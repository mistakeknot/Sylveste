### Findings Index
- P0 | ASC-1 | "Capability Mesh" | No interface control documents between mesh cells — subsystems share state without explicit contracts
- P0 | ASC-2 | "Capability Mesh" | Hidden dependency chains violate independent maturity assumption — Routing depends on Ontology depends on Integration
- P1 | ASC-3 | "Capability Mesh" | Uniform maturity expectations across cells of vastly different criticality — no Design Assurance Level equivalent
- P1 | ASC-4 | "Key Decisions" | No system-level integration validation — per-cell evidence does not prove the composed system works
- P2 | ASC-5 | "Capability Mesh" | Mesh granularity may mask real bottlenecks — 10 cells may be too few for some subsystems and too many for others
Verdict: needs-changes

### Summary

The brainstorm replaces a linear autonomy ladder with a 10-cell capability mesh — a structurally sound move that mirrors aviation's shift from holistic airworthiness to per-ATA-chapter certification. However, the mesh inherits the hardest problem in subsystem certification: cells that claim independence while sharing data, state, or assumptions. In DO-178C and ARP4754A, each subsystem has a formal interface control document (ICD) specifying exactly what crosses the boundary, in what format, at what rate, with what error modes. The brainstorm defines 10 cells with evidence signals but never specifies the interfaces between them. Further, the cells are treated with uniform rigor despite vastly different failure consequences — aviation solves this with Design Assurance Levels (DAL A-E), applying proportional rigor based on the consequence of failure. The mesh needs both: explicit interfaces and criticality-based tiering.

### Issues Found

ASC-1. P0: **No interface control documents between mesh cells.** The capability mesh (Section: Key Decisions, Decision 2) lists 10 subsystems as independently maturing, but multiple cells have implicit data dependencies. Routing (Interspect) consumes outputs from Ontology (Interweave), Governance (Ockham), and Measurement (FluxBench). The flywheel diagram (lines 64-68) explicitly shows Interweave, Ockham, Interop, and FluxBench feeding into Interspect. Yet there is no specification of what data crosses these boundaries, in what format, with what latency requirements, or what happens when an upstream cell produces degraded output. In aviation certification, each ATA chapter boundary has an ICD that specifies: (a) data items exchanged, (b) format and protocol, (c) timing constraints, (d) error handling when the other side is degraded, (e) health monitoring signals. Without ICDs, a failure in Interweave's confidence scores silently degrades Interspect's routing quality — a partition violation. Failure scenario: Interweave ships a schema change to its entity model. Interspect's routing logic breaks because it was consuming the old schema. No interface contract flagged the incompatibility. The "independent maturity" claim masked a hard coupling.

ASC-2. P0: **Hidden dependency chains violate independent maturity.** The brainstorm acknowledges that "the flywheel's input stage is now explicitly multi-source" (line 58) and that "you need ontology, governance, and integration *before* you can route adaptively" (line 71). This creates a dependency DAG: Integration (Interop) and Ontology (Interweave) and Governance (Ockham) → Measurement (FluxBench + Factory Substrate) → Routing (Interspect). Despite this, the mesh claims cells "earn trust independently" (line 98). This is like claiming each ATA chapter earns airworthiness independently while the flight control computer depends on the avionics data bus, which depends on the power distribution system. The independence claim is false for at least 4 of the 10 cells. In aviation, this is handled by defining the "aircraft-level" integration requirement separately from chapter-level requirements. The mesh conflates per-cell certification with system-level airworthiness. Failure scenario: Ontology (Interweave) reaches maturity M3, Governance (Ockham) reaches M3, but Routing (Interspect) is stuck at M1 because its actual dependency on mature ontology and governance data is unrecognized. The "minimum of subsystem maturities" rule blames Routing when the real bottleneck is Integration (the data plumbing between Ontology and Routing).

ASC-3. P1: **Uniform maturity expectations across cells of different criticality.** The capability mesh applies the same evidence bar to all 10 subsystems. In aviation, subsystems are assigned Design Assurance Levels (DAL) from A (catastrophic failure consequence) to E (no safety effect), and the rigor of evidence required is proportional to the DAL. Governance (Ockham) failure is catastrophic — it gates what agents are allowed to do. Coordination (Interlock) failure is inconvenient — agents retry file locks. Yet both require the same evidence standard in the mesh. This wastes effort on low-criticality cells (over-certifying Coordination) and potentially under-protects high-criticality cells (under-certifying Governance). Proposed DAL mapping:

