# fd-masaq-component-patterns

**Task:** Analyze Chris Barber's 50 agent UI concepts against Masaq's existing component surface.
**Date:** 2026-03-12

---

## Masaq Existing Component Surface (Baseline)

| Package | Type | What it does |
|---|---|---|
| `viewport` | `tea.Model` | Scrollable content pane; AppendContent/SetContent; autoScroll; ANSI-safe truncation |
| `compact` | Stateless renderer | Tool-call summaries in compact/verbose mode |
| `diff` | Stateless renderer | Unified diff with Chroma syntax highlighting |
| `keys` | Keybinding registry | Shared key.Binding map (vim-opt-in) |
| `question` | `tea.Model` | Multi-choice prompts; emits SelectedMsg |
| `priompt` | Pure function | Priority-based prompt assembly within token budget |
| `markdown` | Stateless renderer | Glamour-backed markdown; streaming buffer |
| `theme` | Global config | SemanticColors (Primary/Secondary/Success/Warning/Error/Info/Muted/Bg*/Fg*/Border/Diff*); dark+light pairs |
| `settings` | `tea.Model` | Bool/enum settings list; emits ChangedMsg/DismissedMsg |

Dependencies available: bubbletea v1.3.4, bubbles v0.20.0, lipgloss v1.1.0, glamour, chroma, x/ansi.

---

## 1. Candidate New Components (5–8 recommendations)

### 1. `sparkline` — Time-series bar/block chart

**One-line:** Fixed-width ring buffer of float64 samples rendered as Unicode block characters (▁▂▃▄▅▆▇█) with optional peak/mean annotations.

**Covers:** #1 (tok/s waveform), #9 (smart progress with trend), #11 (ETA forecasts), #41 (Wrapped summary graphs), #21 (skill progress over time).

**Design sketch:**
```go
type Model struct {
    samples  []float64   // ring buffer, cap = width
    head     int
    width    int
    label    string
    maxVal   float64     // 0 = auto-scale
}
func (m *Model) Push(v float64)
func (m Model) View() string       // returns one-line sparkline
func (m Model) Mean() float64
func (m Model) Peak() float64
```
`tea.Tick` drives sample ingestion; no full `tea.Model` needed unless the sparkline is interactive.

---

### 2. `statusbar` — Multi-slot status strip

**One-line:** A single-row bar with N named slots (left/center/right aligned), each independently styled, designed for persistent top/bottom attachment to a viewport.

**Covers:** #2 (frame health/state color), #8 (compass on-track indicator), #11 (ETA), #37 (passive feature toggles), #24 (notification badge count).

**Design sketch:**
```go
type Slot struct {
    Label   string
    Value   string
    Style   lipgloss.Style   // caller supplies; theme helpers provided
}
type Model struct {
    Left, Center, Right []Slot
    Width int
}
func (m Model) View() string
```
Purely a renderer — no `Update` loop needed. Callers rebuild slots from their own state. The health-state color question (see §4) feeds directly into `Slot.Style`.

---

### 3. `breadcrumb` — Horizontal trail of labeled steps

**One-line:** Renders a left-to-right sequence of steps (completed / active / pending) using Unicode separators, supporting overflow truncation from the left.

**Covers:** #14 (agent breadcrumb trail), #7 (rearview mirror — last N completed steps), #38 (pattern → recipe steps), #15 (lens tab strip as a degenerate breadcrumb).

**Design sketch:**
```go
type StepState int
const (Active, Done, Pending StepState = iota...)
type Step struct { Label string; State StepState }
type Model struct {
    Steps []Step
    Width int
    Sep   string   // default " › "
}
func (m Model) View() string
```
Left-truncation: when Steps don't fit at Width, drop oldest Done steps first and prepend "…".

---

### 4. `tabbar` — Switchable view lens selector

**One-line:** A horizontal tab strip where one tab is active, navigable by left/right or 1–9 hotkeys, emitting a `TabChangedMsg`.

**Covers:** #15 (lens switching: convo/edits/files/cost/timeline/learnings/decisions), #30 (arrow key detail toggling between levels), #42 (side-by-side alternatives selector).

