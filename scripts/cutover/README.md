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
- Capture validates the archive destination again after the last freeze check, immediately before the
  checkout is realigned, and the destination's push URL must be the one the lane library just validated;
  a destination that stopped being acceptable, or a push URL that changed in between, is a STOP before P1a
  pushes anything. (The push inside `cutover-steps.sh` itself cannot be re-validated from outside; that
  file is not edited by this wrapper's change, so only the read-back after its push covers a change made
  after this check.)
- The preservation copy is flushed file by file (the temporary copy before it is moved, each verified file
  and the directory) with the status of each flush checked; a flush that fails is a STOP and the capture is
  not recorded. `sync` is tried first, then an `fsync` of the path.
- A Clavain restart recorded with no marker reads the lane tip with its exit status: a lane that cannot be
  read is a STOP, never "unchanged".
- A cleanup (`rbail`) stops the services as well as the timers before it reads them back, so a service a
  cut-off restart left running is stopped, and the next restart is a new attempt.
- A restart reads the lane tip and the archive branches before and after the run with the exit status
  checked: a read that fails is a STOP (marker aside, timers stopped), never an empty listing that equals
  another empty listing.
- The service a restart starts (`git-autosync-repair.service`) is always part of the service list the freeze
  and the cleanup stop and read back, whatever `GATE0_UNITS_SERVICES` names.
- The reference-transaction hook is checked again every time the freeze is confirmed (before capture's
  fetch and realign, before a rollback and before a restart), not only at preflight: a writing hook
  installed after preflight is a STOP before any later git command can run it.
- Every read whose status or content a decision rests on is checked where it is used, not trusted from an
  earlier phase: a snapshot or compare that reads from git, the lane, `lsof` or the unit controller checks
  each stage's status (`set -o pipefail` or an explicit status) and refuses an empty result where a
  non-empty one is required, so two failed reads never compare equal. This covers the git directory, the
  commit count and both status reads at preflight, `core.hooksPath` and the hooks directory, the hook's
  hash, the marker's hash at the freeze, the archive listing (including its use in a restart), the head the
  preflight record names, the P1-pre head, the base's tree and the index's tree after P1a, the status, tag
  and journal-cursor reads of a restart, and the P0 lane record of a Clavain restart. A hash that fails
  prints nothing and fails, including a tool that prints a digest and then exits nonzero; a recorded marker
  that is not a sha256 is never compared with a hash. The production unit controller branch accepts a state
  only when the word and the exit status agree (`active` with 0; `inactive` or `failed` with a nonzero
  status); `activating`, `reloading`, `deactivating` and a word that disagrees with its status are unknown,
  and unknown is a STOP. The journal read after the service start must succeed: lines printed by a read
  that then failed are not evidence, and the failure leaves the marker aside with the timers stopped. A
  failed `lsof` listing or filter, and a failed read of `origin/main` behind `--check`, are STOPs and never
  an empty result equal to another empty result. The reviewed pipelines that stay as they are (`ps | tr`
  in the ancestor walk, where a failure only makes more processes count as agents; the count and status
  strings, where an empty value never equals the expected one; the Clavain lane-tip compare, whose read is
  status-checked and whose record is required to exist) are fail-safe by construction.
- Records and values read back are read with their status checked, and an empty value is accepted only
  after a successful read. This covers the freeze record's timer and marker lines (at the freeze repeat,
  the earlier freeze intent, the cleanup, a recorded restart and step 5), P1-pre's status record at an R0
  without P1a and its filter, the P0 lane record, the approved inputs, the sha256 record of the capture
  (it must name exactly the bundle and the W-snapshot), the archive's push URL, the unmerged-entries read,
  and the filter behind the marker rule. A read that prints the expected value and then fails is not a
  match: the compares of the checkout's state (HEAD's name, the heads, the count, the tag) use a helper
  that returns the value only when the read succeeded. The cleanup that returns a restart to the frozen
  state never skips the timers because its record is unreadable: it stops every configured timer
  instead, reads each back, and says so when one cannot be confirmed stopped. The lane-tip fields are cut
  with a shell expansion, so no command's lost status can leave an empty tip.
  The same holds for the restored marker's recorded hash, the list of timers written to the freeze intent
  and the freeze record (a list that fails after its output is not written, and nothing is stopped), and the
  capture's sha256 record: it is read to its last line even without a final newline, exactly two digests must
  be checked, and the preservation copy is staged and verified before it replaces the copy already there,
  so a capture that does not match its record never overwrites a verified backup.
  The names in that record are read with the read's own status (a read that prints both names and then
  fails is a STOP), and a restart checks both entries of the capture in the journal itself before it runs
  the pinned `preserved` step, which reads the record with a loop that drops a last line with no newline.
  The `jsonl_dominated` definition is taken from the steps with the extraction's status held and the whole
  function checked, and its load is checked, so an inherited function never stands in for it. Single-command
  reads that were compared inside `[ ... ]` (the marker record, the checkpoint, the ahead/behind count, a
  process state) are held in a variable with their status first.
  A restore of the set-aside marker over other bytes in the checkout keeps those bytes first, and the
  Clavain restart stops when the freeze record cannot be read instead of treating it as one that names no
  marker.
- A step that acts on a recorded value re-validates it at the point of use: the P1-pre head must be a
  commit sha every time it is read, the marker record must hold a sha256 before it is compared, and a
  restart validates the archive destination and its push URL again itself (server and Clavain) instead of
  trusting preflight. The gate in `cutover-steps.sh` still runs first; where it refuses a damaged record
  the wrapper's own check is a second line that is reached only when that step is bypassed.

The wrapper's own sha256 changes with any edit. A handoff cites the digest of the final bytes.
