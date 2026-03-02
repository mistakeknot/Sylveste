# fd-intercom-scheduler-reliability

**Reviewer role:** Distributed systems engineer, at-least-once delivery guarantees and idempotent task execution.
**Date:** 2026-03-02
**Codebases reviewed:**
- `research/hermes_agent/cron/` — Python asyncio reference implementation
- `apps/intercom/rust/intercomd/src/scheduler.rs` + `scheduler_wiring.rs`
- `apps/intercom/rust/intercomd/src/db.rs` (HTTP endpoints)
- `apps/intercom/rust/intercom-core/src/persistence.rs` (SQL operations)
- `apps/intercom/rust/intercom-core/src/ipc.rs` (IPC types)
- `apps/intercom/rust/intercomd/src/ipc.rs` (IPC watcher)

---

## Summary

The intercom scheduler has three significant reliability gaps. The most critical
is an unguarded crash window between container dispatch and `next_run` write-back
— a crash during execution leaves the task with its old `next_run` in the past,
causing perpetual re-dispatch on every poll. The second critical gap is the
absence of any dispatch-exclusion mechanism in the Rust scheduler: the file lock
in Hermes that prevents double-dispatch has no equivalent in intercom, leaving
concurrent multi-replica or crash-restart scenarios exposed. The third is that
audit log and status update are issued as two independent SQL calls; a crash
between them produces an orphaned run log row with no matching status change.

---

## Area 1 — Delivery Acknowledgement: TOCTOU Window Analysis

### Hermes reference behaviour

`tick()` in `scheduler.py:304–326` runs jobs sequentially inside a file lock.
`mark_job_run()` is called at `scheduler.py:320` — *after* `run_job()` returns
and *after* `_deliver_result()` completes. The call sequence is:

```
run_job()            → returns (success, output, response, error)
save_job_output()    → writes output file
_deliver_result()    → sends to platform
mark_job_run()       → updates next_run + last_run + completed count
```

`mark_job_run()` at `jobs.py:321–357` does an atomic JSON rewrite via
`tempfile.mkstemp` + `os.replace()` (`jobs.py:204–210`). The TOCTOU gap here is
narrow: `mark_job_run` does a `load_jobs()` / mutate / `save_jobs()` cycle, so
a concurrent write by another process between the load and save would silently
win. However, the file lock in `tick()` prevents two ticks from running
simultaneously, which is the dominant protection.

**Hermes delivery-then-mark order matters:** if delivery succeeds but the
process crashes before `mark_job_run()`, the task runs again on next tick
(at-least-once, not exactly-once). Hermes deliberately accepts this tradeoff
— `next_run_at` in `jobs.json` is only updated *after* a confirmed call.

### Intercom behaviour

The intercom re-verify fetch (`scheduler.rs:155`) re-reads the task by ID and
checks `status == "active"` before dispatching. This does *not* close the
TOCTOU window — it only prevents dispatching a task that was paused or deleted
between the bulk `get_due_tasks` query and individual dispatch. It does not
mark the task as "in-flight" before dispatching; `next_run` is only advanced
*after the container finishes* in `log_and_update()` at `scheduler_wiring.rs:267`.

**The sequence is:**

```
get_due_tasks()        persistence.rs:713  — reads next_run <= now
get_task_by_id()       scheduler.rs:155    — re-verify active (no lock)
on_task() callback     scheduler_wiring.rs:65  — enqueue via GroupQueue
... container runs ...
log_and_update()       scheduler_wiring.rs:267 — compute next_run, write to DB
```

**P1 — Gap:** Between `get_due_tasks` and `log_and_update`, the task row still
carries the old `next_run` (which is <= now). If the next poll fires before
`log_and_update` completes (poll interval is 10 seconds, tasks may run much
longer), `get_due_tasks` will return the same task again. The re-verify check
does not prevent this: the task is still `status = 'active'`, and `next_run` is
still <= now.

