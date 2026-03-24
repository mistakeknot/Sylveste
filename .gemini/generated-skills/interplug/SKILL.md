---
name: interplug
description: "Plugin development toolkit — lifecycle management, structure validation, and troubleshooting for Claude Code plugins"
---
# Gemini Skill: interplug

You have activated the interplug capability.

## Base Instructions
# interplug — Development Guide

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


> Cross-AI documentation for interplug. Works with Claude Code, Codex CLI, and other AI coding tools.

## Quick Reference

| Item | Value |
|------|-------|
| Repo | `https://github.com/mistakeknot/interplug` |
| Namespace | `interplug:` |
| Manifest | `.claude-plugin/plugin.json` |
| Components | 3 skills, 0 commands, 0 agents, 0 hooks, 1 script |
| License | MIT |

### Release workflow
```bash
scripts/bump-version.sh <version>   # bump, commit, push, publish
```

## Overview

**interplug** is a plugin development toolkit — lifecycle management (create), structure validation (validate), and troubleshooting (troubleshoot) for Claude Code plugins.

**Problem:** Plugin creation involves many moving parts (plugin.json, skills, hooks, commands, MCP servers, marketplace registration). Easy to get structure wrong. Debugging plugin loading issues is opaque.

**Solution:** Three focused skills covering the full plugin lifecycle from creation through validation to debugging.

**Plugin Type:** Claude Code skill plugin
**Current Version:** 0.1.0

## Architecture

```
interplug/
├── .claude-plugin/
│   └── plugin.json               # 3 skills
├── skills/
│   ├── create/
│   │   ├── SKILL.md              # Full plugin creation workflow
│   │   ├── SKILL-compact.md      # Compact version
│   │   └── references/           # 14 reference files (patterns, structure, knowledge)
│   ├── validate/
│   │   └── SKILL.md              # Structure validation
│   └── troubleshoot/
│       ├── SKILL.md              # Debug guide
│       └── SKILL-compact.md
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

### `/interplug:create-plugin`
Full plugin lifecycle workflow — plan structure, create directories, add components (skills, hooks, commands, MCP servers), configure plugin.json, test, and release.

### `/interplug:validate`
Structural validation: checks plugin.json schema, skill/command/hook path resolution, hook event validity, permission declarations, and marketplace registration.

### `/interplug:troubleshoot`
Debug guide for common issues: plugin not loading, skill not triggering, hooks not firing, MCP server crashes, permission denials.

## Component Conventions

### Skills
Three skills, each with a distinct concern. The `create` skill has a `references/` subdirectory with 14 reference files (common patterns, plugin structure, polyglot hooks, troubleshooting, and knowledge entries). This is the richest reference collection of any interverse skill.

### References
`skills/create/references/` contains accumulated patterns and knowledge entries extracted from real plugin development. These are loaded by the create skill and provide context for generation decisions.

## Integration Points

| Tool | Relationship |
|------|-------------|
| interskill | Companion — interplug handles plugin lifecycle, interskill handles skill content quality |
| interdev | interplug extracted from interdev; interdev now focuses on Claude Code reference docs and MCP CLI |
| interscribe | interscribe restructures docs; interplug generates initial plugin structure |

## Testing

```bash
cd tests && uv run pytest -q
```

## Known Constraints

- `create` skill reference files are specific to Claude Code's plugin system — not portable to other AI tool platforms
- Extracted from interdev (2026-02-25); some reference files may still reference interdev patterns


