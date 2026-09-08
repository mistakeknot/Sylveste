from __future__ import annotations

import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from scripts import check_beads_jsonl_dolt_sync as check


def write_jsonl(path: Path, rows: list[dict[str, object]]) -> None:
    path.write_text("".join(json.dumps(row, sort_keys=True) + "\n" for row in rows), encoding="utf-8")


def test_diff_issue_ids_reports_jsonl_ids_missing_from_dolt() -> None:
    diff = check.diff_issue_ids(
        jsonl_ids={"sylveste-s3z6.19.1", "sylveste-s3z6.19.2", "Sylveste-jm4"},
        dolt_ids={"sylveste-s3z6.19.1", "Sylveste-jm4"},
    )

    assert diff.missing_in_dolt == ["sylveste-s3z6.19.2"]
    assert diff.extra_in_dolt == []
    assert diff.ok is False


def test_load_jsonl_issue_ids_accepts_exported_memory_records(tmp_path: Path) -> None:
    issues_jsonl = tmp_path / "issues.jsonl"
    write_jsonl(
        issues_jsonl,
        [
            {"id": "sylveste-o2fr", "title": "gate"},
            {"_type": "memory", "key": "routing-note", "value": "Prefer live evidence."},
        ],
    )

    assert check.load_jsonl_issue_ids(issues_jsonl) == {"sylveste-o2fr"}


def test_load_jsonl_issue_ids_rejects_malformed_memory_records(tmp_path: Path) -> None:
    issues_jsonl = tmp_path / "issues.jsonl"
    write_jsonl(issues_jsonl, [{"_type": "memory", "key": "routing-note"}])

    try:
        check.load_jsonl_issue_ids(issues_jsonl)
    except ValueError as exc:
        assert "invalid memory record" in str(exc)
    else:  # pragma: no cover - assertion guard
        raise AssertionError("malformed memory record was accepted")


def test_cli_fails_when_tracked_jsonl_contains_ids_absent_from_dolt(tmp_path: Path, capsys) -> None:
    repo = tmp_path
    beads_dir = repo / ".beads"
    beads_dir.mkdir()
    write_jsonl(
        beads_dir / "issues.jsonl",
        [
            {"id": "sylveste-s3z6.19.1", "title": "present"},
            {"id": "sylveste-s3z6.19.2", "title": "jsonl only"},
            {"id": "Sylveste-jm4", "title": "present mixed case"},
        ],
    )
    fake_bd = tmp_path / "bd"
    fake_bd.write_text(
        "#!/usr/bin/env python3\n"
        "import sys\n"
        "assert sys.argv[1:3] == ['sql', 'select id from issues']\n"
        "print('id')\n"
        "print('---------------------')\n"
        "print('sylveste-s3z6.19.1')\n"
        "print('Sylveste-jm4')\n",
        encoding="utf-8",
    )
    fake_bd.chmod(0o755)
    old_path = os.environ.get("PATH", "")
    os.environ["PATH"] = f"{tmp_path}:{old_path}"
    try:
        exit_code = check.main(["--repo", str(repo)])
    finally:
        os.environ["PATH"] = old_path

    out = capsys.readouterr().out
    assert exit_code == 1
    assert "missing_in_dolt=1" in out
    assert "sylveste-s3z6.19.2" in out


def test_pre_commit_hook_checks_staged_issues_jsonl_blob() -> None:
    hook = (ROOT / ".beads" / "hooks" / "pre-commit").read_text(encoding="utf-8")

    assert "git show :'.beads/issues.jsonl'" in hook
    assert "--issues-jsonl \"$_beads_jsonl_staged\"" in hook
    # Record-level, both directions, with the committed blob as provenance. The
    # id-level --strict-extra probe this replaced could not see an edit to an
    # old task or a same-second conflict, and before that the guard ran for
    # weeks while the export sat 63 issues behind Dolt.
    assert "--records" in hook
    # The guarded export commits a file it just verified; the guard skips only
    # when the staged blob's hash is exactly the one the export vouched for.
    assert "BEADS_TRANSPORT_VERIFIED" in hook
    assert "_beads_staged_sha" in hook


def test_cli_passes_when_tracked_jsonl_and_dolt_issue_ids_match(tmp_path: Path, capsys) -> None:
    repo = tmp_path
    beads_dir = repo / ".beads"
    beads_dir.mkdir()
    write_jsonl(
        beads_dir / "issues.jsonl",
        [
            {"id": "sylveste-o2fr", "title": "gate"},
            {"id": "Sylveste-906", "title": "mixed case safety finding"},
        ],
    )
    fake_bd = tmp_path / "bd"
    fake_bd.write_text(
        "#!/usr/bin/env python3\n"
        "print('id')\n"
        "print('---------------------')\n"
        "print('sylveste-o2fr')\n"
        "print('Sylveste-906')\n",
        encoding="utf-8",
    )
    fake_bd.chmod(0o755)
    old_path = os.environ.get("PATH", "")
    os.environ["PATH"] = f"{tmp_path}:{old_path}"
    try:
        exit_code = check.main(["--repo", str(repo)])
    finally:
        os.environ["PATH"] = old_path

    out = capsys.readouterr().out
    assert exit_code == 0
    assert "beads_jsonl_dolt_sync ok" in out
    assert "jsonl_count=2" in out


# ─── content staleness (not just membership) ──────────────────────────


def test_normalize_strips_zone_before_touching_the_separator() -> None:
    """"UTC" contains a T.

    Normalizing the date/time separator first turns " +0000 UTC" into
    " +0000 U C", the suffix strip then misses, and every Dolt timestamp
    compares as older than every JSONL one — silently disabling the staleness
    detection this function exists to enable.
    """
    assert check.normalize_ts("2026-07-31T15:57:07Z") == check.normalize_ts(
        "2026-07-31 15:57:07 +0000 UTC"
    )
    assert check.normalize_ts("") == ""


# There was a test here asserting this module's normalize_ts agreed exactly
# with beads_safe_import.py's, because the two compared the same timestamps and
# a drift between them would move data the wrong way. That second implementation
# is gone — bd 1.1.2 enforces the staleness rule itself, in its own timestamp
# handling, so there is no longer a pair to keep in agreement. What replaced the
# coupling is tests/test_bd_import_guard.py, which tests bd's rule directly
# instead of testing our copy of it.


def test_jsonl_max_updated_ignores_memory_rows(tmp_path: Path) -> None:
    p = tmp_path / "issues.jsonl"
    write_jsonl(
        p,
        [
            {"id": "a", "updated_at": "2026-07-01T00:00:00Z"},
            {"_type": "memory", "key": "k", "value": "v"},
            {"id": "b", "updated_at": "2026-07-05T00:00:00Z"},
        ],
    )
    assert check.load_jsonl_max_updated(p) == "2026-07-05 00:00:00"


