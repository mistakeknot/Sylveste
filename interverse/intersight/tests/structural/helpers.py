"""Helper utilities for structural tests."""
from pathlib import Path


def parse_frontmatter(path: Path) -> tuple[dict | None, str]:
    """Parse YAML frontmatter from a markdown file.

    Returns (frontmatter_dict, body) or (None, full_text) if no frontmatter.
    """
    import yaml

    text = path.read_text()
    if not text.startswith("---"):
        return None, text

    parts = text.split("---", 2)
    if len(parts) < 3:
        return None, text

    try:
        fm = yaml.safe_load(parts[1])
        return fm, parts[2]
    except yaml.YAMLError:
        return None, text
