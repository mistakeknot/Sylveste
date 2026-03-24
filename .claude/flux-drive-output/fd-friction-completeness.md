# fd-friction-completeness: Friction Point Completeness Review

**Reviewed:** `docs/cujs/first-install.md`, `docs/cujs/running-a-sprint.md`, `docs/cujs/code-review.md`
**Role:** Developer relations engineer running onboarding workshops. Focus on omissions, severity calibration, solution status, and cross-CUJ gaps.

---

## 1. first-install: Prerequisites vs. Friction Points

The Journey section establishes these prerequisites (explicit or implicit):

| Prerequisite | Friction point listed? | Assessment |
|---|---|---|
| Claude Code installed | Yes (implied baseline in "Prerequisite sprawl") | Adequate |
| Go (for beads/intercore) | Yes ("Prerequisite sprawl") | Adequate |
| Node (optional, some plugins) | Yes ("Prerequisite sprawl") | Adequate |
| Codex CLI (optional) | Yes ("Prerequisite sprawl") | Adequate |
| OAuth authentication via Claude Code | Partially ("BYOK users face extra friction") | **Gap: the happy-path OAuth flow is assumed to Just Work. No friction point covers OAuth token expiry, org policy blocking marketplace installs, or Claude Code version incompatibility.** |
| Plugin marketplace access | Partially ("Plugin marketplace discovery") | The friction point covers *choosing* plugins but not *accessing* them. Marketplace availability, version mismatches, or network/proxy issues are absent. |
| Terminal + shell environment | **Missing** | The Journey says "They open a terminal in their own project directory." No friction point covers shell compatibility (fish, PowerShell, nushell), PATH configuration, or Windows/WSL. A developer on Windows who has Claude Code via VS Code extension but not a Unix-like shell hits a wall with no warning. |
| Git initialized in their project | **Missing** | `/clavain:project-onboard` creates .beads/ and docs/ structure, and the sprint ends with "a commit on main." If the project doesn't have a git repo, or uses a non-main default branch, the onboarding will fail. No friction point covers this. |
| Sufficient disk space / permissions | **Missing (low severity)** | Dolt databases, plugin caches, and artifact directories add up. Not critical for a friction list, but worth noting for completeness. |

**Finding F1 (missing friction point):** Shell/OS compatibility is absent. The Journey reads as Unix-native; no friction point acknowledges Windows, non-bash shells, or container environments. An onboarding workshop would surface this in the first 15 minutes.

**Finding F2 (missing friction point):** Git initialization prerequisite. The sprint lifecycle assumes git; the friction list doesn't mention what happens when it's missing or misconfigured (wrong default branch, dirty working tree, shallow clone from CI).

## 2. Solution Status in Friction Points

Each friction point should tell the developer: is this a known rough edge with a workaround, a planned fix, or just a statement of the problem? Here is the current status:

| CUJ | Friction Point | States problem? | Workaround? | Planned fix? |
|---|---|---|---|---|
| first-install | Prerequisite sprawl | Yes | No | No |
| first-install | Plugin marketplace discovery | Yes | No | Vaguely ("doesn't yet recommend") |
| first-install | Comprehension gap | Yes | No | No |
| first-install | Beads as unfamiliar concept | Yes | Partial ("creates automatically") | No |
| first-install | Sprint length uncertainty | Yes | No | No |
| first-install | Error recovery on first run | Yes | No | No |
| first-install | BYOK extra friction | Yes | No | No |
| running-a-sprint | Discovery ranking opacity | Yes | No | No |
| running-a-sprint | Complexity misclassification | Yes | No | No |
| running-a-sprint | Brainstorm-to-plan handoff | Yes | No | No |
| running-a-sprint | Gate failures mid-sprint | Yes | No | No |
| running-a-sprint | Context window pressure | Yes | Partial ("write-behind protocol") | No |
| running-a-sprint | Multi-session context loss | Yes | Partial ("re-reads artifacts") | No |
| running-a-sprint | Reflect phase feels optional | Yes | No | No |
| code-review | Triage accuracy on novel types | Yes | No | No |
| code-review | Synthesis quality | Yes | No | No |
| code-review | Dismissal friction | Yes | No | Vaguely ("tension is unresolved") |
| code-review | Re-review cost | Yes | No | Stated as not implemented |
| code-review | Review fatigue on large changes | Yes | No | No |
| code-review | Interspect feedback latency | Yes | No | No |

