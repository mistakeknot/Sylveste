# Progressive Autonomy Gates: Cross-Domain Models for Human-to-Automated Verification Handoff

Research into how safety-critical and high-velocity industries model the progression from human-gated to autonomously-gated quality verification as system maturity and trust increase.

## 1. Aviation: DO-178C Design Assurance Levels and Tool Qualification

### DAL-Based Verification Scaling

DO-178C defines five Design Assurance Levels (DAL A-E) mapped to failure severity. The standard specifies 71 objectives at DAL A (catastrophic), scaling down to zero at DAL E (no safety effect). Critically, **independence requirements scale separately from total objectives**:

| DAL | Failure Effect | Total Objectives | Require Independence |
|-----|---------------|-----------------|---------------------|
| A   | Catastrophic  | 71              | 31                  |
| B   | Hazardous     | 69              | 19                  |
| C   | Major         | 62              | 5                   |
| D   | Minor         | 26              | 2                   |
| E   | No Effect     | 0               | 0                   |

"Independence" means the verifier cannot be the person who produced the artifact. This is not a binary human-vs-automated distinction -- it is a **separation of agency** requirement. The standard permits automated tools to satisfy objectives, but the independence constraint remains: the tool must not have produced the artifact it verifies.

### DO-330 Tool Qualification: Trusting Automation to Replace Humans

The companion standard DO-330 defines five Tool Qualification Levels (TQL 1-5) governing when automated tools can substitute for manual verification activities. The core principle:

> If a manual activity required for certification is reduced or replaced by an automated tool, and the output of that activity is used without being verified, the developer must qualify the tool -- demonstrating the tool is at least as trustworthy as the activity it replaces.

TQL assignment depends on three Tool Qualification Criteria (TQC):
- **TQC-1 (Development tool)**: Could insert errors into airborne software. Requires TQL-1 (most rigorous, approaching DAL-A verification rigor).
- **TQC-2 (Verification tool, reduces activities)**: Could fail to detect errors AND is used to eliminate other verification. Requires TQL-4 or TQL-2 depending on DAL.
- **TQC-3 (Verification tool, does not reduce activities)**: Could fail to detect errors but is not used to eliminate other checks. Requires TQL-5 (least rigorous).

**Key insight for progressive autonomy**: The aviation framework does not model trust as a continuous variable. Instead, it pre-classifies the **criticality of the change** and the **substitution role of the tool**, then assigns a fixed qualification rigor. Trust is established once through qualification, not earned incrementally through track record.

### Applicability to Software Gate Design

The DO-178C model suggests that progressive autonomy should not be modeled as "earn trust over time for all changes" but rather as "classify each change's criticality, then apply the appropriate verification mode." A system handling DAL-D-equivalent changes (minor, easily reversible) can be fully automated from day one if the tooling is qualified. DAL-A-equivalent changes (catastrophic, irreversible) require independence regardless of track record.

## 2. Medical Devices: FDA Predetermined Change Control Plans (PCCP)

### The PCCP Framework

The FDA's PCCP framework, codified by FDORA Section 515C (2022), allows medical device manufacturers to define an **envelope of pre-approved changes** that can be deployed without individual regulatory review. As of late 2024, approximately 53 devices had FDA-authorized PCCPs, concentrated in radiology and cardiovascular AI/ML applications.

A PCCP has three required components:

1. **Description of Modifications**: An itemized list of each planned change, required to be "limited, specific, and verifiable" -- not open-ended proposals.
2. **Modification Protocol**: Detailed procedures for implementing and testing changes, including verification/validation activities, data collection, model versioning, performance testing criteria, and acceptance thresholds.
3. **Impact Assessment**: Risk-benefit analysis demonstrating how each change affects safety and effectiveness, with documented mitigation strategies.

### Boundaries of Autonomous Operation

