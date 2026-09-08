#!/usr/bin/env bash
# Tests for scripts/lib-beads-transport.sh: identity, the lock, and the
# bounded runner.
#
# The lock and the runner are the kind of code whose bugs only show under
# contention, so the scenarios here create the contention rather than
# reasoning about it: several acquirers racing, a forced interleaving where a
# contender arrives while the holder is inside its critical section, a holder
# that dies without releasing, two processes with different TMPDIRs, a
# process that cannot learn its database, and a command whose child outlives
# its leader.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SANDBOX="$(mktemp -d)"
SANDBOX="$(cd "$SANDBOX" && pwd -P)"    # identities are physical paths
trap 'rm -rf "$SANDBOX"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

cp "$ROOT/scripts/lib-beads-transport.sh" "$SANDBOX/"
mkdir -p "$SANDBOX/bin" "$SANDBOX/repo/.beads/dolt"
cd "$SANDBOX/repo"
git init -q .
export BEADS_TRANSPORT_LOCK_BASE="$SANDBOX/locks"; mkdir -p "$BEADS_TRANSPORT_LOCK_BASE"

# Stub bd: `context --json` names the database this checkout is bound to;
# BD_STUB_CONTEXT_FAIL makes the lookup fail the way a wedged server would.
cat > "$SANDBOX/bin/bd" <<'STUB'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do case "$1" in --readonly|--sandbox) shift ;; *) break ;; esac; done
[ -n "${BD_STUB_CONTEXT_FAIL:-}" ] && { echo "Error: dial tcp: connection refused" >&2; exit 1; }
case "${1:-}" in
  context)
    [ -n "${BD_STUB_NO_CONTEXT:-}" ] && { echo "unknown command" >&2; exit 1; }   # legacy bd: no context command
    printf '{"beads_dir":"%s","project_id":"%s","is_worktree":false}\n' "$BD_STUB_BEADS_DIR" "${BD_STUB_PROJECT:-p1}" ;;
  info) echo "Database: ${BD_STUB_INFO_PATH:-$BD_STUB_BEADS_DIR/dolt}"; echo "Mode: direct" ;;
esac
STUB
chmod +x "$SANDBOX/bin/bd"
export PATH="$SANDBOX/bin:$PATH"
export BD_STUB_BEADS_DIR="$SANDBOX/repo/.beads"
lib() { bash -c ". $SANDBOX/lib-beads-transport.sh; $*"; }
# For background holders: exec so $! is the process that owns the lock holder.
libbg() { exec bash -c ". $SANDBOX/lib-beads-transport.sh; $*"; }

# ─── 1: six contenders, never two holders ─────────────────────────────
echo "=== 1: racing acquirers never overlap ==="
: > intervals.log
for _ in 1 2 3 4 5 6; do
  libbg '
    beads_transport_lock 20 || { echo "acquire failed" >&2; exit 1; }
    start=$(python3 -c "import time; print(time.monotonic_ns())")
    sleep 0.3
    end=$(python3 -c "import time; print(time.monotonic_ns())")
    echo "$start $end" >> intervals.log
    beads_transport_unlock
  ' &
done
wait
[ "$(wc -l < intervals.log | tr -d ' ')" = "6" ] || fail "not every acquirer got the lock: $(cat intervals.log)"
python3 - <<'PY' || fail "two holders overlapped"
rows = sorted(tuple(map(int, l.split())) for l in open("intervals.log") if l.strip())
for (s1, e1), (s2, e2) in zip(rows, rows[1:]):
    assert s2 >= e1, f"overlap: {rows}"
PY
lib beads_transport_lock_held && fail "the lock is still held after every acquirer released it"
echo "PASS"

# ─── 2: forced interleaving ───────────────────────────────────────────
echo "=== 2: a contender that arrives mid-critical-section waits for the release ==="
rm -f a.inside a.leave b.acquired overlap
libbg '
  beads_transport_lock 20 || exit 1
  : > a.inside
  while [ ! -f a.leave ]; do sleep 0.05; done
  [ -f b.acquired ] && echo "B acquired while A held" > overlap
  beads_transport_unlock
