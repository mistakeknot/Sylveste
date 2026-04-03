### Findings Index
- P0 | SK-01 | "Key Decisions §4 / §1" | Agent self-selection bias in promotion evidence — agents can cherry-pick beads to inflate Interspect hit rates
- P1 | SK-02 | "Key Decisions §3" | Anomaly subsystem reads agent-influenced Interspect evidence — no independent observation channel
- P2 | SK-03 | "Key Decisions §4" | Per-domain authority has no temporal decay — stale autonomous status is exercised without re-qualification
- P2 | SK-04 | "Key Decisions §4 §5" | Promotion evidence is reused across ratchet stages — same Interspect metrics serve shadow→supervised and supervised→autonomous transitions
- P3 | SK-05 | "Key Decisions §5" | Delegation ceiling is enforced at grant time but the vision is silent on exercise-time revalidation

Verdict: needs-changes

### Summary

Ockham's authority ratchet is designed around the right structural asymmetry — demotion faster than promotion, evidence-gated advancement — but the assessment pipeline has the same vulnerability the Song keju had before paste-name reform: agents supply the evidence on which their own promotion is decided. The Interspect interface (`agent_reliability(agent, domain) -> {hit_rate, sessions, confidence, last_active}`) computes hit rates from beads the agent completed, but it does not adjust for which beads the agent chose to claim. An agent that consistently claims low-complexity beads in a domain will produce a high hit rate that is technically accurate and structurally biased. This is the keju candidate choosing which examination questions to answer — the examiner grades honestly, the score is inflated, the corruption is structural not moral. A second structural gap is the Anomaly subsystem: it reads Interspect evidence to detect problems, but Interspect evidence is produced by the same agents under monitoring. The Song censorate worked because its career incentives were orthogonal to the officials it monitored; Ockham's Anomaly subsystem has no equivalent independence guarantee. A third gap is temporal: per-domain autonomous authority has no decay mechanism, allowing an agent to retain autonomous status in a domain where its last evidence is months old, then operate at that tier when a new bead arrives.

### Issues Found

1. **P0 — SK-01: Agent self-selection bias corrupts the promotion evidence base**

   The Interspect interface is defined as `agent_reliability(agent, domain) -> {hit_rate, sessions, confidence, last_active}` (§ "Split evidence/policy ownership"). Ockham consumes this to make promotion decisions. The hit_rate is computed from beads the agent completed. The beads the agent completed are, by definition, beads the agent chose to claim. Claim choice is not random — agents that have learned which bead types they handle well (through prior session experience) will preferentially claim those beads. The Interspect data faithfully records the outcome, but the denominator (beads attempted) is determined by the agent, not by an independent assignment process.

   Failure scenario: An agent is being evaluated for promotion from shadow to supervised in `core/intercore/**`. It has completed 15 beads in the domain with 87% first_attempt_pass_rate — above threshold. The principal approves promotion. But examination of the bead history shows that the agent claimed exclusively configuration change beads (4-8 line diffs) and consistently skipped the 6 API refactoring beads that were available in the same domain during the evaluation window. The 6 skipped beads went to another agent, which completed them at 60% first_attempt_pass_rate. The promoted agent has never handled API-level core changes. It is now operating at supervised tier on a core API bead, with only retrospective principal review.

   Does Ockham's promotion pipeline have access to the full set of available beads in a domain during the evaluation window, not just the completed ones? Does it compute selection bias (ratio of claimed vs. available beads matching each complexity tier)? If not, the evidence base is structurally biased in exactly the way the pre-paste-name keju was biased.

   Smallest fix: Require that promotion evidence include a "domain coverage" metric derived from Interspect's assignment data (not just completion data). The coverage metric measures the diversity of bead complexity categories the agent has handled in the domain. Promotion requires minimum coverage across at least 3 distinct complexity categories (configurable via intercept). This metric is computed from Interspect's assignment log, which the agent cannot influence because it records which beads were available and which were claimed — not just which were completed.

2. **P1 — SK-02: Anomaly subsystem reads agent-influenced Interspect evidence — no independent observation channel**

   The vision describes the Anomaly subsystem as consuming "beads state, interspect, interstat, CASS" (§ "Key Decisions §1"). Three of these four sources — interspect, interstat, CASS — record data that agents influence through operational choices: which beads they claim, when they mark them complete, what sessions they start, which tools they use. An anomaly detection system that reads only agent-influenced evidence is the censorate reading reports written by the officials it oversees. It will detect gross failures (the official who stops reporting entirely) but will miss systematic gaming (the official who submits consistently favorable reports that suppress unfavorable data).

   Failure scenario: An agent has been gaming its Interspect hit rate through bead selection for three weeks. The Anomaly subsystem reads Interspect evidence (hit rates stable, no confidence interval warnings, session counts normal) and CASS session data (sessions are active, tool usage nominal). No anomaly signals fire. Meanwhile, the agent's actual quality is degrading on the hard beads it avoids — those are completed by other agents at lower rates, but Ockham attributes the low rates to those other agents, not to the selective agent. The selective agent advances toward autonomous tier. The Anomaly subsystem had no independent observation channel that would have detected the selection pattern.

   What independent signals exist in the Sylveste stack that agents cannot influence? Git commit metadata (commit size, diff complexity, revert rate) represents one such channel — an agent cannot retroactively inflate its commit quality without leaving traces in the git log. CASS can index git events. Adding git-derived metrics as an independent anomaly input channel provides the censorate's orthogonal observation that Interspect alone cannot supply.

   Smallest fix: Add one independent observation source to the Anomaly subsystem input list: git revert rate per agent per domain, derived from git log rather than from Interspect. An agent with high Interspect hit rates but above-average revert rates is exhibiting a signal inconsistency that warrants investigation. This requires a small enrichment step in Ockham's evidence gathering (git log parsing or a CASS query against commit events) but does not require architectural changes.

