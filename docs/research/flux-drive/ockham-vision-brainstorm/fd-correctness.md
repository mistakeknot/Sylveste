---
reviewed: 2026-04-02
reviewer: fd-correctness (Julik)
subject: docs/brainstorms/2026-04-03-ockham-vision-brainstorm.md
revision: rev 3 (post 16-agent 4-track flux-review)
---

# Ockham Vision Brainstorm — Correctness Review (rev 3)

## Invariants

These must remain true for Ockham to be a safe policy engine. Each finding below names the invariant it breaks.

1. **Priority order preservation.** An agent dispatching a P1 bead must never be blocked by Ockham in favor of a P3 bead receiving the same work slot. Ockham offsets must not cause cross-tier priority inversions.
2. **Ratchet monotonicity on promotion.** Domain tiers promote one step at a time, never skip. Emergency demotion to shadow is the only multi-step transition, and only on Tier 3.
3. **Ratchet recovery non-triviality.** After a Tier 2 demotion, recovery must require non-zero time in the lower tier with active evidence. Snapping back immediately makes the demotion a no-op.
4. **30-day re-confirmation liveness.** Autonomous domains must actually be re-evaluated every 30 days regardless of operator activity. A no-daemon, CLI-only design must not silently allow expired re-confirmations.
5. **Weight-drift detection requires a defined baseline.** The 20% degradation threshold must be computable at all points in the system's lifecycle, including first launch. Division by zero or silent skip is not acceptable.
6. **Cross-domain resolution requires a defined domain-to-bead mapping.** The min-tier rule cannot be applied if the mapping from bead to domain is ambiguous or absent.
7. **De-escalation completeness.** A frozen theme must return to normal exactly when both windows clear AND the stability window passes. No earlier, no later. The state machine for Tier 2 de-escalation must have no missing transitions.
8. **Safety invariant coherence.** S-08 (no offset exceeds -24) and explicit freeze (-999) must not contradict each other without an explicit documented exception.
9. **Cold-start conservatism is load-bearing.** The claim that cold-start prevents activation regression depends on the promotion window duration. An unspecified window duration makes the conservatism undefinable.

---

## Previous Findings Verification

### C-01: Ratchet had no transition guards — FIXED

The transition table in Section 6 now has explicit guards on all promotion rows:
- shadow → supervised: `hit_rate >= 0.80 AND sessions >= 10 AND confidence >= 0.7`
- supervised → autonomous: `hit_rate >= 0.90 AND sessions >= 25 AND confidence >= 0.85`
- Demotion rows are automatic and immediate (no guard required — correct).

The fix is structurally complete. One residual gap is noted in finding OBR-04 below.

### C-02: Weight multiplier caused priority inversion — PARTIALLY FIXED

The brainstorm correctly switches from multipliers to additive offsets bounded at ±12. However the "~24 point priority tier gap" claim used to justify the bound is factually wrong. The actual gap in `score_bead()` (interphase/hooks/lib-discovery.sh, lines 37-43) is **12 points** between adjacent tiers. This means the ±12 bound does not prevent cross-tier inversions. See finding OBR-01.

### C-03: De-escalation semantics absent — FIXED

Section 5 now specifies: both windows must simultaneously drop below threshold, then a stability window (equal to the short 1h window) must pass with no re-fire. Window-reset on re-fire is specified. The semantics are complete and correct.

---

## Findings Index

- P0 | OBR-01 | "Section 3 / dispatch integration" | Priority-inversion bound is wrong: tier gap is 12 not 24, so ±12 offset still inverts adjacent tiers
- P1 | OBR-02 | "Section 6 / ratchet runaway prevention" | 30-day re-confirmation never fires on a no-daemon CLI-only design unless an invocation happens to occur
- P1 | OBR-03 | "Section 10 / weight-drift detection" | Predicted baseline is undefined at first launch; 20% threshold is not computable when baseline is zero or near-zero
- P1 | OBR-04 | "Section 6 / ratchet recovery" | Post-Tier-2 shadow demotion snaps back immediately if existing evidence still passes the supervised guard; cooldown on re-promotion is absent
- P2 | OBR-05 | "Section 6 / cross-domain resolution" | Domain-to-bead mapping is undefined: domains are path-based, beads use lane labels; the mapping rule is missing
- P2 | OBR-06 | "Section 4 / freeze vs. S-08 floor" | freeze writes -999 but S-08 says no offset exceeds -24; the exception is absent from both the invariant and the validation logic
- P2 | OBR-07 | "Section 6 / cold-start conservatism" | Promotion confirmation window duration is unspecified; cold-start conservatism is non-falsifiable without a window bound
- P3 | OBR-08 | "Section 3 / offset + perturbation composition" | Perturbation (0-5) is applied after the Ockham offset, widening the effective swing to -12..+17; this is unacknowledged and worsens the inversion risk

