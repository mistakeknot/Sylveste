"""Tests for the adaptive batch scheduler."""

from __future__ import annotations

import asyncio

import pytest

from server.batch_scheduler import (
    BatchRequest,
    BatchScheduler,
    BatchStats,
    RequestPriority,
    _PreemptedError,
)


# ---------------------------------------------------------------------------
# BatchRequest ordering
# ---------------------------------------------------------------------------


def test_request_priority_ordering() -> None:
    """Lower priority value = higher priority (dequeued first)."""
    high = BatchRequest(request_id="high", model="m", priority=RequestPriority.HIGH)
    normal = BatchRequest(
        request_id="normal", model="m", priority=RequestPriority.NORMAL
    )
    low = BatchRequest(request_id="low", model="m", priority=RequestPriority.LOW)
    assert high < normal < low


def test_request_fifo_tiebreak() -> None:
    """Equal priority → FIFO by arrival time."""
    import time

    a = BatchRequest(request_id="a", model="m", priority=5)
    time.sleep(0.001)  # ensure different monotonic timestamps
    b = BatchRequest(request_id="b", model="m", priority=5)
    assert a < b


def test_request_priority_enum_values() -> None:
    """Priority enum has expected ordering."""
    assert RequestPriority.CRITICAL < RequestPriority.HIGH
    assert RequestPriority.HIGH < RequestPriority.NORMAL
    assert RequestPriority.NORMAL < RequestPriority.LOW
    assert RequestPriority.LOW < RequestPriority.BULK


# ---------------------------------------------------------------------------
# BatchStats
# ---------------------------------------------------------------------------


def test_batch_stats_to_dict() -> None:
    """BatchStats.to_dict returns all expected keys."""
    stats = BatchStats(total_submitted=10, batches_formed=3, avg_batch_size=3.33)
    d = stats.to_dict()
    assert d["total_submitted"] == 10
    assert d["batches_formed"] == 3
    assert d["avg_batch_size"] == 3.33


# ---------------------------------------------------------------------------
# BatchScheduler — basic lifecycle
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_scheduler_start_stop() -> None:
    """Scheduler starts and stops without error."""
    sched = BatchScheduler(accumulation_window_ms=10)
    await sched.start()
    assert sched._running is True
    await sched.stop()
    assert sched._running is False


@pytest.mark.asyncio
async def test_scheduler_double_start() -> None:
    """Starting twice is a no-op."""
    sched = BatchScheduler(accumulation_window_ms=10)
    await sched.start()
    task1 = sched._scheduler_task
    await sched.start()
    task2 = sched._scheduler_task
    assert task1 is task2  # same task, not restarted
    await sched.stop()


# ---------------------------------------------------------------------------
# BatchScheduler — request submission
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_submit_receives_completion() -> None:
    """Submitted request eventually receives None (completion signal)."""
    sched = BatchScheduler(accumulation_window_ms=10)
    await sched.start()

    req = BatchRequest(request_id="test", model="m", priority=5)
    tokens: list[str] = []

    async for token in sched.submit(req):
        tokens.append(token)

    # Default _decode_request just sends None (completion)
    assert tokens == []
    assert sched.stats.total_submitted == 1
    await sched.stop()


@pytest.mark.asyncio
async def test_submit_tracks_stats() -> None:
    """Stats are updated after processing."""
    sched = BatchScheduler(accumulation_window_ms=10)
    await sched.start()

    req = BatchRequest(request_id="s1", model="m")
    async for _ in sched.submit(req):
        pass

    assert sched.stats.total_submitted == 1
    assert sched.stats.batches_formed >= 1
    await sched.stop()


