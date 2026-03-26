# AI Factory Work Orchestration: Research Synthesis

**Research Complete:** 2026-03-19
**Question:** What lessons from work orchestration in diverse domains apply to building an AI agent software factory where workers are cloneable, cost-per-task is measurable, and humans progressively withdraw to pure oversight?

**Agents:** 10 research threads (5 focused domains + 5 discovery)
**Sources:** 82 external (docs, research, tools), 40+ internal (Demarch codebase)
**Confidence:** High (6/10 agents converge on core patterns)

---

## Executive Summary

Work orchestration for AI agent factories is **fundamentally a governance problem, not a PM problem**. Traditional software PM tools (Jira, Linear) optimize for human cognitive load and team coordination. AI factories invert the constraints: workers scale elastically, cost is continuous and measurable, and execution is 24/7. This creates a new design space where patterns from five non-software domains converge:

1. **Manufacturing MES** — work decomposition, quality gating, rework routing
2. **Military C2** — intent-based delegation, graduated authority, mission-type orders
3. **Hospital OR** — constraint satisfaction, uncertainty handling, multi-resource scheduling
4. **Film Production** — resource-constrained scheduling, version control, quality pipeline stages
5. **Finance/Supply Chain** — cost-aware forecasting, distribution-shaped estimates, regime detection

**Demarch's current state** implements beads + routing + phase gates + basic cost tracking. This is a solid foundation, but **three critical gaps** prevent full autonomy:

1. **No graduated autonomy tiers** — authority is binary, not earned. Mycroft (v0.1, planned) should address this.
2. **No cost-per-task routing** — dispatch ignores budget and agent cost profiles. Routing needs budget awareness.
3. **No autonomous phase progression** — human review gates every advancement. Must support conditional skipping (e.g., Level 5 automation for low-risk tasks).

---

## Part 1: Cross-Cutting Themes

### Theme 1: Work Decomposition Must Separate Planning from Execution

**Converges:** fd-work-decomposition, best-practices-researcher, repo-research-analyst
**Evidence:** Manufacturing MES, hospital OR, military MDMP all distinguish ERP (strategic planning) from MES (real-time execution).

**Finding:** Traditional software assumes all decomposition happens upfront. AI factories need two-level decomposition:

1. **Epic/Sprint (ERP layer, 1-2 weeks):** "Implement feature X" — no task breakdown yet
2. **Bead (Work order, claims-time):** When an agent claims the work, it produces a dependency graph and replan checkpoints

**Why this matters:**
- You cannot know the true task shape until someone understands the codebase
- Demarch's `/clavain:sprint` → `/clavain:work` pipeline encodes this implicitly
- Best teams allocate 10-15% capacity for replanning/rework, but no tooling supports "checkpoint replanning" at 25% and 50% of time budget

**Demarch gap:** Brainstorm produces a spec; strategy proposes children; but once a bead is claimed, there's no mechanism for the executing agent to propose a revised child decomposition. Agents should be able to say "I discovered this needs 3 subtasks, not 1" and have the system adjust.

**Actionable:** Add a `bd refine <parent_id>` command that allows agents mid-execution to propose child beads without requiring manual processing. Auto-merge if complexity increased <20%.

---

### Theme 2: Graduated Authority Is Non-Negotiable; Binary Authority Doesn't Scale

**Converges:** fd-human-withdrawal, best-practices-researcher, repo-research-analyst, framework-docs-researcher
**Evidence:** Military ROE, hospital CRM, aviation automation levels, Knight-Columbia autonomy framework

**Finding:** Current tools (GitHub, CI/CD, Jira) model authority as binary: can deploy or cannot. AI factories need five tiers:

| Tier | Example | When Earned |
|------|---------|------------|
| **Propose** | Suggest changes | Default; demonstrates understanding |
| **Execute** | Write files, run tests | 5 successful proposals accepted without rework |
| **Commit** | Create PRs | 5 successful executions without rollback |
| **Deploy** | Merge and release | 3 successful commits + human certification |
| **Spend** | Provision resources | Explicit delegation + budget cap |

**Why this matters:**
- Jumping from Propose (L1) to Deploy (L4) destroys the principal's out-of-the-loop situational awareness (Endsley's research)
- Each tier should be domain-scoped: an agent may be Deploy-level for tests, Propose-level for payment code
- Authority should be losable: one incident reverts an agent to a lower tier for that domain

