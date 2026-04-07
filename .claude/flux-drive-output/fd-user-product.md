# User & Product Review: Three Core CUJ Documents

**Reviewer:** Flux-drive User & Product Agent
**Date:** 2026-03-13
**Scope:** `docs/cujs/first-install.md`, `docs/cujs/running-a-sprint.md`, `docs/cujs/code-review.md`
**Method:** Prose-first CUJ evaluation against the five review criteria: flow clarity, edge case coverage, scope appropriateness, friction point honesty, and narrative realism.

---

## Primary User and Job

The documents serve two user types: a stranger completing their first install (first-install.md) and a regular developer completing the core development loop (running-a-sprint.md, code-review.md). The job-to-be-done is consistent across all three: ship a tested, reviewed change to main using an autonomous agency platform rather than doing each step manually. The sprint and code-review documents explicitly treat this as P0 work. That framing is correct — if these flows break, nothing else matters.

---

## Document-by-Document Findings

### first-install.md

**Flow Clarity: Mostly Clear, One Critical Gap**

The narrative arc is well-constructed. It moves from discovery through install, onboard, first route invocation, and sprint completion, and it correctly identifies the sprint completion moment as the validation event. The prose does good work distinguishing between "code output" and "decision trail" as the real differentiator.

The critical gap is the install sequence itself. The document describes `claude install clavain` as a single step, then skips to `/clavain:project-onboard` without accounting for what happens between them. A new user has no way to verify that the install succeeded before running onboard — there is no described confirmation step, no output check, no "how do I know this worked?" moment. For a first-run experience on a novel platform, the absence of an install verification step is a flow hole. The document describes what should happen but not what the user sees.

The second issue is the companion plugin discovery step. The document says the developer "adds companion plugins they want — interflux for multi-agent review, interlock for file coordination." How do they know which to add? The friction section acknowledges that new users don't know which plugins are optional vs. useful, but the narrative above it presents companion selection as if it is self-evident. The narrative and the friction section contradict each other on this point.

**Edge Case Coverage: Thin**

The "Known Friction Points" section identifies six friction areas, but the narrative section treats the install as a happy path with no deviations. The journey does not describe:

- What happens if `claude install clavain` fails (network error, name conflict, version incompatibility)
- What happens if `/clavain:project-onboard` runs in a directory that already has CLAUDE.md (overwrite, merge, skip?)
- What `/route` shows when a fresh project has no beads and the brainstorm feature is incomplete or misconfigured
- Whether the sprint can be abandoned mid-run and what state it leaves the project in

These aren't exotic scenarios. The third one — what happens when the new user's first sprint stalls — is arguably the most common failure mode for first-time users and it has no coverage at all. The document hands off to running-a-sprint.md for the sprint detail, but running-a-sprint.md assumes an established user. Neither document covers the "first sprint stalls at plan phase" scenario from a new user's perspective.

**Scope: Appropriately Focused**

The document correctly scopes to the platform user (using Sylveste on their own project) and explicitly excludes the contributor journey. That boundary is right. The document could afford to be slightly narrower in the narrative — the paragraph about understanding what just happened after the sprint works well but could be tightened — but the overall scope is appropriate.

**Friction Point Honesty: Good, With One Understatement**

The friction section is one of the stronger parts of the document. It names real problems with enough specificity to be actionable. The one understatement is the "prerequisite sprawl" item. It correctly identifies Go as a dependency but understates the problem. A developer who has never used Go faces not just "install Go" but also understanding why a plugin system for a Claude Code extension requires Go, and what version to install, and whether their package manager provides a version that works. The severity label on this friction should be higher — it is a potential journey-ending blocker for a non-trivial fraction of developers, not just a mild inconvenience.

The "BYOK users face extra friction" point is honest and useful but slightly buried. For a P1 CUJ, API key configuration is a realistic path for a meaningful fraction of users (those who don't use Claude Code's default auth), and it should appear earlier in the list.

**Narrative Realism: Mostly Realistic, One False Confidence**

The document's closing claim that "the developer understands what happened" after the first sprint is optimistic. The sprint produces artifacts (brainstorm, strategy, plan, closed bead), but a first-time user encountering four new document types, a bead concept, and a phase-based workflow for the first time will require more than artifact presence to develop understanding. The success signal table captures this with "Developer can explain the sprint phases" as a qualitative signal, but the narrative itself presents it as an expected outcome rather than an aspirational one. This creates a gap between what the document promises and what the product currently delivers.

