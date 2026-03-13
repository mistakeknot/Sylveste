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

The README answers these. It explains the lifecycle (not just coding — brainstorm, strategy, plan, execute, ship, reflect), shows the stack (kernel, OS, drivers, all open source), and points to a quickstart. The developer decides it's worth thirty minutes.

They already have Claude Code installed (which provides OAuth authentication — no API keys to configure). They install the Clavain plugin following the quickstart instructions — adding the marketplace source and installing the plugin. They add companion plugins they want — interflux for multi-agent review, interlock for file coordination. Each plugin installs independently; they don't need the full stack to start.

They open a terminal in their own project directory. They run `/clavain:project-onboard`, which introspects the repo, creates CLAUDE.md and AGENTS.md scaffolds, initializes beads tracking, and seeds the docs/ structure. The onboarding takes a few minutes and produces a working development environment without requiring manual configuration.

Now they type `/route` with no arguments. The discovery scanner finds no open beads (it's a fresh project), so it offers "Start fresh brainstorm." They pick it, describe a feature they want to build, and the sprint lifecycle begins. Clavain asks clarifying questions, explores the problem space, generates a strategy, writes a plan, executes it — writing code, running tests, committing incrementally. The developer watches, intervenes when asked, and sees a real change land on main. (For the full sprint experience, see [Running a Sprint](running-a-sprint.md).)

When the sprint completes, the developer has a moment to make sense of what just happened. There's a commit on main with their change. There's a bead — Demarch's unit of work tracking — marked closed. There are artifacts in their docs/ directory: a brainstorm, a strategy, a plan. The sprint produced not just code, but a decision trail. The developer can read back through the brainstorm and see the tradeoffs that were considered, the alternatives that were rejected, the reasoning that led to this implementation.

The critical moment is not the end — it's the middle. When the developer sees the brainstorm produce an insight they hadn't considered, or the review catch a bug they would have missed, or the plan break their vague idea into concrete steps — that's when the platform proves its value. The full lifecycle, not just the code generation, is the differentiator.

## Success Signals

| Signal | Type | Status | Assertion |
|--------|------|--------|-----------|
| README communicates the value proposition | qualitative | active | A developer who reads the README can explain what Demarch does differently from a coding assistant |
| Plugin install completes without errors | measurable | active | Plugin install exits 0; `claude mcp list` shows clavain server registered |
| Install and onboard complete within 10 minutes | measurable | active | Wall-clock delta from first install command to `/clavain:project-onboard` exit is <600s |
| Project onboarding produces valid structure | measurable | active | `ls CLAUDE.md AGENTS.md .beads/ docs/` all exist after `/clavain:project-onboard` |
| Companion plugin failure doesn't block onboarding | measurable | active | If a companion install fails, onboarding still completes; error message names the failed plugin |
| First `/route` presents actionable options | observable | active | Discovery scan writes options to stdout; user sees "Start fresh brainstorm" in terminal output |
| Sprint reaches Ship phase without manual intervention | measurable | active | Sprint state machine advances through brainstorm → strategy → plan → execute → ship |
| At least one review finding is acted upon | observable | active | `.claude/flux-drive-output/` contains a finding file; a subsequent commit addresses it |
| Change lands on main with passing tests | measurable | active | `git log -1` shows a new commit; project test command exits 0 |
| Bead is closed at sprint end | measurable | active | `bd show <bead-id>` reports `status: closed` (lowercase) |
| First sprint time is reasonable | qualitative | active | Sprint duration feels proportionate to the feature's complexity; developer doesn't feel they're waiting |
| Developer understands what happened | qualitative | active | Developer can explain the sprint phases, the artifacts produced, and what the bead represents |
| Install failure produces actionable error | measurable | active | A failed install prints the specific component that failed and a recovery command |

## Known Friction Points

- **Prerequisite sprawl.** Claude Code is the baseline requirement, but Go (for beads/intercore) and optional tools (Codex CLI, Node for some plugins) add up. A developer who doesn't already have Go installed may bounce before reaching the interesting part. *Mitigation: the quickstart lists prerequisites upfront with install commands per platform. No mitigation yet for reducing the prerequisite count itself.*
- **Shell and OS compatibility.** The install and onboarding flows assume bash on Linux/macOS. Windows, fish, and zsh edge cases are not tested. *No mitigation yet.*
- **Plugin marketplace discovery.** New users may not know which companion plugins are useful vs. optional. *Mitigation: the quickstart recommends a starter set (clavain + interflux). The onboarding flow doesn't yet auto-suggest companions.*
- **Comprehension gap.** "Autonomous software development agency platform" is a mouthful. The README needs to bridge from familiar concepts (CI/CD, code review, project management) to Demarch's model (sprints, phases, gates, beads) without jargon overload. *Mitigation: the README includes a "what this is not" section. Further simplification is planned.*
- **Beads as unfamiliar concept.** Developers expect issues/tickets. Beads (Dolt-backed, prefix-scoped, with dependency tracking) have a learning curve. The first sprint creates beads automatically, but the terminology may confuse. *Mitigation: `/clavain:project-onboard` briefly explains beads during setup. No standalone tutorial yet.*
- **Sprint length uncertainty.** A first sprint on a small feature might take 10 minutes or 45 minutes depending on model latency, review depth, and feature complexity. No progress indicator exists beyond phase transitions in the terminal. *No mitigation yet — progress indicators are a planned feature.*
- **Error recovery on first run.** If a gate fails or a model call errors on the first sprint, the developer has no mental model for debugging. Error messages assume familiarity with the phase/gate architecture. *Workaround: `/clavain:doctor` diagnoses common issues. Error messages themselves need improvement.*
- **First-run intervention anxiety.** The developer doesn't know when the system will ask for input vs. proceed autonomously. The first time a gate blocks or a question appears, they may not understand the expected interaction model. *No mitigation yet.*
- **BYOK users face extra friction.** Developers who bring their own API key instead of using Claude Code's built-in OAuth need to configure credentials and may encounter unexpected costs on their first sprint. *Mitigation: BYOK setup is documented in the full setup guide.*
