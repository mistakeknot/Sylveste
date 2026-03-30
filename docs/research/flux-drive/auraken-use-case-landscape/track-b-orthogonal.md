---
artifact_type: flux-drive-findings
track: orthogonal
target: apps/Auraken/
date: 2026-03-30
agents: [fd-concierge-medicine-longitudinal-care, fd-wealth-advisory-fiduciary-modeling, fd-museum-experience-ambient-discovery, fd-intelligence-analysis-structured-sensemaking]
---

# Auraken Use Case Landscape -- Track B (Orthogonal Domain Review)

## Agent: fd-concierge-medicine-longitudinal-care

### Finding CM-1: Trust pacing is monolithic across use case domains

**Severity:** P1

**Source discipline:** Concierge medicine -- differential trust-earning protocols by clinical domain.

A concierge physician earns the right to ask about sexual health on a different timeline than they earn the right to discuss diet. The trust ramp is domain-specific: lifestyle questions on visit one, mental health questions only after months of established relationship. Auraken's PM-on-first-day personality (PRD.md, "Agent Personality" section) applies a single trust arc to all use cases. Product recommendations require near-zero trust ("what backpack do you like?") while probing cognitive blind spots or surfacing cross-domain contradictions requires deep relationship trust built over weeks. Treating these identically means either recommendations are gated behind unnecessary trust-building (months before you get a product suggestion) or cognitive augmentation oversteps before trust is earned.

**Failure scenario:** User messages about a purchase decision on day one. Auraken, still in conservative PM-on-first-day mode, asks three mapping questions before offering any product perspective. The user wanted a quick recommendation and gets a therapy intake. Alternatively, the system ramps up trust quickly because recommendations went well, then prematurely surfaces "you keep avoiding financial decisions" based on two conversations.

**Agent:** fd-concierge-medicine-longitudinal-care

**Recommendation:** Add a per-domain trust level to the profile architecture. Each use case domain (cognitive augmentation, product discovery, learning/growth, pattern awareness) should have its own trust tier that advances independently. Define in PRD.md section "Agent Personality" which interaction modes are available at each trust level per domain. Product recommendations can start at low trust; blind-spot surfacing requires high trust.

---

### Finding CM-2: No competence boundary detection or referral mechanism

**Severity:** P1

**Source discipline:** Concierge medicine -- scope of practice and specialist referral protocols.

Every concierge physician maintains a clear mental map of where their competence ends and where they must refer out. When a patient presents symptoms beyond the physician's scope, they do not attempt treatment -- they refer to a specialist and coordinate the handoff. Auraken's PRD.md documents seven user journeys and nine conversation design principles, but none of them address the moment when a user's problem exceeds Auraken's competence. The "Positioning" decision (PRD.md, "Open Questions > Decided") says "Not therapy, not wellness" but provides no mechanism for detecting when a conversation has crossed that boundary.

**Failure scenario:** User starts with a career decision (in scope), conversation reveals the career paralysis is rooted in clinical anxiety or depression. Auraken applies a Cynefin classification and selects a "sunk cost" lens for what is actually a mental health crisis. The system has no protocol for recognizing the boundary or suggesting professional help, and its "preserve cognitive struggle" principle (PHILOSOPHY.md, Principle 2) could actively worsen the situation by increasing cognitive load on someone in distress.

**Agent:** fd-concierge-medicine-longitudinal-care

**Recommendation:** Add a "Competence Boundary" section to PRD.md. Define trigger signals (sustained emotional distress across sessions, self-harm language, clinical symptom patterns, substance dependency indicators). Define the response protocol: acknowledge, do not apply lenses, suggest professional resources, and log the boundary event for profile learning. Add a Journey 8: "Boundary Detection and Referral."

---

### Finding CM-3: Onboarding is implicit rather than structured

**Severity:** P2

**Source discipline:** Concierge medicine -- comprehensive intake assessment.

Concierge medicine begins every patient relationship with a structured intake: medical history, family history, lifestyle, goals, medications. This is not an interrogation -- it is framed as "help me understand you so I can help you better." Auraken's Journey 1 (PRD.md) opens with "What's on your mind?" and builds context organically from whatever the user brings. This works for cognitive augmentation (the original use case) but becomes a problem when expanding to recommendations: the system cannot recommend products without knowing the user's living situation, budget constraints, aesthetic preferences, brand values, and past purchase patterns. These are not things that surface naturally in cognitive augmentation conversations.

