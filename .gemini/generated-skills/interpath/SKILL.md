---
name: interpath
description: "Product artifact generator — roadmaps, PRDs, vision docs, changelogs, and status reports from beads, brainstorms, and project state. Companion plugin for Clavain."
---
# Gemini Skill: interpath

You have activated the interpath capability.

## Base Instructions
# interpath — Development Guide

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
- **Alignment:** one sentence on how the proposal supports the module's purpose within Demarch's philosophy.
- **Conflict/Risk:** one sentence on any tension with philosophy (or 'none').

If a high-value change conflicts with philosophy, either:
- adjust the plan to align, or
- create follow-up work to update `PHILOSOPHY.md` explicitly.


## Architecture

interpath is a product artifact generator for Claude Code. It synthesizes project documentation from multiple sources:

- **Beads** — issue tracker state (open/closed/blocked counts, priorities)
- **Brainstorms** — design explorations in `docs/brainstorms/`
- **Plans** — implementation plans in `docs/plans/`
- **Flux-drive summaries** — review outputs in `docs/research/flux-drive/`
- **Plugin manifests** — version and component counts from `plugin.json`
- **Git history** — recent commits, tags, activity patterns

### Skill: artifact-gen

The single skill routes to artifact-specific phases:

```
SKILL.md (router)
  → phases/discover.md           (shared source discovery)
  → phases/roadmap.md            (roadmap synthesis)
  → phases/prd.md                (PRD synthesis)
  → phases/vision.md             (vision doc synthesis)
  → phases/changelog.md          (changelog synthesis)
  → phases/status.md             (status report synthesis)
  → phases/discover-monorepo.md  (monorepo source discovery)
  → phases/roadmap-monorepo.md   (monorepo roadmap synthesis)
  → phases/propagate.md          (propagate to sub-module roadmaps)
```

### References

- `references/source-catalog.md` — discoverable source types with glob patterns
- `references/output-templates.md` — structural templates per artifact type

### Interwatch Integration

interpath is a generator target for interwatch's drift-detection framework. When interwatch detects that a product doc (roadmap, PRD, vision) has drifted, it dispatches to `interpath:artifact-gen` with the artifact type. interpath does not know about drift scores or confidence tiers — it receives a generation request and produces an artifact. The contract is:

- interwatch owns detection and dispatch
- interpath owns generation
- Clavain owns when to invoke (via `/interwatch:watch` or `auto-stop-actions.sh`)

interwatch's `signal_templates` in `config/watchables.yaml` declare which signals map to interpath-generated doc types (roadmap, prd, vision).

## Component Conventions

### Skills

- One skill directory: `skills/artifact-gen/`
- SKILL.md has YAML frontmatter with `name` and `description`
- Phase files in `phases/` subdirectory
- Reference files in `references/` subdirectory

### Commands

- 6 commands in `commands/`: roadmap.md, prd.md, vision.md, changelog.md, status.md, propagate.md
- Each has YAML frontmatter with `name` and `description`
- Each invokes the `artifact-gen` skill with the artifact type

## Testing

```bash
cd /root/projects/Interverse/plugins/interpath
uv run pytest tests/structural/ -v
```

### Test Categories

- **test_structure.py** — plugin.json validity, directory structure, marker file
- **test_skills.py** — skill count, frontmatter, phase files, reference files
- **test_commands.py** — command count, frontmatter, expected commands exist

## Development Workflow

1. Edit skill/command files
2. Run structural tests: `uv run pytest tests/structural/ -v`
3. Test locally: `claude --plugin-dir /root/projects/Interverse/plugins/interpath`
4. Bump version and publish: `scripts/bump-version.sh <version>`


