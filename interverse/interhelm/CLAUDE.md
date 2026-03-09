# interhelm

> See `AGENTS.md` for full development guide.

## Overview

3 skills, 1 agent, 3 hooks. Standalone plugin — no intercore dependency. Teaches agents the "agent-as-operator" pattern: observe and control running applications via diagnostic HTTP servers and CLI tools.

## Quick Commands

```bash
python3 -c "import json; json.load(open('.claude-plugin/plugin.json'))"  # Manifest check
ls skills/*/SKILL.md | wc -l  # Should be 3
ls agents/review/*.md | wc -l  # Should be 1
python3 -c "import json; json.load(open('hooks/hooks.json'))"  # Hooks check
cd tests && uv run pytest -q  # Structural tests
```

## Design Decisions (Do Not Re-Ask)

- Standalone plugin — no intercore dependency, pattern works for any app
- Framework-agnostic — skills guide Tauri, Electron, web, CLI scaffolding
- Pattern plugin — teaches the pattern, doesn't ship runtime code
- Structured over visual — prefer JSON state queries over screenshots
- Templates are reference code — not compiled or tested as part of plugin
- Hooks are advisory — suggestions, not blockers
