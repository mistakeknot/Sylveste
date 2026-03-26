# Trigger Mechanisms & Idle Detection for AI Agent Self-Dispatch

> Phase 1 research: How and when should an AI agent decide it's idle and pull new work?

## 1. Kubernetes HPA/KEDA: Metrics-Poll vs Event-Push

### HPA (Horizontal Pod Autoscaler) — Metrics-Poll Model

HPA polls the metrics API on a fixed interval (default 15s, configurable via `--horizontal-pod-autoscaler-sync-period`). It reads CPU/memory utilization, computes a desired replica count, and reconciles. This is a **pure pull model**: no external system pushes "you're idle" — the controller discovers it by polling.

**Mapping to tmux pane activity:** HPA's model maps directly to intermux's current 10-second scan. Both are periodic samplers that derive state from observable metrics. HPA's weakness — lag between "idle" and "scale decision" — is exactly the latency we'd see in a poll-based trigger for agent work-pull.

### KEDA (Kubernetes Event-Driven Autoscaler) — Hybrid Event/Poll Model

KEDA improves on HPA with three key parameters:

| Parameter | Default | Purpose |
|---|---|---|
| `pollingInterval` | 30s | How often KEDA checks each trigger source |
| `cooldownPeriod` | 300s (5min) | Wait time after last active trigger before scaling to zero |
| `activationThreshold` | per-scaler | Minimum metric value to scale from 0 → 1 |

KEDA's architecture is **hybrid**: scalers poll external event sources (queues, Prometheus, etc.) at `pollingInterval`, but the *decision* to scale is event-driven — triggered by the scaler returning a non-zero metric. KEDA acts as a Kubernetes metrics server, feeding event-based metrics to the HPA machinery.

**Key insight for self-dispatch:** KEDA's `cooldownPeriod` is the direct analog of "how long must an agent be idle before we declare it available for new work." Too short = premature work-pull (agent was just between tool calls). Too long = wasted idle time. KEDA defaults to 5 minutes, but latency-critical workloads use 10-15 seconds — which is the range we should target.

### What Maps to Tmux Pane Activity

| KEDA Concept | Agent Self-Dispatch Analog |
|---|---|
| ScaledObject trigger | Intermux watcher detecting `StatusIdle` |
| `pollingInterval` | Watcher scan interval (currently 10s) |
| `cooldownPeriod` | Minimum idle duration before pulling work |
| `activationThreshold` | "Is there queued work?" check |
| Scale 0→1 | "Agent is idle, inject next-work command" |

**Recommendation:** Use KEDA's two-phase model: (1) frequent polling to detect idle state, (2) cooldown timer to confirm it's real idle, not inter-tool pause.

