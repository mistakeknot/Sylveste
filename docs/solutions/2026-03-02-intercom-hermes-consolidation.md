# Intercom-Hermes Consolidation: Recommendation & Roadmap

**Date:** 2026-03-02
**Decision:** Keep dual-process architecture, replace fire-and-forget HTTP with Postgres LISTEN/NOTIFY
**Timeline:** 2–3 weeks to production
**Effort:** 15–18 days

---

## Recommended Approach: Option A (LISTEN/NOTIFY)

### What We're Fixing

**Current problem:** Node and Daemon communicate via fire-and-forget HTTP POST calls. If the network hiccups or the daemon is restarting, messages are silently lost. This causes:
- Scheduled tasks to be missed
- Session updates to not propagate
- No way to recover if a callback fails

**New design:** Both processes write to Postgres outbox tables, then send a LISTEN/NOTIFY signal. The other process subscribes to the signal, wakes up, and drains the outbox with exponential retry.

### Architecture Diagram

```
Node Host                           Rust Daemon
===========                         ============

create task                         polls Postgres
  ↓                                  ↓
INSERT outbox_node_to_daemon    SELECT ... WHERE next_run <= now()
SELECT pg_notify(...)           ↓
  ↓                             enqueue task
  └─→ Daemon wakes up on NOTIFY    ↓
                                run container
                                  ↓
                                INSERT outbox_daemon_to_node
                                SELECT pg_notify(...)
                                  ↓
Node subscribes to NOTIFY ←───────┘
  ↓
SELECT FROM outbox_daemon_to_node
  ↓
sendMessage() + increment retry_count
```

### Key Changes

| What | Before | After |
|------|--------|-------|
| **Task creation flow** | Node: SQLite + fire-and-forget HTTP | Node: SQLite + outbox INSERT + NOTIFY |
| **Task dispatch** | Daemon: HTTP listener (no backpressure) | Daemon: LISTEN subscription + fallback polling |
| **Session updates** | Node: SQLite + HTTP, Daemon: Postgres | Daemon: Postgres only, Node: subscribes to notify |
| **Message callback** | Daemon: HTTP POST to Node (fire-and-forget) | Daemon: outbox INSERT + NOTIFY |
| **Reliability** | At-most-once (messages lost on crash) | At-least-once (with idempotent deduplication) |

---

## What Stays the Same

- **Node host:** Still handles external channels (WhatsApp, Discord webhooks)
- **Telegram bridge:** Still uses IPC polling (unchanged)
- **Container dispatch:** Still in Rust (tokio async)
- **Per-group serialization:** Still enforced via GroupQueue
- **Database schema:** All existing tables + 2 new outbox tables

---

## Phased Rollout

### Phase 1: Fix Critical Bugs (Days 1–5)

From the SYNTHESIS report, implement these in parallel:

| Task | Effort | Blocker |
|------|--------|---------|
| Atomic task claim (`SELECT ... FOR UPDATE SKIP LOCKED`) | 1d | Scheduler reliability |
| Transactional log + update (wrap in SQL transaction) | 1d | Audit trail durability |
| PgPool error-triggered eviction | 2d | Recovery after Postgres restart |
| IPC filename collision (replace rand_u16 with UUID) | 0.5d | Message integrity |
| **Sum** | **4.5 days** | **Unblock next phase** |

**Parallel track:** Start redaction library (3d) while others are debugging.

### Phase 2: Implement LISTEN/NOTIFY (Days 6–11)

**Day 6:** Schema design
- Create `outbox_node_to_daemon` table (action, payload, retry_count, created_at, idempotent_key)
- Create `outbox_daemon_to_node` table
- Create indexes: (created_at, retry_count) for efficient polling

**Days 7–8:** Daemon-side listener
- Implement tokio_postgres LISTEN subscription in a background task
- Subscribe to channel 'intercomd_notify'
- On NOTIFY wake, drain outbox_daemon_to_node with 3-retry backoff
- Fallback: every 5 minutes, poll for stale entries

**Days 9–10:** Node-side listener
- Implement Postgres async subscription in Node (node-postgres plugin or pure JS)
- Subscribe to channel 'intercom_host'
- On NOTIFY wake, drain outbox_node_to_daemon with exponential backoff
- Fallback: every 5 minutes, poll for stale entries

**Day 11:** Replace dual-write calls
- Replace all `dualWriteToPostgres()` calls with INSERT into outbox_node_to_daemon
- Update daemon endpoints to write to outbox instead of directly returning

### Phase 3: Integration & Testing (Days 12–15)

**Day 12:** End-to-end tests
- Create task via HTTP → verify it reaches daemon
- Daemon processes → verify callback reaches Node
- Verify ordering: task1, task2 arrive in order