---

### running-a-sprint.md

**Flow Clarity: Strong**

This is the best-written of the three documents. The phase sequence is clear (brainstorm, strategy, plan, execute, ship, reflect), the decision points are named, and the execution model (developer above the loop, intervening on exceptions) is described with enough specificity to be useful. The "When a Sprint Gets Stuck" subsection is particularly good — it correctly frames the stuck sprint as a diagnostic problem, not a failure, and gives the developer three real recovery options.

One structural observation: the complexity classification (1-5) and its dispatch implications are described at a level of abstraction that makes them hard to evaluate. "Moderate tasks (3) get a lightweight brainstorm" — what is a lightweight brainstorm? "Complex tasks (4-5) get the full lifecycle with multi-agent review at the plan stage" — what triggers a complexity 4 vs. 5 classification? The document correctly defers model routing details, but the complexity classification system is user-facing (it determines what workflow they experience) and deserves slightly more concrete description so that users know what to expect when a task is classified.

The "multi-session resume" section is strong and specific. The claim that context is lost but structural state is preserved is an important distinction and it is stated clearly.

**Edge Case Coverage: Better Than the Others, Still Missing One Critical Path**

The stuck sprint section covers the main failure modes well. The multi-session section covers the resume scenario. The document describes the developer's intervention options at a realistic level of detail.

What is missing is the "sprint completes but quality gates fail at ship" path. The document mentions that gates run at the ship phase, but it does not describe what the developer sees when the ship-phase gate fails — whether they can revert the sprint's commits, whether they can revise and retry without restarting the sprint, whether the bead remains open or is suspended. This is a realistic scenario (tests were green mid-sprint but integration revealed a problem at ship) and the lack of a described recovery path is a real gap for a P0 CUJ.

A secondary missing path: what happens when the reflect phase writes calibration data but there is no interoperability yet with Interspect (i.e., the data sits unread)? The document correctly identifies "Reflect phase feels optional" as a friction point, but it does not describe what the developer sees when reflect completes — no visible outcome, no acknowledgment. For an action that is critical to the long-term flywheel, the lack of any in-session payoff is a significant motivation problem. The friction item identifies this correctly, but the narrative section does not acknowledge that reflect currently produces invisible output. There is a gap between the described post-reflect state ("the next time the developer runs /route, the system is slightly better") and the current reality where Interspect calibration is partially shipped.

**Scope: Correct, With One Redundancy**

The P0 designation is appropriate. This is the right scope for a canonical sprint description.

One minor scope issue: the document doubles as the canonical reference for the full sprint lifecycle and as a friction-point catalog. These are different purposes. The friction section is honest and valuable, but it is doing work that belongs in a separate operational document or a "known issues" section clearly labeled as current-state rather than aspirational. The current structure can mislead a reader into thinking the described friction is acceptable design rather than identified debt. Separating "this is how the sprint works" from "this is where the sprint currently falls short" would improve clarity.

**Friction Point Honesty: Excellent**

The friction section is specific, calibrated, and honest about severity. The "multi-session context loss" point in particular — that conversational intent expressed outside of documents is lost — is an important real limitation that many similar documents would omit or soften. The "complexity misclassification" point correctly identifies that the classifier is heuristic and names a plausible failure mode.

The one gap is the reflect section, discussed above — the friction point is correct but understates the severity by framing it as "feels optional." In practice, if reflect produces no visible in-session payoff and the downstream calibration benefit takes weeks to manifest, most users will skip it or rush through it. The friction is more severe than "feels optional" implies.

**Narrative Realism: High**

The execution section — "the developer is above the loop, not in it" — accurately describes the intended interaction model. The qualification that the goal is "zero interventions for routine work" with "clear, actionable prompts when intervention is needed" is honest about current capability. The multi-session description is realistic about the context window limitation. This document reads like it was written by someone who has used the sprint loop repeatedly, which is appropriate for a P0 CUJ.

---

### code-review.md

**Flow Clarity: Good Conceptually, Weak on Mechanics**

