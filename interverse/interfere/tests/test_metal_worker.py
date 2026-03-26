"""Tests for the Metal worker subprocess."""

from __future__ import annotations

import sys

import pytest

from server.metal_worker import MetalWorker


def _has_mlx() -> bool:
    """Return True if mlx is importable (Apple Silicon with MLX installed)."""
    try:
        import mlx.core  # noqa: F401

        return True
    except (ImportError, ModuleNotFoundError):
        return False


requires_mlx = pytest.mark.skipif(
    not _has_mlx(),
    reason="mlx not available — requires Apple Silicon with MLX installed",
)


@requires_mlx
def test_metal_worker_starts_and_responds_to_health() -> None:
    """Start the worker, call health(), verify response, and shut down."""
    worker = MetalWorker()
    worker.start()

    try:
        assert worker.is_alive()

        resp = worker.health(timeout=10.0)
        assert resp.status == "ready"
        assert resp.data["memory_limit_bytes"] > 0
        assert resp.data["pid"] != 0
    finally:
        worker.shutdown()

    assert not worker.is_alive()


def test_metal_worker_rejects_when_not_started() -> None:
    """Calling health() before start() must raise RuntimeError."""
    worker = MetalWorker()

    with pytest.raises(RuntimeError, match="not running"):
        worker.health()
