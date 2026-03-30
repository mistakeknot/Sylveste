---
artifact_type: review-synthesis
method: flux-review
target: "apps/Auraken/"
target_description: "Auraken use case landscape — all capabilities enabled by deep personal context + interdisciplinary systems thinking"
tracks: 4
quality: max
track_a_agents: [fd-recommender-system-architecture, fd-cognitive-augmentation-science, fd-conversational-ai-personality, fd-personal-ai-privacy-trust, fd-second-brain-knowledge-architecture]
track_b_agents: [fd-concierge-medicine-longitudinal-care, fd-wealth-advisory-fiduciary-modeling, fd-museum-experience-ambient-discovery, fd-intelligence-analysis-structured-sensemaking]
track_c_agents: [fd-persian-carpet-weaving-composition, fd-chinese-lacquerware-layering, fd-gamelan-orchestral-stratification, fd-constitutional-herbalism-terrain]
track_d_agents: [fd-ayurvedic-prakriti-constitution, fd-kampo-sho-pattern-recognition, fd-inuit-siku-ice-knowledge]
date: 2026-03-30
---

# Auraken Use Case Landscape — Flux Review Synthesis

## Critical Findings (P0/P1)

### P0-1: No profile deletion mechanism or data lifecycle policy

**Tracks:** A
**Agent:** fd-personal-ai-privacy-trust (Finding 10)

The cognitive profile stores thinking patterns, contradictions, and "submerged patterns that surprise even the user" across three tiers, but no document mentions deletion, export, retention limits, or user data management. Profile export is a v3.0 feature, meaning v1.0 and v2.0 ship with no portability. The episode layer is described as "immutable." This is a GDPR Article 17/20 compliance failure for EU users from day one.

**Fix:** Add a Data Governance section to the PRD before v1.0 covering right to access, right to erasure (episodes must be made deletable), right to rectification, data lifecycle with retention limits, and purpose limitation between cognitive augmentation and product recommendations.

---

### P0-2: Affiliate monetization creates undisclosed fiduciary conflict

**Tracks:** B
**Agent:** fd-wealth-advisory-fiduciary-modeling (Finding WA-1)

VISION.md lists affiliate revenue as a potential business model. The system has deep knowledge of the user's psychological vulnerabilities (contradiction registry, blind spots, stress patterns) and would be financially incentivized to exploit them. This is structurally identical to the commission-based compensation model that destroyed trust in financial services. The combination of deep personal context with affiliate-monetized recommendations is the single highest reputational risk.

**Fix:** Resolve before recommendations ship. Preferred: subscription-only, never monetize through affiliate links. If affiliate revenue is pursued, structurally separate the recommendation generation process from affiliate status (recommendations generated without knowledge of which products have affiliate links, links added post-selection with explicit disclosure). Document the chosen approach as a named principle in PHILOSOPHY.md.

---

### P0-3: No contraindication signatures on lenses — near-miss patterns cause invisible harm

**Tracks:** D
**Agent:** fd-kampo-sho-pattern-recognition (Finding 4)

Lens selection uses Klein's RPD pattern matching, but RPD was designed for domains with immediate feedback (firefighting, military command). Auraken operates in a low-feedback domain where wrong lens application causes delayed, invisible harm. Each lens has "when to apply" signatures but no "when NOT to apply" contraindication signatures. A sunk-cost lens applied to what is actually a values conflict causes the user to abandon something they genuinely care about. The system has no mechanism to detect or prevent this.

**Fix:** Add `contraindication_signatures` to the lens schema. During lens selection, run a near-miss check against contraindications for the selected lens. When both the trigger pattern and a contraindication match, surface the ambiguity rather than committing to one lens.

---

### P1-1: No cold-start strategy for dynamic lens selection

**Tracks:** A
**Agent:** fd-recommender-system-architecture (Finding 1)

Dynamic lens selection is claimed as the core differentiator, but 3 of 5 selection inputs require a profile that does not exist for new users. The first session degenerates to keyword search over a framework database. The first-session experience is the only chance to demonstrate value.

**Fix:** Add explicit cold-start tier: popularity-based ranking weighted by Cynefin domain, with 2-3 calibration questions that bootstrap a minimal profile by conversation 2.

---

### P1-2: Lens selection paradox — agent selects what the user should learn to select

**Tracks:** A
**Agent:** fd-cognitive-augmentation-science (Finding 4)

Automating framework selection removes the practice opportunity for the skill Auraken claims to develop. The anti-dependency principle (PHILOSOPHY.md Principle 7) is structurally contradicted by the core feature.

**Fix:** Add progressive scaffolding: agent selects invisibly early on, offers binary choices after 10+ conversations with a lens, asks the user to suggest frameworks after 20+. Track selection skill transfer explicitly.

---

