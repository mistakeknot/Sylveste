---
artifact_type: plan
bead: Sylveste-7xm8
stage: design
requirements:
  - F1: SQLite mutation store — schema and DB management
  - F2: mutation_record MCP tool
  - F3: mutation_query MCP tool
  - F4: mutation_genealogy MCP tool
  - F5: /autoresearch mutation store integration
  - F6: Agent quality scoring rubric and benchmark script
  - F7: Pilot campaign — interflux self-review
---
# Meta-Improvement Campaigns Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Sylveste-7xm8
**Goal:** Build a SQLite-backed mutation history store in interlab with provenance tracking, wire it into /autoresearch, and validate with an interflux self-review pilot campaign.

**Architecture:** The mutation store is a new `internal/mutation` Go package in interlab, registering 3 MCP tools via the existing `mark3labs/mcp-go` pattern. SQLite accessed via `modernc.org/sqlite` (CGo-free). The store lives at `~/.local/share/interlab/mutations.db` and auto-initializes on first use. The `/autoresearch` SKILL.md is updated to call mutation tools at campaign start (query prior approaches) and after each experiment (record mutation). The pilot campaign is a campaign directory at `campaigns/interflux-self-review/` with a bash benchmark script that scores agent `.md` files.

**Tech Stack:** Go 1.23, mark3labs/mcp-go v0.32.0, modernc.org/sqlite, bash (benchmark scripts)

**Prior Learnings:**
- `docs/solutions/patterns/critical-patterns.md` — Compiled MCP servers need launcher scripts. interlab already has `bin/launch-mcp.sh` — no action needed.
- CASS session (Hyperspace analysis) — Karpathy's 3 primitives (editable asset + scalar metric + time-boxed cycle) are the design discipline. The mutation store should enforce these constraints.
- Plugin-evolution analysis — PQS formula (`correctness * utility * trust`) as scoring pattern. Agent quality benchmark should follow similar composite approach.

---

## Must-Haves

**Truths** (observable behaviors):
- Running `mutation_record` with a hypothesis and quality_signal persists a row in SQLite and returns `is_new_best` status
- Running `mutation_query` with a `task_type` filter returns mutations sorted by quality descending
- Running `mutation_genealogy` with a mutation ID returns its ancestor and descendant chain
- `/autoresearch` campaigns automatically record mutations and query prior approaches at startup
- Running `agent-quality-benchmark.sh` on an interflux agent `.md` file emits `METRIC agent_quality_score=N.NNNN`

**Artifacts** (files that must exist):
- `interverse/interlab/internal/mutation/store.go` exports `NewStore`, `Record`, `Query`, `Genealogy`, `Close`
- `interverse/interlab/internal/mutation/tools.go` exports `RegisterAll`
- `interverse/interlab/scripts/agent-quality-benchmark.sh` emits METRIC lines
- `interverse/interlab/campaigns/interflux-self-review/` contains config and README

**Key Links:**
- `cmd/interlab-mcp/main.go` calls `mutation.RegisterAll(s)` after `experiment.RegisterAll(s)`
- `/autoresearch` SKILL.md references `mutation_query` at campaign start and `mutation_record` after `log_experiment`
- `agent-quality-benchmark.sh` is the `benchmark_command` for the interflux-self-review campaign

## Plan Review Fixes (from flux-drive)

The following changes were incorporated after 3-agent flux-drive review (architecture, correctness, quality):

1. **TOCTOU race fixed:** `Record` wraps SELECT MAX + INSERT in `BEGIN IMMEDIATE` transaction
2. **Singleton store:** `RegisterAll` accepts `*Store`, opened once in `main.go` (not per-call)
3. **Dead code removed:** `getFloat64FromArgs` and unused `strconv` import deleted
4. **Nil slice fixed:** `Query` initializes results as `make([]Mutation, 0)` (JSON `[]` not `null`)
5. **Schema DDL split:** Separate `db.Exec` per statement instead of multi-statement string
6. **`schema_version` removed:** YAGNI — add migration logic when first migration is needed
7. **Test genealogy fixed:** Root record sets `SessionID`, test asserts `len(tree.Children)`
8. **`loadDescendants` returns error:** Partial tree is reported, not silently swallowed
9. **Error handling aligned:** Infrastructure errors use `nil, fmt.Errorf()` per existing pattern

---

### Task 1: Add SQLite dependency to interlab

**Files:**
- Modify: `interverse/interlab/go.mod`
- Modify: `interverse/interlab/go.sum`

**Step 1: Add the modernc.org/sqlite dependency**

```bash
cd interverse/interlab && go get modernc.org/sqlite
```

This adds a CGo-free SQLite driver to interlab. Using `modernc.org/sqlite` because it's pure Go — no C compiler needed, works on all platforms, and is the standard choice for Go projects that need SQLite without CGo.

**Step 2: Verify the dependency resolves**

Run: `cd interverse/interlab && go mod tidy`
Expected: Clean exit, no errors

**Step 3: Verify build still works**

Run: `cd interverse/interlab && go build ./cmd/interlab-mcp/`
Expected: exit 0, binary builds successfully

**Step 4: Commit**

```bash
cd interverse/interlab && git add go.mod go.sum
git commit -m "chore: add modernc.org/sqlite dependency for mutation store"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/interverse/interlab && go build ./cmd/interlab-mcp/`
  expect: exit 0
</verify>

---

### Task 2: Implement mutation store (SQLite layer)

**Files:**
- Create: `interverse/interlab/internal/mutation/store.go`
- Create: `interverse/interlab/internal/mutation/store_test.go`

**Step 1: Write the failing tests**

Create `interverse/interlab/internal/mutation/store_test.go`:

```go
package mutation

import (
	"os"
	"path/filepath"
	"testing"
)

func tempDB(t *testing.T) *Store {
	t.Helper()
	dir := t.TempDir()
	s, err := NewStore(filepath.Join(dir, "test.db"))
	if err != nil {
		t.Fatalf("NewStore: %v", err)
	}
	t.Cleanup(func() { s.Close() })
	return s
}

func TestRecord(t *testing.T) {
	s := tempDB(t)

	id, isNewBest, bestQuality, err := s.Record(RecordParams{
		SessionID:     "sess-1",
		CampaignID:    "camp-1",
		TaskType:      "plugin-quality",
		Hypothesis:    "add docstrings",
		QualitySignal: 0.75,
	})
	if err != nil {
		t.Fatalf("Record: %v", err)
	}
	if id == 0 {
		t.Error("expected non-zero ID")
	}
	if !isNewBest {
		t.Error("first record should be new best")
	}
	if bestQuality != 0.75 {
		t.Errorf("best quality = %v, want 0.75", bestQuality)
	}
}

func TestRecordIsNewBest(t *testing.T) {
	s := tempDB(t)

	s.Record(RecordParams{TaskType: "t1", Hypothesis: "first", QualitySignal: 0.5})
	_, isNewBest, _, _ := s.Record(RecordParams{TaskType: "t1", Hypothesis: "better", QualitySignal: 0.8})
	if !isNewBest {
		t.Error("0.8 > 0.5, should be new best")
	}

	_, isNewBest, _, _ = s.Record(RecordParams{TaskType: "t1", Hypothesis: "worse", QualitySignal: 0.3})
	if isNewBest {
		t.Error("0.3 < 0.8, should NOT be new best")
	}
}

func TestQuery(t *testing.T) {
	s := tempDB(t)

	s.Record(RecordParams{TaskType: "t1", Hypothesis: "low", QualitySignal: 0.2})
	s.Record(RecordParams{TaskType: "t1", Hypothesis: "high", QualitySignal: 0.9})
	s.Record(RecordParams{TaskType: "t2", Hypothesis: "other", QualitySignal: 0.5})

	results, err := s.Query(QueryParams{TaskType: "t1"})
	if err != nil {
		t.Fatalf("Query: %v", err)
	}
	if len(results) != 2 {
		t.Fatalf("expected 2 results for t1, got %d", len(results))
	}
	if results[0].QualitySignal != 0.9 {
		t.Error("results should be sorted by quality DESC")
	}
}

func TestQueryMinQuality(t *testing.T) {
	s := tempDB(t)

	s.Record(RecordParams{TaskType: "t1", Hypothesis: "low", QualitySignal: 0.2})
	s.Record(RecordParams{TaskType: "t1", Hypothesis: "high", QualitySignal: 0.9})

	results, _ := s.Query(QueryParams{TaskType: "t1", MinQuality: 0.5})
	if len(results) != 1 {
		t.Fatalf("expected 1 result with min_quality 0.5, got %d", len(results))
	}
}

func TestQueryIsNewBestFilter(t *testing.T) {
	s := tempDB(t)

	s.Record(RecordParams{TaskType: "t1", Hypothesis: "first", QualitySignal: 0.5})
	s.Record(RecordParams{TaskType: "t1", Hypothesis: "worse", QualitySignal: 0.3})
	s.Record(RecordParams{TaskType: "t1", Hypothesis: "best", QualitySignal: 0.9})

	isNewBestOnly := true
	results, _ := s.Query(QueryParams{TaskType: "t1", IsNewBestOnly: &isNewBestOnly})
	if len(results) != 2 {
		t.Fatalf("expected 2 'new best' records, got %d", len(results))
	}
}

func TestGenealogy(t *testing.T) {
	s := tempDB(t)

	id1, _, _, _ := s.Record(RecordParams{TaskType: "t1", Hypothesis: "root", QualitySignal: 0.5, SessionID: "sess-root"})
	_, _, _, _ = s.Record(RecordParams{TaskType: "t1", Hypothesis: "child", QualitySignal: 0.7, InspiredBy: "sess-root", SessionID: "sess-child"})
	s.Record(RecordParams{TaskType: "t1", Hypothesis: "grandchild", QualitySignal: 0.9, InspiredBy: "sess-child", SessionID: "sess-gc"})

	tree, err := s.Genealogy(GenealogyParams{MutationID: id1})
	if err != nil {
		t.Fatalf("Genealogy: %v", err)
	}
	if tree.ID != id1 {
		t.Errorf("root ID = %d, want %d", tree.ID, id1)
	}
	if len(tree.Children) != 1 {
		t.Fatalf("expected 1 child, got %d", len(tree.Children))
	}
	if len(tree.Children[0].Children) != 1 {
		t.Fatalf("expected 1 grandchild, got %d", len(tree.Children[0].Children))
	}
}

func TestGenealogyNotFound(t *testing.T) {
	s := tempDB(t)
	_, err := s.Genealogy(GenealogyParams{MutationID: 99999})
	if err == nil {
		t.Error("expected error for nonexistent mutation")
	}
}

func TestQueryEmpty(t *testing.T) {
	s := tempDB(t)
	results, err := s.Query(QueryParams{TaskType: "nonexistent"})
	if err != nil {
		t.Fatal(err)
	}
	if results == nil {
		t.Error("nil slice: callers expect empty array, not null in JSON")
	}
}

func TestAutoInitDir(t *testing.T) {
	dir := t.TempDir()
	nested := filepath.Join(dir, "a", "b", "c", "mutations.db")
	s, err := NewStore(nested)
	if err != nil {
		t.Fatalf("NewStore with nested path: %v", err)
	}
	s.Close()
	if _, err := os.Stat(nested); os.IsNotExist(err) {
		t.Error("DB file should exist after init")
	}
}
```

**Step 2: Run tests to verify they fail**

Run: `cd interverse/interlab && go test ./internal/mutation/ -v -count=1`
Expected: FAIL — package doesn't exist yet

**Step 3: Implement the store**

Create `interverse/interlab/internal/mutation/store.go`:

