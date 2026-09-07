---
artifact_type: plan
bead: sylveste-axo3
stage: design
---
# Ockham Wave 2 Wiring — Harden + Integration Test

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** sylveste-axo3
**Goal:** Close the Wave 2 compose story — fix a latent fast-path signal-name bug, add an end-to-end integration test, and make the pipeline's Unknown-verdict and parse behavior robust.

**Architecture:** The compose pipeline already exists — `trigger.Pipeline.OnSignal` wires F3 confirm, F4 fast path, F5 interspect pairing, F6 in-flight, F7 release, F8 writer. It is invoked from `cmd/ockham/check.go:runTriggerPipeline` (commit af9ae5d). Unit tests cover `trigger/` and `anomaly/` packages. Gap: no cmd-level integration test, a signal-name mismatch silently disables F4 for drift, and two robustness paths (Unknown verdict default, prev_drift parse) could regress.

**Tech Stack:** Go 1.22+, `github.com/mistakeknot/Ockham`, `signals.DB` (SQLite), `testing` stdlib, `os/exec` for bd stub.

**Prior Learnings:**
- `feedback_docs_match_codebase_not_memory` applies — bead description was written before af9ae5d landed. Plan is scoped to what's actually missing.
- `feedback_always_file_followup_bead` — any deferred hardening goes to a child bead, not a comment.

---

## Must-Haves

**Truths** (observable behaviors):
- `ockham check` run against a seeded DB with drift >40 pp between windows fires CONSTRAIN via F4 fast-path (not via 3-cycle confirm streak).
- `ockham check` with 3 consecutive tripped drift windows fires CONSTRAIN via F3 confirm streak.
- A running CONSTRAIN observing 5 consecutive clean windows is released by F7.
- When `interspect.Verdict == Healthy`, pipeline blocks fire; when `Unknown` the behavior is governed by an explicit policy knob and is unit-tested in both branches.
- Weight-offset file at the plumbed `WeightsPath` reflects constrain changes after each fire/release.

**Artifacts**:
- `os/Ockham/cmd/ockham/check.go` exports fixed `runTriggerPipeline` (signal name corrected, prev_drift parse hardened).
- `os/Ockham/cmd/ockham/check_test.go` (NEW) exports `TestRunTriggerPipeline_FirePath`, `TestRunTriggerPipeline_FastPath`, `TestRunTriggerPipeline_ReleasePath`, `TestRunTriggerPipeline_HealthyBlocksFire`.
- `os/Ockham/internal/trigger/pipeline.go` exports `Config.UnknownVerdictBlocks bool` and honors it.

**Key Links**:
- `check.go:runTriggerPipeline` → `trigger.Pipeline.OnSignal` → (`constrain.Controller`, `writer.Writer`, `interspect.Checker`, `inflight.Controller`) — all wired; fast-path dependency broken by signal-name mismatch until Task 1 lands.
- `interspect.Checker.AgreesUnhealthy` → `pipeline.handleTripped` → `p.fire` — Unknown verdict currently falls through to fire; Task 4 makes this explicit.

---

## Prior Learnings

No `docs/solutions/` frontmatter matched `anomaly|evaluator|constrain|inflight`. `docs/plans/2026-04-04-ockham-f4-check-hook.md` and `2026-04-06-ockham-f7-health-bypass.md` give the F4 and F7 reference designs; consult when editing their tasks.

---

### Task 1: Fix fast-path signal name mismatch

**Files:**
- Modify: `os/Ockham/cmd/ockham/check.go:182` (change `Signal: "drift"` → `Signal: "drift_pct"`)
- Test: `os/Ockham/cmd/ockham/check_test.go` (created in Task 2; assertion added in Task 3 fast-path case)

**Context:** `DefaultFastPathPolicy` in `internal/constrain/fastpath.go:20-29` registers `"drift_pct"` with a 0.40 threshold. `check.go` constructs the `trigger.Input` with `Signal: "drift"` — unlisted signals fall through to `DefaultThreshold: 0`, which the policy explicitly treats as "never fire." F4 is silently disabled for the one metric the evaluator actually produces.

