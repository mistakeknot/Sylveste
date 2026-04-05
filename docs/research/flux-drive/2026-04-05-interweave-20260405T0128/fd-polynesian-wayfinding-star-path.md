### Findings Index
- P1 | STARPATH-1 | "F5: Named Query Templates" | Graceful degradation specified but not acceptance-tested — no criterion for partial results with source attribution
- P1 | STARPATH-2 | "F4: Confidence Scoring" | No contradiction detection — conflicting information from different sources returned without markers
- P2 | STARPATH-3 | "F5: Named Query Templates" | No multi-signal synthesis query — agents must manually synthesize across templates
- P2 | STARPATH-4 | "F5: Named Query Templates" | Entity-centric reference frame is correct but etak (moving reference) not operationalized in query API
- P2 | STARPATH-5 | "F8: Philosophy Amendment" | No query reliability documentation — traversal path confidence levels are implicit knowledge
Verdict: needs-changes

## Summary

The PRD addresses the wayfinding pattern's most critical concern — graceful degradation when sources are unavailable — in F5 line 88: "Graceful degradation: if a connector is unavailable, return partial results with source status." This is the right structural commitment. However, the acceptance criterion is a single line with no operational definition. What does "partial results" mean? Does the agent receive results from available connectors immediately, or does it wait for a timeout? What does "source status" include — just up/down, or also staleness and confidence? The pelu would say: you have acknowledged that clouds sometimes obscure the stars. You have not specified which swell patterns to read when they do.

## Issues Found

### STARPATH-1 (P1): Graceful degradation has no testable acceptance criteria

**File**: `docs/prds/2026-04-05-interweave.md`, line 88 (F5 acceptance criteria)

The single criterion: "Graceful degradation: if a connector is unavailable, return partial results with source status." This is structurally correct but operationally ambiguous.

**Concrete failure scenario**: Agent queries `related-work src/parser.py`. The cass connector is healthy (responds in 50ms). The beads connector is down (connection refused). The tldr-code connector is slow (responding in 30 seconds). What happens?

Possible behaviors (all consistent with the acceptance criterion):
1. Wait for all connectors (30+ seconds), return results from cass and tldr-code, error for beads. (Worst case: 30s latency for one slow connector.)
2. Return cass results immediately, mark beads as down and tldr-code as pending. Never update with tldr-code results. (Agent gets fast partial results but misses slow data.)
3. Return cass results immediately with source status, then progressively add tldr-code results when they arrive. (Best case but requires streaming or polling.)

The acceptance criterion does not specify which behavior is required. This is the P1 severity calibration scenario from the wayfinding agent: "the entire query blocks for 30 seconds waiting for one source system connector."

**Recommended fix**: Expand F5 graceful degradation into 3 testable criteria:
- "Query results include per-source availability status: {source: cass, status: ok, latency_ms: 50}, {source: beads, status: unavailable, error: connection_refused}, {source: tldr-code, status: timeout, threshold_ms: 5000}"
- "Queries return results from available connectors within 2 seconds. Connectors that have not responded within the per-connector timeout are marked as `status: timeout` in the result."
- "Results distinguish between 'no data from this source' (connector responded, no matches) and 'source unavailable' (connector did not respond)."

The navigator's principle: "no relationship exists" and "we could not check" are fundamentally different signals. The first narrows the search. The second widens it.

### STARPATH-2 (P1): No contradiction detection mechanism

**File**: `docs/prds/2026-04-05-interweave.md`, lines 60-71 (F4 acceptance criteria)

F4 defines confidence levels (confirmed, probable, speculative) and evidence lists per link. It defines staleness detection. But it does not define *contradiction detection* — what happens when two source systems assert contradictory facts about the same entity.

**Concrete failure scenario**: Beads says bead-xyz status is "closed" (work completed). But cass shows 3 active sessions still modifying files associated with bead-xyz's linked entities. These are contradictory: if the bead is closed, why is work continuing? The ontology returns both facts. An agent checking bead status sees "closed" from beads and moves on, never learning that cass disagrees. The agent's decision (skip bead-xyz, work is done) is based on query order, not signal reliability.

The pelu's principle: the star compass says east, the swell says northeast. The navigator does not ignore the swell — they weigh both signals and note the contradiction. The ontology should do the same.

**Recommended fix**: Add to F4 acceptance criteria: "Cross-source contradiction detection: when two sources assert conflicting states for the same canonical entity (e.g., beads: status=closed vs cass: active_sessions>0), the link or entity record includes a `contradiction` flag with both assertions and their sources. Default query filter surfaces contradictions as warnings, not silent resolution."

