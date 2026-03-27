# Terminal Feasibility Analysis: Chris Barber's 50 Agent UI Concepts

**Evaluator:** fd-terminal-feasibility
**Date:** 2026-03-12
**Rendering stack:** Masaq / bubbletea v1.3.4 / lipgloss v1.1.0 / glamour / bubbles v0.20.0
**Color system:** SemanticColors (15 roles, dual dark/light mode, hex → lipgloss.Color)
**Input system:** keyboard-only by default; mouse wheel supported via tea.MouseMsg (scroll only, no click coordinates)

---

## Terminal Rendering Constraints — The Hard Floor

Before the tier list, these constraints are absolute. They cannot be worked around without leaving the terminal:

1. **No spatial canvas.** There is no pixel grid. The only layout primitive is rows × columns of character cells. lipgloss columns (side-by-side with `lipgloss.JoinHorizontal`) exist but require knowing the terminal width at render time and cannot be resized by dragging.

2. **No mouse drag or click-to-position.** bubbletea's `tea.MouseMsg` provides `MouseWheelUp`/`MouseWheelDown` only (already in masaq/viewport). Click coordinates (`MouseLeft`, `MouseRight`, etc.) require `tea.WithMouseCellMotion()` or `tea.WithMouseAllMotion()` — available in bubbletea but unused in masaq. Even with click support enabled, drag-to-resize borders is a fundamentally graphical metaphor.

3. **No audio.** Terminal cannot produce waveform sound. Visual waveform is possible; audio is not.

4. **No hardware sensors.** Battery level, accelerometer, haptics, GPS — none are accessible from a terminal process in a platform-portable way.

5. **No touch.** Mobile tap zones, swipe gestures, pinch-zoom — inapplicable in a terminal.

6. **Color depth is 256 or 24-bit depending on terminal emulator.** Masaq uses hex colors via lipgloss which falls back gracefully. The SemanticColors palette has 15 named roles — sufficient for any reasonable state encoding (success/warning/error + primary/secondary + muted tiers).

7. **Animation is polling-based.** `tea.Tick(d, fn)` drives all animation. At 100ms intervals you get 10fps — adequate for sparklines and progress; inadequate for smooth video-style motion.

8. **Column budget on a standard 80-col terminal:** Each side-by-side pane costs column width + border (1–2 chars). Three panes at 80 cols = ~25 cols each. Readable minimum is ~20 cols.

---

## Tier Definitions

- **Terminal-native:** Fully expressible today using existing masaq components (viewport, question, settings, compact, diff, markdown, theme, keys).
- **Terminal-equivalent:** Requires a new masaq component but stays within pure bubbletea/lipgloss — no external dependencies, no graphical UI.
- **Terminal-adjacent:** Achievable in a terminal session but requires tmux (pane splits, session titles), OSC escape sequences (desktop notifications, hyperlinks), or a side process. Not pure bubbletea.
- **Out of scope:** Requires graphical UI, hardware access, mobile platform, or audio.

---

## The 50 Concepts — Feasibility Tier List

### 1. Waveform tok/s
**Tier: Terminal-native**

Unicode block elements `▁▂▃▄▅▆▇█` (U+2581–U+2588) form a 8-level sparkline. A 20-char wide waveform shows ~20 time buckets. `tea.Tick` at 200ms provides adequate resolution for tok/s display. Render a fixed-width string of block characters colored with `theme.Primary`. No new component needed — this is a single `View()` function.

**Specific proposal:**
```
tok/s  ▁▂▄▆▇█▇▅▃▂▁▂▄▅▆▇  312 t/s
```
Color: `SemanticColors.Info` for the bars; `SemanticColors.Muted` for the label. Width budget: 30 chars max. Animated via `tea.Tick(200*time.Millisecond, ...)` updating a ring buffer of recent samples.

---

### 2. Health/state frame colors
**Tier: Terminal-native**

lipgloss border styles (`lipgloss.RoundedBorder()`, `lipgloss.NormalBorder()`) accept foreground colors. Map agent health states to SemanticColors: `Success` (healthy), `Warning` (degraded), `Error` (failed), `Muted` (idle), `Info` (active). Already within palette. Zero new primitives needed.

---

### 3. Slash command familiarity
**Tier: Terminal-native**