**Step 1: Confirm the mismatch with a targeted grep**
```bash
grep -n "Signal:\|\"drift_pct\"\|\"drift\"" os/Ockham/cmd/ockham/check.go os/Ockham/internal/constrain/fastpath.go
```
Expected: `check.go` passes `"drift"`; `fastpath.go` Thresholds key is `"drift_pct"`.

**Step 2: Edit check.go**
Change the `trigger.Input` literal at line 182 (inside `runTriggerPipeline`):
```go
in := trigger.Input{
    Theme:    theme,
    Signal:   "drift_pct",  // must match constrain.DefaultFastPathPolicy key
    Tripped:  sig.Status == anomaly.StatusFired,
    Previous: prev,
    Current:  sig.DriftPct,
    Reason:   fmt.Sprintf("INFORM status=%s drift=%.1f%%", sig.Status, sig.DriftPct*100),
}
```

**Step 3: Build**
```bash
cd os/Ockham && go build ./...
```
Expected: exit 0.

**Step 4: Commit**
```bash
git add cmd/ockham/check.go
git commit -m "fix(ockham): use drift_pct signal key so F4 fast path actually fires (sylveste-axo3)"
```

<verify>
- run: `cd os/Ockham && go build ./...`
  expect: exit 0
- run: `grep -c '"drift_pct"' os/Ockham/cmd/ockham/check.go`
  expect: contains "1"
</verify>

---

### Task 2: cmd/ockham integration test harness

**Files:**
- Create: `os/Ockham/cmd/ockham/check_test.go`
- Reference: `os/Ockham/internal/trigger/pipeline_test.go` for helper patterns, `os/Ockham/internal/interspect/interspect_test.go:127-180` for fake-evidence format.

**Context:** `runTriggerPipeline` reads `signals.DB`, writes a weight file via `writer.DefaultPath()`, and reads interspect evidence via `interspect.NewReader("")` (which resolves to `~/.clavain/interspect/confidence.json`). The harness must redirect every external path to temp dirs so parallel tests do not stomp each other and so nothing touches the operator's real state.

**Step 1: Write the scaffold (no assertions yet)**
```go
package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/mistakeknot/Ockham/internal/anomaly"
	"github.com/mistakeknot/Ockham/internal/signals"
)

// testEnv bundles the tempdir-isolated state a runTriggerPipeline test needs.
type testEnv struct {
	t           *testing.T
	homeDir     string // overrides $HOME so interspect reader finds our fake
	db          *signals.DB
	weightsPath string
}

func newTestEnv(t *testing.T) *testEnv {
	t.Helper()
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("XDG_DATA_HOME", filepath.Join(home, ".local", "share"))

	dbPath := filepath.Join(t.TempDir(), "signals.db")
	db, err := signals.NewDB(dbPath)
	if err != nil {
		t.Fatalf("signals.NewDB: %v", err)
	}
	t.Cleanup(func() { db.Close() })

	return &testEnv{
		t:           t,
		homeDir:     home,
		db:          db,
		weightsPath: filepath.Join(t.TempDir(), "weights.json"),
	}
}

// writeInterspectEvidence writes a confidence.json the interspect checker
// will pick up. Pass generatedAt=time.Now() for fresh; staler times mark the
// evidence as Unknown.
func (e *testEnv) writeInterspectEvidence(highRetry []string, generatedAt time.Time) {
	e.t.Helper()
	dir := filepath.Join(e.homeDir, ".clavain", "interspect")
	if err := os.MkdirAll(dir, 0755); err != nil {
		e.t.Fatalf("mkdir interspect: %v", err)
	}
	evidence := map[string]any{
		"generated_at":      generatedAt.Format(time.RFC3339),
		"high_retry_themes": highRetry,
		"categories":        map[string]any{},
	}
	data, _ := json.Marshal(evidence)
	if err := os.WriteFile(filepath.Join(dir, "confidence.json"), data, 0644); err != nil {
		e.t.Fatalf("write evidence: %v", err)
	}
}

// seedFiredSignal preloads signal_state so runTriggerPipeline sees Tripped=true.
func (e *testEnv) seedFiredSignal(theme string, driftPct float64) {
	e.t.Helper()
	sig := anomaly.ThemeSignal{
		Theme:      theme,
		Status:     anomaly.StatusFired,
		DriftPct:   driftPct,
		LastEvalAt: time.Now().Unix(),
	}
	data, _ := json.Marshal(sig)
	if err := e.db.SetSignalState("inform:"+theme, string(data), sig.LastEvalAt); err != nil {
		e.t.Fatalf("seed signal: %v", err)
	}
}

// setPrevDrift plants the prior window so F4 fast-path can compute delta.
func (e *testEnv) setPrevDrift(theme string, prev float64) {
	e.t.Helper()
	if err := e.db.SetSignalState("prev_drift:"+theme,
		/* %f */ formatFloat(prev), time.Now().Unix()); err != nil {
		e.t.Fatalf("seed prev_drift: %v", err)
	}
}

func formatFloat(f float64) string { return fmtSprintf("%f", f) }

// fmtSprintf is a local alias so the helper doesn't require an extra import
// at the top of the test file when we later narrow imports. It exists to
// keep seed helpers readable.
func fmtSprintf(format string, a ...any) string {
	return fmtSprintfInternal(format, a...)
}
```
Replace the `fmtSprintf` aliasing with a direct `fmt.Sprintf` import if lint complains — it is spelled out here to keep each helper grep-able.

