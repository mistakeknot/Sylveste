### Findings Index
- P0 | ERI-1 | "Three Concrete Capabilities" | No entity resolution strategy — 'show me everything connected to this function' requires knowing that a file path, a symbol name, and a session reference all denote the same entity
- P1 | ERI-2 | "The Agentic Development Context" | Five incompatible ID schemes with no identity crosswalk — UUIDs, hex session IDs, file paths, qualified symbol names, and Notion page IDs
- P1 | ERI-3 | "What Already Exists in Sylveste" | Temporal identity gap — renamed/moved/split functions lose all historical connections
- P2 | ERI-4 | "Three Concrete Capabilities" | Granularity mismatch between work-tracking (epic/story) and code entities (file/function/line) produces noisy cross-links
- P1 | ERI-5 | "Three Concrete Capabilities" | Transitive identity closure risk — A=B and B=C does not safely imply A=C across subsystems with different entity granularity
Verdict: needs-changes

## Summary

The concept brief's headline capability — "show me everything connected to this function" — is an entity resolution problem, not a graph structure problem. The brief treats entity identity as a solved prerequisite ("Objects link to other objects with typed, directional edges") when it is in fact the hardest unsolved problem in the proposal. Sylveste has 6+ subsystems, each with its own ID scheme, entity granularity, and temporal model. Without an explicit identity resolution layer, the unified graph would be a collection of disconnected subgraphs connected by false or missing links.

## Issues Found

### 1. [P0] No entity resolution strategy for the headline use case (ERI-1)

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 28, 47-48

The brief's motivating example: "Show me everything connected to this function" should return "the beads that tracked work on it, the sessions where it was modified, the review findings about it, the test results, and the discoveries that referenced it."

This requires resolving a single real-world entity ("this function") across 5 subsystems that refer to it differently:

| Subsystem | How it refers to a function | Example |
|-----------|---------------------------|---------|
| tldr-code / AST | Qualified symbol name | `session.Compact` |
| Git / beads | File path + line range | `os/Skaffen/internal/session/session.go:47-82` |
| cass | Session ID + tool call context | `hex:ab61ea...` → "edited session.go" |
| interject / discoveries | Natural language reference | "the compaction function in Skaffen" |
| flux-drive / review | Finding ID + file reference | `fd-quality-3: session.go line 47` |

The graph cannot link these without an entity resolution layer that maps all five representations to a canonical entity. The brief never addresses this mapping.

**Failure scenario:** Without entity resolution, the graph has:
- A `File` node for `session.go` (from git)
- A `Symbol` node for `session.Compact` (from tldr-code)
- A `Bead` node for "refactor session management" (from beads, references `session.go` in description text)
- A `Session` node for `hex:ab61ea...` (from cass, which touched `session.go`)
- A `Finding` node for quality issue (from flux-drive, references line 47)

These are 5 disconnected nodes that all relate to the same real-world entity. The "show me everything" query returns nothing because there are no edges between them. The graph looks connected in the schema diagram but is disconnected in practice.

**Precedent:** Healthcare's HL7 FHIR standard spent 10+ years building the Master Patient Index (MPI) — a single layer that resolves `Patient/123` (hospital A) = `Patient/789` (hospital B) = `SSN:xxx-xx-xxxx` (insurance). Without MPI, FHIR's linked resources are islands. The ontology graph faces the same problem at a smaller scale but with higher velocity (code entities change every commit, not every hospital visit).

**Recommendation:** Before designing the graph schema, design the entity resolution layer:
1. Define canonical entity types (File, Symbol, WorkItem, Session, Agent, Plugin)
2. For each canonical type, enumerate all ID schemes that can reference it
3. Define resolution rules: exact match (file paths), structural match (symbol names via AST), fuzzy match (natural language references via embedding similarity)
4. Define confidence levels: `exact` (same file path), `structural` (AST-derived), `probable` (text-extracted), `speculative` (embedding match)

### 2. [P1] Five incompatible ID schemes with no crosswalk (ERI-2)

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 19-27

The entity categories listed each come from subsystems with different ID conventions:

| Subsystem | ID Format | Example | Stability |
|-----------|-----------|---------|-----------|
| Beads | Short UUID (prefix + hash) | `Sylveste-8em` | Permanent (immutable once created) |
| Cass | Hex session ID | `ab61ea77e59936bf4` | Permanent (write-once) |
| Intercore | Auto-increment integers | `runs.id = 42` | Permanent but non-portable |
| Files | Absolute path | `/home/mk/projects/Sylveste/os/Skaffen/session.go` | Volatile (rename breaks identity) |
| Interlens | String slug | `first-principles-thinking` | Permanent (manually curated) |
| Interkasten | Notion page ID | `12345678-abcd-...` | External (Notion controls lifecycle) |

There is no identity crosswalk that maps between these. The brief proposes "unified query" (line 14) without addressing how a query initiated with one ID scheme finds entities referenced by another.

**Failure scenario:** An agent asks "what beads are related to `session.go`?" The graph would need to:
1. Resolve `session.go` to a canonical File entity
2. Find all beads that reference this file (beads stores file references as free text in descriptions, not structured links)
3. Find all sessions that modified this file (cass indexes file paths from tool calls)
4. Find all discoveries about this file (interject stores natural language descriptions)

