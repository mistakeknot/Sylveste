# fd-architecture-khouri-domain-model -- Khouri Domain Model Architecture Review

**Date:** 2026-03-21
**Scope:** Proposed `apps/Khouri/src/khouri/models.py` design — three logical groups (CLA Core, Causal/Forecast, Ontology/Gaps) in one flat module; 12 downstream consumers including all 10 pipeline stages, CLI, and project adapter interface.
**Status:** Pre-implementation review. No models.py exists yet. All findings target the proposed design.
**Cross-references:** fd-causal-layered-decomposition.md, fd-graph-topology-and-sid.md, fd-sheaf-consistency-formalism.md (all dated 2026-03-20, reviewed prior to this document).

---

## Summary

The single flat `models.py` is the right call for the current stage. The three logical groups are coherent and the coupling between them is intentional rather than accidental. However, there are four structural issues that, if unaddressed in the initial schema, will cause expensive rework once downstream stages are implemented. Two require schema additions before the first stage is written; two are design decisions that should be settled now to avoid divergent conventions across the 12 sibling beads.

The most consequential decision is whether `CLALayer` is threaded as provenance through `OntologyMapping` and `Gap`, or whether it stays only on `CLADecomposition`. The three prior flux-drive reviews (causal-layered-decomposition, graph-topology-and-sid, sheaf-consistency-formalism) independently converge on the same finding: downstream stages that receive flattened, layer-stripped data cannot recover the CLA provenance they need. The schema must carry layer membership forward, not just record it at decomposition time. Getting this into the initial `models.py` is far cheaper than retrofitting it after five stages have been built against the stripped schema.

---

## 1. Is One Flat Module the Right Call?

Yes, for this stage. The three groups are not independently deployable — they form a single type system used together by every stage. Splitting them at the start would create premature abstraction boundaries before the actual coupling pattern is visible from real consumers.

The YAGNI argument holds: `CausalClaim` and `OntologyMapping` are not independently useful today. Splitting into `cla.py`, `causal.py`, and `ontology.py` before any consumer exists adds three files and three import paths without reducing any real coupling. The coupling between the groups is load-bearing (the sheaf-consistency formalism depends on `OntologyMapping` objects tagged with their `CLALayer`, which depends on `CLADecomposition` having produced that tagging). These groups are cohesive precisely because they form a chain, not independent islands.

The correct split trigger is when a stage has a legitimate reason to import from only one group without touching the others, and that pattern appears consistently across multiple stages. The earliest that can become visible is after the Stage 1 (CLA decomposition agent) and Stage 2a (concept extraction) are implemented. Split then if the pattern is clear, not before.

One condition: the flat module should have clear internal section comments marking the three groups. When the split eventually happens, the section boundaries become the natural module boundaries, and the import structure can be inferred from existing usage.

---

## 2. Boundary and Coupling Analysis

### 2.1 Group 1 to Group 2 coupling (CLA Core -> Causal/Forecast)

`CLALayer` should appear on `CausalClaim` as a `cla_layer: CLALayer | None` field. The source document for this finding is `fd-causal-layered-decomposition.md` F2, which identified that `OntologyMapping` has no `cla_layer` field and thus cannot carry layer provenance once a concept leaves the decomposition stage.

The cascade from this omission: `CausalClaim` objects are produced by Stage 1.5 (causal discovery validation) operating on a `CLADecomposition`. At that moment, each claim is associated with a CLA layer (e.g., a claim about an observable litany-level mechanism vs. a claim about a systemic structural force). If `CausalClaim` does not carry this tag, the SID graph in Stage 3 will contain undifferentiated causal edges. The sheaf checker in Stage 4 will be unable to enforce cross-layer coherence constraints, which require knowing whether restriction maps should be applied within a layer (same-layer edges) or across layers (inter-layer edges have asymmetric dependency directions in CLA methodology). This was flagged independently in both `fd-causal-layered-decomposition.md` and `fd-sheaf-consistency-formalism.md` as a structural gap, not a minor omission.

Smallest viable change: add `cla_layer: CLALayer | None = None` to `CausalClaim`. The `None` default accommodates claims where layer assignment hasn't been determined yet (e.g., during causal discovery validation before CLA decomposition is complete). Stage 1.5 populates it from the parent `CLADecomposition`.

### 2.2 Group 2 to Group 3 coupling (Causal/Forecast -> Ontology/Gaps)

`OntologyMapping` must carry `cla_layer: CLALayer | None` and `Gap` must carry `cla_layer: CLALayer | None`. These are not optional for correct behavior — they are required for the gap classification stage (Stage 6) to distinguish worldview gaps from systemic gaps, and for `GapReport.resolution_order` to have meaningful semantics.

