"""Starlette app factory for interfer inference server."""

from __future__ import annotations

import asyncio
import json
import logging
import time
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager

from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import JSONResponse, Response, StreamingResponse
from starlette.routing import Route

from .cascade import CascadeConfig, CascadeDecision, CascadeStats
from .experiments.config import load_experiment_configs
from .flashmoe_worker import FlashMoeWorker
from .metal_worker import MetalWorker
from .prom import (
    ACTIVE_REQUESTS,
    CASCADE_DECISIONS,
    ERRORS_TOTAL,
    GPU_MEMORY_BYTES,
    QUALITY_COMPOSITE,
    QUALITY_HISTOGRAM,
    QUALITY_PERPLEXITY,
    QUEUE_DEPTH,
    QUEUE_WAIT_SECONDS,
    REJECTED_TOTAL,
    REQUEST_COUNT,
    REQUEST_LATENCY,
    THERMAL_LEVEL,
    THERMAL_LEVEL_MAP,
    TOKENS_GENERATED,
    generate_metrics_text,
)
from .queue import InferenceRequest, PriorityRequestQueue, QueueFullError
from .schema import ChatCompletionChunk
from .shadow_log import ShadowEntry, ShadowLogger
from .thermal import ThermalMonitor

log = logging.getLogger("interfer")

# Maximum quality samples retained in memory (ring buffer behavior)
_MAX_QUALITY_SAMPLES = 1000


def _record_quality(
    model: str,
    quality: dict,
    quality_samples: list[float] | None,
) -> None:
    """Record quality metrics to Prometheus and the in-memory samples list."""
    composite = quality.get("composite", 0)
    perplexity = quality.get("perplexity", 0)

    QUALITY_HISTOGRAM.labels(model=model).observe(composite)
    if perplexity and perplexity != float("inf"):
        QUALITY_PERPLEXITY.labels(model=model).observe(perplexity)
    QUALITY_COMPOSITE.set(composite)

    if quality_samples is not None:
        quality_samples.append(composite)
        # Trim to bounded size to prevent unbounded memory growth
        if len(quality_samples) > _MAX_QUALITY_SAMPLES:
            del quality_samples[: len(quality_samples) - _MAX_QUALITY_SAMPLES]


async def _health(request: Request) -> JSONResponse:
    """GET /health — server readiness check."""
    dry_run: bool = request.app.state.dry_run
    worker: MetalWorker | None = request.app.state.worker
    flashmoe: FlashMoeWorker | None = request.app.state.flashmoe_worker
    thermal: ThermalMonitor | None = request.app.state.thermal

    # Determine server status
    if dry_run:
        status = "dry_run"
    elif worker is not None and worker.is_degraded:
        status = "degraded"
    elif worker is not None and worker.is_restarting:
        status = "restarting"
    elif worker is not None and worker.is_alive():
        status = "ready"
    elif flashmoe is not None and flashmoe.is_alive():
        status = "ready"
    elif flashmoe is not None and flashmoe.is_degraded:
        status = "degraded"
    elif worker is not None or flashmoe is not None:
        status = "worker_down"
    else:
        status = "no_worker"

    info: dict = {"status": status, "models": []}

    if worker is not None:
        info["restart_count"] = worker.restart_count
        if worker.last_crash is not None:
            info["last_crash"] = {
                "classification": worker.last_crash.classification,
                "exit_code": worker.last_crash.exit_code,
                "timestamp": worker.last_crash.timestamp,
            }

    if thermal is not None:
        try:
            ts = thermal.read()
            info["thermal"] = {"level": ts.level, "raw_value": ts.raw_value}
            info["thermal_state"] = ts.raw_value
        except Exception:
            info["thermal"] = {"level": "unknown", "raw_value": -1}

    if worker is not None and worker.is_alive():
        try:
            resp = worker.health(timeout=2.0)
            info["worker"] = resp.data
            info["models"] = resp.data.get("loaded_models", [])
        except Exception:
            info["worker"] = {"status": "unresponsive"}

    if flashmoe is not None:
        fm_health = flashmoe.health(timeout=2.0)
        info["flashmoe"] = fm_health
        # Merge flash-moe models into the models list
        for m in fm_health.get("loaded_models", []):
            if m not in info["models"]:
                info["models"].append(m)

    batch_sched = getattr(request.app.state, "batch_scheduler", None)
    if batch_sched is not None and hasattr(batch_sched, "stats"):
        info["batch_scheduler"] = {
            "enabled": True,
            "pending": batch_sched.pending_count,
            "stats": batch_sched.stats.to_dict(),
        }

    return JSONResponse(info)


