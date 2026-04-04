---
artifact_type: flux-drive-finding
agent: fd-resilience
document: docs/brainstorms/2026-04-03-ockham-vision-brainstorm.md
document_revision: 3
date: 2026-04-02
bead: sylveste-8em
---

# fd-resilience — Ockham Vision Brainstorm (Rev 3)

**Reviewer:** fd-resilience (Flux-drive Adaptive Capacity Reviewer)
**Document:** `docs/brainstorms/2026-04-03-ockham-vision-brainstorm.md`
**Date:** 2026-04-02
**Review type:** Re-review (rev 3); verifying three prior P1 fixes; assessing four new sections

**Verdict:** Two of three prior P1 findings are adequately resolved. R-02 has a structural gap that weakens the fix. Three new findings emerge from the new sections — one P1 (signals.db as unacknowledged single point of failure), one P2 (feedback loop threshold is a single fixed target in a Goodhart-vulnerable system), one P2 (policy immutability during halt creates a recovery deadlock path). No P0s.

---

## Prior Finding Verification

### R-01: No intent.yaml fallback — RESOLVED

Section 4 now explicitly states: "If intent.yaml is missing or corrupt, Ockham uses a hardcoded default: all themes budget 1/N, priority normal." The atomic file replacement after validation prevents partial writes. The fix is sound — the happy-path-only assumption is gone.

### R-02: Interspect unavailability breaks INV-3 — PARTIALLY RESOLVED

Section 7, invariant 3 now reads: "if interspect is unavailable, action-time validation uses the last-known authority snapshot (max staleness: 5 minutes). Beyond 5 minutes stale, fail-closed (deny)."

The staleness window and fail-closed direction are correct. However, the fix assumes a snapshot exists to go stale. The document does not specify where the last-known authority snapshot is persisted. If Ockham is stateless between CLI invocations (no daemon, per Section 2's "No daemon" model), the snapshot must be written to disk after each interspect read, or the 5-minute cache is in-memory only. An in-memory cache means any restart within the 5-minute window loses the snapshot and forces fail-closed immediately — which is conservative but means a crash at minute 4 restores to shadow across all domains, demoting agents mid-sprint without signal. This is underspecified, not wrong, but the fix is incomplete until the persistence location of the snapshot is named. See Finding R-02-b below.

### R-04: No Tier 3 restart sequence — RESOLVED

Section 5 now contains an explicit 4-step restart sequence with correct ordering (check Tier 2 signals before clearing, supervised re-entry window before restoring prior autonomy). The sequence is sound and prevents the "resume to autonomous directly" vulnerability identified in the prior review.

---

## Findings Index

| # | Finding | Section | Lens | Severity |
|---|---------|---------|------|----------|
| R-02-b | Authority snapshot has no named persistence store | §7 INV-3, §2 temporal model | Graceful Degradation | P1 |
| N-01 | signals.db is an unacknowledged single point of failure | §2 temporal model, §5 Tier 1/2 | Redundancy vs. Efficiency | P1 |
| N-02 | Weight-drift detection threshold is a single fixed Goodhart target | §10 weight-outcome feedback | Antifragility, Creative Destruction | P2 |
| N-03 | Policy immutability during halt can trap a partially-frozen factory indefinitely | §7 INV-8 | Graceful Degradation, Staging & Sequencing | P2 |
| N-04 | Cross-domain resolution min-tier rule has no degradation path when domain evidence is absent | §6 cross-domain beads | Graceful Degradation, Assumption Locks | P3 |

---

## Finding R-02-b: Authority snapshot has no named persistence store [P1 — Blind Spot]

**Lens:** Graceful Degradation

**Section:** §2 "Temporal Model" and §7 Invariant 3

**What the document says:** Ockham has no daemon. Each CLI invocation reads current state, evaluates signals, writes updated state. Action-time validation uses the last-known authority snapshot with a 5-minute staleness window, fail-closed beyond that.

**The gap:** The document does not identify where the authority snapshot is persisted between CLI invocations. This matters because "last-known" has three possible implementations with different failure modes:

1. Written to signals.db alongside signal timestamps — snapshot survives restarts but inherits signals.db's failure modes (see N-01).
2. Written to a separate file (e.g., `~/.config/ockham/authority-snapshot.json`) — survives signals.db corruption but creates a second store to manage.
3. Held in memory during a CLI run and reconstructed from interspect on the next invocation — means the 5-minute cache resets on every CLI invocation, making the staleness window practically meaningless for the no-daemon model (each `ockham` call is a fresh process).

Option 3 is the most likely silent default when no persistence location is specified. Under option 3, if interspect is unavailable when an agent calls `ockham authority check`, Ockham has no snapshot to consult — the cache is empty — and must fail-closed immediately regardless of how recently interspect was healthy. This converts a 5-minute degradation window into a zero-second one.

**What happens at scale:** In a multi-agent sprint where 8 agents are mid-work and interspect experiences a 3-minute restart, option 3 means all 8 agents get fail-closed authority denials during that window. Option 1 or 2 means they operate on the last-known snapshot. The document's fix only works if the implementation chooses option 1 or 2, but neither is specified.

**Recommendation:** Name the persistence location for the authority snapshot. The simplest fix is "authority snapshot is written to signals.db after each successful interspect read, with a timestamp." This closes the gap with one sentence and makes the 5-minute window meaningful in the no-daemon model.

---

## Finding N-01: signals.db is an unacknowledged single point of failure [P1 — Blind Spot]

**Lens:** Redundancy vs. Efficiency, Graceful Degradation

**Section:** §2 "Temporal Model" — "Signal timestamps and confirmation windows are persisted to `~/.config/ockham/signals.db` (SQLite)."

**What the document says:** Ockham's entire temporal model depends on signals.db for multi-window confirmation (Tier 2's "short 1h AND long 24h must both breach simultaneously"), de-escalation stability windows, and the 30-day autonomous re-confirmation timer. Each CLI invocation reads and writes to this store.

