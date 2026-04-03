---
artifact_type: flux-drive-review
reviewer: fd-hadza-camp-fission-fusion-egalitarianism
track: D (Esoteric)
target: docs/brainstorms/2026-04-03-ockham-vision-brainstorm.md
---

# Ockham Vision — Hadza Camp Fission-Fusion Review

### Findings Index
- P0 | HADZA-01 | "Key Decisions §4" | Per-domain autonomy tiers not enforced with domain-boundary isolation; cross-domain reputation leakage possible
- P1 | HADZA-02 | "Key Decisions §5" | 'No self-promotion' is a rule without a leveling mechanism — violation is detectable only after the fact
- P1 | HADZA-03 | "Key Decisions §5 / §3" | Human halt supremacy has undocumented exit costs that undermine its frictionlessness
- P2 | HADZA-04 | "Key Decisions §4" | Promote/demote asymmetry ratio is unspecified; insufficient asymmetry allows authority accumulation through moderate luck
- P3 | HADZA-05 | "Open Questions §3 / §5" | Reputation portability across domains is unaddressed — both zero and full portability are wrong

**Verdict: needs-changes**

---

### Summary

The Hadza of Tanzania maintain effective collective governance with no chiefs, no formal authority, and no coercive institutions. Their system works through three mechanisms that map onto Ockham's design: domain-specific authority (the best tracker leads tracking only), an asymmetric reputation ratchet (generosity earned slowly, reputation destroyed fast), and exit as the ultimate governance tool (anyone can leave any camp). The brainstorm captures the autonomy ratchet's asymmetry and the human halt supremacy correctly as design intentions, but the implementation is underspecified in ways that would allow the exact failure modes the Hadza system evolved to prevent: authority earned in one domain leaking into another, and persistent authority accumulating because demotion thresholds are insufficiently asymmetric. The most surprising finding is the human halt supremacy issue: the brainstorm lists five existing mechanisms that implement the halt, but does not assess whether mid-execution states create exit costs that delay the halt from taking effect — the equivalent of a Hadza camp member announcing their departure but being unable to leave because they owe meat from a pending hunt.

---

### Issues Found

**1. P0 — HADZA-01: Per-domain autonomy tiers have no enforcement of domain-boundary isolation**

The brainstorm (§4) states: "State is per-domain, not per-agent — an agent can be autonomous in `interverse/**` but shadow in `core/**`." This is the correct design intention. The gap: nowhere in the brainstorm is it specified how domain-boundary isolation is enforced against leakage through interspect's `agent_reliability` interface.

The interface is defined as: `interspect exposes agent_reliability(agent, domain) -> {hit_rate, sessions, confidence, last_active}`. If this function returns domain-scoped scores correctly (separate scores for `interverse/**` and `core/**`), domain isolation is preserved. But if the function returns an aggregate score (total hit_rate across all domains) or if Ockham's authority subsystem aggregates scores before applying domain filters, an agent's high reliability in `interverse/**` will inflate its apparent reliability in `core/**`.

This is structurally identical to the Hadza tracking-prestige-to-governance-authority leak that leveling mechanisms exist to prevent. The best tracker's authority in camp governance is not zero — it is actively suppressed by leveling. The suppression is structural: when the tracker begins acting like a chief in camp matters, other camp members mock them until they stop. The leveling is not optional behavior; it is a reliable structural response.

Concrete failure scenario: An agent has run 200 sessions in `interverse/**` with a 0.95 hit rate. It has run 3 sessions in `core/**`. Ockham's authority subsystem calls `interspect.agent_reliability(agent, "core/**")`. If interspect returns the aggregate score (0.95) rather than the domain-scoped score (3 sessions, insufficient for promotion), the agent is promoted to supervised in `core/**` based on evidence from a different domain. A mis-calibrated change to core kernel is now executed with supervised autonomy — one step below autonomous — after only 3 core observations.

Fix: The `agent_reliability(agent, domain)` contract must be specified to return domain-scoped scores, and Ockham's authority subsystem must assert it is using domain-scoped evidence. Add a validation: before any promotion decision, assert `evidence.domain == target_domain`. This is a one-line guard in the authority subsystem. Additionally, specify in the interspect interface contract that aggregate scoring is not an acceptable implementation of `agent_reliability(agent, domain)`.

**2. P1 — HADZA-02: 'No self-promotion' is a rule without a leveling mechanism**

The brainstorm (§5) states: "No self-promotion. An agent cannot elevate its own authority tier or domain grants." This is stated as a prohibition — a rule. The Hadza don't have a rule against acting like a chief; they have a leveling mechanism that activates when someone acts like a chief. The distinction matters because rules require the rule-follower to comply, while leveling mechanisms work regardless of the rule-violator's intent.