async def _generate_dry_run_tokens(
    model: str,
) -> AsyncGenerator[str, None]:
    """Yield fake SSE tokens for dry-run mode."""
    chunk = ChatCompletionChunk(model=model)
    tokens = ["Hello", " from", " interfer", "!"]

    for token in tokens:
        data = json.dumps(chunk.to_delta_dict(content=token))
        yield f"data: {data}\n\n"
        await asyncio.sleep(0.01)

    # Final chunk with finish_reason
    data = json.dumps(chunk.to_delta_dict(finish_reason="stop"))
    yield f"data: {data}\n\n"
    yield "data: [DONE]\n\n"


async def _generate_worker_tokens(
    worker: MetalWorker,
    model: str,
    messages: list[dict],
    max_tokens: int,
    temperature: float,
    kv_bits: int | None = None,
    kv_group_size: int = 64,
    quality_samples: list[float] | None = None,
) -> AsyncGenerator[str, None]:
    """Yield SSE tokens from the Metal worker subprocess."""
    chunk = ChatCompletionChunk(model=model)
    loop = asyncio.get_running_loop()
    t0 = time.monotonic()
    completion_tokens = 0
    tok_counter = TOKENS_GENERATED.labels(model=model)

    # Run the blocking generator in a thread so we don't block the event loop.
    # Each iteration of worker.generate() blocks on resp_queue.get().
    token_iter = worker.generate(
        model_name=model,
        messages=messages,
        max_tokens=max_tokens,
        temperature=temperature,
        kv_bits=kv_bits,
        kv_group_size=kv_group_size,
    )

    def _next_token():
        try:
            return next(token_iter)
        except StopIteration:
            return None

    while True:
        token_text = await loop.run_in_executor(None, _next_token)
        if token_text is None:
            break
        completion_tokens += 1
        tok_counter.inc()
        data = json.dumps(chunk.to_delta_dict(content=token_text))
        yield f"data: {data}\n\n"

    # Final chunk with usage stats from the Metal worker
    elapsed = time.monotonic() - t0
    metrics = worker.last_generation_metrics
    final = chunk.to_delta_dict(finish_reason="stop")
    final["usage"] = {
        "completion_tokens": completion_tokens,
        "total_time_s": round(elapsed, 3),
        "generation_tps": metrics.get("generation_tps", 0),
        "prompt_tps": metrics.get("prompt_tps", 0),
        "peak_memory_gb": metrics.get("peak_memory_gb", 0),
        "early_exit_rate": metrics.get("early_exit_rate", 0),
        "mean_confidence": metrics.get("mean_confidence", 0),
    }
    if "quality" in metrics:
        final["quality"] = metrics["quality"]
        _record_quality(model, metrics["quality"], quality_samples)
    data = json.dumps(final)
    yield f"data: {data}\n\n"
    yield "data: [DONE]\n\n"

    # Log request metrics
    log.info(
        "request model=%s tokens=%d time=%.2fs tps=%.1f prompt_tps=%.1f mem=%.2fGB q=%.3f",
        model,
        completion_tokens,
        elapsed,
        metrics.get("generation_tps", 0),
        metrics.get("prompt_tps", 0),
        metrics.get("peak_memory_gb", 0),
        metrics.get("quality", {}).get("composite", 0),
    )


