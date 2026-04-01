"""Experiment configuration loader.

Reads experiment toggles and parameters from a YAML config file
or environment variables. Each experiment has an enabled flag and
arbitrary parameters.

Config file location (checked in order):
  1. INTERFERE_EXPERIMENTS_CONFIG env var
  2. ./experiments.yaml (cwd)
  3. server/experiments/defaults.yaml (package default)

Environment variable overrides:
  INTERFERE_EXP_{NAME}_ENABLED=true|false
  INTERFERE_EXP_{NAME}_{PARAM}=value
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass
class ExperimentConfig:
    """Configuration for a single experiment."""

    name: str
    enabled: bool = False
    params: dict[str, Any] = field(default_factory=dict)

    def get(self, key: str, default: Any = None) -> Any:
        return self.params.get(key, default)


def _parse_yaml(path: Path) -> dict[str, Any]:
    """Parse a YAML file, returning empty dict on failure."""
    try:
        import yaml

        with open(path) as f:
            return yaml.safe_load(f) or {}
    except (ImportError, FileNotFoundError, Exception):
        return {}


def _apply_env_overrides(configs: dict[str, ExperimentConfig]) -> None:
    """Apply INTERFERE_EXP_* environment variable overrides."""
    prefix = "INTERFERE_EXP_"
    for key, value in os.environ.items():
        if not key.startswith(prefix):
            continue
        parts = key[len(prefix) :].lower().split("_", 1)
        exp_name = parts[0]
        if exp_name not in configs:
            configs[exp_name] = ExperimentConfig(name=exp_name)

        if len(parts) == 1 or parts[1] == "enabled":
            configs[exp_name].enabled = value.lower() in ("true", "1", "yes")
        else:
            param_name = parts[1]
            # Try to parse as number
            try:
                configs[exp_name].params[param_name] = float(value)
            except ValueError:
                configs[exp_name].params[param_name] = value


def load_experiment_configs(
    config_path: str | Path | None = None,
) -> dict[str, ExperimentConfig]:
    """Load experiment configs from YAML + env overrides.

    Returns a dict mapping experiment name to ExperimentConfig.
    """
    # Find config file
    if config_path is None:
        config_path = os.environ.get("INTERFERE_EXPERIMENTS_CONFIG")
    if config_path is None:
        cwd_path = Path("experiments.yaml")
        if cwd_path.exists():
            config_path = cwd_path
    if config_path is None:
        pkg_path = Path(__file__).parent / "defaults.yaml"
        if pkg_path.exists():
            config_path = pkg_path

    # Parse YAML
    raw = {}
    if config_path is not None:
        raw = _parse_yaml(Path(config_path))

    # Build configs
    experiments = raw.get("experiments", {})
    configs: dict[str, ExperimentConfig] = {}
    for name, settings in experiments.items():
        if isinstance(settings, dict):
            enabled = settings.pop("enabled", False)
            configs[name] = ExperimentConfig(
                name=name, enabled=bool(enabled), params=settings
            )
        else:
            configs[name] = ExperimentConfig(name=name, enabled=bool(settings))

    # Apply env overrides
    _apply_env_overrides(configs)

    return configs
