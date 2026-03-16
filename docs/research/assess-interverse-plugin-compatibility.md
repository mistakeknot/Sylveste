# Assessment: Interverse Plugin Compatibility Layer for Skaffen

**Date:** 2026-03-16
**Bead:** Demarch-6qb.7
**Verdict:** adopt (phased)

## Context

Skaffen (Go agent at `os/Skaffen/`) needs to consume the 53+ Interverse plugins
(`interverse/*/`) that currently target Claude Code. The brainstorm (D14) scoped
v0.1 to "MCP + agents + shared discipline docs," covering ~80% of plugin value
with ~20% effort.

This assessment maps Interverse plugin capabilities to Skaffen's existing
infrastructure, identifies gaps, and designs the compatibility layer.

## 1. Plugin Anatomy

Every Interverse plugin lives in `interverse/<name>/.claude-plugin/plugin.json`.
The manifest declares up to five capability types:

| Capability | Example field | Count across ecosystem |
|------------|--------------|----------------------|
| MCP servers | `mcpServers` | 53 plugins, ~60 servers |
| Skills | `skills` (paths to SKILL.md dirs) | ~15 plugins |
| Commands | `commands` (paths to .md files) | ~20 plugins |
| Agents | `agents` (paths to agent .md files) | ~5 plugins (interflux: 17 agents) |
| Hooks | `hooks/hooks.json` (separate file) | 24 plugins |

### plugin.json shape (from interlock)

```json
{
  "name": "interlock",
  "version": "0.2.10",
  "mcpServers": {
    "interlock": {
      "type": "stdio",
      "command": "${CLAUDE_PLUGIN_ROOT}/bin/launch-mcp.sh",
      "args": [],
      "env": { "INTERMUTE_SOCKET": "/var/run/intermute.sock" }
    }
  },
  "skills": ["./skills/conflict-recovery", "./skills/coordination-protocol"],
  "commands": ["./commands/join.md", "./commands/leave.md"],
  "agents": []
}
```

### hooks.json shape (from interspect)

```json
{
  "hooks": {
    "SessionStart": [{ "matcher": "...", "hooks": [{ "type": "command", "command": "...", "timeout": 10 }] }],
    "PreToolUse":   [{ "matcher": "Edit", "hooks": [...] }],
    "PostToolUse":  [{ "matcher": "Task", "hooks": [...] }],
    "Stop":         [{ "hooks": [...] }]
  }
}
```

### Agent .md shape (from interflux fd-architecture)

```markdown
---
name: fd-architecture
description: "Flux-drive Architecture & Design reviewer..."
model: sonnet
---
You are a Flux-drive Architecture & Design Reviewer...
```

### Skill SKILL.md shape

```markdown
---
name: coordination-protocol
description: Use when multiple agents are editing...
---
## Overview
Interlock provides file-level coordination...
```

### Command .md shape

```markdown
---
name: interlock-status
description: Show multi-agent coordination status
---
# Multi-Agent Coordination Status
Gather and display coordination state from the interlock MCP server.
```

## 2. Current State: What Skaffen Already Handles

### MCP tools -- FULLY WORKING

`internal/mcp/` provides a complete MCP stdio client pipeline:

- `config.go`: Reads `plugins.toml`, parses `plugin.json`, resolves
  `${CLAUDE_PLUGIN_ROOT}`, merges env vars. Handles user-global + per-project
  merge via `MergePluginConfigs`.
- `client.go`: Spawns MCP server subprocess, JSON-RPC handshake via
  `modelcontextprotocol/go-sdk`, sandbox wrapping.
- `manager.go`: Lifecycle management with graceful degradation, auto-respawn
  (max 3 attempts), concurrent-safe handle map.
- `tool.go`: Wraps each MCP tool as a `tool.Tool` with qualified name
  `plugin_server_toolname`, delegates Execute to the live client.

**Gap:** Config requires manual `plugins.toml` with explicit paths. No
auto-discovery from `interverse/`.

### Skills -- FULLY WORKING (different format)

`internal/skill/` loads SKILL.md files with YAML frontmatter:

- `LoadDir(dir, source)`: Scans `dir/*/SKILL.md`, parses frontmatter.
- `LoadAll(dirs...)`: Merges from user/project/plugin tiers.
- `LoadBody(def)`: Lazy body loading.
- Fields: `name`, `description`, `user_invocable`, `triggers`, `args`, `model`.

