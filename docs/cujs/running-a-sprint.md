---
artifact_type: cuj
journey: running-a-sprint
actor: regular user (developer using Demarch daily)
criticality: p0
bead: Demarch-85k.6
---

# Running a Sprint

## Why This Journey Matters

This is the core loop. Everything else in Demarch exists to make this journey work: the kernel records it, the OS orchestrates it, the profiler learns from it, the drivers augment it. A sprint is the atomic unit of autonomous development — the smallest cycle that takes a problem and produces shipped, reviewed, tested code. If this journey is slow, brittle, or opaque, the platform fails regardless of how elegant its architecture is.

The sprint is also where the three frontier axes are tested simultaneously. Autonomy: how far does the sprint get without human intervention? Quality: does the output survive review and testing? Efficiency: what did it cost in tokens and time? The north-star metric (cost per landable change) is measured here. Every Interspect optimization targets this loop. Every routing decision, every gate calibration, every agent selection is evaluated by its impact on sprint outcomes.

## The Journey

The developer starts their session and types `/route`. The discovery scanner checks beads: open issues ranked by priority, stale work that needs attention, in-progress items from previous sessions. The scanner presents the top candidates with recommended actions — "Continue Demarch-abc (plan exists)", "Plan Demarch-def (brainstorm done)", "Start fresh brainstorm." The developer picks one, or provides a bead ID directly (`/route Demarch-xyz`).

Route classifies the task complexity (1-5) and dispatches to the appropriate workflow. Simple tasks (complexity 1-2) skip brainstorm and strategy, going straight to planning and execution. Moderate tasks (3) get a lightweight brainstorm. Complex tasks (4-5) get the full lifecycle with multi-agent review at the plan stage.

**Brainstorm.** The agency explores the problem space. It reads relevant code, checks for prior art in solution docs, scans for related beads. It produces a brainstorm artifact — not a plan, but an exploration of the design space with tradeoffs, alternatives, and open questions. The developer reviews and refines. For simple tasks, this phase is compressed to a 3-bullet inline assessment.

**Strategy.** The brainstorm becomes a strategy document: a PRD-like spec with clear scope, success criteria, and explicit non-goals. The strategy is the contract between the human (who approved the scope) and the agency (which will execute it). Features cut here stay cut.

**Plan.** The strategy becomes a concrete implementation plan: ordered steps, file references, test expectations, dependency notes. The plan is the work order. For complex or security-sensitive changes, flux-drive reviews the plan before execution begins — dispatching architecture, safety, correctness, and quality agents that examine the plan from different perspectives. The developer reads the synthesis and decides whether to proceed, revise, or abandon.

**Execute.** The agency works through the plan step by step. It reads referenced code, matches existing patterns, writes implementation, runs tests after each change, and commits incrementally. Each commit is a logical unit — not a WIP checkpoint, but a complete, describable change. The agency uses the cheapest model that clears the quality bar for each subtask: Haiku for simple edits, Sonnet for moderate reasoning, Opus for complex logic, Codex for parallel implementation. Model selection is guided by the routing table, which Interspect adjusts based on outcome data.

During execution, the developer is above the loop, not in it. They can observe phase transitions and agent dispatches in the terminal. They intervene only on exceptions: a gate that fails, a test that needs human judgment, a scope question that wasn't anticipated in the plan. The goal is zero interventions for routine work and clear, actionable prompts when intervention is needed.

**Ship.** The change is complete. Quality gates run: tests pass, linting passes, and for risky changes, the review fleet examines the final diff. The developer confirms the push. The commit lands on main.

**Reflect.** The agency captures what happened: complexity estimates vs. actuals, model routing decisions and their outcomes, review findings and whether they were acted on, time spent per phase. This data feeds into Interspect's calibration pipeline. Solution docs are generated for novel patterns. The bead is closed.

The next time the developer runs `/route`, the system is slightly better at estimating complexity, slightly better at selecting models, slightly better at knowing which review agents to deploy. The flywheel turns.

## Success Signals

| Signal | Type | Assertion |
|--------|------|-----------|
| `/route` presents relevant work within 5 seconds | measurable | Discovery scan completes and renders options in <5s |
| Complexity classification matches actual effort | observable | Estimated complexity (1-5) correlates with actual tokens spent and phases needed |
| Brainstorm surfaces at least one non-obvious insight | qualitative | Brainstorm artifact contains analysis the developer hadn't considered |
| Plan is executable without ambiguity | qualitative | Developer reads the plan and has no clarifying questions |
| Execution follows existing codebase patterns | observable | New code matches naming conventions, file structure, and idioms of surrounding code |
| Tests pass after each incremental commit | measurable | No commit in the sprint has failing tests |
| Model routing uses the cheapest sufficient model | observable | Haiku/Sonnet dispatches appear for subtasks that don't require Opus |
| Sprint completes without unnecessary human intervention | measurable | Intervention count is 0 for routine work, <=2 for complex work |
| Bead is closed with complete metadata | measurable | `bd show <id>` shows CLOSED status, all state fields populated |
| Reflect phase produces reusable learnings | observable | Solution doc or calibration data is written to persistent storage |
| Cost per landable change trends downward over time | measurable | Running average of sprint cost decreases as Interspect calibrates |

## Known Friction Points

- **Discovery ranking opacity.** The scanner ranks beads by priority, staleness, and dependencies, but the ranking logic isn't visible to the developer. A bead that should be top-ranked may be buried if its metadata is incomplete.
- **Complexity misclassification.** The classifier uses heuristics (description length, dependency count, file scope). A task that reads as simple but touches a complex subsystem may be underestimated, leading to an undersized workflow (no brainstorm, no review) that produces lower-quality output.
- **Brainstorm-to-plan handoff.** The brainstorm explores; the plan commits. If the brainstorm raises open questions that aren't resolved before planning, the plan may contain ambiguities that surface during execution.
- **Gate failures mid-sprint.** A failed gate (test failure, lint error, missing artifact) blocks advancement. The error message tells you what failed but not always why or how to fix it. Recovery requires understanding the phase/gate model.
- **Context window pressure on long sprints.** A complex sprint that runs through all phases accumulates context. The write-behind protocol (raw output to kernel, summaries to context) mitigates this, but very long sprints may still hit quality degradation in later phases.
- **Reflect phase feels optional.** The developer wants to move to the next task. Reflect produces calibration data and solution docs, but the value is invisible until Interspect uses it weeks later. Easy to skip, expensive to skip repeatedly.
