---
bead: sylveste-14g
date: 2026-03-28
type: synthesis
agents: 8 (5 custom domain + 3 flux-drive core)
---

# SSD Streaming Architecture: Multi-Agent Synthesis

## Executive Summary

8 review agents analyzed the brainstorm's recommendation of Option A (parameterize
flash-moe ObjC/Metal). **All agents that evaluated alternatives recommended against
Option A as the primary path.** The revised recommendation is:

**Option D (mlx-lm fork with StreamingSwitchGLU)**, validated by a sub-day
starter experiment, with flash-moe as a subprocess reference benchmark.

## Agent Consensus Map

| Agent | Recommended | Key Finding |
|-------|-------------|-------------|
| I/O Pipeline | — | Bottleneck is page cache miss rate, not language |
| MLX Integration | **Option D** | StreamingSwitchGLU override, all 4 archs share SwitchGLU |
| Language/FFI | **Python ctypes** | Zero-copy pread into mx.array memoryview = 47.5 GB/s |
| MoE Routing | — | Trust OS page cache, pin shared experts only (427MB) |
| Maintainability | **Option B** | os.pread() = same syscall, flash-moe is external dev's project |
| fd-systems | Against A | Page cache is shared resource, Option A creates hysteresis |
| fd-decisions | Against A | Anchoring bias on 11.1 tok/s, missing starter experiment |
| fd-performance | — | Cache hit cliff non-linear; KV cache competes with page cache; prefill I/O unaddressed |

## Critical Discoveries

### 1. Zero-Copy Python Path Exists (FFI Agent, measured)

`mx.array` supports writable `memoryview`. Python `ctypes.addressof()` on that
memoryview gives a raw pointer into MLX's Metal shared memory buffer. `pread()`
directly into this pointer = **NVMe → kernel page cache → MLX Metal buffer**
with zero application-level copies.

Measured on this M5 Max:
- Parallel 4-thread pread into mx.array: **0.60ms per layer** (4 experts)
- Throughput: **47.5 GB/s** on warm cache
- ctypes FFI overhead: **166 nanoseconds** per call (0.002% of I/O time)

This eliminates the theoretical performance advantage of native code for the I/O path.

### 2. flash-moe Metal Contexts Are Incompatible with MLX (FFI Agent)

flash-moe creates its own `MTLDevice` and `MTLBuffer` objects. These cannot be
shared with MLX's separate Metal allocator. You **cannot use flash-moe as an I/O
library for MLX** — it's all or nothing. This invalidates Option C (hybrid).

### 3. All Target Models Share SwitchGLU (MLX Agent)

DeepSeek V3, Kimi K2.5, GLM-5, and Qwen MoE all use mlx-lm's `SwitchGLU` /
`SwitchLinear` layer for MoE expert routing. A single `StreamingSwitchGLU`
override works for all four architectures. No per-model attention kernels needed
(MLX already has MLA implementations).

### 4. Option A's Performance Advantage Is Overstated (Decisions Agent)

The 11.1 tok/s figure is for Qwen GQA, not MLA. Option A requires writing
a **new, unproven MLA kernel in ObjC Metal** (Phase 2). Option D uses MLX's
**existing, battle-tested MLA implementation**. The net comparison is:

- Option A: Proven pread pipeline + unproven MLA kernel
- Option D: Proven pread pipeline (same syscall) + proven MLA implementation

### 5. Page Cache Hit Rate Is Not Stable (Systems Agent)

The 85% estimate assumes steady-state warming. Clavain's diverse task mix
(coding → writing → Q&A) causes expert routing shifts that flush the warm
cache. Cold-start penalty is exactly when Metal timeout risk is highest.
The real hit rate distribution under production workloads is unknown.

## Revised Approach: Option D with Starter Experiment

### Day 0: Starter Experiment (resolves core uncertainty)

Patch mlx-lm's `SwitchGLU.__call__` for Qwen 397B:
1. After `self.gate(x)`, call `mx.eval(inds)` to get expert indices on CPU
2. pread selected experts from pre-indexed layer files via ctypes → mx.array memoryview
3. Replace expert weights in model
4. Continue with standard MoE forward pass
5. Measure tok/s vs flash-moe's 11.1 baseline

