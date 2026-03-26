# AI Factory Work Orchestration: Framework Design Patterns & Lessons

**Research Date:** 2026-03-19
**Scope:** Linear, Jira, Temporal, CrewAI, AutoGen, LangGraph, Kubernetes, Apache Airflow, Dagster, Restate

## Executive Summary

This document synthesizes orchestration patterns from six categories of frameworks: issue tracking (Linear, Jira), durable execution (Temporal, Restate), multi-agent AI (CrewAI, AutoGen, LangGraph), and data pipeline orchestration (Apache Airflow, Dagster). The goal is to extract design principles applicable to building an AI agent software factory orchestration system.

**Key Insights:**
- **Durable Execution** (Temporal, Restate): Task replay and state persistence are foundational; workflows should be deterministic and recoverable
- **Issue-Centric vs. Asset-Centric**: Linear/Jira model work as discrete issues; Dagster shows asset-lineage perspective valuable for dependency tracking
- **Agent Coordination Models**: CrewAI (role-based, hierarchical), LangGraph (state-machine graphs), AutoGen (conversational) represent three distinct delegation patterns
- **Scheduler Design**: Kubernetes demonstrates sophisticated resource allocation and priority preemption; analogous to agent availability and task prioritization
- **DAG Orchestration**: Airflow's task dependency model and Dagster's asset lineage both inform how to model task decomposition and data flow

---

## 1. Issue Tracking & Work Decomposition

### 1.1 Linear API: GraphQL-Based Issue Model

**Data Model Characteristics:**
- Issues, Projects, Cycles (sprints), and Dependencies are first-class entities
- GraphQL API enables flexible querying and mutation with real-time event webhooks
- Supports issue relations including dependencies between issues
- Cycles extend to include documents and links, supporting narrative context
- Recent improvements prioritize projects by membership, improving visibility

**Design Principles:**
- **GraphQL is a good fit for work decomposition APIs** — enables clients to request exactly what data they need
- **Webhooks for state change notification** — events include issue, comment, attachment, label, project, cycle, SLA mutations
- **Issue relationships separate from hierarchical containment** — dependencies, blockers, and duplicates are distinct relationship types
- **Cycles as organizational unit** — sprints/cycles group work with explicit begin/end semantics

**Relevant Patterns for AI Factory:**
- Use GraphQL for flexible work item querying across agents/sprints
- Separate task relationships (depends-on, blocks, duplicates) from hierarchy
- Support cycle-like concepts for agent task batches or sprint planning

---

### 1.2 Jira Workflow Automation: State Machines & Trigger-Condition-Action

**Automation Architecture:**
- Trigger-Condition-Action model: events trigger rules, conditions filter applicability, actions execute side effects
- Auto-assignment supports workload balancing (least-loaded agent) or role-based assignment
- Workflow transitions can be automated with post-functions and automation rules
- State transitions can copy values from related items, supporting hierarchical workflows

**Supported Actions:**
- Work item management: assignment, editing, cloning, transitions
- Communication: comments, email, Slack, Teams, SMS
- External integrations: web requests, branch creation (VCS), AWS, Azure, Ansible
- Lookup tables and variable creation for complex logic

**Design Principles:**
- **Declarative state machines reduce custom code** — define transitions, not implementation
- **Event-driven automation reduces manual intervention** — triggers can cascade
- **Role-based assignment as opposed to explicit assignment** — reduces management overhead
- **Integration patterns** — automation should bridge to communication and external systems

**Relevant Patterns for AI Factory:**
- Model task state transitions as declarative workflows
- Use triggers for agent task completion events
- Support auto-assignment to agents based on workload or specialization
- Integrate automation with logging, notifications, and external systems

---

## 2. Durable Execution & State Persistence

### 2.1 Temporal: Event History & Deterministic Replay

**Core Execution Model:**
- **Event History** — complete, immutable log of every step in workflow execution
- **Deterministic Replay** — workflows replay from event history on recovery, bypassing already-executed steps
- **Task Queues** — every step (workflow progression or activity completion) queued and distributed
- **State Persistence** — complete workflow state (local variables, progress) auto-saved at critical points

