---
artifact_type: flux-drive-findings
track: distant
target: apps/Auraken/docs/designs/forge-mode.md
date: 2026-03-31
agents: [fd-kintsugi-fracture-taxonomy, fd-persian-carpet-weaving-quality, fd-astronomical-clock-calibration, fd-chinese-tea-ceremony-discrimination]
---

# Forge Mode — Track C (Distant) Findings

Structural isomorphisms from four distant knowledge domains applied to the Forge Mode design (`apps/Auraken/docs/designs/forge-mode.md`), with `apps/Auraken/docs/designs/lens-contraindications.md` as supporting context.

---

## Agent 1: fd-kintsugi-fracture-taxonomy

### Finding 1.1 — Force Vector Fields on Near-Miss Relationships

**Source mechanism:** In kintsugi, two cracks can look identical on the surface (same star-shaped pattern) but originate from opposite force vectors — impact vs thermal shock. The repair strategy is determined by the *cause*, not the *appearance*. A master tests fracture type by applying gentle pressure at specific points; the response reveals the internal stress pattern.

**Mapping to Forge Mode:** The `near_miss_lenses` field in the contraindication schema (lens-contraindications.md, lines 46-52) records *which* lenses are near-misses but not *why* they are near-misses — the force vector that distinguishes them. The sunk-cost / values-conflict example in the stress test (forge-mode.md, lines 49-69) shows a distinguishing *question* ("If you'd only spent 3 months..."), but this question is not formalized in the schema. The `distinguishing_features` field captures static indicators, not dynamic probes.

**Verdict:** Concrete improvement. Add a `distinguishing_probes` field to the lens schema — active questions (not passive features) that test the causal mechanism behind the surface pattern. Each near-miss relationship should carry at least one probe that differentiates the pair, analogous to the kintsugi master's pressure test. This is distinct from `distinguishing_features` (what you observe) and closer to "what you do to resolve ambiguity."

### Finding 1.2 — Irreversibility Gates Before Metadata Commits

**Source mechanism:** In kintsugi, lacquer application is irreversible. Once you commit to a repair strategy and apply lacquer, reversing the decision destroys the piece further. Masters therefore spend disproportionate time in diagnosis relative to repair.

**Mapping to Forge Mode:** The design's artifact pipeline (forge-mode.md, lines 72-74, 113-116, 161-165) specifies that lens metadata updates are "staged for review" and profile rule updates "require explicit approval." But stress test logs are simply "timestamped scenarios with resolutions, stored as regression test candidates" — there is no staging or approval gate on the *interpretation* of a stress test result. If a Forge session misdiagnoses a failure (attributes it to missing contraindication when the real issue is selector algorithm), the resulting metadata change hardens the misdiagnosis into the system.

**Verdict:** Concrete improvement. Add a `diagnosis_confidence` field to stress test logs. When a stress test reveals a failure, the log should record the hypothesized root cause (lens metadata vs selection algorithm vs profile context vs scenario framing) and confidence level. Metadata changes derived from low-confidence diagnoses should be flagged for additional validation in a subsequent session, not immediately committed.

### Finding 1.3 — Revision History as First-Class Diagnostic Data

**Source mechanism:** Repaired ceramics carry the history of both original creation and every subsequent repair. Each break-and-repair cycle adds layers of diagnostic complexity. A piece repaired three times is harder to diagnose than one repaired once, because the repair layers interact with each other.

**Mapping to Forge Mode:** Profile Sim (forge-mode.md, lines 76-116) simulates entity evolution over sessions but does not model what happens when an entity has been *revised* multiple times. The epistemic threshold of "3+ contradicting observations" (line 109) treats all contradictions equally regardless of the entity's revision history. An entity that has flip-flopped between "established" and "emerging" three times is qualitatively different from one that has never been revised — the instability itself is diagnostic information.