**Affected files/lines:**
- `apps/intercom/rust/intercomd/src/scheduler.rs:148–184` — poll loop with no pre-dispatch lock
- `apps/intercom/rust/intercom-core/src/persistence.rs:713–731` — `get_due_tasks` SQL (plain SELECT, no UPDATE)
- `apps/intercom/rust/intercomd/src/scheduler_wiring.rs:263` — `log_and_update` called only on completion

---

## Area 2 — `update_task_after_run` Crash Gap: Skip-on-Restart Risk

### Hermes reference behaviour

Hermes computes `next_run_at` inside `mark_job_run()` at `jobs.py:350`:
```python
job["next_run_at"] = compute_next_run(job["schedule"], now)
```
This is computed at mark-time (post-run), and the result is atomically saved
alongside all other state in a single `save_jobs()` call. There is no window
between "compute next_run" and "persist next_run" — they are the same
`os.replace()` call.

### Intercom behaviour

`calculate_next_run()` is called in application code at
`scheduler_wiring.rs:292`:
```rust
let next_run = calculate_next_run(&task.schedule_type, &task.schedule_value, timezone);
```

This value is then passed to `pool.update_task_after_run()` at
`scheduler_wiring.rs:295–299`. The gap is:

1. Container finishes execution.
2. `log_task_run()` is called at `persistence.rs:771` — INSERT into `task_run_logs`.
3. `update_task_after_run()` is called at `persistence.rs:733` — UPDATE `scheduled_tasks`.
4. If the process crashes between steps 2 and 3, `task_run_logs` has a row for
   the run, but `scheduled_tasks.next_run` still holds the old value (<= now).
5. On restart, `get_due_tasks` sees the same old `next_run` and re-dispatches
   the task — a double-execution with no indication that it ran successfully.

**P1 — Primary gap:** Two separate SQL calls with no transaction wrapping.
A crash after `log_task_run` but before `update_task_after_run` leaves the
task in a re-dispatchable state indefinitely.

**P2 — Secondary gap:** `next_run` is computed in Rust application code before
the write, meaning clock skew or a very brief pause between compute and persist
introduces a drift from Postgres server time. For `"cron"` schedules, the
`calculate_next_run` call uses `Utc::now()` at `scheduler.rs:80` inside the
application process, whereas the `get_due_tasks` comparison uses `now()` at
the Postgres server (`persistence.rs:720`). These can diverge under load.

**Affected files/lines:**
- `apps/intercom/rust/intercomd/src/scheduler_wiring.rs:287–299` — sequential log + update, no transaction
- `apps/intercom/rust/intercom-core/src/persistence.rs:771–796` — `log_task_run` INSERT
- `apps/intercom/rust/intercom-core/src/persistence.rs:733–769` — `update_task_after_run` UPDATE
- `apps/intercom/rust/intercomd/src/scheduler.rs:80` — `Utc::now()` used for cron next-run vs Postgres `now()`

---

## Area 3 — Lock Exclusivity: File Lock vs Mutex / Advisory Lock

### Hermes reference behaviour

`tick()` acquires an exclusive non-blocking `fcntl.flock` on
`~/.hermes/cron/.tick.lock` at `scheduler.py:285–291`:
```python
fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
```
If another tick holds the lock (gateway + daemon + systemd timer overlap),
the new tick returns 0 immediately without running any jobs. The lock is held
for the entire tick duration and released in `finally` at `scheduler.py:329–336`.
This guarantees that at most one process dispatches a given job at a time.

### Intercom behaviour

The `run_scheduler_loop()` at `scheduler.rs:121` runs inside a single tokio
task. There is no Postgres advisory lock, no distributed mutex, and no
"claimed" status field on the task row. The only protection against concurrent
dispatch is the re-verify `get_task_by_id` check — but this only catches
explicit status changes (pause/delete), not concurrent dispatch from another
`intercomd` instance.

