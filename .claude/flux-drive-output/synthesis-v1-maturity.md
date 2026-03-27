# Synthesis: Sylveste v1.0.0 Readiness Across Six Research Frameworks

**Date:** 2026-03-21
**Scope:** Integration of findings from versioning philosophy, maturity models, OSS readiness signals, cybernetic viability, agent ecosystem readiness, and game design release criteria.
**Current State:** Sylveste v0.6.228
**Target:** Define the concrete, measurable v1.0.0 threshold and the v0.7→0.8→0.9→v1.0.0 milestone path

---

## 1. Cross-Agent Convergences: Where Independent Frameworks Agree

### Convergence 1: Stability of Mechanism, Not Feature Completeness

**Who agrees:** Versioning Philosophy, OSS Readiness Signals, Game Design, Agent Ecosystem
**The convergence:**

All four frameworks explicitly reject "feature completeness" as a v1.0 criterion.

- **Versioning Philosophy:** Rust had no async/await at 1.0. Go's stdlib was incomplete. 1.0 declares the *stability mechanism* operational.
- **OSS Readiness:** Kubernetes shipped 1.0 with many alpha/beta APIs. Terraform added zero new features in 1.0 vs. 0.15.5. The declaration is about "we can evolve without breaking you," not "everything is done."
- **Game Design:** Alpha→Beta is content completeness. Beta→Gold is *polish and reliability*, not new features. Game developers explicitly say: "Features ship after launch."
- **Agent Ecosystem:** LangChain's v1.0 had *fewer* abstractions than v0.3, not more. The surface shrank, and with it, the stability commitment became credible.

**What this means for Sylveste:** v1.0.0 should NOT wait for:
- All 57 Interverse plugins to be "production-ready" (impossible)
- All 49 commands to be fully documented
- All 6 agents to be at maximum capability

**What it SHOULD wait for:**
- The plugin/command/agent API to be frozen (you can add more post-v1.0, but existing ones must work in v1.x)
- The mechanism for adding them without breaking existing ones to be proven (release process, deprecation policy, backward compatibility testing)

**Sylveste's current status:** The L1 kernel (Intercore) already exhibits this maturity. The L2/L3 layers are deliberately marked as evolving. The asymmetry is correct.

---

### Convergence 2: Closed-Loop Autonomy as the Maturity Threshold

**Who agrees:** Maturity Models (VSM, autopoiesis, dissipative structures, free energy), Game Design (emergent gameplay), Agent Ecosystem (S3 behavioral stability)
**The convergence:**

The single most precise threshold is: **the system's past behavior automatically shapes its future behavior across multiple independent dimensions.**

- **VSM:** All five systems must be operational, particularly S4 (environmental sensing) and S5 (policy). System improves itself without external calibration.
- **Autopoiesis:** The system produces its own operational logic (routing tables, gate thresholds, agent compositions) from outcomes.
- **Dissipative structures:** The system crosses a bifurcation — it degrades to qualitatively different (worse) behavior if calibration state is deleted.
- **Free energy:** Prediction error (surprise) autonomously triggers model updates AND active interventions without human cranking.
- **Game design:** Emergent gameplay is legible (you can explain why outcomes occurred) and non-degenerate (the strategy space remains diverse and does not collapse to a single dominant approach).
- **Agent ecosystem:** S3 behavioral stability means the system detects model drift, falls back gracefully, and adapts routing without manual intervention.

**What this means for Sylveste:** The v1.0 threshold is **not** the closing of a single feedback loop. It is the closing of *at least three independent loops simultaneously*:

1. **Routing loop:** Evidence → routing override proposal → canary evaluation → application or revert (current: plumbing exists, pump is manual)
2. **Gate threshold loop:** Gate pass/fail rates → threshold adjustment → re-evaluation (current: architecture exists, defaults are hardcoded)
3. **Phase-cost loop:** Estimated vs. actual cost → cost classifier refinement → future predictions (current: calibrate-phase-costs exists but requires manual invocation)

**Sylveste's current status:**

From fd-autopoiesis-viability.md, the three domains are **not yet simultaneously closed**:
- Interspect routing override generation: exists architecturally, zero production callers
- Gate threshold calibration: mostly hardcoded defaults
- Phase cost calibration: manual trigger, not autonomous

The system is proto-autopoietic, not fully autopoietic.

---

### Convergence 3: Existential Failure Modes Must Be Absent, Not Just Rare

