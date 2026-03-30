---
artifact_type: flux-drive-findings
track: adjacent
target: apps/Auraken/
date: 2026-03-30
agents: [fd-recommender-system-architecture, fd-cognitive-augmentation-science, fd-conversational-ai-personality, fd-personal-ai-privacy-trust, fd-second-brain-knowledge-architecture]
---

# Auraken Use Case Landscape -- Adjacent Domain Findings

## Finding 1: No Cold-Start Strategy for Dynamic Lens Selection

**Severity:** P1
**Agent:** fd-recommender-system-architecture

**Description:** The PRD claims dynamic lens selection as the core technical differentiator ("Novel -- No One Does This") but provides no fallback strategy for conversations 1-3 before the cognitive profile has accumulated meaningful signal. The selection pipeline (PRD lines 121-130) lists five inputs -- Cynefin pre-filter, problem description, accumulated personal context, semantic similarity, and RPD pattern matching -- but three of these (accumulated context, RPD, and personal semantic matching) require a profile that does not exist for new users. In a recommendation system, this is the cold-start problem, and it is the single most studied failure mode in the field.

**Evidence:** PRD "Dynamic Selection" section (lines 121-130) lists "Accumulated personal context (thinking patterns, values, blind spots)" as input #3 and "Recognition-primed pattern matching" as input #5. Both are profile-dependent. The Open Questions section (line 376) asks "How many lenses at launch?" but never asks "How does selection work before the profile exists?" Journey 1 (lines 134-151) describes the first conversation but does not specify how lens selection operates without accumulated context -- it assumes the agent can "deliver a reframe" (line 146) without explaining how it selects which reframe.

**Failure scenario:** A new user messages Auraken for the first time. Without accumulated context, the selection pipeline degenerates to Cynefin pre-filter + generic semantic matching, which is no better than keyword search over a framework database. The user receives a generic or poorly-fitted reframe, the "aha" moment fails, and the 48-hour return rate (target: >40%) collapses. The first-session experience is the only chance to demonstrate that dynamic selection outperforms manual selection, and it fails precisely when it matters most.

