# Intercom vs. Hermes: Architectural Analysis & Migration Options

**Date:** 2026-03-02
**Scope:** Comparing IronClaw (Rust daemon) vs. Hermes Agent; evaluating consolidation/hybrid approaches.
**Status:** Detailed analysis with concrete recommendations.

---

## Executive Summary

**Current State (Intercom/IronClaw):**
- **Dual-process:** Node host (messaging channels) + Rust daemon (orchestration, scheduling, container dispatch)
- **Communication:** Fire-and-forget HTTP callbacks (unreliable, unordered, no backpressure)
- **Strengths:** Rustified scheduler, native Postgres, containerized isolation, per-group serialization
- **Weaknesses:** Process boundary complexity, TOCTOU scheduler bugs, no flow control, credential exposure

**Hermes Reference:**
- **Single-process:** Python daemon + async gateway with embedded scheduler
- **Strengths:** Simpler mental model, file-lock TOCTOU protection, always-log-local pattern, defensive redaction
- **Weaknesses:** File-based storage limits, no distributed scheduling, no multi-runtime containers, modal backend isolation

**Verdict:**
Intercom's architecture is fundamentally **sound** but **incompletely implemented**. Rather than adopting Hermes wholesale, Demarch should:
1. **Fix critical scheduler/IPC bugs immediately** (8.5 days, from SYNTHESIS)
2. **Replace fire-and-forget HTTP with reliable IPC** (Postgres LISTEN/NOTIFY or Unix sockets)
3. **Keep the dual-process model** — each process handles what it does well
4. **Port Hermes's defensive patterns** (redaction, pairing, secure I/O) as shared libraries

**Migration effort:** 2–4 weeks to production-hardened system. **No full Node→Rust rewrite needed.**

---

## Section 1: What Hermes Does Right

### 1.1 File-Lock Dispatch Exclusion (TOCTOU Protection)

**Hermes code** (`scheduler.py:285–291`):
```python
def tick(verbose=True):
    try:
        lock_fd = open(_LOCK_FILE, "w")
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)  # Exclusive, non-blocking
    except (OSError, IOError):
        logger.debug("Tick skipped — another instance holds the lock")
        return 0  # Skip entirely if lock held
```

**Why it works:**
- At most one tick can run at any time (file system provides mutual exclusion)
- No double-dispatch under concurrent daemons
- Crash during task dispatch won't block future ticks (file handle closes on exit)

**Intercom's gap** (`persistence.rs` & `scheduler.rs`):
- `get_due_tasks()` returns tasks with `next_run <= now` and `status='active'`
- If two daemons both read before either updates, both will dispatch the same task
- `SELECT ... FOR UPDATE` (P1-001 from SYNTHESIS) solves this atomically

**Verdict:** Hermes's approach is clever but filesystem-scale. Intercom's atomic SQL approach is better **once implemented**.

### 1.2 Always-Log-Local Pattern (Crash-Safe Audit)

**Hermes code** (`delivery.py` & `scheduler.py`):
```python
# save_job_output() writes to disk FIRST, then delivery
output_file = save_job_output(job["id"], output)  # Always persists
_deliver_result(job, content)  # May fail, but log is safe
mark_job_run(job_id, success, error)  # Single atomic call
```

**Why it works:**
- Job output is permanently recorded before sending to remote platform
- If Telegram delivery fails, the data isn't lost
- Audit trail is durable against infrastructure failures

**Intercom's gap** (from fd-intercom-scheduler-reliability report):
- Task output is sent to Telegram but not logged before next_run write
- Crash between container exit and Postgres update leaves task undated
- Next restart will re-dispatch the same task (no dedup check)

**Fix** (AO-SA-2): Wrap `INSERT task_run_logs` + `UPDATE scheduled_tasks` in single transaction.

**Verdict:** Hermes's pattern is simple; Intercom needs atomic transactions, not storage-based fallback.

### 1.3 Delivery Target DSL (Flexible Output Routing)

