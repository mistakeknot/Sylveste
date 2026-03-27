"""MLX inference engine for interfere.

Runs inside the Metal subprocess — all MLX imports happen at method level
so this module can be safely imported by the main (HTTP) process without
touching the Metal GPU context.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Generator

from .experiments.config import ExperimentConfig


@dataclass
class GenerationMetrics:
    """Per-generation metrics collected from experiment hooks."""

    tokens_generated: int = 0
    early_exit_triggers: int = 0
    early_exit_rate: float = 0.0
    max_confidence: float = 0.0
    min_confidence: float = 1.0
    mean_confidence: float = 0.0
    routing_probs: dict[str, float] = field(default_factory=dict)
    prompt_tps: float = 0.0
    generation_tps: float = 0.0
    peak_memory_gb: float = 0.0
    kv_bits: int | None = None
    kv_mode: str | None = None  # "turbo_quant" when polar transform active


class InferenceEngine:
    """MLX-LM inference with experiment hook integration.

    Models are lazily loaded on first use and cached for subsequent requests.
    Experiment hooks are called during generation when enabled.
    """

    def __init__(
        self,
        experiment_configs: dict[str, ExperimentConfig] | None = None,
    ) -> None:
        self._models: dict[str, tuple] = {}  # model_name -> (model, tokenizer)
        self._experiment_configs = experiment_configs or {}
        self._early_exit_hook: Any | None = None
        self._reservoir_hook: Any | None = None
        self._last_metrics: GenerationMetrics | None = None
        self._init_hooks()

    def _init_hooks(self) -> None:
        """Initialize experiment hooks based on config."""
        early_cfg = self._experiment_configs.get("early_exit")
        if early_cfg and early_cfg.enabled:
            from .experiments.early_exit import EarlyExitHook

            self._early_exit_hook = EarlyExitHook(
                threshold=early_cfg.get("threshold", 0.95),
                enabled=True,
            )

        self._reservoir_cfg: ExperimentConfig | None = None
        reservoir_cfg = self._experiment_configs.get("reservoir_routing")
        if reservoir_cfg and reservoir_cfg.enabled:
            from .experiments.reservoir_routing import CLASS_LABELS, ReservoirReadout

            num_models = int(reservoir_cfg.get("num_models", 4))
            label_scheme = reservoir_cfg.get("label_scheme", "4class")
            class_labels = CLASS_LABELS.get(label_scheme)

            self._reservoir_cfg = reservoir_cfg
            self._reservoir_hook = ReservoirReadout(
                hidden_dim=int(reservoir_cfg.get("hidden_dim", 4096)),
                bottleneck=int(reservoir_cfg.get("bottleneck", 64)),
                num_models=num_models,
                activation=reservoir_cfg.get("activation", "relu"),
                class_labels=class_labels,
            )

        # TurboQuant: polar-transformed KV cache quantization
        self._turbo_quant_cfg: ExperimentConfig | None = None
        tq_cfg = self._experiment_configs.get("turbo_quant")
        if tq_cfg and tq_cfg.enabled:
            self._turbo_quant_cfg = tq_cfg

    @property
    def last_metrics(self) -> GenerationMetrics | None:
        """Metrics from the most recent generate() call."""
        return self._last_metrics

    @property
    def hook_stats(self) -> dict[str, Any]:
        """Current stats from all active hooks."""
        stats: dict[str, Any] = {}
        if self._early_exit_hook is not None:
            stats["early_exit"] = {
                "enabled": self._early_exit_hook.enabled,
                "threshold": self._early_exit_hook.threshold,
                "exit_rate": self._early_exit_hook.exit_rate,
            }
        if self._reservoir_hook is not None:
            stats["reservoir_routing"] = {"enabled": True}
        if self._turbo_quant_cfg is not None and self._turbo_quant_cfg.enabled:
            stats["turbo_quant"] = {
                "enabled": True,
                "kv_bits": int(self._turbo_quant_cfg.get("kv_bits", 4)),
            }
        return stats

    def _extract_hidden_state(self, model, tokens, tap_layer: int = 24):
        """Run partial forward pass and return last-token hidden state at tap_layer.

        Args:
            model: mlx-lm Model object (has model.model.layers).
            tokens: Tokenized prompt as mx.array of shape (1, seq_len).
            tap_layer: Which transformer layer to tap (1-indexed from top).

        Returns:
            Hidden state tensor of shape (1, hidden_dim).

        Raises:
            ValueError: If tap_layer exceeds model depth.
        """
        import mlx.core as mx
        from mlx_lm.models.cache import make_prompt_cache

        # make_prompt_cache allocates fresh KV cache per call — these entries are
        # local to this partial pass and do not affect stream_generate's own cache.
        num_layers = len(model.model.layers)
        if tap_layer > num_layers:
            raise ValueError(
                f"tap_layer={tap_layer} exceeds model depth ({num_layers} layers)"
            )

        h = model.model.embed_tokens(tokens)
        cache = make_prompt_cache(model)

        for i in range(tap_layer):
            h = model.model.layers[i](h, mask=None, cache=cache[i])

        # Last token attends to all prior tokens in causal models
        hidden = h[:, -1:, :]  # (1, 1, hidden_dim) -> squeeze to (1, hidden_dim)
        hidden = hidden.squeeze(1)
        mx.eval(hidden)  # Materialize before returning to prevent graph bleed
        return hidden

    def _ensure_loaded(self, model_name: str) -> None:
        """Load *model_name* via mlx-lm if not already cached."""
        if model_name in self._models:
            return

        import mlx.core as mx
        from mlx_lm import load

        model, tokenizer = load(model_name)
        mx.eval(model.parameters())
        self._models[model_name] = (model, tokenizer)

    def _raw_stream_generate(
        self,
        model_name: str,
        prompt: str,
        max_tokens: int = 512,
        temperature: float = 0.7,
    ) -> Generator[Any, None, None]:
        """Yield raw GenerationResponse objects from mlx-lm.

        Exposes logprobs, token IDs, and generation stats for use by the
        confidence cascade and other experiment hooks that need per-token
        metadata beyond just text.
        """
        from mlx_lm import stream_generate
        from mlx_lm.sample_utils import make_sampler

        self._ensure_loaded(model_name)
        model, tokenizer = self._models[model_name]
        sampler = make_sampler(temp=temperature)

        yield from stream_generate(
            model,
            tokenizer,
            prompt=prompt,
            max_tokens=max_tokens,
            sampler=sampler,
        )

    def generate(
        self,
        prompt: str,
        model_name: str,
        max_tokens: int = 512,
        temperature: float = 0.7,
        kv_bits: int | None = None,
        kv_group_size: int = 64,
        max_kv_size: int | None = None,
        draft_model_name: str | None = None,
        num_draft_tokens: int = 3,
    ) -> Generator[str, None, None]:
        """Yield decoded text segments for *prompt*.

        Parameters
        ----------
        prompt:
            The user-facing prompt text.
        model_name:
            HuggingFace model identifier or local path.
        max_tokens:
            Maximum number of tokens to generate.
        temperature:
            Sampling temperature.
        kv_bits:
            If set, quantize the KV cache to this many bits (2, 4, or 8).
        kv_group_size:
            Group size for KV cache quantization. Default: 64.
        max_kv_size:
            Maximum KV cache entries. Enables rotating cache (StreamingLLM).
        draft_model_name:
            If set, use speculative decoding with this model as the draft.
            Must use the same tokenizer as the target model.
        num_draft_tokens:
            Number of tokens to draft per step. Default: 3.

        Yields
        ------
        str
            Decoded text segments as they are produced.
        """
        import mlx.core as mx
        from mlx_lm import stream_generate
        from mlx_lm.sample_utils import make_sampler

        self._ensure_loaded(model_name)
        model, tokenizer = self._models[model_name]

        sampler = make_sampler(temp=temperature)

        # Reset hook stats for this generation
        if self._early_exit_hook is not None:
            self._early_exit_hook.reset_stats()

        # Build kwargs for generate_step (passed through stream_generate)
        gen_kwargs: dict[str, Any] = {}

        # --- Experiment: TurboQuant rotation-based KV cache ---
        if self._turbo_quant_cfg is not None and self._turbo_quant_cfg.enabled:
            if kv_bits is not None:
                raise ValueError(
                    "Cannot set kv_bits when turbo_quant is enabled. "
                    "Configure kv_bits in turbo_quant experiment config instead."
                )
            from .experiments.turbo_quant import (
                install_turbo_quant_attention,
                wrap_prompt_cache_turbo,
            )

            tq_kv_bits = int(self._turbo_quant_cfg.get("kv_bits", 4))
            tq_group_size = int(self._turbo_quant_cfg.get("kv_group_size", 64))
            tq_rotate_values = bool(self._turbo_quant_cfg.get("rotate_values", False))
            tq_seed = int(self._turbo_quant_cfg.get("rotation_seed", 0))
            # Derive head_dim from model config
            model_args = model.args if hasattr(model, "args") else model.model.args
            head_dim = model_args.hidden_size // model_args.num_attention_heads
            # Pre-quantize caches before wrapping — avoids issues with
            # maybe_quantize_kv_cache trying to convert wrapped caches.
            from mlx_lm.models.cache import make_prompt_cache

            raw_cache = make_prompt_cache(model, max_kv_size)
            quantized_cache = [
                c.to_quantized(group_size=tq_group_size, bits=tq_kv_bits)
                for c in raw_cache
            ]
            wrapped_cache, pi = wrap_prompt_cache_turbo(
                quantized_cache,
                head_dim=head_dim,
                seed=tq_seed,
                rotate_values=tq_rotate_values,
            )
            gen_kwargs["prompt_cache"] = wrapped_cache
            install_turbo_quant_attention(pi)
        elif kv_bits is not None:
            gen_kwargs["kv_bits"] = kv_bits
            gen_kwargs["kv_group_size"] = kv_group_size

        if max_kv_size is not None:
            gen_kwargs["max_kv_size"] = max_kv_size

        # Speculative decoding: load draft model if requested
        draft_model_obj = None
        if draft_model_name is not None:
            self._ensure_loaded(draft_model_name)
            draft_model_obj, _ = self._models[draft_model_name]
            gen_kwargs["num_draft_tokens"] = num_draft_tokens

        # Track confidence across generation
        confidences: list[float] = []
        effective_kv_bits = (
            int(self._turbo_quant_cfg.get("kv_bits", 4))
            if self._turbo_quant_cfg and self._turbo_quant_cfg.enabled
            else kv_bits
        )
        metrics = GenerationMetrics(
            kv_bits=effective_kv_bits,
            kv_mode="turbo_quant"
            if self._turbo_quant_cfg and self._turbo_quant_cfg.enabled
            else None,
        )

        # --- Experiment hook: reservoir routing classification ---
        if self._reservoir_hook is not None and self._reservoir_cfg is not None:
            tokens = mx.array(tokenizer.encode(prompt))[None]
            tap_layer = int(self._reservoir_cfg.get("layer", 24))
            hidden = self._extract_hidden_state(model, tokens, tap_layer)
            probs = self._reservoir_hook.classify(hidden)
            mx.eval(probs)
            labels = self._reservoir_hook.class_labels or [
                f"model_{i}" for i in range(probs.shape[-1])
            ]
            metrics.routing_probs = {
                label: float(probs[0, i]) for i, label in enumerate(labels)
            }

        for response in stream_generate(
            model,
            tokenizer,
            prompt=prompt,
            max_tokens=max_tokens,
            sampler=sampler,
            draft_model=draft_model_obj,
            **gen_kwargs,
        ):
            # --- Experiment hook: early exit confidence tracking ---
            if self._early_exit_hook is not None and response.logprobs is not None:
                # logprobs are log-probabilities; convert to probabilities for confidence
                probs = mx.exp(response.logprobs)
                confidence = float(mx.max(probs))
                confidences.append(confidence)

                should_exit, _ = self._early_exit_hook.check(response.logprobs)
                if should_exit:
                    metrics.early_exit_triggers += 1
                    # Note: actual layer skipping requires model-level integration.
                    # For now, we track the signal for calibration.

            # Capture generation stats from response
            metrics.prompt_tps = response.prompt_tps
            metrics.generation_tps = response.generation_tps
            metrics.peak_memory_gb = response.peak_memory
            metrics.tokens_generated = response.generation_tokens

            if response.text:
                yield response.text

        # Finalize metrics
        if confidences:
            metrics.max_confidence = max(confidences)
            metrics.min_confidence = min(confidences)
            metrics.mean_confidence = sum(confidences) / len(confidences)
        if self._early_exit_hook is not None:
            metrics.early_exit_rate = self._early_exit_hook.exit_rate

        self._last_metrics = metrics
