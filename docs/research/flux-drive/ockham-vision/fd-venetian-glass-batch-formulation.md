### Findings Index
- P1 | VG-01 | "Key Decisions §2" | Undefined composition order between intent, authority, and anomaly multipliers
- P1 | VG-02 | "Key Decisions §2 / Open Questions §1" | No weight floor — extreme theme budgets produce dispatch starvation
- P2 | VG-03 | "Key Decisions §2 / Key Decisions §5" | ockham_weight stored as scalar without derivation provenance
- P3 | VG-04 | "Key Decisions §3" | Anomaly tier transitions are phase changes, not smooth curves — composition should reflect this

Verdict: needs-changes

### Summary

Ockham's dispatch formula (`final_score = raw_score * ockham_weight`) assumes that intent, authority, and anomaly contributions are multiplicatively independent — that they can be combined in any order and still produce the intended priority ranking. This is the glassmaker's linear superposition assumption, and it fails for the same reason: the individual ingredients are not independent. An intent boost (weight 1.4 from a 40% theme budget) combined with an authority penalty (from autonomy_tier=shadow under CONSTRAIN) produces a composition that oscillates depending on which factor is applied first — multiplication is commutative, but priority dominance is not. Authority constraint should suppress intent boost, not multiply with it at equal weight. The formula encodes no such ordering. A second structural gap: theme budgets have no specified floor. A 5% theme allocation does not specify what ockham_weight that produces — if the mapping is linear from budget percentage to weight, the 5% theme may generate a weight so low that, when multiplied against already-below-average raw scores, the resulting final_score is permanently sub-threshold for dispatch. This is unfusible-sand glass: individually defensible ingredients that combine to produce something unworkable. A third gap is provenance: `ic state set "ockham_weight" <bead_id>` writes a scalar. Nothing in the current design requires a companion record of the contributing factors (intent contribution 1.4, authority penalty 0.86, anomaly modifier 1.0), so Interspect cannot distinguish "intent was high but authority dragged it down" from "intent was moderate and authority was neutral" — the calibration surface is collapsed.

### Issues Found

1. **P1 — VG-01: Multiplier composition order is undefined, allowing authority constraint to be overridden by intent boost**

   The vision specifies `final_score = raw_score * ockham_weight` (§ "Key Decisions §2") and states that Ockham "writes weights via `ic state set "ockham_weight" <bead_id>`" — a single scalar. It does not specify whether ockham_weight is the product of intent × authority × anomaly factors or whether separate multipliers are applied sequentially in lib-dispatch.sh's `dispatch_rescore()`. If ockham_weight is a pre-blended scalar, the composition order is baked into the computation that wrote it. If separate multipliers are applied in `dispatch_rescore()`, the order is undefined. Either way: a Tier 2 CONSTRAIN signal is supposed to freeze a domain — but the vision simultaneously maintains per-bead intent weights. A bead in the constrained domain with intent weight 1.4 may receive a final ockham_weight above 1.0 if the authority penalty (e.g., 0.7 for shadow tier) is insufficient to overcome the intent boost. The bead appears "ready to dispatch" to a scoring system that sees only the final multiplier. The multiplicative interaction does not implement dominance — it implements arithmetic balance.

   Failure scenario: Theme "auth" at 40% budget generates intent weight 1.4 for auth beads. A Tier 2 CONSTRAIN fires on the auth domain after three quarantines. Authority component becomes 0.7 (shadow). Final ockham_weight = 1.4 × 0.7 = 0.98. The bead is dispatched at near-neutral priority rather than frozen, because the authority penalty does not dominate the intent boost — it negotiates with it. The CONSTRAIN tier's guarantee of "freeze domain" is silently violated.

   Smallest fix: Specify in the weight computation that CONSTRAIN and BYPASS signals produce a sentinel weight (e.g., 0.0 or a named constant `WEIGHT_FROZEN`) that overrides the intent component entirely, rather than multiplying with it. This is a one-line dominance rule: `if anomaly_tier >= CONSTRAIN: return WEIGHT_FROZEN`.