' &
a=$!
while [ ! -f a.inside ]; do sleep 0.05; done
libbg 'beads_transport_lock 20 || exit 1; : > b.acquired; beads_transport_unlock' &
b=$!
sleep 1
[ -f b.acquired ] && fail "B acquired the lock while A was inside its critical section"
lib beads_transport_lock_held || fail "nobody appears to hold the lock while A is inside"
: > a.leave
wait "$a"; wait "$b"
[ -f overlap ] && fail "$(cat overlap)"
[ -f b.acquired ] || fail "B never acquired after A released"
echo "PASS"

# ─── 3: a holder that dies without unlocking releases the lock ────────
echo "=== 3: a SIGKILLed holder leaves nothing to take over ==="
rm -f c.inside c.holder
libbg '
  beads_transport_lock 20 || exit 1
  echo "$BEADS_TRANSPORT_LOCK_HOLDER_PID" > c.holder
  : > c.inside
  sleep 60
' &
c=$!
while [ ! -f c.inside ]; do sleep 0.05; done
holder_pid="$(cat c.holder)"
kill -0 "$holder_pid" 2>/dev/null || fail "fixture: the lock holder child is not running"
kill -9 "$c"; wait "$c" 2>/dev/null || true
rc=0
lib 'BEADS_TRANSPORT_LOCK_WAIT=5 beads_transport_lock; beads_transport_unlock' || rc=$?
[ "$rc" -eq 0 ] || fail "the lock stayed held after its owner was SIGKILLed"
sleep 0.5
if kill -0 "$holder_pid" 2>/dev/null; then
  kill -9 "$holder_pid" 2>/dev/null || true
  fail "the orphaned lock holder (pid $holder_pid) survived its parent"
fi
echo "PASS"

# ─── 4: a live holder is waited on, then reported ─────────────────────
echo "=== 4: a held lock is reported with its holder, never stolen ==="
rm -f d.inside d.leave
libbg 'beads_transport_lock 20 || exit 1; : > d.inside; while [ ! -f d.leave ]; do sleep 0.05; done; beads_transport_unlock' &
d=$!
while [ ! -f d.inside ]; do sleep 0.05; done
out="$(lib 'if BEADS_TRANSPORT_LOCK_WAIT=1 beads_transport_lock; then echo STOLEN; else echo "held by: $BEADS_TRANSPORT_LOCK_HOLDER"; fi')"
case "$out" in
  STOLEN*) fail "a lock with a live owner was taken over" ;;
  "held by: "*"$(hostname -s)"*) ;;
  *) fail "the holder was not reported: $out" ;;
esac
: > d.leave; wait "$d"
echo "PASS"

# ─── 5: the lock path does not depend on the caller's environment ─────
echo "=== 5: different TMPDIR / XDG_RUNTIME_DIR, or a legacy lookup, all lock the same database on the same path ==="
rm -f e.inside e.leave f.acquired
mkdir -p "$SANDBOX/tmpA" "$SANDBOX/tmpB" "$SANDBOX/xdg"
TMPDIR="$SANDBOX/tmpA" libbg 'beads_transport_lock 20 || exit 1; : > e.inside; while [ ! -f e.leave ]; do sleep 0.05; done; beads_transport_unlock' &
e=$!
while [ ! -f e.inside ]; do sleep 0.05; done
out="$(TMPDIR="$SANDBOX/tmpB" lib 'if BEADS_TRANSPORT_LOCK_WAIT=1 beads_transport_lock; then echo UNSERIALIZED; else echo held; fi')"
[ "$out" = "held" ] || fail "a process with a different TMPDIR did not see the lock: $out"
# A process that learned its database from legacy `bd info` (data dir under
# .beads/) must contend for the SAME lock as one that used `bd context`.
out="$(BD_STUB_NO_CONTEXT=1 lib 'if BEADS_TRANSPORT_LOCK_WAIT=1 beads_transport_lock; then echo UNSERIALIZED; else echo held; fi')"
[ "$out" = "held" ] || fail "the legacy info lookup locked on a different identity: $out"
: > e.leave; wait "$e"
idC="$(lib 'beads_transport_identity')"; idI="$(BD_STUB_NO_CONTEXT=1 lib 'beads_transport_identity')"
[ "$idC" = "$idI" ] && [ "$idC" = "$(cd "$SANDBOX/repo/.beads" && pwd -P)" ] || fail "identities differ by lookup: context=$idC info=$idI"
pA="$(TMPDIR="$SANDBOX/tmpA" lib '_beads_transport_lock_path "$(beads_transport_identity)"')"
pB="$(TMPDIR="$SANDBOX/tmpB" lib '_beads_transport_lock_path "$(beads_transport_identity)"')"
[ "$pA" = "$pB" ] || fail "lock paths differ by TMPDIR: $pA vs $pB"
# Without the test override the base is under $HOME — the same whether
# XDG_RUNTIME_DIR is set, set differently, or unset; never under $TMPDIR.
pH1="$(HOME="$SANDBOX/home" TMPDIR="$SANDBOX/tmpA" XDG_RUNTIME_DIR="$SANDBOX/xdg" bash -c "unset BEADS_TRANSPORT_LOCK_BASE; . $SANDBOX/lib-beads-transport.sh; _beads_transport_lock_path x")"
pH2="$(HOME="$SANDBOX/home" TMPDIR="$SANDBOX/tmpB" bash -c "unset BEADS_TRANSPORT_LOCK_BASE XDG_RUNTIME_DIR; . $SANDBOX/lib-beads-transport.sh; _beads_transport_lock_path x")"
[ "$pH1" = "$pH2" ] || fail "lock base differs with XDG_RUNTIME_DIR: $pH1 vs $pH2"
case "$pH1" in "$SANDBOX/home/.cache/sylveste-beads-transport/"*) ;; *) fail "default lock base is not under HOME: $pH1" ;; esac
out="$(bash -c "unset HOME BEADS_TRANSPORT_LOCK_BASE; . $SANDBOX/lib-beads-transport.sh; if beads_transport_lock 1; then echo LOCKED; else echo \"refused: \$BEADS_TRANSPORT_LOCK_HOLDER\"; fi")"
case "$out" in "refused: no lock location"*) ;; *) fail "with no HOME the lock did not fail closed: $out" ;; esac
echo "PASS"