async def _generate_flashmoe_tokens(
    flashmoe: FlashMoeWorker,
    model: str,
    messages: list[dict],
    max_tokens: int,
    temperature: float,
) -> AsyncGenerator[str, None]:
    """Yield SSE tokens from the flash-moe subprocess via HTTP proxy."""
    chunk = ChatCompletionChunk(model=model)
    loop = asyncio.get_running_loop()
    t0 = time.monotonic()
    completion_tokens = 0
    tok_counter = TOKENS_GENERATED.labels(model=model)

    token_iter = flashmoe.generate(
        model_name=model,
        messages=messages,
        max_tokens=max_tokens,
        temperature=temperature,
    )

    def _next_token():
        try:
            return next(token_iter)
        except StopIteration:
            return None

    while True:
        token_text = await loop.run_in_executor(None, _next_token)
        if token_text is None:
            break
        completion_tokens += 1
        tok_counter.inc()
        data = json.dumps(chunk.to_delta_dict(content=token_text))
        yield f"data: {data}\n\n"

    elapsed = time.monotonic() - t0
    metrics = flashmoe.last_generation_metrics
    final = chunk.to_delta_dict(finish_reason="stop")
    final["usage"] = {
        "completion_tokens": completion_tokens,
        "total_time_s": round(elapsed, 3),
        "generation_tps": metrics.get("generation_tps", 0),
        "prompt_tps": metrics.get("prompt_tps", 0),
        "peak_memory_gb": metrics.get("peak_memory_gb", 0),
        "early_exit_rate": 0,
        "mean_confidence": 0,
        "backend": "flash-moe",
    }
    data = json.dumps(final)
    yield f"data: {data}\n\n"
    yield "data: [DONE]\n\n"

    log.info(
        "request model=%s backend=flash-moe tokens=%d time=%.2fs tps=%.1f",
        model,
        completion_tokens,
        elapsed,
        metrics.get("generation_tps", 0),
    )


def _cascade_decide(config: CascadeConfig, confidence: float) -> CascadeDecision:
    """Map a confidence score to a cascade decision."""
    if confidence >= config.accept_threshold:
        return CascadeDecision.ACCEPT
    if confidence >= config.cloud_threshold:
        return CascadeDecision.ESCALATE
    return CascadeDecision.CLOUD


async def _generate_with_probe_prefix(
    worker: MetalWorker,
    model: str,
    messages: list[dict],
    max_tokens: int,
    temperature: float,
    probe_tokens: list[str],
    kv_bits: int | None = None,
    kv_group_size: int = 64,
    quality_samples: list[float] | None = None,
) -> AsyncGenerator[str, None]:
    """Yield probe tokens first, then continue generating the rest."""
    chunk = ChatCompletionChunk(model=model)

    # Yield the probe tokens we already have
    for token_text in probe_tokens:
        data = json.dumps(chunk.to_delta_dict(content=token_text))
        yield f"data: {data}\n\n"

    # Continue generating the remaining tokens
    remaining = max_tokens - len(probe_tokens)
    if remaining > 0:
        async for sse_line in _generate_worker_tokens(
            worker,
            model,
            messages,
            remaining,
            temperature,
            kv_bits=kv_bits,
            kv_group_size=kv_group_size,
            quality_samples=quality_samples,
        ):
            yield sse_line
    else:
        # All tokens came from the probe — send final chunk
        data = json.dumps(chunk.to_delta_dict(finish_reason="stop"))
        yield f"data: {data}\n\n"
        yield "data: [DONE]\n\n"


