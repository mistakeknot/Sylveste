---
artifact_type: prd
bead: Sylveste-og7m
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
Phase A (foundations — all parallel, no inter-dependencies):
  ├── A1: Safety floor clamping (F1/.18) — compose.go only
  ├── A2: Phase name dedup (F4a/.22) — clavain-cli string→constant
  └── A3: Phase skip prevention (F3/.20) — gate.go default priority

Phase B (safety/governance — parallel, after A for verification):
  ├── B1: Autonomy hysteresis (F2/.19) — lib-interspect.sh aggregator
  └── B2: Shadow tracker enforcement (F5/.24) — auto-stop-actions.sh

Phase C (routing — after A1 specifically, may need 2 sessions):
  └── C1: Routing always-on (F6/.3) — Skaffen subagent + ic route dispatch extension
```

## Non-goals

- Phase FSM lift to Intercore (.1) — multi-session effort, Batch 3
- Event pipeline unification (.2) — multi-session effort, Batch 3
- Multi-agent coordination cluster (.12, .27, .29) — matters at 5+ agent scale
- Ockham integration (.7) — blocked on vision doc

## Dependencies

- F1 (.18): None — calibration from .25 already landed
- F2 (.19): None — builds on existing interspect autonomy system
- F3 (.20): None — gate.go is in L1, no compile-time dependency on Clavain phase constants
- F4 (.22): None — .14 phase contract already provides constants
- F5 (.24): None — independent governance change
- F6 (.3): F1 (.18) for correct safety floor behavior + .14 (closed) + .15 (closed)

## Open Questions — Resolved

1. **F2 threshold:** ~~>50%~~ → `>=50%` with minimum 3-agent floor. 1-of-2 = 50% should trip.
2. **F3 logging:** Yes. `--priority=4` and `--disable-gates` emit structured audit events + stderr warning.
3. **F6 fallback:** 200ms timeout ceiling. On timeout, use LLM's original choice + log routing-fallback event.

---

## Flux-Drive Review (2026-03-24)

**Reviewers:** fd-architecture, fd-correctness, fd-safety, fd-user-product (4/4 complete)

### Critical Findings (must resolve before implementation)

#### C1: F4 is a data migration, not a find-replace [correctness]

`phase.PlanReviewed` = `Planned` = `"planned"` and `phase.Shipping` = `Polish` = `"polish"` in `core/intercore/pkg/phase/phase.go`. But Clavain CLI runtime uses `"plan-reviewed"` and `"shipping"` as actual string values stored in IC databases. Swapping to constants changes the DB values, silently breaking in-flight sprints.

**Resolution — split F4 into two steps:**
- **F4a (this batch):** Introduce transition constants in `phase.go` with old string values: `LegacyPlanReviewed = "plan-reviewed"`, `LegacyShipping = "shipping"`. Replace hardcoded strings in Clavain CLI with these constants. No behavioral change — just centralize the strings.
- **F4b (separate bead, Batch 3):** Migrate all IC database phase records from legacy strings to canonical names, then flip constants. Requires `ic migrate phases` command.

**Updated F4 acceptance criteria:**
- [ ] New constants `phase.LegacyPlanReviewed` and `phase.LegacyShipping` with old string values
- [ ] Clavain CLI uses phase constants (mix of canonical + legacy) — zero string literals
- [ ] `factory_stream.go:statusStr()` renamed to `agentStatusStr()`
- [ ] No behavioral change — same string values as before
- [ ] `go build ./...` and existing tests pass

#### C2: F3 TierSoft doesn't block — need TierHard [safety]

`machine.go:188` only hard-blocks on `TierHard` failures. `TierSoft` (priority=2) evaluates gates but still advances on failure — it's observability, not enforcement. The PRD frames F3 as closing a privilege escalation, which requires actual blocking.

**Resolution — change default to 1 (TierHard), not 2:**
- Default priority for `ic run advance` becomes **1** (TierHard = evaluates AND blocks on failure)
- `--priority=2` available for "audit but don't block" mode
- `--priority=4` / `--disable-gates` still available for intentional bypass

**Updated F3 acceptance criteria:**
- [ ] Default priority for `ic run advance` is **1** (TierHard)
- [ ] Hard gates (CheckArtifactExists, CheckVerdictExists, budget) fire and **block** by default
- [ ] `--priority=2` available for audit-only mode (evaluate gates, advance anyway)
- [ ] `--priority=4` and `--disable-gates` still work but emit structured audit event to `ic events` + stderr warning
- [ ] Pre-merge audit: grep all `ic run advance` callers without `--priority` — annotate intended tier
- [ ] Gate block errors include which check failed + bypass flag hint
- [ ] Clavain's `cmdSprintAdvance()` continues using `--priority=0` (unchanged)

### High Findings

#### H1: F2 threshold edge case at small pools [correctness, user-product]

With 2 agents and 1 tripped, `>50%` = exactly 50% → breaker doesn't fire. System stays autonomous with half the fleet degraded.

**Resolution:** `>=50%` threshold with minimum 3-agent floor. If fewer than 3 agents have evidence, skip aggregate check (per-agent breakers still protect individually).

#### H2: F2 auto-disable needs visible notification [user-product]

Current PRD only logs to `interspect.db`. Operator gets no session-visible feedback when system breaker fires.

**Resolution:** Add stderr output at point of auto-disable: agent count, threshold crossed, what changed. Surface in interline statusline if available.

#### H3: F2 `--revert-all` scope and atomicity [safety, correctness]

- `--revert-all` is destructive; must NOT auto-trigger from system breaker (auto-disable only stops new proposals)
- Write to `routing-overrides.json` must be atomic (temp file + `mv`)
- Command must require `--confirm` flag or present dry-run count

**Resolution:** System breaker auto-disables autonomy only. `--revert-all` is manual-only with `--confirm` required. Atomic write via temp+rename.

#### H4: F6 interface mismatch [correctness]

`cmdRouteDispatch()` in `route.go:192` takes `--tier`, not `--type`/`--phase`. The acceptance criteria assume parameters that don't exist.

**Resolution:** Extend `cmdRouteDispatch` with `--type` and `--phase` parameters. When `--type` is provided, resolve subagent type + model; when `--tier` is provided, resolve model only (backward compat).

#### H5: F6 type override invisible to parent LLM [user-product]

When routing overrides the LLM's subagent type choice, the tool result shows nothing. Parent LLM makes decisions assuming the original type ran.

**Resolution:** Tool result annotation: `[routed: explore→general]`. Emit override to interspect evidence for auditability.

#### H6: F1 floor check must be unconditional final line [correctness, safety]

If calibration recommends an unrecognized model string (e.g., `"claude-3-5-sonnet"`), it falls through calibration's whitelist but escapes the floor entirely. The bash reference applies floor unconditionally at the end.

**Resolution:** Safety floor clamp is the absolute last line of `resolveModel()`, applied to the final `model` value regardless of source. Add test: unrecognized calibration model for fd-safety → floor clamps to sonnet.

### Medium Findings

#### M1: F5 false positives on legitimate docs [user-product]

`docs/*.md` with `status: draft` in frontmatter triggers shadow tracker detection. Design docs are not shadow trackers.

**Resolution:** Tighten third category: require `type: task` or `type: todo` in addition to `status:` key. OR require both `status:` AND the file is in `todos/` or matches `pending-beads*`. Block reason must list detected file names so LLM can distinguish real vs false positive.

#### M2: F3 `--disable-gates` has zero audit trail [safety]

`--disable-gates` at `run.go:426` sets `DisableAll: true` with no logging. Gate bypass looks identical to normal advance in event history.

**Resolution:** Addressed in C2 — both `--priority=4` and `--disable-gates` now emit structured audit events.

#### M3: F1 missing upward calibration test [safety]

PRD test cases cover haiku→clamped-to-sonnet but not opus→accepted-above-floor.

**Resolution:** Already in original AC (line 33). Verify the test explicitly confirms `modelSource = "interspect_calibration"` when opus is accepted.

### Architecture Findings (fd-architecture)

#### A1: F5 shadow tracker tier placement is self-defeating [architecture]

Shadow tracker detection at "lowest priority" in the waterfall means it only fires when compound/dispatch/drift-check didn't claim the cycle. Heavy multi-agent sessions — where shadow trackers most likely accumulate — always trigger compound first (weight >= 4). The enforcement fires least when most needed.

**Resolution:** Shadow tracker detection runs as an **independent early check** orthogonal to the tier waterfall. It emits a warning alongside whatever tier action fires. Block escalation only if no other tier claimed the cycle AND shadow files exceed threshold.

#### A2: F5 detection function extraction target not named [architecture]

`doctor.md` is a command markdown file, not a sourceable lib. The extraction needs a named target.

**Resolution:** Extract detection into `lib-shadow-tracker.sh` (new file, sourced by both `auto-stop-actions.sh` and referenced by `doctor.md`). Function: `detect_shadow_trackers()` returns count + file list on stdout.

#### A3: F1 needs tier-ordering comparison, not string equality [architecture]

Safety floor clamp requires comparing `haiku < sonnet < opus`. `compose.go` doesn't have a tier-ordering helper. `core/intercore/internal/routing/resolve.go:83` has `applyFloor()` but that's an internal package.

**Resolution:** Either inline a simple tier map in `compose.go` (3 entries — minimal), or add a `phase.ModelTier()` function to `core/intercore/pkg/phase/` (exported, reusable). Prefer the latter since `lib-routing.sh` already has `_routing_model_tier()`.

#### A4: F6 scope is 3-4x larger than other features [architecture]

F6 requires: extending `cmdRouteDispatch` with `--type`/`--phase`, modifying `SubagentType` struct in `registry.go`, updating `tool.go` call site, replacing `NoOpRouter` in `runner.go`, adding routing config schema for per-type model selection, writing integration tests.

**Resolution:** Flag F6 as a potential 2-session item. If it doesn't complete in one session, the partial state (extended `cmdRouteDispatch` without Skaffen integration) is safe to ship independently.

#### A5: F3 false dependency on F4 removed [architecture]

`gate.go` is in L1 (`core/intercore/internal/phase/`). It has no compile-time dependency on Clavain phase constants. F3 moved to Phase A (parallel with F1 and F4).

#### A6: F2 system breaker should cache with TTL [architecture]

Cross-agent table scan on every `_interspect_should_auto_apply()` call is expensive. At high call frequency this becomes a bottleneck.

**Resolution:** Write `system_breaker_checked_at` sentinel with 60-second TTL. Re-evaluate only when stale. Implementation detail for F2 — not an acceptance criteria change.

### Rollback Safety

| Feature | Rollback | Persistent State | Recovery |
|---------|----------|-----------------|----------|
| F1 | Binary revert | None | Clean |
| F2 | Plugin file revert | `confidence.json` may have `autonomy: false` | Note pre-deploy value |
| F3 | Binary revert | None | Clean |
| F4a | Binary revert | None (same string values) | Clean |
| F5 | Plugin file revert | None | `.claude/clavain.no-shadow-enforce` escape valve |
| F6 | Binary revert | None | Clean |