| Cell | Consequence of Failure | Proposed DAL | Evidence Rigor |
|------|----------------------|-------------|----------------|
| Governance (Ockham) | Unauthorized agent actions | DAL A | Maximum — formal verification, mandatory multi-model review |
| Routing (Interspect) | Suboptimal model selection, cost waste | DAL B | High — controlled experiments, canary deployment |
| Persistence (Intercore) | Data loss, state corruption | DAL A | Maximum — transactional guarantees, durability proofs |
| Execution (Hassease) | Wrong code shipped | DAL B | High — test coverage, rollback mechanisms |
| Ontology (Interweave) | Stale/wrong entity relationships | DAL C | Medium — accuracy sampling, freshness checks |
| Integration (Interop) | Sync drift, stale data | DAL C | Medium — reconciliation metrics |
| Review (Interflux) | Missed defects, false positives | DAL C | Medium — precision/recall measurement |
| Measurement (FluxBench) | Inaccurate model scores | DAL C | Medium — benchmark reproducibility |
| Discovery (Interject) | Missed research signals | DAL D | Low — promotion rate monitoring |
| Coordination (Interlock) | File conflicts, retry overhead | DAL D | Low — conflict rate tracking |

Failure scenario: The team spends equal effort hardening Coordination (Interlock) evidence as Governance (Ockham) evidence, diverting resources from the subsystem where failure has catastrophic consequences.

ASC-4. P1: **No system-level integration validation.** The mesh defines per-cell evidence but does not specify how the composed system is validated. In aviation, individual ATA chapter certification is necessary but not sufficient — the aircraft must also pass system-level integration tests (ground tests, flight tests, EMI/EMC testing) that verify properties that only emerge from the composition. The brainstorm mentions "the system's overall autonomy is the minimum of its subsystem maturities" (line 98) but this is an aggregation rule, not an integration test. Key system-level properties that per-cell evidence cannot prove: (a) End-to-end latency from evidence generation to routing adaptation — depends on all cells in the pipeline. (b) Consistency under partial failure — what happens when Ontology is degraded but Routing continues operating on stale data? (c) Evidence pipeline integrity — is evidence tamper-proof from generation through compounding? (d) Cross-cell emergent behaviors — does the interaction between Governance restrictions and Routing optimization produce unexpected dead zones? Failure scenario: Each cell individually demonstrates strong evidence signals, but the composed system exhibits latency spikes because the evidence pipeline from Interweave through Interspect to routing update has an unmonitored end-to-end path with no integration SLA.

ASC-5. P2: **Mesh granularity may mask real bottlenecks.** The 10-cell mesh (Section: Key Decisions, Decision 2) groups capabilities at a specific granularity, but this may not match where real bottlenecks occur. "Review (Interflux)" is one cell that encompasses 49 agents, reaction rounds, cross-AI validation, and synthesis — each of which could independently constrain quality. Meanwhile, "Coordination (Interlock)" is one cell for a relatively simple file-locking mechanism. In aviation, ATA chapters are themselves decomposed into sub-chapters when a chapter is too coarse to certify effectively. The mesh should allow for decomposition of high-complexity cells without requiring all cells to be decomposed. Does Review really earn trust as a monolithic cell, or should "agent finding precision" and "synthesis deduplication quality" and "cross-AI agreement rate" be tracked separately?

### Improvements

IMP-1. Define Interface Control Documents (ICDs) for every cell-to-cell data dependency. Start with the four dependencies shown in the flywheel diagram (Interweave→Interspect, Ockham→Interspect, Interop→Interspect, FluxBench→Interspect). Each ICD should specify: data items, format, timing, error modes, health signals, and versioning contracts.

IMP-2. Assign a criticality tier (DAL equivalent) to each mesh cell based on consequence of failure. High-criticality cells (Governance, Persistence) require more rigorous evidence. Low-criticality cells (Discovery, Coordination) can use lighter evidence standards. This allocates effort proportionally.

IMP-3. Add a "System Integration Evidence" category to the mesh that captures cross-cell properties: end-to-end pipeline latency, partial-failure behavior, evidence integrity, and emergent interaction effects. This is the aircraft-level integration test equivalent.

IMP-4. Allow mesh cells to decompose into sub-cells when a single cell's internal complexity warrants independent tracking. Define a decomposition trigger: when a cell has >5 independent evidence signals or >3 distinct sub-capabilities, evaluate whether sub-cell tracking would improve bottleneck identification.

<!-- flux-drive:complete -->

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 5 (P0: 2, P1: 2, P2: 1)
SUMMARY: The capability mesh makes a sound structural move from linear ladder to multi-cell certification, but lacks interface contracts between cells, hides dependency chains behind an independence claim, and applies uniform rigor across cells of vastly different criticality.
---