**The gap:** signals.db is the only place this temporal state exists, and the document treats it as infrastructure rather than a failure domain. There are three distinct failure modes:

1. **Corruption:** SQLite WAL files can corrupt under interrupted writes. If signals.db is corrupt, all multi-window confirmations are lost. Ockham cannot distinguish "Tier 2 signal has been active for 23 hours" from "no data." The likely fallback is treating absent data as a cleared signal — which means corruption silently disables the persistence tier of the algedonic system.

2. **Clock skew:** The temporal model uses stored timestamps compared against wall clock. If the host clock is adjusted (NTP step, timezone change, daylight saving transition), stored timestamps become incorrect. A 1-hour NTP correction could either trigger or clear a Tier 2 signal spuriously.

3. **Loss:** If signals.db is deleted (e.g., by a user clearing `~/.config/ockham/`), all active signals reset. A factory operating under Tier 2 CONSTRAIN for 20 hours — one hour from triggering a Tier 3 BYPASS — would silently return to Tier 1. A principal relying on CONSTRAIN notifications might not notice.

The document's safety invariants (§7) protect against agent manipulation of the sentinel (INV-7: "at least one Tier 3 trigger must be agent-unwritable"). But they do not protect against accidental loss of signals.db, which achieves the same effect as manipulation — suppressing escalation — through a mundane operational failure.

**What happens in practice:** The Tier 2 multi-window confirmation is the brainstorm's most sophisticated safety mechanism — it prevents false-positive freezes. If signals.db corruption resets the 24-hour window on hour 23, a genuine problem avoids Tier 2 escalation indefinitely as long as the short window never triggers long enough to write a new timestamp before the next corruption.

**Recommendation:** Two complementary additions:

First, specify recovery behavior when signals.db is absent or corrupt. The conservative option: treat absent signal history as "signal has been active since epoch 0" — fail-closed, which forces a manual `ockham signals reset` after a principal reviews state. This prevents corruption from silently suppressing escalation.

Second, add signals.db to the periodic backup recommendation, or note that the 30-day autonomous re-confirmation timer (§6 ratchet runaway prevention) should be re-evaluated after any signals.db restore, since restored state may be stale.

