---
artifact_type: flux-drive-findings
track: esoteric
target: apps/Auraken/
date: 2026-03-30
agents: [fd-ayurvedic-prakriti-constitution, fd-kampo-sho-pattern-recognition, fd-inuit-siku-ice-knowledge]
---

# Auraken Use Case Landscape — Track D: Esoteric Findings

Frontier pattern review of Auraken's expanding scope (cognitive augmentation agent to life operating system) through three maximally unexpected domain lenses.

---

## Finding 1: The Prakriti-Vikriti Gap — Profile Architecture Conflates Stable Constitution with Temporary State

**Severity:** P1
**Agent:** fd-ayurvedic-prakriti-constitution
**Direction:** Refines existing (profile architecture)

**Source domain mechanism:** In Ayurvedic medicine, Prakriti (innate constitution) is determined at birth and never changes. Vikriti (current imbalance) fluctuates with season, stress, diet, and life circumstances. Every clinical assessment explicitly separates the two: treatment targets Vikriti (restore balance) while respecting Prakriti (don't fight constitution). A Vata-dominant person under Kapha-aggravating stress presents as sluggish — treating them as constitutionally Kapha would be harmful.

**Why it's unexpected:** AI profiling systems universally treat personality as a single evolving model. The idea that a cognitive profile needs TWO distinct temporal layers — one that barely moves across years and one that shifts week to week — comes from a 5,000-year-old medical tradition, not from ML or psychology.

**How it maps:** Auraken's entity layer uses `valid_from`/`valid_until` bi-temporal timestamps (PRD.md, Profile Architecture section), which is the right primitive. But nothing in the architecture distinguishes between entities that represent stable constitutional patterns ("defaults to analytical thinking under uncertainty") and entities that represent temporary state ("currently overwhelmed and reverting to avoidance"). The synthesis layer generates a single compact working profile — it should generate two: a slow-moving constitutional summary and a fast-moving situational overlay.

**Concrete failure:** User goes through a difficult breakup. For three weeks, their conversations show avoidance patterns, reduced analytical engagement, and emotional flooding. Without Prakriti-Vikriti separation, the profile permanently absorbs these as "who the user is." When they recover, the agent continues treating them as avoidant — exactly the wrong lens. The profile was contaminated by Vikriti masquerading as Prakriti.

**Smallest fix:** Add a `temporal_stability` field to entities (`constitutional` | `situational` | `unknown`) and generate two synthesis summaries: one drawn only from `constitutional` entities, one incorporating `situational` overlay. Lens selection draws on both but weights constitutional for framework choice and situational for conversation tone.

---

## Finding 2: Constitutional Dosage — Same Lens, Different Intensity for Different Minds

**Severity:** P2
**Agent:** fd-ayurvedic-prakriti-constitution
**Direction:** Opens new design direction

**Source domain mechanism:** In Ayurveda, the same herb (say, ashwagandha) is prescribed at radically different dosages depending on constitution. A Vata constitution might need warming, grounding preparation at high dose; a Pitta constitution gets the same herb but cooled, lower dose, different vehicle. The active ingredient is identical — the delivery is constitutionally calibrated.

**Why it's unexpected:** Auraken's lens system treats lenses as uniform cognitive tools. The "when to apply" signatures determine *which* lens fires, but nothing modulates *how intensely* or *in what register* the lens is delivered. This is the equivalent of prescribing the same dose of every medicine to every patient.

**How it maps:** The PRD describes Laban Movement Analysis dynamics (Space, Time, Weight, Flow) for conversation adaptation, but these dynamics are disconnected from lens selection. The Ayurvedic insight is that lens selection and delivery intensity should be coupled through constitutional type. A user whose profile shows primarily narrative cognition should receive a sunk-cost analysis wrapped in story ("imagine you're advising a friend who..."), while an analytical user gets the same lens delivered as a structured decomposition. Same lens, different dosage form.

**Concrete scenario:** User with strong narrative-intuitive cognition receives a rigorous analytical decomposition of their career decision using Cynefin domain classification. The framework is correct — but the delivery register is wrong. User feels lectured, disengages. The lens was right; the dosage was wrong.

**Design direction:** Add a `cognitive_receptivity` dimension to the profile (analytical | narrative | somatic | dialogic) derived from conversation patterns. Lens application reads this dimension to modulate delivery — not which lens, but how the lens speaks.

---

## Finding 3: Dinacharya Rhythms — Cyclical Cognitive Patterns the Profile Doesn't Track

**Severity:** P3
**Agent:** fd-ayurvedic-prakriti-constitution
**Direction:** Opens new design direction

**Source domain mechanism:** Ayurvedic dinacharya (daily routine) and ritucharya (seasonal routine) recognize that the same person thinks differently at different times. Morning is Kapha-dominant (slow, grounded, integrative). Midday is Pitta-dominant (sharp, analytical, decisive). Evening is Vata-dominant (creative, scattered, anxious). Seasonal cycles overlay these daily cycles. Treatment timing matters as much as treatment choice.

**Why it's unexpected:** Productivity tools track when you work. No cognitive augmentation system tracks when you think *differently*. The insight isn't about scheduling — it's that the same person at 7 AM and 10 PM may need fundamentally different lenses applied to the same problem, because their cognitive mode has shifted.

**How it maps:** Auraken has timestamps on episodes but uses them only for sequencing and freshness. The system could extract cyclical patterns: "User sends analytical messages in the morning, emotional messages late at night. Career questions asked at night correlate with lower-quality reasoning." This is warm data the current architecture could capture but doesn't look for.

**Design direction:** Add temporal pattern extraction to profile analysis. When the user raises a complex topic at 11 PM, the agent might gently note: "This is a big one — want to dig in now, or flag it for when you're in a different headspace tomorrow?" Not time management. Cognitive rhythm awareness.

---

## Finding 4: The Near-Miss Lens Problem — No Mechanism to Detect Harmful Pattern Matches

**Severity:** P0
**Agent:** fd-kampo-sho-pattern-recognition
**Direction:** Refines existing (lens selection)

**Source domain mechanism:** In Kampo medicine, Sho (pattern) matching is a life-or-death diagnostic art. The formula Xiao Chai Hu Tang (Sho-saiko-to) treats a specific Sho pattern involving alternating fever and chills, chest tightness, and bitter taste. A patient presenting with 80% of these symptoms but with a key difference (say, the chest tightness is actually cardiac, not hepatic) will be harmed by the formula. Kampo training devotes enormous attention to *near-miss* patterns: situations that look like X but are actually Y, where applying X's treatment to Y's condition is actively dangerous.

**Why it's unexpected:** Auraken's PRD describes lens selection using Klein's Recognition-Primed Decision (RPD) — experts pattern-match situations to frameworks. But Klein's RPD research focused on firefighters and military commanders who have *immediate feedback* when they're wrong (the building collapses, the enemy advances). Auraken operates in a domain where wrong lens application produces *delayed, invisible harm*: the user goes down a destructive reasoning path and doesn't realize the framework led them astray until weeks later. RPD without near-miss awareness is dangerous in low-feedback domains.

**How it maps:** The PRD's lens structure includes "when to apply" signatures but has no concept of "when NOT to apply" — contraindication signatures. In Kampo, every formula has both indications and contraindications, and the contraindications are studied as carefully as the indications. Auraken's sunk-cost analysis lens might fire correctly for "user is persisting with something that isn't working." But if the real issue is a values conflict (the user is persisting because they care about the thing, not because of sunk costs), the sunk-cost framing actively undermines their legitimate commitment.

**Concrete failure:** User describes frustration with a side project that's consuming weekends. 80% of the pattern matches sunk-cost analysis. Agent applies the lens: "What would you do if you hadn't already invested this time?" User takes the advice, abandons the project. Three months later, realizes the project was actually aligned with their deepest values — they were frustrated with execution difficulty, not with the project itself. The lens was a near-miss: looked like sunk cost, was actually a capacity problem. The agent's confident application of the wrong lens caused real harm.

**Smallest fix:** Add `contraindication_signatures` to the lens schema — explicit patterns that look similar to the trigger pattern but indicate a different lens is needed. During lens selection, run a near-miss check: "This matches sunk-cost, but does it also match values-conflict? If both match, surface the ambiguity rather than committing to one."

---

## Finding 5: Sho-Evidence — The Missing "Distinguishing Feature" Verification Step

**Severity:** P1
**Agent:** fd-kampo-sho-pattern-recognition
**Direction:** Refines existing (lens selection)

**Source domain mechanism:** In Kampo diagnostics, after initial Sho pattern matching, the physician looks for a *Sho-evidence* (ketteishoko) — a single critical feature that distinguishes the matched pattern from its nearest neighbors. For the formula Keishi-to vs. Mao-to, both treat cold-pattern illness, but the distinguishing feature is whether the patient is sweating (Keishi-to) or not sweating (Mao-to). Without checking for this distinguishing feature, the physician might apply the wrong formula despite a good overall match.

**Why it's unexpected:** AI recommendation systems and RPD models both use holistic similarity matching. The Kampo insight is that after the holistic match, there should be a *targeted verification step* that checks for the one feature that would flip the diagnosis. This is neither pure holistic matching nor pure feature decomposition — it's holistic-then-targeted, a two-phase process that no AI system implements.

**How it maps:** Auraken's OODARC conversation model has Observe (map the problem), Orient (draw on context), Decide (select lens). But between Orient and Decide, there's no explicit verification step: "I think this is a principal-agent problem. What's the one thing that would tell me it's actually a coordination problem instead?" The agent should generate a distinguishing question — one targeted probe that confirms or disconfirms the lens match before committing to it.

**Concrete scenario:** User describes tension with a co-founder. Pattern matches "principal-agent dynamics." But the distinguishing feature between principal-agent (misaligned incentives) and coordination failure (aligned goals, bad communication) is whether both parties want the same outcome. One targeted question — "Do you think your co-founder wants the same thing you want?" — could flip the entire lens. Without Sho-evidence verification, the agent commits to the wrong frame.

**Design direction:** Add a `distinguishing_question` field to each lens — the single question that differentiates this lens from its nearest neighbor in pattern space. After initial lens selection, the agent asks this question before committing. This is the OODARC "Decide" phase becoming two sub-phases: tentative match, then verification probe.

---

## Finding 6: Go-Ho Lens Combination — When Multiple Lenses Must Be Applied Together, Not Sequentially

**Severity:** P2
**Agent:** fd-kampo-sho-pattern-recognition
**Direction:** Opens new design direction

**Source domain mechanism:** In Kampo, go-ho (combined formulas) is a formalized practice of prescribing two complementary formulas simultaneously. This is not polypharmacy (throwing multiple drugs at a problem) — it's a principled combination where Formula A addresses the root pattern and Formula B addresses a secondary pattern that Formula A alone would miss or worsen. Crucially, not all combinations are safe — some formulas have incompatible mechanisms that produce adverse interactions.

**Why it's unexpected:** Auraken's lens system treats lens selection as picking *the* right framework. The PRD's "connections" field in the lens schema hints at composability, but there's no formalized concept of lens combination or lens incompatibility. The Kampo insight is that complex problems often require two lenses held simultaneously — not sequentially applied one after another, but genuinely combined into a compound perspective.

**How it maps:** A user's career frustration might be simultaneously a principal-agent problem (misaligned incentives with employer) AND a pace-layer problem (they're trying to change a slow-moving institution at a fast-moving pace). These aren't two separate analyses — they compound. The principal-agent framing without the pace-layer context leads to "quit." The pace-layer framing without the principal-agent context leads to "be patient." Together, they suggest: "Renegotiate the relationship to align incentives at the institution's natural pace of change."

