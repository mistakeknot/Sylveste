---
artifact_type: plan
bead: Sylveste-6i0
stage: design
requirements:
  - F1: Toggleable sidebar panel (Sylveste-6i0.15)
  - F2: VS Code extension (Sylveste-6i0.16)
---
# Competitive Gaps Final Two — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Sylveste-6i0
**Phase:** planned (as of 2026-03-17T06:35:53Z)
**Goal:** Close the final 2 competitive feature gaps in Skaffen TUI: a toggleable right-side sidebar and a VS Code extension.

**Architecture:** The sidebar is a new `sidebarModel` Bubble Tea sub-model embedded in `appModel`, composed horizontally with the chat viewport via `lipgloss.JoinHorizontal()`. It has 4 sub-tabs (Files, Git, Tools, Debug) rendered as separate viewports. The VS Code extension is a TypeScript project using the VS Code Extension API, opening Skaffen in an integrated terminal with context bridging via environment variables.

**Tech Stack:** Go (Bubble Tea, lipgloss, Masaq), TypeScript (VS Code Extension API, `@types/vscode`)

---

## Must-Haves

**Truths** (observable behaviors):
- User can toggle a sidebar panel with Ctrl+B
- Sidebar shows files changed, git status, active tools, and debug info in 4 tabs
- Sidebar auto-hides when terminal is too narrow (<80 cols)
- VS Code command "Skaffen: Open" launches Skaffen in the integrated terminal
- VS Code passes active file path to Skaffen via environment variable

**Artifacts** (files with specific exports):
- [`internal/tui/sidebar.go`] exports `sidebarModel`, `newSidebarModel()`
- [`internal/tui/keybindings.go`] exports `ActionSidebar` constant
- [`vscode-skaffen/src/extension.ts`] exports `activate()`, `deactivate()`

**Key Links** (connections where breakage cascades):
- `appModel.Update()` must route Ctrl+B to sidebar toggle before prompt delegation
- `appModel.View()` must compose sidebar horizontally with viewport when open
- `compactionState` feeds sidebar Files/Tools data — sidebar reads, doesn't mutate
- `WindowSizeMsg` must resize both viewport and sidebar proportionally

---

### Task 1: Add ActionSidebar Keybinding

**Files:**
- Modify: `internal/tui/keybindings.go:10-29` (add constant)
- Modify: `internal/tui/keybindings.go:38-61` (add default binding)
- Modify: `internal/tui/keybindings_test.go` (add test)

**Step 1: Write the failing test**
```go
// In keybindings_test.go
func TestDefaultKeybindings_IncludesSidebar(t *testing.T) {
	kb := DefaultKeybindings()
	keys := kb.Bindings[ActionSidebar]
	if len(keys) == 0 {
		t.Fatal("expected ActionSidebar to have default bindings")
	}
	if keys[0] != "ctrl+b" {
		t.Errorf("expected ctrl+b, got %s", keys[0])
	}
}
```

**Step 2: Run test to verify it fails**
Run: `cd os/Skaffen && go test ./internal/tui/ -run TestDefaultKeybindings_IncludesSidebar -v`
Expected: FAIL — `ActionSidebar` undefined

**Step 3: Write minimal implementation**
Add to `keybindings.go` constants block:
```go
ActionSidebar     = "sidebar"
ActionSidebarNext = "sidebar_next"
```

Add to `DefaultKeybindings()` bindings map:
```go
ActionSidebar:     {"ctrl+b"},
ActionSidebarNext: {"tab"},
```

**Step 4: Run test to verify it passes**
Run: `cd os/Skaffen && go test ./internal/tui/ -run TestDefaultKeybindings_IncludesSidebar -v`
Expected: PASS

**Step 5: Commit**
```bash
cd os/Skaffen && git add internal/tui/keybindings.go internal/tui/keybindings_test.go
git commit -m "feat(tui): add sidebar keybinding action (ctrl+b)"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/tui/ -run TestDefaultKeybindings -v`
  expect: exit 0
</verify>

---

### Task 2: Create Sidebar Model

**Files:**
- Create: `internal/tui/sidebar.go`
- Create: `internal/tui/sidebar_test.go`

