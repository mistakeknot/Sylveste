# Phase 1 Self-Dispatch: Research Synthesis

**Synthesis Date:** 2026-03-19
**Research Question:** How should AI agents in a software factory autonomously pull work from a prioritized backlog? Specifically: trigger mechanisms, claiming protocols, bead selection, failure recovery, and feedback loops for Phase 1 of a self-dispatching loop.

**Agents Used:** 5 research outputs
**Depth:** Standard
**Sources:** 18 total (12 external, 6 internal)

---

## Executive Summary

Sylveste has the foundation to implement a **self-dispatching loop in Phase 1** using existing infrastructure (Dolt-backed beads, intermux watcher, Clavain heartbeat). The key architectural decision is **optimistic grab-and-validate claiming** (no central coordinator) combined with **event-driven trigger via Stop hook** (not timer-based polling). The system requires three small changes to Dolt atomicity, two new state schema fields, and a 200-line watchdog sweep for failure recovery.

**Critical finding:** The current non-atomic claim (separate `bd update --claim` + `bd set-state`) has a crash window where beads are marked claimed but identity-not-written, leaving them zombied. This must be fixed first — it's the single highest-priority change.

---

## Recommended End-to-End Architecture

### Layer 1: Trigger (When to Pull)

**Primary: Event-driven Stop hook** (fires after each Claude response)
- Checks for `dispatch_signal` file (written by PostToolUse when bead closes)
- Confirms agent has been idle for ≥1 consecutive Stop invocation
- Includes circuit breaker: max 3 consecutive blocks before approve
- Latency: <1 second
- **Why:** Maps to game engine work-stealing (Unity, Unreal) and TPS kanban pull signals. No polling overhead.

**Fallback: Intermux watcher confirmation** (10-second scan)
- Validates that pane content shows idle status (prompt visible)
- Detects if Stop hook is wrong about agent state
- Stuck detection (5-minute no-output threshold)
- **Role:** Health monitoring and validation, not primary trigger

**Cooldown:** 20s idle confirmation (2 consecutive watcher scans) to distinguish inter-tool pause from true idle

### Layer 2: Selection (Which Bead)

**Algorithm: Capability-matching with lane affinity**

1. **Filter:** `bd list --status=open`
   - Exclude claimed beads (check `claimed_by` != "released" AND `claimed_at` < 180s ago)
   - Apply `DISCOVERY_LANE` if set; escape to global pool if empty
   - Exclude beads where `attempt_count >= 3` (already quarantined)
   - Global WIP check: skip if `in_progress_count >= DISCOVERY_MAX_WIP` (default: agent_count + 2)

2. **Score:** Multi-factor [0-100] additive
   - Priority (0-60): P0/P1/P2/P3 with 12-point gaps
   - Phase (0-30): Earlier phases (closer to done) score higher
   - Recency (0-20): Recently-touched beads are context-warm
   - Deps-ready (0-12): Bonus for beads with ≥80% dependencies closed
   - Penalties: -50 claimed, -30 parent-closed, -15 interject, -10 stale
   - **Perturbation (NEW):** Add ±5 random jitter to break ties and prevent herd behavior

3. **Rank:** Sort DESC by score; deterministic tiebreaker by ID

4. **Select:** Top-1 for autonomous mode; present top-3 for interactive

**Why this design:**
- **No inter-agent communication** — each agent independently scans and scores
- **Capability-matching is production-proven** (Kubernetes, Nomad) at scale
- **Score perturbation + startup jitter + claim-failure jitter** approximate batch matching without a coordinator
- **Lane affinity + escape** balances specialization with flexibility

### Layer 3: Claiming (Atomic Acquisition)

**Current problem:** Two-phase non-atomic write (bd update --claim, then bd set-state) has a crash window.

**Proposed fix:** Single Dolt transaction
```sql
UPDATE beads SET
  status='in_progress',
  assignee='<session_id>',
  claimed_by='<session_id>',
  claimed_at=<epoch>
WHERE id='<bead_id>' AND status='open'
-- Dolt cell-level conflict detection ensures only one succeeds
```

