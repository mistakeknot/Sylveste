### Findings Index
- P0 | CCP-1 | "Three Concrete Capabilities" | Unified entity graph contradicts 'unify retrieval, not storage' — the brief's 'read-only projection' defense is a semantic dodge that still creates a central store
- P1 | CCP-2 | "Three Concrete Capabilities" | Plugin registration pressure — ontology visibility creates de facto mandatory integration, violating fail-open independence
- P1 | CCP-3 | "Design Tensions" | Gravity well risk — organizational pressure will push the ontology from projection to system of record, and the brief provides no structural safeguards
- P1 | CCP-4 | "What Already Exists in Sylveste" | MAGMA assessment inconsistency — 'inspire-only' verdict for multi-graph memory vs. proposing a unified ontology graph contradicts the same reasoning
- P2 | CCP-5 | "Open Questions" | Premature ontology design — the brief proposes a schema before understanding actual cross-system query patterns
Verdict: risky

## Summary

This concept brief proposes the single largest architectural addition the platform has considered — a unified semantic layer over all subsystems. The PHILOSOPHY.md was written specifically to prevent this kind of move. The brief acknowledges the tension ("Composition vs. coupling: A unified graph is powerful but creates a central dependency," line 59) but doesn't resolve it. The "read-only projection" framing is a semantic defense that doesn't change the architectural reality: once the ontology exists, it becomes the gravitational center of the platform, and the composition-over-capability principle erodes through convenience, not malice.

## Issues Found

### 1. [P0] 'Read-only projection' is a semantic dodge for a central store (CCP-1)

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 47-48, 67
**Cross-reference:** `PHILOSOPHY.md`, lines 173-176

PHILOSOPHY.md line 175: "Unify retrieval, not storage. The real problem is fragmented read paths, not fragmented stores. A thin retrieval layer that queries across systems and returns ranked, deduplicated results solves discoverability without migration risk. Each system keeps its storage."

The brief proposes "Could this be a read-only projection (materialized view) rather than a system of record?" (line 67). This sounds compatible — the projection is a retrieval layer, not a storage layer.

But a materialized view IS a store. It has:
- **State:** A snapshot of all entities and relationships from all subsystems
- **Schema:** A type system that all entities must conform to
- **Infrastructure:** A graph database, CDC pipeline, and query engine
- **Operational burden:** Monitoring, backup, migration, staleness management

The philosophy says "thin retrieval layer" — meaning a query router that dispatches to existing backends and merges results. The brief proposes a thick projection layer — meaning a separate database that replicates state from all backends.

**The distinguishing test:** If the projection database is deleted, can the system still answer cross-system queries?

- **Thin retrieval layer:** Yes — the router dispatches to backends directly. Slower, but functional.
- **Materialized projection:** No — the graph database is the only place where cross-system relationships are materialized. Without it, agents lose all cross-system query capability.

This means the projection IS a system of record for cross-system relationships, even though each subsystem retains its own storage. The brief frames it as "read-only" to avoid the philosophical contradiction, but the operational reality is a new central dependency.

**Precedent from the project itself:** The memory architecture convergence PRD (`docs/prds/2026-03-07-memory-architecture-convergence.md`) explicitly chose "unify retrieval, not storage" and recommended a thin retrieval layer across 10 memory systems. The ontology brief proposes the opposite approach for the same problem at a different scope — without explaining why the reasoning that applied to memory doesn't apply to entities.

**Recommendation:** The brief should honestly evaluate two alternatives:
1. **Thin retrieval router** (philosophy-compatible): A query dispatcher that hits beads API, cass API, intercore API, and merges results. No separate database. Each query composes results from 2-3 backends. Slower but resilient — fails partially when one backend is down.
2. **Materialized graph projection** (philosophy-breaking): A separate graph database with CDC from all subsystems. Fast queries but central dependency. If this is the right choice, the philosophy should be updated to explain why the ontology is an exception.

Don't call option 2 "read-only projection" when it's architecturally a central store. Name the tradeoff honestly.