**Step 1: Write the failing test**
```go
// sidebar_test.go
package tui

import (
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
)

func TestSidebarModel_NewHasFourTabs(t *testing.T) {
	sb := newSidebarModel(40, 20)
	v := sb.View()
	for _, tab := range []string{"Files", "Git", "Tools", "Debug"} {
		if !strings.Contains(v, tab) {
			t.Errorf("sidebar view missing tab %q", tab)
		}
	}
}

func TestSidebarModel_TabCycling(t *testing.T) {
	sb := newSidebarModel(40, 20)
	if sb.activeTab != 0 {
		t.Fatalf("expected initial tab 0, got %d", sb.activeTab)
	}
	sb, _ = sb.Update(tea.KeyMsg{Type: tea.KeyTab})
	if sb.activeTab != 1 {
		t.Errorf("expected tab 1 after Tab, got %d", sb.activeTab)
	}
}

func TestSidebarModel_TrackFile(t *testing.T) {
	sb := newSidebarModel(40, 20)
	sb.TrackFile("src/main.go", true)
	sb.TrackFile("README.md", false)
	v := sb.View()
	if !strings.Contains(v, "main.go") {
		t.Error("expected tracked file in view")
	}
}

func TestSidebarModel_AddToolCall(t *testing.T) {
	sb := newSidebarModel(40, 20)
	sb.AddToolCall("read", "src/main.go", 150)
	sb.activeTab = 2 // Tools tab
	v := sb.View()
	if !strings.Contains(v, "read") {
		t.Error("expected tool call in Tools tab view")
	}
}
```

**Step 2: Run test to verify it fails**
Run: `cd os/Skaffen && go test ./internal/tui/ -run TestSidebarModel -v`
Expected: FAIL — `newSidebarModel` undefined

