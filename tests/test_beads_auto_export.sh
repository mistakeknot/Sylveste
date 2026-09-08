#!/usr/bin/env bash
# Ordering and guarding tests for scripts/beads-auto-export.sh.
#
# The script creates a git commit from inside post-commit. That is the risky
# part, and the failure modes are all about ordering rather than logic:
# recursing forever, widening someone else's commit, committing nothing, or
# firing in the middle of a rebase. Each gets a scenario here. Scenarios 9-13
# cover the guarded merge: rows the transport alone holds survive, conflicts
# are kept at the transport version with both copies in evidence, an edit the
# high-water mark cannot see is still exported, concurrent writers are
# serialized, and a transport that moves under the merge is never replaced.
#
# Runs entirely in a scratch repo against a stubbed `bd`, so it never reads or
# writes the real Dolt database.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# ─── fixture ──────────────────────────────────────────────────────────

mkdir -p "$SANDBOX/scripts" "$SANDBOX/.beads" "$SANDBOX/bin"
cp "$ROOT/scripts/beads-auto-export.sh" "$SANDBOX/scripts/"
cp "$ROOT/scripts/lib-beads-transport.sh" "$SANDBOX/scripts/"
cp "$ROOT/scripts/check_beads_jsonl_dolt_sync.py" "$SANDBOX/scripts/"

# Stub bd. DOLT_IDS drives what the "database" contains; `bd export` writes
# exactly those ids, `bd sql` lists them, `bd info` names the database. A row
# can be overridden by DOLT_OVERRIDES (one JSON object per line, matched by
# id) so a scenario can change content, not just membership. Accepts the
# `-C <dir>` prefix the real scripts pin their database with.
cat > "$SANDBOX/bin/bd" <<'STUB'
#!/usr/bin/env python3
import json, os, sys
argv = sys.argv[1:]
while argv and argv[0] in ("--readonly", "--sandbox"):
    argv = argv[1:]
if argv[:1] == ["-C"]:
    argv = argv[2:]
ids = os.environ.get("DOLT_IDS", "").split()
overrides = {}
for line in os.environ.get("DOLT_OVERRIDES", "").splitlines():
    if line.strip():
        overrides[json.loads(line)["id"]] = line.strip()
def row(i):
    return overrides.get(i) or json.dumps(
        {"_type": "issue", "id": i, "title": "t", "status": "open",
         "updated_at": "2026-01-01T00:00:00Z", "comment_count": 0}, separators=(",", ":"))
if argv[:1] == ["sql"]:
    print("id"); print("----")
    for i in ids: print(i)
elif argv[:1] == ["export"]:
    out = argv[argv.index("-o") + 1] if "-o" in argv else argv[argv.index("--output") + 1]
    with open(out, "w") as fh:
        for i in ids: fh.write(row(i) + "\n")
    if os.environ.get("BD_STUB_TOUCH_TRANSPORT"):
        with open(os.environ["BD_STUB_TOUCH_TRANSPORT"], "a") as fh:
            fh.write(row("racer") + "\n")
    print("Exported to", out)
elif argv[:1] == ["info"]:
    print("Database:", os.environ["BD_STUB_DB"]); print("Mode: direct")
elif argv[:1] == ["context"]:
    print(json.dumps({"beads_dir": os.path.dirname(os.environ["BD_STUB_DB"]), "project_id": "stub", "is_worktree": False}))
STUB
chmod +x "$SANDBOX/bin/bd"
export PATH="$SANDBOX/bin:$PATH"
export BD_STUB_DB="$SANDBOX/.beads/dolt"       # the database this checkout is bound to
export BEADS_TRANSPORT_LOCK_BASE="$SANDBOX/locks"; mkdir -p "$BEADS_TRANSPORT_LOCK_BASE"

cd "$SANDBOX"
git init -q && git config user.email t@t.invalid && git config user.name t
git config commit.gpgsign false

export DOLT_IDS="a b"
bd export --output .beads/issues.jsonl >/dev/null
echo seed > other.txt
git add -A && git commit -q -m "seed"

# Install the hook only now, so the seed commit does not trigger it.
mkdir -p .githooks
cat > .githooks/post-commit <<EOF
#!/bin/sh
"$SANDBOX/scripts/beads-auto-export.sh" || true
EOF
chmod +x .githooks/post-commit
git config core.hooksPath .githooks

