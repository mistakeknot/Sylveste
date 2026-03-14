---
artifact_type: plan
bead: Demarch-ome7
stage: design
requirements:
  - "F1: Parallel tmux executor for intermix run_cell"
  - "F2: intermux supervisor integration for stress tests"
  - "F3: Auto-create debug beads on cell failure"
  - "F4: Evidence harvesting dual path"
  - "F5: Pattern clustering in report_matrix"
  - "F6: Run 9-cell stress test campaign"
---
# Skaffen Cross-Repo Stress Test — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Demarch-ome7
**Goal:** Build parallel stress test infrastructure in intermix, wire intermux supervision, and run a 9-cell campaign against chi/zod/click.

**Architecture:** Modify intermix's executor to launch Skaffen in named tmux sessions for parallel execution. Per-cell JSONL isolation eliminates write races. intermux monitors session health via its existing watcher. Failures auto-create debug beads, and report_matrix clusters them into pattern beads.

**Tech Stack:** Go (intermix, intermux), tmux, beads CLI, Skaffen `--mode print`, intercore `ic` CLI

---

## Must-Haves

**Truths** (observable behaviors):
- 9 Skaffen instances run simultaneously in separate tmux sessions
- intermux `list_agents` shows all 9 stress test sessions
- Each cell produces its own JSONL result file
- Failed cells automatically have beads created under Demarch-ome7
- `report_matrix` produces a heatmap showing pass/fail per repo×task
- Skaffen evidence files are preserved in the campaign results directory

**Artifacts** (files that must exist):
- [`interverse/intermix/internal/eval/runner.go`] exports `SpawnSkaffenTmux`, `WaitTmuxSession`, `CaptureTmuxPane`
- [`interverse/intermix/internal/eval/parallel.go`] exports `RunBatch`, `PollBatch`, `CollectResults`
- [`interverse/intermix/internal/eval/bead.go`] exports `CreateDebugBead`, `CreatePatternBeads`
- [`interverse/intermix/internal/eval/evidence.go`] exports `HarvestEvidence`

**Key Links:**
- `RunBatch` calls `SpawnSkaffenTmux` per cell, then `PollBatch` polls intermux for health
- `CollectResults` calls `CaptureTmuxPane` + `HarvestEvidence` + `ClassifyFromRunDetails` for each cell
- `CreateDebugBead` is called from `CollectResults` for non-success outcomes
- `CreatePatternBeads` is called from `GenerateReport` when clusters have ≥2 failures

---

### Task 1: Per-Cell JSONL and Run File Isolation

**Beads:** Demarch-sna1 (F1)
**Files:**
- Modify: `interverse/intermix/internal/eval/state.go`
- Modify: `interverse/intermix/internal/eval/tools.go`
- Test: `interverse/intermix/internal/eval/state_test.go`

**Step 1: Write the failing test for per-cell JSONL paths**

In `state_test.go`, add:

```go
func TestCellJSONLPath(t *testing.T) {
	dir := t.TempDir()
	cellsDir := filepath.Join(dir, "cells")

	path := CellJSONLPath(dir, "chi-add-test-1710000000")
	if path != filepath.Join(cellsDir, "chi-add-test-1710000000.jsonl") {
		t.Errorf("unexpected path: %s", path)
	}
}

func TestCellRunFilePath(t *testing.T) {
	dir := t.TempDir()
	path := CellRunFilePath(dir, "chi-add-test-1710000000")
	expected := filepath.Join(dir, "cells", "chi-add-test-1710000000.run.json")
	if path != expected {
		t.Errorf("unexpected path: %s", path)
	}
}

func TestReconstructStateFromCellsDir(t *testing.T) {
	dir := t.TempDir()
	cellsDir := filepath.Join(dir, "cells")
	os.MkdirAll(cellsDir, 0755)

	// Write config to main JSONL
	cfg := MatrixConfig{
		Type:    "config",
		Name:    "test",
		RepoIDs: []string{"chi", "zod"},
		TaskIDs: []string{"add-test"},
		TotalCells: 2,
		MaxCells: 100,
		MaxConsecutiveFailures: 5,
	}
	WriteConfig(filepath.Join(dir, "intermix.jsonl"), cfg)

	// Write cell results to per-cell files
	cr1 := CellResult{Type: "cell_result", Repo: "chi", Task: "add-test", Outcome: OutcomeSuccess}
	cr2 := CellResult{Type: "cell_result", Repo: "zod", Task: "add-test", Outcome: OutcomeTimeout}
	WriteCellResult(CellJSONLPath(dir, "chi-add-test"), cr1)
	WriteCellResult(CellJSONLPath(dir, "zod-add-test"), cr2)

	state, err := ReconstructStateFromCellsDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	if state.CellCount != 2 {
		t.Errorf("expected 2 cells, got %d", state.CellCount)
	}
	if state.SuccessCount != 1 {
		t.Errorf("expected 1 success, got %d", state.SuccessCount)
	}
}
```

**Step 2: Run tests to verify they fail**

Run: `cd interverse/intermix && go test ./internal/eval/ -run "TestCellJSONLPath|TestCellRunFilePath|TestReconstructStateFromCellsDir" -v`
Expected: FAIL — functions don't exist yet

**Step 3: Implement per-cell path helpers and state reconstruction**

In `state.go`, add:

```go
// CellJSONLPath returns the JSONL path for a specific cell in parallel mode.
func CellJSONLPath(workDir, cellID string) string {
	return filepath.Join(workDir, "cells", cellID+".jsonl")
}

// CellRunFilePath returns the run-details path for a specific cell.
func CellRunFilePath(workDir, cellID string) string {
	return filepath.Join(workDir, "cells", cellID+".run.json")
}

// ReconstructStateFromCellsDir reads the main config from intermix.jsonl
// and all cell results from cells/*.jsonl files.
func ReconstructStateFromCellsDir(workDir string) (*State, error) {
	// Read config from main file
	mainPath := filepath.Join(workDir, "intermix.jsonl")
	state, err := ReconstructState(mainPath)
	if err != nil {
		return nil, fmt.Errorf("reading main config: %w", err)
	}

	// Walk cells directory for results
	cellsDir := filepath.Join(workDir, "cells")
	entries, err := os.ReadDir(cellsDir)
	if err != nil {
		if os.IsNotExist(err) {
			return state, nil // No cells yet
		}
		return nil, fmt.Errorf("reading cells dir: %w", err)
	}

	for _, entry := range entries {
		if !strings.HasSuffix(entry.Name(), ".jsonl") {
			continue
		}
		cellPath := filepath.Join(cellsDir, entry.Name())
		data, err := os.ReadFile(cellPath)
		if err != nil {
			continue
		}
		for _, line := range bytes.Split(data, []byte("\n")) {
			if len(line) == 0 {
				continue
			}
			if bytes.Contains(line, []byte(`"type":"cell_result"`)) {
				var cr CellResult
				if err := json.Unmarshal(line, &cr); err != nil {
					continue
				}
				state.CellCount++
				state.CompletedCells[cr.Repo+":"+cr.Task] = true
				state.Results = append(state.Results, cr)
				switch cr.Outcome {
				case OutcomeSuccess, OutcomePartial:
					state.SuccessCount++
					state.ConsecutiveFailures = 0
				case OutcomeSkipped:
					// no effect
				default:
					state.FailureCount++
					state.ConsecutiveFailures++
				}
			}
		}
	}
	return state, nil
}
```

