"""Training script for ReservoirReadout MLP.

Trains the routing classifier on labeled data (synthetic or real hidden states)
and reports metrics compatible with interlab's py-bench-harness.

Usage:
    # As module (reads config from env vars):
    uv run python3 -m server.experiments.train_reservoir

    # Programmatic:
    from server.experiments.train_reservoir import train_reservoir
    metrics = train_reservoir(data_path="training_data.jsonl")
"""

from __future__ import annotations

import os
import sys
import time
from pathlib import Path

import mlx.core as mx
import mlx.nn as nn
import mlx.optimizers as optim

from .reservoir_routing import CLASS_LABELS, ReservoirReadout
from .training_data import generate_training_data, load_jsonl, save_jsonl, split_data


def _make_cluster_centers(
    num_classes: int, hidden_dim: int, center_seed: int = 0
) -> mx.array:
    """Generate deterministic cluster centers for synthetic features.

    Uses a fixed seed so train and test data share the same centers.
    """
    mx.random.seed(center_seed)
    centers = mx.random.normal((num_classes, hidden_dim)) * 3.0
    mx.eval(centers)
    return centers


def _generate_synthetic_features(
    data: list[dict],
    hidden_dim: int,
    num_classes: int,
    seed: int = 42,
    centers: mx.array | None = None,
) -> tuple[mx.array, mx.array]:
    """Generate synthetic hidden state features with class-separable clusters.

    Each class gets a distinct cluster center in hidden_dim space. Data points
    are sampled around these centers with Gaussian noise. This allows benchmarking
    MLP architecture without needing an actual model loaded.

    Args:
        centers: Pre-computed cluster centers. If None, generates from a fixed seed.

    Returns:
        (features, labels) — features shape (N, hidden_dim), labels shape (N,)
    """
    if centers is None:
        centers = _make_cluster_centers(num_classes, hidden_dim)

    mx.random.seed(seed)
    features_list = []
    labels_list = []

    for entry in data:
        label_id = entry["label_id"]
        # Sample around cluster center with noise
        noise = mx.random.normal((1, hidden_dim)) * 0.5
        feature = centers[label_id : label_id + 1] + noise
        features_list.append(feature)
        labels_list.append(label_id)

    features = mx.concatenate(features_list, axis=0)
    labels = mx.array(labels_list)
    mx.eval(features, labels)
    return features, labels


