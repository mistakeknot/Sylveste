# Flux-Drive Synthesis: Ontology Graph Concept Brief

**Target:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`
**Date:** 2026-04-04
**Agents:** 3 esoteric-domain specialists (Dogon cosmology, petrographic mineralogy, Burmese bedin astrology)
**Mode:** Review (frontier cross-domain structural isomorphisms)

---

## Cross-Agent Convergence

Three agents from maximally distant knowledge domains converged independently on the same structural diagnosis. This convergence is the strongest signal in the review.

### Convergence Point 1: The type system must be generative, not taxonomic

All three agents identified the same core deficiency from entirely different angles:

| Agent | Domain Mechanism | Diagnosis |
|-------|-----------------|-----------|
| **Dogon** | Bummo seed categories derive all relationships from category membership | The proposed type system labels entities but does not derive relationships from type |
| **Petrographic** | Diagnostic properties (extinction angle) are invariant across observation frames; contingent properties (interference color) change per view | The proposed type system does not distinguish identity-bearing from view-dependent properties |
| **Bedin** | 8 planetary houses + 3 interaction rules generate the complete relationship matrix for all entities | The proposed type system requires O(N^2) individual relationship declarations |

**Unified recommendation:** The ontology graph needs a **family-level relational calculus** -- a small set of interaction rules between entity families (6 families, ~15 family-pair rules) from which per-type relationships are derived. New types inherit their family's interaction rules automatically. Per-type declarations become overrides, not the primary mechanism.

### Convergence Point 2: Cross-type entities need structural dual classification

Two agents converged independently on the same problem:

| Agent | Domain Mechanism | Diagnosis |
|-------|-----------------|-----------|
| **Dogon** | Twin-seed (ibu yala) entities participate fully in two bummo relationship portfolios | Cross-family entities (Discovery, Session) need multi-family membership, not primary-type flattening |
| **Bedin** | Ketu/Rahu Wednesday split assigns different types to the same entity based on context | Entity type must be lifecycle-aware -- a Session gains Knowledge-family relationships after distillation without losing Agent-family relationships |

**Unified recommendation:** Entity type is not a fixed label but a **lifecycle state machine** with multi-family membership. An entity's current family set determines which relational calculus rules apply. Transitions (creation -> completion -> distillation) add family memberships.

### Convergence Point 3: The materialized view needs incrementality and staleness detection

| Agent | Domain Mechanism | Diagnosis |
|-------|-----------------|-----------|
| **Dogon** | Redundant schema embedding across agriculture, ritual, architecture detects drift | Schema coherence requires redundant signals, not a single canonical source |
| **Petrographic** | Michel-Levy chart precomputes birefringence lookups for runtime efficiency | Entity resolution needs a materialized index, not real-time cross-subsystem joins |
| **Bedin** | Mandalay's city layout materializes the calculus but creates rigidity | The materialized graph must be rule-indexed for incremental updates, not entity-indexed (which requires full rebuild) |

**Unified recommendation:** Build a **materialized entity resolution index** (the Michel-Levy chart) that is rule-indexed (not entity-indexed) so changes to family interaction rules propagate incrementally. Assemble the schema from subsystem-local declarations (not a central file) so drift is structurally impossible.

---

## Unique Contributions Per Agent

Beyond the convergences, each agent surfaced mechanisms the others would have missed:

### Dogon-only: The fonio default category (Finding 5)
What type do unclassifiable entities get? The Dogon system has no "untyped" -- everything belongs to a bummo, with fonio serving as the default category for entities that resist classification. The ontology graph must decide whether untyped entities are invisible (dangerous) or get a default type (risks undermining the generative system). This is an open design question, not a defect.

### Petrographic-only: Grain-boundary entity duplication (Finding 2)
Entities at subsystem interfaces (commits, which live at the development/work-tracking boundary) will create duplicate graph nodes unless explicit boundary resolution rules exist. The petrographic grain-boundary concept is uniquely precise here: the same entity presents different properties on each side of the subsystem contact, and only invariant properties (the extinction angle) can unify them.

### Petrographic-only: Minimum invariant set per entity type (Finding 5)
Each entity family has an "extinction angle" -- the minimum property sufficient for identity resolution. Most have stable IDs (bead_id, session_id). Development entities are the exception: file paths and function names are mutable, making entity resolution fragile across renames and refactors.

### Bedin-only: The Nat overlay for runtime relationship overrides (Finding 3)
Schema-derived relationships are the baseline, but runtime conditions (refactoring sprints, debugging sessions, migration work) create temporary relationships that contradict the schema. The bedin's Nat spirit overlay is a structurally clean mechanism: overrides are tracked separately, linked to their justification, and automatically cleared when the condition ends.

### Bedin-only: Deterministic type assignment from identifiers (Finding 4)
The bedin assigns type from name syllables -- deterministic, zero-maintenance, never stale. The ontology graph can do the same: `core/**` = development, `.beads/**` = work-tracking, `interverse/**` = infrastructure. Pattern-based assignment covers 80%+ of entities; explicit declarations handle the rest.

---

## Consolidated Finding Table

| # | Severity | Finding | Agents | Convergent? |
|---|----------|---------|--------|-------------|
| 1 | **P1** | Type system is taxonomic, not generative -- no family-level relational calculus | Dogon, Bedin | YES |
| 2 | **P1** | Cross-type entities need structural dual classification (twin-seed / Ketu) | Dogon, Bedin | YES |
| 3 | **P1** | No diagnostic vs. contingent property distinction for entity resolution | Petrographic | Unique |
| 4 | **P1** | Grain-boundary entities will create duplicate graph nodes | Petrographic | Unique |
| 5 | **P2** | No materialized entity resolution index (Michel-Levy chart missing) | Petrographic, Bedin | YES |
| 6 | **P2** | Schema coherence lacks redundant embedding / drift detection | Dogon | Unique |
| 7 | **P2** | Runtime relationship overrides unmodeled (Nat overlay) | Bedin | Unique |
| 8 | **P2** | Type assignment not deterministic from identifiers | Bedin | Unique |
| 9 | **P2** | Entities change apparent type across subsystem views (pleochroism) | Petrographic | Unique |
| 10 | **P2** | Materialized graph needs rule-indexed incrementality (Mandalay) | Bedin | Unique |
| 11 | **P3** | Completeness question for untyped entities (fonio default) | Dogon | Unique |
| 12 | **P3** | Minimum invariant set per entity type not identified | Petrographic | Unique |

---

## Architectural Recommendation

The three domain isomorphisms converge on a single architectural pattern for the ontology graph:

```
Layer 1: Identity Anchors (petrographic extinction angles)
  - Per-entity-type invariant properties for cross-subsystem resolution
  - Materialized into a resolution index (Michel-Levy chart)

Layer 2: Family Relational Calculus (bedin planetary rules / Dogon bummo interactions)
  - 6 entity families, ~15 family-pair interaction rules
  - New types inherit family rules, declare overrides only
  - O(family-pairs) maintenance, not O(type-pairs)

Layer 3: Multi-Family Membership (Dogon twin-seeds / bedin Ketu split)
  - Entities participate in multiple families via lifecycle state machine
  - Type transitions add family memberships without removing existing ones
  - Relational calculus applies to current family set

Layer 4: Schema Assembly (Dogon redundant embedding)
  - Each subsystem declares its own entity types and relationships locally
  - Ontology graph assembles from fragments -- no central canonical schema
  - Drift is structurally impossible

Layer 5: Runtime Override (bedin Nat overlay)
  - Overrides tracked separately from schema-derived relationships
  - Linked to justification (bead, sprint, session)
  - Automatically cleared when justification resolves
```

This architecture aligns with the project's "unify retrieval, not storage" philosophy: each subsystem keeps its own storage and declares its own schema fragments. The ontology graph unifies retrieval through a materialized resolution index and a family-level relational calculus, without requiring any subsystem to migrate its data or conform to a central schema.

---

## Verdict

The concept brief identifies the right problem (fragmented entity graphs across 6+ subsystems) and the right philosophical constraint ("unify retrieval, not storage"). The three esoteric-domain reviews converge on the same structural gap: the brief describes a **taxonomic labeling system** when what it needs is a **generative relational calculus**. The difference is between a phone book (look up each pair individually) and a periodic table (derive interaction properties from group and period membership).

The five-layer architecture above (identity anchors, relational calculus, multi-family membership, schema assembly, runtime overrides) provides the generative mechanism the concept brief is missing, while respecting the composition-over-capability philosophy.
