---
artifact_type: cuj
journey: clavain-parallel-dispatch
actor: regular user (developer running multiple agents on a plan)
criticality: p2
bead: Demarch-2c7
---

# Clavain Parallel Agent Dispatch

## Why This Journey Matters

A development plan with 8 tasks can be executed sequentially — one agent, one task at a time — or in parallel where independent tasks run simultaneously. Sequential execution is safe but slow. Parallel execution is fast but requires coordination: file reservation to prevent conflicts, progress tracking across agents, and graceful handling when one agent blocks on another's output.

Clavain's parallel dispatch (`/clavain:dispatching-parallel-agents`) is how the platform achieves its speed promise. A plan that would take 4 hours sequentially completes in 90 minutes with 3 agents working in parallel. But only if the coordination works: conflicts stall the fleet, and a bad dispatch (wrong agent for the task) wastes tokens and time.

## The Journey

The developer has a plan with 8 tasks. They run `/clavain:work <plan>`. Clavain analyzes task dependencies: tasks 1-3 have no dependencies (parallelizable), task 4 depends on task 1, tasks 5-6 depend on task 3, tasks 7-8 depend on everything.

Clavain dispatches tasks 1-3 simultaneously to three agents. Each agent claims its bead, reserves its files via Interlock, and starts working. The developer sees progress in real-time — three task cards advancing in parallel.

Task 2 finishes first. Clavain checks: does anything depend on task 2? No. The agent is now free. Clavain assigns the next eligible task — but tasks 4 and 5-6 both have unmet dependencies. The agent waits.

Task 1 finishes. Task 4 is now unblocked. Clavain dispatches it to the free agent. Task 3 finishes. Tasks 5 and 6 are unblocked — dispatched to two agents.

If two agents need the same file, Interlock's reservation system kicks in. The second agent sees the reservation and works on something else, or negotiates with the first agent for access. The developer can see the coordination: `/interlock:status` shows who holds what.

When all tasks complete, Clavain runs quality gates on the aggregate change, commits, and ships. The developer reviews the summary: total time, per-agent stats, token cost, and any issues encountered.

For Codex-backed dispatch (`/clavain:interserve`), independent tasks can be sent to Codex CLI agents for cost-efficient parallel execution. Clavain keeps architecture, brainstorming, and interactive work in Claude while delegating scoped implementation to Codex.

## Success Signals

| Signal | Type | Assertion |
|--------|------|-----------|
| Independent tasks dispatch in parallel, not sequentially | measurable | Tasks with no shared dependencies start within 10s of each other |
| Dependency resolution prevents premature starts | measurable | No task starts before its dependencies complete |
| File reservation prevents concurrent edits | measurable | Zero merge conflicts during parallel execution |
| Wall time is meaningfully less than sequential | measurable | Parallel execution is faster than sequential for plans with 4+ independent tasks |
| Failed tasks are re-assigned, not abandoned | measurable | A failed task is re-dispatched to another agent; dependent tasks wait |
| Progress is visible across all agents simultaneously | observable | Multi-agent dashboard shows all active tasks |
| Codex dispatch works for scoped implementation tasks | measurable | `/interserve` completes tasks and returns results |

## Known Friction Points

- **Dependency analysis is task-level, not file-level** — Clavain knows task 4 depends on task 1, but doesn't know which specific files task 4 needs from task 1. Over-conservative reservation is common.
- **Agent skill matching is basic** — Clavain doesn't match agent capabilities to task requirements. All available agents are treated as fungible.
- **Codex sandbox limitations** — Codex CLI's bwrap sandbox fails on some kernels. Fallback to `--dangerously-bypass-approvals-and-sandbox` exists but reduces safety.
- **Cost scales with parallelism** — 3 agents running simultaneously use 3x the tokens per minute. Budget monitoring is important.
- **Coordination overhead** — Interlock reservation, Intermux visibility, and Intercore eventing add latency. For small plans (2-3 tasks), sequential might be faster.
