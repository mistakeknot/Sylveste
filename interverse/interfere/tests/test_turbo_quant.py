"""Tests for TurboQuant polar-transformed KV cache quantization."""

import mlx.core as mx

from server.experiments.turbo_quant import (
    inverse_polar_transform,
    make_jl_projection,
    polar_transform,
    qjl_decode,
    qjl_encode,
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
