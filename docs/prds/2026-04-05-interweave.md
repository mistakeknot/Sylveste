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
- [ ] Family-pair interaction matrix documented (appendix) showing which rule governs each of the 15 unordered family pairs
- [ ] Growth test: adding a new entity type to any family requires zero changes to interaction rules
- [ ] Compositionality test: "delegation" expressible using existing primitives without adding rule #8
- [ ] Interaction rules extensible via `{namespace}:{rule-name}` registration (plugins can add domain-specific rules)
- [ ] New entity types can declare family membership(s) and inherit all family rules
- [ ] Multi-family membership supported (entity belongs to Process + Evidence simultaneously)
- [ ] Multi-family resolution strategy: union of valid relationship types from all memberships
- [ ] Lifecycle transitions: entities gain new family memberships via declared lifecycle events (e.g., Session starts as Process, gains Evidence membership after reflection distillation)
- [ ] Transition rules declared per entity type; relational calculus immediately applies to expanded family set
- [ ] Unclassified status: entities without family membership appear in search but don't participate in relational calculus
- [ ] Unit tests: family declaration, rule inheritance, multi-family, lifecycle transitions, compositionality, unclassified behavior

### F2: Identity Crosswalk [P1]

**What:** Materialized identity crosswalk mapping (subsystem, subsystem_id) to canonical_entity_id, with file-level and function-level resolution.

