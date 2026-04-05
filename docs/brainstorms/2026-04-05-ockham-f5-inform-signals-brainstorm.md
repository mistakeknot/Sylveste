---
artifact_type: brainstorm
bead: sylveste-usj
stage: discover
---

# Ockham F5: Tier 1 INFORM Signals + Pleasure Signals

## What We're Building

Wave 1 anomaly detection for Ockham's algedonic signal system. Two capabilities:

1. **Weight-drift detection** — after each bead completion, compare actual cycle time and quality gate pass rate against theme baselines. When a theme's actual-vs-predicted ratio degrades past 20% over a rolling window (minimum 10 beads), emit a Tier 1 INFORM signal and log a `weight_drift` event to interspect. Advisory only — offsets adjust automatically, no freeze.

2. **Three pleasure signals** — positive indicators that enable authority ratchet promotions and validate weight configuration:
   - `first_attempt_pass_rate` — fraction of beads passing quality gates on first attempt
   - `cycle_time_p50_trend` — improving (decreasing) over a rolling window
   - `cost_per_landed_change_trend` — stable or improving over a rolling window

## Why This Approach

The vision doc (§Algedonic Signals, §Pleasure Signals Wave 1) defines these precisely. Weight-drift ships alongside Tier 1 INFORM because "without it, Ockham is a governor that cannot tell when its own governance is harmful." Pleasure signals ship in Wave 1 (not deferred to Wave 3) because the authority ratchet needs positive evidence to promote domains.

## Key Decisions

- **Integration point**: `ockham check` already runs periodic checks (authority snapshots, reconfirmation). INFORM signal evaluation slots in as a new step.
- **Data sources**: beads (cycle time via `bd`), quality-gates verdicts (pass rate — orchestrator-written, agent-unwritable), interstat (cost per landed change via cost-query.sh). Interspect for cross-reference only, never as a primary pleasure signal source.
- **first_attempt_pass_rate source** (P0 fix): Must come from quality-gates verdicts or beads state transitions — NOT interspect evidence, which agents can write. This preserves Signal Independence (vision doc invariant). Agents must not influence the data that feeds their own authority promotions.
- **Storage**: signals.db `signal_state` table for INFORM signal state. New `bead_metrics` table for rolling window data with per-theme retention (keep 2x window size, prune older rows each check cycle).
- **Actuation**: Advisory only — Tier 1 INFORM adjusts dispatch offsets by at most -1 per theme per check cycle (rate-limited to prevent integral windup). Factory-level guard: total advisory reduction across all themes capped at configurable ceiling. Recovery is automatic when signal clears.
- **Thresholds**: 10-bead minimum window, 20% degradation threshold for fire. Uses p50 (median) for cycle time to handle right-skewed distributions.
- **Signal clear condition** (P1 fix): Drift drops below 10% for 3 consecutive evaluations. Hysteresis band: fire at 20%, clear at 10%. Both fire and clear transitions recorded to interspect.
- **Short-circuit**: If no new beads since last evaluation for a theme, skip signal re-evaluation (avoid redundant processing on stale data).
- **Staleness**: If no new beads for a theme in 14 days, expire signal state to `stale` sentinel. Stale signals do not affect dispatch.
- **anomaly package**: Currently a stub (`type State struct{}`). F5 fills this with real signal evaluation that returns per-theme INFORM state to the governor.

## Resolved Questions (from flux-drive review)

- **first_attempt_pass_rate source**: Quality-gates verdicts (agent-unwritable). Not interspect.
- **Rolling window size**: 10 beads for all signals (advisory-only, so lower power is acceptable). Per-signal windows can be tuned later.
- **Pleasure signal thresholds**: Independent from weight-drift. Pleasure signals are trend-based (improving/stable/degrading), not threshold-based.
- **Hysteresis**: Fire at 20% degradation, clear at 10%. Prevents oscillation.
- **Windup prevention**: Rate-limit advisory offset to -1 per theme per check cycle. Factory ceiling on total advisory reduction.

## Open Questions

- Factory-level aggregate pleasure check (all themes drifting 15% each vs one theme at 25%) — defer to Wave 2?
- Graduated advisory response (offset proportional to drift magnitude) vs binary — start binary, graduate later?
- Cross-signal correlation check (pass rate up + cycle time up = cherry-picking) — worth the complexity in Wave 1?
