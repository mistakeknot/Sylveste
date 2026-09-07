---
artifact_type: plan
bead: sylveste-xefe
stage: plan
sources:
  - docs/brainstorms/2026-04-07-ockham-alwe-observation-bridge.md
  - docs/prds/2026-04-14-ockham-alwe-observation-bridge.md
---

# Plan: Ockham-Alwe Observation Bridge

**Date:** 2026-04-14
**Epic:** sylveste-xefe
**Scope:** 5 features (F1-F5), all in Ockham's Go codebase + one Alwe refactor

---

## Prerequisites

Before any feature work, one structural change is needed: Alwe's observer is in `internal/observer/` which Go restricts to same-module imports. Since Ockham is a separate module, the observer must be moved to `pkg/observer/` in Alwe.

### Task 0: Move Alwe observer to pkg/observer (prerequisite)

**Files:**
- Move `os/Alwe/internal/observer/cass.go` → `os/Alwe/pkg/observer/cass.go`
- Move `os/Alwe/internal/observer/cass_test.go` → `os/Alwe/pkg/observer/cass_test.go`
- Update `os/Alwe/internal/mcpserver/` imports to use `pkg/observer`
- Verify: `cd os/Alwe && go test ./...`

**Commit from `os/Alwe/`** (separate git repo).

### Task 0b: Add Alwe dependency to Ockham go.mod

**Files:** `os/Ockham/go.mod`

Add:
```
require github.com/mistakeknot/Alwe v0.0.0
replace github.com/mistakeknot/Alwe => ../../Alwe
```

Run `cd os/Ockham && go mod tidy`.

**Verify Alwe under Ockham's Go version:** Ockham uses Go 1.25, Alwe uses 1.24. Run `cd os/Alwe && go test ./... -count=1` after Task 0 to confirm Alwe code works under the combined build's Go semantics.

---

## F1: Observation package + ObservationMetric type (sylveste-tm6g)

### Task 1.1: Define ObservationMetric type and Observer interface

**File:** `os/Ockham/internal/observation/types.go` (new)

```go
type ObservationMetric struct {
    Theme       string
    MetricType  string  // "session_completion_rate", "tool_error_rate"
    Value       float64 // 0.0-1.0 for rates
    CollectedAt int64   // unix epoch
}

type Observer interface {
    IsAvailable() bool
    Collect(ctx context.Context, themes []string, since time.Duration) ([]ObservationMetric, error)
}
```

Use an interface so tests can mock without CASS.

### Task 1.2: Implement CassObserver wrapping Alwe

**File:** `os/Ockham/internal/observation/cass_observer.go` (new)

- Struct wraps `*observer.CassObserver` from `github.com/mistakeknot/Alwe/pkg/observer`
- `IsAvailable()`: delegates to `observer.New()` — if error, return false
- `Collect()`: calls two query methods, transforms results into `[]ObservationMetric`

### Task 1.3: Session completion rate query

**In `cass_observer.go`:**

- Call `o.cass.Timeline(ctx, durationToString(since))` — Alwe's `Timeline` returns raw JSON string, not structured data. The `since` param is a string like `"24h"`, not `time.Duration`. Add `durationToString()` helper.
- Parse the raw JSON string into `[]TimelineEntry` (define struct matching CASS JSON schema: session_id, provider, timestamp, status)
- Count sessions with status `"done"` vs total sessions per theme (default "open" for F1)
- Return `ObservationMetric{MetricType: "session_completion_rate", Value: done/total}`

### Task 1.4: Tool error rate query

**In `cass_observer.go`:**

- Call `o.cass.SearchSessions(ctx, "error", "", limit)` — returns `[]SessionResult` (session-level hits, not event-level). `SearchSessions` finds sessions that contain error-related content.
- For each matching session, call `o.cass.ExportSession(ctx, session.FilePath)` to get the full JSONL, then count `tool_result` events with `is_error: true` vs total `tool_result` events.
- Alternative (simpler, less accurate): use the ratio of error-matching sessions to total sessions from timeline as a proxy. Choose this for F1 — exact tool-level error rates require per-session parsing which is expensive.
- Return `ObservationMetric{MetricType: "tool_error_rate", Value: errorSessions/totalSessions}`

### Task 1.5: Unit tests

**File:** `os/Ockham/internal/observation/cass_observer_test.go` (new)

- Mock `CassObserver` by implementing `Observer` interface
- Test `Collect()` returns correct metrics for known inputs
- Test `IsAvailable()` returns false when CASS unavailable
- Test empty timeline returns zero metrics (not error)

---

## F2: Schema v3 migration (sylveste-ki2p)

### Task 2.1: Add observation_metrics table

**File:** `os/Ockham/internal/signals/db.go`

- Bump `currentSchemaVersion` from 2 to 3
- Add migration in `ensureSchema()`:
  ```sql
  CREATE TABLE IF NOT EXISTS observation_metrics (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      theme TEXT NOT NULL,
      metric_type TEXT NOT NULL,
      value REAL NOT NULL,
      collected_at INTEGER NOT NULL
  );
  CREATE INDEX IF NOT EXISTS idx_obs_theme_type
      ON observation_metrics(theme, metric_type, collected_at DESC);
  ```

### Task 2.2: Add DB methods

**File:** `os/Ockham/internal/signals/db.go`

```go
func (d *DB) InsertObservation(theme, metricType string, value float64, collectedAt int64) error
func (d *DB) RecentObservations(theme, metricType string, since int64) ([]ObservationRow, error)
func (d *DB) PruneObservations(theme string, keepCount int) (int64, error)  // keepCount = number of rows to keep (matches PruneBeadMetrics convention)
```

### Task 2.3: Tests

**File:** `os/Ockham/internal/signals/db_test.go`

