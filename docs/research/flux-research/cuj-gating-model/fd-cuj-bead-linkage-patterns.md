# CUJ-Bead Linkage Patterns: Scoped, Falsifiable Gate Verification

**Research question:** How should the causal link between a bead (work item) and its CUJ success signals be structured so gate verification is scoped, falsifiable, and not trivially satisfied by unrelated changes?

## Problem Statement

A bead produces code changes. A CUJ gate checks whether a success signal holds. The naive linkage — "bead B is verified by CUJ gate G" — has three failure modes:

1. **Trivial satisfaction.** G passes because the system already worked before B's changes. The gate adds no information about whether B is correct.
2. **False coupling.** G fails because of an unrelated regression. The gate blocks B without cause.
3. **Scope inflation.** G covers so many behaviors that it is insensitive to the specific change B introduces. It passes whether B's feature works or not.

All three reduce gate signal to noise. The research below surveys six domains for structural patterns that prevent these failure modes.

---

## 1. Requirements Traceability Matrices (DO-178C, ISO 26262)

### Core discipline: Bidirectional, per-requirement linking

DO-178C mandates bidirectional traceability: every requirement traces down to implementing code and verifying test cases; every test traces back to the requirement it validates. The RTM is not optional annotation — it is a certification artifact audited by DERs. ISO 26262 mirrors this with ASIL-graded depth: higher automotive safety integrity levels demand stricter bidirectional coverage.

### Key structural constraints

- **1:1 preferred, 1:N explicit.** When a single test case satisfies multiple requirements, each link must be separately justified. The intent is that removing the test should leave exactly the linked requirements uncovered. A test that "happens to exercise" a requirement without an explicit link does not count as verification.
- **Derived requirements must be traced upward.** If implementation introduces a requirement not in the spec (a "derived requirement"), it must be traced to a parent or flagged as new scope. This prevents phantom coverage where code is tested but has no traceable purpose.
- **Structural coverage analysis as a cross-check.** Requirements-based test coverage answers "did we test what we intended?" Structural coverage (statement, decision, MC/DC at DAL A) answers "did we test what we built?" The gap between these two reveals dead code, untested paths, or requirements not reflected in tests.
- **Coverage completeness is per-requirement, not aggregate.** A 95% aggregate coverage score is meaningless if a specific requirement has 0% coverage. DO-178C Section 6.4.4.1 requires analysis at the individual requirement level.

### Applicable pattern for bead-CUJ linkage

**Each bead must declare which CUJ signals it claims to affect, and each CUJ signal must trace back to the beads that justify its inclusion in the gate set.** A CUJ gate that passes but is not linked to the bead under verification provides zero signal. The link must be explicit and auditable, not inferred from "the test ran."

**Anti-pattern:** A single integration test that exercises a full user journey is linked to 15 beads. If it passes, which of the 15 are verified? If it fails, which is broken? This is the DO-178C "one test covering many requirements" problem — each link must be independently justifiable.

---

## 2. BDD/Gherkin Scenario Scoping

### Core discipline: One scenario, one behavior, one rule

The Cucumber team's BRIEF principle (Business-language, Real data, Intention-revealing, Essential, Focused) constrains scenarios to illustrate exactly one rule. The key anti-patterns that destroy gate sensitivity:

- **Scope inflation via multi-When scenarios.** A scenario with multiple When-Then pairs tests multiple behaviors. When one fails, the failure is ambiguous. When all pass, the passing of later Thens does not prove the earlier Whens are correct in isolation.
- **Incidental detail.** Steps that set up context not directly related to the rule under test add fragility without information. Changes to incidental systems break the scenario without revealing anything about the target behavior.
- **Scenario length as a smell.** The Cucumber team recommends five lines or fewer. Longer scenarios are correlated with multiple embedded behaviors and reduced readability by product owners.

### Structural constraint: The "remove and check" test

A well-scoped scenario has the property: if you remove the feature it tests, the scenario fails. If you can remove the feature and the scenario still passes (because it was testing something else incidentally), the scenario is not scoped to that feature.

### Applicable pattern for bead-CUJ linkage

**Each CUJ gate signal linked to a bead must have the "remove and check" property: reverting the bead's changes should cause the gate to fail.** If reverting the bead's code changes does not change the gate outcome, the gate is not actually verifying the bead. This is the falsifiability criterion.

**Corollary: CUJ signals should be decomposed to the granularity where this property holds.** A coarse "user can complete checkout" signal linked to a bead that fixes a discount calculation is too broad — it passes whether the discount works or not. A scoped signal "discount is applied correctly for coupon code X" has the remove-and-check property.

---

## 3. Change Impact Analysis (Blast Radius Estimation)

