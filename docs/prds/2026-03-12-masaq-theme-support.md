# PRD: Masaq/Skaffen Theme Support

**Date:** 2026-03-12
**Status:** Complete
**Brainstorm:** [2026-03-12-masaq-skaffen-theme-support.md](../brainstorms/2026-03-12-masaq-skaffen-theme-support.md)

## Problem

Masaq's `ColorPair` struct stores both dark and light mode hex values, but `Color()` always returns the dark variant. Light mode is dead code. Users on light terminals get unreadable colors. There's no way to switch themes or detect terminal background.

## Solution

Make `ColorPair.Color()` mode-aware by checking a global `currentMode` flag. Add terminal dark/light detection. Add a second built-in theme (Catppuccin) to prove extensibility. Zero breaking changes to existing consumers.

## Features

### F1: Mode-aware Color() [must-have]
- [x] Add `Mode` type (`Dark`/`Light`) and `currentMode` global to `masaq/theme/`
- [x] Add `CurrentMode()` / `SetMode()` functions
- [x] Make `ColorPair.Color()` return `Light` value when mode is `Light`
- [x] All 10 existing consumers auto-adapt with zero code changes

### F2: Terminal detection [must-have]
- [x] Add `DetectMode()` function using `termenv.HasDarkBackground()`
- [x] Check `MASAQ_COLOR_MODE` env override first (values: `dark`, `light`)
- [x] Default to `Dark` when detection fails (pipes, CI, unsupported terminals)
- [x] Cache result — called once at startup via `setupTheme()`

### F3: Skaffen integration [must-have]
- [x] Call `theme.SetMode(theme.DetectMode())` at Skaffen startup
- [x] Add `--color-mode=dark|light` CLI flag to override
- [x] Add `--theme=tokyonight|catppuccin` CLI flag

### F4: Second built-in theme — Catppuccin [nice-to-have]
- [x] Add `Catppuccin` theme (Mocha palette for dark, Latte palette for light)
- [x] Add `Themes()` function returning all available themes
- [x] Add `ThemeByName(name string) (Theme, bool)` for CLI lookup

## Non-goals (deferred to v0.2)
- User-defined theme files (TOML/YAML)
- Theme preview command (`skaffen themes preview`)
- High-contrast / accessibility themes
- Thread safety (TUI is single-threaded, set once at startup)
- Color capability degradation (lipgloss handles this automatically)

## Testing
- Unit tests for `Color()` in both modes
- Unit tests for `DetectMode()` with env var override
- Unit tests for `ThemeByName()` lookup
- Verify existing theme_test.go still passes (backward compat)
