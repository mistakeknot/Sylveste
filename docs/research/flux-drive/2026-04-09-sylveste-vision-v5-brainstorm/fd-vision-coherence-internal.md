### Findings Index

- P1 | VCI-1 | "Key Decisions" | Three-axis framing rejected in Decision 1 but still present implicitly in capability mesh evidence signals
- P1 | VCI-2 | "Resolved Questions" | Measurement hardening resolution defers convergence without specifying when or how
- P1 | VCI-3 | "Capability Mesh" | Capability mesh subsystem list does not match flywheel diagram participants
- P2 | VCI-4 | "Why v5.0" | Version delta claim of 5 new epics includes Hassease which is brainstorm-phase, inflating the magnitude argument
- P2 | VCI-5 | "Resolved Questions" | Khouri marked out of scope but scenario planning capability is implicit in Ockham's governance description
- P2 | VCI-6 | "What's Next" | Priority numbering (P0/P1) does not reference the evidence thesis as justification

Verdict: needs-changes

---

## Detailed Findings

### VCI-1: Three-axis framing survives in capability mesh evidence signals [P1]

**Section:** Key Decisions, Decision 1 + Decision 2

Decision 1 explicitly rejects the three-axis framing (autonomy/quality/efficiency) in favor of the evidence thesis. But the capability mesh in Decision 2 retains evidence signals that map directly to the old three axes without acknowledgment:

- "Gate pass rate" = autonomy signal
- "Finding precision, false positive rate" = quality signal
- "Model cost ratio" = efficiency signal

The document says the three axes "become outcomes of the evidence loop, not the framing itself" but does not show how the evidence signals in the mesh relate to the evidence thesis rather than just relabeling the old axes. A reader would be justified in reading the capability mesh as the three-axis framing wearing a different hat.

**Recommendation:** Either explicitly map each evidence signal to the compounding evidence thesis (showing how it feeds the flywheel, not just measures an axis), or acknowledge that the three-axis framing persists at the measurement level and explain why that's acceptable.

### VCI-2: Measurement hardening resolution is a deferral, not a resolution [P1]

**Section:** Resolved Questions, #1

The resolved question says "both paths, converge later" regarding Factory Substrate and FluxBench. But "converge later" is not a resolution — it's a deferral. The question being resolved is: does the vision need to pick one measurement approach? The answer given is "no, name both." But the actual open question — when do they converge, what does convergence look like, who decides — remains unanswered.

For a vision document, this may be acceptable (vision-level, not implementation-level). But marking it "resolved" when it's actually "deferred with rationale" is misleading. The document's credibility depends on resolved questions actually being closed.

**Recommendation:** Rename to "deferred with rationale" or specify the convergence criterion (e.g., "converge when Interspect reads both" — which is already stated but not framed as the resolution criterion).

### VCI-3: Capability mesh does not align with flywheel diagram [P1]

**Section:** Key Decisions, Decision 2 + flywheel diagram

The flywheel diagram names 4 upstream sources: Interweave, Ockham, Interop, FluxBench. The capability mesh has 10 cells. The mismatch is unexplained:

- Where do the other 6 mesh cells (Discovery, Execution, Persistence, Coordination, Review, Routing) sit in the flywheel?
- Is the flywheel a subset of the mesh, or a different view of the same system?
- Do the non-flywheel mesh cells produce evidence that feeds the flywheel, or are they outside the evidence loop?

The document presents both the flywheel and the mesh without reconciling them. A reader cannot determine whether the flywheel operates on 4 subsystems while the mesh tracks 10, or whether the mesh is meant to replace the flywheel as the primary model.

**Recommendation:** Add a paragraph explicitly relating the mesh to the flywheel. Likely: the 4 upstream flywheel sources are a subset of the 10 mesh cells, and the other 6 cells participate in the flywheel's downstream cycle (routing, evidence production) rather than as upstream evidence sources.

### VCI-4: Version delta magnitude inflated by brainstorm-phase items [P2]

**Section:** Why v5.0, Not v4.1

The argument for a major version bump cites "5 new P0/P1 epics not mentioned in the vision": Interop, Ockham, Interweave, Hassease, and Auraken→Skaffen. But Hassease is at "brainstorm/plan phase" (per the capability mesh), not an active epic. Counting a brainstorm as a "new P0/P1 epic" alongside shipped systems inflates the magnitude argument. Four genuinely new epics is still a strong case for v5.0, but the claim should be accurate.

### VCI-5: Khouri out-of-scope but governance implies scenario planning [P2]

**Section:** Resolved Questions, #4

Khouri (scenario planning) is marked out of scope, but Ockham's governance description in the capability mesh includes "intent→weights" and decision gating, which are scenario planning adjacent. The boundary between governance and scenario planning is not drawn. A reader might wonder why Ockham's intent interpretation isn't Khouri under a different name.

### VCI-6: Priority assignments lack evidence-thesis justification [P2]

**Section:** What's Next

The 6 items in "What's Next" are assigned P0/P1 but the justification is implicit. In a document whose thesis is "evidence earns trust," the priority assignments should themselves reference evidence. Why is Interop P0? Because the flywheel requires integration evidence before routing can be adaptive. This chain should be made explicit, not left to inference.
