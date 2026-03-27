# Claiming Protocol Atomicity: Distributed Agent-to-Bead Assignment

**Author**: flux-research (distributed systems engineer persona)
**Date**: 2026-03-19
**Scope**: Atomic claiming for the Sylveste self-dispatch loop — optimistic vs pessimistic, CAS semantics, heartbeat/TTL, race handling
**Status**: Research complete

---

## 1. Current Claiming Architecture and Its Gaps

The existing claim protocol is a **two-phase non-atomic write**:

```bash
# Phase 1: Set assignee + status (Dolt row update)
bd update "$BEAD_ID" --claim

# Phase 2: Write identity metadata (Dolt key-value state)
bd set-state "$BEAD_ID" "claimed_by=${CLAUDE_SESSION_ID:-unknown}"
bd set-state "$BEAD_ID" "claimed_at=$(date +%s)"
```

**Failure window**: If the agent crashes between Phase 1 and Phase 2, the bead is marked `in_progress` with `assignee` set but `claimed_by=unknown` and no `claimed_at` timestamp. The heartbeat system (`clavain-cli bead-heartbeat`) never starts, so stale-claim detection cannot fire. The bead is effectively zombied.

**Race window**: Two agents running `bd update --claim` concurrently on the same bead can both succeed if `bd update` does not check-and-set atomically. Dolt uses REPEATABLE_READ isolation — the second writer's commit will succeed if they modified different cells, or fail if they modified the same cell to different values. But `--claim` sets `status=in_progress` and `assignee=<agent>`, so both writers touch the same cells. Whether Dolt detects this as a conflict depends on whether `bd update --claim` runs in a single Dolt transaction or as separate writes.

---

## 2. Industry Patterns for Task Claiming

### 2.1 Celery: Visibility Timeout (Pessimistic Lease)

Celery's claim model is **broker-mediated pessimistic leasing**:

1. Worker polls queue; broker delivers task and **hides it** from other workers for `visibility_timeout` seconds (default: 1 hour on SQS, configurable on Redis).
2. Worker processes task, then sends `ack`. If no ack within timeout, broker **re-queues** the task.
3. Delivery guarantees vary by broker:
   - **RabbitMQ/SQS**: at-least-once (redelivery on timeout)
   - **Redis pub/sub**: at-most-once (message lost on disconnect)

**Key insight for Sylveste**: Celery's `visibility_timeout` is the equivalent of a claim TTL. With `acks_late=True`, tasks are only acked on completion — but if the task takes longer than the visibility timeout, the broker redelivers it to another worker, causing **duplicate execution**. This is the exact analog of the stale-claim problem.

**Celery's mitigation**: `reject_on_worker_lost=True` combined with idempotent tasks. The system accepts that duplicates will occasionally occur and relies on idempotency to make them safe.

**Relevance**: Beads are not naturally idempotent (a coding task that commits code cannot be trivially replayed). This means Sylveste needs stronger claim exclusivity than Celery provides, or must make the work itself idempotent (e.g., check if the commit already exists before executing).

