"""Prompt cache manager for shared prefix deduplication.

Clavain agents share substantial prompt prefixes (system prompts, CLAUDE.md,
skill injections). This module caches the KV state for seen prefixes so
subsequent requests skip prefill for the shared portion.

The cache is keyed by a hash of the prompt prefix. When a request arrives,
we find the longest matching prefix in the cache and use its KV state.

Storage: KV caches are saved to disk via mlx-lm's save_prompt_cache/load_prompt_cache.
"""

from __future__ import annotations

import hashlib
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass
class CacheEntry:
    """A cached prompt prefix with its KV state file."""

    prefix_hash: str
    prefix_length: int  # number of tokens
    file_path: Path
    model_name: str
    created_at: float = field(default_factory=time.time)
    hit_count: int = 0
    last_hit_at: float = 0.0

    @property
    def age_s(self) -> float:
        return time.time() - self.created_at


@dataclass
class CacheStats:
    """Running stats for the prompt cache."""

    total_lookups: int = 0
    hits: int = 0
    misses: int = 0
    evictions: int = 0
    total_tokens_saved: int = 0

    @property
    def hit_rate(self) -> float:
        return self.hits / self.total_lookups if self.total_lookups else 0.0

    def to_dict(self) -> dict:
        return {
            "total_lookups": self.total_lookups,
            "hits": self.hits,
            "misses": self.misses,
            "hit_rate": round(self.hit_rate, 3),
            "evictions": self.evictions,
            "total_tokens_saved": self.total_tokens_saved,
        }


class PromptCacheManager:
    """Manages KV cache files for prompt prefix deduplication.

    Usage::

        cache_mgr = PromptCacheManager(cache_dir="/tmp/interfer-cache")

        # Check for cached prefix
        entry = cache_mgr.lookup(prompt_tokens, model_name="local:qwen3.5-35b")
        if entry:
            kv_cache = load_prompt_cache(entry.file_path)
            # Skip prefill for entry.prefix_length tokens
        else:
            # Full prefill, then save
            cache_mgr.store(prompt_tokens, model_name, kv_cache)
    """

    def __init__(
        self,
        cache_dir: str | Path = "/tmp/interfer-prompt-cache",
        max_entries: int = 32,
        max_age_s: float = 3600.0,  # 1 hour default TTL
    ) -> None:
        self._cache_dir = Path(cache_dir)
        self._cache_dir.mkdir(parents=True, exist_ok=True)
        self._max_entries = max_entries
        self._max_age_s = max_age_s
        self._entries: dict[str, CacheEntry] = {}
        self._stats = CacheStats()

    @property
    def stats(self) -> CacheStats:
        return self._stats

    @staticmethod
    def _hash_prefix(tokens: list[int], length: int) -> str:
        """Hash the first *length* tokens to create a cache key."""
        prefix_bytes = bytes(str(tokens[:length]), "utf-8")
        return hashlib.sha256(prefix_bytes).hexdigest()[:16]

    def lookup(
        self,
        prompt_tokens: list[int],
        model_name: str,
    ) -> CacheEntry | None:
        """Find the longest cached prefix matching *prompt_tokens*.

        Returns the CacheEntry if found, or None on miss. Checks progressively
        shorter prefixes until a match is found.
        """
        self._stats.total_lookups += 1

        # Try the full prompt first, then progressively shorter prefixes
        # Step down in chunks of 64 tokens for efficiency
        for length in range(len(prompt_tokens), 0, -64):
            key = self._hash_prefix(prompt_tokens, length) + f":{model_name}"
            entry = self._entries.get(key)
            if entry and entry.file_path.exists() and entry.age_s < self._max_age_s:
                entry.hit_count += 1
                entry.last_hit_at = time.time()
                self._stats.hits += 1
                self._stats.total_tokens_saved += entry.prefix_length
                return entry

        self._stats.misses += 1
        return None

    def store(
        self,
        prompt_tokens: list[int],
        model_name: str,
        kv_cache: Any,
    ) -> CacheEntry:
        """Save a KV cache for the given prompt tokens.

        Evicts the oldest entry if at capacity.
        """
        from mlx_lm.generate import cache as mlx_cache

        length = len(prompt_tokens)
        prefix_hash = self._hash_prefix(prompt_tokens, length)
        key = prefix_hash + f":{model_name}"

        # Evict if at capacity
        if len(self._entries) >= self._max_entries:
            self._evict_oldest()

        # Save KV cache to disk
        file_path = (
            self._cache_dir
            / f"{prefix_hash}-{model_name.replace('/', '_')}.safetensors"
        )
        mlx_cache.save_prompt_cache(
            str(file_path),
            kv_cache,
            metadata={"model": model_name, "prefix_length": str(length)},
        )

        entry = CacheEntry(
            prefix_hash=prefix_hash,
            prefix_length=length,
            file_path=file_path,
            model_name=model_name,
        )
        self._entries[key] = entry
        return entry

    def load_kv_cache(self, entry: CacheEntry) -> Any:
        """Load a KV cache from a cache entry's file."""
        from mlx_lm.generate import cache as mlx_cache

        return mlx_cache.load_prompt_cache(str(entry.file_path))

    def _evict_oldest(self) -> None:
        """Remove the least-recently-used cache entry."""
        if not self._entries:
            return

        oldest_key = min(
            self._entries,
            key=lambda k: self._entries[k].last_hit_at or self._entries[k].created_at,
        )
        entry = self._entries.pop(oldest_key)
        if entry.file_path.exists():
            entry.file_path.unlink()
        self._stats.evictions += 1

    def clear(self) -> None:
        """Remove all cached entries."""
        for entry in self._entries.values():
            if entry.file_path.exists():
                entry.file_path.unlink()
        self._entries.clear()
