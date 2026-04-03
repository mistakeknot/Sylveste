---
artifact_type: flux-drive-review
agent: fd-grid-dispatch
track: B-orthogonal
target: docs/brainstorms/2026-04-03-ockham-vision-brainstorm.md
reviewed_at: 2026-04-03
---

# fd-grid-dispatch Review — Ockham Vision

### Findings Index
- P0 | GRID-1 | "Key Decisions §5 — Safety invariants + §2 Dispatch integration" | Safety invariants validated per-grant in isolation — no global authority configuration check across simultaneously in-flight beads
- P1 | GRID-2 | "Key Decisions §3 — Tier 2 CONSTRAIN + §1 Four subsystems" | CONSTRAIN-tier domain freeze is local — dependency-chain downstream domains continue executing into a frozen upstream
- P2 | GRID-3 | "Key Decisions §4 — Autonomy ratchet" | Ratchet lacks hysteresis — promotion and demotion use symmetric thresholds, enabling oscillation near the boundary
- P2 | GRID-4 | "Key Decisions §2 + §1 Dispatch subsystem" | Dispatch weights are purely reactive — no forecast layer to pre-position resources before theme density shifts
- P3 | GRID-5 | "Key Decisions §3 — Tier 3 BYPASS + Open Question §5" | No reserve capacity accounting — BYPASS requires a principal who can respond, but principal unavailability is not modeled as a degraded-state scenario

Verdict: risky

### Summary

The dominant concern from a security-constrained dispatch perspective is that Ockham's safety invariants are per-grant checks, not global authority state checks. In grid dispatch, a set of individually-valid generator commitments can still produce a globally-invalid dispatch if their combined loading violates a transmission constraint. The analogous failure is: three agents each hold individually valid autonomous-tier grants in overlapping domains, and their simultaneous execution creates an aggregate authority configuration that violates the delegation ceiling invariant at the system level. The brainstorm does not describe a global authority state validator running before each dispatch cycle. The CONSTRAIN-tier freeze is a second acute concern: it applies locally to the frozen domain without propagating weight suppression to domains that consume the frozen domain's outputs, allowing cascading failures in domains that appear locally healthy. The ratchet hysteresis gap is a systemic quality issue that will produce oscillating agents near performance boundaries.

### Issues Found

1. **P0 — GRID-1: Global authority configuration is not validated before dispatch**

   The five safety invariants (§Key Decisions §5) are correct necessary conditions. Invariant 2 (delegation ceiling) and Invariant 3 (action-time validation) are both described as per-grant checks. The brainstorm describes Ockham writing `ockham_weight` per bead via `ic state set` — there is no described step that validates the global authority configuration that results from all currently-claimed beads plus the proposed new dispatch before issuing weights.

   Failure scenario: Agent A holds an autonomous grant in `interverse/**`. Agent B holds an autonomous grant in `core/intercore/**`. Agent C holds an autonomous grant in `core/intermute/**`. Each grant individually satisfies the delegation ceiling invariant — none exceeds the grantor's level. But Agents B and C together cover the entirety of `core/**` at autonomous tier. The principal's intent was to authorize autonomous execution for specific sub-domains, not autonomous execution across all of core simultaneously. The combined authority configuration produces a state where every file in the factory is reachable by autonomous agents simultaneously — which may violate the intent of the delegation ceiling even though each individual grant does not. No check runs against the aggregate in-flight authority state.

   Grid dispatch analogy: a set of generator dispatch instructions is individually feasible per generator but collectively overloads a shared transmission corridor. The N-1 contingency check operates on the combined dispatch, not on each generator in isolation.

   Smallest fix: Before `dispatch_rescore()` issues weights for a new bead, run an `authority_configuration_check(proposed_dispatch + current_claims)` that validates: (a) no two simultaneously-active grants produce combined domain coverage exceeding a configurable overlap limit, (b) the aggregate authority state does not grant more than one agent autonomous access to any single file path. This is one pre-dispatch validation function added to the dispatch subsystem's weight-computation path.

2. **P1 — GRID-2: CONSTRAIN freeze does not propagate to downstream-dependent domains**

   The brainstorm specifies Tier 2 CONSTRAIN as: "Freeze domain, set autonomy_tier=shadow" (§Key Decisions §3 §Tier 2). The freeze applies to the named domain. In power systems, a transmission constraint in one zone raises locational marginal prices in adjacent zones — because the constraint in one zone affects what adjacent zones can economically dispatch, even if those zones are not themselves constrained.

   Failure scenario: CONSTRAIN fires on `core/**` after three quarantines. Ockham freezes `core/**` and sets its agents to shadow tier. `interverse/**` is not constrained and continues receiving normal dispatch weights. Interverse agents are actively building new plugins that depend on APIs defined in `core/intercore/`. Each bead they complete produces artifacts that will fail integration the moment they attempt to land against a frozen `core/**`. The interverse domain looks locally healthy — good completion rates, no anomalies — but it is generating work that will fail on delivery. The factory is accumulating integration debt in a domain that appears green.

   Smallest fix: When the Anomaly subsystem fires CONSTRAIN on a domain, the Dispatch subsystem should run a dependency-graph lookup to identify domains whose output consumers include the frozen domain. Those dependent domains receive an INFORM-tier weight suppression (e.g., 0.7x on new beads that produce core-dependent artifacts) until the CONSTRAIN condition clears. This does not freeze interverse — it slows the rate of new integration-dependent work without halting productive interverse development that is core-independent.

