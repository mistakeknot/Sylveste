# Brief: verdict register listing (validation-seat demonstration, unrun)

Contract: brief

## Objective

The Pattern F verdict register lists every recorded row with its eight columns (ts, session, role, kind, verdict, plan, commit, note), so an orchestrator can read a run back.

## Scope

`scripts/pattern-f-verdict.sh` and its tests in `tests/shell/pattern_f_verdict.bats`.

## Constraints

No schema change; the existing bats suite is the specification.

## Authority

None: this brief is validated only, nothing is committed.

## Acceptance Criteria

1. `bash -n scripts/pattern-f-verdict.sh` exits 0.
2. `bats tests/shell/pattern_f_verdict.bats` reports every test ok.

## Verification

```bash
cd /private/tmp/claude-501/-Users-sma-projects/aa2bb078-ee16-4c32-9f97-01ef7dbdec61/scratchpad/broken/clavain
bash -n scripts/pattern-f-verdict.sh
bats-replay-runner tests/shell/pattern_f_verdict.bats 2>&1 | tail -4
```

## Deliverables

diff or commit, checks run, failures, unresolved questions