**Step 2: Build the scaffold, confirm it compiles**
```bash
cd os/Ockham && go test ./cmd/ockham/ -run NoTests -count=1 2>&1 | tail -5
```
Expected: exit 0, `ok` with no tests run.

**Step 3: Commit scaffold (tests added next task)**
```bash
git add cmd/ockham/check_test.go
git commit -m "test(ockham): scaffold runTriggerPipeline integration test harness (sylveste-axo3)"
```

<verify>
- run: `cd os/Ockham && go vet ./cmd/ockham/`
  expect: exit 0
- run: `cd os/Ockham && go test ./cmd/ockham/ -run NoTests -count=1`
  expect: contains "ok"
</verify>

---

### Task 3: Integration tests — fire / fast-path / release / Healthy-blocks

**Files:**
- Modify: `os/Ockham/cmd/ockham/check_test.go` (add four test funcs using the harness)
- Depends: Task 1 (signal-name fix so fast-path can actually fire), Task 2 (scaffold)

**Context:** These tests call `CheckRunner.runTriggerPipeline` directly with a pre-built `anomaly.State` — avoiding the `bd` shell-out and the full `runCheck` path. The pipeline-internal calls to `constrain`, `writer`, and `interspect` are exercised end-to-end.

**Step 1: Fire-path test (F3 confirm streak)**
Append to `check_test.go`:
```go
func TestRunTriggerPipeline_FirePath(t *testing.T) {
	env := newTestEnv(t)
	env.writeInterspectEvidence([]string{"auth"}, time.Now())

	runner := &CheckRunner{db: env.db}
	// Override writer path via direct pipeline construction is not possible
	// without refactoring runTriggerPipeline; instead override the
	// WeightsPath seam. Task 3.1 below adds a CheckRunner.weightsPath field.

	state := anomaly.State{
		Signals: map[string]anomaly.ThemeSignal{
			"auth": {Theme: "auth", Status: anomaly.StatusFired, DriftPct: 0.10},
		},
	}

	// Three tripped observations to trigger the 3-count confirm streak.
	for i := 0; i < 3; i++ {
		if err := runner.runTriggerPipeline(state); err != nil {
			t.Fatalf("cycle %d: %v", i, err)
		}
	}

	active, _, err := (&constrain.Controller{}).IsConstrained("auth") // placeholder — see Step 2
	_ = active
	_ = err
	// Replaced by: `runner.db`-backed constrain controller inspection in Step 2.
}
```

