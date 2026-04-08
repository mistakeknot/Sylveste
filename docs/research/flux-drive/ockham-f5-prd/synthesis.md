---
artifact_type: flux-drive-synthesis
source: docs/prds/2026-04-05-ockham-f5-inform-signals.md
agents_triaged: 6
agents_launched: 6
date: 2026-04-05
mode: review
scope: sprint PRD review (proportionate — P0/P1 focus)
---

# Flux-Drive Synthesis: Ockham F5 PRD Review

## Triage Summary

**10 agents available** (5 adjacent, 5 distant from prior brainstorm review). Launched 6 for sprint PRD scope:

| Agent | Track | Focus | Findings |
|-------|-------|-------|----------|
| fd-statistical-process-control | adjacent | Sample sizes, threshold calibration | 1 P1, 1 P2 |
| fd-go-metrics-implementation | adjacent | Go API design, error isolation | 1 P1, 1 P2 |
| fd-sqlite-rolling-window | adjacent | Schema, queries, migration | 0 P0, 2 P2 |
| fd-data-pipeline-reliability | adjacent | Source availability, degradation | 1 P1 |
| fd-feedback-loop-closure | adjacent | Windup, hysteresis, recovery | 0 (addressed in PRD) |
| fd-tibetan-sand-mandala-dissolution | distant | State lifecycle, staleness | 1 P2 |

**Skipped (proportionate):** fd-sake-toji (cross-signal correlation), fd-persian-qanat (per-theme variance), fd-ottoman-waqf (tier escalation), fd-carillon-bell (aggregate drift). These cover Wave 2/3 design concerns. The PRD explicitly defers cross-signal correlation and factory-level aggregates to non-goals.

---

## P1 Findings

### P1-1: Scoring function signature change requires careful wiring (fd-go-metrics-implementation)

**Issue:** `scoring.Score()` currently takes `anomaly.State` as a positional arg but ignores it (the `_` parameter). F4 acceptance criterion says "scoring.Score() accepts anomaly.State and incorporates advisory offsets per theme." But `anomaly.State` is currently an empty struct. F5 must:
1. Add fields to `anomaly.State` (per-theme advisory offsets)
2. Wire those offsets into `Score()` alongside intent offsets
3. Update the clamp range — intent goes [-6, +6], advisory is -1 per cycle, but their sum could exceed clamp bounds

**Risk:** The PRD says advisory offsets are "additive, after intent offsets" but doesn't specify whether the combined offset is re-clamped or whether advisory has its own clamp range. If intent gives +6 and advisory gives -1, the result is +5 (fine). But if intent gives -3 and advisory gives -1, the result is -4, still within [-6, +6]. However, the factory-level guard (sum of reductions <= 12) operates at a different level than per-bead clamping.

**Recommendation:** Add to F4 acceptance criteria: "Combined intent + advisory offset is clamped to [OffsetMin, OffsetMax] after addition. Factory-level guard is evaluated before per-theme offsets are computed (fail-fast)." This makes the composition rule explicit and testable.

**Severity justification:** P1 because ambiguous composition rules will cause implementation bugs that are hard to test without a spec.

### P1-2: 10-bead minimum may be insufficient for reliable 20% drift detection (fd-statistical-process-control)

**Issue:** Cycle time distributions are typically right-skewed (log-normal). The PRD correctly specifies p50 (median) rather than mean. But with only 10 beads in the window, the p50 estimate has high variance. For a 20% degradation threshold:
- With 10 samples from a log-normal distribution (CV=0.5, typical for cycle time), the 95% CI for the median spans roughly +/-30% of the true median
- This means a genuine 20% drift has about a 50% chance of being detected in any given evaluation (power = ~0.5)
- Conversely, healthy themes have a non-trivial false positive rate (~10-15%)

**Risk:** For advisory-only INFORM signals, this is tolerable but not great. The rate-limiting (-1 per cycle) and factory-level ceiling (12) contain the blast radius. But P1 because the PRD doesn't acknowledge this statistical limitation, and the acceptance criteria test "fire threshold: 20% degradation" without specifying the statistical power expectation.

**Recommendation:** Add a note to F2 that the 10-bead minimum is a practical floor for early factory operation (where themes may not have many completed beads), not a statistically ideal window. Consider: "If a theme has >= 30 beads in the window, use the larger window for higher detection power." This is a one-line change in the query (ORDER BY completed_at DESC LIMIT min(30, window_size)).

### P1-3: `bd` CLI availability is under-specified as a degradation contract (fd-data-pipeline-reliability)

**Issue:** F1 says `bead_metrics` table stores bead data, but doesn't specify how data gets INTO the table. The dependency list says "`bd` CLI for bead data (cycle time, completion status)" but `bd` is a complex tool with its own Dolt database. Failure modes include:
- Dolt server not running (common after reboot)
- `bd` binary not found
- `bd list` returning stale data (Dolt not synced)
- `bd` timing out on large queries

The PRD specifies degradation for pleasure signals ("if a data source is unavailable, mark insufficient_data") but doesn't specify what happens to weight-drift detection when `bd` is unavailable. If `bd` fails, the bead_metrics table gets no new rows, the rolling window goes stale, and F2's "short-circuit: skip evaluation if no new beads since last check" kicks in. This is correct behavior, but the degradation path should be explicit.

**Recommendation:** Add to F1: "If bd CLI is unavailable during ockham check, log a degraded-mode warning and skip bead_metrics ingestion. Existing window data is preserved. Weight-drift evaluation proceeds on stale data (short-circuit will skip themes with no new beads). If bd is unavailable for > window_staleness_days (14), all themes transition to stale."

---

## P2 Findings

### P2-1: Interspect event format for INFORM fire/clear is an open question with implementation risk (fd-go-metrics-implementation)