**Step 3: Write the sidebar model**
```go
// sidebar.go
package tui

import (
	"fmt"
	"path/filepath"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/mistakeknot/Masaq/theme"
)

var sidebarTabs = []string{"Files", "Git", "Tools", "Debug"}

// trackedFile records a file touched during the session.
type trackedFile struct {
	Path     string
	Mutated  bool
	LastSeen time.Time
}

// toolCallEntry records a single tool invocation.
type toolCallEntry struct {
	Name     string
	Target   string
	Duration time.Duration
	At       time.Time
}

// sidebarModel is the right-side panel showing session context.
type sidebarModel struct {
	width, height int
	activeTab     int
	files         []trackedFile
	fileIndex     map[string]int // path → index in files
	toolCalls     []toolCallEntry
	mcpServers    []string
	phase         string
	turns         int
	tokens        int
	subagentCount int
	gitStatus     string
}

func newSidebarModel(width, height int) sidebarModel {
	return sidebarModel{
		width:     width,
		height:    height,
		fileIndex: make(map[string]int),
	}
}

// TrackFile records a file being read or mutated.
func (s *sidebarModel) TrackFile(path string, mutated bool) {
	if idx, ok := s.fileIndex[path]; ok {
		s.files[idx].LastSeen = time.Now()
		if mutated {
			s.files[idx].Mutated = true
		}
		return
	}
	s.fileIndex[path] = len(s.files)
	s.files = append(s.files, trackedFile{
		Path:     path,
		Mutated:  mutated,
		LastSeen: time.Now(),
	})
}

// AddToolCall records a tool invocation.
func (s *sidebarModel) AddToolCall(name, target string, durationMs int) {
	entry := toolCallEntry{
		Name:     name,
		Target:   target,
		Duration: time.Duration(durationMs) * time.Millisecond,
		At:       time.Now(),
	}
	s.toolCalls = append(s.toolCalls, entry)
	// Keep last 20
	if len(s.toolCalls) > 20 {
		s.toolCalls = s.toolCalls[len(s.toolCalls)-20:]
	}
}

// SetMCPServers updates the list of active MCP server names.
func (s *sidebarModel) SetMCPServers(servers []string) {
	s.mcpServers = servers
}

// SetDebugInfo updates debug state.
func (s *sidebarModel) SetDebugInfo(phase string, turns, tokens, subagents int) {
	s.phase = phase
	s.turns = turns
	s.tokens = tokens
	s.subagentCount = subagents
}

// SetGitStatus updates the git status text.
func (s *sidebarModel) SetGitStatus(status string) {
	s.gitStatus = status
}

// SetSize updates the sidebar dimensions.
func (s *sidebarModel) SetSize(width, height int) {
	s.width = width
	s.height = height
}

func (s sidebarModel) Update(msg tea.Msg) (sidebarModel, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		if msg.Type == tea.KeyTab {
			s.activeTab = (s.activeTab + 1) % len(sidebarTabs)
		}
		if msg.Type == tea.KeyShiftTab {
			s.activeTab = (s.activeTab - 1 + len(sidebarTabs)) % len(sidebarTabs)
		}
	}
	return s, nil
}

func (s sidebarModel) View() string {
	sem := theme.Current().Semantic()
	borderColor := sem.Border.Color()
	dimStyle := lipgloss.NewStyle().Foreground(sem.FgDim.Color())
	headerStyle := lipgloss.NewStyle().Foreground(sem.Primary.Color()).Bold(true)

	// Tab header
	var tabs strings.Builder
	for i, name := range sidebarTabs {
		if i > 0 {
			tabs.WriteString(" ")
		}
		if i == s.activeTab {
			tabs.WriteString(headerStyle.Render("[" + name + "]"))
		} else {
			tabs.WriteString(dimStyle.Render(" " + name + " "))
		}
	}

	// Content area
	contentHeight := s.height - 3 // tabs + top border + bottom border
	if contentHeight < 1 {
		contentHeight = 1
	}
	var content string
	switch s.activeTab {
	case 0:
		content = s.viewFiles(contentHeight)
	case 1:
		content = s.viewGit(contentHeight)
	case 2:
		content = s.viewTools(contentHeight)
	case 3:
		content = s.viewDebug(contentHeight)
	}

	// Compose with border
	innerWidth := s.width - 2
	if innerWidth < 1 {
		innerWidth = 1
	}
	box := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(borderColor).
		Width(innerWidth).
		Height(contentHeight + 1). // +1 for tab header
		Render(tabs.String() + "\n" + content)

	return box
}

func (s sidebarModel) viewFiles(maxLines int) string {
	if len(s.files) == 0 {
		return lipgloss.NewStyle().
			Foreground(theme.Current().Semantic().FgDim.Color()).
			Render("No files touched yet")
	}
	sem := theme.Current().Semantic()
	mutStyle := lipgloss.NewStyle().Foreground(sem.Warning.Color())
	readStyle := lipgloss.NewStyle().Foreground(sem.FgDim.Color())

	var lines []string
	for _, f := range s.files {
		if len(lines) >= maxLines {
			break
		}
		short := filepath.Base(f.Path)
		dir := filepath.Dir(f.Path)
		if dir != "." && dir != "/" {
			short = filepath.Join(filepath.Base(dir), short)
		}
		if f.Mutated {
			lines = append(lines, mutStyle.Render("M ")+short)
		} else {
			lines = append(lines, readStyle.Render("R ")+short)
		}
	}
	return strings.Join(lines, "\n")
}

func (s sidebarModel) viewGit(maxLines int) string {
	if s.gitStatus == "" {
		return lipgloss.NewStyle().
			Foreground(theme.Current().Semantic().FgDim.Color()).
			Render("No git changes")
	}
	lines := strings.Split(s.gitStatus, "\n")
	if len(lines) > maxLines {
		lines = lines[:maxLines]
	}
	return strings.Join(lines, "\n")
}

func (s sidebarModel) viewTools(maxLines int) string {
	sem := theme.Current().Semantic()
	dimStyle := lipgloss.NewStyle().Foreground(sem.FgDim.Color())
	var lines []string

	// MCP servers
	if len(s.mcpServers) > 0 {
		lines = append(lines, lipgloss.NewStyle().Foreground(sem.Primary.Color()).Render("MCP Servers:"))
		for _, srv := range s.mcpServers {
			lines = append(lines, "  "+srv)
		}
		lines = append(lines, "")
	}

	// Recent tool calls (newest first)
	if len(s.toolCalls) > 0 {
		lines = append(lines, lipgloss.NewStyle().Foreground(sem.Primary.Color()).Render("Recent:"))
		for i := len(s.toolCalls) - 1; i >= 0 && len(lines) < maxLines; i-- {
			tc := s.toolCalls[i]
			elapsed := ""
			if tc.Duration >= time.Second {
				elapsed = fmt.Sprintf(" %.1fs", tc.Duration.Seconds())
			}
			target := tc.Target
			if len(target) > 20 {
				target = "..." + target[len(target)-17:]
			}
			line := tc.Name
			if target != "" {
				line += " " + dimStyle.Render(target)
			}
			if elapsed != "" {
				line += dimStyle.Render(elapsed)
			}
			lines = append(lines, "  "+line)
		}
	}

	if len(lines) == 0 {
		return dimStyle.Render("No tool activity")
	}
	return strings.Join(lines, "\n")
}

func (s sidebarModel) viewDebug(maxLines int) string {
	sem := theme.Current().Semantic()
	labelStyle := lipgloss.NewStyle().Foreground(sem.Primary.Color())
	valStyle := lipgloss.NewStyle().Foreground(sem.Fg.Color())
	dimStyle := lipgloss.NewStyle().Foreground(sem.FgDim.Color())

	lines := []string{
		labelStyle.Render("Phase:    ") + valStyle.Render(s.phase),
		labelStyle.Render("Turns:    ") + valStyle.Render(fmt.Sprintf("%d", s.turns)),
		labelStyle.Render("Tokens:   ") + valStyle.Render(fmt.Sprintf("%dk", s.tokens/1000)),
	}
	if s.subagentCount > 0 {
		lines = append(lines, labelStyle.Render("Agents:   ")+valStyle.Render(fmt.Sprintf("%d active", s.subagentCount)))
	} else {
		lines = append(lines, labelStyle.Render("Agents:   ")+dimStyle.Render("none"))
	}
	return strings.Join(lines, "\n")
}
```

