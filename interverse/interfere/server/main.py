"""Starlette app factory for interfere inference server."""

from __future__ import annotations

import asyncio
import json
from typing import AsyncGenerator

from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import JSONResponse, StreamingResponse
from starlette.routing import Route

from .schema import ChatCompletionChunk


async def _health(request: Request) -> JSONResponse:
    """GET /health — server readiness check."""
    dry_run: bool = request.app.state.dry_run
    return JSONResponse(
        {
            "status": "dry_run" if dry_run else "ready",
            "models": [],
        }
    )


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

    return StreamingResponse(
        _generate_dry_run_tokens(model),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
        },
    )


def create_app(dry_run: bool = False) -> Starlette:
    """Create the interfere Starlette application."""
    routes = [
        Route("/health", _health, methods=["GET"]),
        Route("/v1/chat/completions", _chat_completions, methods=["POST"]),
    ]

    app = Starlette(routes=routes)
    app.state.dry_run = dry_run
    return app
