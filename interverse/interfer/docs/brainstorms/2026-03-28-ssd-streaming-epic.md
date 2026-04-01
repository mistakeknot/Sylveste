---
bead: sylveste-14g
date: 2026-03-28
type: brainstorm
---

# SSD Streaming Inference for 700B+ MoE Models

## Problem

Models larger than ~2x unified memory cannot run via mlx-lm's standard
mmap path — Metal GPU times out during page faults. All frontier MoE
models (Kimi K2.5 418GB, GLM-5 390GB, DeepSeek V3.2 352GB) exceed this
threshold on M5 Max 128GB. Confirmed by GPU timeout benchmarks
(sylveste-8v3, sylveste-bpg, sylveste-uln).

## flash-moe Architecture (Qwen 397B baseline: 11.1 tok/s)

flash-moe's key innovation: **pre-read experts via pread() before
submitting Metal GPU work**, avoiding page faults during command buffer
execution. Three-phase per-layer pipeline:

1. **CMD1 (GPU)**: Attention QKV + gate projections
2. **CPU**: Attention compute + routing softmax + top-K expert selection
3. **I/O**: pread() K experts from SSD (page-aligned fanout, 4 concurrent chunks)
4. **CMD2 (GPU)**: o_proj + residual + norm + routing (fused)
5. **CMD3 (GPU, deferred)**: Expert compute + combine (overlaps next layer's CMD1)

Expert I/O dominates at 35-47% of decode time. OS page cache provides
~71% hit rate naturally. Cache-io-split=4 gives +6% throughput.

## What's Generalizable vs Model-Specific

**Generalizable (works for any MoE architecture):**
- pread() expert streaming + page-aligned fanout
- FMA-optimized dequant kernels
- Async expert compute (deferred GPU execution)
- Expert routing (softmax + top-K)
- RMS norm, softmax, sigmoid
- repack_experts.py (data-driven layout)

**Model-specific (needs new code per architecture):**
- Attention mechanism: GQA (Qwen) vs MLA (DeepSeek/Kimi/GLM)
- Buffer allocation: hardcoded #defines for hidden_dim, num_experts, etc
- Layer configuration: which layers are MoE vs dense, attention type per layer
- Quantization profile: expert tensor sizes vary with hidden_dim

## Target Models

| Model | Total | Active | Experts | K | Attention | Size | Ratio |
|-------|-------|--------|---------|---|-----------|------|-------|
| Qwen 397B (baseline) | 397B | 17B | 512 | 4-10 | GQA + GatedDeltaNet | 209GB | 1.6x |
| DeepSeek V3.2 | 672B | ~37B | 256 | 8 | MLA | 352GB | 2.75x |
| GLM-5 | 744B | 40B | 256 | 8 | MLA variant | 390GB | 3.0x |
| Kimi K2.5 | ~1T | 32B | 256 | 8 | MLA (DeepSeek-derived) | 418GB | 3.3x |

All three new models use MLA attention and 256 experts (vs Qwen's 512 + GQA).

## Approach Options

### Option A: Parameterize flash-moe (estimated 3-5 days)

Refactor infer.m from hardcoded #defines to runtime config. Add MLA
attention kernel. Generate expert indices for each model.

Pros: Known performance characteristics, existing optimization suite
Cons: ~7500 lines of Objective-C Metal code to refactor, MLA kernel is new

### Option B: mlx-lm with custom SSD streaming layer (estimated 5-7 days)

Fork mlx-lm's generate loop to pre-read expert weights via pread()
before Metal forward pass. Keep mlx-lm's model support (already has
all four architectures) but replace the weight loading path.

Pros: Supports all models automatically, Python-level changes
Cons: May not achieve same performance as hand-tuned Metal kernels

### Option C: Hybrid — flash-moe pread + mlx-lm models (estimated 7-10 days)

Use flash-moe's I/O pipeline (pread + page cache) with mlx-lm's model
definitions. Essentially a new inference engine that combines the best
of both.

Cons: Biggest scope, most integration complexity

## Recommendation

**Option A** — parameterize flash-moe. It has proven 11.1 tok/s performance
and the model-specific changes (MLA kernel, config struct) are well-scoped.
The 256-expert models have simpler routing than Qwen's 512, so I/O per token
is actually lower.

## Phased Execution

1. **Phase 1**: Config struct + dynamic buffer allocation (no new models yet)
2. **Phase 2**: MLA attention kernel (enables DeepSeek V3.2 + Kimi K2.5)
3. **Phase 3**: Expert index generation + repacking for each model
4. **Phase 4**: Benchmark + tune cache-io-split per model
5. **Phase 5**: GLM-5 support (if MLA variant differs from DeepSeek)

## Success Criteria

8+ tok/s decode on all four models on M5 Max 128GB.
