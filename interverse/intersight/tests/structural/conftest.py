"""Shared fixtures for intersight structural tests."""
import json
from pathlib import Path

import pytest


@pytest.fixture
def plugin_root():
    """Return the plugin root directory."""
    return Path(__file__).resolve().parent.parent.parent


@pytest.fixture
def plugin_json(plugin_root):
    """Parse and return plugin.json contents."""
    pj = plugin_root / ".claude-plugin" / "plugin.json"
    assert pj.exists(), f"plugin.json not found at {pj}"
    return json.loads(pj.read_text())


@pytest.fixture
def skills_dir(plugin_root):
    """Return the skills directory."""
    sd = plugin_root / "skills"
    assert sd.is_dir(), f"skills/ directory not found at {sd}"
    return sd


@pytest.fixture
def scripts_dir(plugin_root):
    """Return the scripts/extraction directory."""
    sd = plugin_root / "scripts" / "extraction"
    assert sd.is_dir(), f"scripts/extraction/ not found at {sd}"
    return sd
