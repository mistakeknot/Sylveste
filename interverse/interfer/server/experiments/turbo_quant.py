"""TurboQuant: KV cache quantization experiments.

v1 (PolarCacheWrapper) — NEGATIVE: inverse trig amplifies error 2.7x.
v2 (TurboQuantCacheWrapper) — NEGATIVE: MLX affine quant negates rotation benefit.
v3 (BHQCacheWrapper) — Custom Lloyd-Max centroids for Beta distribution.
    This is the paper-faithful implementation: rotation + non-uniform scalar
    quantization with precomputed optimal centroids, bypassing mx.quantized_matmul.

References:
  - TurboQuant (ICLR 2026, arxiv.org/abs/2504.19874)
  - PolarQuant (AISTATS 2026, arxiv.org/abs/2502.02617)

Note: This module imports MLX at module level because it is only loaded inside
the Metal subprocess via lazy import in InferenceEngine. The HTTP main process
never imports this module directly.
"""

from __future__ import annotations

import math
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
# Lloyd-Max optimal scalar quantizer for Beta(d/2, d/2) distribution
# ---------------------------------------------------------------------------

# The coordinate distribution of a uniformly random point on S^{d-1} is:
#   f_X(x) = Γ(d/2) / (√π · Γ((d-1)/2)) · (1 - x²)^{(d-3)/2}  for x ∈ [-1, 1]
# This is a scaled/shifted Beta(α, α) with α = (d-1)/2.
# The Lloyd-Max algorithm finds optimal non-uniform centroids that minimize MSE
# under this distribution, which is the core of TurboQuant.


def _beta_pdf(x: float, d: int) -> float:
    """Evaluate the coordinate PDF of a uniform point on S^{d-1}.

    f_X(x) = Γ(d/2) / (√π · Γ((d-1)/2)) · (1 - x²)^{(d-3)/2}
    """
    if abs(x) >= 1.0:
        return 0.0
    log_coeff = (
        math.lgamma(d / 2.0) - 0.5 * math.log(math.pi) - math.lgamma((d - 1) / 2.0)
    )
    exponent = (d - 3) / 2.0
    log_body = exponent * math.log(1.0 - x * x) if exponent != 0 else 0.0
    return math.exp(log_coeff + log_body)


def _integrate_weighted(
    f_weight, f_pdf, a: float, b: float, d: int, n_points: int = 200
) -> float:
    """Numerical integration of f_weight(x) * f_pdf(x, d) over [a, b].

    Uses composite Simpson's rule for accuracy.
    """
    if a >= b:
        return 0.0
    n = n_points if n_points % 2 == 0 else n_points + 1
    h = (b - a) / n
    total = 0.0
    for i in range(n + 1):
        x = a + i * h
        val = f_weight(x) * f_pdf(x, d)
        if i == 0 or i == n:
            total += val
        elif i % 2 == 1:
            total += 4.0 * val
        else:
            total += 2.0 * val
    return total * h / 3.0


def _cdf_inverse_approx(d: int, n_centroids: int) -> list[float]:
    """Initialize centroids at quantiles of the Beta coordinate distribution.

    Computes the CDF numerically, then picks n_centroids evenly-spaced
    quantiles. This avoids the problem of uniform initialization placing
    centroids in the near-zero-density tails.
    """
    n_grid = 2000
    xs = [-1.0 + 2.0 * i / n_grid for i in range(n_grid + 1)]
    # Compute CDF via trapezoidal rule
    cdf = [0.0]
    for i in range(1, n_grid + 1):
        h = xs[i] - xs[i - 1]
        cdf.append(cdf[-1] + 0.5 * h * (_beta_pdf(xs[i - 1], d) + _beta_pdf(xs[i], d)))
    # Normalize
    total = cdf[-1]
    if total > 0:
        cdf = [c / total for c in cdf]

    # Pick quantiles at (0.5/n, 1.5/n, ..., (n-0.5)/n)
    centroids = []
    for k in range(n_centroids):
        target = (k + 0.5) / n_centroids
        # Binary search in CDF
        lo, hi = 0, n_grid
        while lo < hi:
            mid = (lo + hi) // 2
            if cdf[mid] < target:
                lo = mid + 1
            else:
                hi = mid
        centroids.append(xs[lo])
    return centroids


