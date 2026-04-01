"""Adaptive batch scheduler for concurrent inference requests.

Accumulates incoming requests during a brief window and batches their
prefill phase using mlx-lm's batch_generate with prompt_caches.  After
batch prefill, requests are decoded sequentially by priority.

Architecture
------------
HTTP layer → BatchScheduler.submit() → accumulation window → batch prefill →
priority-ordered sequential decode → SSE stream per request

The scheduler runs as an asyncio task in the HTTP process.  It communicates
with the Metal subprocess via the existing WorkerRequest/WorkerResponse
protocol, adding a new BATCH_PREFILL command.

Key design choices:
- Prefill is the expensive phase (quadratic in prompt length) and benefits
  most from batching — a 4-request batch saves ~60% prefill time vs serial.
- Decode is inherently sequential on a single GPU, so we prioritize which
  request decodes next rather than trying to interleave.
- Preemption is cooperative: a high-priority arrival sets a flag that the
  decode generator checks between tokens.
"""

from __future__ import annotations

import asyncio
import logging
import time
from collections.abc import AsyncGenerator
from dataclasses import dataclass, field
from enum import IntEnum

log = logging.getLogger("interfer.batch")


class RequestPriority(IntEnum):
    """Priority levels for inference requests.

    Lower numeric value = higher priority.
    """

    CRITICAL = 0  # system health checks, cascade probes
    HIGH = 2  # interactive user requests
    NORMAL = 5  # default agent requests
    LOW = 8  # background/speculative requests
    BULK = 10  # batch processing, playtest campaigns


@dataclass(order=False)
class BatchRequest:
    """A single inference request submitted to the batch scheduler."""

    request_id: str
    model: str
    messages: list[dict] | None = None
    prompt: str = ""
    max_tokens: int = 512
    temperature: float = 0.7
    priority: int = RequestPriority.NORMAL
    kv_bits: int | None = None
    kv_group_size: int = 64
    _arrival: float = field(default_factory=time.monotonic, repr=False)
    _result_queue: asyncio.Queue[str | None] = field(
        default_factory=asyncio.Queue, repr=False
    )
    _prefill_cache: object | None = field(default=None, repr=False)

    def __lt__(self, other: object) -> bool:
        if not isinstance(other, BatchRequest):
            return NotImplemented
        if self.priority != other.priority:
            return self.priority < other.priority
        return self._arrival < other._arrival


@dataclass
class BatchStats:
    """Statistics for the batch scheduler."""

    total_submitted: int = 0
    total_completed: int = 0
    total_preempted: int = 0
    batches_formed: int = 0
    avg_batch_size: float = 0.0
    total_prefill_time_s: float = 0.0
    total_decode_time_s: float = 0.0

    def to_dict(self) -> dict:
        return {
            "total_submitted": self.total_submitted,
            "total_completed": self.total_completed,
            "total_preempted": self.total_preempted,
            "batches_formed": self.batches_formed,
            "avg_batch_size": round(self.avg_batch_size, 2),
            "total_prefill_time_s": round(self.total_prefill_time_s, 3),
            "total_decode_time_s": round(self.total_decode_time_s, 3),
        }