**Day 13:** Chaos tests
- Kill daemon mid-task → restart → verify outbox has retry entries
- Kill Node host → restart → verify pending Daemon→Node messages are retried
- Simulate network partition → recover → verify deduplication

**Day 14:** Performance tests
- Measure latency: create task → daemon wakes (should be < 1s)
- Measure throughput: 10 concurrent tasks per group (no ordering issues)
- Verify Postgres doesn't become bottleneck (LISTEN should be fast)

**Day 15:** Staging deployment
- Run on staging environment for 24h
- Monitor outbox table row count (should stay < 100)
- Monitor LISTEN subscription health (no unexpected drops)

---

## Acceptance Criteria

### Reliability
- [ ] Task created by Node appears in Daemon within 5 seconds
- [ ] Daemon processes task and routes response back to Node
- [ ] If Daemon crashes mid-task, task is retried on restart (no loss)
- [ ] If Node crashes before draining outbox, messages are retried on restart

### Ordering
- [ ] Multiple tasks enqueued in sequence preserve order (task1 before task2)
- [ ] Messages from multiple groups don't block each other

### Performance
- [ ] LISTEN/NOTIFY latency < 500ms (typically ~50ms)
- [ ] No increase in Postgres query latency
- [ ] Outbox row count stays < 100 under normal load

### Operational
- [ ] Fallback polling works if LISTEN subscription drops
- [ ] Retry logic respects exponential backoff (5s, 10s, 20s, 40s, 80s)
- [ ] Logging captures each retry attempt (for debugging)

---

## Why This Approach

### Rejected: Full Rust Rewrite (Option D)
- **Effort:** 4–6 weeks
- **Risk:** High (need to rewrite all Node logic in Rust)
- **Gain:** ~10ms latency (not worth the cost)
- **Problem:** Node's async/await is better for I/O-bound work (external channels)

### Rejected: Move Telegram to Rust (Option B)
- **Effort:** 3–4 weeks
- **Risk:** High (Grammy SDK has no Rust equivalent; would need custom port)
- **Gain:** Single process (but Node still needed for WhatsApp/Discord)
- **Problem:** Locks Telegram changes to daemon release cycle

### Accepted: LISTEN/NOTIFY (Option A)
- **Effort:** 2 weeks (reasonable)
- **Risk:** Low (isolated schema + subscription logic)
- **Gain:** Reliable, ordered, durable IPC without new dependencies
- **Problem:** Minor (polling fallback adds complexity, but needed for resilience)

---

## Technology Stack

### Additions
- **tokio_postgres:** Already dependency of intercomd (no new crate)
- **node-postgres:** Already dependency of Node host (no new crate)
- **pg_notify triggers:** SQL-only (no code)

### No New Dependencies
- No RabbitMQ, Redis, gRPC, or event bus
- Everything flows through existing Postgres connection

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| LISTEN subscription drops silently | Add fallback polling every 5 min; alert if outbox > 1000 rows |
| Outbox table grows unbounded | Retention policy: keep ≤ 7 days; monitor row count |
| Idempotent key collision | Include (task_id, attempt_number) in key; dedup on retry |
| Postgres down = both processes stuck | Already the case; add Postgres healthcheck to readyz endpoint |

---

## Deployment Checklist

- [ ] Phase 1 beads created and assigned
- [ ] Phase 1 code review (focus: scheduler atomicity)
- [ ] Phase 1 merged to main + pushed
- [ ] Phase 2 beads created
- [ ] Outbox schema applied to staging DB
- [ ] LISTEN/NOTIFY loops tested locally
- [ ] Phase 2 code review (focus: error handling + recovery)
- [ ] Phase 2 merged to main + pushed
- [ ] Phase 3 chaos tests pass
- [ ] Staging deployment stable for 24h
- [ ] Production rollout with rollback plan

---

## Future Optimizations

### Option C: Command Logic in Daemon (Lower Priority)
- Move command parsing from Node to Daemon
- Makes Node pure HTTP→Postgres bridge
- Effort: 2–3 days (after Phase 2)
- Benefit: Simpler Node, faster command execution

### Distributed Scheduling
- Add replication key to tasks: route to specific daemon
- Enables multi-machine scheduler (round-robin or sticky)
- Prerequisite: Phase 1–2 must be stable first

---

## References

- **Full analysis:** [ARCHITECTURAL-ANALYSIS-intercom-vs-hermes.md](../reviews/ARCHITECTURAL-ANALYSIS-intercom-vs-hermes.md)
- **SYNTHESIS report:** [SYNTHESIS-hermes-research.md](../reviews/SYNTHESIS-hermes-research.md)
- **Hermes scheduler reference:** `research/hermes_agent/cron/scheduler.py:285–326` (file lock pattern)
- **Hermes delivery pattern:** `research/hermes_agent/gateway/delivery.py:57–90` (routing DSL)
