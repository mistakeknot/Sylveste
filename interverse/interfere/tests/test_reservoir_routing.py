"""Tests for reservoir routing readout MLP, training, and hidden state extraction."""

from __future__ import annotations

import json
import tempfile
from pathlib import Path

import mlx.core as mx

from server.experiments.reservoir_routing import CLASS_LABELS, ReservoirReadout
from server.experiments.training_data import generate_training_data, split_data


# --- ReservoirReadout tests ---


def test_reservoir_readout_classifies():
    """ReservoirReadout.classify returns valid probability distribution."""
    readout = ReservoirReadout(hidden_dim=64, num_models=4)
    hidden = mx.random.normal((1, 64))

    probs = readout.classify(hidden)

    assert probs.shape == (1, 4), f"Expected shape (1, 4), got {probs.shape}"
    total = probs.sum(axis=-1).item()
    assert abs(total - 1.0) < 1e-5, f"Probabilities sum to {total}, expected ~1.0"


def test_reservoir_readout_activations():
    """All supported activation functions produce valid output."""
    for activation in ["relu", "gelu", "silu"]:
        readout = ReservoirReadout(hidden_dim=32, num_models=3, activation=activation)
        hidden = mx.random.normal((2, 32))
        logits = readout(hidden)
        mx.eval(logits)
        assert logits.shape == (
            2,
            3,
        ), f"{activation}: Expected (2, 3), got {logits.shape}"


def test_reservoir_readout_save_load():
    """Save/load roundtrip preserves weights and metadata."""
    readout = ReservoirReadout(
        hidden_dim=32,
        bottleneck=8,
        num_models=3,
        activation="gelu",
        class_labels=["a", "b", "c"],
    )
    hidden = mx.random.normal((1, 32))
    original_probs = readout.classify(hidden)
    mx.eval(original_probs)

    with tempfile.TemporaryDirectory() as tmpdir:
        weights_path = Path(tmpdir) / "test_weights.safetensors"
        readout.save_model(str(weights_path))

        # Verify metadata sidecar
        metadata_path = weights_path.with_suffix(".json")
        assert metadata_path.exists()
        metadata = json.loads(metadata_path.read_text())
        assert metadata["hidden_dim"] == 32
        assert metadata["bottleneck"] == 8
        assert metadata["num_models"] == 3
        assert metadata["activation"] == "gelu"
        assert metadata["class_labels"] == ["a", "b", "c"]

        # Load and compare
        loaded = ReservoirReadout.load_model(str(weights_path))
        loaded_probs = loaded.classify(hidden)
        mx.eval(loaded_probs)

        diff = float(mx.abs(original_probs - loaded_probs).max())
        assert diff < 1e-5, f"Loaded model diverges by {diff}"


def test_reservoir_readout_class_labels():
    """class_labels is stored and accessible."""
    labels = ["small", "medium", "large"]
    readout = ReservoirReadout(hidden_dim=32, num_models=3, class_labels=labels)
    assert readout.class_labels == labels


# --- Training data tests ---


def test_generate_training_data_3class():
    """3-class scheme generates expected count per class."""
    data = generate_training_data(num_per_class=10, seed=42, label_scheme="3class")
    assert len(data) == 30
    labels = [d["label"] for d in data]
    for label in CLASS_LABELS["3class"]:
        assert (
            labels.count(label) == 10
        ), f"Expected 10 '{label}', got {labels.count(label)}"


def test_generate_training_data_4class():
    """4-class scheme generates expected count per class."""
    data = generate_training_data(num_per_class=10, seed=42, label_scheme="4class")
    assert len(data) == 40
    labels = [d["label"] for d in data]
    for label in CLASS_LABELS["4class"]:
        assert labels.count(label) == 10


def test_training_data_reproducible():
    """Same seed produces identical data."""
    data1 = generate_training_data(num_per_class=5, seed=123)
    data2 = generate_training_data(num_per_class=5, seed=123)
    assert data1 == data2


def test_training_data_different_seeds():
    """Different seeds produce different data."""
    data1 = generate_training_data(num_per_class=5, seed=1)
    data2 = generate_training_data(num_per_class=5, seed=2)
    prompts1 = [d["prompt"] for d in data1]
    prompts2 = [d["prompt"] for d in data2]
    assert prompts1 != prompts2


def test_split_data_ratio():
    """Train/test split is approximately 80/20."""
    data = generate_training_data(num_per_class=50, seed=42)
    train, test = split_data(data)
    total = len(data)
    assert abs(len(train) / total - 0.8) < 0.02
    assert abs(len(test) / total - 0.2) < 0.02


def test_training_data_invalid_num():
    """num_per_class < 1 raises ValueError."""
    import pytest

    with pytest.raises(ValueError, match="num_per_class must be >= 1"):
        generate_training_data(num_per_class=0)


# --- Training loop tests ---


def test_train_reservoir_converges():
    """Training loop converges: loss decreases, all classes predicted, accuracy > 90%."""
    from server.experiments.train_reservoir import train_reservoir

    with tempfile.TemporaryDirectory() as tmpdir:
        output_path = Path(tmpdir) / "test_weights.safetensors"
        metrics = train_reservoir(
            hidden_dim=64,
            bottleneck=16,
            num_classes=3,
            activation="relu",
            epochs=100,
            lr=1e-2,
            batch_size=16,
            output_path=str(output_path),
            label_scheme="3class",
            seed=42,
        )

    assert (
        metrics["final_loss"] < metrics["initial_loss"]
    ), f"Loss did not decrease: {metrics['initial_loss']:.4f} -> {metrics['final_loss']:.4f}"
    assert metrics["all_classes_predicted"] == 1.0, "Not all classes predicted"
    assert (
        metrics["synthetic_routing_accuracy_pct"] > 90.0
    ), f"Accuracy {metrics['synthetic_routing_accuracy_pct']:.1f}% is below 90% threshold"


def test_train_reservoir_metric_format():
    """Training script emits valid METRIC lines."""
    import subprocess

    result = subprocess.run(
        ["uv", "run", "python3", "-m", "server.experiments.train_reservoir"],
        capture_output=True,
        text=True,
        cwd=str(Path(__file__).parent.parent),
        env={
            **dict(__import__("os").environ),
            "HIDDEN_DIM": "32",
            "BOTTLENECK_DIM": "8",
            "NUM_CLASSES": "3",
            "EPOCHS": "10",
            "OUTPUT_PATH": "/tmp/test_reservoir_weights.safetensors",
        },
    )

    assert result.returncode == 0, f"Script failed: {result.stderr}"
    lines = result.stdout.strip().split("\n")
    metric_lines = [l for l in lines if l.startswith("METRIC ")]
    param_lines = [l for l in lines if l.startswith("PARAM ")]

    assert (
        len(metric_lines) >= 3
    ), f"Expected >= 3 METRIC lines, got {len(metric_lines)}"
    assert any("benchmark_exit_code=0" in l for l in metric_lines)
    assert any("synthetic_routing_accuracy_pct" in l for l in metric_lines)
    assert any("inference_overhead_ms" in l for l in metric_lines)
    assert len(param_lines) >= 4, f"Expected >= 4 PARAM lines, got {len(param_lines)}"