**Verdict:** Opens a new question. Should entity revision history be surfaced as a first-class signal in Profile Sim? An entity with high revision count might indicate a genuine domain-dependent split (the analytical/emotional example) rather than noisy data, and the system should treat oscillation differently from monotonic degradation.

### Finding 1.4 — Confirmatory vs Discriminatory Probes

**Source mechanism:** A kintsugi apprentice's common error is using probes that confirm the suspected fracture type rather than probes that could *refute* it. The master insists on probes that test the alternative hypothesis.

**Mapping to Forge Mode:** The stress test example (forge-mode.md, lines 45-69) shows a distinguishing question — "If you'd only spent 3 months, would you still want to stop?" — that *discriminates* between sunk cost and values conflict. But there is no design principle requiring that distinguishing questions be *falsifiable* with respect to the current hypothesis. The stress test flow (lines 36-43) says "generate a synthetic scenario designed to challenge that capability" but does not specify that the scenario should be designed to *refute* the expected classification, not confirm it.

**Verdict:** Concrete improvement. Add to Design Principle 3 (forge-mode.md, line 189) or as a new principle: "Stress test scenarios should be designed to falsify the expected classification, not confirm it. A scenario that confirms what you already believe tests nothing."

---

## Agent 2: fd-persian-carpet-weaving-quality

### Finding 2.1 — Error Pattern Analysis Across Sessions

**Source mechanism:** In carpet authentication, the *pattern* of mistakes reveals the weaver's skill level more reliably than any individual mistake. A novice makes random errors distributed uniformly. A journeyman's errors cluster at pattern transitions. A master's "errors" are deliberately placed variations. The authenticator reads the error signature, not the error count.

**Mapping to Forge Mode:** The flywheel (forge-mode.md, lines 168-178) describes a cycle where stress tests find edge cases, which update metadata, which are validated by Profile Sim. But there is no mechanism for analyzing the *pattern* of failures across multiple Forge sessions. Individual sessions produce individual artifacts, but the meta-pattern — "we keep finding lens selection failures at the boundary between emotional-processing lenses and cognitive-restructuring lenses" — is not captured or surfaced. The existing `lens_evolution.py` tracks engagement events but not failure *clusters*.

**Verdict:** Concrete improvement. Introduce a periodic "error signature review" as a Forge Mode ritual. After every N stress test sessions, analyze the distribution of failures: Are they random (system is generally weak), clustered (specific boundary is poorly defined), or absent (stress tests are too easy)? This meta-analysis should feed into stress test generation priorities for the next cycle.

### Finding 2.2 — Deliberate Ambiguity in Stress Test Design

**Source mechanism:** Master weavers introduce controlled imperfections to distinguish handmade from machine-woven carpets. Paradoxically, a perfectly uniform carpet is less valuable because it signals mechanical reproduction. The skill is knowing *where* to introduce variation and *how much*.

**Mapping to Forge Mode:** The stress test flow (forge-mode.md, lines 35-43) generates scenarios "designed to challenge that capability" — but all example scenarios have clean resolutions. The sunk-cost example (lines 45-69) ends with a clear binary: if yes, values conflict; if no, sunk cost. Real conversations are messier. A stress test suite composed entirely of cleanly resolvable scenarios trains the system to handle only clean cases. It needs scenarios that are *genuinely ambiguous* — where the correct answer is "apply both lenses at different scales" or "this doesn't map to any existing lens."

**Verdict:** Concrete improvement. Add a stress test category: "irreducible ambiguity" — scenarios deliberately designed to have no clean single-lens answer. The expected output is not a correct classification but a well-reasoned acknowledgment of ambiguity, potentially triggering a new lens or a `contrasts` edge rather than a `near_miss` edge. This category tests the system's ability to recognize the limits of its own taxonomy.

### Finding 2.3 — Cumulative Drift Detection for Metadata Changes

**Source mechanism:** Experienced weavers can detect when a pattern is subtly drifting from its template. Each individual row looks correct, but the cumulative effect — a gradual shift in color balance, a slow migration of a motif's position — produces a carpet that is subtly wrong despite every local decision being reasonable.

