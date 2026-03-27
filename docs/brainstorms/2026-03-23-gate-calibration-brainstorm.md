---
artifact_type: brainstorm
bead: Sylveste-0rgc
stage: discover
---

# Gate Threshold Calibration: Pareto Optimal Design

## What We're Building

A calibration loop for Sylveste's phase gates that learns from gate outcomes (false positives from human overrides, false negatives from post-gate defects) and adapts gate enforcement tier (hard/soft) per check type and transition. Follows the PHILOSOPHY.md 4-stage pattern: hardcoded defaults → collect actuals → calibrate from history → defaults become fallback.

## Key Reframe

Gates are **binary existence checks** (artifact exists? agents complete? verdict exists?), not numeric thresholds. "Calibration" means learning which check×transition pairs should be hard (blocks) vs soft (warns) based on outcome evidence. The system has exactly three enforcement states: hard, soft, none. Calibration operates within the hard/soft band only.

## Design Decisions (Synthesized from 5-Agent Research)

### 1. Calibration adjusts enforcement only, never composition

- **Composition** (which checks run) is already solved by the 3-level precedence: per-run stored rules > agency spec rules > hardcoded defaults
- **Enforcement** (hard vs soft) is what calibration adjusts
- Calibration **cannot introduce or remove checks** — that's human-only
- Calibration **cannot create gates for P4+** — priority≥4 is a hard opt-out

### 2. Key space: `(check_type, from_phase, to_phase)`

~10 active keys matching the `gateRules` map structure. Small enough to be fully inspectable. Priority is NOT in the key — a check's FPR doesn't change based on who's asking. Per-check granularity matters because `verdict_exists` (timing-dependent, moderate FP risk) behaves differently from `artifact_exists` (deterministic, near-zero FP).

### 3. Signal extraction from existing `phase_events` — zero schema changes

All 4 confusion matrix cells are extractable:

| Signal | Source | Filter |
|--------|--------|--------|
| **True Positive** | `phase_events` | `event_type='block'` with no subsequent override |
| **False Positive** | `phase_events` | `event_type='override'` OR (`event_type='advance'` AND `gate_result='fail'`) |
| **True Negative** | `phase_events` | `event_type='advance'` AND `gate_result='pass'` with no subsequent rollback |
| **False Negative** | `phase_events` | `event_type='rollback'` (correlate to the advance it undoes) |

Cursor-based extraction using `phase_events.id` (monotonic integer), matching existing interspect/review event cursor patterns. Programmatic bypasses (`gate_result='none'`) excluded — no gate ran, no signal.

### 4. Update rule: discrete tier promotion/demotion with asymmetric thresholds

```
For each (check_type, transition) with weighted_n >= 10:
  if current_tier == "soft" AND FNR > 0.30:  → promote to "hard"
  (hard→soft demotion is NEVER automatic — human-only via ic gate-calibration demote <key>)
```

- **Promotion only**: calibration can promote soft→hard but **cannot demote hard→soft**. Demotion is a human-only action requiring `ic gate-calibration demote <key> --reason=<reason>`. This is the safest first implementation (Option B from safety review).
- **One step per cycle**: soft→hard only. Never hard→none or hard→soft.
- **Minimum weighted_n = 10**: below this, hardcoded defaults stand. With 30-day half-life, this requires ~23 raw observations uniformly distributed over 90 days. P0-P1 gates may not activate calibration for months — this is acceptable safety bias.
- **90-day window with 30-day half-life**: exponential decay weights recent observations higher.
- **7-day cooldown**: minimum 7 days between tier changes per key. Prevents oscillation.
- **Velocity limit**: if a key has changed tier >2 times in the 90-day window, lock it and require human review.

### 5. Storage: JSON calibration file with staleness SLA

`gate-tier-calibration.json` in `.clavain/`:

```json
{
  "calibrated_at": "2026-03-23T12:00:00Z",
  "window_days": 90,
  "half_life_days": 30,
  "overrides": {
    "verdict_exists:review→polish": {
      "tier": "hard",
      "fpr": 0.12,
      "fnr": 0.35,
      "weighted_n": 14.3,
      "raw_n": 22,
      "last_observation": "2026-03-20T08:15:00Z",
      "locked": false
    }
  }
}
```

- Follows existing `phase-cost-calibration.json` pattern
- Missing/corrupt file = defaults only (Stage 4 fallback)
- Staleness SLA: 24 hours max, checked at read time with warning
- `locked: true` entries exempt from calibration (human override)

### 6. Rule precedence with calibration inserted

```
per-run stored rules > agency spec rules > calibrated rules > hardcoded defaults
```

No merge between layers — each is a complete replacement, matching the existing `if/else if` chain in `evaluateGate`.

### 7. Safety invariants (revised after flux-drive review)

