"""Shared helpers for structural tests -- delegates to _shared."""

import sys
from pathlib import Path

# Add interverse/ to path so _shared package is importable
_interverse = Path(__file__).resolve().parents[3]
if str(_interverse) not in sys.path:
    sys.path.insert(0, str(_interverse))

from _shared.tests.structural.helpers import parse_frontmatter

__all__ = ["parse_frontmatter"]
