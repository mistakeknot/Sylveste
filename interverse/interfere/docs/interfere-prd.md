---
artifact_type: prd
stage: design
---

# interfere -- Product Requirements Document

**Version:** 0.1.0
**Date:** 2026-03-26
**Owner:** Demarch / Interverse

## 1. Problem Statement

Demarch agents (orchestrated by Clavain) depend entirely on cloud LLM APIs for inference. This creates three structural problems:

1. **Cost at scale.** Multi-agent workflows (subagents, review agents, routing decisions) generate thousands of API calls per session. At cloud pricing, routine C1/C2 tasks that don't need frontier models still cost frontier prices.
2. **Privacy leakage.** Sensitive code (.env-adjacent files, internal APIs, credentials handling) is sent to third-party endpoints. There is no mechanism to keep private code local.
3. **Latency and availability.** Cloud round-trips add latency to every agent action. Outages and rate limits halt all agent work simultaneously.

The M5 Max with 128GB unified memory is the inflection point where local models can match cloud quality for 60-70% of coding tasks at zero marginal cost. interfere is the inference layer that makes this real -- a custom MLX-LM server that owns the full computation pipeline, enabling optimizations (early exit, reservoir routing, thermal scheduling) impossible in off-the-shelf serving frameworks.

## 2. Users and Personas

### Clavain Orchestrator (primary)
The autonomous routing layer that decides which model handles which task. Clavain needs an OpenAI-compatible endpoint it can route to via Track B5, with confidence scores to drive cascade decisions (try local, escalate to cloud if confidence < threshold). Clavain never interacts with interfere's internals -- only the API contract matters.

### Human Developer (secondary)
The person running Demarch on their Mac. They care about: the system not crashing their machine (OOM kernel panics), not throttling due to thermal pressure, and seeing cost savings vs cloud. They interact via health endpoints, cost dashboards, and thermal status. They may also curl the endpoint directly for ad-hoc local inference.

### Experiment Researcher (tertiary)
The developer designing and running interlab campaigns on the inference pipeline. They need experiment hooks that can be toggled independently, clear before/after metrics, and kill criteria enforcement. They interact via interlab campaign configs and experiment toggle flags.

## 3. Features

### F1: OpenAI-Compatible Local Inference Server

Serve local MLX models through a standard `/v1/chat/completions` endpoint with SSE streaming. Any client that speaks OpenAI protocol can use interfere as a drop-in backend.

**Requirements:**
- POST `/v1/chat/completions` with streaming (SSE) and non-streaming responses
- GET `/health` returning loaded models, memory usage, queue depth, thermal state
- Model addressed as `local:<model-name>` (e.g., `local:qwen3-30b`)
- Starlette HTTP main process with Metal subprocess via `multiprocessing.Queue` (spawn context)
- Priority request queue with backpressure (reject when queue full)
- Port 8421 (default), configurable

**Acceptance criteria:**
- `curl localhost:8421/v1/chat/completions` returns streaming tokens from a loaded model
- Baseline benchmark: measure tok/s, TTFT on 100 representative coding tasks

### F2: Clavain Track B5 Integration

Enable Clavain to route tasks to interfere based on complexity tier, confidence, and privacy classification.

**Requirements:**
- Track B5 modes: `off` (no local routing), `shadow` (log decisions only), `enforce` (route eligible tasks)
- Complexity-to-model mapping: C1 -> local:qwen3-8b, C2 -> local:qwen3-30b, C3+ -> confidence cascade
- Confidence cascade: attempt local inference, escalate to cloud if confidence < 0.6
- Privacy routing dimension: classify tasks as public/internal/sensitive; sensitive tasks must stay local regardless of quality tradeoffs
- Safety floors: fd-safety and fd-correctness agents always use cloud models
- Return confidence metadata in response headers for cascade decisions

**Acceptance criteria:**
- Shadow mode: Clavain routing logs show local-vs-cloud decisions for all C1/C2 tasks
- Enforce mode: 60%+ of C1/C2 tasks route locally
- Privacy: .env-adjacent code correctly classified and routed locally
- No quality regression on interspect evidence (>95% match rate vs cloud baseline)

### F3: Memory-Safe Model Management

Manage model loading, hot-swap, and memory budgets within the 128GB unified memory envelope without risking OOM kernel panics.

**Requirements:**
- `mx.metal.set_memory_limit(relaxed=False)` to enforce hard memory ceiling
- Model registry with per-model memory estimates (weights + KV cache projections)
- Memory budget enforcement: refuse to load a model that would exceed budget
- Hot-swap: unload current model and load replacement without server restart
- Memory budget allocation (128GB M5 Max): ~10GB OS, ~52GB primary (72B Q6_K), ~18GB secondary (30B Q4_K_M), ~5GB draft (8B Q4), ~43GB KV cache pool
- Graceful degradation: if memory pressure detected, shed lowest-priority models first

**Acceptance criteria:**
- Loading a model that exceeds remaining budget returns an error, not a crash
- Hot-swap completes in < 30 seconds for a 30B Q4_K_M model
- No kernel panics from unbounded KV cache growth under sustained load

### F4: Thermal-Aware Scheduling

Monitor Apple Silicon thermal state and adjust inference behavior to prevent throttling and maintain consistent performance.