**Finding F3 (systemic gap):** 18 of 20 friction points state the problem without a workaround or mitigation timeline. This is useful as an internal severity catalog but useless for a developer hitting the friction. A developer reading "Error recovery on first run" learns the system has bad error messages but gets no guidance on what to do about it. Each friction point should have at minimum one of: (a) a current workaround, (b) a link to a tracking issue/bead, or (c) explicit "no mitigation yet, planned for [phase/milestone]."

## 3. Multi-Session Context Loss Severity

The running-a-sprint friction point reads:

> "The checkpoint preserves structural state (phase, step, artifacts) but not conversational context. Nuance from the previous session -- why a particular design choice was made, what the developer said about scope -- is lost."

**Finding F4 (severity assessment):** The severity framing is accurate but incomplete. The friction point correctly identifies the structural/conversational split. However, it undersells the impact in two ways:

1. **Scope drift on resume.** The re-reading agency doesn't just "miss intent" -- it can actively re-interpret ambiguous plan steps differently than the original session intended. This isn't context loss; it's context *replacement*. The resumed sprint may silently diverge from the developer's expectations without surfacing a conflict.

2. **Developer trust calibration.** The friction point doesn't mention that the developer has no way to verify what the resumed session "remembers" vs. what it inferred. Did it pick up the scope constraint from the strategy doc, or did it re-derive a different one? The developer must re-read their own artifacts to verify the agency's understanding, which defeats the "picking up where I left off" promise.

