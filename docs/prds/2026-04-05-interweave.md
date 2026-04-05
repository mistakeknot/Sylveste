---
artifact_type: prd
bead: sylveste-46s
stage: design
---

# PRD: interweave — Generative Ontology Graph for Agentic Platforms

## Problem

Agentic development platforms have 6+ entity classes siloed in independent subsystems with incompatible ID schemes. Agents cannot ask "show me everything connected to this function" because no system can recognize the same entity across subsystem boundaries. Cross-system context requires manual multi-tool queries that cost ~800 tokens and still miss relationships.

## Solution

A generative ontology layer (interweave) that indexes entity metadata across subsystems and returns cross-system context through named query templates. Five composable type families with 7 interaction rules generate the complete relationship matrix — new entity types inherit rules automatically. The ontology is a catalog-of-catalogs: it never owns entity data, delegates to source subsystems, and passes the finding-aid test (deletable without impact).

## Features

### F1: Plugin Scaffold + Type Family System [P1]

**What:** Create the interweave plugin with the core type family system — 5 families (Artifact, Process, Actor, Relationship, Evidence) and 7 interaction rules (Productivity, Transformation, Stewardship, Structure, Evidence Production, Annotation, Lifecycle) as a relational calculus engine.

**Acceptance criteria:**
- [ ] interweave plugin scaffolded in `interverse/interweave/` with .claude-plugin/plugin.json, CLAUDE.md, AGENTS.md
- [ ] 5 type families defined as data models with diagnostic properties
- [ ] 7 interaction rules implemented — given (family_a, family_b), returns valid relationship types
- [ ] New entity types can declare family membership(s) and inherit all family rules
- [ ] Multi-family membership supported (entity belongs to Process + Evidence simultaneously)
- [ ] Unclassified status: entities without family membership appear in search but don't participate in relational calculus
- [ ] Unit tests: family declaration, rule inheritance, multi-family, unclassified behavior

### F2: Identity Crosswalk [P1]

**What:** Materialized identity crosswalk mapping (subsystem, subsystem_id) to canonical_entity_id, with file-level and function-level resolution.

