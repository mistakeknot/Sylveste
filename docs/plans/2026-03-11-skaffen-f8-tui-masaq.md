---
artifact_type: plan
bead: Sylveste-f18
stage: design
requirements:
  - F8: TUI Mode (Skaffen standalone conversational REPL + Masaq shared library)
---
# F8: Skaffen TUI + Masaq Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Sylveste-f18
**Goal:** Ship a standalone conversational REPL for Skaffen (`skaffen` default mode) backed by Masaq, a shared Bubble Tea component library.

**Architecture:** Two deliverables: (1) Masaq (`github.com/mistakeknot/masaq`) — a separate Go module providing rendering-only Bubble Tea sub-models (theme, diff, markdown, question, viewport, keys, compact). No agent concepts. (2) Skaffen TUI (`os/Skaffen/internal/tui/`) — composes Masaq components into a chat-first REPL with smart trust, phase awareness, and session management. The agent loop (`internal/agent/loop.go`) gains a streaming callback interface so the TUI can render events in real-time instead of calling `Collect()`.

**Tech Stack:** Go 1.22+, Bubble Tea v2, Lipgloss v2, Glamour v2, Chroma (syntax highlighting), BurntSushi/toml (trust config).

## Prior Learnings

- **`docs/solutions/patterns/go-map-iteration-non-determinism.md`** — Go map iteration randomizes order. Any hashing/caching in TUI renderers (e.g., diff cache keys, theme lookups by map iteration) must sort map keys first. Encode this into diff and compact component implementations.

---

## Must-Haves

**Truths** (observable behaviors):
- Running `skaffen` with no args launches a TUI REPL; user can type prompts and get streaming responses
- Running `skaffen run --mode print` preserves existing headless behavior
- Tool calls render as compact one-line summaries by default; pressing Enter/d expands them
- Diffs render with syntax highlighting and [y]/[n] approval keys
- Smart trust auto-allows safe operations (read, write, grep) without prompting
- Session persists to JSONL; `skaffen -c` resumes the last session
- Status bar shows: phase | model | cost | context% | turns

**Artifacts** (files that must exist):
- `masaq/theme/theme.go` exports `Theme`, `TokyoNight`, `Current()`, `Semantic()`
- `masaq/diff/diff.go` exports `Model`, `New()` (Bubble Tea sub-model)
- `masaq/markdown/markdown.go` exports `Model`, `New()` (streaming markdown renderer)
- `masaq/question/question.go` exports `Model`, `New()` (structured multi-choice widget)
- `masaq/viewport/viewport.go` exports `Model`, `New()` (flicker-free scrollable viewport)
- `masaq/keys/keys.go` exports `Map`, `NewDefault()`, `WithVim()`
- `masaq/compact/compact.go` exports `Model`, `New()` (compact/verbose formatter)
- `os/Skaffen/internal/tui/app.go` exports `Run()` (entry point)
- `os/Skaffen/internal/trust/trust.go` exports `Evaluator`, `NewEvaluator()`

**Key Links:**
- `app.go` composes `masaq/viewport`, `masaq/markdown`, `masaq/diff`, `masaq/question` into the REPL
- `app.go` calls `agent.RunStreaming()` which sends `StreamEvent`s via callback — the TUI renders them live
- `trust.go` is called by `app.go` before executing each tool call from the agent loop
- `main.go` dispatches to `tui.Run()` when mode is "tui" (default) or `run()` when mode is "print"

---

### Task 1: Scaffold Masaq repo + Go module

**Files:**
- Create: `masaq/go.mod`
- Create: `masaq/masaq.go`

**Step 1: Create the masaq directory at repo root**

The masaq library lives at the monorepo root as `masaq/` during development (using `replace` directives). It will be published as a separate repo later.

```bash
mkdir -p masaq
```

**Step 2: Initialize go.mod**

```bash
cd masaq && go mod init github.com/mistakeknot/masaq
```

The module path matches the future separate repo.

**Step 3: Create masaq.go package doc**

```go
// Package masaq provides shared Bubble Tea rendering components for the Sylveste
// agent ecosystem. Named after Masaq' Orbital from Iain M. Banks' Look to Windward.
//
// Masaq owns rendering primitives only — it never imports agent, provider, or tool
// packages. Consumers (Skaffen, Autarch) compose Masaq components into their layouts.
package masaq
```

**Step 4: Add Bubble Tea dependencies**

```bash
cd masaq && go get github.com/charmbracelet/bubbletea@latest github.com/charmbracelet/lipgloss@latest github.com/charmbracelet/glamour@latest github.com/charmbracelet/bubbles@latest github.com/alecthomas/chroma/v2@latest
```

Note: Check whether Bubble Tea v2 tags are published (`go list -m -versions github.com/charmbracelet/bubbletea`). If v2 is available, use `bubbletea/v2@latest`. If not, use latest stable v1. Same for lipgloss, bubbles, glamour.

**Step 5: Commit**

```bash
git add masaq/
git commit -m "feat(masaq): scaffold Go module with Bubble Tea dependencies"
```

<verify>
- run: `cd masaq && go build ./...`
  expect: exit 0
</verify>

---

### Task 2: Masaq theme package — Tokyo Night palette + semantic colors

**Files:**
- Create: `masaq/theme/theme.go`
- Create: `masaq/theme/theme_test.go`

**Step 1: Write the failing test**

```go
package theme_test

import (
	"testing"

	"github.com/mistakeknot/masaq/theme"
)

func TestTokyoNightHasRequiredColors(t *testing.T) {
	th := theme.TokyoNight
	if th.Name == "" {
		t.Fatal("theme name must not be empty")
	}
	sem := th.Semantic()
	if sem.Primary.Dark == "" {
		t.Fatal("semantic Primary.Dark must not be empty")
	}
	if sem.Success.Dark == "" {
		t.Fatal("semantic Success.Dark must not be empty")
	}
	if sem.Error.Dark == "" {
		t.Fatal("semantic Error.Dark must not be empty")
	}
}

func TestCurrentReturnsDefault(t *testing.T) {
	th := theme.Current()
	if th.Name != theme.TokyoNight.Name {
		t.Errorf("Current() = %q, want %q", th.Name, theme.TokyoNight.Name)
	}
}

func TestSemanticDiffColors(t *testing.T) {
	sem := theme.TokyoNight.Semantic()
	if sem.DiffAdd.Dark == "" || sem.DiffRemove.Dark == "" {
		t.Fatal("diff colors must be defined")
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd masaq && go test ./theme/ -v`
Expected: FAIL — package not found

