# fd-venetian-glass-grading: Material Grading & Evidence-Quality Review

**Reviewer:** fd-venetian-glass-grading (Murano master vetraio — material grading, artisan allocation)
**Document:** `docs/brainstorms/2026-04-04-cross-model-dispatch-brainstorm.md`
**Date:** 2026-04-04
**Scope:** Grade-before-invest validity, thermal commitment (one-shot assignment), batch contamination of synthesis, maestro scarcity and hidden-quality surfacing
**Track:** C — Distant domain structural isomorphism

---

## Executive Summary

The brainstorm's central move is correct: grade the material before committing artisan skill. Expansion score is the grade; model tier is the furnace temperature. But the Murano lens reveals two structural gaps the brainstorm does not address:

1. **The grading instrument is unvalidated.** Expansion scoring is used as a purity signal without any calibration against actual downstream findings. A Murano maestro who grades silica by unverified heuristics would contaminate every subsequent batch.
2. **Synthesis treats all findings as equal regardless of the tier that produced them.** A finding from a haiku-tier agent carries the same weight as one from a sonnet-tier agent in Phase 3. This is the batch contamination problem: one low-grade batch dilutes the crucible.

---

## P1 Findings

### [P1] Expansion score is used as a tier signal without validated calibration (brainstorm, "Design Space" section, lines 55–98)

The brainstorm maps expansion_score directly to model tier: score 3 → keep or upgrade, score 1 → downgrade. This assumes the expansion score is an accurate purity signal for the value that the launched agent will deliver. No evidence for this accuracy is presented, and no calibration mechanism is proposed.

In Murano glassmaking, silica purity is measured instrumentally before furnace commitment. A maestro who grades by visual inspection alone risks thermal mismatch — high-temperature furnace work on impure batch glass produces catastrophic shattering. The equivalent failure here: a score-3 expansion triggered by a P0 in fd-architecture that is wholly specific to that domain (e.g., a type-system invariant violation) expands fd-game-design at opus tier, even though the P0 has no valid adjacency. The score was high; the adjacency transfer was phantom.

The brainstorm's risk table (lines 206–212) acknowledges "token savings < projected" as a medium-likelihood risk but does not acknowledge "expansion score inflated by domain-specific P0" as a distinct failure mode. The finding quality degrades entry (row 3) notes monitoring via intertrust precision scores — but that is post-hoc correction, not pre-launch validation.

**Failure scenario:** `fd-architecture` surfaces a P0 (score contribution +3). `fd-game-design` is launched at sonnet tier. The P0 is a type-narrowing invariant specific to Go's type system — it has no game-design adjacency. `fd-game-design` produces a null finding at sonnet cost. The score was accurate as a signal of *some* P0 existing; it was inaccurate as a signal that fd-game-design should launch at sonnet tier to investigate it.

**Smallest fix:** Add an adjacency-transfer validity check to expansion scoring. Before mapping score → tier, ask: does the triggering finding's *category* overlap with the expansion candidate's domain? In `expansion.md` Step 2.2b, before writing `expansion_score`, check `trigger_finding_domain ∩ candidate_domain != ∅`. If the intersection is empty, cap the expansion tier at haiku regardless of score.

---

## P2 Findings

### [P2] Synthesis treats findings from all tiers equally — batch contamination is unaddressed (brainstorm, "Constraints" section, lines 172–179; "Out of Scope" section, lines 193–198)

The brainstorm explicitly scopes out flux-review changes ("no expansion pool in review mode"). But the expansion pool agents' findings flow into Phase 3 synthesis regardless. A haiku-tier agent on a score-1 expansion produces lower-confidence findings. If Phase 3 synthesis weights all findings equally, a confused or sparse haiku finding carries the same evidentiary weight as a sonnet finding on the same topic.

In Murano, one impure batch inserted into the crucible after grading contaminates the melt. The glass cannot be un-contaminated mid-pour. Similarly, a Phase 3 synthesis that ingests haiku findings at the same weight as sonnet findings cannot distinguish high-confidence from low-confidence evidence.

