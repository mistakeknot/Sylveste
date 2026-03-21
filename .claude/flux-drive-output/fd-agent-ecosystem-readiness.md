# What Should v1.0.0 Mean for Demarch?

**Date:** 2026-03-21
**Status:** Research complete
**Context:** Demarch is at v0.6.228. The platform orchestrates autonomous software development using evolving AI models. This document defines what "production ready" means for an agentic platform whose behavior is inherently model-dependent.

---

## 1. The Three Layers of Stability in an Agentic Platform

Traditional semver assumes deterministic software: given the same inputs, the same version produces the same outputs. Agentic platforms break this assumption because the underlying models change, prompts evolve, and routing decisions adapt based on evidence. Demarch must distinguish three independent stability axes:

### Layer S1: Structural API Stability

What it covers: CLI interfaces (`ic` commands, `bd` commands), plugin manifest schemas, hook contract shapes, event stream formats, kernel data model (runs, phases, gates, dispatches, state, locks), inter-layer communication contracts (L1/L2/L3 boundaries).

**This is what semver can promise.** If `ic run create` takes certain arguments and returns a certain shape in v1.0.0, it must not change until v2.0.0. Plugins compiled against v1.0 kernel schemas must load in v1.x. Event consumers must not break when the kernel upgrades within v1.x.

Demarch's current state: The L1 kernel (Intercore) already has a write-path contract ("all durable state flows through L1") and the three-layer model has stable ownership boundaries. The `ic` CLI surface is the natural API boundary.

### Layer S2: Behavioral Stability Under Fixed Model Version

What it covers: Given the same model (e.g., Claude Opus 4, GPT-5), the same prompts, the same routing table, and the same input, does the system produce comparable outputs across runs?

**This is what evaluation can measure but semver cannot promise.** Stochastic outputs mean exact reproducibility is impossible. What v1.0 can promise is bounded variance: pass@k reliability (the system succeeds at least once in k attempts), consistent phase progression (brainstorm produces a plan, plan produces a spec, implementation produces code), and gate calibration (gates catch defects they are configured to catch with measurable precision/recall).

Demarch's current state: PHILOSOPHY.md already defines the closed-loop calibration pattern (defaults -> collect -> calibrate -> fallback) and Interspect's signal taxonomy provides the measurement infrastructure. The gap is empirical evidence that calibration converges, not architecture.

### Layer S3: Behavioral Stability Across Model Upgrades

What it covers: When Anthropic ships Claude Opus 5 or OpenAI ships GPT-6, does the platform degrade gracefully, maintain quality floors, and adapt routing without manual intervention?

**This is what v1.0 cannot fully promise and should not pretend to.** Model upgrades are external events that change the platform's behavior in ways no version number can capture. What v1.0 CAN promise is: (a) the system detects behavioral drift via canary windows, (b) quality floors are enforced mechanically rather than assumed, (c) routing adapts based on evidence rather than hardcoded model names, and (d) degradation is bounded (the system fails safely, never silently).

Demarch's current state: Interspect's canary monitoring architecture is designed for exactly this, but the Interspect vision doc (v1.1) describes the system at L0-L2 autonomy. The "detect and adapt" machinery exists architecturally; the question is whether it has been exercised enough to trust.

### What v1.0.0 Must Promise

| Layer | Promise | Enforcement |
|-------|---------|-------------|
| S1 | No breaking API changes until v2.0.0 | Semver + deprecation policy |
| S2 | Bounded behavioral variance, published pass@k metrics | Evaluation suite + regression benchmarks |
| S3 | Graceful degradation on model change, detection within N sprints | Canary windows + quality floors + automatic fallback |

---

## 2. How Existing Frameworks Have Handled Version Declarations

### LangChain: The Cautionary Overhaul (v0.0.x -> v1.0.0, Nov 2025)

