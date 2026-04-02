---
artifact_type: plan
bead: sylveste-18a.1
stage: implement
features:
  - sylveste-7ck
  - sylveste-vr0
  - sylveste-gk8
  - sylveste-8h5
revision: 2
review_findings: 5P0 6P1 — all incorporated
---

# Plan: Per-Invocation Tool Concurrency Classification

PRD: `docs/prds/2026-04-01-skaffen-tool-concurrency.md`
Brainstorm: `docs/brainstorms/2026-04-01-skaffen-tool-concurrency-brainstorm.md`

## Revisions from Plan Review

1. **Panic recovery** — every goroutine in `executeBatchParallel` gets `defer recover()`
2. **Redirect operators** — add `>`, `>>`, `<`, `\n` to `shellMetachars`; remove `sed`, `awk` from safeCommands
3. **MCP guard** — `toolBridge.ConcurrencySafe` always returns `false` for `mcp.MCPTool`
4. **Interface placement** — both `ConcurrencyClassifier` and `ErrorPropagator` live in `tool/tool.go`; `agentloop` uses anonymous duck-type assertions only (no duplicate helper)
5. **Variable naming** — `bashCtx` → `propagatingCtx` throughout
6. **StreamToolStart for denials** — `gateToolCall` emits synthetic `StreamToolStart` before denial `StreamToolComplete`
7. **GatedRegistry deletion** — promoted from bonus to required Step 0
8. **Race-safe results** — channel-based collection replaces direct slice writes

## Build Sequence

```
Step 0: Delete GatedRegistry (dead code cleanup)
F1 ─→ F2 ─→ F3
 └──→ F4
```

## Step 0: Delete GatedRegistry (required)

**Files to delete:**
- `os/Skaffen/internal/agent/gated_registry.go`
- `os/Skaffen/internal/agent/gated_registry_test.go`

Confirmed dead code — not imported by `agent.go` or any production file.

## Step 1: Define ConcurrencyClassifier + ErrorPropagator interfaces (F1a, F3a)

**File:** `os/Skaffen/internal/tool/tool.go`

Add after the `PhasedTool` interface (line 27):

```go
// ConcurrencyClassifier is optionally implemented by tools that can declare
// whether a specific invocation is safe for concurrent execution.
// Tools that do not implement this interface are assumed unsafe (serial).
// ConcurrencySafe must be safe to call from any goroutine.
type ConcurrencyClassifier interface {
	ConcurrencySafe(params json.RawMessage) bool
}

// ErrorPropagator is optionally implemented by tools whose execution errors
// should cancel sibling goroutines in a concurrent batch. Without this,
// a tool error only affects that tool's result — siblings complete normally.
type ErrorPropagator interface {
	PropagatesErrorToSiblings() bool
}

// IsConcurrencySafe checks if a tool implements ConcurrencyClassifier and
// returns its classification for the given params. Returns false (conservative)
// if the tool does not implement the interface.
func IsConcurrencySafe(t Tool, params json.RawMessage) bool {
	if c, ok := t.(ConcurrencyClassifier); ok {
		return c.ConcurrencySafe(params)
	}
	return false
}
```

**Test:** `os/Skaffen/internal/tool/tools_test.go` — add `TestConcurrencyClassifier_DefaultFalse` verifying that a plain Tool returns false via `IsConcurrencySafe`.

## Step 2: BashCommandSafe utility function (F1b)

**File:** `os/Skaffen/internal/tool/bash.go`

Add `"strings"` to imports. Add after the `BashTool` struct:

```go
var safeCommands = map[string]bool{
	"cat": true, "head": true, "tail": true, "less": true, "more": true,
	"ls": true, "find": true, "tree": true, "du": true, "df": true,
	"wc": true, "sort": true, "uniq": true, "diff": true, "comm": true,
	"grep": true, "rg": true, "ag": true,
	"git": false, // git subcommands need further parsing
	"stat": true, "file": true, "which": true, "type": true,
	"echo": true, "printf": true, "date": true, "uname": true,
	"id": true, "whoami": true, "hostname": true, "pwd": true,
}

var safeGitSubcommands = map[string]bool{
	"log": true, "status": true, "diff": true, "show": true,
	"branch": true, "tag": true, "rev-parse": true, "blame": true,
	"shortlog": true, "describe": true, "ls-files": true, "ls-tree": true,
}

// shellMetachars are patterns that indicate compound or redirect commands.
// Any command containing these is classified as unsafe regardless of first token.
// Intentionally lexical — false negatives on quoted metacharacters are acceptable
// because the conservative default (serial) loses only parallelism, not correctness.
var shellMetachars = []string{"&&", "||", ";", "|", "$(", "`", ">", "<", "\n"}