def _lloyd_max_centroids(
    d: int, bits: int, max_iters: int = 200, tol: float = 1e-12
) -> list[float]:
    """Compute optimal Lloyd-Max centroids for the Beta coordinate distribution.

    Solves the 1D k-means problem: find c_1 <= c_2 <= ... <= c_{2^b} in [-1, 1]
    that minimize ∑_i ∫_{boundary_i} |x - c_i|² · f_X(x) dx.

    The algorithm alternates:
      1. Update boundaries: b_i = (c_i + c_{i+1}) / 2  (Voronoi)
      2. Update centroids: c_i = E[X | X ∈ [b_{i-1}, b_i]] (conditional mean)

    Args:
        d: Dimension of the vector space (head_dim).
        bits: Number of bits per coordinate.
        max_iters: Maximum Lloyd-Max iterations.
        tol: Convergence tolerance on centroid movement.

    Returns:
        Sorted list of 2^bits centroids in [-1, 1].
    """
    n_centroids = 1 << bits
    # Initialize at CDF quantiles for robust convergence
    centroids = _cdf_inverse_approx(d, n_centroids)

    pdf = _beta_pdf

    for _iteration in range(max_iters):
        # Compute Voronoi boundaries (midpoints between consecutive centroids)
        boundaries = [-1.0]
        for i in range(n_centroids - 1):
            boundaries.append((centroids[i] + centroids[i + 1]) / 2.0)
        boundaries.append(1.0)

        # Update centroids to conditional means
        new_centroids = []
        for i in range(n_centroids):
            lo, hi = boundaries[i], boundaries[i + 1]
            mass = _integrate_weighted(lambda x: 1.0, pdf, lo, hi, d)
            if mass < 1e-30:
                # Dead centroid — keep old position
                new_centroids.append(centroids[i])
            else:
                moment = _integrate_weighted(lambda x: x, pdf, lo, hi, d)
                new_centroids.append(moment / mass)

        # Check convergence
        max_shift = max(
            abs(new_centroids[i] - centroids[i]) for i in range(n_centroids)
        )
        centroids = new_centroids
        if max_shift < tol:
            break

    return centroids


# Centroid cache: (d, bits) -> list of centroids
_centroid_cache: dict[tuple[int, int], list[float]] = {}


def get_lloyd_max_centroids(d: int, bits: int) -> list[float]:
    """Get precomputed Lloyd-Max centroids for the given dimension and bit width.

    Results are cached after first computation. For typical head_dims
    (64, 128, 192, 256) this runs in ~100ms per (d, bits) pair.
    """
    key = (d, bits)
    if key not in _centroid_cache:
        _centroid_cache[key] = _lloyd_max_centroids(d, bits)
    return _centroid_cache[key]


def centroids_to_mx(centroids: list[float]) -> mx.array:
    """Convert centroid list to an MLX float32 array for GPU operations."""
    return mx.array(centroids, dtype=mx.float32)


def compute_centroid_mse(d: int, bits: int) -> float:
    """Compute the MSE achieved by Lloyd-Max centroids for given d and bits.

    Returns E[|X - Q(X)|²] where Q maps each x to its nearest centroid.
    """
    centroids = get_lloyd_max_centroids(d, bits)
    n = len(centroids)
    boundaries = [-1.0]
    for i in range(n - 1):
        boundaries.append((centroids[i] + centroids[i + 1]) / 2.0)
    boundaries.append(1.0)

    total_mse = 0.0
    for i in range(n):
        lo, hi = boundaries[i], boundaries[i + 1]
        c = centroids[i]
        total_mse += _integrate_weighted(
            lambda x, _c=c: (x - _c) ** 2, _beta_pdf, lo, hi, d
        )
    return total_mse


# ---------------------------------------------------------------------------
# BHQ (Beta-distribution Haar-rotation Quantizer) — custom quantize/dequantize
# ---------------------------------------------------------------------------


def bhq_quantize(x_rotated: mx.array, centroids_mx: mx.array) -> mx.array:
    """Quantize rotated coordinates to nearest centroid indices.

    Args:
        x_rotated: (..., head_dim) tensor of rotated values in [-1, 1].
        centroids_mx: (n_centroids,) sorted centroid values.

    Returns:
        Indices tensor of shape (..., head_dim) as uint8 (up to 256 centroids).
    """
    # Compute distances to all centroids: (..., head_dim, n_centroids)
    diffs = mx.abs(mx.expand_dims(x_rotated, -1) - centroids_mx)
    indices = mx.argmin(diffs, axis=-1).astype(mx.uint8)
    return indices


