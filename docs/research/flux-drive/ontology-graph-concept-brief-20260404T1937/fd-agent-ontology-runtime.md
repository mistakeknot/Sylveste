### Findings Index
- P1 | AOR-1 | "Three Concrete Capabilities" | No concrete agent workflow that is impossible without the ontology — the capability delta over existing tools (cass, beads, tldr-code, grep) is undemonstrated
- P0 | AOR-2 | "Three Concrete Capabilities" | Ontology as hard runtime dependency violates fail-open philosophy — agents that previously worked with direct queries would fail when ontology layer is down
- P1 | AOR-3 | "Three Concrete Capabilities" | Bootstrap problem — agents need ontology schema knowledge in context to query the ontology, consuming tokens before delivering value
- P2 | AOR-4 | "Open Questions" | Context window economics unanalyzed — graph traversal results could consume 30-50% of agent context budget with low information density
- P1 | AOR-5 | "Three Concrete Capabilities" | 'Actions' concept underdeveloped — Palantir-style Actions require effect declarations and preconditions that don't map to agent tool use
Verdict: needs-changes

## Summary

The critical question for agent-ontology interaction is not "can we build this" but "will agents actually use it better than what they already have." The brief proposes three capabilities (unified entity graph, typed schema + actions, agent-queryable relationships) but doesn't demonstrate a single concrete agent workflow where the ontology outperforms the existing toolset of `cass search`, `bd list`, `tldr-code context`, and `grep`. Without that capability delta, the ontology adds complexity (schema learning, query formulation, result parsing) for convenience (one interface instead of four) — and convenience that costs tokens is not convenience for an LLM agent.

## Issues Found

### 1. [P1] No demonstrated capability delta over existing tools (AOR-1)

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 47-54, 65-66

The brief asks "What capabilities does an ontology graph unlock that are impossible without one?" (line 65) but doesn't answer it. Let me attempt the analysis the brief should have done.

**Claimed capability 1: "Show me everything related to X"**
- Without ontology: `cass context <path>` shows sessions that touched a file. `bd search "X"` shows beads mentioning X. `tldr-code context X` shows the call graph. `grep -r "X"` finds text references. Agent runs 4 commands, ~5 seconds, ~800 tokens of results.
- With ontology: Agent runs 1 graph query, ~2-5 seconds (traversal), ~500-2000 tokens of results depending on depth.
- **Delta:** Fewer commands (4→1) but similar latency and similar/worse token cost. The ontology saves tool calls at the cost of learning the query interface.

**Claimed capability 2: "Which agents have touched this file?"**
- Without ontology: `cass context <path> --json | jq '.sessions[].agent'` — already available, ~200 tokens.
- With ontology: `MATCH (a:Agent)-[:MODIFIED]->(f:File {path: "X"}) RETURN a` — requires learning Cypher/GQL syntax, ~100 tokens.
- **Delta:** Marginal. The ontology query is slightly more concise but requires graph query knowledge.

**Claimed capability 3: "What skills are available for this entity type?"**
- Without ontology: `grep -r "entity_type" interverse/*/skills/` or read plugin.json manifests — already discoverable, ~300 tokens.
- With ontology: `MATCH (s:Skill)-[:OPERATES_ON]->(t:EntityType {name: "X"}) RETURN s` — requires skills to declare their entity types in the ontology.
- **Delta:** The ontology version requires plugins to register entity type declarations — new integration work for 60+ plugins. The grep version works today.

**The one workflow where the ontology genuinely helps:** Cross-system causal chains. "Why did this test fail? What changed, who changed it, what bead tracked it, and was there a review finding about this area?" This requires traversing beads → commits → files → test results → review findings. Today this requires 5-7 sequential tool calls with manual correlation. An ontology graph could answer it in 1-2 hops.

But this specific workflow is also achievable with a thin "recent activity" view that joins intercore runs, beads, and git log — no full ontology needed.

**Recommendation:** Identify 3-5 concrete agent workflows where the ontology provides > 2x improvement over existing tools. If no such workflows exist, the ontology is solving a human UX problem (unified browsing) not an agent capability problem.

