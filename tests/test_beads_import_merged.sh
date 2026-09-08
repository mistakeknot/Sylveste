#!/usr/bin/env bash
# Tests for scripts/beads-import-merged.sh.
#
# The script exists to make the post-merge import cheap: a full `bd import` of
# .beads/issues.jsonl is ~49s and would run on every pull. It hands bd only the
# rows the merge changed.
#
# Cheap is easy to fake. A filter that imports NOTHING is faster still, and
# every timing check passes while another machine's work never lands — the
# invisible failure this entire path exists to prevent. So every scenario here
# asserts on what bd was actually given, never on whether the script succeeded.
#
# Scenarios 8-14 cover the recoverable half: an unknown before-commit is an
# explicit result rather than an unbounded import, a failed or unverified
# import leaves a pending batch with exact commit identities, a later pull that
# changes nothing still retries it, and a verified retry clears it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$SANDBOX/scripts" "$SANDBOX/.beads" "$SANDBOX/bin"
cp "$ROOT/scripts/beads-import-merged.sh" "$SANDBOX/scripts/"
cp "$ROOT/scripts/lib-beads-transport.sh" "$SANDBOX/scripts/"
cp "$ROOT/scripts/check_beads_jsonl_dolt_sync.py" "$SANDBOX/scripts/"
chmod +x "$SANDBOX/scripts/beads-import-merged.sh"

# Stub bd with a real, if tiny, database: $BD_STUB_DB is a JSONL file.
#   import  -> upserts rows into the database (strictly-newer wins, like bd)
#              and copies the batch to $IMPORTED_TO so scenarios can assert on
#              exactly what was handed over; BD_STUB_FAIL makes it exit 1 after
#              doing nothing, BD_STUB_LOSE makes it drop the named id silently
#              (exit 0), BD_STUB_HANG makes it sleep.
#   export  -> writes the database, so the post-import verification can look.
cat > "$SANDBOX/bin/bd" <<'STUB'
#!/usr/bin/env python3
import json, os, shutil, sys, time
argv = sys.argv[1:]
while argv and argv[0] in ("--readonly", "--sandbox"):
    argv = argv[1:]
if argv[:1] == ["-C"]:
    argv = argv[2:]
db = os.environ["BD_STUB_DB"]
def load():
    rows = {}
    if os.path.exists(db):
        for line in open(db):
            if line.strip():
                r = json.loads(line); rows[r["id"]] = r
    return rows
def save(rows):
    with open(db, "w") as fh:
        for r in rows.values(): fh.write(json.dumps(r) + "\n")
if argv[:1] == ["import"]:
    src = [a for a in argv[1:] if not a.startswith("--")][0]
    if os.environ.get("BD_STUB_HANG"):
        time.sleep(float(os.environ["BD_STUB_HANG"]))
    shutil.copyfile(src, os.environ["IMPORTED_TO"])
    if os.environ.get("BD_STUB_FAIL"):
        print(json.dumps({"error": "simulated: dolt server unreachable"})); sys.exit(1)
    rows = load(); created = updated = 0
    for line in open(src):
        if not line.strip(): continue
        r = json.loads(line)
        if r.get("id") == os.environ.get("BD_STUB_LOSE"):
            continue
        cur = rows.get(r["id"])
        if cur is None: rows[r["id"]] = r; created += 1
        elif r.get("updated_at", "") > cur.get("updated_at", ""): rows[r["id"]] = r; updated += 1
    save(rows)
    # Real bd pretty-prints the reply over many lines, with the bare "{" first.
    print(json.dumps({"created": created, "updated": updated, "skipped": 0,
                      "ids": [json.loads(l)["id"] for l in open(src) if l.strip()]}, indent=2))
elif argv[:1] == ["export"]:
    out = argv[argv.index("-o") + 1]
    shutil.copyfile(db, out) if os.path.exists(db) else open(out, "w").close()
elif argv[:1] == ["info"]:
    print("Database:", db); print("Mode: direct")
elif argv[:1] == ["context"]:
    print(json.dumps({"beads_dir": os.path.dirname(db), "project_id": "stub", "is_worktree": False}))
STUB
chmod +x "$SANDBOX/bin/bd"
export PATH="$SANDBOX/bin:$PATH"
export IMPORTED_TO="$SANDBOX/imported.jsonl"
export BD_STUB_DB="$SANDBOX/.beads/stub-db.jsonl"   # bound to this checkout's .beads/
export BEADS_TRANSPORT_LOCK_BASE="$SANDBOX/locks"; mkdir -p "$BEADS_TRANSPORT_LOCK_BASE"

cd "$SANDBOX"
git init -q .
git config user.email t@test; git config user.name tester

row() { printf '{"id":"%s","title":"t","updated_at":"%s"}\n' "$1" "$2"; }

{ row a 2026-07-01T00:00:00Z; row b 2026-07-01T00:00:00Z; } > .beads/issues.jsonl
cp .beads/issues.jsonl "$BD_STUB_DB"           # the database starts in step with the file
git add -A >/dev/null; git commit -q -m base
base="$(git rev-parse HEAD)"

imported_ids() { grep -o '"id":"[^"]*"' "$IMPORTED_TO" 2>/dev/null | sed 's/.*:"//;s/"//' | sort | tr '\n' ' '; }
reset_import() { rm -f "$IMPORTED_TO"; }
pending_field() { python3 -c 'import json,sys; print(json.load(open(".beads/transport/pending-import.json")).get(sys.argv[1]))' "$1"; }
status_field() { python3 -c 'import json,sys; print(json.load(open(".beads/transport/status.json"))["import"].get(sys.argv[1]))' "$1"; }

# ─── 1: only the added row is imported ────────────────────────────────
echo "=== 1: a merge that adds a row imports that row, and only it ==="
reset_import
{ row a 2026-07-01T00:00:00Z; row b 2026-07-01T00:00:00Z; row c 2026-08-01T00:00:00Z; } > .beads/issues.jsonl
git commit -q -m "add c" -- .beads/issues.jsonl
bash scripts/beads-import-merged.sh "$base" >/dev/null 2>&1 || fail "a verifiable import reported failure"
[ -f "$IMPORTED_TO" ] || fail "nothing was imported; another machine's bead would be invisible"
[ "$(imported_ids)" = "c " ] || fail "expected only 'c', got '$(imported_ids)'"
[ -f .beads/transport/pending-import.json ] && fail "a verified import left pending state behind"
[ "$(status_field result)" = "verified" ] || fail "status.json does not record the verified import"

# ─── 2: an untouched JSONL imports nothing at all ─────────────────────
echo "=== 2: a merge that does not touch bead state calls bd not at all ==="
reset_import
prev="$(git rev-parse HEAD)"
echo "unrelated" > README.md
git add README.md >/dev/null; git commit -q -m "unrelated change"
bash scripts/beads-import-merged.sh "$prev" >/dev/null 2>&1
[ -f "$IMPORTED_TO" ] && fail "imported on a merge that changed no bead state"

# ─── 3: a modified row imports the NEW text ───────────────────────────
echo "=== 3: an updated row is imported as its new version ==="
reset_import
prev="$(git rev-parse HEAD)"
{ row a 2026-07-01T00:00:00Z; row b 2026-09-09T00:00:00Z; row c 2026-08-01T00:00:00Z; } > .beads/issues.jsonl
git commit -q -m "update b" -- .beads/issues.jsonl
bash scripts/beads-import-merged.sh "$prev" >/dev/null 2>&1
[ "$(imported_ids)" = "b " ] || fail "expected only 'b', got '$(imported_ids)'"
grep -q '2026-09-09' "$IMPORTED_TO" || fail "imported the pre-merge text of the row, not the merged one"

