---
artifact_type: flux-drive-review
agent: fd-or-scheduling
track: B-orthogonal
target: docs/brainstorms/2026-04-03-ockham-vision-brainstorm.md
reviewed_at: 2026-04-03
---

# fd-or-scheduling Review — Ockham Vision

### Findings Index
- P1 | OR-1 | "Key Decisions §2 — Dispatch integration via weight multipliers" | Static theme budget weights have no block-release mechanism — idle capacity is never reclaimed
- P1 | OR-2 | "Key Decisions §3 — Algedonic signals §Tier 3" | Tier 3 halt is file-polled, not interrupt-driven — one dispatch cycle executes after bypass trigger
- P2 | OR-3 | "Key Decisions §2 + §5" | Theme weights are computed once; no throughput feedback loop recalibrates them as theme bead population is consumed
- P2 | OR-4 | "Key Decisions §1 — Intent subsystem" | Per-bead weight derivation is not described as auditable — principal cannot reconstruct why a bead received its multiplier
- P3 | OR-5 | "Open Questions §1" | Intent YAML freeze/focus semantics are unspecified — a freeze may zero the weight or sentinel it, producing different downstream behaviors

Verdict: needs-changes

### Summary

The Ockham vision correctly separates policy from dispatch and models authority tiers well. The dominant failure pattern from OR block governance — reserved capacity that sits idle while starving other queues — is directly present: a 40% auth budget reserves 1.4x multiplier on auth beads even when no auth beads are in the dispatch queue, and no mechanism releases that notional allocation to other themes. A second OR-native concern is simultaneous competing emergencies: the Tier 3 BYPASS relies on `factory-paused.json` being read at the next Clavain dispatch cycle, meaning one dispatch window elapses between the BYPASS trigger and the halt taking effect. The weight recalibration loop is missing entirely — intent.yaml is set once and never updated from actual theme throughput. Per-bead weight derivation auditability is asserted as a design goal ("every weight has a derivation chain") but the mechanism to reconstruct it from a given `bead_id` is not specified.

### Issues Found

1. **P1 — OR-1: No block-release equivalent for idle theme capacity**

   In OR scheduling, block time not confirmed by a case deadline reverts to the open pool. Ockham's `final_score = raw_score * ockham_weight` applies the multiplier from `ic state set "ockham_weight" <bead_id>` at dispatch time. The brainstorm describes the auth budget as "40% gets weight 1.4; unlinked bead gets 0.6" (§Key Decisions §2). This is a static allocation: if no auth beads are in the queue at the moment Clavain's `dispatch_rescore()` runs, the 0.6 penalty on non-auth beads still applies, but there is no mechanism to release the effectively-idle auth allocation and let non-auth beads score at their natural weight.

   Failure scenario: A principal sets `auth: 40%`. Clavain dispatches auth beads aggressively on day 1 and exhausts the auth queue by noon. For the rest of the sprint, the auth weight (1.4x) is written into the state of the zero remaining auth beads, and unlinked beads continue receiving the 0.6 penalty — but there is nothing for the 1.4x capacity to dispatch. The factory underperforms on other themes not because auth work is being done, but because the allocation is reserved and idle.

   Smallest fix: `dispatch_rescore()` should check `count_dispatchable_beads_by_theme(theme)` before applying the multiplier. If a theme's queue depth is zero, bleed its weight reserve to the open pool by not applying the penalty to other themes. This is one conditional branch added to the rescore loop, not a weight recomputation.

2. **P1 — OR-2: Tier 3 BYPASS halt is file-polled, not interrupt-driven**

   The brainstorm states that the existing zero-code-change halt path is `~/.clavain/factory-paused.json` (§Key Decisions §6). Tier 3 fires by writing this file. Clavain's dispatch loop reads this file at the start of each dispatch cycle — meaning one full dispatch cycle executes between the BYPASS trigger event and the halt taking effect.

   Failure scenario: Two Tier 2 CONSTRAIN signals fire simultaneously on different domains. Tier 3 BYPASS condition is met. Ockham writes `factory-paused.json`. At this exact moment, Clavain is mid-dispatch-cycle. It has already passed the paused-file check and is computing weights for the next batch of beads. It claims three beads across the two constrained domains before the next cycle begins and reads the halt. Those three beads are now claimed under the assumption of normal operation in what is definitionally an anomalous factory state. In OR terms: a surgeon was assigned an emergency case, the OR was already mid-prep for an elective, and nobody told the surgical team the room was being diverted.

   Smallest fix: Separate the halt-file-write into two actions: first set a memory-mapped flag that `dispatch_rescore()` checks at the top of the scoring loop (not only at the top of the dispatch cycle), then write the durable JSON file. The in-memory flag can be a named pipe or a process signal if Clavain runs as a daemon — but this only works if Ockham can send an interrupt to Clavain's process. If Clavain is purely file-driven, the check should be inline in `dispatch_rescore()` before issuing any new claim.