# ─── 6: no identity, no lock ──────────────────────────────────────────
echo "=== 6: a failed database lookup refuses to lock rather than locking on something else ==="
out="$(BD_STUB_CONTEXT_FAIL=1 lib 'if beads_transport_lock 2; then echo LOCKED; else echo "refused: $BEADS_TRANSPORT_LOCK_HOLDER"; fi')"
case "$out" in
  "refused: identity unavailable"*) ;;
  *) fail "a process that could not learn its database still acquired a lock: $out" ;;
esac
# A lookup that answers with something that is not a .beads directory is not
# an identity either: no lock, no fallback.
out="$(BD_STUB_NO_CONTEXT=1 BD_STUB_INFO_PATH="$SANDBOX/somewhere/else/dolt" lib 'if beads_transport_lock 2; then echo LOCKED; else echo "refused: $BEADS_TRANSPORT_LOCK_HOLDER"; fi')"
case "$out" in
  "refused: identity unavailable"*) ;;
  *) fail "a lookup outside any .beads directory still acquired a lock: $out" ;;
esac
# Two databases, two locks — the identity is the database, not the checkout.
libbg 'beads_transport_lock 20 || exit 1; : > g.inside; while [ ! -f g.leave ]; do sleep 0.05; done; beads_transport_unlock' &
g=$!
while [ ! -f g.inside ]; do sleep 0.05; done
mkdir -p "$SANDBOX/other/.beads"
out="$(BD_STUB_BEADS_DIR="$SANDBOX/other/.beads" lib 'if BEADS_TRANSPORT_LOCK_WAIT=1 beads_transport_lock; then echo independent; beads_transport_unlock; else echo blocked; fi')"
[ "$out" = "independent" ] || fail "a different database was serialized against this one: $out"
: > g.leave; wait "$g"
echo "PASS"

# ─── 7: identity check ────────────────────────────────────────────────
echo "=== 7: the identity check accepts the main checkout's database and refuses any other ==="
lib 'beads_transport_identity_check' || fail "the checkout's own database was refused"
out="$(BD_STUB_BEADS_DIR="$SANDBOX/other/.beads" lib 'if beads_transport_identity_check; then echo accepted; else echo "refused: $BEADS_TRANSPORT_IDENTITY_ERROR"; fi')"
case "$out" in "refused: bd resolves $SANDBOX/other/.beads"*) ;; *) fail "a foreign database was not refused: $out" ;; esac
out="$(BD_STUB_PROJECT=p2 BEADS_TRANSPORT_EXPECT_PROJECT=p1 lib 'if beads_transport_identity_check; then echo accepted; else echo "refused: $BEADS_TRANSPORT_IDENTITY_ERROR"; fi')"
case "$out" in "refused: bd reports project 'p2'"*) ;; *) fail "a project mismatch was not refused: $out" ;; esac
out="$(BD_STUB_CONTEXT_FAIL=1 lib 'if beads_transport_identity_check; then echo accepted; else echo "refused: $BEADS_TRANSPORT_IDENTITY_ERROR"; fi')"
case "$out" in "refused: bd reports no database"*) ;; *) fail "an unanswerable lookup was accepted: $out" ;; esac
echo "PASS"