The plan states that `GapReport.resolution_order` uses CLA depth ordering (myth -> litany). This ordering is defined by `CLA_DEPTH_ORDER`. If `Gap` does not carry a `cla_layer` field, `resolution_order` cannot be computed from the gap data alone — it would require external annotation at report generation time. That means the ordering logic becomes a concern of the orchestrator rather than the domain model, which is a responsibility leak. The `GapReport` should be self-contained: given a list of `Gap` objects, it should be able to compute its own resolution order from the layer annotations on those gaps.

Smallest viable change: add `cla_layer: CLALayer | None = None` to both `OntologyMapping` and `Gap`. The `GapReport.resolution_order` field should be a computed property that sorts gaps by `CLA_DEPTH_ORDER.index(gap.cla_layer)` rather than a caller-populated list.

### 2.3 CLAGraph wrapping networkx DiGraph directly

The direct networkx wrap is correct for the MVP. The coupling concern is that `CLAGraph` exposes `nx.DiGraph` as its backing type, which propagates the graph type as an implicit contract into every stage that calls `cla_graph.graph`. When Stage 3 (SID comparison) needs `nx.DiGraph` and Stage 4 (sheaf consistency) may need `nx.MultiDiGraph` (identified in `fd-graph-topology-and-sid.md` F3 as necessary for multi-party institutional coalitions and typed edges), a type mismatch will surface at integration time.

The issue is not that `CLAGraph` wraps networkx — that is fine. The issue is whether `CLAGraph` should be parameterized on the graph type or whether it should expose a stable interface that hides the underlying graph implementation from callers. If every stage accesses `cla_graph.graph.predecessors(node)` directly, they are coupled to `nx.DiGraph` API, and swapping to `MultiDiGraph` requires touching every stage.

This is a real coupling risk, not a speculative one. `fd-graph-topology-and-sid.md` F3 identifies coalition modeling as a medium-severity gap and recommends `MultiDiGraph` with `edge_type` attributes. That change is plausible mid-implementation, not post-completion.

Smallest viable change that avoids the lock-in without over-engineering: add thin accessor methods to `CLAGraph` that are the only API stages use — `add_causal_edge(source, target, edge_type, **attrs)`, `causal_predecessors(node)`, `causal_descendants(node)` — and keep the raw `graph` attribute available for stages that need it directly. When the backing type changes from `DiGraph` to `MultiDiGraph`, only `CLAGraph` needs updating, not all 12 consumers. The method surface is small and justified because it has 12 concrete callers.

This is not premature abstraction — it is a seam over a dependency that the existing evidence shows is likely to change at a known point in the implementation sequence.

### 2.4 ForecastDomain enum and the generic/specific boundary

`ForecastDomain` as an enum inside `models.py` creates tension with the documented product boundary: "Khouri should stay generic and reusable across domains. Project-specific scenario families and ontology belong in downstream repos." (CLAUDE.md, AGENTS.md).

If `ForecastDomain` values (e.g., `ECONOMIC`, `SOCIAL`, `INSTITUTIONAL`) are baked into the core domain model, downstream adapters cannot introduce their own domains without modifying the shared enum. This is not a YAGNI issue — it is a boundary violation that the Khouri product documents explicitly guard against.

The alternatives are:

Option A: Remove `ForecastDomain` from `models.py` and use `str` on `DomainForecast`. Domains are free-form strings validated by adapters. Loses type safety at the core but preserves the generic boundary. Works well if the set of domains is adapter-specific.

Option B: Keep `ForecastDomain` as an enum in `models.py` but limit it to genuinely generic structural roles that any CLA decomposition uses (e.g., the CLA layers themselves serve as domain partitions — `LITANY`, `SYSTEMIC`, `WORLDVIEW`, `MYTH`). Adapter-specific domains are layered on top via a protocol or adapter base type.

Option C: Use a `Literal` type alias that downstream adapters can widen, or a `Protocol` that adapters implement to supply their domain taxonomy.

Option A is the smallest change and respects the generic boundary most cleanly. The risk is losing the type-checked exhaustive matching that enums provide in stage dispatch logic. Given that stage dispatch is already LLM-driven (the decomposition agent dispatches per-domain specialists), the enum is being used as a routing key. If that routing key is adapter-defined, the routing logic must be adapter-aware too, which is appropriate — the adapter is supposed to own domain structure.

Recommendation: replace `ForecastDomain` enum with `str` in `DomainForecast`, documented as "adapter-defined domain identifier." Provide a `BaseForecastDomain` string constant set in the adapter interface (Stage 12 in the bead list) that downstream repos extend. This preserves the boundary without losing all structure.

---

## 3. Pattern Analysis

### 3.1 CLALayer threading is the correct abstraction

Threading `CLALayer` as provenance through all three groups is the right design decision. This is not overdesign — it is the exact signal needed to make gap classification, resolution ordering, sheaf coherence, and backlog synthesis work correctly. The risk is in the execution: if the field is added to the schema but stages fail to populate it (the same failure mode as `_extract_concepts` ignoring `myth` layer, flagged in `fd-causal-layered-decomposition.md` F1), the threading is decorative.