**Step 4: Run tests to verify they pass**
Run: `cd os/Skaffen && go test ./internal/tui/ -run TestSidebarModel -v`
Expected: PASS (all 4 tests)

**Step 5: Commit**
```bash
cd os/Skaffen && git add internal/tui/sidebar.go internal/tui/sidebar_test.go
git commit -m "feat(tui): add sidebar model with Files/Git/Tools/Debug tabs"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/tui/ -run TestSidebarModel -v`
  expect: exit 0
</verify>

---

### Task 3: Integrate Sidebar into appModel

**Files:**
- Modify: `internal/tui/app.go:148-232` (add sidebar fields to `appModel`)
- Modify: `internal/tui/app.go:234-312` (initialize sidebar in `newAppModel`)
- Modify: `internal/tui/app.go:318-418` (handle Ctrl+B toggle and sidebar key routing in `Update`)
- Modify: `internal/tui/app.go:685-737` (compose sidebar horizontally in `View`)
- Modify: `internal/tui/app.go:749-818` (feed sidebar from stream events in `handleStreamEvent`)
- Modify: `internal/tui/app_test.go` (add integration test)

**Step 1: Add sidebar fields to `appModel` struct**
After `tabs tabbar.Model` (line 231), add:
```go
	// Sidebar panel (toggled with Ctrl+B)
	sidebarOpen  bool
	sidebar      sidebarModel
```

**Step 2: Initialize sidebar in `newAppModel`**
In the return struct (around line 310), add:
```go
		sidebar:      newSidebarModel(30, 20),
```

**Step 3: Handle Ctrl+B toggle in `Update`**
In the `tea.KeyMsg` case, after the plan mode toggle block (after line 382) and before the logo check, add:
```go
		// Sidebar toggle: Ctrl+B
		if m.keybindings.MatchesAction(msg.String(), ActionSidebar) && !m.approving && !m.settingsOpen {
			m.sidebarOpen = !m.sidebarOpen
			break
		}
		// When sidebar is open and focused, delegate tab switching
		if m.sidebarOpen && (msg.Type == tea.KeyTab || msg.Type == tea.KeyShiftTab) && !m.running && !m.approving && !m.settingsOpen {
			// Don't intercept shift+tab if it's the plan mode keybinding
			if msg.Type == tea.KeyShiftTab && m.keybindings.MatchesAction(msg.String(), ActionPlanMode) {
				// Plan mode takes priority — skip sidebar tab cycling
			} else {
				m.sidebar, _ = m.sidebar.Update(msg)
				break
			}
		}
```

