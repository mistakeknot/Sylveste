"""Validate intersight skill structure."""
from helpers import parse_frontmatter


def test_skill_count(skills_dir):
    """Expected number of skills."""
    skill_dirs = [d for d in skills_dir.iterdir() if d.is_dir()]
    assert len(skill_dirs) == 1, (
        f"Expected 1 skill, found {len(skill_dirs)}: {[d.name for d in skill_dirs]}"
    )


def test_skill_frontmatter(skills_dir):
    """Every SKILL.md has valid frontmatter with description."""
    for skill_dir in skills_dir.iterdir():
        if not skill_dir.is_dir():
            continue
        skill_md = skill_dir / "SKILL.md"
        assert skill_md.exists(), f"Missing SKILL.md in {skill_dir.name}"
        fm, _ = parse_frontmatter(skill_md)
        assert fm is not None, f"No YAML frontmatter in {skill_dir.name}/SKILL.md"
        assert "description" in fm, f"Missing 'description' in {skill_dir.name}/SKILL.md frontmatter"
