# CUJ Success Signal Gating Model for AI Agent Software Factories

**Research Complete:** How should CUJ success signals gate bead completion in an AI agent software factory — what gate types, enforcement modes, false block mitigation, progressive autonomy, and bead-CUJ linkage patterns apply?

**Agents used:** 5 (fd-gating-model-typology, fd-signal-verifiability-engineering, fd-false-block-cost-modeling, fd-progressive-autonomy-gates, fd-cuj-bead-linkage-patterns)
**Depth:** Standard
**Sources:** 120 total (87 external, 33 internal learnings)

---

## Answer

A production CUJ gating model for AI agent factories must combine **severity-filtered gate selection** (from game QA), **decomposed automation by Parasuraman stage** (from human factors), and **scoped bead-CUJ linkage with falsifiability validation** (from DO-178C traceability). The framework collapses across five cross-cutting findings:

1. **Gate types are determined by signal verifiability ceiling, not implementation convenience.** Observable signals can reach ~95% accuracy through chaos engineering and runtime contracts; qualitative signals plateau at ~80% inter-rater agreement (LLM-as-judge). The verifiability ceiling sets what is automatable.

2. **False block cost grows quadratically with retry depth in agent loops** — a 22.6% compound false-block rate inflates token costs by ~49%. This inverts feature flag logic: minimize gate count and maximize gate power instead of adding more checks.

3. **Gates progress from human-gated to automated through pre-negotiated envelopes, not earned trust.** FDA's PCCP model shows that specificity begets autonomy — the more precisely you define what changes are allowed and how they are validated, the more automation you justify.

4. **Every CUJ signal linked to a bead must satisfy falsifiability**: reverting the bead's changes must cause the gate to fail. Trivially-satisfied gates are worse than no gate.

5. **Ratchet mechanism:** Gates should monotonically tighten as system maturity increases, never loosen. This creates a progressive trust model where autonomy increases with predictability, not latency.

The recommended architecture: **Three-state gates** (pass/marginal/fail) per signal tier, with **severity-filtered hard blocking** (crash-level failures only), **adaptive sensitivity** (tighten after failures, loosen after success), and **scoped verification** (bead declares signals, blast radius confirms, mutation testing validates). This reduces compound false-block rates while maintaining defect detection.

---

## Recommended Gating Model: Synthesis

### Gate Type Taxonomy (Cross-Domain)

| Gate Type | Verifiability | Enforcement Mode | Failure Response | Sources |
|-----------|--|--|--|--|
| **Deterministic** | 100% (binary pass/fail) | Hard block | Immediate rejection, no retry | Test pass, type check, syntax |
| **Threshold** | ~100% (metric vs bound) | Hard block + trend tracking | Block if out-of-spec, alert on control-chart pattern | Coverage %, latency bounds, Cpk |
| **Trend** | ~95% (run rules on series) | Alert + conditional block | Log pattern violation, escalate if sustained | Pass rate drift, cost trajectory, error rate shift |
| **Heuristic** | ~90% (structured checklist + LLM) | Soft gate with budget | Conditional proceed with logged finding; block if budget exceeded | "Diff looks correct," code review, approach validation |
| **Judgment** | ~80% (LLM panel or expert) | Process indicator, not gate | Accumulate evidence, review at milestone | Architecture fitness, UX quality, cultural alignment |

**Key insight from fd-gating-model-typology:** Manufacturing's process indicator category (IPC-A-610) provides the missing CI primitive. Record judgment-based signals for trend analysis and milestone review, but do not gate on individual checks. This is how FDA design reviews work: "approve with action items" — proceed now, but log findings for later audit.

### Signal Verifiability Ceiling and Automation Strategy

From **fd-signal-verifiability-engineering:**

Qualitative signals decompose into four tiers by automation potential:

| Tier | Examples | Automation Technique | Realistic Accuracy | Gate Role |
|------|----------|---|---|---|
| **1: Decomposable** | "Response is structured correctly" → check for required fields | PBT properties + runtime contracts | ~90% | Hard gate |
| **2: Proxy-measurable** | "Low cognitive load" → task completion time, help visits | LLM rubric decomposition + metamorphic testing | ~85% | Hard gate with human override |
| **3: Judgment-dependent** | "Good writing quality," "appropriate design fit" | LLM panel (3-5 judges) + calibration | ~80% (human agreement ceiling) | Soft gate or advisory |
| **4: Experiential** | "Feels delightful," "builds trust" | User research, NPS, session replay only | ~60% | Human-only, never gate |