2. **P1 — VG-02: No weight floor — extreme theme budgets produce starvation**

   Open Question §1 asks "Does a freeze zero out the weight or set it to a sentinel?" but the analogous question for non-frozen low-budget themes is unasked: what ockham_weight does a 5% theme allocation produce? The vision states theme budgets are expressed as percentages (e.g., "auth 40%") and that weights are multipliers, but the budget-to-weight mapping function is not specified. If the mapping is linear (5% → 0.5, 40% → 1.4, etc.) then a 5% theme produces a 0.5× multiplier. For a bead with below-average raw score (say 0.4 out of 1.0), the final_score = 0.4 × 0.5 = 0.2. Meanwhile, the 40% theme's beads produce final_score = 0.8 × 1.4 = 1.12. The 5% theme beads are never dispatched — they sit at the bottom of the queue indefinitely as the 40% theme continuously wins dispatch slots.

   Failure scenario: A security hardening theme at 5% budget contains three critical beads that have no schedule dependency. A feature theme at 80% budget produces 20 active beads. Ockham weights give the security beads effective score ~0.2 and feature beads effective score ~1.1. After 40 dispatch cycles, the security beads remain undispatched. A vulnerability ships. The 5% budget expressed "lower priority" but Ockham's arithmetic interpretation was "never dispatch."

   Smallest fix: Introduce a weight floor constant (e.g., `WEIGHT_FLOOR = 0.6`) applied after theme-budget-to-weight mapping, such that no bead receives a multiplier below 0.6 regardless of budget allocation. Document this floor in the intent.yaml schema alongside the budget field.

3. **P2 — VG-03: ockham_weight stored as scalar — derivation chain is lost, calibration is impossible**

   The vision specifies that Ockham writes weights via `ic state set "ockham_weight" <bead_id>` (§ "Key Decisions §2"). Safety invariant #4 requires that "every authority decision produces a durable receipt in interspect." However, a scalar weight is not an authority decision — it is the output of a composition. Interspect will record that bead X received ockham_weight=0.98, but not that this was the product of intent=1.4 (auth theme at 40%), authority=0.7 (shadow tier after CONSTRAIN), anomaly=1.0 (no active anomaly signal). Future calibration of individual components — "is the shadow tier penalty too severe?" or "is the 40% theme weight too aggressive?" — requires the decomposed inputs, not the blended output. Without them, Ockham calibration is equivalent to evaluating a glass batch by measuring the refractive index of the final piece without knowing the ingredient ratios.

   Smallest fix: Write a companion key alongside the scalar: `ic state set "ockham_weight_provenance" <bead_id>` with a JSON value `{"intent": 1.4, "authority": 0.7, "anomaly": 1.0, "theme": "auth", "domain_tier": "shadow", "computed_at": <epoch>}`. This requires no schema changes to lib-dispatch.sh (which reads only ockham_weight), but gives Interspect calibration the decomposed surface it needs.

4. **P3 — VG-04: Anomaly tier transitions are phase changes, not gradient adjustments — weight formula should reflect this**

   The three anomaly tiers (INFORM, CONSTRAIN, BYPASS) are described in terms that imply qualitative discontinuity: CONSTRAIN "freezes" the domain; BYPASS "halts" the factory. But the current dispatch formula treats anomaly state as another weight multiplier, implying continuous arithmetic. The maestro's insight is that a glass batch at 95% silica is not "very much silica" — it is a phase change, sand that will not melt at normal furnace temperatures. CONSTRAIN is not "lower weight for the domain" — it is a state that should remove domain beads from the dispatch queue entirely, regardless of their intent weight. The current formula's arithmetic structure resists expressing this discontinuity cleanly. Does the anomaly subsystem produce a continuous modifier or a discrete gate? The vision does not specify.

   Suggested improvement: Separate the anomaly state from the weight computation entirely. Treat INFORM as a weight modifier (part of ockham_weight). Treat CONSTRAIN and BYPASS as dispatch eligibility gates that precede the weight computation — a bead in a CONSTRAIN domain is ineligible for dispatch regardless of its ockham_weight, checked in `dispatch_rescore()` before the score is returned.

### Improvements

1. Define a composition priority rule: anomaly gates take precedence over authority multipliers, which take precedence over intent boosts. Document this hierarchy in the intent.yaml schema comments and enforce it in the weight computation function, not in lib-dispatch.sh.

2. Specify the budget-to-weight mapping function explicitly in the Ockham design document, including the floor constant, the ceiling constant, and the behavior at 0% and 100% allocations. A lookup table or piecewise function is more legible than a prose description.

3. Require derivation provenance alongside every ockham_weight write. The provenance record need not be in the same storage system — a separate `ockham_weight_provenance` key in ic state with a JSON blob is sufficient — but its existence should be an invariant enforced by the weight-writing function.

4. Add a mid-bead observation hook to address the feedback delay: rather than waiting for bead completion to evaluate whether Ockham's weight was appropriate, instrument the point at which an agent first touches a bead (claiming it) as an intermediate signal. This is the glass maestro's "draw a sample from the crucible mid-melt" — not a final evaluation, but an early indicator that the dispatch decision was reasonable.
