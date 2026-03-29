"""Configuration loader for interseed."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml


def load_config(config_path: str | Path | None = None) -> dict[str, Any]:
    """Load config from YAML, falling back to defaults."""
    if config_path is None:
        # Look in standard locations
        candidates = [
            Path.home() / ".interseed" / "config.yaml",
            Path(__file__).parent.parent.parent / "config" / "default.yaml",
        ]
        for c in candidates:
            if c.exists():
                config_path = c
                break

    if config_path and Path(config_path).exists():
        with open(config_path) as f:
            return yaml.safe_load(f) or {}

    return {}


def get_db_path(config: dict[str, Any] | None = None) -> Path:
    """Resolve the SQLite database path."""
    if config and "db_path" in config:
        return Path(config["db_path"]).expanduser()
    return Path.home() / ".interseed" / "interseed.db"
