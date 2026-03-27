---
artifact_type: plan
bead: Sylveste-ome7
stage: design
---
# intermix: Cross-Repo Matrix Evaluation Harness — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Sylveste-ome7
**Goal:** Build a Go MCP plugin that runs Skaffen against unfamiliar repos across a (repo, task) matrix, classifies outcomes with hybrid taxonomy, and generates delta reports with automatic bead creation for failure patterns.

**Architecture:** Go MCP server (`interverse/intermix/`) with 4 stateless tools mirroring interlab's pattern — JSONL persistence, stateless state reconstruction, ic events bridge. Companion Clavain skill (`/evaluate`) drives the loop. Sequential cell execution, subprocess Skaffen spawn, test-based validation.

**Tech Stack:** Go 1.23+, mcp-go v0.32.0, YAML (gopkg.in/yaml.v3), JSONL persistence, bash subprocess execution

---

## Must-Haves

**Truths** (observable behaviors):
- Agent can run `init_matrix` with a YAML manifest and get a campaign created
- Agent can run `run_cell` and get Skaffen spawned against a cloned repo with captured output
- Agent can run `classify_result` and get hybrid taxonomy (fixed category + LLM analysis) written to JSONL
- Agent can run `report_matrix` and get a pass/fail heatmap with failure clustering
- Running the same matrix twice produces a delta report showing fixed/regressed/stable cells
- Failure patterns with ≥2 cells auto-create beads as children of the parent epic

**Artifacts:**
- `interverse/intermix/cmd/intermix-mcp/main.go` exports MCP server entry point
- `interverse/intermix/internal/eval/tools.go` exports `RegisterAll(s *server.MCPServer)`
- `interverse/intermix/internal/eval/state.go` exports `MatrixConfig`, `CellResult`, `MatrixState`, `ReconstructState()`
- `interverse/intermix/internal/eval/runner.go` exports `RunCell()`, `CloneRepo()`, `SpawnSkaffen()`, `RunValidation()`
- `interverse/intermix/internal/eval/classify.go` exports `Classify()`, `Outcome` enum constants
- `interverse/intermix/internal/eval/report.go` exports `GenerateReport()`, `CompareSegments()`, `ClusterFailures()`
- `interverse/intermix/.claude-plugin/plugin.json` — plugin manifest
- `interverse/intermix/bin/launch-mcp.sh` — auto-build launcher

**Key Links:**
- `tools.go` calls `ReconstructState()` before every tool invocation (stateless pattern)
- `run_cell` calls `CloneRepo()` → `SpawnSkaffen()` → `RunValidation()` in sequence
- `report_matrix` calls `ReconstructState()` → `CompareSegments()` → `ClusterFailures()` → bd CLI for bead creation
- `classify_result` reads `.intermix-run.json` (written by `run_cell`) and appends `CellResult` to JSONL

---

### Task 1: Project Scaffold & Plugin Manifest

**Files:**
- Create: `interverse/intermix/cmd/intermix-mcp/main.go`
- Create: `interverse/intermix/go.mod`
- Create: `interverse/intermix/.claude-plugin/plugin.json`
- Create: `interverse/intermix/bin/launch-mcp.sh`
- Create: `interverse/intermix/CLAUDE.md`
- Create: `interverse/intermix/LICENSE`

**Step 1: Initialize Go module**

```bash
mkdir -p interverse/intermix/cmd/intermix-mcp interverse/intermix/internal/eval interverse/intermix/bin interverse/intermix/.claude-plugin
cd interverse/intermix && go mod init github.com/mistakeknot/intermix
```

**Step 2: Write main.go**

```go
package main

import (
	"fmt"
	"os"

	"github.com/mark3labs/mcp-go/server"
	"github.com/mistakeknot/intermix/internal/eval"
)

func main() {
	s := server.NewMCPServer(
		"intermix",
		"0.1.0",
		server.WithToolCapabilities(true),
	)

	eval.RegisterAll(s)

	if err := server.ServeStdio(s); err != nil {
		fmt.Fprintf(os.Stderr, "intermix-mcp: %v\n", err)
		os.Exit(1)
	}
}
```

**Step 3: Write plugin.json**

```json
{
  "name": "intermix",
  "version": "0.1.0",
  "description": "Cross-repo matrix evaluation harness — run Skaffen against unfamiliar codebases, classify outcomes, track failure patterns.",
  "author": { "name": "mistakeknot" },
  "license": "MIT",
  "mcpServers": {
    "intermix": {
      "type": "stdio",
      "command": "${CLAUDE_PLUGIN_ROOT}/bin/launch-mcp.sh",
      "args": []
    }
  },
  "skills": [
    "./skills/evaluate"
  ]
}
```