jsonl_ids() { sed -n 's/.*"id":"\([^"]*\)".*/\1/p' .beads/issues.jsonl | sort | tr '\n' ' '; }
status_field() { python3 -c 'import json,sys; d=json.load(open(".beads/transport/status.json")); print(json.dumps(d["export"].get(sys.argv[1])))' "$1"; }

# ─── 1. a bead change is exported and committed on its own ────────────

echo "=== 1: Dolt ahead -> dedicated export commit, unrelated commit stays atomic ==="
export DOLT_IDS="a b c"
echo work > other.txt
git commit -q -m "unrelated work" -- other.txt

head_msg="$(git log -1 --format=%s)"
[ "$head_msg" = "beads: sync export (automated)" ] \
  || fail "expected an auto export commit at HEAD, got: $head_msg"

files="$(git show --name-only --format= HEAD | tr -d ' ')"
[ "$files" = ".beads/issues.jsonl" ] \
  || fail "auto commit touched more than the export: $files"

prev="$(git show --name-only --format= HEAD~1 | tr -d ' ')"
[ "$prev" = "other.txt" ] \
  || fail "the unrelated commit was widened to: $prev (must stay atomic)"

[ "$(jsonl_ids)" = "a b c " ] || fail "export content wrong: $(jsonl_ids)"
[ "$(status_field result)" = '"committed"' ] || fail "status.json does not record the commit: $(status_field result)"
echo "PASS"

# ─── 2. no bead change -> no commit at all ────────────────────────────

echo "=== 2: nothing to export -> no commit, and no empty commit ==="
before="$(git rev-parse HEAD)"
echo work2 > other.txt
git commit -q -m "more work" -- other.txt
after_msg="$(git log -1 --format=%s)"
[ "$after_msg" = "more work" ] \
  || fail "an export commit was created with nothing to export: $after_msg"
[ "$(git rev-list --count "$before"..HEAD)" = "1" ] \
  || fail "expected exactly one new commit"
[ "$(status_field result)" = '"unchanged"' ] || fail "a no-op pass left no evidence: $(status_field result)"
echo "PASS"

# ─── 3. re-entrancy ───────────────────────────────────────────────────

echo "=== 3: the export commit does not trigger another export commit ==="
export DOLT_IDS="a b c d"
echo work3 > other.txt
git commit -q -m "work3" -- other.txt
# Exactly two commits: the work, then one export. Not three, not a loop.
[ "$(git log -2 --format=%s | tr '\n' '|')" = "beads: sync export (automated)|work3|" ] \
  || fail "unexpected history: $(git log -3 --format=%s | tr '\n' '|')"
echo "PASS"

# ─── 4. JSONL ahead of Dolt -> preserved, never exported away ─────────

echo "=== 4: issues that exist only in the JSONL survive, and nothing is committed for them ==="
# Simulate a pull that brought another machine's issue, not yet imported.
printf '{"_type":"issue","id":"remote-only","title":"from zklw","updated_at":"2026-02-01T00:00:00Z"}\n' >> .beads/issues.jsonl
git add .beads/issues.jsonl
git -c core.hooksPath=/dev/null commit -q -m "pulled remote issue"
echo work4 > other.txt
warn="$(git commit -q -m "work4" -- other.txt 2>&1 >/dev/null)"

grep -q "remote-only" .beads/issues.jsonl \
  || fail "auto-export deleted an issue that existed only in the JSONL"
[ "$(git log -1 --format=%s)" = "work4" ] \
  || fail "auto-export committed with nothing database-side to publish"
case "$warn" in
  *"INCOMPLETE"*) ;;
  *) fail "a pending transport-side row was not reported; stderr: $warn" ;;
esac
[ "$(status_field transport_only)" = '["remote-only"]' ] \
  || fail "status.json does not name the pending row: $(status_field transport_only)"
echo "PASS"

# ─── 5. mid-sequence git operations are left alone ────────────────────

echo "=== 5: no commit is inserted while git is mid-sequence ==="
# Clear the pending state from scenario 4 first: the "other machine's" row is
# now in the database too.
export DOLT_IDS="a b c d remote-only"
export DOLT_OVERRIDES='{"_type":"issue","id":"remote-only","title":"from zklw","updated_at":"2026-02-01T00:00:00Z"}'

