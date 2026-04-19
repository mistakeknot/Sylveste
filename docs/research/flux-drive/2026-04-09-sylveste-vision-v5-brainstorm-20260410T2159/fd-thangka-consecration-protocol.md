### Findings Index
- P0 | TC-1 | "PHILOSOPHY.md Additions / Sparse topology" | Proposed philosophy principle contradicts the vision's own flywheel design — sparse topology advocacy vs. fully-connected hub-and-spoke flywheel
- P1 | TC-2 | "PHILOSOPHY.md Additions / Authority ratchet" | Authority flow reversal — implementation mechanism elevated to philosophy principle rather than philosophy generating mechanism
- P1 | TC-3 | "Capability Mesh" | Uneven specificity across mesh cells creates false uniformity — detailed evidence signals for mature subsystems alongside placeholders for immature ones
- P2 | TC-4 | "Key Decision 1 / Key Decision 5" | Vision-to-philosophy authority direction unclear — does the evidence thesis derive from PHILOSOPHY.md or does the vision retroactively amend philosophy?
- P2 | TC-5 | "Resolved Questions" | No drift detection protocol specified — how changes to one document layer propagate to others after v5.0 is written
Verdict: risky

### Summary

A thangka's completion requires independent integrity in each layer — craft, iconography, consecration, custody — and cross-layer consistency verified by separate authorities. The Sylveste document hierarchy (PHILOSOPHY.md, MISSION.md, vision doc) is a composite artifact where each layer must maintain internal coherence while aligning with the others. The brainstorm proposes changes to all three layers simultaneously, creating a risk of cross-layer inconsistency. The most critical finding: the proposed "sparse topology by default" philosophy principle directly contradicts the vision's own flywheel design, which shows all four upstream sources feeding into a single downstream cycle — a maximally connected topology at the aggregation point. The thangka's iconography depicts one deity while the consecration invokes another.

### Issues Found

TC-1. P0: Sparse topology principle contradicts flywheel design. The brainstorm proposes adding "Sparse topology by default" to PHILOSOPHY.md (lines 118-119), citing the Zollman effect research: "fully-connected networks converge faster but on wrong answers." This is offered as a philosophy-level claim about how agents should collaborate. However, the vision's own expanded flywheel (lines 64-69) shows ALL four upstream sources feeding directly into Interspect — a hub-and-spoke topology that is fully connected at the aggregation point:

```
Interweave ----+
Ockham ---------+
Interop --------+--> Interspect --> routing --> cost --> autonomy --> evidence
FluxBench ------+
```

This is the opposite of sparse topology. Every upstream source connects to the same downstream consumer. The philosophy would advocate sparse connections while the vision's central mechanism is maximally connected.

The concrete failure scenario: a reader encounters "sparse topology by default" in PHILOSOPHY.md and then reads the vision's flywheel diagram. The contradiction undermines both documents — the philosophy appears aspirational rather than descriptive, and the flywheel appears to violate the project's own principles. This is the thangka whose iconography contradicts its consecration — it directs attention toward the wrong object.

**Recommended fix**: Either (a) scope the sparse topology principle to agent-to-agent collaboration (interflux reaction rounds, multi-agent review) rather than system architecture, making it clear it does not apply to the evidence aggregation topology, or (b) redesign the flywheel to show sparse connections (e.g., each upstream source feeds into its own evidence stream, with Interspect performing selective sampling rather than full aggregation). Option (a) is the smaller fix and more accurately represents the Zollman effect's domain of applicability.

TC-2. P1: Authority flow reversal in philosophy additions. The brainstorm states that the vision should "amplify the philosophy, not contradict it" (line 51) — establishing that philosophy is the authority source and the vision is derived from it. This is the correct authority direction: the thangka's iconographic canon determines what the painting depicts, not the other way around.