The review document correctly identifies the problem it solves (signal-to-noise ratio in AI code review) and describes the architecture well (specialized agents, synthesis layer, triage). The opening paragraph is the strongest problem statement in any of the three documents.

The mechanics of invocation are underspecified. The document says the most common entry point is `/clavain:quality-gates` and that developers can also use `/interflux:flux-drive`. But it does not describe what the user types, what they see while agents run in parallel, or what the synthesis output looks like when it arrives. The reader knows what the system does conceptually but not what using it feels like moment-to-moment. For a P1 CUJ, this is a meaningful gap — a new user reading this document would not know what to expect when they run `/clavain:quality-gates` for the first time.

The parenthetical notes in the document ("*Interspect-driven exclusion is partially shipped*", "*Planned: findings grouped by theme*", "*planned — dismissal-to-routing feedback loop is Phase 2*") are honest about current vs. future state, which is valuable. However, they are scattered through the narrative at the points where the future features are mentioned, which creates a choppy reading experience. A reader following the journey narrative repeatedly hits "this part isn't built yet." Consolidating these notes into a single "current-state gaps" section would make the document easier to read as a flow description while preserving the honesty.

**Edge Case Coverage: Weakest of the Three**

The document covers the main review flow and the triage selection but does not cover:

- What happens if an agent times out or errors during parallel dispatch (one agent fails, rest succeed — does synthesis proceed with partial results or does it block?)
- What happens if all agents are dispatched and all findings are at "nit" severity — does the developer still see a report, and how is a "no real issues" verdict communicated?
- What the developer does when the synthesis verdict is "needs discussion" rather than approve or request changes — is this a blocking state?
- Whether the developer can re-run only the agents whose findings were dismissed (the friction section mentions this as not implemented, but the main flow does not describe what "re-run" currently looks like)
- What happens if the user invokes review mid-sprint vs. at the ship phase gate — are these treated differently?

The distinction between plan-stage review and ship-stage review is mentioned once in the journey opening ("a plan is written and needs validation before execution, a feature is implemented and needs review before shipping") but not elaborated. These are meaningfully different use cases with different expected agent sets and different user intentions, and collapsing them into a single narrative makes both less clear.

**Scope: Slightly Too Ambitious for Current Reality**

The document describes a code review system with Interspect learning, dismissal-to-routing feedback, and automated agent selection based on historical effectiveness. The problem is that approximately half of this system is described as Phase 2 or planned. The document's scope encompasses both the current system and the intended system, and it is not always clear which is which beyond the inline parenthetical notes.

This creates a product promise problem. A developer reading this document to decide whether to use Sylveste's review system will form expectations based on the full narrative, including the Interspect learning loop. When they discover that the learning loop is Phase 2, they may feel misled even though the document technically disclosed it. The scope should either narrow to current-state functionality or explicitly lead with "this is the target architecture, here is what ships today."

The "over time, the review gets better" paragraph at the document's end describes the flywheel as if it is operating today. It is not yet operating today. That paragraph should be clearly marked as aspirational.

**Friction Point Honesty: Honest but Incomplete**

The friction section identifies six real problems. The dismissal friction point (fast vs. informative dismissal tension) is a genuine UX design problem that is correctly named. The synthesis quality dependency point (garbage in, garbage out) is honest and important.

What is missing from the friction section:

- No mention of what happens when an agent produces a finding that contradicts the user's design intent — the document describes the user acting on findings or dismissing them, but there is no path for "this finding is correct but I've decided not to fix it and here's why." This is a real user action that the current dismiss model may not capture well.
- No mention of the cost of a false-negative verdict. The success signal table includes "High-confidence 'approve' verdicts don't precede post-merge regressions" as an observable signal, but the friction section does not acknowledge that false approvals are a real risk, particularly early in the Interspect learning curve when confidence scores are not yet well-calibrated.
- Re-review cost is listed as a friction point but the description understates it. "Re-dispatches all agents, not just the ones whose findings were relevant" means the developer pays full cost again for a subset of changes. This compounds with the review fatigue friction point — repeated reviews on a large diff are both expensive and tiring. The interaction between these two friction points deserves acknowledgment.

**Narrative Realism: Mixed**

The document's description of agent specialization is realistic and well-grounded in the actual plugin architecture. The user workflow (read synthesis, act/dismiss/discuss) is plausible and probably accurate for the current system.

