---
artifact_type: cuj
journey: first-install
actor: stranger (new platform user, no prior Demarch exposure)
criticality: p1
bead: Demarch-9ha
---

# First Install and First Sprint

## Why This Journey Matters

This is the only journey that every Demarch user takes exactly once, and it determines whether they take a second. A developer who has heard about Demarch — from a conference talk, a GitHub trending page, a colleague — sits down to try it. They need to go from "what is this?" to "I just shipped a real change using an autonomous agency" in a single session. If the gap between promise and experience is too wide, they leave and don't come back.

The stakes are high because Demarch's value proposition is unusual: it's not a coding assistant, it's an autonomous development platform. Most developers have never used anything like it. The first session must demonstrate the full lifecycle — brainstorm through shipped code — without requiring the user to understand the architecture, memorize commands, or configure infrastructure. The adaptive entry point (`/route`) exists specifically to make this possible, but only if the path from curiosity to first shipped change is frictionless.

This CUJ covers the **platform user** journey: a developer who installs Clavain and companions to use on their own project. The contributor journey (cloning the Demarch monorepo, understanding the architecture, submitting a PR) is a separate CUJ.

## The Journey

A developer finds Demarch — a README on GitHub, a link from a colleague, a mention in a blog post about autonomous development tools. They read the project description and the pitch: "an open-source autonomous software development agency platform." This is not self-explanatory. The developer needs to understand three things before they'll invest time: what does this do that my current tools don't? What does it cost me to try? How long before I see if it works?

The README answers these. It explains the lifecycle (not just coding — brainstorm, strategy, plan, review, ship, reflect), shows the stack (kernel, OS, drivers, all open source), and points to a quickstart. The developer decides it's worth thirty minutes.

They already have Claude Code installed (which provides OAuth authentication — no API keys to configure). They install the Clavain plugin from the marketplace: `claude install clavain`. They add companion plugins they want — interflux for multi-agent review, interlock for file coordination. Each plugin installs independently; they don't need the full stack to start.

They open a terminal in their own project directory. They run `/clavain:project-onboard`, which introspects the repo, creates CLAUDE.md and AGENTS.md scaffolds, initializes beads tracking, and seeds the docs/ structure. The onboarding takes a few minutes and produces a working development environment without requiring manual configuration.

Now they type `/route` with no arguments. The discovery scanner finds no open beads (it's a fresh project), so it offers "Start fresh brainstorm." They pick it, describe a feature they want to build, and the sprint lifecycle begins. Clavain asks clarifying questions, explores the problem space, generates a strategy, writes a plan, executes it — writing code, running tests, committing incrementally. The developer watches, intervenes when asked, and sees a real change land on main. (For the full sprint experience, see [Running a Sprint](running-a-sprint.md).)

When the sprint completes, the developer has a moment to make sense of what just happened. There's a commit on main with their change. There's a bead — Demarch's unit of work tracking — marked closed. There are artifacts in their docs/ directory: a brainstorm, a strategy, a plan. The sprint produced not just code, but a decision trail. The developer can read back through the brainstorm and see the tradeoffs that were considered, the alternatives that were rejected, the reasoning that led to this implementation.

The critical moment is not the end — it's the middle. When the developer sees the brainstorm produce an insight they hadn't considered, or the review catch a bug they would have missed, or the plan break their vague idea into concrete steps — that's when the platform proves its value. The full lifecycle, not just the code generation, is the differentiator.

## Success Signals

| Signal | Type | Assertion |
|--------|------|-----------|
| README communicates the value proposition | qualitative | A developer who reads the README can explain what Demarch does differently from a coding assistant |
| Install completes without errors | measurable | `claude install clavain` exits 0, all declared dependencies resolve |
| Install and onboard complete within 10 minutes | measurable | Time from `claude install clavain` to `/clavain:project-onboard` finishing is <10 minutes |
| Project onboarding produces valid structure | measurable | `/clavain:project-onboard` creates CLAUDE.md, AGENTS.md, .beads/, docs/ |
| First `/route` presents actionable options | observable | Discovery scan completes, user sees "Start fresh brainstorm" option |
| Sprint reaches Ship phase without manual intervention | measurable | Sprint state machine advances through brainstorm → strategy → plan → work → ship |
| At least one review finding is acted upon | observable | Quality gates or flux-drive produces a finding that changes the implementation |
| Change lands on main with passing tests | measurable | `git log -1` shows a new commit, test suite exits 0 |
| Bead is closed at sprint end | measurable | `bd show <bead-id>` reports status CLOSED |
| First sprint time is reasonable | qualitative | Sprint duration feels proportionate to the feature's complexity; developer doesn't feel they're waiting |
| Developer understands what happened | qualitative | Developer can explain the sprint phases, the artifacts produced, and what the bead represents |

## Known Friction Points

- **Prerequisite sprawl.** Claude Code is the baseline requirement, but Go (for beads/intercore), and optional tools (Codex CLI, Node for some plugins) add up. A developer who doesn't already have Go installed may bounce before reaching the interesting part.
- **Plugin marketplace discovery.** New users may not know which companion plugins are useful vs. optional. The onboarding flow doesn't yet recommend a "starter set."
- **Comprehension gap.** "Autonomous software development agency platform" is a mouthful. The README needs to bridge from familiar concepts (CI/CD, code review, project management) to Demarch's model (sprints, phases, gates, beads) without jargon overload.
- **Beads as unfamiliar concept.** Developers expect issues/tickets. Beads (Dolt-backed, prefix-scoped, with dependency tracking) have a learning curve. The first sprint creates beads automatically, but the terminology may confuse.
- **Sprint length uncertainty.** A first sprint on a small feature might take 10 minutes or 45 minutes depending on model latency, review depth, and feature complexity. No progress indicator exists beyond phase transitions in the terminal.
- **Error recovery on first run.** If a gate fails or a model call errors on the first sprint, the developer has no mental model for debugging. Error messages assume familiarity with the phase/gate architecture.
- **BYOK users face extra friction.** Developers who bring their own API key instead of using Claude Code's built-in OAuth need to configure credentials and may encounter unexpected costs on their first sprint.
