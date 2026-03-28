---
bead: sylveste-8v3
epic: sylveste-14g
date: 2026-03-28
status: brainstorm
---

# Brainstorm: SSD Streaming for 700B+ MoE Models on M5 Max 128GB

## Problem

We have four frontier MoE models downloaded. Only one (Qwen3.5-397B) runs via flash-moe at 11.1 tok/s. The other three are too large for 128GB RAM and need SSD streaming. Target: 8+ tok/s for interactive use.

| Model | Total Params | Active | Quant | Disk | Status |
|-------|-------------|--------|-------|------|--------|
| Qwen3.5-397B | 397B | 17B (10/512) | 4-bit MLX | 209 GB | **11.1 tok/s via flash-moe** |
| DeepSeek V3.2 | 672B | 37B (8/256) | 4-bit MLX | 352 GB | Downloaded, no engine |
| GLM-5 | 744B | 40B (8/256) | 4-bit MLX | 390 GB | Downloaded, no engine |
| Kimi K2.5 | 1T | 32B (8/384) | 3-bit MLX | 418 GB | Downloaded, no engine |

## Hardware Constraints

- **M5 Max 128GB unified memory** — GPU and CPU share the same pool
- **NVMe SSD: ~7.4 GB/s sequential, ~5 GB/s random pread** (measured)
- **SSD DMA and GPU compute share the same memory controller** — cannot overlap (flash-moe finding: 58 failed experiments confirmed this)
- **Memory bandwidth: 546 GB/s** (M5 Max)

## Key Insight from flash-moe

The per-token decode breakdown (Qwen 397B, 4-bit, cache-io-split 4):
- Dense/attn: 30.3 ms (33.7%) — GPU compute
- o_proj+shared: 19.1 ms (21.2%) — GPU compute
- **Expert I/O: 37.5 ms (41.7%) — SSD bottleneck**
- Expert compute: 1.4 ms (1.6%) — GPU compute
- LM head: 1.6 ms (1.8%) — GPU compute

Expert I/O dominates. The path to 8+ tok/s is reducing expert I/O time.

## Approach 1: llama.cpp / Ollama with GGUF + mmap (Quickest to try)

**What:** llama.cpp supports all three architectures (kimi_k2, glm_moe_dsa, deepseek_v32). Ollama (0.18.2 installed) wraps llama.cpp. GGUF quants available on HuggingFace.

**Strategy:** Use 1-bit or 2-bit GGUF quants (smaller disk footprint), let llama.cpp mmap the model. OS page cache handles hot/cold expert paging. Use `-ngl 99 -ot ".ffn_.*_exps.=CPU"` to keep attention on GPU but experts on CPU/mmap.

**GGUF sizes at 1-bit:**
| Model | 1-bit GGUF | Fits 128GB? |
|-------|-----------|-------------|
| DeepSeek V3.2 | ~131 GB | Nearly — minimal swap |
| GLM-5 | ~176 GB | 48 GB overflow |
| Kimi K2.5 | ~240 GB | 112 GB overflow |

**Expected perf:** DeepSeek 5-10 tok/s (nearly fits), GLM-5 3-6 tok/s, Kimi 0.5-2 tok/s (published benchmarks say <2 tok/s below 240GB RAM for Kimi).

**Pros:** Zero development work. Just download GGUFs and run.
**Cons:** 1-bit quality is poor. mmap is not optimized for MoE access patterns. No expert-selective streaming.

## Approach 2: Hypura (MoE-aware SSD streaming)