**Requirements:**
- Thermal monitoring via macOS `IOKit` notify API (no sudo required)
- Thermal states: nominal, fair, serious, critical
- Scheduling policy: at `serious`, reduce batch size and insert cooling delays; at `critical`, pause inference and drain queue to cloud
- Expose thermal state in `/health` endpoint
- Log thermal transitions for capacity planning

**Acceptance criteria:**
- Thermal state correctly reported in health endpoint under load
- At `critical` thermal state, requests drain to cloud (no local inference attempted)
- No sustained thermal throttling during normal multi-agent workloads

### F5: Experiment Hooks

Provide insertion points in the inference pipeline for research techniques, each independently toggleable and measurable through interlab campaigns.

**Requirements:**
- Early exit hook: entropy-based confidence check at intermediate layers; skip remaining layers when confidence exceeds threshold. Target: 1.3x tok/s speedup without quality regression.
- Reservoir routing readout: 262K-param MLP on frozen layer-24 hidden states for task classification. Training corpus: 200-500 examples per routing class.
- Speculative decoding hook: draft model (3B/8B) generates candidates, primary model verifies. Target: 1.8x speedup with 65%+ acceptance rate.
- Each hook: toggle on/off via config, report metrics (exit rate, acceptance rate, classification accuracy), define kill criterion
- Hooks compose independently -- a failure in one must not affect others

**Acceptance criteria:**
- Each hook can be enabled/disabled without server restart
- interlab campaign dashboards show before/after metrics for each hook
- Kill criteria enforced: hooks auto-disable if metrics fall below threshold

### F6: KV Cache Persistence and Warming

Persist KV cache state across requests and sessions to reduce time-to-first-token for recurring contexts (system prompts, project context).

**Requirements:**
- In-memory KV cache pool with configurable size (default: 43GB allocation)
- Cache keyed on system prompt hash + conversation prefix
- Quantized KV: Q8 for keys, Q4 for values to maximize cache capacity
- Future: two-tier cache (RAM hot tier + SSD warm tier) for session persistence
- Cache eviction: LRU with priority boost for high-frequency system prompts

**Acceptance criteria:**
- Second request with identical system prompt shows measurable TTFT reduction vs cold start
- Cache respects memory budget -- evicts entries before exceeding allocation
- Quantized KV produces no measurable quality regression vs full-precision KV

## 4. Non-Goals

interfere explicitly does NOT:

- **Replace cloud models for complex tasks.** C3+ tasks, novel architecture decisions, and safety-critical reviews stay on cloud frontier models. interfere handles the volume, not the ceiling.
- **Support non-Apple hardware.** MLX is Apple Silicon only. No CUDA, no ROCm, no CPU fallback. If you don't have an M-series Mac, interfere is not for you.
- **Serve multiple users.** This is a single-machine, single-developer inference server. No multi-tenancy, no auth, no rate limiting beyond backpressure.
- **Train or fine-tune models.** interfere serves inference. Training, fine-tuning, and adapter optimization are out of scope (future: adapter hot-loading may be added).
- **Compete with Ollama/vllm-mlx for general use.** interfere exists because those tools don't expose the hooks needed for early exit, reservoir routing, and thermal scheduling. If the community adds these features, interfere may simplify or deprecate.
- **Provide a UI.** All interaction is API-first. Dashboards (cost, thermal, experiments) are consumed by other Demarch components, not rendered by interfere.

## 5. Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Local routing rate | 60%+ of C1/C2 tasks | Clavain routing logs in enforce mode |
| Tokens per second (30B Q4_K_M) | >= 40 tok/s | Benchmark suite on 100 coding tasks |
| Time to first token | < 200ms (warm cache) | Health endpoint + benchmark suite |
| Quality match rate | > 95% vs cloud baseline | interspect canary evidence |
| Cost reduction | > 50% vs all-cloud | Cost tracking dashboard ($/task local vs cloud) |
| OOM incidents | 0 kernel panics | System logs over 30-day window |
| Thermal throttle events | < 5% of inference time | Thermal monitor logs |
| Early exit speedup | 1.3x tok/s | interlab campaign (Experiment 1) |
| Speculative decoding speedup | 1.8x tok/s | interlab campaign (Experiment 2) |

## 6. Dependencies

| Dependency | Role | Version |
|------------|------|---------|
| **MLX** | Apple Silicon ML framework, Metal backend | >= 0.22.0 |
| **mlx-lm** | Model loading, tokenization, `stream_generate` | >= 0.22.0 |
| **Starlette** | HTTP framework for API server | >= 0.40.0 |
| **uvicorn** | ASGI server | >= 0.32.0 |
| **Clavain** | Orchestrator -- routing decisions, Track B5 config | `os/Clavain/config/routing.yaml` |
| **interspect** | Quality evidence -- canary system for local model quality | Evidence API |
| **interlab** | Experiment platform -- campaign management, metrics, kill criteria | Campaign API |
| **interrank** | Model benchmarking -- registers local models in AgMoDB snapshot | Leaderboard API |
| **macOS IOKit** | Thermal monitoring (notify API, no sudo) | macOS 15+ |
| **Apple Silicon M-series** | Unified memory architecture, Metal GPU | M1 Pro+ (optimized for M5 Max 128GB) |

### Critical Constraint

MLX does not support concurrent inference (`ml-explore/mlx#3078`). All requests are serialized through a priority queue. If this limitation is not resolved by H2 2026, multi-agent throughput will be capped, limiting interfere's value for parallel subagent workloads.