**Hermes** (`delivery.py:57–90`):
```python
deliver = job.get("deliver", "local")  # "local" | "origin" | "telegram:123" | "slack:456"
if deliver == "origin":
    platform_name, chat_id = origin  # Route to originating chat
elif ":" in deliver:
    platform_name, chat_id = deliver.split(":", 1)  # Route to specific chat
else:
    chat_id = os.getenv(f"{platform_name.upper()}_HOME_CHANNEL")  # Default channel
```

**Why it's clean:**
- Separates **what to deliver** from **how to route it**
- Extensible to new platforms without code changes
- Supports "send to origin" (where user triggered it) vs. "send to home channel"

**Intercom equivalent:**
- Currently hard-coded to origin chat (`task.chat_jid`)
- Could evolve to `DeliveryTarget` enum with same DSL

**Verdict:** Portable pattern; low priority for intercom (current behavior sufficient for MVP).

### 1.4 Redaction Library (Credential Protection)

**Hermes** (`agent/redact.py`):
- 5-layer regex patterns: AWS keys, JWT tokens, private keys, DB URLs, API keys
- Applied to logging via `RedactingFormatter` + direct file I/O via `_secure_write()`
- Catches credentials before disk write

**Intercom's gap** (P0-001 from SYNTHESIS):
- Session JSON written to Postgres + SQLite without redaction
- Tool outputs containing tokens persist unmasked
- Audit logs expose credentials

**Fix** (AO-SEC-1): Port `redact.py` to Go, apply to all session persistence paths.

**Verdict:** **Critical gap.** Hermes shows the pattern; Intercom needs shared library implementation.

---

## Section 2: What IronClaw Adds (Not in Hermes)

### 2.1 Native Postgres Persistence

**IronClaw:**
```rust
pub async fn get_due_tasks(&self) -> anyhow::Result<Vec<DueTask>> {
    let rows = self.conn.query(
        "SELECT id, group_folder, chat_jid, prompt, schedule_type, schedule_value
         FROM scheduled_tasks
         WHERE next_run <= now() AND status = 'active'
         LIMIT ?",
        &[&batch_size],
    ).await?;
}
```

**Hermes:**
- File-based job store (~/.hermes/cron/jobs.json)
- No distributed query capability
- No audit trail schema
- No direct integration with Intercore

**Why Rust's approach is better:**
- Unified storage with Intercore runs + session data
- Atomic queries with transactions
- Scalable to 1000s of tasks
- Native timezone support via chrono-tz

**Verdict:** **Intercom wins.** Postgres is the right choice.

### 2.2 Multi-Runtime Container Support

**IronClaw:**
```rust
pub enum RuntimeKind {
    Claude,       // Agent SDK
    Gemini,       // Code Assist API
    Codex,        // codex exec CLI
}

// At dispatch time:
let image = match runtime {
    RuntimeKind::Claude => "intercom-agent:claude",
    RuntimeKind::Gemini => "intercom-agent:gemini",
    RuntimeKind::Codex => "intercom-agent:codex",
};
```

**Hermes:**
- Single agent backend (Hermes Agent codebase)
- No runtime selection per group
- All jobs run with same model/provider

**Why Rust's approach is better:**
- Groups can independently choose runtime
- Easy to A/B test inference providers
- Isolates bugs to single runtime container

**Verdict:** **Intercom wins.** Multi-runtime is a feature Hermes can't easily support.

### 2.3 Per-Group Serialization (Fair Queuing)

**IronClaw:**
```rust
// GroupQueue ensures:
// 1. Max 1 container per group at a time
// 2. Messages drain before tasks (priority)
// 3. Global concurrency cap (e.g., 4 concurrent groups)
// 4. Fair scheduling across groups via waiting queue
```

**Hermes:**
- Single job execution thread (ThreadPoolExecutor with 1 thread for tick)
- No per-chat fairness — first job to run blocks all others

