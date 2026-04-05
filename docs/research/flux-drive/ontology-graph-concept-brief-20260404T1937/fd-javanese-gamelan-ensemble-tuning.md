### Findings Index
- P1 | GAM-1 | "Typed Schema + Actions" | Entity type normalization destroys source-specific semantics — a commit as git-object vs beads-state-change vs session-output carries different structural meaning in each system
- P1 | GAM-2 | "Three Concrete Capabilities" | No query-context mechanism — the same traversal returns identical results regardless of whether the agent is debugging, planning, or reviewing
- P2 | GAM-3 | "What Already Exists in Sylveste" | Six existing graphs tuned to different scales cannot be unified without choosing whose tuning to preserve — the brief assumes harmonization is additive
- P2 | GAM-4 | "Design Tensions" | New source system integration treated as schema extension rather than ensemble integration — risks re-tuning all existing connectors for each addition
- P2 | GAM-5 | "Unified Entity Graph" | Multi-typed entity representation absent — the schema forces each entity into one canonical type, losing the fact that a file participates simultaneously in code-graph, session-log, and beads-DAG with different structural significance
Verdict: needs-changes

## Summary

The concept brief proposes unifying 6+ heterogeneous schemas into a single ontology. The penyelaras (gamelan tuner) recognizes this as the fundamental tuning problem: when instruments built for different tonal systems must play together, you cannot tune each to an external standard without destroying the ensemble character. The brief assumes that a unified schema can preserve the semantics of each source system, but does not address the cases where source systems represent the same real-world entity with structurally different models — and those differences carry meaningful information. A commit is simultaneously a git object (with tree, parent, author), a beads state-change event (with bead_id, transition), and a session output record (with session_id, tool_call_id). Flattening these into a single "Commit" entity type is like tuning all gamelan instruments to equal temperament — the ombak (beating patterns) that give each system its distinctive analytical voice are lost.

## Issues Found

### P1 — GAM-1: Entity Type Normalization Destroys Source-Specific Semantics

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 8-14 ("What Palantir's Foundry Ontology Does")

**Finding:** The Palantir model (lines 8-14) features "typed objects" where "every entity has a declared type with properties and constraints." When this model is applied to Sylveste's heterogeneous systems, it implies each real-world entity gets one canonical type. But a commit has three structurally different representations across source systems, each carrying information the others lack:

- **Git**: tree hash, parent hash, author, committer, message — the commit as a point in a DAG of content snapshots
- **Beads**: bead_id, transition (in_progress → done), timestamp — the commit as evidence of work completion
- **Session log**: session_id, tool_call_id, files_changed — the commit as an output of agent action

These are not three views of the same data — they are three different analytical lenses. A debugging agent needs the git view (what changed). A planning agent needs the beads view (what work was completed). An audit agent needs the session view (who did what). Normalizing to a single "Commit" type loses the ombak — the intentional differences between representations that carry analytical meaning.

**Concrete failure scenario:** The ontology defines a normalized "Commit" entity with properties merged from all three sources. A debugging agent queries for recent commits affecting module X. The normalized Commit includes beads metadata (bead_id, priority) alongside git data (files changed, parent commit). The agent sees that commit abc123 is linked to a P0 bead and prioritizes investigating it — but the P0 bead was actually closed weeks ago, and the commit just happened to reference it in the message. The beads semantics (state-change) and git semantics (content-change) are conflated because the normalized type doesn't distinguish them.

**Smallest viable fix:** Add to the "Typed Schema + Actions" section (Capability 2) a requirement for multi-faceted entity types:

```
Entities carry source-specific type facets alongside any unified type:
  commit.git: { tree, parent, author, message }
  commit.beads: { bead_id, transition, timestamp }
  commit.session: { session_id, tool_call_id, files_changed }
Queries can access the unified view OR any source-specific facet.
```

### P1 — GAM-2: No Query-Context Mechanism (Missing Pathet)

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 53-54 ("Agent-Queryable Relationships")

**Finding:** Capability 3 describes agents querying "which agents have touched this file?", "what evidence exists for this pattern?", "what skills are available for this entity type?" These queries are presented as context-free — the same traversal produces the same result regardless of who asks or why. But in gamelan performance, the same notes produce different musical meaning depending on which pathet (modal framework) is active. The listener must know the pathet to interpret correctly.

The agentic equivalent: "show me everything related to function X" should produce different salience orderings for different operational contexts:
- **Debugging context**: prioritize recent sessions, test failures, error logs; de-prioritize beads metadata and discovery notes
- **Planning context**: prioritize beads status, blocked dependencies, sprint progress; de-prioritize individual tool calls
- **Review context**: prioritize review findings, evidence chains, calibration data; de-prioritize session metadata