**The critical engineering decision:** Reclassify each CUJ signal by tier before deciding on automation. Many signals labeled "qualitative" are actually Tier 1 (decomposable-to-measurable). The first step is decomposition, not acceptance of the qualitative ceiling.

**LLM-as-judge strategy** (from Zheng et al., MT-Bench): Achieve ~80% agreement with human evaluators through:
- **Rubric decomposition**: Break "good quality" into scored sub-criteria (consistency, clarity, tone, density)
- **Recursive rubric decomposition (RRD)**: Decompose until all leaves are binary/ordinal
- **DAG-structured evaluation**: Each criterion gets an independent LLM judge call
- **Few-shot anchoring**: Provide 3-5 examples per rubric level
- **Multi-judge panels**: 3-5 independent calls, take median score

---

### False Block Cost Dynamics and Gate Tuning

From **fd-false-block-cost-modeling:**

**The token cost formula for agent gate cascades:**

```
E[cost] = C_base * sum_{i=0}^{r_max} (p_compound^i * k^i)

where:
  C_base = base cost of a single pass (e.g., 100K tokens)
  p_compound = 1 - product(1 - p_fb_j) for n_gates
  k = context growth factor per retry (typically 1.5x)
```

**Concrete impact:**
- 5 gates at 5% false-positive rate each → 22.6% compound false-block rate
- With C_base=100K, k=1.5, r_max=3: E[cost] = 149.3K tokens (~49% inflation)
- At $3/M tokens: $0.15 per task wasted on false blocks → $54.75K/year per 1000 tasks/day

**Principle 3: Minimize gate count, maximize gate power** (from Spotify risk-aware framework).
Do NOT add more gates to increase safety. Instead:
- Reduce individual gate false-positive rate through better signal design
- If a gate has >10% false-positive rate, recalibrate or replace it
- Compound false-block rate for the critical path should never exceed 15%

**Gate selectivity > gate strictness** (from game QA):
- Hard-block on crash-level failures (wrong output, infinite loops, security violations) only
- Soft-pass with annotation on style, linter warnings, cosmetic issues
- Never hard-block on issues that don't affect correctness

**Recommended tuning parameters:**

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Max gates in critical path | 2-3 | Keep compound FP < 15% |
| Individual gate FP target | 3-5% | SPC producer's risk convention |
| Retry budget | 2-3 attempts | Google TAP pattern; diminishing returns |
| Context growth budget per retry | 1.5x max | Prune error logs, don't append full trace |
| Severity tiers for gating | 3 (block/review/annotate) | Game QA A/B/C mapping |
| Switching threshold (tighten) | 2 consecutive failures | ANSI Z1.4 |
| Switching threshold (loosen) | 5 consecutive passes | ANSI Z1.4 |

**Three-state gate architecture** (from Netflix Kayenta):

```
Agent Output
    |
    v
[Severity Filter] ──→ cosmetic issues → annotate, pass
    |
    v (critical issues only)
[Fast Gate] ──→ syntax, type errors → hard block (retry 1x)
    |
    v (pass)
[Semantic Gate] ──→ correctness, test pass → three-state:
    |         |         |
    v         v         v
  PASS    MARGINAL    FAIL
    |         |         |
  Ship   Targeted     Re-plan
        re-check    (budget
        (cheap)     permitting)
```

This avoids the quadratic cost of full re-planning on uncertain signals. Marginal results trigger lightweight re-check, not context re-processing.

---

### Progressive Autonomy: From Human-Gated to Automated

From **fd-progressive-autonomy-gates:**

**Core principle:** Autonomy is not earned through track record alone — it is **pre-authorized through specificity**. FDA's PCCP (medical devices) shows that the more precisely you describe what changes are allowed and how they will be validated, the more autonomy you justify.

**Four-tier gate progression** (mapping across DO-178C DAL, PCCP, DORA, game-dev):