The severity is correct as-listed (it's a real friction, not inflated), but the description should be more specific about the *consequence* (scope drift, silent re-interpretation) rather than just the *mechanism* (conversational context is lost).

## 4. Interspect Feedback Latency Specificity

The code-review friction point reads:

> "Routing adjustments based on dismissal patterns take multiple sprints to manifest. A developer who dismisses the same agent's findings five times in one session won't see the adjustment until later sessions."

**Finding F5 (insufficient calibration detail):** "Multiple sprints" and "later sessions" are not specific enough for a developer to calibrate trust. A developer who reads this needs to know:

- **How many dismissals trigger adjustment?** Is it 5? 10? 50? "Multiple sprints" could mean 2 or 20.
- **What does "adjustment" look like?** Does the agent get excluded entirely, or just deprioritized? Does the developer see evidence of the adjustment (e.g., "Agent X excluded based on dismissal history"), or does the agent just quietly stop appearing?
- **Is adjustment per-project or global?** If I dismiss architecture findings on my small CLI tool, does that affect architecture agent dispatch on my large web service?
- **Is there a manual override?** If the feedback loop is slow, can I manually exclude an agent now?

Even approximate answers ("roughly 5-10 dismissals of the same finding type over 2-3 sprints") would let a developer decide whether to invest in detailed dismissal feedback or just ignore noise until the system catches up. Without this, the developer can't distinguish "the system is learning, be patient" from "the system isn't learning from my feedback at all."

## 5. Implicit Friction Missing from Lists

Several friction points are present in the Journey narratives but absent from the friction lists.

### first-install.md

**Finding F6 (missing):** "The developer watches, intervenes when asked" -- the narrative mentions this as if it's natural, but a developer's first experience of watching an autonomous agent write code in their repo is high-anxiety. The implicit friction: **trust calibration on first run.** The developer doesn't know when to intervene, how to intervene safely (can I edit a file the agent is working on?), or what "intervene when asked" looks like in practice. This is different from "error recovery" (which covers what happens after something breaks) -- this covers the psychological friction of watching code get written and not knowing if you should stop it.

**Finding F7 (missing):** "They install the Clavain plugin from the marketplace: `claude install clavain`. They add companion plugins they want." The narrative implies the developer knows to install companions *before* running `/route`. But a developer who skips straight from `claude install clavain` to `/route` will get a degraded experience (no multi-agent review, no file coordination) without knowing they missed something. The friction is: **progressive disclosure of plugin value.** If the sprint runs without interflux, does the developer even know what they missed?

### running-a-sprint.md

**Finding F8 (missing):** "The developer is above the loop, not in it. They can observe phase transitions and agent dispatches in the terminal." The narrative describes observability but the friction list doesn't cover **terminal output legibility.** Phase transitions, agent dispatches, model selections, gate results -- all streaming through the terminal. How much of this is signal vs. noise for a developer? Is there a summary view vs. verbose mode? The "Sprint length uncertainty" friction point in first-install touches this ("No progress indicator exists beyond phase transitions"), but running-a-sprint doesn't acknowledge the observability gap at all.

**Finding F9 (missing):** "The agency uses the cheapest model that clears the quality bar for each subtask." The narrative describes model routing as seamless, but the friction list doesn't address **model routing transparency.** If Haiku is dispatched for a subtask that actually needed Opus, the developer sees lower quality output but may not know why. Is there a way to see which model was used for which step? Can the developer override a routing decision? The "Complexity misclassification" friction point is adjacent but covers task-level classification, not per-subtask model selection.

### code-review.md

**Finding F10 (missing):** "The developer doesn't choose agents -- the system does." This is presented as a feature, but it's also friction for developers who want control. The narrative mentions `/interflux:flux-drive` as a manual alternative, but the friction list doesn't cover the **auto-selection trust gap**: a developer who doesn't trust the system's agent selection has no lightweight way to understand *why* these agents were chosen, or to see which agents were considered and excluded.

**Finding F11 (missing):** The narrative describes agents writing findings to `.claude/flux-drive-output/`. These are files in the developer's working directory. The friction list doesn't mention **workspace pollution**: review artifacts accumulate in the working tree, may show up in `git status`, and the developer needs to know whether to gitignore them, commit them, or clean them up. For a first-time user coming from first-install, this is confusing.

## 6. Cross-CUJ Friction Gaps

**Finding F12 (cross-CUJ gap):** first-install friction persisting into running-a-sprint. Several first-install friction points don't resolve after the first session but aren't acknowledged in running-a-sprint:

- **"Beads as unfamiliar concept"** (first-install) -- a developer who was confused by beads on day 1 is still confused on day 5. The running-a-sprint CUJ assumes fluent bead interaction (picking bead IDs from `/route`, understanding priority ranking, reading `bd show` output). No friction point in running-a-sprint acknowledges the ongoing learning curve.

- **"Error recovery on first run"** (first-install) -- reframed as "Gate failures mid-sprint" in running-a-sprint. This is good cross-referencing, but the running-a-sprint version assumes the developer has *some* mental model of gates. A developer who hit their first gate failure during first-install and didn't understand it will hit it again in running-a-sprint with the same confusion. The running-a-sprint friction point should note that gate failure comprehension builds on exposure, and early-session developers may still lack the model.

**Finding F13 (cross-CUJ gap):** first-install friction persisting into code-review. The first-install CUJ establishes the developer's first encounter with review ("the review catch a bug they would have missed"). But the code-review CUJ's friction list assumes the developer already trusts and understands the review fleet. Cross-CUJ friction to acknowledge:

- **Agent identity opacity.** In first-install, the developer sees review findings for the first time. They don't know what "the architecture agent" or "the safety agent" means. The code-review friction list doesn't cover initial agent comprehension -- it jumps straight to triage accuracy and synthesis quality, which are second-order concerns.

**Finding F14 (cross-CUJ gap):** running-a-sprint and code-review don't cross-reference shared friction. Both CUJs have friction around feedback latency and learning loops (Interspect calibration in code-review, complexity calibration in running-a-sprint), but neither acknowledges that these are the *same* feedback system with the same latency characteristics. A developer frustrated by slow routing adjustment in reviews may not realize it's the same system that's slowly improving sprint complexity estimates. Unified framing would help.

---

## Summary of Findings

| ID | Severity | Category | Description |
|---|---|---|---|
| F1 | high | missing friction point | Shell/OS compatibility absent from first-install |
| F2 | medium | missing friction point | Git initialization prerequisite absent from first-install |
| F3 | high | systemic gap | 18/20 friction points lack workarounds, mitigations, or tracking references |
| F4 | medium | severity calibration | Multi-session context loss undersells scope drift and silent re-interpretation risk |
| F5 | high | specificity | Interspect feedback latency too vague for developer trust calibration |
| F6 | high | implicit friction | Trust calibration / intervention anxiety on first autonomous run not listed |
| F7 | medium | implicit friction | Progressive disclosure of plugin value -- degraded experience without companions is silent |
| F8 | medium | implicit friction | Terminal output legibility during sprint execution not listed in running-a-sprint |
| F9 | low | implicit friction | Model routing transparency per-subtask not listed |
| F10 | low | implicit friction | Auto-selection trust gap in code-review not listed |
| F11 | medium | implicit friction | Workspace pollution from review artifacts not listed |
| F12 | high | cross-CUJ gap | Beads learning curve and gate failure comprehension don't carry from first-install to running-a-sprint |
| F13 | medium | cross-CUJ gap | Agent identity opacity not covered for first-time review users |
| F14 | low | cross-CUJ gap | Interspect feedback latency not cross-referenced between running-a-sprint and code-review |

**High severity (act now):** F1, F3, F5, F6, F12
**Medium severity (address in next revision):** F2, F4, F7, F8, F11, F13
**Low severity (note for later):** F9, F10, F14