### 2. [P0] Ontology as hard runtime dependency violates fail-open (AOR-2)

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 47-54
**Cross-reference:** `PHILOSOPHY.md`, lines 128-137

The brief proposes agents querying the ontology at runtime (capability 3: "Agent-Queryable Relationships"). If agents adopt the ontology as their primary query interface, the ontology becomes a hard runtime dependency.

PHILOSOPHY.md is explicit (lines 128-131):
- "Standalone plugins fail-open, degrade gracefully without intercore"
- "No plugin requires another to function"

If the ontology layer goes down (graph database crash, CDC lag, projection corruption), agents that previously worked by calling `cass search` and `bd list` directly would now fail because they've been retrained to use the ontology instead.

**Failure scenario:** The Dolt graph projection corrupts during a schema migration (the exact kind of failure the "Don't pay debt too early" principle warns about). All agent sessions in progress get empty results from ontology queries. Agents that used to grep for context now sit idle because their tool calls go through the ontology layer. The blast radius is every active sprint — not just the ontology subsystem.

This is worse than not having an ontology. Before the ontology, agents had 4 independent query tools, each with independent failure modes. After the ontology, there's a single point of failure that takes out all cross-system queries simultaneously.

**Recommendation:** The ontology must be strictly additive — a "bonus" layer that provides extra context when available, with agents always maintaining direct tool access as the primary path. This means:
1. Never deprecate `cass search`, `bd list`, `tldr-code context`, or `grep` in favor of ontology queries
2. Agent prompts should include both: "Use the ontology for cross-system queries; fall back to direct tools if unavailable"
3. The ontology should fail-silent (empty results), not fail-loud (error propagation)

### 3. [P1] Bootstrap problem — schema knowledge costs tokens (AOR-3)

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 49-50

The brief proposes a "schema browser for the platform itself" (capability 2). But for an LLM agent to query the ontology, it must know:
- What entity types exist (currently 6 categories, potentially dozens of types)
- What relationship types connect them (the brief lists 3 examples; a real ontology would have 20-50)
- What properties each type has
- What the query syntax is (Cypher? GQL? SPARQL? Custom DSL?)

This schema knowledge must be either:
- **Pre-loaded in the system prompt:** 200-500 tokens of schema definition that's always present, consuming context budget even when the agent never queries the ontology.
- **Discovered at runtime:** Agent calls a "describe schema" endpoint, reads the result (~500 tokens), then formulates the query. Total cost: 500 (schema) + 100 (query) + 200 (results) = 800 tokens for a single ontology query.

Compare this to the existing tools: `cass search "query"` requires zero schema knowledge — the agent already knows how to call CLI tools. The ontology adds a learning tax per session.

**Context window economics for a typical sprint:**
- Agent context: ~100K tokens (Opus-class model)
- Sprint prompt (CLAUDE.md, AGENTS.md, plan, code): ~20K tokens
- Tool results during sprint: ~40K tokens
- Available for ontology: ~40K tokens remaining
- Per ontology query: ~800 tokens (schema + query + results)
- Max ontology queries per sprint: ~50

50 queries sounds ample, but context pressure is non-linear — every ontology token competes with code context. An ontology query that returns 2000 tokens of graph metadata displaces 2000 tokens of actual code the agent could have read.

**Recommendation:** If the ontology proceeds, provide:
1. A pre-built set of 5-10 common queries as named commands (not raw graph queries) — "related-beads", "recent-sessions", "review-findings" — that agents can call without knowing the schema
2. A single-line schema summary (~50 tokens) in the system prompt, not the full schema
3. Result truncation that returns top-K entities with one-line summaries, not full entity metadata

### 4. [P2] Context window economics unanalyzed (AOR-4)

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 65-71

The brief's open questions include "How would agents use the ontology at runtime?" but don't address the token cost of graph results.

**Token cost estimate for "show me everything related to this function":**

| Result component | Count | Tokens each | Total |
|-----------------|-------|-------------|-------|
| Entity type + name | 20 (2 hops) | 10 | 200 |
| Entity properties | 20 | 50 | 1000 |
| Relationship edges | 30 | 15 | 450 |
| Traversal metadata | 1 | 100 | 100 |
| **Total** | | | **1750** |

