---
artifact_type: flux-drive-findings
track: adjacent
target: apps/Auraken/docs/designs/forge-mode.md
date: 2026-03-31
agents: [fd-adversarial-testing-lens-safety, fd-cognitive-science-near-miss-learning, fd-alignment-recursive-improvement, fd-simulation-profile-dynamics, fd-ontology-lens-metadata]
---

# Flux-Drive Findings: Forge Mode — Track A (Adjacent)

Target: `apps/Auraken/docs/designs/forge-mode.md`
Supporting context: `apps/Auraken/docs/designs/lens-contraindications.md`, `apps/Auraken/PRD.md`, `apps/Auraken/PHILOSOPHY.md`

---

## fd-adversarial-testing-lens-safety

### Finding 1: No Coverage Tracking Across Lens Pairs

**Severity:** P1

**Description:** Forge Mode's Stress Test sub-mode describes ad-hoc scenario generation driven by the user ("User specifies a capability to stress-test" -- forge-mode.md line 35) but provides no mechanism to track which lens pairs or lens clusters have been tested and which have not. With 291 lenses and the `near_miss_lenses` field connecting them, the theoretical space of confusable pairs is large. The design produces individual stress test logs (line 73-74: "Stress test log (scenario + resolution, for future regression testing)") but has no coverage map that shows: these 40 pairs have been tested, these 200 pairs have not, and these 15 pairs are highest priority based on shared surface features or overlapping `forces`.

**Failure scenario:** After 30 Forge sessions, the builder believes the lens library is well-tested, but the sessions concentrated on cognitively salient pairs (sunk-cost vs. values-conflict, which is the go-to example in both design docs). Subtle near-miss pairs involving less familiar lenses (e.g., `lens_commitment_escalation` vs. `lens_explore_vs_exploit`) remain completely untested. A real user hits one of these pairs and gets a harmful misapplication.

**Recommendation:** Add a "coverage index" artifact to the Forge Mode artifact pipeline: a matrix of lens pairs with `near_miss_lenses` relationships, annotated with test status (untested / tested-date / regression-passing). The Stress Test sub-mode should consult this index to suggest which pairs to test next, prioritizing pairs with high surface-feature overlap (computed from shared `forces` or `scale` tags) and zero test coverage.

### Finding 2: No Treatment of Multi-Lens Ambiguity (3+ Lenses)

**Severity:** P2

**Description:** The Stress Test example (forge-mode.md lines 47-69) and the entire contraindications schema (lens-contraindications.md `near_miss_lenses` field) treat near-miss confusion as pairwise: lens A vs. lens B. But the selector in `select_lenses()` can return 0-3 lenses per turn (lens-contraindications.md line 16: "pick 0-3 lenses from a flat index"). The harder class of failure is when 3 lenses match on surface features and the correct answer is lens C, but contraindication checks on lens A and B individually pass because each contraindication was written for a pairwise contrast. A lens that is only contraindicated in the presence of a specific third lens is invisible to the current design.

**Recommendation:** Add a "multi-lens ambiguity" stress test variant to the Dojo sub-mode. When the coverage index shows a cluster of 3+ lenses with overlapping `forces` or shared `near_miss_lenses` targets, generate scenarios where all three match and the correct resolution depends on contextual weighting among all three, not pairwise elimination.

### Finding 3: Stress Test Logs Lack Structural Schema for Regression Replay

**Severity:** P2

**Description:** The design mentions stress test logs as "timestamped scenarios with resolutions, stored as regression test candidates" (forge-mode.md line 211). But the output artifacts section (lines 72-74) specifies only "Stress test log (scenario + resolution, for future regression testing)" with no structured schema. A conversational scenario narrative ("A user has spent 3 years building a side project...") cannot be automatically replayed through the selector to verify it still makes the correct choice after metadata updates. Regression testing requires: the input text, the expected lens selection, the expected contraindication matches, and the expected final lens set.

**Recommendation:** Define a stress test log schema with fields: `input_text`, `known_entities` (if any), `candidate_lenses` (selector output), `expected_final_lenses`, `contraindications_triggered`, `distinguishing_features_checked`, `resolution_rationale`. This makes logs replayable as automated regression tests against `select_lenses()` and the verify/check pipeline.

---

## fd-cognitive-science-near-miss-learning

### Finding 4: Distinguishing Features Are Standalone Properties, Not Contrastive Pairs

**Severity:** P1