# Invoke the script directly rather than through a commit: git refuses a
# partial commit while MERGE_HEAD exists, so the commit that would trigger the
# hook cannot be made in this state anyway. What matters is that the script
# declines when it IS reached — via `git commit -a`, an amend, or a
# cherry-pick, all of which do fire post-commit mid-sequence.
export DOLT_IDS="a b c d remote-only e"
before="$(git rev-parse HEAD)"
touch "$(git rev-parse --git-dir)/MERGE_HEAD"
bash "$SANDBOX/scripts/beads-auto-export.sh" || true
rm -f "$(git rev-parse --git-dir)/MERGE_HEAD"
[ "$(git rev-parse HEAD)" = "$before" ] \
  || fail "an export commit was created while MERGE_HEAD was present"
git diff --quiet -- .beads/issues.jsonl \
  || fail "the export ran mid-merge and dirtied the working tree"
echo "PASS"

# Same guard, via CHERRY_PICK_HEAD, which post-commit genuinely does reach.
before="$(git rev-parse HEAD)"
touch "$(git rev-parse --git-dir)/CHERRY_PICK_HEAD"
bash "$SANDBOX/scripts/beads-auto-export.sh" || true
rm -f "$(git rev-parse --git-dir)/CHERRY_PICK_HEAD"
[ "$(git rev-parse HEAD)" = "$before" ] \
  || fail "an export commit was created during a cherry-pick"
echo "PASS"

# ─── 6. opt-out ───────────────────────────────────────────────────────

echo "=== 6: BEADS_NO_AUTO_EXPORT=1 disables it ==="
echo work6 > other.txt
BEADS_NO_AUTO_EXPORT=1 git commit -q -m "work6" -- other.txt
[ "$(git log -1 --format=%s)" = "work6" ] || fail "opt-out ignored"
echo "PASS"

# ─── 7. an uncommitted hand-export is still committed ─────────────────

echo "=== 7: a hand-run export that was never committed gets committed ==="
# The probe compares the working tree to Dolt, so after a manual export it
# reports "in sync" — while HEAD still holds the stale copy, and only HEAD is
# pushed. Committing on the probe alone leaves that change stranded forever.
export DOLT_IDS="a b c d remote-only e f"
bd export --output .beads/issues.jsonl >/dev/null   # by hand, not committed
git diff --quiet HEAD -- .beads/issues.jsonl && fail "fixture wrong: expected an uncommitted export"
echo work7 > other.txt
git commit -q -m "work7" -- other.txt
[ "$(git log -1 --format=%s)" = "beads: sync export (automated)" ] \
  || fail "an uncommitted export was left stranded: $(git log -1 --format=%s)"
git diff --quiet HEAD -- .beads/issues.jsonl \
  || fail "the export is still uncommitted after the hook ran"
echo "PASS"

# ─── 8. a broken probe complains instead of going quiet ───────────────

echo "=== 8: a failing probe warns loudly and exports nothing ==="
# The probe is the only thing standing between "beads changed" and "the export
# is committed". When it breaks, every commit still succeeds, so a silent skip
# looks exactly like a repo with no bead changes — which is how the mechanism
# this replaced managed to report success while going two days stale.
cp "$SANDBOX/scripts/check_beads_jsonl_dolt_sync.py" "$SANDBOX/checker.bak"
cat > "$SANDBOX/scripts/check_beads_jsonl_dolt_sync.py" <<'BROKEN'
import sys
print("simulated: bd sql failed (schema mismatch)", file=sys.stderr)
sys.exit(2)
BROKEN

export DOLT_IDS="a b c d remote-only e f g"
before="$(git rev-parse HEAD)"
echo work8 > other.txt
warn="$(git commit -q -m "work8" -- other.txt 2>&1 >/dev/null)"

[ "$(git log -1 --format=%s)" = "work8" ] \
  || fail "a broken probe still produced an export commit: $(git log -1 --format=%s)"
[ "$(git rev-list --count "$before"..HEAD)" = "1" ] \
  || fail "expected exactly one commit when the probe is broken"
case "$warn" in
  *"NOT being exported"*) ;;
  *) fail "a broken probe was silent; stderr was: $warn" ;;
esac
case "$warn" in
  *"schema mismatch"*) ;;
  *) fail "the underlying error was not surfaced; stderr was: $warn" ;;
esac
[ "$(status_field result)" = '"probe_failed"' ] || fail "probe failure left no durable evidence"
cp "$SANDBOX/checker.bak" "$SANDBOX/scripts/check_beads_jsonl_dolt_sync.py"
echo "PASS"

# ─── 9. preserve-and-flag: safe rows apply while others are pending ───

