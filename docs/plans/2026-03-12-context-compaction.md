# Plan: Context Compaction

**Bead:** Demarch-6i0.3
**Stage:** executed

## Overview

Add `/compact` command for session context compaction — compresses old conversation turns into a summary to free context window space. Matches Claude Code's `/compact` behavior.

## Tasks

### Task 1: Add Compact method to session
**Files:** `internal/session/session.go`

Add a `Compact(summary string)` method that replaces old messages with a single summary message:

```go
func (s *JSONLSession) Compact(summary string) (before, after int) {
    s.mu.Lock()
    defer s.mu.Unlock()
    before = len(s.messages)
    // Replace all messages with a single user message containing the summary
    s.messages = []provider.Message{
        {Role: provider.RoleUser, Content: []provider.ContentBlock{
            {Type: "text", Text: "[Context summary from earlier conversation]\n\n" + summary},
        }},
    }
    after = len(s.messages)
    return
}
```

Also add `MessageCount() int` getter.

### Task 2: Repurpose /compact command
**Files:** `internal/tui/commands.go`

Change `/compact` from "toggle display mode" to "session compaction":

```go
case "compact":
    if m.agent == nil {
        return CommandResult{Message: "No agent configured.", IsError: true}
    }
    return m.execCompact()
```

Add `execCompact()`:
1. Get current context % and message count
2. Build a summary of the conversation by asking the agent to summarize
3. If no agent, just do aggressive truncation (keep last 4 messages)
4. Call `session.Compact(summary)`
5. Report before/after context %

Simpler MVP approach (no LLM summarization — that requires a separate API call):
- Just aggressively truncate to keep only the last N messages (configurable via settings)
- Show before/after message counts
- Report freed context

Update KnownCommands to reflect new meaning.

### Task 3: Add auto-compact setting
**Files:** `internal/tui/settings.go`

Add `AutoCompact` bool and `CompactThreshold` int (default 80%) to settings.
When context % exceeds threshold after a turn, auto-trigger compaction.

### Task 4: Wire auto-compact into app.go
**Files:** `internal/tui/app.go`

In the `StreamTurnComplete` handler, after updating `contextPct`, check if auto-compact should trigger.

### Task 5: Tests
**Files:** `internal/session/session_test.go`, `internal/tui/commands_test.go`

- Test `Compact()` replaces messages correctly
- Test `/compact` command works without agent
- Test auto-compact trigger logic

## Execution Order

1 → 2 → 3 → 4 → 5

## Verification

```bash
go test ./internal/... -count=1
go vet ./...
go build ./cmd/skaffen
```
