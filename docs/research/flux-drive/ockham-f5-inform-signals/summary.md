## Flux Drive Review — ockham-f5-inform-signals

**Reviewed**: 2026-04-05 | **Agents**: 10 (5 adjacent-domain, 5 distant-domain) | **Verdict**: needs-changes

### Verdict Summary
| Agent | Status | Summary |
|-------|--------|---------|
| fd-statistical-process-control | warn | 10-bead window has inadequate statistical power for 20% drift detection |
| fd-feedback-loop-closure | warn | No signal-clear condition defined; offset windup risk |
| fd-data-pipeline-reliability | warn | first_attempt_pass_rate may violate Signal Independence |
| fd-go-metrics-implementation | pass | Package structure clean; timeout isolation needed for subprocess calls |
| fd-sqlite-rolling-window | pass | Schema extension path clear; retention policy needed |
| fd-sake-toji-moromi-fermentation | warn | Independent thresholds miss compensatory gaming between metrics |
| fd-carillon-bell-tuning | warn | No hysteresis between fire/clear thresholds; oscillation risk |
| fd-persian-qanat-hydrology | warn | Fixed 20% threshold ignores per-theme variance profiles |
| fd-tibetan-sand-mandala-dissolution | warn | No retention policy or staleness check for rolling window data or signal state |
| fd-ottoman-waqf-endowment | pass | Advisory actuation is self-limiting; offset bounds exist (OffsetMin/OffsetMax) |

### Critical Findings (P0)

**P0-1: first_attempt_pass_rate may violate Signal Independence invariant** (fd-data-pipeline-reliability)

The vision doc requires "at least one agent-unwritable anomaly input." If `first_attempt_pass_rate` is sourced from interspect evidence (which agents write), agents can influence their own pass rate by writing favorable evidence. The brainstorm lists interspect as a data source but does not specify which signals draw from agent-writable vs agent-unwritable channels. This is a design-level integrity issue: a pleasure signal that agents can game provides false positive evidence for authority ratchet promotions.

**Concrete failure**: Agent writes favorable quality-gate evidence to interspect, inflating first_attempt_pass_rate, which feeds the authority ratchet, which promotes the agent to higher autonomy — a self-reinforcing loop with no external check.

**Fix**: Source first_attempt_pass_rate from quality-gates verdicts (written by the orchestrator, not the agent) or from beads state transitions (agent-unwritable). The brainstorm's "Open Questions" section already asks about this — the answer should be "agent-unwritable source only."

### Important Findings (P1)

**P1-1: 10-bead minimum window has insufficient statistical power for 20% drift detection** (fd-statistical-process-control, fd-persian-qanat-hydrology — 2/10 agents)

For cycle time data (right-skewed distribution), detecting a 20% shift in the mean with 10 observations yields a false-negative rate well above 30% (power < 0.70) even under normal distribution assumptions. With the right-skewed distributions typical of cycle time, it is worse. The brainstorm should specify whether it detects drift in the median (p50, as implied by `cycle_time_p50_trend`) or the mean, and the window size should be calibrated to the detection target. A 10-bead window is reasonable for a "something might be wrong" advisory, but the 20% threshold should be expressed relative to the theme's own variance (standard deviations from baseline), not as an absolute percentage.

**Fix**: Either (a) increase the minimum window to 20 beads for reliable 20% detection, or (b) accept 10 beads but widen the threshold to 30-40% for advisory-only signals (acceptable for Tier 1 INFORM), or (c) use median-based detection with a rank-order test (e.g., Mann-Whitney) that does not assume normality.

**P1-2: No signal-clear condition defined — INFORM signals persist indefinitely** (fd-feedback-loop-closure, fd-carillon-bell-tuning, fd-tibetan-sand-mandala-dissolution — 3/10 agents)

The brainstorm says "Recovery is automatic when signal clears" but does not define the clear condition. Without an explicit clear threshold, the signal fires once and the advisory offset persists forever. The check.go code pattern (set signal_state but no code path to unset) confirms this is not yet designed.

**Concrete failure**: INFORM fires for theme A at 20% drift, offset adjusts. Theme recovers. But signal state remains "fired" in signals.db indefinitely because no code path sets it to "cleared." Offset persists, starving the theme.

**Fix**: Define clear condition: drift drops below X% (where X < 20%, e.g., 10%) for N consecutive evaluations. This hysteresis band prevents oscillation.

**P1-3: No hysteresis between fire and clear thresholds — oscillation risk** (fd-carillon-bell-tuning, fd-feedback-loop-closure — 2/10 agents)

If fire threshold = clear threshold = 20%, a metric hovering at 19-21% will oscillate between fired and cleared on every check cycle, producing a stream of interspect events and toggling dispatch offsets rapidly. This is the beat-frequency problem in carillon tuning: near-threshold metrics produce noise, not signal.

**Fix**: Set fire threshold at 20% degradation, clear threshold at 10% degradation. The brainstorm should specify both thresholds explicitly.

**P1-4: Simultaneous INFORM signals on multiple themes can drive all offsets to OffsetMin (-6)** (fd-feedback-loop-closure)