Minimal implementation: define 3 known contradiction patterns (closed-but-active, deleted-but-referenced, renamed-but-old-name-active) as F4 unit tests. Future connectors can add patterns. This is not general-purpose contradiction reasoning — it is specific, enumerated pattern matching.

### STARPATH-3 (P2): No multi-signal synthesis query

**File**: `docs/prds/2026-04-05-interweave.md`, lines 78-88 (F5 acceptance criteria)

The 6 named queries are each single-signal: `related-work` queries beads, `recent-sessions` queries cass, `review-findings` queries flux-drive, etc. Each returns results from one primary source. No query synthesizes signals from multiple sources into a single coherent answer.

**Failure scenario**: An agent needs "what is the health of module X?" This requires: code quality (from tldr-code), test results (from cass sessions), bead progress (from beads), review findings (from flux-drive), and activity (from cass sessions). The agent must call 4-5 queries, spend ~2000 tokens on results, and synthesize manually. This manual synthesis is error-prone — the agent may weight sources incorrectly or miss contradictions.

The pelu's position estimate is not any single signal but a *weighted synthesis*. Interweave provides individual signal readings but no synthesis.

**Recommended fix**: This is acknowledged as P2 (not P1) because single-signal queries are the correct v0.1 scope. But add to Open Questions: "Should v0.2 include synthesis queries that combine results from multiple templates with explicit weighting? Example: `health-check <entity>` returns a synthesized score from code quality + test results + bead progress + review findings, with per-source contribution weights and confidence."

### STARPATH-4 (P2): Entity-centric reference frame correct but etak not operationalized

**File**: `docs/prds/2026-04-05-interweave.md`, lines 85, 96-99 (F5 and F6)

The query model is entity-centric: all 6 templates take `<entity>` as input and return related entities. This is the correct reference frame for the most common agent question ("tell me about X"). F6 adds context modes (debugging, planning, reviewing) that change result ordering.

But the etak (moving reference frame) insight is not operationalized. In Micronesian navigation, the canoe is conceptualized as stationary while the islands move past it. The analogous query pattern would be: instead of "show me what is connected to entity X" (entity-centric, static), "show me what has changed around entity X since my last query" (entity-centric, temporal-relative). This would let agents track evolving context without re-querying everything.

**Recommended fix**: Add to Open Questions: "Should named query templates support temporal-relative queries? Example: `recent-sessions src/parser.py --since=last-query` returns only sessions since the agent's previous query for the same entity. This reduces token cost for repeated queries and aligns with the etak pattern — the agent's context is the fixed point, and the environment changes around it."

### STARPATH-5 (P2): No query reliability documentation

**File**: `docs/prds/2026-04-05-interweave.md`, lines 116-119 (F8 acceptance criteria)

F8 specifies documentation including "development guide, architecture overview, connector development guide" and "operational reference, troubleshooting, CLI reference." But no criterion requires documentation of *query reliability* — which query templates produce high-confidence results, which traversal paths are reliable, and which combinations are known to produce misleading results.

The pelu's apprenticeship insight: wayfinding knowledge cannot be reduced to rules because the synthesis skill requires knowing which signal to trust in which conditions. The analogous requirement for interweave: agent developers need a "reliability chart" showing which queries are trustworthy under which conditions.

**Recommended fix**: Add to F8 acceptance criteria: "Agent developer guide includes a query reliability table showing: each named query template, its primary data sources, confidence level (high/medium/low), known edge cases, and recommended fallback when interweave is unavailable." This is the "star chart" for agents — which signals to trust, when, and what to do when they are unavailable.

## Improvements

1. **Source attribution in all results**: F5 line 86 says "Results include source subsystem attribution." Strengthen to: "Each result item includes {source_subsystem, freshness_timestamp, confidence_level}." This gives agents the meta-information to weight signals, matching the navigator's practice of weighting signals by reliability in current conditions.

2. **Timeout budget per query template**: Add to F5 a per-template timeout budget. `related-work` (1 hop) should timeout faster than `causal-chain` (3 hops). This prevents the "slowest connector blocks everything" problem without requiring streaming/progressive results.

3. **Connector health dashboard**: Add to F7 a persistent health metric beyond the point-in-time `interweave health` command. Track connector response times over time to identify degradation trends before they cause query failures. The navigator reads long-term weather patterns, not just current conditions.

<!-- flux-drive:complete -->
