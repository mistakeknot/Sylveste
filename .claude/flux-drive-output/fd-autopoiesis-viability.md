# Autopoiesis, Viability, and the v1.0 Threshold

**Research question:** What should v1.0.0 mean for Sylveste (currently v0.6.228), analyzed through cybernetic and thermodynamic frameworks?

**Method:** Apply Beer's Viable System Model, Maturana/Varela's autopoiesis, Prigogine's dissipative structures, stigmergic phase transitions, Friston's free energy principle, and Ashby's requisite variety to Sylveste's architecture. Identify where analogies hold, where they break, and what operationally useful maturity thresholds emerge.

---

## 1. Viable System Model Mapping

Beer's VSM requires five systems (plus audit) for an organization to be *viable* — capable of maintaining independent existence in a changing environment. The acid test: if any system is missing, the organism eventually dies.

### Current Mapping

| VSM System | Function | Sylveste Component | Status |
|------------|----------|-------------------|--------|
| **S1: Operations** | Units that do the work | Clavain agents (6), interflux agents (17), sprint lifecycle, phase gates | **Strong.** 23 agents across review, research, and workflow. Sprint lifecycle is well-defined with phase transitions. |
| **S2: Coordination** | Anti-oscillation; shared standards that prevent S1 units from interfering | 3-layer routing (Stage/Domain/Concern), interlock broadcast, hooks.json event bus, plugin collision rules, lib-gates.sh | **Moderate.** Routing prevents dispatch collisions. interlock enables cross-session coordination. But S2 is mostly *static* — routing tables rather than dynamic dampening. |
| **S3: Control** | Resource allocation with authority; balancing local and global | Intercore kernel (`ic run`, `ic dispatch`, `ic gate`, `ic lock`, `ic cost`), budget.yml, token budgets, fleet registry | **Moderate.** Kernel manages runs and gates. Budget enforcement exists but is not yet real-time (runtime budget enforcement is in the "Later" horizon). S3 *directs* but cannot yet *reallocate mid-execution*. |
| **S3\*: Audit** | Sporadic, unpredictable deep verification | Interspect (evidence collection, canary monitoring, routing overrides), interflux multi-agent review (12 review agents with independent scoring), CXDB turn DAG | **Moderate-Strong.** Interspect's canary monitoring is genuine S3\* behavior: it watches for 20-use windows over 14 days and alerts at a 20% threshold. Multi-model review with independent scoring is a form of audit. But audits are not yet *sporadic* in Beer's sense — they follow fixed patterns rather than randomized schedules. |
| **S4: Intelligence** | Environmental scanning; future orientation | Alwe (cross-agent observation via CASS), interflux research agents (5), interlab mutation store, interwatch doc-staleness detection | **Weak.** This is the most underdeveloped system. Alwe observes *internal* agent sessions, but Sylveste has no systematic mechanism for scanning its *external* competitive environment, detecting shifts in model capabilities, or sensing changes in the problem space it targets. The research agents are user-invoked, not autonomously triggered. interwatch detects internal doc drift, not external environmental change. |
| **S5: Policy** | Identity, values, conflict resolution between S3 and S4 | PHILOSOPHY.md (3 principles, 4 bets), trust ladder (L0-L5), safety floors, CLAUDE.md cascading instruction system | **Present but static.** The philosophy is clearly articulated and enforced through cascading CLAUDE.md files. But S5 is *written policy*, not a *living mediator*. There is no runtime mechanism that detects when S3 (optimize current operations) and S4 (adapt to environment) are in tension and resolves it. PHILOSOPHY.md says "There is no 'done.' The flywheel doesn't converge — it compounds." But the policy system itself doesn't compound — it changes only through manual human edits. |

### The Missing System: S4 (Intelligence)

Beer's S4 is the system that looks *outward and forward*. It answers: "What is changing in our environment that requires us to change?" In a biological organism, this is the sensory/nervous interface with the environment. In a firm, it is strategy, R&D, market sensing.

Sylveste's S4 gap is specific and consequential:

1. **No autonomous environmental scanning.** When a new model is released (say, a Claude 5 with different capability characteristics), Sylveste has no mechanism to autonomously detect this, assess implications for routing tables, and propose adaptations. A human must notice, update fleet-registry.yaml, and recalibrate.