**Description:** The `distinguishing_features` field in the contraindications schema (lens-contraindications.md lines 31-34) stores standalone properties: "Past investment cited as primary reason for continuing, separate from future expected value" (line 202). Per Winston's near-miss learning theory, a distinguishing feature is only meaningful relative to the specific near-miss it discriminates against. The same feature -- "user references past investment as primary reason" -- might distinguish sunk-cost from values-conflict (where past investment is incidental) but would NOT distinguish sunk-cost from commitment-escalation (where past investment is also central, but the mechanism is different). The current flat `list[str]` formulation loses the critical information of which contrast each feature serves.

This is compounded in the Forge Mode example (forge-mode.md lines 58-68): the distinguishing question "If you'd only spent 3 months on this project, would you still want to stop?" is generated for the sunk-cost vs. values-conflict contrast specifically. But when stored as a standalone distinguishing feature, there is nothing anchoring it to that particular near-miss pair. A future verification step checking sunk-cost against explore-vs-exploit would find this feature, attempt to apply it, and get a meaningless result.

**Recommendation:** Restructure `distinguishing_features` as a list of objects: `[{discriminates_against: "lens_values_conflict", feature: "Past investment cited as primary reason...", question: "If you'd only spent 3 months..."}]`. This anchors each feature to the specific contrast it serves, following Winston's principle that near-miss examples must be paired with the specific boundary they define.

### Finding 5: No Progressive Difficulty Ordering in Scenario Generation

**Severity:** P2

