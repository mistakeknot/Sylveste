# Cross-Model Dispatch for interflux Expansion Pool

**Bead:** sylveste-9lp.9
**Date:** 2026-04-04
**Dependency:** sylveste-9lp.6 (haiku routing fix — closed)

## Problem

All expansion pool agents (Stage 2, speculative launches) inherit the same model resolved in Step 2.0.5 — a single `routing_resolve_agents` call before any Stage 1 findings exist. This is wasteful: expansion candidates vary in confidence and criticality, yet they all run at the same tier.

A Stage 2 agent launched because of a distant P2 adjacency signal shouldn't cost the same as one triggered by an adjacent P0. The expansion scoring algorithm already quantifies this confidence (0–3), but the dispatch ignores it.

## Current Architecture

### Model Resolution Flow

```
Step 2.0.5: routing_resolve_agents()
  ├── Resolution chain: override → complexity → phase:category → phase → defaults.category → default
  ├── Safety floor clamp: fd-safety, fd-correctness ≥ sonnet (agent-roles.yaml)
  └── Output: JSON model map for ALL agents (Stage 1 + Stage 2 alike)

Step 2.2: Stage 1 launch (uses model map from 2.0.5)
Step 2.2a.5: AgentDropout — prunes redundant Stage 2 candidates
Step 2.2a.6: Incremental expansion — speculative launches (max 2, uses same model map)
Step 2.2b: Domain-aware expansion decision — expansion_score 0-3
Step 2.2c: Stage 2 launch (uses same model map from 2.0.5)
```

### What We Have to Work With

1. **Expansion scores (0–3)** — already computed per Stage 2 candidate in Step 2.2b
2. **Agent roles (agent-roles.yaml)** — planner/reviewer/editor/checker with model_tier + min_model
3. **Safety floors** — lib-routing.sh `_routing_apply_safety_floor()` clamps to min_model
4. **Cost estimates** — estimate-costs.sh, budget.yaml defaults, interstat historical data
5. **Trust multipliers** — per-agent precision scores from intertrust
6. **Redundancy scores** — from AgentDropout (Step 2.2a.5)

### Current Agent Tier Distribution

| Role | Agents | model_tier | min_model |
|------|--------|-----------|-----------|
| planner | fd-architecture, fd-systems | opus | sonnet |
| reviewer | fd-correctness, fd-quality, fd-safety | sonnet | sonnet |
| editor | fd-performance, fd-user-product, fd-game-design | sonnet | — |
| checker | fd-perception, fd-resilience, fd-decisions, fd-people | haiku | — |

## Design Space

### Option A: Expansion-Score-Driven Tier Adjustment

Re-resolve models at Step 2.2b using expansion score as a routing signal.

```
expansion_score == 3 (P0 adjacent)  → keep resolved model (or upgrade: haiku→sonnet)
expansion_score == 2 (P1 adjacent)  → keep resolved model
expansion_score == 1 (weak signal)  → downgrade one tier (sonnet→haiku)
expansion_score == 0 (no signal)    → shouldn't reach dispatch (expansion stops)
```

**Where it fits:** After AgentDropout (2.2a.5), before Stage 2 launch (2.2c). A second `routing_resolve_agents` call with an `--expansion-tier` flag, or a new `routing_adjust_expansion_tier` function.

**Pros:** Uses existing signal. Minimal new state. Respects safety floors.
**Cons:** Only 4 discrete levels. Doesn't account for which specific finding triggered expansion.

### Option B: Finding-Driven Tier Selection

Map the specific Stage 1 finding that triggered expansion to a model tier.

```
P0 finding in adjacent domain → sonnet or opus (critical finding demands quality)
P1 finding in adjacent domain → sonnet (standard investigation)
Disagreement between Stage 1 agents → sonnet (arbitration needs capability)
Domain injection match only → haiku (exploratory, lower confidence)
```

**Where it fits:** Inside Step 2.2b expansion scoring, annotate each candidate with `trigger_finding_severity` and `trigger_type`, then pass to a new routing function.

**Pros:** Granular — ties model investment to the evidence that justified the launch.
**Cons:** More complex. Finding severity already feeds expansion_score, so this may be redundant with Option A.

### Option C: Cost-Budget-Aware Tier Selection

After budget allocation in Step 1.2c, remaining budget determines expansion tier.

