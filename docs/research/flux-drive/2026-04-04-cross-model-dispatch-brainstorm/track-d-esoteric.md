---
artifact_type: flux-drive-synthesis
track: esoteric
target: docs/brainstorms/2026-04-04-cross-model-dispatch-brainstorm.md
date: 2026-04-04
agents: [fd-byzantine-typikon-liturgical, fd-ayurvedic-constitution, fd-songline-navigation]
verdict: needs-changes
gate: warn
p1_count: 6
p2_count: 6
p3_count: 3
---

# Flux-Drive Track D: Cross-Model Dispatch — Esoteric Review

Target: `docs/brainstorms/2026-04-04-cross-model-dispatch-brainstorm.md`
Focus: Frontier patterns from maximally unexpected knowledge domains — Byzantine liturgical typikon, Ayurvedic constitutional medicine, Aboriginal Australian songline navigation — applied to the brainstorm's expansion-pool tier adjustment mechanism.

---

## Track Summary

Three esoteric agents reviewed the brainstorm from domains with zero surface resemblance to AI agent dispatch. All three independently converged on the same structural gap: `routing_adjust_expansion_tier` is a two-variable function solving a three-variable problem. The missing variable is agent *capacity* — what the agent can actually process at a downgraded tier, given its domain complexity and role constitution.

**The unifying insight from Track D:** Per-agent safety floors are not pool-level quality guarantees. The brainstorm conflates the two. Byzantine typikon distinguishes per-feast minimums from Lenten pool-wide floors. Ayurvedic medicine distinguishes individual constitutional floors from contraindicated treatment combinations. Songline tradition distinguishes individual custodian capability from path coverage redundancy. All three distinctions map to the same gap in the brainstorm.

---

## fd-byzantine-typikon-liturgical

*Byzantine typikarios: feast rank resource allocation with immovable floors and concurrence rules*

### TYP-01 — No Tiebreaker for Equal Expansion Scores (P1)

**Finding:** When two Stage 2 candidates have identical `expansion_score` and budget pressure forces a choice, `routing_adjust_expansion_tier` applies identically to both — it is a stateless per-agent function with no pool context. One agent is dropped by arbitrary iteration order, with no log entry distinguishing "budget exhausted on priority" from "score below threshold."

**Evidence:** `routing_adjust_expansion_tier(agent, current_model, expansion_score, budget_pressure)` — no `sibling_agents`, no `pool_rank`. The dispatch loop in expansion.md has no pre-sort step.

**Fix:** Sort expansion candidates by `(expansion_score DESC, role_priority DESC, name ASC)` before the dispatch loop. `role_priority`: planner > reviewer > editor > checker. Break on budget exhaustion with an explicit log entry.

---

### TYP-02 — No Pool-Level Sonnet Floor During Budget Compression (P1)

**Finding:** When `budget_pressure == "high"`, the brainstorm forces downgrade of all non-exempt agents. Safety floors protect `fd-safety` and `fd-correctness`. But `fd-architecture`, `fd-systems`, and other planners/reviewers have no pool-level guarantee — they can all be downgraded to haiku simultaneously. A pool with only safety-floored agents at sonnet cannot detect architectural or performance failures.

**Evidence:** Recommended Hybrid step 3: "If remaining budget < 50% of Stage 2 estimate: force downgrade all non-exempt." No minimum planner-at-sonnet assertion follows.

**Fix:** After per-agent tier adjustment, assert: at least one planner/reviewer-role agent must remain at sonnet. If budget pressure would violate this, downgrade editors/checkers first and protect planners/reviewers last. One guard assertion before dispatch.

---

### TYP-03 — Speculative Launches Inherit Full-Confidence Tiers (P2)

**Finding:** Speculative launches (Step 2.2a.6) fire on partial Stage 1 signal — fewer findings than full expansion. The brainstorm's Constraint #5 applies identical tier logic: "same logic applies." A score=2 at speculative time represents weaker evidence than score=2 at full-expansion time, but receives the same tier.

**Fix:** Apply speculative discount: `speculative_score = max(score - 1, 1)` for Step 2.2a.6 launches. If the true score (when Stage 1 completes) would have been higher, log the discount but do not re-dispatch.