The unrealistic parts are the learning-loop passages. "Over time, the review gets better" and "the cost of review decreases" and "the signal density of the review fleet directly feeds the learning loop" all describe a system that requires Phase 2 work to function. A regular user reading this document should be able to distinguish between what they get today and what the platform is building toward. The current document does not make that boundary clear enough.

---

## Cross-Cutting Issues

**1. Shared Bead ID Across All Three Documents**

All three CUJs have `bead: Sylveste-9ha` in their frontmatter. This is almost certainly a copy-paste artifact from a template. Three distinct P0/P1 journeys should have distinct tracking beads. This is a documentation integrity issue — if CUJs are monitored by interwatch for staleness, they need accurate bead references.

**2. Success Signal Tables Are Stronger Than Narratives**

In all three documents, the success signal tables are more precise and more honest than the narrative sections. The tables distinguish measurable from observable from qualitative signals, include timing assertions, and include signals that are clearly aspirational (like cost-per-landable-change trending downward). The narratives, by contrast, often describe the ideal path without making visible which parts are current capability and which are design intent. Consider treating the success signal table as the canonical source of truth for current vs. aspirational state, and anchoring the narrative more explicitly to it.

**3. Missing Recovery-to-Next-Action Pattern**

All three documents describe what fails, but none describe the "next best action" from the failure state. When a gate fails, the user is told they have options (revise plan, abandon sprint, intervene manually). But none of these options comes with a described outcome. What does "revise the plan and resume from the current step" look like in practice? What does the user type? What state is the sprint left in? This pattern — describe failure, enumerate options, stop before describing the option mechanics — repeats across all three documents and leaves users without actionable guidance at exactly the moment they need it most.

**4. Onboarding-to-Regular-Use Transition is Implicit**

The first-install CUJ ends with the developer having completed a first sprint. The running-a-sprint CUJ begins with a regular user who already knows how to use `/route`. There is no described transition between these two states — no "after your first sprint, here is how the regular workflow differs" bridge. For a new user trying to understand the full platform journey, this creates a discontinuity. The two documents are correctly separated by scope (new user vs. regular user) but the seam between them is not described anywhere.

---

## Summary Assessment

All three documents are well above average for CUJ writing. They are prose-first, specific about success signals, and honest about friction. The sprint document is particularly strong. The gaps are concentrated in three areas: edge case coverage for failure-state recovery, the gap between described future capabilities and current-state reality, and the bead ID integrity issue.

The issues that would block user success if uncorrected:

1. **first-install.md** — The "first sprint stalls" failure mode is not covered. This is the highest-probability failure event for a first-time user and the document provides no guidance for it.
2. **running-a-sprint.md** — The "ship-phase gate failure" recovery path is not described. Users who hit this will have no documented path forward.
3. **code-review.md** — The current-state vs. Phase 2 boundary is not clearly drawn. Users will form expectations based on the full narrative and be surprised by what is not yet built.

The issues that reduce product value but do not block success:

4. Reflect phase payoff is invisible in-session. Users need a visible, immediate signal that reflect completed and produced output, even if the downstream calibration benefit takes longer to manifest.
5. The companion plugin selection step in first-install.md contradicts its own friction section. Either the narrative should describe a recommended starter set, or the friction section should be elevated to acknowledge this as a blocking gap.
6. All three documents share a single bead reference (`Sylveste-9ha`). This should be corrected before the CUJs are used as interwatch monitoring targets.

The smallest change set with the highest user outcome impact:

- Add a "sprint stalls on first run" failure scenario to first-install.md with a described recovery path (even if the recovery is "ask in the community channel" — the absence of any described path is the problem)
- Add a "ship-phase gate failure" recovery section to running-a-sprint.md, even as a two-paragraph subsection modeled on the existing "When a Sprint Gets Stuck" section
- Add a "current-state vs. planned" table to code-review.md that explicitly marks which features ship today and which are Phase 2, so that the narrative can be read with appropriate expectations

---

## Relevant File Paths

- `docs/cujs/first-install.md`
- `docs/cujs/running-a-sprint.md`
- `docs/cujs/code-review.md`
- `docs/cujs/README.md`
- `PHILOSOPHY.md`
- `docs/research/user-product-opportunity-review.md`