**Who agrees:** Agent Ecosystem, Maturity Models (reliability engineering), Game Design (balance)
**The convergence:**

A v1.0 product must have *structurally prevented* failure modes, not just low probability ones.

From agent-ecosystem-readiness.md, five existential failure modes must be mechanically prevented (not mitigated, prevented):

1. **Unbounded cascading failures** — OWASP ASI08 identifies these as distinct from traditional software failures because they amplify through feedback loops. Phase gates are circuit breakers; they must halt propagation mechanically.
2. **Silent quality degradation** — the system must detect within N sprints if model upgrade degrades output, not "eventually someone notices."
3. **Unrecoverable state corruption** — `bd doctor --deep` must run automatically and block sprint starts.
4. **Unprovenanced self-modification** — every routing/threshold/overlay change must produce a durable receipt. No configuration drift.
5. **Infinite agent loops** — every agent execution must have kernel-enforced token ceilings and wall-clock timeouts. The agent cannot extend its own deadline.

Additionally, the **semantic cascade** failure mode (syntactically valid but semantically wrong output amplified through phases) must be *measured*, not assumed absent. Adversarial testing (intentionally inject wrong strategies and measure detection rate) becomes a hard v1.0 requirement.

**Game design analog:** Degenerate strategies (approaches that exploit the system to guarantee success while collapsing the outcome space) must be absent. Examples:
- Gate-farming: minimal changes pass gates fastest, value per token collapses
- Review-stuffing: high finding volume looks productive, code quality doesn't improve
- Model-hoarding: expensive models have lower defect rates (true by definition), routing collapses to one tier

Detection mechanism: if strategy diversity drops, something is degenerate. Fix is not more rules (more gates), it is rebalancing incentives (rotate metrics, cap optimization rate, randomize audits).

**Sylveste's current status:**
- Unbounded cascading: gates exist but are not mechanically enforced to halt propagation
- Silent degradation: Interspect canary windows designed but not yet operational
- State corruption: bd doctor exists but requires manual invocation
- Unprovenanced self-modification: routing overrides are logged, but modifications can occur outside Interspect
- Infinite loops: no hard kernel-enforced timeouts on agent execution

---

### Convergence 4: External Validation Is Required, Redefined for Agentic Platforms

**Who agrees:** OSS Readiness (Signal 3: Production Deployment Evidence), Maturity Models (TRL 8: external environment qualification), Game Design (Day-1 retention)
**The convergence:**

"Production deployment evidence" means different things for deterministic vs. stochastic systems.

For Go, Rust, Kubernetes, Terraform (all deterministic): "somebody outside the maintainers runs this in production and gets the correct results."

For Sylveste (stochastic): "somebody outside the maintainers runs this on their own code and the *orchestration infrastructure* behaves predictably even though the outputs are inherently variable."

**What this means for Sylveste:**

Production evidence should demonstrate:
- Sprints complete end-to-end
- Phase gates fire at the right moments
- Evidence persists correctly
- Routing decisions are traceable
- Calibration data accumulates and influences future decisions

NOT:
- Every sprint produces perfect code
- Output is deterministic
- Cost is identical to Sylveste's self-building

The agent ecosystem research identifies the critical gap: "40% of multi-agent AI pilot projects fail within 6 months of deployment, and the primary cause is the gap between demo performance (on the developer's codebase) and real-world diversity." Sylveste must demonstrate: L1 (same-class projects, 50+ sprints each, 2+ external), L2 (cross-domain projects, 20+ sprints each, 3+).

**Sylveste's current status:** L0 (self-building, 785+ sessions) exists and is measured. L1 and L2 evidence is absent.

---

### Convergence 5: Operational Design Domain (ODD) Must Be Declared

**Who agrees:** Versioning Philosophy (SAE autonomy levels), Game Design (target playtime and player profile), Agent Ecosystem (multi-project scaling)
**The convergence:**

The platform cannot claim universality. Instead, it must declare what it is designed for and explicitly scope what is out of bounds.

SAE autonomous vehicle levels define this precisely: L0-L5 describe what the system is trusted to do and what fallback exists. Expanding the ODD is a separate axis from version bumps.

For Sylveste, the v1.0 ODD should declare:

**In scope:**
- Single-repository software development
- Supported languages (Go, Python, TypeScript, Rust, etc.)
- Supported project types (CLI tools, libraries, web services)
- Human review at phase gates (trust ladder L1-L2)
- Codebase size: 100 LOC to 1M LOC
- Team size: solo developer to small teams

