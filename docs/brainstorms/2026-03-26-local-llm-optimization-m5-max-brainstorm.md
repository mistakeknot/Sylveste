---
artifact_type: brainstorm
bead: none
stage: discover
---

# Local LLM Optimization for M5 Max 128GB

## What We're Building

**interfere** — a new interverse companion plugin (`interverse/interfere/`) that provides a custom MLX-LM-based local inference server for Demarch/Clavain, integrated into Clavain's routing system as Track B5 (local model routing). Each esoteric optimization technique is deployed as a monitored interlab experiment campaign.

The goal is to maximize the efficiency/quality frontier: route 60-70% of Clavain's subagent work to local models (cost dominance), eliminate rate limits for interactive work (latency independence), keep sensitive code off cloud APIs (privacy sovereignty), and progressively integrate cross-disciplinary inference techniques from the research frontier.

### Hardware Context

- Apple Silicon M5 Max, 128GB unified memory
- 614 GB/s memory bandwidth (40-core GPU)
- Neural Accelerators in every GPU core (3.3-4x faster prefill vs M4)
- This is the inflection point where 70B models at Q8 (near-lossless) fit in memory

### The Efficiency/Quality Frontier (March 2026)

| Tier | Model | Quant | Memory | tok/s | SWE-bench | Role |
|------|-------|-------|--------|-------|-----------|------|
| T0 (trivial) | Qwen3-8B | Q4_K_M | ~5GB | 80-100 | ~50% | FIM, autocomplete |
| T1 (routine) | Qwen3-30B-A3B | Q4_K_M | ~18GB | 35-50 | ~70% | Function gen, tests, small fixes |
| T2 (complex) | Qwen2.5-72B | Q6_K | ~52GB | 25-30 | ~75% | Multi-file, review, debugging |
| T3 (hard) | Claude Sonnet 4.6 | Cloud | - | 51 | ~76% | Agentic multi-step |
| T4 (frontier) | Claude Opus 4.6 | Cloud | - | 49 | ~76% | Architecture, research |

Key insight: T1 local (Qwen3-30B) matches Haiku quality at zero marginal cost. T2 local (72B at Q6_K) approaches Sonnet quality. The economics are compelling: local inference costs ~$2-3/MTok amortized vs Sonnet at $6/MTok.

## Why This Approach

### Architecture: interverse plugin (not Clavain-native, not new pillar)

**Chosen over**: Extending Clavain directly (B) or creating a new L2 pillar (A).

Rationale:
1. **Follows established pattern** — interspect, interrank, interlab are all companion plugins that Clavain delegates to. An inference server is a service, not an orchestration concern.
2. **MCP-native** — Plugin's MCP server exposes tools for model management, health checks, benchmarking. Clavain's dispatch calls interfere via its API, not through plugin MCP.
3. **Experiment integration** — interlab is already a plugin; interfere experiments use interlab campaigns directly.
4. **Clavain stays focused** — Clavain dispatches (which model for which task). interfere serves (how to run the model). Clean separation.

### Serving: Custom MLX-LM (not vllm-mlx, not Ollama, not LiteLLM)