**Design sketch:**
```go
type Tab struct { Label string; Key string }
type TabChangedMsg struct { Index int; Label string }
type Model struct {
    tabs   []Tab
    active int
    width  int
}
func (m Model) Update(msg tea.Msg) (Model, tea.Cmd)
func (m Model) View() string
```
This is the most broadly reusable candidate: any multi-view layout in Skaffen or Autarch needs it.

---

### 5. `pane` — Side-by-side split layout

**One-line:** Divides terminal width into 2–N vertical panes (proportional or fixed), each rendering an independent string content block, with optional border between panes.

**Covers:** #42 (side-by-side alternatives), #47 (A/B split pane testing), #17 (parallel exploration pick), #22 (multi-path exploration), #46 (question UI with context panel).

**Design sketch:**
```go
type PaneSpec struct {
    Weight  int      // relative width (like flex-grow)
    Content string   // pre-rendered string
    Title   string   // optional header
}
func Render(totalWidth int, panes []PaneSpec) string
```
Stateless renderer — callers own which pane is "focused". Composable with `viewport` per pane.

---

### 6. `meter` — Bounded value gauge / progress bar

**One-line:** A single horizontal bar showing a value in [0, max] with a labelled percentage or raw value, supporting forecast overlay (filled + projected segments).

**Covers:** #9 (smart progress bars with forecasting), #11 (ETA as time-remaining segment), #21 (skill level progress), #8 (compass alignment as a ±offset meter), #49/#50 (leaderboard score bars).

**Design sketch:**
```go
type Model struct {
    Value, Max     float64
    Forecast       float64   // projected endpoint; 0 = no forecast
    Label          string
    Width          int
    ForecastStyle  lipgloss.Style
    FillStyle      lipgloss.Style
}
func (m Model) View() string  // one line: [████░░░···] 67%  ETA 4m
```
Distinct from `sparkline` (point-in-time vs time-series). No `Update` loop; caller pushes values.

---

### 7. `list` — Navigable item list with selection

**One-line:** A vertically scrollable list of labelled items with cursor, multi-select optional, filter-as-you-type support, emitting `ItemSelectedMsg` / `ItemActivatedMsg`.

**Covers:** #13 (task queue interface), #25 (next-work suggestions stream), #24 (notification queue), #27 (SRS memory review list), #40 (/treasures discoveries), #3 (slash-command familiarity, as an augmented list).

**Note:** `bubbles/list` exists in the dependency already. The question is whether Masaq should wrap it with theme integration and standard keybindings (via `keys`), or expose it raw. Recommendation: thin `masaq/list` wrapper that wires `theme.Current()` and `keys.NewDefault()` so consumers get a consistent look without boilerplate.

---

## 2. Viewport `AppendContent`/`autoScroll` Assessment for Waveform/Sparkline

**Verdict: viewport is insufficient for waveform rendering; a ring buffer is needed.**

Current `viewport` architecture:
- Stores content as `[]string` lines, unbounded growth.
- `AppendContent` merges partial lines, appends, optionally scrolls to end.
- Rendering is a slice window over `m.lines[offset : offset+height]`.

