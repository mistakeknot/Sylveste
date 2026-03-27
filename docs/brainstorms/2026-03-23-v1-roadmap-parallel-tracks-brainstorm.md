---
artifact_type: brainstorm
bead: Sylveste-enxv
stage: discover
---

# v1.0 Roadmap: Parallel Track Model

## What We're Building

A milestone roadmap from v0.6 → v0.7 → v0.8 → v0.9 → v1.0 structured as **three parallel tracks** with version gates at track-level intersections. Each track progresses independently; a version bump requires all tracks to reach the gate threshold.

**Purpose:** Internal north star now, transitioning to external communication as we approach v0.9/v1.0. Early milestones optimize for actionability (what to work on); later milestones optimize for credibility (measurable claims).

**Epic scope:** Sylveste-enxv stays open for the full v0.7→v1.0 journey. All milestones are children of this epic.

## The Three Tracks

### Track A: Autonomy

The system's past behavior shapes its future behavior without human intervention.

| Level | Name | Definition | Current State |
|-------|------|-----------|---------------|
| L1 | Manual calibration | Calibration tools exist but require human invocation | Phase-cost: `calibrate-phase-costs` exists, manual. Routing: `lib-interspect.sh` 95% complete, verdict recording broken. |
| L2 | Semi-automatic | Calibration triggers at natural points (sprint end, session end) | Phase-cost: triggered by `/reflect` (non-blocking). Routing/gates: not triggered. |
| L3 | Fully autonomous loops | All 3 loops (routing, gates, phase-cost) fire without human intervention | None operational. Architecture exists for all three. |
| L4 | Self-healing | Auto-remediation: system retries failed gates, substitutes agents, adjusts parameters | Not started. |

**Current position: A:L1.5** — Phase-cost is between L1 and L2 (triggered by /reflect but not SessionEnd). Routing and gates are at L1.

### Track B: Safety

The system prevents, detects, and recovers from failures structurally, not probabilistically.

| Level | Name | Definition | Current State |
|-------|------|-----------|---------------|
| L1 | Gates exist | Phase gates run on transitions, block on failure | Gates evaluate via `ic gate check` on every transition. Thresholds hardcoded. |
| L2 | Gates learn | Gate thresholds adjust from historical pass/fail data | No calibration file exists. No outcome recording. No feedback loop. |
| L3 | Existential failures prevented | 5 failure modes mechanically prevented (unbounded cascades, silent degradation, state corruption, unprovenanced modification, infinite loops) | Partially: gates exist (cascades), bd doctor exists (corruption, manual). Others absent. |
| L4 | Adversarial testing | Adversarial test suite validates detection rates; semantic cascade detection >70% | Not started. |

**Current position: B:L1** — Gates run but never learn. Thresholds are static constants.

### Track C: Adoption

The system works on codebases the developers don't control, and new users can reach value quickly.

| Level | Name | Definition | Current State |
|-------|------|-----------|---------------|
| L1 | Self-building | Proven on the Sylveste codebase only | 800+ sessions, $2.93/landable-change baseline. |
| L2 | Single external | 1 external project with 50+ sprints, metrics collected | Not started. |
| L3 | Multi-external + ODD | 3+ external projects, ODD published, directional evidence | Not started. |
| L4 | Accessible | Onboarding <60min, 70%+ new users succeed without help, instrumented | Not started. Onboarding is a known pain point. |

**Current position: C:L1** — Self-building only, well-measured.

## Version Gates

Each version bump requires ALL tracks to reach the gate threshold:

```
v0.7 = A:L3 + B:L2 + C:L1
  Autonomy loops close. Gates start learning. Self-building continues.
  Exit: 10 consecutive sprints, no manual calibration intervention.

v0.8 = A:L3 + B:L3 + C:L2
  Existential failures prevented. First external project running.
  Exit: 100 sprints no existential failures. External metrics collected.

v0.9 = A:L4 + B:L4 + C:L3
  Self-healing. Adversarial testing. Multiple external projects proven.
  Exit: External metrics within 1 SD of internal. ODD published.

v1.0 = A:L4 + B:L4 + C:L4
  No new features vs v0.9. Stability declaration. Onboarding works.
  Exit: All v0.7-v0.9 criteria hold. API contract published.
```