The PCCP creates a regulatory envelope with hard constraints:
- Changes must stay within the device's intended use and generally within approved indications.
- Changes cannot increase the device's risk category (e.g., a Class II device cannot autonomously modify itself into Class III territory).
- Only the device version cleared before PCCP implementation can serve as a predicate for future 510(k) comparisons, preventing "leapfrogging" of regulatory oversight.
- Performing out-of-plan changes "would constitute adulteration."

### Monitoring and Rollback

Post-deployment, PCCP-authorized changes require:
- Real-world performance monitoring with defined triggers, frequency, and rollback plans.
- Detection mechanisms for unexpected drift or bias.
- Reporting intervals for ongoing experience data to FDA.
- Rollback procedures if performance thresholds trigger concerns.

### Applicability to Software Gate Design

The PCCP model is the closest regulatory analog to "progressive autonomy with pre-approved boundaries." Its key design insight is the **pre-negotiated envelope**: autonomy is not earned through track record but **pre-authorized through specificity**. The more precisely you can describe what changes will occur, how they will be validated, and what their risk boundaries are, the more autonomy you receive. This inverts the intuition that autonomy requires historical trust -- instead, autonomy requires **predictive specificity**.

The PCCP also demonstrates the importance of **category boundaries as hard stops**. Autonomous changes cannot cross risk categories, just as in aviation, DAL assignment constrains verification mode regardless of tool maturity.

## 3. Continuous Delivery: DORA Metrics and Progressive Delivery

### The DORA Evidence Framework

The Accelerate research program (Forsgren, Humble, Kim) analyzed 23,000+ data points to identify four key metrics distinguishing high-performing teams:

| Metric | Elite | Low |
|--------|-------|-----|
| Deployment Frequency | Multiple/day, on-demand | Monthly or less |
| Lead Time for Changes | < 1 day | > 1 month |
| Change Failure Rate | 0-15% | 46-60% |
| Mean Time to Recovery | < 1 hour | > 1 month |

Elite performers achieve their metrics through CI/CD pipeline maturity, comprehensive automated testing, and progressive delivery -- not through manual gates. The research shows that **removing manual gates correlates with better outcomes**, not worse, provided automated gates have sufficient coverage.

### Progressive Delivery: Automated Gate Promotion

Progressive delivery extends continuous delivery with automated, metrics-driven promotion through deployment stages:

1. **Canary (1-5% traffic)**: New version receives minimal traffic. Automated analysis compares canary metrics against baseline.
2. **Linear ramp (5-25-50-75%)**: Traffic gradually shifts if health metrics remain stable.
3. **Full rollout (100%)**: Automated promotion completes.

At each stage, automated quality gates evaluate:
- Error rates against SLO thresholds
- Latency percentiles against baseline
- Resource utilization anomalies
- Business metric regression (conversion, engagement)

### Automated Canary Analysis: Kayenta and CAS

Google's Canary Analysis Service (CAS) and the open-source Kayenta (Google + Netflix) provide the canonical model for automated gate judgment:

- Kayenta fetches user-configured metrics, runs Mann-Whitney U statistical tests, and produces an aggregate score (0-100).
- The score determines automatic promotion, automatic rollback, or escalation to human review.
- Statistical analysis requires at least 50 time-series data points per metric, meaning canary phases must run long enough to accumulate evidence.
- The system provides a point-in-time PASS/FAIL verdict based on whether behavior is statistically indistinguishable from baseline.

**Key insight**: Automated canary analysis does not "trust" the new version. It tests a statistical null hypothesis (new version behaves the same as baseline) and fails open -- any anomaly triggers rollback. Trust is in the **detection mechanism**, not the change.

### Artifact Provenance as Evidence

Modern CD systems maintain artifact provenance: every live service can be traced back to source commits, test results, and vulnerability scans. This creates an auditable evidence chain that substitutes for human review by making the automated verification inspectable after the fact.

### Applicability to Software Gate Design

