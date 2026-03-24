---
name: interskill
description: "Skill authoring toolkit — unified skill creation, TDD-adapted testing, and audit. Consolidated from interdev's create-agent-skills and writing-skills."
---
# Gemini Skill: interskill

You have activated the interskill capability.

## Base Instructions
# interskill — Development Guide

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


> Cross-AI documentation for interskill. Works with Claude Code, Codex CLI, and other AI coding tools.

## Quick Reference

| Item | Value |
|------|-------|
| Repo | `https://github.com/mistakeknot/interskill` |
| Namespace | `interskill:` |
| Manifest | `.claude-plugin/plugin.json` |
| Components | 2 skills, 0 commands, 0 agents, 0 hooks, 1 script |
| License | MIT |

### Release workflow
```bash
scripts/bump-version.sh <version>   # bump, commit, push, publish
```

## Overview

**interskill** is a skill authoring toolkit — unified skill creation with TDD-adapted testing and quality auditing.

**Problem:** Skill files are the primary interface between users and Claude Code plugins. Poorly written skills produce unreliable behavior. No standardized creation workflow or quality verification.

**Solution:** Two skills — `create` (spec-driven creation + TDD pressure testing) and `audit` (standalone quality verification). Consolidated from interdev's `create-agent-skills` and `writing-skills`.

**Plugin Type:** Claude Code skill plugin
**Current Version:** 0.1.0

## Architecture

```
interskill/
├── .claude-plugin/
│   └── plugin.json               # 2 skills
├── skills/
│   ├── create/
│   │   ├── SKILL.md              # Unified creation workflow (spec + TDD phases)
│   │   ├── SKILL-compact.md      # Compact version
│   │   ├── references/           # 14 reference files (Anthropic best practices, structure, etc.)
│   │   ├── templates/            # router-skill.md, simple-skill.md
│   │   └── workflows/            # create-new-skill.md, audit-skill.md, get-guidance.md, etc.
│   └── audit/
│       └── SKILL.md              # Structure + frontmatter + CSO audit
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

### `/interskill:skill`
Two-phase workflow:
1. **Spec phase** — define skill name, description, trigger patterns, argument handling, tool permissions, output format
2. **Quality phase** — TDD-adapted pressure testing: write test scenarios, run skill against them, iterate until robust

### `/interskill:audit`
Standalone quality verification:
- Structure check (frontmatter, SKILL.md location, SKILL-compact.md if applicable)
- Frontmatter validation (description, argument-hint, allowed-tools)
- Invocation control (trigger patterns, false-positive guards)
- CSO compliance (Claude System Operations alignment)

## Component Conventions

### Reference Library
`skills/create/references/` contains 14 files of accumulated patterns and Anthropic best practices — the richest reference collection of any interverse skill. Templates in `skills/create/templates/` provide starting points (router pattern, simple skill).

### Workflows
`skills/create/workflows/` contains step-by-step workflow files that the create skill follows. Each workflow is a self-contained instruction set.

## Integration Points

| Tool | Relationship |
|------|-------------|
| interplug | Companion — interplug handles plugin lifecycle, interskill handles skill content quality |
| interdev | interskill consolidated interdev's skill-authoring skills; interdev now focuses on Claude Code reference docs and MCP CLI |
| interscribe | interscribe applies progressive disclosure to docs; interskill applies it to skills via SKILL-compact.md |

## Testing

```bash
cd tests && uv run pytest -q
```

## Known Constraints

- Consolidated from two separate interdev skills — some reference files may still reference interdev patterns
- `create` skill has rich supporting structure (references, templates, workflows) unlike most skills — more content to maintain
- `audit` is separate from `create` to allow standalone quality-checking of existing skills