**Why Rust's approach is better:**
- Long-running jobs don't starve other groups
- Fair CPU time allocation across users
- Graceful degradation under load

**Verdict:** **Intercom wins.** Hermes's single-threaded model is a bottleneck.

### 2.4 Concurrent Message Groups (Container-as-Runbook)

**IronClaw:**
```rust
// message_loop polls for new messages per group
// Groups with pending messages are enqueued
// Each group's container stays alive to receive follow-up messages via IPC
// Responses can mention multiple agents in one session
```

**Hermes:**
- Each job runs independently, exits, then marks complete
- No interactive sessions — job input is "prompt", output is "result"
- No message follow-up handling within a session

**Why Rust's approach is better:**
- Interactive multi-turn conversations (user ↔ agent ↔ user)
- Agent can ask clarifying questions and wait for response
- Session state persists across agent runs

**Verdict:** **Intercom wins.** This is a fundamental difference in use case.

### 2.5 IPC Polling (Decoupled Telegram Updates)

**IronClaw:**
```rust
// ipc::IpcWatcher runs in background, polls data/ipc/ for container messages
// Detects when container writes query/request file
// Calls back to Node host via HTTP (sendMessage, forwardTask)
```

**Hermes:**
- Gateway runs in same process as cron scheduler
- Telegram polling is synchronous with job execution
- Job output blocks on network send to Telegram

**Why Rust's approach is better:**
- Container I/O doesn't block scheduler
- Decoupled timing — schedule ticks independently of Telegram latency
- Can parallelize IPC reads and task scheduling

**Verdict:** **Intercom wins.** Async decoupling is more robust.

---

## Section 3: Where the Dual-Process Model Breaks

### 3.1 Fire-and-Forget HTTP Callbacks (Unreliable)

**Current flow** (`src/db.ts:22–34`):
```typescript
function dualWriteToPostgres(endpoint: string, payload: unknown): void {
  fetch(`${INTERCOMD_URL}/v1/db${endpoint}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(3000),  // Hard timeout, no retry
  }).catch((err) => {
    logger.debug({ endpoint, err: err?.message }, 'Postgres dual-write failed (non-fatal)');
  });
}

// Called from:
storeMessage(jid, msg);  // Write to SQLite, then async fire-and-forget to Postgres
createTask(...);         // Write to SQLite, then async fire-and-forget to Postgres
```

**Failure modes:**
1. **Network hiccup:** Postgres write is lost; Node has task, daemon doesn't
2. **Daemon restart:** SQLite state diverges from Postgres for hours
3. **Scheduler poll:** Daemon queries Postgres, gets only tasks it created (stale view)
4. **Race condition:** Node writes task to SQLite, Postgres write fails, daemon never sees task

**Why it's broken:**
- No acknowledgment protocol
- No exponential retry
- No queue if Postgres is temporarily down
- No deduplication (same task enqueued twice if network fails and Node retries)

### 3.2 Host Callback Ordering (Out-of-Order Execution)

**Current flow** (`host-callback.ts` & `scheduler_wiring.rs`):
```
[Scheduler] polls Postgres → [DueTask]
  → calls task_callback()
    → enqueues task_fn into GroupQueue
      → HTTP callback to Node: sendMessage(...)
        → Node processes async, may complete out of order

[Message loop] polls Postgres → [NewMessages]
  → enqueues processGroupMessages()
    → HTTP callback to Node: forwardTask(...)
      → Node processes async, may complete out of order