2. **No competitive sensing.** PHILOSOPHY.md names the core bet that "the system that runs the most sprints learns the fastest." But nothing in the architecture systematically observes whether competitors (Devin, Factory, Codegen, Cursor Agent) have leapfrogged on a specific capability, which would alter strategic priorities.

3. **Research agents are demand-pulled, not supply-pushed.** The 5 interflux research agents (best-practices-researcher, framework-docs-researcher, etc.) activate only when a user invokes `/autoresearch`. A true S4 would continuously scan and propose adaptations without waiting for a trigger.

4. **Alwe observes the organism, not the environment.** Alwe's five MCP tools (`search_sessions`, `context_for_file`, `export_session`, `timeline`, `health`) all look inward at agent session data. This is invaluable S3/S3\* capability (internal control and audit), but it is not S4.

**VSM v1.0 criterion:** All five systems operational, with S4 at minimum generating autonomous environmental-change alerts that feed into S3/S5 decision-making.

---

## 2. Autopoiesis Analysis

Maturana and Varela's autopoiesis defines a system as self-maintaining when it produces and maintains its own operational components through an organizationally closed network of processes. The critical test: does the system produce the components that produce the system?

### Autopoiesis vs. Allopoiesis

An *allopoietic* system produces something other than itself — a car factory produces cars, not more factories. An *autopoietic* system produces its own components — a cell produces the membranes, enzymes, and organelles that constitute the cell.

**Sylveste is currently allopoietic.** It produces shipped code for target projects — other-directed output. The "self-building" principle in PHILOSOPHY.md ("Sylveste builds itself with its own tools") gestures toward autopoiesis, but building *with* your own tools is not the same as *producing your own operational components autonomously*.

### The Autopoiesis Threshold

For Sylveste to cross the autopoiesis threshold, these conditions must hold simultaneously:

| Autopoietic Property | Maturana/Varela Criterion | Sylveste Status |
|----------------------|---------------------------|----------------|
| **Component production** | The network of processes produces the components that realize the network | Partially. interlab mutation store enables agents to improve agents (review agents improving review agents). But this is *one* process, not a network. Routing tables, phase gates, fleet registries, and plugin manifests are all human-produced. |
| **Organizational closure** | The system's behavior is determined by its own structure, not its environment | No. Claude Code's plugin loading system, Anthropic's API changes, and model capability shifts all directly determine Sylveste's behavior. The system is deeply structurally coupled but not organizationally closed. |
| **Boundary production** | The system produces and maintains its own boundary | Partially. Safety floors (lib-routing.sh), trust ladder levels, and capability policies define the boundary. But the boundary itself is human-configured, not self-produced. |
| **Structural determinism** | Only the system's internal state determines what environmental perturbations can trigger changes | No. A model API breaking change, a Claude Code plugin format change, or a new model release bypasses internal determination entirely. |

### Where the Analogy Breaks

The autopoiesis framework reveals a fundamental tension in Sylveste's architecture:

1. **Sylveste cannot produce its own substrate.** A cell produces its own membrane and enzymes. Sylveste cannot produce LLMs, cannot produce Claude Code, cannot produce the terminal infrastructure it runs on. It is *constitutively dependent* on externally-produced components. This is not a gap to be closed — it is a structural property of software platforms. No software system is autopoietic in the strict biological sense because software cannot produce its own hardware or runtime environment.

2. **Luhmann's escape hatch.** Niklas Luhmann extended autopoiesis to social systems by redefining the "components" — social systems don't produce people, they produce *communications*. The system's elements are not the physical substrate but the operations. Applied to Sylveste: the relevant components are not "Go binaries and markdown files" but *decisions* — routing decisions, gate decisions, review verdicts, dispatch choices. By this reading, Sylveste approaches autopoiesis when its decision-making processes produce the rules and calibrations that govern future decision-making processes.

3. **The OODARC loop is proto-autopoietic.** The Reflect/Compound phases of OODARC explicitly close the loop: observations feed back to change future behavior. Interspect's evidence-to-routing-override pipeline is a concrete instance. But the loop only operates on *routing* — it does not yet produce new agents, new phase structures, new gate criteria, or new coordination rules. The network of processes is too narrow to constitute organizational closure.

**Autopoietic v1.0 criterion:** The system's closed-loop calibration operates on at least three independent operational dimensions (not just routing) — e.g., routing, gate thresholds, and agent composition — such that past outcomes automatically shape future operational structure.

---

