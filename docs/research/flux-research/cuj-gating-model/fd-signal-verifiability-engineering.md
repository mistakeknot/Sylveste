# Signal Verifiability Engineering

How property-based testing, formal verification, and LLM-as-judge techniques can upgrade qualitative CUJ signals toward measurability — and where the verifiability ceiling is irreducible.

## Context

The CUJ standard (docs/canon/cuj-standard.md) defines three signal types: **measurable** (quantitative, automatable), **observable** (detectable with instrumentation), and **qualitative** (requires human judgment). The gap between observable and measurable is an engineering problem. The gap between qualitative and observable is partly an engineering problem and partly a fundamental limit. This document surveys techniques for closing both gaps and identifies where the ceiling cannot be raised.

---

## 1. Property-Based Testing for Signal Validation

### Applicable Techniques

Property-based testing (PBT) frameworks — Hypothesis (Python), QuickCheck (Haskell/Erlang), fast-check (TypeScript/JavaScript) — generate adversarial inputs and check that declared properties hold across thousands of random scenarios. The core insight for CUJ signals: **success signals are properties, and PBT can verify they fire correctly under adversarial conditions.**

**Stateful model-based testing** is the most relevant PBT variant. Rather than testing pure functions, it generates random sequences of commands against a state machine model and checks postconditions after each step. QuickCheck State Machine and proptest-state-machine (Rust) pioneered this. For CUJ signals, the approach maps directly:

| CUJ concept | PBT concept |
|---|---|
| Journey steps | Command sequence |
| Success signal | Postcondition check |
| Known friction point | Precondition filter |
| Actor state | Model state |

**Shrinking** — PBT's best feature for signal work — takes a failing scenario and reduces it to the minimal sequence that violates the signal. This converts "signal X didn't fire during journey Y" into "signal X fails specifically when steps A→C→E occur in that order", which is actionable.

### Concrete Application Pattern

```
1. Define signal properties as predicates: signal_fires(state) → bool
2. Define journey steps as PBT commands with pre/postconditions
3. Generate 10K random journey orderings, timing variations, error injections
4. Assert: for every terminal state reachable via valid journey steps,
   all declared success signals evaluate to true
5. Shrink failures to minimal counterexamples
```

### What This Upgrades

- **Observable → Measurable**: If a signal is "detectable with instrumentation," PBT can verify it fires correctly across adversarial scenarios, converting it to a CI-automatable assertion.
- **Qualitative (partial)**: Structural properties of qualitative signals (e.g., "response contains relevant information" can be decomposed into "response references entities mentioned in query") can become PBT properties.

### Limits

PBT requires properties to be machine-evaluable predicates. Signals like "feels intuitive" or "low cognitive load" cannot be expressed as postconditions. PBT also requires a model — if the correct behavior can't be specified as a state machine, the technique doesn't apply.

---

## 2. Runtime Contract Frameworks

### Design by Contract for Signal Invariants

Design by Contract (DbC), originating in Eiffel and now available in Ada/SPARK, D, and via libraries in most languages, provides three assertion types directly analogous to CUJ signals:

| Contract type | CUJ analog | Example |
|---|---|---|
| **Precondition** (`require`) | Journey entry conditions | User is authenticated, workspace exists |
| **Postcondition** (`ensure`) | Success signal | File is saved, notification was sent |
| **Class invariant** | System-level signal | Data consistency maintained throughout journey |

The key operational insight: Eiffel's contract system supports **graduated assertion monitoring** — from preconditions-only (cheap, production-safe) to full invariant checking (expensive, test-only). This maps to the CUJ standard's two-tier signal cost model (feature-change tier vs. test-result tier).

### Operationalizing Observable Signals as Contracts

Observable signals ("player inventory changes," "plugin state updated") translate directly to postconditions:

```
-- After equip_item journey step:
ensure
    inventory.contains(item)
    equipped_set.has(item)
    old inventory.count = inventory.count  -- item moved, not duplicated
```

When contracts are monitored at runtime, every observable signal becomes a measurable signal — contract violations are logged, counted, and alertable. The cost is runtime overhead, managed via Eiffel's class-by-class monitoring controls.

### What This Upgrades

- **Observable → Measurable**: Any signal expressible as a postcondition becomes automatically verifiable at runtime.
- Runtime contracts also catch **signal regression** — when a previously-working signal stops firing due to code changes, the contract violation provides immediate feedback.

### Limits

Contracts require formal specification of expected behavior. They cannot express aesthetic judgments, user satisfaction, or emergent quality properties. Contracts are also synchronous — signals that depend on eventually-consistent state or long-running async processes need temporal logic extensions (see Section 6).

---

## 3. LLM-as-Judge for Qualitative Signal Evaluation

### State of the Art

