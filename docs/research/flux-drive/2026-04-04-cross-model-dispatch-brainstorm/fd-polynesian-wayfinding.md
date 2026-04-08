# fd-polynesian-wayfinding: Signal Quality & Commitment Architecture Review

**Reviewer:** fd-polynesian-wayfinding (Polynesian palu — multi-signal confidence tiering, staged commitment under uncertainty)
**Document:** `docs/brainstorms/2026-04-04-cross-model-dispatch-brainstorm.md`
**Date:** 2026-04-04
**Scope:** Signal hierarchy collapse, correlated-signal inflation, attention-vs-commitment distinction, dead reckoning fallback, progressive commitment model
**Track:** C — Distant domain structural isomorphism

---

## Executive Summary

Polynesian wayfinding reveals the most structurally significant gap in the brainstorm: **expansion scoring collapses heterogeneous signals into a single number, and that number drives a one-shot commitment decision**. The palu (master navigator) never commits course to a single collapsed signal — they weight star paths differently from bird sightings, and they never mistake a correlated cluster of weak signals for a strong independent signal.

Two distinct failure modes emerge from this lens that the brainstorm does not address:

1. **Correlated signal inflation:** Multiple expansion contributors triggered by the same root cause inflate the score beyond its true evidential weight. The brainstorm has no signal-independence check.
2. **Downgrade-as-attention-reduction:** Score=1 maps to a tier downgrade (less capability). But weak signals in wayfinding call for *more* careful attention, not less investment. The mapping is inverted for this case.

---

## P1 Findings

### [P1] Correlated expansion signals inflate the score without increasing independent evidential weight (brainstorm, "Design Space — Option A" section, lines 54–65; "Recommended: Option A + C Hybrid" section, lines 99–114)

The expansion_score is described as a 0–3 integer computed per Stage 2 candidate in Step 2.2b. The scoring algorithm (referenced but not detailed in this brainstorm) presumably adds contributions from different evidence types: P0 finding adjacency, P1 finding adjacency, inter-agent disagreement, domain injection match. A score of 3 might be composed of: P0 adjacency (+2) + domain injection match (+1).

But what if the P0 and the domain injection match are caused by the same root issue? In Polynesian navigation, seeing seabirds flying in a consistent direction and observing a swell deflection that matches a known island's interference pattern are two *independent* signals — they triangulate. But if both are caused by the same island, they confirm rather than add. A navigator who counted them as two separate +1 signals toward a course commitment would be double-counting.

The brainstorm's expansion scoring has no independence requirement. A P0 in fd-architecture about a shared state management pattern might cause: (a) fd-performance to trigger on the same shared-state pattern (P1 adjacency, +2), and (b) a domain injection match for fd-decisions (which also touches state management). The score for fd-decisions accumulates contributions from two signals that trace to the same root cause. The agent gets launched at a higher tier than the independent evidence warrants.

**Failure scenario:** `fd-architecture` finds a P0 in a shared caching layer. `fd-performance` independently finds a P1 in the same caching layer (different symptom, same root). Both findings score toward `fd-resilience`'s expansion. `fd-resilience` accumulates expansion_score=3 from two correlated sources. It launches at full sonnet tier. The caching issue is already covered by the two upstream agents. `fd-resilience` finds a P2 duplication. Two sonnet tokens were spent on a finding that haiku would have matched.

**Smallest fix:** Add a `trigger_source_id` field to each expansion score contribution in Step 2.2b. Before computing the final expansion_score, deduplicate contributions that share the same `trigger_source_id` (same root finding, even if surfaced by different agents). This is a one-pass deduplication in the expansion scoring loop — no architecture change, just a grouping step before summation. The brainstorm's expansion_score would become `min(sum_of_independent_contributions, 3)` rather than `min(sum_of_all_contributions, 3)`.

---

## P2 Findings

### [P2] Score=1 maps to a tier downgrade when the correct response may be higher capability to investigate cautiously (brainstorm, "Design Space — Option A" section, lines 54–65)

The brainstorm maps expansion_score=1 to "downgrade one tier (sonnet→haiku)." The rationale is that weak signals don't justify full investment. This is the correct response to weak signals in a *binary commit/defer* decision — either launch at reduced cost or don't launch at all.

But the Polynesian palu distinguishes between two kinds of weak signals:

1. **Low-confidence directional signals (e.g., a distant cloud formation):** These don't change course but increase attention. The navigator watches more carefully, doesn't yet commit.
2. **High-difficulty signals that are hard to read (e.g., a subtle swell deflection):** These require more skill to interpret, not less. Assigning a junior navigator to read a complex swell pattern because the signal is "weak" produces errors.

