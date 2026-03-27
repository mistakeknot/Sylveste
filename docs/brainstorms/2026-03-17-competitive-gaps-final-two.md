# Brainstorm: Closing Final 2 Competitive Gaps (Sylveste-6i0)

**Date:** 2026-03-17
**Bead:** Sylveste-6i0 (epic: Bridge competitive landscape gaps in Skaffen TUI)
**Status:** 21/23 children complete (91%). Remaining: split panes (6i0.15), VS Code extension (6i0.16)

## Current Architecture Context

Skaffen uses Bubble Tea (Charmbracelet) with Masaq component library. Layout is a vertical stack:
- Tab bar (exists but only has "Chat" tab — not yet functional)
- Chat viewport (fills remaining space)
- Status chrome (breadcrumb, meter, sparkline, status bar — 11 lines fixed)
- Prompt input (bordered, 3 lines)

Key enablers already in place:
- `tabbar.Model` integrated at `app.go:278-279` — just needs tabs + view routing
- `lipgloss.JoinHorizontal()` already used for meter+sparkline
- Overlay pattern (approval, settings, file picker) for modal panels
- Responsive resize via `tea.WindowSizeMsg` updates all components
- Keybindings system supports custom user bindings from JSON config

## Feature 1: Split Panes / Sidebar (Sylveste-6i0.15)

### What Competitors Do
- **OpenCode:** Toggleable sidebar showing file changes and diffs
- **Claude Code:** No sidebar (terminal-only, uses tool output inline)
- **Codex CLI:** No sidebar

### Design Options

**Option A: Sidebar Panel (Recommended)**
Toggle a right-side panel (30% width) with tab-based content:
- Tab 1: **Files** — files changed in session (from tool call tracking)
- Tab 2: **Git** — `git status` / staged changes
- Tab 3: **Tools** — MCP servers + recent tool calls
- Tab 4: **Debug** — agent phase, token counts, subagent status

Layout when sidebar open:
```
┌──────────────────────┬──────────────┐
│ Tab Bar              │              │
├──────────────────────┤  Sidebar     │
│ Chat Viewport        │  [Files]     │
│                      │  [Git]       │
│                      │  [Tools]     │
│                      │  [Debug]     │
├──────────────────────┤              │
│ Status Chrome        │              │
├──────────────────────┤              │
│ Prompt               │              │
└──────────────────────┴──────────────┘
```

Toggle: `Ctrl+B` (matches tmux convention, familiar to terminal users)
Auto-hide: below 80 columns terminal width

