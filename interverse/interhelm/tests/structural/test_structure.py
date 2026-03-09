"""Tests for plugin structure."""

import json
import os
from pathlib import Path


def test_plugin_json_valid(project_root):
    """plugin.json is valid JSON with required fields."""
    path = project_root / ".claude-plugin" / "plugin.json"
    assert path.exists(), "Missing .claude-plugin/plugin.json"
    data = json.loads(path.read_text())
    for field in ("name", "version", "description", "author"):
        assert field in data, f"plugin.json missing required field: {field}"
    assert data["name"] == "interhelm"


def test_plugin_json_skills_match_filesystem(project_root, plugin_json):
    """Every skill listed in plugin.json exists on disk."""
    for skill_path in plugin_json.get("skills", []):
        resolved = project_root / skill_path
        assert resolved.is_dir(), f"Skill dir not found: {skill_path}"
        assert (resolved / "SKILL.md").exists(), f"Missing SKILL.md in {skill_path}"


def test_plugin_json_agents_match_filesystem(project_root, plugin_json):
    """Every agent listed in plugin.json exists on disk."""
    for agent_path in plugin_json.get("agents", []):
        resolved = project_root / agent_path
        assert resolved.exists(), f"Agent not found: {agent_path}"


def test_required_root_files(project_root):
    """All required root-level files exist."""
    required = ["CLAUDE.md", "PHILOSOPHY.md", "LICENSE", ".gitignore", "README.md", "AGENTS.md"]
    for name in required:
        assert (project_root / name).exists(), f"Missing required file: {name}"


def test_hooks_json_valid(project_root):
    """hooks.json is valid JSON with correct structure."""
    path = project_root / "hooks" / "hooks.json"
    assert path.exists(), "Missing hooks/hooks.json"
    data = json.loads(path.read_text())
    assert "hooks" in data, "hooks.json missing 'hooks' key"
    valid_events = {
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest",
        "PostToolUse", "PostToolUseFailure", "Notification", "SubagentStart",
        "SubagentStop", "Stop", "TeammateIdle", "TaskCompleted", "PreCompact",
        "SessionEnd",
    }
    for event in data["hooks"]:
        assert event in valid_events, f"Invalid hook event: {event}"


def test_hooks_scripts_executable(project_root):
    """All hook shell scripts are executable."""
    hooks_dir = project_root / "hooks"
    for script in hooks_dir.glob("*.sh"):
        assert os.access(script, os.X_OK), f"Hook script not executable: {script.name}"


def test_scripts_executable(project_root):
    """All shell scripts are executable."""
    scripts_dir = project_root / "scripts"
    if not scripts_dir.is_dir():
        return
    for script in scripts_dir.glob("*.sh"):
        assert os.access(script, os.X_OK), f"Script not executable: {script.name}"


def test_templates_exist(project_root):
    """Template directories exist with expected files."""
    rust_dir = project_root / "templates" / "rust-hyper"
    assert rust_dir.is_dir(), "Missing templates/rust-hyper/"
    assert (rust_dir / "Cargo.toml").exists(), "Missing rust-hyper/Cargo.toml"
    assert (rust_dir / "src" / "main.rs").exists(), "Missing rust-hyper/src/main.rs"

    cli_dir = project_root / "templates" / "cli"
    assert cli_dir.is_dir(), "Missing templates/cli/"
    assert (cli_dir / "Cargo.toml").exists(), "Missing cli/Cargo.toml"
    assert (cli_dir / "src" / "main.rs").exists(), "Missing cli/src/main.rs"
