# fd-burmese-bedin-planetary-relational-calculus -- Findings

**Target:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`
**Agent:** fd-burmese-bedin-planetary-relational-calculus (Myanmar astrology: relational calculus from O(1) category rules)
**Decision Lens:** Evaluates whether relationships are computed from type-level rules (O(1) per query) or enumerated per pair (O(N^2) declarations). Also evaluates context-dependent type transitions, runtime overrides, deterministic type assignment, and materialized graph incrementality.

---

## Finding 1: The ontology as described requires O(N^2) relationship declarations

**Severity: P1**
**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 47-48, 18-28

The concept brief proposes "Typed Schema + Actions" (lines 47-48) with "declared capabilities, constraints, and allowed actions" per entity type. With 6 entity families containing 20+ types (lines 18-28), this schema must declare the valid relationships between each pair of types. The brief does not describe a mechanism to derive relationships from type membership -- every relationship must be individually registered.

**The bedin structural isomorphism:** The Burmese bedin system assigns every entity to one of 8 planetary houses (with the Ketu intercalary as the 8th). ALL inter-entity relationships are derived from three house-level interaction rules: **trine** (every-third: harmonious), **opposition** (diametrically opposite: conflictual), **square** (adjacent: neutral-tending-negative). You never declare "person A born on Tuesday and person B born on Friday are compatible" -- you compute it: Tuesday = Mars house, Friday = Venus house, Mars-Venus is trine = harmonious. The complete relationship matrix for all entities in the cosmos is generated from 8 house types and 3 interaction rules.

The concept brief's schema has no equivalent computation. To state valid relationships between File and Bead, between Session and Discovery, between Plugin and Tool -- each must be explicitly declared. The brief lists 6 entity families; the bedin equivalent would be 6 "houses" with interaction rules:

- development <-> agent: "modification" relationship (agents modify development entities)
- agent <-> work_tracking: "execution" relationship (agents execute work)
- knowledge <-> review: "evidentiary" relationship (knowledge provides evidence for review)
- work_tracking <-> development: "implementation" relationship (work tracks development)

From 6 families and 3-4 interaction types, you derive the relationship matrix for all 20+ types. Without this calculus, adding the 21st type requires up to 20 new relationship declarations.

**Failure scenario:** The platform adds "Checkpoint" as a new work-tracking entity (snapshot of sprint state for governance). Without a relational calculus, someone must declare: Checkpoint-relates-to-Session, Checkpoint-relates-to-Bead, Checkpoint-relates-to-Agent, Checkpoint-relates-to-File (via changed files), Checkpoint-relates-to-Discovery (via captured learnings), Checkpoint-relates-to-Plugin (via active plugins), and so on. Each declaration is simple, but the combinatorial burden grows with every new type. Meanwhile, the bedin would automatically derive: Checkpoint is work_tracking house, therefore it has "execution" relationships with all agent-house entities and "implementation" relationships with all development-house entities.

**Smallest viable fix:** Implement a two-tier relationship declaration:

**Tier 1 -- Family calculus** (3-6 rules covering 80% of relationships):
```yaml
relational_calculus:
  rules:
    - families: [agent, development]
      relationship: modifies
      directionality: agent -> development
    - families: [agent, work_tracking]
      relationship: executes_within
      directionality: agent -> work_tracking
    - families: [knowledge, work_tracking]
      relationship: discovered_during
      directionality: knowledge -> work_tracking
    - families: [review, agent]
      relationship: evaluates
      directionality: review -> agent
    - families: [infrastructure, agent]
      relationship: provides_capability
      directionality: infrastructure -> agent
```

**Tier 2 -- Type-specific overrides** (for relationships that deviate from family defaults):
```yaml
overrides:
  - types: [test, file]
    relationship: validates  # More specific than generic "modifies"
  - types: [discovery, bead]
    relationship: caused_by  # More specific than "discovered_during"
