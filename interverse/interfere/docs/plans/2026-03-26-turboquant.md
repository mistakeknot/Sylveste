---
artifact_type: plan
bead: Sylveste-4dy
prd: interverse/interfere/docs/prds/2026-03-26-turboquant.md
features:
  - Sylveste-fsj  # F1: PolarQuant core
  - Sylveste-60j  # F2: QJL residual correction
  - Sylveste-ikf  # F3: Experiment module integration
  - Sylveste-keo  # F4: Benchmark comparison
revision: 2  # Post-review rewrite — autoresearch-first approach
review_findings: |
  P0: Storage layout was ~12 bits/element (not 3). Dequantize-on-fetch O(seq_len) per token.
  P0: offset/state/nbytes/empty() missing from cache class.
  P0: Dual KV pathway conflict (kv_bits vs turbo_quant).
  P1: Per-token scale needed, float32 for polar math, bool("false")==True bug.
  Performance recommended Option C: polar-transform then use MLX native quantization.
---

# Plan: TurboQuant — Autoresearch-First KV Cache Compression

## Plan Review Outcome

Three-agent review (correctness, performance, architecture) found critical issues:

1. **Storage math wrong:** uint8 pairs = 8 bits/dim, not 3. With QJL: 12 bits/element — *larger* than kv_bits=8.
2. **Dequantize-on-fetch is O(seq_len):** 2.4ms overhead/token at 4K, 43ms at 32K. Incremental buffer defeats memory savings.
3. **Best path forward (Option C from perf review):** Apply polar transform, then use MLX's native `mx.quantize` at 4-bit. Keeps the fused `quantized_scaled_dot_product_attention` kernel — no custom dequantize needed.

**Decision:** Build a minimal scaffold, then let autoresearch (Sylveste-m0m) explore the mutation space. The key unknown — whether polar coordinate transformation improves quantization quality vs vanilla kv4 — is empirical.

## Architecture: Polar-Transformed Native Quantization

Instead of a custom `TurboQuantCache` with dequantize-on-fetch, we:

1. **Pre-transform** K/V tensors to polar coordinates before they enter the cache
2. **Use mlx-lm's existing `QuantizedKVCache`** to store the transformed tensors at 4-bit
3. **Post-transform** back from polar on dequantize (handled by fused kernel + a thin wrapper)

This avoids the two P0s (storage math and dequantize cost) while preserving the core hypothesis: polar coordinate representation may quantize better than raw Cartesian K/V.

**Integration path:** Wrap each layer's Attention module to intercept K/V *before* they reach the cache. The cache itself stays as `QuantizedKVCache(bits=4, group_size=64)`. The wrapper applies polar_transform on the way in and inverse_polar_transform on the K/V returned by `update_and_fetch`.

```python
class PolarAttentionWrapper:
    """Wraps a model's attention layer to apply polar transform to K/V."""

    def __init__(self, original_attention, grid_size=16):
        self._attn = original_attention
        self._grid_size = grid_size

    def __call__(self, x, mask=None, cache=None):
        # 1. Compute Q, K, V via original projections
        # 2. Apply polar_transform to K and V (Cartesian -> polar coords)
        # 3. Let cache.update_and_fetch store at native 4-bit quantization
        # 4. Apply inverse_polar_transform to cached K, V
        # 5. Run attention with transformed tensors
```

**Why this works:** `QuantizedKVCache` uses `mx.quantize` which is uniform linear quantization. Polar-transformed tensors have different value distributions (bounded angles, non-negative radii) that may quantize with lower error than raw K/V. The autoresearch campaign will measure this.

## Tasks

### Task 1: Polar transform primitives (F1: Sylveste-fsj)

**File:** `server/experiments/turbo_quant.py` (new)

