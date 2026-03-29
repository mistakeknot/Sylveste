# interseed

> See `AGENTS.md` for full development guide.

## Overview

Idea garden plugin — capture rough ideas, refine them in the background, graduate to beads when mature. 0 skills, 0 commands, 0 agents, 0 hooks, 1 MCP server. Standalone Interverse plugin.

## Key Files

- `src/interseed/server.py` — MCP server (FastMCP, 3 tools)
- `src/interseed/db.py` — SQLite schema v1 (ideas, refinement_log, annotations)
- `src/interseed/__main__.py` — CLI entrypoint (plant, enrich, list, delete, annotate, status)
- `src/interseed/config.py` — YAML config loader
- `src/interseed/models.py` — Pydantic models

## CLI Contract (stable, consumed by Auraken)

```
interseed plant <text> --source cli|auraken|manual --json
# --json output: {"id": "...", "thesis": "...", "keywords": [...], "enriched": false}
```

## Dependencies

None (standalone). Optional integration with interject (signal matching) and bd (graduation).
