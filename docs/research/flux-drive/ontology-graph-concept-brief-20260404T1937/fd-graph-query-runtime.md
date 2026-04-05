### Findings Index
- P0 | GQR-1 | "Three Concrete Capabilities" | Unbounded 'everything related to X' traversal — no depth limit, fan-out cap, or query cost model
- P1 | GQR-2 | "Three Concrete Capabilities" | Materialized view refresh rate incompatible with agentic development velocity — code changes per commit, sessions per hour
- P1 | GQR-3 | "Open Questions" | 'Read-only projection' feasibility unanalyzed — write amplification and staleness bounds not estimated
- P2 | GQR-4 | "What Already Exists in Sylveste" | Six existing query interfaces would need adapter integration — no analysis of query translation cost
Verdict: needs-changes

## Summary

The brief proposes graph capabilities ("show me everything related to X," "traverse relationships across all data sources") without any query cost analysis. These are the most expensive operations in any graph database. The concept's ambition (cross-system traversal over 6+ subsystems) combined with the platform's write velocity (code changes every commit, sessions every hour, beads every sprint) creates a query performance problem that the brief doesn't acknowledge, let alone solve. The "read-only projection" idea is promising but needs concrete staleness bounds and write amplification estimates before it can be evaluated.

## Issues Found

### 1. [P0] Unbounded 'everything related to X' traversal (GQR-1)

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 28, 47-48

The motivating query — "Show me everything connected to this function" — is a breadth-first traversal from a starting node with no declared depth limit. In graph database terms, this is `MATCH (n)-[*]-(m) WHERE n.name = 'function_name' RETURN m` — an unbounded path expansion.

**Cost analysis for Sylveste's entity graph:**

Starting from a core utility function (e.g., `routing_resolve_agents` in lib-routing.sh):
- **Hop 1 (direct):** 5-10 files that import it, 3-5 sessions that modified it, 2-3 beads that tracked work on it, 1-2 discoveries referencing it. ~20 nodes.
- **Hop 2 (transitive):** Each of those 5-10 files has its own imports (10-20 each), sessions (3-5 each), beads (1-2 each). ~200 nodes.
- **Hop 3:** Each of those 200 nodes connects to more files, sessions, beads. The graph has small-world properties (high clustering, short path lengths). ~2000+ nodes.
- **Hop 4:** Effectively the entire graph. A platform with 60+ plugins, 100s of beads, 1000s of sessions, and 10000s of files converges to full connectivity at 4 hops.

If this query runs at agent runtime (the brief proposes "Agent-Queryable Relationships," line 53), the result set consumes the agent's entire context window, costs significant tokens, and takes seconds to materialize — for a query that returns "everything" and therefore communicates nothing useful.

**Failure scenario:** An agent during a sprint asks "what's related to this function?" as a context-gathering step. The query returns 2000 nodes. The agent's context window fills with entity metadata. The agent either times out or hallucinates a response based on the noise. The sprint stalls. At Sylveste's target of ~$2.93/landable change, even one such query per sprint adds measurable cost.

**Precedent:** Neo4j's production deployment guide explicitly warns against unbounded traversals (`*` path length) and recommends hard limits: `[*1..3]` for exploratory queries, `[*1..2]` for agent-facing APIs. TigerGraph's GSQL requires explicit depth parameters on all `ACCUM` traversals. Amazon Neptune throttles queries exceeding 120s by default.

**Recommendation:** Define a query cost model before building:
1. **Depth budget:** Max 2 hops for cross-system traversal, 3 for within-system
2. **Fan-out limit:** Return top-K results per hop (K=10 default), ranked by edge weight
3. **Token budget:** Cap total result size at 2000 tokens (agent context economics)
4. **Query shapes:** Pre-define 5-10 useful query templates ("related beads," "recent sessions," "review findings") instead of open-ended traversal

### 2. [P1] Materialized view refresh rate problem (GQR-2)

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 61-62

The brief notes "A code ontology changes every commit" but doesn't estimate the write rate or the materialized view refresh cost.

**Write rate estimate for Sylveste:**
- Git commits: ~5-20 per sprint day (agent-driven development, fast cadence)
- Each commit: 2-10 files changed → 2-10 entity updates + relationship updates for each file's imports/exports
- Sessions: 10-30 per day → 10-30 session entity creates + file-touch relationships
- Beads: 5-15 per day (create/update/close)
- Discoveries: 2-5 per day

**Total write rate:** ~100-500 entity/relationship mutations per day.

