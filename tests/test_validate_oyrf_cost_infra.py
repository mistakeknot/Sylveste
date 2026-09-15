"""Coverage for scripts/validate_oyrf_cost_infra.py's workflow and timer contracts.

The validator once asserted `actions/checkout@v4` and nothing about what the
workflow did with the exporter's output; a Dependabot bump broke the assertion
and the vacuous six-hourly export ran on regardless. These tests pin the
contract that replaced it: CI validates and never publishes; the timer under
ops/ publishes and never fabricates.
"""

import importlib.util
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
_SPEC = importlib.util.spec_from_file_location(
    "validate_oyrf_cost_infra", ROOT / "scripts" / "validate_oyrf_cost_infra.py"
)
val = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(val)

GOOD_WORKFLOW = (ROOT / ".github" / "workflows" / "oyrf-cost-calibration.yml").read_text()


def _workflow_failures(monkeypatch, tmp_path, text):
    path = tmp_path / "wf.yml"
    path.write_text(text)
    monkeypatch.setattr(val, "WORKFLOW", path)
    failures: list[str] = []
    val.validate_workflow(failures)
    return failures


def test_repo_passes_full_validation():
    assert val.validate(run_dry_run=False) == []


def test_committed_workflow_satisfies_contract(monkeypatch, tmp_path):
    assert _workflow_failures(monkeypatch, tmp_path, GOOD_WORKFLOW) == []


@pytest.mark.parametrize(
    "mutation, expected",
    [
        (("on:\n", "on:\n  schedule:\n    - cron: '0 */6 * * *'\n"), "schedule"),
        (("contents: read", "contents: write"), "contents: write"),
        (("run: python3 scripts/validate_oyrf_cost_infra.py --run-dry-run",
          "run: bash estimate-costs.sh"), "estimate-costs.sh"),
        (("actions/checkout@v7", "actions/checkout@v9"), None),  # any major is fine
    ],
)
def test_workflow_contract(monkeypatch, tmp_path, mutation, expected):
    old, new = mutation
    assert old in GOOD_WORKFLOW
    failures = _workflow_failures(monkeypatch, tmp_path, GOOD_WORKFLOW.replace(old, new, 1))
    if expected is None:
        assert failures == []
    else:
        assert failures, "mutation should have been refused"
        assert any(expected in f for f in failures), failures


def test_workflow_that_pushes_to_oyrf_data_is_refused(monkeypatch, tmp_path):
    text = GOOD_WORKFLOW + "\n      - run: git push origin HEAD:oyrf-data\n"
    failures = _workflow_failures(monkeypatch, tmp_path, text)
    assert any("oyrf-data" in f for f in failures), failures


def test_exporter_timer_refusal_is_required(monkeypatch, tmp_path):
    exporter_dir = tmp_path / "oyrf-cost-export"
    exporter_dir.mkdir()
    src = ROOT / "ops" / "oyrf-cost-export"
    for name in ("oyrf-cost-export.sh", "oyrf-cost-export.service", "oyrf-cost-export.timer"):
        (exporter_dir / name).write_text((src / name).read_text())
    (exporter_dir / "oyrf-cost-export.sh").chmod(0o755)
    monkeypatch.setattr(val, "EXPORTER_DIR", exporter_dir)

    failures: list[str] = []
    val.validate_exporter_timer(failures)
    assert failures == []

    # Strip the guard that turns an empty interstat result into exit 3.
    script = exporter_dir / "oyrf-cost-export.sh"
    script.write_text(script.read_text().replace('if [ "$source" != "interstat" ]; then', "if false; then"))
    failures = []
    val.validate_exporter_timer(failures)
    assert any("interstat-empty" in f or "refuse" in f for f in failures), failures


def test_exporter_timer_needs_persistent_schedule(monkeypatch, tmp_path):
    exporter_dir = tmp_path / "oyrf-cost-export"
    exporter_dir.mkdir()
    src = ROOT / "ops" / "oyrf-cost-export"
    for name in ("oyrf-cost-export.sh", "oyrf-cost-export.service", "oyrf-cost-export.timer"):
        (exporter_dir / name).write_text((src / name).read_text())
    (exporter_dir / "oyrf-cost-export.sh").chmod(0o755)
    (exporter_dir / "oyrf-cost-export.timer").write_text("[Timer]\nOnCalendar=daily\n")
    monkeypatch.setattr(val, "EXPORTER_DIR", exporter_dir)
    failures: list[str] = []
    val.validate_exporter_timer(failures)
    assert any("Persistent=true" in f for f in failures), failures