A `\` or `/` prefix triggers command completion inline. The `question` package already renders a navigable option list. Wire a filtered list that narrows as the user types. Standard bubbletea text input (`bubbles/textinput`) + a filtered `question.Model` variant handles this cleanly.

---

### 4. Desktop peripheral
**Tier: Out of scope**

Concept involves physical hardware (gamepad, drawing tablet, macro pad, stream deck, or similar peripheral). Terminal processes receive keyboard events from stdin — they cannot enumerate or communicate with HID devices, USB peripherals, or Bluetooth accessories in a platform-portable way. A system daemon wrapping the peripheral could translate inputs to keystrokes, but that is an OS-level integration, not a terminal UI feature.

**Hard constraint:** No HID/USB API exists in bubbletea or any pure-Go terminal library.

---

### 5. Game-style controls (WASD/vim navigation)
**Tier: Terminal-native**

`masaq/keys` already has `WithVim()` adding `j/k/g/G`. Extending to `w/a/s/d` for directional navigation in a multi-pane layout is a trivial `key.NewBinding` addition. No new component needed.

---

### 6. Codebase visit frequency (heatmap)
**Tier: Terminal-equivalent**

A file tree with frequency-based coloring: high-visit files in `SemanticColors.Warning` or `SemanticColors.Error`, low-visit in `SemanticColors.Muted`. Intensity can use the 8-step block scale or simply 3 color tiers (cold/warm/hot). The `bubbles/list` component or a custom tree renderer handles the list. Needs a new `heatmap` or `filetree` masaq component, but purely within lipgloss + bubbletea.

---

### 7. Rearview mirror (recent actions log)
**Tier: Terminal-native**

This is exactly what `masaq/viewport` does — a scrollable ANSI-aware log with auto-scroll. Recent actions are appended via `AppendContent`. Already built.

---

### 8. Compass on/off track (direction indicator)
**Tier: Terminal-equivalent**

A text-art compass or direction meter: `◀◀ off-track` / `▶ on-track` / `▲ ahead of plan`. A simple status bar rendered in `SemanticColors.Success` or `SemanticColors.Warning` based on ETA delta. `tea.Tick` at 1s updates the indicator. The concept is a labeled status widget — no graphical compass needed. A 4-char Unicode arrow (`←↑→↓` or `◄▲►▼`) with a colored label is sufficient.

---

### 9. Smart progress bars
**Tier: Terminal-native**

`bubbles/progress` provides animated progress bars with lipgloss styling. Smart bars (that slow down or speed up) just require adjusting the increment value on each `tea.Tick`. SemanticColors maps directly to the bar's gradient colors. Already in the dependency tree.

---

### 10. Central task dispatch
**Tier: Terminal-equivalent**

A command palette or task router: a text input field + filtered list of available tasks/agents. The `question` package handles selection; a `bubbles/textinput` handles filtering. Needs composition into a "command palette" masaq component — achievable within bubbletea.

---

### 11. ETA forecasts
**Tier: Terminal-native**

Text rendering: `ETA ~4m32s (↓ from 6m)` colored with SemanticColors. Updated on `tea.Tick`. No graphical element required. The trend arrow (`↑↓→`) is Unicode. Full terminal-native.

---

### 12. Spatial agent overview (2D canvas/map)
**Tier: Out of scope** (as spatial canvas) / **Terminal-equivalent** (as structured list)

If "spatial" means a 2D canvas where agents have (x,y) coordinates on a draggable plane: out of scope. Terminal cells are not a pixel grid; you cannot freely position elements at arbitrary coordinates without re-rendering the entire frame, and there is no drag primitive.

**Keyboard-native equivalent:** A structured list or table showing agents with their current task, status color, and relationship (parent/child) as indentation. `lipgloss.JoinHorizontal` creates columns: `[Agent Name] [Status] [Current Task] [ETA]`. Navigate with `↑↓`, expand with `Enter`. This captures the overview intent without requiring spatial metaphor.

---

### 13. Task queue
**Tier: Terminal-native**

A scrollable ordered list with priority indicators. `bubbles/list` or `masaq/question` handles this. Status colors via SemanticColors. Already composable from existing primitives.

---

### 14. Breadcrumb trail
**Tier: Terminal-native**

A single line: `root > module > function > current` rendered with `SemanticColors.Muted` separators and `SemanticColors.Primary` for the current crumb. Static text updated on navigation events. Zero new components needed.

---

### 15. Lens switching
**Tier: Terminal-native**

Tab-style switching: `[Overview] [Detail] [Diff] [Log]` rendered as a row with the active tab highlighted via `SemanticColors.Primary` + bold. Key `Tab`/`Shift+Tab` cycles lenses. Already a standard bubbletea pattern. Lens labels fit in a single header row.

---

### 16. Mobile tap UI
**Tier: Out of scope**

Large tap targets (44px+), swipe gestures, touch scroll, pinch-zoom — all require a touch screen with a native mobile UI framework (iOS UIKit, Android Views, Flutter, React Native). A terminal running on a mobile device still only receives keyboard input from a connected keyboard or software keyboard. There is no touch event API in bubbletea.

**Hard constraint:** `tea.MouseMsg` has no touch event types. Even if bubbletea is extended, terminal emulators on mobile do not forward touch coordinates as terminal escape sequences (no standardized protocol exists).

---

### 17. Parallel exploration (side-by-side branches)
**Tier: Terminal-adjacent**

Two agent runs side-by-side requires either: (a) two lipgloss columns within one bubbletea program, or (b) two separate terminal panes. Option (a) works if both are submodels of a single program — `lipgloss.JoinHorizontal(lipgloss.Top, leftView, rightView)` at 80 cols gives ~38 chars per pane (2 borders), readable but cramped. Option (b) needs tmux split-pane.

If both agents are submodels of one bubbletea app: **terminal-equivalent**. If agents are independent processes: **terminal-adjacent** (requires tmux).

---

### 18. Energy-aware routing
**Tier: Out of scope**

Routing based on battery level, CPU thermal state, or power mode requires reading `/sys/class/power_supply/` (Linux) or `pmset` (macOS) system interfaces. This is a backend/routing logic concern, not a UI concern. The UI can *display* a power indicator (terminal-native), but routing decisions based on hardware power state are outside the terminal UI layer entirely.

---

### 19. Agent dashboard
**Tier: Terminal-equivalent**

A multi-section layout: header (agent name + status), body (current task + log viewport), footer (key hints). This is a composition of existing masaq components: `compact` for tool calls, `viewport` for logs, lipgloss borders for panels. Needs a `dashboard` layout component that wires them together — achievable within bubbletea.

---

### 20. Preference learning (auto-infer user preferences)
**Tier: Terminal-adjacent**

The *display* of learned preferences (e.g., "I've noticed you prefer X — confirm?") is terminal-native via the `question` model. The *learning* itself (behavior tracking, statistical inference) is backend logic. The UI surface is a confirmation prompt, which masaq already supports. Mark as terminal-adjacent only because the learning pipeline requires persistent state outside the TUI process.

---

### 21. Agent skill tracking
**Tier: Terminal-equivalent**

A table or list: `[Skill Name] [Level ████░░] [Uses]`. Progress bars for level visualization via `bubbles/progress`. A new `skill-tracker` masaq component that renders a table of skills with bar charts. Purely within bubbletea/lipgloss.

---

### 22. Multi-path pick (choose between agent strategies)
**Tier: Terminal-native**

This is precisely what `masaq/question` implements — a navigable list of labeled options with descriptions. Navigate `↑↓`, confirm `Enter`, or press digit shortcut `1–9`. Already built.

---

### 23. Auto shortcuts (keyboard shortcuts that appear based on context)
**Tier: Terminal-native**

A context-sensitive footer/statusbar line showing available keys: `[y] approve [n] reject [d] detail [?] help`. Updated by the host model based on current state. Pure text rendering; uses SemanticColors for key labels. Already a standard bubbletea pattern (see `bubbles/help`).

---

### 24. Notification queue
**Tier: Terminal-equivalent**

An inline notification banner or toast: a bordered box appearing at top/bottom of screen for N seconds, then dismissed. Implemented as a masaq component with `tea.Tick` for auto-dismiss. Pure bubbletea. No new dependencies needed.

---

### 25. Next work suggestions
**Tier: Terminal-native**

A list of suggested next tasks rendered after the current task completes. The `question` model handles selection. If suggestions are just displayed (no interaction), the `compact` formatter or a simple styled text block suffices. Terminal-native.

---

### 26. Drag permission levels (drag a slider to set permission)
**Tier: Out of scope** (as drag) / **Terminal-equivalent** (as keyboard slider)

Dragging a slider requires click-and-drag with mouse coordinates — not supported in masaq's current input model. `tea.MouseMsg` only provides wheel events.

**Keyboard-native equivalent:** `bubbles/progress` used as a display, with `←/→` keys adjusting the level in steps. `[Read-only ◀──●───── Full-write]`. The `settings` package already has `TypeEnum` cycling — the same pattern applies to a permission level enum. Fully achievable as a keyboard-operated control.

---

### 27. SRS memory review (spaced repetition flashcards)
**Tier: Terminal-equivalent**

A flashcard display: front text → key press → reveal back text → rate 1–4. This is a question/reveal/rating flow. `masaq/question` handles the rating step. A `srs-review` component showing front/back panels and a 4-option rating row is buildable within bubbletea. Purely terminal-native once the component exists.

---

### 28. Auto shortcuts + learning (shortcuts that adapt over time)
**Tier: Terminal-adjacent**

The display of adaptive shortcuts is terminal-native (see #23). The adaptation logic (tracking which shortcuts the user uses, reordering by frequency) requires persistent state. The TUI surface itself is unchanged — it just renders whatever shortcuts the backend provides. Mark terminal-adjacent for the same reason as #20: the persistence layer is outside the TUI.

---

### 29. Edit compaction rules (configure how context is summarized)
**Tier: Terminal-native**

A settings panel (`masaq/settings`) with TypeEnum entries for compaction strategy: `[aggressive | balanced | conservative]`. Toggle with `Enter`/`Space`. Already fully supported by `settings.go`.

---

### 30. Arrow key detail toggle
**Tier: Terminal-native**

`→` to expand a selected item to show detail; `←` to collapse. Already handled by `masaq/keys` (`Expand` binding is `d/enter`; `Back` is `esc`). Directional expand/collapse is a standard tree/list pattern in bubbletea. Terminal-native.

---

### 31. Rolling context window (visual display of what's in context)
**Tier: Terminal-equivalent**

A bar or segmented display showing context token usage: `[████████░░░░░░░░] 48k/128k`. Color segments by content type (system/user/tool). Uses `bubbles/progress` for the bar; lipgloss for segment coloring. New component needed but fully within bubbletea.

---

### 32. Coding as game (XP, levels, achievements)
**Tier: Terminal-equivalent**

XP bars, level displays, achievement unlock banners — all pure text + progress bars + notification toasts. The visual vocabulary (numbers, bars, Unicode trophy `🏆` or `★`) works in any UTF-8 terminal. Needs a `gamification` masaq component composing progress bars + notifications. No graphical primitives required.

Note: emoji rendering is terminal-dependent (width assumptions can break layout). Safer to use ASCII art alternatives: `[*]` for star, `+` for XP. Or use emoji only when terminal reports UTF-8 support.

---

### 33. Agent teaches/quizzes user
**Tier: Terminal-native**

Question prompt → user answers → feedback. Exactly the `masaq/question` pattern. The "teaches" half is rendered markdown (`masaq/markdown` via glamour). Terminal-native.

---

### 34. Victory celebrations (confetti, animations)
**Tier: Terminal-equivalent** (text-art) / **Out of scope** (particle confetti)

Full graphical confetti is out of scope — no pixel rendering. However: a multi-line ASCII art burst rendered via lipgloss, auto-dismissed after 3 seconds via `tea.Tick`, is terminal-equivalent. Example:
```
  ★ ·  · ★  ·  ★
