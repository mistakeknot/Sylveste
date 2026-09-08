#!/usr/bin/env bash
# Shared pieces of the Beads git transport: state directory, durable log,
# serialization across worktrees, and a bounded process runner.
#
# Sourced by scripts/beads-auto-export.sh, scripts/beads-import-merged.sh and
# scripts/beads-confirm-deletion.sh. Every function is fail-safe for callers
# that run inside git hooks: nothing here exits the caller's shell.
#
# State lives in <toplevel>/.beads/transport/ (gitignored):
#   status.json            last export/import outcome — the durable evidence
#   pending-import.json    an import that did not complete, with before/after
#   pending-import.jsonl   the exact batch that still needs to land
#   evidence/<stamp>/      both versions of every conflicted record (private)
#   log                    one line per transport event

beads_transport_root() {
  git rev-parse --show-toplevel 2>/dev/null
}

beads_transport_state_dir() {
  local root="${1:-$(beads_transport_root)}"
  [ -n "$root" ] || return 1
  # Pending batches and conflict evidence hold record content that was
  # deliberately not published; the directory is this user's alone.
  if [ ! -d "$root/.beads/transport" ]; then
    mkdir -p "$root/.beads/transport" 2>/dev/null || return 1
    chmod 700 "$root/.beads/transport" 2>/dev/null || true
  fi
  printf '%s\n' "$root/.beads/transport"
}

# beads_capture_bounded <seconds> <command...>  -> stdout of the command
# Exit 124 on timeout; the group is killed, as in beads_run_bounded.
beads_capture_bounded() {
  local secs="$1"; shift
  python3 - "$secs" "$@" <<'PY'
import os, signal, subprocess, sys, time
secs = float(sys.argv[1]); cmd = sys.argv[2:]
proc = subprocess.Popen(cmd, start_new_session=True, stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL, text=True)
def alive(pgid):
    try:
        os.killpg(pgid, 0); return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
try:
    out, _ = proc.communicate(timeout=secs)
    sys.stdout.write(out); sys.exit(proc.returncode)
except subprocess.TimeoutExpired:
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(proc.pid, sig)
        except ProcessLookupError:
            break
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            proc.poll()
            if not alive(proc.pid): break
            time.sleep(0.05)
        else:
            continue
        break
    sys.exit(124)
PY
}

beads_transport_log() {
  local dir
  dir="$(beads_transport_state_dir)" || return 0
  printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" >>"$dir/log" 2>/dev/null || true
}

# The database bd actually talks to from this checkout, as bd reports it.
#
# Run FROM the checkout, never `bd -C <checkout>`: in a linked git worktree
# bd 1.1.2's -C walks up from the path without following the worktree's
# .git file, and resolves whatever .beads/ sits above the worktree — on
# Clavain that is the ~/projects workspace database, not this project's.
# Measured 2026-09-07, the same shape as sylveste-vqlu (a 458-row export of
# the wrong project over a 3,822-row transport, exit 0).
#
# Prefers the structured `bd context --json` (beads_dir, project_id,
# is_worktree — verified 2026-09-07 to name the main checkout's .beads from
# a linked worktree) and falls back to the legacy `bd info` text. Both are
# run --readonly --sandbox: a probe must never write or push. Bounded: they
# open the database, and a wedged Dolt server would otherwise hang the hook
# before the lock — which has its own timeout — is even reached.
#
# Both lookups are normalised to ONE identity: the physical path of the
# `.beads` directory. `context` reports it directly; legacy `info` reports the
# data directory beneath it (`.beads/dolt`, `.beads/embeddeddolt`), which is
# walked up to the `.beads` ancestor. A result that is not a `.beads`
# directory is no identity at all — the function fails, and so does anything
# that needed it. Two processes must never lock, export or import under
# different names for the same database because they asked bd differently.
_beads_transport_normalize_beads_dir() {
  local path="$1" real
  [ -n "$path" ] || return 1
  if [ -d "$path" ]; then
    real="$(cd "$path" && pwd -P)"
  else
    real="$( (cd "$(dirname "$path")" 2>/dev/null && pwd -P) || return 1)/$(basename "$path")"
  fi
  while [ "$real" != "/" ] && [ -n "$real" ]; do
    if [ "$(basename "$real")" = ".beads" ]; then
      printf '%s\n' "$real"
      return 0
    fi
    real="$(dirname "$real")"
  done
  return 1
}

