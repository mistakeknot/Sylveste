---
artifact_type: plan
bead: Demarch-hop
stage: design
prd: docs/prds/2026-03-11-skaffen-go-rewrite.md
requirements:
  - "Tool interface: Name(), Description(), Schema(), Execute(ctx, params) → ToolResult"
  - "Phase-gated tool registry with runtime registration"
  - "7 built-in tools: read, write, edit, bash, grep, glob, ls"
  - "Phase gate matrix: brainstorm=read-only, build=full, review=read+test, ship=git-only"
---
# F2: Core Tool System with Phase Gating

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Demarch-hop
**Goal:** Tool interface, phase-aware registry, and 7 built-in tools that the OODARC agent loop (F3) will use to execute actions.

**Architecture:** The `internal/tool/` package defines a `Tool` interface and a `Registry` that maps phase → available tools. Each built-in tool is a separate file implementing the interface. The registry returns `provider.ToolDef` schemas for LLM tool_use and dispatches `Execute()` calls by name. Phase gating is a simple allow-list map — no tools are created/destroyed per phase, just filtered.

**Tech Stack:** Go 1.22, `os` for file tools, `os/exec` for bash/grep, `filepath.Glob` for glob, `encoding/json` for schemas. No external dependencies.

**Patterns from F1:** Follow the same conventions — interfaces in the package root, implementations in separate files, table-driven tests, no external deps.

---

## Must-Haves

**Truths** (observable behaviors):
- `go test ./internal/tool/...` passes
- Registry returns only read-only tools for brainstorm phase
- Registry returns all tools for build phase
- Each tool's `Schema()` returns valid JSON Schema parseable by `json.Unmarshal`
- `read` tool returns file content with line numbers
- `bash` tool respects timeout and truncates output
- `edit` tool rejects non-unique `old_string` matches

**Artifacts** (files that must exist):
- `internal/tool/tool.go` — interface + result types
- `internal/tool/registry.go` — phase-aware registry
- `internal/tool/read.go`, `write.go`, `edit.go`, `bash.go`, `grep.go`, `glob.go`, `ls.go`
- `internal/tool/registry_test.go` — phase gate matrix tests
- `internal/tool/tools_test.go` — per-tool unit tests

**Key Links** (where breakage causes cascading failures):
- `Tool.Schema()` must produce JSON matching `provider.ToolDef.InputSchema` format — F3 passes these to the LLM
- `Registry.Execute(name, params)` must return `ToolResult` with `Content` and `IsError` — F3 builds `tool_result` content blocks from this
- Phase gate must be a hard block — returning a tool in the wrong phase breaks the safety model

---

### Task 1: Define Tool interface and result types ✅

**Files:**
- `internal/tool/tool.go` (new)

**Changes:**

```go
package tool

import (
    "context"
    "encoding/json"
)

// Tool is implemented by each built-in tool.
type Tool interface {
    Name() string
    Description() string
    Schema() json.RawMessage // JSON Schema for input parameters
    Execute(ctx context.Context, params json.RawMessage) ToolResult
}

// ToolResult is the output of a tool execution.
type ToolResult struct {
    Content string // text content returned to the model
    IsError bool   // true if execution failed
}

// Phase represents an OODARC workflow phase.
type Phase string

const (
    PhaseBrainstorm Phase = "brainstorm"
    PhasePlan       Phase = "plan"
    PhaseBuild      Phase = "build"
    PhaseReview     Phase = "review"
    PhaseShip       Phase = "ship"
)
```

**Exit criteria:** `go vet ./internal/tool/` passes.

---

### Task 2: Phase-aware registry ✅

**Files:**
- `internal/tool/registry.go` (new)
- `internal/tool/registry_test.go` (new)

**Changes:**