**P1 — Missing dispatch exclusion:** If two `intercomd` instances start
simultaneously (e.g., during a rolling restart, or if systemd restarts a
crashed daemon before the previous process fully exits), both will poll
`get_due_tasks`, both will see the same tasks with `status = 'active'` and
`next_run <= now`, and both will pass the re-verify check. Both will enqueue
and run the task.

The standard fix in Postgres-backed schedulers is a `SELECT ... FOR UPDATE SKIP LOCKED`
pattern that atomically claims tasks. The current `get_due_tasks` SQL at
`persistence.rs:717–721` is a plain `SELECT`:
```sql
SELECT * FROM scheduled_tasks
WHERE status = 'active' AND next_run IS NOT NULL AND next_run <= now()
ORDER BY next_run
```

No `FOR UPDATE SKIP LOCKED`, no CAS update to an `in_progress` status before
returning rows.

**Affected files/lines:**
- `apps/intercom/rust/intercom-core/src/persistence.rs:713–731` — `get_due_tasks` plain SELECT
- `apps/intercom/rust/intercomd/src/scheduler.rs:148–183` — no advisory lock before dispatch

---

## Area 4 — Delivery Truncation Guard: Output Size Limits

### Hermes reference behaviour

The `__init__.py` docstring and `_deliver_result()` call in `scheduler.py:313`
passes `final_response` directly to `_send_to_platform()` with no truncation.
The module constant `MAX_PLATFORM_OUTPUT=4000` mentioned in the review brief
is not present in the reviewed codebase; the codebase contains no such guard.
`result_summary()` in `scheduler.rs:106–118` truncates to 200 characters, but
that is the DB summary field, not the delivery content.

### Intercom behaviour

In `scheduler_wiring.rs:169–175`, the full `output.result` text is passed
directly to `telegram.send_text_to_jid()`:
```rust
if let Some(ref text) = output.result {
    if !text.is_empty() {
        if let Err(e) = telegram.send_text_to_jid(&chat_jid, text).await {
```

No size check before the Telegram send. The `result_summary()` truncation at
`scheduler.rs:106` applies only to `last_result` stored in `scheduled_tasks`
(200 chars). The actual Telegram message carries the full container output.

**P2 — Telegram message size:** Telegram's Bot API caps single messages at
4096 UTF-8 characters. Container agent responses may be longer. A long
response will be silently truncated by Telegram's API or rejected outright
(API returns 400). There is no chunking or truncation guard in the delivery
path. This is not a crash risk but a silent data-loss risk for long outputs.

**P3 — IPC message size:** The IPC protocol writes JSON files to disk
(`/workspace/ipc/{channel}/`). There is no explicit size cap on `IpcMessage.text`
at `intercom-core/src/ipc.rs:24–31`. Very large outputs are written and
read back synchronously via `fs::read_to_string` in `ipc.rs:601–605`. On
typical container storage, this is unlikely to fail, but outputs > a few MB
will hold the IPC poll thread during the read.

**Affected files/lines:**
- `apps/intercom/rust/intercomd/src/scheduler_wiring.rs:169–175` — uncapped Telegram send
- `apps/intercom/rust/intercom-core/src/ipc.rs:24–31` — `IpcMessage.text` has no size bound
- `apps/intercom/rust/intercomd/src/ipc.rs:601–605` — full `read_to_string` on IPC files

---

## Area 5 — Audit Trail Atomicity: `always_log_local` vs `log_task_run`

### Hermes reference behaviour

`save_job_output()` at `jobs.py:383–395` writes the full job output (including
prompt, schedule, response, error) to a timestamped Markdown file under
`~/.hermes/cron/output/{job_id}/{timestamp}.md`. This write happens at
`scheduler.py:308` — *before* `mark_job_run()` — so even if `mark_job_run`
fails (e.g., JSON corruption), the output file is on disk and the run is
recoverable from the filesystem audit trail. The two writes are independent
and both succeed before the job is considered "done."