beads_transport_database() {
  local root="${1:-$(beads_transport_root)}" out dir
  command -v bd >/dev/null 2>&1 || return 1
  out="$(cd "$root" && beads_capture_bounded "${BEADS_INFO_TIMEOUT:-15}" bd --readonly --sandbox context --json 2>/dev/null)" || out=""
  dir="$(printf '%s' "$out" | python3 -c '
import json, sys
raw = sys.stdin.read()
start = raw.find("{")
try:
    d = json.loads(raw[start:]) if start >= 0 else {}
except Exception:
    d = {}
print(d.get("beads_dir") or "")' 2>/dev/null)"
  if [ -z "$dir" ]; then
    dir="$( (cd "$root" && beads_capture_bounded "${BEADS_INFO_TIMEOUT:-15}" bd --readonly --sandbox info 2>/dev/null) \
      | sed -n 's/^Database:[[:space:]]*//p' | head -1)"
  fi
  _beads_transport_normalize_beads_dir "$dir"
}

# beads_transport_project [root] -> project_id from `bd context --json`, or "".
beads_transport_project() {
  local root="${1:-$(beads_transport_root)}"
  command -v bd >/dev/null 2>&1 || return 1
  (cd "$root" && beads_capture_bounded "${BEADS_INFO_TIMEOUT:-15}" bd --readonly --sandbox context --json 2>/dev/null) \
    | python3 -c '
import json, sys
raw = sys.stdin.read(); start = raw.find("{")
try:
    print((json.loads(raw[start:]) if start >= 0 else {}).get("project_id") or "")
except Exception:
    print("")' 2>/dev/null
}

# The .beads/ directory the transport is allowed to speak for: the main
# checkout's, which every linked worktree of this repository shares.
beads_transport_expected_beads_dir() {
  local root="${1:-$(beads_transport_root)}" common
  common="$(cd "$root" && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  printf '%s/.beads\n' "$(cd "$(dirname "$common")" && pwd -P)"
}

# beads_transport_identity_check [root]  -> 0 when bd's database is under the
# main checkout's .beads/; 1 otherwise, with the reason in
# BEADS_TRANSPORT_IDENTITY_ERROR. Every export and import calls this first:
# a hook that publishes or imports the wrong project's database exits 0 too.
#
# BEADS_TRANSPORT_EXPECT_PROJECT, when set, must also equal the project_id bd
# reports (the setup command passes --expect-project the same way).
beads_transport_identity_check() {
  local root="${1:-$(beads_transport_root)}" db expected db_real project
  export BEADS_TRANSPORT_IDENTITY_ERROR=""
  db="$(beads_transport_database "$root")"
  if [ -z "$db" ]; then
    BEADS_TRANSPORT_IDENTITY_ERROR="bd reports no database for $root (not initialised here?)"
    return 1
  fi
  expected="$(beads_transport_expected_beads_dir "$root")" || expected=""
  db_real="$db"     # already the normalised .beads directory
  if [ "$db_real" != "$expected" ]; then
    BEADS_TRANSPORT_IDENTITY_ERROR="bd resolves $db, which is not $expected — this checkout is bound to a different database"
    return 1
  fi
  if [ -n "${BEADS_TRANSPORT_EXPECT_PROJECT:-}" ]; then
    project="$(beads_transport_project "$root")"
    if [ "$project" != "$BEADS_TRANSPORT_EXPECT_PROJECT" ]; then
      BEADS_TRANSPORT_IDENTITY_ERROR="bd reports project '${project:-unknown}', expected $BEADS_TRANSPORT_EXPECT_PROJECT"
      return 1
    fi
  fi
  return 0
}

# Identity for the lock: the database bd resolves, canonicalised, so every
# worktree of one database shares one lock. There is deliberately NO
# fallback: a process that cannot learn its database and quietly locked on
# something else (the git common dir, say) would be "serialized" against
# nobody, while the export it went on to run wrote the same file as the
# process that could. Failure to identify is failure to lock.
beads_transport_identity() {
  local root="${1:-$(beads_transport_root)}" db=""
  db="$(beads_transport_database "$root")" || return 1
  [ -n "$db" ] || return 1
  printf '%s\n' "$db"
}

