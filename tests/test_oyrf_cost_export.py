"""Behavioural coverage for ops/oyrf-cost-export/oyrf-cost-export.sh.

The one property that matters: an empty interstat result is never published.
The six-hourly GitHub Actions job this timer replaces published 225 such rows,
because it ran on a checkout that could not see interstat and the exporter's
fallback row is well-formed. Well-formed is not measured. These tests build a
throwaway remote with an oyrf-data branch and check what reaches it.
"""

import os
import shutil
import stat
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "ops" / "oyrf-cost-export" / "oyrf-cost-export.sh"
HEADER = (
    "captured_at,window_days,session_count,total_tokens,input_tokens,"
    "output_tokens,cache_read_tokens,cache_creation_tokens,"
    "total_cost_usd,cost_per_session_usd,source\n"
)
SEED_ROW = "2026-04-30T17:23:50Z,7,0,0,0,0,0,0,0.000000,0.000000,interstat-empty\n"


def _git(*args, cwd):
    return subprocess.run(
        ["git", "-c", "user.name=t", "-c", "user.email=t@t", *args],
        cwd=cwd, check=True, text=True, capture_output=True,
    ).stdout


@pytest.fixture
def estate(tmp_path):
    """A bare remote with main + oyrf-data, a clone with estimate-costs.sh, and a HOME."""
    remote = tmp_path / "remote.git"
    _git("init", "-q", "--bare", str(remote), cwd=tmp_path)

    seed = tmp_path / "seed"
    seed.mkdir()
    _git("init", "-q", "-b", "main", cwd=seed)
    shutil.copy(ROOT / "estimate-costs.sh", seed / "estimate-costs.sh")
    (seed / "estimate-costs.sh").chmod(0o755)
    _git("add", ".", cwd=seed)
    _git("commit", "-q", "-m", "main", cwd=seed)
    _git("checkout", "-q", "--orphan", "oyrf-data", cwd=seed)
    _git("rm", "-rfq", ".", cwd=seed)
    (seed / "data").mkdir()
    (seed / "data" / "cost-trajectory.csv").write_text(HEADER + SEED_ROW)
    _git("add", ".", cwd=seed)
    _git("commit", "-q", "-m", "seed", cwd=seed)
    _git("remote", "add", "origin", str(remote), cwd=seed)
    _git("push", "-q", "origin", "main", "oyrf-data", cwd=seed)

    repo = tmp_path / "Sylveste"
    _git("clone", "-q", "-b", "main", str(remote), str(repo), cwd=tmp_path)

    home = tmp_path / "home"
    home.mkdir()
    env = {
        **os.environ,
        "HOME": str(home),
        "XDG_STATE_HOME": str(home / "state"),
        "OYRF_REPO": str(repo),
    }
    env.pop("OYRF_COST_QUERY_OVERRIDE", None)
    return {"remote": remote, "repo": repo, "home": home, "env": env}


def _run(estate, **extra_env):
    return subprocess.run(
        ["bash", str(SCRIPT)],
        env={**estate["env"], **extra_env},
        text=True, capture_output=True, timeout=60,
    )


def _remote_csv(estate):
    return subprocess.run(
        ["git", "show", "oyrf-data:data/cost-trajectory.csv"],
        cwd=estate["remote"], check=True, text=True, capture_output=True,
    ).stdout


def _remote_commits(estate):
    return _git("rev-list", "--count", "oyrf-data", cwd=estate["remote"]).strip()


def _fake_cost_query(tmp_path, body):
    script = tmp_path / "fake-cost-query.sh"
    script.write_text("#!/usr/bin/env bash\n" + body + "\n")
    script.chmod(script.stat().st_mode | stat.S_IXUSR)
    return str(script)


def _receipt(estate):
    return (estate["home"] / "state" / "oyrf-cost-export" / "last-run").read_text()


def test_script_is_executable():
    assert os.access(SCRIPT, os.X_OK), "the service unit runs it directly"


