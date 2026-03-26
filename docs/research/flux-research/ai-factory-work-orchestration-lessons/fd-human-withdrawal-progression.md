# Human Withdrawal Progression: From Execution to Pure Oversight

**Research question:** What governance, trust-calibration, and authority-delegation models enable a human principal to progressively withdraw from execution into pure oversight -- what existing tools support, where they stall, and what is needed?

---

## 1. Sheridan-Verplanck Levels of Automation Applied to AI Factory Stages

### The Original Taxonomy

Sheridan and Verplanck (1978) defined ten levels of automation for human-computer authority sharing, from full manual control to full autonomy:

| Level | Description | AI Factory Analog |
|-------|-------------|-------------------|
| 1 | Human does everything | Human writes code, runs tests, deploys |
| 2 | Computer offers alternatives | Agent suggests approaches; human picks and executes |
| 3 | Computer narrows to a few | Agent filters to 2-3 viable approaches |
| 4 | Computer suggests one | Agent recommends a single approach with rationale |
| 5 | Computer executes if human approves | Agent generates PR; human reviews and merges |
| 6 | Computer executes; human can veto | Agent merges after timeout unless human objects |
| 7 | Computer executes; informs human | Agent merges and deploys; human gets notification |
| 8 | Computer executes; informs if asked | Agent acts silently; human queries status when curious |
| 9 | Computer informs if it decides to | Agent reports only anomalies or policy-significant events |
| 10 | Computer acts autonomously | Full autonomy; no human in loop |

### Parasuraman-Sheridan-Wickens Refinement

Parasuraman, Sheridan, and Wickens (2000) refined this into a two-dimensional model: automation can be applied independently to four information-processing stages -- (1) information acquisition, (2) information analysis, (3) decision and action selection, (4) action implementation -- each at varying levels. This is critical for AI factory design because **a workflow engine should not uniformly automate all stages**. An agent might operate at Level 7 for information gathering (scan logs, find relevant code) while operating at Level 5 for deployment (execute only with approval).

### Endsley's Out-of-the-Loop Warning

Endsley and Kiris (1995) demonstrated that the out-of-the-loop performance problem -- where operators lose situation awareness and cannot effectively intervene when automation fails -- is significantly worse under full automation than under intermediate levels. The implication for AI factories: **jumping from Level 1 to Level 7+ destroys the principal's ability to intervene effectively during failures**. A workflow engine must implement the intermediate levels (3-6) as genuine operational modes, not just waypoints on a slider.

### What a Workflow Engine Needs

- **Per-stage automation levels.** The engine should allow different automation levels for different stages of the same workflow: high automation for information gathering and analysis, lower for decision selection and action implementation.
- **Automation level as explicit configuration, not emergent behavior.** Each workflow step should declare its automation level. Today's tools (GitHub Actions, CI/CD) have binary gates (manual approval or not). There is no concept of "suggest and wait" (Level 4) vs. "execute unless vetoed within N minutes" (Level 6).
- **Level transitions as first-class events.** When a workflow moves from Level 5 to Level 6 for a class of tasks, that transition should be auditable, reversible, and triggered by evidence (e.g., N successful completions at Level 5).

---

## 2. Approval Mechanisms: What Scales and What Bottlenecks

### Software Development Tools

**Jira** offers approval workflows through Service Desk (since v3.2) and deployment gating. Single-approver flows work well; multi-approver chains are awkward because Jira cannot provide approvers with the exact context of what they are approving. Custom statuses ("Awaiting Approval," "Review In Progress," "Review Complete") must be manually configured per workflow scheme, and these schemes diverge across teams as organizations scale.

**Asana** supports approval tasks and multi-step pipelines with automatic dependency adjustment. However, approval tasks are binary (approved / not approved) -- there is no concept of conditional approval ("approved for staging, blocked from production") or graduated sign-off.

**GitHub** pull request reviews are the most mature approval mechanism for code, but they assume a human reviewer with full context. When AI agents generate PRs at volume, code review becomes the primary bottleneck. GitHub's CODEOWNERS and branch protection rules are the closest thing to graduated authority, but they operate at the repository level, not at the semantic level (e.g., "this change touches payment logic").

### Film Production Sign-Off Chains