# ─── 4: a removed row is not an import's business ─────────────────────
echo "=== 4: a row that only disappears imports nothing ==="
reset_import
prev="$(git rev-parse HEAD)"
{ row a 2026-07-01T00:00:00Z; row b 2026-09-09T00:00:00Z; } > .beads/issues.jsonl
git commit -q -m "drop c" -- .beads/issues.jsonl
bash scripts/beads-import-merged.sh "$prev" >/dev/null 2>&1 || fail "a deletion-only merge reported failure"
[ -f "$IMPORTED_TO" ] && fail "a deletion was fed to the importer; deletions travel through the ledger"

# ─── 5: an unknown before-ref is an explicit, recoverable result ──────
# It used to `exec bd import <whole file>`, unbounded. Slow was thought to beat
# wrong; on zklw slow meant a pull that never returned. The helper now says
# what it does not know and names the deliberate way to import everything.
echo "=== 5: an unresolvable before-ref imports nothing and says so ==="
reset_import
rc=0
out="$(bash scripts/beads-import-merged.sh "nosuchref-deadbeef" 2>&1 >/dev/null)" || rc=$?
[ "$rc" -eq 1 ] || fail "an unknown before-ref exited $rc, expected 1"
[ -f "$IMPORTED_TO" ] && fail "imported without knowing what changed"
case "$out" in *"INCOMPLETE"*"--full"*) ;; *) fail "the recovery command was not named; stderr: $out" ;; esac
[ "$(pending_field reason)" = "before_unresolvable" ] || fail "pending state does not record why"
[ "$(pending_field after)" = "$(git rev-parse HEAD)" ] || fail "pending state does not record the after-commit"

echo "=== 6: --full imports the whole file deliberately, bounded and verified ==="
# Rows the database already holds are verified agreement, not work for bd;
# only what is missing is handed over. Drop 'b' from the database first so
# --full has something real to do.
db_drop() { python3 -c 'import json,sys; p=sys.argv[1]; rows=[l for l in open(p) if l.strip() and json.loads(l)["id"]!=sys.argv[2]]; open(p,"w").write("".join(rows))' "$BD_STUB_DB" "$1"; }
db_set() { python3 -c 'import json,sys; p=sys.argv[1]; new=json.loads(sys.argv[2]); rows=[json.loads(l) for l in open(p) if l.strip()]; rows=[r for r in rows if r["id"]!=new["id"]]+[new]; open(p,"w").write("".join(json.dumps(r)+"\n" for r in rows))' "$BD_STUB_DB" "$1"; }
db_has() { python3 -c 'import json,sys; rows={json.loads(l)["id"]:json.loads(l) for l in open(sys.argv[1]) if l.strip()}; r=rows.get(sys.argv[2]); sys.exit(0 if r and (len(sys.argv)<4 or r.get("title")==sys.argv[3]) else 1)' "$BD_STUB_DB" "$@"; }
db_drop b
bash scripts/beads-import-merged.sh --full >/dev/null 2>&1 || fail "--full failed on a consistent file"
[ "$(imported_ids)" = "b " ] || fail "expected only the missing row 'b', got '$(imported_ids)'"
db_has b || fail "--full did not restore the missing row"
[ -f .beads/transport/pending-import.json ] && fail "--full did not clear the pending state"
python3 -c 'import json,sys; b=json.load(open(".beads/transport/baseline.json"))["records"]; assert set(b) >= {"a","b"}, b' \
  || fail "a verified import did not establish the per-record baseline"

# ─── 7: the file header is never mistaken for a row ───────────────────
echo "=== 7: the diff's '+++ b/...' header is not imported as a bead ==="
grep -q '^+++' "$IMPORTED_TO" 2>/dev/null && fail "a diff header leaked into the import batch"

# ─── 8: a hung import is bounded, and says so ─────────────────────────
echo "=== 8: an import that hangs is timed out, loudly, and left pending ==="
reset_import
prev="$(git rev-parse HEAD)"
{ row a 2026-07-01T00:00:00Z; row b 2026-09-09T00:00:00Z; row d 2026-10-01T00:00:00Z; } > .beads/issues.jsonl
git commit -q -m "add d" -- .beads/issues.jsonl
rc=0
out="$(BD_STUB_HANG=8 BEADS_IMPORT_TIMEOUT=1 bash scripts/beads-import-merged.sh "$prev" 2>&1 >/dev/null)" || rc=$?
case "$out" in
  *"timed out"*) ;;
  *) fail "a hung import was silent; the database is behind and nothing said so" ;;
esac
case "$out" in
  *"beads-import-merged.sh --retry"*) ;;
  *) fail "the timeout message does not name the command that fixes it" ;;
esac
[ "$rc" -eq 1 ] || fail "a timed-out import exited $rc, expected 1 so the hook can report it"
[ "$(pending_field reason)" = "timeout" ] || fail "the timeout was not recorded as pending"
[ "$(pending_field before)" = "$prev" ] || fail "pending state lost the before-commit"
grep -q '"id":"d"' .beads/transport/pending-import.jsonl || fail "the pending batch does not hold the stranded row"

# ─── 9: an unchanged pull still retries the pending batch ─────────────
echo "=== 9: a later pull that changes nothing does not strand the pending batch ==="
reset_import
prev="$(git rev-parse HEAD)"
echo "more" >> README.md; git add README.md >/dev/null; git commit -q -m "unrelated again"
bash scripts/beads-import-merged.sh "$prev" >/dev/null 2>&1 || fail "the retry on an unchanged pull failed"
[ "$(imported_ids)" = "d " ] || fail "the stranded row was not retried on an unchanged pull; got '$(imported_ids)'"
[ -f .beads/transport/pending-import.json ] && fail "a verified retry did not clear the pending state"

# ─── 10: bd exiting 0 is not success; the rows must be there ──────────
echo "=== 10: an import bd reports as done but did not apply stays pending ==="
reset_import
prev="$(git rev-parse HEAD)"
{ row a 2026-07-01T00:00:00Z; row b 2026-09-09T00:00:00Z; row d 2026-10-01T00:00:00Z; row e 2026-10-02T00:00:00Z; } > .beads/issues.jsonl
git commit -q -m "add e" -- .beads/issues.jsonl
rc=0
out="$(BD_STUB_LOSE=e bash scripts/beads-import-merged.sh "$prev" 2>&1 >/dev/null)" || rc=$?
[ "$rc" -eq 1 ] || fail "an unverified import exited $rc, expected 1"
case "$out" in *"not in the database afterwards"*"e"*) ;; *) fail "the unapplied row was not named; stderr: $out" ;; esac
[ "$(pending_field reason)" = "unverified" ] || fail "verification failure was not recorded"

echo "=== 11: --retry is idempotent and clears the batch once it verifies ==="
reset_import
bash scripts/beads-import-merged.sh --retry >/dev/null 2>&1 || fail "--retry failed once bd behaved"
[ "$(imported_ids)" = "e " ] || fail "the retry handed over the wrong batch: '$(imported_ids)'"
[ -f .beads/transport/pending-import.json ] && fail "the verified retry left pending state"
bash scripts/beads-import-merged.sh --retry >/dev/null 2>&1 || fail "a second --retry with nothing pending failed"