**Acceptance criteria:**
- [ ] Crosswalk storage (SQLite) with (subsystem, subsystem_id, canonical_id, confidence, method) schema
- [ ] File-level resolution: path normalization, git SHA matching, git rename detection
- [ ] Function-level resolution: tree-sitter AST fingerprinting (canonical signature = file_path + function_name + parameter_types + return_type)
- [ ] Function rename/move detection: body similarity heuristic (>80% match links identities)
- [ ] Identity chain recording: fn_v1 → renamed_to → fn_v2
- [ ] O(1) lookup at runtime via materialized index
- [ ] Incremental updates (don't rebuild entire crosswalk on each change)
- [ ] Dedup detection (flag when two canonical entities likely refer to the same thing)

### F3: Connector Protocol + First Connectors [P1]

**What:** Define the connector interface and implement connectors for the 3 primary subsystems: cass (sessions), beads (work tracking), and tldr-code (code structure).

**Acceptance criteria:**
- [ ] Connector interface: register, harvest (pull entity metadata), get_observation_contract
- [ ] Observation contract format: entities_indexed, granularity, properties (captured/inferred), refresh cadence, freshness_signal
- [ ] Minimum discovery threshold enforced: entity_type, entity_id, subsystem, created_at
- [ ] cass connector: indexes sessions, tool calls (nested), files_touched; refresh via cass index
- [ ] beads connector: indexes issues, dependencies, sprints; refresh via bd CLI
- [ ] tldr-code connector: indexes files, functions, classes, imports; refresh via tldr-code extract/structure
- [ ] Harvest model: interweave crawls connectors (zero effort from producers)
- [ ] Progressive enhancement: connectors can provide minimal (4-field) or rich metadata

### F4: Confidence Scoring + Link Provenance [P2]

**What:** Every cross-system relationship carries provenance metadata — method, confidence level, evidence, and temporal validity.

**Acceptance criteria:**
- [ ] Link schema: source_entity, target_entity, relationship_type, method, confidence, evidence[], created_at, last_verified_at
- [ ] Methods: explicit-reference, temporal-cooccurrence, identifier-match, embedding-similarity
- [ ] Confidence levels: confirmed (deterministic match), probable (structural match), speculative (temporal/embedding)
- [ ] Default query filter excludes "speculative" links
- [ ] Agents can explicitly request speculative links when exploring
- [ ] Evidence list per link: array of observations supporting the relationship
- [ ] Staleness detection: links not re-verified within TTL flagged as stale

### F5: Named Query Templates (MCP Tools) [P1]

**What:** 6 named query commands exposed as MCP tools with bounded traversal and predictable token cost.

**Acceptance criteria:**
- [ ] MCP server in interweave serving 6 tools:
  - `related-work <entity>`: beads linked to entity (1 hop, max 10)
  - `recent-sessions <entity>`: sessions that touched entity (1 hop, max 10)
  - `review-findings <entity>`: flux-drive findings mentioning entity (1 hop, max 20)
  - `causal-chain <entity>`: blocks/caused-by/discovered-from traversal (3 hops, max 20)
  - `who-touched <entity>`: agents/humans that modified entity (1 hop, max 10)
  - `evidence-for <entity>`: interspect evidence, calibration data (1 hop, max 20)
- [ ] Entity input accepts: file path, bead ID, session ID, function name, or canonical entity ID
- [ ] Results include source subsystem attribution
- [ ] Token cost per query < 500 tokens (result formatting)
- [ ] Graceful degradation: if a connector is unavailable, return partial results with source status

### F6: Query-Context Salience [P2]

**What:** Results ordered differently based on agent context — debugging prioritizes recent sessions + causal chains; planning prioritizes beads + blockers; reviewing prioritizes findings + evidence.

**Acceptance criteria:**
- [ ] 3 context modes: debugging, planning, reviewing
- [ ] Context detection: explicit parameter (`--context=debugging`) as primary method
- [ ] Each query template has per-context ordering weights
- [ ] Default context: "general" (balanced ordering)
- [ ] Context affects result ordering, not result filtering (all results available regardless of context)

### F7: Gravity-Well Safeguards [P2]

**What:** Structural protections against the ontology drifting from index to system-of-record.

**Acceptance criteria:**
- [ ] No-write-through: write operations to source subsystems not implemented in any code path
- [ ] Staleness TTL: entities not refreshed within 30 days automatically excluded from query results
- [ ] Finding-aid audit script: `interweave audit` deletes the entire index, verifies all subsystems still function, and rebuilds
- [ ] Direct access documentation: agent prompts include fallback instructions for when interweave is unavailable
- [ ] Health check: `interweave health` reports index freshness, connector status, and staleness counts

### F8: Philosophy Amendment + Documentation [P3]

**What:** Add interweave's architectural rationale to project documentation and update PHILOSOPHY.md.

**Acceptance criteria:**
- [ ] PHILOSOPHY.md: new paragraph under "Composition Over Capability" explaining catalog-of-catalogs as composition (finding-aid test, no data ownership, no write-through)
- [ ] interweave CLAUDE.md: development guide, architecture overview, connector development guide
- [ ] interweave AGENTS.md: operational reference, troubleshooting, CLI reference

## Non-goals

- **Graph database:** interweave uses SQLite with adjacency tables, not Neo4j/kuzu/etc. The catalog-of-catalogs pattern doesn't need a graph engine.
- **Open-ended graph traversal:** No Cypher, SPARQL, or GraphQL. Named templates only. Unbounded traversal is a token sink.
- **Real-time streaming:** Connectors use harvest (poll) model, not push/CDC. Real-time updates are a future iteration.
- **Cross-platform packaging:** v0.1 is a Sylveste interverse plugin. Standalone binary for other platforms is a future iteration.
- **Replacing existing tools:** cass, beads, tldr-code, grep remain primary. interweave is additive.

## Dependencies

- **cass** (v0.2.0+): Session index for the cass connector
- **beads** (v0.60.0+): Work tracking for the beads connector
- **tldr-code**: Code structure for the tldr-code connector
- **tree-sitter**: AST parsing for function-level identity resolution
- **SQLite**: Storage backend for crosswalk and entity index

## Open Questions

1. **Storage schema design.** Single SQLite database or separate DBs for crosswalk, entity index, and link provenance? Single DB is simpler; separate DBs allow independent lifecycle management.

2. **Connector refresh scheduling.** Should interweave harvest on-demand (when a query arrives and cache is stale), on a timer (background refresh), or on triggers (hook after git push, bead close)? Likely hybrid: on-demand with background refresh for frequently-queried connectors.

3. **Entity input parsing.** How does interweave disambiguate "src/main.py" (file path) from "Sylveste-abc1" (bead ID) from "a1b2c3d4" (session ID)? Likely: prefix-based routing (paths contain `/`, beads contain `-`, sessions are hex strings) with explicit `--type=` override.

4. **Index size management.** With 60+ plugins and years of sessions, the index could grow large. Need a retention policy beyond TTL — archive old entities? Compact the crosswalk?
