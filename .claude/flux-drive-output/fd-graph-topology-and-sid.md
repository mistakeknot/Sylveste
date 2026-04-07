# fd-graph-topology-and-sid -- SID Graph Construction and Comparison Review

**Date:** 2026-03-20
**Scope:** Task 12 (causal_comparison.py), Task 2 domain model (CausalClaim, CascadeEdge, OntologySchema), networkx graph representation
**Non-scope:** Sheaf consistency (fd-sheaf-consistency-formalism), ontology matching ML (fd-ontology-matching-methods), CLA layer structure (fd-causal-layered-decomposition)

## Summary

The proposed SID stage (Task 12 in the implementation plan) extracts two directed graphs -- a forecast causal DAG from `CausalClaim` edges and a simulation cascade DAG from `OntologySchema.cascade_edges` -- then computes Structural Intervention Distance to identify causal gaps. The current domain model and planned approach have six structural issues that range from correctness-threatening (edge semantics conflation, missing temporal annotations) to quality-degrading (phantom nodes from concept extraction, isomorphism instability under relabeling). The core representation choice of `networkx.DiGraph` is adequate for the MVP but will need to evolve to `networkx.MultiDiGraph` with edge-typed layers for institutional coalition modeling.

## Findings

### F1. Edge Semantics Conflation (Severity: HIGH)

**Problem:** The two graph sources encode fundamentally different edge semantics, and the plan treats them as comparable without normalization.

- `CausalClaim` edges encode causal directionality with a mechanism and confidence: `cause -> effect` via `mechanism` at `confidence` level. These are epistemological claims ("we believe X causes Y").
- `CascadeEdge` edges encode pressure propagation with a weight: `source -> target` at `weight`. These are simulation mechanics ("when source fires, target receives weight * intensity").

Comparing these directly via SID conflates epistemological claims with simulation mechanics. SID (Peters & Buhlmann, 2015) measures interventional equivalence between two DAGs over the same variable set. It asks: "for each ordered pair (i, j), is the intervention distribution P(x_j | do(x_i)) the same?" This requires both graphs to share the same node semantics and the same interpretation of edge directionality.

Currently:
- `CausalClaim.cause` and `CausalClaim.effect` are free-text strings from LLM extraction (e.g., "open border policy", "housing demand surge").
- `CascadeEdge.source` and `CascadeEdge.target` are ontology identifiers (e.g., "economic_strain", "social_unrest").

The ontology matching stage (Stage 2) maps forecast concepts to ontology entities, but the plan does not describe how `CausalClaim` endpoints are re-expressed in ontology terms before graph comparison. Without this, SID computation operates on disjoint node sets.

**Where in code:** `CausalClaim` in `~/projects/shadow-work/docs/plans/2026-03-18-khouri-and-system-tracer-plan.md` (Task 2, line ~174-179), `CascadeEdge` (Task 3, line ~311-315).

**Recommendation:** Add a `resolved_cause: str | None` and `resolved_effect: str | None` field to `CausalClaim` that Stage 2 populates with ontology-mapped identifiers. SID computation should only use resolved endpoints. Unresolved claims become gap candidates directly (they represent causal relationships the ontology cannot express).

### F2. Node Relabeling Instability (Severity: HIGH)

**Problem:** SID is not invariant under node relabeling. If the ontology matching stage maps "open border policy" to `demographic_pressure` in one run and to `migration_crisis` in another (both plausible), the SID score changes even though the structural relationship is the same.

The ontology matching stage uses LLM-based matching (`match_forecast_to_ontology`), which is inherently non-deterministic. Two runs of the same forecast against the same schema can produce different `OntologyMapping` results, leading to different graph topologies for the forecast DAG after resolution.

SID between graphs G1 and G2 is defined as:
```
SID(G1, G2) = sum over (i,j) of 1[PA_G1(j) != PA_G2(j) in the interventional sense]
```
where PA denotes parent sets. A relabeling that changes which ontology node a concept maps to changes the parent sets, producing different SID values for structurally equivalent causal claims.

**Recommendation:** Introduce a canonicalization step between Stage 2 and Stage 3:
1. For each `CausalClaim`, resolve both endpoints to ontology entities using Stage 2 mappings.
2. When multiple mappings exist for a concept (e.g., `confidence: medium` for two targets), generate edges for the highest-confidence mapping only, but record alternatives.
3. Collapse duplicate edges (same resolved source and target) by taking the max confidence.
4. Compute SID on the canonicalized graph.
5. Run a sensitivity analysis: re-compute SID with second-best mappings and report the SID delta as a stability score.

### F3. networkx.DiGraph Is Insufficient for Institutional Coalitions (Severity: MEDIUM)

**Problem:** The plan specifies `networkx` for graph operations and a simple directed graph. The simulation ontology includes `institution_types` (central_bank, treasury, executive, corporation, etc.) that form coalitions -- multiple institutions jointly producing a pressure outcome. A `DiGraph` cannot represent:

- **Hyperedges:** "central_bank AND treasury jointly cause economic_strain" requires a hyperedge from {central_bank, treasury} to economic_strain. In a `DiGraph`, this must be decomposed into two separate edges, losing the conjunctive semantics.
- **Multi-edges:** A single institution pair may have multiple causal pathways (e.g., central_bank -> economic_strain via "interest rate policy" AND via "quantitative easing"). `DiGraph` silently overwrites duplicate edges.
- **Typed edges:** Causal edges, institutional membership edges, temporal precedence edges, and co-presence edges all exist in the domain but `DiGraph` has a single edge type.

**networkx alternatives:**
- `networkx.MultiDiGraph` -- supports parallel edges between the same node pair, each with its own attributes. This handles multi-edges and typed edges via an edge `key` or `type` attribute.
- For hyperedges, networkx has no native support. Options: (a) introduce auxiliary "coalition" nodes that aggregate institutional inputs (recommended -- keeps the graph simple), (b) use a separate hypergraph library like `hypernetx`, (c) use bipartite graph encoding.

**Recommendation:** Use `networkx.MultiDiGraph` with an `edge_type` attribute (values: `"causal"`, `"cascade"`, `"institutional"`, `"temporal"`). Model coalitions as explicit coalition nodes: if {central_bank, treasury} jointly cause economic_strain, create a node `coalition:cb_treasury` with edges `central_bank -> coalition:cb_treasury` (type: institutional) and `coalition:cb_treasury -> economic_strain` (type: causal). This keeps SID computable (SID requires a DAG, and coalition nodes preserve acyclicity if the underlying causal structure is acyclic).

### F4. Phantom Gap Nodes from Concept Extraction (Severity: MEDIUM)

**Problem:** The `_extract_concepts` function in `ontology_matching.py` (lines 714-736 in the plan) uses naive text splitting:

```python
for phrase in text.replace(".", ",").split(","):
    phrase = phrase.strip()
    if len(phrase) > 3:
        concepts.add(phrase)
```

This produces low-precision concept extraction. Examples of false positives from a CLA litany like "Sea walls, floating districts, atmospheric processors":
- "Sea walls" -- legitimate concept
- " floating districts" -- legitimate but may not map to any pressure/institution
- "atmospheric processors" -- legitimate
- But from "Climate adaptation as economic engine": "Climate adaptation as economic engine" is one concept, not two split on commas.

Every false-positive concept that fails ontology matching becomes an unmapped concept in the `GapReport`, which the gap synthesis stage (Stage 6) then tries to classify. Phantom concepts create phantom gaps that inflate the gap set and waste synthesis budget.