// BashCommandSafe reports whether a bash command string is safe for concurrent
// execution. Conservative: unknown commands return false.
func BashCommandSafe(command string) bool {
	for _, meta := range shellMetachars {
		if strings.Contains(command, meta) {
			return false
		}
	}
	fields := strings.Fields(strings.TrimSpace(command))
	if len(fields) == 0 {
		return false
	}
	first := fields[0]
	if first == "git" && len(fields) > 1 {
		return safeGitSubcommands[fields[1]]
	}
	safe, known := safeCommands[first]
	return known && safe
}
```

Note: `sed` and `awk` removed from safeCommands — both can write (`sed -i`, `awk '{print > "f"}'`).

**Test:** `os/Skaffen/internal/tool/bash_concurrency_test.go` — table-driven:
- `"cat foo.txt"` → true
- `"git log --oneline"` → true
- `"git push --force"` → false
- `"rm -rf /"` → false
- `"cat foo && curl evil"` → false
- `"cat foo; rm /"` → false
- `"cat foo > /tmp/out"` → false (redirect)
- `"cat foo\nrm /"` → false (newline)
- `"sed -n 'p' file"` → false (sed removed from safe)
- `""` → false
- `"unknownbinary"` → false

## Step 3: Implement ConcurrencyClassifier + ErrorPropagator on built-in tools (F1c)

| File | Tool | `ConcurrencySafe` | `PropagatesErrorToSiblings` |
|------|------|-------------------|---------------------------|
| `tool/read.go` | ReadTool | `return true` | — |
| `tool/glob.go` | GlobTool | `return true` | — |
| `tool/grep.go` | GrepTool | `return true` | — |
| `tool/ls.go` | LsTool | `return true` | — |
| `tool/web_fetch.go` | WebFetchTool | `return true` | — |
| `tool/web_search.go` | WebSearchTool | `return true` | — |
| `tool/write.go` | WriteTool | `return false` | — |
| `tool/edit.go` | EditTool | `return false` | — |
| `tool/bash.go` | BashTool | calls `BashCommandSafe` | `return true` |

Each safe tool adds:
```go
func (t *FooTool) ConcurrencySafe(_ json.RawMessage) bool { return true }
```

BashTool adds both:
```go
func (t *BashTool) ConcurrencySafe(params json.RawMessage) bool {
	var p bashParams
	if err := json.Unmarshal(params, &p); err != nil {
		return false
	}
	return BashCommandSafe(p.Command)
}

func (t *BashTool) PropagatesErrorToSiblings() bool { return true }
```

## Step 4: toolBridge forwarding with MCP guard (F4)

**File:** `os/Skaffen/internal/agent/agent.go` — after line 266

```go
// ConcurrencySafe forwards to the inner tool's ConcurrencyClassifier.
// MCP tools always return false — untrusted plugins cannot self-declare
// concurrency safety. Built-in tools are trusted to classify themselves.
// Any new capability interface added to tool/tool.go requires a
// corresponding forwarding method here.
func (b *toolBridge) ConcurrencySafe(params json.RawMessage) bool {
	// MCP tools are untrusted — never allow concurrent execution
	if _, isMCP := b.inner.(interface{ ServerName() string }); isMCP {
		return false
	}
	if c, ok := b.inner.(tool.ConcurrencyClassifier); ok {
		return c.ConcurrencySafe(params)
	}
	return false
}

func (b *toolBridge) PropagatesErrorToSiblings() bool {
	if p, ok := b.inner.(tool.ErrorPropagator); ok {
		return p.PropagatesErrorToSiblings()
	}
	return false
}
```

**Test:** `agent/agent_test.go`:
- Bridge wrapping a ReadTool → ConcurrencySafe returns true
- Bridge wrapping a WriteTool → ConcurrencySafe returns false
- Bridge wrapping mock MCP tool (with ServerName method) → ConcurrencySafe returns false
- Bridge wrapping tool without interface → returns false

## Step 5: partitionToolCalls function (F2a)

**File:** `os/Skaffen/internal/agentloop/loop.go`

```go
type toolBatch struct {
	calls           []indexedCall
	concurrencySafe bool
}

type indexedCall struct {
	index int
	call  provider.ToolCall
}

