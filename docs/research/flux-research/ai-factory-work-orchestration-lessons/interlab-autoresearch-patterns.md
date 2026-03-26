# Patterns from Autonomous Research Systems for AI Factory Orchestration

Research into two autonomous experiment-loop systems — Demarch's interlab and karpathy/autoresearch — to extract patterns applicable to AI factory work orchestration (the intent directive model, rework taxonomy, CUJ health thresholds, parallel agent dispatch).

## System Summaries

### Demarch interlab

interlab is an MCP plugin providing 7 tools (3 single-campaign + 4 multi-campaign orchestration) that implement an autonomous edit-benchmark-keep/discard loop. An LLM agent drives the intelligence; the plugin provides "dumb tools + smart guards" — circuit breakers, path-scoped git safety, metric parsing. State is reconstructed from append-only JSONL on every tool call (crash recovery for free). Multi-campaign orchestration uses beads (the project's work-tracking system) as the coordination layer: parent bead = broad goal, child beads = individual campaigns, dependency edges = execution ordering.

Key files: `/home/mk/projects/Demarch/interverse/interlab/AGENTS.md`, `skills/autoresearch/SKILL.md`, `skills/autoresearch-multi/SKILL.md`, `internal/experiment/state.go`, `internal/orchestration/plan.go`.

### karpathy/autoresearch

A ~630-line Python system that gives an LLM agent a single training script (train.py) and a fixed 5-minute GPU budget. The agent reads its own code, forms a hypothesis, modifies the script, trains, evaluates val_bpb (validation bits per byte), and keeps or discards. Everything the agent needs to know lives in program.md — a single Markdown file carrying instructions, constraints, and stopping criteria. The entire codebase fits in the LLM's context window, enabling full-file reasoning.

Sources: [GitHub repo](https://github.com/karpathy/autoresearch), [program.md](https://github.com/karpathy/autoresearch/blob/master/program.md), [The New Stack analysis](https://thenewstack.io/karpathy-autonomous-experiment-loop/), [VentureBeat coverage](https://venturebeat.com/technology/andrej-karpathys-new-open-source-autoresearch-lets-you-run-hundreds-of-ai).

---

## Pattern 1: Campaign-as-Intent

### How it works in autoresearch systems

Both systems separate the **what** (the optimization goal) from the **how** (the agent's iteration strategy):

| System | Intent expression | Execution strategy |
|--------|------------------|-------------------|
| karpathy/autoresearch | `program.md`: metric (val_bpb), direction (lower), constraints (5-min budget, no prepare.py changes), simplicity criterion | Agent reads full codebase, forms hypothesis, edits train.py |
| interlab single | `init_experiment` config: metric_name, direction, benchmark_command, files_in_scope, circuit breaker limits | Agent follows `/autoresearch` skill protocol: read context, generate idea, edit one file, benchmark, decide |
| interlab multi | `plan_campaigns` input: goal string, campaign specs with metrics + file scopes + dependency graph | Orchestrator decomposes goal into campaigns; subagents each run `/autoresearch` |

**Key insight:** The intent is always a tuple of (metric, direction, scope, constraints). In karpathy's system this is a single Markdown file. In interlab it's a JSON config. Neither system encodes the optimization *strategy* — the agent discovers that at runtime.

### Translation to AI factory orchestration

An **intent directive** maps directly to a campaign config:

- **metric** = the CUJ health signal or quality gate the directive targets
- **direction** = the rework taxonomy category (improve, fix regression, maintain threshold)
- **scope** = files_in_scope / modules_in_scope (prevents cross-intent interference)
- **constraints** = hard invariants (tests must pass, no API breaks, budget ceiling)
- **stopping criteria** = circuit breakers (max iterations, convergence threshold, no-improvement streak)

The factory's job is to create well-formed intent directives. The agent's job is to iterate within them. This separation means the factory never needs to know *how* to fix something — only *what* needs to be better and *how to measure it*.

---

## Pattern 2: Iterative Improvement Loops and the Keep/Discard Decision

### How it works

Both systems use the same core loop:

```
while not stopped:
    hypothesis = agent.think(context, history)
    change = agent.edit(codebase)
    result = benchmark(change)
    if improved(result, best):
        keep(change)      # commit, update best
        best = result
    else:
        discard(change)   # revert to last good state
```

Critical design choices shared by both systems:

1. **One change per iteration.** interlab's SKILL.md is explicit: "Never bundle multiple changes. You need to know what caused the metric shift." karpathy's system achieves this by having only one file to edit (train.py).

2. **Automatic revert on discard.** The agent never manually handles git. interlab's `log_experiment` tool commits on keep, reverts on discard. karpathy's autoresearch.py handles file restoration.

3. **Crash = discard + escalation.** Both systems count consecutive crashes toward a circuit breaker. A crash is not an error to debug — it's an experiment result (the hypothesis was bad).

4. **The agent never asks "should I continue?"** Both systems are emphatic: the loop runs autonomously until an exit condition fires. Human attention is the scarcest resource. interlab SKILL.md: "LOOP FOREVER. Never ask 'should I continue?' The circuit breaker is the safety net — trust it." karpathy's program.md: "Do NOT pause to ask the human if you should continue... The human might be asleep."

### Translation to the rework taxonomy

The keep/discard decision maps directly to rework outcomes:

| Experiment outcome | Rework taxonomy equivalent | Factory action |
|---|---|---|
| **keep** (metric improved) | Successful iteration — bead closes with improvement evidence | Credit against CUJ health threshold |
| **discard** (metric regressed) | Failed attempt — revert, try different approach | No state change; agent tries next hypothesis |
| **crash** (benchmark failed) | Broken attempt — invalid approach | Count toward circuit breaker; after N consecutive, escalate |
| **converged** (no more improvement possible) | Diminishing returns — stop iterating | Mark directive as "good enough"; move budget elsewhere |

The factory analogy: each bead is an "experiment." A sprint is a "campaign." The sprint's target metric (e.g., "reduce P95 latency for CUJ-3 below 2s") is the campaign config. Each bead attempt either keeps (merges) or discards (closes as wontfix/duplicate). The circuit breaker for the factory is: if N consecutive beads in a sprint produce no CUJ improvement, stop the sprint and reallocate.

---

## Pattern 3: Metric-Driven Stopping and "Good Enough"

### How autoresearch systems decide when to stop

**karpathy/autoresearch:**
- Fixed time budget (5 min per experiment) — prevents runaway compute
- No explicit stopping condition — the human stops the agent manually, or it runs until interrupted
- Implicit convergence: after ~700 experiments, only ~20 additive improvements found (long tail of diminishing returns)

**interlab — three independent circuit breakers:**
- `max_experiments` (default 50) — total iteration budget
- `max_crashes` (default 3) — consecutive crash tolerance
- `max_no_improvement` (default 10) — convergence detection (no improvement streak)
- Plus skill-level exit: "Last 5 experiments show <1% variance from best" = metric converged

**interlab multi-campaign — global stopping:**
- All campaigns complete (all hit individual exit conditions)
- No progress for 3 consecutive status checks across ANY campaign
- Global constraint violated (cross-campaign invariant broken)

### Translation to CUJ health thresholds

The factory needs the same layered stopping:

1. **Per-bead timeout** (= per-experiment time budget): If a single work unit takes longer than X, it's probably stuck. Kill it, mark as crash, try a different approach. This is karpathy's 10-minute kill threshold.

2. **Per-sprint convergence** (= max_no_improvement): If N consecutive beads in a sprint don't move the target CUJ metric, the sprint has hit diminishing returns. Stop and synthesize what was learned.

3. **Per-sprint budget** (= max_experiments): Hard cap on total iterations per sprint. Prevents unbounded spend on a single objective.

4. **Cross-sprint health** (= multi-campaign global stopping): If no CUJ improved across any active sprint for M cycles, the factory is stuck at a local optimum. Escalate to human for strategy re-evaluation.

5. **Threshold-based success** (interlab doesn't have this explicitly, but it's the factory's primary mode): The intent directive says "get metric below X." Once achieved, the campaign is done regardless of whether further improvement is possible. This is the "good enough" decision that autoresearch systems lack — they always chase the optimum. A factory must satisfy, not maximize.

---

## Pattern 4: Parallel Decomposition

### How multi-campaign autoresearch works

**interlab's multi-campaign orchestration:**

1. **Plan phase:** Agent analyzes codebase and decomposes a broad goal into focused campaigns. Each campaign gets: a unique metric, a benchmark command, a file scope, and optional dependency edges. The `plan_campaigns` tool validates the decomposition — specifically, it runs **file conflict detection** using Floyd-Warshall transitive closure on the dependency DAG to find files_in_scope overlaps between independent campaigns. Overlapping scopes between parallel campaigns are rejected at plan time.

2. **Dispatch phase:** Campaigns with no unmet dependencies are dispatched as subagents. Each subagent runs a full `/autoresearch` loop for its assigned campaign. One subagent per campaign, never bundled.

3. **Monitor phase:** Orchestrator polls `status_campaigns` for aggregate progress. Cross-campaign insights are propagated via ideas files (write to campaign B's `interlab.ideas.md`, let its subagent discover it naturally). Never modify a running campaign's code directly.

4. **Synthesize phase:** Once all campaigns complete, `synthesize_campaigns` reads all JSONL results, computes per-campaign improvement percentages, generates cross-campaign insights, and closes the parent bead.

**karpathy's scaling vision:** Spin up a swarm of agents that collaborate to tune smaller models and promote promising ideas to larger scales. In practice, 35 agents on a distributed P2P network ran 333 experiments unsupervised. The key constraint: each agent operates on its own copy and the "promote to larger scale" step is a human curation decision.

### Translation to factory-level parallel dispatch

The factory's parallel dispatch maps cleanly to interlab's multi-campaign model:

| interlab concept | Factory equivalent |
|---|---|
| Parent bead (epic) | Sprint objective / CUJ health target |
| Child beads (campaigns) | Individual work items dispatched to agents |
| files_in_scope disjointness | Module ownership / lock scope |
| depends_on edges | Sequential dependencies between work items |
| File conflict detection at plan time | Resource contention detection before dispatch |
| Cross-campaign insight propagation via ideas files | Agent-to-agent learning without direct interference |
| synthesize_campaigns | Sprint retrospective with aggregate metrics |

**Critical lesson from interlab:** File scope isolation is enforced *structurally*, not by convention. The `plan_campaigns` tool rejects plans where parallel campaigns share files without explicit dependency edges. A factory should do the same: if two agents need to modify the same module, serialize them. Concurrent modification of shared state is the primary failure mode of parallel autonomous work.

**Critical lesson from karpathy:** The "promote promising ideas to larger scale" pattern is valuable for factories. Run cheap explorations first (small model = small bead = fast feedback), then promote winners to expensive validation (larger model = full CI/CD = slower but definitive). This is the "funnel" pattern: wide exploration at low cost, narrow validation at high cost.

---

## Pattern 5: Human Oversight of Autonomous Research

### Where humans intervene

**karpathy/autoresearch:**
- **Before:** Human writes program.md (sets the research direction, constraints, metric)
- **During:** Human is explicitly absent. The system runs overnight. No checkpoints, no approval gates
- **After:** Human reviews the experiment log, cherry-picks winning changes, decides what to scale up
- **Meta-level:** Human decides when to rewrite program.md to redirect research

**interlab:**
- **Before:** Human (or higher-level agent) defines the campaign goal, metric, file scope, constraints
- **During:** Fully autonomous. Circuit breakers are the safety net, not human approval. Living document (interlab.md) provides transparency for async review, but does not gate progress
- **After:** Human reviews archived learnings (campaigns/<name>/learnings.md), decides whether to promote patterns
- **Meta-level:** Human decides when to launch new campaigns, which multi-campaign goals to pursue

**interlab multi-campaign adds one more layer:**
- **Before:** Human defines the broad goal; agent decomposes into campaigns (human can review the plan but typically doesn't gate it)
- **During:** Orchestrator agent monitors; subagent autonomy is complete within their campaign scope
- **After:** Synthesis report provides aggregate results; human decides what to do next

### Translation to factory oversight model

The consistent pattern across both systems: **humans set direction and review results; agents execute autonomously within bounded scopes.** The factory should adopt the same model:

1. **Human sets intent** (= writes program.md / creates campaign config): Define the CUJ to improve, the target threshold, the scope constraints, and the budget.

2. **No human in the loop during execution.** Circuit breakers (iteration limits, convergence detection, crash tolerance) replace human approval gates. The living document provides transparency but does not block progress. If the factory needs human input, it stops the campaign and escalates — it does not spin-wait for attention.

3. **Human reviews synthesized results.** Not individual experiment logs. The synthesis report (interlab) or the experiment log summary (karpathy) gives the human the information they need to make the next strategic decision.

4. **Human redirects strategy.** When the factory reaches a local optimum (all active campaigns converged with no CUJ improvement), the human rewrites the research program (= modifies program.md, creates new intent directives, reallocates budget).

---

## Pattern 6: Institutional Memory and Compound Learning

### How learning compounds across campaigns

**karpathy/autoresearch:** Minimal institutional memory. Each run starts fresh. The agent reads its own code (which includes prior modifications from kept experiments), so improvements accumulate in the artifact itself. But there is no cross-run knowledge base — insights from experiment #50 don't explicitly inform experiment #51 in a new run.

**interlab — three layers of memory:**

1. **Within-campaign:** `interlab.md` (living document updated every iteration) + `interlab.ideas.md` (hypothesis backlog). The agent reads these at the start of every iteration to avoid repeating failed approaches.

2. **Cross-campaign:** The **mutation store** (SQLite database) records every approach attempt with provenance: task_type, hypothesis, quality_signal, is_new_best, inspired_by. At campaign start, the agent queries prior mutations for the same task_type to seed hypotheses. This prevents rediscovery of known dead ends and accelerates convergence.

3. **Cross-session:** The **interlock broadcast** mechanism lets parallel agents share discoveries in real-time. Agent A finds a winning approach and broadcasts it on the "mutation" topic. Agent B picks it up and applies the insight to its own campaign. The `inspired_by` field tracks provenance chains, enabling genealogy queries that trace how ideas evolve across agents.

### Translation to factory compound learning

The mutation store pattern is directly applicable to the factory:

- **Every bead outcome is a mutation.** Record: what was tried (hypothesis), what happened (quality_signal), whether it was a new best (is_new_best), and what inspired the approach (inspired_by bead or session).

- **Before starting a new bead, query the mutation store.** "Has anyone tried this approach for this type of problem? What worked? What failed?" This is the factory's institutional memory — it turns individual agent experience into collective intelligence.

- **Genealogy tracking** enables accountability and pattern discovery. If approach X was inspired by approach Y from campaign Z, and approach X succeeded, that validates approach Y's direction even if Y itself didn't achieve the target metric. This is the "idea lineage" that makes autonomous research compound.

- **The factory needs both mutation-level and campaign-level synthesis.** Mutations are individual experiment outcomes. Campaign synthesis aggregates mutations into validated insights and dead ends (interlab's learnings.md). Sprint retrospectives should produce the equivalent: "What patterns worked across all beads in this sprint? What dead ends should future sprints avoid?"

---

## Synthesis: Mapping to the AI Factory Model

| Autoresearch concept | Factory equivalent | Key constraint |
|---|---|---|
| program.md / campaign config | Intent directive | Must specify: metric, direction, scope, constraints, budget |
| Single experiment iteration | Bead lifecycle (create -> attempt -> keep/discard) | One focused change per bead; atomic revert on failure |
| Campaign (sequence of iterations) | Sprint (sequence of beads targeting one CUJ) | Circuit breakers: max iterations, convergence, crash tolerance |
| Multi-campaign plan | Sprint portfolio (multiple CUJs improved in parallel) | File/module scope isolation enforced structurally |
| Benchmark command | CUJ health measurement | Must be deterministic, automated, and fast enough for tight loops |
| Keep/discard decision | Merge/revert decision | Based on metric delta, not subjective quality |
| Circuit breaker | Sprint budget + convergence detection | Prevents unbounded spend on diminishing returns |
| Mutation store | Factory institutional memory | Every outcome recorded with provenance for future agents |
| Living document (interlab.md) | Sprint dashboard / audit trail | Updated every iteration; enables async human review |
| Synthesis report | Sprint retrospective | Aggregate metrics, cross-campaign insights, recommendations |
| program.md rewrite | Strategy re-evaluation | Human redirects factory when at local optimum |

### What the factory adds beyond autoresearch

1. **Threshold-based success ("good enough").** Autoresearch systems chase the optimum. A factory must satisfy intent directives — once the CUJ metric crosses the threshold, stop and reallocate budget. Maximizing past "good enough" wastes compute.

2. **Priority-weighted dispatch.** Autoresearch treats all campaigns equally. A factory weights sprints by CUJ impact: a P0 regression gets more budget than a P2 improvement opportunity.

3. **Cross-intent interference detection.** Autoresearch's file conflict detection is a starting point, but factories face semantic conflicts too: improving latency might regress memory usage even if the files don't overlap. The factory needs CUJ-level conflict detection, not just file-level.

4. **Human escalation protocol.** Autoresearch has no escalation — the agent runs or stops. A factory needs tiered escalation: circuit breaker -> automated strategy rotation -> human review of stuck sprints.

5. **Cost accounting.** Neither autoresearch system tracks cost per experiment. A factory must: each bead has a token cost, each sprint has a budget, and the factory makes priority decisions based on cost-per-CUJ-improvement.

<!-- flux-research:complete -->