**Out of scope (v1.0):**
- Multi-repo coordination (v2.0 goal)
- Novel domains without precedent (domain transfer is a v2.0 capability)
- Autonomy L3+ (auto-remediation shipping in v0.8/v0.9)
- Guaranteed outcome quality (quality is model-dependent and model-independent)

**Sylveste's current status:** ODD is implicit in PHILOSOPHY.md but not explicitly published as a v1.0 release boundary.

---

## 2. Unique Findings: Non-Obvious Insights From Individual Frameworks

### Finding 1: "Player Expression" as a v1.0 Criterion (Game Design)

**Source:** fd-game-design-readiness.md, Section 8

Player expression is the degree to which a player's choices produce outcomes that feel personal and distinctive, distinct from freedom (available choices) or agency (causal power).

**Applied to Sylveste:** Operator expression — the degree to which a human operator's choices (problem selection, risk tolerance, model preference, review depth) produce measurably different outcomes.

**Why it matters:** If an operator who prioritizes speed cannot get measurably faster results, and an operator who prioritizes quality cannot get measurably fewer defects, then the configuration surface is decorative. The system has launched without the very feature that distinguishes it from single-model tools.

**Test:** Run two operators with opposite stated risk profiles on identical problem classes. Do they get measurably different outcome profiles (speed vs. quality tradeoff)? If not, configuration is cargo cult.

**This is critical for v1.0 credibility:** Users who adopt Sylveste instead of Cursor/Aider are betting that control matters. If control is illusory, they abandon the platform immediately.

**Sylveste's current status:** The knobs exist (routing overrides, gate thresholds, agent selection). Whether they *actually produce different outcomes* is untested.

---

### Finding 2: The "Meta-Stability" Signal From Game Design

**Source:** fd-game-design-readiness.md, Section 2

In competitive games, a "healthy meta" means multiple viable strategies exist, no single approach dominates (concentration <70%), and players form a rock-paper-scissors structure where each strategy beats some and loses to others. "It depends" is the correct answer to "what's optimal?"

**Applied to Sylveste:** The platform's routing, agent composition, and phase structure must not collapse to a single dominant approach across problem classes. If cheap models outperform expensive ones universally, or if all sprints use the same agent pipeline, the system has a degenerate meta.

**Why this matters:** A degenerate meta collapses the value proposition. If fast/cheap always wins, Sylveste becomes "use the cheapest model." If thorough/expensive always wins, Sylveste becomes "use the most expensive model." The platform's edge is *problem-contingent decision-making*, and that edge vanishes if the decision space collapses.

**Test:** Analyze 100 completed sprints. Measure:
- Routing tier distribution (no tier >70%)
- Problem-class coverage (≥5 classes at >80% success rate)
- Model-outcome correlation (expensive models on hard problems → fewer defects, statistically significant)
- Bead granularity diversity (no single size bucket >40%)

**Sylveste's current status:** The routing infrastructure supports meta stability. Whether it actually produces it is untested at scale.

---

### Finding 3: The "Ambient Authority" Problem From Cybernetics

**Source:** fd-autopoiesis-viability.md, Section 1 (VSM mapping)

Beer's Viable System Model shows that S3 (Control) and S3* (Audit) must balance. S3 allocates resources; S3* verifies that allocation is justified. If S3* is weak, then S3's decisions are unchecked.

In Sylveste, S3 is strong (Intercore kernel manages runs, gates, budgets). S3* is moderate (Interspect canary monitoring exists but is not yet fully operational). The imbalance means **the system can allocate tokens and gates based on routing decisions that have never been audited against outcomes**.

**Why this matters:** This is the alignment-faking boundary. If the system proposes its own improvements and evaluates its own improvements, with no independent verification, it can optimize for the appearance of improvement (the proxy metric) rather than actual improvement.

**Critical constraint for v1.0:** Interspect cannot modify the evaluation criteria it uses to assess its own overlays. The "judge cannot modify the scoring rubric." This is a structural safety property.

**Sylveste's current status:** The structural constraint is articulated in agent-ecosystem-readiness.md Section 4.4. Whether it is mechanically enforced is unclear.

---

### Finding 4: The "Deletion-Recovery Test" From Cybernetics

**Source:** fd-autopoiesis-viability.md, Section 7 (Unified test)