**Implementation path (smallest viable fix):**
1. Verify `bd update --claim` includes `WHERE status='open'` precondition (likely yes; check source)
2. If yes: wrap the claim in `bd sql` or create `bead-claim-atomic` that runs single transaction
3. If no: add the precondition to `bd update --claim` source
4. Add post-claim verification: re-read bead and confirm `claimed_by` matches own session ID

**Race protection:** Dolt's cell-level conflict detection on the `status` field. If two agents write concurrently:
- Both read `status='open'`
- Both attempt to write `status='in_progress'`
- Dolt merge detects conflict on same cell → second writer fails
- Second writer catches the failure and retries from Layer 2

**Jitter before claim:** Random 0-500ms to spread stampedes across concurrent agents

### Layer 4: Heartbeat & Liveness

**Interval:** 60 seconds (explicit, piggybacked on existing sprint-budget checks)

**What's written:** Single compound state key
```bash
bd set-state "$BEAD_ID" "claim=${SESSION_ID}:$(date +%s):${SEQ}"
```
Format: `<session_id>:<epoch>:<sequence>` enables sweep to detect:
- Zombie: epoch + TTL < now
- Orphan: status=in_progress but no claim key
- Stolen: claim session ≠ assignee (race artifact)

**Stale-claim TTL:** 600 seconds (10 minutes)
- Current: 2700s (45min) — too long for automated recovery
- Recommended: 10x heartbeat interval (industry std: Airflow 5min, Temporal 30-60s)
- Tolerates 10 consecutive missed heartbeats
- Worst-case crash detection: ~3.5 minutes from crash to reclaim

**Explicit staleness check:** Watchdog sweep (new) runs every 60s:
```
for each in_progress bead:
  age = now - claimed_at
  if age > 600s:
    check intermux status
    if pane=active+output: refresh heartbeat (false positive)
    if pane=crashed/dead: unclaim + re-queue
```

### Layer 5: Failure Recovery & Escalation

**Three failure classes with different actions:**

1. **Retriable** (agent crash, transient timeout)
   - Action: Unclaim, re-queue, `attempt_count += 1`
   - Auto-retry up to 3 times
   - Trigger: intermux `StatusCrashed` OR stale heartbeat + pane dead

2. **Spec-blocked** (ambiguous bead, missing context, conflicting requirements)
   - Action: Set `status=blocked`, label `needs-human`, `failure_class=spec_blocked`
   - No auto-retry
   - Trigger: 2+ failed attempts with no commits, OR agent error message contains "ambiguous"

3. **Env-blocked** (git auth, Dolt zombie, disk full)
   - Action: Set `status=blocked`, label `needs-infra`, pause factory
   - Escalate to human
   - Trigger: 2+ failures within 120s (correlated), OR error matches /auth|Dolt|ENOSPC/

**Disruption budget** (Kubernetes PDB analog):
- Max 2 simultaneous unclaims per patrol cycle
- Min 1 agent always working
- If >2 failures in 120s: classify as env_blocked, pause dispatch, escalate

**Circuit breaker (andon cord):**
- 3 consecutive failures on different beads → pause factory + tier demotion
- >15% failure rate (rolling 24h) → demotion
- Budget overshoot (>120% daily) → demotion

### Layer 6: Feedback Loops

**Six feedback loops with different sample rates:**

| Loop | Sample Rate | Signal | Control Action |
|------|------------|--------|-----------------|
| 1. PI Concurrency | 60s | Queue depth vs. agents | Spawn/drain tmux sessions |
| 2. Takt Time | 60s | Arrival rate vs. completion rate | Adjust PI controller setpoint |
| 3. Workflow Health | 5m | Time-to-claim, cycle-time, close-rate | Alert thresholds |
| 4. Utility Scoring | On-close | Predicted complexity vs. actual cost | Update route.md tier thresholds via EMA |
| 5. Fleet Utilization | 60s | Active/idle ratio, demand ratio | Override PI limits |
| 6. Per-Bead Aggregates | Daily | Claim attempts, idle duration, retry rate | Diagnose systemic issues (backlog hygiene) |