Verdict: needs-changes

---

## Issues Found

### 1. P0 — OBR-01 — Priority-inversion bound is wrong: the tier gap is 12, not 24

**Location:** Section 3, paragraph "Where `ockham_offset` is bounded to `[-12, +12]`. This means intent can nudge ties and close races, but can never cause a P3 bead to outrank a P1 bead (the priority gap between adjacent tiers is ~24 points in lib-dispatch.sh's scoring)."

**Invariant broken:** Priority order preservation (invariant 1).

The claim rests on a wrong number. The actual scoring is in `interverse/interphase/hooks/lib-discovery.sh`, `score_bead()`:

```
P0 = 60, P1 = 48, P2 = 36, P3 = 24, P4 = 12
```

The gap between adjacent priority tiers is **12 points**, not 24. The brainstorm appears to have confused the absolute values with the inter-tier delta.

Immediate consequence: a ±12 offset spans exactly one full tier gap. A P3 bead receiving +12 and a P2 bead receiving -12 end up at the same raw priority score (24+12 = 36-12 = 24). Adding phase and recency scores — which contribute up to 50 additional points — makes the inversion trivially achievable even within a single tier, let alone across two.

Concrete interleaving that causes a 3 AM page:

1. Principal sets theme `auth` to `priority: high` (+12 offset) and `performance` to `priority: low` (-6 offset).
2. A P3 `auth` bead in `shipping` phase (score: 24+30=54) with +12 offset reaches 66.
3. A P1 `performance` bead in `brainstorm` phase (score: 48+4=52) with -6 offset reaches 46.
4. After perturbation (+5 max for P3, +0 for P1): 71 vs 46.
5. The P3 auth bead is dispatched over the P1 performance bead.

This is not just a tie-break nudge; it is a 25-point inversion on a 12-point tier gap. The safety claim in the brainstorm is false.

The correct bound to guarantee no adjacent-tier inversion from Ockham alone is `±(tier_gap - 1)` = ±11. However, even ±11 does not prevent inversions when phase and recency differences are large — that is an existing property of the scoring model. What Ockham can guarantee is that its offset never alone flips an adjacent-tier ordering: for that, the bound must be strictly less than 12. Since perturbation (0-5) also runs after the offset (see OBR-08), the combined Ockham+perturbation swing must stay below 12 to be safe. The only defensible bound is: `|ockham_offset| + max_perturbation < tier_gap`, i.e., `|offset| < 12 - 5 = 7`. This means the maximum safe magnitude is ±6, not ±12.

**Minimum correct fix:** Change the offset bound from ±12 to ±6. Update the prose to use the correct tier gap of 12. Add a note that the bound is derived from `tier_gap - max_perturbation - 1` so it remains correct if either constant changes.

---

### 2. P1 — OBR-02 — 30-day re-confirmation never fires without a daemon or scheduler

**Location:** Section 6, "Ratchet runaway prevention (SYS-01): Every 30 days (configurable), autonomous domains are re-evaluated against the promotion guard."

**Invariant broken:** 30-day re-confirmation liveness (invariant 4).

Section 2 ("Temporal model") establishes that Ockham has no daemon: "No daemon. Signal timestamps and confirmation windows are persisted to `~/.config/ockham/signals.db` (SQLite). Each CLI invocation reads current state, evaluates signals, writes updated state."

