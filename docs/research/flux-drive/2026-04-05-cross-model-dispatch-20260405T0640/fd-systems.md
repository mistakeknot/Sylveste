---
artifact_type: review
reviewer: fd-systems
document: /tmp/flux-drive-cross-model-dispatch-1775371273.md
bead: sylveste-9lp.9
date: 2026-04-05
---

# Systems Thinking Review: Cross-Model Dispatch Implementation Plan

### Findings Index

- P2 | SYS-01 | "Task 1.5 / Task 3.1 Step 3" | Budget Pressure Feedback Loop Has Oscillation Risk at Boundary Conditions
- P1 | SYS-02 | "Task 3.1 Steps 1–6 (interaction of all constraints)" | Constraint Stack Produces Emergent Lock States Not Analyzed as a System
- P2 | SYS-03 | "Task 3.1 Step 4 (downgrade cap)" | Downgrade Cap Breaks Causal Symmetry and Introduces Hysteresis
- P1 | SYS-04 | "Task 1.2 / Task 3.1 Step 7 (shadow→enforce transition)" | Mode Transition Has No Ramp Path — Hysteresis Risk on Activation
- P2 | SYS-05 | "Task 3.1 Steps 5–6 (upgrade pass + pool-level assertion)" | Savings Recycling and Pool Assertion Can Counteract Budget Pressure in Opposing Directions
- P3 | SYS-06 | "Task 4.2–4.3 (calibration emit / escalation advisory)" | Calibration Loop Is Write-Only — No Feedback Path Back to Dispatch Logic
- P2 | SYS-07 | "Task 1.5 / agent-roles.yaml" | Domain Complexity Classification Is Static in a Domain-Dependent System

**Verdict: needs-changes**

---

## Summary

The cross-model dispatch plan is technically well-structured: the constraint pipeline is clearly ordered, the cache-based approach for field lookup avoids subprocess overhead, and the shadow/enforce gate is a sound pattern. The systems-level gaps are concentrated in three areas. First, the feedback loop between budget pressure computation and tier adjustment is iterated (two passes are allowed) but the conditions under which two passes diverge from one pass are not analyzed — at boundary conditions near a threshold, the system can enter a pressure-reclassifies-itself cycle that the two-pass cap resolves arbitrarily rather than convergently. Second, the interaction of all five constraint layers (score, budget, constitutional floor, tier cap from domain intersection, safety floor) produces a constraint space that includes emergent lock states the plan does not enumerate: certain combinations where every constraint pulls in a different direction produce a deterministic output that may be systematically wrong for a class of agents. Third, the shadow→enforce transition has no ramp mechanism, which means the first enforcement run sees a system with zero calibration data — the transition point is the moment of maximum information poverty but also maximum impact.

---

## Issues Found

**1. P2 — SYS-01 — Budget Pressure Feedback Loop Has Oscillation Risk at Boundary Conditions**

Section: Task 1.5 / Task 3.1 Step 3 (pressure recomputation pass)

The plan computes initial pressure from original models, runs tentative adjustments, recomputes pressure from adjusted costs, and if the pressure label changes runs a second pass. The two-pass cap is presented as oscillation prevention, but it resolves ambiguity by truncation rather than by convergence. The Bullwhip lens applies here: pressure is a derived signal computed from a pool of agents whose models are themselves being adjusted in response to that pressure. At the boundary between "medium" and "high" pressure thresholds (0.5 ratio), a pool where one sonnet→haiku downgrade flips the ratio from 0.49 to 0.51 will produce different second-pass behavior than a pool where it does not, with no stable fixed point. The cap of two passes means the system halts at whichever state it reaches on pass two regardless of whether that state is coherent.

What is missing from the plan: the equilibrium condition is never stated. Under what conditions does pressure after adjustment converge to the same label as pressure before adjustment? The plan implicitly assumes this is common enough that two passes suffices, but for pools where adjusted costs are close to the threshold boundary, the two-pass truncation produces a result that depends on arbitrary evaluation order within the merit-order sort rather than on any principled criterion.

**2. P1 — SYS-02 — Constraint Stack Produces Emergent Lock States Not Analyzed as a System**

