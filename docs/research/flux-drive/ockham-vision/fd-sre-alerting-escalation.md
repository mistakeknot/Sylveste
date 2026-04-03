### Findings Index
- P0 | SRE-01 | "Algedonic signals" | No signal flood protection -- cascading agent failure produces O(agents * domains) signals with no suppression
- P1 | SRE-02 | "Algedonic signals" | Multi-window 1h short window prevents detection of rapid-onset incidents within the first hour
- P1 | SRE-03 | "Algedonic signals" | Escalation tiers lack defined owners, response SLAs, and runbook references
- P2 | SRE-04 | "Algedonic signals" | Signal taxonomy conflates infra failure and competence failure under the same "pain" category
- P2 | SRE-05 | "Six qualifications" | Root-cause deduplication mechanism is stated but not specified -- no grouping key or suppression algorithm defined

Verdict: needs-changes

### Summary

The algedonic signal design draws from ISA-18.2 alarm management and references six qualification criteria. The tiered structure (INFORM/CONSTRAIN/BYPASS) maps well to ISA-18.2 severity levels, and the multi-window confirmation pattern is sound in principle. However, evaluated against production alerting systems at scale, three significant gaps emerge: (1) no flood protection or signal rate limiting when a shared root cause triggers signals across multiple domains simultaneously, (2) the 1h short confirmation window creates a guaranteed 1-hour blind spot for genuine rapid-onset incidents, and (3) the tier specifications lack the operational metadata that SRE teams need to act on them -- no owners, no SLAs, no runbook links. At a scale of 10+ agents across 5+ domains, a single infrastructure failure (e.g., Dolt server crash) would generate dozens of uncorrelated signals with no mechanism to group them.

### Issues Found

1. **P0 | SRE-01 | No signal flood protection for cascading failures**

   Section "Six qualifications" (line 65) lists "root-cause deduplication" as one of the six signal qualifications, but the brainstorm provides no specification for how it works. The only detail is "root-cause deduplication" as a named concept. There is no grouping key, no suppression window, no parent-child signal relationship.

   **Failure scenario:** The Dolt server that backs beads crashes (a known failure mode, documented in beads-troubleshooting.md). Every agent that attempts `bd` operations in the next dispatch cycle generates a circuit breaker trip. With 10 agents across 5 themes, this produces 10 circuit breaker signals + 5 theme-level stale-claim signals + 1 factory-wide anomaly. All 16 signals fire within seconds. Without flood protection:
   - Tier 1: 16 simultaneous weight adjustments, potentially all reducing weights to floor (1), making the entire factory appear starved
   - Tier 2: Multiple CONSTRAIN signals trip simultaneously, which is the Tier 3 BYPASS trigger -- escalating an infrastructure blip to a factory halt
   - The principal receives a Tier 3 bypass notification for what is actually a recoverable Dolt restart

   In ISA-18.2 terms, this is "alarm flooding" -- the #1 cause of operator error in industrial control systems. ISA-18.2 mandates a maximum alarm rate (typically 6/hour sustained, 10/10-min peak) and requires flood suppression mechanisms.

   **Fix:** Add three mechanisms: (a) **Signal grouping**: signals that fire within a suppression window (e.g., 60s) and share a root cause indicator (e.g., same error class, same infrastructure component) are grouped into a single composite signal. The composite inherits the highest severity of its children. (b) **Rate limiting**: no more than N signals per tier per hour (e.g., 6 Tier 1, 3 Tier 2, 1 Tier 3). Excess signals are queued and delivered in a digest. (c) **Cascade detection**: if >3 signals fire within 60s, suppress individual signals and emit a single "cascade detected" meta-signal at the appropriate tier.

2. **P1 | SRE-02 | 1-hour short window creates guaranteed blind spot for rapid-onset incidents**

   Section "Tier 2 -- CONSTRAIN" (line 61) requires "multi-window confirmation (short 1h AND long 24h)" before escalating. The short window means that a genuine rapid degradation -- agent starts quarantining every bead in a domain, 5 failures in 30 minutes -- cannot trigger Tier 2 for at least 1 hour.

   **Failure scenario:** An agent starts producing consistently bad code in `core/*` due to a prompt regression. It fails 6 beads in 40 minutes. At minute 41, the signal has been active for only 41 minutes -- below the 1h short window. The agent continues claiming and failing beads for 19 more minutes. By the time the 1h window is satisfied, 8-10 beads have been quarantined, all requiring manual review.

   In SRE practice, this is why systems like PagerDuty have "threshold-based" escalation (N events in M minutes) alongside "duration-based" escalation (sustained for T minutes). The brainstorm only has duration-based.

   **Fix:** Add a threshold-based fast path: if the count of qualifying events exceeds a threshold within the short window (e.g., 3 quarantines in 30 minutes in the same domain), escalate to Tier 2 immediately without waiting for the full 1h window. The multi-window confirmation still applies for slow-onset degradation, but rapid-onset gets a fast path. ISA-18.2 calls this a "rate-of-change alarm."

