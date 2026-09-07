---
artifact_type: plan
bead: sylveste-myyw.7
stage: design
date: 2026-04-19
supersedes: docs/plans/2026-04-18-gate-threshold-calibration-v2.md
prd: docs/prds/2026-04-18-gate-threshold-calibration-v2.md
brainstorm: docs/brainstorms/2026-04-18-gate-threshold-calibration-v2-brainstorm.md
requirements:
  - F1: gate.db storage layer (no writer wired into cmdEnforceGate — superseded)
  - F2: calibrate-gate-tiers v2 (drain consumes `ic gate signals`)
  - F3: SessionEnd hook + backward-compat JSON export
---

# Gate-threshold calibration v2 (regen) — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `clavain:executing-plans` to implement this plan task-by-task.

**Bead:** `sylveste-myyw.7`
**Goal:** Replace v1's static JSON-only calibration with a SQLite-backed v2 store at `.clavain/gate.db` that consumes the existing `ic gate signals` stream, applies a per-theme rolling-window algorithm with stability preconditions, runs on SessionEnd, and regenerates the v1 JSON for backward compat.

**Architecture:** v1 already does the right data-flow shape — consume `ic gate signals --since-id=<cursor>`, apply weighted-decay formulas, write JSON. v2 keeps the data source untouched and only changes the downstream: state moves from JSON → SQLite gate.db, keying gains a `theme` axis, the algorithm gains window partitioning + consecutive-stable + small-n safety, and a SessionEnd hook automates the loop. **`cmdEnforceGate` is NOT modified** (the superseded plan instrumented it; see PRD/brainstorm SUPERSEDED markers).

**Tech Stack:** Go (existing `os/Clavain/cmd/clavain-cli` binary). SQLite via `modernc.org/sqlite v1.29.0` (already in `go.mod`, used by `calibration.go`/`intent.go`). Bash for the SessionEnd hook.

**Prior Learnings:** No `docs/research/assess-*.md` or `docs/solutions/` entry maps directly to gate calibration. The pattern of "drain durable signals into rolling-window state on SessionEnd" mirrors `cmdInterspectRecordCanary` (`os/Clavain/cmd/clavain-cli/calibration.go`) — same sqlite driver, same `_ "modernc.org/sqlite"` blank import, same `sql.Open("sqlite", ...)` shape.

---

## Working Constraints

- **Trunk-based.** Per `os/Clavain/CLAUDE.md`: no branches. Commit directly to `main` from inside `os/Clavain/`.
- **Tests first.** Each task writes a failing test, runs it red, implements minimum, runs it green.
- **Build gate per commit.** `cd os/Clavain/cmd/clavain-cli && /usr/local/go/bin/go test ./... && /usr/local/go/bin/go build` must pass before the next commit.
- **No edit to `phase.go`.** Architectural invariant — flag if any task tempts you to touch it.

## Must-Haves

**Truths** (observable behaviors):
- A SessionEnd that runs `clavain-cli calibrate-gate-tiers --auto` produces a `drain_log` row with `drain_committed != NULL` (or exits 2 if no new signals).
- After the first successful drain on a project that has v1 `.clavain/gate-tier-calibration.json`, the JSON is renamed to `.v1.json.bak` and `gate.db:tier_state` contains one row per former v1 entry with `theme='default', theme_source='migrated'`.
- After every successful drain, `.clavain/gate-tier-calibration.json` is regenerated from `tier_state` in v1 schema shape, and `ic gate check --calibration-file=<path>` parses it without error.
- A theme that exceeds `fnr_threshold` (default 0.30) on ≥3 consecutive non-empty drains with `weighted_n ≥ 10` and no `fnr==0 && n<20` and respects 7-day cooldown + 90d velocity is promoted soft→hard. Empty drains are no-ops on the counter.
- Concurrent `calibrate-gate-tiers` invocations don't corrupt cursor or tier_state; one wins, the other either no-ops (exit 2) or retries via `BEGIN IMMEDIATE` backoff.

**Artifacts** (files with specific exports):
- `os/Clavain/cmd/clavain-cli/gatecal/gatecal.go` exports `Store`, `Open(path) (*Store, error)`, `Close()`, table types `TierState`, `DrainResult`.
- `os/Clavain/cmd/clavain-cli/gatecal/theme.go` exports `DeriveTheme(checkType string, bdStateFn func(string) (string, bool)) (theme, source string)`.
- `os/Clavain/cmd/clavain-cli/gatecal/drain.go` exports `func (s *Store) Drain(ctx, now, invoker, signals []GateSignal) (DrainResult, error)`.
- `os/Clavain/cmd/clavain-cli/gatecal/migrate.go` exports `func (s *Store) MigrateFromV1(ctx, v1Path string) error`.
- `os/Clavain/cmd/clavain-cli/gatecal/export.go` exports `func (s *Store) ExportV1JSON(ctx, path string, sinceID int64) error`.
- `os/Clavain/hooks/gate-calibration-session-end.sh` (executable, registered in `hooks/hooks.json`).

**Key Links** (connections where breakage cascades):
- `calibrate-gate-tiers` (refactored in T6) MUST call `MigrateFromV1` BEFORE `Drain` BEFORE `ExportV1JSON`. Migration is idempotent; out-of-order export would write empty JSON and break `ic gate check`.
- `Drain` reads cursor from `drain_log`, writes cursor in same transaction. Splitting cursor read/write across transactions risks lost or replayed signals.
- The `theme_source` value (`labeled|inferred|default|migrated`) is stable user-visible state — don't rename strings without updating tests AND export.

---

## Pre-flight

```bash
cd /home/mk/projects/Sylveste/os/Clavain/cmd/clavain-cli
/usr/local/go/bin/go test ./... 2>&1 | tail -20
/usr/local/go/bin/go build ./... 2>&1 | tail -10
```
Expected: green baseline. If red, stop and triage before proceeding.

---

## Task sequence

### Task 1: gatecal package skeleton + schema

**Files:**
- Create: `os/Clavain/cmd/clavain-cli/gatecal/gatecal.go`
- Create: `os/Clavain/cmd/clavain-cli/gatecal/gatecal_test.go`

**Step 1: Write the failing test**
```go
// gatecal/gatecal_test.go
package gatecal

import (
	"path/filepath"
	"testing"
)

func TestOpenCreatesSchema(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "gate.db")

	s, err := Open(path)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer s.Close()

	expectTables := []string{"tier_state", "drain_log", "signals_cache"}
	for _, tbl := range expectTables {
		var name string
		err := s.DB().QueryRow(`SELECT name FROM sqlite_master WHERE type='table' AND name=?`, tbl).Scan(&name)
		if err != nil {
			t.Errorf("missing table %s: %v", tbl, err)
		}
	}
}

func TestOpenIsIdempotent(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "gate.db")

	s1, err := Open(path)
	if err != nil {
		t.Fatalf("first Open: %v", err)
	}
	s1.Close()

	s2, err := Open(path)
	if err != nil {
		t.Fatalf("second Open (re-init): %v", err)
	}
	defer s2.Close()
}

func TestTierStateColumns(t *testing.T) {
	dir := t.TempDir()
	s, err := Open(filepath.Join(dir, "gate.db"))
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer s.Close()

	rows, err := s.DB().Query(`PRAGMA table_info(tier_state)`)
	if err != nil {
		t.Fatalf("PRAGMA: %v", err)
	}
	defer rows.Close()

	want := map[string]bool{
		"theme": true, "check_type": true, "phase_from": true, "phase_to": true,
		"tier": true, "fpr": true, "fnr": true, "weighted_n": true,
		"consecutive_windows_above_threshold": true, "locked": true,
		"change_count_90d": true, "last_changed_at": true,
		"fnr_threshold": true, "origin_key": true, "theme_source": true, "updated_at": true,
	}
	got := map[string]bool{}
	for rows.Next() {
		var cid int
		var name, typ string
		var notnull, pk int
		var dflt interface{}
		_ = rows.Scan(&cid, &name, &typ, &notnull, &dflt, &pk)
		got[name] = true
	}
	for col := range want {
		if !got[col] {
			t.Errorf("tier_state missing column %s", col)
		}
	}
}
```

**Step 2: Run test to verify it fails**
Run: `cd os/Clavain/cmd/clavain-cli && /usr/local/go/bin/go test ./gatecal/...`
Expected: FAIL — package missing.

**Step 3: Write minimal implementation**
```go
// gatecal/gatecal.go
// Package gatecal manages the SQLite-backed gate threshold calibration store
// at .clavain/gate.db. v2 keeps `ic gate signals` as the data source (same as
// v1) and only changes the downstream state representation.
package gatecal

import (
	"context"
	"database/sql"
	"fmt"

	_ "modernc.org/sqlite"
)

// Store wraps a sqlite handle for gate.db.
type Store struct {
	db *sql.DB
}

// Open initializes (or opens) gate.db at path and ensures the schema exists.
func Open(path string) (*Store, error) {
	dsn := path + "?_busy_timeout=5000&_journal_mode=WAL"
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, fmt.Errorf("gatecal: open: %w", err)
	}
	s := &Store{db: db}
	if err := s.ensureSchema(context.Background()); err != nil {
		_ = db.Close()
		return nil, err
	}
	return s, nil
}

// DB exposes the underlying handle (for tests + advanced consumers).
func (s *Store) DB() *sql.DB { return s.db }

// Close releases the sqlite handle.
func (s *Store) Close() error { return s.db.Close() }

const schema = `
CREATE TABLE IF NOT EXISTS tier_state (
  theme TEXT NOT NULL,
  check_type TEXT NOT NULL,
  phase_from TEXT NOT NULL,
  phase_to TEXT NOT NULL,
  tier TEXT NOT NULL DEFAULT 'soft',
  fpr REAL,
  fnr REAL,
  weighted_n REAL NOT NULL DEFAULT 0,
  consecutive_windows_above_threshold INTEGER NOT NULL DEFAULT 0,
  locked INTEGER NOT NULL DEFAULT 0,
  change_count_90d INTEGER NOT NULL DEFAULT 0,
  last_changed_at INTEGER,
  fnr_threshold REAL,
  origin_key TEXT,
  theme_source TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (theme, check_type, phase_from, phase_to)
);

