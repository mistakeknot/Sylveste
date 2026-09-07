### Findings Index

- P0 | ATR-1 | "PHILOSOPHY.md Additions" | Authority ratchet has no defined demotion mechanism — trust only moves in one direction
- P1 | ATR-2 | "Pitch" | Evidence sufficiency thresholds never defined — "evidence earns trust" without specifying how much evidence
- P1 | ATR-3 | "Capability Mesh" | Cold-start problem unaddressed — new subsystems cannot participate in flywheel without bootstrap trust
- P2 | ATR-4 | "PHILOSOPHY.md Additions" | Gaming resistance unaddressed at vision level — no mention of adversarial evidence
- P2 | ATR-5 | "Key Decisions" | Trust boundary scope unclear — is trust per-project, per-deployment, or global

Verdict: risky

---

## Detailed Findings

### ATR-1: Authority ratchet has no demotion mechanism [P0]

**Section:** Key Decisions, Decision 5 / PHILOSOPHY.md Additions

The brainstorm proposes adding "Authority ratchet as mechanism" to PHILOSOPHY.md and describes Ockham's "graduated authority model (evidence-gated promotions/demotions)." But the vision's actual description of the ratchet is exclusively one-directional:

- "Evidence compounds. Trust ratchets."
- "Every sprint produces evidence."
- "The system that ships the most sprints learns the fastest."

The word "ratchet" itself implies one-way motion (a ratchet mechanism prevents backward rotation). The brainstorm mentions "demotions" exactly once (in the PHILOSOPHY.md additions) but never specifies:

- What triggers a demotion?
- Is demotion automatic (evidence-triggered) or discretionary (human-initiated)?
- What happens to in-flight work when a subsystem is demoted?
- How quickly does demotion propagate through dependent subsystems?

In real-world graduated authority systems (FAA pilot certification, medical residency, self-driving disengagement), demotion is at least as well-defined as promotion. The FAA can revoke a pilot's certificate on a single incident. Medical boards can suspend a license pending investigation. Self-driving systems have immediate disengagement protocols.

Compare with PHILOSOPHY.md's existing text: "No level is self-promoting. The system advances only when outcome data justifies it, and any level can be revoked if the evidence stops supporting it." The philosophy already claims revocability — but the brainstorm's vision-level mechanism doesn't operationalize it.

**Recommendation:** Define the demotion mechanism at the same level of detail as promotion. At minimum: (1) what evidence triggers demotion review, (2) is demotion immediate or graduated, (3) how does demotion affect the flywheel (does it reduce evidence production?).

### ATR-2: Evidence sufficiency thresholds undefined [P1]

**Section:** The Pitch

The pitch says "trust in autonomous systems is earned through observable evidence that compounds over time." But it never addresses:

- How much evidence is sufficient for a trust promotion?
- What quality of evidence counts? (Is a gate pass rate of 70% sufficient? 90%? 99%?)
- Over what time horizon? (10 sprints? 100? 1000?)
- Evaluated by whom? (Automated threshold? Human judgment? Committee?)

This is the difference between "evidence earns trust" (a principle) and "50 successful sprints with >95% gate pass rate earns L3 authority" (a mechanism). The brainstorm proposes the principle but defers all mechanism details.

At the vision level, exact thresholds may be premature. But the brainstorm should at least specify the structure: "each subsystem defines its own promotion criteria consisting of [evidence type] measured over [time window] evaluated by [authority]."

### ATR-3: Cold-start problem for new subsystems [P1]

**Section:** Capability Mesh

New subsystems (Hassease, Interweave F5+, future modules) start at zero trust. The brainstorm's thesis says trust is earned through evidence. But a new subsystem cannot produce evidence without some initial authority to operate.

This is the chicken-and-egg: to produce evidence, the subsystem must run sprints; to run sprints with meaningful autonomy, the subsystem needs trust; to earn trust, it needs evidence from sprints.

Real-world analogues handle this through supervised probation (medical residency: years of supervised practice before independent authority), bootstrapped credentials (FAA student pilot certificate: limited authority sufficient to generate evidence), or trust inheritance (a new employee at a trusted institution inherits institutional trust).

The brainstorm does not address which approach the evidence thesis takes. Does a new subsystem get a probationary trust level? Does it inherit trust from a predecessor (Auraken→Skaffen)? Does it require human supervision until evidence accumulates?

### ATR-4: Adversarial evidence not considered [P2]

**Section:** The Pitch

The brainstorm describes evidence as a positive signal: sprints produce evidence, evidence compounds, trust grows. But evidence can be:

- **Fabricated:** An agent optimizes for the evidence signal rather than the underlying capability (Goodhart's Law)
- **Cherry-picked:** The system generates many sprints but only surfaces evidence from successful ones
- **Selection-biased:** The flywheel routes easy tasks to subsystems that need trust, inflating their evidence

PHILOSOPHY.md already addresses Goodhart pressure ("Anti-gaming by design... Rotate metrics, cap optimization rate, randomize audits"). But the brainstorm's vision-level description of the ratchet doesn't reference these safeguards, creating a narrative where evidence is trustworthy by assumption.

### ATR-5: Trust scope unclear [P2]

**Section:** Capability Mesh

When a subsystem earns trust, what is the scope?

- Per-project? (Trust earned in project A doesn't transfer to project B)
- Per-deployment? (Trust earned on one server doesn't transfer to another)
- Global? (Trust earned anywhere applies everywhere)

This matters for the open-source strategy: if external users deploy Sylveste, do they start at zero trust, or do they inherit trust from the community's collective evidence? The brainstorm is silent on trust portability.
