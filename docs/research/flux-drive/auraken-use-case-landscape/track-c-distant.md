---
artifact_type: flux-drive-findings
track: distant
target: apps/Auraken/
date: 2026-03-30
agents: [fd-persian-carpet-weaving-composition, fd-chinese-lacquerware-layering, fd-gamelan-orchestral-stratification, fd-constitutional-herbalism-terrain]
---

# Auraken Use Case Landscape — Track C (Distant Domain) Findings

Structural isomorphisms from four distant knowledge domains applied to Auraken's expansion from cognitive augmentation agent to life operating system.

---

## Finding 1: The Missing Cartoon (Master Design Template)

**Severity:** P1
**Agent:** fd-persian-carpet-weaving-composition
**Type:** Concrete improvement

**Source domain mechanism:** In Isfahan carpet weaving, no weaver begins work without a *cartoon* — a full-scale design template drawn on graph paper that maps every knot. The cartoon ensures that motifs designed independently (medallions, borders, corner pieces) compose into a unified field. Without it, individually beautiful motifs collide at junctions.

**Mapping to Auraken:** VISION.md describes four use case domains (cognitive augmentation, ambient recommendations, learning/growth, pattern awareness) but contains no architectural template showing how they compose. The PRD (lines 263-298) specifies features per use case but never defines the shared compositional grammar — the rules by which a cognitive augmentation session hands off to an ambient recommendation, or how a growth tracking observation feeds back into lens selection. Each use case is designed as a standalone motif.

**Failure scenario:** Without a cartoon, the four domains will be designed by different sessions/sprints with locally coherent but globally conflicting interaction patterns. Cognitive augmentation's "never do the user's thinking" principle (PHILOSOPHY.md line 12) directly conflicts with ambient recommendations that must proactively surface products. The first user who experiences both in one session will feel the seam.

**Recommendation:** Add a "Use Case Composition Map" section to VISION.md or PRD.md that explicitly defines: (a) the shared capabilities each domain draws from (the warp/weft), (b) the transition rules between domains (the border designs), and (c) the constraints that prevent domain conflicts (e.g., "ambient recommendations never interrupt an active OODARC cycle").

---

## Finding 2: No Border Design Between Cognitive Augmentation and Commerce

**Severity:** P1
**Agent:** fd-persian-carpet-weaving-composition
**Type:** Concrete improvement

**Source domain mechanism:** In carpet composition, the *hashiyeh* (border) is not decoration — it is the structural element that mediates between the interior field and the edge. A carpet without borders looks unfinished; a carpet with borders that clash with the field looks incoherent. The border has its own design integrity while serving the whole.

**Mapping to Auraken:** The Robinson NTS insight ("best recommendations feel like window shopping, not aggressive sales") implies a specific interaction register for ambient recommendations that differs fundamentally from cognitive augmentation's register. PHILOSOPHY.md's "camera, not engine" principle (line 9) governs cognitive augmentation. But what governs the transition when a conversation about a career decision naturally touches on tools or products? There is no border design — no explicit mediating interaction pattern that allows the system to shift registers without violating either domain's principles.

**Failure scenario:** User is in a deep career discussion. Auraken detects a relevant product signal ("I need better project management"). Without a border design, the system either (a) ignores the signal (loses recommendation value) or (b) pivots to a recommendation (feels like being sold to mid-therapy). Both outcomes damage trust.

**Recommendation:** Define a "border register" — a specific interaction pattern for moments when domains overlap. The Robinson window-shopping insight suggests this border should feel like noticing, not suggesting: "That project management friction you mentioned — I've been noticing a pattern there. Want to explore that separately, or keep going with the career stuff?" The user controls the transition.

---

## Finding 3: Warp and Weft — The Invisible Infrastructure Is Undefined

**Severity:** P2
**Agent:** fd-persian-carpet-weaving-composition
**Type:** Opens a new question

**Source domain mechanism:** Every carpet design, regardless of motif, depends on the invisible structural foundation of warp (vertical threads) and weft (horizontal threads). The warp determines the carpet's dimensions and density. The weft holds the knots. No motif exists without this infrastructure, yet it is never visible in the finished product.