However, the brainstorm then proposes elevating "authority ratchet as mechanism" (line 120) from an Ockham implementation detail to a PHILOSOPHY.md principle. The authority ratchet was designed for a specific subsystem (Ockham's factory governance). Promoting it to a philosophy principle reverses the authority flow: the implementation generates the principle rather than the principle generating the implementation. The consecration ritual is being modified to match the painting rather than the painting conforming to ritual requirements.

The test for a philosophy principle is generality: does it apply beyond its motivating use case? "Authority ratchet as mechanism" is specific to graduated trust systems. PHILOSOPHY.md already has "Evidence earns authority" (principle 2) and the trust ladder (lines 96-107), which are general. The ratchet mechanism is one possible implementation of "evidence earns authority" — it should be in the vision or in Ockham's own docs, not in PHILOSOPHY.md.

**Recommended fix**: Keep "authority ratchet" in the vision document as a mechanism that implements the existing "Evidence earns authority" philosophy principle, rather than elevating it to PHILOSOPHY.md. If the ratchet concept is genuinely general (applies to agent trust, subsystem trust, human-agent trust), articulate that generality explicitly before promotion.

TC-3. P1: Uneven specificity in capability mesh creates false uniformity. The capability mesh (lines 84-98) presents 10 subsystems in a uniform table format, giving the visual impression of equal knowledge depth across all cells. But the actual specificity varies widely:

- **Detailed evidence signals**: Routing ("gate pass rate, model cost ratio"), Review ("finding precision, false positive rate"), Measurement ("attribution chain completeness")
- **Vague evidence signals**: Execution ("task completion rate, model utilization"), Discovery ("promotion rate, source trust scores"), Coordination ("conflict rate, reservation throughput")
- **The gap**: Execution is at "brainstorm/plan phase" (no code shipped) yet has evidence signals defined — these are aspirational, not observed. Discovery has evidence signals that sound precise but may not be instrumented yet.

The thangka's face is painted with master-level detail while the hands are sketched outlines with placeholder gold. The reader assumes equal depth because the table format enforces uniformity. This creates a misleading impression of comprehensive design when the actual knowledge is uneven.

**Recommended fix**: Add a visual marker to the capability mesh distinguishing cells with operational evidence signals (currently instrumented and producing data) from cells with aspirational evidence signals (defined but not yet producing data). Even a simple notation like "(planned)" after aspirational signals would eliminate the false uniformity.

TC-4. P2: Vision-philosophy authority direction ambiguous. The brainstorm simultaneously derives the evidence thesis from PHILOSOPHY.md ("Already established vocabulary. PHILOSOPHY.md's 'Earned Authority' and 'Receipts Close Loops' principles directly express this thesis" — lines 51-52) AND proposes amending PHILOSOPHY.md to match the vision (lines 115-121). This creates an ambiguous authority direction: is the vision derived from the philosophy (top-down), or is the philosophy being retrofitted to match the vision (bottom-up)?

In the thangka tradition, iconometric treatises are the authority source — the painting conforms to the canon, not the other way around. The brainstorm should make the authority direction explicit: either the evidence thesis is already implicit in PHILOSOPHY.md (and the amendments are clarifications of existing principles) or the vision introduces genuinely new principles (and the philosophy amendments are expansions, not clarifications).

**Recommended fix**: In the "PHILOSOPHY.md Additions" section, explicitly state whether each proposed addition is (a) a clarification of an existing principle or (b) a new principle derived from operational learning. This preserves the authority chain.

TC-5. P2: No drift detection protocol for document hierarchy. The brainstorm proposes simultaneous changes to PHILOSOPHY.md, MISSION.md, and the vision document. After v5.0 is written, these three documents must remain consistent as each evolves independently. But the brainstorm does not specify how changes to one layer propagate to the others. If PHILOSOPHY.md is later amended (e.g., a new principle is added), how is the vision checked for consistency? If the vision is updated (e.g., a new subsystem is added to the capability mesh), how is PHILOSOPHY.md checked for coverage?

The project already has interwatch for detecting documentation drift. The brainstorm should note that the three-document hierarchy (PHILOSOPHY.md, MISSION.md, vision doc) should be registered as a drift-detection group where changes to any document trigger a consistency check against the others.

### Improvements

IMP-1. The brainstorm's "Why v5.0, Not v4.1" section (lines 34-35) is effective — it justifies the major version bump. Consider extending this explicitness to the PHILOSOPHY.md additions: "Why a new principle, not a clarification of an existing one."

IMP-2. The three-layer document hierarchy (philosophy > mission > vision) would benefit from an explicit "reading order" note in the vision: "This vision implements PHILOSOPHY.md principles 1-3. Changes to this vision that conflict with PHILOSOPHY.md should trigger a philosophy review."

<!-- flux-drive:complete -->