**Option B: Bottom Drawer**
Pull-up panel from bottom (like VS Code's terminal panel). Simpler layout math but less usable since Skaffen is already vertical.

**Option C: Full-Screen Tab Views**
Use existing tabbar to switch entire viewport between Chat/Files/Git/Tools views. No split — just tab switching. Simplest to implement but loses context (can't see chat + files simultaneously).

### Recommendation: Option A (Sidebar Panel)

Rationale:
- Most useful UX — see chat and context simultaneously
- Matches OpenCode's approach (competitive parity)
- Tab bar can augment with tab switching for full-screen views later
- Bubble Tea + lipgloss `JoinHorizontal` makes this straightforward

### Implementation Sketch

1. **New file: `internal/tui/sidebar.go`**
   - `sidebarModel` struct with sub-tab state and 4 content models
   - Each sub-tab: separate viewport with its own content
   - `Update()` routes to active sub-tab
   - `View()` renders active sub-tab content with tab header

2. **Modify: `app.go`**
   - Add `sidebarOpen bool` and `sidebar sidebarModel` to `appModel`
   - In `View()`: when sidebar open, use `lipgloss.JoinHorizontal()` to split viewport and sidebar
   - Viewport width shrinks to `m.width * 0.7` when sidebar active
   - Handle `Ctrl+B` keypress to toggle

3. **New file: `internal/tui/sidebar_files.go`**
   - Tracks files modified by tool calls (ReadFile, WriteFile, Edit)
   - Listens for `toolCallMsg` to update file list
   - Shows relative paths with modification indicator

4. **New file: `internal/tui/sidebar_git.go`**
   - Runs `git status --porcelain` periodically (on tool completion)
   - Shows staged/unstaged/untracked with diff stats

5. **New file: `internal/tui/sidebar_tools.go`**
   - Lists active MCP servers with connection status
   - Recent tool calls (last 20) with timing

6. **New file: `internal/tui/sidebar_debug.go`**
   - Agent phase (OODARC breadcrumb)
   - Token counts per turn
   - Active subagent status

7. **Keybindings: `keybindings.go`**
   - Add `ActionSidebar = "sidebar"` with default `ctrl+b`
   - Add `ActionSidebarNext = "sidebar_next"` with default `tab` (when sidebar focused)

## Feature 2: VS Code Extension (Sylveste-6i0.16)

### What Competitors Do
- **Claude Code:** VS Code extension with sidebar panel, inline diffs, terminal integration
- **Codex CLI:** VS Code extension (preview), terminal-based
- **OpenCode:** VS Code extension for LSP-like integration
- **Amp:** VS Code extension as primary interface

### Design Options

**Option A: Terminal Integration Extension (Recommended)**
VS Code extension that:
1. Opens Skaffen in VS Code's integrated terminal
2. Sends active file context via environment variables or IPC
3. Applies diffs to VS Code's editor via `code` CLI
4. Optional: sidebar panel showing Skaffen status

This is the lightest-weight approach — Skaffen stays a terminal app, the extension just provides context bridging.

**Option B: WebView Panel Extension**
Full WebView-based chat UI inside VS Code. Requires rewriting the TUI as a web frontend. Very expensive, out of scope.

**Option C: LSP-Based Extension**
Skaffen runs as an LSP server providing code actions and diagnostics. Novel but doesn't match the competitive model (they all use terminal or panel approaches).

### Recommendation: Option A (Terminal Integration)

Rationale:
- Lowest effort — Skaffen stays a terminal app
- Matches Codex CLI's approach
- VS Code's terminal API is well-documented
- Active file context is the most valuable feature (competitors highlight this)

### Implementation Sketch

1. **VS Code Extension (`vscode-skaffen/`)**
   - TypeScript extension using VS Code Extension API
   - Commands: "Open Skaffen", "Send File to Skaffen", "Apply Skaffen Diff"
   - Keybinding: `Ctrl+Shift+S` to open Skaffen terminal
   - Activation: on command or when `.skaffen/` directory exists

2. **Context Bridge**
   - Extension writes active file path to env var `SKAFFEN_VSCODE_FILE`
   - Extension writes workspace root to `SKAFFEN_VSCODE_ROOT`
   - Optional: Unix socket IPC for richer communication

3. **Diff Application**
   - Skaffen writes diffs to a temp file with structured format
   - Extension watches the temp file and applies via VS Code's `WorkspaceEdit` API
   - Or: Skaffen calls `code --diff` for side-by-side comparison

4. **Status Bar**
   - VS Code status bar item showing Skaffen state (idle/thinking/acting)
   - Click to focus Skaffen terminal

## Sequencing

1. **Split panes first** — purely Go, contained in Skaffen codebase, no external dependencies
2. **VS Code extension second** — TypeScript, new directory, can be developed independently

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Sidebar resize edge cases | Medium | Test at various terminal sizes (80x24 minimum) |
| Performance with frequent git status | Low | Debounce to tool completion events only |
| VS Code API breaking changes | Low | Target VS Code engine >=1.85, use stable APIs |
| Extension marketplace publishing | Low | Can distribute as VSIX initially |

## Open Questions

1. Should sidebar be on left or right? (Right recommended — chat is primary, matches IDE convention)
2. Should VS Code extension support other editors (Neovim, Zed)? (Defer — VS Code first)
3. Should sidebar content persist across sessions? (No — ephemeral, regenerated from session state)
