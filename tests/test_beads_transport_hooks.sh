#!/usr/bin/env bash
# Integration tests for the Beads git transport as git actually runs it.
#
# Everything here goes through real `git commit` and real `git pull` in
# disposable repositories, with THIS repository's tracked hook files
# (.beads/hooks/*) made effective by scripts/beads-transport-setup.sh — the
# thing under test is whether ordinary git commands carry bead state, not
# whether the helper scripts work when called by hand (tests/test_beads_*
# cover those). bd is a stub over a tiny JSONL database, so no real Dolt
# database is touched.
#
# Scenarios: setup check on a fresh clone, idempotent install, worktree
# isolation (other worktrees' effective hook paths provably unchanged), a
# commit that exports, a commit that does not, a pull that imports, a pull
# that changes nothing, a failed import reported by the hook with the
# deletion ledger held back, retry, an "Already up to date" pull, foreign
# hook sections untouched, and a database identity mismatch refused.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SANDBOX="$(mktemp -d)"
SANDBOX="$(cd "$SANDBOX" && pwd -P)"
trap 'rm -rf "$SANDBOX"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# Nothing from the host's dotfiles or plugin cache may run inside the hooks.
export HOME="$SANDBOX/home"; mkdir -p "$HOME"
export BEADS_TRANSPORT_LOCK_BASE="$SANDBOX/locks"; mkdir -p "$BEADS_TRANSPORT_LOCK_BASE"
export GIT_CONFIG_NOSYSTEM=1
unset INTERWATCH_HOOK_RUNNER BEADS_NO_AUTO_EXPORT BEADS_TRANSPORT_EXPECT_PROJECT || true

# ─── stub bd: a JSONL database per checkout family ────────────────────
# $BD_STUB_DB names the database file; `context` reports its directory as
# beads_dir, which is what the identity check compares. Import/export behave
# like bd's (strictly-newer upsert), plus the failure knobs the scenarios use.
mkdir -p "$SANDBOX/bin"
cat > "$SANDBOX/bin/bd" <<'STUB'
#!/usr/bin/env python3
import json, os, shutil, sys
argv = sys.argv[1:]
while argv and argv[0] in ("--readonly", "--sandbox"):
    argv = argv[1:]
if argv[:1] == ["-C"]:
    argv = argv[2:]
db = os.environ["BD_STUB_DB"]
calls = os.environ.get("BD_STUB_CALLS")
if calls:
    with open(calls, "a") as fh:
        fh.write(" ".join(argv) + "\n")
def load():
    rows = {}
    if os.path.exists(db):
        for line in open(db):
            if line.strip():
                r = json.loads(line); rows[r["id"]] = r
    return rows
def save(rows):
    with open(db, "w") as fh:
        for r in rows.values(): fh.write(json.dumps(r, separators=(",", ":")) + "\n")
cmd = argv[:1]
if cmd == ["context"]:
    beads_dir = os.path.dirname(db)
    while os.path.basename(beads_dir) != ".beads" and beads_dir != "/":
        beads_dir = os.path.dirname(beads_dir)          # bd reports .beads/, not the dolt data dir
    print(json.dumps({"beads_dir": beads_dir, "project_id": os.environ.get("BD_STUB_PROJECT", "stub-project"), "is_worktree": False}))
elif cmd == ["info"]:
    print("Database:", db); print("Mode: direct")
elif cmd == ["hooks"]:
    if argv[1:2] == ["list"]:
        print("Git hooks status:"); print("  (stub)")
    elif argv[1:3] == ["run", "post-merge"] and calls:
        with open(calls, "a") as fh:
            fh.write("native-import-auto=" + os.environ.get("BD_IMPORT_AUTO", "unset") + "\n")
elif cmd == ["export"]:
    out = argv[argv.index("-o") + 1] if "-o" in argv else argv[argv.index("--output") + 1]
    shutil.copyfile(db, out) if os.path.exists(db) else open(out, "w").close()
