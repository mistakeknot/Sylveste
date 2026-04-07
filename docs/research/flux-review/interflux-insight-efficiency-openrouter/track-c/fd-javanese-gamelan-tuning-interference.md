### Findings Index
- P1 | GAM-1 | "Current Architecture / Synthesize" | Synthesis dedup treats all sources as equivalent — model provenance not tracked, cross-model agreement not weighted above within-model agreement
- P1 | GAM-2 | "OpenRouter integration / Model diversity as a signal" | No mechanism to distinguish productive ombak (genuine cross-model analytical disagreement) from destructive interference (capability-gap noise or hallucination)
- P1 | GAM-3 | "OpenRouter integration / Constraints" | Uniform prompting assumed — no per-model-family prompt adaptation proposed, embat preservation absent
- P2 | GAM-4 | "Cross-model dispatch / Model diversity as a signal" | No baseline disagreement profile proposed for model pairs — system cannot distinguish systematic bias from novel signal
- P3 | GAM-5 | "Budget system / Cross-model dispatch" | Corroboration scoring in synthesis does not distinguish cross-family agreement from within-family agreement

Verdict: needs-changes

### Summary

The interflux document identifies the most important insight in the multi-model diversity space — "disagreements between Claude and DeepSeek on the same finding might be more meaningful than agreement between two Claude agents" — and then proposes no mechanism to actually use this signal. This is the equivalent of a penyelaras who understands that ombak between paired sarons produces richness, but then tunes all the instruments to exactly the same pitch to make the ensemble easier to manage.

The synthesis phase (`phases/synthesize.md` Step 3.2-3.3) performs deduplication with five rules, none of which account for model provenance. Rule 1 ("Same file:line + same issue → merge, credit all agents") merges a Claude-Haiku finding with a DeepSeek-V3 finding on the same issue without noting that two genuinely independent analytical traditions reached the same conclusion — an extremely high-confidence signal. Rule 4 ("Conflicting severity → use highest") resolves a Claude-Sonnet P1 vs DeepSeek P2 conflict by choosing P1, without investigating whether the discrepancy reflects a systematic capability difference (DeepSeek consistently rates this pattern as P2) or a genuine novel disagreement (this specific instance is genuinely ambiguous). The ombak is destroyed by treating all instruments as if they should play in unison.

### Issues Found

**[P1-1]** Section: "Current Architecture / Synthesize phase" — Model provenance not tracked through synthesis; cross-model corroboration destroyed by source-agnostic deduplication

The synthesis deduplication in `phases/synthesize.md` Step 3.3 defines five dedup rules. None reference the source model. The `findings.json` schema in Step 3.4a captures `"agent": "fd-architecture"` but not the model that ran that agent. This means the synthesis subagent cannot distinguish between:
- fd-quality (Claude Haiku) and fd-quality (DeepSeek V3) both finding the same issue → extraordinary corroboration from genuinely independent analytical traditions
- fd-quality (Claude Haiku) and fd-architecture (Claude Sonnet) both finding the same issue → corroboration but from the same training family with shared biases

Both cases currently produce `"convergence": 2` with no model-provenance weighting.

Concrete failure: A review of a security-relevant architectural pattern runs fd-safety on Claude Sonnet and fd-correctness on DeepSeek V3. Both flag the same issue at P0. The synthesis merges them as `convergence: 2`, identical to the weight produced when two Claude models agree. The user sees "2/5 agents converged" without knowing that the cross-family agreement is an unusually strong signal — they underweight the finding relative to the evidence it represents.

Smallest viable fix: Add `model_family` to the agent output and findings.json schema:
```json
{
  "id": "P0-1",
  "severity": "P0",
  "agent": "fd-safety",
  "model_family": "anthropic",  // or "deepseek", "qwen", "yi"
  "convergence": 2,
  "cross_family_convergence": 1  // count of distinct families that found this
}
```
In synthesis dedup Rule 1, when merging: `cross_family_convergence = count(distinct model_family values across merged agents)`. In the Step 3.5 report, display `cross_family_convergence` alongside `convergence` for P0/P1 findings — a finding with `convergence: 2, cross_family: 2` is significantly stronger evidence than `convergence: 3, cross_family: 1`.

**[P1-2]** Section: "OpenRouter integration / Model diversity as a signal" — No disagreement classification mechanism: productive ombak vs capability-gap noise are treated identically

The document hypothesizes that "disagreements between Claude and DeepSeek... might be more meaningful than agreement between two Claude agents." But the synthesis rules (synthesize.md Step 3.3, Rules 4-5) handle conflicts by taking the highest severity or preserving both with attribution. Neither rule attempts to classify the disagreement: is this a known systematic difference between these model families on this finding type, or a novel signal?

Without classification, two destructive interference modes become indistinguishable from productive ombak:
1. **Capability gap noise**: DeepSeek cannot reliably assess subtle security implications → consistently disagrees with Claude on fd-safety P1s → these "disagreements" are noise, not signal
2. **Hallucination disagreement**: A model fabricates a finding that contradicts a genuine Claude finding → synthesis Rule 4 takes the higher severity → the hallucinated finding wins

