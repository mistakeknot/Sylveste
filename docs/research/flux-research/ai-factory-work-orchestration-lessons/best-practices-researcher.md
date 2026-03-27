# AI Factory Work Orchestration: Best Practices from Diverse Domains

**Research Date:** 2026-03-19
**Researcher:** Best Practices Analysis Agent
**Scope:** Cross-domain lessons from software PM, military C2, manufacturing, healthcare, autonomous systems, film production, and SRE

---

## Executive Summary

Work orchestration for AI agent software factories is fundamentally a **distributed coordination and delegation problem**, not primarily a task-tracking problem. The best practices come not from software PM tools (Jira/Linear), but from domains that handle *dynamic*, *uncertain*, *high-consequence* work: military command structures, manufacturing execution systems, hospital operating rooms, and autonomous vehicle fleets.

**Key insight:** The gap between Jira/Linear and what you need is not a gap in *tracking* capability—it's a gap in **authority delegation**, **uncertainty handling**, and **real-time replanning**.

---

## 1. Authority Delegation: Mission Command vs. Instruction Execution

### The Military Lesson: Mission-Type Orders

**Source:** [Air Force Doctrine Publication 1-1 on Mission Command](https://www.doctrine.af.mil/Portals/61/documents/AFDP_1-1/AFDP%201-1%20Mission%20Command.pdf), [Army Mission Command Doctrine](https://www.army.mil/article/106872/understanding_mission_command)

Military command structures use **mission-type orders** (also called *mission-type tactics*), not detailed instruction lists:

- **Commander states:** "What" (objective) and "why" (purpose and commander's intent), NOT "how"
- **Subordinate leaders decide:** How to accomplish the mission within their delegated authority
- **Commander's intent** defines success conditions, timeframe, constraints, and key tasks—not the specific path
- **Conditions-based authorities** grant temporary, enduring, or contingency-triggered delegation rights

**Why this matters for AI agents:**

Traditional PM tools (Jira) enforce a **downstream trust model**: "Manager writes detailed steps → Executor follows steps → Report back." This breaks down when agents encounter uncertainty or must make trade-off decisions that weren't pre-planned.

Mission command enforces an **upstream intent model**: "Leadership defines outcome + constraints → Agents commit to outcome and self-organize approach → Escalate only blocked assumptions."

### Concrete Implementation

- **Beads should describe "intent + constraint" not "steps":**
  ```
  Goal: Implement feature X to reduce latency by ≥20% for use case Y
  Why: Customer Z reports slowness; revenue impact is $X
  Constraints: Can't change persistence layer; must maintain backward compatibility
  Success metrics: Latency <Yms for Z's workload; regression test suite passes
  Time budgets: Analysis (2h), Implementation (4h), Testing (1h)
  Escalation triggers: If analysis finds architectural blocker, escalate before hour 1 ends
  ```

- **NOT:**
  ```
  1. Run perf profiler on endpoint Y
  2. Find top 3 bottlenecks
  3. Implement caching for query X
  4. Run regression tests
  5. Report results
  ```

- **Authority grants should be explicit:** "Agent has authority to make decisions on internal optimization; must escalate any schema changes or load shedding."

---

## 2. Hierarchical Decomposition: WBS + MES Refinement Pattern

### The Manufacturing Lesson: Two-Level Planning

**Sources:** [Manufacturing Execution System Overview](https://www.ibm.com/think/topics/mes-system), [Work Breakdown Structure Best Practices](https://www.projectmanager.com/guides/work-breakdown-structure)

Manufacturing distinguishes sharply between:

1. **ERP level (Enterprise Resource Planning):** Long-term capacity planning, strategic scheduling, high-level work orders derived from customer demand
2. **MES level (Manufacturing Execution System):** Real-time shop-floor decomposition, capacity-aware sequencing, material/tool allocation, dynamic adjustment to constraints discovered at runtime

**Key insight:** You don't plan at the MES level in advance. You only *refine* high-level plans into executable tasks when you have real-time visibility.

MES **automatically decomposes** high-level work orders into:
- Resource allocation (which machine/worker, time block)
- Dependency satisfaction (materials ready? prerequisites done?)
- Sequence optimization (reorder to minimize idle time, changeovers)
- Real-time constraint handling (react to breakdowns, urgencies)

### Concrete Implementation

**Sylveste's three-tier model should align:**

1. **Epic/Sprint (ERP equivalent):** "Implement modular agent architecture refactor (2-week sprint)"
   - User story density, team capacity, deadline
   - NO task breakdown yet

2. **Bead (Work order):** "Refactor API handler package to support plugin API v2"
   - Clear outcome + constraint
   - 1-2 day time horizon
   - Decomposition happens when owner claims it

3. **Sub-bead or session plan (MES equivalent):** At claim time, agent produces:
   - Dependency graph (what must be done first?)
   - Resource needs (does it need code review? design review?)
   - Uncertainty points (what could block us?)
   - Replan checkpoints (when do we re-estimate?)

**Why MES two-level planning matters:**
- You don't know the actual task shape until someone who understands the codebase starts reading it
- Best teams **explicitly plan for replanning**—they allocate 10-15% of sprint capacity to rework/surprises
- Tools should support "checkpoint replanning" at 25% and 50% of time budget, not just waterfall deadline

---

## 3. Uncertainty Handling: The OR Scheduling Model

### The Hospital Lesson: Robustness vs. Efficiency Trade-Off

**Source:** [Operating Room Scheduling Under Uncertainty](https://pmc.ncbi.nlm.nih.gov/articles/PMC12358003/)

Hospital OR scheduling research quantifies the **robustness-efficiency trade-off** precisely:

- **Without robustness planning:** 100% resource efficiency, but schedule disruption is massive
- **With robustness planning (6% efficiency loss):**
  - Overtime reduced by 68%
  - Schedule adjustments on day-of reduced by 13%
  - System stays predictable

**Key sources of uncertainty:**
- Surgery duration variance (estimate ±40% error)
- Emergency cases arriving unpredictably
- Resource unavailability (staff absence, equipment issues)
- Sequential work reveals blockers

**OR scheduling techniques:**
- **Slack insertion:** Allocate 15-20% buffer time between scheduled events
- **Capacity underutilization:** Leave 10-15% of OR time unscheduled for emergencies
- **Stochastic optimization:** Plan for p50 duration, but allocate for p90 to absorb variance
- **Dynamic rescheduling:** Real-time replan when actual performance diverges >threshold

### Concrete Implementation for AI Agents

- **Time budgets should include explicit slack:**
  ```
  Task: Code change (estimate 2h)
  Allocated time: 2.5h (including 20% uncertainty buffer)
  Escalation trigger: If running >15 min behind by 50% mark, pause and reassess
  ```

- **Don't schedule agent capacity at 100%:**
  - If team has 40 hours/week capacity, assign 32-36 hours of committed work
  - Reserve 4-8 hours for rework, escalations, urgent bugs
  - Treat buffer time as "unallocated capacity," not "slack work"

- **Build stochastic models for agent speed:**
  - Track actual duration vs. estimate across 30+ similar tasks
  - Use p50 estimate for display; p90 for planning
  - Recalibrate monthly as agent improves

---

## 4. Real-Time Coordination: Decentralized Task Allocation

### The Autonomous Fleet Lesson: Market-Based Assignment

**Sources:** [Autonomous Vehicle Fleet Management](https://www.digitaldividedata.com/blog/autonomous-fleet-management-for-autonomy), [Decentralized Coordination in Open Vehicle Fleets](https://arxiv.org/html/2401.10965v1)

AV fleet management uses **decentralized, market-based task allocation** instead of centralized dispatch:

- **Pull model, not push:** Vehicles actively bid on tasks (considering proximity, fuel, urgency)
- **Bidding factors:** Priority, distance, current load, expected completion time
- **No central bottleneck:** Dispatcher doesn't compute assignments; vehicles negotiate locally
- **Real-time adaptability:** Vehicles can drop tasks if blocked; reassign on the fly

Why this matters: **Centralized dispatchers become bottlenecks under load.** When a human needs to decide which agent gets which task, you create a serialization point that kills parallelism.

### Concrete Implementation

- **Don't let orchestrator be a "task assigner."** Instead:
  - Post work item ("Bead X is available, takes ~4h, requires code review")
  - Agents pull work when ready (no push, no assignment)
  - Agent commits (claims bead) with expected completion time
  - Orchestrator only intervenes if claimed agent becomes unresponsive

- **Build "capability declaration" as first-class:**
  - Each agent declares: "I handle Go backend; Python scripting; basic testing"
  - Work items declare: "Requires Python + testing + code review"
  - Agents can see matching work immediately without orchestrator matching

- **Enable multi-agent negotiation for complex tasks:**
  - Big bead requires "2 reviewers + 1 implementer"
  - First agent claims "implementer" role
  - System shows available reviewers; they can self-assign
  - No central choreography needed

---

## 5. Hierarchical Creative Work: VFX Pipeline Handoff Model

### The Film Industry Lesson: Staged Handoffs with Reversions

**Sources:** [VFX Pipeline Workflow](https://www.lucidlink.com/blog/vfx-pipeline), [Autodesk Flow Production Tracking](https://www.autodesk.com/products/flow-production-tracking/overview)

VFX pipelines handle *creative* work (not rote tasks) with tight handoff discipline:

- **Pipeline stages are sequential:** Asset creation → Rigging → Animation → Lighting → Rendering → Compositing
- **Each stage has clear "definition of done":** "Animation approved by lead → hand off to lighting"
- **Reversions are first-class:** Compositing finds a problem → animation rework → back to compositing
- **Tracking happens at shot + task level, not subtask level:**
  - Don't track "fix arm rig" and "fix leg rig" separately
  - Track "Shot 47 in animation stage" and let the stage manager handle sequencing within

- **All information flows through one system:** tracking + media playback + notes + task status
- **Real-time sync:** Everyone sees the same current state (not email thread history)

### Concrete Implementation for Code/AI Work

- **Define clear "stage gates":**
  ```
  Analysis → Implementation → Review → Testing → Merge

  Analysis done when: Design doc approved, blockers identified, time estimate revised
  Implementation done when: Code compiles, runs locally, auto-tests pass
  Review done when: 2 approvals, CI passes
  Testing done when: Integration tests pass, regression clean
  Merge done when: All above + bead marked closed
  ```

- **Don't micro-task within stages:**
  - Bad: "Analyze data structures (1h) → Analyze error paths (1h) → Design caching layer (1h)"
  - Good: "Complete analysis phase; estimate remaining work; list blockers"

- **Make reversions explicit:**
  - Review finds issue → status becomes "revision-needed"
  - Implementer fixes → moves back to "review" (not "implementation" again)
  - Track revision count; if >2, escalate to architecture

---

## 6. Intelligent Automation: Levels of Automation + Escalation

### The AI Governance Lesson: Automation Bias and Escalation Criteria

**Sources:** [Automation Bias and Deterministic Solutions](https://medium.com/@Forsaken/automation-bias-and-the-deterministic-solution-why-human-oversight-fails-ai-dc1db35e0acf), [Agentic AI in HR](https://www.phenom.com/blog/agentic-ai-in-hr), [EDPS Human Oversight of Automated Decision-Making](https://www.edps.europa.eu/data-protection/our-work/publications/techdispatch/2025-09-23-techdispatch-22025-techdispatch-22025-human-oversight-automated-making_en)

**The core problem:** "Meaningful oversight requires both time and support; without those, even the best-intentioned humans become bystanders."

**Five levels of automation (Sheridan, adapted):**

1. **Manual:** Human makes all decisions
2. **Decision-support:** System proposes; human decides
3. **Auto-execute if approved:** System proposes and executes if human approves within timeframe
4. **Auto-execute and report:** System executes; human reviews outcome
5. **Fully autonomous:** System executes; human intervenes only on exception

**The critical insight:** Humans can't override automated decisions they didn't understand. Escalation criteria must be **pre-defined and checked mechanically**, not left to human judgment.

### Concrete Implementation

- **Define escalation criteria explicitly for each task type:**
  ```
  Code change escalation if:
  - Affects >10 files
  - Touches security/auth code
  - Performance impact unclear
  - Requires load shedding or circuit breaking
  - Reviewer feedback >2 rounds
  - Merge conflict in core modules
  ```

- **Don't rely on "humans will notice if something is wrong."** Instead:
  - **Auto-escalate to human** if any escalation criterion is met
  - Prevent agent from proceeding past escalation point without approval
  - Log escalations; review monthly for patterns (are criteria right?)

- **Build "explain your decision" into automation:**
  - If agent chooses approach X over Y, require: "Why X: [reasoning]. Why not Y: [reasoning]"
  - If reasoning is weak, cascade to escalation
  - If reasoning is strong but outcome is wrong, update training

---

## 7. SRE Incident Orchestration: Dynamic Runbooks

### The SRE Lesson: Runbook as State Machine, Not Checklist

**Sources:** [Intelligent Runbooks for Incident Management](https://www.cutover.com/blog/intelligent-runbooks-automation-transform-incident-management), [Rootly Automation Workflows](https://rootly.com/sre/rootly-automation-workflows-explained-boost-sre-reliability)

Traditional runbooks are static checklists. Modern SRE uses **dynamic runbooks** as state machines:

- **Triggered by specific conditions:** Alert fires → runbook_metric_spike fires
- **Orchestrate across tools:** Checks Datadog → escalates to PagerDuty → opens Jira ticket → messages Slack
- **Conditional logic:** If error_rate > 10%, try auto-remediation; if still failing after 2 min, page oncall
- **Self-healing:** Common issues auto-remediate before human sees them
- **Human-in-loop:** Escalations wait for human approval or timeout and proceed anyway (configurable)

**Key practice:** Runbooks are continuously refined by post-mortems. Each incident teaches the runbook.

### Concrete Implementation for AI Work

- **Beads should have "runbook-like" contingency plans:**
  ```
  Bead: "Implement API endpoint"
  Happy path: Analysis (1h) → Implementation (3h) → Review (1h) → Merge

  Contingency: "If code review finds >5 issues, escalate to architecture"
  Contingency: "If integration tests fail, gather logs → revert → post-mortem"
  Contingency: "If estimate drifts >50%, pause at 50% checkpoint and reassess"
  ```

- **Auto-escalate via runbook logic, not human judgment:**
  - Bead clock hits 50% of time budget → system auto-checks: "Are we on track?"
  - If not, automatically escalates (pauses agent, alerts manager)
  - Human decides: extend time, reduce scope, or abort and retry

---

## 8. Progressive Complexity: Phased Automation Rollout

### The Integration Lesson: Adopt Mature Tools, Build Around Them

**Key memory from Sylveste project:** "Check assessment docs before building infrastructure. We rebuilt session search when CASS was already assessed as 'adopt'."

For multi-agent orchestration, **don't build custom orchestration logic**. Instead:

- **Phase 1 (Foundation):** Use beads + human scheduling (current Sylveste state)
  - Beads track work intent + constraints
  - Humans (team lead) assign beads to agents
  - Sessions log progress against beads

- **Phase 2 (Pull model):** Add agent work-claiming
  - Agents see available beads; self-claim when ready
  - No scheduler needed; agents auto-balance

- **Phase 3 (Uncertainty handling):** Add checkpoints + contingencies
  - Beads specify "check at 25%, 50%, 75%"
  - Agent reports actual progress at checkpoints
  - System auto-escalates if drifting >threshold

- **Phase 4 (Coordination):** Add multi-agent dependencies
  - Beads can declare: "Blocks: X; Blocked by: Y"
  - System prevents claiming until dependencies ready

- **Phase 5 (Learning):** Add cost estimation feedback
  - Track actual time vs. estimate per task type
  - Use CASS analytics to find patterns
  - Adjust estimates monthly

**Don't jump to Phase 5 before Phase 2 is solid.** Each phase uncovers what the next phase actually needs.

---

## 9. Cost and Efficiency Trade-Offs: Quantified Models

### The Manufacturing Lesson: Don't Optimize for 100% Efficiency

From MES research and hospital OR scheduling:

- **Pure efficiency targets (95%+ utilization) are impossible to maintain.**
  - They fail catastrophically under any disruption (change request, bug, design flaw)
  - Rework and replanning cost more than the efficiency gain

- **Industry baseline: 75-85% sustainable utilization**
  - Leaves 15-25% for rework, escalations, learning, unplanned work
  - Emergent issues can be absorbed without cascading delays

- **Cost impact:** 6% efficiency loss (95% → 89%) → 68% reduction in overtime, 13% fewer rework cycles

**Application to AI agents:**
- If you estimate a task at 4 hours, allocate 5 hours (20% buffer)
- If team has 40 hours capacity, commit to 32 hours of work per week
- Treat unallocated time as contingency, not "slack work" or extra sprint capacity

---

## 10. Learning and Feedback: Post-Mortem-Driven Improvement

### The SRE Lesson: Blameless Post-Mortems Update Runbooks

From SRE incident management:

- After every significant escalation or rework cycle, conduct a brief post-mortem
- Question: "What assumption was wrong? How do we detect this sooner next time?"
- Output: Updated runbook, updated estimates, updated escalation criteria
- This is how systems improve over months (not through theoretical analysis)

### Concrete Implementation

**Monthly Sylveste review cycle:**
1. Query CASS: Sessions that had escalations + cost overruns
2. Per issue type: "Why did this cost more/escalate?"
3. Update: Beads template, agent playbooks, time estimates
4. Review: Escalation criteria—too aggressive (false positives) or too loose (missed issues)?

---

## 11. Communication and Visibility: Single Source of Truth

### The VFX Pipeline Lesson: One System for All Coordination

VFX teams use one tool (e.g., ShotGrid) that combines:
- Work tracking (what stage is each shot in?)
- Media playback (can I see the current state?)
- Notes (what feedback exists?)
- Dependencies (what blocks this?)

Not email threads, Slack discussions, separate wikis.

**For Sylveste:**
- Beads should be the single source of truth for work state
- Session logs should feed back into beads (actual progress)
- Notes should be in beads comments, not Slack
- Dependencies tracked in beads links, not mental models

---

## 12. Concrete Anti-Patterns to Avoid

### Anti-Pattern 1: "Assign tasks from a queue"
- **Why it fails:** Creates bottleneck; orchestrator becomes single point of failure
- **Alternative:** Agents pull work; orchestrator only enforces constraints (no agent should claim work that violates constraints)

### Anti-Pattern 2: "Detailed step-by-step bead decomposition"
- **Why it fails:** Pre-planned breakdowns are wrong; time estimates for steps are guesses
- **Alternative:** Bead states outcome + constraint; agent produces plan on claim

### Anti-Pattern 3: "100% utilization target"
- **Why it fails:** No room for rework; any surprise cascades into delay
- **Alternative:** Target 75-85%; measure unplanned work; if >20% of sprint is unplanned, capacity estimates are off

### Anti-Pattern 4: "Human oversight via manual review"
- **Why it fails:** Humans don't have time; they become rubber-stamps
- **Alternative:** Pre-defined escalation criteria; system auto-escalates; human approves/rejects (explicit decision)

### Anti-Pattern 5: "Keep runbook knowledge in Slack/email"
- **Why it fails:** New agents can't learn; runbooks never improve
- **Alternative:** Update playbooks monthly based on post-mortems; require agents to read current playbook before claiming similar work

---

## Summary: Three Shifts for AI Factory Orchestration

### Shift 1: From Instruction to Intent
- Stop writing "do X, then Y, then Z"
- Start writing "achieve outcome X under constraint Y"
- Let agents figure out how, escalate if blocked

### Shift 2: From Centralized Dispatch to Distributed Claiming
- Stop assigning tasks from a queue
- Let agents see work and claim when ready
- Orchestrator enforces constraints, not choreography

### Shift 3: From Static Plans to Dynamic Replanning
- Don't expect upfront estimates to be accurate
- Build checkpoints (25%, 50%, 75%) where you reassess
- Use actual performance to update estimates
- Treat uncertainty explicitly (buffers, escalation criteria)

---

## References and Sources

**AI Agent Orchestration:**
- [Microsoft AI Agent Orchestration Patterns](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns)
- [LangGraph Agent Framework](https://www.langchain.com/langgraph)
- [CrewAI Multi-Agent Platform](https://crewai.com/)
- [KDnuggets Top 7 AI Agent Orchestration Frameworks](https://www.kdnuggets.com/top-7-ai-agent-orchestration-frameworks)

**Software PM Tools:**
- [Jira vs Linear Comparison (Atlassian)](https://www.atlassian.com/software/jira/comparison/jira-vs-linear)
- [Linear vs Jira (ClickUp)](https://clickup.com/blog/linear-vs-jira/)

**Manufacturing & Production Planning:**
- [IBM MES Overview](https://www.ibm.com/think/topics/mes-system)
- [GE Vernova MES Guide](https://www.gevernova.com/software/blog/manufacturing-execution-systems-mes-comprehensive-guide)
- [TechTarget MES Tips](https://www.techtarget.com/searcherp/feature/Tips-for-manufacturing-production-planning-and-scheduling-with-MES)

**Military Command & Control:**
- [Air Force Doctrine Publication 1-1 Mission Command](https://www.doctrine.af.mil/Portals/61/documents/AFDP_1-1/AFDP%201-1%20Mission%20Command.pdf)
- [Army Understanding Mission Command](https://www.army.mil/article/106872/understanding_mission_command)
- [Wikipedia Mission-Type Tactics](https://en.wikipedia.org/wiki/Mission-type_tactics)

**Healthcare OR Scheduling:**
- [PMC Operating Room Scheduling Analysis](https://pmc.ncbi.nlm.nih.gov/articles/PMC12358003/)
- [Springer Comprehensive OR Scheduling Review](https://link.springer.com/article/10.1007/s12351-024-00884-z)

**Autonomous Vehicle Fleet Management:**
- [Digital Divide Data AV Fleet Management](https://www.digitaldividedata.com/blog/autonomous-fleet-management-for-autonomy)
- [Decentralized Coordination in Open Vehicle Fleets (arXiv)](https://arxiv.org/html/2401.10965v1)

**Film/VFX Production:**
- [LucidLink VFX Pipeline Guide](https://www.lucidlink.com/blog/vfx-pipeline)
- [Autodesk Flow Production Tracking](https://www.autodesk.com/products/flow-production-tracking/overview)

**Automation and Oversight:**
- [Automation Bias and AI Oversight (Medium)](https://medium.com/@Forsaken/automation-bias-and-the-deterministic-solution-why-human-oversight-fails-ai-dc1db35e0acf)
- [EDPS Human Oversight of Automated Decision-Making](https://www.edps.europa.eu/data-protection/our-work/publications/techdispatch/2025-09-23-techdispatch-22025-techdispatch-22025-human-oversight-automated-making_en)

**SRE and Incident Orchestration:**
- [Cutover Intelligent Runbooks](https://www.cutover.com/blog/intelligent-runbooks-automation-transform-incident-management)
- [Rootly Automation Workflows](https://rootly.com/sre/rootly-automation-workflows-explained-boost-sre-reliability)

**Project Management Fundamentals:**
- [Work Breakdown Structure (ProjectManager.com)](https://www.projectmanager.com/guides/work-breakdown-structure)
- [WBS Wikipedia](https://en.wikipedia.org/wiki/Work_breakdown_structure)

**Multi-Agent Systems Research:**
- [MARL Task Allocation Survey (Springer AI Review)](https://link.springer.com/article/10.1007/s10462-025-11340-5)
- [Multi-Agent RL for Smart Factories (Frontiers)](https://www.frontiersin.org/journals/robotics-and-ai/articles/10.3389/frobt.2022.1027340/full)

**Resilience & Chaos Engineering:**
- [Microsoft Azure Chaos Engineering Guide](https://azure.microsoft.com/en-us/blog/advancing-resilience-through-chaos-engineering-and-fault-injection/)
- [Google Cloud Chaos Engineering](https://cloud.google.com/blog/products/devops-sre/getting-started-with-chaos-engineering)

---

<!-- flux-research:complete -->
