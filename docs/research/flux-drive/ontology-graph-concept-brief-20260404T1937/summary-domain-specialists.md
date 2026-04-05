# Flux-Drive Synthesis: Ontology Graph Concept Brief — Domain Specialist Track

**Document reviewed:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`
**Review date:** 2026-04-04
**Agents dispatched:** 5 domain specialists (ontology-schema-evolution, entity-resolution-identity, graph-query-runtime, agent-ontology-runtime, composition-coupling-philosophy)
**Overall verdict:** NEEDS-CHANGES (2 agents: fail, 3 agents: warn)

---

## Executive Summary

The concept brief identifies a real problem — fragmented entity spaces across 6+ subsystems — but every agent found that the proposed solution either contradicts the project's explicit philosophy or leaves critical design questions unanswered. The review surfaced **24 findings** (3 P0, 12 P1, 9 P2) with strong convergence across agents on three themes:

1. **The headline capability is an entity resolution problem, not a graph problem.** "Show me everything connected to this function" requires knowing that a file path, a symbol name, and a session reference all denote the same entity. The brief treats identity as solved; it is the hardest unsolved problem.

2. **The "read-only projection" framing doesn't resolve the philosophy contradiction.** A materialized graph projection IS a central store — it has state, schema, infrastructure, and operational burden. The philosophy says "thin retrieval layer"; the brief proposes a thick projection layer.

3. **No demonstrated agent capability delta over existing tools.** The brief doesn't identify a single concrete agent workflow where the ontology outperforms the existing toolset of `cass search`, `bd list`, `tldr-code context`, and `grep`.

---

## Convergence Analysis

### Cross-Agent Agreement (high confidence)

**All 5 agents independently flagged:**

- **Premature abstraction risk.** The 6 entity categories cement a type hierarchy before usage patterns are understood. Every agent noted that the categories conflate organizational convenience with ontological structure. (OSE-1, ERI-4, AOR-1, CCP-5)

- **Philosophy contradiction.** The unified entity graph tensions with "unify retrieval, not storage" regardless of the "read-only projection" framing. (CCP-1, AOR-2, GQR-3)

- **Missing entity resolution.** The brief proposes graph structure without addressing how entities are identified across subsystems with incompatible ID schemes. (ERI-1, ERI-2, OSE-3)

**4 of 5 agents flagged:**

- **MAGMA assessment inconsistency.** The reasoning that produced an "inspire-only" verdict for multi-graph memory applies with equal force to the ontology graph. The brief doesn't explain what's different. (CCP-4, AOR-1)

- **No schema evolution strategy.** In a weekly-shipping plugin ecosystem, a fixed ontology becomes a liability within months. (OSE-2, OSE-5, CCP-2)

### Cross-Agent Disagreement (productive tension)

- **Thin retrieval router vs. materialized projection:** The composition-coupling-philosophy agent strongly advocates for a thin retrieval router (query dispatcher over existing backends). The graph-query-runtime agent acknowledges this is more philosophy-compatible but notes that federated queries have their own complexity (query planning, result merging, timeout management). Neither option is free.

- **Named queries vs. query language:** The agent-ontology-runtime agent recommends named queries (predefined templates like "related-beads") to avoid the bootstrap problem. The graph-query-runtime agent notes this limits the graph's expressiveness and may not justify the infrastructure cost — if you're only offering 10 named queries, a simple join layer achieves the same result without a graph database.

---

## P0 Findings (3)

| ID | Agent | Finding | Risk |
|----|-------|---------|------|
| ERI-1 | entity-resolution-identity | No entity resolution strategy — the headline use case requires cross-system identity mapping that the brief doesn't address | Graph would be disconnected subgraphs in practice |
| AOR-2 | agent-ontology-runtime | Ontology as hard runtime dependency violates fail-open philosophy | Single point of failure for all cross-system queries |
| CCP-1 | composition-coupling-philosophy | 'Read-only projection' is a semantic dodge for a central store — contradicts 'unify retrieval, not storage' | Architectural foundation contradicts project philosophy |

## P1 Findings (12)

| ID | Agent | Finding |
|----|-------|---------|
| OSE-1 | ontology-schema-evolution | Six entity categories cement premature type hierarchy |
| OSE-2 | ontology-schema-evolution | No schema evolution strategy for weekly-shipping plugin ecosystem |
| OSE-5 | ontology-schema-evolution | Closed-world assumption incompatible with plugin ecosystem |
| ERI-2 | entity-resolution-identity | Five incompatible ID schemes with no identity crosswalk |
| ERI-3 | entity-resolution-identity | Temporal identity gap — refactoring severs all historical connections |
| ERI-5 | entity-resolution-identity | Transitive identity closure creates false equivalences at 3+ hops |
| GQR-2 | graph-query-runtime | Materialized view refresh rate incompatible with development velocity |
| GQR-3 | graph-query-runtime | 'Read-only projection' feasibility unanalyzed — no write amplification estimates |
| AOR-1 | agent-ontology-runtime | No demonstrated capability delta over existing tools |
| AOR-3 | agent-ontology-runtime | Bootstrap problem — schema knowledge costs tokens before delivering value |
| AOR-5 | agent-ontology-runtime | Actions concept creates TOCTOU races with source systems |
| CCP-2 | composition-coupling-philosophy | Plugin registration pressure creates de facto mandatory integration |
| CCP-3 | composition-coupling-philosophy | No structural safeguards against gravity well drift |
| CCP-4 | composition-coupling-philosophy | MAGMA assessment inconsistency — same reasoning applies here |

## P2 Findings (9)

OSE-3 (homonymous relationships), OSE-4 (property vs. relationship boundary), ERI-4 (granularity mismatch), GQR-1 (unbounded traversal — initially P0 from graph-query-runtime but already covered by the depth-budget recommendation), GQR-4 (six query interfaces need adaptation), AOR-4 (context window economics), CCP-5 (premature design before query pattern data).

---

## Recommended Path Forward

The agents converge on a specific alternative that satisfies the brief's goals while respecting the philosophy:

### Phase 0: Instrument (2 weeks)
Add telemetry to existing tools (`cass search`, `bd search`, `tldr-code context`) that logs cross-system query patterns. After 30 days, analyze which subsystem pairs are co-queried and which queries return insufficient results.

### Phase 1: Thin Retrieval Router (4 weeks)
Build a query dispatcher that hits 2-3 backends (beads API, cass API, intercore API) and merges results. No graph database. No CDC pipeline. No schema management. This is the "unify retrieval, not storage" implementation that the memory architecture PRD already recommended.

Expose as named commands: `related-beads <file>`, `recent-sessions <file>`, `review-findings <file>`. Agents call these without learning a schema.

### Phase 2: Entity Resolution Layer (4 weeks)
Build the cross-system identity mapping for the file-level canonical entity type only. Use structured links that already exist (cass file paths, intercore run artifacts, flux-drive finding file references). Defer function-level and natural-language entity resolution.

### Phase 3: Evaluate (2 weeks)
After Phases 1-2 are deployed and instrumented, evaluate: do the named queries satisfy 80% of cross-system query needs? If yes, stop — the thin router is sufficient. If no, the telemetry data from Phase 0 will reveal exactly which entity types and relationships are needed for a graph, and the Phase 2 identity layer provides the foundation.

This path produces working cross-system queries in 6 weeks without creating a central dependency, without contradicting the philosophy, and without cementing premature abstractions.

---

## Output Files

| File | Agent | Verdict | Findings |
|------|-------|---------|----------|
| `fd-ontology-schema-evolution.md` | Schema evolution specialist | warn | 5 (0 P0, 3 P1, 2 P2) |
| `fd-entity-resolution-identity.md` | Entity resolution specialist | fail | 5 (1 P0, 3 P1, 1 P2) |
| `fd-graph-query-runtime.md` | Graph query specialist | warn | 4 (1 P0, 2 P1, 1 P2) |
| `fd-agent-ontology-runtime.md` | Agent-ontology interaction specialist | warn | 5 (1 P0, 3 P1, 1 P2) |
| `fd-composition-coupling-philosophy.md` | Architectural philosophy specialist | fail | 5 (1 P0, 3 P1, 1 P2) |
