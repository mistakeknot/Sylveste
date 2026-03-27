# Architecture Review: Skaffen Plan Mode

**Reviewer:** Flux-drive Architecture & Design Reviewer
**Date:** 2026-03-12
**Subject:** Plan mode feature for Skaffen (toggleable read-only tool gate)

---

## Orientation

Skaffen is a two-layer agent architecture. The inner layer (`agentloop`) is a phase-agnostic Decide-Act loop. The outer layer (`agent`) wraps it with the OODARC phase FSM, a gated tool registry, and adapter bridges. The `tui` package sits above `agent` and drives it from user input. The `session` package implements `agent.Session`.

The dependency rule documented in AGENTS.md is strict: `agentloop` never imports `agent` or `tool`. Everything else flows downward: `cmd/skaffen → tui → agent → agentloop → provider`.

The plan mode proposal cuts across this stack at four points: the registry gate layer, the Agent struct, the CLI entry point, the TUI layer, and the session/prompt layer. Each has distinct concerns.

---

## 1. Boundaries and Coupling

### 1.1 The Gate Swap Is Structurally Sound

The proposed `PlanModeGates` constant in `gated_registry.go` is read-only tools across all phases. The proposed `SetPlanMode(bool)` swaps which gate map `GatedRegistry` consults. This is the right place for it. The `GatedRegistry` already owns the gate map — adding a mode field that selects between two gate maps stays entirely within the existing responsibility of that type.

The `tool.Registry` in `internal/tool/registry.go` has its own parallel gate map (`defaultGates`). The `GatedRegistry` in `internal/agent/gated_registry.go` is a separate type wrapping `agentloop.Registry`. These are not the same object. The plan should clarify which registry type `SetPlanMode` lives on. Based on the code, `agent.go`'s `buildLoopRegistry` calls `a.registry.Tools(phase)` where `a.registry` is `*tool.Registry` (the `tool` package type, not `GatedRegistry`). `GatedRegistry` wraps `agentloop.Registry` and is used in a different path. This distinction matters for where the gate swap lands.

**Action required:** Confirm whether `PlanModeGates` and `SetPlanMode` belong on `tool.Registry` (which `agent.buildLoopRegistry` actually uses) or on `GatedRegistry` (which wraps a flat `agentloop.Registry`). The current `agent.go` does not use `GatedRegistry` at all — it calls `a.registry.Tools(phase)` on a `*tool.Registry` directly. Putting plan mode on `GatedRegistry` would require wiring that is not currently present.

### 1.2 Dual SetPlanMode Creates Unnecessary Coupling

Putting `SetPlanMode` on both `GatedRegistry` and `Agent` creates a layering problem. The TUI calls `agent.SetPlanMode(bool)`, which forwards to the registry. This means `Agent` grows a method that is purely a passthrough with no agent-layer logic. The correct ownership is one of:

- The registry owns the gate; `Agent.SetPlanMode` is a thin delegator and is acceptable as a convenience bridge (the existing `SetModelOverride` uses the same pattern via type assertion on the router). This is fine if kept thin.
- The TUI calls the registry directly. This is worse — it creates a TUI-to-registry dependency, bypassing the agent boundary.

The thin delegator on `Agent` is the lesser coupling. Accept it but treat `Agent.SetPlanMode` as a forwarding method only; no plan mode logic should live in `agent.go` itself.

### 1.3 The `planMode` Field on Agent Is Redundant

If `SetPlanMode` forwards to the registry and the registry holds the gate state, then `Agent` storing a `planMode bool` field mirrors state that already lives in the registry. This is a small but real divergence risk: the two fields can drift out of sync if `SetPlanMode` on the registry is ever called directly. Either:

- Remove the `planMode` field from `Agent` and derive the state from the registry when needed (e.g., `PlanMode() bool` calls the registry), or
- Accept the duplication but never expose a public `PlanMode()` getter on `Agent` that could return a stale value.

### 1.4 Session Prompt Injection

`JSONLSession.SystemPrompt` currently ignores both `phase` and `budget` parameters (see the comment on line 52: "budget parameter is ignored — JSONLSession returns a static prompt"). The `sessionAdapter` calls `sa.inner.SystemPrompt(sa.phase(), hints.Budget)`. Plan mode context injected into the system prompt must be handled inside `JSONLSession.SystemPrompt`, which means adding a `planMode bool` field to `JSONLSession` as well.

This creates a third location storing the same boolean: registry, agent, and session. The fundamental problem is that plan mode is cross-cutting state that multiple objects need to observe, but there is no shared context carrier for it.