Concrete failure: DeepSeek V3 runs as fd-quality and flags a performance finding at P1 that fd-correctness (Claude Sonnet) rates as P2. Synthesis takes P1 per Rule 4. But DeepSeek has a systematic pattern of over-rating certain algorithmic patterns as performance issues due to its training data — this specific disagreement is not a genuine novel signal but a known systematic bias. The user receives a P1 finding that Claude would have rated P2, with no indication that the elevation came from a known-biased source.

Smallest viable fix: Add a `disagreement_type` field to inter-model conflicts in findings.json:
```json
{
  "conflict": {
    "agents": ["fd-quality:deepseek", "fd-correctness:claude-sonnet"],
    "claude_severity": "P2",
    "non_claude_severity": "P1",
    "disagreement_type": "unknown",  // or "systematic_bias" once profiles exist
    "resolution": "highest_severity",
    "resolution_note": "Cross-family conflict — flag for calibration review"
  }
}
```
Initially `disagreement_type` is always `"unknown"`. As the system accumulates data, add a `model_pair_profiles.yaml` that records known systematic biases, enabling automatic classification.

**[P1-3]** Section: "OpenRouter integration / Constraints" — Uniform prompt templates assume Claude's response patterns; non-Claude models will produce embat-destroying homogenization

The document describes routing "certain agent types" through Bash tool API calls or MCP server. The prompt templates in `skills/flux-drive/references/prompt-template.md` are designed around Claude's response patterns: discursive analytical prose, specific structured output format (`### Findings Index` with severity ratings), and reasoning patterns that assume Claude-style chain-of-thought behavior.

DeepSeek V3 and Qwen 2.5 have different natural analytical styles. Sending them Claude-designed prompts has two failure modes:
1. **Output format non-compliance**: DeepSeek produces findings in a different format than the `### Findings Index` pattern, breaking the synthesis parser's validation (Step 3.1 checks for exact format markers like `<!-- flux-drive:complete -->` sentinel)
2. **Analytical style suppression**: The prompt constrains DeepSeek to Claude's discursive analytical style, preventing it from leveraging its own code-focused analytical strengths. The embat is destroyed by retuning all instruments to match one reference.

Concrete failure: DeepSeek V3 is dispatched as fd-correctness with the standard Claude-designed prompt. It produces findings in a different format (numbered list rather than severity-prefixed table, no sentinel comment). Step 3.1 classifies the output as "Malformed" and falls back to prose-based reading. The structured Findings Index is lost, the cross-model findings cannot be properly deduplicated, and the `cross_family_convergence` tracking fails because the finding metadata is incomplete.

Smallest viable fix: Create per-model-family prompt variants in a new `config/flux-drive/model-prompts/` directory:
```
config/flux-drive/model-prompts/
  deepseek-v3.md    # Emphasizes structured output with code-level analysis
  qwen-2.5.md       # Emphasizes checklist-style with explicit severity ratings
  claude-default.md # Current template (unchanged)
```
The OpenRouter dispatch wrapper selects the appropriate variant based on `model_family`. The core required sections (Findings Index structure, severity taxonomy, sentinel comment) remain identical across variants — only the analytical framing and style guidance differ.

**[P2-4]** Section: "Cross-model dispatch / Model diversity" — No baseline disagreement profile for model pairs; every disagreement treated as equally novel signal

The document proposes using model disagreements as signal without proposing any mechanism to establish what level of disagreement is normal between a given model pair. A gamelan tuned yesterday may drift by tomorrow — the penyelaras needs a reference pitch to know whether today's ombak is within the productive range or has drifted into cacophony.

Between Claude Sonnet and DeepSeek V3 reviewing code quality, there may be a systematic baseline disagreement rate of 15% (they consistently disagree on 15% of severity ratings due to different training-data distributions). If a specific review produces a 40% disagreement rate, that excess 25% is the novel signal worth investigating. Without the 15% baseline, the system cannot distinguish normal ombak from unusual discord.

Fix: In the cost report (Step 3.4b), after the first N reviews where both model families ran on the same agent types, compute and store pair-wise baseline disagreement rates in `config/flux-drive/model-pair-baselines.yaml`. The synthesis report should display current disagreement rate vs baseline: "Claude-DeepSeek disagreement: 32% (baseline: 15%) — elevated discord in {domain}."

### Improvements

1. **P3** — The `convergence` field in findings.json should be split into `within_family_convergence` (Claude Haiku + Claude Sonnet → 2) and `cross_family_convergence` (Claude Sonnet + DeepSeek → 1). The Step 3.5 report should visually distinguish these: a P0 with `cross_family: 2` deserves a different visual treatment than a P0 with `within_family: 2`.

2. **P3** — Add a "productive interference" mode where the synthesis explicitly surfaces the top-N findings where model families most strongly disagree, presented as a separate "Model Disagreement" section in the review report. These findings represent the highest epistemic uncertainty — the code that the models collectively understand least — and may be where the most interesting review questions lie.

3. **P3** — Track ombak calibration over time: after enough reviews, build a disagreement signature per agent-type per model-family pair (e.g., "DeepSeek consistently rates fd-quality issues 0.5 severity levels higher than Claude"). Publish this as a `model-family-signatures.yaml` that synthesis uses to normalize severity before taking the highest-severity rule.

<!-- flux-drive:complete -->