---

## Finding N-02: Weight-drift detection threshold is a single fixed Goodhart target [P2 — Missed Lens]

**Lens:** Antifragility, Creative Destruction

**Section:** §10 "Weight-outcome feedback loop"

**What the document says:** "If a theme's actual-vs-predicted ratio degrades >20% over a 7-day rolling window, Ockham emits a Tier 1 INFORM signal and logs a `weight_drift` event." The threshold starts hardcoded and "distills a local model after 50+ evaluations."

**The issue:** PHILOSOPHY.md's measurement section warns explicitly: "Agents will optimize for any stable target. Rotate metrics, cap optimization rate, randomize audits. Goodhart pressure exists from day one." The weight-drift threshold is exactly this kind of stable target. If the 20% threshold is known (and it will be known — it's hardcoded and visible), the factory's dispatch patterns can drift to 19.9% without triggering detection. This is not a hypothetical: the bead granularity gaming vector already identified in Open Question 2 (§ "Open Questions") operates through the same optimization pressure. An agent that creates more granular beads to improve first_attempt_pass_rate could simultaneously keep per-bead cycle time within the 20% band.

More importantly, the document describes the intercept integration as "distills a local model after 50+ evaluations" — but does not specify what the distilled model changes. If it only tunes the threshold value (e.g., calibrates 20% to 18% based on history), the model is still a single stable threshold, just self-calibrated. The Goodhart pressure moves with the threshold.

**What the document gets right:** Shipping weight-drift feedback in Wave 1 alongside Tier 1 INFORM, rather than deferring it, is the correct instinct. PHILOSOPHY.md's "Wired or it doesn't exist" principle is satisfied. The concern is not the decision to ship it — it is that the mechanism is a single fixed threshold rather than a diverse signal ensemble.

**Recommendation:** Either (a) specify that weight-drift detection uses multiple independent signals (cycle time AND gate pass rate AND cost-per-change, where drift in any two triggers the signal — harder to game simultaneously), or (b) explicitly acknowledge this as a known Goodhart exposure and name the review trigger for the 50-evaluation distillation (what does the local model actually update?). This is not a blocker for Wave 1, but the "distills a local model" language implies robustness that hasn't been designed yet.

---

## Finding N-03: Policy immutability during halt creates a recovery deadlock path [P2 — Missed Lens]

**Lens:** Graceful Degradation, Staging and Sequencing

**Section:** §7 Invariant 8 — "When factory-paused.json exists, all Ockham subsystems are read-only. No weight updates, no authority changes, no signal evaluation. Only `ockham resume` (principal action) re-enables writes."

**The gap:** The document does not consider what happens when a Tier 3 halt is triggered by a condition that itself requires Ockham to take a corrective action to resolve. Consider:

1. Tier 3 fires. factory-paused.json is written. All Ockham subsystems go read-only.
2. The principal investigates. The root cause is a rogue domain at autonomous tier with bad dispatch weights — e.g., the "auth" theme has a weight offset misconfiguration that caused the `distinct_root_causes >= 2` condition.
3. To fix the misconfiguration, the principal wants to run `ockham intent set --theme auth --priority normal` to reset the weight offset.
4. But this is a weight update — blocked by INV-8 while factory-paused.json exists.
5. The principal must run `ockham resume` FIRST to unblock writes, which simultaneously resumes the factory.

This means the correction and the resumption are coupled — the principal cannot fix the misconfiguration and then resume, they must resume and then fix, during which the mis-weighted factory is briefly live again. The write-before-notify ordering (INV-5) protects against notification failures, but it does not protect against this resume-then-fix ordering constraint.

For an experienced operator this is manageable. For a principal who is not deeply familiar with Ockham's invariant ordering, the correct repair sequence is non-obvious and the document does not describe it.

**This is not a design error** — the read-only halt invariant is the right default for an autonomous governor. The gap is in the recovery documentation. Policy immutability during halt creates a recoverable but undocumented ordering constraint that could cause a second Tier 3 trigger if the principal resumes before correcting the root cause.

