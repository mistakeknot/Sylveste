---
artifact_type: review-synthesis
method: flux-review
target: "docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md"
target_description: "Ontology graph for agentic development platforms"
tracks: 4
track_a_agents: [fd-ontology-schema-evolution, fd-entity-resolution-identity, fd-graph-query-runtime, fd-agent-ontology-runtime, fd-composition-coupling-philosophy]
track_b_agents: [fd-archival-provenance-linkage, fd-clinical-terminology-harmonization, fd-spatial-data-infrastructure, fd-litigation-entity-mapping]
track_c_agents: [fd-persian-qanat-subterranean-topology, fd-javanese-gamelan-ensemble-tuning, fd-heraldic-blazon-compositional-grammar, fd-polynesian-wayfinding-star-path]
track_d_agents: [fd-dogon-po-tolo-seed-classification, fd-petrographic-thin-section-entity-resolution, fd-burmese-bedin-planetary-relational-calculus]
date: 2026-04-04
---

# Flux-Review Synthesis: Ontology Graph for Agentic Development Platforms

16 agents across 4 tracks (adjacent, orthogonal, distant, esoteric) reviewed the concept brief. Total findings: ~95 (4 P0, 40 P1, 38 P2, 3+ P3). Every track returned a "risky" or "needs-changes" verdict. The strongest signals are the convergent findings -- issues independently discovered by agents reasoning from completely different knowledge domains.

---

## Critical Findings (P0/P1)

### P0-1: No entity resolution strategy for the headline use case

**Agents:** fd-entity-resolution-identity (Track A), fd-archival-provenance-linkage (Track B), fd-litigation-entity-mapping (Track B), fd-spatial-data-infrastructure (Track B), fd-petrographic-thin-section-entity-resolution (Track D)
**Tracks:** A, B, D (3/4)

The brief's motivating example -- "show me everything connected to this function" -- is an entity resolution problem, not a graph structure problem. A single function is referred to as a qualified symbol name (tldr-code), a file path + line range (git/beads), a hex session ID + tool call context (cass), a natural language reference (discoveries), and a finding ID + file reference (flux-drive). Without a resolution layer mapping all five representations to a canonical entity, the graph is a collection of disconnected subgraphs that looks unified in schema diagrams but is fragmented in practice.

**Recommendation:** Design the entity resolution layer before the graph schema. Define canonical entity types with enumerated ID schemes per type, resolution rules (exact match for paths, structural match via AST, fuzzy match via embeddings), and confidence levels (confirmed, probable, speculative). Start with file-level resolution where structured links already exist.

### P0-2: Cross-system entity links lack provenance metadata

**Agents:** fd-litigation-entity-mapping (Track B), fd-persian-qanat-subterranean-topology (Track C), fd-polynesian-wayfinding-star-path (Track C)
**Tracks:** B, C (2/4)

The ontology proposes connecting entities across subsystems without recording why a link was created, what evidence supports it, or what confidence level applies. fd-litigation-entity-mapping identified this as the single most dangerous gap: a false link (temporal co-occurrence mistaken for causation) propagates through the dispatch system with no audit trail. fd-persian-qanat-subterranean-topology independently found the same gap from the correlation-vs-causation angle -- the brief does not distinguish causal edges (bead.blocks) from correlative edges (session.overlaps_temporally_with). fd-polynesian-wayfinding-star-path found it through path reliability -- agents cannot distinguish high-confidence traversals from speculative ones.

**Recommendation:** Every cross-system relationship must carry: source subsystem, method (explicit-reference, temporal-cooccurrence, identifier-match, string-similarity), confidence level (confirmed, probable, speculative), evidence list, and timestamp. Agents must be able to filter by confidence. Low-confidence matches are surfaced as candidates, not asserted as facts.

### P0-3: Ontology as hard runtime dependency violates fail-open philosophy

**Agents:** fd-agent-ontology-runtime (Track A), fd-composition-coupling-philosophy (Track A), fd-polynesian-wayfinding-star-path (Track C)
**Tracks:** A, C (2/4)

If agents adopt the ontology as their primary query interface, it becomes a single point of failure. PHILOSOPHY.md explicitly requires fail-open independence: "Standalone plugins fail-open, degrade gracefully without intercore." Before the ontology, agents have 4 independent query tools (cass, beads, tldr-code, grep) with independent failure modes. After the ontology, a single graph database crash takes out all cross-system queries simultaneously. fd-polynesian-wayfinding-star-path frames this as the navigator who trusts only one signal source -- lost on cloudy nights.