**Failure scenario:** After 20 cognitive augmentation sessions over 3 months, user asks for a product recommendation. Auraken has a rich model of how the user thinks but knows nothing about their budget, living space, or product preferences. The system either asks a sudden barrage of contextual questions (breaking the conversational flow) or makes recommendations based on personality-level inferences ("you value autonomy, so here's an off-grid solar panel") that miss practical constraints.

**Agent:** fd-concierge-medicine-longitudinal-care

**Recommendation:** Design a lightweight, domain-triggered intake protocol. When a user first engages with a new use case domain (e.g., first product recommendation request), Auraken runs a brief contextual intake for that domain -- 3-5 questions, framed conversationally, that establish the minimum context needed. Store the results in the profile's entity layer with domain tags.

---

### Finding CM-4: Follow-up timing has no domain-specific cadence

**Severity:** P2

**Source discipline:** Concierge medicine -- condition-specific follow-up protocols.

In clinical practice, follow-up intervals are rigorously calibrated to the condition: post-surgical patients at 48 hours, chronic conditions quarterly, acute infections in one week. Auraken's follow-up system (PRD.md, Journey 3) describes "contextually timed follow-up messages" but provides no framework for how timing varies by domain. Career decisions need follow-up in 2-4 weeks (decisions take time). Product recommendations might need follow-up in 2-3 days ("did you order it? how is it?"). Learning goals need follow-up at spaced-repetition intervals. Pattern awareness reflections should be monthly.

**Failure scenario:** User commits to trying a new productivity framework (cognitive augmentation) and also mentions they are looking for a new desk chair (product recommendation). The system follows up on both at the same interval. The desk chair follow-up comes too late (user already bought something else) and the productivity framework follow-up comes too early (user has not had time to try it).

**Agent:** fd-concierge-medicine-longitudinal-care

**Recommendation:** Add a domain-aware follow-up cadence table to PRD.md's "Follow-Up & Accountability" section. Define default follow-up intervals per use case domain, with user-configurable overrides. Map these to the commitment tracking system.

---

### Finding CM-5: Cross-domain synthesis lacks clinical correlation rigor

**Severity:** P2

**Source discipline:** Concierge medicine -- integrative diagnosis across body systems.

A concierge physician does not merely track that a patient has sleep issues, work stress, and elevated cortisol in separate charts. They synthesize: the work stress is causing the sleep issues, which are elevating cortisol, which is causing weight gain, which is worsening the work stress via reduced confidence. This is a closed feedback loop, not three independent problems. Auraken's Journey 7 (PRD.md) describes multi-problem juggling and cross-thread connections, but the approach is pattern-based ("these feel similar") rather than mechanistic ("A causes B which causes C"). The phrase "Career, side project, and the gym thing all seem to be about the same tension" is correlation. A concierge physician would identify the causal chain.

**Agent:** fd-concierge-medicine-longitudinal-care

**Recommendation:** When cross-domain connections are surfaced, the agent should attempt causal chain reasoning, not just thematic similarity. Add a cross-domain synthesis mode to the OODARC Orient phase that explicitly models feedback loops between active threads, using Donella Meadows' stock-and-flow vocabulary (which is already in Auraken's intellectual lineage).

---

## Agent: fd-wealth-advisory-fiduciary-modeling

### Finding WA-1: Affiliate monetization creates undisclosed fiduciary conflict

**Severity:** P0

**Source discipline:** Wealth advisory -- fee-only fiduciary standards and conflict-of-interest disclosure.

The wealth management industry underwent a decades-long reckoning over commission-based compensation. The conclusion: when an advisor earns commissions on products they recommend, the advice is structurally compromised, regardless of the advisor's intentions. Fee-only fiduciary advisors reject commissions specifically because the conflict of interest is impossible to manage through good intentions alone. Auraken's VISION.md lists "affiliate revenue" as a potential business model direction, and the Robinson NTS context positions product recommendations as a core use case. The combination of deep personal context (cognitive profile, values, blind spots, contradictions) with affiliate-monetized recommendations creates exactly the conflict that destroyed trust in financial services. The system knows the user's psychological vulnerabilities and is financially incentivized to exploit them.