### Core discipline: Compute which signals a change can plausibly affect

Change impact analysis uses call graphs, dependency graphs, and module coupling metrics to determine the "blast radius" of a code change — which downstream behaviors could be affected.

### Techniques

- **Call graph traversal.** Given changed functions, compute the transitive closure of callers. Any CUJ whose execution path includes a caller of a changed function is within the blast radius. Tools like Blast Radius (blast-radius.dev) and drift (`drift test-topology affected`) automate this for specific ecosystems.
- **Module coupling heatmaps.** High coupling between modules means changes in one are likely to affect the other. CUJ signals in highly-coupled modules should be included in the gate set even if the direct call graph doesn't reach them.
- **Confidence-scored impact maps.** Rather than binary "affected/not affected," some systems score the likelihood that a change affects a test, based on call depth, data flow distance, and historical co-failure rates.

### Two-directional scoping

Impact analysis serves both directions of the scoping problem:

1. **Inclusion:** Which CUJ signals should be in the gate for this bead? (Those within the blast radius.)
2. **Exclusion:** Which CUJ signals should NOT be in the gate? (Those outside the blast radius — their failure is not attributable to this bead.)

### Applicable pattern for bead-CUJ linkage

**The gate set for a bead should be the intersection of (a) CUJ signals the bead claims to affect and (b) CUJ signals within the computed blast radius of the bead's changed files.** Claim without blast radius overlap is suspicious (claiming to fix something without touching related code). Blast radius without claim is a regression risk that should be monitored but not gated on (the bead didn't intend to affect it, so failure is an unrelated regression, not a bead verification failure).

---

## 4. Mutation Testing as Gate Validation Meta-Test

### Core discipline: Verify that gates actually catch regressions

Mutation testing (PIT for JVM, Stryker for JS/TS/.NET) introduces small deliberate faults ("mutants") into production code and checks whether the test suite detects them. A surviving mutant means the test suite has a gap — a real bug in that location could go undetected.

### Quality gate structure

- **Mutation score = killed / (total - equivalent).** The percentage of non-equivalent mutants caught by tests.
- **Risk-based thresholds.** Payment processing: 95%+. Logging utilities: 70%. The threshold reflects the cost of an undetected regression, not a universal standard.
- **Break threshold in CI.** Stryker exits with code 1 if the score drops below the "break" threshold. PIT can similarly fail the build. This is the meta-gate: the gate on whether the gates themselves work.
- **Incremental mutation testing.** Full mutation runs are expensive. For PR-level gating, tools like PIT's `withHistory` and Stryker's incremental mode only mutate changed lines, making CI integration feasible.

### The key insight for CUJ gates

Mutation testing answers: "If I introduce a bug in the code this bead changed, does the linked CUJ gate catch it?" If the answer is no, the gate is trivially satisfiable — it passes whether the bead's code is correct or not. This is the operational definition of the "trivial satisfaction" failure mode.

### Applicable pattern for bead-CUJ linkage

**Periodically validate bead-CUJ links by mutating the bead's changed lines and checking whether the linked CUJ gates detect the mutation.** Gates with low kill ratios against mutations in their linked bead's code are not actually verifying the bead — they should be tightened or replaced.

**Implementation sketch:**
1. For a completed bead, identify its changed lines.
2. Generate mutants in those lines (operator replacement, boundary changes, null injection).
3. Run the linked CUJ gates against each mutant.
4. Report the kill ratio. If below threshold, the linkage is suspect.

This is not a gate on the bead itself — it is a gate on the gate. It answers whether the verification structure has the sensitivity to catch real regressions.

---

## 5. Feature Flag Experimentation: Isolating Treatment Effects

### Core discipline: Attribution via controlled exposure

Feature flag experimentation systems (GrowthBook, Statsig, Optimizely, Eppo) solve a version of the same problem: did this specific change cause the observed metric movement, or was it ambient drift?

### Techniques

- **Holdout groups.** A small percentage of users never see any new features. Comparing the holdout to the treatment group isolates the cumulative effect of all shipped changes. For individual feature attribution, per-feature holdouts are used.
- **CUPED (Controlled-experiment Using Pre-Experiment Data).** Uses pre-experiment metric values as covariates to reduce variance without introducing bias. The adjustment: `Y_adjusted = Y - theta * (X_pre - mean(X_pre))`, where theta maximizes variance reduction. This makes it possible to detect smaller treatment effects faster by removing individual-level baseline variation.
- **Sequential testing and always-valid confidence intervals.** Rather than waiting for fixed sample sizes, these allow early stopping when the effect is clearly present or absent, without inflating false positive rates.

