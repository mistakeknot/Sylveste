# Correctness Review: Plan Mode Toggle

**Reviewed by:** Julik (Flux-drive Correctness Reviewer)
**Date:** 2026-03-12
**Scope:** Proposed "read-only plan mode" toggle via Shift+Tab in Skaffen TUI

---

## Invariants

The following must hold at all times. If they cannot be verified, the plan mode feature has a soundness problem.

1. **Tool gate consistency:** The set of tools available to the LLM for a given turn must be determined before the LLM call starts, and must not change between the decision to execute a tool and the execution of that tool within the same turn.
2. **System prompt consistency:** The system prompt sent to the LLM must reflect the mode (plan vs. normal) that was active when the turn started, not some later mode that was toggled mid-flight.
3. **No torn reads:** Any field shared between the TUI goroutine and the agent goroutine must be read atomically or under a lock. A plain `bool` field on a Go struct is not safe for concurrent read/write without synchronization.
4. **Mid-turn gate changes do not corrupt session state:** If a mode toggle occurs while a tool is executing, the completed tool result must still be fed back to the LLM with a consistent tool list, so the model cannot be given results for tools it did not see in the last tool-definition set.

---

## Existing Race in `SetModelOverride` (Pre-existing, Unfixed)

Before analyzing plan mode, note that the existing `/model` command already has this race. `DefaultRouter.SetModelOverride` writes `r.runtimeModel` from the TUI goroutine (inside `Update`) while `DefaultRouter.SelectModel` reads `r.runtimeModel` from the agent goroutine (inside `agentloop.Loop.Run`). There is no mutex, no `sync/atomic`, and no channel handoff. The `-race` detector would fire on this with a simple repro: start a long run, type `/model sonnet`. This pre-existing race does not corrupt persisted data (the value is advisory, a wrong model at one turn is not catastrophic), but it is a real data race by Go's memory model.

Plan mode would land in the same structural position as `runtimeModel` but with a higher blast radius: it controls which tools are offered to the LLM, which directly affects what the agent can and cannot do.

---

## Proposed Design: Where `planMode` Would Live

Based on the problem statement, the most natural implementation would place `planMode bool` on `Agent` (in `os/Skaffen/internal/agent/agent.go`) with accessors `PlanMode() bool` and `SetPlanMode(bool)`. The TUI would call `m.agent.SetPlanMode(...)` from `appModel.Update` (the Bubble Tea goroutine), and `Agent.Run` would read `a.planMode` when calling `buildLoopRegistry` and when constructing `LoopConfig`.

This is a classic TOCTOU across two goroutines on an unsynchronized field.

---

## Finding 1 — Unsynchronized `planMode` Read/Write (Data Race, Production-visible)

**Severity: High.** This will wake you at 3am if the user toggles plan mode while the agent is mid-turn.

### Concrete Interleaving

```
TUI goroutine (appModel.Update)          Agent goroutine (Agent.Run / Loop.Run)
------------------------------------------  ----------------------------------------
                                            [turn N] phase = build
                                            buildLoopRegistry(build) → includes
                                              write, edit, bash  (planMode=false)
                                            sends tool list to LLM
                                            LLM responds with tool_use: edit
User presses Shift+Tab
SetPlanMode(true) writes a.planMode=true
                                            buildLoopRegistry reads a.planMode=true
                                              (this call is for turn N+1 recovery,
                                               but race window is here)

                                            -- OR, more concretely --
                                            [turn N, executeToolsWithCallbacks]
                                            loop begins iterating tool calls
                                            currently executing: edit (allowed)
                                            ... (edit executes, file mutated) ...

SetPlanMode(true) writes a.planMode=true

                                            [turn N+1] buildLoopRegistry reads
                                              a.planMode=true → tool list = {read,
                                              glob, grep, ls} only
                                            new loopReg sent to LLM
                                            LLM still has unresolved tool call IDs
                                            from turn N in its context window
                                            but tool definitions changed
```

The last step produces a subtle semantic inconsistency: the model's conversation history contains `tool_result` blocks for `edit`, but the tool definitions presented in turn N+1 no longer include `edit`. Some model implementations will tolerate this; others will produce confused follow-on reasoning or hallucinate tool availability.

**Root cause:** `a.planMode` is an unsynchronized `bool` written from the TUI goroutine and read from the agent goroutine. Go's memory model gives no guarantee of visibility without synchronization.

**Minimal fix:** Use `sync/atomic.Bool` (Go 1.19+):

```go
import "sync/atomic"

type Agent struct {
    // ...
    planMode atomic.Bool
}

func (a *Agent) PlanMode() bool         { return a.planMode.Load() }
func (a *Agent) SetPlanMode(on bool)    { a.planMode.Store(on) }
```

This is sufficient to eliminate the data race. It does not solve the semantic mid-turn consistency problem described in Finding 2, but it is necessary as a foundation.

---

