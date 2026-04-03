### Findings Index
- P1 | DOF-01 | "Dispatch integration via weight multipliers" | Intent-to-weight formula undefined -- "40% budget" has no canonical mapping to a weight multiplier
- P1 | DOF-02 | "Dispatch integration via weight multipliers" | Low-budget themes permanently starved due to multiplicative composition with integer scoring
- P2 | DOF-03 | "Dispatch integration via weight multipliers" | No feedback from actual dispatch share to weight correction -- open-loop allocation
- P2 | DOF-04 | "Dispatch integration via weight multipliers" | Priority inversion under review backpressure interacts badly with theme weights
- P3 | DOF-05 | "Four subsystems" | Perturbation range (0-5) in dispatch_rescore can override small Ockham weight differences

Verdict: needs-changes

### Summary

The dispatch integration point is the critical interface between Ockham policy and Clavain execution: `final_score = raw_score * ockham_weight`. Analyzed numerically against the actual scoring in `dispatch_rescore()` (lib-dispatch.sh:133-218), this multiplicative composition has well-defined behavior for high-budget themes but produces starvation for low-budget themes. The root issue is that the brainstorm gives one example ("Auth bead with 40% budget gets weight 1.4; unlinked bead gets 0.6") but does not define the function that maps budget percentages to weights. Without this function, every implementation will derive different weights, and the fairness properties of the system are unanalyzable.

### Issues Found

1. **P1 | DOF-01 | Intent-to-weight formula is undefined**

   Section 2 (line 51) states: "Auth bead with 40% budget gets weight 1.4; unlinked bead gets 0.6." But this is a single example, not a formula. Key questions that must be answered:

   - Is the mapping linear? If 40% -> 1.4, does 20% -> 1.2? Does 10% -> 1.1?
   - What is the base weight? The example implies 1.0 is neutral (100%/N_themes?), with 1.4 being 40% above baseline and 0.6 being 40% below. But this interpretation breaks: if there are 3 themes at 40%/30%/30%, the weights would be 1.4/1.3/1.3, which don't sum to 3.0 (neutral across all themes). They sum to 4.0.
   - What does "unlinked" mean? A bead not tagged to any theme. Is 0.6 a constant for all unlinked beads, or derived from the remaining budget after themes are allocated?
   - Do weights need to be normalized? If all weights are > 1.0, the multiplication uniformly inflates scores without changing relative ordering (only the Ockham weight differences matter, not absolute values).

   **Failure scenario:** Two implementations derive different weight functions. Implementation A uses `weight = 1.0 + (budget - mean_budget)`. Implementation B uses `weight = budget / mean_budget`. For a 3-theme split of 50%/30%/20%, A produces [1.17, 0.97, 0.87] and B produces [1.5, 0.9, 0.6]. The ordering is the same but the magnitude differs significantly -- under B, a 20% theme bead with raw_score 80 gets final_score 48, while under A it gets 69.6. This is a 30% difference in final score from an implementation ambiguity.

   **Fix:** Define the canonical formula in the vision. Recommended: `weight = budget_fraction / (1 / N_themes)` where N_themes is the number of active themes. This normalizes so that equal-budget themes get weight 1.0, above-average themes get > 1.0, and below-average themes get < 1.0. For 40%/30%/30% with 3 themes: weights are 1.2/0.9/0.9. For unlinked beads, define a floor weight (e.g., 0.5) configurable in intent.yaml.

2. **P1 | DOF-02 | Low-budget themes permanently starved under multiplicative scoring**

   The existing scoring formula in lib-dispatch.sh produces integer scores (priority 40%, phase 25%, recency 15%, deps 12%, WIP 8%, summing to ~100 max). After Ockham weight multiplication, the score feeds into a ranking. But `dispatch_rescore()` adds random perturbation of 0-5 (line 204) and subtracts review backpressure (line 205).

   **Numeric walkthrough:** Consider two beads:
   - Bead A: raw_score 70, theme budget 40%, ockham_weight 1.4 -> final 98
   - Bead B: raw_score 75, theme budget 10%, ockham_weight 0.6 -> final 45
   
   Bead B has a higher raw priority but its theme weight crushes it. With perturbation range 0-5, Bead B's maximum possible score is 50, while Bead A's minimum is 93. Bead B can never win against any bead from the 40% theme, regardless of raw priority.

   This is theme starvation. The 10% theme never gets dispatched as long as the 40% theme has any ready beads. Over a 100-bead run, the 10% theme gets 0% of dispatches instead of 10%.

   **Fix:** Two complementary mechanisms: (a) **Starvation floor**: if a theme's actual dispatch share is below 50% of its budget share for more than N dispatch cycles, temporarily boost its weight to 1.0 (neutral) until it catches up. This is analogous to the CFS (Completely Fair Scheduler) in Linux. (b) **Additive composition**: instead of `raw_score * weight`, use `raw_score + weight_offset`, where weight_offset is derived from the budget. Additive composition preserves raw priority ordering within a theme while giving budget themes a bonus, rather than a multiplier that can crush low-budget themes.