async def _chat_completions(request: Request) -> JSONResponse | StreamingResponse:
    """POST /v1/chat/completions — streaming chat completion.

    When cascade is enabled and the worker is available, probes the model
    for confidence before committing to full generation. If confidence is
    too low, escalates to a larger model or signals cloud fallback.
    """
    t0 = time.monotonic()
    worker: MetalWorker | None = request.app.state.worker
    inference_queue: PriorityRequestQueue = request.app.state.inference_queue
    thermal_reject_threshold: int = request.app.state.thermal_reject_threshold

    # -- Admission control: thermal gate --
    t_mon: ThermalMonitor | None = request.app.state.thermal
    if t_mon is not None:
        try:
            ts = t_mon.read()
            thermal_val = THERMAL_LEVEL_MAP.get(ts.level, 0)
            if thermal_val >= thermal_reject_threshold:
                REJECTED_TOTAL.labels(reason="thermal").inc()
                return JSONResponse(
                    {
                        "error": {
                            "message": f"Server thermally throttled ({ts.level})",
                            "type": "overloaded",
                        }
                    },
                    status_code=503,
                    headers={"Retry-After": "30"},
                )
        except Exception:
            pass  # Thermal read failure — allow request through

    # -- Admission control: queue depth gate --
    QUEUE_DEPTH.set(inference_queue.depth)
    if inference_queue.depth >= inference_queue.max_depth:
        REJECTED_TOTAL.labels(reason="queue_full").inc()
        return JSONResponse(
            {
                "error": {
                    "message": f"Server busy ({inference_queue.depth} requests queued)",
                    "type": "overloaded",
                }
            },
            status_code=503,
            headers={"Retry-After": "10"},
        )

    # -- Admission control: worker health gate --
    if worker is not None and worker.is_degraded:
        REJECTED_TOTAL.labels(reason="degraded").inc()
        return JSONResponse(
            {
                "error": {
                    "message": "Worker degraded — max restarts exceeded",
                    "type": "server_error",
                    "restart_count": worker.restart_count,
                }
            },
            status_code=503,
        )
    if worker is not None and worker.is_restarting:
        REJECTED_TOTAL.labels(reason="restarting").inc()
        return JSONResponse(
            {
                "error": {
                    "message": "Worker restarting — retry shortly",
                    "type": "server_error",
                }
            },
            status_code=503,
            headers={"Retry-After": "5"},
        )

    request_count: dict = request.app.state.request_count
    latency_samples: list = request.app.state.latency_samples
    quality_samples: list = request.app.state.quality_samples
    cascade_config: CascadeConfig = request.app.state.cascade_config
    cascade_stats: CascadeStats = request.app.state.cascade_stats
    model_tiers: list[str] = request.app.state.model_tiers
    shadow_logger: ShadowLogger | None = request.app.state.shadow_logger

    # -- Enqueue and track wait time --
    # Client priority: X-Interfere-Priority header (default 5, lower = higher)
    client_priority = int(request.headers.get("x-interfer-priority", "5"))
    client_priority = max(0, min(10, client_priority))  # clamp to 0-10

    request_count["total"] += 1
    ACTIVE_REQUESTS.inc()

    try:
        body = await request.json()
    except Exception:
        request_count["errors"] += 1
        ACTIVE_REQUESTS.dec()
        ERRORS_TOTAL.labels(error_type="invalid_json").inc()
        REQUEST_COUNT.labels(status="4xx").inc()
        return JSONResponse(
            {
                "error": {
                    "message": "Invalid JSON body",
                    "type": "invalid_request_error",
                }
            },
            status_code=400,
        )

    messages = body.get("messages")
    if not messages:
        request_count["errors"] += 1
        ACTIVE_REQUESTS.dec()
        ERRORS_TOTAL.labels(error_type="missing_messages").inc()
        REQUEST_COUNT.labels(status="4xx").inc()
        return JSONResponse(
            {
                "error": {
                    "message": "messages is required and must be non-empty",
                    "type": "invalid_request_error",
                }
            },
            status_code=400,
        )

    model = body.get("model", "dry-run")
    max_tokens = body.get("max_tokens", 512)
    temperature = body.get("temperature", 0.7)
    kv_bits = body.get("kv_bits")
    kv_group_size = body.get("kv_group_size", 64)

    # Track this request in the queue for depth/backpressure visibility
    queue_entry = InferenceRequest(
        request_id=f"req-{id(request)}",
        priority=client_priority,
        prompt="",  # not used for tracking, just depth
        model=model,
        max_tokens=max_tokens,
    )
    try:
        await inference_queue.put(queue_entry)
    except QueueFullError:
        ACTIVE_REQUESTS.dec()
        REJECTED_TOTAL.labels(reason="queue_full").inc()
        return JSONResponse(
            {
                "error": {
                    "message": f"Server busy ({inference_queue.depth} requests queued)",
                    "type": "overloaded",
                }
            },
            status_code=503,
            headers={"Retry-After": "10"},
        )
    QUEUE_DEPTH.set(inference_queue.depth)
    queue_wait_start = time.monotonic()

    dry_run: bool = request.app.state.dry_run
    flashmoe: FlashMoeWorker | None = request.app.state.flashmoe_worker
    flashmoe_model: str = request.app.state.flashmoe_model_name

    # --- Cascade logic ---
    cascade_header: dict = {}

    # Route to flash-moe if model matches (direct request or cascade terminal)
    if (
        not dry_run
        and flashmoe is not None
        and flashmoe.is_alive()
        and (
            model == flashmoe_model
            or model.startswith("flash-moe/")
            or model == "flash-moe"
        )
    ):
        generator = _generate_flashmoe_tokens(
            flashmoe, model, messages, max_tokens, temperature
        )
    elif dry_run or worker is None:
        generator = _generate_dry_run_tokens(model)
    elif cascade_config.enabled and model_tiers:
        # Run cascade: probe each tier until one accepts or we exhaust all
        cascade_stats.total_requests += 1
        generator = None
        models_tried: list[str] = []

        for i, tier_model in enumerate(model_tiers):
            models_tried.append(tier_model)
            loop = asyncio.get_running_loop()
            probe_resp = await loop.run_in_executor(
                None,
                lambda m=tier_model: worker.probe(
                    model_name=m,
                    messages=messages,
                    probe_tokens=cascade_config.probe_tokens,
                    temperature=temperature,
                ),
            )

            if probe_resp.status == "error":
                log.warning(
                    "cascade probe failed for %s: %s", tier_model, probe_resp.error
                )
                continue

            avg_conf = probe_resp.data.get("avg_confidence", 0.0)
            probe_toks = probe_resp.data.get("tokens", [])
            decision = _cascade_decide(cascade_config, avg_conf)

            cascade_header = {
                "decision": decision.value,
                "model": tier_model,
                "confidence": str(round(avg_conf, 4)),
                "models_tried": ",".join(models_tried),
                "escalations": str(i),
            }

            if decision == CascadeDecision.ACCEPT:
                cascade_stats.accepts += 1
                CASCADE_DECISIONS.labels(outcome="accept").inc()
                cascade_stats.total_probe_time_s += probe_resp.data.get(
                    "probe_time_s", 0
                )
                # Shadow log: local model accepted — log counterfactual cloud cost
                if shadow_logger is not None:
                    shadow_logger.log(
                        ShadowEntry(
                            cascade_decision="accept",
                            confidence=avg_conf,
                            local_model=tier_model,
                            local_tokens=max_tokens,
                            cloud_tokens_est=max_tokens,
                            probe_time_s=probe_resp.data.get("probe_time_s", 0),
                            models_tried=",".join(models_tried),
                            escalation_count=i,
                        )
                    )
                # Yield probe tokens, then continue with same model
                generator = _generate_with_probe_prefix(
                    worker,
                    tier_model,
                    messages,
                    max_tokens,
                    temperature,
                    probe_toks,
                    kv_bits=kv_bits,
                    kv_group_size=kv_group_size,
                    quality_samples=quality_samples,
                )
                break

            if decision == CascadeDecision.ESCALATE:
                cascade_stats.total_probe_time_s += probe_resp.data.get(
                    "probe_time_s", 0
                )
                if i < len(model_tiers) - 1:
                    cascade_stats.escalations += 1
                    CASCADE_DECISIONS.labels(outcome="escalate").inc()
                    continue  # try next tier
                # Last tier — fall through to cloud

            # Cloud fallback
            cascade_stats.cloud_fallbacks += 1
            CASCADE_DECISIONS.labels(outcome="cloud").inc()
            cascade_stats.total_probe_time_s += probe_resp.data.get("probe_time_s", 0)
            # Shadow log: cloud fallback — no local savings
            if shadow_logger is not None:
                shadow_logger.log(
                    ShadowEntry(
                        cascade_decision="cloud",
                        confidence=avg_conf,
                        local_model=tier_model,
                        local_tokens=0,
                        cloud_tokens_est=max_tokens,
                        probe_time_s=probe_resp.data.get("probe_time_s", 0),
                        models_tried=",".join(models_tried),
                        escalation_count=i,
                    )
                )
            cascade_header["decision"] = CascadeDecision.CLOUD.value
            cascade_header["model"] = "cloud"
            # Dequeue: cloud fallback exits the queue
            try:
                await inference_queue.get()
            except Exception:
                pass
            QUEUE_DEPTH.set(inference_queue.depth)
            QUEUE_WAIT_SECONDS.observe(time.monotonic() - queue_wait_start)
            latency_samples.append(time.monotonic() - t0)
            REQUEST_LATENCY.labels(model="cloud").observe(time.monotonic() - t0)
            REQUEST_COUNT.labels(status="2xx").inc()
            ACTIVE_REQUESTS.dec()
            return JSONResponse(
                {
                    "cascade": "cloud_fallback",
                    "models_tried": models_tried,
                    "confidence": avg_conf,
                    "message": "All local models below confidence threshold — route to cloud",
                },
                status_code=200,
                headers={
                    "X-Interfere-Cascade": json.dumps(cascade_header),
                },
            )

        if generator is None:
            # All probes errored — fall back to first model without cascade
            generator = _generate_worker_tokens(
                worker,
                model_tiers[0] if model_tiers else model,
                messages,
                max_tokens,
                temperature,
                kv_bits=kv_bits,
                kv_group_size=kv_group_size,
                quality_samples=quality_samples,
            )
    else:
        # No cascade — direct generation
        generator = _generate_worker_tokens(
            worker,
            model,
            messages,
            max_tokens,
            temperature,
            kv_bits=kv_bits,
            kv_group_size=kv_group_size,
            quality_samples=quality_samples,
        )

    # Dequeue: request is being served
    try:
        await inference_queue.get()
    except Exception:
        pass
    QUEUE_DEPTH.set(inference_queue.depth)
    QUEUE_WAIT_SECONDS.observe(time.monotonic() - queue_wait_start)

    elapsed = time.monotonic() - t0
    latency_samples.append(elapsed)
    REQUEST_LATENCY.labels(model=model).observe(elapsed)
    REQUEST_COUNT.labels(status="2xx").inc()
    ACTIVE_REQUESTS.dec()

    headers = {
        "Cache-Control": "no-cache",
        "Connection": "keep-alive",
    }
    if cascade_header:
        headers["X-Interfere-Cascade"] = json.dumps(cascade_header)

    return StreamingResponse(
        generator,
        media_type="text/event-stream",
        headers=headers,
    )


