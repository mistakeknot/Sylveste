# Plan: Skaffen Plan Mode

**Bead:** Demarch-6i0.21
**PRD:** [docs/prds/2026-03-12-skaffen-plan-mode.md](../prds/2026-03-12-skaffen-plan-mode.md)
**Estimated effort:** 5.5 hours (3 features, 8 tasks)
**Review:** Reviewed by fd-architecture, fd-correctness, fd-quality (2026-03-12)

## Architecture Summary

Plan mode is a toggleable restriction that forces the agent to use read-only tools regardless of OODARC phase. It's orthogonal to the phase FSM — the phase continues to progress normally, but tool access is clamped to `{read, glob, grep, ls}`.

**Key design decisions:**
- Plan mode is NOT a phase — it's a boolean overlay on the gate map
- Phase FSM doesn't need modification; toggle can happen between runs
- Plan mode state lives on `tool.Registry` (the actual runtime gate owner)
- Toggle is guarded on `!m.running` — no mid-run switching, no synchronization needed
- System prompt reflects plan mode via `PromptHints` (prevents model from looping on unavailable tools)

## Review Findings Incorporated

| # | Finding | Resolution |
|---|---------|------------|
| 1 | Wrong registry — plan targeted `agent.GatedRegistry` but `Agent.Run` uses `tool.Registry` | **Fixed**: all gate changes now on `internal/tool/registry.go` |
| 2 | Data race on planMode bool (TUI goroutine vs agent goroutine) | **Fixed**: toggle guarded on `!m.running`; no concurrent access |
| 3 | Mid-run toggle shows PLAN badge but agent still has write tools | **Fixed**: same `!m.running` guard prevents inconsistency |
| 4 | System prompt must reflect plan mode | **Fixed**: threaded through `PromptHints` |
| 5 | Naming: `ReadOnlyGates` > `PlanModeGates` | **Fixed**: renamed |
| 6 | Error message too UI-specific for agent package | **Fixed**: context-free message in tool package |
| 7 | Remove `WithPlanMode` constructor option | **Fixed**: use `SetPlanMode` post-construction only |
| 8 | Remove redundant planMode on Agent | **Fixed**: registry owns state, Agent delegates |
| 9 | `agent.DefaultGates` may be dead code | **Deferred**: out of scope, tracked separately |

## Files Changed

| File | Change | Feature |
|------|--------|---------|
| `internal/tool/registry.go` | Add `planMode` field, `SetPlanMode()`, read-only gate override | F1 |
| `internal/tool/registry_test.go` | Tests for plan mode gate switching | F1 |
| `internal/agent/agent.go` | Add `SetPlanMode()` + `PlanMode()` that delegate to registry | F1 |
| `internal/agent/agent_test.go` | Test for SetPlanMode delegation | F1 |
| `cmd/skaffen/main.go` | Add `--plan-mode` flag, call `SetPlanMode` after construction | F1 |
| `internal/tui/app.go` | Shift+Tab handler (guarded on `!m.running`), status update | F2 |
| `internal/tui/status.go` | PLAN badge in status bar | F2 |
| `internal/tui/app_test.go` | Tests for toggle keybinding and state | F2 |
| `internal/agentloop/types.go` | Add `PlanMode bool` to `PromptHints` | F3 |
| `internal/agent/agent.go` | Pass `PlanMode` in `LoopConfig.Hints` | F3 |
| `internal/session/session.go` | Append plan-mode clause when `hints.PlanMode` | F3 |
| `internal/session/session_test.go` | Test plan mode prompt injection | F3 |

## Tasks

### F1: Plan mode gates (Demarch-29jt)

#### Task 1.1: tool.Registry plan mode support
**File:** `internal/tool/registry.go`
**Do:**
- Add `planMode bool` field to `Registry`
- Add `SetPlanMode(on bool)` method
- Add `PlanMode() bool` getter
- Define read-only tool set: `var readOnlyTools = map[string]bool{"read": true, "glob": true, "grep": true, "ls": true}`
- Modify `Tools(phase)`: when `planMode`, filter to `readOnlyTools` instead of phase gates
- Modify `Execute(ctx, phase, name, params)`: when `planMode` and tool not in `readOnlyTools`, return error `"tool %q not available in plan mode (read-only)"`

**Verify:** `go test ./internal/tool/ -run TestRegistry -count=1`

#### Task 1.2: tool.Registry plan mode tests
**File:** `internal/tool/registry_test.go`
**Do:**
- Test: plan mode blocks write/edit/bash tools via `Tools()` (not returned)
- Test: plan mode blocks write/edit/bash tools via `Execute()` (error result)
- Test: plan mode allows read/glob/grep/ls
- Test: `SetPlanMode(false)` restores normal gate behavior
- Test: table-driven completeness — iterate all phases, assert write/edit/bash absent when plan mode on
- Test: MCP tools registered via `RegisterForPhases` are also blocked in plan mode

**Verify:** `go test ./internal/tool/ -run TestPlanMode -count=1`