Film VFX pipelines offer a more sophisticated model. Work flows through structured stages (layout, animation, lighting, compositing), with **dailies reviews** serving as lightweight approval gates. A shot is reviewed by the VFX supervisor before being elevated to the director. This two-tier review is more efficient than flat approval because:

1. The supervisor filters out clearly unfinished work (high-volume, low-stakes review).
2. The director reviews only supervisor-approved work (low-volume, high-stakes review).

Netflix's dailies best practices formalize this: work is screened at department level first, then elevated to creative leads, then to director-level review only when it meets a quality threshold.

### What Scales

- **Tiered review** (VFX model): low-stakes decisions filtered by automated or junior review before reaching the principal. An AI factory should implement tiered review where automated checks (tests pass, no security issues, diff size within bounds) serve as the first tier, with human review reserved for semantic or strategic decisions.
- **Time-bounded veto** (Level 6 automation): instead of requiring affirmative approval, allow actions to proceed after a configurable timeout unless vetoed. This eliminates the bottleneck of waiting for approval while preserving the ability to intervene.
- **Semantic routing of review**: route review requests based on blast radius, not just file paths. A one-line config change to a payment threshold needs more scrutiny than a 500-line documentation update.

### What Bottlenecks

- **Flat approval queues**: treating all changes as equally review-worthy creates backlogs.
- **Context-free approval**: approvers seeing a diff without understanding intent, alternatives considered, and blast radius cannot make fast decisions.
- **Single-approver models**: one human reviewing all agent output does not scale beyond ~10 changes/day.

---

## 3. Trust Calibration Feedback Loops

### Aviation CRM (Crew Resource Management)

Aviation CRM, developed after accidents caused by authority gradients in cockpits, provides the foundational model for trust calibration between humans and automation. Key mechanisms:

- **Bidirectional communication**: for automation to function as a teammate, it must communicate its state, confidence, and limitations -- not just its outputs. Transparency enables trust calibration.
- **Structured challenge protocols**: CRM trains crew to challenge automation (and each other) using graduated assertion. "I notice..." then "I am concerned that..." then "I believe we should..."
- **Post-flight debriefs**: systematic review of automation performance, including cases where automation was correctly overridden, incorrectly overridden, or should have been overridden but was not.

The key insight from CRM: **trust calibration requires both positive and negative feedback**. An AI factory that only reports failures will drive over-intervention; one that only reports successes will drive complacency.

### Nuclear Industry Near-Miss Reporting

The IAEA's near-miss and low-level event reporting system (TECDOC-668, Safety Reports Series No. 73) identifies a critical barrier: **organizational culture suppresses reporting**. Many influences of organizational and individual origins tend to conceal human errors, resulting in loss of information on near misses. Trust in the reporting system itself must be built before the system can calibrate trust in automation.

Nuclear plants address this through:
- **No-blame reporting policies**: separating reporting from performance evaluation.
- **Event taxonomy**: classifying events by severity, root cause, and systemic factors -- not just by outcome.
- **Structured simulator debriefs**: operators replay scenarios in simulators and debrief with instructors, focusing on decision points rather than outcomes.

### AI Factory Analogs

An AI factory implementing trust calibration needs:

1. **Agent confidence reporting**: every agent output should carry a confidence signal -- not a probability, but structured metadata: "I found 3 similar patterns in the codebase," "I am unsure about the test coverage for this change," "This touches a module I have not seen before."

2. **Near-miss capture**: when a human reviewer catches an error, the system should capture not just the correction but the failure mode. Was it a hallucination? A misunderstanding of requirements? A correct change in the wrong context? This is the analog of nuclear near-miss reporting.

3. **Calibration dashboard**: track the ratio of human overrides to agent proposals over time, broken down by task type. A rising override rate on a specific task type signals the agent is miscalibrated for that domain. A falling override rate signals readiness for higher automation levels.

4. **Structured retrospectives**: periodic review of agent performance that examines not just failures but also correct interventions (where human override was justified) and missed interventions (where the human approved something that later caused problems). CRM calls these "line-oriented safety audits."

---

## 4. Irreversibility and Blast Radius Bounding

### Military Rules of Engagement (ROE)

Military ROE provides the most developed model for bounding authority by consequence. The core structure:

- **Authority is tiered by consequence severity**: actions with strategic consequences (e.g., strikes in populated areas) require President/SECDEF approval. Tactical actions can be delegated to combatant commanders. Self-defense is always delegated to the lowest level.
- **Self-defense is never restricted**: unit commanders always retain the authority to protect their forces. The AI factory analog: agents should always be able to roll back their own changes without requiring approval.
- **Graduated response**: ROE require responses proportional to threats, with de-escalation steps and warnings before force application. In an AI factory, destructive actions should follow a graduated protocol: warn, propose, confirm, execute.

### Hospital Never Events

The "never events" framework (Kizer, 2001) identifies a class of errors that are so serious and so clearly preventable that they should never occur: wrong-site surgery, retained foreign objects, wrong-patient procedures. These events are unambiguous, serious, and usually preventable.

The WHO Surgical Safety Checklist applies this principle: a 19-item checklist at three pause points (before induction, before incision, before leaving the operating room) reduced surgical mortality by 47% and complications by 36% (Haynes et al., 2009).

### Financial Circuit Breakers

NYSE circuit breakers implement automatic halts at three threshold levels (7%, 13%, 20% decline from prior close). The mechanism:
- Level 1 and 2: 15-minute trading halt (pause for human assessment).
- Level 3: trading suspended for the remainder of the day.
- Resumption requires a structured reopening auction.

The key design insight: **circuit breakers do not prevent harm -- they create a mandatory pause for human judgment**. The analog for AI factories is not preventing agents from acting, but requiring a pause and human re-engagement when impact thresholds are crossed.

### Blast Radius Classification for AI Factories

Drawing from all three domains, an AI factory should classify every action along two dimensions:

**Reversibility spectrum:**
| Category | Examples | Required Authority |
|----------|----------|--------------------|
| Trivially reversible | Code formatting, adding comments | Agent autonomous |
| Easily reversible | New test file, documentation update | Agent with notification |
| Reversible with effort | Code refactoring, config changes | Agent with veto window |
| Difficult to reverse | Database migration, API contract change | Human approval required |
| Irreversible | Data deletion, public API removal, production deploy | Multi-party sign-off |

**Blast radius scope:**
| Scope | Examples | Authority Ceiling |
|-------|----------|-------------------|
| Self-contained | Changes within one module's internal code | Agent at Level 6-7 |
| Cross-module | Interface changes affecting 2+ modules | Agent at Level 5 |
| Cross-service | API changes affecting external consumers | Human at Level 4-5 |
| User-facing | UX changes, pricing changes, data handling | Human at Level 3-4 |
| Financial | Spending, billing changes, resource allocation | Human at Level 1-2 |

**Never-event list for AI factories:**
- Deploying to production without passing CI
- Deleting production data
- Exposing secrets in code or logs
- Merging code that breaks existing public API contracts
- Committing credentials or PII
- Spending above budget thresholds without approval

These should be enforced as hard blocks (not soft warnings), analogous to the WHO checklist's mandatory pause points.

---

## 5. Graduated Authority Model

### The Problem with Binary Authority

Existing tools model authority as binary: a user either has permission to perform an action or does not. GitHub permissions are read/triage/write/maintain/admin. CI/CD pipelines either run or wait for manual approval. This does not map to the reality of progressive trust building.

### Knight-Columbia Levels of Autonomy for AI Agents

The Knight First Amendment Institute's framework (2025) defines five levels of agent autonomy based on the human's role:

| Level | Human Role | Agent Behavior |
|-------|-----------|----------------|
| 1 | Operator | Human directs every action; agent is a tool |
| 2 | Collaborator | Human and agent co-develop; interleaved contributions |
| 3 | Consultant | Agent proposes plans; human provides strategic guidance |
| 4 | Approver | Agent executes autonomously; human reviews outcomes |
| 5 | Observer | Agent acts fully; human monitors dashboards |

The framework introduces **autonomy certificates** -- digital documents prescribing the maximum autonomy level for an agent given its capabilities and operational context, issued by a governing body.

### Existing Tool Support

**Claude Code** implements the most graduated model in current practice: permissions are Allowed/Asked/Denied per action type, with a session mode system (e.g., read-only planning mode). Permissions build incrementally as users approve actions. Subagents run with independent, typically more restricted permissions.

