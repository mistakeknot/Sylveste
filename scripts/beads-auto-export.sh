#!/usr/bin/env bash
# Publish Dolt → .beads/issues.jsonl through a guarded merge, and commit it,
# when and only when that is both needed and safe. Invoked from post-commit;
# `--manual` runs the same path by hand (after a merge, or to reconcile).
#
# Why a dedicated commit rather than folding the export into the commit that
# triggered it: staging issues.jsonl from pre-commit widens the commit. With
# `git commit -- <paths>` the hook runs against a temporary index, so a
# `git add` there puts the export into a commit that explicitly named other
# paths, and leaves the real index dirty afterward. Measured, not assumed.
# A separate pathspec commit keeps every other commit exactly as authored.
#
# What "guarded" means (scripts/check_beads_jsonl_dolt_sync.py --records):
#   - a PRIVATE native export is taken to a temp file; the transport file is
#     never the target of `bd export`;
#   - every record is compared by content against the transport and against
#     the committed baseline, so provenance decides, not timestamps;
#   - database-side changes apply; rows only the transport holds (pulled but
#     not yet imported, or absent here) are preserved; conflicted IDs keep
#     their current transport version and both versions are kept privately;
#   - the transport's bytes are checked again immediately before the atomic
#     replacement, so a concurrent writer cannot be overwritten.
#
# Fail-open throughout. This runs after the user's commit already succeeded;
# nothing here may fail it, and nothing here may block for long. Every
# outcome — including "did nothing" and "incomplete" — is written to
# .beads/transport/status.json and .beads/auto-export.log.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$ROOT" || exit 0

MANUAL=0
for arg in "$@"; do
  case "$arg" in
    --manual) MANUAL=1 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
  esac
done

LOG="$ROOT/.beads/auto-export.log"
log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" >>"$LOG" 2>/dev/null || true; }

# shellcheck source=scripts/lib-beads-transport.sh
if [ -f "$ROOT/scripts/lib-beads-transport.sh" ]; then
  . "$ROOT/scripts/lib-beads-transport.sh"
else
  log "skip: scripts/lib-beads-transport.sh missing"
  exit 0
fi

# ─── Guards ───────────────────────────────────────────────────────────

# Re-entrancy: the commit this hook makes will itself fire post-commit. Without
# this the hook recurses until something breaks. A manual run after a merge
# that touched the file is the one legitimate exception.
if [ "$MANUAL" -eq 0 ] && git diff-tree --no-commit-id --name-only -r HEAD 2>/dev/null \
     | grep -qx '.beads/issues.jsonl'; then
  exit 0
fi

# Never create a commit while git is mid-sequence. post-commit fires during
# cherry-pick and --amend, and inserting a commit there rewrites what the
# operation is doing underneath it.
GIT_DIR_PATH="$(git rev-parse --git-dir 2>/dev/null)" || exit 0
for marker in rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG; do
  if [ -e "$GIT_DIR_PATH/$marker" ]; then
    log "skip: $marker present"
    exit 0
  fi
done

# An explicit opt-out, and the escape hatch for scripted flows that manage the
# export themselves.
if [ "${BEADS_NO_AUTO_EXPORT:-}" = "1" ]; then
  log "skip: BEADS_NO_AUTO_EXPORT=1"
  exit 0
fi

command -v bd >/dev/null 2>&1 || exit 0
CHECKER="$ROOT/scripts/check_beads_jsonl_dolt_sync.py"
[ -f "$CHECKER" ] || exit 0
TRANSPORT="$ROOT/.beads/issues.jsonl"
[ -f "$TRANSPORT" ] || { log "skip: no transport file"; exit 0; }

STATE="$(beads_transport_state_dir "$ROOT")" || exit 0

# The database bd resolves from here must be this repository's. An export of
# the wrong database exits 0 and rewrites the transport with another
# project's issues (sylveste-vqlu); refusing is the only safe answer.
if ! beads_transport_identity_check "$ROOT"; then
  log "REFUSED identity: $BEADS_TRANSPORT_IDENTITY_ERROR"
  echo "beads: NOT exporting — $BEADS_TRANSPORT_IDENTITY_ERROR" >&2
  echo "       Check with: scripts/beads-transport-setup.sh" >&2
  beads_transport_status export "{\"at\":\"$(date -u +%FT%TZ)\",\"result\":\"refused\",\"reason\":\"database identity\",\"message\":$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$BEADS_TRANSPORT_IDENTITY_ERROR")}"
  exit 0
fi

# ─── Serialize ────────────────────────────────────────────────────────

# Two worktrees of this repo share one database and one transport identity;
# an export from each at the same moment is two writers of one file.
if ! beads_transport_lock; then
  log "skip: transport lock held by ${BEADS_TRANSPORT_LOCK_HOLDER:-?}"
  echo "beads: another transport operation holds the lock (${BEADS_TRANSPORT_LOCK_HOLDER:-?}); export deferred to the next commit." >&2
  beads_transport_status export "{\"at\":\"$(date -u +%FT%TZ)\",\"result\":\"deferred\",\"reason\":\"lock held\"}"
  exit 0
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/sylveste-export.XXXXXX")" || { beads_transport_unlock; exit 0; }
cleanup() { rm -rf "$WORK"; beads_transport_unlock; }
trap cleanup EXIT