**Recommendation:** The ontology must be strictly additive. Never deprecate direct tool access. Agent prompts include both paths: "Use the ontology for cross-system queries; fall back to direct tools if unavailable." The ontology fails silent (empty results), not loud (error propagation).

### P0-4: "Read-only projection" is a semantic dodge for a central store

**Agents:** fd-composition-coupling-philosophy (Track A), fd-spatial-data-infrastructure (Track B), fd-archival-provenance-linkage (Track B)
**Tracks:** A, B (2/4)

The brief frames the ontology as a "read-only projection" to avoid contradicting the "unify retrieval, not storage" principle. But a materialized graph projection IS a store: it has state, schema, infrastructure, and operational burden. fd-composition-coupling-philosophy applies the distinguishing test: if the projection database is deleted, can the system still answer cross-system queries? With a thin retrieval router, yes (slower, but functional). With a materialized projection, no. The projection IS the system of record for cross-system relationships, regardless of the "read-only" label. fd-spatial-data-infrastructure draws the parallel to Australia's national SDI, which attempted to warehouse state government geospatial data and abandoned it when agencies evolved schemas independently.

**Recommendation:** Honestly name the architectural choice. Evaluate two alternatives: (1) thin retrieval router (query dispatcher over existing backends, philosophy-compatible), or (2) materialized graph projection (separate database with CDC, philosophy-breaking but possibly justified). If option 2, update the philosophy to explain why this is an exception. The memory architecture convergence PRD already chose option 1 for the same problem at a different scope.

### P1 — Premature type hierarchy (5+ agents)

**Agents:** fd-ontology-schema-evolution (A), fd-entity-resolution-identity (A), fd-agent-ontology-runtime (A), fd-composition-coupling-philosophy (A), fd-heraldic-blazon-compositional-grammar (C), fd-dogon-po-tolo-seed-classification (D)

The 6 entity categories (Development, Work-tracking, Agent, Knowledge, Review, Infrastructure) conflate organizational convenience with ontological structure. A Discovery is both Knowledge and Work-tracking. A Session is Agent, Work-tracking, and potentially Knowledge after reflection. fd-heraldic-blazon-compositional-grammar counts ~30 bespoke entity types and warns the schema is a catalog, not a grammar. fd-dogon-po-tolo-seed-classification identifies the same gap: the type system is taxonomic (labels without derivation) rather than generative (category membership derives relationships).

**Recommendation:** Replace the 6 fixed categories with composable type primitives (~5 base types: Artifact, Process, Actor, Relationship, Evidence) from which entity types compose. New types inherit family-level interaction rules; per-type declarations are overrides only. Apply the blazon compositionality test: can the grammar describe a future entity type using existing primitives?

### P1 — No schema evolution strategy (4+ agents)

**Agents:** fd-ontology-schema-evolution (A), fd-clinical-terminology-harmonization (B), fd-heraldic-blazon-compositional-grammar (C), fd-burmese-bedin-planetary-relational-calculus (D)

In a weekly-shipping plugin ecosystem, a fixed ontology becomes a liability within months. The brief identifies "static vs. dynamic" as a tension but proposes no versioning mechanism. fd-clinical-terminology-harmonization warns of pre-coordination explosion: with 20 entity types, 15 relationship types, and 10 action types, the exhaustive schema has 3,000 entries. fd-ontology-schema-evolution notes that the closed-world assumption (the ontology declares what exists) is incompatible with the plugin ecosystem (new plugins silently create entity types).

**Recommendation:** Adopt an append-only schema model with open-world assumption. Types can be added and properties extended, never renamed or removed. The ontology discovers entity types by observing what subsystems report, not by requiring declaration. Relationship types are an open, namespaced registry (e.g., `interlens:inspired-by`, `interwatch:drift-detected`).

### P1 — No demonstrated capability delta over existing tools

**Agents:** fd-agent-ontology-runtime (A), fd-composition-coupling-philosophy (A)
**Tracks:** A

The brief asks "What capabilities does an ontology graph unlock that are impossible without one?" but does not answer it. fd-agent-ontology-runtime performs the side-by-side analysis: "show me everything related to X" costs ~800 tokens via 4 existing tool calls (cass, beads, tldr-code, grep) with ~5s latency, versus ~500-2000 tokens via 1 ontology query with similar latency plus the bootstrap cost of learning the query schema. The one clear win is cross-system causal chains ("why did this test fail?"), but this is achievable with a thinner join layer. The MAGMA multi-graph memory assessment reached an "inspire-only" verdict for structurally identical reasons; the brief does not explain why this case is different.

