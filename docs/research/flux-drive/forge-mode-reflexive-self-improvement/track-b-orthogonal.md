---
artifact_type: flux-drive-findings
track: orthogonal
target: apps/Auraken/docs/designs/forge-mode.md
date: 2026-03-31
agents: [fd-aviation-safety-crm, fd-clinical-case-reasoning, fd-feedback-loop-integrity, fd-retrospective-facilitation]
---

# Flux-Drive Findings: Forge Mode — Track B (Orthogonal)

Target: `apps/Auraken/docs/designs/forge-mode.md`
Context: `apps/Auraken/docs/designs/lens-contraindications.md`

---

## fd-aviation-safety-crm

### Finding 1: Scenario Fidelity Traps — Training the Pairing, Not the Skill

**Severity:** P2

**Description:** Aviation CRM simulator research (Salas et al., 2006) discovered that high-fidelity scenarios improve performance on rehearsed scenarios but can *reduce* transfer to novel situations. Forge Mode's Stress Test (Dojo) sub-mode generates specific lens-vs-lens pairings (e.g., sunk-cost vs. values-conflict in the example at lines 47-69 of forge-mode.md). Each resolved scenario produces a concrete distinguishing question and near-miss metadata entry. The risk is that this trains the system to recognize specific lens pairings rather than building the underlying *recognition skill* — the ability to notice when any surface match is misleading, including combinations never encountered in a Forge session. Aviation solved this with "scenario variation sets": same setup, one variable changed each time, mapping the boundary rather than the point.

**Agent:** fd-aviation-safety-crm

**Recommendation:** Add a "boundary mapping" protocol to Dojo: after resolving a scenario, systematically vary one dimension (user emotional tone, domain context, time horizon) to generate 2-3 variants that test whether the distinguishing question generalizes. Store the variant set as a unit in the stress test log, not individual scenarios. This builds transfer rather than memorization.

---

### Finding 2: Unrecognized Near-Miss Blind Spot

**Severity:** P1

**Description:** The most dangerous aviation near-misses are the ones nobody classified as near-misses at the time (ASRS data, Reason 1997). The `near_miss_lenses` field in the contraindication schema (lens-contraindications.md, lines 46-50) captures *recognized* confusions — lenses that human reviewers already know are confusable. But Forge Mode has no mechanism for surfacing *unrecognized* near-misses: lens pairs that nobody has thought to test together because the surface similarity is non-obvious. Aviation addresses this with LOSA (Line Operations Safety Audit) — structured observation of routine operations to find threat categories that were absent from training scenarios. The equivalent for Auraken would be analyzing real conversation logs where the selected lens received pushback or was ignored, and checking whether an untested near-miss relationship explains the failure.

**Agent:** fd-aviation-safety-crm

**Recommendation:** Add a fourth source to the Forge Mode flywheel: real-conversation audit. Periodically sample conversations where `pushed_back` events occurred (from `lens_evolution.py`), and check whether the pushback lens and the *actually-correct* lens (inferred from what the user did next) have a near-miss relationship in the schema. If not, that is an unrecognized near-miss — surface it as a Forge session candidate.

---

### Finding 3: Debrief Structure Deficit

**Severity:** P2

**Description:** CRM research (Tannenbaum & Cerasoli, 2013) shows unstructured debriefs produce narrative satisfaction but structured debriefs (what happened / why / what changes / how we verify the change worked) produce behavioral change. Forge Mode's design principles (lines 186-195) state "Artifacts are the output, not the conversation" but the sub-mode flows (Dojo lines 34-75, Lab lines 78-117, Meta lines 119-165) describe open conversational flows with artifact production as an outcome, not a structural forcing function. There is no specified debrief template, no required fields per session, and no mechanism to distinguish a session that produced genuine metadata improvements from one that produced satisfying conversation.

**Agent:** fd-aviation-safety-crm

**Recommendation:** Define a minimum viable debrief record per Forge session: (1) capability tested, (2) scenario description, (3) failure mode identified or null, (4) metadata diff produced, (5) regression test candidate (yes/no + description). Refuse to mark a Forge session as complete until the record is populated. This is the CRM "CFIT debrief card" equivalent — not bureaucracy, but a structural forcing function for artifact extraction.

