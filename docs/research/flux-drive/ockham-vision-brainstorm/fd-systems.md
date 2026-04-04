# fd-systems — Ockham Vision Brainstorm (Rev 3 Re-Review)

**Reviewer:** fd-systems (Flux-Drive Systems Thinking)
**Document:** `docs/brainstorms/2026-04-03-ockham-vision-brainstorm.md`
**Date:** 2026-04-03
**Review type:** Re-review (rev 3). Verify fixes for SYS-01, SYS-02, SYS-03, SYS-07. Evaluate new sections SUBAK-01 and cross-domain min-tier resolution for novel systemic risks.

---

## Findings Index

- P1 | SYS-01 | "Ratchet runaway prevention" | FIXED — balancing loop present, but 30-day re-confirmation window is unsynchronized across domains, creating a phase-shifted oscillation risk
- P1 | SYS-02 | "Tier 2 — CONSTRAIN" | FIXED — supervised continuation specified; residual: freeze→supervised agents accumulate deferred failures that re-trigger CONSTRAIN after thaw
- P1 | SYS-03 | Three-speed oscillation | PARTIALLY FIXED — tier mechanisms disambiguated; the 7-day weight-drift window (SUBAK-01) and the 30-day re-confirmation window (SYS-01) now introduce a new temporal mismatch cascade
- P1 | SYS-07 | Pleasure signals deferred | FIXED — ships with Wave 1
- P1 | SYS-NEW-01 | "Weight-outcome feedback loop" | SUBAK-01 closes the outcome loop for theme-level weight drift but does not close it for ratchet promotion decisions — two feedback loops with different time horizons and conflicting correction signals now coexist
- P1 | SYS-NEW-02 | "Cross-domain min-tier resolution" | The min-tier rule is structurally sound but creates a preferential attachment dynamic: agents learn to avoid shadow-domain beads, starving those domains of the evidence needed to promote them out of shadow
- P2 | SYS-NEW-03 | "Weight-outcome feedback loop" | The 20% degradation threshold and the intercept calibration loop are applied to a moving baseline — if Ockham's own weight changes shift the baseline, the threshold is chasing a signal it partially caused
- P3 | SYS-NEW-04 | "Autonomy ratchet / cross-domain" | The min-tier rule resolves authority at dispatch time; it does not resolve it at claim time — a claimed bead can change effective tier between claim and execution if a domain's status changes mid-sprint

---

## Verdict

**Partially resolved.** Three of four tracked findings are fully addressed; one (SYS-03) is structurally improved but replaced by a new temporal mismatch between the two newly specified feedback loops. The SUBAK-01 section meaningfully closes the most critical systemic gap from rev 2 (enforcement-derived authority). Two new systemic risks are introduced by the same section: a conflation of two distinct feedback loops that operate at different time scales, and an emergent shadow-domain starvation trap from the min-tier rule. These are P1 and P2 respectively — not blocking but warrant explicit resolution before the plan phase.

---

## Tracked Finding Verdicts

### SYS-01: Ratchet Runaway — FIXED with residual

**What the prior review said:** All domains could ratchet to autonomous with no mechanism to return them absent a failure. Required a 30-day re-confirmation balancing loop.

**What rev 3 added (Section 6, "Ratchet runaway prevention"):** "Every 30 days (configurable), autonomous domains are re-evaluated against the promotion guard. If evidence has degraded below threshold, the domain demotes to supervised. This is a balancing loop that prevents the all-autonomous steady state."

**Verdict: Fixed.** The balancing loop is now explicit and correctly identified as such.