**Execution Guarantees:**
1. **Durability**: Tasks execute "effectively once and to completion" over seconds to years
2. **Reliability**: Fully recoverable after failure, with state persisted across outages
3. **Scalability**: Supports millions to billions of concurrent workflow executions

**Activities (External Tasks):**
- **At-Least-Once vs. At-Most-Once semantics** — configurable per activity
- **Retry Policies** — exponential backoff with duration limits (e.g., months)
- **Idempotency** — activity IDs and tokens ensure side effects execute exactly once
- **Start-To-Close Timeouts** — if exceeded, activity retried per policy
- **Completed activities not re-executed** — results reused even if workflow later fails

**Key Concepts:**
- **Commands & Awaitables** — workflows issue commands (e.g., call activity), wait on results
- **Batching** — commands batch until workflow "can no longer progress without a result"
- **Continue-As-New** — workflows chain themselves to handle load or long-running processes
- **Signals** — external events that can wake workflows or modify execution

**Design Principles:**
- **Deterministic execution is non-negotiable** — enables replay recovery
- **Events as source of truth** — rebuild state by replaying events
- **Side effects isolated to activities** — workflows contain only orchestration logic
- **Idempotency is essential** — activities must be replayable

**Relevant Patterns for AI Factory:**
- Persist task history as immutable event log
- Design agent workflows for deterministic replay recovery
- Isolate side effects (tool calls) from orchestration logic
- Support long-running task chains via continue-as-new pattern
- Implement idempotency tokens for agent task execution

---

### 2.2 Restate: Durable Execution as Code

**Workflow Model:**
- Write workflows as **regular functions** in your language; Restate SDK adds durability
- **WorkflowContext** provides operations that are automatically persisted
- Execution progress logged in persistent journal; recovery replays from journal

**State Management:**
- **Isolated per-workflow state** — K/V store per execution, default 1-day retention
- **Durable Promises** — asynchronous coordination without message queues
- **State Consistency** — K/V updates persisted with execution progress atomically

**Task Sequencing:**
- `ctx.run()` for durable steps
- `ctx.serviceClient()` for external service calls
- Native language constructs (loops, conditions) for parallelism and control flow

**Error Handling:**
- **Transient errors** — automatically retried with exponential backoff
- **Terminal errors** — explicitly thrown, halt retries
- **Saga patterns** — ordered rollback operations for compensation on failure
- **Configurable retry policies** — limits on attempts and total duration

**Design Principles:**
- **Workflows-as-Code** — no separate DSL, reduce impedance mismatch
- **Automatic journaling** — developers write normal code, framework adds durability
- **Transient vs. terminal errors** — distinguish recoverable from unrecoverable failures
- **Promises for async coordination** — avoid message queue complexity

**Relevant Patterns for AI Factory:**
- Implement agent task workflows as code rather than declarative DAGs
- Use journaling for automatic recovery without explicit checkpointing
- Support both transient (network) and terminal (invalid input) failure modes
- Use promise-like primitives for agent-to-agent signaling

---

## 3. Multi-Agent AI Orchestration

### 3.1 CrewAI: Role-Based Agent Coordination

**Architecture:**
- Agents assigned **specific roles** (Researcher, Writer, Reviewer, Manager, Worker)
- Each agent has defined **objectives, backstory, and specialized tools**
- Tasks explicitly assigned to agents; agents work autonomously on assigned work

**Task Allocation Models:**

**Sequential Process:**
- Tasks execute in definition order
- Each task assigned to specific agent
- No central coordinator

**Hierarchical Process:**
- **Manager Agent** coordinates and delegates
- Manager evaluates tasks, assigns to appropriate agents
- Manager validates outcomes before proceeding
- Tasks still execute sequentially despite hierarchical oversight
- Manager enabled via `process=Process.hierarchical` + `manager_llm="gpt-4o"`

**Agent Coordination & Delegation:**
- Agents can delegate to other agents if specialized assistance needed
- CrewAI orchestrates sub-task creation automatically
- Tools can be assigned at agent or task level
- Delegation disabled by default; requires explicit enablement

