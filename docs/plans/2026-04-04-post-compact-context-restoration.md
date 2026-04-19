---
bead: sylveste-18a.9
type: plan
date: 2026-04-04
---

# Plan: Post-Compact Context Restoration

## Summary

Add a `PostCompactHook` callback to auto-compact config. After compaction, the hook builds a context restoration message from pre-compaction state and injects it. The agent layer wires this to build a `CompactionSummary`-based orientation message.

## Tasks

### Task 1: Add PostCompactHook to AutoCompactConfig

**File:** `internal/agentloop/autocompact.go`

Add:
```go
// PostCompactHook is called after successful compaction to build
// context restoration messages. Receives pre-compaction messages
// and the current phase. Returns messages to prepend after the
// compaction marker (before recent messages).
type PostCompactHook func(preCompact []provider.Message, phase string) []provider.Message
```

Add `PostCompactHook` field to `AutoCompactConfig`.

### Task 2: Call PostCompactHook in autoCompactMessages

**File:** `internal/agentloop/autocompact.go` → `autoCompactMessages()`

After snip succeeds, if `cfg.PostCompactHook != nil`, call it with the pre-compaction messages and inject returned messages after the snip marker (position 1, before recent messages).

Update return signature to accept the hook: add `phase string` parameter.

### Task 3: Wire PostCompactHook in loop.go

**File:** `internal/agentloop/loop.go`

Pass `config.Hints.Phase` to `autoCompactMessages`. The hook is already on the config struct — no new Option needed.

### Task 4: Build orientation hook in agent.go

**File:** `internal/agent/agent.go`

Build a `PostCompactHook` closure that:
1. Scans pre-compaction messages for file operations (tool_use with name=read/write/edit)
2. Extracts the goal from the first user message
3. Returns a single orientation message:
   ```
   [Context restored after compaction]
   Goal: <first user message, truncated to 200 chars>
   Files touched: <deduplicated list from tool calls>
   Phase: <current phase>
   ```

Wire this into the `AutoCompactConfig` passed to `WithAutoCompact()`.

### Task 5: Add integration test

**File:** `internal/agentloop/autocompact_integration_test.go`

Add `TestAutoCompactPostCompactHookInLoop`:
- Config with a PostCompactHook that returns a context message
- Verify the hook is called after compaction
- Verify the returned message appears in the conversation
- Verify the hook receives pre-compaction messages (not post-compaction)

### Task 6: Verify plan mode survives compaction

**File:** `internal/agentloop/loop_test.go` (or manual verification)

Confirm that `LoopConfig.PlanMode` flag passes through to `SystemPrompt(PromptHints{PlanMode: true})` after compaction. Since system prompt is rebuilt every turn, this should already work. Quick test to verify.

## Acceptance Criteria

- [ ] PostCompactHook called after every successful compaction
- [ ] Orientation message injected with goal, files, phase
- [ ] Hook receives pre-compaction messages (full history before elision)
- [ ] Integration test passes
- [ ] All existing tests pass with -race
- [ ] Plan mode works across compaction boundary