### Intercom behaviour

`log_and_update()` in `scheduler_wiring.rs:267–308` issues:
1. `pool.log_task_run(&log).await` — INSERT into `task_run_logs`
2. `pool.update_task_after_run(...)` — UPDATE `scheduled_tasks`

These are sequential, independent calls with no transaction wrapper. A Postgres
connection failure or process crash between them produces one of:

- **Run logged, task not advanced:** `task_run_logs` has a row. `next_run` is
  still <= now. On restart, the task re-dispatches. On completion, a second
  `task_run_logs` row is inserted. This is detectable (duplicate entries for
  the same logical run window) but not prevented.

- **Neither logged nor advanced** (both fail): The run is invisible in
  `task_run_logs`. The task re-dispatches. No audit record exists for the
  first execution.

**P1 — No transaction wrapping for `log + update`:** The two calls at
`scheduler_wiring.rs:287–299` must be wrapped in a BEGIN/COMMIT to be
atomic. Currently they are:
```rust
if let Err(e) = pool.log_task_run(&log).await {
    error!(...);
}
// ...
if let Err(e) = pool.update_task_after_run(&task.id, ...).await {
    error!(...);
}
```
The first `Err` is logged but execution continues to the second call.

**P2 — No filesystem fallback:** Unlike Hermes, intercom has no local
file-based audit trail. If Postgres is unavailable, run history is lost
entirely. The `error!()` log at `scheduler_wiring.rs:288` is the only
durability mechanism when Postgres is down.

**Affected files/lines:**
- `apps/intercom/rust/intercomd/src/scheduler_wiring.rs:287–299` — two sequential DB calls, no transaction
- `apps/intercom/rust/intercom-core/src/persistence.rs:160–167` — `with_client()` helper acquires a single connection but does not expose transaction control

---

## Area 6 — Schedule Parsing: Timezone Edge Cases and Parse Failure Surfacing

### Hermes reference behaviour

`parse_schedule()` in `jobs.py:64–146` handles three kinds:
- `"once"` — ISO timestamp parsed with `datetime.fromisoformat()`. Invalid
  strings raise `ValueError` immediately (caller sees a clear error message
  at job creation time, `jobs.py:125–126`).
- `"interval"` — plain integer minutes, no timezone involvement.
- `"cron"` — validated via `croniter(schedule)` at `jobs.py:106`. An invalid
  expression raises `ValueError` at creation time. **No timezone awareness:**
  `compute_next_run()` at `jobs.py:173–178` uses `croniter(schedule["expr"], now)`
  with naive `datetime.now()` (local time). If the system timezone observes DST
  transitions, a `"0 2 * * *"` job will fire at 2am local — but during a
  spring-forward the 2am slot does not exist and `croniter` will skip forward.
  During fall-back it runs twice. The bug is latent and silent.

`parse_schedule()` raises `ValueError` on invalid input, but only at
job-creation time. If `croniter` is unavailable (not installed), the error
is `"Cron expressions require 'croniter' package..."` — surfaced to the creator.

### Intercom behaviour

`calculate_next_run()` in `scheduler.rs:58–103` handles three kinds:
- `"cron"`: `cron::Schedule::from_str()` parses the expression. On parse
  failure, `error!(...)` is logged and `None` is returned at `scheduler.rs:66–70`.
  `None` returned from `calculate_next_run` is passed to `update_task_after_run`
  as `next_run = None`, which sets `status = 'completed'` in the UPDATE's CASE
  expression (`persistence.rs:757`). **A permanently invalid cron expression
  therefore silently completes the task on first dispatch** — no user-visible
  error, no notification that the cron string was rejected.

- Timezone parsing: `timezone.parse::<chrono_tz::Tz>()` at `scheduler.rs:73`.
  On failure, the code falls back to UTC with a `warn!()` at `scheduler.rs:76`.
  This is correct behaviour but the fallback is silent — the user never learns
  that their configured timezone string was invalid. All subsequent cron
  next-run calculations run in UTC instead of the configured tz, potentially
  firing at unexpected times.