**Recommendation:** Identify 3-5 concrete agent workflows where the ontology provides >2x improvement over existing tools, with token cost estimates. If no such workflows exist, the ontology solves a human UX problem, not an agent capability problem.

### P1 — Unbounded traversal with no query cost model

**Agents:** fd-graph-query-runtime (A), fd-entity-resolution-identity (A), fd-agent-ontology-runtime (A)
**Tracks:** A

"Show me everything connected to this function" is an unbounded breadth-first traversal. At hop 1: ~20 nodes. Hop 2: ~200. Hop 3: ~2000+. Hop 4: effectively the entire graph (small-world property). At agent runtime, this consumes the context window, costs significant tokens, and returns "everything" -- therefore communicating nothing useful.

**Recommendation:** Define a query cost model: max 2 hops for cross-system traversal, top-K results per hop (K=10), total result cap at 2000 tokens. Expose 5-10 named query templates ("related-beads", "recent-sessions", "review-findings") instead of open-ended traversal.

---

## Cross-Track Convergence

These findings appeared independently in 2+ tracks. Each was discovered through different reasoning at different semantic distances, making them the highest-confidence signals in the review.

### 1. Entity identity resolution is the hard problem (4/4 tracks)

- **Track A:** fd-entity-resolution-identity — five incompatible ID schemes (UUIDs, hex session IDs, file paths, symbol names, Notion page IDs) with no crosswalk. The headline "show me everything" query is impossible without mapping all references to canonical entities.
- **Track B:** fd-archival-provenance-linkage — authority control (canonical records) vs. entity resolution (ad-hoc matching) are conflated. fd-litigation-entity-mapping — person-entity deduplication absent; same developer appears as GitHub username, session UUID, and beads claimed_by string. fd-spatial-data-infrastructure — entity identifiers require a cross-reference mapping layer, not a unified ID namespace.
- **Track C:** fd-javanese-gamelan-ensemble-tuning — multi-typed entity representation absent; a file participates in code-graph, session-log, and beads-DAG with different structural significance. fd-heraldic-blazon-compositional-grammar — entity definitions are referential (pointers), not reconstructive (sufficient for reasoning).
- **Track D:** fd-petrographic-thin-section-entity-resolution — diagnostic properties (invariant across views, like extinction angle) vs. contingent properties (change per subsystem view, like interference color) not distinguished. Grain-boundary entities (commits, which span development and work-tracking) will create duplicate graph nodes without explicit resolution rules.

**Convergence score: 4/4.** This is the single highest-confidence finding. Every track, from every distance, independently identified entity resolution as the missing foundation. The frames differ -- identity crosswalks (A), authority control (B), multi-faceted entities (C), diagnostic invariants (D) -- but the structural diagnosis is identical.

### 2. The type system must be compositional, not enumerative (4/4 tracks)

- **Track A:** fd-ontology-schema-evolution — 6 fixed categories cement premature hierarchy; replace with flat entity registry where types self-declare properties.
- **Track B:** fd-clinical-terminology-harmonization — pre-coordination trap: defining a schema entry for every entity-type x relationship-type x action-type combination produces combinatorial explosion. Adopt SNOMED CT's post-coordination model.
- **Track C:** fd-heraldic-blazon-compositional-grammar — the schema has ~30 bespoke types (a catalog) rather than ~5 composable primitives (a grammar). Apply the blazon compositionality test: can the grammar describe a future entity using existing primitives?
- **Track D:** fd-dogon-po-tolo-seed-classification + fd-burmese-bedin-planetary-relational-calculus — the type system is taxonomic (labels without derivation) rather than generative (category membership derives relationships via bummo interaction rules). O(N^2) relationship declarations required without a family-level relational calculus.

**Convergence score: 4/4.** Four independent intellectual traditions -- schema engineering, clinical informatics, medieval heraldry, and Dogon cosmology -- converge on the same structural recommendation: small set of composable primitives, relationships derived from type membership, new types inherit family rules.

### 3. Source failure and contradiction must be handled explicitly (3/4 tracks)