But some lens combinations are dangerous: applying both sunk-cost analysis and commitment-consistency in the same problem space creates a contradictory frame that paralyzes rather than clarifies.

**Design direction:** Formalize lens compatibility in the connection graph. Each lens connection should be typed: `complementary` (safe to combine), `sequential` (apply A, then B), `contradictory` (never combine — choose one). When the agent detects a multi-pattern problem, it looks for complementary lens pairs rather than forcing a single-lens selection.

---

## Finding 7: The No-Go Decision — When Auraken Should Explicitly Refuse to Apply a Lens

**Severity:** P1
**Agent:** fd-inuit-siku-ice-knowledge
**Direction:** Opens new design direction

**Source domain mechanism:** In Inuit Siku (sea ice) knowledge, the most critical survival skill is not reading the ice — it's the *no-go decision*. An experienced hunter reads wind, current, snow texture, animal behavior, cloud patterns, and ice sounds. When the signals are ambiguous or contradictory, the correct action is to not travel. Not to guess. Not to apply the best available model. To stay on shore. The no-go decision requires more expertise than the go decision, because it means overriding the desire to act in the face of uncertainty.

**Why it's unexpected:** Every AI system is designed to produce output. Auraken's entire product is delivering reframes and asking revealing questions. The Siku insight is that sometimes the most valuable thing a cognitive augmentation agent can do is *explicitly decline to engage with the problem at the current moment* — not because it lacks information (that's a simple "tell me more"), but because the signals are contradictory and any framework application would be premature.

**How it maps:** Auraken's OODARC has no explicit no-go gate. The Cynefin pre-filter classifies problems into domains but always proceeds to lens selection. There's no pathway where the agent says: "I'm picking up contradictory signals about this situation. I could apply three different frameworks and each would tell you something different. I think we need to sit with this before I point you at any of them."

**Concrete failure:** User brings a complex life decision with entangled career, relationship, and identity dimensions. The agent's profile has contradictory data: the user values both security and adventure, both autonomy and belonging. The problem is genuinely in the "confused" Cynefin domain — classification itself isn't possible yet. But the agent proceeds to lens selection anyway, picks the strongest match, and delivers a reframe that prematurely closes down the problem space. The user follows the frame, makes a decision, and later realizes the frame was arbitrary — the agent's confidence was false.

**Design direction:** Add an explicit confidence threshold to the Decide phase of OODARC. When lens-match confidence is below threshold AND signal modalities are contradictory, the agent enters a "hold" mode: "I have several frameworks that could apply here, but I'm not confident any of them is capturing what's actually going on. Can we explore this without a frame for a bit?" This is the anti-premature-convergence mechanism the slime-mold metaphor in the PRD gestures toward but doesn't formalize.

---

## Finding 8: Multi-Modal Signal Integration — Auraken Over-Indexes on Verbal Content

**Severity:** P1
**Agent:** fd-inuit-siku-ice-knowledge
**Direction:** Refines existing (profile building)

**Source domain mechanism:** Siku knowledge integrates at least seven distinct signal types: wind direction and temperature, ocean current patterns, snow surface texture, animal migration behavior, cloud formations, ice sounds (cracking, groaning, silence), and smell. No single signal is reliable alone. An experienced hunter builds confidence by *corroborating across modalities* — when wind, current, and animal behavior all agree, confidence is high. When they disagree, confidence drops regardless of how strong any single signal is.

**Why it's unexpected:** Auraken's profile architecture captures what users say (stated), what behavior shows (revealed), and submerged patterns. But in practice, text-based messaging provides primarily verbal content. The Siku insight is that the *non-verbal signals available in text messaging* are a rich, under-exploited modality: message timing (when do they write?), response latency (how quickly do they engage?), message length patterns (are they getting more terse?), topic avoidance (what do they never bring up?), session initiation patterns (do they come to you or do you prompt them?), and emoji/punctuation shifts.

**How it maps:** The PRD mentions "communication style fingerprint" but frames it as feeding style mirroring, not as a diagnostic signal for cognitive state. The Siku insight reframes these non-verbal text signals as a *separate modality* from content — the equivalent of reading ice sounds alongside wind patterns. A user who sends short messages at 2 AM about a topic they usually discuss expansively during the day is transmitting information through timing and length that contradicts or modifies their verbal content.

**Concrete scenario:** User says "I'm fine with the decision, just processing" (verbal signal: resolved). But they sent this at 1 AM, three days after the decision, and the message is 8 words when their baseline for this topic is 80+ words (behavioral signals: not resolved). Without multi-modal integration, the agent takes the verbal content at face value and closes the thread. The ice sounds were saying something different from the wind.

**Smallest fix:** Track per-user baselines for: message length, response latency, time-of-day distribution, session initiation ratio, and topic recurrence frequency. Flag deviations from baseline as a separate signal layer that the Observe phase of OODARC integrates alongside verbal content.

---

## Finding 9: Signal Freshness Decay — Yesterday's Profile May Be Dangerously Wrong Today

**Severity:** P2
**Agent:** fd-inuit-siku-ice-knowledge
**Direction:** Refines existing (profile architecture)

**Source domain mechanism:** Sea ice is continuously transforming. An ice formation that was safe to cross yesterday may have thinned overnight due to current shifts. Siku knowledge treats every observation as *time-stamped and decaying* — recent observations dominate, older observations inform background context but never override current reading. A hunter who relied on last week's ice assessment for today's crossing would be making a potentially fatal error.

**Why it's unexpected:** Auraken's bi-temporal entity layer timestamps facts but the PRD doesn't specify a decay function. The default behavior of most AI memory systems is to treat all stored facts as equally valid regardless of age. The Siku insight is that cognitive profile observations should have *half-lives* that vary by type: behavioral patterns might have a half-life of weeks, stated preferences might be stable for months, and emotional states might decay in hours.

**How it maps:** The profile architecture stores entities with `valid_from`/`valid_until` but these are explicit windows, not decay curves. A more Siku-aligned approach would weight entity influence by recency, with the decay rate varying by entity type. "User values autonomy" (constitutional, slow decay) vs. "User is frustrated with manager" (situational, fast decay) vs. "User is in a reflective mood" (ephemeral, very fast decay).

**Design direction:** Assign each entity type a decay half-life. The synthesis layer should weight entities by recency according to their type's half-life. This naturally implements the Prakriti-Vikriti distinction (Finding 1) through a continuous mechanism rather than a binary classification — constitutional entities have long half-lives, situational ones have short half-lives.

**Convergence note:** This finding converges with Finding 1 (Ayurvedic Prakriti-Vikriti). The Ayurvedic lens suggests a categorical separation (constitutional vs. situational). The Siku lens suggests a continuous mechanism (decay half-lives). The strongest design uses both: categorical labels for conceptual clarity, continuous decay for operational weighting.

---

## Finding 10: The "Ice Is Always Changing" Problem — Stale Models Actively Mislead

**Severity:** P2
**Agent:** fd-inuit-siku-ice-knowledge
**Direction:** Opens new design direction

**Source domain mechanism:** In Siku epistemology, the most dangerous mental state is *confident reliance on an outdated model*. A hunter who crossed a particular route successfully ten times develops justified confidence — but that confidence becomes dangerous when conditions change. The experienced hunter's response is not to distrust their model entirely, but to actively probe for *disconfirming signals* that would indicate the model has expired. They test the ice with a harpoon. They listen for sounds that shouldn't be there. They watch for animal behavior that contradicts their mental map.

**Why it's unexpected:** Auraken's cognitive profile is designed to accumulate and compound — the "tenth conversation is dramatically better than the first." The Siku insight introduces a critical counter-principle: accumulated context can become *actively misleading* when the user undergoes a significant life change. A job change, a breakup, a health crisis, a move — any of these can invalidate large portions of the profile. The system needs to not just accumulate but actively probe for model invalidation.

**How it maps:** Auraken's Journey 5 (Lapsed User Re-engagement) acknowledges that "the user may have changed in the gap" but treats this as a re-engagement concern. The Siku insight is broader: even during continuous engagement, the agent should periodically probe for *model validity* — not just "has your situation changed?" but targeted tests of specific profile assumptions. "Last month you said career growth was your top priority. Is that still true, or has something shifted?"

**Design direction:** Implement a "harpoon test" mechanism: periodically, the agent selects a high-weight profile entity and generates a targeted question that would reveal whether that entity is still valid. This is not a survey. It's an organic conversational probe: "You mentioned a few weeks ago that you were energized by the new role. Still feeling that way?" If the answer contradicts the entity, trigger a profile re-evaluation cascade for connected entities. The probe frequency should increase after life events the agent detects (job changes, relationship shifts, moves) and decrease during stable periods.

---

## Finding 11: Ambient Recommendation as Window Shopping — The Kampo "Gentle Formula" Pattern

**Severity:** P3
**Agent:** fd-kampo-sho-pattern-recognition
**Direction:** Refines existing (ProductRecs subsumption / Robinson NTS insight)

**Source domain mechanism:** Kampo medicine distinguishes between *kyo-sho* (deficiency patterns, treated with gentle tonifying formulas) and *jitsu-sho* (excess patterns, treated with strong purging formulas). The critical insight is that for kyo-sho — where the patient is depleted, sensitive, and easily overwhelmed — the formula must be so gentle that the patient barely notices it working. The healing happens through almost imperceptible nourishment over time, not through dramatic intervention. If a kyo-sho patient receives a jitsu-sho formula, the aggressive treatment harms them.

**Why it's unexpected:** This maps precisely to the Robinson NTS insight that "the best recommendations feel like window shopping, not aggressive sales." Most recommendation systems are jitsu-sho: they push, they optimize for conversion, they demand attention. The Kampo insight formalizes *why* the window-shopping approach works — it's constitutional matching. Some users (and some moments for all users) are in a kyo-sho state regarding product recommendations: they want gentle ambient awareness of possibilities, not targeted persuasion. Other users in other moments are in jitsu-sho state: they know what they want and want the system to help them execute efficiently.

**How it maps:** As Auraken subsumes ProductRecs and expands into ambient recommendations, the system should classify the user's current recommendation receptivity as kyo (browsing, exploring, ambient awareness) or jitsu (active need, ready to decide, wants specifics). This classification should shift dynamically within and across sessions — the same user might be kyo about furniture and jitsu about a specific tool they need for a project this week.

**Design direction:** Add recommendation receptivity state to the profile, per domain. Default to kyo (window shopping). Only shift to jitsu when the user signals active intent ("I need to find a..."). This is the Robinson NTS principle grounded in a formal constitutional framework rather than a vibes-based design heuristic.

---

## Finding 12: Acute vs. Chronic Sho — The Same Problem at Different Stages Needs Different Lenses

**Severity:** P2
**Agent:** fd-kampo-sho-pattern-recognition
**Direction:** Opens new design direction

**Source domain mechanism:** In Kampo, the same underlying condition presents as different Sho depending on its stage. An acute cold in its first hours (Taiyo stage) requires a warming, dispersing formula. The same cold three days later (Shaoyang stage) has moved deeper and requires a harmonizing formula. Applying the acute-stage formula to the chronic-stage presentation is ineffective at best, harmful at worst. The Sho shifts over time even though the underlying condition hasn't changed — only its stage has.

**Why it's unexpected:** Auraken's lens selection considers the *problem* but not the *stage of the problem*. A career dissatisfaction issue raised for the first time (acute) and the same issue raised for the fifth time over three months (chronic) pattern-match to the same lens triggers — but they need fundamentally different approaches. The acute presentation benefits from exploratory mapping (Observe phase of OODARC). The chronic presentation needs confrontation with the pattern: "We've talked about this five times. Each time you generate insight and then nothing changes. What's that about?"

**How it maps:** Auraken's Journey 7 (Multi-Problem Juggling) tracks thread status (active, dormant, resolved) but doesn't track *stage*. The Kampo insight adds a temporal dimension to problem classification: is this the user's first encounter with this problem (acute), a recurring pattern (chronic), or a crisis point (acute-on-chronic)? Each stage implies a different lens selection and a different conversational register.

**Design direction:** Add `problem_stage` tracking to active threads: `first_mention`, `recurring` (raised 2+ times), `escalating` (increasing emotional intensity), `chronic` (raised 3+ times without change), `acute_on_chronic` (sudden intensification of a chronic pattern). Different stages should bias lens selection toward different approaches: exploratory for first mentions, confrontational for chronic, crisis-stabilization for acute-on-chronic.

---

## Cross-Track Convergence Analysis

Three findings from three independent esoteric traditions converge on the same architectural gap:

**Temporal stratification of the cognitive profile** (Findings 1, 9, and 10 converge):
- Ayurvedic Prakriti-Vikriti demands categorical separation of constitutional vs. situational traits
- Inuit Siku demands continuous decay weighting by observation recency
- Inuit "ice is always changing" demands active probing for model invalidation
- These three mechanisms are complementary, not redundant. The strongest architecture implements all three: categorical labels, continuous decay, and periodic validity probes.

**Two-phase lens selection** (Findings 4 and 5 converge):
- Kampo near-miss awareness demands contraindication signatures on every lens
- Kampo Sho-evidence demands a distinguishing question before committing to a lens
- Together, these transform lens selection from single-phase pattern matching to: match, check contraindications, ask distinguishing question, then commit or pivot. This is the most architecturally significant finding — it changes the OODARC Decide phase from a single step to a three-step subprocess.

**Constitutional calibration of delivery** (Findings 2 and 11 converge):
- Ayurvedic dosage calibration demands that lens intensity vary by cognitive constitution
- Kampo kyo/jitsu classification demands that recommendation aggressiveness match receptivity state
- Both point to the same gap: Auraken selects *which* intervention but doesn't modulate *how* it's delivered based on who's receiving it.