**Residual risk (P1):** The 30-day window is per-domain but there is no staggering specification. If Ockham is activated and all domains enter shadow simultaneously (typical cold-start), they will be promoted in waves, and their 30-day re-confirmation windows will be synchronized. At T=30 days, all autonomous domains are re-evaluated simultaneously. If the factory has been under unusual load (e.g., a large feature sprint), evidence across multiple domains may degrade together. This produces a synchronized multi-domain demotion cascade — the same anti-pattern the multi-window confirmation was designed to prevent at the Tier 2 level. The balancing loop is present but may itself oscillate at system scale. Recommendation: stagger re-confirmation windows by adding a domain-specific offset derived from the domain's promotion timestamp, so no two domains re-confirm within the same 48-hour window.

---

### SYS-02: Theme Freeze Orphans In-Flight Work — FIXED with residual

**What the prior review said:** Freezing a theme should not terminate in-flight beads; required a supervised-continuation path to prevent freeze→failure→more-pain reinforcing loop.

**What rev 3 added (Section 5, "Tier 2 — CONSTRAIN"):** "In-flight beads: agents mid-sprint in a frozen theme continue at supervised autonomy (complete current work, but no new claims). This prevents the freeze→failure→more-pain reinforcing loop (SYS-02)."

**Verdict: Fixed.** The supervised-continuation path is now specified and the original feedback loop is explicitly broken.

**Residual risk (P1):** The supervised-continuation path prevents abrupt termination but creates a deferred-failure accumulation pattern. Agents completing beads under supervised autonomy in a frozen theme are operating in a degraded state — they lack the authority they had when the bead was claimed. If the bead requires autonomous-tier actions partway through, the agent must either fail the gate or escalate. Each escalation is a signal that can re-trigger CONSTRAIN. The freeze was triggered by 3+ quarantines in the domain; supervised in-flight work may produce additional gate failures that extend the freeze rather than allowing it to decay. The de-escalation window (Section 5, "De-escalation (C-03)") requires both windows to drop below threshold simultaneously, but supervised in-flight agents are still generating events that may count toward the threshold. The residual question is: do in-flight supervised-completion events count toward the Tier 2 re-trigger threshold? This is unspecified and the answer determines whether the freeze is self-reinforcing or self-resolving during drain.

---

### SYS-03: Three-Speed Oscillation — PARTIALLY FIXED

**What the prior review said:** The 1-hour Tier 2 confirmation window, the 24-hour long window, and the 30-day re-confirmation window (once added) would create three nested feedback loops at different time scales, with the risk of oscillation when the loops interact.

**What rev 3 added:** The three-tier mechanism was already present; rev 3 added the 30-day re-confirmation (SYS-01 fix) and the 7-day weight-drift rolling window (SUBAK-01). The document also added the stability window for de-escalation (C-03): "a stability window equal to the short window (default 1h) must pass with no re-fire."

**Verdict: Partially fixed.** The tier mechanism is better specified. However, rev 3 introduces two new time-scale signals (7-day weight-drift from SUBAK-01, 30-day re-confirmation from SYS-01) that now interact with the existing 1h/24h Tier 2 windows. The temporal structure is now: 1h (Tier 2 short window), 24h (Tier 2 long window), 7-day (SUBAK-01 weight-drift), 14-day (pleasure signal rolling window), 30-day (re-confirmation). That is five nested temporal loops. The oscillation risk is not reduced — it is extended to five frequencies.

**What this means structurally:** A domain can receive a SUBAK-01 INFORM signal (7-day weight-drift degradation) that adjusts its dispatch weight downward, while simultaneously receiving a 30-day re-confirmation demotion from supervised to shadow, while its Tier 2 CONSTRAIN is still in the stability window. These three signals are additive in their downward effect and have no coordination mechanism. The result is over-correction: the domain is weight-suppressed, demoted, and frozen simultaneously for conditions that may share a common cause. See Finding SYS-NEW-01 below for the full analysis of the conflicting loop interaction.

---

### SYS-07: Pleasure Signals Deferred — FIXED

**What the prior review said:** Pleasure signals were deferred to Wave 3, creating a system that could only detect failure, not improvement, for the first two waves.