3. **P2 — OR-3: No throughput feedback loop for weight recalibration**

   OR systems track specialty block utilization and trigger formal review when a specialty averages below 75-80% utilization. The brainstorm describes `ockham_weight` as derived from theme budgets in `intent.yaml` (§Key Decisions §2) and states "thresholds start hardcoded, wire through intercept for calibration" (§Key Decisions §4). There is no described path from "actual auth beads completed this sprint" back to "Ockham recalibrates the auth weight multiplier for the remainder of the sprint."

   Does Ockham track beads-completed-per-theme against the budget target? If auth was budgeted at 40% and has delivered 60% of sprint capacity, does the multiplier adjust downward to rebalance toward other themes? Without this feedback loop, intent.yaml becomes a static set point that the factory may chronically over- or under-serve regardless of actual execution.

4. **P2 — OR-4: Per-bead weight derivation auditability is asserted but not specified**

   The brainstorm states "every weight has a derivation chain" and cites audit completeness as a safety invariant for authority decisions. The formula `final_score = raw_score * ockham_weight` is auditable at the formula level. However, reconstructing *why* a specific bead received its `ockham_weight` value requires knowing: which intent theme it matched, what budget allocation applied, whether any authority or anomaly modifiers were active, and what the resulting multiplier was.

   The `ic state set "ockham_weight" <bead_id>` mechanism writes a scalar. It does not write a derivation record. A principal inspecting a bead's dispatch history would see the multiplier but not the reasoning chain. In OR governance, surgeons must understand why their case was delayed or bumped — the equivalent here is a principal being able to query `ockham explain <bead_id>` and receive the derivation chain, not just the final number.

   Does the bead state store include a `ockham_weight_provenance` field alongside `ockham_weight`? If not, auditing is retrospectively impossible once `intent.yaml` is updated.

5. **P3 — OR-5: Freeze and focus semantics in intent.yaml are unresolved**

   Open Question 1 asks: "Does a freeze zero out the weight or set it to a sentinel?" These produce different downstream behaviors. A zero weight means beads from the frozen theme score at 0 and never dispatch. A sentinel (e.g., -1) could mean "skip this bead entirely without penalizing others." In OR scheduling, "block frozen" means no new cases can be scheduled to that block, but existing cases already in the room continue — the freeze applies prospectively. The Ockham design should specify whether freeze applies to already-claimed beads (retroactive) or only to new dispatch decisions (prospective).

### Improvements

1. Add a `dispatch_rescore()` check for zero-depth theme queues: before applying the non-theme weight penalty (0.6x), verify `count_dispatchable_beads(theme) > 0`. If zero, treat the allocation as released to the open pool and apply a neutral weight (1.0x) to other themes rather than the full penalty.

2. Introduce an in-process halt flag that `dispatch_rescore()` checks mid-loop, independent of the `factory-paused.json` file poll. This does not require removing the JSON file mechanism — it adds a faster-acting layer in front of it.

3. Add a `theme_utilization_report` output to the Intent subsystem that tracks beads-completed-per-theme against budget targets on a rolling basis. Wire this as an INFORM-tier pleasure signal that flows back to weight recalibration.

4. Extend `ic state set` for `ockham_weight` to also write an `ockham_weight_provenance` record: `{theme: "auth", budget_pct: 40, applied_modifier: "INFORM:cost_overrun:0.8", final_multiplier: 1.12, computed_at: <epoch>}`. This makes the derivation chain retrievable without reconstructing it from logs.

5. Resolve Open Question 1 (freeze semantics) by adopting the OR convention: freeze is prospective-only. Already-claimed beads continue to execution. The weight is set to 0.0 for new dispatch scoring, and a `freeze_reason` field is written alongside to support principal-visible explanation.
