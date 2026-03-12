---
artifact_type: plan
bead: Demarch-6qb.8
stage: executing
requirements:
  - Separate agent loop library from OODARC workflow engine
---
# Skaffen: Agent Loop Separation Plan

**Bead:** Demarch-6qb.8
**PRD:** docs/prds/2026-03-12-skaffen-agentloop-separation.md
**Goal:** Extract universal Decide→Act loop into `internal/agentloop/`, leave OODARC workflow in `internal/agent/`.

## Prior Learnings

- `docs/solutions/patterns/go-map-iteration-non-determinism.md` — Sort map keys when deterministic output matters (tool registry iteration)

---

## Must-Haves

**Truths:**
- `agentloop.Loop.Run(ctx, task)` executes a complete conversation without any phase references
- `agent.Agent.Run(ctx, task)` produces identical output and behavior to pre-refactor code
- All 295 existing tests pass without modification (except import path updates)
- `SelectionHints` has Phase as an optional string field, not a required typed enum

**Key Links:**
- agentloop imports: `provider`, nothing from `agent` or `tool` (for phase types)
- agent imports: `agentloop`, `tool` (for phase constants)
- TUI imports: `agent` (unchanged)

---

### Task 1: Create agentloop package with core types

**Files:**
- Create: `os/Skaffen/internal/agentloop/types.go`
- Create: `os/Skaffen/internal/agentloop/types_test.go`

Move from `agent/deps.go` and `agent/streaming.go` into `agentloop/types.go`:
- `SelectionHints` struct (new — Phase string, Urgency string, TaskType string)
- `PromptHints` struct (new — Phase string, Budget int, Model string)
- `Router` interface with `SelectModel(hints SelectionHints)` (not phase)
- `Session` interface with `SystemPrompt(hints PromptHints)` (not phase)
- `Emitter` interface (unchanged)
- `StreamEvent`, `StreamEventType`, `StreamCallback` (moved from streaming.go)
- `ToolApprover` type (moved from agent.go)
- `Turn`, `Evidence` structs (moved from deps.go, phase field becomes string)
- `RunResult` struct (moved from agent.go)
- `BudgetState` struct (moved from router)
- `RenderReporter` interface (moved from deps.go)
- NoOp implementations: `NoOpRouter`, `NoOpSession`, `NoOpEmitter`

Test: `SelectionHints{}` with empty Phase is valid; `NoOpRouter.SelectModel(SelectionHints{})` returns a model.

<verify>
- run: `cd os/Skaffen && go build ./internal/agentloop/`
  expect: exit 0
- run: `cd os/Skaffen && go test ./internal/agentloop/ -v`
  expect: PASS
</verify>

---

### Task 2: Create flat tool registry in agentloop

**Files:**
- Create: `os/Skaffen/internal/agentloop/registry.go`
- Create: `os/Skaffen/internal/agentloop/registry_test.go`

Define a flat (ungated) tool registry:
```go
type Tool interface {
    Name() string
    Description() string
    Schema() json.RawMessage
    Execute(ctx context.Context, params json.RawMessage) ToolResult
}

type ToolResult struct {
    Content string
    IsError bool
}

type ToolDef struct {
    Name        string
    Description string
    InputSchema json.RawMessage
}

type Registry struct {
    tools map[string]Tool
}

func NewRegistry() *Registry
func (r *Registry) Register(t Tool)
func (r *Registry) Tools() []ToolDef           // all registered tools, sorted by name
func (r *Registry) Execute(ctx, name string, input json.RawMessage) ToolResult
func (r *Registry) Get(name string) (Tool, bool)
```

Key: `Tools()` returns sorted by name (deterministic — Go map iteration lesson). `Execute()` returns error ToolResult if tool not found (no phase check).

Test: Register 3 tools, verify Tools() returns sorted; Execute unknown tool returns error.

<verify>
- run: `cd os/Skaffen && go test ./internal/agentloop/ -v`
  expect: PASS
</verify>

---

### Task 3: Create agentloop.Loop — the universal Decide→Act core

