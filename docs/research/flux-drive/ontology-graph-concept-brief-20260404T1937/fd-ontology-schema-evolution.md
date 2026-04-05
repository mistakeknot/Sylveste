### Findings Index
- P1 | OSE-1 | "The Agentic Development Context" | Six entity categories cement premature type hierarchy before usage patterns are understood
- P1 | OSE-2 | "Design Tensions" | No schema evolution strategy — brief identifies 'static vs. dynamic' tension but proposes no versioning mechanism
- P2 | OSE-3 | "What Already Exists in Sylveste" | Homonymous 'parent' relationship across beads and intertree creates false ontological equivalence
- P2 | OSE-4 | "Three Concrete Capabilities" | Property vs. relationship boundary unspecified — 'authored_by' is a property in some systems and an edge in others
- P1 | OSE-5 | "Three Concrete Capabilities" | Closed-world assumption incompatible with plugin ecosystem — new plugins silently create entity types the ontology doesn't know about
Verdict: needs-changes

## Summary

The concept brief identifies the right problem (fragmented entity spaces across 6+ subsystems) but proposes a solution architecture that contradicts hard-won lessons from production ontology systems. The six entity categories (Development, Work, Agent, Knowledge, Review, Infrastructure) look reasonable as a first sketch, but the brief treats them as a stable decomposition rather than a hypothesis to be tested. The absence of any schema evolution mechanism is the central gap — in a platform where new plugins ship weekly and each plugin can introduce new entity types, a fixed type hierarchy is a liability within months.

## Issues Found

### 1. [P1] Six entity categories cement premature type hierarchy (OSE-1)

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 19-28

The brief presents six entity categories as the decomposition of "modern agentic platforms." But these categories conflate organizational convenience with ontological structure:

- "Knowledge entities" (line 24) groups discoveries, learnings, solutions, patterns, voice profiles, and lens applications — these have radically different schemas, lifecycles, and query patterns. A "discovery" (interject) has source, confidence, and promotion state. A "voice profile" (interfluence) has style rules and corpus references. Lumping them creates a supertype so vague it provides no query leverage.
- "Review entities" (line 25) vs. "Agent entities" (line 23): A flux-drive finding IS an agent artifact. Is it a Review entity or an Agent entity? The boundary is arbitrary and will cause classification disputes as the ontology grows.

**Failure scenario:** Plugin X introduces a new entity type (e.g., a "campaign" from interlab). Is it a Work entity (tracks progress), an Agent entity (agents execute it), or an Infrastructure entity (configured in YAML)? The answer is "all three," which means either (a) the type must live in multiple categories (violating single-parent hierarchy) or (b) the categories are too coarse to be useful.

**Precedent:** Google Knowledge Graph's initial type hierarchy (Person, Place, Thing, Event, Organization) seemed clean but required 8 major schema revisions over 5 years as real-world entities refused to fit cleanly. Freebase's 86 domain types were eventually abandoned in favor of property-centric identification.

**Recommendation:** Replace the 6 fixed categories with a flat entity registry where types self-declare their properties and relationships. The categories become tags (facets), not hierarchy levels. This is how schema.org evolved after Freebase's lessons — types are a flat lattice with `rdfs:subClassOf`, not a tree.

### 2. [P1] No schema evolution strategy (OSE-2)

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 59-62

The "Design Tensions" section identifies "Static vs. dynamic: A code ontology changes every commit" but doesn't propose any mechanism for handling this. This is the existential risk for the ontology.

Concrete questions that must be answered before building:

- **Additive changes:** When a new plugin adds entity type "campaign," do all existing queries continue to work? (Yes, if open-world; no, if closed-world with exhaustive type matching.)
- **Rename/restructure:** When beads renames "conditional-blocks" to "soft-blocks," do graph traversals break? Where are the cached type names?
- **Property additions:** When intercore adds a `lane_id` field to runs, do materialized views invalidate? What's the refresh cost?
- **Breaking changes:** When two subsystems disagree on the meaning of a type name (e.g., "artifact" in intercore vs. "artifact" in interpath), who arbitrates?

**Failure scenario:** Schema.org's versioning approach (`schema:version` on every type definition, with explicit deprecation dates) works at web scale. But schema.org changes on a quarterly cadence. Sylveste plugins change weekly. If the ontology requires coordination for every type change, it becomes the bottleneck the philosophy explicitly warns against ("Don't pay debt too early — cementing wrong abstractions is worse than messy scripts," PHILOSOPHY.md line 87).