The task context for this review notes: "Synthesis reads all agent findings equally. No tier-weighted synthesis exists." The brainstorm does not add tier-weighted synthesis, and explicitly defers flux-review changes. This leaves the contamination path open.

**Failure scenario:** `fd-game-design` is downgraded to haiku (score=1). It produces a finding that misidentifies a P2 as a P0 because haiku-tier reasoning cannot correctly assess the severity of a complex interaction pattern. Synthesis escalates this as P0. The run owner investigates. No issue exists at P0 severity. A false-positive P0 was injected by a haiku agent on a low-confidence expansion.

**Smallest fix:** This is a Phase 3 concern and the brainstorm correctly defers flux-review changes. But the "Logging" section (lines 161–169) should be extended to emit `tier` per agent finding in the output stream, so Phase 3 synthesis can optionally weight by tier. This requires no architecture change — just adding `tier: haiku|sonnet|opus` to the per-agent finding log. Phase 3 can ignore it initially; the data is present for future weighted synthesis.

---

### [P2] One-shot tier assignment ignores mid-run evidence that would change the grade (brainstorm, "Implementation Sketch" section, lines 119–159)

Murano's thermal commitment is real: once glass enters the furnace at a temperature, you cannot mid-process change it without shattering risk. But the brainstorm accepts this as a constraint without examining whether it is truly necessary.

The brainstorm assigns tier at dispatch time (Step 2.2b → 2.2c) and holds it for the agent's duration. If an agent launched at haiku tier encounters early-stage evidence that the problem is significantly harder than the expansion score indicated, there is no re-evaluation path. The agent continues at haiku, producing degraded findings.

**Failure scenario:** `fd-decisions` is launched at haiku (score=1). Ten tool calls in, the agent has retrieved three files showing a subtle distributed-consensus failure. The domain complexity exceeds haiku's reasoning envelope. The agent produces a confused finding. There is no circuit-breaker that re-evaluates tier based on early findings.

**Smallest fix:** Add a single re-evaluation checkpoint: after an agent's first substantive tool call (first file read or first function trace), check if the `finding_complexity_hint` (a new lightweight signal: "simple pattern match" vs "cross-system reasoning") exceeds the tier's expected envelope. If so, allow a one-time tier upgrade. This is not dynamic tier switching — it is a single commit decision at the first evidence checkpoint, not mid-furnace adjustment.

---

## P3 Findings

### [P3] The upgrade path for score==3 haiku checkers is left as an open question (brainstorm, "Open Questions" section, lines 199–203)

Open Question 1 asks whether score==3 should upgrade haiku checkers to sonnet. The brainstorm's answer is "keep model (no upgrade), but the function could support it." The Murano equivalent: when a batch glass sample reveals unexpectedly high cristallo-grade purity, Murano masters do upgrade it to maestro hands. The asymmetry of the current proposal (downgrades allowed, upgrades deferred) creates a subtle cost-optimization bias: the system captures downgrade savings but not upgrade quality gains.

This is P3 because the system defaults to safe behavior (keep tier), but the decision should be made explicitly, not left as an open question with a "could support it" note. If the function will support upgrades, the spec should document the upgrade semantics now — even if the feature ships disabled. Leaving it as a code comment creates later confusion about whether the upgrade path is an incomplete feature or a deliberate off-switch.

---

## Summary

The grade-before-invest principle is correctly applied. The two gaps that matter:

1. **Grade validity (P1):** Expansion score is used as a purity signal without cross-validating adjacency transfer. A phantom adjacency inflates the score and wastes opus/sonnet tier on a domain where the triggering finding has no valid transfer.
2. **Synthesis contamination (P2):** Tier-adjusted findings flow into Phase 3 at equal weight. Tier metadata should be emitted in the finding log now so weighted synthesis can use it later.

The one-shot assignment constraint (thermal commitment) is real but could be softened with a single first-checkpoint re-evaluation — not continuous adjustment, just one commit point.
