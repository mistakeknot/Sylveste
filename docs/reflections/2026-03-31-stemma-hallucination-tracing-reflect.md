---
artifact_type: reflection
bead: sylveste-rsj.10
stage: reflect
---

# Reflect: Stemma Hallucination Tracing (rsj.10)

## What worked
- Jaccard similarity on evidence_sources is a clean, deterministic heuristic — no LLM judgment needed for grouping
- Placing stemma analysis at Step 6.3 (after dedup, before QDAIF) means it operates on already-merged findings, avoiding duplicate work
- The corrected_convergence field preserves the original convergence for audit while providing the adjusted number for decision-making

## Design choices
- Used transitive closure for stemma groups rather than strict pairwise — if A↔B and B↔C both exceed threshold, all three should be in one group since the shared context propagates transitively
- Set the Jaccard threshold at 0.5 (majority overlap) — too low would create false groups, too high would miss partial overlaps
- Kept stemma analysis as annotation-only (no severity changes) to maintain the principle that only the original finding author sets severity

## Three-layer provenance chain
This session built a coherent chain: hearsay (rsj.12) → stemma (rsj.10) → sycophancy (existing). Each layer addresses a different convergence inflation vector. The synthesis agent now distinguishes genuine independent discovery from three types of false convergence.
