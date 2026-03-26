# interfere — Development Guide

Local MLX-LM inference server for Apple Silicon. Interverse companion plugin for Demarch/Clavain.

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
cd interverse/interfere
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
- `mode: off` (default) — no local routing
- `mode: shadow` — log what would route locally
- `mode: enforce` — route eligible tasks to interfere

Complexity-to-model mapping:
- C1 (trivial) -> local:qwen3-8b
- C2 (routine) -> local:qwen3-30b
- C3+ -> confidence cascade (try local, escalate if confidence < 0.6)

Safety floors: fd-safety and fd-correctness always use cloud models.

## Experiments

Each experiment is toggled via config and tracked through interlab campaigns.

### Early Exit (Experiment 1)
- `server/experiments/early_exit.py` — EarlyExitHook
- Skips remaining transformer layers when confidence > threshold
- Expected: 1.3x speedup on routine code generation
- Monitor: `hook.exit_rate` property

### Reservoir Routing (Experiment 3)
- `server/experiments/reservoir_routing.py` — ReservoirReadout
- 262K-param MLP on frozen layer-24 hidden states
- Classifies task type for model selection
- Training: 200-500 examples per routing class

## Testing

```bash
cd interverse/interfere
uv run pytest tests/ -v
```

## Memory Budget (128GB M5 Max)

```
~10GB:  macOS + system
~52GB:  Primary model (72B Q6_K)
~18GB:  Secondary model (30B Q4_K_M)
~5GB:   Draft model (8B Q4)
~43GB:  KV cache pool (Q8K/Q4V)
```

## Dependencies

- mlx >= 0.22.0
- mlx-lm >= 0.22.0
- starlette >= 0.40.0
- uvicorn >= 0.32.0
