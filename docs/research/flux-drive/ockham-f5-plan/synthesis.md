---
artifact_type: flux-drive-synthesis
target: docs/plans/2026-04-05-ockham-f5-inform-signals.md
reviewed: 2026-04-05
agents: [go-compilation-order, api-backward-compat, statistical-correctness, test-coverage, degradation-contracts]
verdict: PASS with 2 P0, 3 P1
---

# Flux-Drive Synthesis: Ockham F5 Implementation Plan

## Verdict: PASS with conditions

The plan is implementable as written. Batch ordering is sound. Two P0 issues require resolution before implementation begins; three P1 issues should be addressed during implementation.

---

## P0 — Must fix before implementation

### P0-1: `anomaly.State` zero-value breaks existing tests after Step 1.2

**What:** The plan replaces `anomaly.State` from `type State struct{}` to a struct with `Signals map[string]ThemeSignal` and `Pleasure []PleasureSignal`. The plan claims (Step 1.3, Risk Mitigation) "the anomaly.State change from empty struct to struct-with-fields should be backward compatible since scoring.Score() currently ignores the anomaly argument."

**Why this is wrong:** The _signature_ is backward-compatible (both are `anomaly.State`), so it compiles. But the plan's Step 3.1 changes `Score()` to _read_ `an.Signals[lane].AdvisoryOffset`. If that code runs against a zero-value `anomaly.State` where `Signals` is `nil`, it panics on nil map read. The plan says "zero anomaly state = no advisory offsets" — but the implementation must explicitly nil-check `an.Signals` before indexing. The plan's Step 3.1 pseudocode does not show this guard.

**Fix:** In the scorer (Step 3.1), before reading `an.Signals[lane]`, add:
```go
if an.Signals != nil {
    if ts, ok := an.Signals[lane]; ok {
        offset += ts.AdvisoryOffset
    }
}
```
The existing tests pass `anomaly.State{}` which has `Signals: nil` — without this guard they panic. This must be specified in the plan, not left to the implementer.

### P0-2: `bead_metrics.bead_id` needs UNIQUE constraint for duplicate-skip logic

**What:** Step 3.4 says `ingestBeadMetrics()` will "skip duplicates via bead_id uniqueness." But Step 1.1's schema definition for `bead_metrics` has no UNIQUE constraint or PRIMARY KEY on `bead_id`:

```sql
CREATE TABLE IF NOT EXISTS bead_metrics (
    bead_id TEXT NOT NULL,
    ...
);
```

**Why this matters:** Without a UNIQUE constraint, the duplicate-skip logic in Step 3.4 has no database-level enforcement. Each `ockham check` run would re-insert every closed bead, ballooning the table. The implementer would need to add either `INSERT OR IGNORE` with a UNIQUE constraint, or a manual `SELECT EXISTS` check.

**Fix:** Add `bead_id TEXT PRIMARY KEY` or `UNIQUE(bead_id)` to the schema in Step 1.1. Then `ingestBeadMetrics` can use `INSERT OR IGNORE` cleanly.

---

## P1 — Should fix during implementation

### P1-1: Scoring reads per-bead lane but anomaly signals are per-theme — key mismatch

**What:** `Score()` iterates over beads and reads `b.Lane` to look up the intent offset. The plan says to add anomaly advisory offset "for the bead's theme." But the map key in `anomaly.State.Signals` is theme name, while beads use lane (with empty-string → "open" fallback). The plan's Step 3.1 does not specify that the scorer should apply the same empty→"open" normalization when looking up `an.Signals[lane]`.

**Fix:** The scorer already normalizes `lane` to `"open"` for intent lookup. The anomaly lookup must use the _same_ normalized lane, not `b.Lane` directly. Add a comment or explicit mention in the plan.

### P1-2: `medianCycleTime` returns float64 but `CycleTimeMs` is int64 — precision note

**What:** The plan defines `medianCycleTime(metrics []signals.BeadMetric) float64`. For even-length slices, the standard median is the average of the two middle values. Since `CycleTimeMs` is `int64`, the implementer needs to know whether to use integer division (truncated) or float division. For drift percentage calculation, this matters at small sample sizes (10 beads).