Section: Task 3.1 Steps 1–6 (full dispatch pipeline)

The dispatch pipeline applies five constraint layers in sequence: score-based adjustment, budget pressure downgrade, constitutional floor, domain intersection tier cap, and safety floor. Each layer is well-reasoned in isolation. The systems gap is the interaction space. Consider a concrete path: an agent with `score=3`, `max_model=sonnet` (checker role ceiling), `domain_complexity=low`, `budget_pressure=high`, and a safety floor of `sonnet`. Step 1 upgrades haiku→sonnet (score=3, below max_model ceiling). Step 2 downgrades sonnet→haiku (budget pressure high). Step 3 applies constitutional floor — for a checker, there is no min_model, so no correction. Step 4 applies the safety floor — if this checker has a safety floor of sonnet (e.g., from a future change or edge case in the YAML), the model is pushed back to sonnet. The result is a checker running at sonnet under high budget pressure, which is the opposite of what budget pressure is supposed to achieve.

More broadly: the plan never enumerates the constraint interaction matrix. With five binary-directional constraints operating on a three-tier model space, there are constraint combinations where the pipeline output is counterintuitive or contradictory. The safety floor is declared "ALWAYS LAST — non-negotiable" which is correct, but this means the safety floor can silently reverse budget pressure decisions without that reversal being surfaced in the log format. Task 4.1 logs safety floor clamps, but there is no analysis of what the distribution of safety-floor reversals of budget-pressure decisions implies for the coherence of the budget model. If safety floors frequently override budget pressure, the pressure signal is corrupted — the system believes it is saving budget but is not.

**3. P2 — SYS-03 — Downgrade Cap Breaks Causal Symmetry and Introduces Hysteresis**

Section: Task 3.1 Step 4 (downgrade cap)

The downgrade cap (`max_downgrades = floor(len(candidates) / 2)`) restores the "lowest-scored agents to original model" when the cap is exceeded. This introduces a structural asymmetry: upgrades are unbounded (any number of agents can be upgraded in theory, subject only to max_model ceilings), while downgrades are capped at half the pool. The causal chain this breaks: the downgrade cap is motivated by quality preservation, but the agents most likely to trigger the cap are those at the bottom of the merit order — exactly the agents for whom a downgrade has the least quality impact by the plan's own scoring logic. The cap protects the wrong agents by restoring low-scored agents to their original model while high-scored agents (which were processed first in merit order and may already have been downgraded) are not restored.

The hysteresis question: once the system runs under budget pressure with an enforced downgrade cap, the calibration data (Task 4.2) records these agents as "not downgraded" even though budget pressure was high. Future analysis of calibration data will underestimate the correlation between budget pressure and tier adjustment, which degrades the accuracy of any future calibration-based tuning of thresholds. The system's recorded history does not reflect the counterfactual.

**4. P1 — SYS-04 — Shadow→Enforce Transition Has No Ramp Path — Hysteresis Risk on Activation**

Section: Task 1.2 / Task 3.1 Step 7

The plan gates enforcement behind `mode: shadow | enforce` in budget.yaml, changed manually. This is a correct safety primitive. The systems gap is what happens at the transition boundary. Shadow mode runs dispatch logic but uses original models. This means:

- All calibration data accumulated in shadow mode (Task 4.2) records what adjustments *would have* been made, but the findings produced (which feed the escalation advisory in Task 4.3) are from agents running at *original* models, not adjusted models. The calibration dataset is therefore systematically from a different distribution than enforcement will use.
- The `[tier-escalation]` advisory (Task 4.3) fires when "agent was tier-adjusted AND returned P0/P1" — but in shadow mode, the agent was NOT tier-adjusted. The advisory will never fire during shadow mode. The calibration dataset will have zero escalation signals, which means the signal that would justify or delay the shadow→enforce transition is never generated during the period when it is most needed.

This is a Pace Layer mismatch: the shadow phase is designed to build confidence before enforcement, but the evidence needed to build confidence (escalation advisories from downgraded agents producing P0/P1) can only be generated after enforcement. The transition has no ramp — it is a binary state change at the moment of maximum information poverty. The plan should address what evidence threshold justifies the transition and how that evidence can be generated without full enforcement risk.