The CD model suggests three prerequisites before a gate can be delegated from human to automated:

1. **Measurable quality signal**: The property being gated must be quantifiable with known statistical properties.
2. **Baseline availability**: There must be a stable baseline to compare against (behavioral regression detection requires a reference point).
3. **Reversibility**: The change must be rollback-capable, because automated gates trade certainty for speed -- they detect problems through observation, not proof.

When all three conditions hold, the DORA evidence shows that automated gates produce better outcomes than manual ones, because they eliminate human variability and batch-size delays.

## 4. NASA NPR 7150.2: IV&V and Software Classification

### Software Classification and Verification Requirements

NASA classifies software into Classes A through E based on five factors: usage within NASA systems, system criticality, human dependency, developmental complexity, and investment scale. Safety-critical software must be Class D or higher. IV&V is mandatory for:
- Category 1 projects (highest criticality)
- Category 2 projects with Class A or Class B payload risk
- Projects explicitly selected by the Chief of Safety and Mission Assurance

### Automated Tool Integration in IV&V

NPR 7150.2D requires:
- Software test tools to be validated (section 4.4.8, 4.5.6)
- Auto-generated source code to be verified using the same standards as hand-generated code (section 3.8.1)
- Static analysis tools to be used during development and testing phases for defect detection, security analysis, code coverage, and complexity measurement

NASA's IV&V program leverages a Code Quality Risk Assessment (CQRA) methodology examining approximately 350 code-specific attributes across six primary aspects. This is a hybrid model: automated tools perform the analysis, but IV&V analysts interpret results and make risk assessments.

### Trust Model

NASA's approach differs from aviation in a crucial way: **IV&V is organizationally independent, not just personally independent.** The IV&V facility at Goddard is a separate organization from the development teams. Tool automation assists IV&V analysts but does not replace them -- the human judgment role is preserved at the organizational level even when individual analysis tasks are automated.

The trust-building model for automated tools in NASA is:
1. **Tool validation**: Demonstrate the tool produces correct results for known inputs.
2. **Parallel execution**: Run automated analysis alongside manual review; compare results.
3. **Supervised deployment**: Use tool results as input to human judgment, not as replacement.
4. **Graduated scope expansion**: Extend automated analysis to more artifact types as confidence builds.

NASA does not define a formal "track record threshold" for when automated tools can substitute for human IV&V. The organizational independence requirement means there is always a human IV&V analyst in the loop, even if their work is tool-assisted.

### Applicability to Software Gate Design

NASA's model is the most conservative of the four safety-critical frameworks. Its key insight is that **organizational independence creates a structural trust guarantee** that cannot be replicated by tool qualification alone. For a progressive autonomy system, this suggests that the highest-criticality gates should not just be "human reviewed" but "reviewed by a structurally independent entity" -- whether that entity is a separate team, a separate model, or a separate verification pipeline with different assumptions.

## 5. Human Factors: Automation Trust Calibration

### The Parasuraman-Riley Framework

Parasuraman and Riley (1997) identified four failure modes in human-automation interaction:

- **Use**: Appropriate engagement with automation based on calibrated trust.
- **Misuse**: Over-reliance on automation (complacency), resulting in monitoring failures and decision biases.
- **Disuse**: Under-utilization of automation, commonly caused by false alarms eroding trust.
- **Abuse**: Inappropriate delegation to automation by designers or managers without regard for operator consequences.

### The Sheridan-Verplank 10-Level Automation Taxonomy

Sheridan and Verplank (1978), later refined by Parasuraman, Sheridan, and Wickens (2000), defined 10 levels of automation for decision and action selection:

| Level | Description |
|-------|-------------|
| 1     | Human decides everything, no computer assistance |
| 2     | Computer offers a complete set of alternatives |
| 3     | Computer narrows alternatives to a few |
| 4     | Computer suggests one alternative |
| 5     | Computer executes suggestion if human approves |
| 6     | Computer executes unless human vetoes within time window |
| 7     | Computer executes, then informs human |
| 8     | Computer informs human only if asked |
| 9     | Computer informs human only if it decides to |
| 10    | Computer decides and acts autonomously, ignoring human |

