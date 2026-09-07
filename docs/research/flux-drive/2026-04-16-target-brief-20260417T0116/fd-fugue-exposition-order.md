# fd-fugue-exposition-order — Findings

**Lens:** Bach-Kirnberger kapellmeister. Mechanism: a fugue exposition fails not when the subject is weak but when the ordering is rushed — answer enters before subject is fully heard, countersubject displaces subject's cadence, or exposition opens polyphonically so no listener extracts a memorable theme. Test: can the subject survive being stated alone, in one sentence, with no supporting architecture diagram?

## Findings Index

- P0 — README tagline is polyphonic at first statement (three claims in one sentence)
- P0 — Architecture table enters before the subject has been stated
- P1 — Tonal answer (Closed-Loop pipeline) is missing from public exposition
- P1 — Two-brand framing is a second voice entering in measure 2
- P2 — Trust-ladder (L0-L5) and authority-ladder (M0-M4) are simultaneous second and third voices
- P3 — Stretto opportunity missed: no single artifact compresses multiple claims into one visible moment

## Verdict

**Choose subject: "Every agent action produces replayable evidence, and the evidence calibrates the next action."** Choose tonal answer: `estimate-costs.sh` closed-loop pipeline. Strict exposition order: subject → answer → countersubject → inventory. Everything currently in the first 200 words that is not subject or answer is a countersubject collision and must be cut.

## Summary

The current Sylveste exposition opens with all voices simultaneously: tagline states three compound ideas at once ("build with agents" + "review phases matter more" + "every moment in the loop count"), architecture table enters before any subject has completed, two brand registers announce themselves in the same paragraph, and a 64-plugin inventory sits within scroll distance. The listener hears an orchestra tuning, not a subject.

A fugue does not fail because Bach wrote a weak subject. It fails when the bass enters before the soprano has completed the subject statement. Every listener after that moment is lost. Sylveste's subject is present in PHILOSOPHY.md — specifically claim #3 ("Every action produces evidence. Evidence earns authority. Authority is scoped and composed.") — but it is buried behind architecture, inventory, and register framing. It has never been heard alone.

The kapellmeister's single testable question: can the subject be stated in one sentence, under 12 words, and survive being heard without any chart, layer description, or pillar list? Currently no candidate in the public surface passes this test.

## Issues Found

### P0-1: Polyphonic tagline at first statement

- **File:** `README.md` (tagline, brief line 32)
- **Current text:** "A monorepo for building software with agents, where the review phases matter more than the building phases, and the point is not to remove humans from the loop but to make every moment in the loop count."
- **Failure scenario:** 42 words. Three claims: (a) agents build software, (b) review phases outweigh building phases, (c) humans-in-the-loop make moments count. A fugue subject must be monophonic — one idea, fully heard, before any answer voice enters. This tagline enters all three voices at measure one. The reader's attention has no anchor; they cannot repeat the subject to a colleague. The exposition has failed before the second sentence.
- **Smallest viable fix:** One sentence, under 12 words, one claim. Candidate: "Sylveste makes every agent action produce evidence that calibrates the next one." 12 words, one subject, survives being stated alone. Test the candidate: a reader who only reads this sentence can paraphrase it accurately; that is the fugue-subject criterion.

### P0-2: Architecture table enters before subject completes

- **File:** `README.md` architecture section (brief line 109 references it); also `docs/sylveste-vision.md`
- **Failure scenario:** The README arrives at "Three Layers, Six Pillars, Cross-Cutting Systems" within the first scroll. The reader's attention shifts to the table before any claim has been fully heard. This is the second voice (architecture) displacing the first voice (claim). The subject has not established itself — the listener cannot tell whether the architecture is in service of a claim, or whether there is a claim at all.
- **Smallest viable fix:** Remove the architecture table from the README's first 400 words. First section after tagline is one paragraph restating the subject and pointing to the tonal-answer artifact. Architecture appears in section 2 or later, after the subject has been heard, answered, and confirmed.

### P1-1: Tonal answer is missing from public exposition

- **File:** `README.md` generally; `estimate-costs.sh` location (per brief line 90, "existence proof: the `estimate-costs.sh` pipeline that reads interstat historical actuals and writes calibrated estimates back")
- **Failure scenario:** In a fugue exposition, the subject statement is followed by the answer: the same theme restated in the dominant key, which confirms to the listener that they heard the subject correctly. Sylveste's subject (evidence → authority → calibration) has a natural answer: the `estimate-costs.sh` pipeline, which is the operational restatement in a different key (cost calibration rather than authority calibration). But this artifact is not linked next to its governing claim in any public surface. The exposition has no answer entry; the listener cannot confirm they heard the subject.
- **Smallest viable fix:** Immediately after the tagline subject, add one paragraph: "To see the subject operational: `estimate-costs.sh` reads 785 sessions of cost actuals from interstat, writes calibrated per-agent×model estimates back to fleet-registry.yaml, and those estimates become the defaults for the next dispatch. One closed loop, replayable, with a public diff showing calibration change over time." Link directly to the script and a sample output file.

