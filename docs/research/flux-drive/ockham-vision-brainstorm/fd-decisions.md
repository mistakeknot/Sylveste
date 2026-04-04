---
artifact_type: flux-drive-review
domain: fd-decisions
target: docs/brainstorms/2026-04-03-ockham-vision-brainstorm.md
revision: 3
reviewer: fd-decisions
date: 2026-04-03
---

# Decision Quality Review — Ockham Vision Brainstorm (Rev 3)

**Target:** `docs/brainstorms/2026-04-03-ockham-vision-brainstorm.md`
**Scope:** Verify D-01/D-02 fixes from prior review; assess new sections on cross-domain min-tier, weight-outcome feedback (20% drift threshold), intercept calibration, and ±12 offset bound.

---

## Previous Finding Verification

### D-01 — Policy-only as permanent identity: RESOLVED

The "Phase 1-3 constraint, re-evaluate at Phase 4" framing is now explicit in the subsection header and elaborated in the body: "This is a phased constraint, not a permanent identity. At Phase 4 (post-Wave 3), re-evaluate whether Ockham should gain dispatch authority for mid-sprint corrections. The constraint forces clean interfaces now; relaxing it later is additive, not disruptive."

The fix is structurally correct. The reframe correctly identifies the constraint as load-bearing for interface cleanliness rather than a permanent design identity. No residual anchoring on the policy-only frame is detectable.

**Status: closed.**

### D-02 — 1h/24h windows anchored on SRE without calibration path: PARTIALLY RESOLVED

The document adds de-escalation logic (stability window equal to the short window) and tightens the Tier 2 trigger to require both windows to breach simultaneously. However, the calibration path for the 1h and 24h values themselves remains unspecified. The doc states these are defaults but does not describe how they are tuned — there is no intercept/distillation path for confirmation window length, no stated collection mechanism, and no fallback statement for what happens when early data suggests the defaults are wrong.

The weight-drift threshold (20%) gains an intercept calibration path in Section 10 ("distills a local model after 50+ evaluations"). The confirmation window lengths get no equivalent. This is an inconsistency: Ockham now has a closed-loop on one numeric parameter (drift threshold) and an open loop on two others (1h, 24h) that are equally empirical.

**Status: partially closed — inconsistency introduced relative to the new Section 10 standard.**

---

## Findings Index

### D-03 — New Anchoring: 20% Drift Threshold Without Derivation

**Severity: P2 (Missed Lens)**
**Section:** Section 10 — Weight-outcome feedback loop
**Lens:** Cone of Uncertainty / Anchoring Bias

The 20% actual-vs-predicted degradation threshold for emitting a Tier 1 INFORM signal is stated as a hardcoded starting point, which is appropriate. The problem is that no derivation or plausible range is offered. A 20% degradation in cycle time could represent noise in a healthy factory (a single slow bead in a 7-day window can move the ratio by 15-25% depending on theme volume). Alternatively, 20% could be far too permissive for a high-priority theme where earlier detection matters.

The anchoring risk is not that 20% is wrong — it is that by stating a specific number without a sensitivity analysis or a bracket, the first implementation will treat it as validated. The number becomes self-confirming once engineers build the threshold into the detection code and the CI passes green.

The document correctly plans intercept distillation after 50 evaluations. But 50 evaluations at one bead per completion, with a 7-day rolling window, may represent 50 days of operation before any calibration happens. During that window, a miscalibrated 20% produces either alert fatigue (too low) or missed degradation (too high), with no mechanism to identify which is occurring.

What happens if the threshold turns out to be wrong by a factor of two in the first 30 days?

### D-04 — ±12 Offset Bound: Assertion Without Reference

**Severity: P2 (Missed Lens)**
**Section:** Section 3 — Dispatch integration via additive weight offsets
**Lens:** Theory of Change / Snake Oil Test

The ±12 bound is presented as derived: "the priority gap between adjacent tiers is ~24 points in lib-dispatch.sh's scoring." The claim is structurally sound — if the gap is 24, then ±12 is exactly one half-gap, preventing tier inversion. The problem is the "~24 points" is asserted, not cited. The word "approximately" does the load-bearing work silently.

