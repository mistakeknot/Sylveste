### Findings Index
- P1 | SYS-1 | "FluxBench Metrics" | Reinforcing loop: FluxBench scores drive selection, selection drives training data, training data drives scores
- P1 | SYS-2 | "Drift Detection" | Detection latency for silent drift is unbounded — 1-in-10 sampling has no worst-case guarantee
- P2 | SYS-3 | "FluxBench Metrics" | Goodhart's Law — 8 fixed metrics become optimization targets for model providers
- P2 | SYS-4 | "Proactive Surfacing" | Preferential attachment: early-qualified models accumulate more usage data, reinforcing their position
- P2 | SYS-5 | "Write-Back Mechanism" | No staleness decay — FluxBench scores persist indefinitely without re-confirmation
Verdict: needs-changes

### Summary

The brainstorm correctly identifies the need for a closed feedback loop, but the systems dynamics analysis is incomplete. The primary risk is a reinforcing loop where FluxBench scores drive model selection, which drives the review corpus that future qualification runs draw from — models that score well get used more, generating data that confirms their scores. The drift detection mechanism has no worst-case detection latency bound (a model could silently degrade for 100+ reviews before the 1-in-10 sample catches it). The fixed metric set is vulnerable to Goodhart's Law, and there's no score decay mechanism to prevent stale qualifications from persisting indefinitely.

### Issues Found

1. **P1 — SYS-1: Self-reinforcing qualification loop**. The brainstorm describes a loop: interflux qualifies models → scores go to AgMoDB → interrank recommends qualified models → interflux uses those models → models produce review data → data feeds back into future qualification comparisons. This is a reinforcing loop with no balancing mechanism. A model that passes qualification will be used more frequently, generating a larger corpus of "normal" output that the next qualification round compares against. Over time, the system converges on whatever models were first qualified, regardless of whether better alternatives exist. The weekly "discover new candidates" schedule is intended to counter this, but it only adds candidates — it doesn't re-evaluate whether the baseline expectation should shift.

   The missing balancing loop is: periodic forced re-evaluation of ALL qualified models against each other, not just against the Claude baseline. Without this, the system stabilizes at a local optimum.

2. **P1 — SYS-2: Unbounded detection latency for silent drift**. The 1-in-10 sampling rate means on average, a model gets shadow-tested every 10 reviews. But "on average" hides long tails. With geometric distribution, there's a 35% chance of going 10+ reviews without being sampled, and a 12% chance of 20+ reviews. For a model used once per day, that's potentially 20+ days of silent degradation before detection. The brainstorm doesn't specify a maximum detection window. A balancing control would be: "if a model hasn't been sampled in N reviews, force the next review to include a shadow run."

3. **P2 — SYS-3: Goodhart's Law on fixed metric set**. The 8 metrics are specific and measurable, which makes them gameable. Format compliance (pipe-delimited, header, Verdict) is trivially optimizable — a model fine-tuned on interflux output format will score 100% on this metric without necessarily producing better reviews. Persona adherence scored by LLM-as-judge is also gameable: a model that uses domain jargon aggressively will score high on persona without genuine domain understanding. The brainstorm notes "contaminationRisk: low (task-specific, not memorizable)" but this assessment assumes providers don't have access to the qualification prompts. If FluxBench becomes public (as AgMoDB data), the task prompts become de facto training targets.

4. **P2 — SYS-4: Preferential attachment in model selection**. Models qualified early accumulate more review history, more FluxBench data points, and more trust. interrank's recommendation algorithm likely weighs data freshness and volume. New candidates start with 3 synthetic qualification tasks (per the weekly schedule) while incumbents have hundreds of production data points. This creates a rich-get-richer dynamic where incumbents are sticky even if a new model would outperform them. The brainstorm doesn't describe how incumbent and challenger models are compared on equal footing.

5. **P2 — SYS-5: No score decay or expiry**. FluxBench scores have `freshnessType: "continuous"` in the AgMoDB definition, but the actual refresh mechanism depends on drift detection (sample-based or version-triggered). If neither fires — because the model isn't used often enough to be sampled, and the provider doesn't bump versions — the score persists indefinitely. A model qualified 6 months ago with a high score will still be recommended, even though the underlying model may have shifted through silent updates that fell between sampling windows. There's no time-based decay or mandatory re-qualification cadence.

### Improvements

1. **IMP-1: Add a mandatory re-qualification cadence** (e.g., every 30 days regardless of drift signals). This acts as a balancing loop against score staleness.

2. **IMP-2: Add a sampling guarantee**: "if a model hasn't been shadow-tested in 2*N reviews, force a sample." This bounds the worst-case detection latency.

3. **IMP-3: Rotate or expand the metric set periodically**. Even adding one new metric per quarter makes it harder for providers to over-fit to the exact benchmark suite.

4. **IMP-4: Include a "challenger slot"** in model selection — always reserve one agent slot for the highest-scoring unqualified candidate, so new models get production exposure regardless of incumbent advantage.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 5 (P0: 0, P1: 2, P2: 3)
SUMMARY: The closed-loop design has a self-reinforcing qualification dynamic with no balancing mechanism, unbounded drift detection latency, and Goodhart's Law vulnerability in the fixed 8-metric set.
---
<!-- flux-drive:complete -->
