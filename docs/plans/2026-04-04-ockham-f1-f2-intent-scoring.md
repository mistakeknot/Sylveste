---
artifact_type: plan
bead: sylveste-0zr
stage: design
requirements:
  - "F1: Intent CLI + YAML schema"
  - "F2: Scoring package + governor assembly"
---
# Ockham F1+F2: Intent CLI + Scoring Package — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Beads:** sylveste-0zr (F1), sylveste-qd1 (F2)
**Goal:** Build the Ockham CLI and Go packages that translate principal intent directives into per-bead dispatch weight offsets.

**Architecture:** Five internal packages (`halt`, `intent`, `authority`, `anomaly`, `scoring`, `governor`) with strict dependency direction — scoring imports `intent`, `authority`, and `anomaly` (stubs in Wave 1); governor imports all five. Stubs live in their destination packages from day one so the dependency graph is correct before Wave 2-3 adds real behavior. CLI layer (`cmd/ockham`) uses cobra for subcommands. Bead-to-theme mapping via `bd show --json` lane labels happens at the CLI boundary, not inside packages.

**Tech Stack:** Go 1.24, cobra (CLI), gopkg.in/yaml.v3 (intent config), standard library for JSON/os/filepath.

**Prior Learnings:**
- `docs/solutions/patterns/2026-03-20-self-dispatch-stop-hook-integration.md` — dispatch-specific scoring belongs in lib-dispatch.sh, not shared scorer. Ockham writes offsets; lib-dispatch.sh reads them. Clean boundary confirmed.
- Lane-pause check at lib-dispatch.sh:189-201 — Ockham's `intent --freeze` delegates to `ic lane update --metadata='{"paused":true}'`, consumed by existing check. No new gate needed in Wave 1.

---

## Must-Haves

