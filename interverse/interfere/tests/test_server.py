"""Tests for the interfere HTTP server."""

from __future__ import annotations

import json

import httpx
import pytest

from server.__main__ import _parse_args
from server.cascade import CascadeConfig
from server.main import create_app


@pytest.fixture
def app():
    return create_app(dry_run=True, thermal_reject_level="sleeping")


@pytest.fixture
def cascade_app():
    """App with cascade enabled and model tiers (still dry-run)."""
    return create_app(
        dry_run=True,
        model_tiers=["small-model", "large-model"],
        cascade_config=CascadeConfig(enabled=True),
        thermal_reject_level="sleeping",
    )


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


def test_parse_args_defaults() -> None:
    """__main__ parser has correct defaults."""
    args = _parse_args([])
    assert args.port == 8421
    assert args.host == "127.0.0.1"
    assert args.dry_run is False


def test_parse_args_dry_run() -> None:
    """--dry-run flag is parsed correctly."""
    args = _parse_args(["--dry-run", "--port", "9000"])
    assert args.dry_run is True
    assert args.port == 9000


def test_parse_args_cascade() -> None:
    """Cascade CLI args are parsed correctly."""
    args = _parse_args(
        [
            "--model-tiers",
            "small-4bit",
            "large-4bit",
            "--cascade-accept",
            "0.85",
            "--cascade-cloud",
            "0.3",
        ]
    )
    assert args.model_tiers == ["small-4bit", "large-4bit"]
    assert args.cascade_accept == 0.85
    assert args.cascade_cloud == 0.3
    assert args.no_cascade is False


def test_parse_args_no_cascade() -> None:
    """--no-cascade disables cascade."""
    args = _parse_args(["--no-cascade"])
    assert args.no_cascade is True


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


@pytest.mark.asyncio
async def test_metrics_includes_cascade_stats(client: httpx.AsyncClient) -> None:
    """GET /metrics includes cascade section."""
    resp = await client.get("/metrics")
    assert resp.status_code == 200
    data = resp.json()
    assert "cascade" in data
    assert "total_requests" in data["cascade"]
    assert "accept_rate" in data["cascade"]


@pytest.mark.asyncio
async def test_metrics_includes_quality_section(client: httpx.AsyncClient) -> None:
    """GET /metrics includes quality section (empty when no real inference)."""
    resp = await client.get("/metrics")
    assert resp.status_code == 200
    data = resp.json()
    assert "quality" in data


@pytest.mark.asyncio
async def test_metrics_tracks_request_count(client: httpx.AsyncClient) -> None:
    """Request count increments after chat completions calls."""
    # Make a successful request
    await client.post(
        "/v1/chat/completions",
        json={"model": "m", "messages": [{"role": "user", "content": "Hi"}]},
    )
    # Make a failing request (no messages)
    await client.post("/v1/chat/completions", json={"model": "m"})

    resp = await client.get("/metrics")
    data = resp.json()
    assert data["requests"]["total"] == 2
    assert data["requests"]["errors"] == 1


@pytest.mark.asyncio
async def test_dry_run_skips_cascade(cascade_app) -> None:
    """In dry-run mode, cascade model_tiers are ignored — direct dry-run generation."""
    transport = httpx.ASGITransport(app=cascade_app)
    async with httpx.AsyncClient(
        transport=transport, base_url="http://testserver"
    ) as c:
        resp = await c.post(
            "/v1/chat/completions",
            json={
                "model": "test-model",
                "messages": [{"role": "user", "content": "Hello"}],
            },
        )
        assert resp.status_code == 200
        # No cascade header in dry-run
        assert "X-Interfere-Cascade" not in resp.headers
        # Still returns SSE
        assert "text/event-stream" in resp.headers["content-type"]
