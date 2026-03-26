# Rework Cost Accounting: Cost-of-Quality Economics for AI Agent Dispositions

## Research Question

What are the cost economics of each disposition path (scrap/rework/quarantine/use-as-is/deviation) when measured in AI agent tokens and time?

## Framework: Cost of Quality Adapted for Token Economics

The classical Cost of Quality (COQ) framework divides costs into four categories. In manufacturing, the Cost of Poor Quality at a thriving company accounts for 10-15% of operations (ASQ). For AI agent systems, the same structure applies but the unit of cost shifts from materials and labor-hours to **tokens and wall-clock seconds**.

### COQ Categories Mapped to Agent Operations

| Classical Category | Manufacturing Example | Agent Equivalent | Demarch Mechanism |
|---|---|---|---|
| **Prevention** | Training, process design | Prompt engineering, routing rules, gate design | `lib-routing.sh`, gate configs, SKILL.md |
| **Appraisal** | Inspection, testing | Output validation, test execution, review agents | Interspect hooks, tool_selection_events |
| **Internal Failure** | Scrap, rework before ship | Discarded generations, retry loops, re-routing | Scrap/rework dispositions |
| **External Failure** | Warranty, recalls | Merged bad patches, broken builds downstream, user-facing defects | Bead rollback, revert commits |

**Key insight**: In manufacturing, prevention and appraisal costs are incurred upfront to reduce failure costs. The optimal COQ point minimizes total cost, not defect count. The same tradeoff applies: spending tokens on validation (appraisal) reduces the expected cost of downstream failures, but only up to a point.

## Disposition Path Economics

### 1. Scrap (Discard and Regenerate)

**Definition**: Abandon the current output entirely, restart from scratch.

**Cost model**:
```
C_scrap = C_original + C_fresh_generation
       = (sunk, irrelevant to decision) + C_fresh_generation
```

The sunk cost of the original generation is economically irrelevant to the scrap-vs-rework decision — only future costs matter. The decision-relevant cost is purely the fresh generation cost.

**Token cost estimate** (from Demarch interstat baseline):
- Average SWE-bench trajectory: 48.4K tokens across 40 steps (OpenReview research)
- Demarch cost-per-landable-change: $2.93 (785 sessions, 2026-03-18 baseline)
- At Sonnet pricing ($3/Mtok input, $15/Mtok output): a full-scrap re-generation costs approximately the full bead token budget

**When scrap is economically rational**:
- Rework cost exceeds fresh generation cost (the output is so wrong that fixing it costs more than starting over)
- The defect is architectural/structural, not localized (wrong approach, not wrong detail)
- Context pollution: the flawed output has contaminated the conversation context window, and rework would carry that contamination forward
- **Context pollution premium**: Unlike manufacturing, scrapping in agent systems has a hidden benefit — a clean context window. Rework carries the original flawed reasoning in the context, which can bias subsequent generations. This is unique to token-based systems and has no manufacturing analog.

### 2. Rework (Repair and Resubmit)

**Definition**: Take the existing output and apply targeted corrections to bring it to acceptable quality.

**Cost model**:
```
C_rework = C_diagnosis + C_correction + C_re_validation
```

Where:
- `C_diagnosis` = tokens spent identifying what's wrong (reading output, comparing to spec)
- `C_correction` = tokens spent generating the fix (often a fraction of full generation)
- `C_re_validation` = tokens spent verifying the fix didn't introduce new defects

**Token cost estimate**:
- Trajectory reduction research shows 39.9-59.7% of input tokens in agent trajectories are useless, redundant, or expired information
- A targeted rework that identifies and fixes a specific defect typically costs 20-40% of a full regeneration
- But: if rework triggers a retry loop (Reflexion-style), costs can explode to 10-50x a single pass

**Break-even formula** (scrap vs rework):

```
Rework is preferred when:
  C_diagnosis + C_correction + C_re_validation < C_fresh_generation - C_salvage_value

Simplified for tokens:
  T_rework < T_fresh × (1 - salvage_ratio)
```

Where `salvage_ratio` is the fraction of the original output that can be kept (0 = nothing salvageable, 1 = perfect). In practice:

| Defect Type | Typical salvage_ratio | Preferred Disposition |
|---|---|---|
| Wrong approach/architecture | 0.0 - 0.1 | Scrap |
| Correct approach, wrong details | 0.5 - 0.8 | Rework |
| Minor formatting/style issues | 0.9 - 0.95 | Rework |
| Off-by-one, typo-class errors | 0.95+ | Rework |
| Hallucinated dependency/API | 0.3 - 0.6 | Depends on scope |

**Rework cost amplifier — retry loops**: Research shows an agentic loop that runs for 10 cycles can consume 50x the tokens of a single linear pass. Rework must have a circuit breaker: if the first correction attempt fails validation, escalate to scrap rather than entering an unbounded retry loop. The interstat `retry_of_seq` column in `tool_selection_events` already tracks this signal.

