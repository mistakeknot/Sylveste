---
agent: fd-quality
status: NEEDS_CHANGES
finding_count: 10
---

## Findings Index

- HIGH  | Q-1  | F3: lib-dispatch.sh offset wiring | `ic state list <k>` returns scope_ids only — bulk value fetch assumed by PRD does not exist
- HIGH  | Q-2  | F6: Autonomy ratchet | `agent_reliability()` interface assumed but does not exist in interspect
- HIGH  | Q-3  | F3 / F4 / F6 | CONSTRAIN check in F3 references frozen themes but Tier 2 CONSTRAIN is a Wave 2 non-goal — the AC will fail on day 1
- MED   | Q-4  | F4 / F6 | Duplicate AC: 30-day re-confirmation appears identically in both F4 and F6 with no ownership resolution
- MED   | Q-5  | F5 | Cycle time per theme is not available from any listed dependency
- MED   | Q-6  | Non-goals | "Not a quality arbiter" and "Not an audit log" from brainstorm § 8 are absent from the non-goals section
- MED   | Q-7  | F3 | No AC tests the negative: a bead in a frozen theme is NOT selectable despite a positive offset
- MED   | Q-8  | F7 | `ockham health --json` AC duplicates pleasure signal output already specified in F5's `ockham health --json` AC
- LOW   | Q-9  | F2 | F2 names packages `internal/scoring` and `internal/governor` but Ockham directory has `internal/dispatch` (not `scoring`)
- LOW   | Q-10 | F5 | Baseline prediction ("predicted baseline per theme") has no specified source or bootstrapping procedure for themes with no history

---

## Summary

The PRD is structurally well-organized and most ACs are testable. Three blocking issues require attention before implementation starts: the bulk state-fetch interface assumed by F3 does not exist in `ic`; the `agent_reliability()` function assumed by F6 does not exist in interspect; and F3's CONSTRAIN check is self-contradictory because the anomaly package that would produce CONSTRAIN signals is explicitly deferred to Wave 2. The non-goals section is missing two items that appear in the brainstorm's "What Ockham Is NOT" list, and three absence-of-behavior ACs are needed to prevent dispatch from silently violating the frozen-theme contract. The remaining issues are clarification gaps that will slow implementation but not cause hard failures.

---

## Issues Found

**Q-1. HIGH: `ic state list` returns scope_ids only — bulk value fetch does not exist**

F3 AC: `lib-dispatch.sh reads offsets: ic state list "ockham_offset" --json (bulk pre-fetch, once per cycle)`.

The actual `ic state list <k>` signature (confirmed by `ic --help` and live test) is:

```
state list <k>    List scope_ids for a key
```

It returns a list of scope identifiers, not key→value pairs. There is no `--json` flag on `state list` and no mode that returns both the scope_id and the stored value in a single call. The value for each bead would require a separate `ic state get <k> <scope_id>` per bead — which is exactly the per-bead cost the PRD is trying to avoid.

Fix: Either extend `ic state list <k> --json` to return `[{scope_id, value}]` objects (requires an intercore change that should be tracked as a dependency), or accept per-bead `ic state get` calls and remove the "bulk pre-fetch" claim from the AC. If the intercore extension is chosen, add it to the dependencies table with status "Requires implementation".

---

**Q-2. HIGH: `agent_reliability()` interface assumed by F6 does not exist in interspect**

The brainstorm (§ "Split evidence/policy ownership") specifies: `interspect exposes agent_reliability(agent, domain) -> {hit_rate, sessions, confidence, last_active}`. The dependencies table lists interspect as "Available" for F6 (agent_reliability).

A search of `lib-interspect.sh` finds no function named `agent_reliability` or any function with that signature. The library exposes routing confidence, delegation pass rates, and pattern classification — but these are not equivalent to per-(agent, domain) promotion evidence. The `_interspect_classify_pattern` function and `_interspect_compute_delegation_stats` function operate on routing overrides, not on the (agent, domain) grant model Ockham needs.

The dependency is listed as "Available" but the interface does not exist. F6's cold-start logic, promotion guard evaluation, and re-confirmation all depend on this function.

Fix: Either add `agent_reliability(agent, domain)` to interspect as a new function (add to dependencies table with status "Requires wiring") or define a thin interspect adapter inside Ockham that assembles the required struct from existing interspect primitives. The dependency row for F6 should change from "Available" to "Requires implementation".

---

**Q-3. HIGH: F3's CONSTRAIN check contradicts the Wave 2 non-goal**

F3 AC: `Evaluation order: (1) CONSTRAIN check — frozen theme → score=0, skip`.

The non-goals section explicitly defers: `Tier 2 CONSTRAIN — requires anomaly package with multi-window confirmation (Wave 2)`.

