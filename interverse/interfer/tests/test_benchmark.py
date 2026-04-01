"""Tests for the benchmark harness."""

from __future__ import annotations

import pytest

from server.benchmark import (
    PROMPT_CORPUS,
    BenchmarkResult,
    BenchmarkSummary,
    _percentile,
)


def test_prompt_corpus_has_all_categories() -> None:
    """Corpus covers coding, reasoning, tool_calling, factual, creative, instruction."""
    categories = {p["category"] for p in PROMPT_CORPUS}
    assert "coding" in categories
    assert "reasoning" in categories
    assert "tool_calling" in categories
    assert "factual" in categories


def test_prompt_corpus_all_have_names() -> None:
    """Every prompt has a name and prompt field."""
    for p in PROMPT_CORPUS:
        assert "name" in p
        assert "prompt" in p
        assert len(p["prompt"]) > 10


def test_percentile_basic() -> None:
    """Percentile calculation returns expected values."""
    data = [1.0, 2.0, 3.0, 4.0, 5.0]
    assert _percentile(data, 50) == 3.0
    assert _percentile(data, 0) == 1.0
    assert _percentile(data, 100) == 5.0


def test_percentile_empty() -> None:
    """Empty data returns 0."""
    assert _percentile([], 50) == 0.0


def test_benchmark_result_to_dict() -> None:
    """BenchmarkResult serializes to dict."""
    r = BenchmarkResult(
        prompt_name="test",
        model="test-model",
        tokens_generated=50,
        generation_time_s=1.0,
        ttft_s=0.1,
        tok_per_s=50.0,
        thermal_start="nominal",
        thermal_end="nominal",
        output_preview="hello",
        category="coding",
    )
    d = r.to_dict()
    assert d["prompt_name"] == "test"
    assert d["tok_per_s"] == 50.0


def test_benchmark_summary_to_dict() -> None:
    """BenchmarkSummary serializes including nested results."""
    s = BenchmarkSummary(
        model="test",
        total_runs=1,
        median_tok_s=50.0,
        mean_tok_s=50.0,
        p5_tok_s=50.0,
        p95_tok_s=50.0,
        median_ttft_s=0.1,
        total_tokens=100,
        total_time_s=2.0,
        thermal_start="nominal",
        thermal_end="nominal",
    )
    d = s.to_dict()
    assert d["model"] == "test"
    assert isinstance(d["results"], list)
