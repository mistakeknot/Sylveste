# Failure Recovery and Zombie Detection for Phase 1 Self-Dispatch

**Reviewer perspective:** SRE debugging distributed systems failures, writing runbooks for partial-failure recovery.
**Scope:** How the factory detects and recovers from stuck, crashed, or abandoned work items.
**Existing system:** Beads (Dolt-backed) with `bd update --claim` / `bd set-state`, agents in tmux panes via intermux, heartbeat via `clavain-cli bead-heartbeat`, mycroft fleet orchestrator (planned).

---

## 1. Temporal Saga Compensation and Retry Policies

### The Problem

When an agent claims a bead, starts work, and then fails partway through, the system must decide: retry the whole thing, compensate (undo partial work), or escalate. The current system has no compensation logic — a failed agent leaves behind a claimed bead with uncommitted changes in a tmux pane.

### External Pattern: Temporal's Failure Taxonomy

Temporal classifies failures into a strict hierarchy that maps well to the factory:

| Temporal Concept | Factory Equivalent | Behavior |
|---|---|---|
| **Application Failure (non-retryable)** | Bad spec / ambiguous bead description | Stop retrying, escalate to human. The bead itself is the problem. |
| **Application Failure (retryable)** | Agent logic error, wrong approach | Retry with same or different agent. The spec is fine, execution was wrong. |
| **Activity Timeout (Start-to-Close)** | Agent stuck — no output for >StuckTimeout | Kill and reassign. Agent took too long on a single step. |
| **Activity Timeout (Schedule-to-Close)** | Bead TTL exceeded | The whole task exceeded its time budget. Reassign or escalate. |
| **Worker Crash** | tmux pane died, process OOM-killed | Safe to retry — no ambiguity about the spec. |

**Key Temporal principle:** Activities do not surface failures to the workflow until a non-retryable condition is met. This means the retry policy absorbs transient failures silently. The workflow only sees "this activity failed permanently." This is the correct model for the factory — intermux/mycroft should absorb transient agent restarts and only surface persistent failures.

**Temporal retry policy parameters applicable to factory beads:**

