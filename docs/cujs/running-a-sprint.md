---
artifact_type: cuj
journey: running-a-sprint
actor: regular user (developer using Sylveste daily)
criticality: p0
bead: Sylveste-9ha
---

# Running a Sprint

## Why This Journey Matters

This is the core loop. Everything else in Sylveste exists to make this journey work: the kernel records it, the OS orchestrates it, the profiler learns from it, the drivers augment it. A sprint is the atomic unit of autonomous development — the smallest cycle that takes a problem and produces shipped, reviewed, tested code. If this journey is slow, brittle, or opaque, the platform fails regardless of how elegant its architecture is.

The sprint is also where the three frontier axes are tested simultaneously. Autonomy: how far does the sprint get without human intervention? Quality: does the output survive review and testing? Efficiency: what did it cost in tokens and time? The north-star metric (cost per landable change) is measured here. Every Interspect optimization targets this loop. Every routing decision, every gate calibration, every agent selection is evaluated by its impact on sprint outcomes.

This CUJ is the canonical description of the sprint lifecycle. Other CUJs ([First Install](first-install.md), [Code Review](code-review.md)) cross-reference this document rather than duplicating the phase narrative.

## The Journey

The developer starts their session and types `/route`. The discovery scanner checks beads: open issues ranked by priority, stale work that needs attention, in-progress items from previous sessions. The scanner presents the top candidates with recommended actions — "Continue Sylveste-abc (plan exists)", "Plan Sylveste-def (brainstorm done)", "Start fresh brainstorm." The developer picks one, or provides a bead ID directly (`/route Sylveste-xyz`).

Route classifies the task complexity (1-5) and dispatches to the appropriate workflow. Simple tasks (complexity 1-2) skip brainstorm and strategy, going straight to planning and execution. Moderate tasks (3) get a lightweight brainstorm. Complex tasks (4-5) get the full lifecycle with multi-agent review at the plan stage.

**Brainstorm.** The agency explores the problem space. It reads relevant code, checks for prior art in solution docs, scans for related beads. It produces a brainstorm artifact — not a plan, but an exploration of the design space with tradeoffs, alternatives, and open questions. The developer reviews and refines. For simple tasks, this phase is compressed to a 3-bullet inline assessment.

**Strategy.** The brainstorm becomes a strategy document: a PRD-like spec with clear scope, success criteria, and explicit non-goals. The strategy is the contract between the human (who approved the scope) and the agency (which will execute it). Features cut here stay cut.

**Plan.** The strategy becomes a concrete implementation plan: ordered steps, file references, test expectations, dependency notes. The plan is the work order. For complex or security-sensitive changes, the review fleet examines the plan before execution begins (see [Code Review](code-review.md)). The developer reads the synthesis and decides whether to proceed, revise, or abandon.

**Execute.** The agency works through the plan step by step. It reads referenced code, matches existing patterns, writes implementation, runs tests after each change, and commits incrementally. Each commit is a logical unit — not a WIP checkpoint, but a complete, describable change. Model selection uses phase-level and category-level routing (e.g., Haiku for simple edits, Sonnet for moderate reasoning, Opus for complex logic, Codex for parallel implementation). *(Per-subtask complexity-aware routing is active in shadow mode — the system classifies tasks and logs recommended models, but base routing is applied. Enforced complexity routing is planned.)*

During execution, the developer is above the loop, not in it. They can observe phase transitions and agent dispatches in the terminal. They intervene only on exceptions: a gate that fails, a test that needs human judgment, a scope question that wasn't anticipated in the plan. The goal is zero interventions for routine work and clear, actionable prompts when intervention is needed.

**Ship.** The change is complete. Quality gates run: tests pass, linting passes, and for risky changes, the review fleet examines the final diff (see [Code Review](code-review.md)). The developer confirms the push. The commit lands on main.

**Reflect.** The agency captures what happened: complexity estimates vs. actuals, model routing decisions and their outcomes, review findings and whether they were acted on, time spent per phase. This data is recorded as kernel events for Interspect's calibration pipeline. Solution docs are generated for novel patterns. The bead is closed. *(Automated calibration — where Interspect adjusts routing tables without human intervention — is Phase 2. Today, calibration requires manual `/interspect:propose` + `/interspect:approve` steps.)*

The next time the developer runs `/route`, the system is slightly better at estimating complexity and knowing which review agents to deploy — provided the operator has run calibration. The flywheel turns, but today it requires a manual push.

### When a Sprint Gets Stuck

Not every sprint reaches Ship. A plan may turn out to be wrong once implementation begins — an assumption doesn't hold, a dependency has an unexpected API, or the scope was larger than estimated. Tests may fail in ways that reveal a design flaw rather than an implementation bug. The developer may realize mid-execution that the strategy needs revision.

When this happens, the agency surfaces the problem rather than pushing through. A failed gate blocks advancement and reports what went wrong. A test failure during execution pauses the loop and presents the error. The developer has several options: revise the plan and resume from the current step, abandon the sprint and start over with a new brainstorm informed by what was learned, or intervene manually to fix the immediate blocker and let the sprint continue.

The sprint state is durable. If the developer closes their terminal or the session crashes, Clavain's sprint state machine has recorded the current phase, artifacts, and plan progress. The next session picks up where it left off — the sprint doesn't need to restart from scratch. The checkpoint includes which plan steps were completed, which commits were made, and what phase the sprint was in.

### Multi-Session Sprints