elif cmd == ["import"]:
    src = [a for a in argv[1:] if not a.startswith("--")][0]
    if os.environ.get("BD_STUB_FAIL"):
        print(json.dumps({"error": "simulated: dolt server unreachable"})); sys.exit(1)
    rows = load(); created = updated = 0
    for line in open(src):
        if not line.strip(): continue
        r = json.loads(line); cur = rows.get(r["id"])
        if cur is None: rows[r["id"]] = r; created += 1
        elif r.get("updated_at", "") > cur.get("updated_at", ""): rows[r["id"]] = r; updated += 1
    save(rows)
    print(json.dumps({"created": created, "updated": updated, "skipped": 0}))
elif cmd == ["show"]:
    rows = load(); r = rows.get(argv[1])
    if r is None:
        print(f'Error fetching {argv[1]}: no issue found matching "{argv[1]}"', file=sys.stderr); sys.exit(1)
    print(json.dumps([r]))
elif cmd == ["delete"]:
    rows = load(); rows.pop(argv[1], None); save(rows); print("Deleted", argv[1])
STUB
chmod +x "$SANDBOX/bin/bd"
export PATH="$SANDBOX/bin:$PATH"

# ─── fixture: origin, main checkout, peer ─────────────────────────────
row() { printf '{"_type":"issue","id":"%s","title":"%s","status":"open","updated_at":"%s","comment_count":0}\n' "$1" "${3:-t}" "$2"; }

git init -q --bare -b main "$SANDBOX/origin.git"
SEED="$SANDBOX/seed"
mkdir -p "$SEED/.beads/hooks" "$SEED/scripts"
cp "$ROOT/.beads/hooks/pre-commit" "$ROOT/.beads/hooks/post-commit" "$ROOT/.beads/hooks/post-merge" "$ROOT/.beads/hooks/pre-push" "$SEED/.beads/hooks/"
cp "$ROOT/.beads/.gitignore" "$SEED/.beads/.gitignore"
cp "$ROOT/.beads/config.yaml" "$SEED/.beads/config.yaml"
for s in beads-auto-export.sh beads-import-merged.sh beads-confirm-deletion.sh lib-beads-transport.sh \
         check_beads_jsonl_dolt_sync.py beads_apply_deletions.py beads-transport-setup.sh; do
  cp "$ROOT/scripts/$s" "$SEED/scripts/"
