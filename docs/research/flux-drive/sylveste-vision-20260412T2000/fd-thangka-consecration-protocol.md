### Findings Index
- P2 | TC-1 | "Design Principles / Principle 8" | Sparse topology principle scoped correctly to multi-agent collaboration; flywheel contradiction resolved
- P1 | TC-2 | "Capability Mesh / Current Mesh State" | Evidence Signal specificity uneven across subsystems — detailed for mature, vague for immature
- P2 | TC-3 | "Trust Architecture" | Authority direction consistent: PHILOSOPHY -> VISION -> mechanism, but one reverse-flow risk remains
Verdict: needs-changes

### Summary

The v5.0 vision doc has resolved the first review's P0 (sparse topology contradicting flywheel topology). The sparse topology principle in PHILOSOPHY.md (line 127) is scoped to "multi-agent collaboration" and "multi-agent review and discourse," not to system-level evidence architecture. The flywheel's hub topology (all sources feeding Interspect) operates at a different architectural level than agent-to-agent collaboration topology. These are not contradictions — they describe different concerns. Cross-document authority direction is largely consistent: PHILOSOPHY.md defines principles, the vision doc applies them as mechanisms. The vision's Design Principle 8 ("Evidence is independently verified") derives from PHILOSOPHY.md's "Evidence earns authority" and "Receipts Close Loops" principles, maintaining correct authority flow. One P1 remains: the Evidence Signal column in the capability mesh presents all subsystems at the same specificity level despite vastly different levels of operational understanding.

### Issues Found

TC-1. P2: Sparse topology / flywheel topology resolved — The first review flagged a P0 contradiction between PHILOSOPHY.md's sparse topology principle and the flywheel's fully-connected topology. Examination shows this is resolved: PHILOSOPHY.md line 127 scopes sparse topology to "multi-agent collaboration" and "multi-agent review and discourse" — it is an epistemic principle about agent-to-agent information sharing (preventing consensus collapse via the Zollman effect). The flywheel's topology (multiple evidence sources feeding one aggregation point) is a data architecture decision, not an agent collaboration topology. The thangka's iconography (sparse topology for agents) is consistent with its ritual purpose (hub topology for evidence). P2 because the resolution is implicit in the scoping language — an explicit note in the vision doc connecting the two would prevent future confusion, but the current state is not contradictory.

TC-2. P1: Evidence Signal specificity is uneven — The capability mesh (lines 153-166) lists Evidence Signals for all 10 subsystems, but the specificity varies dramatically:
- Routing: "Gate pass rate, model cost ratio" — measurable, concrete, operationally tested
- Persistence: "Event integrity, query latency" — measurable, concrete
- Governance: "Authority events, INFORM signals" — specific to implementation, testable
- Execution: "Task completion rate, model utilization" — generic, could apply to any system
- Ontology: "Query hit rate, confidence scores" — reasonable but not yet operationally validated

The thangka's proportional grid requires all elements in correct proportion. A mesh that presents Execution's aspirational signals at the same visual weight as Routing's operational signals creates false uniformity. The reader cannot distinguish which evidence signals are based on operational data (30+ days of real metrics) from which are prospective definitions. This is P1 because it undermines the mesh's function as a readiness assessment tool — a reader using this mesh to make decisions about where to invest effort may under-invest in subsystems whose evidence signals are placeholders.

TC-3. P2: Authority direction mostly correct with one subtle reverse-flow risk — The vision doc's trust architecture (lines 198-225) introduces the 4-phase trust lifecycle (Earn/Compound/Epoch/Demote) and the capability mesh maturity scale (M0-M4). These are mechanisms that instantiate PHILOSOPHY.md's principle "Evidence earns authority" (line 2). The authority flow is correct: principle -> mechanism. However, the vision doc's Design Principle 8 ("Evidence is independently verified," line 283) is new — it does not appear verbatim in PHILOSOPHY.md. PHILOSOPHY.md establishes independent verification implicitly through "Disagreement" (line 79: "Disagreement between models is the highest-value signal") and "Governance" (line 115: "multiple independent evaluation authorities"). The vision doc elevates implicit philosophy into an explicit principle. This is appropriate — the vision can make implicit principles explicit — but there is a subtle risk: if the vision doc's Principle 8 later diverges from PHILOSOPHY.md's implicit stance, the authority flow reverses (vision constraining philosophy instead of philosophy constraining vision). P2 because the current state is consistent; the risk is future drift, which interwatch's doc-drift detection should catch.

Cross-document consistency check (PHILOSOPHY.md / MISSION.md / Vision):
- MISSION.md (6 lines) states "Ontology to track what's known, governance to gate what's allowed, integration to verify across boundaries, measurement to prove what worked." This matches the vision's four upstream evidence sources exactly.
- PHILOSOPHY.md's three principles (evidence -> authority -> scoped composition) are all reflected in the vision's structure.
- PHILOSOPHY.md's "Graduated authority as mechanism" (line 109) matches the vision's maturity scale verbatim.
- PHILOSOPHY.md's OODARC lens (lines 28-42) is not referenced in the vision doc. This is intentional — the vision doc describes "what" while OODARC describes "how the learning loop operates." No inconsistency.

### Improvements

IMP-1. Add a visual marker to the Evidence Signal column in the capability mesh distinguishing operational signals (based on real data) from prospective signals (defined but not yet validated). Options: italics for prospective, or an asterisk with footnote "* Evidence signal defined but not yet operationally validated."

IMP-2. Consider adding Design Principle 8 ("Evidence is independently verified") to PHILOSOPHY.md as an explicit sub-principle under "Receipts Close Loops" — this would anchor the vision's principle in the philosophy doc and prevent future authority-direction drift.

IMP-3. Add a note after line 133 (upstream dependency ordering) explicitly connecting the 4-phase sequencing to the "sparse topology by default" principle — the phased approach is actually an instance of sparse information flow (subsystems connect to the flywheel only when their evidence reaches maturity, not all at once).

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 3 (P0: 0, P1: 1, P2: 2)
SUMMARY: Sparse topology / flywheel topology contradiction resolved through correct scoping. Cross-document authority direction is consistent. One P1: Evidence Signal specificity in the capability mesh is uneven, creating false uniformity between operational and aspirational signals.
---
<!-- flux-drive:complete -->