### P1-3: Style mirroring has no circuit breaker for distress amplification

**Tracks:** A
**Agent:** fd-conversational-ai-personality (Finding 7)

Style mirroring is default behavior with no boundary conditions. When a user is catastrophizing, mirroring amplifies cognitive distortions rather than breaking the loop. No affect detection, mirroring ceiling, or register exclusion is specified.

**Fix:** Define registers that are mirrored (vocabulary, humor, directness) vs. not mirrored (distress intensity, catastrophizing, self-deprecation). When distress exceeds a threshold, maintain emotional warmth while shifting cognitive register.

---

### P1-4: Negative feedback journey is explicitly undesigned

**Tracks:** A
**Agent:** fd-conversational-ai-personality (Finding 8)

PRD line 239 explicitly acknowledges this gap: "When a reframe lands wrong or feels patronizing." This is the highest-risk conversational moment. Without designed recovery, the agent either doubles down, over-apologizes, or deflects — all of which destroy the "best consultant" positioning.

**Fix:** Design Journey 8: Failed Reframe Recovery. Key elements: acknowledge without excessive apology, use the failure as profile data, shift to Mirror mode after a miss, never try two frameworks in rapid succession.

---

### P1-5: Cross-context linking violates contextual integrity without consent controls

**Tracks:** A
**Agent:** fd-personal-ai-privacy-trust (Finding 11)

Cross-domain pattern detection is positioned as the product's highest-value feature, but violates Nissenbaum's contextual integrity framework. Users sharing relationship information do not consent to it being used to analyze work behavior. No compartmentalization mechanism exists.

**Fix:** Cross-domain linking should be opt-in, not default. The agent must ask before connecting domains for the first time. Users can retroactively compartmentalize.

---

### P1-6: Entity extraction precision undefined — confident wrong profile claims

**Tracks:** A
**Agent:** fd-second-brain-knowledge-architecture (Finding 13)

No confidence thresholds, minimum evidence requirements, or precision/recall targets for entity extraction. "Revealed" and "Submerged" entities are extracted without confidence scoring, compressed into the synthesis layer, and injected into every future conversation. A single-observation inference can be presented as an established pattern.

**Fix:** Add confidence scoring (speculative/emerging/established/confirmed), minimum evidence thresholds per entity category, and phrase low-confidence entities as questions rather than assertions.

---

### P1-7: Trust pacing is monolithic across use case domains

**Tracks:** B
**Agent:** fd-concierge-medicine-longitudinal-care (Finding CM-1)

A single trust arc governs all domains. Product recommendations require near-zero trust; surfacing cognitive blind spots requires deep relationship trust. Treating them identically means either recommendations are gated behind unnecessary trust-building or cognitive augmentation oversteps prematurely.

**Fix:** Per-domain trust level in the profile architecture, advancing independently. Define which interaction modes are available at each trust level per domain.

---

### P1-8: No competence boundary detection or referral mechanism

**Tracks:** B
**Agent:** fd-concierge-medicine-longitudinal-care (Finding CM-2)

Seven journeys are designed, none address the moment when a user's problem exceeds Auraken's competence. The positioning says "not therapy, not wellness" but provides no mechanism for detecting when a conversation has crossed that boundary. The "preserve cognitive struggle" principle could actively worsen a mental health crisis.

**Fix:** Add Competence Boundary section to PRD with trigger signals, response protocol (acknowledge, do not apply lenses, suggest professional resources), and Journey 8: Boundary Detection and Referral.

---

### P1-9: No suitability framework for recommendations

**Tracks:** B
**Agent:** fd-wealth-advisory-fiduciary-modeling (Finding WA-2)

The profile captures thinking patterns, values, and contradictions — all inputs a suitability check would need — but no process consumes them before a recommendation is made. A user in financial stress (inferred from career-change conversations) could receive expensive product recommendations that match aesthetic preferences but not financial reality.

**Fix:** Add a recommendation suitability layer that checks against financial constraints, emotional state, and stated vs. revealed preferences before surfacing.

---

### P1-10: Lens selection has no confirmation bias mitigation

**Tracks:** B
**Agent:** fd-intelligence-analysis-structured-sensemaking (Finding IA-1)

RPD-based lens selection has no competing-hypothesis step. The system selects the lens it recognizes as fitting and moves on. No ACH-equivalent process considers alternative lenses.

**Fix:** Add a competing lens step to the OODARC Decide phase. After primary selection, briefly evaluate at least one alternative lens. If the alternative fits as well, surface the tension to the user.

---

### P1-11: Profile observations lack epistemic confidence levels

**Tracks:** B
**Agent:** fd-intelligence-analysis-structured-sensemaking (Finding IA-2)

No confidence dimension on entities. A pattern observed once is treated the same as one observed twenty times in the entity layer.

