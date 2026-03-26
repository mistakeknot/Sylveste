# Velocity & Forecasting Models for AI Agent Factories

**Research question:** How do existing tools estimate, forecast, and calibrate throughput — what works, what is cargo-culted from human assumptions, and what new forecasting primitives AI agent factories need?

**Status:** Complete
**Date:** 2026-03-19

---

## Executive Summary

Throughput forecasting in software delivery was built for human teams with two-week cadences, context-switching costs, and irreducible estimation uncertainty. AI agent factories break every assumption those models rest on: cost-per-task is measurable post-hoc, execution is 24/7, agent populations are elastic, and task spawning is instantaneous. This document surveys six forecasting domains — story points, sprint velocity, flow metrics, film production scheduling, manufacturing OEE, and calibration feedback loops — extracting what transfers, what is cargo cult, and what new primitives are needed.

The central finding: **the useful forecasting primitives are distribution-shaped, not point-shaped.** Monte Carlo throughput simulation, cycle-time percentile forecasting, OEE decomposition, and critical-chain buffer sizing all survive the transition to AI factories. Story points, planning poker, burn-down charts, and sprint velocity do not — they encode human cognitive constraints that AI agents lack.

---

## 1. Story Points and Planning Poker: What Replaces Them

### What Exists

Story points are a relative sizing unit, deliberately abstract, designed to capture human uncertainty about effort. Planning poker uses anchoring and group consensus to converge on Fibonacci-scale estimates. The mechanism assumes:

- Effort is uncertain and team-dependent
- Discussion surfaces hidden complexity
- Relative sizing avoids the anchoring bias of hours
- Points are stable across sprints even as team velocity fluctuates

Tools like Jira, Linear, and Asana all support story points natively. AI-enhanced estimation tools (Zenhub, monday.com, forecast.app) now use historical Git data to suggest estimates, claiming 60% reduction in estimation meeting time. The #NoEstimates movement (Zuill, Duarte, Killick, circa 2012) argues that counting completed items and measuring cycle time percentiles is strictly more informative than story-by-story estimation.

### What is Cargo Cult

**The entire estimation ceremony.** Planning poker assumes that the estimators are the executors and that discussion reveals hidden work. When the executor is an AI agent:

- **Effort is measurable, not estimated.** Token consumption, wall-clock time, and dollar cost are recorded for every task. Post-hoc cost distributions are available with zero manual effort.
- **Relative sizing is unnecessary.** The reason story points avoid hours is that humans are bad at absolute estimation. AI agent cost data *is* absolute — token counts and API costs are precise.
- **Group consensus adds no signal.** Planning poker exploits the wisdom of crowds over individual cognitive bias. An AI agent does not have cognitive bias about its own execution cost; the relevant uncertainty is about task complexity, which is better captured by historical distributions than by group discussion.

Research on SWE-bench token consumption confirms: token cost for comparable tasks exhibits 10x variance across runs, but the *distribution* is learnable. A 2025 OpenReview paper analyzed agent token consumption patterns and found that while individual task costs are noisy, task-category distributions converge with modest sample sizes (n > 20).

### What Replaces It

**Cost distribution estimation from historical data.** The replacement is not a better point estimate — it is a distributional forecast:

1. **Task categorization** (bug fix, feature, refactor, test) replaces Fibonacci sizing
2. **Per-category cost distributions** (tokens, dollars, wall-clock time) replace story points
3. **Percentile-based forecasts** (p50, p85, p95) replace single estimates
4. **Pre-hoc cost prediction** using task description embeddings and historical cost lookup replaces planning poker

The key insight from Troy Magennis's research: "If the samples were sized with story points, then the output will be in story points. If we use story count, then the output will be a number of stories." For AI factories, the natural unit is **dollars** (or tokens, which map to dollars). The Monte Carlo machinery works identically — the input distribution just changes from "story points completed per sprint" to "dollars per task by category."

**New primitive: Cost-per-landable-change distribution.** This is the AI factory equivalent of velocity. Demarch already tracks this ($2.93/landable change baseline as of 2026-03-18). The primitive is not the mean — it is the full distribution, parameterized by task type, model, and agent configuration.

---

## 2. Sprint Velocity and Burn-Down Charts: Wrong Time Window

### What Exists

Sprint velocity is the number of story points completed per sprint (typically two weeks). Burn-down charts plot remaining work against time within a sprint. Both assume:

- Fixed-length time boxes (1-4 weeks)
- Stable team composition within a sprint
- Context-switching costs between tasks
- A planning→execution→review cadence

Monte Carlo simulation over historical velocity data (Magennis, Actionable Agile, Focused Objective tools) produces probabilistic delivery dates — e.g., "85% chance of completing 20 items by June 1." This is the state of the art for human teams and works well with as few as 10 sprints of throughput data.

### What is Cargo Cult

**The two-week time box.** Sprints exist because:

1. Humans need planning ceremonies to coordinate
2. Humans need retrospectives to course-correct
3. Two weeks balances planning overhead against feedback latency
4. Work-in-progress limits prevent context-switching overload

AI agent factories have none of these constraints. An agent picks up a task, executes it, and emits a result — there is no context-switching cost, no planning ceremony, and no need for synchronous retrospectives. The "sprint" collapses to **the single task execution** as the atomic unit.

**Burn-down charts are meaningless** when tasks complete in minutes to hours and new tasks spawn continuously. The visual metaphor of "burning down" a fixed backlog over a fixed window does not map to a system where backlog size and agent count both vary continuously.

### What Transfers

**Throughput rate as a time series.** The useful abstraction from velocity is not "points per sprint" but "throughput as a function of time." For AI factories:

- **Throughput = landable changes per unit time** (hour, day)
- **Time series decomposition** reveals trend (model improvements), seasonality (if any — likely tied to human review availability), and noise
- **Capacity = agent-hours available** (elastic, unlike human headcount)

**New primitive: Instantaneous throughput rate.** Instead of measuring velocity over fixed windows, measure a rolling throughput rate — tasks completed per hour, smoothed over a configurable window. This is analogous to manufacturing's "units per hour" rather than "units per shift."

**New primitive: Throughput-per-dollar.** The efficiency metric is not "how fast" but "how much per dollar." An agent factory can always go faster by adding agents; the question is whether marginal throughput justifies marginal cost. This is a supply-chain concept (units per dollar of COGS) that software velocity never needed because human labor was a fixed cost.

---

## 3. Cycle Time and Lead Time Distributions: What Transfers Directly

### What Exists

Flow metrics (Reinertsen, SAFe, LinearB) measure:

- **Lead time:** idea → production (includes wait time, backlog time)
- **Cycle time:** first commit → production (active work + review + deploy)
- **Flow efficiency:** active work time / total elapsed time
- **Throughput:** items completed per unit time
- **WIP (Work in Progress):** items concurrently in flight

LinearB decomposes cycle time into four phases: coding time, pickup time, review time, deploy time. DORA metrics (deployment frequency, lead time for changes, change failure rate, MTTR) are the industry standard for delivery performance.

The 2025 DORA report found that AI coding assistants boost individual output (21% more tasks, 98% more PRs merged) but organizational delivery metrics stay flat. The bottleneck shifts from code generation to review, testing, and quality assurance. AI adoption correlates with *higher* instability — more change failures, more rework.

### What Transfers Directly

**Almost everything.** Flow metrics are the most agent-agnostic forecasting framework because they measure *the system*, not the worker:

- Cycle time distributions are just as valid for AI-generated changes
- Lead time still captures organizational latency (review queues, CI pipeline time, deployment windows)
- Flow efficiency exposes the ratio of agent execution time to total wait time — typically very low, because the agent finishes in minutes but review takes hours
- Little's Law (WIP = Throughput x Cycle Time) still holds and still governs capacity planning

