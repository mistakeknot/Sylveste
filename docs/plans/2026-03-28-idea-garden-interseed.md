---
artifact_type: plan
bead: sylveste-e8n
stage: planned
features:
  - sylveste-ec1  # F1: interseed plugin scaffold
  - sylveste-ya2  # F2: Auraken capture
  - sylveste-em9  # F3: refinement engine
  - sylveste-pfi  # F5: signals + graduation
  # sylveste-m2p (F4: Garden Salon bridge) DEFERRED — see Original Intent
---

# Plan: Idea Garden — interseed Plugin

## Overview

Build the `interseed` Interverse plugin that owns the idea lifecycle: capture (Auraken Telegram), storage (SQLite), refinement (Claude CLI), and graduation (beads). Garden Salon bridge deferred to v2 per plan review.

## Architecture

```
Phone -> Telegram -> Auraken -> `interseed plant` (CLI) -> SQLite DB (raw text)
                                                              |
                                              `interseed enrich` (async) -> Claude CLI -> structured idea
                                                              |
Cron/Schedule -> `interseed refine` -> Claude CLI -> updated idea + log
                                                              |
`interseed match` -> interject MCP tools -> evidence enrichment
                                                              |
`interseed graduate` -> bead + brainstorm doc
```

## Batch 1: Plugin Scaffold + Data Model (sylveste-ec1)

**Goal:** Working plugin with SQLite storage and CLI.

### Task 1.1: Plugin directory structure

Create `interverse/interseed/` following interject's pattern:

```
interverse/interseed/
  .claude-plugin/
    plugin.json
  bin/
    launch-mcp.sh
  src/interseed/
    __init__.py
    __main__.py          # CLI entrypoint
    server.py            # MCP server (FastMCP)
    db.py                # SQLite schema + queries
    config.py            # YAML config loader
    models.py            # Pydantic models for Idea, RefinementLog
  config/
    default.yaml
  pyproject.toml
  CLAUDE.md
  AGENTS.md
```

**plugin.json:**
```json
{
  "name": "interseed",
  "version": "0.1.0",
  "description": "Idea garden: capture, refine, and graduate ideas from rough seeds to actionable plans.",
  "mcpServers": {
    "interseed": {
      "type": "stdio",
      "command": "${CLAUDE_PLUGIN_ROOT}/bin/launch-mcp.sh"
    }
  }
}
```

**pyproject.toml entry points:**
- `interseed-mcp` = `interseed.server:main` (MCP server)
- `interseed` = `interseed.__main__:cli` (CLI via argparse)

### Task 1.2: SQLite schema (db.py)

Follow interject's db.py pattern: PRAGMA WAL + foreign_keys, schema versioning.

**Schema init safety:** Wrap `_init_schema` in `BEGIN EXCLUSIVE` transaction. Use `INSERT OR IGNORE` for `schema_info` seeding to prevent race when two processes start on a fresh DB simultaneously.

```sql
CREATE TABLE IF NOT EXISTS ideas (
    id TEXT PRIMARY KEY,
    thesis TEXT NOT NULL,        -- raw text initially, structured after enrich
    evidence TEXT DEFAULT '[]',
    confidence REAL DEFAULT 0.1,
    maturity TEXT DEFAULT 'seed'
        CHECK (maturity IN ('seed','sprouting','growing','mature')),
    keywords TEXT DEFAULT '[]',
    open_questions TEXT DEFAULT '[]',
    garden_id TEXT,
    source TEXT DEFAULT 'manual',
    graduated_bead_id TEXT,      -- NULL -> 'PENDING' -> bead_id (graduation sentinel)
    enriched BOOLEAN DEFAULT 0,  -- false until async enrich completes
    locked_at TEXT,              -- advisory lock for concurrent refinement guard
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS refinement_log (
    id TEXT PRIMARY KEY,
    idea_id TEXT NOT NULL REFERENCES ideas(id),
    trigger TEXT NOT NULL
        CHECK (trigger IN ('scheduled','event','manual')),
    summary TEXT NOT NULL,
    confidence_before REAL,
    confidence_after REAL,
    new_evidence TEXT DEFAULT '[]',
    context_hash TEXT,           -- SHA256 of gathered context for idempotency
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS annotations (
    id TEXT PRIMARY KEY,
    idea_id TEXT NOT NULL REFERENCES ideas(id),
    source TEXT NOT NULL,        -- 'auraken', 'manual', 'garden-salon'
    annotation_type TEXT NOT NULL CHECK (annotation_type IN ('comment','steer','graduation_approval')),
    body TEXT NOT NULL,
    created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_ideas_maturity ON ideas(maturity);
CREATE INDEX IF NOT EXISTS idx_ideas_enriched ON ideas(enriched) WHERE enriched = 0;
CREATE INDEX IF NOT EXISTS idx_refinement_idea ON refinement_log(idea_id);
```