**Failure scenario:** Auraken knows from months of cognitive augmentation that a user struggles with impulse buying (contradiction registry: "says they value minimalism but revealed behavior shows retail therapy during stress"). The system recommends a product during a stressful period. Even if the recommendation is genuinely good, the structural incentive is poisonous: the system profits from recommendations and has a detailed map of the user's purchase triggers. If this becomes public, it destroys not just the recommendation feature but the entire trust relationship that makes cognitive augmentation work.

**Agent:** fd-wealth-advisory-fiduciary-modeling

**Recommendation:** This is an architectural decision that must be resolved before recommendations ship. Three options, in order of fiduciary integrity: (1) Never monetize through affiliate links -- subscription-only, like fee-only advisors. (2) Affiliate links with full disclosure and structural separation: recommendations are generated by a process that does not have access to affiliate status, and affiliate links are added post-selection with explicit disclosure. (3) If affiliate revenue is pursued, add a "suitability check" layer inspired by FINRA's suitability obligations: before any recommendation, verify it is suitable given the user's full profile, including emotional state, financial constraints, and revealed (not just stated) preferences. Document the chosen approach in PHILOSOPHY.md as a named principle.

---

### Finding WA-2: No suitability framework for recommendations

**Severity:** P1

**Source discipline:** Wealth advisory -- FINRA suitability rule and KYC (Know Your Customer) requirements.

Before recommending any investment, a fiduciary advisor must assess suitability: does this recommendation match the client's risk tolerance, financial situation, time horizon, and goals? This is not optional -- it is a regulatory requirement because the advisor has an information advantage over the client. Auraken builds a comprehensive cognitive profile (PRD.md, "Profile Architecture") but defines no equivalent suitability check for product recommendations. The profile captures thinking patterns, values, and contradictions -- all the inputs a suitability framework would need -- but there is no process that consumes these inputs before a recommendation is made.

**Failure scenario:** User's profile reveals they are in a financially stressful period (inferred from career-change conversations). Auraken recommends an expensive product that matches their aesthetic preferences (stated) but not their financial reality (revealed). The recommendation is technically responsive to expressed interest but unsuitable given full context. In wealth advisory, this is a compliance violation. In a trust-based AI relationship, it is a betrayal.

**Agent:** fd-wealth-advisory-fiduciary-modeling

**Recommendation:** Add a recommendation suitability layer to the PRD.md feature set. Before surfacing any product recommendation, the system should check the recommendation against relevant profile dimensions: financial constraints (if known), current emotional state (stress = bad time for purchase decisions), stated vs. revealed preferences (does the user actually want this or just say they do?), and domain-specific context. Model this after FINRA's suitability obligations, adapted for non-financial recommendations.

---

### Finding WA-3: Stated vs. revealed preference gap unaddressed for commerce

**Severity:** P2

**Source discipline:** Wealth advisory -- behavioral finance and the gap between stated risk tolerance and revealed risk behavior.

Behavioral finance's central insight is that people systematically misreport their own preferences. Clients say "I want aggressive growth" and then panic-sell during a 10% drawdown. Auraken's PHILOSOPHY.md (Principle 3) and PRD.md (Profile Architecture, "Entity layer") beautifully capture this for cognition: stated patterns vs. revealed patterns vs. submerged patterns. The contradiction registry is designed to hold exactly this tension. But none of this apparatus is connected to the recommendation use case. When a user says "I prefer minimalist design" but their purchase history reveals they buy maximalist products, the recommendation system has no documented way to reconcile this before making a recommendation.

**Agent:** fd-wealth-advisory-fiduciary-modeling

**Recommendation:** Extend the contradiction registry concept explicitly to commerce-relevant preferences. When the profile detects a stated/revealed gap in a domain that affects recommendations (aesthetic preferences, budget, brand loyalty, impulse patterns), surface the contradiction to the user before recommending: "You've mentioned you prefer minimalist design, but I've noticed you tend to buy more ornate things -- which should I optimize for?" This mirrors the wealth advisor practice of showing clients their actual risk behavior alongside their stated risk tolerance.

---

### Finding WA-4: Deep context creates asymmetric information obligation

**Severity:** P2

**Source discipline:** Wealth advisory -- fiduciary duty arising from information asymmetry.

Fiduciary obligation in wealth management arises specifically from the information asymmetry: the advisor knows more about the client's situation than the client consciously realizes. This creates a duty of care that is proportional to the depth of knowledge. Auraken's cognitive profile explicitly captures "submerged" patterns -- "patterns that surface through conversation and surprise even the user" (PRD.md, Profile Architecture). This is the deepest form of information asymmetry: the system knows things about the user that the user does not know about themselves. VISION.md's business model section and PHILOSOPHY.md's principles do not acknowledge that this level of context creates obligations beyond "anti-dependency."