> **Seam requirement:** `runTriggerPipeline` currently hardcodes `writer.DefaultPath()` inside the pipeline config. For this test to target a temp file, hoist the weights path to a `CheckRunner.weightsPath string` field (default empty → falls back to `writer.DefaultPath()`). Adjust `check.go:runTriggerPipeline` to read `r.weightsPath` when non-empty. This is a **required sub-step of Task 3**, not a separate task — the integration test is unbuildable without it.

**Step 2: Hoist weightsPath seam in check.go**
```go
// In CheckRunner struct add:
weightsPath string // optional override; empty means writer.DefaultPath()

// In runTriggerPipeline, compute:
wp := r.weightsPath
if wp == "" { wp = writer.DefaultPath() }
// Pass wp via trigger.Config{WeightsPath: wp, ...}.
```
Already supported by `trigger.Config.WeightsPath` — just needs to be threaded through.

**Step 3: Finish fire-path assertion**
```go
// in TestRunTriggerPipeline_FirePath, after the 3-cycle loop:
ctrl := constrain.New(env.db)
active, _, err := ctrl.IsConstrained("auth")
if err != nil {
	t.Fatalf("IsConstrained: %v", err)
}
if !active {
	t.Fatalf("want CONSTRAIN active after 3 confirm cycles, got none")
}

raw, err := os.ReadFile(env.weightsPath)
if err != nil {
	t.Fatalf("read weights: %v", err)
}
var weights struct {
	Themes map[string]int `json:"themes"`
}
if err := json.Unmarshal(raw, &weights); err != nil {
	t.Fatalf("parse weights: %v", err)
}
if got := weights.Themes["auth"]; got >= 0 {
	t.Fatalf("auth offset = %d, want negative (constrained)", got)
}
```

**Step 4: Fast-path test (F4 single-cycle fire)**
```go
func TestRunTriggerPipeline_FastPath(t *testing.T) {
	env := newTestEnv(t)
	env.writeInterspectEvidence([]string{"auth"}, time.Now())
	env.setPrevDrift("auth", 0.05)

	runner := &CheckRunner{db: env.db, weightsPath: env.weightsPath}
	state := anomaly.State{
		Signals: map[string]anomaly.ThemeSignal{
			// DriftPct jump from 0.05 → 0.50 is > 0.40 threshold.
			"auth": {Theme: "auth", Status: anomaly.StatusFired, DriftPct: 0.50},
		},
	}
	if err := runner.runTriggerPipeline(state); err != nil {
		t.Fatalf("runTriggerPipeline: %v", err)
	}

	active, rec, err := constrain.New(env.db).IsConstrained("auth")
	if err != nil {
		t.Fatalf("IsConstrained: %v", err)
	}
	if !active {
		t.Fatal("want CONSTRAIN via fast path, got none")
	}
	if !rec.FastPath {
		t.Fatalf("want FastPath=true, got %+v", rec)
	}
}
```

**Step 5: Release-path test (F7)**
```go
func TestRunTriggerPipeline_ReleasePath(t *testing.T) {
	env := newTestEnv(t)
	env.writeInterspectEvidence([]string{"auth"}, time.Now())
	env.setPrevDrift("auth", 0.05)

	runner := &CheckRunner{db: env.db, weightsPath: env.weightsPath}

	// Phase 1: fire via fast path.
	if err := runner.runTriggerPipeline(anomaly.State{
		Signals: map[string]anomaly.ThemeSignal{
			"auth": {Theme: "auth", Status: anomaly.StatusFired, DriftPct: 0.50},
		},
	}); err != nil {
		t.Fatalf("fire: %v", err)
	}

	// Phase 2: five clean cycles to meet DefaultStabilityPolicy (streak=5).
	for i := 0; i < 5; i++ {
		if err := runner.runTriggerPipeline(anomaly.State{
			Signals: map[string]anomaly.ThemeSignal{
				"auth": {Theme: "auth", Status: anomaly.StatusCleared, DriftPct: 0.02},
			},
		}); err != nil {
			t.Fatalf("clean cycle %d: %v", i, err)
		}
	}

	active, _, err := constrain.New(env.db).IsConstrained("auth")
	if err != nil {
		t.Fatalf("IsConstrained: %v", err)
	}
	if active {
		t.Fatal("want CONSTRAIN released after 5 stability cycles, still active")
	}
}
```

