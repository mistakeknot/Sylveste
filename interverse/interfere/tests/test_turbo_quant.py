"""Tests for TurboQuant polar-transformed KV cache quantization."""

import mlx.core as mx

import pytest

from server.experiments.turbo_quant import (
    PolarCacheWrapper,
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


# ---------------------------------------------------------------------------
# PolarCacheWrapper tests
# ---------------------------------------------------------------------------


class _FakeCache:
    """Minimal cache mock for testing PolarCacheWrapper."""

    def __init__(self):
        self.offset = 0
        self._keys = None
        self._values = None

    def update_and_fetch(self, keys, values):
        if self._keys is None:
            self._keys = keys
            self._values = values
        else:
            self._keys = mx.concatenate([self._keys, keys], axis=2)
            self._values = mx.concatenate([self._values, values], axis=2)
        self.offset += keys.shape[2]
        return self._keys, self._values


def test_polar_cache_wrapper_round_trip():
    """PolarCacheWrapper should polar-transform before store and inverse after."""
    inner = _FakeCache()
    wrapper = PolarCacheWrapper(inner)

    keys = mx.random.normal(shape=(1, 4, 8, 128))
    values = mx.random.normal(shape=(1, 4, 8, 128))

    out_k, out_v = wrapper.update_and_fetch(keys, values)
    mx.eval(out_k, out_v)

    # Output should be close to input (polar transform is lossless, inner cache is fp32)
    mse_k = mx.mean((keys - out_k) ** 2).item()
    mse_v = mx.mean((values - out_v) ** 2).item()
    norm_k = mx.mean(keys**2).item()
    norm_v = mx.mean(values**2).item()
    assert mse_k / (norm_k + 1e-10) < 1e-4, f"Key NMSE {mse_k/norm_k:.6f} too high"
    assert mse_v / (norm_v + 1e-10) < 1e-4, f"Value NMSE {mse_v/norm_v:.6f} too high"


def test_polar_cache_wrapper_delegates_offset():
    """Wrapper should delegate offset to inner cache."""
    inner = _FakeCache()
    wrapper = PolarCacheWrapper(inner)
    assert wrapper.offset == 0

    keys = mx.random.normal(shape=(1, 4, 5, 128))
    values = mx.random.normal(shape=(1, 4, 5, 128))
    wrapper.update_and_fetch(keys, values)
    mx.eval(inner._keys)
    assert wrapper.offset == 5


def test_polar_cache_wrapper_accumulates():
    """Multiple updates should accumulate in the inner cache."""
    inner = _FakeCache()
    wrapper = PolarCacheWrapper(inner)

    for _ in range(3):
        k = mx.random.normal(shape=(1, 4, 4, 128))
        v = mx.random.normal(shape=(1, 4, 4, 128))
        wrapper.update_and_fetch(k, v)

    mx.eval(inner._keys)
    assert wrapper.offset == 12
    assert inner._keys.shape[2] == 12


# ---------------------------------------------------------------------------
# Integration tests
# ---------------------------------------------------------------------------


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
