---
artifact_type: prd
bead: sylveste-9lp.9
stage: design
---
# PRD: Cross-Model Dispatch for interflux Expansion Pool

## Problem

All expansion pool agents (Stage 2, speculative launches) inherit the same model resolved before Stage 1 runs. Expansion candidates vary in confidence and domain complexity, yet they all consume the same compute tier. A score-1 agent on a simple domain costs the same as a score-3 agent investigating an adjacent P0.

## Solution

Add evidence-proportional tier routing to the expansion dispatch pipeline. Expansion score and domain complexity jointly determine model tier, with constitutional floors from agent-roles.yaml, safety floors as the final invariant, and a pool-level quality guarantee. Deployed behind a feature gate with shadow mode for safe rollout.

## Features

### F1: Core Tier Adjustment Function
**What:** Implement `_routing_downgrade()` and `routing_adjust_expansion_tier()` in lib-routing.sh, with feature gate in budget.yaml.
**Acceptance criteria:**
- [ ] `_routing_downgrade()` handles opus→sonnet, sonnet→haiku, haiku→haiku, empty→haiku, local models→unchanged
- [ ] `routing_adjust_expansion_tier()` takes (agent, current_model, expansion_score, budget_pressure) and returns adjusted model
- [ ] Empty model guard: `[[ -n "$model" ]] || model="haiku"` before safety floor clamp (matches lib-routing.sh idiom)
- [ ] Constitutional floor read from agent-roles.yaml min_model field (not just hardcoded safety agents)
- [ ] Safety floor applied LAST (non-negotiable invariant)
- [ ] Final validation: returned model must be in {haiku, sonnet, opus} or fallback to current_model
- [ ] Feature gate `cross_model_dispatch: { enabled: true, mode: shadow|enforce }` in budget.yaml
- [ ] Score=3 upgrades haiku→sonnet for agents without max_model=haiku ceiling
- [ ] Score=1 skips downgrade for domain_complexity=high agents

### F2: Expansion Scoring Hardening
**What:** Harden expansion scoring in expansion.md with signal deduplication, merit-order sort, and adjacency validation.
**Acceptance criteria:**
- [ ] Each expansion score contribution carries `trigger_source_id`
- [ ] Contributions with same source_id are deduplicated pool-wide (keep max per source across all candidates)
- [ ] Final score = min(sum_of_independent_contributions, 3)
- [ ] Candidates sorted by (expansion_score DESC, role_priority DESC, name ASC) before dispatch
- [ ] Role priority order: planner > reviewer > editor > checker
- [ ] Domain intersection check before score→tier mapping: cap tier at haiku if trigger domain and candidate domain have no overlap

### F3: Expansion Dispatch Integration
**What:** Wire tier adjustment into Stage 2 dispatch and speculative launches with pool-level guarantees.
**Acceptance criteria:**
- [ ] Stage 2 dispatch (Step 2.2c) calls `routing_adjust_expansion_tier` per agent in sorted order
- [ ] Per-agent adjusted model passed directly to Task call via `model:` parameter (Stage 2 dispatch builds its own model map from adjustment results, independent of Step 2.0.5 map)
- [ ] Speculative launches (Step 2.2a.6) call tier adjustment with discounted score: `max(score - 1, 1)`
- [ ] Budget pressure computed as continuous ratio with speculative reserve subtracted
- [ ] Two-pass budget accounting: tentative adjust → recompute pressure → final adjust
- [ ] Pool-level assertion (runs AFTER upgrade pass): ≥1 planner/reviewer-role agent at sonnet after all adjustments
- [ ] If pool assertion violated, upgrade highest-scored planner/reviewer
- [ ] Simultaneous haiku downgrades capped at floor(pool_size / 2)
- [ ] Upgrade pass (runs BEFORE pool assertion): if tokens_saved > 10K, upgrade highest-scored score=2 agent one tier
- [ ] Shadow mode: when `cross_model_dispatch.mode == "shadow"`, log all adjustments with `[shadow]` prefix but dispatch at original models (F1 owns the gate, F5 owns the log format)

