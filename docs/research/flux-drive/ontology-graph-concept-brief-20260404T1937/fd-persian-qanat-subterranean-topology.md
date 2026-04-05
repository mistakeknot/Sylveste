### Findings Index
- P1 | QAN-1 | "Unified Entity Graph" | Observation depth unspecified — connectors list source systems but not what each connector actually indexes
- P1 | QAN-2 | "Agent-Queryable Relationships" | No distinction between 'no relationship exists' and 'relationship unchecked' — false negatives indistinguishable from absence
- P1 | QAN-3 | "Design Tensions" | Cascade diagnosis across system boundaries assumes correlation preserves causation — backward reasoning from downstream symptoms unsupported
- P2 | QAN-4 | "What Already Exists in Sylveste" | Six existing graph-like structures have unknown observation overlap — shaft placement audit missing
- P2 | QAN-5 | "Open Questions" | Temporal validity treated as afterthought — no freshness model distinguishes current state from cached state
Verdict: needs-changes

## Summary

The concept brief proposes a unified view over 6+ heterogeneous subsystems but does not specify what each connector actually observes versus what it infers. This is the central qanat problem: the value of your unified view depends entirely on the depth and placement of your observation shafts into each underground system. A qanat with shafts that show water level but not flow direction gives false confidence — you see water and assume the system is healthy, but you cannot diagnose blockages, reversals, or depletion. The brief lists source systems (beads, sessions, plugins, code, discoveries, reviews) without specifying the observation contract for each, creating a design that promises unified query but cannot guarantee the depth of answers.

## Issues Found

### P1 — QAN-1: Observation Depth Unspecified

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 19-28 ("The Agentic Development Context")

**Finding:** The brief lists six entity type families and says "each subsystem manages its own entities with its own ID scheme, storage, and query patterns." It then proposes a unified entity graph (lines 46-48) without specifying what each connector actually indexes. The critical missing specification is: for each source system, what is the observation depth?

**Concrete failure scenario:** An agent queries "show me everything related to function parseConfig" and receives session records showing that 3 sessions touched files containing parseConfig. But the session connector only indexed session metadata (start time, model, token count) — not the tool call sequences within those sessions. The agent sees that sessions *existed* that touched the function, but cannot answer "what did those sessions actually do?" This is a qanat with shafts that show standing water but cannot distinguish flow from pooling — the observation shaft is too shallow.

**The muqanni's test:** For each source system, the ontology must declare: (1) what entity types are indexed, (2) at what granularity (e.g., session-level vs tool-call-level), (3) what properties are captured vs inferred, and (4) what the refresh cadence is. Without this, "unified query" means "unified pointers" — you can find that a relationship exists but not interrogate its substance.

**Smallest viable fix:** Add a section titled "Connector Observation Contracts" to the concept brief, specifying for each of the 6 source system families: entity types indexed, granularity level, captured vs inferred properties, and refresh cadence. Example entry:

```
Sessions:
  Indexed: session metadata (id, start, end, model, tokens)
  Not indexed (v1): tool call sequences, file edits within session
  Granularity: session-level (not tool-call-level)
  Refresh: post-session (via cass indexing, typically <1hr stale)
```

### P1 — QAN-2: False Negatives Indistinguishable from Absence

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 53-54 ("Agent-Queryable Relationships")

**Finding:** The query model described in Capability 3 (lines 53-54) says agents can traverse relationships without knowing which subsystem stores the data. But no mechanism distinguishes between three fundamentally different states: (a) "no relationship exists between X and Y," (b) "we checked and found no relationship," and (c) "we could not check because the source system was unavailable or stale." These three states have profoundly different implications for agent reasoning.

**Concrete failure scenario:** An agent asks "what evidence exists for pattern X?" The interspect connector is down (Dolt server crashed, a known failure mode per `beads-troubleshooting.md`). The ontology returns no evidence entities. The agent concludes there is no evidence for the pattern and proceeds to implement a solution that contradicts existing evidence — evidence that exists in interspect but was invisible because the connector was down.

**The muqanni's test:** A qanat shaft that is dry tells you nothing unless you know whether the shaft reaches the tunnel. A dry shaft in rock above the tunnel means the shaft is too shallow. A dry shaft that reaches the tunnel means the tunnel is blocked upstream. The observation must carry metadata about its own completeness.

**Smallest viable fix:** Add to the "Three Concrete Capabilities" section a requirement that every query result carries source attribution metadata:

