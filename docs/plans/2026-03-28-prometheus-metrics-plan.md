---
bead: sylveste-2sr
date: 2026-03-28
type: plan
status: active
---

# Plan: Prometheus /metrics Export

## Overview
Add `prometheus_client` to interfer, register instruments that update in the existing request lifecycle, and serve Prometheus text format alongside existing JSON.

## Tasks

### Task 1: Add `prometheus_client` dependency
**File:** `interverse/interfer/pyproject.toml`
- Add `prometheus_client>=0.21.0` to `dependencies`

### Task 2: Create `server/prom.py` — Prometheus instrument registry
**File:** `interverse/interfer/server/prom.py` (new)
- Define all Prometheus instruments in one module:
  - `REQUEST_LATENCY` — Histogram, buckets `.005,.01,.025,.05,.1,.25,.5,1,2.5,5,10`, labels: `model`
  - `TOKENS_GENERATED` — Counter, labels: `model`
  - `ACTIVE_REQUESTS` — Gauge (no labels)
  - `THERMAL_LEVEL` — Gauge (no labels) — numeric mapping: nominal=0, moderate=1, heavy=2, trapping=3, sleeping=4
  - `GPU_MEMORY_BYTES` — Gauge, labels: `type` (active, peak)
  - `ERRORS_TOTAL` — Counter, labels: `error_type`
  - `CASCADE_DECISIONS` — Counter, labels: `outcome` (accept, escalate, cloud)
  - `QUALITY_COMPOSITE` — Gauge (no labels)
  - `REQUEST_COUNT` — Counter, labels: `status_code`
- Export a `generate_metrics_text()` function that calls `prometheus_client.generate_latest()` and returns bytes

### Task 3: Hook instruments into request lifecycle
**File:** `interverse/interfer/server/main.py`
- Import instruments from `server.prom`
- In `_chat_completions`:
  - `ACTIVE_REQUESTS.inc()` at start, `.dec()` in a `finally` block
  - `REQUEST_LATENCY.labels(model=model).observe(elapsed)` where `latency_samples.append()` already is
  - `REQUEST_COUNT.labels(status_code="200").inc()` on success, `"4xx"`/`"5xx"` on errors
  - `ERRORS_TOTAL.labels(error_type="invalid_json").inc()` / `"missing_messages"` on 400s
- In `_generate_worker_tokens`:
  - `TOKENS_GENERATED.labels(model=model).inc()` per token (inside the while loop)
- In cascade decision points:
  - `CASCADE_DECISIONS.labels(outcome="accept").inc()` etc.

### Task 4: Dual-format `/metrics` endpoint + `/metrics/prometheus` route
**File:** `interverse/interfer/server/main.py`
- Modify `_metrics` to check `Accept` header:
  - If `text/plain` or `text/plain; version=0.0.4` → return Prometheus text
  - Otherwise → return existing JSON (backward compatible default)
- Before returning Prometheus format, update lazy-read gauges:
  - `THERMAL_LEVEL.set(thermal_raw_value)` from thermal monitor
  - `GPU_MEMORY_BYTES.labels(type="active").set(bytes)` from worker health
  - `GPU_MEMORY_BYTES.labels(type="peak").set(bytes)` from worker health
  - `QUALITY_COMPOSITE.set(latest_quality)` if quality samples exist
- Add new route: `Route("/metrics/prometheus", _metrics_prometheus, methods=["GET"])` — always returns Prometheus text format
- Return `Response(content=generate_metrics_text(), media_type="text/plain; version=0.0.4; charset=utf-8")`

### Task 5: Tests
**File:** `interverse/interfer/tests/test_prometheus.py` (new)
- Test Prometheus text format at `/metrics/prometheus` endpoint
- Test content negotiation: `Accept: text/plain` returns Prometheus, `Accept: application/json` returns JSON
- Test that default `/metrics` (no Accept header) returns JSON (backward compat)
- Test instruments update: make a chat completion request, then check `/metrics/prometheus` for updated counters
- Test that `ACTIVE_REQUESTS` gauge is 0 after request completes
- Test thermal and GPU gauges appear in output

## Execution Order
Tasks 1 → 2 → 3 → 4 → 5 (sequential — each builds on the previous)

## Risk Mitigation
- **Backward compatibility:** JSON remains the default when no Accept header is sent
- **No latency impact:** `observe()` and `inc()` are ~1μs operations
- **No global state leak:** Use default registry (prometheus_client cleans up on process exit)