## Finding 2 — Mid-Turn Tool Gate Change Creates Semantic Inconsistency (Logic Bug)

**Severity: Medium.** No data corruption, but the agent can end up in a confused state.

### What Happens

`buildLoopRegistry` is called once per `Agent.Run` invocation, before `agentloop.Loop.Run` starts. Once the loop is running, the registry is fixed for the entire multi-turn conversation. This means:

- If the user toggles plan mode *between* user submissions (i.e., when `m.running == false`), the toggle takes effect cleanly for the next `Agent.Run` call. No problem.
- If the user toggles plan mode *while the agent is running* (i.e., `m.running == true`), the toggle has no effect on the current run because `loopReg` is already captured. The toggle will take effect on the next submission. This is actually the correct behavior for the current architecture — but only if the toggle is blocked during a run (see Finding 3).

The current TUI already blocks prompt input while running (`if !m.running`), but Shift+Tab is not a prompt submission — it's a key binding. The key handling in `Update` does not check `m.running` before processing arbitrary key events. This means the toggle can be accepted and stored at any time.

The immediate semantic problem: if toggle occurs while running, the TUI immediately shows "plan mode ON" in the status bar, but the agent is still running with write/edit/bash available. The displayed state disagrees with the active state. This is confusing but not catastrophic — the fix is to either:

a. Only allow the toggle when `!m.running` (simplest, clearest semantics), or
b. Accept the toggle and show a deferred "will take effect on next run" message.

Option (a) is strongly recommended.

---

## Finding 3 — Toggle Available During Agent Run: Status Display Invariant Violated

**Severity: Low-Medium.** UX correctness issue.

The TUI currently guards prompt submission behind `m.running`, but it does not guard mode toggles behind that flag. In the key handler in `Update`:

```go
case tea.KeyMsg:
    if msg.String() == "ctrl+c" { ... }
    if m.approving { ... break }
    if m.settingsOpen { ... break }
    if !m.running && !isEscapeFragment(msg) {
        m.prompt, cmd = m.prompt.Update(msg)
        ...
    }
```

Shift+Tab is not currently in the list of guarded keys. Any binding you add for plan mode toggle needs to be explicitly guarded with `if !m.running` to prevent the inconsistency described in Finding 2.

---

## Finding 4 — System Prompt Not Updated for Mode Change Mid-Session (Design Gap)

**Severity: Medium.** The plan mode is meaningless if the LLM is not told about it.

`JSONLSession.SystemPrompt` returns a static `s.prompt` set at construction time. This prompt never changes, regardless of `planMode`. Plan mode enforcement via tool gating is mechanical — the LLM will not receive write/edit/bash in plan mode — but if the system prompt is not updated to say "you are in read-only plan mode", the LLM will be confused when its tool calls return errors.

There are two sub-cases:

**Case A: Toggle before any run starts.**
The system prompt is built once in `cmd/skaffen/main.go` (or wherever `session.New` is called) and passed to `JSONLSession`. If plan mode is set before the first `Agent.Run`, the system prompt must already include the plan-mode instruction, or the agent will try to write files and fail at the tool gate.

**Case B: Toggle mid-session (between runs).**
The system prompt for the next turn will be the same static prompt from construction time. It still says the agent can write files. The agent will try to call `edit`, the gate will return an error, the model will see "tool not available in phase build", and will likely loop or produce garbage reasoning.

**Required fix:** `planMode` must influence the system prompt returned by `sessionAdapter.SystemPrompt`. Either:

1. Pass `planMode` down through `LoopConfig.Hints` (add a field like `PlanMode bool`) and have `sessionAdapter` include a conditional instruction in the system prompt, or
2. Add a `SetPlanMode(bool)` to the `agent.Session` interface and have `JSONLSession` include a conditional paragraph in `SystemPrompt`, or
3. Rebuild the `agentloop.Loop` on each `Agent.Run` with a fresh session adapter that reflects the current `planMode` (this is the current architecture — each `Run` builds a new loop, so if the session's `SystemPrompt` method is dynamic, it works immediately).

Option 3 is actually already supported by the architecture: `sessionAdapter` calls `sa.inner.SystemPrompt(sa.phase(), hints.Budget)` on every turn. If `JSONLSession.SystemPrompt` is made to accept and reflect a `planMode` parameter, it will be updated on every turn. The cleanest approach within the existing adapter pattern is to pass `planMode` via `LoopConfig.Hints` → `PromptHints` → `SystemPrompt`.

---

## Finding 5 — `buildLoopRegistry` Snapshot-at-Start is Actually Correct, but Requires Documentation

**Severity: Informational.**

`Agent.Run` calls `buildLoopRegistry(phase)` once before handing the registry to the loop. This means `planMode` is snapshotted at the start of each `Run` call. This is architecturally sound: the LLM sees a consistent tool list for the entire multi-turn conversation started by a single user submission. The risk is only at the boundary: if `planMode` is toggled concurrently with the `buildLoopRegistry` call (i.e., at the exact start of a new run while `m.running` is transitioning from false to true).

The sequence:

```
TUI goroutine                       Agent goroutine
------------------                  ------------------
submitMsg received
m.running = true
tea.Cmd returned → goroutine starts
                                    Agent.Run enters
                                    buildLoopRegistry reads planMode
```

Between `m.running = true` in the TUI goroutine and the `buildLoopRegistry` read in the agent goroutine, there is a narrow window where a toggle from the TUI could race. This is the same race as Finding 1. With `atomic.Bool`, this window is safe to traverse — the snapshot will be either the old or new value, but it will be consistent within the single `Run` invocation.

Document this explicitly: `SetPlanMode` takes effect on the next `Run`, not mid-turn.

---

## Finding 6 — `GatedRegistry.Execute` Does Not Need to Be Guarded for `planMode`

**Severity: Informational (confirm design).**

The existing `GatedRegistry` in `agent/gated_registry.go` gates by phase, not by `planMode`. It reads `g.gates` which is a `map[string]map[string]bool` set at construction time and never mutated. There is no concurrent write path to `g.gates`, so no race here. The plan mode feature should operate by controlling which registry is built (via `buildLoopRegistry` choosing a different tool set), not by mutating `GatedRegistry.gates` at runtime.

Do not add a `SetPlanMode` to `GatedRegistry` that swaps the gates map at runtime. That would be a different and worse design — it would allow mid-turn gate changes and require its own mutex. The current "build a new flat registry per run" approach is the correct one; just make sure `planMode` is read atomically at that moment.

---

## Finding 7 — `SetModelOverride` on `DefaultRouter` Is an Existing Undetected Race (Pre-existing)

**Severity: Medium (pre-existing, not introduced by plan mode).**

For completeness: `DefaultRouter.runtimeModel` is a plain `string` field. The TUI calls `a.router.(ModelOverrideSetter).SetModelOverride(alias)` inside `Update`, and the agent goroutine calls `r.SelectModel(phase)` which reads `r.runtimeModel`. These execute concurrently with no mutex. This is a data race. A string write is not atomic in Go's memory model.

Fix: wrap `runtimeModel` in `sync/atomic.Value` or guard `SelectModel` and `SetModelOverride` with a mutex. Since this review is focused on plan mode, I flag it for tracking but do not elaborate further.

---

## Summary Table

| # | Finding | Severity | File(s) Affected | Fix |
|---|---------|----------|------------------|-----|
| 1 | Unsynchronized `planMode` read/write | High (data race) | `agent/agent.go` | `sync/atomic.Bool` |
| 2 | Mid-turn toggle causes tool list / system prompt mismatch | Medium | `tui/app.go`, `agent/agent.go` | Block toggle while `m.running` |
| 3 | Toggle key not guarded by `!m.running` | Low-Medium | `tui/app.go` | Add `!m.running` guard |
| 4 | System prompt not updated to reflect plan mode | Medium | `session/session.go`, `agent/agent.go` | Thread `planMode` through `LoopConfig.Hints` → `SystemPrompt` |
| 5 | Snapshot-at-start semantics need documentation | Info | `agent/agent.go` | Comment |
| 6 | GatedRegistry gates not touched by plan mode — correct | Info | `agent/gated_registry.go` | No action; confirm design |
| 7 | Pre-existing race on `DefaultRouter.runtimeModel` | Medium (pre-existing) | `router/router.go` | `sync/atomic.Value` or mutex |

---

## Recommended Implementation Order

1. Add `planMode atomic.Bool` to `Agent` with `PlanMode()`/`SetPlanMode()` accessors. This eliminates the data race before any TUI wiring exists.
2. Wire the Shift+Tab key binding in `app.go` with an explicit `if !m.running` guard. Log or display "plan mode takes effect on next run" if the user presses it during a run.
3. Add `PlanMode bool` to `agentloop.PromptHints` and propagate it through `LoopConfig.Hints → PromptHints → systemPrompt`. Have `JSONLSession.SystemPrompt` conditionally append a sentence like: "You are in plan mode. Do not write, edit, or create files. Only read and analyze."
4. Update the status bar to reflect plan mode state (read from `m.agent.PlanMode()` in `updateStatusSlots`), but only update the display after the toggle is accepted, and add a visual qualifier if a run is in progress ("plan mode [next run]").
5. Add a deterministic concurrency test: start a fake agent run, call `SetPlanMode` from a separate goroutine N times while the fake run is in progress, verify no race with `-race`. This is the only reliable way to catch regressions.
6. Fix Finding 7 as a separate housekeeping task.

---

## Assumptions

The review is based on reading the current source. The `planMode` feature does not exist yet in the codebase. The analysis is forward-looking — it describes what would break if plan mode is implemented without the above mitigations. All structural observations (goroutine boundaries, adapter pattern, loop lifecycle) are grounded in the existing code as read.