**Step 4: Update `WindowSizeMsg` handler**
In the `tea.WindowSizeMsg` case (around line 322-342), update viewport width calculation:
```go
		// If sidebar is open and terminal wide enough, split width
		vpWidth := m.width
		if m.sidebarOpen && m.width >= 80 {
			sidebarWidth := m.width * 3 / 10 // 30%
			if sidebarWidth < 20 {
				sidebarWidth = 20
			}
			vpWidth = m.width - sidebarWidth
			m.sidebar.SetSize(sidebarWidth, vpHeight)
		} else if m.sidebarOpen && m.width < 80 {
			// Auto-hide sidebar when terminal too narrow
			m.sidebarOpen = false
		}
		m.viewport.SetSize(vpWidth, vpHeight)
```
Remove the existing `m.viewport.SetSize(m.width, vpHeight)` line.

**Step 5: Compose sidebar in `View`**
In the `View()` method, after calculating `vpHeight` and before the scroll hint (around line 716), update the viewport width when sidebar is open:
```go
	vpWidth := m.width
	sidebarView := ""
	if m.sidebarOpen && m.width >= 80 {
		sidebarWidth := m.width * 3 / 10
		if sidebarWidth < 20 {
			sidebarWidth = 20
		}
		vpWidth = m.width - sidebarWidth
		m.sidebar.SetSize(sidebarWidth, vpHeight+2) // +2 to match viewport + scroll hint
		sidebarView = m.sidebar.View()
	}
	if m.viewport.Width() != vpWidth {
		m.viewport.SetSize(vpWidth, vpHeight)
		vpView = m.viewport.View()
	}
```

Then in the final layout composition (around line 736), wrap the chat area and sidebar:
```go
	chatArea := lipgloss.JoinVertical(lipgloss.Left, tabView, logoView, vpView, scrollHint)
	if sidebarView != "" {
		chatArea = lipgloss.JoinHorizontal(lipgloss.Top, chatArea, sidebarView)
	}
	// ... then join chatArea with promptView and statusArea
```

The final return should be:
```go
	promptView := m.prompt.View(vpWidth, m.running, m.spinner.View())
	return lipgloss.JoinVertical(lipgloss.Left, chatArea, promptView, statusArea)
```

And update the approval/settings overlay paths similarly.

**Step 6: Feed sidebar from stream events**
In `handleStreamEvent`, update `StreamToolStart` case to record in sidebar:
```go
	case agent.StreamToolStart:
		// ... existing code ...
		m.sidebar.AddToolCall(ev.ToolName, extractFilePath(ev.ToolName, ev.ToolParams), 0)
```

In `StreamToolComplete` case, after `m.compactState.observeToolComplete(ev)`:
```go
		// Track files in sidebar
		path := extractFilePath(ev.ToolName, ev.ToolParams)
		if path != "" {
			mutated := ev.ToolName == "write" || ev.ToolName == "edit"
			m.sidebar.TrackFile(path, mutated)
		}
```

In `StreamTurnComplete` case, update debug info:
```go
		// Update sidebar debug info
		subCount := 0
		if m.subagents != nil {
			subCount = m.subagents.ActiveCount()
		}
		m.sidebar.SetDebugInfo(m.phase, m.turns, ev.Usage.InputTokens, subCount)
```

**Step 7: Add git status refresh**
Create a new message type and command at the top of app.go:
```go
type gitStatusMsg string

func refreshGitStatus(workDir string) tea.Cmd {
	return func() tea.Msg {
		g := git.New(workDir)
		if !g.IsRepo() {
			return gitStatusMsg("")
		}
		status, err := g.StatusPorcelain()
		if err != nil {
			return gitStatusMsg("")
		}
		return gitStatusMsg(status)
	}
}
```