The smallest viable change: pass plan mode as a hint through existing seams. `agentloop.PromptHints` already carries `Budget int`. Adding `PlanMode bool` to `PromptHints` would let plan mode flow from `buildLoopRegistry` (which already receives the phase) through the adapter chain to `JSONLSession.SystemPrompt` without anyone storing an extra field. The registry controls the gate; the hints carry the rendering signal to the prompt. No field drift is possible.

### 1.5 The `--plan-mode` CLI Flag

The `main.go` flag is fine at the entry point. It should call `agent.SetPlanMode(true)` after constructing the agent, before `tui.Run`. This matches how `SetStreamCallback` and `SetToolApprover` are wired in `tui/app.go` — post-construction configuration. No structural objection.

---

## 2. Pattern Analysis

### 2.1 Orthogonal Mode vs. New Phase — This Is Correct

The decision not to make plan mode a phase is architecturally correct. Phases in OODARC are sequential workflow states; the FSM advances monotonically. Plan mode is a user-visible constraint that should be toggleable during any phase without affecting phase position. Making it a phase would force the FSM to track a "return destination" after plan mode ends, turning a simple boolean into state machine complexity it was never designed for.

The existing pattern for cross-cutting overrides is the type-assertion optional interface: `ModelOverrideSetter` in `deps.go` allows the router to accept a runtime model switch without requiring all routers to know about model overrides. Plan mode on the registry follows the same spirit.

### 2.2 Thread Safety — This Is the Main Risk