echo "=== 9: a new database row is published while an unimported transport row is preserved ==="
# Bring the file back in step with the database first (g exists in both).
git commit -q -m "work9-prep" --allow-empty
[ "$(git log -1 --format=%s)" = "beads: sync export (automated)" ] || fail "fixture: expected g to be exported"
printf '{"_type":"issue","id":"pulled-h","title":"from zklw","updated_at":"2026-03-01T00:00:00Z"}\n' >> .beads/issues.jsonl
git add .beads/issues.jsonl
git -c core.hooksPath=/dev/null commit -q -m "pulled h"
export DOLT_IDS="a b c d remote-only e f g i"       # i created here; h never imported
echo work9 > other.txt
warn="$(git commit -q -m "work9" -- other.txt 2>&1 >/dev/null)"

[ "$(git log -1 --format=%s)" = "beads: sync export (automated)" ] \
  || fail "a database-side row was held back because an unrelated row was pending: $(git log -1 --format=%s)"
grep -q '"pulled-h"' .beads/issues.jsonl || fail "the unimported transport row was exported away"
grep -q '"id":"i"' .beads/issues.jsonl || fail "the new database row was not published"
case "$warn" in
  *"INCOMPLETE"*"beads-import-merged.sh --retry"*) ;;
  *) fail "the pending import was not reported with its recovery command; stderr: $warn" ;;
esac
echo "PASS"

# ─── 10. a conflict keeps the transport version and both copies ───────

echo "=== 10: same updated_at, different content -> transport version kept, evidence written ==="
export DOLT_IDS="a b c d remote-only e f g i pulled-h"
# Both hosts edited 'i' in the same second, differently. The transport holds
# zklw's version; the database holds ours.
python3 - <<'PY'
import json, re
lines = open(".beads/issues.jsonl").read().splitlines()
out = []
for line in lines:
    row = json.loads(line)
    if row["id"] == "i":
        row.update(title="renamed on zklw", updated_at="2026-04-01T00:00:00Z")
    if row["id"] == "pulled-h":
        pass
    out.append(json.dumps(row, separators=(",", ":")))
open(".beads/issues.jsonl", "w").write("\n".join(out) + "\n")
PY
git add .beads/issues.jsonl
git -c core.hooksPath=/dev/null commit -q -m "pulled zklw rename of i"
# Baseline (HEAD) now carries zklw's version; the database moved from the
# original, so both changed since the baseline the database last matched.
export DOLT_OVERRIDES='{"_type":"issue","id":"remote-only","title":"from zklw","updated_at":"2026-02-01T00:00:00Z"}
{"_type":"issue","id":"pulled-h","title":"from zklw","updated_at":"2026-03-01T00:00:00Z"}
{"_type":"issue","id":"i","title":"renamed on the mac","status":"open","updated_at":"2026-04-01T00:00:00Z","comment_count":0}'
echo work10 > other.txt
warn="$(git commit -q -m "work10" -- other.txt 2>&1 >/dev/null)"

grep -q '"renamed on zklw"' .beads/issues.jsonl || fail "the transport version of a conflicted row was overwritten"
grep -q '"renamed on the mac"' .beads/issues.jsonl && fail "a conflict was resolved by picking the database side"
case "$warn" in
  *"INCOMPLETE"*"conflicts"*" i"*) ;;
  *) fail "the conflict was not reported by id; stderr: $warn" ;;
esac
ev="$(ls -d .beads/transport/evidence/*/ | tail -1)"
[ -f "$ev/i.transport.json" ] && [ -f "$ev/i.database.json" ] \
  || fail "both versions of the conflict were not preserved under $ev"
grep -q "renamed on the mac" "$ev/i.database.json" || fail "evidence does not hold the database version"
[ "$(status_field conflicts | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["reason"])')" = "equal_updated_at_different_content" ] \
  || fail "status.json does not carry the conflict reason"
echo "PASS"

# ─── 11. an edit the high-water mark cannot see is still exported ─────

echo "=== 11: an old task edited with a timestamp below the file's max is exported ==="
# Resolve the conflict out of the way: the database now agrees with the transport.
export DOLT_OVERRIDES='{"_type":"issue","id":"remote-only","title":"from zklw","updated_at":"2026-02-01T00:00:00Z"}
{"_type":"issue","id":"pulled-h","title":"from zklw","updated_at":"2026-03-01T00:00:00Z"}
{"_type":"issue","id":"i","title":"renamed on zklw","status":"open","updated_at":"2026-04-01T00:00:00Z","comment_count":0}
{"_type":"issue","id":"a","title":"a, edited here","status":"open","updated_at":"2026-01-15T00:00:00Z","comment_count":0}'
echo work11 > other.txt
git commit -q -m "work11" -- other.txt 2>/dev/null
[ "$(git log -1 --format=%s)" = "beads: sync export (automated)" ] \
  || fail "an edit below max(updated_at) was not exported: $(git log -1 --format=%s)"
