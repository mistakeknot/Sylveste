---
artifact_type: brainstorm
bead: Sylveste-6qb.7
stage: discover
---

# Interverse Plugin Compatibility Layer for Skaffen

**Date:** 2026-03-16
**Bead:** Sylveste-6qb.7
**Phase:** brainstorm (as of 2026-03-16T06:29:56Z)

## What We're Building

Auto-discovery and loading of all 53+ Interverse plugins into Skaffen's runtime, so Skaffen agents get access to the same MCP tools, skills, commands, agents, and hooks that Claude Code agents get via the Interverse plugin ecosystem.

## Why This Approach

The assessment at `docs/research/assess-interverse-plugin-compatibility.md` (adopt verdict) validated that Skaffen already has ~80% protocol compatibility:

- **MCP client** — fully working, just needs auto-discovery
- **Skills** — identical SKILL.md format, just needs path resolution
- **Hooks** — 90% format match, needs `${CLAUDE_PLUGIN_ROOT}` expansion
- **Commands** — TOML vs Markdown format mismatch, needs loader
- **Agents** — TOML vs Markdown format mismatch, needs loader

The gap is **discovery, not protocol**. Total new code: ~865 lines across 12 files.

## Key Decisions

### D1: Unified plugin package as orchestrator
A new `internal/plugin/` package discovers all plugins and injects their capabilities into existing registries. This avoids scattering Interverse-specific logic across 5 packages.

### D2: Auto-discovery scans `interverse/` relative to git root
`DiscoverPlugins(baseDir)` walks `interverse/*/. claude-plugin/plugin.json`. Manual `plugins.toml` entries take precedence over auto-discovered ones.

### D3: Markdown loaders for commands and agents
New `markdown.go` files in `internal/command/` and `internal/subagent/` parse Interverse .md files with YAML frontmatter. The markdown body becomes the template (commands) or system prompt (agents).

### D4: Plugin agents get qualified names
Plugin-sourced agents use `pluginName:agentName` format (e.g., `interflux:fd-architecture`) to avoid collisions with built-in agents.

### D5: Hook expansion for CLAUDE_PLUGIN_ROOT
Hook loader gets `${CLAUDE_PLUGIN_ROOT}` expansion matching MCP config's existing logic. `Stop` event mapped but not fired (logged as warning). `async: true` ignored (Skaffen hooks are already non-blocking for advisory events).

### D6: Phased rollout — MCP first
Phase 1 (MCP auto-discovery, ~4 hours) unlocks 80% of value since most plugins are MCP-server-only. Subsequent phases add skills, commands, agents, hooks.

## Validation Results

Codebase validation confirmed:
- Assessment's function signatures match current code
- Tool naming convention: `plugin_server_toolname` (underscores)
- Skills have 4 config tiers, commands have 2 — plugin tier needs defining for commands
- Hook merge is cumulative (append), not override — plugin hooks should append last
- All real plugin.json field names validated against interflux, interlock, clavain manifests

## Open Questions

- Should Interverse plugin commands have higher or lower precedence than project commands? (Lean: lower — project overrides plugin)
- Should we load ALL 53 plugins' MCP servers at startup, or lazy-connect on first tool use? (Assessment recommends lazy — validate during planning)
