---
bead: sylveste-tfr
date: 2026-03-27
type: brainstorm
---

# Semantic Quality Validation for Inference Outputs

## Problem

interfer currently tracks `mean_confidence` (avg max-softmax probability across tokens) but has no semantic quality scoring. This means:
- No way to detect degenerate outputs (repetition loops, incoherent text)
- No way to validate that local models produce acceptable quality vs cloud
- No data for interspect evidence to evaluate Track B5 enforce mode promotion

## Constraints

- Must work reference-free (no ground truth available for most requests)
- Must run in the Metal subprocess (where logprobs are available)
- Must not significantly increase latency (<10% overhead target)
- MLX-only — no PyTorch, no external API calls during scoring

## Approach: Three Reference-Free Metrics

### 1. Perplexity (from existing logprobs)

Already have per-token logprobs from `_raw_stream_generate`. Perplexity = exp(-mean(log_probs)).
- Low perplexity = fluent, confident generation
- High perplexity = uncertain, potentially incoherent
- Zero additional compute — just math on existing data
- Threshold: model-specific (small models naturally higher perplexity)

### 2. Coherence Score (confidence stability)

Sliding-window variance of per-token confidence. Large drops indicate model "losing the thread."
- Window size: 10 tokens
- Score: 1 - (variance / mean) — higher is more coherent
- Detects mid-generation quality degradation
- Cheap: simple statistics on existing confidence stream

### 3. Repetition Score (n-gram dedup)

Ratio of unique n-grams to total n-grams. Degenerate generation has near-zero unique ratio.
- Check 3-grams and 5-grams
- Score: unique_ngrams / total_ngrams (1.0 = no repetition)
- < 0.5 signals problematic repetition
- Requires decoded tokens (already available)

## Composite Quality Score

Weighted combination: `quality = 0.4 * norm_perplexity + 0.3 * coherence + 0.3 * repetition`

Normalized to 0-1 range. Reported in:
- GenerationMetrics (per-request)
- /metrics endpoint (aggregate)
- X-Interfere-Quality header (per-response)
- Shadow log (for interspect evidence)

## Optional: Reference-Based Scoring

For interlab playtest campaigns that have reference outputs:
- ROUGE-L: longest common subsequence ratio (pure Python, no deps)
- Enabled via `quality_reference` parameter in request body
- Results in separate `reference_score` field, not mixed into composite

## Non-Goals

- Training or fine-tuning based on quality scores
- Blocking responses based on quality (scoring only, not gating)
- External API calls for evaluation (BERTScore, GPT-as-judge)
