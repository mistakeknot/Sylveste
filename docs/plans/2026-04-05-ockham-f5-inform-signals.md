---
artifact_type: plan
bead: sylveste-usj
prd: docs/prds/2026-04-05-ockham-f5-inform-signals.md
stage: plan
---

# Plan: Ockham F5 — Tier 1 INFORM Signals + Pleasure Signals

4 features, 3 batches. All work in `os/Ockham/`. Tests run with `go test ./... -count=1`.

## Resolved Open Questions

- **first_attempt_pass_rate source**: Beads state transitions via `bd`. A bead that was closed without "rework" status transitions passed on first attempt. Gaming vector acknowledged (vision doc §Known Gaming Surface) — advisory-only, acceptable for Wave 1.
- **Interspect events**: Write via `signals.SetSignalState()` with keys prefixed `interspect:`. The ockham SessionStart hook already runs `ockham check` — interspect integration is fire-and-forget stderr logging for Wave 1 (no direct interspect API dependency). Full interspect event pipeline deferred to Wave 2.

## Batch 1: Foundation (F1) — signals.db schema v2 + anomaly types

**Goal:** Schema migration, bead_metrics CRUD, anomaly type definitions. No evaluation logic yet.

### Step 1.1: Schema v2 migration + bead_metrics CRUD

**File:** `internal/signals/db.go`

- Bump `currentSchemaVersion` from 1 to 2
- Add `bead_metrics` table to schema constant:
  ```sql
  CREATE TABLE IF NOT EXISTS bead_metrics (
      bead_id TEXT PRIMARY KEY,
      theme TEXT NOT NULL,
      cycle_time_ms INTEGER NOT NULL,
      pass_first_attempt INTEGER NOT NULL DEFAULT 0,
      cost_usd REAL,
      completed_at INTEGER NOT NULL
  );
  CREATE INDEX IF NOT EXISTS idx_bead_metrics_theme_completed
      ON bead_metrics(theme, completed_at DESC);
  ```
- In `migrateSchema()`: add v1→v2 migration path (CREATE TABLE + INDEX if not exists)
- Idempotency: use `IF NOT EXISTS` in both schema and migration

**File:** `internal/signals/metrics.go` (new)

- `InsertBeadMetric(bead_id, theme string, cycleTimeMs int64, passFirst bool, costUSD *float64, completedAt int64) error`
- `LatestBeadMetrics(theme string, limit int) ([]BeadMetric, error)` — query latest N by completed_at DESC, covering index
- `PruneBeadMetrics(theme string, keepCount int) (int64, error)` — delete rows older than the Nth most recent per theme
- `LastBeadCompletedAt(theme string) (int64, bool, error)` — for short-circuit check
- `BeadMetric` struct: BeadID, Theme, CycleTimeMs, PassFirstAttempt, CostUSD (*float64), CompletedAt

**File:** `internal/signals/metrics_test.go` (new)

- Insert + query round-trip
- Prune keeps exactly keepCount rows
- LatestBeadMetrics returns in completed_at DESC order
- LastBeadCompletedAt returns (0, false) on empty table

**Verify:** `go test ./internal/signals/... -count=1`

### Step 1.2: Anomaly types

**File:** `internal/anomaly/anomaly.go` — replace stub

```go
package anomaly

// SignalStatus represents the state of an INFORM signal for a theme.
type SignalStatus string

const (
    StatusCleared SignalStatus = "cleared"
    StatusFired   SignalStatus = "fired"
    StatusStale   SignalStatus = "stale"
)

// ThemeSignal holds the INFORM signal state for one theme.
type ThemeSignal struct {
    Theme           string
    Status          SignalStatus
    DriftPct        float64 // current drift percentage (0 = no drift)
    AdvisoryOffset  int     // recommended offset adjustment (0 or negative)
    ConsecutiveClears int   // consecutive evaluations below clear threshold
    LastEvalAt      int64   // unix timestamp of last evaluation
}

// PleasureTrend represents the direction of a pleasure signal.
type PleasureTrend string

const (
    TrendImproving PleasureTrend = "improving"
    TrendStable    PleasureTrend = "stable"
    TrendDegrading PleasureTrend = "degrading"
    TrendInsufficient PleasureTrend = "insufficient_data"
)

// PleasureSignal holds one pleasure signal for one theme.
type PleasureSignal struct {
    Name  string        // e.g., "first_attempt_pass_rate"
    Theme string
    Trend PleasureTrend
    Value float64       // current value (rate or p50)
}

// State carries the full anomaly evaluation result.
// Consumed by governor.Evaluate() and scoring.Score().
type State struct {
    Signals  map[string]ThemeSignal  // key: theme name
    Pleasure []PleasureSignal
}
```

