"""Tests for training data generator."""

from __future__ import annotations

import tempfile
from pathlib import Path

from server.experiments.reservoir_routing import CLASS_LABELS
from server.experiments.training_data import (
    generate_training_data,
    load_jsonl,
    save_jsonl,
    split_data,
)


def test_generate_3class_count():
    data = generate_training_data(num_per_class=20, seed=1, label_scheme="3class")
    assert len(data) == 60


def test_generate_4class_count():
    data = generate_training_data(num_per_class=20, seed=1, label_scheme="4class")
    assert len(data) == 80


def test_labels_match_registry():
    for scheme in ["3class", "4class"]:
        data = generate_training_data(num_per_class=5, seed=1, label_scheme=scheme)
        labels = set(d["label"] for d in data)
        assert labels == set(CLASS_LABELS[scheme])


def test_label_ids_sequential():
    data = generate_training_data(num_per_class=5, seed=1, label_scheme="3class")
    for d in data:
        expected_id = CLASS_LABELS["3class"].index(d["label"])
        assert d["label_id"] == expected_id


def test_jsonl_roundtrip():
    data = generate_training_data(num_per_class=5, seed=1)
    with tempfile.NamedTemporaryFile(suffix=".jsonl", delete=False) as f:
        path = f.name
    save_jsonl(data, path)
    loaded = load_jsonl(path)
    assert loaded == data
    Path(path).unlink()


def test_split_preserves_all():
    data = generate_training_data(num_per_class=10, seed=1)
    train, test = split_data(data)
    assert len(train) + len(test) == len(data)


def test_prompts_are_diverse():
    """No two prompts should be identical (with enough per class)."""
    data = generate_training_data(num_per_class=50, seed=42, label_scheme="4class")
    prompts = [d["prompt"] for d in data]
    unique = set(prompts)
    # Allow small number of collisions due to template/subject overlap
    assert (
        len(unique) > len(prompts) * 0.9
    ), f"Only {len(unique)}/{len(prompts)} unique prompts — too many duplicates"