**Mapping to Forge Mode:** The design has no mechanism for detecting cumulative drift in lens metadata. Each Forge session produces individually reasonable updates (a new contraindication here, a refined distinguishing feature there), but over 50 sessions the aggregate effect could shift the system's classification behavior significantly. The lens_evolution effectiveness scoring (lens-contraindications.md, lines 366-375) tracks engagement events per lens but does not track the *trajectory* of metadata changes over time.

**Verdict:** Concrete improvement. Add a "metadata diff review" to the Forge Mode flywheel. Periodically (every 10-20 sessions), generate a cumulative diff of all lens metadata changes since the last review. Present this diff in a Meta sub-mode session to assess whether the aggregate direction is intentional. This is analogous to the weaver stepping back from the loom to view the carpet from a distance.

### Finding 2.4 — Authentication vs Creation as Distinct Skills

**Source mechanism:** The skills required to weave a carpet and to authenticate one are related but distinct. A great weaver is not automatically a great authenticator, and vice versa. Authentication requires pattern recognition across many weavers' work; creation requires deep mastery of one's own technique.

**Mapping to Forge Mode:** The design does not distinguish between the quality of *generating* a stress test and the quality of *evaluating* a stress test's result. A Forge session could produce an excellent scenario but reach a wrong conclusion, or vice versa. The stress test log (forge-mode.md, line 73) stores "scenario + resolution" as a single unit, but these are products of different cognitive skills.

**Verdict:** Opens a new question. Should Forge Mode track generation quality and evaluation quality separately? A pattern of "good scenarios, bad resolutions" suggests the stress test engine is working but the classification reasoning needs improvement. A pattern of "bad scenarios, irrelevant resolutions" suggests the scenario generation itself is the bottleneck. Separating these signals would sharpen the flywheel's self-diagnosis.

---

## Agent 3: fd-astronomical-clock-calibration

### Finding 3.1 — Coupled Mechanism Root Cause Isolation

**Source mechanism:** In a medieval astronomical clock, a visible error on the lunar phase dial might originate from the lunar gear train, the solar gear train (via a shared intermediate wheel), or the calendar computation (via the Easter dating mechanism). The master clockmaker's discipline is: never adjust until you have isolated which train is the source, because adjusting the wrong train makes the visible error disappear temporarily while introducing a hidden phase error.