**What rev 3 added (Section 6, "Pleasure signals"):** "Ship alongside Wave 1 Tier 1 INFORM, not deferred to Wave 3." Three signals specified: `first_attempt_pass_rate`, `cycle_time_p50_trend`, `cost_per_landed_change_trend`.

**Verdict: Fixed.** The three signals are concrete and Wave 1-tied.

---

## New Findings

### SYS-NEW-01: Two Feedback Loops with Conflicting Correction Signals [P1]

**Section:** "Weight-outcome feedback loop (SUBAK-01)" and "Autonomy ratchet: explicit state machine (revised)" — Section 10 and Section 6.

**Lens:** Compounding Loops, Pace Layers, Causal Graph.

**What the document says:** SUBAK-01 monitors theme-level weight-outcome correlation. If a theme's actual-vs-predicted performance degrades >20% over 7 days, Ockham emits a Tier 1 INFORM signal and adjusts weights. Separately, the autonomy ratchet monitors agent-level hit rates over sessions/windows and promotes or demotes agents per domain.

**The structural problem:** These are two independent feedback loops measuring related but distinct things, with no specified interaction rule:

- Loop A (SUBAK-01): theme performance degrades → weight adjusted downward → fewer beads dispatched to that theme → theme gets less data → baseline estimate degrades further on thin data. This is a potential reinforcing loop if the weight reduction reduces throughput enough to make the 7-day window statistically noisy.

- Loop B (ratchet): agent hit rate in domain falls below threshold → domain demotes → fewer beads claimed in that domain → less evidence → domain stays in lower tier longer. This is the same structural shape as Loop A but operating at a different scope (agent×domain vs. theme aggregate) and time scale (session count vs. 7-day rolling window).

**The conflict:** When both loops fire simultaneously in the same domain, their corrections compound. A domain whose theme is weight-suppressed by Loop A will also have reduced evidence for Loop B's promotion guard, because fewer beads are dispatched to it. The domain becomes self-reinforcing in its degradation: SUBAK-01 suppresses dispatch, which thins evidence, which delays ratchet promotion, which keeps the domain in supervised (lower autonomy → lower throughput) → which degrades theme performance metrics further → which triggers SUBAK-01 again. This is a reinforcing loop that the document does not identify or bound.

**The deeper issue:** The document does not specify whether SUBAK-01's weight-drift signal is domain-scoped or theme-scoped. The SUBAK-01 section says "grouped by theme" — but themes map to lanes, and a domain is a path prefix (e.g., `core/**`). A theme can span multiple domains; a domain can contain beads from multiple themes. If a domain is performing poorly but only one of its themes is weight-drifting, SUBAK-01 fires for the theme while Loop B fires for the domain. The same agents receive two conflicting correction signals that they cannot reconcile.

**Recommendation:** Specify the interaction rule explicitly. Options: (a) SUBAK-01 is evidence-of-policy-error, not evidence-of-agent-failure — the two loops should not compound; SUBAK-01 INFORM should trigger policy review (intent.yaml reconsideration) rather than weight suppression when the ratchet is simultaneously in demotion territory; (b) define a minimum dispatch floor below which SUBAK-01 weight suppression cannot go, to prevent evidence starvation; (c) require SUBAK-01 to be computed on a denominator normalized by dispatch volume (to avoid thin-data false positives).

---

### SYS-NEW-02: Min-Tier Rule Creates Shadow-Domain Starvation Trap [P1]

**Section:** "Cross-domain beads (ET-01/HADZA-01)" in Section 6, "Autonomy ratchet: explicit state machine (revised)."

**Lens:** Preferential Attachment, Hysteresis, Schelling Trap.

**What the document says:** "When a bead touches multiple domains (e.g., `interverse/**` + `core/**`), authority resolves to `min(tier_per_domain)` — the most restrictive domain governs. If any touched domain is frozen (CONSTRAIN), the bead is ineligible for dispatch regardless of other domains' status."

