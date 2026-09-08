#!/usr/bin/env bash
# Import the issue rows a merge actually brought in — bounded, verified, and
# recoverable — rather than all 3,900 on every pull.
#
# `bd import` on the whole file takes ~49s here and on zklw has not always
# finished at all. git already knows which lines a merge changed and every
# issue is exactly one line, so the batch is the '+' side of the diff between
# the commit before the merge and HEAD. bd still decides, row by row, whether
# each may be applied; that guarantee stays bd's (tests/test_bd_import_guard.py
# holds it to that). Only the batch, the bound, the classification and the
# evidence are ours.
#
# What changed from the first version, and why:
#   - An unresolvable before-commit used to mean `exec bd import <whole file>`,
#     unbounded. It now yields an explicit, recoverable result: pending state
#     naming what is unknown, exit 1, and `--full` as the deliberate way to
#     import everything (still classified, bounded and verified).
#   - A git error or an unparseable diff row used to be silently a smaller
#     batch. Both now fail the import and persist pending state.
#   - Rows are classified BEFORE bd sees them, with git's own provenance: for
#     a merge, the merge base of ours (the before-commit) and theirs (the
#     incoming parent). A record changed on both sides since the base is a
#     conflict whichever side the merge took and whatever the timestamps say;
#     it goes to evidence with every version and never to bd. That is what
#     protects an edit that was already exported (every commit exports), which
#     the local-state rule alone cannot see. Ancestry git cannot establish is
#     reported incomplete, never invented.
#   - The import is bounded on both hosts by scripts/lib-beads-transport.sh,
#     which kills the whole process group, not only the leader.
#   - Success is `bd import` exiting 0 with a parseable reply AND a native
#     verification (`check_beads_jsonl_dolt_sync.py --verify-import`) showing
#     every importable row present with the same content or held back by bd's
#     own guard. Until then the batch is pending: pending-import.json with the
#     exact before/after commits and the merge ancestry used, and
#     pending-import.jsonl with the rows.
#   - A pending batch is retried by the next merge that runs this hook and by
#     `--retry`, with the SAME ancestry it recorded (immutable provenance), and
#     only then does the range after it get its own. Git does NOT run
#     post-merge for a pull that is "Already up to date", so such a pull
#     retries nothing; every later commit and push announces the batch.
#
# Exit status: 0 verified (or nothing to do), 1 incomplete (pending state or
# open conflicts, message on stderr), 2 usage. The post-merge hook turns 1 into
# "git completed but Beads sync is incomplete" and skips the deletion ledger.
#
# Startup is explicit. A tracked transport with no bd, no helper library or
# no writable state directory exits 1 — the hook must not read "could not
# even start" as "nothing to import" and go on to apply deletions. Only a
# cloud session (read-only by policy) or an untracked transport exits 0.
#
# Usage: beads-import-merged.sh [<before-ref>] [--retry] [--full] [--status]
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "beads: import not run — not inside a git worktree" >&2; exit 1; }
cd "$ROOT" || exit 1
JSONL="$ROOT/.beads/issues.jsonl"
if ! git ls-files --error-unmatch .beads/issues.jsonl >/dev/null 2>&1; then
  exit 0                                     # no tracked transport here; nothing to carry
fi
if [ "${CLAUDE_CODE_REMOTE_ENVIRONMENT_TYPE:-}" = "cloud_default" ] || [ "${IS_SANDBOX:-}" = "yes" ]; then
  echo "beads: cloud session — bead import skipped (read-only by policy)" >&2
  exit 0
fi
[ -f "$JSONL" ] || { echo "beads: import NOT run — $JSONL is tracked but missing from the working tree" >&2; exit 1; }
command -v bd >/dev/null 2>&1 || { echo "beads: import NOT run — bd is not on PATH; the pulled rows are in the file but not in the database" >&2; exit 1; }
[ -f "$ROOT/scripts/lib-beads-transport.sh" ] || { echo "beads: import NOT run — scripts/lib-beads-transport.sh is missing" >&2; exit 1; }

# shellcheck source=scripts/lib-beads-transport.sh
. "$ROOT/scripts/lib-beads-transport.sh"
STATE="$(beads_transport_state_dir "$ROOT")" || { echo "beads: import NOT run — cannot create .beads/transport (state would not be durable)" >&2; exit 1; }
PENDING="$STATE/pending-import.json"
PENDING_BATCH="$STATE/pending-import.jsonl"
CHECKER="$ROOT/scripts/check_beads_jsonl_dolt_sync.py"
TIMEOUT="${BEADS_IMPORT_TIMEOUT:-120}"

