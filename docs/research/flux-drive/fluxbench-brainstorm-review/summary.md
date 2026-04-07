## Flux Drive Review — fluxbench-closed-loop-model-discovery-brainstorm

**Reviewed**: 2026-04-07 | **Agents**: 6 launched, 6 completed | **Verdict**: needs-changes

### Verdict Summary

| Agent | Status | Summary |
|-------|--------|---------|
| fd-architecture | warn | Cross-plugin boundaries have 3 structural issues: unbuilt AgMoDB API, dual source of truth, Claude circular dependency |
| fd-systems | warn | Self-reinforcing qualification loop with no balancing mechanism; unbounded drift detection latency; Goodhart's Law vulnerability |
| fd-decisions | warn | Threshold values lack empirical basis; over-commits to full integration before validating the benchmark itself |
| fd-resilience | warn | Happy-path design without degradation for AgMoDB outages, recovery timelines, or cost bounds |
| fd-feedback-loop-closure | warn | Loop closed at model-selection level but open at review-quality level; drift detection lacks hysteresis and windup protection |
| fd-perception | warn | Metrics measure what's mechanically measurable, not what matters most; Claude monoculture creates systematic blind spots |

### Critical Findings (P0)

None.

### Important Findings (P1)

1. **Claude baseline as single reference creates circular dependency, monoculture, and single point of failure** (5/6 agents: fd-architecture, fd-systems, fd-resilience, fd-feedback-loop-closure, fd-perception). Three of four core metrics measure performance relative to Claude. This makes the benchmark brittle to Claude model updates, systematically blind to findings Claude misses, and creates a circular dependency where the review engine is also the benchmark reference. This is the highest-convergence finding across the entire review.

2. **AgMoDB has no write API — entire design depends on unbuilt infrastructure** (2/6 agents: fd-architecture, fd-resilience). The brainstorm acknowledges this in Open Questions but designs the full architecture as if the API exists. The `externalBenchmarkScores` table is populated by git-committed JSONL files from scrapers, not a REST endpoint. This is a blocking prerequisite, not an open question.

3. **Threshold values lack empirical grounding and calibration plan** (3/6 agents: fd-decisions, fd-feedback-loop-closure). The specific numbers (90%, 60%, 70%, 0.6, 15% drift) appear to be intuition-based. Once published as AgMoDB benchmarks, they become sticky. No calibration plan is described.

4. **Over-commitment: 3 capabilities designed simultaneously without MVP validation** (2/6 agents: fd-decisions, fd-resilience). Write-back + drift detection + proactive surfacing in one brainstorm. The minimum viable experiment is FluxBench scoring on existing models with local JSON output — no AgMoDB, no drift, no hooks.

5. **Unbounded detection latency for silent drift** (2/6 agents: fd-systems, fd-feedback-loop-closure). The 1-in-10 sampling rate has a 12% chance of going 20+ reviews without sampling a model. No maximum detection window is specified.

6. **No hysteresis in drift detection** (2/6 agents: fd-feedback-loop-closure, fd-architecture). The 15% threshold fires, but no clear threshold is defined. Models could oscillate between qualified/qualifying states.

7. **Loop is closed at model-selection level but open at review-quality level** (1/6 agents: fd-feedback-loop-closure). FluxBench measures model output quality but doesn't measure whether selecting higher-scoring models actually produces better reviews. No outcome sensor exists.

8. **Format compliance measures form, not substance** (2/6 agents: fd-perception, fd-systems). A model producing perfectly formatted empty findings scores 100% on this core gate metric. It should be a binary gate, not a scored metric.

9. **Dual source of truth — model-registry.yaml and AgMoDB** (1/6 agents: fd-architecture). No reconciliation strategy between the local registry and AgMoDB. Which is authoritative when they disagree?

### Improvements Suggested

1. **Define an MVP scope first** (fd-decisions). FluxBench scoring only, local JSON output, manual comparison against current qualification. Validate the metrics correlate with review quality before building integration infrastructure.