def train_reservoir(
    data_path: str | None = None,
    hidden_dim: int = 4096,
    bottleneck: int = 64,
    num_classes: int = 3,
    activation: str = "relu",
    epochs: int = 50,
    lr: float = 1e-3,
    batch_size: int = 32,
    output_path: str = "reservoir_weights.safetensors",
    label_scheme: str = "3class",
    seed: int = 42,
) -> dict[str, float]:
    """Train ReservoirReadout and return metrics dict.

    If data_path is None, generates training data automatically.
    Uses synthetic features (random vectors per class with distinct cluster centers).
    """
    # Generate or load training data
    if data_path and Path(data_path).exists():
        all_data = load_jsonl(data_path)
    else:
        all_data = generate_training_data(
            num_per_class=200, seed=seed, label_scheme=label_scheme
        )

    # Validate class count
    actual_classes = len(set(d["label_id"] for d in all_data))
    if actual_classes != num_classes:
        raise ValueError(
            f"num_classes={num_classes} but data has {actual_classes} distinct labels"
        )

    train_data, test_data = split_data(all_data, train_ratio=0.8, seed=seed)

    # Generate synthetic features with shared cluster centers
    centers = _make_cluster_centers(num_classes, hidden_dim)
    train_features, train_labels = _generate_synthetic_features(
        train_data, hidden_dim, num_classes, seed=seed, centers=centers
    )
    test_features, test_labels = _generate_synthetic_features(
        test_data, hidden_dim, num_classes, seed=seed + 100, centers=centers
    )

    # Build model
    class_labels = CLASS_LABELS.get(label_scheme)
    model = ReservoirReadout(
        hidden_dim=hidden_dim,
        bottleneck=bottleneck,
        num_models=num_classes,
        activation=activation,
        class_labels=class_labels,
    )

    # Optimizer
    optimizer = optim.AdamW(learning_rate=lr)

    # Loss function + gradient
    def loss_fn(model, x, y):
        logits = model(x)  # Raw logits, NOT post-softmax
        return mx.mean(nn.losses.cross_entropy(logits, y))

    loss_and_grad = nn.value_and_grad(model, loss_fn)

    # Training loop
    n_train = train_features.shape[0]
    initial_loss = None
    final_loss = None

    for epoch in range(epochs):
        # Shuffle training data each epoch
        perm = mx.random.permutation(n_train)
        mx.eval(perm)
        shuffled_features = train_features[perm]
        shuffled_labels = train_labels[perm]

        epoch_loss = 0.0
        n_batches = 0

        for i in range(0, n_train, batch_size):
            batch_x = shuffled_features[i : i + batch_size]
            batch_y = shuffled_labels[i : i + batch_size]

            loss, grads = loss_and_grad(model, batch_x, batch_y)
            optimizer.update(model, grads)
            mx.eval(model.parameters(), optimizer.state)

            epoch_loss += float(loss)
            n_batches += 1

        avg_loss = epoch_loss / max(n_batches, 1)
        if initial_loss is None:
            initial_loss = avg_loss
        final_loss = avg_loss

    # Evaluate on test set
    test_logits = model(test_features)
    mx.eval(test_logits)
    predictions = mx.argmax(test_logits, axis=-1)
    mx.eval(predictions)

    correct = int(mx.sum(predictions == test_labels).item())
    total = test_labels.shape[0]
    accuracy = (correct / total) * 100.0

    # Measure inference overhead (single classify call)
    single_input = test_features[:1]
    start = time.perf_counter()
    for _ in range(100):
        probs = model.classify(single_input)
        mx.eval(probs)
    elapsed = (time.perf_counter() - start) / 100.0 * 1000.0  # ms

    # Check all classes predicted
    unique_preds = set(int(p) for p in predictions.tolist())
    all_classes_predicted = len(unique_preds) == num_classes

    # Save model
    output_path_obj = Path(output_path)
    output_path_obj.parent.mkdir(parents=True, exist_ok=True)
    model.save_model(str(output_path_obj))

    return {
        "synthetic_routing_accuracy_pct": accuracy,
        "inference_overhead_ms": elapsed,
        "initial_loss": initial_loss or 0.0,
        "final_loss": final_loss or 0.0,
        "all_classes_predicted": 1.0 if all_classes_predicted else 0.0,
        "test_correct": float(correct),
        "test_total": float(total),
    }


def main() -> None:
    """CLI entry point — reads config from env vars."""
    hidden_dim = int(os.environ.get("HIDDEN_DIM", "4096"))
    bottleneck = int(os.environ.get("BOTTLENECK_DIM", "64"))
    num_classes = int(os.environ.get("NUM_CLASSES", "3"))
    activation = os.environ.get("ACTIVATION", "relu")
    label_scheme = os.environ.get("LABEL_SCHEME", "3class")
    epochs = int(os.environ.get("EPOCHS", "50"))
    lr = float(os.environ.get("LR", "1e-3"))
    seed = int(os.environ.get("SEED", "42"))
    data_path = os.environ.get("DATA_PATH")
    output_path = os.environ.get("OUTPUT_PATH", "reservoir_weights.safetensors")

    try:
        metrics = train_reservoir(
            data_path=data_path,
            hidden_dim=hidden_dim,
            bottleneck=bottleneck,
            num_classes=num_classes,
            activation=activation,
            epochs=epochs,
            lr=lr,
            label_scheme=label_scheme,
            seed=seed,
            output_path=output_path,
        )
    except Exception as e:
        print(f"METRIC error=1", file=sys.stdout)
        print(f"METRIC benchmark_exit_code=1", file=sys.stdout)
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

    # Emit METRIC lines for interlab
    for key, value in metrics.items():
        print(f"METRIC {key}={value:.4f}")
    print("METRIC benchmark_exit_code=0")

    # Also emit hyperparams as PARAM lines for campaign genealogy
    print(f"PARAM hidden_dim={hidden_dim}")
    print(f"PARAM bottleneck={bottleneck}")
    print(f"PARAM num_classes={num_classes}")
    print(f"PARAM activation={activation}")
    print(f"PARAM label_scheme={label_scheme}")
    print(f"PARAM epochs={epochs}")
    print(f"PARAM lr={lr}")
    print(f"PARAM seed={seed}")


if __name__ == "__main__":
    main()
