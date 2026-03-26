# Scheduling and Resource Allocation Patterns for AI Agent Factories

## Research Question

What novel scheduling and resource allocation patterns become possible when workers are cloneable, cost is continuous, and spawn latency approaches zero — drawing from hospital OR, military C2, logistics, and manufacturing?

## Key Insight

Traditional scheduling theory assumes workers are scarce, fixed, and expensive to context-switch. AI agent factories invert these assumptions: workers are cloneable (spawn N identical agents), cost is continuous (not salaried but per-token), and spawn latency is sub-second. This creates a design space where patterns from hospital trauma teams, military parallel planning, logistics dispatch, and manufacturing constraint theory combine in novel ways — but also introduces failure modes (priority inversion, speculative waste, context-loss on preemption) that require purpose-built mitigations.

---

## 1. Speculative Parallel Execution

### The Core Tradeoff

Speculative execution runs multiple branches simultaneously, accepting wasted computation on discarded branches in exchange for reduced wall-clock time. The decision framework is:

```
speculate_when: E[cost_parallel] < E[cost_sequential]
where:
  E[cost_parallel]  = N * cost_per_agent * E[branch_duration] + merge_overhead
  E[cost_sequential] = E[branch_duration] * E[branches_before_success] + switching_overhead
```

When spawn cost is near-zero and per-token cost is low relative to developer wait time, the breakeven point shifts dramatically toward speculation. The key variable becomes **merge/discard overhead** — the cost of reconciling or abandoning speculative results.

### Hospital Parallel Processing Protocols

Trauma team activation provides the most direct analogy. When a Level 1 trauma arrives, the hospital does not triage sequentially — it activates a full team simultaneously:

- **Airway specialist** secures the airway
- **Circulation specialist** establishes IV access and manages hemorrhage
- **Imaging tech** prepares portable X-ray
- **Lab tech** draws blood for cross-match
- **Scribe** documents in real time

All operate in parallel under a **team leader** who coordinates but does not perform procedures. The team leader's role maps to an orchestrator agent: they maintain situational awareness, resolve conflicts between parallel workers (e.g., "imaging needs the patient still, but circulation needs to roll them"), and make discard decisions ("cancel the CT, we're going straight to OR").

Key insight: trauma teams use **role-based parallelism** (each specialist has a pre-assigned domain) rather than **speculative parallelism** (trying multiple approaches to the same problem). This distinction matters for AI factories:

| Pattern | When to use | AI factory analog |
|---------|-------------|-------------------|
| Role-based parallel | Tasks are independent sub-problems | Lint + test + review running concurrently on the same patch |
| Speculative parallel | Uncertain which approach will succeed | Try 3 different fix strategies for a failing test |
| Hedged parallel | Want fastest result, all approaches valid | Send same prompt to 3 model tiers, take first acceptable response |

### Military Parallel Planning and Branches/Sequels

The US Army's Military Decision Making Process (MDMP) uses **parallel planning** to give subordinate units maximum preparation time. Rather than waiting for the commander's complete order, subordinate staffs begin planning on a **warning order** (WARNO) that communicates intent and likely missions. When the full order arrives, they adjust rather than start from scratch.

**Branches** are contingency plans for decision points: "if the enemy counterattacks from the north, execute Branch Alpha." **Sequels** are follow-on operations planned before the current phase completes. A **FRAGPLAN** (fragmentary plan) is a pluggable planning component that can be assembled with other fragments to rapidly construct a complete plan.

Translation to AI agent scheduling:

- **Warning orders** = pre-loading context and beginning analysis before a definitive task assignment. When sprint planning identifies likely next work, agents can begin research speculatively.
- **Branches** = speculative execution with pre-defined merge criteria. "If approach A fails tests, switch to pre-computed approach B without re-analyzing the problem."
- **Sequels** = pipeline stages where downstream agents begin preparing (loading context, reading files) while upstream agents are still executing.
- **FRAGPLANs** = composable partial solutions. Agent produces a validated code change for module X; orchestrator assembles it with changes from other agents into a complete deliverable.

### Triggers for Speculative Execution

Based on cross-domain analysis, speculation should fire when:

1. **High uncertainty, bounded cost**: The problem has multiple plausible approaches and the cost of running N agents is less than the expected sequential cost. Example: a bug with 3 likely root causes — spawn 3 agents to investigate simultaneously.
2. **Time-critical path**: The task is on the critical path and developer is blocked. Even a 2x cost multiplier is justified if it halves wall-clock time.
3. **Low merge complexity**: The speculative branches produce results that are easy to evaluate and merge/discard. Code patches are ideal (test suite is the oracle). Architectural decisions are poor candidates (no automated merge criterion).
4. **Historical branch-miss rate is high**: If past similar tasks required 2+ attempts, speculate on the first attempt.

### Merge/Discard Logic

- **First-past-the-post**: Take the first branch that passes acceptance criteria (tests pass, linter clean). Discard all others. Simple, works for hedged execution.
- **Best-of-N with evaluation**: Run all branches to completion, score each (test coverage, code quality, token cost), select best. Higher cost but better outcomes for complex tasks.
- **Cascading fallback**: Run branch A. If it fails within T seconds, start branch B (which has been pre-loading context). Hybrid between speculative and sequential.
- **Ensemble merge**: Multiple branches each contribute partial solutions that are combined. Rare for code changes, but applicable to research tasks (each agent explores a different documentation source).

---

## 2. Block Scheduling vs. Dynamic Auction

### Hospital OR Scheduling

Hospital operating rooms face a scheduling problem strikingly similar to AI agent factories: expensive shared resources (ORs / model inference capacity), heterogeneous task durations (surgeries / coding tasks), urgent interrupts (emergency cases / production incidents), and the need to balance utilization against responsiveness.

**Block scheduling** reserves specific OR time for specific surgeons/services. A cardiac surgeon gets OR 3 every Tuesday 7am-3pm. Benefits:
- Predictable capacity for the surgeon's practice
- Equipment specialization (robotic equipment stays in one room)
- Surgeon clusters cases efficiently, not racing between office and OR

**Open scheduling** makes all ORs available first-come-first-served. Benefits:
- Better accommodation of urgent/emergent cases
- More consistent utilization across the day
- No wasted block time when a surgeon under-utilizes their allocation

**The consensus**: a hybrid model where 75-85% of capacity is block-scheduled and 15-25% remains open for urgent cases and block overflow. Block time has a **release policy**: if a surgeon hasn't filled their block by a deadline (e.g., 72 hours before), the time is released to the open pool.

### Translation to AI Agent Factories

| Hospital concept | AI factory analog |
|-----------------|-------------------|
| Block time | Reserved agent capacity per project/priority tier |
| Open scheduling | Global pool of agents available for any task |
| Release time | If a project hasn't queued work by T, its reserved capacity returns to the pool |
| Emergency OR | Dedicated incident response capacity, never block-scheduled |
| Block utilization threshold | Minimum % of reserved capacity a project must use to retain its block |

**When spawn latency is near-zero, does block scheduling still make sense?**

Yes, but for different reasons than in hospitals. In hospitals, block scheduling reserves physical space. In AI factories, it reserves:

1. **Context continuity**: An agent that has been working on Project X has loaded context (codebase understanding, recent changes, test patterns). Reserving capacity means this context persists rather than being discarded and rebuilt.
2. **Rate limit headroom**: API rate limits are shared. Block scheduling guarantees a project won't be starved of inference capacity during peak usage.
3. **Cost accounting**: Reserved capacity enables predictable per-project cost budgets.
4. **Priority guarantee**: A P0 production incident should never wait behind a P3 refactoring task for agent capacity.

**The near-zero-spawn advantage**: Unlike hospital ORs, unused AI capacity has zero holding cost (you don't pay for agents that aren't running). This means the **release time** mechanism can be much more aggressive — release unused capacity after minutes, not hours. The hybrid model shifts to perhaps 40-60% reserved (for context continuity and priority guarantee) and 40-60% dynamic, because the cost of spawning into the dynamic pool is negligible.

### Airline Reserve Crew as a Model

Airlines maintain **reserve crews** — pilots and flight attendants on standby who can be activated when scheduled crew are unavailable due to illness, delays, or regulatory rest requirements. Reserve crew are positioned based on predictive analytics about where disruptions are most likely.