```python
import mlx.core as mx

def polar_transform(tensor: mx.array) -> mx.array:
    """Convert (..., head_dim) tensor to polar representation in-place.

    Pairs adjacent dims: (x0,x1), (x2,x3), ... -> (r0,theta0), (r1,theta1), ...
    Returns same shape — first half of each pair is r, second is theta.
    Computation in float32 for precision (cast back to input dtype after).
    """
    orig_dtype = tensor.dtype
    t = tensor.astype(mx.float32)
    *batch, d = t.shape
    t = t.reshape(*batch, d // 2, 2)
    x, y = t[..., 0], t[..., 1]
    r = mx.sqrt(x * x + y * y)
    theta = mx.arctan2(y, x)  # [-pi, pi]
    # Normalize theta to [0, 1] for better quantization distribution
    theta = (theta + mx.pi) / (2 * mx.pi)
    result = mx.stack([r, theta], axis=-1).reshape(*batch, d)
    return result.astype(orig_dtype)

def inverse_polar_transform(tensor: mx.array) -> mx.array:
    """Convert polar representation back to Cartesian."""
    orig_dtype = tensor.dtype
    t = tensor.astype(mx.float32)
    *batch, d = t.shape
    t = t.reshape(*batch, d // 2, 2)
    r, theta_norm = t[..., 0], t[..., 1]
    theta = theta_norm * (2 * mx.pi) - mx.pi
    x = r * mx.cos(theta)
    y = r * mx.sin(theta)
    result = mx.stack([x, y], axis=-1).reshape(*batch, d)
    return result.astype(orig_dtype)
```

**Key fixes from review:**
- Float32 for all trig ops (P1-3: float16 angular precision)
- Theta normalized to [0,1] for uniform quantization distribution
- No scale parameter needed — `mx.quantize` handles its own per-group scaling (P1-2 resolved)
- Zero vectors: `sqrt(0) = 0`, `atan2(0,0) = 0` → round-trips correctly

**Tests:** `tests/test_turbo_quant.py`
- Round-trip MSE < 0.1% on `mx.random.normal(shape=(1, 8, 128, 128))`
- Shape preservation
- Zero vector round-trip
- Dtype preservation (float16 in, float16 out)
- Grid: test with actual Qwen hidden state distributions if available

**Acceptance:** Round-trip error (transform then inverse) < 0.01% normalized MSE. This measures only the transform — quantization error is separate.

### Task 2: QJL residual correction (F2: Sylveste-60j)

**File:** `server/experiments/turbo_quant.py` (extend)

Same as original plan — QJL is an optional add-on. But now it operates on the *quantization residual after native 4-bit quantization*, not on custom polar quantization residuals. This means:

```python
# In the attention wrapper, after cache returns quantized K/V:
cached_kv = cache.update_and_fetch(polar_k, polar_v)  # 4-bit quantized
if qjl_enabled:
    # Residual = original - quantized (in polar space)
    residual = polar_k - cached_kv[0]  # only for new tokens
    bits = qjl_encode(residual, projection)
    # Store bits alongside cache (separate buffer)
    # On decode: cached_kv + qjl_decode(stored_bits, projection)
```

**Deferred to autoresearch:** Whether QJL correction at this point adds enough quality to justify the storage. The autoresearch campaign will toggle `qjl_enabled` as a mutation dimension.

**Tests:** Same as original plan.

### Task 3: Attention wrapper + experiment integration (F3: Sylveste-ikf)

**Files:**
- `server/experiments/turbo_quant.py` — `PolarAttentionWrapper` class
- `server/experiments/defaults.yaml` — config block
- `server/inference.py` — wrapper injection

**PolarAttentionWrapper:**
```python
class PolarAttentionWrapper:
    """Wraps attention to apply polar transform to K/V before cache."""

    def __init__(self, original_attention, qjl_enabled=False, jl_dim=64, layer_idx=0):
        self._attn = original_attention
        self._qjl_enabled = qjl_enabled
        # Copy all projection layers from original
        self.q_proj = original_attention.q_proj
        self.k_proj = original_attention.k_proj
        self.v_proj = original_attention.v_proj
        self.o_proj = original_attention.o_proj
        self.rope = original_attention.rope
        self.scale = original_attention.scale
        self.n_heads = original_attention.n_heads
        self.n_kv_heads = original_attention.n_kv_heads

    def __call__(self, x, mask=None, cache=None):
        queries = self.q_proj(x)
        keys = self.k_proj(x)
        values = self.v_proj(x)
        # reshape for multi-head...

        if cache is not None:
            queries = self.rope(queries, offset=cache.offset)
            # Apply polar transform BEFORE cache stores them
            keys = polar_transform(keys)
            values = polar_transform(values)
            keys, values = cache.update_and_fetch(keys, values)
            # Inverse transform AFTER cache returns (possibly quantized) K/V
            keys = inverse_polar_transform(keys)
            values = inverse_polar_transform(values)
        else:
            queries = self.rope(queries)
            keys = self.rope(keys)

        output = mx.fast.scaled_dot_product_attention(
            queries, keys, values, cache=cache, scale=self.scale, mask=mask
        )
        return self.o_proj(output.reshape(B, L, -1))
```