```go
// Registry holds tools and gates access by phase.
type Registry struct {
    tools map[string]Tool
    gates map[Phase]map[string]bool // phase → tool name → allowed
}

// NewRegistry creates a registry with the default phase gate matrix.
func NewRegistry() *Registry

// Register adds a tool to the registry.
func (r *Registry) Register(t Tool)

// Tools returns the tools available for the given phase as provider.ToolDef slices.
func (r *Registry) Tools(phase Phase) []provider.ToolDef

// Execute runs a tool by name if it's allowed in the given phase.
func (r *Registry) Execute(ctx context.Context, phase Phase, name string, params json.RawMessage) ToolResult

// Get returns a tool by name (ignoring phase). Used for schema introspection.
func (r *Registry) Get(name string) (Tool, bool)
```

Phase gate matrix (hard-coded default):

| Tool | brainstorm | plan | build | review | ship |
|------|-----------|------|-------|--------|------|
| read | ✓ | ✓ | ✓ | ✓ | ✓ |
| glob | ✓ | ✓ | ✓ | ✓ | ✓ |
| grep | ✓ | ✓ | ✓ | ✓ | - |
| ls   | ✓ | ✓ | ✓ | ✓ | ✓ |
| write | - | - | ✓ | - | - |
| edit | - | - | ✓ | - | - |
| bash | - | - | ✓ | ✓ | ✓ |

Notes:
- `review` gets `bash` for running tests
- `ship` gets `bash` for git commands, `read`/`glob`/`ls` for inspection
- `plan` is read-only like brainstorm

`Execute()` on a disallowed tool returns `ToolResult{Content: "tool X not available in phase Y", IsError: true}`.

**Tests:** Table-driven:
- brainstorm: only read, glob, grep, ls available
- build: all 7 tools available
- review: read, glob, grep, ls, bash (no write/edit)
- ship: read, glob, ls, bash (no write/edit/grep)
- Execute disallowed tool returns IsError=true
- Register custom tool, verify it appears in build phase

**Exit criteria:** `go test ./internal/tool/ -run Registry` passes.

---

### Task 3: read tool ✅

**Files:**
- `internal/tool/read.go` (new)

**Changes:**

Reads files with optional offset/limit, returns content with line numbers.

```go
type readParams struct {
    FilePath string `json:"file_path"`
    Offset   int    `json:"offset,omitempty"` // 1-based line number
    Limit    int    `json:"limit,omitempty"`  // max lines to read
}
```

- Default: reads entire file (up to 2000 lines)
- If offset specified: start from that line (1-based)
- If limit specified: read at most that many lines
- Output format: `"    1\tline content\n    2\tline content\n"` (cat -n style, matching Claude Code)
- Error on nonexistent file: `"file not found: <path>"`
- Error on directory: `"path is a directory, not a file: <path>"`

**Exit criteria:** Test reads a temp file with offset/limit, verifies line numbers.

---

### Task 4: write tool ✅

**Files:**
- `internal/tool/write.go` (new)

**Changes:**

Creates or overwrites files.

```go
type writeParams struct {
    FilePath string `json:"file_path"`
    Content  string `json:"content"`
}
```

- Creates parent directories if needed (`os.MkdirAll`)
- Writes atomically: write to temp file, then rename (prevents partial writes)
- Returns: `"wrote N bytes to <path>"`
- Error on empty path: `"file_path is required"`

**Exit criteria:** Test writes to temp dir, reads back, verifies content.

---

### Task 5: edit tool ✅

**Files:**
- `internal/tool/edit.go` (new)

**Changes:**

Exact string replacement with uniqueness validation.

```go
type editParams struct {
    FilePath   string `json:"file_path"`
    OldString  string `json:"old_string"`
    NewString  string `json:"new_string"`
    ReplaceAll bool   `json:"replace_all,omitempty"`
}
```

- Reads file, counts occurrences of `old_string`
- If count == 0: error `"old_string not found in file"`
- If count > 1 and !replace_all: error `"old_string matches N times; use replace_all or provide more context"`
- If count == 1 or replace_all: perform replacement, write file
- Returns: `"replaced N occurrence(s) in <path>"`

**Exit criteria:** Tests for unique match, multiple matches with/without replace_all, not-found case.

---

### Task 6: bash tool ✅

**Files:**
- `internal/tool/bash.go` (new)

**Changes:**

Shell execution with configurable timeout and output truncation.