# run_range's own working files. These are deliberately NOT "local" to
# run_range: the EXIT trap it installs only fires later, at actual process
# exit, by which point a normally-RETURNing run_range has already torn down
# its local scope — so a trap that closed over "local TMP" read an unbound
# variable under set -u on every successful (non-exit-from-inside-run_range)
# return. Globals stay valid for the trap to read no matter when it fires.
TMP=""
TMP_MERGE_N=0
# shellcheck disable=SC2329  # invoked only from the trap string set in run_range
cleanup_range_tmp() {
  [ -n "$TMP" ] || return 0
  rm -f -- "$TMP" "$TMP.batch" "$TMP.before" "$TMP.diff" "$TMP.err" "$TMP.out"
  local i=1
  while [ "$i" -le "$TMP_MERGE_N" ]; do
    rm -f -- "$TMP.base$i" "$TMP.ours$i" "$TMP.theirs$i"
    i=$((i + 1))
  done
}

MODE='diff'
BEFORE_ARG=""
for arg in "$@"; do
  case "$arg" in
    --retry) MODE=retry ;;
    --full) MODE=full ;;
    --status)
      if [ -f "$PENDING" ]; then cat "$PENDING"; exit 1; fi
      echo "no pending import"; exit 0 ;;
    -h|--help) sed -n '2,50p' "$0"; exit 0 ;;
    -*) echo "unknown flag: $arg" >&2; exit 2 ;;
    *) BEFORE_ARG="$arg" ;;
  esac
done

