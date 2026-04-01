"""Priority request queue with backpressure for inference requests."""

from __future__ import annotations

import asyncio
import time
from dataclasses import dataclass, field
from typing import Any


class QueueFullError(Exception):
    """Raised when the queue is at capacity and cannot accept more requests."""


@dataclass(order=False)
class InferenceRequest:
    """A single inference request with priority ordering.

    Lower priority value = higher priority (dequeued first).
    FIFO tiebreak on _arrival for equal priorities.
    """

    request_id: str
    priority: int
    prompt: str
    model: str
    max_tokens: int = 512
    temperature: float = 0.7
    stream: bool = False
    _arrival: float = field(default_factory=time.monotonic, repr=False)
    _future: asyncio.Future[Any] | None = field(default=None, repr=False)

    def __lt__(self, other: object) -> bool:
        if not isinstance(other, InferenceRequest):
            return NotImplemented
        if self.priority != other.priority:
            return self.priority < other.priority
        return self._arrival < other._arrival

    def __le__(self, other: object) -> bool:
        if not isinstance(other, InferenceRequest):
            return NotImplemented
        return self == other or self < other

    def __gt__(self, other: object) -> bool:
        if not isinstance(other, InferenceRequest):
            return NotImplemented
        if self.priority != other.priority:
            return self.priority > other.priority
        return self._arrival > other._arrival

    def __ge__(self, other: object) -> bool:
        if not isinstance(other, InferenceRequest):
            return NotImplemented
        return self == other or self > other


class PriorityRequestQueue:
    """Async priority queue with bounded depth and backpressure.

    Uses asyncio.PriorityQueue internally. Raises QueueFullError when
    the queue is at max_depth and a new request is submitted.
    """

    def __init__(self, max_depth: int = 64) -> None:
        self.max_depth = max_depth
        self._queue: asyncio.PriorityQueue[InferenceRequest] = asyncio.PriorityQueue(
            maxsize=max_depth,
        )

    @property
    def depth(self) -> int:
        """Current number of requests in the queue."""
        return self._queue.qsize()

    async def put(self, request: InferenceRequest) -> None:
        """Enqueue a request. Raises QueueFullError if at capacity."""
        if self._queue.full():
            raise QueueFullError(
                f"Queue at capacity ({self.max_depth}), rejecting request "
                f"{request.request_id}"
            )
        await self._queue.put(request)

    async def get(self) -> InferenceRequest:
        """Dequeue the highest-priority request (lowest priority value)."""
        return await self._queue.get()
