### Findings Index
- P1 | PER-1 | "FluxBench Metrics" | Format compliance is a proxy metric — high format compliance does not imply high review quality
- P1 | PER-2 | "FluxBench Metrics" | Claude monoculture risk — single-source baseline creates systematic blind spots
- P2 | PER-3 | "FluxBench Metrics" | Persona adherence via LLM-as-judge is circular — an LLM judging another LLM's persona performance
- P2 | PER-4 | "FluxBench Metrics" | Missing metrics: false positive rate, actionability, and context utilization are not measured
- P2 | PER-5 | "Write-Back Mechanism" | Reification risk — 8 numeric scores become "the truth" about a model's review capability
Verdict: needs-changes

### Summary

The brainstorm's 8 FluxBench metrics measure what's mechanically measurable (format compliance, recall against a baseline, latency) rather than what matters most for review quality (are the findings actionable? do they lead to better code?). Format compliance is the weakest metric — a model producing perfectly formatted empty findings would score 100%. The Claude baseline creates a monoculture where all models are evaluated against a single perspective, systematically missing any findings Claude itself doesn't surface. Persona adherence scored by LLM-as-judge introduces circularity. The most important gaps are: no measure of false positive rate (how many findings are noise), no measure of actionability (can a developer act on the finding?), and no measure of context utilization (did the model use the provided context or hallucinate?).

### Issues Found

1. **P1 — PER-1: Format compliance measures form, not substance**. The brainstorm defines format compliance as "% of runs producing valid Findings Index (header, pipe-delimited lines, Verdict)." This is the easiest metric to achieve and the least informative about review quality. A model could produce:
   ```
   ### Findings Index
   - P2 | 1 | "Overview" | Consider adding more tests
   Verdict: safe
   ```
   This scores 100% on format compliance while providing zero value. Format compliance is necessary but not sufficient — it should be a binary gate (pass/fail), not a scored metric with a threshold. Including it as one of 4 core gate metrics gives it disproportionate weight relative to its information content.

2. **P1 — PER-2: Claude baseline creates systematic blind spots**. Finding recall is measured as "% of Claude baseline findings also found by candidate." This means: (a) findings Claude misses are invisible to the benchmark — a model that finds issues Claude doesn't gets no credit; (b) the benchmark systematically favors models that think like Claude. The cross-family disagreement rate (extended metric) partially addresses this, but it's NOT a gate metric — it's informational only. The brainstorm acknowledges Claude as the baseline but doesn't consider what happens when Claude is wrong. If Claude produces a false positive finding, every candidate that correctly ignores it gets penalized on recall.

   This is a map/territory confusion: the brainstorm treats "Claude's findings" as "the correct findings" (the territory), when they're actually "one model's interpretation" (a map). The gap between these is not measured.

3. **P2 — PER-3: Persona adherence LLM-as-judge circularity**. Persona adherence is scored as "Does the model stay in domain persona vs generic analysis (0-1 scale, LLM-judged)." The judge is presumably Claude (or another LLM). This creates circularity: an LLM evaluating whether another LLM's output "feels" domain-specific. LLMs are pattern matchers — they may score highly on surface-level domain vocabulary while missing genuine domain reasoning. A model that peppers its output with jargon ("module boundary violation", "coupling antipattern") will score high on persona adherence without necessarily understanding the concepts. The metric conflates style with substance.

4. **P2 — PER-4: Missing metrics that matter more**. The 8 metrics don't include:
   - **False positive rate**: What fraction of a model's findings are incorrect or irrelevant? A model with 100% recall but 80% false positive rate is worse than one with 60% recall and 5% false positives. This is arguably more important than finding recall.
   - **Actionability**: Can a developer act on the finding? Does it cite specific files, lines, and suggest a fix? Or is it vague ("consider improving error handling")?
   - **Context utilization**: Did the model read and reference the provided codebase context, or did it hallucinate file paths and patterns? This is measurable by checking whether cited files/lines actually exist.
   - **Finding novelty**: Does the model surface findings that other models AND Claude all miss? This is the highest-value signal and the hardest to measure.

5. **P2 — PER-5: Reification of numeric scores**. Once 8 metrics are published as AgMoDB benchmarks, they become "the official FluxBench score." Decision-makers will compare models by their FluxBench numbers without considering what the numbers represent. A model with FluxBench scores [0.95, 0.72, 0.81, 0.68, 0.88, 0.15, 2400, 0.42] looks precisely quantified, but the numbers mask substantial measurement uncertainty (sample size of 20 shadow runs, LLM-as-judge subjectivity, Claude baseline variability). The brainstorm should include confidence intervals or note the number of shadow runs alongside each score.

### Improvements

1. **IMP-1: Downgrade format compliance from scored gate metric to binary gate** — pass/fail at 90%, but don't include it in the numeric score. It's a minimum bar, not a quality signal.

2. **IMP-2: Add false positive rate as a core gate metric** — measure "% of candidate's findings that are NOT in the Claude baseline AND are incorrect when manually reviewed." Even a small sample of manual review would calibrate this.

3. **IMP-3: Add confidence intervals to FluxBench scores** — report "finding recall: 0.72 +/- 0.08 (n=20)" so downstream consumers understand measurement precision.

4. **IMP-4: Consider a human-validated calibration set** — a small set (5-10) of review tasks with human-annotated ground truth findings. This reduces Claude baseline dependency and provides a Goodhart-resistant anchor.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 5 (P0: 0, P1: 2, P2: 3)
SUMMARY: The metrics measure what's mechanically measurable (format, recall against Claude) rather than what matters (actionability, false positive rate, context utilization). Claude as sole baseline creates systematic blind spots and map/territory confusion.
---
<!-- flux-drive:complete -->