**PI Controller tuning (initial):**
- Kp = 0.5 (spawn 0.5 agents per excess bead)
- Ki = 0.05 (slow integral correction)
- Target queue depth = ~2-3 beads
- Anti-windup clamp when hitting min/max agent limits

---

## Implementation Sequence: What to Build First

### Phase 1a: Foundation (Week 1 — Critical Path)

**P0: Fix claim atomicity**
1. Verify `bd update --claim` has `WHERE status='open'` precondition
2. Implement atomic claim in single Dolt transaction
3. Add post-claim verification (re-read bead, confirm `claimed_by`)
4. Test with concurrent claim attempts (5 agents, 3 beads)
- **Effort:** 2-4 hours (code review + test)
- **Risk:** High — incorrect implementation leaves zombies
- **Blocker:** Nothing else works without this

**P1: Add heartbeat state schema**
1. Add `claim` compound state key (replacing separate `claimed_by` + `claimed_at`)
2. Modify `clavain-cli bead-heartbeat` to write compound key with sequence number
3. Update claim check logic to parse new format
4. Backfill existing in-progress beads with default claim state
- **Effort:** 1 hour
- **Blocker:** Watchdog sweep won't work without this

**P2: Watchdog sweep (automatic failure recovery)**
1. Create `watchdog_sweep()` function (200 lines bash/Go)
2. Runs every 60s from sprint-find-active or dedicated process
3. Detects stale, orphan, and stolen claims
4. Unclaims dead agents; refreshes false positives
5. Writes `failure_class` and `attempt_count` to bead state
- **Effort:** 4-6 hours
- **Integration:** Intermux OnStatusChange hook or standalone
- **Value:** Enables automatic recovery without human intervention

### Phase 1b: Trigger & Selection (Week 1-2)

**P3: Stop hook self-dispatch**
1. Create `stop_hook_dispatch.sh` that checks for next-work signals
2. Write PostToolUse hook to set `/tmp/flux-dispatch-signal-<session>.json` on bead close
3. Stop hook reads signal, checks `bd list --status=open --limit=1`, confirms idle
4. Returns `{"decision": "block", "reason": "Next: <bead_id>: <title>"}` if queue has work
5. Implement circuit breaker (max 3 consecutive blocks before approve)
- **Effort:** 3-4 hours
- **Integration:** Plugin hook in hooks.json
- **Value:** Eliminates timer polling for work-pull

**P4: Selection algorithm improvements**
1. Add score perturbation (±5 jitter) to `score_bead()` in lib-discovery.sh
2. Add startup jitter in session-start.sh (0-3s delay before first discovery)
3. Add claim-failure jitter (0.5-2.5s before retry)
4. Add global WIP check before claiming
5. Add lane-escape fallback (query global pool if lane empty)
- **Effort:** 1 hour (small, mostly configuration)
- **Value:** Reduces thundering herd collisions from O(n) to O(1) attempts

### Phase 1c: Feedback Loops (Week 2)

**P5: Takt time dashboard**
1. Shell script reading `bd stats` + fleet-registry
2. Computes arrival rate, completion rate, cycle time
3. Displays as human-readable dashboard (JSON + text)
4. Optional: Send to Slack/monitoring every hour
- **Effort:** 30 minutes
- **Value:** Human visibility into factory throughput

**P6: PI controller (agent concurrency)**
1. 60-second loop reading intermux + `bd list`
2. Implements PI control law with anti-windup
3. Spawns/drains tmux sessions based on queue depth
4. Writes decisions to log for debugging
- **Effort:** 3-4 hours
- **Integration:** New mycroft module or standalone daemon
- **Value:** Elastic agent scaling based on backlog

---

## What Exists Today vs. What Needs to Be Built

### Already Implemented ✓