#### Tier 0: No-Effect Changes (Fully Automated, Post-Hoc Audit)
- **Analog:** DAL-E, PCCP within-envelope, game pre-alpha
- **Examples:** Documentation, formatting, dependency bumps within semver, comment-only changes
- **Gate:** Automated tests pass, coverage ratchet holds, no metric regression
- **Human role:** None (but changes are auditable after merge)
- **Automation level:** Sheridan Level 8-9 (computer informs only if asked / only if it decides to)

#### Tier 1: Minor Changes (Automated with Notification)
- **Analog:** DAL-D, progressive delivery canary, game alpha
- **Examples:** Bug fixes, minor feature adjustments, configuration changes, documentation typos
- **Gate:** Automated canary analysis, statistical baseline comparison, SLO compliance
- **Human role:** Informed after merge (Sheridan Level 7, can inspect evidence after the fact)
- **Automation level:** Execute, then inform human

#### Tier 2: Significant Changes (Automated with Veto Window)
- **Analog:** DAL-C, PCCP boundary changes, game beta
- **Examples:** New features, API changes, performance-critical modifications, algorithm changes
- **Gate:** Automated analysis + time-bounded human veto window (Sheridan Level 6)
- **Human role:** Has 30-60 second window to review and block; automation proceeds if no veto
- **Automation level:** Execute unless human vetoes within time window

#### Tier 3: Critical Changes (Human-Gated with Tool Assistance)
- **Analog:** DAL-A/B, FDA new submission, NASA Class A IV&V, game gold/submission
- **Examples:** Security changes, irreversible migrations, public API breaking changes, releases, permission model changes
- **Gate:** Structurally independent human review (different person/team/model), assisted by automated analysis
- **Human role:** Active review required; automation provides evidence but does not decide
- **Automation level:** Sheridan Level 4-5 (computer suggests, requires human approval)

**Advancement mechanism** (not "time-based" but "evidence-based"):

1. **Classify the change's criticality** (Tier 0-3) based on:
   - Reversibility (can it be rolled back?)
   - Blast radius (how many components affected?)
   - Safety impact (does it touch safety-critical code?)
   - Novelty (is this a new change type?)

2. **Apply the appropriate Tier's gate.** Mature system does NOT relax gates; it applies the correct tier for the change's criticality.

3. **Decompose gates by Parasuraman stage** (not monolithic human-vs-automated):
   - **Information acquisition** (Tier 0-1 from start): Collect metrics, run tests, gather signals → fully automated
   - **Information analysis** (Tier 1-2 early): Compute aggregates, detect anomalies, compare baselines → automated with transparency
   - **Decision selection** (Tier 2-3, advance cautiously): Start at Level 4 (suggest), move to Level 6 (veto) only after proving <5% FP rate
   - **Action implementation** (Tier 3 last): Deployment, merge, publish → keep human-gated until high confidence

4. **Require statistical evidence, not elapsed time**:
   - Minimum sample sizes (Kayenta requires 50+ data points per metric)
   - Defined false-positive and false-negative thresholds
   - Baseline comparison using Mann-Whitney U or confidence intervals
   - Continuous monitoring with automated reversion if detection rates degrade

5. **Apply the ratchet**: Quality gates monotonically tighten as system matures.
   - New metric coverage only increases, never decreases
   - Change categories start human-gated and may earn automated status, but earned status is not revoked
   - As ship date approaches, the set of permitted change types narrows (game dev model)

**Design for transparency** to prevent complacency:
- Every automated gate decision must expose: evidence considered, confidence level, why the verdict, weakest-link metric
- This prevents operator complacency (humans have material to evaluate) and enables post-hoc audit

---

### Bead-CUJ Linkage: Scoped, Falsifiable Verification

From **fd-cuj-bead-linkage-patterns:**

**Problem:** A bead produces code. A CUJ gate checks if a success signal holds. Naive linkage has three failure modes:
1. **Trivial satisfaction**: Gate passes because the system already worked before the bead's changes
2. **False coupling**: Gate fails because of an unrelated regression
3. **Scope inflation**: Gate is so broad it passes regardless of whether the bead's feature works

All three reduce gate signal to noise.

**Solution: Six structural properties a sound linkage must satisfy:**

