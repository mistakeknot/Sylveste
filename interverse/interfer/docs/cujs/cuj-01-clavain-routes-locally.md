---
artifact_type: cuj
stage: design
cuj_id: CUJ-01
title: Clavain routes a C2 coding task to interfer
---

# CUJ-01: Clavain Routes a C2 Coding Task to interfer

## Actor

**Clavain orchestrator** -- the L2 OS component that owns sprint execution and task routing. Clavain decides which model handles each task based on complexity tier, privacy classification, and confidence requirements.

## Trigger

A C2-complexity coding task arrives during sprint execution. C2 tasks are moderate-complexity work (refactoring, test writing, documentation generation) that do not require frontier-model reasoning. Clavain's routing engine evaluates this task against Track B5 (local inference via interfer) and determines it is a candidate for local execution.

## Preconditions

1. interfer server is running on `localhost:8421` and reports `status: ready` on `/health`
2. A model is loaded in the Metal worker (e.g., Qwen3-30B Q4_K_M, ~18 GB in unified memory)
3. Clavain's `routing.yaml` has Track B5 enabled (mode: `shadow` or `enforce`)
4. Thermal state is nominal or moderate (not heavy/trapping/sleeping)
5. The priority request queue has capacity (depth < max_depth of 64)
6. interspect canary system is initialized for local model evidence collection

## Steps

1. **Complexity classification.** Clavain's task classifier assigns the incoming task complexity C2 (moderate). The classifier uses heuristics: file count, diff size, presence of cross-module references, and language complexity.

2. **Track B5 resolution.** Clavain's routing engine checks Track B5 eligibility. It evaluates:
   - Complexity tier: C2 is within the local-eligible range (C1/C2)
   - Privacy classification: the task's code is classified (public/internal/sensitive). Sensitive code is forced local regardless of complexity.
   - Model availability: queries interfer `/health` to confirm a suitable model is loaded
   - Thermal state: interfer reports thermal pressure via its health response

3. **interfer API call.** Clavain sends a POST to `localhost:8421/v1/chat/completions` with:
   - `model`: the loaded model identifier (e.g., `mlx-community/Qwen3-30B-A3B-4bit`)
   - `messages`: the chat-formatted coding prompt
   - `stream`: true (SSE streaming)
   - `max_tokens`: appropriate for the task type
   - Request is enqueued in the PriorityRequestQueue with priority based on sprint urgency

4. **Streaming response.** The Metal worker subprocess receives the request via multiprocessing.Queue, runs `InferenceEngine.generate()` using `mlx_lm.stream_generate`, and streams tokens back. The main Starlette process converts these into SSE `data:` frames using the `ChatCompletionChunk` schema (OpenAI-compatible format). Clavain consumes the stream incrementally.

5. **Quality check.** After the response completes:
   - Clavain applies its standard quality heuristics (syntax validation, test execution if applicable)
   - If Track B5 is in shadow mode: Clavain also sends the same task to the cloud model and compares outputs. The local result is discarded but the comparison is recorded.
   - If Track B5 is in enforce mode: the local result is used directly. If confidence is too low (per the EarlyExitHook's confidence signal or Clavain's own quality check), Clavain cascades to the cloud model ("Fail to Cloud, Not to Silence").

6. **interspect evidence recorded.** The quality comparison (local vs cloud, or local standalone metrics) is logged as interspect evidence. This feeds the ongoing measurement of whether local inference maintains quality parity with cloud for C2 tasks. Evidence includes: task ID, complexity tier, model used, tok/s, TTFT, quality score, and whether cascade was triggered.

## Success Criteria

- The C2 task completes with output generated entirely by the local model on Apple Silicon
- No quality regression compared to cloud baseline (interspect evidence shows >95% match rate)
- End-to-end latency (TTFT + generation) is acceptable for the task type
- Zero cloud API calls consumed for this task (in enforce mode)
- interspect evidence is recorded with full provenance (model, quantization, thermal state, tok/s)

## Failure Modes

| Failure | Detection | Recovery |
|---------|-----------|----------|
| **Model not loaded** | `/health` returns empty models list or `status: dry_run` | Clavain skips Track B5, routes to cloud. Logs routing decision for ops visibility. |
| **Confidence too low** | EarlyExitHook reports low confidence; Clavain quality check fails | Cascade to cloud model. Record the local attempt as interspect evidence (quality=fail, cascade=true). |
| **Thermal throttle** | ThermalMonitor reports `heavy`, `trapping`, or `sleeping` (raw_value >= 2) | Clavain suspends Track B5 routing until thermal state returns to nominal/moderate. In-flight requests complete but new requests route to cloud. |
| **Queue backpressure** | PriorityRequestQueue raises QueueFullError (depth >= 64) | Clavain receives HTTP 503 or equivalent, routes to cloud. Alerts ops if sustained. |
| **Metal worker crash** | MetalWorker.is_alive() returns False; health check times out | Clavain marks Track B5 unavailable. interfer attempts worker restart. All pending requests cascade to cloud. |
| **OOM in unified memory** | ModelRegistry.load() raises MemoryError; Metal memory limit exceeded | Model load rejected. Clavain routes to cloud. Operator may need to unload models or adjust memory_budget_bytes. |
| **Network timeout** | Clavain's HTTP client times out waiting for interfer response | Cascade to cloud. Record timeout event for latency monitoring. |

## Related Features

- **Track B5 routing** (Clavain `routing.yaml`) -- the routing tier that enables local inference
- **PriorityRequestQueue** (`server/queue.py`) -- backpressure and priority ordering for inference requests
- **MetalWorker** (`server/metal_worker.py`) -- subprocess isolation for the Metal GPU context
- **InferenceEngine** (`server/inference.py`) -- MLX-LM wrapper with `stream_generate`
- **EarlyExitHook** (`server/experiments/early_exit.py`) -- entropy-based confidence signal
- **ThermalMonitor** (`server/thermal.py`) -- macOS thermal pressure reading via notify API
- **ModelRegistry** (`server/models.py`) -- memory budget enforcement for loaded models
- **ChatCompletionChunk** (`server/schema.py`) -- OpenAI-compatible SSE response format
- **interspect evidence** -- quality tracking for local vs cloud model comparison
