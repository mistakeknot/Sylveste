---
artifact_type: flux-drive-review
reviewer: fd-balinese-subak-water-temple-governance
track: D (Esoteric)
target: docs/brainstorms/2026-04-03-ockham-vision-brainstorm.md
---

# Ockham Vision — Balinese Subak Water Temple Review

### Findings Index
- P0 | SUBAK-01 | "Key Decisions §2 / §3" | No feedback loop validates that Ockham weights improve outcomes; authority is enforcement-only
- P1 | SUBAK-02 | "Key Decisions §3" | Algedonic tiers switch mechanisms at each level rather than applying one mechanism at wider scope
- P1 | SUBAK-03 | "Open Questions §2" | Bead-to-theme mapping is label-based, making the intent system gameable by relabeling
- P2 | SUBAK-04 | "Key Decisions §4" | Autonomy ratchet threshold provenance is not outcome-linked — hardcoded values can drift from actual optimum
- P3 | SUBAK-05 | "Key Decisions §2" | Weight range [0.6, 1.4] is not calibrated to the resource-sharing topology

**Verdict: needs-changes**

---

### Summary

The Balinese subak water temple hierarchy is a 1000-year-old computationally-optimal governance system that coordinates thousands of competing rice terraces through scheduling weights — never through commands. J. Stephen Lansing's models show that the system achieves near-optimal pest management and water allocation through intermediate centralization, and that the temple's authority derives entirely from observable outcomes: terraces that follow schedules get fewer pests. The striking finding is that no farmer understands the global optimization they collectively achieve. This review maps three mechanistic isomorphisms to Ockham's design and finds that the brainstorm correctly captures the weight-multiplier architecture but misses the subak's most important design feature: authority that is outcome-derived rather than enforcement-derived. Ockham's weights are consumed by lib-dispatch.sh regardless of whether they improve outcomes — there is no mechanism to detect when Ockham's weights are wrong, which is structurally different from a temple whose authority disappears the moment its schedules produce pest outbreaks. Two additional findings concern mechanism switching across algedonic tiers and the label-based bead-to-theme mapping that enables gaming.

---

### Issues Found

**1. P0 — SUBAK-01: Ockham weights are followed by enforcement, not by demonstrated outcome advantage**

The brainstorm (§2, §4) specifies that `final_score = raw_score * ockham_weight` and that lib-dispatch.sh reads `ockham_weight` via `ic state set`. This is mechanically correct. The critical gap: there is no mechanism to compare dispatch outcomes between Ockham-weighted and unweighted selection, and no feedback path that detects when Ockham's weights are actively degrading bead outcomes.

The subak's authority is entirely outcome-derived. A farmer follows a planting schedule because terraces that synchronize get fewer pests. A farmer who stops following the schedule gets a pest explosion within one growing cycle — immediate, observable feedback. The temple's authority is self-validating through outcomes. If the temple produced schedules that increased pests, farmers would stop following them within one season, with no intervention required.

Ockham has no equivalent feedback loop. If the intent subsystem misconfigures theme budgets (say, over-weighting an auth theme that starves kernel beads), lib-dispatch.sh will faithfully execute the bad weights indefinitely. Interspect monitors agent reliability, not whether Ockham's weighting is improving factory throughput. The brainstorm mentions "thresholds start hardcoded, wire through intercept for calibration" but this refers to the ratchet thresholds, not to weight-outcome validation.