```go
type bashParams struct {
    Command string `json:"command"`
    Timeout int    `json:"timeout,omitempty"` // seconds, default 120
}

const (
    defaultTimeout   = 120 // seconds
    maxOutputBytes   = 10240 // 10KB
)
```

- Executes via `exec.CommandContext(ctx, "bash", "-c", command)`
- Captures combined stdout+stderr
- Truncates output at `maxOutputBytes` with `"\n... (truncated)"` suffix
- On timeout: kills process, returns error with partial output
- Returns exit code in output: `"exit code: 0\n<output>"` or `"exit code: 1\n<output>"`
- Context cancellation kills the subprocess

**Exit criteria:** Tests: successful command, non-zero exit, timeout (use `sleep 10` with 1s timeout), output truncation.

---

### Task 7: grep tool ✅

**Files:**
- `internal/tool/grep.go` (new)

**Changes:**

Ripgrep wrapper.

```go
type grepParams struct {
    Pattern    string `json:"pattern"`
    Path       string `json:"path,omitempty"`       // default "."
    Glob       string `json:"glob,omitempty"`       // e.g., "*.go"
    OutputMode string `json:"output_mode,omitempty"` // "content", "files_with_matches" (default), "count"
}
```

- Shells out to `rg` (ripgrep)
- Builds args based on params: `rg <pattern> <path> --glob <glob> -l` (for files_with_matches) etc.
- If `rg` not found: fallback to `grep -r` with reduced functionality
- Truncates output at 10KB
- Returns raw output from rg

**Exit criteria:** Test with temp directory containing files, verify pattern matching works. Skip if `rg` not available.

---

### Task 8: glob tool ✅

**Files:**
- `internal/tool/glob.go` (new)

**Changes:**

File pattern matching sorted by modification time.

```go
type globParams struct {
    Pattern string `json:"pattern"`
    Path    string `json:"path,omitempty"` // base directory, default "."
}
```

- Uses `filepath.Glob` for matching
- Sorts results by modification time (most recent first)
- Returns one path per line
- If no matches: `"no files matching pattern"`

**Exit criteria:** Test with temp directory, verify sorting by mtime.

---

### Task 9: ls tool ✅

**Files:**
- `internal/tool/ls.go` (new)

**Changes:**

Directory listing with basic metadata.

```go
type lsParams struct {
    Path string `json:"path,omitempty"` // default "."
}
```

- Lists directory entries via `os.ReadDir`
- Format per entry: `"<name>  <size>\n"` for files, `"<name>/\n"` for directories
- Directories listed first, then files, both alphabetical
- Error on nonexistent path

**Exit criteria:** Test with temp directory containing files and subdirs.

---

### Task 10: Register all built-in tools and integration test ✅

**Files:**
- `internal/tool/builtin.go` (new)
- `internal/tool/tools_test.go` (new)

**Changes:**

`builtin.go`:
```go
// RegisterBuiltins adds all 7 built-in tools to the registry.
func RegisterBuiltins(r *Registry) {
    r.Register(&ReadTool{})
    r.Register(&WriteTool{})
    r.Register(&EditTool{})
    r.Register(&BashTool{})
    r.Register(&GrepTool{})
    r.Register(&GlobTool{})
    r.Register(&LsTool{})
}
```

`tools_test.go` — integration tests:
- Create registry, register builtins, verify 7 tools present
- Each tool's Schema() returns valid JSON
- Each tool's Name() matches expected string
- Execute read on a real temp file
- Execute write + read roundtrip
- Execute edit with unique replacement
- Execute bash with `echo hello`
- Execute ls on temp directory

**Exit criteria:** `go test ./internal/tool/...` — all tests pass, `go vet` clean.

---

### Task 11: Verify clean build ✅

**Files:** none new

**Changes:**
- `go mod tidy`
- `go vet ./...`
- `go test ./...` (all packages including provider)
- `go build ./cmd/skaffen/`
- Verify no import cycles between `tool` and `provider` packages

**Exit criteria:** `go build ./...` and `go test ./...` pass. Zero import cycles.