**Step 4: Write launch-mcp.sh** (mirror interlab's pattern)

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY="${SCRIPT_DIR}/intermix-mcp"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

if [[ ! -x "$BINARY" ]]; then
    if ! command -v go &>/dev/null; then
        echo '{"error":"go not found — cannot build intermix-mcp. Install Go 1.23+."}' >&2
        exit 0
    fi
    cd "$PROJECT_ROOT"
    go build -o "$BINARY" ./cmd/intermix-mcp/ 2>&1 >&2
fi

exec "$BINARY" "$@"
```

**Step 5: Write CLAUDE.md**

```markdown
# intermix

> See `AGENTS.md` for full development guide.

## Overview

MCP server providing 4 stateless matrix evaluation tools (init_matrix, run_cell, classify_result, report_matrix) with JSONL persistence, subprocess Skaffen execution, hybrid failure taxonomy, and bead-integrated regression tracking.

## Quick Commands

\`\`\`bash
# Build binary
go build -o bin/intermix-mcp ./cmd/intermix-mcp/

# Run Go tests
go test ./...

# Validate structure
python3 -c "import json; json.load(open('.claude-plugin/plugin.json'))"
\`\`\`

## Design Decisions (Do Not Re-Ask)

- Go binary for MCP server (mark3labs/mcp-go), mirrors interlab's architecture
- Stateless tools — state reconstructed from JSONL on each call (crash recovery for free)
- Sequential cell execution — no concurrency in v1 (eval data correctness > speed)
- Hybrid taxonomy: fixed categories for aggregation + LLM analysis for nuance
- Subprocess Skaffen spawn: `skaffen --mode print` in isolated clone directories
- Circuit breakers: max cells (100), max consecutive failures (5), per-cell timeout (300s)
```

**Step 6: Write LICENSE** (MIT, same as interlab)

**Step 7: Add mcp-go dependency**

```bash
cd interverse/intermix && go get github.com/mark3labs/mcp-go@v0.32.0
```

**Step 8: Commit**

```bash
cd interverse/intermix && git init && git add -A
git commit -m "scaffold: intermix project with MCP server entry point and plugin manifest"
```

<verify>
- run: `cd interverse/intermix && go build ./cmd/intermix-mcp/`
  expect: exit 0
- run: `python3 -c "import json; json.load(open('interverse/intermix/.claude-plugin/plugin.json'))"`
  expect: exit 0
</verify>

---

### Task 2: YAML Manifest Schema & Parser

**Files:**
- Create: `interverse/intermix/internal/eval/manifest.go`
- Create: `interverse/intermix/internal/eval/manifest_test.go`

**Step 1: Write the failing test**

```go
package eval

import (
	"os"
	"path/filepath"
	"testing"
)

func TestParseManifest_ValidYAML(t *testing.T) {
	dir := t.TempDir()
	yamlContent := `
repos:
  - id: chi
    url: https://github.com/go-chi/chi
    setup: go mod download
    language: go
    complexity: small
  - id: zod
    url: https://github.com/colinhacks/zod
    setup: npm install
    language: typescript
    complexity: small
    skaffen_config:
      timeout: 600s

tasks:
  - id: add-test
    prompt: "Find a function that lacks test coverage and write a unit test."
    difficulty: easy
    tags: [testing, single-file]
    target: auto
  - id: chi-middleware
    prompt: "Add middleware that logs request duration."
    difficulty: medium
    tags: [feature, web]
    repos: [chi]
    validation_cmd: "go test ./..."

defaults:
  timeout: 300s
  max_cells: 100
  max_consecutive_failures: 5
`
	path := filepath.Join(dir, "intermix.yaml")
	os.WriteFile(path, []byte(yamlContent), 0644)

	m, err := ParseManifest(path)
	if err != nil {
		t.Fatalf("ParseManifest: %v", err)
	}
	if len(m.Repos) != 2 {
		t.Errorf("repos: got %d, want 2", len(m.Repos))
	}
	if len(m.Tasks) != 2 {
		t.Errorf("tasks: got %d, want 2", len(m.Tasks))
	}
	if m.Repos[1].SkaffenConfig.Timeout != "600s" {
		t.Errorf("skaffen_config.timeout: got %q, want 600s", m.Repos[1].SkaffenConfig.Timeout)
	}
	if m.Defaults.Timeout != "300s" {
		t.Errorf("defaults.timeout: got %q, want 300s", m.Defaults.Timeout)
	}
}

func TestParseManifest_MissingRequired(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "intermix.yaml")
	os.WriteFile(path, []byte("repos: []\ntasks: []"), 0644)
	_, err := ParseManifest(path)
	if err == nil {
		t.Error("expected error for empty repos/tasks")
	}
}

func TestExpandMatrix(t *testing.T) {
	m := &Manifest{
		Repos: []Repo{
			{ID: "chi", Language: "go"},
			{ID: "zod", Language: "typescript"},
		},
		Tasks: []Task{
			{ID: "add-test", Target: "auto"},           // generic: all repos
			{ID: "chi-mid", Repos: []string{"chi"}},    // repo-specific: chi only
		},
	}
	cells := ExpandMatrix(m)
	// add-test applies to both repos (2), chi-mid applies to chi only (1) = 3 cells
	if len(cells) != 3 {
		t.Errorf("cells: got %d, want 3", len(cells))
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd interverse/intermix && go test ./internal/eval/ -run TestParseManifest -v`
Expected: FAIL (types not defined)

**Step 3: Write manifest.go**

```go
package eval

import (
	"fmt"
	"os"

	"gopkg.in/yaml.v3"
)

// Manifest is the top-level intermix.yaml structure.
type Manifest struct {
	Repos    []Repo   `yaml:"repos"`
	Tasks    []Task   `yaml:"tasks"`
	Defaults Defaults `yaml:"defaults"`
}

// Repo defines a target repository for evaluation.
type Repo struct {
	ID            string       `yaml:"id"`
	URL           string       `yaml:"url"`
	Setup         string       `yaml:"setup,omitempty"`
	Language      string       `yaml:"language"`
	Complexity    string       `yaml:"complexity,omitempty"`
	SkaffenConfig SkaffenCfg   `yaml:"skaffen_config,omitempty"`
}

// SkaffenCfg holds per-repo Skaffen overrides.
type SkaffenCfg struct {
	Timeout string `yaml:"timeout,omitempty"`
}

// Task defines an evaluation task.
type Task struct {
	ID            string   `yaml:"id"`
	Prompt        string   `yaml:"prompt"`
	Difficulty    string   `yaml:"difficulty,omitempty"`
	Tags          []string `yaml:"tags,omitempty"`
	Target        string   `yaml:"target,omitempty"`        // "auto" for generic templates
	Repos         []string `yaml:"repos,omitempty"`         // empty = all repos
	ValidationCmd string   `yaml:"validation_cmd,omitempty"`
}

// Defaults holds campaign-level defaults.
type Defaults struct {
	Timeout                string `yaml:"timeout,omitempty"`
	MaxCells               int    `yaml:"max_cells,omitempty"`
	MaxConsecutiveFailures int    `yaml:"max_consecutive_failures,omitempty"`
	MaxDuration            string `yaml:"max_duration,omitempty"`
}

// Cell is a single (repo, task) evaluation unit.
type Cell struct {
	RepoID string
	TaskID string
	Repo   Repo
	Task   Task
}

// ParseManifest reads and validates an intermix.yaml file.
func ParseManifest(path string) (*Manifest, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read manifest: %w", err)
	}

	var m Manifest
	if err := yaml.Unmarshal(data, &m); err != nil {
		return nil, fmt.Errorf("parse manifest: %w", err)
	}

	// Apply defaults
	if m.Defaults.Timeout == "" {
		m.Defaults.Timeout = "300s"
	}
	if m.Defaults.MaxCells <= 0 {
		m.Defaults.MaxCells = 100
	}
	if m.Defaults.MaxConsecutiveFailures <= 0 {
		m.Defaults.MaxConsecutiveFailures = 5
	}
	if m.Defaults.MaxDuration == "" {
		m.Defaults.MaxDuration = "4h"
	}

	// Validate
	if len(m.Repos) == 0 {
		return nil, fmt.Errorf("manifest must have at least one repo")
	}
	if len(m.Tasks) == 0 {
		return nil, fmt.Errorf("manifest must have at least one task")
	}
	for i, r := range m.Repos {
		if r.ID == "" {
			return nil, fmt.Errorf("repo %d: missing id", i)
		}
		if r.URL == "" {
			return nil, fmt.Errorf("repo %q: missing url", r.ID)
		}
	}
	for i, t := range m.Tasks {
		if t.ID == "" {
			return nil, fmt.Errorf("task %d: missing id", i)
		}
		if t.Prompt == "" {
			return nil, fmt.Errorf("task %q: missing prompt", t.ID)
		}
	}

	return &m, nil
}

// ExpandMatrix generates all (repo, task) cells from the manifest.
// Tasks with Repos set are only applied to those repos.
// Tasks without Repos are applied to all repos.
func ExpandMatrix(m *Manifest) []Cell {
	repoMap := make(map[string]Repo)
	for _, r := range m.Repos {
		repoMap[r.ID] = r
	}

	var cells []Cell
	for _, task := range m.Tasks {
		if len(task.Repos) > 0 {
			// Repo-specific task
			for _, rid := range task.Repos {
				if repo, ok := repoMap[rid]; ok {
					cells = append(cells, Cell{
						RepoID: rid,
						TaskID: task.ID,
						Repo:   repo,
						Task:   task,
					})
				}
			}
		} else {
			// Generic task: all repos
			for _, repo := range m.Repos {
				cells = append(cells, Cell{
					RepoID: repo.ID,
					TaskID: task.ID,
					Repo:   repo,
					Task:   task,
				})
			}
		}
	}
	return cells
}
```

**Step 4: Add yaml dependency**

```bash
cd interverse/intermix && go get gopkg.in/yaml.v3
```

**Step 5: Run tests**

Run: `cd interverse/intermix && go test ./internal/eval/ -v`
Expected: PASS

**Step 6: Commit**

```bash
cd interverse/intermix && git add internal/eval/manifest.go internal/eval/manifest_test.go go.mod go.sum
git commit -m "feat: YAML manifest parser with matrix expansion"
```

<verify>
- run: `cd interverse/intermix && go test ./internal/eval/ -run TestParseManifest -v`
  expect: exit 0
- run: `cd interverse/intermix && go test ./internal/eval/ -run TestExpandMatrix -v`
  expect: exit 0
</verify>

---

### Task 3: JSONL State Types & Reconstruction

**Files:**
- Create: `interverse/intermix/internal/eval/state.go`
- Create: `interverse/intermix/internal/eval/state_test.go`

**Step 1: Write the failing test**

```go
package eval

import (
	"os"
	"path/filepath"
	"testing"
)

func TestReconstructState_Empty(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "intermix.jsonl")
	s, err := ReconstructState(path)
	if err != nil {
		t.Fatalf("ReconstructState: %v", err)
	}
	if s.SegmentID != 0 {
		t.Errorf("segment: got %d, want 0", s.SegmentID)
	}
}

func TestReconstructState_WithResults(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "intermix.jsonl")
	lines := `{"type":"config","name":"test-campaign","timestamp":"2026-03-14T00:00:00Z"}
{"type":"cell_result","repo":"chi","task":"add-test","outcome":"success","validation_passed":true,"duration_ms":5000,"timestamp":"2026-03-14T00:01:00Z"}
{"type":"cell_result","repo":"chi","task":"refactor","outcome":"context_limit","validation_passed":false,"duration_ms":300000,"timestamp":"2026-03-14T00:06:00Z"}
{"type":"cell_result","repo":"cobra","task":"add-test","outcome":"success","validation_passed":true,"duration_ms":8000,"timestamp":"2026-03-14T00:07:00Z"}
`
	os.WriteFile(path, []byte(lines), 0644)

	s, err := ReconstructState(path)
	if err != nil {
		t.Fatalf("ReconstructState: %v", err)
	}
	if s.SegmentID != 1 {
		t.Errorf("segment: got %d, want 1", s.SegmentID)
	}
	if s.CellCount != 3 {
		t.Errorf("cell count: got %d, want 3", s.CellCount)
	}
	if s.SuccessCount != 2 {
		t.Errorf("success: got %d, want 2", s.SuccessCount)
	}
	if s.ConsecutiveFailures != 0 {
		t.Errorf("consecutive failures: got %d, want 0 (last was success)", s.ConsecutiveFailures)
	}
}

func TestCheckCircuitBreaker(t *testing.T) {
	s := &MatrixState{
		ConsecutiveFailures: 5,
		Config:              MatrixConfig{MaxConsecutiveFailures: 5},
	}
	if err := s.CheckCircuitBreaker(); err == nil {
		t.Error("expected circuit breaker error")
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd interverse/intermix && go test ./internal/eval/ -run TestReconstructState -v`
Expected: FAIL

**Step 3: Write state.go**

```go
package eval

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"time"
)

// Outcome constants for the fixed taxonomy.
const (
	OutcomeSuccess      = "success"
	OutcomePartial      = "partial"
	OutcomeWrongApproach = "wrong_approach"
	OutcomeContextLimit = "context_limit"
	OutcomeToolFailure  = "tool_failure"
	OutcomeNoProgress   = "no_progress"
	OutcomeCrash        = "crash"
	OutcomeTimeout      = "timeout"
	OutcomeSetupFailure = "setup_failure"
	OutcomeSkipped      = "skipped"
)

// Severity constants.
const (
	SeverityCritical   = "critical"
	SeverityDegraded   = "degraded"
	SeverityAcceptable = "acceptable"
)

// MatrixConfig is the config record written to JSONL at campaign start.
type MatrixConfig struct {
	Type                   string   `json:"type"`      // always "config"
	Name                   string   `json:"name"`
	ManifestPath           string   `json:"manifest_path,omitempty"`
	RepoIDs                []string `json:"repo_ids"`
	TaskIDs                []string `json:"task_ids"`
	TotalCells             int      `json:"total_cells"`
	MaxCells               int      `json:"max_cells"`
	MaxConsecutiveFailures int      `json:"max_consecutive_failures"`
	Timeout                string   `json:"timeout"`
	BeadID                 string   `json:"bead_id,omitempty"`
	Timestamp              string   `json:"timestamp"`
}

// CellResult is written after each cell evaluation.
type CellResult struct {
	Type             string `json:"type"`              // always "cell_result"
	Repo             string `json:"repo"`
	Task             string `json:"task"`
	Outcome          string `json:"outcome"`           // fixed taxonomy
	Severity         string `json:"severity,omitempty"`
	ValidationPassed bool   `json:"validation_passed"`
	DurationMs       int64  `json:"duration_ms"`
	ExitCode         int    `json:"exit_code"`
	FilesChanged     int    `json:"files_changed"`
	TokensUsed       int    `json:"tokens_used,omitempty"`
	LLMAnalysis      string `json:"llm_analysis,omitempty"`
	FailureReason    string `json:"failure_reason,omitempty"`
	PhasesReached    []string `json:"phases_reached,omitempty"`
	Timestamp        string `json:"timestamp"`
}

// MatrixState holds the reconstructed campaign state.
type MatrixState struct {
	Config              MatrixConfig
	SegmentID           int
	CellCount           int
	SuccessCount        int
	PartialCount        int
	FailureCount        int
	SkippedCount        int
	ConsecutiveFailures int
	TotalDurationMs     int64
	TotalTokens         int
	Results             []CellResult // all results in current segment
	CompletedCells      map[string]bool // "repo:task" -> true
}

// ReconstructState reads the JSONL and rebuilds matrix state.
// Mirrors interlab's byte-level scanning for performance.
func ReconstructState(path string) (*MatrixState, error) {
	s := &MatrixState{
		CompletedCells: make(map[string]bool),
	}

	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return s, nil
	}
	if err != nil {
		return nil, fmt.Errorf("read jsonl: %w", err)
	}

	for len(data) > 0 {
		idx := bytes.IndexByte(data, '\n')
		var line []byte
		if idx < 0 {
			line = data
			data = nil
		} else {
			line = data[:idx]
			data = data[idx+1:]
		}

		line = bytes.TrimSpace(line)
		if len(line) == 0 {
			continue
		}

		isConfig := bytes.Contains(line, []byte(`"type":"config"`))
		isResult := bytes.Contains(line, []byte(`"type":"cell_result"`))

		if isConfig {
			var cfg MatrixConfig
			if err := json.Unmarshal(line, &cfg); err != nil {
				continue
			}
			s.Config = cfg
			s.SegmentID++
			// Reset counters for new segment
			s.CellCount = 0
			s.SuccessCount = 0
			s.PartialCount = 0
			s.FailureCount = 0
			s.SkippedCount = 0
			s.ConsecutiveFailures = 0
			s.TotalDurationMs = 0
			s.TotalTokens = 0
			s.Results = nil
			s.CompletedCells = make(map[string]bool)
		} else if isResult {
			var cr CellResult
			if err := json.Unmarshal(line, &cr); err != nil {
				continue
			}
			s.CellCount++
			s.TotalDurationMs += cr.DurationMs
			s.TotalTokens += cr.TokensUsed
			s.Results = append(s.Results, cr)
			s.CompletedCells[cr.Repo+":"+cr.Task] = true

			switch cr.Outcome {
			case OutcomeSuccess:
				s.SuccessCount++
				s.ConsecutiveFailures = 0
			case OutcomePartial:
				s.PartialCount++
				s.ConsecutiveFailures = 0
			case OutcomeSkipped:
				s.SkippedCount++
				// Skipped doesn't affect consecutive failure count
			default:
				// All other outcomes are failures
				s.FailureCount++
				s.ConsecutiveFailures++
			}
		}
	}

	return s, nil
}

// CheckCircuitBreaker returns an error if any limit is exceeded.
func (s *MatrixState) CheckCircuitBreaker() error {
	cfg := s.Config
	if cfg.MaxConsecutiveFailures > 0 && s.ConsecutiveFailures >= cfg.MaxConsecutiveFailures {
		return fmt.Errorf("circuit breaker: %d consecutive failures (limit %d)",
			s.ConsecutiveFailures, cfg.MaxConsecutiveFailures)
	}
	if cfg.MaxCells > 0 && s.CellCount >= cfg.MaxCells {
		return fmt.Errorf("circuit breaker: %d cells (limit %d)",
			s.CellCount, cfg.MaxCells)
	}
	return nil
}

// WriteConfig appends a config record to the JSONL.
func WriteConfig(path string, cfg MatrixConfig) error {
	cfg.Type = "config"
	if cfg.Timestamp == "" {
		cfg.Timestamp = time.Now().UTC().Format(time.RFC3339)
	}
	return appendJSONL(path, cfg)
}

// WriteCellResult appends a cell result to the JSONL.
func WriteCellResult(path string, cr CellResult) error {
	cr.Type = "cell_result"
	if cr.Timestamp == "" {
		cr.Timestamp = time.Now().UTC().Format(time.RFC3339)
	}
	return appendJSONL(path, cr)
}

func appendJSONL(path string, v interface{}) error {
	data, err := json.Marshal(v)
	if err != nil {
		return fmt.Errorf("marshal: %w", err)
	}
	data = append(data, '\n')

	f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return fmt.Errorf("open: %w", err)
	}
	defer f.Close()

	_, err = f.Write(data)
	return err
}
```

**Step 4: Run tests**

Run: `cd interverse/intermix && go test ./internal/eval/ -run "TestReconstructState|TestCheckCircuitBreaker" -v`
Expected: PASS

**Step 5: Commit**

```bash
cd interverse/intermix && git add internal/eval/state.go internal/eval/state_test.go
git commit -m "feat: JSONL state types and reconstruction with circuit breaker"
```

<verify>
- run: `cd interverse/intermix && go test ./internal/eval/ -run TestReconstructState -v`
  expect: exit 0
- run: `cd interverse/intermix && go test ./internal/eval/ -run TestCheckCircuitBreaker -v`
  expect: exit 0
</verify>

---

### Task 4: Cell Runner — Clone, Spawn Skaffen, Validate

**Files:**
- Create: `interverse/intermix/internal/eval/runner.go`
- Create: `interverse/intermix/internal/eval/runner_test.go`

**Step 1: Write the failing test**

```go
package eval

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

func TestCloneRepo(t *testing.T) {
	// Skip if git not available
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git not available")
	}

	dir := t.TempDir()

	// Create a local bare repo to clone from
	srcDir := filepath.Join(dir, "src")
	os.MkdirAll(srcDir, 0755)
	runCmd(t, srcDir, "git", "init")
	runCmd(t, srcDir, "git", "config", "user.email", "test@test.com")
	runCmd(t, srcDir, "git", "config", "user.name", "Test")
	os.WriteFile(filepath.Join(srcDir, "main.go"), []byte("package main"), 0644)
	runCmd(t, srcDir, "git", "add", ".")
	runCmd(t, srcDir, "git", "commit", "-m", "init")

	cloneDir := filepath.Join(dir, "clone")
	err := CloneRepo(srcDir, cloneDir)
	if err != nil {
		t.Fatalf("CloneRepo: %v", err)
	}

	// Verify clone has the file
	if _, err := os.Stat(filepath.Join(cloneDir, "main.go")); err != nil {
		t.Error("cloned repo missing main.go")
	}
}

func TestRunValidation_Pass(t *testing.T) {
	dir := t.TempDir()
	result := RunValidation(dir, "true") // `true` always exits 0
	if !result.Passed {
		t.Error("expected validation to pass")
	}
}

func TestRunValidation_Fail(t *testing.T) {
	dir := t.TempDir()
	result := RunValidation(dir, "false") // `false` always exits 1
	if result.Passed {
		t.Error("expected validation to fail")
	}
}

func runCmd(t *testing.T, dir string, name string, args ...string) {
	t.Helper()
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(), "GIT_AUTHOR_DATE=2026-01-01T00:00:00Z", "GIT_COMMITTER_DATE=2026-01-01T00:00:00Z")
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("%s %v: %v\n%s", name, args, err, out)
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd interverse/intermix && go test ./internal/eval/ -run TestCloneRepo -v`
Expected: FAIL

**Step 3: Write runner.go**

```go
package eval

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// RunDetails is written to .intermix-run.json after run_cell.
type RunDetails struct {
	CellID       string `json:"cell_id"`
	Repo         string `json:"repo"`
	Task         string `json:"task"`
	ExitCode     int    `json:"exit_code"`
	DurationMs   int64  `json:"duration_ms"`
	Stdout       string `json:"stdout"`
	Stderr       string `json:"stderr"`
	FilesChanged int    `json:"files_changed"`
	ValidationPassed bool   `json:"validation_passed"`
	ValidationOutput string `json:"validation_output"`
	CloneDir     string `json:"clone_dir"`
}

// ValidationResult holds the outcome of running a validation command.
type ValidationResult struct {
	Passed   bool
	ExitCode int
	Output   string
}

// CloneRepo does a shallow clone of a repo URL into destDir.
func CloneRepo(url, destDir string) error {
	cmd := exec.Command("git", "clone", "--depth=1", url, destDir)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("git clone %s: %v (%s)", url, err, strings.TrimSpace(stderr.String()))
	}
	return nil
}

// RunSetup executes the repo's setup command in the clone directory.
func RunSetup(dir, setupCmd string) error {
	if setupCmd == "" {
		return nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, "bash", "-c", setupCmd)
	cmd.Dir = dir
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("setup %q: %v (%s)", setupCmd, err, strings.TrimSpace(stderr.String()))
	}
	return nil
}

// SpawnSkaffen runs skaffen --mode print with the given prompt in dir.
// Returns the RunDetails with captured output.
func SpawnSkaffen(dir, prompt, timeout string) *RunDetails {
	if timeout == "" {
		timeout = "300s"
	}

	start := time.Now()

	args := []string{"--mode", "print", "--prompt", prompt, "--timeout", timeout}
	cmd := exec.Command("skaffen", args...)
	cmd.Dir = dir

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	err := cmd.Run()

	duration := time.Since(start)
	exitCode := 0
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			exitCode = exitErr.ExitCode()
		} else {
			exitCode = -1
		}
	}

	// Count files changed by diffing git status
	filesChanged := countFilesChanged(dir)

	return &RunDetails{
		ExitCode:     exitCode,
		DurationMs:   duration.Milliseconds(),
		Stdout:       truncateOutput(stdout.String(), 40960),
		Stderr:       truncateOutput(stderr.String(), 10240),
		FilesChanged: filesChanged,
		CloneDir:     dir,
	}
}

// RunValidation executes a validation command and checks the exit code.
func RunValidation(dir, validationCmd string) ValidationResult {
	if validationCmd == "" {
		return ValidationResult{Passed: true, Output: "(no validation command)"}
	}

	ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, "bash", "-c", validationCmd)
	cmd.Dir = dir

	var combined bytes.Buffer
	cmd.Stdout = &combined
	cmd.Stderr = &combined

	err := cmd.Run()
	exitCode := 0
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			exitCode = exitErr.ExitCode()
		} else {
			exitCode = -1
		}
	}

	return ValidationResult{
		Passed:   exitCode == 0,
		ExitCode: exitCode,
		Output:   truncateOutput(combined.String(), 10240),
	}
}

// InferValidationCmd returns a language-appropriate test runner command.
func InferValidationCmd(dir, language string) string {
	switch language {
	case "go":
		return "go test ./..."
	case "typescript", "javascript":
		if _, err := os.Stat(filepath.Join(dir, "package.json")); err == nil {
			return "npm test"
		}
		return ""
	case "python":
		return "pytest"
	case "rust":
		return "cargo test"
	default:
		return ""
	}
}

func countFilesChanged(dir string) int {
	cmd := exec.Command("git", "status", "--porcelain")
	cmd.Dir = dir
	out, err := cmd.Output()
	if err != nil {
		return 0
	}
	count := 0
	for _, line := range bytes.Split(out, []byte("\n")) {
		if len(bytes.TrimSpace(line)) > 0 {
			count++
		}
	}
	return count
}

func truncateOutput(s string, maxBytes int) string {
	if len(s) <= maxBytes {
		return s
	}
	return s[:maxBytes] + "\n...(truncated)"
}
```

**Step 4: Run tests**

Run: `cd interverse/intermix && go test ./internal/eval/ -run "TestCloneRepo|TestRunValidation" -v`
Expected: PASS

**Step 5: Commit**

```bash
cd interverse/intermix && git add internal/eval/runner.go internal/eval/runner_test.go
git commit -m "feat: cell runner with clone, Skaffen spawn, and validation"
```

<verify>
- run: `cd interverse/intermix && go test ./internal/eval/ -run TestCloneRepo -v`
  expect: exit 0
- run: `cd interverse/intermix && go test ./internal/eval/ -run TestRunValidation -v`
  expect: exit 0
</verify>

---

### Task 5: Classifier — Fixed Taxonomy + LLM Analysis Placeholder

**Files:**
- Create: `interverse/intermix/internal/eval/classify.go`
- Create: `interverse/intermix/internal/eval/classify_test.go`

**Step 1: Write the failing test**

```go
package eval

import (
	"testing"
)

func TestClassifyFromRunDetails_Success(t *testing.T) {
	rd := &RunDetails{ExitCode: 0, FilesChanged: 3, ValidationPassed: true, DurationMs: 5000}
	cr := ClassifyFromRunDetails(rd, "chi", "add-test")
	if cr.Outcome != OutcomeSuccess {
		t.Errorf("outcome: got %q, want %q", cr.Outcome, OutcomeSuccess)
	}
	if cr.Severity != SeverityAcceptable {
		t.Errorf("severity: got %q, want %q", cr.Severity, SeverityAcceptable)
	}
}

func TestClassifyFromRunDetails_Timeout(t *testing.T) {
	rd := &RunDetails{ExitCode: -1, DurationMs: 300000, Stderr: "context deadline exceeded"}
	cr := ClassifyFromRunDetails(rd, "chi", "refactor")
	if cr.Outcome != OutcomeTimeout {
		t.Errorf("outcome: got %q, want %q", cr.Outcome, OutcomeTimeout)
	}
	if cr.Severity != SeverityCritical {
		t.Errorf("severity: got %q, want %q", cr.Severity, SeverityCritical)
	}
}

func TestClassifyFromRunDetails_NoProgress(t *testing.T) {
	rd := &RunDetails{ExitCode: 0, FilesChanged: 0, ValidationPassed: false, DurationMs: 60000}
	cr := ClassifyFromRunDetails(rd, "cobra", "add-feature")
	if cr.Outcome != OutcomeNoProgress {
		t.Errorf("outcome: got %q, want %q", cr.Outcome, OutcomeNoProgress)
	}
}

func TestClassifyFromRunDetails_Partial(t *testing.T) {
	rd := &RunDetails{ExitCode: 0, FilesChanged: 2, ValidationPassed: false, DurationMs: 45000}
	cr := ClassifyFromRunDetails(rd, "zod", "add-test")
	if cr.Outcome != OutcomePartial {
		t.Errorf("outcome: got %q, want %q", cr.Outcome, OutcomePartial)
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd interverse/intermix && go test ./internal/eval/ -run TestClassify -v`
Expected: FAIL

**Step 3: Write classify.go**

```go
package eval

import (
	"strings"
)

// ClassifyFromRunDetails applies the fixed taxonomy based on observable signals.
// LLM analysis is added later via classify_result tool (not in this function).
func ClassifyFromRunDetails(rd *RunDetails, repo, task string) CellResult {
	cr := CellResult{
		Repo:             repo,
		Task:             task,
		DurationMs:       rd.DurationMs,
		ExitCode:         rd.ExitCode,
		FilesChanged:     rd.FilesChanged,
		ValidationPassed: rd.ValidationPassed,
	}

	// Classification logic — order matters (most specific first)
	switch {
	case rd.ExitCode == -1 && containsAny(rd.Stderr, "deadline exceeded", "timeout", "signal: killed"):
		cr.Outcome = OutcomeTimeout
		cr.Severity = SeverityCritical
		cr.FailureReason = "Process timed out"

	case rd.ExitCode != 0 && containsAny(rd.Stderr, "segfault", "panic", "SIGSEGV", "fatal error"):
		cr.Outcome = OutcomeCrash
		cr.Severity = SeverityCritical
		cr.FailureReason = "Process crashed"

	case containsAny(rd.Stderr, "context limit", "token limit", "max_tokens", "context window"):
		cr.Outcome = OutcomeContextLimit
		cr.Severity = SeverityCritical
		cr.FailureReason = "Hit context/token limits"

	case rd.ExitCode != 0 && containsAny(rd.Stderr, "tool", "MCP", "failed to call"):
		cr.Outcome = OutcomeToolFailure
		cr.Severity = SeverityDegraded
		cr.FailureReason = "Tool execution failed"

	case rd.FilesChanged == 0 && !rd.ValidationPassed:
		cr.Outcome = OutcomeNoProgress
		cr.Severity = SeverityCritical
		cr.FailureReason = "No files changed and validation failed"

	case rd.FilesChanged > 0 && rd.ValidationPassed:
		cr.Outcome = OutcomeSuccess
		cr.Severity = SeverityAcceptable

	case rd.FilesChanged > 0 && !rd.ValidationPassed:
		cr.Outcome = OutcomePartial
		cr.Severity = SeverityDegraded
		cr.FailureReason = "Changes made but validation failed"

	default:
		cr.Outcome = OutcomeToolFailure
		cr.Severity = SeverityDegraded
		cr.FailureReason = "Unclassified failure"
	}

	return cr
}

func containsAny(s string, substrs ...string) bool {
	lower := strings.ToLower(s)
	for _, sub := range substrs {
		if strings.Contains(lower, strings.ToLower(sub)) {
			return true
		}
	}
	return false
}
```

**Step 4: Run tests**

Run: `cd interverse/intermix && go test ./internal/eval/ -run TestClassify -v`
Expected: PASS

**Step 5: Commit**

```bash
cd interverse/intermix && git add internal/eval/classify.go internal/eval/classify_test.go
git commit -m "feat: hybrid classifier with fixed taxonomy rules"
```

<verify>
- run: `cd interverse/intermix && go test ./internal/eval/ -run TestClassify -v`
  expect: exit 0
</verify>

---

### Task 6: Report Generator — Heatmap, Clustering, Delta Comparison

**Files:**
- Create: `interverse/intermix/internal/eval/report.go`
- Create: `interverse/intermix/internal/eval/report_test.go`

**Step 1: Write the failing test**

```go
package eval

import (
	"testing"
)

func TestGenerateReport_BasicStats(t *testing.T) {
	results := []CellResult{
		{Repo: "chi", Task: "add-test", Outcome: OutcomeSuccess},
		{Repo: "chi", Task: "refactor", Outcome: OutcomeContextLimit, Severity: SeverityCritical},
		{Repo: "cobra", Task: "add-test", Outcome: OutcomeSuccess},
		{Repo: "cobra", Task: "refactor", Outcome: OutcomeContextLimit, Severity: SeverityCritical},
	}
	report := GenerateReport(results, nil)
	if report.TotalCells != 4 {
		t.Errorf("total: got %d, want 4", report.TotalCells)
	}
	if report.PassRate != 50.0 {
		t.Errorf("pass rate: got %.1f, want 50.0", report.PassRate)
	}
	if len(report.FailureClusters) != 1 {
		t.Errorf("clusters: got %d, want 1 (context_limit)", len(report.FailureClusters))
	}
}

func TestCompareSegments(t *testing.T) {
	prev := []CellResult{
		{Repo: "chi", Task: "add-test", Outcome: OutcomeContextLimit},
		{Repo: "cobra", Task: "add-test", Outcome: OutcomeSuccess},
	}
	curr := []CellResult{
		{Repo: "chi", Task: "add-test", Outcome: OutcomeSuccess},
		{Repo: "cobra", Task: "add-test", Outcome: OutcomeContextLimit},
	}
	delta := CompareSegments(prev, curr)
	if delta.Fixed != 1 {
		t.Errorf("fixed: got %d, want 1", delta.Fixed)
	}
	if delta.Regressed != 1 {
		t.Errorf("regressed: got %d, want 1", delta.Regressed)
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd interverse/intermix && go test ./internal/eval/ -run "TestGenerateReport|TestCompareSegments" -v`
Expected: FAIL

**Step 3: Write report.go**

```go
package eval

import (
	"fmt"
	"sort"
	"strings"
)

// Report summarizes a campaign's results.
type Report struct {
	TotalCells      int
	SuccessCount    int
	FailureCount    int
	PassRate        float64
	ByRepo          map[string]*RepoStats
	ByTask          map[string]*TaskStats
	ByOutcome       map[string]int
	FailureClusters []FailureCluster
	Delta           *DeltaReport // nil if no previous segment
}

// RepoStats tracks per-repo pass/fail.
type RepoStats struct {
	Total   int
	Success int
	Failure int
}

// TaskStats tracks per-task pass/fail.
type TaskStats struct {
	Total   int
	Success int
	Failure int
}

// FailureCluster groups similar failures.
type FailureCluster struct {
	Outcome    string
	Count      int
	Cells      []string // "repo:task" pairs
	BeadID     string   // set after bead creation
}

// DeltaReport compares two campaign segments.
type DeltaReport struct {
	Fixed      int
	Regressed  int
	Stable     int
	NewCells   int
	FixedCells     []string // "repo:task"
	RegressedCells []string
}

// GenerateReport creates a summary from cell results.
// prevResults is optional — pass nil for the first campaign.
func GenerateReport(results []CellResult, prevResults []CellResult) *Report {
	r := &Report{
		TotalCells: len(results),
		ByRepo:     make(map[string]*RepoStats),
		ByTask:     make(map[string]*TaskStats),
		ByOutcome:  make(map[string]int),
	}

	for _, cr := range results {
		isSuccess := cr.Outcome == OutcomeSuccess

		if isSuccess {
			r.SuccessCount++
		} else if cr.Outcome != OutcomeSkipped {
			r.FailureCount++
		}

		r.ByOutcome[cr.Outcome]++

		// Per-repo
		rs, ok := r.ByRepo[cr.Repo]
		if !ok {
			rs = &RepoStats{}
			r.ByRepo[cr.Repo] = rs
		}
		rs.Total++
		if isSuccess {
			rs.Success++
		} else {
			rs.Failure++
		}

		// Per-task
		ts, ok := r.ByTask[cr.Task]
		if !ok {
			ts = &TaskStats{}
			r.ByTask[cr.Task] = ts
		}
		ts.Total++
		if isSuccess {
			ts.Success++
		} else {
			ts.Failure++
		}
	}

	if r.TotalCells > 0 {
		r.PassRate = float64(r.SuccessCount) / float64(r.TotalCells) * 100
	}

	r.FailureClusters = ClusterFailures(results)

	if prevResults != nil {
		r.Delta = CompareSegments(prevResults, results)
	}

	return r
}

// ClusterFailures groups failed cells by outcome type.
func ClusterFailures(results []CellResult) []FailureCluster {
	clusters := make(map[string]*FailureCluster)

	for _, cr := range results {
		if cr.Outcome == OutcomeSuccess || cr.Outcome == OutcomeSkipped {
			continue
		}
		key := cr.Outcome
		c, ok := clusters[key]
		if !ok {
			c = &FailureCluster{Outcome: key}
			clusters[key] = c
		}
		c.Count++
		c.Cells = append(c.Cells, cr.Repo+":"+cr.Task)
	}

	var out []FailureCluster
	for _, c := range clusters {
		out = append(out, *c)
	}
	sort.Slice(out, func(i, j int) bool {
		return out[i].Count > out[j].Count
	})
	return out
}

// CompareSegments produces a delta report between two campaign runs.
func CompareSegments(prev, curr []CellResult) *DeltaReport {
	d := &DeltaReport{}

	prevMap := make(map[string]string) // "repo:task" -> outcome
	for _, cr := range prev {
		prevMap[cr.Repo+":"+cr.Task] = cr.Outcome
	}

	for _, cr := range curr {
		key := cr.Repo + ":" + cr.Task
		prevOutcome, existed := prevMap[key]
		if !existed {
			d.NewCells++
			continue
		}

		prevFailed := prevOutcome != OutcomeSuccess && prevOutcome != OutcomeSkipped
		currFailed := cr.Outcome != OutcomeSuccess && cr.Outcome != OutcomeSkipped

		switch {
		case prevFailed && !currFailed:
			d.Fixed++
			d.FixedCells = append(d.FixedCells, key)
		case !prevFailed && currFailed:
			d.Regressed++
			d.RegressedCells = append(d.RegressedCells, key)
		default:
			d.Stable++
		}
	}

	return d
}

// FormatReport produces a human-readable report string.
func FormatReport(r *Report) string {
	var sb strings.Builder

	sb.WriteString(fmt.Sprintf("## intermix Campaign Report\n\n"))
	sb.WriteString(fmt.Sprintf("**Total cells:** %d | **Pass rate:** %.1f%%\n", r.TotalCells, r.PassRate))
	sb.WriteString(fmt.Sprintf("**Success:** %d | **Failure:** %d\n\n", r.SuccessCount, r.FailureCount))

	// Outcome distribution
	sb.WriteString("### Outcome Distribution\n\n")
	for outcome, count := range r.ByOutcome {
		sb.WriteString(fmt.Sprintf("- %s: %d\n", outcome, count))
	}

	// Failure clusters
	if len(r.FailureClusters) > 0 {
		sb.WriteString("\n### Failure Clusters\n\n")
		for _, c := range r.FailureClusters {
			sb.WriteString(fmt.Sprintf("**%s** (%d cells): %s\n", c.Outcome, c.Count, strings.Join(c.Cells, ", ")))
		}
	}

	// Delta
	if r.Delta != nil {
		sb.WriteString("\n### Delta vs. Previous\n\n")
		sb.WriteString(fmt.Sprintf("- Fixed: %d\n", r.Delta.Fixed))
		sb.WriteString(fmt.Sprintf("- Regressed: %d\n", r.Delta.Regressed))
		sb.WriteString(fmt.Sprintf("- Stable: %d\n", r.Delta.Stable))
		sb.WriteString(fmt.Sprintf("- New cells: %d\n", r.Delta.NewCells))
		if len(r.Delta.FixedCells) > 0 {
			sb.WriteString(fmt.Sprintf("- Fixed: %s\n", strings.Join(r.Delta.FixedCells, ", ")))
		}
		if len(r.Delta.RegressedCells) > 0 {
			sb.WriteString(fmt.Sprintf("- Regressed: %s\n", strings.Join(r.Delta.RegressedCells, ", ")))
		}
	}

	return sb.String()
}
```

**Step 4: Run tests**

Run: `cd interverse/intermix && go test ./internal/eval/ -run "TestGenerateReport|TestCompareSegments" -v`
Expected: PASS

**Step 5: Commit**

```bash
cd interverse/intermix && git add internal/eval/report.go internal/eval/report_test.go
git commit -m "feat: report generator with clustering and delta comparison"
```

<verify>
- run: `cd interverse/intermix && go test ./internal/eval/ -run TestGenerateReport -v`
  expect: exit 0
- run: `cd interverse/intermix && go test ./internal/eval/ -run TestCompareSegments -v`
  expect: exit 0
</verify>

---

### Task 7: MCP Tool Handlers — Wire Everything Together

**Files:**
- Create: `interverse/intermix/internal/eval/tools.go`
- Create: `interverse/intermix/internal/eval/tools_test.go`

**Step 1: Write the failing test**

```go
package eval

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/mark3labs/mcp-go/mcp"
)

func TestHandleInitMatrix(t *testing.T) {
	dir := t.TempDir()

	// Write a valid manifest
	yaml := `
repos:
  - id: test-repo
    url: /dev/null
    language: go
tasks:
  - id: test-task
    prompt: "Test prompt"
`
	manifestPath := filepath.Join(dir, "intermix.yaml")
	os.WriteFile(manifestPath, []byte(yaml), 0644)

	req := mcp.CallToolRequest{}
	req.Params.Arguments = map[string]interface{}{
		"manifest_path":     manifestPath,
		"working_directory": dir,
		"name":              "test-campaign",
	}

	result, err := handleInitMatrix(context.Background(), req)
	if err != nil {
		t.Fatalf("handleInitMatrix: %v", err)
	}

	// Check JSONL was created
	jsonlPath := filepath.Join(dir, "intermix.jsonl")
	if _, err := os.Stat(jsonlPath); err != nil {
		t.Error("intermix.jsonl not created")
	}

	// Check result text contains cell count
	text := result.Content[0].(mcp.TextContent).Text
	if text == "" {
		t.Error("empty result text")
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd interverse/intermix && go test ./internal/eval/ -run TestHandleInitMatrix -v`
Expected: FAIL

**Step 3: Write tools.go**

```go
package eval

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/mark3labs/mcp-go/mcp"
	"github.com/mark3labs/mcp-go/server"
)

// RegisterAll registers all intermix tools with the MCP server.
func RegisterAll(s *server.MCPServer) {
	s.AddTool(initMatrixTool, handleInitMatrix)
	s.AddTool(runCellTool, handleRunCell)
	s.AddTool(classifyResultTool, handleClassifyResult)
	s.AddTool(reportMatrixTool, handleReportMatrix)
}

var initMatrixTool = mcp.NewTool("init_matrix",
	mcp.WithDescription("Initialize a matrix evaluation campaign from a YAML manifest. Validates repos/tasks, expands the matrix, writes config to JSONL."),
	mcp.WithString("manifest_path", mcp.Required(), mcp.Description("Path to intermix.yaml manifest file")),
	mcp.WithString("name", mcp.Required(), mcp.Description("Campaign name (e.g., 'skaffen-v1-stress')")),
	mcp.WithString("working_directory", mcp.Description("Directory for intermix.jsonl (default: cwd)")),
	mcp.WithString("bead_id", mcp.Description("Parent bead ID for linking failure beads")),
)

var runCellTool = mcp.NewTool("run_cell",
	mcp.WithDescription("Execute a single (repo, task) cell: clone repo, run setup, spawn Skaffen, run validation. Returns structured result."),
	mcp.WithString("repo", mcp.Required(), mcp.Description("Repo ID from the manifest")),
	mcp.WithString("task", mcp.Required(), mcp.Description("Task ID from the manifest")),
	mcp.WithString("working_directory", mcp.Description("Directory containing intermix.jsonl (default: cwd)")),
)

var classifyResultTool = mcp.NewTool("classify_result",
	mcp.WithDescription("Apply hybrid taxonomy to the last run_cell result. Reads .intermix-run.json, classifies outcome, optionally adds LLM analysis, writes to JSONL."),
	mcp.WithString("llm_analysis", mcp.Description("Optional LLM-generated analysis of the failure (free text)")),
	mcp.WithString("working_directory", mcp.Description("Directory containing intermix.jsonl (default: cwd)")),
)

var reportMatrixTool = mcp.NewTool("report_matrix",
	mcp.WithDescription("Generate a campaign report: pass/fail heatmap, failure clusters, delta comparison vs. previous campaign. Optionally creates beads for failure patterns."),
	mcp.WithString("working_directory", mcp.Description("Directory containing intermix.jsonl (default: cwd)")),
	mcp.WithString("bead_id", mcp.Description("Parent bead ID — failure clusters with ≥2 cells auto-create child beads")),
	mcp.WithString("format", mcp.Description("Output format: 'text' (default) or 'json'")),
)

func resolveDir(req mcp.CallToolRequest) string {
	dir := req.GetString("working_directory", "")
	if dir == "" {
		dir, _ = os.Getwd()
	}
	return dir
}

func handleInitMatrix(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	manifestPath := req.GetString("manifest_path", "")
	name := req.GetString("name", "")
	dir := resolveDir(req)
	beadID := req.GetString("bead_id", "")

	if manifestPath == "" || name == "" {
		return mcp.NewToolResultText("missing required fields: manifest_path, name"), nil
	}

	m, err := ParseManifest(manifestPath)
	if err != nil {
		return mcp.NewToolResultText(fmt.Sprintf("manifest error: %v", err)), nil
	}

	cells := ExpandMatrix(m)

	repoIDs := make([]string, len(m.Repos))
	for i, r := range m.Repos {
		repoIDs[i] = r.ID
	}
	taskIDs := make([]string, len(m.Tasks))
	for i, t := range m.Tasks {
		taskIDs[i] = t.ID
	}

	cfg := MatrixConfig{
		Name:                   name,
		ManifestPath:           manifestPath,
		RepoIDs:                repoIDs,
		TaskIDs:                taskIDs,
		TotalCells:             len(cells),
		MaxCells:               m.Defaults.MaxCells,
		MaxConsecutiveFailures: m.Defaults.MaxConsecutiveFailures,
		Timeout:                m.Defaults.Timeout,
		BeadID:                 beadID,
	}

	jsonlPath := filepath.Join(dir, "intermix.jsonl")
	if err := WriteConfig(jsonlPath, cfg); err != nil {
		return mcp.NewToolResultText(fmt.Sprintf("write config: %v", err)), nil
	}

	// Write manifest cache for run_cell to read
	manifestCache, _ := json.Marshal(m)
	os.WriteFile(filepath.Join(dir, ".intermix-manifest.json"), manifestCache, 0644)

	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("Campaign '%s' initialized.\n", name))
	sb.WriteString(fmt.Sprintf("Repos: %d | Tasks: %d | Total cells: %d\n", len(m.Repos), len(m.Tasks), len(cells)))
	sb.WriteString(fmt.Sprintf("Limits: max_cells=%d, max_consecutive_failures=%d, timeout=%s\n",
		cfg.MaxCells, cfg.MaxConsecutiveFailures, cfg.Timeout))
	sb.WriteString(fmt.Sprintf("\nCells to evaluate:\n"))
	for _, c := range cells {
		sb.WriteString(fmt.Sprintf("  - %s × %s\n", c.RepoID, c.TaskID))
	}

	return mcp.NewToolResultText(sb.String()), nil
}

func handleRunCell(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	repoID := req.GetString("repo", "")
	taskID := req.GetString("task", "")
	dir := resolveDir(req)

	if repoID == "" || taskID == "" {
		return mcp.NewToolResultText("missing required fields: repo, task"), nil
	}

	// Read state and check circuit breaker
	jsonlPath := filepath.Join(dir, "intermix.jsonl")
	state, err := ReconstructState(jsonlPath)
	if err != nil {
		return mcp.NewToolResultText(fmt.Sprintf("state error: %v", err)), nil
	}
	if state.SegmentID == 0 {
		return mcp.NewToolResultText("no campaign initialized — run init_matrix first"), nil
	}
	if err := state.CheckCircuitBreaker(); err != nil {
		return mcp.NewToolResultText(fmt.Sprintf("STOPPED: %v", err)), nil
	}

	// Check if already completed
	if state.CompletedCells[repoID+":"+taskID] {
		return mcp.NewToolResultText(fmt.Sprintf("cell %s:%s already completed in this campaign — skipping", repoID, taskID)), nil
	}

	// Load manifest from cache
	manifestData, err := os.ReadFile(filepath.Join(dir, ".intermix-manifest.json"))
	if err != nil {
		return mcp.NewToolResultText(fmt.Sprintf("manifest cache not found: %v — re-run init_matrix", err)), nil
	}
	var manifest Manifest
	json.Unmarshal(manifestData, &manifest)

	// Find repo and task
	var repo *Repo
	for i := range manifest.Repos {
		if manifest.Repos[i].ID == repoID {
			repo = &manifest.Repos[i]
			break
		}
	}
	var task *Task
	for i := range manifest.Tasks {
		if manifest.Tasks[i].ID == taskID {
			task = &manifest.Tasks[i]
			break
		}
	}
	if repo == nil || task == nil {
		return mcp.NewToolResultText(fmt.Sprintf("repo %q or task %q not found in manifest", repoID, taskID)), nil
	}

	cellID := fmt.Sprintf("%s-%s-%d", repoID, taskID, time.Now().Unix())
	cloneDir := filepath.Join(os.TempDir(), "intermix", cellID)
	os.MkdirAll(filepath.Dir(cloneDir), 0755)

	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("Running cell: %s × %s\n", repoID, taskID))

	// 1. Clone
	sb.WriteString(fmt.Sprintf("Cloning %s...\n", repo.URL))
	if err := CloneRepo(repo.URL, cloneDir); err != nil {
		rd := &RunDetails{CellID: cellID, Repo: repoID, Task: taskID, ExitCode: -1, Stderr: err.Error()}
		writeRunDetails(dir, rd)
		return mcp.NewToolResultText(fmt.Sprintf("Clone failed: %v\n\nClassify with: classify_result (outcome will be setup_failure)", err)), nil
	}

	// 2. Setup
	if repo.Setup != "" {
		sb.WriteString(fmt.Sprintf("Running setup: %s\n", repo.Setup))
		if err := RunSetup(cloneDir, repo.Setup); err != nil {
			rd := &RunDetails{CellID: cellID, Repo: repoID, Task: taskID, ExitCode: -1, Stderr: err.Error(), CloneDir: cloneDir}
			writeRunDetails(dir, rd)
			return mcp.NewToolResultText(fmt.Sprintf("Setup failed: %v\n\nClassify with: classify_result (outcome will be setup_failure)", err)), nil
		}
	}

	// 3. Spawn Skaffen
	timeout := state.Config.Timeout
	if repo.SkaffenConfig.Timeout != "" {
		timeout = repo.SkaffenConfig.Timeout
	}
	sb.WriteString(fmt.Sprintf("Spawning Skaffen (timeout: %s)...\n", timeout))
	rd := SpawnSkaffen(cloneDir, task.Prompt, timeout)
	rd.CellID = cellID
	rd.Repo = repoID
	rd.Task = taskID

	// 4. Validate
	valCmd := task.ValidationCmd
	if valCmd == "" {
		valCmd = InferValidationCmd(cloneDir, repo.Language)
	}
	if valCmd != "" {
		sb.WriteString(fmt.Sprintf("Validating: %s\n", valCmd))
		vr := RunValidation(cloneDir, valCmd)
		rd.ValidationPassed = vr.Passed
		rd.ValidationOutput = vr.Output
	}

	// Save run details for classify_result
	writeRunDetails(dir, rd)

	sb.WriteString(fmt.Sprintf("\nResult: exit=%d, duration=%dms, files_changed=%d, validation=%v\n",
		rd.ExitCode, rd.DurationMs, rd.FilesChanged, rd.ValidationPassed))

	// Include tail of output
	if rd.Stdout != "" {
		lines := strings.Split(rd.Stdout, "\n")
		start := len(lines) - 20
		if start < 0 {
			start = 0
		}
		sb.WriteString(fmt.Sprintf("\nOutput (last 20 lines):\n%s\n", strings.Join(lines[start:], "\n")))
	}

	sb.WriteString("\nNext: call classify_result to record the outcome.")

	return mcp.NewToolResultText(sb.String()), nil
}

func handleClassifyResult(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	dir := resolveDir(req)
	llmAnalysis := req.GetString("llm_analysis", "")

	// Read run details
	rd, err := readRunDetails(dir)
	if err != nil {
		return mcp.NewToolResultText(fmt.Sprintf("no run details found: %v — run run_cell first", err)), nil
	}

	// Classify
	cr := ClassifyFromRunDetails(rd, rd.Repo, rd.Task)
	cr.LLMAnalysis = llmAnalysis

	// Handle setup failures explicitly
	if rd.ExitCode == -1 && (rd.FilesChanged == 0 && rd.DurationMs == 0) {
		cr.Outcome = OutcomeSetupFailure
		cr.Severity = SeverityCritical
		cr.FailureReason = rd.Stderr
	}

	// Write to JSONL
	jsonlPath := filepath.Join(dir, "intermix.jsonl")
	if err := WriteCellResult(jsonlPath, cr); err != nil {
		return mcp.NewToolResultText(fmt.Sprintf("write error: %v", err)), nil
	}

	// Clean up run details
	os.Remove(filepath.Join(dir, ".intermix-run.json"))

	return mcp.NewToolResultText(fmt.Sprintf("Classified: %s:%s → %s (%s)\nAnalysis: %s",
		cr.Repo, cr.Task, cr.Outcome, cr.Severity, cr.LLMAnalysis)), nil
}

func handleReportMatrix(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	dir := resolveDir(req)
	format := req.GetString("format", "text")

	jsonlPath := filepath.Join(dir, "intermix.jsonl")
	state, err := ReconstructState(jsonlPath)
	if err != nil {
		return mcp.NewToolResultText(fmt.Sprintf("state error: %v", err)), nil
	}
	if state.SegmentID == 0 {
		return mcp.NewToolResultText("no campaign found — run init_matrix first"), nil
	}

	// For delta: load previous segment if exists (segment > 1)
	var prevResults []CellResult
	if state.SegmentID > 1 {
		prevResults = loadPreviousSegment(jsonlPath, state.SegmentID-1)
	}

	report := GenerateReport(state.Results, prevResults)

	if format == "json" {
		data, _ := json.MarshalIndent(report, "", "  ")
		return mcp.NewToolResultText(string(data)), nil
	}

	return mcp.NewToolResultText(FormatReport(report)), nil
}

func writeRunDetails(dir string, rd *RunDetails) {
	data, _ := json.Marshal(rd)
	os.WriteFile(filepath.Join(dir, ".intermix-run.json"), data, 0644)
}

func readRunDetails(dir string) (*RunDetails, error) {
	data, err := os.ReadFile(filepath.Join(dir, ".intermix-run.json"))
	if err != nil {
		return nil, err
	}
	var rd RunDetails
	if err := json.Unmarshal(data, &rd); err != nil {
		return nil, err
	}
	return &rd, nil
}

// loadPreviousSegment finds results from a specific segment number.
func loadPreviousSegment(path string, targetSegment int) []CellResult {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil
	}

	segment := 0
	var results []CellResult

	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		if strings.Contains(line, `"type":"config"`) {
			segment++
			if segment > targetSegment {
				break
			}
			results = nil // reset for current segment
		} else if segment == targetSegment && strings.Contains(line, `"type":"cell_result"`) {
			var cr CellResult
			json.Unmarshal([]byte(line), &cr)
			results = append(results, cr)
		}
	}
	return results
}
```

**Step 4: Run tests**

Run: `cd interverse/intermix && go test ./internal/eval/ -run TestHandleInitMatrix -v`
Expected: PASS

**Step 5: Commit**

```bash
cd interverse/intermix && git add internal/eval/tools.go internal/eval/tools_test.go
git commit -m "feat: MCP tool handlers wiring all components together"
```

<verify>
- run: `cd interverse/intermix && go test ./internal/eval/ -v`
  expect: exit 0
- run: `cd interverse/intermix && go build ./cmd/intermix-mcp/`
  expect: exit 0
</verify>

---

### Task 8: IC Events Bridge

**Files:**
- Create: `interverse/intermix/internal/eval/ic.go`
- Create: `interverse/intermix/internal/eval/ic_test.go`

**Step 1: Write the failing test**

```go
package eval

import (
	"testing"
)

func TestEmitCellEvent_GracefulDegradation(t *testing.T) {
	// Should not error even if ic is not installed
	cr := CellResult{Repo: "chi", Task: "add-test", Outcome: OutcomeSuccess}
	err := EmitCellEvent(cr, "Sylveste-ome7")
	if err != nil {
		t.Errorf("expected graceful degradation, got: %v", err)
	}
}
```

**Step 2: Write ic.go** (mirrors interlab/internal/experiment/ic.go)

```go
package eval

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"
)

// EmitCellEvent records a cell_evaluation event via ic CLI.
// Gracefully degrades if ic is not available.
func EmitCellEvent(cr CellResult, beadID string) error {
	if _, err := exec.LookPath("ic"); err != nil {
		return nil // ic not available, degrade gracefully
	}

	payload := map[string]interface{}{
		"repo":              cr.Repo,
		"task":              cr.Task,
		"outcome":           cr.Outcome,
		"severity":          cr.Severity,
		"validation_passed": cr.ValidationPassed,
		"duration_ms":       cr.DurationMs,
		"files_changed":     cr.FilesChanged,
		"tokens_used":       cr.TokensUsed,
	}

	payloadJSON, _ := json.Marshal(payload)

	args := []string{"events", "record",
		"--source=intermix",
		"--type=cell_evaluation",
		fmt.Sprintf("--payload=%s", string(payloadJSON)),
	}
	if beadID != "" {
		args = append(args, fmt.Sprintf("--bead=%s", beadID))
	}

	cmd := exec.Command("ic", args...)
	_ = cmd.Run() // best-effort
	return nil
}

// EmitCampaignEvent records campaign-level summary events.
func EmitCampaignEvent(report *Report, campaignName, beadID string) error {
	if _, err := exec.LookPath("ic"); err != nil {
		return nil
	}

	payload := map[string]interface{}{
		"campaign":      campaignName,
		"total_cells":   report.TotalCells,
		"pass_rate":     report.PassRate,
		"success_count": report.SuccessCount,
		"failure_count": report.FailureCount,
		"clusters":      len(report.FailureClusters),
	}
	if report.Delta != nil {
		payload["fixed"] = report.Delta.Fixed
		payload["regressed"] = report.Delta.Regressed
	}

	payloadJSON, _ := json.Marshal(payload)

	args := []string{"events", "record",
		"--source=intermix",
		"--type=campaign_summary",
		fmt.Sprintf("--payload=%s", string(payloadJSON)),
	}
	if beadID != "" {
		args = append(args, fmt.Sprintf("--bead=%s", beadID))
	}

	_ = strings.TrimSpace("") // avoid unused import
	cmd := exec.Command("ic", args...)
	_ = cmd.Run()
	return nil
}
```

**Step 3: Run tests**

Run: `cd interverse/intermix && go test ./internal/eval/ -run TestEmitCellEvent -v`
Expected: PASS

**Step 4: Commit**

```bash
cd interverse/intermix && git add internal/eval/ic.go internal/eval/ic_test.go
git commit -m "feat: ic events bridge with graceful degradation"
```

<verify>
- run: `cd interverse/intermix && go test ./internal/eval/ -run TestEmitCellEvent -v`
  expect: exit 0
</verify>

---

### Task 9: Starter YAML Manifest with 12 Repos

**Files:**
- Create: `interverse/intermix/examples/skaffen-stress.yaml`

**Step 1: Write the starter manifest**

```yaml
# intermix.yaml — Skaffen cross-repo stress test matrix
# 12 repos × 5 tasks (3 generic + 2 repo-specific) = 60 cells

repos:
  # Go (primary)
  - id: chi
    url: https://github.com/go-chi/chi
    setup: go mod download
    language: go
    complexity: small

  - id: cobra
    url: https://github.com/spf13/cobra
    setup: go mod download
    language: go
    complexity: medium

  - id: zap
    url: https://github.com/uber-go/zap
    setup: go mod download
    language: go
    complexity: medium

  - id: viper
    url: https://github.com/spf13/viper
    setup: go mod download
    language: go
    complexity: medium

  # TypeScript
  - id: zod
    url: https://github.com/colinhacks/zod
    setup: npm install
    language: typescript
    complexity: small

  - id: fastify
    url: https://github.com/fastify/fastify
    setup: npm install
    language: typescript
    complexity: large
    skaffen_config:
      timeout: 600s

  - id: commander
    url: https://github.com/tj/commander.js
    setup: npm install
    language: typescript
    complexity: small

  # Python
  - id: click
    url: https://github.com/pallets/click
    setup: pip install -e .
    language: python
    complexity: medium

  - id: httpx
    url: https://github.com/encode/httpx
    setup: pip install -e ".[test]"
    language: python
    complexity: medium

  - id: pydantic
    url: https://github.com/pydantic/pydantic
    setup: pip install -e .
    language: python
    complexity: large
    skaffen_config:
      timeout: 600s

  # Rust
  - id: clap
    url: https://github.com/clap-rs/clap
    setup: cargo fetch
    language: rust
    complexity: medium

  - id: axum
    url: https://github.com/tokio-rs/axum
    setup: cargo fetch
    language: rust
    complexity: medium

tasks:
  # Generic templates (all repos)
  - id: add-test
    prompt: |
      Find a public function in this repository that lacks unit test coverage.
      Write a focused unit test for it. The test should verify the function's
      core behavior with at least one positive case and one edge case.
    difficulty: easy
    tags: [testing, single-file]
    target: auto

  - id: refactor-extract
    prompt: |
      Find a function in this repository that is longer than 40 lines.
      Extract a meaningful helper function from it. Update all callers.
      All existing tests must still pass after refactoring.
    difficulty: medium
    tags: [refactor, multi-file]
    target: auto

  - id: add-feature
    prompt: |
      Read the README and understand what this library does. Add a small,
      useful feature that extends existing functionality. Include tests
      for the new feature. All existing tests must still pass.
    difficulty: hard
    tags: [feature, multi-file]
    target: auto

  # Repo-specific tasks (declared per-repo)
  - id: chi-middleware
    prompt: "Add a middleware to chi that logs the request method, path, and response time to stdout in a structured format."
    difficulty: medium
    tags: [feature, web]
    repos: [chi]
    validation_cmd: "go test ./..."

  - id: chi-route-group
    prompt: "Add a new route group /api/v2/health with a GET handler that returns JSON {\"status\": \"ok\", \"version\": \"2\"}. Include a test."
    difficulty: easy
    tags: [feature, web]
    repos: [chi]
    validation_cmd: "go test ./..."

  - id: cobra-subcommand
    prompt: "Add a 'version' subcommand to the example cobra app that prints version info in semver format. Include flag --json for JSON output. Add tests."
    difficulty: medium
    tags: [feature, cli]
    repos: [cobra]
    validation_cmd: "go test ./..."

  - id: cobra-flag-validation
    prompt: "Add input validation to an existing command's string flag — reject empty strings and strings longer than 255 characters. Include tests for both cases."
    difficulty: easy
    tags: [testing, cli]
    repos: [cobra]
    validation_cmd: "go test ./..."

  - id: zap-custom-encoder
    prompt: "Add a custom field encoder that formats time.Duration values as human-readable strings (e.g., '2m30s'). Include benchmarks."
    difficulty: hard
    tags: [feature, library]
    repos: [zap]
    validation_cmd: "go test ./..."

  - id: zap-level-filter
    prompt: "Write a test that verifies log level filtering works correctly — debug messages excluded at info level, etc."
    difficulty: easy
    tags: [testing, library]
    repos: [zap]
    validation_cmd: "go test ./..."

  - id: viper-env-prefix
    prompt: "Write a test that verifies environment variable binding with a custom prefix works correctly. Test with SetEnvPrefix and BindEnv."
    difficulty: easy
    tags: [testing, config]
    repos: [viper]
    validation_cmd: "go test ./..."

  - id: viper-merge-config
    prompt: "Write a test that verifies merging two config sources (file + env) with env taking precedence."
    difficulty: medium
    tags: [testing, config]
    repos: [viper]
    validation_cmd: "go test ./..."

  - id: zod-custom-type
    prompt: "Add a custom Zod schema type for validating ISO 8601 date strings. Include tests for valid dates, invalid formats, and edge cases."
    difficulty: medium
    tags: [feature, validation]
    repos: [zod]
    validation_cmd: "npm test"

  - id: zod-error-format
    prompt: "Write tests that verify error message formatting for deeply nested object validation failures."
    difficulty: easy
    tags: [testing, validation]
    repos: [zod]
    validation_cmd: "npm test"

  - id: fastify-plugin
    prompt: "Create a simple Fastify plugin that adds a /metrics endpoint returning JSON with request count and uptime. Include tests."
    difficulty: hard
    tags: [feature, web]
    repos: [fastify]
    validation_cmd: "npm test"

  - id: fastify-hook
    prompt: "Write a test for Fastify's onRequest hook that verifies headers are accessible and the hook chain executes in order."
    difficulty: medium
    tags: [testing, web]
    repos: [fastify]
    validation_cmd: "npm test"

  - id: commander-help
    prompt: "Write a test that verifies the help output format for a command with subcommands, options, and aliases."
    difficulty: easy
    tags: [testing, cli]
    repos: [commander]
    validation_cmd: "npm test"

  - id: commander-action
    prompt: "Add a new 'init' command that creates a config file with sensible defaults. Include tests."
    difficulty: medium
    tags: [feature, cli]
    repos: [commander]
    validation_cmd: "npm test"

  - id: click-progress
    prompt: "Write a test that verifies click.progressbar works correctly with a mock iterable."
    difficulty: easy
    tags: [testing, cli]
    repos: [click]
    validation_cmd: "pytest"

  - id: click-file-param
    prompt: "Add a new command that accepts a --config file parameter with validation for JSON format. Include tests."
    difficulty: medium
    tags: [feature, cli]
    repos: [click]
    validation_cmd: "pytest"

  - id: httpx-retry
    prompt: "Write tests for httpx retry behavior — verify exponential backoff, max retries, and retry-after header handling."
    difficulty: medium
    tags: [testing, http]
    repos: [httpx]
    validation_cmd: "pytest"

  - id: httpx-timeout
    prompt: "Write a test that verifies timeout configuration works for connect, read, and write timeouts independently."
    difficulty: easy
    tags: [testing, http]
    repos: [httpx]
    validation_cmd: "pytest"

  - id: pydantic-validator
    prompt: "Add a custom validator that validates email addresses with a specific domain suffix. Include tests for valid, invalid, and edge cases."
    difficulty: medium
    tags: [feature, validation]
    repos: [pydantic]
    validation_cmd: "pytest"

  - id: pydantic-serialization
    prompt: "Write tests that verify custom JSON serialization for models with datetime, Decimal, and UUID fields."
    difficulty: easy
    tags: [testing, validation]
    repos: [pydantic]
    validation_cmd: "pytest"

  - id: clap-derive
    prompt: "Add a new CLI subcommand using clap's derive macro with custom validation for a port number argument (1-65535). Include tests."
    difficulty: hard
    tags: [feature, cli]
    repos: [clap]
    validation_cmd: "cargo test"

  - id: clap-help-format
    prompt: "Write a test that verifies the help output includes all expected sections: usage, args, options, subcommands."
    difficulty: easy
    tags: [testing, cli]
    repos: [clap]
    validation_cmd: "cargo test"

  - id: axum-middleware
    prompt: "Add a middleware layer that measures request duration and adds it as a response header. Include integration tests."
    difficulty: hard
    tags: [feature, web]
    repos: [axum]
    validation_cmd: "cargo test"

  - id: axum-error-handler
    prompt: "Write tests for custom error handling — verify that different error types map to correct HTTP status codes and response bodies."
    difficulty: medium
    tags: [testing, web]
    repos: [axum]
    validation_cmd: "cargo test"

defaults:
  timeout: 300s
  max_cells: 100
  max_consecutive_failures: 5
  max_duration: 4h
```

**Step 2: Validate YAML parses**

Run: `cd interverse/intermix && go test ./internal/eval/ -run TestParseManifest -v` (using the test from Task 2)

**Step 3: Commit**

```bash
cd interverse/intermix && git add examples/skaffen-stress.yaml
git commit -m "feat: starter manifest with 12 repos and 36 tasks"
```

<verify>
- run: `python3 -c "import yaml; yaml.safe_load(open('interverse/intermix/examples/skaffen-stress.yaml'))"`
  expect: exit 0
</verify>

---

### Task 10: Evaluate Skill (SKILL.md)

**Files:**
- Create: `interverse/intermix/skills/evaluate/SKILL.md`

**Step 1: Write the skill protocol**

```markdown
---
name: evaluate
description: Run a cross-repo matrix evaluation of Skaffen using intermix tools
---

# /evaluate — Cross-Repo Matrix Evaluation

Run Skaffen against unfamiliar codebases across a (repo, task) matrix. Classify outcomes, generate reports, create beads for failure patterns.

## Prerequisites

- intermix plugin installed (`claude plugin install intermix`)
- `skaffen` binary on PATH (`command -v skaffen`)
- `intermix.yaml` manifest in working directory (or pass path)

## Protocol

### Phase 1: Initialize

1. Check for existing campaign:
   - If `intermix.jsonl` exists, call `report_matrix` to show current state
   - Ask: "Resume this campaign or start fresh?"

2. Initialize new campaign:
   ```
   init_matrix(manifest_path="intermix.yaml", name="<descriptive-name>", bead_id="<parent-bead>")
   ```

3. Note the cell list and total count.

### Phase 2: Execute Matrix

Iterate through each cell sequentially. For each cell:

1. **Run the cell:**
   ```
   run_cell(repo="<repo-id>", task="<task-id>")
   ```

2. **Read the output.** Look for:
   - Exit code (0 = clean exit, non-zero = error)
   - Files changed count
   - Validation result (passed/failed)
   - Stdout/stderr content

3. **Classify the result.** Based on the output, write a brief analysis:
   ```
   classify_result(llm_analysis="<your analysis of what happened and why>")
   ```

   Classification guidelines:
   - **success**: validation passed, files changed, clean exit
   - **partial**: files changed but validation failed — describe what was attempted
   - **no_progress**: no files changed — describe what Skaffen tried to do
   - **context_limit**: look for "context" or "token" in stderr
   - **timeout**: look for "deadline" or "timeout" in stderr
   - **setup_failure**: clone or setup command failed
   - **crash**: process died with signal

4. **Log progress** every 5 cells:
   ```
   Cell 5/60: chi×add-test ✔ | cobra×refactor ✖ (context_limit) | ...
   ```

5. **Stop if circuit breaker trips** (tool returns STOPPED message).

### Phase 3: Report

After all cells complete (or circuit breaker trips):

1. Generate report:
   ```
   report_matrix(bead_id="<parent-bead>")
   ```

2. Review the report. Highlight:
   - Overall pass rate
   - Worst-performing repos (most failures)
   - Worst-performing tasks (lowest pass rate)
   - Failure clusters with ≥2 cells
   - Delta vs. previous campaign (if applicable)

3. If failure clusters exist and bead_id was provided, beads are auto-created.

### Phase 4: Archive

1. Copy results to campaign archive:
   ```bash
   mkdir -p campaigns/<campaign-name>/
   cp intermix.jsonl campaigns/<campaign-name>/results.jsonl
   ```

2. Write learnings document:
   ```bash
   # campaigns/<campaign-name>/learnings.md
   # - What worked well
   # - Failure patterns and root causes
   # - Suggested fixes for Skaffen
   # - Repos/tasks to add or remove
   ```

## Circuit Breaker

The matrix automatically stops if:
- 5 consecutive failures (something systemic is broken)
- 100 total cells (budget cap)

If tripped, the report still generates for completed cells.

## Tips

- Start with a small manifest (2 repos × 2 tasks) to verify the pipeline works
- Use `--filter=failed` on repeat runs to only re-test failures
- The LLM analysis field is your most valuable output — be specific about root causes
```

**Step 2: Commit**

```bash
cd interverse/intermix && mkdir -p skills/evaluate && git add skills/evaluate/SKILL.md
git commit -m "feat: /evaluate skill with matrix execution protocol"
```

<verify>
- run: `test -f interverse/intermix/skills/evaluate/SKILL.md`
  expect: exit 0
</verify>

---

### Task 11: Integration Test — Full Pipeline

**Files:**
- Create: `interverse/intermix/internal/eval/integration_test.go`

**Step 1: Write the integration test**

```go
package eval

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/mark3labs/mcp-go/mcp"
)

func TestFullPipeline(t *testing.T) {
	dir := t.TempDir()

	// Write a minimal manifest
	yaml := `
repos:
  - id: test-repo
    url: /dev/null
    language: go
tasks:
  - id: test-task
    prompt: "Write a test"
defaults:
  max_cells: 10
  max_consecutive_failures: 3
`
	os.WriteFile(filepath.Join(dir, "intermix.yaml"), []byte(yaml), 0644)

	// Step 1: init_matrix
	initReq := mcp.CallToolRequest{}
	initReq.Params.Arguments = map[string]interface{}{
		"manifest_path":     filepath.Join(dir, "intermix.yaml"),
		"name":              "integration-test",
		"working_directory": dir,
	}
	result, err := handleInitMatrix(context.Background(), initReq)
	if err != nil {
		t.Fatalf("init_matrix: %v", err)
	}
	t.Logf("init_matrix: %s", result.Content[0].(mcp.TextContent).Text)

	// Verify JSONL exists
	jsonlPath := filepath.Join(dir, "intermix.jsonl")
	if _, err := os.Stat(jsonlPath); err != nil {
		t.Fatal("intermix.jsonl not created")
	}

	// Step 2: Simulate a run by writing RunDetails directly
	rd := &RunDetails{
		CellID:           "test-repo-test-task-1",
		Repo:             "test-repo",
		Task:             "test-task",
		ExitCode:         0,
		DurationMs:       5000,
		FilesChanged:     2,
		ValidationPassed: true,
	}
	writeRunDetails(dir, rd)

	// Step 3: classify_result
	classifyReq := mcp.CallToolRequest{}
	classifyReq.Params.Arguments = map[string]interface{}{
		"working_directory": dir,
		"llm_analysis":      "Skaffen successfully identified an untested function and wrote a passing test.",
	}
	result, err = handleClassifyResult(context.Background(), classifyReq)
	if err != nil {
		t.Fatalf("classify_result: %v", err)
	}
	text := result.Content[0].(mcp.TextContent).Text
	if text == "" {
		t.Error("classify_result returned empty")
	}
	t.Logf("classify_result: %s", text)

	// Step 4: report_matrix
	reportReq := mcp.CallToolRequest{}
	reportReq.Params.Arguments = map[string]interface{}{
		"working_directory": dir,
	}
	result, err = handleReportMatrix(context.Background(), reportReq)
	if err != nil {
		t.Fatalf("report_matrix: %v", err)
	}
	t.Logf("report_matrix: %s", result.Content[0].(mcp.TextContent).Text)

	// Verify state
	state, _ := ReconstructState(jsonlPath)
	if state.SuccessCount != 1 {
		t.Errorf("success count: got %d, want 1", state.SuccessCount)
	}
}
```

**Step 2: Run integration test**

Run: `cd interverse/intermix && go test ./internal/eval/ -run TestFullPipeline -v`
Expected: PASS

**Step 3: Commit**

```bash
cd interverse/intermix && git add internal/eval/integration_test.go
git commit -m "test: integration test covering full init → run → classify → report pipeline"
```

<verify>
- run: `cd interverse/intermix && go test ./internal/eval/ -run TestFullPipeline -v`
  expect: exit 0
- run: `cd interverse/intermix && go test ./... -count=1`
  expect: exit 0
</verify>

---

### Task 12: Build Binary & Verify Plugin Loads

**Step 1: Build the binary**

```bash
cd interverse/intermix && go build -o bin/intermix-mcp ./cmd/intermix-mcp/
```

**Step 2: Make launch script executable**

```bash
chmod +x interverse/intermix/bin/launch-mcp.sh
```

**Step 3: Verify the binary starts and responds to MCP init**

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0.1.0"}}}' | interverse/intermix/bin/intermix-mcp 2>/dev/null | head -1
```
Expected: JSON response containing `"serverInfo"` with name `"intermix"`

**Step 4: Final commit**

```bash
cd interverse/intermix && git add -A
git commit -m "chore: build binary and make launcher executable"
```

<verify>
- run: `cd interverse/intermix && go build -o bin/intermix-mcp ./cmd/intermix-mcp/`
  expect: exit 0
- run: `test -x interverse/intermix/bin/launch-mcp.sh`
  expect: exit 0
</verify>
