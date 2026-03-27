---
artifact_type: plan
bead: Sylveste-6qb.7
stage: plan
---

# Plan: Interverse Plugin Compatibility Layer for Skaffen

**Date:** 2026-03-16
**Bead:** Sylveste-6qb.7
**PRD:** docs/prds/2026-03-16-interverse-plugin-compat.md
**Assessment:** docs/research/assess-interverse-plugin-compatibility.md

## Overview

Add auto-discovery and loading of Interverse plugins into Skaffen. ~865 lines across 12 files. 4 implementation phases, each independently testable and shippable.

## Phase 1: Plugin Discovery + MCP Auto-Registration

### Step 1.1: Plugin Discovery (`internal/mcp/discovery.go`)

Create `DiscoverPlugins(baseDir string) (map[string]PluginConfig, error)`:

1. `os.ReadDir(baseDir)` to list directories
2. For each, try `.claude-plugin/plugin.json` (check if exists)
3. Parse JSON into a struct matching the plugin.json schema:
   ```go
   type pluginManifest struct {
       Name       string                       `json:"name"`
       MCPServers map[string]ServerConfig       `json:"mcpServers"`
       Skills     []string                      `json:"skills"`
       Commands   []string                      `json:"commands"`
       Agents     []string                      `json:"agents"`
   }
   ```
4. For each `mcpServers` entry, resolve `${CLAUDE_PLUGIN_ROOT}` to the plugin directory
5. Return as `map[string]PluginConfig` (plugin name → config)
6. Skip plugins that fail to parse (log warning, continue)

**Test:** Create `internal/mcp/discovery_test.go` with testdata directory containing 2-3 fake plugin manifests. Verify discovery, CLAUDE_PLUGIN_ROOT resolution, and graceful skip on malformed JSON.

### Step 1.2: Config InterverseDir (`internal/config/config.go`)

Add `InterverseDir() string` method:
- Walk up from `workDir` looking for `interverse/` directory
- Also check if git root has `interverse/`
- Return empty string if not found

**Test:** Add to `config_test.go`.

### Step 1.3: Wire Discovery into main.go (`cmd/skaffen/main.go`)

After existing `LoadConfig()` and before `manager.LoadAll()`:
```go
if ivDir := cfg.InterverseDir(); ivDir != "" {
    discovered, err := mcp.DiscoverPlugins(ivDir)
    // Merge: explicit plugins.toml wins over discovered
    pluginCfg = mcp.MergePluginConfigs(discovered, pluginCfg)
}
```

**Verify:** Run `skaffen --mode print` and check that Interverse MCP tools appear in the tool registry.

## Phase 2: Skills + Command Loading

### Step 2.1: Skill Path Resolution (`internal/config/config.go`)

In `SkillDirs()`, add tier 5 after project-plugin tier:
```go
// Tier 5: Interverse plugin skills
if ivDir := c.InterverseDir(); ivDir != "" {
    entries, _ := os.ReadDir(ivDir)
    for _, e := range entries {
        if !e.IsDir() { continue }
        skillDir := filepath.Join(ivDir, e.Name(), "skills")
        if dirExists(skillDir) {
            dirs = append(dirs, skillDir)
        }
    }
}
```

No new files needed — skills format is identical.

**Test:** Add to `config_test.go` — verify Interverse skill dirs appear in `SkillDirs()`.

### Step 2.2: Command Markdown Loader (`internal/command/markdown.go`)

Create `LoadMarkdownDir(dir string, source string) []Def`:
1. Glob `dir/*.md`
2. For each: split YAML frontmatter from body
3. Parse frontmatter fields: `name`, `description`
4. Body becomes `Template`
5. Set `Type = TypeTemplate`, `Source = source`

**Test:** `internal/command/markdown_test.go` — parse a sample command .md, verify Def fields.

### Step 2.3: Wire Command Discovery

In config or main.go, scan `interverse/*/commands/*.md` and merge into command map at lowest precedence.

