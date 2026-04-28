# sylveste-9lp.25.3 — learned orchestration shadow evaluator report

No production routing changes; replay-only receipts.

## Verdict

- Phase-0 recommendation: `NO_GO_ENFORCE__KEEP_SHADOW`.
- Enforce threshold: blocked until >=30 joined examples, >=10 negatives, >=5 positives, 100% positive preservation, 100% safety/fallback, and human sign-off.
- Prospective shadow gate met: `false`.

## Corpus

- Total examples: 14
- Negative / instrumentation examples: 11
- Positive controls: 3

## Metrics

- Negative recall: 100.00%
- Positive-control regressions: 0
- False positives: 0
- False negatives: 0
- False-unsafe proposal rate: 0.00%
- Policy block correctness: 100.00%
- Fallback availability: 100.00%
- Safety-floor preservation: 100.00%
- Evidence traceability: 100.00%
- Over-escalation cases: 1
- Under-escalation cases: 1
- Budget-risk cases: 3

## Governor decisions

- `baseline_only`: 3
- `block`: 8
- `needs_human`: 3

## Baseline caveats

- Static fallback is always available and equals the recorded historical route.
- B2 is derived only where a task complexity signal is present; ambiguous `mixed` examples are marked unavailable.
- B3 is marked unavailable in phase 0 unless a route_id/model/outcome join exists; seed prose is not laundered into a calibration label.

## Next gate

Keep this evaluator in shadow/replay mode. The next useful move is collecting joined route/outcome receipts until the Phase-1 gate from `sylveste-9lp.25.2` is satisfiable.

## Per-example receipts

| Example | Decision | Risk hit | FP | FN | Budget risk | Notes |
|---|---|---:|---:|---:|---:|---|
| lo-seed-001 | block | yes | no | no | no | known seed risk blocks enforcement; shadow receipt only |
| lo-seed-002 | block | yes | no | no | no | known seed risk blocks enforcement; shadow receipt only |
| lo-seed-003 | block | yes | no | no | yes | known seed risk blocks enforcement; shadow receipt only |
| lo-seed-004 | block | yes | no | no | no | known seed risk blocks enforcement; shadow receipt only |
| lo-seed-005 | block | yes | no | no | no | known seed risk blocks enforcement; shadow receipt only |
| lo-seed-006 | block | yes | no | no | yes | known seed risk blocks enforcement; shadow receipt only |
| lo-seed-007 | block | yes | no | no | no | known seed risk blocks enforcement; shadow receipt only |
| lo-seed-008 | block | yes | no | no | no | known seed risk blocks enforcement; shadow receipt only |
| lo-seed-009 | needs_human | yes | no | no | no | requires joined labels/instrumentation before scoring authority |
| lo-seed-010 | needs_human | yes | no | no | yes | requires joined labels/instrumentation before scoring authority |
| lo-seed-011 | needs_human | yes | no | no | no | requires joined labels/instrumentation before scoring authority |
| lo-seed-012 | baseline_only | yes | no | no | no | positive control preserved as baseline/no-change |
| lo-seed-013 | baseline_only | yes | no | no | no | positive control preserved as baseline/no-change |
| lo-seed-014 | baseline_only | yes | no | no | no | positive control preserved as baseline/no-change |
