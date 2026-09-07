# Flux-Drive Systems Thinking Review: Auraken Exocortex Shape Brainstorm

**Document:** `/tmp/flux-drive-auraken-exocortex-1919.md`  
**Review Date:** 2026-04-21  
**Reviewer:** Claude Code (fd-systems)  
**Related Beads:** sylveste-i0px, sylveste-2xzz, sylveste-am7w, sylveste-22oi, sylveste-heh8  
**Focus:** Feedback loops, emergence, causal chains, path-dependencies, and unintended consequences in Shape A/B/C selection and sequencing.

---

## Findings Index

| ID | Title | Severity | Lens | Section |
|:---|:------|:---------|:-----|:--------|
| F1 | Validation gate amplifies risk through Shape B/C | P1 | Causal Chain, Feedback Loop | Validation Discipline |
| F2 | Self-corpus extraction creates user-expectation ratchet | P1 | Emergence, Schelling Trap | Shape B Economics |
| F3 | Profile-sharing network effects assume non-adversarial equilibrium | P1 | Emergence, Cobra Effect | Shape C Moat |
| F4 | Hermes pivot pace-layer mismatch: hardening timeline vs. exocortex scope creep | P2 | Pace Layers, Path Dependency | Pivot Cost Section |
| F5 | PHILOSOPHY Principle 8 violation cascades through user-shared profiles | P2 | Causal Chain, Hysteresis | Tension 2 |
| F6 | Shape A moat erosion if pipeline quality regresses across shapes | P2 | Feedback Loop, Compounding | Economics & Moat |
| F7 | Curation discipline divergence: "more profiles" vs. "better authoring" creates false dilemma | P2 | Systems Framing | Tension 1 |
| F8 | Schema v1 commitment locks assumptions without feedback-loop testing | P2 | Path Dependency | What This Is NOT |

---

## Verdict

**Ship Shape A first. Defer B/C pending outcome-based learning signals.**

The brainstorm correctly identifies three genuine shapes with distinct feedback loops and equilibria. However, it underestimates the causal risks where Shape B and Shape C feed back into Shape A's validation discipline and moat durability. The Meadows validation gate (12 leverage-points rediscovery) is a real quality floor for Shape A — but the gate was designed for public-corpus expert extraction, not user-supplied data or user-authored profiles. If B/C ship first or in parallel, either the gate weakens (false negatives, profiles ship unvalidated) or it becomes a costly per-user operation (unsustainable). The Hermes pivot is still hardening; adding exocortex UX before the overlay is stable risks double-reinvention. Path-dependencies are real: once users expect self-corpus ingestion, removing it is costly; once profiles are shared, consent becomes a legal obligation, not a design choice.

---

## Summary

### The Core Systems Issue

Shape A is defensible and complete: curated profiles baked into a companion, moat is curation quality + validation discipline. Shape B and C extend the same extraction pipeline to user-supplied data and user-authored content. The brainstorm frames this as a shape question, but it is actually a **feedback-loop and path-dependency question**:

- **Shape B (self-corpus):** Does user-ingested writing feed back into Shape A curation discipline, or does it fork it? If a user's extracted frames don't pass the Meadows gate, what happens? Is the gate user-facing or internal? 
- **Shape C (handcrafted profiles):** If users author profiles and optionally share them, what emergent behaviors appear? Under what conditions does profile-sharing become like a jailbreak-distribution network rather than intellectual commons?
- **Validation at scale:** The Meadows gate requires human review (Gate 2: "pipeline run on her OTHER essays"). Does this scale to Shape B (user runs gate on their own corpus?) and Shape C (user runs gate on their handcrafted profile)?

The brainstorm touches these tensions (Sections: Tensions 1-5, Assumptions 1-6) but does not trace the feedback loops or second-order effects deeply enough.

### Feedback Loop Structures

1. **Shape B → Shape A (positive or negative feedback?)**  
   User's extracted frames could inform Shape A curation (rare-frame discovery, user-researcher patterns → new profiles). OR: User's noisy corpus produces low-quality frames, sets expectations that profiles are extraction artifacts not carefully curated, weakens Shape A brand.

2. **Shape C → Shape A (dilution or elevation?)**  
   Handcrafted profiles could seed Shape A roster (user-discovered obscure thinker → "worth shipping officially"). OR: Handcrafted profiles become first experience, user expects low validation bar, feels Shape A profiles are over-engineered.

