### Findings Index
- P1 | NAV-1 | "Agent-Queryable Relationships" | Queries block on slowest source — no progressive partial results when some connectors are slow or unavailable
- P1 | NAV-2 | "Three Concrete Capabilities" | No contradiction resolution strategy — conflicting information from different sources silently resolved by query order
- P1 | NAV-3 | "Open Questions" | No traversal path reliability metadata — agents cannot distinguish high-confidence paths from low-confidence paths without implicit knowledge
- P2 | NAV-4 | "Open Questions" | No multi-signal synthesis strategy — complex queries requiring information from multiple sources left to each agent to improvise
- P2 | NAV-5 | "Unified Entity Graph" | Query reference frame unspecified — entity-centric, relationship-centric, and context-centric traversals all implied but none designed as primary
Verdict: needs-changes

## Summary

The pelu (master navigator) evaluates every unified query system as a navigation problem: can you maintain a coherent position estimate when some signals are unavailable, contradictory, or stale? The concept brief proposes agent-queryable relationships across 6+ heterogeneous source systems, each with different availability, latency, and freshness characteristics. But the brief does not address the three failure modes that define real navigation: signal dropout (a source system is down), signal contradiction (two sources disagree), and signal synthesis (combining partial signals into a coherent answer). A navigator who trusts only the star compass is lost on cloudy nights. An ontology that fails when one connector is slow is a fair-weather tool, not a navigation system.

## Issues Found

### P1 — NAV-1: Queries Block on Slowest Source (No Graceful Degradation)

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 53-54 ("Agent-Queryable Relationships")

**Finding:** Capability 3 describes agents traversing relationships "without knowing which subsystem stores the data." This implies the ontology resolves the query by fanning out to relevant connectors and assembling results. But the brief does not specify what happens when one connector is slow (30-second latency on the session connector while code graph responds in milliseconds) or completely unavailable (beads Dolt server crashed).

**Concrete failure scenario:** An agent queries "show me everything related to function parseConfig." The ontology fans out to 5 connectors: code graph (responds in 50ms), beads (responds in 200ms), review findings (responds in 100ms), sessions via cass (responds in 500ms), and interlens knowledge graph (Dolt server crashed, no response). The query blocks indefinitely waiting for interlens, even though 4 out of 5 sources have already returned their results. The agent experiences a 5-minute timeout instead of a sub-second response, because the query is all-or-nothing rather than progressive.

The navigator does not stop voyaging when clouds obscure the stars. They shift to swell reading and bird observation, accepting reduced precision in exchange for continued progress.

**The pelu's test:** Does the query return partial results immediately when fast sources respond, with explicit markers showing which sources contributed and which are pending/unavailable? Or does it wait for the slowest source, treating a 5-connector fan-out like a synchronous chain?

**Smallest viable fix:** Add a progressive query model to Capability 3:

```
Query execution model: parallel fan-out with progressive results.
  t+50ms: code graph results available → return to agent with markers
  t+200ms: beads results available → update agent with additional results
  t+500ms: sessions results available → update agent
  t+5000ms: interlens timeout → mark as "unavailable, retry later"

Agent receives: results + source_status per connector:
  { code_graph: available, beads: available, sessions: available,
    reviews: available, interlens: unavailable(timeout) }

The agent can proceed with 4/5 sources rather than blocking on the 5th.
```

### P1 — NAV-2: Contradictory Information Silently Resolved by Query Order

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 46-54 ("Three Concrete Capabilities")

**Finding:** The brief does not address what happens when two source systems provide contradictory information about the same entity. In real systems, contradictions are common:

- Beads says bead-xyz is "closed" (work completed), but sessions shows 3 active sessions still modifying files associated with bead-xyz
- Code graph shows function `parseConfig` exists in `config.ts`, but git HEAD shows `config.ts` was deleted in the latest commit
- Interlens says pattern X is "validated" (from a discovery), but review findings say pattern X is "rejected" (from a later review)

If the ontology returns both facts without flagging the contradiction, the consuming agent's query order silently determines which "truth" it receives. An agent that checks beads before sessions concludes the bead is closed. An agent that checks sessions before beads sees active work and concludes it is open. Same entity, same moment, different conclusions — determined by implementation order, not by resolution strategy.

The navigator who reads the star compass and ignores the contradictory swell pattern will miss the current that has pushed them off course.

**Smallest viable fix:** Add a contradiction detection and surfacing requirement:

```
When two source systems provide contradictory state for the same entity:
  1. Return both states with source attribution (never silently pick one)
  2. Flag the contradiction explicitly: { contradiction: true, sources: [beads, sessions] }
  3. Include a resolution hint based on source reliability hierarchy:
     - For state: beads > sessions > code graph (beads is system of record for work state)
     - For content: git HEAD > code graph > sessions (git is system of record for code)
     - For evidence: review findings > discoveries > sessions (review is most deliberate)

The hierarchy is configurable, not hardcoded — different deployments may have different trust rankings.
```

### P1 — NAV-3: No Traversal Path Reliability Metadata

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 65-71 ("Open Questions")

**Finding:** The open questions ask "How would agents use the ontology at runtime? What queries would they actually make?" but do not ask the navigation question: "Which traversal paths produce reliable results, and which produce unreliable results?" Not all paths through the graph are equally trustworthy.

