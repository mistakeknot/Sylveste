### Findings Index
- P0 | ACQ-01 | "MVP milestone + D5 flux-drive triage view" | MVP Cypher query is not concretely plannable; four-way multiplication including community neighborhood hides a multi-hop traversal AGE plans poorly
- P1 | ACQ-02 | "D3. Storage + pgvector" | No stated plan for combining AGE graph match with pgvector similarity in a single query — AGE's planner does not reason about pgvector indexes
- P1 | ACQ-03 | "Open Questions: scale headroom" | "Scales to 10M entities" conflates entity count with edge count and traversal depth — the real perf drivers are unnamed
- P2 | ACQ-04 | "D9. Versioning: bi-temporal via timestamps" | `valid_from`/`valid_to` filters on every query will destroy index usage on vertex properties unless a current-version partial index strategy is specified
- P2 | ACQ-05 | "Epic shape #5: interlens MCP adapter" | Per-MCP-call Cypher queries without a caching layer will surface AGE's per-query planning cost on an interactive path
- P3 | ACQ-06 | "Appendix + D3" | Backup/restore story via pg_dump is asserted but unverified for AGE graphs at 1M+ edges
Verdict: risky

## Summary

AGE is the right governance story (one DB, pgvector co-located, no new ops) but the MVP's single most important query — the flux-drive triage selection — is described at a level of abstraction that hides its plannability. "Domain match × discipline coverage × effectiveness × community neighborhood" is either (a) a small, index-friendly query that doesn't actually use graph traversal, in which case the case for a graph DB weakens, or (b) a multi-hop community query that AGE will plan poorly. The brainstorm does not resolve which. A 2-week benchmark spike before committing to AGE-backed triage is warranted.

## Issues Found

### 1. [P0] MVP triage query is not concretely plannable — ACQ-01

**File:** `docs/brainstorms/2026-04-21-persona-lens-ontology-brainstorm.md`, §"MVP milestone" line 26 and D5 line 64.

The MVP deliverable is "measurable triage lift in /flux-drive when it queries the graph instead of filename-glob + tier heuristics," and the query is described as "Cypher queries for agent selection — domain match × discipline coverage × effectiveness × community neighborhood." Let me attempt to write this query and reason about its plan.

```cypher
MATCH (d:Diff {id: $diff_id})-[:in-domain]->(dom:Domain)
MATCH (p:Persona)-[:wields]->(l:Lens)-[:in-domain]->(dom)
OPTIONAL MATCH (p)-[:wields]->(l2:Lens)-[:in-discipline]->(disc:Discipline)
OPTIONAL MATCH (l)-[:bridges]-(l3:Lens)<-[:wields]-(p2:Persona)  // "community neighborhood" via bridges
WHERE l.effectiveness_score > 0.6
RETURN p, count(DISTINCT dom) AS dom_match, count(DISTINCT disc) AS disc_coverage,
       avg(l.effectiveness_score) AS eff, count(DISTINCT p2) AS neighborhood_size
ORDER BY dom_match * disc_coverage * eff * log(neighborhood_size+1) DESC LIMIT 10
```

Plan concerns:
- AGE compiles Cypher to a generated SQL plan over `ag_catalog.ag_graph` tables. Every `MATCH` becomes a join against the edge table `_ag_label_edge` (or per-label if labels are materialized). Four MATCHes means a four-way join with vertex property lookups.
- `(l)-[:bridges]-(l3:Lens)<-[:wields]-(p2:Persona)` is a 2-hop traversal that materializes the neighborhood. For a densely-bridged lens (say 50 bridges), with each bridged lens having 10 wielders, that's 500 rows per seed lens before aggregation. The 291 Auraken lenses already have bridge_score populated; bridge density is a known variable.
- AGE does not have a native graph storage format — edges live in SQL tables. Multi-hop traversal falls back to iterated joins, not an index-friendly depth-first walk. This is the widely-reported AGE-vs-Neo4j perf gap.
- The `ORDER BY dom_match * disc_coverage * eff * log(neighborhood_size+1)` requires materializing aggregates over the whole candidate set — no index can serve this; it's a post-GROUP BY sort.

**Failure scenario:** At 1200 entities with modest bridge density, the query runs in acceptable time (maybe 100-500ms). The moment Auraken lens count grows (flux-review runs generate new lenses continuously) or bridges densify, query time climbs non-linearly. The MVP demonstrates lift on a toy corpus then degrades in production. /flux-drive runs every sprint; if triage takes >2s the loop is unusable.