---

### TYP-04 — Score=3 and Score=2 Produce Identical Tier Outcomes (P2)

**Finding:** The brainstorm maps score=3 → "keep or upgrade" and score=2 → "keep." In practice, the Recommended Hybrid drops the upgrade path — both scores produce "keep." The distinction between P0-adjacent and P1-adjacent evidence produces no routing difference.

**Fix:** Define the upgrade condition explicitly: upgrade haiku→sonnet only when score=3 AND current model is haiku AND no safety floor already covers the agent. One additional case branch in the score mapper.

---

### TYP-05 — Exempt Agent List Is Undefined (P3)

**Finding:** Constraint #2: "Exempt agents bypass cross-model dispatch." The exempt set is never defined. Does `fd-correctness` in expansion mode inherit its safety floor exemption? What about `fd-resilience`?

**Fix:** Add an explicit `expansion_exempt: true` field to relevant agents in `agent-roles.yaml`. Document the distinction: safety-floored agents (hard exemption) vs. safety-adjacent agents (soft floor, can be downgraded but not removed from pool).

---

## fd-ayurvedic-constitution

*Ayurvedic vaidya: prakriti-based treatment intensity — capability must match both evidence AND agent constitution*

### AYU-01 — Constitutional Floor Not Read From agent-roles.yaml (P1)

**Finding:** `routing_adjust_expansion_tier` calls `_routing_apply_safety_floor` as the only agent-specific lookup. The function does not read `min_model` from `agent-roles.yaml`. `fd-architecture` has `min_model: sonnet` for its configured tier — but in expansion mode, this floor is ignored. Score=1 + budget_pressure=high can downgrade `fd-architecture` to haiku even though agent-roles.yaml specifies its floor.

**Evidence:** Function body in Implementation Sketch: `model=$(_routing_apply_safety_floor "$agent" "$model" "expansion")` — only safety floor list checked. No `yq` call to `agent-roles.yaml`.

**Fix:** Before score-based adjustment, read `constitutional_floor = yq ".agents[] | select(.name==\"$agent\") | .min_model" agent-roles.yaml`. Apply as a floor after score/pressure adjustments, before safety floor:

```bash
# After score + pressure adjustments
[[ -n "$constitutional_floor" ]] && model=$(_routing_max "$model" "$constitutional_floor")
# Then safety floor (existing, always last)
model=$(_routing_apply_safety_floor "$agent" "$model" "expansion")
```

---

### AYU-02 — Planner-at-Haiku Failure Mode Misclassified in Risk Table (P1)

**Finding:** The Risk Assessment table classifies "Finding quality degrades on haiku — Medium/Medium." The actual failure mode for planner-role agents at haiku is *confidently incorrect findings*, not merely degraded findings. A haiku `fd-architecture` can produce a finding that recommends introducing an interface layer without modeling that the services share a transaction boundary — the recommendation is wrong, passes synthesis format checks, and misleads implementation. This is a negative failure mode, not a neutral one.

**Evidence:** Risk table entry: "Monitor via intertrust precision scores." Success Criteria measure *recall*, not *precision*. Confidently wrong findings do not reduce recall.

**Fix:** Change the risk classification to "Medium/High" for planner-role haiku assignments. Add to synthesis instructions: findings from planner-role agents adjusted below sonnet should be flagged `planner-downgraded: true` and not escalated above P2 without corroboration from a non-downgraded agent.

---

### AYU-03 — No Domain-Tier Compatibility Assessment (Agni) (P2)

**Finding:** The brainstorm's 6 "What We Have to Work With" inputs include trust multipliers (per-agent precision at native tier) but not per-(agent, tier, domain) compatibility data. An agent's precision at sonnet is not the same as its precision at haiku for a complex domain. `fd-resilience` at haiku reviewing distributed transaction protocols and `fd-people` at haiku reviewing UX copy have entirely different competence profiles at that tier.

**Fix:** Add `domain_complexity: low|medium|high` and `min_trusted_tier: haiku|sonnet|opus` to agent-roles.yaml. The min_trusted_tier is the floor below which the agent's findings carry reduced confidence (not zero — just flagged). Feed into synthesis via `capability-limited` annotation.