## Phase 3: Agent Definition Loading

### Step 3.1: Agent Markdown Loader (`internal/subagent/markdown.go`)

Create `LoadMarkdownAgents(pluginName string, pluginDir string, agentPaths []string) ([]SubagentType, error)`:
1. For each path in agentPaths, resolve relative to pluginDir
2. Parse YAML frontmatter: `name`, `description`, `model`
3. Body becomes `SystemPrompt`
4. Set defaults: `MaxTurns=25`, `ReadOnly=true`
5. Qualified name: `pluginName:agentName`

**Test:** `internal/subagent/markdown_test.go` — parse sample agent .md, verify SubagentType fields and qualified naming.

### Step 3.2: Register Plugin Agents

Add `RegisterFromPlugin(types []SubagentType)` to TypeRegistry. Plugin agents merge alongside built-in and custom TOML agents. Built-in names take precedence over plugin names.

## Phase 4: Hook Translation + Unified Loader

### Step 4.1: Hook Plugin Loader (`internal/hooks/plugin.go`)

Create `LoadPluginHooks(pluginDir string) (*Config, error)`:
1. Read `hooks/hooks.json` from plugin directory (or `.claude-plugin/hooks/hooks.json`)
2. Expand `${CLAUDE_PLUGIN_ROOT}` in all `command` fields
3. Return as `*Config` compatible with `MergeConfig`

**Test:** `internal/hooks/plugin_test.go` — verify CLAUDE_PLUGIN_ROOT expansion.

### Step 4.2: Unified Plugin Loader (`internal/plugin/loader.go`)

Create package `plugin` with:
```go
type Plugin struct {
    Name     string
    Dir      string
    MCP      map[string]mcp.ServerConfig
    Skills   []skill.Def
    Commands []command.Def
    Agents   []subagent.SubagentType
    Hooks    *hooks.Config
}

func Discover(interverseDir string) ([]Plugin, error)
func Inject(p Plugin, ...) error
```

`Discover` calls each capability's loader. `Inject` registers into all registries.

**Test:** `internal/plugin/loader_test.go` — full round-trip with testdata plugin.

### Step 4.3: Wire Unified Loader into main.go

Replace Phase 1's direct MCP wiring with the unified loader:
```go
if ivDir := cfg.InterverseDir(); ivDir != "" {
    plugins, _ := plugin.Discover(ivDir)
    for _, p := range plugins {
        plugin.Inject(p, reg, skills, cmds, subReg, hookCfg)
    }
}
```

## Verification

After all phases:
1. `go test ./... -count=1` — all tests pass (919+ existing + new)
2. `go vet ./...` — clean
3. `go build ./cmd/skaffen` — compiles
4. Manual: run `skaffen` in Sylveste monorepo, verify `/skills` shows Interverse skills, `/` autocomplete shows Interverse commands, MCP tools appear in registry

## File Summary

| File | Phase | Action | Lines |
|------|-------|--------|-------|
| `internal/mcp/discovery.go` | 1 | New | ~80 |
| `internal/mcp/discovery_test.go` | 1 | New | ~60 |
| `internal/config/config.go` | 1 | Modify | ~15 |
| `internal/config/config_test.go` | 1 | Modify | ~20 |
| `cmd/skaffen/main.go` | 1,4 | Modify | ~30 |
| `internal/command/markdown.go` | 2 | New | ~60 |
| `internal/command/markdown_test.go` | 2 | New | ~40 |
| `internal/subagent/markdown.go` | 3 | New | ~80 |
| `internal/subagent/markdown_test.go` | 3 | New | ~60 |
| `internal/hooks/plugin.go` | 4 | New | ~50 |
| `internal/hooks/plugin_test.go` | 4 | New | ~40 |
| `internal/plugin/loader.go` | 4 | New | ~200 |
| `internal/plugin/loader_test.go` | 4 | New | ~150 |
| **Total** | | | **~885** |
