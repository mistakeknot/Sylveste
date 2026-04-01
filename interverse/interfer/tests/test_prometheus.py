"""Tests for Prometheus metrics exposition."""

from __future__ import annotations

import httpx
import pytest

from server.cascade import CascadeConfig
from server.main import create_app
from server.prom import (
    ACTIVE_REQUESTS,
    CASCADE_DECISIONS,
    ERRORS_TOTAL,
    QUALITY_HISTOGRAM,
    QUALITY_PERPLEXITY,
    REQUEST_COUNT,
    REQUEST_LATENCY,
    TOKENS_GENERATED,
)


@pytest.fixture(autouse=True)
def _reset_prom_metrics():
    """Reset all Prometheus collectors between tests.

    prometheus_client instruments are module-level singletons — without
    resetting, counters and histograms accumulate across tests.
    """
    from prometheus_client import REGISTRY

    # Collect metric names before the test so we can identify ours
    yield
    # Reset all our custom metrics by clearing their children/samples
    for collector in [
        REQUEST_LATENCY,
        TOKENS_GENERATED,
        ACTIVE_REQUESTS,
        ERRORS_TOTAL,
        CASCADE_DECISIONS,
        REQUEST_COUNT,
        QUALITY_HISTOGRAM,
        QUALITY_PERPLEXITY,
    ]:
        # _metrics is the internal dict for labeled metrics; _value for unlabeled
        if hasattr(collector, "_metrics"):
            collector._metrics.clear()
        if hasattr(collector, "_value"):
            collector._value.set(0)


@pytest.fixture
def app():
    return create_app(dry_run=True, thermal_reject_level="sleeping")


@pytest.fixture
def client(app):
    transport = httpx.ASGITransport(app=app)
    return httpx.AsyncClient(transport=transport, base_url="http://testserver")


@pytest.mark.asyncio
async def test_prometheus_endpoint_returns_text(client: httpx.AsyncClient) -> None:
    """/metrics/prometheus always returns Prometheus exposition format."""
    resp = await client.get("/metrics/prometheus")
    assert resp.status_code == 200
    assert "text/plain" in resp.headers["content-type"]
    # Prometheus format contains at least the HELP/TYPE preamble
    body = resp.text
    assert "# HELP interfer_" in body
    assert "# TYPE interfer_" in body


@pytest.mark.asyncio
async def test_content_negotiation_text_plain(client: httpx.AsyncClient) -> None:
    """Accept: text/plain on /metrics returns Prometheus format."""
    resp = await client.get("/metrics", headers={"Accept": "text/plain"})
    assert resp.status_code == 200
    assert "text/plain" in resp.headers["content-type"]
    assert "# HELP interfer_" in resp.text


@pytest.mark.asyncio
async def test_content_negotiation_json_default(client: httpx.AsyncClient) -> None:
    """Default /metrics (no Accept header) returns JSON."""
    resp = await client.get("/metrics")
    assert resp.status_code == 200
    assert "application/json" in resp.headers["content-type"]
    data = resp.json()
    assert "requests" in data
    assert "cascade" in data


@pytest.mark.asyncio
async def test_content_negotiation_explicit_json(client: httpx.AsyncClient) -> None:
    """Accept: application/json on /metrics returns JSON."""
    resp = await client.get("/metrics", headers={"Accept": "application/json"})
    assert resp.status_code == 200
    assert "application/json" in resp.headers["content-type"]
    data = resp.json()
    assert "requests" in data


@pytest.mark.asyncio
async def test_request_updates_prometheus_counters(
    client: httpx.AsyncClient,
) -> None:
    """A chat completion request updates latency histogram and request counter."""
    await client.post(
        "/v1/chat/completions",
        json={"model": "test-model", "messages": [{"role": "user", "content": "Hi"}]},
    )

    resp = await client.get("/metrics/prometheus")
    body = resp.text

    # Latency histogram should have at least one observation
    assert 'interfer_request_latency_seconds_count{model="test-model"}' in body
    # Request counter should show 2xx
    assert 'interfer_requests_total{status="2xx"}' in body
    # Note: tokens_generated won't increment in dry-run mode because
    # _generate_dry_run_tokens bypasses _generate_worker_tokens


@pytest.mark.asyncio
async def test_error_updates_prometheus_counters(
    client: httpx.AsyncClient,
) -> None:
    """A 400 error increments the error counter."""
    await client.post("/v1/chat/completions", json={"model": "test-model"})

    resp = await client.get("/metrics/prometheus")
    body = resp.text

    assert 'interfer_errors_total{error_type="missing_messages"}' in body
    assert 'interfer_requests_total{status="4xx"}' in body


@pytest.mark.asyncio
async def test_active_requests_zero_after_completion(
    client: httpx.AsyncClient,
) -> None:
    """ACTIVE_REQUESTS gauge returns to 0 after request completes."""
    await client.post(
        "/v1/chat/completions",
        json={"model": "m", "messages": [{"role": "user", "content": "Hi"}]},
    )

    resp = await client.get("/metrics/prometheus")
    body = resp.text
    # Active requests gauge should be 0.0 after the request
    assert "interfer_active_requests 0.0" in body


@pytest.mark.asyncio
async def test_thermal_gauge_in_prometheus(client: httpx.AsyncClient) -> None:
    """Thermal level gauge appears in Prometheus output."""
    resp = await client.get("/metrics/prometheus")
    body = resp.text
    # The HELP line should always be present even if value is default
    assert "interfer_thermal_level" in body


@pytest.mark.asyncio
async def test_gpu_memory_gauge_in_prometheus(client: httpx.AsyncClient) -> None:
    """GPU memory gauge appears in Prometheus output."""
    resp = await client.get("/metrics/prometheus")
    body = resp.text
    assert "interfer_gpu_memory_bytes" in body


@pytest.mark.asyncio
async def test_quality_histograms_in_prometheus(client: httpx.AsyncClient) -> None:
    """Quality histogram instruments appear in Prometheus output."""
    # Record a quality observation so the histogram has data
    from server.main import _record_quality

    _record_quality("test-model", {"composite": 0.85, "perplexity": 5.0}, [])

    resp = await client.get("/metrics/prometheus")
    body = resp.text
    assert "interfer_quality_score" in body
    assert "interfer_quality_perplexity" in body