**Mapping to Auraken:** The PRD's Profile Architecture (lines 326-338) defines the three-tier profile system, which serves cognitive augmentation well. But does this same warp/weft serve ambient recommendations? Product recommendations need different profile signals — purchase history patterns, aesthetic preferences, budget constraints, brand affinities — that the current entity layer categories (Stated, Revealed, Submerged, Warm data) may not capture. The question: is the profile architecture the universal warp, or is it a warp designed for one motif?

**Open question:** Does the entity layer's four-category taxonomy (Stated/Revealed/Submerged/Warm data at PRD.md lines 329-334) extend naturally to product recommendation context, or does ambient recommendation require its own entity categories that the current schema cannot express?

---

## Finding 4: The Thick Layer Problem — Commerce From Thin Context

**Severity:** P1
**Agent:** fd-chinese-lacquerware-layering
**Type:** Concrete improvement

**Source domain mechanism:** In Fuzhou bodiless lacquerware, a single thick layer of lacquer *will* crack. The material demands many thin layers, each cured separately (typically 24-48 hours between coats), with light sanding between to create adhesion. The temptation to speed up by applying fewer, thicker layers always produces inferior work that fails structurally over time.

**Mapping to Auraken:** The PRD specifies that cognitive augmentation hits its "uncanny moment" around interaction 5-10 (PRD.md line 158). But ambient product recommendations require categorically deeper context — understanding not just how someone thinks, but what they value materially, what their aesthetic sensibilities are, what their budget constraints look like across categories, how they make purchase decisions. This is the Robinson insight operationalized: recommending a Patagonia jacket to someone in Portland from a single outdoor-interest signal is a thick layer applied to uncured substrate.

**Failure scenario:** If ambient recommendations launch alongside cognitive augmentation in v1.0, the system will attempt product suggestions from 5-10 sessions of cognitive conversation — context that was never designed to capture purchase-relevant signals. The recommendations will feel generic or presumptuous, poisoning the user's trust in the system's judgment generally, including for cognitive augmentation where the trust was earned.

**Recommendation:** Define explicit per-use-case "readiness thresholds" in the PRD. Cognitive augmentation: ready from session 1, uncanny by session 5-10. Ambient recommendations: context accumulation phase for N sessions (estimate needed), with the system explicitly declining to recommend until sufficient layers have cured. The system should communicate this honestly: "I'm still learning what matters to you — not ready to suggest things yet."

---

## Finding 5: No Curing Time Between Context Layers

**Severity:** P2
**Agent:** fd-chinese-lacquerware-layering
**Type:** Concrete improvement

**Source domain mechanism:** Lacquer curing is not just drying — it is a chemical transformation (polymerization via the enzyme laccase) that requires specific humidity and temperature. Rushing this process produces a surface that looks finished but is structurally weak. The curing time is not wasted time; it is when the material achieves its structural integrity.

**Mapping to Auraken:** The PRD's adaptive timescale depth table (lines 68-79) defines when deeper engagement activates, but treats all interactions within a session as equally weighted context. Twenty messages in a single hour-long session are treated as equivalent to twenty messages over five sessions spanning a month. But the lacquerware insight suggests that temporal spacing between interactions creates structural context that rapid interaction cannot. A user who returns after a week with an update on a career decision has demonstrated something about their relationship to the problem that is invisible in the content of their message — they've been living with it, integrating it, testing it against reality. That temporal signal is the curing time.

**Recommendation:** Add a "context maturity" dimension to the profile architecture. Weight cross-session patterns higher than within-session patterns for constitutional use cases (cognitive augmentation, growth tracking). A user's stated pattern confirmed by behavior across three sessions over a month is structurally stronger than the same pattern expressed three times in one conversation.

---

## Finding 6: The Sanding Between Layers — Context Revision Is Missing

**Severity:** P2
**Agent:** fd-chinese-lacquerware-layering
**Type:** Opens a new question

**Source domain mechanism:** Between each lacquer layer, the artisan lightly abrades the cured surface. This creates microscopic roughness that allows the next layer to bond. Without sanding, layers delaminate over time — they sit on top of each other without structural integration.