**Fix:** Add epistemic status to entities: speculative (single observation), emerging (2-3), established (repeated across sessions), confirmed (user-acknowledged). Only surface established+ patterns in reflections.

---

### P1-12: No mode transition between cognitive augmentation and ambient discovery

**Tracks:** B
**Agent:** fd-museum-experience-ambient-discovery (Finding MU-1)

The system is either in cognitive augmentation mode or recommendation mode with no designed transition. A product recommendation surfaced during a deep OODARC conversation feels like an ad interrupting therapy.

**Fix:** Design explicit mode transitions — threshold micro-interactions (tone shift, framing statement) and a user-initiated "gallery mode" command.

---

### P1-13: Recommendation surfacing lacks curatorial adjacency logic

**Tracks:** B
**Agent:** fd-museum-experience-ambient-discovery (Finding MU-2)

Individual recommendations served with individual rationales are search results, not discoveries. The Robinson window-shopping insight works through adjacency — seeing things next to each other and making connections.

**Fix:** Surface small curated collections (2-4 items) connected by non-obvious themes based on the user's profile, not individual products.

---

### P1-14: Missing use case composition map (the "cartoon")

**Tracks:** C
**Agent:** fd-persian-carpet-weaving-composition (Finding 1)

Four use case domains are designed as standalone motifs with no architectural template showing how they compose. No shared compositional grammar defines transition rules, shared capabilities, or constraints preventing domain conflicts. "Never do the user's thinking" directly conflicts with proactive product recommendations.

**Fix:** Add a Use Case Composition Map defining shared capabilities (warp/weft), transition rules (border designs), and domain-conflict constraints.

---

### P1-15: No border design between cognitive augmentation and commerce

**Tracks:** C
**Agent:** fd-persian-carpet-weaving-composition (Finding 2)

When a career discussion naturally touches on tools or products, no mediating interaction pattern exists. The system either ignores the signal (loses value) or pivots to a recommendation (feels like being sold to mid-therapy).

**Fix:** Define a "border register" where the user controls the transition: "That friction you mentioned -- want to explore that separately, or keep going with the career stuff?"

---

### P1-16: Commerce from thin context — recommendations need more layers than cognitive augmentation

**Tracks:** C
**Agent:** fd-chinese-lacquerware-layering (Finding 4)

Cognitive augmentation's "uncanny moment" arrives at session 5-10. Product recommendations require categorically deeper context (material values, aesthetic sensibilities, budget, purchase patterns). Launching both simultaneously means recommendations built from cognitive-conversation context that never captured purchase-relevant signals.

**Fix:** Define per-use-case readiness thresholds. The system should explicitly decline to recommend until sufficient context has accumulated and communicate this honestly.

---

### P1-17: No colotomic structure — use cases lack temporal hierarchy

**Tracks:** C
**Agent:** fd-gamelan-orchestral-stratification (Finding 7)

Four temporal frequencies of interaction (per-turn, weekly follow-up, monthly growth, long-term profile evolution) are described as independent features rather than a unified temporal hierarchy where each frequency frames the others. Growth reports do not reference the daily conversations that evidenced growth.

**Fix:** Define explicit temporal hierarchy where longer-cycle features frame shorter-cycle ones. Monthly growth synthesizes from daily conversations and weekly follow-ups. Per-turn reframes are aware of the active growth theme.

---

### P1-18: No constitutional vs. symptomatic depth classification

**Tracks:** C
**Agent:** fd-constitutional-herbalism-terrain (Finding 10)

The Cynefin pre-filter classifies problem complexity but not interaction depth. A "Clear" domain problem could still be constitutionally significant if it is the third instance of a recurring pattern. Without depth classification, the system applies constitutional depth to symptomatic needs (10-message exploration of a tool question) or symptomatic depth to constitutional needs (single reframe for a career crisis).

**Fix:** Add a depth axis alongside Cynefin: symptomatic/transitional/constitutional. Dual classification determines both conversation strategy and which capabilities to activate.

---

### P1-19: Profile conflates stable constitution with temporary state

**Tracks:** D
**Agent:** fd-ayurvedic-prakriti-constitution (Finding 1)

Nothing in the architecture distinguishes entities representing stable constitutional patterns ("defaults to analytical thinking under uncertainty") from temporary state ("currently overwhelmed and reverting to avoidance"). A user going through a breakup has avoidance patterns permanently absorbed into the profile. When they recover, the agent continues treating them as avoidant.

**Fix:** Add `temporal_stability` field to entities (constitutional/situational/unknown). Generate two synthesis summaries: slow-moving constitutional and fast-moving situational overlay.

---

### P1-20: No distinguishing-question verification step before committing to a lens

**Tracks:** D
**Agent:** fd-kampo-sho-pattern-recognition (Finding 5)

