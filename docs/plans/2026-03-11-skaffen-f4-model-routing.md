---
artifact_type: plan
bead: Demarch-0pj
stage: design
prd: docs/prds/2026-03-11-skaffen-f4-model-routing.md
requirements:
  - "F4a: DefaultRouter with phase defaults (brainstorm=opus, rest=sonnet)"
  - "F4b: Config loading (JSON + env var overrides)"
  - "F4c: Budget tracker with graceful degradation"
  - "F4d: Complexity layer (C1-C5 shadow mode)"
---
# F4: Model Routing Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Demarch-0pj
**Goal:** Replace NoOpRouter with a DefaultRouter that selects models based on OODARC phase, config overrides, token budget tracking, and complexity classification.

**Architecture:** New `internal/router/` package. `DefaultRouter` implements `agent.Router` (extended with `RecordUsage`). Three layers: `config.go` loads routing config (JSON + env vars), `budget.go` tracks token usage with degradation modes, `complexity.go` classifies prompt complexity (shadow mode). The agent loop calls `RecordUsage()` after each turn to feed the budget tracker.

**Tech Stack:** Go 1.22, `encoding/json`, `os` for config/env, `sync` for concurrent safety.

---

## Must-Haves

**Truths:**
- `go test ./internal/router/...` passes
- `DefaultRouter.SelectModel(brainstorm)` returns `claude-opus-4-6`
- `DefaultRouter.SelectModel(build)` returns `claude-sonnet-4-6`
- Env var `SKAFFEN_MODEL_BUILD=haiku` overrides the build phase model
- `routing.json` overrides hardcoded defaults
- Budget degradation downgrades model at 80% threshold
- `--budget` CLI flag sets per-session token limit
- Complexity classification logs shadow data via evidence emission

**Artifacts:**
- `internal/router/router.go` — DefaultRouter implementing extended Router interface
- `internal/router/router_test.go` — phase defaults, fallback chain, reason strings
- `internal/router/config.go` — three-layer config resolution
- `internal/router/config_test.go` — JSON overrides, env overrides, missing file
- `internal/router/budget.go` — BudgetTracker with three enforcement modes
- `internal/router/budget_test.go` — degradation thresholds, hard-stop, advisory
- `internal/router/complexity.go` — C1-C5 classification with shadow/enforce modes
- `internal/router/complexity_test.go` — classification thresholds, shadow vs enforce
- `internal/agent/deps.go` — Router interface extended with RecordUsage
- `internal/agent/loop.go` — RecordUsage call after usage accumulation
- `cmd/skaffen/main.go` — `--budget` flag, DefaultRouter wiring

**Key Links:**
- Agent loop calls `router.SelectModel(phase)` at orient step (loop.go:43)
- Agent loop must call `router.RecordUsage(usage)` after usage accumulation (loop.go:70)
- `cmd/skaffen/main.go` creates DefaultRouter and passes via `agent.WithRouter()`
- DefaultRouter uses Config internally; Config loads from JSON then env vars
- BudgetTracker is embedded in DefaultRouter; fed by RecordUsage

---

### Task 1: Extend Router interface with RecordUsage

**Files:**
- Modify: `internal/agent/deps.go`

**Step 1: Add RecordUsage to the Router interface**

In `internal/agent/deps.go`, add `RecordUsage` to the Router interface and update the NoOpRouter:

```go
// Router selects which model to use per turn.
type Router interface {
	SelectModel(phase tool.Phase) (model string, reason string)
	RecordUsage(usage provider.Usage)
}
```

And update NoOpRouter:

```go
func (r *NoOpRouter) RecordUsage(_ provider.Usage) {}
```

**Step 2: Run existing tests to verify no breakage**

Run: `cd os/Skaffen && go test ./...`
Expected: All tests pass (NoOpRouter now satisfies the extended interface).

**Step 3: Commit**

```bash
cd os/Skaffen && git add internal/agent/deps.go && git commit -m "feat(router): extend Router interface with RecordUsage method"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/agent/...`
  expect: exit 0
</verify>

---

### Task 2: Wire RecordUsage in agent loop

**Files:**
- Modify: `internal/agent/loop.go`

**Step 1: Add RecordUsage call after usage accumulation**

In `internal/agent/loop.go`, after line 70 (the cache read tokens accumulation), add:

```go
// Feed budget tracker
a.router.RecordUsage(collected.Usage)
```

This goes right after the four `totalUsage` accumulation lines and before `buildAssistantMessage`.

**Step 2: Run tests**

Run: `cd os/Skaffen && go test ./internal/agent/...`
Expected: PASS (NoOpRouter.RecordUsage is a no-op).

**Step 3: Commit**

```bash
cd os/Skaffen && git add internal/agent/loop.go && git commit -m "feat(loop): call router.RecordUsage after each turn"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/agent/...`
  expect: exit 0
</verify>

---

### Task 3: Create router package with DefaultRouter (phase defaults)

**Files:**
- Create: `internal/router/router.go`
- Create: `internal/router/router_test.go`

**Step 1: Write the failing tests**

Create `internal/router/router_test.go`:

