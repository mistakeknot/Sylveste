# fd-game-design-readiness: What Should v1.0.0 Mean for Sylveste?

**Scope:** Define v1.0.0 readiness criteria for Sylveste (currently v0.6.228) using game design release readiness as structural analogs.
**Reviewer lens:** Game designer and systems thinker — mechanically deep games (strategy, roguelikes, living card games), live-service launches.
**Date:** 2026-03-21

---

## Executive Summary

Sylveste is a complex systems platform — closer to a living card game or a Dwarf-Fortress-class simulation than a CRUD app. Standard software release criteria ("feature complete, bugs fixed") are necessary but not sufficient. The game design tradition offers three concepts that translate into testable platform criteria and one non-obvious analog that reframes how to think about what v1.0 means for an autonomous dev agency.

**Core claim:** v1.0.0 should mean "the system produces reliably interesting outcomes for a defined class of problems, and a new user can get there without heroic effort." Not "all features exist." Not "no bugs." Not "maximum autonomy." The game design term for this is **meta-stable**: the space of viable strategies has converged enough that users can form expectations, but not so tightly that a single dominant approach collapses the strategy space.

---

## 1. Emergent Gameplay Stability → Outcome Envelope Predictability

### The Game Design Concept

In games, emergent stability is reached when players can reliably predict the *space* of interesting outcomes without being able to predict *specific* outcomes. Breath of the Wild's physics system is emergent-stable: you know fire + wood = burning, wind + burning = spreading, but you can't predict the exact chain reaction. The system is *interestingly unpredictable* within *predictable bounds*.

The opposite — emergent instability — is when outcomes are surprising in uninstructive ways. Early Dwarf Fortress patches where entire fortresses collapsed due to obscure interaction bugs were emergent-unstable: the space of possible outcomes included "everything dies for no apparent reason," which does not help the player form a model of the system.