3. **P1 | SRE-03 | Tier specifications lack operational metadata**

   Each tier defines what happens (weight adjustment, freeze, bypass) but not who is responsible, what the expected response time is, or what recovery looks like operationally. For ISA-18.2 compliance, every alarm must have:
   - **Owner**: who is accountable for responding (role, not individual)
   - **Response time**: how quickly the owner must acknowledge
   - **Consequence of inaction**: what happens if the alarm is not addressed within the response time
   - **Recovery procedure**: what steps restore normal operation

   The brainstorm specifies recovery conditions for Tier 1 ("automatic when signal clears") and Tier 2 ("signal clear + asymmetric confirmation window") and Tier 3 ("explicit principal re-enable"), but does not specify response SLAs or owners.

   **Failure scenario:** Tier 2 fires at 2 AM. Meadowsyn displays it. Nobody is monitoring Meadowsyn. The domain remains frozen for 8 hours until the principal checks in the morning. If a response SLA existed (e.g., Tier 2 must be acknowledged within 2 hours or auto-escalate to Tier 3), the system would have self-corrected.

   **Fix:** Add a "Response Contract" to each tier: Tier 1 (no human response required, automatic), Tier 2 (principal acknowledges within N hours or auto-escalate to Tier 3), Tier 3 (principal responds within M hours or factory remains halted -- no auto-recovery). These SLAs should be configurable in intent.yaml.

4. **P2 | SRE-04 | Pain signals conflate infrastructure and competence failures**

   The brainstorm's "pain" category (line 46 in AGENTS.md) groups "quarantined beads, circuit breaker trips, gate failures, stale claims" together. These are fundamentally different signal types:
   - **Competence signals** (quarantine, gate failure): the agent tried and produced bad output. Correct response: demotion.
   - **Infrastructure signals** (circuit breaker trip, stale claim): the system failed around the agent. Correct response: wait and retry, not demote.

   If both feed into the same promotion/demotion logic, an agent that happens to run during a Dolt outage accumulates "pain" that counts toward demotion, even though the failures were infrastructure-caused.

   **Fix:** Tag signals with a cause category (competence vs. infrastructure) and filter the demotion logic to only consider competence signals. Infrastructure signals should trigger Tier 1 weight adjustments (deprioritize work that depends on broken infrastructure) but not affect the autonomy ratchet.

5. **P2 | SRE-05 | Root-cause deduplication is specified by name but not by mechanism**

   "Root-cause deduplication" appears in the six qualifications (line 65) but the brainstorm gives no detail on how it works. Key questions that must be answered for an implementable design:
   - **Grouping key**: what identifies signals as sharing a root cause? Error class? Affected component? Time proximity?
   - **Suppression behavior**: are duplicates dropped, or counted and summarized?
   - **TTL**: how long does a root-cause group stay open before new signals are treated as independent?
   - **Correlation**: does the system infer root causes (e.g., "Dolt down" -> all bd-dependent signals), or must root causes be declared?

   **Fix:** Specify at minimum a grouping key (suggest: `{signal_type, domain, 5-min bucket}`) and suppression behavior (suggest: count duplicates, emit a single signal with `count` metadata, re-emit only if count crosses a new threshold). Defer automated root-cause inference to a later wave, but require manual root-cause declarations for known infrastructure dependencies (Dolt, tmux, intercore).

### Improvements

1. Add an "Alarm Load Budget" to the vision, analogous to SRE error budgets. Define maximum acceptable signal rates per tier (e.g., Tier 1: 20/hour, Tier 2: 5/hour, Tier 3: 1/day). If the signal rate exceeds the budget, the system is over-instrumented and signals must be consolidated or suppressed. This is a direct application of ISA-18.2 Section 6.3 (alarm system performance monitoring).

2. Include a "Signal Lifecycle" diagram showing the state machine for each signal: Created -> Qualified -> (Suppressed | Confirmed) -> (Cleared | Escalated). Each transition should have a defined trigger and timeout. This makes the multi-window confirmation, rate-of-change fast path, and flood suppression composable rather than ad-hoc.

3. Define a "dark period" test: what happens when Ockham itself is unavailable for 1 hour? Clavain continues dispatching with the last-known weights (acceptable for Tier 1). But if a Tier 2 condition develops during the dark period, no CONSTRAIN fires. The vision should specify graceful degradation: Clavain's existing circuit breaker (`DISPATCH_CIRCUIT_THRESHOLD=3` in lib-dispatch.sh:25) provides local protection, but there is no equivalent for authority revocations or algedonic bypass during Ockham unavailability.