**What:** [github.com/t8/hypura](https://github.com/t8/hypura) — purpose-built for "models too big for your Mac." Reads GGUF from NVMe via F_NOCACHE + pread, prefetches based on transformer forward pass order. MoE optimization: intercepts router decisions, loads only active experts.

**Status:** v0.1.0, only tested on Qwen 2.5, Mixtral, Llama 3.3. Kimi K2.5/GLM-5/DeepSeek V3.2 not listed but should load any GGUF.

**Published:** Mixtral 8x7B (47B total, 13B active) → 2.2 tok/s on M1 Max 32GB.

**Estimated for M5 Max 128GB:** 2-4 tok/s for Kimi K2.5 at 1-bit. Potentially better for DeepSeek V3.2 (smaller model, nearly fits in RAM).

**Pros:** Designed for this exact problem. Ollama-compatible API.
**Cons:** Very early (v0.1.0). Untested on our architectures. May not understand MLA attention or 384-expert routing.

## Approach 3: flash-moe port (Best performance, most work)

**What:** Port flash-moe's proven C/Metal engine to each model architecture. flash-moe achieves 11.1 tok/s on the 397B model — far ahead of any other approach.

**Why it's fast:** Hand-tuned Metal shaders for dequant+matvec, parallel pread() via GCD, tiered I/O (cold fds with F_NOCACHE for first access, warm fds for page cache hits), page-aligned SSD fanout.

**Work required per model:**
- New Metal shaders for each attention variant (MLA for Kimi/DeepSeek, DSA for GLM-5)
- New weight extraction + expert repacking scripts
- Architecture-specific layer loop in infer.m (~7000 lines)
- Estimate: 2-4 weeks per model

**Variant: Generalized flash-moe framework.** Abstract the model-specific parts (attention, expert layout, weight format) into a config + plugin system. Then each model is a thin adapter. More upfront work but pays off for 4+ models.

**Pros:** Proven 2.5x over llama.cpp on same hardware. Best possible performance.
**Cons:** Massive engineering effort. Each architecture is significantly different.

## Approach 4: MLX with mmap experimentation

**What:** MLX can't mmap for GPU, but we could try a hybrid: load dense/attention weights into MLX (GPU), and manually pread() expert weights from safetensors, converting to MLX arrays on the fly.

**The math:** For Kimi K2.5, dense weights are ~15B params = ~7.5 GB at 3-bit. Experts are ~1032B = ~387 GB. If we keep 7.5 GB resident and stream experts, 128GB - 7.5GB = 120.5 GB for page cache. With 384 experts × 60 layers = 23,040 total experts, and 8 active per layer per token = 480 expert accesses/token. Each expert at 3-bit is ~750 KB. 480 × 750 KB = 360 MB per token from SSD.

At 7.4 GB/s: 360 MB / 7.4 GB/s = 49 ms per token just for I/O → theoretical max ~20 tok/s. With page cache hits reducing this by 70-80% → ~10-15 ms → **66-100 tok/s theoretical maximum** from I/O alone. GPU compute is the real bottleneck.

**Pros:** We already have the MLX weights. No format conversion needed.
**Cons:** Requires building a custom inference engine (essentially flash-moe but in Python/MLX). MLX can't mmap for GPU — we'd need manual buffer management.

## Recommended Strategy

**Phase 1 — Quick benchmarks with existing tools (1-2 days):**
1. Try `ollama run` with DeepSeek V3.2 using our existing 4-bit MLX weights converted to GGUF, or download 1-bit GGUF directly
2. Try Hypura if it installs cleanly
3. This gives us baseline numbers to compare against

**Phase 2 — Optimize the winner (1 week):**
- If ollama/llama.cpp gets 5+ tok/s on DeepSeek → tune with expert offload flags, madvise hints
- If Hypura works → profile and optimize its MoE router interception
- If neither breaks 3 tok/s → move to Phase 3

**Phase 3 — Custom engine (2-4 weeks):**
- Port flash-moe approach to a generalized framework
- Start with DeepSeek V3.2 (most similar to Qwen3.5, both use MLA attention)
- Key abstractions: model config, attention backend, expert layout, weight format

## Open Questions

1. Can we convert our existing MLX safetensors to GGUF without re-downloading? (Would save 131-240 GB of downloads)
2. Does Hypura's MoE router interception work with MLA attention (kv_lora_rank)?
3. What's the actual 1-bit quality degradation on these models? Need PPL measurements.
4. Could we build a "flash-moe lite" that reuses flash-moe's Metal shaders but adds model-agnostic weight loading?
5. Is the M5 Max's NVMe actually faster than published specs? Need to benchmark with `cache_pread_bench`.