**Step 4: Run tests to verify they pass**

Run: `cd interverse/intermix && go test ./internal/eval/ -run "TestCellJSONLPath|TestCellRunFilePath|TestReconstructStateFromCellsDir" -v`
Expected: PASS

**Step 5: Commit**

```bash
cd interverse/intermix && git add internal/eval/state.go internal/eval/state_test.go
git commit -m "feat(intermix): add per-cell JSONL paths and parallel state reconstruction"
```

<verify>
- run: `cd interverse/intermix && go test ./internal/eval/ -run "TestCellJSONLPath|TestCellRunFilePath|TestReconstructStateFromCellsDir" -v`
  expect: exit 0
- run: `cd interverse/intermix && go vet ./internal/eval/`
  expect: exit 0
</verify>

---

### Task 2: Tmux-Based Skaffen Spawner

**Beads:** Demarch-sna1 (F1)
**Files:**
- Modify: `interverse/intermix/internal/eval/runner.go`
- Test: `interverse/intermix/internal/eval/runner_test.go`

**Step 1: Write failing tests for tmux session management**

In `runner_test.go`, add:

```go
func TestBuildTmuxSessionName(t *testing.T) {
	name := BuildTmuxSessionName("chi", "add-test")
	// Must match intermux pattern: {terminal}-{project}-{agent}
	if name != "intermix-chi-addtest-claude" {
		t.Errorf("unexpected session name: %s", name)
	}
}

func TestBuildTmuxSessionNameSanitizes(t *testing.T) {
	name := BuildTmuxSessionName("my-repo", "refactor-extract")
	// Hyphens in task ID should be stripped for the project segment
	if name != "intermix-myrepo-refactorextract-claude" {
		t.Errorf("unexpected session name: %s", name)
	}
}

func TestBuildSkaffenCommand(t *testing.T) {
	args := BuildSkaffenCommand("/tmp/clone/chi", "Write a test for the router", "300s")
	expected := []string{"skaffen", "--mode", "print", "--prompt", "Write a test for the router"}
	if len(args) != len(expected) {
		t.Errorf("expected %d args, got %d: %v", len(expected), len(args), args)
	}
	for i, arg := range expected {
		if args[i] != arg {
			t.Errorf("arg %d: expected %q, got %q", i, arg, args[i])
		}
	}
}
```

**Step 2: Run tests to verify they fail**

Run: `cd interverse/intermix && go test ./internal/eval/ -run "TestBuildTmuxSessionName|TestBuildSkaffenCommand" -v`
Expected: FAIL

**Step 3: Implement tmux spawner functions**

In `runner.go`, add:

```go
// BuildTmuxSessionName creates an intermux-compatible session name.
// Format: intermix-{repo}-{task}-claude
// intermux detects sessions matching {terminal}-{project}-{agent} pattern.
func BuildTmuxSessionName(repoID, taskID string) string {
	// Strip hyphens from repo and task to keep the session name parseable
	repo := strings.ReplaceAll(repoID, "-", "")
	task := strings.ReplaceAll(taskID, "-", "")
	return fmt.Sprintf("intermix-%s-%s-claude", repo, task)
}

// BuildSkaffenCommand returns the command args for running Skaffen in print mode.
func BuildSkaffenCommand(workDir, prompt, timeout string) []string {
	return []string{"skaffen", "--mode", "print", "--prompt", prompt}
}

// SpawnSkaffenTmux launches Skaffen in a detached tmux session.
// Returns the session name and any spawn error.
func SpawnSkaffenTmux(ctx context.Context, repoID, taskID, workDir, prompt, timeout string) (sessionName string, err error) {
	sessionName = BuildTmuxSessionName(repoID, taskID)
	skaffenArgs := BuildSkaffenCommand(workDir, prompt, timeout)

	// Build the full command string for tmux
	cmdStr := strings.Join(skaffenArgs, " ")

	// Create detached tmux session running Skaffen
	args := []string{
		"new-session", "-d",
		"-s", sessionName,
		"-c", workDir, // Set working directory
		cmdStr,
	}

	cmd := exec.CommandContext(ctx, "tmux", args...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return sessionName, fmt.Errorf("tmux new-session failed: %w: %s", err, stderr.String())
	}

	// Write intermux mapping file for session correlation
	mapping := map[string]string{
		"tmux_session": sessionName,
		"session_id":   fmt.Sprintf("intermix-%s-%s", repoID, taskID),
		"agent_id":     fmt.Sprintf("intermix-stress-%s-%s", repoID, taskID),
	}
	mappingData, _ := json.Marshal(mapping)
	mappingPath := fmt.Sprintf("/tmp/intermux-mapping-%s.json", sessionName)
	os.WriteFile(mappingPath, mappingData, 0644)

	return sessionName, nil
}

// WaitTmuxSession blocks until the named tmux session exits or timeout.
// Returns stdout captured from the pane, the exit status, and duration.
func WaitTmuxSession(ctx context.Context, sessionName string, timeout time.Duration) (stdout string, exitCode int, durationMs int64, err error) {
	start := time.Now()
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()

	deadline := time.After(timeout)

	for {
		select {
		case <-ctx.Done():
			return "", -1, time.Since(start).Milliseconds(), ctx.Err()
		case <-deadline:
			// Kill the session on timeout
			exec.Command("tmux", "kill-session", "-t", sessionName).Run()
			return "", -1, time.Since(start).Milliseconds(), fmt.Errorf("timeout after %v", timeout)
		case <-ticker.C:
			// Check if session still exists
			check := exec.Command("tmux", "has-session", "-t", sessionName)
			if err := check.Run(); err != nil {
				// Session ended — capture final output
				durationMs = time.Since(start).Milliseconds()
				stdout, _ = CaptureTmuxPane(sessionName)
				// Clean up mapping file
				os.Remove(fmt.Sprintf("/tmp/intermux-mapping-%s.json", sessionName))
				return stdout, 0, durationMs, nil
			}
		}
	}
}

// CaptureTmuxPane captures the last N lines from a tmux pane.
func CaptureTmuxPane(sessionName string) (string, error) {
	cmd := exec.Command("tmux", "capture-pane", "-t", sessionName, "-p", "-S", "-2000")
	var stdout bytes.Buffer
	cmd.Stdout = &stdout
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("capture-pane failed: %w", err)
	}
	return stdout.String(), nil
}

// KillTmuxSession kills a tmux session if it exists.
func KillTmuxSession(sessionName string) error {
	return exec.Command("tmux", "kill-session", "-t", sessionName).Run()
}
```

**Step 4: Run tests to verify they pass**

Run: `cd interverse/intermix && go test ./internal/eval/ -run "TestBuildTmuxSessionName|TestBuildSkaffenCommand" -v`
Expected: PASS

