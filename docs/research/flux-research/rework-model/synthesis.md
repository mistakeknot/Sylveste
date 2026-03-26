# Rework Model Synthesis: Manufacturing-Inspired Disposition Taxonomy for AI Agent Output

**Research synthesis date:** 2026-03-19
**Input agents:** 7 flux-drive research documents
**Research question:** How should an AI software factory handle agent output failures using a manufacturing-inspired rework taxonomy, and what patterns from interlab/autoresearch inform the orchestration model?

---

## Executive Summary

The seven research documents converge on a unified model for handling AI agent output failures:

1. **Disposition taxonomy (6 states)** — adapted from manufacturing MRBs: scrap, rework, repair (use-as-is), return to vendor, downgrade, deviation. These replace naive pass/fail gates with nuanced quality decisions grounded in cost economics.

2. **CUJ three-state gates (pass/marginal/fail)** — marginal decomposes into usable (known good, accepted intentionally) and risky (insufficient evidence). Authority tiers directly constrain disposition decisions: high-verifiability signals grant local authority; low-verifiability signals escalate to humans.

3. **Cost economics driving dispositions** — rework breaks even only when salvage ratio > 50%; scrap is preferred for architectural defects (salvage < 30%); quarantine is expensive (blocked downstream work) and must have a time ceiling; use-as-is must accumulate findings with systemic review triggers.

4. **Interlab/autoresearch patterns informing orchestration** — campaign-as-intent (metric + scope + constraints), iterative keep/discard loops with circuit breakers, metric-driven stopping ("good enough" not maximization), parallel decomposition with file-scope conflict detection, and mutation store enabling compound learning across beads.

5. **Top 5 actionable recommendations** — implement quarantine-to-disposition SLAs with auto-defaults, cost-of-quality metrics with disposition events schema, disposition authority matrix with escalation rules, multi-campaign orchestration with scope isolation, and institutional memory (mutation store) for agent learning.

---

## 1. Recommended Disposition Taxonomy

### 1.1 Six Disposition States

Adopted directly from manufacturing MRB practice ([fd-manufacturing-disposition-taxonomy](./fd-manufacturing-disposition-taxonomy.md), Section 2.2):

| Disposition | Definition | Authority Required | Cost Profile | When Preferred |
|---|---|---|---|---|
| **Scrap** | Discard output; restart from scratch | Execute (T0) for own work, Commit (T1+) for others | 100% fresh generation cost | Architectural defect, salvage ratio < 0.3 |
| **Rework** | Targeted correction to existing output | Execute (T0) with retry budget, escalates after 3 attempts | 20-40% of fresh generation (localized fix) | Known good approach, wrong details |
| **Repair (Use-As-Is)** | Accept with known deficiency; manual patches acceptable | Commit (T2) + dual-key review (second authority required) | Near-zero immediate cost, high downstream risk | Deviation is non-critical path, probability of failure × cost < rework cost |
| **Return to Vendor (Reassign)** | Upstream failure, not agent failure | Escalation to next authority tier | Rework cost on different agent | Input quality poor, ambient context corrupt, tool/API degraded |
| **Downgrade/Regrade** | Accept for reduced-scope use | Requester decision (cost-benefit: reduced value acceptable vs. rework cost) | Cost of communicating reduced spec | Original spec too ambitious for budget remaining |
| **Deviation (Waiver)** | Change the spec itself rather than the output | Minor (T2 domain owner), Major (T3 Deploy), Critical (human only) | 500-2K tokens documentation + amortized benefit if rule triggers >3x again | Spec was wrong, not output; rule is too strict |

### 1.2 State Transitions

**Hard-gated quarantine workflow** (from [fd-manufacturing-disposition-taxonomy](./fd-manufacturing-disposition-taxonomy.md), Section 5.1-5.3):

```
[Agent generates output]
        ↓
[Automated inspection] ──pass──> [Release to consumer]
        │
       fail
        ↓
[Quarantine: severity classification]
        ↓
    ┌───┴───┬───────┐
  Minor   Major   Critical
    ├──→   ├──→    └─→
   L0/1   L2      L3 Full MRB
  auto    review  (escalated)
    │      │       │
    └──────┴───────┘
         ↓
[Disposition decision]
    │  │  │  │
    │  │  │  └─ RTV: Fix upstream
    │  │  └──── Scrap: Discard
    │  └─────── Repair: Patch manually
    └────────── Rework: Retry | Use-As-Is: Accept
         ↓
[Verify & release]
         ↓
[Record metrics + check CAPA triggers]
```

