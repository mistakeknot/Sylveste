"""Tests for the priority request queue."""

from __future__ import annotations

import pytest

from server.queue import (
    InferenceRequest,
    PriorityRequestQueue,
    QueueFullError,
)


@pytest.mark.asyncio
async def test_priority_ordering() -> None:
    """High priority (1) is dequeued before low priority (10)."""
    q = PriorityRequestQueue(max_depth=10)

    low = InferenceRequest(request_id="low", priority=10, prompt="lo", model="m")
    high = InferenceRequest(request_id="high", priority=1, prompt="hi", model="m")

    # Insert low before high — high should still come out first.
    await q.put(low)
    await q.put(high)

    first = await q.get()
    second = await q.get()

    assert first.request_id == "high"
    assert second.request_id == "low"


@pytest.mark.asyncio
async def test_fifo_within_same_priority() -> None:
    """Equal priority preserves insertion (arrival) order."""
    q = PriorityRequestQueue(max_depth=10)

    reqs = []
    for i in range(5):
        r = InferenceRequest(request_id=f"req-{i}", priority=5, prompt="p", model="m")
        reqs.append(r)
        await q.put(r)

    for i in range(5):
        got = await q.get()
        assert got.request_id == f"req-{i}"


@pytest.mark.asyncio
async def test_backpressure_rejects_at_max_depth() -> None:
    """QueueFullError is raised when queue is at capacity."""
    q = PriorityRequestQueue(max_depth=2)

    await q.put(InferenceRequest(request_id="a", priority=1, prompt="p", model="m"))
    await q.put(InferenceRequest(request_id="b", priority=1, prompt="p", model="m"))

    assert q.depth == 2

    with pytest.raises(QueueFullError):
        await q.put(InferenceRequest(request_id="c", priority=1, prompt="p", model="m"))

    # Depth unchanged after rejection.
    assert q.depth == 2