Concrete failure scenario: A principal sets `--theme auth --budget 60%` during a security push. Auth beads complete, but kernel beads are starved by the 0.6 weight. Cycle time in core/** degrades over weeks. Interspect sees no agent reliability signal (agents are doing their jobs; it is the selection weighting that is wrong). Ockham has no visibility into this because it never observes dispatch outcomes — it only produces weights. The degradation continues until the principal notices manually.

Fix (smallest viable): Add a weight-outcome validation pass to interspect's existing evidence pipeline. After N dispatch cycles under a given ockham_weight configuration, interspect computes the correlation between theme weight and bead cycle time for that theme. If cycle_time for a theme is degrading while ockham_weight for that theme is elevated, emit a Tier 1 INFORM signal: "Intent weight for theme X is not improving cycle time — consider recalibrating." This does not require Ockham to change its weights automatically; it closes the feedback loop so the principal can act.

**2. P1 — SUBAK-02: Algedonic tiers switch mechanisms rather than applying one mechanism at wider scope**

The brainstorm (§3) specifies three algedonic tiers with three different enforcement mechanisms:
- Tier 1 (INFORM): dispatch weights adjust
- Tier 2 (CONSTRAIN): lane freeze via `ic lane update --metadata="paused:true"` + `autonomy_tier=shadow`
- Tier 3 (BYPASS): `factory-paused.json` write + direct principal notification

The subak system's escalation is: individual subak adjusts planting (INFORM) → regional temple adjusts schedules for the watershed (CONSTRAIN) → supreme temple orders synchronized island-wide fallow (BYPASS). Crucially, all three tiers use the same mechanism — scheduling weights — at different scopes: field-level, watershed-level, island-level. The instrument does not change; the scope does.

Ockham's tiers are not scope-expansions of the same mechanism. They are three different instruments: weight adjustment, metadata freeze, and file write. This has a concrete implementation consequence: each tier requires different testing, different rollback, different failure modes, and different observability. A weight-adjustment bug and a metadata-freeze bug have entirely different recovery paths.

The subak insight is that scope-expansion of one mechanism is dramatically simpler than mechanism-switching. If all three Ockham tiers were weight adjustments at different scopes (bead-level weights, theme-level weights, factory-level weight multiplier), the system would have one implementation, one test surface, and one rollback path.

Concrete failure scenario: Tier 2 fires and successfully freezes a lane via metadata. The Tier 2 signal clears. Recovery is: unfreeze the lane, restore autonomy_tier. But the recovery path must also undo the metadata write and the bd set-state write — two different state stores with different atomicity guarantees. If the lane unfreeze succeeds but the bd set-state restore fails (Dolt hiccup), the domain is operationally unfrozen but Ockham still believes it is in shadow mode, leading to weight suppression that is invisible to the principal.

Fix: This is an architectural suggestion, not a one-liner. Consider whether Tier 2 could be implemented as a theme-level ockham_weight of 0.0 applied to all beads in the affected domain, rather than a metadata freeze. A weight of 0.0 means the domain's beads have zero selection probability — equivalent to a freeze — but the instrument is the same as Tier 1 (weight adjustment, just at theme scope and extreme magnitude). Recovery is then a single weight revert, not a multi-store undo. Document the tradeoff explicitly: metadata freeze provides stronger guarantees but complex recovery; weight-to-zero provides weaker isolation but simpler recovery.

**3. P1 — SUBAK-03: Bead-to-theme mapping is label-determined, not infrastructure-determined**

Open Question 2 asks how Ockham knows which beads belong to which theme. The brainstorm does not specify the answer, but the design's natural answer is lane metadata or bead labels. This is label-determination.

The subak system's coordination scope is infrastructure-determined: which terraces share an irrigation channel is a physical fact, not a label. A farmer cannot claim membership in a better-irrigated watershed by relabeling their terrace. The mapping is hard.

A label-based theme mapping is soft. An agent (or the model running an agent) could label a bead with a high-weight theme to attract dispatch priority. If `--theme auth --budget 40%` means auth-labeled beads get ockham_weight=1.4, an agent managing a low-priority cleanup task can accelerate its own bead by relabeling it as an auth concern. The gaming surface is especially large when the model writing the bead description is the same model being dispatched to work on it.

Concrete failure scenario: Ockham is configured with `--theme auth --budget 50%`. A model agent, through bead update or creation, labels a refactoring bead as "auth-adjacent: removes legacy session handler." Ockham's theme-matching logic (path-based heuristics or label matching against bead description) assigns it a partial auth weight. Over many beads, this inflates the effective auth budget beyond 50% and displaces legitimately high-priority kernel work.

Fix: Infrastructure-determine the primary mapping. Bead file paths (the files a bead modifies) map to themes through the module boundary: `core/**` is kernel theme, `interverse/**` is plugin theme, `os/Clavain/**` is dispatch theme. Labels and lane metadata can override this but only downward (reduce weight, never increase). Ockham's intent subsystem should resolve theme membership by file paths first, fall back to lane, and ignore free-text bead labels entirely. This one policy change eliminates the relabeling attack surface.

**4. P2 — SUBAK-04: Ratchet thresholds are hardcoded without outcome linkage**

The brainstorm (§4) states: "Thresholds start hardcoded, wire through intercept for calibration. The promotion decision becomes an intercept gate: log every decision, distill a local model after 50+ examples."

The subak system's scheduling thresholds (planting dates, fallow periods) are not hardcoded — they are co-evolved over 1000 years by observing what pest outcomes each schedule produces. The system's current thresholds represent 1000 years of outcome-linked calibration. The subak does not use the same planting window for all rice varieties in all watersheds; the schedules vary by elevation, rainfall, and pest pressure.

Ockham's hardcoded thresholds will be wrong for the specific factory they govern — wrong in ways that the original designers cannot know in advance. The intercept calibration path (wire through after 50+ examples) is the right direction, but the brainstorm does not specify what the intercept model is being calibrated against. If the intercept model optimizes for promotion/demotion frequency matching historical decisions (it learns to replicate the hardcoded logic), it will perpetuate the original miscalibration. If it optimizes for factory outcome improvement (it learns which thresholds produce better cycle time and first_attempt_pass_rate), it provides genuine calibration.

Fix: Specify the intercept calibration target explicitly. The intercept model should optimize for `bead_cycle_time_improvement` and `first_attempt_pass_rate` in the post-promotion period, not for agreement with historical Ockham decisions. This is a one-line specification change in the brainstorm, but it determines whether the calibration loop converges to the actual optimum or just codifies the initial miscalibration.

**5. P3 — SUBAK-05: Weight range [0.6, 1.4] is not calibrated to dependency topology**

The brainstorm (§2) specifies `final_score = raw_score * ockham_weight` with the example of an auth bead at 40% budget getting weight 1.4 and an unlinked bead getting 0.6. The weight range [0.6, 1.4] represents a maximum 2.33x advantage for a maximally-weighted bead over a minimally-weighted bead.

The subak insight is that the optimal coordination scope depends on the resource-sharing topology. Terraces in the same irrigation channel share water directly and require tight coordination; terraces in different watersheds are effectively independent. Ockham's weight range is topology-blind: it applies the same [0.6, 1.4] range to beads whether they are deeply interdependent (blocking other beads through a dependency chain) or completely independent.

A bead that is a dependency blocker for 12 other beads should get a higher weight multiplier than a bead in the same theme with no dependents. The dependency topology is already available (the vision mentions "deps 12%" in the dispatch formula), but the weight range does not modulate by dependency depth.

Suggestion: Define a topology modifier within the ockham_weight calculation: `ockham_weight = theme_weight * (1 + dependency_depth_factor)`, where `dependency_depth_factor` is a small positive value (0.0 to 0.3) based on how many beads are blocked by this bead. This narrows the theme-only weight range while adding topology-sensitivity, matching the subak's insight that coordination scope should track resource-sharing structure, not just administrative category.

---

### Improvements

1. **Add a weight-outcome correlation check to interspect's evidence pipeline**: After N dispatch cycles, compute the correlation between ockham_weight assignments for each theme and the cycle_time outcomes for beads in that theme. Emit a Tier 1 INFORM signal when a high-weight theme shows degrading cycle time — closing the feedback loop that makes Ockham's authority outcome-derived rather than enforcement-derived.

2. **Evaluate weight-to-zero as a Tier 2 implementation**: Before finalizing the CONSTRAIN tier as a metadata freeze, spec out whether `ockham_weight = 0.0` applied at theme scope achieves the same isolation guarantee with a simpler recovery path (single weight revert vs. multi-store undo). Document the tradeoff explicitly.

3. **Make file-path the primary bead-to-theme mapping**: In the intent subsystem, resolve theme membership from bead file paths against module boundaries first, with lane metadata as a secondary signal, and ignore free-text labels. This eliminates the relabeling attack surface without requiring any new infrastructure.

4. **Specify the intercept calibration target**: In the autonomy ratchet section, add one sentence: "The intercept model optimizes for post-promotion cycle_time and first_attempt_pass_rate improvement, not for agreement with historical Ockham decisions." This ensures the calibration loop converges on the actual factory optimum.

5. **Add a dependency-depth modifier to ockham_weight**: Extend the weight calculation to include a small topology-sensitive term that elevates weights for beads that are blocking deep dependency chains, matching weight magnitude to resource-sharing structure rather than administrative category alone.