**Timeline:** v0.0.x (Oct 2022 - Dec 2023, monolithic), v0.1.0 (Jan 2024, LCEL + LLMChain deprecated), v0.2.0 (May 2024, AgentExecutor deprecated for LangGraph), v0.3.0 (Sep 2024, Pydantic v2 required), v1.0.0 (Nov 2025, create_agent + middleware + stability commitment).

**Stability promise:** No breaking changes until 2.0.0. Deprecated features work throughout 1.x. Migration guide from v0. Legacy functionality moved to `langchain-classic`. Minor versions every 2-3 months.

**What broke:** Every major abstraction was deprecated at least once before v1.0. Chains, AgentExecutor, and the original agent model were all replaced. The community experienced "abstraction whiplash" -- patterns learned in v0.1 were anti-patterns by v0.3.

**Lesson for Demarch:** LangChain reached v1.0 by *removing* abstractions, not adding them. Their v1.0 surface is dramatically smaller than their v0.3 surface. The `create_agent` function + LangGraph replaced an entire taxonomy of chain types. Demarch should resist the temptation to stabilize everything at v1.0 -- stabilize the kernel boundary (S1) and leave the OS layer (Clavain's routing, agents, prompts) explicitly marked as "model-dependent, evolving."

### AutoGen/Microsoft Agent Framework: The Merger (v0.4 -> Microsoft Agent Framework GA, Q1 2026)

**Timeline:** AutoGen v0.2 (stable, widely adopted), AutoGen v0.4 (2025, async messaging rewrite with breaking changes), Microsoft Agent Framework announcement (Oct 2025, merging AutoGen + Semantic Kernel), GA expected Q1 2026.

**Stability promise:** Semantic Kernel will remain under GA support for at least 1 year after Microsoft Agent Framework leaves Preview. Migration guide published.

**What broke:** AutoGen v0.4 was a near-complete rewrite (async messaging, event-driven architecture). Documentation lagged the code. Microsoft then announced the merge into a new framework, making v0.4 itself a transitional state. Users who adopted v0.4 now face a second migration.

**Lesson for Demarch:** Rewriting a framework mid-adoption is catastrophic for trust. AutoGen had 54K GitHub stars and enterprise adoption, yet the v0.4 rewrite + framework merger created two consecutive breaking transitions. Demarch's philosophy of "strangler-fig, never rewrite" (PHILOSOPHY.md) is the correct instinct. If v1.0 means anything, it means "the next breaking change is v2.0, and v2.0 is a strangler-fig migration, not a rewrite."

### CrewAI: The Fast Mover (v0.28+, late 2025)

**Timeline:** Rapid iteration through v0.x, v0.4 rewrite with breaking changes "still stabilizing," v0.28 (Dec 2025) with improved memory and error handling.

**Stability promise:** None explicit. Fast-moving v0.x with no declared v1.0 timeline.

**What broke:** The v0.4 rewrite introduced breaking changes that were still being stabilized months later. CrewAI has chosen speed over stability guarantees.

**Lesson for Demarch:** CrewAI demonstrates that staying at v0.x indefinitely is a valid strategy when the design space is still being explored. But Demarch is at v0.6.228 -- 228 patch versions deep into v0.6. The version number has stopped communicating meaningful information. Either declare what v1.0 means or adopt a date-based versioning scheme that admits the continuous-evolution nature of the platform.

### Claude Agent SDK: Early Days (v0.1.x, Sep 2025 - Jan 2026)

**Timeline:** v0.1.0 (Sep 2025) through v0.1.18 (Jan 2026). Regular releases every few days. Memory and performance improvements.

**Stability promise:** Implicitly v0.x -- no stability guarantees. Active development.

**Lesson for Demarch:** Even Anthropic's own agent SDK is pre-v1.0. The entire field is pre-v1.0. This means Demarch's v1.0 declaration would be a statement of *infrastructure* maturity, not model maturity -- because no one has solved model-dependent behavioral stability yet.

### LlamaIndex: The Modularization (v0.9 -> v0.10+)

**Timeline:** Monolithic through v0.9.48, then split into `llama-index-core` + hundreds of separate integration packages at v0.10. Legacy package (`llama-index-legacy`) maintained separately.

**What broke:** The modularization split every import path. The migration guide was necessary for all users.

**Lesson for Demarch:** LlamaIndex chose to modularize *before* v1.0 rather than after, which was wise -- it's easier to break imports at v0.10 than v1.0. Demarch's existing modular architecture (6 pillars, 57 plugins, separate package boundaries) means this particular breaking change has already been absorbed. The Interverse plugin ecosystem is already "many small packages."

### Summary: What the Field Has Learned

| Framework | v1.0 Status | Key Lesson |
|-----------|-------------|------------|
| LangChain | v1.0.0 (Nov 2025) | Shrink the stable surface. Deprecate aggressively before v1.0, not after. |
| AutoGen | Merged into Microsoft Agent Framework (Q1 2026 GA) | Never rewrite mid-adoption. Strangler-fig or die. |
| CrewAI | Still v0.x | Staying v0.x is honest if the design space is unsettled. |
| Claude Agent SDK | v0.1.x | The entire field is pre-v1.0 for agent SDKs. |
| LlamaIndex | Still v0.x (modularized at v0.10) | Modularize before v1.0. |
| Semantic Kernel | GA, migrating to Microsoft Agent Framework | Enterprise stability requires explicit support windows. |

---

## 3. The Agent Evaluation Problem at v1.0

### Why Standard Benchmarks Are Insufficient

SWE-bench Verified scores have reached ~75% for frontier models, but this measures single-issue resolution on well-defined open-source bugs. Demarch's value proposition is the full lifecycle: brainstorm -> strategy -> spec -> implement -> review -> ship. No existing benchmark measures this end-to-end pipeline.

Critical gaps between benchmarks and Demarch's production reality:

- **Multi-phase coherence:** SWE-bench tests patch generation. Demarch tests whether the brainstorm phase produces a strategy that produces a spec that produces an implementation that passes review. Phase-to-phase information loss is invisible in single-step benchmarks.
- **Self-building validity:** Demarch builds itself. The evaluation is not "does the agent solve GitHub issues" but "does the system produce durable, maintainable, architecturally coherent changes to its own codebase across hundreds of sprints." The evidence is the commit history.
- **Recovery, not just success:** Pass@1 is the wrong metric. Pass@k (k>=8) reveals production-critical brittleness. A v1.0 system should publish pass@k metrics for representative task classes, not just headline success rates.
- **Domain transfer:** SWE-bench uses 12 popular open-source repos. Demarch claims to work on arbitrary software. The gap between benchmark domains and real-world diversity is where production failures hide.

### What v1.0 Evaluation Should Look Like

1. **Internal dogfooding metrics:** Demarch builds Demarch. Publish: sprint completion rate, post-merge defect rate, revert frequency, gate false-positive/negative rates, cost per landable change (current baseline: $2.93). These are the most honest metrics because they operate on a real, evolving codebase with real stakes.

2. **Stability benchmarks per task class:** Define 3-5 task complexity tiers (from "fix a typo" to "implement a new pillar feature"). For each tier, publish pass@8 reliability on the Demarch codebase itself and at least one external project.

3. **Model migration test:** When a new model version ships, run the evaluation suite on both old and new model. Publish the delta. This tests S3 (behavioral stability across model upgrades) directly.

4. **Adversarial evaluation:** Intentionally introduce known bugs, security issues, or architectural regressions. Measure whether the review pipeline catches them. This tests gate calibration.

---

## 4. The Self-Evolution Problem

Demarch is designed to evolve its own behavior: Interspect proposes routing changes, gate threshold adjustments, and agent configuration overlays. PHILOSOPHY.md explicitly describes this as the flywheel. This creates a versioning paradox: **if v1.0.0 of the platform modifies its own routing table after observing 100 sprints, is it still v1.0.0?**

### The Paradox Resolved: Mechanism vs. State

The answer is to version the *mechanism* (the code that decides how to learn) separately from the *state* (the learned routing table, thresholds, overlays).

- **v1.0.0** = the mechanism is stable. The code that reads events, proposes overlays, evaluates canaries, and applies or reverts changes does not change in breaking ways.
- **Routing state** = an operational artifact, not a versioned release. It changes continuously. It has its own provenance trail (Interspect receipts), its own rollback mechanism (overlay revert), and its own evaluation (canary windows).

This is analogous to how a database engine versions itself (v1.0 of PostgreSQL) independently of the data it contains. The query language is stable; the data evolves.

### What Must Not Self-Modify

PHILOSOPHY.md already identifies the kernel boundary as a trust threshold. For v1.0, the following must be mechanically excluded from self-modification:

1. **Kernel data model** (L1): Runs, phases, gates, events, dispatches. These are the structural foundation. Interspect cannot add columns or change schemas.
2. **Safety infrastructure**: The quality floor mechanisms themselves -- gate enforcement, review requirements, human escalation triggers. Interspect can tune thresholds but cannot remove gates.
3. **Interspect's own evaluation criteria**: The system that evaluates whether an overlay improved things cannot modify its own evaluation function. This is the "alignment faking" boundary -- Anthropic's research showed models exhibiting alignment-faking behavior in 12-78% of cases. The structural constraint is: the judge cannot modify the scoring rubric.
4. **Audit trail**: No self-modification can erase or alter the evidence trail. Receipts are append-only.

### What Can Self-Modify (With Provenance)

- Model routing tables (which model handles which task class)
- Gate thresholds (how strict each quality check is)
- Agent exclusion lists (which review agents run on which project types)
- Context overlays (project-specific prompt adjustments)
- Cost estimates and complexity classifications

Each modification must: (a) be proposed as a diff, (b) go through a canary window, (c) be revertible, and (d) produce a receipt. This is the Interspect overlay model already described in the vision doc.

---

## 5. Minimum Production Readiness Criteria

### Failure Modes That Must Be Absent (Not Just Rare)

These are existential failures -- any occurrence is a v1.0 blocker:

1. **Unbounded cascading failure.** An agent error in one phase must not propagate into cascading failures across the sprint pipeline. The OWASP Agentic AI Top 10 (ASI08, Dec 2025) identifies cascading failures as structurally different from traditional software: "unlike traditional software failures that remain localized, agentic AI cascades propagate across autonomous agents, amplify through feedback loops, and compound into system-wide catastrophes." Demarch's phase gates are the circuit breakers. At v1.0, it must be mechanically impossible for a phase failure to silently advance the sprint.

2. **Silent quality degradation.** If a model upgrade or routing change degrades output quality, the system must detect it within a bounded number of sprints (not sessions, not days -- sprints, because that's the unit of work). Detection means: an alert fires, a canary window activates, or a human is notified. "Nobody noticed for two weeks" is a v1.0 failure.

3. **Unrecoverable state corruption.** The kernel (L1) is the single source of truth. If kernel state becomes inconsistent (orphaned runs, phantom phases, corrupted event streams), the system must either self-heal or halt with a clear error. "bd doctor --deep" is the current implementation; at v1.0, it must run automatically and block sprint starts on corruption.

4. **Self-modification without provenance.** If any agent or subsystem modifies routing, thresholds, prompts, or configuration without producing a durable receipt, the system has lost auditability. This is the structural safety property: every action produces evidence (PHILOSOPHY.md principle 1). At v1.0, this must be enforced mechanically, not by convention.

5. **Infinite agent loops.** An agent that enters an unbounded retry/repair/retry cycle consumes tokens without progress. At v1.0, every agent execution must have a hard token ceiling and a hard wall-clock timeout, enforced by the kernel, not by the agent itself. The agent cannot extend its own deadline.

### The Agentic-Unique Failure Mode: Semantic Cascade

This is the failure mode unique to agentic platforms that must be absent at v1.0:

**Definition:** A semantic cascade occurs when an agent produces output that is *syntactically valid but semantically wrong*, and downstream agents consume that output as trusted input, amplifying the error through multiple phases. Unlike a crash (which halts the pipeline) or a type error (which fails validation), a semantic cascade passes all structural checks while producing increasingly wrong results.

**Example in Demarch:** The brainstorm agent misunderstands the issue and produces a plausible-but-wrong strategy. The plan agent faithfully implements the wrong strategy. The implementation agent writes code that passes tests (because the tests are also generated from the wrong strategy). The review agents find no issues (because the code matches the spec, which matches the plan, which matches the wrong strategy). The sprint completes "successfully" with wrong code.

**Why it's unique to agentic platforms:** In human development, strategy errors are caught by different humans at different stages (the architect catches what the PM missed, the code reviewer catches what the implementer missed). In an agentic system, if the same model or the same prompt lineage handles multiple phases, there's correlated error -- the same blind spot appears everywhere.

**Demarch's mitigation:** Multi-model review (different models have different blind spots), the disagreement-is-signal principle (PHILOSOPHY.md), human oversight at phase gates (trust ladder L1-L2). At v1.0, the mitigation must be *measured*: what percentage of semantic cascades does the review pipeline catch? This requires adversarial testing (intentionally inject wrong strategies and measure detection rate).

### Recovery Behaviors That Must Be Present

1. **Sprint rollback.** Any sprint can be reverted to a previous phase state. Artifacts from the reverted phases are preserved (for evidence) but marked as superseded.

2. **Routing fallback.** If the preferred model is unavailable or degraded, the system must fall back to the next tier without human intervention. The fallback path must be tested, not just declared.

3. **Human escalation.** At any point in any sprint, a human can halt execution, inspect state, override decisions, and resume or abort. The escalation path must work even if the agent is in a failed state.

4. **Evidence recovery.** If event recording fails (disk full, database crash, network partition), the system must buffer events and replay them when the recording infrastructure recovers. Lost evidence is a data integrity failure.

5. **Graceful degradation under load.** When token budgets are exhausted or rate limits hit, the system must queue work rather than fail, degrade to cheaper models rather than stop, and communicate the degradation to humans.

### Observability Requirements

1. **Distributed tracing.** Every sprint must have a trace ID that links: the triggering event, all phase transitions, all agent invocations, all tool calls, all gate evaluations, all human interactions, and the final outcome. OpenTelemetry semantic conventions for AI agents (published 2025) provide the standard.

2. **Cost attribution.** Every token spent must be attributable to a specific sprint, phase, and agent. The current $2.93/landable-change metric is the right shape; at v1.0, it must be computed automatically and available in real-time.

3. **Quality dashboards.** Gate pass rates, finding density, sprint completion rates, revert frequency, and model routing distribution must be visible without querying raw data. Autarch (L3) is the natural home.

4. **Anomaly detection.** Sudden changes in any observable metric (cost spike, completion rate drop, gate pass rate change) must trigger alerts. This is the early-warning system for S3 (model upgrade impact).

### Human Oversight Hooks

1. **Phase gate intervention.** Humans can inspect and override any phase gate decision.
2. **Routing override.** Humans can force a specific model for a specific sprint or task class.
3. **Interspect veto.** Humans can reject any proposed overlay before it enters the canary window.
4. **Emergency halt.** A single command stops all active sprints across all projects.
5. **Audit review.** Any sprint's full evidence trail is reconstructable from receipts.

---

## 6. Multi-Project Scaling: What Must v1.0 Demonstrate?

### The Spectrum

| Level | Description | Evidence Required |
|-------|-------------|-------------------|
| **L0: Single project** | Works on Demarch itself | Self-building metrics (current state) |
| **L1: Same-class projects** | Works on Go/Python CLI tools with tests | At least 2 external projects with published metrics |
| **L2: Cross-domain** | Works on web apps, mobile, infra, data pipelines | 5+ diverse projects with comparable metrics |
| **L3: Arbitrary software** | Works on any codebase a human developer could work on | Unrealistic for v1.0 |

### Recommendation: v1.0 = L1 with L2 evidence

v1.0 should demonstrate:

1. **L0 (self-building):** Demarch has been building itself for 228+ patch versions. The evidence exists. Publish the metrics: sprint completion rate, defect rate, cost per change, revert frequency. This is the strongest evidence because it's been running longest.

2. **L1 (same-class):** At least 2 external projects (Go or Python CLI tools with test suites) must run 50+ sprints each with published metrics comparable to Demarch's self-building metrics. "Comparable" means within 1 standard deviation on completion rate and defect rate.

3. **L2 (cross-domain, directional):** At least 3 additional projects in different domains (web frontend, API backend, infrastructure-as-code) must run 20+ sprints each. Metrics can be worse than L0/L1 but must show the system is functional (>50% sprint completion rate, no existential failures).

4. **L3 is explicitly NOT required for v1.0.** The docs should say: "Demarch v1.0 is tested on Go/Python CLI tools and has directional evidence on web and infrastructure projects. Arbitrary domain support is a v2.0 goal."

### Why This Matters

The research shows that "agent scaffolding matters as much as the underlying model" -- frameworks running identical models scored 17 issues apart on 731 problems. This means Demarch's specific prompts, routing, and phase structure are tuned to the codebases it has been tested on. Claiming generalization without evidence is the #1 way agentic platforms lose trust in production. 40% of multi-agent pilots fail within six months of deployment, and the primary cause is the gap between demo performance and real-world diversity.

---

## 7. Concrete v1.0.0 Production Readiness Checklist

### Structural Stability (S1) -- Hard Requirements

- [ ] Public API surface documented and frozen (ic CLI, plugin manifest schema, hook contracts, event formats)
- [ ] Deprecation policy published (features deprecated in v1.x work until v2.0)
- [ ] Plugin backward compatibility: plugins built for v1.0 kernel load in v1.x
- [ ] Migration guide from v0.6.x to v1.0.0
- [ ] Kernel data model (runs, phases, gates, events, dispatches, state, locks) has schema versioning with forward-compatible evolution

### Behavioral Stability (S2) -- Measured Requirements

- [ ] Pass@8 metrics published for 3+ task complexity tiers on the Demarch codebase
- [ ] Sprint completion rate > 80% on self-building workloads
- [ ] Post-merge defect rate tracked and published (target: declining trend over 90-day window)
- [ ] Gate false-positive rate < 20% (measured by human override frequency)
- [ ] Gate false-negative rate measured by adversarial testing (inject known bugs, measure catch rate)
- [ ] Cost per landable change tracked with automatic attribution

### Model Resilience (S3) -- Architectural Requirements

- [ ] Canary window mechanism operational (new model version gets limited traffic, metrics compared to baseline)
- [ ] Quality floor enforcement: minimum gate thresholds that cannot be relaxed by Interspect
- [ ] Routing fallback tested: preferred model unavailable -> next tier activates within 1 sprint
- [ ] Model upgrade impact report: automated comparison of metrics before/after model change

### Failure Mode Absence -- Existential Requirements

- [ ] No unbounded cascading failures: phase gate circuit breakers enforced mechanically
- [ ] No silent quality degradation: anomaly detection on all core metrics with alerting
- [ ] No unrecoverable state corruption: bd doctor runs automatically, blocks on corruption
- [ ] No unprovenanced self-modification: every routing/threshold/overlay change has a receipt
- [ ] No infinite agent loops: hard token ceiling + wall-clock timeout on every agent execution
- [ ] Semantic cascade detection: adversarial test suite with published catch rate

### Recovery Behaviors -- Operational Requirements

- [ ] Sprint rollback functional and tested
- [ ] Routing fallback functional and tested
- [ ] Human escalation path works from any state
- [ ] Evidence recovery after recording failure
- [ ] Graceful degradation under token/rate-limit exhaustion

### Observability -- Infrastructure Requirements

- [ ] Distributed tracing with sprint-level trace IDs
- [ ] Cost attribution per sprint/phase/agent
- [ ] Quality dashboard (gate rates, completion rates, costs)
- [ ] Anomaly detection with alerting

### Multi-Project Evidence -- Scope Requirements

- [ ] Self-building metrics published (L0)
- [ ] 2+ external same-class projects with 50+ sprints each (L1)
- [ ] 3+ cross-domain projects with 20+ sprints each (L2, directional)
- [ ] Explicit documentation of what domains are NOT tested

---

## 8. Recommendation: The Path from v0.6.228 to v1.0.0

### Phase 1: API Surface Freeze (v0.7.0)

Bump to v0.7.0 when the structural API (S1) is documented and frozen. This signals: "the API is stable, we're working on behavioral evidence." This is the LangChain lesson -- shrink and freeze the surface before v1.0, not at v1.0.

Key actions:
- Document every `ic` command's input/output contract
- Document plugin manifest schema with JSON Schema
- Document event stream format
- Identify and deprecate any API surface that should not be in v1.0
- Publish deprecation timeline

### Phase 2: Evaluation Infrastructure (v0.8.0)

Bump to v0.8.0 when the evaluation infrastructure is operational: pass@k benchmarks, adversarial test suite, canary window mechanism, anomaly detection. This signals: "we can measure production readiness."

Key actions:
- Build pass@k evaluation harness for Demarch self-building tasks
- Build adversarial test suite (inject known bugs, wrong strategies)
- Operationalize canary windows for model upgrades
- Set up anomaly detection on core metrics

### Phase 3: Multi-Project Evidence (v0.9.0)

Bump to v0.9.0 when external project evidence is collected. This signals: "we have evidence beyond self-building."

Key actions:
- Run 50+ sprints each on 2 external Go/Python projects
- Run 20+ sprints each on 3 cross-domain projects
- Publish comparative metrics

### Phase 4: v1.0.0

Declare v1.0.0 when all checklist items are met. Publish a "state of production readiness" document alongside the release that includes:
- All metrics from the checklist
- Known limitations and untested domains
- The stability contract (what changes in v1.x, what waits for v2.0)
- The self-evolution disclosure (what the system modifies about itself, what it cannot)

### What v1.0.0 Does NOT Mean

- It does not mean the system works on arbitrary software domains.
- It does not mean behavioral outputs are deterministic.
- It does not mean model upgrades have no impact.
- It does not mean human oversight is optional.

It means: **the infrastructure is stable, the behavioral properties are measured and published, failure modes are bounded, and the system produces evidence of its own reliability.**

---

## Sources

### Framework Versioning History
- [LangChain v1 GA Announcement](https://changelog.langchain.com/announcements/langchain-1-0-now-generally-available)
- [LangChain Release Policy](https://docs.langchain.com/oss/python/release-policy)
- [LangChain and LangGraph 1.0 Milestones](https://blog.langchain.com/langchain-langgraph-1dot0/)
- [LangChain Evolution Guide](https://medium.com/@pramod21/the-complete-guide-to-langchains-evolution-why-everything-changed-and-how-to-build-with-1-0-2b582874a893)
- [CrewAI Changelog](https://docs.crewai.com/en/changelog)
- [AutoGen vs CrewAI Comparison](https://is4.ai/blog/our-blog-1/autogen-vs-crewai-comparison-2026-332)
- [Microsoft Agent Framework (Semantic Kernel + AutoGen)](https://visualstudiomagazine.com/articles/2025/10/01/semantic-kernel-autogen--open-source-microsoft-agent-framework.aspx)
- [Semantic Kernel Migration Guide](https://learn.microsoft.com/en-us/agent-framework/migration-guide/from-semantic-kernel/)
- [Claude Agent SDK Releases](https://github.com/anthropics/claude-agent-sdk-python/releases)
- [LlamaIndex v0.10 Migration Guide](https://www.llamaindex.ai/blog/llamaindex-v0-10-838e735948f8)

### Agent Evaluation and Benchmarks
- [8 Benchmarks Shaping Next-Gen AI Agents](https://ainativedev.io/news/8-benchmarks-shaping-the-next-generation-of-ai-agents)
- [SWE-EVO: Long-Horizon Software Evolution Benchmarks](https://arxiv.org/html/2512.18470v1)
- [Beyond Accuracy: Multi-Dimensional Enterprise Agent Evaluation](https://arxiv.org/html/2511.14136v1)
- [Evaluating AI Agents in 2025](https://labs.adaline.ai/p/evaluating-ai-agents-in-2025)
- [METR Research Update: Algorithmic vs. Holistic Evaluation](https://metr.org/blog/2025-08-12-research-update-towards-reconciling-slowdown-with-time-horizons/)

### Production Failure Modes and Safety
- [OWASP Top 10 for Agentic Applications 2026](https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/)
- [Cascading Failures in Agentic AI (OWASP ASI08)](https://adversa.ai/blog/cascading-failures-in-agentic-ai-complete-owasp-asi08-security-guide-2026/)
- [Characterizing Faults in Agentic AI: Taxonomy](https://arxiv.org/html/2603.06847v1)
- [Multi-Agent Reality Check: 7 Failure Modes](https://www.techaheadcorp.com/blog/ways-multi-agent-ai-fails-in-production/)
- [5 Production Scaling Challenges for Agentic AI 2026](https://machinelearningmastery.com/5-production-scaling-challenges-for-agentic-ai-in-2026/)
- [Why AI Agent Pilots Fail in Production](https://composio.dev/blog/why-ai-agent-pilots-fail-2026-integration-roadmap)

### Self-Evolution and Safety
- [OpenAI Cookbook: Self-Evolving Agents](https://developers.openai.com/cookbook/examples/partners/self_evolving_agents/autonomous_agent_retraining)
- [Self-Evolving AI Agents (Emergent Mind)](https://www.emergentmind.com/topics/self-evolving-ai-agent)
- [Security Pitfalls for AI Coding Agents in 2026](https://www.darkreading.com/application-security/coders-adopt-ai-agents-security-pitfalls-lurk-2026)

### Observability and Monitoring
- [OpenTelemetry: AI Agent Observability Standards](https://opentelemetry.io/blog/2025/ai-agent-observability/)
- [AI Agent Observability Platforms 2026](https://www.getmaxim.ai/articles/top-5-ai-agent-observability-platforms-in-2026/)
- [Google Cloud: Dev's Guide to Production-Ready AI Agents](https://cloud.google.com/blog/products/ai-machine-learning/a-devs-guide-to-production-ready-ai-agents)

### Multi-Project and Domain Generalization
- [We Tested 15 AI Coding Agents (2026)](https://www.morphllm.com/ai-coding-agent)
- [Anthropic 2026 Agentic Coding Trends Report](https://resources.anthropic.com/hubfs/2026%20Agentic%20Coding%20Trends%20Report.pdf)
- [State of AI Coding Agents 2026](https://medium.com/@dave-patten/the-state-of-ai-coding-agents-2026-from-pair-programming-to-autonomous-ai-teams-b11f2b39232a)
