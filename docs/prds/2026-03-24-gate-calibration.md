---
artifact_type: prd
bead: Demarch-0rgc
stage: design
---
# PRD: Gate Threshold Calibration

## Problem

Phase gates use hardcoded enforcement tiers (hard/soft) that don't adapt to project history. A gate that consistently produces false positives (overridden by humans) wastes attention, while a soft gate with high false negatives (defects slip through) should be promoted to hard. Additionally, 4 pre-existing bugs in the gate evaluation path compromise transaction safety and crash portfolio runs.

## Solution

A calibration loop that learns from gate outcomes (overrides = false positives, rollbacks = false negatives) and promotes soft gates to hard when false negative rates exceed 30%. Hard→soft demotion is human-only. Calibration state lives in a JSON file read by Clavain (L2) and injected into `GateConfig` as a map — the L1 kernel never reads files. Ships alongside 4 P0/P1 bug fixes and override categorization for signal quality.

## Delivery Priority

If time is constrained, deliver in this order:
1. **F1** (bug fixes) — prerequisite for everything; unblocks correct signal collection
2. **F2 + F4** (signal extraction + runtime integration) — the core calibration loop
3. **F5** (override categorization) — signal quality; must ship with calibration
4. **F3** (calibration command) — the intelligence layer that consumes F2 and writes for F4
5. **F6** (observability) — polish; can follow in a subsequent session

## Features

### F1: Pre-existing Bug Fixes
**What:** Fix 4 bugs discovered during gate system analysis that affect correctness and crash safety.
**Acceptance criteria:**
- [ ] `scanRuns` in `tx_queriers.go` scans all 21 `runCols` columns (adds `gateRulesJSON`, calls `parseGateRulesJSON`)
- [ ] `BudgetQuerier` is tx-scoped in `machine.go` via new `txBudgetQuerier` wrapper (budget data is in the same SQLite DB — confirm before implementing; if separate DB, document the residual race)
- [ ] `Rollback` in `machine.go` wraps `RollbackPhase` + `AddEvent` in a single transaction (same `BeginTx`/`Commit` pattern as `Advance`)
- [ ] `cmdGateOverride` in `ic/gate.go` wraps `UpdatePhase` + `AddEvent` in a single transaction (crash between the two currently drops override events, which poisons FPR signal once F5 ships)
- [ ] Existing tests pass; new test for portfolio gate with `gate_rules` column

### F2: Signal Extraction Query
**What:** Cursor-based extraction of confusion matrix signals (TP/FP/TN/FN) from `phase_events` table.
**Acceptance criteria:**
- [ ] New `GetGateSignals(ctx, sinceID int64) ([]GateSignal, error)` on `phase.Store`
- [ ] Correctly classifies: blocks without subsequent override = TP, `justified` overrides = FP (see F5), passes without subsequent rollback within attribution window = TN, rollbacks = FN
- [ ] FN attribution: a rollback from phase X to phase Y attributes the FN to the gate guarding `Y→next(Y)` — the gate that should have blocked. Multi-phase rollbacks attribute to each gated transition in the rolled-back span.
- [ ] TN classification: advance events require a rollback cross-check — scan forward within a 3-phase attribution window for any subsequent rollback to the same run. Two-pass query or self-join; do not use a simple single-pass scan.
- [ ] Key construction via shared `GateCalibrationKey(checkType, from, to string) string` function (defined once in `phase` package, used by F2, F3, and F4). Never inline key construction at call sites.
- [ ] Excludes programmatic bypasses (`gate_result='none'`) and `CLAVAIN_SKIP_GATE` bypasses (no gate event recorded)
- [ ] Pre-F5 overrides (no `override_category` field): count toward FPR as `justified` for backwards compatibility. After F5 ships, only explicit `justified` tags count.
- [ ] Returns cursor position for incremental extraction
- [ ] Unit test with seeded events covering all 4 signal types, including multi-phase rollback attribution

### F3: Calibration Command
**What:** `clavain-cli calibrate-gate-tiers` command that reads signals, computes weighted FPR/FNR per key, and writes `gate-tier-calibration.json`.
**Acceptance criteria:**
- [ ] Computes per-key `(check_type, from_phase→to_phase)` metrics with 90-day window and 30-day half-life
- [ ] Promotes soft→hard when `weighted_n >= 10` AND `FNR > 0.30`
- [ ] Never auto-demotes hard→soft (promotion-only)
- [ ] Enforces 7-day cooldown between tier changes per key
- [ ] Locks keys with >2 tier changes in 90-day window (velocity lock)
- [ ] Respects `locked: true` entries (human-set, never modified by calibration)
- [ ] Writes well-formed JSON with `calibrated_at`, `window_days`, `half_life_days`, per-key stats
- [ ] File path: resolved relative to intercore DB parent directory (walk-up from CWD, same as `ic openDB()`). NOT derived from `CLAVAIN_DIR` env-var — hardcoded project-relative path prevents agent redirection
- [ ] Write via tmp+rename for atomicity