**The test:** Delete all calibration/evidence state (interspect.db, routing overrides, mutation store). Run 10 sprints on the same problem distribution. Measure performance degradation. Continue running without manual intervention on calibration. Measure sprints-to-recovery (when metrics return to baseline).

**v1.0 pass criteria:**
- Amnesiac sprints are >15% worse on at least two of: cost, duration, defect rate
- Recovery occurs within 50 sprints
- No human touches calibration/routing/gate configuration during recovery

**Why this test is powerful:** It validates simultaneously that:
1. VSM completeness: the evidence/calibration data is operationally load-bearing
2. Autopoietic closure: the system reproduces its own operational parameters from outcomes
3. Dissipative bifurcation: the organized state is self-reinforcing
4. Stigmergic phase transition: outcomes propagate as signals that coordinate future behavior
5. Free energy minimization: the system autonomously reduces surprise
6. Requisite variety: the calibration data adds variety that default configuration lacks

**Sylveste's current status:** This test has never been run. It is the single most diagnostic test for whether the platform has crossed the autonomy threshold.

---

### Finding 5: The "One-Hour Viability" Criterion From Game Design

**Source:** fd-game-design-readiness.md, Section 5

From Dwarf Fortress case study: the game existed for 16 years with deep, functional systems that only enthusiasts could access. The 2022 Steam release added UI, mouse support, tutorial, and accessibility. Systems unchanged. Result: 300K sales in one week, $7.2M in January 2023.

**Applied to Sylveste:** The value of Sylveste's infrastructure (multi-model routing, calibration loops, evidence pipelines, review synthesis) is lost if a new developer cannot access it in one hour. If onboarding requires knowing PHILOSOPHY.md, reading .clavain/config.yaml, learning the beads schema, and manually configuring 20 knobs, then that depth is inventory, not capability.

**v1.0 requirement:** Time to first shipped change <60 minutes. 70%+ of new users unfamiliar with internals complete first sprint without asking for help. All onboarding stage events instrumented.

**This is the highest-leverage gap.** Sylveste's infrastructure is deeper than Cursor/Aider, but the infrastructure is worthless if users cannot reach it. The game design tradition calls this "accessibility is a feature, not an afterthought."

**Sylveste's current status:** Onboarding is a known pain point. The documentation assumes operator knowledge of internals. The instrumentation is absent (no events for "user completed first sprint successfully").

---

### Finding 6: "Boring Is Stable" (OSS Readiness, Go 1.0)

**Source:** fd-oss-readiness-signals.md, Section 2 (Go 1.0)

Go's announcement: "boring is stable. Boring means being able to focus on your work, not on what's different about Go."

**Applied to Sylveste:** Users should not be surprised by the platform itself. Surprise should come from *what the agents discover about the problem*, not from *the platform behaving unexpectedly*. If a user cannot form a correct mental model of what the system will do, they cannot rely on it.

This is why "retroactive legibility" (from game design) is critical: after a sprint completes, an independent reviewer can explain why each decision was made from receipts alone.

**Sylveste's current status:** The system is not yet boring. Too much magic happens inside the agents and routers that is not visible in the receipts. Users cannot form confident mental models.

---

## 3. Contradictions Between Frameworks

### Apparent Contradiction 1: Behavioral Stability vs. Model Independence

**The tension:**

- **Maturity Models & OSS Readiness** say: v1.0 should promise behavioral stability — pass@k metrics, completion rates, defect rates all bounded and published.
- **Agent Ecosystem & Cybernetics** say: the system's behavior is inherently model-dependent and model-independent is neither possible nor desirable. Model upgrades will change behavior.

**Resolution:**

This is not actually a contradiction. The distinction is between **mechanism** and **outcome**.

- **Mechanism stability (v1.0 promise):** How the system responds to model changes is stable. Canary windows work. Fallback routing works. Quality floors are enforced. Degradation is detected within N sprints. The *process of adaptation* is predictable.
- **Outcome stability (NOT a v1.0 promise):** The specific outputs do not change when models change. This is impossible for LLM systems.

**Sylveste's correct position:** v1.0 should promise S3 behavioral stability (graceful degradation and adaptation), not S2 behavioral stability (deterministic outputs). The three-layer model from agent-ecosystem-readiness.md is exactly right:
- S1: Structural API stability (CLI, schemas, plugin interface) — SemVer promise
- S2: Behavioral stability under fixed model version — evaluated but not promised
- S3: Behavioral stability across model upgrades — architectural requirement for v1.0