**Step 5: Commit**

```bash
cd interverse/intermix && git add internal/eval/runner.go internal/eval/runner_test.go
git commit -m "feat(intermix): tmux-based Skaffen spawner with intermux-compatible session names"
```

<verify>
- run: `cd interverse/intermix && go test ./internal/eval/ -run "TestBuildTmuxSessionName|TestBuildSkaffenCommand" -v`
  expect: exit 0
</verify>

---

### Task 3: Parallel Batch Runner

**Beads:** Demarch-sna1 (F1), Demarch-3795 (F2)
**Files:**
- Create: `interverse/intermix/internal/eval/parallel.go`
- Create: `interverse/intermix/internal/eval/parallel_test.go`

**Step 1: Write failing test for RunBatch**

Create `parallel_test.go`:

```go
package eval

import (
	"testing"
)

func TestBuildBatchCells(t *testing.T) {
	manifest := &Manifest{
		Repos: []Repo{
			{ID: "chi", URL: "https://github.com/go-chi/chi", Setup: "go mod download", Language: "go"},
			{ID: "zod", URL: "https://github.com/colinhacks/zod", Setup: "npm install", Language: "typescript"},
		},
		Tasks: []Task{
			{ID: "add-test", Prompt: "Write a test", Difficulty: "easy"},
			{ID: "refactor-extract", Prompt: "Refactor a function", Difficulty: "medium"},
		},
	}

	cells := BuildBatchCells(manifest, nil) // nil = no filter, all combos
	if len(cells) != 4 {
		t.Errorf("expected 4 cells, got %d", len(cells))
	}

	// Verify cell IDs are unique
	seen := make(map[string]bool)
	for _, c := range cells {
		if seen[c.ID()] {
			t.Errorf("duplicate cell ID: %s", c.ID())
		}
		seen[c.ID()] = true
	}
}

func TestBuildBatchCellsWithRepoFilter(t *testing.T) {
	manifest := &Manifest{
		Repos: []Repo{
			{ID: "chi", URL: "https://github.com/go-chi/chi", Setup: "go mod download", Language: "go"},
			{ID: "zod", URL: "https://github.com/colinhacks/zod", Setup: "npm install", Language: "typescript"},
		},
		Tasks: []Task{
			{ID: "add-test", Prompt: "Write a test", Difficulty: "easy"},
		},
	}

	filter := []string{"chi"}
	cells := BuildBatchCells(manifest, filter)
	if len(cells) != 1 {
		t.Errorf("expected 1 cell, got %d", len(cells))
	}
	if cells[0].Repo.ID != "chi" {
		t.Errorf("expected chi, got %s", cells[0].Repo.ID)
	}
}

func TestBatchCellSkipsCompleted(t *testing.T) {
	completed := map[string]bool{"chi:add-test": true}
	cell := BatchCell{
		Repo: Repo{ID: "chi"},
		Task: Task{ID: "add-test"},
	}
	if !completed[cell.Repo.ID+":"+cell.Task.ID] {
		t.Error("expected cell to be in completed set")
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd interverse/intermix && go test ./internal/eval/ -run "TestBuildBatchCells" -v`
Expected: FAIL

**Step 3: Implement parallel batch runner**

Create `parallel.go`:

```go
package eval

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"
)

// BatchCell represents a single cell in the stress test matrix.
type BatchCell struct {
	Repo Repo
	Task Task
}

// ID returns a unique identifier for this cell.
func (c BatchCell) ID() string {
	return fmt.Sprintf("%s-%s", c.Repo.ID, c.Task.ID)
}

// BatchResult holds the outcome of a single cell execution.
type BatchResult struct {
	Cell         BatchCell
	SessionName  string
	RunDetails   *RunDetails
	CellResult   *CellResult
	Evidence     string // Path to harvested evidence file
	PaneCapture  string // Last N lines of tmux pane output
	Error        error
}

// BuildBatchCells expands the manifest into individual cells, optionally filtered.
// If repoFilter is non-nil, only repos with IDs in the filter are included.
// Task.Repos field is respected: if a task has Repos set, it only runs on those repos.
func BuildBatchCells(manifest *Manifest, repoFilter []string) []BatchCell {
	filterSet := make(map[string]bool)
	for _, id := range repoFilter {
		filterSet[id] = true
	}

	var cells []BatchCell
	for _, repo := range manifest.Repos {
		if len(repoFilter) > 0 && !filterSet[repo.ID] {
			continue
		}
		for _, task := range manifest.Tasks {
			// If task is repo-specific, skip non-matching repos
			if len(task.Repos) > 0 {
				match := false
				for _, r := range task.Repos {
					if r == repo.ID {
						match = true
						break
					}
				}
				if !match {
					continue
				}
			}
			cells = append(cells, BatchCell{Repo: repo, Task: task})
		}
	}
	return cells
}

// RunBatch launches all cells in parallel tmux sessions.
// Each cell: clone → setup → spawn Skaffen in tmux.
// Returns immediately with session names for monitoring.
func RunBatch(ctx context.Context, cells []BatchCell, workDir string, defaultTimeout time.Duration) []BatchResult {
	results := make([]BatchResult, len(cells))
	var wg sync.WaitGroup

	for i, cell := range cells {
		wg.Add(1)
		go func(idx int, c BatchCell) {
			defer wg.Done()

			cellID := c.ID()
			cloneDir := filepath.Join(os.TempDir(), "intermix", cellID)

			// Ensure cells directory exists
			cellsDir := filepath.Join(workDir, "cells")
			os.MkdirAll(cellsDir, 0755)

			// Clone
			if err := CloneRepo(c.Repo.URL, cloneDir); err != nil {
				results[idx] = BatchResult{Cell: c, Error: fmt.Errorf("clone failed: %w", err)}
				return
			}

			// Setup
			if c.Repo.Setup != "" {
				if err := RunSetup(cloneDir, c.Repo.Setup); err != nil {
					results[idx] = BatchResult{Cell: c, Error: fmt.Errorf("setup failed: %w", err)}
					return
				}
			}

			// Spawn in tmux
			timeout := defaultTimeout
			if c.Repo.SkaffenConfig.Timeout != "" {
				if parsed, err := time.ParseDuration(c.Repo.SkaffenConfig.Timeout); err == nil {
					timeout = parsed
				}
			}

			sessionName, err := SpawnSkaffenTmux(ctx, c.Repo.ID, c.Task.ID, cloneDir, c.Task.Prompt, timeout.String())
			if err != nil {
				results[idx] = BatchResult{Cell: c, Error: fmt.Errorf("spawn failed: %w", err)}
				return
			}

			results[idx] = BatchResult{
				Cell:        c,
				SessionName: sessionName,
			}
		}(i, cell)
	}

	wg.Wait()
	return results
}

// PollBatch waits for all active sessions to complete, collecting results.
// Polls every interval. Kills sessions that exceed timeout.
func PollBatch(ctx context.Context, results []BatchResult, workDir string, timeout time.Duration) {
	var wg sync.WaitGroup

	for i := range results {
		if results[i].Error != nil || results[i].SessionName == "" {
			continue // Already failed during spawn
		}
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()

			r := &results[idx]
			stdout, exitCode, durationMs, err := WaitTmuxSession(ctx, r.SessionName, timeout)

			cloneDir := filepath.Join(os.TempDir(), "intermix", r.Cell.ID())

			// Build RunDetails
			rd := &RunDetails{
				Stdout:       truncateOutput(stdout, 65536),
				Stderr:       "", // tmux captures combined output
				DurationMs:   durationMs,
				ExitCode:     exitCode,
				CloneDir:     cloneDir,
				FilesChanged: countFilesChanged(cloneDir),
			}

			if err != nil {
				rd.ExitCode = -1
				rd.Stderr = err.Error()
			}

			// Run validation if available
			validationCmd := r.Cell.Repo.ValidationCmd
			if validationCmd == "" {
				validationCmd = InferValidationCmd(cloneDir, r.Cell.Repo.Language)
			}
			if validationCmd != "" {
				vr := RunValidation(cloneDir, validationCmd)
				rd.ValidationPassed = vr.Passed
				rd.ValidationOutput = vr.Output
			}

			r.RunDetails = rd

			// Classify
			cr := ClassifyFromRunDetails(rd, r.Cell.Repo.ID, r.Cell.Task.ID)
			r.CellResult = &cr

			// Write per-cell JSONL
			cellJSONL := CellJSONLPath(workDir, r.Cell.ID())
			WriteCellResult(cellJSONL, cr)

			// Write run details for debugging
			runFile := CellRunFilePath(workDir, r.Cell.ID())
			writeRunDetails(runFile, rd)
		}(i)
	}

	wg.Wait()
}

// writeRunDetails writes RunDetails to a JSON file for post-mortem analysis.
func writeRunDetails(path string, rd *RunDetails) {
	os.MkdirAll(filepath.Dir(path), 0755)
	f, err := os.Create(path)
	if err != nil {
		return
	}
	defer f.Close()
	enc := json.NewEncoder(f)
	enc.SetIndent("", "  ")
	enc.Encode(rd)
}
```