**Design Principles:**
- **Role-based expertise** — agents have specialized knowledge and tools
- **Explicit task assignment** — clear ownership reduces ambiguity
- **Hierarchical oversight through delegation** — manager validates before proceeding
- **Emulates corporate structures** — familiar mental model

**Relevant Patterns for AI Factory:**
- Define agent roles with backstories and tool specializations
- Support both sequential and hierarchical task allocation
- Enable agents to request specialist assistance via delegation
- Validate work quality through manager/coordinator oversight

---

### 3.2 LangGraph: State Machines & Dynamic Graph Topology

**Core Model:**
- Workflows modeled as **graphs** with nodes (functions) and edges (transitions)
- **State** is a shared mutable data structure (TypedDict, Pydantic model) capturing current snapshot
- **Nodes** are Python functions receiving state, performing computation, returning updated state
- **Edges** determine next node; can be conditional branches or fixed transitions

**State Management:**
- State immutable and checkpointed after every step
- Persisted via MemorySaver, SqliteSaver, PostgresSaver
- Enables automatic crash recovery

**Graph Topology Patterns (2026):**

**Hierarchical/Tree Architectures:**
- Supervisors manage sub-supervisors managing workers
- Recursion via subgraphs

**Dynamic Topology:**
- Workflows dynamically spawn nodes, insert branches, reconnect edges at runtime
- Enables emergent coordination from agent decisions

**Parallel Execution:**
- Explicit join/fork nodes for concurrent subgraph execution
- Subject to data dependencies

**Orchestrator-Worker Pattern:**
- Dynamically spawns and delegates subtasks
- Uses `Send` API for dynamic branching at runtime

**API Design:**
- `StateGraph(State).add_node(name, function).add_edge(source, target).add_conditional_edges(source, condition_fn)`
- `.compile()` validates structure and configures runtime (checkpointer, breakpoints, etc.)
- Nodes become active when receiving messages on incoming edges; remain inactive otherwise
- Execution proceeds in "super-steps" (iterations) where active nodes run, emit messages

**Design Principles:**
- **State as first-class citizen** — immutable snapshots enable recovery
- **Dynamic graphs** — topology can change at runtime based on decisions
- **Graph compilation** — validation and optimization separate from definition
- **Message-driven activation** — nodes idle until needed
- **Supersteps for determinism** — iterative rounds prevent thundering herd

**Relevant Patterns for AI Factory:**
- Model task dependencies as directed graphs with conditional branches
- Use immutable state snapshots for recovery
- Support dynamic workflow generation (spawn new task graphs)
- Implement hierarchical orchestration via subgraphs
- Use conditional edges for branching on task outcomes

---

### 3.3 AutoGen: Conversational Agent Groups

**Architecture:**
- Agents interact via **conversational group chat**
- Agents dynamically determine task allocation through dialogue
- No predefined role hierarchy or rigid node topology

**Coordination Model:**
- Agents have **conversation abilities** — interpret context, suggest next steps
- Agents adapt roles based on conversational context
- Workflow emerges from agent discussion

**Design Principles:**
- **Flexibility** — agents adapt to context rather than fixed roles
- **Narrative coherence** — conversation remains intelligible to humans
- **Dynamic role-play** — agents take on contextually appropriate roles

**Relevant Patterns for AI Factory:**
- Less suitable for deterministic task orchestration
- Better for open-ended problem-solving and ideation
- Could complement structured orchestration for validation/review loops

---

## 4. Kubernetes Scheduling: Resource Allocation & Priority

### 4.1 Scheduling Algorithm

**Two-Phase Process:**

1. **Filtering Phase:**
   - Eliminate nodes unsuitable for pod placement
   - Apply node affinity, pod affinity, taints/tolerations, resource constraints

2. **Scoring Phase:**
   - Assign scores to remaining nodes
   - Consider: resource utilization, pod affinity, node affinity, topology spread
   - Select highest-scoring node