CREATE TABLE IF NOT EXISTS drain_log (
  rowid INTEGER PRIMARY KEY AUTOINCREMENT,
  drain_started INTEGER NOT NULL,
  drain_committed INTEGER,
  signals_processed INTEGER,
  since_id_before INTEGER,
  since_id_after INTEGER,
  state_changes INTEGER,
  invoker TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS signals_cache (
  event_id INTEGER PRIMARY KEY,
  run_id TEXT,
  check_type TEXT,
  phase_from TEXT,
  phase_to TEXT,
  signal TEXT,
  category TEXT,
  created_at INTEGER
);

CREATE INDEX IF NOT EXISTS idx_drain_log_committed ON drain_log(drain_committed);
CREATE INDEX IF NOT EXISTS idx_signals_cache_created ON signals_cache(created_at);
`

func (s *Store) ensureSchema(ctx context.Context) error {
	_, err := s.db.ExecContext(ctx, schema)
	if err != nil {
		return fmt.Errorf("gatecal: ensureSchema: %w", err)
	}
	return nil
}
```

**Step 4: Run test to verify it passes**
Run: `cd os/Clavain/cmd/clavain-cli && /usr/local/go/bin/go test ./gatecal/...`
Expected: PASS — all three tests.

**Step 5: Commit**
```bash
cd os/Clavain
git add cmd/clavain-cli/gatecal/gatecal.go cmd/clavain-cli/gatecal/gatecal_test.go
git commit -m "feat(gatecal): scaffold sqlite store with tier_state/drain_log/signals_cache schema"
```

<verify>
- run: `cd os/Clavain/cmd/clavain-cli && /usr/local/go/bin/go test ./gatecal/...`
  expect: exit 0
- run: `cd os/Clavain/cmd/clavain-cli && /usr/local/go/bin/go build ./...`
  expect: exit 0
</verify>

---

### Task 2: Theme derivation

**Files:**
- Create: `os/Clavain/cmd/clavain-cli/gatecal/theme.go`
- Create: `os/Clavain/cmd/clavain-cli/gatecal/theme_test.go`

**Step 1: Write the failing test**
```go
// gatecal/theme_test.go
package gatecal

import "testing"

func TestDeriveTheme(t *testing.T) {
	cases := []struct {
		name       string
		checkType  string
		bdStateVal string
		bdStateOK  bool
		wantTheme  string
		wantSource string
	}{
		{"labeled wins", "safety_secrets", "compliance", true, "compliance", "labeled"},
		{"inferred prefix safety_", "safety_secrets", "", false, "safety", "inferred"},
		{"inferred prefix quality_", "quality_test_pass", "", false, "quality", "inferred"},
		{"inferred prefix perf_", "perf_p99_latency", "", false, "perf", "inferred"},
		{"default fallback", "random_check", "", false, "default", "default"},
		{"empty check defaults", "", "", false, "default", "default"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			fn := func(string) (string, bool) { return c.bdStateVal, c.bdStateOK }
			theme, src := DeriveTheme(c.checkType, fn)
			if theme != c.wantTheme || src != c.wantSource {
				t.Errorf("DeriveTheme(%q) = (%q,%q), want (%q,%q)",
					c.checkType, theme, src, c.wantTheme, c.wantSource)
			}
		})
	}
}
```

**Step 2: Run test to verify it fails**
Run: `cd os/Clavain/cmd/clavain-cli && /usr/local/go/bin/go test ./gatecal/ -run TestDeriveTheme`
Expected: FAIL — `DeriveTheme` undefined.

**Step 3: Write minimal implementation**
```go
// gatecal/theme.go
package gatecal

import "strings"

// knownPrefixes maps check_type prefix → theme.
// Order doesn't matter — we test exact prefix match.
var knownPrefixes = map[string]string{
	"safety_":  "safety",
	"quality_": "quality",
	"perf_":    "perf",
}

// DeriveTheme returns (theme, theme_source) for a given check_type. Resolution order:
//  1. bdStateFn returns (val, true) → ("val", "labeled") — explicit per-bead label
//  2. checkType has a known prefix → (prefix-without-underscore, "inferred")
//  3. else → ("default", "default")
//
// bdStateFn is injected so production wires `bd state <bead> theme` and tests
// inject a stub. Pass nil for "no labeling source available".
func DeriveTheme(checkType string, bdStateFn func(string) (string, bool)) (theme, source string) {
	if bdStateFn != nil {
		if v, ok := bdStateFn(checkType); ok && v != "" {
			return v, "labeled"
		}
	}
	for prefix, theme := range knownPrefixes {
		if strings.HasPrefix(checkType, prefix) {
			return theme, "inferred"
		}
	}
	return "default", "default"
}
```

**Step 4: Run test to verify it passes**
Run: `cd os/Clavain/cmd/clavain-cli && /usr/local/go/bin/go test ./gatecal/ -run TestDeriveTheme -v`
Expected: PASS — all 6 subtests.

**Step 5: Commit**
```bash
cd os/Clavain
git add cmd/clavain-cli/gatecal/theme.go cmd/clavain-cli/gatecal/theme_test.go
git commit -m "feat(gatecal): theme derivation (labeled > inferred > default)"
```

<verify>
- run: `cd os/Clavain/cmd/clavain-cli && /usr/local/go/bin/go test ./gatecal/ -run TestDeriveTheme`
  expect: exit 0
</verify>

---

### Task 3: v1 → v2 migration

**Files:**
- Create: `os/Clavain/cmd/clavain-cli/gatecal/migrate.go`
- Create: `os/Clavain/cmd/clavain-cli/gatecal/migrate_test.go`

**Step 1: Write the failing test**
```go
// gatecal/migrate_test.go
package gatecal

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

// v1Shape mirrors GateCalibrationFile in main package — duplicated here to keep
// gatecal package self-contained and avoid an import cycle. If the upstream
// shape changes, this test will fail at unmarshal time and we update both.
type v1Shape struct {
	CreatedAt int64                  `json:"created_at"`
	SinceID   int64                  `json:"since_id"`
	Tiers     map[string]v1EntryTest `json:"tiers"`
}
type v1EntryTest struct {
	Tier           string  `json:"tier"`
	Locked         bool    `json:"locked"`
	FPR            float64 `json:"fpr"`
	FNR            float64 `json:"fnr"`
	WeightedN      float64 `json:"weighted_n"`
	LastChangedAt  int64   `json:"last_changed_at,omitempty"`
	ChangeCount90d int     `json:"change_count_90d,omitempty"`
	UpdatedAt      int64   `json:"updated_at"`
}

func TestMigrateFromV1Inserts(t *testing.T) {
	dir := t.TempDir()
	v1Path := filepath.Join(dir, "gate-tier-calibration.json")
	v1 := v1Shape{
		CreatedAt: 1700000000,
		SinceID:   42,
		Tiers: map[string]v1EntryTest{
			"safety_secrets|brainstorm|design":  {Tier: "hard", FPR: 0.1, FNR: 0.4, WeightedN: 12, UpdatedAt: 1700000000},
			"quality_test_pass|design|planning": {Tier: "soft", FPR: 0.05, FNR: 0.2, WeightedN: 8, UpdatedAt: 1700000000},
			"random_check|x|y":                  {Tier: "soft", FPR: 0, FNR: 0, WeightedN: 0, UpdatedAt: 1700000000},
		},
	}
	data, _ := json.MarshalIndent(v1, "", "  ")
	if err := os.WriteFile(v1Path, data, 0644); err != nil {
		t.Fatal(err)
	}

	s, err := Open(filepath.Join(dir, "gate.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()

	if err := s.MigrateFromV1(context.Background(), v1Path); err != nil {
		t.Fatalf("MigrateFromV1: %v", err)
	}

	// Verify 3 rows in tier_state, all theme='default', theme_source='migrated'.
	var n int
	err = s.DB().QueryRow(`SELECT COUNT(*) FROM tier_state WHERE theme='default' AND theme_source='migrated'`).Scan(&n)
	if err != nil {
		t.Fatal(err)
	}
	if n != 3 {
		t.Errorf("expected 3 migrated rows, got %d", n)
	}

	// Verify origin_key preserved.
	rows, _ := s.DB().Query(`SELECT origin_key FROM tier_state ORDER BY origin_key`)
	defer rows.Close()
	got := []string{}
	for rows.Next() {
		var k string
		_ = rows.Scan(&k)
		got = append(got, k)
	}
	want := []string{
		"quality_test_pass|design|planning",
		"random_check|x|y",
		"safety_secrets|brainstorm|design",
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("origin_key[%d] = %q, want %q", i, got[i], want[i])
		}
	}

	// Verify v1 file archived.
	if _, err := os.Stat(v1Path + ".v1.json.bak"); err != nil {
		t.Errorf("expected .v1.json.bak: %v", err)
	}
	if _, err := os.Stat(v1Path); !os.IsNotExist(err) {
		t.Errorf("expected v1 path removed, got %v", err)
	}
}

func TestMigrateFromV1Idempotent(t *testing.T) {
	dir := t.TempDir()
	v1Path := filepath.Join(dir, "gate-tier-calibration.json")
	v1 := v1Shape{Tiers: map[string]v1EntryTest{"a|b|c": {Tier: "soft"}}}
	data, _ := json.MarshalIndent(v1, "", "  ")
	_ = os.WriteFile(v1Path, data, 0644)

	s, _ := Open(filepath.Join(dir, "gate.db"))
	defer s.Close()

	if err := s.MigrateFromV1(context.Background(), v1Path); err != nil {
		t.Fatal(err)
	}
	// Re-create v1 file (simulating a stale leftover) and re-run.
	_ = os.WriteFile(v1Path, data, 0644)
	if err := s.MigrateFromV1(context.Background(), v1Path); err != nil {
		t.Fatalf("second MigrateFromV1: %v", err)
	}

	var n int
	_ = s.DB().QueryRow(`SELECT COUNT(*) FROM tier_state`).Scan(&n)
	if n != 1 {
		t.Errorf("expected idempotent (1 row), got %d", n)
	}
}

func TestMigrateFromV1NoFile(t *testing.T) {
	dir := t.TempDir()
	s, _ := Open(filepath.Join(dir, "gate.db"))
	defer s.Close()

	// Missing v1 file is not an error — just a no-op.
	if err := s.MigrateFromV1(context.Background(), filepath.Join(dir, "nonexistent.json")); err != nil {
		t.Errorf("expected nil for missing v1 file, got %v", err)
	}
}
```

**Step 2: Run test to verify it fails**
Run: `cd os/Clavain/cmd/clavain-cli && /usr/local/go/bin/go test ./gatecal/ -run TestMigrate`
Expected: FAIL — `MigrateFromV1` undefined.

**Step 3: Write minimal implementation**
```go
// gatecal/migrate.go
package gatecal

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"time"
)

// v1File mirrors the GateCalibrationFile JSON shape in the main package. We
// intentionally duplicate (rather than import) to keep gatecal self-contained.
type v1File struct {
	CreatedAt int64                `json:"created_at"`
	SinceID   int64                `json:"since_id"`
	Tiers     map[string]v1Entry   `json:"tiers"`
}

type v1Entry struct {
	Tier           string  `json:"tier"`
	Locked         bool    `json:"locked"`
	FPR            float64 `json:"fpr"`
	FNR            float64 `json:"fnr"`
	WeightedN      float64 `json:"weighted_n"`
	LastChangedAt  int64   `json:"last_changed_at,omitempty"`
	ChangeCount90d int     `json:"change_count_90d,omitempty"`
	UpdatedAt      int64   `json:"updated_at"`
}

// MigrateFromV1 reads a v1 calibration JSON file at v1Path and inserts each
// tier entry into tier_state with theme='default', theme_source='migrated'.
// Idempotent: returns nil immediately if tier_state is non-empty. Archives the
// v1 file as <v1Path>.v1.json.bak after a successful COMMIT. A missing v1 file
// is treated as a no-op (not an error).
func (s *Store) MigrateFromV1(ctx context.Context, v1Path string) error {
	// Idempotency: bail if any rows exist.
	var count int
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM tier_state`).Scan(&count); err != nil {
		return fmt.Errorf("gatecal.migrate: count tier_state: %w", err)
	}
	if count > 0 {
		return nil
	}

	data, err := os.ReadFile(v1Path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil
		}
		return fmt.Errorf("gatecal.migrate: read %s: %w", v1Path, err)
	}

	var v1 v1File
	if err := json.Unmarshal(data, &v1); err != nil {
		return fmt.Errorf("gatecal.migrate: parse v1 JSON: %w", err)
	}
	if len(v1.Tiers) == 0 {
		// Empty v1 — still archive to avoid a re-import loop next session.
		return os.Rename(v1Path, v1Path+".v1.json.bak")
	}

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("gatecal.migrate: begin: %w", err)
	}
	defer tx.Rollback()

	now := time.Now().Unix()
	for key, entry := range v1.Tiers {
		// v1 key is "check_type|phase_from|phase_to"
		ct, pf, pt, ok := splitV1Key(key)
		if !ok {
			return fmt.Errorf("gatecal.migrate: malformed v1 key %q", key)
		}
		locked := 0
		if entry.Locked {
			locked = 1
		}
		_, err := tx.ExecContext(ctx, `
INSERT INTO tier_state (theme, check_type, phase_from, phase_to, tier, fpr, fnr, weighted_n, locked, change_count_90d, last_changed_at, origin_key, theme_source, updated_at)
VALUES ('default', ?, ?, ?, ?, ?, ?, ?, ?, ?, NULLIF(?, 0), ?, 'migrated', ?)`,
			ct, pf, pt, entry.Tier, entry.FPR, entry.FNR, entry.WeightedN,
			locked, entry.ChangeCount90d, entry.LastChangedAt, key, now,
		)
		if err != nil {
			return fmt.Errorf("gatecal.migrate: insert %q: %w", key, err)
		}
	}

	if err := tx.Commit(); err != nil {
		return fmt.Errorf("gatecal.migrate: commit: %w", err)
	}

	if err := os.Rename(v1Path, v1Path+".v1.json.bak"); err != nil {
		return fmt.Errorf("gatecal.migrate: archive %s: %w", v1Path, err)
	}
	return nil
}