# The lock file lives in a location that is the same for every process on
# this host, whatever its environment: $TMPDIR differs between a login shell,
# a launchd job and an IDE-spawned hook on macOS, XDG_RUNTIME_DIR is set for
# some sessions and not others, and two processes locking in two directories
# are not locking at all. Only $HOME is used; with no HOME there is no lock
# and the caller refuses. BEADS_TRANSPORT_LOCK_BASE exists for tests only.
_beads_transport_lock_path() {
  local identity="$1" hash base
  hash="$(printf '%s' "$identity" | shasum 2>/dev/null | cut -c1-16)"
  [ -n "$hash" ] || hash="$(printf '%s' "$identity" | cksum | cut -d' ' -f1)"
  if [ -n "${BEADS_TRANSPORT_LOCK_BASE:-}" ]; then
    base="$BEADS_TRANSPORT_LOCK_BASE"
  elif [ -n "${HOME:-}" ]; then
    base="$HOME/.cache/sylveste-beads-transport"
  else
    return 1
  fi
  if [ ! -d "$base" ]; then
    mkdir -p "$base" 2>/dev/null && chmod 700 "$base" 2>/dev/null
  fi
  printf '%s/%s.flock\n' "$base" "$hash"
}

# beads_transport_lock [wait-seconds]  -> 0 acquired, 1 held elsewhere
#
# A kernel flock(2), held by a small child process for as long as the caller
# lives. The kernel owns exclusivity, so there is no owner file to read, no
# stale-lock takeover, and no moment at which a live holder's lock is touched
# by anyone else — the class of race that both a `rm -rf` and a rename-based
# takeover of a mkdir lock have (two waiters read the same dead owner; one
# acquires; the other removes or renames the fresh lock).
#
# The holder exits, releasing the lock, when either beads_transport_unlock
# signals it or its parent — the script that took the lock — is gone. A hook
# that is SIGKILLed mid-export therefore leaves nothing behind. The lock file
# carries the holder's identity for diagnostics only; nothing decides on it.
#
# flock(1) is not on macOS; python3's fcntl.flock is on both hosts.
beads_transport_lock() {
  local wait="${1:-${BEADS_TRANSPORT_LOCK_WAIT:-30}}" identity path out holder host
  if ! identity="$(beads_transport_identity)"; then
    BEADS_TRANSPORT_LOCK_HOLDER="identity unavailable: bd could not report this checkout's .beads directory"
    export BEADS_TRANSPORT_LOCK_HOLDER
    return 1
  fi
  if ! path="$(_beads_transport_lock_path "$identity")"; then
    BEADS_TRANSPORT_LOCK_HOLDER="no lock location: HOME is unset"
    export BEADS_TRANSPORT_LOCK_HOLDER
    return 1
  fi
  host="$(hostname -s 2>/dev/null || echo host)"
  out="$(mktemp "${TMPDIR:-/tmp}/sylveste-lock-out.XXXXXX")" || return 1

  python3 - "$path" "$wait" "$$" "$host" >"$out" 2>/dev/null <<'PY' &
import fcntl, os, signal, sys, time
path, wait, parent, host = sys.argv[1], float(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
fd = os.open(path, os.O_RDWR | os.O_CREAT, 0o600)
deadline = time.monotonic() + wait
while True:
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        break
    except (BlockingIOError, PermissionError):
        if time.monotonic() >= deadline or os.getppid() != parent:
            try:
                info = os.read(fd, 256).decode("utf-8", "replace").strip()
            except OSError:
                info = ""
            print("HELD " + (info or "unknown"), flush=True)
            sys.exit(1)
        time.sleep(0.05)
os.ftruncate(fd, 0); os.lseek(fd, 0, 0)
os.write(fd, f"{parent} {host} {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}\n".encode())
print("LOCKED", flush=True)
signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
while os.getppid() == parent:      # parent gone -> release by exiting
    time.sleep(0.2)
PY
  holder=$!
  while kill -0 "$holder" 2>/dev/null && ! grep -q '^LOCKED\|^HELD' "$out" 2>/dev/null; do
    sleep 0.05
  done
  if grep -q '^LOCKED' "$out" 2>/dev/null; then
    rm -f "$out"
    BEADS_TRANSPORT_LOCK_HOLDER_PID="$holder"
    BEADS_TRANSPORT_LOCK_FILE="$path"
    export BEADS_TRANSPORT_LOCK_HOLDER_PID BEADS_TRANSPORT_LOCK_FILE
    return 0
  fi
  BEADS_TRANSPORT_LOCK_HOLDER="$(sed -n 's/^HELD //p' "$out" 2>/dev/null | head -1)"
  export BEADS_TRANSPORT_LOCK_HOLDER
  rm -f "$out"
  wait "$holder" 2>/dev/null || true
  return 1
}

beads_transport_unlock() {
  if [ -n "${BEADS_TRANSPORT_LOCK_HOLDER_PID:-}" ]; then
    kill "$BEADS_TRANSPORT_LOCK_HOLDER_PID" 2>/dev/null || true
    wait "$BEADS_TRANSPORT_LOCK_HOLDER_PID" 2>/dev/null || true
  fi
  unset BEADS_TRANSPORT_LOCK_HOLDER_PID BEADS_TRANSPORT_LOCK_FILE
}

# beads_transport_lock_held  -> 0 when someone currently holds the lock
# (a probe for tests and `beads-transport-setup.sh check`; never a decision).
beads_transport_lock_held() {
  local path identity
  identity="$(beads_transport_identity)" || return 1
  path="$(_beads_transport_lock_path "$identity")" || return 1
  [ -e "$path" ] || return 1
  python3 - "$path" <<'PY'
import fcntl, os, sys
fd = os.open(sys.argv[1], os.O_RDWR)
try:
    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
except (BlockingIOError, PermissionError):
    sys.exit(0)
sys.exit(1)
PY
}

# beads_transport_status <key> <json-object>   -> 0 recorded, 1 not recorded
#
# Every writer owns one key; nobody's verdict may erase another's. The old
# read-merge-write of status.json lost updates: a writer that had read the
# file, was descheduled, and wrote after a newer writer put the OLD verdict
# back (an import refused for a held lock could revert the holder's fresh
# "incomplete" to a stale "verified"). So the durable record is now one file
# per key, status.d/<key>.json, replaced atomically and never merged — a write
# there cannot lose anyone else's key. status.json stays as the public view,
# rebuilt from those files under a sidecar flock held only for the rebuild,
# with a BOUNDED wait: a writer that cannot get it in time still has its key
# recorded, says so on stderr, and returns 0 — the record is durable and the
# next successful writer's rebuild picks it up. Only a key record that could
# not be written returns 1. Readers that need the freshest truth read
# status.d/ directly (beads_transport_status_read, the setup check).
#
# Transition: keys that exist only in a legacy status.json (written before
# status.d/ existed) are carried into the view until an authoritative per-key
# record replaces them. A key file that no longer parses is evidence, not
# garbage: it is left in place, the view keeps its previous value (if any)
# and lists the key under "_malformed", and status_read refuses to answer for
# it rather than fall back to something older.
beads_transport_status() {
  local dir
  dir="$(beads_transport_state_dir)" || { echo "beads: status not recorded — no state directory" >&2; return 1; }
  python3 - "$dir/status.json" "$1" "$2" <<'PY'
import fcntl, json, os, sys, tempfile, time
path, key, payload = sys.argv[1:4]
state_dir = os.path.dirname(path)
keys_dir = os.path.join(state_dir, "status.d")
wait = float(os.environ.get("BEADS_STATUS_LOCK_WAIT", "5"))
try:
    record = json.loads(payload)
except ValueError as exc:
    print(f"beads: status not recorded — payload for {key!r} is not JSON: {exc}", file=sys.stderr); sys.exit(1)
# 1. The durable record: one atomically replaced file per key. No read, no merge.
try:
    os.makedirs(keys_dir, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=keys_dir, prefix=f".{key}.")
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(record, fh, indent=2, sort_keys=True); fh.write("\n")
    os.chmod(tmp, 0o600)
    os.replace(tmp, os.path.join(keys_dir, key + ".json"))
except OSError as exc:
    print(f"beads: status NOT recorded for {key!r}: {exc}", file=sys.stderr); sys.exit(1)
# 2. The view, rebuilt under a short lock. Bounded: never wait on a stuck holder.
lock_path = os.path.join(state_dir, "status.lock")
try:
    lock_fd = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o600)
except OSError as exc:
    print(f"beads: status recorded for {key!r} but the view could not be locked: {exc}", file=sys.stderr); sys.exit(1)
deadline = time.monotonic() + wait
while True:
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB); break
    except (BlockingIOError, PermissionError):
        if time.monotonic() >= deadline:
            print(f"beads: status recorded for {key!r}; status.json view not rebuilt (lock held >{wait}s) — the next writer rebuilds it", file=sys.stderr)
            sys.exit(0)
        time.sleep(0.02)
