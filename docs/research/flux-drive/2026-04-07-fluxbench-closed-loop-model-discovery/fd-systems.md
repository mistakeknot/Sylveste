---
artifact_type: research
subtype: fd-systems
bead: sylveste-s3z6
reviewer: fd-systems
date: 2026-04-07
---
# FluxBench Closed-Loop Model Discovery — Systems Thinking Review

## Findings Index

| ID | Severity | Lens | Section | One-Line Summary |
|----|----------|------|---------|-----------------|
| S1 | P1 | Causal Graph / Hysteresis | F4 Drift Detection | The Claude fallback-to-requalification recovery loop has no modeled escape condition — a demotion storm can lock out all non-Claude models simultaneously. |
| S2 | P1 | Causal Graph / Goodhart | F1 Metric Definitions | Three of five core gate metrics reference Claude output as their baseline anchor, making the benchmark a measure of Claude-similarity rather than review quality. |
| S3 | P1 | Preferential Attachment / Pace Layers | F7 Challenger Slot | Incumbents accumulate runtime data at a rate proportional to their current deployment share; challengers accumulate data only from 1 slot, creating a compounding data-quality divergence that makes promotion harder over time. |
| S4 | P2 | Bullwhip Effect / Pace Layers | F3 + F6 | The store-and-forward → snapshot refresh → recommend_model chain introduces a variable delay between observed model behavior and dispatch decisions, which can cause oscillating over- and under-correction when multiple models drift simultaneously. |
| S5 | P2 | Systems Dynamics / BOTG | F5 Proactive Surfacing | The weekly auto-qualification cycle is the only action path for new entrants; at T=2yr with a mature incumbent pool, no new model will accumulate enough challenger runs to promote before being superseded by the next model generation. |
| S6 | P3 | Schelling Trap / Simple Rules | F2 Fixture Design | Ground-truth fixtures annotated against a Claude baseline risk establishing a consensus equilibrium where the "correct" answer is "what Claude would say," excluding structurally diverse but valid findings from non-Claude review styles. |
| S7 | P3 | Hormesis / Over-Adaptation | F4 + F7 | The 15% drift threshold and 10-run challenger promotion gate are calibrated for the current deployment scale; under stress conditions (rapid API deprecations, model versioning storms) these thresholds produce a requalification queue that exceeds processing capacity. |

---

## Detailed Analysis

### S1 — Demotion Storm with No Escape Valve (P1)

**Section:** F4 Drift Detection, acceptance criteria items 4, 5, and 8.

**Lens:** Hysteresis, Causal Graph.

**The loop as written:**

```
model drifts → demote to "qualifying"
             → Claude fallback assigned for that tier
             → requalification triggered
             → if requalification passes → promote back
             → if provider is mid-rollout, fails again → remains "qualifying"
```

The problem is the third leg. If multiple active models drift in the same sampling window — plausible when a provider does a silent rollout across several model versions simultaneously — all affected tiers fall back to Claude simultaneously. The requalification trigger fires for all of them. The `fluxbench-qualify.sh` pipeline then competes with ongoing reviews for rate-limited provider API access.

The deeper issue is the **hysteresis asymmetry**: demotion requires one drift event (any core metric drops >15%), but promotion requires clearing all five gates plus the 5% recovery band. Once a model is in `qualifying` state during a provider storm, the recovery condition may not be reachable until the provider stabilizes — but the system has no model of "provider instability" as a context that should pause requalification rather than continue generating failures. Each failed requalification extends the state without producing information.

**What is not modeled:** The PRD treats demotion as a local event per model-tier pair. It does not model the system-level effect when the Claude fallback itself is the only active model across multiple tiers. At that point, the diversity hedge (multi-model review) has collapsed to a monoculture, and the drift detection machinery is no longer capable of producing actionable signal because there is nothing to compare against except itself.

**Question to stress-test:** What happens to `cross-family-disagreement-rate` when all tiers fall back to Claude? The metric goes to zero — which looks like perfect agreement, not system failure.