Handle in Update:
```go
	case gitStatusMsg:
		m.sidebar.SetGitStatus(string(msg))
```

Trigger after tool completion in `StreamToolComplete`:
```go
		// Refresh git status for sidebar after file mutations
		if m.sidebarOpen && (ev.ToolName == "write" || ev.ToolName == "edit" || ev.ToolName == "bash") {
			cmds = append(cmds, refreshGitStatus(m.workDir))
		}
```

This requires adding a `StatusPorcelain()` method to `internal/git/git.go`:
```go
func (g *Git) StatusPorcelain() (string, error) {
	out, err := exec.Command("git", "-C", g.dir, "status", "--porcelain").Output()
	if err != nil {
		return "", err
	}
	return string(out), nil
}
```

**Step 8: Run full test suite**
Run: `cd os/Skaffen && go test ./... -count=1`
Expected: PASS

**Step 9: Commit**
```bash
cd os/Skaffen && git add internal/tui/app.go internal/git/git.go
git commit -m "feat(tui): integrate sidebar panel with Ctrl+B toggle"
```

<verify>
- run: `cd os/Skaffen && go build ./cmd/skaffen`
  expect: exit 0
- run: `cd os/Skaffen && go test ./internal/tui/ -v -count=1`
  expect: exit 0
- run: `cd os/Skaffen && go vet ./...`
  expect: exit 0
</verify>

---

### Task 4: Add Sidebar to Keyboard Help Panel

**Files:**
- Modify: `internal/tui/keyhelp.go` (add sidebar entry to help table)
- Modify: `internal/tui/keyhelp_test.go` (verify sidebar appears in help)

**Step 1: Write the failing test**
```go
func TestKeyHelp_IncludesSidebar(t *testing.T) {
	kb := DefaultKeybindings()
	help := renderKeyHelp(kb, 80)
	if !strings.Contains(help, "Sidebar") && !strings.Contains(help, "sidebar") {
		t.Error("expected sidebar entry in key help")
	}
	if !strings.Contains(help, "ctrl+b") && !strings.Contains(help, "Ctrl+B") {
		t.Error("expected ctrl+b binding in key help")
	}
}
```

**Step 2: Run test to verify it fails**
Run: `cd os/Skaffen && go test ./internal/tui/ -run TestKeyHelp_IncludesSidebar -v`
Expected: FAIL

**Step 3: Add sidebar entry to key help**
Add to the help entries in `keyhelp.go` (find the existing entries list and add):
```go
{Action: ActionSidebar, Label: "Toggle sidebar"},
```

**Step 4: Run test to verify it passes**
Run: `cd os/Skaffen && go test ./internal/tui/ -run TestKeyHelp_IncludesSidebar -v`
Expected: PASS

**Step 5: Commit**
```bash
cd os/Skaffen && git add internal/tui/keyhelp.go internal/tui/keyhelp_test.go
git commit -m "feat(tui): add sidebar toggle to keyboard help panel"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/tui/ -run TestKeyHelp -v`
  expect: exit 0
</verify>

---

### Task 5: Subagent Active Count Helper

**Files:**
- Modify: `internal/tui/subagent.go` (add `ActiveCount` method)
- Modify: `internal/tui/subagent_test.go` (add test)

**Step 1: Write the failing test**
```go
func TestSubagentTracker_ActiveCount(t *testing.T) {
	tr := newSubagentTracker()
	if tr.ActiveCount() != 0 {
		t.Error("expected 0 active when empty")
	}
}
```

**Step 2: Run test — should fail because `ActiveCount` doesn't exist**
Run: `cd os/Skaffen && go test ./internal/tui/ -run TestSubagentTracker_ActiveCount -v`

**Step 3: Add `ActiveCount` to subagentTracker**
```go
func (t *subagentTracker) ActiveCount() int {
	count := 0
	for _, b := range t.blocks {
		if b.status == subagent.StatusRunning {
			count++
		}
	}
	return count
}
```

**Step 4: Run test to verify pass**
Run: `cd os/Skaffen && go test ./internal/tui/ -run TestSubagentTracker_ActiveCount -v`
Expected: PASS

