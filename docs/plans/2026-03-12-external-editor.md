# Plan: External Editor Support (Ctrl+G)

**Bead:** Sylveste-6i0.6
**Stage:** executed

## Overview

Add Ctrl+G keybinding to open an external editor (`$EDITOR` / `$VISUAL`) for composing multi-line prompts. All 5 competitors support this (CC/Codex/Amp use Ctrl+G, Gemini uses Ctrl+X, OpenCode uses /editor).

## Tasks

### Task 1: Add editor support to prompt.go
**Files:** `internal/tui/prompt.go`

Add `editing` flag and `editorResultMsg` type. On Ctrl+G:
1. Write current prompt text to a temp file
2. Return `tea.ExecProcess(cmd, func(err) { return editorResultMsg{...} })` — Bubble Tea suspends alt screen, runs editor, resumes
3. On result, read temp file back into prompt, clean up

```go
type editorResultMsg struct {
    Text string
    Err  error
}

func openEditor(currentText string) tea.Cmd {
    editor := os.Getenv("VISUAL")
    if editor == "" {
        editor = os.Getenv("EDITOR")
    }
    if editor == "" {
        editor = "vi"
    }

    f, err := os.CreateTemp("", "skaffen-*.md")
    if err != nil {
        return func() tea.Msg { return editorResultMsg{Err: err} }
    }
    if currentText != "" {
        f.WriteString(currentText)
    }
    f.Close()

    c := exec.Command(editor, f.Name())
    return tea.ExecProcess(c, func(err error) tea.Msg {
        defer os.Remove(f.Name())
        if err != nil {
            return editorResultMsg{Err: err}
        }
        content, readErr := os.ReadFile(f.Name())
        if readErr != nil {
            return editorResultMsg{Err: readErr}
        }
        return editorResultMsg{Text: strings.TrimRight(string(content), "\n")}
    })
}
```

Handle Ctrl+G in prompt Update:
```go
case "ctrl+g":
    return p, openEditor(p.fullText())
```

### Task 2: Wire editorResultMsg into app.go
**Files:** `internal/tui/app.go`

Handle the result in the Update switch:
```go
case editorResultMsg:
    if msg.Err != nil {
        errStyle := lipgloss.NewStyle().Foreground(theme.Current().Semantic().Error.Color())
        m.viewport.AppendContent(errStyle.Render(fmt.Sprintf("Editor error: %v", msg.Err)) + "\n")
        break
    }
    if strings.TrimSpace(msg.Text) != "" {
        m.prompt.input.SetValue(msg.Text)
        m.prompt.input.CursorEnd()
    }
```

Also pass Ctrl+G through in the key handling section (it's not a scroll key, so it reaches the prompt normally).

Update the placeholder text to mention Ctrl+G.

### Task 3: Tests
**Files:** `internal/tui/prompt_test.go`, `internal/tui/app_test.go`

- Test `openEditor` with a mock editor (echo/cat script)
- Test Ctrl+G key detection returns a tea.Cmd
- Test `editorResultMsg` handling in app model
- Test editor fallback chain: VISUAL → EDITOR → vi

## Execution Order

1 → 2 → 3 (sequential)

## Verification

```bash
go test ./internal/tui/... -count=1
go vet ./...
go build ./cmd/skaffen
```