The CONSTRAIN terminology in F3 is borrowed directly from the algedonic tier model. In Wave 1, the only mechanism that sets a theme frozen is an explicit `ockham intent --freeze <theme>` from the principal (F1). The brainstorm makes this distinction: freeze via `ockham intent` uses the existing lane-pause mechanism (`ic lane update --metadata="paused:true"`), which lib-dispatch.sh already checks at line 195 (the `_lane_paused` branch in `dispatch_rescore()`).

F3's CONSTRAIN AC is therefore partially redundant with the existing lane-pause check, partially aspirational (implying an anomaly-triggered freeze that does not exist in Wave 1), and has no acceptance test that could distinguish these two cases. An implementer following F3 literally would build a new CONSTRAIN gate in lib-dispatch.sh, duplicating the lane-pause check.

Fix: Replace the CONSTRAIN AC in F3 with a precise statement: `Evaluation order: (1) lane-pause check — bead's theme is frozen via ic lane update --metadata="paused:true" → score=0, skip (this reuses the existing rsj.1.5 lane-pause path, no new gate needed); (2) apply ockham_offset; ...`. Add a note that Tier 2 CONSTRAIN auto-freeze (anomaly-triggered) extends this path in Wave 2.

---

**Q-4. MED: Duplicate AC for 30-day re-confirmation across F4 and F6**

F4 AC: `30-day autonomous re-confirmation triggers on ockham check (staggered by promotion timestamp)`.
F6 AC: `30-day re-confirmation for autonomous domains (staggered by promotion timestamp)`.

These are identical in effect. F6 defines the policy; F4 defines the trigger mechanism. The duplication creates an implementation ambiguity: if the F4 AC passes but the F6 AC doesn't, or vice versa, which is canonical?

More critically, neither AC defines what "re-confirmation" means in testable terms: does the domain demote to supervised, does it pause dispatch, does it require explicit principal action? The brainstorm says "re-evaluated against the promotion guard; if evidence has degraded below threshold, the domain demotes to supervised" — this specific behavior is absent from both ACs.

Fix: Remove the F4 AC and replace with: `ockham check evaluates autonomy re-confirmation timers and, for any autonomous domain where promotion_timestamp is >30 days old, re-runs the promotion guard; domains that fail the guard are demoted to supervised and logged`. Keep F6 as the policy definition, F4 as the trigger location.

---

**Q-5. MED: Cycle time per theme is not available from any listed dependency**

F5 AC: `Weight-drift: compares actual cycle time + gate pass rate vs predicted baseline per theme`.
Dependency table: `interstat (cost-query.sh)` is listed as providing cycle time for F5.

Reviewing `cost-query.sh`, the available modes are: aggregate, by-bead, by-phase, by-phase-model, by-bead-phase, session-count, per-session, cost-usd, cost-snapshot, baseline, shadow-savings, shadow-by-model, shadow-roi, session-cost, effectiveness. None of these modes aggregate cycle time (claim-to-close duration) per lane/theme.

Cycle time is a beads-level metric: the interval between a bead's `claimed_at` timestamp and its `closed_at` timestamp, grouped by lane label. This data lives in the beads tracker (via `bd list --json`), not in interstat. Interstat tracks token costs per session, not per-bead completion timing.

Fix: Change the F5 dependency to `beads (bd list --json | jq '.[].claimed_at, .closed_at, .labels')` for cycle time, and keep interstat for cost trend. Update the dependency table accordingly.

---

**Q-6. MED: Two "What Ockham Is NOT" items from brainstorm absent from non-goals**

The brainstorm § 8 lists six boundaries. The PRD's non-goals section matches four of them but omits two:

- "Not a quality arbiter. Quality gates are Clavain's domain. Ockham never evaluates code quality or review correctness." — absent from PRD non-goals.
- "Not an audit log. Interspect owns the evidence trail. Ockham writes to interspect, never maintains its own audit store." — absent from PRD non-goals.

Both have implementation-relevant consequences. The "not a quality arbiter" boundary prevents scope creep in F5 (weight-drift uses pass rates from interspect as inputs — it does not evaluate pass/fail itself). The "not an audit log" boundary governs where ratchet decision records live (F6 logs through intercept, not signals.db). If an implementer doesn't know these boundaries, signals.db grows an audit responsibility it was never meant to have.

Fix: Add both items to the non-goals section verbatim from the brainstorm.

---

**Q-7. MED: No AC tests that a frozen-theme bead is NOT dispatchable regardless of offset**

F3 specifies that frozen themes receive `score=0, skip`. F1 specifies that `ockham intent --freeze auth` adds auth to the freeze list. But no AC verifies the composed behavior: a bead in a frozen theme with a high positive `ockham_offset` (+6) must still be ineligible for dispatch.

This is an absence-of-behavior AC. Without it, an implementer who applies the offset before the freeze check would produce beads with offset=+6, floor-guarded to 1, that are technically claimable. The evaluation order is specified, but there is no test that validates the ordering produces the correct skip.