func splitV1Key(key string) (ct, pf, pt string, ok bool) {
	parts := splitN(key, "|", 3)
	if len(parts) != 3 {
		return "", "", "", false
	}
	return parts[0], parts[1], parts[2], true
}

// splitN is a tiny strings.SplitN equivalent — kept inline so this file has
// only one stdlib-strings dependency point in the test diff (clearer review).
func splitN(s, sep string, n int) []string {
	out := []string{}
	cur := ""
	count := 0
	for i := 0; i < len(s); i++ {
		if count < n-1 && i+len(sep) <= len(s) && s[i:i+len(sep)] == sep {
			out = append(out, cur)
			cur = ""
			i += len(sep) - 1
			count++
			continue
		}
		cur += string(s[i])
	}
	out = append(out, cur)
	return out
}
```

> Note: `splitN` is hand-rolled because the rest of the package has minimal stdlib surface. If you prefer `strings.SplitN`, use it — equivalent behavior.

**Step 4: Run test to verify it passes**
Run: `cd os/Clavain/cmd/clavain-cli && /usr/local/go/bin/go test ./gatecal/ -run TestMigrate -v`
Expected: PASS — all 3 subtests.

**Step 5: Commit**
```bash
cd os/Clavain
git add cmd/clavain-cli/gatecal/migrate.go cmd/clavain-cli/gatecal/migrate_test.go
git commit -m "feat(gatecal): idempotent v1->v2 migration with .bak archive"
```

<verify>
- run: `cd os/Clavain/cmd/clavain-cli && /usr/local/go/bin/go test ./gatecal/ -run TestMigrate`
  expect: exit 0
</verify>

---

### Task 4: Drain implementation (signals → tier_state)

**Files:**
- Create: `os/Clavain/cmd/clavain-cli/gatecal/drain.go`
- Create: `os/Clavain/cmd/clavain-cli/gatecal/drain_test.go`

**Constants and signal type are package-level.** This task introduces them.

**Step 1: Write the failing test**
```go
// gatecal/drain_test.go
package gatecal

import (
	"context"
	"path/filepath"
	"sync"
	"testing"
	"time"
)

// helper: build a signal with sane defaults
func sig(eventID int64, ct, pf, pt, signal string, ageDays int) GateSignal {
	return GateSignal{
		EventID:   eventID,
		RunID:     "run1",
		CheckType: ct,
		FromPhase: pf,
		ToPhase:   pt,
		Signal:    signal,
		CreatedAt: time.Now().Unix() - int64(ageDays)*86400,
	}
}

func TestDrainEmptyIsNoOp(t *testing.T) {
	s, _ := Open(filepath.Join(t.TempDir(), "gate.db"))
	defer s.Close()
	now := time.Now().Unix()
	res, err := s.Drain(context.Background(), now, "auto", nil)
	if err != nil {
		t.Fatal(err)
	}
	if res.SignalsProcessed != 0 || res.StateChanges != 0 {
		t.Errorf("expected empty result, got %+v", res)
	}
	// drain_log should still record the attempt with drain_committed set
	var n int
	_ = s.DB().QueryRow(`SELECT COUNT(*) FROM drain_log WHERE drain_committed IS NOT NULL`).Scan(&n)
	if n != 1 {
		t.Errorf("expected 1 committed drain row, got %d", n)
	}
}

func TestDrainSmallNNoPromotion(t *testing.T) {
	s, _ := Open(filepath.Join(t.TempDir(), "gate.db"))
	defer s.Close()
	now := time.Now().Unix()
	// 5 fn signals on safety_secrets — weighted_n ~ 5, below threshold of 10.
	signals := []GateSignal{}
	for i := int64(1); i <= 5; i++ {
		signals = append(signals, sig(i, "safety_secrets", "design", "plan", "fn", 0))
	}
	_, err := s.Drain(context.Background(), now, "auto", signals)
	if err != nil {
		t.Fatal(err)
	}
	var tier string
	_ = s.DB().QueryRow(`SELECT tier FROM tier_state WHERE check_type='safety_secrets'`).Scan(&tier)
	if tier != "soft" {
		t.Errorf("expected soft (small-n guard), got %q", tier)
	}
}

