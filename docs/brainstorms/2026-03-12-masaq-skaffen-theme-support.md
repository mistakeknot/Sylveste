# Brainstorm: How Should Masaq/Skaffen Support Themes?

**Date:** 2026-03-12
**Scope:** Masaq (shared component library) + Skaffen (TUI consumer)
**Status:** Brainstorm

## Current State

### What exists today
- **Single theme:** `TokyoNight` hardcoded as default in `masaq/theme/theme.go`
- **ColorPair struct:** Each semantic color has both `Dark` and `Light` hex values — but `Color()` always returns `Dark`
- **16 semantic slots:** Primary, Secondary, Success, Warning, Error, Info, Muted, Bg, BgDark, BgLight, Fg, FgDim, Border, DiffAdd, DiffRemove, DiffContext
- **Global singleton:** `theme.Current()` / `theme.SetCurrent(t)` — mutable global, no locking
- **10 consumers:** 4 in Masaq (compact, diff, question, theme_test), 6 in Skaffen TUI (app, prompt, status, filepicker, chat, phase)
- **All consumers pattern:** `c := theme.Current().Semantic()` then `c.Primary.Color()`, `c.Error.Color()`, etc.
- **Dependencies already present:** `termenv v0.16.0` and `charmbracelet/colorprofile` are in the go.sum via lipgloss

### What doesn't work
1. **Light mode is dead code.** `ColorPair.Light` values are defined but never used — `Color()` hardcodes `Dark`.
2. **No way to switch themes.** `SetCurrent()` exists but nothing calls it. No CLI flag, no config file, no env var.
3. **No terminal adaptation.** Can't detect whether the terminal is dark or light background and pick the right color variant.
4. **No user customization.** Users can't override colors or define their own themes.
5. **Not thread-safe.** `current` is a package-level `Theme` value — concurrent reads during `SetCurrent()` could race (unlikely in practice since TUI is single-threaded, but library-incorrect).

## Design Space

### Axis 1: How many built-in themes?

| Option | Description | Effort | Value |
|--------|-------------|--------|-------|
| A. Just fix dark/light toggle | Keep TokyoNight, use Light values on light terminals | Low | High — unlocks the existing dead code |
| B. 2-3 curated themes | TokyoNight + Catppuccin + one high-contrast | Medium | Medium — most users stick with defaults |
| C. Theme registry with community contributions | Structured TOML/YAML theme files, `skaffen themes list` | High | Low early — matters at scale |

**Recommendation: A now, B later.** The light-mode fix is the highest-value, lowest-effort change. A second theme (Catppuccin) adds proof that the system is extensible. Community registry is premature.

### Axis 2: How should light/dark mode detection work?

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| A. `termenv.HasDarkBackground()` | Query terminal for background color via OSC 11 | Automatic, no config needed | Slow on some terminals (~100ms), fails in CI/pipes, not all terminals support it |
| B. `COLORFGBG` env var | Check `$COLORFGBG` (format: `fg;bg`, bg > 6 = light) | Fast, no terminal query | Only set by some terminals (rxvt, xterm). Not reliable. |
| C. Explicit config / env var | `MASAQ_THEME=light` or config file | Always works, user control | Manual — user has to set it |
| D. `colorprofile` detection + fallback | Use charmbracelet/colorprofile for capability detection, assume dark, allow override | Fast, correct defaults | Still can't auto-detect light/dark |

**Recommendation: D + C.** Use `colorprofile` to detect color capability (TrueColor vs ANSI256 vs ANSI vs Ascii). Default to dark mode (vast majority of developer terminals). Allow override via `MASAQ_COLOR_MODE=light` env var or `--color-mode=light` CLI flag. Attempt `termenv.HasDarkBackground()` only if no explicit override and stdout is a TTY.

### Axis 3: How should the Color() method adapt?

Current: `func (cp ColorPair) Color() lipgloss.Color` — always returns `cp.Dark`.

| Option | Description | Impact |
|--------|-------------|--------|
| A. Add `ColorFor(mode string)` | New method, keep `Color()` as dark-only for compat | Zero breaking change, but consumers need to change |
| B. Make `Color()` mode-aware via theme context | `Color()` checks `theme.CurrentMode()` global | **Zero consumer changes** — all existing `c.Primary.Color()` calls auto-adapt |
| C. Split into `DarkColor()` / `LightColor()` | Explicit methods | Every consumer must choose which to call |

**Recommendation: B.** This is the key insight — if `Color()` checks a global mode flag, every existing consumer automatically gets light/dark support with **zero code changes**. The 10 call sites across Masaq and Skaffen all just work.

```go
// Before:
func (cp ColorPair) Color() lipgloss.Color {
    return lipgloss.Color(cp.Dark)
}

// After:
func (cp ColorPair) Color() lipgloss.Color {
    if currentMode == Light {
        return lipgloss.Color(cp.Light)
    }
    return lipgloss.Color(cp.Dark)
}
```

### Axis 4: Where does theme selection happen?