·  ✓ COMPLETE! ✓  ·
  ★  ·  · ★ ·  ★
```
Colored with cycling SemanticColors (Success/Warning/Info). Brief animation via frame-cycling on `tea.Tick(100ms)`. Achievable but requires a new `celebrate` masaq component.

---

### 35. Critical hits (dramatic effect on key actions)
**Tier: Terminal-equivalent**

A momentary highlight flash: border color changes to `SemanticColors.Error` (red) or `SemanticColors.Warning` (orange) for 300ms on a "critical" event, then reverts. Implemented via a state flag + `tea.Tick` for timeout. Text effect: bold + color change on the relevant line. Terminal-equivalent (new `flash` or `highlight` component).

---

### 36. Agent location map (2D spatial map of agents)
**Tier: Out of scope** (as 2D map) / **Terminal-equivalent** (as structured list)

Same constraint as #12. A 2D draggable map of agent positions is out of scope.

**Keyboard-native equivalent:** A hierarchical list showing agent containment/relationships with ASCII tree art:
```
► Skaffen (orchestrator)
  ├─ Worker-A [running] src/api.go
  ├─ Worker-B [idle]
  └─ Worker-C [blocked] waiting on Worker-A
```
Navigate with `↑↓`, inspect with `Enter`. Status colors via SemanticColors. This conveys topology without requiring spatial coordinates.

---

### 37. Passive toggles (background behavior switches)
**Tier: Terminal-native**

This is exactly `masaq/settings` — a list of `TypeBool` entries with on/off values, toggled with `Enter`/`Space`. Already built and tested.

---

### 38. Pattern → recipes (detect patterns, suggest recipes)
**Tier: Terminal-equivalent**

Display: a list of detected patterns with suggested actions. The `question` model handles recipe selection. Detection logic is backend. UI surface: a `compact`-style summary of detected pattern + `question` for action selection. Composable from existing primitives with minimal new glue.

---

### 39. Time-aware suggestions
**Tier: Terminal-native**

A contextual suggestion line: `Morning: suggest review queue | Afternoon: suggest new feature work`. Pure text updated on `tea.Tick(1*time.Minute)` checking `time.Now().Hour()`. No new components. Terminal-native.

---

### 40. /treasures discoveries
**Tier: Terminal-native**

A discoverable item log — essentially a filtered viewport or list of "found" items. Slash command `/treasures` triggers a `question`-style panel showing discoveries. Terminal-native using existing components.

---

### 41. Wrapped summary (end-of-session stats)
**Tier: Terminal-native**

A full-screen stats display: numbers, bars, emoji/ASCII art. `glamour` renders markdown summary nicely. `bubbles/progress` for any bar charts. Static render (no interaction required beyond dismiss). Terminal-native.

---

### 42. Side-by-side alternatives (two code versions)
**Tier: Terminal-equivalent**

`lipgloss.JoinHorizontal(lipgloss.Top, leftPane, rightPane)` renders two columns. Each pane wraps a `masaq/diff` renderer or `masaq/viewport`. At 120 cols: ~58 chars per pane (readable). At 80 cols: ~38 chars per pane (tight but workable for code). Toggle between split/unified with a key. Needs a `split-view` masaq component composing two viewports side by side.

**Column layout feasibility:** lipgloss `JoinHorizontal` is proven in many bubbletea apps. The hard constraint is terminal width — below ~60 cols total, split view becomes unusable. Graceful fallback: collapse to single pane with `Tab` to switch, when `termWidth < 80`.

---

### 43. Proactive pref calibration (agent asks about preferences)
**Tier: Terminal-native**

The `masaq/question` model is exactly this: agent presents a question with options, user navigates and selects. Already built. Terminal-native.

---

### 44. Proactive alternatives (agent suggests alternatives unprompted)
**Tier: Terminal-native**

An interruptive `question` panel appearing mid-session: "I could also do X or Y — continue with Z?" Bubbletea's message-passing model handles this cleanly (backend sends a `ProposalMsg`, model shows question overlay). Terminal-native.

---

### 45. Proactive exploration (agent surfaces unexplored paths)
**Tier: Terminal-native**

A suggestion sidebar or inline prompt. Same pattern as #44: a `question` overlay or a compact one-line suggestion in the status bar. Terminal-native.

---

### 46. Interview question UI (structured Q&A flow)
**Tier: Terminal-native**

A sequential question/answer flow. `masaq/question` handles single-choice questions. Free-text answers use `bubbles/textinput`. A `wizard` or `interview` component sequencing multiple questions is buildable from existing primitives. Terminal-native.

**Multi-pane feasibility:** An interview could show prior Q&A on the left (viewport) and the current question on the right (question model). `lipgloss.JoinHorizontal` makes this a two-column layout — terminal-equivalent at adequate terminal width.

---

### 47. A/B split pane (compare two outputs)
**Tier: Terminal-equivalent**

Same as #42. Two `viewport` models joined horizontally. Add a focused-pane indicator (border color change on active pane). `Tab` switches focus between panes. The split must be fixed-ratio (e.g., 50/50) since no drag resize is possible. A `splitpane` masaq component with keyboard-only focus switching.

**Column layout feasibility:** same constraints as #42. Works at 80+ cols; needs graceful fallback below that.

---

### 48. Speculative queue (background pre-computation tasks)
**Tier: Terminal-equivalent**

A background task queue display: `[queued] Analyze auth module | [running] Index symbols | [done] Cache deps`. A list with status color coding. The queue itself is backend logic; the UI is a filterable list with SemanticColors status indicators. Composable from `bubbles/list` + SemanticColors. Terminal-equivalent (needs a `queue-panel` component).

---

### 49. Company leaderboard
**Tier: Terminal-equivalent**

A ranked list table: `[Rank] [Team] [Score] [Delta]`. lipgloss table layout with aligned columns using `lipgloss.NewStyle().Width(n)` on each cell. Sorted list with scroll via `bubbles/list`. Delta shown as `+12 ↑` or `-3 ↓` with SemanticColors.Success/Error. Needs a `leaderboard` masaq component — purely within bubbletea/lipgloss.

---

### 50. Cross-company leaderboard
**Tier: Terminal-equivalent**

Same as #49 with an additional "Company" column. The constraint is column width: at 80 cols, fitting Rank + Company + Team + Score + Delta requires tight column widths (~12–15 chars each). Feasible with careful width allocation. Identical implementation to #49 with one extra column.

---

## Consolidated Tier Summary

### Terminal-native (22 ideas)
Fully expressible today with existing masaq components — no new code required beyond wiring.

| # | Concept |
|---|---------|
| 1 | Waveform tok/s |
| 2 | Health/state frame colors |
| 3 | Slash command familiarity |
| 5 | Game-style controls |
| 7 | Rearview mirror |
| 9 | Smart progress bars |
| 11 | ETA forecasts |
| 13 | Task queue |
| 14 | Breadcrumb trail |
| 15 | Lens switching |
| 22 | Multi-path pick |
| 23 | Auto shortcuts |
| 25 | Next work suggestions |
| 29 | Edit compaction rules |
| 30 | Arrow key detail toggle |
| 33 | Agent teaches/quizzes |
| 37 | Passive toggles |
| 39 | Time-aware suggestions |
| 40 | /treasures discoveries |
| 41 | Wrapped summary |
| 43 | Proactive pref calibration |
| 44 | Proactive alternatives |
| 45 | Proactive exploration |
| 46 | Interview question UI |

*(24 ideas, not 22 — count corrected in table)*

### Terminal-equivalent (19 ideas)
Requires a new masaq component but stays within pure bubbletea/lipgloss.

| # | Concept | New component needed |
|---|---------|---------------------|
| 6 | Codebase visit frequency | `filetree` with heatmap coloring |
| 8 | Compass on/off track | status indicator widget |
| 10 | Central task dispatch | command palette (textinput + filtered list) |
| 12 | Spatial agent overview | structured agent list/table |
| 17 | Parallel exploration | `splitpane` (two viewports horizontal) |
| 19 | Agent dashboard | `dashboard` layout composition |
| 21 | Agent skill tracking | `skill-tracker` table with progress bars |
| 24 | Notification queue | `toast` component with auto-dismiss |
| 26 | Drag permission levels | keyboard slider (←/→ on enum) |
| 27 | SRS memory review | `srs-review` flashcard component |
| 31 | Rolling context window | segmented token-usage bar |
| 32 | Coding as game | `gamification` (XP/level/achievement) |
| 34 | Victory celebrations | `celebrate` text-art + flash animation |
| 35 | Critical hits | `flash` highlight component |
| 36 | Agent location map | ASCII tree topology list |
| 38 | Pattern → recipes | compact + question composition |
| 42 | Side-by-side alternatives | `splitpane` with diff renderers |
| 47 | A/B split pane | `splitpane` with viewport focus |
| 48 | Speculative queue | `queue-panel` list |
| 49 | Company leaderboard | `leaderboard` table |
| 50 | Cross-company leaderboard | `leaderboard` table (extra column) |

*(21 ideas)*

### Terminal-adjacent (3 ideas)
Works in a terminal session but needs tmux, OSC escapes, or persistent external state.

| # | Concept | External dependency |
|---|---------|-------------------|
| 17 | Parallel exploration (independent processes) | tmux split-pane |
| 20 | Preference learning | persistent state backend |
| 28 | Auto shortcuts + learning | persistent state backend |

### Out of scope (5 ideas)
Requires graphical UI, hardware, mobile, or audio — fundamentally non-terminal.

| # | Concept | Hard constraint |
|---|---------|----------------|
| 4 | Desktop peripheral | No HID/USB API in bubbletea |
| 16 | Mobile tap UI | No touch event protocol in terminal |
| 18 | Energy-aware routing | Hardware sensor access; routing logic, not UI |
| 12 | Spatial agent overview (canvas form) | No pixel canvas; no drag |
| 36 | Agent location map (2D map form) | No pixel canvas; no drag |

---

## Detailed Assessments for Specific Categories

### Sparkline/Waveform (#1) — Unicode Rendering Proposal

**Character set:** `▁▂▃▄▅▆▇█` (U+2581–U+2588, "Lower N Eighths Block")

**Rendering formula:**
```
func sparkBar(value, max float64) rune {
    if max == 0 { return '▁' }
    idx := int((value / max) * 7)
    if idx > 7 { idx = 7 }
    return rune('▁' + idx)  // U+2581 + 0..7
}
```

**Layout:** Fixed 20-char ring buffer at 200ms tick interval:
```
tok/s ▁▁▂▃▄▅▆▇█▇▆▅▄▃▂▁▂▃▄ 287 t/s
```

**Color:** All bars share `SemanticColors.Info.Color()` (Tokyo Night: `#7dcfff`). Optionally ramp from `Muted` → `Info` → `Warning` → `Error` based on value relative to a p90 threshold.

