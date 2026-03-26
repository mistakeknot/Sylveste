# CI/CD Failure Taxonomies and Manufacturing Rework Model Mapping

> Flux-drive research: CI/CD failure classification, disposition strategies, and formal mapping to manufacturing quality economics.

## 1. Failure Taxonomy

CI/CD failures divide into two fundamental classes, following the "Good and Bad Failures" framework from industrial CI/CD research (Ericsson/Software Center, 2025):

### 1.1 "Good" Failures (Quality Gates Working as Designed)

These are **intended catches** -- the pipeline doing its job. Manufacturing analog: **inspection station rejects**.

| Category | Example | Disposition |
|---|---|---|
| **Compilation/build error** | Type mismatch, missing import | Block merge; author fixes |
| **Unit test regression** | Assertion failure on changed code path | Block merge; author fixes |
| **Static analysis violation** | New lint error, security finding | Block merge; author fixes or suppresses with justification |
| **Integration contract break** | API schema mismatch, protocol version skew | Block merge; coordinate with upstream |
| **Quality gate threshold** | Coverage drop below floor, performance regression | Block merge; remediate or adjust threshold |

These failures have **high signal** -- the failure correlates with the change that caused it. In manufacturing terms, this is a station detecting a defect at the point of introduction, minimizing rework travel distance.

### 1.2 "Bad" Failures (Pipeline Noise / Waste)

These are **unintended stops** -- failures not caused by the change under test. Manufacturing analog: **machine breakdown, measurement error, fixture malfunction**.

| Category | Example | Disposition |
|---|---|---|
| **Flaky test** | Non-deterministic pass/fail (async timing, test ordering, concurrency) | Quarantine + file bug |
| **Infrastructure failure** | Runner pod crash, docker daemon timeout, network partition | Auto-retry; report to infra team |
| **Resource starvation** | OOM kill, disk full, job execution timeout | Auto-retry with resource bump; capacity planning |
| **Dependency resolution** | Upstream package registry down, transient 503 | Auto-retry with backoff |
| **Environment drift** | Base image update broke assumption, stale cache | Pinning; hermetic builds |
| **Configuration rot** | Stale credentials, expired certificates, wrong region | Operational maintenance |

These failures have **low signal** -- they do not correlate with the developer's change. In manufacturing terms, this is the inspection machine itself malfunctioning, producing false rejects.

### 1.3 Industrial Taxonomy Depth

The TELUS/Concordia study (2025) identified **46 distinct flaky failure categories** using RFM analysis (Recency, Frequency, estimated Monetary cost), enabling prioritized remediation. Key root cause clusters from that and the FlakyCat classifier:

- **Async/await races** -- most frequent in web/mobile CI
- **Test order dependency** -- shared mutable state between tests
- **Unordered collections** -- map iteration, set comparison
- **Concurrency** -- goroutine/thread scheduling non-determinism
- **Time sensitivity** -- wall-clock assertions, timezone assumptions
- **Runner pod failures** -- Kubernetes eviction, node pressure
- **Docker daemon connection** -- container runtime instability
- **Job execution timeout** -- queue depth, noisy neighbors

## 2. Disposition Strategies

### 2.1 Flaky Test Quarantine

The quarantine pattern, pioneered at Google and Facebook/Meta and now standard practice:

1. **Detection**: Statistical flakiness scoring over rolling window (e.g., same test, same code, different outcomes in N runs)
2. **Quarantine**: Automatically remove from critical path; test still runs but failure does not block merge
3. **Accountability**: Auto-file bug, assign to owning team, apply SLA for resolution
4. **Graduation**: Test exits quarantine only after root cause fix and sustained stability window

**Google's approach**: An automated tool monitors test flakiness rates and quarantines tests exceeding threshold. A companion tool detects *changes* in flakiness level and pinpoints the causal commit. At Google's scale (TAP processing 13K+ projects/day, 2 billion LOC), this is essential -- TAP processes >1000 test results/second across thousands of machines.

**Meta/Facebook's approach**: Sandcastle strictly separates infrastructure failures from code failures. Developers *never see* infrastructure failures; those route exclusively to the Sandcastle infra team. Predictive test selection (ML-based) reduces test execution by 50% while catching >95% of true failures.

**Slack's approach**: Automated detection and suppression pipeline with staged remediation -- from retry through quarantine through team notification through escalation.

### 2.2 Rollback vs. Forward-Fix Decision Model

The disposition decision maps directly to manufacturing's **rework-in-place vs. return-to-station** trade-off:

```
                          Is service degraded?
                         /                     \
                       Yes                      No
                      /                           \
              Can you rollback?            Monitor + fix in next release
             /                \
           Yes                 No (destructive migration,
          /                     protocol change, data mutation)
   Time to rollback             \
   < time to fix?            Must fix forward
      /        \
    Yes         No
   /              \
 Rollback      Fix forward
```

**Rollback cost factors:**
- Time to detect failure (MTTD)
- Time to execute rollback (seconds for blue-green, minutes for traditional)
- Data compatibility risk (schema migrations are often irreversible)
- Customer impact during rollback window
- "Rework penalty" -- the original change still needs to ship later

**Forward-fix cost factors:**
- Moratorium on other deploys during fix (pipeline congestion)
- Rushed code with less test coverage
- Extended customer exposure to degradation
- Code churn increasing system entropy

**DORA metrics frame this quantitatively:**
- **Change Failure Rate** (CFR): ratio of deployments requiring rollback or hotfix
- **MTTR** (Mean Time to Recovery): time from failure detection to service restoration
- **Deployment Frequency**: high frequency + low CFR = smaller blast radius per change
- DORA research consistently shows speed and stability are *not* trade-offs -- they correlate positively through smaller, more frequent changes

### 2.3 Artifact Promotion Gates

Quality gates in CI/CD map to manufacturing **inspection stations with hold/release authority**:

```
Source --> Build --> Unit Test --> Integration Test --> Staging --> Canary --> Production
  |          |           |              |                |          |           |
  G0         G1          G2             G3               G4         G5          G6
  lint     compile    fast tests    contract tests    soak test   % traffic   full traffic
```

Each gate has:
- **Pass criteria**: defined thresholds (zero test failures, coverage >= N%, latency p99 < Xms)
- **Failure disposition**: block promotion, auto-retry, quarantine, or alert-and-continue
- **Escape tracking**: defects found at gate Gn that *should* have been caught at Gn-k represent gate escape -- equivalent to manufacturing's "defect escape rate"

The trade-off is explicit: **more gates = higher appraisal cost but lower failure cost downstream**. Missed gates stop pipeline execution entirely -- the artifact never promotes.

### 2.4 Feature Flags as Runtime Disposition

Feature flags represent a **runtime deviation mechanism** -- the software equivalent of manufacturing's **rework loop that operates on the production line itself** rather than returning product to an earlier station:

| Flag Type | Manufacturing Analog | Disposition Use |
|---|---|---|
| **Release toggle** | Conditional packaging -- include part but don't install | Decouple deploy from release; dark launch |
| **Experiment toggle** | A/B test fixture on production line | Canary to % of traffic; measure before commit |
| **Ops toggle / kill switch** | Emergency stop button | Disable feature without rollback; instant mitigation |
| **Permission toggle** | Customer-specific configuration | Progressive rollout by cohort |

**Key properties:**
- Flags allow **partial rollback** -- disable one feature without reverting the entire deployment
- Canary releases via flags: 5% -> 10% -> 25% -> 50% -> 100%, with automatic rollback on metric degradation
- Kill switches provide O(seconds) MTTR vs O(minutes) for deployment rollback
- Technical debt risk: stale flags accumulate; must have lifecycle management (creation -> rollout -> cleanup)

## 3. Mapping to Manufacturing Rework Model

### 3.1 The Cost of Quality (COQ) Framework

The ASQ/Six Sigma Cost of Quality model has four buckets. Here is the CI/CD mapping:

| COQ Category | Manufacturing | CI/CD Equivalent | Examples |
|---|---|---|---|
| **Prevention** | Process design, training, SPC | Linting, type systems, code review, test infrastructure, hermetic builds | Investment in preventing defects from entering the pipeline |
| **Appraisal** | Inspection, testing, audit | CI test execution, integration testing, staging validation, canary analysis | Cost of running the pipeline to detect defects |
| **Internal Failure** | Scrap, rework before shipment | Failed builds, blocked merges, flaky test investigation, rollbacks before customer impact | Defects caught before production exposure |
| **External Failure** | Warranty, returns, recalls | Production incidents, customer-facing outages, data corruption, emergency hotfixes | Defects that escaped all gates |

**The fundamental quality economics law applies identically:**
- High prevention investment -> low COPQ (internal + external failure)
- Low prevention investment -> high COPQ
- COPQ typically represents 15-30% of total engineering effort in immature organizations
- World-class: <5% of effort spent on failure costs