```

**Problem:** If a scheduled task's output should precede a message-driven response, but the HTTP callbacks arrive out of order, the user sees backward responses.

**Example:**
```
1. Scheduler task fires at 10:00:00, enqueues "Send weather forecast"
2. User sends message at 10:00:01, task queues "Answer weather question"
3. Message callback arrives at 10:00:01.5 (faster network)
4. User sees "Answering your question" BEFORE "Today's forecast"
```

### 3.3 Session State Divergence (Node vs. Daemon)

**Node host state:**
```typescript
let sessions: Record<string, string> = {};  // In-memory cache
getAllSessions(); // Loaded from SQLite on startup, never refreshed
```

**Daemon state:**
```rust
// Loaded from Postgres at startup, kept in sync via setter callbacks
let sessions: Arc<RwLock<HashMap<String, String>>> = ...;
```

**Problem:**
- Node never reloads sessions from disk
- If daemon updates session in Postgres, Node doesn't see it
- User clears session via `/reset` command; daemon still has old state if not connected

### 3.4 No Backpressure (Overload Conditions)

**Current behavior:**
```
[Node] fires HTTP POST to [Daemon]
[Daemon] receives request, starts processing immediately
[Node] doesn't wait for response, returns success to user
→ If daemon is overloaded, requests queue indefinitely in daemon
→ If daemon crashes, unsent tasks are lost from Node's memory
```

**Correct behavior:**
```
[Node] sends request to [Daemon]
[Daemon] returns 202 Accepted (queued) or 503 Service Unavailable (overloaded)
[Node] retries with exponential backoff if 503
[Node] logs 202 and waits for async notification when done
```

---

## Section 4: Migration Options (Detailed Analysis)

### Option A: Keep Dual-Process, Fix IPC (Recommended)

**Approach:**
1. Keep Node host as-is (messaging channels, command dispatch)
2. Keep Rust daemon as-is (orchestration, scheduling, containers)
3. Replace fire-and-forget HTTP with reliable IPC

**Mechanism: Postgres LISTEN/NOTIFY**

Node → Daemon direction (task creation, session updates):
```sql
-- Node writes to Postgres, then sends NOTIFY signal
INSERT INTO scheduled_tasks (...) RETURNING id;
SELECT pg_notify('intercomd_tasks', json_build_object('action', 'task_created', 'task_id', id)::text);

-- Daemon is subscribed to 'intercomd_tasks' channel
-- Wakes up on NOTIFY, polls for newly created tasks
```

Daemon → Node direction (sendMessage, session updates):
```rust
// Daemon writes to outbox table, then sends NOTIFY
INSERT INTO daemon_outbox (action, payload, retry_count) VALUES ('send_message', ..., 0);
SELECT pg_notify('intercom_host', json_build_object('action', 'send_message', ...)::text);

// Node is subscribed to 'intercom_host' channel
// Wakes up, drains outbox with exponential retry
```

**Benefits:**
- **Ordered delivery:** Postgres ensures FIFO ordering
- **At-least-once:** Outbox pattern provides durability
- **Backpressure:** Node can slow down Daemon by not draining outbox fast enough
- **Crash recovery:** On restart, both processes replay unsent messages from tables
- **No app-level retry logic:** Postgres handles ordering and durability

**Drawbacks:**
- Adds connection pooling complexity (need async Postgres client)
- Requires migration: convert dual-write pattern → outbox + notify
- Testing is more complex (need Postgres for tests)

**Effort:** 5 days
- Day 1: Schema (outbox table, notify triggers)
- Day 2: Daemon LISTEN loop (tokio_postgres async subscription)
- Day 1–2: Node listener (async Postgres subscription + outbox drain)
- Day 1: Replace all dualWriteToPostgres() calls → INSERT into outbox
- Day 0.5: Tests + retry logic

**Acceptance criteria:**
- All task/message data flows through outbox
- NOTIFY wakes subscribers immediately
- Both processes survive restart without data loss
- No HTTP dependencies for core IPC

---

### Option B: Absorb Node's Telegram Into Rust Daemon

**Approach:**
1. Port Grammy bot SDK to Rust (via gramme crate or equivalent)
2. Move Telegram ingress/routing into intercomd
3. Keep Node for non-Telegram channels (WhatsApp, Discord)
4. Still use HTTP callbacks for Node's async channel operations

**Mechanism:**
```rust
// intercomd main.rs adds:
let telegram_handler = TelegramHandler::new(&config);