**Key schema changes from review:**
- `enriched` column: tracks whether async enrichment (thesis extraction) has run
- `locked_at` column: advisory lock for concurrent refinement guard (Finding 6)
- `context_hash` in refinement_log: SHA256 of gathered context for sound idempotency (Finding 4)
- `annotation_type` uses `graduation_approval` instead of overloading `approve` (Finding 16)
- `graduated_bead_id` sentinel protocol: NULL -> 'PENDING' -> actual bead_id (Finding 1)

### Task 1.3: Pydantic models (models.py)

Idea model with: id, thesis, evidence (list[str]), confidence (float), maturity (Literal), keywords (list[str]), open_questions (list[str]), garden_id (optional), source, graduated_bead_id (optional), enriched (bool), locked_at (optional), timestamps.

RefinementLog model with: id, idea_id, trigger (Literal), summary, confidence_before/after, new_evidence, context_hash, timestamp.

### Task 1.4: CLI -- `interseed plant` (fast) + `interseed enrich` (async)

**`interseed plant` -- instant capture, no LLM call:**

```bash
interseed plant "What if agents could leave pheromone-like traces"
# -> Captured idea abc123 (seed, pending enrichment)
```

Implementation: stores raw text as thesis, sets `enriched=0`, returns immediately. No Claude CLI call on the capture path. This ensures Auraken can reply to Telegram in <1s (Finding 2).

**`interseed enrich` -- async structuring:**

```bash
interseed enrich           # enrich all unenriched ideas
interseed enrich abc123    # enrich a specific idea
```

Calls Claude CLI via stdin (not positional args — Finding 6/correctness) to extract thesis + keywords + open_questions. Updates the idea row with structured fields and sets `enriched=1`.

Structuring prompt (passed via stdin to `claude -p`):
```
Given this rough idea, extract:
1. A clear one-sentence thesis
2. 3-5 keywords for matching
3. 1-3 open questions worth investigating

Respond as JSON: {"thesis": "...", "keywords": [...], "open_questions": [...]}
```

**Transaction discipline:** Read idea (no transaction), call Claude (no DB lock held), then write result in a single short transaction (Finding 5).

### Task 1.5: MCP server -- `interseed_status` + `interseed_list_ideas`

Follow interject's FastMCP pattern. Two tools:
- `interseed_status`: count by maturity stage, last refinement time, unenriched count
- `interseed_list_ideas`: ideas filtered by maturity, sorted by confidence desc. Human-readable maturity display: show evidence count + resolved questions instead of raw confidence float (Finding 9)

### Task 1.6: `interseed list` and `interseed delete`

`interseed list` -- show all ideas with human-readable status.
`interseed delete <idea_id>` -- remove idea and its refinement logs/annotations. Refuse if `graduated_bead_id` is set (Finding 10).

### Task 1.7: Verify

- `uv run interseed plant "test idea"` creates a row with `enriched=0`
- `uv run interseed enrich` structures it (thesis refined, keywords populated, `enriched=1`)
- `uv run interseed list` shows human-readable output
- `uv run interseed delete <id>` removes it
- `uv run interseed-mcp` starts without error
- `python -c "import json; json.load(open('.claude-plugin/plugin.json'))"` validates

**AC check:** All F1 acceptance criteria met.

---

## Batch 2: Auraken Capture (sylveste-ya2)

**Goal:** `/idea` command in Auraken writes to interseed's DB instantly.

**Depends on:** Batch 1 (interseed `plant` command must exist)

### Task 2.1: Add `/idea` command handler to Auraken

In `/home/mk/projects/auraken/src/auraken/telegram.py`:

Add an async handler `_idea_command` that:
1. Collects text as `" ".join(context.args)` -- single joined string, NOT spread across args list (Finding 6/integration)
2. Validates non-empty, replies "Usage: /idea <your rough thought>" if empty
3. Calls `interseed plant <joined_text> --source auraken --json` via `asyncio.create_subprocess_exec` with list args (no shell)
4. **Error handling:** catch `FileNotFoundError` (interseed not on PATH) and non-zero exit. Reply "Idea garden not available right now" instead of silent failure (Finding 13)
5. Parses JSON output, replies with raw text echo + "Planted in idea garden. Enriching in background..."
6. Fires `interseed enrich <id>` as a background task (no await on Telegram reply path)

Register: `app.add_handler(CommandHandler("idea", _idea_command))`

**Also add** `BotCommand("idea", "Plant a seed in your idea garden")` to `_post_init` at line ~511 so `/idea` appears in Telegram's autocomplete (Finding 19).