```

New types inherit Tier 1 rules from their family. Tier 2 overrides are optional refinements.

---

## Finding 2: The Ketu problem -- context-dependent type transitions are unaddressed

**Severity: P1**
**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 56-61

The "Design Tensions" section (lines 56-61) mentions "Static vs. dynamic: A code ontology changes every commit" but frames this as a freshness problem, not a type-transition problem. The deeper issue is that entity type itself is context-dependent.

**The bedin structural isomorphism:** In the bedin, Wednesday is split between two planetary houses: entities associated with Wednesday before midday belong to Rahu's house (the ascending node), entities after midday belong to Ketu's house (the descending node). The SAME temporal position -- Wednesday -- yields different type assignments depending on temporal context. This is not an error or edge case; it is a designed feature of the system. The Ketu/Rahu split is the bedin's mechanism for handling entities that resist clean single-house assignment.

In the ontology graph, several entity types undergo lifecycle transitions that change their type participation:

| Entity | Phase 1 | Transition Event | Phase 2 |
|--------|---------|-----------------|---------|
| Session | Agent entity (executing) | Sprint closes | Work-tracking entity (historical) |
| Session | Agent entity (executing) | Reflection distills learnings | Knowledge entity (distilled) |
| Bead | Work-tracking entity (in-progress) | Close event | Review entity (archival evidence) |
| File | Development entity (source) | Deployment | Infrastructure entity (deployed artifact) |
| Discovery | Knowledge entity (raw) | Applied in implementation | Development entity (embodied pattern) |

If entity type is fixed at creation, the ontology graph cannot represent these transitions. A Session created as "Agent entity" remains forever an Agent entity, even after its learnings are distilled and its sprint is closed. Queries targeting Knowledge entities will never find distilled sessions.

**Failure scenario:** An agent running `/clavain:reflect` asks the ontology graph "what knowledge was produced during sprint S7?" The graph returns Discoveries (typed as Knowledge) but not Sessions (typed as Agent, even though they contain distilled learnings). The reflection is incomplete because the ontology's fixed type assignment prevents Sessions from participating in Knowledge-family queries after distillation.

**Smallest viable fix:** Model entity type as a lifecycle state machine, not a fixed label:

```yaml
lifecycle:
  Session:
    states:
      - active: families: [agent]
      - completed: families: [agent, work_tracking]
      - distilled: families: [agent, work_tracking, knowledge]
    transitions:
      - from: active, to: completed, when: sprint_close
      - from: completed, to: distilled, when: reflection_complete
```

The relational calculus applies to the entity's CURRENT family set, not its creation-time type. When a Session transitions from "active" to "distilled," it gains Knowledge-family relationships without losing Agent-family relationships.

---

## Finding 3: The Nat overlay -- runtime relationship overrides are unmodeled

**Severity: P2**
**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 57-58

The brief mentions "inference vs. declaration" (line 58) but does not address the case where runtime conditions create relationships that contradict the schema-derived defaults.

**The bedin structural isomorphism:** The bedin's planetary calculus provides the baseline relational system. But Nat spirits -- pre-Buddhist supernatural entities integrated into the cosmology -- can override planetary relationships under specific ritual conditions. A planetary opposition (conflictual relationship between Tuesday-Mars and Saturday-Saturn) can be neutralized by appropriate Nat propitiation. The override is:
- **Tracked separately** from the planetary baseline (the Nat hierarchy is a distinct system)
- **Temporary** (the override lasts as long as the ritual condition persists)
- **Reversible** (when the condition ends, the planetary baseline reasserts)

In the ontology graph, runtime conditions can create relationships that violate schema defaults:
- During a refactoring sprint, a Skill that "belongs_to" Plugin A is temporarily extracted to Plugin B. The schema says Skills belong to one Plugin; the runtime reality says this Skill now belongs to two (or is in transit between them).
- A Plugin that is normally "independent" of another Plugin becomes temporarily "blocked_by" it during a coordinated release.
- An Agent that normally has "no relationship" with a specific File becomes "watching" it during a debugging session.

These are Nat overrides -- runtime relationships that exist alongside (and sometimes contradict) schema-derived relationships.

**Failure scenario:** Plugin `interflux` is being refactored: the `flux-drive` skill is being extracted to a new plugin `interflux-core`. During the migration:
- The schema says `flux-drive belongs_to interflux`
- The runtime reality is that `flux-drive` has been moved to `interflux-core` but `interflux` still references it
- Queries for "what skills does interflux have?" return stale results because the schema override is not tracked

Without a Nat-overlay mechanism, the ontology graph has no way to represent "this relationship is temporarily different from what the schema says."

**Smallest viable fix:** Add an override layer that is tracked separately from schema-derived relationships:

```yaml
runtime_overrides:
  - entity: flux-drive
    schema_relationship: belongs_to(interflux)
    override_relationship: belongs_to(interflux-core)
    reason: "refactoring: skill extraction sprint S8"
    created: 2026-04-04T19:00:00Z
    expires: null  # Cleared when migration bead closes
    bead_link: sylveste-abc
