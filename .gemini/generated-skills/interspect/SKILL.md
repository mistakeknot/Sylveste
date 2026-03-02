---
name: interspect
description: "Agent performance profiler and routing optimizer. Collects evidence about flux-drive agent accuracy, proposes routing overrides for underperforming agents, and monitors canary periods. Companion plugin for Clavain."
---
# Gemini Skill: interspect

You have activated the interspect capability.

## Base Instructions
# interspect

> See `AGENTS.md` for full development guide.

## Overview

Agent performance profiler and routing optimizer — 0 skills, 12 commands, 0 agents, 3 hooks, 0 MCP servers. Companion plugin for Clavain. Collects evidence about flux-drive agent accuracy, proposes routing overrides, and monitors canary periods.

## Quick Commands

```bash
# Test locally
claude --plugin-dir /home/mk/projects/Demarch/interverse/interspect

# Validate structure
ls commands/*.md | wc -l              # Should be 12
bash -n hooks/lib-interspect.sh       # Syntax check
python3 -c "import json; json.load(open('.claude-plugin/plugin.json'))"  # Manifest check
python3 -c "import json; json.load(open('hooks/hooks.json'))"           # Hooks JSON check
```

## Design Decisions (Do Not Re-Ask)

- Namespace: `interspect:` (companion to Clavain)
- Evidence stored in `.clavain/interspect/interspect.db` (SQLite)
- Routing overrides written to `.claude/routing-overrides.json` (cross-repo contract)
- Canary monitoring: 20-use window over 14 days, 20% alert threshold
- Protected paths enforced via `.clavain/interspect/protected-paths.json`
- Discovery via clavain lib.sh `_discover_interspect_plugin()` looking for `hooks/lib-interspect.sh`


