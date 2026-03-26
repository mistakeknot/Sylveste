# Backlog Priority and Matching for Self-Dispatching Agents

**Research question:** How should agents score, filter, and select which bead to claim from a prioritized backlog?

**Scope:** Multi-agent task allocation, WIP limits, thundering-herd mitigation, dependency-aware scheduling. All recommendations must be expressible as `bd list` sort/filter + optional local randomization -- no inter-agent communication.

**Existing system:** `interverse/interphase/hooks/lib-discovery.sh` implements `score_bead()` (priority 0-60 + phase 0-30 + recency 0-20 - staleness 10) and `discovery_scan_beads()` which returns a sorted JSON array. `os/Clavain/commands/route.md` presents the top 3 to the user via AskUserQuestion. Claiming uses `bd update <id> --claim` (atomic, Dolt-backed). Heartbeat keeps claims fresh (45-min TTL).

---

## 1. Allocation Paradigms: Market-Based vs Role-Based vs Capability-Matching

### 1.1 Market-Based (Auction/Bid)

Auction algorithms like CBBA (Consensus-Based Bundle Algorithm, MIT ACL) have agents build ordered bundles of tasks they bid on, then resolve conflicts via consensus rounds. The key property is **provably conflict-free convergence** -- but it requires inter-agent communication (bid broadcasts, consensus phases). Recent work (Frontiers in Physics, 2025) extends this to cost-effectiveness maximization with capability-fitness modeling.

**Fit for Demarch:** Poor. CBBA requires O(agents * tasks) message passing per round. Our agents run in isolated tmux panes with no shared message bus. The `bd update --claim` atomic operation already provides conflict resolution at the claim point -- we don't need pre-claim consensus.

### 1.2 Role-Based (Static Assignment)

Each agent is assigned a lane/domain (e.g., "infra agent handles lane:infra beads"). Simple, zero coordination. Used in traditional Kanban team structures.

**Fit for Demarch:** Partial. We already have `DISCOVERY_LANE` filtering (`lane:infra`, `lane:plugins`, etc.) which implements this. But static assignment underutilizes agents when lanes have uneven load -- an infra agent sits idle while 10 plugin beads queue up.

### 1.3 Capability-Matching (Scheduler-Style)

The Kubernetes/Nomad approach: each task declares requirements, each node/agent declares capabilities, a scoring function matches them. No inter-agent communication needed -- each agent independently evaluates and self-selects.

**Fit for Demarch:** Best fit. Agents independently run `discovery_scan_beads()`, apply local scoring, and claim. The atomic `bd update --claim` handles conflicts at the point of commitment. This is already what lib-discovery.sh does -- the question is how to improve the scoring function.

### 1.4 Recommendation

**Capability-matching with opportunistic lane affinity.** Agents have a preferred lane (via `DISCOVERY_LANE`) but can escape to the global pool when their lane is empty. This combines the locality benefits of role-based with the utilization benefits of capability-matching.

```
if DISCOVERY_LANE is set AND lane has open beads:
    score only lane-matching beads
else:
    score all open beads (fallback to global pool)
```

This is already close to what exists -- the improvement is making the lane-escape explicit rather than requiring manual reconfiguration.

---

## 2. Scheduler Scoring: Nomad and Kubernetes Mapped to Bead Fields

### 2.1 Nomad's Two-Phase Architecture

Nomad separates **feasibility** (hard constraints, boolean pass/fail) from **ranking** (soft preferences, 0-1 scores). The `rank.go` implementation normalizes bin-packing scores to [0, 1.0] via `binPackingMaxFitScore = 18.0`, then averages across multiple scoring dimensions (bin-pack, affinity, anti-affinity, spread, job-anti-affinity, node-reschedule-penalty).

Key insight: **normalized additive scoring with independent dimensions is the production-proven pattern** for multi-factor ranking.

### 2.2 Kubernetes Scheduling Framework

Kubernetes v1.23+ uses a plugin-based framework with explicit extension points: PreFilter -> Filter -> PostFilter -> PreScore -> Score -> NormalizeScore -> Reserve -> Permit -> PreBind -> Bind. The Score plugins each return [0, 100] which are then weighted and summed.

Key insight: **weighted score normalization** allows different dimensions to have different importance without score-range coupling.

### 2.3 Mapping to Bead Fields

