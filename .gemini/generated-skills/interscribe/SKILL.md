---
name: interscribe
description: "Documentation quality toolkit — enforces CLAUDE.md/AGENTS.md boundaries, applies progressive disclosure, deduplicates across doc hierarchy."
---
# Gemini Skill: interscribe

You have activated the interscribe capability.

## Base Instructions
# interscribe — Development Guide

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


> Cross-AI documentation for interscribe. Works with Claude Code, Codex CLI, and other AI coding tools.

## Quick Reference

| Item | Value |
|------|-------|
| Repo | `https://github.com/mistakeknot/interscribe` |
| Namespace | `interscribe:` |
| Manifest | `.claude-plugin/plugin.json` |
| Components | 1 skill, 0 commands, 0 agents, 0 hooks, 3 scripts |
| License | MIT |

### Release workflow
```bash
scripts/bump-version.sh <version>   # bump, commit, push, publish
```

## Overview

**interscribe** is a documentation quality toolkit that enforces the CLAUDE.md/AGENTS.md boundary, applies progressive disclosure to project docs, and deduplicates instructions across the doc loading hierarchy.

**Problem:** CLAUDE.md files accumulate project knowledge that belongs in AGENTS.md. AGENTS.md sections grow without bounds. The same instruction appears at multiple hierarchy levels. No tool restructures docs after they're created.

**Solution:** Three modes — audit (report health), refactor (restructure automatically), consolidate (deduplicate across hierarchy).

**Plugin Type:** Claude Code skill plugin
**Current Version:** 0.1.0

## Architecture

```
interscribe/
├── .claude-plugin/
│   └── plugin.json               # Plugin metadata and version
├── skills/
│   └── interscribe/
│       └── SKILL.md              # Main skill (3 modes: audit, refactor, consolidate)
├── scripts/
│   ├── audit-docs.sh             # Token counting, line metrics
│   ├── find-duplicates.sh        # Heading overlap detection across doc hierarchy
│   └── bump-version.sh           # Version management (delegates to ic or interbump.sh)
├── tests/
│   ├── pyproject.toml            # pytest config
│   └── structural/
│       ├── conftest.py           # Shared fixtures
│       ├── helpers.py            # Frontmatter parser
│       ├── test_structure.py     # Plugin structure validation
│       └── test_skills.py        # Skill count and frontmatter checks
├── CLAUDE.md                     # Claude Code settings only
├── AGENTS.md                     # This file — cross-AI development guide
├── PHILOSOPHY.md                 # Design bets and tradeoffs
├── README.md                     # User-facing documentation
└── LICENSE                       # MIT
```

## The Boundary Rule

The single convention that drives all of interscribe's behavior:

| File | Contains | Does NOT contain |
|------|----------|-----------------|
| CLAUDE.md | Plugin settings, hook config, tool preferences, permissions, Claude-specific behavioral overrides | Architecture, workflows, conventions, git workflow, build instructions, troubleshooting |
| AGENTS.md | Architecture, workflows, conventions, standards, troubleshooting, build instructions | Plugin/hook config, Claude-specific tool preferences |
| docs/ | Deep reference content linked from AGENTS.md sections | Top-level project overview (that belongs in AGENTS.md) |

**Any project knowledge in CLAUDE.md is a boundary violation.**

## How It Works

### Audit Mode
Non-destructive analysis. Runs 5 checks:

1. **Boundary check** — classifies each CLAUDE.md section as tool config or project knowledge
2. **Token budget** — counts lines, estimates tokens, flags over-budget files
3. **Duplication** — detects identical instructions across CLAUDE.md/AGENTS.md hierarchy
4. **Staleness** — finds references to deleted files, outdated versions, removed features
5. **Depth violations** — flags AGENTS.md sections exceeding 100 lines

Outputs a health score (A-F) based on violation count and severity.

### Refactor Mode
Fully automatic restructuring. All changes reviewable via `git diff`.

1. Moves project knowledge from CLAUDE.md → AGENTS.md
2. Extracts oversized AGENTS.md sections → docs/ reference files with backlinks
3. Removes duplicates (keeps canonical location, adds pointers from others)
4. Fixes stale references

### Consolidate Mode
Cross-hierarchy deduplication. Maps the full doc loading tree (global → project → subproject), finds duplicate instructions, keeps them at the highest common ancestor level. Flags contradictions for manual resolution.

## Component Conventions

### Skills
One skill: `interscribe`. Lives at `skills/interscribe/SKILL.md`. Uses YAML frontmatter with `name`, `description`, and `argument-hint`. Accepts mode and path as arguments.

### Scripts
Shell scripts provide deterministic metrics that the skill invokes:

| Script | Purpose |
|--------|---------|
| `audit-docs.sh [root]` | Line/token counts for all CLAUDE.md and AGENTS.md files, budget flags |
| `find-duplicates.sh [root]` | H2 heading overlap detection across doc hierarchy |
| `bump-version.sh <version>` | Version management (delegates to `ic publish` or `interbump.sh`) |

## Integration Points

| Tool | Relationship |
|------|-------------|
| interdoc | interdoc generates AGENTS.md from code. interscribe restructures it for optimal consumption. Run interdoc first, interscribe after. |
| interwatch | interwatch detects content drift. Could trigger interscribe:audit when structural drift detected. |
| /review-doc | review-doc scores content quality. interscribe scores structural quality. Complementary. |
| /distill | distill applies progressive disclosure to skills. interscribe applies it to project docs. Same pattern, different targets. |
| intermem:synthesize | intermem promotes memory → docs. interscribe restructures the result. |

## docs/canon/ Convention

Foundational docs that define project identity and standards. Applies to all repos:

```
docs/canon/
├── PHILOSOPHY.md      # Design bets and tradeoffs
├── doc-structure.md   # Pointer-doc standard, token budgets, boundary rules
└── naming.md          # Naming conventions
```

Operational docs (CLAUDE.md, AGENTS.md) stay at project root — they're auto-loaded by tools.

## Testing

```bash
cd tests && uv run pytest -q
```

Structural tests validate:
- plugin.json is valid JSON with required fields
- Skill count matches expected (1)
- SKILL.md has valid frontmatter with `name` and `description`
- Required files exist (README.md, CLAUDE.md, AGENTS.md, PHILOSOPHY.md, LICENSE)
- Scripts are executable

## Validation Checklist

```bash
ls skills/*/SKILL.md | wc -l          # Should be 1
ls scripts/*.sh | wc -l               # Should be 3
python3 -c "import json; json.load(open('.claude-plugin/plugin.json'))"  # Manifest check
```

## Known Constraints

- Semantic duplication detection depends on the LLM — shell scripts only catch heading overlap
- Consolidate mode requires access to global `~/.claude/CLAUDE.md` which may not be readable in all environments
- The boundary rule is a convention, not a hard constraint — interscribe reports and fixes violations but can't prevent them from being reintroduced