def test_no_interstat_is_could_not_look_and_publishes_nothing(estate):
    result = _run(estate)
    assert result.returncode == 3, result.stderr
    assert "does not hold interstat" in result.stderr
    assert _remote_commits(estate) == "1"
    assert _remote_csv(estate) == HEADER + SEED_ROW
    assert "exit=3" in _receipt(estate)


def test_empty_interstat_result_is_not_published(estate, tmp_path):
    fake = _fake_cost_query(tmp_path, "echo '[]'")
    result = _run(estate, OYRF_COST_QUERY_OVERRIDE=fake)
    assert result.returncode == 3, result.stderr
    assert "source=interstat-empty" in result.stderr
    assert _remote_commits(estate) == "1"
    assert _remote_csv(estate) == HEADER + SEED_ROW
    # The append was undone in the worktree too, not just left unpushed.
    worktree_csv = estate["home"] / "state" / "oyrf-cost-export" / "oyrf-data" / "data" / "cost-trajectory.csv"
    assert worktree_csv.read_text() == HEADER + SEED_ROW


def test_measured_row_is_published(estate, tmp_path):
    fake = _fake_cost_query(
        tmp_path,
        'echo \'{"session_count": 3, "input_tokens": 100, "output_tokens": 50, '
        '"cache_read_tokens": 90000, "cache_creation_tokens": 7000, "total_usd": 1.5}\'',
    )
    result = _run(estate, OYRF_COST_QUERY_OVERRIDE=fake)
    assert result.returncode == 0, result.stderr + result.stdout
    assert _remote_commits(estate) == "2"
    rows = _remote_csv(estate).splitlines()
    assert rows[0] == HEADER.strip()
    assert len(rows) == 3
    last = rows[-1].split(",")
    assert last[-1] == "interstat"
    assert last[2] == "3"           # session_count
    assert last[3] == "150"         # total_tokens repaired from input+output
    assert last[6] == "90000"       # cache_read_tokens — the stream the baseline used to drop
    assert last[7] == "7000"        # cache_creation_tokens
    assert last[8] == "1.500000"    # total_cost_usd
    assert "exit=0 source=interstat" in _receipt(estate)


def test_second_measured_run_appends_not_replaces(estate, tmp_path):
    fake = _fake_cost_query(tmp_path, 'echo \'{"session_count": 1, "total_tokens": 10, "total_usd": 0.1}\'')
    assert _run(estate, OYRF_COST_QUERY_OVERRIDE=fake).returncode == 0
    assert _run(estate, OYRF_COST_QUERY_OVERRIDE=fake).returncode == 0
    assert _remote_commits(estate) == "3"
    assert len(_remote_csv(estate).splitlines()) == 4


def test_pause_file_exits_quietly(estate):
    (estate["home"] / ".claude-automations-paused").touch()
    result = _run(estate)
    assert result.returncode == 0
    assert result.stdout == "" and result.stderr == ""
    assert _remote_commits(estate) == "1"


def test_unpushed_sample_is_retried_not_discarded(estate, tmp_path):
    fake = _fake_cost_query(tmp_path, 'echo \'{"session_count": 2, "total_tokens": 20, "total_usd": 0.2}\'')
    # Make the first push fail by pointing the worktree's remote nowhere.
    assert _run(estate, OYRF_COST_QUERY_OVERRIDE=fake).returncode == 0
    worktree = estate["home"] / "state" / "oyrf-cost-export" / "oyrf-data"
    _git("remote", "set-url", "origin", str(tmp_path / "nowhere.git"), cwd=estate["repo"])
    result = _run(estate, OYRF_COST_QUERY_OVERRIDE=fake)
    assert result.returncode == 3, result.stderr
    assert "offline" in result.stderr
    # Restore the remote: the pending sample must go out on the next run.
    _git("remote", "set-url", "origin", str(estate["remote"]), cwd=estate["repo"])
    fetch_only = _fake_cost_query(tmp_path, "echo '[]'")
    result = _run(estate, OYRF_COST_QUERY_OVERRIDE=fetch_only)
    # This run measures nothing (exit 3) but must still have flushed the backlog.
    assert result.returncode == 3
    assert _remote_commits(estate) == "2"
    assert worktree.exists()
