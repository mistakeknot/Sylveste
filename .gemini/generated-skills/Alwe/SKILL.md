---
name: Alwe
description: "Interverse driver capability: Alwe"
---
# Gemini Skill: Alwe

You have activated the Alwe capability.

## Base Instructions
# Alwe — Agent Reference

## Architecture

Alwe is a universal agent observation layer. It watches any CLI AI agent's sessions via CASS and exposes structured data as MCP tools and CLI commands. The complement to [Zaka](https://github.com/mistakeknot/Zaka), which steers.

```
Alwe  ◀──CASS──  Claude Code / Codex / Gemini / AMP / ...
  │                (session JSONL files indexed by CASS)
  ▼
MCP server (stdio)  ──or──  CLI output (JSON/markdown)
```

## Package Map

| Package | Purpose | Key Types |
|---------|---------|-----------|
| `observer` | CASS backend | `CassObserver`, `Event`, `SessionResult`, `ParseJSONLEvent` |
| `mcpserver` | MCP server | `Server`, 5 tool handlers |

## Dual-mode operation

- **MCP server** (default, no args): starts stdio MCP server for programmatic access by Skaffen or other orchestrators
- **CLI**: direct human access to the same CASS queries

## MCP Tools

| Tool | Description |
|------|-------------|
| `search_sessions` | Search agent sessions by content, filter by connector |
| `context_for_file` | Find sessions that touched a specific file |
| `export_session` | Export a session to markdown |
| `timeline` | Recent activity across all agents |
| `health` | CASS availability check |

## Observer modes

1. **Real-time tail** — `TailSession()` polls a JSONL file at 100ms intervals, parses events, sends to channel. For live observation of running agents.
2. **Query** — `SearchSessions()`, `ContextForFile()`, `ExportSession()`, `Timeline()` wrap `cass` CLI calls. For historical data.

## Build & Test

```bash
go build ./cmd/alwe
go test ./... -count=1
go vet ./...
```

## CLI

```bash
# MCP server mode (default)
alwe

# Search sessions
alwe search "auth bug"
alwe search --connector codex "fix"

# Activity timeline
alwe timeline --since 2h

# Export session
alwe export ~/.claude/projects/.../session.jsonl

# Find sessions by file
alwe context src/main.go

# Health check
alwe health
```

## Dependencies

- **cass** (`~/.local/bin/cass`) — required at runtime. Indexes sessions from 15+ agent providers.
- MCP Go SDK — for the MCP server transport


