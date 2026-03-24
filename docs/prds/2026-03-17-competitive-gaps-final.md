---
artifact_type: prd
bead: Demarch-6i0
stage: design
---
# PRD: Close Final Competitive Gaps in Skaffen TUI

## Problem

Skaffen TUI is missing 2 of 23 features identified in the competitive landscape analysis (91% complete). The remaining gaps — a toggleable sidebar and VS Code extension — are shipped by 2+ competitors and represent visible feature parity gaps.

## Solution

Implement a right-side sidebar panel with session context (files, git, tools, debug) and a lightweight VS Code extension that embeds Skaffen in the integrated terminal with file context bridging.

## Features

### F1: Toggleable Sidebar Panel (Demarch-6i0.15)

**What:** Right-side panel (30% width) with tabbed content showing session context, toggled via `Ctrl+B`.

**Acceptance criteria:**
- [ ] `Ctrl+B` toggles a right-side sidebar panel
- [ ] Sidebar has 4 sub-tabs: Files, Git, Tools, Debug
- [ ] Files tab shows files modified by tool calls this session (relative paths)
- [ ] Git tab shows `git status --porcelain` output, refreshed on tool completion
- [ ] Tools tab shows active MCP servers and last 20 tool calls with timing
- [ ] Debug tab shows OODARC phase, token counts, subagent status
- [ ] Sub-tabs switchable via `Tab` key when sidebar is focused
- [ ] Sidebar auto-hides below 80 columns terminal width
- [ ] Chat viewport width shrinks proportionally when sidebar is open
- [ ] Window resize correctly reflows both panels
- [ ] Sidebar state does not persist across sessions (ephemeral)
- [ ] `ActionSidebar` keybinding is user-configurable via keybindings.json

### F2: VS Code Extension (Demarch-6i0.16)

**What:** VS Code extension that opens Skaffen in the integrated terminal and bridges file context from the active editor.

**Acceptance criteria:**
- [ ] Extension activates when `.skaffen/` directory exists in workspace or via command
- [ ] Command "Skaffen: Open" opens Skaffen in a VS Code terminal
- [ ] Active editor file path is passed to Skaffen via `SKAFFEN_VSCODE_FILE` env var
- [ ] Workspace root is passed via `SKAFFEN_VSCODE_ROOT` env var
- [ ] Status bar item shows Skaffen state (idle/running/not started)
- [ ] Click on status bar item focuses the Skaffen terminal
- [ ] Command "Skaffen: Send File" sends current file path to Skaffen's stdin or IPC
- [ ] Extension targets VS Code engine >=1.85 (stable APIs only)
- [ ] Extension packaged as `.vsix` for local installation
- [ ] README with installation and usage instructions

## Non-goals

- WebView-based chat UI inside VS Code (too expensive, Skaffen stays terminal-native)
- LSP server mode for Skaffen
- Neovim/Zed/other editor extensions (VS Code first)
- Sidebar content persistence across sessions
- Drag-to-resize sidebar (fixed 30% width for now)
- Left-side sidebar option (right only, matching IDE convention)

## Dependencies

- F1 depends on: Masaq `tabbar.Model` (already integrated), `lipgloss.JoinHorizontal` (available)
- F2 depends on: Skaffen binary on PATH, VS Code Extension API, `@types/vscode`
- F2 is independent of F1 (can be built in parallel)

## Open Questions

- **Resolved:** Sidebar position → right (matches IDE convention, chat is primary content)
- **Resolved:** Toggle key → `Ctrl+B` (tmux convention, familiar to terminal users)
- **Deferred:** File diff preview in sidebar (OpenCode has this, can add later as enhancement)
- **Deferred:** IPC channel for richer VS Code ↔ Skaffen communication (env vars sufficient for v1)