```
Query results include per-source-system metadata:
  - status: available | unavailable | stale(age)
  - completeness: full | partial(reason) | unknown
  - last_indexed: timestamp
```

### P1 — QAN-3: Correlation Without Causation in Cross-System Traversal

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 46-54 ("Three Concrete Capabilities")

**Finding:** The three capabilities describe traversal across system boundaries — from beads through sessions through tool calls through code changes. But the relationships connecting these systems are temporal correlations (a session happened to modify a file during the period a bead was in_progress), not causal links (the session modified the file *because* of the bead). The brief does not distinguish between causal edges (bead.parent_of → child_bead) and correlative edges (session.overlaps_temporally_with → bead).

**Concrete failure scenario:** An agent asks "why did bead-xyz stall?" The ontology shows that during bead-xyz's in_progress period, 5 sessions occurred, 12 files were modified, and 3 test failures happened. But the test failures were in an unrelated module — they just happened during the same time window. The agent wastes time investigating a false causal chain because the graph's temporal correlation looks like a causal relationship. This is a qanat where you observe reduced flow at kilometer 8 and excavate the tunnel at kilometer 3-8, only to discover the blockage was in a completely different branch tunnel.

**Smallest viable fix:** Add a "Relationship Type Classification" section that distinguishes:

```
Causal edges: explicitly declared, directional, verifiable
  Example: bead.blocks → bead (from beads DAG)
Correlative edges: inferred from temporal/spatial overlap, bidirectional
  Example: session.active_during → bead.in_progress_period
Referential edges: ID-based pointers, no causal semantics
  Example: commit.mentions → bead_id (from commit message)
```

### P2 — QAN-4: Existing Graph Overlap Unaudited

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 30-39 ("What Already Exists in Sylveste")

**Finding:** Six existing graph-like structures are listed but their observation overlap is not mapped. Interlens (288 nodes), beads (DAG), interchart (D3.js force graph), intercore (SQL), intertree (hierarchy), and interkasten (Notion mapping) each observe some subset of the platform — but the brief does not show which entities are visible from which graphs, or where the observation gaps are. Before building a new unified graph, the muqanni would map existing shaft locations to identify: which areas of the underground system already have adequate observation, and which areas are truly unobserved.

**Smallest viable fix:** Add an "Observation Coverage Matrix" showing which entity types are currently observable from which existing graph structure. This reveals the actual gaps that a unified ontology would fill.

### P2 — QAN-5: Temporal Validity as Afterthought

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 59-60 ("Design Tensions: Static vs. dynamic")

**Finding:** The design tension "A code ontology changes every commit. A work ontology changes every sprint. How fresh must the graph be?" treats temporal validity as an open question. But the qanat teaches that temporal validity is not a design option — it is a structural property of observation. A qanat shaft observation from last month is not "stale data" — it is a *different observation* that may describe a *different system state*. The concept brief should not ask "how fresh must the graph be?" but rather "what is the maximum stale age at which each relationship type remains usable for each query type?"

**Smallest viable fix:** Replace the "Static vs. dynamic" tension with a per-relationship-type staleness budget:

```
Code entities (functions, files): stale after 1 commit
Session entities: stale after session completion + indexing lag
Bead entities: stale after state transition
Discovery entities: never stale (immutable once recorded)
```

## Improvements

1. **Observation depth as a first-class design dimension.** The concept brief treats the ontology as a graph of entities and relationships. The qanat perspective reveals a missing dimension: observation depth. Each connector observes the underlying system at a specific depth (entity existence, entity properties, entity operations, entity causality). Making observation depth explicit in the schema would prevent the false-confidence failure mode where agents trust shallow observations as if they were deep ones.

2. **Progressive observation deepening.** Rather than indexing everything at maximum depth from day one, design connectors to support progressive depth: v1 indexes entity existence and basic metadata; v2 adds operational detail (tool calls within sessions, specific changes within commits); v3 adds causal links. This mirrors qanat construction: you dig the shafts first (cheap, fast observation), then the tunnel (expensive, but enables deep observation).

3. **Observation health dashboard.** Add a monitoring surface that shows, for each connector: last successful index, entity count, observation depth, known gaps. This is the equivalent of the muqanni's shaft inspection round — a periodic walk of all shafts to verify each one still reaches the tunnel and shows current flow.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 5 (P0: 0, P1: 3, P2: 2)
SUMMARY: The ontology concept lacks observation depth specifications — connectors list source systems but not what each actually indexes, creating a unified view that promises completeness but cannot guarantee it.
---
<!-- flux-drive:complete -->