### 3.2 First Pass Yield and Rolled Throughput Yield

**First Pass Yield (FPY)** = changes that pass all CI gates on first submission / total changes submitted

This is directly measurable:
```
FPY = (PRs merged without any CI failure) / (total PRs submitted)
```

**Rolled Throughput Yield (RTY)** = product of yields at each gate:
```
RTY = Y_lint * Y_build * Y_unit * Y_integration * Y_staging * Y_canary

Example:
RTY = 0.95 * 0.98 * 0.90 * 0.95 * 0.97 * 0.99 = 0.76
```

An RTY of 0.76 means **24% of changes require rework at some point** in the pipeline. The "hidden factory" -- engineering capacity consumed by rework that doesn't appear in feature velocity metrics.

### 3.3 Rework vs. Scrap Classification

| Manufacturing | CI/CD Equivalent | Cost Profile |
|---|---|---|
| **Rework** (fix and re-inspect) | Failed CI -> author fixes -> re-run pipeline | Author time + compute re-run cost |
| **Scrap** (discard unit entirely) | PR abandoned, feature killed, branch deleted | All prior work on that change is sunk cost |
| **Sort** (segregate for further analysis) | Flaky test quarantine, conditional merge with monitoring | Deferred cost; may convert to rework or scrap |
| **Use-as-is** (accept deviation) | Merge with known failing test (suppressed/skipped) | Technical debt; deferred external failure cost |
| **Return to supplier** | Dependency upgrade reverted; upstream bug filed | Coordination cost + wait time |

### 3.4 The Hidden Factory in CI/CD

The "Hidden Factory" concept from Lean manufacturing maps precisely to CI/CD:

- **Visible factory**: feature development, planned work, roadmap execution
- **Hidden factory**: flaky test investigation, CI debugging, environment fixes, retry loops, rollback coordination

Symptoms of a large hidden factory:
- High retry rates (builds re-triggered 2-3x before passing)
- Long PR cycle times despite fast individual test execution
- Developer learned helplessness ("just re-run it")
- Silent failures: builds that pass on retry but had a real transient issue that will recur

The industrial study "On the Illusion of Success" (2025) specifically examined build reruns and silent failures, finding that re-run culture masks systemic quality issues.

### 3.5 Formal Cost Model

```
Total Pipeline Cost = C_prevention + C_appraisal + C_internal_failure + C_external_failure

Where:
  C_prevention   = CI infrastructure + test authoring + linting + type system + review tooling
  C_appraisal    = compute cost per pipeline run * runs per change * changes per period
  C_internal     = (1 - FPY) * avg_rework_cost * changes_per_period
                   + scrap_rate * avg_sunk_cost * changes_per_period
  C_external     = escape_rate * avg_incident_cost * changes_per_period

Rework cost per change:
  C_rework = t_diagnose + t_fix + t_revalidate + C_compute_rerun + C_opportunity_cost

Rollback cost:
  C_rollback = C_detection + C_execution + C_customer_impact + C_rework_penalty

  where C_rework_penalty = cost to re-land the change later (often > original cost
  due to merge conflicts, context loss, re-review)

Feature flag mitigation value:
  V_flag = P(incident) * (C_rollback - C_flag_disable) * deployment_frequency

  where C_flag_disable << C_rollback (seconds vs minutes)
```

## 4. Practitioner Strategies by Scale

### 4.1 Google Scale (Monorepo, 2B+ LOC)

- **TAP** (Test Automation Platform): dependency-based affected test selection; automatic culprit finding by bisecting batched changes
- **Flaky quarantine**: automated with bug filing; test exits quarantine only after fix + stability proof
- **Predictive test selection**: ML models reduce test matrix while maintaining >95% failure detection
- **Gate philosophy**: block on "good" failures, auto-retry on "bad" failures, never show infra failures to developers

### 4.2 Meta Scale (Monorepo, Rapid Mobile Release)

- **Sandcastle**: strict separation of infra failures from code failures at the system level
- **Predictive test selection**: ML reduces test execution by 50% with >95% failure recall
- **Sapienz**: search-based software testing for automated test generation and crash reproduction
- **Release trains**: time-based releases with cherry-pick gates; feature flags for runtime control

### 4.3 General Enterprise (Multi-repo, Mixed Tooling)

- **Staged promotion**: dev -> staging -> canary -> production with explicit gate criteria
- **Retry budgets**: max N retries per pipeline stage; exceeded retries escalate to infra team
- **Quarantine SLAs**: flaky tests must be fixed within N days or are deleted
- **DORA tracking**: CFR and MTTR as leading indicators of pipeline health