**Step 3: Implement the theme package**

Port the color system from `apps/Autarch/pkg/tui/theme/` (Tokyo Night palette) into Masaq. The theme must be standalone — no Autarch imports. Key types:

- `ColorPair` — holds Dark and Light mode hex colors
- `SemanticColors` — maps roles (Primary, Success, Error, DiffAdd, DiffRemove, etc.) to ColorPairs
- `Theme` — named palette with `Semantic()` accessor
- `TokyoNight` — default theme variable with Autarch's palette values
- `Current()` / `SetCurrent()` — global theme accessor

Colors from Autarch's `colors.go`: Primary=#7aa2f7, Secondary=#bb9af7, Success=#9ece6a, Warning=#e0af68, Error=#f7768e, Info=#7dcfff, Muted=#565f89, Bg=#1a1b26, BgDark=#16161e, BgLight=#24283b, Fg=#c0caf5. Add DiffAdd=#9ece6a, DiffRemove=#f7768e, DiffContext=#565f89.

**Step 4: Run test**

Run: `cd masaq && go test ./theme/ -v`
Expected: PASS

**Step 5: Commit**

```bash
git add masaq/theme/
git commit -m "feat(masaq): Tokyo Night theme with semantic color mapping"
```

<verify>
- run: `cd masaq && go test ./theme/ -v`
  expect: exit 0
</verify>

---

### Task 3: Masaq keys package — keybinding framework

**Files:**
- Create: `masaq/keys/keys.go`
- Create: `masaq/keys/keys_test.go`

**Step 1: Write the failing test**

```go
package keys_test

import (
	"testing"

	"github.com/mistakeknot/masaq/keys"
)

func TestDefaultMapHasQuit(t *testing.T) {
	km := keys.NewDefault()
	if len(km.Quit.Keys()) == 0 {
		t.Fatal("Quit binding must have at least one key")
	}
}

func TestVimModeAddsJK(t *testing.T) {
	km := keys.NewDefault(keys.WithVim())
	found := false
	for _, k := range km.NavDown.Keys() {
		if k == "j" {
			found = true
		}
	}
	if !found {
		t.Fatal("vim mode should bind j to NavDown")
	}
}
```

**Step 2: Run test to verify failure**

Run: `cd masaq && go test ./keys/ -v`
Expected: FAIL

**Step 3: Implement keys package**

Port and extend keybindings from `apps/Autarch/pkg/tui/keys.go`. Key types:

- `Map` struct with fields: Quit, Help, NavUp, NavDown, Top, Bottom, PageUp, PageDown, Accept, Reject, Expand, Back, Submit, Search — all `key.Binding`
- `Option` func type for configuration
- `WithVim()` — adds j/k/g/G bindings alongside arrows
- `NewDefault(opts ...Option)` — returns Map with standard bindings

Standard bindings: ctrl+c=quit, ?=help, up/down, home/end, pgup/pgdown, y=accept, n=reject, d/enter=expand, esc=back, enter=submit, ctrl+f=search.

**Step 4: Run test**

Run: `cd masaq && go test ./keys/ -v`
Expected: PASS

**Step 5: Commit**

```bash
git add masaq/keys/
git commit -m "feat(masaq): keybinding framework with vim mode option"
```

<verify>
- run: `cd masaq && go test ./keys/ -v`
  expect: exit 0
</verify>

---

### Task 4: Masaq viewport — flicker-free scrollable viewport

**Files:**
- Create: `masaq/viewport/viewport.go`
- Create: `masaq/viewport/viewport_test.go`

**Step 1: Write the failing test**

```go
package viewport_test

import (
	"strings"
	"testing"

	"github.com/mistakeknot/masaq/viewport"
)

func TestNewViewport(t *testing.T) {
	vp := viewport.New(80, 24)
	if vp.Width() != 80 || vp.Height() != 24 {
		t.Fatalf("got %dx%d, want 80x24", vp.Width(), vp.Height())
	}
}

func TestAppendAndView(t *testing.T) {
	vp := viewport.New(40, 5)
	vp.AppendContent("line 1\nline 2\nline 3\n")
	view := vp.View()
	if !strings.Contains(view, "line 1") {
		t.Fatal("view should contain appended content")
	}
}

func TestAutoScrollOnAppend(t *testing.T) {
	vp := viewport.New(40, 2)
	for i := 0; i < 10; i++ {
		vp.AppendContent("line\n")
	}
	view := vp.View()
	lines := strings.Split(strings.TrimRight(view, "\n"), "\n")
	if len(lines) > 3 {
		t.Fatalf("viewport should clip to height, got %d lines", len(lines))
	}
}
```

**Step 2: Run test to verify failure**

Run: `cd masaq && go test ./viewport/ -v`
Expected: FAIL

**Step 3: Implement viewport**

A scrollable viewport with auto-scroll on append (for streaming) and manual scroll override. Bubble Tea sub-model (Init/Update/View). Key features:

- `New(width, height)` constructor
- `AppendContent(text)` — for streaming; merges partial last lines
- `SetContent(text)` — replace all content
- `SetSize(w, h)` — resize handler
- `ScrollUp(n)` / `ScrollDown(n)` — manual scroll (disables auto-scroll)
- Auto-scroll re-enables when user scrolls to bottom
- `View()` returns only visible lines, truncated to width
- Keyboard: up/k, down/j, pgup, pgdown, home/g, end/G

