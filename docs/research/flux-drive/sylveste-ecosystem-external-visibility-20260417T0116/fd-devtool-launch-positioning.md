# fd-devtool-launch-positioning — Review

## Findings Index
- P0: README Tagline as 30-Word Philosophy — first-time reader cannot articulate the wedge after 60 seconds
- P0: Architecture Table Ahead of Claim — three-layer/six-pillar taxonomy is the first visible structure, priming "platform" allergy
- P1: Dual-Brand Framing in MISSION.md — Garden Salon and Meadowsyn named before the v1.0 wedge is established
- P1: OODARC and "Wired or It Doesn't Exist" Buried in PHILOSOPHY.md — two genuinely novel primitives with spread potential, invisible from outside
- P2: 64-Plugin Inventory Surfaced via Interchart and Marketplace — ecosystem diagram leads with scale, not capability

## Verdict
Polish → then ship — the wedge exists inside PHILOSOPHY.md but is completely invisible from the public surface; one week of subtractive editing plus one concept-coining post unlocks the attention window without any new build work.

## Summary

The tagline is the problem. "A monorepo for building software with agents, where the review phases matter more than the building phases" buries the actual claim — that most agent tools skip the thinking phases — inside a sentence that opens with the word "monorepo." The Docker pivot lesson here: Solomon didn't pitch dotCloud's internal tooling as a monorepo; he showed you what a container was in 90 seconds. Sylveste has genuine primitives — OODARC's Reflect+Compound extension and "wired or it doesn't exist" as a diagnostic for incomplete agent work — but neither appears before PHILOSOPHY.md. The architecture table (three layers, six pillars, 64 plugins) is what greets a technically serious reader before they reach any of it. The remedy is subtractive: collapse the README to one claim, hide the dual-brand framing until the wedge earns trust, and treat PHILOSOPHY.md as the source material for the one blog post that earns an HN front page.

## Issues Found

### [P0] README Tagline Fails One-Frame Claim Test
**Target (inventory item):** `README.md` tagline — "A monorepo for building software with agents, where the review phases matter more than the building phases, and the point is not to remove humans from the loop but to make every moment in the loop count."
**Verdict:** Polish
**Why (your lens):** The distinctive claim — that agent tools skip brainstorm/strategy/spec phases and Clavain makes these first-class — is real and non-obvious. But it's the subordinate clause. The subject and verb are "monorepo for building software with agents," which triggers the 'we built a platform' recognition pattern before the reader reaches the actual idea. Compare: Prisma's tagline names a known job-to-be-done ("ORM") and qualifies it; Astro named a specific structural concept ("islands"); Rails showed the job in 15 minutes. "Monorepo" names an organizational structure. It answers "how is this arranged?" before the reader has asked "what does this do for me?"
**Failure scenario:** A technically serious reader hits the tagline, sees "monorepo," scans down to the three-layer/six-pillar architecture table, and leaves with the "another platform" pattern activated. They never reach PHILOSOPHY.md. First impression set in under 30 seconds; update rate extremely low.
**Concrete action this week:** Rewrite to lead with the claim: *"Agent scaffolding that makes brainstorm, strategy, and spec phases first-class — because the thinking is where the leverage is."* Test it: can someone who's never seen Sylveste restate the claim in their own words after one read?

---

### [P0] Architecture Table as First Structural Signal
**Target (inventory item):** `README.md` — architecture table (Layer 1 / Layer 2 / Layer 3, six pillars) appearing above the fold
**Verdict:** Hide (move below fold)
**Why (your lens):** The table answers "how is this organized?" before the reader has reason to care. Every pre-1.0 platform launch I've watched that led with taxonomy did so because the builder is proud of the structure — and the structure is genuinely impressive. But structure is not the claim. Rails' 15-minute blog demo didn't start with "we have models, views, controllers, and helpers" — it started by creating a working blog. The three-layer/six-pillar table is useful reference material for someone already committed to learning Sylveste; it's architecture documentation premature-promoted to marketing copy.
**Failure scenario:** The architecture table is the second thing a reader sees, immediately after a tagline that already primed "platform." The two signals compound. Reader concludes: complex, not yet my problem.
**Concrete action this week:** Move the table below the fold. The fold content should be: claim → one concrete demonstration (screencast link or terminal recording) → install. Table at H2 level or below, not the opening.

---