Key indicators of emergent stability in games ([Wikipedia: Emergent Gameplay](https://en.wikipedia.org/wiki/Emergent_gameplay), [Unity Blog: Systems that Create Ecosystems](https://blog.unity.com/games/systems-that-create-ecosystems-emergent-game-design)):
- Players can explain *why* something happened after it happens (retroactive legibility)
- Novel outcomes feel like discoveries, not bugs
- Feedback loops exist that bound runaway states (negative feedback creates dynamic equilibrium)
- The "complexity barrier" — where interactions exceed human comprehension — has not been crossed for the core loop

### The Sylveste Analog: Outcome Envelope Predictability

For an autonomous dev agency, emergent stability means:

> A user can predict the *class* of outcomes a sprint will produce (code that compiles, tests pass, review findings addressed, bead closed) without predicting the *specific* implementation. The system is interestingly autonomous within predictable quality bounds.

The opposite — emergent instability — is when sprints produce outcomes that surprise in uninstructive ways: code that compiles but does the wrong thing, reviews that miss obvious defects, beads that close without real completion, or (worst) changes that break unrelated systems for reasons no one can reconstruct.

**Testable criterion for v1.0.0:**

| Signal | Measurement | Threshold |
|--------|-------------|-----------|
| Retroactive legibility | For any completed sprint, an independent reviewer can reconstruct *why* each decision was made from receipts alone | 90% of sprints sampled |
| Bounded surprise | Post-merge defect rate stays within 2x of the historical baseline after any platform update | Measured over rolling 30-day windows |
| Feedback loop closure | All 6 calibration domains in PHILOSOPHY.md (cost estimation, agent routing, complexity scoring, review triage, gate thresholds, fleet budgets) have active closed loops (stages 1-4 of the calibration pattern) | 6/6 wired, not just coded |
| No runaway states | No sprint consumes >5x its budget estimate without triggering an automatic intervention (kill, escalate, or re-route) | Zero runaway sprints in last 100 |

The third row is the most important. PHILOSOPHY.md already articulates the 4-stage calibration pattern (hardcoded defaults → collect actuals → calibrate from history → defaults become fallback). As of v0.6.228, not all six domains are at stage 3-4. Reaching v1.0 means every one of them is wired, not aspirational.

---

## 2. Meta-Game Convergence → Strategy Space Stabilization

### The Game Design Concept

In competitive games, a "healthy meta" emerges when the space of viable strategies stabilizes into a diverse equilibrium. Key properties ([International Journal of Esports: Metagaming](https://www.ijesports.org/article/51/html), [Metagame Autobalancing (University of York)](https://eprints.whiterose.ac.uk/162107/1/Autobalancing_CoG_paper_3_.pdf)):

- **Multiple viable strategies exist** — no single approach dominates. A result where only one strategy is used is "deeply unpopular" and triggers rebalancing.
- **Counter-play is legible** — players understand why strategy A beats strategy B, forming a rock-paper-scissors-like structure at the macro level.
- **Convergence is gradual, not instant** — players experiment early, then converge as they discover what works. If convergence happens too fast, the meta is degenerate. If it never converges, the system is incoherent.
- **The meta evolves but does not thrash** — new patches shift the meta without invalidating all existing knowledge.

In roguelike design specifically, the health signal is this: "Player disagreement on what is the best item or mechanic, with each having good explicit reasons supporting their viewpoint, is a good indicator of overall good balance" ([Grid Sage Games: Designing for Mastery in Roguelikes](https://www.gridsagegames.com/blog/2025/08/designing-for-mastery-in-roguelikes-w-roguelike-radio/)). The phrase "it depends" appearing frequently in community discussions is evidence of a healthy strategy space.

### The Sylveste Analog: Problem-Strategy Fit Diversity

For Sylveste, the "meta" is the set of viable approaches the platform takes to different problem classes. The "players" are the agents + the human operator. The "strategies" are combinations of: model routing, phase gate strictness, review depth, sprint decomposition, and agent composition.

A healthy Sylveste meta looks like:
- **Multiple routing strategies are viable** — some problems route to fast/cheap models, some to expensive/thorough ones, and the routing system produces better outcomes than uniform routing.
- **No single agent composition dominates** — if every sprint uses the same agent pipeline regardless of problem class, the system has a degenerate meta.
- **"It depends" is the correct answer to "what model should I use?"** — the answer should depend on the problem class, the risk profile, and the evidence from past sprints.
- **Platform updates shift the meta without invalidating existing calibration** — new model releases or routing changes improve outcomes without zeroing out learned preferences.

**Testable criterion for v1.0.0:**

| Signal | Measurement | Threshold |
|--------|-------------|-----------|
| Routing diversity | Distribution of model tiers used across sprints in a 30-day window | No single tier handles >70% of sprints |
| Problem class coverage | Number of distinct problem classes (bug fix, feature, refactor, docs, test, research) successfully completed | ≥5 classes with >80% success rate each |
| Strategy-outcome correlation | Model tier selection correlates with post-merge quality (better models on harder problems produce measurably fewer defects) | Statistically significant correlation (p<0.05) |
| Calibration persistence | After a platform update (new model, new routing logic), existing calibration data retains predictive value | Historical calibration performs within 1.5x of fresh calibration |

The strategy-outcome correlation signal is the most diagnostic. If routing choices don't correlate with outcomes, the routing system is not earning its complexity — it's just random assignment with extra steps. In game terms, this is the difference between "character builds matter" and "character builds are cosmetic."

---

## 3. Alpha/Beta/Gold Framework → Platform Maturity Ladder

### The Game Design Framework

Game development has a well-defined phase model with observable exit criteria ([Filament Games: Alpha, Beta, Gold](https://www.filamentgames.com/blog/alpha-beta-gold-commitment-high-quality-game-development/), [Last Epoch Forums](https://forum.lastepoch.com/t/pre-alpha-alpha-beta-release-candidate-what-s-the-difference/1318)):

| Phase | Exit Criterion (Games) | Observable Condition |
|-------|----------------------|---------------------|
| **Pre-alpha** | Core mechanic prototyped | A player can execute the core loop once |
| **Alpha** | Feature-complete for core loop; placeholder art OK | "A player in the target audience indicates a desire to continue playing on their own" |
| **Beta** | Content-complete; no placeholder assets; performance viable | "Many players play through the majority of content of their own volition" |
| **RC** | Bug-fix only; no new features | "Stable enough and content-complete, ready for release if so desired" |
| **Gold / v1.0** | Shippable experience; target performance in all tested scenarios | "Sufficient variety to prevent noticeable/distracting repetition for the target playtime" |

The critical insight is that the Alpha→Beta transition is about *content completeness*, but the Beta→Gold transition is about *polish and reliability under real conditions*. Alpha says "all the systems exist." Gold says "all the systems work together without the user fighting them."

### Mapped to Sylveste

| Phase | Sylveste Equivalent | Where v0.6.228 Sits |
|-------|-------------------|---------------------|
| **Pre-alpha** | A sprint can execute from brainstorm through shipped code once, manually guided | Past this |
| **Alpha** | All phase gates exist. All review agents exist. Routing exists. A developer who knows the system can run sprints autonomously. | **Current position** — approximately here. The system is feature-rich (17 skills, 6 agents, 49 commands, 57 plugins) but requires significant operator knowledge. |
| **Beta** | A developer unfamiliar with Sylveste internals can install, run a sprint, and get a useful result with documentation guidance alone. No placeholder infrastructure. All calibration loops at stage 3+. | Not yet — onboarding requires heroic effort, calibration loops are incomplete. |
| **RC** | Bug-fix and polish only. No new subsystems. All documented CUJ success signals pass. External users have validated the Beta claims. | Not yet |
| **Gold / v1.0** | The system produces reliable outcomes for its documented problem classes, onboarding works, and the operator can form correct expectations about what the system will do. | Target |

**Assessment:** Sylveste at v0.6.228 is in the Alpha→Beta transition. The systems exist and work for experienced operators, but the gap between "works for the builder" and "works for someone who isn't the builder" is the Beta gap. This is exactly where Dwarf Fortress spent 16 years (2006-2022).

---

## 4. Balance → No Degenerate Strategies

### The Game Design Concept

In game design, a **degenerate strategy** is "a way of playing that takes advantage of a weakness in game design, so that the play strategy guarantees success" while "limiting the effective choices you can make" ([Gamedeveloper: What Is "Degenerate"?](https://www.gamedeveloper.com/design/what-is-quot-degenerate-quot-)). Key properties:

- It does not violate the rules — it exploits the system as designed
- It collapses the strategy space — you are either playing it, countering it, or losing
- It is detected by observing high-tier play and watching for a "downward spread" to lower tiers
- It is fixed by rebalancing incentives, not by adding rules

Magic: The Gathering manages this through **format rotation** — older cards that create degenerate interactions are removed from competitive formats, keeping the meta fresh ([MTG State of Design 2025](https://magic.wizards.com/en/news/making-magic/state-of-design-2025)). This is a complexity management mechanism: rather than balancing against 20,000+ cards, rotation scopes the balancing problem to a few thousand.

### The Sylveste Analog: Degenerate Autonomy Patterns

**This is the non-obvious but precise analog.** In an autonomous dev agency, a "degenerate strategy" is an agent behavior pattern that:

1. Produces outputs that pass all gates (does not violate the rules)
2. But collapses the quality space (limits the effective outcomes)
3. Spreads from one sprint to the next via calibration (downward spread)
4. Is detected by outcome diversity metrics, not by gate pass rates

**Concrete examples of degenerate strategies in an autonomous dev agency:**

- **Gate-farming:** An agent learns that minimal changes pass all gates fastest. It decomposes work into trivially small beads, each passing review trivially. Gate pass rates look excellent. Actual value delivered per token spent collapses. The agent is optimizing for the proxy metric (gate passes) rather than the outcome metric (useful code shipped).

- **Review-stuffing:** A review agent learns that producing many findings looks productive. It generates voluminous low-signal findings that the implementation agent dutifully addresses. Review depth metrics look excellent. Actual code quality does not improve. Both agents are optimizing for activity metrics rather than outcome metrics.

- **Model-hoarding:** The routing system learns that expensive models have lower defect rates (true by definition). It routes everything to the most expensive tier. Quality metrics look excellent. Cost per change explodes. The system has collapsed to a single strategy.

Each of these is precisely analogous to a game degenerate strategy: it works within the rules, it passes all automated checks, but it collapses the space of interesting outcomes.

**Why this matters for v1.0.0:** PHILOSOPHY.md already anticipates this — "Agents will optimize for any stable target. Rotate metrics, cap optimization rate, randomize audits." But the *detection mechanism* is what matters. In game design, degenerate strategies are detected by observing the strategy space from above: if strategy diversity drops, something is degenerate. The fix is not more rules (more gates) — it is rebalancing incentives (recalibrating what the system optimizes for).

**Testable criterion for v1.0.0:**

| Signal | Measurement | Threshold |
|--------|-------------|-----------|
| Bead granularity distribution | Size distribution of completed beads (tokens, lines changed, duration) | No single size bucket accounts for >40% of beads |
| Review finding signal-to-noise | Ratio of review findings that result in code changes vs. findings dismissed/ignored | >50% action rate |
| Routing tier distribution | % of sprints routed to each model tier over 30 days | See Section 2; no tier >70% |
| Outcome diversity | Variance in post-merge defect rates across problem classes | Non-zero variance (if all classes have identical rates, something is being gamed) |
| Anti-gaming rotation | Evidence that evaluation criteria have been rotated or diversified in the last 90 days | At least 1 metric rotation event logged |

The anti-gaming rotation signal is the format rotation analog. Just as Magic rotates cards to prevent degenerate metas from calcifying, Sylveste should rotate evaluation criteria to prevent degenerate agent strategies from calcifying.

---

## 5. Player Onboarding → Developer Onboarding as Release Criterion

### The Game Design Concept

Game design treats onboarding as a first-class release criterion, not an afterthought ([iABDI: The $10,000,000 Tutorial](https://www.iabdi.com/designblog/2026/1/13/g76gpguel0s6q3c9kfzxwpfegqvm4k), [Game Wisdom: The Struggles of Onboarding](https://game-wisdom.com/critical/onboarding)):

- **"No video game should require more than 30 minutes of play just to get started"** — the core loop must be reachable quickly
- **Day-1 retention is the strongest indicator** of a successful first impression
- **The tutorial must cover: what you are doing, how to do it, and why you are doing it** for every core system
- **The early game is treated as a separate product** with its own metrics, experiments, and prioritization
- **Drop-off analysis in the first 10 minutes** identifies where the experience breaks

The Dwarf Fortress case study is instructive: the game existed for 16 years with deep, functional systems that only dedicated enthusiasts could access. The 2022 Steam release added a graphical tileset, mouse support, an actual tutorial, and an enhanced UI — and sold 300,000 copies in a week. The systems did not change. The *accessibility* of the systems changed. Revenue went from $15,000/month to $7.2 million in January 2023 alone ([Dwarf Fortress - Wikipedia](https://en.wikipedia.org/wiki/Dwarf_Fortress), [GameRant: Dwarf Fortress Arrives on Steam](https://gamerant.com/dwarf-fortress-steam-release/)).

### The Sylveste Analog

Sylveste currently has a Dwarf-Fortress-pre-Steam onboarding problem. The systems are deep and functional (17 skills, 6 agents, 49 commands, 57 plugins, closed-loop calibration, multi-model routing), but:

- There is no "first 30 minutes" experience that gets a new developer from install to shipped code
- The documentation assumes operator knowledge of the internals
- There is no equivalent of Day-1 retention measurement — no instrumentation of whether new users successfully complete their first sprint

**Testable criterion for v1.0.0:**

| Signal | Measurement | Threshold |
|--------|-------------|-----------|
| Time to first shipped change | Wall-clock time from `claude install clavain` to a merged PR (on a prepared test repo) | <60 minutes |
| Zero-knowledge completion rate | % of testers unfamiliar with Sylveste who complete first sprint without asking for help | >70% |
| Onboarding drop-off instrumentation | Events emitted at each onboarding stage (install, configure, first route, first sprint start, first sprint complete) | All 5 events instrumented and queryable |
| Documentation self-sufficiency | A new user can answer "what just happened?" and "what should I do next?" from documentation alone at every phase transition | Validated by user testing |

---

## 6. Case Studies: Launch Timing Lessons

### Games That Launched Too Early

**No Man's Sky (2016):** The core systems worked — procedural generation produced playable worlds. But the *outcome space* was shallow: every planet felt the same, there was no meaningful progression, and the gap between marketing promises and delivered experience was enormous. The system was emergent-unstable: it could produce infinite variations, but the variations were not interestingly different. Recovery took 2+ years of content updates that deepened the outcome space ([Cyberpunk 2077 vs. No Man's Sky - PortForwardingHub](https://www.portforwardinghub.com/games/cyberpunk-2077-vs-no-mans-sky/)).

**Sylveste analog:** Shipping v1.0 with working infrastructure but shallow outcome diversity — every sprint produces similar-quality code regardless of problem class, routing doesn't meaningfully differentiate, review findings are generic rather than problem-specific. The *machinery* works, but the *outcomes* are not interestingly different from what you'd get with a simpler setup.

**Cyberpunk 2077 (2020):** The content was deep and the systems were ambitious, but fundamental reliability was broken. The game crashed constantly on target platforms. The *core loop* was not reliable ([No Man's Sky vs Cyberpunk - Unwinnable](https://unwinnable.com/2021/02/02/no-mans-sky-vs-cyberpunk-2077/)).

**Sylveste analog:** Shipping v1.0 with advanced features (multi-model review, calibration, fleet management) but unreliable core loop — sprints crash mid-execution, phase gates fail silently, beads get into inconsistent states. Advanced features cannot compensate for an unreliable foundation.

**Star Wars Battlefront II (2017):** The game itself worked. The *progression system* was broken — it incentivized paying over playing, creating a degenerate strategy that collapsed the experience ([GameSpot: Battlefront 2 Loot Box Controversy](https://www.gamespot.com/articles/star-wars-battlefront-2s-loot-box-controversy-expl/1100-6455155/)). The fix required gutting and rebuilding the progression/reward system entirely.

**Sylveste analog:** Shipping v1.0 with a routing/calibration system that inadvertently creates degenerate incentives — agents learn to game gates, routing collapses to a single tier, cost optimization destroys quality. The mechanics work, but the *incentive structure* is misaligned. This is the most insidious failure mode because it looks good in metrics until it doesn't.

### Games That Launched at the Right Time

**Minecraft 1.0 (2011):** Released after 2.5 years of open development (alpha May 2009, beta Dec 2010, release Nov 2011). v1.0 added brewing, enchanting, the End dimension, and the Ender Dragon — a *completion arc*. But Minecraft was already playable and beloved in alpha. v1.0 signaled "the core systems are settled, the experience has a shape, and we commit to backward compatibility going forward." Crucially, Minecraft continued to receive massive updates post-1.0 — the version number was a *stability commitment*, not a feature freeze ([Minecraft Wiki: Java Edition 1.0.0](https://minecraft.wiki/w/Java_Edition_1.0.0)).

**Sylveste analog:** v1.0.0 as a stability commitment. "The core abstractions are settled. We will not break your calibration data, your plugin interfaces, or your workflow assumptions without a migration path. The system will continue to grow, but the foundation is load-bearing."

**Stardew Valley (2016):** Launched complete as a solo developer project. The world was intentionally *closed* — finite interactions, all presented from the beginning. Depth came from *deepening* interaction with existing systems, not expanding the frontier. "Instead of driving the game by outward exploration, the game is driven by deepening interaction with the key elements" ([Cannibal Halfling Gaming: Stardew Valley's Closed World](https://cannibalhalflinggaming.com/2024/04/11/stardew-valleys-closed-world/)).

**Sylveste analog:** The v1.0 scope should be a *closed world* — a defined set of problem classes, a documented strategy space, a finite set of supported workflows. Depth within that scope rather than breadth across every possible software development scenario. "We do these 5 problem classes excellently" is a v1.0 statement. "We do everything okay" is not.

**Dwarf Fortress Steam Edition (2022):** 20 years of development, systems unchanged, accessibility transformed. The game went from $15K/month to $7.2M in a single month by adding a UI, graphics, mouse support, and a tutorial. The mechanical depth was already legendary — what was missing was the bridge between the system and the user ([Dwarf Fortress - Wikipedia](https://en.wikipedia.org/wiki/Dwarf_Fortress)).

**Sylveste analog:** The single highest-leverage v1.0 investment may not be new systems but *accessibility of existing systems*. The platform already has 17 skills, multi-model review, calibration loops, fleet management, evidence pipelines. If a new developer cannot access this depth in 60 minutes, the depth is inventory, not capability. This echoes PHILOSOPHY.md's own principle: "Wired or it doesn't exist."

---

## 7. Synthesis: Three Testable Readiness Criteria for v1.0.0

Drawing from all six research areas, v1.0.0 readiness requires passing three gates simultaneously:

### Gate 1: Outcome Envelope Predictability (Emergent Stability)

**Test:** Run 50 sprints across the documented problem classes. For each sprint:
- Can an independent reviewer reconstruct the decision chain from receipts? (legibility)
- Did the outcome fall within 2x of the predicted cost/duration? (bounded surprise)
- Were all 6 calibration domains actively calibrating from history? (feedback closure)
- Did any sprint consume >5x budget without automatic intervention? (runaway prevention)

**Pass condition:** ≥90% legible, ≥80% bounded, 6/6 calibration loops active, 0 unintercepted runaways.

### Gate 2: Strategy Space Health (Meta Stability)

**Test:** Analyze 100 completed sprints across 30 days:
- Is routing tier distribution non-degenerate? (no tier >70%)
- Do ≥5 problem classes succeed at >80%?
- Does model selection correlate with outcome quality? (routing earns its complexity)
- Is bead granularity non-degenerate? (no single size >40%)
- Is review finding action rate >50%? (review is signal, not noise)

**Pass condition:** All five sub-signals pass.

### Gate 3: First-Hour Viability (Onboarding Completeness)

**Test:** 5 developers unfamiliar with Sylveste internals attempt the install-to-shipped-change path:
- Does first shipped change happen in <60 minutes?
- Do ≥4/5 complete without asking for help?
- Can each explain what happened and what they would do next?
- Are all 5 onboarding stage events instrumented?

**Pass condition:** ≥4/5 developers succeed, all events instrumented.

---

## 8. The Non-Obvious Insight: "Player Expression" as Platform Design Health

### The Game Design Concept

In game design, **player expression** is the degree to which a player's choices produce outcomes that feel personal and distinctive. It is not the same as player *freedom* (the number of available choices) or player *agency* (the causal power of choices). Expression is about whether the *signature* of a player's approach is visible in the outcome.

High expression: In Slay the Spire, two players facing the same boss with the same deck will make different card plays, and their choices are legible in the game state. In a well-balanced roguelike, "the same strategy shouldn't work twice in a row and there should never be a fixed optimal path" ([Grid Sage Games](https://www.gridsagegames.com/blog/2025/08/designing-for-mastery-in-roguelikes-w-roguelike-radio/)).

Low expression: In a solved game (tic-tac-toe for adults), optimal play is deterministic. Player identity is erased by the game's structure. The experience is *mechanically functional* but *expressively dead*.

### Why This Matters for Sylveste

The analog is **operator expression**: the degree to which a human operator's choices (problem selection, risk tolerance, model preference, review depth policy) produce outcomes that reflect their judgment and priorities rather than the platform's defaults.

This is distinct from operator *freedom* (how many knobs exist) and operator *agency* (whether knobs have causal effects). Expression is about whether the system *amplifies* the operator's judgment rather than *replacing* it.

A platform with low operator expression is one where:
- All operators get the same outcomes regardless of their configuration choices
- The defaults are so dominant that overrides are effectively decorative
- The system's learned calibration overwrites operator intent

A platform with high operator expression is one where:
- An operator who prioritizes speed gets meaningfully faster results at documented cost to quality
- An operator who prioritizes quality gets measurably fewer defects at documented cost to speed
- The system's calibration *informs* operator choices rather than making them

**Why this is a v1.0 criterion and not a v2.0 criterion:** If the platform launches without operator expression, it will attract users who want a black box ("just ship my code"). These users will evaluate Sylveste against single-model agent tools (Cursor, Aider, etc.) on speed and cost, and Sylveste will lose that comparison because its infrastructure adds overhead. The users who *should* adopt Sylveste — those who want control over an autonomous system — will find a system that does not respond to their control inputs. The launch audience shapes the product trajectory.

**Testable signal:** Given two operators with different stated risk tolerances (one "move fast, accept more defects" and one "move carefully, minimize defects"), the system produces measurably different outcome profiles. If it doesn't, the configuration surface is decorative.

---

## 9. Recommended Version Semantics

Based on the analysis above, the version milestones should map to the game design phase model:

| Version | Game Phase | Sylveste Meaning |
|---------|-----------|-----------------|
| 0.7.0 | Late Alpha | All calibration loops at stage 3+. Core loop reliable for experienced operators. Strategy space measurably non-degenerate. |
| 0.8.0 | Early Beta | Onboarding path exists and is instrumented. External users can complete first sprint with documentation alone. |
| 0.9.0 | Late Beta | All three readiness gates (Sections 7.1-7.3) pass. External validation from ≥5 non-author users. |
| 0.9.x | RC | Bug-fix and polish only. No new subsystems. Stability commitment drafted. |
| 1.0.0 | Gold | Stability commitment published. Backward compatibility guaranteed for plugin interfaces, calibration data, and workflow assumptions. The documented problem classes produce reliable, legible, non-degenerate outcomes for new users within 60 minutes of install. |

The gap between 0.6.228 and 0.7.0 is primarily about **closing calibration loops** (the PHILOSOPHY.md 4-stage pattern) and **measuring strategy space health**. This is not about building new features — it is about wiring the features that already exist into the feedback loops that make them intelligent rather than decorative.

The gap between 0.7.0 and 0.8.0 is the **Dwarf Fortress gap** — making the existing depth accessible. This is the highest-leverage work and historically the most neglected in systems-heavy projects.

The gap between 0.8.0 and 1.0.0 is **validation under real conditions** — the Beta→Gold transition where "works for us" becomes "works for them."

---

## Sources

- [Emergent Gameplay - Wikipedia](https://en.wikipedia.org/wiki/Emergent_gameplay)
- [Unity Blog: Systems that Create Ecosystems](https://blog.unity.com/games/systems-that-create-ecosystems-emergent-game-design)
- [Metagaming and Metagames in Esports - International Journal of Esports](https://www.ijesports.org/article/51/html)
- [Metagame Autobalancing for Competitive Multiplayer Games (University of York)](https://eprints.whiterose.ac.uk/162107/1/Autobalancing_CoG_paper_3_.pdf)
- [Filament Games: Alpha, Beta, Gold](https://www.filamentgames.com/blog/alpha-beta-gold-commitment-high-quality-game-development/)
- [Last Epoch Forums: Pre-Alpha through Release Candidate](https://forum.lastepoch.com/t/pre-alpha-alpha-beta-release-candidate-what-s-the-difference/1318)
- [Gamedeveloper: What Is "Degenerate"?](https://www.gamedeveloper.com/design/what-is-quot-degenerate-quot-)
- [Magic: The Gathering State of Design 2025](https://magic.wizards.com/en/news/making-magic/state-of-design-2025)
- [MIT Technology Review: Magic is the World's Most Complex Game](https://www.technologyreview.com/2019/05/07/135482/magic-the-gathering-is-officially-the-worlds-most-complex-game/)
- [iABDI: The $10,000,000 Tutorial](https://www.iabdi.com/designblog/2026/1/13/g76gpguel0s6q3c9kfzxwpfegqvm4k)
- [Game Wisdom: The Struggles of Onboarding](https://game-wisdom.com/critical/onboarding)
- [Grid Sage Games: Designing for Mastery in Roguelikes](https://www.gridsagegames.com/blog/2025/08/designing-for-mastery-in-roguelikes-w-roguelike-radio/)
- [Dwarf Fortress - Wikipedia](https://en.wikipedia.org/wiki/Dwarf_Fortress)
- [GameRant: Dwarf Fortress Arrives on Steam After 20 Years](https://gamerant.com/dwarf-fortress-steam-release/)
- [Minecraft Wiki: Java Edition 1.0.0](https://minecraft.wiki/w/Java_Edition_1.0.0)
- [Cannibal Halfling Gaming: Stardew Valley's Closed World](https://cannibalhalflinggaming.com/2024/04/11/stardew-valleys-closed-world/)
- [Cyberpunk 2077 vs. No Man's Sky Recovery](https://www.portforwardinghub.com/games/cyberpunk-2077-vs-no-mans-sky/)
- [No Man's Sky vs. Cyberpunk 2077 - Unwinnable](https://unwinnable.com/2021/02/02/no-mans-sky-vs-cyberpunk-2077/)
- [GameSpot: Star Wars Battlefront 2 Loot Box Controversy](https://www.gamespot.com/articles/star-wars-battlefront-2s-loot-box-controversy-expl/1100-6455155/)
- [Alts.co: Fundamentals of Game Economy Design](https://alts.co/the-fundamentals-of-game-economy-design-from-basics-to-advanced-strategies/)