---

### S2 — Measuring Claude-Similarity, Not Review Quality (P1)

**Section:** F1 Metric Definitions (core gates), F2 Qualification Test Fixtures.

**Lens:** Causal Graph, Goodhart's Law (PHILOSOPHY.md calls this out explicitly under "Anti-gaming by design" and "Rotate and diversify").

**The circular dependency:**

The PRD names it directly in the user-supplied context: "3 of 5 core metrics reference Claude." What this creates structurally is:

```
Claude produces baseline findings
  → FluxBench ground-truth derived from Claude baseline (F2)
  → FluxBench scores measure proximity to Claude baseline (F1)
  → Registry rewards models that score high on FluxBench
  → Dispatch favors high-registry models
  → Those models produce findings closer to Claude's
  → Those findings reinforce the ground-truth baseline (F2 calibration)
```

This is a reinforcing loop with Claude as attractor. The system is not measuring "finds real bugs" — it is measuring "agrees with Claude about what constitutes a bug." The distinction becomes critical as model generations diverge: a model that finds a different but valid class of findings (e.g., a model with stronger formal reasoning that catches logic errors Claude misses) will score poorly on finding-recall because its findings do not map to the Claude-anchored ground-truth.

PHILOSOPHY.md states: "Disagreement between models is the highest-value signal." The FluxBench metric structure as designed will systematically suppress that signal by treating inter-model disagreement as a scoring failure rather than as evidence of complementary coverage.

**The Goodhart pressure path:** Once models are aware (via their training data) that FluxBench is the qualification gate, fine-tuned or prompted models will optimize for FluxBench score rather than review quality. The PRD's "Rotate and diversify" principle from PHILOSOPHY.md is not surfaced in the metric design — there is no provision for rotating the baseline anchor or periodically introducing human-only (non-Claude-informed) ground-truth fixtures.

**Question to stress-test:** If a non-Claude model consistently surfaces P0 findings that Claude misses, how does FluxBench currently score that model? Under the `finding-recall` metric (severity-weighted, compared against Claude-anchored ground-truth), those additional findings are invisible — they are not false positives (the model is not wrong), but they are also not counted as recall successes because they were not in the baseline.

---

### S3 — Preferential Attachment Compounds Against Challengers (P1)

**Section:** F7 Challenger Slot, acceptance criteria items 4 and 5.

**Lens:** Preferential Attachment, Pace Layers.

**The data accumulation asymmetry:**

An incumbent qualified model participates in every review assigned to its tier. A challenger participates in exactly 1 slot across all reviews. The promotion gate requires "10+ challenger runs." At low review volume, a challenger might need weeks to accumulate 10 runs. During that window:

- The incumbent continues accumulating real-world performance data.
- The challenger accumulates data from 1 slot per review, on documents the incumbent also reviewed (selection bias: the challenger gets the same documents, not a representative distribution).
- Each incumbent run generates a FluxBench shadow comparison that further calibrates the incumbent's registry entry.
- The challenger's FluxBench scores remain based on synthetic fixtures (F2) until promotion.

Over time, incumbents build increasingly fine-grained registry entries while challengers operate on coarse synthetic fixture scores. The promotion gate ("auto-evaluate after 10+ runs") compares a challenger with 10 real-world data points against an incumbent with potentially thousands. The statistical confidence asymmetry means the gate should require different thresholds for incumbents vs. challengers, but the PRD applies the same five core gates to both.

**The rich-get-richer dynamic at scale:** As the system matures, the most-deployed models will have the highest data density, the most calibrated FluxBench thresholds, and the greatest drift detection sensitivity. New challengers enter against an increasingly optimized baseline. This is a classic preferential attachment effect — the probability of a challenger succeeding decreases as the incumbent pool matures, even if the challenger is objectively better.

**Question to stress-test:** At T=2yr, with 5 incumbents each having 500+ registry entries, what is the expected time-to-promotion for a genuinely superior challenger entering with zero history? The PRD does not model this trajectory.