| Component | Status | Location | Notes |
|-----------|--------|----------|-------|
| Bead model (status, priority, phase) | Complete | .beads/ schema | Dolt-backed; has all fields |
| Atomic claiming (via Dolt) | **Partial** | os/Clavain/claim.go | Non-atomic 2-phase; needs fix |
| Heartbeat write | Complete | claim.go line 287 | Writes `claimed_at`; missing state schema |
| Stale claim detection | Complete | claim.go line 22 | `isClaimStale()` checks 2700s |
| Intermux watcher | Complete | intermux/monitor.go | 10s scan; detects stuck/crashed |
| PostToolUse hook | Exists | hooks.json | Async, non-blocking; can write signal files |
| Stop hook | Exists | hooks.json | Blocking available; circuit breaker needed |
| Discovery scoring | Complete | lib-discovery.sh | Base algorithm; needs perturbation + lane-escape |
| Heartbeat piggybacking | Complete | sprint-budget checks | ~60s cadence; explicit now |

### Needs to Be Built 🔨

| Component | Effort | Priority | Blocker |
|-----------|--------|----------|---------|
| Atomic claim transaction | 2-4h | P0 | Yes — everything depends on this |
| Compound claim state key | 1h | P1 | Watchdog won't work without |
| Watchdog sweep | 4-6h | P2 | Automatic failure recovery |
| Stop hook dispatch script | 3-4h | P3 | Primary trigger mechanism |
| Score perturbation + jitter | 1h | P4 | Thundering herd mitigation |
| Takt time dashboard | 0.5h | P5 | Human visibility (nice-to-have) |
| PI controller | 3-4h | P6 | Elastic scaling (Phase 1.5) |

---

