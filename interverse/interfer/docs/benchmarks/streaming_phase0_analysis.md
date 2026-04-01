---
bead: sylveste-14g
date: 2026-03-28
type: experiment-result
phase: 0
verdict: FAIL (>30% gap, per kill criteria)
---

# Phase 0 Results: SSD Streaming via Python pread

## Summary

| Metric | Streaming (this) | flash-moe | Gap |
|--------|-----------------|-----------|-----|
| Decode tok/s | **1.5** | **11.1** | 7.4x slower (86%) |
| TTFT (avg) | 6.4s | ~2s | ~3x slower |
| Peak memory | 37 GB | ~35 GB | comparable |
| pread throughput | 9.3 GB/s | N/A (Metal) | — |

**Verdict**: >30% gap triggers kill criteria. Pure Python pread cannot match flash-moe's
fused Metal pipeline. However, the bottleneck is NOT I/O bandwidth — it's the 60
per-layer CPU-GPU synchronization points.

## Per-Token Breakdown (decode phase)

| Component | Time/layer | Time/token (60L) | % of total |
|-----------|-----------|-------------------|------------|
| pread I/O | 7.5ms | 450ms | 68% |
| mx.eval(inds) sync | ~2ms | ~120ms | 18% |
| gather_qmm compute | ~1ms | ~60ms | 9% |
| Python overhead | ~0.5ms | ~30ms | 5% |
| **Total** | **~11ms** | **~660ms** | **100%** |

## What Worked

1. **Lazy model loading**: 397B model loaded in 1.6s using only 5.1 GB GPU for non-expert
   weights. Expert weights (202.5 GB) stay on disk.
2. **Zero-copy pread**: `ctypes.CDLL(None).pread()` directly into mx.array Metal buffers
   achieves 14.5 GB/s (54% faster than os.pread + memmove).
3. **Dynamic expert loading**: StreamingMoeBlock correctly handles variable numbers of
   unique experts across prefill (87+) and decode (10).
4. **Correctness**: Model generates coherent text — the streaming approach produces
   correct outputs.

## Why It's Slow

flash-moe runs the entire forward pass in Metal (Objective-C), with expert loading fused
into the GPU command stream. Our approach requires:

1. **60 CPU-GPU round-trips per token**: `mx.eval(inds)` at each MoE layer forces a Metal
   command buffer flush to get router indices on CPU before pread.
2. **Sequential layer execution**: Each layer must complete (including pread) before the
   next layer starts. No pipelining between layers.
3. **Python loop overhead**: 60 iterations of the layer loop in Python, with dict lookups,
   thread pool dispatch, and buffer management per iteration.

## Optimization Paths (not pursued)

These could close the gap but add significant complexity:

1. **Pipelined I/O**: Prefetch layer N+1's experts while computing layer N. Requires
   async eval or background prefetch thread. Theoretical: could halve pread latency.
2. **Expert prediction**: Use layer N's routing to predict layer N+1's likely experts
   (MoE routing is partially correlated across layers). Load speculatively.
3. **Page cache warming**: After first pass, OS page cache retains recently-read experts.
   Second conversation turn could be 2-3x faster.
4. **Batched sync**: Evaluate multiple layers before syncing, using placeholder indices.
   Incompatible with current mlx-lm layer loop.

## Decision

Per the plan's kill criteria: "If Phase 0 shows >30% gap vs flash-moe: stop, reassess
Option A." The 86% gap far exceeds this threshold.

**However**, the experiment proves several foundational pieces:
- Lazy loading works: 5.1 GB GPU footprint for a 397B model
- Zero-copy pread into mx.array Metal buffers: confirmed at 14.5 GB/s
- StreamingMoeBlock wrapper: correct drop-in replacement for SparseMoeBlock
- Expert repacking: 60 layers, 203 GB, verified

**Recommended next step**: Option C — hybrid approach. Use flash-moe as the inference
backend (it already achieves 11.1 tok/s), and use interfer as the HTTP server that
proxies to flash-moe's `--serve` mode. This preserves interfer's API compatibility,
cascade routing, and experiment hooks while leveraging flash-moe's Metal performance.

## Raw Data

See `streaming_phase0.json` in this directory.

### Environment
- Apple M5 Max, 128 GB unified memory
- Qwen 3.5 397B-A17B 4-bit (512 experts, 10 active, 60 layers)
- macOS 15.4, MLX 0.26.x, Python 3.14
- NVMe: measured 47.5 GB/s parallel pread (raw), 14.5 GB/s libc pread (per-thread)
