"""Metal-owning subprocess for MLX inference.

The Metal GPU context is process-global on Apple Silicon — it must be created
exactly once, in a *spawned* subprocess (not forked).  This module provides
MetalWorker, which manages that subprocess and communicates with it over a
pair of multiprocessing.Queue objects.

MLX is imported **only** inside _worker_loop so the Metal context is never
touched by the main (HTTP) process.
"""

from __future__ import annotations

import enum
import multiprocessing
import multiprocessing.queues
import os
import time
from dataclasses import dataclass, field
from typing import Any, Generator


# ---------------------------------------------------------------------------
# Protocol types
# ---------------------------------------------------------------------------


class WorkerCommand(enum.Enum):
    """Commands the main process can send to the Metal worker."""

    HEALTH = "health"
    LOAD_MODEL = "load_model"
    GENERATE = "generate"
    SHUTDOWN = "shutdown"


@dataclass(frozen=True, slots=True)
class WorkerRequest:
    """A message sent from the main process to the worker subprocess."""

    command: WorkerCommand
    payload: dict[str, Any] = field(default_factory=dict)
    request_id: str = ""


@dataclass(frozen=True, slots=True)
class WorkerResponse:
    """A message sent from the worker subprocess back to the main process."""

    request_id: str
    status: str  # "ok" | "error"
    data: dict[str, Any] = field(default_factory=dict)
    error: str | None = None


# ---------------------------------------------------------------------------
# Subprocess entry-point
# ---------------------------------------------------------------------------


