---
bead: sylveste-2sr
date: 2026-03-28
status: complete
---

# Brainstorm: Prometheus /metrics Export for Grafana Monitoring

## Problem
interfere's `/metrics` endpoint returns JSON — useful for debugging but not scrapable by Prometheus/Grafana. Overnight playtest sessions need dashboards for thermal pressure, GPU memory, latency percentiles, and cascade routing efficiency.

## Current State
- **Framework:** Starlette + Uvicorn (ASGI)
- **Existing metrics:** latency (p50/p95/p99), thermal level, GPU memory (active/peak), request counts, errors, cascade routing stats (accept/escalation/cloud rates), quality scores, token throughput
- **Format:** JSON at `GET /metrics`
- **Shadow cost logging:** SQLite via `shadow_log.py` → interstat integration

## Approach: Dual-Format /metrics

Add `prometheus_client` dependency. Serve Prometheus text format when `Accept: text/plain` or new path `/metrics/prometheus`. Keep existing JSON at `/metrics` (or when `Accept: application/json`).

### Metrics to expose (Prometheus format)

| Metric | Type | Labels | Source |
|--------|------|--------|--------|
| `interfere_request_latency_seconds` | Histogram | `model`, `status` | `latency_samples` |
| `interfere_tokens_generated_total` | Counter | `model` | streaming response |
| `interfere_active_requests` | Gauge | — | middleware count |
| `interfere_thermal_level` | Gauge | `level` | `thermal.py` |
| `interfere_gpu_memory_bytes` | Gauge | `type` (active/peak) | `metal_worker.py` |
| `interfere_errors_total` | Counter | `type` | error handler |
| `interfere_cascade_decisions_total` | Counter | `outcome` (accept/escalate/cloud) | `cascade.py` |
| `interfere_quality_score` | Gauge | `metric` (perplexity/coherence/composite) | `quality.py` |
| `interfere_request_count_total` | Counter | `model`, `status_code` | request middleware |

### Key Decisions
1. **Content negotiation vs separate path:** Both — Accept header on `/metrics` + explicit `/metrics/prometheus` path
2. **Registry:** Use default `prometheus_client` registry, not custom — simpler
3. **Labels:** Keep minimal — `model` name where relevant, `status` for latency
4. **Histogram buckets:** Latency — `.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5, 10` (standard + longer for large models)

### Risks
- `prometheus_client` adds ~1MB dependency — acceptable
- Must not break existing JSON consumers
- Histogram observation must be in hot path without adding latency — prometheus_client's observe() is ~1μs, negligible

### Out of Scope
- Grafana dashboard JSON (separate task)
- Alerting rules
- Push gateway (Grafana scrapes directly)