- Test schema migration v2→v3 preserves existing data
- Test InsertObservation + RecentObservations round-trip
- Test PruneObservations removes old entries

---

## F3: Evaluator integration (sylveste-ycck)

### Task 3.1: Add Observer to Evaluator

**File:** `os/Ockham/internal/anomaly/evaluator.go`

- Add `observer observation.Observer` field to `Evaluator` struct
- Extend `NewEvaluator` with optional observer parameter (variadic, like sentinelPath):
  ```go
  func NewEvaluator(db *signals.DB, cfg Config, opts ...EvaluatorOption) *Evaluator
  ```
  Use functional options pattern: `WithSentinelPath(string)`, `WithObserver(observation.Observer)`.
- **Breaking change:** Update all call sites:
  - `cmd/ockham/check.go`: create `observation.NewCassObserver()`, pass `WithObserver(obs)` to `NewEvaluator`. Pass `WithSentinelPath(path)` if custom sentinel path is used.
  - All existing tests in `evaluator_test.go`: update `NewEvaluator(db, cfg)` calls to use new signature (no-arg variadic still works, but any sentinelPath calls need `WithSentinelPath()`).
  - Verify: `go test ./internal/anomaly/ -count=1` passes before proceeding.

### Task 3.2: Call Collect() in Evaluate loop

**File:** `os/Ockham/internal/anomaly/evaluator.go`

Before the theme loop in `Evaluate()`:
```go
var obsMetrics []observation.ObservationMetric
if e.observer != nil && e.observer.IsAvailable() {
    obsMetrics, err = e.observer.Collect(ctx, themes, 24*time.Hour)
    if err != nil {
        fmt.Fprintf(os.Stderr, "ockham: observation collect degraded: %v\n", err)
        // Continue without observation metrics
    }
    // Persist to DB
    for _, m := range obsMetrics {
        e.db.InsertObservation(m.Theme, m.MetricType, m.Value, m.CollectedAt)
    }
}
```

Inside the per-theme drift evaluation, merge observation metrics as advisory signal:
- Lookup `obsMetrics` for this theme
- If `tool_error_rate > 0.3` or `session_completion_rate < 0.5`, increase INFORM severity by one level (but not to BYPASS)
- This is advisory — it shifts the INFORM threshold, not the BYPASS threshold

After observation persist, prune old observation metrics (matches bead pruning pattern):
```go
if _, err := e.db.PruneObservations(theme, e.cfg.MaxWindow*2); err != nil {
    fmt.Fprintf(os.Stderr, "ockham: observation prune degraded for %q: %v\n", theme, err)
}
```

### Task 3.3: Integration tests

**File:** `os/Ockham/internal/anomaly/evaluator_test.go`

- Test: evaluator with mock observer producing high tool_error_rate → INFORM severity increases
- Test: evaluator with mock observer producing normal rates → no change
- Test: evaluator without observer → identical output to current behavior (regression test)
- Test: evaluator with unavailable observer → identical to no observer

---

## F4: Health JSON extension (sylveste-0ewu)

### Task 4.1: Add observation status to health output

**File:** `os/Ockham/cmd/ockham/health.go` (or wherever health JSON is built)

Health reads from the DB (not live observer). Add to `HealthOutput` struct and health SQL query:
```json
{
  "observation": {
    "available": true,
    "last_collect": "2026-04-14T12:00:00Z",
    "metric_count": 4
  }
}
```

- `available`: true if `observation_metrics` has rows within last 48h (heuristic — if metrics are flowing, CASS was available recently). Does NOT require live observer instance.
- `last_collect`: `MAX(collected_at)` from `observation_metrics`
- `metric_count`: `COUNT(*)` from `observation_metrics` WHERE `collected_at > now - 24h`
- When table is empty: `"observation": {"available": false}`
- Update `SchemaVersion` from 2 to 3 in health output.

---

## F5: Degradation contract (sylveste-a72u)

### Task 5.1: Implement degradation in CassObserver

**File:** `os/Ockham/internal/observation/cass_observer.go`

- `IsAvailable()`: calls `observer.New()`. If error (CASS not found), cache the result for 60 seconds (avoid repeated PATH lookups).
- `Collect()`: if `!IsAvailable()`, return nil, nil (not error). Caller gets empty metrics.

### Task 5.2: Log degradation in evaluator

**File:** `os/Ockham/internal/anomaly/evaluator.go`

- When `!observer.IsAvailable()`: log once per evaluation cycle `"ockham: Alwe observation degraded: CASS unavailable"` at info level
- Don't log every time — use `loggedDegradation bool` flag, reset each `Evaluate()` call

### Task 5.3: Degradation tests

- Test: CassObserver with no `cass` binary → `IsAvailable() == false`, `Collect() returns nil, nil`
- Test: evaluator with degraded observer → produces clean output, logs once, no panic

---

## Execution Order

```
Task 0  → Task 0b → Task 1.1-1.5 (F1) → Task 2.1-2.3 (F2)
                                                    ↓
                                          Task 3.1-3.3 (F3) → Task 4.1 (F4) → Task 5.1-5.3 (F5)
```

F1 and F2 can be done in parallel (no dependency). F3 requires both. F4 and F5 depend on F1 but not F2, so they could theoretically run after F1, but sequencing after F3 keeps the work orderly.

**Estimated tasks:** 14 (Task 0, 0b, 1.1-1.5, 2.1-2.3, 3.1-3.3, 4.1, 5.1-5.3)
**All work in:** `os/Ockham/` (commits there) + one refactor in `os/Alwe/`

## Test Strategy

- Unit tests per feature (Tasks 1.5, 2.3, 3.3, 5.3)
- Full suite: `cd os/Ockham && go test ./... -count=1`
- Alwe suite after Task 0: `cd os/Alwe && go test ./... -count=1`