**Agent:** fd-wealth-advisory-fiduciary-modeling

**Recommendation:** Add an "Obligations from Context Depth" principle to PHILOSOPHY.md. Articulate that the depth of Auraken's user model creates a proportional duty of care. The deeper the profile, the greater the obligation to use it in the user's interest rather than in the system's commercial interest. This is the philosophical foundation that makes the suitability framework (WA-2) and affiliate disclosure (WA-1) coherent rather than ad hoc.

---

## Agent: fd-museum-experience-ambient-discovery

### Finding MU-1: No mode transition between cognitive augmentation and ambient discovery

**Severity:** P1

**Source discipline:** Museum experience design -- threshold experiences and visitor mode-shifting.

Museums invest heavily in entrance sequences that shift visitors from "street mode" (goal-directed, distracted, hurried) to "museum mode" (receptive, curious, open to surprise). The Exploratorium's Bay Observatory entrance uses a long, darkened corridor that strips away the outside world. Te Papa's ground floor uses open sight lines that invite wandering. These are not decorative -- they are functional threshold experiences that prepare the visitor's cognitive state for discovery. Auraken's PRD.md defines two very different cognitive modes: focused problem-solving (OODARC, lenses, cognitive augmentation) and ambient discovery (recommendations, browsing, the Robinson "window shopping" insight). But there is no threshold experience designed to transition between them. The system is either in cognitive augmentation mode or recommendation mode, with no designed transition.

**Failure scenario:** User is deep in a demanding OODARC conversation about a career decision (high cognitive load, emotional stakes, focused attention). The system surfaces a product recommendation mid-conversation because an adjacency was detected. The recommendation, however relevant, violates the user's cognitive mode -- they are in "museum mode" (focused, analytical) when they need to be in "gallery mode" (receptive, browsing) for recommendations to land well. The recommendation feels like an ad interrupting a therapy session.

**Agent:** fd-museum-experience-ambient-discovery

**Recommendation:** Design explicit mode transitions in the conversation model. When the user shifts from cognitive augmentation to discovery (or the system wants to surface a recommendation), insert a threshold micro-interaction: a change in conversational tone, a brief pause, a framing statement ("Something completely different -- I've been noticing you might be interested in..."). Define these transitions in the PRD.md conversation model. Consider a user-initiated "gallery mode" command: "show me what you've been noticing" that explicitly opens the ambient discovery channel.

---

### Finding MU-2: Recommendation surfacing lacks curatorial adjacency logic

**Severity:** P1

**Source discipline:** Museum experience design -- prepared serendipity through curated adjacency.

The most powerful museum experiences are not about individual objects -- they are about the adjacencies between objects. The V&A's "Rapid Response Collecting" gallery places a 3D-printed gun next to a Liberator pistol from WWII, creating meaning through juxtaposition that neither object carries alone. This is prepared serendipity: the curator creates conditions for discovery without dictating what the visitor discovers. Auraken's PRD.md describes dynamic lens selection and cross-thread connections, but the recommendation system (as described in the Robinson NTS context) does not articulate a curatorial adjacency model. How does the system decide what to surface next to what? If recommendations are served individually ("here's a product for you"), they are search results, not discoveries. If they are served as curated adjacencies ("you've been thinking about decision fatigue -- here's a book, a tool, and an unrelated object that connects to the same pattern"), they are serendipity.

**Failure scenario:** Auraken surfaces product recommendations as individual items with individual rationales. Each recommendation is defensible, but the collection feels like search results. The Robinson "window shopping" insight is lost because window shopping works through adjacency -- you see things next to each other and make connections the shopkeeper did not plan. Individual recommendations served in a chat interface cannot achieve this effect without deliberate curatorial design.

**Agent:** fd-museum-experience-ambient-discovery

**Recommendation:** Design a "curated adjacency" model for recommendations. Instead of surfacing single products, surface small collections (2-4 items) connected by a theme the user would find interesting based on their profile. The connection should be non-obvious -- not "you like hiking, here are hiking boots" but "you've been thinking about decision fatigue -- here's a book on satisficing, a physical timer that constrains choice duration, and a Japandi desk organizer that reduces visual noise." The adjacencies create meaning the individual items do not carry.

