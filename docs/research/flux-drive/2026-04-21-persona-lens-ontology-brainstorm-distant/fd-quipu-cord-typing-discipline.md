---
reviewer: fd-quipu-cord-typing-discipline
bead: sylveste-b1ha
subject: docs/brainstorms/2026-04-21-persona-lens-ontology-brainstorm.md
date: 2026-04-21
severity_counts: {P0: 2, P1: 2, P2: 1, P3: 1}
---

# Review: Persona/Lens Ontology — Relationship Structural Weight

## Executive Summary

The ontology demonstrates strong intuition for relationship-as-structure (D6), but cord properties are underspecified for four critical operations: bridge traversal symmetry (P0), multi-edge discrimination in triage queries (P0), relationship provenance attachment (P1), and Auraken bridge_score transit to AGE (P1). The schema treats edges as thin pointers when the document's own design language implies they should carry quipu-grade structural weight.

---

## P0: Bridge Traversal Symmetry Undefined — Cord Has No Ply Direction

**Location:** D6 (`bridges {strength}` relationship), D5 (triage formula "community neighborhood")

**Finding:**
D6 does not specify whether `Lens —[bridges {strength}]→ Lens` is directed or symmetric. If directed: does `strength` measure outbound influence, inbound grounding, or bidirectional resonance? If symmetric: why use directed edge syntax? When the interlens `find_bridge_lenses` query traverses bridge hops, the query planner cannot determine:
- Follow edge direction: `MATCH (l)-[:bridges]->(neighbor)`
- Ignore direction: `MATCH (l)-[:bridges]-(neighbor)`
- Traverse asymmetrically: `MATCH (l)-[:bridges*1..2]-(neighbor)`

This is catastrophic for the triage scorer's "community neighborhood" term — the formula references a graph metric with undefined topology.

**Concrete failure scenario:**
Phase 4 triage view implements `MATCH (l)-[:bridges]->(neighbor)` (directed). The interlens MCP adapter (Phase 5) implements `MATCH (l)-[:bridges]-(neighbor)` (undirected) to preserve existing `find_bridge_lenses` semantics. Same query intent returns different community neighborhoods. The A/B test comparing graph-triage against filename-glob is comparing two inconsistent graph implementations — the A/B result is meaningless.

**Affected components:** D6 (`bridges`), D5 triage formula, Phase 4 query implementation, Phase 5 interlens adapter

**Smallest viable fix:**
Add to D6: "bridges is SYMMETRIC — strength measures bidirectional resonance. Storage: create both (a)-[:bridges]->(b) AND (b)-[:bridges]->(a) with same strength value. Cypher traversal: always use undirected pattern `(l)-[:bridges]-(neighbor)`." If asymmetric is intended, document: "strength measures how much target-lens depends on source-lens framing; directed traversal is semantically meaningful."

---

## P0: Multi-Edge Discrimination Policy Missing from Triage View

**Location:** D6 (`wields {affinity, generated_at}`), D5 (triage formula first term)

**Finding:**
D6 allows multiple `wields` edges between the same (Persona, Lens) pair with different `{affinity, generated_at}` property bundles. Example:
```
fd-quipu —[wields {affinity: 0.9, generated_at: "2024-01"}]→ structural-semiotics
fd-quipu —[wields {affinity: 0.3, generated_at: "2024-12"}]→ structural-semiotics
```

These are structurally distinct records — two differently-colored cords at the same attachment point. When the triage query runs `MATCH (p:Persona)-[w:wields]->(l:Lens)`, Cypher returns both edges. The D5 scoring formula does not specify: take maximum affinity? weighted recency average? treat as separate candidates?

Without a multi-edge discrimination rule, the triage view produces non-deterministic scores whenever a persona-lens pair has been re-evaluated.

**Affected components:** D5 triage view (wields affinity scoring), D6 relationship properties, Phase 4 query logic

**Smallest viable fix:**
Add to D5 triage view spec:
```yaml
multi_edge_policy:
  wields:
    discrimination: "most_recent"
    formula: "SELECT affinity FROM wields ORDER BY generated_at DESC LIMIT 1"
```
Or add a CONSTRAINT to D6: "Only one active `wields` edge per (Persona, Lens) pair; updates replace edge with new {affinity, generated_at}." Document the choice so Phase 4 and Phase 5 implementors use the same policy.

---

## P1: No Pendant-of-Pendant Slot — Relationship Provenance Has No Structural Home

