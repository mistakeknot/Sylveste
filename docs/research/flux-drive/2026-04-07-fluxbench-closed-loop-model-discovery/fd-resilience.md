---
artifact_type: flux-drive-finding
agent: fd-resilience
reviewed: 2026-04-07-fluxbench-closed-loop-model-discovery
prd: docs/prds/2026-04-07-fluxbench-closed-loop-model-discovery.md
---

# fd-resilience: FluxBench Closed-Loop Model Discovery

## Findings Index

| ID | Severity | Feature | Lens | One-line summary |
|----|----------|---------|------|-----------------|
| RES-1 | P1 | F1/F2 | Antifragility | Baseline drift invalidates all historical scores — the measuring stick changes silently with no versioning or migration plan |
| RES-2 | P1 | F7 | Graceful Degradation | Challenger slot has no partial-failure path — one bad challenger output can corrupt real reviews with no containment boundary |
| RES-3 | P2 | F2 | Creative Constraints | 5-10 fixtures treated as a permanent anchor rather than a living constraint — calibration frequency and fixture retirement are unspecified |
| RES-4 | P2 | F4 | Graceful Degradation | Simultaneous multi-model drift has no defined response — the "fallback to Claude" path assumes Claude is always the stable reference |
| RES-5 | P2 | F5 | Resource Bottleneck | Weekly auto-qualification has no token budget cap — fixture count growth × candidate count growth creates unbounded compounding cost |
| RES-6 | P3 | F3/F6 | Diminishing Returns | AgMoDB write-back creates a one-way dependency: FluxBench scores flow out but nothing flows back to recalibrate the scoring thresholds from real-world outcomes |
| RES-7 | P3 | F1 | First Principles | Weighted severity scoring (P0=4x, P1=2x) is borrowed from common convention without grounding in interflux's actual observed recall distribution — may penalize the wrong models |

---

## Detailed Analysis

### RES-1 (P1) — Baseline Drift Invalidates Historical Scores

**Section:** F1 acceptance criteria, F4 drift detection

**Lens:** Antifragility / Assumption Lock

The PRD measures `finding-recall` and `severity-accuracy` relative to a Claude baseline, but never specifies which Claude model version constitutes "Claude baseline." This is an assumption lock inherited from the brainstorm phase — the brainstorm review (fd-resilience.md in `fluxbench-brainstorm-review/`) flagged baseline versioning as P1, and the PRD does not resolve it.

The risk compounds over time, not at launch. When claude-sonnet-4-6 is superseded, every historical FluxBench score becomes incommensurable with scores computed against the new baseline. A model that qualified in March against sonnet-4-6 may score 0.45 against sonnet-5, not because the model degraded, but because the ruler changed. The PRD's drift detection (F4) will then fire incorrectly on all active models simultaneously — the "all non-Claude models drift simultaneously" scenario described in the review context.

An antifragile system would treat baseline transitions as learning opportunities: the transition forces requalification, and the delta between old-baseline and new-baseline scores becomes a signal about the measurement system itself, not just the models under test. Instead the PRD designs for baseline stability, which is the happy path.

**What is missing:** F1 acceptance criteria must include a `baseline_model_version` field on every FluxBench result record. F4 must specify what happens when a baseline version change is detected: freeze comparisons against the old baseline, trigger full-fleet requalification against the new baseline, and carry forward scores with version tags rather than invalidating them.

**Question to resolve:** When Claude's behavior changes, should FluxBench treat that as model degradation in other models (wrong) or as a ruler replacement requiring fresh baselines (right)? The PRD does not distinguish these.

---

### RES-2 (P1) — Challenger Slot Has No Containment Boundary

**Section:** F7 — Challenger Slot Mechanism

**Lens:** Graceful Degradation / Creative Destruction

The PRD correctly excludes challengers from `fd-safety` and `fd-correctness` (F7 safety constraint). But the partial-failure mode within the challenger slot itself is unspecified. Consider three failure patterns the PRD does not address:

1. **Malformed challenger output.** A challenger producing unparseable JSON, hallucinated severity labels, or findings targeting non-existent code sections enters the peer-findings pool tagged `[challenger]`. The PRD says findings are "included in peer findings but flagged." There is no acceptance gate before inclusion — a challenger that consistently hallucinates P0 findings will inject noise into every review it participates in for 10 full runs before the auto-evaluation fires.

2. **Challenger latency blowout.** If the challenger model provider times out or returns slowly, the challenger's latency p50 metric accumulates but the review run stalls. The PRD does not specify a per-challenger timeout or whether a slow challenger blocks synthesis.

3. **10-run evaluation boundary is a cliff.** "After 10+ challenger runs: auto-evaluate qualification gate — promote or reject." This is a binary jump from accumulation to verdict. A challenger with 9 runs and 8 passing results has no different status than a challenger with 1 run. The cliff structure means the system cannot detect that a challenger is already clearly qualified (or disqualified) before the 10th run.