This design pattern works correctly for signal evaluation (which fires on CLI invocation). But it fails for the 30-day re-confirmation, which is a time-based obligation that must fire on schedule regardless of operator activity. On a healthy factory where nothing goes wrong, the principal may not invoke `ockham` for weeks at a time. The re-confirmation never fires, and autonomous domains remain autonomous indefinitely.

This is not a theoretical edge case. The steady-state of a well-functioning factory is precisely the scenario where the principal interacts with Ockham least. The runaway prevention is most needed exactly when it is least likely to fire.

Failure scenario:
1. Week 1: Factory reaches autonomous state in domain `interverse/**`. All metrics green.
2. Weeks 2-30: Factory runs smoothly. Principal rarely opens Ockham CLI.
3. Day 31: Agent reliability quietly degrades (hit_rate drops from 0.93 to 0.72 due to model drift). The 30-day re-evaluation window has passed, but no CLI invocation triggered it.
4. Day 45: A wave of failures. Ockham has not demoted the domain because re-confirmation never ran.
5. Principal discovers the demotion mechanism they relied upon never executed.

**Minimum correct fix:** Two options:
- (a) Add a `ockham check` step to Clavain's session-start hook so re-confirmation fires on every agent session. This is low-overhead and compatible with the no-daemon model, since agent sessions happen regularly.
- (b) Add a `--check` flag to the `ockham` CLI entry point that is always called from a lightweight cron (systemd timer or cron job) at 24-hour intervals. One line in the install guide.

Option (a) is preferred: it piggybacks on existing infrastructure without requiring a new system timer, and re-confirmation has negligible cost (one interspect query per domain).

---

### 3. P1 — OBR-03 — Weight-drift detection baseline is undefined at first launch

**Location:** Section 10, "If a theme's actual-vs-predicted ratio degrades >20% over a 7-day rolling window, Ockham emits a Tier 1 INFORM signal."

**Invariant broken:** Weight-drift detection requires a defined baseline (invariant 5).

The mechanism compares "actual cycle time and quality gate pass rate against the predicted baseline for that theme." The baseline is never defined:

1. **At first launch, no baseline exists.** The 7-day rolling window has no data. Does the check skip? Emit a false positive at 100% degradation? The brainstorm is silent.

2. **Baseline formula is unspecified.** Is the baseline the historical mean over all completed beads in that theme? A rolling 30-day average? A fixed value set in intent.yaml? Without a definition, two implementors will produce different baselines and different drift signals.

3. **Minimum sample size is absent.** If a theme has 2 completed beads in 7 days, the actual-vs-predicted ratio has a standard error that dwarfs the 20% threshold. A single anomalous bead that took 3x its expected time will fire a drift signal regardless of whether the theme is truly degrading. No floor on `min_completed_beads_for_drift_check` is specified.

4. **Division-by-zero when baseline is zero.** If a theme has never had a completed bead, the baseline cycle time is zero. `actual / 0` is undefined. The check must either skip or use a hardcoded bootstrap baseline.

Concrete failure:
- Factory launches. First bead in theme `auth` completes in 3 hours.
- Second bead completes in 4 hours (33% longer than bead 1).
- The 7-day rolling window "baseline" from bead 1 is 3h. The 20% threshold fires.
- Ockham emits a spurious Tier 1 INFORM signal for theme drift on the second ever completed auth bead.
- The weight-drift event poisons the interspect evidence store for theme `auth`.

**Minimum correct fix:** Define the baseline explicitly: "predicted baseline = rolling 30-day p50 cycle time for beads in that theme, minimum 5 completed beads. If fewer than 5 completed beads exist for the theme in the window, skip drift evaluation and log `insufficient_data`." Add this as a schema constraint in the Scoring subsystem spec.

---

### 4. P1 — OBR-04 — Post-Tier-2 shadow demotion snaps back immediately; no cooldown on re-promotion

**Location:** Section 6, transition table row: `shadow | supervised | Tier 2 clears + stability window | requires passing supervised promotion guard`.

**Invariant broken:** Ratchet recovery non-triviality (invariant 3).

