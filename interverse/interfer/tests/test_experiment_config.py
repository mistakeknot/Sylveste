"""Tests for experiment configuration loader."""

from __future__ import annotations

import os
import tempfile
from pathlib import Path

from server.experiments.config import ExperimentConfig, load_experiment_configs


def test_load_defaults_yaml() -> None:
    """Loading from defaults.yaml returns expected experiments."""
    defaults = Path(__file__).parent.parent / "server" / "experiments" / "defaults.yaml"
    configs = load_experiment_configs(defaults)
    assert "early_exit" in configs
    assert "reservoir_routing" in configs
    assert configs["early_exit"].enabled is False
    assert configs["early_exit"].get("threshold") == 0.95


def test_env_override_enabled(monkeypatch) -> None:
    """INTERFERE_EXP_EARLYEXIT_ENABLED=true overrides config."""
    monkeypatch.setenv("INTERFERE_EXP_EARLYEXIT_ENABLED", "true")
    configs = load_experiment_configs(config_path="/dev/null")
    assert configs["earlyexit"].enabled is True


def test_env_override_param(monkeypatch) -> None:
    """INTERFERE_EXP_EARLYEXIT_THRESHOLD=0.8 sets param."""
    monkeypatch.setenv("INTERFERE_EXP_EARLYEXIT_ENABLED", "true")
    monkeypatch.setenv("INTERFERE_EXP_EARLYEXIT_THRESHOLD", "0.8")
    configs = load_experiment_configs(config_path="/dev/null")
    assert configs["earlyexit"].get("threshold") == 0.8


def test_empty_config_returns_empty() -> None:
    """No config file and no env vars returns empty dict."""
    configs = load_experiment_configs(config_path="/dev/null")
    # Only env-derived configs should be present
    env_keys = [k for k in os.environ if k.startswith("INTERFERE_EXP_")]
    assert len(configs) == len(set(k.split("_")[2].lower() for k in env_keys))


def test_experiment_config_get_default() -> None:
    """ExperimentConfig.get returns default for missing keys."""
    cfg = ExperimentConfig(name="test", params={"a": 1})
    assert cfg.get("a") == 1
    assert cfg.get("missing", 42) == 42
