# Ontology Graph for Agentic Development Platforms — Concept Brief

## The Question

Would a Palantir-style ontology graph be valuable for agentic development platforms (Claude Code, Skaffen, Sylveste, and the broader category)? What capabilities would it unlock?

## What Palantir's Foundry Ontology Does

Palantir's Ontology is a unified semantic layer over heterogeneous data sources:

1. **Typed objects.** Every entity has a declared type (Flight, Patient, Transaction) with properties and constraints.
2. **Relationships.** Objects link to other objects with typed, directional edges (authored_by, blocked_by, triggered).
3. **Actions.** Operations that can be performed on objects, with preconditions and effects declared in the schema.
4. **Unified query.** One interface traverses relationships across all underlying data sources. Users don't need to know where data lives.
5. **Schema browser.** Visual exploration of what types exist, what relationships connect them, what actions are available.

## The Agentic Development Context

Modern agentic platforms have many entity types that are currently siloed:

**Development entities:** Files, functions, classes, modules, tests, dependencies, imports, AST nodes
**Work tracking entities:** Issues/beads, epics, sprints, PRs, commits, branches, deployments
**Agent entities:** Sessions, runs, tool calls, model invocations, dispatches, delegations
**Knowledge entities:** Discoveries, learnings, solutions, patterns, voice profiles, lens applications
**Review entities:** Findings, verdicts, gates, evidence, calibration data, routing overrides
**Infrastructure entities:** Plugins, skills, commands, hooks, MCP tools, agents, configuration

Each subsystem manages its own entities with its own ID scheme, storage, and query patterns. There is no way to ask: "Show me everything connected to this function" and get back the beads that tracked work on it, the sessions where it was modified, the review findings about it, the test results, and the discoveries that referenced it.

## What Already Exists in Sylveste

Sylveste already has 6+ graph-like structures, each solving a specific problem:

1. **interlens** — 288-node NetworkX knowledge graph of thinking lenses (8+ edge types, PageRank, community detection, path finding)
2. **Beads** — Work item DAG with 6 relationship types (blocks, parent-child, conditional-blocks, waits-for, discovered-from, caused-by)
3. **interchart** — D3.js force graph of 60+ plugins/skills/tools/hooks
4. **intercore schema** — Relational tables for runs, artifacts, dispatches, discoveries (SQL-queryable but not graph-traversable)
5. **intertree** — Project hierarchy with parent-child + tag relationships
6. **interkasten** — Notion-project bidirectional entity mapping

**Key philosophical constraint:** "Unify retrieval, not storage." The PHILOSOPHY.md explicitly says many small stores composed via retrieval beats migration to a unified store. Standalone plugins fail-open without intercore.

**Prior art assessed:** MAGMA multi-graph memory → "inspire-only" because code has explicit structure (AST), determinism matters, and existing tools (cass, tldr-code) already cover semantic + structural retrieval.

## Three Concrete Capabilities Being Explored

### 1. Unified Entity Graph
One place to ask "show me everything related to X" — beads, sessions, agents, artifacts, discoveries all linked. Cross-system entity resolution without requiring systems to migrate their storage.

### 2. Typed Schema + Actions
Formal type system for platform entities (Agent, Tool, Skill, Run, Artifact) with declared capabilities, constraints, and allowed actions. Like Palantir's Ontology Manager — a schema browser for the platform itself.

### 3. Agent-Queryable Relationships
Agents can traverse relationships at runtime — "which agents have touched this file?", "what evidence exists for this pattern?", "what skills are available for this entity type?" — without knowing which subsystem stores the data.

## Design Tensions

- **Composition vs. coupling:** A unified graph is powerful but creates a central dependency. The philosophy says composition over capability.
- **Inference vs. declaration:** Should relationships be declared in schemas or inferred from observations? Palantir uses declaration; the ecosystem already has inference (interspect evidence, cass session indexing).
- **Static vs. dynamic:** A code ontology changes every commit. A work ontology changes every sprint. How fresh must the graph be?
- **Cost of wrong abstractions:** "Don't pay debt too early — cementing wrong abstractions is worse than messy scripts."

## Open Questions for Creative Exploration

- What capabilities does an ontology graph unlock that are impossible without one?
- What's the minimal viable ontology — which entity types and relationships would provide 80% of the value?
- Could this be a read-only projection (materialized view) rather than a system of record?
- How would agents use the ontology at runtime? What queries would they actually make?
- What does the ontology graph look like for a general agentic platform vs. Sylveste specifically?
- Are there non-obvious entity types or relationships that become visible only through graph structure?
- What are the failure modes — what goes wrong when an ontology graph is done badly?