**Step 5: Commit**
```bash
cd os/Skaffen && git add internal/tui/subagent.go internal/tui/subagent_test.go
git commit -m "feat(tui): add ActiveCount to subagent tracker for sidebar"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/tui/ -run TestSubagentTracker -v`
  expect: exit 0
</verify>

---

### Task 6: VS Code Extension Scaffold

**Files:**
- Create: `vscode-skaffen/package.json`
- Create: `vscode-skaffen/tsconfig.json`
- Create: `vscode-skaffen/.vscodeignore`
- Create: `vscode-skaffen/src/extension.ts`

**Step 1: Create package.json**
```json
{
  "name": "vscode-skaffen",
  "displayName": "Skaffen",
  "description": "Skaffen AI agent integration for VS Code",
  "version": "0.1.0",
  "publisher": "mistakeknot",
  "engines": {
    "vscode": "^1.85.0"
  },
  "categories": ["Other"],
  "activationEvents": [
    "workspaceContains:.skaffen"
  ],
  "main": "./out/extension.js",
  "contributes": {
    "commands": [
      {
        "command": "skaffen.open",
        "title": "Skaffen: Open"
      },
      {
        "command": "skaffen.sendFile",
        "title": "Skaffen: Send Current File"
      }
    ],
    "keybindings": [
      {
        "command": "skaffen.open",
        "key": "ctrl+shift+s",
        "mac": "cmd+shift+s"
      }
    ]
  },
  "scripts": {
    "compile": "tsc -p ./",
    "watch": "tsc -watch -p ./",
    "package": "npx @vscode/vsce package"
  },
  "devDependencies": {
    "@types/vscode": "^1.85.0",
    "typescript": "^5.3.0",
    "@vscode/vsce": "^2.22.0"
  }
}
```

**Step 2: Create tsconfig.json**
```json
{
  "compilerOptions": {
    "module": "commonjs",
    "target": "ES2020",
    "outDir": "out",
    "rootDir": "src",
    "strict": true,
    "esModuleInterop": true,
    "sourceMap": true,
    "lib": ["ES2020"]
  },
  "exclude": ["node_modules", ".vscode-test"]
}
```

**Step 3: Create .vscodeignore**
```
.vscode/**
.vscode-test/**
src/**
node_modules/**
tsconfig.json
```

**Step 4: Write extension.ts**
```typescript
import * as vscode from "vscode";

let skaffenTerminal: vscode.Terminal | undefined;
let statusBarItem: vscode.StatusBarItem;

export function activate(context: vscode.ExtensionContext) {
  // Status bar item
  statusBarItem = vscode.window.createStatusBarItem(
    vscode.StatusBarAlignment.Left,
    100
  );
  statusBarItem.command = "skaffen.open";
  statusBarItem.text = "$(terminal) Skaffen";
  statusBarItem.tooltip = "Open Skaffen AI Agent";
  statusBarItem.show();
  context.subscriptions.push(statusBarItem);

  // Track terminal lifecycle
  vscode.window.onDidCloseTerminal((terminal) => {
    if (terminal === skaffenTerminal) {
      skaffenTerminal = undefined;
      statusBarItem.text = "$(terminal) Skaffen";
    }
  });

  // Open command
  const openCmd = vscode.commands.registerCommand("skaffen.open", () => {
    if (skaffenTerminal) {
      skaffenTerminal.show();
      return;
    }

    const workspaceRoot =
      vscode.workspace.workspaceFolders?.[0]?.uri.fsPath ?? "";
    const activeFile =
      vscode.window.activeTextEditor?.document.uri.fsPath ?? "";

    const env: Record<string, string> = {};
    if (workspaceRoot) {
      env["SKAFFEN_VSCODE_ROOT"] = workspaceRoot;
    }
    if (activeFile) {
      env["SKAFFEN_VSCODE_FILE"] = activeFile;
    }

    skaffenTerminal = vscode.window.createTerminal({
      name: "Skaffen",
      cwd: workspaceRoot || undefined,
      env,
    });
    skaffenTerminal.sendText("skaffen", true);
    skaffenTerminal.show();
    statusBarItem.text = "$(terminal-active) Skaffen";
  });

  // Send file command
  const sendFileCmd = vscode.commands.registerCommand(
    "skaffen.sendFile",
    () => {
      const activeFile =
        vscode.window.activeTextEditor?.document.uri.fsPath;
      if (!activeFile) {
        vscode.window.showWarningMessage("No active file to send");
        return;
      }
      if (!skaffenTerminal) {
        vscode.window.showWarningMessage("Skaffen is not running");
        return;
      }
      // Send file path as @mention to Skaffen's stdin
      skaffenTerminal.sendText(`@${activeFile}`, false);
      skaffenTerminal.show();
    }
  );

  // Update env when active editor changes
  vscode.window.onDidChangeActiveTextEditor((editor) => {
    if (skaffenTerminal && editor) {
      // VS Code terminals don't support env updates after creation,
      // but we track it for the next terminal creation
    }
  });

  context.subscriptions.push(openCmd, sendFileCmd);
}

export function deactivate() {
  skaffenTerminal?.dispose();
}
```

