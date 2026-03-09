"""Shared fixtures for structural tests."""

import json
from pathlib import Path

import pytest


@pytest.fixture(scope="session")
def project_root() -> Path:
    """Path to the repository root."""
    return Path(__file__).resolve().parent.parent.parent


@pytest.fixture(scope="session")
def skills_dir(project_root: Path) -> Path:
    return project_root / "skills"


@pytest.fixture(scope="session")
def agents_dir(project_root: Path) -> Path:
    return project_root / "agents"


@pytest.fixture(scope="session")
def scripts_dir(project_root: Path) -> Path:
    return project_root / "scripts"


@pytest.fixture(scope="session")
def plugin_json(project_root: Path) -> dict:
    """Parsed plugin.json."""
    with open(project_root / ".claude-plugin" / "plugin.json") as f:
        return json.load(f)
