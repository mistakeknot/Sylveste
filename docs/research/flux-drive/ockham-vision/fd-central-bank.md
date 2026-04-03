---
artifact_type: flux-drive-review
agent: fd-central-bank
track: B-orthogonal
target: docs/brainstorms/2026-04-03-ockham-vision-brainstorm.md
reviewed_at: 2026-04-03
---

# fd-central-bank Review — Ockham Vision

### Findings Index
- P1 | CB-1 | "Key Decisions §4 — Autonomy ratchet + §3 Algedonic signals" | Pleasure signal measurement is endogenous to Ockham's own prior weight decisions — ratchet promotions may reflect dispatch conditions, not agent capability
- P1 | CB-2 | "Key Decisions §3 — Tier 2 CONSTRAIN + Tier 1 INFORM simultaneous" | No joint feasibility check on combined CONSTRAIN + INFORM weight vector — can produce an empty dispatchable set
- P2 | CB-3 | "Key Decisions §1 — Intent subsystem + Open Question §1" | intent.yaml has no expiry or completion condition — all directives treated as indefinitely valid policy stances
- P2 | CB-4 | "Key Decisions §1 — Intent subsystem" | Intent schema expresses discretionary stances (auth: 40%), not rule-based reaction functions — every recalibration requires active principal engagement
- P3 | CB-5 | "Key Decisions §5 — Safety invariant 5 (Human halt supremacy)" | Halt path technical implementation has latency and file-system dependency — halt supremacy is asserted but depends on Ockham's own infrastructure

Verdict: risky

### Summary

The most acute concern from a policy transmission perspective is feedback endogeneity: when Ockham applies a 1.4x weight to auth beads for six weeks, it systematically selects high-confidence auth beads for dispatch and creates favorable conditions for auth agents. If pleasure signal measurement (first_attempt_pass_rate, cycle_time_trend) runs across this period, the ratchet promotes agents based on evidence that is partly an artifact of Ockham's own prior dispatch decisions, not purely agent capability. A central bank with a similar endogeneity problem would mistake policy-induced growth for genuine productivity improvement and loosen when it should hold. The second acute concern is a joint feasibility gap: simultaneous CONSTRAIN and INFORM signals can combine to produce a weight vector that routes all work to domains with no active constraints, exhausting their queues and leaving Clavain with nothing to dispatch. The intent.yaml expiry gap is a systemic quality issue — principals express sprint allocations that should expire but persist indefinitely as open-ended stances.

### Issues Found