| Layer | Responsibility |
|-------|---------------|
| Masaq | Owns `Theme`, `ColorPair`, `SemanticColors`, built-in themes, `Current()`/`SetCurrent()`, mode detection |
| Skaffen | Reads config/env, calls `theme.SetCurrent()` and `theme.SetMode()` at startup |
| User | Sets env var, config file, or CLI flag |

This is clean separation — Masaq is a library that provides themes, Skaffen is an application that configures them.

### Axis 5: Color capability degradation

Not all terminals support TrueColor hex values. Current code uses `lipgloss.Color("#hex")` everywhere which lipgloss auto-degrades via its color profile detection. This already works — lipgloss maps hex to the closest ANSI256 or ANSI color automatically.

**No action needed here.** Lipgloss handles degradation. We just need to make sure our colors look reasonable when degraded to 256-color, which the Tokyo Night palette does.

### Axis 6: User-defined themes

| Option | Description | Effort |
|--------|-------------|--------|
| A. TOML theme files | `~/.config/skaffen/theme.toml` with hex overrides | Medium |
| B. CSS-like variables | `--primary: #7aa2f7` in a theme file | Medium (parsing) |
| C. Env var overrides | `MASAQ_PRIMARY=#ff0000` per-color | Low but ugly |
| D. Defer | Not needed for v1 | Zero |

**Recommendation: D for now, A for v0.2.** Custom themes are a nice-to-have. The infrastructure (Theme struct + SetCurrent) already supports it — we just need file loading. Defer to v0.2.

## Proposed Design

### Phase 1: Mode-aware Color() + dark/light detection (this sprint)

1. **Add `Mode` type and global** to `masaq/theme/`:
   ```go
   type Mode int
   const (
       Dark Mode = iota
       Light
   )
   var currentMode Mode = Dark
   func CurrentMode() Mode { return currentMode }
   func SetMode(m Mode) { currentMode = m }
   ```

2. **Make `ColorPair.Color()` mode-aware:**
   ```go
   func (cp ColorPair) Color() lipgloss.Color {
       if currentMode == Light {
           return lipgloss.Color(cp.Light)
       }
       return lipgloss.Color(cp.Dark)
   }
   ```

3. **Add `DetectMode()` function** using termenv:
   ```go
   func DetectMode() Mode {
       // 1. Check env override first
       if v := os.Getenv("MASAQ_COLOR_MODE"); v != "" {
           if strings.EqualFold(v, "light") { return Light }
           return Dark
       }
       // 2. Try terminal detection (only if TTY)
       if termenv.HasDarkBackground() {
           return Dark
       }
       return Light
   }
   ```

4. **Add second built-in theme** (Catppuccin Mocha/Latte) to prove extensibility:
   ```go
   var Catppuccin = Theme{
       Name: "Catppuccin",
       semantic: SemanticColors{
           Primary: ColorPair{Dark: "#89b4fa", Light: "#1e66f5"}, // Mocha blue / Latte blue
           // ... (Mocha for dark, Latte for light)
       },
   }
   ```

5. **Skaffen startup** calls `theme.SetMode(theme.DetectMode())` — one line in `main.go`.

6. **Optional CLI flags** in Skaffen: `--theme=catppuccin --color-mode=light`

### Phase 2: Theme file loading (future, v0.2)
- TOML theme files at `~/.config/skaffen/theme.toml`
- Override individual semantic colors
- `skaffen themes list` / `skaffen themes preview`

### Phase 3: High-contrast / accessibility (future)
- WCAG contrast ratio checking
- High-contrast theme variant
- Reduce-motion for spinner components (when we have them)

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| How many themes? | 2 (TokyoNight + Catppuccin) | Proves extensibility without over-engineering |
| Dark/light detection | Env override → termenv detection → default dark | Reliable + automatic |
| Color() API change? | Make it mode-aware (check global) | Zero breaking changes to 10 consumers |
| User custom themes? | Deferred to v0.2 | Infrastructure supports it, but no demand yet |
| Thread safety? | Not needed (single-threaded TUI, set once at startup) | Over-engineering for library that's only used in one app |
| Where to configure? | Skaffen main.go calls theme.SetMode() | Clean library/app separation |

## What This Unblocks

- **Light terminal users** can use Skaffen without unreadable colors
- **Theme switching** becomes possible (runtime or config)
- **Future Masaq consumers** (Autarch, other Sylveste tools) get themes for free
- **Community themes** have a clear extension point

## Risks

1. **termenv.HasDarkBackground() reliability** — May return wrong answer or hang on exotic terminals. Mitigated by env override taking precedence and short timeout.
2. **Color coherence** — Adding a second theme means maintaining two full color palettes. Catppuccin has well-documented official palettes, so this is manageable.
3. **Breaking existing visual appearance** — If someone already uses Skaffen, changing default behavior could surprise them. Dark mode default + existing TokyoNight colors means no change for the common case.

## Open Questions

1. Should `DetectMode()` cache the result or re-check on each call? (Probably cache at startup — terminal background doesn't change mid-session.)
2. Should Masaq expose a theme registry (`Register(name, theme)` + `Get(name)`) or just exported vars? (Exported vars are simpler and sufficient for 2-3 themes.)
3. Should we add a `theme.Available() []Theme` function for discoverability?
