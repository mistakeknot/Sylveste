"""MLX inference engine for interfere.

Runs inside the Metal subprocess — all MLX imports happen at method level
so this module can be safely imported by the main (HTTP) process without
touching the Metal GPU context.
"""

from __future__ import annotations

from typing import Generator


class InferenceEngine:
    """Thin wrapper around mlx-lm that manages model loading and generation.

    Models are lazily loaded on first use and cached for subsequent requests.
    """

    def __init__(self) -> None:
        self._models: dict[str, tuple] = {}  # model_name -> (model, tokenizer)

    def _ensure_loaded(self, model_name: str) -> None:
        """Load *model_name* via mlx-lm if not already cached."""
        if model_name in self._models:
            return

        import mlx.core as mx
        from mlx_lm import load

        model, tokenizer = load(model_name)
        mx.eval(model.parameters())
        self._models[model_name] = (model, tokenizer)

    def generate(
        self,
        prompt: str,
        model_name: str,
        max_tokens: int = 512,
        temperature: float = 0.7,
    ) -> Generator[str, None, None]:
        """Yield decoded text segments for *prompt*.

        Parameters
        ----------
        prompt:
            The user-facing prompt text.
        model_name:
            HuggingFace model identifier (e.g. ``mlx-community/Qwen2.5-0.5B-Instruct-4bit``).
        max_tokens:
            Maximum number of tokens to generate.
        temperature:
            Sampling temperature.

        Yields
        ------
        str
            Decoded text segments as they are produced.
        """
        from mlx_lm import stream_generate

        self._ensure_loaded(model_name)
        model, tokenizer = self._models[model_name]

        from mlx_lm.sample_utils import make_sampler

        sampler = make_sampler(temp=temperature)

        for response in stream_generate(
            model,
            tokenizer,
            prompt=prompt,
            max_tokens=max_tokens,
            sampler=sampler,
        ):
            if response.text:
                yield response.text