**The structural problem:** The min-tier rule correctly prevents authority escalation via cross-domain beads. But it creates a second-order effect that the document does not address: agents and principals — both rationally — will prefer to avoid beads that touch shadow domains, because those beads are executed under shadow rules (maximum oversight, slowest). Over time this produces a Schelling trap:

1. Domain D is in shadow (e.g., `core/intermute/**` is new, no evidence).
2. Beads touching D are executed under shadow rules.
3. Work touching D is slower and more expensive.
4. Principals implicitly deprioritize beads that touch D to reduce oversight burden.
5. D receives fewer dispatches.
6. D accumulates less evidence.
7. D cannot promote out of shadow because promotion requires `sessions >= 10` and evidence is below threshold.
8. Return to step 3.

This is hysteresis in its clearest form: a domain enters shadow because it lacks evidence (cold-start or CONSTRAIN), and the min-tier rule makes it hard to accumulate the evidence needed to exit shadow. The domain is path-dependent: entering shadow is easy; exiting is expensive. The document specifies the mechanics of promotion but does not specify a mechanism to ensure shadow domains receive sufficient dispatch to generate promotion evidence.

**The Schelling quality:** Each individual decision to avoid shadow-domain beads is locally rational (less overhead, faster execution), and collectively catastrophic (entire domains never graduate). The document does not identify this as a risk or propose a counter-mechanism.

**Recommendation:** Add a shadow-domain bootstrapping mechanism — a minimum dispatch cadence for shadow domains analogous to the starvation floor discussed for low-budget themes (F3 in the synthesis). Options: (a) reserve a fixed fraction of dispatch capacity (e.g., 5%) for shadow-domain beads regardless of weight, so evidence accrues; (b) when a domain has fewer than 10 sessions in a 30-day window, flag it as evidence-starved and apply a positive dispatch boost to surface it; (c) allow principals to explicitly "accelerate" a domain with a `--bootstrap` flag that bypasses min-tier for a bounded set of beads under explicit principal supervision. Without some form of this, the min-tier rule has the unintended consequence of making new and recently-frozen domains nearly impossible to recover.

---

### SYS-NEW-03: SUBAK-01 Baseline is Ockham-Contaminated [P2]

**Section:** "Weight-outcome feedback loop (SUBAK-01)" — Section 10.

**Lens:** Causal Graph, Bullwhip Effect.

**What the document says:** "After each bead completion, compare actual cycle time and quality gate pass rate against the predicted baseline for that theme. If a theme's actual-vs-predicted ratio degrades >20% over a 7-day rolling window, Ockham emits a Tier 1 INFORM signal."

**The structural problem:** The "predicted baseline" for a theme is derived from historical performance. But Ockham's own weight decisions actively shape which beads get dispatched to the theme, and therefore shape what the historical performance baseline looks like. This is measurement endogeneity: the governor's policy choices determine the data it uses to evaluate its own policy.

Concrete scenario: Ockham boosts Theme A (auth, +12 offset). Higher-priority beads in auth are dispatched preferentially. These beads tend to be more complex (high-priority work is often high-complexity work). Cycle time increases. The 7-day baseline shifts upward. The 20% degradation threshold is now relative to a higher baseline. A later reduction in Ockham's auth boost causes cycle time to fall, which appears as a >20% improvement — but is actually a reversion to mean after the policy-induced distortion. SUBAK-01 fires an INFORM signal for a condition Ockham itself created.

The intercept calibration loop (mentioned in SUBAK-01) will learn from 50+ evaluations, but if the training data is systematically biased by Ockham's own dispatch decisions, the learned threshold will encode the contamination rather than correct it.

