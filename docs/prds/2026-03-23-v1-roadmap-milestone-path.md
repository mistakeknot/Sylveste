---
artifact_type: prd
bead: Demarch-enxv
stage: design
---

# PRD: v1.0 Roadmap — Parallel Track Milestone Path

## Problem

Demarch at v0.6.229 has the architecture for autonomous operation but lacks the wiring, calibration, and validation to declare stability. Without a structured milestone path, work is uncoordinated — some systems advance while critical gaps (gate calibration, external validation, observability) stall. The system needs a roadmap that defines what "v1.0-ready" means and provides actionable milestones to get there.

## Solution

Define a parallel-track milestone model with three tracks (Autonomy, Safety, Adoption) progressing independently, gated by version thresholds. v0.7 is the first milestone: close the 3 calibration loops and add the operational maturity to trust them.

## Features

### F1: Fix routing verdict recording signal path
**What:** Wire quality-gates to invoke `_interspect_record_verdict()` at runtime instead of relying on the SessionStart sweep fallback.
**Acceptance criteria:**
- [ ] Quality-gates calls `_interspect_record_verdict()` after each agent verdict
- [ ] Verdict events appear in interspect.db within the same session (not next session's sweep)
- [ ] Fallback sweep still operates as safety net but is no longer the primary path

### F2: Auto-trigger routing calibration on SessionEnd
**What:** Add a SessionEnd hook that runs `_interspect_auto_calibrate()` to generate routing overrides from accumulated evidence.
**Acceptance criteria:**
- [ ] SessionEnd hook invokes interspect calibration (non-blocking, fail-open)
- [ ] `routing-calibration.json` updated after sessions with new evidence
- [ ] Override proposals generated with canary windows when evidence exceeds threshold
- [ ] Rate limiter enforced (5 modifications/24hr)

### F3: Design and implement gate threshold calibration
**What:** Create a complete gate calibration loop: record gate outcomes, design calibration schema, implement threshold adjustment algorithm, auto-load adjusted thresholds.
**Acceptance criteria:**
- [ ] `gate-calibration.json` schema defined and documented
- [ ] Gate pass/fail outcomes recorded with post-phase quality metrics
- [ ] Threshold adjustment algorithm computes from historical data (minimum 10 data points)
- [ ] `ic gate check` reads from calibration file, falls back to hardcoded defaults
- [ ] Calibration runs automatically (SessionEnd or scheduled)

### F4: Move phase-cost calibration to SessionEnd hook
**What:** Shift `calibrate-phase-costs` invocation from `/reflect` (manual) to SessionEnd hook (automatic).
**Acceptance criteria:**
- [ ] SessionEnd hook triggers `clavain-cli calibrate-phase-costs` (non-blocking)
- [ ] `phase-cost-calibration.json` updated after every session with sprint data
- [ ] `/reflect` still works as manual trigger (backward compatible)
- [ ] Anomaly flag if any phase used >2x estimated tokens

### F5: Gate outcome recording instrumentation
**What:** Instrument phase gate transitions to record what happened after the gate decision (was the gate correct?).
**Acceptance criteria:**
- [ ] Each gate check records: phase, gate result (pass/fail/override), timestamp
- [ ] Post-phase: record actual quality outcome (from quality-gates verdict or test results)
- [ ] Data persisted in a format gate calibration (F3) can consume
- [ ] Minimum overhead: <100ms per gate check

### F6: Gate calibration file schema and read/write
**What:** Define the `gate-calibration.json` format and implement read/write in intercore's gate evaluation path.
**Acceptance criteria:**
- [ ] Schema supports per-phase threshold overrides with confidence intervals
- [ ] Fallback chain: calibration file → agency spec → hardcoded defaults
- [ ] File versioned (schema version field) for forward compatibility
- [ ] `ic gate calibrate` command generates file from outcome history

### F7: Auto-run bd doctor on SessionStart
**What:** Add bd doctor check to SessionStart hook, blocking sprint start on corruption.
**Acceptance criteria:**
- [ ] SessionStart hook runs `bd doctor --deep` (non-blocking by default)
- [ ] If corruption detected: block sprint start with clear error message
- [ ] Configurable: `bd.auto_doctor: false` in `.beads/config.yaml` disables
- [ ] Doctor results cached (skip if last run <1hr ago)

### F8: Deletion-recovery test harness
**What:** Build a test harness that deletes calibration state, runs N sprints, measures degradation and recovery.
**Acceptance criteria:**
- [ ] Script that: (1) snapshots calibration state, (2) deletes all calibration files, (3) runs N sprints on standard workload, (4) measures key metrics, (5) restores snapshot
- [ ] Metrics collected: cost per sprint, duration, gate pass rates, routing tier distribution
- [ ] Pass criteria configurable (default: amnesiac >15% worse on ≥2 metrics)
- [ ] Recovery measurement: run until metrics return to baseline or N sprints exceeded
- [ ] Report generated: `docs/reports/deletion-recovery-YYYY-MM-DD.md`

### F9: Publish v1.0 roadmap artifact
**What:** Write the canonical roadmap document with track definitions, version gates, progress tracking, and current state assessment.
**Acceptance criteria:**
- [ ] `docs/roadmap-v1.md` published with 3 tracks, 4 levels each, 4 version gates
- [ ] Current state assessed with evidence (not just claims)
- [ ] Exit criteria for each milestone are concrete and measurable
- [ ] Progress tracking mechanism defined (how do we know when a level is reached?)
- [ ] Linked from root AGENTS.md or docs index

## Feature Dependencies

```
F5 → F6 → F3  (outcome recording → schema → calibration algorithm)
F1 → F2        (fix signal path → auto-trigger calibration)
F4             (independent)
F7             (independent)
F3 + F1 + F4 → F8  (all loops closed → validate with deletion test)
F9             (independent, can ship first)
```

## Non-goals

- v0.8/v0.9/v1.0 detailed planning (this PRD scopes v0.7 only; later milestones get their own PRDs)
- External project onboarding (C:L2, starts after v0.7)
- L3 auto-remediation (A:L4, v0.9 scope)
- Adversarial testing suite (B:L4, v0.9 scope)
- Pass@k evaluation harness (v0.8 scope)
- Onboarding UX work (C:L4, v1.0 scope)

## Dependencies

- intercore gate evaluation (`ic gate check`) — F3, F5, F6 modify this path
- interspect evidence pipeline (`lib-interspect.sh`) — F1, F2 fix and extend this
- Clavain sprint hooks (`SessionStart`, `SessionEnd`) — F2, F4, F7 add triggers
- interstat cost data — F4 calibration reads from cost-query.sh output
- beads doctor (`bd doctor`) — F7 integrates as pre-flight

## Open Questions

1. **Gate calibration algorithm:** Simple historical average with confidence bands? Or Bayesian updating? Start simple (average + 1 SD), evolve later.
2. **Deletion test workload:** What defines the "standard workload" for F8? Self-building tasks? A curated set? Need a reproducible problem set.
3. **Anomaly detection scope:** F4 flags >2x estimated tokens. Should this extend to all calibrated systems (routing, gates) for v0.7, or defer to v0.8?
4. **Cross-track dependencies:** F3 (Track A × Track B overlap) — does it count toward A:L3, B:L2, or both?