### The Four-Stage Automation Model

Parasuraman, Sheridan, and Wickens (2000) proposed that automation applies across four functional stages, each of which can be independently set to different automation levels:

1. **Information Acquisition**: Sensing and filtering data
2. **Information Analysis**: Pattern recognition and inference
3. **Decision and Action Selection**: Choosing a course of action
4. **Action Implementation**: Executing the chosen action

This decomposition is critical: a system can be highly automated in information acquisition (Level 8-9) while remaining human-gated in decision selection (Level 4-5). Progressive autonomy does not need to advance uniformly across all stages.

### Trust Calibration Principles

Complacency (Parasuraman & Manzey, 2010) is "a psychological state characterized by a low index of suspicion" -- operators stop monitoring automated systems because they have been reliable. Key findings:

- **Reliability threshold effect**: Automation reliability above ~70% tends to induce complacency. Below ~70%, operators distrust and override automation (disuse).
- **Transparency as calibration**: Exposing automation's confidence levels, uncertainty, and reasoning helps operators maintain calibrated trust.
- **Variable reliability is worse than consistent unreliability**: Intermittent failures in otherwise reliable systems produce the worst monitoring performance.
- **Workload interaction**: Complacency increases under high concurrent task load, when operators have the least capacity to monitor automation.

### Applicability to Software Gate Design

The human factors literature provides four design principles for gate handoff:

1. **Decompose by stage, not by trust level.** Rather than moving a gate from "human" to "automated" monolithically, decompose the gate into its Parasuraman stages. Automate information acquisition and analysis first (data collection, metric computation). Keep decision selection at Level 4-5 (suggest, require approval) until evidence accumulates. Only advance action implementation to Level 6-7 (execute unless vetoed) after demonstrating calibrated reliability.

2. **Design for transparency, not opacity.** Every automated gate decision should expose its reasoning, confidence, and the data it considered. This prevents complacency by giving humans material to evaluate, and prevents disuse by making the automation's competence visible.

3. **Avoid the uncanny valley of partial automation.** Level 6 (execute unless vetoed within time window) is the most dangerous level because it demands sustained vigilance without providing meaningful control. If a gate is automated enough that humans rarely intervene, they will stop monitoring. Either keep humans actively in the loop (Level 4-5) or move to full automation with post-hoc audit (Level 7-8).

4. **Set reliability thresholds before handoff.** Define the false-positive and false-negative rates that the automated gate must demonstrate before it can substitute for human review. Track these rates continuously and revert to human gating if they degrade.

## 6. Game Development: Regression Ratchets and Quality Ladders

### Phase-Gated Quality Escalation

Game development uses a well-established phase-gate model where quality criteria tighten monotonically as the project approaches ship:

- **Pre-Alpha**: Core mechanics functional. No quality floor -- exploratory, breaking changes expected.
- **Alpha ("Feature Complete")**: All planned features implemented and playable end-to-end. Quality floor established: no new features after this point. Regression testing begins.
- **Beta ("Content Complete")**: All content, assets, and core functions finalized. Quality floor tightens: no changes to key game elements. Focus shifts to polish, bug fixes, optimization. Regression test suite becomes the primary quality instrument.
- **Gold Master ("Release Candidate")**: Should contain no known ship-blocking bugs. Quality floor is absolute: the game is the product.
- **Submission**: Platform holders (Sony, Microsoft, Nintendo) apply their own certification checklists. External quality gate with pass/fail authority.

### The Ratchet Mechanism

The game development quality model implements a **monotonic ratchet** with two properties:

1. **Gate criteria only tighten, never loosen.** At Alpha, a crash might be acceptable. At Beta, it is a blocker. At Gold, any regression from Beta is a blocker. The threshold moves in one direction.

2. **The set of allowed change types narrows.** Pre-Alpha allows architecture changes. Alpha allows feature changes but not architecture changes. Beta allows bug fixes but not feature changes. Gold allows only ship-blocking bug fixes.

### CI/CD Ratchet Implementations

The ratchet concept has been adopted in CI/CD as automated coverage enforcement:

- **Baseline establishment**: Measure current test coverage or quality metric.
- **Ratchet configuration**: CI fails if coverage drops below current level. The threshold auto-increases as coverage improves but never decreases.
- **Differential enforcement**: Stricter thresholds for critical code paths; relaxed thresholds for non-critical areas.
- **Pull request gates**: Automated status checks that fail if coverage regresses by more than a configured delta.

### Applicability to Software Gate Design

The game development model contributes two mechanisms missing from the safety-critical frameworks:

1. **Monotonic gate tightening**: As a system matures and approaches a quality milestone, gates should tighten, not relax. This is counterintuitive to the "earn trust, relax gates" model. The game development insight is that trust is about **stability and predictability**, not about relaxation. A mature system earns the right to have tighter gates because it can meet them, not because it no longer needs them.

2. **Change-type restriction as a gate dimension**: Rather than gating on "who reviews" (human vs. automated), gate on "what kinds of changes are permitted." As ship date approaches, the system refuses to accept certain change categories entirely. This is a harder gate than any review -- it eliminates the change rather than reviewing it.

## Synthesis: Design Principles for Progressive Autonomy Gates

Drawing across all six domains, a progressive autonomy gate system should incorporate these principles:

### Principle 1: Classify Changes by Criticality, Not by System Maturity

**Source**: DO-178C DAL assignment, FDA PCCP risk categories, NASA software classification.

The primary axis for gate selection is the criticality of the specific change, not the overall maturity of the system. A mature system still applies human review to catastrophic-risk changes. An immature system can still auto-approve no-effect changes. Criticality classification should consider:
- Reversibility (can the change be rolled back?)
- Blast radius (how many users/components are affected?)
- Safety impact (does the change affect safety-critical paths?)
- Novelty (is this a change type the system has handled before?)

### Principle 2: Pre-Negotiate the Autonomy Envelope

**Source**: FDA PCCP modification protocols, DO-330 tool qualification criteria.

Autonomy is not earned through track record alone -- it is pre-authorized through **specificity**. Define in advance:
- What types of changes can be auto-approved
- What validation protocol each change type requires
- What performance thresholds trigger rollback
- What boundaries, if crossed, escalate to human review

The more precisely the envelope is defined, the more autonomy is justified. Vague envelopes get no autonomy.

### Principle 3: Decompose Gates by Parasuraman Stage

**Source**: Parasuraman-Sheridan-Wickens automation taxonomy.

Do not treat a gate as a monolithic "human or automated" decision. Decompose into:
- **Information acquisition** (automated from the start): Collect metrics, run tests, gather signals.
- **Information analysis** (automate early): Compute aggregates, detect anomalies, compare baselines.
- **Decision selection** (automate cautiously): Start at Level 4 (suggest), move to Level 6 (execute unless vetoed), reach Level 7 (execute, inform after) only with proven reliability.
- **Action implementation** (automate last): Deployment, merge, publish.

### Principle 4: Require Statistical Evidence, Not Elapsed Time

**Source**: Google/Netflix Kayenta, DORA metrics, CI/CD ratchets.

The threshold for automated gate promotion is not "the system has been running for N days" but "the system has accumulated sufficient statistical evidence." Specifically:
- Minimum sample sizes for canary analysis (Kayenta requires 50+ data points per metric)
- Defined false-positive and false-negative rate thresholds
- Baseline comparison using appropriate statistical tests (Mann-Whitney U, confidence intervals)
- Continuous monitoring with automated reversion if detection rates degrade