def bhq_dequantize(indices: mx.array, centroids_mx: mx.array) -> mx.array:
    """Dequantize centroid indices back to coordinate values.

    Args:
        indices: (..., head_dim) uint8 centroid indices.
        centroids_mx: (n_centroids,) centroid lookup table.

    Returns:
        Dequantized values of shape (..., head_dim), float32.
    """
    return mx.take(centroids_mx, indices.astype(mx.uint32), axis=0)


# ---------------------------------------------------------------------------
# BHQ KV Cache wrapper — stores rotation + centroid indices
# ---------------------------------------------------------------------------


class BHQCacheWrapper:
    """Custom KV cache that uses Lloyd-Max centroid quantization.

    Instead of MLX's affine quantization (uniform grid + scale + bias),
    this stores centroid indices from the optimal non-uniform quantizer
    for the post-rotation Beta distribution. Dequantization is a simple
    table lookup.

    Flow:
      Store K: K_rot = K @ Π^T → indices = nearest_centroid(K_rot)
      Fetch K: K_approx = centroids[indices]  (stays in rotated space)
      Attention: Q_rot = Q @ Π^T, then Q_rot @ K_approx^T (non-fused)
    """

    def __init__(
        self,
        pi: mx.array,
        centroids_mx: mx.array,
        head_dim: int,
        n_kv_heads: int,
        max_size: int | None = None,
    ):
        self._pi = pi
        self._centroids = centroids_mx
        self._head_dim = head_dim
        self._n_kv_heads = n_kv_heads
        self._max_size = max_size

        # Storage for quantized keys and full-precision values
        # Keys: uint8 centroid indices (batch, n_kv_heads, seq, head_dim)
        # Norms: float16 per-vector norms (batch, n_kv_heads, seq, 1)
        # Values: float16 (batch, n_kv_heads, seq, head_dim)
        self._key_indices: mx.array | None = None
        self._key_norms: mx.array | None = None
        self._values: mx.array | None = None
        self.offset = 0

    def update_and_fetch(
        self, keys: mx.array, values: mx.array
    ) -> tuple[mx.array, mx.array]:
        """Normalize, rotate, quantize and store keys; store values as-is.

        The paper assumes unit vectors on S^{d-1}. Real key vectors have
        large norms (especially after RoPE), so we:
          1. Store per-vector norms separately (float16)
          2. Normalize keys to unit sphere
          3. Rotate normalized keys
          4. Quantize rotated coordinates to centroids
          5. On fetch: dequantize, then rescale by stored norms

        Args:
            keys: (batch, n_kv_heads, seq_new, head_dim) new key vectors.
            values: (batch, n_kv_heads, seq_new, head_dim) new value vectors.

        Returns:
            (all_dequantized_keys, all_values) for the full sequence so far.
            Keys are returned in rotated space (dequantized and rescaled).
        """
        keys_f32 = keys.astype(mx.float32)
        # Per-vector norms: (batch, n_kv_heads, seq_new, 1)
        norms = mx.sqrt(mx.sum(keys_f32 * keys_f32, axis=-1, keepdims=True))
        norms = mx.maximum(norms, 1e-8)
        # Normalize to unit sphere, rotate, quantize
        rotated_keys = (keys_f32 / norms) @ self._pi.T
        new_indices = bhq_quantize(rotated_keys, self._centroids)
        new_norms = norms.astype(mx.float16)

        if self._key_indices is None:
            self._key_indices = new_indices
            self._key_norms = new_norms
            self._values = values
        else:
            self._key_indices = mx.concatenate([self._key_indices, new_indices], axis=2)
            self._key_norms = mx.concatenate([self._key_norms, new_norms], axis=2)
            self._values = mx.concatenate([self._values, values], axis=2)

        # Apply max_size sliding window if configured
        if self._max_size is not None and self._key_indices.shape[2] > self._max_size:
            trim = self._key_indices.shape[2] - self._max_size
            self._key_indices = self._key_indices[:, :, trim:]
            self._key_norms = self._key_norms[:, :, trim:]
            self._values = self._values[:, :, trim:]

        self.offset = self._key_indices.shape[2]

        # Dequantize and rescale by stored norms
        all_keys_dequant = bhq_dequantize(self._key_indices, self._centroids)
        all_keys_dequant = all_keys_dequant * self._key_norms.astype(mx.float32)
        return all_keys_dequant, self._values

    @property
    def state(self):
        """Return cache state for compatibility with mlx-lm internals."""
        return self._key_indices, self._key_norms, self._values


