### Findings Index
- P1 | DEC-1 | "Key Decision 2 / Capability Mesh" | Premature commitment to 10-cell mesh — mesh granularity locked in before subsystems have demonstrated operational maturity
- P1 | DEC-2 | "Why This Approach" | Alternatives analysis uses non-comparable rejection criteria — framing effect in thesis selection
- P2 | DEC-3 | "Key Decision 3 / Garden Salon to Horizons" | Moving Garden Salon to Horizons dissolves the problem but does not address the dependency chain that blocks it
- P2 | DEC-4 | "Resolved Questions" | Four out-of-scope deferrals in a vision document may indicate scope avoidance rather than healthy scoping
- P3 | DEC-5 | "The Pitch" | The pitch is an explore/exploit imbalance — heavy exploit of existing vocabulary, minimal exploration of alternative framings
Verdict: needs-changes

### Summary

The brainstorm makes several structural decisions (10-cell capability mesh, evidence thesis selection, Horizons deferral) with insufficient examination of their decision process. The three-row alternatives analysis uses non-comparable rejection criteria, the mesh granularity is committed before subsystems demonstrate operational maturity, and multiple scope deferrals may collectively represent a pattern of avoiding difficult decisions rather than making clean cuts.

### Issues Found

DEC-1. P1: Premature commitment to 10-cell mesh granularity. The capability mesh (lines 84-98) commits to a specific 10-cell structure that includes subsystems at wildly different maturity levels: Routing (operational, static + complexity-aware) alongside Execution (brainstorm/plan phase — no code shipped). Resolved Question 3 (line 137) explicitly states the mesh was "expanded to match actual systems" and favors "accuracy over communicability."

But committing to a 10-cell structure now creates a premature framework. The mesh will appear in the vision document as a canonical reference, and future work will orient toward filling mesh cells rather than building what the system actually needs. Subsystems that exist only as brainstorm concepts (Execution, Coordination) will receive mesh cells equal in visual weight to operational subsystems (Routing, Persistence), creating false equivalence.

The decision quality question: what would make this 10-cell structure look wrong in 6 months? Answer: if two subsystems merge (e.g., Measurement absorbs aspects of Review), the mesh must be restructured. If a new subsystem emerges (not currently anticipated), it must be shoehorned into an existing cell or the mesh must grow. The mesh is a model — it should be held loosely.

**Recommended fix**: Add a note that the mesh structure is explicitly provisional: "This mesh reflects current understanding. Cells may merge, split, or be added as subsystems demonstrate operational reality." This prevents the mesh from ossifying into a permanent taxonomy.

DEC-2. P1: Alternatives analysis has non-comparable rejection criteria. The three-approach comparison (lines 43-49) rejects alternatives for different reasons:
- Approach A: "'Infrastructure' undersells the experience layer; too platform-builder-specific"
- Approach B: "Anthropomorphic; risks sounding like vaporware"
- Approach C (selected): "Selected — philosophically coherent, aligns with PHILOSOPHY.md, concrete"

These are not comparable criteria. A is rejected for audience fit, B is rejected for tone, and C is selected for philosophical alignment. A fair comparison would evaluate all three against the same criteria. Does A align with PHILOSOPHY.md? (Yes — "Infrastructure unlocks autonomy" is core bet #1.) Is B concrete? (Potentially — "self-knowledge" could mean specific instrumentation.) Is C audience-appropriate? (Unknown — "compounding evidence" may be just as niche as "infrastructure that learns.")

The framing effect: by using different rejection criteria for each alternative, the brainstorm avoids directly comparing them on the same dimensions. The selected approach may indeed be the best choice, but the decision process does not demonstrate it.

**Recommended fix**: Evaluate all three approaches against the same 3-4 criteria (philosophical alignment, audience accessibility, concreteness, scope coverage) and show why C wins on the most important dimensions.

DEC-3. P2: Garden Salon deferral dissolves the problem without addressing it. Key Decision 3 (lines 100-102) moves Garden Salon from "What's Next" to a "Horizons" section because it "depends on Interop (data), Interweave (ontology), and Ockham (governance) reaching sufficient maturity." This is presented as making the "dependency chain explicit." But moving an item to Horizons does not address the dependency chain — it removes the item from active consideration while the dependencies remain unresolved.

The decision quality question: is this a genuine scope cut (Garden Salon is not needed for v5.0's thesis) or is it avoidance (Garden Salon is difficult to plan and the dependencies are convenient justification)? If the evidence thesis is truly the through-line, and Garden Salon is the experience layer where humans and agents collaborate, then Garden Salon is arguably where evidence becomes visible to humans — which is central to "earned trust."

**Recommended fix**: If Garden Salon is deferred, add a sentence explaining what the evidence thesis looks like WITHOUT Garden Salon: "In the near term, evidence is visible through CLI tools (bd, ic, interspect) and developer workflows. Garden Salon will eventually make evidence visible to non-developer stakeholders."

DEC-4. P2: Pattern of scope deferrals. The brainstorm defers four items to "out of scope": Khouri scenario planning (line 139), two-brand operationalization (line 141), Intercom as execution plane (line 143), and Garden Salon (line 100). Each individual deferral is reasonable. Collectively, they may indicate scope avoidance — the brainstorm addresses the subsystems it is most comfortable with (infrastructure, measurement, ontology) and defers the ones that involve user experience, multi-brand complexity, and scenario planning.

The pattern is not alarming but worth noting: a vision document that defers all non-infrastructure concerns may produce a vision that is architecturally complete but experientially hollow.

DEC-5. P3: Explore/exploit imbalance in thesis selection. The brainstorm's thesis selection (lines 43-55) heavily exploits existing vocabulary: "compounding evidence" already appears in MISSION.md, "Earned Authority" and "Receipts Close Loops" are existing PHILOSOPHY.md principles. This is presented as a strength ("Already established vocabulary"). But it means the v5.0 vision is a synthesis of existing language rather than an exploration of genuinely new framings. The question is whether the existing vocabulary is sufficient for the expanded scope (5 new epics, ontology, governance, integration) or whether the expanded scope calls for genuinely new conceptual framing.

### Improvements

IMP-1. The "Resolved Questions" section is a decision register — it documents what was decided and why. This is excellent decision hygiene. Consider adding a "Reversibility" column: which decisions can be easily changed later and which are costly to reverse?

IMP-2. The alternatives analysis would be stronger as a decision matrix with consistent criteria across all options, even if the outcome is the same.

<!-- flux-drive:complete -->
