---
artifact_type: prd
bead: sylveste-usj
stage: design
---

# PRD: Ockham F5 — Tier 1 INFORM Signals + Pleasure Signals

## Problem

Ockham has no way to detect when its own weight configuration is harming the factory. The anomaly subsystem is a stub. Without feedback, misconfigured intent degrades dispatch indefinitely. The authority ratchet has no positive evidence to promote domains.

## Solution

Implement Wave 1 anomaly detection: weight-drift detection (per-theme, advisory-only) and three pleasure signals. Signals evaluate during `ockham check`, store state in signals.db, and emit interspect events. Advisory offset adjustments are rate-limited and reversible.

## Features

### F1: Anomaly Package + Bead Metrics Table

**What:** Replace the `anomaly.State` stub with a real package that reads rolling window metrics and returns per-theme signal state. Add `bead_metrics` table to signals.db (schema v2 migration).

**Acceptance criteria:**
- [ ] `anomaly.State` carries per-theme INFORM signal state (fired/cleared/stale)
- [ ] `bead_metrics` table stores: bead_id, theme, cycle_time_ms, pass_first_attempt (bool), cost_usd, completed_at
- [ ] Schema migration from v1 to v2 is idempotent (safe to run twice)
- [ ] Rolling window query returns latest N beads per theme efficiently (indexed on theme + completed_at)
- [ ] Retention: prune rows older than 2x window size per theme each check cycle
- [ ] `go test ./internal/anomaly/...` passes

### F2: Weight-Drift Detection

**What:** Per-theme drift evaluation comparing actual p50 cycle time and pass rate against the rolling window baseline. Fire at 20% degradation, clear at 10% (hysteresis). Rate-limited offset advisory.

**Acceptance criteria:**
- [ ] Drift computed on p50 (median) cycle time per theme, not mean
- [ ] Fire threshold: 20% degradation from rolling baseline (minimum 10 beads in window). Note: 10-bead window has ~50% power for 20% drift detection — acceptable for advisory signals. Use up to 30 beads when available (adaptive window).
- [ ] Clear threshold: 10% degradation for 3 consecutive evaluations
- [ ] Advisory offset adjustment: at most -1 per theme per check cycle
- [ ] Factory-level guard: sum of advisory reductions across all themes <= configurable ceiling (default 12)
- [ ] Short-circuit: skip evaluation if no new beads since last check for a theme
- [ ] Interspect events emitted for both fire and clear transitions (with before/after state)
- [ ] Signal state written to `signal_state` table with key `inform:<theme>`
- [ ] Staleness: themes with no new beads in 14 days → signal state expires to `stale`
- [ ] `go test ./internal/anomaly/...` covers fire, clear, hysteresis, windup, staleness

### F3: Pleasure Signals

**What:** Three positive health indicators stored in signal_state, evaluated during `ockham check`.

**Acceptance criteria:**
- [ ] `first_attempt_pass_rate`: sourced from quality-gates verdicts (agent-unwritable), NOT interspect evidence
- [ ] `cycle_time_p50_trend`: computed from rolling window, stored as improving/stable/degrading
- [ ] `cost_per_landed_change_trend`: sourced from interstat via cost-query.sh, stored as improving/stable/degrading
- [ ] Each signal stored in `signal_state` with key `pleasure:<signal_name>:<theme>`
- [ ] Degraded mode: if a data source is unavailable, that signal is marked `insufficient_data` (not zero/healthy)
- [ ] `go test` covers each signal with real data, degraded mode, and trend direction changes

### F4: Governor Integration + CLI

**What:** Wire anomaly.State into governor.Evaluate() so dispatch offsets incorporate INFORM advisory adjustments. Add `ockham signals` status command.

**Acceptance criteria:**
- [ ] `governor.Evaluate()` reads anomaly state and applies advisory offsets (additive, after intent offsets). Combined result (intent + advisory) re-clamped to [-6, +6]. Factory guard (sum <= 12) applies before per-bead clamping.
- [ ] `scoring.Score()` accepts anomaly.State and incorporates advisory offsets per theme
- [ ] `ockham check` includes signal evaluation step (after authority snapshot, before reconfirmation)
- [ ] `ockham signals` command shows: per-theme INFORM state (fired/cleared/stale), pleasure signal values, last evaluation timestamp
- [ ] Dual logging: both pre-advisory (`raw_score`) and post-advisory (`final_score`) recorded
- [ ] Halted factory (factory-paused.json) skips signal evaluation entirely (INV-8)
- [ ] `go test ./internal/governor/...` covers advisory offset application, halt guard, degraded anomaly

## Non-goals

- Tier 2 CONSTRAIN signals (Wave 2)
- Authority ratchet promotions/demotions based on pleasure signals (Wave 3 — signals are stored but not acted on for authority)
- Factory-level aggregate pleasure checks (defer to Wave 2)
- Cross-signal correlation checks (defer — start with independent evaluation)
- Graduated advisory response (start binary: no adjustment below threshold, -1 per cycle above)

## Dependencies

- `bd` CLI for bead data (cycle time, completion status). **Degradation:** if bd unavailable, signal evaluation short-circuits (no new beads → skip). Log degraded-mode event. Never produce false all-clear from missing data.
- `cost-query.sh` from interstat for cost per landed change. **Degradation:** cost signal marked `insufficient_data`.
- Quality-gates verdicts for first_attempt_pass_rate (beads state or Clavain verdict files). **Degradation:** pass rate signal marked `insufficient_data`.
- signals.db (F4 shipped, schema v1 exists)
- interspect event pipeline for fire/clear event recording. **Degradation:** signal evaluation proceeds; interspect write is fire-and-forget.

## Open Questions

- Quality-gates verdict source: Clavain's `.clavain/verdicts/` directory or beads state transitions? Need to verify which is agent-unwritable.
- Interspect event format for INFORM fire/clear — coordinate with interspect hook_id allowlist.
