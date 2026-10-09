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
private paths and a host name (the pre-push guard refuses them). The substitutions are
mechanical, and the tests pass on the shipped bytes. The wrapper `gate0-run.sh` and its
test are new in this change and are not a Gate 0 original.

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
`GATE0_JOURNAL_TRIES`, `GATE0_QUIESCE_WAIT`, `GATE0_STATUS_CMD`, `GATE0_UNINSPECTABLE_UIDS`, `AUTOSYNC_LANE_LIB`. See the header of the script.

Unit control (`GATE0_TIMER_CTL`, default `systemctl --user`): the controller is called as
`CTL stop|start|active UNIT`. For `active`, exit 0 means active, exit 3 means inactive,
and any other result (a missing bus, a controller error) is unknown, which the wrapper
treats as a STOP; an error is never read as "inactive". The wrapper keeps its state
directory, journal and preservation copy outside the checkout and its git directory
(checked by physical path, before anything is created), runs no step that rewrites the
index to refresh stat data (`GIT_OPTIONAL_LOCKS=0`), and keeps the predictor's own stderr
and report sender out of the prediction the verifier reads. The freeze is re-checked
(timers, services, marker, agent processes, bd) at every capture, immediately before
the checkout is realigned, and before every restart and rollback.

Further properties, each with a test and a mutation control in `gate0-run-test.sh`:

- Process listings fail closed. If `ps` cannot be read, or the agent listing (`/proc`, else
  `lsof`) does not show the wrapper itself or the listing command exits non-zero, the wrapper
  stops: a failed or partial listing is not "no agent and no bd". `GATE0_PROCFS` (default `/proc`) names the process
  file system; the test points it elsewhere to force the `lsof` branch.
- A live process whose working directory cannot be read (the `/proc` branch) is a STOP naming
  its pid and uid: it cannot be ruled out as an agent. Only a process that has gone, a zombie, or
  one owned by an account listed in `GATE0_UNINSPECTABLE_UIDS` (space separated, default empty) is
  skipped; readable processes of a listed account are still examined. The `lsof` branch cannot see or
  classify processes that `lsof` does not list; that limit is not closed by this wrapper.
- A freeze that fails part-way has already stopped some timers. The restart set is written to
  `freeze-intent` before the first stop, and a repeated freeze takes the union of that set and the
  timers active now, so a timer stopped by the failed attempt is still restarted later.
- A cleanup (`rbail`) reads each recorded timer and service back after stopping it. A unit that is
  not confirmed inactive is named in the message ("UNCONFIRMED"), and the STOP says so.
- Clavain restart: an earlier drift report is not evidence about this sweep. It is set aside before
  the sweep, and only a report the sweep wrote is verified; if none is written the earlier report is
  put back as found and the restart stops. The sweep's own exit status is logged, not judged.
- Children are confined too: the log directory, `gate0-run/` and each preservation
  directory must be plain physical children outside the checkout, its git directory and
  the journal (a symlinked `logs/` or `gate0-run/` is refused; a symlinked preservation
  directory is a STOP before the checkout is realigned).
- `bd` and the steps run with the checkout as their working directory, whatever the caller's.
- A restart that is already recorded runs nothing: it re-verifies that the recorded timers
  are active and the marker is the one set aside. A `freeze` after a completed restart is a new
  attempt: it stops the timers and moves the marker aside again, and clears the earlier restart
  records once the new freeze is recorded.
- The marker put back by a restart (server or Clavain) must be byte for byte the one the freeze
  record names; otherwise it is removed and the restart stops before anything runs.
- A restarted timer is checked live: a controller that returns success while the timer stays
  inactive is treated as a failed restart (timers stopped again, marker aside, no record).
- `--check` phases run `cutover-steps.sh` with its reporting off, so an inherited
  `CUTOVER_LOG_DIR` cannot make a check write into the journal or the checkout.
- If a successful restart cannot be recorded, the wrapper stops the attempt's timers and
  puts the marker aside again, as for any other failed restart.
- A new freeze after a completed restart clears the earlier restart records only after the new
  freeze record is written, and removes the restart-set intent last, so a crash at either point
  leaves a set the repeated freeze can still read. A repeated freeze that finds the record already
  holding also removes a leftover intent.
- Reconciliation separates a tracker file that is absent from a commit (the tree does not list it:
  nothing to dominate) from one that cannot be read (the tree lists it, or cannot be listed): the
  second is a STOP, never an empty file.
- The service's journal is read from a cursor taken just before the start (`--after-cursor`), so a
  summary line left by an earlier run is never taken for this run's. If no cursor can be taken, the
  restart stops before anything starts.
- A recorded restart whose timers or marker no longer match the record is undone like any other
  failed restart: the record is removed, every timer of the attempt is stopped and the marker is
  aside, so a later restart is a new attempt.
- A recorded restart whose timer state cannot be read (the controller errors) is not a hard stop
  that skips cleanup: it goes through the same cleanup, and the STOP names the units that are not
  confirmed stopped ("UNCONFIRMED").
- Cleanup does not depend on the marker matching the record. If the marker in the checkout differs
  from the recorded one, its bytes are first kept beside the record as `marker.unexpected.<sha256>`
  (copied, flushed and compared), then the live file is removed. A `freeze` still stops when a
  different marker is already set aside, because that is an operator decision.
- A restart marks its attempt (`restarting-<name>`) before its first side effect and closes the mark
  only after the completion record is written. A restart that is cut off in between (the marker back,
  the service run, some timers started) is found by the next restart, which undoes it (every timer
  stopped, marker aside, mark cleared only when every unit is confirmed stopped) and stops; the restart
  after that is a new attempt.
- A restart recorded with no marker (the freeze found none) checks that no marker has appeared; one that
  has is undone like any other mismatch. A cleanup with no marker recorded keeps a marker it finds as
  `marker.unexpected.<sha256>` and removes the live file, without creating a marker record.

The wrapper's own sha256 changes with any edit. A handoff cites the digest of the final bytes.
