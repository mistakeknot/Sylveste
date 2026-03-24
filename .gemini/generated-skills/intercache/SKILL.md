---
name: intercache
description: "Cross-session semantic cache for Claude Code. Content-addressed blob storage, per-project manifests, and session tracking — reduces cold start time and eliminates redundant file reads across sessions."
---
# Gemini Skill: intercache

You have activated the intercache capability.

## Base Instructions
# intercache — Development Guide

## Canonical References
1. [`PHILOSOPHY.md`](./PHILOSOPHY.md) — direction for ideation and planning decisions.
2. `CLAUDE.md` — implementation details, architecture, testing, and release workflow.

## Philosophy Alignment Protocol
Review [`PHILOSOPHY.md`](./PHILOSOPHY.md) during:
- Intake/scoping
- Brainstorming
- Planning
- Execution kickoff
- Review/gates
- Handoff/retrospective

For brainstorming/planning outputs, add two short lines:
- **Alignment:** one sentence on how the proposal supports the module's purpose within Demarch's philosophy.
- **Conflict/Risk:** one sentence on any tension with philosophy (or 'none').

If a high-value change conflicts with philosophy, either:
- adjust the plan to align, or
- create follow-up work to update `PHILOSOPHY.md` explicitly.


> Cross-AI documentation for intercache. Works with Claude Code, Codex CLI, and other AI coding tools.

## Quick Reference

| Item | Value |
|------|-------|
| Repo | `https://github.com/mistakeknot/intercache` |
| Namespace | `intercache:` |
| Manifest | `.claude-plugin/plugin.json` |
| Components | 0 skills, 0 commands, 0 agents, 1 hook (git post-commit, manual install), 1 MCP server (Python/uv), 2 scripts |
| License | MIT |

### Release workflow
```bash
scripts/bump-version.sh <version>   # bump, commit, push, publish
```

## Overview

**intercache** is a cross-session semantic cache for Claude Code. Content-addressed blob storage (SHA256 with 2-char prefix sharding), per-project SQLite manifests with mtime+size validation, and JSONL session tracking.

**Problem:** Every Claude Code session re-reads the same files. Cold starts are slow. No cross-session memory of what was recently accessed.

**Solution:** 8 MCP tools for cache lookup/store/invalidate/warm, session tracking, and cache management.

**Plugin Type:** MCP server plugin (Python, uv-launched)
**Current Version:** 0.2.0

## Architecture

```
intercache/
├── .claude-plugin/
│   └── plugin.json               # MCP server registration
├── src/intercache/
│   ├── server.py                 # MCP server entrypoint (8 tools)
│   ├── store.py                  # Content-addressed blob store (SHA256, 2-char sharding)
│   ├── manifest.py               # SQLite per-project manifest (mtime+size validation)
│   ├── session.py                # JSONL session tracking
│   └── __init__.py
├── hooks/
│   └── post-commit.sh            # Git hook for cache invalidation (manual install)
├── scripts/
│   ├── launch-intercache.sh      # uv-based MCP launcher (graceful exit if uv missing)
│   └── bump-version.sh
├── tests/
│   ├── test_server.py            # MCP tool integration tests
│   ├── test_manifest.py
│   ├── test_store.py
│   ├── test_session.py
│   └── test_security.py
├── pyproject.toml                # Python package (hatchling, entrypoint: intercache-mcp)
├── CLAUDE.md
├── AGENTS.md                     # This file
├── PHILOSOPHY.md
├── README.md
└── LICENSE
```

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

## Storage Layout

```
~/.intercache/
├── blobs/              # Content-addressed (SHA256 → 2-char prefix → blob)
└── index/<project-hash>/
    ├── manifest.db     # SQLite: path → SHA256 + mtime + size
    └── sessions/       # JSONL session logs
```

## Component Conventions

### MCP Server
Python package at `src/intercache/`. Launched via `scripts/launch-intercache.sh` which uses `uv run` with graceful degradation if uv is missing. Entry point: `intercache-mcp`.

### Git Hook
`hooks/post-commit.sh` invalidates cache on commit. This is a **git hook** (not a Claude Code hook) — requires manual installation into `.git/hooks/post-commit`. Not registered in `hooks.json`.

## Integration Points

| Tool | Relationship |
|------|-------------|
| intersearch | Received the embedding tools extracted from intercache in v0.2.0 |
| interflux | Primary consumer of session tracking for cold start reduction |

## Testing

```bash
uv run pytest tests/ -v
```

Tests validate MCP tool behavior, content-addressed storage correctness, manifest CRUD, session tracking, and security boundaries.

## Known Constraints

- Embedding tools (`embedding_index`, `embedding_query`) moved to intersearch in v0.2.0 — `embeddings.py` kept on disk for reference only, not imported
- Post-commit hook requires manual git installation (not managed by Claude Code plugin system)
- numpy dependency removed after embedding extraction


