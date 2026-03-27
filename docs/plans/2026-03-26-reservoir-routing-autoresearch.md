---
artifact_type: plan
bead: Sylveste-4b7
stage: planned
features:
  - Sylveste-dbc  # F1: Training data generator
  - Sylveste-dp1  # F2: Evaluation harness
  - Sylveste-bgu  # F3: Hidden state extraction
reviewed: true
review_findings: 5-critical, 5-serious, 5-moderate
---

# Plan: Reservoir Routing MLP Autoresearch Campaign

## Overview

Build the training data, evaluation harness, and hidden state extraction needed to run an interlab autoresearch campaign on the ReservoirReadout MLP. F1 and F3 are independent; F2 integrates both.

## Verified Design Decisions

- **Hidden state access**: `model.model.layers` is a list of TransformerBlock. Partial forward pass through layers[:tap_layer] + last-token extraction gives the hidden state tensor. Confirmed working on mlx-lm 0.31.1 with Qwen2.5-0.5B (24 layers, hidden_dim=896). Production models (35B) have hidden_dim=4096.
- **Cache protocol**: Must use `make_prompt_cache(model)` — passing `cache=[None]*N` raises `AttributeError` on some model families (e.g., Qwen3.5 calls `cache.offset` unconditionally).
- **MLX eval barriers**: Every `mx.array` that crosses a Python boundary (float conversion, dict storage, process boundary) MUST be preceded by `mx.eval()`. Training loop MUST call `mx.eval(model.parameters(), optimizer.state)` after each step.
- **Training approach**: Offline. Generate labeled JSONL, train ReservoirReadout with MLX's `nn.losses.cross_entropy` + `optim.AdamW`, evaluate on held-out split.
- **Metric emission**: Print `METRIC key=value` lines to stdout. interlab's py-bench-harness.sh `--mode output` captures these. Metrics from synthetic data are labeled `synthetic_routing_accuracy_pct` to distinguish from real-data evaluation.
- **MLX imports**: All new files use method-level MLX imports (not module-level) per the design constraint in `inference.py`. Fix existing module-level imports in `reservoir_routing.py` as a prerequisite.
- **All new files** include `from __future__ import annotations`.

## Prerequisite: Fix MLX imports in reservoir_routing.py

**File:** `interverse/interfere/server/experiments/reservoir_routing.py`

Move `import mlx.core as mx` and `import mlx.nn as nn` from module level into method bodies (`__init__`, `__call__`, `classify`). This aligns with the design constraint documented in `inference.py` lines 3-6.

## Tasks

### T1: Training data generator (Sylveste-dbc)

**File:** `interverse/interfere/server/experiments/training_data.py`

Create a Python module with:
- `generate_training_data(num_per_class=200, seed=42, label_scheme: Literal["3class", "4class"] = "3class") -> list[dict]`
- 3-class scheme: `small` (simple questions, greetings, lookups), `medium` (code generation, analysis, multi-step reasoning), `large` (complex creative, long-form, multi-domain)
- 4-class scheme: `coding`, `reasoning`, `creative`, `factual`
- Each entry: `{"prompt": str, "label": str, "label_id": int}`
- Use template-based generation with randomized subjects/contexts (not just keyword lists)
- `CLASS_LABELS` dict mapping scheme → ordered list of label strings (canonical source for label-to-index mapping)
- `split_data(data, train_ratio=0.8, seed=42) -> tuple[list, list]`
- `save_jsonl(data, path)` for persistence

**Test:** `interverse/interfere/tests/test_training_data.py`
- Generates expected count per class
- Labels are valid and match `CLASS_LABELS` registry
- Train/test split ratio is ~80/20
- Reproducible with same seed
- `num_per_class=0` raises `ValueError`

### T2: Extend ReservoirReadout with configurable activation (Sylveste-dbc)

**File:** `interverse/interfere/server/experiments/reservoir_routing.py`