```
remaining_budget > 80% of stage_2_estimate → keep models as-is
remaining_budget 50-80% → downgrade editors/checkers one tier
remaining_budget < 50% → downgrade all non-exempt to haiku
remaining_budget exhausted → expansion blocked (existing behavior)
```

**Where it fits:** Between budget enforcement and Stage 2 launch. Reads `FLUX_BUDGET_REMAINING`.

**Pros:** Direct cost control. Elegant degradation.
**Cons:** Budget is already a binary gate (launch or defer). Adding tier adjustment makes it a continuous signal, which complicates budget accounting.

### Recommended: Option A + C Hybrid

Use expansion score as the primary tier signal, with budget remaining as a secondary constraint.

```
1. Compute expansion_score per candidate (existing Step 2.2b)
2. Map score → model adjustment:
   - score 3: keep or upgrade
   - score 2: keep
   - score 1: downgrade one tier
3. Apply budget constraint:
   - If remaining budget < 50% of Stage 2 estimate: force downgrade all non-exempt
4. Apply safety floors (always, non-negotiable)
5. Dispatch with per-agent model overrides
```

This gives us evidence-driven dispatch with cost guardrails.

## Implementation Sketch

### New Function: `_routing_downgrade`

```bash
# _routing_downgrade <model>
# Returns next lower tier. haiku stays haiku. Empty/unknown returns unchanged.
_routing_downgrade() {
  case "${1:-}" in
    opus)   echo "sonnet" ;;
    sonnet) echo "haiku" ;;
    haiku)  echo "haiku" ;;
    *)      echo "${1:-haiku}" ;; # unknown/empty → preserve or default to haiku
  esac
}
```

### New Function: `routing_adjust_expansion_tier`

```bash
# routing_adjust_expansion_tier <agent> <current_model> <expansion_score> <budget_pressure>
# Returns adjusted model. Respects constitutional floors and safety floors.
# Pipeline: score adjust → budget pressure → constitutional floor → safety floor → validate
routing_adjust_expansion_tier() {
  local agent="$1" model="$2" score="${3:-2}" pressure="${4:-low}"

  # 1. Score-based tier adjustment
  case "$score" in
    3) # Strong evidence — upgrade haiku checkers to sonnet if no max_model ceiling
       local max_model; max_model=$(_routing_agent_field "$agent" "max_model")
       if [[ "$model" == "haiku" && "${max_model:-opus}" != "haiku" ]]; then
         model="sonnet"
       fi ;;
    2) ;; # Moderate evidence — keep model
    1) # Weak evidence — downgrade unless domain_complexity is high
       local dom_complexity; dom_complexity=$(_routing_agent_field "$agent" "domain_complexity")
       if [[ "${dom_complexity:-low}" != "high" ]]; then
         model=$(_routing_downgrade "$model")
       fi ;;
    0) model="haiku" ;; # Should not reach dispatch
  esac

  # 2. Budget pressure (applied after score, before floors)
  if [[ "$pressure" == "high" ]]; then
    model=$(_routing_downgrade "$model")
  fi

  # 3. Constitutional floor from agent-roles.yaml (min_model for this agent's role)
  local constitutional_floor; constitutional_floor=$(_routing_agent_field "$agent" "min_model")
  if [[ -n "$constitutional_floor" ]]; then
    local model_tier floor_tier
    model_tier=$(_routing_model_tier "$model")
    floor_tier=$(_routing_model_tier "$constitutional_floor")
    [[ $model_tier -lt $floor_tier ]] && model="$constitutional_floor"
  fi

  # 4. Safety floor (ALWAYS LAST — non-negotiable)
  # INVARIANT: empty model guard — if anything above returned empty, default to haiku
  [[ -z "$model" ]] && model="haiku"
  model=$(_routing_apply_safety_floor "$agent" "$model" "expansion")

  # 5. Final validation — must be a known model
  [[ ! "$model" =~ ^(haiku|sonnet|opus)$ ]] && {
    echo "[routing] WARN: adjust returned invalid '$model' for $agent, using $2" >&2
    model="$2"
  }

  echo "$model"
}
```

### New Fields in agent-roles.yaml

```yaml
# Added per-agent fields for cross-model dispatch:
#   domain_complexity: low|medium|high — minimum tier for coherent reasoning
#   max_model: haiku|sonnet|opus|null — maximum tier warranted (optional ceiling)
# The effective tier is: max(score_tier, complexity_floor, constitutional_floor, safety_floor)
#                        capped at max_model if set.
```

### Feature Gate in budget.yaml

