"""Model loading and memory budget management for interfer."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass
class LoadedModel:
    """A model currently held in the memory budget."""

    name: str
    estimated_bytes: int
    model: Any | None = None
    tokenizer: Any | None = None


class ModelRegistry:
    """Tracks loaded models and enforces a memory budget.

    The registry refuses to load a model whose estimated_bytes would
    push total usage past the configured budget, raising MemoryError.
    """

    def __init__(self, memory_budget_bytes: int) -> None:
        self._budget = memory_budget_bytes
        self._models: dict[str, LoadedModel] = {}

    # -- properties ----------------------------------------------------------

    @property
    def loaded_models(self) -> list[str]:
        """Names of all currently loaded models."""
        return list(self._models.keys())

    @property
    def available_memory_bytes(self) -> int:
        """Remaining budget after accounting for loaded models."""
        used = sum(m.estimated_bytes for m in self._models.values())
        return self._budget - used

    # -- mutations -----------------------------------------------------------

    def load(
        self,
        name: str,
        estimated_bytes: int,
        model: Any | None = None,
        tokenizer: Any | None = None,
    ) -> LoadedModel:
        """Register a model, consuming part of the memory budget.

        Raises MemoryError if *estimated_bytes* exceeds the remaining budget.
        """
        if estimated_bytes > self.available_memory_bytes:
            raise MemoryError(
                f"Loading {name!r} ({estimated_bytes} bytes) exceeds budget "
                f"({self.available_memory_bytes} bytes available)"
            )
        entry = LoadedModel(
            name=name,
            estimated_bytes=estimated_bytes,
            model=model,
            tokenizer=tokenizer,
        )
        self._models[name] = entry
        return entry

    def unload(self, name: str) -> None:
        """Remove a model and free its budget allocation."""
        self._models.pop(name, None)

    def get(self, name: str) -> LoadedModel | None:
        """Look up a loaded model by name, or None if not loaded."""
        return self._models.get(name)