Sources: [Celery Tasks docs](https://docs.celeryq.dev/en/stable/userguide/tasks.html), [Celery configuration](https://docs.celeryq.dev/en/main/userguide/configuration.html), [Optimizing Celery Retries at Scale](https://medium.com/@bhagyarana80/optimizing-celery-retries-and-visibility-timeouts-at-high-scale-aa79f923d880)

### 2.2 Temporal: Task Slots + Heartbeat Leases (Optimistic with Server-Side Bookkeeping)

Temporal's model is fundamentally different — the **server owns task state**, not the worker:

1. Activities are scheduled by the Temporal server onto a **Task Queue**.
2. A worker polls the queue and receives a **task token** — a lease on that specific activity execution.
3. The worker must **heartbeat** periodically (`HeartbeatTimeout`). If the server receives no heartbeat within the timeout, it considers the activity failed and may schedule a retry per the `RetryPolicy`.
4. **Sticky Execution** pins subsequent workflow tasks to the same worker via a worker-specific queue, avoiding replay overhead. But activities (the analog of beads) are NOT sticky — any worker can pick them up.

**Temporal's four timeout types**:
- `ScheduleToStartTimeout`: max time a task sits in queue before a worker picks it up
- `StartToCloseTimeout`: max time from worker pickup to completion
- `HeartbeatTimeout`: max interval between heartbeats during execution
- `ScheduleToCloseTimeout`: end-to-end timeout including retries

**Key insight for Sylveste**: Temporal separates "claim" (worker picks up task token) from "identity" (worker heartbeats with that token). There is no gap — the claim IS the task token, and the heartbeat extends it. Sylveste's two-phase `bd update --claim` + `bd set-state` is the anti-pattern here. The fix is to make claiming and identity-writing a single operation.

**Temporal's crash handling**: If a worker crashes, it stops heartbeating. The server detects this via `HeartbeatTimeout` and retries. The worker never has to "write its identity" separately — the server knows which worker has the task token because the server issued it.

Sources: [Temporal Activity timeouts](https://temporal.io/blog/activity-timeouts), [Detecting Activity failures](https://docs.temporal.io/encyclopedia/detecting-activity-failures), [Worker performance](https://docs.temporal.io/develop/worker-performance)

### 2.3 Comparison Table

| Property | Celery | Temporal | Current Sylveste |
|---|---|---|---|
| Claim mechanism | Broker hides message | Server issues task token | `bd update --claim` (Dolt row) |
| Identity binding | Implicit (worker received msg) | Implicit (task token holder) | Explicit `bd set-state` (separate write) |
| Claim atomicity | Atomic (single broker op) | Atomic (server-side) | **Non-atomic (2-3 shell commands)** |
| Failure detection | Visibility timeout expiry | HeartbeatTimeout | `bead-heartbeat` + manual sweep |
| Duplicate protection | Idempotency keys | Server-side dedup | **None** |
| Redelivery | Automatic on timeout | Automatic per RetryPolicy | **Manual (requires external sweep)** |

---

## 3. Contract Net Protocol vs Optimistic Grab-and-Validate

### 3.1 Contract Net Protocol (CNP)

The FIPA Contract Net Protocol is a multi-agent task allocation mechanism with explicit bidding phases:

1. **Call for Proposals (CFP)**: Manager broadcasts task description to all potential contractors.
2. **Propose/Refuse**: Each agent evaluates the task against its capabilities and load, then bids or refuses.
3. **Accept/Reject**: Manager evaluates bids, selects winner, sends `accept-proposal` to winner and `reject-proposal` to losers.
4. **Inform/Failure**: Winner executes and reports result.

**Advantages for small fleets**:
- Eliminates races entirely — the manager serializes assignment decisions
- Agents can signal load/capability in their bids (e.g., "I'm already running 2 beads, bid lower")
- Natural affinity routing — agents bid higher for tasks matching their cached context

**Disadvantages**:
- Requires a manager (single point of failure / bottleneck)
- 4 message rounds per assignment: CFP -> Propose -> Accept -> Inform
- Latency: for a 10-minute coding task, 2-3 seconds of bidding overhead is negligible, but the protocol complexity is not
- The manager must wait for all bids (or a timeout) before deciding — slow agents delay assignment

**Extensions**: The Contract Net with Confirmation Protocol (CNCP) adds a confirmation round to handle agents that bid on multiple simultaneous CFPs and might have become unavailable by acceptance time.

Sources: [Contract Net Protocol (Wikipedia)](https://en.wikipedia.org/wiki/Contract_Net_Protocol), [FIPA CNP Spec](http://www.fipa.org/specs/fipa00029/SC00029H.html)

### 3.2 Optimistic Grab-and-Validate

The alternative is a **stampede pattern**: all idle agents independently query `bd list --status=open`, rank beads by priority, and attempt to claim their top pick. If the claim fails (someone else got there first), they retry with their next pick.

**Advantages**:
- No coordinator — pure peer-to-peer, no single point of failure
- Simpler implementation — one `bd update --claim` with CAS semantics
- Lower latency for the common case (no contention with <20 agents)
- Already close to what Sylveste does today

**Disadvantages**:
- Wasted work under contention — N agents may all try to claim the same top-priority bead
- Requires CAS semantics in the claim operation to prevent double-assignment
- Priority inversion — agent A may claim bead X while better-suited agent B was about to

### 3.3 Recommendation for Sylveste (<20 agents)

**Use optimistic grab-and-validate.** Rationale:

1. **Fleet size**: With <20 agents, the probability of two agents racing for the same bead is low. Even in the worst case (all agents idle simultaneously, one new bead appears), only one retry round is needed.
2. **No coordinator requirement**: Sylveste's architecture is process-per-tmux-pane. Introducing a bidding manager means a new daemon, a new failure mode, and a new communication protocol.
3. **Dolt provides natural CAS**: If `bd update --claim` is implemented as a Dolt transaction that checks `status=open` before setting `status=in_progress`, concurrent claimants will conflict at the Dolt merge level. Only the first writer wins; the second gets a merge conflict. This is free CAS from the existing datastore.
4. **Claim jitter**: Add 0-500ms random delay before claiming to spread stampedes. For 10-minute tasks, 500ms jitter is imperceptible.

**What CNP would be good for**: If the fleet grows beyond ~50 agents, or if capability-based routing becomes critical (e.g., "only GPU agents can take ML beads"), a lightweight bidding layer on top of the grab-and-validate base would make sense. But that is not Phase 1.

---

## 4. Kubernetes Lease Objects: CAS Without a Lock Server

Kubernetes Leases (`coordination.k8s.io/v1`) are a production-proven pattern for distributed claiming that maps directly to Sylveste's needs:

### 4.1 How K8s Leases Work

1. A Lease object has: `holderIdentity`, `leaseDurationSeconds`, `acquireTime`, `renewTime`, `leaseTransitions`.
2. **Acquisition**: A candidate writes its identity to the Lease with a `resourceVersion` condition. The API server uses **optimistic concurrency control** — if the `resourceVersion` doesn't match (someone else acquired it first), the write is rejected with a 409 Conflict.
3. **Renewal**: The holder updates `renewTime` at `leaseDurationSeconds / 2` intervals. This is the heartbeat.
4. **Expiry**: If `now > renewTime + leaseDurationSeconds`, the lease is expired. Any candidate can overwrite it with a new `resourceVersion`-conditional write.

**Key design property**: There is no lock server. The API server's etcd backend provides CAS via `resourceVersion`. The Lease object is just a regular Kubernetes resource — no special coordination service.

### 4.2 Mapping to Sylveste

| K8s Lease Field | Sylveste Bead Equivalent |
|---|---|
| `holderIdentity` | `claimed_by` (session ID) |
| `leaseDurationSeconds` | Stale-claim TTL |
| `acquireTime` | `claimed_at` |
| `renewTime` | Last heartbeat timestamp |
| `leaseTransitions` | Claim counter (useful for debugging) |
| `resourceVersion` | Dolt commit hash or row version |

**The critical insight**: K8s Leases make acquisition and identity-writing **a single atomic operation**. The candidate writes `holderIdentity` + `acquireTime` + `leaseDurationSeconds` in one PUT with a `resourceVersion` precondition. Either the whole write succeeds or it is rejected. There is no gap between "claimed" and "identity written."

### 4.3 Adapting for Dolt

Dolt doesn't have `resourceVersion`-style conditional writes natively. But it does have:

1. **Cell-level conflict detection**: If two transactions modify the same cell to different values, the merge fails. This is equivalent to a CAS — two agents writing different `claimed_by` values to the same bead will conflict.
2. **Branch-level transactions**: Each `bd` command runs in a Dolt transaction. If `bd update --claim` is modified to write `assignee`, `status`, `claimed_by`, AND `claimed_at` in a single transaction, the race window closes.

**Proposed single-transaction claim**:
```sql
-- Pseudocode for what bd update --claim should do internally
BEGIN;
UPDATE beads SET
  status = 'in_progress',
  assignee = '<agent_name>',
  claimed_by = '<session_id>',
  claimed_at = NOW()
WHERE id = '<bead_id>' AND status = 'open';
-- If 0 rows affected: bead was already claimed
COMMIT;
```

If two agents execute this concurrently, Dolt's REPEATABLE_READ isolation + cell-level conflict detection ensures only one succeeds. The loser's commit fails with a merge conflict on the `status` cell (both tried to change `open` -> `in_progress`).

Sources: [Kubernetes Leases](https://kubernetes.io/docs/concepts/architecture/leases/), [K8s Leader Election with Leases](https://medium.com/@contactomyna/leader-election-with-leases-in-distributed-systems-6fc46ea84b30), [K8s Leases for Optimistic Locking](https://medium.com/@sehgal.mohit06/kubernetes-leases-solution-to-leader-election-optimistic-locking-ratelimiting-concurrencycontrol-bb07f53c4462)

---

## 5. Crash-Before-Identity: Heartbeat Interval and Stale-Claim TTL

### 5.1 The Failure Timeline

For a ~10-minute coding task:

```
t=0s     Agent starts bd update --claim
t=0.1s   Claim succeeds (status=in_progress, claimed_by written)
t=0.1s   Agent begins work
t=150s   Agent crashes (OOM, SSH disconnect, tmux pane killed)
t=???    System detects stale claim
t=???    Bead is reclaimed by another agent
```

The question: what values for heartbeat interval (H) and stale-claim TTL (T) minimize both wasted time (bead sits claimed but unworked) and false positives (active agent's claim is revoked)?

### 5.2 Parameter Selection

**Industry conventions**:
- Temporal: `HeartbeatTimeout` typically 30-60s for activities. If no heartbeat received within this window, activity is considered failed.
- Kubernetes Leases: `leaseDurationSeconds` is typically 10-15s for leader election, with renewal at `leaseDuration / 2`.
- Celery + SQS: `visibility_timeout` default is 1 hour (designed for batch jobs, not interactive tasks).
- General rule of thumb: timeout = 2-3x heartbeat interval, and heartbeat interval >= 10x round-trip time.

**Sylveste-specific constraints**:
- Tasks are ~10 minutes. A 1-hour visibility timeout (Celery-style) wastes 50 minutes if the agent dies at t=1m.
- The heartbeat is `clavain-cli bead-heartbeat`, which writes `claimed_at` to Dolt. This is a Dolt transaction — not free. At ~100ms per write, a 30s heartbeat adds negligible overhead.
- False positive cost is HIGH: if an active agent's claim is revoked, it may commit code that conflicts with the new claimant. Two agents pushing to the same branch is worse than one agent being idle.

**Recommended values**:

| Parameter | Value | Rationale |
|---|---|---|
| Heartbeat interval (H) | **60 seconds** | Dolt transaction overhead is low; 60s gives 10 heartbeats per task |
| Stale-claim TTL (T) | **180 seconds (3 minutes)** | 3x heartbeat interval; detects crashes within ~3.5 minutes worst case |
| Grace period on revocation | **1 additional heartbeat cycle** | Before reclaiming, check once more — the agent may have been temporarily network-partitioned |
| Max task duration | **30 minutes** | Safety valve — any bead claimed for >30m is force-released regardless of heartbeats |

**Worst-case timeline with these values**:
```
t=0s     Agent claims bead, starts heartbeat loop (every 60s)
t=60s    Heartbeat 1 ✓
t=90s    Agent crashes
t=120s   Heartbeat 2 missed (expected at t=120s)
t=180s   Heartbeat 3 missed (expected at t=180s)
t=270s   TTL expires (last heartbeat at t=60s + TTL 180s = t=240s, plus grace 30s)
t=270s   Sweep marks bead as reclaimable
t=270s   Next idle agent claims it
```

**Wasted time**: ~3 minutes from crash to reclaim. Acceptable for 10-minute tasks — the alternative (no heartbeat) wastes the entire remaining sprint budget.

### 5.3 Heartbeat State Schema

The heartbeat should write a single compound state key rather than multiple `bd set-state` calls:

```bash
# Current: two separate writes (non-atomic, verbose)
bd set-state "$BEAD_ID" "claimed_by=${SESSION_ID}"
bd set-state "$BEAD_ID" "claimed_at=$(date +%s)"

# Proposed: single write with structured value
bd set-state "$BEAD_ID" "claim=${SESSION_ID}:$(date +%s):${HEARTBEAT_SEQ}"
```

The value format `<session_id>:<epoch>:<sequence>` lets the sweep detect:
- **Zombie**: `claim` exists but epoch is older than TTL
- **Orphan**: `status=in_progress` but no `claim` key at all (Phase 1 crash)
- **Stolen**: `claim` session_id doesn't match current `assignee` (race condition artifact)
- **Stale heartbeat**: sequence number hasn't incremented (agent alive but stuck)

---

## 6. Dolt as a CAS Backend

### 6.1 Dolt's Concurrency Model

Dolt uses **REPEATABLE_READ** isolation with **cell-level conflict detection** on merge:

- Two transactions that modify **different cells** of the same row merge cleanly.
- Two transactions that modify the **same cell to the same value** merge cleanly.
- Two transactions that modify the **same cell to different values** produce a **merge conflict**, and the second committer's transaction fails.

This is structurally equivalent to compare-and-swap:
- The "compare" is implicit — Dolt checks that no other transaction modified the same cell since your read.
- The "swap" is your write.
- If the compare fails (someone else wrote a different value), your commit is rejected.

### 6.2 Can `bd set-state` Implement CAS?

`bd set-state` writes to a key-value table in Dolt. If two agents concurrently call:

```bash
# Agent A
bd set-state "BEAD-123" "claim=agentA:1710856800:1"

# Agent B
bd set-state "BEAD-123" "claim=agentB:1710856801:1"
```

Both are writing different values to the same cell (`state.claim` for bead `BEAD-123`). Under Dolt's conflict detection, **the second writer's commit will fail with a merge conflict**. This IS compare-and-swap behavior — but only if both writes happen in overlapping transactions.

**Caveat**: If Agent A's transaction commits and completes before Agent B's transaction begins, Agent B sees the already-committed value and overwrites it. There is no conflict because from Dolt's perspective, Agent B's read already saw Agent A's write. This is standard REPEATABLE_READ behavior — it prevents lost updates within overlapping transactions but not sequential overwrites.

### 6.3 Making Claims Truly Atomic in Dolt

The fix is to make the claim a **conditional write**:

```sql
-- Only claim if still open (single transaction)
UPDATE beads SET status='in_progress', assignee='agentA'
WHERE id='BEAD-123' AND status='open';
-- Check: if 0 rows affected, bead was already claimed
```

This requires `bd update --claim` to include a `WHERE status='open'` precondition internally. If `bd` already does this (likely, since `--claim` semantically means "claim if available"), then the race protection is already present at the Dolt level. If `bd` does an unconditional update (overwrites whatever status exists), it needs modification.

**Recommended verification**: Check `bd` source code for whether `--claim` includes a status precondition. If not, this is the single highest-priority fix.

### 6.4 Branch-Level Transactions in Dolt

Dolt's branch model offers an alternative CAS approach:

1. Create a per-claim branch: `dolt checkout -b claim-BEAD-123`
2. Write claim state on that branch
3. Merge back to main: `dolt merge claim-BEAD-123`
4. If merge conflicts (someone else claimed), the merge fails — CAS semantics

This is heavier than a single-transaction approach but gives full auditability (each claim attempt is a commit on a branch). For Phase 1, the single-transaction approach is simpler and sufficient. Branch-level claiming may be useful later for audit trails.

Sources: [Dolt Concurrent Transaction Example](https://www.dolthub.com/blog/2023-12-14-concurrent-transaction-example/), [Dolt Transactions](https://www.dolthub.com/blog/2021-05-19-dolt-transactions/), [Dolt Merges](https://docs.dolthub.com/sql-reference/version-control/merges)

---

## 7. Rideshare Dispatch: Lessons from Uber/Lyft

### 7.1 The Dispatch Race Problem

Uber's DISCO (Dispatch Optimization) system faces the exact same race: multiple available drivers near a rider, all need to see the request, but exactly one must be assigned.

**Uber's approach**: Centralized dispatch with cell-based sharding.
- The map is divided into S2 cells (~3km).
- Each cell is owned by a shard (via consistent hashing with ringpop).
- When a ride request arrives, the cell's shard identifies nearby supply (drivers), ranks them, and **assigns exactly one**. The assignment is a single write on a single shard — no distributed consensus needed.
- If the assigned driver doesn't accept within a timeout (grace period), the shard re-runs matching and assigns the next driver.

**Key insight**: Uber avoids the race entirely by **centralizing the decision per geographic cell**. There is no bidding, no optimistic locking — the shard owner makes an authoritative assignment.

### 7.2 Applicability to Sylveste

Sylveste's "cell" is the bead priority queue. With a single Dolt database (no sharding), the equivalent of Uber's cell-shard is Dolt itself — all claim writes go through one database.

**What Sylveste can borrow from Uber**:
1. **Server-side decision**: Rather than agents independently racing to claim, a lightweight dispatcher (the `sprint-find-active` sweep, or a new `bead-dispatch` command) could assign beads to agents authoritatively. This eliminates races entirely.
2. **Accept timeout**: After assignment, the agent has N seconds to acknowledge (start heartbeating). If it doesn't, the bead is reassigned. This handles the "assigned but agent crashed before starting" case.
3. **No-bid policy**: Agents don't choose their beads — the dispatcher assigns based on priority, capability, and load. This is simpler than CNP bidding and avoids the "every agent grabs the same top-priority bead" stampede.

**Phase 1 recommendation**: Keep optimistic grab-and-validate (simpler, no new daemon). But design the claim key schema and heartbeat protocol so that a centralized dispatcher can be dropped in later without changing the bead state model.

Sources: [Uber System Design](https://www.geeksforgeeks.org/system-design-of-uber-app-uber-system-architecture/), [Uber Architecture](https://medium.com/@narengowda/uber-system-design-8b2bc95e2cfe), [Solving Race Conditions in Booking Systems](https://hackernoon.com/how-to-solve-race-conditions-in-a-booking-system)

---

## 8. Synthesis: Recommended Claiming Protocol for Phase 1

### 8.1 Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Coordination model | **Optimistic grab-and-validate** | No coordinator daemon; Dolt provides natural CAS; <20 agents means low contention |
| Claim atomicity | **Single Dolt transaction** | Merge `bd update --claim` + `bd set-state` into one transaction that writes status, assignee, claimed_by, claimed_at atomically |
| Race protection | **Dolt cell-level conflict detection** | Concurrent claims on same bead conflict on `status` cell; second writer fails |
| Heartbeat interval | **60 seconds** | 10 heartbeats per 10-minute task; low Dolt overhead |
| Stale-claim TTL | **180 seconds** | 3x heartbeat; ~3-4 minute crash detection |
| Claim state schema | **Single compound key** | `claim=<session_id>:<epoch>:<seq>` — atomic, parseable, sweep-friendly |
| Stampede mitigation | **Random jitter 0-500ms** | Spread concurrent claim attempts; negligible latency for 10-min tasks |
| Duplicate protection | **Pre-claim check** | Before starting work, verify `claimed_by` matches own session ID (handles sequential overwrite edge case) |

### 8.2 Claim State Machine

```
        ┌─────────┐
        │  open   │
        └────┬────┘
             │ bd update --claim (atomic: status + claimed_by + claimed_at)
             │ (Dolt CAS: WHERE status='open')
             ▼
     ┌───────────────┐
     │ in_progress   │◄──── heartbeat every 60s (updates claimed_at + seq)
     └───┬───────┬───┘
         │       │
    success    crash/timeout
         │       │
         ▼       ▼
    ┌────────┐ ┌──────────┐
    │ closed │ │ stale    │ (TTL expired, no heartbeat)
    └────────┘ └────┬─────┘
                    │ sweep reclaims → status='open'
                    ▼
              ┌─────────┐
              │  open   │ (ready for re-claim)
              └─────────┘
```

### 8.3 Implementation Checklist (Smallest Viable Fix)

1. **Verify `bd update --claim` has a status precondition** — confirm it checks `WHERE status='open'` before writing. If not, this is the P0 fix. (Check beads source code.)

2. **Merge identity into claim transaction** — modify `bd update --claim` to accept `--claimed-by` and `--claimed-at` flags, or implement a wrapper `bead-claim-atomic` that runs a single Dolt SQL transaction:
   ```bash
   bead-claim-atomic() {
     local bead_id="$1" session_id="$2" epoch="$(date +%s)"
     bd sql "UPDATE beads SET status='in_progress', assignee='$session_id', claimed_by='$session_id', claimed_at='$epoch' WHERE id='$bead_id' AND status='open'"
     local rows_affected=$?
     if [ "$rows_affected" -eq 0 ]; then
       echo "CLAIM_FAILED: bead already claimed" >&2
       return 1
     fi
   }
   ```

3. **Add claim jitter** — in the dispatch loop, sleep `$((RANDOM % 500))ms` before claiming.

4. **Add post-claim verification** — after claiming, re-read the bead and confirm `claimed_by` matches own session ID. This catches the sequential-overwrite edge case.

5. **Heartbeat writes compound key** — `bd set-state "$BEAD_ID" "claim=${SESSION_ID}:$(date +%s):${SEQ}"` with SEQ incrementing each heartbeat.

6. **Stale-claim sweep** — a periodic sweep (every 60s, run by sprint-find-active or a dedicated sweeper) that:
   ```bash
   # Find beads where: status=in_progress AND (no claim key OR claim epoch + 180s < now)
   # Reset: status=open, clear assignee/claimed_by/claimed_at
   ```

### 8.4 What This Does NOT Cover

- **Trigger and idle detection**: When agents decide to look for work (covered by fd-trigger-and-idle-detection)
- **Priority and matching**: Which bead an agent selects from the backlog (covered by fd-backlog-priority-and-matching)
- **Post-claim failure recovery**: What happens to in-flight work when an agent dies mid-task (covered by fd-failure-recovery-and-zombies)
- **Centralized dispatch**: A coordinator that assigns beads to agents. This is a Phase 2 optimization if stampedes become a problem at scale.

---

## 9. Open Questions

1. **Does `bd update --claim` include a `WHERE status='open'` precondition?** If yes, Dolt already provides CAS for free. If no, this is the single most important fix. Needs source code verification.

2. **Can `bd` expose raw SQL execution for atomic compound writes?** The wrapper approach in 8.3 assumes `bd sql` or equivalent exists. If not, the atomic claim must be implemented inside `bd` itself.

3. **Should stale-claim sweep be pull-based (periodic) or push-based (heartbeat watcher)?** Pull (periodic sweep) is simpler and fits the existing `sprint-find-active` pattern. Push (a watcher that fires on missed heartbeat) is more responsive but requires a new daemon.

4. **What happens if Dolt itself is unavailable during a claim attempt?** The agent should back off and retry, not fall through to an unclaimed state. The retry policy needs specification (exponential backoff with jitter, max 3 retries, then give up and re-enter idle loop).

<!-- flux-research:complete -->