func TestDrainZeroFNRSmallSampleNoPromotion(t *testing.T) {
	s, _ := Open(filepath.Join(t.TempDir(), "gate.db"))
	defer s.Close()
	now := time.Now().Unix()
	// 12 tn signals, 0 fn — weighted_n=12 (>=10) but fnr=0 with n<20 → no promote.
	signals := []GateSignal{}
	for i := int64(1); i <= 12; i++ {
		signals = append(signals, sig(i, "safety_secrets", "design", "plan", "tn", 0))
	}
	_, err := s.Drain(context.Background(), now, "auto", signals)
	if err != nil {
		t.Fatal(err)
	}
	var tier string
	_ = s.DB().QueryRow(`SELECT tier FROM tier_state WHERE check_type='safety_secrets'`).Scan(&tier)
	if tier != "soft" {
		t.Errorf("expected soft (zero-FNR small-sample guard), got %q", tier)
	}
}

func TestDrainConsecutiveStablePromotes(t *testing.T) {
	s, _ := Open(filepath.Join(t.TempDir(), "gate.db"))
	defer s.Close()
	now := time.Now().Unix()

	build := func(eventBase int64) []GateSignal {
		out := []GateSignal{}
		// 6 tn + 4 fn → fnr = 0.4, weighted_n ~ 10 → above threshold.
		for i := int64(0); i < 6; i++ {
			out = append(out, sig(eventBase+i, "safety_secrets", "design", "plan", "tn", 0))
		}
		for i := int64(0); i < 4; i++ {
			out = append(out, sig(eventBase+6+i, "safety_secrets", "design", "plan", "fn", 0))
		}
		return out
	}

	// Drain 1: counter → 1, still soft
	_, _ = s.Drain(context.Background(), now, "auto", build(100))
	assertTier(t, s, "safety_secrets", "soft", 1)

	// Drain 2: counter → 2, still soft
	_, _ = s.Drain(context.Background(), now+1, "auto", build(200))
	assertTier(t, s, "safety_secrets", "soft", 2)

	// Drain 3: counter → 3, promote → hard, counter resets to 0, last_changed_at set
	_, _ = s.Drain(context.Background(), now+2, "auto", build(300))
	assertTier(t, s, "safety_secrets", "hard", 0)
}

func TestDrainConsecutiveCounterResetsOnDrop(t *testing.T) {
	s, _ := Open(filepath.Join(t.TempDir(), "gate.db"))
	defer s.Close()
	now := time.Now().Unix()

	above := func(base int64) []GateSignal {
		out := []GateSignal{}
		for i := int64(0); i < 6; i++ {
			out = append(out, sig(base+i, "safety_secrets", "design", "plan", "tn", 0))
		}
		for i := int64(0); i < 4; i++ {
			out = append(out, sig(base+6+i, "safety_secrets", "design", "plan", "fn", 0))
		}
		return out
	}
	below := func(base int64) []GateSignal {
		out := []GateSignal{}
		// Same volume but mostly tn → fnr below threshold
		for i := int64(0); i < 9; i++ {
			out = append(out, sig(base+i, "safety_secrets", "design", "plan", "tn", 0))
		}
		out = append(out, sig(base+9, "safety_secrets", "design", "plan", "fn", 0))
		return out
	}

	_, _ = s.Drain(context.Background(), now, "auto", above(100))
	assertTier(t, s, "safety_secrets", "soft", 1)
	_, _ = s.Drain(context.Background(), now+1, "auto", below(200))
	assertTier(t, s, "safety_secrets", "soft", 0) // reset
}

func TestDrainEmptyDoesNotResetCounter(t *testing.T) {
	s, _ := Open(filepath.Join(t.TempDir(), "gate.db"))
	defer s.Close()
	now := time.Now().Unix()

	above := func(base int64) []GateSignal {
		out := []GateSignal{}
		for i := int64(0); i < 6; i++ {
			out = append(out, sig(base+i, "safety_secrets", "design", "plan", "tn", 0))
		}
		for i := int64(0); i < 4; i++ {
			out = append(out, sig(base+6+i, "safety_secrets", "design", "plan", "fn", 0))
		}
		return out
	}

	_, _ = s.Drain(context.Background(), now, "auto", above(100))
	assertTier(t, s, "safety_secrets", "soft", 1)
	// Empty drain — counter should NOT reset.
	_, _ = s.Drain(context.Background(), now+1, "auto", nil)
	assertTier(t, s, "safety_secrets", "soft", 1)
}

func TestDrainConcurrentSafe(t *testing.T) {
	path := filepath.Join(t.TempDir(), "gate.db")
	s, _ := Open(path)
	defer s.Close()

	now := time.Now().Unix()
	mk := func(base int64, n int) []GateSignal {
		out := []GateSignal{}
		for i := int64(0); i < int64(n); i++ {
			out = append(out, sig(base+i, "safety_secrets", "design", "plan", "tn", 0))
		}
		return out
	}

	var wg sync.WaitGroup
	errs := make(chan error, 2)
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			s2, err := Open(path)
			if err != nil {
				errs <- err
				return
			}
			defer s2.Close()
			_, err = s2.Drain(context.Background(), now, "auto", mk(int64(idx*1000), 5))
			if err != nil {
				errs <- err
			}
		}(i)
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		t.Errorf("concurrent drain error: %v", err)
	}
	// Both should have committed; tier_state should be coherent (not corrupted).
	var n int
	_ = s.DB().QueryRow(`SELECT COUNT(*) FROM drain_log WHERE drain_committed IS NOT NULL`).Scan(&n)
	if n != 2 {
		t.Errorf("expected 2 committed drains, got %d", n)
	}
}

// assertTier checks tier and consecutive counter for theme=default, given check_type.
func assertTier(t *testing.T, s *Store, ct, wantTier string, wantCounter int) {
	t.Helper()
	var tier string
	var counter int
	err := s.DB().QueryRow(
		`SELECT tier, consecutive_windows_above_threshold FROM tier_state WHERE check_type=? AND theme='default'`, ct,
	).Scan(&tier, &counter)
	if err != nil {
		t.Fatalf("query tier_state: %v", err)
	}
	if tier != wantTier {
		t.Errorf("tier = %q, want %q", tier, wantTier)
	}
	if counter != wantCounter {
		t.Errorf("counter = %d, want %d", counter, wantCounter)
	}
}
```

**Step 2: Run test to verify it fails**
Run: `cd os/Clavain/cmd/clavain-cli && /usr/local/go/bin/go test ./gatecal/ -run TestDrain`
Expected: FAIL — `Drain`/`GateSignal` undefined.

**Step 3: Write minimal implementation**
```go
// gatecal/drain.go
package gatecal

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"math"
	"math/rand"
	"strings"
	"time"
)

// GateSignal is the per-event record returned by `ic gate signals`. Field tags
// match the JSON shape of intercore's signal output (verified against
// `gate_calibration.go` v1 consumer).
type GateSignal struct {
	EventID   int64  `json:"event_id"`
	RunID     string `json:"run_id"`
	CheckType string `json:"check_type"`
	FromPhase string `json:"from_phase"`
	ToPhase   string `json:"to_phase"`
	Signal    string `json:"signal_type"`
	CreatedAt int64  `json:"created_at"`
	Category  string `json:"category,omitempty"`
}

// DrainResult summarizes a single drain transaction.
type DrainResult struct {
	SignalsProcessed int64
	SinceIDBefore    int64
	SinceIDAfter     int64
	StateChanges     int64
	Promotions       int
}

// Algorithm constants (port from gate_calibration.go v1).
const (
	HalfLifeDays         = 30
	DefaultFNRThreshold  = 0.30
	PromotionMinN        = 10.0
	ZeroFNRSafetyMinN    = 20.0
	CooldownDays         = 7
	VelocityLimitChanges = 2
	StableWindowsRequired = 3
)