**Acceptance criteria:**
- [ ] Crosswalk storage (SQLite) with (subsystem, subsystem_id, canonical_id, confidence, method) schema
- [ ] Composite canonical ID format: `{subsystem}:{native_id}` — subsystem prefix routes to connector, native ID is familiar
- [ ] File-level resolution: path normalization, git SHA matching, git rename detection
- [ ] Function-level resolution: tree-sitter AST fingerprinting (canonical signature = file_path + function_name + parameter_types + return_type)
- [ ] Supported languages for function-level resolution declared explicitly; unsupported languages fall back to file-level
- [ ] Function rename/move detection: body similarity >95% = `confirmed` auto-link; 80-95% = `probable` (excluded from default queries per F4); <80% = no link
- [ ] Identity links NOT transitively closed by default (A=B and B=C does not imply A=C without explicit evidence)
- [ ] Identity chain recording: fn_v1 → renamed_to → fn_v2 (history preserved across index rebuilds)
- [ ] Per-entity-type diagnostic property table documenting the identity anchor for each type (file→path, bead→bead_id, session→session_id, commit→SHA, function→AST fingerprint)
- [ ] Actor identity table: (subsystem, actor_id, canonical_person_id, confidence, method) — unifies developer identity across git username, session ID, beads claimed_by, PR reviewer name; canonical person ID = git email
- [ ] O(1) lookup at runtime via materialized index
- [ ] Incremental updates (don't rebuild entire crosswalk on each change)
- [ ] Dedup detection (flag when two canonical entities likely refer to the same thing)

### F3: Connector Protocol + First Connectors [P1]

**What:** Define the connector interface and implement connectors for the 3 primary subsystems: cass (sessions), beads (work tracking), and tldr-code (code structure).

**Acceptance criteria:**
- [ ] Connector interface: register, harvest (pull entity metadata), get_observation_contract
- [ ] Connectors are interweave-internal: subsystems need not know about interweave; adding a connector does not change the subsystem
- [ ] Observation contract format: entities_indexed, granularity, properties (captured/inferred), refresh cadence, freshness_signal, observation_depth per entity type, relationship_types discovered, coverage_estimate (indexed_since, approximate_completeness)
- [ ] Minimum discovery threshold: entity_id + subsystem (2 fields); entity_type and created_at auto-inferred where possible
- [ ] cass connector: indexes sessions, tool calls (nested), files_touched; refresh via cass index
- [ ] beads connector: indexes issues, dependencies, sprints; refresh via bd CLI
- [ ] tldr-code connector: indexes files, functions, classes, imports; refresh via tldr-code extract/structure
- [ ] Harvest model: interweave crawls connectors (zero effort from producers); two modes — broad (fast, metadata-only) and deep (slow, on-demand for specific entities)
- [ ] Progressive enhancement: connectors can provide minimal (2-field) or rich metadata
- [ ] Adding a new connector does not change existing query results unless a query template explicitly includes the new source
- [ ] Cold-start: broad harvest completes within 5 minutes for a fresh install; useful queries available immediately after

### F4: Confidence Scoring + Link Provenance [P2]

**What:** Every cross-system relationship carries provenance metadata — method, confidence level, evidence, and temporal validity.

**Acceptance criteria:**
- [ ] Link schema: source_entity, target_entity, relationship_type, method, confidence, evidence[], created_at, last_verified_at, valid_from, valid_until
- [ ] Methods: explicit-reference, temporal-cooccurrence, identifier-match, embedding-similarity
- [ ] Confidence levels: confirmed (deterministic match), probable (structural match), speculative (temporal/embedding)
- [ ] Default query filter excludes "speculative" links
- [ ] Per-query minimum confidence floor for traversal edges (high-stakes queries can require confirmed/probable only)
- [ ] Agents can explicitly request speculative links when exploring
- [ ] Evidence list per link: array of observations supporting the relationship
- [ ] Cross-source contradiction detection: enumerated patterns (closed-but-active, deleted-but-referenced, conflicting-timestamps) surfaced with source attribution rather than silently resolved
- [ ] Staleness detection: links not re-verified within TTL flagged as stale

### F5: Named Query Templates (MCP Tools) [P1]

**What:** 6 named query commands exposed as MCP tools with bounded traversal and predictable token cost.

**Acceptance criteria:**
- [ ] MCP server in interweave serving 7 tools:
  - `context-for <entity>`: composite query combining related-work + recent-sessions + who-touched (1 hop, max 10 per source)
  - `related-work <entity>`: beads linked to entity (1 hop, max 10)
  - `recent-sessions <entity>`: sessions that touched entity (1 hop, max 10)
  - `review-findings <entity>`: flux-drive findings mentioning entity (1 hop, max 20)
  - `causal-chain <entity>`: blocks/caused-by/discovered-from traversal (3 hops, beam K=50 per intermediate hop, max 20 final results)
  - `who-touched <entity>`: agents/humans that modified entity (1 hop, max 10)
  - `evidence-for <entity>`: interspect evidence, calibration data (1 hop, max 20)
- [ ] Entity input accepts: file path, bead ID, session ID, function name, or canonical entity ID (composite `{subsystem}:{native_id}` format)
- [ ] Results include source subsystem attribution and per-connector coverage/freshness metadata
- [ ] Results distinguish "no data found" vs. "source unavailable" vs. "not yet indexed"
- [ ] Token cost: <500 tokens for 1-hop queries, <800 tokens for causal-chain (3-hop)
- [ ] Latency contract: all queries <200ms at 100K entities / 500K links
- [ ] Graceful degradation: per-source timeout (2s), partial results returned with per-source status indicator
- [ ] Before/after scenarios documented (3 examples with token counts proving capability delta over cass+beads+grep)

### F6: Query-Context Salience [P2]

**What:** Results ordered differently based on agent context — debugging prioritizes recent sessions + causal chains; planning prioritizes beads + blockers; reviewing prioritizes findings + evidence.

**Acceptance criteria:**
- [ ] 3 context modes: debugging, planning, reviewing
- [ ] Context detection: explicit parameter (`--context=debugging`) as primary method
- [ ] Each query template has per-context ordering weights
- [ ] Per-context property projection: debugging surfaces diff stats + test results; planning surfaces bead associations + sprint membership; reviewing surfaces findings + evidence history
- [ ] Default context: "general" (balanced ordering, full property set)
- [ ] Context affects both result ordering AND property projection (same data, different modal meaning)

### F7: Gravity-Well Safeguards [P2]

**What:** Structural protections against the ontology drifting from index to system-of-record.

**Acceptance criteria:**
- [ ] No-write-through: write operations to source subsystems not implemented in any code path
- [ ] Staleness TTL: per-type-family configuration (Process entities: short TTL with archive-to-cold-storage; Artifact entities: long TTL or refresh-on-query)
- [ ] Three-level finding-aid test:
  - (a) Structural audit: `interweave audit --structural` deletes the entire index, verifies all subsystems still function
  - (b) Provenance regeneration: `interweave audit --provenance` rebuilds index and verifies link confidence within 10% of pre-delete levels
  - (c) Behavioral fallback: `interweave audit --behavioral` disables interweave, verifies agents complete queries via direct subsystem access
- [ ] Identity chain history preserved across audits (not destroyed by index rebuild)
- [ ] Direct access documentation: agent prompts include fallback instructions for when interweave is unavailable
- [ ] Health check: `interweave health` reports index freshness, connector status, staleness counts, and unclassified entity percentage (alert at >30%)

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

## Resolved by Flux-Review

3. ~~**Entity input parsing.**~~ **Resolved:** Composite canonical IDs using `{subsystem}:{native_id}` format. Subsystem prefix routes to connector; native ID is familiar. Promoted to F2 acceptance criterion.

4. ~~**Index size management.**~~ **Resolved:** Per-type-family TTLs (Process = short TTL with archive-to-cold-storage; Artifact = long TTL or refresh-on-query) combined with broad/deep harvest modes (broad metadata always retained; deep metadata expires per TTL). Promoted to F7 acceptance criterion.
