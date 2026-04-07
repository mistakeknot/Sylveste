"""Shared test fixtures for interfer tests."""

from __future__ import annotations

import httpx
import pytest

from server.main import create_app
from server.prom import (
    ACTIVE_REQUESTS,
    CASCADE_DECISIONS,
    ERRORS_TOTAL,
    QUALITY_HISTOGRAM,
    QUALITY_PERPLEXITY,
    QUEUE_DEPTH,
    QUEUE_WAIT_SECONDS,
    REJECTED_TOTAL,
    REQUEST_COUNT,
    REQUEST_LATENCY,
    TOKENS_GENERATED,
)


@pytest.fixture(autouse=True)
def _reset_prom_metrics():
    """Reset all Prometheus collectors between tests.

    prometheus_client instruments are module-level singletons -- without
    resetting, counters and histograms accumulate across tests.
    """
    yield
    for collector in [
        QUEUE_DEPTH,
        REJECTED_TOTAL,
        REQUEST_LATENCY,
        TOKENS_GENERATED,
        ACTIVE_REQUESTS,
        ERRORS_TOTAL,
        CASCADE_DECISIONS,
        REQUEST_COUNT,
        QUALITY_HISTOGRAM,
        QUALITY_PERPLEXITY,
    ]:
        if hasattr(collector, "_metrics"):
            collector._metrics.clear()
        if hasattr(collector, "_value"):
            collector._value.set(0)
    if hasattr(QUEUE_WAIT_SECONDS, "_metrics"):
        QUEUE_WAIT_SECONDS._metrics.clear()


@pytest.fixture
def app():
    """Create a test app in dry-run mode with sleeping thermal threshold."""
    return create_app(dry_run=True, thermal_reject_level="sleeping")


@pytest.fixture
def client(app):
    """Create an httpx AsyncClient wired to the test app via ASGITransport."""
    transport = httpx.ASGITransport(app=app)
    return httpx.AsyncClient(transport=transport, base_url="http://testserver")