**Step 6: Healthy-blocks test (F5)**
```go
func TestRunTriggerPipeline_HealthyBlocksFire(t *testing.T) {
	env := newTestEnv(t)
	// Fresh evidence that does NOT list auth as high-retry → Verdict == Healthy.
	env.writeInterspectEvidence([]string{"other"}, time.Now())
	env.setPrevDrift("auth", 0.05)

	runner := &CheckRunner{db: env.db, weightsPath: env.weightsPath}
	// Fast-path-sized jump — would normally fire.
	if err := runner.runTriggerPipeline(anomaly.State{
		Signals: map[string]anomaly.ThemeSignal{
			"auth": {Theme: "auth", Status: anomaly.StatusFired, DriftPct: 0.50},
		},
	}); err != nil {
		t.Fatalf("runTriggerPipeline: %v", err)
	}

	active, _, err := constrain.New(env.db).IsConstrained("auth")
	if err != nil {
		t.Fatalf("IsConstrained: %v", err)
	}
	if active {
		t.Fatal("want fire blocked by Healthy verdict, got CONSTRAIN")
	}
}
```

**Step 7: Run full test suite**
```bash
cd os/Ockham && go test ./cmd/ockham/ -v -count=1
```
Expected: all four `TestRunTriggerPipeline_*` tests PASS.

**Step 8: Commit**
```bash
git add cmd/ockham/check.go cmd/ockham/check_test.go
git commit -m "test(ockham): end-to-end runTriggerPipeline integration coverage (sylveste-axo3)"
```

<verify>
- run: `cd os/Ockham && go test ./cmd/ockham/ -run TestRunTriggerPipeline -v -count=1`
  expect: contains "PASS"
- run: `cd os/Ockham && go test ./... -count=1`
  expect: exit 0
</verify>

---

### Task 4: UnknownVerdictBlocks policy knob

**Files:**
- Modify: `os/Ockham/internal/trigger/pipeline.go` (add field + branch)
- Modify: `os/Ockham/internal/trigger/pipeline_test.go` (two new table rows)

**Context:** `handleTripped` at `pipeline.go:166-177` treats any non-Healthy verdict as permissive — including `Unknown` (no evidence / stale). The bead description's "Unknown-with-low-threshold-policy" phrasing calls for this to be an operator decision. Default stays permissive to preserve current behavior; opt-in tightening via config.

**Step 1: Failing test — Unknown verdict blocks when flag set**
Add to `internal/trigger/pipeline_test.go`:
```go
func TestPipeline_UnknownVerdictBlocks_WhenConfigured(t *testing.T) {
	// Build a pipeline with UnknownVerdictBlocks=true and an interspect
	// Checker whose evidence file does not exist → AgreesUnhealthy returns
	// VerdictUnknown.
	// Assertion: a tripped + confirmed input does NOT fire.
	// [full test body — mirror TestPipeline_FiresAfterConfirmStreak pattern]
}
```

**Step 2: Run to confirm failure**
```bash
cd os/Ockham && go test ./internal/trigger/ -run TestPipeline_UnknownVerdictBlocks -count=1
```
Expected: FAIL — fire still happens.

