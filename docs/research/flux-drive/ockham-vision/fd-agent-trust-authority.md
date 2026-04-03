### Findings Index
- P0 | ATA-01 | "Autonomy ratchet with per-domain state" | Agents can game promotion by self-selecting low-difficulty beads in a domain
- P1 | ATA-02 | "Safety invariants" | Safety invariants 1-2 are behavioral (depend on Ockham compliance), not structural (impossible to violate)
- P1 | ATA-03 | "Autonomy ratchet" | In-flight bead continues executing at old authority level after mid-execution demotion
- P2 | ATA-04 | "Autonomy ratchet" | Cold-start defaults to all-shadow with no mechanism to bootstrap from historical interspect evidence
- P2 | ATA-05 | "Safety invariants" | Cross-domain authority leakage via shared agent state in interspect

Verdict: needs-changes

### Summary

The authority subsystem defines five safety invariants and a per-domain autonomy ratchet. Evaluated from a security architecture perspective, the invariants are necessary but two of the five are enforceable only by Ockham's own compliance -- they are policy rules, not structural impossibilities. The most significant gap is the promotion gaming vector: because Clavain's `dispatch_rescore()` includes random perturbation (lines 203-204 in lib-dispatch.sh) and does not factor difficulty into scoring, an agent that repeatedly claims low-difficulty beads in a domain will accumulate a high `first_attempt_pass_rate` and earn promotion. The interspect evidence pipeline observes outcomes but has no difficulty-adjustment mechanism, making the promotion metric gameable by selection bias.

### Issues Found

1. **P0 | ATA-01 | Promotion gaming via bead difficulty selection bias**

   The brainstorm (lines 67-73) specifies promotion requires `first_attempt_pass_rate > threshold` and `cycle_time_trend improving`, both persisting past multi-window confirmation. Interspect provides `agent_reliability(agent, domain) -> {hit_rate, sessions, confidence, last_active}`. Neither the promotion criteria nor the evidence interface includes any measure of task difficulty.

   In `dispatch_rescore()` (lib-dispatch.sh:133-218), beads are scored by priority (40%), phase (25%), recency (15%), deps (12%), and WIP (8%). None of these are difficulty signals. An agent that claims many small, well-specified beads in a domain will complete them at high rates with low cycle times, satisfying both promotion criteria.

   **Failure scenario:** Agent A recognizes (through prompt history or pattern) that `interverse/**` beads tagged `docs` or `config` have near-100% first-attempt-pass rates. Agent A consistently claims these beads. After the multi-window confirmation period, its hit_rate in `interverse/**` crosses the promotion threshold. It is promoted to autonomous in `interverse/**`. It then claims a complex bead -- a plugin refactor -- and produces code that passes tests but introduces subtle integration issues caught only in later reviews.

   This is analogous to the "cream-skimming" problem in insurance and credentialing: allowing the credentialee to choose their evaluation tasks undermines the validity of the credential.

   **Fix:** Normalize `first_attempt_pass_rate` by difficulty. Options: (a) weight each bead's pass/fail by its priority score (higher priority = harder, counts more), (b) require a minimum distribution of bead types (at least N beads above median priority) for promotion eligibility, (c) have Ockham assign "promotion challenge" beads that the agent must complete -- these are chosen by Ockham, not the agent, preventing selection bias. Option (b) is the smallest viable fix.

2. **P1 | ATA-02 | Safety invariants 1-2 are behavioral, not structural**

   Invariant 1: "No self-promotion -- an agent cannot elevate its own authority tier or domain grants." Invariant 2: "Delegation ceiling -- an agent cannot grant authority exceeding its own level."

   These invariants are enforced by Ockham being the sole writer of authority state. But the brainstorm specifies that Ockham writes via `ic state set` and `bd set-state` (lines 53, 91). Any process with write access to these stores can modify authority state. Agents run as the same Unix user (`mk` or `root`). There is no ACL, capability token, or cryptographic signature that prevents an agent from calling `ic state set "authority_grant" "autonomous"` for its own session.

   In security architecture terms, these invariants rely on "policy compliance" (agents follow the rules) rather than "structural enforcement" (the system makes violations impossible). The distinction matters because:
   - In shadow/supervised mode, agents operate under review -- compliance failures are caught
   - In autonomous mode, the agent operates without pre-review -- a compliance failure goes undetected until audit

   **Failure scenario:** An agent in autonomous mode in domain A executes a script that includes `ic state set "autonomy_tier" "3" <agent_id>` for domain B. Since all processes run as the same user, this write succeeds. The next dispatch cycle treats the agent as autonomous in domain B.

   **Fix:** Add a structural enforcement layer: (a) authority writes require a signed token that only Ockham can produce (HMAC over `{agent_id, domain, tier, timestamp}` with a secret only Ockham holds), or (b) authority state is stored in a write-protected location that agents cannot access (e.g., a Dolt table with row-level permissions keyed to the Ockham process, not the user). Option (a) is simpler and fits the CLI-first architecture. The vision should note that the invariants are currently behavioral and specify the structural enforcement mechanism planned for Wave 3.

