---
artifact_type: plan
bead: Demarch-s9jd
stage: design
requirements:
  - F1: Prompt history search (Ctrl+R)
  - F2: Keyboard shortcuts help panel
---
# Skaffen: Prompt History + Keyboard Help

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Demarch-s9jd
**Goal:** Add readline-style Ctrl+R history search and a ? keyboard shortcuts overlay to Skaffen's TUI.

**Architecture:** History is a flat text file (`~/.skaffen/history`) appended on each submit, loaded into memory at startup. A new `historyModel` Bubble Tea component handles the Ctrl+R overlay with incremental search. Keyboard help is a new `keyHelpModel` overlay toggled by `?` on empty prompt. Both integrate into `promptModel` and `appModel` following the same delegation pattern as the file picker and command completer.

**Tech Stack:** Go, Bubble Tea, lipgloss, Masaq theme

---

## Must-Haves

**Truths** (observable behaviors):
- User can press Ctrl+R on empty or non-empty prompt to search history
- Typing in the search narrows matches incrementally; Up/Down cycle through matches
- Enter selects a match and populates the prompt; Esc cancels
- History persists across sessions in `~/.skaffen/history`
- Consecutive duplicate prompts are not stored
- User can press `?` on empty prompt to see keyboard shortcuts; any key dismisses
- Help panel shows context-sensitive shortcuts grouped by category

**Artifacts** (files that must exist):
- [`internal/tui/history.go`] exports `historyModel`, `newHistoryModel`, `historySelectedMsg`, `historyCancelMsg`
- [`internal/tui/history_store.go`] exports `historyStore`, `newHistoryStore`, `Load`, `Append`, `Search`
- [`internal/tui/keyhelp.go`] exports `keyHelpModel`, `newKeyHelpModel`
- [`internal/tui/history_test.go`] tests for history store and UI model
- [`internal/tui/keyhelp_test.go`] tests for key help overlay

**Key Links:**
- `promptModel` delegates Ctrl+R to `historyModel` and `?` to `keyHelpModel`
- `appModel` passes `historyStore` path from config and wires history on submit
- History file I/O happens only in `history_store.go` (not in the TUI model)

---

### Task 1: History Store — Persistence Layer

**Files:**
- Create: `os/Skaffen/internal/tui/history_store.go`
- Test: `os/Skaffen/internal/tui/history_test.go`

**Step 1: Write the failing tests**

```go
// os/Skaffen/internal/tui/history_test.go
package tui

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestHistoryStoreEmpty(t *testing.T) {
	hs := newHistoryStore(filepath.Join(t.TempDir(), "history"))
	if len(hs.entries) != 0 {
		t.Fatal("new store should be empty")
	}
}

func TestHistoryStoreAppendAndSearch(t *testing.T) {
	path := filepath.Join(t.TempDir(), "history")
	hs := newHistoryStore(path)
	hs.Append("hello world")
	hs.Append("help me")
	hs.Append("goodbye")

	results := hs.Search("hel")
	if len(results) != 2 {
		t.Fatalf("search 'hel' should match 2, got %d", len(results))
	}
	// Most recent first
	if results[0] != "help me" {
		t.Errorf("first result = %q, want 'help me'", results[0])
	}
}

func TestHistoryStoreDedup(t *testing.T) {
	path := filepath.Join(t.TempDir(), "history")
	hs := newHistoryStore(path)
	hs.Append("same")
	hs.Append("same")
	hs.Append("same")
	if len(hs.entries) != 1 {
		t.Errorf("consecutive dupes should be deduped, got %d", len(hs.entries))
	}
}

func TestHistoryStorePersistence(t *testing.T) {
	path := filepath.Join(t.TempDir(), "history")
	hs := newHistoryStore(path)
	hs.Append("first")
	hs.Append("second")

	// Load into a new store
	hs2 := newHistoryStore(path)
	hs2.Load()
	if len(hs2.entries) != 2 {
		t.Fatalf("loaded store should have 2 entries, got %d", len(hs2.entries))
	}
	if hs2.entries[0] != "first" {
		t.Errorf("entries[0] = %q, want 'first'", hs2.entries[0])
	}
}

func TestHistoryStoreLoadMissing(t *testing.T) {
	hs := newHistoryStore(filepath.Join(t.TempDir(), "nonexistent", "history"))
	hs.Load() // should not panic or error
	if len(hs.entries) != 0 {
		t.Fatal("loading missing file should yield empty store")
	}
}

func TestHistoryStoreSearchCaseInsensitive(t *testing.T) {
	path := filepath.Join(t.TempDir(), "history")
	hs := newHistoryStore(path)
	hs.Append("Hello World")
	results := hs.Search("hello")
	if len(results) != 1 {
		t.Fatalf("case-insensitive search should match, got %d", len(results))
	}
}

func TestHistoryStoreSearchEmpty(t *testing.T) {
	path := filepath.Join(t.TempDir(), "history")
	hs := newHistoryStore(path)
	hs.Append("hello")
	hs.Append("world")
	// Empty query returns all entries, most recent first
	results := hs.Search("")
	if len(results) != 2 {
		t.Fatalf("empty search should return all, got %d", len(results))
	}
	if results[0] != "world" {
		t.Errorf("most recent should be first, got %q", results[0])
	}
}

func TestHistoryStoreMaxEntries(t *testing.T) {
	path := filepath.Join(t.TempDir(), "history")
	hs := newHistoryStore(path)
	for i := 0; i < maxHistoryEntries+100; i++ {
		hs.Append(strings.Repeat("x", i+1))
	}
	if len(hs.entries) > maxHistoryEntries {
		t.Errorf("store should cap at %d, got %d", maxHistoryEntries, len(hs.entries))
	}
}
```