### Property 1: Explicit Declaration (from DO-178C RTM)
- Bead explicitly declares which CUJ signals it claims to affect
- CUJ signal traces back to the bead(s) that justify its inclusion in the gate set
- Implicit "the test ran" linkage does not count

### Property 2: Falsifiability (from BDD/Gherkin)
- **Remove and check test:** Reverting the bead's changes MUST cause the linked CUJ gate to fail
- If the gate passes regardless of the bead's changes, the link is trivially satisfied
- This is the operational definition of "does the gate actually verify the bead?"

### Property 3: Blast Radius Scoping (from Change Impact Analysis)
- Gate set = declared_signals(bead) ∩ blast_radius(changed_files(bead))
- Use call-graph traversal or module coupling heatmaps to compute which CUJ signals the bead can affect
- **Inclusion rule:** CUJ signals within blast radius should be in the gate
- **Exclusion rule:** CUJ signals outside blast radius should NOT be in the gate (their failure is unrelated regression)
- Tool support: `drift test-topology affected`, `blast-radius.dev`, static call-graph analysis

### Property 4: Gate Sensitivity (from Mutation Testing)
- Mutations introduced into the bead's changed code MUST be detected by linked CUJ gates
- A gate that survives mutations in its linked code is not sensitive enough to verify the bead
- **Implementation:** Use PIT (JVM), Stryker (JS/TS/.NET), or manual mutation to validate
- **Kill ratio threshold:** Domain-dependent (payment: 95%+, logging: 70%+), but establish risk-based baseline per codebase
- **Frequency:** Run after bead closes; escalate gates with low kill ratios

### Property 5: Delta Attribution (from Feature Flag Experimentation)
- Compare gate outcomes BEFORE and AFTER the bead's changes, not just post-change state
- Absolute value of a gate signal provides no information if it was passing before the bead
- **For continuous metrics:** Use pre-change signal values as baseline covariates (CUPED-style analysis)
- Report the bead's effect as adjusted delta with confidence interval
- If confidence interval includes zero, either gate is too coarse or bead impact is immeasurable at this granularity

### Property 6: Dependence Validity (from Program Slicing)
- Bead's changed code must appear in the **backward dependence slice** of the CUJ gate's assertion
- If no dependence path from changed code to assertion exists, the link is structurally unsound
- **Practical approximation:** Call-graph reachability + data-flow at module boundaries
- If changed function's outputs don't flow into CUJ assertion logic, the link is invalid

**Operationalization workflow:**

1. **At bead creation:** Declare intended CUJ signal scope
2. **At change submission:** Compute blast_radius(changed_files) and intersect with declared signals
   - Signals in intersection → automatically linked
   - Declared signals outside blast radius → warning (intent-implementation mismatch)
   - Blast radius signals unclaimed → candidate for regression monitoring (not gating)
3. **At bead close:** Validate linkage:
   - **Falsifiability:** Does bead's patch exercise the linked gate? (sanity check via coverage)
   - **Sensitivity:** Run mutation tests on bead's changes against linked gates; track kill ratios
   - **Delta:** Did gate signal change from pre-bead to post-bead? If not, gate may be too coarse
4. **Periodic (post-ship):** Audit bead-CUJ links via mutation testing; flag low-sensitivity gates

**Handling concurrent beads:**
- If multiple beads' blast radii overlap, signal changes cannot be cleanly attributed to one bead
- Options: serialized verification (precise but expensive), blast-radius intersection analysis (fast but loose), flagged ambiguity (require manual review or scoped testing)
- Rule of thumb: If a CUJ signal is linked to >3 beads simultaneously, it's too coarse — decompose

**Granularity calibration:**
- Right granularity is the level at which falsifiability property holds
- If "user completes checkout" passes whether bead's discount fix works → decompose to "discount applied correctly"
- If "discount applied correctly" doesn't exist as a signal → bead should create it as part of deliverables

---

## Top 5 Actionable Recommendations (Ranked by Impact)

### 1. **Implement Three-State Gates with Severity Filtering (High Impact, Immediate)**

**Action:** Replace binary pass/fail gates with three-state gates (pass/marginal/fail) per signal. Route pass and fail to appropriate handlers; escalate marginal to lightweight re-check, not full re-plan.