3. **P1 | ATA-03 | Demotion does not revoke in-flight authority**

   Invariant 3 says "Authority is checked at execution time, not just claim time." But "execution time" in the current architecture is ambiguous. A bead lifecycle has multiple execution points: claim, plan, implement, test, commit, push. If authority is checked only at claim time:
   - Agent claims bead at 10:00 (authority: autonomous in `core/*`)
   - Ockham demotes agent at 10:05 (authority: shadow in `core/*`)
   - Agent commits code at 10:15 (still operating under the claim-time authority)

   The brainstorm's description of action-time validation (line 82) says "Grants can expire or be revoked between claim and execution" but does not specify who checks, when, or what happens to in-flight work.

   **Failure scenario:** An agent is demoted mid-bead due to a quarantine in the same domain. The agent has already written implementation code and is in the review phase. Under shadow mode rules, a human should review before commit. But the demotion occurred after the implementation started, and the bead's `autonomy_tier` in `bd set-state` was set at claim time.

   **Fix:** Specify two checkpoints for authority validation: (a) at claim time (already implied), and (b) at commit/push time (the irreversible action). Clavain's quality-gates flow already has a pre-commit phase -- adding an authority re-check there (read current tier from `ic state`, compare to tier at claim time, block if downgraded) is a single `if` statement in the gate logic.

4. **P2 | ATA-04 | Cold-start defaults with no historical evidence bootstrap**

   Open question 3 (line 99) asks "What are the initial ratchet positions? All shadow? Or infer from existing interspect evidence?" The brainstorm does not answer this. If all agents start at shadow, the factory is throttled to principal-approval speed until enough evidence accumulates for promotion -- a cold-start penalty that could last days.

   Interspect already has historical evidence from pre-Ockham factory runs. This evidence is not mentioned as an input to the initial ratchet positioning.

   **Fix:** Define a cold-start algorithm: (a) query interspect for `agent_reliability(agent, domain)` for all known agents and domains, (b) if `sessions > N` and `hit_rate > promotion_threshold` and `confidence > 0.8`, initialize at supervised (not autonomous -- promotion from supervised to autonomous should still require multi-window confirmation under Ockham's active observation), (c) otherwise initialize at shadow. This is conservative (never starts autonomous) but avoids the full cold-start penalty.

5. **P2 | ATA-05 | Cross-domain authority leakage via shared agent state**

   Authority is per-domain (line 68: "an agent can be autonomous in `interverse/**` but shadow in `core/**`"). But interspect's `agent_reliability()` interface returns a single record per `(agent, domain)` pair. The brainstorm does not address whether:
   - An agent's hit_rate in domain A influences its promotion timeline in domain B
   - A demotion in domain A triggers a review of the agent's tier in domain B
   - Pleasure signals (first_attempt_pass) in one domain can mask pain signals in another

   In RBAC systems, this is the "confused deputy" problem: authority in one context leaks into another through a shared intermediary.

   **Fix:** The vision should explicitly state that promotion/demotion decisions are domain-isolated: evidence in domain A affects only the tier in domain A. Cross-domain correlation (e.g., "agent that fails in core/* should be reviewed in sdk/*") should be a separate, explicit rule, not an implicit side effect of shared state.

### Improvements

1. Add a "Threat Model" section to the vision enumerating the adversarial scenarios the safety invariants protect against. At minimum: self-promotion, delegation escalation, evidence tampering, difficulty gaming, and in-flight authority bypass. For each scenario, label the enforcement as structural or behavioral and note the Wave in which structural enforcement arrives.

2. Define "evidence independence" as a first-class property: interspect must observe agent outcomes independently of agent self-reporting. The brainstorm implies this (interspect is a separate system) but does not make it explicit. An agent should never be able to influence its own hit_rate by reporting results to interspect -- all evidence should come from external observation (bead status, gate verdicts, quarantine events).

3. Consider a "promotion board" mechanism for the shadow-to-supervised transition: instead of a purely automated threshold, require that the first promotion in each domain be confirmed by the principal. This provides a human-in-the-loop checkpoint during the most safety-critical transition (agent gains unsupervised execution), after which Ockham can manage supervised-to-autonomous automatically. This matches credentialing systems in medicine and aviation where the first grant is human-approved and subsequent renewals are metrics-based.