**Devin** operates at the highest autonomy level -- it plans, codes, tests, and deploys with minimal oversight, positioning the human as approver/observer.

**GitHub Actions / CI-CD** provides binary gates (manual approval step or automatic). No concept of graduated confidence or conditional execution.

### The Needed Graduated Model

A five-tier authority model for AI agent actions in a software factory:

| Authority Tier | Capability | Examples | Earning Criteria |
|---------------|------------|----------|-----------------|
| **Propose** | Can suggest changes; cannot execute | "I would refactor this function" | Default for new agents/new domains |
| **Execute** | Can modify files; cannot commit | Write code, run tests locally | N successful proposals accepted |
| **Commit** | Can create commits and PRs | Git operations, branch management | N successful executions without rollback |
| **Deploy** | Can merge and trigger deployments | Production releases | M successful commits without revert + human certification |
| **Spend** | Can allocate resources with cost | Provision infrastructure, buy API tokens | Explicit human delegation, budget-capped |

Each tier should be **independently configurable per domain**. An agent might have Deploy authority for documentation changes but only Propose authority for payment system changes. Authority should be **earnable and losable**: successful track record elevates authority; failures (especially near-misses caught in review) reduce it.

### What Is Missing from Current Tools

1. **Domain-scoped authority**: no tool allows "can deploy documentation but only propose for billing code."
2. **Evidence-based authority transitions**: no tool automatically promotes or demotes authority based on track record.
3. **Budget-capped financial authority**: no coding agent tool limits cumulative spending; they either can or cannot provision resources.
4. **Authority inheritance for subagents**: when an agent spawns subagents, there is no formal model for how authority propagates (should it be inherited? reduced? independently configured?).
5. **Temporal authority decay**: authority that is not exercised should decay, requiring re-certification -- analogous to medical credential renewal.

---

## 6. Re-Engagement Protocol

### The Problem

When a principal who has withdrawn to the observer level (Level 5 autonomy) needs to re-enter execution -- due to an incident, strategic pivot, or agent failure -- they face a context reconstruction problem. They have been out of the loop, potentially for days or weeks. Endsley's research shows this context loss is the primary danger of high automation levels.

### Military Battle Handover

Military Transfer of Authority (TOA) requires a full briefing covering:
- Incident/mission history
- Current priorities and objectives
- Resource assignments and organization
- Outstanding orders and requests
- Constraints and limitations
- Assessment of future potential

The "right seat / left seat ride" model is particularly relevant: the incoming commander first observes (right seat) while the outgoing commander executes (left seat), then they swap. This graduated transition prevents the cold-start problem.

### FEMA Incident Command System

FEMA's ICS mandates that transfer of command always includes:
- A complete briefing (oral, written, or both)
- ICS Form 201 (Incident Briefing) as structured documentation
- Notification to all personnel that command is changing
- Face-to-face transfer whenever possible

The ICS Form 201 is designed as a structured context-loading document: it captures the current situation map, organizational chart, resource status, and planned actions in a standardized format that any qualified person can read and assume command from.

### Hospital SBAR Protocol

SBAR (Situation, Background, Assessment, Recommendation) provides the most compact re-engagement protocol:
- **Situation**: what is happening right now (the incident trigger)
- **Background**: relevant context (what the agent has been doing, what changed)
- **Assessment**: what the agent or system believes is wrong
- **Recommendation**: proposed next steps for the re-engaging human

SBAR has been shown to significantly improve patient safety during handovers, especially telephonic ones. Its power is in forced structure: it prevents the common failure mode of dumping raw data without analysis.

### AI Factory Re-Engagement Protocol

An AI factory needs a structured re-engagement mechanism that combines elements of all three:

**1. Context snapshot (ICS Form 201 analog):**
- Current state of all active work items
- Recent completions and their outcomes
- Pending decisions awaiting input
- Active risks or anomalies
- Resource status (budget consumed, infrastructure state)