# ─── Decide, with complete evidence ───────────────────────────────────

# Provenance is the persisted per-record baseline in .beads/transport/
# baseline.json: the last content on which transport and database were seen
# to agree. Not HEAD — after a preserve-and-flag export HEAD holds the
# transport's side of a conflict, and a pass that took it as provenance would
# read the database's side as a fresh one-sided change and publish it. With no
# baseline entry a differing record is a conflict, until the two sides agree
# or the integrator seeds the baseline after a reviewed reconciliation.
MERGED="$WORK/merged.jsonl"
PROPOSAL="$STATE/state.proposed.json"
rm -f "$PROPOSAL"
verdict_err="$WORK/verdict.err"
verdict="$(python3 "$CHECKER" --repo "$ROOT" --records --json \
             --state-dir "$STATE" \
             --propose-state "$PROPOSAL" \
             --write-merged "$MERGED" \
             --evidence-dir "$STATE/evidence" 2>"$verdict_err")"
verdict_rc=$?
verdict_msg="$(head -1 "$verdict_err" 2>/dev/null)"

# A missing verdict means bead state stops being exported. Say so out loud.
# The test is "did it produce a verdict", NOT "did it exit 0": exit 1 is
# precisely the case where an export IS wanted.
if [ -z "$verdict" ]; then
  log "PROBE FAILED rc=$verdict_rc: $verdict_msg"
  echo "beads: auto-export probe failed — bead state is NOT being exported." >&2
  [ -n "$verdict_msg" ] && echo "       $verdict_msg" >&2
  echo "       Until this is fixed, reconcile by hand with: scripts/beads-auto-export.sh --manual" >&2
  beads_transport_status export "{\"at\":\"$(date -u +%FT%TZ)\",\"result\":\"probe_failed\",\"rc\":$verdict_rc,\"message\":$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$verdict_msg")}"
  exit 0
fi