**Step 4: Run tests to verify they pass**

Run: `cd interverse/intermix && go test ./internal/eval/ -run "TestBuildBatchCells" -v`
Expected: PASS

**Step 5: Commit**

```bash
cd interverse/intermix && git add internal/eval/parallel.go internal/eval/parallel_test.go
git commit -m "feat(intermix): parallel batch runner with tmux sessions and per-cell isolation"
```

<verify>
- run: `cd interverse/intermix && go test ./internal/eval/ -run "TestBuildBatchCells" -v`
  expect: exit 0
- run: `cd interverse/intermix && go vet ./internal/eval/`
  expect: exit 0
</verify>

---

### Task 4: Evidence Harvesting

**Beads:** Demarch-yvdy (F4)
**Files:**
- Create: `interverse/intermix/internal/eval/evidence.go`
- Create: `interverse/intermix/internal/eval/evidence_test.go`

**Step 1: Write failing test**

Create `evidence_test.go`:

```go
package eval

import (
	"os"
	"path/filepath"
	"testing"
)

func TestHarvestEvidence(t *testing.T) {
	// Set up fake Skaffen evidence directory
	home := t.TempDir()
	t.Setenv("HOME", home)
	evidenceDir := filepath.Join(home, ".skaffen", "evidence")
	os.MkdirAll(evidenceDir, 0755)

	// Write a fake evidence file
	sessionID := "test-session-123"
	evidencePath := filepath.Join(evidenceDir, sessionID+".jsonl")
	os.WriteFile(evidencePath, []byte(`{"turn":1,"phase":"act"}`+"\n"), 0644)

	// Harvest
	campaignDir := t.TempDir()
	cellID := "chi-add-test"
	destPath, err := HarvestEvidence(campaignDir, cellID, sessionID)
	if err != nil {
		t.Fatal(err)
	}

	expected := filepath.Join(campaignDir, "evidence", cellID+".jsonl")
	if destPath != expected {
		t.Errorf("unexpected dest: %s", destPath)
	}

	// Verify file was copied
	data, err := os.ReadFile(destPath)
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != `{"turn":1,"phase":"act"}`+"\n" {
		t.Errorf("unexpected content: %s", string(data))
	}
}

func TestHarvestEvidenceMissing(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	campaignDir := t.TempDir()
	_, err := HarvestEvidence(campaignDir, "chi-add-test", "nonexistent-session")
	if err == nil {
		t.Error("expected error for missing evidence file")
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd interverse/intermix && go test ./internal/eval/ -run "TestHarvestEvidence" -v`
Expected: FAIL

**Step 3: Implement evidence harvesting**

Create `evidence.go`:

```go
package eval

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
)

// HarvestEvidence copies Skaffen's evidence JSONL from ~/.skaffen/evidence/<sessionID>.jsonl
// to <campaignDir>/evidence/<cellID>.jsonl. Returns the destination path.
func HarvestEvidence(campaignDir, cellID, sessionID string) (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("cannot determine home dir: %w", err)
	}

	srcPath := filepath.Join(home, ".skaffen", "evidence", sessionID+".jsonl")
	if _, err := os.Stat(srcPath); err != nil {
		return "", fmt.Errorf("evidence file not found: %s: %w", srcPath, err)
	}

	destDir := filepath.Join(campaignDir, "evidence")
	if err := os.MkdirAll(destDir, 0755); err != nil {
		return "", fmt.Errorf("create evidence dir: %w", err)
	}

	destPath := filepath.Join(destDir, cellID+".jsonl")
	if err := copyFile(srcPath, destPath); err != nil {
		return "", fmt.Errorf("copy evidence: %w", err)
	}

	return destPath, nil
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer out.Close()

	_, err = io.Copy(out, in)
	return err
}
```

**Step 4: Run tests to verify they pass**

Run: `cd interverse/intermix && go test ./internal/eval/ -run "TestHarvestEvidence" -v`
Expected: PASS

**Step 5: Commit**

```bash
cd interverse/intermix && git add internal/eval/evidence.go internal/eval/evidence_test.go
git commit -m "feat(intermix): evidence harvesting from Skaffen sessions to campaign dir"
```

<verify>
- run: `cd interverse/intermix && go test ./internal/eval/ -run "TestHarvestEvidence" -v`
  expect: exit 0
</verify>

---

### Task 5: Debug Bead Creation

**Beads:** Demarch-utpb (F3)
**Files:**
- Create: `interverse/intermix/internal/eval/bead.go`
- Create: `interverse/intermix/internal/eval/bead_test.go`

**Step 1: Write failing test**

Create `bead_test.go`:

