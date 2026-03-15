---
artifact_type: prd
bead: Demarch-7xm8
stage: design
---
# PRD: Meta-Improvement Campaigns — Mutation History Store + Pilot

## Problem

interlab campaigns start from scratch every time — no memory of what approaches were tried, which succeeded, or which led to dead ends. This means agents waste cycles re-exploring failed approaches and can't build on prior improvements. Hyperspace showed that provenance-tracked mutation search dramatically outperforms random search.

## Solution

Build a SQLite-backed mutation history store owned by interlab, exposed via 3 new MCP tools. Wire it into the `/autoresearch` loop so campaigns automatically record and query prior approaches. Validate end-to-end with a pilot campaign where interflux review agents improve their own definitions.

## Features

### F1: SQLite Mutation Store — Schema and DB Management

**What:** Create the mutation store database with schema, migrations, and lifecycle management.

**Acceptance criteria:**
- [ ] SQLite database created at `~/.local/share/interlab/mutations.db` on first use (auto-init)
- [ ] Schema includes: `id`, `session_id`, `campaign_id`, `task_type`, `hypothesis`, `quality_signal` (float), `is_new_best` (bool), `inspired_by` (nullable session_id), `metadata` (JSON), `created_at`
- [ ] Index on `(task_type, quality_signal DESC)` for efficient best-approach queries
- [ ] Index on `(campaign_id)` for campaign-scoped queries
- [ ] Index on `(inspired_by)` for genealogy traversal
- [ ] Schema version tracking for future migrations
- [ ] `is_new_best` computed automatically: true if `quality_signal` exceeds current best for same `task_type`

### F2: `mutation_record` MCP Tool

**What:** Record a mutation (approach attempt) with provenance metadata.

**Acceptance criteria:**
- [ ] MCP tool registered on interlab's FastMCP server
- [ ] Required params: `task_type`, `hypothesis`, `quality_signal`
- [ ] Optional params: `session_id` (defaults to current), `campaign_id`, `inspired_by`, `metadata` (arbitrary JSON)
- [ ] Auto-computes `is_new_best` by comparing `quality_signal` to max for same `task_type`
- [ ] Returns: mutation ID, `is_new_best` flag, current best quality for task type
- [ ] Validates `quality_signal` is numeric; rejects NaN/Inf

### F3: `mutation_query` MCP Tool

**What:** Query mutation history with filters for seeding campaign hypotheses.

**Acceptance criteria:**
- [ ] MCP tool registered on interlab's FastMCP server
- [ ] Filter params: `task_type`, `campaign_id`, `is_new_best` (bool), `min_quality` (float), `limit` (default 20)
- [ ] Sort: by `quality_signal DESC` (best approaches first)
- [ ] Returns: list of mutations with all fields, sorted
- [ ] Supports `inspired_by_session` filter to find all mutations inspired by a specific session
- [ ] Empty result returns empty list (not error)

### F4: `mutation_genealogy` MCP Tool

**What:** Trace `inspiredBy` provenance chains to visualize idea evolution.

**Acceptance criteria:**
- [ ] MCP tool registered on interlab's FastMCP server
- [ ] Input: `mutation_id` or `session_id`
- [ ] Returns: tree structure showing ancestry (what inspired this) and descendants (what this inspired)
- [ ] Includes quality signal at each node for visualizing improvement trajectory
- [ ] Max depth param (default 10) to prevent unbounded traversal
- [ ] Returns flat list with parent references (caller builds tree)

### F5: `/autoresearch` Integration

**What:** Wire mutation store into the existing `/autoresearch` experiment loop.

**Acceptance criteria:**
- [ ] After each experiment completes, `/autoresearch` calls `mutation_record` with hypothesis, quality signal, and campaign context
- [ ] At campaign startup, `/autoresearch` calls `mutation_query` with the campaign's `task_type` to retrieve prior best approaches
- [ ] Prior approaches are injected into the hypothesis generation prompt as "known good approaches" and "known dead ends"
- [ ] `inspired_by` is set when the agent explicitly references a prior approach in its hypothesis
- [ ] Graceful degradation: if mutation store is unavailable, campaign continues without provenance (existing behavior)

### F6: Agent Quality Scoring Rubric

**What:** Define the composite metric that the interflux self-review campaign will optimize.

**Acceptance criteria:**
- [ ] Scoring rubric documented in `interverse/interlab/campaigns/interflux-self-review/metric.md`
- [ ] Covers: structural quality (frontmatter, sections, length), trigger accuracy (when-to-use examples match actual usage), tool list appropriateness (tools listed are relevant), prompt quality (clear instructions, no ambiguity)
- [ ] Implemented as a benchmark script (`agent-quality-benchmark.sh`) that scores a single agent `.md` file and emits `METRIC agent_quality_score=N.NNNN`
- [ ] Score range: 0.0 to 1.0 (composite of weighted sub-scores)
- [ ] Benchmark can be run against any agent `.md` file (not just interflux agents)

### F7: Pilot Campaign — interflux Self-Review

**What:** Define and configure the campaign where interflux agents review and improve their own definitions.

**Acceptance criteria:**
- [ ] Campaign directory at `interverse/interlab/campaigns/interflux-self-review/`
- [ ] Campaign config specifies: target files (interflux agent `.md` files), metric (`agent_quality_score`), task type (`agent-quality`)
- [ ] Campaign can be launched via `/autoresearch` with the interflux-self-review campaign
- [ ] Each experiment: agent proposes an improvement to one agent definition, benchmark measures quality delta
- [ ] Mutations are recorded with provenance via F2/F5
- [ ] Campaign README documents the purpose, metric, and how to interpret results

## Non-goals

- **Other meta-improvement campaigns** (interskill, intercheck, interlab-self) — separate beads
- **Skaffen Orient integration** — mutation_query API should be Skaffen-friendly, but wiring is out of scope
- **Multi-dimensional Pareto dominance** for `is_new_best` — start with scalar comparison
- **Cross-project mutation sharing** via interlock broadcast — separate bead (Demarch-gpiv)
- **Campaign template/generator** — document patterns from the pilot, but no formal template system

## Dependencies

- **interlab** — MCP server, `/autoresearch` skill, campaign infrastructure (all exist)
- **plugin-benchmark.sh** — exists (351 lines), provides the PQS pattern for F6
- **interflux agent definitions** — exist at `interverse/interflux/agents/review/` (12 review agents, 5 research agents)
- **SQLite** — via `modernc.org/sqlite` (CGo-free Go driver)
- **CASS** — for resolving `session_id` references in genealogy (existing tool)

## Open Questions

1. **Agent quality sub-score weights:** How to weight structural vs. trigger accuracy vs. prompt quality in the composite score? Start with equal weights, tune based on pilot results.
2. **Benchmark determinism:** The agent quality benchmark needs to be deterministic (no LLM calls in scoring) to be a reliable optimization target. Pure structural/heuristic scoring only.
3. **Campaign isolation:** interflux agents are in an independent git repo. How does the campaign modify agent files without breaking the repo? Use interlab's existing branch isolation (`interlab/<campaign-name>` branch).