**Mapping to Auraken:** The profile architecture has an entity layer with `valid_from`/`valid_until` timestamps (PRD.md line 329), suggesting that profile facts can expire. But there is no described mechanism for actively challenging or revising existing context — the equivalent of sanding. Journey 5 (Lapsed User Re-engagement, PRD.md lines 182-197) acknowledges that "the user may have changed in the gap" but treats this as recalibration, not as a structural requirement for deeper understanding. The question: does the system ever deliberately test whether a stored profile fact is still true, the way a good therapist periodically checks assumptions?

**Open question:** Is there an active context revision mechanism, or does the profile only grow and expire? In lacquerware terms: does the system sand between layers, or does it just keep applying new layers on top of unchallenged old ones?

---

## Finding 7: No Colotomic Structure — Use Cases Lack Temporal Hierarchy

**Severity:** P1
**Agent:** fd-gamelan-orchestral-stratification
**Type:** Concrete improvement

**Source domain mechanism:** Javanese gamelan music is organized by *colotomy* — a hierarchical time-cycle structure where the largest gong (gong ageng) marks the longest cycle, the kempul marks subdivisions, the kenong marks smaller subdivisions, and fast instruments (bonang, saron) elaborate within the smallest subdivisions. Every musician knows where they are in the cycle because the gong structure provides orientation. The slow instruments do not merely repeat what the fast instruments do slowly — they operate at a categorically different level of musical meaning.

**Mapping to Auraken:** The PRD describes four temporal frequencies of interaction: per-turn cognitive augmentation (the saron — fast elaboration), follow-up accountability (the kenong — weekly subdivision), growth tracking (the kempul — monthly subdivision), and the overall cognitive profile evolution (the gong ageng — the longest cycle). But these are described as independent features (PRD.md lines 263-316 lists them as separate version milestones: v1.0, v2.0) rather than as a unified temporal hierarchy where each frequency frames and contextualizes the others. There is no described mechanism by which the monthly growth observation frames the meaning of daily conversations, the way the gong cycle frames the meaning of every note played within it.

**Failure scenario:** Without colotomic structure, the system will produce four independent value streams that feel disconnected. The user gets good per-turn reframes, useful follow-ups, and periodic growth reports — but none of these feel like they are part of the same musical piece. The growth report does not reference the specific daily conversations that evidenced the growth. The follow-up does not connect to the broader growth arc. Each voice plays its own tune.

**Recommendation:** Define an explicit temporal hierarchy in the PRD where longer-cycle features explicitly frame shorter-cycle ones. The monthly growth observation should synthesize evidence from daily conversations and weekly follow-ups. The weekly follow-up should reference the current growth arc. The per-turn reframe should be aware of the active growth theme. This is not merely cross-referencing — it is structural: the gong cycle determines which elaborations the saron plays.

---

## Finding 8: The Missing Inner Melody (Lagu Batin)

**Severity:** P3
**Agent:** fd-gamelan-orchestral-stratification
**Type:** Opens a new question

**Source domain mechanism:** In gamelan, the *lagu batin* (inner melody) is the melody that no single instrument plays but that all instruments imply through their interlocking parts. Expert listeners hear it; novice listeners hear only the individual instruments. The inner melody is the emergent meaning of the ensemble — it exists only in the relationship between voices.

**Mapping to Auraken:** If Auraken's four use cases (cognitive augmentation, ambient recommendations, learning/growth, pattern awareness) are the gamelan voices, what is the inner melody — the emergent capability that none of them produces alone but that all of them together imply? VISION.md's thesis suggests it might be "agency" — the user's increasing capacity to act effectively in the world. But this is stated as a goal, not as an emergent property of the use case interlock. The question: when cognitive augmentation helps a user think better about a decision, and ambient recommendations surface a relevant tool, and growth tracking shows the user applying frameworks independently, and pattern awareness reveals a cross-domain connection — what does the user experience as the unified meaning of all four? If the answer is just "Auraken is helpful in many ways," there is no inner melody.