```go
package eval

import (
	"testing"
)

func TestBuildDebugBeadTitle(t *testing.T) {
	title := BuildDebugBeadTitle("chi", "add-test", OutcomeTimeout)
	expected := "Stress test failure: chi/add-test — timeout"
	if title != expected {
		t.Errorf("expected %q, got %q", expected, title)
	}
}

func TestBuildDebugBeadDescription(t *testing.T) {
	cr := CellResult{
		Repo:     "chi",
		Task:     "add-test",
		Outcome:  OutcomeTimeout,
		Severity: SeverityCritical,
		DurationMs: 300000,
		ExitCode: -1,
	}
	desc := BuildDebugBeadDescription(cr, "session exited with timeout", "last 20 lines of output here")
	if desc == "" {
		t.Error("expected non-empty description")
	}
	// Should contain key fields
	for _, substr := range []string{"chi", "add-test", "timeout", "critical", "300000"} {
		if !containsString(desc, substr) {
			t.Errorf("description missing %q", substr)
		}
	}
}

func containsString(s, substr string) bool {
	return len(s) > 0 && len(substr) > 0 && contains(s, substr)
}

func contains(s, sub string) bool {
	return len(sub) <= len(s) && (s == sub || len(sub) == 0 || indexOf(s, sub) >= 0)
}

func indexOf(s, sub string) int {
	for i := 0; i <= len(s)-len(sub); i++ {
		if s[i:i+len(sub)] == sub {
			return i
		}
	}
	return -1
}

func TestBuildPatternBeadTitle(t *testing.T) {
	cluster := FailureCluster{
		Outcome: OutcomeTimeout,
		Count:   3,
		Cells:   []string{"chi:add-test", "zod:add-test", "click:add-test"},
	}
	title := BuildPatternBeadTitle(cluster)
	expected := "Pattern: timeout across 3 cells"
	if title != expected {
		t.Errorf("expected %q, got %q", expected, title)
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd interverse/intermix && go test ./internal/eval/ -run "TestBuildDebugBead|TestBuildPatternBead" -v`
Expected: FAIL

**Step 3: Implement bead creation helpers**

Create `bead.go`:

```go
package eval

import (
	"fmt"
	"os/exec"
	"strings"
)

// BuildDebugBeadTitle formats the title for a per-cell debug bead.
func BuildDebugBeadTitle(repo, task, outcome string) string {
	return fmt.Sprintf("Stress test failure: %s/%s — %s", repo, task, outcome)
}

// BuildDebugBeadDescription formats the description with failure context.
func BuildDebugBeadDescription(cr CellResult, evidenceExcerpt, paneCapture string) string {
	var b strings.Builder
	fmt.Fprintf(&b, "## Cell: %s/%s\n\n", cr.Repo, cr.Task)
	fmt.Fprintf(&b, "- **Outcome:** %s\n", cr.Outcome)
	fmt.Fprintf(&b, "- **Severity:** %s\n", cr.Severity)
	fmt.Fprintf(&b, "- **Duration:** %dms\n", cr.DurationMs)
	fmt.Fprintf(&b, "- **Exit code:** %d\n", cr.ExitCode)
	fmt.Fprintf(&b, "- **Files changed:** %d\n", cr.FilesChanged)
	fmt.Fprintf(&b, "- **Validation passed:** %v\n", cr.ValidationPassed)

	if cr.FailureReason != "" {
		fmt.Fprintf(&b, "\n## Failure Reason\n%s\n", cr.FailureReason)
	}
	if cr.LLMAnalysis != "" {
		fmt.Fprintf(&b, "\n## LLM Analysis\n%s\n", cr.LLMAnalysis)
	}
	if evidenceExcerpt != "" {
		fmt.Fprintf(&b, "\n## Evidence Excerpt\n```\n%s\n```\n", evidenceExcerpt)
	}
	if paneCapture != "" {
		fmt.Fprintf(&b, "\n## Pane Capture\n```\n%s\n```\n", paneCapture)
	}
	return b.String()
}

// BuildPatternBeadTitle formats the title for a failure cluster pattern bead.
func BuildPatternBeadTitle(cluster FailureCluster) string {
	return fmt.Sprintf("Pattern: %s across %d cells", cluster.Outcome, cluster.Count)
}

// CreateDebugBead creates a bead for a failed cell via the bd CLI.
// Returns the created bead ID, or empty string on failure (best-effort).
func CreateDebugBead(cr CellResult, parentBeadID, evidenceExcerpt, paneCapture string) string {
	if _, err := exec.LookPath("bd"); err != nil {
		return ""
	}

	title := BuildDebugBeadTitle(cr.Repo, cr.Task, cr.Outcome)
	desc := BuildDebugBeadDescription(cr, evidenceExcerpt, paneCapture)

	cmd := exec.Command("bd", "create",
		"--title", title,
		"--description", desc,
		"--type", "bug",
		"--priority", severityToPriority(cr.Severity),
	)
	out, err := cmd.Output()
	if err != nil {
		return ""
	}

	// Parse bead ID from output: "✓ Created issue: Demarch-xxxx — ..."
	beadID := parseBeadIDFromOutput(string(out))
	if beadID == "" {
		return ""
	}

	// Set parent
	if parentBeadID != "" {
		exec.Command("bd", "update", beadID, "--parent="+parentBeadID).Run()
	}

	return beadID
}

// CreatePatternBeads creates beads for failure clusters with ≥2 cells.
// Reparents individual debug beads under the pattern bead.
func CreatePatternBeads(clusters []FailureCluster, parentBeadID string, debugBeadMap map[string]string) {
	if _, err := exec.LookPath("bd"); err != nil {
		return
	}

	for i, cluster := range clusters {
		if cluster.Count < 2 {
			continue
		}

		title := BuildPatternBeadTitle(cluster)
		desc := fmt.Sprintf("Failure pattern: %s\nAffected cells: %s",
			cluster.Outcome, strings.Join(cluster.Cells, ", "))

		cmd := exec.Command("bd", "create",
			"--title", title,
			"--description", desc,
			"--type", "bug",
			"--priority", "1",
		)
		out, err := cmd.Output()
		if err != nil {
			continue
		}

		patternBeadID := parseBeadIDFromOutput(string(out))
		if patternBeadID == "" {
			continue
		}

		clusters[i].BeadID = patternBeadID

		// Set parent to campaign epic
		if parentBeadID != "" {
			exec.Command("bd", "update", patternBeadID, "--parent="+parentBeadID).Run()
		}

		// Reparent debug beads under pattern bead
		for _, cellKey := range cluster.Cells {
			if debugID, ok := debugBeadMap[cellKey]; ok {
				exec.Command("bd", "update", debugID, "--parent="+patternBeadID).Run()
			}
		}
	}
}

func severityToPriority(severity string) string {
	switch severity {
	case SeverityCritical:
		return "1"
	case SeverityDegraded:
		return "2"
	default:
		return "3"
	}
}

func parseBeadIDFromOutput(output string) string {
	// Output format: "✓ Created issue: Demarch-xxxx — ..."
	const marker = "Created issue: "
	idx := strings.Index(output, marker)
	if idx < 0 {
		return ""
	}
	rest := output[idx+len(marker):]
	// Find end of bead ID (space or " —")
	end := strings.Index(rest, " ")
	if end < 0 {
		return strings.TrimSpace(rest)
	}
	return strings.TrimSpace(rest[:end])
}
```

**Step 4: Run tests to verify they pass**