**Fix:** Specify that `medianCycleTime` uses float64 arithmetic for the average of two middle values. Minor, but prevents a subtle off-by-one-half in drift detection near the threshold boundary.

### P1-3: Theme discovery for evaluator not specified

**What:** Step 3.2's `Evaluate(themes []string, now int64)` requires a `themes` parameter. Step 3.4 says to "get themes from beads (via beadsFromBD themes)." But `beadsFromBD()` returns open beads, while signal evaluation should cover themes that _had_ beads — including themes where all beads are now closed. A theme with all-closed beads and no new completions might incorrectly be skipped for staleness evaluation.

**Fix:** Theme list should be the union of: (a) lanes from open beads via `beadsFromBD`, and (b) themes already present in `signal_state` table (to catch staleness transitions for inactive themes). The evaluator's `loadPriorSignal` already reads from the DB, so querying distinct themes from `bead_metrics` + `signal_state` is the correct source.

---

## P2 — Advisory (non-blocking)

### P2-1: Split-window baseline vs recent has known statistical weakness at MinWindow=10

The plan acknowledges "10-bead window has ~50% power for 20% drift detection." The split into 5-baseline / 5-recent makes this worse — 5 samples per half gives high variance on the p50 estimate. The adaptive window (up to 30) mitigates this. The plan's choice is acceptable for advisory-only signals. No action needed, but implementers should know that false-positive rate at MinWindow will be high (~20-30%).

### P2-2: `persistPleasure` signal_state key format not explicit

The PRD says `pleasure:<signal_name>:<theme>` but the plan's evaluator code shows `persistPleasure(theme, ...)` without specifying the key format. Should be documented in the evaluator to match the PRD contract.

### P2-3: Recovery path for schema v2 migration on corrupt + recovered DB

If signals.db is corrupt and recovered (deleted + recreated), the `recover()` method uses the `schema` constant which is still v1. The plan says to add `bead_metrics` to the schema constant, but should verify that the recovery path also creates the v2 schema (since recovered DBs re-run the full schema constant, this should work if the constant is updated — but worth a test case).

---

## Validation Answers

**1. Batch ordering prevents compilation errors?**
Yes. Batch 1 creates types (anomaly.State fields, bead_metrics CRUD) that Batch 2 consumes (drift/pleasure functions operate on BeadMetric slices). Batch 3 wires integration (governor, scorer, CLI). Each batch only depends on its predecessors. The parallel steps in Batch 2 (2.1 || 2.2) are correctly identified as independent.

**2. Is the scoring.Score() API change backward-compatible?**
Signature: yes — it still accepts `anomaly.State`. Behavior: conditional on P0-1 fix. With nil-guard on `an.Signals`, existing tests passing `anomaly.State{}` will see zero advisory offset (same behavior as today). Without the guard: panic.

**3. Does the drift detection algorithm make statistical sense?**
The split-window approach (baseline=older half, recent=newer half) is a standard change-point detection heuristic. Using p50 (median) is more robust than mean for skewed cycle-time distributions. The hysteresis (fire at 20%, clear at 10% for 3 consecutive) prevents oscillation. The factory guard (sum <= 12) prevents runaway advisory stacking. Statistically sound for advisory-only use. See P2-1 for power limitations at MinWindow.

**4. Are test cases sufficient for acceptance criteria?**
Mostly. The plan's test tables cover: fire, clear, hysteresis, staleness, factory guard, insufficient data, degraded mode, trend directions. Missing: (a) test for nil-map safety on zero-value anomaly.State in scorer (P0-1), (b) test for duplicate bead ingestion (P0-2), (c) test for theme discovery across active+stale themes (P1-3).

**5. Does `ockham check` handle degradation contracts correctly?**
Yes, with the existing pattern. The plan follows check.go's established degradation pattern: catch error, log to stderr, continue. Signal evaluation failure does not block authority snapshots or reconfirmation checks. The plan explicitly addresses bd-unavailable and cost-query-unavailable cases. The degradation hierarchy (log + continue, never false-all-clear) matches the PRD.
