---
artifact_type: brainstorm
bead: Sylveste-4dy
stage: discover
---

# TurboQuant: 3-bit KV Cache Compression for interfere

## What We're Building

A TurboQuant experiment module for interfere that implements PolarQuant + QJL for 3-bit KV cache quantization on Apple Silicon via MLX. Two-stage approach: (1) PolarQuant converts key/value tensors to polar coordinates and maps them to a fixed circular grid, eliminating expensive per-token normalization; (2) QJL applies 1-bit Johnson-Lindenstrauss residual error correction. Target: 6x KV memory reduction with zero accuracy loss, measured against the existing kv_bits=4/8 baselines.

## Why This Approach

**Experiment module pattern (Approach C):** TurboQuant lives in `server/experiments/turbo_quant.py`, following the established pattern of early_exit and reservoir_routing. Config-driven toggle in `defaults.yaml`. Isolated from core inference — can be enabled/disabled without touching `inference.py`.

Rejected alternatives:
- **Pure inline (Approach A):** No isolation, pollutes generate() method
- **mlx-lm fork (Approach B):** Couples to mlx-lm internals, breaks on upstream updates

The experiment pattern also enables Sylveste-m0m (autoresearch parameter tuning) to iterate on grid sizes, JL dimensions, and bit allocation without touching core code.

## Key Decisions

1. **Experiment module, not core integration.** TurboQuant is a hypothesis — it enters as `server/experiments/turbo_quant.py` with its own config block, metrics, and kill criteria. If it validates, it can graduate to a core KV cache backend later.

2. **MLX array ops, not custom Metal kernels.** The paper's 8x throughput gains were on H100 with CUDA kernels. On Apple Silicon via MLX, we're primarily validating the memory reduction (6x KV savings). Throughput gains depend on MLX's compiler optimizing the polar coordinate ops — we'll measure, not assume.

3. **PolarQuant first, QJL second.** PolarQuant is the larger win (polar grid quantization eliminates normalization). QJL adds 1-bit residual correction. Implement and benchmark PolarQuant alone first, then layer QJL on top.

4. **Benchmark against existing kv_bits baselines.** The existing benchmark harness already measures tok/s, TTFT, and thermal with kv_bits=2/4/8. TurboQuant adds a new quantization scheme at ~3 effective bits. Compare memory usage (mx.get_active_memory), quality (perplexity on a standard prompt set), and throughput.

5. **KV cache tensor interception.** mlx-lm's `stream_generate` currently treats KV cache as opaque. TurboQuant needs to intercept KV tensors after each attention layer. Two paths: (a) use mlx-lm's `QuantizedKVCache` hook points if they exist, or (b) wrap the model's attention modules to intercept before/after cache updates. Research mlx-lm's cache API during planning.

6. **Replaces the Q8K/Q4V plan.** The existing `kv_quantization` experiment config (key_bits=8, value_bits=4) was the old approach (Sylveste-dw8). TurboQuant at 3-bit with zero quality loss is strictly better. Update the config block to use TurboQuant parameters instead.

## Open Questions

- **mlx-lm KV cache API:** Does `stream_generate` expose cache tensors for custom quantization, or do we need to monkey-patch attention modules? Check mlx-lm source for `QuantizedKVCache` and `BaseKVCache` interfaces.
- **Circular grid resolution:** The paper uses specific grid sizes per head dimension. What grid sizes work best for Qwen3.5's head dimensions (128d for 35B, likely 128d for 122B)?
- **JL projection matrix:** QJL uses a random projection matrix. For reproducibility, should this be seeded per-model or per-layer? Paper uses per-layer.
- **Memory measurement:** How to isolate KV cache memory from model weight memory in MLX? Need `mx.get_active_memory()` before/after generation with same prompt at different quantization levels.
- **StreamingLLM integration:** The bead mentions combining with StreamingLLM sinks. The `max_kv_size` parameter exists but isn't wired. Should TurboQuant work with rotating cache, or is that a separate experiment?