### The attribution problem mapped to beads

A bead ships code. A CUJ signal changes. Was it the bead, or was it something else that shipped around the same time, or was it organic user behavior change?

In production experimentation, this is solved by randomized assignment — users are randomly assigned to see or not see the change. In a CI/development context, randomized user assignment doesn't apply, but the structural analog is:

- **Temporal isolation:** Run the CUJ gate before and after the bead's changes on the same codebase, holding everything else constant. The delta is attributable to the bead.
- **Baseline comparison:** Compare the CUJ signal to its historical baseline (the CUPED analog — use pre-change signal values as covariates).
- **Concurrent change control:** If multiple beads land simultaneously, their blast radii must be compared. Overlapping blast radii mean attribution is ambiguous — the system should flag this, not silently attribute signal changes to one bead.

### Applicable pattern for bead-CUJ linkage

**CUJ gate verification for a bead should compare the gate outcome before and after the bead's changes, not just check the post-change outcome.** A gate that passes post-change but also passed pre-change provides no information about the bead. The signal is in the delta, not the absolute value.

**For continuous/metric CUJ signals (not binary pass/fail):** Use pre-change signal values as a baseline covariate (CUPED-style). Report the bead's effect as the adjusted delta, with a confidence interval. If the confidence interval includes zero, the bead had no detectable effect on the signal — which may mean the gate is too coarse, or the bead's impact is too small to measure.

---

## 6. Program Slicing and Dependence Analysis

### Core discipline: Compute the minimal code subset that affects a variable

Program slicing, introduced by Weiser (1979), computes the set of statements that can affect the value of a variable at a given program point. A backward slice from a CUJ assertion point identifies exactly which code could influence the CUJ outcome.

### Application to test selection and bead scoping

- **Slice-based regression test selection.** Gupta and Harrold (1996) showed that program slicing on the program dependence graph (PDG) can identify which tests are affected by a code change: if a change is outside the backward slice of a test's assertion, the test cannot be affected by the change. This is a provably sound (never misses an affected test) but potentially conservative (may include unaffected tests) selection criterion.
- **Semantic slicing of version histories.** Krinke et al. (2016) extended slicing to version histories, computing which commits affect which program behaviors by analyzing dependence across diffs.
- **Dynamic slicing for precision.** Static slices are conservative (include all possible paths). Dynamic slices, computed on a specific execution trace, identify the actual statements that affected the outcome on that run. For CUJ gates with recorded execution traces, dynamic slicing gives precise attribution.

### The key insight for CUJ gates

A CUJ gate's assertion point defines a slicing criterion. The backward slice from that criterion defines the set of code that can possibly affect the gate's outcome. If a bead's changed code is not in the backward slice of a CUJ gate's assertion, the gate cannot be affected by the bead's changes — linking them is incorrect.

Conversely, if a bead's changed code IS in the backward slice, the gate is a relevant verification artifact for the bead. The strength of relevance depends on the slice distance (how many dependence edges separate the change from the assertion).

### Applicable pattern for bead-CUJ linkage

**Validate bead-CUJ links by checking that the bead's changed code appears in the backward slice of the CUJ gate's assertion.** Links where the changed code is outside the slice are false links — the gate cannot verify the bead regardless of outcome.

**Practical approximation:** Full program slicing is expensive. A practical approximation is to use call-graph reachability (Section 3) plus data-flow analysis at module boundaries. If the changed function's outputs do not flow into any input of the CUJ's assertion logic, the link is unsound.

---

## Synthesis: Structural Properties of a Sound Bead-CUJ Linkage

Combining the six domains, a well-structured bead-CUJ link should satisfy five properties:

### Property 1: Explicit Declaration (from RTM)
The bead must explicitly declare which CUJ signals it claims to affect. The CUJ signal must trace back to the bead. Implicit "the test ran" linkage is not linkage.

### Property 2: Falsifiability (from BDD)
Reverting the bead's changes must cause the linked CUJ gate to fail. If the gate passes regardless of the bead's changes, the link is trivially satisfied and provides no verification.

### Property 3: Blast Radius Scoping (from Change Impact Analysis)
The linked CUJ signals must be within the computed blast radius of the bead's changed files. Signals outside the blast radius should not be in the gate set — their outcomes are not attributable to the bead.

### Property 4: Gate Sensitivity (from Mutation Testing)
Mutations in the bead's changed code must be detected by the linked CUJ gates. A gate that survives mutations in its linked code is not sensitive enough to verify the bead.

### Property 5: Delta Attribution (from Experimentation)
Verification should compare gate outcomes before and after the bead's changes, not just check the post-change state. The signal is in the change, not the absolute value.

