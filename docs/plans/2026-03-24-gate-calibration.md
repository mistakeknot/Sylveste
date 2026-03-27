---
artifact_type: plan
bead: Sylveste-0rgc
prd: docs/prds/2026-03-24-gate-calibration.md
stage: planned
---
# Plan: Gate Threshold Calibration

PRD: `docs/prds/2026-03-24-gate-calibration.md`
Brainstorm: `docs/brainstorms/2026-03-23-gate-calibration-brainstorm.md`
Bead: Sylveste-0rgc (parent: Sylveste-enxv)

## Architecture Constraint

Clavain CLI (`os/Clavain/cmd/clavain-cli/`) is a separate Go module (`github.com/mistakeknot/clavain-cli`). It **cannot** import `github.com/mistakeknot/intercore/internal/phase`. All intercore access is via subprocess calls through `runIC()`/`runICJSON()` to the `ic` binary. This means:
- Signal extraction → new `ic gate signals` subcommand (returns JSON)
- Calibrated tiers injection → `--calibration-file=<path>` flag on `ic run advance` and `ic gate check`
- Shared key function → `pkg/phase` (public package), not `internal/phase`
- Calibration command → calls `ic gate signals` via `runICJSON()`, not `store.GetGateSignals()` directly

## Batch Structure

6 batches, ordered by dependency. Each batch is independently testable.

## Batch 1: Bug Fixes (F1) — Sylveste-fi7b

**Goal:** Fix 4 pre-existing bugs. Must land before any calibration code.

### Task 1.1: Fix `scanRuns` column mismatch
**File:** `core/intercore/internal/phase/tx_queriers.go`
**Change:** Add `gateRulesJSON sql.NullString` to the declaration block (after `maxAgents`) and append `&gateRulesJSON` as the 21st `Scan` argument. After the scan, call `parseGateRulesJSON(gateRulesJSON)` and assign to `r.GateRules`, matching `store.go:786-790`.
**Test:** Add test in `gate_test.go`: create a run with `GateRules` set, advance a portfolio parent, verify `CheckChildrenAtPhase` reads children without crash.
**LOC:** ~8

