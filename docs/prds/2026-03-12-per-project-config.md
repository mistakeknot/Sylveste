# PRD: Per-Project Config Directory (.skaffen/)

**Bead:** Demarch-6i0.11
**Status:** Draft

## Problem

Skaffen reads all configuration from `~/.skaffen/` (user-global). Users working across multiple projects cannot customize model routing, MCP plugins, or agent behavior per-project. All 5 competing agents (Claude Code, Codex, Gemini, OpenCode, Amp) have per-project config directories.

## Solution

Add per-project `.skaffen/` directory support with a 3-level config hierarchy: user-global → per-project → CLI flags. The per-project directory is discovered at the git root (or by walking up from the working directory).

## MVP Scope

1. **Config loading package** (`internal/config/`) — unified config loader that discovers and merges per-project and user-global configs
2. **Project root detection** — find `.skaffen/` at git root, with walk-up fallback
3. **Routing merge** — per-project `routing.json` overrides user-global
4. **Plugin merge** — per-project `plugins.toml` merges with user-global (both sets load)
5. **Main.go refactor** — replace scattered config paths with unified `config.Load()`

## Non-Goals (Future)

- Per-project hooks, permissions, skills (separate beads)
- Config write-back from `/settings`
- Shared (committed) vs local (gitignored) config split
- Trust model / explicit project trust marking
- Remote config sources

## Features

### F1: Project Root Discovery
Detect the project root by:
1. `git rev-parse --show-toplevel` → check if `.skaffen/` exists there
2. Walk up from working dir looking for `.skaffen/` directory
3. Fall back to user-global only (no per-project)

### F2: Unified Config Loading
New `internal/config/` package replaces manual path construction in main.go:
- Loads `routing.json` from user-global, overlays per-project
- Loads `plugins.toml` from user-global, merges per-project
- Exposes resolved paths for sessions and evidence (remain user-global)
- CLI flags (`--model`, `--plugins`, `--budget`) override both levels

### F3: Routing Merge
Per-project `routing.json` fields override user-global:
- `phases` map: per-project values override, user-global fills gaps
- `budget`: per-project replaces user-global entirely
- `default_model`: per-project overrides

### F4: Plugin Merge
Both user-global and per-project `plugins.toml` are loaded:
- All plugins from both files are registered
- Duplicate plugin names: per-project wins
- This allows global MCP servers (e.g., web search) plus project-specific ones

## Success Criteria

- `go test ./internal/config/... -count=1` passes
- `go test ./... -count=1` passes (no regressions)
- Running Skaffen with a `.skaffen/routing.json` in the current project uses per-project routing
- Running Skaffen without `.skaffen/` uses `~/.skaffen/` as before (backward compatible)
- `go vet ./...` clean
