#!/usr/bin/env bash
# Tests for the deletion half of the two-machine sync.
#
# `bd import` is upsert-only, so a bead deleted on one machine survives on the
# other and is written back out on its next export — the deletion undoes itself.
# scripts/beads_apply_deletions.py closes that, driven by an explicit ledger.
#
# The property that matters most is NOT "the named bead is deleted" — it is
# "nothing else is". An applier that deleted the whole database would satisfy
# every other assertion here, so scenario 4 exists to make the rest mean
# something.
#
# Runs against a stubbed `bd`, so it never touches a real Dolt database. The
# end-to-end proof on two real databases is a manual exercise; this is the
# regression guard.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$SANDBOX/scripts" "$SANDBOX/.beads" "$SANDBOX/bin"
cp "$ROOT/scripts/beads_apply_deletions.py" "$SANDBOX/scripts/"
cp "$ROOT/scripts/beads-confirm-deletion.sh" "$SANDBOX/scripts/"
cp "$ROOT/scripts/lib-beads-transport.sh" "$SANDBOX/scripts/"
cp "$ROOT/scripts/check_beads_jsonl_dolt_sync.py" "$SANDBOX/checker.real.py"

# Stub bd. DB holds "id<TAB>updated_at" per line and is the whole contract the
# applier depends on: show tells it what exists and when it changed, delete
# removes it, export serializes what is left. Accepts the `-C <dir>` prefix
# the real scripts pin their database with. BD_STUB_SHOW_FAIL makes `show`
# fail for a reason that is NOT absence.
cat > "$SANDBOX/bin/bd" <<'STUB'
#!/usr/bin/env bash
DB="${BD_STUB_DB:?}"
while [ $# -gt 0 ]; do case "$1" in --readonly|--sandbox) shift ;; *) break ;; esac; done
if [ "${1:-}" = "-C" ]; then shift 2; fi
case "${1:-}" in
  context) printf '{"beads_dir":"%s","project_id":"stub","is_worktree":false}\n' "$(dirname "$DB")" ;;
  show)
    id="$2"
    if [ -n "${BD_STUB_SHOW_FAIL:-}" ]; then
      echo "Error: dial tcp 127.0.0.1:3307: connect: connection refused" >&2
      exit 1
    fi
    line="$(grep -m1 "^$id	" "$DB" 2>/dev/null || true)"
    if [ -z "$line" ]; then
      echo "Error fetching $id: no issue found matching \"$id\"" >&2
      exit 1
    fi
    printf '[{"id":"%s","status":"open","updated_at":"%s"}]\n' "$id" "$(printf '%s' "$line" | cut -f2)"
    ;;
  delete)
    id="$2"
    grep -v "^$id	" "$DB" > "$DB.tmp" 2>/dev/null || true
    mv "$DB.tmp" "$DB"
    echo "✓ Deleted $id"
    ;;
  export)
    out=""
    while [ $# -gt 0 ]; do case "$1" in -o|--output) out="$2"; shift ;; esac; shift; done
    out="${out:-.beads/issues.jsonl}"
    : > "$out"
    while IFS=$'\t' read -r id ts; do
      [ -n "$id" ] && printf '{"id":"%s","updated_at":"%s"}\n' "$id" "$ts" >> "$out"
    done < "$DB"
    echo "Exported to $out"
    ;;
  info) echo "Database: $DB"; echo "Mode: direct" ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$SANDBOX/bin/bd"
export PATH="$SANDBOX/bin:$PATH"
export BD_STUB_DB="$SANDBOX/.beads/db"       # bound to this checkout's .beads/
export BEADS_TRANSPORT_LOCK_BASE="$SANDBOX/locks"; mkdir -p "$BEADS_TRANSPORT_LOCK_BASE"

cd "$SANDBOX"
git init -q .
git config user.email t@test; git config user.name tester
git config core.hooksPath /dev/null

reset_db() {
  printf 'keep-1\t2026-07-01T00:00:00Z\ntarget\t2026-07-01T00:00:00Z\nkeep-2\t2026-07-01T00:00:00Z\n' > "$BD_STUB_DB"
}
ledger() { printf '%s\n' "$@" > .beads/deletions.jsonl; }
present() { grep -q "^$1	" "$BD_STUB_DB"; }
use_real_checker() { cp "$SANDBOX/checker.real.py" scripts/check_beads_jsonl_dolt_sync.py; }

# ─── 1: a recorded deletion is applied ────────────────────────────────
echo "=== 1: a bead named in the ledger is deleted ==="
reset_db
ledger '{"id":"target","deleted_at":"2026-07-30T00:00:00Z","actor":"mk","machine":"zklw"}'
python3 scripts/beads_apply_deletions.py --quiet >/dev/null 2>&1 || fail "a clean application exited non-zero"
present target && fail "the bead named in the ledger survived"