---

### Apparent Contradiction 2: Autonomy vs. Human Oversight

**The tension:**

- **Cybernetics (VSM)** says: v1.0 means all five systems operational, including S4 (environmental sensing) and S5 (policy). The system should operate autonomously with minimal human cranking.
- **Game Design & Agent Ecosystem** say: v1.0 means humans can intervene at any phase, override routing, escalate sprints, and reject overlays. Human oversight is a permanent feature, not a v2.0 goal.

**Resolution:**

Again, not a contradiction. The distinction is between **what the system does by default** vs. **what the human can override**.

- **Autonomy dimension:** The system should make good decisions autonomously. Autonomy L0-L3 should be achieved by v1.0.
- **Human oversight dimension:** Humans should be able to countermand any autonomous decision. This never goes away.

These are orthogonal. A v1.0 platform can have high autonomy (things happen without human intervention) and high oversight (humans can inspect and override anything). The two are not zero-sum.

**Sylveste's correct position:** v1.0 should deliver Autonomy L1-L3 (Record, Enforce, React) with full human override capability at every level. L4-L5 (auto-ship, cross-repo learning) are v2.0+ goals.

---

## 4. The Single Most Important Finding

**Stated across all six frameworks:** The system must have **closed-loop calibration operating across at least three independent dimensions simultaneously**.

This is not a feature gap. Sylveste already has routing calibration, gate threshold calibration, and phase-cost calibration *designed*. What is missing is *wiring them into autonomous operation*.

**Current state of the three loops:**

1. **Routing loop** (interspect → override proposal → canary → apply/revert): Plumbing exists. "Zero production callers" for B2 complexity-aware routing. Override *generation* requires manual initiation.

2. **Gate threshold loop** (pass/fail rate → threshold adjustment): Architecture exists. Thresholds are mostly hardcoded defaults. `calibrate-phase-costs` requires manual invocation.

3. **Phase-cost loop** (estimated vs. actual → classifier update): The calibration-phase-costs tool exists. Manual trigger. Not integrated into sprint execution.

**Why this matters:**

Until these three loops are simultaneously closed, the system is a sophisticated build tool, not an autonomous agency. PHILOSOPHY.md explicitly describes the flywheel. If the flywheel does not turn autonomously, the 1.0 declaration is dishonest.

**The fix is not complicated.** It requires:
- Making interspect override *generation* autonomous (not just human-initiated)
- Making gate threshold calibration autonomous (run on a schedule, evaluate historical data, propose adjustments)
- Integrating phase-cost calibration into the normal sprint flow (collect actuals, feed back into estimates)

This is plumbing work, not architecture work. It is wiring systems that already exist.

---

## 5. The v0.7 → v0.8 → v0.9 → v1.0 Milestone Path

### v0.7.0: Closed-Loop Autonomy Achieved

**Threshold:** All three calibration loops operate autonomously without human intervention.

**Concrete deliverables:**
1. Interspect routing override generation runs automatically on a schedule (hourly/daily)
2. Gate threshold calibration runs automatically from historical data
3. Phase-cost calibration integrates into sprint execution flow
4. `bd doctor --deep` runs automatically, blocks on corruption

**Exit criteria:**
- 10 consecutive sprints run without any manual calibration intervention
- Deletion-recovery test: amnesiac sprints >15% worse, recovery within 50 sprints
- All 6 PHILOSOPHY.md calibration domains at stage 3-4

**Work estimate:** Moderate. Mostly wiring, not new capability.

---

### v0.8.0: Evaluation Infrastructure + L3 Auto-Remediation

**Threshold:** The system can measure its own reliability and can recover from common failures without human intervention.

**Concrete deliverables:**
1. Pass@k evaluation harness for Sylveste self-building tasks (at least 3 complexity tiers)
2. Adversarial test suite (inject known bugs, wrong strategies, measure detection rate)
3. Canary window mechanism operational for model upgrades
4. Anomaly detection on core metrics (cost spike, completion rate drop) with alerting
5. Autonomy L3 (auto-remediation): system retries failed gates, substitutes agents, adjusts parameters without human intervention
6. All existential failure modes mechanically prevented (unbounded cascades, silent degradation, state corruption, unprovenanced modification, infinite loops)

