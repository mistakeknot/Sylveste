---
name: intersense
description: "Domain detection — classifies projects by signals (directories, manifests, dependencies, keywords) into domains for review and research targeting"
---
# Gemini Skill: intersense

You have activated the intersense capability.

## Base Instructions
# intersense — Development Guide

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


> Cross-AI documentation for intersense. Works with Claude Code, Codex CLI, and other AI coding tools.

## Quick Reference

| Item | Value |
|------|-------|
| Repo | `https://github.com/mistakeknot/intersense` |
| Namespace | `intersense:` |
| Manifest | `.claude-plugin/plugin.json` |
| Components | 0 skills, 0 commands, 0 agents, 0 hooks, 0 MCP servers, 2 scripts + 11 domain profiles |
| License | MIT |

### Release workflow
```bash
scripts/bump-version.sh <version>   # bump, commit, push, publish
```

## Overview

**intersense** is a domain detection library — classifies projects by signals (directories, manifests, dependencies, keywords) into domains for review and research targeting.

**Problem:** Review agents and research tools treat all projects the same. A web API needs different review criteria than a CLI tool or game simulation. No automated way to detect project domain.

**Solution:** Signal-based classifier with 11 domain profiles. Produces a cached `.claude/intersense.yaml` for consumption by other plugins.

**Plugin Type:** Scripts-only library (no Claude Code components)
**Current Version:** 0.1.0

## Architecture

```
intersense/
├── .claude-plugin/
│   └── plugin.json               # Metadata only (no components)
├── scripts/
│   ├── detect-domains.py         # Signal-based domain classifier (25KB)
│   ├── content-hash.py           # Content hash for staleness detection
│   └── bump-version.sh
├── config/
│   └── domains/
│       ├── index.yaml            # Signal definitions + confidence thresholds
│       ├── claude-code-plugin.md
│       ├── cli-tool.md
│       ├── data-pipeline.md
│       ├── desktop-tauri.md
│       ├── embedded-systems.md
│       ├── game-simulation.md
│       ├── library-sdk.md
│       ├── ml-pipeline.md
│       ├── mobile-app.md
│       ├── tui-app.md
│       └── web-api.md
├── tests/
│   ├── pyproject.toml
│   └── structural/
├── CLAUDE.md
├── AGENTS.md                     # This file
├── PHILOSOPHY.md
└── README.md
```

## Domain Profiles

11 profiles, each containing:
- **Detection signals** — directories, files, dependencies, keywords to match
- **Review criteria** — domain-specific injection bullets for review agents
- **Research Directives** — context for external research agents

| Domain | Key Signals |
|--------|-------------|
| `claude-code-plugin` | `.claude-plugin/`, SKILL.md, hooks.json |
| `cli-tool` | cobra, argparse, clap, `cmd/` |
| `data-pipeline` | airflow, dagster, dbt, `pipelines/` |
| `desktop-tauri` | tauri.conf.json, electron, `src-tauri/` |
| `embedded-systems` | platformio.ini, `hal/`, `firmware/` |
| `game-simulation` | bevy, unity, `assets/`, `shaders/` |
| `library-sdk` | `src/lib.rs`, `index.ts`, `__init__.py`, package.json |
| `ml-pipeline` | pytorch, tensorflow, `models/`, `training/` |
| `mobile-app` | `AndroidManifest.xml`, `Info.plist`, react-native |
| `tui-app` | bubbletea, ratatui, blessed, `views/` |
| `web-api` | express, fastapi, gin, `routes/`, `controllers/` |

## Usage

```bash
# Detect domains for a project
python3 scripts/detect-domains.py /path/to/project

# Check if cache is stale
python3 scripts/detect-domains.py /path/to/project --check-stale

# Content hash for a file
python3 scripts/content-hash.py /path/to/file
```

Output is cached at `.claude/intersense.yaml` in the target project. A project can match multiple domains simultaneously.

## Integration Points

| Tool | Relationship |
|------|-------------|
| interflux | Primary consumer — interflux's `detect-domains.py` is a thin stub that delegates here via `os.execv` |
| intersearch | Domain classification can inform research targeting |

## Testing

```bash
cd tests && uv run pytest -q
```

## Known Constraints

- Scripts-only plugin — no Claude Code components; other plugins call scripts directly
- Extracted from interflux (2026-02-25); cache key renamed from `.claude/flux-drive.yaml` → `.claude/intersense.yaml`
- Domain profiles require manual updates when new project types emerge


