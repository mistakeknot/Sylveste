# fd-byzantine-typikon-liturgical Review: Cross-Model Dispatch Brainstorm

**Source:** `docs/brainstorms/2026-04-04-cross-model-dispatch-brainstorm.md`
**Reviewed:** 2026-04-04
**Agent:** fd-byzantine-typikon-liturgical (Byzantine typikarios — feast rank resource allocation)
**Track:** D (Esoteric)
**Bead:** sylveste-9lp.9

---

## Findings Index

- P1 | TYP-01 | Implementation Sketch / lib-routing.sh | Concurrence deadlock: equal expansion scores with no tiebreaker
- P1 | TYP-02 | Design Space / Recommended Hybrid | Lenten floor absent: pool-level capability can collapse to zero under budget pressure
- P2 | TYP-03 | Current Architecture / Step 2.2a.6 | Vigil tier confusion: speculative launches inherit full-confidence tiers without discount for partial evidence
- P2 | TYP-04 | Design Space / Option A | Score-to-tier mapping is under-granular: 4 scores collapsed to 3 tiers loses information
- P3 | TYP-05 | Constraints / #5 | Movable feast gap: no concept of deferrable safety-adjacent agents

---

## TYP-01 — Concurrence Deadlock: Equal Expansion Scores With No Tiebreaker (P1)

**Location:** `docs/brainstorms/2026-04-04-cross-model-dispatch-brainstorm.md`, "Implementation Sketch" / `routing_adjust_expansion_tier`, "Design Space / Option A" score-to-tier table.

**Severity:** P1 — Required to exit quality gate. Determines correctness of the tier assignment algorithm.

**The Byzantine parallel:**
In the typikon, when two feasts of the same rank coincide on the same day, the typikon provides explicit concurrence rules: the higher-ranked transfers, the lower-ranked yields, or they are combined according to specified rubrics. There is never silence on concurrence — the absence of a rule is itself a failure state the typikon guards against.

The brainstorm's tier assignment function `routing_adjust_expansion_tier(agent, current_model, expansion_score, budget_pressure)` applies score-based mapping:

```
score 3 → keep or upgrade
score 2 → keep
score 1 → downgrade one tier
score 0 → haiku (blocked)
```

When two Stage 2 candidates have `expansion_score == 2` and there is only one remaining sonnet slot (budget enforcement has capped expansion pool size), both agents resolve to "keep" their current model. The function does not know about sibling agents — it is called per-agent independently. The budget gate blocks one launch, but which one?

**Concrete failure scenario:** Two expansion candidates — `fd-performance` (score=2, current=sonnet) and `fd-game-design` (score=2, current=sonnet) — both pass the score-2 "keep" path. `FLUX_BUDGET_REMAINING` is 45% of Stage 2 estimate → budget_pressure="high" → both get downgraded to haiku. The budget pressure path (`_routing_downgrade`) applies identically to both. But suppose the budget is tight enough that launching both at haiku still overruns. No tiebreaker exists. The expansion loop breaks arbitrarily on whichever agent is iterated last. One agent is silently dropped with no log entry distinguishing "budget exhausted" from "expansion scored below threshold."

**Evidence:** The `routing_adjust_expansion_tier()` sketch (Implementation Sketch section) takes `(agent, current_model, expansion_score, budget_pressure)` — no `sibling_agents`, no `pool_budget_remaining`, no priority ordering. The function is stateless across the pool.

**Smallest fix:** Add explicit tie-breaking to the expansion loop in `expansion.md` (Step 2.2b → 2.2c transition). Before calling `routing_adjust_expansion_tier`, sort expansion candidates by `(expansion_score DESC, agent_role_priority DESC, agent_name ASC)` where `agent_role_priority` is: planner > reviewer > editor > checker. Iterate in sorted order; break when budget exhausted. Log the tiebreaker used.

```bash
# expansion.md Step 2.2c, before dispatch loop
candidates_sorted=$(sort_expansion_candidates "$candidates" \
  --by "expansion_score:desc,role_priority:desc,name:asc")
```

---

## TYP-02 — Lenten Floor Absent: Pool-Level Capability Can Collapse (P1)

**Location:** `docs/brainstorms/2026-04-04-cross-model-dispatch-brainstorm.md`, "Design Space / Recommended: Option A + C Hybrid", step 3 (budget constraint).

**Severity:** P1 — Required to exit quality gate. Safety floors exist per-agent but the expansion *pool* has no floor.

**The Byzantine parallel:**
The Byzantine typikon operates differently during Lent: all resources are reduced, but the typikon maintains minimum thresholds even during maximum compression. No Sunday of Great Lent drops below Doxology-rank (rank 4 of 6) regardless of how many competing commemorations fall on the same day. The pool-level floor is the invariant; per-feast floors are separate. You can have a Lenten compression *and* still guarantee a minimum level of corporate worship.