- DST transitions: intercom uses `chrono_tz` for correct IANA timezone handling
  in `calculate_next_run()` at `scheduler.rs:80–84`. The `cron` crate's
  `.after(&now)` call anchored to a `chrono_tz` `DateTime` correctly handles
  DST transitions (the next occurrence is computed in wall-clock timezone
  time). This is **better than Hermes** which uses naive local time.

- `"once"` schedule: The `"once"` type returns `None` from
  `calculate_next_run` (`scheduler.rs:97`), correctly completing the task.

**P1 — Silent task completion on invalid cron:** A malformed `schedule_value`
for a `"cron"` task causes it to silently move to `status = 'completed'` after
one dispatch attempt. No error is surfaced to the creator, no `task_run_logs`
entry records the parse failure. A user who misconfigures a recurring cron job
will see it disappear without explanation.

**P2 — Silent timezone fallback:** Invalid `timezone` string falls back to UTC
with only a tracing warn. No persisted error on the task record, no notification.

**P3 — Validation not at creation time:** Task creation via the IPC
`ScheduleTask` command or the HTTP `create_task` endpoint does not validate the
cron expression or timezone string at creation. The parse failure is deferred
to first execution. Hermes validates at `parse_schedule()` time (job creation)
and surfaces the error immediately.

**Affected files/lines:**
- `apps/intercom/rust/intercomd/src/scheduler.rs:65–70` — cron parse failure returns `None`, silently completes task
- `apps/intercom/rust/intercomd/src/scheduler.rs:73–79` — timezone fallback to UTC, silent
- `apps/intercom/rust/intercom-core/src/persistence.rs:746–758` — `next_run IS NULL` → `status = 'completed'` (does not distinguish "cron parse error" from "one-shot done")
- `apps/intercom/rust/intercom-core/src/ipc.rs:36–48` — `IpcTask::ScheduleTask` carries no validation of `schedule_value` or timezone
- `research/hermes_agent/cron/jobs.py:99–113` — validation at creation time (reference pattern to adopt)

---

## Adaptation Opportunities

These Hermes patterns address the gaps above and are directly portable to intercom's Rust/Postgres stack.

### 1. Atomic claim before dispatch (addresses Areas 1 and 3)

Replace the plain `SELECT` in `get_due_tasks` with a `SELECT ... FOR UPDATE SKIP LOCKED`
that simultaneously sets `status = 'running'` and advances `next_run` to a
sentinel future time. This atomically claims the task and prevents re-dispatch:

```sql
-- Proposed replacement for get_due_tasks
WITH claimed AS (
  SELECT id FROM scheduled_tasks
  WHERE status = 'active' AND next_run IS NOT NULL AND next_run <= now()
  ORDER BY next_run
  LIMIT 50
  FOR UPDATE SKIP LOCKED
)
UPDATE scheduled_tasks
SET status = 'running', last_run = now()
WHERE id IN (SELECT id FROM claimed)
RETURNING *;
```

On completion, `update_task_after_run` sets `status = 'active'` with the new
`next_run`, or `status = 'completed'`/`'error'` as appropriate.
On crash/restart, add a recovery query at startup that resets any tasks stuck
in `status = 'running'` for longer than a configurable timeout.

**Reference:** Hermes file lock (`scheduler.py:285–291`) is the functional
equivalent — the lock prevents re-entry; the SQL approach extends this to
multi-process and survives process restart.

### 2. Transactional `log + update` (addresses Area 5)

Wrap `log_task_run` + `update_task_after_run` in a single BEGIN/COMMIT. The
`PgPool.with_client()` helper (`persistence.rs:160–167`) gives access to the
raw `Client`; expose a `with_transaction()` variant:

```rust
// Proposed addition to PgPool
pub async fn log_and_advance_task(
    &self,
    log: &TaskRunLog,
    task_id: &str,
    next_run: Option<&str>,
    last_result: &str,
) -> anyhow::Result<()> {
    self.with_client(|client| {
        // ...
        Box::pin(async move {
            let tx = client.transaction().await?;
            // INSERT task_run_logs
            // UPDATE scheduled_tasks
            tx.commit().await?;
            Ok(())
        })
    }).await
}
```

**Reference:** Hermes `save_jobs()` (`jobs.py:201–216`) uses `os.replace()` for
atomic file write — the principle is the same: both state changes succeed or
neither does.

### 3. Validate schedule at creation time (addresses Area 6)

Add a validation step when processing `IpcTask::ScheduleTask` and in the HTTP
`create_task` handler. Call `calculate_next_run(schedule_type, schedule_value, timezone)`
before inserting and return an error if it returns `None` for a non-`"once"`
type. This mirrors Hermes `parse_schedule()` raising `ValueError` at
`jobs.py:99–113` and surfaces misconfiguration to the user immediately.

**Reference:** `research/hermes_agent/cron/jobs.py:99–113` — validate cron via
`croniter()` at job creation; `jobs.py:104–108` — distinguish `ImportError` from
parse error.

### 4. Truncate Telegram delivery output (addresses Area 4)

Add a guard before `telegram.send_text_to_jid()` in `scheduler_wiring.rs:169`:

```rust
const MAX_TELEGRAM_TEXT: usize = 4000; // ~4096 UTF-8 chars, leave margin
let text = if text.len() > MAX_TELEGRAM_TEXT {
    format!("{}…\n[truncated — {} chars total]", &text[..MAX_TELEGRAM_TEXT], text.len())
} else {
    text.clone()
};
```

**Reference:** The review brief mentioned `MAX_PLATFORM_OUTPUT=4000` — this is
the value to adopt. Not currently implemented in Hermes either; both codebases
need this guard.

### 5. Surface cron parse failures as task errors, not silent completions (addresses Area 6 P1)

In `log_and_update()`, when `calculate_next_run` returns `None` for a `"cron"` or
`"interval"` task (as opposed to `"once"`, where `None` is expected and correct),
set `status = 'error'` with `last_result = "invalid schedule expression"` rather
than `status = 'completed'`. This makes misconfiguration visible in task listings
and in `task_run_logs`.

```rust
let new_status = match (task.schedule_type.as_str(), &next_run) {
    ("once", None) => "completed",
    (_, None) => "error",  // cron/interval parse failure
    (_, Some(_)) => "active",
};
```

**Reference:** Hermes raises `ValueError` at `jobs.py:107–108` — the parse
failure is visible. Intercom needs an equivalent post-hoc signal since validation
is currently deferred.

---

## Finding Index

| ID | Severity | Area | File | Line(s) |
|----|----------|------|------|---------|
| F1 | P1 | Dispatch/TOCTOU | `scheduler.rs` | 148–184 |
| F2 | P1 | Dispatch/TOCTOU | `persistence.rs` | 713–731 |
| F3 | P1 | Crash gap | `scheduler_wiring.rs` | 287–299 |
| F4 | P1 | No transaction | `scheduler_wiring.rs` | 287–299 |
| F5 | P1 | Double-dispatch | `persistence.rs` | 713–731 |
| F6 | P1 | Silent task loss | `scheduler.rs` | 65–70 |
| F7 | P2 | Clock skew | `scheduler.rs` | 80 |
| F8 | P2 | No filesystem audit | `scheduler_wiring.rs` | 288 |
| F9 | P2 | Silent tz fallback | `scheduler.rs` | 73–79 |
| F10 | P2 | Telegram size | `scheduler_wiring.rs` | 169–175 |
| F11 | P3 | No creation-time validation | `ipc.rs` (core) | 36–48 |
| F12 | P3 | IPC file size | `ipc.rs` (intercomd) | 601–605 |