**What is missing:** F7 needs a pre-inclusion filter: challenger findings must pass format-compliance before entering the peer pool. The challenger timeout must be specified in `budget.yaml`. The evaluation boundary should use an early-stopping rule — if a challenger passes all five core gates by run 7, there is no reason to wait for run 10.

---

### RES-3 (P2) — Fixture Set Has No Retirement or Evolution Path

**Section:** F2 — Qualification Test Fixtures

**Lens:** Creative Constraints / Assumption Lock

The PRD specifies "5+ test fixtures with human-annotated ground-truth findings" as the calibration anchor for the entire scoring engine. The acceptance criteria treat this as a static deliverable: create the fixtures, validate them, done. There is no mechanism to retire fixtures, no signal that a fixture has become too easy (all models pass it at ceiling), and no specification for how ground truth should be updated as interflux's review domains evolve.

This is an inherited constraint that will tighten over time. As more models qualify, the fixtures that were calibrated against claude-sonnet-4-6 on document types from early 2026 will become an increasingly poor representation of the review landscape. A fixture testing for architectural findings in a Python codebase provides no signal about an agent's ability to review Rust FFI boundaries or CRDT convergence logic. The fixture set will ossify rather than evolve.

The PRD's open question 4 ("Calibration frequency: how often should FluxBench thresholds be re-derived from the growing ground-truth set?") acknowledges this but defers it. Deferring calibration frequency is acceptable; deferring fixture evolution policy is not — because it determines whether F1's scoring thresholds remain meaningful as the fixture set ages.

**What is missing:** F2 should specify (a) a ceiling signal — if a fixture produces >=95% recall across all qualified models for 90 days, it is retired as non-discriminating; (b) a growth trigger — when interflux gains a new domain or agent type, a new fixture is required before that domain is scored; (c) ground-truth amendment process when human annotators disagree with the calibration baseline.

---

### RES-4 (P2) — Simultaneous Multi-Model Drift Has No Named Response

**Section:** F4 — Drift Detection

**Lens:** Graceful Degradation / Phoenix Moments

The PRD specifies: "Demoted model replaced by Claude for that agent tier until requalification passes." This is a single-model demotion path. The review context explicitly asks: "What happens when all non-Claude models drift simultaneously?" The PRD does not answer this.

Simultaneous drift across all non-Claude active models is the most plausible correlated failure: a provider outage, a new interflux scoring engine version that recalibrates thresholds, or a Claude baseline transition (see RES-1) would trigger drift detection on every active model at once. At that point, the "replace with Claude" fallback assumes Claude capacity is available and that running all agent tiers on Claude is within budget. The PRD's `budget.yaml` does not have a "full-Claude-fallback" budget scenario.

The more interesting adaptive question is whether simultaneous drift is a signal worth exploiting. If every non-Claude model drifts in the same direction on the same metrics, that is evidence about the scoring engine or the baseline, not about the models. An antifragile response would detect correlated drift as a system-level signal and pause requalification until the root cause is identified, rather than triggering a mass demotion cascade.

**What is missing:** F4 should include a correlated-drift detector: if >=N active models demote within a single drift cycle, pause further demotions and emit a `drift_correlation_alert` rather than executing individual demotions. The fallback budget scenario for full-Claude operation should be specified in `budget.yaml`.

---

### RES-5 (P2) — Auto-Qualification Budget Is Unbounded

**Section:** F5 — Proactive Model Surfacing

**Lens:** Resource Bottleneck / Diminishing Returns

The PRD specifies that the weekly scheduled agent "auto-qualifies candidates with 3+ synthetic tasks from F2 fixtures." The cost model compounds in two dimensions simultaneously: fixture count and candidate count both grow. If F2 delivers 10 fixtures and interrank surfaces 8 new candidates per week, the weekly cycle runs 80 qualification tasks. At the token costs implied by `agent_defaults` in `budget.yaml` (40K tokens per review agent), with 17 agents per qualification run, that is 40K × 17 × 80 = 54M tokens per week before any drift requalification.

The prior brainstorm-review (RES-3 in `fluxbench-brainstorm-review/fd-resilience.md`) flagged this as P2. The PRD partially addressed it by saying candidates "run against 3+ synthetic tasks from F2 fixtures" — but 3 tasks × N candidates still has no budget ceiling. The PRD's open question 2 asks about Haiku persona-scoring cost but does not address the broader weekly cycle cost.

The resource bottleneck is the agent dispatch loop in F5, not the scoring engine. The scoring script is cheap; the qualification runs that feed it are expensive.