```yaml
# Cross-model dispatch — evidence-proportional tier routing for expansion pool
cross_model_dispatch:
  enabled: true
  mode: shadow    # shadow = log adjustments without applying | enforce = apply adjustments
```

### Changes to expansion.md (Step 2.2b → 2.2c)

After expansion scoring, before Stage 2 dispatch:

```
1. Deduplicate expansion score contributions:
   - Each contribution carries trigger_source_id
   - Group by source_id; keep max contribution per source
   - Score = min(sum_of_independent_contributions, 3)

2. Sort candidates by (expansion_score DESC, role_priority DESC, name ASC)
   - Planner > reviewer > editor > checker for role_priority
   - High-score agents get first claim on budget headroom

3. Compute budget_pressure (continuous 0.0-1.0):
   - Subtract speculative_reserve = max_speculative_launches × avg_sonnet_cost
   - effective_budget = remaining_budget - speculative_reserve
   - pressure_ratio = 1.0 - (effective_budget / sum(stage2_estimates))
   - Map: < 0.2 → "low", 0.2-0.5 → "medium", > 0.5 → "high"

4. For each expansion candidate (in sorted order):
   a. Check cross_model_dispatch.enabled && mode == "enforce"
   b. Call routing_adjust_expansion_tier(agent, current_model, score, pressure)
   c. Update budget estimate with adjusted tier cost (two-pass accounting)
   d. Use returned model for this agent's Task dispatch

5. Pool-level quality assertion:
   - Assert ≥1 planner/reviewer-role agent at sonnet after all adjustments
   - If violated, upgrade highest-scored planner/reviewer to sonnet
   - Cap simultaneous haiku downgrades at floor(pool_size / 2)

6. Upgrade pass (savings recycling):
   - tokens_saved = sum(original_cost - adjusted_cost)
   - If tokens_saved > 10K: upgrade highest-scored score=2 agent one tier

For speculative launches (Step 2.2a.6):
  - Apply speculative discount: effective_score = max(score - 1, 1)
  - Call routing_adjust_expansion_tier with discounted score
```

### Logging

```
Cross-model dispatch (Stage 2):
  fd-performance: sonnet → sonnet (score=3, P0 adjacent, domain_complexity=medium)
  fd-game-design: sonnet → haiku (score=1, weak signal, domain_complexity=low)
  fd-people: haiku → haiku (score=2, already lowest viable)
  fd-architecture: sonnet → sonnet (score=1, constitutional floor: sonnet)
  🛡 fd-safety: haiku → sonnet (safety floor clamped)
Budget pressure: 0.18 (low), reserve: 80K for speculative
Pool audit: 2 planners at sonnet ✓
Savings: ~25K tokens (recycled 10K → upgraded fd-decisions haiku→sonnet)
```

### Calibration Logging (in-scope for v1)

Per-run emit to interspect (promotes Open Question 3):
```
(agent, expansion_score, adjusted_tier, finding_count, max_finding_severity, tier_was_downgraded)
```
Also emit `tier: haiku|sonnet|opus` per finding in agent output for future weighted synthesis.

### Escalation Advisory (in-scope for v1)

After each agent completion, if `finding_severity >= P1 AND agent_was_downgraded`:
```
[tier-escalation] fd-decisions was downgraded to haiku but returned P1 finding — candidate for tier escalation
```
Advisory only in v1. Data enables future automatic re-dispatch.

## Constraints

1. **Safety floors are non-negotiable.** fd-safety and fd-correctness always ≥ sonnet, regardless of expansion score or budget pressure.
2. **Exempt agents bypass cross-model dispatch.** They always launch at their configured tier.
3. **Stage 1 is unaffected.** Cross-model dispatch only applies to Stage 2 / expansion pool.
4. **Budget enforcement remains a separate gate.** Cross-model dispatch adjusts tiers within the budget envelope — it doesn't override budget cuts.
5. **Speculative launches (Step 2.2a.6) use discounted scores.** They're early Stage 2 agents with partial evidence — apply `max(score - 1, 1)` discount before tier adjustment.
6. **B1 routing remains primary.** Cross-model dispatch is an adjustment layer on top of B1 resolution, not a replacement.
7. **Pool-level quality guarantee.** At least one planner/reviewer-role agent must remain at sonnet after all adjustments. Per-agent floors don't guarantee pool coverage.
8. **Constitutional floors from agent-roles.yaml are respected.** The `min_model` field applies during expansion, not just initial dispatch.

## Scope

