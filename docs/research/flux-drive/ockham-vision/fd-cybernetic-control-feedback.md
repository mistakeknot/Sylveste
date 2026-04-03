### Findings Index
- P0 | CCF-01 | "Algedonic signals: tiered passive/active with bypass" | Tier 3 bypass routes through file-system state, not an independent channel -- Clavain must read it
- P1 | CCF-02 | "Autonomy ratchet with per-domain state" | Promotion feedback loop is open -- no calibration of threshold correctness after promotion decisions
- P1 | CCF-03 | "Algedonic signals" | Tier 1 INFORM adjustments are reactive, not homeostatic -- no setpoint, no equilibrium model
- P2 | CCF-04 | "Four subsystems" | Requisite variety mismatch -- 3 tiers collapse 5+ distinct failure categories into a single escalation ladder
- P3 | CCF-05 | "Key Decisions" | VSM System 4 (intelligence/environment scanning) is absent from the architecture

Verdict: needs-changes

### Summary

The brainstorm explicitly invokes Stafford Beer's VSM and names Ockham as the Cyberstride. Evaluated against Beer's structural requirements, the architecture satisfies System 3 (operational management via dispatch weights) and System 5 (policy via principal intent), but has structural gaps in System 4 (environment scanning), algedonic channel independence, and feedback loop closure. The most significant finding is that the Tier 3 "bypass" writes `factory-paused.json` to `~/.clavain/` -- a file that Clavain reads. This is not a bypass of the management hierarchy; it is a message routed through the management hierarchy's own file system. In Beer's design, the algedonic channel must be physically independent of the management channel it bypasses.

### Issues Found

1. **P0 | CCF-01 | Algedonic bypass is not structurally independent of the hierarchy it bypasses**

   Section "Algedonic signals" (lines 61-63) defines Tier 3 as "Write factory-paused.json + direct notification bypassing Clavain." But Section "What already works" (line 87) shows the implementation: `~/.clavain/factory-paused.json -> Tier 3 halt`. This file lives inside Clavain's own configuration directory. Clavain reads it to decide whether to halt.

   In Beer's VSM, the algedonic channel exists precisely because the management channel (Systems 3-4) can be saturated, delayed, or corrupted. If the alarm signal must traverse the same system it is alarming about, the alarm is useless when that system is the one failing. Concretely: if Clavain's hook execution is hung (e.g., dolt server crash, tmux session zombie), it will never read `factory-paused.json`, and the "bypass" never reaches the principal.

   **Failure scenario:** A cascading failure causes Clavain's SessionStart hook to hang (documented in beads-troubleshooting.md as a known failure mode). Ockham writes `factory-paused.json`. No Clavain session reads it because no sessions start. The principal is never notified. The factory appears silent rather than halted.

   **Fix:** Tier 3 must have at least one notification path that does not depend on Clavain reading a file. Options: (a) Ockham writes directly to a notification channel the principal monitors (email, Slack webhook, push notification), (b) a watchdog process independent of Clavain polls `factory-paused.json` and escalates, (c) Meadowsyn polls factory state independently. The brainstorm mentions "direct notification bypassing Clavain" but does not specify the mechanism -- this must be made concrete.

2. **P1 | CCF-02 | Promotion feedback loop is open -- OODARC predict-calibrate cycle missing**

   Section "Autonomy ratchet" (lines 67-73) defines promotion thresholds: `first_attempt_pass_rate > threshold`, `cycle_time_trend improving`. These thresholds "start hardcoded, wire through intercept for calibration." But the brainstorm does not describe what happens after a promotion:
   - Is the post-promotion hit rate tracked and compared to the pre-promotion prediction?
   - If an agent is promoted to autonomous and its hit rate subsequently drops (but not below the demotion threshold), is this signal fed back to adjust the promotion threshold?
   - Is there any mechanism to detect that the promotion threshold is set too low (promoting agents who then regress)?

   This is a classic open-loop controller: a decision is made (promote), but the outcome of that decision is never used to calibrate the decision-making process itself. In Ashby's terms, the controller lacks second-order feedback.

   **Fix:** Add a "promotion audit" mechanism: after N beads at the new tier, compare actual performance to the predicted performance that justified promotion. If actual < predicted by more than a confidence band, both (a) demote the agent and (b) tighten the promotion threshold for that domain by a calibration factor. This closes the loop.