# ─── 2: replay is a no-op ─────────────────────────────────────────────
echo "=== 2: replaying the ledger changes nothing ==="
before="$(cat "$BD_STUB_DB")"
python3 scripts/beads_apply_deletions.py --quiet >/dev/null 2>&1 || fail "replay errored"
[ "$before" = "$(cat "$BD_STUB_DB")" ] || fail "replaying the ledger was not idempotent"

# ─── 3: newer local work is refused, loudly, and non-zero ─────────────
echo "=== 3: a bead changed here after the deletion was recorded is kept ==="
printf 'keep-1\t2026-07-01T00:00:00Z\ntarget\t2026-08-01T00:00:00Z\n' > "$BD_STUB_DB"
ledger '{"id":"target","deleted_at":"2026-07-30T00:00:00Z","actor":"mk","machine":"zklw"}'
rc=0
warn="$(python3 scripts/beads_apply_deletions.py --quiet 2>&1 >/dev/null)" || rc=$?
present target || fail "work done after the deletion record was destroyed anyway"
case "$warn" in
  *"NOT deleting"*) ;;
  *) fail "refusing to delete was silent; the operator cannot resolve what they cannot see" ;;
esac
[ "$rc" -ne 0 ] || fail "a refused deletion exited 0, so the hook would report the ledger as applied"

# ─── 4: nothing else is touched ───────────────────────────────────────
# Without this, an applier that deleted everything would pass scenarios 1-3.
echo "=== 4: beads absent from the ledger are never deleted ==="
reset_db
ledger '{"id":"target","deleted_at":"2026-07-30T00:00:00Z","actor":"mk","machine":"zklw"}'
python3 scripts/beads_apply_deletions.py --quiet >/dev/null 2>&1
present keep-1 || fail "a bead not named in the ledger was deleted"
present keep-2 || fail "a bead not named in the ledger was deleted"

# ─── 5: an unusable ledger line is loud and non-zero ──────────────────
echo "=== 5: a malformed ledger line is reported, not skipped quietly ==="
reset_db
ledger '{"id":"target","deleted_at":"2026-07-30T00:00:00Z"}' 'not json at all'
out="$(python3 scripts/beads_apply_deletions.py --quiet 2>&1 >/dev/null)" && rc=0 || rc=$?
case "$out" in
  *"not a usable record"*) ;;
  *) fail "a malformed ledger line was skipped silently; a deletion could be lost" ;;
esac
[ "${rc:-0}" -ne 0 ] || fail "a malformed ledger line exited 0"

# ─── 6: a bd failure is not absence ───────────────────────────────────
# `bd show` failing used to read as "not here", so the ledger replayed while
# nothing was checked, and the hook reported the deletions as applied.
echo "=== 6: a bd show that fails for a non-absence reason is an error, not a skip ==="
reset_db
ledger '{"id":"target","deleted_at":"2026-07-30T00:00:00Z","actor":"mk","machine":"zklw"}'
rc=0
out="$(BD_STUB_SHOW_FAIL=1 python3 scripts/beads_apply_deletions.py --quiet 2>&1 >/dev/null)" || rc=$?
[ "$rc" -ne 0 ] || fail "a failing bd show was treated as success"
case "$out" in *"could not determine local state"*"connection refused"*) ;; *) fail "the bd error was not surfaced: $out" ;; esac
present target || fail "a bead was deleted while bd could not even be asked about it"

# ─── 7: an unreadable timestamp is a refusal ──────────────────────────
echo "=== 7: a deletion record whose timestamp cannot be read is not applied ==="
reset_db
ledger '{"id":"target","deleted_at":"yesterday-ish","actor":"mk","machine":"zklw"}'
rc=0
out="$(python3 scripts/beads_apply_deletions.py --quiet 2>&1 >/dev/null)" || rc=$?
[ "$rc" -ne 0 ] || fail "an unreadable deleted_at exited 0"
present target || fail "a bead was deleted on a timestamp that could not be compared"
case "$out" in *"unreadable timestamp"*) ;; *) fail "the timestamp problem was not named: $out" ;; esac
ledger '{"id":"target","actor":"mk","machine":"zklw"}'
rc=0; python3 scripts/beads_apply_deletions.py --quiet >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] || fail "a missing deleted_at exited 0"
present target || fail "a bead was deleted on a record with no deleted_at at all"

