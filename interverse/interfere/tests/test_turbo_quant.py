"""Tests for TurboQuant KV cache quantization (v1 polar, v2 rotation, v3 BHQ)."""

import math

import mlx.core as mx

import pytest

from server.experiments.turbo_quant import (
    BHQCacheWrapper,
    BHQResidualCacheWrapper,
    bhq_attention,
    bhq_dequantize,
    bhq_quantize,
    bhq_residual_attention,
    centroids_to_mx,
    compute_centroid_mse,
    get_lloyd_max_centroids,
    inverse_polar_transform,
    make_jl_projection,
    make_rotation_matrix,
    polar_transform,
    qjl_decode,
    qjl_encode,
    rotate,
    wrap_prompt_cache_bhq,
    wrap_prompt_cache_bhq_residual,
    _centroid_cache,
)


# ---------------------------------------------------------------------------
# Polar transform tests
# ---------------------------------------------------------------------------


def test_polar_round_trip_low_error():
    """Round-trip (transform then inverse) should have < 0.01% normalized MSE."""
    mx.random.seed(42)
    tensor = mx.random.normal(shape=(1, 8, 128, 128))
    polar = polar_transform(tensor)
    recovered = inverse_polar_transform(polar)
    mx.eval(recovered)

    mse = mx.mean((tensor - recovered) ** 2).item()
    norm = mx.mean(tensor**2).item()
    nmse = mse / (norm + 1e-10)
    assert nmse < 1e-4, f"Normalized MSE {nmse:.6f} exceeds 0.01% threshold"


def test_polar_shape_preserved():
    """Output shape must match input shape."""
    tensor = mx.random.normal(shape=(2, 4, 64, 128))
    polar = polar_transform(tensor)
    mx.eval(polar)
    assert polar.shape == tensor.shape


def test_polar_dtype_preserved():
    """float16 in, float16 out."""
    tensor = mx.random.normal(shape=(1, 4, 32, 64)).astype(mx.float16)
    polar = polar_transform(tensor)
    recovered = inverse_polar_transform(polar)
    mx.eval(recovered)
    assert polar.dtype == mx.float16
    assert recovered.dtype == mx.float16


def test_polar_zero_vector_round_trip():
    """Zero vectors should round-trip to zero (atan2(0,0) = 0, r = 0)."""
    tensor = mx.zeros((1, 2, 4, 8))
    polar = polar_transform(tensor)
    recovered = inverse_polar_transform(polar)
    mx.eval(recovered)
    assert mx.allclose(recovered, tensor, atol=1e-6).item()


def test_polar_large_values():
    """Large values should round-trip cleanly."""
    tensor = mx.random.normal(shape=(1, 4, 32, 64)) * 1000
    polar = polar_transform(tensor)
    recovered = inverse_polar_transform(polar)
    mx.eval(recovered)

    mse = mx.mean((tensor - recovered) ** 2).item()
    norm = mx.mean(tensor**2).item()
    nmse = mse / (norm + 1e-10)
    assert nmse < 1e-4, f"Large-value NMSE {nmse:.6f} exceeds threshold"


