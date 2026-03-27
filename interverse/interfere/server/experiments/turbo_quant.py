"""TurboQuant: Polar-transformed KV cache quantization experiment.

Implements PolarQuant coordinate transformation for KV cache tensors.
The core idea: convert K/V vectors to polar coordinates before quantization
so that MLX's native quantizer operates on a distribution (bounded angles,
non-negative radii) that may compress with lower error than raw Cartesian K/V.

Integration path: wrap attention layers to apply polar_transform before cache
storage and inverse_polar_transform after cache retrieval. The cache itself
uses mlx-lm's existing QuantizedKVCache with its fused attention kernel.

References:
  - TurboQuant (ICLR 2026, arxiv.org/abs/2504.19874)
  - PolarQuant (AISTATS 2026, arxiv.org/abs/2502.02617)

Note: This module imports MLX at module level because it is only loaded inside
the Metal subprocess via lazy import in InferenceEngine. The HTTP main process
never imports this module directly.
"""

from __future__ import annotations

from typing import Any

import mlx.core as mx


# ---------------------------------------------------------------------------
# Polar transform primitives
# ---------------------------------------------------------------------------


def polar_transform(tensor: mx.array) -> mx.array:
    """Convert tensor from Cartesian to polar representation.

    Pairs adjacent dimensions: (x0, x1), (x2, x3), ... -> (r0, theta0), (r1, theta1), ...
    Returns same shape — even-indexed dims become radii, odd-indexed become
    normalized angles in [0, 1] for better quantization distribution.

    Computation is done in float32 for trig precision (P1-3 from review).

    Args:
        tensor: shape (..., head_dim) where head_dim is even.

    Returns:
        Polar-transformed tensor of same shape and dtype.
    """
    orig_dtype = tensor.dtype
    t = tensor.astype(mx.float32)
    *batch, d = t.shape
    t = t.reshape(*batch, d // 2, 2)
    x, y = t[..., 0], t[..., 1]
    r = mx.sqrt(x * x + y * y)
    theta = mx.arctan2(y, x)  # [-pi, pi]
    # Normalize theta to [0, 1] for uniform quantization distribution
    theta_norm = (theta + mx.array(3.141592653589793)) / mx.array(2 * 3.141592653589793)
    result = mx.stack([r, theta_norm], axis=-1).reshape(*batch, d)
    return result.astype(orig_dtype)


def inverse_polar_transform(tensor: mx.array) -> mx.array:
    """Convert tensor from polar representation back to Cartesian.

    Reverses polar_transform: even-indexed dims are radii, odd-indexed are
    normalized angles in [0, 1].

    Args:
        tensor: shape (..., head_dim) in polar representation.

    Returns:
        Cartesian tensor of same shape and dtype.
    """
    orig_dtype = tensor.dtype
    t = tensor.astype(mx.float32)
    *batch, d = t.shape
    t = t.reshape(*batch, d // 2, 2)
    r, theta_norm = t[..., 0], t[..., 1]
    theta = theta_norm * mx.array(2 * 3.141592653589793) - mx.array(3.141592653589793)
    x = r * mx.cos(theta)
    y = r * mx.sin(theta)
    result = mx.stack([x, y], axis=-1).reshape(*batch, d)
    return result.astype(orig_dtype)


# ---------------------------------------------------------------------------
# QJL residual correction
# ---------------------------------------------------------------------------


def make_jl_projection(jl_dim: int, head_dim: int, seed: int) -> mx.array:
    """Create a seeded random Gaussian projection matrix for QJL.

    Args:
        jl_dim: Number of projection dimensions.
        head_dim: Dimension of the head vectors to project.
        seed: Random seed for reproducibility (typically layer_idx).

    Returns:
        Projection matrix of shape (jl_dim, head_dim), float32.
    """
    key = mx.random.key(seed)
    # Unscaled Gaussian — scaling handled in encode/decode
    return mx.random.normal(shape=(jl_dim, head_dim), key=key)


def qjl_encode(residual: mx.array, projection: mx.array) -> mx.array:
    """1-bit Johnson-Lindenstrauss encoding: sign(projection @ residual).

    Uses the standard 1-bit CS formula: bits_i = sign(sum_j P_ij * x_j).

    Args:
        residual: (..., head_dim) — quantization residual to compress.
        projection: (jl_dim, head_dim) — random Gaussian projection matrix.

    Returns:
        bits: (..., jl_dim) as int8 with values +1 or -1.
    """
    # (..., head_dim) @ (head_dim, jl_dim) -> (..., jl_dim)
    projected = residual.astype(mx.float32) @ projection.T
    return mx.where(
        projected >= 0, mx.array(1, dtype=mx.int8), mx.array(-1, dtype=mx.int8)
    )


def qjl_decode(bits: mx.array, projection: mx.array) -> mx.array:
    """Reconstruct approximate residual from 1-bit JL encoding.

    Uses: x_hat = (1/jl_dim) * P^T @ bits, which is the standard unbiased
    estimator (up to a sqrt(2/pi) constant) for the 1-bit sketch.

    Args:
        bits: (..., jl_dim) int8 values of +1/-1.
        projection: (jl_dim, head_dim) — same projection matrix used to encode.

    Returns:
        Approximate residual of shape (..., head_dim), float32.
    """
    jl_dim = projection.shape[0]
    # (..., jl_dim) @ (jl_dim, head_dim) -> (..., head_dim)
    return (bits.astype(mx.float32) @ projection) / jl_dim


# ---------------------------------------------------------------------------
# Cache wrapper — polar transform around any mlx-lm cache
# ---------------------------------------------------------------------------


class PolarCacheWrapper:
    """Wraps an mlx-lm cache to apply polar transform on K/V before storage.

    This is model-agnostic: it wraps any cache object and intercepts
    update_and_fetch to transform K/V to polar coords before the underlying
    cache quantizes them, then inverse-transforms on retrieval.

    The underlying cache (e.g., QuantizedKVCache at 4-bit) handles storage
    and its fused attention kernel handles decompression — no custom
    dequantize-on-fetch needed.
    """

    def __init__(self, inner_cache: Any):
        self._inner = inner_cache

    def update_and_fetch(
        self, keys: mx.array, values: mx.array
    ) -> tuple[mx.array, mx.array]:
        # Transform to polar before cache stores (and quantizes)
        polar_keys = polar_transform(keys)
        polar_values = polar_transform(values)
        # Inner cache stores quantized polar representation
        cached_keys, cached_values = self._inner.update_and_fetch(
            polar_keys, polar_values
        )
        # Inverse transform after cache retrieval (possibly dequantized by fused kernel)
        return inverse_polar_transform(cached_keys), inverse_polar_transform(
            cached_values
        )

    # Delegate all other attributes to the inner cache
    def __getattr__(self, name: str) -> Any:
        return getattr(self._inner, name)


def wrap_prompt_cache(
    prompt_cache: list[Any],
) -> list[PolarCacheWrapper]:
    """Wrap each layer's cache with polar transform."""
    return [PolarCacheWrapper(c) for c in prompt_cache]
