### Findings Index
- P1 | GQR-1 | "F5: Named Query Templates" | Token cost <500 target is unrealistic for causal-chain (3 hops, max 20)
- P2 | GQR-2 | "F5: Named Query Templates" | No index strategy specified for SQLite adjacency tables
- P1 | GQR-3 | "Non-goals" | SQLite adjacency tables will degrade at multi-hop traversal — the non-goal of "no graph database" needs a performance contract
- P2 | GQR-4 | "F3: Connector Protocol" | Harvest model refresh timing creates a consistency window where queries return stale data
- P1 | GQR-5 | "F5: Named Query Templates" | causal-chain query (3 hops) has unbounded fan-out without intermediate filtering
Verdict: needs-changes

## Summary

The PRD makes a strong architectural decision in F5: named query templates with bounded traversal instead of open-ended graph queries. This directly addresses the most common graph database failure mode (unbounded traversal blowing up context windows). The choice of SQLite over a graph database is defensible for the described workload — 6 named queries with bounded depth, not arbitrary graph patterns. However, the performance characteristics of multi-hop queries on SQLite adjacency tables need explicit contracts, and the token cost targets are optimistic for the 3-hop causal-chain query.

## Issues Found

### 1. [P1] Token cost <500 target unrealistic for causal-chain (GQR-1)

**File**: `docs/prds/2026-04-05-interweave.md`, F5, lines 82-87

The PRD specifies "Token cost per query < 500 tokens (result formatting)" and "causal-chain <entity>: blocks/caused-by/discovered-from traversal (3 hops, max 20)."

At 3 hops with max 20 results, each result needs: entity ID, entity type, subsystem attribution, relationship type, and a human-readable label. A minimal result line is ~25-30 tokens. 20 results = 500-600 tokens for results alone, before query metadata, source attribution, and relationship context.

More critically, the 3-hop traversal can fan out significantly. If entity A has 5 causal links at hop 1, each of those has 5 links at hop 2, and each of those has 5 at hop 3, that's 125 candidate results before the max-20 filter. The computation to produce those 20 results touches 125+ nodes. Even if only 20 are returned, the query itself may be expensive.

**Failure scenario**: Agent issues `causal-chain` for a high-connectivity entity (e.g., a core utility function). The 3-hop traversal touches hundreds of nodes, takes >2 seconds (SQLite joins on adjacency tables), and the 20-result output consumes ~600 tokens. The agent's context budget for this query was 500 tokens; the extra 100+ tokens push downstream processing over budget.

**Recommendation**: Split the token cost target: "<500 tokens for 1-hop queries (5 of 6 templates), <800 tokens for causal-chain (3-hop)." Alternatively, add a cost estimate to each query response header: `estimated_tokens: 650` so agents can decide whether to expand the result.

### 2. [P2] No index strategy specified for SQLite adjacency tables (GQR-2)

**File**: `docs/prds/2026-04-05-interweave.md`, Non-goals, line 123

"interweave uses SQLite with adjacency tables, not Neo4j/kuzu/etc."

SQLite adjacency table queries require self-joins for multi-hop traversal. Without explicit indexes, a 3-hop query on a table with 100K+ links degrades to O(n^3) in the worst case. The PRD should specify the minimum index requirements:
- Index on `(source_entity, relationship_type)` — for forward traversal
- Index on `(target_entity, relationship_type)` — for reverse traversal
- Index on `(source_entity, target_entity)` — for link existence checks
- Composite index on `(relationship_type, confidence)` — for filtered traversal

**Recommendation**: Add to F2 or F5 acceptance criteria: "SQLite schema includes covering indexes for all 6 named query patterns. Query execution plans verified with `EXPLAIN QUERY PLAN` — no full table scans for any named query."

### 3. [P1] SQLite adjacency at multi-hop needs a performance contract (GQR-3)

**File**: `docs/prds/2026-04-05-interweave.md`, Non-goals, line 123

The non-goal "no graph database" is a defensible architectural decision for v0.1 with 6 bounded queries. But it needs a performance contract to prevent silent degradation as the index grows.

