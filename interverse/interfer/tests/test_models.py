"""Tests for model registry and memory budget management."""

from __future__ import annotations

import pytest

from server.models import ModelRegistry


def test_registry_tracks_loaded_models() -> None:
    """Empty registry reports no models and full budget available."""
    budget = 100 * 1024**3  # 100 GB
    registry = ModelRegistry(memory_budget_bytes=budget)

    assert registry.loaded_models == []
    assert registry.available_memory_bytes > 0
    assert registry.available_memory_bytes == budget


def test_registry_rejects_oversized_model() -> None:
    """Loading a model larger than the budget raises MemoryError."""
    registry = ModelRegistry(memory_budget_bytes=1024)  # 1 KB

    with pytest.raises(MemoryError, match="exceeds budget"):
        registry.load(name="too-big", estimated_bytes=2048)