---

### AYU-04 — Interspect Calibration Emit Is Out-Of-Scope Without Justification (P2)

**Finding:** Open Question #3 asks whether tier adjustments should feed into interspect for calibration. The infrastructure already exists (interspect, intertrust). The brainstorm answers the question implicitly as "out of scope" with no stated reason. Without calibration emits, tier-adjustment quality can drift without signal.

**Fix:** Emit two interspect events per run: one at dispatch time (agent, original_tier, adjusted_tier, score, pressure) and one after synthesis (agent, adjusted_tier, finding_count, max_severity). This pairs inputs with outcomes. 8 lines of bash, no new dependencies.

---

### AYU-05 — Tier Adjustment Ignores Review Phase (P3)

**Finding:** `routing.yaml` already implements phase-based routing differences. Plan-review mode requires more speculative reasoning than diff-review mode — a haiku planner failure is more likely on abstract architectural plans than on concrete code changes. The tier adjustment function does not accept a phase parameter.

**Fix:** Pass `${FLUX_PHASE:-diff-review}` to `routing_adjust_expansion_tier`. In plan-review mode, apply planner conservatism: do not downgrade planner-role agents below their constitutional floor regardless of score.

---

## fd-songline-navigation

*Songline keeper: sequential knowledge accumulation — each stage's investment justified by previous stage's revelation*

### SNG-01 — Initiation Ceiling: Finding Classes Unreachable at Haiku (P1)

**Finding:** The brainstorm has no model of which finding types require a minimum capability tier. A haiku `fd-architecture` cannot reliably produce findings that require multi-step abstract reasoning chains — not because haiku is incapable, but because it cannot follow the reasoning chain that *validates* the finding. It may produce the correct conclusion with incorrect reasoning. Synthesis cannot detect this.

**Evidence:** Success Criteria: "No regression in P0/P1 finding recall." This measures whether we found what was there, not whether what we found was correct. A confidently wrong finding at haiku satisfies recall while failing precision.

**Fix:** Add `finding_floor_tier` field to agent-roles.yaml for complex-domain agents. `routing_adjust_expansion_tier` emits `${model}:capability-limited` when adjusted tier < finding_floor_tier. Synthesis applies P2-max confidence cap to capability-limited findings without corroboration.

```yaml
# agent-roles.yaml addition
- name: fd-architecture
  model_tier: opus
  min_model: sonnet
  finding_floor_tier: sonnet   # below sonnet, P1+ findings unreliable
```

---

### SNG-02 — Single-Custodian Risk: No Redundancy Check for Downgraded Domains (P1)

**Finding:** Each agent is the sole custodian of its domain. When `fd-resilience` is downgraded to haiku and is the only expansion agent covering resilience patterns, there is no redundancy. The pool has a capability-insufficient single custodian for that domain path with no fallback.

**Evidence:** Constraint #4: "Budget enforcement remains a separate gate. Cross-model dispatch adjusts tiers within the budget envelope." Neither AgentDropout (2.2a.5) nor the expansion scoring checks whether a downgraded agent's domain has an alternative reviewer.

**Fix:** After per-agent tier adjustment, run a single-custodian scan before dispatch: for each capability-limited agent, check whether any other pool agent covers the same domain at sonnet+. If not: (a) if budget allows, upgrade to sonnet; (b) if not, annotate the domain as `single-custodian-haiku` in synthesis input. One post-adjustment loop, ~15 lines.

---

### SNG-03 — Expansion Score Discards Trigger Type (P2)

**Finding:** The Recommended Hybrid explicitly excludes Option B (Finding-Driven Tier Selection) with the reasoning: "Finding severity already feeds expansion_score, so this may be redundant." This conflates severity and type. A P0 security boundary violation and a P0 null check both score 3 but require different minimum tier for trustworthy analysis. The score integer compresses two independent dimensions into one.

**Fix:** Add `trigger_type` to expansion candidate metadata in Step 2.2b. Pass as 5th parameter to `routing_adjust_expansion_tier`. For complex trigger types (security, architectural, transactional), treat score=1 as score=2 — conservative floor for complex-type weak evidence:

```bash
[[ "$trigger_type" =~ ^(security|architectural|transactional)$ && "$score" == "1" ]] \
  && score=2
```

---

### SNG-04 — No Return Journey: Stage 2 Findings Cannot Trigger Re-Expansion (P2)

**Finding:** The dispatch is outward-only: Stage 1 → expansion → Stage 2 → synthesis. A Stage 2 finding that reveals a previously unknown dependency or vulnerability has no path to trigger secondary expansion. The brainstorm does not acknowledge this as a design decision — it is simply out of scope without analysis of the blind spots it creates.

**Fix:** Add to Open Questions: "Should Stage 2 findings that surface new P0/P1 signals be eligible for Stage 2b (secondary expansion, depth ≤ 1)?" This is a question, not an implementation task. Leaving it out of the open questions means it will not be addressed in the first iteration.

---

### SNG-05 — Sequential Position Not Used for Confidence Weighting (P3)

**Finding:** Speculative launches (2.2a.6) fire on partial evidence; standard expansion agents (2.2c) fire on complete evidence. Synthesis has no `launch_phase` annotation to weight speculative findings differently. A speculative finding at haiku and a standard finding at haiku carry identical weight in synthesis, despite different evidential bases.

**Fix:** Annotate expansion candidates with `launch_phase: speculative | standard`. Synthesis prompt: "Speculative findings carry reduced base confidence; require corroboration before escalating to P1."

---

## Track D Cross-Cutting Summary

### Three Independent Convergences

**1. Constitutional capacity is missing from the function signature (AYU-01, SNG-01, TYP-01/02)**
All three agents identify that `routing_adjust_expansion_tier` lacks a capacity dimension. Byzantine typikon: pool-level floor is distinct from per-feast floor. Ayurvedic: patient constitution bounds maximum dose. Songlines: initiation level determines accessible knowledge. In all three: the per-element minimum and the system-level guarantee are different constructs.

**2. The pool has no aggregate quality guarantee (TYP-02, AYU-02, SNG-02)**
All three agents describe a failure mode where per-agent floors compose into a pool with no architectural coverage. The Byzantine liturgy: Lenten compression preserves aggregate minimum sobriety. Ayurvedic: constitutional contraindications are pool-level, not just individual. Songlines: critical path segments require custodian redundancy. All three map to the same missing step: `_expansion_pool_audit()` between tier adjustment and dispatch.

**3. Stage 1 knowledge richness is discarded at the scoring step (SNG-03, AYU-03, TYP-04)**
The expansion score integer compresses finding severity AND finding type into one dimension. The wayfinding/songline lens frames this as sequential knowledge that should carry forward. The Ayurvedic lens frames it as domain constitution. The typikon lens frames it as the granularity gap between 4 scores and 3 tiers. The fix is the same in all three: preserve `trigger_type` and use it as a conservatism modifier for complex-domain downgrade decisions.

### P1 Clusters (4 distinct, 6 total findings)

| Cluster | Findings | Fix |
|---------|----------|-----|
| Constitutional floor not wired | AYU-01, SNG-01 | Read `min_model` + add `finding_floor_tier` to agent-roles.yaml; wire into function |
| Pool-level sonnet floor absent | TYP-02, AYU-02, SNG-02 | Add `_expansion_pool_audit()` to expansion.md before dispatch |
| No tiebreaker for equal scores | TYP-01 | Pre-sort expansion candidates before dispatch loop |
| Finding type discarded | SNG-01, SNG-03 | Add `trigger_type` to expansion candidate metadata + function signature |

### Track D Verdict

**NEEDS_CHANGES** — 4 P1 clusters, all with targeted fixes. No P0 issues. No safety invariants proposed to be weakened. The brainstorm's core mechanism is valid and all three esoteric lenses confirm the A+C hybrid direction. The gaps are *missing* mechanisms, not *wrong* ones.

Implementation can proceed after:
1. Extending `routing_adjust_expansion_tier` to read constitutional floors from agent-roles.yaml
2. Adding `_expansion_pool_audit()` step in expansion.md
3. Adding tiebreaker sort to expansion dispatch loop
4. Adding `trigger_type` to expansion candidate metadata