# ─── 12: a failed bd import is reported with its error ────────────────
echo "=== 12: a failing bd import is pending with bd's own error ==="
reset_import
prev="$(git rev-parse HEAD)"
{ row a 2026-07-01T00:00:00Z; row b 2026-09-09T00:00:00Z; row d 2026-10-01T00:00:00Z; row e 2026-10-02T00:00:00Z; row f 2026-10-03T00:00:00Z; } > .beads/issues.jsonl
git commit -q -m "add f" -- .beads/issues.jsonl
rc=0
out="$(BD_STUB_FAIL=1 bash scripts/beads-import-merged.sh "$prev" 2>&1 >/dev/null)" || rc=$?
[ "$rc" -eq 1 ] || fail "a failed import exited $rc"
case "$out" in *"dolt server unreachable"*) ;; *) fail "bd's error was hidden; stderr: $out" ;; esac
[ "$(pending_field attempts)" = "1" ] || fail "attempt count wrong: $(pending_field attempts)"
rc=0; BD_STUB_FAIL=1 bash scripts/beads-import-merged.sh --retry >/dev/null 2>&1 || rc=$?
[ "$(pending_field attempts)" = "2" ] || fail "retries are not counted: $(pending_field attempts)"
bash scripts/beads-import-merged.sh --retry >/dev/null 2>&1 || fail "recovery retry failed"
[ "$(imported_ids)" = "f " ] || fail "recovery retry handed over '$(imported_ids)'"

# ─── 13: an unparseable diff row fails before bd sees it ──────────────
echo "=== 13: a corrupt row in the merge is refused, not handed to bd ==="
reset_import
prev="$(git rev-parse HEAD)"
{ cat .beads/issues.jsonl; printf '{"id":"g","title":"unterminated\n'; } > .beads/issues.jsonl.new
mv .beads/issues.jsonl.new .beads/issues.jsonl
git commit -q -m "corrupt g" -- .beads/issues.jsonl
rc=0
out="$(bash scripts/beads-import-merged.sh "$prev" 2>&1 >/dev/null)" || rc=$?
[ "$rc" -eq 1 ] || fail "a corrupt batch exited $rc"
[ -f "$IMPORTED_TO" ] && fail "a corrupt batch was handed to bd"
[ "$(pending_field reason)" = "batch_unparseable" ] || fail "the parse failure was not recorded"
# Repair upstream: the next merge fixes the row, and the pending range covers it.
{ row a 2026-07-01T00:00:00Z; row b 2026-09-09T00:00:00Z; row d 2026-10-01T00:00:00Z; row e 2026-10-02T00:00:00Z; row f 2026-10-03T00:00:00Z; row g 2026-10-04T00:00:00Z; } > .beads/issues.jsonl
git commit -q -m "fix g" -- .beads/issues.jsonl
bash scripts/beads-import-merged.sh "$(git rev-parse HEAD~1)" >/dev/null 2>&1 || fail "the repaired merge did not import"
[ "$(imported_ids)" = "g " ] || fail "expected the repaired row, got '$(imported_ids)'"
[ -f .beads/transport/pending-import.json ] && fail "pending state survived a verified import"

# ─── 14: --status is honest ───────────────────────────────────────────
echo "=== 14: --status reports pending state and exits non-zero while it exists ==="
bash scripts/beads-import-merged.sh --status >/dev/null || fail "--status exited non-zero with nothing pending"
db_drop g
rc=0; BD_STUB_FAIL=1 bash scripts/beads-import-merged.sh --full >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "fixture: expected a failed --full"
rc=0; bash scripts/beads-import-merged.sh --status >/dev/null || rc=$?
[ "$rc" -eq 1 ] || fail "--status exited $rc with a pending import"
bash scripts/beads-import-merged.sh --full >/dev/null 2>&1 || fail "recovery --full failed"

# ─── 15: an incoming row never overwrites an independent local change ─
# bd's guard keeps a local row against an OLDER incoming one. It does not keep
# it against a NEWER one — that is overwritten, and nothing afterwards can
# undo it. Classification before bd is what protects it.
echo "=== 15: a newer incoming row for a locally modified bead is held back, not imported ==="
reset_import
prev="$(git rev-parse HEAD)"
# Local work on 'a' since the last verified state (a is baselined from scenario 6).
db_set '{"id":"a","title":"edited locally","updated_at":"2026-11-01T00:00:00Z"}'
# The other host also edited 'a', later, and a pull brings it.
python3 - <<'PY'
import json
rows = [json.loads(l) for l in open(".beads/issues.jsonl") if l.strip()]
for r in rows:
    if r["id"] == "a":
        r.update(title="edited on zklw", updated_at="2026-12-01T00:00:00Z")
rows.append({"id": "h", "title": "t", "updated_at": "2026-12-01T00:00:00Z"})
open(".beads/issues.jsonl", "w").write("".join(json.dumps(r, separators=(",", ":")) + "\n" for r in rows))
PY
git commit -q -m "zklw edited a, added h" -- .beads/issues.jsonl
rc=0
out="$(bash scripts/beads-import-merged.sh "$prev" 2>&1 >/dev/null)" || rc=$?
[ "$rc" -eq 1 ] || fail "an import with a held-back conflict exited $rc, expected 1"
db_has a "edited locally" || fail "the independent local edit was overwritten by the newer incoming row"
[ "$(imported_ids)" = "h " ] || fail "expected only the unambiguous row 'h' to reach bd, got '$(imported_ids)'"
db_has h || fail "the unambiguous row did not land while a conflict was held back"
case "$out" in *"changed on both hosts"*" a"*) ;; *) fail "the held-back row was not named; stderr: $out" ;; esac
python3 -c 'import json,sys; c=json.load(open(".beads/transport/conflicts.json"))["records"]; assert "a" in c and c["a"]["reason"]=="local_changed_since_verified", c' \
  || fail "the conflict was not recorded in conflicts.json"
ev="$(ls -d .beads/transport/evidence/*/ | tail -1)"
grep -q "edited on zklw" "$ev/a.incoming.json" && grep -q "edited locally" "$ev/a.database.json" \
  || fail "both versions of the held-back row were not preserved under $ev"
[ -f .beads/transport/pending-import.json ] && fail "a conflict is not a pending batch; a retry cannot resolve it"

echo "=== 16: a local row unchanged since the pre-merge transport is imported ==="
# 'b' has no local edit: it still matches what the transport said before the
# merge, so the incoming change is one-sided — even with no baseline entry.
reset_import
prev="$(git rev-parse HEAD)"
python3 -c 'import json; p=".beads/transport/baseline.json"; s=json.load(open(p)); s["records"].pop("b", None); json.dump(s, open(p,"w"))'
python3 - <<'PY'
import json
rows = [json.loads(l) for l in open(".beads/issues.jsonl") if l.strip()]
for r in rows:
    if r["id"] == "b":
        r.update(title="b edited on zklw", updated_at="2026-12-02T00:00:00Z")
