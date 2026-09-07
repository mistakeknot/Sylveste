# Four-week pre-Mythos session cadence dial-up plan

Bead: `sylveste-oyrf.1`

Status: planned cadence ramp. This document defines the 4-week pre-Mythos execution plan; it does not claim the four weeks have already elapsed.

## Objective

Increase session cadence only when the closed-loop cost-calibration signal remains legible. The session cadence dial-up should make Mythos launch readiness observable without turning the live Interverse/Sylveste workspace into uncontrolled agent churn.

## Week 1 — Instrument and stabilize

- Run `estimate-costs.sh` through the six-hour GitHub Actions cadence.
- Confirm `data/cost-trajectory.csv` receives structurally valid rows.
- Keep Mythos dry-runs fixture-only unless Interstat metrics are verified.
- Record any `interstat-empty` streak longer than one day as an instrumentation fault, not as true zero cost.

## Week 2 — Controlled increase

- Add one additional bounded operator session per workday for Mythos candidate work.
- Keep work packets bead-scoped and reviewable.
- Compare cost per session against Week 1 baseline.
- Do not broaden model routing until the cost curve is stable.

## Week 3 — Parallelism rehearsal

- Introduce limited parallel sessions only for independent beads with low collision risk.
- Require explicit before/after workload handles for any Mythos transition harness run.
- Use the closed-loop page to check whether increased throughput is matched by manageable cost growth.
- Record intervention count and failed runs alongside cost.

## Week 4 — Launch-readiness rehearsal

- Run a Mythos candidate workload through the full dry-run harness first.
- If Interstat data is available, repeat the same workload with live cost capture.
- Decide whether cadence can continue, pause, or roll back based on cost per completed session and reintegration quality.
- Prepare a final launch note that references the cost trajectory, harness summary, and Beads evidence.

## Stop conditions

- `interstat-empty` persists for more than one day during an intended measurement window.
- Cost per completed session rises materially without an offsetting quality or continuity gain.
- Parallel sessions produce unresolved file collisions or ambiguous Beads ownership.
- Review gates start passing without enough public/repo evidence to reconstruct the work.

## Review cadence

At the end of each week, review the newest `cost-trajectory.csv` rows and summarize:

1. session cadence actually attempted,
2. cost trend,
3. quality/reintegration trend,
4. open blockers,
5. whether the next week's pre-Mythos ramp should proceed.