**2. SBAR-formatted incident briefing:**
When re-engagement is triggered by an incident, the system should generate an SBAR:
- **Situation**: "Production error rate increased 5x after deployment of PR #1847 at 14:32 UTC"
- **Background**: "Agent deployed a refactoring of the payment module. 47 similar refactorings succeeded previously. This one changed the retry logic for failed charges."
- **Assessment**: "Root cause appears to be an edge case in idempotency key generation not covered by existing tests."
- **Recommendation**: "Immediate rollback is available. Three remediation approaches are proposed: [links]."

**3. Right-seat/left-seat transition:**
When a principal re-engages, the system should support a graduated transition:
- **Phase 1 (Observer)**: principal reviews the context snapshot and recent agent activity log
- **Phase 2 (Approver)**: principal approves/rejects the next N agent actions to rebuild intuition
- **Phase 3 (Collaborator)**: principal co-works with agent on the incident resolution
- **Phase 4 (Operator)**: principal takes direct control if needed, with agent assisting

**4. What existing tools provide and where they stall:**

| Capability | Tool Support | Gap |
|-----------|-------------|-----|
| Activity log | Git log, CI history, Jira history | Exists but not structured for rapid comprehension |
| Context snapshot | Jira dashboards, GitHub project boards | No agent-aware summarization; raw data only |
| Incident briefing | PagerDuty, Opsgenie | Alert-oriented, not SBAR-structured |
| Graduated re-entry | None | No tool supports phased authority escalation during re-engagement |
| Decision replay | None | No tool lets a principal replay the decisions an agent made and understand the rationale for each |

The critical missing piece is **decision replay**: the ability for a re-engaging principal to step through the agent's recent decisions, see the context the agent had, the alternatives it considered, and why it chose as it did. This is the analog of the cockpit voice recorder / flight data recorder review that aviation uses after incidents. Without decision replay, re-engagement requires the principal to reconstruct context from raw artifacts (commits, PRs, logs), which is slow and error-prone.

---

## Synthesis: The Withdrawal Progression Path

Combining all six focus areas, the human withdrawal progression for an AI factory follows this path:

```
Stage 1: OPERATOR (Sheridan Level 1-3)
  Human executes. Agent assists with information gathering and analysis.
  Trust mechanism: agent demonstrates competence on low-stakes tasks.
  Authority model: agent can propose only.
  Approval: human reviews every output.

Stage 2: COLLABORATOR (Sheridan Level 4-5)
  Human and agent co-execute. Agent generates solutions; human reviews and approves.
  Trust mechanism: near-miss tracking begins. Override ratio tracked.
  Authority model: agent can execute within approved domains.
  Approval: tiered review (automated first pass, human second pass).

Stage 3: DELEGATOR (Sheridan Level 5-6)
  Agent executes routine work autonomously. Human approves non-routine work.
  Trust mechanism: calibration dashboard active. Structured retrospectives.
  Authority model: agent can commit in earned domains; propose in new domains.
  Approval: time-bounded veto for routine; explicit approval for novel.
  Circuit breakers: blast radius limits enforced.

Stage 4: SUPERVISOR (Sheridan Level 6-7)
  Agent handles most execution. Human monitors dashboards and handles exceptions.
  Trust mechanism: agent confidence reporting. Near-miss severity tracking.
  Authority model: agent can deploy in certified domains.
  Approval: exception-based (agent escalates only anomalies and policy decisions).
  Circuit breakers: never-event hard blocks. Budget caps.

Stage 5: GOVERNOR (Sheridan Level 8-9)
  Human sets policy and reviews aggregate outcomes. Daily/weekly cadence.
  Trust mechanism: periodic authority re-certification. Outcome audits.
  Authority model: agent operates within policy envelope.
  Approval: policy-level only (e.g., "approve new cost category").
  Re-engagement: SBAR protocol + decision replay available on demand.
```

### Key Design Principles

1. **Never skip levels.** Jumping from Operator to Supervisor destroys the trust evidence needed to make Supervisor mode safe. Each stage must be experienced for a minimum duration with measured outcomes.

2. **Per-domain, not global.** Authority progression is domain-specific. An agent may be at Stage 4 for test writing and Stage 2 for infrastructure changes simultaneously.

3. **Losable authority.** A near-miss or incident reverts the agent to a lower stage for the affected domain. Automatic demotion with human-controlled re-promotion.