Simple sprints complete in a single session. Complex work — a cross-cutting refactor, a new module with tests and documentation, a security-sensitive change with thorough review — may span multiple sessions.

When the developer starts a new session and runs `/route`, the discovery scanner detects the in-progress sprint from the previous session. It presents it as the top option: "Resume Sylveste-xyz (executing, step 4/7)." The developer selects it, and the sprint continues from the checkpoint. The context from the previous session is gone (context windows don't survive sessions), but the durable state is intact: the plan, the completed steps, the commits, the review findings. The agency re-reads the plan and the relevant code, orients on where it left off, and continues.

The resume experience should feel seamless — not "starting over with notes" but "picking up where I left off." The checkpoint tells the agency exactly what's been done and what remains. No re-brainstorming, no re-planning, no re-executing completed steps.

## Success Signals

| Signal | Type | Status | Assertion |
|--------|------|--------|-----------|
| `/route` presents relevant work within 5 seconds | measurable | active | `clavain-cli sprint-find-active` + discovery scan complete in <5s wall-clock |
| Complexity classification matches actual effort | measurable | recording | Estimated C-score (1-5) vs actual token spend: Spearman correlation >0.5 across 20+ sprints |
| Brainstorm surfaces at least one non-obvious insight | qualitative | active | Brainstorm artifact contains analysis the developer hadn't considered |
| Strategy has explicit non-goals | measurable | active | Strategy document contains a "Non-goals" section with at least one entry |
| Plan is executable without ambiguity | qualitative | active | Developer reads the plan and has no clarifying questions |
| Execution follows existing codebase patterns | observable | active | `git diff` shows new code matching naming conventions and idioms of surrounding files |
| Tests pass after each incremental commit | measurable | active | `git log --oneline` commits each have passing CI; no commit introduces a test failure |
| Sprint completes without unnecessary human intervention | measurable | active | AskUserQuestion calls during execute phase: 0 for C1-C2 tasks, <=2 for C3-C5 |
| Bead is closed with complete metadata | measurable | active | `bd show <id>` reports `status: closed`, `claimed_by`, `claimed_at`, `closed_at` populated |
| Reflect phase produces reusable learnings | observable | active | `docs/solutions/` or `.clavain/calibration/` gains a new file after reflect |
| Cost per landable change trends downward | measurable | planned | Running average of sprint cost (via `interstat`) decreases over 10-sprint window as Interspect calibrates |
| Multi-session resume preserves progress | measurable | active | Resumed sprint skips completed plan steps; `clavain-cli checkpoint-read` returns correct step index |
| Failed sprints surface the problem clearly | observable | active | Gate failure stderr includes phase name, gate name, and failing condition |
| Gate failure at Ship is recoverable | observable | active | Ship-phase gate failure presents options: fix and retry, revert last commit, or abandon sprint |

## Known Friction Points

- **Discovery ranking opacity.** The scanner ranks beads by priority, staleness, and dependencies, but the ranking logic isn't visible to the developer. A bead that should be top-ranked may be buried if its metadata is incomplete. *Workaround: `/route` with a bead ID bypasses ranking entirely.*
- **Complexity misclassification.** The classifier uses heuristics (description length, dependency count, file scope). A task that reads as simple but touches a complex subsystem may be underestimated, leading to an undersized workflow (no brainstorm, no review) that produces lower-quality output. *Workaround: provide a bead ID with `/route Sylveste-xyz` and the sprint skill will re-classify based on full context.*
- **Brainstorm-to-plan handoff.** The brainstorm explores; the plan commits. If the brainstorm raises open questions that aren't resolved before planning, the plan may contain ambiguities that surface during execution. *Mitigation: the strategy phase (between brainstorm and plan) is designed to resolve open questions. If it doesn't, the plan review gate should catch ambiguities.*
- **Gate failures mid-sprint.** A failed gate (test failure, lint error, missing artifact) blocks advancement. The error message tells you what failed but not always why or how to fix it. Recovery requires understanding the phase/gate model. *Workaround: `/clavain:doctor` diagnoses common gate issues. Error message quality is being improved.*
- **Ship-phase gate failure.** Tests pass during execution but fail at the Ship gate (integration failure, lint regression from an upstream change). The developer must decide: fix and retry, revert last commit, or abandon. *Mitigation: the sprint state machine supports retry from the current phase. No automatic revert.*
- **Context window pressure on long sprints.** A complex sprint that runs through all phases accumulates context. The convention of writing agent output to files and reading summaries into context mitigates this, but very long sprints may still hit quality degradation in later phases. *Workaround: multi-session sprints naturally reset context; for single-session sprints, the /compact mechanism helps.*
- **Multi-session context loss.** The checkpoint preserves structural state (phase, step, artifacts) but not conversational context. Nuance from the previous session — why a particular design choice was made, what the developer said about scope — is lost. The agency re-reads artifacts but may miss intent that was expressed in conversation, not in documents. This can cause scope drift on resumed sprints. *No mitigation yet — recording conversational intent as structured notes is planned.*
- **Reflect phase feels optional.** The developer wants to move to the next task. Reflect produces calibration data and solution docs, but the value is invisible until Interspect uses it weeks later — and today, calibration requires manual steps (`/interspect:propose` + `/interspect:approve`). Easy to skip, expensive to skip repeatedly. *Mitigation: the ship skill includes reflect as a mandatory step. The developer can skip it by closing the session, but the bead remains open.*