- **Track A:** fd-graph-query-runtime — materialized view refresh rate problem; agents querying immediately after a change get stale results.
- **Track B:** fd-clinical-terminology-harmonization — no freshness metadata; "no relationship exists" indistinguishable from "relationship not yet indexed." fd-spatial-data-infrastructure — no data currency metadata; agents cannot assess graph staleness per subsystem.
- **Track C:** fd-persian-qanat-subterranean-topology — false negatives indistinguishable from absence (dry shaft vs. blocked tunnel). fd-polynesian-wayfinding-star-path — queries block on slowest source with no progressive partial results; contradictory information silently resolved by query order.

**Convergence score: 3/4.** (Track D did not address this directly.) The converged recommendation: every query result carries per-subsystem freshness metadata (last_indexed, indexing_lag, completeness). Queries execute as parallel fan-out with progressive partial results. Contradictions are surfaced with source attribution, not silently resolved.

### 4. Cross-family entities need multi-membership, not single-type assignment (3/4 tracks)

- **Track A:** fd-ontology-schema-evolution — a "campaign" is simultaneously Work, Agent, and Infrastructure; single-parent hierarchy forces arbitrary classification.
- **Track C:** fd-javanese-gamelan-ensemble-tuning — a file participates in code-graph, session-log, and beads-DAG simultaneously; normalization to a single type destroys source-specific analytical semantics (the ombak).
- **Track D:** fd-dogon-po-tolo-seed-classification — twin-seed (ibu yala) entities participate fully in two bummo relationship portfolios. fd-burmese-bedin-planetary-relational-calculus — the Ketu/Rahu Wednesday split assigns different types to the same entity based on temporal context; entity type is a lifecycle state machine, not a fixed label. fd-petrographic-thin-section-entity-resolution — pleochroism: a Session viewed from interspect is a Review entity, from interstat a Cost entity, from cass a Knowledge entity.

**Convergence score: 3/4.** (Track B touched this through archival multi-level description but framed it as hierarchy rather than multi-membership.) The converged recommendation: entity type is multi-valued and lifecycle-aware. An entity's current family set determines which relational calculus rules apply. Transitions add family memberships without removing existing ones.

### 5. Observation depth and connector contracts must be specified (3/4 tracks)

- **Track B:** fd-spatial-data-infrastructure — minimum metadata threshold for participation undefined; subsystem developers face unknown adoption cost. fd-clinical-terminology-harmonization — no formality gradient; same schema rigor applied to stable types (Agent, Plugin) and fuzzy types (Discovery, Pattern).
- **Track C:** fd-persian-qanat-subterranean-topology — connectors list source systems but never specify what each actually indexes at what granularity. "Index session metadata" vs. "index tool call sequences" vs. "index file-level diffs" are different observation depths with different costs and different value.
- **Track D:** fd-heraldic-blazon-compositional-grammar — entity definitions are referential (pointers to source) not reconstructive (sufficient for agent reasoning).

**Convergence score: 3/4.** (Track A identified the problem as "closed-world assumption" but did not frame it as observation depth.) The converged recommendation: each connector declares an observation contract -- entity types indexed, granularity level, captured vs. inferred properties, refresh cadence. Define a minimum discovery threshold (4 fields: entity_type, entity_id, subsystem, created_at) and richer metadata as progressive enhancement.

### 6. The ontology should be a catalog-of-catalogs, not a data warehouse (2/4 tracks)

- **Track A:** fd-composition-coupling-philosophy — the "read-only projection" framing does not resolve the philosophy contradiction; the ontology must be a thin retrieval layer, not a thick projection layer.
- **Track B:** fd-spatial-data-infrastructure — catalog-of-catalogs pattern proven at national scale (ASDI, NSDI, INSPIRE). The ontology stores entity discovery records and relationship stubs; full data retrieval delegates to source subsystems. fd-archival-provenance-linkage — frame the ontology as a "finding aid generator" over subsystem collections; if deleting the ontology leaves every subsystem fully functional, the design is correct.

**Convergence score: 2/4.** (Tracks C and D did not address architectural pattern directly, though the qanat's observation-depth framing and the bedin's Mandalay-rigidity concern are compatible.) The converged recommendation: the ontology indexes metadata about entities in subsystem stores and returns pointers to authoritative data. It never owns entity data. Each subsystem publishes a self-described profile; the ontology indexes these for discovery without requiring conformance to a central type system.

### 7. Progressive adoption, not all-or-nothing (3/4 tracks)

