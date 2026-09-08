#!/usr/bin/env python3
"""Compare tracked Beads JSONL with the live Dolt database, and reconcile them.

Two modes share one file so the trigger and the guard can never disagree about
what "in sync" means.

`ids` mode (the default, unchanged contract): compares issue-ID membership plus
the global max(updated_at). ~0.3s. It is a *partial* check — an edit to an old
task whose timestamp is below the file's high-water mark, or two edits in the
same second, are invisible to it — and it says so in `coverage`.

`--records` mode: takes a private native export (`bd export` to a temp file),
parses both sides, and compares every record by ID on semantic content, not on
timestamps. It classifies each difference against a baseline (the last
transport state this host verified, normally the committed blob), so one-sided
changes apply and anything ambiguous is reported as a conflict rather than
resolved by picking a host or the newest timestamp. `--write-merged` writes the
transport file that a guarded export should publish: database-side changes
applied, transport-side rows preserved, conflicted IDs left at their current
transport version with both versions kept privately under `--evidence-dir`.

`--verify-import BATCH` checks, after `bd import`, that every row in BATCH is
either present with the same content or was kept back by bd's own per-record
guard (local row at least as new). That is the evidence an import succeeded;
`bd import` exiting 0 is not.

Exit codes: 0 in sync, 1 drift/incomplete, 2 invalid input or no coverage.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

# Fields bd derives from other tables at export time. Two databases holding the
# same issue can disagree on them without anyone having edited anything, and the
# two machines' snapshots do (2026-09-07: derived counts and metadata on shared
# rows). Treating them as edits would manufacture conflicts.
DEFAULT_IGNORED_FIELDS = ("comment_count", "dependency_count", "dependent_count", "_type")
TIMESTAMP_FIELDS = (
    "created_at", "updated_at", "closed_at", "started_at", "due_at", "defer_until", "deleted_at",
)
EXPORT_TIMEOUT_DEFAULT = 120


# ─── legacy id-level helpers (contract preserved) ─────────────────────


@dataclass(frozen=True)
class IssueIdDiff:
    jsonl_count: int
    dolt_count: int
    missing_in_dolt: list[str]
    extra_in_dolt: list[str]

    @property
    def ok(self) -> bool:
        return not self.missing_in_dolt


def load_jsonl_issue_ids(path: Path) -> set[str]:
    ids: set[str] = set()
    with path.open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError as exc:  # pragma: no cover - argparse-facing guard
                raise ValueError(f"{path}:{line_number}: invalid JSON: {exc}") from exc
            if row.get("_type") == "memory":
                memory_key = row.get("key")
                memory_value = row.get("value")
                if (
                    not isinstance(memory_key, str)
                    or not memory_key
                    or not isinstance(memory_value, str)
                ):
                    raise ValueError(f"{path}:{line_number}: invalid memory record")
                continue
            issue_id = row.get("id")
            if not isinstance(issue_id, str) or not issue_id:
                raise ValueError(f"{path}:{line_number}: missing string id")
            ids.add(issue_id)
    return ids


def normalize_ts(value: str) -> str:
    """Reduce Dolt's and the JSONL's timestamp renderings to one comparable form.

    Dolt prints `2026-07-31 15:57:07 +0000 UTC`; the JSONL carries
    `2026-07-31T15:57:07Z`.

    Strip the zone suffix BEFORE normalizing the date/time separator: "UTC"
    contains a T, so doing it the other way rewrites " +0000 UTC" into
    " +0000 U C" and the suffix stops matching — which makes every Dolt
    timestamp compare as older and hides exactly the staleness this detects.
    """
    if not value:
        return ""
    v = value.strip()
    for suffix in (" +0000 UTC", " UTC", "+00:00", "Z"):
        if v.endswith(suffix):
            v = v[: -len(suffix)]
            break
    return v.replace("T", " ").strip()


def load_jsonl_max_updated(path: Path) -> str:
    """Latest updated_at in the export (partial evidence; see module docstring)."""
    newest = ""
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            row = json.loads(line)
            if row.get("_type") == "memory":
                continue
            ts = normalize_ts(row.get("updated_at") or "")
            if ts > newest:
                newest = ts
    return newest


def resolve_bd(bd_command: str) -> str | None:
    return shutil.which(bd_command) if "/" not in bd_command else bd_command


def load_dolt_max_updated(repo: Path, bd_command: str = "bd") -> str:
    resolved = resolve_bd(bd_command)
    if resolved is None:
        return ""
    result = subprocess.run(
        [resolved, "sql", "select max(updated_at) from issues"],
        cwd=repo, text=True, capture_output=True, check=False,
    )
    if result.returncode != 0:
        return ""
    newest = ""
    for raw in result.stdout.splitlines():
        line = raw.strip()
        if not line or set(line) <= {"-", "+"} or line.startswith("("):
            continue
        if "max(" in line.lower():
            continue
        ts = normalize_ts(line.split("|")[0])
        if ts and ts[0].isdigit() and ts > newest:
            newest = ts
    return newest


def parse_bd_sql_issue_ids(output: str) -> set[str]:
    ids: set[str] = set()
    for raw_line in output.splitlines():
        line = raw_line.strip()
        if not line or line == "id" or set(line) <= {"-"}:
            continue
        if line.startswith("(") and line.endswith("rows)"):
            continue
        if line.startswith("|"):
            cells = [cell.strip() for cell in line.strip("|").split("|")]
            if not cells or cells[0] == "id":
                continue
            issue_id = cells[0]
        else:
            issue_id = line.split()[0]
        if issue_id:
            ids.add(issue_id)
    return ids


def load_dolt_issue_ids(repo: Path, bd_command: str = "bd") -> set[str]:
    resolved = resolve_bd(bd_command)
    if resolved is None:
        raise RuntimeError(f"bd command not found on PATH: {bd_command}")
    result = subprocess.run(
        [resolved, "sql", "select id from issues"],
        cwd=repo,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or "bd sql failed")
    return parse_bd_sql_issue_ids(result.stdout)


def diff_issue_ids(jsonl_ids: set[str], dolt_ids: set[str]) -> IssueIdDiff:
    return IssueIdDiff(
        jsonl_count=len(jsonl_ids),
        dolt_count=len(dolt_ids),
        missing_in_dolt=sorted(jsonl_ids - dolt_ids),
        extra_in_dolt=sorted(dolt_ids - jsonl_ids),
    )


# ─── record-level model ───────────────────────────────────────────────


@dataclass
class Record:
    key: str          # issue id, or "memory:<key>"
    kind: str         # "issue" | "memory"
    raw: str          # the line exactly as read, without its newline
    data: dict
    semantic: str     # sha256 of the canonical form
    updated_at: str   # normalized, "" when absent


@dataclass
class RecordSet:
    records: dict[str, Record] = field(default_factory=dict)
    errors: list[str] = field(default_factory=list)
    line_count: int = 0
    sha256: str = ""

    @property
    def ok(self) -> bool:
        return not self.errors

    @property
    def issue_ids(self) -> set[str]:
        return {r.key for r in self.records.values() if r.kind == "issue"}


def _empty(value) -> bool:
    return value is None or value == "" or value == [] or value == {}


def _prune(value, ignored: frozenset[str]):
    """Canonical value: derived/empty fields removed, timestamps normalized,
    lists of objects order-insensitive."""
    if isinstance(value, dict):
        out = {}
        for key, val in value.items():
            if key in ignored:
                continue
            if key in TIMESTAMP_FIELDS and isinstance(val, str):
                val = normalize_ts(val)
            pruned = _prune(val, ignored)
            if _empty(pruned):
                continue
            out[key] = pruned
        return out
    if isinstance(value, list):
        items = [_prune(v, ignored) for v in value]
        items = [v for v in items if not _empty(v)]
        if items and all(isinstance(v, dict) for v in items):
            items.sort(key=lambda v: json.dumps(v, sort_keys=True))
        return items
    return value


def canonical_form(data: dict, ignored: frozenset[str] | None = None) -> str:
    ignored = ignored if ignored is not None else frozenset(DEFAULT_IGNORED_FIELDS)
    return json.dumps(_prune(data, ignored), sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def semantic_hash(data: dict, ignored: frozenset[str] | None = None) -> str:
    return hashlib.sha256(canonical_form(data, ignored).encode("utf-8")).hexdigest()


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_records(path: Path, ignored: frozenset[str] | None = None) -> RecordSet:
    """Parse a native-export JSONL. Every shape problem is an error, not a skip:
    a record this cannot classify is a record whose loss would be invisible."""
    rs = RecordSet()
    ignored = ignored if ignored is not None else frozenset(DEFAULT_IGNORED_FIELDS)
    try:
        rs.sha256 = file_sha256(path)
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        rs.errors.append(f"{path}: unreadable: {exc}")
        return rs
    for line_number, raw in enumerate(text.split("\n"), start=1):
        line = raw.rstrip("\r")
        if not line.strip():
            continue
        rs.line_count += 1
        try:
            data = json.loads(line)
        except json.JSONDecodeError as exc:
            rs.errors.append(f"{path.name}:{line_number}: invalid JSON: {exc.msg}")
            continue
        if not isinstance(data, dict):
            rs.errors.append(f"{path.name}:{line_number}: not a JSON object")
            continue
        kind = data.get("_type") or "issue"
        if kind == "memory":
            key, value = data.get("key"), data.get("value")
            if not isinstance(key, str) or not key or not isinstance(value, str):
                rs.errors.append(f"{path.name}:{line_number}: invalid memory record")
                continue
            rkey = f"memory:{key}"
        elif kind == "issue":
            issue_id = data.get("id")
            if not isinstance(issue_id, str) or not issue_id:
                rs.errors.append(f"{path.name}:{line_number}: missing string id")
                continue
            rkey = issue_id
        else:
            rs.errors.append(f"{path.name}:{line_number}: unsupported record type {kind!r}")
            continue
        if rkey in rs.records:
            rs.errors.append(f"{path.name}:{line_number}: duplicate record {rkey}")
            continue
        rs.records[rkey] = Record(
            key=rkey,
            kind=kind,
            raw=line,
            data=data,
            semantic=semantic_hash(data, ignored),
            updated_at=normalize_ts(data.get("updated_at") or "") if kind == "issue" else "",
        )
    return rs


# ─── bounded native export ────────────────────────────────────────────


def group_alive(pgid: int) -> bool:
    """True while any process is left in the group — the leader having exited
    says nothing about its children."""
    try:
        os.killpg(pgid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:  # pragma: no cover - members we may not signal
        return True


def stop_group(pgid: int, reap, grace: float = 5.0) -> None:
    """TERM the group, then KILL it, and only return once nothing in it is left.

    `reap` is called while polling so the leader is collected; otherwise a
    zombie leader keeps the group registered and this could never conclude.
    """
    import time
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(pgid, sig)
        except ProcessLookupError:
            return
        deadline = time.monotonic() + grace
        while time.monotonic() < deadline:
            reap()
            if not group_alive(pgid):
                return
            time.sleep(0.05)


def run_bounded(cmd: list[str], cwd: Path, timeout: float) -> tuple[int, str, str]:
    """Run cmd in its own process group; on timeout kill the whole group.

    Returns (rc, stdout, stderr); rc is 124 on timeout, like coreutils.
    """
    proc = subprocess.Popen(
        cmd, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        start_new_session=True,
    )
    try:
        out, err = proc.communicate(timeout=timeout)
        return proc.returncode, out, err
    except subprocess.TimeoutExpired:
        stop_group(proc.pid, proc.poll)
        try:
            out, err = proc.communicate(timeout=5)
        except subprocess.TimeoutExpired:  # pragma: no cover - already killed
            out, err = "", ""
        return 124, out, (err or "") + f"\ntimed out after {timeout}s"


def native_export(repo: Path, bd_command: str, dest: Path, timeout: float) -> str | None:
    """Private `bd export` run FROM `repo`. Returns an error string or None.

    Deliberately cwd-based and not `bd -C repo`: in a linked git worktree,
    bd 1.1.2's -C resolves the database by walking up from the given path
    without the worktree redirect, and lands on whatever .beads/ sits above
    the worktree — on Clavain, the ~/projects workspace database, not this
    project's. Run from the worktree, bd follows the .git file to the main
    checkout's database. Measured 2026-09-07; the same shape as sylveste-vqlu.
    """
    resolved = resolve_bd(bd_command)
    if resolved is None:
        return f"bd command not found: {bd_command}"
    rc, out, err = run_bounded(
        [resolved, "export", "-o", str(dest)], cwd=repo, timeout=timeout,
    )
    if rc != 0:
        detail = (err or out or "").strip().splitlines()
        return f"bd export failed (rc={rc}): {detail[-1] if detail else 'no output'}"
    if not dest.exists() or dest.stat().st_size == 0:
        return "bd export produced no output"
    return None


# ─── verified baseline and conflict state ─────────────────────────────
#
# The baseline is per record and durable: key -> semantic hash of the last
# content on which the transport and the database were SEEN TO AGREE (at a
# reconciliation pass, after a verified export, or after a verified import).
# It is not the committed blob. HEAD is whatever was last committed, which
# after a preserve-and-flag export is the transport's side of a conflict — and
# a pass that took HEAD as provenance would then read the database's side as a
# fresh one-sided change and publish it. Provenance has to remember what was
# verified, and only that.
#
# Conflict state is carried the same way, so a conflict first seen on one pass
# is still a conflict on the next until the two sides actually agree.

Baseline = dict[str, str]
STATE_VERSION = 1


def load_state(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {"version": STATE_VERSION, "records": {}}
    if not isinstance(data, dict) or not isinstance(data.get("records"), dict):
        return {"version": STATE_VERSION, "records": {}}
    return data


class ConflictStateError(Exception):
    """conflicts.json exists but its content cannot be trusted."""


def load_conflicts_state(path: Path) -> dict:
    """Prior conflicts are authoritative: a key recorded here is what keeps an
    unresolved conflict from being silently reclassified as an ordinary
    one-sided change on the next pass (see `reconcile`'s `known_conflicts`).

    A missing file legitimately means no prior conflicts — `load_state`'s
    "unreadable/malformed -> empty" is right for that. It is wrong here: once
    conflicts.json is what protects a conflict from disappearing, treating a
    corrupt copy of it as empty would make every conflict it recorded vanish
    along with the file — the same silent loss this module exists to catch,
    just triggered by disk damage instead of a classification bug. Fail the
    pass instead: this raises before anything is written, so the file and the
    evidence it points at are left exactly as they were.
    """
    if not path.exists():
        return {"version": STATE_VERSION, "records": {}}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise ConflictStateError(f"{path}: unreadable or invalid JSON: {exc}") from exc
    if not isinstance(data, dict) or not isinstance(data.get("records"), dict):
        raise ConflictStateError(
            f"{path}: malformed conflict state (expected an object with a 'records' object)"
        )
    for key, entry in data["records"].items():
        problem = _conflict_entry_shape_error(entry)
        if problem is not None:
            raise ConflictStateError(f"{path}: record {key!r}: {problem}")
    return data


def _conflict_entry_shape_error(entry: object) -> str | None:
    """None if `entry` is a shape `next_conflicts` could have written; a
    description of the first problem otherwise.

    Every field is optional here — an old entry with no `evidence_history`
    is exactly as valid as a fresh one with one (`next_conflicts` treats a
    missing `evidence`/`evidence_history` as "none yet", not as damage) — but
    a field that IS present must have the type `next_conflicts` would give
    it. A bare `isinstance(records, dict)` check on the outer file, as
    `load_state` does, would accept a string `evidence_history` (Python
    happily iterates a string into "the individual characters are all
    strings" and calls that valid) or an integer `evidence` unchanged into
    every future proposal — corrupting the very provenance this state exists
    to protect, silently, on the next write.
    """
    if not isinstance(entry, dict):
        return "not an object"
    for field_name in ("reason", "transport_updated_at", "database_updated_at", "first_seen", "last_seen"):
        if field_name in entry and not isinstance(entry[field_name], str):
            return f"{field_name!r} must be a string"
    for field_name in ("transport_hash", "database_hash", "baseline_hash", "evidence"):
        if field_name in entry and entry[field_name] is not None and not isinstance(entry[field_name], str):
            return f"{field_name!r} must be a string or null"
    if "evidence_history" in entry:
        history = entry["evidence_history"]
        if not isinstance(history, list) or not all(isinstance(item, str) for item in history):
            return "'evidence_history' must be a list of strings"
    return None


def baseline_from_state(state: dict) -> Baseline:
    return {k: v["hash"] for k, v in state.get("records", {}).items()
            if isinstance(v, dict) and isinstance(v.get("hash"), str)}


def baseline_from_records(rs: RecordSet) -> Baseline:
    return {k: r.semantic for k, r in rs.records.items()}


def private_write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=1, sort_keys=True)
        handle.write("\n")
    os.replace(tmp, path)


# ─── reconciliation ───────────────────────────────────────────────────


@dataclass
class Conflict:
    key: str
    reason: str
    transport_hash: str | None
    database_hash: str | None
    baseline_hash: str | None
    transport_updated_at: str
    database_updated_at: str

    def public(self) -> dict:
        return {
            "id": self.key,
            "reason": self.reason,
            "transport_hash": self.transport_hash,
            "database_hash": self.database_hash,
            "baseline_hash": self.baseline_hash,
            "transport_updated_at": self.transport_updated_at,
            "database_updated_at": self.database_updated_at,
        }


@dataclass
class Reconciliation:
    equal: list[str] = field(default_factory=list)
    presentation_only: list[str] = field(default_factory=list)
    database_changed: list[str] = field(default_factory=list)   # one-sided, export applies
    database_only: list[str] = field(default_factory=list)      # new here, export adds
    transport_changed: list[str] = field(default_factory=list)  # one-sided, import pending
    transport_only: list[str] = field(default_factory=list)     # absent here; preserved
    transport_removed: list[str] = field(default_factory=list)  # gone from transport; not re-added
    dropped: list[str] = field(default_factory=list)            # explicitly confirmed deletions
    conflicts: list[Conflict] = field(default_factory=list)
    baseline_available: bool = False

    @property
    def conflict_ids(self) -> list[str]:
        return [c.key for c in self.conflicts]

    @property
    def export_needed(self) -> bool:
        return bool(self.database_changed or self.database_only or self.dropped)

    @property
    def incomplete_reasons(self) -> list[str]:
        reasons = []
        if self.conflicts:
            reasons.append(f"{len(self.conflicts)} conflicting record(s)")
        if self.transport_changed:
            reasons.append(f"{len(self.transport_changed)} transport change(s) not yet imported")
        if self.transport_only:
            reasons.append(f"{len(self.transport_only)} transport-only record(s) absent from the database")
        if self.transport_removed:
            reasons.append(f"{len(self.transport_removed)} record(s) removed from the transport but still in the database")
        return reasons

    @property
    def synchronized(self) -> bool:
        return not self.incomplete_reasons

    def summary(self) -> dict:
        return {
            "equal": len(self.equal),
            "presentation_only": self.presentation_only,
            "database_changed": self.database_changed,
            "database_only": self.database_only,
            "transport_changed": self.transport_changed,
            "transport_only": self.transport_only,
            "transport_removed": self.transport_removed,
            "dropped": self.dropped,
            "conflicts": [c.public() for c in self.conflicts],
            "baseline_available": self.baseline_available,
            "export_needed": self.export_needed,
            "synchronized": self.synchronized,
            "incomplete_reasons": self.incomplete_reasons,
        }


def reconcile(
    transport: RecordSet,
    database: RecordSet,
    baseline: Baseline | None,
    drop_ids: set[str] | None = None,
    known_conflicts: frozenset[str] | None = None,
) -> Reconciliation:
    """Classify every record key across transport, database and baseline.

    Provenance comes from the baseline: a side that still matches the verified
    baseline did not change, so the other side's difference is one-sided and
    applies. A key with no baseline entry, or where both sides moved, is a
    conflict. Equal timestamps with different content are a conflict
    regardless — bd's import guard keeps the local row on a tie, so an export
    that pushed the other version would only make the two databases swap the
    file forever.

    `known_conflicts` is the set of keys already recorded as unresolved in
    conflicts.json. This baseline-only comparison cannot tell "a peer's
    change I haven't imported yet" from "the exact content an importer
    already rejected as both-sides-changed" — both look like one side
    matching the baseline and the other not. A key already on record stays a
    conflict here too; baseline equality on one side alone is not the
    demonstrated resolution that clears it (current transport and database
    content actually agreeing, handled above via `ht == hd`, is).
    """
    drop_ids = drop_ids or set()
    known_conflicts = known_conflicts or frozenset()
    r = Reconciliation(baseline_available=baseline is not None)
    baseline = baseline or {}
    keys = list(transport.records)
    keys += [k for k in database.records if k not in transport.records]
    # A key can be a known conflict without appearing in either side at all
    # this pass (both records absent). Building `keys` only from the two
    # record sets would make such a key invisible to this whole function —
    # never classified, never carried into this pass's conflicts, and then
    # `next_baseline`'s "gone from both sides" cleanup would forget it too.
    # Absence on both sides is not `--drop-id`'s recorded deletion and not
    # `ht == hd` agreement; it is silence, and silence must not resolve it.
    present = set(transport.records) | set(database.records)
    keys += [k for k in known_conflicts if k not in present]

    for key in keys:
        t = transport.records.get(key)
        d = database.records.get(key)
        ht = t.semantic if t else None
        hd = d.semantic if d else None
        hb = baseline.get(key)

        if key in drop_ids:
            if d is None:
                r.dropped.append(key)
                continue
            # A deletion confirmed for a record the database still holds is a lie
            # the other host would act on; keep it visible rather than drop it.
            r.conflicts.append(Conflict(key, "drop_requested_but_present_in_database",
                                        ht, hd, hb, t.updated_at if t else "", d.updated_at))
            continue

        if t is not None and d is not None:
            if ht == hd:
                # Same content. A byte difference here is derived counts or
                # field order, which the transport keeps as-is.
                (r.equal if t.raw == d.raw else r.presentation_only).append(key)
                continue
            conflict = Conflict(key, "", ht, hd, hb, t.updated_at, d.updated_at)
            if hb is None:
                conflict.reason = "no_baseline"
            elif t.updated_at and t.updated_at == d.updated_at:
                conflict.reason = "equal_updated_at_different_content"
            elif hd == hb and ht != hb:
                # Ordinarily one-sided (transport moved, database didn't) and
                # safe to call pending-import. Not when this exact key is a
                # known unresolved conflict: an import that HELD this content
                # back because it changed on both sides of a merge leaves the
                # database matching the (unmoved) baseline too, which looks
                # identical to an untouched database from here. Baseline
                # equality on one side alone cannot be trusted to clear it.
                if key in known_conflicts:
                    conflict.reason = "unresolved_prior_conflict"
                else:
                    r.transport_changed.append(key)
                    continue
            elif ht == hb and hd != hb:
                if t.updated_at and d.updated_at and t.updated_at > d.updated_at:
                    conflict.reason = "database_changed_but_transport_timestamp_newer"
                elif key in known_conflicts:
                    conflict.reason = "unresolved_prior_conflict"
                else:
                    r.database_changed.append(key)
                    continue
            else:
                conflict.reason = "both_changed_since_baseline"
            r.conflicts.append(conflict)
            continue

        if t is not None:            # absent from the database
            # A key can only leave known_conflicts by two sides agreeing
            # (`ht == hd` above); one side vanishing entirely cannot satisfy
            # that, so a known conflict stays visible rather than being read
            # as an ordinary not-yet-imported row.
            if key in known_conflicts:
                r.conflicts.append(Conflict(key, "unresolved_prior_conflict", ht, None, hb,
                                            t.updated_at, ""))
                continue
            r.transport_only.append(key)
            continue

        if d is not None:            # absent from the transport
            if key in known_conflicts:
                r.conflicts.append(Conflict(key, "unresolved_prior_conflict", None, hd, hb,
                                            "", d.updated_at))
                continue
            if hb is None:
                r.database_only.append(key)
            elif hd == hb:
                r.transport_removed.append(key)
            else:
                r.conflicts.append(Conflict(key, "removed_from_transport_but_changed_in_database",
                                            None, hd, hb, "", d.updated_at))
            continue

        # t is None and d is None: only reachable for a known-conflict key
        # (see how `keys` is built above) whose `--drop-id` was not given —
        # that case already returned via the drop_ids branch. Neither side
        # has anything to have agreed on, so it stays exactly what it was.
        r.conflicts.append(Conflict(key, "unresolved_prior_conflict", None, None, hb, "", ""))
    return r


def merged_lines(transport: RecordSet, database: RecordSet, recon: Reconciliation) -> list[str]:
    """The transport file a guarded export should publish.

    Transport order is kept for existing records so the git diff is the change
    and nothing else; new database records append in export order.
    """
    use_database = set(recon.database_changed)
    dropped = set(recon.dropped)
    lines: list[str] = []
    for key, rec in transport.records.items():
        if key in dropped:
            continue
        if key in use_database:
            lines.append(database.records[key].raw)
        else:
            lines.append(rec.raw)     # equal, presentation-only, preserved, or conflicted
    for key in recon.database_only:
        lines.append(database.records[key].raw)
    return lines


def next_baseline(prior: Baseline, transport: RecordSet, database: RecordSet,
                  recon: Reconciliation, applied: bool) -> Baseline:
    """The verified baseline after this pass.

    Agreement is the only thing that moves an entry: keys equal on both sides
    now, and — only if the merged transport was actually published — the
    database-side changes it carried. Conflicts, pending transport rows and
    removed rows leave their entry exactly as it was, which is what keeps a
    conflict a conflict on the next pass.
    """
    out = dict(prior)
    for key in recon.equal + recon.presentation_only:
        out[key] = database.records[key].semantic
    if applied:
        for key in recon.database_changed + recon.database_only:
            out[key] = database.records[key].semantic
        for key in recon.dropped:
            out.pop(key, None)
    conflicted = set(recon.conflict_ids)
    for key in list(out):
        # A still-open conflict can be absent from both sides this pass (see
        # `reconcile`) — that is silence, not agreement, so its baseline
        # provenance is not "gone from both sides; nothing to remember" the
        # way a genuinely departed key's is. Losing it would mean the key
        # comes back with `hb is None` and a less specific reason instead of
        # the history it actually has.
        if key not in transport.records and key not in database.records and key not in conflicted:
            out.pop(key)
    return out


def next_conflicts(prior: dict, conflicts: list[Conflict], now: str, evidence: str | None) -> dict:
    """Carry conflict state across passes: first_seen survives, resolved keys drop.

    `evidence` is kept as a single latest-pointer string for compatibility
    with existing readers. It is not the only copy: an import-time conflict's
    evidence directory holds every merge-side version (base/ours/theirs/
    before), which no later export-only pass ever reproduces (export's
    sources are only transport/database/baseline). Simply overwriting the
    pointer on each pass would orphan that reference the moment a later pass
    re-detects the same still-open conflict, so every distinct evidence
    directory this key has ever pointed at is also kept, deduplicated and in
    the order first seen, in `evidence_history` — nothing on disk is removed
    by dropping out of it.
    """
    records = {}
    prior_records = prior.get("records", {}) if isinstance(prior, dict) else {}
    for conflict in conflicts:
        entry = conflict.public()
        entry.pop("id")
        old = prior_records.get(conflict.key) or {}
        entry["first_seen"] = old.get("first_seen", now)
        entry["last_seen"] = now
        history = [e for e in old.get("evidence_history", []) if isinstance(e, str)]
        if not history and isinstance(old.get("evidence"), str):
            history = [old["evidence"]]
        new_evidence = evidence or old.get("evidence")
        if new_evidence and new_evidence not in history:
            history.append(new_evidence)
        entry["evidence"] = new_evidence
        entry["evidence_history"] = history
        records[conflict.key] = entry
    return {"version": STATE_VERSION, "records": records}


def write_evidence(
    evidence_dir: Path, conflicts: list[Conflict], sources: dict[str, RecordSet | None],
    context: dict,
) -> Path | None:
    """Every version of every conflict, privately. Public output carries hashes."""
    if not conflicts:
        return None
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    target = evidence_dir / stamp
    # The evidence is exactly the content whose publication the conflict
    # prevented: readable by this user only, and never tracked.
    evidence_dir.mkdir(parents=True, exist_ok=True)
    os.chmod(evidence_dir, 0o700)
    target.mkdir(parents=True, exist_ok=True)
    os.chmod(target, 0o700)

    def private_write(path: Path, text: str) -> None:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)

    for conflict in conflicts:
        for label, source in sources.items():
            rec = source.records.get(conflict.key) if source is not None else None
            if rec is not None:
                private_write(target / f"{conflict.key}.{label}.json", rec.raw + "\n")
    private_write(
        target / "summary.json",
        json.dumps({**context, "conflicts": [c.public() for c in conflicts]}, indent=2) + "\n",
    )
    return target


MergeSide = tuple[RecordSet, RecordSet | None, RecordSet | None]   # (base, ours, theirs)


def plan_import(batch: RecordSet, database: RecordSet, before: RecordSet | None,
                baseline: Baseline, merge_sides: list[MergeSide] | None = None,
                git_provenance: bool = False,
                known_conflicts: frozenset[str] | None = None) -> tuple[list[str], list[str], list[Conflict]]:
    """Which batch rows may go to bd import, decided before bd sees any of them.

    Absent and already-equal rows are always safe. For a row that EXISTS
    locally with different content, two kinds of provenance are needed
    before it may be called one-sided:

    Git's. `merge_sides` lists every merge in the pulled range whose parents
    diverged from our before-commit, each as (base, ours, theirs) transports.
    A record that differs from the base on BOTH sides of any of them changed
    on both hosts since they last agreed — a conflict, whichever side the
    merge took and whatever the timestamps say. This is what catches the
    ordinary case the local-state rule cannot: a local edit that was already
    exported (every commit exports) makes the local row equal to `before`, so
    without git's view it would look unchanged and the newer incoming row
    would be handed to bd and win on timestamp. `git_provenance` says the
    caller established the range's history (a fast-forward from ours, or the
    merges listed); without it — the whole-file `--full` recovery — a
    differing existing record cannot become importable merely because the
    local row equals its last export baseline. It is held as
    `no_git_provenance`.

    Local state's. With provenance, a row is one-sided when the local record
    is unchanged since the last verified state — the persisted baseline or
    the pre-merge transport. Anything else is an independent local
    modification. Conflicts go to evidence with every version, never to bd;
    bd's own strictly-newer guard stays as the second line of defense for
    what is handed over.

    `known_conflicts`: a later, unrelated range can be a plain fast-forward
    with no merge in it at all — the divergence that produced a still-open
    conflict is now behind `before`, outside this call's `merge_sides`, so
    `both_changed` never fires for it here. The local-state rule alone would
    then see local == baseline (true precisely because a held conflict never
    moves the baseline) and admit the very row the earlier pass rejected.
    A key already on record stays held until the two sides actually agree
    (`local.semantic == row.semantic`, checked above, before this runs).
    """
    importable: list[str] = []
    already: list[str] = []
    conflicts: list[Conflict] = []
    merge_sides = merge_sides or []
    known_conflicts = known_conflicts or frozenset()

    def sem(rec: Record | None) -> str | None:
        return rec.semantic if rec is not None else None

    for key, row in batch.records.items():
        local = database.records.get(key)
        both_changed = False
        base_hash: str | None = None
        for base, ours, theirs in merge_sides:
            rb = base.records.get(key)
            ro = ours.records.get(key) if ours is not None else None
            rt = theirs.records.get(key) if theirs is not None else row
            # Absent on one side and present on the other is a change too:
            # both hosts creating the same id independently is a conflict.
            if sem(ro) != sem(rb) and sem(rt) != sem(rb) and sem(ro) != sem(rt):
                both_changed, base_hash = True, sem(rb)
                break
        if both_changed:
            conflicts.append(Conflict(key, "both_changed_since_merge_base", row.semantic,
                                      sem(local), base_hash, row.updated_at,
                                      local.updated_at if local else ""))
            continue
        if local is None:
            # Absence is not the demonstrated resolution that clears a known
            # conflict — there is no content here to have agreed with. Held
            # back on export already; a later range must not quietly import
            # it just because the native side no longer exists at all.
            if key in known_conflicts:
                conflicts.append(Conflict(key, "unresolved_prior_conflict", row.semantic, None,
                                          baseline.get(key), row.updated_at, ""))
                continue
            importable.append(key)
            continue
        if local.semantic == row.semantic:
            already.append(key)
            continue
        hb = baseline.get(key)
        if not git_provenance:
            conflicts.append(Conflict(key, "no_git_provenance", row.semantic, local.semantic, hb,
                                      row.updated_at, local.updated_at))
            continue
        prior = before.records.get(key) if before is not None else None
        if key in known_conflicts:
            conflicts.append(Conflict(key, "unresolved_prior_conflict", row.semantic, local.semantic, hb,
                                      row.updated_at, local.updated_at))
            continue
        if local.semantic == hb or (prior is not None and local.semantic == prior.semantic):
            importable.append(key)
            continue
        reason = "local_changed_since_verified" if (hb is not None or prior is not None) else "no_baseline"
        conflicts.append(Conflict(key, reason, row.semantic, local.semantic, hb,
                                  row.updated_at, local.updated_at))
    return importable, already, conflicts


def verify_import(batch: RecordSet, database: RecordSet) -> dict:
    """Did every batch row land, or get legitimately held back by bd's guard?"""
    applied: list[str] = []
    kept_local: list[str] = []
    unapplied: list[str] = []
    unverified: list[str] = []
    for key, row in batch.records.items():
        local = database.records.get(key)
        if row.kind != "issue":
            unverified.append(key)      # memories are not in a default export
            continue
        if local is None:
            unapplied.append(key)
        elif local.semantic == row.semantic:
            applied.append(key)
        elif local.updated_at and row.updated_at and local.updated_at >= row.updated_at:
            kept_local.append(key)
        else:
            unapplied.append(key)
    return {
        "batch_rows": len(batch.records),
        "applied": applied,
        "kept_local": kept_local,
        "unapplied": unapplied,
        "unverified": unverified,
        "ok": batch.ok and database.ok and not unapplied,
    }


# ─── CLI ──────────────────────────────────────────────────────────────


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Validate that tracked .beads/issues.jsonl agrees with live Dolt."
    )
    parser.add_argument("--repo", type=Path, default=Path.cwd(), help="repository root")
    parser.add_argument(
        "--issues-jsonl",
        type=Path,
        default=None,
        help="path to issues.jsonl; default: <repo>/.beads/issues.jsonl",
    )
    parser.add_argument("--bd-command", default="bd", help="bd executable to run")
    parser.add_argument(
        "--strict-extra",
        action="store_true",
        help="also fail when Dolt has issue IDs absent from the tracked JSONL export",
    )
    parser.add_argument("--show", type=int, default=25, help="max mismatched IDs to print per class")
    parser.add_argument(
        "--json",
        action="store_true",
        help="emit the diff as JSON so callers can branch on direction, not just exit code",
    )
    records = parser.add_argument_group("record-level reconciliation")
    records.add_argument("--records", action="store_true",
                         help="compare every record by content against a private native export")
    records.add_argument("--state-dir", type=Path, default=None,
                         help="transport state dir holding baseline.json / conflicts.json "
                              "(default: <repo>/.beads/transport when it exists)")
    records.add_argument("--baseline", type=Path, default=None,
                         help="JSONL to use as the verified baseline when the state dir has none")
    records.add_argument("--database-export", type=Path, default=None,
                         help="use this export instead of running bd (tests, and reuse after an import)")
    records.add_argument("--keep-export", type=Path, default=None,
                         help="keep the private export at this path for reuse")
    records.add_argument("--write-merged", type=Path, default=None,
                         help="write the guarded transport file here (never the transport itself)")
    records.add_argument("--evidence-dir", type=Path, default=None,
                         help="directory for private conflict evidence (every version)")
    records.add_argument("--propose-state", type=Path, default=None,
                         help="write the post-pass baseline/conflict state here for --promote-state")
    records.add_argument("--drop-id", action="append", default=[],
                         help="record confirmed deleted here; omit it from the merged output")
    records.add_argument("--ignore-field", action="append", default=None,
                         help="field ignored in semantic comparison (default: derived counts)")
    records.add_argument("--export-timeout", type=float,
                         default=float(os.environ.get("BEADS_EXPORT_TIMEOUT", EXPORT_TIMEOUT_DEFAULT)))
    imports = parser.add_argument_group("import side")
    imports.add_argument("--plan-import", type=Path, default=None,
                         help="classify this batch against the database; write the importable rows with --write-batch")
    imports.add_argument("--before", type=Path, default=None,
                         help="the transport as committed before the merge, i.e. ours (provenance for --plan-import)")
    imports.add_argument("--base", type=Path, default=None,
                         help="shorthand for one --merge-side with ours = --before: the transport at the merge base")
    imports.add_argument("--theirs", type=Path, default=None,
                         help="shorthand for one --merge-side with ours = --before: the incoming side's transport")
    imports.add_argument("--merge-side", nargs=3, action="append", default=[], metavar=("BASE", "OURS", "THEIRS"),
                         help="a merge in the pulled range that diverged from ours: base, ours and theirs transports (repeatable)")
    imports.add_argument("--git-provenance", action="store_true",
                         help="the caller established the range's git history (fast-forward from ours, or the merges given); "
                              "without it differing existing records are held as no_git_provenance")
    imports.add_argument("--write-batch", type=Path, default=None,
                         help="where --plan-import writes the rows bd may import")
    imports.add_argument("--verify-import", type=Path, default=None,
                         help="verify that this imported batch is reflected in the database")
    state = parser.add_argument_group("state promotion")
    state.add_argument("--promote-state", type=Path, default=None,
                       help="a proposal from --propose-state to install into --state-dir")
    state.add_argument("--applied", action="store_true",
                       help="with --promote-state: the merged transport / batch was actually applied")
    state.add_argument("--seed-baseline", type=Path, default=None,
                       help="establish the baseline from this JSONL (after a reviewed reconciliation)")
    return parser


