### Findings Index
- P0 | CM-1 | "Key Decisions §2" | Routing↔Measurement hidden dependency invalidates independent maturation claim — Routing cannot improve without Measurement data, but Measurement is listed as ~80% and blocked
- P1 | CM-2 | "Key Decisions §2" | At least 4 of 10 evidence signals are hypothetical — not currently collected by any system
- P1 | CM-3 | "Key Decisions §2" | Execution cell is at "brainstorm/plan phase" — including it at the same granularity as shipped cells inflates the mesh without adding signal
- P1 | CM-4 | "Key Decisions §2" | No summarization mechanism — stakeholders cannot answer "how mature is the platform?" from the mesh
- P2 | CM-5 | "Key Decisions §2" | Missing cells for observability/logging, developer experience, and security — all needed for the evidence thesis
- P2 | CM-6 | "Key Decisions §2" | Current state descriptions mix aspiration with implementation across inconsistent granularity levels
Verdict: needs-changes

### Summary

The capability mesh is a significant improvement over the L0-L4 ladder for representing actual system maturity. However, the "independent maturation" claim has a P0 structural flaw: Routing depends on Measurement data that is not yet complete, creating a hidden dependency chain. Four of ten evidence signals are hypothetical (not currently collected). The mesh also lacks a summarization mechanism, making it accurate but not communicable to stakeholders.

### Issues Found

CM-1. P0: Routing and Measurement have a hidden dependency that invalidates the independent maturation claim. The mesh states: Routing's evidence signal is "gate pass rate, model cost ratio," and Measurement's current state is "~80% implemented (3,515 LOC Go)." But adaptive routing (Interspect Phase 2, the flywheel's engine) requires measurement data to function. Routing cannot mature from "static + complexity-aware" to evidence-based without Measurement reaching completion. This means Routing maturity is silently capped by Measurement maturity — they are NOT independently maturable. Similarly, Governance (Ockham) requires evidence from Measurement to gate authority ratchets. The dependency chain is: Measurement → Routing → Governance. Three of ten cells are coupled, and the coupling is structural, not incidental. The mesh should either acknowledge these dependencies (perhaps with directed edges between cells) or redefine "independent" to mean "independently assessable" rather than "independently advanceable."

CM-2. P1: Evidence signal measurability audit across all 10 cells reveals at least 4 hypothetical metrics.

| Cell | Evidence Signal | Currently Measured? |
|------|----------------|-------------------|
| Routing | Gate pass rate, model cost ratio | Partially — gate pass rate yes, model cost ratio requires interstat |
| Governance | Authority ratchet events, INFORM signals | No — Ockham's authority ratchet is not yet emitting events |
| Ontology | Query hit rate, confidence scores | No — Interweave F1-F3 shipped but query metrics not instrumented |
| Integration | Conflict resolution rate, sync latency | Partially — Interop Phase 1 shipped but metrics pipeline not confirmed |
| Review | Finding precision, false positive rate | Partially — finding precision requires act-on-finding tracking (not fully wired) |
| Measurement | Attribution chain completeness | No — this IS the measurement system measuring itself, a self-referential metric |
| Discovery | Promotion rate, source trust scores | Yes — Interject ships these |
| Execution | Task completion rate, model utilization | No — Hassease is at brainstorm/plan phase |
| Persistence | Event integrity, query latency | Yes — Intercore ships these |
| Coordination | Conflict rate, reservation throughput | Yes — Interlock ships these |

At minimum 4 signals (Governance, Ontology, Measurement, Execution) are not currently collected. The mesh presents them as if they are evidence signals rather than aspirational metrics. A vision document can include aspirational signals, but it should distinguish them from signals that are measured today.

CM-3. P1: The Execution cell (Hassease + Codex) is at "brainstorm/plan phase" — the least mature state of any cell. Including it alongside cells with shipped implementations (Persistence: 8/10 epics, Discovery: shipped/kernel-integrated) creates a false equivalence. A 10-cell mesh where one cell has no implementation is effectively a 9-cell mesh plus a placeholder. Either move Execution to a "Planned" section or mark it visually distinct. The weakest-link rule means this single cell constrains the entire system's stated autonomy, which may not be the intended signal.

CM-4. P1: The mesh has no aggregation or summarization mechanism. A stakeholder asking "how mature is the platform?" must read 10 cells, understand 10 different evidence signals, and mentally compute a minimum. The L0-L4 ladder's strength was communicability: "We're at L2." The mesh sacrifices this for accuracy. The document acknowledges this tradeoff in Resolved Question 3 ("accuracy over communicability at the vision level") but does not offer a summary mechanism. Even a simple heatmap (red/yellow/green per cell) or a single-number "mesh maturity score" (min, median, or weighted) would close this gap.

CM-5. P2: Three capabilities needed for the evidence thesis lack mesh cells. (1) **Observability/logging**: the evidence thesis requires evidence to be observable, but there is no cell for the system's ability to observe its own behavior (distinct from Measurement, which is about attribution). (2) **Developer experience**: the mesh tracks platform capabilities but not the human interface to those capabilities — if developer experience is poor, evidence quality degrades because humans misinterpret or ignore it. (3) **Security**: the brainstorm does not mention security as a capability dimension, but PHILOSOPHY.md has extensive security content (capability-based auth, deny-by-default, Gridfire tokens). Either security is a cross-cutting concern that doesn't need a cell (defensible) or it's a capability dimension that can mature independently (also defensible), but the choice should be explicit.

CM-6. P2: Current state descriptions use inconsistent granularity. "Static + complexity-aware" (Routing) is an implementation-level description. "F1-F7 shipped" (Governance) is a feature-tracking description. "~80% implemented (3,515 LOC Go)" (Measurement) is a progress-estimation description. "Shipped, kernel-integrated" (Discovery) is a deployment-status description. "Brainstorm/plan phase" (Execution) is a lifecycle-stage description. The mesh would be more useful if all current states used the same vocabulary — either lifecycle stages (planned/in-progress/shipped/mature) or capability levels (none/basic/advanced/adaptive).

### Improvements

IMP-1. Add a dependency graph overlay to the mesh showing which cells depend on which. Even a simple notation (Routing ← Measurement, Governance ← Measurement) would prevent the "independent maturation" claim from misleading.

IMP-2. Distinguish measured vs. aspirational evidence signals. A simple annotation (e.g., asterisk for "not yet collected") preserves accuracy while being honest about current instrumentation.

IMP-3. Add a summarization mechanism — either a composite maturity score or a heatmap with red/yellow/green. This bridges the communicability gap from L0-L4 without reverting to a false linear model.

IMP-4. Standardize current state descriptions to use a consistent vocabulary (e.g., lifecycle stages: planned → building → shipped → measured → mature).

--- VERDICT ---
STATUS: fail
FILES: 0 changed
FINDINGS: 6 (P0: 1, P1: 3, P2: 2)
SUMMARY: The capability mesh has a P0 hidden dependency chain (Measurement→Routing→Governance) that invalidates the independent maturation claim. Four of ten evidence signals are hypothetical. No summarization mechanism exists.
---
<!-- flux-drive:complete -->