- **Track A:** fd-agent-ontology-runtime — bootstrap problem; agents need schema knowledge in context before the ontology delivers value.
- **Track B:** fd-litigation-entity-mapping — no iterative enrichment model; big-bang indexing assumed. fd-spatial-data-infrastructure — partial coverage not addressed; graph assumes all-or-nothing rather than progressive value delivery.
- **Track C:** fd-persian-qanat-subterranean-topology — progressive observation deepening (v1 existence, v2 operations, v3 causality).

**Convergence score: 3/4.** The converged recommendation: Phase 1 creates coarse entity stubs (4-field minimum). Phase 2 adds relationship stubs between co-occurring entities. Phase 3 deep-indexes specific entities on demand. Define a coverage matrix showing which queries become available at each coverage level.

---

## Domain-Expert Insights (Track A)

### Theme: The philosophy contradiction is structural, not semantic

fd-composition-coupling-philosophy delivered the most penetrating single finding: the gravity well pattern. Phase 1: ontology is a read-only projection. Phase 2: new features designed "ontology-first." Phase 3: subsystems start reading from the ontology. Phase 4: the ontology is the de facto system of record. This trajectory is documented in SAP MDG, Palantir Foundry, and Salesforce metadata layer -- all started as "projections" and became systems of record within 3-5 years. The brief provides no structural safeguards. Recommended safeguards: no-write-through contract (write operations not implemented, period), staleness TTL (entities excluded from results if not refreshed within TTL), and quarterly dependency audit.

### Theme: Context window economics favor named queries over graph languages

fd-agent-ontology-runtime calculates: per ontology query costs ~800 tokens (schema discovery + query formulation + results), versus ~300 tokens for a focused `cass context` call. At 5-10 queries per sprint, the ontology consumes 9-18% of the tool result budget. The recommendation -- named commands (`related-beads`, `recent-sessions`, `review-findings`) that agents call without learning a schema -- eliminates the bootstrap problem and makes token costs predictable.

### Theme: Temporal identity is an unsolved hard problem for code entities

fd-entity-resolution-identity identifies that file paths and function names are mutable identifiers. When a function is renamed, moved, or split, all historical beads, sessions, and findings that referenced it are orphaned. Git's `--follow` handles file-level renames but not function-level. No existing tool solves cross-system temporal identity for code symbols. The pragmatic recommendation: track identity at file level (where git rename detection works) for the MVP and defer function-level temporal identity.

### Theme: The "Actions" concept creates TOCTOU races

fd-agent-ontology-runtime identifies that Palantir-style Actions (preconditions, effects, validation) create time-of-check/time-of-use races when the ontology is a read-only projection. Precondition checking happens in the projection; write operations go through source systems. A bead can appear available in the ontology but already be claimed in beads CLI. Recommendation: drop Actions from scope entirely. The ontology's value is read-only cross-system queries.

---

## Parallel-Discipline Insights (Track B)

### Archival science: Finding aids, authority files, and respect des fonds

fd-archival-provenance-linkage frames the ontology as a **finding aid** -- a document that describes a collection's contents without being the collection. This reframe makes the non-invasive design requirement testable: if deleting the ontology leaves every subsystem fully functional, the design is correct. The **authority file** pattern (a shared registry of canonical entity identifiers maintained by each subsystem's canonical owner, with consumers referencing it) is lighter than a full ontology and directly addresses "show me everything connected to X" without requiring schema convergence. The principle of **respect des fonds** ("the ontology must never require a subsystem to change its internal data model to be discoverable") translates PHILOSOPHY.md into a concrete design test.

### Health informatics: Binding strengths and ConceptMaps

fd-clinical-terminology-harmonization provides the **formality gradient** the ontology needs. FHIR's binding strength model (required/extensible/preferred/example) maps directly: core types (Agent, Plugin, Bead) get "required" binding with strict schemas; peripheral types (Discovery, Pattern) get "extensible" binding where subsystems may add fields and omit optional ones. The **ConceptMap** pattern (formal, versionable, directional mappings between concept systems with declared equivalence types) is the crosswalk primitive for mapping between subsystem schemas. The **interface terminology** distinction (natural-language query patterns mapped to formal graph traversals) solves the agent bootstrap problem.

### Geospatial SDI: Catalog-of-catalogs and harvesting