| Scheduler Concept | Bead Equivalent | Current Implementation | Gap |
|---|---|---|---|
| **Feasibility: node has resources** | Bead is open + unclaimed | `status=open` filter + claimed_by check | None |
| **Feasibility: constraint match** | Lane label matches agent | `DISCOVERY_LANE` filter | Missing lane-escape |
| **Feasibility: taint toleration** | Agent can handle bead type | Not implemented | Could filter by complexity vs agent capability |
| **Score: bin-packing** | N/A (no resource packing) | N/A | N/A |
| **Score: node affinity** | Priority weight | `priority_score` (0-60) | Good, 5-tier with 12-point gaps |
| **Score: pod topology spread** | WIP balance across lanes | Not implemented | See Section 3 |
| **Score: inter-pod anti-affinity** | Don't pile onto same epic | Not implemented | See Section 6 |
| **Score: image locality** | Phase advancement (closer to done = warmer cache) | `phase_score` (0-30) | Good |
| **Score: recency** | Recently touched = context-warm | `recency_score` (0-20) | Good |

### 2.4 Proposed Normalized Scoring

Refactor `score_bead()` to use normalized [0.0, 1.0] dimensions with configurable weights, following the Nomad/K8s pattern:

```
final_score = w_priority * norm_priority
            + w_phase    * norm_phase
            + w_recency  * norm_recency
            + w_deps     * norm_deps_ready    # NEW: Section 6
            + w_wip      * norm_wip_balance   # NEW: Section 3
            - penalty_stale
            - penalty_claimed
            - penalty_parent_closed
```