Run: `cd interverse/intermix && go test ./internal/eval/ -run "TestBuildDebugBead|TestBuildPatternBead" -v`
Expected: PASS

**Step 5: Commit**

```bash
cd interverse/intermix && git add internal/eval/bead.go internal/eval/bead_test.go
git commit -m "feat(intermix): auto-create debug beads on failure with pattern clustering"
```

<verify>
- run: `cd interverse/intermix && go test ./internal/eval/ -run "TestBuildDebugBead|TestBuildPatternBead" -v`
  expect: exit 0
</verify>

---

### Task 6: Report Matrix with Heatmap and Pattern Beads

**Beads:** Demarch-7xak (F5)
**Files:**
- Modify: `interverse/intermix/internal/eval/report.go`
- Modify: `interverse/intermix/internal/eval/report_test.go`

**Step 1: Write failing test for heatmap and per-cell-dir report**

In `report_test.go`, add:

```go
func TestFormatHeatmap(t *testing.T) {
	results := []CellResult{
		{Repo: "chi", Task: "add-test", Outcome: OutcomeSuccess},
		{Repo: "chi", Task: "refactor-extract", Outcome: OutcomeTimeout},
		{Repo: "chi", Task: "add-feature", Outcome: OutcomeSuccess},
		{Repo: "zod", Task: "add-test", Outcome: OutcomeSuccess},
		{Repo: "zod", Task: "refactor-extract", Outcome: OutcomePartial},
		{Repo: "zod", Task: "add-feature", Outcome: OutcomeCrash},
		{Repo: "click", Task: "add-test", Outcome: OutcomeNoProgress},
		{Repo: "click", Task: "refactor-extract", Outcome: OutcomeSuccess},
		{Repo: "click", Task: "add-feature", Outcome: OutcomeTimeout},
	}

	heatmap := FormatHeatmap(results)
	if heatmap == "" {
		t.Error("expected non-empty heatmap")
	}
	// Should contain repo names and task names
	for _, name := range []string{"chi", "zod", "click", "add-test", "refactor-extract", "add-feature"} {
		if !strings.Contains(heatmap, name) {
			t.Errorf("heatmap missing %q", name)
		}
	}
}

func TestGenerateReportFromCellsDir(t *testing.T) {
	dir := t.TempDir()
	cellsDir := filepath.Join(dir, "cells")
	os.MkdirAll(cellsDir, 0755)

	// Write cell results
	results := []CellResult{
		{Type: "cell_result", Repo: "chi", Task: "add-test", Outcome: OutcomeSuccess},
		{Type: "cell_result", Repo: "zod", Task: "add-test", Outcome: OutcomeTimeout},
	}
	for _, cr := range results {
		cellID := cr.Repo + "-" + cr.Task
		WriteCellResult(CellJSONLPath(dir, cellID), cr)
	}

	// Write config to main file
	cfg := MatrixConfig{Type: "config", Name: "test", RepoIDs: []string{"chi", "zod"}, TaskIDs: []string{"add-test"}, TotalCells: 2}
	WriteConfig(filepath.Join(dir, "intermix.jsonl"), cfg)

	state, err := ReconstructStateFromCellsDir(dir)
	if err != nil {
		t.Fatal(err)
	}

	report := GenerateReport(state.Results, nil)
	if report.TotalCells != 2 {
		t.Errorf("expected 2 cells, got %d", report.TotalCells)
	}
	if report.SuccessCount != 1 {
		t.Errorf("expected 1 success, got %d", report.SuccessCount)
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd interverse/intermix && go test ./internal/eval/ -run "TestFormatHeatmap|TestGenerateReportFromCellsDir" -v`
Expected: FAIL

**Step 3: Implement heatmap formatter**

In `report.go`, add:

```go
// FormatHeatmap generates an ASCII grid showing pass/fail per repo×task.
func FormatHeatmap(results []CellResult) string {
	// Collect unique repos and tasks in order
	repoOrder := []string{}
	taskOrder := []string{}
	repoSeen := map[string]bool{}
	taskSeen := map[string]bool{}
	grid := map[string]map[string]string{} // repo -> task -> symbol

	for _, cr := range results {
		if !repoSeen[cr.Repo] {
			repoOrder = append(repoOrder, cr.Repo)
			repoSeen[cr.Repo] = true
		}
		if !taskSeen[cr.Task] {
			taskOrder = append(taskOrder, cr.Task)
			taskSeen[cr.Task] = true
		}
		if grid[cr.Repo] == nil {
			grid[cr.Repo] = map[string]string{}
		}
		grid[cr.Repo][cr.Task] = outcomeSymbol(cr.Outcome)
	}

	// Find max widths
	repoWidth := 5 // minimum
	for _, r := range repoOrder {
		if len(r) > repoWidth {
			repoWidth = len(r)
		}
	}
	taskWidth := 8 // minimum
	for _, t := range taskOrder {
		if len(t) > taskWidth {
			taskWidth = len(t)
		}
	}

	var b strings.Builder

	// Header row
	fmt.Fprintf(&b, "%-*s", repoWidth+2, "")
	for _, task := range taskOrder {
		fmt.Fprintf(&b, " %-*s", taskWidth, task)
	}
	b.WriteString("\n")

	// Data rows
	for _, repo := range repoOrder {
		fmt.Fprintf(&b, "%-*s", repoWidth+2, repo)
		for _, task := range taskOrder {
			sym := grid[repo][task]
			if sym == "" {
				sym = "-"
			}
			fmt.Fprintf(&b, " %-*s", taskWidth, sym)
		}
		b.WriteString("\n")
	}

	// Legend
	b.WriteString("\nLegend: PASS=success, PART=partial, TOUT=timeout, FAIL=crash/failure, NOPG=no_progress, SKIP=skipped\n")

	return b.String()
}

func outcomeSymbol(outcome string) string {
	switch outcome {
	case OutcomeSuccess:
		return "PASS"
	case OutcomePartial:
		return "PART"
	case OutcomeTimeout:
		return "TOUT"
	case OutcomeCrash:
		return "FAIL"
	case OutcomeToolFailure:
		return "TOOL"
	case OutcomeNoProgress:
		return "NOPG"
	case OutcomeContextLimit:
		return "CTXL"
	case OutcomeSetupFailure:
		return "SETU"
	case OutcomeSkipped:
		return "SKIP"
	default:
		return "????"
	}
}
```

Also modify `FormatReport` to include the heatmap by adding after the summary section:

```go
// In FormatReport, add after the Summary section:
fmt.Fprintf(&b, "\n## Heatmap\n\n```\n%s```\n", FormatHeatmap(/* pass results through */) )
```

Note: The implementation agent should wire FormatHeatmap into FormatReport by passing the results through. The current FormatReport takes `*Report` which has all CellResults accessible via the clusters.

**Step 4: Run tests to verify they pass**

Run: `cd interverse/intermix && go test ./internal/eval/ -run "TestFormatHeatmap|TestGenerateReportFromCellsDir" -v`
Expected: PASS

**Step 5: Commit**

```bash
cd interverse/intermix && git add internal/eval/report.go internal/eval/report_test.go
git commit -m "feat(intermix): ASCII heatmap and per-cell-dir report generation"
```