def test_a_close_is_detectable_even_though_the_id_set_is_unchanged(tmp_path: Path) -> None:
    """The gap that motivated the high-water mark.

    Closing a bead changes its status, not the id set — so a membership-only
    check reports "in sync" while the committed export still says `open`.
    Observed in production before this was added.
    """
    before = tmp_path / "before.jsonl"
    write_jsonl(before, [{"id": "a", "status": "open", "updated_at": "2026-07-01T00:00:00Z"}])

    ids_before = check.load_jsonl_issue_ids(before)
    ids_after = {"a"}  # the close does not change membership
    diff = check.diff_issue_ids(jsonl_ids=ids_before, dolt_ids=ids_after)
    assert not diff.missing_in_dolt and not diff.extra_in_dolt, "membership is identical"

    # Only the timestamp reveals it.
    assert check.normalize_ts("2026-07-02 00:00:00 +0000 UTC") > check.load_jsonl_max_updated(before)


# ─── record-level reconciliation (--records) ──────────────────────────
#
# The id+max(updated_at) probe above is partial by construction. These
# scenarios are the ones it cannot see, run against a stub bd whose `export`
# writes exactly the rows an environment variable names.

import subprocess


def row(issue_id: str, updated: str, **fields: object) -> dict[str, object]:
    base: dict[str, object] = {
        "_type": "issue", "id": issue_id, "title": f"title {issue_id}", "status": "open",
        "priority": 2, "updated_at": updated, "comment_count": 0,
    }
    base.update(fields)
    return base


def install_stub_bd(tmp_path: Path) -> Path:
    """`bd [-C dir] export -o PATH` copies $BD_STUB_EXPORT; `sql` lists its ids."""
    stub = tmp_path / "bin" / "bd"
    stub.parent.mkdir(exist_ok=True)
    stub.write_text(
        "#!/usr/bin/env python3\n"
        "import json, os, shutil, sys\n"
        "argv = sys.argv[1:]\n"
        "if argv[:1] == ['-C']:\n"
        "    argv = argv[2:]\n"
        "if os.environ.get('BD_STUB_EXPORT_FAIL'):\n"
        "    print('simulated: dolt server unreachable', file=sys.stderr); sys.exit(1)\n"
        "src = os.environ['BD_STUB_EXPORT']\n"
        "if argv[:1] == ['export']:\n"
        "    shutil.copyfile(src, argv[argv.index('-o') + 1])\n"
        "elif argv[:1] == ['sql']:\n"
        "    print('id'); print('----')\n"
        "    for line in open(src):\n"
        "        if line.strip(): print(json.loads(line)['id'])\n",
        encoding="utf-8",
    )
    stub.chmod(0o755)
    return stub


def run_records(tmp_path: Path, transport: list[dict], database: list[dict],
                baseline: list[dict] | None, *extra: str) -> tuple[int, dict]:
    repo = tmp_path / "repo"
    (repo / ".beads").mkdir(parents=True, exist_ok=True)
    write_jsonl(repo / ".beads" / "issues.jsonl", transport)
    write_jsonl(tmp_path / "database.jsonl", database)
    argv = ["--repo", str(repo), "--records", "--json", "--bd-command", str(install_stub_bd(tmp_path))]
    if baseline is not None:
        write_jsonl(tmp_path / "baseline.jsonl", baseline)
        argv += ["--baseline", str(tmp_path / "baseline.jsonl")]
    argv += list(extra)
    env = dict(os.environ, BD_STUB_EXPORT=str(tmp_path / "database.jsonl"))
    proc = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "check_beads_jsonl_dolt_sync.py"), *argv],
        text=True, capture_output=True, env=env, check=False,
    )
    assert proc.stdout.strip(), proc.stderr
    return proc.returncode, json.loads(proc.stdout.strip().splitlines()[-1])


def test_records_mode_sees_an_older_task_edit_the_high_water_mark_hides(tmp_path: Path) -> None:
    """Edit an old task while the file's max(updated_at) comes from elsewhere.

    ids mode: membership equal, dolt max == jsonl max -> "in sync". Wrong.
    """
    transport = [row("a", "2026-07-01T00:00:00Z"), row("b", "2026-08-01T00:00:00Z")]
    database = [row("a", "2026-07-15T00:00:00Z", title="a, edited here"), row("b", "2026-08-01T00:00:00Z")]
    rc, out = run_records(tmp_path, transport, database, baseline=transport)

    assert out["coverage"] == "complete"
    assert out["database_changed"] == ["a"]
    assert out["export_needed"] is True
    assert out["synchronized"] is True
    assert rc == 1


def test_equal_timestamp_different_content_is_a_conflict_not_a_choice(tmp_path: Path) -> None:
    base = [row("a", "2026-07-01T00:00:00Z")]
    transport = [row("a", "2026-07-02T00:00:00Z", title="renamed on zklw")]
    database = [row("a", "2026-07-02T00:00:00Z", title="renamed on the mac")]
    evidence = tmp_path / "evidence"
    merged = tmp_path / "merged.jsonl"
    rc, out = run_records(tmp_path, transport, database, base,
                          "--evidence-dir", str(evidence), "--write-merged", str(merged))

    assert [c["id"] for c in out["conflicts"]] == ["a"]
    assert out["conflicts"][0]["reason"] == "equal_updated_at_different_content"
    assert out["synchronized"] is False
    assert out["export_needed"] is False
    # The transport keeps its current version; nothing picked a winner.
    assert "renamed on zklw" in merged.read_text(encoding="utf-8")
    assert "renamed on the mac" not in merged.read_text(encoding="utf-8")
    # Both versions survive privately; the public report carries hashes only.
    evidence_dir = Path(out["evidence_path"])
    assert (evidence_dir / "a.transport.json").exists()
    assert (evidence_dir / "a.database.json").exists()
    assert (evidence_dir / "a.baseline.json").exists()
    assert "renamed on the mac" not in json.dumps(out)
    assert rc == 1


def test_without_a_baseline_every_difference_is_a_conflict(tmp_path: Path) -> None:
    transport = [row("a", "2026-07-01T00:00:00Z")]
    database = [row("a", "2026-07-05T00:00:00Z", title="newer here")]
    rc, out = run_records(tmp_path, transport, database, baseline=None)

    assert out["baseline_available"] is False
    assert out["database_changed"] == []
    assert [c["reason"] for c in out["conflicts"]] == ["no_baseline"]
    assert rc == 1


