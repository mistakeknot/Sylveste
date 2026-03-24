# fd-sheaf-consistency-formalism -- Review Output

**Reviewer:** Sheaf consistency formalism specialist
**Date:** 2026-03-20
**Scope:** Task 13 (Stage 4 -- Discourse Sheaf Consistency Checking) as specified in `/home/mk/projects/shadow-work/docs/plans/2026-03-18-khouri-and-system-tracer-plan.md`, cross-referenced with the domain model in Tasks 2-3 and the PRD at `/home/mk/projects/Demarch/apps/Khouri/docs/khouri-prd.md`.
**Status:** Pre-implementation design review. No code exists yet for Stage 4; all findings target the specification.

---

## Summary

The plan specifies a sheaf consistency stage that (1) constructs a "discourse sheaf" over the ontology graph, (2) assigns local sections from forecast mappings, (3) computes the sheaf Laplacian, and (4) identifies high-discord nodes. This is a sound high-level recipe -- it follows the Robinson (2014) / Hansen-Ghrist (2012) framework for cellular sheaves on graphs with Laplacian-based consistency analysis. However, the specification as written is underspecified in five ways that each risk producing a degenerate or vacuously-consistent checker. Three of these are P1 (the implementation will silently pass inconsistent scenarios), one is P0 (the sheaf may not be constructible from the data model as currently defined), and one is P2 (reporting granularity).

The core tension: the plan inherits its graph from Stage 3 (SID comparison via `networkx`) and its sections from Stage 2 (ontology matching via `OntologyMapping` objects). Neither of these provides the structured numeric data that a Laplacian eigenproblem requires. Without explicit design for the embedding of semantic content into vector-valued stalks, the sheaf Laplacian will either operate on trivial (scalar) stalks -- reducing to a standard graph Laplacian with no sheaf-theoretic content -- or require an ad-hoc vectorization step that the plan does not specify.

---

## Findings

### F1 [P0]: Stalks are untyped -- the domain model provides no vector space structure for sheaf sections

**Location:** Task 13 spec ("assigns local sections from forecast mappings") combined with `src/khouri/models.py` (Task 2) and `src/khouri/adapter.py` (Task 3).

**Problem:** A cellular sheaf F on a graph G = (V, E) assigns a vector space F(v) to each vertex v and a vector space F(e) to each edge e, together with linear restriction maps F(v) -> F(e) for each incidence v ~ e. The sheaf Laplacian L_F is defined as delta^T delta where delta is the coboundary operator, and it acts on the direct sum of the vertex stalks. This requires that each stalk be a finite-dimensional real (or complex) vector space with a chosen inner product.

The current domain model provides:
- `OntologyMapping`: a Pydantic object with fields `source_concept: str`, `target_entity: str | None`, `confidence: MappingConfidence` (an enum: high/medium/low/none), `rationale: str`.
- `CausalClaim`: fields `cause: str`, `effect: str`, `mechanism: str`, `confidence: float`.
- `CascadeEdge`: fields `source: str`, `target: str`, `weight: float`.

None of these are elements of a vector space. The `confidence` floats are scalars, not vectors. String fields have no natural inner product. To construct a non-degenerate sheaf, the implementer must define an embedding phi: (domain model object) -> R^d for each stalk, and the plan does not specify this.

**Failure scenario:** An implementer assigns scalar stalks F(v) = R (using just the confidence score) and identity restriction maps. The resulting sheaf Laplacian is numerically identical to the ordinary graph Laplacian weighted by confidence differences. This detects nothing that a simple "flag nodes where adjacent confidences disagree" heuristic wouldn't catch. The sheaf adds no value.

**Recommendation:** Before implementation, define the stalk type explicitly. A productive choice for this domain:

- F(v) = R^k where k = |{CLA layers}| x |{ontology entity types}| (e.g., k = 4 x 3 = 12 for four CLA layers and three entity types: pressure, institution, issue). Each component encodes the confidence that the node's forecast concept maps to a specific CLA layer x entity type combination.
- F(e) = R^m where m encodes the constraint space for the edge (e.g., causal compatibility between source and target stalk dimensions).
- Restriction maps rho_{v,e}: F(v) -> F(e) are projection matrices that extract the components relevant to the edge's causal claim, composed with a compatibility transform.

This gives stalks with dimension > 1, making the sheaf Laplacian spectrum genuinely richer than the graph Laplacian spectrum.