**Bin-Packing Strategies (NodeResourcesFit plugin):**
- **MostAllocated** — score nodes by utilization; favor highly-allocated nodes (consolidates workload)
- **RequestedToCapacityRatio** — score based on ratio of requested to available capacity

**Design Principles:**
- **Two-phase design** — separate feasibility from optimization
- **Pluggable scoring** — different strategies for different workload patterns
- **Explicit constraints** — node affinity, taints/tolerations, resource requests

---

### 4.2 Priority & Preemption

**Pod Priority:**
- PriorityClass defines relative importance of pods
- Higher-priority pods can preempt (terminate) lower-priority pods
- Prevents resource starvation for critical workloads

**Preemption Logic:**
- Triggered when no node satisfies pod requirements
- Finds node where evicting lower-priority pods enables higher-priority pod to schedule
- Evicts pods, allowing preemptor to schedule

**Design Principles:**
- **Explicit priority values** — no hidden ordering
- **Preemption only when necessary** — avoids thrashing
- **Best-effort search** — finds reasonable eviction candidates, not globally optimal

**Relevant Patterns for AI Factory:**
- Model agent availability as node resources (capacity for concurrent tasks)
- Implement task priority levels to ensure critical work executes
- Support preemption for high-priority tasks (e.g., deadline-driven work)
- Use workload consolidation strategies (bin-packing) to optimize agent utilization
- Make resource requirements and constraints explicit

---

## 5. Data Pipeline Orchestration

### 5.1 Apache Airflow: Task-Centric DAGs

**DAG Model:**
- **Directed Acyclic Graph** represents workflow
- Encapsulates scheduling, tasks, dependencies, callbacks, operational parameters
- Tasks are Python functions; operators are task types

**Dependency Declaration:**
- Forward operators: `task_a >> task_b`
- Backward operators: `task_a << task_b`
- Explicit methods: `set_upstream()`, `set_downstream()`
- Complex patterns: `chain()` for sequential, `cross_downstream()` for many-to-many

**Trigger Rules (Conditional Execution):**
- `all_success` (default) — execute when all upstream succeed
- `all_done` — execute regardless of upstream success
- `one_success` — execute when at least one upstream succeeds
- `always` — execute unconditionally

**Branching:**
- `@task.branch` decorator — dynamically select execution paths
- Returns specific task IDs to follow

**Task Organization:**
- **TaskGroups** — hierarchical organization without changing execution semantics
- **Dynamic DAGs** — Python loops/functions generate task structures programmatically
- **@dag decorator** — wraps functions as DAG generators for parameterization

**Design Principles:**
- **DAG immutability** — structure known before execution
- **Operators as task abstraction** — reusable task types
- **Trigger rules for control flow** — avoid custom branching logic
- **Hierarchy for clarity** — TaskGroups don't affect semantics

**Relevant Patterns for AI Factory:**
- Represent agent workflows as DAGs with explicit task dependencies
- Use trigger rules to model conditional task execution
- Support parameterized workflow generation (dynamic DAGs)
- Group related tasks hierarchically for clarity

---

### 5.2 Dagster: Asset-Centric Orchestration

**Core Philosophy:**
- **Assets (data, models, reports) are first-class citizens** — not tasks
- Dagster asks "what assets need to be current?" vs. Airflow's "what tasks need to run?"
- Enables rich dependency tracking and impact analysis

**Asset-Centric Advantages:**
- **Global lineage visualization** — end-to-end data flows (raw → cleaned → reports)
- **Column-level lineage** — Dagster+ tracks individual column dependencies
- **External asset integration** — metadata from Snowflake, BigQuery, etc. unified
- **Asset-focused questions answerable** — "Is asset current? What do I need to refresh it? When will it update?"

**Data Flow Patterns:**
- **Explicit dependency definition** — asset dependencies declared
- **Lineage-driven execution** — what to run determined by what assets need updating
- **Change impact analysis** — understand downstream effects of upstream changes

