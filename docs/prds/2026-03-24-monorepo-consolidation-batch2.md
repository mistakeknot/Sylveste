---
artifact_type: prd
bead: Demarch-og7m
stage: design
batch: 2
---
# PRD: Monorepo Consolidation Batch 2

## Problem

Batch 1 landed foundational security (.11 agent auth, .13 bead state) and calibration (.25 closed-loop thresholds), but the systems they protect have architectural gaps: safety floors block calibration, autonomy has no downward ratchet, phases can be skipped via direct kernel calls, phase names are hardcoded across Clavain CLI, shadow tracking is advisory-only, and subagent routing bypasses `ic route`.

## Solution

Six targeted fixes across safety, phase integrity, governance, and routing that build directly on Batch 1 foundations. All P1, each completable in one session.

## Features

### F1: Safety Floor Clamping (.18)

**What:** Move safety floor logic from pre-resolution early return to post-resolution clamping in `compose.go`, matching the existing bash implementation.

**Root cause:** `resolveModel()` in `compose.go:611-614` early-returns for `fd-safety`/`fd-correctness` before reaching the calibration block at line 618. The bash `lib-routing.sh:705-707` correctly applies calibration first, then clamps with `_routing_apply_safety_floor()`.

**Files:**
- `os/Clavain/cmd/clavain-cli/compose.go` — `resolveModel()` function
- `os/Clavain/cmd/clavain-cli/compose_test.go` — add calibration-vs-floor tests

**Acceptance criteria:**
- [ ] `resolveModel()` applies calibration before safety floor clamping
- [ ] Safety floor still enforces `min_model` (calibration can upgrade, not downgrade)
- [ ] `modelSource` reports `"interspect_calibration"` when calibration wins
- [ ] Test: calibration recommends opus for fd-safety with 0.95 confidence → returns opus (above floor)
- [ ] Test: calibration recommends haiku for fd-safety → clamped to sonnet (below floor)

### F2: Autonomy Hysteresis (.19)

**What:** Add system-level aggregate circuit breaker that auto-disables autonomy when quality degrades across agents, plus cleanup of active overrides on downward transition.

**Root cause:** `_interspect_should_auto_apply()` in `lib-interspect.sh:1705-1749` has per-agent circuit breakers but no aggregate. 7/10 agents tripped = still "autonomous" globally. `/interspect:disable-autonomy` only stops new proposals — existing overrides persist.

**Files:**
- `interverse/interspect/hooks/lib-interspect.sh` — `_interspect_should_auto_apply()`, new `_interspect_system_breaker_check()`
- `interverse/interspect/commands/interspect-disable-autonomy.md` — add override cleanup option

**Acceptance criteria:**
- [ ] System-level breaker: if >50% of agents with evidence have tripped per-agent circuit breakers, auto-disable autonomy
- [ ] Check runs inside `_interspect_should_auto_apply()` before any per-agent gate
- [ ] On auto-disable: log state change reason to interspect.db modifications table
- [ ] `/interspect:disable-autonomy` gains `--revert-all` flag to also revert active overrides
- [ ] Per-agent breaker still works independently (subset of system breaker)

### F3: Phase Skip Prevention (.20)

**What:** Change `ic run advance` default priority from 4 (TierNone, skips all gates) to 2 (TierSoft, enforces soft gates), requiring explicit `--priority=4` or `--disable-gates` for gate bypass.