def test_both_changed_since_baseline_is_a_conflict_whatever_the_timestamps_say(tmp_path: Path) -> None:
    base = [row("a", "2026-07-01T00:00:00Z")]
    transport = [row("a", "2026-07-02T00:00:00Z", status="closed")]
    database = [row("a", "2026-07-09T00:00:00Z", title="retitled")]   # newer, but not a winner
    rc, out = run_records(tmp_path, transport, database, base)

    assert [c["reason"] for c in out["conflicts"]] == ["both_changed_since_baseline"]
    assert out["database_changed"] == []


def test_transport_side_rows_are_preserved_while_database_changes_still_apply(tmp_path: Path) -> None:
    """The accepted semantics: safe records apply even when others are pending."""
    base = [row("a", "2026-07-01T00:00:00Z"), row("b", "2026-07-01T00:00:00Z")]
    transport = [
        row("a", "2026-07-01T00:00:00Z"),
        row("b", "2026-07-03T00:00:00Z", status="closed"),      # pulled, not yet imported
        row("c", "2026-07-03T00:00:00Z"),                       # pulled, never imported
        {"_type": "memory", "key": "note", "value": "keep me"},
    ]
    database = [
        row("a", "2026-07-04T00:00:00Z", title="edited here"),  # one-sided local edit
        row("b", "2026-07-01T00:00:00Z"),
        row("d", "2026-07-04T00:00:00Z"),                       # created here
    ]
    merged = tmp_path / "merged.jsonl"
    rc, out = run_records(tmp_path, transport, database, base, "--write-merged", str(merged))

    assert out["database_changed"] == ["a"]
    assert out["transport_changed"] == ["b"]
    assert out["transport_only"] == ["c", "memory:note"]
    assert out["database_only"] == ["d"]
    assert out["missing_in_dolt"] == ["c"]           # legacy field still answers
    assert out["safe_to_export"] is True
    assert out["synchronized"] is False
    assert out["conflicts"] == []
    lines = [json.loads(l) for l in merged.read_text(encoding="utf-8").splitlines()]
    by_id = {l.get("id") or f"memory:{l.get('key')}": l for l in lines}
    assert by_id["a"]["title"] == "edited here"
    assert by_id["b"]["status"] == "closed"            # transport version kept
    assert "c" in by_id and "d" in by_id and "memory:note" in by_id
    assert [l.get("id") or "memory" for l in lines][:4] == ["a", "b", "c", "memory"], "transport order kept"
    assert out["merged"]["changes_transport"] is True


def test_derived_counts_are_presentation_not_edits(tmp_path: Path) -> None:
    transport = [row("a", "2026-07-01T00:00:00Z", comment_count=0, dependency_count=1)]
    database = [row("a", "2026-07-01T00:00:00Z", comment_count=2, dependency_count=0)]
    rc, out = run_records(tmp_path, transport, database, baseline=None)

    assert out["presentation_only"] == ["a"]
    assert out["conflicts"] == [] and out["database_changed"] == []
    assert out["status"] == "equal"
    assert rc == 0


def test_a_row_removed_from_the_transport_is_not_resurrected_by_export(tmp_path: Path) -> None:
    base = [row("a", "2026-07-01T00:00:00Z"), row("x", "2026-07-01T00:00:00Z")]
    transport = [row("a", "2026-07-01T00:00:00Z")]               # x removed upstream
    database = [row("a", "2026-07-01T00:00:00Z"), row("x", "2026-07-01T00:00:00Z")]
    merged = tmp_path / "merged.jsonl"
    rc, out = run_records(tmp_path, transport, database, base, "--write-merged", str(merged))

    assert out["transport_removed"] == ["x"]
    assert out["database_only"] == []
    assert '"x"' not in merged.read_text(encoding="utf-8")
    assert out["synchronized"] is False                 # still visible, not silent


def test_malformed_transport_is_invalid_coverage_never_complete(tmp_path: Path) -> None:
    transport = [row("a", "2026-07-01T00:00:00Z"), row("a", "2026-07-02T00:00:00Z"),
                 {"_type": "gadget", "id": "z"}]
    database = [row("a", "2026-07-01T00:00:00Z")]
    merged = tmp_path / "merged.jsonl"
    rc, out = run_records(tmp_path, transport, database, transport[:1], "--write-merged", str(merged))

    assert rc == 2
    assert out["coverage"] == "invalid"
    assert any("duplicate record a" in e for e in out["errors"])
    assert any("unsupported record type" in e for e in out["errors"])
    assert not merged.exists()


def test_a_failing_native_export_is_unavailable_not_in_sync(tmp_path: Path) -> None:
    transport = [row("a", "2026-07-01T00:00:00Z")]
    os.environ["BD_STUB_EXPORT_FAIL"] = "1"
    try:
        rc, out = run_records(tmp_path, transport, transport, transport)
    finally:
        del os.environ["BD_STUB_EXPORT_FAIL"]

    assert rc == 2
    assert out["coverage"] == "unavailable"
    assert "dolt server unreachable" in " ".join(out["errors"])


def test_confirmed_deletions_are_dropped_but_a_live_row_is_not(tmp_path: Path) -> None:
    base = [row("a", "2026-07-01T00:00:00Z"), row("gone", "2026-07-01T00:00:00Z"),
            row("still", "2026-07-01T00:00:00Z")]
    transport = base
    database = [row("a", "2026-07-01T00:00:00Z"), row("still", "2026-07-01T00:00:00Z")]
    merged = tmp_path / "merged.jsonl"
    rc, out = run_records(tmp_path, transport, database, base,
                          "--drop-id", "gone", "--drop-id", "still", "--write-merged", str(merged))

    assert out["dropped"] == ["gone"]
    assert [c["reason"] for c in out["conflicts"]] == ["drop_requested_but_present_in_database"]
    text = merged.read_text(encoding="utf-8")
    assert '"gone"' not in text and '"still"' in text


def test_verify_import_distinguishes_applied_kept_local_and_unapplied(tmp_path: Path) -> None:
    batch = [
        row("applied", "2026-07-02T00:00:00Z", title="new title"),
        row("kept", "2026-07-01T00:00:00Z", title="stale incoming"),
        row("lost", "2026-07-02T00:00:00Z"),
    ]
    database = [
        row("applied", "2026-07-02T00:00:00Z", title="new title", comment_count=3),
        row("kept", "2026-07-05T00:00:00Z", title="local, newer"),
    ]
    write_jsonl(tmp_path / "batch.jsonl", batch)
    rc, out = run_records(tmp_path, [], database, None, "--verify-import", str(tmp_path / "batch.jsonl"))

    assert out["applied"] == ["applied"]
    assert out["kept_local"] == ["kept"]
    assert out["unapplied"] == ["lost"]
    assert out["ok"] is False and rc == 1

    write_jsonl(tmp_path / "batch.jsonl", batch[:2])
    rc, out = run_records(tmp_path, [], database, None, "--verify-import", str(tmp_path / "batch.jsonl"))
    assert out["ok"] is True and rc == 0 and out["status"] == "verified"