**Quarantine states:**
- `PENDING_INSPECTION` → `RELEASED` (passed auto checks)
- `PENDING_INSPECTION` → `QUARANTINED` (failed auto checks)
- `QUARANTINED` → `REWORK_IN_PROGRESS` (rework disposition)
- `QUARANTINED` → `RELEASED_WITH_DEVIATION` (use-as-is disposition)
- `QUARANTINED` → `SCRAPPED` (scrap disposition)
- `QUARANTINED` → `RTV` (return to vendor)
- `REWORK_IN_PROGRESS` → `PENDING_REINSPECTION` (rework complete, re-running gates)
- `PENDING_REINSPECTION` → `RELEASED` (rework validated) or `QUARANTINED` (rework failed, re-quarantine)

**Rework limits** (from [fd-manufacturing-disposition-taxonomy](./fd-manufacturing-disposition-taxonomy.md), Section 5.3):
- Max 3 rework iterations per task (configurable). After 3 failures, force escalation to human review or scrap.
- Rework budget ceiling: if cumulative rework token cost > 3x original generation cost, auto-scrap.
- Rework-on-rework detection: if rework introduces new defects, escalate severity by one tier.

---

## 2. Integration with CUJ Three-State Gates and Authority Tiers

### 2.1 Marginal State Semantics

From [fd-cuj-rework-integration](./fd-cuj-rework-integration.md), Section 1.2:

| Marginal Sub-State | Meaning | Authority Disposition |
|---|---|---|
| **Marginal-Usable** | Output known to work but known suboptimal (coverage dropped 3% below target, diff correct but inconsistent style) | Can proceed with logged finding; escalate only to accumulation ledger |
| **Marginal-Risky** | Might work but evidence insufficient (edge-case coverage absent, LLM-as-judge at 0.62 confidence on 0.60 threshold) | Must quarantine; escalate to disposition authority |

**Epistemic criterion:** Usable = certainty about known deficiency. Risky = uncertainty about whether deficiency exists.

### 2.2 Signal Tier × Disposition Authority Matrix

From [fd-cuj-rework-integration](./fd-cuj-rework-integration.md), Section 2.1:

| Signal Tier | T0 (Observe) | T1 (Suggest) | T2 (Allowlist Auto) | T3 (Full Auto) |
|---|---|---|---|---|
| **Deterministic fail** | Log only | Log + notify | Auto-reject, create rework bead | Auto-reject, create rework |
| **Threshold marginal** | Log | Log + recommend | Self-disposition if usable; escalate if risky | Self-disposition both; log rationale |
| **Trend marginal** | Log | Log + recommend | Escalate all (process-scope) | Escalate all (process-scope) |
| **Heuristic marginal** | Log | Log + evidence | Escalate all | Self-disposition usable (3+ criteria pass); escalate risky |
| **Judgment marginal** | Log | Log + panel votes | Escalate all | Escalate all |

**Key rule:** Even T3 agents cannot self-disposition trend or judgment marginals. Trends indicate systemic issues; judgment disagreement means measurement itself is inconclusive.

### 2.3 Escalation to Disposition Authority

From [fd-authority-rework-routing](./fd-authority-rework-routing.md), Section 4-5:

**Disposition authority by type** (from existing action classes):