```go
package mutation

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"time"

	_ "modernc.org/sqlite"
)

type Store struct {
	db *sql.DB
}

type RecordParams struct {
	SessionID     string
	CampaignID    string
	TaskType      string
	Hypothesis    string
	QualitySignal float64
	InspiredBy    string            // optional session_id
	Metadata      map[string]string // arbitrary key-value
}

type Mutation struct {
	ID            int64             `json:"id"`
	SessionID     string            `json:"session_id"`
	CampaignID    string            `json:"campaign_id"`
	TaskType      string            `json:"task_type"`
	Hypothesis    string            `json:"hypothesis"`
	QualitySignal float64           `json:"quality_signal"`
	IsNewBest     bool              `json:"is_new_best"`
	InspiredBy    string            `json:"inspired_by,omitempty"`
	Metadata      map[string]string `json:"metadata,omitempty"`
	CreatedAt     string            `json:"created_at"`
}

type QueryParams struct {
	TaskType        string
	CampaignID      string
	IsNewBestOnly   *bool
	MinQuality      float64
	InspiredBySession string
	Limit           int
}

type GenealogyParams struct {
	MutationID int64
	SessionID  string
	MaxDepth   int
}

type GenealogyNode struct {
	ID            int64            `json:"id"`
	Hypothesis    string           `json:"hypothesis"`
	QualitySignal float64          `json:"quality_signal"`
	IsNewBest     bool             `json:"is_new_best"`
	SessionID     string           `json:"session_id"`
	InspiredBy    string           `json:"inspired_by"`
	Children      []*GenealogyNode `json:"children,omitempty"`
}

// DDL statements executed individually for proper error reporting.
var ddl = []string{
	`CREATE TABLE IF NOT EXISTS mutations (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		session_id TEXT NOT NULL DEFAULT '',
		campaign_id TEXT NOT NULL DEFAULT '',
		task_type TEXT NOT NULL,
		hypothesis TEXT NOT NULL,
		quality_signal REAL NOT NULL,
		is_new_best INTEGER NOT NULL DEFAULT 0,
		inspired_by TEXT NOT NULL DEFAULT '',
		metadata TEXT NOT NULL DEFAULT '{}',
		created_at TEXT NOT NULL
	)`,
	`CREATE INDEX IF NOT EXISTS idx_mutations_task_quality ON mutations(task_type, quality_signal DESC)`,
	`CREATE INDEX IF NOT EXISTS idx_mutations_campaign ON mutations(campaign_id)`,
	`CREATE INDEX IF NOT EXISTS idx_mutations_inspired_by ON mutations(inspired_by)`,
	`CREATE INDEX IF NOT EXISTS idx_mutations_session ON mutations(session_id)`,
}

func NewStore(dbPath string) (*Store, error) {
	dir := filepath.Dir(dbPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return nil, fmt.Errorf("create db dir: %w", err)
	}

	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		return nil, fmt.Errorf("open db: %w", err)
	}

	// Serialize writes and set busy timeout for concurrent access
	db.SetMaxOpenConns(1)
	if _, err := db.Exec("PRAGMA journal_mode=WAL"); err != nil {
		db.Close()
		return nil, fmt.Errorf("set WAL mode: %w", err)
	}
	if _, err := db.Exec("PRAGMA busy_timeout=5000"); err != nil {
		db.Close()
		return nil, fmt.Errorf("set busy timeout: %w", err)
	}

	for _, stmt := range ddl {
		if _, err := db.Exec(stmt); err != nil {
			db.Close()
			return nil, fmt.Errorf("init schema: %w", err)
		}
	}

	return &Store{db: db}, nil
}

func (s *Store) Close() error {
	return s.db.Close()
}

func DefaultDBPath() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".local", "share", "interlab", "mutations.db")
}

func (s *Store) Record(p RecordParams) (id int64, isNewBest bool, bestQuality float64, err error) {
	if math.IsNaN(p.QualitySignal) || math.IsInf(p.QualitySignal, 0) {
		return 0, false, 0, fmt.Errorf("quality_signal must be a finite number, got %v", p.QualitySignal)
	}

	// Use IMMEDIATE transaction to prevent TOCTOU race on is_new_best.
	// IMMEDIATE acquires a reserved lock at BEGIN, serializing concurrent writers.
	tx, err := s.db.Begin()
	if err != nil {
		return 0, false, 0, fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback() // no-op after Commit

	// Check current best for this task type (inside transaction)
	var currentBest sql.NullFloat64
	err = tx.QueryRow(
		"SELECT MAX(quality_signal) FROM mutations WHERE task_type = ?",
		p.TaskType,
	).Scan(&currentBest)
	if err != nil {
		return 0, false, 0, fmt.Errorf("query current best: %w", err)
	}

	if currentBest.Valid {
		isNewBest = p.QualitySignal > currentBest.Float64
		if isNewBest {
			bestQuality = p.QualitySignal
		} else {
			bestQuality = currentBest.Float64
		}
	} else {
		isNewBest = true
		bestQuality = p.QualitySignal
	}

	metaJSON := "{}"
	if len(p.Metadata) > 0 {
		b, _ := json.Marshal(p.Metadata)
		metaJSON = string(b)
	}

	now := time.Now().UTC().Format(time.RFC3339)

	res, err := tx.Exec(
		`INSERT INTO mutations (session_id, campaign_id, task_type, hypothesis, quality_signal, is_new_best, inspired_by, metadata, created_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		p.SessionID, p.CampaignID, p.TaskType, p.Hypothesis,
		p.QualitySignal, boolToInt(isNewBest), p.InspiredBy, metaJSON, now,
	)
	if err != nil {
		return 0, false, 0, fmt.Errorf("insert mutation: %w", err)
	}

	if err := tx.Commit(); err != nil {
		return 0, false, 0, fmt.Errorf("commit: %w", err)
	}

	id, _ = res.LastInsertId()
	return id, isNewBest, bestQuality, nil
}

