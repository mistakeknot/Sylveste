---
name: interknow
description: "Knowledge compounding — durable pattern repository with provenance tracking, temporal decay, and semantic retrieval via qmd."
---
# Gemini Skill: interknow

You have activated the interknow capability.

## Base Instructions
# interknow — Development Guide

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


> Cross-AI documentation for interknow. Works with Claude Code, Codex CLI, and other AI coding tools.

## Quick Reference

| Item | Value |
|------|-------|
| Repo | `https://github.com/mistakeknot/interknow` |
| Namespace | `interknow:` |
| Manifest | `.claude-plugin/plugin.json` |
| Components | 2 skills, 0 commands, 0 agents, 1 hook (SessionStart), 1 MCP server (qmd, optional), 2 scripts |
| License | MIT |

### Release workflow
```bash
scripts/bump-version.sh <version>   # bump, commit, push, publish
```

## Overview

**interknow** is a durable pattern repository with provenance tracking, temporal decay, and semantic retrieval. Every pattern discovered once should be discoverable forever.

**Problem:** Knowledge discovered during reviews and debugging is trapped in conversation context. Same mistakes get rediscovered across sessions. No structured way to accumulate durable patterns.

**Solution:** Two skills (compound + recall), provenance-tracked knowledge entries, and optional semantic search via qmd MCP server.

**Plugin Type:** Claude Code skill + MCP server plugin
**Current Version:** 0.1.0

## Architecture

```
interknow/
├── .claude-plugin/
│   └── plugin.json               # 2 skills + qmd MCP server
├── skills/
│   ├── compound/SKILL.md         # Write knowledge entry with provenance
│   └── recall/SKILL.md           # Query knowledge with domain-aware filtering
├── config/
│   └── knowledge/
│       ├── README.md             # Entry format, provenance rules, decay rules
│       ├── *.md                  # Active knowledge entries
│       └── archive/              # Decayed entries
├── hooks/
│   ├── hooks.json                # SessionStart registration
│   └── session-start.sh          # Reports knowledge stats at session start
├── scripts/
│   ├── launch-qmd.sh             # qmd MCP launcher (graceful if qmd missing)
│   └── bump-version.sh
├── tests/
│   ├── pyproject.toml
│   └── structural/
├── CLAUDE.md
├── AGENTS.md                     # This file
├── PHILOSOPHY.md
└── LICENSE
```

## Provenance Model

Each knowledge entry tracks its source:
- **`independent`** — discovered without prior prompting (high confidence)
- **`primed`** — discovered after being reminded of a similar pattern (lower confidence, needs independent confirmation)

This prevents feedback loops where Claude keeps "discovering" patterns it was told about.

## Decay Rules

- 10 reviews without independent confirmation → archive
- Archived entries remain discoverable but are deprioritized in recall

## How It Works

### `/interknow:compound`
Write a knowledge entry: domain tag, evidence anchors (file:line), provenance source, generalized heuristic (no repo-specific paths).

### `/interknow:recall`
Query knowledge for a topic. Domain-aware filtering narrows results. Returns matching entries ranked by relevance and recency.

### SessionStart Hook
Reports knowledge stats as `additionalContext`: `"interknow: N knowledge entries (M archived)"`.

### qmd MCP Server
Optional semantic search via `vsearch` tool. Launched via `scripts/launch-qmd.sh`. Gracefully exits if `qmd` not installed (`bun install -g @tobilu/qmd`). Skills work without it (reduced to filename/heading matching). Source: https://github.com/tobi/qmd

## Integration Points

| Tool | Relationship |
|------|-------------|
| interflux | Primary consumer — interknow was extracted from interflux's knowledge layer |
| intermem | intermem promotes memory → docs; interknow stores durable patterns (complementary) |
| qmd | External semantic search binary; optional dependency with graceful fallback |

## Testing

```bash
cd tests && uv run pytest -q
```

## Known Constraints

- qmd is an optional external dependency — semantic search degrades gracefully without it
- Knowledge entries must be sanitized (generalized heuristics only, no repo-specific paths)
- Decay threshold (10 reviews) is hardcoded in the compound skill