**File:** `internal/anomaly/anomaly_test.go` (new)

- State with zero value is safe to read (empty maps)
- SignalStatus string constants match expected values

**Verify:** `go test ./internal/anomaly/... -count=1`

### Step 1.3: Build check

`go build ./cmd/ockham && go vet ./...`

Existing tests must still pass — the anomaly.State change from empty struct to struct-with-fields should be backward compatible since scoring.Score() currently ignores the anomaly argument.

---

## Batch 2: Detection Logic (F2 + F3) — drift detection + pleasure signals

**Goal:** Core evaluation logic. All pure functions operating on BeadMetric slices — no CLI, no governor wiring yet.

### Step 2.1: Weight-drift detection

**File:** `internal/anomaly/drift.go` (new)

```go
// Config holds drift detection parameters.
type Config struct {
    MinWindow       int     // minimum beads for evaluation (default 10)
    MaxWindow       int     // adaptive: use up to this many beads (default 30)
    FireThreshold   float64 // drift pct to fire INFORM (default 0.20)
    ClearThreshold  float64 // drift pct to clear INFORM (default 0.10)
    ClearCount      int     // consecutive clears needed (default 3)
    MaxAdvisoryPerCycle int // rate limit: max offset reduction per theme per cycle (default 1)
    FactoryGuard    int     // max sum of advisory reductions across all themes (default 12)
    StaleDays       int     // days without new beads → stale (default 14)
}

func DefaultConfig() Config { ... }
```

- `EvaluateDrift(metrics []signals.BeadMetric, prior ThemeSignal, cfg Config) ThemeSignal`
  - If len(metrics) < cfg.MinWindow → return prior unchanged (insufficient data)
  - Split metrics into baseline (older half) and recent (newer half)
  - Compute p50 cycle time for each half using `medianCycleTime()`
  - Drift = (recent_p50 - baseline_p50) / baseline_p50
  - Fire: drift >= cfg.FireThreshold AND prior.Status != Fired → Status=Fired, AdvisoryOffset=-1
  - Clear: drift < cfg.ClearThreshold → increment ConsecutiveClears; if >= cfg.ClearCount → Status=Cleared, AdvisoryOffset=0
  - Already fired + drift still >= ClearThreshold → maintain Fired, AdvisoryOffset stays (rate-limited, already -1)
  - Stale: handled by caller (check LastBeadCompletedAt)

- `ApplyFactoryGuard(signals map[string]ThemeSignal, guard int) map[string]ThemeSignal`
  - Sum absolute advisory offsets. If > guard, proportionally reduce offsets (heaviest themes first).

- `medianCycleTime(metrics []signals.BeadMetric) float64` — sort by CycleTimeMs, return middle value. For even-length slices, use float64 average of two middle values (not integer division).

**File:** `internal/anomaly/drift_test.go` (new)

Table-driven tests:
- Insufficient data (< MinWindow) → no change
- 20% drift fires signal
- 15% drift (between thresholds) → remains in prior state
- 9% drift for 3 consecutive evals → clears
- Hysteresis: 19% drift does not clear a fired signal (above ClearThreshold)
- Factory guard caps total advisory
- Adaptive window: uses up to MaxWindow beads when available

### Step 2.2: Pleasure signals

**File:** `internal/anomaly/pleasure.go` (new)

- `EvaluatePassRate(metrics []signals.BeadMetric, minWindow int) PleasureSignal`
  - Count pass_first_attempt / total in window
  - Compare current half vs prior half: improving if rate increased, degrading if decreased, stable otherwise
  - < minWindow → TrendInsufficient

