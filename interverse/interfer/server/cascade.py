"""Confidence cascade for multi-model inference routing.

Implements the "waterfall" pattern: start with the smallest model,
measure early-token confidence, escalate to larger models or cloud
if confidence is too low.

The cascade is the core mechanism that makes local-first routing practical.
It answers: "Is this model good enough for this specific request?"
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Generator

from .inference import InferenceEngine


class CascadeDecision(Enum):
    """Outcome of the confidence check."""

    ACCEPT = "accept"  # confidence >= accept_threshold
    ESCALATE = "escalate"  # confidence between cloud and accept thresholds
    CLOUD = "cloud"  # confidence < cloud_threshold


@dataclass
class CascadeConfig:
    """Configuration for the confidence cascade."""

    accept_threshold: float = 0.8
    escalate_threshold: float = 0.6
    cloud_threshold: float = 0.4
    probe_tokens: int = 3  # how many tokens to generate before deciding
    enabled: bool = True


@dataclass
class CascadeResult:
    """Result of a cascade generation attempt."""

    decision: CascadeDecision
    model_used: str
    probe_confidence: float  # average confidence over probe tokens
    probe_tokens: list[str]  # the tokens generated during probing
    probe_time_s: float
    models_tried: list[str] = field(default_factory=list)
    escalation_count: int = 0


@dataclass
class CascadeStats:
    """Running statistics for cascade decisions."""

    total_requests: int = 0
    accepts: int = 0
    escalations: int = 0
    cloud_fallbacks: int = 0
    total_probe_time_s: float = 0.0

    @property
    def accept_rate(self) -> float:
        return self.accepts / self.total_requests if self.total_requests else 0.0

    @property
    def escalation_rate(self) -> float:
        return self.escalations / self.total_requests if self.total_requests else 0.0

    @property
    def cloud_rate(self) -> float:
        return (
            self.cloud_fallbacks / self.total_requests if self.total_requests else 0.0
        )

    def to_dict(self) -> dict:
        return {
            "total_requests": self.total_requests,
            "accepts": self.accepts,
            "escalations": self.escalations,
            "cloud_fallbacks": self.cloud_fallbacks,
            "accept_rate": round(self.accept_rate, 3),
            "escalation_rate": round(self.escalation_rate, 3),
            "cloud_rate": round(self.cloud_rate, 3),
            "avg_probe_time_s": round(self.total_probe_time_s / self.total_requests, 4)
            if self.total_requests
            else 0.0,
        }


class ConfidenceCascade:
    """Multi-model confidence cascade.

    Usage::

        cascade = ConfidenceCascade(
            engine=engine,
            model_tiers=["local:qwen3.5-9b-4bit", "local:qwen3.5-35b-a3b-4bit"],
        )
        for token in cascade.generate(prompt="Write a function...", ...):
            print(token, end="")
        print(f"\\nUsed model: {cascade.last_result.model_used}")
    """

    def __init__(
        self,
        engine: InferenceEngine,
        model_tiers: list[str],
        config: CascadeConfig | None = None,
    ) -> None:
        self._engine = engine
        self._model_tiers = model_tiers
        self._config = config or CascadeConfig()
        self._stats = CascadeStats()
        self._last_result: CascadeResult | None = None

    @property
    def stats(self) -> CascadeStats:
        return self._stats

    @property
    def last_result(self) -> CascadeResult | None:
        return self._last_result

    def _probe_confidence(
        self,
        model_name: str,
        prompt: str,
        temperature: float,
    ) -> tuple[float, list[str], float]:
        """Generate probe_tokens tokens and return (avg_confidence, tokens, time_s).

        Returns the average max-softmax-probability over the probe window.
        """
        import mlx.core as mx

        probe_confidences: list[float] = []
        probe_tokens: list[str] = []
        t0 = time.perf_counter()

        for response in self._engine._raw_stream_generate(
            model_name=model_name,
            prompt=prompt,
            max_tokens=self._config.probe_tokens,
            temperature=temperature,
        ):
            if response.logprobs is not None:
                probs = mx.exp(response.logprobs)
                confidence = float(mx.max(probs))
                probe_confidences.append(confidence)
            if response.text:
                probe_tokens.append(response.text)

        elapsed = time.perf_counter() - t0
        avg_confidence = (
            sum(probe_confidences) / len(probe_confidences)
            if probe_confidences
            else 0.0
        )
        return avg_confidence, probe_tokens, elapsed

    def _decide(self, confidence: float) -> CascadeDecision:
        """Map a confidence score to a cascade decision."""
        if confidence >= self._config.accept_threshold:
            return CascadeDecision.ACCEPT
        if confidence >= self._config.cloud_threshold:
            return CascadeDecision.ESCALATE
        return CascadeDecision.CLOUD

    def generate(
        self,
        prompt: str,
        max_tokens: int = 512,
        temperature: float = 0.7,
        complexity_tier: str | None = None,
    ) -> Generator[str, None, None]:
        """Generate with confidence cascade.

        Probes the smallest eligible model first. If confidence is too low,
        escalates to larger models. If all local models fail, signals cloud
        fallback (yields nothing, sets last_result.decision = CLOUD).

        Yields decoded text segments (including probe tokens that were accepted).
        """
        if not self._config.enabled or not self._model_tiers:
            # Cascade disabled — use first model directly
            model = self._model_tiers[0] if self._model_tiers else ""
            yield from self._engine.generate(
                prompt=prompt,
                model_name=model,
                max_tokens=max_tokens,
                temperature=temperature,
            )
            return

        models_tried: list[str] = []
        self._stats.total_requests += 1

        for i, model_name in enumerate(self._model_tiers):
            models_tried.append(model_name)

            # Probe: generate a few tokens and measure confidence
            avg_confidence, probe_tokens, probe_time = self._probe_confidence(
                model_name=model_name,
                prompt=prompt,
                temperature=temperature,
            )

            decision = self._decide(avg_confidence)

            if decision == CascadeDecision.ACCEPT:
                # This model is confident enough. Yield probe tokens, then continue.
                self._stats.accepts += 1
                self._stats.total_probe_time_s += probe_time
                self._last_result = CascadeResult(
                    decision=decision,
                    model_used=model_name,
                    probe_confidence=round(avg_confidence, 4),
                    probe_tokens=probe_tokens,
                    probe_time_s=round(probe_time, 4),
                    models_tried=models_tried,
                    escalation_count=i,
                )

                # Yield probe tokens first
                for t in probe_tokens:
                    yield t

                # Continue generating remaining tokens with this model
                remaining = max_tokens - len(probe_tokens)
                if remaining > 0:
                    # Build continuation prompt (original + probe output)
                    continuation_prompt = prompt + "".join(probe_tokens)
                    yield from self._engine.generate(
                        prompt=continuation_prompt,
                        model_name=model_name,
                        max_tokens=remaining,
                        temperature=temperature,
                    )
                return

            if decision == CascadeDecision.ESCALATE:
                # Try the next larger model (if available)
                if i < len(self._model_tiers) - 1:
                    self._stats.escalations += 1
                    self._stats.total_probe_time_s += probe_time
                    continue  # try next model
                # Last model and still not confident — fall through to cloud

            # Cloud fallback
            self._stats.cloud_fallbacks += 1
            self._stats.total_probe_time_s += probe_time
            self._last_result = CascadeResult(
                decision=CascadeDecision.CLOUD,
                model_used="cloud",
                probe_confidence=round(avg_confidence, 4),
                probe_tokens=[],
                probe_time_s=round(probe_time, 4),
                models_tried=models_tried,
                escalation_count=i,
            )
            # Yield nothing — caller should route to cloud
            return