def wrap_prompt_cache_bhq(
    head_dim: int,
    n_kv_heads: int,
    n_layers: int,
    bits: int = 4,
    seed: int = 0,
    max_size: int | None = None,
) -> tuple[list[BHQCacheWrapper], mx.array]:
    """Create a BHQ cache for each layer with shared rotation matrix and centroids.

    Args:
        head_dim: Dimension per attention head.
        n_kv_heads: Number of KV attention heads.
        n_layers: Number of transformer layers.
        bits: Bit width for centroid quantization (2, 3, 4, or 8).
        seed: Random seed for rotation matrix.
        max_size: Optional sliding window size.

    Returns:
        (list of BHQCacheWrapper, rotation matrix Π)
    """
    pi = make_rotation_matrix(head_dim, seed)
    centroids = get_lloyd_max_centroids(head_dim, bits)
    centroids_mx = centroids_to_mx(centroids)

    caches = [
        BHQCacheWrapper(pi, centroids_mx, head_dim, n_kv_heads, max_size)
        for _ in range(n_layers)
    ]
    return caches, pi


# ---------------------------------------------------------------------------
# BHQ + QJL residual correction (Algorithm 2: TurboQuant_prod)
# ---------------------------------------------------------------------------
#
# At low bit widths (esp. 2-bit), MSE-optimal quantizers are biased for
# inner products.  Algorithm 2 from the TurboQuant paper allocates (b-1)
# bits to the MSE centroid quantizer and uses the remaining 1 bit to store
# a QJL sketch of the quantization residual.
#
# Corrected inner product:
#   <q, k> ≈ <q, k_hat> + sqrt(π/2) · γ / d · <q, S^T · sign(S · r)>
# where:
#   k_hat = dequant(quantize(k))      — (b-1)-bit centroid approximation
#   r = k_rot - k_hat                  — quantization residual
#   γ = ||r||                           — residual norm
#   S = (jl_dim, head_dim) Gaussian     — random projection
#   d = jl_dim                          — number of JL projection rows
#
# Equivalently, the corrected key vector is:
#   k_corrected = k_hat + sqrt(π/2) · γ / d · S^T · sign(S · r)