3. **P1 | CCF-03 | Tier 1 weight adjustments lack homeostatic structure**

   Section "Tier 1 -- INFORM" (line 59) says "Signal fires, dispatch weights adjust. Recovery is automatic when signal clears." This describes a reactive system (deviation triggers response) but not a homeostatic one. A homeostatic regulator requires:
   - A setpoint (target state)
   - A sensor (current state)
   - An error signal (setpoint - current)
   - A corrective action proportional to the error

   The brainstorm defines the sensor (interspect evidence) and the corrective action (weight adjustment) but not the setpoint. What is the "normal" state that Tier 1 is trying to restore? Is it "each theme receives dispatches proportional to its budget"? Is it "cycle time remains below a threshold"? Without a defined setpoint, Tier 1 adjustments are ad-hoc reactions, not regulation. The system cannot distinguish between "returning to equilibrium" and "oscillating around an undefined center."

   **Fix:** Define explicit setpoints for each Tier 1 signal. For theme drift: setpoint = budget allocation percentages in intent.yaml. For cycle time: setpoint = trailing 7-day average. For cost overrun: setpoint = per-bead budget from costs.yaml. The Tier 1 weight adjustment should be proportional to the error (deviation from setpoint), with a damping factor to prevent oscillation.

4. **P2 | CCF-04 | Requisite variety: 3 tiers for 5+ failure categories**

   Ashby's Law of Requisite Variety states that a controller must have at least as many response states as the system has disturbance states. The brainstorm identifies at least 5 distinct categories of disturbance in the Tier 2 examples alone: quarantine patterns, circuit breaker trips, gate failures, stale claims, and lane starvation. Each of these has different root causes, different recovery procedures, and different stakeholders. Yet all are collapsed into a single response: "freeze domain, set autonomy_tier=shadow, emit to Meadowsyn."

   **Consequence:** A stale claim (benign, often self-resolving) triggers the same response as 3 quarantines in the same domain (serious competence signal). The principal sees "Tier 2 CONSTRAIN" for both and cannot triage without investigating each one manually. Over time this trains the principal to ignore Tier 2 signals (alert fatigue at the human level).

   **Fix:** Sub-tier Tier 2 into at least two categories: CONSTRAIN-CAPABILITY (competence signals -- quarantine, gate failure) and CONSTRAIN-INFRASTRUCTURE (operational signals -- circuit breaker, stale claim). These can share the freeze mechanism but should present differently to the principal and have different recovery criteria.

5. **P3 | CCF-05 | VSM System 4 (intelligence function) is absent**

   Beer's VSM has five systems. The brainstorm maps Ockham to System 3 (operational management) and the principal to System 5 (policy). System 1 (operations) is Clavain/Zaka/Alwe. System 2 (coordination) is dispatch scoring. But System 4 -- the intelligence function that scans the environment and feeds strategic information to System 5 -- has no counterpart.

   In the AI factory context, System 4 would be: what new patterns are emerging in the codebase? What external changes (dependency updates, API deprecations, security advisories) should influence strategic intent? Currently the principal must discover these independently and update intent.yaml manually.

   **Improvement:** Not needed for Wave 1, but the vision should acknowledge the System 4 gap and name it as a future subsystem. The interject plugin's discovery scanning is a natural candidate -- noting this connection would make the VSM mapping explicit.

### Improvements

1. Formalize the OODARC loop for each subsystem by adding a "Feedback Closure" column to the four-subsystem table (Section 1, line 40). For each subsystem, specify: what is observed, what decision is made, what outcome is tracked, and how the outcome feeds back into decision calibration.

2. Add a "Setpoints" section to the Tier 1 specification. Each INFORM signal should have a named setpoint, a measurement, and a proportional response function. This transforms Tier 1 from reactive ("something changed, adjust weights") to genuinely homeostatic ("theme drift is 12% above setpoint, reduce weight by 0.12 * damping_factor").

3. Rename the architecture diagram in AGENTS.md to explicitly label which VSM system each component maps to. This makes the cybernetic model auditable and reveals gaps (like System 4) visually rather than requiring analysis.