**Gap:** Skaffen loads from `~/.skaffen/skills/` and `.skaffen/skills/`.
Interverse skills live at `interverse/<plugin>/skills/<skill>/SKILL.md`. The
format is identical -- the gap is only discovery path.

### Commands -- DIFFERENT FORMAT

`internal/command/` loads TOML files:

```toml
description = "Show status"
type = "template"
template = "Show coordination status..."
```

**Gap:** Interverse commands are Markdown with YAML frontmatter. Skaffen commands
are TOML with `template` or `script` fields. The formats are structurally
different, but the semantics overlap: both inject prompt text or run scripts.

### Subagents / Agents -- PARTIALLY WORKING

`internal/subagent/` provides agent type definitions and a concurrent runner:

- `TypeRegistry`: Built-in types (explore, general) + custom from `.skaffen/agents/*.toml`.
- `Runner`: Goroutine-per-task with semaphore, Intercore reservation, timeout.
- Agent TOML fields: `name`, `description`, `tools`, `system_prompt`,
  `max_turns`, `token_budget`, `read_only`, `model`, `timeout`.

**Gap:** Interverse agents are Markdown files with frontmatter (`name`,
`description`, `model`). The body IS the system prompt. Skaffen agents are TOML
with an explicit `system_prompt` field. Translation is straightforward: the
markdown body becomes `system_prompt`, frontmatter maps to TOML fields.

### Hooks -- FULLY WORKING (same format)

`internal/hooks/` is already JSON-compatible with Interverse hooks.json:

- Same event types: `SessionStart`, `PreToolUse`, `PostToolUse`.
- Same structure: `{ hooks: { Event: [{ matcher, hooks: [{ type, command, timeout }] }] } }`.
- Same execution model: JSON on stdin, JSON decision on stdout (PreToolUse).
- `LoadConfig` + `MergeConfig` already handle multi-source hooks.

**Gap:** Interverse hooks reference `${CLAUDE_PLUGIN_ROOT}` in command paths.
Skaffen's hook executor doesn't expand this variable. Also, Interverse has a
`Stop` event that Skaffen maps to shutdown but doesn't currently fire. Some
Interverse hooks use `"async": true` which Skaffen ignores.

## 3. Gap Analysis Summary

| Capability | Format match | Discovery gap | Translation needed | Effort |
|-----------|-------------|---------------|-------------------|--------|
| MCP servers | Exact | Yes (auto-discovery) | None | Small |
| Skills | Exact | Yes (path resolution) | None | Small |
| Commands | Different | Yes | Markdown→TOML shim | Medium |
| Agents | Different | Yes | Markdown→SubagentType | Medium |
| Hooks | 90% match | Yes | CLAUDE_PLUGIN_ROOT expansion, Stop/async | Small |

The dominant gap is **discovery**, not translation. Skaffen already speaks all
the right protocols -- it just doesn't know where to find Interverse plugins.

## 4. Integration Design

### 4.1 Plugin Discovery (`internal/mcp/discovery.go`, new file)

Auto-scan `interverse/` directory for plugin.json manifests:

```go
// DiscoverPlugins scans baseDir/*/. claude-plugin/plugin.json and returns
// a map of plugin name → resolved PluginConfig. Designed for the
// interverse/ directory but works with any layout following the convention.
func DiscoverPlugins(baseDir string) (map[string]PluginConfig, error)
```

Algorithm:
1. `os.ReadDir(baseDir)` to list plugin directories
2. For each, check `.claude-plugin/plugin.json`
3. Parse mcpServers, resolve `${CLAUDE_PLUGIN_ROOT}` to the plugin dir
4. Return merged config (explicit `plugins.toml` entries win over auto-discovered)

Wire into `config.go`: add `InterverseDir() string` that returns
`interverse/` relative to git root (if it exists). In `main.go`, merge
auto-discovered plugins under explicit ones.

### 4.2 Skill Bridge (extend `config.go` + `skill.LoadDir`)

No code changes to the skill package needed. Add Interverse skill dirs
to the config tier:

```go
// In config.go SkillDirs(), add after project plugin tier:
// Tier 5: Interverse plugin skills (auto-discovered)
for _, pluginDir := range discoverInterversePluginDirs(c.workDir) {
    skillDir := filepath.Join(pluginDir, "skills")
    if dirExists(skillDir) {
        dirs = append(dirs, skillDir)
    }
}
```

The skill SKILL.md format is identical between Interverse and Skaffen.

### 4.3 Agent Definition Loader (`internal/subagent/markdown.go`, new file)