grep -q '"a, edited here"' .beads/issues.jsonl || fail "the edited row did not reach the transport"
echo "PASS"

# ─── 12. concurrent transport operations are serialized ───────────────

echo "=== 12: a held transport lock defers the export instead of racing it ==="
export DOLT_IDS="a b c d remote-only e f g i pulled-h j"
# Hold the lock the way another worktree of the same database would: a
# process that acquired it and is still inside its transport operation.
rm -f holder.inside holder.leave
bash -c '
  . scripts/lib-beads-transport.sh
  beads_transport_lock 20 || exit 1
  : > holder.inside
  while [ ! -f holder.leave ]; do sleep 0.05; done
  beads_transport_unlock
' &
holder=$!
while [ ! -f holder.inside ]; do sleep 0.05; done
before="$(git rev-parse HEAD)"
echo work12 > other.txt
warn="$(BEADS_TRANSPORT_LOCK_WAIT=1 git commit -q -m "work12" -- other.txt 2>&1 >/dev/null)"
[ "$(git rev-list --count "$before"..HEAD)" = "1" ] || fail "an export ran while the transport lock was held"
grep -q '"id":"j"' .beads/issues.jsonl && fail "the transport was written while the lock was held"
case "$warn" in *"holds the lock"*) ;; *) fail "the deferred export was silent; stderr: $warn" ;; esac
[ "$(status_field result)" = '"deferred"' ] || fail "the deferral left no durable evidence"
# The holder dies without releasing (a killed hook). The kernel drops the
# flock with it, so the next commit proceeds instead of waiting on a ghost.
kill -9 "$holder"; wait "$holder" 2>/dev/null || true
echo work12b > other.txt
BEADS_TRANSPORT_LOCK_WAIT=5 git commit -q -m "work12b" -- other.txt 2>/dev/null
grep -q '"id":"j"' .beads/issues.jsonl || fail "a dead holder's lock blocked the export"
bash -c '. scripts/lib-beads-transport.sh; beads_transport_lock_held' && fail "the lock was not released after the export"
echo "PASS"

# ─── 13. the transport is never replaced if it moved under the merge ──

echo "=== 13: a transport that changes while the merge is computed is left alone ==="
export DOLT_IDS="a b c d remote-only e f g i pulled-h j k"
echo work13 > other.txt
warn="$(BD_STUB_TOUCH_TRANSPORT="$SANDBOX/.beads/issues.jsonl" git commit -q -m "work13" -- other.txt 2>&1 >/dev/null)"
[ "$(git log -1 --format=%s)" = "work13" ] || fail "the export committed over a transport that changed underneath it"
grep -q '"id":"k"' .beads/issues.jsonl && fail "the merged file replaced a transport that had moved"
grep -q '"id":"racer"' .beads/issues.jsonl || fail "fixture: the concurrent write did not land"
case "$warn" in *"changed while the merge"*) ;; *) fail "the abort was silent; stderr: $warn" ;; esac
[ "$(status_field result)" = '"aborted"' ] || fail "the abort left no durable evidence"
echo "PASS"

# ─── 14. a conflict stays a conflict across consecutive commits ───────

echo "=== 14: after a partial export commits the transport side, the next pass does not publish the database side ==="
# Baseline A (verified), transport C (pulled from zklw), database B (edited
# here). Pass 1: conflict, transport keeps C, and an unrelated database row
# makes the export commit. If provenance were HEAD, pass 2 would see
# transport == HEAD and read B as a fresh one-sided change. It must not.
export DOLT_IDS="a b c d remote-only e f g i pulled-h j k racer"
export DOLT_OVERRIDES='{"_type":"issue","id":"remote-only","title":"from zklw","updated_at":"2026-02-01T00:00:00Z"}
{"_type":"issue","id":"pulled-h","title":"from zklw","updated_at":"2026-03-01T00:00:00Z"}
{"_type":"issue","id":"i","title":"renamed on zklw","status":"open","updated_at":"2026-04-01T00:00:00Z","comment_count":0}
{"_type":"issue","id":"a","title":"a, edited here","status":"open","updated_at":"2026-01-15T00:00:00Z","comment_count":0}'
echo settle > other.txt
git commit -q -m "settle" -- other.txt 2>/dev/null            # k and racer verified, baseline moves
[ "$(git log -1 --format=%s)" = "beads: sync export (automated)" ] || fail "fixture: expected a settling export"
# zklw edits k (transport side, pulled); we edit k too (database side), later.
python3 - <<'PY'
import json
lines = open(".beads/issues.jsonl").read().splitlines()
out = []
for line in lines:
    row = json.loads(line)
    if row["id"] == "k":
        row.update(title="k per zklw", updated_at="2026-05-01T00:00:00Z")
    out.append(json.dumps(row, separators=(",", ":")))