**Recommendation:** Add a short "Recovery sequence" note alongside INV-8 that specifies the intended order: (1) `ockham resume --supervised-only` to re-enable writes without unpausing the factory (if this mode is desired), or (2) `ockham intent set ...` dry-run while paused, then resume, then apply. If option 1 doesn't exist yet, note whether a "write-only mode" separate from full resume is worth adding. This is a staging and sequencing gap in the halt recovery path, not a fundamental design flaw.

---

## Finding N-04: Cross-domain resolution min-tier has no degradation path when domain evidence is absent [P3 — Consider Also]

**Lens:** Graceful Degradation, Assumption Locks

**Section:** §6 "Cross-domain beads (ET-01/HADZA-01)"

**What the document says:** "authority resolves to `min(tier_per_domain)` — the most restrictive domain governs." If any touched domain is frozen, the bead is ineligible regardless of other domains.

**The question this raises:** The min-tier rule requires Ockham to have a known tier for every domain a bead touches. At cold start (§6 "Cold start"), the document specifies that domains with no interspect evidence start at shadow. This implies the cold-start rule and the cross-domain rule compose correctly: unknown domains default to shadow, and the bead resolves to shadow (most restrictive). That much is fine.

But during normal operation, what is the tier of a domain for which interspect evidence has expired or been pruned? PHILOSOPHY.md specifies a 90-day evidence rolling window for C2 (Evidence & Calibration). If an agent's evidence for a domain ages out of the 90-day window (e.g., an agent that only works on a domain quarterly), does the domain revert to shadow? Or does the last-known tier persist in signals.db until overwritten?

If the domain silently reverts to shadow after 90 days, a quarterly cross-domain bead that previously resolved to supervised would suddenly resolve to shadow — causing a regression without any signal, not even a Tier 1 INFORM. The principal would observe work slowing in a domain they haven't changed, with no indication that an evidence expiry was the cause.

**Recommendation:** Specify the tier-at-evidence-expiry rule for cross-domain resolution. The conservative option is revert to shadow (consistent with cold-start behavior). If so, add a Tier 1 INFORM signal for "domain tier reset due to evidence expiry" so the regression is observable. This is a single sentence addition to the cross-domain section but prevents a silent degradation in quarterly-work domains.

---

## Summary

| # | Finding | Section | Severity | Action |
|---|---------|---------|----------|--------|
| R-01 | intent.yaml fallback | §4 | RESOLVED | No action needed |
| R-02 | Interspect unavailability / INV-3 | §7 | PARTIAL | See R-02-b |
| R-04 | Tier 3 restart sequence | §5 | RESOLVED | No action needed |
| R-02-b | Authority snapshot has no named persistence store | §2, §7 | P1 | Name the persistence location (one sentence) |
| N-01 | signals.db is an unacknowledged single point of failure | §2, §5 | P1 | Specify corruption/loss recovery behavior |
| N-02 | Weight-drift threshold is a single Goodhart target | §10 | P2 | Multi-signal ensemble or explicit Goodhart acknowledgement |
| N-03 | Policy immutability during halt creates undocumented recovery ordering constraint | §7 INV-8 | P2 | Add recovery sequence note or `--supervised-only` mode |
| N-04 | Cross-domain min-tier has no evidence-expiry degradation path | §6 | P3 | Specify tier-at-expiry rule, add Tier 1 INFORM for silent resets |

### Net Assessment

The document has absorbed the three prior P1 findings with appropriate specificity. R-01 and R-04 are closed. The new sections (weight-outcome feedback, cross-domain resolution, signals.db persistence, policy immutability) introduce two new P1-equivalent issues that both stem from the same pattern: the no-daemon, CLI-invocation model creates implicit assumptions about what state persists between calls. The authority snapshot (R-02-b) and signals.db (N-01) are both stateful systems where the document specifies behavior without specifying failure modes. Resolving these two findings requires naming persistence locations and failure-mode behaviors, not redesign. The document is close to plan-ready; the open items are specification gaps, not architectural ones.