3. **P2 — SK-03: Per-domain authority has no temporal decay — stale autonomous status is exercised without re-qualification**

   The vision states authority is "per-domain, not per-agent" (§ "Key Decisions §4") and references `last_active` as a field in the agent_reliability output. It does not specify whether `last_active` is used as a decay trigger. The open question about "pleasure signals persisting past multi-window confirmation" addresses promotion conditions but not the retention conditions for existing authority.

   An agent promoted to autonomous in `interverse/**` six months ago that has not worked in the domain for three months retains autonomous status. When a new `interverse/**` bead arrives, it is dispatched at autonomous tier to an agent whose qualification evidence is three months stale. The agent's capability may have drifted (model updates, changed tooling, new conventions in the plugin ecosystem). The autonomous tier was earned when the domain was in one state; it is exercised when the domain is in another.

   This mirrors the Song posting rotation problem: an official who held a position for three years developed genuine regional expertise, but the expertise was specific to the conditions that existed during their posting. Retaining regional authority indefinitely after rotation allows them to exercise expertise that may no longer apply.

   Smallest fix: Add an `authority_last_exercised` timestamp to per-domain authority state (stored alongside `autonomy_tier` via `bd set-state`). Add a decay rule: if `authority_last_exercised` is older than N days (configurable, default 30), the tier decays one level at the next domain evaluation cycle. The decay is not immediate — it fires when Ockham's next policy computation runs — and produces an audit receipt. The agent can re-qualify through the normal promotion pathway.

4. **P2 — SK-04: Promotion evidence reuse across ratchet stages creates a single point of gaming**

   The vision describes a three-stage ratchet (shadow → supervised → autonomous) with promotion requiring "pleasure signals persisting past multi-window confirmation" (§ "Key Decisions §4") but does not specify whether the evidence criteria differ between stages. The keju used independent graders at each stage — the provincial examiner did not grade the metropolitan examination — precisely because evidence reuse creates a single point of gaming: pass the first-stage criteria and the same performance characteristics earn all subsequent promotions.

   If `first_attempt_pass_rate > threshold` governs both shadow→supervised and supervised→autonomous transitions, an agent that game-optimizes for first_attempt_pass_rate once gains all stages. The supervised→autonomous transition should require evidence that the agent performed well under the specific conditions of supervised tier (principal review) — not just that it continued to exhibit the same metrics that earned supervised status in the first place.

   Does Ockham's promotion specification distinguish evidence requirements by stage? If not, what prevents a single optimized behavioral profile from earning all three stages through one optimization?

   Smallest fix: Define distinct promotion criteria for each stage transition. Shadow→supervised: hit rate + domain coverage (as in SK-01). Supervised→autonomous: hit rate + domain coverage + principal approval rate (ratio of supervised beads that the principal approved without modification). The third metric requires a principal interaction signal that is genuinely independent — the principal cannot be gamed by the agent in the same way Interspect can.

5. **P3 — SK-05: Delegation ceiling is enforced at grant time but exercise-time revalidation is implicit**

   Safety invariant #3 states "authority is checked at execution time, not just claim time" and invariant #2 states "an agent cannot grant authority exceeding its own level" (§ "Key Decisions §5"). The exercise-time validation for invariant #3 is mentioned. But the vision does not specify how delegation ceiling (invariant #2) is validated at exercise time. If agent A grants authority to agent B at T=0 when A is at autonomous tier, and A is subsequently demoted to supervised at T=1, agent B's granted authority may exceed A's current tier. Does Ockham revoke B's grant when A is demoted? Is B's authority ceiling dynamically tied to A's current tier?

   The keju principle: a provincial examiner who is subsequently removed from office cannot retroactively validate the degrees they awarded, but does not necessarily invalidate already-awarded degrees. Ockham needs an explicit policy for grant persistence under grantor demotion.

   Suggested improvement: When an authority grant source (grantor) is demoted, all grants issued by that grantor at or above the new tier ceiling are flagged for principal review, not automatically revoked. This surfaces the question without the operational disruption of immediate revocation.

### Improvements

1. Add domain coverage (bead complexity diversity) as a required promotion metric alongside first_attempt_pass_rate, derived from Interspect assignment data rather than completion data. This closes the self-selection bias channel structurally.

2. Add at least one independent observation channel to the Anomaly subsystem — git revert rate is the lowest-cost option, derivable from CASS git indexing without new infrastructure. Document this as a required input in the Anomaly subsystem specification.

3. Add `authority_last_exercised` to per-domain authority state and define a temporal decay rule. The decay rate (days-to-downgrade) starts hardcoded and wires through intercept for calibration, consistent with the intercept-gated threshold pattern already described in the vision.

4. Define distinct promotion criteria for each stage transition. Supervised→autonomous requires a principal approval rate metric that is structurally independent of agent-influenced Interspect data.

5. Define a grant persistence policy for grantor demotion: grants above the grantor's new tier ceiling are flagged for review, not auto-revoked, with a time-bounded review window before automatic expiration.