### 3. Quarantine (Hold for Later Disposition)

**Definition**: Set the output aside without immediate disposition, pending more information or a different reviewer.

**Cost model**:
```
C_quarantine = C_holding + C_eventual_disposition + C_blocked_downstream

C_holding = C_storage + C_decision_overhead × T_wait
C_blocked_downstream = Σ(blocked_bead_value × time_blocked)
```

**Holding costs in agent systems** are different from manufacturing:

| Holding Cost Component | Manufacturing (25-30% of unit value/year) | Agent Systems |
|---|---|---|
| Physical storage | Warehouse space, refrigeration | Negligible (disk is cheap) |
| Capital tie-up | Cash in inventory | **Blocked downstream beads** — the real cost |
| Obsolescence | Style changes, shelf life | **Context staleness** — quarantined output may reference outdated code |
| Decision overhead | MRB meeting time | **Token cost of re-review** each time someone revisits |

**The dominant quarantine cost in agent systems is blocked downstream work.** When a bead's output is quarantined, any dependent beads cannot proceed. In Demarch's bead graph, this creates a cascade: if bead A's output is quarantined and beads B, C, D depend on A, the effective holding cost is the idle-time cost of B + C + D.

**Quarantine cost per hour** (estimated from Demarch baseline):
```
C_quarantine_per_hour = N_blocked_beads × avg_bead_cost × opportunity_cost_rate

With Demarch's $2.93/landable-change baseline:
  1 blocked bead × $2.93 × 0.1/hour ≈ $0.29/hour of quarantine
  3 blocked beads × $2.93 × 0.1/hour ≈ $0.88/hour
```

This appears small in dollar terms, but in **time** terms, quarantine delays compound: a 4-hour quarantine on a critical-path bead delays the entire sprint by 4 hours. The cost is better measured in wall-clock sprint delay than in tokens.

**When quarantine is economically rational**:
- The defect classification is genuinely ambiguous (a reviewer cannot reliably determine if rework or scrap is correct)
- Additional information is expected soon (e.g., a test suite is running, a dependent spec is being finalized)
- The quarantine duration has a hard ceiling (24h maximum, then auto-scrap)
- **Anti-pattern**: Quarantine as indecision. Without a hard ceiling, quarantine becomes the default for difficult decisions, and holding costs accumulate silently.

### 4. Use-As-Is (Accept with Known Deficiency)

**Definition**: Accept the output despite a known deviation from specification, because the deviation is tolerable.

**Cost model**:
```
C_use_as_is = C_documentation + C_downstream_risk

C_downstream_risk = P(defect_causes_failure) × C_failure
```

This is an expected-value calculation. The key question: what is the probability that the known deficiency will cause a downstream failure, and what is the cost of that failure?

**Token cost**: Near-zero immediate cost (just the documentation overhead). But the deferred cost can be large:

| Downstream Failure Mode | P(failure) | C(failure) | Expected Cost |
|---|---|---|---|
| Style deviation, no functional impact | ~0 | $0 | $0 |
| Missing edge-case handling, rare path | 0.05 | $5-15 (debug + fix) | $0.25-0.75 |
| Incorrect error handling, common path | 0.3 | $10-30 (rework + test) | $3-9 |
| Wrong API contract, affects dependents | 0.5 | $20-50 (multi-bead rework) | $10-25 |

**When use-as-is is economically rational**:
- P(failure) × C(failure) < C(rework) — the expected downstream cost is less than the certain rework cost
- The deviation is in a non-critical path (test code, documentation, logging)
- The deviation will be corrected as part of a planned future bead anyway (amortized rework)

**Risk**: Use-as-is decisions compound. Each individual deviation may be tolerable, but 10 accepted deviations create a debt surface that makes future rework more expensive. This is the "broken windows" effect — use-as-is must have a counter/threshold that triggers mandatory cleanup.

### 5. Deviation (Formal Exception with Tracking)

**Definition**: Accept the output with an explicit, tracked exception that modifies the specification rather than the output.

**Cost model**:
```
C_deviation = C_review + C_documentation + C_spec_update + C_future_confusion

C_future_confusion = N_future_agents × P(misinterpret_spec) × C_rework_from_confusion
```

**Deviation is the most expensive disposition in documentation overhead** but can be the cheapest in total cost when the spec was wrong, not the output. If an agent produces output that violates a gate rule but the output is actually correct (the rule was too strict), a deviation that updates the rule prevents all future false-positive scrap/rework on that rule.

**Token economics of deviation**:
- Immediate cost: ~500-2000 tokens for review + documentation
- Amortized benefit: prevents N future false dispositions, each costing 5K-50K tokens
- Break-even: if the rule triggers >3 times and the output was right each time, deviation + rule update saves tokens