---

## fd-clinical-case-reasoning

### Finding 4: Contraindication Accumulation as Over-Testing Analog

**Severity:** P1

**Description:** Clinical reasoning education has a well-documented failure mode: teaching too many red flags produces over-testing, where clinicians order unnecessary diagnostics to rule out unlikely conditions (Kassirer, 1989). The lens-contraindications.md design adds a verification LLM call after initial lens selection (lines 117-135: Match -> Verify -> Check). As Forge Mode populates contraindications across 291 lenses (lens-contraindications.md line 407), every lens selection will trigger verification against an expanding list of exclusion scenarios. The design acknowledges this at open question 2 (lines 431-432: "Should contraindications have confidence scores?") but defers it. Without confidence weighting, the system treats "never apply sunk-cost when values are the issue" (absolute) identically to "SBI in low-trust environments sometimes still works" (probabilistic). This is the diagnostic equivalent of treating a pathognomonic sign and a soft sign with equal weight.

**Agent:** fd-clinical-case-reasoning

**Recommendation:** Do not defer contraindication confidence to post-v1. Add a binary field: `strength: "absolute" | "contextual"`. Absolute contraindications (matching any one is disqualifying) are checked first and cheaply. Contextual contraindications require the LLM verification call to weigh against the overall situation. This mirrors clinical reasoning's distinction between hard contraindications (allergy to a drug class) and relative contraindications (mild renal impairment with a nephrotoxic drug — depends on alternatives).

---

### Finding 5: Missing Base Rate Awareness in Stress Testing

**Severity:** P2

**Description:** Clinical training disproportionately emphasizes rare-but-dramatic conditions (zebras) while most diagnostic errors occur with common conditions (horses) presented atypically. Forge Mode's Dojo sub-mode (lines 30-75) is designed to generate challenging scenarios — "a problem where multiple lenses match, where mode transition timing is ambiguous, where profile data is contradictory." These are zebras by construction. The most common lens selection errors in real conversations are likely mundane: the correct lens is obvious but the selector picks a more "interesting" adjacent lens, or the user's framing triggers a lens that matches their language but not their actual situation. Forge Mode has no mechanism to prioritize stress-testing the common-error patterns over the exotic ones.

**Agent:** fd-clinical-case-reasoning

**Recommendation:** Before each Forge session, query `lens_evolution.py` effectiveness data to identify the lenses with the highest `pushed_back` rates in real conversations. These are the "common presenting complaints" — target Dojo scenarios at these first, not at synthetic edge cases. Reserve exotic multi-lens-match scenarios for after the high-frequency failure modes are addressed.

---

### Finding 6: Illness Script Equivalents Missing from Artifact Schema

**Severity:** P2

**Description:** The most durable diagnostic improvement in clinical education comes from building *illness scripts* — abstract templates that capture the typical presentation, pathophysiology, and discriminating features of a condition — rather than memorizing specific case presentations. Forge Mode's artifact outputs (lines 72-75, 114-117, 161-165) produce case-specific items: updated lens JSON for a particular scenario, edge case scenarios for automated testing, specific product decision reframes. What is missing is the equivalent of an illness script: a transferable *lens selection heuristic* that captures the general pattern ("when the user's language references past investment but their energy is about identity, check for values-conflict before sunk-cost"). These heuristics would sit between the individual contraindication entries and the general OODARC Decide logic.

**Agent:** fd-clinical-case-reasoning

**Recommendation:** Add a "selection heuristic" artifact type to Forge Mode output. After accumulating 3+ contraindication entries for the same near-miss pair, synthesize them into a single heuristic rule that captures the general discriminating pattern. Store these heuristics in a separate file (e.g., `lens_selection_heuristics.yaml`) that the selector prompt can reference directly, reducing dependence on exhaustive contraindication enumeration.

---

## fd-feedback-loop-integrity

### Finding 7: No Gain-Limiting Mechanism in the Flywheel

**Severity:** P1

