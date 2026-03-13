---
artifact_type: cuj
journey: first-install
actor: stranger (new user, no prior Demarch exposure)
criticality: p1
bead: Demarch-85k.6
---

# First Install and First Sprint

## Why This Journey Matters

This is the only journey that every Demarch user takes exactly once, and it determines whether they take a second. A developer who has heard about Demarch — from a conference talk, a GitHub trending page, a colleague — sits down to try it. They need to go from zero to "I just shipped a real change using an autonomous agency" in a single session. If the gap between promise and experience is too wide, they leave and don't come back.

The stakes are high because Demarch's value proposition is unusual: it's not a coding assistant, it's an autonomous development platform. Most developers have never used anything like it. The first session must demonstrate the full lifecycle — brainstorm through shipped code — without requiring the user to understand the architecture, memorize commands, or configure infrastructure. The adaptive entry point (`/route`) exists specifically to make this possible, but only if the install-to-first-sprint path is frictionless.

## The Journey

A developer clones the Demarch monorepo and reads the README. The README points them to the Full Setup Guide, which walks through prerequisites: Go 1.22+, Claude Code, and optionally Codex CLI. They install the Clavain plugin from the marketplace (`claude install clavain`) and any companion plugins they want (interflux for review, interlock for coordination). Each plugin is independently installable — they don't need the full stack to start.

They open a terminal in their own project directory. They run `/clavain:project-onboard`, which introspects the repo, creates CLAUDE.md and AGENTS.md scaffolds, initializes beads tracking, and seeds the docs/ structure. The onboarding takes about two minutes and produces a working development environment without requiring manual configuration.

Now they type `/route` with no arguments. The discovery scanner finds no open beads (it's a fresh project), so it offers "Start fresh brainstorm." They pick it. The sprint lifecycle begins: Clavain asks what they want to build, runs a brainstorm phase that explores the problem space, generates a strategy document, writes a plan with concrete steps, and optionally runs flux-drive review on the plan. Then it executes the plan — writing code, running tests, committing incrementally. At the end, it ships the change and runs a reflect phase that captures what was learned.

The developer watches the agency work. They see phase transitions in the terminal. They see artifacts being created (brainstorm, strategy, plan). They see code being written, tests passing, commits landing. They see the review agents catch a real issue and the implementation agent fix it. When it's done, there's a commit on main with their change, and a bead marked closed.

The critical moment is not the end — it's the middle. When the developer sees the brainstorm produce an insight they hadn't considered, or the review catch a bug they would have missed, or the plan break their vague idea into concrete steps — that's when the platform proves its value. The full lifecycle, not just the code generation, is the differentiator.

## Success Signals

| Signal | Type | Assertion |
|--------|------|-----------|
| Install completes without errors | measurable | `claude install clavain` exits 0, all declared dependencies resolve |
| Project onboarding produces valid structure | measurable | `/clavain:project-onboard` creates CLAUDE.md, AGENTS.md, .beads/, docs/ |
| First `/route` presents actionable options | observable | Discovery scan completes, user sees "Start fresh brainstorm" option |
| Sprint reaches Ship phase without manual intervention | measurable | Sprint state machine advances through brainstorm → strategy → plan → work → ship |
| At least one review finding is acted upon | observable | Flux-drive or quality-gates produces a finding that changes the implementation |
| Change lands on main with passing tests | measurable | `git log -1` shows a new commit, test suite exits 0 |
| Bead is closed at sprint end | measurable | `bd show <bead-id>` reports status CLOSED |
| Total wall-clock time under 45 minutes | qualitative | First sprint completes in a reasonable time for a small feature |
| Developer understands what happened | qualitative | Developer can explain the sprint phases and what each produced |

## Known Friction Points

- **Prerequisite sprawl.** Go, Claude Code, and optional tools (Codex, Node for some plugins) add up. A developer who doesn't already have Go installed may bounce before reaching the interesting part.
- **Plugin marketplace discovery.** New users may not know which companion plugins are useful vs. optional. The onboarding flow doesn't yet recommend a "starter set."
- **Beads as unfamiliar concept.** Developers expect issues/tickets. Beads (Dolt-backed, prefix-scoped, with dependency tracking) have a learning curve. The first sprint creates beads automatically, but the terminology may confuse.
- **Sprint length uncertainty.** A first sprint on a small feature might take 10 minutes or 45 minutes depending on model latency, review depth, and feature complexity. No progress indicator exists beyond phase transitions in the terminal.
- **Error recovery on first run.** If a gate fails or a model call errors on the first sprint, the developer has no mental model for debugging. Error messages assume familiarity with the phase/gate architecture.