The brainstorm's hybrid recommendation specifies:

```
3. Apply budget constraint:
   - If remaining budget < 50% of Stage 2 estimate: force downgrade all non-exempt
```

"All non-exempt" means: every agent without a safety floor gets downgraded. The safety floors protect `fd-safety` and `fd-correctness`. But a review pool where only `fd-safety` and `fd-correctness` run at sonnet — while `fd-architecture`, `fd-systems`, `fd-performance`, `fd-resilience` all run at haiku — is a *functionally blind pool*. No finding about architectural viability, system integration, or performance can be trusted from haiku-tier agents on complex technical domains.

**Concrete failure scenario:** Expansion pool has 5 candidates: `fd-architecture` (planner, score=3), `fd-resilience` (checker, score=2), `fd-performance` (editor, score=2), `fd-people` (checker, score=1). Budget pressure = high (38% remaining). Forced downgrade path: `fd-architecture` → haiku (no min_model for expansion agents), `fd-resilience` → haiku, `fd-performance` → haiku, `fd-people` → haiku. Only `fd-safety` and `fd-correctness` (safety-floored) remain at sonnet. Result: a pool nominally running 6 agents, but with 4 at haiku for complex architectural/resilience/performance domains. The synthesis receives findings from haiku-architecture that cannot detect multi-component race conditions or cascade failures. The review passes. The actual architectural defect ships.

**Evidence:** The Constraints section specifies: "Safety floors are non-negotiable. fd-safety and fd-correctness always ≥ sonnet." No equivalent pool-level floor. agent-roles.yaml has `min_model` only for planner (`sonnet`) and reviewer (`sonnet`) roles — but these apply to the configured tier, not to expansion tier adjustments. Does `routing_adjust_expansion_tier` respect `min_model` from agent-roles.yaml, or only the safety floor list? The brainstorm's function signature (`_routing_apply_safety_floor "$agent" "$model" "expansion"`) implies it checks the agent-level floor, but `fd-architecture`'s `min_model: sonnet` is defined for *non-expansion* mode.

**Smallest fix:** Add a pool-level quality floor to the expansion dispatch logic. Before dispatching, assert: "At least one agent with `model_tier: planner or reviewer` must be at sonnet or above." If budget pressure would violate this, downgrade checkers/editors first, protect planners/reviewers last. One guard condition in `expansion.md`:

```bash
# After per-agent tier adjustment, before dispatch
assert_pool_floor "$expansion_pool" \
  --min-sonnet-roles "planner,reviewer" \
  --min-count 1 \
  || log_warning "Pool floor violation: no planner/reviewer at sonnet tier"
```

---

## TYP-03 — Vigil Tier Confusion: Speculative Launches Inherit Full-Confidence Tiers (P2)

**Location:** `docs/brainstorms/2026-04-04-cross-model-dispatch-brainstorm.md`, "Current Architecture / Step 2.2a.6", "Constraints / #5".

**Severity:** P2 — Degrades quality; creates systematic cost inflation for early speculative agents.

**The Byzantine parallel:**
In the typikon, a Vigil service (the evening before a major feast) allocates specific resources — not the full feast allocation, but more than a regular vespers. The investment is calibrated to the *anticipated* feast, not to full certainty. A Vigil for a Great Feast is more elaborate than a Vigil for a simple feast. Critically, a Vigil for a feast that turns out to have been pre-empted by a concurring Great Feast may be simplified — the investment tracks the anticipated need, not a fixed rate.

Speculative launches (Step 2.2a.6) are described as "early Stage 2 agents" launched on partial evidence before full Stage 1 completion. The brainstorm's constraint #5 states: "Speculative launches (Step 2.2a.6) use the same logic [as regular expansion agents]."

But speculative launches have *structurally lower confidence* — they fire on incomplete Stage 1 signal. An `expansion_score` computed at Step 2.2a.6 is based on fewer findings than one computed at Step 2.2b. The same score (e.g., score=2) at speculative-launch time represents weaker evidence than score=2 at full-expansion time.

**Concrete failure scenario:** `fd-game-design` is speculatively launched at Step 2.2a.6 with score=2 (sonnet) based on 3 of 8 expected Stage 1 findings. When all 8 findings arrive, `fd-game-design` receives score=1 (would have been haiku). The speculative agent has already launched at sonnet; no downgrade is possible. The agent runs at sonnet on evidence that would have warranted haiku. The 35K token savings estimate assumes this doesn't happen systematically.

**Evidence:** Step 2.2a.6 has a max of 2 speculative launches; scores are computed at Step 2.2b (post-Stage 1). At Step 2.2a.6 the score must be estimated, not computed. The brainstorm describes AgentDropout (2.2a.5) pruning redundant candidates but does not describe score computation for speculative agents specifically.