**What is missing:** F5 must add to `budget.yaml`: `weekly_qualification_budget: <token_ceiling>` and `max_candidates_per_cycle: N`. Priority ordering (highest interrank score first) ensures that if the budget is hit, the most promising candidates qualify first. A circuit-breaker that skips the weekly cycle if total weekly FluxBench spend already exceeds X% of the total project token budget would also prevent runaway during high-traffic periods.

---

### RES-6 (P3) — Scores Flow Out but Nothing Flows Back to Calibrate Thresholds

**Section:** F3, F6 — AgMoDB Write-Back and interrank Integration

**Lens:** Diminishing Returns / Closed-Loop by Default

The PRD closes one loop (interflux → AgMoDB → interrank → model selection) but leaves a second loop open: FluxBench scores affect which models get dispatched, but whether those dispatched models produce better real-world outcomes never feeds back to recalibrate FluxBench thresholds.

This matters because the PRD's core gates (format-compliance >=95%, finding-recall >=60%, etc.) are hardcoded initial values with no calibration mechanism. PHILOSOPHY.md's "Closed-loop by default" principle is explicit that shipping hardcoded defaults without a calibrate-from-history stage is incomplete work. The PRD delivers stages 1 and 2 of the four-stage pattern (hardcoded defaults + collect actuals) but not stages 3 and 4 (calibrate from history + defaults become fallback).

The "finding survival rate tracking" (PRD Non-goals, deferred to v2) is the natural calibration signal: if a model with high FluxBench recall consistently produces findings that humans act on, its threshold should lower (it's already useful); if a model with borderline recall produces findings that get dismissed, its threshold should tighten. Deferring this is acceptable, but deferring the threshold-calibration mechanism entirely means FluxBench will Goodhart itself — models will optimize for the stable target (>=60% recall against Claude baseline) rather than for the outcome the system actually cares about (findings that drive code improvement).

**Note:** This intersects with `fd-feedback-loop-closure.md` territory. Flag for cross-agent review if that agent runs against this PRD.

---

### RES-7 (P3) — Severity Weights Inherited from Convention, Not Interflux Data

**Section:** F1 — FluxBench Metric Definitions

**Lens:** First Principles / Assumption Lock

The PRD specifies: "Weighted recall uses P0=4x, P1=2x, P2=1x, P3=0.5x — missing any P0 auto-fails regardless of aggregate." These weights are reasonable by intuition, but they are borrowed from convention (P0 most important, P3 least) rather than derived from interflux's observed data. No citation or derivation is given.

The risk is that these weights misrepresent the actual value distribution in interflux reviews. If interflux's 26+ production runs (referenced in `budget.yaml` dropout validation note) show that P0 findings occur in 8% of reviews but P2 findings drive 60% of acted-upon code changes, then the 4x P0 weighting is measuring the wrong thing. Severity is not the same as impact.

This is a P3 rather than P1 because wrong weights will produce sub-optimal model selection, not system failure — the system still operates, but may favor models that excel at rare P0 catching over models that produce a high density of useful P2 findings.

**What is missing:** Before hardcoding the weights in `fluxbench-metrics.yaml`, query the existing qualification data in `model-registry.yaml` and interstat to derive empirical weights. If the data is insufficient, ship the convention-based weights as version 1.0 but document them as provisional and specify that they will be recalibrated once 50+ qualification runs exist.

---

## Cross-Cutting Observation: The Happy Path is Well-Designed

The PRD is notably stronger than the brainstorm on the three concerns that were P1/P2 in the prior review:

- **AgMoDB unavailability** (brainstorm RES-2) is addressed — F3 explicitly implements store-and-forward via local JSONL persistence before the AgMoDB commit.
- **Recovery SLA** (brainstorm RES-4) is partially addressed — F4 specifies hysteresis (clear only when recovered to within 5% of baseline) and the `fluxbench-results.jsonl` drift event log. The state machine is implicit but inferrable.
- **Unbounded qualification cost** (brainstorm RES-3) is partially addressed — the auto-qualification is scoped to "3+ synthetic tasks from F2 fixtures" rather than full-fleet runs.

The remaining gaps (RES-1 through RES-7 above) are concentrated in correlated-failure scenarios and long-term adaptive decay — the system survives any single dependency failure but lacks mechanisms to improve from them.

---

## Verdict

STATUS: needs-changes
FINDINGS: 7 (P0: 0, P1: 2, P2: 3, P3: 2)
BLOCKING: RES-1 (baseline versioning required before F4 drift detection is implementable), RES-2 (challenger containment required before F7 is safe to ship)
SUMMARY: FluxBench is resilient against individual component failures but brittle against correlated failures (simultaneous model drift, baseline version transition) and lacks the calibration feedback loop that PHILOSOPHY.md's "Closed-loop by default" principle requires. The two P1s should be resolved before Phase 2 implementation begins.

<!-- flux-drive:complete -->
