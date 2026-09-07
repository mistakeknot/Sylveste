# Plan: scope the review's dirty-tree check to paths outside sibling tasks' declared files (mk-b7e0)

Contract: exact

`dispatch_review` in `scripts/orchestrate.py` compares `git status --porcelain` before and after the reviewer runs and invalidates the review when they differ. With `max_parallel > 1`, sibling executors commit into the same working tree while a review runs, so clean reviews were invalidated every round and tasks escalated on false positives (uncrancher run 57651f7d, 2026-09-02). The snapshot now drops every path a sibling task declares in the manifest.

## Preconditions

```bash
test -f scripts/orchestrate.py
! grep -q '_review_dirty_snapshot' scripts/orchestrate.py
```

## Task 1: add the scoped snapshot and use it in both comparisons

In `scripts/orchestrate.py`, add the helper directly above `dispatch_review`:

old_string (scripts/orchestrate.py):
```python
def dispatch_review(
```

new_string (scripts/orchestrate.py):
```python
def _review_dirty_snapshot(project_dir: str, task: Task, manifest: Manifest) -> str:
    """git status --porcelain minus the paths sibling tasks declare. With
    max_parallel > 1 siblings commit into the same tree while a review runs,
    and a snapshot that includes their files invalidates clean reviews on
    every round (mk-b7e0). A declared directory covers everything under it."""
    siblings = {
        f for t in manifest.tasks.values() if t.id != task.id for f in t.files
    }
    dirs = tuple(s.rstrip("/") + "/" for s in siblings)
    kept: list[str] = []
    for line in _git(project_dir, "status", "--porcelain").splitlines():
        path = line[3:].split(" -> ")[-1].strip()
        if path in siblings or path.startswith(dirs):
            continue
        kept.append(line)
    return "\n".join(kept)


def dispatch_review(
```

Then replace both snapshots in `dispatch_review`:

old_string (scripts/orchestrate.py):
```python
    dirty_before = _git(project_dir, "status", "--porcelain")
```

new_string (scripts/orchestrate.py):
```python
    dirty_before = _review_dirty_snapshot(project_dir, task, manifest)
```

old_string (scripts/orchestrate.py):
```python
    dirty_after = _git(project_dir, "status", "--porcelain")
```

new_string (scripts/orchestrate.py):
```python
    dirty_after = _review_dirty_snapshot(project_dir, task, manifest)
```

Create `tests/structural/test_orchestrate_review_dirty_scope.py` with:

```python
"""_review_dirty_snapshot ignores the paths sibling tasks declare (mk-b7e0)."""

import importlib.util
import subprocess
import sys
from pathlib import Path

import pytest


@pytest.fixture(scope="module")
def orc(project_root: Path):
    spec = importlib.util.spec_from_file_location(
        "orchestrate_dirty", project_root / "scripts" / "orchestrate.py"
    )
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules["orchestrate_dirty"] = mod
    spec.loader.exec_module(mod)
    yield mod
    sys.modules.pop("orchestrate_dirty", None)


def _git(repo: Path, *args: str) -> None:
    subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True)


def _repo(tmp_path: Path) -> Path:
    repo = tmp_path / "repo"
    repo.mkdir()
    subprocess.run(["git", "init", "-q", "-b", "main", str(repo)], check=True)
    _git(repo, "config", "user.email", "t@t")
    _git(repo, "config", "user.name", "t")
    _git(repo, "config", "commit.gpgsign", "false")
    return repo


def _manifest(orc):
    t1 = orc.Task(id="task-1", title="one", stage="s", files=["a.py"])
    t2 = orc.Task(id="task-2", title="two", stage="s", files=["b.py", "pkg/"])
    manifest = orc.Manifest(
        version=1, mode="dependency-driven", tier="fast", max_parallel=2,
        timeout_per_task=60, stages=[], tasks={"task-1": t1, "task-2": t2},
    )
    return t1, manifest


def test_sibling_paths_are_dropped_from_the_snapshot(orc, tmp_path):
    repo = _repo(tmp_path)
    for name in ("a.py", "b.py", "c.py"):
        (repo / name).write_text("x = 1\n")
    (repo / "pkg").mkdir()
    (repo / "pkg" / "m.py").write_text("y = 1\n")
    t1, manifest = _manifest(orc)
    lines = orc._review_dirty_snapshot(str(repo), t1, manifest).splitlines()
    assert any(line.endswith("a.py") for line in lines)
    assert any(line.endswith("c.py") for line in lines)
    assert not any("b.py" in line for line in lines)
    assert not any("pkg" in line for line in lines)


def test_a_sibling_commit_during_the_review_leaves_the_snapshot_unchanged(orc, tmp_path):
    repo = _repo(tmp_path)
    (repo / "a.py").write_text("x = 1\n")
    (repo / "b.py").write_text("y = 1\n")
    _git(repo, "add", "-A")
    _git(repo, "commit", "-q", "-m", "init")
    t1, manifest = _manifest(orc)
    (repo / "b.py").write_text("y = 2\n")
    before = orc._review_dirty_snapshot(str(repo), t1, manifest)
    _git(repo, "commit", "-q", "-am", "sibling commit")
    after = orc._review_dirty_snapshot(str(repo), t1, manifest)
    assert before == after == ""


def test_the_reviewed_task_s_own_edits_still_show(orc, tmp_path):
    repo = _repo(tmp_path)
    (repo / "a.py").write_text("x = 1\n")
    _git(repo, "add", "-A")
    _git(repo, "commit", "-q", "-m", "init")
    t1, manifest = _manifest(orc)
    (repo / "a.py").write_text("x = 2\n")
    assert orc._review_dirty_snapshot(str(repo), t1, manifest).endswith("a.py")
```

### Verify Task 1

```bash
python3 -m py_compile scripts/orchestrate.py
grep -c '_review_dirty_snapshot(project_dir, task, manifest)' scripts/orchestrate.py
cd tests && uv run pytest structural/test_orchestrate_review_dirty_scope.py structural/test_orchestrate_review.py -q
```

Expected: exit 0

## Commit

Message file: written by the orchestrator. Pathspec: `scripts/orchestrate.py tests/structural/test_orchestrate_review_dirty_scope.py`.