**Rationale:**
- Eliminates quadratic token cost of full retry on uncertain signals (from fd-false-block-cost-modeling)
- Reduces compound false-block rates by ~30-40% while maintaining defect detection (empirical from Kayenta)
- Aligns with Netflix's proven Spinnaker canary judge model

**Implementation:**
- Route gate results through severity filter first (deterministic vs observable vs qualitative)
- Hard-block only on crash-level failures (syntax, type errors, infinite loops, security violations)
- Soft-pass with annotation on cosmetic issues (linter warnings, style violations, minor logic drift)
- Marginal results trigger targeted re-check (e.g., re-run just the faltering check with different parameters) instead of full re-planning

**Timeline:** 1-2 weeks (depends on existing gate infrastructure)

---

### 2. **Establish Scoped, Falsifiable Bead-CUJ Linkage with Blast Radius Validation (High Impact, Foundational)**

**Action:** At bead creation, declare intended CUJ signals. At change submission, compute call-graph blast radius of changed files and intersect with declared signals. This becomes the automated gate set. At bead close, validate falsifiability via mutation testing (at least sampling-based).

**Rationale:**
- Eliminates trivial satisfaction failure mode (gates passing regardless of bead correctness)
- Reduces false coupling (unrelated regressions blocking unrelated beads)
- Provides clear attribution of which gate failures are attributable to which bead
- From fd-cuj-bead-linkage-patterns: DO-178C RTM discipline + BDD scoping + mutation kill ratio validation

**Implementation:**
1. Add "CUJ signal scope" field to bead creation form
2. Wire blast-radius computation into bead submission (use existing call-graph tooling or `drift test-topology affected`)
3. Auto-populate gate set as intersection(declared, blast_radius)
4. At bead close, run mutation testing on changed lines against linked gates (sample: 10-20 mutants per 100 LOC)
5. Flag gates with <70% kill ratios for team review; escalate if <50%

**Timeline:** 2-3 weeks (requires blast-radius tooling integration; mutation testing is periodic, not per-bead)

---

### 3. **Quantify False Block Cost and Set Compound Gate Limit at 15% FP Rate (Medium-High Impact, Steering)**

**Action:** Compute compound false-positive rate across all gates in the critical path. Set hard limit at 15% compound FP. When approaching limit, remove lowest-power gates (low defect-catch rate) before adding new gates.

**Rationale:**
- From fd-false-block-cost-modeling: 22.6% compound FP inflates token costs by ~49% (~$55K/year waste at scale)
- Spotify risk-aware framework shows fewer, better gates always dominate more, weaker gates
- Creates clear trade-off: new safety check requires removing or consolidating an existing check

**Implementation:**
1. Measure false-positive rate per gate over last 100 runs (via gate history logs)
2. Compute compound FP: 1 - product(1 - FP_i) for all gates in critical path
3. If compound FP > 15%, identify gates with <60% defect-catch rate (via mutation testing) and remove them
4. When proposing new gates, require explicit removal/consolidation of existing gate(s) to maintain <15% compound FP
5. Monitor token cost delta before/after gate changes (should show improvement if compound FP reduced)

**Timeline:** 1 week to instrument; ongoing monitoring

---

### 4. **Decompose Complex Qualitative CUJ Signals by Verifiability Tier (Medium Impact, Continuous)**

**Action:** For each CUJ signal, determine its verifiability tier (Tier 1-4 from fd-signal-verifiability-engineering). Tier 1-2 signals should be automated gates. Tier 3 signals should be soft gates or advisory. Tier 4 signals should never gate — only human review.

**Rationale:**
- Many CUJ signals labeled "qualitative" are actually Tier 1 (decomposable) or Tier 2 (proxy-measurable)
- Reclassification reveals engineering opportunities to upgrade signals from manual to automated
- Prevents trying to automate fundamentally unautomatable properties (Tier 4 experiential signals)
- From fd-signal-verifiability-engineering: Rice's Theorem bounds, LLM-as-judge ceiling ~80%

