---
name: interchart
description: "Interactive ecosystem diagram — scans Interverse monorepo and generates a D3.js force graph showing all plugins, skills, MCP tools, hooks, and their relationships."
---
# Gemini Skill: interchart

You have activated the interchart capability.

## Base Instructions
# interchart — AGENTS.md

Interactive ecosystem diagram generator for the Sylveste monorepo. Scans all plugins, skills, agents, MCP servers, hooks, and infrastructure nodes and produces a self-contained D3.js force graph.

**Live diagram:** https://mistakeknot.github.io/interchart/

## Canonical References
1. [`PHILOSOPHY.md`](../../PHILOSOPHY.md) — direction for ideation and planning decisions.
2. `CLAUDE.md` — implementation details, architecture, testing, and release workflow.

## Quick Reference

```bash
# Generate diagram
bash scripts/generate.sh /root/projects/Sylveste

# Scanner only (JSON to stdout)
node scripts/scan.js /root/projects/Sylveste

# Deploy (commit to main triggers Actions)
git add templates/ecosystem.html data/scan.json
git commit -m "chore: regenerate diagram" && git push origin main
```

**Location:** `interverse/interchart/`
**Scanner:** `scripts/scan.js` (Node.js, 455 lines)
**Template:** `templates/ecosystem.html` (D3.js v7, ~850 lines)
**Deploy:** GitHub Actions on push to `main` (NOT `gh-pages`)

## Topic Guides

| Topic | File | Covers |
|-------|------|--------|
| Architecture | [agents/architecture.md](agents/architecture.md) | Pipeline, file layout, data injection |
| Data Model | [agents/data-model.md](agents/data-model.md) | Node types, edge types, overlap/domain system |
| Visualization | [agents/visualization.md](agents/visualization.md) | Toggle architecture, UI layout, sprint nodes, interactions, variable ordering, CSS classes |
| Deployment | [agents/deployment.md](agents/deployment.md) | Deploy steps, agent-driven workflow, GitHub Pages config |
| Extending | [agents/extending.md](agents/extending.md) | Adding plugins, node types, edge types, overlap domains |
| Testing | [agents/testing.md](agents/testing.md) | Manual verification commands |
| Gotchas | [agents/gotchas.md](agents/gotchas.md) | Blank page debugging, deploy pitfalls, CDN dependency, hull edge cases |

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


