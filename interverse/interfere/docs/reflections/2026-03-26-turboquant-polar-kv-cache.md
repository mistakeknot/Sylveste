---
artifact_type: reflection
bead: Demarch-4dy
stage: reflect
---

# Reflection: TurboQuant Polar-Transformed KV Cache

## What happened

Implemented a polar coordinate transformation experiment for KV cache quantization in interfere. The plan review (3 agents: correctness, performance, architecture) caught a critical storage math error before any code was written — the original custom `TurboQuantCache` design stored ~12 bits/element (not 3), and the dequantize-on-fetch pattern would have been O(seq_len) per token. Pivoted to a fundamentally simpler approach: `PolarCacheWrapper` that wraps mlx-lm's native `QuantizedKVCache`, applying polar transform before storage and inverse after retrieval. The fused attention kernel handles decompression — zero custom dequantize overhead.

## Key learnings

**Plan review before coding saved significant rework.** The bit-accounting error (uint8 per dim-pair = 8 bits/dim, not 2) would have been discovered only after benchmarking. Three agents converging on the same P0 from different angles (correctness: storage math, performance: memory comparison, architecture: dual pathway conflict) gave high confidence the finding was real.

**Wrap, don't subclass, for experiment integration.** The `PolarCacheWrapper` pattern (delegate via `__getattr__`, intercept only `update_and_fetch`) is model-agnostic and survives mlx-lm upgrades. The original plan's `TurboQuantCache(_BaseCache)` would have needed `offset`, `state`, `meta_state`, `nbytes`, `empty()`, `from_state` — all load-bearing methods the plan left as stubs.

**QJL requires jl_dim >= 2x head_dim.** At jl_dim=64 with head_dim=128 (the original plan), the 1-bit sketch adds noise instead of correcting it. The test caught this definitively. Autoresearch should explore jl_dim=256+ only.

**Autoresearch-first is the right pattern for quantization experiments.** Whether polar coordinate transformation actually improves quantization quality on real Qwen hidden states is an empirical question that can't be answered by planning. The scaffold (interlab-turboquant-tune.sh) lets the autoresearch campaign (Demarch-m0m) answer it with data.

## What to do differently

- Run bit-accounting math on paper before designing storage formats
- Default to wrapping existing infrastructure rather than reimplementing
- For numerical algorithms, write the test *before* the implementation — the QJL jl_dim issue would have been a clear test spec upfront