def _fail_json(payload: dict, code: int) -> int:
    print(json.dumps(payload))
    return code


def _state_dir(args: argparse.Namespace, repo: Path) -> Path | None:
    if args.state_dir is not None:
        return args.state_dir
    default = repo / ".beads" / "transport"
    return default if default.exists() else None


def _load_baseline(args: argparse.Namespace, state_dir: Path | None, ignored: frozenset[str],
                   out: dict) -> tuple[Baseline | None, RecordSet | None, dict]:
    """Persisted state first; an explicit JSONL only when there is none."""
    baseline_records = None
    baseline_state: dict = {"version": STATE_VERSION, "records": {}}
    if state_dir is not None and (state_dir / "baseline.json").exists():
        baseline_state = load_state(state_dir / "baseline.json")
        baseline = baseline_from_state(baseline_state)
        out["baseline"] = {"source": str(state_dir / "baseline.json"), "records": len(baseline)}
        return baseline, None, baseline_state
    if args.baseline is not None:
        if not args.baseline.exists():
            out["errors"].append(f"baseline missing: {args.baseline}")
            return None, None, baseline_state
        baseline_records = load_records(args.baseline, ignored)
        out["baseline"] = {"source": str(args.baseline), "sha256": baseline_records.sha256,
                           "records": len(baseline_records.records)}
        out["errors"] += baseline_records.errors
        return baseline_from_records(baseline_records), baseline_records, baseline_state
    out["baseline"] = None
    return None, None, baseline_state