**Important:** RoPE is applied to queries and keys *before* polar transform. The polar transform operates on the RoPE-rotated K vectors. This preserves positional information in the quantized representation.

Wait — that's wrong. Looking at the mlx-lm pattern: RoPE is applied to queries with `offset=cache.offset`, but for keys, RoPE is applied to the *new* keys only, and `cache.update_and_fetch` concatenates them with previously-cached (already RoPE'd) keys. So we need:

```python
if cache is not None:
    queries = self.rope(queries, offset=cache.offset)
    keys = self.rope(keys, offset=cache.offset)
    # Polar transform the new RoPE'd keys/values
    keys = polar_transform(keys)
    values = polar_transform(values)
    keys, values = cache.update_and_fetch(keys, values)
    # Inverse transform everything returned from cache
    keys = inverse_polar_transform(keys)
    values = inverse_polar_transform(values)
```

Actually, this is also wrong — `cache.update_and_fetch` returns *all* cached keys including previous ones that were already polar-transformed. Applying `inverse_polar_transform` to the full cache output is correct: every stored key was polar-transformed on entry, so every returned key needs inverse on exit.

**defaults.yaml:**
```yaml
  turbo_quant:
    enabled: false
    qjl_enabled: false  # autoresearch toggles this
    jl_dim: 64
    kv_bits: 4           # which native quantization to use underneath
    kv_group_size: 64
```

Keep the old `kv_quantization` block with a deprecation comment.

**inference.py changes:**
In `_init_hooks()`: store config.
In `generate()`: if turbo_quant enabled, wrap model attention layers before calling `stream_generate`:

```python
if self._turbo_quant_cfg is not None and self._turbo_quant_cfg.enabled:
    from .experiments.turbo_quant import PolarAttentionWrapper
    kv_bits = int(self._turbo_quant_cfg.get("kv_bits", 4))
    # Temporarily wrap attention layers
    original_layers = []
    for i, layer in enumerate(model.model.layers):
        original_layers.append(layer.self_attn)
        layer.self_attn = PolarAttentionWrapper(
            layer.self_attn,
            qjl_enabled=...,
            layer_idx=i,
        )
    gen_kwargs["kv_bits"] = kv_bits  # use native quantization
    gen_kwargs["kv_group_size"] = int(self._turbo_quant_cfg.get("kv_group_size", 64))
    metrics.kv_mode = "turbo_quant"

# ... stream_generate ...

# Restore original attention layers after generation
if self._turbo_quant_cfg is not None and self._turbo_quant_cfg.enabled:
    for i, orig in enumerate(original_layers):
        model.model.layers[i].self_attn = orig
```

**Fix for P0.1 (dual pathway):** Add mutual exclusion guard:
```python
if self._turbo_quant_cfg and self._turbo_quant_cfg.enabled and kv_bits is not None:
    # TurboQuant controls kv_bits internally — reject caller override
    raise ValueError("Cannot set kv_bits when turbo_quant is enabled. "
                     "Configure kv_bits in turbo_quant experiment config instead.")
```

**Fix for P2-3/P2.2 (bool parsing):** Use explicit string check for `qjl_enabled`:
```python
qjl_raw = self._turbo_quant_cfg.get("qjl_enabled", False)
qjl_enabled = qjl_raw if isinstance(qjl_raw, bool) else str(qjl_raw).lower() in ("true", "1", "yes")
```

