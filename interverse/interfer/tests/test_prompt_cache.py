"""Tests for the prompt cache manager."""

from __future__ import annotations

import tempfile
from pathlib import Path

from server.prompt_cache import CacheEntry, CacheStats, PromptCacheManager


def test_cache_stats_hit_rate() -> None:
    """Stats compute hit rate correctly."""
    stats = CacheStats(total_lookups=10, hits=7, misses=3)
    assert stats.hit_rate == 0.7
    d = stats.to_dict()
    assert d["hit_rate"] == 0.7


def test_cache_stats_empty() -> None:
    """Empty stats return zero hit rate."""
    stats = CacheStats()
    assert stats.hit_rate == 0.0


def test_cache_manager_miss_on_empty() -> None:
    """Lookup on empty cache returns None."""
    with tempfile.TemporaryDirectory() as tmpdir:
        mgr = PromptCacheManager(cache_dir=tmpdir)
        result = mgr.lookup([1, 2, 3, 4, 5], model_name="test-model")
        assert result is None
        assert mgr.stats.misses == 1
        assert mgr.stats.hits == 0


def test_cache_manager_hash_deterministic() -> None:
    """Same tokens produce same hash."""
    h1 = PromptCacheManager._hash_prefix([1, 2, 3], 3)
    h2 = PromptCacheManager._hash_prefix([1, 2, 3], 3)
    assert h1 == h2


def test_cache_manager_hash_different_for_different_tokens() -> None:
    """Different tokens produce different hashes."""
    h1 = PromptCacheManager._hash_prefix([1, 2, 3], 3)
    h2 = PromptCacheManager._hash_prefix([4, 5, 6], 3)
    assert h1 != h2


def test_cache_entry_age() -> None:
    """CacheEntry.age_s returns positive value."""
    entry = CacheEntry(
        prefix_hash="abc123",
        prefix_length=100,
        file_path=Path("/tmp/test.safetensors"),
        model_name="test",
    )
    assert entry.age_s >= 0.0


def test_cache_manager_clear() -> None:
    """Clear removes all entries."""
    with tempfile.TemporaryDirectory() as tmpdir:
        mgr = PromptCacheManager(cache_dir=tmpdir)
        mgr._entries["test"] = CacheEntry(
            prefix_hash="abc",
            prefix_length=10,
            file_path=Path(tmpdir) / "nonexistent.safetensors",
            model_name="test",
        )
        assert len(mgr._entries) == 1
        mgr.clear()
        assert len(mgr._entries) == 0
