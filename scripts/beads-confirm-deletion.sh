#!/usr/bin/env bash
# Record that a bead was deleted on purpose, so the other machine deletes it too.
#
# This is the answer to the auto-export's question. When a bead exists in
# .beads/issues.jsonl but not in Dolt, two situations look identical:
#
#   another machine's work, pulled but never imported  -> import it
#   deleted here on purpose                            -> confirm it
#
# Answering the second with a bare `bd export` drops the row from the file and
# loses the *intent*. The other machine then sees only an absence, which is not
# a deletion signal (a filtered export, or work not yet exported, looks the
# same), keeps its copy, and writes the bead back on its next export. The
# deletion silently undoes itself.
#
# So the intent is written down, in an append-only git-tracked ledger, and
# committed in the same commit as the export that acts on it. Split across two
# commits, a machine can pull the export without the ledger and resurrect the
# bead in the window between.
#
# The export here is the same guarded merge the post-commit hook uses
# (scripts/check_beads_jsonl_dolt_sync.py --records --write-merged), with the
# confirmed IDs dropped from it: database-side changes apply, rows only the
# transport holds are preserved, conflicts keep their transport version. It
# never calls `bd export` against the transport file, and it refuses when the
# verdict is anything but complete. The first version called `bd export`
# directly; a later one consulted the checker but read "no verdict" as "go
# ahead". Neither is a guard.
#
# Usage:
#   scripts/beads-confirm-deletion.sh <id> [<id>...]        # already deleted here
#   scripts/beads-confirm-deletion.sh --delete-local <id>   # delete here too
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LEDGER="$ROOT/.beads/deletions.jsonl"
TRANSPORT="$ROOT/.beads/issues.jsonl"
CHECKER="$ROOT/scripts/check_beads_jsonl_dolt_sync.py"
DELETE_LOCAL=0
NOTE=""
IDS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --delete-local) DELETE_LOCAL=1 ;;
    --note) NOTE="${2:-}"; shift ;;
    -h|--help) sed -n '2,33p' "$0"; exit 0 ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *) IDS+=("$1") ;;
  esac
  shift
done