Similarly, F7 specifies that when the halt sentinel is active, all Ockham write operations are blocked — but there is no AC that verifies `ockham intent --theme auth --budget 0.5` returns an error (not silently succeeds) when factory-paused.json is present.

Fix: Add to F3: `A bead in a theme frozen via ockham intent --freeze is NOT selected by dispatch even when its ockham_offset is +6`. Add to F7: `ockham intent --theme auth --budget 0.5 returns exit code 1 with an error message when the halt sentinel is active`.

---

**Q-8. MED: `ockham health --json` AC appears in both F5 and F7 with conflicting scope**

F5 AC: `ockham health --json includes pleasure signal values and trend directions`.
F7 AC: `ockham health outputs JSON: pain signals (...), pleasure signals (pass rate, cycle time, cost trends), ratchet state, overall status`.

Both specify `ockham health --json`. F7 is a superset of F5 (it includes pleasure signals plus pain signals, ratchet state, and overall status). If an implementer implements F7's AC first, F5's AC passes trivially. If F5 is implemented first (per feature order), F7 requires a rewrite.

This is not a duplication that causes incorrect behavior — it is a sequencing trap. The more subtle problem: F5's AC says "trend directions" while F7 says "cost trends" but does not say "trend directions". These may test for different JSON fields.

Fix: Remove the `ockham health --json` AC from F5. Replace with: `Pleasure signal values and trend directions (improving/degrading/stable) are written to signals.db fields: first_attempt_pass_rate, cycle_time_trend, cost_trend`. F7 remains the authoritative ockham health spec and can reference "reads pleasure signal trends from signals.db".

---

**Q-9. LOW: F2 package name `internal/scoring` conflicts with existing `internal/dispatch`**

F2 specifies building `internal/intent`, `internal/scoring`, and `internal/governor`. The existing Ockham directory structure has `internal/dispatch`, not `internal/scoring`. The CLAUDE.md and AGENTS.md for Ockham both use `dispatch` for the weight synthesis package.

This is a naming inconsistency between the PRD and the existing (pre-code, scaffold-level) repository structure. An implementer following the PRD would create `internal/scoring/` alongside the existing `internal/dispatch/` directory, producing two packages with overlapping responsibility.

Fix: Either update F2 to say `internal/dispatch` (matching the existing scaffold) or update the repository CLAUDE.md/AGENTS.md to rename the planned package to `scoring`. The brainstorm § 1 explicitly says "renamed: Scoring, not Dispatch" — the PRD is correct on intent but the scaffold pre-dates this decision. Resolve in the PRD by noting: `internal/scoring (directory currently scaffolded as internal/dispatch — rename as part of this wave)`.

---

**Q-10. LOW: "Predicted baseline per theme" has no bootstrap procedure**

F5 AC: `Weight-drift: compares actual cycle time + gate pass rate vs predicted baseline per theme`.
F5 also specifies: `Drift detection activates only after ≥10 completed beads per theme`.

The minimum sample size guard is correct. But the AC does not specify what the "predicted baseline" is or how it is computed from those first 10 beads. The brainstorm section 10 says "compare actual cycle time and quality gate pass rate against the predicted baseline for that theme" but does not define whether the baseline is the mean of the first 10, the median of the first 10, a percentile, or an externally configured value.

Without a specified baseline derivation, two independent implementers will build different drift detectors that are equally "correct" per the AC but incompatible. This is a low-risk ambiguity because the threshold check (>20% degradation) is clearly specified, but the reference point is not.

Fix: Add one sentence: `Baseline is computed as the rolling 14-day p50 of cycle_time and gate_pass_rate for that theme, initialized once the theme reaches ≥10 completed beads. Below threshold, drift detection logs "insufficient_data" and skips`.

---

## Improvements

**Q-I1. Add an AC for `ockham intent validate` exit code on unknown theme freeze entries** — The AC says misspelled entries in freeze/focus are errors, not silent no-ops. Specify the exit code (non-zero) and whether the error message names the unknown theme. This makes the AC machine-testable.

**Q-I2. Specify signals.db schema as part of F4 acceptance** — F4 says signals.db "stores: signal timestamps, confirmation window state, ratchet timers, authority snapshots" but lists no column names or table structure. At minimum, F4 should reference or include the CREATE TABLE statements so that F5 and F6 implementers know which fields to write without inspecting each other's code.

**Q-I3. Clarify what `intercept decide` receives for ratchet decision logging (F6)** — F6 says "Ratchet decisions logged through intercept for future distillation." `intercept decide <gate> --input <json>` expects a gate name and a JSON input blob. Specify the gate name and the JSON schema so that an implementer can write the logging call without guessing the interface.

<!-- flux-drive:complete -->