AI factory analog: maintain a pool of **warm agents** with pre-loaded context for the most likely next tasks. When a task arrives, a warm agent can begin immediately rather than spending time on context loading. The cost is the pre-loading computation, which is small relative to the time saved on critical-path work.

---

## 3. Commander's Intent and Mission-Type Orders

### Auftragstaktik

The German military doctrine of Auftragstaktik (mission-type tactics) specifies **what** to achieve and **why**, leaving **how** to the subordinate commander. The key elements:

1. **Commander's intent**: Broad enough to permit initiative, specific enough to align effort. "Seize the bridge by dawn to enable the main body's crossing" — not "advance along Route Alpha at 0300, clear buildings 1-4, then..."
2. **Mutual trust**: The commander trusts subordinates to make good decisions. Subordinates trust the commander's intent is well-reasoned.
3. **Freedom of action within bounds**: Subordinates may violate specific guidance if it serves the intent. A subordinate who discovers the bridge is destroyed may seize an alternative crossing point without asking permission.
4. **Decentralized execution**: Allows faster decision-making at the point of action, freeing higher leadership to focus on strategy.

### Application to AI Agent Delegation

Current AI agent orchestration tends toward **Befehlstaktik** (detailed-order tactics): the orchestrator specifies exact files to edit, exact tests to run, exact commit messages. This creates brittleness — when conditions change (a file has been refactored, a test framework has been updated), the agent either fails or asks for new instructions.

**Intent-based delegation** for AI agents:

```
Intent: "Make the user dashboard load in under 200ms on p95.
         Currently it's 1.2s. The bottleneck is likely the
         N+1 query pattern in the activity feed, but investigate
         before assuming."

Bounds: "Don't change the public API contract. Don't add new
         dependencies without approval. Keep changes under 500
         lines to maintain reviewability."

Success criteria: "p95 latency < 200ms on the staging benchmark
                   suite. All existing tests pass. No new N+1
                   queries introduced (checked by bullet_train gem)."
```

vs. procedural delegation:

```
1. Open app/models/activity.rb
2. Add `includes(:user, :project)` to the `recent` scope
3. Run `bundle exec rspec spec/models/activity_spec.rb`
4. If tests pass, commit with message "perf: eager-load activity associations"
```