**Tests:**
- Smoke test: turbo_quant enabled, generate with test model produces coherent output
- Mutual exclusion: `kv_bits=4` + `turbo_quant.enabled=true` raises ValueError
- Layer restoration: after generate(), `model.model.layers[0].self_attn` is the original class

### Task 4: Benchmark integration (F4: Sylveste-keo)

**Files:** `server/benchmark_cli.py`, `server/benchmark.py`

Same as original plan with these fixes from review:

- Add `--kv-mode turbo_quant` flag
- Memory measurement: call `mx.eval()` on a dummy after generator exhaustion to force materialization, *then* read `mx.metal.get_peak_memory()` (not `get_active_memory()` — fixes P2-4)
- Add long-context prompts (2K, 4K tokens) to benchmark corpus for context-scaling measurement
- Report `kv_mode` in results; set `kv_bits` to the underlying native bits (e.g., 4) for consistency

### Task 5: Autoresearch scaffold (Sylveste-m0m)

**File:** `interlab-turboquant-tune.sh` (new, in interfere root)

Build the interlab benchmark script that the autoresearch campaign will invoke:

```bash
#!/usr/bin/env bash
# Autoresearch benchmark for TurboQuant
# Emits METRIC lines for interlab's py-bench-harness

cd "$(dirname "$0")"
export INTERFERE_EXP_TURBO_QUANT_ENABLED=true

# Mutation parameters (set by autoresearch via env vars)
export INTERFERE_EXP_TURBO_QUANT_KV_BITS="${TQ_KV_BITS:-4}"
export INTERFERE_EXP_TURBO_QUANT_QJL_ENABLED="${TQ_QJL_ENABLED:-false}"
export INTERFERE_EXP_TURBO_QUANT_JL_DIM="${TQ_JL_DIM:-64}"

# Run benchmark and extract metrics
result=$(uv run python -m server.benchmark_cli \
    --model "${TQ_MODEL:-mlx-community/Qwen2.5-0.5B-Instruct-4bit}" \
    --kv-mode turbo_quant \
    --max-tokens 200 \
    --json 2>/dev/null)

# Emit interlab METRIC lines
echo "$result" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(f'METRIC kv_memory_bytes {d.get(\"kv_memory_delta_bytes\", 0)}')
print(f'METRIC tok_per_s {d.get(\"median_tok_per_s\", 0)}')
print(f'METRIC ttft_ms {d.get(\"median_ttft_ms\", 0)}')
"
```

**Mutation space for autoresearch:**
- `TQ_KV_BITS`: 2, 4, 8 (native quantization level under polar transform)
- `TQ_QJL_ENABLED`: true/false
- `TQ_JL_DIM`: 32, 64, 128
- `TQ_MODEL`: test model for quick iteration

**Kill criteria (from Sylveste-m0m):** 10 experiments with no memory reduction at iso-quality.

## Execution Order

```
Task 1 (polar primitives) → Task 3 (wrapper + integration) → Task 4 (benchmark)
                                                                    ↓
Task 2 (QJL, can parallel with 3)                          Task 5 (autoresearch scaffold)
```

Task 1 is foundation. Task 3 depends on 1. Task 2 can run in parallel with 3. Task 4 depends on 3. Task 5 depends on 4.

## What Autoresearch Will Answer

1. **Does polar transform improve quantization quality?** Compare `kv_bits=4` (baseline) vs `kv_bits=4 + polar transform` on Qwen3.5. If MSE/perplexity is the same or worse, polar transform doesn't help and we kill the experiment.
2. **Does QJL add enough quality?** Toggle `qjl_enabled` — if the improvement is <5%, the storage overhead isn't worth it.
3. **What native bit depth is optimal?** Test kv_bits=2,4,8 with polar transform. If polar+kv2 matches vanilla kv4, that's a 2x win.
4. **Throughput impact:** The polar transform adds trig ops per token. Measure whether it's <5% overhead.

## Kill Criteria (Revised)

- If polar_transform + kv4 has higher MSE than vanilla kv4: polar transform hurts, not helps
- If throughput drops >10% vs vanilla kv4: trig overhead too high for M5 Max
- If autoresearch runs 10 mutations with no improvement over vanilla kv_bits=2: the entire approach is not useful for this hardware