Important: Use `ansi.Truncate` from `charmbracelet/x/ansi` for width truncation of styled strings, NOT `[]rune` slicing (see Autarch CLAUDE.md Bubble Tea rules).

**Step 4: Run test**

Run: `cd masaq && go test ./viewport/ -v`
Expected: PASS

**Step 5: Commit**

```bash
git add masaq/viewport/
git commit -m "feat(masaq): flicker-free scrollable viewport with auto-scroll"
```

<verify>
- run: `cd masaq && go test ./viewport/ -v`
  expect: exit 0
</verify>

---

### Task 5: Masaq diff renderer — unified diff with Chroma syntax highlighting

**Files:**
- Create: `masaq/diff/diff.go`
- Create: `masaq/diff/diff_test.go`

**Step 1: Write the failing test**

```go
package diff_test

import (
	"strings"
	"testing"

	"github.com/mistakeknot/masaq/diff"
)

func TestRenderUnifiedDiff(t *testing.T) {
	d := diff.New(80)
	before := "func hello() {\n\treturn \"hello\"\n}\n"
	after := "func hello() {\n\treturn \"hello world\"\n}\n"
	result := d.Render(before, after, "main.go")
	if !strings.Contains(result, "+") {
		t.Fatal("diff should contain + lines for additions")
	}
	if !strings.Contains(result, "-") {
		t.Fatal("diff should contain - lines for removals")
	}
}

func TestNoDiffReturnsEmpty(t *testing.T) {
	d := diff.New(80)
	result := d.Render("same", "same", "file.go")
	if result != "" {
		t.Fatalf("identical content should produce empty diff, got: %q", result)
	}
}
```

**Step 2: Run test to verify failure**

Run: `cd masaq && go test ./diff/ -v`
Expected: FAIL

**Step 3: Implement diff renderer**

Uses `git diff --no-index` for diff generation (same approach as `apps/Autarch/pkg/tui/diff.go`), then applies styling:

- `New(width)` constructor
- `Render(before, after, filename)` — returns styled diff string
- Header lines (diff --git, ---, +++) in Info color, bold
- Hunk markers (@@) in Secondary color
- Added lines (+) in DiffAdd color with Chroma syntax highlighting of the content
- Removed lines (-) in DiffRemove color with Chroma syntax highlighting
- Context lines in DiffContext color
- `highlightLine(line, filename)` — uses Chroma lexer matched by filename extension, terminal256 formatter

Gotcha: sort map keys before hashing if any caching is added (see Prior Learnings).

**Step 4: Run test**

Run: `cd masaq && go test ./diff/ -v`
Expected: PASS

**Step 5: Commit**

```bash
git add masaq/diff/
git commit -m "feat(masaq): unified diff renderer with Chroma syntax highlighting"
```

<verify>
- run: `cd masaq && go test ./diff/ -v`
  expect: exit 0
</verify>

---

### Task 6: Masaq markdown renderer — Glamour-based streaming adapter

**Files:**
- Create: `masaq/markdown/markdown.go`
- Create: `masaq/markdown/markdown_test.go`

**Step 1: Write the failing test**

```go
package markdown_test

import (
	"strings"
	"testing"

	"github.com/mistakeknot/masaq/markdown"
)

func TestRenderComplete(t *testing.T) {
	m := markdown.New(80)
	result := m.Render("# Hello\n\nThis is **bold**.")
	if !strings.Contains(result, "Hello") {
		t.Fatal("rendered markdown should contain heading text")
	}
}

func TestStreamingAppend(t *testing.T) {
	m := markdown.New(80)
	m.Append("# He")
	m.Append("llo\n\nBody text.")
	result := m.View()
	if !strings.Contains(result, "Hello") {
		t.Fatal("streaming view should render accumulated content")
	}
}

func TestEmptyReturnsEmpty(t *testing.T) {
	m := markdown.New(80)
	result := m.Render("")
	if result != "" {
		t.Fatalf("empty input should return empty, got %q", result)
	}
}
```

**Step 2: Run test to verify failure**

Run: `cd masaq && go test ./markdown/ -v`
Expected: FAIL

**Step 3: Implement streaming markdown renderer**

- `New(width)` — creates renderer, initializes Glamour `TermRenderer` with auto-style and word wrap
- `Render(md)` — one-shot render of complete markdown via Glamour
- `Append(text)` — accumulates streaming text chunks into a `strings.Builder`
- `View()` — renders the accumulated buffer via Glamour (called on each TUI tick)
- `Reset()` — clears the buffer
- `Content()` — returns raw accumulated text

Glamour handles the heavy lifting. The streaming adapter simply accumulates partial markdown and re-renders. In practice, the TUI's tick rate (60fps) limits how often View() is called, so re-rendering is bounded.

**Step 4: Run test**

Run: `cd masaq && go test ./markdown/ -v`
Expected: PASS

**Step 5: Commit**

```bash
git add masaq/markdown/
git commit -m "feat(masaq): Glamour-based streaming markdown renderer"
```

<verify>
- run: `cd masaq && go test ./markdown/ -v`
  expect: exit 0
</verify>

---

### Task 7: Masaq question widget — structured multi-choice with previews

**Files:**
- Create: `masaq/question/question.go`
- Create: `masaq/question/question_test.go`

**Step 1: Write the failing test**

