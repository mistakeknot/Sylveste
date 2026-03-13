---
artifact_type: plan
bead: Demarch-p23
stage: plan
---

# Plan: ScopedSession — Context Isolation with Selective Injection

**Bead:** Demarch-p23
**Parent PRD:** docs/prds/2026-03-12-skaffen-subagent-system.md (F3)
**Complexity:** 3/5 (moderate)

## Overview

Enhance the existing `ScopedSession` in `os/Skaffen/internal/subagent/session.go` with three missing capabilities: `{{.BeadDescription}}` template placeholder, token-capped context injection, and a structured context builder helper.

## Steps

### Step 1: Add BeadDescription placeholder and token cap to ScopedSession

**File:** `os/Skaffen/internal/subagent/session.go`

Changes:
1. Add `DefaultContextTokenCap = 4096` constant
2. Change `NewScopedSession` signature to accept `ScopedSessionConfig` struct instead of 3 positional strings:
   ```go
   type ScopedSessionConfig struct {
       PromptTemplate  string
       TaskPrompt      string
       InjectedContext string
       BeadDescription string
       ContextTokenCap int // 0 = use DefaultContextTokenCap
   }
   ```
3. Add `{{.BeadDescription}}` expansion alongside existing placeholders
4. Add `truncateToTokenCap(s string, cap int) string` that:
   - Uses 4-chars-per-token heuristic
   - Truncates from the beginning, keeping the tail (most recent context)
   - Prepends `[...truncated ~N tokens...]` marker when truncation occurs
5. Apply token cap to `InjectedContext` before template expansion

**Why struct:** The constructor now has 4 string parameters plus an int — positional args become error-prone. A config struct makes call sites self-documenting and future-proof.

### Step 2: Add BuildInjectedContext helper

**File:** `os/Skaffen/internal/subagent/session.go` (same file, it's small)

Add:
```go
type ContextSource struct {
    Label   string
    Content string
}

func BuildInjectedContext(sources []ContextSource) string
```

Formats each source as `--- <Label> ---\n<Content>\n\n`. Returns concatenated string. Empty sources are skipped. Empty label uses "Context".

### Step 3: Update runner.go to use new API

**File:** `os/Skaffen/internal/subagent/runner.go`

Change line ~114 from:
```go
sess := NewScopedSession(st.SystemPrompt, task.Prompt, task.InjectedContext)
```
to:
```go
sess := NewScopedSession(ScopedSessionConfig{
    PromptTemplate:  st.SystemPrompt,
    TaskPrompt:      task.Prompt,
    InjectedContext: task.InjectedContext,
    BeadDescription: task.BeadDescription,
    ContextTokenCap: st.ContextTokenCap,
})
```

### Step 4: Add ContextTokenCap to SubagentType and BeadDescription to SubagentTask

**File:** `os/Skaffen/internal/subagent/types.go`

- Add `ContextTokenCap int \`toml:"context_token_cap"\`` to `SubagentType` struct
- Add `BeadDescription string` to `SubagentTask` struct

### Step 5: Update Agent tool schema

**File:** `os/Skaffen/internal/subagent/tool.go`

Add `bead_description` to the Agent tool's input schema (optional field). The tool passes it through to `SubagentTask.BeadDescription`.

### Step 6: Tests

**File:** `os/Skaffen/internal/subagent/session_test.go`

Add tests:
1. `TestScopedSession_BeadDescription` — verifies `{{.BeadDescription}}` expansion
2. `TestScopedSession_TokenCap_Truncates` — inject >4096 tokens worth of context, verify truncation + marker
3. `TestScopedSession_TokenCap_NoTruncation` — inject <4096 tokens, verify no truncation
4. `TestScopedSession_TokenCap_Zero_UsesDefault` — ContextTokenCap=0 uses DefaultContextTokenCap
5. `TestBuildInjectedContext` — verify formatting with multiple sources
6. `TestBuildInjectedContext_EmptyLabel` — verify default label
7. `TestBuildInjectedContext_SkipsEmpty` — empty content sources are skipped
8. Update existing 3 tests to use `ScopedSessionConfig` struct

## Verification

```bash
cd os/Skaffen && go test ./internal/subagent/ -count=1 -run TestScopedSession
cd os/Skaffen && go test ./internal/subagent/ -count=1 -run TestBuildInjected
cd os/Skaffen && go vet ./internal/subagent/
cd os/Skaffen && go build ./...
```

## Not In Scope

- Token counting with a real tokenizer (byte heuristic is sufficient)
- Per-source token caps (total cap only)
- Message-level injection (string-based only)
- Changes to agentloop.Session interface