async def _load_model(request: Request) -> JSONResponse:
    """POST /v1/models/load — preload a model into the Metal subprocess."""
    worker: MetalWorker | None = request.app.state.worker
    if worker is None or not worker.is_alive():
        return JSONResponse(
            {"error": {"message": "Worker not available", "type": "server_error"}},
            status_code=503,
        )

    try:
        body = await request.json()
    except Exception:
        return JSONResponse(
            {
                "error": {
                    "message": "Invalid JSON body",
                    "type": "invalid_request_error",
                }
            },
            status_code=400,
        )

    model_name = body.get("model", "")
    if not model_name:
        return JSONResponse(
            {
                "error": {
                    "message": "model is required",
                    "type": "invalid_request_error",
                }
            },
            status_code=400,
        )

    resp = worker.load_model(model_name, timeout=120.0)
    if resp.status == "error":
        return JSONResponse(
            {"error": {"message": resp.error, "type": "server_error"}},
            status_code=500,
        )

    return JSONResponse({"status": "loaded", "model": model_name, "data": resp.data})


def create_app(
    dry_run: bool = False,
    model_tiers: list[str] | None = None,
    cascade_config: CascadeConfig | None = None,
    max_queue_depth: int = 8,
    thermal_reject_level: str = "heavy",
    flashmoe_binary: str = "",
    flashmoe_model_path: str = "",
    flashmoe_port: int = 0,
    flashmoe_extra_args: list[str] | None = None,
    flashmoe_model_name: str = "flash-moe",
    flashmoe_only: bool = False,
    flashmoe_malloc_cache: int = 0,
    flashmoe_predict: bool = False,
    batch_scheduler: object | None = None,
) -> Starlette:
    """Create the interfer Starlette application.

    When *dry_run* is False, a MetalWorker subprocess is spawned on startup
    and shut down on application exit.

    *model_tiers* configures the cascade ordering (smallest → largest).
    *cascade_config* tunes thresholds; defaults are sensible.
    *max_queue_depth* bounds the inference waiting room (503 when full).
    *thermal_reject_level* rejects new requests at this thermal pressure
    or above ('heavy', 'trapping', 'sleeping'). Set to 'sleeping' to
    only reject at the most extreme level.

    Flash-MoE integration:
    *flashmoe_binary* path to the infer binary. If set, spawns a
    FlashMoeWorker alongside (or instead of) the MetalWorker.
    *flashmoe_model_path* model directory for flash-moe.
    *flashmoe_port* port for flash-moe's HTTP API (0 = auto-pick).
    *flashmoe_extra_args* extra CLI args passed to the binary.
    *flashmoe_model_name* model name used for routing requests.
    *flashmoe_only* if True, skip MetalWorker entirely.
    """
    exp_configs = load_experiment_configs()

    # MetalWorker: skip if dry_run or flashmoe_only
    skip_metal = dry_run or flashmoe_only
    worker: MetalWorker | None = (
        None if skip_metal else MetalWorker(experiment_configs=exp_configs)
    )

    # FlashMoeWorker: create if binary path provided
    flashmoe_worker: FlashMoeWorker | None = None
    if flashmoe_binary and not dry_run:
        flashmoe_worker = FlashMoeWorker(
            binary_path=flashmoe_binary,
            model_path=flashmoe_model_path,
            port=flashmoe_port,
            extra_args=flashmoe_extra_args,
            malloc_cache=flashmoe_malloc_cache,
            predict=flashmoe_predict,
        )
    _inference_queue = PriorityRequestQueue(max_depth=max_queue_depth)
    _thermal_reject_threshold = THERMAL_LEVEL_MAP.get(thermal_reject_level, 2)

    # Thermal monitoring runs in the main process (no Metal dependency)
    thermal: ThermalMonitor | None = None
    try:
        thermal = ThermalMonitor()
    except Exception:
        pass  # Non-macOS or libSystem unavailable

    # Cascade and metrics state — shared across requests via app.state
    _cascade_config = cascade_config or CascadeConfig()
    _cascade_stats = CascadeStats()
    _request_count: dict = {"total": 0, "errors": 0}
    _latency_samples: list[float] = []
    _model_tiers = model_tiers or []
    _quality_samples: list[float] = []  # composite quality scores

    # Shadow cost logger — writes to interstat's SQLite DB
    _shadow_logger: ShadowLogger | None = None
    try:
        _shadow_logger = ShadowLogger()
    except Exception:
        pass  # interstat DB not available — cascade still works without logging

    @asynccontextmanager
    async def _lifespan(app: Starlette):
        # Startup
        app.state.dry_run = dry_run
        app.state.worker = None
        app.state.flashmoe_worker = None
        app.state.flashmoe_model_name = flashmoe_model_name
        app.state.thermal = thermal
        app.state.cascade_config = _cascade_config
        app.state.cascade_stats = _cascade_stats
        app.state.model_tiers = _model_tiers
        app.state.request_count = _request_count
        app.state.latency_samples = _latency_samples
        app.state.quality_samples = _quality_samples
        app.state.shadow_logger = _shadow_logger
        app.state.inference_queue = _inference_queue
        app.state.thermal_reject_threshold = _thermal_reject_threshold
        app.state.batch_scheduler = batch_scheduler
        if worker is not None:
            worker.start()
            app.state.worker = worker
        if flashmoe_worker is not None:
            flashmoe_worker.start()
            app.state.flashmoe_worker = flashmoe_worker
        if batch_scheduler is not None and hasattr(batch_scheduler, "start"):
            await batch_scheduler.start()
        yield
        # Shutdown
        if batch_scheduler is not None and hasattr(batch_scheduler, "stop"):
            await batch_scheduler.stop()
        if _shadow_logger is not None:
            _shadow_logger.close()
        if flashmoe_worker is not None and flashmoe_worker.is_alive():
            flashmoe_worker.shutdown()
        if worker is not None and worker.is_alive():
            worker.shutdown()

    def _update_lazy_gauges() -> None:
        """Update gauges that are read on scrape, not per-request."""
        if thermal is not None:
            try:
                ts = thermal.read()
                THERMAL_LEVEL.set(THERMAL_LEVEL_MAP.get(ts.level, -1))
            except Exception:
                pass

        if worker is not None and worker.is_alive():
            try:
                resp = worker.health(timeout=2.0)
                d = resp.data
                GPU_MEMORY_BYTES.labels(type="active").set(
                    d.get("metal_active_memory", 0)
                )
                GPU_MEMORY_BYTES.labels(type="peak").set(d.get("metal_peak_memory", 0))
            except Exception:
                pass

        if _quality_samples:
            QUALITY_COMPOSITE.set(_quality_samples[-1])

    async def _metrics(request: Request) -> JSONResponse | Response:
        """GET /metrics — JSON or Prometheus format based on Accept header."""
        w: MetalWorker | None = request.app.state.worker
        t: ThermalMonitor | None = request.app.state.thermal

        # Content negotiation: text/plain → Prometheus, else JSON
        accept = request.headers.get("accept", "")
        if "text/plain" in accept:
            _update_lazy_gauges()
            return Response(
                content=generate_metrics_text(),
                media_type="text/plain; version=0.0.4; charset=utf-8",
            )

        # Default: existing JSON format (backward compatible)
        data: dict = {
            "requests": _request_count.copy(),
            "latency": {},
            "quality": {},
            "thermal": {},
            "memory": {},
            "models": [],
            "cascade": _cascade_stats.to_dict(),
        }

        if _latency_samples:
            sorted_lat = sorted(_latency_samples)
            n = len(sorted_lat)
            data["latency"] = {
                "count": n,
                "mean_s": round(sum(sorted_lat) / n, 3),
                "p50_s": round(sorted_lat[n // 2], 3),
                "p95_s": round(sorted_lat[int(n * 0.95)], 3) if n >= 20 else None,
                "p99_s": round(sorted_lat[int(n * 0.99)], 3) if n >= 100 else None,
            }

        if _quality_samples:
            sorted_q = sorted(_quality_samples)
            nq = len(sorted_q)
            data["quality"] = {
                "count": nq,
                "mean": round(sum(sorted_q) / nq, 4),
                "p50": round(sorted_q[nq // 2], 4),
                "min": round(sorted_q[0], 4),
                "max": round(sorted_q[-1], 4),
            }

        if t is not None:
            try:
                ts = t.read()
                data["thermal"] = {"level": ts.level, "raw_value": ts.raw_value}
            except Exception:
                pass

        if w is not None and w.is_alive():
            try:
                resp = w.health(timeout=2.0)
                d = resp.data
                data["memory"] = {
                    "active_mb": round(d.get("metal_active_memory", 0) / 1e6, 1),
                    "peak_mb": round(d.get("metal_peak_memory", 0) / 1e6, 1),
                    "limit_gb": round(d.get("memory_limit_bytes", 0) / 1e9, 1),
                }
                data["models"] = d.get("loaded_models", [])
                data["experiment_hooks"] = d.get("experiment_hooks", {})
            except Exception:
                pass

        return JSONResponse(data)

    async def _metrics_prometheus(request: Request) -> Response:
        """GET /metrics/prometheus — always Prometheus exposition format."""
        _update_lazy_gauges()
        return Response(
            content=generate_metrics_text(),
            media_type="text/plain; version=0.0.4; charset=utf-8",
        )

    async def _quality_stats(request: Request) -> JSONResponse:
        """GET /v1/quality — quality scoring summary for interspect evidence.

        Returns aggregate and recent quality metrics. Consumers can poll
        this endpoint to build quality evidence for model promotion.
        """
        data: dict = {"total_scored": len(_quality_samples), "recent": []}

        if _quality_samples:
            sorted_q = sorted(_quality_samples)
            nq = len(sorted_q)
            data["aggregate"] = {
                "mean": round(sum(sorted_q) / nq, 4),
                "p50": round(sorted_q[nq // 2], 4),
                "p5": round(sorted_q[max(0, int(nq * 0.05))], 4),
                "p95": round(sorted_q[min(nq - 1, int(nq * 0.95))], 4),
                "min": round(sorted_q[0], 4),
                "max": round(sorted_q[-1], 4),
            }
            # Last 10 scores for recent trend
            data["recent"] = [round(s, 4) for s in _quality_samples[-10:]]
        else:
            data["aggregate"] = {}

        return JSONResponse(data)

    routes = [
        Route("/health", _health, methods=["GET"]),
        Route("/metrics", _metrics, methods=["GET"]),
        Route("/metrics/prometheus", _metrics_prometheus, methods=["GET"]),
        Route("/v1/chat/completions", _chat_completions, methods=["POST"]),
        Route("/v1/models/load", _load_model, methods=["POST"]),
        Route("/v1/quality", _quality_stats, methods=["GET"]),
    ]

    app = Starlette(routes=routes, lifespan=_lifespan)
    # Set state eagerly so tests that skip lifespan still work
    app.state.dry_run = dry_run
    app.state.worker = None
    app.state.flashmoe_worker = None
    app.state.flashmoe_model_name = flashmoe_model_name
    app.state.thermal = thermal
    app.state.cascade_config = _cascade_config
    app.state.cascade_stats = _cascade_stats
    app.state.model_tiers = _model_tiers
    app.state.request_count = _request_count
    app.state.latency_samples = _latency_samples
    app.state.quality_samples = _quality_samples
    app.state.shadow_logger = _shadow_logger
    app.state.inference_queue = _inference_queue
    app.state.thermal_reject_threshold = _thermal_reject_threshold
    app.state.batch_scheduler = batch_scheduler
    return app