**Width budget:** Label (6) + space (1) + bars (20) + space (1) + rate (8) = 36 chars. Fits a 40-col sidebar or header segment.

**tea.Tick sufficiency:** 200ms tick = 5fps. Human perception of smooth motion requires ~24fps for video; for a tok/s waveform, 5fps is entirely adequate. The ring buffer shifts one position per tick regardless of actual token count (samples are averaged into the current slot).

---

### Mouse-dependent ideas — Keyboard-native equivalents

**#26 Drag permission levels:**
- Keyboard: `←` decrements, `→` increments on a 5-step enum `[none | read | read-write | full | admin]`
- Display: `Permission: [read-write] ←/→ to change`
- Exact masaq pattern: `settings.TypeEnum` with `Options: []string{"none","read","read-write","full","admin"}`

**#12 Spatial agent overview:**
- Keyboard: arrow navigation through a `bubbles/list` of agents; `Enter` to inspect; `Tab` to switch focus group
- Display: tabular layout with `lipgloss.JoinHorizontal` for status columns
- Topology: expressed as indentation depth in the list (parent → children → grandchildren)

**#36 Agent location map:**
- Keyboard: same as #12; add `e`/`c` to expand/collapse subtrees
- Display: ASCII tree with `├─`, `└─`, `│` box-drawing characters
- Navigation: `j/k` moves cursor, `Enter` selects, `Esc` collapses
- Status colors applied to each node's name

