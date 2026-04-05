# fd-petrographic-thin-section-entity-resolution -- Findings

**Target:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`
**Agent:** fd-petrographic-thin-section-entity-resolution (optical mineralogy: identifying entities across observation frames)
**Decision Lens:** Evaluates whether entity resolution uses invariant properties (persist across all subsystem views) or contingent properties (change per view). Also evaluates grain-boundary entities, materialized lookup, and minimum invariant sets.

---

## Finding 1: No distinction between diagnostic and contingent properties

**Severity: P1**
**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 41-54

The concept brief describes the Unified Entity Graph capability (lines 41-48) without distinguishing identity-bearing properties from view-dependent properties. Line 43 says "beads, sessions, agents, artifacts, discoveries all linked" -- but linked HOW? The brief assumes entity identity is obvious, when in practice the same entity presents radically different surfaces across subsystems.

**The petrographic structural isomorphism:** A petrographer examining a thin section knows that interference color (what you see under crossed polars) is contingent -- it changes with every 1-degree rotation of the microscope stage. But extinction angle (the rotation at which the grain goes dark) is diagnostic -- it is invariant for a given mineral regardless of orientation. A beginning student who tries to identify minerals by interference color will fail catastrophically because the same olivine crystal shows first-order gray at one rotation and vivid second-order blue at another. Entity resolution using contingent properties has the same failure mode.

In the concept brief, consider a File entity:
- In the development subsystem: has a path, language, AST structure, import graph, test coverage
- In the work-tracking subsystem: has an associated bead, sprint context, PR link
- In the agent subsystem: has sessions-that-touched-it, tool-calls-that-modified-it, token cost
- In the knowledge subsystem: has discoveries referencing it, learnings about it

The file path is the extinction angle -- it persists across all views. The AST structure, bead association, session list, and discovery references are all interference colors -- they change depending on which subsystem you query and when. But the concept brief does not make this distinction explicit. Without it, entity resolution will attempt to match on contingent properties (like "status" or "last modified") that differ across views.

**Failure scenario:** An agent asks "show me everything related to `core/intercore/internal/dispatch/router.go`." The ontology graph must resolve this file path across: (1) git (commits touching it), (2) beads (work items that modified it), (3) cass (sessions where it was read/edited), (4) interspect (evidence about agent performance on it), (5) interknow (solution docs referencing it). If the graph uses file path as the invariant anchor, this works. If it tries to match on properties like "recently modified" or "associated with sprint X," it fails because those properties differ across subsystems and across time.

**Smallest viable fix:** For each entity family, declare the minimum invariant property set (the "extinction angle") that uniquely identifies an entity across all subsystem views:

```yaml
identity_anchors:
  file: path                          # Absolute path, stable across all views
  bead: bead_id                       # UUID, stable across all views
  session: session_id                 # UUID, stable across all views
  agent: agent_name                   # Registry name, stable across views
  commit: sha                         # Content-addressed, immutable
  discovery: discovery_id             # UUID, stable across all views
  plugin: plugin_name                 # Registry name from plugin.json
  skill: qualified_name               # e.g. "clavain:sprint"
  tool_call: (session_id, call_index) # Compound key within session
