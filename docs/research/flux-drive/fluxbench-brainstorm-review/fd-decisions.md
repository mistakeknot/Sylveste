### Findings Index
- P1 | DEC-1 | "FluxBench Metrics" | Threshold values are ungrounded — no empirical basis or calibration plan
- P1 | DEC-2 | "Key Decisions" | Over-commitment: 3 capabilities (write-back + drift + surfacing) designed simultaneously without MVP validation
- P2 | DEC-3 | "Why This Approach" | Anchoring on "full AgMoDB loop" without evaluating intermediate alternatives
- P2 | DEC-4 | "FluxBench Metrics" | Finding recall at 60% threshold is too low — permits models that miss 40% of findings
- P2 | DEC-5 | "Drift Detection" | 15% drift threshold is arbitrary — no sensitivity analysis on threshold choice
- P2 | DEC-6 | "Open Questions" | Persona adherence LLM-as-judge cost acknowledged but no decision framework for resolution
Verdict: needs-changes

### Summary

The brainstorm makes several strong decisions (per-metric gates over composite scores, dual surfacing modes) but commits prematurely to others. The threshold values (90%, 60%, 70%, 0.6, 15%) appear to be intuition-based with no calibration data or plan to calibrate. The scope is ambitious — three capabilities designed in one brainstorm — without identifying which capability alone would prove the concept. The "Why This Approach" section presents rationale for chosen approaches but doesn't enumerate the alternatives that were considered and rejected, making it difficult to evaluate whether the right trade-offs were made.

### Issues Found

1. **P1 — DEC-1: Threshold values lack empirical grounding**. The brainstorm sets specific thresholds: format compliance >= 90%, finding recall >= 60%, severity accuracy >= 70%, persona adherence >= 0.6, drift threshold > 15%. None of these have stated empirical basis. Were they derived from existing qualification data? Are they based on what "feels right"? The risk is anchoring: once published in AgMoDB as benchmark thresholds, they become sticky. If they're wrong (too strict excludes viable models; too lenient admits poor ones), the feedback loop reinforces the error. The brainstorm should include a calibration plan: "Run FluxBench against N existing models, plot the score distribution, set thresholds at the Nth percentile."

2. **P1 — DEC-2: Three capabilities without MVP validation**. The brainstorm designs write-back, drift detection, AND proactive surfacing as a single system. Each is independently complex. The minimum viable experiment is: run FluxBench scoring on 5 models, manually compare results to current qualification, and see if the 8 metrics correlate with actual review quality. This can be done with a local JSON file — no AgMoDB API, no drift detection, no SessionStart hooks. The brainstorm jumps from "we should have a benchmark" to "we should have a fully integrated closed-loop system." The risk is building integration infrastructure before validating that the benchmark itself is useful.

   Reversibility analysis:
   - Write-back API: Medium reversibility — API can be deprecated, but benchmark definitions in AgMoDB are harder to remove once other consumers depend on them.
   - Drift detection: High reversibility — can be disabled without affecting other components.
   - Proactive surfacing: High reversibility — SessionStart hook can be removed cleanly.
   - FluxBench metric definitions: Low reversibility — once published as AgMoDB benchmarks with `category: "fluxbench"`, changing metric names or semantics breaks downstream consumers.

3. **P2 — DEC-3: Missing alternative evaluation**. The "Why This Approach" section argues for three choices: full AgMoDB loop (over sidecar), API endpoint (over direct DB), and dual drift modes (over single). But it doesn't present the alternatives as a structured comparison. For example:
   - Option A: Local FluxBench JSON file + interrank reads it directly. Pros: no API dependency, immediate. Cons: not in AgMoDB, interrank needs custom code.
   - Option B: JSONL commit to AgMoDB repo (like existing scrapers). Pros: uses existing pipeline. Cons: batch, not real-time.
   - Option C: REST API write-back. Pros: real-time, clean separation. Cons: requires new AgMoDB capability.
   
   The brainstorm chose C without presenting A and B as explicit alternatives. This makes the decision harder to evaluate.

4. **P2 — DEC-4: Finding recall threshold is too permissive**. A 60% finding recall threshold means a model can miss 40% of findings that Claude detects and still qualify. For a code review tool, missing 40% of issues is significant. If Claude finds 10 issues and a candidate finds 6, the candidate misses 4 — some of which could be P0/P1. The threshold should either be higher (75-80%) or weighted by severity: missing a P0 finding should fail qualification regardless of overall recall.

5. **P2 — DEC-5: Drift threshold lacks sensitivity analysis**. The 15% drop threshold for triggering requalification is a single number without analysis of false positive/negative rates. A 14% drop is ignored; a 16% drop triggers full requalification. What if normal variance between reviews is 10-12%? The threshold should be set based on the observed variance in FluxBench scores across repeated runs on the same model (measurement noise), not picked as a round number.

6. **P2 — DEC-6: Persona adherence cost not resolved**. The brainstorm identifies "LLM-as-judge is expensive" and asks "Should we use Claude Haiku for this or find a heuristic proxy?" but provides no decision framework. This is a key architectural choice: if persona adherence is too expensive to measure on every qualification run, it might be dropped from the core gate metrics. If it stays, the cost needs to be budgeted. The brainstorm should state: "If LLM-as-judge costs > X per qualification run, use heuristic proxy instead."

### Improvements

1. **IMP-1: Define an MVP scope** — FluxBench scoring only, local JSON output, manual comparison against current qualification results. Validate the metrics before building integration.

2. **IMP-2: Add a calibration phase** — run FluxBench against 5-10 models currently used by interflux, use the score distributions to set thresholds empirically.

3. **IMP-3: Weight finding recall by severity** — missing a P0 finding should count more than missing a P2. Consider: `weighted_recall = sum(severity_weight * found) / sum(severity_weight * total)` with P0=4, P1=2, P2=1.

4. **IMP-4: Add an alternatives matrix** to the "Why This Approach" section, even if brief, so future readers understand what was rejected and why.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 6 (P0: 0, P1: 2, P2: 4)
SUMMARY: Threshold values lack empirical basis and the brainstorm over-commits to full integration before validating that the 8-metric benchmark itself correlates with review quality. An MVP-first approach with a calibration phase would reduce risk.
---
<!-- flux-drive:complete -->