**Issue:** Open Question #2 in the PRD: "Interspect event format for INFORM fire/clear -- coordinate with interspect hook_id allowlist." This is a cross-cutting dependency. If the format isn't resolved before implementation starts, the implementer will either:
- Design a format that doesn't match interspect's allowlist schema (rejected at write time)
- Skip interspect writes and backfill later (losing audit trail for early signals)

**Recommendation:** Resolve before sprint start. Check `~/.clavain/interspect/` for existing event schemas. The event likely needs: `hook_id: "ockham:inform"`, `event_type: "signal_fire" | "signal_clear"`, `payload: {theme, signal_name, before_state, after_state, evidence}`.

### P2-2: Schema v1 -> v2 migration needs explicit handling for the bead_metrics table (fd-sqlite-rolling-window)

**Issue:** The existing `migrateSchema()` function is a stub that just bumps the version number. F1 needs:
- `CREATE TABLE IF NOT EXISTS bead_metrics (...)` in the migration
- Index creation: `CREATE INDEX IF NOT EXISTS idx_bead_metrics_theme_completed ON bead_metrics (theme, completed_at)`
- The migration must be idempotent (run it twice, no error)

The PRD's acceptance criteria correctly require idempotent migration, but the existing code's `migrateSchema()` pattern (just update version) needs to actually execute DDL. This is straightforward but should be in the implementation plan.

**Recommendation:** No PRD change needed. Implementation note: follow the commented pattern in `db.go:172-177` exactly.

### P2-3: Retention pruning timing relative to evaluation (fd-sqlite-rolling-window)

**Issue:** F1 says "prune rows older than 2x window size per theme each check cycle." But if pruning runs BEFORE evaluation in the check cycle, it could delete rows that the rolling window query needs. If it runs AFTER, stale rows persist for one extra cycle (harmless).

**Recommendation:** Add to F1: "Retention pruning runs after signal evaluation in the check cycle, not before." One sentence, prevents an ordering bug.

### P2-4: Clear-condition consecutive evaluation tracking (fd-tibetan-sand-mandala-dissolution)

**Issue:** F2 says "Clear threshold: 10% degradation for 3 consecutive evaluations." This requires tracking how many consecutive evaluations met the clear condition. Where is this counter stored? Options:
- In `signal_state` as a JSON value (e.g., `{"state":"fired","clear_count":2}`)
- In a new column on `signal_state`
- In a separate counter table

The PRD doesn't specify the storage mechanism for the consecutive-evaluation counter. This isn't a PRD-level concern (implementation detail), but the implementer needs to know the pattern.

**Recommendation:** No PRD change needed. Implementation note: store as JSON in signal_state value field (matches existing key-value pattern, avoids schema change for a counter).

---

## Addressed Concerns (no findings)

### Hysteresis: Properly specified
The PRD has asymmetric fire (20%) and clear (10%) thresholds, plus the 3-consecutive-evaluation requirement for clearing. fd-feedback-loop-closure confirms this prevents oscillation.

### Windup prevention: Properly specified
Factory-level guard (sum of advisory reductions <= 12) and per-theme rate limit (-1 per cycle) together prevent runaway offset accumulation. With OffsetMin=-6 and max advisory of -1/cycle, a single theme takes 6 cycles to hit minimum. The ceiling of 12 means at most 2 themes can be fully suppressed (or 12 themes lightly suppressed). This is well-calibrated for a factory with 3-8 active themes.

### Staleness: Properly specified
14-day no-new-beads -> stale state. F2 acceptance criteria include staleness test. fd-tibetan-sand-mandala-dissolution's concern about ghost signals is addressed.

### Halt guard: Properly specified
F4 says "Halted factory (factory-paused.json) skips signal evaluation entirely (INV-8)." This matches the existing `governor.go` pattern.

### First_attempt_pass_rate source: Properly specified
PRD explicitly says "sourced from quality-gates verdicts (agent-unwritable), NOT interspect evidence." This resolves the P0 from the brainstorm review.

---

## Feature Gap Assessment

**Are the 4 features sufficient?** Yes, for Wave 1 scope. The features cover:
- Storage (F1) -> Detection (F2) -> Health tracking (F3) -> Integration (F4)

This is a clean pipeline. No missing capability for the stated scope.

**What's NOT covered (correctly deferred):**
- Cross-signal correlation (non-goal, Wave 2)
- Factory-level aggregate checks (non-goal, Wave 2)
- Authority ratchet integration of pleasure signals (non-goal, Wave 3)
- Graduated advisory response (non-goal, start binary)
- Per-theme variance calibration (distant agents flagged this, but it's a Wave 2 refinement)

---

## Open Questions Resolution Recommendations

### OQ-1: Quality-gates verdict source
The PRD says "quality-gates verdicts (agent-unwritable)" and asks whether this is `.clavain/verdicts/` or beads state transitions. **Recommendation:** Use `.clavain/verdicts/` directory. Beads state transitions are agent-writable (agents close their own beads). Clavain's quality-gates write verdict files that agents cannot modify. Verify: `ls ~/.clavain/verdicts/` to confirm the directory exists and has the expected format.

### OQ-2: Interspect event format
See P2-1 above. Resolve before sprint start by checking interspect's hook_id allowlist at `~/.clavain/interspect/config.yaml` or equivalent.

---

## Bottom Line

The PRD is implementation-ready with three P1 refinements:
1. **Clarify offset composition rule** (P1-1) — one sentence in F4 acceptance criteria
2. **Acknowledge window size limitation** (P1-2) — one note in F2, optional adaptive window
3. **Specify bd degradation contract** (P1-3) — one paragraph in F1

All three are small additions. No structural changes needed. The brainstorm review fixes (pass_rate source, hysteresis, clear-condition, windup) are properly incorporated.