class BHQResidualCacheWrapper:
    """BHQ cache with 1-bit QJL residual correction for unbiased inner products.

    Uses (b-1) bits for the Lloyd-Max centroid quantizer and stores a 1-bit
    QJL sketch of the quantization residual alongside the centroid indices.
    At decode time, the residual correction term is added to the dequantized
    keys, yielding an unbiased inner product estimator.

    This is particularly valuable at 2-bit (where 1-bit centroids + 1-bit QJL
    significantly outperforms plain 2-bit centroids for inner product tasks).

    Storage per key coordinate:
      - (b-1) bits: centroid index
      - 1 bit: QJL sign bit
      - float16: per-vector norm (shared across coordinates)
      - float16: per-vector residual norm γ (shared across coordinates)
    """

    def __init__(
        self,
        pi: mx.array,
        centroids_mx: mx.array,
        head_dim: int,
        n_kv_heads: int,
        jl_dim: int | None = None,
        max_size: int | None = None,
        jl_seed: int = 42,
    ):
        self._pi = pi
        self._centroids = centroids_mx
        self._head_dim = head_dim
        self._n_kv_heads = n_kv_heads
        self._max_size = max_size

        # JL projection: (jl_dim, head_dim) i.i.d. N(0,1)
        # Default jl_dim = head_dim (1:1 ratio, paper recommends d to 2d)
        self._jl_dim = jl_dim if jl_dim is not None else head_dim
        key = mx.random.key(jl_seed)
        self._projection = mx.random.normal(shape=(self._jl_dim, head_dim), key=key)
        mx.eval(self._projection)

        # sqrt(π/2) / jl_dim — the QJL correction scaling factor
        self._qjl_scale = float(math.sqrt(math.pi / 2.0) / self._jl_dim)

        # Storage
        self._key_indices: mx.array | None = None
        self._key_norms: mx.array | None = None
        self._qjl_bits: mx.array | None = None  # int8 ±1 per JL dim
        self._residual_norms: mx.array | None = None  # float16 per-vector γ
        self._values: mx.array | None = None
        self.offset = 0

    def update_and_fetch(
        self, keys: mx.array, values: mx.array
    ) -> tuple[mx.array, mx.array]:
        """Quantize keys with (b-1)-bit centroids + 1-bit QJL residual.

        Args:
            keys: (batch, n_kv_heads, seq_new, head_dim) new key vectors.
            values: (batch, n_kv_heads, seq_new, head_dim) new value vectors.

        Returns:
            (all_corrected_keys, all_values) for the full sequence so far.
            Corrected keys include the QJL residual term and are in rotated space.
        """
        keys_f32 = keys.astype(mx.float32)

        # Step 1: Per-vector norms and normalization
        norms = mx.sqrt(mx.sum(keys_f32 * keys_f32, axis=-1, keepdims=True))
        norms = mx.maximum(norms, 1e-8)
        rotated_keys = (keys_f32 / norms) @ self._pi.T  # unit sphere, rotated

        # Step 2: Quantize with (b-1)-bit centroids
        new_indices = bhq_quantize(rotated_keys, self._centroids)
        k_hat = bhq_dequantize(new_indices, self._centroids)

        # Step 3: Compute residual and QJL sketch
        residual = rotated_keys - k_hat
        # Per-vector residual norm γ: (batch, n_kv_heads, seq_new, 1)
        res_norms = mx.sqrt(mx.sum(residual * residual, axis=-1, keepdims=True))
        # QJL encode: sign(S @ r) for each vector
        # residual shape: (batch, n_kv_heads, seq_new, head_dim)
        # projection shape: (jl_dim, head_dim)
        # result: (batch, n_kv_heads, seq_new, jl_dim)
        new_qjl = qjl_encode(residual, self._projection)

        new_norms = norms.astype(mx.float16)
        new_res_norms = res_norms.astype(mx.float16)

        # Step 4: Append to stored cache
        if self._key_indices is None:
            self._key_indices = new_indices
            self._key_norms = new_norms
            self._qjl_bits = new_qjl
            self._residual_norms = new_res_norms
            self._values = values
        else:
            self._key_indices = mx.concatenate([self._key_indices, new_indices], axis=2)
            self._key_norms = mx.concatenate([self._key_norms, new_norms], axis=2)
            self._qjl_bits = mx.concatenate([self._qjl_bits, new_qjl], axis=2)
            self._residual_norms = mx.concatenate(
                [self._residual_norms, new_res_norms], axis=2
            )
            self._values = mx.concatenate([self._values, values], axis=2)

        # Step 5: Apply sliding window
        if self._max_size is not None and self._key_indices.shape[2] > self._max_size:
            trim = self._key_indices.shape[2] - self._max_size
            self._key_indices = self._key_indices[:, :, trim:]
            self._key_norms = self._key_norms[:, :, trim:]
            self._qjl_bits = self._qjl_bits[:, :, trim:]
            self._residual_norms = self._residual_norms[:, :, trim:]
            self._values = self._values[:, :, trim:]

        self.offset = self._key_indices.shape[2]

        # Step 6: Return dequantized keys (without inline correction).
        # The QJL correction is applied at attention-score time via
        # bhq_residual_attention(), not embedded in the key vectors.
        # Reason: the correction is direction-dependent — adding it to
        # keys injects isotropic noise into dimensions orthogonal to
        # the query, degrading quality rather than improving it.
        all_k_hat = bhq_dequantize(self._key_indices, self._centroids)
        all_norms_f32 = self._key_norms.astype(mx.float32)
        all_k_hat = all_k_hat * all_norms_f32

        return all_k_hat, self._values

    def get_qjl_state(self) -> tuple[mx.array, mx.array]:
        """Return QJL state for attention-time correction.

        Returns:
            (qjl_bits, residual_norms) covering the full stored sequence.
            qjl_bits: (batch, n_kv_heads, seq, jl_dim) int8 ±1
            residual_norms: (batch, n_kv_heads, seq, 1) float16
        """
        return self._qjl_bits, self._residual_norms

    @property
    def projection(self) -> mx.array:
        """The JL projection matrix S: (jl_dim, head_dim)."""
        return self._projection

    @property
    def qjl_scale(self) -> float:
        """The QJL correction scale factor: sqrt(π/2) / jl_dim."""
        return self._qjl_scale

    @property
    def state(self):
        """Return cache state for compatibility with mlx-lm internals."""
        return (
            self._key_indices,
            self._key_norms,
            self._qjl_bits,
            self._residual_norms,
            self._values,
        )