**Recommendation:** If this proceeds, adopt an append-only schema model: types can be added and properties extended, but never renamed or removed. Deprecation through annotation, not deletion. This is the only schema evolution strategy compatible with the plugin ecosystem's pace.

### 3. [P2] Homonymous 'parent' relationship (OSE-3)

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, line 36 (beads DAG) and line 39 (intertree hierarchy)

Beads has a `parent-child` relationship (line 36) representing work decomposition (epic contains stories). Intertree has a `parent-child` relationship (line 39) representing filesystem hierarchy. These are semantically different:

- Beads: parent-child means "work item X was decomposed into Y" — Y cannot exist without X's context.
- Intertree: parent-child means "directory A contains file B" — purely structural, no semantic dependency.

If both map to a unified `parent_of` edge type in the ontology, a traversal query like "show me all children of X" conflates work decomposition with directory containment. An agent asking "what are the subtasks?" might get directory listings.

**Recommendation:** Namespace relationship types by source system: `beads:parent_of`, `intertree:parent_of`. This preserves the semantics while allowing cross-system traversal when explicitly requested.

### 4. [P2] Property vs. relationship boundary unspecified (OSE-4)

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, line 10

The brief mentions "authored_by, blocked_by, triggered" as example relationships. But in intercore's schema (`core/intercore/internal/db/schema.sql`), `agent_type` is a TEXT column on the `dispatches` table — a property, not a relationship. Similarly, `parent_id` on dispatches is a TEXT foreign key, not a first-class edge.

The decision of what is a property vs. a relationship determines query expressiveness:

- If `agent_type` is a property: you can filter dispatches by agent, but you can't traverse from an Agent entity to its dispatches without scanning the dispatches table.
- If `agent_type` is a relationship edge: you can traverse bidirectionally, but you pay storage and maintenance costs for every dispatch record.

**Recommendation:** Use a simple heuristic from OWL ontology design: if the target is an entity with its own identity and lifecycle, it's a relationship. If it's a value (string, number, enum), it's a property. `agent_type` is a value (enum); `parent_id` references an entity with its own lifecycle — so `parent_id` should be a relationship edge and `agent_type` should be a property.

### 5. [P1] Closed-world assumption incompatible with plugin ecosystem (OSE-5)

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 47-54 (Capability 2: Typed Schema + Actions)

The brief proposes "Formal type system for platform entities... with declared capabilities, constraints, and allowed actions." This implies a closed-world assumption: the ontology declares what exists, and anything not declared doesn't exist.

But PHILOSOPHY.md (lines 125-137) explicitly describes a plugin ecosystem where:
- "Standalone plugins fail-open without intercore" (line 129)
- "No plugin requires another to function" (line 129)
- "The right count is however many single-responsibility units exist" (line 125)

A closed-world ontology creates pressure for plugins to register their types. A plugin that doesn't register becomes invisible to "show me everything related to X." This is de facto mandatory integration, violating fail-open independence.

**Failure scenario:** A developer creates a new plugin `interwatch` with a `DriftReport` entity type. Without registering in the ontology, `DriftReport` entities are invisible to cross-system queries. Users learn that unregistered plugins are "broken" and demand registration, creating implicit coupling the philosophy was designed to prevent.

**Recommendation:** Adopt an open-world assumption: the ontology discovers entity types by observing what subsystems report, not by requiring declaration. This is the "infer from observations" approach the brief identifies in the Design Tensions section (line 59) but doesn't commit to. For an ecosystem with 60+ plugins shipping independently, inference is the only scalable approach.

## Improvements

1. **Add a "Schema Lifecycle" section** to the brief that addresses: how types are added, how properties evolve, how breaking changes are handled, and what the migration path looks like when the ontology needs restructuring.

2. **Replace the 6 fixed categories with example entity types** — show concrete types (Run, Bead, Session, Discovery, File, Plugin) and their properties, rather than abstract categories. This forces specificity and reveals whether the categories actually help.

3. **Address the Freebase/Wikidata precedent explicitly** — both started with clean hierarchies and migrated to property-centric models. The brief should either explain why this case is different or plan for the same evolution.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 5 (P0: 0, P1: 3, P2: 2)
SUMMARY: The concept brief identifies a real fragmentation problem but proposes a type hierarchy that will cement premature abstractions. The absence of schema evolution strategy is the critical gap — in a weekly-shipping plugin ecosystem, a fixed ontology becomes a liability faster than it provides value.
---
<!-- flux-drive:complete -->