**Percentile-based cycle time forecasting** (the core #NoEstimates technique) works out of the box: if 85% of completed tasks had cycle time <= 4 hours, forecast that the next task has an 85% chance of completing within 4 hours.

### What Changes

**The distribution shape changes.** Human cycle time distributions are approximately log-normal with a heavy right tail (a few tasks take orders of magnitude longer). AI agent cycle times have a different shape:

- **Bimodal distribution:** tasks either succeed quickly (minutes) or fail/loop and consume many retry cycles (hours, with token costs spiraling). The "spinning wheels" failure mode is well-documented — agents stuck in reasoning loops can consume 10-50x normal token budgets.
- **The right tail is cost-bounded, not time-bounded.** Human teams eventually finish slow tasks; AI agents hit token budgets and stop. The tail is truncated by budget, creating a censored distribution.
- **Review bottleneck dominates.** Agent execution is fast; human review creates the long pole. The cycle time distribution has two modes: agent-execution-time (fast, narrow) and human-review-time (slow, wide). Optimizing the agent mode without addressing review latency has diminishing returns — exactly what the 2025 DORA report observed.

**New primitive: Decomposed cycle time with agent/human phases.** Track cycle time as the sum of distinct phases: agent execution, CI/test, human review, deployment. Each phase has its own distribution. The bottleneck phase determines system throughput (Theory of Constraints applied to the value stream).

**New primitive: Cost-weighted cycle time.** A task that takes 2 hours but costs $50 in tokens is fundamentally different from one that takes 2 hours and costs $0.50. Cycle time alone does not capture this. The forecasting model needs (time, cost) tuples, not just time.

---

## 4. Film Production Scheduling: Resource-Constrained Forecasting

### What Exists

Film production uses a radically different forecasting model than software, one built for **scarce, non-fungible resources** under hard calendar constraints:

- **Script breakdown:** Every scene is decomposed into elements (cast, locations, props, effects, time of day). This is the "estimation" phase, but it estimates *resource requirements*, not effort.
- **One-liner:** A single-line-per-scene summary showing scene number, cast required, location, page count (as a proxy for shoot time), and day/night. This is the scheduling input.
- **Shooting schedule:** Scenes are grouped by location (not script order) to minimize "company moves" (location changes), reducing transport costs by up to 30%. Cast availability windows constrain which scenes can shoot on which days.
- **Buffer management:** 20% buffer on complex scenes, 30% on weather-dependent exteriors, 30-60 minutes of daily buffer time. Buffer allocation is non-uniform — technically demanding scenes get more.
- **Contingency days:** 1-2 unscheduled days per week of shooting, explicitly reserved for overruns.

### What is Cargo Cult (for Software)

Software has historically ignored resource-constrained scheduling because developers were treated as fungible. "Any developer can work on any task" is the agile assumption. Film production knows this is false — the lead actor is not interchangeable with a grip.

### What Transfers to AI Factories

**Resource constraint modeling.** AI agents are *not* fungible:

- Different models have different capabilities (Claude Opus vs Haiku, GPT-4 vs GPT-3.5)
- Different agent configurations suit different task types
- API rate limits, context window limits, and cost tiers create real resource constraints
- Human reviewers are scarce, non-fungible resources — exactly like lead actors

**The one-liner as task metadata.** Film's script breakdown maps to task decomposition. The useful fields transfer: task ID, required agent capability, estimated cost tier, required human reviewer, blocking dependencies. The one-liner format is more useful than a Jira ticket for scheduling because it is *designed for scheduling*, not for discussion.

**Non-uniform buffer allocation.** Software typically applies uniform contingency (if any). Film's approach — more buffer for higher-risk scenes — maps directly to AI task scheduling: tasks with high cost variance (novel features, complex refactors) need larger cost and time buffers than routine tasks (documentation, test additions).

**Critical Chain Project Management (CCPM).** Goldratt's CCPM, derived from Theory of Constraints, is widely used in film (implicitly) and construction. Key ideas:

- Remove safety padding from individual task estimates; aggregate it into project and feeding buffers
- Size project buffers at 50% of the critical chain duration (Goldratt's original rule) or use root-square-error method for more nuanced sizing
- Monitor buffer consumption rate, not task completion against estimates
- Feeding buffers protect the critical chain from delays in non-critical paths

**New primitive: Agent-capability-constrained scheduling.** Schedule tasks against agent capability slots (model tier, context window size, specialized tools) the way film schedules scenes against actor availability windows. This is a bin-packing/scheduling optimization, not a velocity calculation.

---

## 5. Manufacturing OEE Applied to AI Agents

### What Exists

OEE (Overall Equipment Effectiveness) decomposes production efficiency into three multiplicative factors:

```
OEE = Availability x Performance x Quality
```

- **Availability** = Run Time / Planned Production Time (accounts for downtime)
- **Performance** = (Ideal Cycle Time x Total Count) / Run Time (accounts for speed loss)
- **Quality** = Good Count / Total Count (accounts for defects)

World-class manufacturing targets OEE of 85%+. Typical plants run 60%. The power of OEE is its *decomposition* — a low OEE can be diagnosed: is the problem downtime (availability), slow speed (performance), or defects (quality)?

### Translation to AI Agent Factories

The OEE framework maps to AI agents with important modifications:

**Availability** = fraction of time the agent system is operational and accepting work.
- For cloud API agents, availability is effectively 100% (on-demand, no downtime)
- For self-hosted agents, availability includes infrastructure uptime
- This factor is *nearly trivial* for AI factories, unlike manufacturing where it is often the dominant loss
- **However:** human reviewer availability is NOT 100% and often IS the dominant constraint. OEE should be measured for the *system* (agent + review + deploy), not just the agent.

**Performance** = actual throughput / theoretical maximum throughput.
- Theoretical max = tokens-per-second * available-seconds (for the agent)
- Actual throughput is reduced by: retry loops, context window reloading, reasoning overhead, rate limiting
- The "spinning wheels" failure mode (agent stuck in loops consuming 10-50x normal tokens) is a *performance* loss, not a quality loss — the agent is running but not producing output at its ideal rate
- **Key metric:** tokens-per-landable-change vs theoretical-minimum-tokens-per-change

**Quality** = fraction of agent outputs that pass review and ship without rework.
- This is the most important factor for AI factories and the one most different from manufacturing
- Manufacturing quality is binary (pass/fail inspection). AI output quality is probabilistic and often requires human judgment
- **Quality rate = changes landed / changes attempted**
- Rework rate (changes requiring revision after review) is the quality loss
- The 2025 DORA finding — AI increases instability and rework — suggests quality is currently the binding constraint

### OEE Calculation for an AI Factory

```
Agent OEE = System_Availability x Execution_Efficiency x Land_Rate

Where:
  System_Availability = (hours system operational) / (hours in period)
  Execution_Efficiency = (ideal_cost_per_task * tasks_completed) / actual_total_cost
  Land_Rate = tasks_landed / tasks_attempted
```

Example: System up 23/24 hours (95.8%), ideal cost $2 but actual average $3.50 per task (57.1% efficiency due to retries and loops), 80% of attempted tasks land without rework.

```
OEE = 0.958 x 0.571 x 0.80 = 0.437 (43.7%)
```

This is below typical manufacturing OEE (60%), which is expected for a young technology. The decomposition immediately tells you: availability is fine, quality is decent, but **execution efficiency is the problem** — agents are spending nearly double the ideal cost per task on retries and overhead.

**New primitive: Agent OEE dashboard.** Track Availability, Execution Efficiency, and Land Rate independently. Trend each over time. Diagnose which factor is improving and which is degrading after model updates or configuration changes.

---

## 6. Forecast Calibration Feedback Loops

### What Exists

**Jira/Linear/Asana calibration:** These tools support estimate-vs-actual tracking but do not automate recalibration. The typical workflow:

1. Team estimates tasks (story points or hours)
2. Team logs actual time/effort
3. A dashboard (Tempo, ActivityTimeline) shows planned vs actual
4. Humans manually adjust future estimates based on the gap

Jira's Rovo AI suggests estimates based on historical data, but it is a *recommendation*, not a closed-loop recalibration system. The feedback loop is mediated by human judgment in sprint retrospectives.

**Monte Carlo recalibration:** Tools like Actionable Agile and Focused Objective automatically update their throughput distributions as new data arrives. This is the closest to automated calibration — the forecast model retrains on every new data point. The "When" chart recalculates delivery date probabilities after every completed item.

**Forecast calibration theory:** A well-calibrated forecast has the property that events predicted with probability P occur approximately P% of the time. Brier scores and calibration curves measure this. Software delivery forecasting rarely measures calibration formally — teams just notice when they are "usually late" or "usually early."

### What is Missing

**Model-update-aware recalibration.** When an AI model is updated (e.g., Claude 3.5 → Claude 4), the historical cost distribution shifts. Existing tools have no mechanism for:

- Detecting a distribution shift in cost/time data
- Downweighting or segmenting pre-update data
- Re-estimating the new distribution from a small sample of post-update data
- Communicating forecast uncertainty during the transition period

This is a well-studied problem in financial trading (alpha decay, regime detection) and supply chain (demand sensing after promotional events), but it has no analog in current software delivery tools.

**Automated calibration scoring.** The system should continuously compute:

- Calibration curves: for tasks predicted at 85th-percentile cost X, what fraction actually came in under X?
- Brier scores for completion-date forecasts
- Distribution shift detection (Kolmogorov-Smirnov test or similar) when new model versions deploy

**Cost-profile versioning.** Each (model, agent-config, task-type) tuple defines a cost profile. When any element changes, the profile should be versioned:

- Old profile data is archived, not discarded
- New profile starts with a wide prior (high uncertainty)
- Bayesian updating narrows the new profile as data accumulates
- During transition, forecasts use a mixture of old and new profiles, weighted by recency

### What Financial Trading Offers

Alpha decay modeling in quantitative finance faces an identical problem: a trading signal's predictive power degrades over time as markets adapt. The standard approach:

1. **Exponential decay weighting** of historical observations — recent data counts more
2. **Regime detection** (Hidden Markov Models, change-point detection) to identify when the generating process has changed
3. **Ensemble forecasts** that blend multiple models with different lookback windows
4. **Walk-forward validation** — never test a forecast on data that was available when the forecast was made

All of these apply directly to AI agent cost forecasting when model updates shift the cost distribution.

### What Supply Chain Demand Sensing Offers

Demand sensing (used by Amazon, Walmart, and supply chain platforms like Blue Yonder) addresses the problem of forecasting when the underlying distribution is non-stationary:

1. **Short-term sensing** uses the most recent data (days, not months) to override longer-term statistical forecasts
2. **Promotional event detection** identifies known causes of distribution shifts and adjusts accordingly
3. **Multi-horizon forecasting** provides different forecasts for different planning horizons (next day vs next month), each using different data windows

For AI factories, "promotional events" = model updates, configuration changes, prompt engineering improvements. The system should tag these events and segment cost data accordingly.

**New primitive: Calibrated probabilistic forecaster with regime detection.** The forecasting system should:

1. Maintain per-(model, config, task-type) cost distributions
2. Detect distribution shifts automatically (change-point detection)
3. Re-weight historical data using exponential decay after detected shifts
4. Report calibration scores alongside forecasts
5. Provide multi-horizon forecasts (next task, next day, next week) with appropriate uncertainty bands

---

## Synthesis: New Forecasting Primitives for AI Factories

| Human-Era Concept | Status | AI Factory Replacement |
|---|---|---|
| Story points | **Dead.** Encodes human estimation uncertainty. | Cost distribution per task category (tokens, dollars) |
| Planning poker | **Dead.** Consensus mechanism for human teams. | Automated cost prediction from task embeddings + historical lookup |
| Sprint velocity | **Dead.** Fixed-window, fixed-team metric. | Instantaneous throughput rate (tasks/hour, rolling) |
| Burn-down chart | **Dead.** Fixed-backlog, fixed-window visual. | Cost burn rate vs budget (continuous) |
| Sprint time box | **Mostly dead.** Cadence exists only for human sync points. | Event-driven: task complete → next task. Human review batches create de facto cadence. |
| Cycle time distribution | **Alive.** Agent-agnostic system metric. | Decomposed into agent-phase + human-phase distributions |
| Lead time | **Alive.** Still captures organizational latency. | Dominated by review queue time, not execution time |
| Flow efficiency | **Alive.** Exposes wait-time waste. | Expect very low values (agent fast, review slow) — this is the metric that drives review automation investment |
| Monte Carlo throughput sim | **Alive.** Works with any input distribution. | Input changes from "points/sprint" to "cost/task by category" |
| WIP limits | **Alive.** Little's Law still holds. | WIP limited by review capacity, not agent capacity |
| DORA metrics | **Alive but insufficient.** Deployment freq and cycle time transfer. | Need cost-per-change and land-rate additions |
| OEE decomposition | **New import.** Not used in software today. | Availability x Efficiency x Land Rate — powerful diagnostic |
| Critical chain buffers | **New import.** Underused in software. | Non-uniform buffer sizing by task risk category |
| Resource-constrained scheduling | **New import.** From film production. | Agent-capability-slot scheduling (model tier, reviewer availability) |
| Calibration scoring | **New import.** From forecasting/finance. | Brier scores, calibration curves, automated recalibration |
| Regime detection | **New import.** From trading/supply chain. | Change-point detection for model update cost shifts |

### The Five Primitives an AI Factory Forecaster Needs

1. **Cost distribution registry:** Per-(model, config, task-type) distributions of cost (tokens, dollars, time), updated continuously, versioned on model/config changes.

2. **Decomposed cycle time tracker:** Separate distributions for agent execution, CI/test, human review, and deployment phases. The bottleneck phase (almost always human review) determines system throughput.

3. **Agent OEE dashboard:** Availability x Execution Efficiency x Land Rate, trended over time, decomposed to diagnose whether the binding constraint is infrastructure, agent performance, or output quality.

4. **Monte Carlo throughput forecaster:** Uses the cost distribution registry as input. Answers "when will N tasks complete?" and "how many tasks complete by date D?" with confidence intervals. Re-forecasts automatically as new data arrives.

5. **Calibrated regime-aware updater:** Detects cost distribution shifts (model updates, config changes), re-weights historical data, reports calibration scores, and provides honest uncertainty bands during transition periods.

---

## Sources

- [Scrum.org: Monte Carlo Forecasting in Scrum](https://www.scrum.org/resources/blog/monte-carlo-forecasting-scrum)
- [Expedia Group: Monte Carlo Forecasting in Software Delivery](https://medium.com/expedia-group-tech/monte-carlo-forecasting-in-software-delivery-474bb49cb3f9)
- [Troy Magennis: Introduction to Monte Carlo Forecasting](https://observablehq.com/@troymagennis/introduction-to-monte-carlo-forecasting)
- [Troy Magennis: Story Point Velocity or Throughput Forecasting](https://observablehq.com/@troymagennis/story-point-velocity-or-throughput-forecasting-does-it-mat)
- [Focused Objective: Forecasting Tools](https://focusedobjective.com/)
- [LinearB: Flow Metrics](https://linearb.io/blog/5-key-flow-metrics)
- [LinearB: Lead Time vs Cycle Time](https://linearb.io/blog/lead-time-vs-cycle-time)
- [DORA: 2025 State of AI-Assisted Software Development](https://dora.dev/dora-report-2025/)
- [Faros AI: DORA Report 2025 Key Takeaways](https://www.faros.ai/blog/key-takeaways-from-the-dora-report-2025)
- [Swarmia: What the 2025 DORA Report Tells Us About AI Readiness](https://www.swarmia.com/blog/dora-2025-report-ai-readiness/)
- [Agile Pain Relief: NoEstimates](https://agilepainrelief.com/glossary/noestimates/)
- [Xebia: Accurate Forecasting Without Estimation](https://xebia.com/blog/accurate-forecasting-without-estimation/)
- [GetNave: Why Delivery Predictions Will Always Be Wrong with Story Points](https://getnave.com/blog/story-points-to-hours/)
- [OpenReview: Analyzing and Predicting Token Consumptions in Agentic Coding Tasks](https://openreview.net/forum?id=1bUeVB3fov)
- [Cosine: Pricing AI Coding Agents — Task vs Token](https://cosine.sh/blog/ai-coding-agent-pricing-task-vs-token)
- [OEE.com: Calculating OEE](https://www.oee.com/calculating-oee/)
- [Lean Production: Understanding OEE](https://www.leanproduction.com/oee/)
- [Wikipedia: Critical Chain Project Management](https://en.wikipedia.org/wiki/Critical_chain_project_management)
- [PMI: Critical Chain Buffer Sizing](https://www.pmi.org/learning/library/critical-chain-project-management-theory-7118)
- [Asana: Critical Chain Project Management](https://asana.com/resources/critical-chain-project-management)
- [Filmustage: Best Practices for Scheduling a Film](https://filmustage.com/blog/best-practices-for-scheduling-a-film/)
- [Filmustage: Overcoming Common Challenges in Shooting Scheduling](https://filmustage.com/blog/overcoming-common-challenges-in-shooting-scheduling/)
- [Scrum.org: Story Points with AI Dev Acceleration](https://www.scrum.org/forum/scrum-forum/94752/how-approach-story-point-estimation-advent-ai-dev-acceleration-tools)
- [Anthropic: 2026 Agentic Coding Trends Report](https://resources.anthropic.com/hubfs/2026%20Agentic%20Coding%20Trends%20Report.pdf)
- [PwC: Agentic SDLC in Practice](https://www.pwc.com/m1/en/publications/2026/docs/future-of-solutions-dev-and-delivery-in-the-rise-of-gen-ai.pdf)
- [Tempo: Planned vs Actuals in Jira](https://www.tempo.io/blog/the-planned-vs-actuals-report-in-jira-with-tempo)
- [Medium/Thrivve: Using Rovo for Probabilistic Forecasting](https://medium.com/thrivve-partners/using-rovo-jiras-ai-for-probabilistic-forecasting-time-saver-or-frustrater-6e49265ac42a)
- [Atlassian: Agile Monte Carlo Charts](https://community.atlassian.com/forums/App-Central-articles/Coming-Soon-Agile-Monte-Carlo-charts-probabilistic-forecasting/ba-p/3144668)

<!-- flux-research:complete -->