2. **Add a calibration phase** (fd-decisions, fd-feedback-loop-closure). Run FluxBench against 5-10 existing models. Use score distributions to set thresholds empirically rather than by intuition.

3. **Store-and-forward write pattern** (fd-architecture, fd-resilience). Persist FluxBench results locally first, forward to AgMoDB asynchronously. This decouples qualification from API availability.

4. **Add false positive rate as a core metric** (fd-perception). The most important missing metric. A model with 100% recall but 80% false positive rate is worse than 60% recall with 5% false positives.

5. **Weight finding recall by severity** (fd-decisions). Missing a P0 finding should count more than missing a P2. Use severity weights: P0=4, P1=2, P2=1.

6. **Add hysteresis to drift detection** (fd-feedback-loop-closure). Flag at >15% drop, clear only when recovered to within 5% of baseline. Prevents oscillation.

7. **Add an outcome sensor** (fd-feedback-loop-closure). Track finding survival rate per model (how often findings lead to code changes). This closes the loop at the quality level.

8. **Challenger slot in model selection** (fd-systems). Always reserve one agent slot for the highest-scoring unqualified candidate. Prevents preferential attachment.

9. **Define single source of truth** (fd-architecture). Either model-registry.yaml is authoritative (reads from AgMoDB on startup) or AgMoDB is authoritative (registry becomes a cache). Document ownership.

10. **Model status state machine** (fd-resilience). Explicit transitions and timeouts: new -> qualifying -> qualified -> drift_detected -> requalifying (max 7 days) -> qualified | disqualified.

11. **Human-validated calibration set** (fd-perception). 5-10 review tasks with human-annotated ground truth findings. Reduces Claude baseline dependency and provides a Goodhart-resistant anchor.

12. **Sampling guarantee** (fd-systems). Force a shadow run if a model hasn't been sampled in 2*N reviews. Bounds worst-case detection latency.

### Section Heat Map

| Section | Issues | Improvements | Agents Reporting |
|---------|--------|-------------|-----------------|
| FluxBench Metrics | P1: 4, P2: 4 | 7 | all 6 agents |
| Drift Detection | P1: 2, P2: 3 | 4 | fd-systems, fd-feedback-loop-closure, fd-resilience, fd-architecture |
| Write-Back Mechanism | P1: 2, P2: 3 | 3 | fd-architecture, fd-resilience, fd-perception |
| Proactive Surfacing | P2: 2 | 1 | fd-systems, fd-resilience, fd-architecture |
| Key Decisions | P1: 1 | 1 | fd-decisions |

### Conflicts

No direct conflicts detected. All agents converged on the Claude baseline dependency as the primary risk, though they approached it from different angles (architectural coupling, systems dynamics, resilience, control theory, sensemaking).

### Files

- Summary: `/home/mk/projects/Sylveste/docs/research/flux-drive/fluxbench-brainstorm-review/summary.md`
- Findings: `/home/mk/projects/Sylveste/docs/research/flux-drive/fluxbench-brainstorm-review/findings.json`
- Individual reports:
  - [fd-architecture](./fd-architecture.md) -- Cross-plugin boundaries, dual source of truth, API design
  - [fd-systems](./fd-systems.md) -- Reinforcing loops, detection latency, Goodhart's Law
  - [fd-decisions](./fd-decisions.md) -- Threshold anchoring, MVP scope, reversibility analysis
  - [fd-resilience](./fd-resilience.md) -- Degradation paths, cost bounds, recovery SLAs
  - [fd-feedback-loop-closure](./fd-feedback-loop-closure.md) -- Hysteresis, windup, Nyquist, outcome sensing
  - [fd-perception](./fd-perception.md) -- Metric reification, monoculture, missing dimensions

### Beads

*Beads not created -- this is a brainstorm review, not an implementation gate. Create beads when the brainstorm advances to strategy/plan stage.*