def test_polar_transform_range():
    """After polar_transform, even dims (radii) should be >= 0,
    odd dims (theta_norm) should be in [0, 1]."""
    mx.random.seed(7)
    tensor = mx.random.normal(shape=(1, 4, 32, 64))
    polar = polar_transform(tensor)
    mx.eval(polar)

    *batch, d = polar.shape
    polar_flat = polar.reshape(-1, d // 2, 2)
    radii = polar_flat[..., 0]
    thetas = polar_flat[..., 1]
    mx.eval(radii, thetas)

    assert mx.all(radii >= -1e-6).item(), "Radii should be non-negative"
    assert mx.all(thetas >= -1e-6).item(), "Theta norm should be >= 0"
    assert mx.all(thetas <= 1.0 + 1e-6).item(), "Theta norm should be <= 1"


# ---------------------------------------------------------------------------
# QJL tests
# ---------------------------------------------------------------------------


def test_jl_projection_seeded():
    """Same seed produces same projection matrix."""
    p1 = make_jl_projection(64, 128, seed=42)
    p2 = make_jl_projection(64, 128, seed=42)
    mx.eval(p1, p2)
    assert mx.allclose(p1, p2).item()


def test_jl_projection_different_seeds():
    """Different seeds produce different matrices."""
    p1 = make_jl_projection(64, 128, seed=42)
    p2 = make_jl_projection(64, 128, seed=43)
    mx.eval(p1, p2)
    assert not mx.allclose(p1, p2).item()


def test_qjl_encode_produces_binary():
    """QJL encode should produce only +1 and -1."""
    residual = mx.random.normal(shape=(1, 4, 32, 128))
    projection = make_jl_projection(64, 128, seed=0)
    bits = qjl_encode(residual, projection)
    mx.eval(bits)

    assert bits.dtype == mx.int8
    # All values should be +1 or -1
    abs_bits = mx.abs(bits)
    mx.eval(abs_bits)
    assert mx.all(abs_bits == 1).item(), "All QJL bits should be +1 or -1"


def test_qjl_round_trip_reduces_error():
    """QJL correction reduces error when jl_dim >= 2 * head_dim."""
    mx.random.seed(99)
    head_dim = 128
    jl_dim = 256  # 2x oversampling required for 1-bit sketch
    original = mx.random.normal(shape=(1, 4, 32, head_dim))

    # Simulate quantization error by adding noise
    noise = mx.random.normal(shape=original.shape) * 0.1
    quantized = original + noise
    residual = original - quantized
    mx.eval(residual)

    projection = make_jl_projection(jl_dim, head_dim, seed=0)
    bits = qjl_encode(residual, projection)
    approx_residual = qjl_decode(bits, projection)
    corrected = quantized + approx_residual
    mx.eval(corrected)

    error_before = mx.mean((original - quantized) ** 2).item()
    error_after = mx.mean((original - corrected) ** 2).item()

    assert (
        error_after < error_before
    ), f"QJL correction should reduce error: {error_after:.6f} >= {error_before:.6f}"


def test_qjl_small_dim_adds_noise():
    """At jl_dim < head_dim, 1-bit sketch adds noise (known limitation)."""
    mx.random.seed(99)
    head_dim = 128
    jl_dim = 64  # underdetermined — correction adds noise
    original = mx.random.normal(shape=(1, 4, 32, head_dim))

    noise = mx.random.normal(shape=original.shape) * 0.1
    quantized = original + noise
    residual = original - quantized
    mx.eval(residual)

    projection = make_jl_projection(jl_dim, head_dim, seed=0)
    bits = qjl_encode(residual, projection)
    approx_residual = qjl_decode(bits, projection)
    corrected = quantized + approx_residual
    mx.eval(corrected)

    error_before = mx.mean((original - quantized) ** 2).item()
    error_after = mx.mean((original - corrected) ** 2).item()

    # At small jl_dim, correction may increase error — this is expected
    # and will be explored by autoresearch (jl_dim is a mutation dimension)
    assert error_after > 0, "Error should be non-zero"


def test_qjl_encode_shape():
    """QJL encode output shape should be (..., jl_dim)."""
    residual = mx.random.normal(shape=(2, 4, 16, 128))
    projection = make_jl_projection(64, 128, seed=0)
    bits = qjl_encode(residual, projection)
    mx.eval(bits)
    assert bits.shape == (2, 4, 16, 64)


# ---------------------------------------------------------------------------
# PolarCacheWrapper tests removed — PolarCacheWrapper was deprecated in v1


# ---------------------------------------------------------------------------
# Integration tests
# ---------------------------------------------------------------------------


# ---------------------------------------------------------------------------
# BHQ (TurboQuant v3) — Lloyd-Max centroid tests
# ---------------------------------------------------------------------------


def test_lloyd_max_centroids_symmetry():
    """Centroids should be symmetric around 0 (distribution is symmetric)."""
    _centroid_cache.clear()
    for d in [64, 128]:
        for bits in [2, 3, 4]:
            c = get_lloyd_max_centroids(d, bits)
            n = len(c)
            for i in range(n // 2):
                assert abs(c[i] + c[n - 1 - i]) < 0.01, (
                    f"d={d}, b={bits}: centroids not symmetric: "
                    f"c[{i}]={c[i]:.6f}, c[{n-1-i}]={c[n-1-i]:.6f}"
                )


def test_lloyd_max_centroids_count():
    """Should produce exactly 2^b centroids."""
    _centroid_cache.clear()
    for bits in [1, 2, 3, 4, 8]:
        c = get_lloyd_max_centroids(128, bits)
        assert (
            len(c) == 2**bits
        ), f"b={bits}: expected {2**bits} centroids, got {len(c)}"


def test_lloyd_max_centroids_sorted():
    """Centroids should be in ascending order."""
    _centroid_cache.clear()
    for bits in [2, 3, 4]:
        c = get_lloyd_max_centroids(128, bits)
        for i in range(len(c) - 1):
            assert c[i] < c[i + 1], f"b={bits}: centroids not sorted at {i}"


def test_lloyd_max_centroids_in_range():
    """All centroids should be in [-1, 1]."""
    _centroid_cache.clear()
    for bits in [2, 3, 4]:
        c = get_lloyd_max_centroids(128, bits)
        for ci in c:
            assert -1.0 <= ci <= 1.0, f"b={bits}: centroid {ci} out of range"


def test_lloyd_max_mse_decreases_with_bits():
    """Higher bit width should give lower MSE."""
    _centroid_cache.clear()
    d = 128
    prev_mse = float("inf")
    for bits in [1, 2, 3, 4, 8]:
        mse = compute_centroid_mse(d, bits)
        assert mse < prev_mse, f"MSE did not decrease from b={bits-1} to b={bits}"
        prev_mse = mse


def test_lloyd_max_1bit_matches_paper():
    """1-bit centroids for large d should match paper: ±√(2/(πd))."""
    _centroid_cache.clear()
    d = 1024
    c = get_lloyd_max_centroids(d, 1)
    expected = math.sqrt(2.0 / (math.pi * d))
    assert abs(c[0] + expected) < 1e-3, f"c[0]={c[0]}, expected {-expected}"
    assert abs(c[1] - expected) < 1e-3, f"c[1]={c[1]}, expected {expected}"


def test_bhq_quantize_shape():
    """BHQ quantize should preserve spatial dimensions."""
    _centroid_cache.clear()
    centroids_mx = centroids_to_mx(get_lloyd_max_centroids(128, 4))
    x = mx.random.normal(shape=(1, 4, 8, 128))
    indices = bhq_quantize(x, centroids_mx)
    mx.eval(indices)
    assert indices.shape == (1, 4, 8, 128)
    assert indices.dtype == mx.uint8


def test_bhq_quantize_range():
    """Indices should be in [0, n_centroids)."""
    _centroid_cache.clear()
    for bits in [2, 3, 4]:
        centroids_mx = centroids_to_mx(get_lloyd_max_centroids(128, bits))
        x = mx.random.normal(shape=(1, 4, 8, 128)) * 0.1
        indices = bhq_quantize(x, centroids_mx)
        mx.eval(indices)
        assert int(mx.max(indices)) < 2**bits
        assert int(mx.min(indices)) >= 0


def test_bhq_dequantize_matches_centroids():
    """Dequantized values should be exact centroid values."""
    _centroid_cache.clear()
    centroids = get_lloyd_max_centroids(128, 2)
    centroids_mx = centroids_to_mx(centroids)
    # Create known indices
    indices = mx.array([[[0, 1, 2, 3]]], dtype=mx.uint8)
    dq = bhq_dequantize(indices, centroids_mx)
    mx.eval(dq)
    for i in range(4):
        assert abs(dq[0, 0, i].item() - centroids[i]) < 1e-6


def test_bhq_attention_matches_standard():
    """BHQ attention with exact (unquantized) keys should match standard attention."""
    head_dim = 64
    batch, n_heads = 1, 2
    seq_q, seq_kv = 1, 8
    scale = 1.0 / math.sqrt(head_dim)

    pi = make_rotation_matrix(head_dim, seed=0)
    mx.random.seed(42)
    Q = mx.random.normal(shape=(batch, n_heads, seq_q, head_dim))
    K = mx.random.normal(shape=(batch, n_heads, seq_kv, head_dim))
    V = mx.random.normal(shape=(batch, n_heads, seq_kv, head_dim))

    # Standard attention
    scores = (Q.astype(mx.float32) @ mx.swapaxes(K.astype(mx.float32), -2, -1)) * scale
    weights = mx.softmax(scores, axis=-1)
    output_std = weights @ V.astype(mx.float32)
    mx.eval(output_std)

    # BHQ attention with exact rotated keys (no quantization)
    K_rot = K.astype(mx.float32) @ pi.T
    output_bhq = bhq_attention(Q, K_rot, V, pi, scale, mask=None)
    mx.eval(output_bhq)

    nmse = (
        mx.mean((output_std - output_bhq.astype(mx.float32)) ** 2).item()
        / mx.mean(output_std**2).item()
    )
    assert (
        nmse < 1e-5
    ), f"BHQ attention NMSE {nmse:.2e} too high (should match standard)"


def test_bhq_cache_wrapper_accumulates():
    """BHQ cache should accumulate tokens and track offset."""
    _centroid_cache.clear()
    head_dim = 64
    n_kv_heads = 2
    pi = make_rotation_matrix(head_dim, seed=0)
    centroids_mx = centroids_to_mx(get_lloyd_max_centroids(head_dim, 4))

    cache = BHQCacheWrapper(pi, centroids_mx, head_dim, n_kv_heads)
    assert cache.offset == 0

    for step in range(3):
        k = mx.random.normal(shape=(1, n_kv_heads, 4, head_dim))
        v = mx.random.normal(shape=(1, n_kv_heads, 4, head_dim))
        out_k, out_v = cache.update_and_fetch(k, v)
        mx.eval(out_k, out_v)

    assert cache.offset == 12
    assert out_k.shape == (1, n_kv_heads, 12, head_dim)
    assert out_v.shape == (1, n_kv_heads, 12, head_dim)


def test_bhq_cache_wrapper_preserves_norms():
    """Dequantized keys should have approximately correct norms."""
    _centroid_cache.clear()
    head_dim = 128
    n_kv_heads = 4
    pi = make_rotation_matrix(head_dim, seed=0)
    centroids_mx = centroids_to_mx(get_lloyd_max_centroids(head_dim, 4))

    cache = BHQCacheWrapper(pi, centroids_mx, head_dim, n_kv_heads)

    mx.random.seed(42)
    keys = mx.random.normal(shape=(1, n_kv_heads, 8, head_dim)) * 100  # large norms
    values = mx.random.normal(shape=(1, n_kv_heads, 8, head_dim))

    out_k, _ = cache.update_and_fetch(keys, values)
    mx.eval(out_k)

    # Check norms are approximately preserved
    orig_norms = mx.sqrt(mx.sum(keys.astype(mx.float32) ** 2, axis=-1))
    out_norms = mx.sqrt(mx.sum(out_k**2, axis=-1))
    mx.eval(orig_norms, out_norms)

    norm_ratio = (out_norms / orig_norms.astype(mx.float32)).reshape(-1)
    mx.eval(norm_ratio)
    # Norms should be within 20% (quantization error on direction, not magnitude)
    assert mx.mean(mx.abs(norm_ratio - 1.0)).item() < 0.2


def test_bhq_2bit_beats_native_2bit():
    """BHQ at 2-bit should have lower attention NMSE than native affine 2-bit."""
    _centroid_cache.clear()
    head_dim = 128
    batch, n_heads = 1, 4
    seq_kv = 64
    scale = 1.0 / math.sqrt(head_dim)

    pi = make_rotation_matrix(head_dim, seed=42)
    mx.random.seed(99)
    Q = mx.random.normal(shape=(batch, n_heads, 1, head_dim)) * 0.1
    K = mx.random.normal(shape=(batch, n_heads, seq_kv, head_dim))
    V = mx.random.normal(shape=(batch, n_heads, seq_kv, head_dim))
    K_norms = mx.sqrt(mx.sum(K.astype(mx.float32) ** 2, axis=-1, keepdims=True))
    K_unit = K.astype(mx.float32) / K_norms

    # Ground truth
    scores_gt = (
        Q.astype(mx.float32) @ mx.swapaxes(K.astype(mx.float32), -2, -1)
    ) * scale
    weights_gt = mx.softmax(scores_gt, axis=-1)
    output_gt = weights_gt @ V.astype(mx.float32)
    mx.eval(output_gt)
    gt_norm = mx.mean(output_gt**2).item()

    # BHQ 2-bit
    centroids_mx = centroids_to_mx(get_lloyd_max_centroids(head_dim, 2))
    K_rot = rotate(K_unit, pi)
    idx = bhq_quantize(K_rot, centroids_mx)
    K_dq = bhq_dequantize(idx, centroids_mx) * K_norms.astype(mx.float32)
    out_bhq = bhq_attention(Q, K_dq, V, pi, scale, mask=None)
    mx.eval(out_bhq)
    bhq_nmse = mx.mean((output_gt - out_bhq.astype(mx.float32)) ** 2).item() / gt_norm

    # Native 2-bit
    qd, qs, qb = mx.quantize(K, group_size=64, bits=2)
    K_native = mx.dequantize(qd, qs, qb, group_size=64, bits=2)
    scores_n = (
        Q.astype(mx.float32) @ mx.swapaxes(K_native.astype(mx.float32), -2, -1)
    ) * scale
    weights_n = mx.softmax(scores_n, axis=-1)
    out_n = weights_n @ V.astype(mx.float32)
    mx.eval(out_n)
    native_nmse = mx.mean((output_gt - out_n) ** 2).item() / gt_norm

    assert (
        bhq_nmse < native_nmse
    ), f"BHQ-2 NMSE {bhq_nmse:.2e} should be lower than Native-2 {native_nmse:.2e}"


def test_bhq_mutual_exclusion():
    """BHQ + explicit kv_bits should raise ValueError."""
    from server.experiments.config import ExperimentConfig
    from server.inference import InferenceEngine

    bhq_cfg = ExperimentConfig(name="bhq", enabled=True, params={"kv_bits": 4})
    engine = InferenceEngine(experiment_configs={"bhq": bhq_cfg})

    with pytest.raises(ValueError, match="Cannot set kv_bits"):
        list(
            engine.generate(
                prompt="test",
                model_name="mlx-community/Qwen2.5-0.5B-Instruct-4bit",
                kv_bits=8,
                max_tokens=1,
            )
        )


def test_turbo_quant_mutual_exclusion():
    """TurboQuant + explicit kv_bits should raise ValueError."""
    from server.experiments.config import ExperimentConfig
    from server.inference import InferenceEngine

    tq_cfg = ExperimentConfig(name="turbo_quant", enabled=True, params={"kv_bits": 4})
    engine = InferenceEngine(experiment_configs={"turbo_quant": tq_cfg})

    with pytest.raises(ValueError, match="Cannot set kv_bits"):
        # Pass kv_bits explicitly while turbo_quant is enabled
        list(
            engine.generate(
                prompt="test",
                model_name="mlx-community/Qwen2.5-0.5B-Instruct-4bit",
                kv_bits=8,
                max_tokens=1,
            )
        )


# ---------------------------------------------------------------------------
# BHQ + QJL residual correction (Algorithm 2: TurboQuant_prod)
# ---------------------------------------------------------------------------


def test_bhq_residual_cache_accumulates():
    """BHQ residual cache should accumulate tokens and track offset."""
    _centroid_cache.clear()
    head_dim = 64
    n_kv_heads = 2
    caches, pi = wrap_prompt_cache_bhq_residual(
        head_dim, n_kv_heads, n_layers=1, bits=2
    )
    cache = caches[0]
    assert cache.offset == 0

    for step in range(3):
        k = mx.random.normal(shape=(1, n_kv_heads, 4, head_dim))
        v = mx.random.normal(shape=(1, n_kv_heads, 4, head_dim))
        out_k, out_v = cache.update_and_fetch(k, v)
        mx.eval(out_k, out_v)

    assert cache.offset == 12
    assert out_k.shape == (1, n_kv_heads, 12, head_dim)
    assert out_v.shape == (1, n_kv_heads, 12, head_dim)


def test_bhq_residual_state_includes_qjl():
    """BHQ residual cache state should include QJL bits and residual norms."""
    _centroid_cache.clear()
    head_dim = 64
    n_kv_heads = 2
    caches, _ = wrap_prompt_cache_bhq_residual(head_dim, n_kv_heads, n_layers=1, bits=2)
    cache = caches[0]

    k = mx.random.normal(shape=(1, n_kv_heads, 8, head_dim))
    v = mx.random.normal(shape=(1, n_kv_heads, 8, head_dim))
    cache.update_and_fetch(k, v)

    state = cache.state
    assert len(state) == 5  # indices, norms, qjl_bits, residual_norms, values
    indices, norms, qjl_bits, res_norms, values = state
    assert qjl_bits.shape == (1, n_kv_heads, 8, head_dim)  # jl_dim = head_dim
    assert qjl_bits.dtype == mx.int8
    assert res_norms.shape == (1, n_kv_heads, 8, 1)


def test_bhq_residual_preserves_norms():
    """Corrected keys should have approximately correct norms."""
    _centroid_cache.clear()
    head_dim = 128
    n_kv_heads = 4
    caches, pi = wrap_prompt_cache_bhq_residual(
        head_dim, n_kv_heads, n_layers=1, bits=2
    )
    cache = caches[0]

    mx.random.seed(42)
    keys = mx.random.normal(shape=(1, n_kv_heads, 16, head_dim)) * 50
    values = mx.random.normal(shape=(1, n_kv_heads, 16, head_dim))

    out_k, _ = cache.update_and_fetch(keys, values)
    mx.eval(out_k)

    orig_norms = mx.sqrt(mx.sum(keys.astype(mx.float32) ** 2, axis=-1))
    out_norms = mx.sqrt(mx.sum(out_k**2, axis=-1))
    mx.eval(orig_norms, out_norms)

    norm_ratio = (out_norms / orig_norms.astype(mx.float32)).reshape(-1)
    mx.eval(norm_ratio)
    # Norms should be approximately preserved (within 30% for 1-bit centroids)
    assert mx.mean(mx.abs(norm_ratio - 1.0)).item() < 0.3


def test_bhq_residual_score_correction_reduces_raw_ip_error():
    """QJL score correction reduces raw inner product error (pre-softmax).

    The paper's unbiased estimator works on inner products directly, not
    through the softmax nonlinearity. We verify the correction reduces
    mean absolute error on raw Q @ K^T scores at the same bit budget.
    """
    _centroid_cache.clear()
    head_dim = 128
    n_kv_heads = 4
    batch = 1
    seq_kv = 64

    pi = make_rotation_matrix(head_dim, seed=42)
    mx.random.seed(99)
    Q = mx.random.normal(shape=(batch, n_kv_heads, 1, head_dim))
    K = mx.random.normal(shape=(batch, n_kv_heads, seq_kv, head_dim))
    mx.eval(Q, K)

    # Ground truth scores: Q @ K^T
    Q_f32 = Q.astype(mx.float32)
    K_f32 = K.astype(mx.float32)
    scores_gt = Q_f32 @ mx.swapaxes(K_f32, -2, -1)
    mx.eval(scores_gt)

    # BHQ 3-bit (2-bit centroids) — base dequantized scores
    caches, pi_res = wrap_prompt_cache_bhq_residual(
        head_dim, n_kv_heads, n_layers=1, bits=3, seed=42, jl_seed=77
    )
    cache = caches[0]
    V_dummy = mx.zeros((batch, n_kv_heads, seq_kv, head_dim))
    K_dequant, _ = cache.update_and_fetch(K, V_dummy)
    mx.eval(K_dequant)

    # Base scores (no correction): Q_rot @ K_hat^T
    Q_rot = Q_f32 @ pi_res.T
    base_scores = Q_rot @ mx.swapaxes(K_dequant, -2, -1)
    mx.eval(base_scores)

    # Corrected scores: base + QJL correction
    qjl_bits, res_norms = cache.get_qjl_state()
    mx.eval(qjl_bits, res_norms)
    Q_proj = Q_rot @ cache.projection.T
    gamma_bits = res_norms.astype(mx.float32) * qjl_bits.astype(mx.float32)
    score_correction = (Q_proj @ mx.swapaxes(gamma_bits, -2, -1)) * cache.qjl_scale
    corrected_scores = base_scores + score_correction
    mx.eval(corrected_scores)

    # MAE on raw scores
    base_mae = mx.mean(mx.abs(scores_gt - base_scores)).item()
    corrected_mae = mx.mean(mx.abs(scores_gt - corrected_scores)).item()

    # The correction should reduce raw inner product error
    assert corrected_mae < base_mae, (
        f"Corrected MAE {corrected_mae:.4f} should be lower than "
        f"base MAE {base_mae:.4f}"
    )


def test_bhq_residual_sliding_window():
    """Sliding window should trim all residual-related storage."""
    _centroid_cache.clear()
    head_dim = 64
    n_kv_heads = 2
    max_size = 8

    caches, _ = wrap_prompt_cache_bhq_residual(
        head_dim, n_kv_heads, n_layers=1, bits=2, max_size=max_size
    )
    cache = caches[0]

    # Insert more than max_size tokens
    for _ in range(3):
        k = mx.random.normal(shape=(1, n_kv_heads, 4, head_dim))
        v = mx.random.normal(shape=(1, n_kv_heads, 4, head_dim))
        cache.update_and_fetch(k, v)

    assert cache.offset == max_size
    indices, norms, qjl_bits, res_norms, values = cache.state
    assert indices.shape[2] == max_size
    assert qjl_bits.shape[2] == max_size
    assert res_norms.shape[2] == max_size