# ─── 8: the bounded runner kills the whole group ──────────────────────
echo "=== 8: a child that ignores SIGTERM does not outlive the timeout ==="
marker=6113
rc=0
lib 'beads_run_bounded 1 bash -c "(trap \"\" TERM; exec sleep '"$marker"') & sleep '"$marker"'"' || rc=$?
[ "$rc" -eq 124 ] || fail "expected exit 124 on timeout, got $rc"
sleep 0.3
if pgrep -f "sleep $marker" >/dev/null 2>&1; then
  pkill -9 -f "sleep $marker" || true
  fail "a child ignoring SIGTERM survived the bounded runner"
fi
echo "PASS"

# ─── 9: a command that finishes in time returns its own status ────────
echo "=== 9: the runner is transparent for commands that finish ==="
rc=0
lib 'beads_run_bounded 5 bash -c "exit 7"' || rc=$?
[ "$rc" -eq 7 ] || fail "expected the command's own exit status 7, got $rc"
out="$(lib 'beads_capture_bounded 5 printf hello')"
[ "$out" = "hello" ] || fail "capture did not return stdout: $out"
rc=0
lib 'beads_capture_bounded 1 sleep 5' >/dev/null || rc=$?
[ "$rc" -eq 124 ] || fail "capture did not time out: $rc"
echo "PASS"

# ─── 10: state is private ─────────────────────────────────────────────
echo "=== 10: the transport state directory is created user-only ==="
mode="$(lib 'd=$(beads_transport_state_dir); stat -f %Lp "$d" 2>/dev/null || stat -c %a "$d"')"
[ "$mode" = "700" ] || fail "expected mode 700 on .beads/transport, got $mode"
echo "PASS"


# ─── 11: two interleaved status writers lose nothing ──────────────────
# The lost update: writer A reads the old view, is descheduled, writer B
# records a newer verdict, A resumes and writes the old verdict back. The
# pause is forced deterministically by patching json.load in A's process,
# exactly where the read-merge-write design was vulnerable.
echo "=== 11: a status writer paused after its read cannot revert a newer writer's record ==="
mkdir -p "$SANDBOX/repo/.beads/transport"
body="$(python3 - "$SANDBOX/lib-beads-transport.sh" <<'PY'
import sys
src = open(sys.argv[1]).read()
print(src.split("beads_transport_status() {", 1)[1].split("<<'PY'", 1)[1].split("\n", 1)[1].split("\nPY\n", 1)[0])
PY
)"
status="$SANDBOX/repo/.beads/transport/status.json"
rm -rf "$SANDBOX/repo/.beads/transport/status.d" "$status"
printf '{"import": {"result": "verified", "head": "old"}}\n' > "$status"
mkdir -p "$SANDBOX/repo/.beads/transport/status.d"; printf '{"result": "verified", "head": "old"}\n' > "$SANDBOX/repo/.beads/transport/status.d/import.json"
rm -f "$SANDBOX/ready" "$SANDBOX/release"
shim="import json, pathlib, time
_orig = json.load
def _paused(stream):
    v = _orig(stream)
    pathlib.Path('$SANDBOX/ready').touch()
    t = time.monotonic() + 15
    while not pathlib.Path('$SANDBOX/release').exists():
        if time.monotonic() > t: raise TimeoutError()
        time.sleep(0.01)
    return v
json.load = _paused
"
python3 -c "$shim$body" "$status" import_not_attempted '{"reason":"lock_held","at":"2026-09-07T20:00:00Z"}' 2>"$SANDBOX/a.err" &
a=$!
t=0; while [ ! -f "$SANDBOX/ready" ]; do sleep 0.05; t=$((t+1)); [ $t -gt 100 ] && fail "writer A never reached its read"; done
rc=0; python3 -c "$body" "$status" import '{"result":"incomplete","head":"new","reason":"conflicts","at":"2026-09-07T20:00:01Z"}' 2>"$SANDBOX/b.err" || rc=$?
# B's key is durably recorded whatever happened to the view.
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["result"]=="incomplete" and d["head"]=="new", d' "$SANDBOX/repo/.beads/transport/status.d/import.json" \
  || fail "writer B's record was not written while A held the view lock"
