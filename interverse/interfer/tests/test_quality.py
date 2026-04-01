"""Tests for quality scoring."""

from __future__ import annotations

import math

import pytest

from server.quality import (
    QualityScore,
    QualityScorer,
    compute_coherence,
    compute_composite,
    compute_perplexity,
    compute_repetition,
    rouge_l,
)


# ---------------------------------------------------------------------------
# Perplexity
# ---------------------------------------------------------------------------


def test_perplexity_perfect_confidence() -> None:
    """Log-prob of 0 means prob=1, perplexity=1."""
    assert compute_perplexity([0.0, 0.0, 0.0]) == pytest.approx(1.0)


def test_perplexity_moderate() -> None:
    """Known log-probs give predictable perplexity."""
    # logprob = -2.0 → perplexity = exp(2.0) ≈ 7.389
    assert compute_perplexity([-2.0, -2.0, -2.0]) == pytest.approx(math.exp(2.0))


def test_perplexity_empty() -> None:
    """Empty logprobs returns infinity."""
    assert compute_perplexity([]) == float("inf")


def test_perplexity_mixed() -> None:
    """Mixed log-probs: mean(-1, -3) = -2, perplexity = exp(2) ≈ 7.389."""
    assert compute_perplexity([-1.0, -3.0]) == pytest.approx(math.exp(2.0))


# ---------------------------------------------------------------------------
# Coherence
# ---------------------------------------------------------------------------


def test_coherence_stable() -> None:
    """All-same confidences → coherence ≈ 1.0."""
    confidences = [0.9] * 20
    assert compute_coherence(confidences) == pytest.approx(1.0, abs=0.01)


def test_coherence_unstable() -> None:
    """Alternating high/low → coherence < 0.5."""
    confidences = [0.9, 0.1] * 10
    assert compute_coherence(confidences) < 0.5


def test_coherence_single_token() -> None:
    """Single token → perfect coherence (not enough to measure)."""
    assert compute_coherence([0.8]) == 1.0


def test_coherence_few_tokens() -> None:
    """Fewer than window size still works."""
    assert 0.0 <= compute_coherence([0.9, 0.85, 0.88]) <= 1.0


# ---------------------------------------------------------------------------
# Repetition
# ---------------------------------------------------------------------------


def test_repetition_unique_tokens() -> None:
    """All unique 3-grams → score = 1.0."""
    tokens = ["The", " quick", " brown", " fox", " jumps", " over"]
    assert compute_repetition(tokens) == 1.0


def test_repetition_degenerate() -> None:
    """Repeated tokens → low score."""
    tokens = ["hello", " world"] * 20
    score = compute_repetition(tokens)
    assert score < 0.2


def test_repetition_too_few() -> None:
    """Fewer than n tokens → 1.0."""
    assert compute_repetition(["a", "b"]) == 1.0


def test_repetition_exact_n() -> None:
    """Exactly n tokens → 1 n-gram → 1.0."""
    assert compute_repetition(["a", "b", "c"]) == 1.0


# ---------------------------------------------------------------------------
# Composite
# ---------------------------------------------------------------------------


def test_composite_perfect() -> None:
    """Perfect scores → composite near 1.0."""
    # perplexity=1.0 → norm=0.99, coherence=1.0, repetition=1.0
    score = compute_composite(perplexity=1.0, coherence=1.0, repetition=1.0)
    assert score > 0.9


def test_composite_terrible() -> None:
    """Terrible scores → composite near 0.0."""
    # perplexity=1000 → norm=0.0, coherence=0.0, repetition=0.0
    score = compute_composite(perplexity=1000.0, coherence=0.0, repetition=0.0)
    assert score == pytest.approx(0.0)


def test_composite_moderate() -> None:
    """Moderate scores → composite in middle range."""
    score = compute_composite(perplexity=50.0, coherence=0.7, repetition=0.8)
    assert 0.3 < score < 0.8


# ---------------------------------------------------------------------------
# ROUGE-L
# ---------------------------------------------------------------------------


def test_rouge_l_identical() -> None:
    """Identical strings → ROUGE-L = 1.0."""
    assert rouge_l("the cat sat on the mat", "the cat sat on the mat") == 1.0


