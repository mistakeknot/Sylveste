---
bead: sylveste-tfr
date: 2026-03-27
type: plan
complexity: C3
---

# Plan: Semantic Quality Validation

## Tasks

### Task 1: QualityScorer class (server/quality.py)
**New file.** Pure-Python quality scoring from logprobs and decoded tokens.

```python
@dataclass
class QualityScore:
    perplexity: float        # exp(-mean(log_probs)), lower is better
    coherence: float         # 1 - (variance/mean) of confidence window, 0-1
    repetition: float        # unique_ngrams / total_ngrams, 0-1
    composite: float         # weighted combination, 0-1 (higher is better)
    token_count: int

class QualityScorer:
    def score(logprobs: list[float], tokens: list[str]) -> QualityScore
```

- Perplexity: `exp(-mean(logprobs))` where logprobs are natural-log token probs
- Coherence: sliding window (10 tokens) variance of `exp(logprob)` values. Score = `1 - clamp(std/mean, 0, 1)`
- Repetition: ratio of unique 3-grams to total 3-grams. 1.0 = no repetition
- Composite: `0.4 * (1 - clamp(perplexity/100, 0, 1)) + 0.3 * coherence + 0.3 * repetition`

No MLX dependency — operates on plain Python floats/strings.

### Task 2: Wire into InferenceEngine (server/inference.py)
- Add `quality_score: QualityScore | None` field to `GenerationMetrics`
- Collect logprobs and decoded tokens during `generate()`
- Call `QualityScorer.score()` after generation completes
- Store result in `GenerationMetrics.quality_score`

### Task 3: Expose in MetalWorker response (server/metal_worker.py)
- Include quality score dict in the GENERATE `done` response metrics
- Fields: `quality_perplexity`, `quality_coherence`, `quality_repetition`, `quality_composite`

### Task 4: Wire into HTTP responses (server/main.py)
- Add `X-Interfere-Quality` header to SSE responses: `{"composite": 0.85, "perplexity": 12.3, ...}`
- Add quality section to `/metrics` endpoint: aggregate mean/p50/p95 of composite scores

### Task 5: Optional ROUGE-L reference scoring
- Add `reference` field to QualityScore (None when no reference provided)
- Implement `rouge_l(candidate: str, reference: str) -> float` — LCS-based, pure Python
- Triggered by `quality_reference` parameter in chat completion request body
- Result in `quality_reference_score` field in response

### Task 6: Tests
- Unit tests for QualityScorer (known inputs → expected outputs)
- Test perplexity calculation against manual computation
- Test coherence with stable vs unstable confidence sequences
- Test repetition detection with degenerate vs clean text
- Test ROUGE-L against known examples
- Integration test: quality score appears in /metrics after request

## File Change Summary

| File | Change |
|------|--------|
| `server/quality.py` | NEW — QualityScorer, QualityScore, rouge_l |
| `server/inference.py` | Add quality_score to GenerationMetrics, collect logprobs |
| `server/metal_worker.py` | Include quality in GENERATE done response |
| `server/main.py` | X-Interfere-Quality header, quality in /metrics |
| `tests/test_quality.py` | NEW — unit tests for quality scoring |
| `tests/test_server.py` | Integration test for quality in /metrics |

## Risks

- Perplexity thresholds are model-specific — need per-model calibration later
- Coherence score may be noisy for very short generations (< 10 tokens)
- Repetition check has O(n) memory for n-gram set — fine for typical max_tokens