### 2. [P1] Plugin registration pressure creates de facto mandatory integration (CCP-2)

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 49-50
**Cross-reference:** `PHILOSOPHY.md`, lines 128-137

The brief proposes "Formal type system for platform entities... with declared capabilities, constraints, and allowed actions" (line 49). For an entity type to be queryable in the ontology, it must be declared in the schema.

PHILOSOPHY.md lines 128-131: "Standalone plugins fail-open, degrade gracefully without intercore. Value proposition is self-contained. The platform recommends compositions and detects missing companions, but no plugin requires another to function."

If a plugin doesn't register its entity types:
1. Its entities are invisible to "show me everything related to X"
2. Its entities can't be linked to entities from other subsystems
3. Agents can't discover what the plugin provides through the schema browser
4. The plugin appears broken to users who rely on ontology queries

This creates invisible pressure to register. No one forces plugins to register, but unregistered plugins are second-class citizens — visible to `grep` and `ls` but invisible to the platform's intelligence layer. Over time, "standalone" plugins that don't register become "broken" plugins in user perception.

**Failure scenario from the Kubernetes ecosystem:** Kubernetes Custom Resource Definitions (CRDs) were optional — you could deploy pods without defining custom resources. But once Operators became the standard deployment pattern, CRDs became de facto mandatory. Controllers that didn't register CRDs were invisible to `kubectl get all`. The "optional" registration became the only way to participate in the ecosystem's tooling.

The same pattern would apply here: once agents learn to query the ontology as their primary context-gathering tool, plugins that aren't in the ontology don't exist in the agent's world.

**Recommendation:** If the ontology proceeds, it must discover entity types automatically (by observing what subsystems report) rather than requiring declaration. Auto-discovery preserves fail-open independence because plugins don't need to know the ontology exists.

### 3. [P1] No structural safeguards against gravity well drift (CCP-3)

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 59-62

The brief identifies "Composition vs. coupling" as a design tension but proposes no mechanism to prevent the ontology from becoming the system of record.

**The gravity well pattern:**

Phase 1 (Year 1): Ontology is a read-only projection. Subsystems maintain their own storage. The ontology provides convenient cross-system queries.

Phase 2 (Year 2): New features are designed "ontology-first" — the entity type is defined in the ontology schema, then implemented in the subsystem. The ontology schema leads; the subsystem follows.

Phase 3 (Year 3): Some subsystems start reading from the ontology instead of their own storage for cross-system data. "Why maintain our own cross-reference when the ontology already has it?"

Phase 4 (Year 4): The ontology is the de facto system of record. Subsystem storage is vestigial. Deleting the ontology database would break the platform.

This isn't hypothetical — it's the documented trajectory of every "read-only" unified schema project in enterprise software. SAP's Master Data Governance, Palantir's Foundry Ontology itself, and Salesforce's metadata layer all started as "projections" and became systems of record within 3-5 years.

**Recommendation:** If the ontology proceeds, encode structural safeguards:
1. **No-write-through contract:** The ontology library exposes ONLY read operations. Write operations are not implemented, period — not "disabled by default."
2. **Staleness TTL:** Every entity in the projection has a TTL. If the source system's CDC hasn't refreshed it within the TTL, the entity is marked stale and excluded from query results. This makes the projection visibly degraded when sources are unhealthy, preventing it from being treated as authoritative.
3. **Dependency audit:** A quarterly check (automated via interwatch) that scans for code paths that read from the ontology for non-cross-system queries. Any subsystem reading from the ontology what it could read from its own store is a design regression.

### 4. [P1] MAGMA assessment inconsistency (CCP-4)

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 42-43
**Cross-reference:** `docs/research/assess-magma-multi-graph-retrieval.md`

The brief references the MAGMA assessment: "'inspire-only' because code has explicit structure (AST), determinism matters, and existing tools (cass, tldr-code) already cover semantic + structural retrieval."

The MAGMA assessment rejected a multi-graph memory architecture for these reasons:
1. Code has explicit structure — causal/entity edges exist as AST data
2. Determinism matters — non-deterministic graph traversal is worse than deterministic priority rendering
3. Existing tools already cover the use cases — cass for cross-session search, tldr-code for code structure
4. Engineering complexity vs. benefit — ~2000-4000 lines of Go for marginal improvement over ~225 lines