**Step 3: Implementation**
In `pipeline.go`:
```go
type Config struct {
    // ... existing fields
    // UnknownVerdictBlocks, when true, treats interspect.VerdictUnknown as
    // a block (same as VerdictHealthy). Default false preserves the
    // permissive behavior: only explicit Healthy blocks a fire.
    UnknownVerdictBlocks bool
}

type Pipeline struct {
    // ... existing fields
    unknownBlocks bool
}

// In New(): p.unknownBlocks = cfg.UnknownVerdictBlocks
```
In `handleTripped`, replace:
```go
if verdict == interspect.VerdictHealthy { return out, nil }
```
with:
```go
if verdict == interspect.VerdictHealthy ||
   (p.unknownBlocks && verdict == interspect.VerdictUnknown) {
    return out, nil
}
```

**Step 4: Run to confirm pass**
```bash
cd os/Ockham && go test ./internal/trigger/ -count=1
```
Expected: exit 0.

**Step 5: Commit**
```bash
git add internal/trigger/pipeline.go internal/trigger/pipeline_test.go
git commit -m "feat(ockham): UnknownVerdictBlocks policy knob on trigger pipeline (sylveste-axo3)"
```

<verify>
- run: `cd os/Ockham && go test ./internal/trigger/ -count=1`
  expect: exit 0
- run: `grep -c "UnknownVerdictBlocks" os/Ockham/internal/trigger/pipeline.go`
  expect: contains "2"
</verify>

---

### Task 5: Harden prev_drift parse

**Files:**
- Modify: `os/Ockham/cmd/ockham/check.go` (replace `fmt.Sscanf` with explicit parse)

**Context:** `check.go:178` uses `fmt.Sscanf(raw, "%f", &prev)` and discards the error. A malformed state-store entry silently yields `prev=0`, which makes a fast-path delta look larger than reality and can spurious-fire. Replace with `strconv.ParseFloat` + error log.

**Step 1: Implementation**
```go
import "strconv"

// Replace the Sscanf block with:
prev := 0.0
if raw, found, _ := r.db.GetSignalState("prev_drift:" + theme); found {
    if p, err := strconv.ParseFloat(strings.TrimSpace(raw), 64); err == nil {
        prev = p
    } else {
        fmt.Fprintf(os.Stderr, "ockham: prev_drift parse degraded for %q: %v\n", theme, err)
    }
}
```

**Step 2: Build**
```bash
cd os/Ockham && go build ./... && go vet ./...
```
Expected: exit 0.

**Step 3: Commit**
```bash
git add cmd/ockham/check.go
git commit -m "fix(ockham): harden prev_drift parse — log and zero on malformed state (sylveste-axo3)"
```

<verify>
- run: `cd os/Ockham && go build ./... && go vet ./...`
  expect: exit 0
- run: `grep -c "strconv.ParseFloat" os/Ockham/cmd/ockham/check.go`
  expect: contains "1"
</verify>

---

### Task 6: Wire tasks through beads + changelog entry

**Files:**
- Modify: `os/Ockham/docs/CHANGELOG.md` if it exists, else skip this step and note in bead close reason.

**Step 1: Close bead on completion**
```bash
bd close sylveste-axo3 --reason="Wave 2 compose shipped af9ae5d; hardened + integration-tested (signal-name fix, 4 end-to-end tests, UnknownVerdictBlocks knob, prev_drift parse)"
```
**Irreversible — confirm with user before running.**

**Step 2: Backup**
```bash
bd backup
```

<verify>
- run: `bd show sylveste-axo3 | head -1`
  expect: contains "closed"
</verify>

---

## Open Questions

- Should `UnknownVerdictBlocks` default flip to `true` once an operator has a stable interspect feed? Decision deferred — new-default change warrants its own bead if adopted.
- Config plumbing for `DefaultConfirmPolicy` / `DefaultStabilityPolicy` (currently hardcoded in `check.go:159-161`) — left out deliberately. File as follow-up bead if operator wants per-deployment tuning.

---

## Execution Notes

This plan has 5 independent Wave-1 tasks (1, 2, 4, 5, 6) and 1 dependent Wave-2 task (3 depends on 1 + 2). A `.exec.yaml` manifest is generated alongside so orchestrate.py can fan out.