def _worker_loop(
    req_queue: multiprocessing.Queue,  # type: ignore[type-arg]
    resp_queue: multiprocessing.Queue,  # type: ignore[type-arg]
    memory_limit_bytes: int,
    experiment_configs: dict | None = None,
) -> None:
    """Run in a *spawned* subprocess — this is the only place MLX is imported.

    Parameters
    ----------
    req_queue:
        Incoming :class:`WorkerRequest` messages from the main process.
    resp_queue:
        Outgoing :class:`WorkerResponse` messages to the main process.
    memory_limit_bytes:
        Hard Metal memory limit passed to ``mx.metal.set_memory_limit``.
    experiment_configs:
        Optional dict of experiment configs to pass to InferenceEngine.
    """
    import mlx.core as mx  # noqa: F811 — intentionally imported here only

    from .inference import InferenceEngine

    # Lock down Metal memory before any allocation.
    # The relaxed parameter was added in later MLX versions; pass it when
    # the runtime supports it, otherwise fall back to positional-only.
    # Use the newer mx.set_memory_limit API if available (MLX 0.23+),
    # fall back to the deprecated mx.metal.set_memory_limit.
    _set_limit = getattr(mx, "set_memory_limit", None) or mx.metal.set_memory_limit
    try:
        _set_limit(memory_limit_bytes, relaxed=False)
    except TypeError:
        _set_limit(memory_limit_bytes)

    pid = os.getpid()
    engine = InferenceEngine(experiment_configs=experiment_configs)

    while True:
        try:
            request: WorkerRequest = req_queue.get()
        except (EOFError, OSError):
            break

        if request.command is WorkerCommand.SHUTDOWN:
            resp_queue.put(
                WorkerResponse(
                    request_id=request.request_id,
                    status="ok",
                    data={"message": "shutting down"},
                )
            )
            break

        if request.command is WorkerCommand.HEALTH:
            resp_queue.put(
                WorkerResponse(
                    request_id=request.request_id,
                    status="ready",
                    data={
                        "pid": pid,
                        "memory_limit_bytes": memory_limit_bytes,
                        "metal_active_memory": (
                            getattr(mx, "get_active_memory", None)
                            or mx.metal.get_active_memory
                        )(),
                        "metal_peak_memory": (
                            getattr(mx, "get_peak_memory", None)
                            or mx.metal.get_peak_memory
                        )(),
                        "loaded_models": list(engine._models.keys()),
                        "experiment_hooks": engine.hook_stats,
                    },
                )
            )
            continue

        if request.command is WorkerCommand.LOAD_MODEL:
            model_name = request.payload.get("model_name", "")
            if not model_name:
                resp_queue.put(
                    WorkerResponse(
                        request_id=request.request_id,
                        status="error",
                        error="model_name is required",
                    )
                )
                continue
            try:
                engine._ensure_loaded(model_name)
                resp_queue.put(
                    WorkerResponse(
                        request_id=request.request_id,
                        status="ok",
                        data={"model_name": model_name, "loaded": True},
                    )
                )
            except Exception as exc:
                resp_queue.put(
                    WorkerResponse(
                        request_id=request.request_id,
                        status="error",
                        error=f"failed to load {model_name}: {exc}",
                    )
                )
            continue

        if request.command is WorkerCommand.GENERATE:
            model_name = request.payload.get("model_name", "")
            prompt = request.payload.get("prompt", "")
            max_tokens = request.payload.get("max_tokens", 512)
            temperature = request.payload.get("temperature", 0.7)

            if not model_name or not prompt:
                resp_queue.put(
                    WorkerResponse(
                        request_id=request.request_id,
                        status="error",
                        error="model_name and prompt are required",
                    )
                )
                continue

            try:
                # Stream tokens back as individual responses.
                # Each has status="token"; the final has status="done".
                kv_bits = request.payload.get("kv_bits")
                kv_group_size = request.payload.get("kv_group_size", 64)
                max_kv_size = request.payload.get("max_kv_size")

                for token_text in engine.generate(
                    prompt=prompt,
                    model_name=model_name,
                    max_tokens=max_tokens,
                    temperature=temperature,
                    kv_bits=kv_bits,
                    kv_group_size=kv_group_size,
                    max_kv_size=max_kv_size,
                ):
                    resp_queue.put(
                        WorkerResponse(
                            request_id=request.request_id,
                            status="token",
                            data={"text": token_text},
                        )
                    )
                # Include generation metrics in the final response
                done_data: dict = {"finish_reason": "stop"}
                if engine.last_metrics is not None:
                    m = engine.last_metrics
                    done_data["metrics"] = {
                        "generation_tps": m.generation_tps,
                        "prompt_tps": m.prompt_tps,
                        "peak_memory_gb": m.peak_memory_gb,
                        "early_exit_rate": m.early_exit_rate,
                        "mean_confidence": m.mean_confidence,
                        "tokens_generated": m.tokens_generated,
                    }
                resp_queue.put(
                    WorkerResponse(
                        request_id=request.request_id,
                        status="done",
                        data=done_data,
                    )
                )
            except Exception as exc:
                resp_queue.put(
                    WorkerResponse(
                        request_id=request.request_id,
                        status="error",
                        error=f"generation failed: {exc}",
                    )
                )
            continue

        # Unknown command
        resp_queue.put(
            WorkerResponse(
                request_id=request.request_id,
                status="error",
                error=f"unknown command: {request.command}",
            )
        )


# ---------------------------------------------------------------------------
# Main-process handle
# ---------------------------------------------------------------------------

# Default to 96 GiB — leaves headroom on a 128 GB M5 Max for the OS and
# the HTTP server process.
_DEFAULT_MEMORY_LIMIT = 96 * 1024 * 1024 * 1024