3. **Validation gate → Shape B/C (transferability question)**  
   Meadows gate works for canonical expert extraction. Does it transfer? Rediscovering Meadows's 12 points from her essays is validation (ground-truth comparison). Rediscovering a *user's* framework from their corpus is weaker (user is ground truth but cannot articulate it). Validating a *user-handcrafted* profile has no validation gate — it ships at whatever quality user accepts.

4. **User expectations → Validation standards (ratchet effect)**  
   Once Shape B ships, users expect self-corpus to work. If it produces mediocre frames, they blame the pipeline, not their corpus. Pressure to lower the validation bar to ship "good enough" profiles. Once bar lowers for Shape B, Shape A profiles face same pressure (why is this one harder?). **Ratchet is one-way — cannot raise bar once lowered without breaking user expectations.**

### Emergence & Adversarial Dynamics

Shape C's profile-sharing assumes cooperative equilibrium: users author profiles to help others, shared profiles are trustworthy, network effects compound trust. But shape C has no validation gate and **explicitly makes provenance visible** (user-authored, visible to recipients). Under adversarial pressure:

- Jailbreak profiles: users craft profiles of fictional "unconstrained advisors" to bypass Auraken's safety guidelines, share with others (profile-market for jailbreaks)
- Overfit profiles: profile works brilliantly for its author, fails for others, receiver blames Auraken, not profile
- Adversarial extraction: user points corpus ingestion at someone else's published work without consent, builds profile, shares it (consent violation at scale)
- False authority: user makes up a profile (fake "expert"), shares it, others trust it because it looks official

None of these are impossible; they are predictable emergent behaviors under adversarial pressure. The brainstorm does not model them.

### Pace-Layer Mismatch

Hermes pivot is still hardening (sylveste-22oi active). The pivot itself is a **slow layer** — personality, MCP servers, skill packs must integrate cleanly. Shape B requires **corpus ingestion UX** (new surface). Shape C requires **authoring UX** (significantly more new surface). Both are **fast layers**. If exocortex shapes ship before Hermes hardening, they fork the product shape: legacy standalone → Hermes overlay vs. new UX for exocortex. If they ship after Hermes hardens, they add complexity to an overlay system still learning what "overlay" means in practice.

---

## Issues Found

### F1: Validation Gate Amplifies Risk Through Shape B/C [P1 / Causal Chain, Feedback Loop]

**Location:** Section "Tension 5: Validation discipline"  
**Issue:**  
The Meadows gate is powerful but narrow. It validates extraction quality by comparing extracted frames against a canonical expert's explicitly-enumerated framework (12 leverage points, readily verifiable). The brainstorm says:

> Shape B inherits a weaker version (does the pipeline rediscover *the user's* framework from their writing? The user is the ground truth, but they may not be able to articulate what the pipeline should find).

But the actual causal chain is:

1. Shape A ships with Meadows + Appleton + others, all passing the 12-point gate or equivalent
2. Users see these profiles, observe validation rigor (human review, rediscovery tests, scope metadata consistency)
3. Shape B ships: user uploads corpus, pipeline runs, frames extracted, **no validation gate available** (user cannot articulate their own framework precisely enough for rediscovery test)
4. **User-extracted frames fail silently or ship at lower quality**
5. User assumes Shape A profiles are equally unvetted (they work the same way internally, right?)
6. **Curation moat erodes** — users no longer believe the curated roster is carefully crafted, now believes it is algorithmic like their self-corpus extraction

This is a **negative feedback loop on moat credibility**. Once users see mediocre self-corpus extraction, they re-evaluate the entire profile roster through that lens. The gate cannot strengthen user-extracted profiles without human intervention (user reviews their own extracted frames? unsustainable). The gate cannot be weakened for Shape A without losing the moat.

**Second-order effect:**  
If Shape B ships and self-corpus extraction is noisy, users will demand Shape A profiles also pass a "user experience" test (i.e., "does this profile actually help?") instead of a rigorous rediscovery test. Validation discipline bifurcates: curated profiles need theoretical rigor, user-extracted profiles need subjective quality. Once you ship both, the cheaper criterion wins (Goodhart pressure). Within 6-12 months, Shape A validation gates loosen to match user expectations set by Shape B.

**Recommendation:**  
Ship Shape B only after defining and shipping a **user-level validation criterion** for self-corpus extraction. This is not the Meadows gate (that is for experts). It could be: "pipeline rediscovers 3+ unique patterns from user's writing when run twice on different subsets (consistency test)" or "user reviews extracted frames and marks 70%+ as accurate." Document this gate explicitly, surface it to users as feedback, and measure its signal. Do not ship Shape B "preview" without validation gate. Preview shapes set user expectations.

---

### F2: Self-Corpus Extraction Creates User-Expectation Ratchet [P1 / Emergence, Schelling Trap]

**Location:** Section "Shape B: Self-Corpus Exocortex" and "Assumptions 2: Self-corpus extraction works"  
**Issue:**  
The brainstorm correctly identifies the assumption: "A user's mixed journals + drafts + Slack-like notes may be too noisy." But it does not model the **expectation ratchet** created when Shape B ships.

Once a user uploads their corpus and Auraken surfaces insights ("you keep using systems-thinking frames in technical decisions but not in relationships"), the user's expectation is set: **Auraken can extract my frameworks from my writing.** If Auraken later says "your corpus is too noisy, extraction quality is low" or "I need you to hand-annotate these frames," the user experiences this as **regression**, not as honest limitation.

The causal chain:

1. User uploads 50K words of journals + drafts + half-finished notes
2. Pipeline runs, surfaces some genuine patterns + some noise
3. User finds some insights useful, feels some are wrong
4. User's model now includes: "Auraken's self-extraction sometimes works"
5. User starts keeping journal in Auraken instead of external tool
6. User expectation: "Auraken can extract from increasing corpus complexity"
7. **Corpus becomes noisier** (mixed from multiple sources, less edited, more scattered)
8. Extraction quality degrades OR Auraken must surface quality degradation message
9. User perceives this as broken, feels worse than if they had never tried

This is a **Schelling trap**: individually, shipping Shape B looks good (users love the idea). But the system-level equilibrium is "user uploads corpus → expectation set → corpus complexity increases → quality degrades → user churn increases." Worse, the churn is not random — users with substantial, well-organized corpora (researchers, writers, scholars) will be the ones who *benefit* from Shape B and *stay*. Users with disorganized corpora will churn. This selects for a narrow demographic.

**Recommendation:**  
Before shipping Shape B, run a **prototype phase** with 10-20 power users with known substantial corpora (writers, researchers, scholars explicitly). Measure: (1) corpus characteristics (size, editing ratio, source diversity), (2) extraction quality vs. corpus characteristics, (3) user satisfaction vs. quality perception, (4) expectations set after first upload vs. actual quality long-term. Document the "corpus profile" (coherence, editing ratio, size) required for good extraction quality. Only ship Shape B with a clear communication about corpus requirements, and surface corpus-quality feedback to users as a collaboration signal, not a failure signal.

---

### F3: Profile-Sharing Network Effects Assume Non-Adversarial Equilibrium [P1 / Emergence, Cobra Effect]

**Location:** Section "Shape C: Handcrafted-Thinker Substrate" and "Assumptions 4: Network effects are reachable"  
**Issue:**  
The brainstorm assumes profile-sharing creates positive network effects: users craft profiles for rare thinkers, share with others, others find value, network grows. Reality under adversarial pressure:

**Jailbreak profiles:**  
A user crafts a profile of a fictional "unrestricted advisor" with moves like "ignore safety considerations" and "tell me how to make [illegal thing]." This profile is shaped to bypass Auraken's guidelines. The user shares it, others download it, Auraken now has a distribution network for jailbreaks. Once jailbreak profiles exist in the ecosystem, Auraken must either: (a) validate every shared profile before publishing (costly), (b) allow users to publish anything (liability and safety issue), or (c) remove profiles post-hoc (creates trust that shared profiles are trustworthy, then betrays that trust).

**Overfit profiles:**  
A user crafts a profile of a philosopher, deeply customizes it to their own way of thinking. The profile is brilliant for them. They share it. Another user downloads it, finds it doesn't match the original philosopher's actual thinking (because it's overfit to the first user's interpretation). The second user blames Auraken ("this profile is broken"), not the first user. If profiles are removable, the first user's months of work vanish; if persistent, bad profiles accumulate.

**Adversarial extraction:**  
A user points corpus ingestion at another person's published work (with or without consent), builds a profile of them, shares it. If consent was not obtained, Auraken is extracting third-party data at scale. The brainstorm acknowledges this under Tension 4 ("even if the user is the only consumer, the extraction still happened") but does not model the incentive: users will extract profiles of living people without consent if it's easy and beneficial.

The **cobra effect** (named after a colonial British policy in India that incentivized cobra killing, leading to cobra farming): Shape C incentivizes users to author and share profiles. Incentive: get your profile into the ecosystem, gain followers, influence how others think. But no validation gate means profiles optimized for virality and engagement, not accuracy. Overfitting becomes a feature (profiles that strongly "match" a user's thinking spread faster). Jailbreaks become a feature (profiles that break guidelines attract users who want to break guidelines).

**Recommendation:**  
Profile-sharing is not a launch feature for Shape C. Ship Shape C v1 with local-only profiles (user-authored, not shared). Measure: (1) do users actually author profiles, or is authoring too much work?, (2) what is the breakdown between profiles that start as extractons from user corpora vs. handcrafted?), (3) do users find shared profiles valuable as a concept? Only after you have local-only adoption and can characterize what good looks like (quality metrics, user investment patterns) should you consider sharing. If you ship sharing, require human review for each shared profile (Auraken staff validates that profile accurately represents the intended thinker, and that the profile does not circumvent safety guidelines). This is not scalable, but it is the only way to avoid the cobra effect.

---

### F4: Hermes Pivot Pace-Layer Mismatch: Hardening Timeline vs. Exocortex Scope Creep [P2 / Pace Layers, Path Dependency]

**Location:** Section "Tension 6: Pivot cost against Hermes roadmap"  
**Issue:**  
The Hermes pivot is a **slow layer** in Brand's pace-layer model: it is the foundation that other things are built on. Auraken's personality, MCP servers, skill packs must integrate with Hermes cleanly, and Hermes itself is still stabilizing as an overlay architecture. The brainstorm says:

> How much of the Hermes pivot needs to harden before exocortex shapes are addressable? Does exocortex pull Auraken back toward a standalone product and away from the overlay?

This is the right question, but the answer is implicit in the pace-layer structure: **all of it needs to harden, and exocortex shapes pull Auraken away from the overlay.**

If you ship Shape A before Hermes fully hardens, Shape A is tightly coupled to Hermes (personality layer, built-in). If you then ship Shape B (corpus ingestion), you need corpus-ingestion UX. This UX is either: (a) built into Hermes as a skill, or (b) built as a standalone module and plugged into Auraken. If (a), you are adding a fast-layer feature to a slow-layer system still learning its architecture. If (b), you are drifting back toward the standalone product shape that the pivot moved away from.

**Path-dependency:**  
Hermes overlay was designed for personality + MCP + skills. Corpus ingestion is a data-management layer (where does the user's corpus live? who owns it? how long is it stored?). This is architecturally different from personality (behavior) and MCP (capabilities). If you add corpus ingestion to the Hermes overlay, you are re-architecting Hermes's data model. Once done, it becomes the new baseline; undoing it is costly.

**Causal chain:**  
1. Hermes pivot hardening: personality + MCP + skills working together
2. Decision: ship Shape B (corpus ingestion)
3. Architecture question: where does corpus live? (Hermes server, user's local storage, Auraken backend?)
4. If Hermes server: Hermes data model must support corpus storage, versioning, privacy controls. This is a slow-layer change.
5. If user's local: Auraken can only access corpus during active conversation (inference-time latency). User's data security is user's responsibility.
6. If Auraken backend: new infrastructure (database, API, privacy/compliance). This is a pivot-level change, not an exocortex feature.
7. Once this decision is made and shipped, the architecture is locked in. Changing it later requires re-implementing all three shapes.

**Recommendation:**  
Do not ship Shape B or C until the Hermes pivot has shipped one complete cycle with real users (not internal). By "one complete cycle," I mean: personality working well, users use MCP tools, users benefit from skills, no major architectural rework. This is probably Q3 2026 (guessing from current bead tracker). Shape A should ship with Hermes at that point. Shape B and C can then be evaluated against the real Hermes architecture, not the planned architecture.

---

### F5: PHILOSOPHY Principle 8 Violation Cascades Through User-Shared Profiles [P2 / Causal Chain, Hysteresis]

**Location:** Section "Tension 2: PHILOSOPHY principle collision"  
**Issue:**  
Sylveste PHILOSOPHY.md Principle 8 states: "frameworks apply invisibly by default, revealable on request." This is a **cognitive UX principle**: the agent reframes your thinking without calling attention to the frame, so you experience the insight freshly, not as "I'm being forced through a funnel." You can ask "what lens did you use?" and the agent reveals it.

Shape A honors this: profiles are invisible. User experiences reframes and insights without seeing the profile machinery. Shape B is neutral: user's own frames applied to user's own writing (no opacity concern). Shape C violates it: user-authored profiles have provenance visible by construction, and once shared, they are visible to recipients.

**Causal chain:**  
1. User authors a profile of a philosopher using the Shape C interface
2. Profile is local, user controls visibility
3. User decides to share it with a colleague
4. Shared profile now shows: author name, date, philosophy, description
5. Colleague uses the profile, sees the reframe, and immediately knows it came from a user-created profile (not curated by Auraken)
6. **Colleague's experience is different from Shape A user's experience:** Shape A user sees magic (where did this insight come from?), Shape C user knows it came from a handcrafted profile
7. Colleague's trust in the reframe is **lower** (it is filtered through the author's biases, not carefully curated by experts)
8. Over time, users distinguish between "Auraken-curated profiles" (invisible, trusted) and "user-authored profiles" (visible, less trusted)
9. User-authored profiles become a **second-class citizen**, used only when no curated profile exists for a thinker
10. Network effects for Shape C weaken (users do not invest in authoring if profiles are second-class)

The brainstorm acknowledges this: "Is that a problem or a feature? Principle 8 says default-invisible, revealable on ask. Shape C makes 'reveal' the default for some profiles." But it does not model the hysteresis: **once users experience visible profiles, they cannot un-experience them.** If you later try to hide the provenance (make shared profiles invisible about their origin), users will perceive it as deceptive. If you keep provenance visible, you violate Principle 8, and you create two classes of profiles with different trust levels.

**Recommendation:**  
Do not ship Shape C with profile-sharing until you have resolved the Principle 8 collision. Options: (1) **Keep profiles local-only and invisible** — users author and use profiles for themselves, profiles are not shared or visible. This honors Principle 8 and simplifies governance. (2) **Create a "research and teaching" exception** — shared profiles are explicitly framed as "research artifacts" not as invisible lenses, visible by default, lower trust assumed. This violates Principle 8 but is honest and avoids two-tier trust. (3) **Hide provenance of shared profiles** — shared profiles appear to come from Auraken (same visual treatment as curated profiles), but are actually user-curated. This is deceptive. Choose one, document it, and build UX and governance around that choice.

---

### F6: Shape A Moat Erosion If Pipeline Quality Regresses Across Shapes [P2 / Feedback Loop, Compounding]

**Location:** Implied across "Moat" sections in all three shapes  
**Issue:**  
Shape A's moat is **curation quality** — careful extraction, validation through the Meadows gate, human review. The brainstorm assumes this moat is independent of Shapes B and C. But the pipeline is shared:

> Both are inherently leveraging the same profile extraction and scaffold-generation pipeline (sylveste-1nvc), so the technical architecture is already in place. The schema (sylveste-2xzz) accommodates all three shapes with one field: `profile_origin: curated | user_authored | self_corpus`.

If the extraction pipeline is shared, and Shape B and C use it without the same validation gates as Shape A, then the pipeline accumulates signals from lower-quality extractions. Specifically:

1. User runs self-corpus extraction on noisy journal, pipeline produces mediocre frames
2. User sees low-quality output, provides negative feedback (or no feedback, implicit signal of dissatisfaction)
3. Pipeline learns from this signal (if there is learning in the extraction loop), might adjust parameters to be more conservative
4. Next extraction (Shape A profile) is more conservative, possibly missing rare frames
5. **Shape A quality regresses** as a side effect of Shape B experimentation

This is a **negative feedback loop on moat quality**. The loop is slow (shape adoption takes months), so it is invisible at first. By the time you notice moat erosion (users say "these profiles are less useful than they used to be"), it is hard to trace back to Shape B learning dynamics.

**Recommendation:**  
Before shipping Shape B or C, implement **isolated pipeline branches** for each shape: Shape A uses one extraction model trained on expert corpora with human feedback, Shape B uses a separate model (or the same model with different parameters), Shape C uses a third. Do not let Shape B/C learning degrade Shape A's pipeline. This is not technically complex (pipeline duplication), but it requires discipline to avoid shared-state bugs. Measure Shape A quality (rerun the Meadows gate quarterly on existing profiles) to detect regression early.

---

### F7: Curation Discipline Divergence: "More Profiles" vs. "Better Authoring" Creates False Dilemma [P2 / Systems Framing]

**Location:** Section "Tension 1: Moat direction"  
**Issue:**  
The brainstorm frames Shape A and Shape C as having different moats: "Shape A's moat is *curation quality*. Shape C's moat is *the substrate*." This framing creates a false choice: "ship more profiles" vs. "ship better authoring." But this is not a binary. The false framing obscures the actual tension:

- Shape A requires **expert curation** (small team, high rigor, slow) to maintain moat
- Shape C requires **user authoring capability** (self-serve, low friction, fast) to scale
- Both require **validation discipline** to avoid moat collapse

The tension is not "more vs. better" but "who does the curation?" In Shape A, Auraken's team curates. In Shape C, users curate their own profiles. Once both ship, the question becomes: "How do we signal to users that self-curated profiles are less rigorous than Auraken-curated profiles?" If users can't tell the difference (same visual treatment), trust erodes. If users can tell (visible provenance), you have a two-tier system and users invest less in self-curation because it is second-class.

**The real tension:** Shape A's success depends on people believing "these profiles are carefully crafted." Shape C's success depends on people believing "I can craft profiles that are good enough." These are not compatible belief structures. You can have one or the other, but if you ship both, you create a **Schelling point failure**: users will naturally separate into two groups (those who trust curated profiles, those who self-author), and the groups will not mix.

**Recommendation:**  
Reframe the tension. Do not frame it as "moat direction" but as "audience segmentation." Shape A targets users who want to trust Auraken's curation. Shape C targets users who want to extend Auraken with their own frameworks. These are different users, different value propositions, different retention models. If you ship both simultaneously, you need explicit UX boundaries (separate interfaces, separate modes, separate pricing) to prevent confusion and cross-pollination. If you ship A first and C later, C automatically becomes "advanced mode" and avoids Principle 8 collision. Choose sequencing intentionally based on how you want to signal quality to different user segments.

---

### F8: Schema v1 Commitment Locks Assumptions Without Feedback-Loop Testing [P2 / Path Dependency]

**Location:** Section "What This Doc Is NOT"  
**Issue:**  
The brainstorm says: "Schema v1 can accommodate all three shapes with one field (`profile_origin: curated | user_authored | self_corpus`) — that decision is cheap and I flagged it separately."

But this **assumes schema v1 will not need to change based on Shape B/C learning.** Reality:

- **Shape A schemas** include fields like `corpus_source` (Meadows essays), `validation_gate` (12 leverage points), `human_review_by` (staff initials), `human_review_notes` (finding summary)
- **Shape B schemas** need fields like `corpus_upload_date`, `corpus_coherence_score`, `user_corpus_config` (which types of writing to include?)
- **Shape C schemas** need fields like `authored_by_user_id`, `shares_with` (list of users), `override_provenance` (display as Auraken-curated?), `third_party_thinker_consent` (if extracting from someone else's work)

The single `profile_origin` field does not capture this complexity. Once you ship profiles with more detailed origin metadata, changing the schema is costly: you need migrations, backwards-compatibility shims, and all existing profiles must be re-validated. The schema becomes a **locked-in assumption** about what profiles are and how they're described.

**Path-dependency:**  
If you commit to schema v1 now (before piloting Shape B/C), you are locking in assumptions about what fields profiles need. If Shape B pilots reveal that corpus coherence is crucial metadata (and schema v1 does not have it), you must either: (a) extend schema in-place (breaking change), or (b) ship Shape B profiles with a different schema (now you have two profile schemas, versioning nightmare). Either way, the early commitment to schema v1 becomes a liability, not an asset.

**Recommendation:**  
Ship schema v1 with Shape A only. Include a `profile_version: 1` field explicitly. Document the schema as "v1, scoped to curated expert extraction, not extensible to user-supplied data." When you pilot Shape B, write a new schema v2 (or Shape B schema, with different `profile_origin` field handling). Keep both schemas in production during the pilot (profiles carry their schema version). Only after Shape B pilots succeed (users do extract their corpora, quality is acceptable) should you unify schemas or make design decisions about Shape C schema requirements. This is more work upfront (you manage two schemas) but it is less work long-term (you avoid migrations and locked-in assumptions).

---

## Improvements & Recommendations

### For Shape A (Ship First)

1. **Validate the Meadows gate empirically:** Before shipping Shape A, complete sylveste-am7w fully. Run the pipeline on Meadows's essays twice (Gate 1 and Gate 2) and confirm 7+ of 12 leverage points rediscovered. Document the prompts and parameters used. This is your baseline for Shape B/C comparison.

2. **Surface validation quality to users:** Users should see that profiles are carefully curated, not algorithmic. Consider a "validation badge" or "human-reviewed" marker on profiles, plus optional access to validation notes (what the Meadows gate confirmed). This builds trust in the moat.

3. **Measure Shape A adoption and satisfaction:** Before piloting Shape B, ship Shape A with real users and measure: do users actually use profiles? Do they cite them in their own thinking? Does long-term retention improve? This is your signal that the moat is real. Only proceed to B/C if Shape A shows strong signal.

### For Shape B (Pilot After Shape A Stability)

1. **Prototype with 10-20 power users:** Users with 50K+ well-organized corpora (writers, researchers, scholars). Not public beta. **Measure corpus characteristics that correlate with extraction quality.** Document the minimum viable corpus (coherence, size, editing ratio) required for good extraction.

2. **Define a user-level validation criterion:** Not the Meadows gate (that is for experts). Instead: "pipeline consistently rediscovers the same patterns when run on different subsets of your corpus" (consistency test). Surface results to the user as collaboration feedback, not quality judgment.

3. **Implement isolated pipeline:** Shape B uses its own extraction model or parameters, not shared with Shape A. Measure Shape A quality metrics quarterly to detect regression.

4. **Explicitly scope and limit**: Shape B is a pilot. Market it as beta, gather feedback, and plan for either sunset (users did not want this) or graduation (add to product). Do not let it drift into permanent "beta" status.

### For Shape C (Defer Beyond Hermes Hardening)

1. **Ship local-only profiles first:** Users author profiles for their own use, not shared. This lets you understand the authoring UX without governance complexity. Once you have local adoption, *then* consider sharing.

2. **Profile-sharing requires governance:** If you ship sharing, require human review for each shared profile (staff validates accuracy, checks for jailbreaks). Do not automate. This is not scalable, but it prevents the cobra effect. If you reach scale where human review is infeasible, you've succeeded and can reconsider scaling through trust signals, reputation, community review, etc.

3. **Resolve Principle 8 collision explicitly:** Document whether user-authored profiles will be treated as (a) local research artifacts, (b) second-class citizens distinct from curated profiles, or (c) hiding provenance (not recommended, potentially deceptive). Build UX around that choice so users understand what they are using.

### General

1. **Lock the schema commitment to Shape A:** Do not use a shared schema field `profile_origin` to "future-proof" for B/C. Schema v1 is for Shape A. Shape B can use Shape B Schema. This makes the codebase clearer and avoids locked-in assumptions.

2. **Treat exocortex shapes as a pivot question, not a feature question:** Whether Auraken ships exocortex is a strategic decision about the product shape, not a product management decision about feature scope. The decision should be made by leadership with input from fd-decisions (reversibility, timing, commitment cost) not just fd-systems. This brainstorm provides good material for that conversation but should not drive the decision alone.

---

## Conclusion

The three shapes are real, the tensions are genuine, and the feedback loops are non-obvious. The brainstorm correctly identifies that validation discipline, curation moat, and Hermes pivot timing are the critical questions. The systems-thinking review surfaces the causal chains and path-dependencies that make this decision consequential.

**Recommendation:** Ship Shape A with Hermes, validate with real users. Pilot Shape B with power users after Shape A stability. Defer Shape C pending outcome data from Shape B and resolution of PHILOSOPHY Principle 8 collision. This sequencing preserves optionality, avoids locked-in assumptions, and lets feedback loops from users inform the next decision.

---

<!-- flux-drive:complete -->
