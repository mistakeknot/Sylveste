---
bead: sylveste-rsj.3
date: 2026-03-30
type: reflection
---

# Reflection: Roguelike-Inspired Agent Architecture

## What Worked

1. **Parallel research agents produced rich findings fast.** Four agents (Arcgentica deep-dive, NLE/environment survey, roguelike↔agent isomorphisms, research planner) ran in parallel and returned within ~5 minutes. The research planner's decomposition was not used directly but confirmed the other agents' coverage was comprehensive.

2. **The "surprisingly related" framing produced the best insights.** Arcgentica turned out not to be a roguelike at all — it's an ARC-AGI agent harness — but its architecture (orchestrator → sub-agents, compressed summaries, parallel hypotheses) provided the strongest external validation of Sylveste's core thesis. The 340x efficiency figure is more compelling than any roguelike analogy.

3. **Plan review caught real gaps.** The fd-user-product reviewer identified that the BALROG assessment would close on documentation without pulling toward actual execution. The fix (follow-on bead requirement in DoD) prevents the assessment from becoming shelf-ware.

## What I'd Change

1. **The vision doc update (Task 1) was the weakest deliverable.** The plan reviewer was right — it's decorative unless cross-linked from places where developers actually make routing decisions. I added the Interspect vision cross-link to make it load-bearing, but the brainstorm doc has far more detail than the vision doc paragraph. The real value is in the assessment docs.

2. **Should have checked whether "Arcgentica" was a roguelike before dispatching a dedicated research agent.** A 30-second web search would have redirected that agent's prompt to be more targeted. Instead it spent time trying name variations before finding the real thing.

3. **Assessment docs were delegated to agents without reading the Interspect codebase first.** The identification-as-calibration agent had to discover the routing architecture cold. Pre-reading lib-routing.sh and providing key function names in the prompt would have produced a more grounded assessment.

## Calibration Data

- **Research phase:** 4 parallel agents, ~5 min wall clock, ~209K total tokens
- **Execution phase:** 3 tasks (1 direct, 2 agents), ~10 min wall clock
- **Plan review:** 1 agent, caught 5 concrete improvements (0 P0/P1, 5 P2/P3)
- **Total artifacts:** 7 files (brainstorm, PRD, plan, 2 assessments, 2 doc edits)

## Lessons for Future Sprints

- **Pre-validate assumptions before dispatching expensive research.** A quick web search before agent dispatch avoids wasted context on misidentified subjects.
- **Assessment epics should always require follow-on beads in their DoD.** The pattern "assess → close bead → nothing happens" is the most common way research epics die. Every assessment bead should create its execution bead as part of closing.
- **Plan review is cheap relative to its value on documentation epics.** It caught the decorative-vs-load-bearing distinction and the assessment→execution gap. Worth running even on small plans.
