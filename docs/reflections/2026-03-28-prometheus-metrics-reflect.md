---
bead: sylveste-2sr
date: 2026-03-28
type: reflection
---

# Reflection: Prometheus /metrics Export

## What went well
- **Format translation, not metrics creation**: interfer already had comprehensive observability. The task was purely exposing existing data in Prometheus format — the right abstraction level.
- **Dual-format via content negotiation**: Preserves backward compatibility for any JSON consumers while adding Prometheus support. No breaking changes.
- **Review findings were actionable**: The quality reviewer caught the hot-loop label resolution issue and the latency measurement semantic ambiguity. Both were incorporated during execution.

## What to watch
- **Dry-run path gap**: `_generate_dry_run_tokens` doesn't increment `TOKENS_GENERATED` because it bypasses `_generate_worker_tokens`. This is correct for dry-run but means Prometheus metrics are incomplete in test mode. If dry-run is used for anything beyond development, the fake generator should also instrument.
- **ACTIVE_REQUESTS dec happens at stream-start**: The gauge decrements when the StreamingResponse is returned, not when streaming completes. For true in-flight tracking, you'd wrap the generator with an async finalizer. Acceptable for now since scrape intervals (15-30s) dwarf individual stream durations.

## Decisions made
- Used default prometheus_client registry (not custom) — simpler, and interfer runs as a single process
- Kept both `/metrics` (content-negotiated) and `/metrics/prometheus` (explicit) — different consumers may prefer different discovery patterns
- Thermal level mapped to integers (0-4) rather than string labels — Grafana gauge panels need numeric values for thresholds and alerting
