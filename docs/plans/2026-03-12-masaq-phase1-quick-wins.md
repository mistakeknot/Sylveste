**Bead:** Demarch-u2b

# Masaq Phase 1: Quick-Win Components

**Source:** Agent UI Explorations synthesis (`.claude/flux-drive-output/synthesis.md`)
**Scope:** 6 deliverables in masaq/ — zero Skaffen runtime changes required

## Context

Chris Barber's 50 agent UI explorations identified recurring patterns that map to reusable Masaq components. Phase 1 covers the components that are terminal-native, have no Skaffen dependencies, and unlock the most ideas across the roadmap.

## Deliverables

### 1. `theme.Active` color addition

Add an `Active ColorPair` field to `SemanticColors` for "currently executing" state (distinct from Primary). Both themes need the new field.

**File:** `masaq/theme/theme.go`

- Add `Active ColorPair` to `SemanticColors` struct (after `Info`)
- Tokyo Night: `{Dark: "#2ac3de", Light: "#007197"}` (cyan)
- Catppuccin: `{Dark: "#89dceb", Light: "#04a5e5"}` (sky)
- Update tests in `theme_test.go`

**Ideas unlocked:** #2, #19, #36

### 2. `sparkline` package — time-series sparkline renderer

New package `masaq/sparkline/` — a fixed-width ring-buffer sparkline using Unicode block characters (▁▂▃▄▅▆▇█).

**Files:**
- `masaq/sparkline/sparkline.go` — Model + View
- `masaq/sparkline/sparkline_test.go` — Tests

**API:**
```go
type Model struct { ... }
func New(width int) Model
func (m *Model) Push(value float64)        // Add sample to ring buffer
func (m *Model) SetBounds(min, max float64) // Manual scale (auto if unset)
func (m Model) View() string               // Render sparkline
func (m Model) Last() float64              // Most recent value
func (m Model) Avg() float64               // Running average
```

**Design:**
- Internal `[]float64` ring buffer of capacity `width`
- Auto-scaling: min/max derived from buffer contents unless manually set
- 8-level quantization to Unicode blocks: `▁▂▃▄▅▆▇█`
- Empty slots render as space
- Colorized via `theme.Current().Semantic()` — Success for normal, Warning for high, Error for critical (thresholds configurable)
- No tea.Model interface needed — this is a stateless renderer called from parent's View()

**Ideas unlocked:** #1 (tok/s waveform), #9 (progress trending), #11 (ETA visual), #21 (skill progress), #41 (wrapped summary)

### 3. `statusbar` package — multi-slot status strip

New package `masaq/statusbar/` — a single-row strip with named slots for persistent status display at top or bottom of screen.

**Files:**
- `masaq/statusbar/statusbar.go`
- `masaq/statusbar/statusbar_test.go`

**API:**
```go
type Slot struct {
    Label string
    Value string
    Color lipgloss.Color // optional override
}

type Model struct { ... }
func New(width int) Model
func (m *Model) SetSlots(slots []Slot)
func (m *Model) SetSlot(name, value string)
func (m Model) View() string
func (m Model) Height() int  // always 1
```

**Design:**
- Renders as `│ label: value │ label: value │ ...` in a single line
- Slots separated by `│` with padding
- Truncates from the right if total exceeds width
- Uses `theme.Current().Semantic().Border` for separators, `FgDim` for labels, `Fg` for values
- Color override per slot for health-state coloring (e.g., Active for running, Success for done, Error for failed)

**Ideas unlocked:** #2 (health state), #8 (compass), #11 (ETA), #24 (notification count), #37 (passive toggles)

### 4. `tabbar` package — lens/view switcher

New package `masaq/tabbar/` — horizontal tab selector with number-key hotkeys.

**Files:**
- `masaq/tabbar/tabbar.go`
- `masaq/tabbar/tabbar_test.go`

