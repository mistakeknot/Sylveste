---
artifact_type: plan
bead: Demarch-6qb
stage: planned
---
# Plan: @-file mentions with fuzzy search in input composer

## Goal

Implement the last unchecked non-deferred F8 acceptance criterion: `@-file mentions with fuzzy search in input composer`. When the user types `@` in the prompt, show a filterable file list. Selecting a file inserts `@path` which gets expanded to file content before sending to the LLM.

## Prior Patterns

- Approval overlay in `app.go:203-232` — demonstrates overlay rendering + message delegation pattern
- `question.Model` from masaq — existing popup widget pattern to follow
- `prompt.go` — simple 91-line model, clean extension point

## Tasks

### 1. File walker utility (`internal/tui/filepicker.go`)
- [x] `walkFiles(root string, maxDepth int) []string` — returns relative paths
- [x] Exclude: `.git/`, `node_modules/`, `vendor/`, `__pycache__/`, `.beads/`, hidden dirs
- [x] Cache results (invalidated when picker opens)
- [x] `fuzzyMatch(pattern, candidate string) (bool, int)` — case-insensitive substring match with score (earlier match = higher score)

### 2. File picker model (`internal/tui/filepicker.go`)
- [x] `filePickerModel` struct: items, filtered, cursor, pattern, visible
- [x] Update: arrow keys navigate, typing filters, Enter selects, Escape cancels
- [x] View: renders max 10 matching items with cursor highlight
- [x] `filePickerSelectedMsg{Path string}` and `filePickerCancelMsg{}` message types

### 3. Wire into prompt (`internal/tui/prompt.go`)
- [x] Detect `@` keystroke → activate file picker with current workDir
- [x] On selection: insert `@relative/path` at cursor position, close picker
- [x] On cancel: close picker, resume normal input

### 4. Expand @-mentions before submit (`internal/tui/app.go`)
- [x] In `submitMsg` handler: regex-find `@(\S+)` patterns in text
- [x] Read each referenced file, inject content as `[File: path]\n<content>\n[/File]`
- [x] If file doesn't exist or is too large (>50KB), leave `@path` as-is and show warning
- [x] Pass expanded text to agent, display original text in viewport

### 5. Tests
- [x] `filepicker_test.go`: walkFiles excludes hidden dirs, fuzzyMatch scoring, picker navigation, selection/cancel messages
- [x] `prompt_test.go`: @-trigger activates picker, selection inserts path, cancel resumes
- [x] `app_test.go`: @-expansion in submit, missing file handling, large file warning

### 6. PRD update
- [x] Check off `@-file mentions with fuzzy search in input composer` in PRD

## Estimated scope
~200 lines new code (filepicker.go) + ~40 lines prompt.go changes + ~30 lines app.go changes + ~150 lines tests. Total: ~420 lines.