### Principle 5: Apply the Ratchet -- Gates Tighten, Never Loosen

**Source**: Game development phase gates, CI/CD coverage ratchets.

Quality gates should monotonically tighten as the system matures:
- New metric coverage only increases, never decreases
- New change categories start human-gated and may earn automated status, but earned automated status is not revoked (it is supplemented with additional automated checks)
- As the system approaches critical milestones, the set of permitted change types narrows

### Principle 6: Design for Transparency to Prevent Complacency

**Source**: Parasuraman trust calibration, NASA IV&V organizational independence.

Every automated gate decision must expose:
- What evidence it considered
- What its confidence level is
- Why it reached its verdict
- What the closest-to-threshold metric was (the "weakest link")

This serves dual purposes: preventing operator complacency (humans have material to evaluate) and enabling post-hoc audit (automated decisions are inspectable).

### Principle 7: Structural Independence for Highest-Criticality Gates

**Source**: NASA IV&V organizational independence, DO-178C independence requirements.

For the highest-criticality changes, independence must be structural, not just procedural. The verifier must be a different entity (team, model, pipeline) with different assumptions and failure modes than the producer. Automated tools can assist but cannot replace structural independence at the highest criticality levels.

## Mapping to a Concrete Gate Progression

Combining these principles, a four-tier gate model emerges:

### Tier 0: No-Effect Changes (Fully Automated)
- **Analog**: DAL-E, PCCP within-envelope, game dev pre-alpha
- **Gate**: Automated tests pass, coverage ratchet holds, no metric regression
- **Human role**: None (post-hoc audit available)
- **Examples**: Formatting, documentation, dependency bumps within semver range

### Tier 1: Minor Changes (Automated with Notification)
- **Analog**: DAL-D, progressive delivery canary, game dev alpha
- **Gate**: Automated canary analysis, statistical baseline comparison, SLO compliance
- **Human role**: Informed after merge (Sheridan Level 7), can inspect evidence
- **Examples**: Bug fixes, minor feature adjustments, configuration changes

### Tier 2: Significant Changes (Automated with Veto Window)
- **Analog**: DAL-C, PCCP boundary changes, game dev beta
- **Gate**: Automated analysis plus time-bounded human veto opportunity (Sheridan Level 6)
- **Human role**: Has window to review and block; automation proceeds if no veto
- **Examples**: New features, API changes, performance-critical modifications

### Tier 3: Critical Changes (Human-Gated with Tool Assistance)
- **Analog**: DAL-A/B, FDA new submission, NASA Class A IV&V, game dev gold/submission
- **Gate**: Structurally independent human review, assisted by automated analysis
- **Human role**: Active review required; automation provides evidence but does not decide
- **Examples**: Security changes, irreversible migrations, public API breaking changes, releases

---

## Sources