4. **Mandatory re-engagement support.** Every automation level above Stage 2 must maintain the artifacts needed for rapid re-engagement: context snapshots, decision logs, SBAR generation capability.

5. **Irreversibility gates are absolute.** Regardless of authority level, actions classified as irreversible or never-events require explicit human confirmation. These gates do not graduate away.

---

## Sources

- [Sheridan & Verplanck LOA taxonomy (ResearchGate diagram)](https://www.researchgate.net/figure/Levels-of-Automation-From-Sheridan-Verplank-1978_tbl1_235181550)
- [Literature review of LOA taxonomies (Academia.edu)](https://www.academia.edu/36441688/A_literature_review_on_the_levels_of_automation_during_the_years_What_are_the_different_taxonomies_that_have_been_proposed)
- [Parasuraman, Sheridan, Wickens (2000) - IEEE model](https://ieeexplore.ieee.org/document/844354)
- [Endsley & Kiris (1995) - Out-of-the-Loop Performance Problem](https://journals.sagepub.com/doi/10.1518/001872095779064555)
- [Kaber & Endsley - Intermediate Levels of Automation](https://www.researchgate.net/publication/229774424_Out-of-the-Loop_Performance_Problems_and_the_Use_of_Intermediate_Levels_of_Automation_for_Improved_Control_System_Functioning_and_Safety)
- [CRM Training - SKYbrary](https://skybrary.aero/articles/crew-resource-management-crm)
- [NASA CRM-A for Automated Teammates](https://ntrs.nasa.gov/api/citations/20180004774/downloads/20180004774.pdf)
- [IAEA TECDOC-668 - Automation and Humans in Nuclear Plants](https://www-pub.iaea.org/MTCD/Publications/PDF/te_668_web.pdf)
- [IAEA Safety Reports Series No. 73 - Low Level Event Reporting](https://www-pub.iaea.org/MTCD/Publications/PDF/Pub1545_web.pdf)
- [Nuclear LOA and Trust (MDPI)](https://www.mdpi.com/2313-576X/11/1/22)
- [Never Events - AHRQ PSNet](https://psnet.ahrq.gov/primer/never-events)
- [WHO Surgical Safety Checklist](https://www.who.int/teams/integrated-health-services/patient-safety/research/safe-surgery/tool-and-resources)
- [NYSE Circuit Breakers FAQ](https://www.nyse.com/publicdocs/nyse/NYSE_MWCB_FAQ.pdf)
- [Military ROE - Duke Law](https://sites.duke.edu/lawfire/files/2020/10/ROEOperational-Law-Handbook-2020.pdf)
- [Military TOA - Army Doctrine](https://www.benning.army.mil/Infantry/DoctrineSupplement/ATP3-21.8/chapter_06/Transitions/TransferofAuthority/index.html)
- [FEMA ICS Transfer of Command](https://training.fema.gov/emiweb/is/icsresource/assets/transfer%20of%20command.pdf)
- [SBAR Systematic Review (PMC)](https://pmc.ncbi.nlm.nih.gov/articles/PMC6112409/)
- [SBAR Implementation (PMC)](https://pmc.ncbi.nlm.nih.gov/articles/PMC6752450/)
- [Knight-Columbia Levels of Autonomy for AI Agents](https://knightcolumbia.org/content/levels-of-autonomy-for-ai-agents-1)
- [MIT Media Lab - Authenticated Delegation for AI Agents](https://www.media.mit.edu/publications/authenticated-delegation-and-authorized-ai-agents/)
- [Claude Code Permission Model](https://skywork.ai/blog/permission-model-claude-code-vs-code-jetbrains-cli/)
- [Adaptive Human-Machine Teaming (SAGE)](https://journals.sagepub.com/doi/full/10.1177/1555343419878038)
- [Variable Autonomy for Human-Robot Teaming (PMC)](https://pmc.ncbi.nlm.nih.gov/articles/PMC11576532/)
- [Palo Alto Networks - Agentic AI Governance](https://www.paloaltonetworks.com/cyberpedia/what-is-agentic-ai-governance)
- [Netflix Dailies Best Practices](https://partnerhelp.netflixstudios.com/hc/en-us/articles/4415931246995-Dailies-Best-Practices)

<!-- flux-research:complete -->