After holistic pattern matching, no targeted verification step checks the one feature that would flip the diagnosis. A single question — "Do you think your co-founder wants the same thing you want?" — could distinguish principal-agent from coordination failure.

**Fix:** Add `distinguishing_question` to each lens. After initial selection, ask the distinguishing question before committing. The OODARC Decide phase becomes: tentative match, verification probe, then commit or pivot.

---

### P1-21: No explicit no-go decision — system always proceeds to lens selection

**Tracks:** D
**Agent:** fd-inuit-siku-ice-knowledge (Finding 7)

The OODARC model has no pathway where the agent explicitly declines to engage because signals are contradictory and any framework application would be premature. The system always proceeds from classification to lens selection.

**Fix:** Add a confidence threshold to the Decide phase. When lens-match confidence is below threshold and signals are contradictory, enter hold mode: sit with the problem without a frame.

---

### P1-22: Profile over-indexes on verbal content, ignores behavioral text signals

**Tracks:** D
**Agent:** fd-inuit-siku-ice-knowledge (Finding 8)

Message timing, response latency, message length patterns, topic avoidance, and session initiation patterns are rich diagnostic signals for cognitive state, but the PRD frames them only as feeding style mirroring, not as a separate signal modality.

**Fix:** Track per-user baselines for message length, response latency, time-of-day distribution, session initiation ratio, and topic recurrence. Flag deviations as a separate signal layer in OODARC Observe.

---

## Cross-Track Convergence

### Convergence 1: Use case coordination layer is missing (4/4)

The single highest-confidence finding across all tracks. Every track independently identified that Auraken lacks a meta-layer for managing transitions and interactions between use cases operating at different depths and timescales.

- **Track A** (fd-recommender-system-architecture): No exploration mechanism in lens selection; system converges toward familiar frameworks with no diversity constraint.
- **Track B** (fd-museum-experience-ambient-discovery): No mode transition between cognitive augmentation and ambient discovery; fd-concierge-medicine-longitudinal-care: trust pacing is monolithic across domains.
- **Track C** (fd-persian-carpet-weaving-composition): "Missing cartoon" — no compositional template. fd-gamelan-orchestral-stratification: "Missing kendang" — no coordinator between use case voices. fd-constitutional-herbalism-terrain: no triage between symptomatic and constitutional depth.
- **Track D** (fd-inuit-siku-ice-knowledge): No no-go decision; system always proceeds to engagement. fd-kampo-sho-pattern-recognition: no mechanism to detect when multiple lenses must be applied simultaneously vs. sequentially.

Track C's convergence note is explicit: "the carpet weaver calls it missing borders, the lacquerware artisan calls it undefined curing times, the gamelan dalang calls it missing colotomy, the herbalist calls it absent triage." Four metaphors for the same architectural need.

**Convergence score: 4/4**

---

### Convergence 2: Entity confidence and epistemic rigor (4/4)

Profile entities lack confidence scoring, evidence thresholds, and mechanisms for challenging stored assertions.

- **Track A** (fd-second-brain-knowledge-architecture): No precision/recall targets, no minimum evidence requirements. Entities extracted from single observations injected into synthesis layer without confidence scoring. fd-cognitive-augmentation-science: metrics are self-referential — the system measuring its own intervention effectiveness.
- **Track B** (fd-intelligence-analysis-structured-sensemaking): No epistemic confidence levels (NIE-style). No adversarial self-challenge (red teaming) on profile assertions. Single-source observations presented as established patterns.
- **Track C** (fd-chinese-lacquerware-layering): No active context revision mechanism — profile only grows and expires, never sands between layers. fd-constitutional-herbalism-terrain: no mechanism for symptomatic patterns to escalate to constitutional investigation.
- **Track D** (fd-ayurvedic-prakriti-constitution): Profile conflates stable constitution with temporary state. fd-inuit-siku-ice-knowledge: stale models actively mislead; no mechanism to probe for model invalidation. Signal freshness decay undefined.

Each track frames it differently: Track A sees a measurement gap, Track B sees an intelligence analysis failure, Track C sees missing structural maintenance, Track D sees dangerous reliance on outdated models. All converge on: the profile lacks mechanisms for uncertainty, challenge, and revision.

**Convergence score: 4/4**

---

### Convergence 3: Commerce-trust boundary and fiduciary obligation (3/4)

Deep personal context combined with commercial recommendations creates a structural trust problem that requires explicit architectural resolution.

