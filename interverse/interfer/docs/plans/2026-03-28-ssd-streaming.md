---
bead: sylveste-14g
date: 2026-03-28
type: plan
complexity: C4
reviewed_by: 8-agent flux-drive synthesis
---

# Plan: SSD Streaming Inference for 700B+ MoE Models

## Context

8 review agents unanimously recommended Option D (mlx-lm fork with
StreamingSwitchGLU) over the brainstorm's Option A (parameterize flash-moe).
Key reasons: zero-copy Python path exists (mx.array memoryview + ctypes pread
= 47.5 GB/s measured), flash-moe Metal contexts are incompatible with MLX,
and the I/O bottleneck is SSD bandwidth not language overhead.

## Phase 0: Starter Experiment (Day 0, resolves core uncertainty) — COMPLETE

**Goal**: Measure whether Python pread-based expert streaming on Qwen 397B
reaches within 20% of flash-moe's 11.1 tok/s. This one data point collapses
the entire A-vs-D decision.

**Result**: 1.5 tok/s — 7.4x slower than flash-moe (86% gap). Kill criteria
triggered (>30%). See `docs/benchmarks/streaming_phase0_analysis.md`.

### Task 0.1: Expert file preparation — DONE

Repacked all 60 layers via `repack_experts.py` from flash-moe: 203 GB at
3.6 GB/s in 56 seconds. All layers verified (experts 0, 1, 255, 511 per layer).

### Task 0.2: Proof-of-concept StreamingSwitchGLU — DONE

Implemented `server/streaming_switch.py` with `StreamingMoeBlock` class:
- Lazy model loading: 397B in 1.6s, 5.1 GB GPU (expert weights on NVMe)
- True zero-copy: `libc.pread()` → mx.array Metal buffer at 14.5 GB/s
- Drop-in `SparseMoeBlock` replacement (MLX `nn.Module.__call__` uses C++
  dispatch; instance-level `__call__` overrides are ignored, requiring a
  full wrapper class rather than monkey-patching)
- Dynamic buffer allocation for variable unique experts (10 decode, 87+ prefill)

### Task 0.3: Benchmark — DONE

5 prompts × 200 tokens on Qwen 397B 4-bit:

| Metric | Streaming | flash-moe | Gap |
|--------|-----------|-----------|-----|
| tok/s  | 1.5       | 11.1      | 7.4x|
| TTFT   | 6.4s      | ~2s       | 3x  |
| Memory | 37 GB     | 35 GB     | same|
| pread  | 9.3 GB/s  | N/A       | —   |

Per-layer breakdown (decode): 7.5ms pread + 3.5ms mx.eval sync + overhead = 11ms.
60 layers × 11ms = 660ms/token → 1.5 tok/s.

### Task 0.4: Decision gate — >30% GAP → KILL CRITERIA

Bottleneck is NOT I/O bandwidth. It's 60 per-layer `mx.eval(inds)` CPU-GPU
synchronization points (~2ms each). flash-moe avoids this by running the
entire forward pass in fused Metal.

**Decision**: Abandon Option D (pure Python pread). Promote Phase 4.1
(flash-moe subprocess proxy) to next action.

## Phase 1: StreamingSwitchGLU Implementation (Days 1-3)

### Task 1.1: Expert index generator

Python script that scans a model's safetensors files and produces an
`expert_layout.json` mapping each layer's experts to file offsets.
Similar to flash-moe's `repack_experts.py` but for the mlx-lm weight format.

Input: model directory (safetensors + config.json)
Output: `expert_layout.json` with per-layer expert offsets

### Task 1.2: Expert repacker