class MetalWorker:
    """Manages a spawned subprocess that owns the Metal GPU context.

    Usage::

        worker = MetalWorker()
        worker.start()
        resp = worker.health()
        assert resp.status == "ready"
        worker.shutdown()
    """

    def __init__(
        self,
        memory_limit_bytes: int = _DEFAULT_MEMORY_LIMIT,
        experiment_configs: dict | None = None,
    ) -> None:
        self._memory_limit_bytes = memory_limit_bytes
        self._experiment_configs = experiment_configs
        self._process: multiprocessing.Process | None = None
        self._req_queue: multiprocessing.Queue | None = None  # type: ignore[type-arg]
        self._resp_queue: multiprocessing.Queue | None = None  # type: ignore[type-arg]

    # -- lifecycle -----------------------------------------------------------

    def start(self) -> None:
        """Spawn the Metal worker subprocess."""
        if self._process is not None and self._process.is_alive():
            raise RuntimeError("already running")

        ctx = multiprocessing.get_context("spawn")
        self._req_queue = ctx.Queue()
        self._resp_queue = ctx.Queue()

        self._process = ctx.Process(
            target=_worker_loop,
            args=(
                self._req_queue,
                self._resp_queue,
                self._memory_limit_bytes,
                self._experiment_configs,
            ),
            daemon=True,
            name="interfere-metal-worker",
        )
        self._process.start()

    def shutdown(self, timeout: float = 5.0) -> None:
        """Send SHUTDOWN and wait for the subprocess to exit."""
        if self._process is None or not self._process.is_alive():
            return

        self._send(WorkerRequest(command=WorkerCommand.SHUTDOWN, request_id="shutdown"))
        self._process.join(timeout=timeout)

        if self._process.is_alive():
            self._process.terminate()
            self._process.join(timeout=2.0)

        self._process = None

    def is_alive(self) -> bool:
        """Return True if the worker subprocess is running."""
        return self._process is not None and self._process.is_alive()

    # -- commands ------------------------------------------------------------

    def health(self, timeout: float = 5.0) -> WorkerResponse:
        """Ping the worker and return health information."""
        return self._roundtrip(
            WorkerRequest(
                command=WorkerCommand.HEALTH, request_id=f"health-{time.monotonic_ns()}"
            ),
            timeout=timeout,
        )

    def load_model(self, model_name: str, timeout: float = 120.0) -> WorkerResponse:
        """Load a model into the Metal subprocess. May take a while on first load."""
        return self._roundtrip(
            WorkerRequest(
                command=WorkerCommand.LOAD_MODEL,
                request_id=f"load-{time.monotonic_ns()}",
                payload={"model_name": model_name},
            ),
            timeout=timeout,
        )

    def generate(
        self,
        model_name: str,
        prompt: str,
        max_tokens: int = 512,
        temperature: float = 0.7,
        timeout: float = 60.0,
        kv_bits: int | None = None,
        kv_group_size: int = 64,
        max_kv_size: int | None = None,
    ) -> Generator[str, None, None]:
        """Stream generated tokens from the Metal subprocess.

        Yields decoded text segments. Raises on error or timeout.
        """
        request_id = f"gen-{time.monotonic_ns()}"
        payload: dict[str, Any] = {
            "model_name": model_name,
            "prompt": prompt,
            "max_tokens": max_tokens,
            "temperature": temperature,
        }
        if kv_bits is not None:
            payload["kv_bits"] = kv_bits
            payload["kv_group_size"] = kv_group_size
        if max_kv_size is not None:
            payload["max_kv_size"] = max_kv_size
        self._send(
            WorkerRequest(
                command=WorkerCommand.GENERATE,
                request_id=request_id,
                payload=payload,
            )
        )
        while True:
            resp = self._recv(timeout=timeout)
            if resp.status == "token":
                yield resp.data.get("text", "")
            elif resp.status == "done":
                return
            elif resp.status == "error":
                raise RuntimeError(resp.error or "generation failed")
            else:
                raise RuntimeError(f"unexpected status: {resp.status}")

    # -- internal transport --------------------------------------------------

    def _send(self, request: WorkerRequest) -> None:
        if (
            self._req_queue is None
            or self._process is None
            or not self._process.is_alive()
        ):
            raise RuntimeError("not running")
        self._req_queue.put(request)

    def _recv(self, timeout: float) -> WorkerResponse:
        if self._resp_queue is None:
            raise RuntimeError("not running")
        try:
            return self._resp_queue.get(timeout=timeout)
        except Exception as exc:
            raise TimeoutError(f"no response within {timeout}s") from exc

    def _roundtrip(self, request: WorkerRequest, timeout: float) -> WorkerResponse:
        self._send(request)
        return self._recv(timeout)