**Description:** The Forge Mode flywheel (lines 168-178) is a closed feedback loop: stress test -> update metadata -> validate -> apply to decisions -> find new edge cases -> stress test. In control systems engineering, a closed loop without gain management will either converge, oscillate, or diverge depending on the loop gain. Each Forge session adds contraindications, distinguishing features, and near-miss relationships with equal weight regardless of how mature the system is. Session 1 adding a sunk-cost/values-conflict contraindication is high-value. Session 50 adding yet another edge-case contraindication to the same pair has diminishing returns but identical system impact. Without damping, the metadata set grows linearly with sessions, the verification LLM call grows in token cost, and the false-positive rate on contraindication matches increases monotonically. There is no convergence criterion — no definition of "this lens pair is sufficiently characterized."

**Agent:** fd-feedback-loop-integrity

**Recommendation:** Introduce a coverage saturation metric per lens and per near-miss pair. Track the number of Forge sessions that touched each lens and the marginal metadata additions per session. When a lens's last 3 sessions each produced fewer than 1 new metadata entry, mark it as "saturated" and deprioritize it in Forge session targeting. This is the control-theoretic equivalent of adaptive gain reduction — high gain when far from the target, decreasing gain as the system converges.

---

### Finding 8: Observer Effect in Meta Mode

**Severity:** P2

**Description:** Meta Mode (lines 119-165) has Auraken apply its own lenses to its own product decisions. This creates a self-referential measurement where the observer and the observed are the same system. In cybernetics, this is the observer effect: the act of measurement distorts the thing being measured. Concretely, when Auraken applies the pace-layers lens to its own launch sequencing question (example at lines 130-159), the quality of the reframe is simultaneously (a) evidence of whether the pace-layers lens works well, and (b) the basis for a real product decision. If the reframe is good, it validates the lens *and* changes the product direction. If the reframe is poor, it is unclear whether the lens is bad, the application was bad, or the question was poorly framed. There is no separation between the measurement instrument and the thing being measured.

**Agent:** fd-feedback-loop-integrity

**Recommendation:** Tag Meta Mode outputs with an explicit confidence discount: "self-referential — validate externally before acting." For product decisions that emerge from Meta Mode, require at least one external validation step (user reflection after 24 hours, or peer review via `/interpeer`) before committing the decision to the roadmap. This is the control systems practice of never closing the loop through the same sensor that drives the actuator.

---

### Finding 9: Goodhart's Law Risk in Stress Test Pass Rate

**Severity:** P2

**Description:** If Forge Mode implicitly optimizes for stress test pass rate (all known near-misses correctly handled in Dojo scenarios), this metric becomes the target rather than the measure. The system would optimize for handling generated scenarios — which are drawn from recognized near-miss pairs — rather than for genuine lens selection quality in real conversations where the confusing patterns are unrecognized. This is Goodhart's Law: "when a measure becomes a target, it ceases to be a good measure." The flywheel diagram (lines 168-178) implies that the cycle is self-validating ("Profile Sim validates the updates"), but validation against synthetic scenarios generated by the same system that produced the metadata is not independent validation.

**Agent:** fd-feedback-loop-integrity

**Recommendation:** Separate the validation signal from the generation signal. Profile Sim (Lab) should not validate metadata produced by Dojo using Dojo-style scenarios. Instead, the primary validation metric should be the `pushed_back` rate in real conversations from `lens_evolution.py`. If Forge sessions are improving the system, the real-conversation pushback rate should decline over time. Track this as the ground-truth metric; Dojo pass rate is a leading indicator only.

---

## fd-retrospective-facilitation

### Finding 10: Insight Addiction Risk in Conversational Format

**Severity:** P1

**Description:** Coaching psychology (Grant, 2012) distinguishes between insight (understanding a pattern) and behavior change (acting differently). The conversational format of Forge Mode — particularly the example sessions at lines 47-69, 86-112, and 130-159 — reads as intellectually satisfying dialogue. The Dojo example ends with "I'll add that as a distinguishing question" (line 68), but the design has no mechanism to verify that the metadata was actually written, that it was written correctly, or that it changed the selector's behavior. Design Principle 2 (line 189) states "Artifacts are the output, not the conversation" but the sub-mode flows do not enforce this — a Forge session could produce a rich conversation and zero committed artifacts, and the system would not flag this as a failure. In facilitation practice, this is the "insight addiction" pattern: reflection feels productive but produces no durable behavioral change.