### F4: Agent-Roles Extension
**What:** Add `domain_complexity` and `max_model` fields to agent-roles.yaml for all agents.
**Acceptance criteria:**
- [ ] `domain_complexity: low|medium|high` added per agent based on reasoning requirements
- [ ] `max_model: haiku|sonnet|opus|null` added per agent (optional ceiling)
- [ ] Planner-role agents: domain_complexity=high (architectural reasoning)
- [ ] Reviewer-role agents: domain_complexity=high (detailed checking)
- [ ] Editor-role agents: domain_complexity=medium (practical analysis)
- [ ] Checker-role agents: domain_complexity=low (pattern matching)
- [ ] Fields documented in agent-roles.yaml header comments

### F5: Observability
**What:** Add calibration logging, tier field per finding, escalation advisory, and dispatch log enhancements.
**Acceptance criteria:**
- [ ] Per-run calibration emit: (agent, expansion_score, adjusted_tier, finding_count, max_finding_severity, tier_was_downgraded)
- [ ] `tier: haiku|sonnet|opus` emitted per agent in output for future weighted synthesis
- [ ] Escalation advisory: when downgraded agent returns P1+ finding, log `[tier-escalation]` warning
- [ ] Dispatch log includes: domain_complexity, constitutional floor status, pool audit result
- [ ] Budget pressure logged as continuous ratio with reserve amount
- [ ] Savings logged with recycled amount if upgrade pass fires
- [ ] Shadow mode logs all adjustments with `[shadow]` prefix without applying

## Non-goals

- Stage 1 model changes (separate concern, different dispatch path)
- B2 complexity routing enforcement (experiment showed B1+floors is optimal)
- Dynamic model switching mid-review (too risky, validated by flux-review)
- Automatic tier escalation re-dispatch (v2 — data collected in v1)
- flux-review changes (no expansion pool in review mode)
- Agent role reclassification (only adding new fields)

## Dependencies

- sylveste-9lp.6 (haiku routing fix) — CLOSED
- lib-routing.sh — existing, will be extended
- agent-roles.yaml — existing, will be extended
- expansion.md — existing, will be modified
- budget.yaml — existing, will add feature gate

## Feature Dependencies

```
F1 (core function) ← F2 (scoring hardening) ← F3 (dispatch integration)
                   ← F4 (agent-roles extension)
F3 ← F5 (observability)
```

F1 is the foundation. F2 and F4 can be done in parallel (both feed F3). F4 is also a data dependency for F2's domain intersection check and F1's integration tests (unit tests can stub). F3 integrates everything. F5 adds logging on top.

## Open Questions

None — all three original open questions resolved in brainstorm review:
1. Score=3 upgrades haiku→sonnet (yes, with max_model ceiling)
2. Speculative launches use discounted scores (yes, max(score-1, 1))
3. Calibration data in-scope for v1 (yes, minimum viable logging)

## Success Metrics

1. Stage 2 agents route to different tiers based on expansion score + domain complexity
2. Safety floors and constitutional floors never violated (zero violations in first 20 runs)
3. Token savings: 0-15K per run with expansion (conservative estimate per score distribution analysis)
4. No P0/P1 finding recall regression (measured via calibration logging after 20 runs)
5. Pool-level quality: ≥1 planner/reviewer at sonnet in 100% of expansion pools
6. Shadow mode rollout: first 10 runs log-only before enforcement

## Review Lineage

- Brainstorm: `docs/brainstorms/2026-04-04-cross-model-dispatch-brainstorm.md`
- 4-track flux-review (16 agents, 53 findings, 5 convergences): `docs/research/flux-review/cross-model-dispatch-brainstorm/2026-04-05-synthesis.md`
- Track A findings: `docs/research/flux-drive/cross-model-dispatch-brainstorm/synthesis.md`
- Track B findings: `docs/research/flux-drive/2026-04-04-cross-model-dispatch-brainstorm/track-b-orthogonal.md`
- Track C findings: `docs/research/flux-drive/2026-04-04-cross-model-dispatch-brainstorm/synthesis.md`
- Track D findings: `docs/research/flux-drive/2026-04-04-cross-model-dispatch-brainstorm/track-d-esoteric.md`