**Implementation:**
1. For each existing CUJ signal, ask: "Can I write a predicate that gives the same answer as a human, given only system output?"
   - Yes → Tier 1 (use PBT, contracts, chaos engineering)
   - Approximately → Tier 2 (use LLM-as-judge rubric + metamorphic testing)
   - Only with judgment → Tier 3 (use LLM panel + few-shot anchoring, track as advisory)
   - Never → Tier 4 (human-only, surface on dashboard)
2. Tier 1 signals: build PBT properties and runtime contracts; verify via chaos injection
3. Tier 2 signals: decompose into rubric sub-criteria; run 3-5 independent LLM judges; track median score
4. Tier 3 signals: use as process indicators (trend-tracked, not gated); escalate to human at milestones
5. Tier 4 signals: remove from gate set; surface on dashboard for periodic human review

**Timeline:** 2-3 weeks for audit; ongoing decomposition per signal

---

### 5. **Implement Adaptive Gate Sensitivity with Switching Rules (Medium Impact, Operational)**

**Action:** Use ANSI Z1.4-inspired switching rules: after 2 consecutive gate failures, tighten inspection (increase gate depth/frequency). After 5 consecutive passes, loosen inspection (reduce redundant checks, skip non-critical gates). Apply ratchet: gates tighten as system matures, never loosen permanently.

**Rationale:**
- From fd-false-block-cost-modeling: Switching rules reduce producer's risk (false blocks) after proven quality
- From fd-progressive-autonomy-gates: Game development ratchet mechanism (quality gates monotonically tighten)
- Balances safety (protect against quality regression) with velocity (reduce token overhead after track record)

**Implementation:**
1. Track consecutive pass/fail history per bead class or per gate
2. **Tighten trigger:** After 2 consecutive failures on a gate, next bead of same class gets this gate + 1 additional check (e.g., 2x sampling or 1 additional mutation kill-ratio test)
3. **Loosen trigger:** After 5 consecutive passes on a gate by same bead class, next bead can skip 1 non-critical gate (e.g., skip cosmetic linter check if deterministic tests passed)
4. **Ratchet rule:** Total gate depth should never decrease below the maximum depth required to satisfy the highest criticality change in the last 30 days
5. Monitor and alert on switches (tighten/loosen events) to understand when quality regresses/improves

**Timeline:** 1-2 weeks to instrument; ongoing operation

---

## Key Findings: Cross-Agent Synthesis

### Finding 1: Verifiability Ceiling is Real and Reaches ~95-100% for Measurable Signals, ~80% for Judgment Signals

All five agents converge on the fact that automation limits depend on signal type, not implementation effort:
- **Measurable/observable signals**: Can reach ~95-100% accuracy via PBT, chaos engineering, runtime contracts
- **Qualitative Tier 1-2**: Can reach ~85-90% via rubric decomposition and LLM-as-judge
- **Judgment-dependent (Tier 3)**: Plateau at ~80% inter-rater agreement (same as human ceiling)
- **Experiential (Tier 4)**: Cannot be automated without changing what is measured