`Agent.Run` is called from a goroutine (see `tui/app.go`'s `runAgent` tea.Cmd). The TUI's `Update` method runs on the Bubble Tea event loop (the main goroutine). `Shift+Tab` fires from `Update`, which would call `agent.SetPlanMode(bool)`, which would mutate the registry's gate map while `Run` may be executing `buildLoopRegistry`.

Looking at the current gate swap design: if `SetPlanMode` replaces the active map pointer (e.g., `g.activeGates = planModeGates`) or flips a bool that `Tools()` reads, this is a data race under the Go memory model unless protected by a mutex or atomic.

The existing `JSONLSession` uses `sync.Mutex` for its message slice. The `tool.Registry` has no synchronization. `GatedRegistry` has none either.

**This is a must-fix.** Options in ascending order of invasiveness:

1. Disallow toggling while the agent is running (simplest): the TUI already has `m.running bool`. Gate the `Shift+Tab` handler on `!m.running`. No synchronization needed because the toggle only fires when no goroutine is executing `Run`. This is the lowest-risk path and matches the existing TUI pattern for blocking inputs during agent execution (`if !m.running` guards at line 268 in `app.go`).

2. Add a `sync/atomic.Bool` to the registry for the plan mode flag. Reads in `Tools()` and `Execute()` use the atomic; `SetPlanMode` writes atomically. This is safe but adds a dependency on atomic state to a package currently free of it.

3. Use a `sync.RWMutex` on the registry. Overkill given option 1 is available.

Option 1 is the correct answer for this codebase. Plan mode is a session-level setting; toggling it mid-execution would produce undefined tool availability within a single `Run` call anyway (the loop would see different tools than it presented to the model at turn start). Block the toggle when running.

### 2.3 No Circular Dependencies Introduced

The proposed changes stay within the existing dependency graph. `tui` already imports `agent`; `agent` already owns the registry. `session` already implements `agent.Session`. No new cross-package edges are introduced. This is clean.

### 2.4 Duplication of Gate Definitions

`internal/tool/registry.go` has `defaultGates` (the canonical phase gate matrix). `internal/agent/gated_registry.go` has `DefaultGates` (an exported copy of the same matrix in a slightly different format). These already represent a near-duplication. Adding `PlanModeGates` to `gated_registry.go` while the actual runtime path goes through `tool.Registry.gates` (used in `buildLoopRegistry`) means `PlanModeGates` may be defined in one place but needs to be applied in another. Audit which gate map is actually consulted at runtime before committing to where plan mode gates live.

---

## 3. Simplicity and YAGNI

### 3.1 `WithPlanMode` Option vs. `SetPlanMode` Method

`Agent` already has a post-construction mutation pattern: `SetStreamCallback`, `SetToolApprover`, `SetModelOverride`. These exist because the TUI needs to wire callbacks after the agent is constructed but before the first run. `SetPlanMode` fits this pattern exactly.

`WithPlanMode(bool)` as a constructor option is not needed. The CLI flag is applied at construction time; the TUI toggle is applied post-construction. One mechanism (`SetPlanMode`) covers both. Adding `WithPlanMode` is speculative generality — remove it. Use `SetPlanMode(true)` in `main.go` after `agent.New(...)` returns when `--plan-mode` is set.

### 3.2 The PLAN Badge in the Status Bar

`updateStatusSlots` in `status.go` currently takes `phase, model string, cost, contextPct float64, turns int`. Adding plan mode here will require either adding a `planMode bool` parameter (widening a function already taking five arguments) or passing it through `appModel` state.

The simpler path: store `planMode bool` in `appModel` and compute the displayed phase string in `View()` as `phase + " [PLAN]"` or by injecting a dedicated status slot. The status bar already has a slot system; inserting a conditional slot or mutating the phase slot's value string avoids a new parameter. This is low-risk local rendering logic — keep it in the TUI, don't push it into the agent layer.

### 3.3 Prompt Injection Scope

The plan notes "plan mode context in system prompt" via `session/session.go`. Evaluate whether this is needed. If the gate correctly removes write/edit/bash tools, the model will be incapable of making changes regardless of what the system prompt says. Prompt injection is then belt-and-suspenders, and the belt (gate) is sufficient. Adding suspenders adds complexity in the session layer without changing agent behavior. Skip the prompt injection unless there is a specific reason the model needs to be told it is in plan mode (e.g., to produce a different output format). If that reason exists, thread it through `PromptHints.PlanMode bool` as described above — do not store the flag in `JSONLSession`.

---

## Summary Table

| Concern | Verdict | Required Change |
|---------|---------|-----------------|
| Orthogonal mode vs. phase | Correct | None |
| PlanModeGates on GatedRegistry vs. tool.Registry | Ambiguous — verify runtime path | Audit which registry buildLoopRegistry actually uses; place gates there |
| planMode field on both GatedRegistry and Agent | Redundant | Remove field from Agent; derive from registry, or remove Agent getter |
| Thread safety of gate swap | Data race risk | Gate Shift+Tab toggle on `!m.running` (match existing TUI pattern) |
| WithPlanMode constructor option | YAGNI | Remove; use SetPlanMode post-construction |
| planMode stored in JSONLSession | Third copy of same bool | Avoid; use PromptHints.PlanMode if prompt injection is needed |
| Prompt injection into system prompt | Unnecessary if gates are correct | Skip unless output-format reason exists |
| PLAN badge in status bar | Fine in TUI layer | Compute in View(), not a new parameter |
| CLI --plan-mode flag | Correct | Wire as SetPlanMode(true) after agent.New |

---

## Must-Fix Items

**1. Verify which registry buildLoopRegistry uses.** `agent.go` line 172 calls `a.registry.Tools(phase)` on a `*tool.Registry`. `GatedRegistry` wraps `agentloop.Registry`. These are distinct types and distinct runtime paths. Plan mode gates placed on `GatedRegistry` will not affect the execution path currently in use. Place `PlanModeGates` and `SetPlanMode` on `tool.Registry`.

**2. Block Shift+Tab when `m.running` is true.** The toggle must not fire during agent execution. The TUI already guards input on `!m.running`; apply the same guard to the plan mode key handler. This resolves the thread safety issue without requiring synchronization primitives.

**3. Remove `planMode bool` field from `Agent`.** The registry owns the gate state; the agent is a forwarding delegate. One authoritative location prevents drift.

---

## Optional Cleanup

- Remove `WithPlanMode` constructor option.
- If prompt injection is retained, route plan mode through `PromptHints` rather than storing in `JSONLSession`.
- Reconcile the duplicated gate definitions between `tool/registry.go` (`defaultGates`) and `agent/gated_registry.go` (`DefaultGates`) as a separate cleanup — they represent the same matrix in two formats.

---

## Relevant Files

- `/home/mk/projects/Sylveste/os/Skaffen/internal/tool/registry.go` — canonical gate matrix; plan mode gates belong here
- `/home/mk/projects/Sylveste/os/Skaffen/internal/agent/agent.go` — buildLoopRegistry uses tool.Registry directly; SetPlanMode delegator goes here
- `/home/mk/projects/Sylveste/os/Skaffen/internal/agent/gated_registry.go` — GatedRegistry wraps agentloop.Registry; not the runtime path for plan mode gates
- `/home/mk/projects/Sylveste/os/Skaffen/internal/agent/deps.go` — PromptHints lives in agentloop but flows through sessionAdapter here; add PlanMode bool if prompt injection is kept
- `/home/mk/projects/Sylveste/os/Skaffen/internal/tui/app.go` — gate Shift+Tab on `!m.running` (line 268 establishes the pattern)
- `/home/mk/projects/Sylveste/os/Skaffen/internal/tui/status.go` — PLAN badge stays local to View(); no new parameters
- `/home/mk/projects/Sylveste/os/Skaffen/internal/session/session.go` — SystemPrompt ignores phase/budget today; avoid storing plan mode here
- `/home/mk/projects/Sylveste/os/Skaffen/cmd/skaffen/main.go` — wire SetPlanMode after agent.New; no constructor option needed
