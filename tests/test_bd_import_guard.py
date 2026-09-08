"""Guard the import direction of the beads JSONL <-> Dolt round trip.

The failure this prevents is silent and destructive: an import that upserts
every record reverts anything changed here since the incoming export was
written. A bead closed on this machine reopens, with no error and nothing in
the output to notice.

`scripts/beads_safe_import.py` used to enforce that, because `bd import` did
not. bd 1.1.2 does, so the script is gone and this file tests the property
where it now lives — in bd. That means these tests can fail on a bd upgrade
without a line of this repo changing, which is the point: the guarantee is
load-bearing and it is no longer ours.

Deliberately run against a real bd database rather than a stub. A stub would
assert what we believe bd does, which is exactly the belief under test — the
tombstone support this repo planned around turned out to have been removed
three releases earlier, and no amount of stubbing would have caught that.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

# Native prerequisites. By default a host without bd skips (these tests are
# not part of the mandatory CI generator checks). A REQUIRED native run —
# the acceptance receipt — sets BEADS_NATIVE_REQUIRED=1, and then a missing
# binary or a failing `bd init` is a FAILURE: an all-skipped run must never
# read as a pass. The plan: "skipped native tests are not acceptance evidence".
NATIVE_REQUIRED = os.environ.get("BEADS_NATIVE_REQUIRED") == "1"


def _native_unavailable(reason: str) -> None:
    if NATIVE_REQUIRED:
        pytest.fail(f"native bd verification REQUIRED but unavailable: {reason}")
    pytest.skip(reason)


@pytest.fixture(autouse=True)
def _require_bd():
    if shutil.which("bd") is None:
        _native_unavailable("bd not installed")


def test_required_native_runs_cannot_pass_by_skipping():
    """The mechanism itself, so a receipt can rely on it."""
    assert callable(_native_unavailable)
    if NATIVE_REQUIRED:
        assert shutil.which("bd") is not None


def bd(repo: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["bd", *args], cwd=repo, text=True, capture_output=True, check=False
    )


@pytest.fixture(scope="module")
def repo(tmp_path_factory) -> Path:
    """A throwaway bd database.

    Its own directory, never a copy of a real .beads — copying one carries
    metadata.json, which names a database, and the copy then writes to the
    original. That mistake once applied 30 schema migrations to production.
    """
    path = tmp_path_factory.mktemp("bdguard")
    subprocess.run(["git", "init", "-q", "."], cwd=path, check=True)
    result = bd(path, "init", "--prefix", "guardprobe")
    if result.returncode != 0:
        _native_unavailable(f"bd init failed: {result.stderr.strip()[:200]}")
    return path


@pytest.fixture
def closed_bead(repo: Path) -> tuple[Path, str, dict]:
    """A bead that is CLOSED here — the local state a stale import would revert."""
    created = bd(repo, "create", "closed here", "-p", "3", "--json")
    issue_id = json.loads(created.stdout)["id"]
    bd(repo, "close", issue_id)
    exported = bd(repo, "export", "-o", "current.jsonl")
    assert exported.returncode == 0, exported.stderr
    rows = [
        json.loads(line)
        for line in (repo / "current.jsonl").read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    row = next(r for r in rows if r.get("id") == issue_id)
    assert row["status"] == "closed"
    return repo, issue_id, row


def status_of(repo: Path, issue_id: str) -> str:
    shown = bd(repo, "show", issue_id, "--json")
    assert shown.returncode == 0, shown.stderr
    payload = json.loads(shown.stdout[shown.stdout.find("[") :])
    return payload[0]["status"]


def reopened(row: dict, updated_at: str) -> dict:
    """The other machine's view: same bead, still open.

    closed_at has to go. bd rejects a non-closed issue carrying one, and the
    rejection aborts the whole file — which looks exactly like a stale row
    being skipped unless you read the error.
    """
    variant = dict(row, status="open", updated_at=updated_at)
    variant.pop("closed_at", None)
    return variant


def import_rows(repo: Path, name: str, rows: list[dict]) -> subprocess.CompletedProcess:
    path = repo / name
    path.write_text("\n".join(json.dumps(r) for r in rows) + "\n", encoding="utf-8")
    return bd(repo, "import", str(path))


def test_stale_incoming_does_not_reopen_a_locally_closed_bead(closed_bead):
    """The regression that motivated all of this."""
    repo, issue_id, row = closed_bead
    bd(repo, "update", issue_id, "--status", "closed")

    import_rows(repo, "stale.jsonl", [reopened(row, "2020-01-01T00:00:00Z")])

    assert status_of(repo, issue_id) == "closed"


def test_equal_timestamps_keep_the_local_row(closed_bead):
    """updated_at has second granularity, so a tie is two distinct writes.

    Neither side can claim to be later, and reverting on a coin flip is the
    hazard. bd resolves it toward local.
    """
    repo, issue_id, row = closed_bead
    bd(repo, "update", issue_id, "--status", "closed")

    import_rows(repo, "tie.jsonl", [reopened(row, row["updated_at"])])

    assert status_of(repo, issue_id) == "closed"


def test_genuinely_newer_incoming_is_applied(closed_bead):
    """Without this the two tests above are vacuous.

    An import that refuses everything passes them both while breaking the sync
    entirely — which is the whole point of the mechanism, not a side effect.
    """
    repo, issue_id, row = closed_bead
    bd(repo, "update", issue_id, "--status", "closed")

    result = import_rows(repo, "newer.jsonl", [reopened(row, "2099-01-01T00:00:00Z")])

    assert result.returncode == 0, result.stderr
    assert status_of(repo, issue_id) == "open"


def test_absent_issues_are_created(closed_bead):
    """The other half of non-vacuity: unseen beads must actually arrive."""
    repo, _, row = closed_bead
    fresh_id = "guardprobe-fromelsewhere"
    incoming = reopened(dict(row, id=fresh_id, title="from another machine"), "2026-06-01T00:00:00Z")

    result = import_rows(repo, "absent.jsonl", [incoming])

    assert result.returncode == 0, result.stderr
    assert status_of(repo, fresh_id) == "open"


# ─── native post-merge: it imports the JSONL itself, ahead of any classifier ─
#
# `bd hooks run post-merge` (the block bd installs in .beads/hooks/post-merge)
# imports .beads/issues.jsonl on its own, applying every strictly newer row.
# That would let a newer incoming row overwrite an independently modified
# local one before scripts/beads-import-merged.sh has classified anything.
# bd 1.1.2 (20e493e56) maps the dotted config key import.auto to the
# environment as BD_IMPORT_AUTO and returns from its auto-import when that is
# false. The tracked post-merge hook sets it for its own invocation, before
# bd's block. These tests hold bd to that: the first proves the native import
# is real (so the second is not vacuous), the second proves the invocation-
# local override silences it, the third runs the ACTUAL tracked hook with the
# helpers in place and a newer stray file at transport-disabled.jsonl, and the
# fourth pins the hook's ordering.


def _post_merge_fixture(tmp_path_factory, name: str) -> tuple[Path, str]:
    path = tmp_path_factory.mktemp(name)
    subprocess.run(["git", "init", "-q", "."], cwd=path, check=True)
    subprocess.run(["git", "config", "user.email", "t@t"], cwd=path, check=True)
    subprocess.run(["git", "config", "user.name", "t"], cwd=path, check=True)
    subprocess.run(["git", "config", "core.hooksPath", "/dev/null"], cwd=path, check=True)
    result = bd(path, "init", "--prefix", "pmprobe")
    if result.returncode != 0:
        _native_unavailable(f"bd init failed: {result.stderr.strip()[:200]}")
    created = bd(path, "create", "local row", "-p", "3", "--json")
    issue_id = json.loads(created.stdout)["id"]
    exported = bd(path, "export", "-o", str(path / ".beads" / "issues.jsonl"))
    assert exported.returncode == 0, exported.stderr
    return path, issue_id


def _commit_newer_incoming(repo: Path, issue_id: str, title: str) -> None:
    jsonl = repo / ".beads" / "issues.jsonl"
    rows = [json.loads(l) for l in jsonl.read_text(encoding="utf-8").splitlines() if l.strip()]
    for row in rows:
        if row["id"] == issue_id:
            row["title"] = title
            row["updated_at"] = "2099-06-01T00:00:00Z"
    jsonl.write_text("".join(json.dumps(r) + "\n" for r in rows), encoding="utf-8")
    subprocess.run(["git", "add", ".beads/issues.jsonl"], cwd=repo, check=True)
    subprocess.run(["git", "-c", "core.hooksPath=/dev/null", "commit", "-q", "-m", "incoming"], cwd=repo, check=True)


def _title_of(repo: Path, issue_id: str) -> str:
    shown = bd(repo, "show", issue_id, "--json")
    payload = json.loads(shown.stdout[shown.stdout.find("["):])
    return payload[0]["title"]


def _native_post_merge(repo: Path, **env: str) -> subprocess.CompletedProcess:
    return subprocess.run(["bd", "hooks", "run", "post-merge"], cwd=repo, text=True,
                          capture_output=True, env={**os.environ, "BD_GIT_HOOK": "1", **env}, check=False)


def test_native_post_merge_imports_the_jsonl_by_default(tmp_path_factory):
    repo, issue_id = _post_merge_fixture(tmp_path_factory, "pm-default")
    _commit_newer_incoming(repo, issue_id, "renamed by the other host")

    result = _native_post_merge(repo)

    assert result.returncode == 0, result.stderr
    assert _title_of(repo, issue_id) == "renamed by the other host", \
        "bd no longer imports on post-merge; the BD_IMPORT_AUTO override may be unnecessary — re-verify"


def test_bd_import_auto_false_silences_the_native_post_merge_import(tmp_path_factory):
    repo, issue_id = _post_merge_fixture(tmp_path_factory, "pm-override")
    _commit_newer_incoming(repo, issue_id, "renamed by the other host")

    result = _native_post_merge(repo, BD_IMPORT_AUTO="false")

    assert result.returncode == 0, result.stderr
    assert _title_of(repo, issue_id) == "local row", "the native post-merge import ran despite BD_IMPORT_AUTO=false"
    # Positive control in the same database: without the override it imports.
    assert _native_post_merge(repo).returncode == 0
    assert _title_of(repo, issue_id) == "renamed by the other host"


def test_the_tracked_post_merge_hook_preserves_an_independent_local_edit(tmp_path_factory):
    """The actual hook, with the helpers, against a real bd — the runtime case.

    The local row was edited here after the base commit; the pull brings a
    NEWER incoming version, and a stray, newer transport-disabled.jsonl sits
    in .beads/ (it used to be the mechanism; it must now be irrelevant). The
    classifier holds the incoming row back and the native import stays off.
    """
    repo, issue_id = _post_merge_fixture(tmp_path_factory, "pm-hook")
    subprocess.run(["git", "add", "-A"], cwd=repo, check=True)
    subprocess.run(["git", "-c", "core.hooksPath=/dev/null", "commit", "-q", "-m", "base"], cwd=repo, check=True)
    before = subprocess.run(["git", "rev-parse", "HEAD"], cwd=repo, text=True, capture_output=True, check=True).stdout.strip()
    assert bd(repo, "update", issue_id, "--title", "independent local edit").returncode == 0
    _commit_newer_incoming(repo, issue_id, "incoming edit")
    subprocess.run(["git", "update-ref", "ORIG_HEAD", before], cwd=repo, check=True)
    root = Path(__file__).resolve().parents[1]
    shutil.copytree(root / "scripts", repo / "scripts")
    shutil.copy2(root / ".beads" / "hooks" / "post-merge", repo / ".beads" / "hooks" / "post-merge")
    (repo / ".beads" / "transport-disabled.jsonl").write_text(
        (repo / ".beads" / "issues.jsonl").read_text(encoding="utf-8"), encoding="utf-8")
    subprocess.run(["git", "config", "core.hooksPath", str(repo / ".beads" / "hooks")], cwd=repo, check=True)

    env = {**os.environ, "BEADS_ACTOR": "hook-fixture", "BEADS_TRANSPORT_LOCK_BASE": str(repo / "locks")}
    env.pop("BD_IMPORT_AUTO", None)
    result = subprocess.run(["sh", ".beads/hooks/post-merge", "0"], cwd=repo, text=True,
                            capture_output=True, env=env, timeout=180, check=False)

    assert result.returncode == 0, result.stderr
    assert _title_of(repo, issue_id) == "independent local edit", result.stderr
    assert "INCOMPLETE" in result.stderr, "the held-back conflict was not reported"
    assert "BD_IMPORT_AUTO" not in os.environ, "the override leaked into the caller's environment"
    assert "BD_IMPORT_AUTO" not in (repo / ".beads" / "config.yaml").read_text(encoding="utf-8")


def test_the_tracked_post_merge_hook_sets_the_override_before_bd_runs():
    hook = (Path(__file__).resolve().parents[1] / ".beads" / "hooks" / "post-merge").read_text(encoding="utf-8")
    override = hook.index("export BD_IMPORT_AUTO")
    native = hook.index("BEGIN BEADS INTEGRATION")
    assert "BD_IMPORT_AUTO=false" in hook
    assert override < native, "bd's block must come after the override or it imports unclassified"


# ─── the helper's SUCCESS path, against the real binary ───────────────
#
# Every shell suite stubs `bd import --json` with a one-line printer. Real bd
# pretty-prints its reply over many lines; a parser that took the first line
# (`{`) made every first-pass import that applied rows exit 1 with
# status_not_recorded while the rows were in fact in the database. These run
# scripts/beads-import-merged.sh end to end against real bd, in disposable
# repositories, through the exact merge shapes git produces.


def _helper_repo(tmp_path_factory, name: str) -> tuple[Path, str, dict]:
    """A repo with real bd, the helpers, and a committed base export."""
    repo, issue_id = _post_merge_fixture(tmp_path_factory, name)
    root = Path(__file__).resolve().parents[1]
    shutil.copytree(root / "scripts", repo / "scripts")
    subprocess.run(["git", "add", "-A"], cwd=repo, check=True)
    subprocess.run(["git", "-c", "core.hooksPath=/dev/null", "commit", "-q", "-m", "base"], cwd=repo, check=True)
    env = {**os.environ, "BEADS_ACTOR": "helper-fixture", "BEADS_TRANSPORT_LOCK_BASE": str(repo / "locks")}
    env.pop("BD_IMPORT_AUTO", None)
    return repo, issue_id, env


def _git(repo: Path, *args: str) -> str:
    return subprocess.run(["git", "-c", "core.hooksPath=/dev/null", *args], cwd=repo, text=True,
                          capture_output=True, check=True).stdout.strip()


def _rows(repo: Path) -> list[dict]:
    return [json.loads(l) for l in (repo / ".beads" / "issues.jsonl").read_text(encoding="utf-8").splitlines() if l.strip()]


def _write_rows(repo: Path, rows: list[dict]) -> None:
    (repo / ".beads" / "issues.jsonl").write_text("".join(json.dumps(r) + "\n" for r in rows), encoding="utf-8")


def _helper(repo: Path, env: dict, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["bash", "scripts/beads-import-merged.sh", *args], cwd=repo, text=True,
                          capture_output=True, env=env, timeout=300, check=False)


def _status_import(repo: Path) -> dict:
    return json.loads((repo / ".beads" / "transport" / "status.d" / "import.json").read_text(encoding="utf-8"))


def test_helper_first_pass_verifies_a_real_import(tmp_path_factory):
    """Finding 1: the first pass must complete, not need a --retry."""
    repo, _, env = _helper_repo(tmp_path_factory, "helper-success")
    base = _git(repo, "rev-parse", "HEAD")
    rows = _rows(repo)
    rows.append({"_type": "issue", "id": "pmprobe-new1", "title": "from the other host", "status": "open",
                 "priority": 2, "issue_type": "task", "created_at": "2026-09-07T00:00:00Z",
                 "updated_at": "2026-09-07T00:00:00Z"})
    _write_rows(repo, rows)
    _git(repo, "commit", "-q", "-m", "incoming", "--", ".beads/issues.jsonl")

    first = _helper(repo, env, base)

    assert first.returncode == 0, first.stderr
    assert _status_import(repo)["result"] == "verified", first.stderr
    assert _status_import(repo)["detail"]["bd"].get("created") == 1, _status_import(repo)
    assert not (repo / ".beads" / "transport" / "pending-import.json").exists()
    assert _title_of(repo, "pmprobe-new1") == "from the other host"
    # Idempotent: a retry with nothing pending is a clean no-op.
    again = _helper(repo, env, "--retry")
    assert again.returncode == 0 and "nothing pending" in again.stdout, again.stdout + again.stderr


def _divergent_merge(repo: Path, issue_id: str, env: dict) -> str:
    """Both hosts edit the same bead after the base; the merge takes incoming.

    Local: `bd update` then an export commit on main (the edit is EXPORTED,
    the ordinary case). Peer branch from base: the same bead edited with a
    later timestamp plus an unrelated new row. `git merge` conflicts on the
    line; the documented procedure takes the incoming side and commits by
    hand, so no hook runs and the helper is invoked explicitly with ORIG_HEAD.
    Returns the base commit.
    """
    base = _git(repo, "rev-parse", "HEAD")
    assert bd(repo, "update", issue_id, "--title", "edited on this host").returncode == 0
    exported = bd(repo, "export", "-o", str(repo / ".beads" / "issues.jsonl"))
    assert exported.returncode == 0, exported.stderr
    _git(repo, "commit", "-q", "-m", "local export", "--", ".beads/issues.jsonl")
    _git(repo, "checkout", "-q", "-b", "peer", base)
    rows = _rows(repo)
    for row in rows:
        if row["id"] == issue_id:
            row["title"] = "edited on the other host"
            row["updated_at"] = "2099-09-01T00:00:00Z"
    rows.append({"_type": "issue", "id": "pmprobe-unrelated", "title": "unrelated new row", "status": "open",
                 "priority": 2, "issue_type": "task", "created_at": "2026-09-07T00:00:00Z",
                 "updated_at": "2026-09-07T00:00:00Z"})
    _write_rows(repo, rows)
    _git(repo, "commit", "-q", "-m", "peer export", "--", ".beads/issues.jsonl")
    _git(repo, "checkout", "-q", "main")
    merge = subprocess.run(["git", "-c", "core.hooksPath=/dev/null", "merge", "--no-commit", "peer"], cwd=repo,
                           text=True, capture_output=True, check=False)
    assert merge.returncode != 0, "fixture: the merge was expected to conflict on the shared line"
    _git(repo, "checkout", "--theirs", "--", ".beads/issues.jsonl")
    _git(repo, "add", ".beads/issues.jsonl")
    _git(repo, "commit", "-q", "--no-edit")
    assert _git(repo, "rev-parse", "ORIG_HEAD") != _git(repo, "rev-parse", "HEAD")
    return base


def test_helper_keeps_both_versions_when_both_hosts_edited_after_export(tmp_path_factory):
    """Finding 2: an exported local edit must not lose to a newer incoming one."""
    repo, issue_id, env = _helper_repo(tmp_path_factory, "helper-divergent")
    _divergent_merge(repo, issue_id, env)

    first = _helper(repo, env, "ORIG_HEAD")

    assert first.returncode == 1, first.stdout + first.stderr
    assert _title_of(repo, issue_id) == "edited on this host", "the newer incoming version silently won"
    assert "changed on both hosts" in first.stderr and issue_id in first.stderr, first.stderr
    conflicts = json.loads((repo / ".beads" / "transport" / "conflicts.json").read_text(encoding="utf-8"))["records"]
    assert conflicts[issue_id]["reason"] == "both_changed_since_merge_base", conflicts
    evidence = Path(conflicts[issue_id]["evidence"])
    for label in ("incoming", "database", "before", "base", "theirs"):
        assert (evidence / f"{issue_id}.{label}.json").exists(), f"missing {label} version in evidence"
    assert "edited on the other host" in (evidence / f"{issue_id}.theirs.json").read_text(encoding="utf-8")
    assert "edited on this host" in (evidence / f"{issue_id}.database.json").read_text(encoding="utf-8")
    # The unrelated row from the other host still lands.
    assert _title_of(repo, "pmprobe-unrelated") == "unrelated new row"
    assert not (repo / ".beads" / "transport" / "pending-import.json").exists()
    # Retries, first and repeated, keep the conflict and choose nothing.
    for _ in range(2):
        again = _helper(repo, env, "--retry")
        assert again.returncode == 1 and issue_id in again.stderr, again.stderr
        assert _title_of(repo, issue_id) == "edited on this host"
    assert json.loads((repo / ".beads" / "transport" / "conflicts.json").read_text(encoding="utf-8"))["records"][issue_id]


def test_helper_applies_a_one_sided_change_on_a_fast_forward_pull(tmp_path_factory):
    repo, issue_id, env = _helper_repo(tmp_path_factory, "helper-ff")
    base = _git(repo, "rev-parse", "HEAD")
    _git(repo, "checkout", "-q", "-b", "peer", base)
    rows = _rows(repo)
    for row in rows:
        if row["id"] == issue_id:
            row["title"] = "edited on the other host only"
            row["updated_at"] = "2099-09-01T00:00:00Z"
    _write_rows(repo, rows)
    _git(repo, "commit", "-q", "-m", "peer export", "--", ".beads/issues.jsonl")
    _git(repo, "checkout", "-q", "main")
    _git(repo, "merge", "-q", "--ff-only", "peer")

    result = _helper(repo, env, "ORIG_HEAD")

    assert result.returncode == 0, result.stderr
    assert _title_of(repo, issue_id) == "edited on the other host only"
    assert _status_import(repo)["result"] == "verified"
    assert _status_import(repo)["detail"]["ancestry"]["kind"] == "ff"
