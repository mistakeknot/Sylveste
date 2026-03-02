---
name: intercache
description: "Cross-session semantic cache for Claude Code. Content-addressed blob storage, per-project manifests, and session tracking — reduces cold start time and eliminates redundant file reads across sessions."
---
# Gemini Skill: intercache

You have activated the intercache capability.

## Base Instructions
# Intercache

Cross-session semantic cache for Claude Code. Content-addressed blob storage, per-project manifests, and session tracking.

## MCP Server

Python MCP server at `src/intercache/server.py`. Run with `uv run intercache-mcp`.

## Key Files

- `src/intercache/server.py` — MCP server entrypoint (8 tools)
- `src/intercache/store.py` — Content-addressed blob store (SHA256 keying, 2-char prefix sharding)
- `src/intercache/manifest.py` — Per-project file manifest (SQLite, mtime+size validation)
- `src/intercache/session.py` — Session tracking (JSONL read logs, cross-session dedup)
- `hooks/post-commit.sh` — Git hook for cache invalidation

## Storage

All data stored at `~/.intercache/`:
- `blobs/` — Content-addressed blob store (SHA256 → file content)
- `index/<project-hash>/` — Per-project manifest, session logs

## MCP Tools

| Tool | Purpose |
|------|---------|
| `cache_lookup` | Return cached content if file unchanged |
| `cache_store` | Store file content with SHA256 dedup |
| `cache_invalidate` | Invalidate by path, pattern, or project |
| `cache_warm` | Pre-warm cache from recent sessions |
| `cache_stats` | Hit rates, sizes, file counts |
| `session_track` | Record file accesses for cross-session dedup |
| `session_diff` | Compare accesses between sessions |
| `cache_purge` | Wipe cached data (per-project or global) |

## Dependencies

- Core: `mcp`
- Embeddings moved to intersearch plugin (2026-02-25)

## Testing

```bash
cd interverse/intercache
uv run pytest tests/ -v
```

## Design Decisions (Do Not Re-Ask)

- Embedding tools (embedding_index, embedding_query) moved to intersearch in v0.2.0
- numpy dependency removed (was only needed for embeddings)
- embeddings.py kept on disk for reference but no longer imported by server