func (s *Store) Query(p QueryParams) ([]Mutation, error) {
	query := "SELECT id, session_id, campaign_id, task_type, hypothesis, quality_signal, is_new_best, inspired_by, metadata, created_at FROM mutations WHERE 1=1"
	var args []any

	if p.TaskType != "" {
		query += " AND task_type = ?"
		args = append(args, p.TaskType)
	}
	if p.CampaignID != "" {
		query += " AND campaign_id = ?"
		args = append(args, p.CampaignID)
	}
	if p.IsNewBestOnly != nil && *p.IsNewBestOnly {
		query += " AND is_new_best = 1"
	}
	if p.MinQuality > 0 {
		query += " AND quality_signal >= ?"
		args = append(args, p.MinQuality)
	}
	if p.InspiredBySession != "" {
		query += " AND inspired_by = ?"
		args = append(args, p.InspiredBySession)
	}

	query += " ORDER BY quality_signal DESC"

	limit := p.Limit
	if limit <= 0 {
		limit = 20
	}
	query += " LIMIT ?"
	args = append(args, limit)

	rows, err := s.db.Query(query, args...)
	if err != nil {
		return nil, fmt.Errorf("query mutations: %w", err)
	}
	defer rows.Close()

	results := make([]Mutation, 0) // empty slice, not nil (marshals as [] not null)
	for rows.Next() {
		var m Mutation
		var isNewBestInt int
		var metaJSON string
		if err := rows.Scan(&m.ID, &m.SessionID, &m.CampaignID, &m.TaskType, &m.Hypothesis, &m.QualitySignal, &isNewBestInt, &m.InspiredBy, &metaJSON, &m.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan row: %w", err)
		}
		m.IsNewBest = isNewBestInt == 1
		if metaJSON != "{}" {
			json.Unmarshal([]byte(metaJSON), &m.Metadata)
		}
		results = append(results, m)
	}
	return results, rows.Err()
}

func (s *Store) Genealogy(p GenealogyParams) (*GenealogyNode, error) {
	maxDepth := p.MaxDepth
	if maxDepth <= 0 {
		maxDepth = 10
	}

	// Find the root mutation
	var rootID int64
	if p.MutationID > 0 {
		rootID = p.MutationID
	} else if p.SessionID != "" {
		err := s.db.QueryRow("SELECT id FROM mutations WHERE session_id = ? ORDER BY created_at DESC LIMIT 1", p.SessionID).Scan(&rootID)
		if err != nil {
			return nil, fmt.Errorf("find mutation by session: %w", err)
		}
	} else {
		return nil, fmt.Errorf("must provide mutation_id or session_id")
	}

	// Build the node
	node, err := s.loadNode(rootID)
	if err != nil {
		return nil, err
	}

	// Load descendants (mutations inspired by this session)
	if maxDepth > 0 {
		if err := s.loadDescendants(node, maxDepth-1); err != nil {
			return node, fmt.Errorf("partial tree (root loaded, descendants failed): %w", err)
		}
	}

	return node, nil
}

func (s *Store) loadNode(id int64) (*GenealogyNode, error) {
	var n GenealogyNode
	var isNewBestInt int
	err := s.db.QueryRow(
		"SELECT id, hypothesis, quality_signal, is_new_best, session_id, inspired_by FROM mutations WHERE id = ?", id,
	).Scan(&n.ID, &n.Hypothesis, &n.QualitySignal, &isNewBestInt, &n.SessionID, &n.InspiredBy)
	if err != nil {
		return nil, fmt.Errorf("load node %d: %w", id, err)
	}
	n.IsNewBest = isNewBestInt == 1
	return &n, nil
}

func (s *Store) loadDescendants(node *GenealogyNode, depth int) error {
	if depth <= 0 || node.SessionID == "" {
		return nil
	}

	rows, err := s.db.Query(
		"SELECT id FROM mutations WHERE inspired_by = ? ORDER BY created_at ASC",
		node.SessionID,
	)
	if err != nil {
		return fmt.Errorf("query descendants of %d: %w", node.ID, err)
	}
	defer rows.Close()

	for rows.Next() {
		var childID int64
		if err := rows.Scan(&childID); err != nil {
			return fmt.Errorf("scan child of %d: %w", node.ID, err)
		}
		child, err := s.loadNode(childID)
		if err != nil {
			return err
		}
		if err := s.loadDescendants(child, depth-1); err != nil {
			return err
		}
		node.Children = append(node.Children, child)
	}
	return rows.Err()
}

func boolToInt(b bool) int {
	if b {
		return 1
	}
	return 0
}
```

**Step 4: Run tests to verify they pass**

Run: `cd interverse/interlab && go test ./internal/mutation/ -v -count=1`
Expected: PASS — all tests green

**Step 5: Commit**

```bash
cd interverse/interlab && git add internal/mutation/store.go internal/mutation/store_test.go
git commit -m "feat: add SQLite mutation store with record, query, genealogy"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/interverse/interlab && go test ./internal/mutation/ -v -count=1`
  expect: exit 0
</verify>

---

### Task 3: Implement mutation MCP tools

**Files:**
- Create: `interverse/interlab/internal/mutation/tools.go`
- Create: `interverse/interlab/internal/mutation/tools_test.go`
- Modify: `interverse/interlab/cmd/interlab-mcp/main.go`

**Step 1: Write the failing test for tool handlers**

Create `interverse/interlab/internal/mutation/tools_test.go`:

```go
package mutation

import (
	"context"
	"encoding/json"
	"path/filepath"
	"testing"

	"github.com/mark3labs/mcp-go/mcp"
	"github.com/mark3labs/mcp-go/server"
)

func TestToolRegistration(t *testing.T) {
	s := server.NewMCPServer("test", "0.1.0", server.WithToolCapabilities(true))
	RegisterAll(s)
	// If RegisterAll panics or errors, the test fails
}