**Step 2: Run tests to verify they fail**

Run: `cd os/Skaffen && go test ./internal/tui/ -run TestHistoryStore -v -count=1`
Expected: FAIL — `newHistoryStore` not defined

**Step 3: Implement history_store.go**

```go
// os/Skaffen/internal/tui/history_store.go
package tui

import (
	"bufio"
	"os"
	"path/filepath"
	"strings"
)

const maxHistoryEntries = 10000

// historyStore manages a flat-file prompt history.
// Entries are stored one per line. The file is append-only;
// Load reads the full file into memory on startup.
type historyStore struct {
	path    string
	entries []string
}

func newHistoryStore(path string) *historyStore {
	return &historyStore{path: path}
}

// Load reads history entries from the file on disk.
// Missing file is not an error (empty history).
func (h *historyStore) Load() {
	f, err := os.Open(h.path)
	if err != nil {
		return
	}
	defer f.Close()

	var entries []string
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		if line != "" {
			entries = append(entries, line)
		}
	}
	// Cap at max
	if len(entries) > maxHistoryEntries {
		entries = entries[len(entries)-maxHistoryEntries:]
	}
	h.entries = entries
}

// Append adds an entry to history. Consecutive duplicates are skipped.
// The entry is also appended to the file on disk.
func (h *historyStore) Append(entry string) {
	entry = strings.TrimSpace(entry)
	if entry == "" {
		return
	}
	// Skip consecutive duplicates
	if len(h.entries) > 0 && h.entries[len(h.entries)-1] == entry {
		return
	}
	h.entries = append(h.entries, entry)
	// Cap at max
	if len(h.entries) > maxHistoryEntries {
		h.entries = h.entries[len(h.entries)-maxHistoryEntries:]
	}
	// Append to file (best-effort — don't fail the UI on write errors)
	if h.path != "" {
		if err := os.MkdirAll(filepath.Dir(h.path), 0o755); err == nil {
			if f, err := os.OpenFile(h.path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644); err == nil {
				f.WriteString(entry + "\n")
				f.Close()
			}
		}
	}
}

// Search returns entries matching the query substring (case-insensitive),
// most recent first. Empty query returns all entries in reverse order.
func (h *historyStore) Search(query string) []string {
	lower := strings.ToLower(query)
	var results []string
	// Iterate backwards for most-recent-first
	for i := len(h.entries) - 1; i >= 0; i-- {
		if query == "" || strings.Contains(strings.ToLower(h.entries[i]), lower) {
			results = append(results, h.entries[i])
		}
	}
	return results
}
```

**Step 4: Run tests to verify they pass**

Run: `cd os/Skaffen && go test ./internal/tui/ -run TestHistoryStore -v -count=1`
Expected: PASS — all 8 tests

**Step 5: Commit**

```bash
cd os/Skaffen && git add internal/tui/history_store.go internal/tui/history_test.go
git commit -m "feat(tui): add history store with file persistence and search"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/tui/ -run TestHistoryStore -v -count=1`
  expect: exit 0
- run: `cd os/Skaffen && go vet ./internal/tui/`
  expect: exit 0
</verify>

---

### Task 2: History Search Overlay — Bubble Tea Model

**Files:**
- Create: `os/Skaffen/internal/tui/history.go`
- Modify: `os/Skaffen/internal/tui/history_test.go` (add UI tests)

**Step 1: Write the failing tests**

Append to `os/Skaffen/internal/tui/history_test.go`:

```go
func TestHistoryModelInitialState(t *testing.T) {
	hs := newHistoryStore(filepath.Join(t.TempDir(), "history"))
	hs.Append("first")
	hs.Append("second")
	hm := newHistoryModel(hs, "")
	if !hm.visible {
		t.Fatal("history model should start visible")
	}
	if len(hm.matches) != 2 {
		t.Errorf("initial matches = %d, want 2", len(hm.matches))
	}
}

func TestHistoryModelTypeNarrows(t *testing.T) {
	hs := newHistoryStore(filepath.Join(t.TempDir(), "history"))
	hs.Append("hello world")
	hs.Append("help me")
	hs.Append("goodbye")
	hm := newHistoryModel(hs, "")
	hm, _ = hm.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'h'}})
	hm, _ = hm.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'e'}})
	if len(hm.matches) != 2 {
		t.Errorf("typing 'he' should match 2, got %d", len(hm.matches))
	}
}

func TestHistoryModelEnterSelects(t *testing.T) {
	hs := newHistoryStore(filepath.Join(t.TempDir(), "history"))
	hs.Append("hello world")
	hm := newHistoryModel(hs, "")
	_, cmd := hm.Update(tea.KeyMsg{Type: tea.KeyEnter})
	if cmd == nil {
		t.Fatal("enter should produce a command")
	}
	msg := cmd()
	sel, ok := msg.(historySelectedMsg)
	if !ok {
		t.Fatalf("expected historySelectedMsg, got %T", msg)
	}
	if sel.Text != "hello world" {
		t.Errorf("selected = %q, want 'hello world'", sel.Text)
	}
}

func TestHistoryModelEscCancels(t *testing.T) {
	hs := newHistoryStore(filepath.Join(t.TempDir(), "history"))
	hs.Append("hello")
	hm := newHistoryModel(hs, "")
	_, cmd := hm.Update(tea.KeyMsg{Type: tea.KeyEsc})
	if cmd == nil {
		t.Fatal("esc should produce a command")
	}
	msg := cmd()
	if _, ok := msg.(historyCancelMsg); !ok {
		t.Fatalf("expected historyCancelMsg, got %T", msg)
	}
}

func TestHistoryModelArrowKeys(t *testing.T) {
	hs := newHistoryStore(filepath.Join(t.TempDir(), "history"))
	hs.Append("first")
	hs.Append("second")
	hs.Append("third")
	hm := newHistoryModel(hs, "")
	if hm.cursor != 0 {
		t.Fatal("cursor should start at 0")
	}
	hm, _ = hm.Update(tea.KeyMsg{Type: tea.KeyDown})
	if hm.cursor != 1 {
		t.Errorf("cursor after down = %d, want 1", hm.cursor)
	}
	hm, _ = hm.Update(tea.KeyMsg{Type: tea.KeyUp})
	if hm.cursor != 0 {
		t.Errorf("cursor after up = %d, want 0", hm.cursor)
	}
}

func TestHistoryModelView(t *testing.T) {
	hs := newHistoryStore(filepath.Join(t.TempDir(), "history"))
	hs.Append("hello world")
	hm := newHistoryModel(hs, "")
	view := hm.View(80)
	if view == "" {
		t.Fatal("view should not be empty")
	}
	if !strings.Contains(view, "hello world") {
		t.Fatal("view should contain history entry")
	}
}

func TestHistoryModelViewHidden(t *testing.T) {
	hs := newHistoryStore(filepath.Join(t.TempDir(), "history"))
	hm := newHistoryModel(hs, "")
	hm.visible = false
	if hm.View(80) != "" {
		t.Fatal("hidden model should return empty view")
	}
}

func TestHistoryModelWithSeedText(t *testing.T) {
	hs := newHistoryStore(filepath.Join(t.TempDir(), "history"))
	hs.Append("hello world")
	hs.Append("goodbye world")
	hm := newHistoryModel(hs, "hello")
	if len(hm.matches) != 1 {
		t.Errorf("seed 'hello' should match 1, got %d", len(hm.matches))
	}
}

func TestHistoryModelEmptyStore(t *testing.T) {
	hs := newHistoryStore(filepath.Join(t.TempDir(), "history"))
	hm := newHistoryModel(hs, "")
	_, cmd := hm.Update(tea.KeyMsg{Type: tea.KeyEnter})
	if cmd == nil {
		t.Fatal("enter on empty should still produce a command")
	}
	msg := cmd()
	if _, ok := msg.(historyCancelMsg); !ok {
		t.Fatalf("enter on empty matches should cancel, got %T", msg)
	}
}

func TestHistoryModelBackspace(t *testing.T) {
	hs := newHistoryStore(filepath.Join(t.TempDir(), "history"))
	hs.Append("hello")
	hs.Append("world")
	hm := newHistoryModel(hs, "")
	hm, _ = hm.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'h'}})
	narrowed := len(hm.matches)
	hm, _ = hm.Update(tea.KeyMsg{Type: tea.KeyBackspace})
	if len(hm.matches) < narrowed {
		t.Error("backspace should widen results")
	}
	if hm.query != "" {
		t.Errorf("query after backspace = %q, want empty", hm.query)
	}
}
```

**Step 2: Run tests to verify they fail**

Run: `cd os/Skaffen && go test ./internal/tui/ -run TestHistoryModel -v -count=1`
Expected: FAIL — `newHistoryModel` not defined

**Step 3: Implement history.go**