# ─── 8: the ledger is actually written, through the guarded export ────
# The regression this catches is the deletion path quietly ceasing to record
# intent, which looks identical to "no deletions happened lately".
echo "=== 8: confirming a deletion records it and exports through the guarded merge ==="
reset_db
rm -f .beads/deletions.jsonl
use_real_checker
bd export --output .beads/issues.jsonl >/dev/null
git add -A >/dev/null 2>&1; git commit -q -m base >/dev/null 2>&1
bash scripts/beads-confirm-deletion.sh --delete-local target >/dev/null 2>&1 || fail "confirming a deletion failed"
[ -f .beads/deletions.jsonl ] || fail "confirming a deletion wrote no ledger entry"
grep -q '"id": "target"' .beads/deletions.jsonl || fail "the ledger entry does not name the deleted bead"
grep -q '"deleted_at"' .beads/deletions.jsonl || fail "the ledger entry carries no timestamp, so the guard cannot work"
grep -q '"target"' .beads/issues.jsonl && fail "the export still contains the deleted bead"
grep -q '"keep-1"' .beads/issues.jsonl && grep -q '"keep-2"' .beads/issues.jsonl || fail "the export lost beads that were not deleted"
[ "$(git log -1 --format=%s)" = "beads: confirm deletion of target" ] || fail "the ledger and export were not committed together: $(git log -1 --format=%s)"
files="$(git show --name-only --format= HEAD | sort | tr '\n' ' ')"
[ "$files" = ".beads/deletions.jsonl .beads/issues.jsonl " ] || fail "the commit does not carry exactly the ledger and the export: $files"

# ─── 9: recording a deletion that did not happen is refused ───────────
echo "=== 9: refusing to record a deletion for a bead that still exists ==="
reset_db
if bash scripts/beads-confirm-deletion.sh keep-1 >/dev/null 2>&1; then
  fail "recorded a deletion for a live bead — the other machine would act on a lie"
fi
present keep-1 || fail "the refusal deleted the bead anyway"

# ─── 10: no verdict is not permission ─────────────────────────────────
# A checker that produces no complete verdict used to be read as "go ahead"
# and the script exported directly over whatever the file held.
echo "=== 10: an unreadable or incomplete checker verdict refuses to export ==="
reset_db
rm -f .beads/deletions.jsonl
cat > scripts/check_beads_jsonl_dolt_sync.py <<'CHECK'
import json, os, sys
print(json.dumps({"missing_in_dolt": ["from-elsewhere"]}))
CHECK
{ printf '{"id":"keep-1"}\n{"id":"target"}\n{"id":"from-elsewhere"}\n'; } > .beads/issues.jsonl
if bash scripts/beads-confirm-deletion.sh --delete-local target >/dev/null 2>&1; then
  fail "exported on a verdict that was not complete"
fi
[ -f .beads/deletions.jsonl ] && fail "recorded a deletion it then refused to carry out"
grep -q 'from-elsewhere' .beads/issues.jsonl || fail "the other machine's bead was dropped from the file"
present target || fail "deleted locally before checking whether the export was safe"
rm -f scripts/check_beads_jsonl_dolt_sync.py
if bash scripts/beads-confirm-deletion.sh --delete-local target >/dev/null 2>&1; then
  fail "exported with no checker at all"
fi
present target || fail "deleted locally with no checker present"

# ─── 11: another machine's unimported work survives a confirmed deletion ─
# On zklw, whose import had been killed mid-flight, confirming ONE deletion
# once produced an export with SIX beads missing. The guarded merge keeps
# rows only the transport holds; only the confirmed ID is dropped.
echo "=== 11: a confirmed deletion never exports away rows this database has not imported ==="
reset_db
rm -f .beads/deletions.jsonl
use_real_checker
git checkout -q -- .beads/issues.jsonl 2>/dev/null || true
{ bd export --output "$SANDBOX/tmp.jsonl" >/dev/null; cat "$SANDBOX/tmp.jsonl"; printf '{"id":"from-elsewhere","updated_at":"2026-07-15T00:00:00Z"}\n'; } > .beads/issues.jsonl
git add .beads/issues.jsonl; git commit -q -m "pulled from-elsewhere (not imported)"
bash scripts/beads-confirm-deletion.sh --delete-local target >/dev/null 2>&1 || fail "confirming a deletion refused although the merge preserves the pending row"
grep -q 'from-elsewhere' .beads/issues.jsonl || fail "the other machine's unimported bead was exported away"
grep -q '"target"' .beads/issues.jsonl && fail "the confirmed deletion was not applied to the export"
present target && fail "--delete-local did not delete locally"
grep -q '"id": "target"' .beads/deletions.jsonl || fail "the ledger does not carry the deletion"
python3 -c 'import json; b=json.load(open(".beads/transport/baseline.json"))["records"]; assert "target" not in b and "keep-1" in b, b' \
  || fail "the verified baseline was not updated by the confirmed deletion"

echo "all deletion-propagation scenarios passed"
