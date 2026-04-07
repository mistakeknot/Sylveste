"""Tests for admission control: queue backpressure and thermal gate."""

from __future__ import annotations

from unittest.mock import patch

import httpx
import pytest

from server.main import create_app


@pytest.mark.asyncio
async def test_normal_request_passes_admission(client: httpx.AsyncClient) -> None:
    """A normal request passes through admission control."""
    resp = await client.post(
        "/v1/chat/completions",
        json={"model": "m", "messages": [{"role": "user", "content": "Hi"}]},
    )
    assert resp.status_code == 200


@pytest.mark.asyncio
async def test_thermal_gate_rejects_at_threshold() -> None:
    """Requests are rejected with 503 when thermal level is >= threshold."""
    from server.thermal import ThermalState

    # Create app with 'heavy' threshold so we can test rejection
    heavy_app = create_app(
        dry_run=True, max_queue_depth=2, thermal_reject_level="heavy"
    )
    transport = httpx.ASGITransport(app=heavy_app)
    async with httpx.AsyncClient(
        transport=transport, base_url="http://testserver"
    ) as client:
        with patch.object(
            heavy_app.state.thermal, "read", return_value=ThermalState("heavy", 2)
        ):
            resp = await client.post(
                "/v1/chat/completions",
                json={
                    "model": "m",
                    "messages": [{"role": "user", "content": "Hi"}],
                },
            )
            assert resp.status_code == 503
            data = resp.json()
            assert "thermally throttled" in data["error"]["message"]
            assert resp.headers.get("retry-after") == "30"


@pytest.mark.asyncio
async def test_thermal_gate_allows_below_threshold() -> None:
    """Requests pass when thermal level is below threshold."""
    from server.thermal import ThermalState

    heavy_app = create_app(
        dry_run=True, max_queue_depth=2, thermal_reject_level="heavy"
    )
    transport = httpx.ASGITransport(app=heavy_app)
    async with httpx.AsyncClient(
        transport=transport, base_url="http://testserver"
    ) as client:
        with patch.object(
            heavy_app.state.thermal, "read", return_value=ThermalState("moderate", 1)
        ):
            resp = await client.post(
                "/v1/chat/completions",
                json={
                    "model": "m",
                    "messages": [{"role": "user", "content": "Hi"}],
                },
            )
            assert resp.status_code == 200


@pytest.mark.asyncio
async def test_priority_header_is_accepted(client: httpx.AsyncClient) -> None:
    """X-Interfere-Priority header is accepted without error."""
    resp = await client.post(
        "/v1/chat/completions",
        json={"model": "m", "messages": [{"role": "user", "content": "Hi"}]},
        headers={"X-Interfere-Priority": "0"},
    )
    assert resp.status_code == 200


@pytest.mark.asyncio
async def test_queue_depth_gauge_returns_to_zero(client: httpx.AsyncClient) -> None:
    """Queue depth returns to 0 after request completes."""
    await client.post(
        "/v1/chat/completions",
        json={"model": "m", "messages": [{"role": "user", "content": "Hi"}]},
    )
    resp = await client.get("/metrics/prometheus")
    body = resp.text
    assert "interfer_queue_depth 0.0" in body


@pytest.mark.asyncio
async def test_queue_wait_histogram_recorded(client: httpx.AsyncClient) -> None:
    """Queue wait time histogram is recorded after a request."""
    await client.post(
        "/v1/chat/completions",
        json={"model": "m", "messages": [{"role": "user", "content": "Hi"}]},
    )
    resp = await client.get("/metrics/prometheus")
    body = resp.text
    assert "interfer_queue_wait_seconds_count" in body


@pytest.mark.asyncio
async def test_rejected_counter_appears_in_prometheus() -> None:
    """Rejected counter appears in Prometheus output after thermal rejection."""
    from server.thermal import ThermalState

    heavy_app = create_app(
        dry_run=True, max_queue_depth=2, thermal_reject_level="heavy"
    )
    transport = httpx.ASGITransport(app=heavy_app)
    async with httpx.AsyncClient(
        transport=transport, base_url="http://testserver"
    ) as client:
        with patch.object(
            heavy_app.state.thermal, "read", return_value=ThermalState("heavy", 2)
        ):
            await client.post(
                "/v1/chat/completions",
                json={
                    "model": "m",
                    "messages": [{"role": "user", "content": "Hi"}],
                },
            )

        resp = await client.get("/metrics/prometheus")
        body = resp.text
        assert 'interfer_rejected_total{reason="thermal"}' in body


@pytest.mark.asyncio
async def test_cli_args_queue_depth() -> None:
    """--max-queue-depth CLI arg is parsed correctly."""
    from server.__main__ import _parse_args

    args = _parse_args(["--max-queue-depth", "16"])
    assert args.max_queue_depth == 16


@pytest.mark.asyncio
async def test_cli_args_thermal_reject() -> None:
    """--thermal-reject CLI arg is parsed correctly."""
    from server.__main__ import _parse_args

    args = _parse_args(["--thermal-reject", "trapping"])
    assert args.thermal_reject == "trapping"