open(".beads/issues.jsonl", "w").write("".join(json.dumps(r, separators=(",", ":")) + "\n" for r in rows))
PY
git commit -q -m "zklw edited b" -- .beads/issues.jsonl
bash scripts/beads-import-merged.sh "$prev" >/dev/null 2>&1 || fail "a one-sided incoming edit reported failure"
db_has b "b edited on zklw" || fail "a one-sided incoming edit was not applied"
python3 -c 'import json; b=json.load(open(".beads/transport/baseline.json"))["records"]; assert "b" in b' \
  || fail "the applied row was not added to the verified baseline"

# ─── 17: every added line counts, not only those starting with '{' ───
echo "=== 17: a valid row with leading whitespace is imported ==="
reset_import
prev="$(git rev-parse HEAD)"
printf '   {"id":"ws","title":"t","updated_at":"2026-12-03T00:00:00Z"}\n' >> .beads/issues.jsonl
git commit -q -m "add ws with leading whitespace" -- .beads/issues.jsonl
bash scripts/beads-import-merged.sh "$prev" >/dev/null 2>&1 || fail "a whitespace-led row failed the import"
[ "$(imported_ids)" = "ws " ] || fail "a valid row with leading whitespace was dropped from the batch: '$(imported_ids)'"
db_has ws || fail "the whitespace-led row did not land"

echo "=== 18: a merge whose only addition is not JSON is incomplete, never verified ==="
# If the only added line is malformed and the batch were built from '^+{'
# lines alone, the batch would be empty, the import "verified", and the hook
# would go on to apply the deletion ledger after an import that never happened.
reset_import
prev="$(git rev-parse HEAD)"
printf 'not-json at all\n' >> .beads/issues.jsonl
git commit -q -m "corrupt addition" -- .beads/issues.jsonl
rc=0
out="$(bash scripts/beads-import-merged.sh "$prev" 2>&1 >/dev/null)" || rc=$?
[ "$rc" -eq 1 ] || fail "a malformed-only addition exited $rc, expected 1 (incomplete)"
[ -f "$IMPORTED_TO" ] && fail "a malformed batch reached bd"
[ "$(pending_field reason)" = "batch_unparseable" ] || fail "the malformed addition was not recorded: $(pending_field reason)"
case "$out" in *"INCOMPLETE"*) ;; *) fail "the malformed addition was silent; stderr: $out" ;; esac
# Repair upstream and confirm the deletion-only shape is still a clean no-op.
before_ids="$(grep -o '"id":"[^"]*"' .beads/issues.jsonl | sort | tr '\n' ' ')"
python3 - <<'PY'
p = ".beads/issues.jsonl"
lines = open(p, encoding="utf-8").read().splitlines(keepends=True)   # read fully before truncating
open(p, "w", encoding="utf-8").write("".join(l for l in lines if l.strip().startswith("{")))
PY
[ "$(grep -o '"id":"[^"]*"' .beads/issues.jsonl | sort | tr '\n' ' ')" = "$before_ids" ] \
  || fail "the repair dropped valid records, so the deletion-only case below would be vacuous"
grep -q 'not-json' .beads/issues.jsonl && fail "the repair did not remove the corrupt line"
git commit -q -m "remove corrupt line" -- .beads/issues.jsonl
bash scripts/beads-import-merged.sh "$(git rev-parse HEAD~1)" >/dev/null 2>&1 || fail "a deletion-only repair reported failure"
[ -f "$IMPORTED_TO" ] && fail "a deletion-only diff was fed to bd"
[ -f .beads/transport/pending-import.json ] && fail "pending state survived the repair"

# ─── 19: startup that cannot import is explicit ──────────────────────
# A tracked transport with no bd used to exit 0, which the hook read as
# "nothing to import" — and then applied the deletion ledger.
echo "=== 19: a tracked transport with no bd on PATH is an explicit failure, not a quiet success ==="
# A PATH with every tool the script needs except bd (the host may have a real
# bd in /usr/local/bin, so a plain PATH edit is not enough).
mkdir -p "$SANDBOX/nobin"
python3 - "$SANDBOX/nobin" "$SANDBOX/bin" <<'PY'
import os, shutil, sys
dest, exclude = sys.argv[1:3]
os.environ["PATH"] = ":".join(p for p in os.environ["PATH"].split(":") if p != exclude)
for tool in ("bash", "git", "python3", "sed", "grep", "head", "tail", "cat", "mktemp", "date", "hostname",
             "dirname", "basename", "awk", "cut", "sort", "tr", "mv", "cp", "rm", "chmod", "wc", "shasum", "env", "uname"):
    src = shutil.which(tool)
    if src and not os.path.exists(os.path.join(dest, tool)):
        os.symlink(src, os.path.join(dest, tool))
PY
rc=0
out="$(PATH="$SANDBOX/nobin" bash scripts/beads-import-merged.sh 2>&1 >/dev/null)" || rc=$?
[ "$rc" -eq 1 ] || fail "missing bd exited $rc, expected 1: $out"
case "$out" in *"bd is not on PATH"*) ;; *) fail "missing bd was not named: $out" ;; esac
# A cloud session is the one legitimate quiet skip, and it says so.
rc=0
out="$(IS_SANDBOX=yes PATH="$SANDBOX/nobin" bash scripts/beads-import-merged.sh 2>&1 >/dev/null)" || rc=$?
[ "$rc" -eq 0 ] || fail "a cloud session exited $rc"
case "$out" in *"cloud session"*) ;; *) fail "the cloud skip was silent: $out" ;; esac
# Missing helper library: explicit.
mv scripts/lib-beads-transport.sh scripts/lib-beads-transport.sh.away
rc=0; out="$(bash scripts/beads-import-merged.sh 2>&1 >/dev/null)" || rc=$?
mv scripts/lib-beads-transport.sh.away scripts/lib-beads-transport.sh
[ "$rc" -eq 1 ] || fail "a missing helper library exited $rc"
case "$out" in *"lib-beads-transport.sh is missing"*) ;; *) fail "the missing library was not named: $out" ;; esac

# ─── 20: durable state that cannot be written keeps the import incomplete ─
echo "=== 20: a state directory that cannot be written leaves the batch pending with its evidence ==="
reset_import
prev="$(git rev-parse HEAD)"
{ cat .beads/issues.jsonl; row z 2026-12-09T00:00:00Z; } > .beads/issues.jsonl.new; mv .beads/issues.jsonl.new .beads/issues.jsonl
git commit -q -m "add z" -- .beads/issues.jsonl
# (a) the whole state directory is unwritable: no evidence can be kept, so
#     nothing proceeds and the message says exactly that.
chmod 500 .beads/transport
rc=0
out="$(bash scripts/beads-import-merged.sh "$prev" 2>&1 >/dev/null)" || rc=$?
chmod 700 .beads/transport
[ "$rc" -eq 1 ] || fail "an unwritable state directory exited $rc, expected 1"
case "$out" in *"INCOMPLETE"*"could not be written"*) ;; *) fail "the state failure was not reported: $out" ;; esac
[ -f "$IMPORTED_TO" ] && fail "rows were handed to bd although provenance could not be recorded"
# (b) pending state is writable but the baseline cannot be promoted (the file
#     is a directory): the batch stays pending with its evidence, bd is not
#     called, and the message names the state.
mkdir .beads/transport/baseline.json.blocker && mv .beads/transport/baseline.json .beads/transport/baseline.json.saved && mv .beads/transport/baseline.json.blocker .beads/transport/baseline.json
rc=0
out="$(bash scripts/beads-import-merged.sh "$prev" 2>&1 >/dev/null)" || rc=$?
[ "$rc" -eq 1 ] || fail "a failed state promotion exited $rc, expected 1"
case "$out" in *"INCOMPLETE"*"could not be written"*) ;; *) fail "the promotion failure was not reported: $out" ;; esac
[ -f "$IMPORTED_TO" ] && fail "rows were handed to bd although the verified state could not be recorded"
[ "$(pending_field reason)" = "state_not_writable" ] || fail "pending state does not record the cause: $(pending_field reason)"
[ "$(pending_field before)" = "$prev" ] || fail "pending state lost the before-commit"
grep -q '"id":"z"' .beads/transport/pending-import.jsonl || fail "the pending batch does not hold the stranded row"
rmdir .beads/transport/baseline.json && mv .beads/transport/baseline.json.saved .beads/transport/baseline.json
# Recovery: once the state is writable again, --retry lands the row.
bash scripts/beads-import-merged.sh --retry >/dev/null 2>&1 || fail "the retry after restoring the state directory failed"
db_has z || fail "the row did not land on retry"
[ -f .beads/transport/pending-import.json ] && fail "pending state survived a verified retry"
python3 -c 'import json; b=json.load(open(".beads/transport/baseline.json"))["records"]; assert "z" in b' || fail "z was not baselined after the retry"

