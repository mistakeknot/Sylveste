---
name: intership
description: "Culture ship names as Claude Code spinner verbs. Because why would you settle for 'Thinking...' when you could have 'Experiencing A Significant Gravitas Shortfall'?"
---
# Gemini Skill: intership

You have activated the intership capability.

## Base Instructions
# intership — Development Guide

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


> Cross-AI documentation for intership. Works with Claude Code, Codex CLI, and other AI coding tools.

## Quick Reference

| Item | Value |
|------|-------|
| Repo | `https://github.com/mistakeknot/intership` |
| Namespace | `intership:` |
| Manifest | `.claude-plugin/plugin.json` |
| Components | 0 skills, 1 command, 0 agents, 1 hook (SessionStart), 2 scripts |
| License | MIT |

### Release workflow
```bash
scripts/bump-version.sh <version>   # bump, commit, push, publish
```

## Overview

**intership** replaces Claude Code's default spinner verbs with Culture ship names from Iain M. Banks' novels. 237 curated names — 56 canonical Banks originals, 181 generated Banksian originals refined over 6 rounds.

**Problem:** "Thinking..." is boring.

**Solution:** SessionStart hook writes `spinnerVerbs` to `~/.claude/settings.json`. Names span 8 rhetorical registers: terse loaded phrases, conversational asides, dry understatement, bewildered observers, polite menace, dark whimsy, bureaucratic absurdity, single evocative words.

**Plugin Type:** Claude Code command + hook plugin
**Current Version:** 0.3.0

## Architecture

```
intership/
├── .claude-plugin/
│   └── plugin.json               # 1 command
├── commands/
│   └── setup.md                  # /intership:setup — interactive customization
├── data/
│   ├── ships.txt                 # 237 ship names (canonical marked with *asterisks*)
│   ├── config.json               # {"includeCanonical": true, "includeGenerated": true}
│   └── generator-prompt.md       # v6 name generation prompt (11KB)
├── hooks/
│   ├── hooks.json                # SessionStart registration
│   └── session-start.sh          # Writes spinnerVerbs to ~/.claude/settings.json
├── scripts/
│   ├── bump-version.sh
│   └── validate-gitleaks-waivers.sh
├── tests/
│   ├── pyproject.toml
│   └── structural/
├── CLAUDE.md
├── AGENTS.md                     # This file
├── PHILOSOPHY.md
└── README.md
```

## How It Works

### SessionStart Hook
`hooks/session-start.sh` reads `data/ships.txt`, applies config filters (canonical/generated), writes the `spinnerVerbs` array to `~/.claude/settings.json`.

### `/intership:setup` Command
Interactive customization: filter by book, add/remove individual ships, toggle canonical vs generated mode.

### Ship Name Data
`data/ships.txt` — one name per line. `#` comment headers mark source novels. Names wrapped in `*asterisks*` are canonical Banks originals. User-editable directly; changes apply next session.

### Generator Prompt
`data/generator-prompt.md` — v6 prompt iteratively refined over 6 rounds and ~380 candidates. For users who want to generate more names in the Banksian style.

## Integration Points

| Tool | Relationship |
|------|-------------|
| intername | intername handles agent identity naming; intership handles cosmetic spinner verbs (separate concerns) |
| interline | interline manages statusline; intership manages spinner verbs (complementary UI surfaces) |

## Testing

```bash
cd tests && uv run pytest -q
```

## Known Constraints

- Names restart each session — no deduplication within session by default
- Writes directly to `~/.claude/settings.json` — could conflict with other plugins modifying the same file
- `data/ships.txt` is user-editable but format-sensitive (one name per line, `#` for headers)