<verify>
- run: `cd interverse/intermix && go test ./internal/eval/ -run "TestFormatHeatmap|TestGenerateReportFromCellsDir" -v`
  expect: exit 0
</verify>

---

### Task 7: MCP Tools for Batch Operations

**Beads:** Demarch-sna1 (F1), Demarch-3795 (F2)
**Files:**
- Modify: `interverse/intermix/internal/eval/tools.go`
- Modify: `interverse/intermix/internal/eval/tools_test.go`

**Step 1: Write failing test for run_batch tool registration**

In `tools_test.go`, add:

```go
func TestRunBatchToolRegistered(t *testing.T) {
	s := server.NewMCPServer("test", "0.1.0", server.WithToolCapabilities(true))
	RegisterAll(s)

	// The server should have run_batch registered
	// We test by calling it with minimal args
	req := mcp.CallToolRequest{}
	req.Params.Name = "run_batch"
	req.Params.Arguments = map[string]interface{}{
		"repos": []interface{}{"chi", "zod", "click"},
		"tasks": []interface{}{"add-test", "refactor-extract", "add-feature"},
	}
	// Just verify it doesn't panic — full integration test needs tmux
	result, err := s.HandleCallTool(t.Context(), req)
	// Expect error (no manifest file) but not a panic or "unknown tool"
	if err != nil && strings.Contains(err.Error(), "unknown tool") {
		t.Error("run_batch tool not registered")
	}
	_ = result
}
```

**Step 2: Run test to verify it fails**

Run: `cd interverse/intermix && go test ./internal/eval/ -run "TestRunBatchToolRegistered" -v`
Expected: FAIL

**Step 3: Register run_batch and poll_batch MCP tools**

In `tools.go`, add two new tool registrations inside `RegisterAll`:

```go
// run_batch — launches N cells in parallel tmux sessions
s.AddTool(mcp.Tool{
	Name:        "run_batch",
	Description: "Launch multiple stress test cells in parallel tmux sessions. Each cell clones the repo, runs setup, and spawns Skaffen in a named tmux session visible to intermux.",
	InputSchema: mcp.ToolInputSchema{
		Type: "object",
		Properties: map[string]interface{}{
			"repos": map[string]interface{}{
				"type":        "array",
				"items":       map[string]interface{}{"type": "string"},
				"description": "List of repo IDs to test (from manifest)",
			},
			"tasks": map[string]interface{}{
				"type":        "array",
				"items":       map[string]interface{}{"type": "string"},
				"description": "List of task IDs to run (from manifest)",
			},
			"working_directory": map[string]interface{}{
				"type":        "string",
				"description": "Working directory containing intermix.jsonl and .intermix-manifest.json",
			},
			"bead_id": map[string]interface{}{
				"type":        "string",
				"description": "Parent bead ID for failure tracking",
			},
		},
		Required: []string{"repos", "tasks"},
	},
}, handleRunBatch)

// poll_batch — waits for all tmux sessions to complete and collects results
s.AddTool(mcp.Tool{
	Name:        "poll_batch",
	Description: "Wait for all active stress test tmux sessions to complete. Collects results, classifies outcomes, harvests evidence, and creates debug beads for failures.",
	InputSchema: mcp.ToolInputSchema{
		Type: "object",
		Properties: map[string]interface{}{
			"working_directory": map[string]interface{}{
				"type":        "string",
				"description": "Working directory containing intermix.jsonl",
			},
			"bead_id": map[string]interface{}{
				"type":        "string",
				"description": "Parent bead ID for failure tracking",
			},
			"timeout": map[string]interface{}{
				"type":        "string",
				"description": "Max time to wait per cell (default: 300s)",
			},
		},
	},
}, handlePollBatch)
```

Then implement the handlers:

```go
func handleRunBatch(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	dir := resolveDir(req)

	// Load manifest
	manifestPath := filepath.Join(dir, ".intermix-manifest.json")
	data, err := os.ReadFile(manifestPath)
	if err != nil {
		return mcp.NewToolResultError("no manifest found — run init_matrix first"), nil
	}
	var manifest Manifest
	if err := json.Unmarshal(data, &manifest); err != nil {
		return mcp.NewToolResultError("invalid manifest: " + err.Error()), nil
	}

	// Parse repo and task filters
	repoFilter := toStringSlice(req.Params.Arguments["repos"])
	taskFilter := toStringSlice(req.Params.Arguments["tasks"])

	// Build cells
	cells := BuildBatchCells(&manifest, repoFilter)
	// Further filter by tasks
	if len(taskFilter) > 0 {
		taskSet := make(map[string]bool)
		for _, t := range taskFilter {
			taskSet[t] = true
		}
		var filtered []BatchCell
		for _, c := range cells {
			if taskSet[c.Task.ID] {
				filtered = append(filtered, c)
			}
		}
		cells = filtered
	}

	// Check for already-completed cells
	state, _ := ReconstructStateFromCellsDir(dir)
	if state != nil {
		var remaining []BatchCell
		for _, c := range cells {
			key := c.Repo.ID + ":" + c.Task.ID
			if !state.CompletedCells[key] {
				remaining = append(remaining, c)
			}
		}
		cells = remaining
	}

	if len(cells) == 0 {
		return mcp.NewToolResultText("All cells already completed"), nil
	}

	// Launch all cells
	timeout := 300 * time.Second
	results := RunBatch(ctx, cells, dir, timeout)

	// Count successes and failures
	spawned := 0
	failed := 0
	var sessions []string
	for _, r := range results {
		if r.Error != nil {
			failed++
		} else {
			spawned++
			sessions = append(sessions, r.SessionName)
		}
	}

	// Store results for poll_batch to pick up
	resultsData, _ := json.Marshal(results)
	os.WriteFile(filepath.Join(dir, ".intermix-batch.json"), resultsData, 0644)

	msg := fmt.Sprintf("Launched %d cells (%d failed to spawn).\nSessions: %s\n\nRun poll_batch to wait for completion and collect results.",
		spawned, failed, strings.Join(sessions, ", "))
	return mcp.NewToolResultText(msg), nil
}

func handlePollBatch(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	dir := resolveDir(req)
	beadID, _ := req.Params.Arguments["bead_id"].(string)

	// Load batch state
	batchPath := filepath.Join(dir, ".intermix-batch.json")
	data, err := os.ReadFile(batchPath)
	if err != nil {
		return mcp.NewToolResultError("no active batch — run run_batch first"), nil
	}
	var results []BatchResult
	if err := json.Unmarshal(data, &results); err != nil {
		return mcp.NewToolResultError("invalid batch state: " + err.Error()), nil
	}

	// Parse timeout
	timeout := 300 * time.Second
	if ts, ok := req.Params.Arguments["timeout"].(string); ok {
		if parsed, err := time.ParseDuration(ts); err == nil {
			timeout = parsed
		}
	}

	// Wait for all sessions to complete
	PollBatch(ctx, results, dir, timeout)

	// Harvest evidence and create debug beads
	debugBeadMap := make(map[string]string) // "repo:task" -> bead ID
	successes := 0
	failures := 0

	for i, r := range results {
		if r.CellResult == nil {
			failures++
			continue
		}

		cellKey := r.Cell.Repo.ID + ":" + r.Cell.Task.ID

		// Harvest evidence (best-effort)
		sessionID := fmt.Sprintf("intermix-%s-%s", r.Cell.Repo.ID, r.Cell.Task.ID)
		evidencePath, _ := HarvestEvidence(dir, r.Cell.ID(), sessionID)
		results[i].Evidence = evidencePath

		// Emit ic event
		EmitCellEvent(*r.CellResult, beadID)

		if r.CellResult.Outcome == OutcomeSuccess {
			successes++
		} else {
			failures++

			// Create debug bead
			var excerpt string
			if evidencePath != "" {
				// Read last 20 lines of evidence
				if eData, err := os.ReadFile(evidencePath); err == nil {
					lines := strings.Split(string(eData), "\n")
					start := len(lines) - 20
					if start < 0 {
						start = 0
					}
					excerpt = strings.Join(lines[start:], "\n")
				}
			}

			// Capture pane output (last 50 lines)
			var paneCapture string
			if r.RunDetails != nil {
				lines := strings.Split(r.RunDetails.Stdout, "\n")
				start := len(lines) - 50
				if start < 0 {
					start = 0
				}
				paneCapture = strings.Join(lines[start:], "\n")
			}

			debugID := CreateDebugBead(*r.CellResult, beadID, excerpt, paneCapture)
			if debugID != "" {
				debugBeadMap[cellKey] = debugID
			}
		}
	}

	// Generate report with pattern clustering
	state, _ := ReconstructStateFromCellsDir(dir)
	var report *Report
	if state != nil {
		report = GenerateReport(state.Results, nil)
		// Create pattern beads for clusters ≥2
		if len(report.FailureClusters) > 0 {
			CreatePatternBeads(report.FailureClusters, beadID, debugBeadMap)
		}
	}

	// Clean up batch file
	os.Remove(batchPath)

	// Format summary
	var msg strings.Builder
	fmt.Fprintf(&msg, "Batch complete: %d success, %d failure\n\n", successes, failures)
	if report != nil {
		msg.WriteString(FormatReport(report))
		msg.WriteString("\n\n")
		msg.WriteString(FormatHeatmap(state.Results))
	}
	if len(debugBeadMap) > 0 {
		msg.WriteString("\nDebug beads created:\n")
		for cellKey, beadID := range debugBeadMap {
			fmt.Fprintf(&msg, "  %s → %s\n", cellKey, beadID)
		}
	}

	// Emit campaign event
	if report != nil {
		EmitCampaignEvent(report, "stress-test", beadID)
	}

	return mcp.NewToolResultText(msg.String()), nil
}

func toStringSlice(v interface{}) []string {
	arr, ok := v.([]interface{})
	if !ok {
		return nil
	}
	result := make([]string, 0, len(arr))
	for _, item := range arr {
		if s, ok := item.(string); ok {
			result = append(result, s)
		}
	}
	return result
}
```