**Location:** D6 (relationship taxonomy), D7 (`same-as {confidence, method}`), Phase 2 ingestion, Phase 3 dedup

**Finding:**
D6 promises `same-as {confidence, method}` on relationships, but there is no structural slot for "which embedding model version, which threshold, which human reviewer approved this same-as edge." AGE supports edge properties but not edges-on-edges (pendant-of-pendant). The document is aware of this gap (the review instruction asks explicitly about it) but does not resolve it.

Options and their trade-offs:
1. **Reify the edge** — create `WieldsRecord` node, demotes `wields` from relationship to node. Breaks AGE traversal patterns.
2. **Provenance table** — separate `edge_provenance(edge_id, source_id)` in Postgres. Breaks graph traversal.
3. **Inline property** — `wields {affinity, generated_at, source_ref}`. Loses Source's own graph structure.

Without a decision, Phase 3 dedup will emit `same-as` edges with `method = "embedding"` but no record of which embedding model, which threshold, or whether a human reviewed it. The dedup audit trail is informationally empty.

**Affected components:** D6 (all edges with rich provenance), D7 (same-as justification), Phase 2 ingestion (which importer created which edges), Phase 3 (embedding method citation)

**Smallest viable fix:**
Adopt inline provenance for V1: extend all relationship types to include `source_ref: text` (FK to Source node ID) and `method_version: text`. This preserves graph traversal at the cost of Source graph structure. Document: "V2 will evaluate edge reification if provenance queries become complex." Add to D6 schema table a "provenance_fields" row.

---

## P1: Auraken bridge_score → AGE bridges.strength Transit Is Unspecified

**Location:** D6 (`bridges {strength}`), Phase 2 (Auraken importer)

**Finding:**
Auraken's `bridge_score` is a lens-level node property (a global measure per lens), not an edge-specific measure per (lens, lens) pair. D6 maps it to `Lens —[bridges {strength}]→ Lens` where `strength` is an edge property. The Phase 2 Auraken importer must decide: does `bridge_score = 0.87` become the `strength` on every outbound `bridges` edge from that lens? Or is it stored as a Lens node property, with `bridges.strength` computed separately?

If the former: a lens with `bridge_score = 0.87` has all its bridge edges at 0.87 regardless of which specific lens it bridges to. If the latter: the triage formula references `bridges.strength` but the property is actually on the Lens node.

**Concrete failure scenario:**
Phase 4 triage implements: `MATCH (l:Lens)-[b:bridges]->(neighbor) WHERE b.strength > 0.5`. If bridge_score was stored as a Lens property rather than an edge property, `b.strength` is always NULL → no community neighborhood edges are traversed → triage degrades to filename-glob quality, breaking the A/B test.

**Affected components:** D6 (`bridges` schema), Phase 2 Auraken importer, D5 triage formula

**Smallest viable fix:**
Add to Phase 2 spec:
```yaml
auraken_importer:
  bridge_score_mapping:
    # bridge_score is lens-global in Auraken, not per-target
    transform: "bridges.strength = auraken_lens.bridge_score (applied to all outbound edges)"
    provenance: "bridges.source_ref = 'auraken:flux-review-ep11'"
    note: "If per-bridge scores exist in Auraken, extract from bridge_targets[i].score instead"
```

---

## P2: contradicts Directionality Semantics Unspecified

**Location:** D6 (`Lens —[contradicts]→ Lens`)

**Finding:**
`supersedes` direction is semantically clear (newer replaces older). `contradicts` is typically symmetric — contradiction is a property of a pair, not an orientation. The schema does not clarify whether contradicts is symmetric (store both directions) or whether direction encodes "which lens reveals the contradiction."

**Recommendation:**
Document in D6: "contradicts is SYMMETRIC — always create both directed edges when storing. supersedes is DIRECTED — (old)-[:supersedes]->(new)." This prevents Phase 4 query authors from making inconsistent pattern choices.

---

## P3: derives-from Cycle Handling Unspecified

**Location:** D6 (`derives-from`), Phase 2 validation

**Finding:**
D6 shows `Lens —[derives-from]→ Source` but does not prohibit Source→Source chains that could introduce cycles. If a lens derives from a synthesized source that itself derives from that lens (circular import from the same research corpus), the derives-from traversal will loop.

**Recommendation:**
Add to D6 or D9: "derives-from is acyclic — ingestion pipeline rejects imports that would create cycles. bridges is cyclic-allowed (dialectical loops are valid). Document cycle policy per relationship type."