**Recommendation:** The SUBAK-01 baseline should control for dispatch priority composition. Specifically: when comparing actual-vs-predicted, normalize cycle time by the complexity distribution of dispatched beads (beads priority distribution, bead size estimate). Without this control, SUBAK-01 cannot distinguish "this theme's performance degraded because Ockham changed what it dispatches" from "this theme's performance degraded because the agents working it are less effective." The intercept calibration should be trained on residuals after controlling for dispatch composition, not on raw cycle-time deltas.

---

### SYS-NEW-04: Min-Tier Computed at Dispatch; Not Locked at Claim [P3]

**Section:** "Cross-domain beads (ET-01/HADZA-01)" in Section 6.

**Lens:** Causal Graph, Hysteresis.

**What the document says:** "Ockham computes this [min-tier resolution] during weight synthesis; lib-dispatch.sh receives the final weight without needing to understand domain resolution."

**The structural problem:** The min-tier is computed when the bead enters the dispatch queue (weight synthesis). But the brainstorm does not specify whether the resolved tier is locked at claim time or re-evaluated continuously during execution. This matters because:

- A bead is dispatched under autonomous rules (all touched domains are at autonomous tier at dispatch time).
- Mid-sprint, a different bead in a shared domain triggers CONSTRAIN — that domain demotes to supervised.
- The original bead's effective tier has changed from autonomous to supervised (because min-tier is now lower) but the bead is already in execution.
- The agent continues under the assumption of autonomous authority, but the domain's actual tier is supervised.

The document specifies CONSTRAIN behavior for new dispatches (bead ineligible) and for in-flight beads (continue at supervised autonomy, per SYS-02 fix). But the SYS-02 fix applies to theme freezes, not to cross-domain mid-sprint tier changes. The min-tier rule creates a new class of mid-sprint state invalidation that the CONSTRAIN in-flight policy does not directly address.

**The severity is P3** because this is a gap in specification rather than a structural failure mode — in practice, the action-time validation invariant (Safety Invariant 3) will catch authority overreach at execution time. But it means a bead can be dispatched under one tier assumption and execute under a different effective tier, which the audit trail will reflect inconsistently. The gap should be resolved by specifying: "the effective tier for a bead is computed at dispatch and re-evaluated at each authority-gated action during execution."

---

## Summary Table

| ID | Status | Section | Severity | Lens | Action |
|----|--------|---------|----------|------|--------|
| SYS-01 | Fixed (residual) | §6 Ratchet runaway | P1 | Bullwhip, Pace Layers | Stagger 30-day windows by promotion timestamp |
| SYS-02 | Fixed (residual) | §5 Tier 2 CONSTRAIN | P1 | Reinforcing Loop | Clarify whether in-flight events count toward re-trigger threshold |
| SYS-03 | Partially fixed | §5, §6, §10 | P1 | Pace Layers, Three-speed oscillation | See SYS-NEW-01 for the replacement concern |
| SYS-07 | Fixed | §6 Pleasure signals | — | — | No action required |
| SYS-NEW-01 | New | §6 + §10 | P1 | Compounding Loops, Pace Layers | Specify interaction rule between SUBAK-01 and ratchet; add dispatch floor |
| SYS-NEW-02 | New | §6 Cross-domain | P1 | Preferential Attachment, Hysteresis, Schelling Trap | Add shadow-domain bootstrapping mechanism |
| SYS-NEW-03 | New | §10 SUBAK-01 | P2 | Causal Graph, Bullwhip | Normalize baseline by dispatch priority composition |
| SYS-NEW-04 | New | §6 Cross-domain | P3 | Causal Graph, Hysteresis | Specify tier locking at claim vs. re-evaluation at each action |

**Net change:** 4 tracked findings → 3 fixed, 1 partially fixed. 4 new findings introduced by rev 3 changes. The document is materially better on the original gaps; the new sections introduce new systemic risks at a lower severity level than the originals. No P0 findings from this review — the most critical prior issues (bypass channel independence CCF-01, promotion gaming F2, joint feasibility F3) remain the domain of other agents and are not regressed here.
