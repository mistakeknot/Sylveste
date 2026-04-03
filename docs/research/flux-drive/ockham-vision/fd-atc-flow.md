---
artifact_type: flux-drive-review
agent: fd-atc-flow
track: B-orthogonal
target: docs/brainstorms/2026-04-03-ockham-vision-brainstorm.md
reviewed_at: 2026-04-03
---

# fd-atc-flow Review — Ockham Vision

### Findings Index
- P1 | ATC-1 | "Key Decisions §3 — Algedonic signals §Tier 2 + §5 Safety invariants" | Cross-domain bead execution with no authority handoff protocol — claimed-but-blocked limbo is unresolved
- P1 | ATC-2 | "Key Decisions §3 — Algedonic signals §Tier 1→2 escalation" | INFORM-to-CONSTRAIN escalation lacks a rate-of-change signal — accelerating degradation escalates at the same speed as slow drift
- P2 | ATC-3 | "Key Decisions §3 — Tier 3 BYPASS" | No intermediate degraded mode between full autonomous operation and factory pause — no non-radar-equivalent
- P2 | ATC-4 | "Key Decisions §3 — Tier 2 CONSTRAIN" | CONSTRAIN tier has no tactical deviation path for agents whose local execution makes the freeze harmful
- P3 | ATC-5 | "Key Decisions §4 + §5 §4 Audit completeness" | Retrospective review path for anomaly threshold improvement is not described — audit trail supports compliance but not policy refinement

Verdict: needs-changes

### Summary

The Ockham vision's authority tier model is structurally sound for single-domain execution, but ATC-style cross-domain handoff is absent. When a bead executing in `interverse/**` (where the agent is autonomous) touches `core/**` (where the agent is shadow), the action-time check fires and blocks the action — but the bead remains claimed, creating a stale-claim condition with no described resolution path. This is the ATC coordination-fix handoff problem: the aircraft is in the air but no sector has accepted it. The INFORM-to-CONSTRAIN escalation path also lacks a rate-of-change component, meaning a domain degrading quickly passes through the same 1-hour short confirmation window as a domain drifting slowly — the factory cannot distinguish an emerging crisis from a chronic low-grade problem. The absence of an intermediate degraded mode (analogous to non-radar procedural control) is a structural gap: Tier 3 BYPASS goes directly from normal operation to factory pause, with no mode that continues operation at reduced throughput under heightened principal review.

### Issues Found

1. **P1 — ATC-1: Cross-domain bead execution produces claimed-but-blocked limbo**

   Safety invariant 3 states: "Authority is checked at execution time, not just claim time" (§Key Decisions §5). This is correct. The failure is in what happens next. When an agent claims a bead in `interverse/**` (autonomous tier) and execution triggers a file write to `core/intercore/` (shadow tier), the action-time check fires and blocks the write. The brainstorm describes this as the intended behavior. What is not described is the resolution path for the bead: it remains in a claimed state, the agent cannot complete it, and Clavain's `dispatch_rescore()` does not know to reclaim it.

   Failure scenario: An agent autonomously claims a refactor bead tagged `interverse/**`. Mid-execution it touches `core/intercore/config/costs.yaml`. The action-time authority check blocks the write. The agent reports partial completion. The bead is now claimed, partially executed, in a state that requires `core/**` authority to resolve. No Clavain dispatch logic reclaims it because stale-claim detection fires on timeout, not on authority violation. Until the timeout elapses — or until a principal manually intervenes — the bead occupies a queue slot and the agent that holds the claim cannot productively work. In ATC terms: the aircraft is on a heading that crosses the adjacent sector's boundary, the handoff was never accepted, and the controller still shows it as their responsibility.

   Smallest fix: When the action-time authority check fires a violation, write a `claimed_by_blocked` state to the bead alongside the blocking reason (`insufficient_authority: core/**`). Add a `dispatch_rescore()` check for this state flag: beads in `claimed_by_blocked` are reclaimed and re-queued with authority context (`required_domains: [core/**]`) so Clavain can route them to an agent with appropriate grants. This is one state flag and one rescore branch.

2. **P1 — ATC-2: INFORM-to-CONSTRAIN escalation has no rate-of-change signal**

   The brainstorm specifies multi-window confirmation: "short 1h AND long 24h" for CONSTRAIN promotion (§Key Decisions §3). This is an absolute-value threshold. ATC issues miles-in-trail restrictions when a sector *approaches* saturation — before it saturates — based on traffic flow rate, not only on current occupancy. The INFORM tier is described as firing on "theme drift, cycle time degradation, cost overrun" (§Key Decisions §3 §Tier 1). But INFORM-to-CONSTRAIN transition is gated on the anomaly persisting past the confirmation windows.

   Failure scenario: A domain begins degrading at 2x the normal rate (three circuit breaker trips in 30 minutes vs. three over 6 hours). Both scenarios require the anomaly to persist past a 1-hour short window before CONSTRAIN fires. The rapidly-degrading domain spends one hour in INFORM state while the factory routes work into it at full weight. A rate-of-change signal — `d(anomaly_signal)/dt > k` — would escalate the rapidly-degrading case ahead of the window without changing the slow-drift case.

   Smallest fix: Add a rate-of-change condition as an OR branch on the CONSTRAIN promotion gate: `(anomaly_persists_past_short_window) OR (anomaly_rate_of_change > rapid_degradation_threshold)`. This preserves the existing slow-drift behavior while allowing fast escalation for acute events. One additional predicate in the anomaly subsystem's escalation logic.