open(".beads/issues.jsonl", "w").write("\n".join(out) + "\n")
PY
git add .beads/issues.jsonl
git -c core.hooksPath=/dev/null commit -q -m "pulled zklw edit of k"
export DOLT_OVERRIDES="$DOLT_OVERRIDES
{\"_type\":\"issue\",\"id\":\"k\",\"title\":\"k per the mac\",\"status\":\"open\",\"updated_at\":\"2026-06-01T00:00:00Z\",\"comment_count\":0}"
export DOLT_IDS="$DOLT_IDS m"                                  # unrelated new row forces a commit
echo work14 > other.txt
warn="$(git commit -q -m "work14" -- other.txt 2>&1 >/dev/null)"
[ "$(git log -1 --format=%s)" = "beads: sync export (automated)" ] || fail "pass 1 did not commit the unrelated row"
grep -q '"k per zklw"' .beads/issues.jsonl || fail "pass 1 overwrote the transport side of the conflict"
case "$warn" in *"conflicts"*" k"*) ;; *) fail "pass 1 did not report the conflict; stderr: $warn" ;; esac
# Pass 2: HEAD now holds C; the database still holds B.
export DOLT_IDS="$DOLT_IDS n"
echo work14b > other.txt
warn="$(git commit -q -m "work14b" -- other.txt 2>&1 >/dev/null)"
grep -q '"k per zklw"' .beads/issues.jsonl || fail "pass 2 published the database side of a conflict the previous pass had flagged"
grep -q '"k per the mac"' .beads/issues.jsonl && fail "the conflict was silently reclassified as one-sided on the second pass"
case "$warn" in *"conflicts"*" k"*) ;; *) fail "pass 2 forgot the conflict; stderr: $warn" ;; esac
python3 -c 'import json; c=json.load(open(".beads/transport/conflicts.json"))["records"]["k"]; assert c["first_seen"] < c["last_seen"] or c["first_seen"] <= c["last_seen"], c' \
  || fail "conflicts.json does not carry the conflict across passes"
echo "PASS"

# ─── 15. a pulled, unimported row plus a local edit is a conflict ─────

echo "=== 15: a local edit to a bead whose newer version was pulled but never imported is not exported over it ==="
# With HEAD as provenance the pulled row equals HEAD, so the local edit would
# read as one-sided and overwrite the other host's newer work in the transport.
python3 - <<'PY'
import json
lines = open(".beads/issues.jsonl").read().splitlines()
out = []
for line in lines:
    row = json.loads(line)
    if row["id"] == "m":
        row.update(title="m per zklw", updated_at="2026-07-01T00:00:00Z")
    out.append(json.dumps(row, separators=(",", ":")))
open(".beads/issues.jsonl", "w").write("\n".join(out) + "\n")
PY
git add .beads/issues.jsonl
git -c core.hooksPath=/dev/null commit -q -m "pulled zklw edit of m (not imported)"
export DOLT_OVERRIDES="$DOLT_OVERRIDES
{\"_type\":\"issue\",\"id\":\"m\",\"title\":\"m per the mac\",\"status\":\"open\",\"updated_at\":\"2026-07-02T00:00:00Z\",\"comment_count\":0}"
echo work15 > other.txt
warn="$(git commit -q -m "work15" -- other.txt 2>&1 >/dev/null)"
grep -q '"m per zklw"' .beads/issues.jsonl || fail "a local edit overwrote a pulled row that was never imported"
case "$warn" in *"conflicts"*" m"*|*"conflicts"*"m "*|*"conflicts"*"m"*) ;; *) fail "the conflict was not reported; stderr: $warn" ;; esac
echo "PASS"

echo "PASS: beads-auto-export ordering"
