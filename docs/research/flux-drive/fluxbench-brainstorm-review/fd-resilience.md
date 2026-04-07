### Findings Index
- P1 | RES-1 | "FluxBench Metrics" | Claude baseline is a single point of failure — if Claude changes behavior, all scores invalidate
- P2 | RES-2 | "Write-Back Mechanism" | No degradation path when AgMoDB API is unavailable — qualification results are lost
- P2 | RES-3 | "Proactive Surfacing" | Weekly qualification of all candidates is unbounded — cost scales linearly with model count
- P2 | RES-4 | "Drift Detection" | Recovery path from "qualifying" back to "qualified" is unspecified — no SLA or timeout
Verdict: needs-changes

### Summary

The brainstorm designs for the happy path but underspecifies failure modes and recovery. The most critical resilience gap is the Claude baseline dependency: three of four core metrics measure performance relative to Claude, making the entire benchmark brittle to Claude model updates. There's no degradation strategy for AgMoDB unavailability, no cost bound on weekly qualification runs, and no defined recovery timeline for demoted models. The system is resilient in concept (dual drift modes, dual surfacing) but fragile in execution because every capability depends on external services with no fallback.

### Issues Found

1. **P1 — RES-1: Claude baseline as single point of failure**. Finding recall, severity accuracy, and persona adherence all require a Claude baseline run. If Claude is unavailable (API outage, rate limit, subscription lapse), no qualification or drift detection can run. If Claude changes behavior (model update from claude-sonnet-4-6 to a successor), all historical FluxBench scores become incomparable to new scores — the measuring stick changed. This isn't just a bias risk (covered by fd-systems); it's a resilience risk. The system has zero redundancy on its most critical dependency.

   Mitigation options that should be evaluated:
   - Cache the last N Claude baseline runs and use them as reference when Claude is unavailable
   - Use multiple baseline models (Claude + one other) and average for robustness
   - Version the baseline: tag each FluxBench score with the baseline model version so scores are only compared within the same baseline generation

2. **P2 — RES-2: AgMoDB write failure causes silent data loss**. The brainstorm describes `POST /api/fluxbench/report` but doesn't specify what happens if the write fails. Qualification runs are expensive (20+ shadow runs). If the API call fails after completing all shadow runs, those results are lost. There's no local persistence, no retry queue, no write-ahead log. The write-back should follow a store-and-forward pattern: write results locally first (e.g., to `model-registry.yaml` or a local FluxBench results file), then forward to AgMoDB asynchronously.

3. **P2 — RES-3: Unbounded qualification cost**. The weekly schedule "For each new candidate, run 3 synthetic qualification tasks." As the model landscape grows (AgMoDB tracks hundreds of models), the number of new candidates per week could be large. Each qualification task requires 20 shadow runs (per the write-back schema example). There's no budget cap, no priority ordering, and no circuit breaker. The brainstorm should specify: "Max N candidates per weekly cycle, prioritized by interrank score, with a total token budget of X."

4. **P2 — RES-4: Demotion without recovery SLA**. When drift detection fires, a model is demoted to "qualifying" status and interflux falls back to Claude. But the requalification process isn't specified. How many shadow runs are needed? How long does it take? What if requalification fails — does the model stay in "qualifying" limbo forever? There should be a state machine: `qualified → drift_detected → requalifying (max 7 days) → qualified | disqualified`. The `disqualified` state prevents models from cycling endlessly between drift detection and requalification.

### Improvements

1. **IMP-1: Add a store-and-forward write pattern** — persist FluxBench results locally before attempting AgMoDB write. This decouples qualification from API availability.

2. **IMP-2: Budget-cap the weekly discovery cycle** — "max 5 candidates per week, max 100K tokens per cycle." This prevents cost runaway as the model landscape grows.

3. **IMP-3: Define a model status state machine** with explicit transitions and timeouts: `new → qualifying → qualified → drift_detected → requalifying → qualified | disqualified`.

4. **IMP-4: Version the Claude baseline** — every FluxBench score should record which Claude model version produced the baseline. Scores from different baseline versions should not be directly compared.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 4 (P0: 0, P1: 1, P2: 3)
SUMMARY: The system designs for the happy path without specifying degradation for AgMoDB outages, recovery timelines for demoted models, or cost bounds on weekly qualification — and the Claude baseline is a single point of failure for the entire benchmark.
---
<!-- flux-drive:complete -->