# ─── 21: a held lock or an unverified identity never touches shared pending state ─
# The holder's pending-import.json/jsonl belong to the import that is running.
# A second invocation that cannot take the lock, or cannot identify its
# database, must say so and exit 1 without replacing them.
echo "=== 21: a held lock leaves the holder's pending state byte-identical ==="
reset_import
prev="$(git rev-parse HEAD)"
{ cat .beads/issues.jsonl; row y 2026-12-10T00:00:00Z; } > .beads/issues.jsonl.new; mv .beads/issues.jsonl.new .beads/issues.jsonl
git commit -q -m "add y" -- .beads/issues.jsonl
printf '{"before":"%s","after":"HOLDER","reason":"in_progress","rows":1,"attempts":0}\n' "$prev" > .beads/transport/pending-import.json
printf '{"id":"holder-row"}\n' > .beads/transport/pending-import.jsonl
pending_sha="$(shasum .beads/transport/pending-import.json .beads/transport/pending-import.jsonl)"
rm -f h.inside h.leave
bash -c '. scripts/lib-beads-transport.sh; beads_transport_lock 20 || exit 1; : > h.inside; while [ ! -f h.leave ]; do sleep 0.05; done; beads_transport_unlock' &
holder=$!
while [ ! -f h.inside ]; do sleep 0.05; done
rc=0
out="$(BEADS_TRANSPORT_LOCK_WAIT=1 bash scripts/beads-import-merged.sh "$prev" 2>&1 >/dev/null)" || rc=$?
: > h.leave; wait "$holder"
[ "$rc" -eq 1 ] || fail "a held lock exited $rc, expected 1"
case "$out" in *"NOT attempted"*"holds the lock"*) ;; *) fail "the held lock was not reported: $out" ;; esac
[ "$(shasum .beads/transport/pending-import.json .beads/transport/pending-import.jsonl)" = "$pending_sha" ] \
  || fail "the holder's pending state was replaced by a process that did not hold the lock"
grep -q "IMPORT NOT ATTEMPTED (lock_held)" .beads/transport/log || fail "no append-only evidence of the deferral"
python3 -c 'import json; d=json.load(open(".beads/transport/status.json")); assert d["import_not_attempted"]["reason"]=="lock_held", d' \
  || fail "status.json does not carry the deferral under its own key"
[ -f "$IMPORTED_TO" ] && fail "bd import ran without the lock"

echo "=== 22: an unverified database identity leaves pending state untouched too ==="
mkdir -p "$SANDBOX/foreign/.beads"
rc=0
out="$(BD_STUB_DB="$SANDBOX/foreign/.beads/db.jsonl" bash scripts/beads-import-merged.sh "$prev" 2>&1 >/dev/null)" || rc=$?
[ "$rc" -eq 1 ] || fail "a foreign database exited $rc, expected 1"
case "$out" in *"NOT attempted"*"different database"*) ;; *) fail "the identity failure was not reported: $out" ;; esac
[ "$(shasum .beads/transport/pending-import.json .beads/transport/pending-import.jsonl)" = "$pending_sha" ] \
  || fail "an identity failure replaced the pending state"
[ -f "$IMPORTED_TO" ] && fail "bd import ran against an unverified database"
# Recovery is the holder's business: its range still lands the row.
bash scripts/beads-import-merged.sh --retry >/dev/null 2>&1 || fail "the retry after the deferral failed"
db_has y || fail "the row did not land once the lock was free"


# ─── 23: a verdict that cannot be recorded does not clear the batch ───
# The rows bd applied stay applied (progress), the pending batch stays
# (evidence), and the exit status keeps the hook from running the ledger.
echo "=== 23: an unwritable status record keeps the verified import pending ==="
reset_import
prev="$(git rev-parse HEAD)"
{ cat .beads/issues.jsonl; row w 2026-12-11T00:00:00Z; } > .beads/issues.jsonl.new; mv .beads/issues.jsonl.new .beads/issues.jsonl
git commit -q -m "add w" -- .beads/issues.jsonl
mkdir -p .beads/transport/status.d; chmod 500 .beads/transport/status.d
rc=0; out="$(bash scripts/beads-import-merged.sh "$prev" 2>&1 >/dev/null)" || rc=$?
chmod 700 .beads/transport/status.d
[ "$rc" -eq 1 ] || fail "an unrecordable verdict exited $rc, expected 1"
case "$out" in *"could NOT be recorded"*) ;; *) fail "the status failure was swallowed: $out" ;; esac
db_has w || fail "the applied row was lost"
[ -f .beads/transport/pending-import.json ] || fail "the pending batch was cleared although the verdict was not recorded"
bash scripts/beads-import-merged.sh --retry >/dev/null 2>&1 || fail "the retry after restoring status.d failed"
[ -f .beads/transport/pending-import.json ] && fail "pending state survived a recorded verdict"
python3 -c 'import json; d=json.load(open(".beads/transport/status.d/import.json")); assert d["result"]=="verified", d' || fail "the verdict was not recorded on retry"
# The public view carries the same key.
python3 -c 'import json; d=json.load(open(".beads/transport/status.json")); assert d["import"]["result"]=="verified", d' || fail "status.json view not rebuilt"


# ─── 24: git provenance — exported edits on both hosts are a conflict ─
# Local edits K and EXPORTS it (a commit on main). The peer edits K too, with
# a later timestamp, plus an unrelated row U. The merge conflicts on K's line;
# the documented path takes the incoming side and commits by hand, then calls
# the helper with ORIG_HEAD. Local == before == baseline for K, so the
# local-state rule alone would import it and bd would apply the newer row.
echo "=== 24: a record edited on both hosts since the merge base is held back, whatever the timestamps say ==="
reset_import
rm -f .beads/transport/conflicts.json
base="$(git rev-parse HEAD)"
db_set '{"id":"k","title":"edited here","updated_at":"2027-01-01T00:00:00Z"}'
python3 - <<'PY2'
import json
p = ".beads/issues.jsonl"
rows = [json.loads(l) for l in open(p) if l.strip()]
rows = [r for r in rows if r["id"] != "k"] + [{"id": "k", "title": "edited here", "updated_at": "2027-01-01T00:00:00Z"}]
open(p, "w").write("".join(json.dumps(r, separators=(",", ":")) + "\n" for r in rows))
PY2
git commit -q -m "local export of k" -- .beads/issues.jsonl
git checkout -q -b peer "$base"
python3 - <<'PY2'
import json
p = ".beads/issues.jsonl"
rows = [json.loads(l) for l in open(p) if l.strip()]
rows = [r for r in rows if r["id"] != "k"] + [{"id": "k", "title": "edited on the peer", "updated_at": "2027-02-01T00:00:00Z"},
                                             {"id": "u", "title": "unrelated", "updated_at": "2027-02-01T00:00:00Z"}]
