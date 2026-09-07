---
artifact_type: prd
bead: sylveste-xefe
stage: design
---

# PRD: Ockham-Alwe Observation Bridge

## Problem

Ockham's anomaly evaluator sees only coarse-grained metrics: bead cycle times from `bd list` and authority snapshots from interspect files. It cannot detect agent-level failures, tool error patterns, or session anomalies — signals that would enable earlier intervention and close the governance flywheel (authority → actions → evidence → authority). Alwe already has this data via CASS but Ockham has no connection to it.

## Solution

Add an `internal/observation/` package to Ockham that imports Alwe's `internal/observer.CassObserver` (Go library call, same monorepo), queries session/tool metrics, and feeds `ObservationMetric` values into the anomaly evaluator as advisory signals alongside existing bead-based metrics.

## Features

### F1: Observation package + ObservationMetric type

**What:** New `internal/observation/` package with `Observer` struct wrapping `*observer.CassObserver`, `ObservationMetric` type (theme, metric_type, value, collected_at), and `Collect(themes, since)` method that gathers session completion rate and tool error rate.

**Acceptance criteria:**
- [ ] `Observer` wraps `*observer.CassObserver` with `IsAvailable()` check
- [ ] `Collect()` returns `[]ObservationMetric` for two metric types: `session_completion_rate` and `tool_error_rate`
- [ ] `session_completion_rate`: queries `cass timeline`, counts sessions with done event vs total per theme
- [ ] `tool_error_rate`: queries `cass search "is_error"`, computes error/total ratio per theme
- [ ] All queries parameterized by `since` duration (default 24h)
- [ ] Unit tests with mock CassObserver (interface-based)

### F2: Schema v3 migration (observation_metrics table)

**What:** Add `observation_metrics` table to signals.db, with schema version bump v2→v3.

**Acceptance criteria:**
- [ ] New table: `observation_metrics(id, theme, metric_type, value, collected_at)`
- [ ] Index on `(theme, metric_type, collected_at DESC)`
- [ ] Migration runs on first `signals.Open()` call (existing pattern)
- [ ] Existing data preserved (additive schema change)
- [ ] `DB.InsertObservation()` and `DB.RecentObservations(theme, metricType, since)` methods

### F3: Evaluator integration

**What:** Wire optional `Observer` into `anomaly.Evaluator`. When present, evaluator calls `Collect()` before drift evaluation and merges observation metrics into signal assessment.

**Acceptance criteria:**
- [ ] `NewEvaluator` accepts optional `Observer` (variadic parameter, like sentinelPath)
- [ ] Evaluator calls `observer.Collect(themes, 24h)` when observer is non-nil and available
- [ ] Observation metrics are **advisory** — they influence INFORM signal severity but do NOT independently trigger BYPASS
- [ ] Observation metrics persisted to `observation_metrics` table via DB
- [ ] Integration tests: evaluator with mock observer produces enriched signals
- [ ] Integration tests: evaluator without observer produces identical output to current behavior

### F4: Health JSON extension

**What:** Add observation status to Ockham's health output.

**Acceptance criteria:**
- [ ] `health.json` includes `"observation": {"available": bool, "last_collect": timestamp, "metric_count": int}`
- [ ] When observation unavailable: `"available": false`, other fields omitted
- [ ] Existing health fields unchanged

### F5: Degradation contract

**What:** Graceful degradation when CASS is unavailable.

**Acceptance criteria:**
- [ ] `observer.IsAvailable()` returns false when CASS binary not found or health check fails
- [ ] When unavailable: evaluator skips all observation queries, logs `"ockham: Alwe observation degraded: CASS unavailable"` at info level
- [ ] No BYPASS trigger change — observation is supplementary, not primary
- [ ] Test: evaluator with unavailable observer produces clean output (no panic, no error return)

## Non-goals

- Real-time session tailing (TailSession) — future work, needs streaming architecture
- Revert detection (O3 from brainstorm) — requires git correlation, deferred
- Session duration anomaly (O4) — requires baseline calibration data, deferred
- Changes to Alwe itself — Alwe is consumed as-is
- Theme-specific mapping via bead attribution — F1 defaults all to "open" theme

## Dependencies

- Alwe's `internal/observer` package (Go import with `replace` directive in go.mod)
- CASS CLI binary on PATH (runtime dependency, graceful degradation when absent)
- Ockham's existing `internal/signals` DB and `internal/anomaly` evaluator

## Go Module Dependency

Ockham's go.mod needs:
```
require github.com/mistakeknot/Alwe v0.0.0
replace github.com/mistakeknot/Alwe => ../../Alwe
```

Note: Alwe's observer is in `internal/`, which Go normally restricts to same-module imports. Since Ockham is a separate module, we need to either (a) move `observer` to `pkg/observer` in Alwe, or (b) create a thin `pkg/observer` facade in Alwe that re-exports the internal types. Option (a) is cleaner — the observer types are the public API of Alwe.

## Open Questions

None remaining — all resolved in brainstorm (D1-D5).