## Interstat Schema Extensions for Rework Tracking

The current interstat schema (`agent_runs` + `tool_selection_events`) tracks token consumption and tool failures but has no concept of disposition events. To enable cost-of-quality analysis, the following extension is proposed.

### Schema v5: disposition_events Table

```sql
CREATE TABLE IF NOT EXISTS disposition_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,
    session_id TEXT NOT NULL,
    bead_id TEXT NOT NULL,
    phase TEXT DEFAULT '',

    -- Disposition classification
    disposition TEXT NOT NULL,  -- 'scrap', 'rework', 'quarantine', 'use_as_is', 'deviation'
    defect_type TEXT,           -- 'wrong_approach', 'wrong_detail', 'style', 'hallucination', 'test_failure'
    severity TEXT,              -- 'p0', 'p1', 'p2', 'p3'

    -- Cost signals
    tokens_spent_before INTEGER,     -- tokens consumed before disposition decision
    tokens_spent_on_disposition INTEGER,  -- tokens consumed during rework/re-generation
    wall_ms_before INTEGER,          -- wall clock before disposition
    wall_ms_on_disposition INTEGER,  -- wall clock during rework/re-generation

    -- Quarantine tracking
    quarantine_start TEXT,      -- ISO timestamp, NULL if not quarantined
    quarantine_end TEXT,        -- ISO timestamp, NULL if still quarantined
    blocked_beads TEXT,         -- JSON array of bead_ids blocked by quarantine

    -- Rework tracking
    rework_attempt INTEGER DEFAULT 1,  -- which attempt (1=first rework, 2=second, etc.)
    rework_of_id INTEGER,              -- FK to previous disposition_events.id if this is a re-disposition

    -- Outcome
    final_outcome TEXT,         -- 'accepted', 'scrapped_after_rework', 'escalated'
    authority_level TEXT,       -- 'agent', 'gate', 'human' — who decided

    -- Linkage
    gate_id TEXT,               -- which gate triggered the disposition
    agent_run_id INTEGER        -- FK to agent_runs.id
);

CREATE INDEX IF NOT EXISTS idx_de_bead ON disposition_events(bead_id);
CREATE INDEX IF NOT EXISTS idx_de_disposition ON disposition_events(disposition);
CREATE INDEX IF NOT EXISTS idx_de_session ON disposition_events(session_id);
CREATE INDEX IF NOT EXISTS idx_de_outcome ON disposition_events(final_outcome);
```

### New cost-query.sh Modes

```bash
# Proposed additions to cost-query.sh:
bash scripts/cost-query.sh disposition-summary     # Count + avg cost by disposition type
bash scripts/cost-query.sh rework-ratio            # Rework tokens / total tokens (quality metric)
bash scripts/cost-query.sh quarantine-duration      # Avg/p50/p90 quarantine hold time
bash scripts/cost-query.sh scrap-vs-rework-breakeven  # Empirical breakeven from actual data
bash scripts/cost-query.sh disposition-by-gate      # Which gates trigger which dispositions
```

### Derived View: v_disposition_cost

```sql
CREATE VIEW v_disposition_cost AS
SELECT
    disposition,
    COUNT(*) as count,
    ROUND(AVG(tokens_spent_on_disposition)) as avg_disposition_tokens,
    ROUND(AVG(tokens_spent_before)) as avg_pre_disposition_tokens,
    ROUND(AVG(wall_ms_on_disposition)) as avg_disposition_ms,
    ROUND(
        CAST(SUM(tokens_spent_on_disposition) AS REAL) /
        NULLIF(SUM(tokens_spent_before + tokens_spent_on_disposition), 0) * 100,
    2) as rework_overhead_pct,
    SUM(CASE WHEN final_outcome = 'accepted' THEN 1 ELSE 0 END) as accepted_count,
    SUM(CASE WHEN final_outcome = 'scrapped_after_rework' THEN 1 ELSE 0 END) as wasted_rework_count
FROM disposition_events
GROUP BY disposition;
```

The critical metric is `wasted_rework_count` — dispositions where rework was attempted but the output was ultimately scrapped anyway. This represents pure waste: the rework tokens were spent with zero value recovery. A high wasted-rework rate signals that the scrap-vs-rework decision heuristic is miscalibrated.

## Second-Order Costs of Poor Disposition Decisions

### 1. Systematic Under-Scrapping (Use-As-Is Bias)

When the system defaults to accepting marginal output, defect density accumulates in the codebase. Each accepted deficiency makes future work harder:

```
C_accumulated_debt = Σ(accepted_deviations) × avg_confusion_tax_per_future_bead

Where confusion_tax = additional tokens spent by future agents
navigating around or misunderstanding prior deviations
```