The impact on SID: if phantom concepts are resolved to ontology nodes (even at low confidence), they add phantom edges to the forecast DAG, increasing SID artificially. If they remain unresolved, they appear as missing nodes -- which is the correct behavior (they ARE missing from the ontology), but for the wrong reason (they aren't real concepts).

**Recommendation:**
1. Replace comma-splitting with LLM-based concept extraction (or at minimum, NLP chunking). The Stage 1 CLA decomposition already uses an LLM -- add a concept extraction step to the domain agent prompt that returns explicit concept lists alongside the CLA fields.
2. Add a `CausalClaim`-derived concept set that extracts concepts from the structured `cause`, `effect`, and `mechanism` fields rather than from free-text CLA layers. These are higher-precision because the LLM already structured them.
3. Add a deduplication pass: fuzzy-match extracted concepts (e.g., Levenshtein or embedding similarity) and merge near-duplicates before ontology matching.

### F5. Missing Temporal Annotations for Backward Tracing (Severity: MEDIUM)

**Problem:** The plan describes Khouri as an "inverse scenario planning engine" that performs backward tracing -- given a future state, identify the prerequisite institutions and causal chains that must exist. Backward tracing requires temporal ordering: "institution A must exist before pressure B can emerge, and pressure B must precede institution C's creation."

Neither `CausalClaim` nor `CascadeEdge` carries temporal information:
- `CausalClaim` has `cause`, `effect`, `mechanism`, `confidence` -- no temporal precedence.
- `CascadeEdge` has `source`, `target`, `weight` -- no temporal layer.

The `Scenario` type in the domain model review has `HorizonStart` and `HorizonEnd`, but these are scenario-level, not edge-level. Individual causal links within a scenario have no temporal annotation.

Without edge-level temporal annotations, the graph cannot distinguish:
- "economic_strain causes social_unrest" (immediate propagation)
- "demographic_pressure causes economic_strain" (multi-decade lag)
- "institution X must be established before cascade Y can fire" (temporal prerequisite)

For backward tracing, topological sort of the DAG gives a partial ordering, but it cannot distinguish "A before B by 5 years" from "A before B by 50 years." This matters when synthesizing gaps: a missing institution that must exist 200 years before the target state is a different kind of gap than one needed 5 years before.

**Recommendation:** Add temporal annotations to both edge types:

```python
class CausalClaim(BaseModel):
    cause: str
    effect: str
    mechanism: str = ""
    confidence: float = Field(default=0.5, ge=0.0, le=1.0)
    temporal_lag: str | None = None  # "immediate", "years", "decades", "centuries"
    temporal_order: int | None = None  # relative ordering within the scenario

class CascadeEdge(BaseModel):
    source: str
    target: str
    weight: float = Field(default=0.2, ge=0.0, le=1.0)
    propagation_delay: int = 0  # simulation ticks
```

In the networkx graph, store these as edge attributes. Backward tracing then uses weighted topological sort where edge weights encode temporal distance, enabling the gap synthesizer to prioritize "early prerequisite" gaps over "late prerequisite" gaps.

### F6. Missing vs. Present-But-Inactive Node Distinction (Severity: LOW)

**Problem:** The plan mentions simulation probing (Stage 5) as a way to validate gaps by running the simulation. The graph representation needs to distinguish:

1. **Missing nodes:** The ontology has no entity for this concept. The concept cannot be represented in the simulation. This is a structural gap.
2. **Present-but-inactive nodes:** The ontology has the entity, but under the given initial conditions it never activates. This is a calibration gap or a parametric gap, not a structural one.

Currently, SID comparison can only detect structural differences (edges present in one graph but not the other). It cannot detect that a node exists in the simulation graph but never participates in any causal chain under the proposed scenario conditions.

**networkx query approach:** For present-but-inactive detection:
- Compute reachability from initial condition nodes using `networkx.descendants(G, node)` for each activated pressure.
- Nodes in the simulation graph that are NOT in any reachability set from active initial conditions are present-but-inactive candidates.
- Compare against forecast DAG: if the forecast expects a node to be active (it appears as a cause or effect in a `CausalClaim`) but simulation reachability analysis shows it's unreachable from the proposed initial conditions, flag it as a calibration/parametric gap rather than a structural gap.

**Recommendation:** Add a `NodeStatus` enum to the graph representation:

```python
class NodeStatus(str, Enum):
    ACTIVE = "active"          # In the graph and reachable
    INACTIVE = "inactive"      # In the graph but unreachable from ICs
    MISSING = "missing"        # Not in the ontology at all
    PHANTOM = "phantom"        # Extracted but likely a false positive
```

Tag each node in the forecast DAG after simulation probing. Gap synthesis should use this tag to set severity: MISSING > INACTIVE > PHANTOM.

## Recommendations Summary

| # | Finding | Severity | Action |
|---|---------|----------|--------|
| F1 | Edge semantics conflation | HIGH | Add `resolved_cause`/`resolved_effect` to CausalClaim; SID only on resolved graphs |
| F2 | Node relabeling instability | HIGH | Canonicalize mappings; compute SID stability score via second-best mapping sensitivity |
| F3 | DiGraph insufficient | MEDIUM | Use `networkx.MultiDiGraph` with `edge_type` attr; model coalitions as auxiliary nodes |
| F4 | Phantom concepts | MEDIUM | LLM-based extraction; derive concepts from CausalClaim fields; deduplicate before matching |
| F5 | No temporal annotations | MEDIUM | Add `temporal_lag`/`propagation_delay` to edges; weighted topological sort for backward trace |
| F6 | Missing vs. inactive | LOW | Reachability analysis via `networkx.descendants`; add `NodeStatus` enum |

## SID Implementation Guidance

For the actual SID computation in `causal_comparison.py`, the reference algorithm (Peters & Buhlmann, 2015) is O(p^2) where p is the number of nodes. networkx provides:

- `networkx.d_separation(G, x, y, z)` -- tests d-separation, the building block for interventional equivalence
- `networkx.is_directed_acyclic_graph(G)` -- required precondition; SID is undefined on cyclic graphs
- `networkx.ancestors(G, node)` and `networkx.descendants(G, node)` -- for parent set computation
- `networkx.topological_sort(G)` -- for temporal ordering in backward tracing

There is no built-in SID function in networkx. Implement as:

```python
def sid(g1: nx.DiGraph, g2: nx.DiGraph) -> int:
    """Structural Intervention Distance between two DAGs over the same node set."""
    nodes = set(g1.nodes()) | set(g2.nodes())
    distance = 0
    for target in nodes:
        # Compare intervention-equivalent parent sets
        parents_g1 = set(g1.predecessors(target)) if target in g1 else set()
        parents_g2 = set(g2.predecessors(target)) if target in g2 else set()
        if parents_g1 != parents_g2:
            distance += 1
    return distance
```

Note: this is the simplified SID that compares parent sets directly. The full SID compares interventional distributions, which requires checking Markov equivalence classes. For the Khouri use case (comparing a forecast DAG against a known simulation DAG, not learning from data), parent-set comparison is sufficient because both graphs are fully specified (no hidden variables, no equivalence class ambiguity).

## Confidence Assessment

- **Graph comparison produces minimal gap sets (no phantoms):** NOT YET MET. F4 (phantom concepts) directly creates false-positive gaps. Requires LLM-based extraction fix.
- **Graph comparison produces maximal gap sets (no misses):** PARTIALLY MET. F1 (unresolved endpoints) causes real causal gaps to be invisible to SID. F5 (no temporal ordering) causes temporal prerequisite gaps to be missed.
- **SID comparison stable under ontology-equivalent relabeling:** NOT YET MET. F2 (relabeling instability) is a direct violation. Requires canonicalization and sensitivity analysis.
