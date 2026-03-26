"""Tests for reservoir routing readout MLP."""

import mlx.core as mx

from server.experiments.reservoir_routing import ReservoirReadout


def test_reservoir_readout_classifies():
    """ReservoirReadout.classify returns valid probability distribution."""
    readout = ReservoirReadout(hidden_dim=64, num_models=4)
    hidden = mx.random.normal((1, 64))

    probs = readout.classify(hidden)

    assert probs.shape == (1, 4), f"Expected shape (1, 4), got {probs.shape}"
    total = probs.sum(axis=-1).item()
    assert abs(total - 1.0) < 1e-5, f"Probabilities sum to {total}, expected ~1.0"