**Chosen over**: LiteLLM + vllm-mlx (#1), Ollama (#2), multiple backends (#4).

Rationale:
1. **Full control of inference pipeline** — Esoteric techniques (early exit, speculative streaming, reservoir routing, thermal scheduling) require hooks inside the inference loop. vllm-mlx and Ollama are black boxes.
2. **Clavain's dispatch > LiteLLM** — Clavain already has 4-track task-aware routing with evidence-based calibration, safety floors, and complexity classification. LiteLLM is a dumb proxy by comparison. Adding it creates an unnecessary translation layer.
3. **MLX-LM is the fastest raw backend** — ~230 tok/s for 7B on Apple Silicon. No server overhead. We build exactly the serving layer we need.
4. **Concurrent inference** — MLX doesn't support native concurrent inference (ml-explore/mlx#3078). We build our own request queue with priority scheduling (interactive tool calls preempt batch generation).

### Economics first, experiments monitored

Every esoteric technique enters as an interlab experiment campaign with:
- Baseline measurement (current throughput/quality on the task class)
- Treatment (technique enabled)
- Success metric (tok/s improvement, quality maintenance, latency reduction)
- Kill criterion (quality regression > 2% on coding eval OR latency regression > 20%)

## Key Decisions

### 1. Clavain Integration: Track B5

Add `local_models` section to `routing.yaml`. Extend `_routing_model_tier()` in `lib-routing.sh` to recognize local model IDs. Extend `resolveModel()` in `compose.go` for local model recommendations.

Routing logic: Clavain's complexity classifier (C1-C5) maps to local model tiers:
- C1 (trivial) -> T0 local (8B)
- C2 (routine) -> T1 local (30B)
- C3+ -> confidence cascade: try T2 local (72B), measure first-3-token probability, escalate to cloud if < 0.7

Safety floors preserved: fd-safety and fd-correctness maintain `min_model: sonnet` — local models must demonstrate equivalent performance via interspect evidence before they're eligible.

### 2. Privacy Sovereignty

New routing dimension: `privacy_classification` on each task.
- `public` — any model (cloud or local)
- `internal` — local only, regardless of complexity
- `sensitive` — local only + no logging

Classification signals: presence of `.env` references, internal API patterns, credential-adjacent code, proprietary business logic keywords.

### 3. Confidence-Based Cascade (MCCom Pattern)

From the hybrid routing research (arXiv 2603.05974):
1. Run local model
2. Measure average probability of first 3 generated tokens
3. If probability > 0.8 AND prompt < 1500 tokens: accept local output
4. If probability 0.6-0.8: try larger local model (72B)
5. If probability < 0.6 OR multi-file context: escalate to cloud

This alone handles ~61% of requests locally in the research.

### 4. Model Memory Budget

128GB allocation strategy:
- ~10GB: macOS + system processes
- ~52GB: Primary model (72B at Q6_K) — always loaded
- ~18GB: Secondary model (30B at Q4_K_M) — loaded on demand, LRU evicted
- ~5GB: Draft model for speculative decoding (8B at Q4)
- ~43GB: KV cache pool (shared across models, quantized Q8 keys / Q4 values)

With quantized KV cache, this supports ~64-96k context for the primary model.

## Esoteric Experiment Roadmap

Each is an interlab experiment campaign on interfere:

### Experiment 1: Entropy-Based Early Exit (Near-term)
- **Source**: BEEM (ICLR 2025), arXiv 2412.01455
- **Hypothesis**: Skip 20-40% of transformer layers on high-confidence code tokens (identifiers, common keywords, boilerplate)
- **Metric**: tok/s improvement with quality maintenance (linter pass rate, test pass rate)
- **Implementation**: Attach lightweight confidence estimators at intermediate layers. If entropy at layer K < threshold tau, exit early.
- **Expected**: 1.3x wall-time speedup on routine code generation

### Experiment 2: Speculative Decoding with Draft Model (Near-term)
- **Source**: mlx-lm native `--draft-model` support; EAGLE-3 (NeurIPS '25)
- **Hypothesis**: Classic two-model speculative decoding (small draft + large verifier) accelerates generation with minimal quality loss
- **Metric**: tok/s vs baseline, acceptance rate on coding tasks, memory overhead of draft model
- **Implementation**: Use mlx-lm's native `--num-draft-tokens` with a 3B Q4 draft model (~2GB). Apple's Speculative Streaming and Mirror-SD are PyTorch-only and Mirror-SD requires separate GPU+NPU — NOT viable on single M5 Max.
- **Expected**: 1.8-2.5x speedup with 65%+ acceptance rate on code completion

### Experiment 3: Reservoir Routing (Medium-term)
- **Source**: arXiv 2507.15779, AIP Chaos 2025
- **Hypothesis**: Frozen first 6-8 layers of the smallest model serve as a reservoir computer for zero-cost task classification
- **Metric**: Routing accuracy vs. RouteLLM BERT classifier, with zero additional model load
- **Implementation**: Extract hidden state at layer 6, apply 2-layer MLP readout, route to appropriate specialist
- **Expected**: Semantic task classification for free (computation already happening in the model forward pass)

### Experiment 4: ACO Pheromone Routing (Medium-term)
- **Source**: AMRO-S (arXiv 2603.12933, March 2026)
- **Hypothesis**: Ant colony optimization self-organizes model routing without training. Pheromone matrix learns which specialist handles which task category.
- **Metric**: Routing quality vs. static rules, adaptation speed on new task types
- **Expected**: Self-organizing routing that adapts as project workload shifts

### Experiment 5: Thermal-Aware Scheduling (Medium-term)
- **Source**: TAPAS (ASPLOS 2025, arXiv 2501.02600)
- **Hypothesis**: Using `powermetrics` die temperature as a scheduling signal prevents thermal throttling
- **Metric**: Sustained throughput over 30-minute heavy inference session
- **Implementation**: When die temp > 85C, preemptively downshift to smaller model or increase batching
- **Expected**: 97% reduction in thermal throttling events (TAPAS datacenter numbers — Apple Silicon likely different)

### Experiment 6: Active Inference Prefetching (Research frontier)
- **Source**: arXiv 2509.05651, Free Energy Principle
- **Hypothesis**: Bayesian tracker over task-type sequences predicts which model will be needed next, pre-loads KV cache
- **Metric**: Cache hit rate, TTFT reduction for model switches
- **Expected**: Eliminate model cold-start latency for predictable task sequences (common in Clavain sprint loops)

### Experiment 7: Model Swarms / PSO Adapter Optimization (Research frontier)
- **Source**: ICML 2025, arXiv 2410.11163
- **Hypothesis**: PSO over LoRA adapter weight space finds combinations that outperform any single adapter
- **Metric**: Coding eval score vs best individual adapter
- **Expected**: "Diamond in the rough" effect — bottom-half adapters rise to top in 56.9% of searches

### Experiment 8: Hebbian KV Cache Warming (Speculative)
- **Hypothesis**: Reinforce recently useful context patterns in KV cache (instead of LRU eviction) for agent session reuse
- **Metric**: Cache hit rate for repeated context patterns in Clavain agent loops
- **Expected**: >40% improvement over LRU for repetitive agent workflows

## Open Questions

1. **MLX concurrent inference**: ml-explore/mlx#3078 tracks this. How do we handle concurrent subagent requests? Priority queue with head-of-line preemption? Or accept sequential processing with smart batching?

2. **Model selection**: Which specific models to start with? Qwen3-Coder series vs DeepSeek-Coder vs Llama 3.3? Need to benchmark on Clavain's actual task distribution, not generic coding evals.

3. **KV cache persistence**: Should we persist per-agent KV caches to SSD (oMLX pattern) for instant session resumption? Or is the cold-start cost acceptable for the memory savings?

4. **Interspect evidence threshold**: How many successful local completions before interspect auto-approves a local model for a task category? Current canary system expects ~50 observations for confidence.

5. **Apple Neural Engine**: M5 Max has neural accelerators in every GPU core. Can we offload embedding lookups or normalization layers to ANE while the GPU handles attention? No MLX API for this yet.

## Round 2 Implementation Research Findings (2026-03-26)

### Server Architecture (Confirmed)
- **Must use `multiprocessing.get_context("spawn")`** — fork causes Metal GPU semaphore leaks on macOS
- Pattern: Main process (Starlette HTTP) → spawned subprocess (Metal context) → inference ThreadPoolExecutor
- **Cannot cancel mid-forward-pass** — cooperative cancellation between `generate_step` iterations only (~20ms for 30B)
- `mx.compile(shapeless=True)` required or prefill recompiles on every sequence length
- Metal buffers are wired (non-pageable) — OOM causes kernel panic without `mx.metal.set_memory_limit(relaxed=False)`

### Early Exit (Zero Training Required)
- Reuse the model's own LM head at intermediate layers — Qwen3 uses `tie_word_embeddings=True` so `embed_tokens.as_linear()` gives free projection
- 88.9% of tokens do NOT need the final layer; average exit at 72% depth
- Monkey-patch `LlamaModel.__call__` — no fork of mlx-lm needed
- Check every 4 layers starting at 25% depth; ~0.4ms per check on M5 Max; break-even at ~1-2% of layer cost
- Per-layer thresholds required; calibrate with 500-2000 code completions

### Reservoir + ACO Routing (Concrete Numbers)
- Qwen3-8B: hidden_dim=4096, 36 layers. Best tap: layer 24 (~67% depth)
- MLP readout: 262K params (4096→64→K), <0.1ms, zero extra compute if model already running
- Training: 200-500 examples per class, use Clavain's routing decisions as labels
- ACO pheromone: ~432 floats, serialize as JSON, Thompson sampling cold start until 20+ observations

### Thermal Monitoring
- No-sudo path: `notify_register_check("com.apple.system.thermalpressurelevel")` — zero overhead, 5 levels
- For actual temperatures: compiled IOKit helper or sudoers entry for powermetrics
- Use notify API for detection, poll powermetrics only when Moderate+

### KV Cache (Critical Updates)
- KV serialization works natively via safetensors: `save_prompt_cache()` / `load_prompt_cache()` — 500ms reload
- oMLX has block-level SSD paging with LRU eviction and CoW prefix sharing (90s → 1s TTFT)
- **mlx-lm prefix caching broken** for sliding-window and hybrid models (Qwen 3.5, Gemma 3)
- SnapKV/CAKE are closest to Hebbian warming (attention-frequency scores) — neither ported to MLX
- KV quantization must be online (during generation), not post-hoc. Q8K/Q4V = 59% memory reduction

### Speculative Decoding (Reality Check)
- Apple's Speculative Streaming: PyTorch-only, no MLX port
- Mirror-SD: requires separate GPU+NPU — NOT viable on single M5 Max chip
- EAGLE-3: PyTorch-only, no MLX port, needs tree attention kernel
- **What works on MLX today**: Classic two-model draft+verifier via mlx-lm `--draft-model`

### New Esoteric Experiments from Round 2
- **Experiment 9: Compression-Ratio Routing** — gzip on prompt (~0.1ms) as zero-shot complexity signal. DeepMind proved LLM quality = compression. Nobody has published this as routing. Novel.
- **Experiment 10: MInference Sparse Attention** — per-head sparse patterns (NeurIPS 2024), 95% FLOP reduction in attention, 10x on long context
- **Experiment 11: KVFlow Stigmergic Prefetch** — predict next agent from workflow graph, pre-load KV (NeurIPS 2025). 15x throughput with LMCache
- **Experiment 12: Activation Steering for NL→Code Priming** — inject structural reasoning vectors from NL description into code gen. MAPS + activation steering (ACL 2024). Components proven, combination novel.
- **Experiment 13: Allostatic Load Monitoring** — EWMA of (throttle events + OOM near-misses + cache eviction rate) per model instance. Swap degraded instances proactively.

## Research Sources

### MLX / Apple Silicon
- Apple ML Research: "Exploring LLMs with MLX and the Neural Accelerators in the M5 GPU"
- arXiv 2510.18921: Benchmarking On-Device ML on Apple Silicon with MLX
- arXiv 2601.19139: Native LLM Inference at Scale on Apple Silicon
- arXiv 2511.05502: Comparative Study of MLX, MLC-LLM, Ollama, llama.cpp

### Speculative Decoding
- Apple ML Research: Recurrent Drafter, Speculative Streaming, Mirror Speculative Decoding
- arXiv 2503.01840: EAGLE-3 (NeurIPS '25)
- PEARL: Parallel Speculative Decoding (ICLR 2025)

### Hybrid Routing
- arXiv 2406.18665: RouteLLM (ICLR 2025)
- arXiv 2603.05974: MCCom — Local-Cloud Model Cascading for Code Completion
- arXiv 2603.04445: Dynamic Model Routing and Cascading Survey
- arXiv 2411.05276: GPT Semantic Cache

### Esoteric / Cross-Disciplinary
- BEEM: Boosting Early Exit Mechanisms (ICLR 2025)
- arXiv 2603.12933: AMRO-S — ACO for Multi-Agent LLM Routing
- arXiv 2509.05651: Orchestrator — Active Inference for Multi-Agent Systems
- arXiv 2501.02600: TAPAS — Thermal-Aware Scheduling (ASPLOS 2025)
- arXiv 2507.15779: Reservoir Computing as a Language Model
- ICML 2025: Model Swarms — Collaborative Search via Swarm Intelligence
- arXiv 2504.17768: The Sparse Frontier — Sparse Attention Trade-offs
- KVSplit: Differentiated KV cache precision for Apple Silicon

### Clavain Integration Points
- `os/Clavain/config/routing.yaml` — 4-track routing configuration
- `os/Clavain/scripts/lib-routing.sh` — Model resolution library
- `os/Clavain/cmd/clavain-cli/compose.go` — Fleet & calibration resolution
- `interverse/interspect/` — Evidence-driven routing calibration
- `interverse/interrank/` — Model comparison and recommendation
- `interverse/interlab/` — Experiment campaign framework