[ ${#IDS[@]} -gt 0 ] || { echo "usage: $(basename "$0") [--delete-local] [--note TEXT] <id>..." >&2; exit 2; }
command -v bd >/dev/null 2>&1 || { echo "bd not on PATH" >&2; exit 1; }
[ -f "$CHECKER" ] || { echo "refusing: $CHECKER is missing; the export cannot be guarded" >&2; exit 1; }
[ -f "$TRANSPORT" ] || { echo "refusing: $TRANSPORT is missing" >&2; exit 1; }

cd "$ROOT"

# shellcheck source=scripts/lib-beads-transport.sh
. "$ROOT/scripts/lib-beads-transport.sh"
STATE="$(beads_transport_state_dir "$ROOT")" || { echo "cannot create .beads/transport" >&2; exit 1; }
if ! beads_transport_identity_check "$ROOT"; then
  echo "refusing: $BEADS_TRANSPORT_IDENTITY_ERROR" >&2
  echo "          Check with: scripts/beads-transport-setup.sh" >&2
  exit 1
fi
if ! beads_transport_lock; then
  echo "refusing: another transport operation holds the lock (${BEADS_TRANSPORT_LOCK_HOLDER:-?})" >&2
  exit 1
fi
WORK="$(mktemp -d "${TMPDIR:-/tmp}/sylveste-confirm.XXXXXX")"
trap 'rm -rf "$WORK"; beads_transport_unlock' EXIT

# ─── Complete evidence first, before anything is deleted ──────────────

# The local deletion below is irreversible. If the checker cannot produce a
# complete verdict now, it will not produce one afterwards either, and the
# bead would be gone here with nothing recorded and nothing exported.
preflight="$(python3 "$CHECKER" --repo "$ROOT" --records --json --state-dir "$STATE" 2>"$WORK/err" || true)"
pre_coverage="$(printf '%s' "$preflight" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("coverage", "unreadable"))
except Exception: print("unreadable")' 2>/dev/null || echo unreadable)"
if [ "$pre_coverage" != "complete" ]; then
  echo "refusing: transport verdict coverage is '$pre_coverage' — nothing is deleted or exported until it is complete." >&2
  [ -s "$WORK/err" ] && head -1 "$WORK/err" >&2
  printf '%s' "$preflight" | python3 -c 'import json,sys; [print("          " + e, file=sys.stderr) for e in json.load(sys.stdin).get("errors", [])]' 2>/dev/null || true
  exit 1
fi

# ─── Local state of the beads being confirmed ─────────────────────────

for id in "${IDS[@]}"; do
  if bd show "$id" >/dev/null 2>&1; then
    if [ "$DELETE_LOCAL" -eq 1 ]; then
      bd delete "$id" --force >/dev/null
      echo "deleted locally: $id"
    else
      # Recording a deletion that has not happened would ship an instruction to
      # destroy a bead that is still live here — the ledger would be a lie the
      # other machine acts on.
      echo "refusing: $id still exists in this database." >&2
      echo "          Delete it first, or pass --delete-local to do both." >&2
      exit 1
    fi
  fi
done

# ─── Guarded export with the confirmed IDs dropped ────────────────────

drop_args=()
for id in "${IDS[@]}"; do drop_args+=(--drop-id "$id"); done
MERGED="$WORK/merged.jsonl"
PROPOSAL="$STATE/state.proposed.json"; rm -f "$PROPOSAL"
verdict="$(python3 "$CHECKER" --repo "$ROOT" --records --json --state-dir "$STATE" \
             "${drop_args[@]}" --write-merged "$MERGED" \
             --evidence-dir "$STATE/evidence" --propose-state "$PROPOSAL" 2>"$WORK/err" || true)"
if [ -z "$verdict" ]; then
  echo "refusing: the transport checker produced no verdict: $(head -1 "$WORK/err")" >&2
  exit 1
fi
read -r coverage transport_sha n_conflicts drop_conflicts <<EOF
$(printf '%s' "$verdict" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("unreadable - 0 -"); raise SystemExit
bad = [c["id"] for c in d.get("conflicts", []) if c.get("reason") == "drop_requested_but_present_in_database"]
print(d.get("coverage", "unreadable"), (d.get("transport") or {}).get("sha256", "-"),
      len(d.get("conflicts", [])), ",".join(bad) or "-")
')
EOF
if [ "$coverage" != "complete" ]; then
  echo "refusing: transport verdict coverage is '$coverage' — nothing is exported until it is complete." >&2
  printf '%s' "$verdict" | python3 -c 'import json,sys; [print("          " + e, file=sys.stderr) for e in json.load(sys.stdin).get("errors", [])]' 2>/dev/null || true
  rm -f "$PROPOSAL"
  exit 1
fi
if [ "$drop_conflicts" != "-" ]; then
  echo "refusing: $drop_conflicts still exist(s) in this database; a deletion record for a live bead is a lie the other machine would act on." >&2
  rm -f "$PROPOSAL"
  exit 1
fi
[ -f "$MERGED" ] || { echo "refusing: no merged transport was produced" >&2; rm -f "$PROPOSAL"; exit 1; }

# ─── Ledger ───────────────────────────────────────────────────────────

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
actor="$(git config user.name 2>/dev/null || echo "${USER:-unknown}")"
machine="$(hostname -s 2>/dev/null || echo unknown)"

for id in "${IDS[@]}"; do
  python3 - "$LEDGER" "$id" "$ts" "$actor" "$machine" "$NOTE" <<'PY'
import json, sys, pathlib
ledger, issue_id, ts, actor, machine, note = sys.argv[1:7]
path = pathlib.Path(ledger)
path.parent.mkdir(parents=True, exist_ok=True)
row = {"id": issue_id, "deleted_at": ts, "actor": actor, "machine": machine}
if note:
    row["note"] = note
with path.open("a", encoding="utf-8") as fh:
    fh.write(json.dumps(row, sort_keys=True) + "\n")
PY
  echo "recorded deletion: $id"
done

# ─── Replace the transport, atomically, then commit both ──────────────

now_sha="$(beads_transport_sha256 "$TRANSPORT")"
if [ "$now_sha" != "$transport_sha" ]; then
  echo "refusing: .beads/issues.jsonl changed while the merge was computed; the ledger entry is written, re-run to export it." >&2
  rm -f "$PROPOSAL"
  exit 1
fi
python3 - "$MERGED" "$TRANSPORT" <<'PY'
import os, shutil, sys
merged, transport = sys.argv[1:3]
tmp = transport + ".sylveste-merge.tmp"
shutil.copyfile(merged, tmp)
shutil.copymode(transport, tmp)
os.replace(tmp, transport)
PY
python3 "$CHECKER" --repo "$ROOT" --state-dir "$STATE" --promote-state "$PROPOSAL" --applied >/dev/null 2>&1 || true
[ "$n_conflicts" -gt 0 ] && echo "note: $n_conflicts conflicting record(s) kept at their transport version; see .beads/transport/conflicts.json" >&2

# One commit, pathspec form: the export and the intent that authorises it
# travel together or not at all.
git add -- .beads/deletions.jsonl >/dev/null 2>&1 || true
if BEADS_TRANSPORT_VERIFIED="$(beads_transport_sha256 "$TRANSPORT")" \
     git commit -q -m "beads: confirm deletion of ${IDS[*]}" \
      -- .beads/issues.jsonl .beads/deletions.jsonl 2>/dev/null; then
  echo "committed $(git rev-parse --short HEAD) — push to propagate the deletion"
else
  echo "nothing to commit; the export already matched HEAD" >&2
fi