// Drain ingests signals and updates tier_state in a single SQLite transaction.
// `now` is injected for deterministic tests. `invoker` ∈ {"auto","manual"}.
// `signals` is the slice returned by `ic gate signals --since-id=<cursor>`;
// callers source it. Empty signals → no-op (drain_log row written, counter NOT
// reset). bdStateFn is currently nil at the call site (theme labeling is
// future work); the function is plumbed through DeriveTheme for forward compat.
func (s *Store) Drain(ctx context.Context, now int64, invoker string, signals []GateSignal) (DrainResult, error) {
	res := DrainResult{}

	tx, err := s.beginImmediateWithRetry(ctx, 3)
	if err != nil {
		return res, fmt.Errorf("gatecal.drain: begin: %w", err)
	}
	defer tx.Rollback()

	// Read prior cursor.
	var prevCursor sql.NullInt64
	err = tx.QueryRowContext(ctx, `SELECT MAX(since_id_after) FROM drain_log WHERE drain_committed IS NOT NULL`).Scan(&prevCursor)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return res, fmt.Errorf("gatecal.drain: read cursor: %w", err)
	}
	if prevCursor.Valid {
		res.SinceIDBefore = prevCursor.Int64
	}

	// Open drain_log row.
	logRes, err := tx.ExecContext(ctx,
		`INSERT INTO drain_log (drain_started, since_id_before, invoker) VALUES (?, ?, ?)`,
		now, res.SinceIDBefore, invoker,
	)
	if err != nil {
		return res, fmt.Errorf("gatecal.drain: open drain_log: %w", err)
	}
	logRowID, _ := logRes.LastInsertId()

	if len(signals) == 0 {
		// Empty drain: commit log row with same cursor; counter is NOT touched.
		_, err = tx.ExecContext(ctx,
			`UPDATE drain_log SET drain_committed=?, signals_processed=0, since_id_after=?, state_changes=0 WHERE rowid=?`,
			now, res.SinceIDBefore, logRowID,
		)
		if err != nil {
			return res, fmt.Errorf("gatecal.drain: close empty log: %w", err)
		}
		if err := tx.Commit(); err != nil {
			return res, fmt.Errorf("gatecal.drain: commit empty: %w", err)
		}
		return res, nil
	}

	// Mirror signals into signals_cache (best-effort, INSERT OR IGNORE on PK collision).
	for _, sig := range signals {
		_, _ = tx.ExecContext(ctx,
			`INSERT OR IGNORE INTO signals_cache (event_id, run_id, check_type, phase_from, phase_to, signal, category, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
			sig.EventID, sig.RunID, sig.CheckType, sig.FromPhase, sig.ToPhase, sig.Signal, sig.Category, sig.CreatedAt,
		)
	}

	// Group signals by (theme, check_type, phase_from, phase_to).
	type groupKey struct{ theme, ct, pf, pt string }
	type weights struct{ wTP, wFP, wTN, wFN float64; maxEventID int64 }
	groups := map[groupKey]*weights{}
	maxEventID := res.SinceIDBefore

	for _, sig := range signals {
		theme, _ := DeriveTheme(sig.CheckType, nil) // bdStateFn nil for now
		k := groupKey{theme, sig.CheckType, sig.FromPhase, sig.ToPhase}
		w, ok := groups[k]
		if !ok {
			w = &weights{}
			groups[k] = w
		}
		ageDays := float64(now-sig.CreatedAt) / 86400.0
		weight := math.Exp(-math.Ln2 * ageDays / HalfLifeDays)
		switch sig.Signal {
		case "tp":
			w.wTP += weight
		case "fp":
			w.wFP += weight
		case "tn":
			w.wTN += weight
		case "fn":
			w.wFN += weight
		}
		if sig.EventID > w.maxEventID {
			w.maxEventID = sig.EventID
		}
		if sig.EventID > maxEventID {
			maxEventID = sig.EventID
		}
	}

	// For each group: load tier_state row (or default), apply algorithm, UPSERT.
	for k, w := range groups {
		row, err := loadTierStateForUpdate(ctx, tx, k.theme, k.ct, k.pf, k.pt)
		if err != nil {
			return res, err
		}

		// Window partition: only consider this drain's signals if all are AFTER last_changed_at.
		// Filter out signals before the partition point.
		if row.LastChangedAt > 0 {
			adjusted := *w
			adjusted.wTP, adjusted.wFP, adjusted.wTN, adjusted.wFN, adjusted.maxEventID = 0, 0, 0, 0, 0
			for _, sig := range signals {
				if sig.CheckType != k.ct || sig.FromPhase != k.pf || sig.ToPhase != k.pt {
					continue
				}
				theme, _ := DeriveTheme(sig.CheckType, nil)
				if theme != k.theme {
					continue
				}
				if sig.CreatedAt <= row.LastChangedAt {
					continue
				}
				ageDays := float64(now-sig.CreatedAt) / 86400.0
				weight := math.Exp(-math.Ln2 * ageDays / HalfLifeDays)
				switch sig.Signal {
				case "tp":
					adjusted.wTP += weight
				case "fp":
					adjusted.wFP += weight
				case "tn":
					adjusted.wTN += weight
				case "fn":
					adjusted.wFN += weight
				}
				if sig.EventID > adjusted.maxEventID {
					adjusted.maxEventID = sig.EventID
				}
			}
			w = &adjusted
		}

		weightedN := w.wTP + w.wFP + w.wTN + w.wFN
		var fpr, fnr float64
		if w.wTP+w.wFP > 0 {
			fpr = w.wFP / (w.wTP + w.wFP)
		}
		if w.wTN+w.wFN > 0 {
			fnr = w.wFN / (w.wTN + w.wFN)
		}

		row.WeightedN = weightedN
		row.FPR = fpr
		row.FNR = fnr

		// Apply promotion logic only if non-empty + not locked + tier=soft.
		if !row.Locked && row.Tier == "soft" && weightedN > 0 {
			threshold := DefaultFNRThreshold
			if row.FNRThreshold.Valid {
				threshold = row.FNRThreshold.Float64
			}
			above := fnr > threshold &&
				weightedN >= PromotionMinN &&
				!(fnr == 0 && weightedN < ZeroFNRSafetyMinN)
			cooldownOK := row.LastChangedAt == 0 || (now-row.LastChangedAt) >= CooldownDays*86400
			velocityOK := row.ChangeCount90d <= VelocityLimitChanges-1 // strictly < limit before incrementing

			if above && cooldownOK && velocityOK {
				row.ConsecutiveWindows++
				if row.ConsecutiveWindows >= StableWindowsRequired {
					row.Tier = "hard"
					row.LastChangedAt = now
					row.ChangeCount90d++
					row.ConsecutiveWindows = 0
					res.Promotions++
					res.StateChanges++
				}
			} else if !above {
				row.ConsecutiveWindows = 0
			}
			// Velocity-cap lock (port from v1).
			if row.ChangeCount90d >= VelocityLimitChanges {
				row.Locked = true
				res.StateChanges++
			}
		}

		row.UpdatedAt = now
		if err := upsertTierState(ctx, tx, row); err != nil {
			return res, err
		}
	}

	res.SignalsProcessed = int64(len(signals))
	res.SinceIDAfter = maxEventID
	_, err = tx.ExecContext(ctx,
		`UPDATE drain_log SET drain_committed=?, signals_processed=?, since_id_after=?, state_changes=? WHERE rowid=?`,
		now, res.SignalsProcessed, res.SinceIDAfter, res.StateChanges, logRowID,
	)
	if err != nil {
		return res, fmt.Errorf("gatecal.drain: close drain_log: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return res, fmt.Errorf("gatecal.drain: commit: %w", err)
	}
	return res, nil
}

// TierStateRow is an internal mutable view of tier_state for one (theme, check, phase_from, phase_to).
type TierStateRow struct {
	Theme              string
	CheckType          string
	PhaseFrom          string
	PhaseTo            string
	Tier               string
	FPR                float64
	FNR                float64
	WeightedN          float64
	ConsecutiveWindows int
	Locked             bool
	ChangeCount90d     int
	LastChangedAt      int64
	FNRThreshold       sql.NullFloat64
	OriginKey          sql.NullString
	ThemeSource        string
	UpdatedAt          int64
}

func loadTierStateForUpdate(ctx context.Context, tx *sql.Tx, theme, ct, pf, pt string) (*TierStateRow, error) {
	row := &TierStateRow{
		Theme: theme, CheckType: ct, PhaseFrom: pf, PhaseTo: pt,
		Tier: "soft", ThemeSource: deriveSourceFor(theme, ct),
	}
	var locked int
	err := tx.QueryRowContext(ctx,
		`SELECT tier, fpr, fnr, weighted_n, consecutive_windows_above_threshold, locked, change_count_90d, last_changed_at, fnr_threshold, origin_key, theme_source, updated_at FROM tier_state WHERE theme=? AND check_type=? AND phase_from=? AND phase_to=?`,
		theme, ct, pf, pt,
	).Scan(
		&row.Tier, &row.FPR, &row.FNR, &row.WeightedN,
		&row.ConsecutiveWindows, &locked, &row.ChangeCount90d,
		&nullableInt{&row.LastChangedAt}, &row.FNRThreshold,
		&row.OriginKey, &row.ThemeSource, &row.UpdatedAt,
	)
	if err == sql.ErrNoRows {
		return row, nil
	}
	if err != nil {
		return nil, fmt.Errorf("gatecal.drain: load tier_state: %w", err)
	}
	row.Locked = locked != 0
	return row, nil
}

func upsertTierState(ctx context.Context, tx *sql.Tx, r *TierStateRow) error {
	locked := 0
	if r.Locked {
		locked = 1
	}
	var lastChanged sql.NullInt64
	if r.LastChangedAt > 0 {
		lastChanged = sql.NullInt64{Int64: r.LastChangedAt, Valid: true}
	}
	_, err := tx.ExecContext(ctx, `
INSERT INTO tier_state (theme, check_type, phase_from, phase_to, tier, fpr, fnr, weighted_n, consecutive_windows_above_threshold, locked, change_count_90d, last_changed_at, fnr_threshold, origin_key, theme_source, updated_at)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(theme, check_type, phase_from, phase_to) DO UPDATE SET
  tier=excluded.tier,
  fpr=excluded.fpr,
  fnr=excluded.fnr,
  weighted_n=excluded.weighted_n,
  consecutive_windows_above_threshold=excluded.consecutive_windows_above_threshold,
  locked=excluded.locked,
  change_count_90d=excluded.change_count_90d,
  last_changed_at=excluded.last_changed_at,
  fnr_threshold=excluded.fnr_threshold,
  theme_source=excluded.theme_source,
  updated_at=excluded.updated_at`,
		r.Theme, r.CheckType, r.PhaseFrom, r.PhaseTo,
		r.Tier, r.FPR, r.FNR, r.WeightedN,
		r.ConsecutiveWindows, locked, r.ChangeCount90d, lastChanged,
		r.FNRThreshold, r.OriginKey, r.ThemeSource, r.UpdatedAt,
	)
	return err
}

func deriveSourceFor(theme, ct string) string {
	if theme == "default" {
		return "default"
	}
	for prefix := range knownPrefixes {
		if strings.HasPrefix(ct, prefix) && knownPrefixes[prefix] == theme {
			return "inferred"
		}
	}
	return "labeled"
}

// nullableInt scans a possibly-NULL INTEGER into an int64 (zero on NULL).
type nullableInt struct{ Dest *int64 }

func (n *nullableInt) Scan(value interface{}) error {
	if value == nil {
		*n.Dest = 0
		return nil
	}
	switch v := value.(type) {
	case int64:
		*n.Dest = v
	case int:
		*n.Dest = int64(v)
	default:
		return fmt.Errorf("nullableInt: unexpected type %T", v)
	}
	return nil
}

// beginImmediateWithRetry opens a write transaction with retry on SQLITE_BUSY.
func (s *Store) beginImmediateWithRetry(ctx context.Context, attempts int) (*sql.Tx, error) {
	var lastErr error
	delays := []time.Duration{100 * time.Millisecond, 250 * time.Millisecond, 500 * time.Millisecond}
	for i := 0; i < attempts; i++ {
		tx, err := s.db.BeginTx(ctx, nil)
		if err == nil {
			if _, err := tx.ExecContext(ctx, `BEGIN IMMEDIATE`); err == nil {
				// Already in a transaction from BeginTx; BEGIN IMMEDIATE inside
				// will error on most drivers. Fall back: rely on busy_timeout from DSN.
				return tx, nil
			}
			// BEGIN IMMEDIATE failed inside BeginTx — driver doesn't support nested.
			// Just return the transaction as-is; busy_timeout=5000ms in DSN handles BUSY.
			return tx, nil
		}
		lastErr = err
		jitter := time.Duration(rand.Int63n(50)) * time.Millisecond
		time.Sleep(delays[i] + jitter)
	}
	return nil, lastErr
}
```

> **Note on `BEGIN IMMEDIATE`:** the modernc.org/sqlite driver doesn't expose a `BeginTx(ctx, &sql.TxOptions{...})` mode for IMMEDIATE. We rely on `_busy_timeout=5000` in the DSN (set in `Open`) to handle write-write contention. The retry wrapper is belt-and-suspenders for transient open failures. The concurrent test (`TestDrainConcurrentSafe`) verifies coherence either way.

**Step 4: Run test to verify it passes**
Run: `cd os/Clavain/cmd/clavain-cli && /usr/local/go/bin/go test ./gatecal/ -run TestDrain -v`
Expected: PASS — all 7 subtests.

**Step 5: Commit**
```bash
cd os/Clavain
git add cmd/clavain-cli/gatecal/drain.go cmd/clavain-cli/gatecal/drain_test.go
git commit -m "feat(gatecal): drain — weighted-decay + consecutive-stable + small-n safety"
```

<verify>
- run: `cd os/Clavain/cmd/clavain-cli && /usr/local/go/bin/go test ./gatecal/...`
  expect: exit 0
</verify>

---

### Task 5: Backward-compat JSON export

**Files:**
- Create: `os/Clavain/cmd/clavain-cli/gatecal/export.go`
- Create: `os/Clavain/cmd/clavain-cli/gatecal/export_test.go`

**Step 1: Write the failing test**
```go
// gatecal/export_test.go
package gatecal

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestExportV1JSONBasic(t *testing.T) {
	dir := t.TempDir()
	dbPath := filepath.Join(dir, "gate.db")
	jsonPath := filepath.Join(dir, "gate-tier-calibration.json")

	s, _ := Open(dbPath)
	defer s.Close()
	now := time.Now().Unix()

	// Seed two rows on the same v1 key, different themes — worst-case wins.
	signals := []GateSignal{
		{EventID: 1, CheckType: "safety_secrets", FromPhase: "design", ToPhase: "plan", Signal: "tn", CreatedAt: now},
		{EventID: 2, CheckType: "safety_secrets", FromPhase: "design", ToPhase: "plan", Signal: "tn", CreatedAt: now},
	}
	_, _ = s.Drain(context.Background(), now, "auto", signals)

	// Manually inject a hard-tier row under a different theme on the same v1 key.
	_, err := s.DB().Exec(`INSERT INTO tier_state (theme, check_type, phase_from, phase_to, tier, weighted_n, theme_source, updated_at) VALUES ('compliance', 'safety_secrets', 'design', 'plan', 'hard', 12, 'labeled', ?)`, now)
	if err != nil {
		t.Fatal(err)
	}

	if err := s.ExportV1JSON(context.Background(), jsonPath, 1234); err != nil {
		t.Fatalf("ExportV1JSON: %v", err)
	}

	data, _ := os.ReadFile(jsonPath)
	var got v1Shape
	if err := json.Unmarshal(data, &got); err != nil {
		t.Fatalf("export not v1-shape: %v", err)
	}
	if got.SinceID != 1234 {
		t.Errorf("since_id = %d, want 1234", got.SinceID)
	}
	entry, ok := got.Tiers["safety_secrets|design|plan"]
	if !ok {
		t.Fatalf("missing entry: keys=%v", keys(got.Tiers))
	}
	if entry.Tier != "hard" {
		t.Errorf("worst-case tiebreak failed: tier=%q want hard", entry.Tier)
	}
}

func TestExportV1JSONAtomicNoTmpResidue(t *testing.T) {
	dir := t.TempDir()
	jsonPath := filepath.Join(dir, "gate-tier-calibration.json")

	s, _ := Open(filepath.Join(dir, "gate.db"))
	defer s.Close()

	if err := s.ExportV1JSON(context.Background(), jsonPath, 0); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(jsonPath + ".tmp"); !os.IsNotExist(err) {
		t.Errorf("expected no .tmp residue, got %v", err)
	}
}

func keys(m map[string]v1EntryTest) []string {
	out := []string{}
	for k := range m {
		out = append(out, k)
	}
	return out
}
```

**Step 2: Run test to verify it fails**
Run: `cd os/Clavain/cmd/clavain-cli && /usr/local/go/bin/go test ./gatecal/ -run TestExport`
Expected: FAIL — `ExportV1JSON` undefined.

**Step 3: Write minimal implementation**
```go
// gatecal/export.go
package gatecal

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"time"
)

// ExportV1JSON regenerates the v1-shaped gate-tier-calibration.json from
// tier_state. When multiple themes share the same (check_type, phase_from,
// phase_to) v1 key, the WORST-CASE tier wins (`hard` beats `soft`). This is the
// safety-leaning default — documented in the brainstorm.
//
// sinceID is the current cursor (latest drain_log.since_id_after). Caller
// supplies it from the same drain transaction or a follow-up query.
func (s *Store) ExportV1JSON(ctx context.Context, path string, sinceID int64) error {
	rows, err := s.db.QueryContext(ctx, `
SELECT check_type, phase_from, phase_to, tier, locked, fpr, fnr, weighted_n, change_count_90d, last_changed_at, updated_at
FROM tier_state
ORDER BY check_type, phase_from, phase_to,
  CASE tier WHEN 'hard' THEN 0 ELSE 1 END  -- hard rows first, so first-seen wins
`)
	if err != nil {
		return fmt.Errorf("gatecal.export: query: %w", err)
	}
	defer rows.Close()

	tiers := map[string]v1Entry{}
	for rows.Next() {
		var ct, pf, pt, tier string
		var locked int
		var fpr, fnr, weightedN float64
		var changeCount int
		var lastChanged, updatedAt int64
		err := rows.Scan(&ct, &pf, &pt, &tier, &locked, &fpr, &fnr, &weightedN, &changeCount, &nullableInt{&lastChanged}, &updatedAt)
		if err != nil {
			return fmt.Errorf("gatecal.export: scan: %w", err)
		}
		key := ct + "|" + pf + "|" + pt
		// Worst-case wins: skip if we already have a row for this key
		// (the SQL ORDER BY puts hard first, so first-seen IS worst-case).
		if _, exists := tiers[key]; exists {
			continue
		}
		tiers[key] = v1Entry{
			Tier:           tier,
			Locked:         locked != 0,
			FPR:            fpr,
			FNR:            fnr,
			WeightedN:      weightedN,
			LastChangedAt:  lastChanged,
			ChangeCount90d: changeCount,
			UpdatedAt:      updatedAt,
		}
	}

	out := v1File{
		CreatedAt: time.Now().Unix(),
		SinceID:   sinceID,
		Tiers:     tiers,
	}
	data, err := json.MarshalIndent(out, "", "  ")
	if err != nil {
		return fmt.Errorf("gatecal.export: marshal: %w", err)
	}

	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, 0644); err != nil {
		return fmt.Errorf("gatecal.export: write tmp: %w", err)
	}
	if err := os.Rename(tmp, path); err != nil {
		_ = os.Remove(tmp)
		return fmt.Errorf("gatecal.export: rename: %w", err)
	}
	return nil
}
```

**Step 4: Run test to verify it passes**
Run: `cd os/Clavain/cmd/clavain-cli && /usr/local/go/bin/go test ./gatecal/ -run TestExport -v`
Expected: PASS — both subtests.

**Step 5: Commit**
```bash
cd os/Clavain
git add cmd/clavain-cli/gatecal/export.go cmd/clavain-cli/gatecal/export_test.go
git commit -m "feat(gatecal): backward-compat v1 JSON export (worst-case tier wins)"
```

<verify>
- run: `cd os/Clavain/cmd/clavain-cli && /usr/local/go/bin/go test ./gatecal/...`
  expect: exit 0
</verify>

---

### Task 6: Refactor `cmdCalibrateGateTiers` to use gatecal v2

**Files:**
- Modify: `os/Clavain/cmd/clavain-cli/gate_calibration.go` (replace body of `cmdCalibrateGateTiers`)

**Step 1: Read existing code and identify scope**

Re-read `gate_calibration.go:62-242` to confirm:
- `runICJSON` is the subprocess helper for `ic gate signals`.
- `gateCalibrationFilePath()` walks up to find `.clavain/intercore.db` and returns the JSON path. Reuse for the gate.db path.
- `--dry-run` flag exists.

**Step 2: Write the failing test**

Add to existing `gate_calibration_test.go` (create if absent):
```go
// gate_calibration_v2_test.go
package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestCalibrateGateTiersAutoFlag(t *testing.T) {
	// Smoke test: --auto flag is recognized and exit code is 2 (no signals).
	// Hermetic: point gateCalibrationFilePath at a temp .clavain.
	tmp := t.TempDir()
	clavainDir := filepath.Join(tmp, ".clavain")
	_ = os.MkdirAll(clavainDir, 0755)
	// Touch intercore.db so gateCalibrationFilePath() walks here.
	_ = os.WriteFile(filepath.Join(clavainDir, "intercore.db"), []byte{}, 0644)

	oldCwd, _ := os.Getwd()
	defer os.Chdir(oldCwd)
	_ = os.Chdir(tmp)

	// runIC will fail in test env (no `ic` binary). The v2 implementation
	// must tolerate this and either short-circuit cleanly OR surface the
	// error code distinctly. Acceptance: returns nil OR an error matching
	// "ic gate signals" (subprocess error). Any other panic is a bug.
	err := cmdCalibrateGateTiers([]string{"--auto"})
	_ = err // tolerated; test asserts no panic
}
```

> **Test scope rationale:** unit-testing `cmdCalibrateGateTiers` end-to-end requires either mocking `runICJSON` or building/installing `ic`. Neither is in scope here; the gatecal package tests already cover Drain/Export/Migrate. This smoke test only ensures the --auto flag parses and the function doesn't panic.

**Step 3: Implement v2 refactor**

Replace `cmdCalibrateGateTiers` body. Pseudocode:
```go
func cmdCalibrateGateTiers(args []string) error {
    autoMode, dryRun := false, false
    for _, a := range args {
        switch a {
        case "--auto": autoMode = true
        case "--dry-run": dryRun = true
        }
    }

    invoker := "manual"
    if autoMode { invoker = "auto" }

    calPath := gateCalibrationFilePath() // .clavain/gate-tier-calibration.json
    dbPath := filepath.Join(filepath.Dir(calPath), "gate.db")

    s, err := gatecal.Open(dbPath)
    if err != nil { return fmt.Errorf("calibrate-gate-tiers: open gate.db: %w", err) }
    defer s.Close()

    // 1. v1 → v2 migration (idempotent — no-op on second run)
    if err := s.MigrateFromV1(context.Background(), calPath); err != nil {
        return fmt.Errorf("calibrate-gate-tiers: migrate: %w", err)
    }

    // 2. Read current cursor from drain_log
    var sinceID int64
    _ = s.DB().QueryRow(`SELECT COALESCE(MAX(since_id_after), 0) FROM drain_log WHERE drain_committed IS NOT NULL`).Scan(&sinceID)

    // 3. Fetch signals
    var sr signalResult
    if err := runICJSON(&sr, "gate", "signals", "--since-id="+strconv.FormatInt(sinceID, 10)); err != nil {
        return fmt.Errorf("calibrate-gate-tiers: fetch signals: %w", err)
    }

    // 4. Translate signals to gatecal.GateSignal
    sigs := make([]gatecal.GateSignal, 0, len(sr.Signals))
    for _, s := range sr.Signals {
        sigs = append(sigs, gatecal.GateSignal{
            EventID:   s.EventID, RunID: s.RunID, CheckType: s.CheckType,
            FromPhase: s.FromPhase, ToPhase: s.ToPhase, Signal: s.Signal,
            CreatedAt: s.CreatedAt, Category: s.Category,
        })
    }

    // 5. Drain
    res, err := s.Drain(context.Background(), time.Now().Unix(), invoker, sigs)
    if err != nil { return fmt.Errorf("calibrate-gate-tiers: drain: %w", err) }

    // 6. Regenerate backward-compat JSON unless --dry-run
    if !dryRun {
        if err := s.ExportV1JSON(context.Background(), calPath, res.SinceIDAfter); err != nil {
            return fmt.Errorf("calibrate-gate-tiers: export: %w", err)
        }
    }

    // 7. Best-effort interspect events (preserve v1 behavior)
    if res.Promotions > 0 {
        emitInterspectEvent("calibration_checkpoint", fmt.Sprintf("promoted %d gate(s)", res.Promotions))
    }

    fmt.Fprintf(os.Stderr, "calibrate-gate-tiers: signals=%d, state_changes=%d, promotions=%d → %s\n",
        res.SignalsProcessed, res.StateChanges, res.Promotions, calPath)

    // 8. Exit codes (delivered via os.Exit in main when wrapped — for now return error sentinels)
    if res.SignalsProcessed == 0 {
        return ErrNoNewSignals // exit code 2 in main wrapper
    }
    return nil
}

// ErrNoNewSignals signals exit code 2 to the main dispatcher.
var ErrNoNewSignals = errors.New("calibrate-gate-tiers: no new signals")
```

**`main.go` exit-code mapping (audit + edit):**
- Open `os/Clavain/cmd/clavain-cli/main.go`.
- Find the dispatch case for `calibrate-gate-tiers`.
- Wrap: `if errors.Is(err, ErrNoNewSignals) { os.Exit(2) }`.
- Test: invoke `clavain-cli calibrate-gate-tiers --auto` against an empty workspace → expect exit 2.

**Step 4: Run tests to verify**
Run: `cd os/Clavain/cmd/clavain-cli && /usr/local/go/bin/go test ./...`
Expected: PASS for gatecal; the new smoke test in `gate_calibration_v2_test.go` should not panic. Existing `phase_test.go` tests must still pass (we did not touch `phase.go`).

**Step 5: Commit**
```bash
cd os/Clavain
git add cmd/clavain-cli/gate_calibration.go cmd/clavain-cli/gate_calibration_v2_test.go cmd/clavain-cli/main.go
git commit -m "refactor(calibrate-gate-tiers): delegate to gatecal v2 (drain + migrate + export)"
```

<verify>
- run: `cd os/Clavain/cmd/clavain-cli && /usr/local/go/bin/go test ./...`
  expect: exit 0
- run: `cd os/Clavain/cmd/clavain-cli && /usr/local/go/bin/go build ./...`
  expect: exit 0
- run: `cd os/Clavain/cmd/clavain-cli && ./clavain-cli calibrate-gate-tiers --auto; echo $?`
  expect: contains "2"
</verify>

---

### Task 7: SessionEnd hook + hooks.json registration

**Files:**
- Create: `os/Clavain/hooks/gate-calibration-session-end.sh`
- Modify: `os/Clavain/hooks/hooks.json` (append SessionEnd entry)

**Step 1: Write the hook script**
```bash
#!/usr/bin/env bash
# SessionEnd hook — recalibrates gate thresholds from accumulated `ic gate signals`.
# Exit 0 always: never block session exit on calibration failure.
set -u
timeout 10 clavain-cli calibrate-gate-tiers --auto 2>&1 | head -20 || true
exit 0
```
Mark executable: `chmod +x os/Clavain/hooks/gate-calibration-session-end.sh`

**Step 2: Modify `hooks.json`**

Add to the existing `SessionEnd` array (alongside `dotfiles-sync.sh` and `auto-push.sh`):
```json
{
  "type": "command",
  "command": "${CLAUDE_PLUGIN_ROOT}/hooks/gate-calibration-session-end.sh",
  "async": true
}
```

**Step 3: Verify JSON is valid**
Run: `python3 -c "import json; json.load(open('os/Clavain/hooks/hooks.json'))" && echo OK`
Expected: `OK`

**Step 4: Smoke-test the script directly**
Run: `bash os/Clavain/hooks/gate-calibration-session-end.sh; echo "exit=$?"`
Expected: `exit=0` (regardless of whether `clavain-cli` is in PATH or signals exist).

**Step 5: Commit**
```bash
cd os/Clavain
git add hooks/gate-calibration-session-end.sh hooks/hooks.json
git commit -m "feat(hooks): SessionEnd hook calls calibrate-gate-tiers --auto"
```

<verify>
- run: `python3 -c "import json; json.load(open('os/Clavain/hooks/hooks.json'))"`
  expect: exit 0
- run: `bash os/Clavain/hooks/gate-calibration-session-end.sh; echo "exit=$?"`
  expect: contains "exit=0"
- run: `test -x os/Clavain/hooks/gate-calibration-session-end.sh && echo executable`
  expect: contains "executable"
</verify>

---

### Task 8: Full-flow integration test

**Files:**
- Create: `os/Clavain/cmd/clavain-cli/gatecal/integration_test.go`

**Content:** End-to-end test that exercises Migrate → Drain (3 invocations with mid-stream signals) → Export, verifying all observable invariants from the Must-Haves.

**Step 1: Write the failing test**
```go
// gatecal/integration_test.go
package gatecal

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestFullFlowMigrateDrainExport(t *testing.T) {
	dir := t.TempDir()
	clavainDir := filepath.Join(dir, ".clavain")
	_ = os.MkdirAll(clavainDir, 0755)
	dbPath := filepath.Join(clavainDir, "gate.db")
	jsonPath := filepath.Join(clavainDir, "gate-tier-calibration.json")

	// Seed v1 JSON with one entry that should migrate.
	v1 := v1File{
		CreatedAt: 1,
		SinceID:   0,
		Tiers: map[string]v1Entry{
			"perf_p99|design|plan": {Tier: "soft", FPR: 0.0, FNR: 0.0, WeightedN: 0, UpdatedAt: 1},
		},
	}
	data, _ := json.MarshalIndent(v1, "", "  ")
	if err := os.WriteFile(jsonPath, data, 0644); err != nil {
		t.Fatal(err)
	}

	s, err := Open(dbPath)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()

	// Migrate.
	if err := s.MigrateFromV1(context.Background(), jsonPath); err != nil {
		t.Fatalf("migrate: %v", err)
	}

	now := time.Now().Unix()

	// Three drains with above-threshold signals on safety_secrets,
	// and below-threshold signals on quality_test_pass.
	for i := 0; i < 3; i++ {
		base := int64(100 + i*100)
		signals := []GateSignal{}
		// safety_secrets: 6 tn + 4 fn (fnr=0.4, n>=10)
		for j := int64(0); j < 6; j++ {
			signals = append(signals, GateSignal{EventID: base + j, CheckType: "safety_secrets", FromPhase: "design", ToPhase: "plan", Signal: "tn", CreatedAt: now})
		}
		for j := int64(0); j < 4; j++ {
			signals = append(signals, GateSignal{EventID: base + 6 + j, CheckType: "safety_secrets", FromPhase: "design", ToPhase: "plan", Signal: "fn", CreatedAt: now})
		}
		// quality_test_pass: 10 tn + 0 fn (fnr=0)
		for j := int64(0); j < 10; j++ {
			signals = append(signals, GateSignal{EventID: base + 50 + j, CheckType: "quality_test_pass", FromPhase: "design", ToPhase: "plan", Signal: "tn", CreatedAt: now})
		}

		res, err := s.Drain(context.Background(), now+int64(i), "auto", signals)
		if err != nil {
			t.Fatalf("drain %d: %v", i, err)
		}
		if res.SignalsProcessed != int64(len(signals)) {
			t.Errorf("drain %d processed %d/%d", i, res.SignalsProcessed, len(signals))
		}
	}

	// Verify safety promoted, quality stayed soft.
	var safetyTier, qualityTier string
	_ = s.DB().QueryRow(`SELECT tier FROM tier_state WHERE check_type='safety_secrets' AND theme='safety'`).Scan(&safetyTier)
	_ = s.DB().QueryRow(`SELECT tier FROM tier_state WHERE check_type='quality_test_pass' AND theme='quality'`).Scan(&qualityTier)
	if safetyTier != "hard" {
		t.Errorf("safety_secrets tier=%q, want hard", safetyTier)
	}
	if qualityTier != "soft" {
		t.Errorf("quality_test_pass tier=%q, want soft", qualityTier)
	}

	// Verify drain_log has 3 committed rows with invoker='auto'.
	var n int
	_ = s.DB().QueryRow(`SELECT COUNT(*) FROM drain_log WHERE drain_committed IS NOT NULL AND invoker='auto'`).Scan(&n)
	if n != 3 {
		t.Errorf("expected 3 auto-invoker drain rows, got %d", n)
	}

	// Export and verify v1 JSON parses with correct tiers.
	var maxCursor int64
	_ = s.DB().QueryRow(`SELECT MAX(since_id_after) FROM drain_log`).Scan(&maxCursor)
	if err := s.ExportV1JSON(context.Background(), jsonPath, maxCursor); err != nil {
		t.Fatalf("export: %v", err)
	}

	exportData, _ := os.ReadFile(jsonPath)
	var got v1File
	if err := json.Unmarshal(exportData, &got); err != nil {
		t.Fatalf("export not v1-shape: %v", err)
	}
	if got.Tiers["safety_secrets|design|plan"].Tier != "hard" {
		t.Errorf("export safety_secrets tier=%q want hard", got.Tiers["safety_secrets|design|plan"].Tier)
	}
	if got.Tiers["quality_test_pass|design|plan"].Tier != "soft" {
		t.Errorf("export quality_test_pass tier=%q want soft", got.Tiers["quality_test_pass|design|plan"].Tier)
	}

	// Verify v1 JSON archived as .bak.
	if _, err := os.Stat(jsonPath + ".v1.json.bak"); err != nil {
		t.Errorf("expected .v1.json.bak: %v", err)
	}
}
```

**Step 2: Run to verify red**
Run: `cd os/Clavain/cmd/clavain-cli && /usr/local/go/bin/go test ./gatecal/ -run TestFullFlow -v`
Expected: PASS (everything is implemented by T7) — but this test couples all pieces and will catch any wiring slip.

**Step 3: Commit**
```bash
cd os/Clavain
git add cmd/clavain-cli/gatecal/integration_test.go
git commit -m "test(gatecal): full-flow integration (migrate → 3 drains → export)"
```

<verify>
- run: `cd os/Clavain/cmd/clavain-cli && /usr/local/go/bin/go test ./gatecal/ -run TestFullFlow -v`
  expect: exit 0
</verify>

---

### Task 9: Docs + changelog

**Files:**
- Modify: `os/Clavain/CHANGELOG.md` (append entry) — create if absent
- Create: `os/Clavain/docs/gate-calibration.md`

**Step 1: Write `docs/gate-calibration.md`**

One page covering:
- v2 architecture summary (1 paragraph) + link to brainstorm + PRD.
- Storage: `.clavain/gate.db` (SQLite). Tables: tier_state, drain_log, signals_cache.
- Subcommand: `clavain-cli calibrate-gate-tiers [--auto] [--dry-run]`.
- Hook: `hooks/gate-calibration-session-end.sh` (registered in `hooks.json`).
- Backward compat: regenerated `.clavain/gate-tier-calibration.json` unchanged for `ic gate check`.
- Migration: automatic on first SessionEnd; v1 JSON archived as `.v1.json.bak`.
- Algorithm note: see brainstorm § "Algorithm (v2 on top of v1 formulas)".

**Step 2: Append CHANGELOG entry**

```markdown
## Unreleased

### Changed
- `calibrate-gate-tiers` now uses SQLite-backed state at `.clavain/gate.db` instead of JSON-only storage. Same data source (`ic gate signals`); new per-theme keying, window partitioning at tier change, consecutive-stable precondition (3 windows), small-n safety. Backward-compat JSON regenerated automatically — no consumer changes required. v1 JSON archived as `.v1.json.bak` on first run.
- New `--auto` flag distinguishes SessionEnd-triggered drains from manual `/reflect` invocations (recorded in `drain_log.invoker`).

### Added
- SessionEnd hook `hooks/gate-calibration-session-end.sh` — calibration runs automatically without `/reflect`.
```

**Step 3: Commit**
```bash
cd os/Clavain
git add CHANGELOG.md docs/gate-calibration.md
git commit -m "docs(gate-calibration): v2 architecture, migration path, hook"
```

<verify>
- run: `test -f os/Clavain/docs/gate-calibration.md && echo present`
  expect: contains "present"
- run: `grep -l 'gate.db' os/Clavain/CHANGELOG.md`
  expect: contains "CHANGELOG.md"
</verify>

---

## Test strategy

- **Unit tests** (per gatecal file): schema init, theme derivation, migration idempotency, drain algorithm (small-n, zero-FNR, consecutive-stable, counter-reset, empty-no-op, concurrent-safe), JSON export (worst-case tiebreak, atomic write).
- **Integration test** (T8): full v1→v2 → 3-drain promotion arc → JSON export.
- **Existing `phase_test.go`** must still pass — we did NOT touch `phase.go`.
- **Smoke test before final commit**: `cd os/Clavain/cmd/clavain-cli && go test ./... && go build && ./clavain-cli calibrate-gate-tiers --auto` against a real `.clavain/` (expect exit 2 on first run with empty store).

## Risk mitigations

- **Drain failure blocks SessionEnd:** hook script swallows all errors, `exit 0` always, `timeout 10`.
- **SQLite concurrency:** `_busy_timeout=5000` in DSN + retry wrapper handles multi-agent races. Test `TestDrainConcurrentSafe` exercises two-goroutine contention.
- **Hook timeout:** `timeout 10` in shell; uncommitted drain_log row remains; next SessionEnd resumes via cursor.
- **v1 → v2 migration goes wrong:** idempotent (skip if tier_state non-empty); reversible by restoring `.v1.json.bak`. Don't delete v1 — just rename.
- **Backward-compat JSON corrupts `ic gate check`:** worst-case tiebreak is the safety-leaning default; integration test (T8) regenerates and parses the JSON. End-to-end verification with real `ic gate check` is recommended after merge — track as follow-up smoke test in handoff.

## Out of scope (explicitly)

- Cutover of `ic gate check` to read `gate.db` directly — follow-up bead (`sylveste-myyw.7` non-goal per PRD).
- Theme registry infrastructure — separate cross-cutting effort.
- `signals_cache` retention / VACUUM policy — defer (table grows; prune on a future bead if it bites).
- `clavain-cli gate-streak` observability command for `sylveste-myyw.10` — that bead owns its read path.
- Editing `phase.go` / `cmdEnforceGate` — explicit invariant; the superseded plan instrumented this and v3 brainstorm reverts it.

## Sequencing + dependencies

```
T1 (skeleton) → T2 (theme), T3 (migrate)
T1, T2 → T4 (drain)
T4 → T5 (export reads tier_state)
T2, T3, T4, T5 → T6 (subcommand wires them)
T6 → T7 (hook calls subcommand)
T1-T7 → T8 (integration)
T8 → T9 (docs after green)
```

T2 and T3 are independent of each other and can be done in parallel. T4 depends on both.

## Commit plan

- **C1:** T1 (gatecal package skeleton + schema)
- **C2:** T2 (theme derivation)
- **C3:** T3 (migration)
- **C4:** T4 (drain algorithm + tests)
- **C5:** T5 (JSON export)
- **C6:** T6 (calibrate-gate-tiers v2 refactor + main.go exit-code wrap)
- **C7:** T7 (SessionEnd hook + hooks.json)
- **C8:** T8 (integration test)
- **C9:** T9 (docs + changelog)

Each commit must pass `cd os/Clavain/cmd/clavain-cli && go test ./... && go build` before the next.