The LLM-as-judge paradigm, formalized by MT-Bench and Chatbot Arena (Zheng et al., 2023), demonstrates that strong LLMs (GPT-4 class) achieve >80% agreement with human evaluators — the same level of inter-human agreement. This establishes a practical ceiling: **LLM judges are as reliable as individual human judges, but not as reliable as expert consensus.**

### Techniques for Converting Qualitative Signals

**Rubric decomposition** is the most important technique. Rather than asking an LLM to rate "feels intuitive" holistically, decompose into scored sub-criteria:

| Qualitative signal | Decomposed rubric criteria |
|---|---|
| "Feels intuitive" | (1) Action required is discoverable without docs, (2) Feedback appears within 200ms, (3) Error messages suggest corrective action, (4) No more than 3 steps to complete |
| "Low friction" | (1) No unnecessary confirmation dialogs, (2) Defaults are correct >80% of the time, (3) Undo is available for destructive actions |
| "Professional quality" | (1) Consistent formatting, (2) No spelling/grammar errors, (3) Tone matches target audience, (4) Information density appropriate for medium |

**Recursive Rubric Decomposition (RRD)** takes this further: each sub-criterion is itself decomposed until all leaves are binary (yes/no) or ordinal (1-5 scale) judgments. The LLM evaluates leaves, and scores aggregate upward. This reduces positional bias and scoring variance.

**DAG-structured evaluation** (criteria decomposition via directed acyclic graphs) assigns each sub-criterion to an independent LLM judge call, reducing cross-contamination between criteria. Each node evaluates one atomic dimension.

### Calibration Techniques

- **Few-shot anchoring**: Provide 3-5 scored examples per rubric level to calibrate the judge's scale.
- **Pairwise comparison**: More reliable than absolute scoring — "Is output A better than output B on criterion X?" achieves higher inter-rater agreement than "Rate output A from 1-5."
- **Multi-judge panels**: Run 3-5 independent judge calls and take majority vote or median score to reduce variance.
- **Logprob extraction**: Where available, extract logprobs for each possible score to get confidence intervals, not just point estimates.

### What This Upgrades

- **Qualitative → Observable**: Structured rubric evaluation converts "requires human judgment" into "requires LLM judgment with known agreement rate." The signal becomes instrumentable.
- **Observable → Measurable (with caveats)**: If rubric scores are logged and tracked over time, trend analysis and regression detection become automatable. However, the measurement has inherent noise (~20% disagreement with any individual human).

### Limits

LLM judges inherit the biases of their training data. They exhibit verbosity bias (preferring longer outputs), position bias (preferring first-listed options in pairwise comparison), and self-enhancement bias (preferring outputs from their own model family). Rubric decomposition mitigates but does not eliminate these.

More fundamentally: **decomposing "feels intuitive" into sub-criteria changes what is being measured.** The decomposed rubric measures structural proxies for intuitiveness, not intuitiveness itself. If the proxies are well-chosen, this is useful. If not, it's Goodhart's Law in action — optimizing the proxy diverges from the goal.

---

## 4. Chaos Engineering for Signal Verification

### Signal-Firing Verification Pattern

Chaos engineering's core question — "does the system behave correctly under failure?" — maps directly to CUJ signal verification: **do success signals fire (or correctly fail to fire) when the system is degraded?**

The pattern from Gremlin, LitmusChaos, and Netflix's Chaos Monkey:

```
1. Define steady-state hypothesis (signals X, Y, Z are all green)
2. Inject fault (network partition, high CPU, dependency failure, disk full)
3. Observe: do signals correctly transition?
   - Signals that should remain green: verify they do (resilience)
   - Signals that should go red: verify they do (detection fidelity)
   - Signals that should recover: verify recovery time (liveness)
4. Gate on SLO: abort experiment if blast radius exceeds threshold
```

### SLO-Based Signal Gating

Gremlin's SLO-based gating is directly applicable: define success signals as SLIs (service-level indicators), set SLO thresholds, and automatically halt experiments — or deployments — when signals degrade beyond acceptable bounds. This converts observable signals into deployment gates.

### What This Upgrades

- **Observable → Measurable**: Chaos experiments produce quantitative data — signal transition latency, false-negative rates under load, recovery times. These are CI-automatable.
- **Signal fidelity verification**: The meta-question "does our signal actually detect the condition it claims to detect?" is directly testable via fault injection.

### Limits

Chaos engineering verifies that signals fire under known failure modes. It cannot verify signals for failure modes that weren't anticipated. The technique tests detection fidelity, not signal correctness — it confirms the alarm rings but not whether the alarm's threshold is set correctly.

---

## 5. Automated Test Oracles: Differential and Metamorphic Testing

### The Oracle Problem

The test oracle problem — knowing what the correct output should be — is the core challenge for CUJ signals that lack fixed specifications. Two techniques address this by comparing outputs rather than checking against ground truth.

### Differential Testing