def test_ids_mode_now_declares_its_coverage_partial(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    (repo / ".beads").mkdir(parents=True)
    write_jsonl(repo / ".beads" / "issues.jsonl", [row("a", "2026-07-01T00:00:00Z")])
    write_jsonl(tmp_path / "db.jsonl", [row("a", "2026-07-01T00:00:00Z")])
    stub = install_stub_bd(tmp_path)
    old = os.environ.get("BD_STUB_EXPORT")
    os.environ["BD_STUB_EXPORT"] = str(tmp_path / "db.jsonl")
    try:
        proc = subprocess.run(
            [sys.executable, str(ROOT / "scripts" / "check_beads_jsonl_dolt_sync.py"),
             "--repo", str(repo), "--json", "--bd-command", str(stub)],
            text=True, capture_output=True, check=False,
        )
    finally:
        if old is None:
            del os.environ["BD_STUB_EXPORT"]
        else:
            os.environ["BD_STUB_EXPORT"] = old
    out = json.loads(proc.stdout)
    assert out["mode"] == "ids" and out["coverage"] == "partial"
    assert out["safe_to_export"] is True and out["export_needed"] is False


# ─── persisted baseline: provenance survives a preserve-and-flag export ─


def test_conflict_survives_a_partial_export_when_the_baseline_is_persisted(tmp_path: Path) -> None:
    """Baseline A, transport C (pulled), database B (edited here).

    Pass 1 conflicts and keeps C in the transport. If pass 2 took the committed
    transport (now C) as provenance it would read B as one-sided and publish
    it. The persisted per-record baseline still says A, so it stays a conflict.
    """
    state = tmp_path / "state"
    state.mkdir()
    a = row("k", "2026-01-01T00:00:00Z")
    c = row("k", "2026-05-01T00:00:00Z", title="k per zklw")
    b = row("k", "2026-06-01T00:00:00Z", title="k per the mac")
    write_jsonl(tmp_path / "seed.jsonl", [a])
    proc = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "check_beads_jsonl_dolt_sync.py"),
         "--state-dir", str(state), "--seed-baseline", str(tmp_path / "seed.jsonl"), "--json"],
        text=True, capture_output=True, check=False,
    )
    assert json.loads(proc.stdout)["status"] == "seeded"

    proposal = tmp_path / "proposal.json"
    rc, out = run_records(tmp_path, [c], [b, row("new", "2026-06-02T00:00:00Z")], None,
                          "--state-dir", str(state), "--propose-state", str(proposal),
                          "--write-merged", str(tmp_path / "m1.jsonl"))
    assert [x["reason"] for x in out["conflicts"]] == ["both_changed_since_baseline"]
    assert out["database_only"] == ["new"]
    # The export is applied (the merged file is published): promote as applied.
    proc = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "check_beads_jsonl_dolt_sync.py"),
         "--state-dir", str(state), "--promote-state", str(proposal), "--applied", "--json"],
        text=True, capture_output=True, check=False,
    )
    assert json.loads(proc.stdout)["status"] == "promoted", proc.stdout
    baseline = json.load((state / "baseline.json").open())["records"]
    assert baseline["k"]["hash"] == check.semantic_hash(a), "a conflict must not move the baseline"
    assert "new" in baseline
    conflicts = json.load((state / "conflicts.json").open())["records"]
    assert "k" in conflicts

    # Pass 2: the committed transport is now C. Same verdict, same reason.
    rc, out = run_records(tmp_path, [c, row("new", "2026-06-02T00:00:00Z")],
                          [b, row("new", "2026-06-02T00:00:00Z")], None,
                          "--state-dir", str(state), "--propose-state", str(proposal),
                          "--write-merged", str(tmp_path / "m2.jsonl"))
    assert [x["reason"] for x in out["conflicts"]] == ["both_changed_since_baseline"]
    assert out["database_changed"] == []
    assert "k per the mac" not in (tmp_path / "m2.jsonl").read_text(encoding="utf-8")
    assert json.loads(proposal.read_text())["conflicts"]["records"]["k"]["first_seen"] == conflicts["k"]["first_seen"]


def test_plan_import_holds_back_rows_whose_local_copy_changed_since_verified(tmp_path: Path) -> None:
    """Newer incoming rows would overwrite an independent local edit; bd's
    strictly-newer guard cannot help there. Classification before bd can."""
    baseline_a = row("a", "2026-01-01T00:00:00Z")
    before = [baseline_a, row("b", "2026-01-01T00:00:00Z")]
    batch = [
        row("a", "2026-12-01T00:00:00Z", title="a per zklw"),   # local a changed too -> conflict
        row("b", "2026-12-01T00:00:00Z", title="b per zklw"),   # local b == before -> import
        row("c", "2026-12-01T00:00:00Z"),                       # absent locally -> import
        row("d", "2026-12-01T00:00:00Z"),                       # already equal -> nothing to do
    ]
    database = [
        row("a", "2026-11-01T00:00:00Z", title="a edited locally"),
        row("b", "2026-01-01T00:00:00Z"),
        row("d", "2026-12-01T00:00:00Z"),
    ]
    write_jsonl(tmp_path / "batch.jsonl", batch)
    write_jsonl(tmp_path / "before.jsonl", before)
    out_batch = tmp_path / "importable.jsonl"
    evidence = tmp_path / "evidence"
    # Without git provenance a differing existing row is never importable,
    # however the baseline reads; absent and equal rows still are.
    rc, out = run_records(tmp_path, [], database, None,
                          "--plan-import", str(tmp_path / "batch.jsonl"), "--before", str(tmp_path / "before.jsonl"),
                          "--write-batch", str(out_batch))
    assert out["importable"] == ["c"] and out["already_applied"] == ["d"]
    assert sorted(c["reason"] for c in out["conflicts"]) == ["no_git_provenance", "no_git_provenance"]

    rc, out = run_records(tmp_path, [], database, None,
                          "--plan-import", str(tmp_path / "batch.jsonl"), "--before", str(tmp_path / "before.jsonl"),
                          "--git-provenance", "--write-batch", str(out_batch), "--evidence-dir", str(evidence))

    assert rc == 0 and out["status"] == "planned"
    assert out["importable"] == ["b", "c"]
    assert out["already_applied"] == ["d"]
    assert [c["id"] for c in out["conflicts"]] == ["a"]
    assert out["conflicts"][0]["reason"] == "local_changed_since_verified"
    ids = [json.loads(l)["id"] for l in out_batch.read_text(encoding="utf-8").splitlines()]
    assert ids == ["b", "c"], "the conflicted row must never reach bd import"
    ev = Path(out["evidence_path"])
    assert "a per zklw" in (ev / "a.incoming.json").read_text(encoding="utf-8")
    assert "a edited locally" in (ev / "a.database.json").read_text(encoding="utf-8")
    assert "a edited locally" not in json.dumps(out)


