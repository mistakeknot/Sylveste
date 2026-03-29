# Strategy: Flash-MoE Cache Sweep

**Bead:** sylveste-rb6
**Date:** 2026-03-29

## Problem

We need empirical data on the expert cache size vs throughput tradeoff for Qwen3.5-397B on M5 Max 128GB. Without this data, we're guessing the `--malloc-cache` default. Too small = SSD-bound latency, too large = OOM risk.

## Goal

A TSV dataset and Pareto analysis that definitively answers: "What `--malloc-cache` value should interfere use as default for 128GB systems?"

## Approach: Enhanced Benchmark Run

1. **Enhance script** — Add `--cache-telemetry` for cold/eviction breakdown. Add memory pressure check between configs.
2. **Run sweep** — 5 configs: 0, 2581, 5000, 10000, 15000. ~8 min per config. ~40 min total.
3. **Analyze** — Compute Pareto frontier from results TSV. Plot cache GB vs tok/s.
4. **Recommend** — Set default `--malloc-cache` in interfere server config based on results.

## Non-Goals

- Expert prediction (`predict` column) — future work
- Multi-model benchmarks — only Qwen3.5-397B for now
- Automated regression — manual benchmark for now

## Success Criteria

- [ ] All 5 configs run successfully (or documented why one failed)
- [ ] Results TSV with cache_entries, cache_gb, startup_s, mean_tps, median_tps, min/max, hit rate
- [ ] Pareto frontier identified
- [ ] Recommended default documented