**If within 20% of flash-moe**: Ship Option D. The maintenance, observability,
and model support advantages are overwhelming.

**If >30% gap**: Investigate where time is lost (router sync? memcpy? MLX
dispatch overhead?). Consider Option A only if the gap is irreducible.

### Days 1-5: StreamingSwitchGLU Implementation

1. Create `StreamingSwitchGLU` class overriding `SwitchGLU.__call__`
2. Pre-allocate mx.array buffer pool (K * 2 for double-buffering)
3. Expert file index generator (like flash-moe's expert_index.json)
4. Expert repacking script (one binary per layer, experts at fixed offsets)
5. Parallel pread via ThreadPoolExecutor(max_workers=4)
6. Wire into InferenceEngine with `--streaming-weights` flag
7. Pin shared experts as resident Metal buffers (427MB)

### Day 5-7: Benchmark All Four Models

Measure tok/s, page cache hit rate, TTFT, sustained generation quality.

### Parallel Track: flash-moe as Reference

Use flash-moe's `--serve PORT` HTTP/SSE mode as a subprocess benchmark.
This gives a reference ceiling for each model without any integration work.

## Why Not Option A

| Concern | Detail |
|---------|--------|
| **Bus factor** | 14K lines ObjC by external dev (Anemll), personal project |
| **Fork risk** | Must fork to parameterize; upstream may diverge |
| **MLA kernel** | Weeks of new ObjC Metal work with no intermediate deliverable |
| **Metal context** | Incompatible with MLX — all or nothing |
| **Observability** | Zero Prometheus integration; parsing stderr for metrics |
| **Crash recovery** | MetalWorker watchdog can't classify ObjC crashes |
| **Model onboarding** | Per-model: new expert_index, repack, attention kernel |

## Risk Register

| Risk | Mitigation |
|------|------------|
| Router sync (mx.eval) breaks async pipeline | Measure cost in starter experiment; if >2ms/layer, explore async routing |
| Page cache cold-start on task switches | Pre-warm experts based on Clavain task classifier signal |
| KV cache competes with page cache on long contexts | Monitor via vm_stat; implement KV eviction at memory pressure threshold |
| mx.array memoryview API changes in future MLX | Pin mlx-lm version; contribute streaming upstream (Option E) |
| 8 tok/s not achievable for Kimi K2.5 (3.3x ratio) | Accept 5-6 tok/s; use Q3 quantization; or defer Kimi K2.5 |

## Performance Findings (fd-performance)

The performance agent identified issues in the existing interfer codebase that
must be addressed before or alongside SSD streaming work:

### Must-Fix Before Streaming

1. **Default `kv_bits=4` for 60L+ MLA models** — unquantized MLA KV at 4K context
   directly competes with the expert page cache budget. 2GB of KV evicts 2GB of
   expert pages, degrading hit rate.

2. **Measure prefill I/O pattern** — the brainstorm focuses on decode but ignores
   prefill. If flash-moe does per-token pread during prefill, a 2K prompt generates
   2000 sequential pread calls before the first output token.

3. **Orphan cleanup in PromptCacheManager** — cache files at `/tmp` survive process
   restarts. With watchdog-enabled frequent restarts, orphaned files accumulate
   (~6GB per restart cycle for 700B models).

### Performance Cliffs

- **Cache hit degradation is non-linear**: at 85% hit, 1.2 experts/token from SSD.
  At 70%, 2.4 (double the I/O). At 60%, 3.2. The 4-thread pread pool that hides
  latency at 85% is insufficient at 70%.
- **KV cache + page cache competition**: `PromptCacheManager.store()` writes dirty
  pages that evict expert weight pages — creating a feedback loop where longer
  context → worse decode throughput.
- **Per-token `mx.exp`/`float(mx.max)` sync**: confidence tracking forces Metal
  synchronization 8-11 times per second. ~4ms/s overhead in a tight budget.

### Existing Code Fixes (low-hanging fruit)

- `_latency_samples` list grows unbounded, sorted on every /metrics scrape → use deque(maxlen=1000)
- Cascade probe discards KV state, generation re-runs full prefill → wire KV handoff
- PromptCacheManager lookup is O(n/64) with string allocation → use binary search + struct.pack
