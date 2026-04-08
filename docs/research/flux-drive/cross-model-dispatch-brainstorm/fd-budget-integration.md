### Findings Index
- P1 | BI-1 | "Implementation Sketch" | Circular dependency: budget pressure computed from pre-adjustment estimates, but adjustment changes the cost
- P1 | BI-2 | "Implementation Sketch" | Budget tracker not updated after tier adjustment — interstat and synthesis cost report will show wrong estimates
- P2 | BI-3 | "Design Space" | AgentDropout savings not reflected in budget pressure calculation
- P2 | BI-4 | "Implementation Sketch" | estimate-costs.sh has per-agent averages, not per-model-per-agent — downgrade savings are approximate
Verdict: needs-changes

## Summary

The brainstorm's budget integration has a structural issue: the budget pressure signal that drives tier adjustment is itself affected by the adjustment. The current proposal computes pressure once from pre-adjustment estimates, applies it, but never updates the cost accounting. This creates silent cost drift in the budget tracker and interstat. The fix is straightforward — a single-pass pipeline with post-adjustment cost update — but the brainstorm needs to specify it.

## Issues Found

### 1. [P1] BI-1: Circular dependency in budget pressure computation

**File:** brainstorm lines 152-158 (implementation sketch, Steps 1-4)
**Codebase ref:** `interverse/interflux/config/flux-drive/budget.yaml`, line 1-14

The sketch says:
1. Compute expansion_score
2. Compute budget_pressure: `remaining_budget / sum(stage2_estimates)`
3. Call `routing_adjust_expansion_tier` (which may downgrade based on pressure)

The problem: `sum(stage2_estimates)` uses pre-adjustment token estimates (from estimate-costs.sh, which gives per-agent averages). After tier adjustment, a downgraded agent costs less. So the *actual* remaining budget is higher than computed, meaning the pressure signal was too pessimistic.

**Failure scenario (not oscillation, but over-conservation):** 3 Stage 2 agents at sonnet (40K each = 120K total). Remaining budget = 80K. Pressure = 80K/120K = 0.67 -> "medium" (no action in current proposal, since medium means 0.5-0.8). But if one agent were score=1 and downgraded to haiku (~15K), actual cost would be 95K. The pressure was computed against 120K when the true denominator should be 95K, making pressure = 80K/95K = 0.84 -> "low."

This is conservative (over-downgrades rather than under-downgrades), which is safe but wasteful. It's NOT oscillation because the brainstorm uses a single-pass design (compute once, apply once). No feedback loop exists.

**Smallest fix:** Make it explicit that budget pressure is computed from PRE-adjustment estimates and this is intentionally conservative. Or: compute pressure using model-aware estimates (haiku cost for score=1 agents, sonnet for score=2+), which requires knowing the adjustment before computing pressure. A two-pass approach: (1) compute tentative adjustments from expansion score alone, (2) compute pressure using adjusted costs, (3) apply budget pressure override. This is still single-pass from the caller's perspective.

### 2. [P1] BI-2: Budget tracker not updated after tier adjustment

**File:** brainstorm lines 145-158
**Codebase ref:** `interverse/interflux/config/flux-drive/budget.yaml`, Step 1.2c; `interverse/interflux/skills/flux-drive/SKILL-compact.md`, lines 159-215

The existing budget enforcement (Step 1.2c) tracks cumulative token costs for the triage table. The brainstorm proposes tier adjustment AFTER triage (between Steps 2.2b and 2.2c), but never mentions updating the budget tracker's cumulative cost.

**Failure scenario:** The triage table shows "Budget: 160K / 200K (80%)" based on pre-adjustment estimates. After cross-model dispatch downgrades 2 agents from sonnet to haiku, actual cost is ~120K. The synthesis cost report (Step 3.4b) would show the original 160K estimate, making the run appear more expensive than it was. Over time, this inflates the average cost in interstat, causing future runs to allocate larger budgets than needed.

The brainstorm's Risk Assessment table mentions "Budget accounting mismatch" (line 211) with "Tier-adjusted costs fed back to budget tracker" as mitigation — but the implementation sketch doesn't show WHERE this feedback happens.

**Smallest fix:** After `routing_adjust_expansion_tier` returns, update the budget tracker entry for that agent:
```
if adjusted_model != original_model:
    agent.est_tokens = lookup_model_cost(adjusted_model, agent)
    cumulative = recalculate(selected_agents)
```
Log the adjustment in the cost report data (Step 3.4b), alongside dropout savings.

### 3. [P2] BI-3: AgentDropout savings not reflected in budget pressure

**File:** brainstorm "Current Architecture" section, Step 2.2a.5
**Codebase ref:** `interverse/interflux/skills/flux-drive/phases/expansion.md`, lines 66-83

AgentDropout (Step 2.2a.5) runs before expansion scoring (Step 2.2b). Dropped agents free up budget. But the brainstorm's budget pressure computation uses `remaining_budget / sum(stage2_estimates)` — does `stage2_estimates` include dropped agents?

If yes: pressure is inflated (denominator includes agents that won't run).
If no: this is already correct.

The expansion.md tracks `estimated_savings` from dropout but doesn't show it being subtracted from budget accounting.

**Question:** Does the budget tracker subtract dropout savings from the cumulative total? If so, `remaining_budget` already reflects dropout. If not, this is a P2 because it leads to over-conservative tier adjustment.

### 4. [P2] BI-4: estimate-costs.sh granularity mismatch

**File:** brainstorm line 148
**Codebase ref:** `interverse/interflux/config/flux-drive/budget.yaml`, lines 16-23 (agent_defaults)

estimate-costs.sh queries interstat for per-agent historical costs. But interstat stores per-agent averages (across all model tiers the agent has run on), not per-model-per-agent costs. When an agent is downgraded from sonnet to haiku, the savings estimate uses the average (which blends sonnet and haiku runs).

For the "estimated savings: ~35K tokens" claim (brainstorm line 169), this means the savings are approximate. If an agent has historically run 80% on sonnet and 20% on haiku, the average is close to sonnet cost — so the downgrade savings would be overestimated.

**Question:** Does interstat store `(agent, model)` pairs, or just `agent`? If per-model data exists, the downgrade cost estimate should use `estimate(agent, haiku)` instead of `estimate(agent) * 0.5`.

## Improvements

1. Add a "Budget Accounting Flow" diagram showing: dropout savings -> remaining budget -> pressure computation -> tier adjustment -> cost update -> synthesis report. This makes the data flow explicit.
2. The brainstorm's logging example (line 163-169) should include post-adjustment budget: "Budget pressure: low (82% remaining -> 91% after adjustment)."

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 4 (P0: 0, P1: 2, P2: 2)
SUMMARY: Budget pressure is computed from pre-adjustment estimates, creating a conservative bias. Post-adjustment cost update is mentioned in risk mitigation but absent from the implementation sketch. Both are fixable with a two-pass approach and explicit cost recalculation.
---
<!-- flux-drive:complete -->