**Files:**
- Create: `os/Skaffen/internal/agentloop/loop.go`
- Create: `os/Skaffen/internal/agentloop/loop_test.go`

Extract the Decide→Act core from `agent/loop.go`:

```go
type Loop struct {
    provider  provider.Provider
    registry  *Registry
    router    Router
    session   Session
    emitter   Emitter
    streamCB  StreamCallback
    approver  ToolApprover
    maxTurns  int
    sessionID string
}

type LoopConfig struct {
    Hints SelectionHints  // passed to Router.SelectModel and Session.SystemPrompt
}

func New(p provider.Provider, reg *Registry, opts ...Option) *Loop
func (l *Loop) Run(ctx context.Context, task string) (*RunResult, error)
func (l *Loop) SetStreamCallback(cb StreamCallback)
func (l *Loop) SetToolApprover(fn ToolApprover)
```

The `Run()` method implements the Decide→Act core loop from loop.go:
1. **Orient**: Call `router.SelectModel(config.Hints)`, get tools from `registry.Tools()`, build system prompt via `session.SystemPrompt(PromptHints{...})`
2. **Decide**: Call `provider.Stream()` with messages + tools + config
3. **Act**: Execute tool calls via `registry.Execute()` (with approver gate)
4. **Record**: Emit evidence, save turn to session
5. Repeat until `StopReason == "end_turn"` or max turns

This is a direct extraction — the logic is identical to the current loop.go minus the `phase` parameter threading. The Hints struct carries optional phase info for consumers that need it.

Test: Create Loop with mock provider that returns end_turn after 1 message. Verify Run() returns RunResult.

<verify>
- run: `cd os/Skaffen && go test ./internal/agentloop/ -v`
  expect: PASS
</verify>

---

### Task 4: Create GatedRegistry in agent package

**Files:**
- Create: `os/Skaffen/internal/agent/gated_registry.go`
- Create: `os/Skaffen/internal/agent/gated_registry_test.go`

Wrap `agentloop.Registry` with phase gating:

```go
type GatedRegistry struct {
    inner *agentloop.Registry
    gates map[string]map[string]bool  // phase → {tool name → allowed}
}

func NewGatedRegistry(inner *agentloop.Registry, gates map[string]map[string]bool) *GatedRegistry
func (g *GatedRegistry) Tools(phase string) []agentloop.ToolDef  // filtered by phase
func (g *GatedRegistry) Execute(ctx context.Context, phase, name string, input json.RawMessage) agentloop.ToolResult
```

Migrate the default gate matrix from `tool/registry.go`:
```go
var DefaultGates = map[string]map[string]bool{
    "brainstorm": {"read": true, "glob": true, "grep": true, "ls": true},
    "plan":       {"read": true, "glob": true, "grep": true, "ls": true},
    "build":      {"read": true, "write": true, "edit": true, "bash": true, "grep": true, "glob": true, "ls": true},
    "review":     {"read": true, "glob": true, "grep": true, "ls": true, "bash": true},
    "ship":       {"read": true, "glob": true, "ls": true, "bash": true},
}
```

Test: Register tools, create gated registry. Verify `Tools("brainstorm")` excludes "write"; `Execute("brainstorm", "write", ...)` returns error.

<verify>
- run: `cd os/Skaffen && go test ./internal/agent/ -v -run TestGated`
  expect: PASS
</verify>

---

### Task 5: Refactor agent.Agent to wrap agentloop.Loop [x]

**Files:**
- Modify: `os/Skaffen/internal/agent/agent.go`
- Modify: `os/Skaffen/internal/agent/loop.go`
- Modify: `os/Skaffen/internal/agent/deps.go`
- Delete (or empty): `os/Skaffen/internal/agent/streaming.go` (moved to agentloop)

Refactor Agent to embed/delegate to agentloop.Loop:

```go
type Agent struct {
    loop    *agentloop.Loop
    gated   *GatedRegistry
    fsm     *phaseFSM
    // ... other agent-specific fields
}

func (a *Agent) Run(ctx context.Context, task string) (*agentloop.RunResult, error) {
    phase := a.fsm.Current()
    // Build hints from current phase
    hints := agentloop.SelectionHints{Phase: string(phase)}
    // Configure loop with phase-filtered tools and hints
    // ...delegate to a.loop.Run() with appropriate config
}
```

The key insight: Agent.Run() translates phase → SelectionHints before each loop invocation. The loop itself is phase-agnostic.

**Critical**: `deps.go` should re-export types from agentloop where needed (or update all imports). The Router/Session interfaces in deps.go become thin adapters that translate the old phase-based API to the new hints-based API.

Test: All existing agent tests must pass (import path changes may be needed).

<verify>
- run: `cd os/Skaffen && go test ./internal/agent/ -v`
  expect: PASS
</verify>

---

### Task 6: Update router to use SelectionHints [x] (no-op — adapter pattern handles bridge)

**Files:**
- Modify: `os/Skaffen/internal/router/router.go`
- Modify: `os/Skaffen/internal/router/config.go`

Change `SelectModel(phase tool.Phase)` to `SelectModel(hints agentloop.SelectionHints)`:
- Extract `hints.Phase` (string) where phase was previously typed
- Phase defaults map uses string keys instead of `tool.Phase` constants
- Budget degradation and complexity classification unchanged (they don't use phase)
- IC integration passes `hints.Phase` to `RecordDecision`

Router already has the agentloop.Router interface shape — this is mostly a type signature change.

Test: All existing router tests pass with string phases instead of typed constants.

<verify>
- run: `cd os/Skaffen && go test ./internal/router/ -v`
  expect: PASS
</verify>

---

### Task 7: Update session to use PromptHints [x] (no-op — adapter pattern handles bridge)

**Files:**
- Modify: `os/Skaffen/internal/session/session.go`

Change `SystemPrompt(phase tool.Phase, budget int)` to `SystemPrompt(hints agentloop.PromptHints)`:
- Extract `hints.Phase`, `hints.Budget`, `hints.Model` where needed
- Session already builds prompts from string interpolation — phase is already used as a string in templates

Test: All existing session tests pass.

<verify>
- run: `cd os/Skaffen && go test ./internal/session/ -v`
  expect: PASS
</verify>

---

### Task 8: Update tool package — remove phase from core Tool interface [x] (no-op — Option B: tool.Phase stays)

**Files:**
- Modify: `os/Skaffen/internal/tool/tool.go`
- Modify: `os/Skaffen/internal/tool/registry.go`

The `tool.Tool` interface stays as-is (it doesn't have phase). The `tool.Phase` type and `tool.Registry` with phase gating become thin wrappers or are superseded by `agentloop.Registry` + `agent.GatedRegistry`.

Options:
- A) Keep `tool/` package for tool implementations only, move `Phase` to agent package
- B) Keep backward compatibility — `tool.Phase` stays, `agentloop` uses strings

Choose B for minimum disruption: `tool.Phase` stays as a typed string, `agentloop` uses plain strings, agent package converts between them.

Test: All tool tests pass.

<verify>
- run: `cd os/Skaffen && go test ./internal/tool/ -v`
  expect: PASS
</verify>

---

### Task 9: Integration test — verify full stack [x] (333 tests, 14 packages)

**Files:**
- Run: all tests across all packages

Verify the complete test suite passes:
```bash
cd os/Skaffen && go test ./... -count=1
```

Expected: 295+ tests pass (original 295 plus new agentloop tests).

Also verify:
- TUI tests still compose correctly with the refactored Agent
- Agent tests exercise the OODARC phased workflow through the new GatedRegistry
- agentloop tests verify the universal loop works without phases

<verify>
- run: `cd os/Skaffen && go test ./... -count=1`
  expect: all packages PASS
</verify>

---

### Task 10: Commit and push

Stage all changes, commit with conventional message, push.

<verify>
- run: `cd os/Skaffen && go vet ./...`
  expect: exit 0
</verify>
