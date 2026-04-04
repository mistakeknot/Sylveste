# Algedonic Signal Systems for an Autonomous AI Factory Policy Engine

**Research Date:** 2026-04-02
**Researcher:** Best Practices Analysis Agent
**Scope:** Cross-domain algedonic signal patterns for Ockham — the Sylveste factory governor
**Framing:** Ockham shapes dispatch via weights and authority grants; it never dispatches directly. Three autonomy ratchet modes: shadow / supervised / autonomous. Three candidate designs: (A) passive dashboard, (B) active circuit breakers, (C) tiered passive-below / active-above threshold.

---

## Executive Summary

Five domains converge on a single structural pattern: **tiered response with bypass**. The signal taxonomy is always pain-first (asymmetric), the response hierarchy always has a slow path and a fast path, and every mature system learned to distinguish "too many signals" from "not enough signals" — often from an accident. The most consequential finding: algedonic channels that do not bypass normal management chains are not algedonic channels. They are just another queue. Design C (tiered passive-below / active-above) is the closest analog to what every successful real-world implementation has converged on. The specific mapping to Ockham's three modes is the main contribution of this document.

---

## Domain 1: Stafford Beer's VSM — Algedonic Channels in Practice

### Signal Taxonomy

Beer defined algedonic signals as the **pain/pleasure channel** that cuts across the VSM's five subsystems. The signal is binary in intent: "crossing a threshold of significance." The implementation taxonomy from Cybersyn:

- **Production alarm** — a factory metric fell outside the statistically normal range (computed by Cyberstride software from rolling variance)
- **Cascade alarm** — a System 1 unit failed to self-correct within a defined timeout
- **Structural alarm** — capability-actuality gap has been widening trend over multiple periods (slow-burn equivalent)

Pleasure signals existed in theory but were rarely operationalized. In real deployments, the channel was almost exclusively pain-carrying.

### Response Hierarchy

The VSM algedonic design has two explicit properties that are frequently dropped in naive implementations:

1. **Autonomy-first, escalation-second.** The signal first notifies the affected System 1 unit (the factory). That unit gets a timeout window to self-correct. Only on timeout does the signal propagate upward to System 3 (operations management). Only on a second timeout (or explicit escalation flag) does it reach System 5 (policy/identity).

2. **Hierarchy bypass.** If the severity is high enough, the signal skips S2/S3/S4 and goes directly to S5. This is not optional — it is the defining property of the algedonic channel. A signal that must traverse the normal chain is not algedonic.

The Cybersyn truck-strike deployment (1972) demonstrated this working: algedonic signals flooded into the Cybernet telex system; the Operations Room received direct visibility; the government was able to route ~10–30% of normal transport capacity to achieve full supply within 24 hours. The channel bypassed the normal ministerial hierarchy.

### Failure Modes

- **No bypass implementation.** Many VSM-inspired systems describe algedonic signals as a concept but implement them as a slightly-faster reporting pipeline. The bypass is what makes the channel valuable.
- **Threshold instability.** Cyberstride used statistical range detection. If the baseline is poorly calibrated (common in newly nationalized industries), the signal fires constantly — the VSM equivalent of alarm flooding.
- **Pleasure signals ignored.** The channel's positive feedback function (improving cycle time, shrinking backlog) was never operationalized in any known deployment. Real systems only used pain. This is a gap, not a design choice.
- **Missing from reference diagrams.** Tom Graves documented that algedonic signal channels are "often absent from standard VSM reference diagrams," leading to system designs that omit them entirely, leaving S5 blind to operational pain until it traverses the normal hierarchy — which can take weeks.

### Mapping to Ockham

| VSM Concept | Ockham Equivalent |
|---|---|
| System 1 (operational units) | Individual agents / bead sessions |
| System 3 (operational management) | Clavain dispatch + sprint management |
| System 5 (policy/identity) | Ockham intent directives + authority tiers |
| Algedonic signal | `anomaly.Signal` firing to Ockham, bypassing Clavain |
| Cyberstride threshold detection | `anomaly.Detector` computing rolling variance |
| Autonomy-first timeout | Agent gets N minutes to self-correct before signal propagates |