```

The query layer returns `override_relationship` when an active override exists, `schema_relationship` otherwise. Overrides link to their justification (a bead, a sprint, a debugging session) and can be automatically cleared when the justification resolves.

---

## Finding 4: Deterministic type assignment from entity identifiers

**Severity: P2**
**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 18-28

The brief lists 6 entity families but does not describe how entities are assigned to families.

**The bedin structural isomorphism:** In the bedin, a person's planetary house is determined by the first syllable of their Burmese name. Each consonant is assigned to a specific house: ka/ga/nga = Monday = Moon, sa/za = Tuesday = Mars, la/wa = Wednesday-morning = Rahu, and so on. Type assignment is deterministic and computable from the entity's identifier -- no external declaration needed. The assignment never goes stale because it is derived from the name itself.

In the ontology graph, many entity types can be deterministically assigned from their location or identifier:

| Entity | Identifier Pattern | Derived Family |
|--------|-------------------|---------------|
| Files under `core/` | Path prefix `core/**` | Development |
| Files under `.beads/` | Path prefix `.beads/**` | Work-tracking |
| Files under `.claude/agents/` | Path prefix `.claude/agents/**` | Infrastructure |
| Beads with `sylveste-*` prefix | ID pattern `sylveste-*` | Work-tracking |
| Sessions with `sess-*` prefix | ID pattern `sess-*` | Agent |
| Plugins in `interverse/` | Path prefix `interverse/**` | Infrastructure |
| Discoveries in `docs/solutions/` | Path prefix `docs/solutions/**` | Knowledge |

Deterministic assignment from identifiers is:
- **Never stale** (the path IS the type)
- **Zero maintenance** (no manual declaration needed)
- **Auditable** (the rule is inspectable)

The limitation is entities whose type does not correlate with their identifier -- a file under `docs/` that is actually infrastructure configuration, or a session that produces knowledge. These require explicit type declarations as overrides.

**Smallest viable fix:** Implement a two-tier type assignment: (1) pattern-based assignment from identifiers (covers 80%+ of entities), (2) explicit declaration for entities that resist pattern assignment:

```yaml
type_assignment:
  patterns:
    - match: "core/**"     -> family: development
    - match: "*.go"        -> family: development
    - match: ".beads/**"   -> family: work_tracking
    - match: "interverse/**" -> family: infrastructure
    - match: "docs/solutions/**" -> family: knowledge
  overrides:
    - entity: "docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md"
      family: knowledge  # Override: brainstorms are knowledge, not development
```

---

## Finding 5: Materialized graph rigidity -- the Mandalay problem

**Severity: P2**
**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, line 66

The brief asks "Could this be a read-only projection (materialized view) rather than a system of record?" (line 66). This is the right instinct, but the question of incrementality is unaddressed.

**The bedin structural isomorphism:** King Mindon built Mandalay (1857) with its physical layout following bedin directional assignments -- north gates correspond to Thursday/Jupiter, east gates to Sunday/Sun, and so on. The city IS a materialized view of the planetary calculus. This has real navigational value: you can orient yourself in the city by knowing the cosmological relationships. But when the bedin is reinterpreted (as happens with the Ketu/Rahu Wednesday split, which different traditions resolve differently), the city cannot be rebuilt. The materialization creates rigidity.

For the ontology graph: if the graph is materialized as a precomputed index, what happens when the relational calculus rules change? Suppose the family interaction rules are updated to add a new relationship type between Agent and Knowledge entities. Must the entire materialized graph be recomputed?

The answer depends on whether the materialization is **rule-indexed** or **entity-indexed**:
- **Entity-indexed** (each entity has a row with all its relationships): Changing a rule requires recomputing every entity's relationships. This is rebuilding Mandalay.
- **Rule-indexed** (each rule has a set of entity pairs it generates): Changing a rule requires recomputing only the entity pairs affected by that rule. This is rebuilding one district of Mandalay.

**Smallest viable fix:** Structure the materialized index as rule-indexed, not entity-indexed. Each entry in the index points back to the rule that generated it. When a rule changes, invalidate only the entries generated by that rule and recompute them. This makes rule changes O(affected-entities) rather than O(all-entities).

---

## Summary

| # | Severity | Finding | Core Bedin Mechanism |
|---|----------|---------|---------------------|
| 1 | P1 | O(N^2) relationship declarations required | Planetary house relational calculus |
| 2 | P1 | Context-dependent type transitions unaddressed | Ketu/Rahu Wednesday split |
| 3 | P2 | Runtime relationship overrides unmodeled | Nat spirit overlay |
| 4 | P2 | Type assignment is not deterministic from identifiers | Name-syllable house assignment |
| 5 | P2 | Materialized graph incrementality unaddressed | Mandalay city rigidity |
