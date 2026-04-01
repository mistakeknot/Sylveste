"""Reference-free quality scoring for inference outputs.

Computes perplexity, coherence, and repetition metrics from logprobs
and decoded tokens. All computation is pure Python — no MLX dependency.

Used by InferenceEngine to populate GenerationMetrics.quality_score.
"""

from __future__ import annotations

import math
from dataclasses import dataclass


@dataclass
class QualityScore:
    """Quality metrics for a single generation."""

    perplexity: float  # exp(-mean(logprobs)), lower is better
    coherence: float  # confidence stability, 0-1, higher is better
    repetition: float  # unique ngram ratio, 0-1, higher is better
    composite: float  # weighted combination, 0-1, higher is better
    token_count: int
    reference_score: float | None = None  # ROUGE-L if reference provided

    def to_dict(self) -> dict:
        d = {
            "perplexity": round(self.perplexity, 4),
            "coherence": round(self.coherence, 4),
            "repetition": round(self.repetition, 4),
            "composite": round(self.composite, 4),
            "token_count": self.token_count,
        }
        if self.reference_score is not None:
            d["reference_score"] = round(self.reference_score, 4)
        return d


def compute_perplexity(logprobs: list[float]) -> float:
    """Compute perplexity from log-probabilities.

    Perplexity = exp(-mean(logprobs)). Lower is better.
    A perplexity of 1.0 means the model is perfectly confident.
    """
    if not logprobs:
        return float("inf")
    mean_logprob = sum(logprobs) / len(logprobs)
    return math.exp(-mean_logprob)


def compute_coherence(confidences: list[float], window_size: int = 10) -> float:
    """Compute coherence from per-token confidence values.

    Measures stability of confidence across a sliding window.
    Score = 1 - clamp(mean_std / mean_confidence, 0, 1).
    Higher means more stable/coherent generation.
    """
    if len(confidences) < 2:
        return 1.0  # too few tokens to measure variance

    # Compute sliding window standard deviations
    window_stds: list[float] = []
    for i in range(len(confidences) - window_size + 1):
        window = confidences[i : i + window_size]
        if len(window) < 2:
            continue
        mean = sum(window) / len(window)
        variance = sum((x - mean) ** 2 for x in window) / len(window)
        window_stds.append(math.sqrt(variance))

    if not window_stds:
        # Fewer tokens than window_size — use global stats
        mean = sum(confidences) / len(confidences)
        variance = sum((x - mean) ** 2 for x in confidences) / len(confidences)
        std = math.sqrt(variance)
        mean_conf = mean
    else:
        std = sum(window_stds) / len(window_stds)
        mean_conf = sum(confidences) / len(confidences)

    if mean_conf <= 0:
        return 0.0

    ratio = std / mean_conf
    return max(0.0, min(1.0, 1.0 - ratio))


def compute_repetition(tokens: list[str], n: int = 3) -> float:
    """Compute repetition score from decoded tokens.

    Ratio of unique n-grams to total n-grams.
    1.0 = no repetition, 0.0 = completely repetitive.
    """
    if len(tokens) < n:
        return 1.0  # too few tokens for n-grams

    ngrams: list[tuple[str, ...]] = []
    for i in range(len(tokens) - n + 1):
        ngrams.append(tuple(tokens[i : i + n]))

    if not ngrams:
        return 1.0

    unique = len(set(ngrams))
    return unique / len(ngrams)


def compute_composite(perplexity: float, coherence: float, repetition: float) -> float:
    """Compute weighted composite quality score (0-1, higher is better).

    Perplexity is normalized: 1 - clamp(perplexity / 100, 0, 1).
    """
    norm_perplexity = 1.0 - max(0.0, min(1.0, perplexity / 100.0))
    return 0.4 * norm_perplexity + 0.3 * coherence + 0.3 * repetition


def rouge_l(candidate: str, reference: str) -> float:
    """Compute ROUGE-L F1 score between candidate and reference.

    Uses longest common subsequence (LCS). Pure Python, no deps.
    Returns F1 score in [0, 1].
    """
    cand_tokens = candidate.split()
    ref_tokens = reference.split()

    if not cand_tokens or not ref_tokens:
        return 0.0

    # LCS via dynamic programming
    m, n = len(cand_tokens), len(ref_tokens)
    # Use 1D DP for memory efficiency
    prev = [0] * (n + 1)
    curr = [0] * (n + 1)

    for i in range(1, m + 1):
        for j in range(1, n + 1):
            if cand_tokens[i - 1] == ref_tokens[j - 1]:
                curr[j] = prev[j - 1] + 1
            else:
                curr[j] = max(curr[j - 1], prev[j])
        prev, curr = curr, [0] * (n + 1)

    lcs_len = prev[n]

    precision = lcs_len / m if m > 0 else 0.0
    recall = lcs_len / n if n > 0 else 0.0

    if precision + recall == 0:
        return 0.0

    return 2 * precision * recall / (precision + recall)


class QualityScorer:
    """Computes quality scores for inference outputs.

    Usage::

        scorer = QualityScorer()
        score = scorer.score(logprobs=[...], tokens=[...])
        print(f"Quality: {score.composite:.3f}")
    """

    def score(
        self,
        logprobs: list[float],
        tokens: list[str],
        reference: str | None = None,
    ) -> QualityScore:
        """Score a generation's quality.

        Parameters
        ----------
        logprobs:
            Per-token log-probabilities (natural log).
        tokens:
            Decoded token strings.
        reference:
            Optional reference text for ROUGE-L scoring.
        """
        perplexity = compute_perplexity(logprobs)
        confidences = [math.exp(lp) for lp in logprobs] if logprobs else []
        coherence = compute_coherence(confidences)
        repetition = compute_repetition(tokens)
        composite = compute_composite(perplexity, coherence, repetition)

        ref_score = None
        if reference is not None:
            candidate_text = "".join(tokens)
            ref_score = rouge_l(candidate_text, reference)

        return QualityScore(
            perplexity=perplexity,
            coherence=coherence,
            repetition=repetition,
            composite=composite,
            token_count=len(tokens),
            reference_score=ref_score,
        )