- **Track A** (fd-personal-ai-privacy-trust): Cross-context linking violates contextual integrity. Contradiction registry creates weaponization risk without access controls.
- **Track B** (fd-wealth-advisory-fiduciary-modeling): Affiliate monetization creates undisclosed fiduciary conflict. Deep context creates asymmetric information obligation proportional to profile depth. fd-museum-experience-ambient-discovery: commerce transition risks trust contamination (the gift shop problem).
- **Track C** (fd-persian-carpet-weaving-composition): No border design between cognitive augmentation and commerce. fd-chinese-lacquerware-layering: attempting commerce from thin context poisons trust in all capabilities.

Track D did not directly address the commerce boundary, though the Kampo near-miss finding (wrong lens causing delayed harm) is structurally related.

**Convergence score: 3/4**

---

### Convergence 4: Temporal stratification of the cognitive profile (3/4)

The profile needs multiple temporal layers, not a single evolving model.

- **Track A** (fd-second-brain-knowledge-architecture): Bi-temporal model cannot distinguish changed mind from contextual variation. Synthesis layer token budget produces lossy compression at scale.
- **Track C** (fd-chinese-lacquerware-layering): No curing time between context layers — twenty messages in one hour treated as equivalent to twenty across five sessions. fd-gamelan-orchestral-stratification: no colotomic structure linking temporal frequencies.
- **Track D** (fd-ayurvedic-prakriti-constitution): Constitutional vs. situational distinction (Prakriti-Vikriti). fd-inuit-siku-ice-knowledge: signal freshness decay — observations need type-specific half-lives.

Track D's own convergence note observes that Ayurvedic and Siku lenses are complementary: categorical labels for conceptual clarity, continuous decay for operational weighting. The strongest architecture implements both plus periodic validity probes.

**Convergence score: 3/4**

---

### Convergence 5: Two-phase lens selection — match then verify (3/4)

Lens selection should not be single-pass pattern matching. Multiple tracks independently identified the need for verification, competing hypotheses, or contraindication checking after initial selection.

- **Track A** (fd-recommender-system-architecture): No exploration mechanism; pure exploitation produces filter bubbles.
- **Track B** (fd-intelligence-analysis-structured-sensemaking): No competing-hypothesis step (ACH). No post-mortem learning from failed lens applications.
- **Track D** (fd-kampo-sho-pattern-recognition): Near-miss patterns cause invisible harm without contraindication signatures. Sho-evidence verification step checks the single distinguishing feature. fd-inuit-siku-ice-knowledge: no-go decision when signals are contradictory.

Together these transform lens selection from a single step to a multi-step subprocess: match, check contraindications, ask distinguishing question, consider competing lens, then commit or hold.

**Convergence score: 3/4**

---

### Convergence 6: Distress detection and competence boundaries (2/4)

- **Track A** (fd-conversational-ai-personality): Style mirroring has no circuit breaker for distress amplification.
- **Track B** (fd-concierge-medicine-longitudinal-care): No competence boundary detection or referral mechanism. "Preserve cognitive struggle" principle could worsen a mental health crisis.

Both identify the same gap from different angles: Track A sees a conversational design failure (mirroring distress), Track B sees a scope-of-practice violation (treating beyond competence).

**Convergence score: 2/4**

---

### Convergence 7: Constitutional calibration of delivery (2/4)

The system selects which intervention but does not modulate how it is delivered based on who is receiving it.

- **Track C** (fd-constitutional-herbalism-terrain): Different user terrains need different modulation of the same intervention.
- **Track D** (fd-ayurvedic-prakriti-constitution): Same lens, different dosage — narrative vs. analytical delivery. fd-kampo-sho-pattern-recognition: kyo/jitsu classification for recommendation aggressiveness.

**Convergence score: 2/4**

---

## Domain-Expert Insights (Track A)

### Profile Architecture

- **Synthesis layer lossy compression** (fd-second-brain-knowledge-architecture): The 300-500 token fixed budget cannot represent 50+ entities after 6 months. Replace with adaptive budget: 300 tokens persistent synthesis + 700 tokens RAG-retrieved on demand.
- **No mid-conversation retrieval pipeline** (fd-second-brain-knowledge-architecture): Storage tiers are defined but no retrieval architecture specifies how the agent accesses deeper profile information during conversation. Multi-problem juggling (Journey 7) requires real-time entity-layer queries.
- **Bi-temporal conflation** (fd-second-brain-knowledge-architecture): `valid_from`/`valid_until` cannot distinguish temporal change from contextual variation. Add `context_scope` field alongside temporal fields.

### Feedback and Learning

- **Undefined feedback signal** (fd-recommender-system-architecture): The system cannot improve lens selection quality over time because "Did it help?" has no operational definition. Define 3-5 implicit feedback signals (self-correction, curiosity questions, topic change, future-session reference, independent application) with calibrated weights.
- **Self-referential metrics** (fd-cognitive-augmentation-science): Every augmentation metric is detected by the system producing the augmentation. No external validation, no control condition. Add at least one external validation approach (self-assessment on real-world decisions, independent journaling before Auraken discussion).