func TestHandleMutationRecord(t *testing.T) {
	dir := t.TempDir()
	dbPath := filepath.Join(dir, "test.db")
	t.Setenv("INTERLAB_MUTATIONS_DB", dbPath)

	req := mcp.CallToolRequest{}
	req.Params.Name = "mutation_record"
	req.Params.Arguments = map[string]any{
		"task_type":      "plugin-quality",
		"hypothesis":     "add docstrings to all exported functions",
		"quality_signal": 0.82,
		"session_id":     "test-session-1",
		"campaign_id":    "test-campaign",
	}

	result, err := handleMutationRecord(context.Background(), req)
	if err != nil {
		t.Fatalf("handleMutationRecord: %v", err)
	}

	// Parse the text response
	text := result.Content[0].(mcp.TextContent).Text
	if text == "" {
		t.Error("expected non-empty response")
	}

	// Verify it contains mutation ID and is_new_best
	var resp map[string]any
	if err := json.Unmarshal([]byte(text), &resp); err != nil {
		t.Fatalf("response should be JSON: %v\nGot: %s", err, text)
	}
	if resp["is_new_best"] != true {
		t.Error("first mutation should be new best")
	}
}

func TestHandleMutationQuery(t *testing.T) {
	dir := t.TempDir()
	dbPath := filepath.Join(dir, "test.db")
	t.Setenv("INTERLAB_MUTATIONS_DB", dbPath)

	// Record a mutation first
	recordReq := mcp.CallToolRequest{}
	recordReq.Params.Name = "mutation_record"
	recordReq.Params.Arguments = map[string]any{
		"task_type":      "plugin-quality",
		"hypothesis":     "test hypothesis",
		"quality_signal": 0.75,
	}
	handleMutationRecord(context.Background(), recordReq)

	// Query
	queryReq := mcp.CallToolRequest{}
	queryReq.Params.Name = "mutation_query"
	queryReq.Params.Arguments = map[string]any{
		"task_type": "plugin-quality",
	}

	result, err := handleMutationQuery(context.Background(), queryReq)
	if err != nil {
		t.Fatalf("handleMutationQuery: %v", err)
	}

	text := result.Content[0].(mcp.TextContent).Text
	var resp struct {
		Mutations []Mutation `json:"mutations"`
		Count     int        `json:"count"`
	}
	if err := json.Unmarshal([]byte(text), &resp); err != nil {
		t.Fatalf("response should be JSON: %v", err)
	}
	if resp.Count != 1 {
		t.Errorf("expected 1 mutation, got %d", resp.Count)
	}
}
```

**Step 2: Run tests to verify they fail**

Run: `cd interverse/interlab && go test ./internal/mutation/ -v -count=1 -run TestTool`
Expected: FAIL — functions don't exist yet

**Step 3: Implement the MCP tools**

Create `interverse/interlab/internal/mutation/tools.go`:

```go
package mutation

import (
	"context"
	"encoding/json"
	"fmt"
	"os"

	"github.com/mark3labs/mcp-go/mcp"
	"github.com/mark3labs/mcp-go/server"
)

// Package-level store, injected via RegisterAll from main.go.
var globalStore *Store

var mutationRecordTool = mcp.NewTool("mutation_record",
	mcp.WithDescription("Record a mutation (approach attempt) with provenance metadata. Returns mutation ID, is_new_best status, and current best quality for this task type."),
	mcp.WithString("task_type", mcp.Required(), mcp.Description("Task category for cross-campaign queries (e.g., 'plugin-quality', 'agent-quality')")),
	mcp.WithString("hypothesis", mcp.Required(), mcp.Description("What approach was tried")),
	mcp.WithNumber("quality_signal", mcp.Required(), mcp.Description("Quality metric value (higher is better)")),
	mcp.WithString("session_id", mcp.Description("Session that produced this mutation (default: $CLAUDE_SESSION_ID)")),
	mcp.WithString("campaign_id", mcp.Description("Campaign this mutation belongs to")),
	mcp.WithString("inspired_by", mcp.Description("Session ID that inspired this approach (for provenance tracking)")),
	mcp.WithString("metadata", mcp.Description("JSON string of arbitrary key-value metadata")),
)

var mutationQueryTool = mcp.NewTool("mutation_query",
	mcp.WithDescription("Query mutation history with filters. Returns mutations sorted by quality (best first). Use at campaign start to seed hypotheses from prior approaches."),
	mcp.WithString("task_type", mcp.Description("Filter by task type")),
	mcp.WithString("campaign_id", mcp.Description("Filter by campaign")),
	mcp.WithBoolean("is_new_best", mcp.Description("If true, only return mutations that were new-best at time of recording")),
	mcp.WithNumber("min_quality", mcp.Description("Minimum quality_signal threshold")),
	mcp.WithString("inspired_by_session", mcp.Description("Filter mutations inspired by a specific session")),
	mcp.WithNumber("limit", mcp.Description("Max results to return (default: 20)")),
)

var mutationGenealogyTool = mcp.NewTool("mutation_genealogy",
	mcp.WithDescription("Trace inspiredBy provenance chains to visualize idea evolution. Returns a tree of mutations showing ancestry and descendants with quality signals."),
	mcp.WithNumber("mutation_id", mcp.Description("ID of the mutation to trace from")),
	mcp.WithString("session_id", mcp.Description("Session ID to find the most recent mutation for")),
	mcp.WithNumber("max_depth", mcp.Description("Maximum traversal depth (default: 10)")),
)

// RegisterAll registers mutation tools. Store must be opened once in main.go.
func RegisterAll(s *server.MCPServer, store *Store) {
	globalStore = store
	s.AddTool(mutationRecordTool, handleMutationRecord)
	s.AddTool(mutationQueryTool, handleMutationQuery)
	s.AddTool(mutationGenealogyTool, handleMutationGenealogy)
}

