# Ockham-Alwe Observation Bridge — Brainstorm

**Bead:** sylveste-xefe | **Date:** 2026-04-07
**Prior art:** Ockham F1-F7 shipped (intent, scoring, anomaly, signals, BYPASS). Alwe ships 5 MCP tools wrapping CASS (search, context, timeline, export, health). No connection between them.

## The Gap

Ockham's anomaly evaluator currently gets metrics from two sources:
1. **bd list --status=closed** — shells out to beads CLI for cycle times (check.go:closedBeadsFromBD)
2. **interspect confidence.json** — reads file for authority snapshots (check.go:snapshotAuthority)

Both are batch, file-scraping, and coarse-grained. Ockham can detect theme-level drift in p50 cycle times but cannot see:
- **Agent-level failure rates** — which agent connector is producing errors
- **Tool failure patterns** — are Bash calls failing? Are Edit calls being rejected?
- **Session-level anomalies** — abandoned sessions, unusually long tool chains, repeated retries
- **Cross-agent correlation** — are multiple agents failing on the same files?

Alwe already has this data via CASS. The bridge connects them.

## What the Bridge Does

The bridge is a new package in Ockham that queries Alwe's observation layer and transforms the results into metrics that the anomaly evaluator can consume. It does NOT replace the existing bd-based metrics — it supplements them with agent-level signals.

### Data Flow

```
CASS (indexes 15+ agent providers)
  ↓
Alwe (CassObserver: search, timeline, context)
  ↓
Ockham/internal/observation/ (new package — queries Alwe, transforms to metrics)
  ↓
Ockham/internal/anomaly/evaluator.go (consumes observation metrics alongside bead metrics)
  ↓
signals.db (persisted for health output + BYPASS evaluation)
```

### What Ockham Can Now Observe

**O1: Session completion rate per theme**
Query: `cass timeline --since 24h --json` → count sessions per connector, count sessions with `done` event vs abandoned.
Maps to: new `ObservationMetric` in signals.db with type `session_completion_rate`.

**O2: Tool error rate per theme**
Query: `cass search "is_error" --json --limit 100` → count tool_result events with `is_error: true` vs total tool_results.
Maps to: `ObservationMetric` with type `tool_error_rate`.

**O3: Agent revert detection**
Query: `cass context <file> --json` → cross-reference with `git log --diff-filter=D` to detect files that were added then removed (agent work reverted).
Maps to: `ObservationMetric` with type `revert_rate`. This is the vision doc's "agent-unwritable" channel.

**O4: Session duration anomaly**
Query: `cass timeline --since 7d --json` → compute p50/p90 session duration per connector. Flag sessions > 2x p90 as anomalous.
Maps to: `ObservationMetric` with type `session_duration_anomaly`.

## Design Decisions

### D1: How does Ockham call Alwe?
Options:
- (a) **Shell out to `alwe` CLI** — matches existing pattern (bd, cass)
- (b) **Import Alwe's pkg/observer** — Go library call, type-safe
- (c) **MCP client** — call Alwe's MCP server

**Recommendation: (b) Import pkg/observer.** Alwe is in the same monorepo. Direct Go import is type-safe, testable, and avoids shell-out overhead. The observer wraps CASS CLI internally, so Ockham gets structured data without parsing JSON from shell output. Degradation: if CASS is unavailable, `IsAvailable()` returns false, Ockham skips observation metrics and logs degradation.

### D2: Where does the observation code live?
**New package: `internal/observation/`** in Ockham. Imports `pkg/observer` from Alwe. Contains:
- `Observer` struct wrapping `*observer.CassObserver`
- `Collect(themes []string, since time.Duration) ([]ObservationMetric, error)` — gathers all metrics
- `ObservationMetric` type — theme, metric_type, value, timestamp

### D3: How does the evaluator consume observation metrics?
Add an optional `Observer` to `anomaly.Evaluator` (variadic parameter, like sentinelPath). When present, the evaluator calls `observer.Collect()` before drift evaluation and merges observation metrics into the signal assessment.

Observation metrics are **advisory** — they influence the INFORM signal's drift calculation but do not independently trigger BYPASS. This preserves the principle that BYPASS requires bead-level evidence (not just session-level anomalies).

### D4: Schema extension
Add `observation_metrics` table to signals.db (schema v3):
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

### D5: Degradation contract
From the vision doc: "When Alwe is unavailable, the anomaly subsystem skips Alwe-sourced inputs and proceeds on remaining channels."
- `observer.IsAvailable()` returns false → skip all observation queries
- Log: `"ockham: Alwe observation degraded: CASS unavailable"`
- Evaluator proceeds with bd-based metrics only (existing behavior)
- No BYPASS trigger change — observation is supplementary, not primary

## Scope Boundaries

**In scope:**
- `internal/observation/` package (Observer, Collect, ObservationMetric)
- Schema v2→v3 migration (observation_metrics table)
- Evaluator integration (optional observer, advisory metrics)
- Session completion rate + tool error rate signals
- Degradation when CASS unavailable
- Health JSON extension (observation status)

**Out of scope:**
- Real-time TailSession (live monitoring — future)
- Revert detection (requires git correlation — future)
- Session duration anomaly (requires baseline calibration — future)
- Alwe MCP client (we import Go directly)
- Changes to Alwe itself

## Open Questions

### Q1: go.mod dependency
Ockham's go.mod doesn't currently reference Alwe. Adding `require github.com/mistakeknot/Alwe` creates a cross-repo dependency. Since both are in the monorepo, use `replace github.com/mistakeknot/Alwe => ../../Alwe` in go.mod.

### Q2: Theme mapping from CASS connectors
CASS sessions have a `connector` field (claude_code, codex, gemini). Ockham themes are lane labels (auth, perf, open). The bridge needs a mapping function. Options:
- (a) Map connector → theme via config
- (b) Use bead attribution: each session has a bead ID, beads have lane labels
- (c) Default all to "open" for now

**Recommendation: (c) default to "open" for F1, add bead-based mapping in F2.** The initial bridge proves the data flow works. Theme-specific observation comes after.