try:
    previous = {}
    try:
        with open(path, encoding="utf-8") as fh:
            loaded = json.load(fh)
        if isinstance(loaded, dict):
            previous = loaded
    except Exception:
        pass
    # Start from the legacy/previous view so keys without a per-key record
    # survive the transition; authoritative records then replace them.
    view = {k: v for k, v in previous.items() if k != "_malformed"}
    malformed = []
    for name in sorted(os.listdir(keys_dir)):
        if not name.endswith(".json") or name.startswith("."):
            continue
        k = name[:-5]
        try:
            with open(os.path.join(keys_dir, name), encoding="utf-8") as fh:
                view[k] = json.load(fh)
        except Exception:
            # Visibly invalid in the public view: no reader of status.json can
            # mistake it for a current verdict. The previous value, if any, is
            # kept only as explicitly labelled last-known evidence.
            malformed.append(k)
            last_known = previous.get(k)
            if isinstance(last_known, dict) and last_known.get("_invalid"):
                last_known = last_known.get("last_known")
            view[k] = {"_invalid": "malformed authoritative record; kept as evidence under status.d/",
                       "last_known": last_known}
    if malformed:
        view["_malformed"] = malformed
    fd, tmp = tempfile.mkstemp(dir=state_dir, prefix=".status.")
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(view, fh, indent=2, sort_keys=True); fh.write("\n")
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)
except OSError as exc:
    print(f"beads: status recorded for {key!r} but status.json could not be rewritten: {exc}", file=sys.stderr); sys.exit(0)