Default weights (sum to 1.0):
- `w_priority = 0.40` (strategic importance dominates, matching current 60/110 ratio)
- `w_phase = 0.25` (phase advancement is strong signal)
- `w_recency = 0.15` (context warmth matters but shouldn't override priority)
- `w_deps = 0.12` (dependency readiness -- new dimension)
- `w_wip = 0.08` (WIP balance -- light touch to avoid starving hot lanes)

**Implementation note:** This can stay in bash. Normalize each raw score to [0, 1], multiply by weight (integer math: multiply by 100, then divide). The current integer-based scoring is fine for Phase 1 -- normalized floats are a Phase 2 refinement.

---

## 3. WIP Limits and Little's Law

### 3.1 Little's Law Applied to Beads

Little's Law: **L = lambda * W** (items in system = arrival rate * cycle time). Equivalently: **Cycle Time = WIP / Throughput**.

For bead processing:
- **WIP** = count of `status=in_progress` beads across all agents
- **Throughput** = beads closed per hour (measurable from beads history)
- **Cycle Time** = average time from claim to close

If we have 3 agents and average cycle time is 2 hours, optimal WIP = 3 (one per agent). More than 3 in_progress beads means at least one is stale/abandoned or an agent is context-switching.

### 3.2 WIP Limit as Discovery Gate

**Proposed rule:** Before claiming a new bead, check global WIP:

```bash
ip_count=$(bd list --status=in_progress --json | jq 'length')
max_wip=${DISCOVERY_MAX_WIP:-5}  # configurable, default = expected_agents + 2 buffer

if [[ $ip_count -ge $max_wip ]]; then
    # Don't claim new work. Instead:
    # 1. Check if any in_progress beads are stale (claimed_at > TTL)
    # 2. If stale found, auto-release and claim that instead
    # 3. If no stale, wait or work on non-bead tasks (refactoring, docs)
fi
```

### 3.3 Per-Agent WIP Limit

An individual agent should never hold more than 1 bead. The current system enforces this implicitly (route.md Step 1 checks for active sprints and resumes them). Making it explicit:

```bash
my_beads=$(bd list --status=in_progress --assignee="${BD_ACTOR:-}" --json | jq 'length')
if [[ $my_beads -gt 0 ]]; then
    # Resume existing work, don't claim new
fi
```

### 3.4 Thrashing Prevention

Context-switching between beads is the primary throughput killer. Little's Law tells us: **reducing WIP with constant throughput reduces cycle time**. The concrete policy:

1. **Hard limit:** Agent WIP = 1 (already enforced by sprint resume logic)
2. **Soft limit:** Global WIP = N_agents + 2 (allows for TTL-expired stale claims)
3. **Stale reclaim:** If global WIP is at limit, prefer reclaiming stale beads over waiting

---

## 4. Thundering Herd Mitigation in Discovery Scan

### 4.1 The Problem

When N agents start simultaneously (e.g., `intermux` launches 3 panes), they all run `discovery_scan_beads()` at roughly the same time, see the same top-3 ranking, and all try to claim bead #1. Only one succeeds; the others fail, retry, and all grab bead #2. Worst case: N claims for N beads takes O(N^2) attempts.

### 4.2 Current Mitigation

The atomic `bd update --claim` prevents double-claiming. Failed agents re-run discovery. But this is wasteful -- each failed claim attempt costs ~200ms (Dolt round-trip) and delays the agent.

### 4.3 Weighted Random Selection (Lottery Scheduling)

Instead of always selecting the highest-scored bead, use **weighted random selection** where the probability of selecting bead_i is proportional to its score:

```
P(bead_i) = score_i / sum(all_scores)
```

This is the lottery scheduling approach from OS theory. With 3 agents and beads scored [90, 85, 80, 70], the top bead gets ~35% probability instead of 100%. Agents naturally spread across the top candidates.

**Implementation in bash:**

```bash
# After scoring, select from top-K candidates using weighted random
top_k=5  # consider top 5 candidates
scores=( $(echo "$results" | jq -r ".[0:$top_k] | .[].score") )
total=0; for s in "${scores[@]}"; do total=$((total + s)); done
roll=$((RANDOM % total))
cumulative=0
selected=0
for i in "${!scores[@]}"; do
    cumulative=$((cumulative + scores[i]))
    if [[ $roll -lt $cumulative ]]; then
        selected=$i
        break
    fi
done
```

### 4.4 Startup Jitter

Add random delay before first discovery scan on session start:

```bash
# In session-start.sh, before discovery_brief_scan
jitter_ms=$((RANDOM % 3000))  # 0-3 seconds
sleep "0.${jitter_ms}"
```

This is the standard exponential-backoff-with-jitter pattern from AWS architecture guidance. Full jitter (uniform random up to max) outperforms equal jitter and decorrelated jitter in practice.

### 4.5 Claim-Failure Jitter

When a claim fails, add jitter before re-scanning:

```bash
# In bead_claim() retry loop
jitter_ms=$((RANDOM % 2000 + 500))  # 0.5-2.5 seconds
sleep "0.${jitter_ms}"
```

### 4.6 Score Perturbation (Simpler Alternative to Weighted Random)

Instead of weighted random selection, add small random noise to scores before sorting:

```bash
# After computing score, add jitter of +/- 5 points
jitter=$(( (RANDOM % 11) - 5 ))
score=$((score + jitter))
```

This preserves the general priority ordering but breaks ties and near-ties randomly. A P0 bead (score ~90) will never be displaced by a P3 bead (score ~40), but two P1 beads within 10 points of each other will be selected with roughly equal probability.

**Recommendation:** Score perturbation is simpler and more predictable than weighted random. Use it for Phase 1, with the option to upgrade to weighted random if telemetry shows persistent herd behavior.

---

## 5. Rideshare Batched Matching

### 5.1 Lyft's Approach

Lyft holds unserved orders for a short batching window (e.g., 5 seconds), collects all available drivers, then runs optimal matching (Hungarian algorithm or RL-based) over the batch. The key tradeoff: longer windows = better matches but longer rider wait times.

### 5.2 Why Batched Matching Doesn't Fit

Batched matching requires a **central coordinator** that:
1. Collects all idle agents in a time window
2. Collects all available tasks
3. Runs global optimization (e.g., Hungarian algorithm for minimum-cost assignment)
4. Dispatches assignments to agents

Our constraint is **no inter-agent communication**. There is no central dispatcher. Each agent runs its own discovery scan independently.

### 5.3 Approximating Batch Matching Without Coordination

We can approximate the benefits of batched matching through **implicit coordination via shared state**:

1. **Claim timestamps as coordination signal:** When agent A claims bead #1, its `claimed_at` timestamp becomes visible to agent B's next discovery scan. If B scans within seconds of A's claim, it sees A's claim and skips to bead #2.

2. **Scan-before-claim pattern:** Already implemented. The 45-min TTL and -50 score penalty for claimed beads means agents naturally avoid each other's claims.

3. **The real gap:** The window between scan and claim. Agent A scans, sees bead #1 as unclaimed, but before it can claim, agent B also scans and also sees #1 as unclaimed. This is the classic TOCTOU race.

### 5.4 Mitigating TOCTOU Without a Coordinator

The combination of:
- **Score perturbation** (Section 4.6) -- agents likely pick different beads
- **Startup jitter** (Section 4.4) -- agents don't scan simultaneously
- **Atomic claim + retry** (existing) -- failed claims retry quickly

...is sufficient for our scale (3-8 concurrent agents). At 50+ agents, we'd need a proper coordinator. At 3-8, the probabilistic approach wastes at most 1-2 extra claim attempts per discovery cycle.

### 5.5 Cost Analysis

With 5 agents, score perturbation, and 0-3s startup jitter:
- **Best case:** All 5 agents select different beads. 5 claims, 5 successes. 0 wasted attempts.
- **Expected case:** 1-2 collisions. 5 claims, 3-4 successes, 1-2 retries. ~400ms extra latency for colliding agents.
- **Worst case (no jitter, no perturbation):** All 5 select bead #1. 5 claims, 1 success, 4 retries cascading. ~3-4 seconds total settle time.

The expected case is acceptable. No coordinator needed.

---

## 6. Dependency-Aware Scheduling

### 6.1 The Problem

Beads have parent-child relationships (`bd dep list`). Working on a child bead whose parent dependencies are still open is often wasted effort -- the parent may change scope, invalidating the child's work.

Conversely, beads whose **all dependencies are already closed** are "ready" in the DAG-scheduling sense (Kahn's algorithm: zero in-degree nodes are ready for execution).

### 6.2 Current Implementation

`_discovery_build_stale_parent_map()` already detects children of **closed** epics and penalizes them (-30 score, action=`verify_done`). This is the inverse problem -- it flags beads that should already be done.

The gap is the forward case: **boosting beads whose blockers are resolved**.

### 6.3 Dependency Readiness Score

For each bead, compute the fraction of its dependencies that are closed:

```bash
# deps_ready_score for bead $id
# Returns 0-100 (percentage of deps closed)
deps_ready_score() {
    local id="$1"
    local deps
    deps=$(bd dep list "$id" --direction=down --json 2>/dev/null) || { echo 100; return; }
    local total=$(echo "$deps" | jq 'length')
    [[ "$total" -eq 0 ]] && { echo 100; return; }  # No deps = fully ready
    local closed=$(echo "$deps" | jq '[.[] | select(.status == "closed")] | length')
    echo $(( closed * 100 / total ))
}
```

Integration into scoring (using the weight from Section 2.4):

```
norm_deps = deps_ready_score / 100  # [0.0, 1.0]
# Beads with all deps closed get full w_deps bonus
# Beads with 0/3 deps closed get 0 bonus
# Beads with 2/3 deps closed get 0.67 * w_deps bonus
```

### 6.4 Performance Concern

`bd dep list` is a Dolt query per bead. For 50 beads, that's 50 extra queries. Mitigation:

1. **Only check top-K candidates** (like `_discovery_flag_possibly_done` already does with top 10)
2. **Cache in ic state** with 5-minute TTL
3. **Batch query:** If bd supports it, query all deps at once (currently not supported, but could be added to bd CLI)

For Phase 1, checking only the top 10 candidates is sufficient. Cost: ~10 extra `bd dep list` calls, ~2 seconds total.

### 6.5 DAG-Aware Topological Boost

Beyond simple dependency readiness, prefer beads that **unblock the most downstream work**:

```
unblock_score = count of open beads that depend on this bead
```

A bead that unblocks 5 other beads is more valuable than one that unblocks 0, all else being equal. This is analogous to critical-path scheduling in project management.

**Phase 1 recommendation:** Implement `deps_ready_score` only. `unblock_score` requires reverse-dependency traversal which is expensive and better suited for Phase 2 when bd supports batch dependency queries.

---

## 7. Consolidated Design: The Selection Function

### 7.1 Algorithm

```
SELECT_BEAD(agent):
  1. FILTER: bd list --status=open (feasibility)
     - Exclude claimed beads (claimed_at < TTL)
     - Apply DISCOVERY_LANE if set (with lane-escape if empty)
     - Exclude beads where agent WIP >= 1

  2. SCORE: For each candidate (existing score_bead + extensions)
     - priority_score:       [0, 60]   (unchanged)
     - phase_score:          [0, 30]   (unchanged)
     - recency_score:        [0, 20]   (unchanged)
     - deps_ready_bonus:     [0, 12]   (NEW: 12 * fraction_deps_closed)
     - staleness_penalty:    -10       (unchanged)
     - claimed_penalty:      -50       (unchanged)
     - parent_closed_penalty: -30      (unchanged)
     - interject_penalty:    -15       (unchanged)
     - score_perturbation:   [-5, +5]  (NEW: RANDOM jitter)

  3. RANK: Sort by score DESC, id ASC (deterministic tiebreaker)

  4. PRESENT: Top 3 to user (interactive) or auto-select top 1 (autonomous)

  5. CLAIM: bd update <id> --claim
     - Success: proceed
     - Failure: jitter 0.5-2.5s, re-run from step 1
```

### 7.2 What Changes from Current lib-discovery.sh

| Change | Effort | Impact |
|---|---|---|
| Add `deps_ready_bonus` (top-10 only) | Medium | Prevents wasted work on blocked beads |
| Add score perturbation (+-5 jitter) | Trivial | Breaks thundering herd at near-zero cost |
| Add startup jitter in session-start.sh | Trivial | Staggers initial discovery scans |
| Add claim-failure jitter in bead_claim() | Trivial | Prevents retry synchronization |
| Add lane-escape fallback | Small | Improves utilization when lanes are empty |
| Add global WIP check before claim | Small | Prevents overloading the system |

### 7.3 What Does NOT Change

- The `score_bead()` function structure (additive multi-factor)
- The `discovery_scan_beads()` pipeline (scan -> score -> sort -> present)
- The `bd update --claim` atomic claiming
- The 45-min heartbeat TTL
- The top-3 presentation to user

### 7.4 Autonomous Mode (Self-Dispatch Loop)

For Phase 1 self-dispatch (no human in the loop), the selection changes:

```
# Instead of AskUserQuestion with top 3:
auto_select = results[0]  # After perturbation, this is probabilistically distributed
bd update "${auto_select.id}" --claim || { sleep_with_jitter; retry; }
```

The score perturbation is critical here -- without it, all autonomous agents would always select the same bead.

---

## 8. Open Questions for Phase 2

1. **Agent capability profiles:** Should agents declare capabilities (e.g., "can handle Go code", "good at research") that influence scoring? This would require agent-specific scoring weights.

2. **Learning from outcomes:** Can we use `discovery_log_selection` telemetry to tune weights? E.g., if beads selected at phase=`planned` close faster than those at `brainstorm`, increase `w_phase`.

3. **Predictive demand:** Like Lyft's demand forecasting, can we predict which beads will become urgent based on epic deadlines or dependency chains?

4. **Batch dependency queries:** Adding `bd dep list-all --status=open` to avoid N+1 queries for dependency scoring.

5. **Central coordinator (at scale):** If agent count exceeds ~10, the probabilistic approach may not be sufficient. A lightweight coordinator (Redis-based or file-based lock) could batch-assign beads. But this is well beyond Phase 1 scope.

---

## Sources

- [Nomad Scheduling: How It Works](https://developer.hashicorp.com/nomad/docs/concepts/scheduling/how-scheduling-works) -- feasibility + ranking two-phase architecture
- [Nomad rank.go](https://github.com/hashicorp/nomad/blob/main/scheduler/rank.go) -- bin-packing score normalization, MaxScoreIterator
- [Kubernetes Scheduling Framework](https://kubernetes.io/docs/concepts/scheduling-eviction/scheduling-framework/) -- plugin-based Filter/Score/NormalizeScore pipeline
- [Kubernetes Scheduling Policies](https://kubernetes.io/docs/reference/scheduling/policies/) -- predicates and priorities (legacy, pre-v1.23)
- [CBBA: Consensus-Based Bundle Algorithm](https://acl.mit.edu/projects/consensus-based-bundle-algorithm) -- decentralized auction with convergence proofs
- [Multi-agent task allocation via cost-effectiveness auction](https://www.frontiersin.org/articles/10.3389/fphy.2025.1617607/full) -- capability-fitness modeling in multi-round auctions
- [Decentralized adaptive task allocation](https://www.nature.com/articles/s41598-025-21709-9) -- two-layer architecture for dynamic assignment under partial observability
- [Lyft dispatch: Solving Dispatch in a Ridesharing Problem Space](https://eng.lyft.com/solving-dispatch-in-a-ridesharing-problem-space-821d9606c3ff) -- batched matching with Hungarian algorithm
- [Lyft RL matching](https://arxiv.org/pdf/2310.13810) -- online reinforcement learning for rider-driver matching
- [Little's Law and Kanban](https://getnave.com/blog/kanban-littles-law/) -- WIP / throughput / cycle time relationship
- [WIP Limits in Kanban](https://teachingagile.com/kanban/introduction/kanban-wip-limits) -- Toyota Production System origins, focus-on-finish
- [Thundering Herd: Exponential Backoff with Jitter](https://medium.com/@avnein4988/mitigating-the-thundering-herd-problem-exponential-backoff-with-jitter-b507cdf90d62) -- full/equal/decorrelated jitter strategies
- [Starvation and Aging in OS Scheduling](https://www.geeksforgeeks.org/starvation-and-aging-in-operating-systems/) -- lottery scheduling, priority aging
- [Topological Sort for Dependency Resolution](https://brunoscheufler.com/blog/2021-11-27-scheduling-tasks-with-topological-sorting) -- Kahn's algorithm for DAG-based task scheduling

<!-- flux-research:complete -->
