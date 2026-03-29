# Flash-MoE Expert Cache Sweep Benchmark

**Bead:** sylveste-rb6
**Date:** 2026-03-29
**Status:** brainstorm

## Context

Qwen3.5-397B runs on M5 Max 128GB via flash-moe. The model has 61 MoE expert layers streamed from SSD. The `--malloc-cache` flag pre-allocates resident memory for expert weights, trading RAM for reduced SSD reads. We need to find the Pareto frontier: cache GB vs tok/s vs cache hit rate.

**Blocker resolved:** `sylveste-kyz` fixed pread -1 in GPU Metal path (io_pool_dispatch). GPU inference now works correctly.

## What We Already Have

- `benchmarks/flashmoe_cache_sweep.sh` — complete script, 5 cache configs, warmup + bench
- flash-moe binary with `--malloc-cache`, `--cache-entries`, `--q3-experts`, `--serve`, `--cache-telemetry`
- Model at `~/Models/flash_mlx_4bit/` (61 packed expert layers)
- 128GB RAM, 765GB free SSD

## Sweep Parameters

| Config | `--malloc-cache` | Estimated GB | Purpose |
|--------|-----------------|-------------|---------|
| 0 | 0 (disabled) | 0 | Baseline: SSD-only streaming |
| 2581 | 2581 | ~14 GB | ~80% hit rate (from flash-moe docs) |
| 5000 | 5000 | ~27 GB | ~90%+ hit rate estimate |
| 10000 | 10000 | ~54 GB | High residency, leaves ~70GB for model + OS |
| 15000 | 15000 | ~82 GB | Near-full caching, tight on remaining RAM |

Each expert entry ≈ 5.4 MB (5,439,488 bytes per the script's calculation).

## Key Questions

1. **Diminishing returns?** At what cache size does tok/s plateau relative to RAM consumed?
2. **Startup cost?** Large malloc-cache may increase startup time significantly
3. **15000 viable?** 82GB for cache + model weights + Metal buffers + OS — will it OOM?
4. **Cache telemetry?** Script doesn't pass `--cache-telemetry` — should we add it for cold vs eviction miss breakdown
5. **Predict mode?** TSV has a `predict` column set to "off" — future work for expert prediction

## Risks

- **OOM at 15000:** 82GB cache + ~20GB model + Metal buffers could exceed 128GB. Mitigation: run configs in ascending order, abort if swap pressure detected.
- **Startup timeout:** 300s may not be enough for large cache pre-fill. Script already handles this with continue-on-skip.
- **Measurement noise:** SSD bandwidth varies with thermal throttling on sustained reads. Mitigation: warmup phase + 5 bench prompts.

## Approach

1. Review/enhance the benchmark script (add `--cache-telemetry`, check for swap pressure)
2. Run the sweep
3. Record results, compute Pareto frontier
4. Document findings and recommended default cache size

## Decision: Script Enhancement

The existing script is solid. Two small enhancements:
- Add `--cache-telemetry` flag to get cold vs eviction miss breakdown
- Add memory pressure monitoring (vm_stat-based) to detect OOM risk before it hits
