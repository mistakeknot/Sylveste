---
artifact_type: brainstorm
bead: sylveste-46s
stage: discover
---

# interweave: Generative Ontology Graph for Agentic Development Platforms

## What We're Building

**interweave** — a generative ontology layer for agentic development platforms that gives agents cross-system context without centralizing storage. The ontology is a catalog-of-catalogs: it indexes metadata about entities across subsystems and returns pointers to authoritative data, never owning entity data itself.

The core insight, converged upon independently by 16 review agents from domains spanning Dogon cosmology, optical mineralogy, Burmese astrology, e-discovery law, archival science, geospatial infrastructure, heraldic blazon, Persian irrigation, Javanese gamelan, and Polynesian wayfinding: **a small set of composable type primitives + family-level interaction rules generates the complete relationship matrix**. New entity types inherit rules automatically. This replaces the O(N^2) approach of declaring relationships per type pair with an O(family-pairs) + O(exceptions) system.

**Scope:** Platform-general design, proved on Sylveste's concrete ecosystem (60+ plugins, beads, intercore, cass, Skaffen). The primitives are validated across Claude Code, Cursor, Devin, and Codex CLI — not Sylveste-specific.

**Implementation home:** Standalone interverse plugin with optional kernel enrichment. The finding-aid test (if you delete interweave, everything still works) is the architectural invariant.

