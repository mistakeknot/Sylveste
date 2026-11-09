"""Entry-point scripts that a person or a timer runs directly must be executable.

Each file below has a shebang and is meant to be started as ``./<file>``; a
tracked mode of 100644 makes direct execution fail with "Permission denied".
"""
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent

ENTRY_POINTS = [
    "experiments/calibration-eval/scripts/run_matrix.sh",
    "experiments/calibration-eval/scripts/run_matrix_qwen.sh",
    "experiments/calibration-eval/scripts/run_rung.sh",
    "ops/canongraph/estate-drift-check.sh",
    "tests/test_beads_transport_hooks.sh",
]


@pytest.mark.parametrize("path", ENTRY_POINTS)
def test_entry_point_is_executable_in_git(path):
    out = subprocess.check_output(["git", "ls-files", "-s", "--", path], cwd=ROOT, text=True)
    assert out, f"{path} is not tracked"
    assert out.split()[0] == "100755", f"{path} has git mode {out.split()[0]}, expected 100755"