```go
package router

import (
	"testing"

	"github.com/mistakeknot/Skaffen/internal/tool"
)

func TestPhaseDefaults(t *testing.T) {
	r := New(nil) // nil config = use hardcoded defaults
	tests := []struct {
		phase tool.Phase
		want  string
	}{
		{tool.PhaseBrainstorm, "claude-opus-4-6"},
		{tool.PhasePlan, "claude-sonnet-4-6"},
		{tool.PhaseBuild, "claude-sonnet-4-6"},
		{tool.PhaseReview, "claude-sonnet-4-6"},
		{tool.PhaseShip, "claude-sonnet-4-6"},
	}
	for _, tt := range tests {
		model, reason := r.SelectModel(tt.phase)
		if model != tt.want {
			t.Errorf("SelectModel(%s) = %q, want %q", tt.phase, model, tt.want)
		}
		if reason == "" {
			t.Errorf("SelectModel(%s) returned empty reason", tt.phase)
		}
	}
}

func TestFallbackChain(t *testing.T) {
	r := New(nil)
	// Verify the fallback chain is opus → sonnet → haiku
	chain := r.FallbackChain()
	if len(chain) != 3 {
		t.Fatalf("fallback chain length = %d, want 3", len(chain))
	}
	if chain[0] != "claude-opus-4-6" {
		t.Errorf("chain[0] = %q, want claude-opus-4-6", chain[0])
	}
	if chain[1] != "claude-sonnet-4-6" {
		t.Errorf("chain[1] = %q, want claude-sonnet-4-6", chain[1])
	}
	if chain[2] != "claude-haiku-4-5-20251001" {
		t.Errorf("chain[2] = %q, want claude-haiku-4-5-20251001", chain[2])
	}
}

func TestReasonStrings(t *testing.T) {
	r := New(nil)
	_, reason := r.SelectModel(tool.PhaseBrainstorm)
	if reason != "phase-default" {
		t.Errorf("brainstorm reason = %q, want %q", reason, "phase-default")
	}
}

func TestRecordUsageNoOp(t *testing.T) {
	r := New(nil)
	// Should not panic with no budget set
	r.RecordUsage(provider.Usage{InputTokens: 100, OutputTokens: 50})
}
```

**Step 2: Run tests to verify they fail**