**Open question:** Can the PRD articulate the emergent capability that arises specifically from the *combination* of use cases, distinct from what any single use case delivers? This would be the product's inner melody — the thing that makes Auraken a life operating system rather than four useful features in a trenchcoat.

---

## Finding 9: No Kendang (Drummer/Coordinator) Between Use Cases

**Severity:** P2
**Agent:** fd-gamelan-orchestral-stratification
**Type:** Concrete improvement

**Source domain mechanism:** The *kendang* (drum) in gamelan does not play melody — it coordinates. The drummer signals tempo changes, transitions between sections, and cues entrances. Without the kendang, the ensemble would have no mechanism for shifting between sections or adapting to the dalang's dramatic needs. The kendang is meta-musical: it is about the music, not in the music.

**Mapping to Auraken:** The PRD describes the OODARC conversation model (lines 63-79) as the engine for cognitive augmentation, but OODARC is designed for single-use-case interaction. What coordinates the transition between use cases within a conversation? When a user's career discussion reveals a product need, or when a follow-up conversation reveals a growth pattern, something must decide to shift registers. The PRD's Cynefin pre-filter (lines 82-92) classifies problem domains but not use case domains. Journey 7 (Multi-Problem Juggling, lines 218-235) describes tracking multiple threads but not transitioning between use case modes.

**Recommendation:** Define a meta-layer above OODARC that functions as the kendang — a use case coordinator that tracks which mode the system is in, detects signals that warrant mode transitions, and manages the transition itself. This coordinator does not deliver value directly; it ensures the right use case is active for the current conversational moment.

---

## Finding 10: Constitutional vs. Symptomatic Use Case Taxonomy Is Absent

**Severity:** P1
**Agent:** fd-constitutional-herbalism-terrain
**Type:** Concrete improvement

**Source domain mechanism:** Constitutional herbalism distinguishes sharply between *constitutional remedies* (deep, slow, whole-person: adaptogenic herbs like ashwagandha taken for months to shift baseline physiology) and *symptomatic remedies* (fast, targeted: peppermint tea for an upset stomach). Applying a constitutional remedy to a symptomatic need wastes resources. Applying a symptomatic remedy to a constitutional need treats symptoms while the root cause progresses.

**Mapping to Auraken:** The four use cases span a wide depth spectrum, but the PRD does not explicitly classify them. Mapping to the herbalism framework:

- **Constitutional (deep context, slow value):** Cognitive augmentation (builds thinking patterns over months), growth tracking (requires longitudinal observation), pattern awareness/self-knowledge (needs cross-domain warm data accumulated over many sessions)
- **Symptomatic (shallow context, immediate value):** Quick reframes for simple problems (Clear domain in Cynefin), product lookups, factual questions
- **Transitional (symptomatic surface, constitutional depth):** Ambient recommendations (appear symptomatic — "here's a product" — but require constitutional context to be good), follow-up accountability (appears as a simple check-in but connects to deep growth arcs)

The PRD's Cynefin pre-filter (lines 82-92) classifies problem complexity but not interaction depth. A "Clear" domain problem could still be constitutionally significant if it is the third instance of a recurring pattern.

**Failure scenario:** Without this taxonomy, Auraken will apply constitutional depth to symptomatic needs (user asks "what's a good project management tool?" and gets a 10-message exploration of their relationship to control and delegation) or symptomatic depth to constitutional needs (user describes a career crisis and gets a single reframe that addresses the surface symptom).

**Recommendation:** Add a depth classification to the OODARC model that runs alongside Cynefin. Every interaction should be classified on two axes: domain complexity (Cynefin: clear/complicated/complex/chaotic) AND depth requirement (symptomatic/transitional/constitutional). This dual classification determines both the conversation strategy and which use case capabilities to activate.

---

## Finding 11: The Terrain Concept — Same Signal, Different Constitution

**Severity:** P2
**Agent:** fd-constitutional-herbalism-terrain
**Type:** Concrete improvement

