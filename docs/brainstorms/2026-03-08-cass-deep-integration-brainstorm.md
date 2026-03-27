---
artifact_type: brainstorm
bead: none
stage: discover
---
# Deep cass Integration into Sylveste

## What We're Building

A comprehensive integration of [cass](https://github.com/Dicklesworthstone/coding_agent_session_search) (Coding Agent Session Search) across the Sylveste ecosystem. cass is a Rust-native CLI tool (already assessed as "adopt" in `docs/research/assess-dicklesworthstone-batch-2.md`) that indexes 10K+ sessions across 15 agent providers with sub-60ms BM25 + semantic hybrid search, plus analytics (tokens, tools, models), timeline, context-by-file, and session export.

The integration has three pillars:

1. **Reduce interstat's scope** — remove session analytics (sessions.db, FTS5, session-index.py) since cass covers this better. Interstat focuses on its unique value: bead-correlated token metrics, failure classification, and cost-per-landable-change baseline.

2. **Move session search to intersearch** — the session-search skill migrates from interstat to intersearch, wrapping all cass capabilities (search, timeline, context, export, analytics).

3. **Integrate cass into downstream commands** — reflect (session export), compound (similar session discovery), tool-time (cass analytics tools), route/next-work (cass context by file), and galiana (cross-agent cost views).

## Why This Approach

**Reduce, don't replace.** Interstat has genuine unique value that cass cannot replicate:
- **Bead correlation** — real-time hooks write bead_id and phase into every agent_run event. cass has no concept of work items.
- **Failure classification** — categorizes tool selection failures (discovery/sequencing/scale). Domain-specific.
- **Cost-per-landable-change** — correlates token spend with `ic landed summary` / git commits. Sylveste-specific metric.
- **Per-phase budgets** — calibrated token estimates that feed Clavain's sprint budget system.
- **Real-time event capture** — PostToolUse hooks capture events as they happen; cass only indexes after session ends.

Everything else — session search, session stats, activity timeline, raw token counts — cass does better because it's a dedicated tool with 15 agent connectors, pre-built rollup tables, and a Rust performance profile.

## Key Decisions

### D1: Remove interstat sessions.db entirely
Sessions.db (FTS5 + session-index.py) is fully redundant with cass. cass indexes 143K messages in 32 seconds across all agents. Our indexer only covered Claude Code sessions. Remove entirely — no freeze/deprecate, just delete.

### D2: Session-search skill moves to intersearch
intersearch already handles embedding/search infrastructure. The session-search skill becomes a thin cass wrapper in intersearch, not interstat. Clean separation: intersearch = search + retrieval, interstat = metrics + correlation.

### D3: Keep interstat's JSONL parsing pipeline
Interstat's `analyze.py` backfill pipeline writes bead_id and phase at INSERT time via hooks. Trying to join cass token data with bead context after the fact would be fragile. The proven pipeline stays. cass analytics provides a complementary cross-agent view, not a replacement.

### D4: cass auto-indexing via hook
Add a SessionStart hook (or piggyback on interstat's existing one) that checks `cass health --json` and runs `cass index` if stale. Keeps the cass index fresh without manual intervention.

### D5: Galiana gets cross-agent analytics from cass
Galiana's KPI analysis currently queries only interstat's cost-query.sh. Adding cass analytics as a supplementary data source gives cross-agent token views (Codex, Gemini spending alongside Claude Code).

### D6: Four downstream command integrations
- **/reflect** — `cass export <session_path> --format markdown` archives the sprint session transcript alongside the reflection artifact. Durable receipt.
- **/compound** — `cass search "<problem description>"` finds past sessions with similar problems. Surfaces documentation gaps.
- **tool-time** — `cass analytics tools --workspace <path> --json` provides per-tool invocation data across all agents. Richer than reading individual sessions.
- **/route & /next-work** — `cass context <file>` shows recent sessions that touched the same files. Context before starting work.

## Scope: What Changes Where

### interstat (shrinks)
**Remove:**
- `scripts/session-index.py`
- `scripts/session-search.sh` (stats/activity/projects modes)
- `skills/session-search/` directory
- `sessions.db` creation/migration code in `init-db.sh`
- FTS5 triggers and `messages`/`messages_fts` tables

**Keep (unchanged):**
- All 5 hooks (session-start, post-task, post-tool-all, post-tool-failure, session-end)
- `metrics.db` + agent_runs + tool_selection_events
- `scripts/cost-query.sh`, `analyze.py`, `classify-failures.py`, `report.sh`, `status.sh`
- `skills/report`, `status`, `analyze`
- `scripts/set-bead-context.sh`

**Add:**
- cass index freshness check in session-start.sh (or separate hook)

### intersearch (gains session-search)
**Add:**
- `skills/session-search/SKILL.md` — wraps cass: search, timeline, context, export, analytics
- Dependency: cass binary at `~/.local/bin/cass`

### galiana (gains cross-agent view)
**Modify:**
- `analyze.py` — add cass analytics as supplementary data source for cross-agent token views

### clavain commands (four integrations)
**Modify:**
- `commands/reflect.md` — add session export step using `cass export`
- `commands/compound.md` — add similar session discovery using `cass search`

### tool-time (gains cass analytics)
**Modify:**
- `skills/tool-time/SKILL.md` — use `cass analytics tools` as data source

### internext (gains file context)
**Modify:**
- `skills/next-work/SKILL.md` — use `cass context <file>` for recent activity context

## Resolved Questions

1. **cass index scheduling** — **SessionStart hook, conditional.** Piggyback on interstat's existing SessionStart hook. Check `cass health --json` — only run `cass index` if stale >1 hour. Adds ~1ms check per session start, ~30s rebuild occasionally.

2. **intersearch session-search skill granularity** — **One skill, subcommand routing.** Single `session-search` skill routes based on intent: search, timeline, context, export, analytics. Mirrors cass's CLI structure. Fewer skills to discover and maintain.

3. **cass version pinning** — **Document minimum, check at runtime.** SKILL.md documents `Requires: cass >= 0.2.0`. Skill checks `cass --version` at startup and warns if below minimum. Graceful degradation if missing.

4. **galiana cass integration depth** — **Supplementary view.** Galiana queries `cass analytics tokens` alongside interstat's cost-query.sh. Two perspectives: interstat for bead-correlated costs ("this sprint cost $X"), cass for cross-agent totals ("Codex used Y tokens this week"). No merging.

5. **reflect export format** — **Both.** Export markdown for human archive AND JSON for machine analysis. `cass export <path> --format markdown` + `cass export <path> --format json`. Two files per sprint — complete record.
