---
name: interknow
description: "Knowledge compounding — durable pattern repository with provenance tracking, temporal decay, and semantic retrieval via qmd."
---
# Gemini Skill: interknow

You have activated the interknow capability.

## Base Instructions
# interknow

Knowledge compounding — durable pattern repository with provenance tracking, temporal decay, and semantic retrieval.

## Overview

2 skills, 0 agents, 0 commands, 1 hook, 1 MCP server (qmd). Extracted from interflux's knowledge layer (2026-02-25).

## MCP Server

qmd semantic search (via `scripts/launch-qmd.sh`). Graceful degradation if qmd not installed.

## Skills

| Skill | Purpose |
|-------|---------|
| `/interknow:compound` | Write a knowledge entry with provenance, domain tag, evidence anchors |
| `/interknow:recall` | Query knowledge for a topic with domain-aware filtering |

## Key Files

- `config/knowledge/` — Knowledge entries (markdown with YAML frontmatter)
- `config/knowledge/README.md` — Entry format, provenance rules, decay rules
- `scripts/launch-qmd.sh` — qmd MCP launcher with graceful degradation
- `hooks/session-start.sh` — Reports knowledge stats at session start

## Quick Commands

```bash
# Count knowledge entries
ls config/knowledge/*.md | grep -v README | wc -l

# Validate frontmatter
for f in config/knowledge/*.md; do head -5 "$f" | grep -q "lastConfirmed:" && echo "OK: $f" || echo "MISSING: $f"; done
```

## Design Decisions (Do Not Re-Ask)

- Extracted from interflux knowledge layer (was `config/flux-drive/knowledge/`)
- Provenance tracking: `independent` vs `primed` prevents false-positive feedback loops
- Decay: 10 reviews without independent confirmation → archive
- Sanitization: generalized heuristics only, no repo-specific paths
- qmd provides semantic search across entries (vsearch tool)


