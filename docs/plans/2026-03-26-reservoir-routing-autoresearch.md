---
artifact_type: plan
bead: Demarch-4b7
stage: planned
features:
  - Demarch-dbc  # F1: Training data generator
  - Demarch-dp1  # F2: Evaluation harness
  - Demarch-bgu  # F3: Hidden state extraction
---

# Plan: Reservoir Routing MLP Autoresearch Campaign

## Overview

Build the training data, evaluation harness, and hidden state extraction needed to run an interlab autoresearch campaign on the ReservoirReadout MLP. F1 and F3 are independent; F2 integrates both.

## Verified Design Decisions

- **Hidden state access**: `model.model.layers` is a list of TransformerBlock. Partial forward pass through layers[:tap_layer] + mean-pool gives the hidden state tensor. Confirmed working on mlx-lm 0.31.1 with Qwen2.5-0.5B (24 layers, hidden_dim=896). Production models (35B) have hidden_dim=4096.
- **Training approach**: Offline. Generate labeled JSONL, train ReservoirReadout with MLX's `nn.losses.cross_entropy` + `optim.AdamW`, evaluate on held-out split.
- **Metric emission**: Print `METRIC key=value` lines to stdout. interlab's py-bench-harness.sh `--mode output` captures these.

## Tasks

### T1: Training data generator (Demarch-dbc)

**File:** `interverse/interfere/server/experiments/training_data.py`

Create a Python module with:
- `generate_training_data(num_per_class=200, seed=42, label_scheme="3class") -> list[dict]`
- 3-class scheme: `small` (simple questions, greetings, lookups), `medium` (code generation, analysis, multi-step reasoning), `large` (complex creative, long-form, multi-domain)
- 4-class scheme: `coding`, `reasoning`, `creative`, `factual`
- Each entry: `{"prompt": str, "label": str, "label_id": int}`
- Use template-based generation with randomized subjects/contexts (not just keyword lists)
- `split_data(data, train_ratio=0.8, seed=42) -> tuple[list, list]`
- `save_jsonl(data, path)` for persistence

**Test:** `interverse/interfere/tests/test_training_data.py`
- Generates expected count per class
- Labels are valid
- Train/test split ratio is ~80/20
- Reproducible with same seed

### T2: Extend ReservoirReadout with configurable activation (Demarch-dbc)

**File:** `interverse/interfere/server/experiments/reservoir_routing.py`

- Add `activation` param to `__init__`: supports `"relu"`, `"gelu"`, `"silu"` (default: `"relu"`)
- Store as `self._activation_fn` and use in `__call__` instead of hardcoded `nn.relu`
- Add `save_weights(path)` and `load_weights(path)` convenience methods (delegates to `mx.save`/`mx.load`)

**Test:** Update `test_reservoir_routing.py`:
- Test each activation function produces valid output
- Test save/load roundtrip preserves weights

### T3: Hidden state extraction (Demarch-bgu)

**File:** `interverse/interfere/server/experiments/reservoir_routing.py`

Add a standalone function:
```python
def extract_hidden_state(
    model,         # mlx-lm Model object
    tokens: mx.array,  # tokenized prompt (1, seq_len)
    tap_layer: int = 24,
) -> mx.array:
    """Run partial forward pass and return mean-pooled hidden state at tap_layer."""
```

Implementation:
1. `h = model.model.embed_tokens(tokens)`
2. `cache = [None] * len(model.model.layers)`
3. Loop `model.model.layers[:tap_layer]`, accumulating `h = layer(h, mask, c)`
4. Mean-pool: `mx.mean(h, axis=1)` → shape `(1, hidden_dim)`
5. Clamp `tap_layer` to `min(tap_layer, len(model.model.layers))` with a warning

**Test:** `test_reservoir_routing.py`
- Extract hidden state from loaded 0.5B model
- Output shape is `(1, hidden_dim)`
- Different prompts produce different hidden states

### T4: Wire reservoir hook into InferenceEngine (Demarch-bgu)

**File:** `interverse/interfere/server/inference.py`