### Aviation (DO-178C / DO-330)
- [DO-178C - Wikipedia](https://en.wikipedia.org/wiki/DO-178C)
- [DO-178C Overview - Parasoft](https://www.parasoft.com/learning-center/do-178c/what-is/)
- [DO-178C DAL Deep Dive - TheCloudStrap](https://thecloudstrap.com/design-assurance-level-dal-in-do-178c/)
- [DO-178C Guidance - Rapita Systems](https://www.rapitasystems.com/do178)
- [DO-330 Introduction - AFuzion](https://afuzion.com/do-330-introduction-tool-qualification/)
- [DO-330 Tool Qualification - LDRA](https://ldra.com/do-330/)
- [Trusting the Tools - Military Embedded Systems](https://militaryembedded.com/avionics/safety-certification/trusting-tools-agile-approach-tool-qualification-do-178c)

### Medical Devices (FDA PCCP)
- [FDA PCCP Guide - IntuitionLabs](https://intuitionlabs.ai/articles/fda-predetermined-change-control-plan-pccp-guide)
- [PCCP Guiding Principles - PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC12577744/)
- [PCCP Implementation Guide 2025 - Complizen](https://www.complizen.ai/post/fda-predetermined-change-control-plan-pccp-implementation-guide-2025)
- [FDA PCCP Guidance Document](https://www.fda.gov/media/180978/download)
- [FDA AI/ML SaMD Framework](https://www.fda.gov/media/145022/download)
- [Understanding FDA PCCP Guidance - Ketryx](https://www.ketryx.com/blog/understanding-fda-guidance-on-ai-in-medical-devices-and-predetermined-change-control-plans-pccps)

### Continuous Delivery (DORA / Progressive Delivery)
- [Accelerate Metrics - LinearB](https://linearb.io/blog/accelerate-metrics)
- [DORA Metrics Guide - GetDX](https://getdx.com/blog/dora-metrics/)
- [DORA and Progressive Delivery](https://progressivedelivery.com/2025/09/30/dora-and-progressive-delivery/)
- [Kayenta - Google Cloud Blog](https://cloud.google.com/blog/products/gcp/introducing-kayenta-an-open-automated-canary-analysis-tool-from-google-and-netflix)
- [Automated Canary Analysis at Netflix - Netflix TechBlog](https://netflixtechblog.com/automated-canary-analysis-at-netflix-with-kayenta-3260bc7acc69)
- [Google SRE Canarying Releases](https://sre.google/workbook/canarying-releases/)
- [Canary Analysis Lessons - Google Cloud Blog](https://cloud.google.com/blog/products/devops-sre/canary-analysis-lessons-learned-and-best-practices-from-google-and-waze)

### NASA (NPR 7150.2 / IV&V)
- [NPR 7150.2D - NASA NODIS](https://nodis3.gsfc.nasa.gov/displayDir.cfm?t=NPR&c=7150&s=2D)
- [SWE-141 Software IV&V - NASA SWEHB](https://swehb.nasa.gov/display/SWEHBVD/SWE-141+-+Software+Independent+Verification+and+Validation)
- [NASA Software Classification - Appendix D](https://nodis3.gsfc.nasa.gov/displayDir.cfm?Internal_ID=N_PR_7150_002D_&page_name=AppendixD)
- [NASA IV&V Services](https://www.nasa.gov/ivv-services/)
- [NPR 7150.2D - LDRA Compliance](https://ldra.com/npr7150-2d/)

### Human Factors (Automation Trust)
- [Parasuraman & Riley 1997 - Use, Misuse, Disuse, Abuse](https://journals.sagepub.com/doi/10.1518/001872097778543886)
- [Parasuraman, Sheridan & Wickens 2000 - Automation Model](https://pubmed.ncbi.nlm.nih.gov/11760769/)
- [Parasuraman & Manzey 2010 - Complacency and Bias](https://journals.sagepub.com/doi/10.1177/0018720810376055)
- [Adaptive Trust Calibration - PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC8181412/)
- [Sheridan & Verplank Levels of Automation](https://www.researchgate.net/figure/Levels-of-Automation-From-Sheridan-Verplank-1978_tbl1_235181550)

### Game Development / CI Ratchets
- [Alpha Beta Gold - Filament Games](https://www.filamentgames.com/blog/alpha-beta-gold-commitment-high-quality-game-development/)
- [Game Development Milestones](http://mycours.es/gamedesign2021/milestone-beta/)
- [Code Coverage Ratcheting - PullNotifier](https://pullnotifier.com/tools/code-coverage)
- [Code Coverage in CI/CD - OtterWise](https://getotterwise.com/article/code-coverage-in-ci-cd-pipelines-basics)
- [Quality Gates in Agile - Christian Nissen](https://medium.com/@cnissen_48622/quality-gates-in-agile-development-697df393d9cd)

<!-- flux-research:complete -->