### Property 6: Dependence Validity (from Program Slicing)
The bead's changed code must appear in the backward dependence slice of the CUJ gate's assertion. If there is no dependence path from the changed code to the assertion, the link is structurally unsound.

---

## Implications for Demarch's Gate Model

### Gate registration at bead creation time

When a bead is created, its description implies a CUJ scope. At implementation time, the changed files are known. The gate set should be computed as:

```
gate_set(bead) = declared_signals(bead) ∩ blast_radius(changed_files(bead))
```

Signals claimed but outside blast radius: warning (intent-implementation mismatch).
Signals in blast radius but unclaimed: candidate for regression monitoring (not gating).

### Gate validation at bead close time

At bead close, validate the gate set:

1. **Falsifiability check:** Does reverting the bead's patch cause any linked gate to fail? (Can be approximated by checking that the bead's changes include code exercised by the gate.)
2. **Sensitivity check (periodic):** What is the mutation kill ratio for the bead's changed lines against the linked gates?
3. **Delta check:** Did the gate signal change between pre-bead and post-bead states? If not, either the gate is too coarse or the bead's impact is not measurable at this granularity.

### Handling concurrent beads

When multiple beads land in the same time window and their blast radii overlap, CUJ signal changes cannot be cleanly attributed to a single bead. Options:

- **Serialized verification:** Run gates between each bead's merge. Expensive but precise.
- **Blast radius intersection analysis:** If two beads' blast radii don't overlap, their CUJ signals can be independently attributed even if they land simultaneously.
- **Flagged ambiguity:** When blast radii overlap, flag the attribution as ambiguous and require manual review or additional scoped testing.

### Granularity calibration

The right CUJ signal granularity is the level at which the falsifiability property holds. If "user completes checkout" passes whether or not the bead's discount fix works, decompose to "discount applied correctly." If "discount applied correctly" is too fine-grained (no existing signal), the bead should create the signal as part of its deliverables.

**Rule of thumb:** If a CUJ signal is linked to more than ~3 beads simultaneously, it is probably too coarse. If it is linked to zero beads, it is either foundational (always monitored) or dead (should be removed).

---

## Sources

- [Requirements Traceability Matrix for DO-178C Compliance - Parasoft](https://www.parasoft.com/learning-center/do-178c/requirements-traceability/)
- [DO-178C & Structural Coverage Analysis - LDRA](https://ldra.com/ldra-blog/do-178c-structural-coverage-analysis/)
- [Requirements Traceability: ISO 26262 Software Compliance - Parasoft](https://www.parasoft.com/learning-center/iso-26262/requirements-traceability/)
- [Making ISO 26262 Traceability Practical - Electronic Design](https://www.electronicdesign.com/technologies/embedded/article/21235207/arteris-ip-making-iso-26262-traceability-practical)
- [Cucumber Anti-patterns Part 1](https://cucumber.io/blog/bdd/cucumber-antipatterns-part-one/)
- [Keep Your Scenarios BRIEF - Cucumber](https://cucumber.io/blog/bdd/keep-your-scenarios-brief/)
- [Cucumber Anti-patterns Part 2](https://cucumber.io/blog/bdd/cucumber-anti-patterns-part-two/)
- [Blast Radius - Impact Analysis for Code Changes](https://blast-radius.dev/)
- [Call Graph Analysis - drift wiki](https://github.com/dadbodgeoff/drift/wiki/Call-Graph-Analysis)
- [PIT Mutation Testing](https://pitest.org/)
- [Stryker Mutator](https://stryker-mutator.io/)
- [PIT Mutation Testing on CI/CD Pipeline - Trendyol Tech](https://medium.com/trendyol-tech/pit-mutation-testing-on-ci-cd-pipeline-1298f355bae5)
- [CUPED Explained - Statsig](https://www.statsig.com/blog/cuped)
- [Understanding CUPED - Matteo Courthoud](https://matteocourthoud.github.io/post/cuped/)
- [Feature Flag Experiments - GrowthBook](https://docs.growthbook.io/feature-flag-experiments)
- [Hold-Out - Statsig Glossary](https://www.statsig.com/glossary/hold-out)
- [Program Slicing - Wikipedia](https://en.wikipedia.org/wiki/Program_slicing)
- [Program Slicing-Based Regression Testing - Gupta & Harrold (1996)](https://onlinelibrary.wiley.com/doi/abs/10.1002/(SICI)1099-1689(199606)6:2%3C83::AID-STVR112%3E3.0.CO;2-9)
- [Slice-Based Change Impact Analysis for Regression Test Prioritization](https://www.hindawi.com/journals/ase/2016/7132404/)

<!-- flux-research:complete -->