---

### F2 [P1]: No specification of restriction maps -- risk of identity-map degeneracy

**Location:** Task 13 spec ("constructs a discourse sheaf over the ontology graph").

**Problem:** The specification says "constructs a discourse sheaf" but does not define the restriction maps rho_{v,e}: F(v) -> F(e). In the Hansen-Ghrist framework, the restriction maps *are* the sheaf -- two sheaves on the same graph with different restriction maps encode entirely different consistency constraints. If restriction maps default to identity (or to trivial projection), the sheaf consistency check degenerates:

- If all rho_{v,e} = id_F(v) (and edge stalks equal vertex stalks), then the coboundary operator delta measures only whether adjacent vertex sections are *equal*. This is the graph Laplacian, not a sheaf Laplacian.
- If restriction maps are all zero, every assignment is consistent. The check passes vacuously.

**What should the restriction maps encode?** In Khouri's domain, the coherence semantics are: "if node A claims X causes Y through mechanism M, and node B participates in Y, then B's local section must be compatible with receiving causal influence from A through M." This is a *typed compatibility* constraint, not equality. The restriction map from A to edge (A,B) should project A's stalk onto the dimensions corresponding to the causal claim's output type, and the restriction map from B to edge (A,B) should project B's stalk onto the dimensions corresponding to the causal claim's input type. Consistency on edge (A,B) means rho_{A,e}(s_A) = rho_{B,e}(s_B), which encodes "A's output matches B's input along the causal channel."

**Failure scenario:** With identity restriction maps, a scenario where "technology node claims AI governance requires democratic institutions" and "politics node claims authoritarian consolidation" would not be flagged as inconsistent -- both would simply have different section values, and the Laplacian would measure the magnitude of difference without distinguishing meaningful contradiction from expected domain diversity.

**Recommendation:** Define restriction maps as typed projections determined by the `CausalClaim` edge metadata. Specifically: each `CausalClaim` with fields (cause, effect, mechanism) defines which stalk dimensions of the source and target are coupled. The restriction map projects onto those dimensions. This is the minimum structure needed for the sheaf to encode cross-node coherence rather than just cross-node similarity.

---

### F3 [P1]: Global section existence is not what the Laplacian spectrum directly computes

**Location:** Task 13 spec ("computes the sheaf Laplacian" and "identifies high-discord nodes").

**Problem:** The plan conflates two distinct operations:

1. **Global section existence:** Does there exist a global section s in prod_v F(v) such that for every edge (u,v), rho_{u,e}(s_u) = rho_{v,e}(s_v)? This is a system of linear equations. The space of global sections is ker(delta) = ker(L_F) (the 0-eigenspace of the sheaf Laplacian). If dim(ker(L_F)) = 0, no nontrivial global section exists, and the local assignments are globally inconsistent.

2. **Discord localization:** Given a *specific* assignment x (the local sections from forecast mappings), how inconsistent is x, and where? The answer is L_F x, which gives a per-vertex "inconsistency energy" vector. The total inconsistency is x^T L_F x. High-energy vertices are "high-discord nodes."

These are complementary but distinct. The plan says "identifies high-discord nodes," which is operation (2). But it also should check operation (1) -- if ker(L_F) is trivial, the sheaf itself is over-constrained and *no* forecast could be consistent, which indicates the restriction maps are too tight or the graph is missing mediating nodes.

**Failure scenario:** The implementation computes only x^T L_F x (discord energy) without checking dim(ker(L_F)). On a graph where the sheaf has no global sections (trivial kernel), *every* forecast will show high discord everywhere, and the output will be noise -- no localization is meaningful when the entire sheaf is structurally inconsistent.

**Recommendation:** Compute both:
- `ker_dim = np.sum(eigenvalues < epsilon)` to check whether global sections exist at all. If `ker_dim == 0`, report "sheaf is over-constrained" as a structural finding before attempting discord localization.
- `discord = L_F @ x` for per-node localization only when `ker_dim > 0`.
- The near-zero eigenvalues and their eigenvectors identify the "most consistent directions" -- projecting the actual assignment onto this subspace gives the best-fit globally-consistent approximation, and the residual localizes the inconsistencies.

---

### F4 [P1]: Open-world/closed-world distinction -- missing nodes are vacuously consistent

**Location:** Task 13 spec combined with the adapter model in `src/khouri/adapter.py` (Task 3).