def wrap_prompt_cache_bhq_residual(
    head_dim: int,
    n_kv_heads: int,
    n_layers: int,
    bits: int = 2,
    seed: int = 0,
    jl_dim: int | None = None,
    jl_seed: int = 42,
    max_size: int | None = None,
) -> tuple[list[BHQResidualCacheWrapper], mx.array]:
    """Create a BHQ+QJL residual cache for each layer.

    Uses (bits-1) centroid bits + 1-bit QJL residual.  Default bits=2
    since this is most impactful at very low bit widths.

    Args:
        head_dim: Dimension per attention head.
        n_kv_heads: Number of KV attention heads.
        n_layers: Number of transformer layers.
        bits: Total bit budget per coordinate (centroid uses bits-1).
        seed: Random seed for rotation matrix.
        jl_dim: JL projection dimension (default: head_dim).
        jl_seed: Random seed for JL projection matrix.
        max_size: Optional sliding window size.

    Returns:
        (list of BHQResidualCacheWrapper, rotation matrix Π)
    """
    pi = make_rotation_matrix(head_dim, seed)
    # Use (bits-1) for the centroid quantizer
    centroid_bits = max(1, bits - 1)
    centroids = get_lloyd_max_centroids(head_dim, centroid_bits)
    centroids_mx = centroids_to_mx(centroids)

    caches = [
        BHQResidualCacheWrapper(
            pi,
            centroids_mx,
            head_dim,
            n_kv_heads,
            jl_dim=jl_dim,
            max_size=max_size,
            jl_seed=jl_seed,
        )
        for _ in range(n_layers)
    ]
    return caches, pi


# ---------------------------------------------------------------------------
# Non-fused attention with BHQ dequantized keys
# ---------------------------------------------------------------------------


def bhq_attention(
    queries: mx.array,
    keys_dequant: mx.array,
    values: mx.array,
    pi: mx.array,
    scale: float,
    mask: mx.array | None = None,
) -> mx.array:
    """Compute scaled dot-product attention with BHQ-dequantized keys.

    Since BHQ keys are stored in rotated space, Q must be rotated too:
      Q_rot = Q @ Π^T
      scores = Q_rot @ K_dequant^T * scale
      output = softmax(scores) @ V

    Args:
        queries: (batch, n_heads, seq_q, head_dim)
        keys_dequant: (batch, n_kv_heads, seq_kv, head_dim) — already dequantized
        values: (batch, n_kv_heads, seq_kv, head_dim)
        pi: (head_dim, head_dim) rotation matrix
        scale: Attention scale factor (typically 1/√head_dim)
        mask: Optional attention mask

    Returns:
        Attention output (batch, n_heads, seq_q, head_dim)
    """
    # Rotate queries into the same space as dequantized keys
    q_rot = queries @ pi.T

    # Handle GQA: repeat KV heads if n_heads > n_kv_heads
    n_heads = q_rot.shape[1]
    n_kv_heads = keys_dequant.shape[1]
    if n_heads > n_kv_heads:
        repeats = n_heads // n_kv_heads
        keys_dequant = mx.repeat(keys_dequant, repeats, axis=1)
        values = mx.repeat(values, repeats, axis=1)

    # Compute attention scores
    scores = (q_rot @ mx.swapaxes(keys_dequant, -2, -1)) * scale

    if mask is not None:
        if isinstance(mask, str) and mask == "causal":
            # Create causal mask for non-fused attention path
            seq_q_len = q_rot.shape[2]
            seq_kv_len = keys_dequant.shape[2]
            if seq_q_len > 1:
                row_idx = mx.arange(seq_kv_len - seq_q_len, seq_kv_len)[:, None]
                col_idx = mx.arange(seq_kv_len)[None, :]
                causal = mx.where(col_idx <= row_idx, 0.0, -float("inf"))
                scores = scores + causal
        else:
            scores = scores + mask

    # Softmax and weighted sum
    weights = mx.softmax(scores.astype(mx.float32), axis=-1).astype(queries.dtype)
    output = weights @ values

    return output


