---
artifact_type: brainstorm
bead: Sylveste-p23
stage: discover
---

# ScopedSession — Context Isolation with Selective Injection

**Bead:** Sylveste-p23

## Current State

`ScopedSession` already exists in `os/Skaffen/internal/subagent/session.go` with basic functionality:
- Implements `agentloop.Session` interface (SystemPrompt, Save, Messages)
- Template expansion with `{{.TaskPrompt}}` and `{{.InjectedContext}}` placeholders
- Isolated message history (subagent messages don't pollute parent)

Created as part of the subagent system sprint (Sylveste-6i0.18). The runner instantiates it at `runner.go:114`.

## Gaps vs PRD F3 Acceptance Criteria

Three capabilities are missing:

### 1. `{{.BeadDescription}}` template placeholder

The PRD specifies three placeholders: `{{.TaskPrompt}}`, `{{.InjectedContext}}`, `{{.BeadDescription}}`. Only the first two exist. Bead descriptions provide domain awareness — the subagent knows what issue it's working on.

**Approach:** Add `beadDescription` as a fourth parameter to `NewScopedSession` and expand it in the template. The caller (runner.go) passes it from the task or from a bead lookup.

**Alternative considered:** Make template expansion generic (map[string]string of replacements). Rejected because the three placeholders are fixed by the PRD and a generic approach adds complexity without benefit — we know exactly which variables subagents need.

### 2. Token-capped injection

Currently `InjectedContext` is unbounded — a parent could inject the entire conversation history (50k+ tokens). The PRD specifies a configurable cap (default: 4096 tokens).

**Design decisions:**

- **Token counting:** Use a simple byte-based heuristic (4 chars ≈ 1 token) rather than importing a tokenizer. Exact counts don't matter — the cap is a safety rail, not a billing boundary. This avoids adding a tiktoken dependency.

- **Truncation strategy:** Truncate from the beginning of injected context, keeping the most recent content. Rationale: recent messages are more relevant than earlier ones. Add a `[...truncated N tokens...]` marker at the start so the subagent knows context was cut.

- **Where to enforce:** In `NewScopedSession` before template expansion. The cap applies to the raw injected context string, not the final expanded prompt (which also includes system prompt + task prompt). This keeps the cap predictable — you know exactly how much context you're injecting regardless of template size.

- **Configuration:** Default 4096 tokens (≈16KB). Configurable per `SubagentType` via a new `ContextTokenCap` field. Zero means use default.

### 3. Selected parent messages (structured injection)

The PRD says: "parent can pass selected messages, bead descriptions, file contents." Currently `InjectedContext` is a flat string. This works but loses structure — the subagent can't distinguish between a file content block and a conversation excerpt.

**Approach:** Keep the flat string interface for `NewScopedSession` but add a helper function `BuildInjectedContext` that formats structured inputs into a well-delimited string:

```go
type ContextSource struct {
    Label   string            // e.g., "Parent conversation", "File: main.go"
    Content string
}

func BuildInjectedContext(sources []ContextSource) string
```

Each source is rendered as:
```
--- <Label> ---
<Content>
```

This preserves the simple `NewScopedSession(template, task, context string)` signature while giving callers a structured way to build context. The subagent sees labeled sections it can reason about.

**Alternative considered:** Make `InjectedContext` a `[]ContextSource` and expand them inside `SystemPrompt()`. Rejected because it couples the session to a specific context format. The flat string approach lets any caller inject any format.

## What We're NOT Changing

- **Session interface:** `agentloop.Session` stays as-is (SystemPrompt, Save, Messages). No new methods.
- **Runner integration:** The runner creates `ScopedSession` the same way (just with an additional bead description parameter).
- **Template syntax:** Keep `{{.Placeholder}}` — no need for Go's text/template since we have exactly 3 known placeholders and simple string replacement is faster and safer.
- **Message history:** Stays isolated. No mechanism to "export" subagent messages back to parent (that's the runner's job via SubagentResult.Response).

## Implementation Shape

1. Add `{{.BeadDescription}}` expansion to `NewScopedSession` (new parameter)
2. Add `ContextTokenCap` field to `SubagentType` (default 4096)
3. Add token-cap enforcement in `NewScopedSession` with truncation
4. Add `BuildInjectedContext([]ContextSource) string` helper
5. Update runner.go to pass bead description
6. Tests for all new behavior: cap enforcement, truncation marker, bead description expansion, BuildInjectedContext formatting

## Open Questions (Resolved)

1. **Should the token cap apply per-source or to the total?** Total — per-source caps add complexity and the subagent doesn't care which source was truncated. The caller can pre-filter sources if they care about relative weight.

2. **Should we support message-level injection (pass []provider.Message)?** No. Subagents use their own message format. Injecting raw parent messages would require format conversion and creates coupling. The string-based approach is universal.