At 1750 tokens per query, and agents making 5-10 contextual queries per sprint, the ontology consumes 8750-17500 tokens — 9-18% of the sprint's tool result budget. For queries that return ranked, curated results, this is acceptable. For queries that return "everything," most of those tokens are noise.

**Compare to existing tools:**
- `cass context session.go --json`: ~300 tokens (3 recent sessions with one-line summaries)
- `bd search "session"`: ~200 tokens (5 matching beads with titles)
- `tldr-code context session.Compact`: ~400 tokens (call graph, 2 hops)

Total: ~900 tokens for 3 focused queries, each returning precisely what the agent needs.

The ontology's 1750-token "everything" result costs 2x more tokens and provides less focused information.

**Recommendation:** Design the ontology query interface for information density, not breadth. Return ranked, typed results with token budget controls. Model the interface on `cass search` (compact, ranked, budget-aware) not on "MATCH all paths."

### 5. [P1] 'Actions' concept underdeveloped (AOR-5)

**File:** `docs/brainstorms/2026-04-04-ontology-graph-concept-brief.md`, lines 13, 49-50

The brief mentions Palantir-style "Actions" — "Operations that can be performed on objects, with preconditions and effects declared in the schema" (line 13) — and proposes capability 2 includes "allowed actions." But the brief doesn't develop what Actions mean for agent tool use.

In Palantir Foundry, an Action is a transactional operation with:
- **Preconditions:** Object must be in state X, user must have permission Y
- **Effects:** Object transitions to state Z, related objects are notified
- **Validation:** Input parameters are type-checked against the schema

For Sylveste agents, the equivalent would be:
- **Action: claim-bead** — Precondition: bead is unclaimed. Effect: bead.status = in_progress, bead.claimed_by = session_id. Validation: bead exists, is not closed.
- **Action: record-finding** — Precondition: review is in progress. Effect: finding entity created, linked to file + review. Validation: file path exists.

But agents already do this through tool calls: `bd update <id> --claim` and writing to `{OUTPUT_DIR}/{agent-name}.md`. The ontology Actions would be a second way to do the same thing — now there are two systems that can mutate state, creating consistency risks.

**Failure scenario:** An agent claims a bead through the ontology Action (which updates the graph projection) but the beads CLI doesn't know about it (the projection is read-only). Now the graph says the bead is claimed but `bd show` says it's available. Another agent claims it through `bd`, creating a double-claim that the ontology's preconditions should have prevented.

This is the fundamental problem with read-only projections that also declare Actions: write operations must go through the source system, but precondition checking happens in the projection, creating a TOCTOU (time-of-check/time-of-use) race.

**Recommendation:** Drop "Actions" from the ontology scope entirely. The ontology should be a read-only query layer. Write operations (claiming beads, recording findings, creating entities) should continue to go through the source systems' native interfaces. This avoids the TOCTOU problem and keeps the ontology's scope tractable.

## Improvements

1. **Add a "Capability Delta" section** with side-by-side comparison: current tools vs. ontology for 5 concrete agent workflows, with token cost estimates.

2. **Add an "Agent Integration Pattern" section** describing how agents would discover, query, and interpret ontology results — including fallback behavior when the ontology is unavailable.

3. **Drop Actions from scope** — the ontology's value is in read-only cross-system queries, not in providing a second write path that races with source systems.

4. **Design named queries, not a query language** — agents should call `ontology.related_beads(file)` not `MATCH (b:Bead)-[:TRACKS]->(f:File {path: $path}) RETURN b`. Named queries are cheaper (fewer tokens), more reliable (no malformed query risk), and easier to optimize.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 5 (P0: 1, P1: 3, P2: 1)
SUMMARY: The brief doesn't demonstrate a single agent workflow where the ontology outperforms existing tools (cass, beads, tldr-code, grep). The one clear win — cross-system causal chains — is achievable with a thinner join layer. If built, the ontology must be strictly additive (never replace direct tool access) and expose named queries (not a query language) to avoid the bootstrap problem and context window tax.
---
<!-- flux-drive:complete -->