The critical VSM lesson for Ockham: the signal must be able to reach Ockham **without going through Clavain's normal dispatch loop**. If the signal is just a bead state change that Clavain notices on its next poll, the bypass property is lost.

### Confidence: High
### Sources
- [Project Cybersyn — Wikipedia](https://en.wikipedia.org/wiki/Project_Cybersyn)
- [VSM — Viable System Model Wikipedia](https://en.wikipedia.org/wiki/Viable_system_model)
- [Stafford Beer — Archania](https://www.archania.org/wiki/Individuals/Scientists/Stafford_Beer)
- [Pervasives and the VSM algedonic link — Tom Graves / Tetradian](https://weblog.tetradian.com/2015/07/27/pervasives-and-the-vsm-algedonic-link/)
- [VSM — The Architecture of Viability — Strix Research](https://strix.timkellogg.me/vsm-viable-system-model)
- [Cybernetics of Governance: The Cybersyn Project 1971–1973 — ResearchGate](https://www.researchgate.net/publication/290742382_Cybernetics_of_Governance_The_Cybersyn_Project_1971-1973)

---

## Domain 2: SRE Incident Response — Error Budgets, Burn Rates, and Escalation Tiers

### Signal Taxonomy

Google SRE formalizes a three-level signal taxonomy using **burn rate** as the primary signal dimension:

- **Fast burn (pain, immediate):** Burn rate ≥ 14.4× baseline over a 1-hour window. Consumes a full hour's budget in minutes. Page on-call now.
- **Slow burn (pain, deferred):** Burn rate ≥ 2× baseline over a 24-hour window. Budget exhaustion in days. File a ticket; SRE investigates before next week.
- **Budget exhausted (pain, structural):** Error budget at zero. Development velocity freezes until SLO is restored. Feature work stops; reliability work is mandatory.
- **Budget healthy (pleasure, passive):** Budget being consumed at ≤1× baseline. No signal. Healthy state is the absence of signal, not a positive signal.

The multi-window approach (long window for detection, short window — 1/12 of long — for confirmation) prevents false positives from transient spikes. This is the SRE equivalent of VSM's "autonomy-first timeout" before escalation.

### Response Hierarchy

The SRE escalation chain has explicit, pre-defined decision points — not judgment calls:

1. **Auto-remediate first.** Kubernetes liveness probes restart broken containers. Circuit breakers trip and redirect traffic. Rollback policies revert bad deploys. No human involved.
2. **Page if auto-remediate fails or if customer-facing SLO is breached.** The decision rule is mechanical: `if (burn_rate >= threshold AND window_confirmed) -> page`. The SRE is first responder.
3. **Escalate to developers if SRE cannot resolve within 1 week.** This is the slow cascade.
4. **Freeze feature velocity if budget exhausted.** This is the autonomy ratchet equivalent: the policy engine changes what the system is allowed to do.

The key architectural distinction for Ockham: **the policy engine (error budget policy) is not the orchestrator (runbook execution)**. Error budget policy says "what is allowed"; the runbook handles "what to do." This matches Ockham's role exactly.

The Kubernetes probe taxonomy maps directly to Ockham's signal types:
- **Liveness probe** = agent health check (is the agent process alive?)
- **Readiness probe** = dispatch eligibility (is the agent ready to take work?)
- **Startup probe** = agent initialization (is the agent in a known good state?)

Critically: liveness probes must NOT depend on external systems. If Ockham's circuit breaker trips based on a downstream dependency failure that isn't the agent's fault, agents get stuck in a restart loop.

### Failure Modes

- **Page storm.** Paging on every alarm rather than on significant burn rate events creates alert fatigue. The pre-ISA-18.2 equivalent in SRE: before multi-window burn rate, teams received hundreds of spurious pages per week. This caused oncall burnout and desensitization. The fix: page on "significant fraction of budget consumed," not on "any SLO violation."
- **Automation bias.** Auto-remediation running silently for weeks hides gradual structural degradation. The system looks healthy (no pages) while the underlying problem worsens. Fix: slow-burn detection catches the drift before budget exhaustion.
- **Policy-execution conflation.** Teams that put remediation logic inside the policy engine cannot distinguish "what is allowed" from "what to do." When remediation logic misfires, the policy engine is blamed and disabled — leaving no governance at all.
- **Liveness probe misconfiguration.** Probes that depend on external services (database, cache) cause cascade restarts when the dependency fails. The probe signals agent failure, but the agent is not the source of the problem.

### Mapping to Ockham

| SRE Concept | Ockham Equivalent |
|---|---|
| Error budget burn rate | Bead failure rate, cycle time drift, gate failure rate |
| Fast burn threshold (14.4×) | Circuit breaker trip condition |
| Slow burn threshold (2×) | Dispatch weight adjustment threshold |
| Budget exhaustion → velocity freeze | Autonomy ratchet demotion (autonomous → supervised) |
| Liveness probe | Agent heartbeat check (is session alive?) |
| Readiness probe | Authority check (is agent authorized for this domain?) |
| Policy engine | Ockham (separate from Clavain runbook execution) |
| Multi-window confirmation | Require signal to persist across two measurement windows before acting |

The SRE two-window pattern is directly implementable in Ockham: require a pain signal to persist in both a short window (1 hour) and a long window (24 hours) before triggering a policy response. This prevents transient spikes from demoting the autonomy ratchet.

### Confidence: High
### Sources
- [Google SRE — Error Budget Policy](https://sre.google/workbook/error-budget-policy/)
- [Google SRE — Alerting on SLOs (multi-window burn rate)](https://sre.google/workbook/alerting-on-slos/)
- [Google Cloud — Example Escalation Policy](https://cloud.google.com/blog/products/gcp/an-example-escalation-policy-cre-life-lessons)
- [Nobl9 — Fast and Slow Burn](https://docs.nobl9.com/alerting/alerting-use-cases/fast-and-slow-burn/)
- [Datadog — Burn Rate Is a Better Error Rate](https://www.datadoghq.com/blog/burn-rate-is-better-error-rate/)
- [Kubernetes — Liveness, Readiness, Startup Probes](https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/)
- [PagerDuty — Escalation Policy Basics](https://support.pagerduty.com/main/docs/escalation-policies)

---

## Domain 3: Autonomous Vehicle Safety — Disengagement Hierarchy and Degraded Modes

### Signal Taxonomy

The AV safety framework (SAE J3016, NHTSA ADS 2.0) defines signals as **operational domain departure events**:

- **ODD boundary approach** — vehicle is operating near the edge of its Operational Design Domain (weather, speed, road type). Not yet a failure; a precondition signal. Equivalent to "entering the amber zone."
- **Sensor degradation** — one sensor stream has reduced confidence or has failed. Adaptive compensation kicks in: remaining sensors are weighted more heavily, speed is reduced, maneuver repertoire shrinks.
- **Functional failure** — ADS cannot maintain DDT (Dynamic Driving Task) to specification. Must transition to degraded mode or initiate fallback.
- **Minimal Risk Condition trigger** — ADS cannot or should not continue the mission. Must reach a safe stopped state.

The fallback strategy for Level 4+ ADS (Waymo / Mercedes Safety First) defines **three degraded levels with seven fallback scenarios**, matching signal type to response:

| Level | Signal Type | Response |
|---|---|---|
| Degraded-1 | Sensor degradation, within ODD | Adaptive compensation, reduced speed, continue |
| Degraded-2 | Functional failure, still navigable | Reduced ODD, reduced maneuvers, pull-over preparation |
| Degraded-3 | Mission-blocking failure | Minimal Risk Condition: stop in lane or pull over |

### Response Hierarchy

The AV disengagement hierarchy demonstrates four key properties:

1. **Degraded mode over hard stop.** The system attempts to continue operating at reduced capability before escalating to a full stop. This preserves mission value while managing risk. Hard stops are the last resort.

2. **Proportional response.** The response scales to the degradation signal's severity. Losing one lidar returns → reduced speed. Losing all positioning → stop.

3. **Context-dependent MRC.** The Minimal Risk Condition is not "stop in place." It is "reach the lowest-risk achievable state given current conditions." Sometimes that means continuing at low speed to a pull-off. Stopping in a lane on a highway is worse than stopping at a shoulder. The system must evaluate the environment at the time fallback triggers.

4. **Transparency requirement.** NHTSA requires the ADS to notify the human of its status — degraded mode, failure, or MRC — in a way that enables oversight. The human must be able to understand why the system changed behavior.

### Failure Modes

- **Single-level MRC.** Early ADS designs had a single "stop in place" fallback. This was worse than context-dependent MRC in many scenarios (highway lane stops are dangerous). Real systems need a hierarchy of safe states.
- **Sensor fusion overconfidence.** Systems that weighted redundant sensors equally (rather than degrading gracefully when one failed) suffered from compounded errors when multiple sensors degraded simultaneously.
- **Disengagement reporting gaming.** Tesla's early disengagement reports were criticized because "disengagement" was defined by manufacturer, not by NHTSA. Companies could choose not to count certain failure events. The lesson: signal definitions must be externally auditable.
- **Missing opacity on degraded state.** Operators and passengers were not always notified when the system entered a degraded mode. The system appeared normal while operating at reduced confidence. Failures occurred because humans did not know they needed to take over.

### Mapping to Ockham

| AV Concept | Ockham Equivalent |
|---|---|
| ODD boundary | Autonomy ratchet mode boundary (shadow / supervised / autonomous) |
| Sensor degradation → adaptive compensation | Partial pain signal → adjust dispatch weights (stay in current mode) |
| Functional failure → degraded ODD | Persistent pain signal → tighten authority grants (reduce scope) |
| Minimal Risk Condition | Autonomy ratchet demotion (or human halt) |
| Context-dependent MRC | Demotion target depends on factory state (don't drop to shadow if supervised works) |
| Transparency requirement | Ockham must explain why a policy change occurred (audit trail + Meadowsyn surface) |
| Fallback hierarchy (3 levels, 7 scenarios) | Signal severity tiers map to distinct policy responses, not just on/off |

The AV lesson most applicable to Ockham's three candidate designs: **Design A (passive dashboard) is the equivalent of no MRC — the factory appears healthy to the policy engine while degrading**. Design B (active circuit breakers) is a single-level MRC — good for critical failures, but harsh for moderate degradation. Design C (tiered passive-below / active-above) maps directly to the AV degraded-mode hierarchy.

### Confidence: High (structural lessons); Medium (Waymo-specific thresholds, not public)
### Sources
- [NHTSA — Automated Driving Systems 2.0](https://www.nhtsa.gov/sites/nhtsa.gov/files/documents/13069a-ads2.0_090617_v9a_tag.pdf)
- [Minimal Risk Condition — Stanford CyberLaw Blog](https://cyberlaw.stanford.edu/blog/2022/01/deep-weeds-levels-driving-automation-lurks-ambiguous-minimal-risk-condition/)
- [Minimal Risk Condition for Safety Assurance — HAL Science](https://hal.science/hal-03365857/document)
- [Fallback Strategy for Level 4+ ADS — Semantic Scholar](https://www.semanticscholar.org/paper/Fallback-Strategy-for-Level-4+-Automated-Driving-Yu-Luo/181d690b47a59ae16d0439156806973c56681268)
- [Waymo Safety Case Approach White Paper](https://assets.ctfassets.net/e6t5diu0txbw/66jOjPtNIjzawaK0ZjpU3q/7f081b392cf29a3355c97d0d758fe6cf/Waymo_Safety_Case_Approach.pdf)
- [SAE J3016 User Guide — CMU](https://users.ece.cmu.edu/~koopman/j3016/index.html)

---

## Domain 4: Industrial Control (SCADA/DCS) — Alarm Management and ISA-18.2

### Signal Taxonomy

ISA-18.2 defines an alarm as a signal that is **abnormal, actionable, has a consequence, is relevant, and is unique**. The five-part test eliminates the following non-alarms: informational messages, routine status updates, duplicate alarms for the same root cause, and alarms with no operator response available.

The ISA-18.2 taxonomy distinguishes signal types by response urgency:

- **Critical alarm** — requires operator action within minutes to prevent a safety incident. Maximum 10% of alarm population.
- **High priority alarm** — requires action within 10–30 minutes. 
- **Medium / Low priority** — informational but tracked; no immediate response required.
- **Alarm flood** — defined as >10 alarms per operator per 10-minute period. A flood is a systemic failure, not a collection of individual alarms.

### Response Hierarchy

ISA-18.2 defines the alarm lifecycle as nine stages, but the key operational insight is the **suppression vs. shelving distinction**:

- **Suppression** is a safety function: deliberately silencing an alarm during a known non-critical state (startup, maintenance, testing). Must be designed in. Must have a condition that re-enables the alarm automatically.
- **Shelving** is an operator action: temporarily hiding an alarm they cannot currently respond to. Must have a time limit. Must never hide critical alarms.
- **Disabling** is a management function: removing an alarm from the system. Requires authorization and documentation. Should be rare.

The most important ISA-18.2 finding: **root-cause alarming, not consequence alarming.** A single root failure in a chemical plant can generate hundreds of downstream alarms. The correct response is to alarm the root cause once, not the 200 downstream consequences. This requires explicit alarm rationalization — mapping root causes to alarms during system design.

Real-world result: the Solvay Novecare plant reduced alarm load by 84% through rationalization without losing meaningful coverage. The Texaco Milford Haven explosion (1994) involved 275 alarms in 11 minutes — operators missed the critical one. The BP Texas City disaster involved key alarm devices failing entirely.

### Failure Modes

- **Alarm flood → alarm blindness.** When operators receive more than 10 alarms/10 minutes, they begin triaging by ignoring alarms rather than by priority. The most critical alarm can be missed entirely.
- **Crying wolf effect.** Nuisance alarms (alarms that fire frequently but require no action) desensitize operators to all alarms. One plant found its operators had been silencing a "critical" alarm for months because it was always spurious. It was eventually real.
- **Consequence alarming.** Alarming every downstream effect of a single root cause generates a flood on every incident. Operators see the effects, not the cause. The flood itself impairs their ability to identify the root.
- **Suppression without condition.** Suppressing an alarm "temporarily" without an automatic re-enable condition means the alarm silently stays suppressed forever. The operator who suppressed it moved on; no one re-enabled it.
- **Single priority level.** Systems where all alarms are equally "important" provide no guidance on what to respond to first. Operators invent their own triage heuristics, which are inconsistent.

### Mapping to Ockham

| ISA-18.2 Concept | Ockham Equivalent |
|---|---|
| Five-part alarm test (abnormal, actionable, consequence, relevant, unique) | Signal qualification: does this anomaly meet all five criteria before surfacing? |
| Root-cause alarming, not consequence alarming | Alert on the root cause (agent circuit breaker) not every downstream consequence (beads blocked by that agent) |
| Suppression with auto-re-enable | Silencing a Meadowsyn alert during known maintenance, with automatic reinstatement |
| Shelving with time limit | Deferring a non-critical signal during sprint crunch, expiring after N hours |
| Flood threshold (10/10min) | Ockham must not emit more than N signals per M minutes to Meadowsyn |
| Priority tiers (critical / high / medium / low) | Ockham signal severity levels (circuit-breaker trip / dispatch adjustment / informational) |
| Alarm rationalization | Pre-build signal-to-action mapping; every signal should have a defined Ockham response |

The ISA-18.2 lesson most applicable to Ockham's three designs: **Design B (active circuit breakers only) risks the consequence-alarming failure mode** — tripping a circuit breaker for every downstream effect of a single agent failure floods Meadowsyn and Ockham alike. **Design C** requires explicit rationalization: define which signals are root causes, which are consequences, and suppress consequences when the root is already in circuit-breaker state.

The five-part test is directly applicable to Ockham signal qualification: before emitting a signal, check:
1. Is this genuinely abnormal (compared to rolling baseline)?
2. Is there an action Ockham can take?
3. Does ignoring it have a consequence?
4. Is it relevant to the current factory state?
5. Is it unique (not duplicating a signal already in flight for this root cause)?

### Confidence: High
### Sources
- [ISA-18.2 Implementing Alarm Management — Yokogawa](https://www.yokogawa.com/us/library/resources/media-publications/implementing-alarm-management-per-the-ansi-isa-182-standard-control-engineering/)
- [Industrial Alarm Management Best Practices — Optizeus](https://optizeus.org/blog/industrial-alarm-management-best-practices)
- [From Alarm Floods to Highly Protected Status — ISA InTech](https://www.isa.org/intech-home/2021/august-2021/features/from-alarm-floods-to-highly-protected-status)
- [Alarm Floods and Plant Incidents — Digital Refining](https://www.digitalrefining.com/article/1000558/alarm-floods-and-plant-incidents)
- [Best Practices with Alarm Management — Emerson Automation](https://www.emersonautomationexperts.com/2025/industrial-software/best-practices-with-alarm-management/)
- [Alarm Rationalization White Paper — Emerson DeltaV](https://www.emerson.com/documents/automation/white-paper-alarm-rationalization-deltav-en-56654.pdf)

---

## Domain 5: Multi-Agent Systems Research — Stigmergy and Collective Degradation

### Signal Taxonomy

Swarm and multi-agent systems use **environmental signals** rather than direct agent-to-agent communication. The signal types:

- **Pheromone trail** — a positive signal indicating a viable path or resource location. Decays over time. Reinforced by successful traversals.
- **Absence of pheromone** — a negative signal indicating an abandoned path. No explicit "this path failed" signal; the trail simply decays away.
- **Heartbeat / census signal** — in engineered swarms (not biological), agents emit health signals at intervals. Missing heartbeats indicate failure.
- **Quorum signal** — a threshold-based collective decision. A behavior is adopted when N% of the population signals agreement. Used for Byzantine fault tolerance in SWARM+ and similar frameworks.

The key distinction from other domains: **stigmergic signals are implicit** (pheromone decay, absence of trail) rather than explicit (alarm, page, circuit breaker). This makes them robust to individual agent failures but slow to detect coordinated or systematic failures.

### Response Hierarchy

Decentralized multi-agent systems use a three-tier response:

1. **Individual adaptation.** Each agent adjusts its behavior based on local signal density. No central authority involved. Fast, local, robust.
2. **Population drift.** If many agents are adapting in the same direction (e.g., all avoiding the same path), the population behavior shifts. This is detectable as a pattern but requires population-level observation.
3. **Quorum-based response.** Explicit collective decision when population drift reaches a threshold. SWARM+ implements this via consensus protocols; biological swarms via density thresholds.

SWARM+ (2026) uses multi-signal failure detection: gRPC health check failures (consecutive failures trigger peer status callbacks) AND Redis heartbeat expiry (agents not updating state within window are marked stale). The combination prevents false positives from transient failures — both signals must agree.

Research finding on density limits: pheromone stigmergy degrades in very high-density agent populations. Above a critical density, the pheromone signal becomes saturated, and simple stigmergic avoidance performs no better than random walking. This is directly relevant: Ockham should not rely on a purely implicit/stigmergic signal model for a factory with many agents operating in the same domain.

Agent population sensitivity: losing 2 of 12 agents degrades coordination measurably. Trace corruption causes ~14% degradation; agent failure causes ~21% degradation. These are empirical baseline numbers for degradation detection thresholds.

### Failure Modes

- **Decay rate mismatch.** If pheromone decays too slowly, outdated information persists and agents follow stale trails. If it decays too quickly, information is lost before enough agents can act on it. The correct decay rate is a function of agent density and update frequency — not a fixed constant.
- **Saturation in high density.** At large N, pheromone signals saturate. The system loses the ability to differentiate "very good path" from "good path" — all trails look equally attractive. This is the multi-agent equivalent of alarm flooding.
- **No explicit "this failed" signal.** Stigmergic systems detect failures through absence, not presence. A path that causes agents to fail simply doesn't get reinforced, and decays. This means the system is slow to react to novel failures with no historical trail data.
- **No collective health observable.** In purely stigmergic systems, there is no single "health score" for the collective. Health must be inferred from population behavior statistics. This requires an external observer role (Alwe in the Sylveste architecture).

### Mapping to Ockham

| Swarm Concept | Ockham Equivalent |
|---|---|
| Pheromone trail | Dispatch weight — agents reinforced for successful completions in a domain |
| Pheromone decay | Dispatch weight decay when domain is inactive or has mixed results |
| Heartbeat + quorum (SWARM+) | Multi-signal confirmation before triggering policy response |
| Population drift detection | Alwe observes aggregate agent behavior; Ockham receives synthesized pattern signal |
| Quorum threshold | N% of signals in agreement before ratchet demotion (not single-event trigger) |
| Decay rate tuning | Ockham's signal window lengths should be configurable, not hardcoded |
| External observer role | Alwe (not Ockham itself) observes population-level behavior |

The swarm research finding most applicable to Ockham: **the policy engine should not be both the observer and the actor**. In swarm systems that have been successfully scaled, observation (Alwe) is separated from policy response (Ockham). When the observer and policy engine are conflated, the system cannot distinguish "I am detecting this because I caused it" from genuine external signal.

### Confidence: Medium (theoretical; production deployments of SWARM+ are very recent)
### Sources
- [Phormica: Photochromic Pheromone Release and Detection System — PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC7805914/)
- [Testing the Limits of Pheromone Stigmergy — PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC6894587/)
- [SWARM+: Scalable and Resilient Multi-Agent Consensus — arXiv](https://arxiv.org/html/2603.19431)
- [Generic, Scalable, Decentralized Fault Detection for Robot Swarms — PLOS One](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0182058)
- [Emergent Collective Memory in Decentralized Multi-Agent AI Systems — arXiv](https://arxiv.org/html/2512.10166)
- [Collective Stigmergic Optimization for Multi-Agentic AI Systems — Medium](https://medium.com/@jsmith0475/collective-stigmergic-optimization-leveraging-ant-colony-emergent-properties-for-multi-agent-ai-55fa5e80456a)

---

## Synthesis: Cross-Domain Pattern Map

### The Universal Structure

All five domains converge on the same three-layer architecture:

```
Layer 1: Local adaptation (agent self-corrects, AV degrades gracefully, K8s probe restarts)
Layer 2: Policy adjustment (VSM S3 adjusts, error budget adjusts weights, MRC level 2)
Layer 3: Human escalation + ratchet change (VSM S5 wakes, SRE pages, AV hands off, ISA critical alarm, quorum threshold)
```

The algedonic channel is the mechanism that **allows Layer 1 signals to reach Layer 3 directly** when the severity justifies bypassing Layer 2.

### Signal Taxonomy for Ockham

Drawing from all five domains, Ockham needs four signal categories:

| Category | Trigger | Response Layer | Bypass Layer 2? |
|---|---|---|---|
| **Heartbeat failure** (agent dead) | Missing session heartbeat | Layer 1: claim reclaimed | No |
| **Performance drift** (slow burn) | Metric trending outside 2× baseline over 24h window | Layer 2: dispatch weight adjustment | No |
| **Circuit breaker trip** (fast burn) | Metric at 14.4× baseline over 1h window, or gate failure rate > threshold | Layer 2: authority tightening + ratchet warning | No |
| **Factory-level crisis** (algedonic) | Multiple circuit breakers tripped AND ratchet in autonomous mode, OR principal halt signal | Layer 3: autonomy ratchet demotion + human surface | **Yes — bypass Clavain** |

The bypass condition is the key design decision. Not every circuit breaker is algedonic. Only the combination of "multiple failures AND operating in a mode where human oversight is reduced" is algedonic.

### Response Hierarchy for Ockham

```
Signal arrives at anomaly.Detector
│
├── Qualify signal (ISA-18.2 five-part test)
│     If not qualified: discard (not abnormal, not actionable, consequence is trivial, not relevant, or duplicate)
│
├── Check if root cause already in circuit-breaker state
│     If yes: suppress downstream consequences (root-cause alarming)
│
├── Multi-window confirmation (SRE pattern)
│     Short window (1h) + long window (24h) both showing elevated signal?
│     If no: log to Meadowsyn as informational only
│
├── Determine severity tier
│     Performance drift → adjust dispatch weights (no human notification)
│     Circuit breaker → adjust authority grants + surface to Meadowsyn (no human page)
│     Factory crisis → autonomy ratchet demotion + require human acknowledgment
│
└── Bypass trigger (algedonic)
      Crisis-level + autonomous mode → signal directly to Meadowsyn ops surface + block dispatch
      (does not go through Clavain's normal dispatch loop)
```

### Design Verdict: C is Correct, With Qualifications

**Design A (passive dashboard)** is VSM without the algedonic channel — the policy engine is blind to pain until a human checks the dashboard. Fails under the AV "missing degraded state opacity" failure mode and the SCADA "alarm blindness" failure mode.

**Design B (active circuit breakers)** collapses all signal tiers into one response, producing the industrial consequence-alarming failure mode. Every downstream effect of a single agent failure trips a circuit breaker. Meadowsyn floods; human is paged for noise; autonomy ratchet is demoted unnecessarily.

**Design C (tiered)** maps correctly to every domain's mature implementation:
- Passive (weight adjustment) below the circuit breaker threshold — matches VSM's "autonomy-first timeout" and AV's "degraded mode, continue"
- Active (circuit breaker + authority tightening) above the threshold — matches SRE's "fast burn page" and AV's "functional failure → reduced ODD"
- Algedonic bypass for factory-level crisis — matches VSM's direct S1→S5 channel and AV's MRC

The qualifications Design C must incorporate to avoid known failure modes:

1. **Signal qualification gate** (ISA-18.2): not everything that deviates is an alarm
2. **Root-cause deduplication** (ISA-18.2): suppress downstream consequences when root is already in circuit-breaker state
3. **Multi-window confirmation** (SRE): require both short and long window elevation before acting
4. **Pleasure signals** (VSM gap): implement positive feedback (clean completions, improving cycle time) as explicit signals that can loosen authority grants and advance the ratchet — not just the absence of pain
5. **Alwe separation** (swarm): Ockham does not observe its own policy effects; Alwe observes, Ockham acts
6. **Context-dependent ratchet demotion** (AV): don't always demote to shadow; demote to the lowest ratchet level that restores safety, not the absolute minimum

---

## Gaps and Open Questions

1. **Pleasure signal operationalization.** No domain has a fully working positive feedback channel. VSM described it; no deployment used it. SRE's error budget positive state is "no page" (absence). The design for how Ockham emits pleasure signals (and what policy changes they enable) is not covered by existing research.

2. **Ratchet promotion criteria.** All domains are clear on demotion triggers. Promotion triggers (supervised → autonomous) are underspecified. The AV research notes that ADS qualification requires "rigorous testing at scale," which is not a policy-engine function. The criteria for Ockham to emit a "trust is being earned" signal are not addressed by any domain.

3. **Threshold calibration in early factory operation.** ISA-18.2 and VSM both note that threshold calibration requires operational data. In early shadow mode, there is no baseline. The correct approach (from SRE: start with wide windows, tighten over time) needs explicit guidance for Ockham's cold-start period.

4. **Multi-ratchet-level signaling.** The current Ockham design has one ratchet. If different domains operate at different ratchet levels simultaneously (auth domain in supervised, performance domain in autonomous), domain-specific circuit breakers need domain-specific ratchet state. Cross-domain interference is not addressed by the current architecture.

5. **Signal latency vs. Meadowsyn polling.** If Meadowsyn polls Ockham rather than receiving push signals, there is an inherent latency between a factory-level crisis and human visibility. The VSM algedonic channel is explicitly a push channel. The implementation choice (push vs. poll) for the bypass channel is not resolved.

---

## Confidence Summary

| Domain | Confidence | Basis |
|---|---|---|
| VSM / Cybersyn | High | Primary historical sources; Beer's own documentation |
| SRE (Google + PagerDuty) | High | Production implementations; public documentation |
| AV Safety (NHTSA / SAE J3016) | High (structural), Medium (Waymo specifics) | Public standards; Waymo safety papers |
| Industrial Alarm (ISA-18.2) | High | Industry standard; multiple case studies with quantified outcomes |
| Multi-Agent Swarms | Medium | Research papers; SWARM+ is very new; production data thin |

---

<!-- flux-research:complete -->