If the actual gap is closer to 18 points (as dispatch scoring is perturbed by randomization and floor guards), then a +12 offset applied to a high-P2 bead could push it above a low-P1 bead in edge cases. The invariant the document relies on ("intent can nudge ties and close races, but can never cause a P3 bead to outrank a P1 bead") depends on the gap measurement being accurate.

The logging provision (raw and final scores) provides counterfactual data post hoc. But the decision to set ±12 precedes that data collection. The document would be stronger if it stated the gap measurement method ("measured from lib-dispatch.sh scoring constants" vs. "estimated from observed dispatch behavior") and set the bound conservatively at ±10 until the gap is measured empirically, with an upgrade path to ±12 after one sprint of data.

What would make this look wrong: a single P1 bead consistently losing to an Ockham-boosted P2 bead in the first week of Wave 1 deployment.

### D-05 — Cross-Domain Min-Tier: Sour Spot in Complex Beads

**Severity: P2 (Missed Lens)**
**Section:** Section 6 — Autonomy ratchet, cross-domain beads
**Lens:** Sour Spots / Local vs. Global Optimization

The capability-ceiling model ("a bead that crosses a shadow domain boundary must be executed under shadow rules") is principled in isolation. The sour spot emerges at scale: beads that span many domains will systematically resolve to the most restrictive tier in the set — typically shadow — because shadow is the cold-start default for any domain that has not accumulated evidence yet.

This creates a compounding effect at project start and after any new domain is introduced. A bead touching `interverse/**` (autonomous), `core/**` (supervised), and a newly-created `ops/**` (shadow by default) resolves to shadow. The bead then executes under shadow rules, producing evidence for shadow autonomy rather than for the tiers of the domains it is actually exercising. Shadow evidence does not propagate upward through the ratchet — only domain-specific evidence from supervised and autonomous executions does.

The document does not address this. The Ockham governor could systematically train its evidence base on shadow executions for the most complex cross-domain beads, while simpler single-domain beads accumulate tier-appropriate evidence. Over time, the complex beads that most need higher autonomy are the ones that accumulate the least evidence for promotion.

This is not a bug in the rule. It is an unexamined consequence: the correct short-term safety choice (min-tier) degrades the long-term calibration signal for the beads where calibration matters most.

A signpost would help: after N cross-domain beads resolve to shadow, evaluate whether domain decomposition should be forced (split the bead) rather than accepting shadow execution.

### D-06 — Weight-Drift Feedback Loop: Missing Theory of Change Between Signal and Action

**Severity: P2 (Missed Lens)**
**Section:** Section 10 — Weight-outcome feedback loop
**Lens:** Theory of Change / Explore vs. Exploit

The feedback loop is described at the mechanism level: detect drift, emit Tier 1 INFORM, log `weight_drift` to interspect. What is missing is the causal chain from signal to correction. A Tier 1 INFORM "adjusts dispatch offsets" — but how? The document does not specify whether the 20% drift signal causes Ockham to reduce the drifting theme's offset, freeze new claims until investigation, notify the principal, or do something else entirely.

Without this chain, the feedback loop is a measurement instrument without an actuator. The document distinguishes itself from pure enforcement-driven weight-setting by promising "outcome-derived" weights. But outcome-derivation requires a correction mechanism, not just detection. Detection without correction is expensive instrumentation.

The intercept distillation path (learning a local model after 50+ evaluations) suggests the eventual actuator is automated threshold adjustment. But that is a calibration of the detection threshold, not a correction of the weights that caused the drift. These are different:
- Calibrating the threshold means detecting drift more accurately.
- Correcting the weights means undoing the policy decision that produced the drift.

The Ockham operator — the principal — is not mentioned in the drift response path. If Ockham detects that the "auth" theme's actual cycle time has degraded 25% vs. baseline, the expected response is presumably for the principal to examine whether the auth budget allocation is misconfigured. Nothing in the document routes the signal to that decision.

What happens if weight drift persists for the full 50-evaluation distillation period without principal action? Is that a Tier 2 escalation? Is it self-correcting? The theory of change is absent.

### D-07 — Cold-Start Conservatism Applied Once, Not Continuously

**Severity: P3 (Consider Also)**
**Section:** Section 6 — Cold start
**Lens:** Signposts / Cone of Uncertainty

