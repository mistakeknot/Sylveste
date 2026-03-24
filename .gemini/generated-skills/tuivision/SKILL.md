---
name: tuivision
description: "TUI automation and visual testing - Playwright for terminal applications. Spawn, interact with, and screenshot TUI apps."
---
# Gemini Skill: tuivision

You have activated the tuivision capability.

## Base Instructions
# AGENTS.md — tuivision

MCP server for TUI automation and visual testing — "Playwright for TUIs". Lets Claude Code spawn, interact with, and screenshot terminal applications via virtual PTY sessions backed by xterm.js headless and node-canvas rendering.

## Canonical References
1. [`PHILOSOPHY.md`](../../PHILOSOPHY.md) — direction for ideation and planning decisions.
2. `CLAUDE.md` — implementation details, architecture, testing, and release workflow.

## Quick Reference

| Item | Value |
|------|-------|
| Language | TypeScript (ESM) |
| Node Version | 20+ |
| Build | `npm run build` |
| Entry Point | `dist/index.js` |

## Topic Guides

| Topic | File | Covers |
|-------|------|--------|
| Architecture | [agents/architecture.md](agents/architecture.md) | Component diagram, directory structure, dependencies |
| Development | [agents/development.md](agents/development.md) | Prerequisites, build & test, Claude Code integration |
| MCP Tools | [agents/mcp-tools.md](agents/mcp-tools.md) | spawn_tui, send_input, get_screen, get_screenshot |
| Code Patterns | [agents/code-patterns.md](agents/code-patterns.md) | xterm.js imports, color extraction, session cleanup, known issues |

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