**Description:** The Forge Mode flywheel (forge-mode.md lines 168-178) describes a cycle: stress test finds edge cases, updates metadata, profile sim validates, meta applies, repeat. But there is no mechanism for progressive difficulty in scenario generation. Cognitive science research on concept formation (Gentner's structure-mapping, Kotovsky and Gentner 1996) shows that learners build category boundaries more effectively when examples progress from easy (high surface + structural difference) to hard (surface similarity + subtle structural difference). The Forge Mode design generates scenarios at whatever difficulty the builder chooses, with no awareness of whether the current boundary is well-established enough to handle harder cases.

After 50 Forge sessions, the metadata might contain both easy distinctions (sunk cost vs. pace layers -- very different domains) and hard distinctions (sunk cost vs. values conflict -- overlapping surface features) accumulated in random order. Without progressive ordering, harder cases may have been attempted before easier cases established a stable boundary, producing mushy intermediate rules that neither case sharpened properly.

**Recommendation:** Add a difficulty estimation heuristic to Stress Test scenario generation, based on: (a) number of shared `forces` between the two lenses, (b) number of shared `scale` tags, (c) semantic similarity of `when_to_apply` fields. Suggest easier pairs first for newly-created near-miss relationships, graduating to harder pairs once the distinguishing features for easy cases are stable.

### Finding 6: Flywheel Lacks Convergence Signal

**Severity:** P2

**Description:** The Forge Mode flywheel (lines 168-184) describes each cycle making Auraken "more robust" and "more honest" but provides no convergence metric. How does the builder know when a particular lens boundary is sufficiently refined? Without a convergence signal, the flywheel either stops prematurely (the builder gets bored) or continues past the point of diminishing returns (adding contradictions to already-well-defined boundaries). In concept learning, convergence is measured by the stability of the category boundary across new examples -- if the last N examples all confirm the existing boundary without requiring adjustments, the concept is stable.

**Recommendation:** Track boundary stability per near-miss pair: count consecutive Forge sessions where the pair is tested and no metadata update is required. After 3 consecutive stable tests, mark the pair as "converged" in the coverage index. This gives the builder a signal to move on to less-stable pairs.

---

## fd-alignment-recursive-improvement

### Finding 7: Ambiguous Staging Gate Between Forge Artifacts and Production

**Severity:** P1

**Description:** The design sends contradictory signals about whether Forge Mode artifacts go directly to production. Design Principle 5 (forge-mode.md line 195) states "Session artifacts are versioned. Forge sessions produce diffs to lens metadata, profile rules, and design docs. These should be version-controlled and reviewable, not silently applied." The artifact pipeline section (lines 208-209) specifies: "Lens metadata updates: written to lens JSON files, staged for review" and "Profile rule updates: written to design docs, require explicit approval before code changes."

However, the Stress Test example (lines 68-69) shows the agent immediately acting: "I'll add that as a distinguishing question for both lenses and mark them as near-misses for each other. [Updates lens metadata]". This suggests in-session updates to the lens JSON, not a staged review. Since Forge Mode operates within the same agent that serves real users, and the lens JSON files are the production lens library, the question is: does "[Updates lens metadata]" write to production or to a staging copy?

**Failure scenario:** The builder runs a Forge session that adds an overly broad contraindication to `lens_sunk_cost` (e.g., "contraindicated when user mentions values"). The update goes directly to the production lens JSON. The next real user who discusses a genuine sunk-cost situation with any mention of "values" in the conversation gets the sunk-cost lens filtered out by the contraindication check. The user receives no framework when one was appropriate.

**Recommendation:** Make the staging gate explicit in the design: Forge Mode writes to a `lens_library_staging.json` (or a git branch). A separate review step -- which can be as lightweight as `git diff lens_library_v2.json` before committing -- prevents in-session changes from reaching production. The Stress Test example should show "[Stages lens metadata update for review]" not "[Updates lens metadata]".

### Finding 8: No Regression Detection for Cumulative Metadata Drift

**Severity:** P1

**Description:** The design describes a flywheel where each session produces metadata updates (forge-mode.md lines 168-178), but there is no mechanism to detect when session N's updates cause a regression in a scenario that session M previously validated. The contraindications design (lens-contraindications.md) integrates with `lens_evolution.py` effectiveness scoring (lines 366-375) but this tracks user pushback in production, not pre-deployment validation. If session 15 adds a contraindication to lens A, and that contraindication would have incorrectly filtered lens A in the scenario from session 3, no alarm fires.

**Failure scenario:** Over 20 sessions, contraindications accumulate. Session 20 adds a contraindication that happens to match the distinguishing features from session 5. The validated scenario from session 5 now produces the wrong result, but nobody knows because there is no regression suite.

**Recommendation:** The stress test log schema (recommended in Finding 3) should be automatically replayed after every batch of metadata updates. If any previously-passing scenario now fails -- a lens that was selected is now filtered, or a lens that was filtered is now selected -- flag the regression before the update reaches production.

### Finding 9: Anti-Sycophancy Is Aspirational, Not Structural

**Severity:** P2

**Description:** Design Principle 4 (forge-mode.md lines 193-194) states: "The agent's job is to find problems, not validate solutions. If a lens contraindication the user proposes would catch legitimate applications, the agent pushes back." This is a prompt-level instruction with no structural enforcement. The agent is an LLM following instructions. When the builder (mk) proposes a rule with conviction, the asymmetry of the conversation -- mk is the product owner, the agent is the tool -- creates systematic pressure toward agreement. PHILOSOPHY.md Principle 2 ("Preserve cognitive struggle") applies here: if the agent doesn't genuinely challenge the builder's proposals, the cognitive struggle that makes Forge Mode valuable is lost.

The risk is not dramatic (the agent "goes rogue") but subtle: over 50 sessions, the lens library gradually encodes mk's personal preferences as objective contraindications. Lenses mk finds less intuitive accumulate more contraindications. Lenses mk prefers get fewer. The library narrows toward one person's cognitive style.

**Recommendation:** Add a structural anti-sycophancy mechanism: for every proposed contraindication, the agent must generate at least one "devil's advocate scenario" where the contraindication would incorrectly filter the lens. This is not a prompt instruction but a required output field in the Forge session protocol. The builder must explicitly dismiss the devil's advocate scenario (with reasoning) before the contraindication is staged.

---

## fd-simulation-profile-dynamics

### Finding 10: Profile Sim Describes Static Snapshots, Not Temporal Sequences

**Severity:** P1

**Description:** The Profile Sim example (forge-mode.md lines 88-112) shows the builder requesting a synthetic profile ("analytical and decisive in work conversations but emotional and indecisive in relationship conversations") and the agent describing what the profile looks like "after 10 sessions." But the simulation jumps directly to the end state. It does not generate the 10-session conversation sequence that would produce that profile. The interesting edge cases live in the sequence: at what point does the entity "emotionally-driven, seeks validation" transition from speculative to emerging? What happens if session 4 contradicts session 2? Does the profile architecture correctly handle the evidence threshold crossing?

The design says "Auraken generates a sequence of conversations that would produce that profile" (line 82) but the example shows a static end-state description, not a sequence. The profile architecture (per PRD.md lines 120-122) includes Symptomatic/Transitional/Constitutional depth classification and epistemic status progression (PHILOSOPHY.md Principle 12: speculative -> emerging -> established -> confirmed). These are inherently temporal properties. A simulation that does not generate the temporal sequence cannot test them.

**Failure scenario:** Profile Sim validates that the end-state profile looks correct, but the path to that end state contains a premature assertion bug: the entity "emotionally-driven" reaches "established" status after only 2 conversations because the evidence threshold was set too low. This bug is invisible in a static snapshot because the end state (after 10 sessions) would have enough evidence either way.

**Recommendation:** The Profile Sim flow should require generating the conversation sequence step-by-step, with the agent and builder examining the profile state after each simulated session. The output artifact should be a timeline: `[{session: 1, entities_added: [...], entities_updated: [...], threshold_crossings: [...]}]`. This is the only way to surface temporal edge cases.

### Finding 11: No Parameterization on Profile Architecture Dimensions

**Severity:** P2

**Description:** Profile Sim scenarios are specified in natural language ("analytical and decisive in work conversations" -- forge-mode.md line 90) rather than parameterized on the profile architecture's own dimensions: epistemic status thresholds, context scope boundaries, decay half-lives, evidence accumulation rates. This means Profile Sim cannot systematically sweep the parameter space. The builder generates scenarios that feel interesting, but the scenarios cluster around human-salient patterns (domain-switching, contradictions) and miss architecturally-salient edge cases (what happens when decay half-life is 14 days and sessions are 15 days apart? what happens when evidence threshold is 3 and the user provides exactly 2 observations then contradicts?).

**Recommendation:** Add a parameterized scenario generator that accepts profile architecture parameters directly: `{epistemic_threshold: 3, decay_halflife_days: 14, session_gap_days: [1, 1, 15, 1], contradiction_at_session: 4}`. This complements natural-language scenarios by ensuring architectural edge cases get tested even when the builder does not think of them.

### Finding 12: No Distinction Between Bugs and Design Gaps in Simulation Output

**Severity:** P2

**Description:** The Profile Sim output artifacts (forge-mode.md lines 114-117) list "Profile architecture rule refinements" and "Edge case scenarios for automated testing" but do not distinguish between two fundamentally different failure types: (a) the profile architecture mishandles a valid scenario (bug -- the code does not match the spec), and (b) the profile architecture cannot represent a real user pattern (design gap -- the spec is incomplete). These require different responses: bugs need code fixes; design gaps need architecture discussion.

The Profile Sim example (lines 99-112) shows both types interleaved: the synthesis layer compression problem is a design gap (the spec does not address domain-scoped synthesis), while the "does one contradicting observation flip the entity?" question is a threshold calibration bug. But the design does not distinguish them.

**Recommendation:** Add a classification field to Profile Sim output artifacts: `{type: "bug" | "design_gap", component: "entity_extraction" | "synthesis" | "decay" | ..., description: ..., proposed_response: ...}`. This ensures bugs go to the code backlog and design gaps go to design discussion, preventing design gaps from being silently treated as bugs (patched with heuristics rather than properly designed).

---

## fd-ontology-lens-metadata

### Finding 13: Distinguishing Features Are Unanchored From Their Near-Miss Context

**Severity:** P1

**Description:** The `distinguishing_features` field (lens-contraindications.md lines 31-34) is a flat `list[str]` with no reference to which `near_miss_lenses` entry each feature discriminates against. The sunk-cost lens example has three distinguishing features (lines 213-217) and two near-miss lenses (lines 219-220: `lens_explore_vs_exploit`, `lens_values_conflict`). But there is no way to know which feature distinguishes sunk-cost from values-conflict versus which distinguishes it from explore-vs-exploit. The verify step in the OODARC Decide flow (lens-contraindications.md lines 119-125) checks "whether the distinguishing features are present" but cannot weight them correctly because it does not know which contrast each feature serves.

At 291 lenses, the LLM verification call would receive a bag of distinguishing features with no structural indication of which near-miss they guard against. For lenses with 3+ near-misses, the verification becomes guesswork: which features matter for which contrast?

This finding converges with Finding 4 from the cognitive science agent -- the same structural gap identified from different disciplinary perspectives.

**Recommendation:** Restructure `distinguishing_features` into a dict keyed by near-miss lens ID: `distinguishing_features: {lens_values_conflict: ["Past investment cited as primary reason..."], lens_explore_vs_exploit: ["Historical pattern of allocation..."]}`. This preserves the diagnostic context that Forge Mode sessions generate and enables targeted verification per near-miss pair.

### Finding 14: Near-Miss Directionality Is Undefined

**Severity:** P2

**Description:** The contraindications design (lens-contraindications.md lines 95-96) explicitly notes that `near_miss` relationships are asymmetric: "A is a near-miss for B means when B is the correct lens, A is commonly misapplied." But the schema (`near_miss_lenses: list[str]`) does not encode direction. The sunk-cost lens lists `lens_values_conflict` as a near-miss (line 219), but this could mean either: (a) when sunk-cost is correct, values-conflict is commonly misapplied, or (b) when values-conflict is correct, sunk-cost is commonly misapplied. The lens-contraindications design says "when B is the correct lens, A is commonly misapplied" (line 382) implying that listing B in A's `near_miss_lenses` means "when A is the correct lens, B gets misapplied" -- but the design never states this definitively.

At scale, without explicit directionality, Forge Mode sessions will produce inconsistent near-miss graphs. If session 5 adds `lens_values_conflict` to sunk-cost's near-misses and session 12 adds `lens_sunk_cost` to values-conflict's near-misses with different assumptions about direction, the verification step cannot reason correctly about the relationships.

**Recommendation:** Add a convention to the schema (or the Forge Mode session protocol) that defines: "near_miss_lenses on lens A lists lenses that are commonly confused FOR A -- i.e., A is selected when these lenses are actually correct." Then add a consistency check to the artifact pipeline: if A lists B as a near-miss, B should list A as a near-miss (the confusion is typically bidirectional, even if the harm is asymmetric). Forge Mode sessions should surface unreciprocated near-miss entries for review.

### Finding 15: Contraindications Cannot Express Conditional Dependencies

**Severity:** P2

**Description:** The contraindication schema stores natural-language strings (lens-contraindications.md lines 39-41). Some contraindication examples are inherently conditional: "User is in early-stage exploration where persistence through difficulty IS the correct strategy" (sunk-cost contraindication, line 69). But "early-stage exploration" is itself a judgment that depends on profile data (how long has the user been working on this? is there an entity for "exploration phase"?). The verify/check LLM call (lens-contraindications.md lines 141-154) must interpret this natural language and infer the conditional dependency. At 291 lenses with 3+ contraindications each, the verify call receives ~900 natural-language conditions with no structured indication of which profile entities or context signals each condition depends on.

This creates a fidelity gap between what Forge Mode sessions produce (richly contextual reasoning about when a contraindication applies) and what the schema stores (a flat string that has lost the conditional structure).

**Recommendation:** Add optional structured annotations to contraindication entries: `{text: "User is in early-stage exploration...", depends_on: ["profile.entity.exploration_phase", "profile.entity.project_duration < 6mo"], severity: "hard"}`. The LLM verify call can use these as signals, and the structured dependencies enable automated analysis of which contraindications fire for which profile states. Keep the natural-language text as the primary content; the structured annotations are supplementary, not replacing it.

### Finding 16: Failure Signatures Require LLM Interpretation for Automated Detection

**Severity:** P3

**Description:** The design proposes integrating `failure_signatures` with `lens_evolution.py` effectiveness scoring (lens-contraindications.md lines 371-375), cross-referencing pushback messages against failure signatures to produce `pushed_back_contraindicated` events. But failure signatures are natural-language narratives: "User pushes back with 'but this actually matters to me'" (line 83). The `classify_engagement()` function would need to do semantic matching between arbitrary user messages and these narrative descriptions. This is tractable with an LLM call but not with simple keyword matching, and the design does not specify which approach `classify_engagement()` should use.

This is a P3 because the existing `pushed_back` event type already captures the critical signal. The `pushed_back_contraindicated` refinement adds precision but is not required for safety.

**Recommendation:** Specify that `classify_engagement()` uses the same lightweight Haiku call pattern as the contraindication check itself: pass the user's pushback message + the lens's failure signatures, get back a boolean match + confidence score. This keeps the approach consistent with the rest of the contraindication architecture and avoids building a separate NLU pipeline.

---

## Cross-Agent Convergence

Two findings independently converged from different disciplinary perspectives:

1. **Unanchored distinguishing features** (Finding 4 + Finding 13): The cognitive science agent identified this as a violation of Winston's near-miss learning theory (features must be contrastive pairs, not standalone properties). The ontology agent identified the same gap as a schema expressiveness problem (flat lists cannot encode which near-miss a feature discriminates against). Same structural problem, same recommended fix (anchor features to specific near-miss contrasts), arrived at from learning theory and knowledge engineering respectively.

2. **Missing regression detection in the self-improvement loop** (Finding 3 + Finding 8): The adversarial testing agent identified that stress test logs lack the structure needed for automated regression replay. The alignment agent identified that cumulative metadata drift across sessions has no detection mechanism. Together, these form a single P1 gap: the Forge Mode flywheel can silently degrade previously-validated behavior because (a) past scenarios are not stored in replayable form and (b) no automated check runs past scenarios against updated metadata.