- Add `activation` param to `__init__`: supports `"relu"`, `"gelu"`, `"silu"` (default: `"relu"`)
- Store as `self.activation_fn` (no underscore — matches `fc1`/`fc2` convention) and use in `__call__`
- Add `class_labels: list[str] | None = None` param to `__init__` — stores the label-to-index mapping for `routing_probs` dict population
- **Do NOT add** custom `save_weights`/`load_weights` — `nn.Module` already provides these. Instead, save metadata (hidden_dim, bottleneck, num_models, activation, class_labels) in a separate JSON sidecar file alongside weights.

**Test:** Update `test_reservoir_routing.py`:
- Test each activation function produces valid output
- Test `nn.Module.save_weights`/`load_weights` roundtrip preserves weights
- Test metadata sidecar save/load roundtrip
- Test hidden_dim mismatch raises clear error on forward pass

### T3: Hidden state extraction (Sylveste-bgu)

**File:** `interverse/interfere/server/inference.py` (as private method `_extract_hidden_state`)

The function lives in `inference.py` alongside other mlx-lm internal access (`_ensure_loaded`, `_init_hooks`), not in `reservoir_routing.py`.

```python
def _extract_hidden_state(
    self,
    model,         # mlx-lm Model object
    tokens: mx.array,  # tokenized prompt (1, seq_len)
    tap_layer: int = 24,
) -> mx.array:
    """Run partial forward pass and return last-token hidden state at tap_layer."""
```