```go
package question_test

import (
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/mistakeknot/masaq/question"
)

func TestNewQuestion(t *testing.T) {
	q := question.New("Which approach?", []question.Option{
		{Label: "Option A", Description: "First approach"},
		{Label: "Option B", Description: "Second approach"},
	})
	if q.Question() != "Which approach?" {
		t.Fatalf("got %q", q.Question())
	}
	if len(q.Options()) != 2 {
		t.Fatalf("got %d options", len(q.Options()))
	}
}

func TestNavigation(t *testing.T) {
	q := question.New("Pick:", []question.Option{
		{Label: "A"}, {Label: "B"}, {Label: "C"},
	})
	if q.Cursor() != 0 {
		t.Fatalf("initial cursor=%d, want 0", q.Cursor())
	}
	q, _ = q.Update(tea.KeyMsg{Type: tea.KeyDown})
	if q.Cursor() != 1 {
		t.Fatalf("after down cursor=%d, want 1", q.Cursor())
	}
}

func TestSelectSendsMsg(t *testing.T) {
	q := question.New("Pick:", []question.Option{
		{Label: "A"}, {Label: "B"},
	})
	_, cmd := q.Update(tea.KeyMsg{Type: tea.KeyEnter})
	if cmd == nil {
		t.Fatal("enter should produce a command")
	}
	msg := cmd()
	selected, ok := msg.(question.SelectedMsg)
	if !ok {
		t.Fatalf("expected SelectedMsg, got %T", msg)
	}
	if selected.Index != 0 || selected.Label != "A" {
		t.Fatalf("got index=%d label=%q", selected.Index, selected.Label)
	}
}
```

**Step 2: Run test to verify failure**

Run: `cd masaq && go test ./question/ -v`
Expected: FAIL

**Step 3: Implement question widget**

Bubble Tea sub-model modeled on Claude Code's AskUserQuestion. Key types:

- `Option` — Label, Description, Preview (optional side-pane content)
- `SelectedMsg` — sent when user selects (Index, Label, Notes)
- `Model` — question text, options, cursor, selected state

Features:
- Up/Down navigation with wrap-around
- Number key shortcuts (1-9) for quick selection
- Enter to confirm selection, sends `SelectedMsg` via tea.Cmd
- Styled rendering: question in Primary+Bold, cursor indicator (>), selected in Success, descriptions in Subtext
- Preview pane (when Option.Preview is set): side-by-side layout with options on left, preview content on right

**Step 4: Run test**

Run: `cd masaq && go test ./question/ -v`
Expected: PASS

**Step 5: Commit**

```bash
git add masaq/question/
git commit -m "feat(masaq): structured question widget with descriptions and previews"
```

<verify>
- run: `cd masaq && go test ./question/ -v`
  expect: exit 0
</verify>

---

### Task 8: Masaq compact formatter — tool call summaries

**Files:**
- Create: `masaq/compact/compact.go`
- Create: `masaq/compact/compact_test.go`

**Step 1: Write the failing test**

```go
package compact_test

import (
	"strings"
	"testing"

	"github.com/mistakeknot/masaq/compact"
)

func TestCompactSummary(t *testing.T) {
	c := compact.New(80)
	result := c.FormatToolCall("read", `{"file_path": "/home/mk/foo.go"}`, "file contents...", false)
	if !strings.Contains(result, "read") {
		t.Fatal("compact should contain tool name")
	}
	if !strings.Contains(result, "foo.go") {
		t.Fatal("compact should extract filename from params")
	}
}

func TestVerboseMode(t *testing.T) {
	c := compact.New(80)
	c.SetVerbose(true)
	result := c.FormatToolCall("bash", `{"command": "go test ./..."}`, "PASS", false)
	if !strings.Contains(result, "PASS") {
		t.Fatal("verbose mode should include output")
	}
}

func TestErrorAlwaysExpanded(t *testing.T) {
	c := compact.New(80)
	result := c.FormatToolCall("bash", `{"command": "go build"}`, "compilation error", true)
	if !strings.Contains(result, "compilation error") {
		t.Fatal("errors should always show output regardless of compact mode")
	}
}
```

**Step 2: Run test to verify failure**

Run: `cd masaq && go test ./compact/ -v`
Expected: FAIL

**Step 3: Implement compact formatter**

- `New(width)` constructor
- `SetVerbose(bool)` / `IsVerbose()` — toggle mode
- `FormatToolCall(name, paramsJSON, output, isError)` — renders tool call

Rendering rules:
- Compact mode (default): tool name in Info+Bold, extracted summary param in Subtext, one line
- Verbose mode: header + full output in Muted color, truncated at 2000 chars
- Errors: always expanded regardless of mode, output in Error color, truncated at 500 chars

Summary extraction per tool:
- read/write/edit: `filepath.Base(file_path)`
- bash: command text (truncated at 60 chars)
- grep: `/pattern/`
- glob: pattern

Gotcha: When extracting summaries from JSON params, use `json.Unmarshal` into `map[string]interface{}`. If iterating map keys for any caching, sort them first (Prior Learnings).

**Step 4: Run test**

Run: `cd masaq && go test ./compact/ -v`
Expected: PASS

**Step 5: Commit**

```bash
git add masaq/compact/
git commit -m "feat(masaq): compact/verbose tool call formatter"
```

<verify>
- run: `cd masaq && go test ./compact/ -v`
  expect: exit 0
</verify>

---

### Task 9: Smart Trust engine — pattern rules + progressive learning

**Files:**
- Create: `os/Skaffen/internal/trust/trust.go`
- Create: `os/Skaffen/internal/trust/rules.go`
- Create: `os/Skaffen/internal/trust/trust_test.go`

**Step 1: Write the failing test**

