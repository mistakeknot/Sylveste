# Plan: Masaq/Skaffen Theme Support

**PRD:** [2026-03-12-masaq-theme-support.md](../prds/2026-03-12-masaq-theme-support.md)
**Estimated tasks:** 7

## Tasks

### 1. Add Mode type and mode-aware Color() to masaq/theme
**File:** `masaq/theme/theme.go`
- [x] Add `Mode` type (int const: `Dark`, `Light`)
- [x] Add `currentMode` package var (default `Dark`)
- [x] Add `CurrentMode() Mode` and `SetMode(m Mode)` functions
- [x] Change `ColorPair.Color()` to check `currentMode` and return `Light` when appropriate
- [x] Add `String()` method on `Mode` for debugging

### 2. Add DetectMode() with env override
**File:** `masaq/theme/detect.go` (new)
- [x] Check `MASAQ_COLOR_MODE` env var first (case-insensitive: "light" → Light, else Dark)
- [x] Fall back to `termenv.HasDarkBackground()` when no env override
- [x] Import `os` and `github.com/muesli/termenv` (already in go.sum)
- [ ] Cache detection result in the function (call once at startup) — deferred: called once in main(), no need for internal caching

### 3. Add Catppuccin theme
**File:** `masaq/theme/catppuccin.go` (new)
- [x] Define `Catppuccin` var with Mocha (dark) and Latte (light) palettes
- [x] Map all 16 semantic slots to official Catppuccin colors

### 4. Add theme registry helpers
**File:** `masaq/theme/theme.go` (extend)
- [x] Add `Themes() []Theme` returning `[TokyoNight, Catppuccin]`
- [x] Add `ThemeByName(name string) (Theme, bool)` with case-insensitive lookup

### 5. Update theme tests
**File:** `masaq/theme/theme_test.go`
- [x] Test `Color()` returns Dark value when mode is Dark
- [x] Test `Color()` returns Light value when mode is Light
- [x] Test `SetMode()` / `CurrentMode()` round-trip
- [x] Test `DetectMode()` with `MASAQ_COLOR_MODE=light` env var
- [x] Test `DetectMode()` defaults to Dark with no env var
- [x] Test `Themes()` returns at least 2 themes
- [x] Test `ThemeByName()` found and not-found cases
- [x] Test Catppuccin has all required semantic colors

### 6. Integrate into Skaffen startup
**File:** `os/Skaffen/cmd/skaffen/main.go`
- [x] Call `theme.SetMode(theme.DetectMode())` early in startup
- [x] Add `--color-mode` and `--theme` CLI flags
- [x] Apply theme selection before TUI starts

### 7. Run tests and verify
- [x] `cd masaq && go test ./...` passes (81 tests, 9 packages)
- [x] `cd os/Skaffen && go test ./...` passes (355 tests, 14 packages)
- [ ] Manual test: `MASAQ_COLOR_MODE=light go run ./cmd/skaffen/` shows light colors
