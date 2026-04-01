# Plan: Flash-MoE Cache Sweep Benchmark

**Bead:** sylveste-rb6
**Date:** 2026-03-29
**Complexity:** C3

## Tasks

### Task 1: Enhance benchmark script
**Files:** `interverse/interfer/benchmarks/flashmoe_cache_sweep.sh`
- Add `--cache-telemetry` flag to flash-moe invocation for cold vs eviction miss breakdown
- Add memory pressure check (vm_stat) between config runs — skip next config if swap > 1GB
- Ensure results dir is under `interverse/interfer/benchmarks/` not relative `benchmarks/`

### Task 2: Run benchmark sweep
**Duration:** ~40 minutes
**Configs:** `--malloc-cache` = 0, 2581, 5000, 10000, 15000
- Each config: start flash-moe → wait ready → 3 warmup → 5 bench prompts → extract metrics → kill
- Monitor via `tail -f /tmp/flashmoe_bench.log` in another terminal if needed

### Task 3: Analyze results
**Files:** `interverse/interfer/benchmarks/results_*.tsv`
- Parse TSV, identify Pareto-optimal configs (cache_gb vs mean_tps)
- Calculate marginal tok/s per GB for each step up in cache
- Document findings in analysis section below

### Task 4: Update interfer server with recommended default
**Files:** `interverse/interfer/server/` (config or docs)
- Set recommended `--malloc-cache` based on Pareto analysis
- Document in AGENTS.md or server config

## Dependencies
- Task 1 → Task 2 (script must be enhanced before running)
- Task 2 → Task 3 (need results to analyze)
- Task 3 → Task 4 (need analysis to recommend)

## Risk Mitigation
- 15000 entries (~82GB) may OOM → memory pressure check will abort gracefully
- SSD thermal throttle → warmup phase mitigates; if variance high, note in results