---

### Finding MU-3: No "gallery mode" for receptive browsing state

**Severity:** P2

**Source discipline:** Museum experience design -- visitor agency and self-directed exploration.

The best museums support multiple visitor modes: the guided tour (structured, narrative), the audio guide (self-paced but directed), and free exploration (pure agency). Each mode serves different visitors and different visits. Te Papa's open floor plans support free exploration; the British Museum's room sequences support narrative progression. Auraken's conversation model (PRD.md) is entirely pull-based for recommendations: the user must bring a problem or the system follows up on past conversations. There is no designed mode where the user signals "I'm receptive, show me interesting things" -- the equivalent of walking into a museum with no agenda.

**Failure scenario:** User has 15 minutes of idle time and would genuinely enjoy browsing ambient recommendations. But Auraken has no "browse mode" -- the only entry point is "What's on your mind?" which requires an active problem. The user does not message because they have nothing to ask about, missing an engagement opportunity where the Robinson "window shopping" experience would be ideal.

**Agent:** fd-museum-experience-ambient-discovery

**Recommendation:** Add a "gallery mode" entry point to the conversation model. Users can trigger it explicitly ("show me things") or the system can offer it at appropriate moments ("nothing urgent today? I've been collecting some things you might find interesting"). In gallery mode, the agent surfaces curated adjacencies (see MU-2) with low-pressure presentation -- no call to action, no "buy now," just interesting things with light context. The user can engage deeply with any item or keep browsing.

---

### Finding MU-4: The gift shop problem -- commerce transition risks trust contamination

**Severity:** P2

**Source discipline:** Museum experience design -- the gift shop placement dilemma.

Every museum struggles with the gift shop. Place it at the exit and visitors feel herded toward commerce. Place it in the middle and it interrupts the experience. The Exploratorium solves this by making the gift shop feel like an extension of the exhibits -- the products ARE experiments and educational tools. The V&A separates the shop spatially but connects it thematically. Auraken's transition from cognitive augmentation (the exhibition) to product recommendations with affiliate links (the gift shop) faces the same structural problem. The moment a user realizes that some interactions have commercial intent, they may retroactively question all previous interactions.

**Agent:** fd-museum-experience-ambient-discovery

**Recommendation:** Take the Exploratorium approach: recommendations should feel like an organic extension of the core experience, not a separate commercial channel. Products surfaced should be "thinking tools" -- objects, books, services, experiences that extend the cognitive augmentation work. A book that applies the lens the user just learned. A physical tool that embodies a framework. This makes the "gift shop" feel like part of the exhibition rather than an exit-gate money trap. Structurally, never interrupt a cognitive augmentation conversation with a recommendation. Recommendations live in their own temporal space (gallery mode, post-session, idle moments).

---

### Finding MU-5: No return visit evolution for recommendation surfaces

**Severity:** P3

**Source discipline:** Museum experience design -- designing for repeat visitors.

Great museums design for the repeat visitor who sees different things each time. The permanent collection is the anchor, but temporary exhibitions, rotated displays, and seasonal programs ensure the tenth visit reveals something the first nine did not. Auraken's PRD.md (Journey 4, "Cognitive Growth") beautifully addresses this for the cognitive augmentation side: the agent tracks when users apply lenses independently, celebrates growth, and brings harder problems. But there is no equivalent evolution model for the recommendation surface. Does the recommendation engine evolve as the user grows? Do the curated adjacencies become more sophisticated over time?

**Agent:** fd-museum-experience-ambient-discovery

**Recommendation:** Define a recommendation maturity model that parallels the cognitive growth tracking in Journey 4. Early recommendations are accessible and practical ("here's a good notebook"). As the profile deepens, recommendations become more ambitious and cross-domain ("here's a tool from architecture that applies to how you've been thinking about team dynamics"). Track recommendation sophistication as a profile dimension.

---

## Agent: fd-intelligence-analysis-structured-sensemaking

### Finding IA-1: Lens selection has no confirmation bias mitigation

**Severity:** P1

**Source discipline:** Intelligence analysis -- Analysis of Competing Hypotheses (ACH) and debiasing protocols.