open(p, "w").write("".join(json.dumps(r, separators=(",", ":")) + "\n" for r in rows))
PY2
git commit -q -m "peer export" -- .beads/issues.jsonl
git checkout -q main
git merge --no-commit peer >/dev/null 2>&1 && fail "fixture: the merge was expected to conflict"
git checkout --theirs -- .beads/issues.jsonl && git add .beads/issues.jsonl && git commit -q --no-edit
# First attempt: bd fails, so the batch goes pending WITH its ancestry.
rc=0; BD_STUB_FAIL=1 bash scripts/beads-import-merged.sh ORIG_HEAD >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "fixture: expected the failed first attempt to exit 1"
[ "$(python3 -c 'import json; print(json.load(open(".beads/transport/pending-import.json"))["ancestry"]["kind"])')" = "merge" ] \
  || fail "the pending record does not carry the merge ancestry"
[ "$(python3 -c 'import json; print(json.load(open(".beads/transport/pending-import.json"))["ancestry"]["sides"][0]["base"])')" = "$base" ] \
  || fail "the pending record's merge base is wrong"
# The retry uses that recorded provenance: K conflicts, U applies.
rc=0; out="$(bash scripts/beads-import-merged.sh --retry 2>&1 >/dev/null)" || rc=$?
[ "$rc" -eq 1 ] || fail "a retry with a both-sides conflict exited $rc, expected 1: $out"
db_has k "edited here" || fail "the exported local edit was overwritten by the newer incoming row"
db_has u "unrelated" || fail "the unrelated one-sided row did not land"
case "$out" in *"changed on both hosts"*" k"*) ;; *) fail "the conflict was not reported by id: $out" ;; esac
python3 -c 'import json; c=json.load(open(".beads/transport/conflicts.json"))["records"]["k"]; assert c["reason"]=="both_changed_since_merge_base", c' \
  || fail "conflicts.json does not carry the merge-base reason"
ev="$(python3 -c 'import json; print(json.load(open(".beads/transport/conflicts.json"))["records"]["k"]["evidence"])')"
# k did not exist at the merge base (both hosts created it), so there is no base version to keep.
for side in incoming database before theirs; do [ -f "$ev/k.$side.json" ] || fail "evidence lacks the $side version"; done
[ -f "$ev/k.base.json" ] && fail "a base version was fabricated for a record absent at the merge base"
grep -q '"edited on the peer"' "$ev/k.theirs.json" && grep -q '"edited here"' "$ev/k.database.json" || fail "evidence versions are wrong"
[ -f .beads/transport/pending-import.json ] && fail "a conflict is not a pending batch"
# Repeated retries keep the conflict and choose nothing.
rc=0; out="$(bash scripts/beads-import-merged.sh --retry 2>&1 >/dev/null)" || rc=$?
[ "$rc" -eq 1 ] || fail "a second retry with an open conflict exited $rc"
case "$out" in *"remain unresolved"*" k"*|*"remain unresolved"*"k"*) ;; *) fail "the open conflict was not restated on retry: $out" ;; esac
db_has k "edited here" || fail "a retry chose a side"

echo "=== 25: a fast-forward pull of a one-sided change applies it ==="
reset_import
rm -f .beads/transport/conflicts.json
base="$(git rev-parse HEAD)"
git checkout -q -b peer2 "$base"
python3 - <<'PY2'
import json
p = ".beads/issues.jsonl"
rows = [json.loads(l) for l in open(p) if l.strip()]
rows = [r for r in rows if r["id"] != "u"] + [{"id": "u", "title": "unrelated, edited on the peer only", "updated_at": "2027-03-01T00:00:00Z"}]
open(p, "w").write("".join(json.dumps(r, separators=(",", ":")) + "\n" for r in rows))
PY2
git commit -q -m "peer2 export" -- .beads/issues.jsonl
git checkout -q main && git merge -q --ff-only peer2
bash scripts/beads-import-merged.sh ORIG_HEAD >/dev/null 2>&1 || fail "a fast-forward one-sided change reported failure"
db_has u "unrelated, edited on the peer only" || fail "the one-sided change was not applied"
[ "$(python3 -c 'import json; print(json.load(open(".beads/transport/status.d/import.json"))["detail"]["ancestry"]["kind"])')" = "ff" ] \
  || fail "the verdict does not record fast-forward ancestry"

echo "=== 26: ancestry git cannot establish is reported, never invented ==="
reset_import
prev="$(git rev-parse HEAD)"
git checkout -q -b elsewhere "$base"
echo other > OTHER.md; git add OTHER.md; git commit -q -m "unrelated elsewhere"
git checkout -q main
# A before-commit that is not an ancestor of HEAD (the shape of a rebase/reset).
rc=0; out="$(bash scripts/beads-import-merged.sh elsewhere 2>&1 >/dev/null)" || rc=$?
[ "$rc" -eq 1 ] || fail "ambiguous ancestry exited $rc, expected 1"
case "$out" in *"INCOMPLETE"*"not an ancestor"*"--full"*) ;; *) fail "ambiguous ancestry was not reported with the --full way out: $out" ;; esac
[ "$(pending_field reason)" = "ancestry_unknown" ] || fail "pending reason: $(pending_field reason)"
rm -f .beads/transport/pending-import.json .beads/transport/pending-import.jsonl
[ "$(git rev-parse HEAD)" = "$prev" ] || fail "fixture: HEAD moved"

echo "=== 27: a zero-row pass whose verdict cannot be recorded is truthful about having nothing to retry ==="
reset_import
prev="$(git rev-parse HEAD)"
# A deletion-only change: the file moved, the batch has zero rows to import.
grep -q '"id":"ws"' .beads/issues.jsonl || fail "fixture: expected row ws to exist"
python3 -c 'p=".beads/issues.jsonl"; rows=[l for l in open(p) if l.strip() and "\"id\":\"ws\"" not in l]; open(p,"w").write("".join(rows))'
git commit -q -m "drop ws (deletion-only)" -- .beads/issues.jsonl
chmod 500 .beads/transport/status.d
rc=0; out="$(bash scripts/beads-import-merged.sh "$prev" 2>&1 >/dev/null)" || rc=$?
chmod 700 .beads/transport/status.d
[ "$rc" -eq 1 ] || fail "an unrecordable zero-row verdict exited $rc"
case "$out" in *"No batch is pending"*"re-run"*"$prev"*) ;; *) fail "the zero-row failure did not name the truthful re-run: $out" ;; esac
case "$out" in *"--retry"*) fail "the zero-row failure still points at --retry with nothing pending" ;; esac
[ -f .beads/transport/pending-import.json ] && fail "a zero-row pass created pending state"
bash scripts/beads-import-merged.sh "$prev" >/dev/null 2>&1 || fail "the named re-run failed once status.d was writable"

