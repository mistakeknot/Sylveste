# fd-dogon-po-tolo-seed-classification -- Findings

**Target:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`
**Agent:** fd-dogon-po-tolo-seed-classification (Mali Dogon cosmology: generative type systems)
**Decision Lens:** Evaluates whether the type system is generative (category membership derives relationships) or taxonomic (labels that group without deriving). Also evaluates dual-classification and relationship algebra.

---

## Finding 1: The type system as described is taxonomic, not generative

**Severity: P1**
**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 18-28

The concept brief lists 6 entity families with 20+ entity types, then proposes "Typed Schema + Actions" (line 47) where entity types have "declared capabilities, constraints, and allowed actions." This is a taxonomic system -- each type is a label with manually attached properties. There is no mechanism described where declaring an entity as type `Agent` would automatically derive its relationship portfolio (dispatched_by, consumed_tool, produced_artifact) from the Agent family's interaction rules.

**The Dogon structural isomorphism:** In the bummo system, knowing that an entity belongs to the fonio-seed category (bummo 3) tells you it is in productive combination with bummo 7 (earth-seed) and bummo 1 (millet-seed), in conflict with bummo 5 (bean-seed), and can undergo the "germination" transformation class. None of these relationships are declared per-entity -- they are derived from bummo membership. The concept brief's type system has no equivalent derivation engine. Adding a new entity type (e.g., "Checkpoint" in the work-tracking family) would require manually declaring its relationships to Session, Bead, Sprint, Agent, and every other type it interacts with.

**Failure scenario:** The platform adds a 7th entity family ("Governance" -- policies, budgets, approval chains). Every existing type must be manually wired to the new family's types. With 20+ existing types and 5+ new governance types, this means 100+ relationship declarations, most of which follow predictable family-level patterns (governance entities "authorize" agent entities, "constrain" infrastructure entities, "scope" work-tracking entities). Without a generative mechanism, these patterns must be enumerated individually, and the enumerations will be incomplete from day one.

**Smallest viable fix:** Add a "family interaction rules" declaration layer above the type schema. Instead of declaring relationships per type-pair, declare interaction rules per family-pair:

```yaml
family_interactions:
  agent <-> work_tracking: [tracked_by, produced_in, dispatched_for]
  agent <-> development: [modified, read, tested]
  knowledge <-> work_tracking: [discovered_during, applied_in]
```

New types inherit their family's interaction rules. Per-type relationships become overrides, not the primary declaration mechanism. This reduces schema maintenance from O(type-pairs) to O(family-pairs) + O(exceptions).

---

## Finding 2: No dual-classification mechanism for cross-family entities

**Severity: P1**
**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 18-28, 46-48

The concept brief lists entity families as disjoint categories. But several entities genuinely participate in multiple families: a Discovery is both a Knowledge entity (voice, lens, evidence) and a Work-tracking entity (linked to beads, sessions). A Session is both an Agent entity (tool calls, model invocations) and a Work-tracking entity (sprint context, bead link) and potentially a Knowledge entity (after reflection distills learnings). The brief does not describe how cross-family entities work.

**The Dogon structural isomorphism:** The Dogon handle this through "twin seeds" (ibu yala) -- entities that genuinely carry dual bummo classification. A twin-seed entity participates fully in both relationship portfolios. Critically, twin-seed status is a structural property of the entity, not an ad-hoc annotation. The twin-seed mechanism preserves generative derivation for both classifications: the entity's relationships from bummo 3 AND bummo 7 are both derived automatically, not declared individually.

**Failure scenario:** A Discovery entity is classified as a Knowledge entity (primary type). An agent queries "show me all work-tracking entities related to sprint S" -- the Discovery does not appear because it is not typed as work-tracking, even though it was discovered during that sprint and is linked to a bead. The agent must know to also query Knowledge entities and manually check bead links -- defeating the purpose of the unified graph.

**Smallest viable fix:** Add explicit multi-family membership as a first-class schema concept. An entity declares its family memberships (not a single primary type), and the relationship algebra applies for each membership:

```yaml
entity_types:
  Discovery:
    families: [knowledge, work_tracking]
    # Inherits interaction rules from BOTH families
  Session:
    families: [agent, work_tracking, knowledge]
    lifecycle_transitions:
      - from: [agent] to: [agent, work_tracking] when: bead_linked
      - from: [agent, work_tracking] to: [agent, work_tracking, knowledge] when: reflection_distilled