**Demarch gap:** Beads have no authority metadata. There's no mechanism to say "this agent can auto-commit docs, but only propose for payment code." Interspect has "exclude agent X from domain Y" but not positive authority grants. Mycroft (planned) will add graduated tiers T0-T3, but this must be domain-scoped.

**Actionable:** Implement domain-scoped authority in Intercore. Store in `agent_authority` table: (agent_id, domain/module_glob, tier, earned_at, evidence_ids). Route and gate checks consult this table.

---

### Theme 3: Cost Must Be a First-Class Dimension, Not a Hidden Backend Metric

**Converges:** fd-velocity-forecasting, fd-dashboard-oversight, best-practices-researcher, repo-research-analyst
**Evidence:** OEE dashboards, P&L dashboards, manufacturing cost accounting

**Finding:** No mainstream PM tool (Jira, Linear, Asana) surfaces cost-per-task as a primary metric. This is the largest gap between software and AI factories.

**Why this matters:**
- In human teams, cost ~ developer salary × time. Cost is opaque and amortized.
- In AI factories, cost = tokens × rate + compute + API calls. Cost is direct, measurable, per-task.
- This makes cost a **better** primary metric than time for decision-making
- You should route tasks based on cost profile (send cheap tasks to cheap model, expensive tasks to expensive model)
- You should gate based on cost: skip plan-review if cost is low, always require approval if cost is high

**Demarch gap:** Demarch tracks cost via interstat (tokens spent per session) and has a cost baseline ($2.93/landable change). But:

- Routing ignores cost profiles (no distinction between Claude Opus and Haiku dispatch)
- Gating doesn't check "is this task within budget?" before approving
- Dashboard oversight doesn't show cost burn rate; only humans see interstat separately
- Phase budgets are fixed (brainstorm=80K, plan=150K) but don't adjust for epic size

**Actionable:**
1. Add cost-per-model to fleet-registry (currently has token/cost data, not per-model)
2. Routing table adds cost check: "if budget remaining < predicted cost, route to cheaper model or defer"
3. Dashboard L1 (ambient) shows "$47/$200 spent" as primary metric
4. Phase budgets scale with epic size: brainstorm_budget = max(baseline, 0.15 × epic_estimated_cost)

---

### Theme 4: Intent-Based Delegation Beats Procedural Task Specs

**Converges:** fd-scheduling-allocation, best-practices-researcher, learnings-researcher
**Evidence:** Military Auftragstaktik, hospital protocols, aviation CRM

**Finding:** Current beads enforce procedural specs: "edit file X, run test Y, commit with message Z." AI agents do better with intent + constraints.

**Procedural (current):**
```
1. Run perf profiler on endpoint Y
2. Find top 3 bottlenecks
3. Implement caching for query X
4. Run regression tests
```

**Intent-based (needed):**
```
Goal: Reduce p95 latency to <200ms (currently 1.2s)
Why: Revenue impact $X, customer Y blocked
Constraints: Don't change persistence layer, backward compat required
Success: p95 < 200ms on staging, all tests pass
Budget: 4h
Escalation: If analysis finds architectural blocker, escalate by hour 1
```

**Why this matters:**
- Agents can adapt when conditions differ (found bottleneck is different than expected)
- Agents can parallelize (spawn sub-agents to profile multiple endpoints)
- Agents can make intermediate decisions without round-tripping
- Failure modes are clearer (agent chose wrong approach vs. followed bad steps)

**Demarch gap:** Brainstorm and strategy docs are narrative (human-readable). Beads lack structured intent fields. When an agent claims a bead, it reads a markdown spec, not structured goal/constraints/success JSON.

**Actionable:** Add optional `goal`, `constraints`, `success_criteria`, `escalation_triggers` fields to beads. Migrate existing PRD/plan docs to populate these. Routing prefers intent-based beads for delegation.

---

### Theme 5: Quality Gates Must Be Multistage and Machine-Verifiable

**Converges:** fd-work-decomposition, fd-dashboard-oversight, best-practices-researcher
**Evidence:** VFX production pipelines (ShotGrid), manufacturing MES, hospital checklists

**Finding:** Software assumes "code reviewed, tests pass, deployed" is binary done-ness. AI agents need graduated gates with clear pass/fail criteria.

**Demarch's Phase Gates (current):**
```
plan-reviewed gate:
  - 2/3 review agents must pass
  - Based on qualitative judgment (readability, feasibility, etc.)
```