### Conversational Design

- **OODARC empirical grounding** (fd-cognitive-augmentation-science): Boyd's OODA imports adversarial-tempo assumptions unsuited to collaborative sensemaking. Frame OODARC as a design heuristic rather than a cognitive model.
- **Follow-up commitment granularity** (fd-conversational-ai-personality): "I'm going to try" and "I will" are treated identically. Add commitment-strength detection and only proactively follow up on firm commitments.

### Privacy and Trust

- **Contradiction registry weaponization risk** (fd-personal-ai-privacy-trust): Contradictions are therapeutically powerful but represent an attack surface. Add threat model covering breach, legal discovery, and access controls. Contradictions should be encrypted at rest.

---

## Parallel-Discipline Insights (Track B)

### Concierge Medicine: Domain-triggered intake

**Practice:** Structured intake assessment at the start of every patient relationship, calibrated by clinical domain.
**Mapping:** When a user first engages with a new use case domain (first product recommendation request), run a brief contextual intake (3-5 conversational questions) establishing minimum context for that domain. Store results with domain tags. This avoids the sudden-barrage problem when a user with 20 cognitive augmentation sessions asks for their first product recommendation.

### Concierge Medicine: Domain-specific follow-up cadence

**Practice:** Follow-up intervals rigorously calibrated to condition type (post-surgical: 48 hours, chronic: quarterly).
**Mapping:** Career decisions need 2-4 week follow-up, product recommendations need 2-3 day follow-up, learning goals need spaced-repetition intervals, pattern awareness reflections should be monthly. Add a domain-aware cadence table.

### Concierge Medicine: Causal chain reasoning in cross-domain synthesis

**Practice:** Integrative diagnosis models feedback loops, not just thematic similarity.
**Mapping:** "Career, side project, and gym all seem about the same tension" is correlation. A concierge physician would identify: work stress causes sleep issues, which reduce exercise motivation, which worsens work performance via reduced confidence. Add causal chain reasoning using Donella Meadows' stock-and-flow vocabulary.

### Wealth Advisory: Stated vs. revealed preference reconciliation for commerce

**Practice:** Behavioral finance's central insight: people systematically misreport their own preferences.
**Mapping:** Extend the contradiction registry explicitly to commerce-relevant preferences. When a stated/revealed gap affects recommendations, surface the contradiction before recommending: "You've mentioned you prefer minimalist design, but I've noticed you tend to buy more ornate things — which should I optimize for?"

### Wealth Advisory: Duty of care proportional to context depth

**Practice:** Fiduciary obligation arises from information asymmetry and is proportional to the advisor's knowledge depth.
**Mapping:** Add an "Obligations from Context Depth" principle to PHILOSOPHY.md. The deeper the profile, the greater the obligation to use it in the user's interest. This is the philosophical foundation making suitability and disclosure requirements coherent rather than ad hoc.

### Museum Design: Gallery mode for receptive browsing

**Practice:** Great museums support multiple visitor modes: guided tour, audio guide, free exploration.
**Mapping:** Add a "gallery mode" entry point. Users trigger it explicitly ("show me things") or the system offers it at appropriate moments. In gallery mode, the agent surfaces curated adjacencies with no call to action. The Robinson window-shopping experience needs a conversational affordance.

### Museum Design: Commerce as extension of exhibition

**Practice:** The Exploratorium makes the gift shop feel like an extension of exhibits — products ARE experiments.
**Mapping:** Recommendations should feel like thinking tools: a book applying the lens just learned, a physical tool embodying a framework. Never interrupt cognitive augmentation with a recommendation. Recommendations live in their own temporal space.

### Intelligence Analysis: Signal-to-noise calibration by source domain

**Practice:** Different collection methods produce different signal-to-noise ratios (SIGINT vs. HUMINT).
**Mapping:** Tag profile observations with source domain. Cognitive augmentation conversations are high-signal; product browsing is high-noise. Apply domain-appropriate weighting — a casual product mention is not a core value expression.

### Intelligence Analysis: Puzzle vs. mystery routing

**Practice:** Treverton's distinction: puzzles have answers findable with more information; mysteries are genuinely uncertain.
**Mapping:** Product recommendations are mostly puzzles (there is a best product). Career decisions are mostly mysteries (no objectively right answer). Layer this on Cynefin to set expectations and route between recommendation and augmentation modes.

---

## Structural Insights (Track C)

### Persian Carpet Weaving: Shared warp and weft across use cases

**Isomorphism:** The invisible structural foundation (warp/weft) that all carpet motifs depend on.
**Open question:** Does the entity layer's four-category taxonomy (Stated/Revealed/Submerged/Warm data) extend naturally to product recommendation context, or does ambient recommendation require entity categories the current schema cannot express? Purchase history, aesthetic preferences, budget constraints, and brand affinities may need their own entity types.