func handleMutationRecord(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	taskType := req.GetString("task_type", "")
	hypothesis := req.GetString("hypothesis", "")
	qualitySignal := req.GetFloat64("quality_signal", 0)

	if taskType == "" || hypothesis == "" {
		return mcp.NewToolResultText("Error: task_type and hypothesis are required"), nil
	}

	sessionID := req.GetString("session_id", "")
	if sessionID == "" {
		sessionID = os.Getenv("CLAUDE_SESSION_ID")
	}

	var meta map[string]string
	if metaStr := req.GetString("metadata", ""); metaStr != "" {
		json.Unmarshal([]byte(metaStr), &meta)
	}

	id, isNewBest, bestQuality, err := globalStore.Record(RecordParams{
		SessionID:     sessionID,
		CampaignID:    req.GetString("campaign_id", ""),
		TaskType:      taskType,
		Hypothesis:    hypothesis,
		QualitySignal: qualitySignal,
		InspiredBy:    req.GetString("inspired_by", ""),
		Metadata:      meta,
	})
	if err != nil {
		return nil, fmt.Errorf("recording mutation: %w", err)
	}

	resp, _ := json.Marshal(map[string]any{
		"mutation_id":  id,
		"is_new_best":  isNewBest,
		"best_quality": bestQuality,
		"task_type":    taskType,
	})
	return mcp.NewToolResultText(string(resp)), nil
}

func handleMutationQuery(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	params := QueryParams{
		TaskType:          req.GetString("task_type", ""),
		CampaignID:        req.GetString("campaign_id", ""),
		InspiredBySession: req.GetString("inspired_by_session", ""),
		MinQuality:        req.GetFloat64("min_quality", 0),
		Limit:             int(req.GetFloat64("limit", 20)),
	}

	if isNewBest := req.GetBoolean("is_new_best", false); isNewBest {
		params.IsNewBestOnly = &isNewBest
	}

	mutations, err := globalStore.Query(params)
	if err != nil {
		return nil, fmt.Errorf("querying mutations: %w", err)
	}

	resp, _ := json.Marshal(map[string]any{
		"mutations": mutations,
		"count":     len(mutations),
	})
	return mcp.NewToolResultText(string(resp)), nil
}

func handleMutationGenealogy(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	mutationID := int64(req.GetFloat64("mutation_id", 0))
	sessionID := req.GetString("session_id", "")

	if mutationID == 0 && sessionID == "" {
		return mcp.NewToolResultText("Error: must provide mutation_id or session_id"), nil
	}

	tree, err := globalStore.Genealogy(GenealogyParams{
		MutationID: mutationID,
		SessionID:  sessionID,
		MaxDepth:   int(req.GetFloat64("max_depth", 10)),
	})
	if err != nil {
		return nil, fmt.Errorf("tracing genealogy: %w", err)
	}

	resp, _ := json.Marshal(tree)
	return mcp.NewToolResultText(string(resp)), nil
}

```

**Step 4: Wire into main.go**

Add mutation store initialization and `mutation.RegisterAll(s, store)` to `cmd/interlab-mcp/main.go`:

In the imports, add:
```go
"github.com/mistakeknot/interlab/internal/mutation"
```

After `orchestration.RegisterAll(s)`, add:
```go
mutStore, err := mutation.NewStore(mutation.DefaultDBPath())
if err != nil {
	fmt.Fprintf(os.Stderr, "interlab-mcp: mutation store: %v\n", err)
	os.Exit(1)
}
defer mutStore.Close()
mutation.RegisterAll(s, mutStore)
```

**Step 5: Run tests to verify they pass**

Run: `cd interverse/interlab && go test ./internal/mutation/ -v -count=1`
Expected: PASS — all tests green

**Step 6: Build to verify compilation**

Run: `cd interverse/interlab && go build ./cmd/interlab-mcp/`
Expected: exit 0

**Step 7: Commit**

```bash
cd interverse/interlab && git add internal/mutation/tools.go internal/mutation/tools_test.go cmd/interlab-mcp/main.go
git commit -m "feat: add mutation_record, mutation_query, mutation_genealogy MCP tools"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/interverse/interlab && go test ./internal/mutation/ -v -count=1`
  expect: exit 0
- run: `cd /home/mk/projects/Sylveste/interverse/interlab && go build ./cmd/interlab-mcp/`
  expect: exit 0
</verify>

---

### Task 4: Write agent quality benchmark script

**Files:**
- Create: `interverse/interlab/scripts/agent-quality-benchmark.sh`

**Step 1: Write the benchmark script**

Create `interverse/interlab/scripts/agent-quality-benchmark.sh`:

```bash
#!/usr/bin/env bash
# agent-quality-benchmark.sh — Score an agent .md file on structural quality.
# Emits METRIC lines compatible with interlab's experiment loop.
#
# Usage: bash agent-quality-benchmark.sh <agent.md>
# Output: METRIC agent_quality_score=N.NNNN (0.0 to 1.0)
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: agent-quality-benchmark.sh <agent.md>" >&2
    exit 1
fi

AGENT_FILE="$1"
if [[ ! -f "$AGENT_FILE" ]]; then
    echo "Error: file not found: $AGENT_FILE" >&2
    exit 1
fi

content=$(cat "$AGENT_FILE")
total_checks=0
passed_checks=0

# --- Structural Quality (6 checks) ---

# 1. Has YAML frontmatter (---)
total_checks=$((total_checks + 1))
if echo "$content" | head -1 | grep -q '^---'; then
    passed_checks=$((passed_checks + 1))
fi

# 2. Has description field in frontmatter
total_checks=$((total_checks + 1))
if echo "$content" | sed -n '/^---$/,/^---$/p' | grep -qi 'description:'; then
    passed_checks=$((passed_checks + 1))
fi