// Instead of IPC-polling and calling Node:
telegram_handler.handle_message(msg).await  // Process inline
  → routes to existing processGroupMessages()
  → updates Postgres, enqueues container
```

**Benefits:**
- **Fewer processes:** Single-daemon scheduling + Telegram = no HTTP for Telegram path
- **Lower latency:** No network hop for Telegram updates
- **Simpler callback:** Only WhatsApp/Discord need async HTTP callbacks

**Drawbacks:**
- **Large rewrite:** Grammy SDK features ≠ gramme crate (likely need custom port)
- **Rust stdlib doesn't have good Telegram client:** gramme is unmaintained; would need to maintain fork
- **Locks Telegram into Rust release cycle:** Can't deploy Telegram changes without recompiling daemon
- **Duplicates message processing:** Both Node and Daemon would need same command parser

**Effort:** 3–4 weeks
- Week 1: Port Grammy API and webhook handler to Rust
- Week 1: Integrate into intercomd message loop
- Week 0.5: Migrate existing Telegram tests
- Week 0.5: Migration period (run both in parallel, compare output)

**Verdict:** **Not recommended.** Node already handles this well; effort is high for marginal gain.

---

### Option C: Absorb Node's Routing Into Rust Daemon, Keep HTTP Channels

**Approach:**
1. Keep Node as thin HTTP→Postgres bridge for external channels (WhatsApp webhook, Discord bot)
2. Move command dispatch logic into daemon
3. Daemon becomes the canonical command processor

**Mechanism:**
```rust
// Node:
POST /v1/webhook/whatsapp → store message in Postgres → return 200
POST /v1/webhook/discord → store message in Postgres → return 200

// Daemon:
message_loop polls Postgres for new messages
  → executes parseCommand() locally (not in Node)
  → handles /status, /reset, etc. inline
  → enqueues container for regular messages
