# False Block Cost Modeling for Quality Gates

How CI/CD feature flag rollout, game QA quality bars, and SPC frameworks model the cost of false positives in quality gates -- and what optimal gate tuning looks like when false blocks cost agent tokens.

## 1. Feature Flag Progressive Rollout: Premature Passage vs. False Block

### LaunchDarkly Guarded Rollouts

LaunchDarkly's [guarded rollouts](https://launchdarkly.com/docs/home/releases/guarded-rollouts) represent the state of the art in flag-gated deployment. The system progressively increases traffic to a new variation while monitoring selected metrics for regressions. If sequential testing detects a statistically significant negative impact, the rollout pauses and sends a notification.

The implicit cost model:
- **Premature passage cost**: Degraded experience hits an increasing percentage of users. Because rollout is monotonic (a user's variation changes only once), premature passage at 50% is catastrophically worse than at 5%.
- **False block cost**: Rollout stalls at a low percentage. The new feature is delayed, but no users are harmed. The cost is opportunity cost (delayed value delivery) plus engineering time investigating a phantom regression.

LaunchDarkly's design reveals a strong asymmetry: they heavily favor false blocks over premature passage. The default behavior is to pause on any detected regression, requiring manual resumption. This makes sense for user-facing products where a bad deploy can erode trust.

### Facebook Gatekeeper

Facebook's [Gatekeeper system](https://sigops.org/s/conferences/sosp/2015/current/2015-Monterey/printable/008-tang.pdf) (Tang et al., SOSP 2015) enables multi-phase rollout without code changes: engineer-only -> 1% employees -> 10% employees -> 100% employees -> 5% regional users -> general availability. The system processes billions of checks per second across hundreds of thousands of frontend servers.

The key insight: Gatekeeper's rollout phases are manually gated, not metric-gated. Each phase transition requires human judgment. This sidesteps false positive risk entirely at the gate level by making every gate a human decision point. The cost model is implicit: human review time per phase transition is the false block cost, and it is considered acceptable because the alternative (automated premature passage at Facebook scale) is existentially risky.

### Unleash Gradual Rollout

[Unleash](https://docs.getunleash.io/feature-flag-tutorials/use-cases/gradual-rollout) uses normalized MurmurHash of user IDs for sticky, consistent percentage-based rollout. The system guarantees that a user in the 10% cohort remains in the 20% cohort -- monotonic inclusion.

Unleash also implements [kill switches](https://www.getunleash.io/blog/rolling-deployment-vs-kill-switch) as a distinct concept from gradual rollout: features can be instantly disabled under load as a graceful degradation strategy. This separates the rollout gate (gradual, forward-only) from the safety gate (instant, backward).

### Implications for Agent Token Gates

Feature flag frameworks universally favor false blocks over premature passage because:
1. Premature passage costs scale with user population (O(n) users affected)
2. False block costs are fixed (one team delayed)
3. Rollback from premature passage is expensive and sometimes impossible (data corruption, user trust)

**For agent gates, the calculus inverts.** A false block doesn't delay a human team -- it forces an agent to re-plan, rebuild context, and retry. The cost is measured in tokens, and it compounds quadratically (see Section 6). There is no "team" absorbing the delay; the system pays directly in compute.

## 2. Game QA Quality Bars: Ship Gates and Severity Tiering

### Bug Severity Classification

AAA game studios use a universal severity taxonomy for ship gating:

| Severity | Description | Ship Gate Effect |
|----------|-------------|------------------|
| **A / Blocker** | Crashes, data loss, certification failures | Hard block: zero tolerance |
| **B / Critical** | Major functionality broken, playable with workarounds | Soft block: must-fix list, exception requires sign-off |
| **C / Major** | Noticeable issues, minor functionality gaps | Tracked, not blocking |
| **D / Minor** | Cosmetic, polish, typos | Backlog only |

The critical insight is the **certification gate**: platform certification (Sony TRC, Microsoft XR, Nintendo Lotcheck) is a hard external gate with concrete costs for failure. Re-submission fees, marketing window misses, and launch date slips make certification false negatives (passing with a cert-failing bug) catastrophically expensive. Studios therefore over-invest in cert compliance, accepting false blocks (delaying for suspected cert issues that turn out to be acceptable).

### The Cosmetic Issue Problem

Modern AAA games routinely have [100,000+ bugs in their tracking systems](https://www.quora.com/How-are-so-many-issues-bypassing-AAA-QA-game-testing). The quality bar problem is not "are there bugs" but "which bugs block ship." Studios that set quality bars too tight (blocking on C-severity cosmetic issues) miss launch windows. Studios that set them too loose ship broken games and face review score damage.

The optimal strategy is **severity-filtered gating**: hard gates on A/B bugs only, soft gates (human review required) on C bugs in critical paths, no gate on D bugs. This mirrors the SPC concept of inspection levels (Section 3).

### Application to Agent Quality Gates

Game QA teaches that **gate selectivity matters more than gate strictness**. A gate that blocks on everything (including cosmetic issues) is worse than a gate that blocks on nothing, because the false block cost of re-running QA passes across the entire bug population dominates. The optimal gate is highly selective: zero tolerance for crash-equivalent failures, loose tolerance for cosmetic issues.

For agent token gates: a linter warning that triggers a full re-plan is the equivalent of blocking ship on a typo. The gate must distinguish between "output is wrong" (hard block) and "output style is suboptimal" (soft pass with annotation).

## 3. SPC Acceptance Sampling: Producer's Risk and Consumer's Risk

### The Two-Risk Framework

Statistical Process Control acceptance sampling ([ANSI/ASQ Z1.4](https://asq.org/quality-resources/z14-z19), [MIL-STD-1916](https://www.statgraphics.com/blog/mil-std-1916-and-ansi-z1.4)) provides the most rigorous framework for gate calibration through two explicit risk parameters:

- **Producer's risk (alpha)**: Probability of rejecting a good lot. Conventionally set at 5% at the Acceptable Quality Level (AQL). This is the false block rate.
- **Consumer's risk (beta)**: Probability of accepting a bad lot. Conventionally set at 10% at the Rejectable Quality Level (RQL/LTPD). This is the false pass rate.

The [Operating Characteristic (OC) curve](https://www.6sigma.us/six-sigma-in-focus/operating-characteristic-curve/) maps every possible true defect rate to a probability of acceptance, creating a complete picture of gate behavior across the quality spectrum.

### Switching Rules: Adaptive Gate Sensitivity

ANSI Z1.4 defines three inspection levels with [automatic switching rules](https://bookdown.org/lawson/an_introduction_to_acceptance_sampling_and_spc_with_r26/attribute-sampling-plans.html):

- **Normal inspection** (Level II): Default. Balanced producer/consumer risk.
- **Tightened inspection** (Level III): Triggered after 2 consecutive rejected lots. Larger sample, lower acceptance number. Protects consumer.
- **Reduced inspection** (Level I): Triggered after 5 consecutive accepted lots with good history. Smaller sample. Reduces producer cost.

The switching rules create an adaptive system that automatically tightens when quality degrades and loosens when quality is consistently good. This is directly analogous to what agent quality gates should do: tighten after failures (increase scrutiny), loosen after a track record of success (reduce token overhead).

### MIL-STD-1916: From Detection to Prevention

[MIL-STD-1916](https://www.statgraphics.com/blog/mil-std-1916-and-ansi-z1.4) shifted DoD procurement from acceptance sampling (detection) to statistical process control (prevention). The standard endorses SPC programs over prescribed sampling, recognizing that inspecting quality in is more expensive than building quality in.

**Agent gate implication**: Rather than inspecting every agent output (expensive sampling), invest in process quality (better prompts, better context, better tools) and use lightweight verification gates. This maps to the distinction between "check every token of output" and "check the final artifact against acceptance criteria."

### Concrete OC Curve Parameters for Agent Gates

Applying SPC conventions to agent quality gates:

| Parameter | SPC Convention | Agent Gate Analog |
|-----------|---------------|-------------------|
| AQL | 1-2.5% defective | Target false-positive rate of the gate itself |
| LTPD | 5-10% defective | Maximum acceptable defect rate in agent output |
| Producer's risk (alpha) | 5% at AQL | 5% chance of rejecting good agent work |
| Consumer's risk (beta) | 10% at LTPD | 10% chance of accepting bad agent work |
| Sample size (n) | From tables | Number of checks per gate evaluation |

The key SPC insight: **you cannot reduce both risks simultaneously without increasing sample size (cost).** In agent terms: you cannot make a gate both more sensitive to real bugs and less likely to false-block without running more checks -- which costs more tokens.

## 4. CI/CD Gate Tuning at Scale

### Google TAP: Flaky Test Quarantine

Google's [Test Automation Platform (TAP)](https://research.google.com/pubs/archive/45861.pdf) handles 50,000+ changes and 4 billion test cases daily. Their flaky test strategy reveals the economic reasoning behind gate tuning:

- **Automatic retry**: Tests that fail are re-run up to 3 times. A failure is reported only if all 3 attempts fail. This trades 3x compute cost for exponential reduction in false block rate (a test with 10% flake rate has only 0.1% false block rate after 3 retries).
- **Quarantine**: Tests exceeding a flakiness threshold are automatically removed from the critical path and a bug is filed. This is the nuclear option for chronic false blockers.
- **Batch splitting**: TAP batches changes for efficiency but automatically splits failing batches into individual changes for isolation. This is an adaptive sample size increase triggered by failure.

[Google's SWE book](https://abseil.io/resources/swe-book/html/ch23.html) states the core principle: "If a test is routinely failing but still being ignored, it's worse than no test at all -- it's actively training engineers to ignore test signals."

### Meta Probabilistic Flakiness Score (PFS)

Meta's [Probabilistic Flakiness Score](https://engineering.fb.com/2020/12/10/developer-tools/probabilistic-flakiness/) (Memon & Gao, 2020) provides the most sophisticated false-positive-aware gate model in industry:

- PFS measures how likely a test is to fail given it **could have passed** on the same code version. This isolates flakiness from genuine failure.
- Uses Bayesian inference (Stan probabilistic programming) to estimate test flakiness from observed results.
- The key insight: "All real-world tests are flaky to some extent, so the right question is not **whether** a test is flaky, but **how flaky** it is."

The PFS directly quantifies false block probability per gate check. A gate with a PFS of 0.15 will false-block 15% of the time. The cost of that false block (developer time investigating, re-running CI) is the producer's risk made concrete.

Meta's [Presubmit Rescue](https://dl.acm.org/doi/10.1145/3643656.3643896) system automatically ignores flaky test executions in presubmit, removing them from the blocking path. This is the CI/CD equivalent of SPC's switching to reduced inspection.

### Netflix Kayenta: Statistical Canary Analysis

Netflix's [Kayenta](https://netflixtechblog.com/automated-canary-analysis-at-netflix-with-kayenta-3260bc7acc69) system (integrated with Spinnaker) runs statistical tests on user-specified metrics and returns an aggregate score for rollout/rollback decisions.

Netflix explicitly states the cost calculus: "A false positive test unnecessarily interrupts the software release process, reducing the velocity of software delivery and sending developers looking for bugs that do not exist." They strictly control false positive probability because Kayenta operates in a semi-automated pipeline where false positives have concrete velocity costs.

The [canary judge](https://spinnaker.io/docs/guides/user/canary/judge/) uses configurable thresholds for marginal vs. pass vs. fail scores, creating a three-state gate (pass/review/block) rather than binary pass/fail. This middle state ("marginal") is the practical solution to gate sensitivity: uncertain results trigger human review rather than automated block.

### Synthesis: CI/CD Gate Tuning Patterns

| System | False Block Mitigation | Cost Model |
|--------|----------------------|------------|
| Google TAP | Retry 3x, quarantine chronic flakes | Compute cost of retries < developer time investigating false failures |
| Meta PFS | Bayesian flakiness scoring, presubmit rescue | Probabilistic: each test has quantified false block probability |
| Netflix Kayenta | Three-state gate (pass/marginal/fail) | False positives measured in release velocity |
| Spinnaker | Configurable score thresholds per metric | Aggregate scoring avoids single-metric false triggers |

## 5. A/B Testing Guardrail Metrics: Gate Sensitivity with Noisy Measurement

### The Multiple Testing Problem in Guardrails

[Airbnb's experimentation guardrails](https://medium.com/airbnb-engineering/designing-experimentation-guardrails-ed6a976ec669) (Xifara et al.) provide the clearest quantification of how gate count affects false block rate:

| Number of Guardrail Metrics | False Alert Rate (AA Test) |
|----------------------------|---------------------------|
| 3 | 14% |
| 10 | 40% |
| 25 | 73% |
| 50 | 92% |

At alpha=0.05 per metric, the probability of at least one false alert follows 1-(1-alpha)^n. With 50 guardrails, you false-block 92% of the time even when nothing is wrong.

Airbnb's practical solution: out of thousands of monthly experiments, guardrails trigger approximately 25 for review. Of those, 80% roll out after stakeholder discussion, and about 5 experiments per month are paused. This implies an ~80% false positive rate among triggered guardrails, which is acceptable because the review cost is human time, not automated retry.

### Spotify's Risk-Aware Framework

[Spotify's framework](https://engineering.atspotify.com/2024/03/risk-aware-product-decisions-in-a-b-tests-with-multiple-metrics) (Schultzberg et al., 2024) makes a counterintuitive but statistically sound distinction:

- **False positive rates should NOT be adjusted** for the number of guardrail metrics
- **False negative rates (power) MUST be corrected** for the number of guardrails

The structural reason: for a ship decision, all guardrails must pass simultaneously. The chance of incorrectly passing at least one guardrail (false positive = shipping something bad) is already individually controlled. But the chance of incorrectly failing at least one guardrail (false negative = blocking something good) compounds with each additional metric.

This is the **exact inversion** of the traditional multiple testing correction (Bonferroni), which adjusts alpha downward to control family-wise error rate. Spotify argues that for guardrail metrics specifically, you should adjust power upward instead.

### Sensitivity vs. Gate Count Tradeoff

The [Statsig analysis](https://www.statsig.com/blog/what-are-guardrail-metrics-in-ab-tests) identifies a fundamental constraint: an experiment's sample size is typically powered for the primary metric, but a guardrail's variance might be entirely different. You might detect 1% changes in the primary metric but only 10-30% changes in a guardrail. This means many guardrails are effectively decoration -- they can only catch catastrophic regressions, not subtle ones.

### Application to Agent Quality Gates

The guardrail pattern maps directly to multi-check agent gates:

- Each quality check (lint, type check, test pass, style check, semantic review) is a guardrail metric
- Each check has its own false positive rate
- The compound false block rate follows 1-(1-alpha_i)^n for independent checks

**If an agent gate runs 10 checks at 5% individual false positive rate, it false-blocks 40% of the time.** This is the fundamental problem with multi-gate agent pipelines. Each additional "safety check" that seems individually reasonable compounds into an aggregate gate that blocks more often than it passes.

Spotify's insight applies: don't reduce individual gate sensitivity (that increases false pass risk). Instead, increase gate power by running better checks, not more checks.

## 6. Token Cost Compounding of Gate False Positives in LLM Agent Loops

### The Quadratic Cost Curve

The [exe.dev analysis](https://blog.exe.dev/expensively-quadratic) ("Expensively Quadratic: the LLM Agent Cost Curve") identifies the fundamental economic trap:

Because LLMs are stateless, every turn re-processes the entire conversation history. In a multi-turn agent loop:
- Turn 1: 100 input tokens + 100 output = 200 total context
- Turn 2: 200 history + 100 new input + 100 output = 400
- Turn 3: 400 history + 100 new + 100 output = 600
- ...
- Turn N: cost grows as O(N^2) in total tokens consumed

A Reflexion loop running for 10 cycles consumes **50x the tokens** of a single linear pass.

### False Block as a Quadratic Cost Multiplier

When a quality gate false-blocks, the agent must:
1. **Process the rejection signal**: Read the gate output, parse the error (additional input tokens)
2. **Re-plan**: Generate a new approach, often re-reading the original context (full context re-processing)
3. **Re-execute**: Run tools again, generate new code (additional tool calls + output tokens)
4. **Re-check**: Submit to the gate again (another gate evaluation)

Each false block adds at minimum 2 additional turns (re-plan + re-execute), and because context grows monotonically, each retry is more expensive than the last. The [MCP context tax analysis](https://www.mmntm.net/articles/mcp-context-tax) quantifies this: a 50,000-token tool output at Turn 1 is re-processed on every subsequent turn, so 5 follow-up questions pay that cost 6 times.

### Empirical Token Consumption Data

The [Tokenomics paper](https://arxiv.org/html/2601.14470v1) (Abuduweili et al., 2025) found that in multi-agent software engineering:
- **59.4% of tokens** are consumed in the Code Review stage (verification/gating), not code generation
- Input tokens dominate overall consumption (the "communication tax")
- Different development stages exhibit unique tokenomic profiles

The [SWE-bench analysis](https://openreview.net/forum?id=1bUeVB3fov) found:
- Token usage has **large variance across runs**: some runs use 10x more tokens than others for the same task
- pass@1 vs. pass@3 (retry budget of 3) shows typical improvement from 76% to 81% -- meaning ~6% of failures are recovered by retry, but at 3x token cost
- Resolving a single real-world scenario requires approximately **90 tool calls and 1M tokens**

### The False Block Cost Formula

For an agent system with:
- `C_base`: base cost of a single pass (tokens)
- `p_fb`: false block probability per gate evaluation
- `n_gates`: number of gates
- `r_max`: maximum retry budget
- `k`: context growth factor per retry (typically 1.3-2.0x due to error logs, re-planning tokens)

The expected token cost per task is:

```
E[cost] = C_base * sum_{i=0}^{r_max} (p_compound^i * k^i)

where p_compound = 1 - product_{j=1}^{n_gates} (1 - p_fb_j)
```

For concrete numbers:
- C_base = 100K tokens
- p_fb = 5% per gate, 5 gates -> p_compound = 22.6%
- k = 1.5 (50% context growth per retry)
- r_max = 3

```
E[cost] = 100K * (1 + 0.226*1.5 + 0.226^2*2.25 + 0.226^3*3.375)
        = 100K * (1 + 0.339 + 0.115 + 0.039)
        = 100K * 1.493
        = 149.3K tokens
```

A 22.6% compound false block rate inflates expected cost by ~49%. At $3/M tokens (Claude Sonnet cached input), that is $0.15 per task wasted on false blocks. Across 1000 tasks/day, $150/day or $54,750/year in pure waste.

### Catastrophic Loops

The [unbounded agent execution analysis](https://www.singhspeak.com/blog/unbounded-agent-execution-can-result-in-denial-of-service-attacks) identifies the worst case: agents can get trapped in crafted cyclic loops that force excessive, redundant reasoning steps. Without backpressure (retry budgets, circuit breakers), the planner interprets tool failures as a reason to increase effort rather than stop -- creating a positive feedback loop where cost grows without bound.

## 7. Optimal Gate Tuning for Agent Token Economies

### Design Principles

Synthesizing across all six domains:

**Principle 1: Severity-filtered gating (from Game QA)**
Not all checks deserve gate status. Hard-block only on crash-equivalent failures (wrong output, infinite loops, security violations). Soft-pass with annotation on style, convention, and cosmetic issues. Never hard-block on linter warnings.

**Principle 2: Adaptive sensitivity (from SPC switching rules)**
Tighten gates after failures (increase scrutiny for the next N attempts). Loosen gates after consistent success (reduce check depth, skip redundant validations). This maps directly to ANSI Z1.4's normal/tightened/reduced inspection levels.

**Principle 3: Minimize gate count, maximize gate power (from Spotify)**
Compound false block rate grows as 1-(1-alpha)^n. Five 5%-FP gates compound to 22.6% false block rate. Three 3%-FP gates compound to 8.7%. Fewer, better gates always dominate more, weaker gates. Invest in gate quality (lower individual false positive rate) rather than gate quantity.

**Principle 4: Three-state gates (from Netflix Kayenta)**
Replace binary pass/fail with pass/marginal/fail. Marginal results trigger lightweight review (re-check with different parameters, ask for human input) rather than full re-plan. This avoids the quadratic cost of a full retry for uncertain signals.

**Principle 5: Probabilistic gating (from Meta PFS)**
Assign each gate check a known false positive probability. Use Bayesian inference on gate history to calibrate. When a gate fails, weight the response by the gate's historical reliability: a gate with 20% FP rate should trigger investigation, not automatic retry.

**Principle 6: Retry budgets with backpressure (from Google TAP)**
Cap retries at 2-3 attempts. After retry budget exhaustion, escalate to human rather than continuing to burn tokens. Each retry should be cheaper than the previous (targeted re-check, not full re-execution).

### Recommended Gate Architecture

```
Agent Output
    |
    v
[Severity Filter] -- cosmetic issues -> annotate, pass through
    |
    v (critical issues only)
[Fast Gate] -- type errors, syntax, crash-on-run -> hard block (retry 1x)
    |
    v (pass)
[Semantic Gate] -- correctness check, test execution -> three-state
    |         |         |
    v         v         v
  PASS    MARGINAL    FAIL
    |         |         |
    v         v         v
  Ship   Targeted    Re-plan
         re-check    (budget
         (cheap)     permitting)
```

### Gate Tuning Parameters

| Parameter | Recommended Value | Rationale |
|-----------|------------------|-----------|
| Max gates in critical path | 2-3 | Compound FP rate < 15% |
| Individual gate FP target | 3-5% | Matches SPC producer's risk convention |
| Retry budget | 2-3 attempts | Google TAP pattern; diminishing returns beyond 3 |
| Context growth budget | 1.5x per retry max | Prune error logs, don't append full trace |
| Severity levels | 3 (block/review/annotate) | Game QA A/B/C mapping |
| Switching threshold (tighten) | 2 consecutive failures | ANSI Z1.4 convention |
| Switching threshold (loosen) | 5 consecutive passes | ANSI Z1.4 convention |

### Economic Threshold

A gate is worth adding if and only if:

```
(defect_catch_rate * cost_of_escaped_defect) > (false_block_rate * cost_of_false_block)
```

Where cost_of_false_block in agent systems = `C_retry * k^retry_depth` (quadratic in context size).

For a gate with 5% FP rate and 80% defect catch rate, with retry cost of 150K tokens and escaped defect cost of 500K tokens (full task re-execution):

```
0.80 * 500K = 400K benefit
0.05 * 150K = 7.5K cost
Ratio: 53:1 -- clearly worth adding
```

But for a gate with 15% FP rate and 20% defect catch rate (a noisy cosmetic checker):

```
0.20 * 500K = 100K benefit
0.15 * 150K = 22.5K cost
Ratio: 4.4:1 -- marginal, and worsens with retry depth
```

At retry depth 3 with k=1.5, the false block cost becomes 0.15 * 150K * 1.5^2 = 50.6K, making the ratio 2:1 -- barely worth it, and likely net negative when accounting for the compound effect with other gates.

## Sources

- [LaunchDarkly Guarded Rollouts](https://launchdarkly.com/docs/home/releases/guarded-rollouts)
- [Facebook Holistic Configuration Management (SOSP 2015)](https://sigops.org/s/conferences/sosp/2015/current/2015-Monterey/printable/008-tang.pdf)
- [Unleash Gradual Rollout](https://docs.getunleash.io/feature-flag-tutorials/use-cases/gradual-rollout)
- [Unleash Kill Switches vs Rolling Deployment](https://www.getunleash.io/blog/rolling-deployment-vs-kill-switch)
- [ANSI/ASQ Z1.4 Sampling Standards](https://asq.org/quality-resources/z14-z19)
- [MIL-STD-1916 and ANSI Z1.4 Comparison](https://www.statgraphics.com/blog/mil-std-1916-and-ansi-z1.4)
- [Attribute Sampling Plans (R textbook)](https://bookdown.org/lawson/an_introduction_to_acceptance_sampling_and_spc_with_r26/attribute-sampling-plans.html)
- [Operating Characteristic Curve Guide](https://www.6sigma.us/six-sigma-in-focus/operating-characteristic-curve/)
- [Google TAP: Taming Google-Scale Continuous Testing](https://research.google.com/pubs/archive/45861.pdf)
- [Google: Flaky Tests and How We Mitigate Them](https://testing.googleblog.com/2016/05/flaky-tests-at-google-and-how-we.html)
- [Software Engineering at Google (Ch. 23: CI)](https://abseil.io/resources/swe-book/html/ch23.html)
- [Meta: Probabilistic Flakiness](https://engineering.fb.com/2020/12/10/developer-tools/probabilistic-flakiness/)
- [Presubmit Rescue: Automatically Ignoring Flaky Test Executions](https://dl.acm.org/doi/10.1145/3643656.3643896)
- [Netflix: Automated Canary Analysis with Kayenta](https://netflixtechblog.com/automated-canary-analysis-at-netflix-with-kayenta-3260bc7acc69)
- [Spinnaker Canary Judge](https://spinnaker.io/docs/guides/user/canary/judge/)
- [Airbnb: Designing Experimentation Guardrails](https://medium.com/airbnb-engineering/designing-experimentation-guardrails-ed6a976ec669)
- [Spotify: Risk-Aware Product Decisions in A/B Tests](https://engineering.atspotify.com/2024/03/risk-aware-product-decisions-in-a-b-tests-with-multiple-metrics)
- [Statsig: What Are Guardrail Metrics](https://www.statsig.com/blog/what-are-guardrail-metrics-in-ab-tests)
- [Expensively Quadratic: the LLM Agent Cost Curve](https://blog.exe.dev/expensively-quadratic)
- [The MCP Tax: Hidden Costs of Model Context Protocol](https://www.mmntm.net/articles/mcp-context-tax)
- [Tokenomics: Quantifying Where Tokens Are Used in Agentic SE](https://arxiv.org/html/2601.14470v1)
- [SWE-bench Agent Token Consumption Analysis](https://openreview.net/forum?id=1bUeVB3fov)
- [Unbounded Agent Execution as DoS](https://www.singhspeak.com/blog/unbounded-agent-execution-can-result-in-denial-of-service-attacks)

<!-- flux-research:complete -->
