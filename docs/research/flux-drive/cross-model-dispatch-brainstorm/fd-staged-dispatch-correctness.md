### Findings Index
- P1 | SDC-1 | "Implementation Sketch" | Speculative launches (Step 2.2a.6) bypass expansion tier adjustment entirely
- P1 | SDC-2 | "Implementation Sketch" | routing_adjust_expansion_tier called per-agent but model map from Step 2.0.5 is a JSON blob — no per-agent override mechanism exists
- P2 | SDC-3 | "Implementation Sketch" | Idempotency gap: calling routing_adjust_expansion_tier twice with different budget_pressure yields different results
- P2 | SDC-4 | "Design Space" | Score=0 case reaches function despite brainstorm claiming "shouldn't happen"
Verdict: needs-changes

## Summary

The brainstorm proposes a sound architecture for cross-model dispatch, but the implementation sketch has two P1-level correctness issues at dispatch boundaries. The speculative launch path (Step 2.2a.6) and the model override mechanism both need design attention before implementation.

## Issues Found

### 1. [P1] SDC-1: Speculative launches bypass expansion tier adjustment

**File:** `interverse/interflux/skills/flux-drive/phases/expansion.md`, Step 2.2a.6
**Brainstorm ref:** Constraint 5, line 178: "Speculative launches (Step 2.2a.6) use the same logic."

The brainstorm states speculative launches should use cross-model dispatch logic, but the implementation sketch places `routing_adjust_expansion_tier` between Steps 2.2b and 2.2c — *after* speculative launches have already fired at Step 2.2a.6.

**Failure scenario:** A speculative launch fires during Stage 1 because a P0 finding triggered expansion_score >= 3. The agent launches at the model from Step 2.0.5's JSON map. Later, when Step 2.2b runs for remaining candidates, they get tier-adjusted models. Result: two agents in the same expansion pool run at inconsistent tiers — the speculative agent at its Step 2.0.5 model, the non-speculative agent at its adjusted model.

**Smallest fix:** Call `routing_adjust_expansion_tier` inside the speculative launch loop (Step 2.2a.6, line 103 of expansion.md: "If any candidate reaches expansion_score >= 3: launch immediately"). The expansion_score is already computed there — pass it through. Budget pressure can default to "low" for speculative launches (they're only 2 agents max).

### 2. [P1] SDC-2: No per-agent model override mechanism in dispatch

**File:** `interverse/interflux/skills/flux-drive/phases/launch.md`, Step 2.0.5
**Brainstorm ref:** Scope, line 187: "Per-agent model override in Stage 2 Task calls"

Step 2.0.5 calls `routing_resolve_agents` which returns a JSON model map (`{"fd-safety": "sonnet", "fd-performance": "sonnet", ...}`). The brainstorm proposes calling `routing_adjust_expansion_tier` per-agent to get adjusted models, but there's no mechanism to *merge* these per-agent overrides back into the model map that the Task dispatch reads.

Currently, each Task call receives `model:` from the JSON map (launch.md Step 2.0.5). The brainstorm's "per-agent model override" would require either: (a) mutating the JSON map after tier adjustment, or (b) bypassing the map entirely for Stage 2 agents and passing the adjusted model directly to each Task call.

**Smallest fix:** Option (b) — for Stage 2 dispatch (Step 2.2c), don't read from the Step 2.0.5 model map. Instead, call `routing_adjust_expansion_tier` inline and pass the returned model directly to the Task tool's `model:` parameter. This keeps Stage 1 dispatch unchanged.

### 3. [P2] SDC-3: Idempotency gap in routing_adjust_expansion_tier

**File:** brainstorm line 121-142 (implementation sketch)

The function takes `budget_pressure` as a parameter. If called twice with different pressure values (e.g., first "low" during speculative launch, then "high" after budget recomputation), it returns different models for the same agent+score. This isn't idempotent.

For the current design this is acceptable if each agent is only dispatched once. But if a retry mechanism or re-dispatch exists (e.g., agent failure + retry), the second call could produce a different tier.

**Question:** Does the retry path in flux-drive re-resolve models, or does it reuse the original dispatch parameters?

### 4. [P2] SDC-4: Score=0 defense

**File:** brainstorm line 135

The sketch handles `score=0` with `model="haiku"` and comments "shouldn't happen (expansion blocked)." But defensive code should either: (a) return early with an error, or (b) log a warning. Silently assigning haiku masks a logic error upstream — if score=0 reaches dispatch, something in the expansion gate (Step 2.2b) failed.

## Improvements

1. Add a sequence diagram to the brainstorm showing the exact call order: Step 2.0.5 (resolve) -> 2.2a.5 (dropout) -> 2.2a.6 (speculative, with tier adjustment) -> 2.2b (score) -> tier adjustment -> 2.2c (dispatch). This would have surfaced SDC-1 during design.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 4 (P0: 0, P1: 2, P2: 2)
SUMMARY: Two P1 issues at dispatch boundaries — speculative launches bypass tier adjustment, and no mechanism exists to override per-agent models in the current dispatch flow. Both have small fixes.
---
<!-- flux-drive:complete -->