**Materialized view cost:** If the graph is a read-only projection (the brief's suggestion at line 67), every mutation in the source system triggers:
1. Read the source entity's new state
2. Map it to the ontology schema
3. Update the entity node in the projection
4. Update all relationship edges (fan-out: 5-20 edges per entity)
5. Invalidate and recompute any pre-computed traversal caches

At 500 mutations/day, this is ~2500-10000 graph operations/day — manageable for a graph database, but the latency question is critical: how fresh must the projection be?

- **Synchronous refresh:** Source mutation blocks until projection updates. Adds 50-200ms per mutation. Makes every git commit, bead update, and session start slower. Unacceptable for an agent-driven platform where speed is the product.
- **Async refresh with bounded staleness:** Source mutation fires-and-forgets, projection catches up within N seconds. Acceptable if N < 30s (agent won't query the graph within 30s of the mutation that created the entity). But this means agents querying immediately after a code change get stale results.
- **Batch refresh:** Projection rebuilds on a schedule (every 5 minutes, every hour). Cheap but stale. An agent working in a sprint might not see its own recent work.

**Failure scenario:** Agent commits a change to `session.go`, then queries the graph for "what tests cover this file?" The materialized view hasn't refreshed yet (30s staleness). The graph returns the pre-commit test coverage. The agent skips writing a test because the graph says coverage exists — but the coverage data was for the old version of the function.

**Recommendation:** If the projection proceeds, the staleness bound must be < 5 seconds for entities the current agent has modified (read-your-writes consistency). This likely means a hybrid approach: synchronous for the agent's own mutations, async for everything else.

### 3. [P1] 'Read-only projection' feasibility unanalyzed (GQR-3)

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, line 67

The brief asks "Could this be a read-only projection (materialized view) rather than a system of record?" This is the right question, but the brief doesn't attempt to answer it.

A read-only projection over 6+ source systems requires:

1. **Change data capture (CDC)** from each source system. Beads has JSONL backup export. Intercore has SQLite. Cass has its own index. Interlens has a NetworkX graph. Intertree has filesystem state. Interkasten has the Notion API. Each requires a different CDC adapter.

2. **Schema mapping** from each source format to the ontology format. Beads' JSONL has different fields than intercore's SQLite tables. The mapping must be maintained as source schemas evolve.

3. **Conflict resolution** when sources disagree. If beads says a work item is "in_progress" and intercore says the corresponding run is "completed," which wins?

4. **Garbage collection** when source entities are deleted. If a bead is closed and purged, does the projection delete the node? What about the edges that referenced it?

**Write amplification estimate:** Each source entity change produces 1 node upsert + N edge upserts (N = number of relationships). For an entity with 5 relationships, write amplification is 6x. For 500 source mutations/day, the projection processes 3000 operations/day. This is tractable but non-trivial infrastructure.

**Recommendation:** Before committing to the projection approach, build a prototype CDC adapter for one subsystem (beads is the best candidate — JSONL export is simple, entity model is clean) and measure:
- CDC latency (how fast can changes be detected?)
- Mapping complexity (how many lines of code per entity type?)
- Write amplification (actual operations per source mutation)
- Query latency (how fast are reads from the projection?)

If the prototype takes more than a week or the measurements are worse than expected, the projection approach is too expensive for the current stage.

### 4. [P2] Six existing query interfaces need adaptation (GQR-4)

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 34-40

The brief lists 6 existing graph-like structures. Each has its own query interface:

| System | Query Interface | Query Language |
|--------|----------------|---------------|
| Interlens | NetworkX Python API | Python (PageRank, community detection, path finding) |
| Beads | `bd` CLI + Dolt SQL | SQL via Dolt |
| Interchart | D3.js force graph | JavaScript (browser-only) |
| Intercore | SQLite via Go | SQL (ic CLI, Go API) |
| Intertree | Filesystem + tags | Bash/Go (file operations) |
| Interkasten | Notion API | REST API |

A unified graph query would need to either:
- **Federate:** Route each sub-query to the appropriate backend and merge results. This is the "unify retrieval, not storage" approach aligned with philosophy. But federation requires query planning (which backends to hit for which parts of the query), result merging (different return formats), and timeout management (slowest backend determines latency).
- **Replicate:** Copy all data into a single graph database and query it directly. This is simpler for queries but contradicts the philosophy and requires CDC for all 6 systems.

The brief doesn't discuss the query translation layer — how does a graph traversal query get decomposed into SQL queries (beads, intercore), Python API calls (interlens), and REST calls (interkasten)?

**Recommendation:** Evaluate whether a federated query layer (like Hasura or GraphQL federation) over the existing query interfaces would satisfy the "unified query" requirement without building a separate graph database. This aligns with "unify retrieval, not storage" and avoids the CDC/projection infrastructure.

## Improvements

1. **Add a "Query Cost Model" section** with concrete traversal depth budgets, fan-out limits, and result size caps. No graph system should ship without these.

2. **Estimate write rates from actual platform telemetry** (interstat has this data) and derive materialized view refresh costs.

3. **Prototype the "read-only projection" with one subsystem** (beads) before designing the full system. Measure CDC latency, mapping complexity, and query performance.

4. **Evaluate federated query** as an alternative to materialized projection — it better aligns with the "unify retrieval, not storage" philosophy.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 4 (P0: 1, P1: 2, P2: 1)
SUMMARY: The brief proposes unbounded cross-system traversal without any query cost model. The 'everything related to X' query degenerates into 'everything' at 3+ hops. The materialized view refresh rate problem is real but solvable — if staleness bounds are defined upfront. Federated query over existing interfaces may be a better fit for the philosophy than a separate graph database.
---
<!-- flux-drive:complete -->