Run: `cd os/Skaffen && go test ./internal/router/...`
Expected: FAIL (package doesn't exist yet).

**Step 3: Write the DefaultRouter implementation**

Create `internal/router/router.go`:

```go
package router

import (
	"github.com/mistakeknot/Skaffen/internal/provider"
	"github.com/mistakeknot/Skaffen/internal/tool"
)

// Canonical model IDs.
const (
	ModelOpus   = "claude-opus-4-6"
	ModelSonnet = "claude-sonnet-4-6"
	ModelHaiku  = "claude-haiku-4-5-20251001"
)

// Hardcoded fallback chain: opus → sonnet → haiku.
var fallbackChain = []string{ModelOpus, ModelSonnet, ModelHaiku}

// Phase defaults from Clavain's economy routing table.
var phaseDefaults = map[tool.Phase]string{
	tool.PhaseBrainstorm: ModelOpus,
	tool.PhasePlan:       ModelSonnet,
	tool.PhaseBuild:      ModelSonnet,
	tool.PhaseReview:     ModelSonnet,
	tool.PhaseShip:       ModelSonnet,
}

// DefaultRouter selects models based on phase, config overrides, and budget.
type DefaultRouter struct {
	cfg        *Config
	budget     *BudgetTracker
	complexity *ComplexityClassifier
}

// New creates a DefaultRouter. Pass nil config to use hardcoded defaults.
func New(cfg *Config) *DefaultRouter {
	if cfg == nil {
		cfg = &Config{}
	}
	r := &DefaultRouter{cfg: cfg}
	if cfg.Budget != nil && cfg.Budget.MaxTokens > 0 {
		r.budget = newBudgetTracker(cfg.Budget)
	}
	if cfg.Complexity != nil {
		r.complexity = newComplexityClassifier(cfg.Complexity)
	}
	return r
}

// SelectModel returns the model and reason for the given phase.
// Resolution order: budget degradation > env var > config file > phase default.
func (r *DefaultRouter) SelectModel(phase tool.Phase) (string, string) {
	// Start with phase default
	model := phaseDefaults[phase]
	reason := "phase-default"
	if model == "" {
		model = ModelSonnet
		reason = "fallback-default"
	}

	// Config file override
	if m, ok := r.cfg.Phases[phase]; ok && m != "" {
		model = resolveModelAlias(m)
		reason = "config-file"
	}

	// Env var override (highest priority for explicit user control)
	if m := r.cfg.envOverride(phase); m != "" {
		model = resolveModelAlias(m)
		reason = "env-override"
	}

	// Budget degradation (overrides everything when budget is exhausted)
	if r.budget != nil {
		model, reason = r.budget.MaybeDegrade(model, reason)
	}

	return model, reason
}

// RecordUsage feeds the budget tracker with token consumption.
func (r *DefaultRouter) RecordUsage(usage provider.Usage) {
	if r.budget != nil {
		r.budget.Record(usage)
	}
}

// FallbackChain returns the hardcoded model fallback chain.
func (r *DefaultRouter) FallbackChain() []string {
	return fallbackChain
}

// resolveModelAlias converts short aliases to canonical model IDs.
func resolveModelAlias(alias string) string {
	switch alias {
	case "opus":
		return ModelOpus
	case "sonnet":
		return ModelSonnet
	case "haiku":
		return ModelHaiku
	default:
		return alias // assume it's already a full model ID
	}
}
```

**Step 4: Run tests**

Run: `cd os/Skaffen && go test ./internal/router/... -v`
Expected: PASS (all 4 tests).

**Step 5: Commit**

```bash
cd os/Skaffen && git add internal/router/ && git commit -m "feat(router): DefaultRouter with phase defaults and fallback chain"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/router/... -v`
  expect: exit 0
- run: `cd os/Skaffen && go test ./internal/router/... -run TestPhaseDefaults`
  expect: exit 0
</verify>

---

### Task 4: Config loading (JSON + env vars)

**Files:**
- Create: `internal/router/config.go`
- Create: `internal/router/config_test.go`

**Step 1: Write the failing tests**

Create `internal/router/config_test.go`:

```go
package router

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/mistakeknot/Skaffen/internal/tool"
)

func TestLoadConfigDefaults(t *testing.T) {
	// No config file → empty config, no error
	cfg, err := LoadConfig("/nonexistent/path/routing.json")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(cfg.Phases) != 0 {
		t.Errorf("expected empty phases, got %v", cfg.Phases)
	}
}

func TestLoadConfigFromJSON(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "routing.json")
	data := `{"phases": {"brainstorm": "sonnet", "build": "haiku"}, "budget": {"max_tokens": 500000, "mode": "graceful", "degrade_at": 0.8}}`
	if err := os.WriteFile(path, []byte(data), 0644); err != nil {
		t.Fatal(err)
	}
	cfg, err := LoadConfig(path)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if cfg.Phases[tool.PhaseBrainstorm] != "sonnet" {
		t.Errorf("brainstorm = %q, want sonnet", cfg.Phases[tool.PhaseBrainstorm])
	}
	if cfg.Phases[tool.PhaseBuild] != "haiku" {
		t.Errorf("build = %q, want haiku", cfg.Phases[tool.PhaseBuild])
	}
	if cfg.Budget == nil || cfg.Budget.MaxTokens != 500000 {
		t.Errorf("budget max_tokens = %v, want 500000", cfg.Budget)
	}
	if cfg.Budget.Mode != "graceful" {
		t.Errorf("budget mode = %q, want graceful", cfg.Budget.Mode)
	}
}

func TestEnvVarOverride(t *testing.T) {
	cfg := &Config{}
	t.Setenv("SKAFFEN_MODEL_BUILD", "haiku")
	got := cfg.envOverride(tool.PhaseBuild)
	if got != "haiku" {
		t.Errorf("envOverride(build) = %q, want haiku", got)
	}
}

func TestEnvVarOverrideMissing(t *testing.T) {
	cfg := &Config{}
	got := cfg.envOverride(tool.PhaseBuild)
	if got != "" {
		t.Errorf("envOverride(build) = %q, want empty", got)
	}
}

func TestResolutionOrder(t *testing.T) {
	// JSON sets brainstorm=haiku, env sets brainstorm=sonnet → env wins
	dir := t.TempDir()
	path := filepath.Join(dir, "routing.json")
	data := `{"phases": {"brainstorm": "haiku"}}`
	if err := os.WriteFile(path, []byte(data), 0644); err != nil {
		t.Fatal(err)
	}
	cfg, _ := LoadConfig(path)
	t.Setenv("SKAFFEN_MODEL_BRAINSTORM", "sonnet")

	r := New(cfg)
	model, reason := r.SelectModel(tool.PhaseBrainstorm)
	if model != ModelSonnet {
		t.Errorf("model = %q, want %q (env should override JSON)", model, ModelSonnet)
	}
	if reason != "env-override" {
		t.Errorf("reason = %q, want env-override", reason)
	}
}

func TestLoadConfigInvalidJSON(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "routing.json")
	if err := os.WriteFile(path, []byte("{invalid"), 0644); err != nil {
		t.Fatal(err)
	}
	_, err := LoadConfig(path)
	if err == nil {
		t.Error("expected error for invalid JSON")
	}
}
```

**Step 2: Run tests to verify they fail**

Run: `cd os/Skaffen && go test ./internal/router/... -run TestLoad`
Expected: FAIL (Config type and LoadConfig don't exist yet).

**Step 3: Write the config implementation**

Create `internal/router/config.go`:

```go
package router

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"github.com/mistakeknot/Skaffen/internal/tool"
)

// Config holds routing configuration from JSON + env vars.
type Config struct {
	Phases     map[tool.Phase]string `json:"phases,omitempty"`
	Budget     *BudgetConfig         `json:"budget,omitempty"`
	Complexity *ComplexityConfig      `json:"complexity,omitempty"`
}

// BudgetConfig controls per-session token budget enforcement.
type BudgetConfig struct {
	MaxTokens int     `json:"max_tokens"`
	Mode      string  `json:"mode"`       // "graceful" (default), "hard-stop", "advisory"
	DegradeAt float64 `json:"degrade_at"` // 0-1, default 0.8
}

// ComplexityConfig controls prompt complexity classification.
type ComplexityConfig struct {
	Mode string `json:"mode"` // "shadow" (default), "enforce"
}

// LoadConfig reads routing config from a JSON file.
// Returns empty config (not error) if file doesn't exist.
func LoadConfig(path string) (*Config, error) {
	cfg := &Config{
		Phases: make(map[tool.Phase]string),
	}

	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return cfg, nil
		}
		return nil, fmt.Errorf("read routing config: %w", err)
	}

	if err := json.Unmarshal(data, cfg); err != nil {
		return nil, fmt.Errorf("parse routing config %s: %w", path, err)
	}

	// Normalize budget defaults
	if cfg.Budget != nil {
		if cfg.Budget.Mode == "" {
			cfg.Budget.Mode = "graceful"
		}
		if cfg.Budget.DegradeAt == 0 {
			cfg.Budget.DegradeAt = 0.8
		}
	}

	if cfg.Phases == nil {
		cfg.Phases = make(map[tool.Phase]string)
	}

	return cfg, nil
}

// envOverride checks for SKAFFEN_MODEL_<PHASE> env var.
func (c *Config) envOverride(phase tool.Phase) string {
	key := "SKAFFEN_MODEL_" + strings.ToUpper(string(phase))
	return os.Getenv(key)
}
```

**Step 4: Run tests**

Run: `cd os/Skaffen && go test ./internal/router/... -v`
Expected: PASS (all tests).

**Step 5: Commit**

```bash
cd os/Skaffen && git add internal/router/config.go internal/router/config_test.go && git commit -m "feat(router): config loading with JSON + env var overrides"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/router/... -v`
  expect: exit 0
- run: `cd os/Skaffen && go test ./internal/router/... -run TestResolutionOrder`
  expect: exit 0
</verify>

---

### Task 5: Budget tracker with degradation modes

**Files:**
- Create: `internal/router/budget.go`
- Create: `internal/router/budget_test.go`

**Step 1: Write the failing tests**

Create `internal/router/budget_test.go`:

```go
package router

import (
	"testing"

	"github.com/mistakeknot/Skaffen/internal/provider"
)

func TestBudgetGracefulUnderThreshold(t *testing.T) {
	bt := newBudgetTracker(&BudgetConfig{
		MaxTokens: 1000, Mode: "graceful", DegradeAt: 0.8,
	})
	// At 0% — no degradation
	model, reason := bt.MaybeDegrade(ModelOpus, "phase-default")
	if model != ModelOpus {
		t.Errorf("at 0%%: model = %q, want %q", model, ModelOpus)
	}
	if reason != "phase-default" {
		t.Errorf("at 0%%: reason = %q, want phase-default", reason)
	}
}

func TestBudgetGracefulAtThreshold(t *testing.T) {
	bt := newBudgetTracker(&BudgetConfig{
		MaxTokens: 1000, Mode: "graceful", DegradeAt: 0.8,
	})
	// Record 800 tokens → 80% → should degrade
	bt.Record(provider.Usage{InputTokens: 500, OutputTokens: 300})
	model, reason := bt.MaybeDegrade(ModelOpus, "phase-default")
	if model != ModelHaiku {
		t.Errorf("at 80%%: model = %q, want %q", model, ModelHaiku)
	}
	if reason != "budget-degrade" {
		t.Errorf("at 80%%: reason = %q, want budget-degrade", reason)
	}
}

func TestBudgetGracefulOverBudget(t *testing.T) {
	bt := newBudgetTracker(&BudgetConfig{
		MaxTokens: 1000, Mode: "graceful", DegradeAt: 0.8,
	})
	// Record 1100 tokens → 110% → should degrade to haiku + warn
	bt.Record(provider.Usage{InputTokens: 700, OutputTokens: 400})
	model, reason := bt.MaybeDegrade(ModelOpus, "phase-default")
	if model != ModelHaiku {
		t.Errorf("at 110%%: model = %q, want %q", model, ModelHaiku)
	}
	if reason != "budget-exceeded" {
		t.Errorf("at 110%%: reason = %q, want budget-exceeded", reason)
	}
}

func TestBudgetHardStop(t *testing.T) {
	bt := newBudgetTracker(&BudgetConfig{
		MaxTokens: 1000, Mode: "hard-stop", DegradeAt: 0.8,
	})
	bt.Record(provider.Usage{InputTokens: 600, OutputTokens: 500})
	model, reason := bt.MaybeDegrade(ModelOpus, "phase-default")
	if model != "" {
		t.Errorf("hard-stop over budget: model = %q, want empty", model)
	}
	if reason != "budget-exhausted" {
		t.Errorf("hard-stop: reason = %q, want budget-exhausted", reason)
	}
}

func TestBudgetAdvisory(t *testing.T) {
	bt := newBudgetTracker(&BudgetConfig{
		MaxTokens: 1000, Mode: "advisory", DegradeAt: 0.8,
	})
	bt.Record(provider.Usage{InputTokens: 600, OutputTokens: 500})
	// Advisory: never changes model, just tracks
	model, reason := bt.MaybeDegrade(ModelOpus, "phase-default")
	if model != ModelOpus {
		t.Errorf("advisory: model = %q, want %q", model, ModelOpus)
	}
	if reason != "phase-default" {
		t.Errorf("advisory: reason = %q, want phase-default", reason)
	}
}

func TestBudgetState(t *testing.T) {
	bt := newBudgetTracker(&BudgetConfig{
		MaxTokens: 1000, Mode: "graceful", DegradeAt: 0.8,
	})
	bt.Record(provider.Usage{InputTokens: 300, OutputTokens: 200})
	state := bt.State()
	if state.Spent != 500 {
		t.Errorf("spent = %d, want 500", state.Spent)
	}
	if state.Max != 1000 {
		t.Errorf("max = %d, want 1000", state.Max)
	}
	if state.Percentage < 0.49 || state.Percentage > 0.51 {
		t.Errorf("percentage = %f, want ~0.5", state.Percentage)
	}
}

func TestBudgetCumulativeRecording(t *testing.T) {
	bt := newBudgetTracker(&BudgetConfig{
		MaxTokens: 1000, Mode: "graceful", DegradeAt: 0.8,
	})
	bt.Record(provider.Usage{InputTokens: 200, OutputTokens: 100})
	bt.Record(provider.Usage{InputTokens: 200, OutputTokens: 100})
	bt.Record(provider.Usage{InputTokens: 200, OutputTokens: 100})
	state := bt.State()
	if state.Spent != 900 {
		t.Errorf("cumulative spent = %d, want 900", state.Spent)
	}
}
```

**Step 2: Run tests to verify they fail**

Run: `cd os/Skaffen && go test ./internal/router/... -run TestBudget`
Expected: FAIL (BudgetTracker doesn't exist yet).

**Step 3: Write the budget tracker implementation**

Create `internal/router/budget.go`:

```go
package router

import (
	"sync"

	"github.com/mistakeknot/Skaffen/internal/provider"
)

// BudgetState reports current budget consumption.
type BudgetState struct {
	Spent      int     `json:"spent"`
	Max        int     `json:"max"`
	Percentage float64 `json:"percentage"`
	Mode       string  `json:"mode"`
}

// BudgetTracker tracks cumulative token usage against a budget.
type BudgetTracker struct {
	maxTokens int
	degradeAt float64
	mode      string // "graceful", "hard-stop", "advisory"
	spent     int
	mu        sync.Mutex
}

func newBudgetTracker(cfg *BudgetConfig) *BudgetTracker {
	mode := cfg.Mode
	if mode == "" {
		mode = "graceful"
	}
	degradeAt := cfg.DegradeAt
	if degradeAt == 0 {
		degradeAt = 0.8
	}
	return &BudgetTracker{
		maxTokens: cfg.MaxTokens,
		degradeAt: degradeAt,
		mode:      mode,
	}
}

// Record adds token consumption from a single turn.
func (bt *BudgetTracker) Record(usage provider.Usage) {
	bt.mu.Lock()
	defer bt.mu.Unlock()
	bt.spent += usage.InputTokens + usage.OutputTokens
}

// MaybeDegrade returns a (possibly degraded) model and reason.
// If no degradation is needed, returns the input model and reason unchanged.
func (bt *BudgetTracker) MaybeDegrade(model, reason string) (string, string) {
	bt.mu.Lock()
	pct := float64(bt.spent) / float64(bt.maxTokens)
	mode := bt.mode
	bt.mu.Unlock()

	switch mode {
	case "advisory":
		// Never change model, just track
		return model, reason

	case "hard-stop":
		if pct >= 1.0 {
			return "", "budget-exhausted"
		}
		return model, reason

	default: // "graceful"
		if pct >= 1.0 {
			return ModelHaiku, "budget-exceeded"
		}
		if pct >= bt.degradeAt {
			return ModelHaiku, "budget-degrade"
		}
		return model, reason
	}
}

// State returns the current budget consumption state.
func (bt *BudgetTracker) State() BudgetState {
	bt.mu.Lock()
	defer bt.mu.Unlock()
	pct := 0.0
	if bt.maxTokens > 0 {
		pct = float64(bt.spent) / float64(bt.maxTokens)
	}
	return BudgetState{
		Spent:      bt.spent,
		Max:        bt.maxTokens,
		Percentage: pct,
		Mode:       bt.mode,
	}
}
```

**Step 4: Run tests**

Run: `cd os/Skaffen && go test ./internal/router/... -run TestBudget -v`
Expected: PASS (all 7 budget tests).

**Step 5: Commit**

```bash
cd os/Skaffen && git add internal/router/budget.go internal/router/budget_test.go && git commit -m "feat(router): budget tracker with graceful/hard-stop/advisory modes"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/router/... -run TestBudget -v`
  expect: exit 0
</verify>

---

### Task 6: Complexity classifier (shadow mode)

**Files:**
- Create: `internal/router/complexity.go`
- Create: `internal/router/complexity_test.go`

**Step 1: Write the failing tests**

Create `internal/router/complexity_test.go`:

```go
package router

import (
	"testing"
)

func TestClassifyComplexity(t *testing.T) {
	cc := newComplexityClassifier(&ComplexityConfig{Mode: "shadow"})
	tests := []struct {
		tokens int
		want   int // C1-C5
	}{
		{100, 1},
		{299, 1},
		{300, 2},
		{799, 2},
		{800, 3},
		{1999, 3},
		{2000, 4},
		{3999, 4},
		{4000, 5},
		{10000, 5},
	}
	for _, tt := range tests {
		got := cc.Classify(tt.tokens)
		if got != tt.want {
			t.Errorf("Classify(%d) = C%d, want C%d", tt.tokens, got, tt.want)
		}
	}
}

func TestComplexityShadowMode(t *testing.T) {
	cc := newComplexityClassifier(&ComplexityConfig{Mode: "shadow"})
	// Shadow mode: should NOT change the model
	model, reason, override := cc.MaybeOverride(ModelSonnet, "phase-default", 100)
	if model != ModelSonnet {
		t.Errorf("shadow mode changed model to %q", model)
	}
	if reason != "phase-default" {
		t.Errorf("shadow mode changed reason to %q", reason)
	}
	if override == nil {
		t.Fatal("shadow mode should still return override info")
	}
	if override.Tier != 1 {
		t.Errorf("override tier = %d, want 1", override.Tier)
	}
	if override.Applied {
		t.Error("shadow mode should not apply override")
	}
}

func TestComplexityEnforcePromote(t *testing.T) {
	cc := newComplexityClassifier(&ComplexityConfig{Mode: "enforce"})
	// C4 (2000 tokens) should promote to opus
	model, reason, override := cc.MaybeOverride(ModelSonnet, "phase-default", 2500)
	if model != ModelOpus {
		t.Errorf("enforce C4: model = %q, want opus", model)
	}
	if reason != "complexity-promote" {
		t.Errorf("enforce C4: reason = %q, want complexity-promote", reason)
	}
	if !override.Applied {
		t.Error("enforce mode should apply override")
	}
}

func TestComplexityEnforceDemote(t *testing.T) {
	cc := newComplexityClassifier(&ComplexityConfig{Mode: "enforce"})
	// C1 (100 tokens) should demote to haiku
	model, reason, override := cc.MaybeOverride(ModelSonnet, "phase-default", 100)
	if model != ModelHaiku {
		t.Errorf("enforce C1: model = %q, want haiku", model)
	}
	if reason != "complexity-demote" {
		t.Errorf("enforce C1: reason = %q, want complexity-demote", reason)
	}
}

func TestComplexityEnforceNoChange(t *testing.T) {
	cc := newComplexityClassifier(&ComplexityConfig{Mode: "enforce"})
	// C3 (1000 tokens) should NOT change model
	model, reason, _ := cc.MaybeOverride(ModelSonnet, "phase-default", 1000)
	if model != ModelSonnet {
		t.Errorf("enforce C3: model = %q, want sonnet (no change)", model)
	}
	if reason != "phase-default" {
		t.Errorf("enforce C3: reason = %q, want phase-default", reason)
	}
}
```

**Step 2: Run tests to verify they fail**

Run: `cd os/Skaffen && go test ./internal/router/... -run TestClassify`
Expected: FAIL (ComplexityClassifier doesn't exist yet).

**Step 3: Write the complexity classifier implementation**

Create `internal/router/complexity.go`:

```go
package router

// ComplexityOverride records what the complexity layer would/did change.
type ComplexityOverride struct {
	Tier         int    `json:"complexity_tier"`
	WouldPromote bool   `json:"would_promote,omitempty"`
	WouldDemote  bool   `json:"would_demote,omitempty"`
	Applied      bool   `json:"complexity_override"`
	OrigModel    string `json:"original_model,omitempty"`
}

// ComplexityClassifier classifies prompt complexity and optionally overrides model selection.
type ComplexityClassifier struct {
	mode string // "shadow" or "enforce"
}

func newComplexityClassifier(cfg *ComplexityConfig) *ComplexityClassifier {
	mode := cfg.Mode
	if mode == "" {
		mode = "shadow"
	}
	return &ComplexityClassifier{mode: mode}
}

// Classify returns a complexity tier (1-5) based on input token count.
// C1: <300, C2: <800, C3: <2000, C4: <4000, C5: 4000+
func (cc *ComplexityClassifier) Classify(inputTokens int) int {
	switch {
	case inputTokens < 300:
		return 1
	case inputTokens < 800:
		return 2
	case inputTokens < 2000:
		return 3
	case inputTokens < 4000:
		return 4
	default:
		return 5
	}
}

// MaybeOverride returns a (possibly overridden) model based on complexity.
// In shadow mode, returns the original model but still provides override info for logging.
// In enforce mode, C4-C5 promote to opus, C1-C2 demote to haiku.
func (cc *ComplexityClassifier) MaybeOverride(model, reason string, inputTokens int) (string, string, *ComplexityOverride) {
	tier := cc.Classify(inputTokens)
	override := &ComplexityOverride{
		Tier:      tier,
		OrigModel: model,
	}

	// Determine what would change
	if tier >= 4 {
		override.WouldPromote = true
	} else if tier <= 2 {
		override.WouldDemote = true
	}

	if cc.mode == "shadow" {
		// Log what would change, but don't apply
		override.Applied = false
		return model, reason, override
	}

	// Enforce mode: apply overrides
	if tier >= 4 && model != ModelOpus {
		override.Applied = true
		return ModelOpus, "complexity-promote", override
	}
	if tier <= 2 && model != ModelHaiku {
		override.Applied = true
		return ModelHaiku, "complexity-demote", override
	}

	override.Applied = false
	return model, reason, override
}
```

**Step 4: Run tests**

Run: `cd os/Skaffen && go test ./internal/router/... -run TestC -v`
Expected: PASS (all complexity tests).

**Step 5: Commit**

```bash
cd os/Skaffen && git add internal/router/complexity.go internal/router/complexity_test.go && git commit -m "feat(router): complexity classifier with shadow/enforce modes"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/router/... -v`
  expect: exit 0
</verify>

---

### Task 7: Integrate complexity into DefaultRouter + evidence

**Files:**
- Modify: `internal/router/router.go`
- Modify: `internal/router/router_test.go`
- Modify: `internal/agent/deps.go` (add complexity fields to Evidence)

**Step 1: Add complexity integration tests**

Append to `internal/router/router_test.go`:

```go
func TestRouterWithComplexityShadow(t *testing.T) {
	cfg := &Config{
		Phases:     map[tool.Phase]string{},
		Complexity: &ComplexityConfig{Mode: "shadow"},
	}
	r := New(cfg)
	model, reason := r.SelectModel(tool.PhaseBuild)
	// Shadow mode should NOT change the model
	if model != ModelSonnet {
		t.Errorf("shadow complexity changed model to %q", model)
	}
	if reason != "phase-default" {
		t.Errorf("shadow complexity changed reason to %q", reason)
	}
}

func TestRouterWithComplexityEnforce(t *testing.T) {
	cfg := &Config{
		Phases:     map[tool.Phase]string{},
		Complexity: &ComplexityConfig{Mode: "enforce"},
	}
	r := New(cfg)
	r.SetInputTokens(5000) // C5 → promote to opus
	model, reason := r.SelectModel(tool.PhaseBuild)
	if model != ModelOpus {
		t.Errorf("enforce C5: model = %q, want opus", model)
	}
	if reason != "complexity-promote" {
		t.Errorf("enforce C5: reason = %q, want complexity-promote", reason)
	}
}

func TestRouterLastOverride(t *testing.T) {
	cfg := &Config{
		Phases:     map[tool.Phase]string{},
		Complexity: &ComplexityConfig{Mode: "shadow"},
	}
	r := New(cfg)
	r.SetInputTokens(100)
	r.SelectModel(tool.PhaseBuild)
	override := r.LastComplexityOverride()
	if override == nil {
		t.Fatal("expected complexity override info")
	}
	if override.Tier != 1 {
		t.Errorf("tier = %d, want 1", override.Tier)
	}
	if override.Applied {
		t.Error("shadow mode should not apply")
	}
}
```

**Step 2: Add SetInputTokens, LastComplexityOverride, and complexity integration to DefaultRouter**

Update `internal/router/router.go` — add fields and methods:

```go
// Add to DefaultRouter struct:
//   inputTokens   int                // set before SelectModel for complexity
//   lastOverride  *ComplexityOverride // last complexity result for evidence

// SetInputTokens sets the current turn's input token count for complexity classification.
func (r *DefaultRouter) SetInputTokens(n int) {
	r.inputTokens = n
}

// LastComplexityOverride returns the complexity override from the last SelectModel call.
func (r *DefaultRouter) LastComplexityOverride() *ComplexityOverride {
	return r.lastOverride
}
```

In `SelectModel`, add complexity processing after budget degradation:

```go
// Complexity override (applied last in shadow mode, or can promote/demote in enforce mode)
r.lastOverride = nil
if r.complexity != nil {
    model, reason, r.lastOverride = r.complexity.MaybeOverride(model, reason, r.inputTokens)
}
```

**Step 3: Add complexity fields to Evidence struct**

In `internal/agent/deps.go`, add optional complexity fields to Evidence:

```go
// Add to Evidence struct:
ComplexityTier     int  `json:"complexity_tier,omitempty"`
ComplexityOverride bool `json:"complexity_override,omitempty"`
```

**Step 4: Run all tests**

Run: `cd os/Skaffen && go test ./...`
Expected: PASS (all tests).

**Step 5: Commit**

```bash
cd os/Skaffen && git add internal/router/router.go internal/router/router_test.go internal/agent/deps.go && git commit -m "feat(router): integrate complexity into DefaultRouter + evidence fields"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/router/... -v`
  expect: exit 0
- run: `cd os/Skaffen && go test ./...`
  expect: exit 0
</verify>

---

### Task 8: Wire DefaultRouter + --budget flag in CLI

**Files:**
- Modify: `cmd/skaffen/main.go`

**Step 1: Add --budget flag and DefaultRouter wiring**

In `cmd/skaffen/main.go`:

1. Add import: `"github.com/mistakeknot/Skaffen/internal/router"`
2. Add flag: `flagBudget = flag.Int("budget", 0, "Per-session token budget (0 = unlimited)")`
3. In `run()`, after provider creation and before agent creation, add:

```go
// Load routing config (optional file, env vars always checked)
routingPath := filepath.Join(os.Getenv("HOME"), ".skaffen", "routing.json")
routerCfg, err := router.LoadConfig(routingPath)
if err != nil {
    fmt.Fprintf(os.Stderr, "skaffen: warning: routing config: %v\n", err)
    routerCfg = &router.Config{}
}

// CLI --budget flag overrides config file budget
if *flagBudget > 0 {
    routerCfg.Budget = &router.BudgetConfig{
        MaxTokens: *flagBudget,
        Mode:      "graceful",
        DegradeAt: 0.8,
    }
}

// CLI --model flag: set as override for all phases (backward compat)
if *flagModel != "" {
    if routerCfg.Phases == nil {
        routerCfg.Phases = make(map[tool.Phase]string)
    }
    for _, p := range []tool.Phase{tool.PhaseBrainstorm, tool.PhasePlan, tool.PhaseBuild, tool.PhaseReview, tool.PhaseShip} {
        routerCfg.Phases[p] = *flagModel
    }
}

modelRouter := router.New(routerCfg)
opts = append(opts, agent.WithRouter(modelRouter))
```

4. Remove the old `cfg.Model = *flagModel` line from provider config (model is now router-managed).

**Step 2: Update provider config**

The provider's `Config.Model` field is still set per-turn by the agent loop (loop.go:49 reads from `router.SelectModel`), so the provider config in main.go should NOT set the model — it's router-managed now.

**Step 3: Build and verify**

Run: `cd os/Skaffen && go build -o /tmp/skaffen ./cmd/skaffen`
Expected: Build succeeds.

**Step 4: Commit**

```bash
cd os/Skaffen && git add cmd/skaffen/main.go && git commit -m "feat(cli): wire DefaultRouter with --budget flag and config loading"
```

<verify>
- run: `cd os/Skaffen && go build -o /tmp/skaffen ./cmd/skaffen`
  expect: exit 0
- run: `cd os/Skaffen && go test ./...`
  expect: exit 0
</verify>

---

### Task 9: Budget state in evidence emission

**Files:**
- Modify: `internal/agent/deps.go` (add budget fields to Evidence)
- Modify: `internal/agent/loop.go` (populate budget state in evidence)

**Step 1: Add budget fields to Evidence**

In `internal/agent/deps.go`, add to Evidence struct:

```go
BudgetSpent      int     `json:"budget_spent,omitempty"`
BudgetMax        int     `json:"budget_max,omitempty"`
BudgetPercentage float64 `json:"budget_pct,omitempty"`
```

**Step 2: Add BudgetState method to Router interface**

This requires a way for the loop to query budget state. Add an optional interface check in loop.go rather than changing the Router interface (keeps backward compat with NoOpRouter):

In loop.go, after the evidence struct is built and before `a.emitter.Emit()`, add:

```go
// Populate budget + complexity state if router supports it
type budgetReporter interface {
    BudgetState() BudgetState
}
if br, ok := a.router.(budgetReporter); ok {
    state := br.BudgetState()
    ev.BudgetSpent = state.Spent
    ev.BudgetMax = state.Max
    ev.BudgetPercentage = state.Percentage
}
```

Import the router package's BudgetState type — but to avoid circular imports, define the budget state fields inline in the evidence or use a type assertion with an anonymous interface.

Actually, to keep it simple and avoid circular imports between `agent` and `router`, use the inline interface assertion pattern shown above. The `BudgetState` return type needs to be from a shared location. The cleanest approach: return `(spent int, max int, pct float64)` tuple instead of a struct.

Alternative: Add `BudgetState() (spent, max int, pct float64)` to the Router interface directly, and implement as no-op in NoOpRouter.

**Updated approach — extend Router interface:**

In `deps.go`:
```go
type Router interface {
    SelectModel(phase tool.Phase) (model string, reason string)
    RecordUsage(usage provider.Usage)
    BudgetState() (spent, max int, pct float64)
}
```

In NoOpRouter:
```go
func (r *NoOpRouter) BudgetState() (int, int, float64) { return 0, 0, 0 }
```

In DefaultRouter (router.go):
```go
func (r *DefaultRouter) BudgetState() (int, int, float64) {
    if r.budget == nil {
        return 0, 0, 0
    }
    s := r.budget.State()
    return s.Spent, s.Max, s.Percentage
}
```

In loop.go, after building the evidence struct:
```go
spent, max, pct := a.router.BudgetState()
ev.BudgetSpent = spent
ev.BudgetMax = max
ev.BudgetPercentage = pct
```

**Step 3: Run tests**

Run: `cd os/Skaffen && go test ./...`
Expected: PASS.

**Step 4: Commit**

```bash
cd os/Skaffen && git add internal/agent/deps.go internal/agent/loop.go internal/router/router.go && git commit -m "feat(evidence): include budget state and complexity tier in evidence emission"
```

<verify>
- run: `cd os/Skaffen && go test ./...`
  expect: exit 0
</verify>

---

### Task 10: End-to-end integration test

**Files:**
- Create: `internal/router/integration_test.go`

**Step 1: Write integration test**

Create `internal/router/integration_test.go`:

```go
package router

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/mistakeknot/Skaffen/internal/provider"
	"github.com/mistakeknot/Skaffen/internal/tool"
)

func TestFullRoutingPipeline(t *testing.T) {
	// Setup: JSON config with budget and complexity
	dir := t.TempDir()
	path := filepath.Join(dir, "routing.json")
	data := `{
		"phases": {"review": "haiku"},
		"budget": {"max_tokens": 10000, "mode": "graceful", "degrade_at": 0.8},
		"complexity": {"mode": "shadow"}
	}`
	if err := os.WriteFile(path, []byte(data), 0644); err != nil {
		t.Fatal(err)
	}

	cfg, err := LoadConfig(path)
	if err != nil {
		t.Fatal(err)
	}
	r := New(cfg)

	// Turn 1: brainstorm → should be opus (phase default, not overridden)
	model, reason := r.SelectModel(tool.PhaseBrainstorm)
	if model != ModelOpus {
		t.Errorf("turn1 brainstorm: model = %q, want opus", model)
	}
	if reason != "phase-default" {
		t.Errorf("turn1: reason = %q", reason)
	}

	// Turn 2: review → should be haiku (config override)
	model, reason = r.SelectModel(tool.PhaseReview)
	if model != ModelHaiku {
		t.Errorf("turn2 review: model = %q, want haiku", model)
	}
	if reason != "config-file" {
		t.Errorf("turn2: reason = %q, want config-file", reason)
	}

	// Record usage: 8000 tokens → 80% of budget → should degrade
	r.RecordUsage(provider.Usage{InputTokens: 5000, OutputTokens: 3000})
	model, reason = r.SelectModel(tool.PhaseBrainstorm)
	if model != ModelHaiku {
		t.Errorf("after 80%%: model = %q, want haiku (degraded)", model)
	}
	if reason != "budget-degrade" {
		t.Errorf("after 80%%: reason = %q, want budget-degrade", reason)
	}

	// Budget state check
	spent, max, pct := r.BudgetState()
	if spent != 8000 {
		t.Errorf("spent = %d, want 8000", spent)
	}
	if max != 10000 {
		t.Errorf("max = %d, want 10000", max)
	}
	if pct < 0.79 || pct > 0.81 {
		t.Errorf("pct = %f, want ~0.8", pct)
	}
}

func TestEnvVarOverridesJSON(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "routing.json")
	data := `{"phases": {"build": "haiku"}}`
	if err := os.WriteFile(path, []byte(data), 0644); err != nil {
		t.Fatal(err)
	}

	cfg, _ := LoadConfig(path)
	t.Setenv("SKAFFEN_MODEL_BUILD", "opus")
	r := New(cfg)

	model, reason := r.SelectModel(tool.PhaseBuild)
	if model != ModelOpus {
		t.Errorf("model = %q, want opus (env overrides JSON)", model)
	}
	if reason != "env-override" {
		t.Errorf("reason = %q, want env-override", reason)
	}
}
```

**Step 2: Run all tests**

Run: `cd os/Skaffen && go test ./... -v`
Expected: PASS (all tests including integration).

**Step 3: Commit**

```bash
cd os/Skaffen && git add internal/router/integration_test.go && git commit -m "test(router): end-to-end integration tests for full routing pipeline"
```

<verify>
- run: `cd os/Skaffen && go test ./... -v`
  expect: exit 0
</verify>

---

### Task 11: Live test via tmux

**Files:** None (verification only)

**Step 1: Build the binary**

```bash
cd os/Skaffen && go build -o /tmp/skaffen ./cmd/skaffen
```

**Step 2: Test default routing (no config file)**

```bash
tmux send-keys -t warp-skaffen-skaffen "echo 'what is 2+2?' | /tmp/skaffen --phase brainstorm 2>&1 | head -5" Enter
sleep 8
tmux capture-pane -t warp-skaffen-skaffen -p -S -10
```

Verify: stderr shows model selection happening (opus for brainstorm phase).

**Step 3: Test --budget flag**

```bash
tmux send-keys -t warp-skaffen-skaffen "echo 'hello' | /tmp/skaffen --budget 100 2>&1 | tail -3" Enter
sleep 8
tmux capture-pane -t warp-skaffen-skaffen -p -S -10
```

Verify: output includes token usage info.

**Step 4: Test env var override**

```bash
tmux send-keys -t warp-skaffen-skaffen "SKAFFEN_MODEL_BUILD=haiku echo 'hello' | /tmp/skaffen 2>&1 | tail -3" Enter
```

<verify>
- run: `cd os/Skaffen && go build -o /tmp/skaffen ./cmd/skaffen`
  expect: exit 0
</verify>

---

### Task 12: Update PRD checkboxes

**Files:**
- Modify: `docs/prds/2026-03-11-skaffen-go-rewrite.md` (check off F4 items)
- Modify: `docs/prds/2026-03-11-skaffen-f4-model-routing.md` (check off items)

**Step 1: Check off all completed acceptance criteria**

In `docs/prds/2026-03-11-skaffen-f4-model-routing.md`, change all `- [ ]` to `- [x]` for completed items.

In `docs/prds/2026-03-11-skaffen-go-rewrite.md`, check off the F4 items.

**Step 2: Commit**

```bash
git add docs/prds/ && git commit -m "docs: check off F4 model routing acceptance criteria"
```

<verify>
- run: `grep -c '\- \[x\]' docs/prds/2026-03-11-skaffen-f4-model-routing.md`
  expect: exit 0
</verify>
