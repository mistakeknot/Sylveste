---
artifact_type: cuj
stage: design
cuj_id: CUJ-03
title: Researcher runs an early exit experiment campaign
---

# CUJ-03: Researcher Runs an Early Exit Experiment Campaign

## Actor

**Experiment researcher** -- a developer or data scientist using interlab (the Demarch experiment platform) to measure inference optimizations. They design campaigns with explicit baselines, treatments, success metrics, and kill criteria. In the interfere context, they are testing whether esoteric optimization techniques produce real speedups without quality regression.

## Trigger

The researcher wants to measure the tok/s improvement from entropy-based early exit on coding tasks. The EarlyExitHook is implemented but unvalidated -- it needs a controlled experiment to determine whether skipping downstream layers when the model is highly confident actually improves throughput without degrading output quality.

## Preconditions

1. interfere server is running with a model loaded (e.g., Qwen3-30B Q4_K_M)
2. interlab is installed and configured for interfere campaigns
3. A representative task corpus exists: 100+ coding tasks spanning C1/C2 complexity tiers (the same distribution Clavain will route in production)
4. interspect is available for quality scoring (or a quality evaluator is configured)
5. Baseline performance numbers do not yet exist (this campaign will establish them)
6. EarlyExitHook is available in the inference pipeline with configurable threshold and enable/disable toggle

## Steps

1. **Configure the experiment.** The researcher defines the campaign via interlab:
   - **Hypothesis:** Entropy-based early exit at threshold 0.95 will increase tok/s by 1.3x on C2 coding tasks without measurable quality regression.
   - **Independent variable:** EarlyExitHook enabled vs disabled
   - **Dependent variables:** tok/s (throughput), TTFT (time to first token), quality score (interspect match rate vs reference output), exit rate (fraction of tokens where early exit triggered)
   - **Kill criterion:** Quality score drops below 90% match rate, OR tok/s improvement is less than 1.1x (not worth the complexity)
   - **Sample size:** 100 tasks per arm (baseline and treatment), drawn from the representative corpus

2. **Run baseline campaign.** With EarlyExitHook disabled (`enabled=False`), the researcher runs the full task corpus through interfere:
   - Each task is sent to `/v1/chat/completions` as a streaming request
   - For each task, the researcher records: total tokens generated, wall-clock generation time (tok/s), TTFT, thermal state at start, and the full output text
   - The output text is scored for quality against reference outputs (cloud model baseline or human-validated gold set)
   - Baseline metrics are aggregated: median tok/s, p95 TTFT, mean quality score
   - Results are logged to interlab as the baseline arm

3. **Enable the early exit hook.** The researcher activates the treatment:
   - EarlyExitHook is enabled with `threshold=0.95` (the model must be >95% confident in the next token for early exit to trigger)
   - The hook's stats counters are reset via `reset_stats()`
   - The inference pipeline is configured to check `EarlyExitHook.check(logits)` at each generation step and skip remaining layers when `should_exit=True`

4. **Run treatment campaign.** With EarlyExitHook enabled, the researcher runs the same task corpus:
   - Same 100 tasks, same prompts, same model, same temperature
   - Same metrics recorded: tok/s, TTFT, quality score, plus the new metric: exit_rate from `EarlyExitHook.exit_rate`
   - Thermal conditions are monitored to ensure comparability (if thermal state differs significantly between runs, the comparison is flagged)
   - Results are logged to interlab as the treatment arm

5. **Compare metrics.** The researcher analyzes the campaign results:
   - **Primary metric:** tok/s improvement ratio (treatment median / baseline median). Target: >= 1.3x.
   - **Quality guard:** Quality score difference (treatment mean - baseline mean). Must be within -2% (no significant regression).
   - **Secondary metrics:** TTFT comparison, exit rate distribution across tasks, correlation between task complexity and exit rate
   - **Statistical tests:** Confidence interval on tok/s ratio; paired comparison on quality scores per task
   - interlab dashboard shows side-by-side comparison with pass/fail against the predefined criteria

