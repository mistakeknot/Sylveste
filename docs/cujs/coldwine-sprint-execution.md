---
artifact_type: cuj
journey: coldwine-sprint-execution
actor: regular user (developer running task sprints)
criticality: p2
bead: Demarch-2c7
---

# Coldwine Sprint Execution

## Why This Journey Matters

Coldwine bridges the gap between "here's a plan" and "here's shipped code." It takes a set of tasks — from Gurgeh specs, beads, or manual input — and orchestrates their execution across agent sessions. The developer sees tasks flow through states (pending → in-progress → review → done), diffs accumulate, and branches merge. Without Coldwine, the developer manually tracks which tasks are done, which agents are working on what, and which branches need review.

The sprint is the heartbeat of daily development. If it's too rigid (forced sequencing, mandatory reviews for trivial changes), developers bypass it. If it's too loose (no visibility, no checkpoints), they lose track. Coldwine must be the Goldilocks orchestrator — just enough structure to prevent chaos, not so much that it slows velocity.

## The Journey

The developer loads their task set. In Epics mode, they see a tree of related tasks with dependencies. In Runs mode, they see a flat list sorted by priority. They pick a mode based on the work — epics for feature development, runs for bug-fix batches.

They start a sprint. Coldwine assigns tasks to available agents (or the developer picks manually). The TUI shows a split or inline view: task list on the left, agent output on the right. As agents work, Coldwine tracks diffs, runs tests, and flags failures. The developer can approve completed tasks, request changes, or reassign.

For the inline layout, Coldwine preserves terminal scrollback — the developer can scroll up to see previous agent output without losing context. The split layout gives a side-by-side view for review-heavy work.

When all tasks complete, Coldwine generates a sprint summary: what shipped, what's still open, test results, and token cost. The developer can export this to beads (closing completed items) or save it for the next session.

## Success Signals

| Signal | Type | Assertion |
|--------|------|-----------|
| Sprint starts within 30 seconds of task selection | measurable | Time from selection to first agent dispatch ≤ 30s |
| Task state transitions are visible in real-time | observable | TUI updates within 2 seconds of state change |
| Inline mode preserves scrollback | measurable | Terminal scrollback accessible after sprint completes |
| Failed tasks are flagged, not silently skipped | measurable | Failed tasks have status=failed with error reason |
| Sprint summary matches actual work done | measurable | Summary task count equals closed + failed count |
| Developer can resume a sprint across sessions | measurable | Sprint state persists in .coldwine/ and reloads |

## Known Friction Points

- **Agent output rendering** — long diffs in the TUI can be slow. The viewport needs efficient scrolling for large outputs.
- **No automatic beads integration** — sprint completion doesn't auto-close beads. Manual step required.
- **Review workflow assumes branches** — trunk-based development (Demarch's model) means review is commit-level, not PR-level. Coldwine's review UI was designed for branch-based flow.
- **Model initialization overhead** — first agent dispatch in a sprint has cold-start latency.