```

All other properties are view-dependent and must be tagged with their source subsystem.

---

## Finding 2: Grain-boundary entities will create duplicate graph nodes

**Severity: P1**
**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 41-43

The brief says "One place to ask 'show me everything related to X' -- beads, sessions, agents, artifacts, discoveries all linked" (lines 42-43). But entities at subsystem boundaries -- entities that exist at the interface between two systems -- are the hardest to unify.

**The petrographic structural isomorphism:** At a grain boundary in a thin section, two mineral crystals interpenetrate. The same physical grain presents different interference colors on each side of the contact because the crystallographic orientation changes at the boundary. A student looking at the boundary sees what appears to be two different minerals; an expert recognizes them as the same grain by checking invariant properties (extinction angle, crystal system) on both sides.

In the ontology graph, a Commit is a grain-boundary entity: it lives at the interface between the development subsystem (where it has a diff, files changed, and author) and the work-tracking subsystem (where it has a bead link, sprint context, and merge status). In beads, the commit might be referenced by its short SHA. In git, by its full SHA. In cass, by the session that produced it. In intercore, by the run that triggered it. These are four different subsystem representations of the same entity with different identifier formats and different property sets.

**Failure scenario:** The ontology graph imports entities from each subsystem independently. A commit `a1b2c3d` appears as:
- Node 1: development entity `{sha: "a1b2c3d4e5f6...", files: [...], author: "claude"}`
- Node 2: work-tracking entity `{commit_ref: "a1b2c3d", bead: "sylveste-xyz", sprint: "S7"}`
- Node 3: agent entity `{session: "sess-123", tool: "Bash", action: "git commit"}`

Without explicit grain-boundary resolution, the graph has three nodes for one entity. The "show me everything related to X" query returns one-third of the actual relationships for any single node.

**Smallest viable fix:** Define explicit grain-boundary resolution rules for entity types that span subsystem interfaces:

```yaml
boundary_entities:
  commit:
    canonical_id: full_sha
    subsystem_identifiers:
      git: full_sha
      beads: short_sha | commit_message_match
      cass: session_id + tool_call_index
      intercore: run_id + artifact_sha
    resolution_strategy: normalize_to_canonical
```

The resolution rules are the Michel-Levy chart for the ontology graph -- precomputed mappings that avoid real-time cross-subsystem joins.

---

## Finding 3: No materialized entity resolution index (the Michel-Levy chart is missing)

**Severity: P2**
**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 49-54

The brief proposes "Agent-Queryable Relationships" (lines 49-54) where agents "traverse relationships at runtime" to answer queries like "which agents have touched this file?" This implies real-time cross-subsystem joins. The brief asks whether the graph should be "a read-only projection (materialized view)" (line 66) but does not describe what would be materialized.

**The petrographic structural isomorphism:** The Michel-Levy birefringence chart is a precomputed lookup table that maps (interference color + specimen thickness) to mineral birefringence, enabling rapid identification during microscope work. It exists because computing birefringence from raw interference patterns in real time would be impractical -- the microscopist would spend minutes on calculations that the chart resolves in seconds.

For the ontology graph, the equivalent materialized index would map subsystem-specific identifiers to unified entity IDs. Without this index, every "show me everything related to X" query requires:
1. Identify X's type and subsystem
2. Query that subsystem for X's properties
3. For each property that might be an identifier in another subsystem, query that subsystem
4. For each result, repeat steps 2-3 for additional subsystems
5. Deduplicate results

This is O(subsystems^2) per query. With 6+ subsystems, each query traverses 36+ cross-system lookups.

**Failure scenario:** An agent running `/clavain:route` needs to find all context related to a file before dispatching work. The agent queries the ontology graph, which must perform real-time joins across git, beads, cass, intercore, interspect, and interknow. With each subsystem taking 50-200ms to query, the total latency is 300-1200ms per file -- unacceptable for interactive routing decisions. The agent either skips the ontology query (making it useless) or blocks on it (making routing slow).

**Smallest viable fix:** Build a materialized entity resolution index that maps (subsystem, subsystem_id) -> canonical_entity_id. Update it incrementally via hooks/events from each subsystem (beads events, git hooks, cass indexing runs). Queries hit the index (O(1) lookup) rather than performing live cross-subsystem resolution.

```
entity_index:
  canonical_id: "entity-a1b2c3d"
  type: commit
  subsystem_refs:
    git: "a1b2c3d4e5f6789..."
    beads: "sylveste-xyz.commit_ref"
    cass: "sess-123.call[47]"
  last_updated: 2026-04-04T19:00:00Z