3. **P2 — ATC-3: No intermediate degraded operating mode between autonomous and paused**

   ATC degrades gracefully: radar fails → non-radar separation standards → procedural control → restricted operations. The factory never goes directly from normal ops to full halt; each degraded mode is slower but still safe. The Ockham brainstorm defines Tier 3 BYPASS as writing `factory-paused.json` — a binary transition from operation to halt (§Key Decisions §3 §Tier 3, §Key Decisions §6).

   Does a mode exist between full autonomous operation and factory pause? The brainstorm describes the autonomy ratchet modes (shadow/supervised/autonomous) as per-domain states but not as a factory-wide degraded operating mode. There is no described "supervised dispatch" mode where the factory continues operating but the principal must approve each dispatch decision before it executes — the ATC equivalent of procedural control. Tier 3 currently jumps from "anomaly detected" directly to "factory stopped." For anomaly situations where the factory can still operate safely at reduced throughput under increased oversight, this is an overcorrection that stops productive work unnecessarily.

4. **P2 — ATC-4: CONSTRAIN tier freeze has no tactical deviation path**

   ATC issues Expected Departure Clearance Times (EDCTs) as mandatory constraints, but controllers can issue a tactical deviation when honoring the constraint would create a safety problem in the local traffic picture. The deviation is logged. The Ockham brainstorm specifies that Tier 2 CONSTRAIN freezes a domain and sets `autonomy_tier=shadow` (§Key Decisions §3 §Tier 2). There is no described path for an agent executing against a legitimate local constraint to request a time-limited deviation from the freeze with full audit logging.

   This matters because a CONSTRAIN freeze on `core/**` does not distinguish between "stop speculative new work in core" and "stop the in-progress security patch that is 90% complete and will leave the system in an inconsistent state if interrupted." The freeze applies uniformly. The agent completing the security patch has no audited mechanism to request completion rights. They either violate the freeze (invisible to audit) or abandon mid-task (leaving the system inconsistent).

   Does the CONSTRAIN tier include a `freeze_deviation_request` path that logs the request, requires principal acknowledgment, and grants a time-bounded completion window? If not, this is a gap.

5. **P3 — ATC-5: Audit trail supports compliance verification but not threshold calibration**

   Safety invariant 4 states: "every authority decision produces a durable receipt in interspect" (§Key Decisions §5). This supports compliance review: "did this grant happen, was it authorized?" ATC's post-coordination review goes further: non-standard coordinations are analyzed to improve procedures. The brainstorm does not describe a path from accumulated audit receipts to anomaly threshold recalibration.

   Is there a described mechanism for analyzing the interspect audit trail to answer: "The 1h short window fires too early for drift anomalies in core/**, causing unnecessary CONSTRAIN cycles" or "The rapid-escalation threshold should be domain-specific because interverse/** has higher natural variance than core/**"? Without this path, thresholds remain hardcoded and drift away from calibration as factory operating patterns evolve.

### Improvements

1. Add a `claimed_by_blocked` state to the bead state schema alongside a `blocked_reason` and `required_domains` field. Wire `dispatch_rescore()` to treat this state as a reclaim trigger — returning the bead to the queue with routing context attached. This is the minimum viable authority-violation reclaim path.

2. Add a `d(anomaly_rate)/dt` input to the Anomaly subsystem's CONSTRAIN escalation gate, alongside the existing multi-window absolute-value confirmation. Gate the rate-of-change branch on a configurable `rapid_degradation_threshold` that starts conservative and can be calibrated via intercept.

3. Define a factory-wide `supervised_dispatch` operating mode that sits between normal operation and `factory-paused.json`. In this mode, Clavain continues scoring and queuing dispatch decisions but writes proposals to a `dispatch-pending/` directory for principal acknowledgment before execution. The Tier 3 trigger condition should evaluate whether `supervised_dispatch` is sufficient before escalating to full halt.

4. Add a `freeze_deviation_request` mechanism to Tier 2 CONSTRAIN: an agent can write a `{bead_id, reason, completion_estimate}` record to a `freeze-deviations/` directory. Ockham surfaces this to the principal via Meadowsyn. Principal acknowledgment writes a time-bounded grant to interspect. This satisfies both audit completeness and the legitimate completion case.

5. Add an `anomaly-threshold-review` report to the Anomaly subsystem's outputs — a periodic summary of INFORM/CONSTRAIN/BYPASS events by domain, including false-positive rate (CONSTRAIN fires that clear within the long window without requiring recovery). Feed this into the intercept calibration path alongside authority promotion decisions.
