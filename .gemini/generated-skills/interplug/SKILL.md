---
name: interplug
description: "Plugin development toolkit — lifecycle management, structure validation, and troubleshooting for Claude Code plugins"
---
# Gemini Skill: interplug

You have activated the interplug capability.

## Base Instructions
# Interplug

Plugin development toolkit — lifecycle management, structure validation, and troubleshooting for Claude Code plugins.

## Skills

| Skill | What it does |
|-------|-------------|
| `create` | Full plugin lifecycle — plan, create structure, add components, test, release |
| `validate` | Structural validation — checks plugin.json, paths, hooks, permissions |
| `troubleshoot` | Debug guide — plugin not loading, skill not triggering, hooks not firing |

## Companion Plugins

- **interskill** — skill authoring toolkit (for creating skills within plugins)
- **interdev** — Claude Code reference docs and MCP CLI interaction

## Design Decisions (Do Not Re-Ask)

- Extracted from interdev's developing-claude-code-plugins skill (2026-02-25)
- Three focused skills instead of one monolithic skill
- Reference files shared across skills via relative paths


