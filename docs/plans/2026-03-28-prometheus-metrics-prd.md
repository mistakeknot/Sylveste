---
bead: sylveste-2sr
date: 2026-03-28
type: prd
status: active
---

# PRD: Prometheus /metrics Export for Grafana Monitoring

## Problem Statement
interfere exposes rich operational metrics (latency, thermal, GPU memory, cascade routing, quality scores) as JSON. Prometheus/Grafana—the standard monitoring stack—cannot scrape JSON. Overnight playtest sessions need automated dashboards without custom JSON→Prometheus adapters.

## Goal
Add native Prometheus exposition format to interfere's `/metrics` endpoint, enabling direct Grafana scraping.

## Features

### F1: Prometheus Metric Instruments
Register prometheus_client instruments that get updated in the request lifecycle:
- `interfere_request_latency_seconds` (Histogram) — per-request, labeled by model
- `interfere_tokens_generated_total` (Counter) — cumulative tokens produced
- `interfere_active_requests` (Gauge) — currently in-flight requests
- `interfere_thermal_level` (Gauge) — macOS thermal pressure (0=nominal, 1=moderate, 2=heavy, 3=trapping, 4=sleeping)
- `interfere_gpu_memory_bytes` (Gauge) — active and peak Metal memory
- `interfere_errors_total` (Counter) — error count by type
- `interfere_cascade_decisions_total` (Counter) — cascade outcomes (accept/escalate/cloud)
- `interfere_quality_composite` (Gauge) — latest quality composite score

### F2: Dual-Format /metrics Endpoint
- `GET /metrics` with `Accept: text/plain` → Prometheus text format
- `GET /metrics` with `Accept: application/json` → existing JSON (backward compatible)
- `GET /metrics/prometheus` → always Prometheus text format (explicit path)

### F3: Instrument Update Points
Hook prometheus instruments into existing code paths:
- Latency: record in request middleware (same place as `latency_samples`)
- Tokens: increment in streaming response loop
- Active requests: inc/dec in request middleware
- Thermal: update on each `/metrics` scrape (lazy — thermal reads are cheap)
- GPU memory: update on each `/metrics` scrape from worker health
- Errors: increment in error handler
- Cascade: increment in cascade decision callback

## Non-Goals
- Grafana dashboard JSON provisioning
- Alerting rules or runbooks
- Push gateway support
- Custom collector for historical data (prometheus_client handles this)

## Success Criteria
1. `curl localhost:8421/metrics/prometheus` returns valid Prometheus text format
2. Existing JSON consumers get identical output when requesting `Accept: application/json`
3. `promtool check metrics` passes on the output
4. No measurable latency impact (< 100μs per scrape)
