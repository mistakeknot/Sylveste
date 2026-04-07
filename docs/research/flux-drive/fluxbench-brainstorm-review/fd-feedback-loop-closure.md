### Findings Index
- P1 | FLC-1 | "Drift Detection" | No hysteresis band — 15% threshold for fire has no corresponding clear threshold
- P1 | FLC-2 | "FluxBench Metrics" | Open-loop scoring — FluxBench measures output quality but has no actuator feedback to verify that model selection actually improved review quality
- P2 | FLC-3 | "Drift Detection" | Integral windup risk — repeated drift detections with failed requalifications have no floor
- P2 | FLC-4 | "Drift Detection" | Nyquist violation — 1-in-10 sampling cannot detect drift patterns faster than ~20 review cycles
- P2 | FLC-5 | "FluxBench Metrics" | Fixed setpoints — qualification thresholds don't adapt to population distribution
Verdict: needs-changes

### Summary

Viewed as a control system, FluxBench has a sensor (qualification runs), a controller (threshold-based scoring), and an actuator (interrank model selection). But the loop isn't truly closed: there's no feedback from the actuator's effect on the plant (actual review quality perceived by users). The drift detection subsystem lacks hysteresis (oscillation risk between qualified/qualifying states), has no integral windup protection (a model stuck in requalification can be retried indefinitely), and the 1-in-10 sampling rate may violate Nyquist conditions for detecting fast-moving drift patterns.

### Issues Found

1. **P1 — FLC-1: No hysteresis in drift detection**. The brainstorm specifies "If any core metric drops >15% from baseline, flag for requalification." But it doesn't specify a re-qualification clearance threshold. If a model's format compliance drops from 95% to 80% (>15% relative drop), it's flagged. After requalification, if it scores 82% (above the 90% gate), it's re-qualified. But the next sample might show 79% (below the drift threshold again), triggering another requalification. Without a hysteresis band (e.g., "flag at >15% drop, clear only when recovered to within 5% of baseline"), the model oscillates between qualified and qualifying states. In control systems, this is the classic thermostat oscillation problem.

   Concrete scenario: Model X qualified with format compliance = 95%. Drift threshold fires at < 80.75% (15% below 95%). Requalification passes at 82%. Next sample: 79%. Drift fires again. The model cycles between states every 10-20 reviews.

2. **P1 — FLC-2: Loop isn't closed at the output**. The brainstorm closes the loop at the model selection level (FluxBench scores → interrank recommendation → model usage). But it doesn't close the loop at the outcome level: does selecting a higher-FluxBench-scoring model actually produce better reviews? There's no sensor on the plant output. The system assumes that FluxBench metrics correlate with review quality, but this is the core hypothesis that should be validated, not assumed.

   In control theory terms: the system has a reference signal (FluxBench thresholds), a controller (scoring algorithm), and an actuator (model selection). But the plant output (actual review quality) is unobserved. The loop is closed in the model space but open in the quality space. A true closed loop would include a quality sensor — e.g., tracking how often users accept/reject findings from different models, or measuring finding survival rate in code changes.

3. **P2 — FLC-3: Integral windup on repeated drift**. If a model repeatedly fails requalification, the brainstorm doesn't describe what happens. Each drift event writes a new FluxBench report with `metadata.trigger: "drift"`, but there's no escalation or dampening. The system will keep trying to requalify the model on every Nth review (sample-based drift) or on every version bump (trigger-based). There's no "give up after K attempts" backoff. In control theory, this is integral windup: the error signal accumulates without a reset mechanism.

   Fix: After N consecutive failed requalifications (e.g., 3), move the model to a "suspended" state that requires manual re-enablement or a significant version bump to re-enter qualification.

4. **P2 — FLC-4: Sampling rate may violate Nyquist for fast drift**. The 1-in-10 sampling rate means the system can detect drift patterns with a period of >= ~20 review cycles (Nyquist: 2x the sampling interval). A model that degrades and recovers within a 10-review window would be invisible to the sample-based detector. The version-triggered detector helps for known updates but not for silent fluctuations. If a provider A/B tests model variants (routing 50% of traffic to a new checkpoint), the degradation would be intermittent and potentially undetectable at 1-in-10 sampling.

5. **P2 — FLC-5: Thresholds should be adaptive, not fixed**. The qualification thresholds (90% format compliance, 60% recall, etc.) are fixed setpoints. In a healthy control system, setpoints adapt to the process capability. If the top 5 models all achieve >95% format compliance, the 90% threshold is too lenient — it admits models significantly below the frontier. Conversely, if no model achieves >70% severity accuracy, the 70% threshold blocks everything. Adaptive thresholds (e.g., "pass if within 1 standard deviation of the qualified model population mean") would track the actual model landscape.

### Improvements

1. **IMP-1: Add hysteresis to drift detection** — "flag when metric drops >15% below baseline; clear only when metric recovers to within 5% of baseline." This prevents oscillation.

2. **IMP-2: Add an outcome sensor** — even a simple one. Track the ratio of review findings that lead to code changes (finding survival rate) per model. This closes the loop at the quality level, not just the score level.

3. **IMP-3: Add windup protection** — after 3 consecutive failed requalifications, suspend the model. Require a version bump or manual intervention to re-enter.

4. **IMP-4: Consider adaptive thresholds** for v2 — set qualification gates relative to the current qualified model population, not as absolute numbers.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 5 (P0: 0, P1: 2, P2: 3)
SUMMARY: The feedback loop is closed at the model-selection level but open at the review-quality level. Drift detection lacks hysteresis (oscillation risk) and windup protection, and the 1-in-10 sampling rate may miss fast drift patterns.
---
<!-- flux-drive:complete -->
