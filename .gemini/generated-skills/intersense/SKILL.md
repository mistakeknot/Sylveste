---
name: intersense
description: "Domain detection — classifies projects by signals (directories, manifests, dependencies, keywords) into domains for review and research targeting"
---
# Gemini Skill: intersense

You have activated the intersense capability.

## Base Instructions
# intersense

Domain detection — classifies projects by signals into domains for review and research targeting.

## Overview

0 skills, 0 agents, 0 commands, 0 hooks. Scripts-only plugin.

## Scripts

| Script | What it does |
|--------|-------------|
| `detect-domains.py` | Scans project signals, classifies into domains, caches at `.claude/intersense.yaml` |
| `content-hash.py` | Content-addressable hashing for staleness detection |

## Domain Profiles

11 domain profiles in `config/domains/` with `index.yaml` manifest:
- claude-code-plugin, cli-tool, data-pipeline, desktop-tauri, embedded-systems
- game-simulation, library-sdk, ml-pipeline, mobile-app, tui-app, web-api

Each profile contains detection signals (directories, files, dependencies, keywords) and domain-specific review criteria (injection bullets per agent) plus Research Directives for external agents.

## Usage

```bash
# Detect domains for a project
python3 scripts/detect-domains.py /path/to/project

# Check if cache is stale
python3 scripts/detect-domains.py /path/to/project --check-stale

# Content hash for a file
python3 scripts/content-hash.py /path/to/file
```

## Design Decisions (Do Not Re-Ask)

- Extracted from interflux domain detection (2026-02-25)
- Cache file: `.claude/intersense.yaml` (was `.claude/flux-drive.yaml`)
- No MCP server, no skills — pure scripts consumed by interflux and other plugins
- Domain profiles include both review injection criteria and Research Directives


