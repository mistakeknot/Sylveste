"""Entropy-based early exit hook for the inference pipeline."""

import mlx.core as mx


class EarlyExitHook:
    """Decides whether to exit generation early based on token confidence.

    When the model is highly confident in its next-token prediction
    (softmax probability exceeds *threshold*), downstream layers can be
    skipped to save compute.
    """

    def __init__(self, threshold: float = 0.95, enabled: bool = True) -> None:
        self.threshold = threshold
        self.enabled = enabled
        self._exit_count = 0
        self._total_count = 0

    def check(self, logits: mx.array) -> tuple[bool, float]:
        """Evaluate whether early exit is warranted for *logits*.

        Returns a ``(should_exit, confidence)`` tuple where *confidence*
        is the maximum softmax probability across the vocabulary.
        """
        probs = mx.softmax(logits, axis=-1)
        confidence = float(mx.max(probs))

        self._total_count += 1
        should_exit = self.enabled and confidence > self.threshold
        if should_exit:
            self._exit_count += 1

        return should_exit, confidence

    @property
    def exit_rate(self) -> float:
        """Fraction of checks that triggered an early exit."""
        if self._total_count == 0:
            return 0.0
        return self._exit_count / self._total_count

    def reset_stats(self) -> None:
        """Zero both counters."""
        self._exit_count = 0
        self._total_count = 0