### [P1] Dual-Brand Framing in MISSION.md Before Wedge Is Established
**Target (inventory item):** `MISSION.md` — two-brand framing (Sylveste + Garden Salon), plus Meadowsyn named in public inventory
**Verdict:** Hide (Garden Salon + Meadowsyn) until after v1.0 wedge earns trust
**Why (your lens):** Every dual-brand pre-1.0 developer infrastructure launch I've observed hurts the project. The reader's mental model fractures: is Sylveste the kernel, or the experience layer, or the visualization layer? Docker didn't mention Swarm in the original launch. Astro didn't name its build tool separately from its islands concept. The dual brand signals identity uncertainty. Garden Salon isn't launched; Meadowsyn has a domain but no content. They cost attention without offering return. Deno's initial HN narrative error is instructive here: "we're rewriting Node" before showing what Deno actually did caused a framing fight that consumed the attention window.
**Failure scenario:** A reader sees "Sylveste" (infrastructure), "Garden Salon" (experience layer), and "Meadowsyn" (visualization bridge) in the first encounter. They conclude: "they don't know what they are yet." They do not click again.
**Concrete action this week:** Remove Garden Salon and Meadowsyn from MISSION.md's external-facing text. One brand for now. Reintroduce when either product is launched or when the Sylveste wedge is established.

---

### [P1] OODARC and "Wired or It Doesn't Exist" Buried in PHILOSOPHY.md
**Target (inventory item):** `PHILOSOPHY.md` — claims 4 ("OODARC, not OODA") and 5 ("Wired or it doesn't exist")
**Verdict:** Ship (as a blog post, not as a doc)
**Why (your lens):** These are the two most exportable primitives in the inventory. "OODARC" has a name, a lineage (Boyd), and a specific extension (Reflect + Compound) that diagnoses a real failure mode in agent pipelines. "Wired or it doesn't exist" is a sharp diagnostic that any senior practitioner working with agent-built codebases will immediately recognize from their own experience with steps 1-2 shipping without steps 3-4. Astro coined "islands architecture" in a blog post before the framework was mature; the concept spread ahead of adoption. Sylveste has two concepts at least as sharp, and neither is externally visible.
**Failure scenario:** A technically serious reader who would immediately understand and share "OODARC's Compound step" never encounters it because it lives three clicks deep inside a monorepo they didn't bookmark.
**Concrete action this week:** Write one blog post: "OODARC: Why agent pipelines need Reflect and Compound after Act." 600–800 words. One working code example from Clavain's phase structure showing the Reflect step emitting evidence and the Compound step writing calibration. Post to HN as "Show HN." This is the concept-coining moment — use it.

---

### [P2] 64-Plugin Inventory Surfaced via Interchart and Marketplace
**Target (inventory item):** `mistakeknot/interagency-marketplace` and ecosystem diagram at `mistakeknot.github.io/interchart/`
**Verdict:** Hide (from primary external discovery path)
**Why (your lens):** The interchart diagram answers "how much did they build?" A technically serious reader's reaction to 64 plugins before they understand the core claim is not admiration — it's the complexity tax. "How do I evaluate this?" is not the question you want them asking in the first 30 seconds. Prisma didn't open with its full adapter list; it opened with the schema language. The marketplace and diagram belong in documentation for committed adopters, not in the external discovery surface.
**Failure scenario:** Someone linked to interchart as a "look what Sylveste is" artifact comes away thinking "this is complex" rather than "this solves a specific thing I have."
**Concrete action this week:** Remove the interchart link from README.md and any external-facing context. Retain it in docs for adopters. The diagram has value as a map for users who are already committed — not as a first impression.

---

## Improvements
- The `estimate-costs.sh` closed-loop pipeline (claim 3's existence proof) is a concrete credibility artifact — a working benchmark showing calibrated cost estimation from historical actuals. Consider a short screencast: "How Sylveste calibrates its own agent costs in real time." Concrete output, non-obvious method, no additional build required.
- Claims 8 ("Disagreement between models is the highest-value signal") and 9 ("Zollman effect / sparse topology") both have academic backing. A short post citing the original Zollman paper plus a working implementation in Sylveste earns researcher-tier attention at almost zero build cost.

## Single Highest-Leverage Move
Write the OODARC blog post, rewrite the README tagline to match its claim, and post both to HN — the concept coinage plus the working system reaches the right audience in one move, with no additional infrastructure built.

<!-- flux-drive:complete -->
