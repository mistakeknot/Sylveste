# Closed-Loop Feedback Signals for AI Factory Self-Regulation

**Research question:** What closed-loop signals let the AI factory regulate itself — throughput metrics, backlog health, dynamic concurrency, and learning from completed work?

**Status:** Complete
**Date:** 2026-03-19

---

## Executive Summary

A self-regulating AI factory needs six feedback loops, each with a distinct sample rate and control action. This document maps concrete control-theory mechanisms to Sylveste's existing data sources (`bd stats`, interstat, intermux, fleet-registry.yaml), identifies what signals are already observable, and specifies the minimal new instrumentation required to close each loop.

The central finding: **three of the six loops can be closed today with existing data; the other three require only per-bead timestamp enrichment and a 20-line aggregation query.** No new databases or services are needed — the signals exist but are not yet connected to actuators.

---

## 1. Throughput Governor: PI Controller over Agent Concurrency

### The Control Problem

The factory must decide how many concurrent agent sessions to run. Too few starves throughput; too many wastes tokens on context-loading overhead and increases merge conflict probability. The setpoint is not a fixed number — it is a function of backlog depth and completion rate.

### PI Controller Design

A proportional-integral (PI) controller is the standard industrial solution for setpoint tracking with zero steady-state error. The proportional term reacts to the current gap; the integral term eliminates persistent offset.

```
error(t) = queue_depth(t) - target_queue_depth
P_term   = Kp * error(t)
I_term   = Ki * Σ error(τ) dτ     (with anti-windup clamp)
desired_agents(t) = base_agents + P_term + I_term
actual_agents(t)  = clamp(desired_agents(t), min_agents, max_agents)
```

**Tuning parameters:**
- `Kp`: Proportional gain. Start at 0.5 (spawn half an agent per excess bead). Too high causes thrashing.
- `Ki`: Integral gain. Start at 0.05 (slow correction of persistent backlog). Too high causes windup overshoot.
- `target_queue_depth`: The desired steady-state backlog. Not zero — a small buffer (2-3 beads) prevents idle agents.
- Anti-windup: Clamp the integral accumulator when `actual_agents` hits `min_agents` or `max_agents`. This prevents the integral term from winding up during saturation, which would cause overshoot when the constraint releases.

**Why PI, not PID:** The derivative term reacts to rate-of-change, useful for fast disturbance rejection. Agent spawning has 30-60 second latency (tmux session creation + context loading), which makes derivative action noisy and counterproductive. PI is sufficient.

### Mapping to Sylveste Data Sources

| Signal | Source | Query |
|--------|--------|-------|
| `queue_depth` | `bd stats` | Count of beads with `status=ready` or `status=blocked_ready` |
| `active_agents` | intermux `store.List()` | Count of `AgentActivity` with `Status == StatusActive` |
| `completion_rate` | `bd stats` + timestamps | Beads closed per hour (rolling window) |
| `target_queue_depth` | Derived | `active_agents * avg_bead_duration_hours` (keep ~1 bead queued per agent) |

### Control Loop Implementation

Sample every 60 seconds. The actuator is `tmux new-session` (spawn) or allowing idle sessions to self-terminate after a grace period (retire). Never kill active agents — only withhold new work from idle ones.

```
every 60s:
  queue     = bd list --status=ready | wc -l
  active    = intermux list | jq '[.[] | select(.status=="active")] | length'
  error     = queue - target
  integral += error * dt
  integral  = clamp(integral, -max_integral, max_integral)   # anti-windup
  desired   = base + Kp*error + Ki*integral
  desired   = clamp(desired, min_agents, max_agents)
  if desired > active: spawn (desired - active) agents
  if desired < active: mark (active - desired) agents as "drain" (finish current bead, don't claim next)
```

**Kubernetes HPA analogy:** K8s HPA uses `desiredReplicas = ceil(currentReplicas * (currentMetricValue / desiredMetricValue))` — a pure proportional controller. Adding the integral term via custom metrics and a sidecar controller eliminates the steady-state offset that causes K8s HPA to oscillate around the target. The `--horizontal-pod-autoscaler-downscale-stabilization` flag (default 5 minutes) serves as a crude anti-windup. Our explicit integral clamp is more principled.