Run the same journey across two implementations (or versions) and flag divergences. For CUJ signals:

- **Version-to-version**: Does upgrading from v1.2 to v1.3 change which signals fire for the same journey?
- **Implementation-to-implementation**: Do two different backends produce the same signal outcomes for identical inputs?
- **Configuration-to-configuration**: Does the same journey succeed across different environments?

Divergence ≠ bug, but divergence is always investigatable. The technique converts "we don't know the right answer" into "we know when the answer changed."

### Metamorphic Testing

Define metamorphic relations — transformations of input that should produce predictable transformations of output. Over 750 papers have explored this since Chen (1998). For CUJ signals:

| Metamorphic relation | Signal expectation |
|---|---|
| Reorder independent journey steps | Same signals fire |
| Double the input data volume | Same signals fire (perhaps slower) |
| Add irrelevant context to a query | Same result quality signal |
| Translate UI text to another language | Same functional signals, possibly different quality signals |
| Retry a failed step | Signal transitions from red to green |

**LLMORPH** (Cho et al., 2025) applies metamorphic testing to LLM outputs specifically, defining 191 metamorphic relations for NLP tasks and running ~560K metamorphic tests. This is directly applicable to evaluating LLM-as-judge consistency.

### What This Upgrades

- **Observable → Measurable**: Metamorphic relations become automated regression tests. No ground truth needed — only consistency expectations.
- **Qualitative (partial)**: For signals like "response quality," metamorphic testing can verify that irrelevant perturbations don't change the judgment, even if the absolute judgment is subjective.

### Limits

Metamorphic testing verifies consistency, not correctness. A system that is consistently wrong passes all metamorphic tests. Differential testing requires a reference implementation, which may not exist for novel features. Both techniques detect regressions well but cannot validate initial correctness.

---

## 6. The Irreducible Verifiability Ceiling

### Formally Unspecifiable Properties

Some properties cannot be formally specified even in principle. Understanding where this ceiling lies prevents wasted effort and sets realistic expectations for signal automation.

**Rice's Theorem** establishes the fundamental limit: no general algorithm can decide whether a program satisfies a non-trivial semantic property. In practice, this means formal verification always requires restricting the problem — finite state spaces, decidable logics, bounded model checking.

But the CUJ verifiability ceiling is not primarily about computability. It's about **specifiability** — whether the property can be written down at all, even given infinite compute.

### Taxonomy of Irreducible Qualitative Signals

**Tier 1: Decomposable-to-measurable** (ceiling is engineering effort)
These signals feel qualitative but are actually composite measurable signals. "Responsive UI" decomposes to p95 latency < 100ms + no layout shift > 0.1 CLS + input-to-paint < 50ms. The ceiling is reached when all sub-criteria are enumerated and instrumented.

**Tier 2: Proxy-measurable** (ceiling is approximation quality)
These signals can be approximated by measurable proxies, but the approximation has irreducible error. "Intuitive navigation" can be proxied by task-completion rate, time-to-first-action, help-page visit rate, but no combination of proxies fully captures "intuitive." The ceiling is the gap between proxy accuracy and the actual property.

**Tier 3: Judgment-dependent** (ceiling is inter-rater agreement)
These signals require evaluative judgment with no objective ground truth. "Good writing quality," "appropriate tone," "creative solution." LLM-as-judge achieves ~80% human agreement, which is the human ceiling too. The irreducible floor is ~20% legitimate disagreement among qualified judges. These signals can be scored but not verified.

**Tier 4: Experiential** (ceiling is observation itself)
These signals are properties of the experience, not the output. "Feels delightful," "builds trust over time," "worth recommending to a friend." They depend on the observer's internal state, history, and context. They cannot be decomposed into output properties without changing what is measured. The only honest evaluation is asking the person having the experience.

### The Liveness Analogy

In formal verification, liveness properties ("something good eventually happens") are strictly harder than safety properties ("nothing bad ever happens"). Every liveness property requires a fairness assumption — that the system gets to make progress. Without fairness, liveness is unverifiable.

CUJ qualitative signals have an analogous structure:

| Formal verification | CUJ signals |
|---|---|
| Safety: bad state never reached | Measurable: failure condition never occurs |
| Liveness: good state eventually reached | Observable: success condition eventually detected |
| Fairness: assumption needed for liveness | Qualitative: judgment context needed for evaluation |

Just as liveness cannot be reduced to safety without losing the "eventually" requirement, qualitative signals cannot be reduced to measurable signals without losing the judgment component. The reduction changes the property.

### Practical Implications for the CUJ Gating Model