**Root cause:** `run.go:410` sets `priority := 4`. In `gate.go:143`, priority ≥ 4 maps to `TierNone` which returns `GateNone` without evaluating any rules. Any caller running `ic run advance <id>` bypasses both kernel gates (artifacts, agents, budget) and OS-layer gates (Clavain's `enforce_gate()`).

**Files:**
- `core/intercore/cmd/ic/run.go` — change default priority, add validation
- `core/intercore/internal/phase/gate.go` — document tier semantics
- `os/Clavain/cmd/clavain-cli/phase.go` — verify `--priority=0` usage (line 143, already correct)

**Acceptance criteria:**
- [ ] Default priority for `ic run advance` is 2 (TierSoft)
- [ ] `--priority=4` still works but requires explicit flag
- [ ] Soft gates (CheckArtifactExists, CheckVerdictExists) fire by default
- [ ] Hard gates (budget) fire at priority ≤ 1 (unchanged)
- [ ] Clavain's `cmdSprintAdvance()` continues using `--priority=0` (hard gates)
- [ ] No breaking change for existing `ic run advance --priority=N` callers

### F4: Phase Name Deduplication (.22)

**What:** Replace hardcoded phase name strings across 5 Clavain CLI files with `phase.DefaultChain()` constants from `core/intercore/pkg/phase/phase.go`.

**Root cause:** handler_spawn.go correctly uses `phase.Executing`, but 5 Clavain CLI files hardcode phase strings: `policy.go` (6 phases), `phase.go` (9 including deprecated), `budget.go` (9 with cost defaults), `stats.go` ("done"), `factory_stream.go` ("executing" semantic collision).

**Files:**
- `os/Clavain/cmd/clavain-cli/policy.go` — lines 101, 145-150, 226
- `os/Clavain/cmd/clavain-cli/phase.go` — lines 16-36, 506-522
- `os/Clavain/cmd/clavain-cli/budget.go` — lines 86-128
- `os/Clavain/cmd/clavain-cli/stats.go` — line 96
- `os/Clavain/cmd/clavain-cli/factory_stream.go` — line 303 (rename to avoid collision)
- `core/intercore/pkg/phase/phase.go` — add `DefaultChain()` iterator if missing

**Acceptance criteria:**
- [ ] Zero string literals for phase names in policy.go, phase.go, budget.go, stats.go
- [ ] All use `phase.Brainstorm`, `phase.Executing`, etc. constants
- [ ] Deprecated aliases ("plan-reviewed", "shipping") removed from switch cases
- [ ] `factory_stream.go:statusStr()` renamed to `agentStatusStr()` with comment explaining it's agent activity status, not sprint phase
- [ ] `go build ./...` passes for clavain-cli
- [ ] Existing tests pass (no behavioral change)

### F5: Shadow Tracker Enforcement (.24)

**What:** Add shadow tracker detection to the Stop hook's tiered decision system, upgrading enforcement from advisory-only (`/clavain:doctor`) to automatic session-end blocking.

**Root cause:** Shadow tracker detection in `doctor.md:147-159` only runs manually via `/clavain:doctor`. At 5+ concurrent agents with Dolt contention, agents resort to shadow tracking (TODO files, pending-beads lists). The Stop hook (`auto-stop-actions.sh`) already has a tiered decision system for compound/dispatch/drift-check — shadow tracking should be a new tier.

**Files:**
- `os/Clavain/hooks/auto-stop-actions.sh` — add shadow tracker tier (lowest priority)
- `os/Clavain/commands/doctor.md` — extract detection logic into reusable function

**Acceptance criteria:**
- [ ] Stop hook detects shadow trackers using same 3-category logic as doctor.md
- [ ] Returns block decision with `/bead-sweep` recommendation
- [ ] Opt-out via `.claude/clavain.no-shadow-enforce` (matches existing opt-out pattern)
- [ ] Runs at lowest priority tier (after compound/dispatch/drift-check)
- [ ] Never fails hard (exit 0 always)
- [ ] Dedup sentinel prevents double-firing

### F6: Routing Always-On (.3)

**What:** Wire Skaffen's subagent dispatch through `ic route dispatch` so the kernel's routing intelligence (calibration, safety floors, caps) applies to subagent type and model selection, not just the main LLM.

**Root cause:** Skaffen's model routing correctly calls `ic route model` via `router/intercore.go:36-49`. But subagent dispatch in `subagent/tool.go:97-144` takes the LLM's `subagent_type` directly without consulting `ic route dispatch`. The subagent runner at `runner.go:80-152` uses `NoOpRouter` for model selection, bypassing calibration entirely.

**Prerequisites:** .14 (phase contract — closed), .15 (superstar cap — closed)

**Files:**
- `os/Skaffen/internal/subagent/tool.go` — add `ic route dispatch` call before execution
- `os/Skaffen/internal/subagent/runner.go` — replace `NoOpRouter` with IC-backed router
- `os/Skaffen/internal/subagent/registry.go` — extend type metadata for routing context
- `core/intercore/cmd/ic/route.go` — verify `dispatch` subcommand handles subagent context

**Acceptance criteria:**
- [ ] Subagent type selection queries `ic route dispatch --type=<requested> --phase=<current>`
- [ ] Dispatch routing can override LLM's type choice (e.g., upgrade explore→general for complex tasks)
- [ ] Subagent model uses IC-backed router, not `NoOpRouter`
- [ ] Safety floors and calibration apply to subagent models
- [ ] Fallback: if `ic route dispatch` fails, use LLM's original choice (graceful degradation)
- [ ] No breaking change to Agent tool schema

## Execution Order

```
Phase A (quick fixes — parallel):
  ├── A1: Safety floor clamping (F1/.18) — compose.go only
  └── A2: Phase name dedup (F4/.22) — clavain-cli string→constant

Phase B (security — after A2 for phase constants):
  └── B1: Phase skip prevention (F3/.20) — gate.go default priority

Phase C (safety/governance — parallel with B):
  ├── C1: Autonomy hysteresis (F2/.19) — lib-interspect.sh aggregator
  └── C2: Shadow tracker enforcement (F5/.24) — auto-stop-actions.sh tier

Phase D (routing — after all foundations):
  └── D1: Routing always-on (F6/.3) — Skaffen subagent dispatch
```

## Non-goals

- Phase FSM lift to Intercore (.1) — multi-session effort, Batch 3
- Event pipeline unification (.2) — multi-session effort, Batch 3
- Multi-agent coordination cluster (.12, .27, .29) — matters at 5+ agent scale
- Ockham integration (.7) — blocked on vision doc

## Dependencies

- F1 (.18): None — calibration from .25 already landed
- F2 (.19): None — builds on existing interspect autonomy system
- F3 (.20): F4 (.22) for clean phase constants in gate documentation
- F4 (.22): None — .14 phase contract already provides constants
- F5 (.24): None — independent governance change
- F6 (.3): .14 (closed) + .15 (closed) — both landed in Batch 1

## Open Questions

1. **F2 threshold:** Should system breaker trigger at >50% tripped agents, or use a different ratio?
2. **F3 logging:** Should priority-4 (TierNone) calls emit a warning to stderr when gates are bypassed?
3. **F6 fallback:** If routing service is slow (>500ms), should subagent dispatch skip routing entirely or wait?
