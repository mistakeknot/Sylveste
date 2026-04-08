# Flux-Drive Review: Cross-Model Dispatch Brainstorm

**Document:** `docs/brainstorms/2026-04-04-cross-model-dispatch-brainstorm.md`
**Bead:** sylveste-9lp.9
**Track:** A (Adjacent) — domain-specialist review
**Date:** 2026-04-04
**Agents:** 5 Project Agents (fd-staged-dispatch-correctness, fd-safety-floor-invariant, fd-budget-integration, fd-expansion-signal-quality, fd-backward-compat)

## Verdict: NEEDS-CHANGES

The brainstorm correctly identifies the problem (uniform model tier for Stage 2 agents wastes tokens) and proposes a sound architecture (expansion-score-driven adjustment with budget pressure, safety floors last). However, the review surfaces 1 P0, 5 P1, and 9 P2 findings across dispatch correctness, safety invariants, budget accounting, signal quality, and backward compatibility.

**The design is viable but not implementable as-is.** The P0 and P1 findings must be addressed in the brainstorm before writing an implementation plan.

## Consolidated Findings

### P0 (1 finding)

| ID | Agent | Title | Fix |
|----|-------|-------|-----|
| SFI-1 | fd-safety-floor-invariant | Empty model from `_routing_downgrade` bypasses safety floor — `_routing_apply_safety_floor` returns empty on empty input | Guard: `[[ -n "$model" ]] \|\| model="haiku"` before floor clamp. Add INVARIANT comment. |

### P1 (5 findings)

| ID | Agent | Title | Fix |
|----|-------|-------|-----|
| SDC-1 | fd-staged-dispatch-correctness | Speculative launches (Step 2.2a.6) bypass tier adjustment — fires before routing_adjust_expansion_tier is called | Call tier adjustment inside the speculative launch loop; expansion_score is already available there |
| SDC-2 | fd-staged-dispatch-correctness | No per-agent model override mechanism — Step 2.0.5 returns a JSON map with no way to inject per-agent adjustments | For Stage 2 dispatch, pass adjusted model directly to Task calls instead of reading from Step 2.0.5 map |
| SFI-2 | fd-safety-floor-invariant | `_routing_downgrade()` does not exist — no implementation, no edge case handling | Implement using `_routing_model_tier()`: opus->sonnet, sonnet->haiku, haiku->haiku, unknown->unchanged |
| BI-1 | fd-budget-integration | Budget pressure computed from pre-adjustment estimates — conservative bias | Two-pass: tentative adjustment from score, then pressure from adjusted costs, then final adjustment |
| BC-1 | fd-backward-compat | No feature gate — no way to disable cross-model dispatch without code revert | Add `cross_model_dispatch.enabled` to budget.yaml; gate dispatch path |

### P2 (9 findings)

| ID | Agent | Title |
|----|-------|-------|
| SDC-3 | fd-staged-dispatch-correctness | Idempotency gap: different budget_pressure -> different result |
| SDC-4 | fd-staged-dispatch-correctness | Score=0 silently assigns haiku instead of logging error |
| SFI-3 | fd-safety-floor-invariant | 5 agents have min_model floors (not just 2) — brainstorm understates floor coverage |
| SFI-4 | fd-safety-floor-invariant | Namespace stripping consistency (actually safe as-is) |
| BI-2 | fd-budget-integration | Budget tracker not updated after tier adjustment — inflates reported costs |
| BI-3 | fd-budget-integration | AgentDropout savings not reflected in budget pressure |
| BI-4 | fd-budget-integration | estimate-costs.sh lacks per-model granularity |
| BC-2 | fd-backward-compat | flux-review shares code paths — standalone function is safe, flag on routing_resolve_agents is not |
| BC-3 | fd-backward-compat | New log format "Estimated savings" prefix collides with AgentDropout's |

### P1 (Signal Quality — affects projected value)

| ID | Agent | Title |
|----|-------|-------|
| ESQ-1 | fd-expansion-signal-quality | Score distribution clusters at 2 — tier adjustment is a no-op for ~70% of agents |

This is categorized separately because it doesn't block implementation but fundamentally affects the projected value (15-40K savings -> 0-15K savings).

## Cross-Agent Themes

### Theme 1: Missing primitives

Two brainstorm-assumed primitives don't exist: `_routing_downgrade()` (SFI-2) and per-agent model override in Task dispatch (SDC-2). These are the foundation of the implementation — the brainstorm should specify them.

### Theme 2: Pipeline ordering

Three findings converge on ordering: speculative launches fire before tier adjustment (SDC-1), budget pressure uses pre-adjustment costs (BI-1), and safety floors must be provably last (SFI-1). A sequence diagram would have caught all three.

### Theme 3: Operational readiness

The brainstorm lacks operational infrastructure: no feature gate (BC-1), no shadow mode (BC-4 improvement), no rollback criteria, no log format coordination (BC-3). Every comparable feature in the codebase has these (AgentDropout: `dropout.enabled`, B2 routing: `mode: off|shadow|enforce`).

### Theme 4: Signal entropy

The expansion score (0-3) doesn't carry enough entropy for meaningful tier differentiation (ESQ-1). Most agents score 2 ("keep model"). The brainstorm should either refine the score (expose trigger_type as a secondary signal) or acknowledge that savings will be modest.

## Recommended Changes to Brainstorm

**Must-fix before /write-plan:**

1. **Add `_routing_downgrade()` specification** — implementation using `_routing_model_tier()`, handling of edge cases (haiku, empty, local models).

2. **Add speculative launch integration** — call `routing_adjust_expansion_tier` inside Step 2.2a.6's launch loop, not just between 2.2b and 2.2c.

3. **Specify per-agent model override mechanism** — "Stage 2 dispatch passes adjusted model directly to Task, bypassing the Step 2.0.5 JSON map."

4. **Add feature gate** — `cross_model_dispatch: { enabled: true, mode: shadow|enforce }` in budget.yaml, following the B2 complexity routing pattern.

5. **Add empty-model guard** — before safety floor clamp, assert model is non-empty.

**Should-fix (improves accuracy):**

6. **Two-pass budget pressure** — compute tentative adjustments, then recalculate pressure from adjusted costs.

7. **Post-adjustment cost update** — feed adjusted tier back to budget tracker and interstat cost report.

8. **Score composition annotation** — add `trigger_type` to expansion candidates so score=2-from-P1 and score=2-from-disagreement can be distinguished.

**Consider:**

9. **Shadow mode rollout** — log tier adjustments without applying them for the first 10 runs, then enable enforcement. Mirrors B2 pattern.

10. **Revise savings estimate** — 0-15K per run is more realistic given score distribution. Adjust success criterion accordingly.

## Agent Concordance

All 5 agents agreed on the verdict (needs-changes). No disagreements between agents. The strongest convergence was on the missing `_routing_downgrade` function (cited by SFI-2 and implicitly by SDC-1) and the need for a feature gate (BC-1, with operational patterns referenced by ESQ-3 and BI-2).

---

*Generated by flux-drive Track A (Adjacent) review. 5 project agents, single-stage dispatch.*
*For orthogonal/esoteric perspectives, run Track B/C.*
