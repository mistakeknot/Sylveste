# Flash-MoE Throughput Regression After Upstream Merge

**Bead:** sylveste-1xj
**Date:** 2026-03-29
**Status:** brainstorm

## Symptom

Throughput dropped from 12.2 tok/s (serve, warmed) / 5.0 tok/s (batch, cold) to 1.3 tok/s (serve) / 2.3 tok/s (batch) after pulling upstream commit 20f8591.

## Per-Layer Timing Comparison

| Metric (ms/layer) | Old (Q3 5.4MB) | New (4-bit 7.1MB) | Ratio |
|--------------------|-----------------|---------------------|-------|
| expert_io | 0.695 | 3.566 | 5.1x |
| cmd1_wait | 1.418 | 2.333 | 1.6x |
| cmd2_wait | 0.916 | 1.050 | 1.1x |
| total_layer | 3.233 | 7.208 | 2.2x |

## Root Cause Hypotheses

### H1: Expert size increase (31% more I/O)
The Q3 hybrid format used 5,439,488 bytes/expert. Upstream removed Q3 and uses full 4-bit at 7,077,888 bytes/expert. But 31% more I/O shouldn't cause 5.1x slower expert_io.

### H2: Lost I/O pipelining
The upstream removed tiered I/O (cold F_NOCACHE fds). `layer_fds_cold` is set to -1. If the old code overlapped cold reads with GPU work, removing this breaks the pipeline. The comment says "trust OS page cache" but the expert access pattern is mostly random (4 out of 512 experts per layer), so page cache may not help.

### H3: cmd1_wait regression (1.6x)
cmd1 is GPU attention — shouldn't change with expert format. But if the upstream changed the Metal shader pipeline or buffer layouts (103 new lines in shaders.metal), this could affect GPU utilization. Or the larger 70.8GB malloc_cache is causing unified memory bandwidth contention.

### H4: Q3 hybrid was reading less data by design
The Q3 hybrid format (5.4MB) was intentionally compressed — it read the gate+up+down projection matrices at lower precision, using less data per expert for a small quality tradeoff. The 4-bit format is the "full quality" format. The old code was essentially getting a free 31% I/O reduction by using lower precision.

## Key Question

Is 2.3 tok/s the correct throughput for 4-bit 7.1MB experts on M5 Max, or is the upstream code leaving performance on the table?

## Approach

1. Profile with `--timing` on both branches (done — see table above)
2. Check if old Q3 experts produce similar quality to new 4-bit (perplexity comparison)
3. Check if upstream fused_layer_forward has inefficient I/O scheduling
4. Test with `--2bit` (3.9MB experts) to see if throughput scales linearly with expert size
5. If H4 is confirmed: the "regression" is expected — we were trading quality for speed with Q3