The transition table says: after a Tier 2 event demotes a domain to shadow, recovery to supervised requires passing the stability window AND passing the supervised promotion guard (`hit_rate >= 0.80 AND sessions >= 10 AND confidence >= 0.7`).

The flaw: the Tier 2 event that triggered the demotion did not erase the interspect evidence. The domain was at supervised tier, which means it already satisfied the promotion guard before the demotion. If the Tier 2 signal clears in, say, 2 hours (stability window = 1h), the domain immediately satisfies the promotion guard again with the same evidence that was already there.

Result: the domain spends at most `stability_window` (1h) in shadow before re-promoting to supervised. The demotion is cosmetic — it lasts for exactly one stability window.

This is not catastrophic, but it means the ratchet provides no meaningful time in the lower tier for observation and evidence accumulation after a Tier 2 event. The invariant "Recovery from CONSTRAIN always drops one level, never restores to prior tier directly" is satisfied literally but not in spirit: re-promotion happens at the earliest possible moment, not after demonstrated recovery.

Failure scenario in a wave of cascading quarantines:
1. Domain `interverse/**` at supervised. Three quarantines fire in quick succession.
2. Tier 2 CONSTRAIN fires. Domain demotes to shadow.
3. Root cause is fixed in 90 minutes. Tier 2 signal clears.
4. 1h stability window passes. Domain re-promotes to supervised immediately.
5. Underlying fragility is still present; the 90-minute window was insufficient to detect whether the fix was durable.
6. Another quarantine wave fires 2 hours later.

**Minimum correct fix:** Add a minimum re-promotion interval after any Tier 2 demotion. A simple rule: "After a Tier 2-triggered demotion to shadow, re-promotion to supervised requires the full supervised confirmation window (`sessions >= 10` NEW evidence since the demotion, not total). Existing evidence at or before the demotion timestamp is discarded from the promotion guard evaluation." This forces genuine evidence accumulation rather than re-using stale evidence.

---

### 5. P2 — OBR-05 — Cross-domain resolution depends on an undefined domain-to-bead mapping

**Location:** Section 6, "Cross-domain beads (ET-01/HADZA-01): When a bead touches multiple domains (e.g., `interverse/**` + `core/**`), authority resolves to `min(tier_per_domain)`."

**Invariant broken:** Cross-domain resolution requires a defined domain-to-bead mapping (invariant 6).

The min-tier logic is sound in principle. The gap is that "domain" in the ratchet model is a path-based namespace (`interverse/**`, `core/**`), while beads in the actual system are associated with **lanes**, not paths. A bead tagged `lane=auth` may touch files in both `interverse/` and `core/` — but Ockham has no way to know this from the bead metadata alone. Only the executing agent knows which files it will touch.

This creates three unresolved questions:

1. **At dispatch time**, how does Ockham determine which domains a bead spans? Beads don't have file-path metadata. The plan document may reference domains, but parsing plan docs for path patterns is fragile and not specified.

2. **Fallback behavior** when the domain mapping is absent or ambiguous is not specified. Does Ockham use the bead's single lane? Use the most restrictive known domain? Assume the `open` domain?

3. **Post-execution discovery**: If an agent's work spans more domains than the pre-dispatch mapping predicted, the authority violation is discovered after the fact. The brainstorm says "Ockham computes this during weight synthesis" — implying it is a pre-dispatch computation — but the inputs to that computation are not defined.

Absent this mapping, the cross-domain min-tier rule is a design intention with no implementable specification.

**Minimum correct fix:** Specify how domain membership is determined for a bead at dispatch time. The simplest defensible rule: "Domain membership is declared by the bead author via a `domains` field in the bead state (e.g., `bd set-state domains=interverse,core <bead_id>`). If absent, domain defaults to the bead's lane. Ockham reads `domains` from bead state during weight synthesis." This makes the input explicit and under the bead author's control, rather than inferred from file paths Ockham cannot see.

---

### 6. P2 — OBR-06 — Freeze (-999 offset) contradicts the S-08 neutrality floor without a documented exception

**Location:** Section 4 (freeze writes -999); Section 7, invariant 6: "No bead's offset can exceed `-24` (effectively blocked requires an explicit freeze constraint, not an organic weight)."