#### Task 1.3: Agent SetPlanMode delegation
**File:** `internal/agent/agent.go`
**Do:**
- Add `SetPlanMode(on bool)` method — delegates to `a.registry.SetPlanMode(on)`
- Add `PlanMode() bool` getter — delegates to `a.registry.PlanMode()`
- In `Run()`: pass `a.registry.PlanMode()` into `LoopConfig.Hints` (done in F3)
- No `planMode` field on Agent — registry is single source of truth

**Verify:** `go test ./internal/agent/ -run TestSetPlanMode -count=1`

#### Task 1.4: CLI flag
**File:** `cmd/skaffen/main.go`
**Do:**
- Add `flagPlanMode = flag.Bool("plan-mode", false, "Start in read-only plan mode")`
- In `runTUI()` and `runPrint()`: after `agent.New(...)`, if `*flagPlanMode`, call `a.SetPlanMode(true)`
- In `runPrint()`: if plan mode, print `"skaffen: plan mode (read-only)\n"` to stderr

**Verify:** `echo "list files" | go run ./cmd/skaffen --mode print --plan-mode 2>&1 | grep -q "plan mode"`

### F2: TUI toggle (Demarch-c2k)

#### Task 2.1: Shift+Tab keybinding and app state
**File:** `internal/tui/app.go`
**Do:**
- In `Update()` key handler, add `tea.KeyShiftTab` case
- Guard: `if m.running { break }` — cannot toggle mid-run
- When not running: call `m.agent.SetPlanMode(!m.agent.PlanMode())` to toggle
- Add system message to chat viewport: "Plan mode enabled — read-only tools only" or "Plan mode disabled — full tools available"
- Trigger status bar refresh

**Verify:** Unit test with simulated Shift+Tab key event (agent not running)

#### Task 2.2: Status bar plan mode badge
**File:** `internal/tui/status.go`
**Do:**
- Add `planMode bool` parameter to `updateStatusSlots()`
- When plan mode active, prepend `"PLAN "` to phase value (e.g., `"PLAN build"`) with `c.Info.Color()` (blue accent)
- Update all call sites of `updateStatusSlots()` to pass plan mode state

**Verify:** Visual inspection via `go run ./cmd/skaffen --plan-mode`

### F3: System prompt injection (Demarch-nbvj)

#### Task 3.1: PromptHints plan mode field
**File:** `internal/agentloop/types.go`
**Do:**
- Add `PlanMode bool` to `PromptHints` struct

**File:** `internal/agent/agent.go`
**Do:**
- In `Run()`, set `config.Hints.PlanMode = a.PlanMode()` (snapshot at run start)

**Verify:** `go vet ./internal/agentloop/ ./internal/agent/`

#### Task 3.2: Session plan mode prompt clause
**File:** `internal/session/session.go`
**Do:**
- In `SystemPrompt(phase, budget)`: accept plan mode via the sessionAdapter bridge
- Actually: the sessionAdapter receives `PromptHints` from agentloop, so update `sessionAdapter.SystemPrompt()` in `agent.go` to forward `hints.PlanMode` to the session
- Add `PlanMode bool` parameter or use a separate method on Session interface
- Simplest approach: check if session implements an optional `PlanModePrompter` interface; if so, call it
- Append: `"\n\nYou are in plan mode (read-only). Explore, analyze, and explain. You cannot modify files or run commands."`

**File:** `internal/session/session_test.go`
**Do:**
- Test: plan mode prompt appended when plan mode active
- Test: prompt unchanged when plan mode inactive

**Verify:** `go test ./internal/session/ -run TestPlanMode -count=1`

## Execution Order

```
Task 1.1 → Task 1.2 → Task 1.3 → Task 1.4  (F1: sequential, builds on tool.Registry)
                                       ↓
                              Task 2.1 → Task 2.2  (F2: needs Agent.SetPlanMode from F1)
                              Task 3.1 → Task 3.2  (F3: needs F1, parallel with F2)
```

F2 and F3 can run in parallel after F1 completes.

## Test Plan

1. **Unit tests:** Each task has a verify command
2. **Integration:** `go test ./... -count=1` from `os/Skaffen/`
3. **Race detector:** `go test -race ./internal/tool/ ./internal/agent/` — must pass clean
4. **Manual TUI test:**
   - Start with `--plan-mode`, verify write tools rejected
   - Start normally, press Shift+Tab while idle, verify toggle works
   - Press Shift+Tab while agent running — should be ignored
   - Verify status bar shows PLAN badge
5. **Headless test:** `echo "write a file" | go run ./cmd/skaffen --mode print --plan-mode` — should refuse

## Lessons Learned (from plan review)

- `agent.GatedRegistry` wraps `agentloop.Registry` but is NOT used by `Agent.Run` — the real gate owner is `tool.Registry`. Any future tool access work must target `tool.Registry`.
- `agent.DefaultGates` appears to duplicate `tool.defaultGates` and may be dead code. Track separately.
- The TUI's `m.running` guard pattern is the standard way to prevent concurrent access to agent state during runs — no need for mutexes/atomics when the toggle is simply disallowed mid-run.