**Auraken coupling boundary:** The handler is a thin shim -- all logic lives in interseed's CLI. Auraken knows only the stable contract: `interseed plant <text> --source auraken --json` returns `{"id": "...", "thesis": "..."}` (Finding 1/architecture).

### Task 2.2: interseed CLI `--source` and `--json` flags

Add to `plant` subcommand:
- `--source auraken|manual|cli` (default: `cli`)
- `--json` flag outputs `{"id": "...", "thesis": "...", "keywords": [...]}` for machine parsing

**Contract:** Document the JSON output schema in interseed's AGENTS.md. This is a stable interface consumed by Auraken (Finding 14/integration).

### Task 2.3: Verify

- Send `/idea what if agents could leave pheromone-like traces` to Auraken on Telegram
- Confirm: reply appears in <2 seconds (no LLM blocking)
- Confirm: `interseed list` shows the idea with source=auraken
- Confirm: after ~10s, `interseed list` shows enriched=true (background enrich completed)
- Confirm: `/idea` appears in Telegram's autocomplete menu

**AC check:** All F2 acceptance criteria met.

---

## Batch 3: Refinement Engine (sylveste-em9)

**Goal:** `interseed refine` processes active ideas with Claude.

### Task 3.1: Refinement loop (refine.py)

Core function `refine_all(db, trigger="scheduled", limit=10)`:
1. List all ideas with maturity < mature AND enriched=1, ordered by last_refined ASC
2. **Budget cap:** process at most `limit` ideas per run (default 10, configurable). Prevents runaway costs at 50+ ideas (Finding 15)
3. For each idea:
   a. **Concurrency guard:** Check `locked_at`. If set and < 10 minutes ago, skip (another process is working on it). If stale (> 10 min), treat as abandoned. Set `locked_at = now()` in a short transaction (Finding 6)
   b. Gather context (Task 3.2)
   c. **Idempotency check:** Compute SHA256 of gathered context. Compare to `context_hash` in last `refinement_log` entry. If identical, skip -- no new signals (Finding 4). This replaces the unsound mtime comparison.
   d. **Transaction discipline:** Commit/close any open transaction BEFORE calling Claude CLI. No write lock held during external calls (Finding 5)
   e. Call Claude CLI for refinement via stdin (Task 3.3)
   f. Write results in a single short transaction: UPDATE idea, INSERT refinement_log (with context_hash), clear `locked_at`
4. Return list of refinement logs

### Task 3.2: Context gathering (context.py)

`gather_context(idea)` pulls:
- Active beads in related domains (`bd search` with idea keywords -- subprocess, list args)
- Recent brainstorms matching keywords (glob `docs/brainstorms/*.md`, bounded to last 20 files by mtime, keyword check against content)
- Previous refinement history for the idea (from DB)
- Human annotations from the annotations table (from DB)

Returns a RefinementContext dataclass with a `content_hash()` method that returns SHA256 of the serialized context. All timestamps normalized to UTC epoch integers.

**Config:** `brainstorm_dir` path comes from `config/default.yaml` with default `docs/brainstorms/`. Explicit and overridable (Finding from architecture review).

### Task 3.3: Claude refinement prompt

Passed via stdin to `claude -p` (never embedded in shell args):

System: "You are refining an idea in an idea garden."

Input: current thesis, evidence, confidence, open questions, plus new context (beads, brainstorms, annotations).

Output JSON: `{"thesis": "...", "new_evidence": [...], "confidence": 0.X, "open_questions": [...], "summary": "..."}`

Key rule: if nothing meaningful changed, return confidence_delta=0.

### Task 3.4: Maturity computation

```
confidence < 0.3 -> "seed"
confidence < 0.5 -> "sprouting"
confidence < 0.7 -> "growing"
confidence >= 0.7 -> "mature" (but graduation still needs human approval)
```

Log raw LLM confidence alongside maturity transition in `refinement_log` for future calibration (Finding from architecture review).

### Task 3.5: CLI wiring

- `interseed refine` -- all non-mature ideas, trigger=scheduled, limit=10
- `interseed refine <idea_id>` -- single idea, trigger=manual
- `interseed refine --limit 20` -- override budget cap

### Task 3.6: Verify

- Plant 2-3 test ideas, run `interseed enrich` to structure them
- Run `interseed refine`, confirm confidence increases and evidence grows
- Run again immediately: confirm no changes (context_hash matches -- idempotent)
- Run two `interseed refine` concurrently: confirm second skips locked ideas

**AC check:** All F3 acceptance criteria met.

---

## Batch 4: Signal Feeds + Graduation (sylveste-pfi)

**Goal:** interject signal matching and idea-to-bead graduation.