- `EvaluateCycleTimeTrend(metrics []signals.BeadMetric, minWindow int) PleasureSignal`
  - Compare p50 of recent half vs baseline half
  - Improving if p50 decreased (faster), degrading if increased

- `EvaluateCostTrend(metrics []signals.BeadMetric, minWindow int) PleasureSignal`
  - Same split logic but on cost_usd field
  - Skip metrics where cost_usd is nil (unavailable)
  - If all nil → TrendInsufficient

**File:** `internal/anomaly/pleasure_test.go` (new)

Table-driven tests:
- Improving: recent half has better metrics than baseline
- Degrading: recent half is worse
- Stable: within ~5% tolerance
- Insufficient data: < minWindow
- Cost with nil values: graceful degradation

### Step 2.3: Build + full test

`go test ./internal/anomaly/... -count=1 -v`

---

## Batch 3: Integration (F4) — governor wiring + CLI

**Goal:** Wire everything together. Scoring accepts anomaly state. Governor runs evaluation. CLI exposes signals.

### Step 3.1: Scoring integration

**File:** `internal/scoring/types.go`

- Add `AdvisoryOffsets map[string]int` field to... actually, advisory offsets come from anomaly.State.Signals[theme].AdvisoryOffset. Scoring should read this.

**File:** `internal/scoring/scorer.go`

- Update `Score()` signature: `func Score(iv intent.IntentVector, _ authority.State, an anomaly.State, beads []BeadInfo) WeightVector`
  - **Nil-guard (P0 fix):** if `an.Signals == nil`, treat as zero advisory (no offset adjustment). Existing tests pass `anomaly.State{}` with nil maps — must not panic.
  - **Lane normalization (P1 fix):** normalize empty lane to `"open"` before anomaly signal lookup, same as intent lookup
  - After computing intent offset, add anomaly advisory offset for the bead's theme
  - Re-clamp combined result to [OffsetMin, OffsetMax]
  - Record both raw (intent-only) and final (intent+advisory) — add `RawOffsets` field to WeightVector

**File:** `internal/scoring/types.go`

- Add `RawOffsets map[string]int` to WeightVector (for dual logging)

**File:** `internal/scoring/scorer_test.go`

- New test: advisory offset applied additively
- New test: combined offset clamped to [-6, +6]
- New test: zero anomaly state → same behavior as before (backward compat)

### Step 3.2: Anomaly evaluator (orchestrator)

**File:** `internal/anomaly/evaluator.go` (new)

```go
// Evaluator orchestrates signal evaluation across all themes.
type Evaluator struct {
    db  *signals.DB
    cfg Config
}

func NewEvaluator(db *signals.DB, cfg Config) *Evaluator { ... }

// Evaluate runs drift detection and pleasure signals for all themes.
// Returns the full State. Handles short-circuit, staleness, and degradation.
func (e *Evaluator) Evaluate(themes []string, now int64) (State, error) {
    state := State{
        Signals:  make(map[string]ThemeSignal, len(themes)),
        Pleasure: make([]PleasureSignal, 0, len(themes)*3),
    }
    for _, theme := range themes {
        // Short-circuit: check if new beads since last eval
        lastCompleted, found, err := e.db.LastBeadCompletedAt(theme)
        if err != nil { return state, err }

        // Load prior signal state from signal_state table
        prior := e.loadPriorSignal(theme)

        if !found || lastCompleted <= prior.LastEvalAt {
            state.Signals[theme] = prior // no new data
            continue
        }

        // Staleness check
        staleThreshold := now - int64(e.cfg.StaleDays*86400)
        if lastCompleted < staleThreshold {
            state.Signals[theme] = ThemeSignal{
                Theme: theme, Status: StatusStale, LastEvalAt: now,
            }
            e.persistSignal(theme, state.Signals[theme])
            continue
        }

        // Fetch rolling window
        metrics, err := e.db.LatestBeadMetrics(theme, e.cfg.MaxWindow)
        if err != nil { return state, err }

        // Drift detection
        signal := EvaluateDrift(metrics, prior, e.cfg)
        signal.LastEvalAt = now
        state.Signals[theme] = signal

        // Pleasure signals
        state.Pleasure = append(state.Pleasure,
            EvaluatePassRate(metrics, e.cfg.MinWindow),
            EvaluateCycleTimeTrend(metrics, e.cfg.MinWindow),
            EvaluateCostTrend(metrics, e.cfg.MinWindow),
        )

        // Persist
        e.persistSignal(theme, signal)
        e.persistPleasure(theme, state.Pleasure[len(state.Pleasure)-3:])

        // Prune old data
        e.db.PruneBeadMetrics(theme, e.cfg.MaxWindow*2)
    }

    // Factory guard
    state.Signals = ApplyFactoryGuard(state.Signals, e.cfg.FactoryGuard)

    return state, nil
}
```