def promote_state(proposal_path: Path, state_dir: Path, applied: bool) -> dict:
    proposal = json.loads(proposal_path.read_text(encoding="utf-8"))
    key = "baseline_if_applied" if applied else "baseline_if_not_applied"
    baseline = proposal[key]
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    private_write_json(state_dir / "baseline.json", {
        "version": STATE_VERSION, "updated_at": now, "applied": applied,
        "records": {k: {"hash": h} for k, h in baseline.items()},
    })
    private_write_json(state_dir / "conflicts.json", proposal["conflicts"])
    proposal_path.unlink(missing_ok=True)
    return {"baseline_records": len(baseline), "conflicts": len(proposal["conflicts"].get("records", {}))}


def run_records_mode(args: argparse.Namespace, repo: Path, issues_jsonl: Path) -> int:
    ignored = frozenset(args.ignore_field) if args.ignore_field is not None else frozenset(DEFAULT_IGNORED_FIELDS)
    state_dir = _state_dir(args, repo)
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    out: dict = {"mode": "records", "coverage": "unavailable", "status": "unavailable",
                 "transport": {"path": str(issues_jsonl)}, "errors": []}

    if args.promote_state is not None:
        if state_dir is None:
            out["errors"].append("--promote-state needs --state-dir")
            return _fail_json(out, 2)
        try:
            out.update(promote_state(args.promote_state, state_dir, args.applied))
        except (OSError, ValueError, KeyError) as exc:
            out["errors"].append(f"cannot promote state: {exc}")
            return _fail_json(out, 2)
        out.update({"coverage": "complete", "status": "promoted"})
        return _fail_json(out, 0)

    if args.seed_baseline is not None:
        if state_dir is None:
            out["errors"].append("--seed-baseline needs --state-dir")
            return _fail_json(out, 2)
        seed = load_records(args.seed_baseline, ignored)
        if not seed.ok:
            out["errors"] += seed.errors
            out["coverage"] = "invalid"
            return _fail_json(out, 2)
        private_write_json(state_dir / "baseline.json", {
            "version": STATE_VERSION, "updated_at": now, "seeded_from": str(args.seed_baseline),
            "records": {k: {"hash": h} for k, h in baseline_from_records(seed).items()},
        })
        out.update({"coverage": "complete", "status": "seeded", "baseline_records": len(seed.records)})
        return _fail_json(out, 0)

    # Transport side first, BEFORE the export runs. The export takes seconds,
    # and the hash recorded here is what the caller re-checks immediately
    # before replacing the file; reading the transport afterwards would let a
    # write that landed during the export pass as "unchanged".
    transport: RecordSet | None = None
    if args.verify_import is None and args.plan_import is None:
        if not issues_jsonl.exists():
            out["errors"].append(f"transport file missing: {issues_jsonl}")
            return _fail_json(out, 2)
        transport = load_records(issues_jsonl, ignored)
        out["transport"].update({"sha256": transport.sha256, "records": len(transport.records)})

    tmpdir = None
    export_path = args.database_export
    if export_path is None:
        if resolve_bd(args.bd_command) is None:
            out["errors"].append(f"bd command not found: {args.bd_command}")
            return _fail_json(out, 2)
        tmpdir = tempfile.mkdtemp(prefix="sylveste-beads-export.")
        export_path = Path(tmpdir) / "database.jsonl"
        error = native_export(repo, args.bd_command, export_path, args.export_timeout)
        if error:
            out["errors"].append(error)
            shutil.rmtree(tmpdir, ignore_errors=True)
            return _fail_json(out, 2)
    try:
        database = load_records(export_path, ignored)
        out["database"] = {"sha256": database.sha256, "records": len(database.records),
                           "exported_at": now}
        if args.keep_export is not None:
            shutil.copyfile(export_path, args.keep_export)
            os.chmod(args.keep_export, 0o600)
            out["database"]["kept_at"] = str(args.keep_export)
    finally:
        if tmpdir is not None:
            shutil.rmtree(tmpdir, ignore_errors=True)

    baseline, baseline_records, baseline_state = _load_baseline(args, state_dir, ignored, out)
    try:
        prior_conflicts = (load_conflicts_state(state_dir / "conflicts.json")
                          if state_dir is not None else {"version": STATE_VERSION, "records": {}})
    except ConflictStateError as exc:
        out["errors"].append(str(exc))
        out["coverage"] = "invalid"
        out["status"] = "conflict_state_unreadable"
        return _fail_json(out, 2)

    # ── import side ──
    if args.plan_import is not None:
        batch = load_records(args.plan_import, ignored)

        def side(path: Path | None, label: str) -> RecordSet | None:
            if path is None:
                return None
            if not path.exists():
                out["errors"].append(f"{label} transport missing: {path}")
                return None
            return load_records(path, ignored)

        before = side(args.before, "before")
        merge_sides: list[MergeSide] = []
        sources: dict[str, RecordSet | None] = {"incoming": batch, "database": database, "before": before}
        triples = [(Path(b), Path(o), Path(t)) for b, o, t in args.merge_side]
        if args.base is not None:
            triples.append((args.base, args.before, args.theirs))
        for i, (b, o, t) in enumerate(triples):
            base = side(b, f"merge {i} base")
            ours = side(o, f"merge {i} ours") if o is not None else before
            theirs = side(t, f"merge {i} theirs") if t is not None else None
            if base is not None:
                merge_sides.append((base, ours, theirs))
                suffix = "" if len(triples) == 1 else f"-{i}"
                # Every version a conflict can involve goes to evidence: the
                # merge base, both sides of the merge (ours is not always the
                # pre-merge transport — an upstream merge has its own), and
                # the incoming/database/before rows recorded above.
                sources[f"base{suffix}"], sources[f"theirs{suffix}"] = base, theirs
                if ours is not None and ours is not before:
                    sources[f"ours{suffix}"] = ours
        out["errors"] += batch.errors + database.errors
        for rs in list(sources.values()):
            if rs is not None:
                out["errors"] += rs.errors
        if out["errors"]:
            out["coverage"] = "invalid"
            out["status"] = "invalid_input"
            return _fail_json(out, 2)
        git_provenance = bool(args.git_provenance or merge_sides)
        importable, already, conflicts = plan_import(batch, database, before, baseline or {},
                                                     merge_sides, git_provenance,
                                                     known_conflicts=frozenset(prior_conflicts.get("records", {})))
        evidence = None
        if args.evidence_dir is not None and conflicts:
            evidence = write_evidence(args.evidence_dir, conflicts, sources,
                                      {"phase": "import", "database_sha256": database.sha256,
                                       "batch_sha256": batch.sha256, "written_at": now,
                                       "git_provenance": git_provenance, "merges": len(merge_sides)})
        if args.write_batch is not None:
            text = "".join(batch.records[k].raw + "\n" for k in importable)
            fd = os.open(args.write_batch, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write(text)
        if args.propose_state is not None:
            # Rows already equal are verified agreement now; importable rows
            # become baseline only once the import is verified (--applied).
            not_applied = dict(baseline or {})
            for key in already:
                not_applied[key] = database.records[key].semantic
            applied = dict(not_applied)
            for key in importable:
                applied[key] = batch.records[key].semantic
            merged_conflicts = next_conflicts(prior_conflicts, conflicts, now,
                                              str(evidence) if evidence else None)
            # Export-side conflicts that this pass did not look at stay recorded.
            for key, entry in prior_conflicts.get("records", {}).items():
                if key not in merged_conflicts["records"] and key not in batch.records:
                    merged_conflicts["records"][key] = entry
            private_write_json(args.propose_state, {
                "baseline_if_applied": applied, "baseline_if_not_applied": not_applied,
                "conflicts": merged_conflicts,
            })
        out.update({
            "coverage": "complete", "status": "planned",
            "batch_rows": len(batch.records), "importable": importable, "already_applied": already,
            "conflicts": [c.public() for c in conflicts], "evidence_path": str(evidence) if evidence else None,
            "baseline_available": baseline is not None or before is not None,
            "git_provenance": git_provenance, "merges_considered": len(merge_sides),
        })
        return _fail_json(out, 0)

    if args.verify_import is not None:
        batch = load_records(args.verify_import, ignored)
        verdict = verify_import(batch, database)
        out.update(verdict)
        out["errors"] += batch.errors + database.errors
        out["coverage"] = "complete" if batch.ok and database.ok else "invalid"
        out["status"] = "verified" if verdict["ok"] else "unverified"
        if args.propose_state is not None and out["coverage"] == "complete":
            applied = dict(baseline or {})
            for key in verdict["applied"]:
                applied[key] = database.records[key].semantic
            kept = [Conflict(k, "native_guard_kept_local", batch.records[k].semantic,
                             database.records[k].semantic, (baseline or {}).get(k),
                             batch.records[k].updated_at, database.records[k].updated_at)
                    for k in verdict["kept_local"]]
            evidence = None
            if args.evidence_dir is not None and kept:
                evidence = write_evidence(args.evidence_dir, kept, {"incoming": batch, "database": database},
                                          {"phase": "import-verify", "written_at": now})
            merged_conflicts = next_conflicts(prior_conflicts, kept, now, str(evidence) if evidence else None)
            for key, entry in prior_conflicts.get("records", {}).items():
                if key not in merged_conflicts["records"] and key not in verdict["applied"]:
                    merged_conflicts["records"][key] = entry
            private_write_json(args.propose_state, {
                "baseline_if_applied": applied, "baseline_if_not_applied": dict(baseline or {}),
                "conflicts": merged_conflicts,
            })
        return _fail_json(out, 0 if verdict["ok"] else (2 if not out["coverage"] == "complete" else 1))

    # ── export side ──
    assert transport is not None
    out["errors"] += transport.errors + database.errors
    if out["errors"]:
        out["coverage"] = "invalid"
        out["status"] = "invalid_input"
        return _fail_json(out, 2)

    recon = reconcile(transport, database, baseline, set(args.drop_id),
                      known_conflicts=frozenset(prior_conflicts.get("records", {})))
    diff = diff_issue_ids(transport.issue_ids, database.issue_ids)
    out.update({
        "coverage": "complete",
        "jsonl_count": diff.jsonl_count,
        "dolt_count": diff.dolt_count,
        "missing_in_dolt": diff.missing_in_dolt,
        "extra_in_dolt": diff.extra_in_dolt,
        "jsonl_max_updated": max((r.updated_at for r in transport.records.values()), default=""),
        "dolt_max_updated": max((r.updated_at for r in database.records.values()), default=""),
        "safe_to_export": True,       # the merged writer never overwrites transport-side work
        **recon.summary(),
    })
    out["content_stale"] = bool(recon.database_changed or recon.database_only)
    out["status"] = "equal" if (not recon.export_needed and recon.synchronized) else "drift"

    evidence = None
    if args.evidence_dir is not None:
        evidence = write_evidence(args.evidence_dir, recon.conflicts,
                                  {"transport": transport, "database": database, "baseline": baseline_records},
                                  {"phase": "export", "transport_sha256": transport.sha256,
                                   "database_sha256": database.sha256, "written_at": now})
        out["evidence_path"] = str(evidence) if evidence else None

    if args.propose_state is not None:
        prior = baseline or {}
        merged_conflicts = next_conflicts(prior_conflicts, recon.conflicts, now, str(evidence) if evidence else None)
        private_write_json(args.propose_state, {
            "baseline_if_applied": next_baseline(prior, transport, database, recon, applied=True),
            "baseline_if_not_applied": next_baseline(prior, transport, database, recon, applied=False),
            "conflicts": merged_conflicts,
        })
        out["state_proposal"] = str(args.propose_state)

    if args.write_merged is not None:
        lines = merged_lines(transport, database, recon)
        text = "".join(line + "\n" for line in lines)
        args.write_merged.write_text(text, encoding="utf-8")
        check = load_records(args.write_merged, ignored)
        expected = len(transport.records) - len(recon.dropped) + len(recon.database_only)
        if not check.ok or len(check.records) != expected:
            out["errors"] += check.errors or [f"merged output has {len(check.records)} records, expected {expected}"]
            out["coverage"] = "invalid"
            out["status"] = "invalid_output"
            args.write_merged.unlink(missing_ok=True)
            return _fail_json(out, 2)
        out["merged"] = {"path": str(args.write_merged), "sha256": check.sha256,
                         "records": len(check.records),
                         "changes_transport": check.sha256 != transport.sha256}
    print(json.dumps(out))
    return 0 if out["status"] == "equal" else 1


def main(argv: list[str] | None = None) -> int:
    # Cloud-guard: this script asks Dolt for issue ids and compares to JSONL.
    # In cloud there is no Dolt, and we treat JSONL as the source of truth,
    # so the comparison is meaningless. Skip cleanly with exit 0.
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    try:
        from lib_cloud_guard import cloud_session, cloud_log_skip, workstation_log_missing_bd
    except ImportError:
        cloud_session = lambda: False  # type: ignore
        cloud_log_skip = lambda op="op": None  # type: ignore
        workstation_log_missing_bd = lambda op="op": None  # type: ignore
    if cloud_session():
        cloud_log_skip("check_beads_jsonl_dolt_sync")
        return 0

    args = build_parser().parse_args(argv)
    repo = args.repo.resolve()
    issues_jsonl = args.issues_jsonl or (repo / ".beads" / "issues.jsonl")

    if (args.records or args.verify_import is not None or args.plan_import is not None
            or args.promote_state is not None or args.seed_baseline is not None):
        return run_records_mode(args, repo, issues_jsonl)

    if shutil.which("bd") is None and resolve_bd(args.bd_command) is None:
        # Legacy advisory contract: absent tooling is logged, not failed. Record
        # mode above is what export decisions use, and it refuses instead.
        workstation_log_missing_bd("check_beads_jsonl_dolt_sync")
        return 0

    try:
        jsonl_ids = load_jsonl_issue_ids(issues_jsonl)
        dolt_ids = load_dolt_issue_ids(repo, args.bd_command)
    except Exception as exc:
        print(f"beads_jsonl_dolt_sync error: {exc}", file=sys.stderr)
        return 2

    diff = diff_issue_ids(jsonl_ids=jsonl_ids, dolt_ids=dolt_ids)

    # The two directions need different responses, and an exit code cannot carry
    # that. Dolt-ahead is fixed by exporting; JSONL-ahead must NEVER trigger an
    # export, because exporting would delete the issues the JSONL uniquely holds
    # — which is exactly how sylveste-j7vl came within one command of being lost.
    if args.json:
        # Membership alone misses the commonest change of all: closing a bead
        # alters its status, not the id set. Compare high-water marks too, or a
        # session that only closes issues exports nothing and the committed
        # JSONL keeps saying "open". Still partial: see `coverage`.
        jsonl_ts = load_jsonl_max_updated(issues_jsonl)
        dolt_ts = load_dolt_max_updated(repo, args.bd_command)
        content_stale = bool(dolt_ts and dolt_ts > jsonl_ts)
        print(json.dumps({
            "mode": "ids",
            "coverage": "partial",
            "jsonl_count": diff.jsonl_count,
            "dolt_count": diff.dolt_count,
            "missing_in_dolt": diff.missing_in_dolt,
            "extra_in_dolt": diff.extra_in_dolt,
            "jsonl_max_updated": jsonl_ts,
            "dolt_max_updated": dolt_ts,
            "content_stale": content_stale,
            "safe_to_export": not diff.missing_in_dolt,
            "export_needed": bool(diff.extra_in_dolt) or content_stale,
        }))
        return 1 if (diff.missing_in_dolt or (args.strict_extra and diff.extra_in_dolt)) else 0

    print(
        "beads_jsonl_dolt_sync "
        f"jsonl_count={diff.jsonl_count} dolt_count={diff.dolt_count} "
        f"missing_in_dolt={len(diff.missing_in_dolt)} extra_in_dolt={len(diff.extra_in_dolt)}"
    )
    if diff.missing_in_dolt:
        print("JSONL issue IDs absent from live Dolt:")
        for issue_id in diff.missing_in_dolt[: args.show]:
            print(f"  - {issue_id}")
        if len(diff.missing_in_dolt) > args.show:
            print(f"  ... {len(diff.missing_in_dolt) - args.show} more")
    if diff.extra_in_dolt and args.strict_extra:
        print("Dolt issue IDs absent from tracked JSONL:")
        for issue_id in diff.extra_in_dolt[: args.show]:
            print(f"  - {issue_id}")
        if len(diff.extra_in_dolt) > args.show:
            print(f"  ... {len(diff.extra_in_dolt) - args.show} more")

    if diff.missing_in_dolt or (args.strict_extra and diff.extra_in_dolt):
        print("Reconcile with the guarded transport: scripts/beads-auto-export.sh --manual "
              "(exports database-side changes, preserves rows only the JSONL holds).")
        return 1
    print("beads_jsonl_dolt_sync ok")
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