```go
// os/Skaffen/internal/tui/history.go
package tui

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/mistakeknot/Masaq/theme"
)

// historySelectedMsg is sent when the user selects a history entry.
type historySelectedMsg struct {
	Text string
}

// historyCancelMsg is sent when the user cancels history search.
type historyCancelMsg struct{}

const historyMaxVisible = 8

// historyModel provides an incremental reverse-search overlay for prompt history.
type historyModel struct {
	store   *historyStore
	query   string
	matches []string
	cursor  int
	visible bool
}

func newHistoryModel(store *historyStore, seedQuery string) historyModel {
	hm := historyModel{
		store:   store,
		query:   seedQuery,
		visible: true,
	}
	hm.matches = store.Search(seedQuery)
	return hm
}

func (h historyModel) Update(msg tea.Msg) (historyModel, tea.Cmd) {
	km, ok := msg.(tea.KeyMsg)
	if !ok {
		return h, nil
	}

	switch km.Type {
	case tea.KeyEnter:
		h.visible = false
		if len(h.matches) == 0 {
			return h, func() tea.Msg { return historyCancelMsg{} }
		}
		text := h.matches[h.cursor]
		return h, func() tea.Msg { return historySelectedMsg{Text: text} }

	case tea.KeyEsc:
		h.visible = false
		return h, func() tea.Msg { return historyCancelMsg{} }

	case tea.KeyUp, tea.KeyCtrlP:
		if h.cursor > 0 {
			h.cursor--
		}
		return h, nil

	case tea.KeyDown, tea.KeyCtrlN:
		if h.cursor < len(h.matches)-1 {
			h.cursor++
		}
		return h, nil

	case tea.KeyBackspace:
		if len(h.query) > 0 {
			h.query = h.query[:len(h.query)-1]
			h.matches = h.store.Search(h.query)
			h.cursor = 0
		}
		return h, nil

	case tea.KeyRunes:
		h.query += string(km.Runes)
		h.matches = h.store.Search(h.query)
		h.cursor = 0
		return h, nil
	}

	return h, nil
}

func (h historyModel) View(width int) string {
	if !h.visible {
		return ""
	}
	c := theme.Current().Semantic()
	headerStyle := lipgloss.NewStyle().Foreground(c.Primary.Color()).Bold(true)
	dimStyle := lipgloss.NewStyle().Foreground(c.FgDim.Color())
	selectedStyle := lipgloss.NewStyle().Foreground(c.Accent.Color()).Bold(true)

	var b strings.Builder
	if h.query == "" {
		b.WriteString(headerStyle.Render("reverse-i-search: "))
	} else {
		b.WriteString(headerStyle.Render(fmt.Sprintf("reverse-i-search: %s", h.query)))
	}
	b.WriteString("\n")

	if len(h.matches) == 0 {
		b.WriteString(dimStyle.Render("  (no matches)"))
		return b.String()
	}

	// Show up to historyMaxVisible entries
	visible := h.matches
	if len(visible) > historyMaxVisible {
		visible = visible[:historyMaxVisible]
	}
	for i, entry := range visible {
		// Truncate long entries
		display := entry
		maxLen := width - 4
		if maxLen < 20 {
			maxLen = 20
		}
		if len(display) > maxLen {
			display = display[:maxLen-3] + "..."
		}
		if i == h.cursor {
			b.WriteString(selectedStyle.Render("▸ " + display))
		} else {
			b.WriteString(dimStyle.Render("  " + display))
		}
		if i < len(visible)-1 {
			b.WriteString("\n")
		}
	}

	if len(h.matches) > historyMaxVisible {
		b.WriteString("\n")
		b.WriteString(dimStyle.Render(fmt.Sprintf("  ... %d more", len(h.matches)-historyMaxVisible)))
	}

	return b.String()
}
```

**Step 4: Run tests to verify they pass**

Run: `cd os/Skaffen && go test ./internal/tui/ -run TestHistoryModel -v -count=1`
Expected: PASS — all 10 tests

**Step 5: Commit**

```bash
cd os/Skaffen && git add internal/tui/history.go internal/tui/history_test.go
git commit -m "feat(tui): add history search overlay with incremental filtering"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/tui/ -run "TestHistory" -v -count=1`
  expect: exit 0
</verify>

---

### Task 3: Wire History into Prompt and App

**Files:**
- Modify: `os/Skaffen/internal/tui/prompt.go`
- Modify: `os/Skaffen/internal/tui/app.go`
- Modify: `os/Skaffen/internal/tui/commands.go` (add `/history` command)
- Modify: `os/Skaffen/internal/config/config.go` (add `HistoryPath`)
- Modify: `os/Skaffen/cmd/skaffen/main.go` (wire history path)
- Test: `os/Skaffen/internal/tui/history_test.go` (add integration tests)

**Step 1: Add HistoryPath to config**

In `os/Skaffen/internal/config/config.go`, add after the `EvidenceDir` method:

```go
// HistoryPath returns the path to the prompt history file (always ~/.skaffen/history).
func (c *Config) HistoryPath() string { return filepath.Join(c.userDir, "history") }
```

**Step 2: Add history fields to promptModel**

In `os/Skaffen/internal/tui/prompt.go`:

Add `history` and `searching` fields to `promptModel`:

```go
type promptModel struct {
	input      textinput.Model
	lines      []string
	picker     filePickerModel
	picking    bool
	completer  cmdCompleterModel
	completing bool
	history    historyModel
	searching  bool
	workDir    string
	customCmds map[string]command.Def
	skills     map[string]skill.Def
}
```

Add `historySelectedMsg` and `historyCancelMsg` handling in `Update`, right after `cmdCompleterCancelMsg`:

```go
case historySelectedMsg:
	sel := msg.(historySelectedMsg)
	p.searching = false
	p.input.SetValue(sel.Text)
	p.input.CursorEnd()
	return p, nil
case historyCancelMsg:
	p.searching = false
	return p, nil
```

Add delegation to history model when searching (after the completer delegation block):

```go
// Delegate to history search when active
if p.searching {
	var cmd tea.Cmd
	p.history, cmd = p.history.Update(msg)
	return p, cmd
}
```

Add Ctrl+R trigger in the `tea.KeyMsg` switch, before the `default:` case:

```go
case "ctrl+r":
	if p.historyStore != nil {
		p.history = newHistoryModel(p.historyStore, p.input.Value())
		p.searching = true
		return p, nil
	}
```

Add `historyStore *historyStore` field to `promptModel` and update `View` to show history overlay:

```go
// Show history search below prompt input
if p.searching {
	historyView := p.history.View(width)
	if historyView != "" {
		result = result + "\n" + historyView
	}
}
```

Update `Reset()` to clear searching state:

```go
func (p *promptModel) Reset() {
	p.input.SetValue("")
	p.lines = nil
	p.picking = false
	p.completing = false
	p.searching = false
}
```

**Step 3: Wire history store in appModel**

In `os/Skaffen/internal/tui/app.go`:

Add `historyStore *historyStore` field to `Config`:

```go
type Config struct {
	// ... existing fields ...
	HistoryPath string
}
```

In `newAppModel`, after creating the promptModel, load history:

```go
var hs *historyStore
if cfg.HistoryPath != "" {
	hs = newHistoryStore(cfg.HistoryPath)
	hs.Load()
}
pm.historyStore = hs
```

Add `historyStore` field to `appModel`:

```go
historyStore  *historyStore
```

In `newAppModel`, wire it:

```go
historyStore: hs,
```

In the `submitMsg` handler (before the agent call), append to history:

```go
if m.historyStore != nil {
	m.historyStore.Append(msg.Text)
}
```

Also add `historySelectedMsg, historyCancelMsg` to the message delegation block:

```go
case filePickerSelectedMsg, filePickerCancelMsg,
	cmdCompleterSelectedMsg, cmdCompleterCancelMsg,
	historySelectedMsg, historyCancelMsg:
```

**Step 4: Wire history path in main.go**

In `os/Skaffen/cmd/skaffen/main.go`, in `runTUI()`, add to the `tui.Config`:

```go
HistoryPath: cfg.HistoryPath(),
```

**Step 5: Add /history command**

In `os/Skaffen/internal/tui/commands.go`:

Add `"history"` to `KnownCommands()`:

```go
"history": "Show recent prompt history",
```

Add case in `executeCommand`:

```go
case "history":
	return m.execHistory(cmd.Args)
```

Add the method:

```go
func (m *appModel) execHistory(args []string) CommandResult {
	if m.historyStore == nil {
		return CommandResult{Message: "History not available.", IsError: true}
	}
	entries := m.historyStore.Search("")
	if len(entries) == 0 {
		return CommandResult{Message: "No history entries."}
	}
	limit := 20
	if len(entries) < limit {
		limit = len(entries)
	}
	var b strings.Builder
	b.WriteString("Recent prompts:\n")
	for i, e := range entries[:limit] {
		display := e
		if len(display) > 80 {
			display = display[:77] + "..."
		}
		b.WriteString(fmt.Sprintf("  %d. %s\n", i+1, display))
	}
	if len(entries) > limit {
		b.WriteString(fmt.Sprintf("  ... %d more (Ctrl+R to search)\n", len(entries)-limit))
	}
	return CommandResult{Message: b.String()}
}
```

**Step 6: Write integration tests**

Append to `os/Skaffen/internal/tui/history_test.go`:

```go
func TestPromptCtrlRActivatesHistory(t *testing.T) {
	p := newPromptModel()
	hs := newHistoryStore(filepath.Join(t.TempDir(), "history"))
	hs.Append("test prompt")
	p.historyStore = hs
	p, _ = p.Update(tea.KeyMsg{Type: tea.KeyCtrlR})
	if !p.searching {
		t.Fatal("Ctrl+R should activate history search")
	}
}

func TestPromptCtrlRWithoutStoreSafe(t *testing.T) {
	p := newPromptModel()
	p, _ = p.Update(tea.KeyMsg{Type: tea.KeyCtrlR})
	if p.searching {
		t.Fatal("Ctrl+R without history store should not activate search")
	}
}

func TestPromptHistorySelection(t *testing.T) {
	p := newPromptModel()
	hs := newHistoryStore(filepath.Join(t.TempDir(), "history"))
	hs.Append("selected prompt")
	p.historyStore = hs
	p, _ = p.Update(tea.KeyMsg{Type: tea.KeyCtrlR})
	p, _ = p.Update(historySelectedMsg{Text: "selected prompt"})
	if p.searching {
		t.Fatal("history should close after selection")
	}
	if p.input.Value() != "selected prompt" {
		t.Errorf("input after selection = %q, want 'selected prompt'", p.input.Value())
	}
}

func TestPromptHistoryCancel(t *testing.T) {
	p := newPromptModel()
	hs := newHistoryStore(filepath.Join(t.TempDir(), "history"))
	hs.Append("something")
	p.historyStore = hs
	p, _ = p.Update(tea.KeyMsg{Type: tea.KeyCtrlR})
	p, _ = p.Update(historyCancelMsg{})
	if p.searching {
		t.Fatal("history should close after cancel")
	}
}
```

**Step 7: Run all tests**

Run: `cd os/Skaffen && go test ./internal/tui/ -v -count=1`
Expected: PASS — all tests including new history integration tests

**Step 8: Run full project tests**

Run: `cd os/Skaffen && go test ./... -count=1`
Expected: PASS

**Step 9: Commit**

```bash
cd os/Skaffen && git add internal/tui/prompt.go internal/tui/app.go internal/tui/commands.go internal/config/config.go cmd/skaffen/main.go internal/tui/history_test.go
git commit -m "feat(tui): wire Ctrl+R history search into prompt, app, and config"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/tui/ -run "TestHistory|TestPromptCtrlR|TestPromptHistory" -v -count=1`
  expect: exit 0
- run: `cd os/Skaffen && go test ./... -count=1`
  expect: exit 0
- run: `cd os/Skaffen && go vet ./...`
  expect: exit 0
</verify>

---

### Task 4: Keyboard Shortcuts Help Overlay

**Files:**
- Create: `os/Skaffen/internal/tui/keyhelp.go`
- Create: `os/Skaffen/internal/tui/keyhelp_test.go`

**Step 1: Write the failing tests**

```go
// os/Skaffen/internal/tui/keyhelp_test.go
package tui

import (
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
)

func TestKeyHelpInitialState(t *testing.T) {
	kh := newKeyHelpModel()
	if !kh.visible {
		t.Fatal("key help should start visible")
	}
}

func TestKeyHelpDismissOnEsc(t *testing.T) {
	kh := newKeyHelpModel()
	kh, cmd := kh.Update(tea.KeyMsg{Type: tea.KeyEsc})
	if kh.visible {
		t.Fatal("esc should hide key help")
	}
	if cmd == nil {
		t.Fatal("esc should produce a command")
	}
	msg := cmd()
	if _, ok := msg.(keyHelpDismissMsg); !ok {
		t.Fatalf("expected keyHelpDismissMsg, got %T", msg)
	}
}

func TestKeyHelpDismissOnAnyKey(t *testing.T) {
	kh := newKeyHelpModel()
	kh, cmd := kh.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'a'}})
	if kh.visible {
		t.Fatal("any key should hide key help")
	}
	if cmd == nil {
		t.Fatal("any key should produce a dismiss command")
	}
}

func TestKeyHelpViewNonEmpty(t *testing.T) {
	kh := newKeyHelpModel()
	view := kh.View(80)
	if view == "" {
		t.Fatal("view should not be empty")
	}
	if !strings.Contains(view, "Enter") {
		t.Fatal("view should mention Enter key")
	}
	if !strings.Contains(view, "Ctrl+R") {
		t.Fatal("view should mention Ctrl+R")
	}
}

func TestKeyHelpViewHidden(t *testing.T) {
	kh := newKeyHelpModel()
	kh.visible = false
	if kh.View(80) != "" {
		t.Fatal("hidden key help should return empty view")
	}
}

func TestKeyHelpViewContainsCategories(t *testing.T) {
	kh := newKeyHelpModel()
	view := kh.View(80)
	if !strings.Contains(view, "Input") {
		t.Fatal("view should have Input category")
	}
	if !strings.Contains(view, "Navigation") {
		t.Fatal("view should have Navigation category")
	}
}

func TestKeyHelpViewWidth(t *testing.T) {
	kh := newKeyHelpModel()
	view := kh.View(40)
	// Should still render without panic
	if view == "" {
		t.Fatal("narrow view should still render")
	}
}
```

**Step 2: Run tests to verify they fail**

Run: `cd os/Skaffen && go test ./internal/tui/ -run TestKeyHelp -v -count=1`
Expected: FAIL — `newKeyHelpModel` not defined

**Step 3: Implement keyhelp.go**

