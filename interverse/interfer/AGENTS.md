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

Complexity-to-model mapping (MoE-first, updated 2026-03-26):
- C1 (trivial) → `local:qwen3.5-9b-4bit` (~5GB, ~60-80 tok/s)
- C2 (routine) → `local:qwen3.5-35b-a3b-4bit` (~18GB, MoE 3B active, ~86 tok/s benchmarked)
- C3 (moderate) → `local:qwen3.5-122b-a10b-4bit` (~65GB, MoE 10B active, pending benchmark)

MoE models activate only a fraction of parameters per token (e.g., 3B of 35B), giving
big-model quality at small-model inference speed.

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

### Flash-MoE Expert Cache Tuning

**Binary:** upstream 20f8591 + pread fix. Expert size: 7,077,888 bytes (4-bit).

Preliminary timing (batch mode, `--timing --tokens 10`):

| `--malloc-cache` | Cache GB | expert_io ms/layer | total ms/layer | tok/s |
|------------------|---------|-------------------|----------------|-------|
| 5000 | 35.4 | 2.410 | 6.526 | 2.5 |
| 10000 | 70.8 | 3.566 | 7.208 | 2.3 |

**Recommended: `--flashmoe-malloc-cache 5000`** — 35GB cache gives better throughput
than 10000 (70GB) due to unified memory contention with Metal GPU buffers. Full sweep pending.

Previous benchmark (Q3 hybrid, pre-upstream merge) is **invalid** — the Q3 format read
5.4MB from 7.1MB experts, producing garbage output that inflated hit rates and throughput.

**CLI changes after upstream merge:** `--q3-experts` removed. Use explicit
`--weights`/`--manifest`/`--vocab` paths (--model alone doesn't resolve them).

## Dependencies

- mlx >= 0.22.0
- mlx-lm >= 0.22.0
- starlette >= 0.40.0
- uvicorn >= 0.32.0