The intent-based approach enables the agent to:
- Discover the actual bottleneck (maybe it's not N+1 but a missing index)
- Choose the best fix strategy (eager loading, caching, query restructuring)
- Adapt when conditions differ from expectations
- Make intermediate decisions without round-tripping to the orchestrator

### Implications for Resource Allocation

Intent-based delegation changes allocation because agents become **self-directing within bounds**. This means:

- **Agents may self-parallelize**: An intent-driven agent investigating a performance problem might spawn sub-agents to profile different code paths simultaneously.
- **Work duration becomes less predictable**: Procedural tasks have bounded duration. Intent tasks may take 5 minutes or 2 hours depending on what the agent discovers.
- **Orchestrator role shifts**: From detailed scheduler to strategic allocator. The orchestrator assigns intents to agents, monitors progress via checkpoints, and intervenes only when an agent exceeds its bounds or stalls.
- **Checkpoint-based monitoring replaces step-tracking**: Instead of "agent completed step 3 of 7", the orchestrator checks "agent has reduced p95 latency from 1.2s to 400ms, still working toward 200ms target."

---

## 4. Logistics Dispatch Patterns

### Dynamic Re-routing

Modern logistics dispatch systems continuously reoptimize routes as conditions change: new orders arrive, traffic patterns shift, a vehicle breaks down, a customer cancels. The key mechanisms:

1. **Periodic reoptimization**: At fixed intervals (every 5 minutes), recompute optimal assignments given current state.
2. **Event-driven reoptimization**: Triggered by significant events (new high-priority order, vehicle failure, major traffic incident).
3. **Continuous reoptimization**: Ongoing real-time adjustment — the system is always computing the next-best state.

For AI agent factories, **event-driven reoptimization** is the most applicable pattern. Periodic reoptimization adds unnecessary latency when the system state is stable, and continuous reoptimization is computationally wasteful. Events that should trigger re-allocation:

- A higher-priority task arrives
- An agent fails or stalls
- An agent completes early, freeing capacity
- External dependency changes (upstream PR merged, API deployed)
- Cost threshold exceeded on a running task

### Preemption of Lower-Priority Tasks

Logistics systems preempt lower-priority deliveries when urgent orders arrive: a vehicle carrying routine packages is rerouted to pick up a medical supply shipment. The preempted packages are reassigned to another vehicle or delayed.

AI agent preemption has a unique challenge: **context loss**. When a vehicle is rerouted, the packages don't lose their addresses. When an agent is preempted, its accumulated context (understanding of the codebase, partially formed solution, debugging hypotheses) may be lost unless explicitly checkpointed.

**Preemption protocol for AI agents:**

1. **Checkpoint before preemption**: The preempted agent writes a structured summary of its current state — what it has learned, what it has tried, what it suspects, what files it has modified.
2. **Context handoff**: When the preempted task is resumed (possibly by a different agent), the checkpoint is loaded as initial context, avoiding re-discovery.
3. **Preemption cost accounting**: Track the wasted computation from preemption. If preemption costs consistently exceed the priority benefit, the scheduling policy is too aggressive.
4. **Preemption levels**: Not all preemption is full stop. Options include:
   - **Hard preempt**: Kill immediately, checkpoint what's available
   - **Soft preempt**: Complete current sub-task (e.g., finish the current file edit), then yield
   - **Throttle**: Reduce the preempted agent's inference rate rather than stopping it

### Pickup-and-Delivery Sequencing

The Pickup and Delivery Problem (PDP) involves vehicles that must pick up items at one location and deliver them to another, with constraints on capacity, time windows, and sequencing (pickup must precede delivery).

AI agent analog: tasks have **dependencies** (must read codebase before writing fix), **handoff points** (one agent's output is another's input), and **capacity constraints** (model context window limits how much an agent can hold).

The PDP insight for AI factories: **sequence tasks to minimize context re-loading**. If Agent A needs to understand modules X and Y, and there are tasks touching both modules, assign them to Agent A sequentially rather than splitting them across agents. This is the AI equivalent of minimizing empty vehicle miles.

---

## 5. Manufacturing Constraint Theory (DBR)

### Drum-Buffer-Rope for AI Factories

In Goldratt's Theory of Constraints, the system's throughput is limited by its constraint (bottleneck). Drum-Buffer-Rope (DBR) manages this by:

- **Drum**: The constraint sets the pace. Everything else subordinates to it.
- **Buffer**: A time/work buffer protects the constraint from starvation.
- **Rope**: A signal that releases new work into the system at the rate the constraint can consume it.

### Identifying the Constraint

In an AI agent factory, the constraint shifts depending on the workload:

| Scenario | Constraint | Implication |
|----------|-----------|-------------|
| High parallelism, many agents | Model inference API rate limits | Buffer: pre-compute prompts; Rope: admission control on new agents |
| Complex tasks, few agents | Context window / reasoning quality | Buffer: pre-load context; Rope: limit task complexity per agent |
| Review-heavy workflow | Human review bandwidth | Buffer: queue reviewed-and-ready work; Rope: don't start new work faster than reviews complete |
| Integration-heavy | Test/CI infrastructure | Buffer: batch test runs; Rope: limit concurrent PRs to CI capacity |

### DBR Applied to Model Inference as Constraint

When model inference is the bottleneck:

**Drum**: The inference API's throughput (requests per minute, tokens per second) sets the pace for all work.

**Buffer**: Maintain a queue of ready-to-execute prompts upstream of the inference call. This means:
- Pre-load file contents and context before the agent needs to reason about them (using cheaper operations like file reads)
- Pre-compute prompt templates so the agent's "think" step is the only inference call
- Cache repeated inference patterns (e.g., "explain this function" results for commonly-referenced code)

**Rope**: Control work-in-progress to match inference throughput:
- If 10 agents each need 5 inference calls per minute but the API allows 30 RPM, only 6 agents should run simultaneously
- The remaining 4 should be in "pre-load" state, building their context buffers
- When a running agent completes, a pre-loaded agent takes its slot immediately (near-zero swap time because context is already built)

### WIP Limits and Kanban Analogy

Kanban's WIP limits serve the same function as DBR's Rope: they prevent overloading the system. For AI agent factories:

- **Per-stage WIP limits**: Limit how many tasks can be in "agent working" vs. "awaiting review" vs. "in CI" at any time
- **Feedback signal**: When "awaiting review" hits its WIP limit, the system stops starting new agent work and instead surfaces review requests
- **Constraint identification**: The stage that consistently hits its WIP limit is the constraint. Focus improvement effort there.

### Subordinating Non-Constraints

The corollary of DBR: non-constraint resources should have spare capacity. If model inference is the constraint, don't optimize for 100% utilization of code review bandwidth or CI infrastructure — keep them at 70-80% so they never block the constraint.

For AI factories, this means:
- If inference is the constraint, keep more reviewers available than strictly necessary
- If human review is the constraint, let agents idle rather than generating more unreviewed work
- Never optimize a non-constraint at the expense of the constraint's throughput

---

## 6. Priority Inversion, Starvation, and AI-Native Failure Modes

### Classical Priority Inversion

The Mars Pathfinder incident (1997) is the canonical example: a high-priority data bus task was blocked by a low-priority meteorological task holding a shared mutex, while medium-priority tasks ran freely — inverting the intended priority order. The fix was enabling **priority inheritance** on the mutex: the low-priority task temporarily inherits the high-priority task's priority while holding the shared resource.

### Priority Inversion in AI Agent Factories

AI factories face analogous inversions:

1. **Shared resource inversion**: A P1 task needs the test suite, but a P3 task is running a long test suite execution. The P1 task waits behind the P3 task's resource hold.
   - **Fix**: Priority-aware resource queuing. When a higher-priority task needs a resource held by a lower-priority task, either preempt the lower-priority task or escalate its resource access to complete faster.

2. **Context inversion**: A P1 task needs an agent with Project X context, but all Project X-experienced agents are working on P3 tasks. Spawning a new agent for P1 requires expensive context loading.
   - **Fix**: Maintain a "context registry" mapping agents to their loaded context. When a high-priority task arrives, preempt the lowest-priority agent with matching context rather than spawning cold.

3. **Review queue inversion**: P1 agent output waits in the same review queue as P3 output. If reviewers process FIFO, P1 work is delayed by accumulated P3 work.
   - **Fix**: Priority-aware review queues. Simple but often overlooked.

4. **Cascade inversion**: A P1 task depends on a P3 task's output (e.g., P1 feature needs a P3 refactoring to land first). The P3 task runs slowly because of its low priority, blocking the P1 task.
   - **Fix**: **Dependency-aware priority promotion** — when a high-priority task depends on a lower-priority task, the dependency's effective priority is promoted to match. This is directly analogous to priority inheritance.

### Starvation Prevention

Starvation occurs when low-priority work never runs because high-priority work continuously arrives. Classical solutions:

1. **Aging**: Gradually increase the priority of waiting tasks. A P3 task that has waited 4 hours gets promoted to P2, then P1 after 8 hours.
2. **Reserved slots**: Guarantee that N% of capacity is always available for low-priority work. Even during peak high-priority load, at least 1-2 agents work on P3 tasks.
3. **Batch windows**: Designate specific time windows for low-priority work (e.g., overnight runs for technical debt reduction).
4. **Priority budgets**: Each priority level gets a guaranteed fraction of total capacity. P1 gets up to 50%, P2 gets 30%, P3 gets 20%. Within each band, tasks compete normally.

### AI-Native Failure Modes

Beyond classical priority issues, AI agent factories have unique failure modes:

1. **Speculative waste cascade**: Speculative execution spawns N agents. Each discovers it needs to speculate further, spawning N more. Cost grows exponentially. **Fix**: Speculation depth limits and cumulative cost caps.

2. **Context drift**: An agent works on a task for 30 minutes, but 10 minutes in, another agent merged a conflicting change. The first agent's remaining work is based on stale state. **Fix**: Event-driven staleness checks — subscribe to relevant file-change events and trigger revalidation.

3. **Warm-agent staleness**: Agents pre-loaded with context for expected tasks become stale if the codebase changes before the task arrives. **Fix**: Lightweight freshness checks before dispatching to a warm agent. If staleness exceeds a threshold, re-load context.

4. **Review bottleneck starvation**: Agents produce work faster than humans can review it. The review queue grows unboundedly, and no agent output reaches production. This is a variant of the manufacturing constraint problem. **Fix**: Apply DBR — the review queue is the Drum, and the Rope limits agent work-in-progress to match review throughput.

5. **Cost runaway on intent-based tasks**: Intent-based delegation gives agents freedom to explore, but exploration is open-ended. An agent investigating a performance problem might profile 50 endpoints when only 3 are relevant. **Fix**: Budget envelopes (max tokens, max wall-clock time) per intent, with mandatory checkpoint-and-approval at budget thresholds.

6. **Herd behavior**: Multiple agents independently decide to work on the same high-value task (e.g., all detect the same failing test and try to fix it). **Fix**: Centralized task claiming with lease-based locks. An agent must claim a task before starting, and the claim expires if the agent doesn't heartbeat.

---

## 7. Work Stealing for Load Balancing

### The Pattern

Work stealing (Blumofe and Leiserson, 1999) is a decentralized load-balancing algorithm: each processor maintains a local deque of tasks. When a processor's deque is empty, it randomly selects another processor's deque and steals a task from the top. This minimizes coordination overhead — no central scheduler is needed, and load balancing only happens when a processor is idle.

### Application to AI Agents

Work stealing translates well when agents are organized into project-specific pools:

- Each project maintains a task queue (its deque)
- Agents assigned to a project pull from their project's queue
- When a project's queue is empty, its agents "steal" tasks from other projects' queues
- Stealing preference order: same-codebase projects first (context reuse), then any project

The advantage over centralized scheduling: reduced orchestrator bottleneck. The orchestrator only needs to assign tasks to project queues, not to individual agents. Agents self-balance.

The risk: stolen tasks may require context the stealing agent lacks. Mitigation: tasks in the queue are tagged with context requirements, and stealing agents check compatibility before taking a task.

---

## Synthesis: Design Recommendations for Demarch

1. **Hybrid block/dynamic scheduling** with aggressive release times (minutes, not hours). Reserve 40-60% of capacity for priority tiers, keep 40-60% in the dynamic pool. Near-zero spawn cost makes the dynamic pool cheap to maintain.

2. **Intent-based delegation** for complex tasks, procedural delegation for mechanical tasks. The orchestrator classifies tasks by uncertainty and delegates accordingly. High-uncertainty tasks get commander's intent; low-uncertainty tasks get step-by-step instructions.

3. **Speculative execution with cost caps** for tasks on the critical path with high uncertainty. Use first-past-the-post merge for speed, best-of-N for quality. Limit speculation depth to prevent cascade waste.

4. **DBR with inference as the default drum** — buffer upstream work (pre-load context, pre-compute prompts), rope downstream admission (limit WIP to inference throughput). Shift the drum identification when the constraint changes (e.g., to human review during review-heavy phases).

5. **Priority inheritance for dependencies** — when a high-priority task depends on a lower-priority task, promote the dependency. Combined with aging for starvation prevention and reserved capacity slots for low-priority work.

6. **Checkpoint-based preemption** — never hard-preempt without checkpointing. Context is the most expensive asset in an AI agent factory (measured in tokens spent understanding the problem). Losing it to preemption is the equivalent of throwing away half-finished surgical prep.

7. **Event-driven re-allocation** rather than periodic or continuous. Reoptimize assignments when significant events occur (task completion, failure, new high-priority arrival, external dependency change).

---

## Sources

- [Operating Room Block Scheduling vs Open Scheduling](https://hospitalmedicaldirector.com/operating-room-block-scheduling-versus-open-scheduling/)
- [Comprehensive Review on OR Scheduling and Optimization](https://link.springer.com/article/10.1007/s12351-024-00884-z)
- [Block Time Utilization in Operating Rooms](https://www.qventus.com/resources/blog/block-time-utilization-in-operating-rooms-how-to-identify-areas-of-improvement-and-increase-utilization/)
- [Impact of Block Scheduling and Release Time on OR Efficiency](https://www.researchgate.net/publication/266673395_The_Impact_of_Block_Scheduling_and_Release_Time_on_Operating_Room_Efficiency)
- [Trauma Care Principles - NCBI](https://www.ncbi.nlm.nih.gov/books/NBK547757/)
- [Performance and Assessment of Hospital Trauma Teams](https://pmc.ncbi.nlm.nih.gov/articles/PMC3017008/)
- [Process Modeling of ABCDE Primary Survey in Trauma Resuscitations](https://pmc.ncbi.nlm.nih.gov/articles/PMC9273801/)
- [Mission-Type Tactics (Auftragstaktik) - Wikipedia](https://en.wikipedia.org/wiki/Mission-type_tactics)
- [Mission Command - Wikipedia](https://en.wikipedia.org/wiki/Mission_command)
- [Auftragstaktik Leads to Decisive Action - USNI Proceedings](https://www.usni.org/magazines/proceedings/2025/may/auftragstaktik-leads-decisive-action)
- [Army Planning and Orders Production - FM 5-0](https://www.elon.edu/assets/docs/rotc/FM%205-0%20Army%20Planning%20and%20Orders%20Production%20.pdf)
- [FRAGPLAN - Wikipedia](https://en.wikipedia.org/wiki/Fragplan)
- [Dynamic Vehicle Routing and Dispatching - Springer](https://link.springer.com/chapter/10.1007/978-1-4615-5755-5_5)
- [Stochastic Dynamic Vehicle Routing Review](https://www.mdpi.com/2227-7390/12/1/28)
- [Multi-Depot Pickup and Delivery VRP](https://www.sciencedirect.com/science/article/abs/pii/S095219762401858X)
- [Drum Buffer Rope - Velocity Scheduling](https://www.velocityschedulingsystem.com/blog/drum-buffer-rope/)
- [Theory of Constraints 105: DBR - Forte Labs](https://fortelabs.com/blog/theory-of-constraints-105-drum-buffer-rope/)
- [Theory of Constraints and Kanban](https://kanbantool.com/kanban-guide/theory-of-constraints)
- [Theory of Constraints in Agile](https://extremeuncertainty.com/theory-constraints-agile/)
- [Aging (Scheduling) - Wikipedia](https://en.wikipedia.org/wiki/Aging_(scheduling))
- [Starvation and Aging in Operating Systems](https://www.geeksforgeeks.org/operating-systems/starvation-and-aging-in-operating-systems/)
- [Priority Inversion - Wikipedia](https://en.wikipedia.org/wiki/Priority_inversion)
- [Mars Pathfinder Priority Inversion - Cornell](https://www.cs.cornell.edu/courses/cs614/1999sp/papers/pathfinder.html)
- [Mars Pathfinder Priority Inversion Report - Chalmers](https://www.cse.chalmers.se/~risat/Report_MarsPathFinder.pdf)
- [Work Stealing - Wikipedia](https://en.wikipedia.org/wiki/Work_stealing)
- [Work Stealing: Load-balancing for Compute-Heavy Tasks](https://stack.convex.dev/work-stealing)
- [Reliable Reserve-Crew Scheduling for Airlines](https://www.sciencedirect.com/science/article/pii/S1366554523002715)
- [Airline Crew Scheduling: Models and Algorithms](https://www.sciencedirect.com/science/article/pii/S2192437620300820)
- [Parallel Speculative Execution for Mobile GUI Agents](https://dl.acm.org/doi/10.1145/3737902.3768356)
- [Parallelization: Optimizing AI Agent Performance](https://medium.com/@danielibisagba/parallelization-optimizing-ai-agent-performance-to-break-free-from-sequential-execution-9aaea588eb0b)
- [Multi-Agent Orchestration Patterns 2026](https://www.ai-agentsplus.com/blog/multi-agent-orchestration-patterns-2026)
- [AI Agent Orchestration - Deloitte](https://www.deloitte.com/us/en/insights/industry/technology/technology-media-and-telecom-predictions/2026/ai-agent-orchestration.html)

<!-- flux-research:complete -->
