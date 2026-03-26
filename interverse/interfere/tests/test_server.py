"""Tests for the interfere HTTP server."""

from __future__ import annotations

import json

import httpx
import pytest

from server.main import create_app


@pytest.fixture
def app():
    return create_app(dry_run=True)


@pytest.fixture
def client(app):
    transport = httpx.ASGITransport(app=app)
    return httpx.AsyncClient(transport=transport, base_url="http://testserver")


@pytest.mark.asyncio
async def test_health_endpoint(client: httpx.AsyncClient) -> None:
    """GET /health returns 200 with status in ('ready', 'dry_run')."""
    resp = await client.get("/health")
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] in ("ready", "dry_run")
    assert "models" in data


@pytest.mark.asyncio
async def test_chat_completions_returns_sse(client: httpx.AsyncClient) -> None:
    """POST /v1/chat/completions with stream=True returns SSE stream."""
    resp = await client.post(
        "/v1/chat/completions",
        json={
            "model": "test-model",
            "messages": [{"role": "user", "content": "Hello"}],
            "stream": True,
        },
    )
    assert resp.status_code == 200
    assert "text/event-stream" in resp.headers["content-type"]

    # Parse SSE events from the response body
    body = resp.text
    lines = [ln for ln in body.strip().split("\n\n") if ln.startswith("data: ")]
    assert len(lines) >= 2  # at least one token + [DONE]

    # Last line should be the [DONE] sentinel
    assert lines[-1].strip() == "data: [DONE]"

    # Earlier lines should be valid JSON chunks
    first_data = json.loads(lines[0].removeprefix("data: "))
    assert first_data["object"] == "chat.completion.chunk"
    assert first_data["model"] == "test-model"


@pytest.mark.asyncio
async def test_chat_completions_rejects_missing_messages(
    client: httpx.AsyncClient,
) -> None:
    """POST /v1/chat/completions without messages returns 400."""
    resp = await client.post(
        "/v1/chat/completions",
        json={"model": "test-model"},
    )
    assert resp.status_code == 400
    data = resp.json()
    assert "error" in data
