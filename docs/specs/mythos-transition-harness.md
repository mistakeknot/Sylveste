# Mythos transition harness

Bead: `sylveste-oyrf.1`

The Mythos transition harness is the pre-launch comparison loop for deciding whether a proposed Mythos operating mode changes cost, session cadence, or closed-loop quality enough to block launch.

## Harness entrypoint

Run the safe harness wrapper:

```bash
scripts/mythos-transition-dry-run.sh --before main --after mythos-candidate
```

The wrapper invokes `estimate-costs.sh --dry-run` for the `before` and `after` labels, writes isolated CSV fixtures under a temporary output directory by default, and emits a markdown summary. The default path is intentionally dry-runnable without private Interstat metrics, branch checkout, network calls, or credentials.

## Comparison contract

A real Mythos transition review must compare **identical workloads** across the `before` and `after` modes. The workload should be the same bead set, same acceptance criteria, same model-routing policy unless model routing is the variable under test, and the same review gate.

Minimum fields to compare:

1. Cost trajectory row from `estimate-costs.sh` for the baseline window.
2. Session count and session cadence pressure.
3. Total tokens and estimated USD.
4. Evidence quality: whether the closed-loop handoff could be reproduced from public artifacts plus CASS/session evidence.
5. Operator intervention count: clarifications, manual resets, failed runs, and review escalations.

## Dry-run semantics

`estimate-costs.sh --dry-run` produces deterministic `dry-run-fixture` rows. That mode proves the CSV/export/harness plumbing and should pass in CI. It does **not** prove Mythos is cheaper or ready.

When Interstat data is available, rerun the harness with the same before/after workload and archive:

- the two generated cost CSVs,
- the markdown summary,
- the bead IDs used as workload handles,
- the Git commit/ref for each mode,
- any reviewer notes that explain non-cost tradeoffs.

## Launch gate

Mythos transition is ready only when the `after` mode is no worse than `before` on cost per completed session or has an explicit doctrine-approved reason to pay the delta. Cost deltas must be interpreted alongside quality and continuity; cheaper-but-less-reintegrable runs should not pass the harness.