## 3. Thermodynamic Free Energy Analysis

### Prigogine's Dissipative Structures

A dissipative structure maintains itself far from thermodynamic equilibrium through continuous energy (or information) throughput. Key properties:

- **Requires continuous flow.** Stop the energy input and the structure dissipates. For Sylveste: stop the token flow (API calls, model invocations) and the system is inert files on disk.
- **Nonlinear dynamics.** Dissipative structures emerge only when the system's governing equations are nonlinear. For Sylveste: the flywheel (authority -> actions -> evidence -> authority) is explicitly nonlinear — each cycle compounds, not merely accumulates.
- **Bifurcation points.** As parameters change (increasing throughput, growing agent count), the system hits bifurcation points where the old steady state becomes unstable and a qualitatively new pattern emerges.
- **Entropy production increases with structure.** More complex dissipative structures dissipate *more* energy, not less. This maps directly to Sylveste's cost observation: "Wasted tokens dilute context." Efficient structure doesn't minimize token consumption — it maximizes useful work *per token*.

**The dissipative structure question for v1.0:** Has the system crossed its first bifurcation — from a manually-driven tool to a self-sustaining pattern that would collapse back to manual operation only if the throughput dropped below a critical threshold?

Currently, Sylveste is arguably *pre-bifurcation*. The flywheel exists in principle (PHILOSOPHY.md describes it clearly) but the evidence-to-routing-override loop has "zero production callers" for B2 complexity-aware routing. The calibration tables exist but are populated by defaults, not by closed-loop feedback from outcomes. The system is far from equilibrium (it consumes tokens continuously) but has not yet crossed the threshold where its organized structure is self-reinforcing.

### Friston's Free Energy Principle

Under Friston's framework, viable agents minimize *variational free energy* — the divergence between their world model and sensory reality. Two mechanisms:

1. **Perceptual inference (update the model):** When outcomes surprise the agent, update internal beliefs.
2. **Active inference (change the world):** Act to make the world match predictions.

Mapping to Sylveste:

| FEP Mechanism | Sylveste Implementation | Maturity |
|---------------|----------------------|----------|
| **World model** | Fleet registry, routing tables, complexity classifiers, phase-cost estimates | Exists but largely hardcoded defaults |
| **Prediction error** | Interspect evidence (verdict accuracy, routing success rates), interstat token actuals vs. estimates | Collection infrastructure exists; closed-loop calibration is partial |
| **Perceptual inference** | `calibrate-phase-costs`, interspect canary monitoring, interlab mutation quality signals | Individual calibration loops exist; not integrated into a unified prediction-error minimization process |
| **Active inference** | Routing overrides (change which agent handles which task), gate threshold adjustment | Override *application* works; override *generation* is human-initiated, not autonomously driven by prediction error |

**The FEP insight:** Sylveste's architecture already embeds the distinction between "update the model" (perceptual inference via calibration) and "change the world" (active inference via routing overrides). What's missing is the *automatic connection* between prediction error and active response. Currently, surprise (e.g., an agent performing worse than expected) is *recorded* but not *autonomously acted upon*. The interspect pipeline has the plumbing but the pump is manual.

**Free energy v1.0 criterion:** The system's prediction error (observed outcomes vs. expected outcomes) autonomously triggers model updates AND active interventions without human initiation — the "surprise minimization" loop runs without a human turning the crank.

---

## 4. Stigmergic Phase Transitions

Research on Pharaoh's ants (Beekman et al., PNAS 2001) demonstrates a first-order phase transition in foraging behavior as colony size increases. Below a critical threshold, ants forage individually with random walks. Above it, pheromone trails emerge and coordinated exploitation dominates. The transition exhibits hysteresis — intermediate-sized colonies can be in either state depending on initial conditions.

### Analogous Phases in Multi-Agent Development