### In Scope
- `routing_adjust_expansion_tier()` function in lib-routing.sh
- `_routing_downgrade()` helper (model → next lower tier)
- `_routing_agent_field()` helper (read agent-roles.yaml fields)
- Expansion phase (expansion.md) changes to call tier adjustment before Stage 2 dispatch
- Speculative launch integration (Step 2.2a.6 calls tier adjustment with discounted score)
- Per-agent model override in Stage 2 Task calls (bypass Step 2.0.5 map)
- Feature gate: `cross_model_dispatch: { enabled, mode: shadow|enforce }` in budget.yaml
- `domain_complexity` and `max_model` fields in agent-roles.yaml
- `trigger_source_id` deduplication in expansion scoring
- Pool-level quality assertion (≥1 planner/reviewer at sonnet)
- Calibration logging per-run to interspect
- Escalation advisory logging (tier-escalation-candidate)
- Logging of tier adjustments with `tier` field per finding
- Budget pressure as continuous ratio with speculative reserve
- Merit-order sort before dispatch
- Upgrade pass for savings recycling

### Out of Scope
- Stage 1 model changes (separate concern)
- B2 complexity routing enforcement (experiment showed B1+floors is optimal)
- Agent role reclassification
- Dynamic model switching mid-review (agent restart)
- flux-review changes (no expansion pool in review mode)
- Automatic tier escalation re-dispatch (v2 — data collected in v1)

## Open Questions (Resolved)

1. **Upgrade path:** ~~Current proposal: keep model (no upgrade).~~ **Resolved: Yes.** Score=3 upgrades haiku→sonnet for agents without max_model=haiku ceiling. Strong evidence justifies the cost.
2. **Speculative launch tier:** ~~Current proposal: same logic applies.~~ **Resolved: Discounted.** Speculative launches use `max(score - 1, 1)` — partial evidence gets conservative tier.
3. **Calibration data:** ~~Deferred.~~ **Resolved: In-scope for v1.** Minimum viable: log `(agent, score, tier, finding_count, max_severity)` per run. Interspect integration after 20 runs of data.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Safety-critical agent under-resourced | Low | High | Safety floors enforced post-adjustment + constitutional floors from agent-roles.yaml |
| Token savings < projected | High | Low | Score distribution clusters at 2 (~70% no-op). Revised estimate: 0-15K per run. Primary value is quality differentiation, not cost savings. |
| Planner-role agent produces confidently wrong findings at haiku | Medium | High | Constitutional floor prevents planner/reviewer downgrade below sonnet; pool-level assertion guarantees coverage |
| Correlated downgrade under budget pressure | Medium | High | Pool-level quality floor + cap simultaneous downgrades at floor(pool_size/2) |
| Finding quality degrades on haiku | Medium | Medium | Calibration logging + escalation advisory when downgraded agent returns P1+ |
| Budget accounting mismatch | Low | Medium | Two-pass budget: tentative adjust → recompute pressure → final adjust |
| Expansion score inflated by correlated signals | Medium | Medium | trigger_source_id deduplication before scoring |

## Success Criteria

1. Stage 2 agents route to different tiers based on expansion score and domain complexity
2. Safety floors and constitutional floors never violated
3. Token savings of 0-15K per run with expansion (revised from 15-40K based on score distribution)
4. No regression in P0/P1 finding recall (measured via calibration logging, validated after 20 runs)
5. Pool-level quality guarantee: ≥1 planner/reviewer at sonnet in every expansion pool
6. Feature gate allows shadow mode rollout for first 10 runs before enforcement

## Review Findings Incorporated

This brainstorm was reviewed by a 4-track flux-review (16 agents across adjacent, orthogonal, distant, and esoteric domains). 53 total findings (1 P0, 18 P1, ~26 P2, ~8 P3). Key changes incorporated:

- **Two-axis tier assignment** (4/4 track convergence): Added `domain_complexity` and `max_model` fields
- **Pool-level quality floor** (3/4 convergence): Added pool assertion after adjustment
- **Escalation advisory** (3/4 convergence): Added tier-escalation-candidate logging
- **Calibration feedback loop** (3/4 convergence): Promoted from deferred to in-scope
- **Safety hardening**: Empty model guard, constitutional floor wiring, fallback validation
- **Operational infrastructure**: Feature gate, shadow mode, merit-order sort, speculative discount

Full synthesis: `docs/research/flux-review/cross-model-dispatch-brainstorm/2026-04-05-synthesis.md`