**Exit criteria:**
- Pass@k metrics published for Sylveste codebase (3+ tiers)
- Semantic cascade detection rate >70% (measured by adversarial suite)
- Model upgrade protocol operational with <1 sprint detection latency
- 100 consecutive sprints without existential failures

**Work estimate:** Significant. Evaluation and auto-remediation require careful design.

---

### v0.9.0: External Validation + ODD Declaration

**Threshold:** The system has been proven to work on codebases outside the developer's control.

**Concrete deliverables:**
1. 2+ external Go/Python projects, 50+ sprints each, metrics comparable (within 1 std dev) to self-building
2. 3+ cross-domain projects (web, infrastructure, data), 20+ sprints each, directional evidence
3. Multi-project scaling infrastructure: fleet registry, federation, cross-repo coordination
4. Operational Design Domain published: in-scope domains, out-of-scope domains, autonomy tier promises
5. All three readiness gates from game-design-readiness.md passing (outcome envelope, strategy space health, onboarding)

**Exit criteria:**
- External metrics published alongside internal metrics
- ODD published in public documentation
- Onboarding instrumentation complete (5 stage events)
- Zero external project catastrophic failures (existential failure modes still absent)

**Work estimate:** Heavy. Requires running the platform on unknown codebases, collecting evidence, iterating on accessibility.

---

### v1.0.0: Stability Commitment + Production Readiness Declaration

**Threshold:** All criteria from all six frameworks met simultaneously.

**Concrete deliverables:**
1. API stability contract published (what is frozen, what evolves, deprecation policy)
2. Behavioral envelope published (pass@k metrics, completion rates, defect detection rates)
3. Operational Design Domain published (what is promised, what is explicitly excluded)
4. Deletion-recovery test passed (calibration state is load-bearing AND self-reproducing)
5. External validation evidence published (L0, L1, L2 metrics)
6. All failure modes mechanically prevented, existential failures at zero incidence
7. v1.x release plan published (maintenance duration, backward compatibility guarantees)

