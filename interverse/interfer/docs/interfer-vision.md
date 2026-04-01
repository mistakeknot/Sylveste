# interfer — Vision

**Last updated:** 2026-03-26
**Mission:** [`MISSION.md`](../MISSION.md)
**Brainstorm:** [`docs/brainstorms/2026-03-26-local-llm-optimization-m5-max-brainstorm.md`](../../docs/brainstorms/2026-03-26-local-llm-optimization-m5-max-brainstorm.md)

## The Big Idea

The M5 Max with 128GB unified memory is the inflection point where local models match cloud quality for 60-70% of coding tasks at zero marginal cost. interfer is the layer that makes this real for Sylveste — a custom MLX-LM inference server that owns the full computation pipeline, enabling optimizations impossible in off-the-shelf serving frameworks. It's not just a local Ollama replacement; it's a research-grade inference laboratory where techniques from computational neuroscience, swarm intelligence, and information theory are tested against production workloads and either proven or killed.

## Design Principles

**Economics Before Elegance** — Every change must move a metric: tokens/second, quality maintenance, or cost reduction. Beautiful techniques that don't measure up are research debt.

**Own the Loop** — We build the inference pipeline because early exit, reservoir routing, and thermal scheduling need hooks inside the forward pass. This is a strategic requirement, not NIH.

**Experiments Are First-Class** — Every inference optimization enters as an interlab campaign with baseline, treatment, success metric, and kill criterion.

**Fail to Cloud, Not to Silence** — When local confidence is low, escalate. Never silently degrade quality. The cascade is the feature.

**Privacy Is a Routing Dimension** — Code classification (public/internal/sensitive) is a first-class routing signal alongside complexity and latency.

## Current State

- **Version:** 0.1.0 (initial scaffold)
- **Maturity:** Foundation — server skeleton, experiment hooks, no live model serving yet
- **Components:** 7 server modules, 2 experiment hooks, 16 passing tests, MCP server declared
- **Architecture:** Starlette HTTP process + spawned Metal subprocess + priority queue
- **Clavain integration:** Track B5 added to routing.yaml (mode: off)

**Shipped so far:**
- Metal subprocess with memory safety (OOM kernel panic prevention)
- OpenAI-compatible `/v1/chat/completions` with SSE streaming
- Priority request queue with backpressure
- Thermal monitoring via macOS notify API (no sudo)
- Early exit experiment hook (entropy-based confidence check)
- Reservoir routing readout MLP (262K-param task classifier)
- Model registry with memory budget enforcement
- MLX inference engine with stream_generate

## Where We're Going

**Near-term (April 2026):** Ship end-to-end model serving. Wire the Metal worker to the inference engine. Serve Qwen3-30B Q4_K_M. Enable Clavain Track B5 in shadow mode. Measure baseline tok/s and quality.

**Medium-term (May-June 2026):** Run first experiment campaigns — early exit (target: 1.3x speedup), speculative decoding with draft model (target: 1.8x), reservoir routing accuracy vs RouteLLM. Enable Track B5 enforce mode. Confidence cascade routing 60%+ of C1/C2 tasks locally. Cost tracking dashboard.

**Long-term (H2 2026):** The full five-layer stack — reservoir + ACO routing, speculative streaming, two-tier KV cache (RAM + SSD), thermal-aware scheduling, and model swarms for adapter optimization. Each layer proven through interlab campaigns. The system continuously adapts its model fleet and routing based on workload patterns, thermal state, and quality feedback.

## Constellation

| Companion | Role | Integration |
|-----------|------|-------------|
| **Clavain** | Orchestrator — decides which model for which task | Track B5 in routing.yaml, lib-routing.sh tier mappings |
| **interspect** | Evidence collector — tracks local model quality | Canary system extended for local model evidence |
| **interlab** | Experiment platform — runs A/B campaigns | Each esoteric technique is an interlab campaign |
| **interrank** | Model benchmarker — compares model quality | Registers local models in AgMoDB snapshot |
| **interflux** | Review system — 10 custom fd-* agents for interfer | 5 landscape + 5 implementation review agents |

## What We Believe

**Bet 1: 128GB unified memory is a lasting advantage.** Apple Silicon's unified memory architecture makes local 70B models viable in a way that's structurally different from NVIDIA's discrete GPU memory. If Apple continues increasing memory bandwidth (M5 Max: 614 GB/s), the quality ceiling for local inference keeps rising.

**Bet 2: Custom inference loops beat off-the-shelf.** The esoteric optimizations (early exit, reservoir routing, thermal scheduling) require hooks that vllm-mlx, Ollama, and llama.cpp don't expose. Owning the loop is worth the engineering cost. If the community catches up (MLX adds concurrent inference, vllm-mlx adds early exit), we can switch — but waiting for them means losing months.

**Bet 3: The efficiency/quality frontier is dynamic.** New models, new quantization methods, and new hardware generations continuously shift what's optimal. A system that measures and adapts (via interspect evidence + interlab experiments) will outperform static routing over time.

**Bet 4: Cross-disciplinary techniques transfer.** Ant colony optimization, reservoir computing, active inference, and Hebbian learning have concrete implementations that are not just metaphors. At least 3 of the 13 planned experiments will produce measurable improvements. If fewer than 2 work, the "inference laboratory" thesis is wrong and interfer should simplify to a conventional local serving layer.

**Risk:** MLX's lack of concurrent inference (ml-explore/mlx#3078) is the biggest technical constraint. If this isn't resolved by H2 2026, the multi-agent throughput ceiling limits interfer's value for parallel subagent workloads.
