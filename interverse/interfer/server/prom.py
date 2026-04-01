"""Prometheus metric instruments for interfer.

All instruments are module-level singletons registered in the default
CollectorRegistry.  Import and use them from request handlers; call
``generate_metrics_text()`` to produce the Prometheus exposition format.
"""

from __future__ import annotations

from prometheus_client import Counter, Gauge, Histogram, generate_latest

# -- Request latency (time-to-first-byte, not end-to-end streaming) ----------
REQUEST_LATENCY = Histogram(
    "interfer_request_latency_seconds",
    "Time from request receipt to SSE stream start",
    labelnames=["model"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0),
)

# -- Token throughput ---------------------------------------------------------
TOKENS_GENERATED = Counter(
    "interfer_tokens_generated_total",
    "Cumulative tokens generated across all requests",
    labelnames=["model"],
)

# -- In-flight requests -------------------------------------------------------
ACTIVE_REQUESTS = Gauge(
    "interfer_active_requests",
    "Number of currently in-flight chat completion requests",
)

# -- macOS thermal pressure (0=nominal … 4=sleeping) -------------------------
THERMAL_LEVEL = Gauge(
    "interfer_thermal_level",
    "macOS thermal pressure as integer (0=nominal, 1=moderate, 2=heavy, 3=trapping, 4=sleeping)",
)

# -- GPU memory ---------------------------------------------------------------
GPU_MEMORY_BYTES = Gauge(
    "interfer_gpu_memory_bytes",
    "Metal GPU memory usage in bytes",
    labelnames=["type"],  # active, peak
)

# -- Error counter ------------------------------------------------------------
ERRORS_TOTAL = Counter(
    "interfer_errors_total",
    "Total error count by type",
    labelnames=["error_type"],
)

# -- Cascade decision routing -------------------------------------------------
CASCADE_DECISIONS = Counter(
    "interfer_cascade_decisions_total",
    "Cascade routing decisions by outcome",
    labelnames=["outcome"],  # accept, escalate, cloud
)

# -- Quality composite --------------------------------------------------------
QUALITY_COMPOSITE = Gauge(
    "interfer_quality_composite",
    "Latest composite quality score from the quality scorer",
)

QUALITY_HISTOGRAM = Histogram(
    "interfer_quality_score",
    "Distribution of composite quality scores per model",
    labelnames=["model"],
    buckets=(0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 0.95, 1.0),
)

QUALITY_PERPLEXITY = Histogram(
    "interfer_quality_perplexity",
    "Distribution of perplexity per model (lower is better)",
    labelnames=["model"],
    buckets=(1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 500.0),
)

# -- Total request counter (coarse status buckets) ----------------------------
REQUEST_COUNT = Counter(
    "interfer_requests_total",
    "Total HTTP requests by status class",
    labelnames=["status"],  # 2xx, 4xx, 5xx
)

# -- Thermal level name → numeric mapping ------------------------------------
THERMAL_LEVEL_MAP: dict[str, int] = {
    "nominal": 0,
    "moderate": 1,
    "heavy": 2,
    "trapping": 3,
    "sleeping": 4,
}


# -- Queue depth ---------------------------------------------------------------
QUEUE_DEPTH = Gauge(
    "interfer_queue_depth",
    "Number of requests currently waiting in the inference queue",
)

# -- Queue wait time -----------------------------------------------------------
QUEUE_WAIT_SECONDS = Histogram(
    "interfer_queue_wait_seconds",
    "Time spent waiting in the inference queue before processing starts",
    buckets=(0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0, 30.0, 60.0),
)

# -- Rejected requests ---------------------------------------------------------
REJECTED_TOTAL = Counter(
    "interfer_rejected_total",
    "Requests rejected by admission control",
    labelnames=["reason"],  # thermal, queue_full
)


def generate_metrics_text() -> bytes:
    """Return Prometheus exposition format as bytes."""
    return generate_latest()