```go
package trust_test

import (
	"testing"

	"github.com/mistakeknot/Skaffen/internal/trust"
)

func TestAutoAllowSafeTools(t *testing.T) {
	e := trust.NewEvaluator(nil)
	tests := []struct {
		tool string
		want trust.Decision
	}{
		{"read", trust.Allow},
		{"write", trust.Allow},
		{"edit", trust.Allow},
		{"grep", trust.Allow},
		{"glob", trust.Allow},
		{"ls", trust.Allow},
	}
	for _, tt := range tests {
		got := e.Evaluate(tt.tool, `{}`)
		if got != tt.want {
			t.Errorf("Evaluate(%q) = %v, want %v", tt.tool, got, tt.want)
		}
	}
}

func TestAlwaysBlockDangerous(t *testing.T) {
	e := trust.NewEvaluator(nil)
	got := e.Evaluate("bash", `{"command": "rm -rf /"}`)
	if got != trust.Block {
		t.Errorf("rm -rf should be Block, got %v", got)
	}
	got = e.Evaluate("bash", `{"command": "sudo apt install"}`)
	if got != trust.Block {
		t.Errorf("sudo should be Block, got %v", got)
	}
}

func TestPromptOnceForGrayArea(t *testing.T) {
	e := trust.NewEvaluator(nil)
	got := e.Evaluate("bash", `{"command": "npm install express"}`)
	if got != trust.Prompt {
		t.Errorf("npm install should be Prompt, got %v", got)
	}
}

func TestBashSafeCommands(t *testing.T) {
	e := trust.NewEvaluator(nil)
	safe := []string{"go test ./...", "git status", "git diff", "go build ./..."}
	for _, cmd := range safe {
		got := e.Evaluate("bash", `{"command": "`+cmd+`"}`)
		if got != trust.Allow {
			t.Errorf("bash(%q) = %v, want Allow", cmd, got)
		}
	}
}

func TestLearnedOverride(t *testing.T) {
	e := trust.NewEvaluator(nil)
	e.Learn("bash:npm install*", trust.Allow, trust.ScopeProject)
	got := e.Evaluate("bash", `{"command": "npm install express"}`)
	if got != trust.Allow {
		t.Errorf("learned override should Allow, got %v", got)
	}
}
```

**Step 2: Run test to verify failure**

Run: `cd os/Skaffen && go test ./internal/trust/ -v`
Expected: FAIL

**Step 3: Implement trust evaluator**

Two files:

**trust.go** — Core types and evaluator:
- `Decision` enum: Allow, Prompt, Block
- `Scope` enum: ScopeSession, ScopeProject, ScopeGlobal
- `Override` struct: Pattern, Decision, Scope, Count (for auto-promotion)
- `Config` struct: holds `[]Override` from trust.toml
- `Evaluator` struct: overrides slice + session map
- `NewEvaluator(cfg *Config)` — nil config = built-in rules only
- `Evaluate(toolName, paramsJSON)` — three-step pipeline:
  1. Check session overrides (exact match)
  2. Check learned overrides (glob match via `filepath.Match`)
  3. Check built-in rules (see rules.go)
- `Learn(pattern, decision, scope)` — adds override
- `buildKey(toolName, paramsJSON)` — returns lookup key (e.g., "bash:go test ./...")

**rules.go** — Built-in pattern rules:
- Tier 1 (Allow): read, write, edit, grep, glob, ls tools; bash with safe prefixes (go test, go build, git status, git diff, git log, ls, cat, head, tail, wc, echo, mkdir)
- Tier 3 (Block): bash with dangerous patterns (rm -rf, sudo, chmod 777, curl, wget, nc/ncat, .env modifications)
- Tier 2 (Prompt): everything else
- `matchGlob(pattern, key)` — exact match then `filepath.Match`

**Step 4: Run test**

Run: `cd os/Skaffen && go test ./internal/trust/ -v`
Expected: PASS

**Step 5: Commit**

```bash
git add os/Skaffen/internal/trust/
git commit -m "feat(skaffen): smart trust engine with pattern rules + progressive learning"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/trust/ -v`
  expect: exit 0
</verify>

---

### Task 10: Agent streaming callback — expose stream events for TUI

**Files:**
- Create: `os/Skaffen/internal/agent/streaming.go`
- Modify: `os/Skaffen/internal/agent/agent.go:9-19` — add `streamCB` field
- Modify: `os/Skaffen/internal/agent/loop.go:56-63` — iterate events instead of Collect()
- Create: `os/Skaffen/internal/agent/streaming_test.go`

**Step 1: Write the failing test**

Test that when `WithStreamCallback` is set, the callback receives events during the agent loop. Use the existing mock provider from `agent_test.go`.

**Step 2: Create streaming.go**

Define the callback types:
- `StreamEventType` enum: StreamText, StreamToolStart, StreamToolComplete, StreamTurnComplete, StreamPhaseChange
- `StreamEvent` struct: Type, Text, ToolName, ToolParams, ToolResult, IsError, Phase, Usage, TurnNumber
- `StreamCallback` type: `func(StreamEvent)`
- `WithStreamCallback(cb)` Option

**Step 3: Modify agent.go**

Add `streamCB StreamCallback` field to `Agent` struct. Default to nil in `New()`.

**Step 4: Modify loop.go**

In `Run()`, when `a.streamCB != nil`, replace `stream.Collect()` with event-by-event iteration:
- For each `EventTextDelta`: call `streamCB(StreamEvent{Type: StreamText, Text: ev.Text})`
- For each `EventToolUseStart`: call `streamCB(StreamEvent{Type: StreamToolStart, ToolName: ev.Name})`
- After executing each tool: call `streamCB(StreamEvent{Type: StreamToolComplete, ToolName: tc.Name, ToolResult: result.Content, IsError: result.IsError})`
- At end of turn: call `streamCB(StreamEvent{Type: StreamTurnComplete, Usage: collected.Usage, TurnNumber: turn})`

When `streamCB` is nil, keep existing `Collect()` behavior unchanged.

**Step 5: Run tests**

Run: `cd os/Skaffen && go test ./internal/agent/ -v -race`
Expected: PASS (existing tests unchanged + new streaming test)

**Step 6: Commit**

```bash
git add os/Skaffen/internal/agent/
git commit -m "feat(skaffen): streaming callback interface for TUI real-time rendering"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/agent/ -v`
  expect: exit 0
</verify>

---

### Task 11: Skaffen TUI app — main REPL model composing Masaq components

**Files:**
- Create: `os/Skaffen/internal/tui/app.go`
- Create: `os/Skaffen/internal/tui/chat.go`
- Create: `os/Skaffen/internal/tui/status.go`
- Create: `os/Skaffen/internal/tui/prompt.go`

**Step 1: Create app.go — main Bubble Tea model**