| Ant Colony Phase | Agent Platform Analogue | Sylveste Status |
|------------------|------------------------|----------------|
| **Phase 0: Solitary foraging** | Single agent, human-directed. No coordination needed because there's only one worker. | Pre-Sylveste. A single Claude Code session with no plugins. |
| **Phase 1: Local pheromone deposits** | Agents leave traces (session logs, beads, events) but don't read each other's traces systematically. Information exists but doesn't coordinate. | **Current state.** Agents produce JSONL sessions, beads track work, intercore records events. But cross-session learning is weak — interlock broadcasts exist but have limited consumers. |
| **Phase 2: Trail formation** | Agents read and reinforce each other's successful paths. Good solutions attract more agents; bad paths decay. Self-organized division of labor emerges. | **Partially built.** interlab mutation store with delta sharing via interlock is *exactly* this — "parallel sessions discover and build on each other's approaches." But it's limited to /autoresearch campaigns. The sprint lifecycle doesn't yet exhibit trail-based coordination across sessions. |
| **Phase 3: Adaptive load balancing** | The colony dynamically reallocates foragers between food sources based on trail strength. Trail decay prevents lock-in to depleted sources. | **Not yet reached.** Requires: (a) real-time reallocation of agents between tasks based on signals, (b) decay of stale routing decisions, and (c) autonomous work selection based on environmental signals. This is the Skaffen OODARC vision but not yet operational at fleet scale. |

### The Phase Transition Threshold

The ant colony research identifies the critical variable as colony size relative to search difficulty. Below the threshold, pheromone trails evaporate before reinforcement arrives. Above it, trails self-reinforce.

For Sylveste, the analogous variables are:
- **Agent count per active task** — enough agents contributing to a solution space that successful approaches get reinforced before they decay
- **Signal persistence** — how long evidence and calibration data remain actionable
- **Feedback latency** — how quickly an outcome (success/failure) propagates to future decisions

The Phase 1 -> Phase 2 transition requires that *successful approaches propagate faster than they decay*. Currently, Sylveste's evidence has long persistence (90-day rolling window) but slow propagation (manual interspect override generation). This inversion — high persistence, low propagation — is the equivalent of an ant colony where pheromone doesn't evaporate but ants can't smell it.

**Stigmergy v1.0 criterion:** Evidence from completed sprints automatically influences the next sprint's agent selection, phase structure, or approach — without human mediation. The "pheromone" (outcome evidence) is both persistent AND propagated.

---

## 5. Ashby's Law of Requisite Variety

The law states: "Only variety can destroy variety." A controller must have at least as many distinguishable responses as the system it regulates has distinguishable disturbances.

### Variety Inventory

**Disturbance variety (the problem space):**
- Programming languages: dozens (Python, Go, Rust, TypeScript, Ruby, Java, ...)
- Project types: library, CLI, web service, mobile, infrastructure, data pipeline
- Task types: bug fix, feature, refactor, test, documentation, migration, security patch
- Complexity levels: one-file tweak to multi-service architecture change
- Codebase sizes: 100 lines to millions of lines
- Review dimensions: correctness, security, performance, architecture, UX, accessibility

Conservative estimate of distinguishable problem states: ~10,000+ (combinatorial explosion across dimensions).