1. **P1 — CB-1: Pleasure signal measurement is endogenous to Ockham's weight decisions**

   The autonomy ratchet uses `first_attempt_pass_rate > threshold` and `cycle_time_trend improving` as promotion criteria (§Key Decisions §4). The ratchet promotion decision is also described as an intercept gate that will be calibrated from examples after 50+ decisions. The evidence endogeneity problem is structural: when Ockham applies a 1.4x weight to auth beads, it routes the highest-confidence, best-scoped auth beads to the most experienced agents in that domain (because those agents have accumulated the highest dispatch priority). The resulting performance improvement in that domain is partially explained by favorable selection conditions that Ockham itself created — easier beads, experienced agents, high-priority routing — not by underlying improvement in agent capability.

   Failure scenario: Agent A's pass_rate improves from 62% to 88% over 30 beads during a six-week auth sprint. Ockham promotes Agent A to autonomous tier in `auth/**`. The six-week improvement coincides with the 1.4x auth weight period, which routed high-confidence auth beads to Agent A and kept ambiguous multi-domain beads away. When the auth sprint ends and weights normalize, Agent A's natural pass_rate on diverse beads reverts to 65%. The autonomous grant causes Agent A to execute core/** changes without principal review at a 65% success rate. The ratchet promoted based on policy-induced evidence.

   Does the pleasure signal measurement control for selection effects? Central banks solve this by comparing outcomes against a counterfactual model. A pragmatic Ockham equivalent: exclude from the promotion evidence set any beads dispatched during a period when the agent's domain had a non-neutral `ockham_weight` (above 1.1x or below 0.9x). Flag the measurement period as "weight-skewed" in the interspect record. Only count performance on neutral-weight beads toward ratchet promotion decisions. This can be implemented as a filter on the evidence query without changing the ratchet logic itself.

2. **P1 — CB-2: Simultaneous CONSTRAIN and INFORM signals can produce an empty dispatchable set**

   The CONSTRAIN tier freezes a domain (§Key Decisions §3 §Tier 2). The INFORM tier applies weight adjustments to other domains (§Key Decisions §3 §Tier 1). These are described as independent mechanisms with independent signal paths. There is no described joint feasibility check.

   Failure scenario: CONSTRAIN fires on `core/**` (three quarantines in 48h) — all core beads are frozen. Simultaneously, INFORM fires on `interverse/**` (cost overrun) — interverse bead weights drop to 0.7x. The remaining non-frozen, non-INFORM-adjusted domains (`os/Skaffen/**`, `apps/Autarch/**`) contain only two dispatchable beads. Clavain's `dispatch_rescore()` runs and produces a weight vector where: core beads have zero-weight frozen status, interverse beads have 0.7x multiplier applied to already-low-priority beads, and the open-pool beads exhaust in two dispatch cycles. Clavain now has an empty dispatchable set while two signals are active. It cannot dispatch without violating a constraint, but no escalation fires because no individual signal has reached its Tier 3 threshold — the combination produced a deadlock that neither signal's logic monitors for.

   Smallest fix: Add a post-weight-computation feasibility check to the Dispatch subsystem: `assert count_dispatchable_beads(weight > W_min) >= N_min` before finalizing the weight vector. If the check fails, fire an INFORM-tier meta-signal: "dispatch-feasibility constraint active" that surfaces to Meadowsyn and adjusts INFORM weights back toward neutral until the dispatchable set exceeds the minimum threshold. This is one post-computation guard, not a restructuring of the signal architecture.

3. **P2 — CB-3: intent.yaml has no expiry or completion condition**

   Central banks maintain a distinction between a time-bounded policy stance (raise rates until inflation is below 2%) and an open-ended policy stance (maintain rates at neutral). intent.yaml is described as storing "principal theme budgets, constraints" (§Key Decisions §1 Intent subsystem) and is written via `ockham intent --theme auth --budget 40%`. Open Question 2 asks about bead-to-theme mapping. Open Question 5 asks about pleasure signal operationalization. Neither question surfaces the expiry problem.

   A principal expressing `auth: 40%` for a two-week sprint has a bounded intent: when auth beads reach zero, the allocation should expire. The system has no way to represent this as a time-bounded directive vs. an ongoing policy stance. The 1.4x auth weight continues applying after the sprint ends, elevating the few remaining low-priority auth cleanup beads over high-priority core work. The principal does not experience this as a governance failure immediately — the effect is gradual and only visible in theme throughput data that requires a report to see.

   The intent.yaml schema should support: `auth: {budget: 40%, until: "2026-04-17"}` and `auth: {budget: 40%, until_bead_count: 0}`. The Dispatch subsystem evaluates the `until` condition at weight-computation time and treats an expired directive as returning to neutral weight (1.0x) rather than persisting indefinitely.

4. **P2 — CB-4: Intent schema expresses discretionary stances, not rule-based reaction functions**

   A Taylor rule maps observable state variables (inflation gap, output gap) to instrument settings (policy rate) without requiring a human decision for each adjustment: `rate = r* + 1.5*(π - π*) + 0.5*(y - y*)`. The formula runs automatically from observed data. The brainstorm describes intent.yaml as storing theme budget allocations set by a principal via CLI. Every change to weights requires active principal engagement.

   For steady-state factory governance, a principal should be able to express a reaction function rather than a discretionary stance: "If cycle_time_trend in auth/** degrades more than 15% below baseline, reduce auth weight by 0.1x per hour until normalized." This is a bounded rule that adjusts automatically within stated parameters. The principal retains oversight by setting the rule, not by making each adjustment.

   Does the intent.yaml schema support conditional weight rules alongside absolute budget allocations? If not, Ockham requires continuous principal attention to maintain calibrated weights across an operating sprint — the equivalent of a central bank that sets interest rates by committee vote every day rather than by rule with periodic committee review.

5. **P3 — CB-5: Human halt supremacy technical implementation depends on Ockham's own infrastructure**

   Safety invariant 5 states: "The principal can halt the entire factory at any time. No Ockham policy can override or delay a human halt" (§Key Decisions §5). The existing halt mechanism is `~/.clavain/factory-paused.json` (§Key Decisions §6). The brainstorm notes: "Single missing wire: `ockham_weight` read in lib-dispatch.sh."

   The lender-of-last-resort function in central banking operates unconditionally outside normal policy frameworks — it does not depend on the central bank's own policy transmission infrastructure to function. The Ockham halt supremacy invariant is implemented through a file that Clavain reads at the top of its dispatch cycle. This is correct for the normal halt path. The concern is: if Ockham's anomaly subsystem has crashed, or if the Dolt backend is in an error state, or if `ic state set` operations are failing — can the principal still write `factory-paused.json` directly and have Clavain honor it immediately?

   The halt path should have zero dependency on Ockham being operational. Clavain's check for `~/.clavain/factory-paused.json` should be a direct filesystem read at the top of every dispatch cycle, independent of any Ockham-mediated state. The brainstorm implies this is already the case (the file exists today), but the new `ockham_weight` integration adds a new Ockham-mediated step to lib-dispatch.sh's dispatch_rescore() — and that step should be structured so its failure degrades to neutral weights rather than blocking dispatch entirely.

### Improvements

1. Add a `weight_skew_flag` to bead interspect records during periods of non-neutral theme weighting (`ockham_weight` outside 0.9-1.1 range). The ratchet promotion logic's evidence query filters to `weight_skew_flag = false` when computing pass_rate for promotion decisions. This requires one additional field in the interspect record write and one filter condition in the ratchet evidence query.

2. Add a post-weight-computation feasibility guard to the Dispatch subsystem: `count_dispatchable_beads_above_threshold() >= N_min`. If the check fails, surface a `dispatch-feasibility` meta-signal to Meadowsyn and apply a neutral-weight correction to INFORM-adjusted domains until the minimum dispatchable set is restored.

3. Extend the intent.yaml schema with optional `until` and `until_bead_count` fields on each theme allocation. The Dispatch subsystem evaluates expiry at weight-computation time; expired directives revert to 1.0x weight. Implement the schema extension first (no logic change), then add the evaluation step.

4. Add support for rule-based weight expressions in intent.yaml alongside discretionary allocations: `auth: {budget: 40%, rule: "if cycle_time_p90 > 1.2 * baseline then weight -= 0.05"}`. Parse these as simple threshold rules at intent-load time, not as arbitrary code. The rule evaluates against Ockham's live factory metrics. This is a Phase 2 capability that requires the intent subsystem to hold a metrics reference — document it as a future extension in the vision, not a Wave 1 requirement.

5. Verify that Clavain's `factory-paused.json` check is the first operation in every dispatch cycle before any Ockham-mediated state reads. If `dispatch_rescore()` reads `ockham_weight` from bead state before checking the pause file, reorder the operations. Add an explicit comment in lib-dispatch.sh marking the pause check as "halt supremacy invariant — must precede all Ockham reads."