**Concrete failure scenario:** A new agent developer writes a query that traverses: sessions → tool_calls → file_edits → functions. This path technically works — sessions contain tool calls, tool calls modify files, files contain functions. But the tool_call → file_edit mapping has low fidelity (tool calls record that a Write tool was used, but the file path in the tool call may differ from the actual file written due to symlinks or path normalization). The developer doesn't know this. A more reliable path exists: git_commits → file_changes → functions (git is authoritative about what changed). But this knowledge is implicit — the schema and API don't surface path reliability.

The navigator knows that star compass readings are high-confidence on clear nights and useless in storms, that swell patterns are medium-confidence in open ocean and unreliable near islands where swells refract. This meta-knowledge is as important as the signals themselves.

**Smallest viable fix:** Add path reliability annotations to the schema:

```
Relationship types carry reliability metadata:
  commit.changed → file: reliability=high (git is authoritative)
  session.touched → file: reliability=medium (inferred from tool calls)
  discovery.references → file: reliability=low (text mention, may be stale)

Traversal paths inherit the minimum reliability of their edges.
Common query patterns have documented reliability levels:
  "what changed this file?" via git: high
  "what changed this file?" via sessions: medium (may include false positives)
  "what evidence exists?" via reviews: high
  "what evidence exists?" via discoveries: medium (not all discoveries are validated)
```

### P2 — NAV-4: No Multi-Signal Synthesis Strategy

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 65-66 ("Open Questions: What capabilities does an ontology graph unlock?")

**Finding:** Some agent queries require synthesizing information from multiple sources into a single coherent answer. "What is the health status of module X?" requires: code quality metrics (from reviews), test results (from CI), bead progress (from beads), session activity (from cass), and developer availability (from session recency). The brief describes the graph as a traversal mechanism but not as a synthesis mechanism.

The navigator's position estimate is not any single signal — it is the weighted synthesis of all available signals. The weights depend on current conditions (clear sky → trust stars; confused seas → reduce swell weight). The concept brief's queries are all single-signal: "which agents touched this file?" (sessions only), "what evidence exists?" (reviews + discoveries). The harder queries — "is this module healthy?", "is this sprint at risk?", "should I trust this agent's output?" — require multi-signal synthesis with reliability weighting.

**Smallest viable fix:** Add a "Composite Query" capability alongside the three proposed capabilities:

```
Capability 4: Composite Queries (multi-signal synthesis)
  Predefined synthesis templates for common agent questions:
    module_health(X) = weighted(code_quality, test_results, bead_progress, session_activity)
    sprint_risk(S) = weighted(bead_completion_rate, blocked_count, session_velocity)
    agent_trust(A) = weighted(review_scores, override_rate, defect_escape_rate)

  Weights are configurable and calibrated from historical data (closed-loop per PHILOSOPHY.md).
  New composite queries can be defined by composing existing ones.
```

### P2 — NAV-5: Query Reference Frame Unspecified

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 65-68 ("Open Questions")

**Finding:** The brief's example queries span three different reference frames without acknowledging the distinction:
- Entity-centric: "show me everything related to X" (the entity is the reference point)
- Relationship-centric: "what instances of pattern Y exist?" (the pattern is the reference point)
- Context-centric: "what matters for task Z?" (the task is the reference point)

In Micronesian navigation, the navigator uses the etak reference frame: the canoe is conceptualized as stationary while reference islands move past it. This simplifies multi-signal integration because all signals are interpreted relative to the canoe, not relative to external landmarks.

The ontology needs to choose a primary reference frame that matches the most common agent query pattern. If agents mostly ask entity-centric questions ("tell me about X"), optimize for entity-centric traversal. If agents mostly ask context-centric questions ("what do I need for this task?"), optimize for task-context traversal.

**Smallest viable fix:** Add query pattern analysis to the open questions:

```
Before choosing a reference frame, audit existing agent queries:
  1. Grep cass session history for tool calls that perform cross-system lookups
  2. Categorize: entity-centric vs relationship-centric vs context-centric
  3. Optimize the graph's primary traversal for the dominant pattern
  4. Support other patterns as secondary queries (possible but not optimized)

Hypothesis: agents mostly ask entity-centric questions (80% "tell me about X"),
so the graph should be optimized for entity-centric fan-out.
```

## Improvements

1. **Source reliability hierarchy as a configurable, calibratable parameter.** Define default trust rankings for each source system, then calibrate from observed contradiction resolution outcomes. When a human resolves a contradiction, record which source was correct — this is exactly the "disagreement at time T, human resolution at T+1, routing signal at T+2" pattern from PHILOSOPHY.md. Over time, the reliability hierarchy self-calibrates.

2. **Query health dashboard for agents.** Provide agents with a meta-query: "which sources are currently available, and what is their freshness?" This allows agents to adjust their query strategy before asking substantive questions — the equivalent of the navigator checking sky conditions before deciding which signals to rely on for the next leg.

3. **Documented "star paths" — recommended traversal routes for common queries.** In Polynesian navigation, star paths are pre-computed routes between known islands, using reliable star sequences for each heading. The ontology equivalent: documented, tested traversal paths for the top 10 most common agent queries, with known reliability levels and fallback paths when primary sources are unavailable. These serve as both documentation and as query optimization hints.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 5 (P0: 0, P1: 3, P2: 2)
SUMMARY: The ontology design lacks graceful degradation, contradiction resolution, and path reliability metadata — agents cannot distinguish high-confidence traversals from low-confidence ones and have no strategy for when sources disagree or drop out.
---
<!-- flux-drive:complete -->