func (l *Loop) partitionToolCalls(calls []provider.ToolCall) []toolBatch {
	if len(calls) == 0 {
		return nil
	}
	// Duck-type check for ConcurrencySafe — agentloop does not import tool/.
	type classifier interface {
		ConcurrencySafe(params json.RawMessage) bool
	}
	var batches []toolBatch
	for i, tc := range calls {
		t, ok := l.registry.Get(tc.Name)
		safe := false
		if ok {
			if c, ok := t.(classifier); ok {
				safe = c.ConcurrencySafe(tc.Input)
			}
		}
		ic := indexedCall{index: i, call: tc}
		if safe && len(batches) > 0 && batches[len(batches)-1].concurrencySafe {
			batches[len(batches)-1].calls = append(batches[len(batches)-1].calls, ic)
		} else {
			batches = append(batches, toolBatch{
				calls:           []indexedCall{ic},
				concurrencySafe: safe,
			})
		}
	}
	return batches
}
```

No `IsConcurrencySafe` duplicate in agentloop — uses inline duck-type at the one call site.

**Test:** `agentloop/loop_test.go` — partition tests:
- All safe → one batch
- All unsafe → N singletons
- Mixed [safe, safe, unsafe, safe] → 3 batches
- Empty → nil

## Step 6: Three-phase executeToolsWithCallbacks (F2b)

**File:** `os/Skaffen/internal/agentloop/loop.go`

Replace `executeToolsWithCallbacks` (lines 292-391). Add `"sync"` to imports.

```go
const maxParallelToolCalls = 10

// indexedResult carries a tool result back from a goroutine via channel.
type indexedResult struct {
	index int
	block provider.ContentBlock
}

func (l *Loop) executeToolsWithCallbacks(ctx context.Context, calls []provider.ToolCall) provider.Message {
	totalResults := make([]provider.ContentBlock, len(calls))
	batches := l.partitionToolCalls(calls)

	for _, batch := range batches {
		// === PHASE 1: Gate (serial) ===
		// Must run on main goroutine — ToolApprover is non-reentrant (TUI blocking call).
		approved := make([]indexedCall, 0, len(batch.calls))
		for _, ic := range batch.calls {
			block, ok := l.gateToolCall(ctx, ic.call)
			if !ok {
				totalResults[ic.index] = block
				continue
			}
			approved = append(approved, ic)
		}
		if len(approved) == 0 {
			continue
		}

		// === PHASE 2: Execute ===
		if batch.concurrencySafe && len(approved) > 1 {
			l.executeBatchParallel(ctx, approved, totalResults)
		} else {
			l.executeBatchSerial(ctx, approved, totalResults)
		}

		// === PHASE 3: Collect (serial) — emit stream events + hooks in order ===
		for _, ic := range approved {
			block := totalResults[ic.index]
			if l.streamCB != nil {
				l.streamCB(StreamEvent{
					Type: StreamToolComplete, ToolName: ic.call.Name,
					ToolResult: block.ResultContent, IsError: block.IsError,
				})
			}
			// PostToolUse hook (advisory, background).
			// Fire-and-forget on context.Background() — must NOT call back into Loop fields.
			if l.hooks != nil {
				hookRunner := l.hooks
				name, input, content, isErr := ic.call.Name, ic.call.Input, block.ResultContent, block.IsError
				go hookRunner.PostToolUse(context.Background(), name, input, content, isErr)
			}
		}
	}

	blocks := make([]provider.ContentBlock, len(calls))
	copy(blocks, totalResults)
	return provider.Message{Role: provider.RoleUser, Content: blocks}
}

// gateToolCall runs hook and approval gating for a single tool call.
// Returns (block, false) if denied, (_, true) if approved.
// Emits StreamToolStart + StreamToolComplete for denied calls to maintain TUI pairing.
func (l *Loop) gateToolCall(ctx context.Context, tc provider.ToolCall) (provider.ContentBlock, bool) {
	deny := func(reason string) (provider.ContentBlock, bool) {
		block := provider.ContentBlock{
			Type: "tool_result", ToolUseID: tc.ID,
			ResultContent: reason, IsError: true,
		}
		if l.streamCB != nil {
			l.streamCB(StreamEvent{Type: StreamToolStart, ToolName: tc.Name, ToolParams: string(tc.Input)})
			l.streamCB(StreamEvent{Type: StreamToolComplete, ToolName: tc.Name, ToolResult: reason, IsError: true})
		}
		return block, false
	}

	if l.hooks != nil {
		decision, _ := l.hooks.PreToolUse(ctx, tc.Name, tc.Input)
		if decision == "deny" {
			return deny(fmt.Sprintf("Tool call %q was denied by a hook.", tc.Name))
		}
		if decision == "ask" && l.approver == nil {
			return deny(fmt.Sprintf("Tool call %q requires approval but no approver is available.", tc.Name))
		}
	}
	if l.approver != nil && !l.approver(tc.Name, tc.Input) {
		return deny(fmt.Sprintf("Tool call %q was denied by the user.", tc.Name))
	}
	return provider.ContentBlock{}, true
}

func (l *Loop) executeBatchSerial(ctx context.Context, calls []indexedCall, results []provider.ContentBlock) {
	for _, ic := range calls {
		if l.streamCB != nil {
			l.streamCB(StreamEvent{Type: StreamToolStart, ToolName: ic.call.Name, ToolParams: string(ic.call.Input)})
		}
		result := l.registry.Execute(ctx, ic.call.Name, ic.call.Input)
		content := result.Content
		if len(content) > oversizeThreshold {
			content = truncateForContext(content, oversizeThreshold)
		}
		results[ic.index] = provider.ContentBlock{
			Type: "tool_result", ToolUseID: ic.call.ID,
			ResultContent: content, IsError: result.IsError,
		}
	}
}