**Controller variety (Sylveste's response repertoire):**
- 23 agents across review, research, and workflow
- 17 skills for different development disciplines
- 49 commands for specific operations
- 3-layer routing with ~20 domain cells
- 5 model tiers (cheap to expensive)
- Complexity classifier (3-5 buckets)
- Phase gates (7 phases: explore, plan, execute, debug, review, ship, meta)

Conservative estimate of distinguishable response states: ~500-2,000 (products of routing dimensions).

### The Variety Gap

Sylveste's controller variety (~2,000) is one order of magnitude below the disturbance variety (~10,000+). Ashby's law predicts this gap will manifest as *unregulated disturbances* — problems the system cannot adequately respond to.

Observable symptoms of insufficient variety:
- **One-size-fits-all phase gates.** The same 7-phase structure applies to a one-line typo fix and a multi-service migration. This is variety compression that loses information.
- **Language-agnostic routing.** Routing by Stage/Domain/Concern does not distinguish Python-specific from Go-specific expertise. An agent routed to "review/code/correctness" may lack language-specific knowledge.
- **Fixed agent composition.** The 12 review agents have fixed concerns. A novel concern (e.g., accessibility, internationalization, regulatory compliance) has no agent — the variety of review dimensions exceeds the variety of reviewers.

### Variety Amplification Strategies

Ashby identified two responses to variety gaps:
1. **Amplify controller variety** — add more distinguishable responses
2. **Attenuate disturbance variety** — filter or constrain the problem space

Sylveste already uses both:
- **Amplification:** 53 Interverse plugins extend the base variety. The plugin architecture is explicitly a variety amplification mechanism ("Growth is a feature").
- **Attenuation:** "Software development is the first-class citizen" constrains the problem space. The complexity classifier attenuates by bucketing continuous complexity into discrete levels.

But the variety gap reveals why the plugin architecture is not just a convenience — it is *structurally necessary*. The base system cannot have requisite variety for the full problem space. Only the composed system (base + plugins + routing + calibration) can approach it.

**Requisite variety v1.0 criterion:** The system's composed variety (base + plugins + routing dimensions) covers >80% of observed problem types without falling back to generic/default handling. Measurable by: what fraction of dispatched tasks uses specialized (non-default) routing?

---

## 6. Where the Analogies Break Down

Each framework illuminates something, but each also distorts. The distortions are as informative as the illuminations.

### Biology vs. Software: The Substrate Problem

Autopoiesis requires that the system produces its own components. Cells produce enzymes; organisms produce cells. Software systems *never* produce their own substrate — they run on externally-produced hardware, operating systems, and runtimes. Sylveste depends on Claude Code, Anthropic's API, Go, SQLite, and tmux. None of these are produced by Sylveste.

**What this reveals:** The autopoietic threshold for software must be redefined. A software platform is "autopoietic" not when it produces its hardware (impossible) but when it produces its own *operational logic* — the rules, calibrations, and compositions that determine its behavior. By this criterion, the relevant question is: does Sylveste produce its own routing tables, gate thresholds, agent compositions, and coordination rules? Currently: partially (interspect routing overrides), but mostly not.

### Thermodynamics vs. Information: The Entropy Problem

Prigogine's dissipative structures exist because they increase total entropy production while decreasing local entropy. The thermodynamic framing maps awkwardly to information systems because "entropy" in information theory (Shannon entropy) and thermodynamics (Boltzmann entropy) are related but not identical. A software system that "minimizes surprise" (Friston) is not literally minimizing thermodynamic entropy.

**What this reveals:** The useful insight from thermodynamics is not entropy per se but *the requirement for continuous throughput*. Sylveste is a dissipative structure in the sense that it requires continuous token flow to maintain its organized state. Turn off the API, and it degrades to inert files. The v1.0 question is whether the organized state has crossed a bifurcation into self-reinforcing complexity — and the honest answer is not yet.

### Ant Colonies vs. Agent Fleets: The Identity Problem

Ants have no individual identity or strategy. They follow simple rules (deposit pheromone, follow gradients, random walk otherwise). LLM agents are the opposite — they have rich internal representations, can strategize, and maintain session context. Stigmergy works for ants because individual simplicity enables collective complexity. For LLM agents, the individual is already complex, which makes collective coordination *harder*, not easier, because agents can have conflicting internal models.

**What this reveals:** Pure stigmergy (indirect coordination through environment modification) is necessary but not sufficient for Sylveste. The system needs *both* stigmergic coordination (beads, events, routing overrides as "pheromones") AND direct mediation (interlock broadcasts, multi-agent review synthesis). Beer's S2 (anti-oscillation coordination) is more relevant than pure stigmergy for the agent-identity problem.

### VSM vs. Software: The Recursion Problem

Beer's VSM is fractal — every viable system contains viable sub-systems, and is itself part of a larger viable system. Sylveste partially exhibits this recursion (Intercore is a viable sub-system with its own S1-S5; Clavain is another; each plugin could be analyzed as a viable system). But the recursion *stops at the model boundary*. Sylveste cannot make the LLM itself more viable — it can only route to different LLMs. This creates a viability dependency that Beer's framework doesn't anticipate: the sub-system's viability depends on an external component that the meta-system cannot regulate.

**What this reveals:** Sylveste's viability has an irreducible external dependency. This is why the "host platform agnostic" strategy in PHILOSOPHY.md is a viability strategy, not just a business strategy — it reduces the single-point-of-failure risk from any one LLM provider.

---

## 7. Synthesis: The Operationally Useful v1.0 Criterion

Each framework suggests a different threshold:

| Framework | v1.0 Criterion | Observable Test |
|-----------|---------------|-----------------|
| **VSM** | All five systems operational | S4 generates autonomous environmental-change signals |
| **Autopoiesis** | Three independent closed-loop calibration dimensions | Past outcomes automatically shape routing + gates + agent composition |
| **Dissipative structures** | First bifurcation crossed | System degrades to qualitatively different (worse) behavior if calibration data is deleted |
| **Stigmergy** | Phase 1->2 transition | Sprint outcomes propagate to next sprint without human mediation |
| **Free energy** | Autonomous surprise minimization | Prediction error triggers model updates AND active interventions automatically |
| **Requisite variety** | >80% specialized routing coverage | <20% of tasks fall through to generic/default handling |

### The Unified Test

These criteria converge on a single observable property: **closed-loop autonomy across multiple operational dimensions.**

The frameworks agree that v1.0 is NOT about:
- Feature count (Sylveste already has 53 plugins, 23 agents, 49 commands)
- Code quality (the codebase is well-structured with clear boundaries)
- Architectural completeness (5 pillars, 3 layers, well-defined interfaces)

The frameworks agree that v1.0 IS about:
- Whether the system's past behavior *automatically* shapes its future behavior
- Whether this happens across multiple independent dimensions, not just one
- Whether removing the accumulated calibration/evidence would cause observable degradation

### The Concrete Observable Test

**Sylveste v1.0.0 means: if you delete `.clavain/interspect/interspect.db`, the routing-overrides, the calibration history, and the mutation store, the system performs measurably worse on the next 10 sprints — AND it recovers to prior performance within 50 sprints without human intervention.**

This single test validates:
1. **VSM completeness** — the evidence/calibration data is operationally load-bearing (it matters), implying all five systems contribute
2. **Autopoietic closure** — the system reproduces its own operational parameters from outcomes
3. **Dissipative bifurcation** — the organized state is self-reinforcing (it degrades when disrupted and recovers through its own dynamics)
4. **Stigmergic phase transition** — outcomes propagate as "pheromones" that coordinate future behavior
5. **Free energy minimization** — the system autonomously reduces surprise (prediction error shrinks over sprints)
6. **Requisite variety** — the calibration data adds variety to the controller that the default configuration lacks

### The Deletion-Recovery Test, Operationalized

```
SETUP:
  1. Run 100 sprints across diverse projects with full Sylveste stack
  2. Record per-sprint metrics: cost, duration, defect rate, gate pass rate
  3. Snapshot the calibration state (interspect.db, routing-overrides, mutation store)

DELETION:
  4. Delete all calibration/evidence state
  5. Run 10 sprints (same project distribution) — these are the "amnesiac" sprints
  6. Compare metrics to the last 10 pre-deletion sprints

RECOVERY:
  7. Continue running sprints without human intervention on calibration
  8. Measure sprints-to-recovery (when metrics return to within 1 sigma of pre-deletion)

v1.0 PASS CRITERIA:
  - Amnesiac sprints are >15% worse on at least two of: cost, duration, defect rate
  - Recovery occurs within 50 sprints
  - No human touches calibration/routing/gate configuration during recovery
```

### What Must Change to Reach v1.0

Working backward from this test, the gaps are:

1. **Close the interspect routing loop end-to-end.** Override *generation* must be automated, not human-initiated. The evidence pipeline needs to autonomously propose and apply routing changes when prediction error exceeds a threshold. (Current: plumbing exists, pump is manual.)

2. **Close at least two more calibration loops.** Gate threshold calibration (gate pass/fail rates feeding back to threshold adjustment) and phase-cost calibration (estimated vs. actual phase costs feeding back to estimates) must run autonomously. (Current: `calibrate-phase-costs` exists but requires manual invocation; gate thresholds are hardcoded defaults.)

3. **Build minimal S4.** The system needs at least one autonomous environmental-sensing mechanism. Candidate: a hook that runs on a schedule (not per-session), queries model capability changes via API, and flags routing-relevant shifts. This doesn't need to be sophisticated — even a weekly check of available models against the fleet registry would satisfy Beer's S4 minimum.

4. **Wire complexity-aware routing into production.** The B2 infrastructure exists but has "zero production callers." This is the variety amplification mechanism that the requisite variety analysis identifies as necessary.

5. **Make the mutation store feed back into agent composition.** interlab records mutation quality signals. These signals should influence which approaches future agents attempt — not just within /autoresearch campaigns but across normal sprint execution.

---

## 8. The Pre-v1.0 Milestones

Based on the framework analysis, the path from v0.6 to v1.0 has three natural milestones that correspond to framework thresholds:

### v0.7: First Closed Loop (Stigmergic Phase 1.5)
- Interspect routing overrides generated and applied automatically
- Sprint outcomes measurably influence next sprint routing
- **Framework:** Stigmergic trail formation begins; Friston's perceptual inference loop closes

### v0.8: Multiple Closed Loops (Proto-Autopoiesis)
- Gate thresholds calibrate from outcome history
- Phase-cost estimates calibrate from actuals
- Routing calibrates from evidence
- Three independent feedback dimensions operational
- **Framework:** Autopoietic closure over operational logic (not substrate); dissipative bifurcation point approached

### v0.9: Environmental Coupling (VSM Complete)
- S4 intelligence system operational (minimal environmental scanning)
- Algedonic channel for critical failures (bypass normal processing)
- Complexity-aware routing in production with real dispatchers
- **Framework:** VSM viability achieved; requisite variety gap below 20% for core use cases

### v1.0: Deletion-Recovery (Full Viability)
- System passes the deletion-recovery test
- Calibration state is load-bearing AND self-reproducing
- All five VSM systems present and operational
- **Framework:** All six frameworks satisfied simultaneously

---

## Sources

### Stafford Beer's Viable System Model
- [Viable System Model (Stafford Beer) | Systems Thinking](https://umbrex.com/resources/frameworks/organization-frameworks/viable-system-model-stafford-beer/)
- [Your Multi-Agent Framework Handles Operations. What About the Other Five? - DEV Community](https://dev.to/philippenderle/your-multi-agent-framework-handles-operations-what-about-the-other-five-3hlj)
- [The Levels of Agentic Coding - Tim Kellogg](https://timkellogg.me/blog/2026/01/20/agentic-coding-vsm)
- [Viable system model - Wikipedia](https://en.wikipedia.org/wiki/Viable_system_model)
- [Stafford Beer's Viable System Model (VSM) - BusinessBalls.com](https://www.businessballs.com/strategy-innovation/viable-system-model-stafford-beer/)

### Autopoiesis
- [Autopoiesis - Wikipedia](https://en.wikipedia.org/wiki/Autopoiesis)
- [A Study of "Organizational Closure" and Autopoiesis - Harish's Notebook](http://harishsnotebook.com/2019/07/21/a-study-of-organizational-closure-and-autopoiesis/)
- [Autopoiesis: How Maturana & Varela Redefined Life | Ideasthesia](https://www.ideasthesia.org/the-biologists-who-redefined-life-maturana-varela-and-the-autopoietic-revolution/)
- [Niklas Luhmann: What is Autopoiesis?](https://criticallegalthinking.com/2022/01/10/niklas-luhmann-what-is-autopoiesis/)
- [Allopoiesis - Grokipedia](https://grokipedia.com/page/allopoiesis)

### Thermodynamics and Free Energy
- [Prigogine Nobel Lecture: Time, Structure and Fluctuations (1977)](https://www.nobelprize.org/uploads/2018/06/prigogine-lecture.pdf)
- [Active Inference and the Free Energy Principle - Engineering Notes](https://notes.muthu.co/2026/02/active-inference-and-the-free-energy-principle-how-agents-minimize-surprise-instead-of-maximizing-reward/)
- [Free energy principle - Wikipedia](https://en.wikipedia.org/wiki/Free_energy_principle)
- [Dissipative system - Wikipedia](https://en.wikipedia.org/wiki/Dissipative_system)
- [Dissipative Structures, Organisms and Evolution - PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC7712552/)

### Stigmergy
- [Phase transition between disordered and ordered foraging in Pharaoh's ants | PNAS](https://www.pnas.org/doi/10.1073/pnas.161285298)
- [Stigmergy - Wikipedia](https://en.wikipedia.org/wiki/Stigmergy)
- [Why Multi-Agent Systems Don't Need Managers: Lessons from Ant Colonies](https://www.rodriguez.today/articles/emergent-coordination-without-managers)
- [Stigmergic Independent Reinforcement Learning for Multi-Agent Collaboration](https://arxiv.org/abs/1911.12504)

### Requisite Variety
- [W. Ross Ashby, Cybernetics and Requisite Variety (1956)](https://www.panarchy.org/ashby/variety.1956.html)
- [Ashby's Law of Requisite Variety - BusinessBalls.com](https://www.businessballs.com/strategy-innovation/ashbys-law-of-requisite-variety/)
- [Requisite Variety, Autopoiesis, and Self-organization](https://arxiv.org/pdf/1409.7475)