**Truths** (observable behaviors):
- Principal can set theme budgets and priorities via `ockham intent` and see them via `ockham intent show`
- `ockham intent validate` rejects invalid configs (budgets don't sum to 1.0, unknown themes in freeze/focus)
- `ockham dispatch advise --json` outputs per-bead weight offsets computed from intent
- When `factory-paused.json` exists, all mutating commands and `governor.Evaluate()` return errors/empty results
- Scoring clamps all offsets to [-6, +6] and never inverts priority tiers

**Artifacts** (files with specific exports):
- [`internal/intent/types.go`] exports `IntentFile`, `ThemeBudget`, `IntentVector`, `Priority`
- [`internal/intent/store.go`] exports `Store` with `Load`, `Save`, `Validate`, `Default`
- [`internal/authority/authority.go`] exports `State` (Wave 1 stub — neutral)
- [`internal/anomaly/anomaly.go`] exports `State` (Wave 1 stub — neutral)
- [`internal/scoring/scorer.go`] exports `Score(IntentVector, authority.State, anomaly.State, []BeadInfo) WeightVector`
- [`internal/governor/governor.go`] exports `Governor` with `Evaluate(ctx, Stores) (WeightVector, error)`
- [`internal/halt/halt.go`] exports `IsHalted() bool`, `SentinelPath() string`

**Key Links** (connections where breakage cascades):
- Governor calls `halt.IsHalted()` before any computation
- Governor calls `intent.Store.Load()` then passes `IntentVector` to `scoring.Score()`
- CLI `dispatch advise` calls `governor.Evaluate()` and formats the `WeightVector` as JSON
- CLI `intent` commands call `halt.IsHalted()` before any write operation

---

### Task 1: Module setup + halt sentinel

**Files:**
- Modify: `os/Ockham/go.mod`
- Create: `os/Ockham/internal/halt/halt.go`
- Create: `os/Ockham/internal/halt/halt_test.go`
- Remove: `os/Ockham/internal/dispatch/` (empty dir, rename to scoring)

**Step 1: Add dependencies**
```bash
cd os/Ockham && go get github.com/spf13/cobra gopkg.in/yaml.v3
```

**Step 2: Remove empty dispatch dir, create scoring dir**
```bash
rmdir os/Ockham/internal/dispatch
mkdir -p os/Ockham/internal/scoring
```

**Step 3: Write halt sentinel test**
```go
// internal/halt/halt_test.go
package halt_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/mistakeknot/Ockham/internal/halt"
)

func TestIsHalted_NoFile(t *testing.T) {
	dir := t.TempDir()
	h := halt.New(filepath.Join(dir, "factory-paused.json"))
	if h.IsHalted() {
		t.Error("expected not halted when file missing")
	}
}

func TestIsHalted_FileExists(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "factory-paused.json")
	if err := os.WriteFile(path, []byte(`{"reason":"test"}`), 0644); err != nil {
		t.Fatal(err)
	}
	h := halt.New(path)
	if !h.IsHalted() {
		t.Error("expected halted when file exists")
	}
}

func TestDefaultSentinelPath(t *testing.T) {
	path := halt.DefaultSentinelPath()
	if filepath.Base(path) != "factory-paused.json" {
		t.Errorf("expected factory-paused.json, got %s", filepath.Base(path))
	}
}
```

**Step 4: Run test to verify it fails**
Run: `cd os/Ockham && go test ./internal/halt/ -v`
Expected: FAIL — package does not exist

**Step 5: Write halt implementation**
```go
// internal/halt/halt.go
package halt

import (
	"os"
	"path/filepath"
)

// Sentinel checks factory halt state via a filesystem sentinel file.
type Sentinel struct {
	path string
}

// New creates a Sentinel checking the given file path.
func New(path string) *Sentinel {
	return &Sentinel{path: path}
}

// DefaultSentinelPath returns ~/.config/ockham/factory-paused.json.
func DefaultSentinelPath() string {
	cfg, err := os.UserConfigDir()
	if err != nil {
		cfg = filepath.Join(os.Getenv("HOME"), ".config")
	}
	return filepath.Join(cfg, "ockham", "factory-paused.json")
}

// IsHalted returns true if the sentinel file exists.
func (s *Sentinel) IsHalted() bool {
	_, err := os.Stat(s.path)
	return err == nil
}

// Path returns the sentinel file path.
func (s *Sentinel) Path() string {
	return s.path
}
```

**Step 6: Run test to verify it passes**
Run: `cd os/Ockham && go test ./internal/halt/ -v`
Expected: PASS

**Step 7: Commit**
```bash
cd os/Ockham && git add -A && git commit -m "feat(ockham): module deps + halt sentinel package"
```

<verify>
- run: `cd os/Ockham && go test ./internal/halt/ -v`
  expect: exit 0
- run: `cd os/Ockham && go vet ./internal/halt/`
  expect: exit 0
</verify>

---

### Task 2: Intent types + YAML schema

**Files:**
- Create: `os/Ockham/internal/intent/types.go`
- Create: `os/Ockham/internal/intent/types_test.go`

**Step 1: Write types test**
```go
// internal/intent/types_test.go
package intent_test

import (
	"testing"

	"github.com/mistakeknot/Ockham/internal/intent"
)

func TestPriorityOffset(t *testing.T) {
	tests := []struct {
		p    intent.Priority
		want int
	}{
		{intent.PriorityHigh, 6},
		{intent.PriorityNormal, 0},
		{intent.PriorityLow, -3},
	}
	for _, tt := range tests {
		if got := tt.p.Offset(); got != tt.want {
			t.Errorf("Priority(%s).Offset() = %d, want %d", tt.p, got, tt.want)
		}
	}
}

func TestPriorityFromString(t *testing.T) {
	tests := []struct {
		s       string
		want    intent.Priority
		wantErr bool
	}{
		{"high", intent.PriorityHigh, false},
		{"normal", intent.PriorityNormal, false},
		{"low", intent.PriorityLow, false},
		{"HIGH", intent.PriorityHigh, false},
		{"invalid", "", true},
	}
	for _, tt := range tests {
		got, err := intent.ParsePriority(tt.s)
		if tt.wantErr && err == nil {
			t.Errorf("ParsePriority(%q) expected error", tt.s)
		}
		if !tt.wantErr && got != tt.want {
			t.Errorf("ParsePriority(%q) = %s, want %s", tt.s, got, tt.want)
		}
	}
}

func TestIntentFileDefault(t *testing.T) {
	f := intent.DefaultFile()
	if len(f.Themes) == 0 {
		t.Error("default should have at least one theme")
	}
	var total float64
	for _, tb := range f.Themes {
		total += tb.Budget
	}
	if total < 0.99 || total > 1.01 {
		t.Errorf("default budgets sum to %f, want 1.0", total)
	}
}
```

**Step 2: Run test to verify it fails**
Run: `cd os/Ockham && go test ./internal/intent/ -v`
Expected: FAIL — types not defined

**Step 3: Write types implementation**
```go
// internal/intent/types.go
package intent

import (
	"fmt"
	"strings"
	"time"
)

// Priority represents a theme's dispatch priority.
type Priority string

const (
	PriorityHigh   Priority = "high"
	PriorityNormal Priority = "normal"
	PriorityLow    Priority = "low"
)

// Offset returns the additive score offset for this priority.
// Asymmetric: high=+6, normal=0, low=-3.
func (p Priority) Offset() int {
	switch p {
	case PriorityHigh:
		return 6
	case PriorityLow:
		return -3
	default:
		return 0
	}
}

func (p Priority) String() string { return string(p) }

// ParsePriority converts a string to Priority, case-insensitive.
func ParsePriority(s string) (Priority, error) {
	switch Priority(strings.ToLower(s)) {
	case PriorityHigh:
		return PriorityHigh, nil
	case PriorityNormal:
		return PriorityNormal, nil
	case PriorityLow:
		return PriorityLow, nil
	default:
		return "", fmt.Errorf("unknown priority %q (valid: high, normal, low)", s)
	}
}

// ThemeBudget is one entry in the intent file.
type ThemeBudget struct {
	Budget   float64  `yaml:"budget"`
	Priority Priority `yaml:"priority"`
}

// Constraints express freeze/focus directives.
type Constraints struct {
	Freeze []string `yaml:"freeze,omitempty"`
	Focus  []string `yaml:"focus,omitempty"`
}

// IntentFile is the on-disk YAML representation.
type IntentFile struct {
	Version     int                    `yaml:"version"`
	Themes      map[string]ThemeBudget `yaml:"themes"`
	Constraints Constraints            `yaml:"constraints"`
	ValidUntil  *time.Time             `yaml:"valid_until,omitempty"`
	UntilBeads  *int                   `yaml:"until_bead_count,omitempty"`
}

// IntentVector is the computed form consumed by the scoring package.
// Maps theme name to its offset.
type IntentVector struct {
	Offsets     map[string]int // theme → priority offset
	Budgets     map[string]float64
	FrozenLanes map[string]bool
}

// DefaultFile returns the hardcoded fallback: single "open" theme, budget 1.0, normal priority.
func DefaultFile() IntentFile {
	return IntentFile{
		Version: 1,
		Themes: map[string]ThemeBudget{
			"open": {Budget: 1.0, Priority: PriorityNormal},
		},
		Constraints: Constraints{},
	}
}

// ToVector computes the IntentVector from a validated IntentFile.
func (f *IntentFile) ToVector() IntentVector {
	v := IntentVector{
		Offsets:     make(map[string]int, len(f.Themes)),
		Budgets:     make(map[string]float64, len(f.Themes)),
		FrozenLanes: make(map[string]bool, len(f.Constraints.Freeze)),
	}
	for name, tb := range f.Themes {
		v.Offsets[name] = tb.Priority.Offset()
		v.Budgets[name] = tb.Budget
	}
	for _, lane := range f.Constraints.Freeze {
		v.FrozenLanes[lane] = true
	}
	return v
}
```

**Step 4: Run test to verify it passes**
Run: `cd os/Ockham && go test ./internal/intent/ -v`
Expected: PASS

**Step 5: Commit**
```bash
cd os/Ockham && git add -A && git commit -m "feat(ockham): intent types, priority offsets, YAML schema"
```

<verify>
- run: `cd os/Ockham && go test ./internal/intent/ -v`
  expect: exit 0
</verify>

---

### Task 3: Intent store (load/save/validate)

**Files:**
- Create: `os/Ockham/internal/intent/store.go`
- Create: `os/Ockham/internal/intent/store_test.go`

**Step 1: Write store tests**
```go
// internal/intent/store_test.go
package intent_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/mistakeknot/Ockham/internal/intent"
)

func TestStore_LoadMissing_ReturnsDefault(t *testing.T) {
	s := intent.NewStore(filepath.Join(t.TempDir(), "intent.yaml"))
	f, err := s.Load()
	if err != nil {
		t.Fatal(err)
	}
	if len(f.Themes) != 1 {
		t.Errorf("expected 1 default theme, got %d", len(f.Themes))
	}
	if _, ok := f.Themes["open"]; !ok {
		t.Error("expected 'open' theme in default")
	}
}

func TestStore_SaveAndLoad_Roundtrip(t *testing.T) {
	path := filepath.Join(t.TempDir(), "intent.yaml")
	s := intent.NewStore(path)
	orig := intent.IntentFile{
		Version: 1,
		Themes: map[string]intent.ThemeBudget{
			"auth": {Budget: 0.6, Priority: intent.PriorityHigh},
			"open": {Budget: 0.4, Priority: intent.PriorityNormal},
		},
	}
	if err := s.Save(orig); err != nil {
		t.Fatal(err)
	}
	loaded, err := s.Load()
	if err != nil {
		t.Fatal(err)
	}
	if loaded.Themes["auth"].Budget != 0.6 {
		t.Errorf("expected auth budget 0.6, got %f", loaded.Themes["auth"].Budget)
	}
}

func TestStore_Save_AtomicReplacement(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "intent.yaml")
	s := intent.NewStore(path)

	f := intent.DefaultFile()
	if err := s.Save(f); err != nil {
		t.Fatal(err)
	}
	// File exists at the expected path (not a temp path)
	if _, err := os.Stat(path); err != nil {
		t.Errorf("expected file at %s after atomic save", path)
	}
}

func TestValidate_BudgetsSumToOne(t *testing.T) {
	f := intent.IntentFile{
		Version: 1,
		Themes: map[string]intent.ThemeBudget{
			"a": {Budget: 0.5, Priority: intent.PriorityNormal},
			"b": {Budget: 0.3, Priority: intent.PriorityNormal},
		},
	}
	if err := intent.Validate(f); err == nil {
		t.Error("expected validation error for budgets summing to 0.8")
	}
}

func TestValidate_NegativeBudget(t *testing.T) {
	f := intent.IntentFile{
		Version: 1,
		Themes: map[string]intent.ThemeBudget{
			"a": {Budget: -0.1, Priority: intent.PriorityNormal},
			"b": {Budget: 1.1, Priority: intent.PriorityNormal},
		},
	}
	err := intent.Validate(f)
	if err == nil {
		t.Error("expected validation error for negative budget")
	}
	if !strings.Contains(err.Error(), "out of range") {
		t.Errorf("expected 'out of range' in error, got: %s", err)
	}
}

func TestValidate_FreezeUnknownTheme(t *testing.T) {
	f := intent.IntentFile{
		Version: 1,
		Themes: map[string]intent.ThemeBudget{
			"auth": {Budget: 1.0, Priority: intent.PriorityNormal},
		},
		Constraints: intent.Constraints{
			Freeze: []string{"typo-theme"},
		},
	}
	if err := intent.Validate(f); err == nil {
		t.Error("expected validation error for unknown freeze theme")
	}
}

func TestValidate_InvalidPriority(t *testing.T) {
	f := intent.IntentFile{
		Version: 1,
		Themes: map[string]intent.ThemeBudget{
			"auth": {Budget: 1.0, Priority: "urgent"},
		},
	}
	err := intent.Validate(f)
	if err == nil {
		t.Error("expected validation error for unrecognized priority")
	}
	if !strings.Contains(err.Error(), "unknown priority") {
		t.Errorf("expected 'unknown priority' in error, got: %s", err)
	}
}

func TestValidate_ValidFile(t *testing.T) {
	f := intent.IntentFile{
		Version: 1,
		Themes: map[string]intent.ThemeBudget{
			"auth": {Budget: 0.4, Priority: intent.PriorityHigh},
			"perf": {Budget: 0.3, Priority: intent.PriorityNormal},
			"open": {Budget: 0.3, Priority: intent.PriorityNormal},
		},
		Constraints: intent.Constraints{
			Freeze: []string{"auth"},
		},
	}
	if err := intent.Validate(f); err != nil {
		t.Errorf("expected no errors, got %v", err)
	}
}

func TestStore_LoadCorrupt_ReturnsDefaultWithError(t *testing.T) {
	path := filepath.Join(t.TempDir(), "intent.yaml")
	if err := os.WriteFile(path, []byte("{{{{not yaml"), 0644); err != nil {
		t.Fatal(err)
	}
	s := intent.NewStore(path)
	f, err := s.Load()
	if err == nil {
		t.Error("expected error for corrupt YAML")
	}
	if _, ok := f.Themes["open"]; !ok {
		t.Error("corrupt file should still return default as fallback")
	}
}
```

**Step 2: Run test to verify it fails**
Run: `cd os/Ockham && go test ./internal/intent/ -v -run 'Store|Validate'`
Expected: FAIL — Store not defined

**Step 3: Write store implementation**
```go
// internal/intent/store.go
package intent

import (
	"errors"
	"fmt"
	"math"
	"os"
	"path/filepath"

	"gopkg.in/yaml.v3"
)

// Store reads and writes intent files with atomic replacement.
type Store struct {
	path string
}

// NewStore creates a Store for the given YAML file path.
func NewStore(path string) *Store {
	return &Store{path: path}
}

// DefaultStorePath returns ~/.config/ockham/intent.yaml.
func DefaultStorePath() string {
	cfg, err := os.UserConfigDir()
	if err != nil {
		cfg = filepath.Join(os.Getenv("HOME"), ".config")
	}
	return filepath.Join(cfg, "ockham", "intent.yaml")
}

// Path returns the store's file path.
func (s *Store) Path() string { return s.path }

// Load reads the intent file. Returns default if missing. Returns error
// (with default as fallback) for I/O errors or corrupt YAML, so callers
// can log/surface the problem.
func (s *Store) Load() (IntentFile, error) {
	data, err := os.ReadFile(s.path)
	if err != nil {
		if os.IsNotExist(err) {
			return DefaultFile(), nil
		}
		return DefaultFile(), fmt.Errorf("reading intent file: %w", err)
	}

	var f IntentFile
	if err := yaml.Unmarshal(data, &f); err != nil {
		return DefaultFile(), fmt.Errorf("parsing intent YAML: %w", err)
	}

	if f.Themes == nil {
		return DefaultFile(), nil
	}

	return f, nil
}

// Save writes the intent file atomically (write temp, rename).
func (s *Store) Save(f IntentFile) error {
	if err := os.MkdirAll(filepath.Dir(s.path), 0755); err != nil {
		return fmt.Errorf("creating config dir: %w", err)
	}

	data, err := yaml.Marshal(f)
	if err != nil {
		return fmt.Errorf("marshaling intent: %w", err)
	}

	tmp := s.path + ".tmp"
	if err := os.WriteFile(tmp, data, 0644); err != nil {
		return fmt.Errorf("writing temp file: %w", err)
	}

	if err := os.Rename(tmp, s.path); err != nil {
		os.Remove(tmp)
		return fmt.Errorf("atomic rename: %w", err)
	}

	return nil
}

// Validate checks an IntentFile for correctness.
// Returns nil if valid, or a combined error via errors.Join.
func Validate(f IntentFile) error {
	var errs []error

	// Priority enum check
	for name, tb := range f.Themes {
		if _, err := ParsePriority(string(tb.Priority)); err != nil {
			errs = append(errs, fmt.Errorf("theme %q: %w", name, err))
		}
	}

	// Budget range check
	for name, tb := range f.Themes {
		if tb.Budget < 0 || tb.Budget > 1.0 {
			errs = append(errs, fmt.Errorf("theme %q: budget %f out of range [0, 1]", name, tb.Budget))
		}
	}

	// Budgets must sum to 1.0 (tolerance: 0.001)
	var total float64
	for _, tb := range f.Themes {
		total += tb.Budget
	}
	if math.Abs(total-1.0) > 0.001 {
		errs = append(errs, fmt.Errorf("budgets sum to %f, must equal 1.0", total))
	}

	// Freeze/focus entries must reference declared themes
	for _, lane := range f.Constraints.Freeze {
		if _, ok := f.Themes[lane]; !ok {
			errs = append(errs, fmt.Errorf("freeze references unknown theme %q", lane))
		}
	}
	for _, lane := range f.Constraints.Focus {
		if _, ok := f.Themes[lane]; !ok {
			errs = append(errs, fmt.Errorf("focus references unknown theme %q", lane))
		}
	}

	return errors.Join(errs...)
}
```

**Step 4: Run test to verify it passes**
Run: `cd os/Ockham && go test ./internal/intent/ -v`
Expected: PASS

**Step 5: Commit**
```bash
cd os/Ockham && git add -A && git commit -m "feat(ockham): intent store with load/save/validate and atomic replacement"
```

<verify>
- run: `cd os/Ockham && go test ./internal/intent/ -v`
  expect: exit 0
- run: `cd os/Ockham && go test ./internal/intent/ -cover`
  expect: contains "coverage:"
</verify>

---

### Task 4: Scoring types + scorer

**Files:**
- Create: `os/Ockham/internal/scoring/types.go`
- Create: `os/Ockham/internal/scoring/scorer.go`
- Create: `os/Ockham/internal/scoring/scorer_test.go`

**Depends on:** Task 2 (uses `intent.IntentVector`)

**Step 1: Write scoring types**
```go
// internal/authority/authority.go
package authority

// State is a Wave 1 stub — returns neutral (no constraints).
// Wave 3 adds: per-domain tier, frozen domains, delegation ceiling.
type State struct{}

// internal/anomaly/anomaly.go
package anomaly

// State is a Wave 1 stub — returns neutral (no signals).
// Wave 2 adds: tier-1 INFORM signals, tier-2 CONSTRAIN.
type State struct{}

// internal/scoring/types.go
package scoring

// BeadInfo carries the data needed to score a single bead.
// Populated by the caller (CLI layer), not by the scoring package.
type BeadInfo struct {
	ID   string
	Lane string // empty → "open" theme
}

// WeightVector maps bead ID → additive offset for dispatch scoring.
type WeightVector struct {
	Offsets map[string]int
}
```

**Step 2: Write scorer tests**
```go
// internal/scoring/scorer_test.go
package scoring_test

import (
	"testing"

	"github.com/mistakeknot/Ockham/internal/anomaly"
	"github.com/mistakeknot/Ockham/internal/authority"
	"github.com/mistakeknot/Ockham/internal/intent"
	"github.com/mistakeknot/Ockham/internal/scoring"
)

func TestScore_HighPriorityTheme(t *testing.T) {
	iv := intent.IntentVector{
		Offsets:     map[string]int{"auth": 6, "open": 0},
		Budgets:     map[string]float64{"auth": 0.6, "open": 0.4},
		FrozenLanes: map[string]bool{},
	}
	beads := []scoring.BeadInfo{
		{ID: "b1", Lane: "auth"},
		{ID: "b2", Lane: "open"},
	}
	wv := scoring.Score(iv, authority.State{}, anomaly.State{}, beads)
	if wv.Offsets["b1"] != 6 {
		t.Errorf("auth bead offset = %d, want 6", wv.Offsets["b1"])
	}
	if wv.Offsets["b2"] != 0 {
		t.Errorf("open bead offset = %d, want 0", wv.Offsets["b2"])
	}
}

func TestScore_LowPriorityTheme(t *testing.T) {
	iv := intent.IntentVector{
		Offsets:     map[string]int{"cleanup": -3},
		Budgets:     map[string]float64{"cleanup": 1.0},
		FrozenLanes: map[string]bool{},
	}
	beads := []scoring.BeadInfo{{ID: "b1", Lane: "cleanup"}}
	wv := scoring.Score(iv, authority.State{}, anomaly.State{}, beads)
	if wv.Offsets["b1"] != -3 {
		t.Errorf("low bead offset = %d, want -3", wv.Offsets["b1"])
	}
}

func TestScore_NoLane_DefaultsToOpen(t *testing.T) {
	iv := intent.IntentVector{
		Offsets:     map[string]int{"open": 0},
		Budgets:     map[string]float64{"open": 1.0},
		FrozenLanes: map[string]bool{},
	}
	beads := []scoring.BeadInfo{{ID: "b1", Lane: ""}}
	wv := scoring.Score(iv, authority.State{}, anomaly.State{}, beads)
	if wv.Offsets["b1"] != 0 {
		t.Errorf("no-lane bead offset = %d, want 0", wv.Offsets["b1"])
	}
}

func TestScore_UnknownTheme_ZeroOffset(t *testing.T) {
	iv := intent.IntentVector{
		Offsets:     map[string]int{"auth": 6},
		Budgets:     map[string]float64{"auth": 1.0},
		FrozenLanes: map[string]bool{},
	}
	beads := []scoring.BeadInfo{{ID: "b1", Lane: "unknown-lane"}}
	wv := scoring.Score(iv, authority.State{}, anomaly.State{}, beads)
	if wv.Offsets["b1"] != 0 {
		t.Errorf("unknown-lane bead offset = %d, want 0", wv.Offsets["b1"])
	}
}

func TestScore_ClampToRange(t *testing.T) {
	// Even if somehow offset exceeds bounds, clamp to [-6, +6]
	iv := intent.IntentVector{
		Offsets:     map[string]int{"x": 100},
		Budgets:     map[string]float64{"x": 1.0},
		FrozenLanes: map[string]bool{},
	}
	beads := []scoring.BeadInfo{{ID: "b1", Lane: "x"}}
	wv := scoring.Score(iv, authority.State{}, anomaly.State{}, beads)
	if wv.Offsets["b1"] > 6 {
		t.Errorf("offset %d exceeds clamp max 6", wv.Offsets["b1"])
	}
}

func TestScore_EmptyBeads(t *testing.T) {
	iv := intent.IntentVector{
		Offsets:     map[string]int{"auth": 6},
		Budgets:     map[string]float64{"auth": 1.0},
		FrozenLanes: map[string]bool{},
	}
	wv := scoring.Score(iv, authority.State{}, anomaly.State{}, nil)
	if len(wv.Offsets) != 0 {
		t.Errorf("expected empty offsets for nil beads, got %d", len(wv.Offsets))
	}
}

func TestScore_MultipleBeadsSameTheme(t *testing.T) {
	iv := intent.IntentVector{
		Offsets:     map[string]int{"auth": 6, "open": 0},
		Budgets:     map[string]float64{"auth": 0.7, "open": 0.3},
		FrozenLanes: map[string]bool{},
	}
	beads := []scoring.BeadInfo{
		{ID: "b1", Lane: "auth"},
		{ID: "b2", Lane: "auth"},
		{ID: "b3", Lane: "open"},
	}
	wv := scoring.Score(iv, authority.State{}, anomaly.State{}, beads)
	if wv.Offsets["b1"] != 6 || wv.Offsets["b2"] != 6 {
		t.Error("all auth beads should get +6")
	}
	if wv.Offsets["b3"] != 0 {
		t.Error("open bead should get 0")
	}
}
```

**Step 3: Run test to verify it fails**
Run: `cd os/Ockham && go test ./internal/scoring/ -v`
Expected: FAIL — Score not defined

**Step 4: Write scorer implementation**
```go
// internal/scoring/scorer.go
package scoring

import (
	"github.com/mistakeknot/Ockham/internal/anomaly"
	"github.com/mistakeknot/Ockham/internal/authority"
	"github.com/mistakeknot/Ockham/internal/intent"
)

const (
	// OffsetMin is the minimum clamped offset.
	OffsetMin = -6
	// OffsetMax is the maximum clamped offset.
	OffsetMax = 6
)

// Score computes per-bead weight offsets from intent, authority, and anomaly state.
// Dependency direction: scoring imports intent, authority, anomaly. Governor imports all.
func Score(iv intent.IntentVector, _ authority.State, _ anomaly.State, beads []BeadInfo) WeightVector {
	wv := WeightVector{Offsets: make(map[string]int, len(beads))}

	for _, b := range beads {
		lane := b.Lane
		if lane == "" {
			lane = "open"
		}

		offset, ok := iv.Offsets[lane]
		if !ok {
			offset = 0 // unknown theme → neutral
		}

		// Clamp to safe range
		wv.Offsets[b.ID] = clamp(offset, OffsetMin, OffsetMax)
	}

	return wv
}

func clamp(v, lo, hi int) int {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}
```

**Step 5: Run test to verify it passes**
Run: `cd os/Ockham && go test ./internal/scoring/ -v`
Expected: PASS

**Step 6: Check coverage**
Run: `cd os/Ockham && go test ./internal/scoring/ -cover`
Expected: coverage >= 80%

**Step 7: Commit**
```bash
cd os/Ockham && git add -A && git commit -m "feat(ockham): scoring package — additive offsets with [-6,+6] clamp"
```

<verify>
- run: `cd os/Ockham && go test ./internal/scoring/ -v`
  expect: exit 0
- run: `cd os/Ockham && go test ./internal/scoring/ -cover`
  expect: contains "100"
</verify>

---

### Task 5: Governor assembly

**Files:**
- Create: `os/Ockham/internal/governor/governor.go`
- Create: `os/Ockham/internal/governor/governor_test.go`

**Depends on:** Task 1 (halt), Task 2+3 (intent), Task 4 (scoring)

**Step 1: Write governor tests**
```go
// internal/governor/governor_test.go
package governor_test

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/mistakeknot/Ockham/internal/governor"
	"github.com/mistakeknot/Ockham/internal/halt"
	"github.com/mistakeknot/Ockham/internal/intent"
	"github.com/mistakeknot/Ockham/internal/scoring"
)

func newTestGovernor(t *testing.T) (*governor.Governor, string) {
	t.Helper()
	dir := t.TempDir()
	intentPath := filepath.Join(dir, "intent.yaml")
	haltPath := filepath.Join(dir, "factory-paused.json")

	is := intent.NewStore(intentPath)
	hs := halt.New(haltPath)

	g := governor.New(is, hs)
	return g, dir
}

func TestEvaluate_BasicScoring(t *testing.T) {
	g, dir := newTestGovernor(t)

	// Write intent file
	is := intent.NewStore(filepath.Join(dir, "intent.yaml"))
	is.Save(intent.IntentFile{
		Version: 1,
		Themes: map[string]intent.ThemeBudget{
			"auth": {Budget: 0.6, Priority: intent.PriorityHigh},
			"open": {Budget: 0.4, Priority: intent.PriorityNormal},
		},
	})

	beads := []scoring.BeadInfo{
		{ID: "b1", Lane: "auth"},
		{ID: "b2", Lane: "open"},
	}

	wv, err := g.Evaluate(context.Background(), beads)
	if err != nil {
		t.Fatal(err)
	}
	if wv.Offsets["b1"] != 6 {
		t.Errorf("auth offset = %d, want 6", wv.Offsets["b1"])
	}
	if wv.Offsets["b2"] != 0 {
		t.Errorf("open offset = %d, want 0", wv.Offsets["b2"])
	}
}

func TestEvaluate_HaltedReturnsEmpty(t *testing.T) {
	g, dir := newTestGovernor(t)

	// Create halt sentinel
	haltPath := filepath.Join(dir, "factory-paused.json")
	if err := os.WriteFile(haltPath, []byte(`{"reason":"test"}`), 0644); err != nil {
		t.Fatal(err)
	}

	beads := []scoring.BeadInfo{{ID: "b1", Lane: "auth"}}

	wv, err := g.Evaluate(context.Background(), beads)
	if err == nil {
		t.Error("expected error when halted")
	}
	if len(wv.Offsets) != 0 {
		t.Errorf("expected empty offsets when halted, got %d", len(wv.Offsets))
	}
}

func TestEvaluate_MissingIntent_UsesDefault(t *testing.T) {
	g, _ := newTestGovernor(t)

	beads := []scoring.BeadInfo{{ID: "b1", Lane: ""}}

	wv, err := g.Evaluate(context.Background(), beads)
	if err != nil {
		t.Fatal(err)
	}
	// Default is single "open" theme with normal priority (offset 0)
	if wv.Offsets["b1"] != 0 {
		t.Errorf("default offset = %d, want 0", wv.Offsets["b1"])
	}
}
```

**Step 2: Run test to verify it fails**
Run: `cd os/Ockham && go test ./internal/governor/ -v`
Expected: FAIL — governor package not defined

**Step 3: Write governor implementation**
```go
// internal/governor/governor.go
package governor

import (
	"context"
	"fmt"

	"github.com/mistakeknot/Ockham/internal/anomaly"
	"github.com/mistakeknot/Ockham/internal/authority"
	"github.com/mistakeknot/Ockham/internal/halt"
	"github.com/mistakeknot/Ockham/internal/intent"
	"github.com/mistakeknot/Ockham/internal/scoring"
)

// Governor assembles subsystem stores and evaluates dispatch weights.
// Dependency direction: governor imports intent, scoring, halt.
// Scoring imports intent only. Halt imports nothing.
type Governor struct {
	intent *intent.Store
	halt   *halt.Sentinel
}

// New creates a Governor with the given stores.
func New(intentStore *intent.Store, haltSentinel *halt.Sentinel) *Governor {
	return &Governor{
		intent: intentStore,
		halt:   haltSentinel,
	}
}

// Evaluate computes per-bead weight offsets.
// Returns ErrHalted if the factory is paused (INV-8).
func (g *Governor) Evaluate(_ context.Context, beads []scoring.BeadInfo) (scoring.WeightVector, error) {
	// INV-8: halt check FIRST
	if g.halt.IsHalted() {
		return scoring.WeightVector{Offsets: map[string]int{}}, fmt.Errorf("factory halted: %s exists", g.halt.Path())
	}

	// Load intent (falls back to default on missing/corrupt)
	intentFile, err := g.intent.Load()
	if err != nil {
		return scoring.WeightVector{Offsets: map[string]int{}}, fmt.Errorf("loading intent: %w", err)
	}

	iv := intentFile.ToVector()

	// Wave 1 stubs: neutral authority and anomaly
	as := authority.State{}
	an := anomaly.State{}

	wv := scoring.Score(iv, as, an, beads)
	return wv, nil
}
```

**Step 4: Run test to verify it passes**
Run: `cd os/Ockham && go test ./internal/governor/ -v`
Expected: PASS

**Step 5: Commit**
```bash
cd os/Ockham && git add -A && git commit -m "feat(ockham): governor assembly — Evaluate() with halt check"
```

<verify>
- run: `cd os/Ockham && go test ./internal/governor/ -v`
  expect: exit 0
- run: `cd os/Ockham && go test ./... -v`
  expect: exit 0
</verify>

---

### Task 6: CLI root + intent subcommands

**Files:**
- Create: `os/Ockham/cmd/ockham/main.go`
- Create: `os/Ockham/cmd/ockham/root.go`
- Create: `os/Ockham/cmd/ockham/intent.go`

**Depends on:** Task 1 (halt), Task 3 (intent store)

**Step 1: Write CLI root**
```go
// cmd/ockham/main.go
package main

import (
	"fmt"
	"os"
)

func main() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
```

```go
// cmd/ockham/root.go
package main

import "github.com/spf13/cobra"

var rootCmd = &cobra.Command{
	Use:   "ockham",
	Short: "Factory governor — translates strategic intent to dispatch weights",
}
```

**Step 2: Write intent subcommand**
```go
// cmd/ockham/intent.go
package main

import (
	"fmt"
	"os"
	"strings"
	"text/tabwriter"

	"github.com/mistakeknot/Ockham/internal/halt"
	"github.com/mistakeknot/Ockham/internal/intent"
	"github.com/spf13/cobra"
)

var (
	intentTheme    string
	intentBudget   float64
	intentPriority string
	intentFreeze   string
)

var intentCmd = &cobra.Command{
	Use:   "intent",
	Short: "Manage theme budgets and priorities",
	RunE:  runIntentSet,
}

var intentShowCmd = &cobra.Command{
	Use:   "show",
	Short: "Display current intent directives",
	RunE:  runIntentShow,
}

var intentValidateCmd = &cobra.Command{
	Use:   "validate",
	Short: "Validate the intent file",
	RunE:  runIntentValidate,
}

func init() {
	intentCmd.Flags().StringVar(&intentTheme, "theme", "", "Theme name")
	intentCmd.Flags().Float64Var(&intentBudget, "budget", -1, "Budget fraction (0-1)")
	intentCmd.Flags().StringVar(&intentPriority, "priority", "normal", "Priority (high|normal|low)")
	intentCmd.Flags().StringVar(&intentFreeze, "freeze", "", "Freeze a theme (add to constraints)")

	intentCmd.AddCommand(intentShowCmd)
	intentCmd.AddCommand(intentValidateCmd)
	rootCmd.AddCommand(intentCmd)
}

func haltGuard() error {
	h := halt.New(halt.DefaultSentinelPath())
	if h.IsHalted() {
		return fmt.Errorf("factory halted: %s exists — run 'ockham resume' first", h.Path())
	}
	return nil
}

func runIntentSet(cmd *cobra.Command, args []string) error {
	if err := haltGuard(); err != nil {
		return err
	}

	store := intent.NewStore(intent.DefaultStorePath())

	// Handle --freeze
	if intentFreeze != "" {
		f, err := store.Load()
		if err != nil {
			return err
		}
		// Add to freeze list if not present
		for _, existing := range f.Constraints.Freeze {
			if existing == intentFreeze {
				fmt.Fprintf(os.Stderr, "theme %q already frozen\n", intentFreeze)
				return nil
			}
		}
		f.Constraints.Freeze = append(f.Constraints.Freeze, intentFreeze)
		if err := intent.Validate(f); err != nil {
			fmt.Fprintln(os.Stderr, err)
			return fmt.Errorf("validation failed")
		}
		if err := store.Save(f); err != nil {
			return err
		}
		fmt.Printf("Frozen theme %q\n", intentFreeze)
		return nil
	}

	// Handle --theme + --budget/--priority
	if intentTheme == "" {
		return cmd.Help()
	}

	f, err := store.Load()
	if err != nil {
		return err
	}

	tb := f.Themes[intentTheme]

	if intentBudget >= 0 {
		tb.Budget = intentBudget
	}

	if cmd.Flags().Changed("priority") {
		p, err := intent.ParsePriority(intentPriority)
		if err != nil {
			return err
		}
		tb.Priority = p
	} else if tb.Priority == "" {
		tb.Priority = intent.PriorityNormal
	}

	if f.Themes == nil {
		f.Themes = make(map[string]intent.ThemeBudget)
	}
	f.Themes[intentTheme] = tb
	f.Version = 1

	if err := store.Save(f); err != nil {
		return err
	}

	fmt.Printf("Updated theme %q: budget=%.2f priority=%s\n", intentTheme, tb.Budget, tb.Priority)
	fmt.Println("Run 'ockham intent validate' to check consistency")
	return nil
}

func runIntentShow(cmd *cobra.Command, args []string) error {
	store := intent.NewStore(intent.DefaultStorePath())
	f, err := store.Load()
	if err != nil {
		return err
	}

	w := tabwriter.NewWriter(os.Stdout, 0, 4, 2, ' ', 0)
	fmt.Fprintln(w, "THEME\tBUDGET\tPRIORITY\tOFFSET")
	fmt.Fprintln(w, "─────\t──────\t────────\t──────")
	for name, tb := range f.Themes {
		fmt.Fprintf(w, "%s\t%.0f%%\t%s\t%+d\n", name, tb.Budget*100, tb.Priority, tb.Priority.Offset())
	}
	w.Flush()

	if len(f.Constraints.Freeze) > 0 {
		fmt.Printf("\nFrozen: %s\n", strings.Join(f.Constraints.Freeze, ", "))
	}
	if len(f.Constraints.Focus) > 0 {
		fmt.Printf("Focus:  %s\n", strings.Join(f.Constraints.Focus, ", "))
	}

	return nil
}

func runIntentValidate(cmd *cobra.Command, args []string) error {
	store := intent.NewStore(intent.DefaultStorePath())
	f, err := store.Load()
	if err != nil {
		return err
	}

	if err := intent.Validate(f); err != nil {
		fmt.Fprintf(os.Stderr, "ERROR: %s\n", err)
		return fmt.Errorf("validation failed")
	}

	fmt.Println("Intent file valid")
	return nil
}
```

**Step 3: Build and verify**
Run: `cd os/Ockham && go build ./cmd/ockham`
Expected: exit 0

**Step 4: Smoke test**
Run: `cd os/Ockham && ./ockham intent show`
Expected: shows default "open" theme table

Run: `cd os/Ockham && ./ockham intent validate`
Expected: "Intent file valid"

**Step 5: Commit**
```bash
cd os/Ockham && git add -A && git commit -m "feat(ockham): CLI root + intent subcommands (show, validate, set, freeze)"
```

<verify>
- run: `cd os/Ockham && go build ./cmd/ockham`
  expect: exit 0
- run: `cd os/Ockham && go vet ./...`
  expect: exit 0
</verify>

---

### Task 7: CLI dispatch advise command

**Files:**
- Create: `os/Ockham/cmd/ockham/dispatch.go`

**Depends on:** Task 5 (governor), Task 6 (CLI root)

**Step 1: Write dispatch advise command**
```go
// cmd/ockham/dispatch.go
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/mistakeknot/Ockham/internal/governor"
	"github.com/mistakeknot/Ockham/internal/halt"
	"github.com/mistakeknot/Ockham/internal/intent"
	"github.com/mistakeknot/Ockham/internal/scoring"
	"github.com/spf13/cobra"
)

var dispatchJSON bool

var dispatchCmd = &cobra.Command{
	Use:   "dispatch",
	Short: "Dispatch weight operations",
}

var dispatchAdviseCmd = &cobra.Command{
	Use:   "advise",
	Short: "Show current weight offsets for all open beads",
	RunE:  runDispatchAdvise,
}

func init() {
	dispatchAdviseCmd.Flags().BoolVar(&dispatchJSON, "json", false, "Output as JSON")
	dispatchCmd.AddCommand(dispatchAdviseCmd)
	rootCmd.AddCommand(dispatchCmd)
}

// beadsFromBD shells out to bd to get open beads with lane labels.
// NOTE: bd list --json label format ("lane:<name>") is undocumented — if
// bd changes this, lane falls through to "open" default silently.
func beadsFromBD() ([]scoring.BeadInfo, error) {
	cmd := exec.Command("bd", "list", "--status=open", "--json")
	out, err := cmd.Output()
	if err != nil {
		// Include stderr in error message for debuggability
		if exitErr, ok := err.(*exec.ExitError); ok {
			return nil, fmt.Errorf("bd list: %w\nstderr: %s", err, exitErr.Stderr)
		}
		return nil, fmt.Errorf("bd list: %w", err)
	}

	var beads []struct {
		ID     string   `json:"id"`
		Labels []string `json:"labels"`
	}
	if err := json.Unmarshal(out, &beads); err != nil {
		return nil, fmt.Errorf("parsing bd output: %w", err)
	}

	infos := make([]scoring.BeadInfo, 0, len(beads))
	for _, b := range beads {
		lane := ""
		for _, label := range b.Labels {
			if strings.HasPrefix(label, "lane:") {
				lane = strings.TrimPrefix(label, "lane:")
				break
			}
		}
		infos = append(infos, scoring.BeadInfo{ID: b.ID, Lane: lane})
	}
	return infos, nil
}

func runDispatchAdvise(cmd *cobra.Command, args []string) error {
	is := intent.NewStore(intent.DefaultStorePath())
	hs := halt.New(halt.DefaultSentinelPath())
	g := governor.New(is, hs)

	beads, err := beadsFromBD()
	if err != nil {
		return err
	}

	wv, err := g.Evaluate(cmd.Context(), beads)
	if err != nil {
		return err
	}

	if dispatchJSON {
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		return enc.Encode(wv.Offsets)
	}

	// Table output
	fmt.Printf("%-30s  %s\n", "BEAD", "OFFSET")
	fmt.Printf("%-30s  %s\n", "─────", "──────")
	for id, offset := range wv.Offsets {
		fmt.Printf("%-30s  %+d\n", id, offset)
	}

	return nil
}
```

**Step 2: Build and verify**
Run: `cd os/Ockham && go build ./cmd/ockham`
Expected: exit 0

**Step 3: Smoke test**
Run: `cd os/Ockham && ./ockham dispatch advise --json`
Expected: JSON output of bead offsets (or error if bd unavailable — acceptable)

**Step 4: Commit**
```bash
cd os/Ockham && git add -A && git commit -m "feat(ockham): dispatch advise command — JSON weight vector output"
```

<verify>
- run: `cd os/Ockham && go build ./cmd/ockham`
  expect: exit 0
- run: `cd os/Ockham && go vet ./...`
  expect: exit 0
</verify>

---

### Task 8: Full test suite + AGENTS.md update

**Files:**
- Modify: `os/Ockham/AGENTS.md`
- Create: `os/Ockham/internal/intent/tostring_test.go` (IntentVector roundtrip)

**Depends on:** Tasks 1-7

**Step 1: Run full test suite with coverage**
Run: `cd os/Ockham && go test ./... -v -cover`
Expected: all pass, scoring coverage >= 80%

**Step 2: Run vet**
Run: `cd os/Ockham && go vet ./...`
Expected: exit 0

**Step 3: Update AGENTS.md**

Update the Package Map table to reflect the rename (`dispatch` → `scoring`) and add `halt` and `governor` packages. Update the CLI section from "planned" to actual commands.

**Step 4: Commit**
```bash
cd os/Ockham && git add -A && git commit -m "chore(ockham): update AGENTS.md for F1+F2 packages, full test pass"
```

<verify>
- run: `cd os/Ockham && go test ./... -v -cover`
  expect: exit 0
- run: `cd os/Ockham && go build ./cmd/ockham`
  expect: exit 0
- run: `cd os/Ockham && go vet ./...`
  expect: exit 0
</verify>
