---
artifact_type: reflection
bead: Demarch-fqb
stage: reflect
---
# Sprint Reflection: Interrank Power-Up (Demarch-fqb)

## What Was Built

Added task-based model recommendation and cost-efficiency analysis to the interrank MCP server (v0.1.0 → v0.2.0):

- **`recommend_model` tool** — natural-language task → ranked model recommendations with weighted benchmark scoring, confidence indicators, budget filtering
- **`cost_leaderboard` tool** — performance-per-dollar efficiency ranking across models
- **Enriched benchmark metadata** — null-coalesced fields in `list_benchmarks` and `recommend_benchmarks` responses
- **`filterByProvider` helper** — extracted from 5 duplicated inline blocks

## Key Learnings

### 1. Interverse plugins have independent git repos

The monorepo's `.gitignore` excludes `interverse/` entirely. Each plugin (interrank, interflux, etc.) has its own git repo at `interverse/<name>/`. Running `git status` from the monorepo root shows nothing for plugin changes — you must `cd` into the plugin directory or use `git -C interverse/interrank/ status`.

**Impact this sprint:** Spent time debugging "where did my changes go?" when git showed clean working tree. The prior session's context compaction made this worse — the mystery was carried forward as an unresolved blocker.

**Rule:** When working in an Interverse plugin, always run git commands from the plugin's own directory.

### 2. Budget filter default: exclude unknown, not include

The initial implementation passed unknown-cost models through the budget filter (`return true` when cost is NaN/undefined). Three review agents converged on this being wrong — when a user asks for "low budget" models, including models with no price data violates the constraint.

**Pattern:** For filter predicates with missing data, the safe default depends on the filter's purpose:
- **Inclusion filter** (show me X): exclude unknowns (conservative)
- **Exclusion filter** (hide predicted): include unknowns (permissive)

### 3. Schema descriptions are the MCP contract

Zod v4 `.optional()` creates schema-level documentation that MCP clients inspect for tool discovery. When runtime validation is stricter than the schema implies (e.g., "exactly one of A or B required" but both marked optional), agents get confusing errors. The fix is description-level documentation since Zod doesn't support discriminated unions across optional fields.

### 4. Provider filter duplication was a design smell

The 5-line provider filter block appeared 5 times across tool handlers. Quality gates caught this with 2/3 agent convergence. Extracting `filterByProvider()` was trivial but the real lesson is that MCP tool handlers tend to accumulate copy-paste boilerplate — worth extracting helpers proactively after the second instance.

## Quality Gate Outcomes

- **3 agents dispatched:** fd-architecture, fd-quality, fd-user-product
- **Initial verdict:** FAIL (2 P1, 3 P2, 4 P3)
- **P1 fixes:** Budget filter logic reversal, schema/runtime contract alignment
- **P2 fixes:** McpServer version sync, filterByProvider extraction, getMetricValue guard consistency
- **P3 fixes:** Predicted discount test assertion strengthened, budget field null instead of "unlimited"
- **Final:** All 21 tests pass, TypeScript clean

## Complexity Calibration

Estimated C3, actual was C3. The recommendation engine logic (weighted scoring, predicted discount, benchmark relevance chaining) was moderate complexity. The quality gate findings added ~30min of resolve work that was valuable — the budget filter bug would have been a real issue in production.

## What Would Be Different Next Time

- Start git operations from the plugin directory immediately, not the monorepo root
- Add a `filterByProvider`-style helper from the first tool handler, not after 5 duplications
- For MCP tools with mutually exclusive params, document the constraint in both tool description and field descriptions from the start