Repack scattered safetensors into one binary per MoE layer:
`packed_experts/layer_XX.bin` — experts at fixed offsets, contiguous.
Per-layer file layout (matching flash-moe's proven design).

### Task 1.3: StreamingSwitchGLU class

Full implementation with:
- Pre-allocated mx.array buffer pool via memoryview
- ThreadPoolExecutor(max_workers=4) for parallel pread
- Router sync point (`mx.eval(inds)`)
- Weight replacement via `mx.stack()` + assignment
- Shared expert pinning (427MB resident, always loaded)
- `--streaming-weights` CLI flag to enable

### Task 1.4: Wire into InferenceEngine

- New `streaming=True` parameter on `InferenceEngine.__init__`
- Load expert layout at init, open layer file descriptors
- Monkey-patch SwitchGLU at model load time
- MetalWorker protocol unchanged (GENERATE command works as-is)

### Task 1.5: Tests

- Unit test: expert index generation for Qwen safetensors layout
- Unit test: pread into mx.array memoryview correctness
- Unit test: StreamingSwitchGLU produces same output as standard SwitchGLU (on tiny model)
- Integration test: generate with streaming flag in dry-run mode

## Phase 2: Model Onboarding (Days 3-5)

### Task 2.1: DeepSeek V3.2 expert index + repack

Generate expert_layout.json and packed layer files for DeepSeek V3.2.
mlx-lm already has the model definition — no new attention code needed.

### Task 2.2: Benchmark DeepSeek V3.2

Target: 8+ tok/s. Measure decode, TTFT, quality (5 standard prompts).
Record page cache hit rate and compare to estimates (~85%).

### Task 2.3: GLM-5 expert index + repack + benchmark

Same process. Target: 6+ tok/s (borderline per I/O analysis).

### Task 2.4: Kimi K2.5 expert index + repack + benchmark

Same process. Target: 5+ tok/s (at risk per I/O analysis).
May need Q3 quantization for viable performance.

## Phase 3: Production Hardening (Days 5-7)

### Task 3.1: Performance fixes from fd-performance review

- Default `kv_bits=4` for 60L+ MoE models
- PromptCacheManager orphan cleanup at init
- Cap `_latency_samples` with deque(maxlen=1000)
- Batch confidence computation post-generation (remove per-token mx.eval sync)

### Task 3.2: Prometheus metrics for streaming

Add to prom.py:
- `interfer_ssd_pread_bytes_total` (counter)
- `interfer_expert_cache_hit_rate` (gauge, from vm_stat sampling)
- `interfer_streaming_io_seconds` (histogram, per-layer I/O time)

### Task 3.3: Cascade integration

When cascade is enabled with streaming models:
- Probe uses streaming path (same expert loading)
- Wire KV state handoff from probe to continuation (fix double-prefill bug)

### Task 3.4: Shadow cost logging for streaming models

Log to `local_routing_shadow` table with actual model used and tok/s achieved.
`infer_cloud_model()` already maps model sizes to cloud tiers.

## Phase 4: Parallel Track — flash-moe Reference (ongoing)

### Task 4.1: flash-moe subprocess benchmark harness

Use flash-moe's `--serve PORT` HTTP/SSE mode as a reference ceiling.
interfer proxies to it for A/B comparison.

### Task 4.2: Upstream contribution (Option E)

File design proposal to mlx-lm for native SSD streaming support.
Reference benchmark data from Phase 2. If accepted, migrate from
StreamingSwitchGLU monkey-patch to upstream API.

## File Change Summary

| File | Change |
|------|--------|
| `server/streaming_switch.py` | NEW — StreamingSwitchGLU, expert layout loader, pread pool |
| `server/inference.py` | Add streaming=True parameter, monkey-patch at load |
| `server/metal_worker.py` | Pass streaming flag through to InferenceEngine |
| `server/__main__.py` | Add --streaming-weights CLI flag |
| `server/prom.py` | Add streaming I/O metrics |
| `server/main.py` | Wire streaming flag, fix latency_samples cap |
| `server/prompt_cache.py` | Add orphan cleanup at init |
| `scripts/expert_index.py` | NEW — generate expert_layout.json from safetensors |
| `scripts/repack_experts.py` | NEW — repack into per-layer binary files |
| `tests/test_streaming_switch.py` | NEW — streaming unit + integration tests |

## Success Criteria

| Model | Target tok/s | Confidence |
|-------|-------------|------------|
| Qwen 397B (4-bit) | 9+ | High (baseline 11.1 via flash-moe) |
| DeepSeek V3.2 (4-bit) | 8+ | Medium-high (85% cache hit estimated) |
| GLM-5 (4-bit) | 6+ | Medium (borderline I/O budget) |
| Kimi K2.5 (3-bit) | 5+ | Medium-low (3.3x ratio, may need Q3) |

## Kill Criteria

- If Phase 0 shows >30% gap vs flash-moe: stop, reassess Option A
- If DeepSeek V3.2 < 5 tok/s after tuning: the approach is fundamentally limited
- If mx.array memoryview API breaks in future MLX: pin version, escalate upstream

## Risks

| Risk | Mitigation |
|------|------------|
| Router sync (mx.eval) adds >2ms/layer | Profile in Phase 0; if bad, explore async routing |
| Page cache cold-start on task switches | Pre-warm from Clavain task classifier signal |
| KV cache competes with page cache | Default kv_bits=4 for large models |
| mx.array memoryview API unstable | Pin mlx-lm version; pursue Option E upstream |
| Qwen repacked experts not available | Re-run flash-moe's repack_experts.py |
