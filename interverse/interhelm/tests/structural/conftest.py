"""Shared fixtures for structural tests."""

import sys
from pathlib import Path

# Add interverse/ to path so _shared package is importable
_interverse = Path(__file__).resolve().parents[3]
if str(_interverse) not in sys.path:
    sys.path.insert(0, str(_interverse))

from _shared.tests.structural.conftest_base import create_structural_fixtures

PROJECT_ROOT = Path(__file__).resolve().parents[2]
fixtures = create_structural_fixtures(PROJECT_ROOT)

# Register fixtures in this module's namespace so pytest discovers them
project_root = fixtures["project_root"]
plugin_json = fixtures["plugin_json"]
skills_dir = fixtures["skills_dir"]
commands_dir = fixtures["commands_dir"]
agents_dir = fixtures["agents_dir"]
scripts_dir = fixtures["scripts_dir"]