### Task 1.2: Add `txBudgetQuerier` wrapper
**File:** `core/intercore/internal/phase/tx_queriers.go`
**Change:** Add `txBudgetQuerier` struct implementing `BudgetQuerier` interface, parallel to `txRuntrackQuerier`. Budget data IS in the same SQLite DB (`dispatches` table). The correct query mirrors `dispatch.Store.AggregateTokens` (`dispatch.go:416-430`):
```sql
SELECT COALESCE(SUM(input_tokens), 0) + COALESCE(SUM(output_tokens), 0)
FROM dispatches WHERE scope_id = ?
```
**Note:** Column is `scope_id` NOT `run_id`. Column names are `input_tokens` + `output_tokens`, NOT `token_count` (which doesn't exist). The `txBudgetQuerier` needs `scopeID` and `tokenBudget` passed at construction time (from the loaded run), since it can't call `store.Get` inside the tx independently.
```go
type txBudgetQuerier struct {
    q           Querier
    scopeID     string
    tokenBudget int64
}
```
**File:** `core/intercore/internal/phase/machine.go:162`
**Change:** Construct `txBQ` from the loaded run's `ScopeID` and `TokenBudget`, then replace `bq` with `txBQ` in the `evaluateGate` call, following the same nil-guard pattern on lines 148-159.
**Test:** Add test in `machine_test.go`: budget at 100%, advance should block within tx.
**LOC:** ~30

### Task 1.3: Wrap `Rollback` in transaction
**File:** `core/intercore/internal/phase/machine.go` (Rollback function, line 280)
**Change:** Add `BeginTx` at top, `defer tx.Rollback()`. Replace `store.RollbackPhase` with a new `store.RollbackPhaseQ(ctx, tx, ...)` method (add to `tx_queriers.go`). Replace `store.AddEvent` with `store.AddEventQ(ctx, tx, ...)`. Add `tx.Commit()` after both succeed. Fire callback after commit (outside tx, matching Advance pattern).
**File:** `core/intercore/internal/phase/tx_queriers.go`
**Change:** Add `RollbackPhaseQ(ctx, q Querier, id, currentPhase, targetPhase string) error` — same SQL as `RollbackPhase` using `q.ExecContext`. **Critical:** the zero-rows-affected branch (OCC error handling, `store.go:294-305`) must be replicated using `s.GetQ(ctx, q, id)` (NOT `s.Get` which reads outside the tx). Must classify all 3 failure modes: `ErrNotFound`, `ErrTerminalRun` (cancelled/failed), `ErrStalePhase`.
**Test:** Existing rollback tests should pass. Add test confirming both phase and event are atomic.
**LOC:** ~35

### Task 1.4: Wrap `cmdGateOverride` in transaction
**File:** `core/intercore/cmd/ic/gate.go` (cmdGateOverride, line 169)
**Change:** After opening the store, call `store.BeginTx(ctx)` + `defer tx.Rollback()`. Replace `store.UpdatePhase` (line 230) with `store.UpdatePhaseQ(ctx, tx, ...)`. Replace `store.AddEvent` (line 235) with `store.AddEventQ(ctx, tx, ...)`. The terminal-phase `UpdateStatus` (line 250) also moves inside the tx. Add `tx.Commit()` before JSON output.
**Test:** Existing gate_test.go tests should pass.
**LOC:** ~15

### Task 1.5: Fix override event tier recording
**File:** `core/intercore/cmd/ic/gate.go:241`
**Change:** Overrides only happen on hard blocks (soft gates auto-advance). Keep `TierHard` but add a code comment documenting this semantic. No behavioral change.
**LOC:** ~2

**Batch 1 checkpoint:** `go test ./internal/phase/... && go test ./cmd/ic/...`

---

## Batch 2: Shared Types + IC Subcommands (F2 prep + F4 prep)

**Goal:** Define shared types, key function, and `ic` subcommands that bridge the Clavain↔intercore module boundary.

### Task 2.1: Add `GateCalibrationKey` function to `pkg/phase`
**File:** `core/intercore/pkg/phase/phase.go` (public package, importable by Clavain)
**Change:** Add:
```go
// GateCalibrationKey returns the canonical map key for calibrated tier lookups.
// Used by signal extraction, calibration command, and runtime integration.
func GateCalibrationKey(checkType, fromPhase, toPhase string) string {
    return checkType + ":" + fromPhase + "→" + toPhase
}
```
**Also in:** `internal/phase/gate.go` — add a thin wrapper that delegates to `pkg/phase.GateCalibrationKey` for internal callers.
**Test:** `TestGateCalibrationKey` — verify format for known check×transition pairs.
**LOC:** ~10

### Task 2.2: Add `GateSignal` type
**File:** `core/intercore/internal/phase/phase.go`
**Change:** Add:
```go
type GateSignal struct {
    EventID    int64  `json:"event_id"`
    RunID      string `json:"run_id"`
    CheckType  string `json:"check_type"`
    FromPhase  string `json:"from_phase"`
    ToPhase    string `json:"to_phase"`
    SignalType string `json:"signal_type"` // "tp", "fp", "tn", "fn"
    CreatedAt  int64  `json:"created_at"`
    Category   string `json:"category,omitempty"` // overrides only
}
```
**LOC:** ~12

### Task 2.3: Add `CalibratedTiers` field to `GateConfig`
**File:** `core/intercore/internal/phase/machine.go`
**Change:** Add field to `GateConfig` struct:
```go
CalibratedTiers map[string]string // map[GateCalibrationKey]tier, populated from --calibration-file
```
**LOC:** ~2

### Task 2.4: Add `ic gate signals` subcommand
**File:** `core/intercore/cmd/ic/gate.go`
**Change:** New subcommand that calls `store.GetGateSignals(ctx, sinceID)` and outputs JSON. This is the bridge for Clavain's calibration command (Task 5.2) to access signal data across the module boundary via `runICJSON`.
```
ic gate signals [--since-id=N] [--json]
```
Returns `{"signals": [...], "cursor": N}`.
**LOC:** ~30

### Task 2.5: Add `--calibration-file` flag to `ic run advance` and `ic gate check`
**File:** `core/intercore/cmd/ic/run.go` (cmdRunAdvance)
**File:** `core/intercore/cmd/ic/gate.go` (cmdGateCheck)
**Change:** Parse `--calibration-file=<path>` flag. If provided, read and validate the JSON file, build `CalibratedTiers` map, and pass it into `GateConfig`. Validation includes:
- Staleness check (>24h → treat as absent, log warning)
- Promotion-only enforcement: skip entries where file says `"soft"` but hardcoded default is `"hard"`
- Skip `locked: true` entries (they fall through to hardcoded defaults)

The `LoadGateCalibration(path string) (map[string]string, error)` function lives in `core/intercore/cmd/ic/calibration_load.go` (new file), importable by both `run.go` and `gate.go`.
**LOC:** ~60

**Batch 2 checkpoint:** `go test ./internal/phase/... && go test ./cmd/ic/... && go test ./pkg/phase/...`

---

## Batch 3: Signal Extraction (F2) — Sylveste-pix4

**Goal:** Extract TP/FP/TN/FN signals from `phase_events`.

### Task 3.1: Add `GetGateSignals` to store
**File:** `core/intercore/internal/phase/store.go`
**Change:** New method `GetGateSignals(ctx context.Context, sinceID int64) ([]GateSignal, int64, error)`. Returns signals and max event ID (cursor).

Algorithm (two-pass + reclassification):
1. **Pass 1 — scan events:** Query `phase_events WHERE id > ? AND gate_result IS NOT NULL AND gate_result != 'none' ORDER BY id ASC`. For each event:
   - `event_type='block'` → candidate TP (keyed by run_id + from→to)
   - `event_type='override'` → FP (extract `override_category` from reason JSON; default `"uncategorized"` for pre-F5)
   - `event_type='advance' AND gate_result='pass'` → candidate TN
   - `event_type='advance' AND gate_result='fail'` → FP (soft gate override-by-advance)
2. **Pass 2 — rollback cross-check:** Query `phase_events WHERE event_type='rollback' AND id > ? ORDER BY id ASC`. For each rollback:
   - Find the advance events for the same `run_id` within 3 phases of the rollback target → reclassify those TNs as FN
   - Attribute FN to each gated transition in the rolled-back span using `gateRules` lookup
3. **Pass 3 — block→override reclassification:** For each override (already counted as FP in Pass 1), find the preceding block for the same run_id + transition → **remove the block from TP count** (it's no longer a true positive since it was overridden). Do NOT add another FP — the override FP from Pass 1 already accounts for this. This prevents double-counting.

Extract `check_type` from the `reason` JSON field (GateEvidence.Conditions[].Check). Events without structured reason → attribute to all checks for that transition.

**Test:** `TestGetGateSignals` in `store_test.go`: seed ~15 events covering TP, FP, TN, FN, multi-phase rollback, pre-F5 overrides, block→override sequence (verify no double-count).
**LOC:** ~80

**Batch 3 checkpoint:** `go test ./internal/phase/... -run TestGetGateSignals`

---

## Batch 4: Runtime Integration (F4) — Sylveste-p9pg

**Goal:** `evaluateGate` uses `CalibratedTiers` map for tier overrides.

### Task 4.1: Add calibration lookup in `evaluateGate`
**File:** `core/intercore/internal/phase/gate.go`
**Change:** In the per-rule tier override loop (line 179-187), after checking `rule.tier`, add a calibration lookup:
```go
if usingDefaults && cfg.CalibratedTiers != nil {
    calKey := GateCalibrationKey(rule.check, from, to)
    if calTier, ok := cfg.CalibratedTiers[calKey]; ok {
        if calTier == TierHard {
            tier = TierHard
        }
    }
}
```
**`usingDefaults` scope:** Set `true` in the `else if hr, ok := gateRules[...]` branch (line 153). Per-run and spec rules skip calibration. System-injected rules (portfolio/upstream/budget, lines 157-171) are always appended regardless — calibration applies to these only when the base rule source is hardcoded defaults. This is correct: if a user has per-run rules, they've explicitly chosen their gate configuration.

### Task 4.2: Add gate provenance `Source` to `GateCheckResult`
**File:** `core/intercore/internal/phase/gate.go`
**Change:** Add `Source string` field to `GateCheckResult`. In `evaluateGate`, set source to `"calibrated"`, `"spec"`, `"per-run"`, or `"default"` based on which rule branch was taken. Return the source in both `evaluateGate` and `EvaluateGate`.

**No `CalibrationInfo` in `GateCheckResult`** — L1 kernel doesn't know calibration statistics (weighted_n, FPR, etc.). Those are enriched in `ic gate check` output layer (Task 6.1) by reading the calibration file directly after calling `EvaluateGate`.
**LOC:** ~10

**Test:** `TestGate_CalibratedTier_Override` — set `CalibratedTiers` map with a hard override for `verdict_exists:review→polish`, verify soft default becomes hard and source is `"calibrated"`.
`TestGate_CalibratedTier_IgnoredWithSpecRules` — verify calibration is skipped when spec rules are present and source is `"spec"`.
**LOC total:** ~20

**Batch 4 checkpoint:** `go test ./internal/phase/... -run TestGate`

---

## Batch 5: Override Categorization + Calibration Command (F5 + F3)

### Task 5.1: Add `--justified`/`--expedient` flags to `cmdGateOverride`
**File:** `core/intercore/cmd/ic/gate.go`
**Change:** Parse `--justified` and `--expedient` flags in the arg loop. Determine category:
- Both flags → error
- `--justified` → `"justified"`
- `--expedient` → `"expedient"`
- Neither → `"uncategorized"` + deprecation warning to stderr

Embed category in reason JSON:
```go
reasonJSON := fmt.Sprintf(`{"override_category":%q,"reason":%q}`, category, reason)
```
Store `reasonJSON` as the event's `Reason` field.
**Test:** Test in `gate_test.go` or integration test: verify reason JSON includes `override_category`.
**LOC:** ~25

### Task 5.2: Calibration command — `calibrate-gate-tiers`
**File:** `os/Clavain/cmd/clavain-cli/gate_calibration.go` (new file)
**Change:** New command following existing `cmdInterspectCalibrateThresholds` pattern in `calibration.go`. Uses subprocess calls, NOT direct `internal/phase` import.

Steps:
1. Call `runICJSON(&signalResult, "gate", "signals", "--since-id="+lastCursor, "--json")` to get signals from intercore
2. Read existing `gate-tier-calibration.json` (if exists, not stale)
3. For each `(check_type, from→to)` key (construct via `pkg/phase.GateCalibrationKey`):
   - Compute weighted_n with 30-day half-life: `weight = exp(-ln(2) * age_days / 30)`
   - Compute FPR = weighted_FP / (weighted_TP + weighted_FP)
   - Compute FNR = weighted_FN / (weighted_TN + weighted_FN)
4. Apply promotion rule: if `current_tier == "soft" AND FNR > 0.30 AND weighted_n >= 10`:
   - Check 7-day cooldown since last tier change for this key
   - Check velocity limit (>2 changes in 90 days → lock)
   - If both pass → promote to `"hard"`
5. Skip `locked: true` entries
6. Write JSON via tmp+rename

**File path resolution:** Walk up from CWD looking for `.clavain/intercore.db`, use that parent dir. NOT `CLAVAIN_DIR`.
**Interspect events:** Emit `calibration_checkpoint`, `calibration_data_starvation`, `calibration_goodhart_warning` as appropriate.
**LOC:** ~130

### Task 5.3: Update Clavain advance wrapper to pass calibration file
**File:** `os/Clavain/cmd/clavain-cli/phase.go`
**Change:** In `cmdSprintAdvance` and `cmdEnforceGate`, discover calibration file path and pass it via the new flag:
```go
calPath := gateCalibrationFilePath() // walk up from CWD
if calPath != "" {
    runIC("run", "advance", runID, "--priority=0", "--calibration-file="+calPath)
} else {
    runIC("run", "advance", runID, "--priority=0")  // no calibration
}
```
**LOC:** ~15

**Batch 5 checkpoint:** `go test ./... && go build ./cmd/clavain-cli/...`

---

## Batch 6: Observability (F6) — Sylveste-pgl8

### Task 6.1: Gate provenance in `ic gate check` output
**File:** `core/intercore/cmd/ic/gate.go` (cmdGateCheck function)
**Change:** After calling `EvaluateGate` (which returns `Source`), enrich the output with calibration details by reading the calibration JSON file directly (if `--calibration-file` was passed):
- Calibrated: `(tier: soft, source: calibrated, fpr: 0.62)`
- Insufficient data: `(tier: soft, source: default, calibration: insufficient_data, n: 7/23)`
- Locked: `(tier: hard, source: default, calibration: locked)`

For `--json` output, add `source`, `calibration_status`, `fpr`, `weighted_n` fields. This enrichment happens in the `ic` output layer, not in `evaluateGate` (L1 doesn't know calibration stats).
**LOC:** ~25

### Task 6.2: `CLAVAIN_SKIP_GATE` audit event
**File:** `os/Clavain/cmd/clavain-cli/phase.go` (cmdEnforceGate)
**Change:** When `CLAVAIN_SKIP_GATE` is set and gate is bypassed, emit interspect event `calibration_skip_gate` with run_id and reason.
**LOC:** ~10

### Task 6.3: `calibration_file_stale` event
**File:** `core/intercore/cmd/ic/calibration_load.go`
**Change:** Already handled in Task 2.5 `LoadGateCalibration` — log warning when staleness detected. Also emit interspect event if interspect DB is available.
**LOC:** ~5

**Batch 6 checkpoint:** `go test ./... && go build -o ic ./cmd/ic && go build ./cmd/clavain-cli/...`

---

## Final Integration Test

```bash
cd core/intercore && bash test-integration.sh
```

After all 6 batches, verify:
1. Portfolio advance with `gate_rules` doesn't crash (F1)
2. Budget gate blocks within transaction (F1)
3. Rollback events are always recorded (F1)
4. Override with `--justified` stores category in reason JSON (F5)
5. `ic gate check --calibration-file=<path>` shows provenance (F6)
6. `ic gate signals --since-id=0` returns well-formed signal JSON (F2)

## Total Estimates

| Batch | Files Modified | New Files | LOC (approx) |
|-------|---------------|-----------|-------------|
| 1 | 3 (tx_queriers, machine, gate.go/ic) | 0 | ~90 |
| 2 | 4 (gate.go, phase.go, machine.go, run.go) | 1 (calibration_load.go) | ~114 |
| 3 | 1 (store.go) | 0 | ~80 |
| 4 | 1 (gate.go) | 0 | ~20 |
| 5 | 2 (gate.go/ic, phase.go/clavain) | 1 (gate_calibration.go) | ~170 |
| 6 | 2 (gate.go/ic, phase.go/clavain) | 0 | ~40 |
| **Total** | **10** | **2** | **~514** |

Note: higher than v1 plan (~470) due to `ic gate signals` subcommand and `--calibration-file` flag (subprocess architecture adds ~44 LOC vs direct import).

## Resolved Findings from Plan Review

| Finding | Resolution |
|---------|-----------|
| `internal/phase` not importable from Clavain | New `ic gate signals` subcommand + `--calibration-file` flag |
| `CalibratedTiers` has no path into `ic run advance` | `--calibration-file=<path>` flag reads/validates JSON in `ic` process |
| `CalibrationInfo` in `GateCheckResult` (L1 can't know stats) | Stripped to `Source string` only; enrichment in `ic gate check` output layer |
| `GateCalibrationKey` in `internal/phase` unreachable | Moved to `pkg/phase` (public package) |
| `txBudgetQuerier` wrong column/filter | Corrected to `input_tokens`+`output_tokens`, `scope_id` filter |
| `RollbackPhaseQ` OCC handling dropped | Explicitly uses `GetQ(ctx, q, id)` for 3-way error classification |
| Pass 3 double-counts FP | Reclassify block from TP to removed; FP already counted from override |
| `usingDefaults` vs injected rules | Documented: calibration applies to injected rules when base source is defaults |