---

### S4 — Bullwhip Effect Through the Sync-Snapshot Chain (P2)

**Section:** F3 AgMoDB Write-Back, F6 interrank Integration.

**Lens:** Bullwhip Effect, Pace Layers.

**The signal chain:**

```
qualification run → results.jsonl (immediate, local)
                 → fluxbench-sync.sh (periodic, unspecified cadence)
                 → AgMoDB repo commit
                 → interrank snapshot refresh (unspecified cadence)
                 → recommend_model (live queries)
                 → dispatch decisions
```

There are at least two unspecified delays in this chain: the sync interval and the snapshot refresh interval. If both are daily, a qualification result can be up to 48 hours old before it influences dispatch. Under normal conditions this is acceptable. Under degradation conditions, the delay creates a phase mismatch:

A model that drifts will continue being dispatched by recommend_model for up to 48 hours after the drift is detected locally. If drift detection demotes the model in model-registry.yaml immediately (local cache, "immediate" per the architecture diagram), but recommend_model still returns the model as highly ranked because the snapshot has not refreshed, there are now two sources of truth with opposite answers. The PRD does not specify which authority wins for dispatch: local model-registry.yaml or interrank recommend_model.

**The oscillation scenario:** Suppose a model is demoted via drift detection (local), then re-promoted after requalification (local), before the sync has propagated to AgMoDB. The snapshot will reflect the pre-demotion score. When the snapshot does refresh, it may receive a sequence of writes: high score → low score → high score, all arriving in a single batch commit. The AgMoDB schema does not appear to support per-entry versioning — the PRD mentions `qualification_run_id` for idempotency but not for temporal ordering. A snapshot refresh that ingests all three writes may produce an unpredictable final state depending on ordering.

**Question to stress-test:** What does recommend_model return for a model that is currently in `qualifying` state in local registry but `qualified` in the most recent interrank snapshot? Which source of truth does the dispatch logic consult?

---

### S5 — New Entrant Time-to-Promotion Grows Without Bound (P2)

**Section:** F5 Proactive Model Surfacing.

**Lens:** Systems Dynamics / Behavior Over Time Graph, Pace Layers.

**T=0 vs. T=2yr comparison:**

At T=0, the registry has few incumbents, FluxBench baselines are freshly derived, and the challenger pool is small. A new model enters, runs the weekly auto-qualification pipeline against 5-10 F2 fixtures, and promotes in days if it passes.

At T=2yr, the registry has 10-20 incumbents. The weekly pipeline must now:
1. Query interrank for new candidates above threshold.
2. Run each against all F2 fixtures (fixture count may have grown).
3. Score via FluxBench.
4. Compare against calibrated baselines that have drifted over time.
5. For passing candidates, allocate a challenger slot.
6. Wait for 10+ real-world challenger runs before final promotion decision.

Steps 1-4 can execute automatically, but step 5-6 are rate-limited by the challenger slot constraint (1 slot per review). If there are 5 candidates simultaneously in the challenger pipeline, each competing for the single challenger slot, the expected time to 10 runs for any individual candidate is 5x longer. The PRD allocates 1 challenger slot total (F7), with no provision for expanding the slot count as the candidate pool grows.

**The pace layer mismatch:** Model release cycles at major providers (Anthropic, Google, Meta) are accelerating — rough cadence is 3-6 months between significant versions. The FluxBench qualification pipeline requires weeks to months for full promotion. At T=2yr, this gap will mean that new models are superseded by their successors before completing the challenger pipeline. The PRD treats this as a future concern but the architecture does not provide a mechanism for compressing promotion time (e.g., fast-track based on benchmark scores alone, or provisional deployment with ongoing monitoring).

**Question to stress-test:** At what model release cadence does the FluxBench qualification pipeline become a bottleneck that prevents the system from ever deploying any non-incumbent model?

---

### S6 — Consensus Equilibrium in Fixture Annotation (P3)

**Section:** F2 Qualification Test Fixtures, acceptance criteria item 6.

