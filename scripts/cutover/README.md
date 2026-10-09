# scripts/cutover

Tooling for moving a checkout of this repository from a tree that tracks internal
documents to a public tree plus a private overlay (`scripts/git-internal`). It is code
only. Nothing here runs when the pull request that adds it is merged, and merging
does not cut over any checkout; each checkout is cut over separately by its operator
(bead mk-z9st.22, parent mk-z9st).

## Contents

| File | Purpose |
| --- | --- |
| `cutover-steps.sh` | Journalled, idempotent cutover steps: `p0`, `p1-pre`, `p1a`, `p2`, `forward`, `rollback`, `recover`, `unfreeze-gate`, `preserved`, `--check`. Exit 0 ok, 1 usage or refused, 2 fetch failed, 3 STOP. |
| `restart-predict.sh` | Predicts the outcome of restarting autosync after a step (`server`, `clavain`, `verify`), so a restart that would delete or overwrite work is refused first. |
| `gate0-run.sh` | The production wrapper around the Gate 0 steps: preflight, freeze, capture, rollback, restart. |
| `gate0-run-test.sh` | Runs the real wrapper and the real `cutover-steps.sh` on synthetic local repositories with stubbed unit control, journal, lane library and predictor. Includes mutation controls. |
| `p1a-flush-test.sh` | Full-P1a flush-failure test: removing P1a's caller-side STOP on a failed flush must turn the test red. |
| `rh-gate0.sh` | The Gate 0 rehearsal against the real autosync repair script. |
| `crash-inject.sh`, `cutover-repro.sh`, `lane-sync-test.sh` | Crash-injection, reproduction and lane-sync tests. |
| `acceptance-grep.py` | Counts pattern hits in a tree against a pattern table, a defer list and a ceiling. |
| `repro-r5/` ... `repro-r8.1/` | Fixtures for the reproduction tests. |

The test scripts and the shipped copies of the Gate 0 scripts were edited to remove
private paths and a host name (the pre-push guard refuses them). The edits are
mechanical substitutions; behaviour is unchanged and the tests pass on the shipped bytes.

## Running the tests

Every test uses only synthetic content and a scratch directory.

```
T_ROOT=/path/to/scratch scripts/cutover/gate0-run-test.sh
T_ROOT=/path/to/scratch GI_TREE=/path/to/this/checkout scripts/cutover/p1a-flush-test.sh
```

`--check` on any script validates syntax and required tools and writes nothing.
`T_ROOT` is the parent for scratch directories (default `$TMPDIR`, else `/tmp`); a
failing run keeps its scratch directory and prints its path. `GI_TREE` is the root of
the checkout that holds the shipped bytes under test.

## The wrapper: `gate0-run.sh`

```
gate0-run.sh --check                 syntax and tools only
gate0-run.sh --check PHASE           the phase's read-only checks; writes nothing to the checkout or the journal
gate0-run.sh preflight               readiness and the P0 record; refuses a writing reference-transaction hook
gate0-run.sh freeze                  presence phrase, no agents or bd in the checkout, timers and services stopped, marker moved aside
gate0-run.sh capture                 P1-pre, P1a, a re-check, then the preservation copy verified by sha256
gate0-run.sh rollback                R0a (before the merge only)
gate0-run.sh restart r0|p10|r6       unfreeze gate, preservation, reconciliation, prediction, one repair run, verification, timers back
```

The operator writes the approved inputs into the journal directory first: `base`,
`host`, `lane-remote`, `dispositions`, `pr1-head`, `delete-list`. A missing input is a
refusal before anything is written. A STOP (exit 3) leaves the checkout, the marker
and the timers as they were, except that a failed restart leaves the marker aside and
the timers stopped. The wrapper re-runs as the operator when started as root.

Environment knobs (all optional; defaults are the production values): `GATE0_ROOT`,
`GATE0_STATE_DIR`, `GATE0_JOURNAL`, `GATE0_PRESERVE_DIR`, `GATE0_MACHINE`, `GATE0_REL`,
`GATE0_OPERATOR`, `GATE0_OPERATOR_HOME`, `GATE0_PATH`, `GATE0_CS`, `GATE0_PRED`,
`GATE0_BD`, `GATE0_TIMER_CTL`, `GATE0_UNITS_TIMERS`, `GATE0_UNITS_SERVICES`,
`GATE0_CONFIRM_FILE`, `GATE0_READONLY_HOOKS`, `GATE0_REPORT_TELL`, `GATE0_REPORT_TITLE`,
`GATE0_JOURNAL_TRIES`, `GATE0_QUIESCE_WAIT`, `GATE0_STATUS_CMD`, `AUTOSYNC_LANE_LIB`. See the header of the script.

The wrapper's own sha256 changes with any edit. A handoff cites the digest of the final bytes.