def bhq_residual_attention(
    queries: mx.array,
    keys_dequant: mx.array,
    values: mx.array,
    pi: mx.array,
    scale: float,
    qjl_bits: mx.array,
    residual_norms: mx.array,
    projection: mx.array,
    qjl_scale: float,
    mask: mx.array | None = None,
) -> mx.array:
    """Attention with QJL residual correction applied at score level.

    Computes corrected attention scores:
      base_score = Q_rot @ K_hat^T * scale
      correction = sqrt(π/2)/d * γ * (Q_rot @ S^T) @ sign(S @ r)^T * scale
      score = base_score + correction

    The correction is applied to the raw scores before softmax, so it
    only affects the relative weighting — it doesn't add noise to the
    key vectors in directions orthogonal to the query.

    Args:
        queries: (batch, n_heads, seq_q, head_dim)
        keys_dequant: (batch, n_kv_heads, seq_kv, head_dim) — from cache
        values: (batch, n_kv_heads, seq_kv, head_dim)
        pi: (head_dim, head_dim) rotation matrix
        scale: Attention scale factor (1/√head_dim)
        qjl_bits: (batch, n_kv_heads, seq_kv, jl_dim) int8 ±1
        residual_norms: (batch, n_kv_heads, seq_kv, 1) float16 — γ per vector
        projection: (jl_dim, head_dim) — S matrix
        qjl_scale: sqrt(π/2) / jl_dim
        mask: Optional attention mask
    """
    q_rot = queries @ pi.T

    # Handle GQA
    n_heads = q_rot.shape[1]
    n_kv_heads = keys_dequant.shape[1]
    if n_heads > n_kv_heads:
        repeats = n_heads // n_kv_heads
        keys_dequant = mx.repeat(keys_dequant, repeats, axis=1)
        values = mx.repeat(values, repeats, axis=1)
        qjl_bits = mx.repeat(qjl_bits, repeats, axis=1)
        residual_norms = mx.repeat(residual_norms, repeats, axis=1)

    # Base attention scores: Q_rot @ K_hat^T
    base_scores = (q_rot @ mx.swapaxes(keys_dequant, -2, -1)) * scale

    # QJL score correction:
    #   For each (q, k_j) pair, the correction is:
    #     Δ_j = qjl_scale * γ_j * <q_rot, S^T @ sign(S @ r_j)>
    #   In batch form:
    #     Q_proj = Q_rot @ S^T          — (batch, n_heads, seq_q, jl_dim)
    #     correction = Q_proj @ (γ * qjl_bits)^T  * qjl_scale * scale
    q_proj = q_rot.astype(mx.float32) @ projection.T  # (..., jl_dim)
    # Scale bits by residual norms: (batch, n_kv_heads, seq_kv, jl_dim)
    gamma_bits = residual_norms.astype(mx.float32) * qjl_bits.astype(mx.float32)
    score_correction = (q_proj @ mx.swapaxes(gamma_bits, -2, -1)) * (qjl_scale * scale)

    scores = base_scores + score_correction

    if mask is not None:
        if isinstance(mask, str) and mask == "causal":
            seq_q_len = q_rot.shape[2]
            seq_kv_len = keys_dequant.shape[2]
            if seq_q_len > 1:
                row_idx = mx.arange(seq_kv_len - seq_q_len, seq_kv_len)[:, None]
                col_idx = mx.arange(seq_kv_len)[None, :]
                causal = mx.where(col_idx <= row_idx, 0.0, -float("inf"))
                scores = scores + causal
        else:
            scores = scores + mask

    weights = mx.softmax(scores.astype(mx.float32), axis=-1).astype(queries.dtype)
    output = weights @ values
    return output


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
    """Monkey-patch scaled_dot_product_attention to handle TurboQuant caches.

    For TurboQuantCacheWrapper (v2): rotates Q vectors so Q_rot · K_rot^T = Q · K^T.
    For BHQCacheWrapper (v3): uses non-fused bhq_attention with centroid dequantization.

    This patches mlx_lm.models.base.scaled_dot_product_attention, which
    all model implementations import.

    Must be called once before generation starts. Call
    uninstall_turbo_quant_attention() to restore the original function.
    """
    global _original_sdpa
    import mlx_lm.models.base as base

    if _original_sdpa is not None:
        return  # already installed

    _original_sdpa = base.scaled_dot_product_attention

    def turbo_sdpa(queries, keys, values, cache, scale, mask, sinks=None):
        if cache is not None and isinstance(cache, BHQCacheWrapper):
            # BHQ path: keys are already dequantized by update_and_fetch
            return bhq_attention(queries, keys, values, cache._pi, scale, mask)
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