## Key Parameters (Phase 1 Baseline)

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| **Heartbeat Interval** | 60s | Explicit, same cadence as sprint-budget checks. Dolt transaction overhead ~100ms. |
| **Stale-Claim TTL** | 600s (10min) | 10x heartbeat interval. Tolerates 10 missed heartbeats. Detect crash in ~3.5min. |
| **Grace Period** | 30s | Before reclaiming after TTL expires, check intermux once more (false positive check). |
| **Max Task Duration** | 30min | Safety valve — any bead claimed >30m is force-released regardless of heartbeats. |
| **Score Perturbation** | ±5 points | Breaks ties, prevents herd. Preserves priority ordering (P0 won't lose to P3). |
| **Startup Jitter** | 0-3s | Full jitter (uniform random) spreads concurrent agent starts. |
| **Claim-Failure Jitter** | 0.5-2.5s | Staggers retries. Prevents synchronized retry storms. |
| **Idle Confirmation** | 20s (2 scans) | Distinguish inter-tool pause (rarely >20s) from true idle. |
| **Global WIP Limit** | agent_count + 2 | Buffer for stale claims. Prevent overload. Default: if 3 agents, max 5 in-progress. |
| **Max Retry Attempts** | 3 | After 3 failures, bead is quarantined (spec or env problem). Matches Temporal convention. |
| **Disruption Budget Max** | 2 unclaims/cycle | Prevent cascading failure amplification. If >2 fail, classify as env_blocked. |
| **Circuit Breaker Trigger** | 3 consecutive failures | Pause factory; tier demotion; escalate to human. |
| **Failure Rate Alert** | >15% (24h rolling) | Demote tier; investigate root cause. |

---

## Top 5 Actionable Recommendations

### 1. Fix Atomic Claiming (P0 — Do First)

**What:** Merge `bd update --claim` + `bd set-state` into single Dolt transaction.

**Why:** Current non-atomic approach creates a crash window where beads are marked claimed but identity-not-written, leaving them zombied. This is the single highest-severity bug in the self-dispatch system.

**How:**
- Check if `bd update --claim` already includes `WHERE status='open'` precondition
- If yes: wrap in single transaction that also writes `claimed_by` + `claimed_at` atomically
- If no: add the precondition to `bd update --claim` source code
- Test with 5 concurrent agents racing to claim the same bead (verify only 1 succeeds)

**Acceptance Criteria:**
- Concurrent claim attempts fail safely (second writer gets merge conflict)
- Post-claim verification succeeds (re-read confirms `claimed_by` matches own session ID)
- Zombies no longer occur (watchdog finds no beads with status=in_progress but no claim key)

**Effort:** 2-4 hours

---

### 2. Implement Stop Hook Dispatch (Primary Trigger)

**What:** Wire Stop hook to pull next bead from queue.

**Why:** Event-driven trigger (Stop hook after each response) has <1s latency, no polling overhead, and maps to proven patterns (game engines, TPS). This is dramatically better than timer-based polling.

**How:**
1. Create `stop_hook_dispatch.sh` that:
   - Checks `/tmp/flux-dispatch-signal-<session>.json` for "bead closed" signal (written by PostToolUse)
   - Verifies agent has been idle ≥1 Stop invocation (via timestamp file)
   - Queries `bd list --status=open --limit=1`
   - Implements circuit breaker: if last 3 Stops all blocked, approve (break loop)
2. Return `{"decision": "block", "reason": "Next: <bead_id>: <title>"}` if work available
3. Return `{"decision": "approve"}` otherwise

**Acceptance Criteria:**
- Stop hook fires after each Claude response
- Blocking behavior correctly injects next-work reason into Claude context
- Circuit breaker prevents infinite loops (max 3 consecutive blocks)
- No spurious blocks during inter-tool pauses (20s idle confirmation via watcher)

**Effort:** 3-4 hours

---

### 3. Implement Watchdog Sweep (Automatic Failure Recovery)

**What:** 60-second daemon that detects stale/crashed agents and auto-unclaims their beads.

**Why:** Automatic detection + recovery means the factory self-heals without human intervention. Required for unattended autonomous operation.

**How:**
1. Every 60s, scan `in_progress` beads
2. For each bead:
   - Check age = now - claimed_at
   - If age < 600s: healthy, skip
   - If age > 600s: cross-reference with intermux
     - If intermux says "active" + recent output: refresh heartbeat (false positive)
     - If intermux says "crashed" or PID dead: unclaim + classify "retriable" + re-queue
     - If intermux says "stuck" (no output >5min): wait until stale TTL, then unclaim

3. Write bead state: `failure_class`, `attempt_count`, `last_failure_at`

**Acceptance Criteria:**
- Stale beads are detected within 120s of crash
- False positives (active agent) are avoided (intermux cross-reference)
- Retriable failures auto-retry up to 3 times
- Spec/env-blocked failures are quarantined (status=blocked, label:needs-human)
- No double-unclaim if intermux also detected crash

**Effort:** 4-6 hours

---

### 4. Add Score Perturbation & Jitter (Thundering Herd Mitigation)

**What:** Small randomization to break ties and spread concurrent claim attempts.

**Why:** With 5+ concurrent agents, all see the same top-ranked beads and all race for #1. Score perturbation + startup jitter reduces failed claims from O(n²) to O(1) per discovery cycle.

**How:**
1. In `score_bead()`, add jitter: `score = score + (RANDOM % 11 - 5)` (±5 points)
2. In session-start.sh, add jitter: `sleep 0.$((RANDOM % 3000))` (0-3s)
3. In bead_claim() retry loop, add jitter: `sleep 0.$((RANDOM % 2000 + 500))` (0.5-2.5s)

**Acceptance Criteria:**
- Score perturbation preserves priority ordering (P0 never loses to P3)
- Near-ties (within ±5 points) are selected with roughly equal probability
- Startup jitter staggers concurrent agent scans
- Failed claim retry is not synchronized (agents don't all retry at same time)

**Effort:** 1 hour

---

### 5. Implement PI Controller for Agent Concurrency (Elastic Scaling)

**What:** 60-second feedback loop that spawns/drains agents based on queue depth.

**Why:** Self-regulating concurrency. Too few agents = starvation (beads wait). Too many = waste (idle agents burn tokens). PI control holds queue depth at a setpoint with zero steady-state error.

**How:**
1. Every 60s:
   ```
   queue_depth = bd list --status=open | wc -l
   active_agents = intermux list | jq '[.[] | select(.status=="active")] | length'
   error = queue_depth - target_queue_depth
   integral = integral + error * 0.05  (Ki = 0.05)
   integral = clamp(integral, -10, 10)  (anti-windup)
   desired = base_agents + 0.5 * error + integral  (Kp = 0.5)
   desired = clamp(desired, min_agents, max_agents)
   if desired > active: spawn (desired - active) agents
   if desired < active: drain (mark agents for self-termination)
   ```

2. Integration point: Standalone daemon or mycroft module
3. Override: Fleet utilization monitor can suppress spawning if utilization < 50% (surplus)

**Acceptance Criteria:**
- Queue depth converges to target within 300s (5 minutes)
- Agents are spawned only when needed (queue depth > target)
- Agents are drained gracefully (finish current bead, don't claim new ones)
- Anti-windup prevents overshoot when hitting min/max limits
- Telemetry shows queue oscillation amplitude < 2 beads around target

**Effort:** 3-4 hours

---

## What's Not Covered (Phase 2+)

- **Centralized dispatcher:** When fleet grows beyond ~20 agents, introduce a lightweight coordinator to batch-assign beads (avoids stampede entirely). Current optimistic approach is sufficient at current scale.
- **Agent capability profiles:** Agents declaring skills (e.g., "good at Go code") to influence scoring. Requires per-agent config + weight tuning.
- **Predictive demand forecasting:** Like Lyft's approach, anticipate which beads will become urgent based on deadlines. Requires time-series modeling.
- **Batch dependency queries:** If bd supports `bd dep list-all --status=open`, enable fast dependency-readiness scoring without N+1 queries.
- **EMA utility scoring:** Learning from completed work to auto-tune complexity classification thresholds. Requires cost-tracking per bead.

---

## Risk Mitigation

### High Risk: Atomic Claim Implementation

**Risk:** Incorrect Dolt transaction logic leaves race window open; two agents claim same bead.

**Mitigation:**
- Write comprehensive unit test: 5 concurrent agents, 3 beads, verify only 3 succeeds
- Read `bd` source code (GitHub) before implementing
- Test with `bd sql` directly to understand Dolt's transaction semantics
- Add post-claim verification (re-read bead) to catch any slips

### Medium Risk: Stop Hook Infinite Loop

**Risk:** Stop hook blocks on every turn (checks queue, finds work, blocks again), trapping Claude in loop.

**Mitigation:**
- Circuit breaker: max 3 consecutive blocks before approve
- Test with small queue (2-3 beads) and manual closure
- Log all Stop hook decisions to /tmp/ for debugging
- Have fallback manual approval command

### Medium Risk: Watchdog False Positives

**Risk:** Watchdog unclaims a legitimately working agent (network glitch, long pause).

**Mitigation:**
- Cross-reference with intermux before unclaiming (don't unclaim if pane shows recent output)
- Grace period: check once more 30s after TTL before unclaiming
- Only unclaim if BOTH heartbeat stale AND intermux confirms dead/stuck

### Low Risk: PI Controller Oscillation

**Risk:** Tuning Kp/Ki incorrectly causes queue depth to oscillate wildly.

**Mitigation:**
- Start conservative: Kp=0.5, Ki=0.05
- Anti-windup clamp on integral term
- Observation window: let system stabilize for 5 minutes before adjusting tuning
- Ziegler-Nichols method available for Phase 2 auto-tuning

---

## Success Criteria

A successful Phase 1 self-dispatch loop should:

1. **Autonomy:** Agents claim and execute beads without human work-selection
2. **Latency:** Work-pull latency <5 seconds (from idle detection to next bead start)
3. **Correctness:** No double-assignment of beads (race window closed)
4. **Recovery:** Crashed agents auto-unclaimed within 10 minutes; bead re-queued
5. **Transparency:** Takt time dashboard shows throughput and cycle time
6. **Cost-effective:** PI controller keeps agent count near optimal (no persistent surplus or starvation)

### Metrics to Track

- **Time-to-claim:** Distribution of time from bead creation to claimed_at. Target: p50 < 30s, p95 < 5m
- **Cycle time:** Distribution of closed - created. Target: p50 < 20min, p95 < 60min
- **Close rate:** % of claimed beads that close vs. cancel/stale. Target: >85%
- **Retry rate:** % of beads reopened after close. Target: <10%
- **WIP:** In-progress bead count. Target: stay within [N-2, N+2] where N = agent count
- **Queue depth:** Open beads. Target: ≤3 (not starving agents, not overwhelming)
- **Agent utilization:** Active / (active + idle). Target: 70-90%

---

## References

### Claiming & Atomicity
- [Kubernetes Leases](https://kubernetes.io/docs/concepts/architecture/leases/) — optimistic locking via resourceVersion
- [Dolt Concurrent Transactions](https://www.dolthub.com/blog/2023-12-14-concurrent-transaction-example/)
- [Celery Task Claiming](https://docs.celeryq.dev/en/stable/userguide/tasks.html)
- [Temporal Task Token Leasing](https://temporal.io/blog/activity-timeouts)

### Trigger Mechanisms
- [KEDA Scaling](https://github.com/kedacore/keda-docs) — event-driven with cooldown periods
- [Toyota TPS Kanban](https://en.wikipedia.org/wiki/Kanban) — pull signals, not push
- [Game AI Job Systems](https://docs.unity3d.com/Manual/job-system.html) — work-stealing, completion-driven triggers

### Selection & Scoring
- [Kubernetes Scheduling Framework](https://kubernetes.io/docs/concepts/scheduling-eviction/scheduling-framework/)
- [Nomad Job Ranking](https://developer.hashicorp.com/nomad/docs/concepts/scheduling/how-scheduling-works)
- [Lottery Scheduling](https://en.wikipedia.org/wiki/Lottery_scheduling) — weighted random selection

### Failure Recovery
- [Temporal Retry Policies](https://docs.temporal.io/encyclopedia/retry-policies)
- [Apache Airflow Zombie Tasks](https://medium.com/@shakik19/troubleshooting-zombie-task-job-errors-in-apache-airflow-5527303dbcad)
- [Kubernetes Pod Disruption Budgets](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/)
- [Toyota Andon Cord](https://itrevolution.com/articles/kata/) — stop-the-line principle

### Feedback Loops & Control
- [Control Theory: PI Controllers](https://apmonitor.com/pdc/index.php/Main/ProportionalIntegralControl)
- [Little's Law in Kanban](https://kanbanzone.com/resources/lean/littles-law/)
- [Takt Time Fundamentals](https://www.creativesafetysupply.com/glossary/takt-time/)
- [Temporal Workflow Metrics](https://docs.temporal.io/develop/worker-performance)
- [Game AI Utility Theory](http://www.gameaipro.com/GameAIPro/GameAIPro_Chapter09_An_Introduction_to_Utility_Theory.pdf)

---

## Appendix: Existing Infrastructure Inventory

| Component | Status | Confidence |
|-----------|--------|-----------|
| Beads Dolt schema (status, priority, phase, etc.) | Complete | High |
| `bd update --claim` command | Exists | Medium (needs atomicity check) |
| `bd set-state` key-value store | Complete | High |
| `clavain-cli bead-heartbeat` | Complete | High |
| Intermux health monitor (status enum) | Complete | High |
| Intermux OnStatusChange hook | Exists but unwired | Medium |
| PostToolUse hook | Exists | High |
| Stop hook | Exists | High |
| lib-discovery.sh score_bead() | Complete | High |
| interstat token cost tracking | Complete | High |
| fleet-registry.yaml agent profiles | Complete | High |
| sprint-find-active patrol loop (planned) | Planned | Low |
| Mycroft fleet orchestrator (planned) | Planned | Low |

---

**Document Status:** Research synthesis complete. Ready for Phase 1 implementation planning.

**Next Steps:**
1. Verify atomic claim implementation (P0)
2. Plan watchdog sweep integration (P1-P2)
3. Create Stop hook dispatch script (P3)
4. Schedule implementation sprints (week-by-week breakdown)
