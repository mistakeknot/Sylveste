---
bead: sylveste-8v3
epic: sylveste-14g
date: 2026-03-28
status: prd
---

# PRD: SSD Streaming Inference for 700B+ MoE Models

## Problem Statement

Four frontier MoE models (397B-1T params) are downloaded locally. Only one runs at interactive speed. The other three exceed 128GB RAM and have no optimized inference path. Without this, the Pareto frontier analysis (sylveste-m71) and local model routing are blocked.

## Goal

Run all four models at **8+ tok/s** on M5 Max 128GB with coherent output quality. 8 tok/s is the threshold where streaming text matches reading speed — below this, users notice the lag.

## Non-Goals

- Multi-user serving / batched inference
- Training or fine-tuning
- Vision/multimodal capabilities (text-only)
- Building a general-purpose framework (optimize for these 4 models specifically)

## Success Criteria

| Model | Target tok/s | Quality Gate |
|-------|-------------|-------------|
| Qwen3.5-397B | 11+ (already achieved) | PPL < 4.0 |
| DeepSeek V3.2 672B | 8+ | Coherent multi-paragraph output |
| GLM-5 744B | 8+ | Coherent multi-paragraph output |
| Kimi K2.5 1T | 6+ (stretch: 8+) | Coherent multi-paragraph output |

Kimi K2.5 has a relaxed target (6+ tok/s) because at 1T params / 240GB 1-bit, it's the hardest to fit.

## Features

### F1: Quick Benchmark Suite (P0)
Benchmark all three new models with existing tools (ollama/llama.cpp) to establish baselines. No development work — just download GGUFs and measure.

### F2: DeepSeek V3.2 Optimization (P0)
DeepSeek V3.2 at 1-bit GGUF (~131GB) nearly fits in 128GB. This is the highest-probability path to 8+ tok/s. Optimize llama.cpp flags for Apple Silicon MoE offloading.

### F3: GLM-5 Benchmark + Optimization (P1)
GLM-5 at 1-bit GGUF (~176GB) has 48GB overflow. Test with mmap and measure page cache behavior. If <6 tok/s, evaluate Hypura or custom streaming.

### F4: Kimi K2.5 Benchmark + Streaming Engine (P1)
Kimi K2.5 at 1-bit is 240GB — 112GB overflow. Unlikely to hit 8 tok/s with generic mmap. May need Hypura or a flash-moe-style custom engine. Start with baseline measurement, then decide.

### F5: SSD Benchmark + Page Cache Profiling (P2)
Measure actual M5 Max NVMe throughput with flash-moe's `cache_pread_bench`. Profile OS page cache hit rates during inference to guide optimization decisions.

## Architecture Decision: GGUF vs MLX Weights

We downloaded MLX safetensors (3-bit/4-bit). The fastest inference tools (llama.cpp, ollama, Hypura) use GGUF format. Options:

1. **Download GGUF separately** — adds 131-240GB per model but gives access to optimized 1-bit/2-bit quants
2. **Convert MLX → GGUF** — may be possible but not well-supported tooling
3. **Use MLX weights directly** — only works with mlx-lm (no SSD streaming support)

**Decision: Download GGUF 1-bit for DeepSeek V3.2 first (~131GB).** If results are promising, download for GLM-5 and Kimi K2.5. Keep MLX weights for potential flash-moe-style engine later.

## Risks

| Risk | Impact | Mitigation |
|------|--------|-----------|
| 1-bit quality is too degraded | High | Also test 2-bit; compare PPL |
| llama.cpp mmap is too slow for 700B+ | Medium | Try Hypura; consider flash-moe port |
| Hypura doesn't support these architectures | Medium | Fall back to llama.cpp or custom engine |
| NVMe bandwidth insufficient for 1T model | Low | flash-moe proved 397B works; larger models have same per-token I/O pattern |

## Timeline

- **Day 1:** F1 (baselines) + F2 (DeepSeek optimization) — download GGUF, benchmark
- **Day 2:** F3 (GLM-5) + F5 (SSD profiling)
- **Day 3-4:** F4 (Kimi K2.5) — try available tools, evaluate custom engine need
- **Week 2:** Custom engine work if needed for Kimi K2.5