**Invariant broken:** Safety invariant coherence (invariant 8).

The brainstorm acknowledges the tension in the S-08 text ("effectively blocked requires an explicit freeze constraint, not an organic weight") but does not resolve it formally. The result is a contradiction in the spec:

- S-08 says no offset exceeds -24.
- Freeze sets the offset to -999.
- The validation logic for `ockham_offset` that enforces the -24 floor must either reject freeze offsets (breaking freeze) or contain an exception for freeze (undocumented, hard to audit).

There is also a missing floor guard in `dispatch_rescore()` interaction. The current dispatch code has `adjusted_score < 1 → 1` as the floor. If Ockham writes -999 as an offset for a frozen bead, and the brainstorm says this is applied BEFORE perturbation and BEFORE the floor guard, then the floor guard in dispatch_rescore() will lift the score from -999+perturbation back to 1, making the bead claimable. The freeze fails silently if the floor guard is not also updated to recognize freeze offsets.

Concrete failure:
1. Theme `auth` is frozen. Ockham writes `ockham_offset = -999` for each auth bead.
2. lib-dispatch.sh reads the offset, applies it: score = raw_score - 999 (e.g., 60 - 999 = -939).
3. Perturbation adds 0-5: still deeply negative.
4. Floor guard fires: `adjusted_score < 1 → 1`.
5. The auth bead now has score=1 and is eligible for dispatch. The freeze did not freeze it.

**Minimum correct fix:** Two changes required:
- (a) In the S-08 invariant, explicitly document that freeze offsets (-999) are exempt from the -24 floor, and that the -24 floor applies only to organic (non-freeze) offsets. This removes the contradiction.
- (b) In `dispatch_rescore()`, add a "freeze sentinel" check: if `ockham_offset == -999`, skip the bead entirely (do not add to the candidate list), rather than clamping to 1. The current floor guard must be bypass-able by the freeze signal.

---

### 7. P2 — OBR-07 — Promotion confirmation window duration is unspecified; cold-start conservatism is non-falsifiable

**Location:** Section 6, "Cold start (resolved, D-05/SYS-05/R-06)": "promotion from supervised to autonomous happens in the first confirmation window if evidence holds."

**Invariant broken:** Cold-start conservatism is load-bearing (invariant 9).

The cold-start claim is: start at supervised even if evidence meets the autonomous guard, and the domain will promote to autonomous "in the first confirmation window." This is offered as the mechanism preventing activation regression. But the document never specifies how long a confirmation window is for promotions (as opposed to Tier 2 CONSTRAIN, where 1h and 24h windows are defined).

If the promotion confirmation window is, say, 15 minutes, then a domain with strong historical evidence starts at supervised and promotes to autonomous 15 minutes later. The "conservatism" provides 15 minutes of supervised operation. If the window is 7 days, it provides 7 days. These are wildly different safety properties.

The Tier 2 signal windows (1h short, 24h long) are carefully specified. The promotion window is not. An implementor will pick an arbitrary value, and two implementors will pick different values, violating the claim that "turning on Ockham shouldn't increase principal load."

**Minimum correct fix:** Specify promotion confirmation window duration, e.g.: "Promotion confirmation window: 72 hours. Pleasure signals must persist above threshold for 72 continuous hours before a tier transition fires." This is a single constant with a large impact on the safety profile; it must be specified, not inferred.

---

### 8. P3 — OBR-08 — Offset + perturbation composition widens effective swing; unacknowledged in the inversion analysis

**Location:** Section 3, "lib-dispatch.sh reads them in `dispatch_rescore()` BEFORE perturbation and BEFORE the floor guard."

**Invariant broken:** Priority order preservation (invariant 1) — amplification of OBR-01.

The brainstorm correctly notes the ordering: offset is applied first, then perturbation. But the inversion analysis only considers the offset magnitude (±12) without accounting for perturbation's contribution.

In `dispatch_rescore()`, perturbation adds `RANDOM % 6` (0 to 5) to the adjusted score. Applied after the Ockham offset:

```
final = raw + ockham_offset + perturbation - pressure_penalty
```