```go
// os/Skaffen/internal/tui/keyhelp.go
package tui

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/mistakeknot/Masaq/theme"
)

// keyHelpDismissMsg is sent when the help overlay is dismissed.
type keyHelpDismissMsg struct{}

type keyBinding struct {
	Key  string
	Desc string
}

type keyCategory struct {
	Name     string
	Bindings []keyBinding
}

// keyHelpModel displays an overlay of keyboard shortcuts.
type keyHelpModel struct {
	visible    bool
	categories []keyCategory
}

func newKeyHelpModel() keyHelpModel {
	return keyHelpModel{
		visible: true,
		categories: []keyCategory{
			{
				Name: "Input",
				Bindings: []keyBinding{
					{"Enter", "Send message"},
					{"Shift+Enter", "New line"},
					{"Ctrl+G", "Open editor"},
					{"Ctrl+R", "Search history"},
					{"/", "Slash commands"},
					{"@", "File picker"},
					{"?", "This help"},
				},
			},
			{
				Name: "Navigation",
				Bindings: []keyBinding{
					{"PgUp/PgDn", "Scroll viewport"},
					{"Home/End", "Jump to top/bottom"},
					{"Ctrl+U/D", "Half-page scroll"},
				},
			},
			{
				Name: "Session",
				Bindings: []keyBinding{
					{"Shift+Tab", "Toggle plan mode"},
					{"Ctrl+C", "Quit"},
				},
			},
		},
	}
}

func (k keyHelpModel) Update(msg tea.Msg) (keyHelpModel, tea.Cmd) {
	if _, ok := msg.(tea.KeyMsg); ok {
		k.visible = false
		return k, func() tea.Msg { return keyHelpDismissMsg{} }
	}
	return k, nil
}

func (k keyHelpModel) View(width int) string {
	if !k.visible {
		return ""
	}

	c := theme.Current().Semantic()
	titleStyle := lipgloss.NewStyle().Foreground(c.Primary.Color()).Bold(true)
	catStyle := lipgloss.NewStyle().Foreground(c.Accent.Color()).Bold(true)
	keyStyle := lipgloss.NewStyle().Foreground(c.Info.Color())
	descStyle := lipgloss.NewStyle().Foreground(c.Fg.Color())
	dimStyle := lipgloss.NewStyle().Foreground(c.FgDim.Color())

	var b strings.Builder
	b.WriteString(titleStyle.Render("Keyboard Shortcuts"))
	b.WriteString("\n")

	for i, cat := range k.categories {
		if i > 0 {
			b.WriteString("\n")
		}
		b.WriteString(catStyle.Render(cat.Name))
		b.WriteString("\n")
		for _, bind := range cat.Bindings {
			// Pad key to 14 chars for alignment
			key := bind.Key
			pad := 14 - len(key)
			if pad < 1 {
				pad = 1
			}
			b.WriteString(fmt.Sprintf("  %s%s%s\n",
				keyStyle.Render(key),
				strings.Repeat(" ", pad),
				descStyle.Render(bind.Desc),
			))
		}
	}

	b.WriteString("\n")
	b.WriteString(dimStyle.Render("Press any key to dismiss"))

	return b.String()
}
```

**Step 4: Run tests to verify they pass**

Run: `cd os/Skaffen && go test ./internal/tui/ -run TestKeyHelp -v -count=1`
Expected: PASS — all 7 tests

**Step 5: Commit**

```bash
cd os/Skaffen && git add internal/tui/keyhelp.go internal/tui/keyhelp_test.go
git commit -m "feat(tui): add keyboard shortcuts help overlay"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/tui/ -run TestKeyHelp -v -count=1`
  expect: exit 0
</verify>

---

### Task 5: Wire Keyboard Help into Prompt and App

**Files:**
- Modify: `os/Skaffen/internal/tui/prompt.go`
- Modify: `os/Skaffen/internal/tui/app.go`
- Modify: `os/Skaffen/internal/tui/commands.go` (add to /help output + KnownCommands)
- Modify: `os/Skaffen/internal/tui/keyhelp_test.go` (add integration tests)

**Step 1: Add helping state to promptModel**

In `os/Skaffen/internal/tui/prompt.go`:

Add `keyHelp` and `helping` fields:

```go
type promptModel struct {
	// ... existing fields ...
	keyHelp    keyHelpModel
	helping    bool
}
```

Add `keyHelpDismissMsg` handling (after `historyCancelMsg`):

```go
case keyHelpDismissMsg:
	p.helping = false
	return p, nil
```

Add delegation to keyHelp when active (after history delegation):

```go
// Delegate to key help when active
if p.helping {
	var cmd tea.Cmd
	p.keyHelp, cmd = p.keyHelp.Update(msg)
	return p, cmd
}
```

Add `?` trigger in the `default:` case, right before the `/` trigger check:

```go
// Check for ? trigger on empty prompt (no accumulated lines)
if len(msg.Runes) == 1 && msg.Runes[0] == '?' &&
	len(p.lines) == 0 && p.input.Value() == "" {
	p.keyHelp = newKeyHelpModel()
	p.helping = true
	return p, nil
}
```