- **No auto-demotion**: Calibration cannot demote hard→soft. Only a human via `ic gate-calibration demote` can do this. Eliminates the rubber-stamp risk and alignment-faking concern.
- **No L1→L2 file reads**: `evaluateGate` does NOT read the JSON file. Clavain (L2) reads the file during Advance setup and injects calibrated tiers via a `CalibratedTiers map[string]string` field on `GateConfig`. L1 kernel does a map lookup, no file I/O.
- **Hardcoded calibration file path**: Path is NOT env-var derived. Uses a fixed project-relative path to prevent agent redirection attacks.
- **`locked: true` enforced at read time**: `evaluateGate` checks the lock flag and ignores calibrated tier for locked entries. Lock can only be set by a human via `ic gate-calibration lock <key>`, never by the calibration command.
- **Override categorization required**: `ic gate override` must accept `--justified` or `--expedient` tag. Only `justified` overrides count toward FPR signal. Ships with calibration, not deferred.
- Calibration changes are prospective only (next Advance call)
- One tier step per calibration cycle per key, 7-day cooldown
- Agency spec rules can declare `calibration_locked: true` to opt out
- Stale file (>48h) treated as absent — falls through to hardcoded defaults

### 8. Observability: structured events in interspect evidence table

4 new event types using existing schema (zero DDL):
- `calibration_checkpoint`: per-agent metrics after each calibration run
- `calibration_goodhart_warning`: override apply rate up + success rate down
- `calibration_data_starvation`: insufficient samples for calibration
- `calibration_file_corrupt`: file parse failure, preserved for forensics

Gate provenance in `ic gate check` output: `(tier: soft, source: calibrated, fpr: 0.62)`

## 4-Stage Mapping

| Stage | Implementation |
|-------|---------------|
| 1. Hardcoded defaults | `gateRules` map + priority→tier switch (existing) |
| 2. Collect actuals | `phase_events` with gate_result, gate_tier, reason JSON (existing) |
| 3. Calibrate from history | New `calibrate-gate-tiers` command: reads phase_events, computes FPR/FNR, writes `gate-tier-calibration.json` |
| 4. Defaults become fallback | Clavain reads calibration file, injects into `GateConfig.CalibratedTiers`; `evaluateGate` does map lookup, falls back to gateRules on missing/corrupt/insufficient/stale data |

## Implementation Scope

| Component | Files | Effort |
|-----------|-------|--------|
| Signal extraction query | `core/intercore/internal/phase/store.go` | Small (~40 lines) |
| Calibration command | `os/Clavain/cmd/clavain-cli/calibration.go` | Medium (~150 lines, parallel to existing) |
| Runtime integration | `core/intercore/internal/phase/gate.go` | Small (~15 lines in evaluateGate) |
| Calibration types | `core/intercore/internal/phase/phase.go` | Small (~20 lines) |
| Gate provenance | `core/intercore/cmd/ic/gate.go` + `gate.go` | Small (~10 lines) |
| Observability events | `os/Clavain/cmd/clavain-cli/calibration.go` | Small (~30 lines) |
| SessionEnd trigger | Clavain hooks | Small (~5 lines) |

Total: ~270 lines of new code across 6 files.

## Pre-existing Bugs Discovered (fix before or alongside calibration)

1. **P0: BudgetQuerier not tx-scoped** (`machine.go:162`): `bq` is passed to `evaluateGate` outside the Advance transaction. Budget gate can read stale state. Fix: add `txBudgetQuerier` in `tx_queriers.go`.
2. **P0: scanRuns column mismatch** (`tx_queriers.go:74`): `scanRuns` scans 20 columns against `runCols`'s 21 (missing `gate_rules`). Portfolio gate checks crash at runtime. Fix: add `gateRulesJSON` to scan.
3. **P1: Rollback atomicity split** (`machine.go:296`): `RollbackPhase` and `AddEvent` not in same transaction. A failed `AddEvent` drops the rollback event, silently undercounting false negatives. Fix: wrap in single tx.

## Resolved Questions (from flux-drive review)

1. **Override categorization**: RESOLVED — must ship with calibration. `ic gate override --justified` / `--expedient`. Only justified overrides count toward FPR.
2. **Hard→soft demotion**: RESOLVED — no auto-demotion. Human-only via `ic gate-calibration demote`.
3. **SQLite vs JSON**: RESOLVED — JSON file, but Clavain reads it and injects into `GateConfig` (no file I/O in L1 kernel).
4. **L1/L2 boundary**: RESOLVED — `GateConfig.CalibratedTiers map[string]string` injected by Clavain at call site.
5. **Calibration scope**: Calibration applies only when hardcoded defaults apply (no per-run or spec rules for that transition).

## Remaining Open Questions

1. **Defect attribution window**: How many phases after a gate pass should a defect be attributable? Algorithm agent suggests 3. Needs validation.
2. **Calibration file path**: Project-local (`.clavain/`) or user-home (`~/.clavain/`)? Phase-cost calibration precedent needs checking.
3. **FN underestimation**: Rollback events are rare and can be lost (pre-existing bug). Should FN extraction also cross-check for runs whose current phase is behind the gated phase (direct phase comparison, not just rollback events)?