### Persian Carpet Weaving: Productive variation (abrash)

**Isomorphism:** Hand-dyed wool's subtle color variation is prized because it signals warmth and human craft.
**Open question:** Should use cases have deliberately different interaction textures? Cognitive augmentation as deep conversation with a sharp consultant, ambient recommendations as window shopping with a knowledgeable friend, growth tracking as quarterly review with a watching mentor, pattern awareness as sudden surprising insight. Style mirroring adapts to the user but not necessarily to the use case mode.

### Chinese Lacquerware: Context maturity weighting

**Isomorphism:** Many thin layers cured separately are stronger than fewer thick layers. Temporal spacing creates structural integrity the material properties alone cannot achieve.
**Improvement:** Weight cross-session patterns higher than within-session patterns for constitutional use cases. A pattern confirmed by behavior across three sessions over a month is structurally stronger than the same pattern expressed three times in one conversation. Add a "context maturity" dimension to the profile.

### Chinese Lacquerware: Honest value curve communication

**Isomorphism:** Most lacquer layers are invisible in the final product, but their contribution is structural, not aesthetic. The artisan does not pretend they are unnecessary.
**Improvement:** Design user-facing communication of accumulation phases: "I'm learning what matters to you — I'll start surfacing things when I'm confident they'll be useful, not before." This aligns with anti-dependency: honest about limitations rather than appearing omniscient from day one.

### Gamelan: The inner melody (lagu batin)

**Isomorphism:** The melody no single instrument plays but all instruments imply through interlocking parts.
**Open question:** When cognitive augmentation, ambient recommendations, learning/growth, and pattern awareness operate together, what is the emergent capability none produces alone? If the answer is just "Auraken is helpful in many ways," there is no inner melody — and the product is four features in a trenchcoat rather than a life operating system.

### Constitutional Herbalism: Symptomatic-to-constitutional escalation detection

**Isomorphism:** Three headaches in a month with the same presentation suggest a constitutional issue, not three independent symptoms.
**Improvement:** When shallow interactions cluster around the same theme (three product queries in the same category, repeated simple reframes for the same problem type), surface the pattern: "You've asked about productivity tools three times now. Want to dig into what's behind the search?"

### Constitutional Herbalism: Acute-before-constitutional sequencing

**Isomorphism:** Address acute symptoms before beginning constitutional work. A patient with acute bronchitis gets antimicrobials first, then constitutional assessment.
**Improvement:** When OODARC detects acute distress (Chaotic domain, emotional intensity, urgency language), restrict to symptomatic engagement — short, grounding, actionable — before shifting to constitutional depth. The constitutional observation can be noted internally but not surfaced until the acute phase resolves.

---

## Frontier Patterns (Track D)

### Ayurvedic Constitution: Dual synthesis summaries (Prakriti-Vikriti)

**Source:** 5,000-year-old distinction between innate constitution (never changes) and current imbalance (fluctuates with circumstances).
**Mechanism:** The synthesis layer should generate two profiles: a slow-moving constitutional summary and a fast-moving situational overlay. Lens selection draws on both but weights constitutional for framework choice and situational for conversation tone.
**Design direction:** Add `temporal_stability` field to entities. This is the most architecturally concrete finding from Track D and directly fixes a profile contamination failure mode.

### Ayurvedic Constitution: Cognitive receptivity modulates lens delivery

**Source:** Same herb (ashwagandha) prescribed at radically different dosages depending on constitution.
**Mechanism:** A narrative-intuitive user should receive sunk-cost analysis wrapped in story; an analytical user gets structured decomposition. Same lens, different delivery form.
**Design direction:** Add `cognitive_receptivity` dimension (analytical/narrative/somatic/dialogic) derived from conversation patterns. Lens application reads this to modulate delivery register.

### Ayurvedic Constitution: Cyclical cognitive rhythms

**Source:** Dinacharya/ritucharya — the same person thinks differently at different times of day and season.
**Mechanism:** A user sending analytical messages in the morning and emotional messages late at night is transmitting cognitive rhythm data the system could use. When a complex topic is raised at 11 PM, the agent might note: "This is a big one — want to dig in now, or flag it for when you're in a different headspace?"
**Design direction:** Temporal pattern extraction from message timestamps. Not time management — cognitive rhythm awareness.

### Kampo Pattern Recognition: Lens combination (go-ho)

**Source:** Principled combination of two complementary formulas, not polypharmacy.
**Mechanism:** Complex problems often require two lenses held simultaneously. Career frustration that is both a principal-agent problem and a pace-layer problem needs a compound perspective: "Renegotiate the relationship to align incentives at the institution's natural pace of change." But some combinations are dangerous — sunk-cost analysis combined with commitment-consistency creates a contradictory frame.
**Design direction:** Formalize lens compatibility in the connection graph. Type each connection as complementary (safe to combine), sequential (apply A then B), or contradictory (never combine).