6. **Decide keep or kill.** Based on the campaign results:
   - **Keep:** tok/s improvement >= 1.3x AND quality regression < 2%. The EarlyExitHook is promoted from experiment to default-on in the inference pipeline. The threshold (0.95) becomes the production default. Results are published as interlab evidence.
   - **Iterate:** tok/s improvement is between 1.1x and 1.3x with no quality regression. Try adjusting the threshold (0.90, 0.85) to increase exit rate, and re-run the treatment arm.
   - **Kill:** Quality regression exceeds the kill criterion (>10% match rate drop), OR tok/s improvement < 1.1x even after threshold tuning. The EarlyExitHook is disabled and the experiment is archived with findings. The "inference laboratory" thesis requires at least 2 of 13 techniques to work (per MISSION.md Bet 4); one failure is expected and acceptable.

## Success Criteria

- Baseline and treatment campaigns both complete on the full 100-task corpus
- Metrics are logged to interlab with full provenance (model, quantization, hardware, thermal state, timestamp)
- The comparison produces a clear signal: either the improvement meets the 1.3x target or it does not
- Quality scores are computed for every task in both arms, enabling paired comparison
- The keep/kill decision is made based on data, not intuition
- If kept, the EarlyExitHook configuration is documented and the threshold is justified by the experiment results
- If killed, the findings are archived and the reason is recorded (this is a valid and valuable outcome)

## Failure Modes

| Failure | Detection | Recovery |
|---------|-----------|----------|
| **Thermal variance between runs** | ThermalMonitor shows different pressure levels during baseline vs treatment | Flag comparison as unreliable. Re-run both arms during thermal-stable period (early morning, or with active cooling). |
| **Quality evaluator disagrees with human judgment** | Spot-check reveals interspect scores do not match human assessment of output quality | Calibrate the quality evaluator on a subset of human-judged tasks before trusting automated scores. |
| **Early exit never triggers** | `EarlyExitHook.exit_rate` is near zero even with threshold at 0.95 | The model is rarely confident enough. Try lower thresholds (0.90, 0.85). If still near zero, the model's logit distribution may not be suitable for this technique. |
| **Early exit triggers too often** | Exit rate > 80% with quality regression | Threshold is too low. Raise to 0.98 or 0.99. If quality still regresses at high exit rates, the technique does not work for this model. |
| **Model OOM during campaign** | MemoryError mid-run; Metal worker crashes | Campaign is partially complete. Restart worker, resume from the last completed task. Ensure no memory leaks in the inference pipeline (check `mx.metal.get_active_memory()` between tasks). |
| **Non-deterministic results** | High variance in tok/s across runs of the same task | Increase sample size. Pin temperature to 0.0 for reproducibility (at the cost of diversity). Report confidence intervals, not point estimates. |
| **interlab unavailable** | Campaign logging fails | Record metrics to local CSV as fallback. Import into interlab when available. The experiment data is more important than the tooling. |

## Related Features

- **EarlyExitHook** (`server/experiments/early_exit.py`) -- the entropy-based confidence check being evaluated; threshold, enabled toggle, exit_rate stats
- **InferenceEngine** (`server/inference.py`) -- the generation loop where the hook is inserted
- **interlab campaigns** -- the experiment platform that structures baseline/treatment/metrics/kill-criteria
- **interspect evidence** -- quality scoring system used to evaluate output quality
- **ThermalMonitor** (`server/thermal.py`) -- thermal state tracking for experiment validity
- **ReservoirReadout** (`server/experiments/reservoir_routing.py`) -- a separate experiment hook (not used in this CUJ but part of the same experiment pipeline)
- **MetalWorker** (`server/metal_worker.py`) -- subprocess that runs inference; memory monitoring via `mx.metal.get_active_memory()` and `get_peak_memory()`