The ontology graph brief proposes:
1. A multi-graph structure (entity graph with typed relationships) over code + work + agent entities
2. Graph traversal for queries (non-deterministic result ordering based on edge weights)
3. Existing tools already cover most use cases (cass, beads, tldr-code, grep — as shown in the agent-ontology-runtime analysis)
4. Significant engineering complexity (CDC pipeline, graph database, schema management, query engine)

The reasoning that rejected MAGMA applies with equal force to the ontology graph. The brief should explain what's different — what specific factor makes a unified ontology graph viable when a multi-graph memory was rejected.

**Possible differentiators (the brief should address these):**
- Scale: MAGMA was per-session memory; the ontology is platform-wide. Does platform scale change the calculus?
- Consumers: MAGMA served one agent (Skaffen); the ontology serves all agents. Does shared benefit justify shared cost?
- Scope: MAGMA covered memory retrieval; the ontology covers entity relationships. Are these different enough problems?

Without explicit differentiation, the ontology brief contradicts the project's own assessment methodology.

### 5. [P2] Premature ontology design before understanding query patterns (CCP-5)

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 65-71

The brief's open questions include "What's the minimal viable ontology — which entity types and relationships would provide 80% of the value?" This is the right question asked at the wrong time.

PHILOSOPHY.md line 87: "Don't pay debt too early — cementing wrong abstractions is worse than messy scripts."

The brief proposes designing an ontology (6 entity categories, typed relationships, formal schema) without data on actual cross-system query patterns. We don't know:
- How often agents actually need cross-system context (is it every sprint? 1 in 10?)
- What cross-system queries agents would make (is it always "related beads" or is it diverse?)
- Which subsystem pairs are most frequently co-queried (beads+code? sessions+discoveries?)
- Whether the existing tools' failure mode is "wrong results" or "no results" (is the problem quality or discoverability?)

Without this data, any ontology design is speculative. The 6 entity categories and their relationships are hypotheses, not observations.

**Recommendation:** Before designing the ontology, instrument the existing tools:
1. Add telemetry to `cass search`, `bd search`, `tldr-code context` that logs what agents query and what they do with the results
2. After 30 days, analyze: what queries cross subsystem boundaries? Which pairs of subsystems are co-queried most? Which queries return empty or insufficient results?
3. Design the ontology's entity types and relationships from observed query patterns, not from entity enumeration

This is exactly the "closed-loop by default" pattern from PHILOSOPHY.md (lines 56-76): predict (hypothesize ontology), observe (instrument queries), calibrate (design from observations), then fallback (keep existing tools if ontology adds no value).

## Improvements

1. **Honestly name the architectural choice** — "materialized graph projection" or "thin retrieval router." Don't use "read-only projection" as a compromise term that obscures the real decision.

2. **Differentiate from the MAGMA assessment** — explain specifically why the reasoning that rejected multi-graph memory doesn't apply to the ontology graph.

3. **Add structural safeguards** against gravity well drift: no-write-through contract, staleness TTL, dependency audit.

4. **Instrument before designing** — collect 30 days of cross-system query telemetry before committing to entity types and relationships.

5. **Evaluate the "thin retrieval router" alternative** as the philosophy-compatible path — a query dispatcher over existing backends, not a separate graph database.

--- VERDICT ---
STATUS: fail
FILES: 0 changed
FINDINGS: 5 (P0: 1, P1: 3, P2: 1)
SUMMARY: The ontology graph contradicts the project's core philosophy of 'unify retrieval, not storage' and 'composition over capability.' The 'read-only projection' framing is a semantic defense that doesn't change the architectural reality of a central store. The brief should honestly evaluate a thin retrieval router (philosophy-compatible) vs. materialized graph (philosophy-breaking with explicit justification). The MAGMA assessment's 'inspire-only' verdict applies with equal force here.
---
<!-- flux-drive:complete -->