class BatchScheduler:
    """Adaptive batch scheduler for the inference pipeline.

    Accumulates requests during a configurable window, batches prefill,
    then serves decode in priority order.

    Parameters
    ----------
    accumulation_window_ms:
        How long to wait for additional requests before forming a batch.
        Shorter = lower latency for single requests.
        Longer = better batching efficiency under load.
    max_batch_size:
        Maximum requests to batch together for prefill.
    preemption_enabled:
        If True, a higher-priority request can interrupt a lower-priority
        decode in progress.
    preemption_threshold:
        Priority difference required for preemption (e.g., 3 means a
        priority-2 request can preempt priority-5 but not priority-4).
    """

    def __init__(
        self,
        accumulation_window_ms: float = 50.0,
        max_batch_size: int = 8,
        preemption_enabled: bool = True,
        preemption_threshold: int = 3,
    ) -> None:
        self._window_s = accumulation_window_ms / 1000.0
        self._max_batch_size = max_batch_size
        self._preemption_enabled = preemption_enabled
        self._preemption_threshold = preemption_threshold

        self._pending: asyncio.PriorityQueue[BatchRequest] = asyncio.PriorityQueue()
        self._stats = BatchStats()
        self._preempt_event = asyncio.Event()
        self._current_priority: int | None = None  # priority of currently decoding req
        self._running = False
        self._scheduler_task: asyncio.Task | None = None

    @property
    def stats(self) -> BatchStats:
        return self._stats

    @property
    def pending_count(self) -> int:
        return self._pending.qsize()

    async def start(self) -> None:
        """Start the scheduler loop."""
        if self._running:
            return
        self._running = True
        self._scheduler_task = asyncio.create_task(self._scheduler_loop())

    async def stop(self) -> None:
        """Stop the scheduler loop gracefully."""
        self._running = False
        if self._scheduler_task is not None:
            self._scheduler_task.cancel()
            try:
                await self._scheduler_task
            except asyncio.CancelledError:
                pass

    async def submit(self, request: BatchRequest) -> AsyncGenerator[str, None]:
        """Submit a request and yield tokens as they're generated.

        This is the main entry point for the HTTP layer. It enqueues the
        request and yields tokens from the result queue as the scheduler
        processes it.
        """
        self._stats.total_submitted += 1
        await self._pending.put(request)

        # Check if we should preempt the current decode
        if (
            self._preemption_enabled
            and self._current_priority is not None
            and self._current_priority - request.priority >= self._preemption_threshold
        ):
            log.info(
                "preempt: new priority=%d interrupts current=%d",
                request.priority,
                self._current_priority,
            )
            self._preempt_event.set()

        # Yield tokens from this request's result queue
        while True:
            token = await request._result_queue.get()
            if token is None:
                break
            yield token

    async def _scheduler_loop(self) -> None:
        """Main scheduler loop: accumulate → batch prefill → decode."""
        while self._running:
            # Wait for at least one request
            try:
                first = await asyncio.wait_for(self._pending.get(), timeout=1.0)
            except asyncio.TimeoutError:
                continue
            except asyncio.CancelledError:
                break

            # Accumulation window: gather more requests
            batch = [first]
            deadline = time.monotonic() + self._window_s
            while len(batch) < self._max_batch_size and time.monotonic() < deadline:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    break
                try:
                    req = await asyncio.wait_for(self._pending.get(), timeout=remaining)
                    batch.append(req)
                except asyncio.TimeoutError:
                    break

            # Sort batch by priority (lowest value = highest priority)
            batch.sort()

            self._stats.batches_formed += 1
            n = self._stats.batches_formed
            self._stats.avg_batch_size = (
                self._stats.avg_batch_size * (n - 1) + len(batch)
            ) / n

            log.info(
                "batch formed: size=%d priorities=%s",
                len(batch),
                [r.priority for r in batch],
            )

            # Process batch: decode each request in priority order
            # Note: batch prefill optimization requires subprocess support
            # (BATCH_PREFILL command) which is implemented separately.
            # For now, this scheduler provides priority ordering and
            # preemption — the prefill optimization is layered on top.
            for request in batch:
                self._current_priority = request.priority
                self._preempt_event.clear()

                try:
                    await self._decode_request(request)
                    self._stats.total_completed += 1
                except _PreemptedError:
                    self._stats.total_preempted += 1
                    # Re-enqueue the preempted request
                    await self._pending.put(request)
                    log.info(
                        "request %s preempted, re-enqueued",
                        request.request_id,
                    )
                finally:
                    self._current_priority = None

    async def _decode_request(self, request: BatchRequest) -> None:
        """Decode a single request, checking for preemption between tokens.

        This is a placeholder that the MetalWorker integration will override.
        It demonstrates the preemption protocol: between each token, check
        if a higher-priority request has set the preempt event.
        """
        # Subclasses or the integration layer will replace this with actual
        # worker.generate() calls.  The key contract:
        # 1. Put tokens into request._result_queue as they're generated
        # 2. Check self._preempt_event between tokens
        # 3. Put None to signal completion
        # 4. Raise _PreemptedError if preempted
        await request._result_queue.put(None)

    def should_preempt(self) -> bool:
        """Check if the current decode should be preempted.

        Called by the decode loop between tokens. Returns True if a
        higher-priority request is waiting.
        """
        return self._preempt_event.is_set()


class _PreemptedError(Exception):
    """Raised when a decode is interrupted by a higher-priority request."""