def test_native_guard_kept_local_is_recorded_as_a_conflict_after_verification(tmp_path: Path) -> None:
    state = tmp_path / "state"
    state.mkdir()
    batch = [row("k", "2026-01-01T00:00:00Z", title="older incoming")]
    database = [row("k", "2026-02-01T00:00:00Z", title="local, newer")]
    write_jsonl(tmp_path / "batch.jsonl", batch)
    proposal = tmp_path / "proposal.json"
    rc, out = run_records(tmp_path, [], database, None,
                          "--state-dir", str(state), "--verify-import", str(tmp_path / "batch.jsonl"),
                          "--propose-state", str(proposal))
    assert out["kept_local"] == ["k"] and out["ok"] is True
    conflicts = json.loads(proposal.read_text())["conflicts"]["records"]
    assert conflicts["k"]["reason"] == "native_guard_kept_local"
    assert "k" not in json.loads(proposal.read_text())["baseline_if_applied"]


def test_plan_import_flags_a_record_changed_on_both_sides_of_a_merge(tmp_path: Path) -> None:
    """Git provenance: local == before == baseline (the edit was exported), the
    incoming row is newer — yet both sides changed it since the merge base."""
    b0 = row("k", "2026-01-01T00:00:00Z")
    ours = [row("k", "2026-02-01T00:00:00Z", title="ours")]
    theirs = [row("k", "2026-03-01T00:00:00Z", title="theirs"), row("u", "2026-03-01T00:00:00Z")]
    write_jsonl(tmp_path / "base.jsonl", [b0])
    write_jsonl(tmp_path / "ours.jsonl", ours)
    write_jsonl(tmp_path / "theirs.jsonl", theirs)
    write_jsonl(tmp_path / "batch.jsonl", theirs)           # the merge took incoming
    out_batch = tmp_path / "importable.jsonl"
    rc, out = run_records(tmp_path, [], ours, None,          # database == ours
                          "--plan-import", str(tmp_path / "batch.jsonl"), "--before", str(tmp_path / "ours.jsonl"),
                          "--merge-side", str(tmp_path / "base.jsonl"), str(tmp_path / "ours.jsonl"), str(tmp_path / "theirs.jsonl"),
                          "--write-batch", str(out_batch), "--evidence-dir", str(tmp_path / "ev"))
    assert [c["id"] for c in out["conflicts"]] == ["k"]
    assert out["conflicts"][0]["reason"] == "both_changed_since_merge_base"
    assert out["importable"] == ["u"]
    ev = Path(out["evidence_path"])
    for label in ("base", "ours", "theirs", "before", "database", "incoming"):
        assert (ev / f"k.{label}.json").exists(), f"evidence lacks the {label} version"
    assert "theirs" in (ev / "k.theirs.json").read_text(encoding="utf-8")
    assert "ours" in (ev / "k.ours.json").read_text(encoding="utf-8")
    # A merge that did not touch k (a dependency PR) adds no conflict.
    write_jsonl(tmp_path / "dep-base.jsonl", ours)
    write_jsonl(tmp_path / "dep-theirs.jsonl", ours)
    rc, out = run_records(tmp_path, [], ours, None,
                          "--plan-import", str(tmp_path / "batch.jsonl"), "--before", str(tmp_path / "ours.jsonl"),
                          "--merge-side", str(tmp_path / "dep-base.jsonl"), str(tmp_path / "ours.jsonl"), str(tmp_path / "dep-theirs.jsonl"),
                          "--write-batch", str(out_batch))
    assert out["conflicts"] == [] and out["importable"] == ["k", "u"]


# ─── a conflict recorded on import must survive the next export pass ────


def promote(state: Path, proposal: Path, applied: bool = False) -> dict:
    argv = [sys.executable, str(ROOT / "scripts" / "check_beads_jsonl_dolt_sync.py"),
            "--state-dir", str(state), "--promote-state", str(proposal), "--json"]
    if applied:
        argv.append("--applied")
    proc = subprocess.run(argv, text=True, capture_output=True, check=False)
    return json.loads(proc.stdout)