Parse Interverse agent .md files into `SubagentType`:

```go
// LoadMarkdownAgents reads agent .md files listed in plugin.json "agents"
// field. Returns SubagentType definitions with the markdown body as
// SystemPrompt and frontmatter fields mapped to SubagentType fields.
func LoadMarkdownAgents(pluginDir string, agentPaths []string) ([]SubagentType, error)
```

Mapping:
- `name` (frontmatter) → `SubagentType.Name`
- `description` (frontmatter) → `SubagentType.Description`
- `model` (frontmatter) → `SubagentType.Model` (translate "sonnet"→actual model ID)
- Markdown body → `SubagentType.SystemPrompt`
- Default `MaxTurns`: 25, `ReadOnly`: true (review agents don't edit)

Wire into `TypeRegistry`: add `RegisterFromPlugin(types []SubagentType)` that
merges plugin agents alongside built-in and custom TOML agents. Plugin agents
get a qualified name: `pluginName:agentName` (e.g., `interflux:fd-architecture`).

### 4.4 Command Translation (`internal/command/markdown.go`, new file)

Parse Interverse command .md files into `command.Def`:

```go
// LoadMarkdownCommands reads command .md files listed in plugin.json
// "commands" field. Returns command.Def with the markdown body as
// the template text and frontmatter mapped to name/description.
func LoadMarkdownCommands(pluginDir string, cmdPaths []string) ([]Def, error)
```

Mapping:
- `name` (frontmatter) → `Def.Name`
- `description` (frontmatter) → `Def.Description`
- Markdown body → `Def.Template`
- `Def.Type` = `TypeTemplate` (commands are always prompt injection)
- `Def.Source` = `"interverse-plugin"`

### 4.5 Hook Translation (`internal/hooks/plugin.go`, new file)

Load Interverse `hooks/hooks.json` and merge into Skaffen hook config:

```go
// LoadPluginHooks reads hooks.json from an Interverse plugin directory,
// expands ${CLAUDE_PLUGIN_ROOT}, and returns a hooks.Config compatible
// with MergeConfig.
func LoadPluginHooks(pluginDir string) (*Config, error)
```

Key translations:
- Expand `${CLAUDE_PLUGIN_ROOT}` in all `command` fields
- Map `Stop` event → `SessionEnd` (or add `EventStop` to Skaffen's types.go)
- Ignore `"async": true` (Skaffen hooks are already non-blocking for advisory events)

### 4.6 Unified Plugin Loader (`internal/plugin/loader.go`, new package)

Orchestrate all five capability types from a single entry point:

```go
package plugin

// Plugin holds all resolved capabilities from a single Interverse plugin.
type Plugin struct {
    Name     string
    Dir      string
    MCP      map[string]mcp.ServerConfig
    Skills   []skill.Def
    Commands []command.Def
    Agents   []subagent.SubagentType
    Hooks    *hooks.Config
}

// Discover scans interverseDir for plugins and resolves all capabilities.
func Discover(interverseDir string) ([]Plugin, error)

// Inject registers a plugin's capabilities into the runtime registries.
func Inject(p Plugin, toolReg *tool.Registry, skillMap map[string]skill.Def,
    cmdMap map[string]command.Def, subReg *subagent.TypeRegistry,
    hookCfg *hooks.Config) error
```

In `main.go`, after existing config loading:

```go
// Auto-discover Interverse plugins
if interverseDir := cfg.InterverseDir(); interverseDir != "" {
    plugins, err := plugin.Discover(interverseDir)
    if err != nil {
        fmt.Fprintf(os.Stderr, "skaffen: warning: interverse: %v\n", err)
    }
    for _, p := range plugins {
        plugin.Inject(p, reg, skills, customCmds, subReg, hookCfg)
    }
}
```

## 5. Architecture Diagram

```
┌─────────────────────────────────────────────────────┐
│ main.go                                             │
│                                                     │
│  initConfig()                                       │
│    ├── config.Load()          existing               │
│    ├── plugins.toml           existing               │
│    └── plugin.Discover()      NEW: interverse scan   │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │ plugin.Inject() per plugin                    │  │
│  │  ├── mcp.Manager.LoadAll()     existing       │  │
│  │  ├── skill map merge           existing logic │  │
│  │  ├── command map merge         NEW: md loader │  │
│  │  ├── subagent.TypeRegistry     NEW: md loader │  │
│  │  └── hooks.MergeConfig()       existing       │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  Agent.Run() → tools from registry (MCP + built-in) │
│  TUI.Run()   → skills + commands from merged maps   │
│  Hooks.Exec  → merged hook config                   │
│  Subagent    → TypeRegistry (built-in + plugin)     │
└─────────────────────────────────────────────────────┘
```

## 6. File Plan

| File | Action | Lines est. |
|------|--------|-----------|
| `internal/plugin/loader.go` | New: Discover + Inject | ~200 |
| `internal/plugin/loader_test.go` | New: tests | ~150 |
| `internal/mcp/discovery.go` | New: DiscoverPlugins | ~80 |
| `internal/mcp/discovery_test.go` | New: tests | ~60 |
| `internal/subagent/markdown.go` | New: LoadMarkdownAgents | ~80 |
| `internal/subagent/markdown_test.go` | New: tests | ~60 |
| `internal/command/markdown.go` | New: LoadMarkdownCommands | ~60 |
| `internal/command/markdown_test.go` | New: tests | ~40 |
| `internal/hooks/plugin.go` | New: LoadPluginHooks + CLAUDE_PLUGIN_ROOT | ~50 |
| `internal/hooks/plugin_test.go` | New: tests | ~40 |
| `internal/config/config.go` | Modify: add InterverseDir() | ~15 |
| `cmd/skaffen/main.go` | Modify: wire plugin.Discover + Inject | ~30 |
| **Total** | | **~865** |

## 7. Effort Estimate

| Phase | Work | Estimate |
|-------|------|----------|
| Phase 1: Auto-discovery + MCP | discovery.go + config wiring | 4 hours |
| Phase 2: Skills + Commands | Path resolution + markdown loader | 3 hours |
| Phase 3: Agent definitions | Markdown→SubagentType + registry | 4 hours |
| Phase 4: Hook translation | CLAUDE_PLUGIN_ROOT + Stop event | 2 hours |
| Phase 5: Unified loader + main wiring | plugin package + integration | 3 hours |
| Phase 6: Testing | Unit + integration tests | 4 hours |
| **Total** | | **~20 hours (2.5 days)** |

## 8. Phased Rollout

### Phase 1: MCP Auto-Discovery (immediate, highest value)

Implement `mcp/discovery.go` and `config.InterverseDir()`. This gives Skaffen
access to all 53+ plugin MCP servers without manual plugins.toml entries.
~80% of the D14 value since most plugins are MCP-server-only.

### Phase 2: Skills + Commands (next sprint)

Wire Interverse skill and command directories into config tiers. Skills require
zero translation. Commands need the markdown→Def loader.

### Phase 3: Agent Definitions (after phase 2)

The markdown→SubagentType loader. Primarily benefits interflux (17 agents) and
any future plugins that define agents. Enables Skaffen to dispatch interflux
review/research agents via its existing subagent runner.

### Phase 4: Hook Translation (deferred)

Lowest priority because Skaffen's OODARC phases have different hook boundaries
than Claude Code. Many Interverse hooks are Claude-Code-specific (e.g.,
`Stop` event, Claude session ID handling). Load what's compatible, skip what
isn't, log warnings.

## 9. Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| Plugin MCP servers may depend on Claude-specific env vars (CLAUDE_SESSION_ID) | Map to Skaffen equivalents (SKAFFEN_SESSION_ID) during env expansion |
| Some hooks reference Claude Code internals | Skip with warning; hooks are advisory |
| Agent prompts may assume Claude Code's tool names | Qualify tool names with plugin prefix; model handles different names |
| Performance: loading 53 MCP servers at startup | Lazy initialization -- discover all, connect on first tool use |
| Interverse plugins have independent git repos | Discovery scans filesystem, not git; works regardless of repo structure |

## 10. Verdict

**Adopt (phased).** The gap is predominantly discovery, not protocol. Skaffen
already has a production MCP client, a compatible hook system, and an identical
skill format. The total new code is ~865 lines across 6 new files and 2 modified
files. Phase 1 alone (MCP auto-discovery, 4 hours) unlocks 80% of plugin value.

The D14 brainstorm decision was correct: MCP + agents + shared docs covers the
80/20 split. Hook translation is genuinely lower priority because Skaffen's
OODARC phases don't map 1:1 to Claude Code's lifecycle events.

Full compatibility (translating all 24 hook-bearing plugins' lifecycle
assumptions) is a separate, larger effort (the brainstorm's "200-400 hours"
estimate). That should be evaluated after v0.2 based on which hooks actually
matter in practice.
