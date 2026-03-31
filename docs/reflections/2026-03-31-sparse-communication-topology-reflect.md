---
artifact_type: reflection
bead: sylveste-rsj.11
date: 2026-03-31
---

# Reflect: Sparse Communication Topology (rsj.11)

## What shipped

Domain-aware sparse topology for the reaction round's peer findings assembly. Agents now see filtered peer findings based on role proximity — full within-domain, summary for adjacent domains, excluded for distant domains. With cross-cluster links and isolation fallback.

**New files (1):**
- `discourse-topology.yaml` — topology mode, adjacency map, visibility levels, fallback config

**Modified files (2):**
- `reaction.md` — Step 2.5.2a (topology-aware peer visibility) with isolation fallback
- `reaction.yaml` — registered topology in discourse section

## Key design decisions

1. **Pre-filter data preserved for fixative.** Both reviews (ARCH-02, SCT-01) converged: topology filtering ONLY affects reaction prompts. The convergence gate, fixative, and synthesis always see the full unfiltered population. This separation is explicitly documented in Step 2.5.2a.

2. **Cross-cluster links for planner↔checker.** The linear adjacency chain (planner→reviewer→editor→checker) created dead-ends that prevented complementary agents (fd-architecture + fd-resilience) from cross-examining each other. Adding planner↔checker summary visibility solves this without fully-connecting the graph.

3. **Isolation fallback.** When only non-adjacent agents are dispatched (e.g., 1 planner + 1 checker), both would get empty peer_findings. The fallback gives them summary-only visibility from all peers rather than a silent no-op.

4. **Convergence gate operates on unfiltered data (intentional).** The gate measures global heterogeneity to decide whether a reaction round adds value. Topology constrains local visibility within that round. These are different questions operating at different levels.

## What went well

- Three discourse beads shipped in one session (rsj.7, rsj.9, rsj.11) — each building on the previous
- The protocol stack model from the brainstorm (rsj.7) held up: Sawyer (monitor) → fixative (correct) → topology (constrain) are orthogonal layers
- Review agent convergence on the fixative/topology interaction (both agents independently found the pre-filter data issue) gives high confidence the fix is correct

## Lessons learned

1. **Capability tier ≠ epistemic proximity.** The role assignments in agent-roles.yaml reflect model capability requirements (opus/sonnet/haiku), not how closely agents' domains relate. Using them directly for topology creates accidental isolation of epistemically complementary agents. Cross-cluster links are the patch; future work should define a separate epistemic proximity graph.

2. **Global metrics + local filtering require explicit data preservation.** When a pipeline has both global-scope operations (convergence gate, fixative) and local-scope operations (topology filtering), the data flow must explicitly preserve the global view. Without the "retain unfiltered" instruction, a naive implementation would let topology filtering corrupt the fixative's input.

3. **Isolation fallback prevents degenerate states.** Any filtering mechanism that can produce empty results needs a fallback. The "summary from all peers" fallback is graceful — it gives isolated agents some visibility without fully-connecting them.

## Discourse Protocol Stack (complete after rsj.7 + rsj.9 + rsj.11)

```
Layer 5: Sawyer Flow Envelope  (rsj.7) — health monitoring
Layer 4: Discourse Fixative    (rsj.9) — corrective injection
Layer 3: Sparse Topology       (rsj.11) — peer visibility
Layer 2: Lorenzen Dialogue     (rsj.7) — move validation
Layer 1: Reaction Round        (rsj.2) — substrate
```

The stack is now 5 layers deep, all composable and independently configurable. Future layers (Yes-And, Conduction, Pressing) build on this foundation.
