"""Tests for skill content."""

import yaml
from pathlib import Path


def test_skill_count(skills_dir):
    """Expected number of skills."""
    skills = list(skills_dir.glob("*/SKILL.md"))
    assert len(skills) == 3, (
        f"Expected 3 skills, found {len(skills)}: {[s.parent.name for s in skills]}"
    )


def test_skill_frontmatter(skills_dir):
    """Each SKILL.md has valid YAML frontmatter with required fields."""
    for skill_md in skills_dir.glob("*/SKILL.md"):
        content = skill_md.read_text()
        assert content.startswith("---"), f"{skill_md}: missing frontmatter"
        parts = content.split("---", 2)
        assert len(parts) >= 3, f"{skill_md}: malformed frontmatter"
        fm = yaml.safe_load(parts[1])
        assert "name" in fm, f"{skill_md}: frontmatter missing 'name'"
        assert "description" in fm, f"{skill_md}: frontmatter missing 'description'"
        assert fm["name"] == skill_md.parent.name, (
            f"{skill_md}: name '{fm['name']}' doesn't match dir '{skill_md.parent.name}'"
        )


def test_agent_count(agents_dir):
    """Expected number of agents."""
    agents = list(agents_dir.rglob("*.md"))
    assert len(agents) == 1, (
        f"Expected 1 agent, found {len(agents)}: {[a.name for a in agents]}"
    )


def test_agent_frontmatter(agents_dir):
    """Each agent .md has valid YAML frontmatter."""
    for agent_md in agents_dir.rglob("*.md"):
        content = agent_md.read_text()
        assert content.startswith("---"), f"{agent_md}: missing frontmatter"
        parts = content.split("---", 2)
        assert len(parts) >= 3, f"{agent_md}: malformed frontmatter"
        fm = yaml.safe_load(parts[1])
        assert "name" in fm, f"{agent_md}: frontmatter missing 'name'"
        assert "description" in fm, f"{agent_md}: frontmatter missing 'description'"
        assert "model" in fm, f"{agent_md}: frontmatter missing 'model'"