**Step 5: Install dependencies and compile**
Run: `cd os/Skaffen/vscode-skaffen && npm install && npm run compile`
Expected: Compiles without errors

**Step 6: Commit**
```bash
cd os/Skaffen && git add vscode-skaffen/
git commit -m "feat: add VS Code extension scaffold with terminal integration"
```

<verify>
- run: `cd os/Skaffen/vscode-skaffen && npx tsc --noEmit`
  expect: exit 0
</verify>

---

### Task 7: VS Code Extension README and Packaging

**Files:**
- Create: `vscode-skaffen/README.md`

**Step 1: Write README**
```markdown
# Skaffen for VS Code

Integrates the Skaffen AI agent into VS Code's integrated terminal.

## Features

- **Open Skaffen** (`Ctrl+Shift+S` / `Cmd+Shift+S`): Launch Skaffen in a VS Code terminal
- **Send File**: Send the active editor file to Skaffen as an @mention
- **Status Bar**: Shows Skaffen status (click to focus)
- **Auto-activate**: Activates when `.skaffen/` directory is detected in workspace

## Environment Variables

The extension sets these environment variables for Skaffen:

| Variable | Description |
|----------|-------------|
| `SKAFFEN_VSCODE_ROOT` | Workspace root directory |
| `SKAFFEN_VSCODE_FILE` | Active editor file path |

## Installation

### From VSIX (local)

1. Build: `npm install && npm run package`
2. Install: `code --install-extension vscode-skaffen-0.1.0.vsix`

### Prerequisites

- `skaffen` binary on PATH
- VS Code >= 1.85
```

**Step 2: Package as VSIX**
Run: `cd os/Skaffen/vscode-skaffen && npm run package`
Expected: Produces `vscode-skaffen-0.1.0.vsix`

**Step 3: Commit**
```bash
cd os/Skaffen && git add vscode-skaffen/README.md
git commit -m "docs: add VS Code extension README and packaging"
```

<verify>
- run: `cd os/Skaffen/vscode-skaffen && npx tsc --noEmit`
  expect: exit 0
</verify>

---

### Task 8: Final Integration Test and Vet

**Files:**
- None new — verification pass only

**Step 1: Run full Go test suite**
Run: `cd os/Skaffen && go test ./... -count=1 -v`
Expected: All tests PASS

**Step 2: Run go vet**
Run: `cd os/Skaffen && go vet ./...`
Expected: No issues

**Step 3: Build binary**
Run: `cd os/Skaffen && go build -o /dev/null ./cmd/skaffen`
Expected: Builds cleanly

**Step 4: Verify VS Code extension compiles**
Run: `cd os/Skaffen/vscode-skaffen && npx tsc --noEmit`
Expected: No type errors

**Step 5: Commit any fixes**
Only if previous steps revealed issues.

<verify>
- run: `cd os/Skaffen && go test ./... -count=1`
  expect: exit 0
- run: `cd os/Skaffen && go vet ./...`
  expect: exit 0
- run: `cd os/Skaffen && go build -o /dev/null ./cmd/skaffen`
  expect: exit 0
</verify>