In `generate()`, before the stream_generate loop:
1. If `self._reservoir_hook is not None`:
   - Tokenize prompt: `tokens = mx.array(tokenizer.encode(prompt))[None]`
   - `tap_layer = int(reservoir_cfg.get("layer", 24))`
   - `hidden = extract_hidden_state(model, tokens, tap_layer)`
   - `probs = self._reservoir_hook.classify(hidden)`
   - Store in `metrics.routing_probs`: `{f"model_{i}": float(probs[0, i]) for i in range(probs.shape[-1])}`
2. Store the reservoir_cfg reference in `__init__` for layer access

This runs once per prompt (not per token) — overhead is one partial forward pass through tap_layer layers.

**Test:** Verify `GenerationMetrics.routing_probs` is populated when reservoir_routing is enabled.

### T5: Training script (Demarch-dp1)

**File:** `interverse/interfere/server/experiments/train_reservoir.py`

Standalone training script:
```python
def train_reservoir(
    data_path: str,           # JSONL training data
    hidden_dim: int = 4096,
    bottleneck: int = 64,
    num_classes: int = 3,
    activation: str = "relu",
    epochs: int = 50,
    lr: float = 1e-3,
    batch_size: int = 32,
    output_path: str = "reservoir_weights.npz",
) -> dict[str, float]:
    """Train ReservoirReadout and return metrics dict."""
```

Training loop:
1. Load JSONL, extract label_ids
2. For training: need hidden state features. Two options:
   - **Synthetic features** (for autoresearch): generate random vectors per class with distinct cluster centers. This lets us benchmark the MLP architecture without needing the actual model loaded.
   - **Real features** (for production): extract from actual model. Separate concern.
3. Build ReservoirReadout with params
4. AdamW optimizer, cross_entropy loss
5. Train for N epochs
6. Evaluate on test split: accuracy + inference time for single classify() call
7. Return `{"routing_accuracy_pct": float, "inference_overhead_ms": float}`

For autoresearch, synthetic features are sufficient to compare architectures — the MLP's ability to separate clusters is the metric we care about. Real features come later when deploying the best architecture.

### T6: Evaluation harness script (Demarch-dp1)

**File:** `interverse/interfere/interlab-reservoir-tune.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
# Accepts hyperparams as env vars with defaults
TAP_LAYER=${TAP_LAYER:-24}
HIDDEN_DIM=${HIDDEN_DIM:-4096}
BOTTLENECK_DIM=${BOTTLENECK_DIM:-64}
ACTIVATION=${ACTIVATION:-relu}
NUM_CLASSES=${NUM_CLASSES:-3}

cd "$(dirname "$0")"
uv run python3 -m server.experiments.train_reservoir \
  --hidden-dim "$HIDDEN_DIM" \
  --bottleneck "$BOTTLENECK_DIM" \
  --activation "$ACTIVATION" \
  --num-classes "$NUM_CLASSES" \
  --output-format metric
```

The Python script in `--output-format metric` mode prints:
```
METRIC routing_accuracy_pct=87.5
METRIC inference_overhead_ms=0.12
METRIC benchmark_exit_code=0
```

**Test:** Run harness with default params, verify METRIC lines in output.

### T7: Integration test (all features)

**File:** `interverse/interfere/tests/test_reservoir_routing.py` (extend)

End-to-end test:
1. Generate training data (3-class, small count for speed)
2. Train ReservoirReadout
3. Evaluate accuracy > 60% (synthetic clusters should be easily separable)
4. Verify METRIC output format

## Execution Order

```
T1 (training data) ──┐
                      ├──→ T5 (training script) → T6 (harness) → T7 (integration)
T2 (activation) ─────┤
T3 (hidden state) ────┘
T4 (wire hook) ← T3
```

T1, T2, T3 are independent → parallel.
T4 depends on T3.
T5 depends on T1 + T2 + T3.
T6 depends on T5.
T7 depends on all.

## Risks

1. **mlx-lm model internals may change**: We access `model.model.layers` and `model.model.embed_tokens` directly. Pin mlx-lm version or add a compatibility check.
2. **Synthetic vs real features gap**: Architecture that works on synthetic clusters may not transfer to real hidden states. Mitigated: autoresearch will later rerun with real features once best architecture is found.
