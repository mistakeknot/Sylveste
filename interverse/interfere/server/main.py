"""Starlette app factory for interfere inference server."""

from __future__ import annotations

import asyncio
import json
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager

from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import JSONResponse, StreamingResponse
from starlette.routing import Route

from .experiments.config import load_experiment_configs
from .metal_worker import MetalWorker
from .schema import ChatCompletionChunk
from .thermal import ThermalMonitor


async def _health(request: Request) -> JSONResponse:
    """GET /health — server readiness check."""
    dry_run: bool = request.app.state.dry_run
    worker: MetalWorker | None = request.app.state.worker
    thermal: ThermalMonitor | None = request.app.state.thermal

    info: dict = {"status": "dry_run" if dry_run else "ready", "models": []}

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

    return JSONResponse(info)


async def _generate_dry_run_tokens(
    model: str,
) -> AsyncGenerator[str, None]:
    """Yield fake SSE tokens for dry-run mode."""
    chunk = ChatCompletionChunk(model=model)
    tokens = ["Hello", " from", " interfere", "!"]

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
) -> AsyncGenerator[str, None]:
    """Yield SSE tokens from the Metal worker subprocess."""
    chunk = ChatCompletionChunk(model=model)
    loop = asyncio.get_running_loop()

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
        data = json.dumps(chunk.to_delta_dict(content=token_text))
        yield f"data: {data}\n\n"

    data = json.dumps(chunk.to_delta_dict(finish_reason="stop"))
    yield f"data: {data}\n\n"
    yield "data: [DONE]\n\n"


async def _chat_completions(request: Request) -> JSONResponse | StreamingResponse:
    """POST /v1/chat/completions — streaming chat completion."""
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

    messages = body.get("messages")
    if not messages:
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

    dry_run: bool = request.app.state.dry_run
    worker: MetalWorker | None = request.app.state.worker

    if dry_run or worker is None:
        generator = _generate_dry_run_tokens(model)
    else:
        generator = _generate_worker_tokens(
            worker,
            model,
            messages,
            max_tokens,
            temperature,
            kv_bits=kv_bits,
            kv_group_size=kv_group_size,
        )

    return StreamingResponse(
        generator,
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
        },
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


def create_app(dry_run: bool = False) -> Starlette:
    """Create the interfere Starlette application.

    When *dry_run* is False, a MetalWorker subprocess is spawned on startup
    and shut down on application exit.
    """
    exp_configs = load_experiment_configs()
    worker: MetalWorker | None = (
        None if dry_run else MetalWorker(experiment_configs=exp_configs)
    )

    # Thermal monitoring runs in the main process (no Metal dependency)
    thermal: ThermalMonitor | None = None
    try:
        thermal = ThermalMonitor()
    except Exception:
        pass  # Non-macOS or libSystem unavailable

    @asynccontextmanager
    async def _lifespan(app: Starlette):
        # Startup
        app.state.dry_run = dry_run
        app.state.worker = None
        app.state.thermal = thermal
        if worker is not None:
            worker.start()
            app.state.worker = worker
        yield
        # Shutdown
        if worker is not None and worker.is_alive():
            worker.shutdown()

    routes = [
        Route("/health", _health, methods=["GET"]),
        Route("/v1/chat/completions", _chat_completions, methods=["POST"]),
        Route("/v1/models/load", _load_model, methods=["POST"]),
    ]

    app = Starlette(routes=routes, lifespan=_lifespan)
    # Set state eagerly so tests that skip lifespan still work
    app.state.dry_run = dry_run
    app.state.worker = None
    app.state.thermal = thermal
    return app
