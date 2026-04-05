# interfer — Development Guide

Local MLX-LM inference server for Apple Silicon. Interverse companion plugin for Sylveste/Clavain.

## Architecture

```
Main Process (Starlette/uvicorn)
  ├── GET  /health
  ├── POST /v1/chat/completions (OpenAI-compatible SSE)
  └── PriorityRequestQueue
        └── multiprocessing.Queue (spawn context)
              └── Metal Subprocess
                    ├── InferenceEngine (mlx-lm stream_generate)
                    ├── ModelRegistry (memory budget)
                    └── ThermalMonitor (macOS notify API)

Experiment Hooks (inside Metal subprocess):
  ├── EarlyExitHook — entropy-based layer skipping
  └── ReservoirReadout — frozen-layer task classification MLP
```

### Key Design Constraints

- **Spawn, not fork**: `multiprocessing.get_context("spawn")` — fork causes Metal GPU semaphore leaks on macOS
- **Memory safety**: `mx.metal.set_memory_limit(relaxed=False)` prevents kernel panics from unbounded KV growth
- **Cannot cancel mid-forward-pass**: cooperative cancellation between generate_step iterations (~20ms for 30B)
- **No concurrent MLX inference**: ml-explore/mlx#3078 — we use a priority queue with sequential processing

## Server Startup

```bash
cd interverse/interfer
uv run python -m server              # starts on port 8421 (MLX inference)
uv run python -m server --dry-run    # dry-run mode (fake tokens, no MLX)
uv run python -m server --port 9000  # custom port
```

## API

### GET /health
Returns server status, loaded models, memory usage.

### POST /v1/chat/completions
OpenAI-compatible streaming endpoint. Accepts standard chat completion requests.

```bash
curl http://localhost:8421/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "local:qwen3-30b", "messages": [{"role": "user", "content": "Hello"}], "stream": true}'
```

## Clavain Integration

Track B5 in `os/Clavain/config/routing.yaml`:
- `mode: off` — no local routing
- `mode: shadow` (current) — log what would route locally
- `mode: enforce` — route eligible tasks to interfer

Complexity-to-model mapping (MoE-first, updated 2026-04-05):
- C1 (trivial) → `local:qwen3.5-9b-4bit` (~5GB, ~60-80 tok/s)
- C2 (routine) → `local:qwen3.5-35b-a3b-4bit` (~18GB, MoE 3B active, ~86 tok/s benchmarked)
- C3 (moderate) → `flash-moe:qwen3.5-397b` (Q3+cis4, ~1 tok/s SSD-streamed) OR cloud escalation

MoE models activate only a fraction of parameters per token (e.g., 3B of 35B), giving
big-model quality at small-model inference speed.

Note: Qwen3.5-122B-A10B-4bit was benchmarked at 2.99 tok/s (2026-04-05) but
consumes 69GB RAM, preventing model coexistence. The 397B via flash-moe gives
equivalent quality at ~6GB RAM. See docs/benchmarks/2026-04-05-qwen35-122b-a10b.md.

Safety floors: fd-safety and fd-correctness always use cloud models.

## Experiments

Each experiment is toggled via config and tracked through interlab campaigns.

### Early Exit (Experiment 1)
- `server/experiments/early_exit.py` — EarlyExitHook
- Skips remaining transformer layers when confidence > threshold
- Expected: 1.3x speedup on routine code generation
- Monitor: `hook.exit_rate` property

### KV Cache Quantization (Experiment 2 — complete)
- `kv_bits` param plumbed through InferenceEngine → MetalWorker → HTTP endpoint → benchmark_cli
- Benchmarked on Qwen3.5-35B at 100 and 500 tokens
- kv_bits=8: **free lunch** — no throughput penalty, 2x KV memory reduction
- kv_bits=4: ~5% cost, 4x KV memory reduction, recommended for 122B+
- kv_bits=2: ~7% cost, 8x KV memory reduction, quality identical at 500 tokens
- Full results: `docs/benchmarks/20260326-*-kv*.json`

### Reservoir Routing (Experiment 3)
- `server/experiments/reservoir_routing.py` — ReservoirReadout
- 262K-param MLP on frozen layer-24 hidden states
- Classifies task type for model selection
- Training: 200-500 examples per routing class

## Testing

```bash
cd interverse/interfer
uv run pytest tests/ -v
```

## Memory Budget (128GB M5 Max)

```
~10GB:  macOS + system
~32GB:  Primary model — Nemotron-Cascade-2-30B-A3B 8-bit (MoE, 3B active)
~18GB:  Secondary model — Qwen3.5-35B-A3B 4-bit (MoE, 3B active)
~5GB:   Draft model — Qwen3.5-9B-OptiQ 4-bit
~63GB:  KV cache pool + headroom
```

Alternative high-end layout (when running gpt-oss-120b):
```
~10GB:  macOS + system
~60GB:  Primary model — gpt-oss-120b MXFP4-Q8
~5GB:   Draft model — Qwen3.5-9B-OptiQ 4-bit
~53GB:  KV cache pool + headroom
```

Flash-MoE layout (Qwen3.5-397B-A17B via flash-moe binary):
```
~10GB:  macOS + system
~6GB:   Model weights (mmap'd, 5.52GB)
~35GB:  Expert cache — --malloc-cache 5000 (recommended, 7.1MB × 5000)
~0.5GB: Metal GPU buffers (KV cache, delta-net state, attention)
~76GB:  Remaining headroom
```

### Flash-MoE Configuration

**Binary:** Anemll/flash-moe m5-nax branch (commit 26cd7f8) + pread zero-init fix.

**Recommended: Q3 GGUF experts + cache-io-split 4** (best speed/quality tradeoff):

```bash
uv run python -m server \
  --flashmoe-binary ~/projects/flash-moe/metal_infer/infer \
  --flashmoe-model ~/Models/flash_mlx_4bit \
  --flashmoe-q3-experts \
  --flashmoe-cache-io-split 4 \
  --flashmoe-gguf-embedding ~/Models/flash_mlx_4bit/gguf/embedding_q8_0.bin \
  --flashmoe-gguf-lm-head ~/Models/flash_mlx_4bit/gguf/lm_head_q6.bin \
  --flashmoe-malloc-cache 5000 \
  --flashmoe-only
```

| Config | Decode | PPL | Expert size | Notes |
|--------|--------|-----|-------------|-------|
| Q3 GGUF + cache-io-split 4 | **12.9 tok/s** | 3.81 | 5.44 MB | Recommended |
| 4-bit MLX (previous) | 9.5 tok/s | 3.64 | 6.75 MB | ~36% slower |
| 4-bit + malloc-cache 5000 | 2.5 tok/s | 3.64 | 6.75 MB | Old config, obsolete |
| 2-bit MLX | 14.5 tok/s | 5.71 | 3.75 MB | Fast but PPL degrades |

**New CLI flags (m5-nax upstream):**
- `--flashmoe-q3-experts` — Use Unsloth IQ3_XXS experts (23% smaller, 36% faster)
- `--flashmoe-cache-io-split N` — Page-aligned pread fanout (4 recommended)
- `--flashmoe-gguf-embedding PATH` — Q8_0 embedding overlay (quality boost, free)
- `--flashmoe-gguf-lm-head PATH` — Q6_K LM head overlay (quality boost, free)

**GGUF overlay setup:** See `~/projects/flash-moe/docs/model-download-and-convert.md`
for extraction scripts. Q3 experts come pre-packed in `packed_experts_Q3/`.

## Dependencies

- mlx >= 0.22.0
- mlx-lm >= 0.22.0
- starlette >= 0.40.0
- uvicorn >= 0.32.0