echo "=== 28: an unresolvable pending before-commit leaves the original record byte-identical ==="
reset_import
printf '{"before":"0000000000000000000000000000000000000000","after":"%s","reason":"in_progress","rows":7,"attempts":2,"ancestry":{"kind":"merge","base":null,"theirs":null}}\n' "$(git rev-parse HEAD)" > .beads/transport/pending-import.json
printf '{"id":"ghost"}\n' > .beads/transport/pending-import.jsonl
sha_before="$(shasum .beads/transport/pending-import.json .beads/transport/pending-import.jsonl)"
rc=0; out="$(bash scripts/beads-import-merged.sh --retry 2>&1 >/dev/null)" || rc=$?
[ "$rc" -eq 1 ] || fail "an unresolvable pending before exited $rc"
[ "$(shasum .beads/transport/pending-import.json .beads/transport/pending-import.jsonl)" = "$sha_before" ] \
  || fail "the original pending record was overwritten"
case "$out" in *"no longer resolves"*"left as it is"*) ;; *) fail "the unresolvable before was not reported truthfully: $out" ;; esac
python3 -c 'import json; d=json.load(open(".beads/transport/status.d/import.json")); assert d["reason"]=="pending_before_unknown" and d["rows"]==7, d' \
  || fail "the status record does not preserve the original row count"
rm -f .beads/transport/pending-import.json .beads/transport/pending-import.jsonl


# ─── 29-31: the provenance guardrail ──────────────────────────────────
echo "=== 29: a fast-forward across an unrelated upstream merge, then more commits, applies a one-sided row ==="
# The rollout shape: origin advanced by dependency-PR merges touching only
# workflow files, plus a later export. None of those merges diverged from us.
reset_import
rm -f .beads/transport/conflicts.json
base="$(git rev-parse HEAD)"
git checkout -q -b upstream "$base"
git checkout -q -b dep "$base"; mkdir -p .github/workflows; echo v2 > .github/workflows/ci.yml; git add .github; git commit -q -m "dep bump"
git checkout -q upstream; git merge -q --no-ff -m "Merge pull request #1 from dep" dep
python3 - <<'PY2'
import json
p = ".beads/issues.jsonl"
rows = [json.loads(l) for l in open(p) if l.strip()]
rows = [r for r in rows if r["id"] != "u"] + [{"id": "u", "title": "edited upstream after the dep merge", "updated_at": "2027-04-01T00:00:00Z"}]
open(p, "w").write("".join(json.dumps(r, separators=(",", ":")) + "\n" for r in rows))
PY2
git commit -q -m "upstream export" -- .beads/issues.jsonl
git checkout -q main && git merge -q --ff-only upstream
rc=0; out="$(bash scripts/beads-import-merged.sh "$base" 2>&1 >/dev/null)" || rc=$?
[ "$rc" -eq 0 ] || fail "a fast-forward across an unrelated merge was refused: $out"
db_has u "edited upstream after the dep merge" || fail "the one-sided row did not land across the unrelated merge"
python3 -c 'import json; d=json.load(open(".beads/transport/status.d/import.json"))["detail"]; assert d["conflicts"]==0 and d["ancestry"]["kind"]=="merge" and len(d["ancestry"]["merges"])==1, d' \
  || fail "the unrelated upstream merge was not inspected harmlessly"

echo "=== 30: a divergent Beads merge that is not the tip still flags the record; later unrelated rows apply ==="
reset_import
base="$(git rev-parse HEAD)"
db_set '{"id":"k","title":"edited here again","updated_at":"2027-05-01T00:00:00Z"}'
python3 - <<'PY2'
import json
p = ".beads/issues.jsonl"
rows = [json.loads(l) for l in open(p) if l.strip()]
rows = [r for r in rows if r["id"] != "k"] + [{"id": "k", "title": "edited here again", "updated_at": "2027-05-01T00:00:00Z"}]
open(p, "w").write("".join(json.dumps(r, separators=(",", ":")) + "\n" for r in rows))
PY2
git commit -q -m "local export 2" -- .beads/issues.jsonl
local_tip="$(git rev-parse HEAD)"
git checkout -q -b peer3 "$base"
python3 - <<'PY2'
import json
p = ".beads/issues.jsonl"
rows = [json.loads(l) for l in open(p) if l.strip()]
rows = [r for r in rows if r["id"] != "k"] + [{"id": "k", "title": "edited on the peer again", "updated_at": "2027-06-01T00:00:00Z"}]
open(p, "w").write("".join(json.dumps(r, separators=(",", ":")) + "\n" for r in rows))
PY2
git commit -q -m "peer3 export" -- .beads/issues.jsonl
git checkout -q main
git merge --no-commit peer3 >/dev/null 2>&1 && fail "fixture: expected a conflict"
git checkout --theirs -- .beads/issues.jsonl && git add .beads/issues.jsonl && git commit -q --no-edit
# A further commit on top, before the helper runs: the merge is no longer the tip.
python3 - <<'PY2'
import json
p = ".beads/issues.jsonl"
rows = [json.loads(l) for l in open(p) if l.strip()]
rows.append({"id": "v", "title": "added after the merge", "updated_at": "2027-06-02T00:00:00Z"})
open(p, "w").write("".join(json.dumps(r, separators=(",", ":")) + "\n" for r in rows))
PY2
git commit -q -m "after the merge" -- .beads/issues.jsonl
db_has v && fail "fixture: v must not exist in the database before the helper runs"
rc=0; out="$(bash scripts/beads-import-merged.sh "$local_tip" 2>&1 >/dev/null)" || rc=$?
[ "$rc" -eq 1 ] || fail "a divergent merge inside the range was not flagged (rc=$rc): $out"
db_has k "edited here again" || fail "the exported local edit was overwritten although the merge was not the tip"
db_has v "added after the merge" || fail "a safe row after the merge did not land"
case "$out" in *"changed on both hosts"*"k"*) ;; *) fail "the conflict was not reported: $out" ;; esac

echo "=== 31: --full keeps the conflict rule: differing existing records are held, absent rows apply ==="
reset_import
rm -f .beads/transport/conflicts.json .beads/transport/pending-import.json .beads/transport/pending-import.jsonl
# The file carries a version of k that differs from the database (an exported
# concurrent edit), and a row w the database has never seen.
python3 - <<'PY2'
import json
p = ".beads/issues.jsonl"
rows = [json.loads(l) for l in open(p) if l.strip()]
rows = [r for r in rows if r["id"] not in ("k", "full-absent-31")] + [{"id": "k", "title": "file version of k", "updated_at": "2099-01-01T00:00:00Z"},
                                                          {"id": "full-absent-31", "title": "absent locally", "updated_at": "2027-07-01T00:00:00Z"}]
open(p, "w").write("".join(json.dumps(r, separators=(",", ":")) + "\n" for r in rows))
PY2
git commit -q -m "file diverges" -- .beads/issues.jsonl
db_has full-absent-31 && fail "fixture: full-absent-31 must not exist in the database before --full"
rc=0; out="$(bash scripts/beads-import-merged.sh --full 2>&1 >/dev/null)" || rc=$?
[ "$rc" -eq 1 ] || fail "--full chose a side for a differing existing record (rc=$rc): $out"
db_has k "edited here again" || fail "--full overwrote an existing local record by timestamp"
db_has full-absent-31 "absent locally" || fail "--full did not import a row the database lacked"
python3 -c 'import json; c=json.load(open(".beads/transport/conflicts.json"))["records"]["k"]; assert c["reason"]=="no_git_provenance", c' \
  || fail "the --full hold-back was not recorded as no_git_provenance"


