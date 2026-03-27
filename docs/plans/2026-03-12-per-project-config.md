# Plan: Per-Project Config Directory (.skaffen/)

**Bead:** Sylveste-6i0.11
**Stage:** plan-reviewed

## Overview

Add per-project `.skaffen/` directory support. Config hierarchy: user-global (`~/.skaffen/`) → per-project (`.skaffen/` at git root) → CLI flags. Unified config loading replaces scattered path construction in main.go.

## Review Findings Applied

- `RoutingPaths()` returns `[]string` (both user-global + per-project), not single path
- `Load()` returns `(*Config, error)`, not swallowing errors
- `MergeConfig` deep-copies maps to avoid aliasing base config
- `MergeConfig` initializes nil `ContextWindows` before writing
- `findProjectRoot` validates `.skaffen/` exists at git root before accepting
- `os.UserHomeDir()` instead of `os.Getenv("HOME")`
- Extract shared `initConfig()` helper in main.go to avoid duplication

## Tasks

### Task 1: Create `internal/config/` package — project root detection + config loading
**Files:** `internal/config/config.go`

```go
package config

import (
    "context"
    "os"
    "os/exec"
    "path/filepath"
    "strings"
    "time"
)

// Config holds resolved paths for user-global and per-project configuration.
type Config struct {
    userDir    string // ~/.skaffen (from os.UserHomeDir)
    projectDir string // project root containing .skaffen/, empty if none
    workDir    string // current working directory
}

// Load discovers user-global and per-project config directories.
// Returns error only if home directory cannot be resolved.
func Load(workDir string) (*Config, error) {
    home, err := os.UserHomeDir()
    if err != nil {
        return nil, fmt.Errorf("resolve home directory: %w", err)
    }
    return &Config{
        userDir:    filepath.Join(home, ".skaffen"),
        projectDir: findProjectRoot(workDir, home),
        workDir:    workDir,
    }, nil
}

// RoutingPaths returns routing config paths to load, ordered user-global first.
// Load both and merge with router.MergeConfig (user-global as base, per-project as overlay).
// Returns only existing paths.
func (c *Config) RoutingPaths() []string {
    var paths []string
    userPath := filepath.Join(c.userDir, "routing.json")
    if fileExists(userPath) {
        paths = append(paths, userPath)
    }
    if c.projectDir != "" {
        projPath := filepath.Join(c.projectDir, ".skaffen", "routing.json")
        if fileExists(projPath) {
            paths = append(paths, projPath)
        }
    }
    return paths
}

// PluginPaths returns plugin config paths to load (user-global + per-project).
// Both are loaded; per-project plugins merge with user-global.
func (c *Config) PluginPaths() []string {
    var paths []string
    userPath := filepath.Join(c.userDir, "plugins.toml")
    if fileExists(userPath) {
        paths = append(paths, userPath)
    }
    if c.projectDir != "" {
        projPath := filepath.Join(c.projectDir, ".skaffen", "plugins.toml")
        if fileExists(projPath) {
            paths = append(paths, projPath)
        }
    }
    return paths
}

// SessionDir returns the user-global sessions directory.
func (c *Config) SessionDir() string { return filepath.Join(c.userDir, "sessions") }

// EvidenceDir returns the user-global evidence directory.
func (c *Config) EvidenceDir() string { return filepath.Join(c.userDir, "evidence") }

// ProjectDir returns the project root (parent of .skaffen/), empty if none found.
func (c *Config) ProjectDir() string { return c.projectDir }

// findProjectRoot tries git root first (with timeout), then walks up.
// Only accepts git root if .skaffen/ exists there.
func findProjectRoot(startDir, homeDir string) string {
    // Try git root with 2s timeout
    if root := gitRoot(startDir); root != "" {
        if dirExists(filepath.Join(root, ".skaffen")) {
            return root
        }
    }
    // Walk up from startDir looking for .skaffen/ directory
    return walkUpForDir(startDir, homeDir, ".skaffen")
}

func gitRoot(dir string) string {
    ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
    defer cancel()
    cmd := exec.CommandContext(ctx, "git", "rev-parse", "--show-toplevel")
    cmd.Dir = dir
    out, err := cmd.Output()
    if err != nil {
        return ""
    }
    return strings.TrimSpace(string(out))
}

func walkUpForDir(startDir, stopDir, target string) string {
    dir := filepath.Clean(startDir)
    stopDir = filepath.Clean(stopDir)
    for {
        if dirExists(filepath.Join(dir, target)) {
            return dir
        }
        if dir == stopDir {
            break
        }
        parent := filepath.Dir(dir)
        if parent == dir {
            break
        }
        dir = parent
    }
    return ""
}

func fileExists(path string) bool {
    info, err := os.Stat(path)
    return err == nil && !info.IsDir()
}

func dirExists(path string) bool {
    info, err := os.Stat(path)
    return err == nil && info.IsDir()
}
```

### Task 2: Routing config merge logic
**Files:** `internal/router/config.go`

Add `MergeConfig` with deep-copied maps to avoid aliasing:

```go
// MergeConfig overlays project config onto base config.
// Returns a new Config — neither base nor project is modified.
func MergeConfig(base, project *Config) *Config {
    merged := &Config{
        Phases:         make(map[tool.Phase]string, len(base.Phases)+len(project.Phases)),
        ContextWindows: make(map[string]int, len(base.ContextWindows)+len(project.ContextWindows)),
    }
    // Deep-copy base maps
    for k, v := range base.Phases {
        merged.Phases[k] = v
    }
    for k, v := range base.ContextWindows {
        merged.ContextWindows[k] = v
    }
    // Deep-copy base pointers
    if base.Budget != nil {
        cp := *base.Budget
        merged.Budget = &cp
    }
    if base.Complexity != nil {
        cp := *base.Complexity
        merged.Complexity = &cp
    }
    // Overlay project values
    for phase, model := range project.Phases {
        merged.Phases[phase] = model
    }
    if project.Budget != nil {
        merged.Budget = project.Budget
    }
    if project.Complexity != nil {
        merged.Complexity = project.Complexity
    }
    for model, window := range project.ContextWindows {
        merged.ContextWindows[model] = window
    }
    return merged
}
```

### Task 3: Plugin config merge logic
**Files:** `internal/mcp/config.go`

```go
// MergePluginConfigs merges per-project plugins into user-global plugins.
// Per-project plugins with the same name override user-global entirely.
func MergePluginConfigs(base, project map[string]PluginConfig) map[string]PluginConfig {
    merged := make(map[string]PluginConfig, len(base)+len(project))
    for k, v := range base {
        merged[k] = v
    }
    for k, v := range project {
        merged[k] = v // per-project wins on name collision
    }
    return merged
}
```

### Task 4: Refactor main.go to use unified config
**Files:** `cmd/skaffen/main.go`

Extract shared `initConfig` helper used by both `runTUI()` and `runPrint()`:

```go
func initConfig() (*config.Config, *router.Config, map[string]mcp.PluginConfig, error) {
    workDir, err := os.Getwd()
    if err != nil {
        return nil, nil, nil, fmt.Errorf("getwd: %w", err)
    }
    cfg, err := config.Load(workDir)
    if err != nil {
        return nil, nil, nil, err
    }

    // Load and merge routing configs
    var routerCfg *router.Config
    routingPaths := cfg.RoutingPaths()
    if len(routingPaths) == 0 {
        routerCfg = &router.Config{Phases: make(map[tool.Phase]string)}
    } else {
        base, err := router.LoadConfig(routingPaths[0])
        if err != nil {
            return nil, nil, nil, fmt.Errorf("routing config: %w", err)
        }
        routerCfg = base
        if len(routingPaths) > 1 {
            project, err := router.LoadConfig(routingPaths[1])
            if err != nil {
                fmt.Fprintf(os.Stderr, "skaffen: warning: project routing config: %v\n", err)
            } else {
                routerCfg = router.MergeConfig(base, project)
            }
        }
    }

    // Load and merge plugin configs
    var pluginsCfg map[string]mcp.PluginConfig
    pluginPaths := cfg.PluginPaths()
    for _, p := range pluginPaths {
        pcfg, err := mcp.LoadConfig(p)
        if err != nil {
            fmt.Fprintf(os.Stderr, "skaffen: warning: plugins config %s: %v\n", p, err)
            continue
        }
        if pluginsCfg == nil {
            pluginsCfg = pcfg
        } else {
            pluginsCfg = mcp.MergePluginConfigs(pluginsCfg, pcfg)
        }
    }
    if pluginsCfg == nil {
        pluginsCfg = make(map[string]mcp.PluginConfig)
    }

    return cfg, routerCfg, pluginsCfg, nil
}
```

Then simplify `runTUI()` and `runPrint()` to call `initConfig()` and apply CLI flag overrides on top.

### Task 5: Tests
**Files:** `internal/config/config_test.go`, `internal/router/config_test.go`, `internal/mcp/config_test.go`

Config tests:
- `TestLoadNoProjectDir` — working dir with no `.skaffen/`, returns user-global only
- `TestLoadWithProjectDir` — working dir with `.skaffen/`, returns per-project paths
- `TestFindProjectRootWalkUp` — walk-up detection (primary, no git dependency)
- `TestFindProjectRootGitSkip` — git root detection (skip if git unavailable)
- `TestFindProjectRootGitNoSkaffen` — git root without `.skaffen/` falls through to walk-up
- `TestRoutingPaths` — both paths returned when both exist
- `TestRoutingPathsUserOnly` — only user-global when no per-project
- `TestPluginPaths` — both paths returned when both exist
- `TestSessionDirAlwaysUserGlobal` — sessions stay in ~/.skaffen
- `TestLoadBadHome` — error when home dir unresolvable

Router merge tests:
- `TestMergeConfigPhases` — per-project phase overrides, base phases preserved
- `TestMergeConfigBudget` — per-project budget replaces
- `TestMergeConfigEmpty` — empty project config is no-op
- `TestMergeConfigNilMaps` — nil base maps don't panic
- `TestMergeConfigNoAlias` — mutating merged config doesn't affect base
- `TestMergeConfigContextWindows` — per-project context windows merge

Plugin merge tests:
- `TestMergePluginConfigsBasic` — both sets included
- `TestMergePluginConfigsNameCollision` — per-project wins entirely

## Execution Order

1 → 2 → 3 → 4 → 5

## Verification

```bash
go test ./internal/config/... ./internal/router/... ./internal/mcp/... -count=1
go test ./... -count=1
go vet ./...
go build ./cmd/skaffen
```
