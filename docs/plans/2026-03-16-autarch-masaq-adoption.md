---
artifact_type: plan
bead: Demarch-4nl
stage: design
---
# Autarch Masaq Adoption — Phase 1 Plan

**Bead:** Demarch-4nl
**Phase:** executing (as of 2026-03-16T06:24:20Z)
**Scope:** Theme bridge + 4 component integrations (tabbar, viewport, spinner, minsize)

## Tasks

### 1. Add Masaq dependency to Autarch go.mod
**File:** `apps/autarch/go.mod`
- [x] Add `github.com/mistakeknot/Masaq` to require block
- [x] Add replace directive: `github.com/mistakeknot/Masaq => ../../masaq`
- [x] Run `go mod tidy` to resolve

### 2. Create theme bridge: Autarch → Masaq
**File:** `apps/autarch/pkg/tui/theme/masaq_bridge.go` (new)
- [x] Create `SyncToMasaq()` function that maps Autarch's current theme to Masaq's `theme.SetCurrent()`
- [x] Map: Primary→Primary, Secondary→Secondary, Success→Success, Warning→Warning, Error→Error, Info→Info, Overlay→Muted, Base→Bg, Mantle→BgDark, Surface0→BgLight, Text→Fg, Subtext→FgDim, Surface2→Border, Sky→Active, Green→DiffAdd, Red→DiffRemove, Surface1→DiffContext
- [x] Call `SyncToMasaq()` from Autarch startup in cmd/autarch/main.go before tui.Run()
- [x] Added `NewTheme()` constructor to masaq/theme for external theme creation

### 3. Replace tabs.go with masaq/tabbar
**File:** `apps/autarch/internal/tui/tabs.go`
- [x] Replace `TabBar` struct with a thin wrapper around `tabbar.Model`
- [x] Preserve existing API: `NewTabBar([]string)`, `SetActive()`, `Active()`, `Next()`, `Prev()`, `View()`, `TabNames()`
- [x] The wrapper converts `[]string` to `[]tabbar.Tab` and delegates
- [x] No changes needed to unified_app.go (API preserved)

### 4. Replace logpane viewport with masaq/viewport
**File:** `apps/autarch/pkg/tui/logpane.go`
- [x] Replace `"github.com/charmbracelet/bubbles/viewport"` import with `"github.com/mistakeknot/Masaq/viewport"`
- [x] Replace `p.viewport.GotoBottom()` with `p.viewport.ScrollToBottom()`
- [x] Replace `p.viewport.GotoTop()` with `p.viewport.ScrollTo(0)`
- [x] Scroll behavior preserved (g/G keys, Update delegation)

### 5. Add masaq/spinner to chatpanel — DEFERRED
**Skipped:** masaq/spinner uses a different TickMsg type (includes ID field) that's incompatible with the chatpanel's existing `bubbles/spinner.TickMsg` matching. Replacing would require updating all message routing. Deferred to Phase 2.

### 6. Add masaq/minsize guard to unified_app
**File:** `apps/autarch/internal/tui/unified_app.go`
- [x] Import `"github.com/mistakeknot/Masaq/minsize"`
- [x] Add `sizeGuard minsize.Model` field to UnifiedApp
- [x] Initialize with `minsize.New(60, 15)` (Autarch needs more space than Skaffen)
- [x] Update `applyResize()` to call `sizeGuard.SetSize()`
- [x] Short-circuit `View()` when `sizeGuard.ShouldBlock()`

### 7. Run tests and verify
- [x] `cd apps/autarch && go test ./internal/tui/ ./pkg/tui/ ./pkg/tui/theme/` — 264 passed
- [x] `go vet` — pre-existing warnings only (loghandler.go lock copy)
- [x] `go build ./cmd/...` succeeds
- [x] Theme bridge: SyncToMasaq() maps all 17 semantic color fields

## Acceptance Criteria

- [x] Autarch imports at least 4 Masaq packages (tabbar, viewport, minsize, theme) — spinner deferred
- [x] Theme bridge syncs Autarch themes → Masaq SemanticColors
- [x] All existing tests pass (264/264 in changed packages)
- [x] No visual regression in tab bar rendering (API preserved)
- [x] LogPane scroll behavior unchanged (API mapped)
- [x] Minsize warning appears when terminal < 60x15