3. **P2 | DOF-03 | No feedback from dispatch share to weight correction**

   The brainstorm defines intent budgets (40% auth, 30% performance, etc.) and weight multipliers, but does not specify any mechanism to track whether actual dispatch share matches intended budget share. This is an open-loop allocation: the principal sets budgets, Ockham translates to weights, and the system never checks whether the weights achieved the intended outcome.

   **Consequence:** Due to non-uniform bead distribution (some themes have more ready beads than others), actual dispatch share diverges from budget share. A theme with many ready beads will over-consume even at a low weight because it has more candidates in the scoring pool. A theme with few ready beads will under-consume even at a high weight because there are no beads to dispatch.

   **Fix:** Add a dispatch-share feedback loop (Wave 1 compatible): Ockham tracks actual dispatches per theme over a rolling window (e.g., last 20 dispatches). If actual_share / budget_share deviates beyond a tolerance band (e.g., +/- 20%), Ockham adjusts the weight multiplier proportionally. This is proportional-integral (PI) control applied to dispatch fairness. The integral term prevents steady-state error; the proportional term provides fast response.

4. **P2 | DOF-04 | Review backpressure interacts adversely with theme weights**

   In `dispatch_rescore()` (lib-dispatch.sh:156-163), review backpressure subtracts a penalty from all bead scores equally: `pressure_penalty = (review_depth - threshold) * 5`. This penalty is applied after Ockham weight multiplication. For low-weight themes, the penalty constitutes a larger fraction of the final score.

   **Numeric walkthrough:**
   - Bead A: raw 70 * weight 1.4 = 98, minus pressure_penalty 15 = 83
   - Bead B: raw 75 * weight 0.6 = 45, minus pressure_penalty 15 = 30
   
   Pressure reduces Bead A by 15% but Bead B by 33%. Under backpressure, low-budget themes are disproportionately deprioritized. This is a priority inversion: the review queue depth (which may be caused by high-budget theme beads) penalizes low-budget themes more than high-budget themes.

   **Fix:** Apply the pressure penalty before Ockham weight multiplication: `final_score = (raw_score - pressure_penalty) * ockham_weight`. This makes the penalty proportional to theme budget rather than inversely proportional. Alternatively, make the penalty a multiplicative factor: `final_score = raw_score * ockham_weight * (1 - pressure_fraction)` where `pressure_fraction = min(1.0, pressure_penalty / 100)`.

5. **P3 | DOF-05 | Perturbation range can override small Ockham weight differences**

   `dispatch_rescore()` adds `RANDOM % 6` (0-5) for tie-breaking (line 204). If two beads have the same raw_score but different Ockham weights producing a final_score difference of < 5, the perturbation can reverse the ordering.

   **Numeric walkthrough:**
   - Bead A: raw 60 * weight 1.1 = 66, + perturbation 0 = 66
   - Bead B: raw 60 * weight 0.9 = 54, + perturbation 5 = 59

   The intended ordering (A before B) is preserved here. But:
   - Bead A: raw 60 * weight 1.05 = 63, + perturbation 0 = 63
   - Bead B: raw 60 * weight 0.95 = 57, + perturbation 5 = 62

   Nearly reversed. For themes with similar budgets (e.g., 35% vs 30%), Ockham weights will be close (e.g., 1.05 vs 0.95), and perturbation noise will frequently override the policy signal.

   **Improvement:** Not a blocking issue -- perturbation exists for good reason (prevents deterministic lock-in). But the vision should acknowledge that Ockham weight differences below the perturbation range (~5 points) are not reliably enforced, and budget splits closer than ~15% will have stochastic rather than deterministic dispatch ordering. This is a design constraint that should inform how the principal sets budgets.

### Improvements

1. Include a "Dispatch Arithmetic" section in the vision with a worked example showing 3 themes, 5 candidate beads, the full scoring pipeline (raw_score -> weight multiplication -> pressure penalty -> perturbation -> final ordering). This makes the composition verifiable and reveals edge cases like starvation and priority inversion before implementation.

2. Define "unlinked bead" semantics explicitly. The brainstorm mentions unlinked beads get weight 0.6, but many beads will be untagged in early usage. If 70% of beads are unlinked, the 0.6 weight effectively becomes the majority weight and the theme weights only differentiate the tagged minority. Consider a "default theme" that captures unlinked beads with a configurable budget share.

3. Add a monitoring metric to the vision: `dispatch_fairness_index = 1 - max(|actual_share_i - budget_share_i| for all themes i)`. This single number (range 0-1, higher is better) tells the principal whether Ockham weights are achieving the intended allocation without requiring them to inspect per-theme dispatch counts. Surface it in `ockham health` and Meadowsyn.