The cold-start resolution ("if evidence meets the autonomous guard, start at supervised anyway — promotion from supervised to autonomous happens in the first confirmation window if evidence holds") is conservative and well-reasoned. The issue is it treats cold start as a one-time event rather than a recurring condition.

Ockham can encounter cold-start-equivalent conditions mid-lifecycle:
- A domain is renamed or split (old evidence no longer maps cleanly)
- A new agent joins and the domain has no evidence for that agent
- Evidence ages out under the 30-day re-confirmation window without recent activity

The document addresses the 30-day re-confirmation case explicitly ("autonomous domains require periodic re-confirmation"). But domain rename/split and new-agent introduction are not covered. If a `core/**` domain is split into `core/intercore/**` and `core/intermute/**`, both new domains start at shadow regardless of the `core/**` evidence history. This means a domain split causes a supervised-tier regression factory-wide for all cross-cutting work on those domains.

A signpost would help: any domain structure change (create, rename, split) triggers a supervised-tier hold of one confirmation window before evidence from the prior domain can be transferred.

This is a P3 — the 30-day re-confirmation partially mitigates it, and the cold-start rule errs on the right side. But the gap between "initial cold start" and "recurring cold-start-equivalent events" is unexamined.

### D-08 — Intercept Integration: Staged Rollout Absent

**Severity: P3 (Consider Also)**
**Section:** Section 10 — Intercept integration
**Lens:** Starter Option / Explore vs. Exploit

The document commits to intercept integration ("logs every evaluation through intercept, distills a local model after 50+ evaluations") in Wave 1 alongside Tier 1 INFORM. This is a reasonable design target but conflates two independent decisions: (1) whether to ship the feedback loop in Wave 1 at all, and (2) whether to ship the full intercept-calibrated version vs. a simpler observable-but-not-yet-calibrated version.

The document's own Wave 1 wiring list in Section 10 ("ockham_offset read in lib-dispatch.sh + bulk pre-fetch + raw/final score logging + weight-drift feedback from interstat/interspect") is already ambitious. Adding intercept distillation as a Wave 1 deliverable compounds the risk of undershipping Wave 1's core contract: stable offset injection into lib-dispatch.sh.

The starter option would be: ship the detection and logging in Wave 1 (hardcoded 20%, logs drift events), ship the intercept distillation in Wave 2 once there are enough evaluations to seed the model. This is the four-stage closed-loop pattern from PHILOSOPHY.md ("ship stages 1-2 first, calibration is stage 3"). The document conflates stages 2 and 3 into a single Wave 1 deliverable, which is inconsistent with the pattern the project already follows elsewhere.

This does not invalidate the design — it is a sequencing observation, not a structural flaw.

---

## Summary

| ID | Severity | Section | Lens | Status |
|----|----------|---------|------|--------|
| D-01 | — | Policy-only framing | — | Resolved |
| D-02 | P2 | Algedonic signal windows | Cone of Uncertainty | Partially closed — inconsistency with Section 10 standard introduced |
| D-03 | P2 | Weight-drift threshold (20%) | Cone of Uncertainty / Anchoring | New finding |
| D-04 | P2 | ±12 offset bound | Theory of Change / Snake Oil Test | New finding |
| D-05 | P2 | Cross-domain min-tier | Sour Spots / Local vs. Global | New finding |
| D-06 | P2 | Feedback loop theory of change | Theory of Change / Explore-Exploit | New finding |
| D-07 | P3 | Cold-start as recurring condition | Signposts / Cone of Uncertainty | New finding |
| D-08 | P3 | Intercept staged rollout | Starter Option | New finding |

**Net assessment:** Rev 3 closes D-01 cleanly and partially closes D-02. The new sections (weight-drift feedback, min-tier, ±12 offset) are structurally sound additions but introduce four new decision-quality gaps. D-05 and D-06 are the highest-priority: D-05 because the sour spot compounds silently over time, D-06 because a feedback loop without an actuator is the canonical form of incomplete closed-loop work per PHILOSOPHY.md "Receipts Close Loops." D-02's partial closure introduces an inconsistency — the document now holds one numeric threshold to a calibration standard it does not apply to the others.