**Exit criteria:**
- All items from v0.7, v0.8, v0.9 persisted and active
- No new features shipped in v1.0 compared to v0.9.x (follow Terraform's pattern: 1.0 is a stability declaration, not a feature release)
- Backward compatibility tested: plugins built for v1.0 load in hypothetical v1.5
- "State of production readiness" document published alongside v1.0.0 release

**Work estimate:** Low implementation work, high documentation and validation work.

---

## 6. The v1.0.0 Contract: What Is Promised, What Is Excluded

### What MUST Be Stable (SemVer Protected Until v2.0.0)

**Layer 1: Structural API Stability**
- `ic` CLI commands (input args, output shapes)
- Plugin manifest schema (plugin.json)
- Hook lifecycle and contract
- Event stream format
- Kernel data model (runs, phases, gates, dispatches, state, locks)
- Bead schema and state transitions
- Configuration contract (CLAUDE.md, AGENTS.md, .clavain/ keys)

**Migration:** Existing plugins built for v1.0 must load in v1.x without code changes.

**Enforcement:** Automated schema validation, contract tests, plugin compatibility matrix.

---

### What MAY Change (With Notice, Not SemVer)

**Layer 2: Behavioral Policies**
- Model routing decisions (which model for which task may change based on new evidence)
- Gate thresholds (calibration adjusts based on outcome history)
- Review agent behavior (what is looked for, scoring may improve)
- Default prompts and system messages
- Cost and token consumption (efficiency improvements occur)

**Mechanism:** Behavioral changelog with [behavior] tag. GODEBUG-style pinning: projects can declare `sylveste-compat: 1.2` to freeze behavioral defaults to a specific version's values.

**Enforcement:** Interspect overlay logs, canary windows before defaults change, ability to pin compatibility version.

---

### What Is Explicitly Out of Scope

**Cannot promise:**
- Deterministic outputs (stochastic by design)
- Specific model availability (models are external dependency)
- Output quality floor (depends on model capabilities, not platform)
- Timing or latency (model provider infrastructure-dependent)
- Cost stability (model pricing changes externally)
- Domain generalization beyond ODD (arbitrary software development is v2.0+ goal)

---

### How Breaking Changes Are Communicated

**Structural breaking changes (API shape, schema, CLI):**
- Minimum 2 minor releases of deprecation warnings before removal
- Migration guide published with deprecation
- `bd doctor` and `/clavain:doctor` check for usage of deprecated features

**Behavioral breaking changes (policies, defaults, routing):**
- [behavior] tag in release notes
- GODEBUG-style pinning available for production deployments
- Behavioral changes must be justified by evidence (outcome data, not opinion)

**Model-driven changes (new models, model deprecations):**
- Model routing changelog published separately from platform releases
- Model version pinning available for production deployments
- Canary period before new model becomes default

---

## 7. Definition of Done: The v1.0.0 Readiness Checklist

### Structural Stability (Hard Requirements)

- [ ] Public API surface fully documented (ic CLI, plugin.json schema, hook contracts, event formats)
- [ ] Deprecation policy published with timeline
- [ ] Plugin backward compatibility: v1.0 plugins load in v1.x without changes
- [ ] Migration guide from v0.6.x → v1.0.0
- [ ] Kernel data model versioning strategy defined with forward-compatible evolution mechanism

### Closed-Loop Autonomy (Hard Requirements)

- [ ] Interspect routing override generation autonomous (not human-initiated)
- [ ] Gate threshold calibration autonomous from historical data
- [ ] Phase-cost calibration integrated into sprint flow
- [ ] All 6 PHILOSOPHY.md calibration domains at stage 3-4
- [ ] Deletion-recovery test passes: amnesiac >15% worse, recovery <50 sprints, no manual intervention

### Behavioral Stability (Hard Requirements)

- [ ] Pass@k metrics published for ≥3 task complexity tiers on Sylveste codebase
- [ ] Sprint completion rate >80% on self-building workloads
- [ ] Post-merge defect rate tracked with declining trend over 90-day window
- [ ] Gate false-positive rate <20% (measured by human override frequency)
- [ ] Gate false-negative rate measured by adversarial testing (inject known bugs, measure catch rate)
- [ ] Cost per landable change tracked with automatic attribution
- [ ] Model upgrade impact report: automated comparison before/after

### Failure Mode Absence (Hard Requirements)

- [ ] No unbounded cascading failures: phase gate circuit breakers enforced mechanically
- [ ] No silent quality degradation: anomaly detection on all core metrics with alerting
- [ ] No unrecoverable state corruption: `bd doctor --deep` runs automatically, blocks on corruption
- [ ] No unprovenanced self-modification: every routing/threshold/overlay change has receipt
- [ ] No infinite agent loops: hard token ceiling + wall-clock timeout on every agent execution
- [ ] Semantic cascade detection rate >70% (adversarial test suite)

### Recovery & Resilience (Hard Requirements)

- [ ] Sprint rollback functional and tested
- [ ] Routing fallback functional and tested (preferred model unavailable → next tier)
- [ ] Human escalation path works from any state
- [ ] Evidence recovery after recording failure
- [ ] Graceful degradation under token/rate-limit exhaustion

### Observability (Hard Requirements)

- [ ] Distributed tracing with sprint-level trace IDs
- [ ] Cost attribution per sprint/phase/agent
- [ ] Quality dashboard (gate rates, completion rates, costs)
- [ ] Anomaly detection with alerting
- [ ] All 5 onboarding stage events instrumented

### Multi-Project Validation (Hard Requirements)

- [ ] Self-building metrics published (L0, 785+ sessions documented)
- [ ] 2+ external same-class projects with 50+ sprints each, metrics comparable (L1)
- [ ] 3+ cross-domain projects with 20+ sprints each, directional evidence (L2)
- [ ] Explicit documentation of what domains are NOT tested

### Game Design Release Criteria (Hard Requirements)

- [ ] 90% of completed sprints have retroactive legibility (independent reviewer can explain decisions from receipts)
- [ ] Bounded surprise: post-merge defect rate within 2x of baseline after any platform update
- [ ] Meta stability: no single routing tier >70%, problem class coverage ≥5 classes at >80% success
- [ ] Strategy-outcome correlation statistically significant (model tier selection correlates with quality)
- [ ] Operator expression measurable: different risk profiles get different outcome profiles
- [ ] Onboarding: time to first shipped change <60 minutes, 70%+ of new users succeed without help

### Cybernetic Viability (Hard Requirements)

- [ ] VSM completeness: all five systems operational (S1 operations, S2 coordination, S3 control, S3* audit, S4 intelligence, S5 policy)
- [ ] Autopoietic closure: system reproduces its own operational logic from outcomes across ≥3 dimensions
- [ ] Requisite variety: >80% of tasks use specialized routing (not generic/default)
- [ ] Free energy minimization: prediction error autonomously triggers model updates AND active interventions
- [ ] No alignment faking: Interspect cannot modify the evaluation criteria it uses to assess its own overlays

### Operational Design Domain (Hard Requirements)

- [ ] In-scope domains explicitly published (languages, project types, team sizes, autonomy tier)
- [ ] Out-of-scope domains explicitly published (what is v2.0+)
- [ ] Autonomy tier promise published (L1-L3 for v1.0)
- [ ] Human oversight requirements documented

---

## 8. The v1.0.0 Declaration Template

```markdown
# Sylveste v1.0.0: Production-Ready Autonomous Software Development

**Released:** [date]

## Stability Commitment

Sylveste v1.0.0 declares backward compatibility for the structural API (layer 1:
CLI, schemas, hooks, events) throughout the v1.x release series. Behavioral
policies (routing, gates, review criteria) evolve with documented migration paths.
Model-dependent behavior adapts to external model changes with graceful degradation.

## What This Release Promises

- **Infrastructure Stability:** The machinery that orchestrates autonomous development
  (phase gates, event pipelines, calibration loops, plugin interface) is load-bearing
  and will not change in breaking ways until v2.0.0.

- **Behavioral Envelopes:** The system produces results within documented bounds. Pass@k
  metrics, completion rates, defect detection rates are measured and published.

- **Graceful Adaptation:** When model providers change their offerings, Sylveste detects
  the impact within N sprints, falls back safely, and re-optimizes routing without human
  manual intervention.

- **Operator Control:** Configuration choices (risk tolerance, model preference, review
  depth) produce measurably different outcomes. The system amplifies operator judgment
  rather than replacing it.

- **Auditable Autonomy:** Every decision the system makes produces durable evidence.
  What the agents decided, why they decided it, what evidence informed the decision —
  all are reconstructable from receipts.

## What This Release Does NOT Promise

- **Deterministic outputs:** The same input will not produce identical outputs across runs
  because the underlying models are stochastic. This is a feature, not a bug.

- **Universal domain coverage:** Sylveste is proven on [list ODD]. Arbitrary software
  development is a v2.0+ goal.

- **Output quality floor:** Agent quality depends on model capabilities, which change
  independently of platform version. The platform's job is routing and gating, not
  intelligence.

- **Cost stability:** Token consumption, model availability, and provider pricing change
  externally. The platform's job is cost-aware routing, not cost guarantees.

- **Autonomy L4+:** The system does not auto-merge or auto-deploy. Human approval remains
  required at the ship phase. L4+ are v2.0+ goals.

## Evidence

- 785+ self-building sessions, $2.93/landable-change baseline
- 50+ sprints each on 2 external Go/Python projects
- 20+ sprints each on 3 cross-domain projects (web, infrastructure, data)
- All existential failure modes mechanically prevented
- Three calibration loops (routing, gates, phase-cost) operating autonomously
- Deletion-recovery test passed: system recovers to baseline within 50 sprints with no manual intervention

## Migration Path from v0.6.x

Upgrading from v0.6.x to v1.0.0 requires: [migration guide]. No changes to sprint
configurations, calibration data, or plugin installations are required.

## Maintenance Commitment

Sylveste v1.x will receive updates for a minimum of 24 months from v1.0.0 release.
Security fixes will be backported to the two most recent v1.x minor releases. Feature
releases occur every [N] weeks with deprecation warnings [N] releases before removal.

## Known Limitations

[List domains that are functional but not fully qualified. Example: "Web frontend
projects work but have been tested on only 3 projects. Performance on monorepos with
>100K files is untested."]
```

---

## Summary

The single most important finding is that **v1.0.0 should mean the three calibration loops turn autonomously**, not that all features are done. This is neither a massive new undertaking nor a marketing exercise. It is wiring existing systems into their designed feedback loops.

The six frameworks converge on this: a v1.0 platform is one that *improves itself without manual cranking*. Sylveste already has the machinery. It needs activation.

The path is:
1. **v0.7:** Autonomy loops close
2. **v0.8:** Evaluation infrastructure + L3 remediation
3. **v0.9:** External validation + ODD declaration
4. **v1.0:** Stability commitment + production declaration

This is achievable. The architecture is sound. The pieces are in place. What remains is integration, validation, and honest communication about what has been proven and what remains to be done.
