"""TurboQuant: KV cache quantization experiments.

RESULT: NEGATIVE for both approaches tested with MLX's native quantization.

Approach 1 — Polar coordinates (PolarCacheWrapper):
  Inverse trig amplifies quantization error by 2.7x. Garbage at all bit widths.

Approach 2 — Orthogonal rotation (TurboQuantCacheWrapper):
  Mathematically correct (dot product preserved, fp16 path perfect).
  Per-element K quantization error reduced by 7%.
  Attention score error reduced by 8%.
  BUT: final attention output is 1.3x worse via manual dequant and 5x worse
  via fused mx.quantized_matmul kernel. The fused kernel has distribution-
  dependent precision optimizations that the rotation disrupts. And the
  paper's benefit comes from Lloyd-Max centroids specifically tuned to the
  post-rotation Beta distribution — MLX's affine quantizer (uniform grid +
  scale + bias) doesn't get significant benefit from the rotation.

To actually implement TurboQuant would require:
  1. Custom Lloyd-Max quantizer (non-uniform centroids for Beta distribution)
  2. Custom attention kernel (can't use mx.quantized_matmul with non-affine quant)
  3. ~3-5x more implementation effort

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
# Rotation primitives (TurboQuant core)
# ---------------------------------------------------------------------------


def make_rotation_matrix(head_dim: int, seed: int = 0) -> mx.array:
    """Generate a random orthogonal rotation matrix via QR decomposition.

    The Q factor of QR(Normal(0,1)^{d×d}) is a Haar-distributed random
    orthogonal matrix, which is exactly what TurboQuant requires.

    Args:
        head_dim: Dimension of the head vectors (d).
        seed: Random seed for reproducibility.

    Returns:
        Orthogonal matrix Π of shape (head_dim, head_dim), float32.
        Satisfies Π·Π^T = I.
    """
    key = mx.random.key(seed)
    A = mx.random.normal(shape=(head_dim, head_dim), key=key)
    # QR decomposition must run on CPU in MLX
    Q, _R = mx.linalg.qr(A, stream=mx.cpu)
    mx.eval(Q)
    return Q


def rotate(x: mx.array, pi: mx.array) -> mx.array:
    """Apply rotation: x_rot = x @ Π^T (equivalent to Π @ x per-vector).

    Args:
        x: (..., head_dim) tensor to rotate.
        pi: (head_dim, head_dim) orthogonal rotation matrix.

    Returns:
        Rotated tensor of same shape and dtype.
    """
    return x @ pi.T


def rotate_inverse(x: mx.array, pi: mx.array) -> mx.array:
    """Apply inverse rotation: x_orig = x @ Π (since Π^{-1} = Π^T).

    Args:
        x: (..., head_dim) rotated tensor.
        pi: (head_dim, head_dim) orthogonal rotation matrix.

    Returns:
        Tensor rotated back to original space, same shape and dtype.
    """
    return x @ pi


# ---------------------------------------------------------------------------
# QJL residual correction (Phase 2, shared with rotation approach)
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
    return mx.random.normal(shape=(jl_dim, head_dim), key=key)


def qjl_encode(residual: mx.array, projection: mx.array) -> mx.array:
    """1-bit Johnson-Lindenstrauss encoding: sign(projection @ residual).

    Args:
        residual: (..., head_dim) — quantization residual to compress.
        projection: (jl_dim, head_dim) — random Gaussian projection matrix.

    Returns:
        bits: (..., jl_dim) as int8 with values +1 or -1.
    """
    projected = residual.astype(mx.float32) @ projection.T
    return mx.where(
        projected >= 0, mx.array(1, dtype=mx.int8), mx.array(-1, dtype=mx.int8)
    )


def qjl_decode(bits: mx.array, projection: mx.array) -> mx.array:
    """Reconstruct approximate residual from 1-bit JL encoding.

    Args:
        bits: (..., jl_dim) int8 values of +1/-1.
        projection: (jl_dim, head_dim) — same projection matrix used to encode.

    Returns:
        Approximate residual of shape (..., head_dim), float32.
    """
    jl_dim = projection.shape[0]
    return (bits.astype(mx.float32) @ projection) / jl_dim


# ---------------------------------------------------------------------------
# Cache wrapper — orthogonal rotation around any mlx-lm cache
# ---------------------------------------------------------------------------


class TurboQuantCacheWrapper:
    """Wraps an mlx-lm cache to apply orthogonal rotation on K before storage.

    The rotation concentrates coordinate distributions for better quantization.
    Since Π is orthogonal, Q·K^T = (Q·Π^T)·(K·Π^T)^T, so we rotate Q at
    attention time (via install_turbo_quant_attention) and the fused kernel
    computes correct attention scores on rotated data.

    Unlike the failed PolarCacheWrapper, this wrapper:
    - DOES expose bits/group_size (fused kernel path is used)
    - Does NOT dequantize or inverse-transform on retrieval
    - Only transforms K on storage; Q is transformed at attention time
    """

    def __init__(self, inner_cache: Any, pi: mx.array, rotate_values: bool = False):
        self._inner = inner_cache
        self._pi = pi
        self._rotate_values = rotate_values

    def update_and_fetch(self, keys: mx.array, values: mx.array) -> tuple[Any, Any]:
        rotated_keys = rotate(keys, self._pi)
        rotated_values = rotate(values, self._pi) if self._rotate_values else values
        return self._inner.update_and_fetch(rotated_keys, rotated_values)

    def to_quantized(
        self, group_size: int = 64, bits: int = 4
    ) -> "TurboQuantCacheWrapper":
        """Delegate quantization to inner cache, re-wrap the result."""
        if not hasattr(self._inner, "to_quantized"):
            return self  # inner already quantized
        new_inner = self._inner.to_quantized(group_size, bits)
        return TurboQuantCacheWrapper(new_inner, self._pi, self._rotate_values)

    def __getattr__(self, name: str) -> Any:
        return getattr(self._inner, name)


def wrap_prompt_cache_turbo(
    prompt_cache: list[Any],
    head_dim: int,
    seed: int = 0,
    rotate_values: bool = False,
) -> tuple[list[TurboQuantCacheWrapper], mx.array]:
    """Wrap each layer's cache with orthogonal rotation.

    Returns the wrapped cache list and the rotation matrix (needed for Q
    rotation at attention time via install_turbo_quant_attention).
    """
    pi = make_rotation_matrix(head_dim, seed)
    wrapped = [
        TurboQuantCacheWrapper(c, pi, rotate_values=rotate_values) for c in prompt_cache
    ]
    return wrapped, pi


# ---------------------------------------------------------------------------
# Attention monkey-patch for Q rotation
# ---------------------------------------------------------------------------

_original_sdpa: Any = None


def install_turbo_quant_attention(pi: mx.array) -> None:
    """Monkey-patch scaled_dot_product_attention to rotate Q vectors.

    When K vectors are stored rotated by Π in the cache, Q must also be
    rotated so that Q_rot · K_rot^T = Q · K^T.

    This patches mlx_lm.models.base.scaled_dot_product_attention, which
    all model implementations import. The patch checks for a marker attribute
    on the cache and only applies rotation when TurboQuant is active.

    Must be called once before generation starts. Call
    uninstall_turbo_quant_attention() to restore the original function.
    """
    global _original_sdpa
    import mlx_lm.models.base as base

    if _original_sdpa is not None:
        return  # already installed

    _original_sdpa = base.scaled_dot_product_attention

    def turbo_sdpa(queries, keys, values, cache, scale, mask, sinks=None):
        if cache is not None and isinstance(cache, TurboQuantCacheWrapper):
            queries = rotate(queries, cache._pi)
        return _original_sdpa(queries, keys, values, cache, scale, mask, sinks)

    base.scaled_dot_product_attention = turbo_sdpa

    # Also patch any modules that have already imported it
    import sys

    for name, mod in list(sys.modules.items()):
        if name.startswith("mlx_lm.models.") and mod is not None:
            if hasattr(mod, "scaled_dot_product_attention"):
                if mod.scaled_dot_product_attention is _original_sdpa:
                    mod.scaled_dot_product_attention = turbo_sdpa


def uninstall_turbo_quant_attention() -> None:
    """Restore the original scaled_dot_product_attention function."""
    global _original_sdpa
    if _original_sdpa is None:
        return

    import sys
    import mlx_lm.models.base as base

    current_patched = base.scaled_dot_product_attention
    base.scaled_dot_product_attention = _original_sdpa

    for name, mod in list(sys.modules.items()):
        if name.startswith("mlx_lm.models.") and mod is not None:
            if hasattr(mod, "scaled_dot_product_attention"):
                if mod.scaled_dot_product_attention is current_patched:
                    mod.scaled_dot_product_attention = _original_sdpa

    _original_sdpa = None


# ---------------------------------------------------------------------------
# Legacy: polar transform (DEPRECATED — produces garbage, kept for reference)
# ---------------------------------------------------------------------------


def polar_transform(tensor: mx.array) -> mx.array:
    """DEPRECATED: Polar coordinate transform. Produces garbage with quantized
    KV cache due to 2.7x error amplification through inverse trig. Kept for
    reference only — use rotation-based TurboQuant instead."""
    orig_dtype = tensor.dtype
    t = tensor.astype(mx.float32)
    *batch, d = t.shape
    half = d // 2
    t = t.reshape(*batch, half, 2)
    x, y = t[..., 0], t[..., 1]
    r = mx.sqrt(x * x + y * y)
    theta = mx.arctan2(y, x)
    theta_norm = (theta + mx.array(3.141592653589793)) / mx.array(2 * 3.141592653589793)
    result = mx.concatenate([r, theta_norm], axis=-1)
    return result.astype(orig_dtype)


def inverse_polar_transform(tensor: mx.array) -> mx.array:
    """DEPRECATED: Inverse polar coordinate transform. See polar_transform."""
    orig_dtype = tensor.dtype
    t = tensor.astype(mx.float32)
    *batch, d = t.shape
    half = d // 2
    r = t[..., :half]
    theta_norm = t[..., half:]
    theta = theta_norm * mx.array(2 * 3.141592653589793) - mx.array(3.141592653589793)
    x = r * mx.cos(theta)
    y = r * mx.sin(theta)
    result = mx.stack([x, y], axis=-1).reshape(*batch, d)
    return result.astype(orig_dtype)
