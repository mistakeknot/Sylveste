### Findings Index

- P0 | PPN-1 | "Pitch" | Aspirational-operational conflation — the flywheel is described as functioning when key upstream sources are in brainstorm/plan phase
- P1 | PPN-2 | "Pitch" | Target audience unidentified — the pitch negates ("not a coding assistant") but never affirms who it's for
- P1 | PPN-3 | "Capability Mesh" | Terminology barrier — 7+ terms require insider knowledge, no glossary or plain-language equivalents
- P2 | PPN-4 | "Pitch" | Differentiation is negative only — no named competitors or alternative approaches
- P2 | PPN-5 | "What's Next" | Aspirational-operational ratio undisclosed — reader cannot distinguish shipped from planned

Verdict: needs-changes

---

## Detailed Findings

### PPN-1: The pitch describes a functioning flywheel that doesn't yet function [P0]

**Section:** The Pitch

The pitch states: "Every sprint produces evidence. Evidence compounds. Trust ratchets. The system that ships the most sprints learns the fastest."

This reads as a description of current reality. But the capability mesh reveals:
- Interweave (ontology): F1-F3 shipped, F5 in progress — not yet producing meaningful evidence for the flywheel
- Ockham (governance): F1-F7 shipped — newly created, evidence accumulation has barely begun
- Hassease (execution): brainstorm/plan phase — not operational
- Interop (integration): Phase 1 shipped — early stage

The v5.0 flywheel with 4 upstream sources is aspirational. The v4.0 flywheel (Interspect-only) is closer to operational. But the pitch does not distinguish between "the flywheel we're building" and "the flywheel that's running." A reader unfamiliar with the project would believe the full evidence loop is closed.

This is the most significant positioning issue: a vision document that describes its aspiration in the present tense erodes credibility when readers discover the gap. Either (1) use future tense for the expanded flywheel, (2) explicitly mark what's operational vs. planned, or (3) frame the pitch around the v4.0 flywheel that exists and position v5.0 as the expansion.

**Recommendation:** Add a single sentence to the pitch: "Today the flywheel operates on Interspect evidence alone. The v5.0 expansion adds three upstream sources — ontology, governance, and integration — that are in early operational phases."

### PPN-2: No affirmative audience identification [P1]

**Section:** The Pitch

The pitch says: "Not a coding assistant. Not an agent framework. A platform for autonomous agencies that earn trust through receipts."

This tells the reader what Sylveste isn't. But who is it for? The v4.0 vision had clear audience segmentation (platform builders / proof by demonstration / personal rig). The v5.0 brainstorm doesn't reference audience at all. The pitch lands differently for:

- **A developer evaluating tools:** Needs to know if this replaces their coding assistant, their CI pipeline, or their project management
- **A platform builder:** Needs to know what primitives they can build on
- **An investor/advisor:** Needs to know the market positioning

"Autonomous agencies that earn trust through receipts" is evocative but not audience-targeted. Who builds autonomous agencies? Who needs them? What problem are they solving for their end users?

### PPN-3: Dense insider terminology [P1]

**Section:** Throughout

Terms requiring Sylveste-specific knowledge to parse:

1. Interweave — no context clue that this means ontology/entity tracking
2. Ockham — no context clue that this means governance/policy
3. Interspect — no context clue that this means profiler/learning loop
4. FluxBench — no context clue that this means model qualification
5. Interop — somewhat self-explanatory but still project-specific
6. INFORM signals — unexplained (algedonic signals also unexplained)
7. Authority ratchet — explained in context but assumes familiarity with the metaphor

In addition: "Zollman effect," "algedonic signals," "capability mesh," and "evidence epoch" are domain-specific terms from epistemology, cybernetics, and maturity modeling.

A vision document should be readable by someone encountering the project for the first time. Currently, the brainstorm assumes the reader already knows all subsystem names and their functions.

### PPN-4: No competitive differentiation [P2]

**Section:** The Pitch

The pitch differentiates by negation ("not a coding assistant, not an agent framework") but never names what the reader might be considering instead. In the agent platform space, alternatives include LangGraph, CrewAI, AutoGen, Devin, Replit Agent, and Cursor. A vision document doesn't need a competitive matrix, but it should at least acknowledge the landscape.

### PPN-5: No shipped/planned transparency [P2]

**Section:** What's Next + Capability Mesh

The capability mesh mixes shipped systems with brainstorm-phase ideas in the same table format. The "What's Next" section assigns priorities but doesn't indicate what percentage of each item is already built. A transparency marker (e.g., "[operational]" vs. "[in development]" vs. "[planned]") would help readers calibrate their expectations.
