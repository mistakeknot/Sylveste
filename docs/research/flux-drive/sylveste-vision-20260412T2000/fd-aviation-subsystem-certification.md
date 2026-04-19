### Findings Index
- P1 | AV-1 | "Capability Mesh" | Interface Evidence table is a strong start but covers only 5 of 45 possible cell-pair interfaces — no methodology for prioritizing which interfaces need monitoring
- P1 | AV-2 | "Capability Mesh" | Dependency DAG declares independence for 5 root cells but does not specify fault containment — failure propagation paths between "independent" cells are unanalyzed
- P2 | AV-3 | "Capability Mesh" | No system-level integration validation — individual cell maturity is necessary but not sufficient; composed behavior requires its own evidence
- P2 | AV-4 | "Capability Mesh" | Criticality tiers lack formal assignment criteria — "inspired by aviation DALs" but no systematic failure consequence analysis
- P2 | AV-5 | "Trust Architecture" | Trust transfer for subsystem replacement lacks interface re-certification scope — which neighboring cells must re-test?
Verdict: needs-changes

### Summary

The v5.0 document makes significant progress from v4.0. The dependency DAG (lines 174-180) is a genuine structural improvement — it explicitly maps which cells can mature independently and which have upstream dependencies. The Interface Evidence table (lines 185-193) is an excellent addition that acknowledges cross-subsystem interfaces as first-class concerns. From an aviation certification perspective, these are analogous to Interface Control Documents (ICDs) and the certification basis, respectively.

However, the Interface Evidence table covers only 5 interfaces out of 45 possible cell pairs (10 choose 2). The document does not specify how these 5 were selected or whether the remaining 40 were analyzed and found non-critical. In DO-178C, every interface between partitions is either (a) explicitly characterized or (b) explicitly declared as "no interface exists." The undeclared interfaces are the certification risk.

### Issues Found

AV-1. P1: Interface Evidence table coverage gap (Capability Mesh, lines 185-193)
The table lists 5 monitored interfaces: Ontology/Governance, Routing/Measurement, Integration/Ontology, Review/Routing, Measurement/Governance. With 10 mesh cells, there are 45 possible pairwise interfaces. The document does not explain:
(a) How these 5 were selected (risk-based? ad hoc? exhaustive analysis reduced to 5?)
(b) Whether the remaining 40 were analyzed and found non-critical
(c) What happens when a NEW interface emerges (e.g., Execution starts consuming Ontology data)

In aviation, ICD coverage is a certification artifact — you must demonstrate that all interfaces are either tested or formally declared as non-existent. Missing interfaces are the #1 source of integration failures in certified systems.
Failure scenario: Persistence/Review interface (e.g., review findings written to kernel events) degrades silently because it was never monitored. Review findings appear to land but are actually lost due to a schema change in Persistence.
Fix: Add a sentence stating the selection methodology (e.g., "interfaces where data crosses from one cell's evidence domain to another's decision domain") and explicitly declare the remaining interfaces as "no monitoring required — rationale: [X]" or "deferred to M2 analysis."

AV-2. P1: Dependency DAG independence claim lacks fault containment analysis (Capability Mesh, lines 174-180)
The DAG declares 5 "independent roots": Persistence, Coordination, Discovery, Review, Execution. "Independent" means they can mature without upstream dependencies. But independence for maturity progression is different from independence for fault containment. Can a failure in Persistence silently affect Review's evidence signals? The document doesn't analyze this.
In aviation, partition testing verifies that a fault in one partition cannot corrupt another. The dependency DAG addresses maturity ordering, not fault propagation.
Failure scenario: Persistence has a subtle SQLite WAL corruption that causes intermittent lost events. Review continues to operate (it's "independent") but its finding precision metric degrades because some findings are lost in transit. Review is demoted from M2 to M1 — but the root cause is in Persistence, not Review. The weakest-link model correctly blocks system advancement, but the wrong cell is blamed.
Fix: Add a "fault propagation analysis" companion to the dependency DAG that maps how failure in each cell could affect evidence signals in other cells, even "independent" ones. This is the distinction between maturity dependency (ordering) and operational dependency (runtime coupling).

AV-3. P2: No system-level integration validation (Capability Mesh, entire section)
The mesh tracks per-cell maturity and 5 cross-cell interfaces. But it does not specify system-level integration testing — validation that the COMPOSED system exhibits the desired emergent properties (e.g., "the flywheel actually accelerates" or "trust decisions are consistent across cells"). In aviation, airworthiness is not the sum of subsystem compliance — it requires integrated system-level testing (DO-178C Table A-7).
The Interface Evidence table is a step in this direction but monitors pairwise interactions, not emergent system behavior.
Fix: Add a "system integration evidence" category that tracks properties only observable at system level — e.g., "end-to-end evidence pipeline latency" (from sprint evidence production to routing adjustment), "cross-cell maturity consistency" (no cell more than 2 levels ahead of dependent cells).

AV-4. P2: Criticality tiers lack formal assignment criteria (Capability Mesh, lines 168)
"Criticality tiers (inspired by aviation Design Assurance Levels): subsystems with higher failure consequences require more rigorous evidence at each maturity level." The document assigns: Governance=Critical, Persistence/Integration/Measurement/Routing=High, Coordination/Discovery/Ontology/Review=Medium, Execution=Medium.
But no failure consequence analysis is provided to justify these assignments. Why is Review "Medium" when review failure (false negatives letting bugs through) has direct quality consequences? In DO-178C, DAL assignment follows a rigorous Functional Hazard Assessment (FHA).
Fix: For each cell, state the worst-case failure consequence in one sentence. This makes the criticality assignment auditable and revisable as the system evolves.

AV-5. P2: Trust transfer lacks interface re-certification scope (Trust Architecture, lines 224-225)
"All interfaces to neighboring mesh cells are re-tested." Which interfaces? The Interface Evidence table lists 5 monitored interfaces, but a replaced subsystem may participate in additional runtime interfaces not in the table. This is the same coverage gap as AV-1, but specifically during the high-risk trust transfer period.
Fix: Cross-reference the Interface Evidence table and specify that trust transfer re-tests all interfaces where the replaced subsystem appears, including any not yet in the monitoring table.

### Improvements

IMP-AV-1. The 10-cell granularity appears appropriate for the current system scale. However, consider a "cell split" trigger — when a cell's internal complexity exceeds a threshold (e.g., multiple independent evidence signals that don't covary), it should be split. Aviation ATA chapters have sub-chapters for exactly this reason.

IMP-AV-2. The document's use of "provisional" for the mesh (line 194) is honest and appropriate. Recommend adding a specific review cadence (e.g., "mesh structure reviewed at each M-level advancement of any cell").

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 5 (P0: 0, P1: 2, P2: 3)
SUMMARY: Dependency DAG and Interface Evidence table are strong additions, but interface coverage is partial (5/45 pairs), fault containment is unanalyzed, and criticality assignments lack formal justification.
---
<!-- flux-drive:complete -->