echo "=== 32: a fast-forward over an upstream merge of two divergent Beads edits flags the record; a later safe row applies ==="
# BEFORE = A. Upstream, b1 and b2 both edit K after A; b2 is merged into b1
# (taking one side), then a safe row is added; we fast-forward from A. Both
# parents of that merge descend from A, so a "did it diverge from us" test
# would skip it — yet K was edited concurrently and the merge's choice is not
# ours to accept silently.
reset_import
rm -f .beads/transport/conflicts.json
A="$(git rev-parse HEAD)"
git checkout -q -b b1 "$A"
python3 - <<'PY2'
import json
p = ".beads/issues.jsonl"
rows = [json.loads(l) for l in open(p) if l.strip()]
rows = [r for r in rows if r["id"] != "k"] + [{"id": "k", "title": "k per b1", "updated_at": "2027-08-01T00:00:00Z"}]
open(p, "w").write("".join(json.dumps(r, separators=(",", ":")) + "\n" for r in rows))
PY2
git commit -q -m "b1 edits k" -- .beads/issues.jsonl
git checkout -q -b b2 "$A"
python3 - <<'PY2'
import json
p = ".beads/issues.jsonl"
rows = [json.loads(l) for l in open(p) if l.strip()]
rows = [r for r in rows if r["id"] != "k"] + [{"id": "k", "title": "k per b2", "updated_at": "2027-08-02T00:00:00Z"}]
open(p, "w").write("".join(json.dumps(r, separators=(",", ":")) + "\n" for r in rows))
PY2
git commit -q -m "b2 edits k" -- .beads/issues.jsonl
git checkout -q b1
git merge --no-commit b2 >/dev/null 2>&1 && fail "fixture: expected b1/b2 to conflict on k"
git checkout --theirs -- .beads/issues.jsonl && git add .beads/issues.jsonl && git commit -q --no-edit
python3 - <<'PY2'
import json
p = ".beads/issues.jsonl"
rows = [json.loads(l) for l in open(p) if l.strip()]
rows.append({"id": "safe-32", "title": "safe row after the upstream merge", "updated_at": "2027-08-03T00:00:00Z"})
open(p, "w").write("".join(json.dumps(r, separators=(",", ":")) + "\n" for r in rows))
PY2
git commit -q -m "safe row" -- .beads/issues.jsonl
git checkout -q main && git merge -q --ff-only b1
db_has safe-32 && fail "fixture: safe-32 must not exist in the database before the helper runs"
k_before="$(python3 -c 'import json,sys; rows={json.loads(l)["id"]:json.loads(l) for l in open(sys.argv[1]) if l.strip()}; print(rows["k"]["title"])' "$BD_STUB_DB")"
rc=0; out="$(bash scripts/beads-import-merged.sh "$A" 2>&1 >/dev/null)" || rc=$?
[ "$rc" -eq 1 ] || fail "an upstream divergent merge inside a fast-forward was not flagged (rc=$rc): $out"
db_has k "$k_before" || fail "the upstream merge's choice for k was imported as if resolved"
db_has safe-32 "safe row after the upstream merge" || fail "the safe row after the upstream merge did not land"
python3 -c 'import json; c=json.load(open(".beads/transport/conflicts.json"))["records"]["k"]; assert c["reason"]=="both_changed_since_merge_base", c' \
  || fail "k was not recorded as changed on both sides"
ev="$(python3 -c 'import json; print(json.load(open(".beads/transport/conflicts.json"))["records"]["k"]["evidence"])')"
grep -q '"k per b1"' "$ev"/k.*.json && grep -q '"k per b2"' "$ev"/k.*.json || fail "evidence does not hold both upstream versions of k"

echo "=== 33: a normal verified fast-forward import leaves no stray TMP files and releases the lock ==="
# Regression for the installed defect diagnosed on zklw: run_range declared
# its working file as "local TMP" but installed an EXIT trap that reads $TMP
# only when the WHOLE PROCESS exits — by which point a successful (non-exit)
# return from run_range has already torn down that local binding, so the trap
# read an unbound variable under set -u and never reached its cleanup/unlock.
# Each sub-scenario below runs the real script as a child process against an
# isolated TMPDIR, so leftover files are unambiguous and never confused with
# another scenario's temp files in this same $SANDBOX.
reset_import
prev="$(git rev-parse HEAD)"
{ cat .beads/issues.jsonl; row tmp1 2026-12-20T00:00:00Z; } > .beads/issues.jsonl.new; mv .beads/issues.jsonl.new .beads/issues.jsonl
git commit -q -m "add tmp1" -- .beads/issues.jsonl
range_tmp="$(mktemp -d)"
rc=0
out="$(TMPDIR="$range_tmp" bash scripts/beads-import-merged.sh "$prev" 2>&1 >/dev/null)" || rc=$?
[ "$rc" -eq 0 ] || fail "a plain fast-forward import that should verify cleanly exited $rc: $out"
case "$out" in *"unbound variable"*) fail "run_range's temp-file trap referenced an out-of-scope variable: $out" ;; esac
[ -z "$(ls -A "$range_tmp")" ] || fail "run_range left temp files behind on a successful return: $(ls -A "$range_tmp")"
bash -c '. scripts/lib-beads-transport.sh; beads_transport_lock_held' && fail "the transport lock was still held after a successful run"
db_has tmp1 || fail "fixture: the row exercising the cleanup path did not actually import"
rm -rf "$range_tmp"

echo "=== 34: a merge-ancestry import (indexed .base/.ours/.theirs temp files) also leaves nothing behind ==="
reset_import
rm -f .beads/transport/conflicts.json
base33="$(git rev-parse HEAD)"
git checkout -q -b merge33 "$base33"
{ cat .beads/issues.jsonl; row tmp2 2026-12-21T00:00:00Z; } > .beads/issues.jsonl.new; mv .beads/issues.jsonl.new .beads/issues.jsonl
git commit -q -m "merge33 adds tmp2" -- .beads/issues.jsonl
git checkout -q main
git merge -q --no-ff -m "merge tmp2" merge33
range_tmp2="$(mktemp -d)"
rc=0
out="$(TMPDIR="$range_tmp2" bash scripts/beads-import-merged.sh "$base33" 2>&1 >/dev/null)" || rc=$?
[ "$rc" -eq 0 ] || fail "a merge-ancestry import that should verify cleanly exited $rc: $out"
case "$out" in *"unbound variable"*) fail "the merge-ancestry trap referenced an out-of-scope variable: $out" ;; esac
[ -z "$(ls -A "$range_tmp2")" ] || fail "a merge-ancestry import left indexed side-files behind: $(ls -A "$range_tmp2")"
bash -c '. scripts/lib-beads-transport.sh; beads_transport_lock_held' && fail "the transport lock was still held after a merge-ancestry run"
db_has tmp2 || fail "fixture: the merge-ancestry row did not actually import"
rm -rf "$range_tmp2"

echo "all import-merged scenarios passed"
