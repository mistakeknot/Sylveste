### Findings Index
- P0 | ET-01 | "Key Decisions §4" | Cross-domain beads have no authority resolution rule — ambiguity defaults to whichever tier is encountered first
- P1 | ET-02 | "Key Decisions §4" | Promotion window is wall-clock time (24h), not evidence quantity — conflates "has not failed" with "has demonstrated competence"
- P1 | ET-03 | "Open Questions §3" | Cold start inference from pre-Ockham evidence grants retroactive authority that was never formally assessed under oversight
- P2 | ET-04 | "Key Decisions §5 §4" | Audit receipts capture decisions but not the epistemic state at decision time — forensic reconstruction is incomplete
- P3 | ET-05 | "Key Decisions §4" | Shadow tier has no explicit "must-dispatch" pathway for critical beads — operational urgency may create pressure to bypass the ratchet

Verdict: needs-changes

### Summary

Ockham's authority ratchet is structured around the right principle — asymmetric promotion and demotion, per-domain scope, shadow as the default posture — but three structural gaps undermine the integrity of the tier system in the same way that tabot custody rules fail when exceptional circumstances are used to justify temporary tier bypass. The most urgent gap is the cross-domain resolution rule: when an agent is autonomous in `interverse/**` but shadow in `core/**`, and a bead touches both, the system has no defined answer for which tier governs. This is not a policy ambiguity — it is an architectural ambiguity that defaults to whichever tier Ockham's computation encounters first, which is functionally equivalent to granting the more permissive tier by accident. The second gap is the promotion window: 24 hours of wall-clock time is not a demonstration of competence — it is a demonstration of not-yet-failing. The tabot system grants ordination after years of demonstrated qualification because qualification must be measured against the full distribution of difficulty, not a favorable sample. Ockham's 24h window, during which an agent could complete as few as 4-8 beads, is too narrow to distinguish competence from luck. The third gap is cold start: inferring ratchet positions from pre-Ockham interspect evidence is a consecration-without-ordination — the agent performed well, but under conditions of no structured oversight, and the evidence cannot reveal what the agent would have done under the oversight Ockham imposes.

### Issues Found

1. **P0 — ET-01: Cross-domain beads have no authority resolution rule**

   The vision states "state is per-domain, not per-agent — an agent can be autonomous in `interverse/**` but shadow in `core/**`" (§ "Key Decisions §4"). It does not specify what tier governs when a bead touches both domains. This is not a rare edge case: integration work, refactoring, and dependency upgrades routinely touch both plugin and core paths. Without a defined resolution rule, Ockham's weight computation for cross-domain beads has an unspecified input, and the behavior depends on implementation order.

   Failure scenario: An agent is autonomous in `interverse/**` (high hit rate, 30 completed beads) and shadow in `core/**` (no prior evidence). A bead is created that refactors an interverse plugin's dependency on a core kernel interface — it touches `interverse/myplugin/src/` and `core/intercore/src/`. Ockham computes the authority component using the first domain match it finds. If `interverse/**` matches first, the agent is dispatched at autonomous tier. The bead modifies core kernel interfaces without the principal review that shadow tier would require. The principal's assumption — "I'll always review core changes" — is violated silently.

   Smallest fix: Add a cross-domain resolution rule to the authority specification: when a bead's file scope spans multiple domains, the effective authority tier is the minimum across all matched domains. This is one additional step in the domain-authority lookup: `effective_tier = min(tier for each matched domain)`. Document this rule in the intent.yaml schema and in lib-dispatch.sh's `dispatch_rescore()` comment block.

2. **P1 — ET-02: Promotion qualification window is wall-clock time, not evidence quantity**

   The vision specifies promotion requires "multi-window confirmation (short 1h AND long 24h)" (§ "Key Decisions §3") and "explicit pleasure signals (first_attempt_pass_rate > threshold, cycle_time_trend improving) persisting past multi-window confirmation" (§ "Key Decisions §4"). The confirmation is defined in terms of time windows. At sprint pace, a 24-hour window may contain 4-8 beads — a sample too small to distinguish genuine competence from a favorable sequence of easy tasks. The tabot system requires years of demonstrated qualification because the distribution of ecclesiastical duties is wide and sparse; a deacon ordained after two successful services has not encountered the distribution that ordination must qualify.

   In Ockham's context: an agent that completes 6 auth beads successfully over 24 hours may have been assigned exclusively low-complexity auth beads with no cross-domain dependencies. The pleasure signal (first_attempt_pass_rate) would be high. The agent would be promoted to supervised. The promotion decision was correct given the evidence but the evidence was not representative of the distribution it must handle at supervised tier.

   Smallest fix: Replace the wall-clock confirmation window with an evidence quantity requirement. Promotion from shadow→supervised requires N completed beads in the domain (minimum 10) with first_attempt_pass_rate > threshold, spanning at least M distinct complexity categories (derived from bead metadata). The wall-clock window can remain as a secondary constraint (prevents rapid-fire promotion through lucky clustering) but should not be the primary gate. N and M start as hardcoded constants, wired through intercept for calibration per invariant §5.