**Problem:** The ontology graph is built from `OntologySchema.cascade_edges` (the simulation's known causal structure) and augmented by `CausalClaim` edges from the forecast. When the forecast introduces a concept that maps to `target_entity = None` (unmapped in Stage 2), this concept either:

(a) Gets no node in the graph (closed-world: if it's not in the ontology, it doesn't exist). Then the sheaf never sees it, and consistency is evaluated only over the simulation's known world. This is the "vacuous consistency" failure: the forecast says "housing-as-right governance is needed" but since no `housing_governance` node exists, the sheaf check passes without noticing the gap.

(b) Gets a node with an empty stalk (open-world: the concept exists but has no grounding). Then the restriction maps from this node to its neighbors produce zero vectors, and consistency with this node is trivially satisfied (0 = 0).

Either way, the most important class of gaps -- *things the simulation doesn't model at all* -- is invisible to the sheaf checker.

**Failure scenario:** The LA-2525 forecast generates "post-scarcity housing governance" as a causal prerequisite. Stage 2 maps it to `target_entity = None`. The sheaf is built only over nodes with ontology groundings. The sheaf check reports "consistent" even though the forecast requires an institution type that doesn't exist. The gap is caught by Stage 6 (gap synthesis) but not by Stage 4, making Stage 4 redundant for the highest-value gap class.

**Recommendation:** For unmapped concepts, insert a "placeholder node" with a non-trivial stalk (e.g., the stalk is R^k filled with the forecast's confidence vector) but with *intentionally incompatible restriction maps* to its neighbors. Specifically, the restriction map from the placeholder to any edge should map to a distinguished "ungrounded" subspace of the edge stalk, while the restriction map from the grounded neighbor maps to the "grounded" subspace. These subspaces should be orthogonal, guaranteeing that rho_{placeholder,e}(s_placeholder) != rho_{neighbor,e}(s_neighbor) and the sheaf Laplacian reports maximal discord at the placeholder. This converts "missing institution" from a vacuous pass to a detectable inconsistency.

---

### F5 [P2]: Dynamic graph topology during backward tracing

**Location:** Task 13 spec ("constructs a discourse sheaf over the ontology graph") combined with Task 12 (Stage 3 -- SID comparison).

**Problem:** The plan implies a fixed graph: Stage 3 builds the SID comparison graph, then Stage 4 builds a sheaf over it. But the broader Khouri architecture involves backward tracing -- iteratively discovering what must exist for the destination state to be reachable. Each iteration may add new nodes (discovered prerequisites) or edges (discovered causal pathways). If the sheaf is built once and not updated, it evaluates consistency of an incomplete graph.

Technically, updating a cellular sheaf when the base graph changes requires:
- Extending the coboundary matrix delta with new rows (for new edges) and columns (for new vertex stalks).
- Re-computing the Laplacian L_F = delta^T delta.
- The eigendecomposition from the previous iteration is not reusable (rank-1 update formulas exist for Laplacians but are non-trivial for sheaf Laplacians with non-identity restriction maps).

For the MVP where backward tracing is not yet implemented (Stages 3-5 are all post-MVP), this is not a blocking issue. But the design should not assume a fixed graph if backward tracing is the intended use case.

**Recommendation:** Document that the current sheaf construction is a one-shot evaluation over the Stage 3 output graph. If backward tracing is added later, either (a) rebuild the sheaf from scratch on each iteration (simple, O(|V|^2 |E|) per iteration), or (b) implement incremental Laplacian updates using the matrix determinant lemma for rank-k perturbations. Option (a) is sufficient unless the graph exceeds ~1000 nodes, which is unlikely for CLA-structured scenario graphs.

---

### F6 [P2]: Reporting granularity -- which restriction map failed

**Location:** Success criteria ("the implementation can report which specific restriction map failed").

**Problem:** The Laplacian-based approach produces a per-vertex energy vector (L_F x), which localizes discord to *nodes* but not to specific *edges* (restriction maps). To identify which restriction map failed, the implementation must also compute the per-edge inconsistency:

For each edge e = (u,v): `edge_discord[e] = ||rho_{u,e}(x_u) - rho_{v,e}(x_v)||^2`

This is the summand in x^T L_F x and is straightforward to compute from the coboundary operator: `per_edge = delta @ x`, then take norms per edge block. The per-vertex discord is the sum of per-edge discords over incident edges.

**Recommendation:** Compute and return `edge_discord` as a dict keyed by `(source_concept, target_concept, edge_type)`. This directly satisfies the success criterion and enables the gap synthesis stage (Stage 6) to report "the causal claim 'X causes Y through M' is inconsistent with the local forecast at node Y" rather than just "node Y has high discord."

---

### F7 [P1]: Coboundary vs. Laplacian -- soft vs. hard inconsistency classification

**Location:** Task 13 spec ("classifies inconsistencies: genuine gap vs. calibration vs. creative tension").

**Problem:** The plan mentions classifying inconsistencies but does not specify how to distinguish soft from hard inconsistencies using the sheaf's algebraic structure. The sheaf Laplacian provides a natural classification:

- **Hard inconsistency (genuine gap):** `edge_discord[e] > 0` AND the edge's restriction maps have full rank (the constraint is well-posed and violated). This means the local sections are fundamentally incompatible along this edge.
- **Soft inconsistency (calibration issue):** `edge_discord[e] > 0` BUT the residual lies in a low-dimensional subspace of F(e) (the sections agree on most dimensions but disagree on parameter-like quantities). Detected by checking `rank(residual) << dim(F(e))`.
- **Creative tension:** The discord is concentrated on stalk dimensions corresponding to `worldview` or `myth` CLA layers (the deeper, more subjective layers), not on `litany` or `systemic` layers. This requires the stalk structure from F1 to distinguish CLA layers within the vector space.
- **No inconsistency, but structurally interesting:** Near-zero eigenvalues of L_F that are not exactly zero indicate "almost consistent" -- the global section space is "almost" non-empty. The gap between the smallest non-zero eigenvalue and zero is the "consistency margin."

Without this classification, the implementation will report a single scalar discord per node with no semantics, which is insufficient for routing gaps to different remediation paths.

**Recommendation:** Implement the three-tier classification: (1) compute per-edge discord vectors (not just norms), (2) check rank of discord residuals for soft/hard distinction, (3) project discord onto CLA-layer subspaces of the stalk for creative-tension detection.

---

## Recommendations

### Implementation order (smallest-viable-fix approach)

1. **Define stalk type** (addresses F1). Add a `SheafStalk` model to `models.py` with explicit dimensionality tied to CLA layers x entity types. This is the load-bearing design decision -- everything else follows from it.

2. **Define restriction maps as typed projections** (addresses F2). Write a `build_restriction_map(causal_claim: CausalClaim, source_stalk_dim: int, target_stalk_dim: int) -> np.ndarray` function that constructs the projection matrix. Test with a hand-crafted 3-node graph where one planted inconsistency is detectable only via the sheaf (not by node-local checks).

3. **Implement placeholder nodes for unmapped concepts** (addresses F4). This is the single highest-value addition to the sheaf layer -- without it, the sheaf check is redundant with the gap synthesis stage.

4. **Compute both kernel dimension and per-edge discord** (addresses F3, F6). Return a `SheafConsistencyReport` with fields: `kernel_dimension: int`, `is_over_constrained: bool`, `per_node_discord: dict[str, float]`, `per_edge_discord: dict[tuple[str,str], float]`, `failed_restriction_maps: list[RestrictionMapFailure]`.

5. **Add soft/hard/creative classification** (addresses F7). This can be a post-processing step on the per-edge discord vectors.

6. **Document fixed-graph assumption** (addresses F5). Add a comment in the stage docstring noting that backward-tracing iterations require sheaf reconstruction.

### Synthetic test case for validation

Construct a 4-node linear graph: A -> B -> C -> D, where A is a climate node, B is an economic node, C is a political node, D is a demographic node. Plant an inconsistency: A's forecast claims "managed sea-level rise drives green economy growth" (positive causal direction), but C's forecast claims "economic collapse from climate costs drives authoritarian politics" (negative causal direction). B is the mediating node. Node-local validation sees no contradiction (each node's CLA decomposition is internally coherent). The sheaf check should detect that the restriction maps on edges (A,B) and (B,C) impose contradictory constraints on B's stalk -- B cannot simultaneously encode "green growth" and "economic collapse."

This test case validates the success criterion: the sheaf catches a cross-node contradiction that node-local validation misses, and the per-edge discord report identifies edge (A,B) and/or (B,C) as the failure locus.