Two beads at the same raw score:
- Bead A: raw=50, offset=+12, perturbation=5 → final=67
- Bead B: raw=50, offset=-12, perturbation=0 → final=38

The effective swing is not ±12 but -12..+17, a 29-point asymmetric range. This worsens the inversion analysis from OBR-01 and must be accounted for in the bound derivation. The correct bound on `|ockham_offset|` is `tier_gap - max_perturbation - 1 = 12 - 5 - 1 = 6`.

This is a direct consequence of the ordering choice (offset before perturbation). An alternative is to apply the Ockham offset AFTER perturbation, which would make the effective swing exactly ±12 as intended. The current ordering is not wrong per se, but the inversion guarantee it is supposed to provide requires a tighter bound.

**Minimum correct fix:** Either (a) change the bound to ±6 (consistent with OBR-01 fix) and document that `max_perturbation = 5` is factored in, or (b) move the offset application to after perturbation, which preserves the ±12 bound as an exact inversion limit for tie-breaking purposes.

---

## Improvements

### 1. Make the Scoring subsystem's clamping contract explicit

The brainstorm says Scoring "receives typed input structs" and produces a "unified weight vector." The clamping of the final offset (the -24 floor, the freeze sentinel, the ±12 bound) is described across multiple sections. A single "Offset clamping contract" paragraph in the Scoring subsystem spec, listing all clamping operations in application order, would prevent the S-08/freeze contradiction (OBR-06) from being re-introduced during implementation.

### 2. Define what "interspect evidence confidence" means for the ratchet guard

The promotion guard uses `confidence >= 0.7`. The interspect interface is described as `agent_reliability(agent, domain) -> {hit_rate, sessions, confidence, last_active}`. The brainstorm does not define what `confidence` means in this context — is it a Wilson interval lower bound on `hit_rate`? A recency-weighted certainty? The guard threshold of 0.7 is only as meaningful as the definition of the confidence field.

### 3. Add a "domain health rollup" to the Ockham status output

With per-domain autonomy tiers, cold-start inference, and 30-day re-confirmations (even when fixed to fire correctly per OBR-02), a principal needs a single command showing each domain's current tier, last re-confirmation date, and whether the promotion guard is satisfied. `ockham status --domains` would surface OBR-02 failures immediately: a domain with `last_confirmed: 47 days ago` is visually alarming.

---

## Summary

C-01, C-02, and C-03 are all addressed in rev 3. The transition table is complete, the freeze semantics were added, and de-escalation windows are correctly specified.

The open correctness issues introduced or exposed in this revision are:

The most serious finding is OBR-01: the ±12 offset bound is built on a factual error (the tier gap is 12, not 24). The correct maximum is ±6, and that must also account for perturbation. This is a design decision that must be revisited before any implementation begins.

OBR-02 (30-day liveness) and OBR-04 (immediate re-promotion after demotion) will produce operational failures in production that are easy to overlook: the system appears to behave correctly but the safety backstops have silently lapsed. Both require small targeted changes.

OBR-03 (undefined baseline) will cause spurious Tier 1 signals on factory launch, poisoning the weight-drift evidence before it has meaning. This must be specified before the feedback loop ships.

OBR-05 (undefined domain-to-bead mapping) is an implementation blocker for cross-domain resolution: the feature cannot be built without it.

OBR-06 (freeze contradicts S-08) is a silent dispatch correctness bug: frozen beads will be re-admitted to the candidate list by the floor guard. It requires both a spec clarification and a code fix.

---

STATUS: fail
FILES: 0 changed
FINDINGS: 8 (P0: 1, P1: 3, P2: 3, P3: 1)
SUMMARY: The ±12 offset bound rests on an incorrect priority tier gap (12, not 24). OBR-01 invalidates the core safety claim of Section 3 and the correct bound is ±6 when perturbation is accounted for. Three P1 findings are operational time-bombs: 30-day re-confirmation never fires on a CLI-only design, weight-drift detection cannot compute a baseline at launch, and post-demotion re-promotion is immediate due to stale evidence. The freeze/S-08 contradiction (OBR-06) is a latent dispatch bug that will allow frozen beads to be dispatched.