done
chmod +x "$SEED"/.beads/hooks/* "$SEED"/scripts/*.sh
{ row a 2026-01-01T00:00:00Z; row b 2026-01-01T00:00:00Z; } > "$SEED/.beads/issues.jsonl"
: > "$SEED/.beads/deletions.jsonl"
echo seed > "$SEED/README.md"
git -C "$SEED" init -q . && git -C "$SEED" config user.email t@t && git -C "$SEED" config user.name t
git -C "$SEED" config core.hooksPath /dev/null
git -C "$SEED" add -A && git -C "$SEED" commit -q -m "seed" && git -C "$SEED" branch -M main
git -C "$SEED" remote add origin "$SANDBOX/origin.git" && git -C "$SEED" push -q origin main

MAIN="$SANDBOX/main"
git clone -q "$SANDBOX/origin.git" "$MAIN"
git -C "$MAIN" config user.email t@t; git -C "$MAIN" config user.name main
mkdir -p "$MAIN/.beads/dolt"                       # where the stub's "database" lives
cp "$MAIN/.beads/issues.jsonl" "$MAIN/.beads/dolt/db.jsonl"
export BD_STUB_DB="$MAIN/.beads/dolt/db.jsonl"

PEER="$SANDBOX/peer"                               # the other machine: no hooks, commits JSONL by hand
git clone -q "$SANDBOX/origin.git" "$PEER"
git -C "$PEER" config user.email t@t; git -C "$PEER" config user.name peer
git -C "$PEER" config core.hooksPath /dev/null

setup() { (cd "$1" && bash scripts/beads-transport-setup.sh "${@:2}"); }
status_field() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(json.dumps(d.get(sys.argv[2], {}).get(sys.argv[3])))' "$1/.beads/transport/status.json" "$2" "$3"; }
db_has() { python3 -c 'import json,sys; rows={json.loads(l)["id"]:json.loads(l) for l in open(sys.argv[1]) if l.strip()}; r=rows.get(sys.argv[2]); sys.exit(0 if r and (len(sys.argv)<4 or r.get("title")==sys.argv[3]) else 1)' "$BD_STUB_DB" "$@"; }

# ─── 1: a fresh clone has the hooks and runs none of them ─────────────
echo "=== 1: check on a fresh clone reports inactive hooks, with the files present ==="
rc=0; out="$(setup "$MAIN" check 2>&1)" || rc=$?
[ "$rc" -eq 1 ] || fail "check exited $rc on a clone with no hooksPath; expected 1"
case "$out" in *"[FAIL] effective hooksPath"*) ;; *) fail "the inactive hook path was not reported: $out" ;; esac
case "$out" in *"[ok  ] hook post-commit"*"[ok  ] hook post-merge"*) ;; *) fail "the tracked hook files were not recognised: $out" ;; esac
case "$out" in *"[ok  ] database"*) ;; *) fail "the database binding was not verified: $out" ;; esac
git -C "$MAIN" log -1 --format=%s | grep -q seed || fail "fixture: unexpected history"

# ─── 2: install is idempotent ─────────────────────────────────────────
echo "=== 2: install makes the tracked hooks effective; a second install changes nothing ==="
setup "$MAIN" install >/dev/null 2>&1 || fail "install failed: $(setup "$MAIN" install 2>&1 | tail -3)"
setup "$MAIN" check >/dev/null 2>&1 || fail "check fails right after install: $(setup "$MAIN" check 2>&1 | grep FAIL)"
[ "$(git -C "$MAIN" config --get core.hooksPath)" = "$MAIN/.beads/hooks" ] || fail "core.hooksPath is $(git -C "$MAIN" config --get core.hooksPath)"
out="$(setup "$MAIN" install 2>&1)" || fail "second install failed: $out"
case "$out" in *"unchanged; already effective"*) ;; *) fail "second install was not a no-op: $out" ;; esac
json="$(setup "$MAIN" check --json)"
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["ok"] and d["hooks_active"] and d["database_verified"], d' "$json" || fail "--json does not report an installed checkout"

# ─── 3: worktrees are isolated ────────────────────────────────────────
echo "=== 3: installing in a linked worktree changes no other worktree's effective hook path ==="
git -C "$MAIN" worktree add -q "$SANDBOX/wt-other" -b other >/dev/null 2>&1
git -C "$MAIN" worktree add -q "$SANDBOX/wt" -b feature >/dev/null 2>&1
main_before="$(git -C "$MAIN" config --get core.hooksPath)"
other_before="$(git -C "$SANDBOX/wt-other" config --get core.hooksPath)"
rc=0; out="$(setup "$SANDBOX/wt" check 2>&1)" || rc=$?
[ "$rc" -eq 1 ] || fail "a fresh worktree reported active hooks: $out"
case "$out" in *"linked=1"*) ;; *) fail "worktree discovery failed: $out" ;; esac
out="$(setup "$SANDBOX/wt" install 2>&1)" || fail "install in the worktree failed: $out"
case "$out" in *"other worktree unchanged"*"$MAIN"*) ;; *) fail "the main checkout's path was not proven unchanged: $out" ;; esac
[ "$(git -C "$SANDBOX/wt" config --get core.hooksPath)" = "$SANDBOX/wt/.beads/hooks" ] || fail "the worktree's effective hooksPath is $(git -C "$SANDBOX/wt" config --get core.hooksPath)"
[ "$(git -C "$MAIN" config --get core.hooksPath)" = "$main_before" ] || fail "installing in a worktree changed the main checkout's hooksPath"
[ "$(git -C "$SANDBOX/wt-other" config --get core.hooksPath)" = "$other_before" ] || fail "installing in one worktree changed another worktree's hooksPath"
[ "$(git -C "$SANDBOX/wt" config --show-scope --get core.hooksPath | awk '{print $1}')" = "worktree" ] || fail "the worktree setting is not worktree-scoped"
setup "$SANDBOX/wt" check >/dev/null 2>&1 || fail "check fails in the installed worktree"
setup "$MAIN" check >/dev/null 2>&1 || fail "the main checkout no longer checks clean"
git -C "$MAIN" worktree remove --force "$SANDBOX/wt" >/dev/null 2>&1
git -C "$MAIN" worktree remove --force "$SANDBOX/wt-other" >/dev/null 2>&1

# ─── 4: a real commit exports through the real post-commit hook ───────
echo "=== 4: a commit after a database change produces the export commit; a commit without one does not ==="
python3 - "$BD_STUB_DB" <<'PY'
import json, sys
p = sys.argv[1]
rows = [l for l in open(p) if l.strip()]
rows.append(json.dumps({"_type":"issue","id":"c","title":"created on main","status":"open","updated_at":"2026-02-01T00:00:00Z","comment_count":0}) + "\n")
open(p, "w").write("".join(rows))
PY
echo work > "$MAIN/README.md"
git -C "$MAIN" commit -q -m "work" -- README.md 2>"$SANDBOX/commit.err" || fail "commit failed: $(cat "$SANDBOX/commit.err")"
[ "$(git -C "$MAIN" log -1 --format=%s)" = "beads: sync export (automated)" ] || fail "no export commit after a database change: $(git -C "$MAIN" log -2 --format=%s | tr '\n' '|'); stderr: $(cat "$SANDBOX/commit.err")"
grep -q '"created on main"' "$MAIN/.beads/issues.jsonl" || fail "the export does not carry the new row"
[ "$(status_field "$MAIN" export result)" = '"committed"' ] || fail "status.json: $(status_field "$MAIN" export result)"
before="$(git -C "$MAIN" rev-parse HEAD)"
echo work2 > "$MAIN/README.md"
git -C "$MAIN" commit -q -m "work2" -- README.md 2>/dev/null
[ "$(git -C "$MAIN" rev-list --count "$before"..HEAD)" = "1" ] || fail "a commit with no bead change produced an export commit"
[ "$(status_field "$MAIN" export result)" = '"unchanged"' ] || fail "a no-change pass left no evidence"
git -C "$MAIN" push -q origin main 2>/dev/null || fail "push failed"

# ─── 5: a real pull imports through the real post-merge hook ──────────
echo "=== 5: a pull that brings another machine's row imports it, verified ==="
git -C "$PEER" pull -q --no-rebase origin main
python3 - "$PEER/.beads/issues.jsonl" <<'PY'
import json, sys
p = sys.argv[1]
rows = [json.loads(l) for l in open(p) if l.strip()]
rows.append({"_type":"issue","id":"d","title":"created on peer","status":"open","updated_at":"2026-03-01T00:00:00Z","comment_count":0})
open(p, "w").write("".join(json.dumps(r, separators=(",", ":")) + "\n" for r in rows))
PY
git -C "$PEER" commit -q -m "peer: add d" -- .beads/issues.jsonl && git -C "$PEER" push -q origin main
export BD_STUB_CALLS="$SANDBOX/calls.log"; : > "$BD_STUB_CALLS"
git -C "$MAIN" pull -q --no-rebase origin main 2>"$SANDBOX/pull.err" || fail "pull failed: $(cat "$SANDBOX/pull.err")"
db_has d "created on peer" || fail "the pulled row did not reach the database; stderr: $(cat "$SANDBOX/pull.err")"
grep -q '^import' "$BD_STUB_CALLS" || fail "bd import was not invoked by the hook"
# The native block runs AFTER ours in the tracked hook, with BD_IMPORT_AUTO
# already false for this invocation. With a real bd it imports the JSONL
# itself otherwise (tests/test_bd_import_guard.py proves both); this pins
# the ordering that lets the classifier see every row first, and that the
# override actually reached bd's process.
[ "$(grep -n '^hooks run post-merge\|^import' "$BD_STUB_CALLS" | head -1 | cut -d: -f2- | cut -d' ' -f1)" = "import" ] \
  || fail "expected the classified import to run before the native post-merge block; calls: $(tr '\n' '|' < "$BD_STUB_CALLS")"
grep -q '^hooks run post-merge' "$BD_STUB_CALLS" || fail "the native block did not run after ours"
grep -q '^native-import-auto=false' "$BD_STUB_CALLS" || fail "bd's post-merge did not see BD_IMPORT_AUTO=false: $(tr '\n' '|' < "$BD_STUB_CALLS")"
[ -z "${BD_IMPORT_AUTO:-}" ] || fail "the override leaked out of the hook into this shell"
[ "$(status_field "$MAIN" import result)" = '"verified"' ] || fail "import status: $(status_field "$MAIN" import result)"
[ -f "$MAIN/.beads/transport/pending-import.json" ] && fail "a verified import left pending state"

echo "=== 6: a pull that merges only unrelated changes calls bd import not at all ==="
echo peerdoc > "$PEER/PEER.md"; git -C "$PEER" add PEER.md; git -C "$PEER" commit -q -m "peer: doc"; git -C "$PEER" push -q origin main
: > "$BD_STUB_CALLS"
git -C "$MAIN" pull -q --no-rebase origin main 2>/dev/null
grep -q '^import' "$BD_STUB_CALLS" && fail "bd import ran on a pull that changed no bead state"
[ -f "$MAIN/.beads/transport/pending-import.json" ] && fail "pending state appeared without an import"

# ─── 7: a failed import is reported by the hook; the ledger waits ─────
echo "=== 7: a failing import leaves git complete, Beads incomplete, and the deletion ledger unapplied ==="
python3 - "$PEER/.beads/issues.jsonl" <<'PY'
import json, sys
p = sys.argv[1]
rows = [json.loads(l) for l in open(p) if l.strip()]
rows.append({"_type":"issue","id":"e","title":"created on peer later","status":"open","updated_at":"2026-04-01T00:00:00Z","comment_count":0})
open(p, "w").write("".join(json.dumps(r, separators=(",", ":")) + "\n" for r in rows))
PY
printf '{"actor":"peer","deleted_at":"2026-04-02T00:00:00Z","id":"b","machine":"peer"}\n' >> "$PEER/.beads/deletions.jsonl"
git -C "$PEER" commit -q -m "peer: add e, delete b" -- .beads/issues.jsonl .beads/deletions.jsonl && git -C "$PEER" push -q origin main
: > "$BD_STUB_CALLS"
rc=0; BD_STUB_FAIL=1 git -C "$MAIN" pull -q --no-rebase origin main 2>"$SANDBOX/pull.err" || rc=$?
[ "$rc" -eq 0 ] || fail "a failed import failed the pull itself (rc=$rc); git must complete"
grep -q "Beads sync is INCOMPLETE" "$SANDBOX/pull.err" || fail "the hook did not report the incomplete sync: $(cat "$SANDBOX/pull.err")"
grep -q "deletion ledger NOT applied" "$SANDBOX/pull.err" || fail "the hook did not say the ledger was held back: $(cat "$SANDBOX/pull.err")"
db_has b || fail "the deletion ledger was applied after an incomplete import"
grep -q '^delete' "$BD_STUB_CALLS" && fail "bd delete ran after an incomplete import"
[ -f "$MAIN/.beads/transport/pending-import.json" ] || fail "no pending state after a failed import"
[ "$(status_field "$MAIN" import result)" = '"incomplete"' ] || fail "import status: $(status_field "$MAIN" import result)"

echo "=== 8: an 'Already up to date' pull runs no hook; the pending batch is announced by the next commit and push ==="
rc=0; out="$(git -C "$MAIN" pull --no-rebase origin main 2>&1)" || rc=$?
case "$out" in *"Already up to date"*) ;; *) fail "fixture: expected an up-to-date pull, got: $out" ;; esac
[ -f "$MAIN/.beads/transport/pending-import.json" ] || fail "pending state vanished across an up-to-date pull"
echo work3 > "$MAIN/README.md"
git -C "$MAIN" commit -q -m "work3" -- README.md 2>"$SANDBOX/commit.err" || true
grep -q "pending import batch is waiting" "$SANDBOX/commit.err" || fail "the next commit did not announce the pending batch: $(cat "$SANDBOX/commit.err")"
git -C "$MAIN" push origin main 2>"$SANDBOX/push.err" >/dev/null || fail "push failed: $(cat "$SANDBOX/push.err")"
grep -q "pending import batch is waiting" "$SANDBOX/push.err" || fail "the push did not announce the pending batch: $(cat "$SANDBOX/push.err")"
rc=0; setup "$MAIN" check >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "check passed with a pending import"

echo "=== 9: --retry lands the batch; the next pull then applies the ledger ==="
(cd "$MAIN" && bash scripts/beads-import-merged.sh --retry >/dev/null 2>&1) || fail "retry failed"
db_has e "created on peer later" || fail "the retried row did not land"
[ -f "$MAIN/.beads/transport/pending-import.json" ] && fail "pending state survived a verified retry"
# The ledger runs after the next successful import pass, i.e. the next merge.
git -C "$PEER" pull -q --no-rebase origin main            # main pushed in scenario 8
echo peerdoc2 > "$PEER/PEER.md"; git -C "$PEER" commit -q -m "peer: doc2" -- PEER.md; git -C "$PEER" push -q origin main
git -C "$MAIN" pull -q --no-rebase origin main 2>/dev/null
db_has b && fail "the deletion ledger was not applied after the import recovered"

# ─── 10: foreign hooks: retained or refused, never lost ───────────────
echo "=== 10: install leaves every foreign hook section byte-identical ==="
for h in pre-commit post-commit post-merge pre-push; do
  cmp -s "$SEED/.beads/hooks/$h" "$MAIN/.beads/hooks/$h" || fail "hook $h was modified in the working tree"
done
grep -q "BEGIN BEADS INTEGRATION" "$MAIN/.beads/hooks/pre-commit" || fail "the native beads block is gone"
grep -q "interwatch managed block" "$MAIN/.beads/hooks/post-commit" || fail "the interwatch block is gone"

echo "=== 10b: a custom hook that is effective now is not silently retired by install ==="
# The probe that found this: a foreign post-commit writing a sentinel, effective
# through core.hooksPath. After install, an ordinary commit exited 0 and the
# sentinel stayed where it was — the hook file still existed, git just no
# longer ran it. Now install refuses BEFORE touching config and names the file.
FOREIGN="$SANDBOX/foreign-hooks"; mkdir -p "$FOREIGN"
printf '#!/bin/sh\nprintf "foreign\\n" >> "%s"\n' "$SANDBOX/sentinel" > "$FOREIGN/post-commit"; chmod +x "$FOREIGN/post-commit"
git -C "$MAIN" config core.hooksPath "$FOREIGN"
echo custom > "$MAIN/README.md"; git -C "$MAIN" commit -q -m "custom hook before" -- README.md
before="$(grep -c foreign "$SANDBOX/sentinel")"
rc=0; out="$(setup "$MAIN" install 2>&1)" || rc=$?
[ "$rc" -eq 1 ] || fail "install exited $rc although an effective custom hook would have been retired"
case "$out" in *"[FAIL] effective hook would be lost"*"$FOREIGN/post-commit"*"[FAIL] install"*"refused before any config change"*) ;; *) fail "the retired hook was not named before refusal: $out" ;; esac
[ "$(git -C "$MAIN" config --get core.hooksPath)" = "$FOREIGN" ] || fail "install changed core.hooksPath despite refusing"
echo custom2 > "$MAIN/README.md"; git -C "$MAIN" commit -q -m "custom hook after" -- README.md
[ "$(grep -c foreign "$SANDBOX/sentinel")" -gt "$before" ] || fail "the custom hook stopped running"
# A hook name we do not ship is refused too.
git -C "$MAIN" config core.hooksPath "$SANDBOX/foreign2"; mkdir -p "$SANDBOX/foreign2"
printf '#!/bin/sh\nexit 0\n' > "$SANDBOX/foreign2/commit-msg"; chmod +x "$SANDBOX/foreign2/commit-msg"
rc=0; out="$(setup "$MAIN" install 2>&1)" || rc=$?
case "$out" in *"commit-msg (no tracked commit-msg to retain it)"*) ;; *) fail "an unshipped hook name was not refused: $out" ;; esac
[ "$(git -C "$MAIN" config --get core.hooksPath)" = "$SANDBOX/foreign2" ] || fail "install changed core.hooksPath despite an unshipped hook"

echo "=== 10c: an older copy of these hooks with the same foreign sections is replaceable; one with extra foreign content is not ==="
OLD="$SANDBOX/old-transport-hooks"; mkdir -p "$OLD"
for h in pre-commit post-commit post-merge pre-push; do
  # Same foreign sections, different (older) transport sections.
  python3 - "$MAIN/.beads/hooks/$h" "$OLD/$h" <<'PY2'
import re, sys
src, dst = sys.argv[1:3]
out, skip = [], False
for line in open(src):
    s = line.strip()
    if re.match(r"#\s*-{3}\s*BEGIN SYLVESTE BEADS ", s):
        skip = True; out.append(line); out.append("echo old transport section\n"); continue
    if re.match(r"#\s*-{3}\s*END SYLVESTE BEADS ", s):
        skip = False; out.append(line); continue
    if not skip: out.append(line)
open(dst, "w").write("".join(out))
PY2
  chmod +x "$OLD/$h"
done
git -C "$MAIN" config core.hooksPath "$OLD"
out="$(setup "$MAIN" install 2>&1)" || fail "install refused an older copy of the transport hooks whose foreign sections are all retained: $out"
case "$out" in *"previous hook post-commit"*"retained"*) ;; *) fail "the retained-sections verdict was not reported: $out" ;; esac
[ "$(git -C "$MAIN" config --get core.hooksPath)" = "$MAIN/.beads/hooks" ] || fail "install did not switch away from the replaceable old hooks"
# Now the old copy carries a foreign line ours lacks.
git -C "$MAIN" config core.hooksPath "$OLD"
printf '\n# custom\ntouch "%s/custom-ran"\n' "$SANDBOX" >> "$OLD/pre-push"
rc=0; out="$(setup "$MAIN" install 2>&1)" || rc=$?
[ "$rc" -eq 1 ] || fail "install accepted an old hook carrying foreign content ours lacks"
case "$out" in *"$OLD/pre-push (retains content the tracked pre-push lacks"*) ;; *) fail "the extra foreign content was not named: $out" ;; esac
[ "$(git -C "$MAIN" config --get core.hooksPath)" = "$OLD" ] || fail "install changed core.hooksPath despite refusing"
git -C "$MAIN" config core.hooksPath "$MAIN/.beads/hooks"

echo "=== 10d: the override is per invocation, never global, and a stray newer transport-disabled.jsonl is irrelevant ==="
# The retired mechanism pointed import.path at that filename; a file appearing
# there must change nothing now. The override is visible to bd's block and to
# nothing outside the hook process.
cp "$MAIN/.beads/issues.jsonl" "$MAIN/.beads/transport-disabled.jsonl"
git -C "$PEER" pull -q --no-rebase origin main
python3 - "$PEER/.beads/issues.jsonl" <<'PY2'
import json, sys
p = sys.argv[1]
rows = [json.loads(l) for l in open(p) if l.strip()]
rows.append({"_type":"issue","id":"f","title":"created on peer again","status":"open","updated_at":"2026-05-01T00:00:00Z","comment_count":0})
open(p, "w").write("".join(json.dumps(r, separators=(",", ":")) + "\n" for r in rows))
PY2
git -C "$PEER" commit -q -m "peer: add f" -- .beads/issues.jsonl && git -C "$PEER" push -q origin main
: > "$BD_STUB_CALLS"
rc=0; git -C "$MAIN" pull -q --no-rebase origin main 2>"$SANDBOX/pull.err" || rc=$?
[ "$rc" -eq 0 ] || fail "the pull itself failed (rc=$rc)"
grep -q '^import' "$BD_STUB_CALLS" || fail "the classified import did not run"
db_has f "created on peer again" || fail "the classified import did not land the pulled row"
grep -q '^native-import-auto=false' "$BD_STUB_CALLS" || fail "bd's post-merge ran without the override: $(tr '\n' '|' < "$BD_STUB_CALLS")"
[ "$(git -C "$MAIN" config --get bd.import.auto 2>/dev/null || true)" = "" ] || fail "the override was written into git config"
grep -q "BD_IMPORT_AUTO" "$MAIN/.beads/config.yaml" && fail "the override was written into the shared config"
rm -f "$MAIN/.beads/transport-disabled.jsonl"

# ─── 11: a wrong database is refused, before and at runtime ───────────
echo "=== 11: a checkout bound to another database is refused by check, install and the hooks ==="
mkdir -p "$SANDBOX/elsewhere/.beads"; cp "$BD_STUB_DB" "$SANDBOX/elsewhere/.beads/db.jsonl"
rc=0; out="$(BD_STUB_DB="$SANDBOX/elsewhere/.beads/db.jsonl" setup "$MAIN" check 2>&1)" || rc=$?
[ "$rc" -eq 1 ] || fail "check passed against a foreign database"
case "$out" in *"[FAIL] database"*"bound to a different database"*) ;; *) fail "the mismatch was not named: $out" ;; esac
git -C "$MAIN" config --unset core.hooksPath
rc=0; out="$(BD_STUB_DB="$SANDBOX/elsewhere/.beads/db.jsonl" setup "$MAIN" install 2>&1)" || rc=$?
case "$out" in *"[FAIL] install"*"refused"*) ;; *) fail "install proceeded against a foreign database: $out" ;; esac
git -C "$MAIN" config --get core.hooksPath >/dev/null 2>&1 && fail "install wrote hooksPath despite refusing"
setup "$MAIN" install >/dev/null 2>&1 || fail "reinstall against the right database failed"
before="$(git -C "$MAIN" rev-parse HEAD)"
echo work4 > "$MAIN/README.md"
BD_STUB_DB="$SANDBOX/elsewhere/.beads/db.jsonl" git -C "$MAIN" commit -q -m "work4" -- README.md 2>"$SANDBOX/commit.err" || true
[ "$(git -C "$MAIN" rev-list --count "$before"..HEAD)" = "1" ] || fail "an export ran against a foreign database"
grep -q "NOT exporting" "$SANDBOX/commit.err" || fail "the runtime refusal was silent: $(cat "$SANDBOX/commit.err")"
[ "$(status_field "$MAIN" export result)" = '"refused"' ] || fail "the refusal left no evidence"

echo "all transport-hook integration scenarios passed"