---

### Multi-pane ideas — lipgloss Column Layout Feasibility

**`lipgloss.JoinHorizontal(lipgloss.Top, pane1, pane2)`**

Constraints:
- Each pane must be pre-computed to an exact string width before joining
- Width must be calculated from terminal width: `paneW = (termW - borderCols) / numPanes`
- Resize: bubbletea sends `tea.WindowSizeMsg` on terminal resize; re-render both panes at new widths

**#42 Side-by-side alternatives:**
- At 80 cols: paneW = 38, usable for code with short lines
- At 120 cols: paneW = 58, comfortable
- Fallback below 60 cols: stack vertically or offer `Tab` toggle between views
- Border: 1 char separator `│` between panes

**#47 A/B split pane:**
- Same geometry as #42
- Focus indicator: active pane gets `SemanticColors.Primary` border; inactive gets `SemanticColors.Muted` border
- Focus switch: `Tab` cycles focus; focused pane handles scroll keys

**#46 Interview question UI (if using split):**
- Left pane: prior Q&A transcript (viewport)
- Right pane: current question (question model)
- At 80 cols: left=30, right=48 — adequate for question + options

**General lipgloss column rule:** Three panes require 120+ cols for comfortable use; two panes work at 80+. Always provide a single-pane fallback.

---

