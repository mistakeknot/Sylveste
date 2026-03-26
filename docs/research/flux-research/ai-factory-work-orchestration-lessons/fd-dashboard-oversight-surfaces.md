# Dashboard & Oversight Surfaces for AI Factory Operations

**Research question:** What dashboard and visibility patterns support effective human oversight as principals progressively withdraw from execution — what existing tools get right and what new views an AI factory requires?

---

## 1. The Common Operating Picture: From C2 to Agent Swarms

### What military C2 gets right

The [Common Operational Picture (COP)](https://en.wikipedia.org/wiki/Common_operational_picture) is a single, shared, continuously updated display of relevant operational information — own-force positions, enemy positions, infrastructure status — shared across echelons. Its design principles map directly to AI factory oversight:

| COP Principle | AI Factory Translation |
|---|---|
| **Single authoritative view** — all echelons see the same picture | One dashboard shows all active agents, their current tasks, and blockers. No "my view" vs "your view" fragmentation. |
| **Relevancy-gated display** — information is emplaced based on relevance to the echelon's decisions | A sprint-lead sees task-level status; a principal sees only blockers and cost trajectory. Same data, different projections. |
| **Data fusion, not raw feeds** — COP depends on contextualized, analyzed data, not sensor dumps | Agent telemetry (token counts, tool calls, diffs) must be aggregated into meaningful signals: "task is stuck," "cost overrun," "dependency blocked." Raw LLM traces are not a COP. |
| **Conspicuity** — displays must be conspicuous and accessible to those maintaining SA | The overview must be visible without navigation. Nuclear control rooms achieve this with large-format overview displays visible from any operator position. The AI factory equivalent is the always-visible top bar or ambient display. |

### What's new for agent swarms

Military COP tracks entities with known positions on a map. Agent swarms lack spatial metaphor — they operate in a task graph, not geography. The COP equivalent needs:

- **Task-graph topology** as the spatial substrate (not a Kanban column, not a map)
- **Agent identity markers** showing which agent holds which task, analogous to unit symbols on a COP
- **Temporal layering** — what changed in the last N minutes, analogous to the COP's "last known position" timestamps
- **Contested-resource indicators** — which files, APIs, or environments are being accessed by multiple agents simultaneously (analogous to shared battlespace)

New Relic's 2026 [AI Agent Monitoring](https://newrelic.com/blog/ai/beyond-the-black-box-next-gen-agentic-ai-monitoring) moves in this direction with "Unified Orchestration Visibility" that treats multi-agent systems as cohesive wholes and integrates AI Agent Spans into distributed-tracing waterfall views. Splunk's Q1 2026 [AI Infrastructure Monitoring](https://www.splunk.com/en_us/blog/observability/splunk-observability-ai-agent-monitoring-innovations.html) provides data-dense dashboards for orchestration frameworks, agents, model providers, and GPUs. Both are infrastructure-oriented — neither provides the task-graph COP an AI factory principal needs.

---

## 2. Exception-Based Management: Surface Only What Requires a Human

### The EICAS model

Aviation's [Engine Indicating and Crew Alerting System (EICAS)](https://skybrary.aero/articles/engine-indicating-and-crew-alerting-system-eicas) is the gold standard for exception-based displays. Its design choices are directly transferable:

| EICAS Element | AI Factory Analog |
|---|---|
| **Three-tier severity** — Warning (red, immediate action), Caution (yellow, awareness), Advisory (green/blue, informational) | **Blocker** (agent cannot proceed, principal decision required), **Drift** (cost/time exceeding thresholds, may self-resolve), **Info** (completed milestones, routine progress) |
| **Prioritized + chronological ordering** — most severe first, most recent within severity band | Same. Blockers always on top, ordered by staleness (oldest blocker = most urgent). |
| **Master caution light** — a single ambient signal that something needs attention | A single badge count or color shift on the oversight bar. Not a notification storm. |
| **Clickthrough to context** — each alarm tile navigates to the relevant system schematic | Each alert links to the task, the agent's reasoning trace, and the specific decision point. |

### Alarm flood prevention (ISA-18.2)

Industrial alarm management standard [ISA-18.2](https://www.isa.org/standards-and-publications/isa-standards/isa-18-series-of-standards) defines an alarm flood as >10 alarms in 10 minutes and mandates rationalization — every alarm must have a defined cause, consequence, and corrective action. Techniques directly applicable to AI factory oversight:

- **Alarm rationalization** — systematically evaluate whether each alert type genuinely requires principal attention. "Agent retried a tool call" is not an alarm. "Agent has been stuck for 5 minutes with no progress" is.
- **State-driven suppression** — during known transient states (e.g., a deployment is running, a large codebase is being indexed), suppress alarms that are expected consequences of that state.
- **First-out alarming** — in a cascade, show only the root cause, not the downstream effects. If an API key expires and 12 agents fail, surface the key expiry once, not 12 agent failures.
- **Maximum alarm rate** — ISA-18.2 recommends no more than ~6 alarms per hour in steady state for an operator to handle effectively. An AI factory dashboard should target similar rates.

### Hospital rapid-response and airline ops

Hospital rapid-response teams activate on specific physiological thresholds (Modified Early Warning Score), not on "patient seems unwell." Airline operations centers (AOCs) monitor hundreds of flights but only escalate on threshold breaches: delay >30 min, crew duty-time approaching limits, maintenance deferral stacking. Both use:

- **Quantitative thresholds, not qualitative judgment** — the system decides what's an exception, not the operator scanning for it
- **Graduated escalation** — first alert goes to the closest handler; only unresolved exceptions escalate to the principal
- **Automatic de-escalation** — when the condition clears, the alert resolves without manual acknowledgment

### Threshold logic for an AI factory

A concrete threshold scheme for agent oversight:

| Signal | Drift (yellow) | Blocker (red) |
|---|---|---|
| Task elapsed time | >2x median for similar tasks | >5x median or agent self-reports stuck |
| Token spend on task | >150% of budget estimate | >300% of budget or no progress in last 20% of spend |
| Tool-call failure rate | >30% in last 10 calls | >60% or same error 3x consecutively |
| Agent idle time | >3 minutes with no action | >10 minutes |
| Confidence self-report | Agent reports "uncertain" | Agent reports "blocked, need principal input" |
| File conflict | Two agents editing same file region | Merge conflict detected |

---

## 3. Spatial Metaphors: What PM Tools Get Right, What Breaks at Scale

### What existing tools offer

| Tool | Primary Metaphor | Strength | Breaks When |
|---|---|---|---|
| **Jira board** | Kanban columns (To Do / In Progress / Done) | Simple state machine, universally understood | >50 concurrent tasks — columns become scrolling lists with no spatial meaning |
| **Linear cycle** | Time-boxed sprint with progress ring | Creates urgency and scope clarity | Tasks run in parallel at inhuman speed — a "cycle" of 200 tasks completing in 4 hours has no human rhythm |
| **Asana timeline** | Gantt chart with dependencies | Shows critical path and parallelism | [Performance degrades at 1000+ tasks](https://www.ideaplan.io/compare/jira-vs-linear-vs-asana); dependency lines become spaghetti; assumes sequential human work |

### What breaks fundamentally

All three tools assume **one task = one human** and **tasks proceed at human pace** (~2-8 per developer per day). An AI factory runs 10-100 agents completing tasks in minutes. The spatial metaphors fail because:

1. **Columns lose meaning** — In Kanban, "In Progress" implies a small number of active items. When 40 agents are all "In Progress" simultaneously, the column is just a list.
2. **Time axes compress** — A Gantt chart spanning 30 minutes of wall-clock time with 80 parallel tracks is not a useful visualization.
3. **Dependency arrows explode** — Real agent work has dynamic dependencies discovered during execution, not pre-planned waterfall deps.

### New metaphors needed

**The Hive View (topological):** Tasks are nodes in a directed acyclic graph. Active agents are particles moving through edges. Node size = remaining effort. Edge thickness = data flow. Clusters form around shared resources (a repo, an API, a database). This replaces the Kanban board for in-flight work.

**The Burn Meter (temporal):** Instead of a timeline, show a single horizontal bar per active workstream with three segments: completed (green), in-flight (amber), remaining (gray). Stack multiple bars vertically. This replaces the Gantt chart — it shows progress fraction without pretending to know exact finish times.

**The Exception Stack (priority):** A single column of items that need human attention, ordered by severity and staleness. Not a board with columns — a feed with priority. This replaces the sprint backlog for oversight mode. Everything not in this stack is "agents are handling it."

**The Replay Scrubber (forensic):** A time slider that shows the state of the task graph at any past moment. For post-hoc review, not real-time monitoring. This replaces the activity log — it provides temporal context without requiring reading chronological entries.

---

## 4. Audit Trail and Explainability: What Context Does a Principal Need?

### Lessons from MES, OR scheduling, and military decision logs

When a principal intervenes — overrides an agent decision, reassigns a task, changes scope — they need context fast. Three domains have solved this:

**Manufacturing Execution Systems (MES):** Under FDA 21 CFR Part 11, MES systems maintain audit trails that capture not just *what* changed but *why*. When an operator deviates from a recipe, the system captures the deviation reason with an electronic signature. The AI factory equivalent: when an agent deviates from its plan (e.g., edits a file not in scope, chooses a different approach than specified), the system should capture the agent's stated reasoning automatically, not require a human to reconstruct it.

**Operating Room scheduling:** When an OR schedule changes mid-day (emergency case, equipment failure, surgeon availability), the change-of-plan record captures: prior plan, trigger event, new plan, who authorized, downstream impact. The AI factory equivalent: when an agent re-plans (abandons an approach, picks up a different task, requests help), the system should record a structured change-of-plan event with: prior approach, reason for change, new approach, expected impact on timeline.

**Military decision logs (MDMP):** The Military Decision-Making Process requires recording Commander's Intent, courses of action considered, criteria for selection, and the rationale for the chosen course. Key features: decisions are recorded *before* execution, alternatives are preserved (not just the winner), and the decision authority is explicit. The AI factory equivalent: when an agent faces an ambiguous situation and chooses a path, the system should record what alternatives it considered and why it chose this one — especially for irreversible actions.

### The five-layer intervention context stack

When a principal clicks on an alert or task, they need information in this order:

1. **What happened** — one-sentence summary: "Agent-7 has been stuck for 8 minutes trying to resolve a type error in `parser.go`"
2. **What the agent tried** — collapsed list of approaches attempted, most recent first
3. **What the agent thinks the options are** — if the agent can articulate its uncertainty, show its self-assessed options
4. **What changed since the last known-good state** — diff view of files modified, tests run, commands executed
5. **Full trace** — the complete reasoning chain, tool calls, and outputs (available but not shown by default)

This mirrors nuclear control room design where [information is layered from overview schematic to detailed parameter display](https://ceur-ws.org/Vol-696/paper4.pdf), with each layer accessible by progressive drill-down. The improved HMI designs from nuclear modernization studies showed 33% higher task success rate and 79% lower navigation time compared to legacy displays.

---

## 5. Progressive Disclosure: Four Zoom Levels

Drawing from [progressive disclosure research (NNGroup)](https://www.nngroup.com/articles/progressive-disclosure/), nuclear control room information hierarchy, and [dashboard information hierarchy patterns](https://clusterdesign.io/information-hierarchy-in-dashboards/), an AI factory dashboard should support four distinct zoom levels:

### Level 0 — Ambient (Glanceable)

**Analogy:** The master caution light in a cockpit. The andon board on a factory floor.

- Visible without opening a dashboard (menu bar icon, ambient display, notification badge)
- Three states: **green** (all agents nominal), **yellow** (drift detected, no blockers), **red** (at least one blocker requiring principal)
- Shows: blocker count, active agent count, spend-so-far vs budget
- Interaction: click to open Level 1

**Design constraint:** Must be parseable in <2 seconds. No text beyond a number. Color and count only.

### Level 1 — Oversight (The COP)

**Analogy:** The nuclear control room overview display. The airline ops center main board.

- Shows all active workstreams as horizontal burn meters (see Section 3)
- Exception stack on the right: blockers and drifts, ordered by severity/staleness
- Top bar: aggregate metrics (total spend, completion %, active agents, time elapsed)
- No individual agent details — only workstream-level aggregates
- Interaction: click a workstream to go to Level 2; click an exception to go to Level 3

**Design constraint:** Must fit on a single screen without scrolling. Maximum ~20 items visible. If more exist, show top-20 by priority and a "+N more" indicator.

### Level 2 — Workstream (The Task Graph)

**Analogy:** A specific sector on the ATC radar. A specific OR suite in the surgical dashboard.

- Shows one workstream's task graph: nodes = tasks, edges = dependencies, agent icons on active tasks
- Each task node shows: status, assigned agent, elapsed time, token spend
- Highlights: blocked tasks (red border), drifting tasks (yellow border), completed (green fill)
- Side panel: recent events for this workstream (task completions, agent handoffs, plan changes)
- Interaction: click a task to go to Level 3

**Design constraint:** Supports 5-50 tasks per workstream. If a workstream has >50 tasks, auto-cluster into sub-groups.

### Level 3 — Task Detail (The Intervention Surface)

**Analogy:** The specific alarm tile + system schematic in EICAS. The patient chart in rapid response.

- Shows the five-layer intervention context stack (Section 4)
- Action buttons: reassign agent, provide guidance, change scope, approve/reject, abort
- Live feed of agent activity (streaming, can be paused)
- Cost breakdown: tokens spent by category (reasoning, tool calls, retries)
- Interaction: this is where the principal *does things*, not just observes

**Design constraint:** Must load in <1 second from Level 2 click. The summary (Layer 1 of the context stack) must be visible without scrolling.

---

## 6. Real-Time Cost Visibility: The Missing Primary Metric

### The gap in software PM tools

No mainstream PM tool (Jira, Linear, Asana, GitHub Projects, Monday.com) surfaces cost-per-task or burn rate as a primary dashboard metric. They track *time* (story points, cycle time, lead time) as a proxy for cost, which works when the cost function is (developer salary x time). In an AI factory, cost is (model price x tokens) + (compute x time) + (API calls x price) — a direct, measurable, per-task dollar amount. This makes cost a *better* primary metric than time.

### Patterns from manufacturing and finance

**OEE Dashboards ([Vorne](https://www.vorne.com/solutions/applications/oee-software/), [Tulip](https://tulip.co/blog/overall-equipment-effectiveness-oee-dashboard/)):** Manufacturing OEE dashboards track cost-per-unit in real time by decomposing loss into three buckets: availability (downtime), performance (slow cycles), and quality (scrap). The AI factory equivalent:

| OEE Bucket | AI Factory Equivalent | Metric |
|---|---|---|
| Availability loss | Agent idle time, blocked time, waiting for human | % of wall-clock time agents are not producing |
| Performance loss | Token waste on retries, hallucination loops, suboptimal model selection | Tokens spent / useful output tokens |
| Quality loss | Failed tasks, reverted commits, rework | % of completed tasks that required rework |

Manufacturing dashboards make these visible as **real-time gauges** — not buried in reports. An AI factory should show a live OEE-equivalent gauge: `(useful output tokens) / (total tokens spent)` as a primary efficiency metric.

**Real-time P&L dashboards:** Finance trading floors show live P&L with [burn rate and runway calculations](https://www.phoenixstrategy.group/blog/how-to-design-real-time-financial-dashboards). Key patterns to adopt:

- **Budget vs actual as a primary gauge**, not a report — shown as a filling bar (green when on track, yellow when approaching limit, red when exceeded)
- **Burn rate trend line** — not just current spend, but the slope. A task that spent $2 in 5 minutes and is 80% done is fine. A task that spent $2 in 5 minutes and is 10% done is alarming. The rate relative to progress is the signal.
- **Runway indicator** — at current burn rate, when will the budget be exhausted? Displayed as a countdown, not a number.
- **Cost attribution** — break spend into: model inference, tool execution, retries/waste, inter-agent communication. This is the AI factory equivalent of a P&L line-item breakdown.

### Cost visibility at each zoom level

| Level | Cost Display |
|---|---|
| **L0 Ambient** | Single number: total spend today vs daily budget (e.g., "$47 / $200") |
| **L1 Oversight** | Per-workstream spend bars; aggregate burn rate trend; budget runway countdown |
| **L2 Workstream** | Per-task cost bubbles (bubble size = spend); cost efficiency ratio per task |
| **L3 Task Detail** | Token-by-token cost breakdown; cost of retries highlighted; projected total cost to completion |

---

## 7. Synthesis: What an AI Factory Dashboard Requires Beyond Existing Tools

### Capabilities that existing tools provide (adopt)

1. **EICAS-style tiered alerting** with color-coded severity, prioritized ordering, and clickthrough to context — this is well-understood and directly transferable
2. **Progressive disclosure** with glanceable overview, intermediate COP, and detail drill-down — established UX pattern, well-documented by NNGroup and nuclear HFE research
3. **Audit trail with structured rationale capture** — MES and military decision logs show the template: what, why, who authorized, what alternatives existed

### Capabilities that require new design (build)

1. **Task-graph COP** — no existing tool provides a continuously-updated topological view of a task DAG with agent positions, resource contention markers, and temporal layering. Kanban boards, Gantt charts, and cycle views all assume human-paced sequential work.
2. **Autonomous alarm rationalization** — ISA-18.2 provides the framework, but applying it to AI agent telemetry (where the alarm types themselves are novel) requires defining the alarm philosophy from scratch: what constitutes a genuine principal-required decision vs. a transient agent state?
3. **Cost as a first-class dimension** — no PM tool treats cost-per-task as a primary metric. OEE and P&L dashboards show the visualization patterns, but integrating cost into a task-management context (where cost is per-task, real-time, and directly controllable via model selection and retry policy) is new.
4. **The exception stack as primary navigation** — existing tools orient around the *work* (board, timeline, backlog). An oversight dashboard should orient around *exceptions* — the default view is "here's what needs you," not "here's everything that's happening."
5. **Change-of-plan event capture** — agents re-plan constantly. No existing tool has a structured event type for "I changed my approach because X." This needs to be a first-class event in the telemetry schema, not buried in logs.
6. **Agent-aware resource contention display** — when 3 agents are editing the same module, the COP should show this as a spatial conflict marker, analogous to shared battlespace in military COP. No existing tool tracks this.

### The fundamental shift

Traditional dashboards answer: "What is the status of my project?"
An AI factory dashboard answers: "What do I need to do right now, and how much is it costing me?"

The principal is not managing work. The principal is governing a system that manages work. The dashboard's job is to make governance efficient — surfacing only the decisions that require human judgment, providing the context to make those decisions quickly, and making the cost of both action and inaction visible.

---

## Sources

- [Common Operational Picture — Wikipedia](https://en.wikipedia.org/wiki/Common_operational_picture)
- [Benefits of a Common Operating Picture — MAG Aerospace](https://www.magaero.com/unlocking-the-benefits-of-a-common-operating-picture/)
- [From COP to Common Situational Understanding — ScienceDirect](https://www.sciencedirect.com/science/article/pii/S0925753521002253)
- [EICAS — SKYbrary](https://skybrary.aero/articles/engine-indicating-and-crew-alerting-system-eicas)
- [EICAS — Wikipedia](https://en.wikipedia.org/wiki/Engine-indicating_and_crew-alerting_system)
- [ISA-18.2 Alarm Management Standard](https://www.isa.org/standards-and-publications/isa-standards/isa-18-series-of-standards)
- [Alarm Rationalization — Emerson](https://www.emerson.com/documents/automation/white-paper-alarm-rationalization-deltav-en-56654.pdf)
- [ISA-18.2 and the Future of Alarm Management — ProcessVUE](https://www.processvue.com/news-blog/digitalisation-isa-18-2-and-the-future-of-alarm-management/)
- [Human-Centered Design for Nuclear Control Room Modernization](https://ceur-ws.org/Vol-696/paper4.pdf)
- [Nuclear Control Room Design Guide — Controlroomsolution.com](https://controlroomsolution.com/a-guide-to-the-nuclear-power-plant-control-room/)
- [Human Factors — NRC](https://www.nrc.gov/reactors/operating/ops-experience/human-factors)
- [Progressive Disclosure — NNGroup](https://www.nngroup.com/articles/progressive-disclosure/)
- [Information Hierarchy in Dashboards — Cluster](https://clusterdesign.io/information-hierarchy-in-dashboards/)
- [Beyond the Black Box: Next-Gen AI Agent Monitoring — New Relic](https://newrelic.com/blog/ai/beyond-the-black-box-next-gen-agentic-ai-monitoring)
- [Splunk Observability Q1 2026 Update](https://www.splunk.com/en_us/blog/observability/splunk-observability-ai-agent-monitoring-innovations.html)
- [AI Agent Orchestration — Deloitte 2026](https://www.deloitte.com/us/en/insights/industry/technology/technology-media-and-telecom-predictions/2026/ai-agent-orchestration.html)
- [Human-in-the-Loop Agentic AI — OneReach](https://onereach.ai/blog/human-in-the-loop-agentic-ai-systems/)
- [OEE Dashboard — Tulip](https://tulip.co/blog/overall-equipment-effectiveness-oee-dashboard/)
- [OEE Software — Vorne](https://www.vorne.com/solutions/applications/oee-software/)
- [Real-Time Financial Dashboards Design — Phoenix Strategy Group](https://www.phoenixstrategy.group/blog/how-to-design-real-time-financial-dashboards)
- [Jira vs Linear vs Asana 2026 — Ideaplan](https://www.ideaplan.io/compare/jira-vs-linear-vs-asana)
- [Decision Audit Trails — Workmate](https://www.workmate.com/blog/decision-audit-trails-structuring-timestamped-notes)
- [MES Manufacturing Execution System Guide — SG Systems](https://sgsystemsglobal.com/glossary/mes-manufacturing-execution-system/)
- [Audit Trail Compliance for 21 CFR Part 11 — IntuitionLabs](https://intuitionlabs.ai/articles/audit-trails-21-cfr-part-11-annex-11-compliance)

<!-- flux-research:complete -->