**Lens:** Schelling Trap, Simple Rules.

**The annotation protocol as stated:**

The PRD specifies "Ground-truth validated by human annotation (not Claude-generated baseline alone)" and "calibration script runs all fixtures against Claude baseline and computes threshold baselines." This creates a two-step process where human annotation validates fixture content but Claude's baseline run sets the scoring thresholds.

The Schelling trap is subtle: annotators working in an environment where Claude is the reference model will, over time, unconsciously calibrate their annotations toward findings that Claude reliably surfaces. Findings that require reasoning styles or domain knowledge underrepresented in Claude's training will be systematically under-annotated — not because they are wrong, but because annotators have no independent reference to compare against.

PHILOSOPHY.md's "Disagreement is the highest-value signal" principle cuts the other way here: disagreement between a non-Claude model and the ground-truth should be examined as potential evidence that the ground-truth is incomplete, not automatically scored as a false positive or missed recall.

**The compounding effect:** As FluxBench scores select for Claude-similar models, the review outputs used to calibrate future fixtures will increasingly reflect Claude's epistemic fingerprint. Without a deliberate protocol for introducing findings from structurally diverse sources (human reviewers who do not use Claude, models from different training lineages), the fixture set will converge to a local maximum that is not the global quality optimum.

---

### S7 — Threshold Calibration for Current Conditions, Not Storm Conditions (P3)

**Section:** F4 Drift Detection, F7 Challenger Slot.

**Lens:** Hormesis, Over-Adaptation.

**The calibration implicit in current numbers:**

- Drift threshold: 15% core metric drop from qualified baseline.
- Drift hysteresis band: 5% recovery margin.
- Challenger promotion gate: 10+ runs.
- Sample rate: 1-in-10 reviews.

These numbers are presented as configurable (via budget.yaml) but calibrated against no stated stress scenario. The PHILOSOPHY.md principle "optimize for time-to-recovery, not mean-time-between-failures" suggests the system should be able to absorb a degradation event and recover quickly. But the 15% threshold, 5% hysteresis, and 1-in-10 sample rate are each independently reasonable under steady-state conditions — they have not been analyzed for their combined behavior under stress.

**The over-adaptation risk:** A system perfectly calibrated for "occasional individual model drift" will produce a requalification queue that exceeds processing capacity when multiple models drift simultaneously. The PRD does not specify a maximum requalification queue depth or a priority ordering for the queue. Under a provider-wide silent update (e.g., OpenAI updates all GPT-4 variants simultaneously), all instances using those models would trigger drift detection in the same 1-in-10 sampling window, generating a burst of requalification jobs that compete with production review workload for API capacity.

**The hormesis angle:** Periodic deliberate stress tests — artificially triggering drift on a single model to verify the recovery path works end-to-end — would build confidence in the recovery loop without risking production stability. The PRD's success metrics ("Drift detection catches a simulated 20% regression within 2*N reviews") describe a single-model test. Multi-model simultaneous drift is not in scope, and a system that passes single-model stress tests but fails multi-model scenarios is over-adapted to the test conditions.

---

## Cross-Cutting Observation

The five feedback loops named in the review context (qualification, catalog, recovery, exploration, human-in-loop) are individually well-conceived. The systemic gap is in their **interaction**. When loops 1, 3, and 4 activate simultaneously — a drift event that demotes an incumbent while a challenger is mid-pipeline and the catalog loop has a stale snapshot — the system state is not analyzed anywhere in the PRD. The delivery order (F2 → F1 → F3 → F4+F5 → F6+F7) deploys these loops in sequence, which means their interaction effects will first be observable only after all seven features ship. Building in a multi-loop integration test before F6+F7 go live would make the interaction behavior visible earlier, when it is cheaper to correct.

This observation is technically adjacent (fd-architecture crossover) but the root cause is systemic: the PRD analyzes each loop in isolation and does not include a combined-state scenario for when multiple loops are active simultaneously.

<!-- flux-drive:complete -->
