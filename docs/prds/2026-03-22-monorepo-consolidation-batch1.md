# PRD: Monorepo Consolidation Batch 1 — Dedup, Security, Phase Contract

**Date:** 2026-03-22
**Epic:** Sylveste-og7m
**Beads:** .10 (P0), .11, .13, .14, .15, .16, .25 (all P1)
**Brainstorm:** `docs/brainstorms/2026-03-22-monorepo-consolidation-kernel-expansion-brainstorm.md`

## Problem

Multi-agent analysis identified 29 systemic issues across the Sylveste monorepo. Three cross-cutting patterns need immediate attention:

1. **Active drift** — Skaffen copy-forks of Alwe/Zaka are diverging (P0). Bug fixes won't propagate.
2. **Security gaps** — Agent impersonation via unauthenticated X-Agent-ID and bead content poisoning via unauthenticated `bd set-state` are exploitable now on localhost.
3. **Architecture fragility** — Two independent phase systems (Clavain 9-phase, Skaffen 6-phase OODARC) with no shared contract. Routing has no per-agent cap. WorkContext reconstructed independently in 8+ places.

These block further autonomous operation: a poisoned bead state can hijack a sprint, a forked codebase means every Skaffen bug fix must be made twice, and phase divergence causes silent MCP tool gating failures.

## Scope

7 child beads from Sylveste-og7m. Execution order follows dependency graph:

```
.10 (Skaffen dedup) ← standalone, can start immediately
.14 (phase contract) ← standalone, can start immediately
.16 (WorkContext type) ← standalone, can start immediately
.15 (superstar cap) ← standalone, can start immediately
.11 (X-Agent-ID auth) ← standalone, can start immediately
.13 (bead poisoning) ← standalone, can start immediately
.25 (interspect calibration) ← depends on .16 conceptually but not code-wise
```

All 7 are independent at the code level. Parallelizable.

## Requirements

### R1: Skaffen→Alwe/Zaka Import (.10, P0)

**What:** Replace Skaffen's copy-forked files with Go module imports from Alwe and Zaka.

**Acceptance criteria:**
- `internal/observer/cass.go` in Skaffen imports from `Alwe/internal/observer` (or a shared package extracted from it)
- `internal/provider/tmuxagent/` in Skaffen imports from `Zaka/internal/adapter` (or shared package)
- `parseJSONLEvent` vs `ParseJSONLEvent` drift resolved — one canonical implementation
- `go test ./...` passes in Skaffen, Alwe, and Zaka after change
- No copy-fork files remain in Skaffen for code that exists in Alwe/Zaka

**Implementation notes:**
- Use `go.mod replace` directives for monorepo-local paths
- Alwe/Zaka may need to export currently-internal packages (move from `internal/` to `pkg/` or root)
- If extraction is complex, a shared package in one of the modules is preferred over `sdk/interbase`

### R2: Agent Identity Verification (.11, P1)

**What:** Intermute must verify that X-Agent-ID matches the registered identity for the session token.

**Acceptance criteria:**
- Agent registration records agent name + session token binding
- Middleware rejects requests where X-Agent-ID doesn't match token-bound identity
- Existing agents work without code changes (registration already happens)
- Test: agent A cannot use agent B's reservations by spoofing header
- Scope: localhost auth only. External auth (mTLS) is out of scope.

### R3: Bead State Writer Verification (.13, P1)

**What:** Critical bd set-state fields require writer identity verification.

**Acceptance criteria:**
- Critical fields list: `ic_run_id`, `dispatch_count`, `autonomy_tier`, `phase`
- Writer identity recorded on all state writes (already logged in events, need enforcement)
- State writes from non-owning agents rejected for critical fields
- Non-critical fields (custom user state) remain open
- Backward-compatible: if no ownership set, writes succeed (progressive enforcement)

### R4: Phase Contract (.14, P1)

**What:** Shared phase vocabulary that both Clavain and Skaffen reference.

**Acceptance criteria:**
- `sdk/interbase/phases/phases.go` defines phase constants and valid transitions
- Clavain's bash reads phase list via `ic phase list` (new Intercore command)
- Skaffen references the Go package directly
- Deprecated aliases (Clavain's 9→6 mapping) are explicit in the contract with deprecation dates
- `handler_spawn.go` reads spawn trigger from run config instead of hardcoding `"executing"`
- Test: invalid phase transition rejected by contract validator

### R5: Routing Superstar Cap (.15, P1)

**What:** `selectQuality()` in scoring.go must cap per-agent assignment.

**Acceptance criteria:**
- `maxPerAgent` parameter in `selectQuality()` matching `selectBalanced()` pattern
- Default cap derived from `floor(total_tasks / available_agents) + 1`
- Test: with 10 tasks and 5 agents, no agent gets >3 tasks even with highest score
- Existing `selectBalanced()` behavior unchanged

### R6: WorkContext Type (.16, P1)

**What:** Named type for the (bead_id, run_id, session_id) trinity.

**Acceptance criteria:**
- `core/intercore/types/workcontext.go` defines `WorkContext` struct
- At least 3 of the 8 reconstruction sites converted to use the type
- Remaining sites tracked as follow-up items (not blocking this sprint)
- Hook chain passes WorkContext instead of individual IDs where possible
- Test: WorkContext serializes/deserializes correctly for event pipeline

### R7: Interspect Confidence Calibration (.25, P1)

**What:** One complete predict→observe→calibrate→fallback loop for Interspect confidence thresholds.

**Acceptance criteria:**
- Canary outcomes (did override improve quality?) written to interspect.db
- `calibrate-thresholds` subcommand reads canary outcomes and writes adjusted thresholds
- `/interspect:calibrate` wires the subcommand into the existing calibrate flow
- Fallback: if no canary data exists, hardcoded defaults still apply
- Test: with 10 mock canary outcomes, thresholds adjust predictably
- This is stages 3-4 of the closed-loop pattern (stages 1-2 exist: hardcoded defaults + canary monitoring)

## Out of Scope

- Phase FSM lift (.1) — full 1,717-line rewrite deferred to Batch 2 after contract lands
- Event pipeline unification (.2) — depends on WorkContext (.16) completing across all 8 sites
- Reservation starvation (.12), autonomy hysteresis (.19) — lower immediate risk
- External auth (mTLS, service mesh) — future work
- Ockham integration (.7) — needs `DispatchAdvice` interface design first

## Success Metrics

| Metric | Target |
|--------|--------|
| Skaffen copy-fork files | 0 (currently 2+) |
| X-Agent-ID spoofing in test | Rejected |
| Phase contract coverage | Both Clavain and Skaffen reference shared constants |
| WorkContext adoption | ≥3/8 sites converted |
| selectQuality per-agent max | Enforced with test |
| Interspect closed-loop stages | 4/4 (was 2/4) |
| Child beads closed | ≥6/7 |

## Dependencies & Risks

| Risk | Mitigation |
|------|------------|
| Alwe/Zaka internal packages not exportable | Extract to `pkg/` subdirectory within same module |
| Phase contract requires bash changes in active sprints | Contract is additive — aliases remain until deprecated |
| bd set-state auth breaks automation | Progressive enforcement — only critical fields, ownership optional |
| Interspect calibration needs real canary data | Mock data for tests; real calibration runs after merge |