This is the agent equivalent of technical debt. Interstat can detect it by correlating: beads that touch files with high prior use-as-is disposition rates should show higher-than-average token consumption. If they do, the use-as-is threshold is too permissive.

### 2. Systematic Over-Scrapping (Perfectionism Bias)

When gates are too strict, good-enough output is scrapped and regenerated at full cost. The waste signal: scrap dispositions where the defect_type is `style` or `p3` severity. If >20% of scraps are for cosmetic issues, the gate thresholds need loosening.

**Detection query**:
```sql
SELECT
    defect_type,
    severity,
    COUNT(*) as scrap_count,
    SUM(tokens_spent_before) as tokens_wasted
FROM disposition_events
WHERE disposition = 'scrap'
GROUP BY defect_type, severity
ORDER BY tokens_wasted DESC;
```

### 3. Quarantine Drift (Indecision Cost)

Quarantine without a hard time ceiling becomes the default for difficult decisions. The cost is invisible because no tokens are spent — but downstream work stalls. Detection: monitor quarantine_duration p90. If p90 > 4 hours, the system has a decision bottleneck.

### 4. Rework Spiral (Unbounded Retry)

Rework that fails validation and triggers re-rework is the highest-cost failure mode. Each cycle adds full rework cost while the probability of eventual acceptance may be declining:

```
Expected cost of N rework attempts:
  E[C] = Σ(i=1..N) C_rework_i × P(still_failing_at_i)

If P(success) doesn't increase with attempts, the series diverges.
Circuit breaker: max 2 rework attempts, then mandatory scrap.
```

The `rework_attempt` column in `disposition_events` tracks this directly. A dashboard alert when any bead reaches `rework_attempt >= 3` signals a problem that human review should intercept.

### 5. Authority Miscalibration

When the wrong authority level makes disposition decisions, costs increase in both directions:
- **Too autonomous**: Agent decides use-as-is for a defect that causes downstream failure. Cost: full external failure cost (multi-bead rework).
- **Too conservative**: Every disposition escalates to human review. Cost: latency (quarantine holding cost while waiting for human) + human attention cost.

The `authority_level` column enables calibration analysis: for each authority level, what is the rate of disposition decisions that were later reversed or led to downstream failures?

## Summary: Disposition Decision Matrix

| Disposition | When Optimal | Typical Token Cost (% of fresh gen) | Key Risk | Tracking Signal |
|---|---|---|---|---|
| **Scrap** | Salvage ratio < 0.3, architectural defect | 100% (fresh gen) | Over-scrapping cosmetic issues | scrap count by severity |
| **Rework** | Salvage ratio > 0.5, localized defect | 20-40% | Unbounded retry loops | rework_attempt, wasted_rework_count |
| **Quarantine** | Genuinely ambiguous, info expected soon | 0% immediate, high holding cost | Indefinite holds, blocked beads | quarantine_duration p90 |
| **Use-As-Is** | P(failure) × C(failure) < C(rework) | ~0% | Accumulated deviation debt | use-as-is rate by file/module |
| **Deviation** | Spec is wrong, not output | 2-5% (documentation) | Future agent confusion | deviation count per gate rule |

## Sources

- [ASQ: Cost of Quality](https://asq.org/quality-resources/cost-of-quality)
- [How Scrap and Rework Affect Cost of Quality and OEE](https://www.ease.io/blog/scrap-rework-affect-cost-of-quality-and-oee/)
- [Six Sigma Study Guide: Cost of Poor Quality](https://sixsigmastudyguide.com/cost-of-poor-quality/)
- [Material Review Board: Deciding the Fate of Nonconforming Product (Tulip)](https://tulip.co/blog/material-review-board/)
- [Inventory Quarantine System: Hold/Release Controls (SGS)](https://sgsystemsglobal.com/guides/inventory-quarantine-system/)
- [How Do Coding Agents Spend Your Money? (OpenReview)](https://openreview.net/forum?id=1bUeVB3fov)
- [Improving Efficiency of LLM Agent Systems through Trajectory Reduction (arXiv)](https://arxiv.org/pdf/2509.23586)
- [The Hidden Economics of AI Agents (Stevens)](https://online.stevens.edu/blog/hidden-economics-ai-agents-token-costs-latency/)
- [Tracking Scrap, Rework, and Waste: Cost Accounting's Role](https://accountingprofessor.org/tracking-scrap-rework-and-waste-cost-accountings-role/)
- [Disposition in Manufacturing: Best Practices (Amplio)](https://www.amplio.com/post/disposition-in-manufacturing)
- [How to Scale Agentic Evaluation: Lessons from 200K SWE-bench Runs (AI21)](https://www.ai21.com/blog/scaling-agentic-evaluation-swe-bench/)
- [CliffsNotes: Spoilage, Rework, and Scrap in Cost Accounting](https://www.cliffsnotes.com/study-notes/19302148)

<!-- flux-research:complete -->