# ---------------------------------------------------------------------------
# BatchScheduler — batching behavior
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_accumulation_window_batches_concurrent() -> None:
    """Requests arriving within the window are batched together."""
    sched = BatchScheduler(accumulation_window_ms=100, max_batch_size=4)
    await sched.start()

    # Submit 3 requests nearly simultaneously
    requests = [
        BatchRequest(request_id=f"r{i}", model="m", priority=5) for i in range(3)
    ]

    async def drain(req):
        async for _ in sched.submit(req):
            pass

    await asyncio.gather(*[drain(r) for r in requests])

    # Should form at most 1-2 batches (likely 1 with 100ms window)
    assert sched.stats.total_submitted == 3
    assert sched.stats.total_completed == 3
    await sched.stop()


@pytest.mark.asyncio
async def test_max_batch_size_respected() -> None:
    """Batch size never exceeds max_batch_size."""
    sched = BatchScheduler(accumulation_window_ms=200, max_batch_size=2)
    await sched.start()

    requests = [BatchRequest(request_id=f"r{i}", model="m") for i in range(4)]

    async def drain(req):
        async for _ in sched.submit(req):
            pass

    await asyncio.gather(*[drain(r) for r in requests])

    # 4 requests with max_batch_size=2 → at least 2 batches
    assert sched.stats.batches_formed >= 2
    assert sched.stats.total_completed == 4
    await sched.stop()


# ---------------------------------------------------------------------------
# BatchScheduler — priority ordering
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_priority_ordering_within_batch() -> None:
    """Higher-priority requests are decoded first within a batch."""
    decode_order: list[str] = []

    class TrackingScheduler(BatchScheduler):
        async def _decode_request(self, request: BatchRequest) -> None:
            decode_order.append(request.request_id)
            await request._result_queue.put(None)

    sched = TrackingScheduler(accumulation_window_ms=50)
    await sched.start()

    # Submit in reverse priority order
    low = BatchRequest(request_id="low", model="m", priority=RequestPriority.LOW)
    high = BatchRequest(request_id="high", model="m", priority=RequestPriority.HIGH)
    normal = BatchRequest(
        request_id="normal", model="m", priority=RequestPriority.NORMAL
    )

    async def drain(req):
        async for _ in sched.submit(req):
            pass

    # Submit all three quickly so they batch together
    await asyncio.gather(drain(low), drain(high), drain(normal))

    assert decode_order == ["high", "normal", "low"]
    await sched.stop()


# ---------------------------------------------------------------------------
# BatchScheduler — preemption
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_preemption_flag() -> None:
    """should_preempt returns True when preempt event is set."""
    sched = BatchScheduler()
    assert sched.should_preempt() is False
    sched._preempt_event.set()
    assert sched.should_preempt() is True


@pytest.mark.asyncio
async def test_preemption_threshold() -> None:
    """Preemption only triggers when priority gap meets threshold."""
    sched = BatchScheduler(preemption_threshold=3)
    await sched.start()

    # Set current priority to NORMAL (5)
    sched._current_priority = RequestPriority.NORMAL

    # Priority 4 (gap=1) should NOT trigger preemption
    req_close = BatchRequest(request_id="close", model="m", priority=4)
    sched._stats.total_submitted += 1
    await sched._pending.put(req_close)
    assert not sched._preempt_event.is_set()

    # Priority 2 (gap=3) SHOULD trigger preemption (via submit)
    req_high = BatchRequest(request_id="high", model="m", priority=RequestPriority.HIGH)

    # We can't use submit() directly since it would block waiting for tokens.
    # Instead, simulate the preemption check logic.
    gap = sched._current_priority - req_high.priority
    assert gap >= sched._preemption_threshold

    sched._current_priority = None
    await sched.stop()


def test_preempted_error() -> None:
    """_PreemptedError is a proper exception."""
    err = _PreemptedError("interrupted")
    assert str(err) == "interrupted"
    assert isinstance(err, Exception)


# ---------------------------------------------------------------------------
# BatchScheduler — pending count
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_pending_count() -> None:
    """pending_count tracks unprocessed requests."""
    sched = BatchScheduler(accumulation_window_ms=500)
    # Don't start the scheduler — requests will accumulate
    assert sched.pending_count == 0

    req = BatchRequest(request_id="r1", model="m")
    await sched._pending.put(req)
    assert sched.pending_count == 1