**5. P2 — SYS-05 — Savings Recycling and Pool Assertion Can Counteract Budget Pressure in Opposing Directions**

Section: Task 3.1 Steps 5–6 (upgrade pass + pool-level assertion)

The upgrade pass (Step 5) recycles token savings from downgrades into a single upgrade for the highest-scored score=2 agent. The pool-level quality assertion (Step 6) independently upgrades the highest-scored planner/reviewer to sonnet if none are at sonnet. Both steps execute after the budget pressure downgrade pass and after the downgrade cap. This means:

Under high budget pressure, the downgrade pass reduces costs. The upgrade pass may then fire (if savings > 10,000 tokens) and upgrade one agent. The pool assertion may independently fire and upgrade a second agent. Net result: high budget pressure produces at most N-2 downgrades but at least 0-2 upgrades, making the actual cost reduction from budget pressure substantially less than the pressure signal implies. The relationship between `pressure_label = "high"` and actual cost reduction is nonlinear and depends on pool composition, savings threshold, and pool assertion conditions simultaneously.

The plan does not state whether Steps 5 and 6 are conditional on pressure label. If both fire unconditionally regardless of pressure, then for a pool under high pressure where pool assertion fires, the system guarantees at least one agent is upgraded, which may negate the entire savings from the downgrade pass for small pools. This is a Cobra Effect risk: the budget pressure response mechanism partially undoes itself through the quality preservation mechanisms.

**6. P3 — SYS-06 — Calibration Loop Is Write-Only — No Feedback Path Back to Dispatch Logic**

Section: Task 4.2–4.3 (calibration emit / escalation advisory)

The calibration emit (Task 4.2) and escalation advisory (Task 4.3) are correctly designed as observability outputs. The systems gap is that both are one-directional: data flows from dispatch decisions into log lines, and there it stops. The plan describes a future use case ("enables future analysis: grep cmd-calibration | jq to build the calibration dataset") but does not specify any feedback path by which calibration findings affect dispatch thresholds, score boundaries, or domain complexity classifications.

This is not a P1 because the plan explicitly defers calibration-driven tuning. The concern is architectural: the plan creates a reinforcing loop structure (more runs → more calibration data → better thresholds) but only implements the first half. The second half (thresholds ← calibration data) is undefined. If the calibration data accumulates but the feedback path is never built, the system over-adapts to its initial thresholds — the static values in agent-roles.yaml become entrenched because the feedback mechanism that would revise them never materializes. This is an Over-Adaptation risk at the system level, not the implementation level.

**7. P2 — SYS-07 — Domain Complexity Classification Is Static in a Domain-Dependent System**

Section: Task 1.1 / Task 1.5 (agent-roles.yaml domain_complexity / score=1 downgrade logic)

The `domain_complexity` field is a static per-role classification (`low`, `medium`, `high`) baked into agent-roles.yaml at authoring time. It serves as a downgrade veto: score=1 agents with `domain_complexity=high` are not downgraded. The systems gap is that domain complexity is used as a proxy for document complexity, but the actual complexity of the input document varies independently of the agent's role complexity. A `fd-correctness` agent (domain_complexity=high) reviewing a 50-line configuration file faces a simpler reasoning task than the same agent reviewing a 2,000-line architectural spec. The static classification means the constitutional floor operates correctly for the hardest case but prevents downgrade even for the easiest case.

More specifically: the score=1 path means "weak evidence this agent is needed." For a high-complexity-domain agent with score=1, the plan keeps the agent at its original tier. But score=1 already implies weak expansion evidence, so this agent is being kept at full tier precisely in the case where its contribution is least justified. The causal logic reverses the reasonable intuition: strong evidence → upgrade, weak evidence → preserve expensive tier because domain is complex. A document-complexity modifier (even a coarse one, like a word count or stage 1 finding density) would break this static coupling, but no such signal is in scope. The plan should at minimum acknowledge this as a known limitation with a forward reference to how it might be addressed.

---

## Improvements