**Needed (VFX model):**
```
Self-check (agent):
  ✓ Compilation succeeds
  ✓ Existing tests pass
  ✓ Linter passes
  ✓ Type checker passes

Technical gate (automated):
  ✓ New tests cover changes
  ✓ Security scan passes
  ✓ No new vulnerabilities

Semantic gate (LLM judge):
  ✓ Changes implement stated intent
  ✓ No side effects or scope creep
  ✓ Code quality score ≥0.8

Acceptance gate (human, optional):
  ✓ Human spot-check or confidence > threshold
```

**Confidence-based acceptance:**
- High confidence (>0.9): auto-merge after deterministic gates pass
- Medium (0.7-0.9): LLM judge review, auto-merge if judge agrees
- Low (<0.7): human review required
- Unknown: quarantine (don't merge, hold for inspection)

**Demarch gap:** Demarch has phase gates but they're all qualitative (human review). No deterministic gates. No LLM judge. No confidence scoring on outputs. No quarantine for uncertain work.

**Actionable:**
1. Add deterministic gates: compile, test, lint, type-check (git hook)
2. Add semantic gate: call Claude with task spec + output, score intent alignment
3. Add confidence field to run outcomes; use for auto-merge vs. hold
4. Implement quarantine status for outputs with confidence < threshold

---

## Part 2: Five Actionable Insights Ranked by Impact

### 1. Implement Graduated Autonomy with Evidence-Backed Authority (Impact: 9/10)

**What:** Replace binary authority (can/cannot) with earned tiers (T0-T3) per domain.

**Why:** This is the bottleneck preventing 20+ parallel agents. Humans cannot review every output, and jumping to full automation destroys situational awareness. Graduated tiers allow agents to prove competence and humans to trust incrementally.

**Implementation:**
- Store agent_authority(agent_id, domain_glob, tier, earned_at) in Intercore
- Routing checks tier before dispatch; routes Propose-tier work through manual review, Deploy-tier work direct to merge
- Interspect tracks near-misses and overrides; uses evidence to auto-demote on regression
- Mycroft orchestrator enforces tier caps per agent

**Evidence:**
- Sheridan-Verplanck automation levels (fd-human-withdrawal)
- Aviation CRM trust calibration (fd-human-withdrawal)
- Military mission command (best-practices-researcher)
- Knight-Columbia autonomy framework (fd-human-withdrawal)
- Demarch's nascent Mycroft tier system (repo-research-analyst)

**Effort:** High (requires Interspect Phase 2 evidence loop + Mycroft core)
**Benefit:** Unlocks async operation; reduces principal oversight time by ~80% once baseline trust is established

**Current State in Demarch:** Planned in Mycroft v0.1; not yet implemented

---

### 2. Make Cost-Per-Task the Primary Dispatch and Gating Criterion (Impact: 8/10)

**What:** Every routing decision and phase gate checks cost: "Is this task worth its predicted cost? Can we afford it? Is there a cheaper path?"

**Why:** Token cost is measurable, predictable (distribution-shaped), and directly controllable via model selection. This is true for no other metric in software (time, quality, priority are all uncertain and indirect).

**Implementation:**
- Fleet registry stores cost profiles per (model, agent_config, task_type): p50/p85/p95 distributions
- Routing: "if budget < p85_cost, route to cheaper model or mark as budget-blocked"
- Gating: "if cost_to_date > 0.8 × budget and task not close to complete, escalate cost overrun"
- Dashboard L1: show spend rate vs. budget as primary metric (before agent count, completion %)

**Evidence:**
- Demarch cost baseline: $2.93/landable change, 785 sessions (repo-research-analyst)
- OEE cost analysis (fd-velocity-forecasting): execution efficiency is the binding constraint
- Finance dashboards (fd-dashboard-oversight): budget vs. actual, burn rate trend
- Manufacturing cost accounting (best-practices-researcher)

**Effort:** Medium (fleet-registry already has data; routing adds cost lookup; dashboard refactor)
**Benefit:** 15-25% cost reduction by shifting expensive tasks to cheaper models; better budget predictability

**Current State in Demarch:** Baseline tracked, but routing/gating don't use cost

---

### 3. Build Machine-Verifiable Quality Gates, Not Qualitative "Looks Good" Review (Impact: 7/10)

**What:** Replace "human reads output" with graduated deterministic → stochastic → human gates.

**Why:** Human review is the bottleneck (2025 DORA: agent execution is fast, review takes hours). Deterministic gates (tests pass, linter clean) scale. LLM judge gates (semantic correctness) are cheap relative to human review. Save human judgment for irreversible/high-blast-radius decisions.

**Implementation:**
- Deterministic gates: compile, test suite passes, linter, type checker, security scan (pre-commit hook)
- Stochastic gates: Claude-as-judge scores semantic correctness (intent alignment, no scope creep)
- Confidence scoring: output confidence = (deterministic_gates_pass) × (stochastic_gate_score)
- Routing to human review: only if confidence < threshold or action is irreversible

**Evidence:**
- VFX production pipeline stages (fd-work-decomposition, fd-dashboard-oversight)
- Manufacturing First Pass Yield (fd-work-decomposition)
- Hospital WHO checklist mandatory pause points (fd-human-withdrawal)
- Demarch phase gates (repo-research-analyst, learnings-researcher)

**Effort:** Medium (deterministic gates via git hook; LLM judge via Anthropic API; confidence scoring logic)
**Benefit:** 50%+ reduction in human review time; faster feedback loop; better signal on which tasks are risky

**Current State in Demarch:** Beads have phase gates (human review only); no deterministic gates; no confidence scoring

---

### 4. Support Two-Level Decomposition: Strategy → Claims-Time Breakdown (Impact: 7/10)

**What:** Epic/Sprint decomposition stops at the bead level. When a bead is claimed, the executing agent produces a sub-task dependency graph. This graph is not pre-planned, but discovered.

**Why:** Top-down decomposition assumes you know the shape of the work (you don't). Mid-execution decomposition adapts to discovered complexity. Best teams allocate 10-15% capacity for replanning; tools don't support it.

**Implementation:**
- Beads support `bd refine <parent_id>` command: agents propose new children during execution
- Refinements auto-merge if complexity increase < 20%; require approval if > 20%
- Replan checkpoints: at 25% and 50% of time budget, agent can request re-estimation
- Routing considers discovered decomposition: if task became 3x more complex, route sub-tasks to appropriate agents

**Evidence:**
- Manufacturing two-level planning: ERP vs. MES (best-practices-researcher)
- Hospital OR re-planning (best-practices-researcher, fd-scheduling-allocation)
- Demarch sprint → brainstorm → strategy → plan pipeline (learnings-researcher)
- Temporal continue-as-new pattern (framework-docs-researcher)

**Effort:** Low (new command + bead schema update + routing hook)
**Benefit:** 20% reduction in rework; better cost predictability; agents can self-parallelize

**Current State in Demarch:** Strategy produces breakdown; plan details it; but claims don't refine

---

### 5. Implement Graduated Phase Progression, Not Binary Gates (Impact: 6/10)

**What:** "Skip plan-review if cost < $5 AND task is in safe domain." Not "plan-review required for all."

**Why:** Demarch's phase gates are mandatory for all work (good: safety floor). But low-risk work (typo fix, comment addition) pays the same overhead as high-risk work (API change). Graduated progression saves tokens and speed.

**Implementation:**
- Gates have skip conditions: `skip_if: cost < $5 AND domain in (docs, tests) AND agent_tier >= Deploy`
- Blast-radius classification per bead: (reversible_spectrum, scope_level)
- Never-events (data deletion, secret commit, API break) always block, regardless of conditions
- Conditional approval: "Approve if output confidence > 0.9; escalate otherwise"

**Evidence:**
- Military irreversibility and blast-radius rules (fd-human-withdrawal)
- Hospital never-events (fd-human-withdrawal)
- NYSE circuit breakers: mandatory pause only at threshold, not always (fd-human-withdrawal)
- Manufacturing use-as-is with deviation (fd-work-decomposition)

**Effort:** Medium (gate rules as DSL in Intercore; blast-radius classification in beads)
**Benefit:** 10-20% speedup on low-risk work; humans focus on high-leverage decisions

**Current State in Demarch:** All phase gates mandatory; no skip conditions

---

## Part 3: Where Demarch Is Strong vs. Missing

### Demarch Has ✓

| Capability | Implementation | Maturity |
|-----------|-----------------|----------|
| Work tracking foundation | Beads + SSOT | ✓✓✓ Mature |
| Phase gating framework | Intercore phases + events | ✓✓ Solid |
| Cost measurement | interstat + fleet-registry | ✓✓ Good |
| Routing to handlers | clavain:route fast-path heuristics | ✓✓ Good |
| Domain-aware dispatch | flux-drive domain detection | ✓ Basic |
| Evidence collection | Interspect events + hooks | ✓ Emerging |

### Demarch Is Missing ✗

| Capability | Why Important | Status |
|-----------|---------------|--------|
| Graduated autonomy tiers | Cannot scale beyond 5 agents without burnout | Planned (Mycroft v0.1) |
| Cost-aware routing | Routing ignores budget and agent cost profiles | Not started |
| Domain-scoped authority | No distinction: "deploy all code" vs. "deploy only tests" | Interspect Phase 2 |
| Intent-based beads | Specs are narrative markdown, not structured intent+constraints | Design draft needed |
| Deterministic quality gates | Phase gates are all human-review; no auto-pass on tests | In brainstorm |
| Confidence scoring | No signal on which outputs are high vs. low quality | Not started |
| Claims-time decomposition | Agents cannot propose sub-beads during execution | Not started |
| Multi-resource scheduling | Doesn't consider API rate limits, file locks, review capacity | Interlock v1 partial |
| Cost-per-phase budgets | Budgets fixed (80K brainstorm) not scaled to epic size | Not started |
| Re-engagement protocol | No SBAR/decision-replay for re-entering after automation | Not started |

---

## Part 4: Tensions & Tradeoffs

### Tension 1: Automation vs. Situational Awareness

**Conflict:** Graduated tiers mean humans understand less about day-to-day decisions. High trust = low visibility = bad incident response.

**Resolution:** Implement mandatory re-engagement artifacts (SBAR format, decision replay, change-of-plan events). Out-of-the-loop is acceptable only if the loop can be re-joined in <5 minutes.

**Demarch action:** Add ICS Form 201-equivalent (context snapshot on-demand). Implement decision replay: "show me the decisions agent X made in the last 30 minutes with alternatives considered."

### Tension 2: Cost Optimization vs. Quality

**Conflict:** Cheapest model gets routed more work. But cheaper models fail more often, requiring rework (expensive in aggregate).

**Resolution:** Use OEE decomposition: track (availability, efficiency, land_rate) separately. If cheap model has 60% land rate but expensive model has 90%, net cost-per-successful-change favors expensive model.

**Demarch action:** Add land_rate (tasks landed / tasks attempted) to fleet-registry. Routing considers OEE, not just token cost.

### Tension 3: Parallelism vs. Coordination

**Conflict:** Parallel agents = more throughput, but coordination overhead grows quadratically (file conflicts, review queue saturation, API rate limits).

**Resolution:** Apply Theory of Constraints (DBR): identify the bottleneck (usually human review), buffer upstream (queue-ready work), rope downstream (limit work-in-progress to match review throughput).

**Demarch action:** Track per-stage WIP (agents-working, review-queue, CI-running, deployed). Alert when any stage hits cap. Rope controls agent dispatch rate.

### Tension 4: Upfront Planning vs. Discovered Replanning

**Conflict:** Planning costs tokens; replanning costs tokens. Do one or the other, not both.

**Resolution:** Allocate % of budget to each. Demarch allocates 20% to brainstorm + strategy + plan (upfront); reserve 10% for replanning (discovered).

**Demarch action:** Monitor actual replan frequency. If > 20% of tasks require mid-execution breakdown, increase upfront planning budget.

---

## Part 5: Implementation Roadmap (Ranked by Impact × Feasibility)

### Q2 2026 (High Impact, High Feasibility)

1. **Cost-aware routing** (Insight #2)
   - Add cost_tier to routing table
   - Fleet registry stores (model, task_type) → cost distribution
   - Routing defers budget-blocked work instead of routing to expensive model
   - Effort: 3 days | Impact: 8/10

2. **Deterministic quality gates** (Insight #3)
   - Add pre-commit hook: test, lint, type-check
   - Route human review only if deterministic gates fail
   - Effort: 2 days | Impact: 7/10

3. **Graduated phase skipping** (Insight #5)
   - Add skip_if DSL to phase gates
   - Never-events always block
   - Effort: 2 days | Impact: 6/10

### Q3 2026 (High Impact, Medium Feasibility)

4. **Graduated autonomy tiers** (Insight #1)
   - Implement Mycroft v0.1: T0-T3 per domain
   - Route based on tier; escalate high-risk work
   - Interspect v1 auto-demotes on incident
   - Effort: 10 days | Impact: 9/10

5. **Intent-based bead schema** (Insight #4)
   - Add goal, constraints, success_criteria fields
   - Migrate brainstorm/PRD docs to populate
   - Routing prefers intent-based beads
   - Effort: 5 days | Impact: 6/10

### Q4 2026 (Medium Impact, Medium Feasibility)

6. **Claims-time decomposition** (Insight #4)
   - bd refine command for agents to propose sub-tasks
   - Auto-merge if complexity increase < 20%
   - Effort: 4 days | Impact: 7/10

7. **Confidence scoring** (Insight #3)
   - Score outputs 0-1 (deterministic gates + semantic gate)
   - Auto-merge if > 0.9; hold if < 0.7
   - Effort: 3 days | Impact: 6/10

8. **Re-engagement protocol** (Insight #1)
   - SBAR-formatted incident brief
   - Decision replay for last N decisions
   - Right-seat/left-seat transition support
   - Effort: 8 days | Impact: 5/10

---

## Sources Map

### Core Domain Research

| Domain | Sources | Agent(s) |
|--------|---------|----------|
| **Manufacturing MES** | IBM MES guide, manufacturing execution theory | fd-work-decomposition, best-practices, learnings |
| **Military C2** | FM 5-0, MDMP, Auftragstaktik doctrine | fd-scheduling-allocation, best-practices, fd-human-withdrawal |
| **Hospital OR** | OR scheduling research, CRM training, WHO checklist | fd-scheduling-allocation, best-practices, fd-human-withdrawal |
| **Film Production** | Filmustage, Netflix dailies, CCPM | fd-velocity-forecasting, fd-work-decomposition |
| **Finance/Supply Chain** | P&L dashboards, demand sensing, alpha decay | fd-velocity-forecasting, fd-dashboard-oversight |

### Software Frameworks

| Framework | Patterns | Agent(s) |
|-----------|----------|----------|
| **Linear** | Issue model, cycle management | framework-docs-researcher |
| **Jira** | Automation rules, state machines | framework-docs-researcher |
| **Temporal** | Durable execution, deterministic replay | framework-docs-researcher |
| **Airflow/Dagster** | DAG scheduling, asset lineage | framework-docs-researcher |
| **CrewAI/LangGraph** | Multi-agent delegation patterns | framework-docs-researcher |

### Internal (Demarch)

| Artifact | Coverage | Agent(s) |
|----------|----------|----------|
| Beads workflow | Decomposition, claiming, phase gates | repo-research-analyst, learnings |
| Route.md | Routing table, classification | repo-research-analyst, git-history |
| Intercore / Interspect | Event-driven gating, evidence collection | repo-research-analyst, learnings |
| Fleet registry | Cost tracking, agent profiles | repo-research-analyst, learnings |
| Brainstorm/PRD/Plan docs | Narrative problem-solving | repo-research-analyst, learnings |

---

## Glossary

- **Beads:** Demarch's work-tracking unit (like Jira issue, but durable)
- **Phase gates:** Mandatory progression checks (brainstorm → strategy → plan → work)
- **Interspect:** Demarch's evidence collection & verdict system
- **Mycroft:** Planned fleet orchestrator (handles 20+ agents with graduated tiers)
- **OEE:** Overall Equipment Effectiveness (availability × efficiency × quality)
- **DBR:** Drum-Buffer-Rope constraint management (manufacturing)
- **Graduated autonomy:** Tiers of authority earned through demonstrated competence
- **Blast radius:** Scope and reversibility of an action (determines approval requirements)
- **SBAR:** Situation, Background, Assessment, Recommendation (hospital handover protocol)

---

## Conclusion

The research converges on a clear architectural pattern for AI factory orchestration:

1. **Accept that humans cannot review every output.** Graduated tiers, confidence scoring, and deterministic gates do the work.
2. **Make cost-per-task the primary decision signal.** Cost is measurable, controllable, and predictive in ways time and quality are not.
3. **Design for replanning, not just planning.** Decomposition happens in two phases: upfront (strategy) and claims-time (discovered).
4. **Separate intent from implementation.** Tell agents what to achieve, not how. This enables adaptation and parallelization.
5. **Implement multi-stage quality gates:** deterministic (tests pass) → stochastic (semantic correctness) → human (irreversible decisions).

Demarch has the foundation (beads, routing, phase gates, cost tracking). The gaps are not architectural, but graduated-trust infrastructure. Mycroft, Interspect Phase 2, and cost-aware routing will unlock the transition from "augmented human engineers" to "autonomous software factory with human oversight."

**Estimated Impact of Roadmap:** Current bottleneck is human review bandwidth. With graduated autonomy + deterministic gates + confidence scoring, human review per output drops from 15-30 minutes to 1-2 minutes (for exceptions only). This enables scaling from 3-5 parallel agents to 20+ without increasing human burden.

---

*Research conducted by 10 agents across 5 focused domains and 5 discovery threads. Compiled 2026-03-19.*