def test_rouge_l_no_overlap() -> None:
    """No overlap → ROUGE-L = 0.0."""
    assert rouge_l("alpha beta gamma", "delta epsilon zeta") == 0.0


def test_rouge_l_partial() -> None:
    """Partial overlap → 0 < ROUGE-L < 1."""
    score = rouge_l("the cat sat", "the dog sat on the mat")
    assert 0.0 < score < 1.0


def test_rouge_l_empty() -> None:
    """Empty strings → 0.0."""
    assert rouge_l("", "hello") == 0.0
    assert rouge_l("hello", "") == 0.0


# ---------------------------------------------------------------------------
# QualityScorer integration
# ---------------------------------------------------------------------------


def test_scorer_basic() -> None:
    """Scorer returns all fields."""
    scorer = QualityScorer()
    score = scorer.score(
        logprobs=[-0.5, -0.3, -0.4, -0.5, -0.3],
        tokens=["Hello", " from", " the", " test", " suite"],
    )
    assert isinstance(score, QualityScore)
    assert score.perplexity > 0
    assert 0.0 <= score.coherence <= 1.0
    assert 0.0 <= score.repetition <= 1.0
    assert 0.0 <= score.composite <= 1.0
    assert score.token_count == 5
    assert score.reference_score is None


def test_scorer_with_reference() -> None:
    """Scorer computes reference score when reference provided."""
    scorer = QualityScorer()
    score = scorer.score(
        logprobs=[-0.5] * 5,
        tokens=["the", " cat", " sat", " on", " mat"],
        reference="the cat sat on the mat",
    )
    assert score.reference_score is not None
    assert 0.0 < score.reference_score <= 1.0


def test_scorer_to_dict() -> None:
    """to_dict includes all expected keys."""
    score = QualityScore(
        perplexity=5.0,
        coherence=0.85,
        repetition=0.95,
        composite=0.8,
        token_count=10,
    )
    d = score.to_dict()
    assert set(d.keys()) == {
        "perplexity",
        "coherence",
        "repetition",
        "composite",
        "token_count",
    }


def test_scorer_to_dict_with_reference() -> None:
    """to_dict includes reference_score when present."""
    score = QualityScore(
        perplexity=5.0,
        coherence=0.85,
        repetition=0.95,
        composite=0.8,
        token_count=10,
        reference_score=0.72,
    )
    d = score.to_dict()
    assert "reference_score" in d
    assert d["reference_score"] == 0.72


# ---------------------------------------------------------------------------
# _record_quality (main.py integration helper)
# ---------------------------------------------------------------------------


def test_record_quality_appends_to_samples() -> None:
    """_record_quality adds composite score to the samples list."""
    from server.main import _record_quality

    samples: list[float] = []
    _record_quality("test-model", {"composite": 0.85, "perplexity": 5.0}, samples)
    assert len(samples) == 1
    assert samples[0] == 0.85


def test_record_quality_trims_overflow() -> None:
    """_record_quality keeps at most _MAX_QUALITY_SAMPLES entries."""
    from server.main import _MAX_QUALITY_SAMPLES, _record_quality

    samples: list[float] = list(range(_MAX_QUALITY_SAMPLES))
    _record_quality("test-model", {"composite": 0.99, "perplexity": 1.0}, samples)
    assert len(samples) == _MAX_QUALITY_SAMPLES
    assert samples[-1] == 0.99
    # Oldest entry was trimmed
    assert samples[0] == 1  # was 0, got trimmed


def test_record_quality_handles_none_samples() -> None:
    """_record_quality handles None samples list gracefully."""
    from server.main import _record_quality

    # Should not raise
    _record_quality("test-model", {"composite": 0.85, "perplexity": 5.0}, None)


def test_record_quality_handles_inf_perplexity() -> None:
    """_record_quality skips perplexity histogram when infinity."""
    from server.main import _record_quality

    samples: list[float] = []
    # Should not raise — inf perplexity is skipped
    _record_quality(
        "test-model", {"composite": 0.5, "perplexity": float("inf")}, samples
    )
    assert len(samples) == 1