**Agent:** fd-retrospective-facilitation

**Recommendation:** Add an artifact gate to Forge Mode exit. When the user types `/exit` or the session ends naturally, the agent must enumerate the artifacts produced (metadata diffs, rule changes, brainstorm docs) and their commit status. If zero artifacts were produced, the agent should surface this explicitly: "This session produced conversation but no committed artifacts. Should we extract findings before closing?" This is the retrospective facilitator's "action item check" — no retrospective closes without at least one concrete, assigned, time-bound action.

---

### Finding 11: No Diminishing Returns Tracking

**Severity:** P2

**Description:** Deliberate practice research (Ericsson, 1993) shows that reflection on the same skill area produces diminishing returns after initial improvement. Forge Mode has no mechanism to track which capabilities have been stress-tested, how many sessions have targeted each, or what the yield-per-session trend looks like. Without this, the builder will naturally gravitate toward capabilities they find intellectually interesting (lens selection edge cases) while neglecting capabilities that are less interesting but more impactful (profile entity extraction thresholds, depth classification boundaries). The retrospective facilitation equivalent is "topic rotation fatigue" — teams that discuss the same theme every sprint stop generating new insights after the third discussion but continue holding the retrospective.

**Agent:** fd-retrospective-facilitation

**Recommendation:** Maintain a Forge session log with structured fields: date, sub-mode, capability targeted, artifacts produced, novelty score (self-rated: "mostly new findings" / "mostly refinements" / "no new findings"). Surface the log at session start: "Lens selection has been stress-tested in 8 sessions with declining novelty. Profile entity extraction has been tested in 0 sessions. Recommended target: profile entity extraction." This is the facilitator's "topic health dashboard."

---

### Finding 12: Performative Introspection — The Safe Edge Case Problem

**Severity:** P2

**Description:** In team retrospectives, groups sometimes perform the ritual of reflection without genuine vulnerability — discussing safe problems while avoiding the uncomfortable ones. Forge Mode's examples (lines 47-69, 86-112, 130-159) all involve technically interesting edge cases: lens selection ambiguity, entity temporal conflation, pace-layer sequencing. None of them test the genuinely uncomfortable questions: "Is the entire lens-based approach the right architecture?" "Do users actually want cognitive augmentation or do they want validation?" "Is the camera-not-engine principle limiting the product's value?" Forge Mode as described would be excellent at refining an approach that might be fundamentally wrong, because the sub-modes all assume the existing architecture is correct and test within its boundaries.

**Agent:** fd-retrospective-facilitation

**Recommendation:** Add a fourth Forge sub-mode or a periodic "red team" variant of Meta Mode where the explicit goal is to challenge a core assumption, not refine an existing capability. The entry prompt would be: "What is one assumption in PHILOSOPHY.md or VISION.md that, if wrong, would make the current architecture irrelevant?" This is the retrospective facilitator's "sacred cow" exercise — deliberately targeting the thing the team is least willing to question.

---

### Finding 13: Rumination Boundary Undefined

**Severity:** P3

**Description:** Clinical psychology distinguishes productive reflection (goal-directed, bounded, concludes with action items) from rumination (recursive, unbounded, produces anxiety rather than clarity). Forge Mode sessions have no time bounds, no scope constraints, and no escalation path for scenarios that resist resolution. The Dojo flow (lines 34-43) says "User specifies a capability to stress-test" but does not constrain the scope within that capability. A session targeting "lens selection" could recursively generate scenarios for hours, each one slightly more exotic than the last, without producing proportionally more valuable metadata. The design principle "Forge Mode is a conversation, not a test suite" (line 187) actively resists structural bounds, but unbounded conversational exploration is exactly the condition that produces rumination.

**Agent:** fd-retrospective-facilitation

**Recommendation:** Add soft session bounds: after 30 minutes or 5 scenarios (whichever comes first), the agent surfaces a checkpoint — "We have explored N scenarios and produced M artifacts. Continue, narrow scope, or close?" This is not a hard limit but a structural interruption that forces the builder to consciously choose continued exploration over session closure. Retrospective facilitators call this the "timeboxed divergence" pattern.
