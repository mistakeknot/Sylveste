### Findings Index
- P0 | PN-1 | "The Pitch" | Pitch describes the flywheel in present tense but multiple upstream sources are in brainstorm/plan phase — a reader would believe the system is operating when key links are aspirational
- P1 | PN-2 | "The Pitch" | No identifiable audience — "not a coding assistant, not an agent framework" negates but never affirms the target reader
- P1 | PN-3 | "The Pitch" | Differentiation is only negative — no competitors or alternative approaches named, making differentiation abstract
- P2 | PN-4 | "Key Decisions" | Terminology accessibility: 8+ terms require domain-specific knowledge with no glossary or plain-language equivalent
- P2 | PN-5 | "Key Decisions §3" | Garden Salon moved to Horizons with no replacement experience narrative — leaves a "what does the user touch?" gap
Verdict: needs-changes

### Summary

The brainstorm's pitch is intellectually rigorous but fails the "explain it to someone outside the project" test. The present-tense framing of the flywheel implies an operating system when key components are aspirational. The audience is defined by negation ("not a coding assistant") without affirmation. Competitive positioning names no alternatives. A developer platform vision that requires insider knowledge of 8+ internal subsystem names to parse has a fundamental accessibility problem.

### Issues Found

PN-1. P0: The pitch uses present-tense language that implies the evidence loop is closed: "Every sprint produces evidence. Evidence compounds. Trust ratchets." A reader unfamiliar with Sylveste's current state would believe this is a description of a shipped product. In reality: Interspect Phase 2 (the flywheel engine) is listed as P1 in What's Next and "blocked on measurement hardening." Ockham (governance) has "F1-F7 shipped" but its authority ratchet events are not yet emitted. Interweave (ontology) has "F1-F3 shipped, F5 in progress" but query metrics are not instrumented. Execution (Hassease) is at "brainstorm/plan phase." The ratio of shipped-to-aspirational in the flywheel is roughly 40-60%, but the pitch reads as 100% operational. This is not dishonesty — vision documents are aspirational by nature — but the v5.0 brainstorm specifically rejects aspirational framing (Approach B rejected because it "risks sounding like vaporware"). The document should either use future tense for unshipped components or include an explicit "today vs. tomorrow" distinction in the pitch.

PN-2. P1: The brainstorm defines the audience by negation: "Not a coding assistant. Not an agent framework. A platform for autonomous agencies that earn trust through receipts." This tells the reader what Sylveste is NOT but never says who should use it. The v4.0 vision had a clearer audience section: "for developers and platform builders" (Sylveste), "for everyone" (Garden Salon). The v5.0 brainstorm drops this because Garden Salon moves to Horizons, leaving no affirmative audience statement. "Autonomous agencies" is the what, not the who. Who builds these agencies? Solo developers? Platform teams? Researchers? Enterprise architects? The pitch needs one sentence naming the human reader: "For [role] who [activity]."

PN-3. P1: The brainstorm differentiates Sylveste from categories ("not a coding assistant, not an agent framework") but never names specific alternatives or competitors. The v4.0 vision similarly did not name competitors, but v4.0's differentiation was clearer because it positioned against the "pick two" tradeoff (autonomy/quality/efficiency). The v5.0 brainstorm's differentiation — "trust earned through receipts" — is unique but abstract. A developer evaluating Sylveste against LangGraph, CrewAI, AutoGen, or OpenAI Agents SDK cannot determine from the vision alone why this is better. Even one concrete comparison ("Unlike X, which Y, Sylveste Z") would sharpen the positioning. Alternatively, the brainstorm could name the structural feature that competitors lack (durable evidence pipeline, closed-loop learning, kernel-enforced gates) in terms a developer who knows those tools would recognize.

PN-4. P2: Terminology count requiring domain-specific knowledge: (1) capability mesh, (2) authority ratchet, (3) algedonic signals, (4) Zollman effect, (5) sparse topology, (6) stigmergic coordination, (7) CXDB, (8) AgMoDB, (9) INFORM signals, (10) ring/small-world topology. Ten terms in a 143-line brainstorm that require explanation for an external reader. Some (capability mesh, authority ratchet) are introduced with enough context to be parseable. Others (algedonic signals, Zollman effect, stigmergic) appear without definition. A brainstorm is an internal document, so this is P2 rather than P1 — but if the brainstorm informs the vision document, the vision must provide a glossary or use plain-language equivalents for at least the 5 terms that come from outside the project's own vocabulary.

PN-5. P2: Decision 3 moves Garden Salon from "What's Next" to "Horizons." This is honest (Garden Salon depends on preconditions that aren't met), but it creates a positioning gap: the vision now describes only infrastructure. There is no "what does the user touch?" narrative. The v4.0 vision had a clear two-brand story: "Sylveste is the infrastructure. Garden Salon is the experience." The v5.0 brainstorm acknowledges the two-brand architecture is "out of scope for v5.0" but doesn't offer an interim experience narrative. A developer reading the v5.0 vision would see kernel, OS, plugins, profiler — and ask "but what do I interact with?" The answer (CLI, TUI via Autarch, Claude Code plugins) exists but is not positioned as the user surface in the brainstorm.

### Improvements

IMP-1. Add one sentence of affirmative audience identification: "For [role] who [activity], Sylveste provides [capability]." This grounds the negation-based positioning.

IMP-2. Include explicit shipped/aspirational markers in the pitch. Even a parenthetical — "Every sprint produces evidence (today). Evidence compounds (today via Interspect F1-F5). Trust ratchets (planned: Ockham authority ratchet, in progress)." — would prevent a misleading read.

IMP-3. Name the competitive landscape, even briefly. "Unlike agent frameworks that orchestrate tool calls, Sylveste orchestrates full development lifecycles with durable evidence and closed-loop learning" — one sentence that gives an external reader a mental model for where this sits.

IMP-4. Create a term glossary for the vision document. Not in the brainstorm, but flagged as a requirement for the v5.0 vision itself.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 5 (P0: 1, P1: 2, P2: 2)
SUMMARY: The pitch implies a fully operational evidence loop when key components are aspirational (P0). Audience is defined by negation only, no competitors are named, and 10+ terms require domain knowledge. The Garden Salon deferral creates a positioning gap with no interim user-surface narrative.
---
<!-- flux-drive:complete -->