The field should default to `None`, not to a sentinal layer, so that unpopulated provenance is distinguishable from explicitly assigned provenance. Stages that produce `OntologyMapping` or `Gap` objects should assert that `cla_layer` is non-None before inserting into structures that require it (e.g., before adding a `Gap` to a `GapReport` that will compute layer-ordered resolution). This makes the contract explicit without requiring callers to always populate the field upfront.

### 3.2 GapReport.resolution_order as a computed property

If `resolution_order` is a caller-populated list, it is easy for callers to provide it in the wrong order, omit gaps, or include the same gap twice. Making it a `@computed_field` (pydantic v2) or a `@property` computed from the gaps list at access time removes the caller's opportunity to get it wrong. The `CLA_DEPTH_ORDER` list in Group 1 is the correct single source of truth for the ordering, and `GapReport` should reference it directly when sorting.

This is a design correction, not a new capability. The plan already states that `resolution_order` uses CLA depth ordering — computing it from the data rather than requiring callers to provide it is just making that stated intent structural.

### 3.3 MappingConfidence enum vs. float on CausalClaim

The plan uses `MappingConfidence` (enum: high/medium/low/none) on `OntologyMapping` and a raw `float` on `CausalClaim`. This inconsistency will create friction when the sheaf-consistency stage needs to compare or combine confidences from both types. The sheaf formalism requires numeric vector components (as detailed in `fd-sheaf-consistency-formalism.md` F1); an enum cannot be directly used in Laplacian computation without an intermediate conversion table.

Two consistent choices:
- Use `float` on both (0.0-1.0 range). Convert `MappingConfidence` to a float via a helper constant mapping at the sheaf-construction boundary. Simple, uniform, no enum-to-float impedance mismatch.
- Use `MappingConfidence` on both. `CausalClaim.confidence` becomes an enum rather than a float. Loses the continuous confidence semantics that LLM-produced probabilities naturally carry, but is simpler for classification and gap routing.

The float approach is preferable because causal discovery validation (Stage 1.5) and sheaf construction (Stage 4) both need arithmetic on confidence values. The `MappingConfidence` enum should be retained as a categorization convenience (three-bucket display in CLIs and reports), but `OntologyMapping` should also carry a `confidence_score: float` alongside the enum. That way downstream arithmetic uses the float and human-readable output uses the enum, without requiring the enum-to-float conversion to be re-derived at each use site.

### 3.4 Duplication between CLADecomposition and StructuredForecast

Both types appear to encode a structured view of a scenario across CLA layers. `CLADecomposition` holds the raw four-layer textual decomposition; `StructuredForecast` aggregates `DomainForecast` instances. If `DomainForecast.cla` is a field containing CLA layer text, there is a risk of parallel CLA layer representations: one in the raw `CLADecomposition` and one distributed across `DomainForecast` instances.

Before the schema is finalized, the relationship between these types should be explicit in the module docstrings. Is `StructuredForecast` a downstream projection from multiple `CLADecomposition` results (one per domain)? Or are they parallel inputs to Stage 2? If the former, `StructuredForecast` should reference or include `CLADecomposition` instances rather than re-encoding layer content. If the latter, the two types need clear documentation explaining why both exist and what each one's source is.

This is not a boundary violation — it is a cohesion risk. If the relationship is implicit, Stage 1 and Stage 2 will likely develop incompatible assumptions about which of the two types is authoritative for CLA layer content.

---

## 4. Missing Abstractions

### 4.1 No representation of unresolved concepts

The plan's `OntologyMapping` can express a successful mapping (concept -> ontology entity) and presumably a failed mapping (`target_entity: None`). But the gap between "concept successfully extracted from CLA text" and "concept successfully mapped to ontology entity" has no representation in the schema. This gap is where phantom concepts live: concepts that were extracted but are either too vague to map or are artifacts of concept extraction noise.