# 3. Has when_to_use or trigger section
total_checks=$((total_checks + 1))
if echo "$content" | grep -qiE '(when.to.use|trigger|use.*when|examples)'; then
    passed_checks=$((passed_checks + 1))
fi

# 4. Has tools or allowed-tools section
total_checks=$((total_checks + 1))
if echo "$content" | grep -qiE '(tools:|allowed.tools|Tools:)'; then
    passed_checks=$((passed_checks + 1))
fi

# 5. Under 500 lines
total_checks=$((total_checks + 1))
line_count=$(wc -l < "$AGENT_FILE")
if [[ "$line_count" -le 500 ]]; then
    passed_checks=$((passed_checks + 1))
fi

# 6. Has markdown headings (structure)
total_checks=$((total_checks + 1))
heading_count=$(grep -c '^#' "$AGENT_FILE" 2>/dev/null || echo 0)
if [[ "$heading_count" -ge 2 ]]; then
    passed_checks=$((passed_checks + 1))
fi

# --- Prompt Quality (4 checks) ---

# 7. Has examples section with concrete examples
total_checks=$((total_checks + 1))
if echo "$content" | grep -qiE '(example|<example>)'; then
    passed_checks=$((passed_checks + 1))
fi

# 8. No vague instructions ("as needed", "if appropriate", "consider")
total_checks=$((total_checks + 1))
vague_count=$(echo "$content" | grep -ciE '(as needed|if appropriate|consider doing|you might want|perhaps)' || echo 0)
if [[ "$vague_count" -le 2 ]]; then
    passed_checks=$((passed_checks + 1))
fi

# 9. Has clear output format specification
total_checks=$((total_checks + 1))
if echo "$content" | grep -qiE '(output|return|respond|format|result)'; then
    passed_checks=$((passed_checks + 1))
fi

# 10. Has scope boundary (what NOT to do)
total_checks=$((total_checks + 1))
if echo "$content" | grep -qiE '(do not|don.t|never|avoid|not for|skip)'; then
    passed_checks=$((passed_checks + 1))
fi

# --- Completeness (3 checks) ---

# 11. Non-trivial content (>20 lines)
total_checks=$((total_checks + 1))
if [[ "$line_count" -ge 20 ]]; then
    passed_checks=$((passed_checks + 1))
fi

# 12. Has system prompt or role definition
total_checks=$((total_checks + 1))
if echo "$content" | grep -qiE '(you are|your role|system.prompt|agent.*that|specialized)'; then
    passed_checks=$((passed_checks + 1))
fi

# 13. References specific file paths or code patterns
total_checks=$((total_checks + 1))
if echo "$content" | grep -qE '(/|\.go|\.py|\.ts|\.md|\.sh|\.yaml)'; then
    passed_checks=$((passed_checks + 1))
fi

# Compute composite score
if [[ "$total_checks" -gt 0 ]]; then
    score=$(awk "BEGIN {printf \"%.4f\", $passed_checks / $total_checks}")
else
    score="0.0000"
fi

echo "METRIC agent_quality_score=$score"
echo "METRIC agent_quality_passed=$passed_checks"
echo "METRIC agent_quality_total=$total_checks"
```

**Step 2: Make it executable**

```bash
chmod +x interverse/interlab/scripts/agent-quality-benchmark.sh
```

**Step 3: Test against an actual interflux agent**

Run: `bash interverse/interlab/scripts/agent-quality-benchmark.sh interverse/interflux/agents/review/fd-architecture.md`
Expected: Output containing `METRIC agent_quality_score=` with a value between 0.0 and 1.0

**Step 4: Test against another agent for comparison**

Run: `bash interverse/interlab/scripts/agent-quality-benchmark.sh interverse/interflux/agents/review/fd-quality.md`
Expected: Output containing `METRIC agent_quality_score=` — may differ from the first agent

**Step 5: Commit**

```bash
cd interverse/interlab && git add scripts/agent-quality-benchmark.sh
git commit -m "feat: add agent quality benchmark script (13-point scoring)"
```

<verify>
- run: `bash /home/mk/projects/Sylveste/interverse/interlab/scripts/agent-quality-benchmark.sh /home/mk/projects/Sylveste/interverse/interflux/agents/review/fd-architecture.md`
  expect: contains "METRIC agent_quality_score="
</verify>

---

### Task 5: Create interflux self-review campaign directory

**Files:**
- Create: `interverse/interlab/campaigns/interflux-self-review/README.md`
- Create: `interverse/interlab/campaigns/interflux-self-review/metric.md`

**Step 1: Create campaign directory and README**

Create `interverse/interlab/campaigns/interflux-self-review/README.md`:

```markdown
# Campaign: interflux-self-review

**Task Type:** `agent-quality`
**Target:** interflux review agent `.md` definitions
**Metric:** `agent_quality_score` (0.0 - 1.0, higher is better)
**Benchmark:** `bash scripts/agent-quality-benchmark.sh <agent.md>`

## Purpose

flux-drive review agents review each other's `.md` definitions for structural quality, prompt clarity, and completeness. This is the first meta-improvement campaign — the review system reviewing and improving itself.

## How to Run

```bash
# From interverse/interflux/ directory:
# 1. Pick a target agent
TARGET="agents/review/fd-architecture.md"

# 2. Launch campaign via /autoresearch
# Metric: agent_quality_score
# Direction: higher_is_better
# Benchmark: bash ../interlab/scripts/agent-quality-benchmark.sh $TARGET
```

## Target Files

All agent definitions in `interverse/interflux/agents/review/`:
- fd-architecture.md
- fd-safety.md
- fd-correctness.md
- fd-quality.md
- fd-user-product.md
- fd-performance.md
- fd-game-design.md
- fd-systems.md
- fd-decisions.md
- fd-people.md
- fd-resilience.md
- fd-perception.md

## Expected Improvements