```

This is the Michel-Levy chart: precomputed resolution that makes runtime queries fast.

---

## Finding 4: Pleochroism -- entities whose apparent type changes across views

**Severity: P2**
**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 18-28

The concept brief lists 6 entity families as though type assignment is stable. But some entities change apparent type depending on which subsystem view you examine.

**The petrographic structural isomorphism:** Pleochroic minerals (hornblende, biotite, tourmaline) appear to be fundamentally different substances at different microscope stage rotations -- changing not just color but apparent crystal habit. Hornblende appears brown at 0 degrees, green at 60 degrees, and yellow at 120 degrees. A student examining a single orientation would classify it as three different minerals.

In the ontology graph:
- A Session viewed from interspect is a **Review entity** (evidence, reliability scores, calibration data)
- The same Session viewed from interstat is a **Cost entity** (token counts, model usage, duration)
- The same Session viewed from cass is a **Knowledge entity** (discoveries, learnings, file context)
- The same Session viewed from beads is a **Work-tracking entity** (sprint context, bead link)

The Session's apparent TYPE changes across views. If the ontology graph assigns a single type to each entity, which type does Session get? Any single assignment makes the entity invisible in queries targeting the other types.

**Failure scenario:** Session is typed as "Agent entity." An agent asks "show me all knowledge entities from the last sprint." Sessions that produced discoveries during that sprint do not appear because they are typed as Agent, not Knowledge. The unified graph fails to surface a relationship that the user would expect.

**Smallest viable fix:** This converges with the Dogon twin-seed finding (Finding 2 in the Dogon report). The entity resolution layer should distinguish the entity's identity (invariant: session_id) from its type participation (multi-valued: agent + cost + knowledge + work_tracking, depending on which subsystem relationships it has). Type is not a property of the entity -- it is a property of the entity's participation in a subsystem.

---

## Finding 5: The minimum invariant set per entity type (the extinction angle)

**Severity: P3**
**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 41-68

The concept brief does not identify the minimum set of invariant properties sufficient for entity resolution per type.

**The petrographic structural isomorphism:** The extinction angle is the single most diagnostic property in mineral identification. One measurement (rotate until dark) constrains the mineral identity to a small set when combined with crystal system. Petrographers learn to go for the extinction angle FIRST because it provides maximum information per observation.

For the ontology graph, the question is: what is the extinction angle for each entity family? The minimum invariant that resolves identity across all views?

| Entity Family | Extinction Angle | Notes |
|---------------|-----------------|-------|
| Development (files) | File path | Renames break resolution -- need rename-tracking |
| Development (functions) | (file_path, qualified_name) | Refactoring breaks resolution |
| Work-tracking (beads) | Bead ID | Stable, never changes |
| Agent (sessions) | Session ID | Stable, never changes |
| Agent (tool calls) | (session_id, call_index) | Stable within session |
| Knowledge (discoveries) | Discovery ID | Stable if assigned at creation |
| Review (findings) | (review_session_id, finding_index) | Or finding_id if assigned |
| Infrastructure (plugins) | Plugin name | From plugin.json, stable |

**Key insight:** Most entity families have a single stable identifier (the extinction angle). The exception is Development entities, where the identifier (file path, function name) is itself mutable. This means the ontology graph needs rename-tracking for development entities -- or accepts that entity resolution breaks on renames. This is a known hard problem in petrography too: metamorphic recrystallization changes the grain boundary geometry so completely that previously identified grains can no longer be tracked.

---

## Summary

| # | Severity | Finding | Core Petrographic Mechanism |
|---|----------|---------|---------------------------|
| 1 | P1 | No diagnostic vs. contingent property distinction | Extinction angle vs. interference color |
| 2 | P1 | Grain-boundary entities will duplicate | Grain boundary resolution |
| 3 | P2 | No materialized entity resolution index | Michel-Levy birefringence chart |
| 4 | P2 | Entities change apparent type across views | Pleochroism |
| 5 | P3 | Minimum invariant set not identified | Extinction angle per mineral |
