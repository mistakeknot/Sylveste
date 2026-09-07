### Findings Index
- P2 | ARCH-1 | "The Stack" | Layer diagram clean but cross-cutting evidence infrastructure has unclear layer placement
- P2 | ARCH-2 | "Design Principles / Principle 4" | Standalone independence claim needs reconciliation with evidence infrastructure dependencies
- P1 | ARCH-3 | "Capability Mesh / Dependency DAG" | Dependency DAG presents two independent root clusters but Persistence is shared, creating hidden coupling
Verdict: needs-changes

### Summary

The architectural structure of the v5.0 vision doc is sound at the macro level: three layers (kernel, OS, apps) with clear survival properties, cross-cutting evidence infrastructure, and explicit design principles governing boundaries. The stack diagram (lines 43-74) is well-organized and the survival properties are clear. The 8 design principles form a coherent set. However, two architectural concerns emerge: (1) the evidence infrastructure is described as "cross-cutting" but its relationship to the layer model is ambiguous — is it above the kernel, alongside the OS, or truly orthogonal? (2) The dependency DAG's "independent roots" (line 175: Persistence, Coordination, Discovery, Review, Execution) share a hidden coupling through Persistence — almost all subsystems ultimately depend on the kernel's SQLite database, which means Persistence is less an "independent root" and more a shared foundation that everything depends on.

### Issues Found

ARCH-1. P2: Cross-cutting evidence infrastructure layer placement — The stack diagram (lines 43-74) places the evidence infrastructure as "Cross-cutting" below the three layers. The description says these systems "feed the flywheel" and are "preconditions for adaptive improvement." However, some of these systems (Interspect, Ockham) modify OS-level configuration (routing overrides, dispatch weights), while others (Interweave, Interop) synchronize with external systems. This means the evidence infrastructure operates across all three layers — it reads from L1 (kernel events), modifies L2 (routing, gates), and could affect L3 (app behavior). The current "cross-cutting" designation is architecturally accurate but could be clearer about which layer boundaries each evidence system crosses. P2 because the architectural intent is clear; the layer-crossing semantics could be more explicit.

ARCH-2. P2: Standalone independence vs. evidence infrastructure — Design Principle 4 (lines 266-267) states "Any capability driver works standalone. Install interflux for multi-agent review, tldr-swinton for code context, or interlock for file coordination. No Clavain, no Intercore, no rest of the stack required." The evidence infrastructure sections imply that subsystem maturity requires kernel integration (evidence signals come from kernel events). These are not contradictory — Principle 4 applies to capability drivers while evidence infrastructure is a separate concern — but the vision doc should make this distinction explicit: drivers degrade gracefully to standalone mode, but evidence-based maturity advancement requires kernel integration. P2 because the distinction is architecturally correct; the presentation conflates "usable standalone" with "fully capable standalone."

ARCH-3. P1: Hidden coupling through Persistence — The dependency DAG (line 175) lists Persistence, Coordination, Discovery, Review, and Execution as "independent roots." However, Coordination depends on Persistence (file locks require database state), Discovery depends on Persistence (discovery pipeline feeds kernel events), and Review's evidence signal (finding precision) is stored via Persistence. The only truly independent root is Execution (which is at M0 and has no implementation). The architecture is actually a star topology with Persistence at the center, not five independent roots. This matters because if Persistence regresses, it cascades to all dependent subsystems — a scenario the dependency DAG does not surface. P1 because the dependency DAG should accurately represent the actual coupling topology to support the weakest-link assessment.

### Improvements

IMP-1. Add a brief note to the stack diagram (after line 74) specifying which layer boundaries each evidence infrastructure system crosses (e.g., "Interspect: reads L1, writes L2. Interop: reads L2, writes external.").

IMP-2. Add a sentence to Design Principle 4 distinguishing standalone usability (works without kernel) from evidence-integrated capability (requires kernel for maturity advancement).

IMP-3. Revise the dependency DAG to show Persistence as a shared foundation rather than an independent root, or add a note clarifying that all roots except Execution have an implicit dependency on Persistence (the kernel).

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 3 (P0: 0, P1: 1, P2: 2)
SUMMARY: Layer architecture and design principles are sound. Evidence infrastructure correctly designated as cross-cutting. One P1: the dependency DAG's "independent roots" share hidden coupling through Persistence, which should be surfaced.
---
<!-- flux-drive:complete -->