**Mapping to Forge Mode:** When a stress test reveals a lens selection failure (forge-mode.md, lines 35-43), the design assumes the fix is lens metadata (add a contraindication, refine a distinguishing feature). But the failure could originate from any of four coupled subsystems: lens metadata, the selection algorithm (`select_lenses()` in lens-contraindications.md, lines 100-135), the profile context (entities fed to the selector), or the stress test scenario itself (a badly constructed scenario that doesn't actually test what it claims). The design has no isolation protocol to determine which subsystem is the root cause before committing a metadata change.

**Verdict:** Concrete improvement. Add a "root cause isolation" step to the Forge Mode stress test flow, between failure identification and artifact generation. Before updating lens metadata, the session should explicitly test alternative hypotheses: "Would a better selector prompt have caught this?" "Was the profile context misleading?" "Is the scenario itself ambiguous rather than the classification?" This prevents phantom corrections — metadata changes that mask algorithmic problems.

### Finding 3.2 — Phantom Correction Risk in Contraindication Updates

**Source mechanism:** When a clockmaker adjusts the wrong gear train, the visible error on the dial disappears — the clock appears fixed. But a hidden phase error has been introduced that will compound over months, eventually producing a larger and harder-to-diagnose failure.

**Mapping to Forge Mode:** The contraindication check flow (lens-contraindications.md, lines 117-135) adds a Verify and Check step after lens selection. If a stress test reveals that sunk-cost was incorrectly applied, the natural fix is to add a contraindication to sunk-cost. But if the real problem was that the selector prompt lacked sufficient context (not a metadata issue but an algorithm issue), the new contraindication will prevent sunk-cost from being applied in that specific scenario while leaving the underlying selector weakness intact. Future scenarios with the same selector weakness but different surface features will fail in new, harder-to-diagnose ways.

**Verdict:** Opens a new question. Should every metadata change from a Forge session carry a "regression test" — a scenario where the *old* behavior was correct and the new metadata should not change it? This is the clockmaker's "check the other dials after adjusting one train" — verify that your fix didn't introduce a hidden regression in an adjacent classification boundary.

### Finding 3.3 — External Calibration Reference

**Source mechanism:** Astronomical clocks calibrate against an external standard: the actual sky. The clock's displayed output (computed solar/lunar position) is compared against direct astronomical observation. Without this external reference, the clock calibrates against itself — circular validation that can drift arbitrarily far from reality.

**Mapping to Forge Mode:** The design's calibration loop is entirely self-referential. Forge Mode uses Auraken's own lens selection to stress-test Auraken's own lens selection, judged by Auraken's own (user + agent) assessment of correctness. There is no external reference point. The closest thing is user pushback (lens-contraindications.md, lines 366-375), but this only captures explicit disagreement, not cases where the user accepts a wrong classification because it sounds plausible.

**Verdict:** Concrete improvement. Define what serves as Forge Mode's "astronomical observation" — the external ground truth. Candidates: (a) post-conversation user outcome data ("did the reframe actually help, measured weeks later?"), (b) peer review by a different agent or human expert who evaluates Forge session transcripts without knowing which lens was selected, (c) a curated set of "gold standard" classification examples with known-correct answers that are periodically re-tested. Without at least one external calibration mechanism, the self-referential loop risks drifting from user-serving accuracy toward internal consistency.

### Finding 3.4 — Sub-Mode Independence with Explicit Coupling Points

**Source mechanism:** Each gear train in an astronomical clock must be independently correct (moon phase accurate regardless of solar time) but harmonically coupled at specific, well-defined points (Easter computation requires both). The coupling points are explicit mechanical connections, not emergent interactions.

**Mapping to Forge Mode:** The three sub-modes (Stress Test, Profile Sim, Meta) are described as feeding into each other via the flywheel (forge-mode.md, lines 168-178), but the coupling points are implicit. The flywheel says "Stress Test updates metadata, Profile Sim validates, Meta applies" — but there is no explicit interface between them. What specific artifacts does Stress Test produce that Profile Sim consumes? Can Profile Sim run without any prior Stress Test output? Can Meta contradict a Stress Test finding?

**Verdict:** Concrete improvement. Define explicit coupling interfaces between sub-modes. For example: Stress Test produces `stress_test_log.jsonl` entries with a defined schema; Profile Sim reads these as regression test inputs; Meta reads cumulative metadata diffs as strategic review material. Making the coupling points explicit prevents emergent interactions where a change in one sub-mode's output format silently breaks another sub-mode's assumptions.

---

## Agent 4: fd-chinese-tea-ceremony-discrimination

### Finding 4.1 — Bitter Pairs as Targeted Stress Test Generation

**Source mechanism:** Gongfu masters train apprentices using "bitter pairs" — two teas that taste nearly identical but require different brewing parameters. The pairs are not randomly selected; they are deliberately chosen to target the *boundary* of the apprentice's current discrimination ability. The pedagogical value is in the pairing, not in the individual teas.

**Mapping to Forge Mode:** The stress test flow (forge-mode.md, lines 35-43) generates scenarios to "challenge a capability" but does not specify that scenarios should be generated as *pairs* targeting an existing near-miss boundary. The sunk-cost / values-conflict example is a pair, but this pairing is ad hoc rather than systematic. With 291 lenses and a growing `near_miss_lenses` graph, stress test generation should be *driven by* the near-miss graph — automatically selecting the least-tested or most-recently-changed near-miss pair as the next stress test target.

**Verdict:** Concrete improvement. Add a stress test generation strategy that consumes the `near_miss_lenses` graph and prioritizes pairs with: (a) no existing stress test coverage, (b) recent metadata changes that may have shifted the boundary, or (c) high effectiveness-score volatility. This transforms stress testing from ad hoc exploration into systematic boundary refinement.

### Finding 4.2 — Anchor Examples for Calibration Verification

**Source mechanism:** Tea competition judges periodically return to "anchor teas" — reference samples of known provenance and character — to recalibrate their palate. After tasting a sequence of boundary-pushing samples, the judge's perceptual baseline can drift. The anchor resets it.

**Mapping to Forge Mode:** After a series of boundary-pushing stress test sessions, the system's classification behavior may have drifted from its baseline. There is no mechanism to verify that classifications which were correct *before* the stress tests are still correct *after*. The lens_evolution effectiveness scoring (lens-contraindications.md, lines 366-375) tracks trends but does not have a fixed reference set.

**Verdict:** Concrete improvement. Curate a set of "anchor scenarios" — 20-30 classification examples with known-correct lens selections, representing the full range of lens categories. Run these as a regression suite after every N Forge sessions. Any change in classification for an anchor scenario is a calibration drift signal that should be investigated before further stress testing. This is cheap (a batch Haiku call) and provides the external reference that Finding 3.3 also identifies as missing.

### Finding 4.3 — Action-Consequence Requirement for Near-Miss Distinctions

**Source mechanism:** In gongfu tea, over-subdivision of cultivar categories is a known failure mode. Expert judges can distinguish 50 sub-types of Wuyi yancha, but the practical question is: does the distinction change the brewing? A distinction that does not map to a different *action* (water temperature, steeping time, vessel choice) is intellectually interesting but practically useless — it wastes the judge's limited perceptual bandwidth.

**Mapping to Forge Mode:** The contraindication schema (lens-contraindications.md) enables increasingly fine-grained near-miss distinctions between lenses. But there is no requirement that each distinction map to a different *treatment* in the conversation. If sunk-cost and values-conflict are near-misses, the design requires that selecting one vs the other produces a *different reframe, different questions, different lens injection*. If two near-miss lenses produce substantially similar conversation outputs, the distinction is wasted complexity.

**Verdict:** Concrete improvement. Add an "action divergence test" to the stress test flow. When a near-miss pair is identified or refined, verify that the two lenses produce materially different conversation behavior (different reframes, different follow-up questions, different `watch_for` injections). If they do not, the lenses may be candidates for merging or the `near_miss` edge should be downgraded to a `contrasts` edge. Every near-miss distinction must pay for itself in treatment divergence.

### Finding 4.4 — Progressive Difficulty Tracking

**Source mechanism:** Tea discrimination training follows a strict easy-to-hard progression: green vs black (trivial), different Wuyi yancha (moderate), same cultivar from adjacent gardens (expert). An apprentice who skips to expert-level pairs without mastering moderate ones develops brittle discrimination — they memorize specific pairs rather than building generalizable perceptual categories.

**Mapping to Forge Mode:** The design has no concept of stress test difficulty levels or progression tracking. A Forge session could jump from testing an obvious misclassification (sunk-cost vs systems-thinking, which share almost no surface features) to an expert-level boundary case (sunk-cost vs values-conflict, which share many surface features) with no awareness of the gap. Without difficulty tracking, there is no way to assess whether the system's classification ability is improving — whether it can now handle harder cases than it could 20 sessions ago.

**Verdict:** Opens a new question. Should stress tests carry a difficulty rating, perhaps derived from the semantic distance between the near-miss pair and the number of shared surface features? This would enable: (a) progressive curriculum design for systematic lens boundary refinement, (b) a measurable "discrimination score" that tracks Auraken's classification maturity over time, and (c) identification of difficulty plateaus where the system stops improving on harder cases, suggesting a deeper architectural limitation rather than a metadata gap.