# Pull the fields the decision needs out of the JSON verdict.
read -r coverage synchronized changes_transport transport_sha n_conflicts n_pending <<EOF
$(printf '%s' "$verdict" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("unreadable false false - 0 0"); raise SystemExit
m = d.get("merged") or {}
pending = len(d.get("transport_changed", [])) + len(d.get("transport_only", []))
print(d.get("coverage", "unreadable"),
      str(d.get("synchronized", False)).lower(),
      str(m.get("changes_transport", False)).lower(),
      (d.get("transport") or {}).get("sha256", "-"),
      len(d.get("conflicts", [])), pending)
')
EOF

if [ "$coverage" != "complete" ]; then
  # Invalid transport, unreadable export, missing baseline file: no verdict is
  # complete, so nothing is published. The reason is in the verdict itself.
  rm -f "$PROPOSAL"
  errs="$(printf '%s' "$verdict" | python3 -c 'import json,sys; print("; ".join(json.load(sys.stdin).get("errors", [])))' 2>/dev/null)"
  log "REFUSED coverage=$coverage: $errs"
  echo "beads: NOT exporting — coverage is $coverage: $errs" >&2
  beads_transport_status export "{\"at\":\"$(date -u +%FT%TZ)\",\"result\":\"refused\",\"coverage\":\"$coverage\",\"errors\":$(printf '%s' "$verdict" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin).get("errors", [])))')}"
  exit 0
fi

public_summary="$(printf '%s' "$verdict" | python3 -c '
import json, sys
d = json.load(sys.stdin)
keep = ("coverage", "database_changed", "database_only", "transport_changed", "transport_only",
        "transport_removed", "dropped", "conflicts", "synchronized", "incomplete_reasons",
        "baseline_available", "evidence_path", "export_needed", "presentation_only")
out = {k: d.get(k) for k in keep}
out["transport_sha256"] = (d.get("transport") or {}).get("sha256")
out["database_sha256"] = (d.get("database") or {}).get("sha256")
out["merged_sha256"] = (d.get("merged") or {}).get("sha256")
print(json.dumps(out))
')"

# ─── Replace the transport, atomically ────────────────────────────────

if [ "$changes_transport" = "true" ]; then
  # The snapshot was taken seconds ago; if anything else wrote the transport in
  # between, this merge was computed against a file that no longer exists.
  now_sha="$(beads_transport_sha256 "$TRANSPORT")"
  if [ "$now_sha" != "$transport_sha" ]; then
    rm -f "$PROPOSAL"
    log "ABORTED: transport changed underneath the merge ($transport_sha -> $now_sha)"
    echo "beads: NOT exporting — .beads/issues.jsonl changed while the merge was computed; retry on the next commit." >&2
    beads_transport_status export "{\"at\":\"$(date -u +%FT%TZ)\",\"result\":\"aborted\",\"reason\":\"transport changed during merge\"}"
    exit 0
  fi
  if ! python3 - "$MERGED" "$TRANSPORT" <<'PY'
import os, shutil, sys
merged, transport = sys.argv[1:3]
tmp = transport + ".sylveste-merge.tmp"
shutil.copyfile(merged, tmp)
shutil.copymode(transport, tmp)       # keep the file's permissions
os.replace(tmp, transport)            # atomic on the same filesystem
PY
  then
    rm -f "$PROPOSAL"
    log "replace failed; transport left untouched"
    echo "beads: auto-export could not replace .beads/issues.jsonl; nothing was changed." >&2
    exit 0
  fi
  log "merged export written (db-changed/new applied, transport-only preserved, $n_conflicts conflict(s) kept at transport version)"
  applied_flag="--applied"
else
  applied_flag=""
fi

# The baseline moves only now, when the merged transport is actually on disk
# (or nothing needed to change): agreement observed this pass, plus the
# database-side rows the merge carried. Conflicts keep their old entry. If
# the state cannot be written the pass is INCOMPLETE whatever else happened:
# the next pass would have no provenance for what this one published.
state_written=1
# shellcheck disable=SC2086
if ! python3 "$CHECKER" --repo "$ROOT" --state-dir "$STATE" --promote-state "$PROPOSAL" $applied_flag >/dev/null 2>&1; then
  state_written=0
  log "STATE NOT WRITTEN: baseline/conflict state under $STATE could not be promoted"
  echo "beads: the verified-baseline state under .beads/transport could not be written; this export pass is INCOMPLETE." >&2
fi

# ─── Commit ───────────────────────────────────────────────────────────

# Commit against HEAD, not against the index, and do it even when no export was
# needed: the probe compares the working tree to Dolt, which says nothing about
# what is committed — and only the committed copy is pushed. A hand-run export
# that was never committed leaves the file matching Dolt while HEAD still holds
# the stale version. Observed exactly that, once.
if git diff --quiet HEAD -- .beads/issues.jsonl 2>/dev/null; then
  log "export matches HEAD; no commit (synchronized=$synchronized conflicts=$n_conflicts pending=$n_pending)"
  result="unchanged"
else
  # Pathspec form: commits this file only, even when other changes are staged.
  # The pre-commit drift guard is told the staged blob's hash so it can skip
  # re-deriving what was just verified — and only for exactly that blob.
  staged_sha="$(beads_transport_sha256 "$TRANSPORT")"
  if BEADS_TRANSPORT_VERIFIED="$staged_sha" \
       git commit -q -m "beads: sync export (automated)" -- .beads/issues.jsonl >>"$LOG" 2>&1; then
    log "committed export $(git rev-parse --short HEAD)"
    result="committed"
  else
    log "commit failed; export left in the working tree for the next commit"
    echo "beads: export refreshed but could not be committed; it is in your working tree" >&2
    result="uncommitted"
  fi
fi

[ "$state_written" -eq 1 ] || result="${result}_state_unwritten"
if ! beads_transport_status export "$(python3 -c '
import json, sys
summary = json.loads(sys.argv[1])
summary.update({"at": sys.argv[2], "result": sys.argv[3], "head": sys.argv[4], "state_written": sys.argv[5] == "1"})
print(json.dumps(summary))
' "$public_summary" "$(date -u +%FT%TZ)" "$result" "$(git rev-parse HEAD 2>/dev/null)" "$state_written")"; then
  # The commit (if any) stands; what is missing is the record of this pass.
  # Say so rather than let a stale status.json advertise an older result.
  log "STATUS NOT RECORDED: export result '$result' could not be written under $STATE"
  echo "beads: export pass finished ($result) but its status could NOT be recorded under .beads/transport; do not trust status.json until a later pass rewrites it." >&2
fi

# A pending import batch is not this pass's business, but every commit is a
# chance to say it exists: git runs no hook at all for a pull that is
# "Already up to date", so a batch stranded by a failed import would
# otherwise wait in silence for the next merge.
if [ -f "$STATE/pending-import.json" ]; then
  echo "beads: a pending import batch is waiting ($(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(f"{d.get(\"rows\")} row(s), reason={d.get(\"reason\")}, attempts={d.get(\"attempts\")}")' "$STATE/pending-import.json" 2>/dev/null)); load it with: scripts/beads-import-merged.sh --retry" >&2
fi

if [ "$synchronized" != "true" ]; then
  reasons="$(printf '%s' "$verdict" | python3 -c 'import json,sys; print("; ".join(json.load(sys.stdin).get("incomplete_reasons", [])))')"
  conflict_ids="$(printf '%s' "$verdict" | python3 -c 'import json,sys; print(" ".join(c["id"] for c in json.load(sys.stdin).get("conflicts", []))[:400])')"
  log "INCOMPLETE: $reasons${conflict_ids:+ [conflicts: $conflict_ids]}"
  echo "beads: transport export $result, but synchronization is INCOMPLETE: $reasons" >&2
  [ -n "$conflict_ids" ] && echo "       conflicts (transport version kept, both versions under .beads/transport/evidence/): $conflict_ids" >&2
  [ "$n_pending" -gt 0 ] && echo "       pending transport-side rows are preserved; load them with: scripts/beads-import-merged.sh --retry" >&2
  echo "       details: .beads/transport/status.json" >&2
fi
exit 0