finally:
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_UN)
    except OSError:
        pass
PY
}

# beads_transport_status_read <key>  -> 0 and the key's authoritative record;
# 1 when there is none; 2 when the authoritative record exists but is
# malformed (nothing older is returned in its place — an unreadable verdict
# is not a good one). The legacy view is consulted only when no per-key
# record exists at all.
beads_transport_status_read() {
  local dir
  dir="$(beads_transport_state_dir)" || return 1
  python3 - "$dir" "$1" <<'PY'
import json, os, sys
d, key = sys.argv[1:3]
record = os.path.join(d, "status.d", key + ".json")
if os.path.exists(record):
    try:
        with open(record, encoding="utf-8") as fh:
            print(json.dumps(json.load(fh))); sys.exit(0)
    except Exception as exc:
        print(f"beads: status record for {key!r} is malformed ({exc.__class__.__name__}); kept as evidence, not readable", file=sys.stderr)
        sys.exit(2)
try:
    with open(os.path.join(d, "status.json"), encoding="utf-8") as fh:
        legacy = json.load(fh)
except Exception:
    sys.exit(1)
data = legacy.get(key) if isinstance(legacy, dict) else None
if data is None:
    sys.exit(1)
print(json.dumps(data)); sys.exit(0)
PY
}

# beads_run_bounded <seconds> <command...>
# Runs the command in its own process group and kills the whole group on
# timeout, so a hung `bd import` cannot leave a child holding the Dolt server.
# Exit 124 on timeout (coreutils convention); the command's own status otherwise.
# Portable: python3 is required by the rest of the transport anyway, whereas
# `timeout` is not on macOS unless coreutils happens to be installed.
#
# Escalation is decided by the GROUP, not the leader. `bd` may exit on
# SIGTERM while a child it spawned ignores it; waiting on the leader alone
# would declare victory with that child still running. killpg(pgid, 0) is
# the probe: it fails only once no member is left.
beads_run_bounded() {
  local secs="$1"; shift
  python3 - "$secs" "$@" <<'PY'
import os, signal, subprocess, sys, time
secs = float(sys.argv[1]); cmd = sys.argv[2:]
proc = subprocess.Popen(cmd, start_new_session=True)
def alive(pgid):
    try:
        os.killpg(pgid, 0); return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
try:
    sys.exit(proc.wait(timeout=secs))
except subprocess.TimeoutExpired:
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(proc.pid, sig)
        except ProcessLookupError:
            break
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            proc.poll()                      # reap the leader; a zombie keeps the group alive
            if not alive(proc.pid): break
            time.sleep(0.05)
        else:
            continue                         # still members left: escalate
        break
    sys.exit(124)
PY
}

# beads_transport_head_blob <path-out> [ref]
# Materializes the committed transport (default HEAD) as the reconciliation
# baseline. Returns 1 when the ref has no such file (fresh repo), in which case
# the checker runs without a baseline and reports every difference as a conflict.
beads_transport_head_blob() {
  local out="$1" ref="${2:-HEAD}"
  git show "$ref:.beads/issues.jsonl" >"$out" 2>/dev/null
}

beads_transport_sha256() {
  python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1" 2>/dev/null
}