```

---

## Finding 3: Schema coherence through redundant embedding is absent

**Severity: P2**
**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 57-61

The design tensions section (lines 57-61) identifies "inference vs. declaration" but does not address schema staleness detection. The brief asks whether the graph should be "a read-only projection (materialized view)" (line 66) but does not describe how the projection detects that its source schema has drifted.

**The Dogon structural isomorphism:** The Dogon classification system survived centuries of oral transmission without a canonical written schema because the same classification principles are embedded redundantly across multiple cultural domains -- agriculture (seed categories), architecture (house orientation), ritual (sacrifice sequences), social organization (kinship categories), and astronomy (star associations). If the agricultural embedding drifts from the ritual embedding, the inconsistency is detectable because practitioners encounter the same classification in multiple contexts. The schema IS the redundancy.

In the concept brief, the ontology schema would be declared in one place (a schema file or registry). When the beads subsystem adds a new relationship type (e.g., "conditional-blocks" -- which already exists in beads per line 37) that is not reflected in the ontology schema, there is no cross-referencing mechanism to detect the drift. The schema file says one thing, the subsystem does another, and the gap grows silently.

**Failure scenario:** Beads adds a "discovered-from" relationship type (which it already has per line 37). The ontology schema declares only 4 of beads' 6 relationship types. Agents querying the ontology for "what relationship types exist between beads?" get an incomplete answer. The ontology becomes a stale subset of reality -- the exact failure mode that the "unify retrieval, not storage" philosophy was designed to avoid.

**Smallest viable fix:** Each subsystem declares its own entity types and relationships in a local schema fragment (like beads already implicitly does with its 6 relationship types). The ontology graph is assembled from these fragments, not from a separate canonical file. Schema drift becomes structurally impossible because the schema IS the subsystem declarations. This aligns with the "unify retrieval, not storage" philosophy -- the ontology unifies retrieval of schema information without requiring subsystems to migrate their schema declarations to a central registry.

---

## Finding 4: Relationship algebra is the missing multiplier

**Severity: P2**
**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 41-54

The three capabilities (Unified Entity Graph, Typed Schema + Actions, Agent-Queryable Relationships) are described independently. The brief does not describe a relationship algebra -- rules that compute valid relationship types between any two entities from their type memberships.

**The Dogon structural isomorphism:** In the bummo system, the interaction between bummo 3 and bummo 7 is "productive combination." This rule generates the relationship for EVERY entity-pair where one is bummo-3 and the other is bummo-7, without enumerating the pairs. The algebra has only 4 interaction types (productive, conflictual, neutral, transformative) applied across 22 x 22 category pairs = 484 relationships, all derived from ~40 inter-bummo rules (not 484 individual declarations).

For the ontology graph: 6 entity families with an average of 4 types each = 24 types. Full pairwise relationships = 576 type-pairs. A relationship algebra with 15 family-pair rules (6 choose 2 = 15) plus ~30 type-level overrides would cover the same space. Without the algebra, someone must write and maintain 576 relationship declarations -- and every new type adds 48 more.

**Smallest viable fix:** Define the interaction rules at the family level:

| Family A | Family B | Default Relationship Types |
|----------|----------|--------------------------|
| development | work_tracking | tracked_by, implemented_in |
| development | agent | modified_by, read_by |
| agent | work_tracking | dispatched_for, produced_during |
| knowledge | agent | discovered_by, applied_by |
| knowledge | review | evidenced_by, calibrated_from |
| review | agent | evaluated, gated |

Per-type declarations become overrides to these defaults, not the primary mechanism.

---

## Finding 5: The "everything has a type" completeness question

**Severity: P3**
**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 18-28

The brief lists 6 entity families. Does the 'everything has a type' assumption hold? Several real-world entities resist clean classification: configuration files (development entity? infrastructure entity?), environment variables (infrastructure? agent context?), error messages (development? review? agent?), temporary scaffolding (no stable type).

**The Dogon structural isomorphism:** The Dogon system classifies everything -- there is no "untyped" entity. The fonio seed (the smallest cultivated grain in the Dogon agricultural system) serves as the default classification for entities that resist categorization: small, numerous, foundational, not obviously important. The fonio-bummo is not a "miscellaneous" category -- it has a full relationship portfolio like any other bummo. Its generative power is that it produces "combinatorial" relationships: fonio-classified entities are compatible with almost everything but dominant over nothing.

Does the concept brief need a similar "fonio category" -- a default type for entities that resist classification, with a relationship portfolio that means "related to everything, primary to nothing"? Or would this undermine the generative type system by becoming a catch-all that short-circuits the derivation engine?

This is a genuine open question, not a defect.

---

## Summary

| # | Severity | Finding | Core Dogon Mechanism |
|---|----------|---------|---------------------|
| 1 | P1 | Type system is taxonomic, not generative | Bummo derivation engine |
| 2 | P1 | No dual-classification for cross-family entities | Twin-seed (ibu yala) |
| 3 | P2 | No redundant schema embedding for drift detection | Multi-domain classification redundancy |
| 4 | P2 | Relationship algebra missing | Bummo interaction rules |
| 5 | P3 | Completeness question for untyped entities | Fonio default category |