### P1-2: Two-brand framing enters in measure 2

- **File:** `MISSION.md` (brief lines 64-69)
- **Failure scenario:** Before the subject has been heard, MISSION.md introduces a register theory: Sylveste (SF) + Garden Salon (organic) + Meadowsyn (bridge). This is three additional voices entering in the second measure of the exposition. The reader is now tracking five voices: subject candidate, architecture, brand SF-register, brand organic-register, bridge brand. None of them have completed a statement. The exposition has collapsed into cacophony.
- **Smallest viable fix:** Delete the two-brand framing from MISSION.md for now. MISSION.md contains one paragraph stating the subject. Period. The brand-register split can return later, in a separate doc at a separate exposition-time, after the subject is established.

## Improvements

### P2-1: Trust-ladder and authority-ladder as simultaneous voices

- **File:** PHILOSOPHY.md claims #6 (trust ladder L0-L5) and #7 (authority ladder M0-M4)
- **Observation:** Both are ladder claims. Both are gradation claims. To a listener, they arrive as the same voice stated twice — or as two voices that collide because they occupy the same frequency range. The distinction (trust vs authority, human delegation vs subsystem maturity) is real internally, but in exposition order they step on each other's statements.
- **Fix:** In public surface, surface only one ladder. Candidate: authority ladder (M0-M4), because it is the ladder the Closed-Loop pipeline actually rides on. Trust ladder can appear later in a separate doc focused on human-agent delegation.

### P3-1: No stretto moment in current exposition

- **Observation:** A stretto is the fugue's late-exposition move where subject entries overlap, compressing the claim-ladder into a single visible moment of inevitability. Sylveste has the raw material for a stretto — a single artifact that simultaneously demonstrates claims #3 (evidence→authority), #5 (wired or it doesn't exist), and #7 (graduated authority M0-M4): namely, the `estimate-costs.sh` pipeline's behavior when it transitions a subsystem from M0 (hardcoded defaults) to M2 (calibrated from actuals). But no public artifact shows this transition as a moment.
- **Fix:** Produce one screenshot or one diff showing a subsystem's `est_billing` value moving from `defaults[type]` to `interstat (N runs)` after the Nth session. That single image compresses three claims into one visible event. Label it "a subsystem crossing M2."

## Deliverable

### The subject (under 12 words, survives being stated alone)

> **"Every agent action produces evidence, and the evidence calibrates the next action."**

Test: a reader can repeat it from memory. It makes a testable claim. It does not require an architecture diagram. It survives monophonic statement. (11 words.)

### The tonal answer (operational restatement in a different key)

> **`estimate-costs.sh`** — reads 785 sessions of cost actuals from interstat, writes calibrated estimates to fleet-registry.yaml, and those estimates become the defaults for the next dispatch. Same subject (evidence → calibration), different key (cost instead of authority).

### Countersubject collisions to cut from the first 200 words

1. Architecture table (three layers / six pillars) — currently enters before subject
2. Two-brand / three-brand register framing — second voice in measure 2
3. 64-plugin Interverse enumeration — fifth voice
4. Trust ladder L0-L5 — redundant voice with authority ladder M0-M4
5. "Every `ic` invocation opens the database..." (technical detail about kernel behavior) — belongs in section 3, not section 1

### Strict exposition order for the public-facing surface

1. **Measure 1 (subject, monophonic):** Tagline stating the subject in ≤12 words.
2. **Measure 2 (answer, same theme in the dominant):** `estimate-costs.sh` paragraph with direct link to artifact.
3. **Measure 3 (countersubject):** One adjacent claim that provides contrast without displacing — candidate: "Wired or it doesn't exist."
4. **Measure 4+ (further entries, one at a time):** Clavain → Interspect → intercore, in that order, each one paragraph, each restating the subject in its own voice.
5. **Later (inventory, development section):** Architecture, layers, pillars, plugins. Only after the subject is established and the listener is tracking the theme confidently.

### Stretto candidate (for a later exposition-time)

Produce one published screenshot showing a subsystem's cost estimate source transitioning from `default` to `interstat (N runs)` after its Nth session. This is the moment where three claims (evidence, wiring, authority) overlap in a single visible frame. That image becomes the single most citable Sylveste artifact.

<!-- flux-drive:complete -->