## Why This Approach

**Why parallel tracks instead of sequential milestones:**
- Work on any track at any time — doesn't force artificial sequencing
- Version gates prevent declaring "done" when one track sprinted ahead while another stalled
- External validation starts at v0.7 (continuous, not gated to v0.9)
- Maps cleanly to different team/agent specializations

**Why these three tracks:**
- **Autonomy** is the core bet (PHILOSOPHY.md: "infrastructure unlocks autonomy")
- **Safety** is the trust foundation (can't declare v1.0 if failures are probabilistic)
- **Adoption** is the credibility requirement (self-building evidence alone is insufficient)

**Why these specific gate combinations:**
- v0.7 doesn't require external adoption (C:L1) — loops must close before we expose them to external stress
- v0.8 requires first external project (C:L2) — external runs stress-test the evaluation infrastructure being built in B:L3
- v0.9 requires self-healing (A:L4) — by the time multiple external projects are running, auto-remediation is essential
- v1.0 requires accessible onboarding (C:L4) — Dwarf Fortress lesson: depth without accessibility is inventory, not capability

## Key Decisions

1. **Milestone versions are qualitative thresholds**, not feature releases. Patch versions (v0.6.230, v0.6.231...) continue between milestones.
2. **External validation is continuous from v0.7**, not gated to a single milestone. v0.8 and v0.9 have formal evidence requirements, but runs begin earlier.
3. **v0.7 is broader than "just wire the loops"** — it includes the operational maturity to trust them (bd doctor auto-run, anomaly detection basics, graceful degradation).
4. **v1.0 is a stability declaration, not a feature release.** No new features vs v0.9. Follows the Terraform/Go pattern: "boring is stable."
5. **The epic tracks the full v0.7→v1.0 journey.** Milestone-level children get created under this epic as work is scoped.

## Concrete Gap Analysis (v0.7 Focus)

### Track A: L1.5 → L3

| Component | Current | Needed for L3 | Effort |
|-----------|---------|---------------|--------|
| Phase-cost calibration | Manual trigger in /reflect | SessionEnd hook auto-trigger | Small — move trigger location |
| Routing verdict recording | Broken — quality-gates never calls `_interspect_record_verdict()` | Fix signal path: quality-gates → lib-interspect.sh | Medium — debug broken wiring |
| Routing auto-calibration | Manual `/interspect:calibrate` | SessionEnd hook + scheduled background job | Medium — new trigger + scheduling |
| Gate threshold calibration | No calibration mechanism at all | Design schema, outcome recording, threshold adjustment algorithm | Large — new design work |

### Track B: L1 → L2

| Component | Current | Needed for L2 | Effort |
|-----------|---------|---------------|--------|
| Gate outcome recording | Not recorded | Record pass/fail + actual quality post-phase | Medium — new instrumentation |
| Gate calibration file | Doesn't exist | `gate-calibration.json` schema + read/write | Medium — new file format |
| Threshold adjustment | Hardcoded constants | Algorithm: historical rates → adjusted thresholds | Medium — new algorithm |
| bd doctor auto-run | Manual | SessionStart hook or cron | Small — wiring |

### Track C: Stays at L1

No new work for v0.7. Continue self-building metrics collection.

## Open Questions

1. **Deletion-recovery test timing:** The synthesis placed it as a v1.0 hard requirement. Should it be an early validation (run at v0.7 to prove loops are real) or a late gate (v0.9/v1.0)?
2. **Evaluation harness priority:** Pass@k metrics are in v0.8 (B:L3 area). Should we build a lightweight version earlier for v0.7 self-assessment?
3. **Interplay between tracks:** If Track A reaches L3 but Track B is stuck at L1, do we bump version? The gate model says no — but does that create perverse incentives to under-invest in the hardest track?
4. **Bead structure:** Should each track×level cell be a child bead? That's 12 beads. Or should milestone-level children (v0.7, v0.8, v0.9, v1.0) each contain track-specific grandchildren?