Implementation:
1. Validate: `if tap_layer > len(model.model.layers): raise ValueError(f"tap_layer={tap_layer} exceeds model depth {len(model.model.layers)}")`
2. `h = model.model.embed_tokens(tokens)`
3. `cache = make_prompt_cache(model)` — use `from mlx_lm.models.cache import make_prompt_cache`
4. Loop `model.model.layers[:tap_layer]`, with corresponding cache entries: `h = layer(h, mask=None, cache=cache[i])`
5. Last-token extraction: `h[:, -1, :]` → shape `(1, hidden_dim)` (not mean-pool — causal model's last token attends to all prior tokens)
6. `mx.eval(hidden)` — materialize before returning to prevent graph bleed into `stream_generate`
7. Return hidden state

**Performance note**: This runs a partial forward pass separate from `stream_generate`, adding ~37.5% overhead to prefill for 24/64 layers. Acceptable for the diagnostic/autoresearch campaign. Future optimization: forward-hook approach that captures hidden states during `stream_generate`'s own prefill (zero overhead). Track as follow-up when routing becomes a pre-flight gate.

**Test:** `test_reservoir_routing.py`
- Extract hidden state from loaded 0.5B model
- Output shape is `(1, hidden_dim)`
- Different prompts produce different hidden states
- `tap_layer > model depth` raises ValueError
- `tap_layer == model depth` works (last layer)

### T4: Wire reservoir hook into InferenceEngine (Sylveste-bgu)

**File:** `interverse/interfere/server/inference.py`

In `generate()`, before the stream_generate loop:
1. If `self._reservoir_hook is not None`:
   - Tokenize prompt: `tokens = mx.array(tokenizer.encode(prompt))[None]`
   - `tap_layer = int(self._reservoir_cfg.get("layer", 24))`
   - `hidden = self._extract_hidden_state(model, tokens, tap_layer)`
   - `probs = self._reservoir_hook.classify(hidden)`
   - `mx.eval(probs)` — materialize before float conversion
   - Store in `metrics.routing_probs` using `class_labels`: `{label: float(probs[0, i]) for i, label in enumerate(self._reservoir_hook.class_labels or [f"model_{i}" for i in range(probs.shape[-1])])}`
2. Store `self._reservoir_cfg` reference in `__init__` for layer access

**Test:** Verify `GenerationMetrics.routing_probs` is populated with correct label keys when reservoir_routing is enabled.

### T5: Training script (Sylveste-dp1)

**File:** `interverse/interfere/server/experiments/train_reservoir.py`

Standalone training script (reads config from env vars only — no argparse duplication):
```python
def train_reservoir(
    data_path: str,
    hidden_dim: int = 4096,
    bottleneck: int = 64,
    num_classes: int = 3,
    activation: str = "relu",
    epochs: int = 50,
    lr: float = 1e-3,
    batch_size: int = 32,
    output_path: str = "reservoir_weights.npz",
    output_format: str = "dict",
) -> dict[str, float]:
```

Training loop:
1. Load JSONL, extract label_ids. Validate: `num_classes` must match number of distinct labels in data.
2. Synthetic features: random vectors per class with distinct cluster centers. This lets us benchmark MLP architecture without model loaded.
3. Build ReservoirReadout with params. Freeze: only ReservoirReadout params in optimizer (already the case since no backbone is loaded).
4. Loss: `nn.losses.cross_entropy(logits, labels)` — from raw logits, NOT post-softmax.
5. Use `nn.value_and_grad(model, loss_fn)` to get gradients.
6. Each step: `optimizer.update(model, grads)` then `mx.eval(model.parameters(), optimizer.state)`.
7. Evaluate on test split: accuracy + inference time for single classify() call.
8. Return `{"synthetic_routing_accuracy_pct": float, "inference_overhead_ms": float}`.
9. Save weights + metadata sidecar (hidden_dim, bottleneck, num_classes, activation, class_labels).

When `output_format == "metric"`, print METRIC lines to stdout and emit `METRIC benchmark_exit_code=0`.

**Test:** Unit test that training loop converges (loss decreases) and all classes appear in predictions.

### T6: Evaluation harness script (Sylveste-dp1)

**File:** `interverse/interfere/scripts/interlab-reservoir-tune.sh` (in `scripts/` not project root)

```bash
#!/usr/bin/env bash
set -euo pipefail
# Accepts hyperparams as env vars with defaults
export HIDDEN_DIM=${HIDDEN_DIM:-4096}
export BOTTLENECK_DIM=${BOTTLENECK_DIM:-64}
export ACTIVATION=${ACTIVATION:-relu}
export NUM_CLASSES=${NUM_CLASSES:-3}

cd "$(dirname "$0")/.."
uv run python3 -m server.experiments.train_reservoir 2>/tmp/reservoir-train-stderr.log
EXIT_CODE=$?

if [[ $EXIT_CODE -ne 0 ]]; then
    echo "METRIC error=1"
    echo "METRIC benchmark_exit_code=$EXIT_CODE"
    cat /tmp/reservoir-train-stderr.log >&2
    exit $EXIT_CODE
fi
```

Python script reads env vars directly via `os.environ.get()` — no CLI arg duplication. stderr is captured separately to avoid corrupting METRIC lines on stdout.

**Test:** Run harness with default params, verify METRIC lines in output. Test with deliberately broken config, verify error propagation.

### T7: Integration test (all features)

**File:** `interverse/interfere/tests/test_reservoir_routing.py` (extend)

End-to-end test:
1. Generate training data (3-class, small count for speed)
2. Train ReservoirReadout with synthetic features
3. Assert: final loss < initial loss (convergence), all 3 classes appear in predictions, accuracy > 90% (synthetic clusters are trivially separable — 60% is too low)
4. Verify METRIC output format
5. Test: load saved weights into new ReservoirReadout with matching config — classify produces same results
6. Test: load saved weights with mismatched `num_classes` — raises clear error from metadata validation

## Execution Order

```
Prereq (fix MLX imports) ──→ T2 (activation + class_labels)
T1 (training data) ─────────┐
                              ├──→ T5 (training script) → T6 (harness) → T7 (integration)
T2 (activation) ────────────┤
T3 (hidden state) ──────────┘
T4 (wire hook) ← T3
```

T1, T2, T3 are independent → parallel (after prereq).
T4 depends on T3.
T5 depends on T1 + T2 + T3.
T6 depends on T5.
T7 depends on all.

## Risks

1. **mlx-lm model internals may change**: We access `model.model.layers`, `model.model.embed_tokens`, and `make_prompt_cache` directly. Add attribute existence check at hook init time. Pin mlx-lm version in pyproject.toml.
2. **Synthetic vs real features gap**: Architecture that works on synthetic clusters may not transfer to real hidden states. Mitigated: metrics labeled as `synthetic_*`. Follow-up bead for real-data validation before `mode: enforce`.
3. **Double-prefill overhead**: ~37.5% time-to-first-token tax when reservoir hook enabled. Acceptable for diagnostic/autoresearch. Follow-up: forward-hook approach for zero-overhead extraction when routing becomes pre-flight gate.