**Recommendation:** Add an explicit cold-start tier to the lens selection pipeline in the PRD. For conversations 1-3: popularity-based ranking (lenses that have been most successful across all users) weighted by Cynefin domain, with an onboarding signal collection step (2-3 calibration questions about the user's domain, thinking style, and current challenge type) that bootstraps a minimal profile for content-based selection by conversation 2. Document this as a designed degradation, not a gap.

---

## Finding 2: No Exploration Mechanism in Lens Selection

**Severity:** P2
**Agent:** fd-recommender-system-architecture

**Description:** The lens selection system describes a pipeline that converges toward lenses matching the user's profile and problem, but contains no exploration mechanism. In recommender systems, pure exploitation produces filter bubbles -- the system stops surfacing novel frameworks because it has no incentive to try unfamiliar ones. This directly contradicts the stated goal of "expanding lens repertoire" (VISION.md line 71) and the v1.5 roadmap of growing the lens library.

**Evidence:** VISION.md (lines 25-26) describes dynamic lens selection as "recognitional pattern-matching -- the way experts see situations through frameworks rather than choosing frameworks for situations." This is a pure exploitation metaphor drawn from Klein's RPD. There is no mention of epsilon-greedy, Thompson sampling, diversity constraints, or any mechanism for surfacing lenses the user has never encountered. The PRD's competitive positioning (line 363) claims Auraken adds "dynamic lens selection" vs. competitors, but if selection converges on a narrow set, the user gets the same 5-8 frameworks repeatedly.

**Failure scenario:** After 20-30 conversations, the system has identified that the user responds well to sunk cost analysis, principal-agent framing, and pace layers. It stops surfacing Cynefin domain classification, enabling constraints, or cognitive light cones because those have lower predicted engagement. The user's lens repertoire stagnates at exactly the frameworks they already knew. The "expanding lens repertoire" artifact (VISION.md line 71) never materializes.

**Recommendation:** Add a diversity constraint to lens selection: at minimum, 20% of lens applications should be from frameworks the user has not previously encountered, with a decay toward exploitation as the user's repertoire grows. Consider a "lens of the week" serendipity mechanism that proactively introduces an unfamiliar framework when the problem signature permits, separate from the primary selection pipeline.

---

## Finding 3: Undefined Feedback Signal for Lens Selection Quality

**Severity:** P2
**Agent:** fd-recommender-system-architecture

**Description:** The PRD's OODARC Reflect phase (VISION.md lines 35) asks "Did it help? Did the user's thinking shift?" but provides no operational definition of how the system detects this. PHILOSOPHY.md Principle 10 states feedback should be "invisible" -- no structured surveys, capturing signals only when users "naturally express what worked or didn't." This creates a feedback loop integrity problem: the system cannot improve lens selection quality over time if it has no calibrated signal for whether a selection was good.

**Evidence:** PHILOSOPHY.md (lines 46-47): "No structured surveys. When users naturally express what worked or didn't, the system captures it." PRD Reflect phase (VISION.md line 35): "Did it help? Did the user's thinking shift? What did we learn about how this person reasons?" These are questions, not measurements. The Key Metrics table (PRD lines 342-349) lists "Independent lens application" as a metric but marks it as "Detectable" with "Conversational signal analysis" -- no operational definition of what signals constitute detection.

**Failure scenario:** Without calibrated feedback, lens selection cannot improve. The system may develop a degenerate feedback loop: lenses that produce longer conversations appear "successful" (user engaged more), but lengthy conversations may indicate confusion, not insight. Alternatively, lenses that produce short "aha" exchanges appear unsuccessful because the conversation ended quickly. The optimization target is undefined, so the system optimizes for a proxy that may be anti-correlated with actual cognitive value.

**Recommendation:** Define 3-5 implicit feedback signals with calibration: (1) user self-correction within 2 turns of lens application (positive), (2) user explicitly asks "what framework is that?" (positive -- curiosity), (3) user changes topic immediately after reframe (negative -- didn't land), (4) user references the reframe in a future session (strong positive), (5) user applies the lens independently in a future conversation (strongest positive). Weight these signals and use them to update lens-problem affinity scores.

---

## Finding 4: Lens Selection Paradox -- Agent Selects What the User Should Learn to Select

**Severity:** P1
**Agent:** fd-cognitive-augmentation-science

**Description:** There is a structural contradiction between the core augmentation thesis and the core technical feature. VISION.md (line 13) states the gap: "No system implements dynamic lens selection -- all framework tools require manual framework choice." Auraken's differentiator is that it selects frameworks autonomously. But PHILOSOPHY.md Principle 7 states: "Anti-dependency by design. Track when users apply frameworks independently." If the goal is for users to learn to select frameworks themselves, then automating framework selection removes the practice opportunity. This is the cognitive offloading problem cited in the PRD itself (PHILOSOPHY.md Principle 2, referencing the MIT brain connectivity study).

**Evidence:** PHILOSOPHY.md Principle 2 (line 15): "The MIT brain connectivity study shows cognition scales down with AI support." VISION.md (line 25): "dynamic lens selection... No existing system does this autonomously." PRD v2.0 roadmap (line 314): "Independent lens application detection -- does the user apply frameworks without prompting?" The system trains users to receive frameworks rather than select them, then measures whether they select frameworks independently -- but provides no scaffolded pathway for the selection skill itself to transfer.

**Failure scenario:** After 6 months of use, the user can recognize and name frameworks when prompted but cannot independently select which framework applies to a new problem without Auraken. The augmentation thesis ("operates at B and C levels") fails because framework selection -- the B-level skill -- was never practiced by the user, only consumed. The agent celebrates "independent lens application" when the user names a framework mid-conversation, but this is recognition, not selection. The user cannot do the hardest part (choosing the right framework for a novel problem) without the agent.

**Recommendation:** Add a progressive scaffolding model to the PRD for lens selection specifically. Early conversations: agent selects lens invisibly. After 10+ conversations with a lens, agent offers a choice: "This could be a sunk cost problem or a principal-agent problem -- which framing feels more useful?" After 20+ conversations: agent describes the problem signature and asks the user to suggest a framework. Track whether the user's selection matches the agent's and use divergence as a learning signal. This turns lens selection into a practiced skill, not an automated service.

---

## Finding 5: Cognitive Augmentation Metrics Are Self-Referential

**Severity:** P2
**Agent:** fd-cognitive-augmentation-science

**Description:** Every metric for measuring cognitive augmentation in the PRD (lines 342-349) is detected by the system that claims to produce the augmentation. "Independent lens application" is detected by "conversational signal analysis" -- the agent itself interprets whether the user applied a framework independently. "User-initiated reframes" are counted by the agent. There is no external validation, no control condition, and no way to distinguish genuine cognitive growth from the user learning to use framework language in conversation with an agent that rewards framework language.

**Evidence:** PRD Key Metrics table (lines 342-349): "Independent lens application -- Detectable -- Conversational signal analysis." "User-initiated reframes -- Increasing trend -- Session-over-session tracking." Both are measured by the agent interpreting its own conversations. Journey 4 (line 174): "the agent tracks this: 'You just did a sunk cost analysis without me prompting it'" -- the agent is both the intervention and the measurement instrument, a design that no cognitive scientist would accept as evidence of augmentation.

**Failure scenario:** The system reports increasing "independent lens application" and "user-initiated reframes" over 6 months, which is interpreted as evidence that Auraken produces genuine cognitive augmentation. In reality, the user has learned to talk about problems using framework language because the agent reinforces framework-laden conversation. Outside of Auraken conversations, the user's actual decision-making quality has not changed. The product ships growth metrics to investors that do not reflect real-world cognitive improvement.

**Recommendation:** Add at least one external validation approach to the PRD. Options: (1) periodic self-assessment prompts where the user evaluates their own decision quality on recent real-world decisions (not within Auraken), (2) journaling prompts that ask the user to analyze a problem on their own before discussing with Auraken, comparing framework usage in independent vs. aided analysis, (3) explicit acknowledgment in the PRD that conversational signal analysis is a proxy metric, not a validated measure of cognitive augmentation, with a research roadmap for stronger validation.

---

## Finding 6: OODARC Model Lacks Empirical Grounding as Conversation Engine

**Severity:** P3
**Agent:** fd-cognitive-augmentation-science

**Description:** OODARC is presented as an extension of Boyd's OODA loop with an explicit Reflect phase. Boyd's OODA was designed for adversarial military decision-making under time pressure, not collaborative sensemaking conversations. The sensemaking literature (Weick, which is cited in VISION.md line 108) emphasizes that sensemaking is retrospective, social, enactive, and driven by plausibility -- properties that resist being decomposed into sequential phases. Using OODA as the basis for a conversation engine imports assumptions (adversarial tempo, decisional urgency, individual cognition) that may conflict with the collaborative, exploratory nature of the conversations Auraken aims to facilitate.

**Evidence:** VISION.md (lines 28-36) describes OODARC phases. Line 108 cites Weick: "Sensemaking is retrospective, enactive, driven by plausibility not accuracy." Boyd's OODA was specifically about competitive tempo advantage -- "acting faster than the opponent can observe and orient." The adaptive timescale depth (PRD lines 68-79) partially addresses this by allowing depth variation, but the fundamental phase model remains sequential (Observe-Orient-Decide-Act-Reflect), which may impose false structure on naturally recursive or parallel cognitive processes.

**Recommendation:** This is a naming and framing issue, not a functional one. The adaptive timescale depth already provides flexibility. Consider framing OODARC as a "design heuristic for conversation engineering" rather than a "cognitive model," and acknowledge in the docs that actual conversations will be recursive and non-linear. Alternatively, investigate whether the Weick sensemaking properties (enactive, retrospective, social, ongoing, focused on extracted cues, driven by plausibility) offer a better framework for the conversation engine.

---

## Finding 7: Style Mirroring Has No Circuit Breaker for Distress Amplification

**Severity:** P1
**Agent:** fd-conversational-ai-personality

**Description:** Style mirroring is described as a default behavior (PRD line 38-41, PHILOSOPHY.md Principle 1) where the agent "learns and mirrors the user's own speech and writing style." No boundary conditions are specified. When a user is in distress -- catastrophizing, using self-deprecating language, expressing hopelessness -- mirroring that style amplifies the negative affect rather than breaking the loop. This is well-documented in therapeutic contexts: matching a distressed person's affect validates their emotional state, but matching their cognitive distortions reinforces those distortions.

**Evidence:** PRD "Style Mirroring" section (lines 38-41): "By default, Auraken learns and mirrors the user's own speech and writing style. The agent should feel like an extension of how the user already thinks and communicates." PHILOSOPHY.md Principle 7 (line 28): "Profile echoes use the user's language. If they say 'stuck,' don't reframe as 'on a journey of growth.'" There is no mention of affect detection, mirroring ceilings, or registers that should not be mirrored. The Laban Movement Analysis framework (PRD lines 44-51) mentions "Weight (Light/Strong)" but does not address what happens when the weight is distress.

**Failure scenario:** User messages Auraken in crisis: "Everything is falling apart. I'm a complete failure at work, my relationship is dying, and I can't even get out of bed." Style mirroring produces a response in the same catastrophizing register: "It sounds like things are really collapsing across multiple fronts." This validates the emotional state but reinforces the all-or-nothing thinking pattern. The agent has become a distortion amplifier instead of a cognitive camera. Worse, the PRD explicitly positions "Values autonomy at work but defers in relationships" as warm data, but doesn't address what to do when the data is "I'm a failure everywhere."

**Recommendation:** Add an affect detection layer and a mirroring ceiling to the style mirroring specification. Define registers that are mirrored (vocabulary, sentence structure, humor, directness) vs. registers that are not mirrored (distress intensity, catastrophizing patterns, self-deprecation). When distress is detected above a threshold, the agent should maintain warmth and validation of the emotion while shifting cognitive register -- acknowledging the feeling without matching the cognitive frame. Add this as a design constraint in PHILOSOPHY.md alongside Principle 7.

---

## Finding 8: Negative Feedback Journey Is Explicitly Undesigned

**Severity:** P1
**Agent:** fd-conversational-ai-personality

**Description:** The PRD explicitly acknowledges a missing journey (line 239): "Negative feedback -- When a reframe lands wrong or feels patronizing." This is not just a gap -- it is the single highest-risk conversational moment. When an agent that claims to understand "how you think" delivers a reframe that feels wrong, the user's trust in the entire profile and the agent's competence collapses. Without a designed recovery path, the agent will either double down (alienating), over-apologize (sycophantic), or deflect (dismissive). All three destroy the "best consultant you've ever met" positioning.

**Evidence:** PRD line 239: "Missing Journey (To Be Designed) -- Negative feedback -- When a reframe lands wrong or feels patronizing." The seven designed journeys (lines 134-236) cover first conversation, ongoing engagement, follow-up, cognitive growth, lapsed user, cognitive mirror, and multi-problem juggling. None address the scenario where the agent's core value proposition (the reframe) fails. PHILOSOPHY.md Principle 5 (line 27) says "questions are the product" -- but when the question is wrong, the product has failed, and there is no error handling.

**Failure scenario:** User describes a career frustration. Auraken selects a principal-agent lens and says "What if the real issue is that your interests and your manager's interests aren't aligned?" The user responds: "That's not it at all -- we're perfectly aligned, the problem is the tooling." The agent has no designed recovery. It either tries another lens (feels like cycling through a toolkit), apologizes and asks for clarification (loses authority), or insists on the framing (alienates). The "PM on first day" personality has no protocol for being wrong, which is exactly the situation a PM on their first day encounters most.

**Recommendation:** Design Journey 8: Failed Reframe Recovery. Key elements: (1) Acknowledge the miss without excessive apology: "Fair enough -- I was reading that differently. Tell me more about the tooling." (2) Use the failure as profile data: the fact that principal-agent framing didn't fit here is itself a signal about the user's reasoning. (3) Shift to Mirror mode (Journey 6) after a failed reframe -- ask the user to explain their view rather than offering another framework. (4) Never try two frameworks in rapid succession -- it breaks the "consultant" illusion and reveals the toolkit.

---

## Finding 9: Follow-Up Tracking Lacks User Controls for Commitment Granularity

**Severity:** P2
**Agent:** fd-conversational-ai-personality

**Description:** Journey 3 (lines 162-169) describes commitment tracking and follow-up but makes no distinction between types of commitments. "I'm going to try blocking mornings for deep work" (a tentative intention) and "I will submit my resignation on Monday" (a firm commitment) should have very different follow-up behaviors. The PRD treats all stated future actions as follow-up-worthy, creating a surveillance dynamic where casual mentions of intent are tracked and revisited.

**Evidence:** PRD Journey 3 (lines 162-169): "After a conversation where the user commits to an action ('I'm going to try blocking mornings for deep work'), Auraken notes the commitment." The example uses "going to try" -- the weakest form of commitment -- yet treats it identically to firm commitments. The design principles for Journey 3 say follow-up should be "genuinely curious, not judgmental" (line 168), but even non-judgmental follow-up on a casual mention feels like surveillance. There is no user-facing mechanism to say "don't track that" or to distinguish intentions from commitments.

**Recommendation:** Add commitment granularity to the follow-up system: (1) detect strength of commitment language (tentative: "I might try," "I'm thinking about" vs. firm: "I will," "I've decided to"), (2) only proactively follow up on firm commitments, (3) for tentative intentions, note them in the profile but only reference them if the user raises the topic again, (4) add an explicit opt-out: "Don't track that" or similar phrase that removes a commitment from the follow-up queue.

---

## Finding 10: No Profile Deletion Mechanism or Data Lifecycle Policy

**Severity:** P0
**Agent:** fd-personal-ai-privacy-trust

**Description:** The PRD describes the cognitive profile as "the moat" (PHILOSOPHY.md Principle 6, VISION.md lines 78-79) and the three-tier profile architecture stores thinking patterns, contradictions, cross-domain connections, and "submerged patterns that surprise even the user" (PRD Entity layer, line 329). There is no mention anywhere in the three documents of profile deletion, data export, data lifecycle, retention limits, or user data management. This is not a gap in a feature list -- it is a GDPR Article 17 (right to erasure) and Article 20 (right to portability) compliance issue for any user in the EU, and a basic trust issue for all users.

**Evidence:** VISION.md "Defensibility" section (lines 78-79): "The cognitive profile is the second moat." PRD Profile Architecture (lines 326-338) describes three tiers of stored data including "Submerged -- Patterns that surface through conversation and surprise even the user." PRD v3.0 roadmap (line 320) mentions "Profile export and portability" -- but this is a v3.0 feature, meaning v1.0 and v2.0 ship with no data portability. No mention of deletion in any document. Open Questions (lines 375-382) do not include any data governance questions.

**Failure scenario:** A user has 6 months of conversations with Auraken. They want to stop using the service. They ask to delete their data. There is no mechanism to do so. The episode layer is "immutable" (PRD line 328), the entity layer has temporal ranges, and the synthesis layer is derived. A naive deletion of the synthesis layer leaves thinking pattern data in the entity and episode layers. The user has no way to know what is stored about them, no way to export it, and no way to delete it. If the user is in the EU, this is a GDPR violation from day one.

**Recommendation:** Add a Data Governance section to the PRD before v1.0, covering: (1) right to access -- user can request a full export of their profile (all three tiers) in human-readable format, (2) right to erasure -- user can request complete deletion, which cascades through all three tiers including immutable episodes (which must be made deletable, not truly immutable), (3) right to rectification -- user can dispute and correct entity-layer facts about their thinking patterns, (4) data lifecycle -- retention limits for episodes (e.g., episodes older than 2 years are summarized and raw data deleted), (5) purpose limitation -- cognitive profile data used for augmentation cannot be used for product recommendations without separate consent.

---

## Finding 11: Cross-Context Linking Violates Contextual Integrity Without Consent Controls

**Severity:** P1
**Agent:** fd-personal-ai-privacy-trust

**Description:** Auraken's core value proposition includes cross-domain pattern detection -- connecting what the user says about work to what they say about relationships to what they say about health. Helen Nissenbaum's contextual integrity framework holds that information shared in one context has implicit norms governing its flow to other contexts. When a user discusses work frustration, they are not consenting to that information being linked to their relationship dynamics. The PRD presents this cross-context linking as the product's highest-value feature (Journey 2 line 158, Journey 7 lines 226-227) without acknowledging that it violates the informational norms the user likely assumes.

**Evidence:** PRD Journey 2 (line 158): "the 'uncanny' moment -- the agent surfaces a cross-domain connection the user hadn't made: 'You handle uncertainty at work the same way you handle it in your relationship -- by over-planning.'" PHILOSOPHY.md Principle 3 (line 18): "Contradictions are features... cross-domain tensions are where the most valuable insights live." The warm data concept (PRD line 332) explicitly stores "transcontextual connections across life domains." No mechanism exists for the user to compartmentalize domains -- to say "don't connect my work conversations to my relationship conversations."

**Failure scenario:** User discusses relationship difficulties with Auraken. In a later conversation about a work decision, Auraken surfaces: "This pattern -- avoiding confrontation by over-planning -- is the same thing you described with your partner." The user feels violated. They shared relationship information in an intimate context and did not expect it to be used to analyze their work behavior. The "uncanny moment" described in Journey 2 tips from insightful to invasive. The user loses trust not because the insight was wrong, but because they never consented to cross-domain inference.

**Recommendation:** Add domain-boundary controls to the profile architecture: (1) allow users to tag conversation topics as domain-specific ("this is about my relationship"), (2) cross-domain linking is opt-in, not default -- the agent must ask before connecting domains for the first time ("I notice a pattern that connects your work situation to something you mentioned about your relationship -- would you like me to explore that?"), (3) the user can retroactively compartmentalize: "don't use my relationship conversations to inform work analysis." This preserves the cross-domain insight capability while respecting contextual integrity.

---

## Finding 12: Contradiction Registry Creates Weaponization Risk Without Access Controls

**Severity:** P2
**Agent:** fd-personal-ai-privacy-trust

**Description:** The PRD stores contradictions as features (PHILOSOPHY.md Principle 3, PRD Entity layer "Contradiction registry," line 283). These contradictions -- "values autonomy at work but defers in relationships" -- are therapeutically powerful but represent an attack surface if access is ever shared. The PRD mentions no access controls, no sharing model, and no consideration of scenarios where the profile is accessed by someone other than the user (a partner, an employer, a legal discovery process, or an attacker in a data breach).

**Evidence:** PRD line 283: "Contradiction registry -- conflicting patterns tracked as features, not bugs." VISION.md line 70: "'values autonomy at work but defers in relationships, and this tension surfaces as procrastination on joint financial decisions.'" This is extremely sensitive information that could be used manipulatively if accessed by a bad actor. The v3.0 roadmap mentions "Profile export and portability" (line 320) but no access control model. No threat model for the contradiction registry exists in any document.

**Recommendation:** Add a threat model section to the PRD addressing: (1) who can access the contradiction registry (user only, never shared with third parties including partners or employers), (2) what happens in a data breach (contradictions are the highest-sensitivity data and should be encrypted at rest with user-controlled keys), (3) legal discovery -- what is the response to a subpoena for a user's cognitive profile? (4) the contradiction registry should never be surfaced in aggregate or used for product recommendations, even internally.

---

## Finding 13: Entity Extraction Precision Undefined -- Risk of Confident Wrong Profile Claims

**Severity:** P1
**Agent:** fd-second-brain-knowledge-architecture

**Description:** The profile architecture describes entity extraction with four categories (Stated, Revealed, Submerged, Warm data -- PRD lines 329-333) but provides no precision/recall targets, confidence thresholds, or minimum evidence requirements. "Revealed" entities -- patterns inferred from behavior -- and "Submerged" entities -- "patterns that surface through conversation and surprise even the user" -- are the most powerful but also the most error-prone. An LLM extracting thinking patterns from conversation will generate false positives, and when these are injected into the synthesis layer and presented back to the user as confident observations, they undermine the entire profile's credibility.

**Evidence:** PRD Entity layer (lines 329-333): "Stated -- What users say about how they think," "Revealed -- What behavior shows," "Submerged -- Patterns that surface through conversation and surprise even the user." No confidence scoring is mentioned. The synthesis layer (line 334) generates "compact summaries (~300-500 tokens) for system prompt injection" -- meaning extracted entities are compressed and injected into every future conversation without the user seeing or validating the individual entities. Journey 2 (line 158) describes the agent making cross-domain claims: "You handle uncertainty at work the same way you handle it in your relationship" -- if this entity was extracted with low confidence, the agent makes a confidently wrong claim about the user's psychology.

**Failure scenario:** After 5 conversations, the LLM extracts a "Revealed" entity: "tends to avoid direct confrontation." This is based on one conversation where the user described a diplomatic approach to a specific work situation. The entity is injected into the synthesis layer. In conversation 6, the user describes assertively confronting a contractor about quality. The agent says: "That's interesting -- you usually avoid direct confrontation. What made this different?" The user has never been told about the entity, never validated it, and the claim is wrong. The agent's credibility collapses.

**Recommendation:** Add to the profile architecture specification: (1) confidence scoring for all extracted entities (high: 3+ conversations supporting, medium: 2 conversations, low: 1 conversation), (2) minimum evidence threshold for entity categories (Stated: 1 instance, Revealed: 3 instances across 2+ sessions, Submerged: 5 instances across 3+ sessions), (3) low-confidence entities are never surfaced as confident claims -- instead, they are phrased as questions: "I've noticed you tend to take a diplomatic approach -- is that generally how you operate, or was that specific to that situation?" (4) user review mechanism: periodically surface entity-layer contents for validation.

---

## Finding 14: Synthesis Layer Token Budget Creates Lossy Compression at Scale

**Severity:** P2
**Agent:** fd-second-brain-knowledge-architecture

**Description:** The synthesis layer generates "compact summaries (~300-500 tokens) for system prompt injection" (PRD line 334). After 100+ conversations spanning career, relationships, health, finances, and creative projects, the full entity graph may contain hundreds of entities with complex interconnections. Compressing this into 300-500 tokens will lose critical nuance, particularly the contradictions and warm data that the docs position as the highest-value data. The fixed token budget means profile quality degrades as conversation volume increases -- the opposite of the stated principle that "the tenth conversation is dramatically better than the first" (PHILOSOPHY.md Principle 9).

**Evidence:** PRD Synthesis layer (line 334): "LLM-generated compact summaries (~300-500 tokens) for system prompt injection. Adaptive structure (FluxMem-inspired): graph memory for complex relational problems, linear for sequential reasoning, narrative for identity questions." The adaptive structure varies format but not budget. After 6 months of weekly conversations (26+ sessions), the entity layer may contain 50+ entities with interconnections. 500 tokens cannot represent 50 entities, their temporal evolution, their contradictions, and their cross-domain links without severe lossy compression.

**Failure scenario:** At month 6, the synthesis layer for a complex user reads: "Systems thinker who values autonomy, tends toward over-planning, has career growth and relationship themes active." This is accurate but so compressed it is useless for dynamic lens selection. The agent loses the nuance that the user over-plans specifically in uncertain domains, values autonomy differently at work vs. home, and has a specific blind spot around sunk costs in creative projects. The synthesis is correct at a headline level but lacks the detail needed for the "uncanny" cross-domain connections that are the product's differentiator.

**Recommendation:** Replace the fixed 300-500 token budget with an adaptive budget model: (1) base synthesis: 300 tokens for core patterns, (2) problem-specific retrieval: when a conversation topic is identified, RAG retrieves relevant entities from the entity layer and appends them to the synthesis (additional 200-500 tokens), (3) maximum total context injection: 1000 tokens, of which 300 is persistent synthesis and 700 is retrieved on-demand. This preserves conversation-speed latency while allowing the profile to scale without lossy compression. The PRD already mentions "Adaptive structure (FluxMem-inspired)" -- extend this to adaptive budget, not just adaptive format.

---

## Finding 15: No Defined Retrieval Pipeline for Mid-Conversation Profile Access

**Severity:** P2
**Agent:** fd-second-brain-knowledge-architecture

**Description:** The PRD describes what is stored (three-tier architecture) and what is injected (synthesis layer summaries) but does not specify how the agent accesses accumulated context mid-conversation when it needs deeper profile information than the synthesis provides. Journey 7 (multi-problem juggling) requires the agent to track 3-4 active threads and surface cross-thread connections -- this requires real-time retrieval from the entity and episode layers, not just the static synthesis injection.

**Evidence:** PRD Profile Architecture (lines 326-338) describes storage tiers. PRD Infrastructure (lines 294-298) lists "PostgreSQL + pgvector for profile storage and lens retrieval." The Open Questions (lines 375-382) include "Warm data extraction: How does the agent reliably detect transcontextual patterns?" but do not address the retrieval pipeline that serves these patterns during conversation. Journey 7 (lines 219-236) requires the agent to "track cross-thread connections in the background" and "maintain a lightweight mental model of thread status" -- but the mechanism for this real-time access is unspecified.

**Recommendation:** Add a Retrieval Architecture section to the PRD specifying: (1) synthesis layer is injected as system prompt context (300-500 tokens, always present), (2) entity-layer RAG is triggered when the agent detects a cross-domain or cross-thread connection opportunity, using pgvector semantic search over entity descriptions, (3) episode-layer retrieval is triggered when the agent needs verbatim evidence for a claim about the user's past statements, (4) maximum retrieval latency target: <500ms to avoid perceptible conversation delay, (5) retrieval caching strategy for active threads to avoid redundant entity-layer queries within a session.

---

## Finding 16: Bi-Temporal Model Cannot Distinguish Changed Mind from Contextual Variation

**Severity:** P2
**Agent:** fd-second-brain-knowledge-architecture

**Description:** The entity layer uses `valid_from`/`valid_until` timestamps (PRD line 329) to track when thinking patterns change. But human thinking patterns are not temporally linear -- a person may be assertive at work and deferential at home simultaneously, or assertive with one manager and deferential with another. The bi-temporal model cannot distinguish between "the user changed from deferential to assertive in March" (temporal change) and "the user is assertive in work contexts and deferential in relationship contexts" (contextual variation). Both would create entities with different validity windows, but they represent fundamentally different profile facts.

**Evidence:** PRD Entity layer (line 329): "Extracted thinking pattern facts with valid_from/valid_until timestamps." PHILOSOPHY.md Principle 3 (line 18): "Real people are contradictory. 'Values autonomy at work but defers in relationships' is warm data, not a bug to fix." The warm data concept explicitly acknowledges contextual variation, but the entity modeling uses temporal windows rather than contextual scoping. The example "values autonomy at work but defers in relationships" would ideally be modeled as two context-scoped entities, not two temporally sequential entities.

**Recommendation:** Extend the entity model with an optional `context_scope` field alongside the temporal fields: `valid_from`, `valid_until`, `context_scope` (e.g., "work," "relationships," "creative projects," null for universal patterns). This allows the system to represent both temporal change and contextual variation without conflating them. Warm data entities would have multiple context scopes linked by a contradiction or tension edge. This is a data model change, not an architecture change -- it adds one nullable column to the entity schema.