### F4: Runtime Integration
**What:** `evaluateGate` reads calibrated tiers from `GateConfig.CalibratedTiers` map when no per-run or spec rules apply.
**Acceptance criteria:**
- [ ] New `CalibratedTiers map[string]string` field on `GateConfig`
- [ ] Calibration lookup is **per-rule inside the eval loop** — for each rule, check `CalibratedTiers[GateCalibrationKey(rule.check, from, to)]` to get the tier override. Not a single per-transition lookup before the loop.
- [ ] Map key via shared `GateCalibrationKey()` function (same as F2)
- [ ] Missing/empty map = use hardcoded defaults (Stage 4 fallback)
- [ ] Clavain reads JSON file at Advance call site and populates the map (no file I/O in L1 kernel)
- [ ] **Locked entries excluded at load time:** Clavain filters out `locked: true` entries when building `CalibratedTiers` — locked keys fall through to hardcoded defaults. `evaluateGate` never sees locked entries.
- [ ] **Promotion-only enforced at load time:** if a key in the file has tier `"soft"` but the hardcoded `gateRules` default for that check×transition is `"hard"`, emit `calibration_file_corrupt` event and treat that entry as absent (fall through to default). Prevents file tampering from demoting hard gates.
- [ ] Stale file (>24h) treated as absent, emits `calibration_file_stale` event
- [ ] Unit test: calibrated tier overrides default when no per-run/spec rules exist

### F5: Override Categorization
**What:** `ic gate override` accepts `--justified` or `--expedient` tag stored in event reason JSON.

**Definitions:**
- `justified`: "The gate correctly identified a problem, but we are proceeding because the risk is accepted." Counts toward FPR — this is a real false positive from the gate's perspective.
- `expedient`: "The gate is wrong — this is a false alarm, but we don't have time to fix the gate right now." Also counts toward FPR (it IS a false positive). The distinction is for audit/reporting, not signal exclusion.

**RESOLVED (from flux-drive review):** Both categories count toward FPR. The original design excluded `expedient` from FPR, but this creates a gaming vector (agents always choose `expedient` to suppress signal). Instead, both count equally. The category exists for human audit trails only.

**Acceptance criteria:**
- [ ] `ic gate override` accepts optional `--justified` or `--expedient` flag
- [ ] **Backwards compatible:** if neither flag is provided, override proceeds with a deprecation warning to stderr: `"Warning: --justified or --expedient will be required in a future version"`. Category stored as `"uncategorized"` in reason JSON. All uncategorized overrides count toward FPR.
- [ ] Tag stored in `phase_events.reason` JSON: `{"override_category": "justified|expedient|uncategorized", ...}`
- [ ] Signal extraction (F2) counts ALL overrides toward FPR regardless of category
- [ ] Clavain's automated override paths must pass `--justified` or `--expedient` — update hook scripts that call `ic gate override`

### F6: Observability Events
**What:** 5 new interspect event types for calibration monitoring plus gate provenance in `ic gate check`.
**Acceptance criteria:**
- [ ] `calibration_checkpoint` event emitted per key after each calibration run
- [ ] `calibration_goodhart_warning` when override rate up + run completion rate (`completed / (completed + failed)`) down over the same window
- [ ] `calibration_data_starvation` when insufficient samples for a key (`weighted_n < 10`)
- [ ] `calibration_file_corrupt` on parse failure or demotion detected in file (file preserved for forensics)
- [ ] `calibration_file_stale` when file age exceeds 24h SLA at read time
- [ ] `ic gate check` output includes provenance: `(tier: soft, source: calibrated, fpr: 0.62)` for calibrated keys; `(tier: soft, source: default, calibration: insufficient_data, n: 7/23)` for unactivated keys; `(tier: hard, source: default, calibration: locked)` for locked keys
- [ ] `ic gate check --json` includes `source`, `fpr`, `calibration_status` fields in JSON output
- [ ] `CLAVAIN_SKIP_GATE` usage logged as interspect event for Goodhart monitoring

## Non-goals

- **Continuous confidence scores**: Gates are binary (hard/soft/none). A continuous score mapping to the same 2 outcomes adds complexity with no behavioral difference.
- **Per-check skip probability**: Non-deterministic gate evaluation violates auditability.
- **Auto-demotion**: Hard→soft requires human `ic gate-calibration demote` to prevent rubber-stamp risk.
- **New schema/DDL**: All signal extraction works on existing `phase_events` table. Observability uses existing interspect evidence schema.
- **P4+ gate calibration**: Priority ≥ 4 bypasses gates entirely; calibration cannot opt them in.
- **`ic gate-calibration demote` / `unlock` commands**: Human escape hatches for demotion and velocity-lock release. Required for operational safety but can ship as a fast follow — the JSON file is human-editable as interim escape. Track as separate bead.

## Dependencies

- `phase_events` table with `gate_result`, `gate_tier`, `reason` columns (existing)
- Interspect evidence table for observability events (existing)
- `ic gate override` command (existing, extended in F5)
- `GateCalibrationKey()` shared function (new, created in F2, consumed by F3 and F4)

## Resolved Questions (from flux-drive review)

1. **Defect attribution window**: 3 phases. A rollback from phase X to phase Y attributes FN to each gated transition in the span. Multi-phase rollbacks produce multiple FN signals.
2. **FN cross-check**: Not needed for v1. The F1 rollback atomicity fix ensures future rollbacks are correctly recorded. Historical signal gaps are documented (first 90 days may have underestimated FNR from pre-fix data).
3. **Staleness SLA**: 24 hours (not 48h). Aligns with brainstorm. Conservative bias is correct for safety tooling.
4. **Override categorization gaming**: Both `justified` and `expedient` count toward FPR. Category is for audit, not signal exclusion.
5. **Lock enforcement location**: Clavain-side. Locked entries excluded from `CalibratedTiers` map at load time. `evaluateGate` never sees them.
6. **Calibration file path**: Resolved relative to intercore DB parent directory. NOT from `CLAVAIN_DIR` env-var.
7. **Override event atomicity**: `cmdGateOverride` must be tx-wrapped (added to F1).