The brainstorm's self-promotion prohibition implicitly relies on Ockham choosing not to issue self-promotions. A software bug in Ockham's authority subsystem — not an adversarial agent, just a logic error — could cause Ockham to issue a domain expansion that effectively promotes itself. If no consuming system (lib-dispatch.sh, bd set-state) checks whether a promotion is self-issued and rejects it, the violation succeeds silently.

The critical timing issue: the brainstorm specifies "Audit completeness: Every authority decision produces a durable receipt in interspect." This means violations are recorded, but recording is post-hoc. Interspect detects the violation at its next audit cycle. The Hadza leveling mechanism is not post-hoc — it fires immediately when the behavior is observed, before the chief has had time to consolidate authority. The difference between immediate structural rejection and next-audit-cycle detection is the window for unauthorized authority accumulation.

Concrete failure scenario: A logic error in Ockham's pleasure-signal processing causes it to evaluate a domain expansion: an agent with strong evidence in `interverse/auth/**` triggers a domain reclassification that expands to `interverse/**`. Ockham writes `autonomy_tier=autonomous` for `interverse/**` to that agent's bd state. lib-dispatch.sh reads it and honors it. Interspect records the write. At the next audit cycle (hours or days later), interspect flags the self-issued promotion. In the intervening window, the agent has been executing autonomously in a broader domain than it earned.

Fix: `bd set-state autonomy_tier=<tier>` (and any equivalent command) should check whether the caller is the same entity as the target and reject the write with a structured error. This shifts detection from Ockham (behavioral prevention) to the execution path (structural rejection). Interspect's audit should additionally scan for self-issued authority writes as a second detection layer — matching the Hadza dual mechanism of structural impossibility plus social observation.

**3. P1 — HADZA-03: Human halt supremacy has undocumented exit costs**

The brainstorm (§6) lists five existing mechanisms that implement the halt:
- `~/.clavain/factory-paused.json` — Tier 3 halt
- `~/.clavain/paused-agents/<id>.json` — Tier 2 agent demotion
- `ic lane update --metadata="paused:true"` — Tier 2 theme freeze
- `_interspect_apply_routing_override()` — Tier 2 agent exclusion
- `bd set-state autonomy_tier=3` — Tier 2 ratchet demotion

The brainstorm (§5, invariant 5) states: "The principal can halt the entire factory at any time. No Ockham policy can override or delay a human halt."

The Hadza exit mechanism works because exit is truly frictionless — anyone can walk to another camp at any time, with no exit costs, no mid-hunt obligations that must be completed first, no social debt that prevents departure. The freedom of exit is absolute, which is what makes it the ultimate governance mechanism.

The brainstorm specifies that `factory-paused.json` implements Tier 3 halt. But it does not address what happens to beads that are mid-execution when the halt fires. If a bead is currently being executed by an agent (a subprocess is running, a file is being modified, a test is in flight), does the halt: (a) interrupt immediately (true frictionlessness), (b) wait for current bead execution to complete (exit cost), or (c) complete current execution and prevent new dispatches (soft halt)?

The brainstorm is silent on this. If the answer is (b) or (c) — both reasonable implementations — then human halt supremacy is not truly immediate, which weakens it as a governance guarantee. The principal writes `factory-paused.json` and waits. In the Hadza analogy, the principal announces departure but must finish distributing the meat from the current hunt first.

Concrete failure scenario: A Tier 3 bypass fires during a sequence where an agent is mid-execution on a core kernel modification. The principal writes `factory-paused.json`. Clavain's dispatch loop checks `factory-paused.json` at its next poll interval (say, 30 seconds). The executing agent continues for up to 30 seconds. In a security-relevant scenario (an agent has made unauthorized changes and the principal wants to halt immediately), this 30-second window is a genuine exit cost.

Fix: Document the halt semantics explicitly — specify which halt mode (interrupt/wait/soft) is implemented and why. If the answer is "soft halt" (complete current bead, block new dispatches), say so explicitly and explain why it is the right tradeoff. If the design intends "interrupt halt" (kill running agents immediately), specify how mid-execution state cleanup works. The brainstorm's silence on this is the gap — not the choice of halt mode, but the absence of a specification.

**4. P2 — HADZA-04: Promote/demote asymmetry ratio is unspecified**

The brainstorm (§4) states: "Demotion fires faster than promotion (asymmetric, matching every credentialing system studied)." The asymmetry is described qualitatively but not quantitatively. How many successful sessions constitute the promotion signal? How many failures trigger demotion?