### Kampo Pattern Recognition: Problem stage tracking (acute/chronic)

**Source:** The same underlying condition presents as different Sho depending on its stage. Acute-stage treatment applied to chronic-stage presentation is ineffective or harmful.
**Mechanism:** A career dissatisfaction raised for the first time and the same issue raised for the fifth time over three months both match the same lens triggers but need fundamentally different approaches. First mention: exploratory mapping. Chronic (3+ times without change): confrontation with the pattern: "We've talked about this five times. Each time you generate insight and nothing changes. What's that about?"
**Design direction:** Add `problem_stage` tracking: first_mention, recurring, escalating, chronic, acute_on_chronic. Stage biases lens selection toward different approaches.

### Kampo Pattern Recognition: Recommendation receptivity state (kyo/jitsu)

**Source:** Kyo-sho (deficiency, gentle treatment) vs. jitsu-sho (excess, strong treatment).
**Mechanism:** Formalizes the Robinson NTS window-shopping insight within a constitutional framework. Some users/moments are kyo regarding recommendations (want ambient awareness, resist persuasion). Others are jitsu (know what they want, want efficient execution). Default to kyo. Shift to jitsu only on active-intent signals.
**Design direction:** Per-domain recommendation receptivity state in the profile. This transforms Robinson's vibes-based design heuristic into a formal classification with operational implications.

### Inuit Siku: Active model invalidation probing

**Source:** The experienced hunter's most dangerous mental state is confident reliance on an outdated model. Response: periodically test ice with a harpoon.
**Mechanism:** Even during continuous engagement, the agent should periodically probe specific profile assumptions: "Last month you said career growth was your top priority. Is that still true?" Not a survey — organic conversational probes. Increase probe frequency after detected life events; decrease during stable periods.
**Design direction:** Implement "harpoon test" mechanism: periodically select a high-weight profile entity, generate a targeted conversational probe for its continued validity. On contradiction, trigger re-evaluation cascade for connected entities.

### Inuit Siku: Decay half-lives by entity type

**Source:** Sea ice observations are time-stamped and decaying. Recent observations dominate; older ones inform background context.
**Mechanism:** Behavioral patterns: half-life of weeks. Stated preferences: months. Emotional states: hours. The synthesis layer should weight entities by recency according to their type's half-life.
**Design direction:** This implements the Prakriti-Vikriti distinction through a continuous mechanism rather than a binary classification. Use both: categorical labels for conceptual clarity, continuous decay for operational weighting.

---

## Synthesis Assessment

**Overall quality of the target:** Auraken's vision and philosophy documents are unusually strong — the core thesis (cognitive augmentation through dynamic lens selection with deep personal context) is distinctive and well-argued. The architectural gaps are not conceptual failures but rather the natural consequence of expanding from a single use case (cognitive augmentation) to a multi-domain life operating system without yet defining the coordination layer between domains.

**Highest-leverage improvement:** Define the use case coordination layer — the meta-architecture that manages transitions, depth classification, trust pacing, and mode switching across Auraken's four domains. This is the 4/4 convergent finding. Every track independently identified its absence. Without it, the four domains will be designed by different sprints with locally coherent but globally conflicting interaction patterns. The first user who experiences cognitive augmentation and ambient recommendations in the same session will feel the seam.

**Most surprising finding:** The Kampo near-miss/contraindication pattern (Track D, fd-kampo-sho-pattern-recognition). Every AI recommendation system optimizes for "when to apply." No system formalizes "when NOT to apply" — explicit contraindication signatures on each lens that catch cases where the pattern looks right but the intervention would cause harm. This emerged from a 1,000-year-old medical tradition and addresses a failure mode (delayed, invisible harm from confident wrong framing) that is unique to low-feedback cognitive augmentation domains and invisible to conventional recommender system analysis.

**Semantic distance value:** The outer tracks (C/D) contributed qualitatively different insights that inner tracks (A/B) could not have produced. Track A and B identified gaps in what exists (missing features, missing safeguards, missing processes). Track C identified structural relationships between use cases that require meta-architectural thinking — the carpet cartoon, the gamelan colotomy, the lacquerware curing time. Track D identified failure modes invisible to closer domains: profile contamination from temporary states (Ayurveda), near-miss harmful interventions (Kampo), and the counter-intuitive value of refusing to act (Siku). The inner melody question (Track C, gamelan) and the no-go decision (Track D, Siku) are findings no adjacent or orthogonal domain would surface because they require traditions where NOT doing something is itself a sophisticated act. The 4-track structure earned its cost.