**What this is NOT:**
- Not a graph database (it's an index layer over existing stores)
- Not a system of record (subsystems remain authoritative for their data)
- Not a replacement for existing tools (cass, beads, tldr-code, grep remain primary)
- Not a runtime dependency (agents fall back to direct tool access if unavailable)

## Why This Approach

### The Problem

Agentic development platforms have 6+ entity classes in siloed subsystems:

| Class | Examples | Subsystems |
|-------|----------|------------|
| Development | Files, functions, modules, tests | git, tldr-code, LSP |
| Work-tracking | Issues, epics, sprints, PRs, commits | beads, GitHub |
| Agent | Sessions, runs, tool calls, dispatches | cass, intercore |
| Knowledge | Discoveries, learnings, solutions, patterns | interject, interknow, docs/solutions |
| Review | Findings, verdicts, gates, evidence | flux-drive, interspect |
| Infrastructure | Plugins, skills, commands, hooks, MCP tools | plugin.json, interchart |

Each subsystem has its own ID scheme, storage, and query patterns. There is no way to ask: "Show me everything connected to this function" and get back beads, sessions, findings, and discoveries — because no system can recognize the same entity across subsystem boundaries.

### Why a Generative Architecture

The 4-track flux-review (16 agents across 4 semantic distance tiers) produced two findings with 4/4 convergence — the strongest possible signal:

1. **Entity identity resolution is the foundational problem.** The "show me everything about X" query requires mapping 5+ incompatible ID schemes to canonical entities. Every graph design is premature until identity is solved.

2. **The type system must be generative, not taxonomic.** A fixed catalog of ~30 entity types with individually declared relationships scales as O(type-pairs). A family-level relational calculus (~5 families, ~15 interaction rules) generates the full relationship matrix and new types inherit rules automatically.

Three additional findings at 3/4 convergence reinforce the design:

3. Source failure and contradiction must surface explicitly (freshness metadata per subsystem, progressive partial results, contradiction surfacing with source attribution).

4. Entities need multi-family membership with lifecycle transitions (a Session starts as Process-family, gains Work-tracking membership when a bead links, gains Knowledge membership after reflection).

5. Progressive adoption with minimal bootstrap (4-field minimum entity stubs → relationship stubs → deep metadata on demand).

### Cross-Domain Convergence (from flux-review)

| Pattern | Source Domains | Mechanism |
|---------|---------------|-----------|
| Generative relational calculus | Dogon bummo, Burmese bedin, heraldic blazon, SNOMED CT | Family-pair interaction rules derive relationships; per-type declarations are overrides |
| Diagnostic vs. contingent properties | Optical mineralogy (petrographic thin-section) | Identity-bearing properties (path, SHA, bead_id) invariant across views; other properties are view-dependent |
| Catalog-of-catalogs | Geospatial SDI (ASDI/NSDI/INSPIRE) | Index metadata + pointers; delegate data retrieval to source subsystems |
| Observation depth contracts | Persian qanat topology | Each connector declares entity types indexed, granularity, captured vs. inferred, refresh cadence |
| Formality gradient | FHIR binding strengths | Core types get strict schemas; peripheral types get extensible bindings |
| Confidence scoring on links | E-discovery litigation | Every cross-system relationship carries method, confidence level, and evidence |
| Query-context salience | Javanese gamelan pathet | "Show me everything about X" returns different orderings for debugging vs. planning vs. reviewing |
| Progressive partial results | Polynesian wayfinding | Fast sources return immediately; slow sources update later; unavailable sources marked explicitly |
| Multi-family lifecycle | Burmese bedin Ketu transition, Dogon twin seeds | Entity type is multi-valued and lifecycle-aware; transitions add family memberships |
| Finding-aid test | Archival science (respect des fonds) | If deleting the ontology leaves every subsystem fully functional, the design is correct |

## Key Decisions

### 1. Five composable type families

| Family | Covers | Diagnostic Property (identity-bearing) |
|--------|--------|---------------------------------------|
| **Artifact** | Files, functions, modules, tests, configs, docs | Canonical path or content hash |
| **Process** | Sessions, runs, sprints, builds, deployments | Process ID (session_id, run_id, bead_id) |
| **Actor** | Agents, models, humans, plugins, MCP servers | Actor identifier (plugin name, model ID, username) |
| **Relationship** | Dependencies, blocks, triggers, references, caused-by | (source_id, target_id, relationship_type) tuple |
| **Evidence** | Findings, verdicts, metrics, calibration data, discoveries | Evidence ID + source system |

New entity types declare their family membership(s). Family-level interaction rules determine which relationship types are valid. Per-type rules are overrides only.

**Platform validation:** These 5 families hold across Claude Code, Cursor, Devin, and Codex CLI. Evidence is thinner on simpler platforms (tool errors, lint results) but never absent. The richer the platform, the richer Evidence gets.

**Unclassified entities:** Entities without family membership get an "Unclassified" status. They have identity crosswalk entries and basic metadata, appear in search/discovery, but do not participate in the relational calculus (no derived relationships). Family membership activates rules progressively.

### 2. Seven family-interaction rules (the relational calculus)

These rules determine which relationship types are valid between entity families. New entity types inherit all rules for their declared families automatically.

| # | Rule | Family Pair | Valid Relationship Types |
|---|------|-------------|------------------------|
| 1 | **Productivity** | Actor × Process | executes, dispatches, delegates, monitors |
| 2 | **Transformation** | Process × Artifact | produces, modifies, reads, consumes, deploys |
| 3 | **Stewardship** | Actor × Artifact | owns, maintains, created, reviewed |
| 4 | **Structure** | Same × Same | imports, depends-on, references, blocks, parent-child, delegates-to |
| 5 | **Evidence Production** | {any} × Evidence | produces, evaluates, asserts-about, measures |
| 6 | **Annotation** | Evidence × Relationship | validates, disputes, strengthens, weakens |
| 7 | **Lifecycle** | {any} → transition → {any} | entities gain new family memberships over time |

**No hard tincture constraints needed.** All family pairs connect through at least one rule. The rules constrain WHICH relationship types are valid for a given family pair, not WHICH families can connect. Specific relationship types are derived from the rule number + the entity types involved.

**Inheritance:** A new entity type declares `families: [Process, Evidence]`. It automatically participates in Rules 1, 2, 4, 5, 6, and 7 — with relationship types appropriate to each family membership. No per-type declarations needed unless overriding a family default.

### 3. Identity crosswalk as the foundation layer

Every subsystem-specific entity ID maps to a canonical entity via an identity crosswalk:

```
(subsystem, subsystem_id) → canonical_entity_id
```

Resolution methods ranked by confidence:
- **Structural match** (highest): Git SHA, bead ID, session ID — deterministic
- **Path match**: File path normalization across subsystems
- **AST match**: Function signature + file context for function-level entities (Phase 1)
- **Temporal co-occurrence**: Entities appearing in the same time window — speculative, confidence-scored

The crosswalk is a materialized index, updated incrementally. Runtime queries are O(1) lookup, not O(subsystems^2) cross-join.

**Function-level identity (Phase 1):** File-level uses git rename detection and path normalization. Function-level uses AST fingerprinting: canonical signature = `(file_path, function_name, parameter_types, return_type)`. When functions are renamed/moved, tree-sitter diff + heuristic matching (body similarity > 80%) links old and new identities. The crosswalk records the identity chain: `fn_v1 → renamed_to → fn_v2`.

### 4. Observation contracts per connector

Each subsystem connector declares what it provides:

```yaml
connector: cass
entities_indexed: [session, tool_call]
granularity: session-level (tool calls as nested, not independent entities)
properties:
  captured: [session_id, start_time, model, total_tokens, files_touched]
  inferred: [intent_category, outcome_quality]
refresh: on-demand (cass index --full triggers)
freshness_signal: last_indexed_at
```

**Minimum discovery threshold** (4 required fields): entity_type, entity_id, subsystem, created_at. This is the floor — any subsystem can participate by reporting just these four fields. Richer metadata is progressive enhancement.

### 5. Confidence scoring on every cross-system link

Every relationship between entities from different subsystems carries:
- `method`: how the link was established (explicit-reference, temporal-cooccurrence, identifier-match, embedding-similarity)
- `confidence`: confirmed | probable | speculative
- `evidence`: list of supporting observations
- `created_at`, `last_verified_at`: temporal validity

Agents can filter by confidence level. Default queries exclude "speculative" links.

### 6. Named query templates over open-ended graph traversal

Instead of a query language, expose 5-10 named commands:

| Command | Query | Max hops | Result cap |
|---------|-------|----------|-----------|
| `related-work <entity>` | Beads linked to entity | 1 | 10 |
| `recent-sessions <entity>` | Sessions that touched entity | 1 | 10 |
| `review-findings <entity>` | Flux-drive findings mentioning entity | 1 | 20 |
| `causal-chain <entity>` | Blocks/caused-by/discovered-from traversal | 3 | 20 |
| `who-touched <entity>` | Agents/humans that modified entity | 1 | 10 |
| `evidence-for <entity>` | Interspect evidence, calibration data | 1 | 20 |

Each template has bounded traversal depth and result caps. Token cost is predictable. Agents call named commands without learning a schema.

**Query-context salience:** Results are ordered differently based on agent context (debugging prioritizes recent sessions + causal chains; planning prioritizes beads + blockers; reviewing prioritizes findings + evidence).

### 7. Four gravity-well safeguards

SAP MDG, Palantir Foundry, and Salesforce metadata layers all started as "projections" and became systems of record within 3-5 years. interweave has four structural safeguards:

1. **No-write-through contract:** interweave never writes to source subsystems. Not implemented, not planned, not architecturally possible. Write operations go through source systems directly.

2. **Staleness TTL:** Entities expire from the index if not refreshed within TTL (default: 30 days). Prevents the index from becoming "the truth" when sources have moved on.

3. **Finding-aid audit:** Quarterly, delete the entire interweave index. If anything breaks, that's a dependency that must be removed. This is the archival science respect-des-fonds test.

4. **Direct access preservation:** Never deprecate cass, beads, tldr-code, grep. Agent prompts always include both paths: "Use interweave for cross-system queries; fall back to direct tools if unavailable." If agents stop using direct tools, that's the early warning sign.

### 8. Philosophy amendment

Add a paragraph to PHILOSOPHY.md under "Composition Over Capability" explaining that a catalog-of-catalogs (index over existing stores with no data ownership, no write-through, and the finding-aid deletion test) satisfies the composition principle. This makes the architectural constraint explicit and prevents future drift toward system-of-record behavior.

### 9. Strictly additive, fail-silent, deletable

- **Fail-silent**: If interweave is down, agents fall back to direct tool access (cass, beads, tldr-code, grep) — degraded but functional
- **Deletable**: If you delete the entire interweave index, every subsystem continues to work
- **Append-only schema**: Types and properties can be added, never renamed or removed. Open-world assumption — interweave discovers entity types by observing what subsystems report, not by requiring declaration

## Open Questions

1. **Storage backend.** SQLite with adjacency tables? Embedded graph (e.g., kuzu)? The catalog-of-catalogs pattern doesn't need a full graph database, but the relational calculus needs efficient family-pair lookups.

2. **Connector protocol.** How do subsystems publish entity metadata to interweave? Options: (a) interweave crawls subsystem CLIs (harvest model, zero effort from producers), (b) subsystems push events (higher fidelity, requires integration work), (c) hybrid (crawl for baseline, push for real-time updates).

3. **Query-context detection.** How does interweave know the agent is debugging vs. planning vs. reviewing? Options: (a) explicit parameter (`--context=debugging`), (b) inferred from recent tool calls, (c) agent declares intent in the query.

4. **Cross-platform packaging.** For non-Sylveste platforms, interweave needs to work as a standalone tool. What's the minimal installation? A single binary with SQLite? An MCP server?

## Supporting Materials

- **Flux-review synthesis:** `docs/research/flux-review/ontology-graph-agentic-platforms/2026-04-04-synthesis.md`
- **Concept brief:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`
- **Agent specs (16 agents, reusable):**
  - `.claude/flux-gen-specs/ontology-graph-agentic-platforms-adjacent.json`
  - `.claude/flux-gen-specs/ontology-graph-agentic-platforms-orthogonal.json`
  - `.claude/flux-gen-specs/ontology-graph-agentic-platforms-distant.json`
  - `.claude/flux-gen-specs/ontology-graph-agentic-platforms-esoteric.json`
- **Prior art:** `docs/research/assess-magma-multi-graph-retrieval.md` (verdict: inspire-only for agent memory; interweave targets a different problem)
