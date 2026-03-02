# Intercom Architecture: Decision Summary

**Analysis Date:** 2026-03-02
**Decision:** Keep dual-process (Node + Rust), implement Postgres LISTEN/NOTIFY for IPC
**Timeline:** 2–3 weeks

---

## TL;DR

Intercom's **dual-process architecture is sound.** Hermes is a useful reference for defensive patterns (redaction, pairing, always-log-local), not a wholesale replacement.

**Fix these immediately (8.5 days):**
1. Atomic task claim: `SELECT ... FOR UPDATE SKIP LOCKED`
2. Transactional log + update (one SQL transaction)
3. PgPool eviction on connection error
4. IPC filename collision (UUID instead of rand_u16)
5. Session redaction before disk writes

**Then implement reliable IPC (2 weeks):**
- Replace fire-and-forget HTTP with Postgres LISTEN/NOTIFY
- Outbox pattern for at-least-once delivery
- Both processes drain outbox with exponential retry

**Don't do these:**
- ❌ Rewrite Node in Rust (unnecessary, Node owns I/O-bound work)
- ❌ Port Telegram to Rust (high effort, wrong abstraction)
- ❌ Adopt Hermes's file-lock model (doesn't scale to multi-machine)

---

## What Hermes Does Right

| Pattern | Where? | Value | Action |
|---------|--------|-------|--------|
| **File-lock TOCTOU protection** | `scheduler.py:285–291` | Prevents double-dispatch | Use SQL `SELECT ... FOR UPDATE SKIP LOCKED` instead |
| **Always-log-local pattern** | `delivery.py` & `scheduler.py` | Crash-safe audit trail | Wrap log + update in single SQL transaction |
| **Redaction library** | `agent/redact.py` | Credential protection | Port to Go, apply universally |
| **Pairing/OTP** | `gateway/pairing.py` | User authorization | Port to Rust (medium priority) |
| **Delivery target DSL** | `delivery.py` | Flexible output routing | Portable; backlog item for intercom |

---

## What IronClaw Does Better

| Feature | Hermes | IronClaw | Winner |
|---------|--------|----------|--------|
| **Task persistence** | File-based (~/.hermes/jobs.json) | Postgres with transactions | IronClaw ✓ |
| **Multi-runtime support** | Single agent backend | Claude/Gemini/Codex selection per group | IronClaw ✓ |
| **Per-group fairness** | Single job thread (no fairness) | Per-group serialization + queue | IronClaw ✓ |
| **Interactive sessions** | Job → Result (one-shot) | Multi-turn messages via IPC | IronClaw ✓ |
| **Distributed scheduling** | Single cron instance (not distributed) | Ready for multi-daemon setup | IronClaw ✓ |

---

## The Dual-Process Problem

**Fire-and-forget HTTP is broken:**

```
Node: INSERT task INTO sqlite, then POST http://localhost:8001/v1/db/tasks
      → No ack, no retry, no ordering guarantee

Result:
- Network hiccup = task lost
- Daemon restart = tasks in Node not seen by Daemon
- No backpressure = Daemon can be overloaded
- Out-of-order callbacks = user sees reversed outputs
```

**Solution: Postgres LISTEN/NOTIFY**

```
Node: INSERT task INTO postgres, SELECT pg_notify('intercomd_tasks', ...)
      ↓ Daemon wakes up immediately (or polls fallback)
      ↓ Drains outbox with retry

Result:
- Ordered delivery (FIFO from Postgres row order)
- Durable (outbox survives crashes)
- Backpressure (Node controls drain rate)
- Recovery (both processes can replay unsent messages)
```

---

## The Four Migration Options (Ranked)

### ✅ Recommended: Option A — LISTEN/NOTIFY
- **Effort:** 2 weeks
- **Risk:** Low (isolated to schema + subscription logic)
- **Gain:** Reliable, ordered, durable IPC; no new dependencies
- **Verdict:** Ship this. Solves 80% of problems for 20% of effort.

### ⚠️ Conditional: Option C — Daemon Command Router
- **Effort:** 2–3 days (after Option A)
- **Risk:** Low (Node becomes thin HTTP→Postgres bridge)
- **Gain:** Cleaner architecture, faster command execution
- **Verdict:** Nice-to-have, do after Option A stabilizes.

### ❌ Not Recommended: Option B — Port Telegram to Rust
- **Effort:** 3–4 weeks (Grammy SDK has no maintained Rust port)
- **Risk:** High (custom SDK maintenance burden)
- **Gain:** One fewer process (but Node still needed for WhatsApp/Discord)
- **Verdict:** Not worth it. Node already handles this.

### ❌ Not Recommended: Option D — Full Rust Rewrite
- **Effort:** 4–6 weeks
- **Risk:** High (rewrite all scheduler + queue logic)
- **Gain:** ~10ms latency improvement
- **Verdict:** Rust is stronger for orchestration, but this is overkill. Keep the win-win split.

---

## Immediate Priorities (This Sprint)

### Fix Critical Bugs (from SYNTHESIS report)

**P1-001: Atomic task claim** (1 day)
- `SELECT id FROM scheduled_tasks WHERE next_run <= now() AND status = 'active' FOR UPDATE SKIP LOCKED LIMIT 10`
- Prevents two daemons from claiming same task

**P1-002: Transactional log + update** (1 day)
- Wrap `INSERT task_run_logs` + `UPDATE scheduled_tasks` in one transaction
- Prevents orphaned logs on crash

**P1-004: PgPool eviction** (2 days)
- Detect connection errors in `with_client()`
- Evict stale connection from pool
- Retry on next call
- Fixes permanent failure after Postgres restart

