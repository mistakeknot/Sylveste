---
artifact_type: prd
bead: Demarch-4dy
stage: design
---
# PRD: TurboQuant — 3-bit KV Cache Compression

## Problem

interfere's KV cache quantization uses mlx-lm's built-in uniform bit-width scheme (2/4/8-bit), which trades quality for memory savings. At 2-bit, quality degrades noticeably on long-context tasks. The planned Q8K/Q4V approach (Demarch-dw8) improves this but still uses 4-8 effective bits. TurboQuant (ICLR 2026) achieves 3-bit quantization with zero accuracy loss via polar coordinate mapping + JL residual correction — strictly better.

## Solution

Implement TurboQuant as an experiment module (`server/experiments/turbo_quant.py`) that intercepts KV cache tensors and applies PolarQuant + QJL quantization. Follows the existing experiment pattern (config-driven, toggled, metrics-emitting). Benchmark against kv_bits=2/4/8 baselines on Qwen3.5-35B and 122B models.

## Features

### F1: PolarQuant Core
**What:** Convert KV cache tensors to polar coordinates (r, theta) and quantize to a fixed circular grid, implemented as MLX array ops.
**Acceptance criteria:**
- [ ] `polar_quantize(tensor, grid_size) -> quantized` and `polar_dequantize(quantized, grid_size) -> tensor` functions work on arbitrary MLX arrays
- [ ] Grid size configurable per head dimension (default: 256 for 128d heads)
- [ ] Round-trip error (quantize then dequantize) is < 1% normalized MSE on random tensors
- [ ] No custom Metal kernels — pure `mlx.core` operations

### F2: QJL Residual Correction
**What:** Apply 1-bit Johnson-Lindenstrauss random projection to capture quantization residuals from PolarQuant, adding ~1 bit of effective precision.
**Acceptance criteria:**
- [ ] `qjl_encode(residual, projection_matrix) -> bits` and `qjl_decode(bits, projection_matrix) -> residual` work on MLX arrays
- [ ] Projection matrix is seeded per-layer for reproducibility
- [ ] Combined PolarQuant+QJL achieves ~3 effective bits per KV element
- [ ] QJL can be independently toggled (PolarQuant works without it)

### F3: Experiment Module Integration
**What:** Wire TurboQuant into interfere's experiment framework with config, inference hook, and metrics.
**Acceptance criteria:**
- [ ] Config block in `defaults.yaml` under `turbo_quant:` with `enabled`, `grid_size`, `qjl_dim`, `qjl_enabled` params
- [ ] Env var overrides: `INTERFERE_EXP_TURBO_QUANT_ENABLED=true`, etc.
- [ ] KV cache interception works with mlx-lm's `stream_generate` (via QuantizedKVCache subclass or model wrapper)
- [ ] Metrics emitted: `kv_memory_bytes`, `quantize_time_ms`, `dequantize_time_ms` per generation
- [ ] Old `kv_quantization` config block updated/replaced with TurboQuant params

### F4: Benchmark Comparison
**What:** Extend the benchmark harness to run TurboQuant against existing baselines and report memory/quality/throughput.
**Acceptance criteria:**
- [ ] `benchmark_cli.py --kv-mode=turbo_quant` flag alongside existing `--kv-bits`
- [ ] Memory delta reported: `mx.get_active_memory()` before/after generation, isolated from model weights
- [ ] Quality metric: perplexity or generation similarity score on standard prompt corpus
- [ ] Results saved to `docs/benchmarks/` with timestamp and config

## Non-goals

- Custom Metal kernels for throughput optimization (future work if memory validation succeeds)
- StreamingLLM integration (separate experiment, `max_kv_size` already parameterized)
- Production KV cache backend graduation (requires validation first)
- Support for non-Qwen models (test on Qwen3.5-35B/122B only)

## Dependencies

- mlx-lm KV cache API must expose tensors for interception (research during planning)
- Existing experiment framework (`server/experiments/config.py`)
- Existing benchmark harness (`server/benchmark.py`, `benchmark_cli.py`)
- Demarch-m0m (autoresearch campaign) will consume this experiment for parameter tuning

## Open Questions

- mlx-lm `QuantizedKVCache` internals: can we subclass, or must we wrap attention modules?
- Optimal grid sizes for Qwen3.5 head dimensions (128d) — paper tested on Llama/Gemma
- Whether MLX's JIT compiler optimizes polar coordinate ops well enough for throughput parity
