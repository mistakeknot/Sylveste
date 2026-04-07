### Findings Index
- P1 | MD-1 | "Question" | Cross-provider agreement should weight higher than same-provider agreement in synthesis — but the current deduplication algorithm has no provider attribution
- P2 | MD-2 | "Current Architecture" | Sycophancy detection in reaction round is calibrated for Claude-Claude dynamics — cross-model sycophancy patterns are qualitatively different
- P2 | MD-3 | "Question" | Disagreement taxonomy is missing — not all model divergence is signal; format interpretation differences are noise
- P2 | MD-4 | "Question" | Training data temporal divergence creates a hidden signal — models trained on different data cutoffs disagree on recently-changed best practices
- P3 | MD-5 | "Current Architecture" | Convergence scoring in expansion.md could leverage provider diversity as a first-class expansion signal
Verdict: needs-changes

### Summary

The document's insight that "disagreements between Claude and DeepSeek on the same finding might be more meaningful than agreement between two Claude agents" is the most valuable idea in the proposal — but it requires measurement infrastructure that doesn't exist yet. The current synthesis pipeline (Phase 3) deduplicates findings by semantic similarity without tracking which model produced each finding. Adding provider attribution to findings would enable a divergence scoring layer where cross-provider agreement increases confidence and cross-provider disagreement triggers investigation. This is the highest-leverage improvement because it turns model diversity from a cost optimization into an insight quality amplifier.

### Issues Found

MD-1. **P1: Synthesis has no provider attribution.** The synthesis subagent (Step 3.2) reads `{OUTPUT_DIR}/{agent-name}.md` files and deduplicates by semantic similarity. It has no mechanism to know which model produced which finding. If fd-systems (Claude Sonnet) and fd-perception (DeepSeek V3) both flag the same feedback loop risk, synthesis treats this as redundancy and deduplicates. But cross-provider agreement on the same finding from independent training pipelines is stronger evidence than same-provider agreement. Conversely, if they disagree — Claude flags a risk that DeepSeek doesn't, or vice versa — that divergence is a signal worth surfacing.

**Concrete scenario:** Claude and DeepSeek both independently identify a missing rate-limit in the design. Synthesis deduplicates to one finding. But two independent model families converging on the same gap is much stronger evidence than two Claude agents (which share training biases) agreeing. Without provider attribution, this signal is lost.

**Smallest fix:** Add a `provider:` field to the Findings Index contract: `- SEVERITY | ID | "Section" | Title | provider:claude` or `provider:deepseek-v3`. Synthesis can then compute a `cross_provider_convergence` score: findings confirmed across providers get a confidence boost; findings present in only one provider get flagged for human attention.

MD-2. **P2: Cross-model sycophancy is qualitatively different.** The reaction round's sycophancy detection (discourse-fixative.yaml) looks for agents echoing peer findings without independent evidence. This was calibrated for Claude-Claude dynamics where sycophancy manifests as agreeable hedging ("I concur with fd-architecture's assessment"). Cheaper models exhibit different sycophancy patterns: DeepSeek tends to be more direct but may copy the structure of peer findings without adding analysis; Qwen models may add excessive qualifiers. The hearsay detection heuristics need recalibration for cross-model reaction rounds.

MD-3. **P2: Not all disagreement is signal.** The document assumes model disagreement indicates analytical divergence, but much of it will be format interpretation noise. If Claude produces `- P2 | ARCH-1 | "API Design" | Missing pagination` and DeepSeek produces `- P1 | 1 | "API" | No pagination support`, these are the same finding at different severity and with different formatting conventions. The disagreement taxonomy should distinguish: (a) **Severity disagreement** — same finding, different priority (often meaningful), (b) **Finding presence/absence** — one model flags something the other doesn't (highest signal), (c) **Section attribution** — same finding, different document sections cited (usually noise), (d) **Format divergence** — same finding, different expression (always noise, should be normalized away).

MD-4. **P2: Training cutoff temporal divergence.** Claude, DeepSeek, and Qwen have different training data cutoffs and different proportions of open-source code in their training data. When reviewing code that uses patterns adopted in the last 6-12 months, models trained on older data may flag "outdated" patterns that are actually current best practice. This creates a temporal signal: if the older-trained model flags something the newer-trained model doesn't, it might indicate a recently-changed convention. This is useful metadata for the orchestrator but should not be treated as disagreement — it should be annotated with `temporal_divergence: likely` based on known training cutoff dates.

MD-5. **P3: Provider diversity as expansion signal.** The expansion scoring in `phases/expansion.md` uses finding density and domain coverage to decide whether to launch Stage 2 agents. If Stage 1 includes both Claude and non-Claude agents, and they disagree on severity or finding presence, that divergence could be an expansion trigger — "the models disagree, launch more agents to break the tie." This would make cross-provider dispatch a direct driver of insight quality, not just cost optimization.

### Improvements

MD-I1. Start with a simple `provider_id` metadata field in each agent's output. No changes to synthesis algorithm needed initially — just collect the data. After 20+ mixed-provider reviews, analyze cross-provider vs same-provider agreement rates to calibrate the divergence scoring.

MD-I2. The existing `peer-findings.jsonl` contract already includes `agent` field — add `provider` and `model` fields. This enables the reaction round to surface cross-provider disagreements as high-value signals.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 5 (P0: 0, P1: 1, P2: 3, P3: 1)
SUMMARY: Model diversity as a signal is the highest-leverage idea in this proposal but requires provider attribution in the findings contract, a disagreement taxonomy to separate signal from noise, and recalibrated sycophancy detection for cross-model reaction dynamics.
---
<!-- flux-drive:complete -->