The brainstorm's score=1 downgrade conflates these two cases. An expansion candidate with score=1 might be: (a) low-confidence, genuinely exploratory — haiku is appropriate, or (b) a complex domain where the signal is weak but the *interpretation difficulty* is high — haiku will produce incoherent findings.

**Failure scenario:** `fd-decisions` scores 1 on a complex multi-agent dependency negotiation scenario. The weak signal is genuine: only one P2 adjacency triggered the expansion. But `fd-decisions` on a multi-agent dependency scenario requires sonnet-level reasoning to produce a coherent finding. Downgrading to haiku produces a finding that misidentifies which decision boundary is at risk. A real P1 is missed.

**Smallest fix:** Add a `min_interpretation_complexity` field to `agent-roles.yaml` (alongside `model_tier` and `min_model`). This field specifies the minimum tier needed to reason about this agent's domain, independent of expansion score. In `routing_adjust_expansion_tier`, after the score-based downgrade:

```bash
# After score-based adjustment:
min_complexity=$(_agent_min_interpretation_complexity "$agent")
if [[ "$(_tier_rank "$model")" -lt "$(_tier_rank "$min_complexity")" ]]; then
  model="$min_complexity"
  # Log: "complexity floor applied"
fi
```

This is distinct from the safety floor (which applies to fd-safety, fd-correctness). The complexity floor applies to domains where *any* tier below a threshold produces incoherent findings regardless of finding severity.

---

### [P2] No dead reckoning fallback for expansion scoring failure or unexpected input (brainstorm, "Constraints" section, lines 172–179)

When all Polynesian navigation signals fail (overcast sky, no swell, no birds), the palu falls back to dead reckoning: known starting position, elapsed time, current speed, heading. The navigator doesn't stop; they continue on the best estimate of current position.

The brainstorm does not specify what happens when expansion scoring fails to produce a score, or when an agent appears in the expansion pool without a computed `expansion_score`. The implementation sketch (lines 145–158) shows a per-candidate loop: "Read expansion_score (computed above)" — but what if the score is absent, null, or outside the 0–3 range due to a bug in Step 2.2b?

Constraint 6 says "B1 routing remains primary. Cross-model dispatch is an adjustment layer on top of B1 resolution." This implies the fallback exists — if `routing_adjust_expansion_tier` is not called, B1 resolution stands. But this fallback is implicit. The implementation sketch doesn't specify the guard: if `expansion_score` is absent, skip adjustment and use B1 model.

**Smallest fix:** In `expansion.md` Step 2.2b → 2.2c changes, make the absence-guard explicit:

```
For each expansion candidate:
  1. Read expansion_score (computed above). If absent or out of range, use B1-resolved model unchanged.
  2. Compute budget_pressure...
```

One sentence in the spec, zero implementation cost. Converts an implicit fallback into a documented dead reckoning position.

---

## P3 Findings

### [P3] Progressive commitment — launching at a lower tier with an upgrade path if early findings are strong — is absent from the design (brainstorm, entire "Design Space" section)

In Polynesian navigation, commitment is progressive: weak signals justify attention shifts (look toward that heading), moderate signals justify course corrections (adjust 10 degrees), strong signals justify full course commitment (set heading to this island). Resources committed at each stage scale with signal strength, but earlier stages can be revised upward.

The brainstorm makes one-shot tier decisions at dispatch time. There is no provision for "launch at haiku, upgrade to sonnet if first findings exceed a complexity threshold." This is partially addressed by the one-shot tier assignment (the brainstorm explicitly notes "Dynamic model switching mid-review" is out of scope), but the progressive model doesn't require mid-run switching — it requires a *checkpoint* before the agent produces its final synthesis.

A lightweight version: if a haiku-tier agent's intermediate tool-call log shows N tool calls with high complexity indicators (long function traces, multi-file cross-references), an upgrade decision can be made before the final synthesis call. The agent has not yet committed its finding — the upgrade changes only the synthesis call's model, not the investigation phase.

This is P3 because it is an optimization beyond the current scope, not a correctness gap. But it represents the systematic missing piece of the progressive commitment model the brainstorm alludes to but never fully implements.

---

## Summary

The wayfinding lens surfaces one P1 (correlated signal inflation — score composition has no independence check) and two P2s (score=1 downgrade vs. complexity-appropriate tier; implicit vs. explicit dead reckoning fallback). The correlated-signal issue is the most architecturally significant: it means expansion_score can be inflated by a single root cause appearing through multiple evidence channels, causing over-investment in agents whose combined evidence is weaker than the summed score implies.

The attention-vs-commitment distinction (P2) is the most conceptually important: weak signals should sometimes drive *more* careful investigation, not *cheaper* investigation. The complexity floor mechanism addresses this without requiring a complete redesign of the score → tier mapping.
