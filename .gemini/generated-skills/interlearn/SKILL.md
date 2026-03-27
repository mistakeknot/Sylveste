---
name: interlearn
description: "Cross-repo institutional knowledge index — indexes solution docs across the Interverse monorepo, enables unified search, and audits reflect coverage."
---
# Gemini Skill: interlearn

You have activated the interlearn capability.

## Base Instructions
# interlearn — Development Guide

## Canonical References
1. [`PHILOSOPHY.md`](../../PHILOSOPHY.md) — direction for ideation and planning decisions.
2. `CLAUDE.md` — implementation details, architecture, testing, and release workflow.

## Philosophy Alignment Protocol
Review [`PHILOSOPHY.md`](../../PHILOSOPHY.md) during:
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


## Architecture

interlearn is a shell-only Claude Code plugin that builds a cross-repo index of solution documents in `docs/solutions/`. It has no MCP server, no Python runtime, and no compiled binary — just one bash script, one skill, and one hook.

### Core Abstractions

- **Solution doc** — a markdown file in any repo's `docs/solutions/` with YAML frontmatter (category, date, tags)
- **Index** — dual output: `INDEX.md` for humans, `index.json` for tools
- **Monorepo root** — detected by 3-marker heuristic (`.beads/` + `plugins/` + `hub/`)

### Components

```
scripts/index-solutions.sh     Deterministic cross-repo index builder (bash)
skills/interlearn/SKILL.md     Skill with 3 modes: index, search, audit
hooks/hooks.json               SessionEnd hook registration
hooks/session-end.sh           Background index refresh trigger
```

### Indexing Script

`scripts/index-solutions.sh` walks `docs/solutions/*.md` across the Interverse monorepo and:
1. Parses YAML frontmatter (tolerant of schema variants: `category` vs `problem_type`, `date_resolved`/`created` vs `date`)
2. Extracts module identity from file path (not frontmatter — too inconsistent)
3. Writes `docs/solutions/INDEX.md` (human-readable table)
4. Writes `docs/solutions/index.json` (machine-readable, keyed by path)

### Skill Modes

| Mode | What it does |
|------|-------------|
| `/interlearn:index` | Rebuild the cross-repo index |
| `/interlearn:search <query>` | Search indexed solutions by keyword |
| `/interlearn:audit` | Check coverage gaps — closed beads without solution docs |

### Hook

`hooks/session-end.sh` fires on `SessionEnd` and re-indexes if the working directory is inside the monorepo. Fail-open: indexing errors never block session teardown.

## Component Conventions

### Frontmatter Schema Tolerance

Solution docs across repos use inconsistent frontmatter. interlearn handles:
- `category` or `problem_type` for categorization
- `date`, `date_resolved`, or `created` for timestamps
- Missing fields are silently skipped, not errors

### Path as Module Identity

Module attribution comes from the file path (`interverse/interflux/docs/solutions/foo.md` → module `interflux`), never from frontmatter `module:` fields which are unreliable.

## Testing

```bash
# Syntax check the indexing script
bash -n scripts/index-solutions.sh

# Verify plugin manifest
python3 -c "import json; json.load(open('.claude-plugin/plugin.json'))"

# Check generated outputs
jq . /home/mk/projects/Sylveste/docs/solutions/index.json
wc -l /home/mk/projects/Sylveste/docs/solutions/INDEX.md
```

No pytest suite — interlearn is shell-only. Validation is structural (manifest, syntax, output format).

## Development Workflow

1. Edit scripts or skill files
2. Syntax-check: `bash -n scripts/index-solutions.sh`
3. Test locally: `claude --plugin-dir interverse/interlearn`
4. Bump version and publish: use `/interpub:release <version>`