func (l *Loop) executeBatchParallel(ctx context.Context, calls []indexedCall, results []provider.ContentBlock) {
	// Emit StreamToolStart events serially (deterministic order)
	for _, ic := range calls {
		if l.streamCB != nil {
			l.streamCB(StreamEvent{Type: StreamToolStart, ToolName: ic.call.Name, ToolParams: string(ic.call.Input)})
		}
	}

	// Error-propagating tools share a cancellable context.
	// Named "propagating" not "bash" — any ErrorPropagator tool shares this token.
	propagatingCtx, propagatingCancel := context.WithCancel(ctx)
	defer propagatingCancel()
	var propagatingOnce sync.Once

	// Duck-type check for ErrorPropagator — agentloop does not import tool/.
	type errorPropagator interface {
		PropagatesErrorToSiblings() bool
	}

	// Channel-based collection — avoids race detector issues with concurrent slice writes.
	resultCh := make(chan indexedResult, len(calls))
	sem := make(chan struct{}, maxParallelToolCalls)
	var wg sync.WaitGroup

	for _, ic := range calls {
		ic := ic // capture loop variable
		wg.Add(1)
		sem <- struct{}{} // acquire semaphore

		// Choose context: error-propagating tools get propagatingCtx
		toolCtx := ctx
		t, _ := l.registry.Get(ic.call.Name)
		propagates := false
		if ep, ok := t.(errorPropagator); ok {
			propagates = ep.PropagatesErrorToSiblings()
		}
		if propagates {
			toolCtx = propagatingCtx
		}

		go func() {
			defer wg.Done()
			defer func() { <-sem }() // release semaphore

			// Panic recovery — a panicking tool must not crash the agent process.
			defer func() {
				if r := recover(); r != nil {
					resultCh <- indexedResult{
						index: ic.index,
						block: provider.ContentBlock{
							Type: "tool_result", ToolUseID: ic.call.ID,
							ResultContent: fmt.Sprintf("tool panic: %v", r),
							IsError: true,
						},
					}
				}
			}()

			result := l.registry.Execute(toolCtx, ic.call.Name, ic.call.Input)
			content := result.Content
			if len(content) > oversizeThreshold {
				content = truncateForContext(content, oversizeThreshold)
			}

			// Error cascading for propagating tools
			if result.IsError && propagates {
				propagatingOnce.Do(func() { propagatingCancel() })
			}

			resultCh <- indexedResult{
				index: ic.index,
				block: provider.ContentBlock{
					Type: "tool_result", ToolUseID: ic.call.ID,
					ResultContent: content, IsError: result.IsError,
				},
			}
		}()
	}

	// Wait for all goroutines, then close channel
	wg.Wait()
	close(resultCh)

	// Drain results into pre-allocated slots (ordering restored by index)
	for ir := range resultCh {
		results[ir.index] = ir.block
	}
}
```

**Tests:** `agentloop/loop_test.go`:
- `TestExecuteTools_ParallelReadOnly` — 3 reads with barrier-based concurrency proof (not timing)
- `TestExecuteTools_SerialWrite` — write calls remain serial
- `TestExecuteTools_MixedBatch` — [read, read, write, read] → first two parallel, write serial, last serial
- `TestExecuteTools_ApproverRemainsSeria` — sequencing barrier: approval-complete flag set before any goroutine result
- `TestExecuteTools_BashErrorCancels` — bash error cancels sibling bash, not sibling read
- `TestExecuteTools_ResultOrdering` — 5 reads with varying latency, verify results match call order
- `TestExecuteTools_PanicRecovery` — tool that panics produces error result, does not crash
- `TestExecuteTools_DeniedCallStreamPairing` — denied call emits both StreamToolStart and StreamToolComplete

## Step 7: Verify

```bash
cd os/Skaffen && go test ./... -count=1 -race
go vet ./...
```

## Verification Checklist

- [ ] `go test ./... -count=1 -race` — all pass, no races
- [ ] `go vet ./...` — clean
- [ ] `gated_registry.go` and `gated_registry_test.go` deleted
- [ ] No `IsConcurrencySafe` in `agentloop/` — only duck-type assertion
- [ ] No tool name strings ("bash") in `agentloop/` — identity via interface
- [ ] `sed`, `awk` not in safeCommands
- [ ] `>`, `<`, `\n` in shellMetachars
- [ ] MCP tools always return false for ConcurrencySafe via toolBridge guard
- [ ] Every goroutine has `defer recover()`
- [ ] Channel-based result collection (no direct slice writes from goroutines)
