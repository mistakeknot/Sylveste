"""Reservoir routing readout MLP for model selection.

A lightweight bottleneck MLP that maps a frozen reservoir's hidden state
to soft model-selection weights (probability distribution over available models).
"""

import mlx.core as mx
import mlx.nn as nn


class ReservoirReadout(nn.Module):
    """Bottleneck MLP that produces model-selection probabilities from hidden states.

    Architecture: hidden_dim -> bottleneck (ReLU) -> num_models (softmax for classify).
    The small bottleneck keeps the trainable parameter count minimal while the
    upstream reservoir (frozen LLM hidden layer) provides rich representations.
    """

    def __init__(
        self,
        hidden_dim: int = 4096,
        bottleneck: int = 64,
        num_models: int = 4,
    ):
        super().__init__()
        self.fc1 = nn.Linear(hidden_dim, bottleneck)
        self.fc2 = nn.Linear(bottleneck, num_models)

    def __call__(self, hidden_state: mx.array) -> mx.array:
        """Return raw logits over models.

        Args:
            hidden_state: Tensor of shape (..., hidden_dim).

        Returns:
            Logits of shape (..., num_models).
        """
        x = nn.relu(self.fc1(hidden_state))
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