**P1-005: IPC filename collision** (0.5 days)
- Replace `rand_u16()` (65K possible values) with `uuid::Uuid::new_v4()`
- Prevents `.tmp` file overwrites under high concurrency

**P0-001: Session redaction** (3 days, parallel)
- Port `redact.py` to Go (`core/redact/redact.go`)
- Apply to all session persistence paths
- Covers AWS keys, JWT tokens, private keys, DB URLs, API keys

**Total:** 6.5 days (4.5 + 3 in parallel)

---

## Implementation Strategy

### Phase 1: Fix (Days 1–5)
Create 5 beads:
1. `iv-sched-atomic-claim` (P1-001)
2. `iv-sched-transactional-log` (P1-002)
3. `iv-postgres-eviction` (P1-004)
4. `iv-ipc-uuid` (P1-005)
5. `iv-security-redaction` (P0-001, parallel)

### Phase 2: LISTEN/NOTIFY (Days 6–11)
1. Outbox schema (1 day)
2. Daemon LISTEN loop (2 days)
3. Node listener (2 days)
4. Replace dual-write calls (1 day)

### Phase 3: Testing (Days 12–15)
1. End-to-end tests (1 day)
2. Chaos tests (1 day)
3. Performance tests (1 day)
4. Staging soak (1 day)

---

## Architecture Comparison

### Before (Status Quo)
```
Node                    Daemon
====                    ======
CREATE task (SQLite)
  ↓ fire-and-forget HTTP POST
  ↓ (no ack, no retry)
  └→ /v1/db/tasks (may fail silently)

Poll for messages
  ↓ HTTP callback (fire-and-forget)
  └→ /v1/ipc/send-message (may fail silently)
```

Problems:
- ❌ No ordering guarantee
- ❌ No durability on failure
- ❌ No backpressure
- ❌ Process boundary complexity

### After (Option A)
```
Node                    Daemon
====                    ======
INSERT task             Poll Postgres
SELECT pg_notify(...)       ↓ LISTEN wake
  ↓                    SELECT outbox_daemon_to_node
  └→ Daemon notified   ↓
                       Retry with backoff
                       ↓
                       INSERT outbox_node_to_daemon
                       SELECT pg_notify(...)
                       ↓
Node subscribed to notify
  ↓
SELECT outbox_daemon_to_node
  ↓
sendMessage with retry
```

Benefits:
- ✅ FIFO ordering (from Postgres rows)
- ✅ Durable (outbox survives crashes)
- ✅ Backpressure (Node controls drain)
- ✅ Recovery (replay unsent messages)

---

## Why Not These Other Options?

### "Just use RabbitMQ"
- Postgres LISTEN/NOTIFY is already available (no new service)
- Simpler (all data in one place: Postgres)
- Better observability (query outbox directly)
- No new operational burden

### "Use Unix sockets"
- Doesn't work across machines (Kubernetes)
- No persistence (crashes = messages lost)
- Postgres works today and scales to multi-machine

### "Add gRPC"
- Unnecessary complexity for this use case
- Postgres + outbox is simpler, more observable
- gRPC is better for **bidirectional streaming** (we don't need it)

### "Keep HTTP, just add retry"
- Still lacks ordering guarantees
- Client-side retry is fragile (no acknowledgment protocol)
- Server-side state is source of truth (Postgres), not client

---

## Risk Mitigation

| Risk | Mitigation |
|------|-----------|
| LISTEN subscription drops | Fallback polling every 5 min; alert if outbox > 1000 |
| Outbox grows unbounded | Retention policy (≤ 7 days); monitor row count |
| Duplicate messages | Idempotent key (task_id + attempt#); dedup on retry |
| Postgres unavailable | Already the case; add Postgres to readyz endpoint |
| Network partition | Each process has fallback polling (recovers in 5 min) |

---

## Success Metrics

After Option A implementation:

- [ ] **Reliability:** Task created by Node reaches Daemon within 5s
- [ ] **Durability:** Daemon crash doesn't lose tasks (outbox has retry entries)
- [ ] **Ordering:** Multi-task sequences preserve order
- [ ] **Performance:** LISTEN latency < 500ms (typically ~50ms)
- [ ] **Operational:** Outbox row count stays < 100 under normal load
- [ ] **Recovery:** Both processes survive restart + crash cycle

---

## What We're NOT Doing

| What | Why Not |
|------|---------|
| Full rewrite to single process | IronClaw's Rust is better for CPU-bound orchestration; Node's async is better for I/O |
| Move Telegram to Rust | High effort, locks changes to daemon release cycle, no single-process benefit |
| Adopt Hermes file-lock model | Doesn't scale past single machine; SQL is better |
| Replace Postgres with file-based storage | Postgres is proven, durable, queryable; filesystem is not |
| Use Redis/RabbitMQ for IPC | Unnecessary; Postgres LISTEN/NOTIFY is simpler + already available |

---

## References

- **Full analysis:** [ARCHITECTURAL-ANALYSIS-intercom-vs-hermes.md](ARCHITECTURAL-ANALYSIS-intercom-vs-hermes.md)
- **Roadmap:** [2026-03-02-intercom-hermes-consolidation.md](../solutions/2026-03-02-intercom-hermes-consolidation.md)
- **SYNTHESIS report:** [SYNTHESIS-hermes-research.md](SYNTHESIS-hermes-research.md)
- **Hermes reference:** `/research/hermes_agent/cron/scheduler.py`
- **Intercom docs:** `apps/intercom/CLAUDE.md` & `apps/intercom/AGENTS.md`

