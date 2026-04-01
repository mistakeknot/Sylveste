---
artifact_type: cuj
stage: design
cuj_id: CUJ-02
title: Developer starts interfer and loads a model
---

# CUJ-02: Developer Starts interfer and Loads a Model

## Actor

**Human developer** -- a Sylveste contributor or user who wants to run local inference on their Apple Silicon Mac. They interact with interfer directly via CLI and HTTP, outside of the Clavain orchestration loop.

## Trigger

The developer wants to use local models for development work -- testing prompts, running inference experiments, or serving a model for other tools to consume via the OpenAI-compatible API.

## Preconditions

1. Apple Silicon Mac with sufficient unified memory (M5 Max 128 GB recommended; smaller configs supported with smaller models)
2. Python 3.12+ installed with `uv` available
3. MLX and mlx-lm installed in the interfer virtual environment
4. Network access to download model weights from HuggingFace (first run only; cached thereafter)
5. No other process bound to port 8421

## Steps

1. **Start the server.** The developer launches interfer:
   ```
   uv run python -m interfer.server
   ```
   The Starlette HTTP server starts on `localhost:8421`. The MetalWorker subprocess is spawned with `multiprocessing.get_context("spawn")`, establishing the Metal GPU context in isolation. The default memory limit is set to 96 GiB (`mx.metal.set_memory_limit`), leaving headroom for the OS and HTTP process on a 128 GB machine.

2. **Check server health.** The developer verifies the server is running:
   ```
   curl http://localhost:8421/health
   ```
   Expected response:
   ```json
   {"status": "ready", "models": []}
   ```
   The empty models list confirms the server is up but no model is loaded yet. If running in dry-run mode, status will be `"dry_run"`.

3. **Pull a model.** The developer downloads model weights if not already cached. For the target model (Qwen3-30B Q4_K_M), this is a one-time download of approximately 18 GB:
   ```
   huggingface-cli download mlx-community/Qwen3-30B-A3B-4bit
   ```
   Weights are cached in `~/.cache/huggingface/hub/`. Subsequent loads are instant.

4. **Load the model.** The developer requests model loading via the interfer API (or the model loads lazily on first inference request). The ModelRegistry checks the memory budget:
   - Estimated model size (~18 GB for Q4_K_M of a 30B model) is validated against `available_memory_bytes`
   - If the budget allows, the model is registered and the InferenceEngine calls `mlx_lm.load()` inside the Metal worker subprocess
   - `mx.eval(model.parameters())` forces weight materialization so TTFT is not inflated by lazy loading

5. **Verify with a test completion.** The developer sends a test request:
   ```
   curl -X POST http://localhost:8421/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{
       "model": "mlx-community/Qwen3-30B-A3B-4bit",
       "messages": [{"role": "user", "content": "Write a Python hello world"}],
       "stream": true
     }'
   ```
   The server returns SSE-streamed token chunks in OpenAI-compatible format (`ChatCompletionChunk`). Each chunk contains a delta with content text. The stream ends with `finish_reason: "stop"` followed by `[DONE]`.

6. **Check health endpoint with loaded model.** The developer re-checks health:
   ```
   curl http://localhost:8421/health
   ```
   Expected response now includes the loaded model:
   ```json
   {"status": "ready", "models": ["mlx-community/Qwen3-30B-A3B-4bit"]}
   ```
   The model is now serving and available for completions requests from any client that speaks the OpenAI API format.

## Success Criteria

- Server starts without errors and binds to port 8421
- Metal worker subprocess is alive and reports ready status via health check
- Model loads within the memory budget (no MemoryError)
- Streaming completions return coherent text in OpenAI-compatible SSE format
- Health endpoint accurately reflects server state and loaded models
- The developer can point any OpenAI-compatible client (Clavain, aider, continue.dev, custom scripts) at `localhost:8421` and get completions

## Failure Modes

| Failure | Detection | Recovery |
|---------|-----------|----------|
| **Port 8421 already in use** | Server fails to bind on startup with `OSError: [Errno 48] Address already in use` | Kill the existing process on port 8421, or configure interfer to use a different port |
| **MLX not installed** | ImportError when Metal worker subprocess starts | Install MLX: `uv pip install mlx mlx-lm` |
| **Insufficient memory for model** | ModelRegistry raises MemoryError: loading exceeds budget | Choose a smaller model (e.g., 7B instead of 30B), or adjust memory_budget_bytes. Unload other models if any are loaded. |
| **Model not found / download fails** | `mlx_lm.load()` raises FileNotFoundError or network error | Verify model name matches HuggingFace hub. Check network connectivity. Use `huggingface-cli download` to pre-cache. |
| **Metal worker fails to spawn** | `MetalWorker.start()` raises; `is_alive()` returns False | Check that no other process holds the Metal context. Restart interfer. On rare occasions, a reboot is needed if Metal is in a bad state. |
| **Thermal throttle during load** | Model loading is slow; ThermalMonitor shows heavy pressure | Wait for thermal pressure to subside. Model loading is a one-time cost; generation performance will recover once thermal state is nominal. |
| **Non-Apple-Silicon platform** | ThermalMonitor raises RuntimeError; MLX import fails | interfer requires Apple Silicon. For non-Mac development, use dry-run mode (`--dry-run`) which returns synthetic responses without MLX. |

## Related Features

- **MetalWorker** (`server/metal_worker.py`) -- subprocess lifecycle and Metal memory limit enforcement
- **InferenceEngine** (`server/inference.py`) -- model loading via `mlx_lm.load()` and `stream_generate`
- **ModelRegistry** (`server/models.py`) -- memory budget tracking and loaded model inventory
- **ThermalMonitor** (`server/thermal.py`) -- thermal state awareness during operation
- **Starlette app** (`server/main.py`) -- HTTP endpoints: `/health`, `/v1/chat/completions`
- **ChatCompletionChunk** (`server/schema.py`) -- OpenAI-compatible streaming response schema
- **Dry-run mode** -- synthetic responses for development/testing without MLX hardware