**Source domain mechanism:** In constitutional herbalism, the same symptom (e.g., insomnia) in different constitutional types requires different treatments. A "hot/dry" constitution with insomnia needs cooling, moistening herbs (passionflower, chamomile). A "cold/damp" constitution with insomnia needs warming, stimulating herbs (valerian, ginger). Treating the symptom without understanding the terrain produces inconsistent results at best and adverse effects at worst.

**Mapping to Auraken:** The PRD's Profile Architecture captures thinking patterns but does not define user *terrain* — the constitutional type that determines how the same surface need should be addressed differently. Two users both asking about career decisions might have radically different terrains: one is a chronic over-analyzer who needs to be pushed toward action (warming), another is a chronic impulsive decider who needs to be slowed down (cooling). The cognitive profile captures this implicitly through accumulated warm data, but there is no explicit terrain model that would allow the system to classify users along constitutional axes and adjust its approach systematically.

**Mapping to recommendations specifically:** The Robinson insight about window-shopping vs. aggressive sales is a terrain observation. Some users have a "browsing" constitution — they enjoy discovery and resist being told what to buy. Others have a "decisive" constitution — they want clear recommendations and find browsing wasteful. The same ambient recommendation strategy applied to both terrains will satisfy neither.

**Recommendation:** Consider defining 2-3 constitutional axes for user terrain that affect how all use cases modulate their approach. Candidates from the PRD's existing Laban dynamics (lines 44-49): Direct/Indirect, Sustained/Sudden, Light/Strong. These already capture something like constitutional type. Making them explicit as terrain dimensions (rather than just conversation dynamics) would allow systematic modulation of use case behavior.

---

## Finding 12: Symptomatic Patterns Revealing Constitutional Issues — The Escalation Path

**Severity:** P2
**Agent:** fd-constitutional-herbalism-terrain
**Type:** Concrete improvement

**Source domain mechanism:** An experienced herbalist treats a headache symptomatically but watches for patterns. Three headaches in a month with the same presentation suggest a constitutional issue — perhaps liver congestion, hormonal imbalance, or chronic tension. The symptomatic treatment addresses the immediate need; the pattern recognition triggers constitutional investigation. The two timescales work together: symptomatic treatment buys time while constitutional assessment proceeds.

**Mapping to Auraken:** Journey 7 (Multi-Problem Juggling, PRD.md lines 218-235) describes cross-thread synthesis, and the system tracks recurring themes. But there is no described mechanism for a *symptomatic* use case (quick product lookup, simple reframe) to escalate into a *constitutional* one. If a user asks for three different project management tool recommendations over two months, that is a symptomatic pattern revealing a constitutional issue — perhaps a deeper problem with how they structure work, delegate authority, or manage overwhelm. The system should detect this escalation path and offer to shift from symptomatic to constitutional depth.

**Recommendation:** Add an escalation detector to the profile architecture that monitors symptomatic interactions for constitutional patterns. When a user's quick/shallow interactions cluster around the same theme (three product queries in the same category, repeated simple reframes for the same type of problem), the system should surface the pattern: "You've asked about productivity tools three times now. I'm starting to wonder if the real question isn't about tools at all — want to dig into what's behind the search?"

---

## Finding 13: The Abrash Effect — Productive Variation Across Use Cases

**Severity:** P3
**Agent:** fd-persian-carpet-weaving-composition
**Type:** Opens a new question

**Source domain mechanism:** *Abrash* is the subtle color variation that occurs in hand-dyed wool when different dye batches produce slightly different shades. In machine-made carpets, this variation is eliminated for uniformity. In handmade carpets, abrash is prized — it gives the carpet visual warmth, evidence of human craft, and a quality of being alive rather than manufactured. Deliberate uniformity looks cold; natural variation looks warm.

**Mapping to Auraken:** As Auraken expands across use cases, there will be pressure to enforce uniform interaction patterns — same tone, same depth, same pacing across cognitive augmentation, ambient recommendations, learning, and pattern awareness. But the abrash insight suggests that productive variation between use cases is a feature. Cognitive augmentation should feel like a deep conversation with a sharp consultant. Ambient recommendations should feel like window shopping with a friend who knows your taste. Growth tracking should feel like a quarterly review with a mentor who has been watching. Pattern awareness should feel like a sudden insight that surprises you. These are different *textures* of the same product.