The REPL app model composes masaq components:
- `Config` struct: Agent, Trust evaluator, Session ID, Verbose flag
- `Run(cfg Config) error` — entry point, creates `tea.NewProgram` with `WithAltScreen()`
- `appModel` struct: width/height, viewport (masaq), compact (masaq), markdown (masaq), keys (masaq), agent, trust, status, prompt sub-models
- `Init()` — returns prompt init cmd
- `Update(msg)` — handles WindowSizeMsg (allocate: status=1 line, prompt=3 lines, rest=viewport), KeyMsg (ctrl+c=quit), delegates to prompt
- `View()` — renders viewport + status bar + prompt vertically

**Step 2: Create chat.go — conversation rendering**

Manages the list of chat messages and renders them into the viewport:
- User messages styled with Primary color
- Assistant messages rendered via masaq/markdown
- Tool calls rendered via masaq/compact (compact by default, expanded on demand)
- Diffs rendered via masaq/diff
- Phase transitions as styled system messages
- Error messages always expanded

**Step 3: Create status.go — status bar**

Renders 5 items: phase | model | cost | context% | turns
- Phase in Primary+Bold
- Cost color: green < $0.50, yellow < $2.00, red >= $2.00
- Context color: green < 50%, yellow < 80%, red >= 80%
- Background: Surface0

**Step 4: Create prompt.go — input composer**

Multi-line text input:
- Enter = submit (sends user message to agent loop)
- Shift+Enter = newline
- @ triggers file search overlay (Task 18)
- / prefix triggers slash command parsing (Task 15)
- Ctrl+C = quit

**Step 5: Commit**

```bash
git add os/Skaffen/internal/tui/
git commit -m "feat(skaffen): TUI REPL with chat viewport, status bar, and input composer"
```

<verify>
- run: `cd os/Skaffen && go build ./...`
  expect: exit 0
</verify>

---

### Task 12: Wire TUI mode into main.go — default mode dispatch

**Files:**
- Modify: `os/Skaffen/cmd/skaffen/main.go`
- Modify: `os/Skaffen/go.mod`

**Step 1: Update go.mod with masaq dependency**

Add `replace` directive for local development:

```
require github.com/mistakeknot/masaq v0.0.0
replace github.com/mistakeknot/masaq => ../../masaq
```

Then `go mod tidy`.

**Step 2: Add --mode flag to main.go**

Add `flagMode = flag.String("mode", "tui", "Execution mode: tui (default), print")` alongside existing flags. Add `-c` flag for resume-last and `-r` for resume-specific.

**Step 3: Modify main() dispatch**

```go
switch *flagMode {
case "tui":
    if err := runTUI(); err != nil { ... }
case "print":
    if err := runPrint(); err != nil { ... }
default:
    fmt.Fprintf(os.Stderr, "unknown mode %q\n", *flagMode)
}
```

Rename existing `run()` to `runPrint()`. Create `runTUI()` that:
1. Sets up provider (same as runPrint)
2. Sets up tool registry (same)
3. Creates trust evaluator (new): `trust.NewEvaluator(nil)` for now
4. Creates agent with streaming callback
5. Calls `tui.Run(tui.Config{...})`

**Step 4: Build**

Run: `cd os/Skaffen && go build ./cmd/skaffen/`
Expected: Build succeeds

**Step 5: Test headless mode still works**

Run: `cd os/Skaffen && go test ./cmd/skaffen/ -v`
Expected: PASS

**Step 6: Commit**

```bash
git add os/Skaffen/
git commit -m "feat(skaffen): wire TUI as default mode, print mode via --mode=print"
```

<verify>
- run: `cd os/Skaffen && go build ./cmd/skaffen/`
  expect: exit 0
- run: `cd os/Skaffen && go test ./cmd/skaffen/ -v`
  expect: exit 0
</verify>

---

### Task 13: TUI tool call approval — smart trust UI integration

**Files:**
- Create: `os/Skaffen/internal/tui/toolcall.go`
- Modify: `os/Skaffen/internal/agent/loop.go` — add ToolApproval callback

**Step 1: Add ToolApproval callback to agent**

Add `ToolApproval func(toolName, paramsJSON string) (approved bool)` to Agent struct and Option constructor. When set, the agent loop calls it before executing each tool. If not set, all tools execute (existing behavior for print mode).

**Step 2: Implement toolcall.go**

When the TUI receives a `StreamToolStart` event:
1. Call `trust.Evaluate(toolName, paramsJSON)`
2. If `Allow` → return immediately, render compact summary
3. If `Block` → render error: "Blocked: [tool] [reason]", skip execution
4. If `Prompt` → render question widget:
   - Question: "Allow [tool] [summary]?"
   - Options: [y]es, [n]o, [a]lways (project), [s]ession
   - Block until answered
   - On approval: render compact summary, call `trust.Learn()` based on scope choice
   - On rejection: skip, render "Skipped: [tool]"

After 3 approvals of the same pattern without explicit "always", show notification: "Auto-allowing [pattern] (approved 3 times). Run /trust to review."

**Step 3: Commit**

```bash
git add os/Skaffen/internal/tui/toolcall.go os/Skaffen/internal/agent/loop.go
git commit -m "feat(skaffen): smart trust approval UI with inline learning"
```

<verify>
- run: `cd os/Skaffen && go build ./...`
  expect: exit 0
</verify>

---

### Task 14: Phase indicator + transition events

**Files:**
- Create: `os/Skaffen/internal/tui/phase.go`

**Step 1: Implement phase rendering**

Two rendering locations:

1. **Status bar** — phase label updates from StreamPhaseChange events. Color-coded:
   - brainstorm = Info (#7dcfff)
   - plan = Secondary (#bb9af7)
   - build = Success (#9ece6a)
   - review = Warning (#e0af68)
   - ship = Primary (#7aa2f7)

2. **Chat stream** — phase transitions appear as styled system messages:
   ```
   ─── build → review ───
   Decisions: implemented feature X
   Artifacts: internal/tui/app.go, internal/tui/chat.go
   ```

The chat model receives `StreamPhaseChange` events and appends a formatted transition message to the viewport.

**Step 2: Commit**

```bash
git add os/Skaffen/internal/tui/phase.go
git commit -m "feat(skaffen): OODARC phase indicator in status bar + chat transitions"
```

<verify>
- run: `cd os/Skaffen && go build ./...`
  expect: exit 0
</verify>

---

### Task 15: Slash commands — /compact, /verbose, /phase, /undo, /help, /sessions

**Files:**
- Create: `os/Skaffen/internal/tui/commands.go`
- Create: `os/Skaffen/internal/tui/commands_test.go`

**Step 1: Write the failing test**

```go
package tui_test

func TestParseSlashCommand(t *testing.T) {
    tests := []struct {
        input string
        cmd   string
        args  []string
    }{
        {"/compact", "compact", nil},
        {"/verbose", "verbose", nil},
        {"/phase", "phase", nil},
        {"/undo", "undo", nil},
        {"/help", "help", nil},
        {"/sessions", "sessions", nil},
    }
    // ... parse and assert
}
```

**Step 2: Implement command parser and handlers**

When the input composer detects a `/` prefix:
- `/compact` — `compact.SetVerbose(false)`, system message: "Switched to compact mode"
- `/verbose` — `compact.SetVerbose(true)`, system message: "Switched to verbose mode"
- `/phase` — system message showing current phase name
- `/advance` — call `agent.AdvancePhase()`, show transition event
- `/undo` — call `git.Undo()`, show result
- `/commit` — call `git.AutoCommit()`, show hash
- `/ship` — call `git.Ship()`, show result
- `/sessions` — list sessions from `~/.skaffen/sessions/`, show picker
- `/help` — render keybinding help overlay

Each command returns a result string rendered as a system message in the chat stream.

**Step 3: Run test**

Run: `cd os/Skaffen && go test ./internal/tui/ -v -run TestParseSlash`
Expected: PASS

**Step 4: Commit**

```bash
git add os/Skaffen/internal/tui/commands.go os/Skaffen/internal/tui/commands_test.go
git commit -m "feat(skaffen): slash commands — /compact, /verbose, /phase, /undo, /help"
```

<verify>
- run: `cd os/Skaffen && go build ./...`
  expect: exit 0
</verify>

---

### Task 16: Session resume with smart picker

**Files:**
- Create: `os/Skaffen/internal/session/picker.go`
- Create: `os/Skaffen/internal/session/picker_test.go`
- Modify: `os/Skaffen/cmd/skaffen/main.go` — add -c and -r flags

**Step 1: Write the failing test**

```go
package session_test

func TestListSessions(t *testing.T) {
    dir := t.TempDir()
    // Write a few session JSONL files
    // Call picker.ListSessions(dir)
    // Assert returns sorted by modification time, most recent first
}

func TestSessionMetadata(t *testing.T) {
    // Write a session file, parse metadata (turn count, initial prompt, last timestamp)
}
```

**Step 2: Implement session picker**

- `ListSessions(dir)` — reads `~/.skaffen/sessions/*.jsonl`, returns `[]SessionInfo` sorted by mtime desc
- `SessionInfo` — ID, LastModified, TurnCount, InitialPrompt (first 80 chars of first user message)
- `ShowPicker(sessions)` — creates a masaq/question widget:
  - [1] New session
  - [2] Resume last: "initial prompt text..." (N turns, 2h ago)
  - [3] Browse all sessions

**Step 3: Add -c and -r flags to main.go**

- `-c` — resume last session (most recent by mtime)
- `-r <id>` — resume specific session by ID
- No flag + TUI mode → show picker on startup

**Step 4: Run test**

Run: `cd os/Skaffen && go test ./internal/session/ -v`
Expected: PASS

**Step 5: Commit**

```bash
git add os/Skaffen/internal/session/ os/Skaffen/cmd/skaffen/main.go
git commit -m "feat(skaffen): session resume with smart picker and -c/-r flags"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/session/ -v`
  expect: exit 0
</verify>

---

### Task 17: Git-native integration — auto-commit, /undo, /ship

**Files:**
- Create: `os/Skaffen/internal/git/git.go`
- Create: `os/Skaffen/internal/git/git_test.go`

**Step 1: Write the failing test**

```go
package git_test

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	skgit "github.com/mistakeknot/Skaffen/internal/git"
)

func TestAutoCommit(t *testing.T) {
	dir := t.TempDir()
	run(t, dir, "git", "init")
	run(t, dir, "git", "config", "user.email", "test@test.com")
	run(t, dir, "git", "config", "user.name", "Test")

	g := skgit.New(dir)
	os.WriteFile(filepath.Join(dir, "test.go"), []byte("package main"), 0644)

	hash, err := g.AutoCommit("test.go", "create test.go")
	if err != nil {
		t.Fatalf("AutoCommit: %v", err)
	}
	if hash == "" {
		t.Fatal("expected commit hash")
	}
}

func TestUndoReverts(t *testing.T) {
	dir := t.TempDir()
	run(t, dir, "git", "init")
	run(t, dir, "git", "config", "user.email", "test@test.com")
	run(t, dir, "git", "config", "user.name", "Test")

	g := skgit.New(dir)

	// Create initial file + commit
	os.WriteFile(filepath.Join(dir, "a.go"), []byte("v1"), 0644)
	g.AutoCommit("a.go", "v1")

	// Modify + commit
	os.WriteFile(filepath.Join(dir, "a.go"), []byte("v2"), 0644)
	g.AutoCommit("a.go", "v2")

	// Undo
	if err := g.Undo(); err != nil {
		t.Fatalf("Undo: %v", err)
	}

	// Verify file reverted
	data, _ := os.ReadFile(filepath.Join(dir, "a.go"))
	if string(data) != "v1" {
		t.Fatalf("expected v1 after undo, got %q", string(data))
	}
}

func run(t *testing.T, dir, name string, args ...string) {
	t.Helper()
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	if err := cmd.Run(); err != nil {
		t.Fatalf("%s %v: %v", name, args, err)
	}
}
```

**Step 2: Run test to verify failure**

Run: `cd os/Skaffen && go test ./internal/git/ -v`
Expected: FAIL

**Step 3: Implement git operations**

- `New(dir)` — creates Git instance for working directory
- `AutoCommit(file, message)` — `git add <file> && git commit -m <message>`, returns commit hash
- `Undo()` — `git revert HEAD --no-edit`
- `Ship(message)` — squash recent commits (soft reset to merge base, then caller commits)
- `IsRepo()` — checks if dir is a git repo
- `Status()` — returns `git status --short` output

All operations use `exec.Command("git", ...)` with `cmd.Dir` set.

**Step 4: Run test**

Run: `cd os/Skaffen && go test ./internal/git/ -v`
Expected: PASS

**Step 5: Commit**

```bash
git add os/Skaffen/internal/git/
git commit -m "feat(skaffen): git-native integration — auto-commit, undo, ship"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/git/ -v`
  expect: exit 0
</verify>

---

### Task 18: @-file mentions — fuzzy file search in prompt

**Files:**
- Modify: `os/Skaffen/internal/tui/prompt.go`

**Step 1: Implement @-mention detection and file search**

When the user types `@` in the input composer:
1. Start capturing the partial filename after `@`
2. Walk the project tree (excluding `.git/`, `node_modules/`, `vendor/`)
3. Fuzzy-match the partial against file paths (simple `strings.Contains` for v0.1)
4. Render matches in a dropdown below the cursor (max 10 results)
5. Up/Down to navigate, Enter to select, Esc to cancel
6. On select: insert the full relative path at cursor position
7. The path is added to the user message context (the agent receives it as an @-mention)

**Step 2: Commit**

```bash
git add os/Skaffen/internal/tui/prompt.go
git commit -m "feat(skaffen): @-file mentions with fuzzy search in input composer"
```

<verify>
- run: `cd os/Skaffen && go build ./...`
  expect: exit 0
</verify>

---

### Task 19: Integration test — full TUI smoke test

**Files:**
- Create: `os/Skaffen/internal/tui/app_test.go`

**Step 1: Write integration test**

```go
package tui_test

import (
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/mistakeknot/Skaffen/internal/tui"
)

func TestAppModelLifecycle(t *testing.T) {
	// Create app with nil agent/trust (test mode)
	m := tui.NewForTest()

	// Window resize
	model, _ := m.Update(tea.WindowSizeMsg{Width: 120, Height: 40})
	view := model.(tui.TestableModel).View()
	if view == "" {
		t.Fatal("view should not be empty after resize")
	}

	// Status bar should contain default phase
	if !strings.Contains(view, "build") {
		t.Fatal("status bar should show default phase")
	}
}
```

The test exercises Masaq component composition without requiring a real terminal or agent.

**Step 2: Run test**

Run: `cd os/Skaffen && go test ./internal/tui/ -v`
Expected: PASS

**Step 3: Commit**

```bash
git add os/Skaffen/internal/tui/app_test.go
git commit -m "test(skaffen): TUI integration smoke test"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/tui/ -v`
  expect: exit 0
</verify>

---

### Task 20: Update PRD — add F8 acceptance criteria

**Files:**
- Modify: `docs/prds/2026-03-11-skaffen-go-rewrite.md:114-136`

**Step 1: Add F8 section after F7**

Insert after the F7 section (after line ~127):

```markdown
### F8: TUI Mode

**What:** Standalone conversational REPL using Bubble Tea, composing Masaq shared components. Default mode when running `skaffen` with no args.

**Acceptance criteria:**
- [ ] `skaffen` (default) launches TUI REPL with chat viewport, input composer, status bar
- [ ] `skaffen run --mode print` preserves headless streaming behavior
- [ ] Smart trust: auto-allows safe tools, prompts for gray-area, blocks dangerous — with progressive learning
- [ ] Streaming markdown rendered via Glamour adapter
- [ ] Diffs rendered with Chroma syntax highlighting and [y]/[n] approval keys
- [ ] Tool calls compact by default, expandable via Enter/d
- [ ] Status bar shows: phase | model | cost | context% | turns
- [ ] Session resume via `-c` (last) or `-r <id>` (specific) with smart picker
- [ ] Slash commands: /compact, /verbose, /phase, /advance, /undo, /commit, /sessions, /help
- [ ] @-file mentions with fuzzy search in input composer
- [ ] Git-native: auto-commit per edit, /undo = git revert, /ship = squash
- [ ] OODARC phase transitions visible in status bar and chat stream
```

**Step 2: Update non-goals section**

Change line 130 from "TUI. Skaffen starts headless..." to:
"~~TUI.~~ *Reversed: F8 adds TUI mode as default. Print mode remains via `--mode print`.*"

**Step 3: Commit**

```bash
git add docs/prds/2026-03-11-skaffen-go-rewrite.md
git commit -m "docs: add F8 TUI Mode to Skaffen PRD, reverse No TUI non-goal"
```

<verify>
- run: `grep -c "F8" docs/prds/2026-03-11-skaffen-go-rewrite.md`
  expect: contains "1"
</verify>

---

### Task 21: Final integration — build + test + smoke

**Step 1: Build everything**

```bash
cd masaq && go build ./...
cd os/Skaffen && go build ./cmd/skaffen/
```

**Step 2: Run all tests with race detector**

```bash
cd masaq && go test ./... -race
cd os/Skaffen && go test ./... -race
```

**Step 3: Manual smoke test — headless mode**

```bash
cd os/Skaffen && go run ./cmd/skaffen/ --mode print -p "Hello"
```

Should work identically to pre-TUI behavior.

**Step 4: Commit any integration fixes**

```bash
git add masaq/ os/Skaffen/
git commit -m "fix: integration fixes from full build + test pass"
```

<verify>
- run: `cd masaq && go test ./... -race`
  expect: exit 0
- run: `cd os/Skaffen && go test ./... -race`
  expect: exit 0
- run: `cd os/Skaffen && go build ./cmd/skaffen/`
  expect: exit 0
</verify>