: > "$SANDBOX/release"; wait "$a" || true
python3 - "$status" <<'PY' || fail "the view lost writer B's newer import verdict: $(cat "$status")"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["import"] == {"result": "incomplete", "head": "new", "reason": "conflicts", "at": "2026-09-07T20:00:01Z"}, d
assert d["import_not_attempted"]["reason"] == "lock_held", d
PY
[ "$rc" -eq 0 ] || fail "writer B failed although its record was durably written: $(cat "$SANDBOX/b.err")"
grep -q "view not rebuilt" "$SANDBOX/b.err" || fail "B's bounded wait did not explain itself: $(cat "$SANDBOX/b.err")"
echo "PASS"

# ─── 12: a status record that cannot be written is a visible failure ──
echo "=== 12: an unwritable status record returns 1, and malformed records are kept as evidence, never read as good ==="
chmod 500 "$SANDBOX/repo/.beads/transport/status.d"
rc=0; out="$(lib 'beads_transport_status import "{\"result\":\"verified\",\"head\":\"newer\"}"' 2>&1)" || rc=$?
chmod 700 "$SANDBOX/repo/.beads/transport/status.d"
[ "$rc" -eq 1 ] || fail "an unwritable record returned $rc"
case "$out" in *"status NOT recorded"*) ;; *) fail "the failure was swallowed: $out" ;; esac
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["import"]["head"]=="new", d' "$status" \
  || fail "a failed write changed the view"
# A malformed authoritative record stays on disk, is listed in the view, keeps
# the view's previous value — and is NOT read as anything older or better.
printf 'not json\n' > "$SANDBOX/repo/.beads/transport/status.d/import.json"
lib 'beads_transport_status export "{\"result\":\"committed\"}"' || fail "a good write failed because another key is malformed"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["_malformed"]==["import"] and d["import"]["_invalid"] and d["import"]["last_known"]["head"]=="new" and "result" not in d["import"] and d["export"]["result"]=="committed", d' "$status" \
  || fail "the malformed key is not visibly invalid in the view, or last-known evidence was lost: $(cat "$status")"
[ "$(cat "$SANDBOX/repo/.beads/transport/status.d/import.json")" = "not json" ] || fail "the malformed record was rewritten"
out="$(lib 'beads_transport_status_read export')"; [ "$out" = '{"result": "committed"}' ] || fail "status_read did not return the fresh record: $out"
rc=0; out="$(lib 'beads_transport_status_read import' 2>&1)" || rc=$?
[ "$rc" -eq 2 ] || fail "status_read returned $rc for a malformed authoritative record (must be 2, never a legacy fallback): $out"
case "$out" in *"malformed"*) ;; *) fail "the malformed record was not named: $out" ;; esac
echo "PASS"

# ─── 13: legacy status.json keys survive the transition ───────────────
echo "=== 13: the first per-key write keeps every legacy key until its own record replaces it ==="
rm -rf "$SANDBOX/repo/.beads/transport/status.d"
printf '{"import": {"result": "incomplete", "reason": "conflicts", "at": "2026-09-07T19:00:00Z"}}\n' > "$status"
lib 'beads_transport_status export "{\"result\":\"committed\",\"at\":\"2026-09-07T19:01:00Z\"}"' || fail "the first per-key write failed"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["import"]["result"]=="incomplete" and d["export"]["result"]=="committed", d' "$status" \
  || fail "the legacy import evidence was erased by the first per-key write: $(cat "$status")"
out="$(lib 'beads_transport_status_read import')"
[ "$out" = '{"at": "2026-09-07T19:00:00Z", "reason": "conflicts", "result": "incomplete"}' ] || fail "legacy fallback for an absent record failed: $out"
lib 'beads_transport_status import "{\"result\":\"verified\",\"at\":\"2026-09-07T19:02:00Z\"}"' || fail "replacing the legacy key failed"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["import"]["result"]=="verified" and d["export"]["result"]=="committed", d' "$status" \
  || fail "the authoritative record did not replace the legacy key: $(cat "$status")"
echo "PASS"

echo "all transport-lib scenarios passed"