Add key help overlay rendering in `View` (after history overlay):

```go
// Show key help overlay below prompt
if p.helping {
	helpView := p.keyHelp.View(width)
	if helpView != "" {
		result = result + "\n" + helpView
	}
}
```

Update `Reset()`:

```go
p.helping = false
```

**Step 2: Wire keyHelpDismissMsg in appModel**

In `os/Skaffen/internal/tui/app.go`, add `keyHelpDismissMsg` to the message delegation block:

```go
case filePickerSelectedMsg, filePickerCancelMsg,
	cmdCompleterSelectedMsg, cmdCompleterCancelMsg,
	historySelectedMsg, historyCancelMsg,
	keyHelpDismissMsg:
```

**Step 3: Update placeholder text**

In `os/Skaffen/internal/tui/prompt.go`, update the placeholder:

```go
ti.Placeholder = "Ask anything... (Enter to send, Shift+Enter for newline, ? for help)"
```

**Step 4: Update /help to mention ? shortcut**

In `os/Skaffen/internal/tui/commands.go`, update the `/help` description in `KnownCommands()`:

```go
"help": "Show available commands (? for keyboard shortcuts)",
```

**Step 5: Add tab completer knowledge**

In `os/Skaffen/internal/tui/cmdcomplete.go`, add `"history"` to the `KnownCommands()` reference since it was added in Task 3.

**Step 6: Write integration tests**

Append to `os/Skaffen/internal/tui/keyhelp_test.go`:

```go
func TestPromptQuestionMarkTriggersHelp(t *testing.T) {
	p := newPromptModel()
	p, _ = p.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'?'}})
	if !p.helping {
		t.Fatal("? on empty prompt should activate key help")
	}
}

func TestPromptQuestionMarkMidTextNoTrigger(t *testing.T) {
	p := newPromptModel()
	p.input.SetValue("what")
	p, _ = p.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'?'}})
	if p.helping {
		t.Fatal("? mid-text should not activate key help")
	}
}

func TestPromptQuestionMarkWithLinesNoTrigger(t *testing.T) {
	p := newPromptModel()
	p.lines = []string{"first line"}
	p, _ = p.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'?'}})
	if p.helping {
		t.Fatal("? with accumulated lines should not activate key help")
	}
}

func TestPromptKeyHelpDismiss(t *testing.T) {
	p := newPromptModel()
	p, _ = p.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'?'}})
	p, _ = p.Update(keyHelpDismissMsg{})
	if p.helping {
		t.Fatal("key help should close after dismiss")
	}
}
```

**Step 7: Run all tests**

Run: `cd os/Skaffen && go test ./... -count=1`
Expected: PASS

**Step 8: Commit**

```bash
cd os/Skaffen && git add internal/tui/prompt.go internal/tui/app.go internal/tui/commands.go internal/tui/keyhelp_test.go
git commit -m "feat(tui): wire ? keyboard help overlay into prompt and app"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/tui/ -run "TestKeyHelp|TestPromptQuestion|TestPromptKeyHelp" -v -count=1`
  expect: exit 0
- run: `cd os/Skaffen && go test ./... -count=1`
  expect: exit 0
- run: `cd os/Skaffen && go vet ./...`
  expect: exit 0
</verify>

---

### Task 6: Update Placeholder and Final Polish

**Files:**
- Modify: `os/Skaffen/internal/tui/prompt_test.go` (update placeholder test)
- Modify: `os/Skaffen/internal/tui/cmdcomplete_test.go` (add history to view test)

**Step 1: Update placeholder test**

In `os/Skaffen/internal/tui/prompt_test.go`, update `TestPromptPlaceholderMentionsCtrlG`:

```go
func TestPromptPlaceholderMentionsCtrlG(t *testing.T) {
	p := newPromptModel()
	if !strings.Contains(p.input.Placeholder, "?") {
		t.Fatal("placeholder should mention ? for help")
	}
}
```

**Step 2: Update cmdcomplete view test**

In `os/Skaffen/internal/tui/cmdcomplete_test.go`, the `TestCmdCompleterView` test checks for `/advance` and `/help`. Now `/history` should also appear. Add:

```go
func TestCmdCompleterViewContainsHistory(t *testing.T) {
	cc := newCmdCompleter(nil, nil)
	view := cc.View(80)
	if !strings.Contains(view, "/history") {
		t.Fatal("view should contain /history")
	}
}
```

**Step 3: Run full test suite**

Run: `cd os/Skaffen && go test ./... -count=1`
Expected: PASS

**Step 4: Commit**

```bash
cd os/Skaffen && git add internal/tui/prompt_test.go internal/tui/cmdcomplete_test.go
git commit -m "test(tui): update placeholder and completer tests for history and key help"
```

<verify>
- run: `cd os/Skaffen && go test ./... -count=1`
  expect: exit 0
- run: `cd os/Skaffen && go build ./cmd/skaffen`
  expect: exit 0
</verify>