Step 2 is the hard part: beads doesn't have structured file references. The link between a bead and a file exists only as unstructured text in the bead description ("refactored session management in Skaffen"). Extracting this requires NLP/regex over every bead description — an entity extraction problem, not a graph traversal problem.

**Recommendation:** Start with the subset of cross-system links that are already structured:
- cass → files (structured: tool call file paths)
- intercore runs → beads (structured: `bead_id` field if present)
- flux-drive findings → files (structured: file + line in finding format)

Defer unstructured links (bead descriptions → files, discoveries → entities) until the structured links prove their value.

### 3. [P1] Temporal identity gap — refactoring severs connections (ERI-3)

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 59-60

The brief notes "A code ontology changes every commit" but doesn't address the temporal identity problem: when a function is renamed, moved to a different file, or split into two functions, is it the same entity?

In Sylveste's actual development:
- `session.go` was likely refactored multiple times (it's core Skaffen code)
- Functions get extracted from one file to another during cleanup sprints
- Files get renamed during the monorepo consolidation (epic Sylveste-og7m, per MEMORY.md)

After a rename from `session.Compact()` to `session.CompactHistory()`:
- All historical beads that reference "the Compact function" now point to a non-existent entity
- All cass sessions that touched the old file path are disconnected from the new path
- All flux-drive findings about the old function are orphaned

**Failure scenario:** A developer asks "what's the history of the compaction feature?" The graph returns only records after the most recent rename, missing months of prior work. The "unified view" is worse than git blame, which at least tracks line-level history through renames.

**Precedent:** Git's rename detection (`git log --follow`) solves this for files but not for functions. GitHub's code navigation can track symbol renames within a single commit but not across commits. No existing tool solves cross-system temporal identity for code symbols at the granularity this brief proposes.

**Recommendation:** Acknowledge temporal identity as an unsolved hard problem. For the MVP, track identity only at the file level (where `git log --follow` provides rename history) and defer function-level temporal identity. This narrows the scope but avoids shipping a system that silently loses historical connections.

### 4. [P2] Granularity mismatch produces noisy cross-links (ERI-4)

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 19-27

The entity categories operate at different granularities:
- Beads: epic/story level (1 bead = days of work, multiple files)
- Sessions: session level (1 session = hours, 10-50 files touched)
- Code: file/function/line level (1 function = 10-100 lines)
- Discoveries: concept level (1 discovery = a pattern or insight)

Linking across granularities creates noise. A bead titled "refactor auth module" touches 15 files, 40 functions, and 200 lines. If the graph links the bead to all 40 functions, a query "what work items relate to `validateToken()`" returns the bead — but so does the same query for the other 39 functions. The graph is technically correct but informationally useless because every function in the module returns the same bead.

**Recommendation:** Define explicit granularity-bridging rules:
- Bead → File links: create when bead description mentions specific files or bead artifacts include file diffs
- File → Function links: create from AST analysis (tldr-code already does this)
- Bead → Function links: do NOT create directly (too noisy). Instead, traverse Bead → File → Function, which preserves the granularity boundary.

### 5. [P1] Transitive identity closure creates false equivalences (ERI-5)

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 47-54

The unified entity graph implies transitive relationship traversal: if Bead-A relates to File-X, and File-X relates to Session-Y, then Bead-A indirectly relates to Session-Y. This is the entire point of the graph.

But transitive closure across different relationship types can create false equivalences:

**Example:** 
1. Bead "refactor auth" → touches `auth.go` (file relationship)
2. Session-123 → modified `auth.go` (file relationship)
3. Session-123 → also modified `config.go` (file relationship)
4. Bead "update config defaults" → touches `config.go` (file relationship)

Transitive closure: "refactor auth" is 2 hops from "update config defaults" (via auth.go → session-123 → config.go). But these beads are completely unrelated — they just happened to share a session.

At 3+ hops, the entire graph is connected to everything (small-world property). The "show me everything related" query degenerates into "show me everything."

**Recommendation:** 
1. Cap traversal depth at 2 hops for cross-system queries
2. Weight edges by relationship type: same-system edges (bead→bead) are stronger than cross-system edges (bead→file→session)
3. Require at least 2 independent paths to establish a "related" connection (co-reference, not single-chain inference)

## Improvements

1. **Add an "Entity Resolution" section** as a first-class design concern, before the graph schema. The resolution layer is harder than the graph layer.

2. **Enumerate actual ID schemes** from each subsystem with concrete examples. This forces specificity about the crosswalk problem.

3. **Define confidence levels** for cross-system links: exact, structural, probable, speculative. Agents should know how reliable a connection is.

4. **Address the "small world" problem** explicitly — how does the graph avoid degenerating into "everything is related to everything" at 3+ hops?

--- VERDICT ---
STATUS: fail
FILES: 0 changed
FINDINGS: 5 (P0: 1, P1: 3, P2: 1)
SUMMARY: The headline capability ("show me everything connected to this function") is an entity resolution problem that the brief doesn't address at all. Without a cross-system identity layer mapping 5+ incompatible ID schemes, the ontology graph would be a collection of disconnected subgraphs — technically unified but practically useless.
---
<!-- flux-drive:complete -->