**Reference:** [Celery autoscaling on ECS Fargate](https://www.obytes.com/blog/autoscale-celery-rabbitmq) demonstrates queue-depth-driven worker scaling; [KEDA Celery scaler](https://github.com/klippa-app/keda-celery-scaler) uses load ratio `(active + queued) / workers` as the scaling metric. Both are proportional-only. [Kubernetes HPA docs](https://kubernetes.io/docs/concepts/workloads/autoscaling/horizontal-pod-autoscale/) describe the behavior stabilization window that approximates integral control.

---

## 2. Takt Time: The Factory's Heartbeat

### Toyota TPS Takt Time

In Toyota's Production System, takt time is the drumbeat that synchronizes the entire line:

```
takt_time = available_production_time / customer_demand
```

If a factory runs 480 minutes/day and customers order 240 units, takt time is 2 minutes. Every station must complete its operation within 2 minutes, or the line stops (andon pull). The power of takt time is that it converts an external constraint (demand) into an internal rhythm that every worker can observe.

### AI Factory Takt Time

The AI factory equivalent replaces "customer demand" with "backlog arrival rate" and "available production time" with "agent-hours available":

```
takt_time = agent_hours_available / beads_arriving_per_period
```

But unlike Toyota, our factory has elastic capacity. The more useful formulation is the **inverse** — the **required completion rate** to prevent backlog growth:

```
required_throughput = arrival_rate + (current_backlog - target_backlog) / drain_horizon
```

Where `drain_horizon` is the acceptable time to return to steady state (e.g., 4 hours). This is the setpoint for the PI controller in Section 1.

### Computing Takt from Existing Data

| Metric | Source | Computation |
|--------|--------|-------------|
| `arrival_rate` | `bd list --status=ready --since=24h` | New beads per hour (EMA over 24h) |
| `completion_rate` | `bd list --status=closed --since=24h` | Closed beads per hour (EMA over 24h) |
| `avg_bead_cost_usd` | `cost-query.sh by-bead` | Median USD per closed bead |
| `agent_hours_available` | intermux `List()` | `count(active) * 1.0` (each agent = 1 agent-hour per hour) |
| `takt_time` | Derived | `agent_hours_available / arrival_rate` |
| `cycle_efficiency` | Derived | `actual_cycle_time / takt_time` (>1.0 means falling behind) |

### Little's Law Cross-Check

Little's Law provides the consistency check: `WIP = throughput * cycle_time`. If observed WIP (in-progress beads) diverges from `throughput * avg_cycle_time`, one of the three measurements is wrong — or the system is not in steady state. This is a free diagnostic from existing data.

```
expected_wip = completion_rate_per_hour * avg_hours_to_complete
observed_wip = bd list --status=in_progress | wc -l
drift        = observed_wip - expected_wip
```

If `drift > 0` persistently, beads are getting stuck (claim without completion). If `drift < 0`, beads are completing faster than expected (good) or the completion rate measurement is stale (bad).

**Reference:** [Little's Law in Kanban](https://kanbanzone.com/resources/lean/littles-law/) — `WIP = throughput * cycle_time`; [Takt time fundamentals](https://www.creativesafetysupply.com/glossary/takt-time/); [TPS metrics for software](https://www.researchgate.net/figure/TPS-and-software-measurement-process-and-metrics-Source-the-authors-work-TPS-Toyota_fig6_384360093).

---

## 3. Temporal-Style Workflow Health Metrics

### What Temporal Measures

Temporal's workflow engine exposes three categories of health metrics that map directly to bead lifecycle:

1. **Schedule-to-Start Latency** — time from task enqueue to worker pickup. High values mean workers cannot keep up.
2. **Workflow Execution Duration** — total time from start to completion. Percentile distributions reveal long-tail problems.
3. **Failure Rate** — fraction of workflows that fail or time out. Elevated rates indicate systemic issues (bad dependencies, flaky tests).

Temporal's recommended alert: `schedule_to_start_latency p99 > 1 minute` means "add workers or investigate stuck tasks." Their backlog health formula: `demand_per_worker = backlog_count / worker_count`.

### Mapping to Bead Lifecycle

Every Temporal metric has a bead equivalent computable from `bd` timestamps:

| Temporal Metric | Bead Equivalent | Computation |
|-----------------|----------------|-------------|
| `schedule_to_start_latency` | **Time-to-Claim** | `claimed_at - created_at` |
| `workflow_task_schedule_to_start` | **Claim-to-Active** | First tool use timestamp - `claimed_at` (from interstat) |
| `workflow_execution_duration` | **Bead Cycle Time** | `closed_at - created_at` |
| `activity_execution_duration` | **Active Work Time** | Sum of interstat session durations for bead |
| `workflow_completion_rate` | **Close Rate** | `closed / (closed + cancelled + stale)` per period |
| `workflow_failure_rate` | **Retry/Reopen Rate** | Beads that were closed then reopened, or cancelled after claim |

### What Is Missing Today

The critical gap: **`bd` does not store `claimed_at` as a first-class timestamp.** The `bd set-state` writes `claimed_at` as an opaque state key, but `bd list` and `bd stats` do not expose it in structured output. To close this loop:

1. `bd list --json` should include `claimed_at` and `closed_at` as ISO timestamps
2. Alternatively, a `bd metrics` subcommand that computes time-to-claim, cycle-time, and close-rate distributions

Until then, the workaround: parse `.beads/backup/events.jsonl` for state-transition timestamps. Events with `type: "state_changed"` and `key: "claimed_at"` contain the epoch value.

### Alert Thresholds (Starting Points)

| Metric | Warning | Critical | Action |
|--------|---------|----------|--------|
| Time-to-Claim p50 | > 30 min | > 2 hours | Backlog has stale beads or agents are not claiming |
| Bead Cycle Time p90 | > 4 hours | > 8 hours | Complexity misclassification or agent stuck |
| Close Rate (24h) | < 60% | < 40% | Systemic quality issue — beads being abandoned |
| Retry Rate (7d) | > 15% | > 25% | Work decomposition too coarse or acceptance criteria unclear |

**Reference:** [Temporal schedule-to-start latency](https://docs.temporal.io/develop/worker-performance); [Temporal SDK metrics](https://docs.temporal.io/references/sdk-metrics); [Autoscaling Temporal workers](https://community.temporal.io/t/suggested-metrics-to-autoscale-temporal-workers-on/5870).

---

## 4. Utility Scoring: Learning from Completed Work

### Game AI Utility Systems

In game AI, utility systems score every possible action on a 0-to-1 scale using **considerations** — functions that map world state to a normalized score. The agent picks the highest-scoring action. The power is in the update rule: after taking an action, the outcome adjusts future scores.

A typical response curve maps a raw input (e.g., "hunger level 0.0-1.0") through a function (linear, quadratic, logistic) to produce a utility score. Multiple considerations are multiplied together (or use a compensation formula) to produce the final action score.

### Application to Route.md Complexity Classification

Route.md currently classifies beads into complexity tiers (quick-fix, standard, complex, epic-scale) using static heuristics. Utility scoring can make this adaptive:

**Considerations for complexity classification:**
- `file_count_consideration`: Number of files likely touched (from bead description NLP + historical similarity)
- `dependency_consideration`: Cross-module dependencies detected in description
- `test_requirement_consideration`: Whether tests are mentioned or implied
- `historical_cost_consideration`: Token cost of similar past beads (from interstat `by-bead`)

**Update rule using EMA:**

```
After bead closes:
  predicted_tier  = route.md classification at claim time
  actual_cost     = interstat cost-query.sh cost-snapshot --bead=<id>
  actual_tier     = tier_from_cost(actual_cost)    # map USD to tier thresholds

  if actual_tier != predicted_tier:
    # Adjust the consideration weights using exponential moving average
    for each consideration C that contributed to the prediction:
      C.weight = α * observed_signal + (1 - α) * C.weight
      where α = 0.1 (learning rate — slow adaptation to avoid overfit to single bead)
```

The EMA update is the simplest viable learning rule. It has one hyperparameter (α), does not require a training dataset, and converges to the true distribution under stationarity. Research on EMA Q-learning confirms convergence properties in multi-agent settings.

**Concrete implementation path:**
1. After each bead closes, `cost-query.sh cost-snapshot --bead=<id>` retrieves actual cost
2. Compare against the tier prediction stored in bead metadata (requires storing `predicted_complexity` at claim time)
3. Write `(predicted, actual)` pairs to a JSONL file: `~/.claude/interstat/complexity-calibration.jsonl`
4. Periodically (weekly), compute per-tier accuracy and adjust threshold boundaries in route.md config

**Reference:** [Game AI Pro — Utility Theory](http://www.gameaipro.com/GameAIPro/GameAIPro_Chapter09_An_Introduction_to_Utility_Theory.pdf); [EMA Q-learning](https://link.springer.com/article/10.1007/s10462-015-9447-5); [Choosing Effective Utility-Based Considerations](http://www.gameaipro.com/GameAIPro3/GameAIPro3_Chapter13_Choosing_Effective_Utility-Based_Considerations.pdf).

---

## 5. Fleet Utilization: Surplus vs. Starvation Detection

### The Detection Problem

The factory can be in three states:
- **Balanced:** Most agents active, small ready backlog (1-2 beads), no idle agents
- **Surplus (too many agents):** Multiple agents idle, ready backlog near zero, token cost rising without throughput gains
- **Starvation (too few agents):** All agents active, ready backlog growing, time-to-claim increasing

These map to Temporal's worker health diagnostics: `LastAccessTime > 5min` means worker fleet has shrunk; `ApproximateBacklogAge` growing means workers cannot keep up.

### Detection Signals from Existing Sources

```
# Compute fleet state every 60 seconds
active   = intermux list | jq '[.[] | select(.status=="active")] | length'
idle     = intermux list | jq '[.[] | select(.status=="idle")] | length'
stuck    = intermux list | jq '[.[] | select(.status=="stuck")] | length'
ready    = bd list --status=ready | wc -l
wip      = bd list --status=in_progress | wc -l

utilization = active / (active + idle)          # 0.0 to 1.0
demand_ratio = ready / max(active, 1)           # beads per active agent
```

### State Classification

| State | Condition | Control Action |
|-------|-----------|----------------|
| **Balanced** | `0.7 ≤ utilization ≤ 0.9` AND `demand_ratio ∈ [0.5, 2.0]` | No action |
| **Surplus** | `utilization < 0.5` AND `demand_ratio < 0.5` | Let idle agents drain; do not spawn |
| **Mild Starvation** | `utilization > 0.9` AND `demand_ratio > 2.0` | Spawn 1 agent (PI controller handles) |
| **Severe Starvation** | `utilization > 0.95` AND `demand_ratio > 5.0` | Emergency spawn + alert human |
| **Stuck Fleet** | `stuck > 0.3 * (active + stuck)` | Kill stuck sessions, investigate root cause |

### Cost-Aware Utilization

Raw utilization ignores cost. A fleet of 10 agents at 80% utilization costs 8x what 1 agent at 80% costs. The cost-aware metric:

```
cost_efficiency = beads_closed_per_hour / total_token_cost_per_hour
```

If adding an agent increases `beads_closed_per_hour` by less than its marginal token cost, the fleet is over-provisioned. This is the diminishing-returns signal. Track it as a time series; when the derivative goes negative, stop spawning.

### Fleet-Registry Integration

`fleet-registry.yaml` already tracks per-agent `cold_start_tokens` — the overhead cost of spawning. The spawn decision should factor this in:

```
net_value_of_spawn = expected_beads_completed * avg_value_per_bead
                   - cold_start_tokens * cost_per_token
                   - hourly_token_burn * expected_active_hours
```

Only spawn if `net_value_of_spawn > 0`.

**Reference:** [Temporal worker performance docs](https://docs.temporal.io/develop/worker-performance) — backlog count / worker count as demand metric; [Fleet resource utilization metrics (GKE)](https://cloud.google.com/kubernetes-engine/fleet-management/docs/utilization-metrics).

---

## 6. Per-Bead Health Signals: Detecting Systemic Problems

### Individual Bead Signals

Each bead emits signals through its lifecycle that, when aggregated, reveal systemic problems:

| Signal | Definition | What It Detects |
|--------|-----------|-----------------|
| **Time-to-Claim** | `claimed_at - created_at` | Backlog hygiene: are beads well-described enough to claim? |
| **Claim-Attempt Count** | Number of agents that claimed then unclaimed a bead | Bead is too hard, poorly specified, or has hidden dependencies |
| **Active Duration** | Total interstat session time while bead was in-progress | Execution difficulty — compare against complexity tier prediction |
| **Idle Duration** | Time in-progress but no interstat activity | Agent stuck, waiting for human input, or claiming without working |
| **Retry Rate** | Beads closed then reopened | Quality problem — work not meeting acceptance criteria |
| **Escalation Rate** | Beads that hit human-gate more than once | Acceptance criteria ambiguous or agent misunderstanding requirements |

### Aggregation for Systemic Detection

Individual signals are noisy. Aggregated across the backlog, they diagnose systemic problems:

**High mean time-to-claim (> 1 hour):**
- Cause A: Bead descriptions are too vague for agents to assess claimability
- Cause B: All beads are high-complexity and agents are capacity-constrained
- Diagnosis: Check if time-to-claim correlates with bead word count (Cause A) or with fleet utilization (Cause B)

**Rising claim-attempt count (> 1.5 attempts per bead):**
- Cause A: Complexity misclassification — beads labeled "quick-fix" are actually "standard"
- Cause B: Missing dependencies not declared in bead metadata
- Diagnosis: Compare predicted vs. actual complexity (Section 4). If mismatch rate > 30%, recalibrate.

**Idle duration > 50% of active duration:**
- Cause: Agents are blocked on gates, waiting for human review, or stuck in retry loops
- Action: Audit gate configuration; consider auto-approval for low-risk tiers

**Retry rate > 15% (rolling 7-day window):**
- Cause: Acceptance criteria too strict, or agents not reading them
- Action: Compare retry beads against non-retry beads. Check if specific complexity tiers or domains have disproportionate retry rates.

### Implementation: Events JSONL as the Signal Source

All per-bead signals can be extracted from `.beads/backup/events.jsonl`, which records every state transition:

```bash
# Time-to-claim distribution (requires jq)
jq -r 'select(.type=="state_changed" and .key=="claimed_at") |
  [.bead_id, .value] | @tsv' .beads/backup/events.jsonl |
while read bead_id claimed_epoch; do
  created=$(jq -r "select(.type==\"created\" and .bead_id==\"$bead_id\") | .timestamp" .beads/backup/events.jsonl)
  echo "$bead_id $(( claimed_epoch - $(date -d "$created" +%s) ))"
done
```

This is O(n^2) and fragile. The proper solution is a `bd metrics` subcommand that computes these distributions directly from the Dolt database, which has indexed access to all state transitions.

---

## Signal Dependency Graph

The six loops form a hierarchy where faster loops feed slower ones:

```
Sample Rate    Loop                          Feeds Into
─────────────────────────────────────────────────────────
60s            1. PI Concurrency Controller   → spawn/drain tmux sessions
60s            5. Fleet Utilization           → override PI controller limits
5m             3. Workflow Health Metrics      → alert thresholds for human
1h             2. Takt Time                   → adjust PI setpoint
on-close       4. Utility Scoring             → update route.md tier thresholds
daily          6. Per-Bead Aggregates         → systemic backlog hygiene
```

The fastest loops (PI controller, fleet utilization) operate on current state and need only intermux + `bd stats`. The slowest loops (utility scoring, per-bead aggregates) operate on historical data and need interstat + events JSONL.

---

## Implementation Priority

### Phase 0: Observable Today (No Code Changes)

These signals can be computed right now with existing tools:

1. **Fleet utilization** — `intermux list` gives active/idle/stuck counts
2. **Queue depth** — `bd list --status=ready` gives backlog size
3. **WIP** — `bd list --status=in_progress` gives in-progress count
4. **Token cost per bead** — `cost-query.sh by-bead` gives per-bead token spend
5. **Little's Law check** — combine WIP, throughput (beads closed/day), and cycle time

### Phase 1: Minimal Instrumentation (< 100 lines)

1. **Takt time dashboard** — shell script computing arrival rate, completion rate, and takt time from `bd stats` output
2. **`bd metrics` subcommand** — compute time-to-claim, cycle-time, and close-rate distributions from Dolt
3. **Complexity calibration JSONL** — store `(predicted_tier, actual_cost)` pairs on bead close

### Phase 2: Closed-Loop Control (< 500 lines)

1. **PI controller script** — 60-second loop reading intermux + bd, writing spawn/drain decisions
2. **Utility score updater** — on-close hook reading calibration JSONL, adjusting route.md thresholds via EMA
3. **Fleet state classifier** — intermux enrichment adding surplus/balanced/starved to health reports

### Phase 3: Adaptive Setpoints

1. **Auto-tuning Kp/Ki** — use Ziegler-Nichols method: increase Kp until oscillation, then apply Z-N ratios
2. **Dynamic target_queue_depth** — adjust based on observed bead duration distribution (keep ~1 bead queued per agent at p50 duration)
3. **Cross-loop integration** — per-bead aggregates (Loop 6) feed utility scoring (Loop 4), which feeds takt time setpoint (Loop 2), which feeds PI controller target (Loop 1)

---

## Key Insight

The factory does not need a complex scheduler. It needs **six independent feedback loops with different sample rates**, each making a single control decision based on a single observable signal. The loops interact through shared state (fleet size, backlog, cost data) but do not coordinate explicitly. This is the control-theory principle of **cascade control**: fast inner loops stabilize the plant, slow outer loops optimize the setpoint.

The minimum viable self-regulating factory is: a 60-second PI controller over agent count (Loop 1) with fleet utilization override (Loop 5), a weekly complexity recalibration (Loop 4), and a human-readable takt time dashboard (Loop 2). Everything else is refinement.

---

Sources:
- [Celery autoscaling on ECS Fargate](https://www.obytes.com/blog/autoscale-celery-rabbitmq)
- [KEDA Celery scaler](https://github.com/klippa-app/keda-celery-scaler)
- [Kubernetes HPA documentation](https://kubernetes.io/docs/concepts/workloads/autoscaling/horizontal-pod-autoscale/)
- [Kubernetes HPA custom metrics guide](https://oneuptime.com/blog/post/2026-01-21-horizontal-pod-autoscaler-custom-metrics/view)
- [PI Controller fundamentals](https://apmonitor.com/pdc/index.php/Main/ProportionalIntegralControl)
- [Discrete PI controller implementation](https://imperix.com/doc/implementation/pi-controller)
- [Little's Law in Kanban](https://kanbanzone.com/resources/lean/littles-law/)
- [Takt time calculation](https://www.creativesafetysupply.com/glossary/takt-time/)
- [TPS and software measurement metrics](https://www.researchgate.net/figure/TPS-and-software-measurement-process-and-metrics-Source-the-authors-work-TPS-Toyota_fig6_384360093)
- [Temporal worker performance](https://docs.temporal.io/develop/worker-performance)
- [Temporal SDK metrics reference](https://docs.temporal.io/references/sdk-metrics)
- [Temporal schedule-to-start monitoring](https://community.temporal.io/t/how-to-monitor-scheduletostart-latency/3235)
- [Autoscaling Temporal workers](https://community.temporal.io/t/suggested-metrics-to-autoscale-temporal-workers-on/5870)
- [Game AI Pro: Utility Theory](http://www.gameaipro.com/GameAIPro/GameAIPro_Chapter09_An_Introduction_to_Utility_Theory.pdf)
- [Game AI Pro 3: Effective Utility Considerations](http://www.gameaipro.com/GameAIPro3/GameAIPro3_Chapter13_Choosing_Effective_Utility-Based_Considerations.pdf)
- [EMA Q-learning in multi-agent RL](https://link.springer.com/article/10.1007/s10462-015-9447-5)
- [GKE Fleet resource utilization metrics](https://cloud.google.com/kubernetes-engine/fleet-management/docs/utilization-metrics)

<!-- flux-research:complete -->