3. **P1 — ET-03: Cold start inference grants retroactive authority without Ockham oversight**

   Open Question §3 asks: "All shadow? Or infer from existing interspect evidence?" The vision does not resolve this. The tabot lens makes the risk concrete: pre-Ockham interspect evidence was collected under conditions where the principal's oversight was informal and ad hoc — the agent was not operating under the structured CONSTRAIN/BYPASS/shadow tier system. High hit rates during this period reflect performance under no structured oversight. Inferring autonomous status from this evidence is equivalent to consecrating a tabot based on its age: the age is real, but the age is not ordination.

   Failure scenario: Before Ockham is deployed, an agent completes 50 beads in `core/**` with 85% first_attempt_pass_rate. Ockham cold-starts and, inferring from this evidence, promotes the agent to supervised in `core/**`. The agent immediately begins executing core changes with only retrospective principal review. But the 50 pre-Ockham beads were dispatched without the circuit breaker and anomaly detection infrastructure that Ockham now provides — the historical performance does not reflect what the agent would do under conditions of structured pressure, audit, and anomaly detection. The principal expected to start with full oversight and gradually relax it; Ockham's inference collapsed that expectation.

   Smallest fix: Cold start defaults to shadow for all domains, unconditionally. Add a separate `ockham init --fast-track` command that reads pre-existing interspect evidence and proposes a set of tier promotions for the principal to explicitly approve — each approval generates an audit receipt, making the retroactive grant a conscious decision rather than an automatic inference. The evidence is used to inform, not to decide.

4. **P2 — ET-04: Audit receipts capture decisions but not the epistemic state at decision time**

   Safety invariant #4 states: "Every authority decision produces a durable receipt in interspect" (§ "Key Decisions §5"). The receipt records that a decision occurred. But for forensic reconstruction — "why did Ockham promote this agent, given what it knew at 14:32 on 2026-04-02?" — the receipt must also capture the evidence state at decision time: the specific agent_reliability snapshot (hit_rate, sessions, confidence, last_active) and the active ratchet position before and after. Without this, a receipt is a log entry, not a forensic artifact. The tabot system records not just ordinations but the liturgical calendar, the officiating patriarch, and the witnesses — because the record must be reconstructable by someone who was not present.

   Does the current interspect schema for authority receipts include the input evidence snapshot? The vision does not specify. If not, calibrating promotion thresholds after deployment becomes guesswork: we know what decisions were made but not what evidence they were made from.

   Smallest fix: Define an audit receipt schema for authority decisions that includes: decision type, agent_id, domain, tier_before, tier_after, evidence_snapshot (the full output of agent_reliability at decision time), active_thresholds (the promotion criteria values at decision time), and decision timestamp. This schema should be part of the Ockham-Interspect interface contract, not an implementation detail.

5. **P3 — ET-05: Shadow tier has no explicit pathway for critical-bead urgency — gap creates bypass pressure**

   The vision notes that shadow mode means "propose, principal approves" but does not specify what happens when a critical bead in a shadow domain requires urgent execution and no promoted agent is available. The tabot system's integrity rests on the rule having no operational exception — but the tabot system has multiple ordained priests; Ockham's factory may have only one agent qualified for a domain. In that scenario, operational pressure will create an implicit expectation that shadow tier be "temporarily relaxed," which is the political exception the tabot system was designed to prevent.

   Suggested improvement: Specify an explicit "shadow-urgent" pathway: a shadow-tier agent can execute a critical bead without prior principal approval, but only if the principal has been notified and a 15-minute timer has elapsed without a halt signal. This is not a bypass — it is a defined escalation with a documented window, preserving the tabot principle that the exception is part of the rule, not a violation of it.

### Improvements

1. Adopt the minimum-tier composition rule for cross-domain beads as a named invariant alongside the five existing safety invariants. Call it "domain restriction composition: the most restrictive tier governs cross-domain beads." This belongs in the vision document's safety invariants section.

2. Replace time-window promotion confirmation with evidence-quantity confirmation, with the wall-clock window as a secondary anti-gaming constraint, not the primary gate. Define N and M as named constants in the ratchet specification.

3. Define a `fast-track` cold-start mode that converts pre-existing interspect evidence into explicit, principal-approved tier promotions, each generating an audit receipt. Make unconditional shadow the default; fast-track is opt-in.

4. Specify the audit receipt schema as part of the Interspect interface contract. Every authority decision should record the full evidence snapshot, not just the decision outcome.

5. Add a "shadow-urgent" escalation pathway that preserves the no-bypass principle while handling genuine operational urgency through a defined, audited, time-bounded procedure.
