# interseed — Agent Instructions

## What This Is

Idea garden plugin for the Demarch/Sylveste ecosystem. Captures rough ideas from any source (Telegram via Auraken, CLI, MCP), enriches them with Claude, refines them over time, and graduates mature ideas to beads + brainstorm docs.

## Development

```bash
cd interverse/interseed
uv run interseed plant "test idea"      # fast capture
uv run interseed enrich                  # Claude structuring
uv run interseed list                    # show all ideas
uv run interseed status                  # garden summary
uv run interseed-mcp                     # start MCP server
```

## Architecture

- **Storage:** SQLite at `~/.interseed/interseed.db` (WAL mode)
- **Capture:** `interseed plant` — instant (no LLM), stores raw text
- **Enrichment:** `interseed enrich` — async Claude call to extract thesis/keywords
- **Refinement:** `interseed refine` — scheduled re-examination with context
- **Graduation:** `interseed graduate` — create bead + brainstorm doc from mature idea

## Key Design Decisions

- Capture is decoupled from enrichment (no LLM on the Telegram response path)
- Advisory locking via `locked_at` column prevents concurrent refinement of same idea
- Idempotency via content hash (SHA256 of gathered context stored in refinement_log)
- Graduation uses PENDING sentinel to handle crash between bead creation and DB commit
- interject integration via CLI/MCP tools, not direct DB access