| Disposition | Minimum Action Class | Minimum Tier | Domain Scope | Examples |
|---|---|---|---|---|
| Scrap (own) | Execute | T0 | Same domain | Agent abandons its own output |
| Scrap (other's) | Commit | T2 | Same domain | One agent decides another's work is unsalvageable |
| Rework (self) | Execute | T0 | Same domain | Auto if within retry budget |
| Rework (reassign) | Commit | T1 | Parent domain+ | When original exhausted retries |
| Use-As-Is | Commit | T2 | Domain + blast-radius | Always requires dual-key (second authority) |
| Deviation (minor) | Commit | T2 | Domain owning spec | Spec owner (or co-signer) approval |
| Deviation (major) | Deploy | T3 | Cross-domain safety-relevant | Principal approval |
| Deviation (critical) | — | — | — | **Human-only, no agent delegation** |

---

## 3. Cost Economics of Disposition Decisions

### 3.1 Cost-of-Quality Framework

From [fd-rework-cost-accounting](./fd-rework-cost-accounting.md), Section 1:

**COQ categories mapped to tokens:**

| Category | Manufacturing | AI Agent Cost | Demarch Example |
|---|---|---|---|
| **Prevention** | Process design, training | Prompt engineering, guardrails, gate design | `lib-routing.sh`, gate configs, skill authoring |
| **Appraisal** | Inspection, testing | Output validation, test execution | Interspect hooks, tool-selection-events |
| **Internal Failure** | Scrap, rework before ship | Discarded generations, retry loops | Rework dispositions, re-routing |
| **External Failure** | Warranty, recalls | Merged bad patches, broken builds, user-facing defects | Bead rollback, revert commits |

**Fundamental insight:** In manufacturing, prevention + appraisal investments reduce failure costs. The same applies: spending tokens on validation reduces expected downstream failure cost, but only up to a point (the COQ optimum).

### 3.2 Disposition Cost Model

From [fd-rework-cost-accounting](./fd-rework-cost-accounting.md), Sections 2-5:

#### Scrap Economics

**Cost model:** `C_scrap = C_fresh_generation` (sunk cost of original is irrelevant)

**When optimal:** Salvage ratio < 0.3, architectural defect, context pollution (flawed reasoning in context window biases rework)

**Unique to agents:** Context pollution premium — unlike manufacturing, scrapping gives the benefit of a clean context window. Rework carries original flawed reasoning forward, biasing subsequent generations.

#### Rework Economics

**Cost model:** `C_rework = C_diagnosis + C_correction + C_re_validation` (typically 20-40% of fresh generation)

**Break-even formula:** Rework preferred when:
```
C_diagnosis + C_correction + C_re_validation < C_fresh_generation × (1 - salvage_ratio)
```

**Salvage ratio by defect type:**
| Defect Type | Salvage Ratio | Preferred |
|---|---|---|
| Wrong approach/architecture | 0.0-0.1 | Scrap |
| Correct approach, wrong details | 0.5-0.8 | Rework |
| Minor formatting/style | 0.9-0.95 | Rework |
| Off-by-one, typo | 0.95+ | Rework |
| Hallucinated dependency | 0.3-0.6 | Depends |

**Rework circuit breaker:** If first correction attempt fails validation, escalate to scrap rather than entering unbounded retry loop. (Research shows 10-cycle loops consume 50x single-pass tokens.)

#### Quarantine Economics

**Cost model:** `C_quarantine = C_holding + C_eventual_disposition + C_blocked_downstream`

**Dominant cost in agent systems:** Blocked downstream beads. When bead A's output is quarantined and beads B, C, D depend on A, the effective cost is idle-time of B + C + D.

**Estimated quarantine cost per hour:**
```
C_per_hour = N_blocked_beads × avg_bead_cost × opportunity_cost_rate
           ≈ 1-3 blocked × $2.93 × 0.1/hour = $0.29-0.88/hour
```

**Decision rule:** Quarantine is rational only when defect classification is genuinely ambiguous AND additional info is expected soon. **Hard ceiling: 24h maximum, then auto-scrap.** Without ceiling, quarantine becomes default indecision.

#### Use-As-Is Economics

**Cost model:** `C_use_as_is = C_documentation + P(failure) × C(failure)`

**Expected-value calculation:** Accept deviation if probability of downstream failure × cost of that failure < cost of rework.

**Risk tracking:** Use-as-is decisions compound. Each individual deviation may be tolerable, but 10 accepted deviations create a debt surface making future rework more expensive (broken-windows effect). Counter/threshold required to trigger mandatory cleanup.

#### Deviation Economics

**Cost model:** `C_deviation = C_review + C_documentation + C_spec_update + C_future_confusion`

**When optimal:** Spec was wrong, not output. If a rule triggers >3 times and the output was right each time, deviation + rule update saves tokens.

**Token economics:**
- Immediate: ~500-2K tokens for review + documentation
- Amortized benefit: prevents N future false dispositions at 5K-50K tokens each
- Break-even: triggers >3 times = tokens saved

### 3.3 Schema for Cost Tracking

From [fd-rework-cost-accounting](./fd-rework-cost-accounting.md), Section 6:

**New `disposition_events` table** (extends `interstat` schema):
```sql
CREATE TABLE disposition_events (
  id INTEGER PRIMARY KEY,
  timestamp TEXT NOT NULL,
  bead_id TEXT NOT NULL,
  disposition TEXT NOT NULL,  -- 'scrap'|'rework'|'quarantine'|'use_as_is'|'deviation'
  defect_type TEXT,           -- 'wrong_approach'|'wrong_detail'|'style'|'hallucination'|'test_failure'
  severity TEXT,              -- 'p0'|'p1'|'p2'|'p3'
  tokens_spent_before INTEGER,
  tokens_spent_on_disposition INTEGER,
  wall_ms_before INTEGER,
  wall_ms_on_disposition INTEGER,
  quarantine_start TEXT,
  quarantine_end TEXT,
  rework_attempt INTEGER DEFAULT 1,
  final_outcome TEXT,         -- 'accepted'|'scrapped_after_rework'|'escalated'
  authority_level TEXT,       -- 'agent'|'gate'|'human'
  gate_id TEXT,
  agent_run_id INTEGER
);
```

**New cost-query.sh modes:**
- `disposition-summary` — count + avg cost by type
- `rework-ratio` — rework tokens / total tokens (quality metric)
- `quarantine-duration` — avg/p50/p90 hold time
- `scrap-vs-rework-breakeven` — empirical break-even from actual data
- `disposition-by-gate` — which gates trigger which dispositions

**Critical metric:** `wasted_rework_count` — dispositions where rework was attempted but ultimately scrapped. Pure waste signal.

---

## 4. Interlab/Autoresearch Patterns Informing Orchestration

### 4.1 Pattern 1: Campaign-as-Intent

From [interlab-autoresearch-patterns](./interlab-autoresearch-patterns.md), Section 1:

**Intent directive = (metric, direction, scope, constraints, stopping_criteria)**

| Intent Component | Karpathy/autoresearch | Interlab | Factory Translation |
|---|---|---|---|
| **Metric** | `val_bpb` (validation bits/byte) | `metric_name` + direction | CUJ health signal (latency p95, coverage %, scrap rate) |
| **Direction** | "Lower" | "improve" / "maintain" | Rework taxonomy category: improve, fix-regression, maintain-threshold |
| **Scope** | `no prepare.py changes` (file constraints) | `files_in_scope` | Modules/domains (prevents cross-intent interference) |
| **Constraints** | 5-min budget, no simplicity violations | Circuit breaker limits | Hard invariants (tests pass, API contracts, budget ceiling) |
| **Stopping Criteria** | Manual (human stops agent) | max_experiments, max_crashes, max_no_improvement | Threshold-based: "get metric below X" OR convergence OR budget exhausted |

**Key insight:** Intent is always a **specification** (what needs to be better, how to measure it), never a **strategy** (the agent discovers strategy at runtime).

**Factory application:** Create well-formed intent directives. The agent discovers how. Factory never needs to know *how* — only *what* to target and *how to measure it*.

### 4.2 Pattern 2: Keep/Discard Loop with Circuit Breakers

From [interlab-autoresearch-patterns](./interlab-autoresearch-patterns.md), Section 2:

**Core loop (both systems identical):**
```
while not stopped:
    hypothesis = agent.think(context, history)
    change = agent.edit(codebase)
    result = benchmark(change)
    if improved(result, best):
        keep(change)      # commit
    else:
        discard(change)   # revert
```

**Critical design choices:**
1. **One change per iteration** — "Never bundle. You need to know what caused the shift."
2. **Automatic revert on discard** — agent never manually handles git
3. **Crash = discard + escalation** — crash is experiment result, not error to debug
4. **Agent never asks "should I continue?"** — loop runs autonomously until exit condition fires. Human attention is scarcest resource.

**Mapping to rework dispositions:**

| Experiment Outcome | Rework Equivalent | Factory Action |
|---|---|---|
| **Keep** (metric improved) | Successful iteration | Bead closes with improvement evidence |
| **Discard** (metric regressed) | Failed attempt | Revert, try different approach |
| **Crash** (benchmark failed) | Broken attempt | Count toward circuit breaker |
| **Converged** (no improvement) | Diminishing returns | Mark directive "good enough"; move budget elsewhere |

### 4.3 Pattern 3: Metric-Driven Stopping ("Good Enough")

From [interlab-autoresearch-patterns](./interlab-autoresearch-patterns.md), Section 3:

**Autoresearch systems:**
- **karpathy:** Fixed time budget (5 min/experiment), no explicit stopping
- **interlab:** Three independent circuit breakers:
  - `max_experiments` (default 50) — total budget
  - `max_crashes` (default 3) — crash tolerance
  - `max_no_improvement` (default 10) — convergence detection

**Factory needs layered stopping:**

1. **Per-bead timeout** (= per-experiment time budget) — If single work unit takes >X, it's stuck. Kill, mark crash, try different approach.
2. **Per-sprint convergence** (= max_no_improvement) — If N consecutive beads don't move target CUJ, sprint hit diminishing returns. Stop and synthesize.
3. **Per-sprint budget** (= max_experiments) — Hard cap on iterations.
4. **Cross-sprint health** — If no CUJ improved across active sprints for M cycles, stuck at local optimum. Escalate for strategy re-evaluation.
5. **Threshold-based success** — Once metric crosses threshold, done. Don't maximize past "good enough" (critical difference from autoresearch).

### 4.4 Pattern 4: Parallel Decomposition with Scope Isolation

From [interlab-autoresearch-patterns](./interlab-autoresearch-patterns.md), Section 4:

**Interlab multi-campaign architecture:**

1. **Plan phase:** Agent decomposes goal into campaigns. Each gets: metric, benchmark, file_scope, dependencies. Tool validates **file conflict detection** — rejects plans where parallel campaigns share files without dependency edges.

2. **Dispatch phase:** Campaigns with unmet dependencies queued; independent campaigns dispatched as subagents. One subagent per campaign.

3. **Monitor phase:** Orchestrator polls for progress. Cross-campaign insights propagated via ideas files.

4. **Synthesize phase:** Aggregate results, cross-campaign insights, recommendations.

**Factory mapping:**

| Concept | Factory Equivalent | Constraint |
|---|---|---|
| Parent bead (epic) | Sprint objective / CUJ target | Budget allocation |
| Child beads (campaigns) | Individual work items | One agent per bead |
| files_in_scope | Module ownership | No concurrent modification of shared state |
| depends_on edges | Sequential dependencies | Serialization enforced |
| Conflict detection | File/module contention detection at plan time | Rejects overlapping scopes without edges |
| Insight propagation | Agent-to-agent learning | Without direct interference |
| Synthesis | Sprint retrospective | Aggregate metrics, patterns, dead ends |

**Critical lessons:**
- File scope isolation enforced *structurally*, not by convention.
- Concurrent modification of shared state = primary failure mode.
- "Promote promising ideas to larger scale" pattern: cheap exploration first, expensive validation after.

### 4.5 Pattern 5: Compound Learning via Mutation Store

From [interlab-autoresearch-patterns](./interlab-autoresearch-patterns.md), Section 6:

**Interlab's three-layer memory:**

1. **Within-campaign:** `interlab.md` (living doc updated each iteration) + `interlab.ideas.md` (hypothesis backlog)
2. **Cross-campaign:** Mutation store (SQLite) — records every approach with provenance: task_type, hypothesis, quality_signal, is_new_best, inspired_by
3. **Cross-session:** Interlock broadcast — agents share discoveries in real-time; inspired_by field tracks genealogy

**Factory mutation store:**
- Every bead outcome is a mutation: what tried (hypothesis), what happened (quality_signal), whether new best, what inspired approach
- Before starting new bead: query mutation store. "Has anyone tried this for this type of problem? What worked? What failed?"
- Genealogy tracking enables accountability and pattern discovery
- Turns individual agent experience into collective intelligence
- Factory needs both mutation-level and campaign-level synthesis

---

## 5. Top 5 Actionable Recommendations

### Recommendation 1: Implement Quarantine-to-Disposition SLAs with Auto-Defaults

**Rationale:** ISO 9001 Clause 8.7 requires nonconforming outputs be "prevented from unintended use or delivery." Extended quarantine blocks downstream work. Auto-defaults prevent indecision.

**Implementation:**

| Gate Outcome | SLA | Auto-Default if Missed |
|---|---|---|
| **Fail (deterministic)** | Immediate | Auto-reject, create rework bead |
| **Fail (threshold)** | 1 hour | Escalate to disposition authority |
| **Fail (heuristic/judgment)** | 4 hours | Escalate for human review |
| **Marginal-Risky** | 4 hours | Auto-rework (conservative) |
| **Marginal-Usable** | No quarantine | Auto-accept with finding logged |

**SLA breach escalation:**
- SLA + 0: Alert to bead owner and sprint lead
- SLA + 2h: Auto-escalate to process owner; highlight in dashboard
- SLA + 8h: Auto-disposition (marginal-risky → rework; failed → scrap)

**Benefit:** Quarantine never becomes permanent limbo. System defaults to action over indecision.

---

### Recommendation 2: Cost-of-Quality Metrics with Disposition Events Schema

**Rationale:** Quality costs are invisible without tracking. The COQ framework enables cost-driven disposition decisions.

**Implementation:**

Add `disposition_events` table to interstat schema (see Section 3.3). Extend cost-query.sh with:
- `disposition-summary` — disposition counts and average costs
- `rework-ratio` — internal failure cost as % of total
- `wasted-rework-count` — rework attempts that ended in scrap (pure waste signal)
- `quarantine-duration-p90` — bottleneck indicator
- `scrap-vs-rework-breakeven` — empirical threshold for disposition choice

**Dashboard signals:**
- **Rework overhead >30%:** Gate too strict OR agent capability declining
- **Wasted rework >15%:** Scrap-vs-rework heuristic miscalibrated
- **Quarantine p90 >4h:** Disposition authority bottleneck
- **Use-as-is rate >8%:** Threshold may be too permissive; audit debt accumulation

**Benefit:** Every disposition decision links to cost. Factory optimizes for minimum total cost, not minimum rework count.

---

### Recommendation 3: Disposition Authority Matrix with Explicit Escalation Rules

**Rationale:** Manufacturing MRBs work because authority is clear. Ambiguous authority leads to rubber-stamping or analysis paralysis.

**Implementation:**

Adopt the authority matrix from [fd-authority-rework-routing](./fd-authority-rework-routing.md), Section 3.1-3.2:

**Authority rules:**
- **Scrap own work:** T0 Execute always permitted (stop-digging principle)
- **Scrap others' work:** T1+ Commit required + review evidence
- **Rework self:** T0 Execute if retry budget < 3
- **Rework reassign:** T1 Commit in parent domain
- **Use-As-Is:** T2 Commit + dual-key required (second independent authority)
- **Deviation minor:** T2 domain owner approval
- **Deviation major:** T3 Deploy approval
- **Deviation critical:** Human principal only

**Escalation triggers (mandatory):**
- Retry budget exhausted (3 attempts)
- Blast radius > "moderate"
- Test regression in unrelated module
- Cost exceeds bead budget by >50%
- Safety-relevant domain
- Spec ambiguity discovered
- Conflicting review signals
- Agent confidence below threshold

**Benefit:** Clear governance prevents deadlock. Escalation is structural, not discretionary.

---

### Recommendation 4: Multi-Campaign Orchestration with Module-Scope Isolation

**Rationale:** Parallel work accelerates factories. File conflict detection prevents silent data races.

**Implementation:**

Adopt interlab's multi-campaign model with these additions:

1. **Plan phase:** When spawning parallel beads (within a sprint), validate that modules_in_scope are disjoint or connected by explicit dependency edges. Reject overlapping scopes without edges.

2. **Dispatch phase:** One agent per bead. Beads with unmet dependencies queued.

3. **Mutation propagation:** When bead A finds a winning approach for task_type X, broadcast to ideas files of parallel beads working on X. Let them discover and decide.

4. **Synthesis phase:** Aggregate per-bead metrics into sprint retrospective. Identify: what patterns worked? What dead ends? What compound learnings?

**Conflict detection algorithm:**
```
for each pair of parallel beads (A, B):
  if modules_in_scope(A) ∩ modules_in_scope(B) ≠ ∅:
    if no dependency edge A→B or B→A:
      REJECT plan
```

**Benefit:** Eliminates silent merge conflicts and interference bugs. Enables 2-4x parallel throughput vs. sequential.

---

### Recommendation 5: Institutional Memory (Mutation Store) for Agent Learning

**Rationale:** Agents rediscover known dead ends. Mutation store gives collective intelligence to the fleet.

**Implementation:**

Extend interstat with `mutation_outcomes` table:
```sql
CREATE TABLE mutation_outcomes (
  id INTEGER PRIMARY KEY,
  timestamp TEXT NOT NULL,
  bead_id TEXT NOT NULL,
  task_type TEXT NOT NULL,        -- 'latency-optimization', 'coverage-fix', 'api-design', ...
  hypothesis TEXT NOT NULL,       -- what was tried
  quality_signal REAL,            -- metric delta (positive = improvement)
  is_new_best BOOLEAN,
  inspired_by TEXT,               -- prior bead_id or session_id (genealogy)
  outcome TEXT                    -- 'keep'|'discard'|'crash'
);
```

**Agent query before starting bead:**
```bash
# Search mutation store for similar task types + hypotheses
SELECT hypothesis, outcome, quality_signal, inspired_by
FROM mutation_outcomes
WHERE task_type = ?
  AND timestamp > (now - 7 days)
ORDER BY quality_signal DESC;
```

**Genealogy tracking:**
- Each bead records `inspired_by` (which prior work inspired this approach)
- Query: "Trace lineage of winning idea X back to origin" → shows how insights evolved across agents

**Benefits:**
1. Avoids rediscovery of dead ends
2. Accelerates convergence by seeding good hypotheses
3. Enables genealogy queries for accountability and pattern discovery
4. Turns individual agent experience into collective intelligence
5. Empirical evidence of "which approaches work for which problem classes"

**Cross-sprint learning:** At sprint retrospective, synthesize: "Across all beads, which hypotheses had >0.5 median quality_signal? Those become default first-attempts next sprint."

---

## 6. VFX Disposition Model Insights

From [fd-film-vfx-revision-pipelines](./fd-film-vfx-revision-pipelines.md):

The VFX industry has solved many rework problems at scale. Key patterns:

### Multi-Tier Review (Section 3)
- **Internal dailies (Tier 1):** Fast, low-ceremony feedback. Artist iterates same day.
- **Client review (Tier 2):** Slow, high-ceremony. Rejection more expensive.
- **Parallel quality streams:** Proxy/WIP playblasts for cheap review; full-quality renders only after direction approved.

**Factory translation:** Don't waste expensive human review on outputs that would fail cheap automated checks. Gate before gate.

### CBB Pattern (Section 2)
- **CBB ("Could Be Better"):** Approved for use but remains on improvement list if budget permits.
- Captures middle ground between hard-reject and unconditional-accept.

**Factory translation:** When iteration budget is exhausted, accept all CBB-status outputs as final rather than forcing rework on diminishing returns.

### Escalation Ladder (Section 6)
- Artist self-review → Lead pre-filter → Dailies notes → Reassignment → Supervisor takeover → Approach change → Creative redirect → Omit/simplify
- Budget-aware: escalate when cost exceeds N×estimate

**Factory translation:** Each escalation level costs more. Auto-escalate when cumulative cost exceeds original estimate.

### Omit/Reinstate Pattern (Section 5)
- Omit is **distinct from failure.** Shot became unnecessary (requirements changed).
- Omit is **reversible.** Preserves all work; shot can return to prior status when re-instated.

**Factory translation:** When task requirements change, mark status as "omitted" not "scrapped." Preserve work products; resumption is possible.

---

## 7. CI/CD Rework Lessons

From [fd-cicd-failure-modes](./fd-cicd-failure-modes.md):

### Good vs. Bad Failures (Section 1)
- **Good failures:** Inspection catching defects at point of introduction. High signal.
- **Bad failures:** Flaky tests, infra crashes, measurement error. Low signal.

**Factory translation:** Apply RFM analysis (Recency, Frequency, Monetary cost) to distinguish signal from noise. Quarantine bad failures, investigate signal failures.

### Hidden Factory (Section 3.4)
- In CI/CD: flaky test investigation, CI debugging, retry loops, rollback coordination
- In agent factories: rework investigation, prompt debugging, disposition delays

**Detection signals:**
- High retry rates (2-3x before passing)
- Long PR cycle times despite fast test execution
- Developer learned helplessness ("just re-run it")

### Rollback vs. Forward-Fix (Section 2.2)
- Rollback cost: MTTD + execution time + rework penalty (change still lands later)
- Forward-fix cost: pipeline moratorium + rushed code + extended degradation

**Factory translation:** For disposition decisions: scrap (equivalent to rollback) costs fresh generation but buys clean context. Rework (forward-fix) is cheaper upfront but carries context risk.

---

## 8. Interplay of Disposition, CUJ Gates, and Cost Metrics

### The Feedback Loop

```
[Agent produces output]
        ↓
[CUJ gate(s) evaluate with signal tier + marginal sub-state]
        ↓
[Marginal/fail → Quarantine with evidence record]
        ↓
[Signal tier + authority tier determine who can self-disposition]
        ↓
[If escalation triggered → Disposition authority decides: scrap/rework/use-as-is/deviation/quarantine]
        ↓
[Disposition event logged with cost accounting]
        ↓
[Metrics accumulated → triggers CAPA if thresholds crossed]
        ↓
[Mutation store updated with outcome + genealogy]
        ↓
[Next agent queries mutation store before attempting similar task]
```

### Cost-Driven Authority Coupling

When a marginal-risky output is detected:
1. **Immediate:** Evidence record captures measurement + confidence interval
2. **Authority check:** Signal tier determines who can disposition
3. **Escalation:** If no qualified agent available, escalate to human
4. **Cost estimation:** For rework, estimate cost based on defect_type + salvage_ratio
5. **Disposition:** Authority decides rework vs. scrap vs. use-as-is based on cost-benefit
6. **Outcome:** Token cost tracked; contributes to COQ metrics

Example flow:
- **Scenario:** Heuristic-tier marginal (LLM confidence 0.62 on 0.60 threshold)
- **Authority:** Requires human review (heuristic signals don't grant agent self-disposition per Section 2.2 matrix)
- **Cost estimate:** Defect_type="test_failure", salvage_ratio=0.7 → rework cost ≈ 25% of fresh generation
- **Decision:** Human reviews evidence; if low risk of downstream failure, approves rework. If risk high, approves scrap.
- **Outcome:** Recorded in disposition_events; contributes to rework_ratio metric

---

## 9. Design Decisions Summary

### Decisions Made (from all documents)

1. ✓ **Six dispositions, not two.** Pass/fail misses the nuance that VFX/manufacturing capture.
2. ✓ **Marginal splits into usable/risky.** Epistemic uncertainty (risky) ≠ known minor deficiency (usable).
3. ✓ **Signal tier constrains authority.** Low-verifiability signals require human disposition.
4. ✓ **Three-attempt rework budget.** Beyond 3, probability of self-correction approaches zero.
5. ✓ **Quarantine has time ceiling.** 24h maximum (configurable per domain), then auto-scrap or escalate.
6. ✓ **Conservative SLA defaults.** Expired quarantine auto-dispositions toward rework/scrap, never acceptance.
7. ✓ **Use-As-Is requires dual-key.** Never a single authority accepting known deficiency; separation of duties.
8. ✓ **Critical deviations are human-only.** No agent authority for safety invariants, security boundaries, data integrity.
9. ✓ **Salvage ratio drives scrap-vs-rework.** Cost-economics, not subjective judgment.
10. ✓ **Mutation store for institutional memory.** Agents learn from prior attempts; genealogy tracking enables accountability.

### Open Questions

1. ? **Retry budget calibration:** Is 3 right? Should it vary by domain complexity?
2. ? **Quarantine max-age:** 14 days too long/short for different domain velocities?
3. ? **Deviation budget enforcement:** Is 5 active deviations per domain the right limit?
4. ? **MRB composition for small fleets:** What if not enough agents hold required authority?
5. ? **SLA calibration for async work:** How to handle overnight/weekend work with 4h SLAs?
6. ? **Accumulation trigger tuning:** Are the thresholds in Section 2 (3 marginals/7days, etc.) empirically calibrated?
7. ? **Cross-bead marginal correlation:** Should two beads producing marginal on same gate count toward accumulation?

---

## 10. Implementation Roadmap

### Phase 1: Core Taxonomy + Authority Matrix (Week 1-2)
- [ ] Adopt six-disposition model in bead schema
- [ ] Implement disposition authority matrix checks (Commit, Deploy, T0-T3 validation)
- [ ] Add `disposition_details` table to authority_audit
- [ ] Create `/clavain:disposition` CLI command

### Phase 2: CUJ Gates + Marginal Handling (Week 3-4)
- [ ] Implement marginal-usable/risky split in gate evaluations
- [ ] Build accumulation ledger tracking (marginal findings)
- [ ] Add SLA timer to quarantine state
- [ ] Auto-default logic when SLA expires

### Phase 3: Cost Tracking + Metrics (Week 5-6)
- [ ] Create `disposition_events` table; instrument rework paths
- [ ] Add cost-query.sh modes for COQ analysis
- [ ] Build dashboard signals (rework overhead %, wasted rework, quarantine p90)
- [ ] Validate disposition decision cost-benefit in retrospectives

### Phase 4: Mutation Store + Learning (Week 7-8)
- [ ] Create `mutation_outcomes` table with genealogy tracking
- [ ] Agent query interface before bead start
- [ ] Cross-sprint synthesis: "which hypotheses worked?"
- [ ] Genealogy query: "trace lineage of winning approach"

### Phase 5: Multi-Campaign Orchestration (Week 9-10)
- [ ] Module-scope conflict detection in plan_campaigns
- [ ] Parallel bead dispatch with dependency validation
- [ ] Mutation propagation via ideas files
- [ ] Sprint retrospective synthesis

---

## Conclusion

The unified model provides:

1. **Nuanced disposition taxonomy** replacing naive pass/fail, grounded in manufacturing MRB practice and validated by VFX industry at scale.

2. **Clear authority governance** preventing rubber-stamping or deadlock, with explicit escalation rules and dual-key requirements for high-risk decisions.

3. **Cost-driven decisions** enabling the factory to optimize for minimum total COQ (prevention + appraisal + failure costs), not minimum iteration count.

4. **Autonomous orchestration** via campaign-as-intent, circuit breakers, and mutation store, enabling parallel work with scope isolation and compound learning.

5. **Measurement infrastructure** (disposition events, cost metrics, accumulation ledger) making quality costs visible and systemic patterns detectable.

The model is implementable in phases, starting with disposition taxonomy + authority matrix (most critical), then layering in cost tracking, mutation store, and multi-campaign orchestration.

---

## Source Attribution

All findings in this synthesis are attributed to the 7 input research documents:

1. **fd-manufacturing-disposition-taxonomy.md** — Taxonomy structure, MRB authority, CAPA escalation
2. **fd-cicd-failure-modes.md** — Signal vs. noise, cost-of-quality framework, rollback economics
3. **fd-film-vfx-revision-pipelines.md** — Multi-tier review, CBB pattern, escalation ladder
4. **fd-cuj-rework-integration.md** — Marginal sub-states, authority matrix, SLA governance
5. **fd-rework-cost-accounting.md** — Cost models for each disposition, salvage ratio heuristics, schema design
6. **fd-authority-rework-routing.md** — Authority tier mapping, escalation mechanics, audit trail
7. **interlab-autoresearch-patterns.md** — Campaign-as-intent, keep/discard loops, mutation store, compound learning

**Confidence: High** — Findings are convergent across independent sources (manufacturing, CI/CD, VFX, autonomous research systems). Model is implementable and validated in multiple industrial contexts.

**Gaps:** Real production data from Demarch deployments will be needed to calibrate thresholds (retry budget, quarantine max-age, accumulation triggers). Phase 3 onward provides instrumentation to gather that data.

