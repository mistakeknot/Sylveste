# Strategy: Flash-MoE Cache Sweep

**Bead:** sylveste-rb6
**Date:** 2026-03-29

## Problem

We need empirical data on the expert cache size vs throughput tradeoff for Qwen3.5-397B on M5 Max 128GB. Without this data, we're guessing the `--malloc-cache` default. Too small = SSD-bound latency, too large = OOM risk.

## Goal

A TSV dataset and Pareto analysis that definitively answers: "What `--malloc-cache` value should interfer use as default for 128GB systems?"

## Approach: Enhanced Benchmark Run

1. **Enhance script** — Add `--cache-telemetry` for cold/eviction breakdown. Add memory pressure check between configs.
2. **Run sweep** — 5 configs: 0, 2581, 5000, 10000, 15000. ~8 min per config. ~40 min total.
3. **Analyze** — Compute Pareto frontier from results TSV. Plot cache GB vs tok/s.
4. **Recommend** — Set default `--malloc-cache` in interfer server config based on results.

## Non-Goals

- Expert prediction (`predict` column) — future work
- Multi-model benchmarks — only Qwen3.5-397B for now
- Automated regression — manual benchmark for now

## Success Criteria

- [x] All 12 configs run successfully (2 quant × 3 cache × 2 io-split)
- [x] Results TSV at `flash-moe/autoresearch/results/cache_sweep.tsv`
- [x] Pareto frontier identified (degenerate — single winner)
- [x] Recommended default documented (see Results below)

## Results (2026-04-01)

Sweep: Q3 vs 4-bit × malloc-cache [0, 2500, 5000] × cache-io-split [0, 4].

| Config | mean tok/s | hit rate | Expert I/O% | Total time |
|--------|-----------|----------|-------------|-----------|
| **q3_mc0_cis4** | **1.98** | 0% | 34.0% | 48.8s |
| 4bit_mc0_cis4 | 1.84 | 0% | 36.2% | 50.9s |
| q3_mc0_cis0 | 1.39 | 0% | 36.6% | 62.5s |
| 4bit_mc0_cis0 | 1.34 | 0% | 40.9% | 65.1s |
| q3_mc2500_cis4 | 1.32 | 54.6% | 21.7% | 74.4s |
| q3_mc2500_cis0 | 1.26 | 54.6% | 22.4% | 82.6s |
| 4bit_mc2500_cis4 | 1.25 | 54.8% | 25.5% | 78.6s |
| 4bit_mc2500_cis0 | 1.24 | 54.8% | 25.0% | 80.7s |
| q3_mc5000_cis4 | 1.01 | 62.4% | 21.4% | 103.1s |
| q3_mc5000_cis0 | 0.92 | 62.4% | 19.7% | 108.1s |
| 4bit_mc5000_cis0 | 0.83 | 62.5% | 21.7% | 125.5s |
| 4bit_mc5000_cis4 | 0.77 | 62.5% | 20.7% | 130.3s |

### Key Findings

1. **malloc-cache is a net negative on Apple Silicon M5 Max.** Every cache size was slower than uncached. The memcpy from userspace cache buffers is more expensive than SSD pread through the unified memory DMA path.

2. **cache-io-split=4 is the single most impactful optimization** (+37% for 4-bit, +42% for Q3), but only without malloc-cache.

3. **Q3 beats 4-bit in every matched config** (+4% to +8%). Smaller GGUF experts = faster SSD I/O.

4. **Peak burst: 4.86 tok/s** (when OS page cache is warm). Mean 1.98 tok/s includes cold-start reads.

5. **Expert frequency analysis:** 80% hit rate requires ~3,347 pinned experts (16.96 GB). Early layers route broadly (128-161 unique), late layers concentrate (65-85 unique).

### Recommended Default for 128 GB M5 Max

```
--q3-experts --malloc-cache 0 --cache-io-split 4
```

The OS page cache is the expert cache on Apple Silicon — malloc-cache is redundant and harmful. The `--cache-io-split 4` flag should become the default for all quant modes.

### Gap to Upstream (12.9 tok/s)

Our best (1.98) vs upstream claim (12.9) = 6.5× gap. Root causes:
- Upstream likely benchmarks with all experts resident in RAM (no SSD streaming)
- Our SSD path (Expert I/O 38%) is the bottleneck; upstream may use pre-loaded experts
- Future: expert prediction (`--predict`) to prefetch during CMD1 wait could hide I/O latency