For a tok/s waveform (idea #1), the requirements diverge:
1. **Fixed width, rolling window** — a 60-column sparkline always shows the last 60 samples, not the last 60 lines. `viewport` would need to be told to drop old lines manually; there's no cap or ring mechanic.
2. **Float64 sample normalization** — viewport holds styled strings, not numeric samples. Normalizing all previous samples on every `Push` (to re-scale the chart) would require re-rendering all lines.
3. **Single-line render** — a waveform is 1 row tall, not a scrollable document. Embedding it in viewport adds scroll-offset machinery that does nothing.

The `sparkline` component (§1 above) should own a `[]float64` ring buffer of length == display width, with a `head` index for O(1) push. `AppendContent` on viewport is the right primitive for conversation logs; it is the wrong primitive for time-series data.

**Conclusion:** Build `masaq/sparkline` with its own ring buffer. Viewport remains unchanged and correct for its job.

---

## 3. Lipgloss-Native Ideas (No New Component)

These ideas map directly to lipgloss styling primitives or existing Masaq components with no new package needed.

### #2 — Terminal frame health-state color
`lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).BorderForeground(c.Error.Color())` — the frame border color is just a style attribute. A `statusbar` slot (§1.2) can also show state inline. Zero new component needed; see §4 for theme extension.

### #34 / #35 — Victory celebrations / Critical hits
Purely textual ASCII art + color burst rendered as a one-shot `lipgloss` string. Could be a helper function `masaq/celebrate.Render(kind CelebrationKind, width int) string` but this is 10 lines, not a component. Inline lipgloss with `c.Success` / `c.Warning` colors suffices.

### #37 — Passive feature toggles at bottom
This is exactly `masaq/settings` already. `TypeBool` entries rendered in a row instead of a column is a layout variant, achievable by calling `settings.View()` and reflowing, or by exposing a `HorizontalView()` method. No new component.

### #30 — Arrow key detail toggling
The `keys.Map` already has `Expand` and `Back` bindings. The host model tracks `detailLevel int` and switches between compact/verbose rendering by calling different formatters. The `compact.Formatter.SetVerbose()` method is exactly this. No new component.

### #23 / #28 — Auto-generated shortcuts with learning
The display layer is just `masaq/keys` augmented with a `Dynamic []key.Binding` field (or a separate slice the host populates). The learning/generation logic is agent-side, not a UI primitive. Display: one extra section in the help bar rendered with `lipgloss`. No new component.

### #14 (partial) — Breadcrumb as pure lipgloss
For ≤5 steps and fixed width, a breadcrumb is `strings.Join(labels, " › ")` with lipgloss color per step state. A full `masaq/breadcrumb` component (§1.3) is warranted only when overflow truncation and step-state transitions are needed. For simple trails, lipgloss inline is sufficient.

### #29 — Editable compaction rules
This is `masaq/settings` with `TypeEnum` entries for compaction strategy. Consumers add entries like `{Key: "compaction", Type: TypeEnum, Options: []string{"verbatim", "summary", "aggressive"}}`. No new component.

---

## 4. Theme System Assessment — SemanticColors vs Health-State Needs

**Verdict: SemanticColors is adequate for 2-state and 4-state health indicators but needs one new semantic role: `Active`.**

Current semantic roles and their health-state mapping:

| Use case | Existing color | Verdict |
|---|---|---|
| Healthy / running | `Success` (#9ece6a) | Good |
| Warning / slow | `Warning` (#e0af68) | Good |
| Error / failed | `Error` (#f7768e) | Good |
| Idle / paused | `Muted` (#565f89) | Adequate |
| In-progress / active | `Primary` (#7aa2f7) | Usable but semantically off |
| Information overlay | `Info` (#7dcfff) | Good |

The gap: there is no dedicated **`Active`** color for "currently executing" state (idea #2's blinking/pulsing frame for a running agent). Using `Primary` for both "this is Demarch blue" and "this agent is actively running" creates ambiguity. Recommendation:

```go
// Add to SemanticColors:
Active ColorPair  // in-progress / currently executing; distinct from Primary UI chrome
```

For TokyoNight: `Active: ColorPair{Dark: "#2ac3de", Light: "#188092"}` (the cyan, currently unused at semantic level).

Everything else in idea #2 (frame border color cycling through Idle/Active/Warning/Error) maps directly to existing colors. The `statusbar` component (§1.2) can expose a `StateStyle(s AgentState) lipgloss.Style` helper that selects from `SemanticColors`.

**No theme restructuring needed** — one field addition to `SemanticColors` and both `TokyoNight` and `Catppuccin` theme structs.

---

## 5. Animation/Timing Assessment — `tea.Tick` Sufficiency

**Verdict: `tea.Tick` is sufficient for all real-time update needs in this list. No additional animation framework is needed.**

The relevant ideas and their update rates:

| Idea | Update rate needed | `tea.Tick` verdict |
|---|---|---|
| #1 Tok/s waveform | ~1 Hz sample, 250ms re-render | Trivial — `tea.Tick(250ms, func(t time.Time) tea.Msg {...})` |
| #9 Smart progress | 1–5 Hz | Trivial |
| #11 ETA forecasts | 1 Hz | Trivial |
| #8 Compass drift | 2–5 Hz | Trivial |
| #34/#35 Celebrations | One-shot then auto-dismiss after 2s | `tea.Tick` once for dismiss |
| #18 Energy routing | Minutes-scale | Trivial |
| #19 Agent dashboard | 1–2 Hz heartbeat | Trivial |

The `tea.Tick` + `tea.Cmd` model is already idiomatic BubbleTea for periodic updates. The pattern is:

```go
func tickCmd() tea.Cmd {
    return tea.Tick(250*time.Millisecond, func(t time.Time) tea.Msg {
        return TickMsg{T: t}
    })
}
// In Update: case TickMsg → push sample, return tickCmd() to re-arm
```

**No animation framework required.** The one case where `tea.Tick` feels thin is a celebration burst (#34/#35) that wants a multi-frame animation (frame 0 → frame 1 → frame 2 → done). This is still `tea.Tick` but with a frame counter in model state. Standard BubbleTea pattern, no new primitive.

For the waveform specifically: `tea.Tick` at 1 Hz driving `sparkline.Push()` is correct. The sparkline ring buffer does not need to be driven faster than the underlying data source (token throughput stats, typically polled from agent state).

---

## 6. Non-Terminal Ideas and Their Terminal-Adjacent Equivalents

These ideas as described are GUI/mobile/hardware concepts. Each has a terminal-adjacent equivalent that Masaq could implement.

| # | Original concept | Non-terminal requirement | Terminal-adjacent equivalent |
|---|---|---|---|
| #4 | Desktop peripheral controller | Physical hardware; dedicated screen | `statusbar` with glanceable agent state; external `ssh`/`tmux` session readable at a glance |
| #16 | Mobile tap-approval UI | Touch/voice input, native mobile app | `question` component over an SSH-accessible agent endpoint; approval via single keypress |
| #26 | Click-drag permission boundaries | Mouse drag interaction | `settings` component with permission enum entries; arrow-key cycling through permission levels |
| #12 | Spatial overview of agents | 2D canvas / map layout | `pane` (§1.5) grid: N agents each in their own viewport tile; or a table renderer showing agent×attribute matrix |
| #32 | Coding agent as video game | Full game loop, sound effects, sprites | ANSI art + color burst (`celebrate`, §3) for pass/fail events; health-bar via `meter` (§1.6) showing test suite pass rate |
| #36 | Agent location/status map | Geographic or spatial canvas | Agent roster list using `list` (§1.7) with `statusbar`-style state badges; column = agent, row = current task |
| #41 | Wrapped summary (like Spotify Wrapped) | Rich graphical layout, animations | `sparkline` arrays + `meter` bars in a full-screen layout; purely textual but data-rich |
| #49/#50 | Company/cross-company leaderboards | Web dashboard, auth, data federation | `list` with score column + `meter` inline per row; data federation is backend concern, display is terminal-native |

The boundary to watch: #26 (drag boundaries) genuinely needs mouse-down-drag events. BubbleTea v1.3.4 exposes `tea.MouseMsg` with position — `tea.MouseLeft` button events are available. A drag handler is possible in pure BubbleTea (track mousedown position, compute delta on mousemove), but it's fiddly. The `settings` keyboard approach is more reliable cross-terminal.

---

## Summary Table

| Component | New / Existing | Ideas Covered | Priority |
|---|---|---|---|
| `sparkline` | New | 1, 9, 11, 21, 41 | High |
| `statusbar` | New | 2, 8, 11, 24, 37 | High |
| `tabbar` | New | 15, 30, 42 | High |
| `meter` | New | 9, 11, 21, 8, 49/50 | Medium |
| `pane` | New | 42, 47, 17, 22, 46 | Medium |
| `breadcrumb` | New | 14, 7, 38 | Medium |
| `list` (thin wrapper) | Thin wrap of `bubbles/list` | 13, 25, 24, 27, 40, 3 | Low (bubbles already there) |
| Theme `Active` field | Extend existing | 2, 19, 36 | Low-cost, high-value |

**Highest-leverage first:** `sparkline` → `statusbar` → `tabbar`. These three cover the most ideas and compose well with each other (a `statusbar` can embed a `sparkline` View string as a slot value, and a `tabbar` sits above a viewport).