now() { date -u +%FT%TZ; }
json_str() { python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"; }
pending_get() { python3 -c 'import json,sys; v=json.load(open(sys.argv[1])).get(sys.argv[2]); print("" if v is None else v)' "$PENDING" "$1" 2>/dev/null; }

# write_pending <before|""> <after> <reason> <rows> [bump-attempts:0|1] [merges] [unused] [kind]
#   <merges> is the ancestry list run_range was given ("M:base:ours:theirs,..."
#   for a merge range, "before:before:before:after" for a fast-forward), kept
#   verbatim so a retry classifies with exactly the provenance this pass had.
write_pending() {
  local attempts=0
  [ -f "$PENDING" ] && attempts="$(python3 -c 'import json,sys; print(int(json.load(open(sys.argv[1])).get("attempts", 0)))' "$PENDING" 2>/dev/null || echo 0)"
  python3 - "$PENDING" "$1" "$2" "$3" "$4" "$attempts" "$(now)" "$PENDING_BATCH" "${5:-1}" "${6:-}" "${8:-}" <<'PY'
import json, os, sys
path, before, after, reason, rows, attempts, at, batch, bump, merges, kind = sys.argv[1:12]
sides = [dict(zip(("merge", "base", "ours", "theirs"), m.split(":"))) for m in merges.split(",") if m]
state = {
    "before": before or None, "after": after, "reason": reason,
    "rows": int(rows), "batch": batch if int(rows) > 0 else None,
    "attempts": int(attempts) + int(bump), "updated_at": at,
    "ancestry": {"kind": kind or None, "merges": merges or None, "sides": sides},
}
if os.path.exists(path):
    try:
        prev = json.load(open(path, encoding="utf-8"))
        state["first_failed_at"] = prev.get("first_failed_at", at)
    except Exception:
        state["first_failed_at"] = at
else:
    state["first_failed_at"] = at
fd = os.open(path + ".tmp", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w", encoding="utf-8") as fh:
    json.dump(state, fh, indent=2, sort_keys=True); fh.write("\n")
os.replace(path + ".tmp", path)
PY
}

# incomplete <before> <after> <reason> <rows> <message...>   (writes pending)
incomplete() {
  local before="$1" after="$2" reason="$3" rows="$4"; shift 4
  write_pending "$before" "$after" "$reason" "$rows" 1 "${R_MERGES:-}" "" "${R_KIND:-}"
  report_incomplete "$before" "$after" "$reason" "$rows" "$@"
}

# report_incomplete <before> <after> <reason> <rows> <message...>   (touches no pending state)
report_incomplete() {
  local before="$1" after="$2" reason="$3" rows="$4"; shift 4
  beads_transport_log "IMPORT INCOMPLETE ($reason): $*"
  beads_transport_status import "{\"at\":\"$(now)\",\"result\":\"incomplete\",\"reason\":$(json_str "$reason"),\"before\":$(json_str "$before"),\"after\":$(json_str "$after"),\"rows\":$rows,\"message\":$(json_str "$*")}" \
    || beads_transport_log "IMPORT INCOMPLETE ($reason): status record itself could not be written"
  echo "beads: import INCOMPLETE — $*" >&2
  echo "       The rows are still in .beads/issues.jsonl; the local database is behind the file." >&2
  [ -f "$PENDING" ] && echo "       Pending state: .beads/transport/pending-import.json" >&2
  if [ -n "$before" ] && [ "$reason" != "ancestry_unknown" ]; then
    echo "       Retry with:  scripts/beads-import-merged.sh --retry" >&2
  else
    [ "$reason" = "ancestry_unknown" ] && echo "       git cannot establish which side changed what, so nothing was classified." >&2
    echo "       Import the whole file deliberately (classified by local state only) with:  scripts/beads-import-merged.sh --full" >&2
  fi
  return 1
}

# complete <result> <detail-json> <has-batch:0|1>   -> exits 1 if the verdict could not be recorded
complete() {
  # Evidence first, then the pending state. A verified import whose verdict
  # cannot be written is not advertised as complete: the rows stay imported
  # (bd applied them; that is progress, not something to undo), the pending
  # batch (if there is one) stays so --retry re-verifies and re-records, and
  # the exit status keeps the hook from running the ledger on top of a result
  # nobody can see. With no batch there is nothing to retry: say so, and name
  # the exact re-run instead.
  beads_transport_log "import $1: $2"
  if ! beads_transport_status import "{\"at\":\"$(now)\",\"result\":\"$1\",\"head\":\"$(git rev-parse HEAD 2>/dev/null)\",\"detail\":$2}"; then
    beads_transport_log "IMPORT INCOMPLETE (status_not_recorded): verdict '$1' could not be written to .beads/transport"
    echo "beads: import $1, but the verdict could NOT be recorded under .beads/transport." >&2
    if [ "${3:-1}" -eq 1 ]; then
      echo "       The batch stays pending. Retry with:  scripts/beads-import-merged.sh --retry   (rows already applied are verified again, not re-imported)" >&2
    else
      echo "       No batch is pending (nothing needed importing). Fix .beads/transport, then re-run:  scripts/beads-import-merged.sh ${R_BEFORE:-ORIG_HEAD}" >&2
    fi
    exit 1
  fi
  rm -f "$PENDING" "$PENDING_BATCH"
}

# ─── The right database, then the lock ────────────────────────────────

# Neither failure below may touch pending-import.json or the pending batch:
# those belong to whichever import is running or last ran, and a process that
# could not even identify its database or take the lock has no business
# replacing them. Diagnostics go to stderr, the append-only log, and a
# separate status key; the exit status makes the hook report incomplete.
not_attempted() {   # not_attempted <reason> <message>
  beads_transport_log "IMPORT NOT ATTEMPTED ($1): $2"
  beads_transport_status import_not_attempted "{\"at\":\"$(now)\",\"reason\":$(json_str "$1"),\"head\":$(json_str "$(git rev-parse HEAD 2>/dev/null)"),\"message\":$(json_str "$2")}" \
    || beads_transport_log "IMPORT NOT ATTEMPTED ($1): status record itself could not be written"
  echo "beads: import NOT attempted — $2" >&2
}

# Importing into the wrong database is as silent as exporting from it.
if ! beads_transport_identity_check "$ROOT"; then
  not_attempted "database_identity" "$BEADS_TRANSPORT_IDENTITY_ERROR"
  echo "       Check with: scripts/beads-transport-setup.sh" >&2
  exit 1
fi

if ! beads_transport_lock; then
  not_attempted "lock_held" "another transport operation holds the lock (${BEADS_TRANSPORT_LOCK_HOLDER:-?}); its pending state is left untouched"
  echo "       Retry once it finishes: scripts/beads-import-merged.sh --retry" >&2
  exit 1
fi
trap 'beads_transport_unlock' EXIT

HEAD_NOW="$(git rev-parse HEAD 2>/dev/null)" || { echo "beads: cannot resolve HEAD" >&2; exit 1; }
[ -f "$CHECKER" ] || { echo "beads: import NOT run — scripts/check_beads_jsonl_dolt_sync.py is missing; rows cannot be classified or verified" >&2; exit 1; }

# ─── Git provenance for a range ───────────────────────────────────────

# ancestry <before> <after>  -> prints "<kind> <merges>" and returns 0, or
# prints the reason and returns 1 when git cannot say what happened.
#
# <before> must be an ancestor of <after> (a rebase or reset is not a range
# git can explain). EVERY two-parent merge in the range is inspected: the
# merge base of its parents is where two lines of history last agreed, and a
# record changed on both sides since then is a concurrent edit that some
# merge resolved — a conflict for us whichever side it took and whatever the
# timestamps say. This holds whether the merge diverged from <before> (we
# pulled while carrying exported edits), or happened entirely upstream with
# both parents descending from <before> (two hosts diverged after our tip and
# one of them merged), or neither: an arbitrary merge choice is never read as
# a deliberate resolution. A dependency PR merged upstream is harmless
# because its records did not diverge, not because of where its parents sit;
# a fast-forward across such merges is ordinary. An octopus merge is
# ambiguous and reported. The parent descending from <before> is labelled
# "ours" when there is exactly one; the rule is symmetric, so the label only
# names the evidence files.
#   kind ff:     no merge in the range; base = before, theirs = after.
#   kind merge:  one or more merges, listed as M:base:ours:theirs.
ancestry() {
  local before="$1" after="$2" m parents ours theirs base merges="" first second
  if ! git merge-base --is-ancestor "$before" "$after" 2>/dev/null; then
    echo "$(git rev-parse --short "$before") is not an ancestor of $(git rev-parse --short "$after") (a rebase or reset?)"
    return 1
  fi
  for m in $(git rev-list --merges "$before".."$after" 2>/dev/null); do
    parents="$(git rev-list --parents -n 1 "$m" | cut -d' ' -f2-)"
    if [ "$(printf '%s\n' "$parents" | wc -w | tr -d ' ')" -ne 2 ]; then
      echo "$(git rev-parse --short "$m") is an octopus merge"
      return 1
    fi
    first="${parents%% *}"; second="${parents##* }"
    ours="$first"; theirs="$second"
    if ! git merge-base --is-ancestor "$before" "$first" 2>/dev/null && git merge-base --is-ancestor "$before" "$second" 2>/dev/null; then
      ours="$second"; theirs="$first"
    fi
    base="$(git merge-base "$ours" "$theirs" 2>/dev/null)" || { echo "no common ancestor between the sides of $(git rev-parse --short "$m")"; return 1; }
    merges="${merges:+$merges,}$m:$base:$ours:$theirs"
  done
  if [ -n "$merges" ]; then
    echo "merge $merges"
  else
    echo "ff $before:$before:$before:$after"
  fi
}

# ─── One range: batch, classify, import, verify, record ───────────────

# run_range <before|""> <after> <kind> <merges>
#   <merges>: for kind merge, "M:base:ours:theirs,..."; for kind ff,
#   "before:before:before:after"; for kind full, "".
# Exits 1 on any incomplete result (pending state written where a batch
# exists). Returns 0 when the range is verified, so a follow-up range can run.
run_range() {
  local BEFORE="$1" AFTER="$2"
  R_BEFORE="$BEFORE"; R_KIND="$3"; R_MERGES="$4"
  local rows bad reason_scope

  TMP="$(mktemp "${TMPDIR:-/tmp}/beads-merged.XXXXXX")" || { incomplete "$BEFORE" "$AFTER" "mktemp_failed" 0 "mktemp failed"; exit 1; }
  chmod 600 "$TMP"
  TMP_MERGE_N=0
  trap 'cleanup_range_tmp; beads_transport_unlock' EXIT

  if [ "$R_KIND" = "full" ]; then
    cp "$JSONL" "$TMP"
    reason_scope="full file"
  else
    git diff --quiet "$BEFORE" "$AFTER" -- .beads/issues.jsonl 2>/dev/null
    local diff_rc=$?
    if [ $diff_rc -eq 0 ]; then
      # The range did not touch bead state. With a pending batch this cannot
      # happen (its rows are in the range); without one there is nothing to do.
      [ -f "$PENDING" ] && complete "verified" '{"rows":0,"note":"pending range no longer differs"}' 1
      return 0
    elif [ $diff_rc -ne 1 ]; then
      incomplete "$BEFORE" "$AFTER" "git_diff_failed" 0 "git diff exited $diff_rc"
      exit 1
    fi
    # Every added line of the diff is a candidate row — not only those that
    # begin with '{'. A row with leading whitespace is valid JSONL and must be
    # imported; a line that is not JSON at all must fail the import. The
    # '+++ ' file header is the one added-looking line that is not data. A
    # modified row shows up as a '-' for the old text and a '+' for the new,
    # so the '+' side carries updates as well as creations. Rows that only
    # disappear are deletions, which travel through .beads/deletions.jsonl.
    if ! git diff "$BEFORE" "$AFTER" -- .beads/issues.jsonl >"$TMP.diff" 2>"$TMP.err"; then
      local msg; msg="$(head -1 "$TMP.err")"
      incomplete "$BEFORE" "$AFTER" "git_diff_failed" 0 "git diff: $msg"
      exit 1
    fi
    python3 - "$TMP.diff" "$TMP" <<'PY'
import sys
diff_path, out_path = sys.argv[1:3]
with open(diff_path, encoding="utf-8", errors="surrogateescape") as src, \
     open(out_path, "w", encoding="utf-8", errors="surrogateescape") as dst:
    for line in src:
        if line.startswith("+++ "):
            continue
        if line.startswith("+"):
            dst.write(line[1:] if line.endswith("\n") else line[1:] + "\n")
PY
    reason_scope="rows changed $(git rev-parse --short "$BEFORE")..$(git rev-parse --short "$AFTER") ($R_KIND)"
  fi

  # Every row must be a JSON object with a string id (or a memory record)
  # BEFORE it is handed to bd: bd aborts the whole file on a bad line, and the
  # abort reads like a stale-row skip unless one checks the error.
  local parse_err
  parse_err="$(python3 - "$TMP" <<'PY'
import json, sys
bad = []
n = 0
for i, line in enumerate(open(sys.argv[1], encoding="utf-8", errors="surrogateescape"), 1):
    if not line.strip():
        continue
    n += 1
    try:
        row = json.loads(line)
    except ValueError as exc:
        bad.append(f"line {i}: {exc.msg}"); continue
    if not isinstance(row, dict):
        bad.append(f"line {i}: not an object"); continue
    if row.get("_type") == "memory":
        if not isinstance(row.get("key"), str): bad.append(f"line {i}: memory without key")
    elif not isinstance(row.get("id"), str) or not row["id"]:
        bad.append(f"line {i}: missing string id")
print(n)
print("; ".join(bad[:5]))
PY
)"
  rows="$(printf '%s\n' "$parse_err" | sed -n 1p)"
  bad="$(printf '%s\n' "$parse_err" | sed -n 2p)"
  if [ -n "$bad" ]; then
    cp "$TMP" "$PENDING_BATCH" 2>/dev/null; chmod 600 "$PENDING_BATCH" 2>/dev/null
    incomplete "$BEFORE" "$AFTER" "batch_unparseable" "${rows:-0}" "diff rows are not valid records: $bad"
    exit 1
  fi

  if [ "${rows:-0}" -eq 0 ]; then
    complete "verified" "{\"rows\":0,\"scope\":$(json_str "$reason_scope")}" 0
    return 0
  fi

  # Persist the batch BEFORE running bd: a kill mid-import must leave the
  # exact rows, range and ancestry behind, not a guess reconstructed later.
  # If even that cannot be written there is nowhere to keep evidence, so
  # nothing proceeds.
  if ! { cp "$TMP" "$PENDING_BATCH" && chmod 600 "$PENDING_BATCH" && write_pending "$BEFORE" "$AFTER" "in_progress" "$rows" 0 "$R_MERGES" "" "$R_KIND"; } 2>/dev/null; then
    beads_transport_log "IMPORT INCOMPLETE (state_not_writable): $STATE is not writable"
    echo "beads: import INCOMPLETE — the pending state under .beads/transport could not be written; nothing was imported." >&2
    echo "       Fix the directory's permissions, then: scripts/beads-import-merged.sh $([ -n "$BEFORE" ] && echo "$BEFORE" || echo --full)" >&2
    exit 1
  fi

  # ─── Classify before bd sees a row ──────────────────────────────────
  local PROPOSAL="$STATE/state.proposed.json"; rm -f "$PROPOSAL"
  local BATCH="$TMP.batch"
  local -a side_args=()
  if [ -n "$BEFORE" ] && beads_transport_head_blob "$TMP.before" "$BEFORE"; then
    side_args+=(--before "$TMP.before")
  fi
  # Git provenance: a fast-forward from ours needs no merge sides; every
  # diverging merge contributes its base/ours/theirs transports. --full
  # passes neither, and the classifier holds differing rows accordingly.
  local i=0 m mb mo mt
  if [ "$R_KIND" = "ff" ]; then
    side_args+=(--git-provenance)
  elif [ "$R_KIND" = "merge" ]; then
    side_args+=(--git-provenance)
    for m in $(printf '%s' "$R_MERGES" | tr ',' ' '); do
      mb="$(printf '%s' "$m" | cut -d: -f2)"; mo="$(printf '%s' "$m" | cut -d: -f3)"; mt="$(printf '%s' "$m" | cut -d: -f4)"
      i=$((i + 1))
      TMP_MERGE_N="$i"
      beads_transport_head_blob "$TMP.base$i" "$mb" || : > "$TMP.base$i"
      beads_transport_head_blob "$TMP.ours$i" "$mo" || : > "$TMP.ours$i"
      beads_transport_head_blob "$TMP.theirs$i" "$mt" || : > "$TMP.theirs$i"
      side_args+=(--merge-side "$TMP.base$i" "$TMP.ours$i" "$TMP.theirs$i")
    done
  fi
  local plan prc
  plan="$(python3 "$CHECKER" --repo "$ROOT" --json --state-dir "$STATE" \
            --plan-import "$TMP" "${side_args[@]}" --write-batch "$BATCH" \
            --evidence-dir "$STATE/evidence" --propose-state "$PROPOSAL" 2>/dev/null)"
  prc=$?
  if [ -z "$plan" ] || [ $prc -ne 0 ]; then
    incomplete "$BEFORE" "$AFTER" "plan_failed" "$rows" "rows could not be classified before import (rc=$prc): $(printf '%s' "$plan" | python3 -c 'import json,sys; print("; ".join(json.load(sys.stdin).get("errors", [])))' 2>/dev/null)"
    exit 1
  fi
  local n_importable n_already n_conflicts conflict_ids
  read -r n_importable n_already n_conflicts conflict_ids <<EOF
$(printf '%s' "$plan" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(len(d.get("importable", [])), len(d.get("already_applied", [])), len(d.get("conflicts", [])),
      ",".join(c["id"] for c in d.get("conflicts", []))[:400] or "-")
')
EOF

  # Rows already equal on both sides are verified agreement as of now, and
  # the conflicts just found are state to carry; both are recorded before bd
  # runs. Importable rows join the baseline only after verification below.
  if ! python3 "$CHECKER" --repo "$ROOT" --state-dir "$STATE" --promote-state "$PROPOSAL" >/dev/null 2>&1; then
    incomplete "$BEFORE" "$AFTER" "state_not_writable" "$rows" \
      "the verified-baseline/conflict state under .beads/transport could not be written; nothing was imported"
    exit 1
  fi

  if [ "$n_importable" -eq 0 ]; then
    if [ "$n_conflicts" -gt 0 ]; then
      # Nothing bd may apply and something is conflicted. Not a pending
      # batch (a retry changes nothing until someone resolves it), but not
      # complete either; the conflicts are on record.
      rm -f "$PENDING" "$PENDING_BATCH"
      report_incomplete "$BEFORE" "$AFTER" "conflicts" "$rows" \
        "$n_conflicts of $rows incoming row(s) changed on both hosts and were NOT imported: $conflict_ids (every version under .beads/transport/evidence/, ids in conflicts.json)"
      exit 1
    fi
    complete "verified" "{\"rows\":$rows,\"already_applied\":$n_already,\"scope\":$(json_str "$reason_scope")}" 1
    return 0
  fi

  # ─── Import, bounded ────────────────────────────────────────────────
  # Observed on zklw: `bd import` blocked in futex_wait with an open socket
  # to its own Dolt server. Without a bound, `git pull` never returns.
  beads_run_bounded "$TIMEOUT" bd import --json "$BATCH" >"$TMP.out" 2>&1    # cwd is $ROOT; never -C (see lib)
  local rc=$?
  # bd's --json reply is pretty-printed over many lines. The complete object
  # is parsed, never a first line, and never interpolated as a fragment.
  local import_json
  import_json="$(python3 - "$TMP.out" <<'PY'
import json, sys
raw = open(sys.argv[1], encoding="utf-8", errors="replace").read()
start, end = raw.find("{"), raw.rfind("}")
if start < 0 or end <= start:
    sys.exit(1)
try:
    obj = json.loads(raw[start:end + 1])
except ValueError:
    sys.exit(1)
if not isinstance(obj, dict):
    sys.exit(1)
print(json.dumps(obj, separators=(",", ":")))
PY
)" || import_json=""
  if [ $rc -eq 124 ]; then
    incomplete "$BEFORE" "$AFTER" "timeout" "$rows" \
      "bd import timed out after ${TIMEOUT}s; $rows row(s) may not have landed (another bd process is likely holding the Dolt server)"
    exit 1
  elif [ $rc -ne 0 ]; then
    local msg=""
    [ -n "$import_json" ] && msg="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("error",""))' "$import_json" 2>/dev/null || true)"
    [ -n "$msg" ] || msg="$(tail -1 "$TMP.out")"
    incomplete "$BEFORE" "$AFTER" "bd_import_failed" "$rows" "bd import exited $rc: $msg"
    exit 1
  elif [ -z "$import_json" ]; then
    incomplete "$BEFORE" "$AFTER" "bd_reply_unparseable" "$rows" \
      "bd import exited 0 but its --json reply could not be parsed: $(head -c 200 "$TMP.out" | tr '\n' ' ')"
    exit 1
  fi

  # ─── Verify, natively ───────────────────────────────────────────────
  # bd exiting 0 is not evidence the rows are in the database — its counters
  # report rows processed, not rows present. A private export compared
  # against the batch is: each row is there with the same content, or bd's
  # guard kept a local row that is at least as new.
  rm -f "$PROPOSAL"
  local verdict vrc
  verdict="$(python3 "$CHECKER" --repo "$ROOT" --json --state-dir "$STATE" \
               --verify-import "$BATCH" --propose-state "$PROPOSAL" \
               --evidence-dir "$STATE/evidence" 2>/dev/null)"
  vrc=$?
  if [ -z "$verdict" ]; then
    incomplete "$BEFORE" "$AFTER" "verify_failed" "$rows" "post-import verification produced no verdict (rc=$vrc)"
    exit 1
  fi
  local v_ok n_applied n_kept n_unapplied unapplied_ids
  read -r v_ok n_applied n_kept n_unapplied unapplied_ids <<EOF
$(printf '%s' "$verdict" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(str(d.get("ok", False)).lower(), len(d.get("applied", [])), len(d.get("kept_local", [])),
      len(d.get("unapplied", [])), ",".join(d.get("unapplied", [])[:20]) or "-")
')
EOF
  if [ "$v_ok" != "true" ]; then
    rm -f "$PROPOSAL"
    incomplete "$BEFORE" "$AFTER" "unverified" "$rows" \
      "bd import exited 0 but $n_unapplied of $n_importable importable row(s) are not in the database afterwards: $unapplied_ids"
    exit 1
  fi
  if ! python3 "$CHECKER" --repo "$ROOT" --state-dir "$STATE" --promote-state "$PROPOSAL" --applied >/dev/null 2>&1; then
    incomplete "$BEFORE" "$AFTER" "state_not_writable" "$rows" \
      "the import verified ($n_applied applied, $n_kept kept local) but the verified-baseline state under .beads/transport could not be written"
    exit 1
  fi

  # The detail record is built by json.dumps from parsed values only.
  local detail
  detail="$(python3 - "$rows" "$n_importable" "$n_already" "$n_applied" "$n_kept" "$n_conflicts" "$reason_scope" "$import_json" "$R_KIND" "$R_MERGES" <<'PY'
import json, sys
rows, imp, already, applied, kept, conflicts, scope, reply, kind, merges = sys.argv[1:11]
bd = json.loads(reply)
keep = ("created", "updated", "skipped", "ids", "updated_issues", "stale_skipped_ids", "tie_kept_local_ids")
sides = [dict(zip(("merge", "base", "ours", "theirs"), m.split(":"))) for m in merges.split(",") if m]
print(json.dumps({
    "rows": int(rows), "importable": int(imp), "already_applied": int(already), "applied": int(applied),
    "kept_local": int(kept), "conflicts": int(conflicts), "scope": scope,
    "ancestry": {"kind": kind or None, "merges": sides},
    "bd": {k: bd.get(k) for k in keep if k in bd},
}, separators=(",", ":")))
PY
)"
  if [ "$n_conflicts" -gt 0 ]; then
    # The importable rows landed and are verified; the conflicted ones did
    # not and will not until someone resolves them. Both facts are reported:
    # the batch is not "pending" (a retry changes nothing) but the sync is
    # not complete either.
    beads_transport_log "import verified with conflicts: $detail"
    if ! beads_transport_status import "{\"at\":\"$(now)\",\"result\":\"incomplete\",\"reason\":\"conflicts\",\"head\":\"$AFTER\",\"detail\":$detail}"; then
      echo "beads: the conflict verdict could NOT be recorded under .beads/transport; the batch stays pending until it is (--retry)." >&2
      exit 1
    fi
    rm -f "$PENDING" "$PENDING_BATCH"
    echo "beads: import applied $n_applied row(s), but $n_conflicts incoming row(s) changed on both hosts and were NOT imported: $conflict_ids" >&2
    echo "       Every version is under .beads/transport/evidence/; see .beads/transport/conflicts.json" >&2
    exit 1
  fi
  complete "verified" "$detail" 1
  return 0
}

# ─── Decide the range(s) ──────────────────────────────────────────────

open_conflicts() {   # prints the ids of unresolved conflicts, if any
  python3 -c 'import json,sys
try: print(" ".join(sorted(json.load(open(sys.argv[1])).get("records", {}))))
except Exception: print("")' "$STATE/conflicts.json" 2>/dev/null
}

if [ "$MODE" = "full" ]; then
  # No git provenance. Absent and already-equal rows apply; a differing
  # existing record is held as a conflict (no_git_provenance) — full scope is
  # not permission to choose an exported concurrent edit by timestamp.
  run_range "" "$HEAD_NOW" "full" ""
  exit 0
fi

if [ -f "$PENDING" ]; then
  # A pending batch takes precedence over whatever ORIG_HEAD says now. Its
  # range still ends at HEAD (a later commit may be the repair that makes it
  # importable), but the ancestry it RECORDED is what classifies the commits
  # it covered — immutable provenance. Commits after it get their own.
  pb="$(pending_get before)"; pa="$(pending_get after)"
  p_kind="$(python3 -c 'import json,sys; print((json.load(open(sys.argv[1])).get("ancestry") or {}).get("kind") or "")' "$PENDING" 2>/dev/null)"
  p_merges="$(python3 -c 'import json,sys; print((json.load(open(sys.argv[1])).get("ancestry") or {}).get("merges") or "")' "$PENDING" 2>/dev/null)"
  if [ -z "$pb" ] || ! git rev-parse --verify --quiet "$pb^{commit}" >/dev/null 2>&1; then
    # The original record is evidence: its before-commit and row count stay
    # exactly as written. Nothing here overwrites it.
    report_incomplete "$pb" "$HEAD_NOW" "pending_before_unknown" "$(pending_get rows)" \
      "a pending import exists but its before-commit ${pb:-is unset}${pb:+ no longer resolves}; the record is left as it is"
    exit 1
  fi
  if [ -z "$pa" ] || ! git rev-parse --verify --quiet "$pa^{commit}" >/dev/null 2>&1; then
    pa="$HEAD_NOW"
  fi
  if [ -z "$p_kind" ]; then
    # Older pending record without ancestry: derive it for the recorded range
    # (the commits are immutable, so this is the same answer it would have had).
    if anc="$(ancestry "$pb" "$pa")"; then
      read -r p_kind p_merges <<<"$anc"
    else
      incomplete "$pb" "$pa" "ancestry_unknown" "$(pending_get rows)" "$anc"
      exit 1
    fi
  fi
  if [ "$pa" = "$HEAD_NOW" ]; then
    run_range "$pb" "$pa" "$p_kind" "$p_merges"
  elif tail_anc="$(ancestry "$pa" "$HEAD_NOW")"; then
    # One pass over pb..HEAD: the recorded merges plus whatever diverged after.
    read -r t_kind t_merges <<<"$tail_anc"
    if [ "$p_kind" = "merge" ] || [ "$t_kind" = "merge" ]; then
      merged=""
      [ "$p_kind" = "merge" ] && merged="$p_merges"
      [ "$t_kind" = "merge" ] && merged="${merged:+$merged,}$t_merges"
      run_range "$pb" "$HEAD_NOW" "merge" "$merged"
    else
      run_range "$pb" "$HEAD_NOW" "ff" "$pb:$pb:$pb:$HEAD_NOW"
    fi
  else
    incomplete "$pa" "$HEAD_NOW" "ancestry_unknown" "$(pending_get rows)" "$tail_anc"
    exit 1
  fi
  exit 0
fi

if [ "$MODE" = "retry" ]; then
  ids="$(open_conflicts)"
  if [ -n "$ids" ]; then
    echo "beads: nothing pending to retry, but $(printf '%s\n' "$ids" | wc -w | tr -d ' ') conflict(s) remain unresolved: $ids" >&2
    echo "       Every version is under .beads/transport/evidence/; resolve natively on the host whose version should win." >&2
    exit 1
  fi
  echo "beads: nothing pending to retry"; exit 0
fi

candidate="${BEFORE_ARG:-ORIG_HEAD}"
if git rev-parse --verify --quiet "$candidate^{commit}" >/dev/null 2>&1; then
  BEFORE="$(git rev-parse "$candidate^{commit}")"
else
  incomplete "" "$HEAD_NOW" "before_unresolvable" 0 \
    "before-commit '$candidate' does not resolve, so the changed rows cannot be computed"
  exit 1
fi
if anc="$(ancestry "$BEFORE" "$HEAD_NOW")"; then
  read -r kind merges <<<"$anc"
  run_range "$BEFORE" "$HEAD_NOW" "$kind" "$merges"
  exit 0
fi
incomplete "$BEFORE" "$HEAD_NOW" "ancestry_unknown" 0 "$anc"
exit 1
