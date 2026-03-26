# Work Decomposition Primitives for AI Agent Factories

Research into what existing work-tracking systems (software PM tools, manufacturing MES, VFX production, military C2, logistics dispatch, hospital OR scheduling) assume about work decomposition, and what structural changes are needed when the "worker" is an LLM agent operating at $0.003/token rather than $80/hour.

## 1. Granularity and Cognitive Load Assumptions

### What existing tools assume

Every major project management tool embeds assumptions about human cognitive capacity into its hierarchy primitives:

**Jira (Epic > Story > Subtask):** Stories are sized to fit a single sprint (1-2 weeks), with subtasks representing 2-8 hour chunks. The standard guidance is "only use subtasks for complex stories with distinct steps or handoffs." The implicit cognitive model is that a human can hold one story's context in working memory and needs subtasks only when handoff boundaries or multi-step coordination are involved. Teams that go deeper than 3 levels consistently report confusion navigating the hierarchy.

**Linear (flat issues, cycles, projects):** Linear deliberately rejected deep hierarchy. Its design philosophy is "opinionated simplicity" -- issues are flat, triage is mandatory, and cycles replace sprints. The implicit bet: hierarchy depth correlates with organizational overhead, not useful structure. Linear's triage step (new issues must be explicitly accepted or declined) is a cognitive load reducer that maps well to AI agent intake.

**Asana (tasks > subtasks, up to 5 levels):** Asana technically supports 5 nesting levels but explicitly recommends against going past 1 level of subtasks. Their reasoning: subtasks don't appear in Timeline or Calendar views, making deep nesting invisible to coordination surfaces. The practical cap is 2 levels.

**Shortcut (Milestone > Epic > Story):** Three clean levels with Stories as the atomic unit. Milestones represent outcomes (OKRs, releases), Epics represent coordinated efforts, Stories represent individual deliverables.

**Monday.com:** Board-centric with items and subitems. Essentially 2 levels. The flexibility is in views and automations, not hierarchy depth.

### How granularity must shift for AI agents

The fundamental economic shift: a human developer costs ~$80/hour and takes 4-8 hours per story. An AI agent costs $3-13 per task (source: exe.dev cost analysis, Devin performance data). This creates three structural pressures:

**1. Smaller atomic units are economically viable.** When a task costs $5 instead of $500, the overhead of creating and tracking it becomes the dominant cost. A human story ("implement user authentication") might decompose into 50 agent-sized tasks ("add password hash column to users table", "write bcrypt comparison function", "add login route handler"). The ratio is roughly 10:1 to 50:1 more tasks per equivalent human work unit.

**2. Context window replaces cognitive load as the binding constraint.** Human stories are sized to fit in working memory (~7 items). Agent tasks must be sized to fit in context windows while avoiding the quadratic cost curve. The exe.dev analysis shows cache reads dominate cost by 27,500 tokens, reaching 87% of total cost by conversation end. This means agent tasks should be sized to complete in under ~30,000 tokens of context accumulation -- roughly 15-25 tool calls. Anthropic's own multi-agent research found that token usage explained 80% of performance variance.

**3. Task descriptions must be machine-parseable specifications, not human-readable narratives.** A Jira story like "As a user, I want to reset my password so I can regain access to my account" encodes intent for a human to interpret. An agent task needs: target files, expected inputs/outputs, verification commands, and explicit boundary conditions.

### Recommended primitive sizing

| Level | Human Analog | Agent Sizing | Token Budget |
|-------|-------------|-------------|-------------|
| Objective | Epic / Milestone | Outcome with acceptance gate | N/A (coordination only) |
| Work Unit | Story | 15-25 tool calls, single concern | 20,000-40,000 tokens |
| Step | Subtask | Single file edit + verify | 3,000-8,000 tokens |

Devin's performance data validates this: tasks with "clear, upfront requirements and verifiable outcomes that would take a junior engineer 4-8 hours" achieve a 67% merge rate. Ambiguous scope or mid-task requirement changes cause failures.