def test_import_side_conflict_survives_the_next_export_pass(tmp_path: Path) -> None:
    """The exact sequence the reviewer's probe reproduced:

    1. Local edits k and exports it (baseline moves to the edited content).
    2. A peer independently edits k (later timestamp) and adds unrelated u;
       the merge takes the peer's side. `--plan-import` correctly holds k as
       `both_changed_since_merge_base` and imports u.
    3. The next ordinary export pass must NOT silently reclassify k as an
       ordinary one-sided `transport_changed` (pending import) just because
       the database still equals the (unmoved) baseline — that shape is
       indistinguishable, by baseline hashes alone, from the conflict the
       importer already rejected. u, genuinely one-sided and now applied,
       must still travel with no global stop.
    4. Only real agreement (transport and database actually matching) clears
       the conflict.
    """
    state = tmp_path / "state"
    state.mkdir()
    orig = row("k", "2026-01-01T00:00:00Z", title="orig")
    write_jsonl(tmp_path / "seed.jsonl", [orig])
    proc = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "check_beads_jsonl_dolt_sync.py"),
         "--state-dir", str(state), "--seed-baseline", str(tmp_path / "seed.jsonl"), "--json"],
        text=True, capture_output=True, check=False,
    )
    assert json.loads(proc.stdout)["status"] == "seeded"

    # 1. Local edit, exported: baseline moves to agree with the new content.
    edited_here = row("k", "2027-01-01T00:00:00Z", title="edited here")
    proposal1 = tmp_path / "proposal1.json"
    rc, out = run_records(tmp_path, [orig], [edited_here], None,
                          "--state-dir", str(state), "--propose-state", str(proposal1),
                          "--write-merged", str(tmp_path / "m1.jsonl"))
    assert out["database_changed"] == ["k"] and out["conflicts"] == []
    assert promote(state, proposal1, applied=True)["status"] == "promoted"
    baseline = json.load((state / "baseline.json").open())["records"]
    assert baseline["k"]["hash"] == check.semantic_hash(edited_here)

    # 2. Peer concurrently edits k (newer) and adds u; the merge takes theirs.
    edited_peer = row("k", "2027-02-01T00:00:00Z", title="edited on the peer")
    unrelated = row("u", "2027-02-01T00:00:00Z")
    write_jsonl(tmp_path / "base.jsonl", [orig])
    write_jsonl(tmp_path / "ours.jsonl", [edited_here])
    write_jsonl(tmp_path / "theirs.jsonl", [edited_peer, unrelated])
    proposal2 = tmp_path / "proposal2.json"
    rc, out = run_records(tmp_path, [], [edited_here], None,
                          "--state-dir", str(state),
                          "--plan-import", str(tmp_path / "theirs.jsonl"), "--before", str(tmp_path / "ours.jsonl"),
                          "--merge-side", str(tmp_path / "base.jsonl"), str(tmp_path / "ours.jsonl"), str(tmp_path / "theirs.jsonl"),
                          "--propose-state", str(proposal2), "--write-batch", str(tmp_path / "importable.jsonl"))
    assert [c["id"] for c in out["conflicts"]] == ["k"]
    assert out["conflicts"][0]["reason"] == "both_changed_since_merge_base"
    assert out["importable"] == ["u"]
    # Not applied: k was held, nothing importable landed in this proposal yet.
    assert promote(state, proposal2, applied=False)["status"] == "promoted"
    conflicts = json.load((state / "conflicts.json").open())["records"]
    assert "k" in conflicts and conflicts["k"]["reason"] == "both_changed_since_merge_base"
    baseline = json.load((state / "baseline.json").open())["records"]
    assert baseline["k"]["hash"] == check.semantic_hash(edited_here), "a held conflict must not move the baseline"

    # 3. The merge lands on the transport; u gets imported, k does not.
    # An ordinary commit fires the next export pass.
    merged_transport = [edited_peer, unrelated]
    database_after_import = [edited_here, unrelated]
    proposal3 = tmp_path / "proposal3.json"
    rc, out = run_records(tmp_path, merged_transport, database_after_import, None,
                          "--state-dir", str(state), "--propose-state", str(proposal3),
                          "--write-merged", str(tmp_path / "m3.jsonl"))
    assert [c["id"] for c in out["conflicts"]] == ["k"], "the conflict must not disappear"
    assert out["conflicts"][0]["reason"] == "unresolved_prior_conflict"
    assert out["transport_changed"] == [], "not a fresh one-sided change"
    assert out["synchronized"] is False
    assert out["incomplete_reasons"] == ["1 conflicting record(s)"]
    merged_text = (tmp_path / "m3.jsonl").read_text(encoding="utf-8")
    assert "edited on the peer" in merged_text, "k keeps its transport version"
    assert '"id": "u"' in merged_text, "unrelated safe row still travels"
    assert promote(state, proposal3, applied=False)["status"] == "promoted"
    conflicts = json.load((state / "conflicts.json").open())["records"]
    assert "k" in conflicts, "the unresolved conflict must survive the export pass"

    # setup-check-style tallies must stay truthful while it remains.
    assert len(conflicts) == 1

    # A retry-style query (open_conflicts, mirrored here) still names it.
    assert sorted(conflicts) == ["k"]

    # 4. Only a demonstrated resolution — the two sides actually agreeing —
    # clears it.
    resolved = row("k", "2027-03-01T00:00:00Z", title="edited on the peer")
    proposal4 = tmp_path / "proposal4.json"
    rc, out = run_records(tmp_path, [resolved, unrelated], [resolved, unrelated], None,
                          "--state-dir", str(state), "--propose-state", str(proposal4),
                          "--write-merged", str(tmp_path / "m4.jsonl"))
    assert out["conflicts"] == []
    assert promote(state, proposal4, applied=False)["status"] == "promoted"
    conflicts = json.load((state / "conflicts.json").open())["records"]
    assert "k" not in conflicts


def test_corrupt_conflicts_state_fails_closed_instead_of_silently_erasing_it(tmp_path: Path) -> None:
    """conflicts.json is what protects an unresolved conflict from being
    reclassified as safe on a later pass. `load_state`'s normal
    unreadable-or-malformed -> empty behavior is right for baseline.json (an
    empty baseline just makes every difference a `no_baseline` conflict,
    which is conservative); applied to conflicts.json it would do the
    opposite — silently discard every conflict on record. This must fail
    the pass instead, and touch nothing on disk."""
    state = tmp_path / "state"
    state.mkdir()
    (state / "conflicts.json").write_text("{not valid json", encoding="utf-8")
    original = (state / "conflicts.json").read_text(encoding="utf-8")

    rc, out = run_records(tmp_path, [row("a", "2026-07-01T00:00:00Z")],
                          [row("a", "2026-07-01T00:00:00Z")], None,
                          "--state-dir", str(state))

    assert rc == 2
    assert out["coverage"] == "invalid"
    assert any("conflicts.json" in e for e in out["errors"])
    assert (state / "conflicts.json").read_text(encoding="utf-8") == original
    assert not (state / "baseline.json").exists()

    (state / "conflicts.json").write_text(json.dumps(["not", "an", "object"]), encoding="utf-8")
    rc, out = run_records(tmp_path, [row("a", "2026-07-01T00:00:00Z")],
                          [row("a", "2026-07-01T00:00:00Z")], None,
                          "--state-dir", str(state))
    assert rc == 2 and out["coverage"] == "invalid"


# ─── a known conflict must not clear when one side goes missing entirely,
#     nor be silently re-admitted by a later, unrelated fast-forward ──────


def _establish_known_conflict(tmp_path: Path) -> tuple[Path, dict, dict]:
    """k held as `both_changed_since_merge_base`, exactly as production would
    leave it: baseline moved to the locally-exported content, database still
    equals that baseline (the conflict was never applied), conflicts.json
    names k, and evidence for it is on disk. Returns (state_dir, edited_here,
    edited_peer)."""
    state = tmp_path / "state"
    state.mkdir()
    orig = row("k", "2026-01-01T00:00:00Z", title="orig")
    write_jsonl(tmp_path / "seed.jsonl", [orig])
    proc = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "check_beads_jsonl_dolt_sync.py"),
         "--state-dir", str(state), "--seed-baseline", str(tmp_path / "seed.jsonl"), "--json"],
        text=True, capture_output=True, check=False,
    )
    assert json.loads(proc.stdout)["status"] == "seeded"

    edited_here = row("k", "2027-01-01T00:00:00Z", title="edited here")
    proposal1 = tmp_path / "proposal1.json"
    rc, out = run_records(tmp_path, [orig], [edited_here], None,
                          "--state-dir", str(state), "--propose-state", str(proposal1),
                          "--write-merged", str(tmp_path / "m1.jsonl"))
    assert out["database_changed"] == ["k"]
    assert promote(state, proposal1, applied=True)["status"] == "promoted"

    edited_peer = row("k", "2027-02-01T00:00:00Z", title="edited on the peer")
    write_jsonl(tmp_path / "base.jsonl", [orig])
    write_jsonl(tmp_path / "ours.jsonl", [edited_here])
    write_jsonl(tmp_path / "theirs.jsonl", [edited_peer])
    proposal2 = tmp_path / "proposal2.json"
    rc, out = run_records(tmp_path, [], [edited_here], None,
                          "--state-dir", str(state),
                          "--plan-import", str(tmp_path / "theirs.jsonl"), "--before", str(tmp_path / "ours.jsonl"),
                          "--merge-side", str(tmp_path / "base.jsonl"), str(tmp_path / "ours.jsonl"), str(tmp_path / "theirs.jsonl"),
                          "--propose-state", str(proposal2), "--write-batch", str(tmp_path / "importable.jsonl"),
                          "--evidence-dir", str(state / "evidence"))
    assert [c["id"] for c in out["conflicts"]] == ["k"]
    assert out["conflicts"][0]["reason"] == "both_changed_since_merge_base"
    assert promote(state, proposal2, applied=False)["status"] == "promoted"
    conflicts = json.load((state / "conflicts.json").open())["records"]
    assert "k" in conflicts and conflicts["k"]["evidence"]
    return state, edited_here, edited_peer