| Signal tier | Automation strategy | Realistic accuracy | Gate type |
|---|---|---|---|
| Measurable | PBT + contracts + CI | ~100% (deterministic) | Hard gate |
| Observable | Chaos + metamorphic + runtime contracts | >95% (instrumentation fidelity) | Hard gate |
| Decomposable qualitative | Rubric decomposition + LLM judge | ~90% (proxy quality) | Soft gate with human override |
| Judgment-dependent qualitative | LLM panel + calibration + trend tracking | ~80% (human agreement ceiling) | Advisory signal, not gate |
| Experiential qualitative | User research, NPS, session replay | ~60% (self-report reliability) | Human-only review |

**The key engineering decision**: which tier does each signal actually belong to? Many signals classified as "qualitative" in CUJ documents are actually Tier 1 (decomposable) or Tier 2 (proxy-measurable) — they just haven't been decomposed yet. The first step in upgrading a CUJ's verifiability is reclassifying each signal by tier.

---

## 7. Synthesis: An Upgrade Playbook

### Step 1: Classify Each Signal by Tier

For every qualitative signal in a CUJ, determine its tier (1-4) by asking: "Can I write a predicate that, given only the system's output and state, returns the same answer a human would?" If yes → Tier 1. If approximately → Tier 2. If only with judgment → Tier 3. If not even with judgment → Tier 4.

### Step 2: Apply Technique by Tier

| Tier | Primary technique | Supporting technique |
|---|---|---|
| 1 (Decomposable) | Rubric decomposition → PBT properties | Runtime contracts for regression |
| 2 (Proxy) | LLM-as-judge with calibrated rubric | Metamorphic testing for consistency |
| 3 (Judgment) | LLM panel with few-shot anchoring | Differential testing across versions |
| 4 (Experiential) | None — human evaluation only | Trend tracking on human ratings |

### Step 3: Verify Signal Fidelity

For Tiers 1-3, use chaos engineering patterns to verify that upgraded signals actually fire when they should. Inject faults → confirm signal transitions → measure detection latency.

### Step 4: Accept the Ceiling

For Tier 3-4 signals, accept that automation produces advisory scores, not definitive verdicts. Build the gating model with two tracks:
- **Hard gates**: Tiers 1-2, block on failure
- **Soft gates**: Tier 3, flag for review on score degradation, do not block
- **Dashboard-only**: Tier 4, surface for periodic human review, never gate

---

## Sources

- [Hypothesis: property-based testing for Python](https://hypothesis.works/articles/what-is-property-based-testing/)
- [QuickCheck State Machine: stateful PBT](https://dev.to/meeshkan/stateful-property-based-testing-with-quickcheck-state-machine-4mp5)
- [fast-check: PBT framework for JavaScript/TypeScript](https://fast-check.dev/)
- [proptest-state-machine for Rust](https://blog.nikosbaxevanis.com/2025/01/10/state-machine-testing-proptest/)
- [LLM-based property-based test generation](https://arxiv.org/abs/2506.18315)
- [MT-Bench and Chatbot Arena: LLM-as-judge](https://arxiv.org/abs/2306.05685)
- [Decomposed criteria-based evaluation of LLM responses](https://arxiv.org/html/2509.16093v1)
- [Rubric generation for LLM reward modeling (RRD)](https://www.emergentmind.com/papers/2602.05125)
- [LLM-as-a-Judge guide — Confident AI](https://www.confident-ai.com/blog/why-llm-as-a-judge-is-the-best-llm-evaluation-method)
- [LLM-as-a-Judge 2026 guide](https://labelyourdata.com/articles/llm-as-a-judge)
- [Metamorphic testing — Wikipedia](https://en.wikipedia.org/wiki/Metamorphic_testing)
- [LLMORPH: metamorphic testing of LLMs (Cho et al., 2025)](https://valerio-terragni.github.io/assets/pdf/cho-ase-2025.pdf)
- [Intramorphic testing (Rigger, 2022)](https://arxiv.org/pdf/2210.11228)
- [Design by Contract — Eiffel](https://www.eiffel.org/doc/eiffel/ET-_Design_by_Contract_(tm),_Assertions_and_Exceptions)
- [Design by Contract in Ada/SPARK](https://learn.adacore.com/courses/intro-to-ada/chapters/contracts.html)
- [Chaos engineering — Gremlin](https://www.gremlin.com/chaos-engineering)
- [Chaos engineering tools comparison 2025](https://steadybit.com/blog/top-chaos-engineering-tools-worth-knowing-about-2025-guide/)
- [LitmusChaos and chaos engineering in the wild](https://arxiv.org/html/2505.13654v1)
- [Rice's Theorem and program analysis limits](https://www.alphanome.ai/post/rice-s-theorem-understanding-the-limits-of-program-analysis)
- [Safety and liveness properties — Alpern & Schneider](https://www.cs.cornell.edu/fbs/publications/RecSafeLive.pdf)
- [Recognizing safety and liveness (Wikipedia)](https://en.wikipedia.org/wiki/Safety_and_liveness_properties)

<!-- flux-research:complete -->