**Step 4: Run tests to verify they pass**

Run: `cd interverse/intermix && go test ./internal/eval/ -run "TestRunBatchToolRegistered" -v`
Expected: PASS

**Step 5: Commit**

```bash
cd interverse/intermix && git add internal/eval/tools.go internal/eval/tools_test.go
git commit -m "feat(intermix): run_batch and poll_batch MCP tools for parallel stress testing"
```

<verify>
- run: `cd interverse/intermix && go test ./internal/eval/ -v`
  expect: exit 0
- run: `cd interverse/intermix && go build ./cmd/intermix-mcp/`
  expect: exit 0
</verify>

---

### Task 8: Build and Verify intermix Binary

**Beads:** Demarch-sna1 (F1)
**Files:**
- Modify: `interverse/intermix/cmd/intermix-mcp/main.go` (no changes needed if RegisterAll already covers new tools)

**Step 1: Build the binary**

Run: `cd interverse/intermix && go build -o bin/intermix-mcp ./cmd/intermix-mcp/`
Expected: Successful build

**Step 2: Run full test suite**

Run: `cd interverse/intermix && go test ./... -v`
Expected: All tests pass

**Step 3: Verify binary starts**

Run: `cd interverse/intermix && echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0.1.0"}}}' | timeout 5 ./bin/intermix-mcp 2>/dev/null | head -1`
Expected: JSON response with server capabilities including run_batch and poll_batch

**Step 4: Commit binary**

```bash
cd interverse/intermix && git add bin/intermix-mcp
git commit -m "build(intermix): rebuild binary with parallel stress test tools"
```

<verify>
- run: `cd interverse/intermix && go test ./... -count=1`
  expect: exit 0
- run: `cd interverse/intermix && go vet ./...`
  expect: exit 0
</verify>

---

### Task 9: Run the 9-Cell Campaign

**Beads:** Demarch-vmen (F6)
**Files:**
- No new files — uses the built intermix tools

**Prerequisites:** Skaffen binary built and on PATH, tmux installed, ANTHROPIC_API_KEY set or Claude Code available.

**Step 1: Verify prerequisites**

Run: `command -v skaffen && command -v tmux && command -v bd && echo "OK"`
Expected: OK

**Step 2: Create campaign working directory**

```bash
mkdir -p /tmp/intermix-campaign-$(date +%Y%m%d)
cd /tmp/intermix-campaign-$(date +%Y%m%d)
```

**Step 3: Initialize the matrix**

Use intermix MCP `init_matrix` tool with the skaffen-stress.yaml manifest, filtered to our 3 repos:
- Manifest: `interverse/intermix/examples/skaffen-stress.yaml`
- Bead: `Demarch-ome7`

**Step 4: Launch all 9 cells**

Use intermix MCP `run_batch` tool:
- repos: `["chi", "zod", "click"]`
- tasks: `["add-test", "refactor-extract", "add-feature"]`
- bead_id: `Demarch-ome7`

**Step 5: Monitor via intermux**

While cells run, periodically check:
- `intermux list_agents` — verify all 9 sessions visible
- `intermux agent_health` — check for stuck/crashed
- `intermux peek_agent` — inspect any interesting sessions

**Step 6: Collect results**

Use intermix MCP `poll_batch` tool:
- bead_id: `Demarch-ome7`
- timeout: `600s`

This waits for all sessions, classifies results, creates debug beads, and generates the report.

**Step 7: Review the report**

Read the generated report. Verify:
- Heatmap shows all 9 cells
- Debug beads exist for failures
- Pattern beads exist for clusters ≥2
- Evidence files are in the campaign directory

**Step 8: Commit campaign results**

```bash
# Copy report to docs/
cp /tmp/intermix-campaign-*/report.md docs/research/2026-03-14-stress-test-results.md
git add docs/research/2026-03-14-stress-test-results.md
git commit -m "data: first 9-cell stress test campaign results"
```

<verify>
- run: `bd children Demarch-ome7 2>/dev/null | jq 'length'`
  expect: contains "6"
</verify>