## 2. Dependency Modeling

### How existing tools represent dependencies

**Jira:** Supports four link types: blocks/is-blocked-by, relates-to, duplicates/is-duplicated-by, clones/is-cloned-from. In practice, "blocks" is the only enforced dependency -- the rest are informational. Jira does not prevent starting blocked work; it only shows a visual indicator. There is no concept of parallel fan-out with merge gates.

**Linear:** Dependencies exist but are lightweight -- "blocking" and "blocked by" relationships. No DAG visualization, no enforcement. The philosophy is that smart developers route around blocks; the tool shouldn't prevent work.

**Manufacturing MES:** Uses routing sheets with forced sequencing. Operations must complete in order unless explicitly rerouted. Dependencies are physical -- you cannot paint before welding. MES systems enforce this through gate controls: "when a gate fails, the system should deny the action or place the operation/order/unit into a blocked/exception state."

**VFX Production (ShotGrid/Flow):** Dependencies are discipline-based: modeling must complete before texturing, rigging before animation, animation before lighting. The hierarchy is Show > Sequence > Shot > Task (per discipline) > Version. Each version goes through a multi-stage review pipeline (WIP > Internal Review > Tech Check > Client Review > Published). Dependencies are both sequential (pipeline order) and parallel (multiple shots in a sequence can progress independently).

**Military C2:** Uses the "one-third, two-thirds rule" -- senior planning consumes one-third of available time, leaving two-thirds for subordinate parallel planning. Dependencies are managed through commander's intent: subordinates understand the desired end state and can adapt execution independently. This is the closest existing model to AI agent autonomy.

**Hospital OR Scheduling:** Multi-resource constraint satisfaction. An operation depends on simultaneous availability of: OR room, surgeon, anesthesiologist, nurses, equipment, and downstream recovery bed. Dependencies are not just sequential but resource-concurrent -- multiple independent constraints must all be satisfied simultaneously.

**Logistics (Vehicle Routing Problem):** Precedence constraints (pickup before delivery) combined with time windows and capacity constraints. The VRP with time windows (VRPTW) is the closest analog to scheduling agent tasks with context window limits and API rate limits.

### New dependency types for AI agent factories

Existing dependency models assume expensive, scarce workers. When you can clone 50 workers instantly, new dependency patterns emerge:

**Speculative parallel execution.** Run N competing implementations of the same task, evaluate outputs, discard losers. Manufacturing has no analog (you don't build 5 copies of a part to pick the best one). The closest analog is film production's "takes" -- shoot the scene multiple times, select the best in editing. The key structural difference: AI takes cost tokens, not time, so speculation is viable when the evaluation function is cheap relative to execution.

**Fan-out-then-merge with conflict resolution.** Distribute subtasks across parallel agents, then merge results. This resembles the MapCoder architecture: retrieval agent > planning agent > N coding agents > debugging agent. The merge step is the hard part -- git merge conflicts, semantic contradictions, API contract violations. Manufacturing handles this through work-in-process inventory buffers; software needs semantic merge gates.

**Dependency on evaluation capacity, not execution capacity.** The bottleneck shifts from "can we do the work?" to "can we verify the work?" This creates a new dependency type: evaluation-blocked, where work is complete but awaiting quality assessment. VFX production already has this pattern (Version Pending Review, Tech Checks Pending, Client Pending Review).

**Context-dependency (shared knowledge).** Agent B needs information discovered by Agent A, but doesn't need Agent A to finish. This is a data dependency without a completion dependency. Military C2 handles this through situation reports (SITREPs) -- periodic broadcasts of discovered information that don't block the reporter.

### Recommended dependency primitives

```
hard-blocks:     A must complete before B can start (MES forced routing)
data-feeds:      B needs A's intermediate output, not A's completion (C2 SITREP)
resource-locks:  B needs exclusive access to a resource A currently holds (OR scheduling)
speculative:     A and B are competing solutions; evaluate and kill loser (film takes)
fan-merge:       A1..An execute in parallel; merge gate collects and reconciles (MapReduce)
eval-blocked:    work complete, awaiting quality gate (VFX version review)
```

## 3. Definition of Done and Acceptance Criteria

### What existing tools assume

All mainstream PM tools assume a human reads the output and makes a judgment call. Jira's Definition of Done is a checklist ("code reviewed, tests pass, documentation updated") verified by a person. Scrum.org explicitly distinguishes between acceptance criteria (story-specific, functional) and definition of done (team-wide, quality standards).

**The structural problem:** "code reviewed" requires human judgment. "Tests pass" is machine-verifiable but assumes someone wrote the tests. "Documentation updated" is qualitative.

### Machine-verifiable done-ness

Manufacturing MES provides the better model here. A work order's quality gate is not "someone looked at it" but "measured dimension X is within tolerance Y." First Pass Yield -- the percentage of units that pass quality control without rework -- is a hard metric.

For AI agent output, done-ness must be expressed as a conjunction of machine-checkable predicates:

**Deterministic gates (binary pass/fail):**
- Compilation succeeds
- Existing test suite passes (no regressions)
- Linter/formatter passes
- Type checker passes
- Generated tests achieve coverage threshold
- No new security vulnerabilities (SAST)

**Stochastic gates (probabilistic pass/fail):**
- LLM-as-judge scores output above threshold on rubric (Anthropic's multi-agent system uses this)
- Agent-as-judge with tool-augmented verification (emerging pattern from 2026 research: judges that can actually run code, inspect files, and verify claims rather than just reading text)
- Semantic diff review: changes are consistent with stated intent
- N-of-M agreement: multiple judge agents must concur

**The VFX model is instructive here.** ShotGrid's status pipeline (WIP > Internal Review > Tech Check > Client Review > Published > Final) separates functional review from technical review from stakeholder review. An AI factory should similarly separate:

1. **Self-check** (agent verifies its own output -- compilation, tests, lint)
2. **Technical gate** (automated verification -- integration tests, type checking, security scan)
3. **Semantic gate** (LLM judge evaluates correctness against spec)
4. **Acceptance gate** (human spot-check or automated approval based on confidence score)

### Confidence-based acceptance

Hospital OR scheduling uses probabilistic duration estimates (predicted surgery time with variance). AI agent factories need analogous confidence scoring:

- **High confidence (>0.9):** auto-merge after deterministic gates pass
- **Medium confidence (0.7-0.9):** LLM judge review, auto-merge if judge agrees
- **Low confidence (<0.7):** human review required
- **Unknown confidence:** quarantine (manufacturing model -- see Section 6)

## 4. Work Hierarchy Depth and Shape

### Depth patterns across domains

| Domain | Hierarchy Depth | Levels | Shape |
|--------|----------------|--------|-------|
| Jira (typical) | 3 | Epic > Story > Subtask | Bushy (many stories per epic) |
| Linear | 2 | Project > Issue | Flat |
| Shortcut | 3 | Milestone > Epic > Story | Balanced |
| Asana (recommended) | 2 | Task > Subtask | Flat |
| VFX (ShotGrid) | 6+ | Show > Episode > Sequence > Shot > Task > Version | Deep, narrow |
| Manufacturing MES | 4 | Production Order > Work Order > Operation > Step | Linear chain |
| Military C2 | 5+ | Campaign > Operation > Phase > Mission > Task | Tree with delegation |
| Film Production | 6+ | Production > Sequence > Scene > Shot > Take > Revision | Deep with branching at "Take" |

### The depth-shape tradeoff

Deep hierarchies (VFX, military) work when:
- Each level has a distinct decision-maker or evaluation criteria
- Work at each level has different time horizons
- Failure at a low level can be locally contained without cascading upward

Flat hierarchies (Linear, Asana) work when:
- Workers are interchangeable and self-directing
- Coordination cost exceeds the value of structural organization
- Speed of iteration matters more than plan fidelity

### Optimal shape for AI agent factories

AI agents combine properties of both scenarios. They are interchangeable (clone instantly) but not self-directing (require explicit specifications). They operate at different time horizons (a 30-second subtask vs. a 2-hour feature) but failures cascade unpredictably.

**Recommended: 4 levels with branching at level 3.**

```
L1: Objective (human-defined goal, acceptance criteria, success metrics)
    |
L2: Work Package (decomposed plan, dependency graph, resource estimates)
    |
L3: Task (agent-executable unit, 15-25 tool calls, single concern)
    |--- speculative branch: Task variant A
    |--- speculative branch: Task variant B
    |
L4: Step (individual tool call or verification check, logged but not independently tracked)
```

**Why 4 and not 3 or 6:**
- 3 levels (Jira-style) conflates planning (L2) with execution (L3). When tasks cost $5 each, the planning layer must be explicit to avoid waste.
- 6 levels (VFX-style) creates coordination overhead that exceeds the cost of the work itself. VFX needs 6 levels because each level involves different human specialists. AI agents don't have specialization boundaries at every level.
- 4 levels with speculative branching at L3 captures the unique AI capability of parallel competing execution without adding hierarchy depth.

The VFX "Version" concept (multiple attempts at the same deliverable, each independently reviewable) maps directly to speculative task variants. The military "commander's intent" concept maps to L1 Objectives -- agents at L3 can make autonomous decisions as long as they serve the L1 intent.

## 5. Vestigial vs. AI-Native Metadata Fields

### Fields that become vestigial

| Human Field | Why Vestigial | Replacement |
|-------------|--------------|-------------|
| **Assignee (person)** | Agents are interchangeable; identity doesn't predict capability | `agent_profile` (model + tools + context config) |
| **Time estimate (hours)** | Agent work is measured in tokens, not hours; duration is seconds to minutes, not days | `token_budget` (max tokens before abort) + `estimated_cost` (dollars) |
| **Story points** | Relative complexity proxy for human planning poker | `complexity_class` (enum: trivial/standard/complex/research) based on file count, dependency depth, ambiguity score |
| **Sprint assignment** | Fixed-length iteration cadence for human teams | `batch_id` or `wave` (logical grouping for fan-out) |
| **Priority (P1-P5)** | Human attention is scarce; priority rations it | `execution_order` (topological sort of dependency DAG) + `value_weight` (for speculative execution budget allocation) |
| **Reporter** | Who noticed the issue | `origin` (human request, automated detection, agent-discovered) |
| **Watchers** | Humans who want notifications | `notification_rules` (programmatic conditions for human escalation) |
| **Labels/components** | Human categorization for filtering | `scope` (affected files/modules, machine-extracted) |

### Fields that need AI-native replacements

| AI-Native Field | Purpose | Analog |
|----------------|---------|--------|
| `context_hash` | Deterministic ID of the information an agent had when executing | Manufacturing lot number / traceability |
| `token_cost_actual` | Realized cost of execution | Manufacturing actual-vs-standard cost variance |
| `first_pass_yield` | Did the output pass all gates on first attempt? | Manufacturing FPY metric |
| `confidence_score` | Agent's self-assessed probability of correctness | No direct human analog; closest is surgical risk score |
| `verification_vector` | Which gates passed/failed and with what scores | VFX tech-check results |
| `rework_count` | Number of retry cycles | Manufacturing rework tracking |
| `parent_context` | What information was inherited from parent task | Military operations order (OPORD) lineage |
| `speculative_group` | Which tasks are competing variants | Film take number |
| `eval_cost` | Cost of verifying this output | Hospital diagnostic test cost |

### The "blocked" status transformation

In human tools, "blocked" means "a person needs to do something and hasn't." In an AI factory:
- **resource-blocked**: waiting for API rate limit, compute capacity, or exclusive file lock
- **data-blocked**: waiting for another task's output (hard dependency)
- **eval-blocked**: work complete, awaiting quality gate evaluation
- **budget-blocked**: would exceed allocated token budget
- **human-blocked**: requires human decision (the only true block)

The distinction matters because the first four can be automatically resolved by the orchestrator. Only the fifth requires the human interrupt that "blocked" implies in Jira.

## 6. Rework and Defect Routing: Manufacturing vs. Software

### How manufacturing MES handles failures

Manufacturing has a mature taxonomy for output that doesn't meet specification:

**Scrap:** The output is unsalvageable. The work order is closed with a scrap disposition code. Root cause is recorded (material defect, machine error, operator error). The item is destroyed or recycled. A new work order is created from scratch if the output is still needed.

**Rework:** The output is fixable. A rework work order is created that references the original. The item re-enters the production line at a specific operation step -- not from the beginning, but from the point where the defect can be corrected. Rework has its own routing (different steps than original production).

**Quarantine:** The output's status is uncertain. It is moved to a quarantine location for inspection. After inspection, it is dispositioned as either scrap or rework. Quarantine prevents defective output from entering the downstream pipeline.

**Use-as-is / Deviation:** The output doesn't meet specification but is acceptable for this specific use case. Requires explicit approval with documented justification.

### How software tools handle failures

Software PM tools have one mechanism: **reopen the ticket**. There is no distinction between "the approach was fundamentally wrong" (scrap) and "there's a small bug in the implementation" (rework). There is no quarantine -- partially-working code either gets merged or doesn't. There is no deviation -- code either passes tests or it doesn't.

### Which model fits AI agent output

Manufacturing's model is substantially more appropriate for AI agent output, because:

**1. Agent outputs have measurable defect types.** Like manufactured parts, agent code can fail in categorizable ways: compilation error (material defect), logic error (process defect), wrong files modified (routing error), style violation (cosmetic defect). Each type has different rework costs and strategies.

**2. Rework-from-midpoint is economically critical.** If an agent produces 90% correct output with one function wrong, scrapping and re-executing wastes the 90% that was correct. Manufacturing's approach of re-entering the production line at the specific failed operation maps to: give the agent back its prior context plus the specific failure, and ask it to fix only the failing part. This is dramatically cheaper than a fresh execution.

**3. Quarantine prevents cascade failures.** In a multi-agent factory, one agent's incorrect output can poison downstream agents. Manufacturing's quarantine -- hold the output, inspect it, then decide -- prevents this. Software's "reopen ticket" model has no quarantine; the bad output either blocks everything (if tests catch it) or silently propagates (if they don't).

**4. Use-as-is with documented deviation is a real category.** An agent might produce code that works but doesn't follow the team's naming convention. Manufacturing's "deviation with approval" is the right model -- accept the output with a documented exception rather than paying for a full rework cycle.

### Recommended defect routing for AI agent output

```
Agent output
    |
    v
[Deterministic Gates] -- fail --> classify defect
    |                                    |
    pass                          [compilation error] --> SCRAP (re-execute from scratch,
    |                                    |                  different approach likely needed)
    v                             [test regression] ----> REWORK (re-enter with failure context,
[Stochastic Gates]                       |                  fix specific function)
    |                             [style/lint] ---------> REWORK-MINOR (auto-fix, re-verify)
    |-- fail --> [confidence?]           |
    |              |                [wrong scope] ------> SCRAP (task spec was misunderstood)
    |              high: REWORK         |
    |              low: SCRAP      [partial success] ---> QUARANTINE (inspect, then
    |              unknown: QUARANTINE                     rework or accept-with-deviation)
    |
    pass
    |
    v
[ACCEPT] --> merge / publish
```

**Key difference from manufacturing:** In manufacturing, scrap means physical destruction. In an AI factory, "scrap" means "discard this output and re-execute, possibly with a different strategy." The agent's execution trace is preserved for root-cause analysis even when the output is discarded. This is closer to manufacturing's corrective action process than to its physical scrap process.

**Key difference from software:** Software "reopen" loses the defect classification and rework routing information. The manufacturing model preserves: what failed, why it failed, what the rework strategy is, and whether this defect type is trending upward (indicating a systemic problem with the task spec or agent configuration rather than a one-off failure).

## 7. Cross-Domain Synthesis: Design Principles

Drawing from all six domains, the following principles govern work decomposition primitives for an AI agent factory:

### From manufacturing MES
- **Forced routing with gates.** Don't let output proceed without passing quality checks. MES systems deny actions at failed gates rather than relying on humans to notice warnings.
- **First Pass Yield as the primary quality metric.** Track what percentage of agent tasks pass all gates on first execution. This is more actionable than "number of bugs found."
- **Rework routing is a first-class concept.** Distinguish scrap from rework from quarantine. Each has different cost profiles and orchestration strategies.

### From VFX production
- **Version everything.** Every agent output is a version with its own review pipeline. Multiple versions of the same deliverable can coexist and be independently evaluated.
- **Separate technical review from semantic review.** ShotGrid's split between "tech checks" (does it render correctly?) and "client review" (is it what was asked for?) maps directly to deterministic vs. stochastic quality gates.
- **Status granularity matters.** ShotGrid uses 15+ statuses across 5 review stages. "In progress" and "done" are insufficient for a system that needs to track where in the evaluation pipeline each output sits.

### From military C2
- **Commander's intent enables autonomous execution.** Agents need to understand the objective (L1), not just the task (L3). When an L3 task encounters an unexpected situation, the agent should be able to adapt within the bounds of L1 intent rather than blocking.
- **One-third/two-thirds rule for planning budgets.** Don't spend more tokens planning than executing. Anthropic's multi-agent research confirmed this: token usage (execution) explained 80% of quality variance, not plan sophistication.
- **Delegation with mission-type orders.** Tell agents what to achieve, not how to achieve it. Over-specified task descriptions constrain agent problem-solving and increase rework when the specified approach doesn't fit.

### From hospital OR scheduling
- **Multi-resource constraint satisfaction.** Agent tasks compete for: context window capacity, API rate limits, file locks, evaluation capacity, and human review bandwidth. Scheduling must satisfy all constraints simultaneously, not sequentially.
- **Probabilistic duration estimates.** Agent task duration is stochastic. Schedule with expected value plus variance, not fixed estimates.

### From logistics dispatch
- **Precedence + time windows + capacity.** The VRPTW model (pickup before delivery, within time windows, subject to vehicle capacity) maps to: data dependencies before consumption, within token budgets, subject to rate limits.
- **Skill-based routing.** Not all agents are equivalent. Route tasks to agent profiles (model + tools + context) that match task requirements, analogous to dispatching technicians with the right certifications.

### From software PM tools (what to keep)
- **Triage as an explicit step (Linear).** Not all work requests should become tasks. A triage gate prevents the factory from executing low-value or ill-defined work.
- **Flat-by-default with opt-in depth (Linear/Asana).** Start with minimal hierarchy. Add levels only when evaluation or coordination requires them. Most AI factory overhead comes from over-structured task hierarchies, not under-structured ones.
- **Cycle/batch as an execution boundary.** Linear's cycles and manufacturing's production batches both provide natural boundaries for measuring throughput and adjusting strategy.

---

*Research conducted 2026-03-19. Sources include practitioner documentation from Atlassian, Linear, Shortcut, Asana, Autodesk Flow Production Tracking (ShotGrid), U.S. Army Field Manuals, operations research literature on VRP and OR scheduling, Anthropic's multi-agent research engineering blog, Cognition AI's Devin performance review, and exe.dev's analysis of LLM agent cost curves.*

<!-- flux-research:complete -->