3. **P2 — GRID-3: Autonomy ratchet lacks hysteresis — symmetric thresholds enable oscillation**

   The brainstorm specifies: "Promotion requires explicit pleasure signals (first_attempt_pass_rate > threshold, cycle_time_trend improving) persisting past multi-window confirmation. Demotion fires faster than promotion (asymmetric)" (§Key Decisions §4). This correctly identifies asymmetric timing as important. But it does not specify whether the promotion threshold and demotion threshold are different values or only different time windows.

   If promotion requires `pass_rate > 0.80` persisting 48h, and demotion fires at `pass_rate < 0.80` over 1h, an agent performing at 0.79-0.81 will promote in 48h, then demote within the first 1h of supervised execution at 0.79, then wait another 48h to re-promote. The promotion and demotion are symmetric in value even if asymmetric in time. This is AGC frequency hunting: the controller responds faster than the system can settle, producing oscillation around the setpoint.

   Does the ratchet use different pass-rate thresholds for promotion vs. demotion (e.g., promote at >0.85, demote at <0.70), not just different time windows? Grid dispatch uses hysteresis in generator commitment: a unit must be committed for a minimum time before it can be decommitted. The equivalent here is: an agent promoted to supervised cannot demote back to shadow until it has accumulated a minimum number of beads at the supervised tier, regardless of individual bead outcomes.

4. **P2 — GRID-4: Dispatch weights are purely reactive with no forecast layer**

   Grid operators run day-ahead and hour-ahead forecasts to pre-position resources before real-time dispatch — generators are committed before the dispatch interval, not as real-time demand arrives. The Ockham dispatch subsystem computes `ockham_weight` from current factory state: intent.yaml budgets, current authority grants, current anomaly signals (§Key Decisions §1, §2). There is no described predictive component.

   When a principal's sprint plan implies that the auth queue will reach zero by Wednesday and a large batch of core work will enter on Thursday, Ockham has no mechanism to pre-position: reduce auth weights slightly ahead of depletion, pre-warm authority grants for core agents, adjust anomaly alert thresholds anticipating higher core activity. The dispatch system will react to the Thursday queue shift with one dispatch cycle of lag.

   Is there a `bead_pipeline_forecast` input to the Dispatch subsystem that reads the planned bead queue (e.g., open beads not yet in progress, sorted by estimated readiness date) and computes anticipatory weight pre-adjustments? This would not require a separate model — it is a lookahead over the existing beads tracker data.

5. **P3 — GRID-5: Principal unavailability under Tier 3 BYPASS is not modeled**

   Grid operators maintain spinning reserve specifically to handle contingencies when normal response capacity is unavailable. The Tier 3 BYPASS description states: "Write factory-paused.json + direct notification bypassing Clavain" (§Key Decisions §3 §Tier 3) and Safety invariant 5 states: "The principal can halt the entire factory at any time" (§Key Decisions §5). This is correct directionally. But the implicit assumption is that the principal can receive and act on the BYPASS notification.

   If the principal is unavailable (travel, offline, asleep), the factory is paused and waiting for explicit re-enable. There is no described reserve capacity mechanism: a designated fallback principal, an auto-resume condition with a safety timeout, or a reduced-operations mode that does not require full principal re-enable for recovery. The factory grid is operating with zero spinning reserve — every contingency requires principal response. What is the degraded behavior when the principal's notification channel is unreachable?

### Improvements

1. Add a pre-dispatch `authority_configuration_check()` that validates the combined authority state of all currently-claimed beads plus the proposed dispatch before issuing new `ockham_weight` values. This runs in the Dispatch subsystem after individual weight computation but before `ic state set` writes. Start with a conservative overlap limit: no more than 2 agents at autonomous tier in any directory subtree simultaneously.

2. When the Anomaly subsystem fires CONSTRAIN on domain D, the Dispatch subsystem should compute `dependent_domains(D)` from a dependency graph (which can be approximated from bead labels and lane metadata) and apply an INFORM-tier suppression weight to beads in those domains that produce D-dependent artifacts. Clear the suppression when CONSTRAIN clears.

3. Define asymmetric promotion/demotion thresholds as separate values in the intent.yaml or a separate `ratchet-config.yaml`: `{promote_threshold: 0.85, demote_threshold: 0.70, min_supervised_beads_before_demotion: 5}`. The `min_supervised_beads_before_demotion` field is the hysteresis gate that prevents oscillation.

4. Add a `bead_pipeline_lookahead_hours` configuration to the Dispatch subsystem. If set, the weight computation includes a weighted input from `count_beads_by_theme_entering_queue_in_window(N_hours)` — anticipating queue shifts without requiring a separate forecasting model.

5. Define a fallback-principal path for Tier 3 BYPASS recovery: a `bypass-recovery-config.yaml` that specifies a fallback contact, an auto-resume timeout (e.g., factory auto-resumes in read-only dispatch mode after 8h with no principal acknowledgment), and the minimum re-enable conditions. This does not relax human halt supremacy — the principal can still override — but it prevents indefinite factory stall from a temporary principal unavailability.
