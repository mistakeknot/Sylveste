---
artifact_type: cuj
journey: clavain-parallel-dispatch
actor: regular user (developer running multiple agents on a plan)
criticality: p2
bead: Sylveste-2c7
---

# Clavain Parallel Agent Dispatch

## Why This Journey Matters

A development plan with 8 tasks can be executed sequentially — one agent, one task at a time — or in parallel where independent tasks run simultaneously. Sequential execution is safe but slow. Parallel execution is fast but requires coordination: file reservation to prevent conflicts, progress tracking across agents, and graceful handling when one agent blocks on another's output.

Clavain's parallel dispatch (`/clavain:dispatching-parallel-agents`) is how the platform achieves its speed promise. A plan that would take 4 hours sequentially completes in 90 minutes with 3 agents working in parallel. But only if the coordination works: conflicts stall the fleet, and a bad dispatch (wrong agent for the task) wastes tokens and time.

## The Journey

The developer has a plan file (YAML or markdown with task list) containing 8 tasks. They run `/clavain:work <plan-file>`. Clavain automatically analyzes task dependencies: tasks 1-3 have no dependencies (parallelizable), task 4 depends on task 1, tasks 5-6 depend on task 3, tasks 7-8 depend on everything.

Clavain dispatches tasks 1-3 simultaneously to three agents. Each agent auto-joins Interlock, claims its bead, reserves its files, and starts working. The developer sees progress in real-time — three task cards advancing in parallel.

Task 2 finishes first. Clavain checks: does anything depend on task 2? No. The agent is now free. Clavain assigns the next eligible task — but tasks 4 and 5-6 both have unmet dependencies. The agent waits.

Task 1 finishes. Task 4 is now unblocked. Clavain dispatches it to the free agent. Task 3 finishes. Tasks 5 and 6 are unblocked — dispatched to two agents.

If a task fails (agent timeout after 45 minutes, non-zero exit, or unrecoverable error), Clavain unclaims the bead and re-dispatches to another agent (max 2 retries). Dependent tasks wait during re-dispatch. If the heartbeat stops (agent crash), the stale claim expires via adaptive timeout and Clavain's orchestrator reclaims it — this is the slow-path fallback.

If two agents need the same file, Interlock's reservation system kicks in. The second agent sees the reservation and works on something else, or negotiates with the first agent for access. The developer can see the coordination: `/interlock:status` shows who holds what.

When all tasks complete, Clavain runs quality gates on the aggregate change — intersynth operates on the combined diff of all completed tasks, not per-task diffs — then commits and ships. The developer reviews the summary: total time, per-agent stats, token cost, and any issues encountered. Parallel dispatch records wall-time, sum-of-task-durations, and agent count per run for post-hoc performance analysis.

For Codex-backed dispatch (`/clavain:interserve`), independent tasks can be sent to Codex CLI agents for cost-efficient parallel execution. Codex agents run within Codex's Landlock+seccomp sandbox (workspace-write mode), and their output is validated post-dispatch (diff scope check, quality gates) before being accepted. Clavain keeps architecture, brainstorming, and interactive work in Claude while delegating scoped implementation to Codex.

## Success Signals

| Signal | Type | Assertion |
|--------|------|-----------|
| Independent tasks dispatch in parallel, not sequentially | measurable | Tasks with no shared dependencies start within 10s of each other |
| Dependency resolution prevents premature starts | measurable | No task starts before its dependencies complete |
| File reservation prevents concurrent edits | measurable | Zero merge conflicts during parallel execution (Interlock file-level reservation enforces this) |
| Dispatch records performance metrics | measurable | Wall-time, task-sum, and agent count logged per run for post-hoc analysis |
| Failed tasks are re-assigned, not abandoned | measurable | A failed task (timeout/error/crash) is re-dispatched to another agent (max 2 retries); dependent tasks wait |
| Progress is visible across all agents simultaneously | observable | Multi-agent dashboard shows all active tasks |
| Codex dispatch works for scoped implementation tasks | measurable | `/interserve` completes tasks within sandbox, output passes post-dispatch validation |

## Known Friction Points

- **Dependency analysis is task-level, not file-level** — Clavain knows task 4 depends on task 1, but doesn't know which specific files task 4 needs from task 1. Over-conservative reservation is common.
- **Agent skill matching is basic** — Clavain doesn't match agent capabilities to task requirements. All available agents are treated as fungible.
- **Codex sandbox requires Landlock** — Codex's default sandbox uses Landlock+seccomp (kernel ≥ 5.13). On older kernels, the sandbox degrades to unsandboxed. Post-dispatch validation provides the safety net.
- **Codex trust model is structural, not behavioral** — Codex agents rely on OS-level sandboxing and post-dispatch validation, not Skaffen's trust evaluator. Trust rules do not transfer to Codex dispatches.
- **Cost scales with parallelism** — 3 agents running simultaneously use 3x the tokens per minute. Budget monitoring is important.
- **Coordination overhead** — Interlock reservation, Intermux visibility, and Intercore eventing add latency. For small plans (2-3 tasks), sequential might be faster.