## 5. Key Insights for Rework Model Design

1. **The taxonomy is binary at root**: every CI failure is either signal (change caused it) or noise (change didn't cause it). All disposition strategy flows from this classification.

2. **Quarantine is "sort" disposition**: it is neither rework nor scrap but a deferred classification. Manufacturing has the same pattern -- segregate suspect units for further analysis.

3. **Feature flags are a novel disposition class**: they enable "use-as-is with runtime guard" -- accepting a deviation from spec with a compensating control. Manufacturing has no perfect analog because physical products can't be dynamically reconfigured post-shipment.

4. **RTY is the single best health metric**: it captures the multiplicative cost of multi-stage rework in a way that individual gate pass rates cannot. A pipeline with six 95% gates has RTY of 0.74 -- one in four changes requires rework somewhere.

5. **The hidden factory is measurable**: retry rate, PR cycle time minus test execution time, and flaky test count are direct proxies for hidden rework cost.

6. **Prevention ROI is superlinear**: investment in prevention (types, linting, hermetic builds) reduces both appraisal cost (fewer tests needed) and failure cost (fewer defects to catch). This is the quality economics fundamental that manufacturing learned decades ago.

7. **Rollback is not free rework**: unlike manufacturing where rework returns a unit to a prior station at known cost, deployment rollback carries a "rework penalty" -- the change must still be re-landed later, often at higher cost due to drift and context loss.

## Sources

- [On the Diagnosis of Flaky Job Failures (TELUS/Concordia, 2025)](https://arxiv.org/html/2501.04976v1) -- 46-category flaky failure taxonomy with RFM cost analysis
- ["Good" and "Bad" Failures in Industrial CI/CD (Software Center/Ericsson, 2025)](https://arxiv.org/html/2504.11839v1) -- industrial CI/CD failure classification balancing cost and quality
- [Predicting Intermittent Job Failure Categories (FlakyCat, 2026)](https://arxiv.org/html/2601.22264) -- few-shot LLM classification of flaky failure root causes
- [On the Illusion of Success: Build Reruns and Silent Failures (2025)](https://arxiv.org/html/2509.14347v1) -- hidden factory dynamics in CI retry culture
- [Taming Google-Scale Continuous Testing (Google Research)](https://research.google.com/pubs/archive/45861.pdf) -- TAP architecture and affected test selection
- [Flaky Tests at Google and How We Mitigate Them (Google Testing Blog)](https://testing.googleblog.com/2016/05/flaky-tests-at-google-and-how-we.html) -- quarantine workflow at Google
- [Rapid Release at Massive Scale (Meta Engineering)](https://engineering.fb.com/2017/08/31/web/rapid-release-at-massive-scale/) -- Meta's release pipeline and signal quality
- [Predictive Test Selection (Meta Research)](https://research.facebook.com/publications/predictive-test-selection/) -- ML-based test selection reducing execution by 50%
- [Handling Flaky Tests at Scale (Slack Engineering)](https://slack.engineering/handling-flaky-tests-at-scale-auto-detection-suppression/) -- automated detection and suppression pipeline
- [Pipeline Quality Gates (InfoQ)](https://www.infoq.com/articles/pipeline-quality-gates/) -- quality gate implementation patterns
- [DORA Metrics (dora.dev)](https://dora.dev/guides/dora-metrics/) -- CFR, MTTR, deployment frequency, lead time
- [Fix Forward or Roll Back (xMatters)](https://www.xmatters.com/blog/after-a-deployment-error-should-you-fix-forward-or-roll-back) -- rollback vs forward-fix decision framework
- [Cost of Quality (ASQ)](https://asq.org/quality-resources/cost-of-quality) -- prevention, appraisal, internal/external failure cost model
- [Scrap Rate vs. Rework Rate (Symestic)](https://www.symestic.com/en-us/what-is/scrap-rate-vs.-rework-rate) -- manufacturing rework/scrap definitions
- [First Time Yield ROI (Sciemetric)](https://www.sciemetric.com/blog/metric-save-you-millions-roi-improving-fty) -- FPY/RTY measurement and business impact
- [Feature Flags: The Hidden Switch (Semaphore)](https://semaphore.io/blog/feature-flags) -- feature flag CI/CD integration patterns
- [Feature Flags 101 (LaunchDarkly)](https://launchdarkly.com/blog/what-are-feature-flags/) -- kill switches and operational toggles

<!-- flux-research:complete -->