`fd-graph-topology-and-sid.md` F4 flags phantom concepts as a medium-severity issue. The schema needs a way to represent `ConceptExtractionResult` that is separate from `OntologyMapping` — the former records what was extracted and from which CLA layer, the latter records whether a mapping was found. Conflating them means concept extraction quality and mapping quality cannot be measured independently, and calibration (per PHILOSOPHY.md's closed-loop requirement) cannot target the right stage.

Smallest viable addition: a `ConceptCandidate` dataclass (not a full Pydantic model — it is intermediate scratch data) with `text: str`, `source_layer: CLALayer`, and `source_stage: str` fields. Stage 2a produces these; Stage 2b consumes them and produces `OntologyMapping` instances. The distinction makes the Stage 2a/2b seam explicit in the type system.

### 4.2 No adapter interface type

The adapter interface (Stage 12 in the bead list) is a downstream consumer of `models.py`. The adapter system is described in AGENTS.md and the PRD as the mechanism for downstream projects to inject domain ontology into Khouri. The domain model should define a `Protocol` or `ABC` that adapters implement, even if the implementation is deferred.

Without it, each of the 12 pipeline stages will develop its own assumptions about what an adapter provides. Stage 1 may expect an adapter to return a list of `ForecastDomain` strings; Stage 6 may expect a `GapClassificationHint` type that does not yet exist. The adapter protocol should define the minimal contract at `models.py` time to give sibling stages a shared target.

This is the one abstraction that is not premature: it has a concrete consumer (12 pipeline stages and Stage 12 itself), a clear boundary (Khouri generic vs. adapter-specific), and an explicit risk if absent (divergent adapter assumptions per stage). A `KhouriAdapter` Protocol with three or four methods is sufficient.

---

## 5. Must-Fix Before First Stage

These two changes should be made to the schema before any sibling bead begins implementation against `models.py`. Retrofitting them later will require touching all 12 consumers.

**M1. Add `cla_layer: CLALayer | None = None` to `CausalClaim`, `OntologyMapping`, and `Gap`.**
Rationale: All three of the prior flux-drive reviews for Khouri converge on this gap. The sheaf construction, gap classification, and resolution ordering all require CLA layer provenance to function correctly. Getting it into the schema now is a schema addition; getting it in after five stages are built is a protocol change across all of them.

**M2. Make `GapReport.resolution_order` a computed property from gap `cla_layer` annotations using `CLA_DEPTH_ORDER`, not a caller-populated list.**
Rationale: The ordering is deterministic given the gaps and the depth ordering. A computed property eliminates a category of caller error. It also means the field is always consistent with its source data — a list field can be populated incorrectly; a computed property cannot.

---

## 6. Optional Cleanup Before First Stage

These changes improve the design but are not blocking. They should be resolved before the adapter interface bead (Stage 12) is implemented, since that stage will lock in the domain/adapter boundary.

**O1. Replace `ForecastDomain` enum with `str` on `DomainForecast`, add adapter-supplied domain taxonomy in the adapter Protocol.**
Rationale: Preserves the documented generic boundary. Defers domain taxonomy to adapters where it belongs.

**O2. Add `confidence_score: float` alongside `MappingConfidence` enum on `OntologyMapping`.**
Rationale: Eliminates enum-to-float impedance at the sheaf-construction boundary. Both fields serve different downstream consumers (float for arithmetic, enum for display).

**O3. Define `ConceptCandidate` as an intermediate type representing extracted-but-not-yet-mapped concepts.**
Rationale: Makes the Stage 2a/2b seam explicit in the type system. Enables independent measurement of concept extraction quality vs. mapping quality.

**O4. Add a `KhouriAdapter` Protocol to `models.py` with a stub docstring.**
Rationale: Gives all 12 sibling stages a shared target for adapter expectations. Can be an empty Protocol initially — even an empty Protocol with a docstring prevents stages from inventing incompatible assumptions.

---

## 7. Integration Risk Assessment

The highest integration risk in this domain model is the `CLAGraph` / networkx coupling (section 2.3). The `models.py` plan uses `nx.DiGraph` directly. Two sibling stages (SID comparison in Stage 3, sheaf consistency in Stage 4) have been reviewed and both have requirements that push toward `nx.MultiDiGraph` with typed edge attributes. If all 12 stages are built against `nx.DiGraph` before that change is made, the migration touches every stage. The thin accessor method approach described in 2.3 is a one-session change that prevents a multi-stage migration later.

The second integration risk is the `ForecastDomain` enum (section 3.4). The first downstream project to adapt Khouri will encounter this boundary immediately. If the enum is in the core model, the first adapter bead will either subclass it (which Python enums do not support cleanly) or submit a PR to add adapter-specific values to the core model (which violates the generic boundary). Addressing this in the initial schema avoids that first collision.

---

## Confidence Assessment

- **Single flat module is correct for this stage:** CONFIRMED. Split trigger is visible only after real consumers exist; premature split adds import surface without reducing coupling.
- **M1 and M2 are required before sibling bead implementation:** HIGH CONFIDENCE. Three independent prior reviews converge on the same gap.
- **CLAGraph thin accessor layer prevents multi-stage migration:** HIGH CONFIDENCE. Evidence from fd-graph-topology-and-sid.md F3 is concrete and medium-severity.
- **ForecastDomain boundary violation:** CONFIRMED against documented product boundary (CLAUDE.md, AGENTS.md, README.md all state generic-app boundary explicitly).
- **KhouriAdapter Protocol is not premature:** HIGH CONFIDENCE. 12 concrete consumers exist; the boundary is documented; absence creates divergent conventions.