def test_known_conflict_does_not_clear_when_transport_side_goes_missing(tmp_path: Path) -> None:
    """A known conflict can only be cleared by the two sides actually
    agreeing; one side vanishing entirely cannot do that, so it must not
    fall into `transport_removed` (an ordinary, safe "not re-added" case)
    just because the database still equals the (unmoved) baseline."""
    state, edited_here, _edited_peer = _establish_known_conflict(tmp_path)
    conflicts_before = json.load((state / "conflicts.json").open())["records"]
    evidence_before = conflicts_before["k"]["evidence"]

    proposal3 = tmp_path / "proposal3.json"
    rc, out = run_records(tmp_path, [], [edited_here], None,   # k absent from the transport entirely
                          "--state-dir", str(state), "--propose-state", str(proposal3),
                          "--write-merged", str(tmp_path / "m3.jsonl"))

    assert [c["id"] for c in out["conflicts"]] == ["k"]
    assert out["conflicts"][0]["reason"] == "unresolved_prior_conflict"
    assert out["transport_removed"] == []
    assert promote(state, proposal3, applied=False)["status"] == "promoted"
    conflicts_after = json.load((state / "conflicts.json").open())["records"]
    assert "k" in conflicts_after, "the conflict must not clear just because the transport row disappeared"
    # Evidence history is not orphaned: first_seen and the evidence pointer survive.
    assert conflicts_after["k"]["first_seen"] == conflicts_before["k"]["first_seen"]
    assert Path(evidence_before).exists(), "prior evidence must still be on disk"


def test_known_conflict_is_not_readmitted_by_a_later_unrelated_fast_forward_import(tmp_path: Path) -> None:
    """The merge that produced the conflict can be behind `before` by the time
    a later, unrelated range is imported — a plain fast-forward with no merge
    in it at all. Local-state provenance alone (local == baseline, true
    precisely because a held conflict never moves the baseline) must not
    re-admit a row a known conflict already rejected."""
    state, edited_here, edited_peer = _establish_known_conflict(tmp_path)

    # A later commit range that never merged anything (kind=ff): k's row is
    # unchanged in the transport (still the peer's rejected content) but this
    # pass has no merge-side evidence to re-derive the conflict on its own.
    write_jsonl(tmp_path / "ff-batch.jsonl", [edited_peer])
    proposal_ff = tmp_path / "proposal-ff.json"
    rc, out = run_records(tmp_path, [], [edited_here], None,
                          "--state-dir", str(state),
                          "--plan-import", str(tmp_path / "ff-batch.jsonl"), "--before", str(tmp_path / "ours.jsonl"),
                          "--git-provenance", "--propose-state", str(proposal_ff),
                          "--write-batch", str(tmp_path / "ff-importable.jsonl"))

    assert out["importable"] == [], "a known conflict must not be admitted by a later ff import"
    assert [c["id"] for c in out["conflicts"]] == ["k"]
    assert out["conflicts"][0]["reason"] == "unresolved_prior_conflict"
    assert (tmp_path / "ff-importable.jsonl").read_text(encoding="utf-8") == ""
    assert promote(state, proposal_ff, applied=False)["status"] == "promoted"
    conflicts_after = json.load((state / "conflicts.json").open())["records"]
    assert "k" in conflicts_after


def test_known_conflict_is_not_readmitted_because_its_native_side_vanished(tmp_path: Path) -> None:
    """`plan_import` admits a batch row whenever `local is None`, before it
    ever consults `known_conflicts` — a known conflict whose native row was
    since deleted (or never existed on this host) would otherwise be handed
    straight to bd. Absence is not the demonstrated agreement that resolves
    a conflict; there is no content here that could have agreed."""
    state, edited_here, edited_peer = _establish_known_conflict(tmp_path)

    write_jsonl(tmp_path / "ff-batch.jsonl", [edited_peer])
    proposal = tmp_path / "proposal-native-gone.json"
    # k has no native row at all this pass (deleted, or never existed here);
    # an unrelated row keeps the stub export non-empty.
    rc, out = run_records(tmp_path, [], [row("other", "2026-01-01T00:00:00Z")], None,
                          "--state-dir", str(state),
                          "--plan-import", str(tmp_path / "ff-batch.jsonl"), "--before", str(tmp_path / "ours.jsonl"),
                          "--git-provenance", "--propose-state", str(proposal),
                          "--write-batch", str(tmp_path / "native-gone-importable.jsonl"))

    assert out["importable"] == [], "absence of the native row must not admit a known conflict"
    assert [c["id"] for c in out["conflicts"]] == ["k"]
    assert out["conflicts"][0]["reason"] == "unresolved_prior_conflict"
    assert (tmp_path / "native-gone-importable.jsonl").read_text(encoding="utf-8") == ""
    assert promote(state, proposal, applied=False)["status"] == "promoted"
    conflicts_after = json.load((state / "conflicts.json").open())["records"]
    assert "k" in conflicts_after


def test_evidence_history_survives_from_import_through_export(tmp_path: Path) -> None:
    """An import-time conflict's evidence directory holds every merge-side
    version (base/ours/theirs) that a later export-only pass's own evidence
    write can never reproduce (export's sources are only transport/database/
    baseline). The single `evidence` pointer moving to the latest write must
    not orphan that earlier, richer reference — nor delete it from disk."""
    state, edited_here, edited_peer = _establish_known_conflict(tmp_path)
    conflicts = json.load((state / "conflicts.json").open())["records"]
    import_evidence = conflicts["k"]["evidence"]
    assert conflicts["k"]["evidence_history"] == [import_evidence]
    for label in ("base", "ours", "theirs"):
        assert (Path(import_evidence) / f"k.{label}.json").exists()

    # The next export pass re-detects the same still-open conflict and writes
    # its own, export-only evidence (no base/ours/theirs on that side).
    proposal3 = tmp_path / "proposal3.json"
    rc, out = run_records(tmp_path, [edited_peer], [edited_here], None,
                          "--state-dir", str(state), "--propose-state", str(proposal3),
                          "--write-merged", str(tmp_path / "m3.jsonl"),
                          "--evidence-dir", str(state / "evidence"))
    export_evidence = out["evidence_path"]
    assert export_evidence and export_evidence != import_evidence
    assert promote(state, proposal3, applied=False)["status"] == "promoted"

    conflicts_after = json.load((state / "conflicts.json").open())["records"]
    assert conflicts_after["k"]["evidence"] == export_evidence, "the latest pointer moves"
    history = conflicts_after["k"]["evidence_history"]
    assert history == [import_evidence, export_evidence], "the richer import-time evidence must not be orphaned"
    # Nothing on disk was removed by dropping out of the latest-pointer slot.
    for label in ("base", "ours", "theirs"):
        assert (Path(import_evidence) / f"k.{label}.json").exists()