```

**Benefits:**
- **Simpler Node:** Just HTTP→Postgres, no business logic
- **Easier testing:** Command logic testable in Rust (faster tests)
- **Centralized auth:** Commands validated in daemon, consistent across all channels

**Drawbacks:**
- **Node still needed:** Still need to maintain Node runtime
- **Split responsibility:** External channel setup is still Node's problem
- **Not much gain:** Most Demarch complexity is already in Rust

**Effort:** 3–4 days
- Day 1: Move `commands.rs` logic (already there)
- Day 1: Integrate command execution into message loop
- Day 1: Node becomes thin HTTP→Postgres bridge
- Day 1: Tests + regression validation

**Verdict:** **Acceptable.** Lower effort than Option B, cleaner architecture than status quo. Could follow Option A.

---

### Option D: Full Rewrite — Node Host Absorbs Container Dispatch

**Approach:**
1. Keep Node as primary process
2. Port container dispatch to Node (Docker.js or similar)
3. Remove Rust daemon entirely
4. Postgres queries via node-postgres

**Mechanism:**
```typescript
// index.ts
const groupQueue = new GroupQueue();
const processMessagesFn = async (chat_jid) => {
  const group = groups[chat_jid];
  const messages = await db.getNewMessages(group.folder);
  const { output } = await runContainerAgent(group, messages, run_config);
  await telegram.send(output);
};
```

**Benefits:**
- **Single process:** Fewer moving parts, simpler deployment
- **Simpler IPC:** All state in shared memory (Node + child processes)
- **No dual-write:** All data is natively in Postgres + Node memory

**Drawbacks:**
- **TypeScript isn't ideal for systems code:** No type-safe async/await like Rust's tokio
- **CPU-bound container spawning:** Node's event loop can block on Docker API calls
- **Process management:** Would need to reimplement all Rust queue/scheduler logic in TS
- **Loses type safety:** Rust's type system caught many bugs during Intercom development
- **Performance:** Node 22's V8 is OK but not comparable to Rust for high-concurrency workloads
- **Operational burden:** Would need to retest all scheduler logic, state recovery, timeout handling

**Effort:** 4–6 weeks
- Week 1: Port scheduler.rs logic to TypeScript
- Week 1: Port queue.rs and GroupQueue logic
- Week 1: Port container/runner.rs to use Docker.js
- Week 0.5: Port all Postgres query logic
- Week 1: Integration testing + state recovery testing
- Week 0.5: Deployment validation + performance testing

**Verdict:** **Not recommended.** Rust's concurrency model is a fundamental advantage; losing it is a net negative. Node's strength is async I/O (messaging), not CPU-bound orchestration.

---

### Option E: Hybrid — Postgres LISTEN/NOTIFY + Scheduled Reorg

**Approach:**
1. Implement Option A (LISTEN/NOTIFY for reliable IPC)
2. Add periodic Postgres polling as fallback (every 5 minutes)
3. Both processes query for stale outbox entries and retry

**Mechanism:**
```rust
// Daemon subscribes to NOTIFY, but also polls outbox every 5min
let outbox = pool.query_outbox_since(last_drain_time).await?;
for msg in outbox {
    if msg.retry_count < 3 {
        retry_send(&msg).await?;
        pool.increment_retry(&msg.id).await?;
    }
}
```

**Benefits:**
- **Belt-and-suspenders:** NOTIFY handles normal case, polling catches failures
- **Recovery from Postgres connection loss:** If NOTIFY subscription drops, polling reconnects
- **No backlog explosion:** Polling ensures backlog doesn't grow unbounded

**Drawbacks:**
- **Complexity:** Need to manage both subscription state and polling clock
- **Storage cost:** Outbox table grows if polling stops working

**Effort:** +2 days (on top of Option A)

**Verdict:** **Good addition to Option A,** but not strictly necessary if outbox design is sound.

---

## Section 5: Concrete Recommendation

### Phased Rollout (2-3 weeks to production)

**Week 1: Fix Critical Bugs (from SYNTHESIS)**
- Atomic task claim via `SELECT ... FOR UPDATE SKIP LOCKED` (P1-001, 1 day)
- Transactional log + update (P1-002, 1 day)
- PgPool eviction on error (P1-004, 2 days)
- IPC filename collision fix (P1-005, 0.5 days)
- Start redaction library (P0-001, 1.5 days)

**Week 2: Implement Reliable IPC (Option A)**
- Postgres schema: outbox tables + notify triggers (1 day)
- Daemon LISTEN/NOTIFY loop (1.5 days)
- Node outbox consumer (1.5 days)
- Replace all dual-write calls (1 day)

**Week 3: Integration & Validation**
- End-to-end tests (1 day)
- Chaos testing: kill daemon, restart, check recovery (1 day)
- Performance testing: verify NOTIFY doesn't introduce latency (0.5 days)
- Deploy to staging (0.5 days)

**Total:** 15 days (realistic: 16–18 with debugging)

### Technology Stack

| Component | Before | After | Notes |
|-----------|--------|-------|-------|
| Task persistence | SQLite + Postgres dual-write | Postgres only | Daemon is source of truth |
| Message persistence | SQLite + Postgres dual-write | Postgres + outbox table | Deduplication via outbox |
| Task dispatch | HTTP POST (fire-and-forget) | LISTEN/NOTIFY | Ordered, durable, backpressure-aware |
| Node-to-Daemon | HTTP callbacks | HTTP (external channels only) | Telegram/WhatsApp still use callbacks |
| Daemon-to-Node | IPC polling + HTTP delegate | Outbox + LISTEN/NOTIFY | All state flows through Postgres |
| Scheduling | Rust scheduler loop (good) | No change | Keep as-is |
| Container dispatch | Rust (good) | No change | Keep as-is |

### What Doesn't Change

- Node host still handles external channels (Telegram webhook via IPC, WhatsApp webhook)
- Rust daemon still manages containers + scheduling
- per-group serialization still enforced via GroupQueue
- IPC watcher still polls data/ipc/ for container messages
- All existing Postgres schema remains compatible

### What Changes

- Node writes tasks → outbox table, then sends NOTIFY 'intercomd_tasks'
- Daemon listens to NOTIFY 'intercomd_tasks', polls outbox on wake
- Daemon writes messages → outbox table, then sends NOTIFY 'intercom_host'
- Node listens to NOTIFY 'intercom_host', drains outbox with retry

---

## Section 6: Why Not Full Rust Rewrite?

### The Node Host Owns Messaging Channels

Node's core responsibility:
```typescript
// WhatsApp webhook → Postgres
POST /v1/webhook/whatsapp
→ db.storeChatMetadata(group)
→ db.storeMessage(chat_jid, msg)
→ return 200

