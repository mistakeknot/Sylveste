---
artifact_type: reflection
bead: iv-6ixw
stage: reflect
category: patterns
tags: [self-building, clavain, agency-spec, wiring, gate-graduation]
---
# C5: Self-Building Loop — Sprint Reflection

## What We Built

Wired C1-C4 deliverables together so Clavain can use its own agency specs to orchestrate development sprints. Four features shipped:

1. **Self-targeting config** (`.clavain/agency-spec.yaml`) — project override that adds `fd-self-modification` safety gate
2. **Compose plan integration** (`composeSprint()`, `sprint-compose`, `sprint-plan-phase`, `sprint-env-vars`) — turns agency spec into per-phase model routing env vars
3. **Gate mode graduation** — per-stage `gate_mode` (enforce for discover/design, shadow for build/ship)
4. **E2E smoke tests** — integration tests covering the full compose→phase-tier→env-var pipeline

## Key Patterns

### Wiring > Building
C5 was classified complexity 5/5 but turned out to be mostly a wiring problem. All infrastructure existed (C1 specs, C2 fleet, C3 composer, C4 contracts) — the work was connecting them with thin adapter functions. **Lesson:** complexity classification should weight novelty more than scope.

### phaseToStage() as Bridge Function
The authoritative mapping from sprint phases (brainstorm, executing, shipping) to agency spec stages (discover, build, ship) in `budget.go` became the critical bridge. Three new features all depend on it. **Lesson:** when wiring subsystems, identify the bridge function early — it's the narrowest interface between domains.

### Fallback Chains Over Hard Dependencies
Every new command falls back gracefully: compose plans → agency spec → hardcoded defaults. This means the self-building loop works even without ic/bd running — essential for bootstrapping. **Lesson:** fallback chains make autonomous systems resilient to partial infrastructure.

### Per-Stage Gate Graduation
Enforce gates for cheap-to-redo phases (discover/design), shadow for expensive ones (build/ship). This balances safety against false-positive blocking. **Lesson:** gate strictness should be inversely proportional to the cost of re-doing the gated work.

## Quality Gate Findings (Resolved)

Review agents caught 4 issues that were fixed before shipping:

1. **loadAgencySpec() in hot loop** (3/3 agent convergence) — hoisted outside the handoff check loop
2. **Budget fallback used MinTokens instead of proportional allocation** — was exporting 2000 instead of 100000 for discover stage
3. **Silent nil on unknown phase** — now emits stderr warning
4. **json.Marshal errors discarded** — now returns proper errors

The budget undercount (P5) would have caused real problems — agents would get 40x less budget than intended when using fallback path. Good catch by fd-correctness.

## Deferred Work

- **iv-71kf3**: C5.1 Full agent dispatch (replace model routing with actual agent spawning)
- **iv-p0w2s**: C5.2 Event reactor (cross-session advancement without polling)
- P2 (budget arithmetic duplication), P3 (alphabetical model selection) tracked but not critical

## Complexity Calibration

Estimated: 5/5 (complex). Actual effort: ~3/5 (moderate). Most time was spent on test fixtures and review resolution, not novel code. Future similar wiring tasks should classify at 3.
