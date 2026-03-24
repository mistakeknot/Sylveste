**Bead:** Demarch-4nl

# Autarch Masaq Adoption — Discovery & Analysis

## Context

Autarch is a Go TUI app using Bubble Tea + lipgloss with ~8,700 LOC in `pkg/tui/` and ~40+ view files. It has its own theme system (5 themes), custom layouts, and chat panel. It currently imports **zero Masaq packages** despite Masaq being the shared component library in the same monorepo.

## Discovery Findings

### High-Confidence Replacements (can do safely)

1. **masaq/tabbar → `internal/tui/tabs.go`** (60 lines)
   - Autarch has a minimal tab bar. Direct drop-in replacement.
   - Risk: 0%

2. **masaq/viewport → `pkg/tui/logpane.go`** (viewport.Model, lines 15-36)
   - Autarch uses `bubbles/viewport` directly. Masaq's viewport wraps it with extras (AppendContent, ScrollIndicator, ScrollTo).
   - Risk: 5% — need to verify logpane's scroll behavior matches

3. **masaq/breadcrumb → `internal/tui/breadcrumb.go`** (192 lines)
   - Autarch has a custom breadcrumb for onboarding. Masaq's breadcrumb has the same concept but different API.
   - Risk: 5% — needs adapter for OnboardingState coupling in `views/gurgeh_onboarding.go`

### Medium-Confidence Refactors

4. **masaq/spinner → `pkg/tui/chatpanel.go`** (spinner creation, lines 53-55)
   - Replace `bubbles/spinner` with `masaq/spinner` for themed frames.
   - Risk: 5%

5. **masaq/compact → tool call rendering** in chatpanel.go (lines 490+)
   - Wrap existing tool call formatting with Masaq's compact formatter.
   - Risk: 5%

6. **masaq/theme → `pkg/tui/theme/`** (475 lines + 286 semantic.go)
   - Autarch has 5 themes (Tokyo Night, Catppuccin, Nord, Gruvbox, Solarized) with its own semantic color system.
   - Strategy: Keep Autarch themes as primary. Wire Autarch's active theme colors → Masaq SemanticColors at init so Masaq components render in the correct palette.
   - Risk: 10% — theme switching at runtime needs bridge function

### Net-New Additions (no equivalent exists today)

- **masaq/minsize** — terminal-too-small guard
- **masaq/meter** — token usage visualization
- **masaq/sparkline** — trend visualization
- **masaq/statusbar** — unified footer (Autarch has no unified status bar)
- **masaq/question** — modal prompts
- **masaq/settings** — configuration UI
- **masaq/diff** — diff viewer

### Keep Unchanged

- `chatpanel.go` (924 lines) — too specialized for streaming chat
- `splitlayout.go`, `shelllayout.go`, `lane_pane.go` — custom layouts
- `command_picker.go` — fuzzy search specialized
- `tokens.go` — Autarch-specific token counting
- All custom layouts are composable with Masaq components

## Recommended Phasing

### Phase 1: Safe replacements (this bead)
- tabbar, viewport (logpane), spinner, minsize
- Theme bridge: wire Autarch theme → Masaq SemanticColors

### Phase 2: Breadcrumb + compact (future bead)
- Breadcrumb needs adapter for onboarding state
- Compact needs wrapper for Autarch's tool call format

### Phase 3: Net-new features (future beads)
- statusbar, meter, sparkline, question, settings

## Key Risk: Theme Bridge

Autarch has 5 themes with its own `SemanticColors` type. Masaq has a global `theme.Current()` with its own `SemanticColors`. The bridge needs to:
1. Read Autarch's active theme
2. Map Autarch semantic colors → Masaq semantic colors
3. Call `theme.SetCurrent()` with the mapped theme
4. Re-map on theme change events

This is the critical integration point — get this right and all Masaq components render correctly in any Autarch theme.

## Decision

Scope this bead to **Phase 1 only**: tabbar, viewport, spinner, minsize, and theme bridge. This validates the integration pattern without risking the more complex breadcrumb/compact work.
