---
artifact_type: prd
bead: Demarch-6qb.7
stage: strategize
---

# PRD: Interverse Plugin Compatibility Layer for Skaffen

**Date:** 2026-03-16
**Bead:** Demarch-6qb.7
**Priority:** P3 (but highest-impact single feature for Skaffen ecosystem integration)

## Problem

Skaffen agents cannot access Interverse plugins. The 53+ plugins (MCP tools, skills, commands, agents, hooks) that power the Clavain-rigged Claude Code experience are invisible to Skaffen. This means Skaffen agents can't use interflux review, interlock coordination, intersearch, or any other plugin capability.

## Solution

Auto-discover and load Interverse plugins into Skaffen's existing runtime registries. A new `internal/plugin/` package scans `interverse/*/. claude-plugin/plugin.json`, resolves all five capability types (MCP, skills, commands, agents, hooks), and injects them into Skaffen's existing infrastructure.

## Success Criteria

1. `skaffen` binary auto-discovers plugins from `interverse/` on startup
2. MCP tools from all plugins are available in the tool registry
3. Skills from plugins appear in `/skills` command and trigger matching
4. Commands from plugins appear in `/` autocomplete
5. Agent definitions from plugins are dispatchable via subagent system
6. Plugin hooks fire alongside built-in hooks
7. All 919+ existing tests still pass
8. No startup regression >200ms with all 53 plugins loaded

## Features

### F1: Plugin Auto-Discovery
Scan `interverse/*/. claude-plugin/plugin.json` relative to git root. Parse manifests. Manual `plugins.toml` entries take precedence.

### F2: MCP Server Registration
Convert discovered `mcpServers` entries into `PluginConfig`. Expand `${CLAUDE_PLUGIN_ROOT}`. Lazy-connect on first tool use (don't spawn 53 servers at startup).

### F3: Skill Path Resolution
Add Interverse skill directories as tier 5 in `SkillDirs()`. Zero format translation needed.

### F4: Command Markdown Loader
Parse Interverse command .md files (YAML frontmatter + body) into `command.Def`. Body becomes template text. Plugin commands at lowest precedence tier.

### F5: Agent Markdown Loader
Parse Interverse agent .md files into `SubagentType`. Body becomes `SystemPrompt`. Qualified name: `pluginName:agentName`.

### F6: Hook CLAUDE_PLUGIN_ROOT Expansion
Expand `${CLAUDE_PLUGIN_ROOT}` in hook command paths. Append plugin hooks after project hooks (lowest precedence).

### F7: Unified Plugin Loader
`internal/plugin/` package ties F1-F6 together. Single `Discover() + Inject()` entry point from `main.go`.

## Non-Goals

- Full hook lifecycle parity (Stop event, async execution)
- Plugin dependency resolution
- Plugin version management
- Plugin marketplace integration
- Hot-reloading plugins at runtime

## Phased Rollout

| Phase | Features | Effort | Value |
|-------|----------|--------|-------|
| 1 | F1 + F2 (discovery + MCP) | ~4h | 80% (most plugins are MCP-only) |
| 2 | F3 + F4 (skills + commands) | ~3h | 10% |
| 3 | F5 (agents) | ~4h | 8% |
| 4 | F6 + F7 (hooks + unified loader) | ~5h | 2% |

## Architecture

See `docs/research/assess-interverse-plugin-compatibility.md` § "Integration Design" for file-level architecture, function signatures, and wiring diagram.