The scoring package clamps offsets to `[OffsetMin, OffsetMax]` = `[-6, +6]`. If 3+ themes fire INFORM simultaneously and each advisory reduces offset, the offsets can pile up toward -6 across all themes. This is integral windup: the advisory system's cumulative effect becomes functionally equivalent to a halt, even though each individual adjustment is "advisory only."

**Fix**: Add a factory-level guard: total advisory offset reduction across all themes cannot exceed a configurable ceiling (e.g., sum of advisory reductions <= 12 across all themes). Or: each INFORM advisory adjusts by at most -1 per check cycle, not the full penalty at once.

### P2 Findings

**P2-1: Independent pleasure signals miss compensatory gaming** (fd-sake-toji-moromi-fermentation)

If `first_attempt_pass_rate` improves (0.7 to 0.9) while `cycle_time_p50` degrades by 40%, agents may be cherry-picking easy beads to inflate pass rate at the cost of throughput. Each signal individually looks acceptable. The brainstorm evaluates each signal independently with no cross-correlation check. Consider a composite productivity signal or cross-signal ratio check.

**P2-2: Rolling window data has no retention policy** (fd-sqlite-rolling-window, fd-tibetan-sand-mandala-dissolution)

The brainstorm proposes an `inform_signals` table for rolling window data but does not specify cleanup. With every `ockham check` run inserting new rows, the table grows unboundedly. For a 10-bead window, only the latest 10-20 rows per theme matter — older data should be pruned during the check cycle. The existing signals.db has no cleanup logic.

**P2-3: Stale signal state on dormant themes** (fd-tibetan-sand-mandala-dissolution, fd-persian-qanat-hydrology)

If a theme has no new beads for 30 days, its INFORM signal (computed from month-old data) persists in signal_state. When the theme resumes, the stale signal biases dispatch. Add a staleness check: if no new beads in N days, expire the signal state to a "cold" sentinel.

**P2-4: Missing data source produces silent all-clear** (fd-data-pipeline-reliability)

If `bd` is unavailable, `beadsFromBD()` returns an error (good), but if `cost-query.sh` returns empty results or interspect confidence.json is stale, the system may compute zero signals — a silent false all-clear rather than an explicit "insufficient data" state.

**P2-5: ockham check cadence vs data arrival rate** (fd-persian-qanat-hydrology)

If check runs hourly but a slow theme produces 2 beads/day, the same 10-bead window is re-evaluated 12 times with no new information. Add a short-circuit: if no new beads since last evaluation for a theme, skip signal re-evaluation for that theme.

**P2-6: Signal clear events not recorded to interspect** (fd-tibetan-sand-mandala-dissolution)

The brainstorm specifies that INFORM signal fires emit `weight_drift` events to interspect, but does not mention recording clear events. Without clear events, signal duration cannot be audited. Record both fire and clear transitions.

### Improvements Suggested

1. **Factory-level aggregate pleasure check** (fd-carillon-bell-tuning): If the median per-theme trend is degrading even though no individual theme crosses its threshold, emit a factory-level INFORM. All themes drifting 15% each is worse than one theme drifting 25%.

2. **Per-signal minimum window sizes** (fd-statistical-process-control, fd-persian-qanat-hydrology): `cost_per_landed_change` likely has higher variance than `first_attempt_pass_rate` — consider different minimum windows per signal rather than a uniform 10.

3. **Cold-start sentinel for recovered DB** (fd-tibetan-sand-mandala-dissolution): When signals.db is recreated via `recover()`, initialize signal state to explicit `cold_start` sentinels rather than empty tables. Downstream code can then distinguish "never evaluated" from "evaluated and healthy."

4. **Graduated advisory response** (fd-sake-toji-moromi-fermentation): Rather than binary (no adjustment below threshold, full adjustment above), adjust offset proportionally to drift magnitude: -1 for 20-30%, -2 for 30-50%, etc.

5. **Advisory offset audit trail** (fd-persian-qanat-hydrology): When offset adjusts for theme A, log which themes implicitly gained budget share from the rebalancing, making cascade effects visible.

### Section Heat Map
| Section | Issues | Improvements | Agents Reporting |
|---------|--------|-------------|-----------------|
| Weight-drift detection | P0:0, P1:3 | 3 | spc, feedback-loop, carillon, qanat, mandala |
| Pleasure signals | P0:1, P1:0, P2:1 | 2 | data-pipeline, sake-toji, spc |
| Storage (signals.db) | P0:0, P1:0, P2:2 | 1 | sqlite-rolling, mandala |
| Open Questions | P0:0, P1:0 | 0 | data-pipeline (confirms Q2 is critical) |

### Conflicts

No direct conflicts. All agents agree that:
- Signal clear conditions are missing (convergence: 3/10)
- Hysteresis is needed (convergence: 2/10)
- 10-bead window is marginal (convergence: 2/10)

The fd-ottoman-waqf-endowment agent found no blocking issues for this brainstorm specifically — its concerns about institutional perpetuity and learning decay are less relevant to a short-lived advisory signal system (by design, INFORM signals are transient, not permanent).

### Files
- Summary: `docs/research/flux-drive/ockham-f5-inform-signals/summary.md`
- Findings: `docs/research/flux-drive/ockham-f5-inform-signals/findings.json`