Without pathet, every query returns everything at equal weight — playing slendro pitches in a pelog piece because the ensemble "has those notes."

**Smallest viable fix:** Add a query-context parameter to Capability 3:

```
Queries accept an operational context that adjusts relationship salience:
  context: debug | plan | review | audit | explore
Each context defines which relationship types are high/medium/low salience.
Agents receive results ordered by context-appropriate salience.
```

### P2 — GAM-3: Existing Graphs Are Differently Tuned Ensembles

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 30-39 ("What Already Exists in Sylveste")

**Finding:** The six existing graph-like structures are not just different data stores — they are differently tuned analytical instruments. Interlens is tuned for conceptual reasoning (PageRank, community detection). Beads is tuned for dependency tracking (blocks, caused-by). Interchart is tuned for visual exploration (force-directed layout). Each has its own "ombak" — its own characteristic analytical texture that emerges from its specific data model.

The brief assumes that unifying these into one graph is additive — you get all six perspectives in one place. But unification requires choosing a common representation, and that representation will be optimally tuned for none of them. The penyelaras knows: you cannot retune six instruments that were each built for different scales (slendro, pelog, Western, etc.) to a single common scale without losing what made each one analytically valuable.

**Smallest viable fix:** Add an acknowledgment that the unified graph is a *seventh* analytical instrument, not a replacement for the existing six. Frame it as a coordination layer that enables cross-system traversal while each existing system retains its native query capabilities:

```
The ontology graph does not replace existing query surfaces.
Interlens queries still use NetworkX. Beads queries still use the beads DAG.
The ontology provides cross-system traversal for questions that span systems.
Each source system remains the authoritative query surface for within-system questions.
```

### P2 — GAM-4: New Source Integration as Schema Extension (Ensemble Re-Tuning Risk)

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 59-60 ("Design Tensions: Composition vs. coupling")

**Finding:** When a new source system is added (e.g., a new MCP tool registry), does the ontology schema need to change? If yes, every existing connector and query must be validated against the new schema — this is the equivalent of re-tuning the entire ensemble when one instrument is replaced. The penyelaras's principle: when a damaged instrument is replaced, you tune the replacement to match the existing ensemble, not the ensemble to match the replacement.

**Smallest viable fix:** Add an "Additive Integration Principle" to the design tensions:

```
New source system connectors adapt to the ontology's existing type primitives.
They do not introduce new entity types unless no existing primitive can represent them.
Existing queries must return identical results before and after a new connector is added
(they may return additional results, but existing results must not change).
```

### P2 — GAM-5: Multi-Typed Entities Not Addressed

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 46-48 ("Unified Entity Graph")

**Finding:** A file is simultaneously: an AST node in the code graph, an artifact in the beads DAG, a touched-file in session logs, a node in intertree's hierarchy, and potentially a knowledge entity in interlens. The brief's entity model does not address how a single real-world thing participates in multiple type systems simultaneously. Does the file become one entity with multiple type facets? Or multiple entities (one per source system) linked by "same-as" edges?

The gamelan parallel: certain instruments (rebab, suling) participate in both slendro and pelog pieces during a single wayang performance. They must adapt to both tonal systems without being "retuned" between pieces. The instrument's identity persists across tonal systems — it doesn't become a different instrument.

**Smallest viable fix:** Specify an entity identity model in the concept brief:

```
Entity identity is resolved by source-system-specific identifiers.
A file at path X is one entity with facets from each system that knows about it.
Entity resolution rules: git path → canonical identity, with aliases from beads/sessions/interlens.
Facets are additive — a new source system adds a facet, it never modifies existing facets.
```

## Improvements

1. **Context-dependent salience as a first-class query feature.** Rather than returning all relationships at equal weight, design the query API with an explicit "pathet" parameter that adjusts which relationship types are foregrounded. This mirrors how the penyelaras tunes the same instrument to sound different in different modal contexts — not by retuning, but by adjusting which harmonic relationships the listener attends to.

2. **Source-native query delegation.** For within-system questions ("what beads block this bead?"), route the query to the source system's native API rather than traversing the unified graph. The unified graph handles cross-system questions ("what sessions touched the files changed by the commits in this bead?"). This preserves each system's analytical ombak while providing the cross-system coordination layer.

3. **Schema stability contract.** Define and enforce: after v1 of the ontology schema ships, new source system integrations must not change existing entity type definitions or relationship types. New types require an RFC process. This prevents the ensemble re-tuning cascade where each new source modifies existing semantics.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 5 (P0: 0, P1: 2, P2: 3)
SUMMARY: The ontology design forces entity type normalization that destroys source-specific analytical semantics, and lacks query-context mechanisms — all traversals return identical results regardless of whether the agent is debugging, planning, or reviewing.
---
<!-- flux-drive:complete -->