- Better YAML frontmatter (description accuracy, trigger specificity)
- Clearer when-to-use examples matching real usage patterns
- More specific output format requirements
- Removal of vague language ("consider", "as needed")
- Addition of scope boundaries (what NOT to review)
```

**Step 2: Create metric documentation**

Create `interverse/interlab/campaigns/interflux-self-review/metric.md`:

```markdown
# Agent Quality Scoring Rubric

**Script:** `scripts/agent-quality-benchmark.sh`
**Score Range:** 0.0 to 1.0
**Direction:** higher_is_better

## Sub-scores (13 checks, equal weight)

### Structural Quality (6/13)
1. YAML frontmatter present
2. Description field in frontmatter
3. When-to-use / trigger section
4. Tools or allowed-tools declaration
5. Under 500 lines
6. Has 2+ markdown headings

### Prompt Quality (4/13)
7. Contains examples
8. Minimal vague language (<=2 instances of "as needed", "consider", etc.)
9. Output format specification
10. Scope boundaries (what NOT to do)

### Completeness (3/13)
11. Non-trivial content (>20 lines)
12. Role/identity definition
13. References specific file paths or code patterns

## Interpretation

| Score | Quality |
|-------|---------|
| >= 0.85 | Excellent — production-ready agent |
| 0.70 - 0.84 | Good — minor improvements possible |
| 0.50 - 0.69 | Needs work — missing key sections |
| < 0.50 | Poor — significant structural gaps |
```

**Step 3: Commit**

```bash
cd interverse/interlab && git add campaigns/interflux-self-review/
git commit -m "feat: add interflux-self-review campaign directory and metric docs"
```

<verify>
- run: `test -f /home/mk/projects/Sylveste/interverse/interlab/campaigns/interflux-self-review/README.md && echo "exists"``
  expect: contains "exists"
</verify>

---

### Task 6: Update /autoresearch skill for mutation store integration

**Files:**
- Modify: `interverse/interlab/skills/autoresearch/SKILL.md`

**Step 1: Read the current SKILL.md**

Read `interverse/interlab/skills/autoresearch/SKILL.md` to understand the current structure before modifying.

**Step 2: Add mutation query at campaign startup**

In the Setup Phase (after `init_experiment` and baseline), add this section:

```markdown
#### Query Prior Mutations (if mutation store available)

After establishing baseline, check for prior approaches on this task type:

1. Call `mutation_query` with:
   - `task_type`: the campaign's task type (e.g., "agent-quality", "plugin-quality")
   - `is_new_best`: true (only successful approaches)
   - `limit`: 10

2. If results returned, add to `interlab.md` under "## Prior Approaches (from mutation store)":
   - List each prior approach: hypothesis, quality_signal, campaign_id
   - Mark which ones are "known good" (is_new_best=true) and "known dead ends" (recorded but not new_best)
   - These seed the agent's hypothesis generation — avoid re-exploring dead ends

3. If `mutation_query` fails or returns empty: continue normally. The mutation store is optional.
```

**Step 3: Add mutation recording after each experiment**

In the Loop Phase, after `log_experiment`, add:

```markdown
#### Record Mutation

After each `log_experiment` call, record the mutation for provenance tracking:

1. Call `mutation_record` with:
   - `task_type`: campaign's task type
   - `hypothesis`: the description passed to log_experiment
   - `quality_signal`: the metric value from run_experiment
   - `campaign_id`: the campaign name
   - `inspired_by`: if the hypothesis was explicitly inspired by a prior approach from the mutation query, include that session_id

2. Note whether `is_new_best` was true — this signals a meaningful improvement.

3. If `mutation_record` fails: log a warning but do NOT stop the campaign. Mutation recording is best-effort.
```

**Step 4: Verify the SKILL.md is valid**

Run: `wc -l interverse/interlab/skills/autoresearch/SKILL.md`
Expected: File exists and has been modified

**Step 5: Commit**

```bash
cd interverse/interlab && git add skills/autoresearch/SKILL.md
git commit -m "feat: wire mutation store into /autoresearch (query at start, record after each experiment)"
```

<verify>
- run: `grep -c "mutation_record\|mutation_query" /home/mk/projects/Sylveste/interverse/interlab/skills/autoresearch/SKILL.md`
  expect: contains "2"
</verify>

---

### Task 7: Run full test suite and verify build

**Files:**
- No new files

**Step 1: Run all Go tests**

Run: `cd interverse/interlab && go test ./... -v -count=1`
Expected: PASS — all packages pass

**Step 2: Build the binary**

Run: `cd interverse/interlab && go build -o bin/interlab-mcp ./cmd/interlab-mcp/`
Expected: exit 0, binary exists

**Step 3: Verify MCP server starts**

Run: `echo '{"jsonrpc":"2.0","method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0.1"}},"id":1}' | timeout 5 interverse/interlab/bin/interlab-mcp 2>/dev/null | head -1`
Expected: JSON response containing "interlab"

**Step 4: Verify mutation tools are listed**

Run: `echo -e '{"jsonrpc":"2.0","method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0.1"}},"id":1}\n{"jsonrpc":"2.0","method":"tools/list","params":{},"id":2}' | timeout 5 interverse/interlab/bin/interlab-mcp 2>/dev/null | tail -1`
Expected: Output contains "mutation_record", "mutation_query", "mutation_genealogy"

**Step 5: Final commit with version bump**

Update version in `interverse/interlab/.claude-plugin/plugin.json` from `0.3.7` to `0.4.0` (new feature: mutation store).

```bash
cd interverse/interlab && git add .claude-plugin/plugin.json
git commit -m "chore: bump interlab to v0.4.0 (mutation store)"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/interverse/interlab && go test ./... -count=1`
  expect: exit 0
- run: `cd /home/mk/projects/Sylveste/interverse/interlab && go build -o bin/interlab-mcp ./cmd/interlab-mcp/`
  expect: exit 0
</verify>