**1. State the pressure equilibrium condition explicitly (addresses SYS-01)**

Before the two-pass cap, add a convergence note: the two-pass cap is justified if and only if pressure after adjustment is typically within the same label bucket as pressure before adjustment. Compute the threshold gap: if a pool's `adjusted_total` is within ±15% of `effective_budget / (1 - threshold)`, the boundary condition is live and the two-pass truncation is non-convergent. In that case, the second pass should use the average of the two pressure labels (rounding toward conservative: medium if boundary between low/medium) rather than the strict second-pass label. This eliminates the order-dependence of the two-pass truncation at boundary conditions.

**2. Enumerate the constraint interaction matrix for the five constraint layers (addresses SYS-02)**

Add a decision table or worked examples covering the interaction of: score (0–3), budget pressure (low/medium/high), constitutional floor (present/absent), domain intersection tier cap (present/absent), and safety floor (present/absent). Specifically identify the paths where safety floor reverses a budget-pressure downgrade, and add a log line distinguishing "safety floor preserved model against budget pressure" from "safety floor applied without conflict." This makes the budget model's actual cost impact auditable rather than assumed.

**3. Invert the downgrade cap protection order (addresses SYS-03)**

The downgrade cap should protect the *highest-scored* agents in the pool (those near the top of merit order), not the lowest. Revise Step 4: when `downgraded_count > max_downgrades`, restore the N excess downgrades starting from the *lowest-scored* agents (bottom of merit order) rather than the "last processed" (which are also lowest-scored but the framing matters for correctness). Then separately consider whether the cap bound of `floor(len / 2)` is the right threshold or whether a pressure-proportional cap (e.g., cap at `floor(len * (1 - pressure_ratio))`) better tracks the intent.

**4. Add a shadow-mode evidence proxy for escalation advisories (addresses SYS-04)**

In shadow mode, the escalation advisory cannot fire because agents run at original models. Add a shadow-mode proxy: after reading each Stage 2 agent's findings, if the agent *would have been downgraded* in enforce mode AND returned P0/P1 findings, log `[shadow][tier-escalation-proxy]` with the same fields. This proxy fires on original-model outputs and provides the signal needed to assess shadow→enforce transition risk, even though it overestimates the risk (original model is more capable than the adjusted model would be). Document the overestimation direction so operators know the proxy is conservative.

**5. Make upgrade pass and pool assertion conditional on pressure label (addresses SYS-05)**

Add explicit conditions: the savings recycling upgrade (Step 5) should not fire when `pressure_label == "high"`. The pool-level quality assertion (Step 6) is a quality invariant, not a budget mechanism, so it may reasonably fire unconditionally — but if it fires under high pressure, it should be logged as an override ("pool assertion overrides high pressure for agent X") so the cost model reflects it. Alternatively, the savings threshold for the upgrade pass (currently 10,000 tokens) should scale with pressure: `threshold = 10000 * (1 + pressure_ratio)` so that high pressure requires proportionally larger savings to justify a recycle upgrade.

**6. Add a forward reference for the calibration feedback path (addresses SYS-06)**

In Task 4.2, add a note naming the future mechanism: "calibration data feeds future threshold revision via [mechanism TBD — likely interspect or a manual review cycle]. Until that path exists, thresholds in agent-roles.yaml and budget.yaml are authoritative." This makes the open loop explicit and prevents the static thresholds from accumulating unexamined authority. A concrete trigger for the first manual review (e.g., "after 50 enforcement runs or 30 days") would close the loop provisionally.

**7. Document domain complexity as a role-level floor, not a document-level signal (addresses SYS-07)**

In the budget.yaml or expansion.md commentary, add a note: "`domain_complexity` reflects the minimum reasoning tier for this agent's domain regardless of document complexity. It prevents downgrade of correctness-domain agents on hard documents but also prevents downgrade on easy documents. Acceptable tradeoff until a document-complexity signal (e.g., stage 1 finding density) is available." This preserves the current implementation while flagging the known over-protection case, and gives future implementers the hook for refinement without implying the current behavior is wrong.

<!-- flux-drive:complete -->