fd-spatial-data-infrastructure provides the most operationally concrete architecture: the **catalog-of-catalogs** pattern. The ontology stores entity type metadata, entity discovery records, and relationship stubs. Full data retrieval delegates to source subsystems via native APIs. The **minimum metadata threshold** (4 required fields: entity_type, entity_id, subsystem, created_at) prevents the adoption cliff. The **harvest model** (the ontology periodically crawls subsystem endpoints for metadata, requiring zero effort from data producers) achieves dramatically higher adoption than push-based registration. This directly addresses the concern that 60+ plugins will never voluntarily register their entities.

### E-discovery: Proportionality and confidence scoring

fd-litigation-entity-mapping provides the **proportionality** framework for deciding what to index: sample cross-system query patterns, measure hit rates per entity type and relationship type, then build only the top-3 patterns. The **confidence scoring** pattern (every computed relationship carries a confidence score that consumers use to prioritize) prevents the graph from overwhelming agents with speculative connections. The **bead-centric query paradigm** (organize everything around the bead as the central entity, analogous to litigation's "matter-centric" model) is the highest-value first query pattern.

---

## Structural Insights (Track C)

### Persian qanat: Observation depth as a first-class design dimension

**Source domain:** Iranian subterranean irrigation (qanat). The muqanni (qanat builder) knows that observation shafts show water level but not flow direction, flow direction but not blockage location. The value depends on shaft depth.

**Structural isomorphism:** The ontology's connectors are observation shafts into underground subsystems. A connector that indexes session metadata (start time, model, tokens) but not tool call sequences is a shallow shaft -- it tells you a session exists but not what it did. The brief lists source systems without specifying observation depth per connector.

**Mapping:** The "Connector Observation Contracts" addition -- for each source system, declare entity types indexed, granularity, captured vs. inferred properties, refresh cadence. This is the single highest-leverage addition to the concept brief (flagged by 5 of 8 Track B+C agents).

**Concrete improvement.** This suggests a specific design artifact (the observation contract table) that the concept brief should include.

### Javanese gamelan: Entity normalization destroys analytical ombak

**Source domain:** Gamelan ensemble tuning. The penyelaras (tuner) maintains intentional detuning (ombak) between paired instruments; the beating patterns carry musical information. Tuning all instruments to a single standard destroys the ensemble character.

**Structural isomorphism:** A commit as git-object (tree, parent, author) vs. beads-state-change (bead_id, transition) vs. session-output (session_id, tool_call_id) carries structurally different analytical information. Normalizing to a single "Commit" type is like tuning all gamelan instruments to equal temperament.

**Mapping:** Entities should carry source-specific type facets alongside any unified type. Queries can access the unified view OR any source-specific facet. This is the "multi-faceted entity" pattern that converges with petrographic thin-section analysis (Track D).

**Concrete improvement.** Also suggests the **query-context (pathet)** mechanism: "show me everything related to X" should return different salience orderings for debugging vs. planning vs. reviewing. This is a Track-C-unique finding not surfaced by any inner track.

### Heraldic blazon: Grammar test as acceptance criteria

**Source domain:** Heraldic blazon compositional grammar. A small set of field divisions, tinctures, ordinaries, charges, and positional terms describes any coat of arms -- including those that did not exist when the rules were written.

**Structural isomorphism:** The ontology schema has ~30 bespoke entity types (catalog). A compositional grammar with ~5 base types (Artifact, Process, Actor, Relationship, Evidence) would describe any entity type from existing primitives.

**Mapping:** The blazon also provides relationship constraints (the tincture rule: colour on colour and metal on metal are forbidden). The ontology equivalent: typed constraints on which entity types can participate in which relationship types. "produced-by: Evidence -> Process" is valid; "produced-by: Evidence -> Artifact" is not. Invalid traversals should be rejected at query time, preventing meaningless chains.

**Concrete improvement.** The **testable schema specification** -- two independent implementations should produce the same graph structure from the same input data -- is a quality gate the concept brief should adopt.

### Polynesian wayfinding: Graceful degradation and star paths

**Source domain:** Pacific island navigation. The pelu (master navigator) synthesizes multiple unreliable signals (stars, swells, bird flights, phosphorescence) into a coherent position estimate. No single signal is authoritative.

**Structural isomorphism:** The ontology queries 6+ subsystems, each with different availability, latency, and freshness. When one is down, the query should degrade gracefully rather than block.

**Mapping:** Progressive partial results (fast sources return immediately, slow sources update later, unavailable sources marked explicitly). Source reliability hierarchy (git -> high, cass -> medium, string-matching -> low) annotated on traversal paths. Pre-computed "star paths" -- documented, tested traversal routes for the top 10 agent queries.

**Open question:** The **etak reference frame** (the canoe is stationary, islands move past it) suggests optimizing the graph's primary traversal for the dominant agent query pattern. Should the graph optimize for entity-centric ("tell me about X"), relationship-centric ("what instances of pattern Y?"), or context-centric ("what matters for task Z?") traversal? Needs query pattern data to decide.

---

## Frontier Patterns (Track D)

### Dogon cosmology: Generative type system via bummo interaction rules

**Source domain:** Dogon bummo seed classification (Mali). 22 seed categories with family-level interaction rules that derive all entity relationships from category membership. Knowing that an entity is bummo-3 (fonio) tells you it is in productive combination with bummo-7, in conflict with bummo-5, and can undergo the "germination" transformation class -- without declaring any per-entity relationships.

**Why unexpected:** A West African cosmological classification system is about as far from software ontology design as possible. Yet the bummo system solves the exact O(N^2) relationship declaration problem: 6 entity families with ~15 family-pair interaction rules generate the complete relationship matrix, versus 576 type-pair declarations without the calculus.

**Specific mechanism:** Family interaction rules declared at the family level. New types inherit their family's rules automatically. Per-type declarations become overrides, not the primary mechanism. This reduces schema maintenance from O(type-pairs) to O(family-pairs) + O(exceptions).

**Design direction:** This opens a new direction. The concept brief does not describe any mechanism where declaring an entity's type automatically derives its relationship portfolio. The bummo calculus provides the missing architecture: a small, declarative rule set that generates the large, combinatorial relationship space. This converges with the bedin (below) and with Track C's blazon compositional grammar.

The Dogon agent also surfaced the **twin-seed (ibu yala)** mechanism for cross-family entities and the **fonio default category** open question: should untyped entities get a default type with a "related to everything, primary to nothing" relationship portfolio, or does this undermine the generative system?

### Optical mineralogy: Diagnostic invariants and grain-boundary resolution

**Source domain:** Petrographic thin-section entity resolution. A petrographer distinguishes diagnostic properties (extinction angle -- invariant across all microscope stage rotations) from contingent properties (interference color -- changes with every 1-degree rotation).

**Why unexpected:** Microscopic mineral identification through polarized light is a radically different domain. Yet the diagnostic-vs-contingent distinction maps precisely to the ontology's entity resolution problem.

**Specific mechanism:** For each entity family, declare the minimum invariant property set (the "extinction angle") that uniquely identifies an entity across all subsystem views: file -> path, bead -> bead_id, session -> session_id, commit -> SHA. All other properties are view-dependent and tagged with source subsystem. The **grain-boundary** concept (entities at subsystem interfaces like commits, which present different properties on each side of the contact) predicts exactly where duplicate graph nodes will appear and provides resolution rules.

**Design direction:** Refines an existing direction (entity resolution from Tracks A and B) with a more precise framework. The Michel-Levy chart analogy suggests a **materialized entity resolution index** -- a precomputed mapping from (subsystem, subsystem_id) to canonical_entity_id, updated incrementally. This makes runtime queries O(1) lookup instead of O(subsystems^2) cross-joins.

### Burmese bedin astrology: O(1) relational calculus and lifecycle type transitions

**Source domain:** Burmese bedin planetary classification. 8 planetary houses with 3 interaction rules (trine, opposition, square) generate all inter-entity relationships. Type assignment is deterministic from entity identifiers (name syllables map to houses).

**Why unexpected:** A Myanmar astrological system for computing interpersonal compatibility is far from software engineering. Yet the bedin solves the scalability problem: the complete relationship matrix for all entities is generated from 8 types and 3 rules, not enumerated per pair.

**Specific mechanisms:** (1) The **Ketu/Rahu Wednesday split** -- the same temporal position yields different type assignments based on context -- maps to lifecycle-dependent type transitions. A Session is an Agent entity while executing, gains Work-tracking family membership when a bead links, gains Knowledge family membership after reflection distillation. (2) The **Nat overlay** -- runtime relationships that override schema-derived defaults, tracked separately, linked to justification, automatically cleared when the condition ends -- maps to temporary relationship overrides during refactoring sprints or debugging sessions. (3) **Deterministic type assignment from identifiers** (file path patterns map to entity families) provides zero-maintenance type assignment for 80%+ of entities. (4) The **Mandalay problem** -- a materialized view of the calculus creates rigidity when rules change -- recommends rule-indexed materialization (invalidate only entries generated by the changed rule) over entity-indexed (full rebuild).

**Design direction:** The bedin opens a genuinely new design direction: **family-level relational calculus as the primary relationship mechanism**. Combined with the Dogon bummo rules, this produces a two-tier system: Tier 1 is family-pair interaction rules (~15 rules covering 80% of relationships), Tier 2 is type-specific overrides for exceptions. New types inherit Tier 1 automatically. This converges with Track C's blazon grammar and Track B's SNOMED CT post-coordination -- four completely independent knowledge domains arriving at the same architecture.

---

## Synthesis Assessment

**Overall assessment.** The concept brief identifies a real fragmentation problem -- 6+ subsystems with siloed entity spaces and no cross-system query capability. But the proposed solution is premature: it designs a graph schema before understanding actual query patterns, contradicts the project's core "unify retrieval, not storage" philosophy without acknowledging the contradiction, and leaves the hardest problem (entity resolution across 5+ incompatible ID schemes) entirely unaddressed. The solution shape is correct (agents need cross-system context); the solution scope is wrong (full ontology graph when a thin retrieval router may suffice).

**Highest-leverage insight.** Entity identity resolution is the foundational layer that must precede any graph design. 4 of 4 tracks independently arrived at this. The concept brief treats identity as a solved prerequisite ("objects link to other objects") when it is the hardest unsolved problem in the proposal. Every dollar spent on graph schema, query engines, or materialized views is wasted until the identity crosswalk exists. Build the crosswalk first; the graph structure becomes obvious once you can actually connect entities across subsystems.

**Most surprising finding.** The convergence across Tracks C and D on a **family-level relational calculus** -- where 3-6 interaction rules between entity families generate the complete relationship matrix, and new types inherit rules automatically. This was independently discovered by Dogon cosmology (bummo seed interactions), Burmese astrology (planetary house rules), heraldic blazon (compositional grammar with tincture constraints), and clinical informatics (post-coordination). Four knowledge domains spanning six continents and twenty centuries, each solving the same problem of generating a large combinatorial space from a small declarative rule set. No inner track (A or B) surfaced this architectural pattern; the domain experts focused on what was wrong with the proposed type system rather than proposing a generative alternative.

**Semantic distance value.** The outer tracks (C/D) contributed qualitatively different insights from the inner tracks (A/B). Tracks A and B diagnosed deficiencies (missing entity resolution, philosophy contradiction, no query cost model). Tracks C and D proposed alternative architectures (generative type calculus, observation depth contracts, query-context salience, graceful degradation with star paths, materialized resolution indexes). The most actionable architectural recommendations -- composable type primitives, family interaction rules, progressive observation deepening, diagnostic-vs-contingent property distinction -- came from the outer tracks. The inner tracks would not have surfaced these because domain experts reason within the existing paradigm; distant-domain agents reason by structural analogy, which produces novel solutions to the same problems.

**Recommended path forward.**

1. **Instrument before building** (2 weeks). Add telemetry to cass, beads, tldr-code, grep that logs which cross-system queries agents attempt. After 30 days, analyze which subsystem pairs are co-queried and which queries fail.

2. **Build entity resolution first** (4 weeks). Implement a materialized identity crosswalk for file-level entities using structured links that already exist (cass file paths, git commit SHAs, beads bead_ids, flux-drive finding file references). Defer function-level and NLP-based resolution.

3. **Deploy a thin retrieval router** (4 weeks). Build a query dispatcher that hits 2-3 backends (beads, cass, intercore) and merges results. Expose as named commands: `related-beads <file>`, `recent-sessions <file>`, `review-findings <file>`. No graph database. No CDC. No schema management. This is the philosophy-compatible implementation.

4. **Evaluate and expand** (2 weeks). After phases 1-3, measure: do the named queries satisfy 80% of cross-system query needs? If yes, stop -- the thin router is sufficient. If no, the telemetry data reveals exactly which entity types and relationships to add, and the identity crosswalk provides the foundation for a graph if warranted.

5. **If a graph is warranted, adopt the generative architecture.** Use ~5 composable type primitives, family-level interaction rules (~15 rules), multi-family lifecycle membership, observation depth contracts per connector, and confidence scoring on every cross-system link. This is the architecture that 4 of 4 tracks converged on from maximally different reasoning paths.