# ─── v4: a known conflict absent from BOTH sides is not invisible ────────


def test_known_conflict_survives_when_both_sides_go_silent_but_drop_id_still_clears_it(tmp_path: Path) -> None:
    """`reconcile`'s key set used to come only from the transport and
    database record sets, so a known-conflicted key with no row on either
    side this pass was never visited at all: not classified, not carried
    into conflicts.json, and purged from baseline.json by the "gone from
    both sides" cleanup. Export would report `equal`/rc=0 with an empty
    conflicts.json while the conflict was still, in fact, unresolved.
    Absence is not `--drop-id`'s recorded deletion and not the `ht == hd`
    agreement that actually resolves a conflict — silence must not resolve
    it either way, but an explicit drop still can (existing contract)."""
    state, edited_here, edited_peer = _establish_known_conflict(tmp_path)
    conflicts_before = json.load((state / "conflicts.json").open())["records"]
    baseline_before = json.load((state / "baseline.json").open())["records"]
    assert "k" in conflicts_before and "k" in baseline_before

    # Both sides go silent on k this pass: gone from the transport (someone
    # truncated the file) and gone from the database (someone deleted the
    # native row) — an unrelated safe row is the only thing either side has.
    unrelated = row("other", "2026-06-01T00:00:00Z")
    proposal = tmp_path / "proposal-both-absent.json"
    rc, out = run_records(tmp_path, [unrelated], [unrelated], None,
                          "--state-dir", str(state), "--propose-state", str(proposal),
                          "--write-merged", str(tmp_path / "m-both-absent.jsonl"))

    assert [c["id"] for c in out["conflicts"]] == ["k"], "silence on both sides must not clear the conflict"
    assert out["conflicts"][0]["reason"] == "unresolved_prior_conflict"
    assert out["synchronized"] is False
    assert out["status"] == "drift" and rc == 1
    merged_text = (tmp_path / "m-both-absent.jsonl").read_text(encoding="utf-8")
    assert '"id": "other"' in merged_text, "the unrelated safe row is unaffected"

    assert promote(state, proposal, applied=True)["status"] == "promoted"
    conflicts_after = json.load((state / "conflicts.json").open())["records"]
    assert "k" in conflicts_after, "the conflict must survive an export pass where both sides are silent"
    baseline_after = json.load((state / "baseline.json").open())["records"]
    assert baseline_after.get("k", {}).get("hash") == baseline_before["k"]["hash"], \
        "baseline provenance for an open conflict must not be purged just because both sides went quiet"

    # Now an explicit, recorded deletion — the existing authorized way to
    # clear it — does clear it.
    proposal_drop = tmp_path / "proposal-drop.json"
    rc, out = run_records(tmp_path, [unrelated], [unrelated], None,
                          "--state-dir", str(state), "--propose-state", str(proposal_drop),
                          "--write-merged", str(tmp_path / "m-drop.jsonl"), "--drop-id", "k")
    assert out["dropped"] == ["k"]
    assert out["conflicts"] == []
    assert promote(state, proposal_drop, applied=True)["status"] == "promoted"
    conflicts_final = json.load((state / "conflicts.json").open())["records"]
    baseline_final = json.load((state / "baseline.json").open())["records"]
    assert "k" not in conflicts_final
    assert "k" not in baseline_final


def test_load_conflicts_state_rejects_malformed_nested_entries(tmp_path: Path) -> None:
    """A shallow `isinstance(records, dict)` check accepts a string
    `evidence_history` (Python iterates a string into "characters that are
    all strings," which passes a naive per-item `isinstance(..., str)`
    check) and an integer `evidence`, silently carrying both forward into
    every future proposal. Each must be caught and the pass failed instead
    — but an old entry that simply lacks `evidence_history` is still valid."""
    state = tmp_path / "state"
    state.mkdir()

    bad_history = state / "bad-history.json"
    bad_history.write_text(json.dumps({
        "version": 1,
        "records": {"k": {"reason": "x", "evidence": "/e/1", "evidence_history": "/e/1"}},
    }), encoding="utf-8")
    try:
        check.load_conflicts_state(bad_history)
        raise AssertionError("a string evidence_history must be rejected")
    except check.ConflictStateError as exc:
        assert "evidence_history" in str(exc)

    bad_evidence = state / "bad-evidence.json"
    bad_evidence.write_text(json.dumps({
        "version": 1,
        "records": {"k": {"reason": "x", "evidence": 42}},
    }), encoding="utf-8")
    try:
        check.load_conflicts_state(bad_evidence)
        raise AssertionError("a non-string evidence must be rejected")
    except check.ConflictStateError as exc:
        assert "evidence" in str(exc)

    # Backward compatible: a valid old entry with no evidence_history at all.
    old_shape = state / "old-shape.json"
    old_shape.write_text(json.dumps({
        "version": 1,
        "records": {"k": {"reason": "both_changed_since_baseline", "evidence": "/e/1",
                          "first_seen": "2026-01-01T00:00:00+00:00", "last_seen": "2026-01-01T00:00:00+00:00"}},
    }), encoding="utf-8")
    data = check.load_conflicts_state(old_shape)
    assert data["records"]["k"]["evidence"] == "/e/1"

    # And the CLI surfaces this the same way as the other conflict-state
    # corruption case: refused, coverage=invalid, nothing written.
    conflicts_path = state / "conflicts.json"
    conflicts_path.write_text(bad_evidence.read_text(encoding="utf-8"), encoding="utf-8")
    original = conflicts_path.read_text(encoding="utf-8")
    rc, out = run_records(tmp_path, [row("a", "2026-07-01T00:00:00Z")],
                          [row("a", "2026-07-01T00:00:00Z")], None,
                          "--state-dir", str(state))
    assert rc == 2 and out["coverage"] == "invalid"
    assert conflicts_path.read_text(encoding="utf-8") == original