**Design Principles:**
- **Invert from task-centric to asset-centric** — focus on data, not operations
- **Lineage as query language** — navigate data relationships
- **Lazy evaluation** — only execute what's needed to materialize assets
- **Integration over isolation** — connect to external systems

**Relevant Patterns for AI Factory:**
- Model agent outputs (code, analysis, reports) as assets
- Track asset lineage to understand agent task dependencies
- Implement asset-driven scheduling (update assets when inputs change)
- Use lineage for impact analysis (what's downstream of a failing agent task?)
- Support external asset references (e.g., metrics from external systems)

---

## 6. Cross-Framework Synthesis

### 6.1 Commonalities

| Pattern | Temporal | Restate | CrewAI | LangGraph | Airflow | Kubernetes |
|---------|----------|---------|--------|-----------|---------|------------|
| **State Persistence** | Event history | Journal | N/A | Checkpoints | N/A | N/A |
| **Deterministic Execution** | Replay-based | Journal replay | No | State-based | No | No |
| **Conditional Routing** | Signals | Service client | Delegation | Edges | Trigger rules | Affinity/scoring |
| **Retries** | Activity retries | Automatic backoff | N/A | Implicit in checkpoint | Exponential backoff | Eviction/rescheduling |
| **Hierarchical Structure** | None | None | Manager agent | Subgraphs | TaskGroups | Pod priority classes |
| **Timeout Handling** | Start-To-Close | Retry policy duration | N/A | Checkpoints | Task timeout | Pod grace period |
| **Resource Limits** | Task queues | Service capacity | Agent tools | N/A | Executor slots | Node CPU/memory |

### 6.2 Design Patterns for AI Factory

**Pattern 1: Immutable State + Replay-Based Recovery**
- Adopt Temporal/Restate model: events or journals as source of truth
- Design workflows for deterministic replay
- Support recovery from failure without side-effect re-execution

**Pattern 2: Explicit Dependency Graphs**
- Use DAG model from Airflow/Dagster
- Support conditional edges (LangGraph style) for branching
- Make dependencies visible and queryable

**Pattern 3: Role-Based Agent Assignment**
- Adopt CrewAI patterns: agents with specialized tools and objectives
- Support hierarchical coordination (manager agents)
- Enable delegation when agents need specialist assistance

**Pattern 4: Asset-Centric Metrics**
- Track agent outputs (code, analysis, reports) as assets
- Maintain lineage for impact analysis
- Support asset-driven scheduling

**Pattern 4: Priority & Preemption**
- Implement Kubernetes-style priority for task allocation
- Support preemption for critical tasks
- Make workload consolidation strategies explicit

---

## 7. API Design Recommendations

### 7.1 Work Item / Task Model

```graphql
interface WorkItem {
  id: ID!
  title: String!
  description: String!
  status: Status!  # PENDING, IN_PROGRESS, COMPLETE, FAILED
  priority: Priority!  # CRITICAL, HIGH, MEDIUM, LOW
  assignedAgent: Agent
  dependencies: [WorkItem!]!
  dependents: [WorkItem!]!
  createdAt: DateTime!
  updatedAt: DateTime!
  completedAt: DateTime
  history: [WorkItemEvent!]!
}

type WorkItemEvent {
  id: ID!
  type: EventType!  # CREATED, ASSIGNED, STATUS_CHANGED, FAILED, COMPLETED
  timestamp: DateTime!
  agent: Agent
  change: JSON
}
```

**Key Design Choices:**
- **GraphQL for flexible querying** (Linear pattern)
- **Events for audit trail** (Temporal/Restate pattern)
- **Dependencies separate from hierarchy** (Linear pattern)
- **Explicit priority for scheduling** (Kubernetes pattern)

### 7.2 Agent / Worker Model

```graphql
type Agent {
  id: ID!
  name: String!
  role: AgentRole!  # COORDINATOR, RESEARCHER, REVIEWER, EXECUTOR
  capabilities: [String!]!  # tool names
  status: AgentStatus!  # IDLE, BUSY, UNAVAILABLE, ERROR
  maxConcurrentTasks: Int!
  activeTasks: [WorkItem!]!
  completedTasks(limit: Int): [WorkItem!]!
  failureRate(window: Duration!): Float!  # for scheduling decisions
}

enum AgentRole {
  COORDINATOR  # hierarchical orchestration
  RESEARCHER   # information gathering
  REVIEWER     # validation, quality check
  EXECUTOR     # tool calling, implementation
}
```

**Key Design Choices:**
- **Roles inform task assignment** (CrewAI pattern)
- **Capabilities (tools) are queryable** (enables capability-driven assignment)
- **Status for scheduling** (Kubernetes resource model)
- **Metrics for load-balancing** (Jira auto-assignment pattern)

### 7.3 Workflow Execution Model

```graphql
type WorkflowExecution {
  id: ID!
  workflowDefinition: WorkflowDef!
  status: ExecutionStatus!  # PENDING, RUNNING, SUCCEEDED, FAILED, SUSPENDED
  startTime: DateTime!
  endTime: DateTime
  state: JSON!  # mutable execution state
  history: [ExecutionEvent!]!
  retryCount: Int!
  nextRetryAt: DateTime
}

type ExecutionEvent {
  id: ID!
  type: EventType!  # STEP_STARTED, STEP_COMPLETED, ERROR, SIGNAL_RECEIVED
  timestamp: DateTime!
  stepId: String!
  details: JSON!
}
```

**Key Design Choices:**
- **Events as immutable history** (Temporal pattern)
- **State for recovery** (Restate pattern)
- **Explicit retry tracking** (Temporal/Restate pattern)

---

## 8. Implementation Patterns

### 8.1 Task Execution Guarantees

**Design Pattern: Deterministic with Idempotency**

```pseudocode
WorkflowExecution:
  - Persist event history before executing step
  - On failure: replay from last persisted event
  - For external side effects (tool calls):
    - Assign idempotent ID to each call
    - Record completion in event history
    - On replay: check history first, reuse result if found
  - Never re-execute completed steps
```

**Benefits:**
- Recovers from any failure without data loss or side-effect duplication
- Enables long-running tasks without manual checkpointing
- Audit trail always available

### 8.2 Agent Task Allocation

**Design Pattern: Hierarchical with Capability Matching**

```pseudocode
ScheduleTask(task):
  1. If task.priority == CRITICAL:
       Preempt lower-priority tasks on available agents
  2. For available agents with matching capabilities:
       Score by: workload + failure_rate + specialization
  3. Assign to highest-scoring agent
  4. If no agent available:
       Queue with deadline; retry on agent availability
  5. If deadline approaching:
       Escalate to coordinator agent for delegation
```

**Benefits:**
- Aligns agent specialization with task requirements
- Prioritizes critical work
- Escalates when primary agents unavailable

### 8.3 Data Lineage Tracking

**Design Pattern: Asset-Centric Dependency Graph**

```pseudocode
AssetProduced(asset, producer_agent, inputs):
  1. Record asset metadata (name, type, location, schema)
  2. Record lineage: asset -> dependencies
  3. Record producer: agent name, timestamp, workflow ID
  4. On dependent asset query: walk lineage to find inputs
  5. On downstream failure: identify which assets might be stale
```

**Benefits:**
- Enable impact analysis (cascading failure detection)
- Support asset-driven re-execution
- Visualize agent workflow results

---

## 9. Known Pitfalls & Mitigations

| Pitfall | Framework | Mitigation |
|---------|-----------|-----------|
| Non-deterministic execution breaks replay | Temporal | Isolate side effects to activities; workflows logic only |
| State machine deadlock | LangGraph | Support manual intervention / breakpoints |
| Priority inversion (low-priority task blocking high-priority) | Kubernetes | Implement preemption; avoid unbounded resource holding |
| Lost events on coordinator failure | Temporal/Restate | Persist events durably before proceeding |
| Agent resource starvation | Kubernetes | Use resource quotas and priority classes |
| Circular task dependencies | Airflow | Validate DAG acyclicity at compile time |
| Explosion of conditional branches | LangGraph | Limit depth; support supervised branching |

---

## 10. References

**Issue Tracking & Automation:**
- [Linear API and Webhooks](https://linear.app/docs/api-and-webhooks)
- [Linear Developers](https://linear.app/developers/graphql)
- [Jira Automation Actions](https://support.atlassian.com/cloud-automation/docs/jira-automation-actions/)
- [Jira Auto-Assign on Transition](https://support.atlassian.com/jira/kb/how-to-automatically-change-the-assignee-when-transitioning-the-workflow/)

**Durable Execution Frameworks:**
- [Temporal Workflow Execution Overview](https://docs.temporal.io/workflow-execution)
- [Temporal Activity Execution](https://docs.temporal.io/activity-execution)
- [Temporal Durable Execution Definition](https://temporal.io/blog/what-is-durable-execution)
- [Restate Workflows Documentation](https://docs.restate.dev/tour/workflows)
- [Restate Durable Execution Principles](https://www.restate.dev/what-is-durable-execution)

**Multi-Agent AI Frameworks:**
- [CrewAI Hierarchical Process](https://docs.crewai.com/en/learn/hierarchical-process)
- [CrewAI Framework Repository](https://github.com/crewAIInc/crewAI)
- [LangGraph Graph API Overview](https://docs.langchain.com/oss/python/langgraph/graph-api)
- [LangGraph State Machines & Patterns](https://markaicode.com/langgraph-state-machine-branching-logic/)
- [LangGraph Architecture & Design](https://medium.com/@shuv.sdr/langgraph-architecture-and-design-280c365aaf2c)
- [CrewAI vs LangGraph vs AutoGen Comparison](https://www.datacamp.com/tutorial/crewai-vs-langgraph-vs-autogen)
- [AI Agent Frameworks 2026](https://designrevision.com/blog/ai-agent-frameworks)

**Pipeline & Workflow Orchestration:**
- [Apache Airflow DAGs Documentation](https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/dags.html)
- [Apache Airflow Core Concepts](https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/overview.html)
- [Dagster vs Airflow Comparison](https://dagster.io/blog/dagster-airflow)
- [Data Pipeline Orchestration Comparison](https://opencredo.com/blogs/data-orchestration-showdown-airflow-vs-dagster)

**Kubernetes Scheduling:**
- [Kubernetes Scheduling, Preemption, and Eviction](https://kubernetes.io/docs/concepts/scheduling-eviction/)
- [Kubernetes Pod Priority and Preemption](https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/)
- [Kubernetes Resource Bin Packing](https://kubernetes.io/docs/concepts/scheduling-eviction/resource-bin-packing/)
- [Beyond Kubernetes Scheduling: QoS and Priority](https://dev.to/gteegela/beyond-scheduling-how-kubernetes-uses-qos-priority-and-scoring-to-keep-your-cluster-balanced-4o8i)

---

## Appendix: Comparative Matrix

| Criteria | Temporal | CrewAI | LangGraph | Airflow | Dagster | Kubernetes |
|----------|----------|--------|-----------|---------|---------|------------|
| **Determinism** | High (replay) | Low | Medium (state snapshots) | Low | Low | Low |
| **Recovery** | Automatic (event replay) | Manual | Explicit (checkpoints) | Manual (task retries) | Manual | Rescheduling |
| **Task Dependencies** | Implicit (await) | Task ordering | Graph edges | DAG edges | Asset lineage | Node affinity |
| **Human Oversight** | Limited | Via manager agent | Breakpoints | UI monitoring | UI monitoring | Manual intervention |
| **Scalability** | Millions of executions | Hundreds of tasks | Thousands of nodes | Thousands of tasks | Thousands of assets | Tens of thousands of pods |
| **Code vs. Config** | Code | Code + config | Code | Code (Python) | YAML + Python | YAML |
| **Failure Handling** | Activity retries + workflow retry | Manual | Manual | Task retries | Task retries | Pod eviction/reschedule |
| **Agent/Worker Model** | N/A | Role-based | Node functions | Executor/scheduler | N/A | Pod/Node |

---

<!-- flux-research:complete -->
