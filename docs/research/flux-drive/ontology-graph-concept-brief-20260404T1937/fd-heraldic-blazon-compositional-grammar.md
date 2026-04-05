### Findings Index
- P1 | BLZ-1 | "Typed Schema + Actions" | Schema is a catalog, not a grammar — every new source system adds entity types rather than composing from primitives, producing unbounded schema growth
- P1 | BLZ-2 | "Unified Entity Graph" | Relationship types are untyped links — no compositional constraints prevent meaningless traversal paths that chain valid individual edges into nonsensical sequences
- P1 | BLZ-3 | "Typed Schema + Actions" | Entity definitions are referential, not reconstructive — schema entries point to source systems rather than containing enough semantic content for independent agent reasoning
- P2 | BLZ-4 | "Three Concrete Capabilities" | No entity versioning or lineage mechanism — the same function across commits, the same bead across state transitions, treated as unrelated entities
- P2 | BLZ-5 | "Design Tensions" | Sub-schema composition rules absent — no marshalling mechanism for combining the beads DAG schema, session log schema, and code graph schema without mutual modification
Verdict: needs-changes

## Summary

The herald evaluates every schema language as a blazon: does the grammar compose, or does it merely catalog? The concept brief proposes a typed schema with entity types and relationships but does not specify whether the type system is compositional (new entity types constructed from existing primitives) or enumerative (each new source system adds bespoke types). Blazon solved this problem in the 12th century: a small grammar of field divisions, tinctures, ordinaries, charges, and positional terms can describe shields that did not exist when the rules were written. The grammar composes. If the ontology schema is enumerative — File, Function, Bead, Session, Run, Tool, Plugin, Discovery, Review, Agent, each with bespoke properties — then after 10 source system integrations the schema will have 60+ types with 200+ relationship types and no agent will be able to navigate it efficiently. The schema becomes a catalog masquerading as a grammar.

## Issues Found

### P1 — BLZ-1: Catalog, Not Grammar — Schema Grows Linearly with Source Count

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 8-14 ("What Palantir's Foundry Ontology Does") and lines 19-28 ("The Agentic Development Context")

**Finding:** The Palantir model defines typed objects (line 9: "every entity has a declared type — Flight, Patient, Transaction"). The concept brief then lists 6 entity type families with ~30 specific types (files, functions, classes, modules, tests, dependencies, imports, AST nodes, issues/beads, epics, sprints, PRs, commits, branches, deployments, sessions, runs, tool calls, model invocations, dispatches, delegations, discoveries, learnings, solutions, patterns, findings, verdicts, gates, plugins, skills, commands, hooks, MCP tools, agents, configuration).

This is a catalog. Each entity type is bespoke — defined individually with its own properties and constraints. The herald's question: can the grammar describe a new entity type that does not yet exist, using existing type primitives? If a new subsystem appears (say, a cost accounting system with Budget, Invoice, LineItem entities), does the ontology need new type definitions, or can Budget be composed from existing primitives?

If new types require schema extension every time, the ontology follows the anti-pattern of "a unique keyword for every shield ever painted rather than composable rules for describing any shield." After Sylveste's ~60 plugins each contribute 2-3 entity types, the schema has 120-180 types — unnavigable.

**Concrete failure scenario:** A developer adds a new interverse plugin (`intercost`) that tracks cost data. They must define 4 new entity types (Budget, Allocation, Spend, Forecast) in the ontology schema. A different developer adds `interaudit` with 3 types (AuditEvent, AuditTrail, AuditFinding). A third adds `interbench` with 3 types (Benchmark, Trial, Result). Each addition requires schema migration, schema browser updates, and re-validation of existing queries. After 20 such additions, the schema has 90+ types and the schema browser requires scrolling through pages of types to find anything.

**The herald's test:** Count the type primitives. If the count is < 10 and all entity types compose from them, you have a grammar. If the count equals the number of entity types, you have a catalog.

