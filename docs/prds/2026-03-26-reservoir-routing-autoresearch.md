---
artifact_type: prd
bead: Sylveste-4b7
stage: design
---

# PRD: Reservoir Routing MLP Autoresearch Campaign

## Problem

The ReservoirReadout MLP skeleton exists but has no training data, evaluation harness, or hidden state extraction — it can't be trained or benchmarked. The 270-combination mutation space (tap layer x hidden dim x bottleneck x activation x routing classes) needs systematic exploration via interlab autoresearch.

## Solution

Build three components that enable interlab to run the autoresearch campaign: a training data generator, an evaluation harness script, and a hidden state extraction hook in the inference engine. Together these let `interlab run_experiment` iterate over the mutation space with clear metrics (routing_accuracy_pct, inference_overhead_ms) and a kill condition (5 experiments with <0.5% improvement).

## Features

### F1: Training Data Generator

**What:** Python script that generates labeled prompt examples for each routing class and produces train/test splits.

**Acceptance criteria:**
- [ ] Generates 200+ labeled prompts per routing class
- [ ] Supports 3-class (small/medium/large) and 4-class (coding/reasoning/creative/factual) label schemes
- [ ] Outputs JSONL with fields: `prompt`, `label`, `split` (train/test, 80/20)
- [ ] Prompts are diverse enough to avoid trivial pattern matching (not just keyword lists)
- [ ] Reproducible with a seed parameter

### F2: Evaluation Harness

**What:** Shell script (`interlab-reservoir-tune.sh`) that trains the MLP, runs evaluation, and emits interlab-compatible METRIC lines.

**Acceptance criteria:**
- [ ] Accepts hyperparams as env vars or args: `TAP_LAYER`, `HIDDEN_DIM`, `BOTTLENECK_DIM`, `ACTIVATION`, `NUM_CLASSES`
- [ ] Trains ReservoirReadout on training split using MLX optimizer (Adam/AdamW)
- [ ] Evaluates on held-out test split
- [ ] Emits `METRIC routing_accuracy_pct=<float>` and `METRIC inference_overhead_ms=<float>`
- [ ] Emits `METRIC benchmark_exit_code=0` on success
- [ ] Compatible with interlab's `py-bench-harness.sh --mode output`
- [ ] Training completes in <60s on M5 Max for the largest config (hidden_dim=8192)

### F3: Hidden State Extraction Hook

**What:** Integration in InferenceEngine to capture hidden states at a configurable transformer layer during the prefill pass, feeding them to ReservoirReadout.

**Acceptance criteria:**
- [ ] Captures hidden state tensor at the configured layer (default: 24) after prefill
- [ ] Passes hidden state to ReservoirReadout.classify() and stores routing_probs in GenerationMetrics
- [ ] Layer index is configurable via defaults.yaml `reservoir_routing.layer` param
- [ ] No inference overhead when reservoir_routing is disabled (zero cost when off)
- [ ] Works with the existing `_raw_stream_generate` / `generate` methods
- [ ] Handles models with fewer layers than the tap layer gracefully (clamp or error)

## Non-goals

- Production routing decisions (this campaign only measures accuracy — actual routing integration is a separate bead)
- Cloud model benchmarking (routing targets are local models only)
- Real-time training during inference (offline training only)
- Custom transformer architectures (we use frozen off-the-shelf models)

## Dependencies

- MLX and mlx-lm installed (already in interfer's dependencies)
- interlab MCP tools (init_experiment, run_experiment, log_experiment)
- Existing ReservoirReadout skeleton in `server/experiments/reservoir_routing.py`
- py-bench-harness.sh for METRIC line parsing

## Open Questions

- Does mlx-lm expose intermediate layer activations during stream_generate, or do we need a separate model forward pass for hidden state extraction? (Investigate during F3 implementation)
- Optimal training epochs/learning rate for 262K params on 500 examples? (Empirical — autoresearch will explore this too)
