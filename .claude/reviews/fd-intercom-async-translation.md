# fd-intercom-async-translation: Async Model Translation Review

**Scope:** `research/hermes_agent/gateway/` + `research/hermes_agent/cron/` (Python asyncio reference) vs. `apps/intercom/rust/intercomd/src/` (Rust/tokio target)
**Reviewer role:** fd-intercom-async-translation (asyncio → tokio porting hazards)
**Date:** 2026-03-02

---

## Executive Summary

The translation from asyncio to tokio is largely sound at the structural level. The five areas below contain two genuine safety gaps (P1), one design pattern that constrains future work (P1), and several lower-priority concerns that are latent rather than immediately harmful. The most dangerous issue is the `rand_u16()` filename generator used in the IPC hot path; the second is the `PgPool` single-client reconnection scheme's behaviour under concurrent requests.

---

## 1. asyncio.run() from Sync Contexts vs. tokio::spawn

### Hermes pattern

Hermes uses `asyncio.run()` from sync contexts in two places:

**`cron/scheduler.py:117-125`** — `_deliver_result()` calls `asyncio.run(_send_to_platform(...))` from a plain `threading.Thread`. When a running event loop already exists in that thread (i.e., when called from within the gateway's own asyncio loop), this raises `RuntimeError`. The fallback at lines 119-125 spawns a fresh `ThreadPoolExecutor(max_workers=1)` and re-calls `asyncio.run()` inside it, which succeeds because that new thread has no running loop. This is an intentional, documented workaround for the "can't run inside a running loop" restriction.

**`gateway/run.py:2243`** — Top-level `asyncio.run(start_gateway(config))` at the `main()` entry point. This is correct: a single top-level `asyncio.run()` owns the loop lifetime.

**`gateway/run.py:2037`** — `loop.run_in_executor(None, run_sync)` offloads the synchronous `AIAgent.run_conversation()` call (which itself is blocking) to the default `ThreadPoolExecutor`. This is the correct pattern for CPU/IO-bound blocking work inside an async context.

### Intercom pattern

Intercom does not use `asyncio.run()` equivalents at all. The Rust daemon is `#[tokio::main]` throughout. Background loops are `tokio::spawn`. Blocking filesystem work (IPC polling, snapshot writes) is done either in sync helper functions called from async contexts, or via `std::fs` calls inside `tokio::spawn` tasks.

### Finding

**P3 — Informational.** The Hermes `ThreadPoolExecutor(max_workers=1)` workaround in `cron/scheduler.py:123` has no direct equivalent in intercom because intercom's cron-equivalent (the scheduler loop in `scheduler.rs`) runs natively in tokio. The pattern to watch for in Rust: never call a sync function that does blocking I/O from inside an `async fn` without wrapping it in `tokio::task::spawn_blocking`. Intercom's IPC watcher (`ipc.rs:217`) calls `self.poll_once()` — a fully synchronous `std::fs::read_dir` scan — from inside an `async fn`. This is tolerable because the poll loop yields between calls (`tokio::time::sleep`), but a large or slow filesystem scan could stall the tokio worker thread for meaningful wall-clock time.

**Specific location:** `apps/intercom/rust/intercomd/src/ipc.rs:203` — `self.poll_once()` is called from inside `async fn run()`. `poll_once()` itself is synchronous and performs blocking filesystem I/O.

**Recommendation:** Wrap `poll_once()` in `tokio::task::spawn_blocking` or convert it to use `tokio::fs`. For typical IPC directories with a handful of files this is likely safe today, but becomes a latency hazard at high message volume.

---

## 2. Fire-and-Forget Hook Emission — Error Isolation

### Hermes pattern

`gateway/hooks.py:118-150` — `HookRegistry.emit()` wraps every handler call in a `try/except Exception` and prints errors without re-raising. This provides complete isolation: a misbehaving hook cannot propagate an exception into the main message pipeline. Both sync and async handlers are supported; async handlers are `await`ed in-place within the `emit` coroutine. Crucially, `emit()` is always `await`ed at the call site (e.g., `gateway/run.py:441`), so hook errors are captured before the surrounding code proceeds.

### Intercom pattern

Intercom's equivalent fire-and-forget pattern is used in three places:

1. **`ipc.rs:124`** — `HttpDelegate::send_message()` calls `tokio::spawn(async move { ... })`. Errors are `warn!`-logged but the spawned task is detached (no `JoinHandle` retained). If the HTTP call fails, the message is silently lost. This matches Hermes's intent but with an important difference: in Python `await emit()` blocks until all handlers complete; in Rust the spawned task runs concurrently and independently.

2. **`ipc.rs:149`** — `HttpDelegate::forward_task()` uses the same pattern.

3. **`scheduler_wiring.rs:64`** — `build_task_callback()` spawns a small task to call `queue_for_enqueue.enqueue_task(...)`. This is fire-and-forget within the `TaskCallback` closure (which is sync). Any panic inside `enqueue_task` will be swallowed by the detached task.

### Finding

**P2 — Design gap: spawn isolation vs. sequential completion.** In Hermes, `await registry.emit(...)` means the calling code knows hook execution is finished (or errored) before continuing. In intercom, `tokio::spawn` tasks for IPC sends and task enqueues run fully concurrently. This is intentional and correct for performance, but it means:

- If the Node host callback server is down, IPC messages from containers are silently dropped (no backpressure, no queue).
- If `enqueue_task` panics inside the spawned task in `scheduler_wiring.rs:64`, the scheduler loop continues without knowing the task failed to enqueue.

The error handling at `ipc.rs:128-136` logs a `warn!` but does not expose failure back to the poll loop. This is acceptable for the IPC use case (same semantics as Node IPC), but the scheduler wiring path deserves a `JoinHandle` or at minimum a counter of enqueue failures.

**Specific locations:**
- `apps/intercom/rust/intercomd/src/ipc.rs:121-136` (send_message spawn)
- `apps/intercom/rust/intercomd/src/ipc.rs:148-162` (forward_task spawn)
- `apps/intercom/rust/intercomd/src/scheduler_wiring.rs:63-67` (enqueue_task spawn)

**Recommendation:** For the scheduler wiring path, retain the `JoinHandle` and log errors:

```rust
// scheduler_wiring.rs:63
let handle = tokio::spawn(async move {
    queue_for_enqueue.enqueue_task(&chat_jid, &task_id, task_fn).await;
});
// Optionally: tokio::spawn(async move { if let Err(e) = handle.await { error!(...) } });
```

For IPC sends, the current approach is acceptable but should be documented as intentional best-effort delivery.

---

## 3. Re-entrant asyncio Locks — Rust Mutex Held Across Await Points

### Hermes pattern

Python's `asyncio.Lock` is re-entrant within a single coroutine (a coroutine that `await`s while holding a lock will release it for other tasks — but `asyncio.Lock` is NOT reentrant in the Python sense, it simply cannot be acquired twice by the same coroutine without deadlocking). However, Hermes does not use `asyncio.Lock` for the gateway message processing pipeline at all. Message handler execution is serialized by the event loop's single-threaded nature: only one `_handle_message` coroutine runs at a time unless it yields. The `_running_agents` dict and `_pending_messages` dict (`gateway/run.py:182-183`) are accessed without locks because Python's GIL and asyncio's cooperative scheduling make this safe.

### Intercom pattern

The critical path in `queue.rs` uses `tokio::sync::Mutex` extensively:

```rust
// queue.rs:109 — lock acquired, work done, lock released before spawn
let should_spawn = {
    let mut inner = self.inner.lock().await;
    // ... mutate state
    true
}; // lock dropped here
if should_spawn {
    tokio::spawn(...)  // spawn outside the lock
}
```

This is the correct pattern. The lock is dropped before `tokio::spawn` is called. However, in `run_for_group` (line 402) the lock is re-acquired after `process_fn` completes:

```rust
// queue.rs:392-402
let success = if let Some(ref f) = process_fn {
    f(group_jid.clone()).await   // ← awaits without holding the lock
} else { false };

let mut inner = queue.lock().await;  // ← re-acquired after await completes
```

This is safe. The lock is NOT held across the `await` in `f(...)`. The `process_fn` completes fully before the lock is taken again. This is the canonical safe pattern for tokio Mutex.

### Finding

**P0 — No issue found.** Intercom correctly avoids holding `tokio::sync::Mutex` across `.await` points in all identified paths. The `run_for_group` and `run_task` functions follow the correct "acquire → mutate → release → await → acquire again" pattern.

There is one subtle concern worth flagging for future code:

**P3 — Latent risk: `scheduler_wiring.rs` RwLock read across awaits.** In `run_scheduled_task()` (`scheduler_wiring.rs:85-99`), a `groups.read().await` guard is held, then a value is extracted and the guard is dropped before further awaits. This is safe. However, multiple `sessions.write().await` calls at lines 161-163 and 243-246 hold the write lock while calling `pool.set_session()` (an async Postgres call). If `set_session` blocks for an extended period (e.g., Postgres is slow or reconnecting), the sessions write lock is held and all concurrent readers are blocked.

**Specific location:** `apps/intercom/rust/intercomd/src/scheduler_wiring.rs:160-166` and `243-246`.

**Recommendation:** Extract the Postgres call outside the write lock:

```rust
// Instead of:
{
    let mut s = sessions.write().await;
    s.insert(group_folder.clone(), sid.clone());
    if let Err(e) = pool.set_session(&group_folder, sid).await {  // ← Postgres inside lock
        warn!(...);
    }
}

// Prefer:
{
    let mut s = sessions.write().await;
    s.insert(group_folder.clone(), sid.clone());
}  // ← lock released
if let Err(e) = pool.set_session(&group_folder, sid).await {  // ← Postgres outside lock
    warn!(...);
}
```

This pattern appears in both `scheduler_wiring.rs` and `process_group.rs` (lines 242-247 and 303-308). Both should be updated.

---

## 4. Hermes Lazy Async Initialization vs. intercom's Arc<Option<PgPool>>

### Hermes pattern

Hermes does not use a connection pool. The gateway performs no database I/O directly. Session state is stored on the filesystem (`session.py:329-336`) or via SQLite (`hermes_state.SessionDB`). Database access is never lazy-initialized across concurrent requests.

### Intercom pattern

Intercom's `PgPool` (`persistence.rs:119-157`) holds a single `tokio_postgres::Client` behind `Arc<RwLock<Option<Client>>>`. The `get()` method attempts a fast-path read-lock, and falls back to `connect()` (a write-lock + network I/O) if the client is None.

**Critical observation:** When multiple concurrent requests arrive during initial startup or after a connection loss, the fast-path check (`guard.is_some() → return`) protects against redundant reconnects only if the first reconnect has already completed. Consider this scenario:

1. Request A arrives, fast-path check: `is_none()`, falls through to `connect()`.
2. `connect()` acquires a write lock. While it awaits `tokio_postgres::connect(...)`, the write lock is held.
3. Requests B and C arrive and try `client.read().await`. They block on the read lock because A holds the write lock.
4. A's `connect()` completes, write lock released. B and C acquire read lock, see `is_some()`, return successfully.

In this scenario, behaviour is correct: B and C block until A completes reconnection. The `RwLock` provides correct mutual exclusion.

**However there is a second scenario:**

1. The `Option<Client>` contains a client that is closed/disconnected (e.g., Postgres was restarted).
2. Request A's fast-path: `guard.is_some() → return Ok(guard)` — returns the stale guard.
3. `with_client()` executes the closure against the stale client, which fails.
4. The error propagates to the caller as an `anyhow::Error`, but the `client` field still contains the dead `Client`. No automatic eviction occurs.
5. All subsequent requests also fast-path to the stale client and fail.

### Finding

**P1 — Silent stale connection: no dead-client eviction.** `PgPool::get()` does NOT invalidate the cached client on error. If the Postgres connection dies mid-session (network blip, Postgres restart), the pool fast-paths to the stale client indefinitely. Only a call to `pool.connect()` (which writes `None` implicitly via `*self.client.write().await = Some(client)`) will replace it. But `connect()` is only called explicitly by `get()` when `is_none()`.

**Specific location:** `apps/intercom/rust/intercom-core/src/persistence.rs:140-157`.

```rust
async fn get(&self) -> anyhow::Result<...> {
    {
        let guard = self.client.read().await;
        if guard.is_some() {   // ← stale client passes this check
            return Ok(guard);
        }
    }
    self.connect().await?;     // ← only reached when client is None
    ...
}
```

Additionally, `tokio_postgres` connections are managed with a separate connection task (see `persistence.rs:174`):

```rust
tokio::spawn(async move {
    if let Err(err) = connection.await {
        error!(err = %err, "postgres connection error");
    }
});
```

When this connection task exits (on connection loss), the `Client` becomes unusable but the `Option<Client>` inside `PgPool` still reads `Some(...)`. The `get()` fast-path returns the dead client to callers.

**Recommendation:** Add error-triggered eviction in `with_client()`:

```rust
async fn with_client<F, T>(&self, f: F) -> anyhow::Result<T>
where F: ...
{
    let guard = self.get().await?;
    let client = guard.as_ref().unwrap();
    match f(client).await {
        Ok(v) => Ok(v),
        Err(e) => {
            // If it's a connection error, evict the stale client so next call reconnects
            if is_connection_error(&e) {
                drop(guard);
                *self.client.write().await = None;
            }
            Err(e)
        }
    }
}
```

Alternatively, switch to `deadpool-postgres` or `bb8` with `tokio-postgres` which handle eviction automatically.

**Secondary finding (P2):** The `Arc<Option<PgPool>>` pattern used in `AppState` and all axum handlers (`db.rs:31-40`) means that when Postgres is not configured, every DB endpoint returns `503 SERVICE_UNAVAILABLE`. This is correct and intentional. No issue. But the `require_pool` helper deserves a note: during the orchestrator startup window before `pool.connect()` completes, handlers that bypass the `db` sub-router and use `state.db` directly could race. Audit: `main.rs:348` gates the orchestrator on `state.db.is_some()`, which is set before the scheduler loop starts. Safe.

---

## 5. Hermes ThreadPoolExecutor(max_workers=1) Timeout Pattern vs. tokio::time::timeout

### Hermes pattern

`cron/scheduler.py:122-125`:

```python
with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
    future = pool.submit(asyncio.run, _send_to_platform(...))
    result = future.result(timeout=30)   # ← 30-second hard timeout
```

This constrains delivery calls to at most 30 seconds. If the platform API hangs, the exception propagates and the job reports a delivery failure. `max_workers=1` also means at most one concurrent delivery; subsequent deliveries block on the future.

### Intercom pattern

Intercom does not have an equivalent explicit timeout on DB writes or Telegram sends. Looking at the specific paths:

1. **Telegram sends** (`telegram.rs` — not read directly but called from `process_group.rs:255`): The `TelegramBridge::send_text_to_jid()` is called bare with no timeout wrapper.

2. **Postgres writes** in `process_group.rs:273-275`:
```rust
if let Err(e) = pool.store_message(&bot_msg).await {
    warn!(err = %e, "failed to store bot response");
}
```
No timeout. If Postgres is slow, this await blocks indefinitely while holding the `run_for_group` task alive.

3. **Scheduler wiring `log_and_update`** (`scheduler_wiring.rs:278-308`): Two Postgres calls (`log_task_run`, `update_task_after_run`) with no timeout. If these block, the group's slot in `GroupQueue` is not released (because `run_task` awaits `run_scheduled_task` which awaits `log_and_update`).

### Finding

**P1 — Missing timeouts on Postgres writes in the hot path.** In Hermes, delivery is bounded to 30 seconds via `future.result(timeout=30)`. In intercom, Postgres writes inside `run_for_group` and `run_task` are unbounded. If `log_and_update` blocks indefinitely (Postgres overloaded, network partition), the group's `active = true` state in `GroupQueue::Inner` is never cleared (`reset_group` is never called because `run_task` never returns). This permanently starves that group's slot in the queue.

**Specific locations:**
- `apps/intercom/rust/intercomd/src/scheduler_wiring.rs:287-308` (`log_and_update`)
- `apps/intercom/rust/intercomd/src/process_group.rs:273-275` (bot message store)
- `apps/intercom/rust/intercomd/src/process_group.rs:303-308` (session persist)

**Recommendation:** Wrap the tail of `run_scheduled_task` and `run_for_group` cleanup paths in `tokio::time::timeout`:

```rust
// scheduler_wiring.rs — wrap log_and_update
tokio::time::timeout(
    std::time::Duration::from_secs(30),
    log_and_update(pool, &task, start, ...),
).await
.unwrap_or_else(|_| {
    error!(task_id = task.id.as_str(), "log_and_update timed out after 30s");
});
```

Similarly, `queue::run_task` should reset the group even if the task panics. Currently `reset_group` is called at `queue.rs:464` after `(task.task_fn)().await`, but if the task future panics (rather than returning), the `JoinHandle` propagates the panic and `reset_group` is never called. Consider `AssertUnwindSafe` + `catch_unwind` or noting this as a known limitation.

---

## 6. rand_u16() IPC Filename Generation — Collision Probability

### Hermes pattern

`cron/scheduler.py:118` uses `asyncio.run()` for delivery, not IPC filenames. IPC between Hermes's CLI and any background processes uses `uuid.uuid4()` via Python's `uuid` module, which produces a 128-bit cryptographically random UUID. Collision probability across billions of files is negligible.

### Intercom pattern

`queue.rs:480`:

```rust
let filename = format!("{ts}-{:04x}.json", rand_u16());
```

`rand_u16()` at lines 507-512:

```rust
fn rand_u16() -> u16 {
    let t = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default();
    (t.subsec_nanos() ^ (t.as_secs() as u32).wrapping_mul(2654435761)) as u16
}
```

This produces a 16-bit value (65,536 possible values) derived from `subsec_nanos` XOR'd with a Knuth multiplicative hash of the seconds component.

The full filename is `{millis_timestamp}-{rand_u16:04x}.json`. So uniqueness depends on: (a) two files being generated in the same millisecond, AND (b) `rand_u16()` returning the same value for both.

**Collision analysis:**

Under normal operation (one message per group per second), collisions are practically impossible.

Under high concurrency — specifically when `write_ipc_message` is called rapidly from multiple `tokio::spawn` tasks for the same group — the timestamp component (`SystemTime::now()` in milliseconds) will be identical across tasks spawned in the same scheduler tick. With 64K possible suffixes, the birthday bound for a 50% collision probability at N concurrent writes is approximately N ≈ sqrt(65536) ≈ 256 simultaneous writes to the same `input/` directory within the same millisecond.

More critically: `SystemTime::now()` on Linux has only millisecond resolution in the filename prefix, while `subsec_nanos` in the suffix also comes from `SystemTime::now()` — called in rapid succession, multiple calls within the same millisecond will have nearly identical `subsec_nanos` values. The XOR with the seconds hash doesn't help when the seconds are the same. Two concurrent calls within microseconds of each other will likely produce identical `rand_u16()` values.

**Worst case:** Under the maximum concurrency allowed by `GroupQueue` (default `max_concurrent` from config), all groups that become ready simultaneously will call `write_ipc_message` concurrently. A collision causes the second writer's `std::fs::write` to overwrite the first writer's `.tmp` file, and the subsequent `rename` of the first write's `.tmp` silently fails (since `.tmp` is now gone or overwritten), losing a message.

### Finding

**P1 — IPC filename collision under concurrent writes: silent message loss.** The 16-bit entropy suffix is insufficient for a concurrent filesystem-IPC system. When multiple tokio tasks call `write_ipc_message` in the same millisecond, two files can map to the same filename. The atomic write sequence (`write .tmp → rename to .json`) is not atomic across tasks: two tasks generating the same `{ts}-{rand}.json.tmp` path will race on the `.tmp` write, with the loser's data being overwritten.

**Specific location:** `apps/intercom/rust/intercomd/src/queue.rs:480-497`.

**Comparison:** Hermes uses 128-bit UUID4, giving effectively zero collision probability. Intercom uses 16-bit derived entropy — a 10,000x reduction in collision resistance.

**Recommendation:** Replace `rand_u16()` with a UUID or a thread-safe atomic counter:

```rust
// Option 1: Use uuid crate (already likely in dep tree)
use uuid::Uuid;
let filename = format!("{ts}-{}.json", Uuid::new_v4().simple());

// Option 2: Process-global atomic counter
static IPC_COUNTER: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
fn ipc_seq() -> u64 {
    IPC_COUNTER.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
}
let filename = format!("{ts}-{:016x}.json", ipc_seq());
```

Option 2 (atomic counter) is zero-cost and monotonically unique within a process lifetime, which is all that is required since each intercomd process owns its IPC directories.

---

## Adaptation Opportunities

### 1. Adopt tokio::time::timeout universally on DB paths

Hermes's `ThreadPoolExecutor(max_workers=1, timeout=30)` is a blunt instrument to prevent delivery hangs. Intercom can achieve the same result more surgically with `tokio::time::timeout`. The recommended locations are the Postgres write calls in `log_and_update`, `process_group.rs` bot message store, and `process_group.rs` session persist. A 30-second default (matching Hermes) is reasonable.

### 2. PgPool should evict on connection error

Hermes avoids this problem by using the filesystem. Intercom's `PgPool` should grow a `mark_disconnected()` method or perform eviction in `with_client()` on connection-category errors. The `deadpool-postgres` crate provides this out of the box at the cost of a dependency. Given that intercomd targets long-running daemon operation, this is worth the investment.

### 3. IPC atomic counter vs. uuid4

The `rand_u16()` approach in `write_ipc_message` should be replaced with an atomic u64 counter or uuid. This is a one-line change that eliminates an entire class of potential message loss under load.

### 4. IPC poll_once in spawn_blocking

Hermes's cron ticker (`_start_cron_ticker`) is already in a dedicated `threading.Thread`, so it never blocks asyncio. Intercom's `IpcWatcher::poll_once()` runs blocking filesystem I/O from within an async context. Wrapping in `spawn_blocking` would isolate this and allow the tokio worker pool to handle it without stalling.

### 5. sessions.write() + pool.set_session() lock reduction

Both `scheduler_wiring.rs` and `process_group.rs` hold `sessions.write()` while calling `pool.set_session()`. This is an async Postgres call inside a write lock. Releasing the write lock before the Postgres call (extracting the sid value first, then updating memory, then releasing, then calling Postgres) would reduce contention at no semantic cost.

### 6. Scheduler enqueue failure observability

The fire-and-forget `tokio::spawn` in `scheduler_wiring.rs:64` that calls `queue.enqueue_task()` has no failure reporting path. If the scheduler fires 10 tasks in one poll but all 10 fail to enqueue (e.g., GroupQueue is shutting down), the scheduler loop continues unaware. At minimum, the spawned task should log at `error!` level on unexpected failure. Hermes's cron scheduler logs every job failure explicitly.

---

## Summary Table

| # | Finding | Severity | File | Line(s) |
|---|---------|----------|------|---------|
| 1 | IPC poll_once does blocking fs I/O in async context | P3 | `ipc.rs` | 203 |
| 2 | IPC/task spawn errors are fire-and-forget (no backpressure) | P2 | `ipc.rs`, `scheduler_wiring.rs` | 124, 149, 64 |
| 3 | Mutex not held across await — SAFE | P0 | `queue.rs` | 392-402 |
| 4 | sessions.write() held across Postgres await (lock contention) | P3 | `scheduler_wiring.rs`, `process_group.rs` | 160-166, 303-308 |
| 5 | PgPool stale client not evicted on connection loss | P1 | `persistence.rs` | 140-157 |
| 6 | No timeout on Postgres writes in task/group hot path | P1 | `scheduler_wiring.rs`, `process_group.rs` | 287-308, 273-275 |
| 7 | rand_u16() has 16-bit entropy — collision risk at concurrency | P1 | `queue.rs` | 507-512, 480 |
