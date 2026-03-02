---
name: intertree
description: "Project hierarchy management — filesystem discovery, parent-child relationships, tagging, and layout orchestration"
---
# Gemini Skill: intertree

You have activated the intertree capability.

## Base Instructions
# intertree

Project hierarchy management — filesystem discovery, parent-child relationships, tagging, and layout orchestration.

## Overview

1 skill, 0 agents, 0 commands, 0 hooks.

## Skills

| Skill | What it does |
|-------|-------------|
| `layout` | Interactive project discovery, hierarchy review, classification, and registration |

## Architecture

Intertree owns the **hierarchy concern** extracted from interkasten:

- **Pure functions** (`server/src/discovery.ts`, `server/src/signals.ts`): filesystem tree walking, signal gathering — no DB or Notion dependencies
- **MCP tools**: Currently still registered in interkasten (`interkasten_scan_preview`, `interkasten_set_project_parent`, `interkasten_set_project_tags`, `interkasten_gather_signals`, `interkasten_scan_files`, `interkasten_add_database_property`). Will be migrated to intertree MCP server in a future phase.
- **Shared DB access**: via interbase SDK (`sdk/interbase/lib/interkasten-db.sh`)

## Dependencies

- **interkasten** — MCP tools for hierarchy operations (until tool migration)
- **interbase** — shared SQLite access to `~/.interkasten/state.db`

## Design Decisions (Do Not Re-Ask)

- Extracted from interkasten's hierarchy tools (2026-02-25)
- Pure functions extracted immediately; MCP tool registration deferred (requires DaemonContext decoupling)
- Layout skill references interkasten tools by current names (will rename to `intertree_*` after MCP migration)