**Depends on:** Batch 3 (refinement engine)

### Task 4.1: Signal matching (signals.py)

`match_signals(db)`:
- List non-mature, enriched ideas
- **Use interject's MCP tools or CLI** -- NOT direct DB file access (Finding 3). Call `interject search <keywords>` via subprocess, or use the `interject_search` MCP tool if available.
- If interject is not installed: log "interject not available, skipping signal matching" and return empty -- graceful degradation, not an error (Finding from UX review)
- For each idea: match discoveries by keyword against `title` and `summary` fields (interject has no `keywords` column -- Finding 3)
- Return list of (idea_id, matching_discoveries)

### Task 4.2: `interseed match` CLI

Runs `match_signals()`, adds matches as evidence to ideas, triggers manual refinement for enriched ideas.

### Task 4.3: Graduation (graduate.py)

`graduate(db, idea_id)`:
1. Load idea. **Re-entry guard:** if `graduated_bead_id` is not NULL and not 'PENDING', already graduated -- abort. If 'PENDING', prior run died mid-flight -- reconcile (search beads for thesis match) before retrying (Finding 1)
2. Check guards: confidence >= 0.7, has `graduation_approval` annotation (distinct type, not overloaded 'approve')
3. **Write sentinel:** `UPDATE ideas SET graduated_bead_id='PENDING'` in a transaction BEFORE calling `bd create` (Finding 1)
4. **Set working directory:** subprocess `bd create` must run from the Sylveste monorepo root to target the correct Dolt instance (Finding 18)
5. Create bead: `bd create --title <thesis> --type feature --priority 2` (subprocess, list args)
6. Generate brainstorm doc from accumulated state (thesis, evidence, refinement history, annotations). Output path from config with default `docs/brainstorms/` (Finding from architecture review)
7. **Commit:** Update idea in a single transaction: `maturity=mature, graduated_bead_id=<real_bead_id>`. If this fails after `bd create` succeeded, the sentinel 'PENDING' remains and the re-entry guard will handle reconciliation next time.

### Task 4.4: `interseed graduate <idea_id>` CLI

Calls `graduate()`, prints bead ID + brainstorm path.

### Task 4.5: `interseed annotate <idea_id>` CLI

```bash
interseed annotate <id> --type graduation_approval --body "Ready to build"
interseed annotate <id> --type comment --body "Consider also looking at X"
interseed annotate <id> --type steer --body "Focus on the CLI use case, not the web UI"
```

### Task 4.6: Verify

- Plant idea, enrich, refine until confidence >= 0.7
- Add graduation approval: `interseed annotate <id> --type graduation_approval --body "Ready"`
- `interseed graduate <id>` creates bead + brainstorm doc
- Confirm bead exists: `bd show <bead_id>`
- Kill process mid-graduation (after bd create, before DB commit): confirm re-run detects PENDING sentinel and reconciles

**AC check:** All F5 acceptance criteria met.

---

## Risks

| Risk | Mitigation |
|------|-----------|
| Claude CLI calls from cron may have auth issues | Use `claude -p` with explicit model flag; test in cron context |
| interject not installed or API changes | Use CLI/MCP interface, not direct DB. Graceful degradation if absent. |
| Concurrent refinement corrupts state | `locked_at` advisory lock with 10-min staleness threshold |
| Graduation crash leaves orphan bead | PENDING sentinel + re-entry reconciliation guard |
| Large garden (50+ ideas) causes runaway costs | `--limit N` budget cap (default 10 per cycle) |
| Confidence score drift across model versions | Log raw confidence per refinement; calibration bead before v2 |
| Subprocess hangs (Claude, bd) | `asyncio.wait_for(..., timeout=60)` on all subprocess calls; terminate + reap on timeout |

## Original Intent

This plan covers v1 MVP focused on zero-friction capture (Batches 1-4). Deferred to v2:

**Garden Salon bridge (sylveste-m2p):** Cross-language Node.js bridge adds complexity without affecting core value. Deferred until salon-core exposes an HTTP API or the MVP proves the idea lifecycle is valuable. The correct import is `from "@garden-salon/salon-core/agent"` (not default export). Relay persistence (in-memory only) must be solved before annotations are reliable.

**Future iterations:**
- Intermonk dialectic stress-testing of ideas
- Push-based interject webhooks (vs pull)
- Multi-user idea gardens
- Custom Meadowsyn maturity visualizations
- Auto-detect idea-shaped messages in Auraken (no /idea prefix needed)
- Session hook or terminal alias for desk-side idea discovery notifications
- Companion-graph edges + contract-ownership.md row for `interseed plant --json`
- Interspect/kernel event wiring for graduation and refinement visibility