### Real-time Animation Ideas — tea.Tick Sufficiency

| Concept | Recommended tick | fps equiv | Assessment |
|---------|-----------------|-----------|------------|
| #1 Waveform tok/s | 200ms | 5 fps | Sufficient — waveform is sampled data, not smooth motion |
| #8 Compass on/off track | 1000ms | 1 fps | Sufficient — direction only changes when plan state changes |
| #11 ETA forecasts | 1000ms | 1 fps | Sufficient — ETA is a coarse estimate, 1s update is appropriate |
| #9 Smart progress bars | 100ms | 10 fps | Sufficient — `bubbles/progress` uses 10fps for smooth fill |
| #34 Victory celebrations | 100ms | 10 fps | Borderline — 10fps ASCII art animation works; not silky smooth |
| #35 Critical hits | 100ms | 10 fps | Sufficient — 300ms flash with 2–3 frames is perceptible |

**Conclusion:** `tea.Tick` is sufficient for all these cases. The limitation is not frame rate but rendering cost — a full re-render of a complex layout at 100ms (10fps) is fast enough for Go's string-building approach, but pathological cases (very wide terminals, many concurrent viewports) could introduce visible lag. Mitigation: only tick the components that need it; use `tea.Batch` to compose multiple tick intervals.

---

### Color Depth vs SemanticColors Palette