Helper methods: `loadPriorSignal`, `persistSignal`, `persistPleasure` — read/write `signal_state` table via `db.GetSignalState`/`db.SetSignalState`.

**File:** `internal/anomaly/evaluator_test.go` (new)

- Full evaluation with DB (t.TempDir() + signals.NewDB)
- Short-circuit: no new beads → prior state unchanged
- Staleness: old beads → stale status
- Factory guard applied after all themes evaluated
- Multiple themes evaluated independently

### Step 3.3: Governor wiring

**File:** `internal/governor/governor.go`

- Add `anomaly *anomaly.Evaluator` field to Governor struct
- Update `New()` to accept optional evaluator (nil = Wave 1 stub behavior for backward compat)
- In `Evaluate()`: if evaluator non-nil, call `evaluator.Evaluate(themes, now)` to get anomaly.State
- Pass anomaly.State to `scoring.Score()`

**File:** `internal/governor/governor_test.go`

- Existing tests pass unchanged (nil evaluator = stub behavior)
- New test: with evaluator, advisory offsets apply
- New test: halted factory skips signal evaluation (INV-8)

### Step 3.4: ockham check integration

**File:** `cmd/ockham/check.go`

- Add step between authority snapshot and reconfirmation:
  ```go
  // Step 2: Evaluate signals
  if err := runner.evaluateSignals(); err != nil {
      fmt.Fprintf(os.Stderr, "ockham: signal evaluation degraded: %v\n", err)
  }
  ```
- `evaluateSignals()`: open signals.DB, create Evaluator with DefaultConfig(), get themes as union of: (1) open bead lanes from beadsFromBD, (2) distinct themes in bead_metrics table, (3) existing signal_state keys matching `inform:*`. Run Evaluate(), log transitions to stderr
- Ingest new bead metrics: before evaluation, call `ingestBeadMetrics()` which shells out to `bd list --status=closed --json` and inserts new completions into bead_metrics (skip duplicates via bead_id uniqueness)

### Step 3.5: ockham signals CLI

**File:** `cmd/ockham/signals.go` (new)

- `ockham signals` command — shows per-theme INFORM state and pleasure signals
- Reads directly from signals.db signal_state table
- Output: table with Theme | INFORM | Drift% | Advisory | PassRate | CycleTime | Cost | LastEval

### Step 3.6: Final build + full test suite

```bash
cd os/Ockham && go test ./... -count=1 -v && go build ./cmd/ockham && go vet ./...
```

---

## Execution Order

```
Batch 1 (F1): Schema + types           [~45 min]
  1.1 → 1.2 → 1.3 (sequential — schema before types, build check last)

Batch 2 (F2+F3): Detection logic       [~60 min]
  2.1 ∥ 2.2 (parallel — drift and pleasure are independent)
  2.3 (sequential — after both)

Batch 3 (F4): Integration              [~60 min]
  3.1 → 3.2 → 3.3 → 3.4 → 3.5 → 3.6 (sequential — each builds on prior)
```

## Risk Mitigation

- **bd CLI unavailable**: evaluateSignals() catches error, logs degraded mode, continues. No false all-clear.
- **Schema migration on existing DB**: idempotent (IF NOT EXISTS). Tested in step 1.1.
- **Scoring API change**: anomaly.State is backward-compatible (zero value = no advisory offsets). Existing tests pass without modification.
- **cost-query.sh format change**: cost_usd is nullable. nil → TrendInsufficient.
