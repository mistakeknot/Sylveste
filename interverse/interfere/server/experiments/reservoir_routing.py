"""Reservoir routing readout MLP for model selection.

A lightweight bottleneck MLP that maps a frozen reservoir's hidden state
to soft model-selection weights (probability distribution over available models).

Note: This module imports MLX at module level because it is only loaded inside
the Metal subprocess via lazy import in InferenceEngine._init_hooks(). The HTTP
main process never imports this module directly.
"""

from __future__ import annotations

import json
from pathlib import Path

import mlx.core as mx
import mlx.nn as nn


# Label registries — canonical source for label-to-index mapping.
CLASS_LABELS: dict[str, list[str]] = {
    "3class": ["small", "medium", "large"],
    "4class": ["coding", "reasoning", "creative", "factual"],
}


def _get_activation(name: str):
    """Return an MLX activation function by name."""
    mapping = {"relu": nn.relu, "gelu": nn.gelu, "silu": nn.silu}
    if name not in mapping:
        raise ValueError(f"Unknown activation {name!r}. Choose from: {list(mapping)}")
    return mapping[name]


class ReservoirReadout(nn.Module):
    """Bottleneck MLP that produces model-selection probabilities from hidden states.

    Architecture: hidden_dim -> bottleneck (activation) -> num_models (softmax for classify).
    The small bottleneck keeps the trainable parameter count minimal while the
    upstream reservoir (frozen LLM hidden layer) provides rich representations.
    """

    def __init__(
        self,
        hidden_dim: int = 4096,
        bottleneck: int = 64,
        num_models: int = 4,
        activation: str = "relu",
        class_labels: list[str] | None = None,
    ):
        super().__init__()
        self.fc1 = nn.Linear(hidden_dim, bottleneck)
        self.fc2 = nn.Linear(bottleneck, num_models)
        self.activation_fn = _get_activation(activation)
        self.activation_name = activation
        self.class_labels = class_labels
        self._hidden_dim = hidden_dim
        self._bottleneck = bottleneck

    def __call__(self, hidden_state: mx.array) -> mx.array:
        """Return raw logits over models.

        Args:
            hidden_state: Tensor of shape (..., hidden_dim).

        Returns:
            Logits of shape (..., num_models).
        """
        x = self.activation_fn(self.fc1(hidden_state))
        return self.fc2(x)

    def classify(self, hidden_state: mx.array) -> mx.array:
        """Return soft model-selection weights (probability distribution over models).

        Args:
            hidden_state: Tensor of shape (..., hidden_dim).

        Returns:
            Probabilities of shape (..., num_models) summing to 1 along the last axis.
        """
        logits = self(hidden_state)
        return mx.softmax(logits, axis=-1)

    def save_model(
        self, weights_path: str | Path, metadata_path: str | Path | None = None
    ) -> None:
        """Save weights and metadata sidecar."""
        weights_path = Path(weights_path)
        if metadata_path is None:
            metadata_path = weights_path.with_suffix(".json")

        self.save_weights(str(weights_path))
        metadata = {
            "hidden_dim": self._hidden_dim,
            "bottleneck": self._bottleneck,
            "num_models": self.fc2.weight.shape[0],
            "activation": self.activation_name,
            "class_labels": self.class_labels,
        }
        Path(metadata_path).write_text(json.dumps(metadata, indent=2))

    @classmethod
    def load_model(
        cls, weights_path: str | Path, metadata_path: str | Path | None = None
    ) -> ReservoirReadout:
        """Load weights and validate metadata."""
        weights_path = Path(weights_path)
        if metadata_path is None:
            metadata_path = weights_path.with_suffix(".json")

        metadata = json.loads(Path(metadata_path).read_text())
        model = cls(
            hidden_dim=metadata["hidden_dim"],
            bottleneck=metadata["bottleneck"],
            num_models=metadata["num_models"],
            activation=metadata["activation"],
            class_labels=metadata.get("class_labels"),
        )
        model.load_weights(str(weights_path))
        return model
