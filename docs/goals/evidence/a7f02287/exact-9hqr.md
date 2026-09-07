# Plan: an empty output file pre-created by the engine is not fresh output (mk-9hqr)

Contract: exact

`dispatch_task` in `scripts/orchestrate.py` treats `output.md` as fresh output whenever the file exists. On the claude and kimi engines `dispatch.sh` pipes the seat's stdout through `tee "$OUTPUT"`, which creates the file before the model writes anything, so an executor that timed out having written nothing is reported as `timeout (no output movement)` with an output path instead of `timed out, no fresh output` with none (found by the validation seat on run 120d9aa1, goal 60771535). Freshness now requires a non-empty file.

## Preconditions

```bash
test -f scripts/orchestrate.py
grep -q '^    fresh_output = os.path.exists(output_path)$' scripts/orchestrate.py
! test -e tests/structural/test_orchestrate_fresh_output.py
```

## Task 1: require a non-empty output file

old_string (scripts/orchestrate.py):
```python
    note: str | None = None
    fresh_output = os.path.exists(output_path)
```

new_string (scripts/orchestrate.py):
```python
    note: str | None = None
    # A file that exists but is empty is not output: dispatch.sh pre-creates
    # output.md through tee on the claude and kimi engines, so an existence
    # check reads a silent timeout as output movement (mk-9hqr).
    fresh_output = os.path.exists(output_path) and os.path.getsize(output_path) > 0
```

Create `tests/structural/test_orchestrate_fresh_output.py` with:

```python
"""An empty output file pre-created by the engine is not fresh output (mk-9hqr)."""

import importlib.util
import sys
from pathlib import Path

import pytest


@pytest.fixture(scope="module")
def orc(project_root: Path):
    spec = importlib.util.spec_from_file_location(
        "orchestrate_fresh", project_root / "scripts" / "orchestrate.py"
    )
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules["orchestrate_fresh"] = mod
    spec.loader.exec_module(mod)
    yield mod
    sys.modules.pop("orchestrate_fresh", None)


STUB = """#!/bin/bash
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) OUT="$2"; shift 2;;
    *) shift;;
  esac
done
: > "$OUT"
sleep 5
"""


def _inputs(orc, tmp_path: Path):
    project = tmp_path / "project"
    project.mkdir()
    task = orc.Task(id="task-1", title="empty output", stage="test", files=[])
    manifest = orc.Manifest(
        version=1, mode="dependency-driven", tier="fast", max_parallel=1,
        timeout_per_task=1, stages=[], tasks={task.id: task},
    )
    run_dir = tmp_path / "run"
    run_dir.mkdir()
    stub = tmp_path / "dispatch.sh"
    stub.write_text(STUB)
    stub.chmod(0o755)
    return project, task, manifest, run_dir, stub


def test_an_empty_pre_created_output_file_is_not_fresh(orc, tmp_path, monkeypatch):
    project, task, manifest, run_dir, stub = _inputs(orc, tmp_path)
    monkeypatch.setenv("CLAVAIN_DISPATCH_SH", str(stub))
    result = orc.dispatch_task(
        task, manifest, str(project), None, {}, str(stub), "testrun", str(run_dir),
    )
    assert result.status == "error"
    assert result.output_path is None
    assert "timed out, no fresh output" in (result.error or "")
    assert (run_dir / task.id / "output.md").exists(), "the stub pre-created the file"
```

### Verify Task 1

```bash
python3 -m py_compile scripts/orchestrate.py
grep -c 'os.path.getsize(output_path) > 0' scripts/orchestrate.py
cd tests && uv run pytest structural/test_orchestrate_fresh_output.py structural/test_orchestrate_stale_output.py -q
```

Expected: exit 0

## Commit

Message file: written by the orchestrator. Pathspec: `scripts/orchestrate.py tests/structural/test_orchestrate_fresh_output.py`.
