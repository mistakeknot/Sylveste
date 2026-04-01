"""Tests for the entropy-based early exit hook."""

import mlx.core as mx

from server.experiments.early_exit import EarlyExitHook


def test_early_exit_hook_computes_confidence():
    """A dominant logit should produce high confidence and trigger exit."""
    hook = EarlyExitHook(threshold=0.95)

    # One very strong logit among zeros -> softmax concentrates mass there.
    logits = mx.zeros((1, 100))
    logits = logits.at[0, 42].add(10.0)

    should_exit, confidence = hook.check(logits)

    assert should_exit is True
    assert confidence > 0.9


def test_early_exit_hook_rejects_low_confidence():
    """Uniform logits should produce low confidence and not trigger exit."""
    hook = EarlyExitHook(threshold=0.95)

    # All ones -> uniform softmax -> confidence = 1/vocab_size.
    logits = mx.ones((1, 100))

    should_exit, confidence = hook.check(logits)

    assert should_exit is False
    assert confidence < 0.5
