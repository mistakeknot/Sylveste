---
artifact_type: brainstorm
bead: Sylveste-4b7
stage: discover
---

# Reservoir Routing MLP Autoresearch

## What We're Building

An interlab autoresearch campaign that systematically explores the mutation space of the ReservoirReadout MLP — a 262K-param bottleneck network that classifies prompts from frozen transformer hidden states to route inference to the optimal model (small/medium/large or per-category).

Three deliverables:
1. **Training data generator** — labeled prompt examples per routing class
2. **Evaluation harness** (`interlab-reservoir-tune.sh`) — trains, evaluates, emits METRIC lines
3. **Campaign config** — mutation space encoding for interlab's experiment loop

## Why This Approach

The ReservoirReadout skeleton exists (`server/experiments/reservoir_routing.py`) with a simple 2-layer bottleneck MLP. The architecture decisions from Sylveste-f0k (frozen layer-24, 262K params) are locked. What remains is empirical: which hyperparameter combination yields the best routing accuracy with minimal inference overhead.

Autoresearch is the right tool because:
- Mutation space is discrete and enumerated (tap layer x hidden dim x bottleneck x activation x classes = 270 combinations)
- Primary/secondary metrics are well-defined (accuracy, latency)
- Kill condition prevents wasted compute (5 runs with <0.5% improvement)
- interlab already handles branch isolation, JSONL logging, and circuit breakers

## Key Decisions

1. **Training data**: Synthetic labeled prompts across 4 categories (coding, reasoning, creative, factual). Generate 200-500 per class using template patterns + manual curation. No external LLM needed — pattern-based classification suffices for initial routing.

2. **Evaluation protocol**: Train on 80% of labeled data, evaluate on held-out 20%. Report accuracy and inference overhead (time to classify one prompt through the MLP). Use py-bench-harness.sh in `output` mode to capture METRIC lines.

3. **Routing classes**: Start with 3 classes (small/medium/large) matching the existing complexity tiers (C1/C2/C3). The 4-class (per-category) and 2-class (local/cloud) variants are mutations explored during the campaign.

4. **Hidden state extraction**: Need to add a hook point in InferenceEngine that captures the hidden state at the configured layer during the first forward pass. This is the main integration work — ReservoirReadout.classify() is called once per prompt, not per token.

5. **Interlab integration**: Use `--mode output` with py-bench-harness.sh. The benchmark script trains the MLP with current hyperparams, runs eval, and prints `METRIC routing_accuracy_pct=X` and `METRIC inference_overhead_ms=Y`.

## Open Questions

- **Layer extraction from mlx-lm**: Does `stream_generate` expose intermediate layer activations, or do we need a separate prefill pass? Need to check mlx-lm API.
- **Training compute**: How long does training 262K params on 500 examples take on M5 Max? Likely seconds, but should validate before setting campaign iteration budget.
