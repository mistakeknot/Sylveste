---
name: intertree
description: "Project hierarchy management — filesystem discovery, parent-child relationships, tagging, and layout orchestration"
---
# Gemini Skill: intertree

You have activated the intertree capability.

## Base Instructions
# intertree — Development Guide

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
- **Alignment:** one sentence on how the proposal supports the module's purpose within Sylveste's philosophy.
- **Conflict/Risk:** one sentence on any tension with philosophy (or 'none').

If a high-value change conflicts with philosophy, either:
- adjust the plan to align, or
- create follow-up work to update `PHILOSOPHY.md` explicitly.


> Cross-AI documentation for intertree. Works with Claude Code, Codex CLI, and other AI coding tools.

## Quick Reference

| Item | Value |
|------|-------|
| Repo | `https://github.com/mistakeknot/intertree` |
| Namespace | `intertree:` |
| Manifest | `.claude-plugin/plugin.json` |
| Components | 1 skill, 0 commands, 0 agents, 0 hooks, 0 MCP servers (pending migration), 1 script |
| License | MIT |

### Release workflow
```bash
scripts/bump-version.sh <version>   # bump, commit, push, publish
```

## Overview

**intertree** manages project hierarchy — filesystem discovery, parent-child relationships, tagging, and layout orchestration. Extracted from interkasten's hierarchy tools.

**Problem:** Interkasten conflated Notion sync with project hierarchy management. Hierarchy logic (discovery, parent-child, tagging) should be independent of the sync target.

**Solution:** Pure TypeScript functions for tree walking and signal gathering, plus a layout skill for interactive project organization. MCP tools still hosted in interkasten pending migration.

**Plugin Type:** Claude Code skill plugin (+ TypeScript server, not yet wired)
**Current Version:** 0.1.0

## Architecture

```
intertree/
├── .claude-plugin/
│   └── plugin.json               # 1 skill (no mcpServers declared yet)
├── skills/
│   └── layout/
│       ├── SKILL.md              # 6-step interactive project discovery workflow
│       └── SKILL-compact.md      # Compact version
├── server/
│   └── src/
│       ├── discovery.ts          # Pure filesystem tree walking (no DB dependency)
│       └── signals.ts            # Pure signal gathering (no Notion dependency)
├── scripts/
│   └── bump-version.sh
├── tests/
│   ├── pyproject.toml
│   └── structural/
├── CLAUDE.md
├── AGENTS.md                     # This file
├── PHILOSOPHY.md
├── README.md
└── LICENSE
```

## How It Works

### `/intertree:layout` Skill
6-step interactive workflow:
1. **Scan** — `interkasten_scan_preview` to discover projects
2. **Hierarchy Review** — confirm parent-child relationships via `interkasten_set_project_parent`
3. **Classification** — gather signals, propose doc tier/tags/status
4. **Notion Schema** — `interkasten_add_database_property` for new properties
5. **Register** — parent-first registration via `interkasten_register_project`
6. **File Selection** — choose which project files to track

### Hierarchy Rules
- `.beads` is the hierarchy marker — nearest ancestor with `.beads` = parent
- `.git` is a project detection marker only (doesn't imply parentage)
- Intermediate directories without markers are transparent (traversed, not registered)
- Symlinks deduplicated via `realpathSync()`

### TypeScript Server (Not Yet Wired)
`server/src/discovery.ts` and `server/src/signals.ts` contain pure functions extracted from interkasten. No DB or Notion dependencies. These will become the intertree MCP server once DaemonContext decoupling from interkasten is complete.

## MCP Tools (Currently in interkasten)

These tools will migrate to intertree's own MCP server:
- `interkasten_scan_preview` → `intertree_scan_preview`
- `interkasten_set_project_parent` → `intertree_set_project_parent`
- `interkasten_set_project_tags` → `intertree_set_project_tags`
- `interkasten_gather_signals` → `intertree_gather_signals`
- `interkasten_scan_files` → `intertree_scan_files`
- `interkasten_add_database_property` → `intertree_add_database_property`

## Integration Points

| Tool | Relationship |
|------|-------------|
| interkasten | Current host for intertree's MCP tools; provides Notion sync; shared SQLite via `~/.interkasten/state.db` |
| interbase | Shared SQLite access via `sdk/interbase/lib/interkasten-db.sh` |
| intersense | intersense detects project domains; intertree manages hierarchy/layout (complementary) |

## Testing

```bash
cd tests && uv run pytest -q
```

## Known Constraints

- MCP tools still registered in interkasten (requires DaemonContext decoupling for migration)
- Layout skill references `interkasten_*` tool names — will rename to `intertree_*` after MCP migration
- Pure TS functions extracted but not yet serving as an MCP server