SQLite recursive CTEs (required for multi-hop traversal) have known performance characteristics:
- 1-hop: O(fanout) — fast, index-friendly
- 2-hop: O(fanout^2) — acceptable with proper indexes
- 3-hop: O(fanout^3) — can degrade significantly with high-connectivity nodes

With 60+ plugins producing entities, and sessions touching multiple files, the average fan-out per entity will increase over time. A function touched by 50 sessions has fan-out 50 at hop 1 alone.

**Failure scenario**: After 6 months of use, a `causal-chain` query on a frequently-edited core file takes >5 seconds because the recursive CTE traverses thousands of intermediate nodes. Agents timeout or the query dominates the session latency budget.

**Recommendation**: Add to F5 acceptance criteria: "All named queries complete in <200ms for indexes up to 100K entities and 500K links (benchmark required). If a query exceeds the latency budget, return partial results with a `truncated: true` flag rather than timing out." This makes the performance contract testable and the degradation graceful.

### 4. [P2] Harvest model creates a consistency window (GQR-4)

**File**: `docs/prds/2026-04-05-interweave.md`, F3, line 57 + Open Question 2

"Harvest model: interweave crawls connectors (zero effort from producers)." Combined with Open Question 2 about refresh scheduling, this means there is always a consistency window between reality and the index.

For the `recent-sessions <entity>` query: if a session just touched `src/auth.py` 30 seconds ago, but the cass connector hasn't been harvested since, the query returns stale results. The agent doesn't know the result is stale.

The PRD's F7 staleness TTL (30 days) is too coarse — it addresses long-term decay but not the short-term consistency problem that affects agent decision-making in real-time.

**Recommendation**: Add freshness metadata to every query response: `last_harvested: {timestamp}` per connector, so agents can see how fresh the data is. For the "recent-sessions" query specifically, consider a pass-through mode that queries cass directly when the harvest is older than the session TTL. This preserves the catalog-of-catalogs architecture (interweave never owns data) while providing fresh results for time-sensitive queries.

### 5. [P1] causal-chain 3-hop has unbounded intermediate fan-out (GQR-5)

**File**: `docs/prds/2026-04-05-interweave.md`, F5, line 82

"causal-chain <entity>: blocks/caused-by/discovered-from traversal (3 hops, max 20)"

The "max 20" limit applies to the final result set, but the intermediate traversal is unbounded. At each hop, ALL matching entities are expanded before the final result is pruned. For high-connectivity nodes, this means:
- Hop 1: entity E has 50 causal links (all 50 expanded)
- Hop 2: those 50 entities have 10 links each = 500 candidates (all expanded)
- Hop 3: those 500 have 5 links each = 2,500 candidates
- Final filter: take top 20 from 2,500

The query touched 3,050 nodes to return 20 results. This is the classic "graph explosion" problem.

**Recommendation**: Add intermediate fan-out limits: "At each hop, expand at most K nodes (K=50). If more than K nodes exist at an intermediate hop, select the top K by recency or confidence score." This turns unbounded BFS into bounded beam search. Add to F5 acceptance criteria: "causal-chain intermediate fan-out limited to 50 nodes per hop."

## Improvements

1. **Add query cost estimation to F5.** Before executing a query, return a cost estimate: `estimated_results: 15, estimated_tokens: 400, estimated_latency_ms: 50`. This lets agents make informed decisions about whether to proceed, especially for the expensive causal-chain query.

2. **Consider materialized 1-hop neighborhoods.** For the 5 single-hop queries, pre-compute each entity's direct neighbors and store as a materialized view. This converts runtime joins into single-row lookups. The write amplification is manageable because the harvest model is already batch-oriented — materialize after each harvest, not after each change.

3. **Specify the "max 20" ordering strategy.** When a 1-hop query returns 50 candidates and must select 20, what ordering is used? Recency? Confidence? Relevance to query context? The F6 salience feature addresses this for different agent contexts, but F5 needs a default ordering that works without F6.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 5 (P0: 0, P1: 3, P2: 2)
SUMMARY: SQLite adjacency tables are defensible for bounded queries, but the 3-hop causal-chain query needs intermediate fan-out limits and a performance contract to prevent graph explosion on high-connectivity nodes.
---
<!-- flux-drive:complete -->
