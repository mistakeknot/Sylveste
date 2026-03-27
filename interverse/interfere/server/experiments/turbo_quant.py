"""TurboQuant: Polar-transformed KV cache quantization experiment.

RESULT: NEGATIVE — polar transform INCREASES quantization error by ~19% (4-bit)
and the inverse trigonometric transform further AMPLIFIES that error by ~2.7x.
The approach produces garbage output at all bit widths (2, 4, 8) with quantized
KV cache. Only works correctly with fp16 (non-quantized) cache.

Root cause: angle quantization error δθ becomes Cartesian error r * sin(δθ) —
proportional to the radius. High-radius vectors (most important for attention)
suffer the most. This is a fundamental mathematical limitation, not fixable by
layout or bit allocation changes.

The core idea was: convert K/V vectors to polar coordinates before quantization
so that MLX's native quantizer operates on a distribution (bounded angles,
non-negative radii) that may compress with lower error than raw Cartesian K/V.
In practice, Cartesian K/V (centered, symmetric, Gaussian-like) is already
near-optimal for symmetric quantization, and polar coordinates waste codebook
capacity on the strictly-positive radius distribution.

Iteration log:
  1. Original PolarCacheWrapper: called inverse_polar_transform on quantized
     tuples (data, scales, biases) — structurally broken, never worked.
  2. Fixed dequantize-then-inverse: correct structure, but 3.1x worse error
     due to interleaved r/θ layout mixing distributions within quant groups.
  3. Contiguous layout [radii|angles]: reduced to 1.19x worse (4-bit), but
     still produces garbage output due to 2.7x error amplification through
     inverse trigonometric transform.

Kept for reference and to prevent re-derivation of the same dead end.

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

    Pairs adjacent dimensions: (x0, x1), (x2, x3), ...
    Output layout: [r0, r1, ..., r_{d/2-1}, theta0, theta1, ..., theta_{d/2-1}]
    Radii and angles are stored in contiguous halves (not interleaved) so that
    each quantization group contains a single distribution type.
    Angles are normalized to [0, 1].

    Computation is done in float32 for trig precision.

    Args:
        tensor: shape (..., head_dim) where head_dim is even.

    Returns:
        Polar-transformed tensor of same shape and dtype.
    """
    orig_dtype = tensor.dtype
    t = tensor.astype(mx.float32)
    *batch, d = t.shape
    half = d // 2
    t = t.reshape(*batch, half, 2)
    x, y = t[..., 0], t[..., 1]
    r = mx.sqrt(x * x + y * y)
    theta = mx.arctan2(y, x)  # [-pi, pi]
    # Normalize theta to [0, 1] for uniform quantization distribution
    theta_norm = (theta + mx.array(3.141592653589793)) / mx.array(2 * 3.141592653589793)
    # Contiguous layout: [all radii | all angles] — not interleaved
    result = mx.concatenate([r, theta_norm], axis=-1)
    return result.astype(orig_dtype)


def inverse_polar_transform(tensor: mx.array) -> mx.array:
    """Convert tensor from polar representation back to Cartesian.

    Reverses polar_transform: first half of last dim is radii, second half
    is normalized angles in [0, 1].

    Args:
        tensor: shape (..., head_dim) in polar representation.

    Returns:
        Cartesian tensor of same shape and dtype.
    """
    orig_dtype = tensor.dtype
    t = tensor.astype(mx.float32)
    *batch, d = t.shape
    half = d // 2
    r = t[..., :half]
    theta_norm = t[..., half:]
    theta = theta_norm * mx.array(2 * 3.141592653589793) - mx.array(3.141592653589793)
    x = r * mx.cos(theta)
    y = r * mx.sin(theta)
    # Interleave back: (x0, y0, x1, y1, ...)
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

    Polar transform converts K/V vectors to (radius, angle) pairs before
    quantization. The bounded ranges (radius >= 0, angle in [0,1]) may
    quantize with lower error than unbounded Cartesian values.

    On retrieval, the quantized polar data is dequantized and inverse-
    transformed back to Cartesian coordinates. This means we cannot use
    the fused quantized attention kernel — we explicitly hide the `bits`
    attribute so `scaled_dot_product_attention` takes the standard
    (non-quantized) path with our dequantized Cartesian tensors.
    """

    def __init__(self, inner_cache: Any):
        self._inner = inner_cache

    def update_and_fetch(
        self, keys: mx.array, values: mx.array
    ) -> tuple[mx.array, mx.array]:
        # Transform to polar before cache stores (and quantizes)
        polar_keys = polar_transform(keys)
        polar_values = polar_transform(values)
        # Inner cache stores quantized polar representation.
        # For QuantizedKVCache this returns (data, scales, biases) tuples.
        q_keys, q_values = self._inner.update_and_fetch(polar_keys, polar_values)
        # Dequantize and inverse-transform back to Cartesian
        return (
            self._dequantize_and_inverse(q_keys),
            self._dequantize_and_inverse(q_values),
        )

    def _dequantize_and_inverse(
        self, quantized: tuple[mx.array, mx.array, mx.array] | mx.array
    ) -> mx.array:
        """Dequantize a quantized tuple and apply inverse polar transform."""
        if isinstance(quantized, tuple):
            # (data_uint32, scales, biases) from QuantizedKVCache
            data, scales, biases = quantized
            group_size = self._inner.group_size
            bits = self._inner.bits
            tensor = mx.dequantize(data, scales, biases, group_size, bits)
        else:
            # Plain tensor from non-quantized cache
            tensor = quantized
        return inverse_polar_transform(tensor)

    def __getattr__(self, name: str) -> Any:
        # Hide 'bits' and 'group_size' so scaled_dot_product_attention
        # takes the standard (non-fused) path with our plain tensors.
        if name in ("bits", "group_size"):
            raise AttributeError(name)
        return getattr(self._inner, name)


def wrap_prompt_cache(
    prompt_cache: list[Any],
) -> list[PolarCacheWrapper]:
    """Wrap each layer's cache with polar transform."""
    return [PolarCacheWrapper(c) for c in prompt_cache]