- `InitialInterval`: Wait before first retry. Factory: 30s (let the tmux session fully die before respawning).
- `BackoffCoefficient`: Exponential backoff multiplier. Factory: 2.0 (30s → 60s → 120s).
- `MaximumAttempts`: Hard cap on retries before terminal failure. Factory: 3 (matches mycroft's consecutive-failure demotion trigger).
- `NonRetryableErrorTypes`: Errors that should never be retried. Factory: `spec_ambiguous`, `dependency_missing`, `environment_broken`.

### Recommendation for Sylveste

Add a `failure_class` field to bead state (via `bd set-state`) with three values:

```
retriable       — agent crash, timeout, transient env issue. Safe for auto-retry.
spec_blocked    — ambiguous spec, missing context, conflicting requirements. Needs human.
env_blocked     — infra broken (git auth, Dolt zombie, disk full). Needs SRE/infra fix.
```

The compensation action differs by class:

| Failure Class | Compensation | Who Acts |
|---|---|---|
| `retriable` | Unclaim bead, reset `claimed_by=released`, re-enter dispatch queue | Watchdog (automatic) |
| `spec_blocked` | Unclaim bead, set `status=blocked`, add `label:needs-human` | Watchdog sets status; human triages |
| `env_blocked` | Unclaim bead, set `status=blocked`, add `label:needs-infra` | Watchdog sets status; pause further dispatch until env check passes |

**Concrete integration point:** `clavain-cli bead-release` (in `/home/mk/projects/Sylveste/os/Clavain/cmd/clavain-cli/claim.go` line 253) currently just sets `claimed_by=released`. It should accept an optional `--failure-class=<class>` argument that writes the classification to bead state alongside the release.

---

## 2. Intermux Health Monitor: State Transitions for Automatic Unclaim

### Current State

Intermux already has a health monitor (`/home/mk/projects/Sylveste/interverse/intermux/internal/health/monitor.go`) that detects stuck agents:

- **Check interval:** 30 seconds (`MonitorConfig.Interval`)
- **Stuck threshold:** 5 minutes (`MonitorConfig.StuckTimeout`)
- **Status enum:** `active`, `idle`, `stuck`, `crashed`, `unknown` (in `/home/mk/projects/Sylveste/interverse/intermux/internal/activity/models.go`)
- **Callback:** `OnStatusChange func(session string, old, new AgentStatus)` — fires when status transitions

The monitor detects `active → stuck` but does **not** trigger bead unclaim. The `OnStatusChange` callback exists but is not wired to any bead release logic.

### Missing State Transitions

The following transitions are needed for automatic recovery:

```
                    ┌──────────────┐
                    │   active     │
                    └──────┬───────┘
                           │ no output > 5min
                           ▼
                    ┌──────────────┐
             ┌──────│    stuck     │──────┐
             │      └──────────────┘      │
             │ output resumes             │ no recovery > StaleClaimTTL
             ▼                            ▼
      ┌──────────────┐           ┌───────────────────┐
      │   active     │           │  abandoned (NEW)   │
      └──────────────┘           └────────┬──────────┘
                                          │ auto-unclaim bead
                                          ▼
                                 ┌───────────────────┐
                                 │  dispatch queue    │
                                 └───────────────────┘

      Process dies (PID check fails):
      ┌──────────────┐
      │   active     │──── PID gone ────▶ ┌──────────────┐
      └──────────────┘                     │   crashed    │
                                           └──────┬───────┘
                                                  │ immediate unclaim
                                                  ▼
                                         ┌───────────────────┐
                                         │  dispatch queue    │
                                         └───────────────────┘
```

**New status: `abandoned`.** Currently, `stuck` is the terminal detection state. But `stuck` should be recoverable (the agent might resume). A new `abandoned` status represents "stuck AND exceeded stale-claim TTL." This triggers automatic unclaim.

### Concrete Changes Needed

1. **Wire `OnStatusChange` to bead release** in `/home/mk/projects/Sylveste/interverse/intermux/cmd/intermux-mcp/main.go`. When status transitions to `crashed`, call `clavain-cli bead-release <bead_id> --failure-class=retriable`.

2. **Add `abandoned` status** to `/home/mk/projects/Sylveste/interverse/intermux/internal/activity/models.go`. Transition: `stuck` for longer than `StaleClaimTTL` (see Section 4) → `abandoned`.

3. **Add bead correlation to health monitor.** The monitor currently tracks tmux sessions, not bead IDs. It needs the mapping: tmux session → bead ID. This mapping already exists via `/tmp/intermux-mapping-*.json` files (noted in intermux CLAUDE.md). The monitor should read these to know which bead to unclaim when an agent fails.

4. **Guard against double-unclaim.** If intermux detects a crash AND the patrol loop also detects a stale claim, both will try to unclaim. The `cmdBeadRelease` function in claim.go (line 275) already has an ownership check — only releases if we own the claim. This is safe. But the patrol loop should skip beads that intermux already released (check `claimed_by == "released"` before acting).

---

## 3. Cascading Failure Protection (Pod Disruption Budget Analog)

### The Problem

If a shared resource fails (git auth, Dolt server, network), multiple agents fail simultaneously. Without protection, the system would:
1. Detect N stuck/crashed agents
2. Unclaim N beads simultaneously
3. Attempt to re-dispatch N beads simultaneously
4. All N re-dispatches fail (same root cause)
5. Each failure counts toward the circuit breaker
6. Circuit breaker trips, demoting mycroft from T2 → T1 or T1 → T0
7. Human must manually investigate and re-promote

This is cascading failure amplification — a single infrastructure problem triggers N failure events and a tier demotion that takes significant effort to recover from.

### Kubernetes PDB Adaptation

Kubernetes Pod Disruption Budgets limit how many pods can be simultaneously disrupted. The factory needs an analogous constraint:

**Factory Disruption Budget:**

```yaml
# .autarch/mycroft/config.yaml
disruption_budget:
  max_simultaneous_unclaims: 2        # Never unclaim more than 2 beads in one patrol cycle
  min_healthy_agents: 1               # Always keep at least 1 agent working (don't drain the fleet)
  correlated_failure_window: 120s     # If >2 failures within 120s, treat as correlated (infra issue)
  correlated_failure_action: pause    # Pause dispatch instead of retry-storm
```

**Correlated failure detection heuristic:** If more than `max_simultaneous_unclaims` agents fail within `correlated_failure_window`, classify the failures as `env_blocked` (not `retriable`), pause all dispatch, and escalate to human. This prevents retry storms.

### Implementation Sketch

In the mycroft patrol loop (planned in `/home/mk/projects/Sylveste/apps/Autarch/internal/mycroft/`):

```
patrol_cycle():
  failures_this_cycle = detect_failures()

  if len(failures_this_cycle) > disruption_budget.max_simultaneous_unclaims:
    # Correlated failure — don't retry, escalate
    for each failure: classify(failure, "env_blocked")
    mycroft.pause(reason="correlated failure: {len} agents failed within {window}")
    return

  # Normal path — process up to max_simultaneous_unclaims
  for failure in failures_this_cycle[:max_simultaneous_unclaims]:
    unclaim_and_requeue(failure)
```

**Key insight from PDB design:** The budget is about limiting the blast radius of recovery actions, not preventing failures. Failures happen; the budget prevents the recovery mechanism from making things worse.

---

## 4. Heartbeat-Based Liveness: Stale-Claim TTL

### Current Implementation

The heartbeat system is already implemented:

- **`clavain-cli bead-heartbeat <bead_id>`** refreshes `claimed_at` timestamp (`/home/mk/projects/Sylveste/os/Clavain/cmd/clavain-cli/claim.go` line 287).
- **Stale threshold:** 2700 seconds (45 minutes), defined as `beadClaimStaleSeconds` (claim.go line 13).
- **Staleness check:** `isClaimStale()` returns true if `age > 2700s` (claim.go line 22).
- **Heartbeat piggybacked on:** `sprint-budget-remaining` calls (per MEMORY.md).

### Analysis: Is 45 Minutes Right?

For tasks lasting 10-60 minutes, the parameters need to satisfy:

```
heartbeat_interval << stale_claim_TTL << max_task_duration
```

Current values:
- Heartbeat interval: ~60s (piggybacked on sprint-budget checks)
- Stale-claim TTL: 2700s (45 min)
- Max task duration: 60 min (typical bead)

**Problem:** A 45-minute TTL for a 60-minute max task means a legitimately working agent on a long task will appear stale for the last 15 minutes of its work if it somehow misses a heartbeat. The safety margin is thin.

**Airflow's approach:** Airflow uses `scheduler_zombie_task_threshold` (default 300s / 5 minutes) with a heartbeat interval of ~30s. The ratio is ~10:1 (threshold = 10x heartbeat interval). This allows for ~10 missed heartbeats before declaring dead — robust against transient pauses.

**Recommended parameters for Sylveste:**

| Parameter | Current | Recommended | Rationale |
|---|---|---|---|
| Heartbeat interval | ~60s (implicit) | 60s (explicit) | Budget check already runs at this cadence. No change needed. |
| Stale-claim TTL | 2700s (45min) | 600s (10min) | 10x heartbeat interval. A healthy agent heartbeats every 60s; 10 missed heartbeats = something is wrong. |
| Intermux stuck threshold | 300s (5min) | 300s (5min) | Keep as early warning. Triggers `stuck` status, not unclaim. |
| Abandoned threshold (new) | N/A | 600s (10min) | Matches stale-claim TTL. Triggers `abandoned` status + unclaim. |

**Why shorten from 45min to 10min?** The current 45-minute TTL was designed for the manual world where a human checks `bd list` periodically. In the automated factory, the patrol loop checks every 30 seconds. A 10-minute TTL is aggressive enough to recover quickly but conservative enough to avoid false positives (would require 10 consecutive missed heartbeats).

**Risk mitigation:** Before unclaiming at 10 minutes, the system should:
1. Check intermux status — is the tmux pane alive and producing output? If yes, just refresh the heartbeat (the agent forgot, not died).
2. Check PID liveness — is the agent process running? If yes but no output, mark `stuck` but don't unclaim yet.
3. Only unclaim if both heartbeat is stale AND (tmux pane dead OR process crashed OR no output for >10min).

### Concrete Implementation: Watchdog Process

The watchdog is the missing piece. It should be a goroutine in the mycroft patrol loop (or a standalone process for Phase 1):

```
watchdog_sweep():
  for each bead in bd_list(status=in_progress):
    claimed_at = bd_state(bead, "claimed_at")
    age = now() - claimed_at

    if age < stale_TTL:
      continue  # healthy

    # Cross-reference with intermux
    intermux_status = intermux_health(bead.agent_session)

    if intermux_status == "active":
      # Agent is alive but forgot to heartbeat — refresh it
      bead_heartbeat(bead.id)
      continue

    if intermux_status in ["stuck", "crashed", "unknown"]:
      # Confirm dead, then unclaim
      unclaim(bead.id, failure_class=classify(intermux_status))
```

---

## 5. Manufacturing Andon Cord: Escalation After N Failures

### The Pattern

Toyota's Andon Cord allows any worker to stop the production line when they detect a problem. The key properties:

1. **Anyone can pull it** — the agent itself, the watchdog, or the human.
2. **It stops the line** — no new work dispatched until the problem is addressed.
3. **Specialists respond immediately** — designated personnel go to the problem (go and see).
4. **Root cause, not workaround** — the line stays stopped until the root cause is fixed.

### Application to Factory

The mycroft brainstorm (`/home/mk/projects/Sylveste/docs/brainstorms/2026-03-12-mycroft-fleet-orchestrator-brainstorm.md` line 75-80) already defines demotion triggers that are effectively andon cord pulls:

- **3 consecutive failures on different beads** → immediate one-tier demotion
- **>15% failure rate in rolling 24h** → T2 → T1
- **>25% failure rate in rolling 24h** → T3 → T2
- **Budget overshoot (>120% daily)** → any tier → T0

### What's Missing: The "Stop and Fix" Protocol

The mycroft CUJ (`/home/mk/projects/Sylveste/docs/cujs/mycroft-failure-recovery.md`) describes the developer investigating after demotion, but doesn't define a structured escalation protocol. Here's what the factory needs:

**Tier 1 Andon: Auto-retry with backoff (agent pulls cord)**

```
Trigger:  Agent fails a bead (non-zero exit, crash, stuck)
Action:   Unclaim bead, classify failure, log to dispatch_log
Retry:    Same bead re-enters queue with attempt_count + 1
Limit:    max_attempts = 3 per bead
Who:      Fully automatic (watchdog)
```

**Tier 2 Andon: Single-bead quarantine (watchdog pulls cord)**

```
Trigger:  Same bead fails max_attempts times
Action:   Set bead status=blocked, add label:needs-human
          Log: "bead {id} failed {n} times: {failure_summaries}"
Retry:    None — bead is quarantined until human reviews
Who:      Watchdog quarantines; human un-quarantines
```

**Tier 3 Andon: Factory pause (circuit breaker pulls cord)**

```
Trigger:  3 consecutive failures on different beads (correlated failures)
          OR >15% failure rate in rolling window
          OR environment check fails (Dolt, git, disk)
Action:   mycroft.pause(), tier demotion, alert human
          Log: "factory paused: {trigger_reason}, {evidence}"
Retry:    None — human must investigate root cause and resume
Who:      Circuit breaker pauses; human resumes after fix
```

**Tier 4 Andon: Full stop (human pulls cord)**

```
Trigger:  `mycroft pause --drain` (manual)
Action:   Stop all dispatch, signal agents to checkpoint
          In-flight agents finish current step then stop
Who:      Human, explicitly
```

### Critical Design Principle

**Never auto-retry more than 3 times total per bead.** After 3 attempts, the failure is either in the spec (needs human clarification) or in the environment (needs infra fix). Auto-retrying a 4th time is waste.

This aligns with Temporal's practice: set `MaximumAttempts` and let the workflow handle the terminal failure, rather than retrying forever and hoping.

### Implementation in Bead State

Track retry attempts via `bd set-state`:

```
bd set-state <bead_id> attempt_count=1
bd set-state <bead_id> last_failure_class=retriable
bd set-state <bead_id> last_failure_at=<epoch>
bd set-state <bead_id> last_failure_agent=<session_id>
```

The watchdog reads `attempt_count` before re-queuing. If `attempt_count >= 3`, quarantine instead of retry.

---

## 6. Failure Classification: A Decision Tree

### The Three Failure Classes

Every failure the factory encounters falls into one of three classes. The classification determines the recovery action.

```
                         Agent failed
                              │
                    ┌─────────┴──────────┐
                    │ Was the process     │
                    │ alive at failure?   │
                    └─────────┬──────────┘
                         no/  │  \yes
                        /     │    \
                       ▼      │     ▼
               ┌─────────┐   │  ┌──────────────────┐
               │ CRASHED  │   │  │ Did it produce    │
               │ (retry)  │   │  │ any output/commits│
               └─────────┘   │  └────────┬─────────┘
                              │      no/  │  \yes
                              │     /     │    \
                              │    ▼      │     ▼
                              │ ┌──────┐  │  ┌────────────────────┐
                              │ │STUCK │  │  │ Did it fail with a  │
                              │ │(retry│  │  │ clear error message?│
                              │ │once) │  │  └────────┬───────────┘
                              │ └──────┘  │      no/  │  \yes
                              │           │     /     │    \
                              │           │    ▼      │     ▼
                              │           │  ┌─────┐  │  ┌───────────────┐
                              │           │  │AMBI-│  │  │ Is the error  │
                              │           │  │GUOUS│  │  │ about the spec│
                              │           │  │(esc)│  │  │ or about env? │
                              │           │  └─────┘  │  └───────┬───────┘
                              │           │           │    spec/ │ \env
                              │           │           │   /     │   \
                              │           │           │  ▼      │    ▼
                              │           │           │┌─────┐  │ ┌──────┐
                              │           │           ││SPEC │  │ │ ENV  │
                              │           │           ││BLOCK│  │ │BLOCK │
                              │           │           │└─────┘  │ └──────┘
                              │           │           │         │
                              │           │           │         │
```

### Classification Signals

| Signal | Source | Indicates |
|---|---|---|
| tmux pane gone, PID dead | intermux `StatusCrashed` | **Agent crash** — safe to retry |
| No output for >StuckTimeout, PID alive | intermux `StatusStuck` | **Agent stuck** — retry once, then escalate |
| Agent exited with error mentioning "ambiguous", "unclear", "conflicting" | Agent exit log | **Spec blocked** — needs human |
| Agent exited with error mentioning "auth", "permission", "disk", "network", "Dolt" | Agent exit log | **Env blocked** — needs infra fix |
| Agent produced commits but tests fail on all attempts | Bead state + git log | **Spec blocked** — the task as specified may not be feasible |
| Agent produced no commits across multiple attempts | Bead state | **Ambiguous** — could be spec or agent issue. Escalate after 2 retries. |

### Concrete Classification Function

For Phase 1, classification can be simple pattern matching on the failure context:

```
classify(intermux_status, exit_log, bead_state) -> failure_class:
  if intermux_status == "crashed":
    return "retriable"

  if intermux_status == "stuck" and bead_state.attempt_count < 2:
    return "retriable"

  if exit_log matches /auth|permission|denied|ENOSPC|Dolt|zombie|ECONNREFUSED/:
    return "env_blocked"

  if exit_log matches /ambiguous|unclear|conflicting|underspecified|missing.*context/:
    return "spec_blocked"

  if bead_state.attempt_count >= 2 and no_commits_produced:
    return "spec_blocked"  # Two attempts, no progress — spec is the problem

  return "retriable"  # Default: assume transient, try one more time
```

### Integration with Existing Code

The classification function should be called from two places:

1. **`cmdSprintRelease` in claim.go (line 154):** When an agent completes (normally or abnormally), the release path should classify the failure if the bead is not closed.

2. **Watchdog sweep:** When the watchdog detects a stale/crashed agent, it classifies based on intermux status and available exit logs.

The classification is written to bead state as `failure_class` and `failure_detail`, making it available to the patrol loop, the dispatch queue, and the human via `bd show`.

---

## Summary: Recovery Runbook

### Automatic Recovery (No Human Needed)

| Scenario | Detection | TTL | Action |
|---|---|---|---|
| Agent process crashes | intermux PID check → `crashed` | Immediate | Unclaim, classify `retriable`, re-queue |
| Agent stuck (no output) | intermux output check → `stuck` | 5 min | Mark stuck; wait for StaleClaimTTL |
| Stale heartbeat, pane dead | watchdog `claimed_at` check | 10 min | Unclaim, classify `retriable`, re-queue |
| Stale heartbeat, pane alive + output | watchdog + intermux cross-ref | 10 min | Refresh heartbeat (false positive) |

### Human-Required Recovery

| Scenario | Detection | Trigger | Action |
|---|---|---|---|
| Same bead fails 3 times | watchdog `attempt_count >= 3` | Tier 2 andon | Quarantine bead, label `needs-human` |
| 3 different beads fail consecutively | patrol loop dispatch_log | Tier 3 andon | Pause factory, demote tier |
| >15% failure rate | rolling window on dispatch_log | Circuit breaker | Demote tier, alert human |
| Correlated failure (>2 agents at once) | watchdog disruption budget | Tier 3 andon | Pause factory, classify `env_blocked` |
| Environment broken | env health check | Tier 3 andon | Pause factory, label `needs-infra` |

### State Machine for Bead Recovery

```
in_progress + claimed
       │
       │ agent fails
       ▼
in_progress + released + failure_class + attempt_count
       │
       ├── attempt_count < 3 AND failure_class == "retriable"
       │   └── re-enter dispatch queue (auto)
       │
       ├── attempt_count >= 3 OR failure_class == "spec_blocked"
       │   └── status=blocked + label:needs-human (quarantine)
       │
       └── failure_class == "env_blocked"
           └── status=blocked + label:needs-infra (factory pause)
```

---

## Key Files Referenced

| File | Relevance |
|---|---|
| `/home/mk/projects/Sylveste/os/Clavain/cmd/clavain-cli/claim.go` | Heartbeat, claim/release, stale detection (2700s TTL) |
| `/home/mk/projects/Sylveste/interverse/intermux/internal/health/monitor.go` | Health monitor with stuck detection (5min threshold) |
| `/home/mk/projects/Sylveste/interverse/intermux/internal/activity/models.go` | Agent status enum (active/idle/stuck/crashed/unknown) |
| `/home/mk/projects/Sylveste/docs/cujs/mycroft-failure-recovery.md` | Failure recovery CUJ with tier demotion triggers |
| `/home/mk/projects/Sylveste/docs/brainstorms/2026-03-12-mycroft-fleet-orchestrator-brainstorm.md` | Circuit breaker thresholds, reconciliation sweep |
| `/home/mk/projects/Sylveste/.claude/flux-drive-output/fd-coordination-state-model.md` | Bead claim as LWW-Register, Dolt zombie problem chain |

## Sources

- [Temporal: Saga Compensating Transactions](https://temporal.io/blog/compensating-actions-part-of-a-complete-breakfast-with-sagas)
- [Temporal: Error Handling in Distributed Systems](https://temporal.io/blog/error-handling-in-distributed-systems)
- [Temporal: Retry Policies](https://docs.temporal.io/encyclopedia/retry-policies)
- [Temporal: Failures Reference](https://docs.temporal.io/references/failures)
- [Temporal: Retry Logic Best Practices](https://temporal.io/blog/failure-handling-in-practice)
- [Kestra: Building a New Liveness and Heartbeat Mechanism](https://kestra.io/blogs/2024-04-22-liveness-heartbeat)
- [Martin Fowler: HeartBeat Pattern](https://martinfowler.com/articles/patterns-of-distributed-systems/heartbeat.html)
- [AlgoMaster: HeartBeats in Distributed Systems](https://blog.algomaster.io/p/heartbeats-in-distributed-systems)
- [Apache Airflow: Zombie Task Detection](https://medium.com/@shakik19/troubleshooting-zombie-task-job-errors-in-apache-airflow-5527303dbcad)
- [Apache Airflow: Tasks Documentation](https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/tasks.html)
- [Kubernetes: Pod Disruption Budgets](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/)
- [Kubernetes: Configuring PDBs](https://kubernetes.io/docs/tasks/run-application/configure-pdb/)
- [IT Revolution: The Andon Cord](https://itrevolution.com/articles/kata/)
- [DevLead: Andon Cord Pattern](https://devlead.io/DevTips/AndonCord)
- [Redis: Distributed Locks with Heartbeats](https://compileandrun.com/redis-distrubuted-locks-with-heartbeats/)

<!-- flux-research:complete -->
