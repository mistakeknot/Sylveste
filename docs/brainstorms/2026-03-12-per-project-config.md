# Brainstorm: Per-Project Config Directory (.skaffen/)

**Bead:** Sylveste-6i0.11

## Context

All 5 competitors (Claude Code, Codex, Gemini, OpenCode, Amp) have per-project configuration directories. Skaffen currently only reads from `~/.skaffen/` (user-global) and loads CLAUDE.md/AGENTS.md instruction files via `contextfiles.Load()`. There is no per-project config.

## Competitor Survey

| Agent | Directory | Config Format | Hierarchy Levels |
|-------|-----------|--------------|-----------------|
| Claude Code | `.claude/` | JSON | 5 (managed → CLI → local → shared → user) |
| Codex | `.codex/` | TOML | 5 (CLI → project → user → defaults) |
| Gemini | `.gemini/` | JSON | 3+ (system → project → user) |
| OpenCode | `.opencode/` | JSON/JSONC | 6 (remote → global → env → project → dir → inline) |
| Amp | `.amp/` | JSON | 4 (managed → project → legacy → user) |

**Common per-project config contents:** model routing, MCP server definitions, tool permissions, hooks, instruction files. All store in a dotdir at the project root.

## Current State (Skaffen)

**User-global `~/.skaffen/`:**
- `routing.json` — model routing, budget, phase overrides
- `plugins.toml` — MCP plugin definitions
- `sessions/` — session persistence (JSONL)
- `evidence/` — evidence emission (JSONL)

**`contextfiles.Load()`:** Walks from working dir to HOME, reads CLAUDE.md and AGENTS.md at each level. Read-only, no config merging.

**`.gitignore`:** Already ignores `.skaffen/` — designed for local-only config.

## Design Space

### A. What to put in per-project `.skaffen/`

**Tier 1 — MVP (this bead):**
1. `routing.json` — per-project model routing overrides
2. `plugins.toml` — per-project MCP plugin definitions
3. `AGENTS.md` — per-project instructions (already supported via contextfiles, but should also look in `.skaffen/`)

**Tier 2 — Future:**
4. `hooks.json` — per-project hook definitions
5. `permissions.json` — per-project tool approval rules
6. `skills/` — per-project skill definitions

### B. Config Hierarchy (3 levels)

1. **User global:** `~/.skaffen/` (lowest precedence)
2. **Per-project:** `.skaffen/` in project root (higher precedence)
3. **CLI flags:** `--model`, `--plugins`, etc. (highest precedence)

**Merging strategy:**
- `routing.json`: Per-project overrides user-global. CLI flags override both.
- `plugins.toml`: Per-project **merges with** user-global (both sets of plugins load).
- `AGENTS.md`: Per-project appends to contextfiles hierarchy (already works this way).

### C. Project Root Detection

How to find the per-project `.skaffen/`:
1. **Walk up from working dir** — first `.skaffen/` directory found (same as contextfiles)
2. **Git root** — `.skaffen/` at `git rev-parse --show-toplevel`
3. **Explicit flag** — `--config-dir /path/to/.skaffen`

Option 1 is simplest and matches contextfiles behavior. Option 2 is what most competitors do.

**Recommendation:** Use git root (option 2) with fallback to option 1. Git root is the natural project boundary.

### D. Trust Model

- **Codex approach:** Explicit trust — projects must be marked safe before loading config
- **Claude Code approach:** Implicit trust — auto-load, but security-sensitive settings require confirmation
- **Skaffen approach:** Implicit trust with warnings. Per-project routing.json and plugins.toml auto-load. No code execution from per-project config without trust evaluation.

### E. Shared vs Local

Should `.skaffen/` be committed to git?
- **CC:** `.claude/settings.json` committed, `.claude/settings.local.json` gitignored
- **Skaffen `.gitignore`:** Already ignores `.skaffen/`

**Recommendation:** Keep `.skaffen/` gitignored (local-only). Shared project instructions go in CLAUDE.md/AGENTS.md at project root (already supported). Per-project config is agent-specific and shouldn't be committed.

## Key Design Decisions

1. **Config format:** JSON (matches existing routing.json) — TOML for plugins (matches existing plugins.toml)
2. **Discovery:** Git root → walk up → explicit flag
3. **Merge strategy:** Per-project overrides user-global, CLI flags override both. Plugins merge.
4. **Trust:** Implicit (auto-load), matching existing contextfiles behavior
5. **Shared/local:** Local-only (gitignored), consistent with current .gitignore

## Implementation Sketch

### New: `internal/config/` package

```go
// config.go
type Config struct {
    Routing  *router.Config   // from routing.json (merged)
    Plugins  []mcp.PluginCfg  // from plugins.toml (merged)
    WorkDir  string           // resolved working directory
    ProjectDir string         // resolved project root (git root or .skaffen/ parent)
}

func Load(workDir string) (*Config, error) {
    projectDir := findProjectRoot(workDir)
    userDir := filepath.Join(os.Getenv("HOME"), ".skaffen")

    cfg := &Config{WorkDir: workDir, ProjectDir: projectDir}

    // Load user-global, then overlay per-project
    cfg.Routing = loadRouting(userDir, projectDir)
    cfg.Plugins = loadPlugins(userDir, projectDir)

    return cfg, nil
}

func findProjectRoot(startDir string) string {
    // Try git root first
    if root := gitRoot(startDir); root != "" {
        if dirExists(filepath.Join(root, ".skaffen")) {
            return root
        }
    }
    // Walk up looking for .skaffen/
    return walkUpForDir(startDir, ".skaffen")
}
```

### Changes to `cmd/skaffen/main.go`

Replace scattered `filepath.Join(os.Getenv("HOME"), ".skaffen", ...)` calls with unified config loading:

```go
cfg, err := config.Load(workDir)
// Use cfg.Routing instead of manual routing.json load
// Use cfg.Plugins instead of manual plugins.toml load
```

## Open Questions

1. Should per-project `.skaffen/sessions/` exist? (Probably not — sessions are user-scoped)
2. Should per-project `.skaffen/evidence/` exist? (Probably not — evidence is user-scoped)
3. Should we support `.skaffen/AGENTS.md` as an alternative to project-root AGENTS.md?
4. Should config changes at runtime (e.g., `/settings`) write back to per-project config?

## Risks

- **Minimal:** Feature is well-understood from 5 competitor implementations
- **Config merging bugs:** Edge cases in overlay logic — mitigated by keeping merge simple (override, not deep-merge)
- **Breaking change:** None — all existing `~/.skaffen/` paths continue to work as fallback
