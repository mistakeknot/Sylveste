"""Tests for the MLX inference engine."""

from __future__ import annotations

import pytest


def test_inference_engine_generates_tokens() -> None:
    """Load a small model and verify that generate() yields text."""
    mlx = pytest.importorskip("mlx")  # noqa: F841 — skip if MLX unavailable
    pytest.importorskip("mlx_lm")

    from server.inference import InferenceEngine

    engine = InferenceEngine()
    tokens = list(
        engine.generate(
            prompt="Hello",
            model_name="mlx-community/Qwen2.5-0.5B-Instruct-4bit",
            max_tokens=5,
        )
    )

    assert len(tokens) > 0
    assert all(isinstance(t, str) for t in tokens)