**Smallest viable fix:** Define a small set of composable type primitives in the concept brief:

```
Base entity types (composable primitives):
  Artifact: anything that can be content-addressed (file, commit, discovery, test result)
  Process: anything that has a lifecycle (session, run, sprint, bead)
  Actor: anything that performs actions (agent, user, tool, skill)
  Relationship: anything that connects entities (blocks, produced-by, touched, references)
  Evidence: anything that supports a claim (finding, verdict, test result, metric)

Source systems declare their entities as compositions:
  Bead = Process + { status, priority, assignee }
  Session = Process + { model, tokens, start, end }
  Commit = Artifact + { tree, parent, author, message }
  ReviewFinding = Evidence + { severity, agent, section }
```

This gives 5 primitives instead of 30+ bespoke types, and new source systems compose from them.

### P1 — BLZ-2: Untyped Relationship Links Allow Meaningless Traversals

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 10-11 ("Relationships" in Palantir model)

**Finding:** The Palantir model specifies "typed, directional edges (authored_by, blocked_by, triggered)." The concept brief mentions "relationships" throughout but does not specify typed constraints on which entity types can participate in which relationship types. Without constraints, the schema permits meaningless traversal paths.

**Concrete failure scenario:** An agent traverses: Function → (referenced_in) → Discovery → (produced_by) → Session → (used_tool) → Plugin → (registered_in) → Agent. Each individual edge is valid, but the composed path is meaningless — a function being referenced in a discovery that was produced by a session that used a plugin that was registered in an agent does not constitute a meaningful relationship between the function and the agent. This is equivalent to a blazon that says "gules a lion or" without specifying position — technically parseable, but every herald reconstructs a different shield.

**The herald's test (tincture rule):** Does the schema enforce that colour cannot be placed on colour, nor metal on metal? In ontology terms: does the schema constrain which relationship types connect which entity types? "Run.is-child-of Session" is a valid typed relationship. "Run.links-to Plugin" needs qualification — is it "Run.invoked Plugin" or "Run.was-routed-by Plugin"? Unqualified "links-to" is the heraldic equivalent of unspecified tincture.

**Smallest viable fix:** Add relationship type constraints to the schema design:

```
Relationship constraints (tincture rules):
  produced-by: Evidence → Process (never Evidence → Artifact)
  is-child-of: Process → Process (with cardinality: exactly one parent)
  references: any → Artifact (the most permissive, but still typed)
  triggered: Actor → Process (directional: actors trigger processes)
  blocked-by: Process → Process (with cycle detection)

Invalid traversals are rejected at query time, not silently returned.
```

### P1 — BLZ-3: Schema Entries Are Referential, Not Reconstructive

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 46-54 ("Three Concrete Capabilities")

**Finding:** Capability 2 ("Typed Schema + Actions") proposes a "formal type system for platform entities (Agent, Tool, Skill, Run, Artifact) with declared capabilities, constraints, and allowed actions." The key blazon test: does the schema entry contain enough information for an agent that has never interacted with the underlying source system to reason about the entity correctly?

A blazon must contain enough information for a herald who has never seen the shield to paint it correctly. If the schema defines a Bead as `{ id: string, title: string, status: enum, assignee: string }`, an agent knows the shape but not the substance. It cannot answer "is this bead blocked?" or "what is the bead's estimated completion date?" without querying beads directly. The schema is a directory (pointer to the source), not a model (sufficient for reasoning).

**Concrete failure scenario:** An agent asks "which beads are at risk of missing the sprint deadline?" The ontology returns all open beads with their schema properties (id, title, status, assignee). The agent has status=in_progress but no information about: estimated vs actual effort, dependency chain depth, assignee availability, historical completion rates for similar beads. It cannot reason about risk without querying beads, interstat, and session history directly — the ontology schema entry is too thin for independent reasoning.

**Smallest viable fix:** Define "reconstruction sufficiency" as a schema design principle:

```
Schema design principle: an agent with access only to the ontology (not the source system)
should be able to answer the 3 most common questions about each entity type.

For Bead:
  Q1: "Is this bead at risk?" → requires: status, priority, created_at, blocked_by count, estimated_tokens
  Q2: "What work was done?" → requires: linked commits (count + last date), linked sessions (count)
  Q3: "Who is responsible?" → requires: assignee, claimed_at, last_activity_date

Minimum viable properties are derived from the top-3 questions, not from the source system's schema.
```

### P2 — BLZ-4: No Entity Versioning (Missing Cadency Marks)

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 20-21 ("Development entities")

**Finding:** Development entities include "files, functions, classes" — but these change with every commit. Is function parseConfig at commit abc123 the same entity as parseConfig at commit def456? The brief does not address entity versioning. In heraldic terms, marks of cadency distinguish the arms of different sons of the same family without changing the base blazon. The ontology needs an equivalent: a mechanism that preserves base entity identity while marking variants across time.

**Smallest viable fix:** Add versioning semantics:

```
Entity versioning: entities that change over time carry:
  identity: stable across versions (e.g., file path, function name + file)
  version: commit hash, timestamp, or state transition ID
  lineage: previous_version → current_version edges

Query default: latest version. Query with version parameter: specific point in time.
```

### P2 — BLZ-5: No Schema Composition (Missing Marshalling)

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 57-58 ("Design Tensions: Composition vs. coupling")

**Finding:** The brief notes the tension between composition and coupling. But it does not specify how sub-schemas from different source systems compose. In heraldry, when two families marry, their arms are combined through marshalling rules (impalement, quartering) that preserve each family's arms while composing them into a new whole. The ontology needs an equivalent: rules for combining the beads DAG schema and the session log schema into a unified ontology while each retains its native relationship types.

The PHILOSOPHY.md mandates "composition over capability" and "many small stores composed via retrieval." This philosophy directly implies marshalling — each source system's schema is preserved intact, and the unified ontology composes them through well-defined combination rules, not by merging them into a single normalized schema.

**Smallest viable fix:** Add marshalling rules:

```
Schema composition (marshalling):
  Each source system's type definitions are preserved as a named sub-schema.
  Cross-system relationships are defined in a separate "composition schema."
  Sub-schemas cannot reference each other's internal types directly.
  The composition schema defines bridge relationship types that connect sub-schemas.

Example:
  beads-schema: { Bead, Epic, Sprint } with internal relationships
  session-schema: { Session, Run, ToolCall } with internal relationships
  composition: { Session.worked-on → Bead, Commit.resolves → Bead }
```

## Improvements

1. **Grammar test as acceptance criteria.** Before finalizing the ontology schema, apply the blazon compositionality test: can the grammar describe a plausible future entity type (e.g., "agent performance profile" or "cost allocation bucket") using only existing type primitives and relationship types? If yes, the grammar composes. If no, identify which new primitive is needed and add it — but add primitives, not bespoke types.

2. **Schema browser as blazon renderer.** The schema browser (mentioned in line 13 of the Palantir model) should work like a blazon renderer: given an entity type's compositional definition, it should produce a human-readable description that any developer can understand without knowing which source system the entity comes from. If the schema browser requires source-system-specific knowledge to interpret an entity type, the schema definitions are too thin.

3. **Testable schema specifications.** Apply the blazon reconstruction test: given only the schema definition (no access to the source system), two independent implementations should produce the same graph structure for the same input data. If they diverge, the schema is ambiguous. This is how heraldic authorities validate blazon — two heralds paint the same shield from the same description, and the results must match.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 5 (P0: 0, P1: 3, P2: 2)
SUMMARY: The ontology schema is a catalog (30+ bespoke types) rather than a grammar (composable primitives), with untyped relationships that permit meaningless traversals and entity definitions too thin for independent agent reasoning.
---
<!-- flux-drive:complete -->