Sources:
- [KEDA Concepts: Scaling Deployments](https://github.com/kedacore/keda-docs/blob/main/content/docs/2.10/concepts/scaling-deployments.md)
- [KEDA Scale-to-Zero](https://oneuptime.com/blog/post/2026-02-09-keda-scale-from-zero-event-driven/view)
- [KEDA cooldownPeriod semantics](https://github.com/kedacore/keda/discussions/3036)

---

## 2. Toyota TPS Kanban: Pull Signal Mechanics

### The Core Pull Mechanism

In Toyota's production system, **no upstream station produces anything until a downstream station signals need.** The signal (kanban card) flows *opposite* to material flow:

```
Material:  Upstream → Downstream
Signal:    Downstream → Upstream (kanban card returns when part consumed)
```

The trigger is consumption: when a downstream station uses a part from its buffer, the empty container (or card) travels back upstream as authorization to produce exactly one more unit.

### What Triggers a Downstream Station to Request Work

Three conditions must all be true for a pull signal:

1. **Buffer depleted** — the downstream station has consumed a work item from its local buffer (WIP limit reached on the output side)
2. **Capacity available** — the station has finished its current work and has capacity (is idle)
3. **Signal mechanism exists** — a physical kanban card, empty container, or electronic signal is the medium

The critical insight: **the signal is the empty slot, not a timer.** TPS doesn't poll "are you idle?" — the act of completing work *is* the signal. The kanban card returning to the upstream queue is an event, not a polled metric.

### Mapping to Agent Self-Dispatch

| TPS Concept | Agent Self-Dispatch Analog |
|---|---|
| Kanban card | Bead (work item) completion event |
| Empty buffer slot | Agent reaches idle state (no active bead) |
| WIP limit | Max concurrent beads per agent (currently 1) |
| Pull signal | "I finished my bead, give me the next one" |
| Upstream queue | Sprint backlog / prioritized bead queue |

**Key lesson:** TPS favors **event-driven pull** (completion triggers next-work request) over **timer-based poll** (periodically checking if idle). The agent's `Stop` hook firing is the closest analog to a kanban card returning — it's the event that says "I finished a unit of work."

### Heijunka (Level Loading) Consideration

TPS also level-loads work to prevent burst demand. For agents, this means the work queue should be pre-prioritized so the pull signal doesn't need to make complex scheduling decisions at trigger time. The dispatcher should be a simple "pop next from sorted queue," not a planning step.

Sources:
- [Toyota Production System - Wikipedia](https://en.wikipedia.org/wiki/Toyota_Production_System)
- [Pull Systems (Kanban) - Lean Techniques](https://www.ineak.com/pull-systems-kanban-lean-techniques/)
- [Kanban - Wikipedia](https://en.wikipedia.org/wiki/Kanban)

---

## 3. Game Engine Job Systems: Completion Callbacks vs Polling

### Unity DOTS Job System

Unity's job system uses a **dependency graph with synchronous completion checks**, not callbacks:

```csharp
JobHandle handle = myJob.Schedule();
// ... do other work ...
handle.Complete();  // blocks until job finishes
```

`Complete()` is a blocking call — the caller polls/waits synchronously. There are no completion callbacks in the standard API. Instead, the system relies on **dependency chaining**: when scheduling a job, you declare its dependencies, and the scheduler ensures ordering. Jobs that depend on a completed job are automatically eligible to run.

**Work availability detection:** Unity's job scheduler uses a thread pool where worker threads pull from a shared task queue. When a worker finishes a job, it immediately checks for the next available job — no explicit "idle detection" step. The thread either has work or blocks on the queue.

### Unreal Engine TaskGraph

Unreal's TaskGraph uses a **priority-based work-stealing** model:

- Worker threads have per-thread deques (double-ended queues)
- Workers pull from their own deque (LIFO for cache locality)
- **Idle workers steal from other workers' deques** (FIFO for fairness)
- Task completion fires prerequisite resolution: when task A completes, all tasks that depended on A become eligible

The key pattern is **work-stealing**: idle workers actively seek work from busy workers' queues. This is a pull model where idle detection is implicit — if your local queue is empty, you're idle, and you immediately try to steal.

### Relevance to Agent Self-Dispatch

| Game Engine Pattern | Agent Self-Dispatch Analog |
|---|---|
| Dependency graph | Bead dependency chains (epic → child beads) |
| `Complete()` blocking | Stop hook (synchronous check point) |
| Work-stealing | Agent pulling from shared sprint queue |
| Per-thread deque | Per-agent assigned work buffer |
| Priority levels | Bead priority / sprint ordering |

**Key insight:** Game engines don't have a separate "idle detection" phase. Completion of work *is* the trigger to find more work. The thread never enters an "idle" state and then separately decides to look for work — those are the same operation. This is the strongest argument for an event-driven (Stop hook) approach over poll-based (timer) detection.

Sources:
- [Unity Job System Documentation](https://docs.unity3d.com/Manual/job-system.html)
- [Unreal Engine Tasks Systems](https://dev.epicgames.com/documentation/en-us/unreal-engine/tasks-systems-in-unreal-engine)
- [Work Stealing - Wikipedia](https://en.wikipedia.org/wiki/Work_stealing)
- [Work-Stealing Task Scheduler in Go](https://medium.com/@nathanbcrocker/building-a-multithreaded-work-stealing-task-scheduler-in-go-843861b878me)

---

## 4. Intermux's Existing Tmux Watcher: Is 10-Second Resolution Sufficient?

### Current Architecture

Intermux's watcher (`internal/tmux/watcher.go`) runs a goroutine on a 10-second ticker:

```go
Interval: 10 * time.Second  // WatcherConfig default
```

Each scan: `listSessions()` → filter by agent name → `capturePaneContent()` → `ParsePaneContent()` → detect status. Status detection works by checking the last 10 lines of pane content for:

- **Active indicators:** "Thinking", "Reading", "Writing", "Editing", "Running", "Searching", "Analyzing"
- **Idle indicators:** prompt patterns (`$`, `>`, `claude>`, `?`)
- **Stuck detection:** active status but no content change for >5 minutes
- **Crash detection:** process PID no longer alive

### Resolution Analysis

**For triggering work-pull, 10 seconds is borderline sufficient but not ideal.**

| Scenario | 10s resolution impact |
|---|---|
| Agent finishes bead, prompt appears | 0-10s detection lag — acceptable |
| Agent between tool calls (brief idle) | May false-positive as idle — dangerous |
| Agent waiting for user input (true idle) | 10s detection + cooldown — fine |
| Agent crashed | 0-10s detection — acceptable |

The core problem: **10 seconds cannot distinguish "brief pause between tool calls" from "actually done with all work."** A Claude Code session shows a prompt between turns — the same `$` or `>` that appears when truly idle also appears momentarily between responses.

### Recommended Changes

1. **Keep 10s scan interval** for health monitoring — it's fine for dashboard/status purposes
2. **Add cooldown timer for idle confirmation** — require 2-3 consecutive idle scans (20-30s) before declaring "available for work-pull"
3. **Prefer hook-based triggers** (Section 5) for the actual work-pull decision — the watcher becomes a fallback/validation mechanism, not the primary trigger
4. **Add `StatusIdleConfirmed` state** — distinct from `StatusIdle`, meaning "idle for long enough to pull new work"

### What Intermux Already Has That's Useful

- `lastChangeAt` tracking per session — can compute idle duration
- `StatusStuck` detection (5 min unchanged) — proof the cooldown pattern works
- `ActivityEvent` ring buffer — can detect patterns like "idle → active → idle → active" (inter-tool chatter) vs "idle for 30s straight" (truly done)
- Agent ID correlation via `/tmp/intermux-mapping-*.json` — knows which Claude session maps to which tmux pane

---

## 5. Claude Code Hook Lifecycle: Which Hook for "Check for Next Work"?

### Available Hook Events (Lifecycle Order)

```
SessionStart          → session begins
UserPromptSubmit      → user sends a message
PreToolUse            → before a tool call
PermissionRequest     → permission check
PostToolUse           → after a tool call
Notification          → Claude sends notification
PreCompact            → before context compaction
Stop                  → after each assistant response (every turn)
SubagentStop          → after a subagent completes
SessionEnd            → (REQUESTED BUT NOT YET IMPLEMENTED as of 2026-03)
```

### Stop Hook: The Primary Candidate

The `Stop` hook fires **after every assistant response**, which is the closest analog to "I just finished a unit of work." It supports:

- **JSON output** with `decision` field: `"block"` prevents Claude from stopping (forces continuation)
- **`reason` field:** explanation injected into Claude's context for the next turn
- **`continue` field:** boolean override (false = force stop, true = keep going)
- **Exit code 2:** signals blocking feedback that halts current action

**The self-dispatch pattern via Stop hook:**

```
Claude completes response
  → Stop hook fires
  → Hook script checks: "Is there queued work?"
    → If yes: return {"decision": "block", "reason": "Next task: <bead description>"}
    → If no: return {"decision": "approve"} (let Claude stop normally)
```

### Critical Ordering Guarantees and Limitations

1. **Parallel execution:** When multiple hooks match the same event, they run in parallel. Identical commands are deduplicated. This means a Stop hook and a SubagentStop hook could race.

2. **Infinite loop risk:** A Stop hook that always blocks creates an infinite loop (block → Claude processes → Stop fires again → block). **Must include a circuit breaker** — e.g., check `stop_hook_active` field, or count consecutive blocks.

3. **SubagentStop vs Stop:** For subagents spawned by a parent Claude session, `Stop` hooks are automatically converted to `SubagentStop`. Self-dispatch should only trigger on `Stop` (top-level agent), never on `SubagentStop` (subagent completing is the parent's concern).

4. **No true SessionEnd:** The `Stop` hook fires after every turn, not just at session end. There's an [open feature request](https://github.com/anthropics/claude-code/issues/34954) for a `SessionEnd` hook that fires exactly once. Until that exists, Stop is the only end-of-turn hook.

5. **Async vs sync:** Stop hooks default to `blocking?: false` to prevent infinite loops. For self-dispatch, we **want** blocking behavior (to inject the next task), so we must explicitly handle the loop prevention.

### PostToolUse: A Secondary Signal

`PostToolUse` fires after every tool call. It could detect specific "work complete" signals:

- After a `git push` (bead is done)
- After `bd close` (bead explicitly closed)
- After the last Edit in a sequence

But PostToolUse fires too frequently (after every Read, Edit, Bash call) to be a reliable work-pull trigger. It's better as a **signal enrichment source** — feeding data to the Stop hook's decision logic.

### Recommended Hook Architecture

```
PostToolUse (async, non-blocking)
  → Detect "bead closed" or "git pushed" signals
  → Write to /tmp/flux-dispatch-signal-<session>.json
  → No blocking, no decision

Stop (blocking, with circuit breaker)
  → Read /tmp/flux-dispatch-signal-<session>.json
  → If signal present AND queue has work:
      return {"decision": "block", "reason": "Pull next: ..."}
  → If no signal or no work:
      return {"decision": "approve"}
  → Circuit breaker: if last 3 Stop hooks all blocked, approve (break loop)
```

Sources:
- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks)
- [Stop Hook Task Enforcement](https://claudefa.st/blog/tools/hooks/stop-hook-task-enforcement)
- [Hook Control Flow](https://stevekinney.com/courses/ai-development/claude-code-hook-control-flow)
- [SessionEnd Feature Request](https://github.com/anthropics/claude-code/issues/34954)
- [SubagentStop feedback issue](https://github.com/anthropics/claude-code/issues/20221)

---

## 6. Behavior Tree Selector Nodes & Utility AI Idle Patterns

### Classic Behavior Tree Idle Fallback

In behavior trees, a **Selector** (or Fallback) node tries each child left-to-right until one succeeds:

```
Selector
  ├── [Priority 1] Combat (condition: enemy visible?)
  ├── [Priority 2] Build (condition: blueprint assigned?)
  ├── [Priority 3] Gather (condition: resources needed?)
  └── [Priority 4] Idle (always succeeds — wander, rest)
```

The Idle node is the **terminal fallback** — it always succeeds, ensuring the NPC never gets stuck. Game AI treats idle as the natural state; work is the interruption.

### Worker NPC Pattern (Colony Sims)

Rubenwardy's colonist AI blog (2022) describes the pattern most relevant to agent self-dispatch:

```
Root (Selector)
  ├── HasAssignedWork? → DoWork (sub-tree)
  └── FindWork (action node)
        ├── Query global work allocator
        ├── Claim work item
        └── Return to DoWork
```

**Critical design decision:** The global work allocator tracks idle workers each frame and allocates work in batch, rather than having each NPC independently race to claim work. This prevents thundering-herd problems when multiple workers become idle simultaneously.

### Utility AI Scoring for Work Selection

Pure behavior trees use binary conditions (work exists? yes/no). Utility AI adds **scoring** to select *which* work:

```
Utility Selector
  ├── FixBug(score: urgency × skill_match × proximity)
  ├── AddFeature(score: priority × complexity_fit)
  ├── WriteTests(score: coverage_gap × module_familiarity)
  └── Idle(score: 0.1)  // always available, always lowest
```

The Game AI Pro chapter on building utility decisions into behavior trees (Merrill, 2013) describes a **Utility Selector** node that queries children for utility values rather than binary success/fail. Only leaf behaviors compute utility; parent nodes propagate the best child's score.

**Mapping to agent self-dispatch:**

| Utility AI Concept | Agent Analog |
|---|---|
| Utility score | Bead priority × agent skill affinity |
| Evaluation function | Sprint queue ordering + agent capability match |
| Utility Selector | Work-pull decision: which bead to claim |
| Idle score (0.1) | "Do nothing" option — prevents low-value work-pull |
| Re-evaluation frequency | Each Stop hook invocation |

### The "If Nothing Urgent, Seek Work" Pattern

Game NPCs implement this as a **two-tier selector**:

```
Root (Selector)
  ├── Urgent (Selector — checked every tick)
  │     ├── UnderAttack?
  │     ├── OnFire?
  │     └── CriticalBugFiled?
  └── Normal (Selector — checked when idle)
        ├── HasQueuedWork? → ClaimAndDo
        ├── CanHelp(neighbor)? → Assist
        └── Rest
```

The "Normal" branch only evaluates when the "Urgent" branch fails — meaning the agent is not mid-task. This maps to:

```
Agent Loop (Selector)
  ├── ActiveBead? → Continue working (Stop hook: approve)
  ├── UrgentBeadQueued? → Pull immediately (Stop hook: block with task)
  ├── NormalBeadQueued? → Pull after cooldown (Stop hook: block with task)
  └── NoWork → Idle (Stop hook: approve, let Claude stop)
```

Sources:
- [Creating Worker NPCs Using Behavior Trees](https://blog.rubenwardy.com/2022/07/17/game-ai-for-colonists/)
- [Behavior Trees for AI: How They Work](https://www.gamedeveloper.com/programming/behavior-trees-for-ai-how-they-work)
- [Building Utility Decisions into Your Existing Behavior Tree (Game AI Pro)](http://www.gameaipro.com/GameAIPro/GameAIPro_Chapter10_Building_Utility_Decisions_into_Your_Existing_Behavior_Tree.pdf)
- [Behavior Tree - Wikipedia](https://en.wikipedia.org/wiki/Behavior_tree_(artificial_intelligence,_robotics_and_control))

---

## Synthesis: Recommended Trigger Architecture

### Decision Matrix

| Approach | Latency | False Positive Risk | Complexity | Source Domain |
|---|---|---|---|---|
| Poll-only (intermux 10s scan) | 10-20s | High (inter-tool pauses) | Low | HPA |
| Event-only (Stop hook) | <1s | Medium (every turn fires) | Medium | TPS kanban, game engines |
| Hybrid: event + cooldown | 5-30s (configurable) | Low | Medium | KEDA |
| Hybrid: event + signal file | <1s for real idle | Very low | Higher | Behavior tree + utility AI |

### Recommended: Two-Layer Trigger

**Layer 1: Stop Hook (event-driven, primary trigger)**

The Stop hook fires after each Claude response. A shell script checks for dispatch signals:

1. Was a bead just closed? (check `/tmp/flux-dispatch-signal-*.json`)
2. Is the sprint queue non-empty? (check `bd list --status=open --limit=1`)
3. Has the agent been idle for >1 consecutive Stop invocation? (timestamp file)
4. Circuit breaker: has this hook blocked >3 times in a row? (prevent loops)

If all conditions met: `{"decision": "block", "reason": "Next bead: <id> — <title>"}`.

**Layer 2: Intermux Watcher (poll-based, fallback/validation)**

The 10-second scan provides:

1. Ground truth for agent status (pane content confirms idle vs active)
2. Stuck detection (agent claims active but no progress for 5 min)
3. Crash detection (PID dead)
4. Cross-validation: if Stop hook says "idle" but watcher sees "active," something is wrong

### Cooldown Configuration

Drawing from KEDA's parameters:

| Parameter | Recommended Value | Rationale |
|---|---|---|
| Idle confirmation period | 20s (2 watcher scans) | Distinguish inter-tool pause from true idle |
| Post-bead-close pull delay | 5s | Allow git push to complete |
| Max consecutive blocks | 3 | Circuit breaker for Stop hook loops |
| Scan interval (watcher) | 10s (keep current) | Sufficient for health monitoring |
| Queue check interval | On-demand (Stop hook) | Don't poll the queue separately |

### State Machine

```
                    ┌─────────────┐
                    │   WORKING   │
                    │ (active bead)│
                    └──────┬──────┘
                           │ Stop hook fires
                           │ bead still open
                           ▼
                    ┌─────────────┐
                    │  BETWEEN    │──── Stop hook: approve
                    │  TURNS      │     (not idle yet)
                    └──────┬──────┘
                           │ Stop hook fires
                           │ no active bead
                           ▼
                    ┌─────────────┐
              ┌────│ IDLE_PENDING │──── Start cooldown timer
              │    └──────┬──────┘
              │           │ Cooldown elapsed (20s)
              │           │ Watcher confirms idle
              │           ▼
              │    ┌─────────────┐
              │    │ IDLE_READY  │──── Check queue
              │    └──────┬──────┘
              │           │
              │     ┌─────┴──────┐
              │     ▼            ▼
              │  Queue has    Queue empty
              │  work           │
              │     │           ▼
              │     │    ┌─────────────┐
              │     │    │   PARKED    │ (truly idle, no work)
              │     │    └─────────────┘
              │     ▼
              │  ┌─────────────┐
              └──│ DISPATCHING │──── Stop hook: block
                 │ (inject task)│     reason: "Pull bead X"
                 └──────┬──────┘
                        │ Claude starts new bead
                        ▼
                 ┌─────────────┐
                 │   WORKING   │
                 └─────────────┘
```

### What Not to Do

1. **Don't use tmux `send-keys` to inject work.** It types characters into the pane, racing with Claude's own output. Use the Stop hook's `reason` field — it's injected into Claude's context cleanly.

2. **Don't trigger on PostToolUse.** It fires hundreds of times per session. Use it only to *set a signal file* that the Stop hook reads.

3. **Don't poll the bead queue on a timer.** `bd list` is a Dolt query that takes 200-500ms. Running it every 10 seconds wastes resources. Only query when the Stop hook fires and idle state is confirmed.

4. **Don't dispatch to subagents via SubagentStop.** Subagent completion is the parent's concern. Self-dispatch should only operate on top-level `Stop` hooks.

5. **Don't skip the cooldown.** Without it, every inter-tool-call pause looks like idle and triggers spurious work-pulls.

<!-- flux-research:complete -->