**Smallest fix:** Apply a speculative discount to scores at launch time for Step 2.2a.6 agents. Treat speculative score as `max(score - 1, 1)` — a vigil gets one tier below what the full feast would justify. After Stage 1 completes, if the agent's true score would have been higher, note the discount in logs but do not re-launch (too late). This caps speculative launches at a conservative tier:

```bash
# Step 2.2a.6
speculative_score=$(( expansion_score - 1 ))
speculative_score=$(( speculative_score < 1 ? 1 : speculative_score ))
routing_adjust_expansion_tier "$agent" "$current_model" "$speculative_score" "$pressure"
```

---

## TYP-04 — Score-to-Tier Mapping Is Under-Granular: 4 Scores, 3 Tiers, Lossy Collapse (P2)

**Location:** `docs/brainstorms/2026-04-04-cross-model-dispatch-brainstorm.md`, "Design Space / Option A", score-to-tier table.

**Severity:** P2 — Systematic information loss; scores 3 and 2 are indistinguishable at the tier level.

**The Byzantine parallel:**
The Byzantine typikon has 6 feast ranks (Great Feast, Polyeleos, Doxology, Great Doxology, 6-Verse, Simple commemoration) mapped to distinct resource commitments. A mapping that collapsed Polyeleos and Great Feast into the same resource profile would be considered deficient — those ranks exist *because* the distinctions matter liturgically.

The brainstorm's mapping:

```
score 3 → keep (or upgrade)
score 2 → keep
score 1 → downgrade one tier
score 0 → blocked
```

Scores 3 and 2 map to the same outcome ("keep"). The distinction between score=3 (P0 adjacent) and score=2 (P1 adjacent) — a meaningful evidential difference — produces no routing difference. Score=3 agents should arguably receive *more* investment than score=2 agents (upgrade path), but the brainstorm marks upgrade as "(or upgrade)" with no specification of when upgrading applies.

**Evidence:** Option A footnote: "score 3: keep or upgrade (haiku→sonnet)" — conditional but unpecified. The hybrid recommendation drops the upgrade path entirely: "score 3: keep or upgrade" becomes part of the optional first step, not the canonical path.

**Smallest fix:** Define the upgrade condition explicitly. A natural rule: upgrade only if agent is currently at haiku AND expansion_score == 3 AND agent has no min_model floor already at haiku. This preserves the informational distinctiveness of score=3 without creating budget runaway:

```bash
case "$score" in
  3) [[ "$model" == "haiku" ]] && model="sonnet" ;; # upgrade haiku on max evidence
  2) ;; # keep
  1) model=$(_routing_downgrade "$model") ;;
  0) model="haiku" ;;
esac
```

---

## TYP-05 — No Concept of Deferrable Safety-Adjacent Agents (P3)

**Location:** `docs/brainstorms/2026-04-04-cross-model-dispatch-brainstorm.md`, "Constraints / #2".

**Severity:** P3 — Improvement for future iteration.

**The Byzantine parallel:**
The typikon distinguishes between immovable feasts (fixed to calendar date, cannot transfer) and movable feasts (can be transferred to another day if calendar conflict requires). Safety-floored agents are immovable feasts: their minimum model is non-negotiable. But some agents adjacent to safety concerns — `fd-resilience`, `fd-correctness` in expansion mode — are movable: their floor is softer.

The brainstorm's Constraints specify: "Exempt agents bypass cross-model dispatch. They always launch at their configured tier." The set of exempt agents is not defined in the brainstorm. Is `fd-resilience` exempt? Is `fd-correctness` (when not in its safety-floored role)? If expansion-mode `fd-correctness` is not on the exempt list, it can be downgraded despite its safety-adjacent role.

**Smallest fix:** Add to the scope section: document the exempt agent list explicitly. Recommend two tiers of floor: (a) hard floor — `fd-safety`, `fd-correctness` always ≥ sonnet; (b) soft floor — `fd-resilience`, `fd-architecture` (planner) always ≥ haiku (never removed from pool). This is a documentation addition, not a code change.

---

## Summary

| ID | Severity | Domain | Status |
|----|----------|--------|--------|
| TYP-01 | P1 | Tier assignment ordering | BLOCKING — no tiebreaker for equal-score candidates |
| TYP-02 | P1 | Pool-level quality floor | BLOCKING — budget compression can eliminate all non-safety planners |
| TYP-03 | P2 | Speculative launch tier | Important — systematic over-investment on partial evidence |
| TYP-04 | P2 | Score-to-tier granularity | Important — score=3 and score=2 produce identical outcomes |
| TYP-05 | P3 | Exempt agent list | Improvement — movable vs. immovable floor distinction |

**Verdict: needs-changes** — two P1 structural gaps (tiebreaker, pool floor) must be addressed before implementation.
