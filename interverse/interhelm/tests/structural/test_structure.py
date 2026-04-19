"""Tests for plugin structure."""

import json
import os
import sys
from pathlib import Path

# Add interverse/ to path so _shared package is importable
_interverse = Path(__file__).resolve().parents[3]
if str(_interverse) not in sys.path:
    sys.path.insert(0, str(_interverse))

from _shared.tests.structural.test_base import StructuralTests


class TestStructure(StructuralTests):
    """Structural tests -- inherits shared base, adds plugin-specific checks."""

    def test_plugin_name(self, plugin_json):
        assert plugin_json["name"] == "interhelm"

    def test_required_root_files(self, project_root):
        """Override: interhelm requires the stricter 6-file set."""
        required = ["CLAUDE.md", "PHILOSOPHY.md", "LICENSE", ".gitignore", "README.md", "AGENTS.md"]
        for name in required:
            assert (project_root / name).exists(), f"Missing required file: {name}"

    def test_plugin_json_agents_match_filesystem(self, project_root, plugin_json):
        """Every agent listed in plugin.json exists on disk."""
        for agent_path in plugin_json.get("agents", []):
            resolved = project_root / agent_path
            assert resolved.exists(), f"Agent not found: {agent_path}"

    def test_hooks_json_valid(self, project_root):
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

    def test_hooks_scripts_executable(self, project_root):
        """All hook shell scripts are executable."""
        hooks_dir = project_root / "hooks"
        for script in hooks_dir.glob("*.sh"):
            assert os.access(script, os.X_OK), f"Hook script not executable: {script.name}"

    def test_templates_exist(self, project_root):
        """Template directories exist with expected files."""
        rust_dir = project_root / "templates" / "rust-hyper"
        assert rust_dir.is_dir(), "Missing templates/rust-hyper/"
        assert (rust_dir / "Cargo.toml").exists(), "Missing rust-hyper/Cargo.toml"
        assert (rust_dir / "src" / "main.rs").exists(), "Missing rust-hyper/src/main.rs"

        cli_dir = project_root / "templates" / "cli"
        assert cli_dir.is_dir(), "Missing templates/cli/"
        assert (cli_dir / "Cargo.toml").exists(), "Missing cli/Cargo.toml"
        assert (cli_dir / "src" / "main.rs").exists(), "Missing cli/src/main.rs"