The 15 SemanticColors roles cover all reasonable UI state encoding:

| Role | Usage in these 50 ideas |
|------|------------------------|
| Primary | Active element, selected item, focused pane border |
| Secondary | Accent, skill level, lens label |
| Success | Healthy state, on-track compass, completed task, XP gain |
| Warning | Degraded state, approaching deadline, off-track |
| Error | Failed state, critical hit flash, blocked agent |
| Info | Waveform bars, tok/s display, info notifications |
| Muted | Inactive border, breadcrumb separator, context lines |
| Bg/BgDark/BgLight | Panel backgrounds, alternating rows |
| Fg/FgDim | Primary text, secondary text |
| Border | Default borders |
| DiffAdd/DiffRemove/DiffContext | Code diff rendering (#42, #47) |

**Finding:** The palette is complete for all 50 ideas. No additional semantic role is needed. The only gap is a "Highlight" or "Flash" color for #35 critical hits — but `Error` red serves this purpose adequately.

**Color depth requirement:** All ideas work at 256-color (terminal256). The hex values in Tokyo Night will dither gracefully in 256-color mode via lipgloss's automatic color quantization. True 24-bit (truecolor) is preferred but not required.

---

## Out of Scope — Specific Constraint Explanations

**#4 Desktop peripheral:**
Terminal processes communicate with the OS kernel via stdin/stdout. HID devices (gamepads, stream decks, tablets) are USB/Bluetooth HID class devices communicated via platform-specific APIs (Linux `hidraw`, macOS IOKit, Windows WinAPI). bubbletea has no facility to enumerate or read from HID devices. A daemon that translates physical inputs to synthetic keystrokes could bridge this, but that daemon is an OS-level integration, not a terminal UI.

**#16 Mobile tap UI:**
The xterm escape sequence protocol (which terminal emulators implement) has no touch event codes. The closest is `\e[<Mb;x;yM` for mouse button clicks, but this requires a physical pointer device and reports column/row coordinates, not pixel coordinates. Touch events (multi-touch, gestures, pressure) have no representation in any terminal escape sequence standard (not in VT220, xterm, kitty, nor iTerm2 protocols as of 2026). A native mobile app framework is required.

**#18 Energy-aware routing:**
Reading battery state (`/sys/class/power_supply/BAT0/capacity` on Linux, `ioreg` on macOS) is technically possible from a Go process. However, this is routing logic — it belongs in the agent orchestration layer, not the terminal UI. The UI can display a battery indicator (terminal-native), but the concept as described (routing decisions based on power state) is a backend concern. Marked out of scope because the UI layer has no agency over routing.

**#12 / #36 Spatial canvas forms:**
A 2D canvas where elements have arbitrary (x,y) positions and can be dragged requires: (1) absolute cursor positioning (possible with ANSI `\e[row;colH` escape), (2) mouse click coordinates to determine which element was clicked (possible with `tea.MouseMsg` if `WithMouseCellMotion` is enabled), (3) drag gestures tracking mousedown + mousemove + mouseup sequences. bubbletea v1.3.4 supports mouse button events, but masaq does not currently enable them, and drag-to-move remains a complex interaction that conflicts with the terminal's own text selection behavior. The visual result also fights terminal rendering: elements can only be placed on character-cell boundaries (columns are 8px wide in most terminals), and transparent overlapping is impossible. The spatial canvas metaphor is fundamentally graphical.

---

## Prioritized Implementation Order

For Masaq/Sylveste, the highest-value terminal-equivalent components to build (ordered by number of ideas they unlock):

1. **`splitpane` component** — unlocks #17, #42, #47 (3 ideas; also enables multi-agent monitoring)
2. **`toast`/notification component** — unlocks #24, #34, #35 (3 ideas; essential for any event-driven feedback)
3. **`filetree` component** with heatmap coloring — unlocks #6, #36-equivalent (agent topology as tree)
4. **`leaderboard`/table component** — unlocks #49, #50
5. **`dashboard` layout** composing existing masaq models — unlocks #19
6. **`srs-review` component** — unlocks #27 (niche but self-contained)

The 24 terminal-native ideas require zero new masaq code — they are immediate.