**API:**
```go
type Tab struct {
    Label string
    Key   string // single char shortcut (e.g., "1", "c" for convo)
}

type Model struct { ... }
func New(tabs []Tab) Model
func (m Model) Init() tea.Cmd
func (m Model) Update(msg tea.Msg) (Model, tea.Cmd)
func (m Model) View() string
func (m Model) Active() int
func (m *Model) SetActive(index int)

// Message emitted on tab change
type ChangedMsg struct { Index int }
```

**Design:**
- Renders as `[1 Convo] [2 Edits] [3 Files] [4 Cost] [5 Timeline]`
- Active tab highlighted with `Primary` color + underline
- Inactive tabs in `FgDim`
- Number keys 1-9 switch directly; left/right arrows cycle
- Emits `ChangedMsg` on tab change
- Tab labels truncated if total exceeds width

**Ideas unlocked:** #15 (lens switching), #30 (detail toggling), #42 (alternatives view)

### 5. `breadcrumb` package — horizontal step trail

New package `masaq/breadcrumb/` — left-to-right progress trail with overflow truncation.

**Files:**
- `masaq/breadcrumb/breadcrumb.go`
- `masaq/breadcrumb/breadcrumb_test.go`

**API:**
```go
type Step struct {
    Label  string
    Status Status // Pending, Active, Done
}

type Status int
const (
    Pending Status = iota
    Active
    Done
)

type Model struct { ... }
func New(width int) Model
func (m *Model) SetSteps(steps []Step)
func (m *Model) Push(label string)       // Add step as Active, previous becomes Done
func (m *Model) Complete()               // Mark current as Done
func (m Model) View() string
```

**Design:**
- Renders as `✓ init → ✓ plan → ● build → ○ review → ○ ship`
- Done steps: `Success` color + `✓`
- Active step: `Active` color + `●` (bold)
- Pending steps: `Muted` color + `○`
- Arrow separator `→` in `FgDim`
- Left-truncation with `…` when steps exceed width (most recent always visible)

**Ideas unlocked:** #14 (breadcrumb trail), #7 (rearview mirror), #38 (recipe steps)

### 6. `meter` package — progress gauge with forecast

New package `masaq/meter/` — bounded horizontal bar with optional forecast overlay.

**Files:**
- `masaq/meter/meter.go`
- `masaq/meter/meter_test.go`

**API:**
```go
type Model struct { ... }
func New(width int) Model
func (m *Model) SetValue(current, max float64)
func (m *Model) SetForecast(forecast float64) // optional: predicted completion point
func (m *Model) SetLabel(label string)
func (m Model) View() string
func (m Model) Percent() float64
```

**Design:**
- Renders as `[████████░░░░░░│░░░░░] 42% build`
- Filled portion: `Primary` color using `█`
- Forecast marker: `│` in `Info` color at predicted position
- Empty portion: `░` in `Muted`
- Percentage + optional label at right
- Handles edge cases: 0%, 100%, forecast > 100%, forecast < current

**Ideas unlocked:** #9 (smart progress), #11 (ETA), #21 (skill levels), #8 (compass gauge), #49 (leaderboard scores)

## Implementation Order

1. **theme.Active** — 15 min, unblocks color usage in all other components
2. **sparkline** — 1-2 hours, self-contained, most requested component
3. **meter** — 1 hour, simple bounded gauge
4. **statusbar** — 1 hour, slot-based layout
5. **breadcrumb** — 1 hour, step trail with truncation
6. **tabbar** — 1-2 hours, needs tea.Model interface + key handling

Total: ~1 day of focused implementation.

## Acceptance Criteria

- [x] All 6 components have `_test.go` files with meaningful coverage
- [x] All components use `theme.Current().Semantic()` for colors (no hardcoded colors)
- [x] All components handle width=0 and width=1 gracefully (no panics)
- [x] `go test ./...` passes in masaq/
- [x] No new dependencies added to go.mod (lipgloss + bubbletea already sufficient)
- [x] Each component has a godoc package comment explaining its purpose

## Out of Scope

- Integration with Skaffen or Autarch (that's Phase 2+)
- `splitpane` component (blocked on Skaffen ParallelRunner — Phase 4)
- `toast` notification overlay (Phase 4)
- Real data sources (components accept data via their API; callers wire data)