**Open question:** Does the system deliberately cultivate different interaction textures for different use cases, or does it default to a uniform conversational register? The style mirroring feature (PRD.md lines 38-49) adapts to the user but not necessarily to the use case mode. The agent might need to mirror the user's style *while also* varying its own register by mode.

---

## Finding 14: The Honest Value Curve — Invisible Layers Acknowledged

**Severity:** P2
**Agent:** fd-chinese-lacquerware-layering
**Type:** Concrete improvement

**Source domain mechanism:** A lacquerware artisan knows that most of the 60+ layers will be invisible in the final product. The inner layers provide structural integrity; only the final decorative layers are visible. But the artisan does not pretend the inner layers are unnecessary — their contribution is structural, not aesthetic. A client who asks "why does this take six months?" deserves an honest answer about invisible layers, not a promise that each layer will be individually beautiful.

**Mapping to Auraken:** The PRD defines success metrics (lines 342-349) that are all user-facing: engagement rates, return rates, independent lens application. But for use cases with long accumulation periods (ambient recommendations, growth tracking), there is no user-facing communication of the value curve. PHILOSOPHY.md principle 9 ("Accumulation creates value," line 43) acknowledges this internally, but the product design does not include a mechanism for communicating to the user that the system is in an accumulation phase. The user experiences sessions 1-20 of ambient recommendation context-building as... nothing. No recommendations appear. The system is silently building layers, but the user may interpret silence as absence of capability.

**Recommendation:** Design an honest value curve communication for each use case. For ambient recommendations: "I'm learning what matters to you — I'll start surfacing things when I'm confident they'll be useful, not before." For growth tracking: "I need a few more sessions before I can see patterns in how your thinking is changing." This aligns with the anti-dependency principle (PHILOSOPHY.md line 35) — the system is honest about its own limitations rather than trying to appear omniscient from day one.

---

## Finding 15: Acute-Before-Constitutional Sequencing

**Severity:** P2
**Agent:** fd-constitutional-herbalism-terrain
**Type:** Concrete improvement

**Source domain mechanism:** A responsible herbalist addresses acute symptoms before beginning constitutional work. A patient presenting with acute bronchitis and chronic fatigue gets antimicrobial herbs for the bronchitis first, *then* constitutional assessment for the fatigue. Attempting deep constitutional work while someone is acutely ill is inappropriate — they cannot engage with deep inquiry while suffering.

**Mapping to Auraken:** The PRD's OODARC model does not explicitly sequence acute/symptomatic needs before constitutional/deep ones within a session. Journey 4 (Cognitive Growth, PRD.md lines 173-178) describes long-term development, and Journey 1 describes first contact. But what about the user who arrives in acute distress ("Everything is falling apart at work right now" — PRD.md line 89, the Chaotic domain)? The Cynefin pre-filter classifies this as chaotic, but the system's response should go beyond domain classification: it should prioritize stabilization (symptomatic) before pattern exploration (constitutional). The user in crisis does not need to hear about their recurring avoidance pattern — they need one concrete thing to do right now.

**Recommendation:** Add an explicit acute-first rule to the OODARC model: when the system detects acute distress signals (Chaotic domain classification, emotional intensity markers, urgency language), it should restrict itself to symptomatic engagement — short, grounding, actionable — before shifting to constitutional depth. The constitutional observation ("this is part of a pattern") can be noted internally but should not be surfaced until the acute phase resolves.

---

## Cross-Domain Convergence

Three of four agents independently identify the same structural gap: **Auraken lacks a mechanism for managing the interaction between use cases that operate at different depths and timescales.** The carpet weaver calls it "missing borders." The lacquerware artisan calls it "undefined curing times." The gamelan dalang calls it "missing colotomy." The herbalist calls it "absent triage." These are four metaphors for the same architectural need: a meta-layer that understands which mode of engagement is appropriate for the current moment and manages transitions between modes.

This convergence suggests the highest-priority architectural addition is not any single use case, but the **coordination layer** that allows use cases to coexist productively — the OODARC model extended with use case awareness, depth classification, and transition management.