The Hadza asymmetry is not arbitrary. Researchers estimate a 10:1 to 20:1 ratio because the cost of misplaced authority (a bad hunter leads a hunt, 20 people waste a day, the protein deficit is immediate) vastly exceeds the cost of delayed promotion (a skilled hunter leads one more supervised hunt before being recognized). The asymmetry is calibrated to the cost ratio of false positives versus false negatives in authority grants.

In Ockham's context, the cost of a false positive (promoting an agent that is not ready for autonomous operation in `core/**`) vastly exceeds the cost of a false negative (making a ready agent wait one more supervised cycle). A false positive in `core/**` autonomous mode means an agent makes unsupervised changes to the kernel — the blast radius is the entire factory. A false negative means a competent agent has one more review cycle — a minor friction.

If the promotion threshold is "3 sessions at >0.9 first_attempt_pass_rate" and the demotion threshold is "1 session at <0.7," the asymmetry is 3:1. The Hadza evidence suggests this is insufficient to prevent authority accumulation through a moderate run of luck. An agent that gets 3 easy beads in a row with no edge cases could promote to autonomous in `core/**` before it has faced the bead types that would reveal its limitations.

Fix: Specify the asymmetry ratio explicitly and tie it to the blast-radius difference between false positives and false negatives. A reasonable starting point: promotion requires 10+ sessions in current tier with no failures and first_attempt_pass_rate > 0.92; demotion requires 1 session failure (any severity) in the same domain. Document these numbers as calibration targets for the intercept model, not permanent thresholds.

**5. P3 — HADZA-05: Reputation portability across domains is unaddressed**

Open Question 3 asks whether cold start defaults to all-shadow. Open Question 5 asks which metrics constitute pleasure signals. Neither question addresses reputation portability: when an agent starts operating in a new domain, should interspect's evidence from other domains count toward its authority assessment in the new domain?

When a Hadza individual moves to a new camp, they bring their reputation — but the new camp applies a discount. A skilled tracker who is new to this particular watershed is trusted at a reduced level until they demonstrate local knowledge. The discount is not zero (zero portability would waste the evidence that exists) and not full (full portability would cause domain-leakage, the P0 above).

The brainstorm does not specify portability policy. The likely default in implementation is zero portability (each domain starts from scratch), which is conservative but wasteful: an agent with 500 sessions of evidence in `interverse/**` starts in shadow mode in `interverse/auth/**` as if it were a new agent.

Suggestion: Define a portability discount: when an agent begins operating in a new sub-domain, initialize its authority assessment with a discounted view of its evidence from the most closely related domain. "Most closely related" is determined by directory prefix distance: `interverse/auth/**` is closer to `interverse/**` than to `core/**`. The discount factor (e.g., 50% of the sessions count toward the new domain's threshold) means the agent reaches promoted status in half the normal sessions. This is a concrete answer to Open Question 3 that also resolves the edge case in Open Question 5 (what counts as a pleasure signal when evidence comes from a related domain).

---

### Improvements

1. **Assert domain-scoping in agent_reliability contract**: Add a single validation in Ockham's authority subsystem: before any promotion decision, assert `evidence.domain == target_domain` and fail the promotion if the assertion is false. Specify in the interspect interface contract that `agent_reliability(agent, domain)` must return domain-scoped evidence, not aggregate evidence.

2. **Push self-promotion rejection to the write path**: Add a check to `bd set-state autonomy_tier=<tier>` that rejects writes where `asserting_principal == target_agent`. This is a structural leveling mechanism, not a conditional inside Ockham. Interspect's audit additionally scans for self-issued authority writes as a secondary detection layer.

3. **Specify halt semantics explicitly**: Add a "Halt behavior" section to the brainstorm specifying which halt mode is implemented (interrupt/wait/soft), what happens to mid-execution beads when the halt fires, and the maximum latency between `factory-paused.json` write and dispatch cessation. This does not require choosing a specific mode — it requires specifying whatever mode is chosen.

4. **Specify the asymmetry ratio with blast-radius justification**: Replace "demotion fires faster than promotion" with concrete numbers. Tie the ratio to the blast-radius asymmetry between false positive and false negative authority grants. Document as calibration targets for the intercept model.

5. **Define reputation portability with directory-prefix discounting**: Specify that new-domain authority assessment initializes with a discounted view of evidence from the most closely related domain (determined by directory prefix distance), with a discount factor that reduces effective session count. This resolves the cold-start edge case while maintaining domain-boundary isolation.