**Smallest fix (before Epic shape #4 starts):** Benchmark spike in week 1: load all 1200 entities + synthetic edges (target 10k edges, then 100k) into a test AGE instance. Run the above query (or its actual chosen form) with EXPLAIN ANALYZE. If p95 > 500ms at 10k edges, redesign: drop community neighborhood from MVP, or precompute community_id as a materialized column (already exists in Auraken), or fall back to a two-step query (graph for candidates, SQL for ranking).

### 2. [P1] AGE + pgvector combined query has no stated plan — ACQ-02

**File:** same brainstorm, D3 line 52.

"AGE is a Postgres extension — zero new ops surface, Cypher queries in the same DB as embeddings." The co-location is correct. The query-time integration is not addressed. A realistic triage query wants to combine:
- Graph match: "personas who wield lenses in this domain"
- Vector similarity: "...and whose embeddings are close to the diff's embedding"

These live in different query dialects. AGE Cypher produces vertex/edge rows; pgvector `<->` operates on table columns. You cannot write a single Cypher query that uses pgvector's IVFFlat or HNSW index. The options are:

(a) CTE with Cypher subquery + SQL vector filter — two planners, no unified optimization.
(b) Precompute per-diff candidate set in Cypher, then filter by embedding in app layer — two round-trips.
(c) Duplicate embeddings into vertex properties; use cosine distance function in Cypher — no index, full scan.

**Failure scenario:** First triage query that wants embedding similarity is re-architected mid-epic. The flux-drive view ships without embedding context, or ships with a 2-roundtrip pattern that becomes the template for every downstream consumer.

**Smallest fix:** In D3 or Epic shape #4, commit to one of (a)/(b)/(c) and name it. (a) is the most common pattern in production AGE+pgvector systems; it's the right default. Add a §§ noting the CTE-plus-filter pattern as the blessed query shape.

### 3. [P1] "10M entities" elides edge count and traversal depth — ACQ-03

**File:** same brainstorm, Open Questions §"Scale headroom" line 108.

"AGE scales to ~10M entities per the assessment." Entity count is not what breaks AGE at scale. What breaks it is:
- Edge count (every traversal touches the edge table)
- Traversal depth (AGE's translator doesn't optimize variable-length paths well)
- Concurrent writer load (DDL changes lock graph catalog)

At 1200 entities, fd-agents + Auraken + interlens produce ~1200 `wields` edges (if 1:1), plus `bridges` edges (Auraken already has bridge_score for many pairs — potentially 1000+), plus `same-as` from dedup (potentially 200+), plus `in-domain`/`in-discipline` (likely 2-5 per entity, so 2400-6000), plus `derives-from` (1 per entity, 1200). Rough total: 6000-10000 edges at V1. If lens generation industrializes, edges could 10x before entities do.

**Failure scenario:** The brainstorm projects comfort at 1200 entities but edge count is already 8x that. Scale headroom analysis is entity-count-anchored; the real question is "at what edge count does our worst query cross the SLO?"

**Smallest fix:** Revise the scale-headroom bullet to name edge density. Add a benchmark in Epic shape #1 that loads the schema with 10x current edge count and runs the MVP query.

### 4. [P2] Bi-temporal filters will destroy index usage — ACQ-04

**File:** same brainstorm, D9 line 83.

"We add `valid_from` / `valid_to` columns on entities and relationships." Without a strategy, every query must add `WHERE valid_to IS NULL OR valid_to > now()`. This predicate is not index-friendly on a B-tree — roughly half the versions will be current, so the index doesn't narrow much. AGE also wraps vertices in `agtype` JSON which further complicates property indexes.

**Failure scenario:** After 6 months of edits, Lens has 2x the rows (current + one superseded version average). Every triage query scans double the data, or you remember to add the predicate and AGE plans it poorly.

**Smallest fix:** Use a partial index pattern: `CREATE INDEX ON ag_label_vertex.lens (id) WHERE valid_to IS NULL;` — or materialize a `current_lens` view and query through it. Name this strategy in D9, not left as an implementation detail.

### 5. [P2] interlens MCP adapter needs a caching layer — ACQ-05

**File:** same brainstorm, Epic shape #5 line 94.

"Swap interlens MCP server's backend from bundled JSON to AGE queries. Contract-stable." MCP calls are interactive — agent asks `find_bridge_lenses`, expects a response in sub-second. Current bundled-JSON reads are O(ms). AGE Cypher queries for `find_bridge_lenses` involve at minimum a graph traversal with scoring; realistic latency is 50-200ms per call. Hermes conversational view may issue 5-10 MCP calls per turn.

**Failure scenario:** Hermes latency jumps from "instant" to "noticeable lag" after the adapter swap. Users feel it. Rollback considered.

**Smallest fix:** Epic shape #5 should include a cached projection: materialize common MCP query results (top-N bridges per lens, dialectic triads) into a read-optimized table refreshed on ingestion. MCP queries the cache, AGE populates it. Contract-stable, latency-equivalent to the JSON it replaces.

## Improvements

### 1. Backup/restore benchmark before production — ACQ-06

"pg_dump handles it" is true, but AGE graph data lives in `ag_catalog` tables with non-obvious dependencies. A restore test (dump, drop, restore, verify row counts and query correctness) should be part of Epic shape #1's DDL work, not assumed.

### 2. Write the EXPLAIN ANALYZE output into the epic plan

The quality-gate for Epic shape #4 (flux-drive triage view) should include a documented EXPLAIN ANALYZE of the MVP query at target scale. This is the single most useful artifact for proving the AGE bet works.

### 3. Name the observability plan

AGE doesn't have `EXPLAIN (FORMAT GRAPH)` or native graph query observability. Production queries need `log_min_duration_statement` tuning and a grafana panel for p95 Cypher query time. Add this to the plan step.

--- VERDICT ---
STATUS: fail
FILES: 0 changed
FINDINGS: 6 (P0: 1, P1: 2, P2: 2, P3: 1)
SUMMARY: The MVP triage query is not concretely plannable from the brainstorm alone; multi-hop community traversal is AGE's weak spot. Benchmark spike in week 1 is a hard prerequisite — otherwise the three-views promise is built on an unverified assumption.
---
<!-- flux-drive:complete -->