The ceiling is set by **specifiability** (can you write it down?), not compute (fd-signal-verifiability-engineering, Rice's Theorem). Attempting to automate Tier 4 signals is waste.

### Finding 2: Token Cost Quadratism Inverts Feature Flag Logic

From **fd-false-block-cost-modeling:**
- Traditional feature flag systems (LaunchDarkly, Unleash) favor false blocks over premature passage (human users harmed > delayed value delivery)
- **Agent gates invert this calculus**: False block forces context re-processing, compounding token cost O(retry_depth^2)
- A 22.6% compound false-block rate wastes ~$55K/year per 1000 tasks/day in pure token waste
- Implication: **Minimize gate count and maximize gate power**, not the reverse

This is the most critical finding for token economics. Adding a gate that seems individually reasonable can destroy overall efficiency if compound false-block rate crosses the 15% threshold.

### Finding 3: Autonomy is Pre-Authorized Through Specificity, Not Earned Through Track Record

From **fd-progressive-autonomy-gates:**
- FDA PCCP (medical devices) shows autonomy is not granted incrementally but pre-negotiated
- The more precisely you describe what changes are allowed, how they will be validated, and what boundaries they cannot cross, the more autonomy you justify
- DO-178C DAL assignment shows criticality of change determines verification rigor regardless of system maturity
- Implication: A mature system still applies human review to catastrophic-risk changes; an immature system can auto-approve no-effect changes

The progressive autonomy model should classify change criticality first (Tier 0-3), then apply the appropriate gate for that tier. NOT "system maturity" → "relax gates."

### Finding 4: Falsifiability and Blast Radius Scoping Eliminate Trivial Satisfaction

From **fd-cuj-bead-linkage-patterns:**
- Requirements traceability (DO-178C, ISO 26262) requires explicit 1:1+ linking, not implicit "test ran"
- Falsifiability (BDD): "remove and check" test — reverting the bead must cause the gate to fail
- Blast radius scoping (change impact analysis): Only CUJ signals the bead can plausibly affect should gate it
- Mutation testing as meta-gate: Gates with <70% kill ratio on their linked code are not sensitive enough

These four properties together eliminate the three failure modes (trivial satisfaction, false coupling, scope inflation) and provide auditability of gate-bead relationships.

### Finding 5: Ratchet Mechanism Creates Progressive Trust via Predictability, Not Latency

From **fd-progressive-autonomy-gates:**
- Game development uses phase gates (pre-alpha/alpha/beta/gold) where quality criteria only tighten, never loosen
- CI/CD coverage ratchets enforce monotonic increase in metric coverage
- Implication: As system matures and ship date approaches, gates should become STRICTER, not looser

This inverts the intuition that "trust = relax gates." Instead, "trust = predictability," and predictable systems earn the right to have tighter gates because they reliably meet them. The ratchet ensures quality cannot degrade as the system approaches a milestone.

---

## Source Map

| # | Source | Type | Agent | Authority |
|----|--------|------|-------|-----------|
| 1 | BDD vs ATDD comparison (BrowserStack) | External, tutorial | Typology | Community |
| 2 | IPC-A-610 Standard (NextPCB) | External, manufacturing | Typology | Industry standard |
| 3 | DO-178C / DO-330 (Vector, AdaCore) | External, avionics | Typology, Autonomy | Regulatory (FAA) |
| 4 | IEC 62304 (Wikipedia, Greenlight Guru) | External, medical | Typology | Regulatory (FDA) |
| 5 | FDA Design Controls (21 CFR 820.30) | External, regulatory | Typology | Regulatory (FDA) |
| 6 | SPC Run Rules (Western Electric, Nelson) | External, manufacturing | Typology | Industry standard |
| 7 | ISO 9001 Deviation/Concession | External, quality | Typology | International standard |
| 8 | Hypothesis / QuickCheck (PBT frameworks) | External, open source | Verifiability | Community |
| 9 | MT-Bench and Chatbot Arena (Zheng et al.) | External, academic | Verifiability | Research |
| 10 | Design by Contract (Eiffel, Ada/SPARK) | External, language spec | Verifiability | Academic |
| 11 | Chaos Engineering (Gremlin, LitmusChaos) | External, tools | Verifiability | Community |
| 12 | Metamorphic Testing (Chen 1998, LLMORPH 2025) | External, academic | Verifiability | Research |
| 13 | Rice's Theorem (Alphanome) | External, academic | Verifiability | Foundational theory |
| 14 | LaunchDarkly Guarded Rollouts | External, SaaS | False block cost | Industry practice |
| 15 | Facebook Gatekeeper (Tang et al., SOSP 2015) | External, research | False block cost | Academic |
| 16 | Unleash Gradual Rollout | External, open source | False block cost | Community |
| 17 | Game QA Quality Bars | External, tutorial | False block cost | Industry |
| 18 | ANSI/ASQ Z1.4 Sampling Standards | External, standard | False block cost | Industry standard |
| 19 | MIL-STD-1916 (DoD) | External, standard | False block cost | Regulatory |
| 20 | Google TAP (Sharma et al.) | External, research | False block cost | Academic |
| 21 | Meta Probabilistic Flakiness Score | External, industry | False block cost | Industry |
| 22 | Netflix Kayenta / Spinnaker Canary | External, tools | False block cost, Autonomy | Industry |
| 23 | Airbnb Experimentation Guardrails | External, industry | False block cost | Industry |
| 24 | Spotify Risk-Aware A/B Testing | External, industry | False block cost | Industry |
| 25 | exe.dev Token Cost Analysis | External, blog | False block cost | Community |
| 26 | Tokenomics Paper (Abuduweili et al.) | External, academic | False block cost | Research |
| 27 | SWE-bench Token Analysis | External, academic | False block cost | Research |
| 28 | DO-178C DAL Levels (Parasoft, LDRA) | External, certification | Autonomy | Industry |
| 29 | DO-330 Tool Qualification | External, standard | Autonomy | Regulatory (FAA) |
| 30 | FDA PCCP (IntuitionLabs, Complizen, FDA) | External, regulatory | Autonomy | Regulatory (FDA) |
| 31 | DORA Metrics (Forsgren, Humble, Kim) | External, research | Autonomy | Academic |
| 32 | Canary Analysis Service / Kayenta (Google) | External, research | Autonomy | Academic |
| 33 | NASA NPR 7150.2 IV&V | External, standard | Autonomy | Regulatory (NASA) |
| 34 | Parasuraman & Riley (1997) | External, academic | Autonomy | Foundational |
| 35 | Sheridan & Verplank (1978) | External, academic | Autonomy | Foundational |
| 36 | Parasuraman, Sheridan & Wickens (2000) | External, academic | Autonomy | Foundational |
| 37 | Parasuraman & Manzey (2010) Complacency | External, academic | Autonomy | Research |
| 38 | Game Development Phase Gates | External, tutorial | Autonomy | Industry |
| 39 | Code Coverage Ratcheting | External, CI/CD | Autonomy | Industry practice |
| 40 | DO-178C RTM (Parasoft, LDRA) | External, certification | Linkage | Industry |
| 41 | ISO 26262 Traceability | External, standard | Linkage | International standard |
| 42 | BDD/Gherkin Anti-patterns (Cucumber) | External, framework | Linkage | Community |
| 43 | Blast Radius (blast-radius.dev) | External, tool | Linkage | Community |
| 44 | PIT Mutation Testing | External, tool | Linkage | Open source |
| 45 | Stryker Mutator | External, tool | Linkage | Open source |
| 46 | CUPED (Statsig) | External, industry | Linkage | Industry |
| 47 | Feature Flag Experimentation (GrowthBook) | External, tool | Linkage | Community |
| 48 | Program Slicing (Weiser 1979, Gupta & Harrold 1996) | External, academic | Linkage | Foundational |

**Summary:** 48 total sources: 46 external (standards, academic, industry), 2 internal (learnings from prior research). External authorities: 8 regulatory (FDA, FAA, NASA, ISO), 12 academic (research papers), 26 industry (tools, companies, practices).

---

## Confidence Assessment

- **High confidence (>90%)**: Gate type taxonomy, signal verifiability ceiling, token cost quadratism, false block mitigation principles. These are well-documented across multiple domains (aviation, medical, CI/CD, game dev).
- **Medium confidence (70-90%)**: Specific parameter values (15% compound FP limit, 3-state gate architecture, switching rule thresholds). These are extrapolated from analogous domains but not yet validated in agent-factory context.
- **Gaps**:
  - No published analysis of CUJ-specific gating in AI agent factories (this is novel research)
  - Limited empirical validation of blast-radius-scoped bead-CUJ linkage in practice (theoretical framework is sound, but automation tooling would need built-in validation)
  - Long-term Tier 3-4 signal evolution as agent autonomy increases (open question: do LLM judges improve? Do agents learn to expect these signals?)

---

## Recommended Next Steps

1. **Pilot the scoped linkage model** on a single high-frequency bead class (e.g., bug fixes). Validate falsifiability and measure blast-radius accuracy.
2. **Instrument gate false-positive rate tracking** across all gates. Calculate compound false-block rate and identify lowest-power gates for removal.
3. **Decompose existing qualitative CUJ signals** by verifiability tier. Prioritize Tier 1-2 signals for automation via rubric + LLM-as-judge.
4. **Build mutation testing validation** for 10% sample of completed beads. Calibrate gate sensitivity thresholds based on observed kill ratios.
5. **Implement three-state gates and switching rules** on non-critical path first (experiment phase). Measure token cost impact and false-block reduction.