Richards Heuer's central insight in "Psychology of Intelligence Analysis" is that analysts see what they expect to see. The most dangerous failure mode is not wrong data but wrong framing -- the analyst selects an analytical framework that confirms their existing beliefs and never considers alternatives. Auraken's dynamic lens selection (PRD.md, "Dynamic Selection") uses "recognition-primed pattern matching" (Klein's RPD), which is explicitly an expert-intuition model. RPD works well when the expert has extensive, representative experience in a stable domain. But RPD is maximally vulnerable to confirmation bias when applied in novel situations or when the expert's model of the situation is wrong. Auraken's lens selection has no competing-hypothesis step: the system selects the lens it recognizes as fitting, applies it, and moves on. There is no moment where the system asks "what alternative lens would reframe this differently?"

**Failure scenario:** User brings a problem that superficially resembles a principal-agent dynamic (the lens Auraken has successfully applied to this user's problems before). The system selects the principal-agent lens via RPD pattern matching. But the actual problem is a coordination failure -- a different lens entirely. Because there is no ACH-equivalent step, the system never considers the alternative. The user receives a coherent but wrong reframe, and the agent's confidence in its model increases (because the user engaged with the reframe), deepening the confirmation bias. The Reflect phase records "principal-agent lens worked well" when it actually didn't -- the user engaged because the agent was confident, not because the lens was right.

**Agent:** fd-intelligence-analysis-structured-sensemaking

**Recommendation:** Add a "competing lens" step to the OODARC Decide phase. After the system selects a primary lens via RPD, it should briefly consider at least one alternative lens that would reframe the problem differently. This does not need to be surfaced to the user every time -- but the system should internally evaluate whether the alternative lens fits at least as well. If it does, surface the tension: "This could be a principal-agent problem OR a coordination failure -- the interventions are very different. Which feels closer?" This is the ACH protocol adapted for lens selection.

---

### Finding IA-2: Profile observations lack epistemic confidence levels

**Severity:** P1

**Source discipline:** Intelligence analysis -- estimative language standards (NIE confidence levels).

Intelligence products use standardized confidence levels: "We assess with high confidence that..." vs. "We assess with moderate confidence that..." This is not hedging -- it is a disciplined practice that communicates the evidentiary basis for an assessment. Auraken's Profile Architecture (PRD.md) distinguishes between "Stated," "Revealed," and "Submerged" pattern types, which is a good start -- it captures the source of the observation. But it does not capture the confidence level. A pattern observed once is treated the same as a pattern observed twenty times. The entity layer has `valid_from`/`valid_until` timestamps (temporal validity) but no confidence score (evidentiary strength).

**Failure scenario:** Auraken observes a single instance of the user deferring a decision and records "tendency to defer decisions under pressure" as a profile entity. Over subsequent sessions, this observation gets used as if it were a well-established pattern. The user eventually gets a reflection like "I've noticed you tend to defer when things get stressful" based on a single data point. The user rightly feels mischaracterized. In intelligence analysis, a single-source observation would carry a "low confidence" tag and would never be presented as an established pattern.

**Agent:** fd-intelligence-analysis-structured-sensemaking

**Recommendation:** Add a confidence dimension to the entity layer in the Profile Architecture. Each entity should carry an epistemic status: `speculative` (single observation), `emerging` (2-3 observations), `established` (repeated pattern across sessions), `confirmed` (user has acknowledged the pattern). The synthesis layer should only surface `established` or `confirmed` patterns in reflections. `Speculative` and `emerging` patterns inform lens selection internally but are not reflected to the user until they cross a threshold.

---

### Finding IA-3: No adversarial self-challenge on profile assertions

**Severity:** P2

**Source discipline:** Intelligence analysis -- red teaming and devil's advocacy protocols.

Intelligence agencies institutionalize adversarial review: the Red Team's job is to challenge the analysis team's conclusions. This is not optional peer review -- it is structural opposition designed to catch groupthink and premature closure. Auraken's conversation model includes micro-provocations after reframes (PRD.md, Conversation Design Principle 4) and Mirror Mode (Journey 6) that challenges the user's reasoning. But there is no equivalent self-challenge mechanism for the agent's own assertions. The system builds a model of the user, selects lenses based on that model, and reflects patterns from that model -- but never questions whether the model itself is wrong.

**Failure scenario:** Over 20 sessions, Auraken builds a model that the user's core pattern is "fear of commitment." The system increasingly selects lenses and surfaces reflections that reinforce this interpretation. But the actual pattern is "rational option-keeping in genuine uncertainty" -- a different framing entirely. Without adversarial self-challenge, the model becomes self-reinforcing: the agent interprets all new data through the "fear of commitment" frame, and the user's engagement with these reflections is taken as confirmation.

**Agent:** fd-intelligence-analysis-structured-sensemaking

**Recommendation:** Add a periodic "red team" step to the profile synthesis process. When the synthesis layer generates a compact profile, run an adversarial pass: "What if the opposite interpretation of this pattern were true? What evidence would support it?" This could be implemented as a second LLM call with instructions to challenge the primary profile's conclusions. Surface strong counter-interpretations to the user as honest uncertainty: "I've been framing this as X, but it could also be Y -- which resonates more?"

---

### Finding IA-4: No framework for distinguishing signals from noise across use case domains

**Severity:** P2

**Source discipline:** Intelligence analysis -- signal-to-noise calibration and collection bias awareness.

Intelligence analysts are trained to recognize that different collection methods produce different signal-to-noise ratios and different biases. SIGINT (signals intelligence) is high-volume, low-context. HUMINT (human intelligence) is low-volume, high-context. Treating them identically produces bad analysis. Auraken's expansion from cognitive augmentation to product recommendations changes the signal-to-noise ratio dramatically. Cognitive augmentation conversations are high-signal (every message carries intentional meaning). Product browsing behavior is high-noise (many casual mentions, off-hand preferences, context-dependent choices). The profile system (PRD.md, Profile Architecture) treats all observations through the same entity extraction pipeline regardless of source domain.

**Agent:** fd-intelligence-analysis-structured-sensemaking

**Recommendation:** Tag profile observations with their source domain and apply domain-appropriate weighting. Observations from deep cognitive augmentation sessions carry higher weight for thinking-pattern inferences. Observations from product browsing carry higher weight for preference inferences but lower weight for personality inferences. A user who casually mentions liking a product is not expressing a core value -- the entity extraction should reflect this distinction.

---

### Finding IA-5: No post-mortem learning from failed lens applications or wrong recommendations

**Severity:** P2

**Source discipline:** Intelligence analysis -- post-mortem analysis and lessons-learned institutionalization.

Intelligence agencies conduct formal post-mortems after analytical failures. The 9/11 Commission Report, the WMD Commission Report -- these are institutionalized learning from failure. Auraken's OODARC model includes a Reflect phase, but the Reflect phase as described (PRD.md, OODARC section and Conversation Design Principle 4) focuses on whether the user's thinking shifted -- not on whether the agent's lens selection was correct. There is no mechanism for the system to recognize "I selected the wrong lens" or "my recommendation was bad" and learn from that failure structurally.

**Agent:** fd-intelligence-analysis-structured-sensemaking

**Recommendation:** Extend the OODARC Reflect phase to include agent self-assessment. After a lens application, track not just user engagement but user outcome: did the reframe lead to genuine insight or did the user redirect, disengage, or express confusion? Build a "lens effectiveness" metric per user per problem domain. When a lens consistently underperforms for a user, downweight it in future RPD selection. When a recommendation is rejected or regretted, record the failure and analyze what the suitability check missed.

---

### Finding IA-6: Puzzle vs. mystery distinction missing across use cases

**Severity:** P3

**Source discipline:** Intelligence analysis -- Gregory Treverton's puzzle/mystery distinction.

Treverton distinguished between puzzles (have a definite answer that can be found with more information) and mysteries (genuinely uncertain, more information does not resolve them). "Where is Bin Laden?" is a puzzle. "What will Iraq look like in 2010?" is a mystery. Different use cases fall at different points on this spectrum. Product recommendations are mostly puzzles (there is a best product for your needs -- you just need to find it). Career decisions are mostly mysteries (there is no objectively right answer). Auraken's Cynefin pre-filter (PRD.md) partially addresses this with the Clear/Complicated/Complex/Chaotic classification, but the puzzle/mystery distinction is subtly different: it is about whether the user should expect an answer at all.

**Agent:** fd-intelligence-analysis-structured-sensemaking

**Recommendation:** Consider layering the puzzle/mystery distinction on top of the Cynefin classification for recommendation vs. augmentation routing. When a user brings a puzzle-type problem (product search, factual question), route toward recommendation/information mode. When they bring a mystery-type problem (career direction, relationship dynamics), route toward augmentation mode. This would help set appropriate expectations: "I can help you find the right desk chair" vs. "I can help you think about your career differently, but there's no single right answer."