// Telegram IPC poll → Postgres
ipc.pollTelegramUpdates()
→ db.storeChatMetadata(group)
→ db.storeMessage(chat_jid, msg)
```

These are **I/O-bound, request-driven workloads** that Node handles well (async/await, non-blocking I/O). Moving them to Rust would:
- Require rebuilding Grammy SDK in Rust (3–4 weeks)
- Lock Telegram changes into daemon release cycle
- Not improve latency (I/O is still network-bound)

### Container Dispatch Should Stay in Rust

Rust's value:
```rust
// Tokio concurrency model handles:
// - Concurrent group processing (tokio::spawn)
// - IPC streaming (AsyncRead + BufReader)
// - Container stdout/stderr parsing (real-time)
// - Timeout enforcement (tokio::time::timeout)
// - Graceful shutdown (watch::channel)
```

Node would need:
- child_process spawn for container (blocking)
- Stream parsing for OUTPUT markers (async, but Node's streaming is clunky)
- Timeout enforcement (no elegant solution in Node)

### Operational Reality

- **Team familiarity:** Developers know Node better than Rust
- **Debugging:** Node stack traces are clearer; Rust backtraces require symbols
- **Iteration speed:** Node hot-reload works out-of-the-box
- **TypeScript type safety** ≠ **Rust type safety** (Rust caught several concurrency bugs)

Keeping both languages allows each to be used for its strength:
- **Node:** External I/O (HTTP webhooks, async messaging)
- **Rust:** Internal orchestration (scheduling, queuing, containerization)

---

## Section 7: Decision Matrix

| Criterion | Option A | Option B | Option C | Option D | Option E |
|-----------|----------|----------|----------|----------|----------|
| **Effort (weeks)** | 2 | 3–4 | 0.5–1 | 4–6 | +0.5 on A |
| **Risk (high/med/low)** | Low | High | Low | High | Low |
| **Operational gain** | High | Medium | Medium | Medium | High |
| **Maintainability** | Good | Worse | Better | Worse | Good |
| **Latency improvement** | ~50ms (NOTIFY) | ~100ms (no HTTP) | ~50ms | ~10ms | ~50ms (NOTIFY) |
| **Failure recovery** | Excellent | Good | Good | Fair | Excellent |
| **Team velocity impact** | None | Negative | Neutral | Negative | None |
| **Deployment risk** | Medium | High | Low | High | Medium |

**Recommended:** **Option A (LISTEN/NOTIFY) + Option C (optional, later)** as separate PRs.

---

## Section 8: Concrete Next Steps

### Immediate (This Sprint)

1. **Create beads** for SYNTHESIS findings:
   - P1-001: Atomic task claim (1 day)
   - P1-002: Transactional log + update (1 day)
   - P1-004: PgPool eviction (2 days)
   - P1-005: UUID filename (0.5 days)
   - P0-001: Redaction library (3 days)

2. **Code review checkpoint** (day 2):
   - Verify atomic claim logic doesn't introduce race conditions
   - Validate PgPool eviction covers all error paths

3. **Deploy to staging** (end of sprint):
   - Verify no regressions in scheduler operation
   - Monitor Postgres query latency (should not increase)

### Following Sprint

1. **Design outbox schema**:
   - outbox_daemon_to_node (action, payload, retry_count, created_at)
   - outbox_node_to_daemon (action, payload, retry_count, created_at)
   - Indexes on (created_at, retry_count) for efficient polling

2. **Implement LISTEN/NOTIFY loop** in daemon:
   - tokio_postgres async subscription
   - Fallback polling if subscription drops
   - Handle Postgres connection loss gracefully

3. **Implement Node listener** (TypeScript):
   - Start Postgres subscription on startup
   - Drain outbox with exponential backoff
   - Handle Postgres connection loss gracefully

4. **Migrate dual-write calls**:
   - Replace all dualWriteToPostgres() with outbox insert
   - Remove HTTP dependency from data path

5. **Test & validate**:
   - End-to-end test: create task, verify it reaches daemon
   - Chaos test: kill daemon mid-task, restart, verify recovery
   - Load test: 10 concurrent tasks, verify ordering preserved

---

## Section 9: FAQ

**Q: Why not use RabbitMQ / Redis instead of Postgres LISTEN/NOTIFY?**

A: Postgres LISTEN/NOTIFY is **already available** (no new dependency), provides **natural ordering** (SQL row insertion order), and integrates with **existing transaction model** (durability for free). RabbitMQ would require separate deployment, operational complexity, and learning curve for async patterns.

**Q: Could we use Unix sockets instead of Postgres?**

A: Unix sockets work for local only. If daemon and Node are ever on separate machines (cluster deployment), Postgres is the only durable option. Start with what scales.

**Q: Does Hermes's file-lock approach work in cloud (Kubernetes)?**

A: No. Kubernetes pods don't share filesystems. File locks only work for single-machine deployment. Postgres LISTEN/NOTIFY works across any network.

**Q: Why not fully embrace Hermes's async/await model?**

A: Hermes is **single-process + single-threaded** (asyncio loop with one worker thread for execution). Intercom needs **multi-group fair scheduling** (multiple containers running per-group, serialized). Hermes's model is simpler but less scalable.

**Q: Should we add gRPC between Node and Daemon?**

A: gRPC requires code generation + schema definition. Postgres + outbox is simpler, more observable (you can query outbox directly), and requires no new RPC protocol. Use gRPC if we need **low-latency bidirectional streaming** (we don't currently).

---

## Section 10: Risk Mitigation

### Risk: LISTEN/NOTIFY subscription drops silently

**Mitigation:** Add fallback polling (Option E) every 5 minutes. If outbox has stale entries (older than 5min, retry_count < 3), retry them.

### Risk: Outbox table grows unbounded

**Mitigation:** Add retention policy (keep entries ≤ 7 days, then archive to history table). Monitor outbox row count; alert if > 10,000 rows.

### Risk: Daemon restarts before NOTIFY callback processed

**Mitigation:** Store LISTEN subscription state in Postgres (last_notify_seq). On restart, query unseen entries since last_seq.

### Risk: Node and Daemon both retry same message

**Mitigation:** Use idempotent keys (task_id + attempt_number). Outbox row includes `idempotent_key`, daemon deduplicates on retry.

---

## Conclusion

**Intercom's architecture is sound.** The dual-process model is a strength, not a weakness:
- Node handles I/O-bound messaging (does this well)
- Rust handles CPU-bound orchestration (does this well)
- Postgres is the common source of truth (proper design)

**The problem is IPC:** Fire-and-forget HTTP is unreliable, unordered, and lacks backpressure.

**The solution:** Replace HTTP with Postgres LISTEN/NOTIFY (2 week effort). This gives us:
- **Ordered delivery** (FIFO from Postgres rows)
- **Durability** (outbox pattern)
- **Backpressure** (Node controls drain rate)
- **Recovery** (both processes can replay unsent messages)

**No rewrite needed.** Fix the bugs from SYNTHESIS, implement reliable IPC, and Intercom is production-ready.

