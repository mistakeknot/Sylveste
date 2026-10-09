#!/bin/bash
# restart-predict.sh: restart steps 2 and 4 of plan §1.4 (revisions 9.3-9.5).
# Predicts the row of the restart-outcome table that one autosync run will take
# on a checkout, decides whether the exit accepts it, and afterwards verifies the
# run against the prediction. Read-only: it reads the checkout, ls-remotes origin
# and the lane, and writes nothing but stdout.
#
#   restart-predict.sh server REPO REL LANE EXIT [P2STATUS]
#       EXIT is p10, r6 or a0r. r6 needs P2STATUS, P2's J/p2.status.all
#       (`status --porcelain=v1 --untracked-files=all`, the repair script's mode): B must equal its B entries, C must lie in its C paths plus
#       .beads/issues.jsonl, both under the repair script's classification.
#   restart-predict.sh clavain REPO LANE
#   restart-predict.sh verify PRED LOG
#       PRED is this script's prediction output, LOG the repair run's stdout and
#       stderr (server) or the sweep's report (clavain). Compares Sylveste's log
#       lines, the committed paths, the status after the run and the lane tip.
#
# Prediction lines: "row N", "log <line>", "commit <path>", "after <status line>",
# "lane unchanged|head", context lines (kind, repo, rel, lane, head, lanetip),
# and last "verdict run" or "verdict STOP <reason>". A state in no row prints
# "row none". The prediction is printed in full even for a STOP, so a test can
# run the state anyway and check that the prediction was right.
# AUTOSYNC_LANE_LIB names the lane library (default ~/.local/lib/autosync-lane.sh),
# the same one the run sources. Exit: 0 run / match; 1 usage; 3 STOP.
# The allowlist mirrors ALLOW_PATTERNS of git-autosync-repair.sh (lines 101-106);
# RH runs the real script against these predictions.
# Reporting: the EXIT trap writes a report (sha256, command, exit status) to $RESTART_LOG_DIR (default $GATE0_STATE_DIR/logs, else logs/
# beside this script's directory) and sends it with report-tell --title "$RESTART_REPORT_TITLE",
# as $RESTART_OPERATOR when run as root. RESTART_REPORT=0 turns it off (the RH, which tests it once with a stub).
set -u
PATH=/usr/local/bin:/usr/bin:/bin
export LC_ALL=C
# the hash tool is chosen by a known answer (the digest of no input), so a present but broken sha256sum falls back
if [ "$(printf '' | sha256sum 2>/dev/null | cut -d' ' -f1)" = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 ]
then sha() { sha256sum | cut -d' ' -f1; }; else sha() { shasum -a 256 2>/dev/null | cut -d' ' -f1; }; fi
SELF_SHA=$(sha < "$0")
[[ $SELF_SHA =~ ^[0-9a-f]{64}$ ]] || { echo "restart-predict.sh: no sha256 of this script (neither sha256sum nor shasum -a 256 works); refusing" >&2; exit 1; }
case ${1:-} in --check)   # syntax and tools only; reads and writes nothing
  bash -n "$0" && command -v git >/dev/null && command -v awk >/dev/null && echo "restart-predict.sh: check ok (sha256 $SELF_SHA)"
  exit $? ;; esac
usage() { echo "usage: restart-predict.sh server REPO REL LANE p10|r6|a0r [P2STATUS] | clavain REPO LANE | verify PRED LOG" >&2; exit 1; }
ALLOW_PATTERNS=('uv.lock' '.beads/issues.jsonl' '.git-autosync' 'docs/diagrams/*.html')
allowed() { local pat; for pat in "${ALLOW_PATTERNS[@]}"; do [[ "$1" == $pat ]] && return 0; done; return 1; }
classify() {  # status lines on stdin -> "C\t<path>" or "B\t<entry>" in status order, as the repair script does
  local line xy path
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    xy=${line:0:2}; path=${line:3}
    if [[ "$path" == \"* ]]; then printf 'B\t%s (quoted path)\n' "$path"
    elif [[ "$xy" == *T* ]]; then printf 'B\t%s (type change)\n' "$path"
    elif allowed "$path"; then printf 'C\t%s\n' "$path"
    else printf 'B\t%s\n' "$path"; fi
  done; }
lane_lib() {
  # shellcheck disable=SC1090
  source "${AUTOSYNC_LANE_LIB:-$HOME/.local/lib/autosync-lane.sh}" 2>/dev/null || none "the lane library does not load"
  asl_resolve "$REPO" || none "lane destination not acceptable: $ASL_REASON"
  asl_tip "$REPO" "autosync/$LANE" || none "lane remote unreachable"; }
out() { printf '%s\n' "$*"; }
none() { out "row none"; out "verdict STOP no row: $*"; exit 3; }
context() { out "kind $1"; out "repo $REPO"; out "rel ${REL:-}"; out "lane $LANE"; out "head $HEAD"; }

server() {
  local gd ex p st c b n ahead behind row r tip
  gd=$(git -C "$REPO" rev-parse --absolute-git-dir 2>/dev/null) || none "not a git repository"
  HEAD=$(git -C "$REPO" rev-parse -q --verify HEAD) || none "no HEAD"
  context server
  for p in rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD BISECT_LOG; do [ ! -e "$gd/$p" ] || none "$p (the run refuses)"; done
  git -C "$REPO" symbolic-ref -q HEAD >/dev/null || none "detached HEAD (the run refuses)"
  grep -qE '^LANE=1[[:space:]]*$' "$REPO/.git-autosync" 2>/dev/null || none "no LANE=1 marker"
  st=$(git -C "$REPO" status --porcelain=v1 --untracked-files=all)
  ! printf '%s\n' "$st" | grep -q '^\(DD\|AU\|UD\|UA\|DU\|AA\|UU\)' || none "unresolved conflicts (the run refuses)"
  git -C "$REPO" diff --cached --quiet || none "staged changes (the run refuses)"
  [ "$(git -C "$REPO" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)" = origin/main ] || none "upstream is not origin/main"
  [ "$(git -C "$REPO" ls-remote origin refs/heads/main | cut -f1)" = "$(git -C "$REPO" rev-parse refs/remotes/origin/main)" ] ||
    none "origin/main moved since the last fetch; the run's fetch would change the counts"
  ahead=$(git -C "$REPO" rev-list --count origin/main..HEAD); behind=$(git -C "$REPO" rev-list --count HEAD..origin/main)
  printf '%s\n' "$st" | classify > "$T/cls"
  c=$(grep -c '^C' "$T/cls"); b=$(grep -c '^B' "$T/cls")
  if [ -z "$st" ] && [ "$ahead" = 0 ] && [ "$behind" = 0 ]; then row=1
  elif [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then row=4
  elif [ "$behind" -gt 0 ]; then none "behind only (the run fast-forwards)"
  else
    lane_lib; tip=$ASL_TIP
    if [ "$c" -gt 0 ]; then   # asl_ahead after the run's commit
      if [ -z "$tip" ]; then n=$(( $(git -C "$REPO" rev-list --count origin/main..HEAD) + 1 ))
      elif git -C "$REPO" cat-file -e "$tip^{commit}" 2>/dev/null; then n=$(( $(git -C "$REPO" rev-list --count "$tip..HEAD") + 1 ))
      else n=1; fi
    else n=$(asl_ahead "$REPO"); fi
    if [ "$b" -gt 0 ]; then row=3
    elif [ "$c" -gt 0 ] || { [ "$ahead" -gt 0 ] && [ "$n" -gt 0 ]; }; then row=2
    else row=2u; fi
  fi
  out "lanetip $(git -C "$REPO" ls-remote lane "refs/heads/autosync/$LANE" | cut -f1)"
  out "row $row"
  case $row in
    1) ;;
    4) out "log   NEEDS-HUMAN $REL -- diverged from origin/main (behind $behind, ahead $ahead)" ;;
    2u) out "log   UNACCOUNTED $REL -- no outcome recorded (behind=0 ahead=0 dry=0)" ;;
    2|3) [ "$c" = 0 ] || out "log   COMMIT  $REL -- $(grep '^C' "$T/cls" | cut -f2 | paste -sd' ' -)"
       [ "$b" = 0 ] || { out "log   NEEDS-HUMAN $REL -- $b path(s) not on the allowlist:"
         grep '^B' "$T/cls" | head -n 6 | cut -f2- | sed 's/^/log       /'
         [ "$b" -le 6 ] || out "log       ... and $((b-6)) more"; }
       [ "$n" -gt 0 ] && out "log   PUSH    $REL -- $n commit(s) -> autosync/$LANE" ;;
  esac
  grep '^C' "$T/cls" | cut -f2 | sed 's/^/commit /'
  case $row in 2|3) r=$(grep '^C' "$T/cls" | cut -f2) ;; *) r= ;; esac
  printf '%s\n' "$st" | while IFS= read -r p; do [ -n "$p" ] || continue; printf '%s\n' "$r" | grep -qxF -- "${p:3}" || out "after $p"; done
  case $row in 2) out "lane head" ;; 3) if [ "$n" -gt 0 ]; then out "lane head"; else out "lane unchanged"; fi ;; *) out "lane unchanged" ;; esac
  # acceptance (restart step 2's exit table, and the two rules for every exit)
  [ "$row" != 2u ] || { out "verdict STOP row 2u at every exit"; exit 3; }
  ! grep -qxF "C	.git-autosync" "$T/cls" || { out "verdict STOP the marker rule: C holds .git-autosync"; exit 3; }
  case $EXIT in
    p10) case $row in 1|2) ;; *) out "verdict STOP row $row at p10"; exit 3 ;; esac
         [ -z "$(grep '^C' "$T/cls" | cut -f2 | grep -vxF .beads/issues.jsonl)" ] || { out "verdict STOP p10: C holds more than .beads/issues.jsonl"; exit 3; } ;;
    r6) case $row in 1|2|3) ;; *) out "verdict STOP row $row at r6"; exit 3 ;; esac
        classify < "$P2STATUS" > "$T/p2cls"
        [ "$(grep '^B' "$T/cls")" = "$(grep '^B' "$T/p2cls")" ] || { out "verdict STOP r6: B differs from P2's B"; exit 3; }
        [ -z "$(grep '^C' "$T/cls" | cut -f2 | grep -vxF -f <(grep '^C' "$T/p2cls" | cut -f2; echo .beads/issues.jsonl))" ] ||
          { out "verdict STOP r6: C holds a path outside P2's C and .beads/issues.jsonl"; exit 3; } ;;
    a0r) [ "$row" = 4 ] || { out "verdict STOP row $row at a0r"; exit 3; } ;;
    *) usage ;; esac
  out "verdict run"; }

clavain() {
  local gd st n tip
  REL=; HEAD=$(git -C "$REPO" rev-parse -q --verify HEAD) || none "no HEAD"
  context clavain
  out "lanetip $(git -C "$REPO" ls-remote lane "refs/heads/autosync/$LANE" 2>/dev/null | cut -f1)"
  if [ ! -e "$REPO/.git-autosync" ]; then out "row 8"; out "lane unchanged"   # the sweep skips it: the status stays as it is
    git -C "$REPO" status --porcelain=v1 --untracked-files=all | sed 's/^/after /'; out "verdict run"; return; fi
  grep -qE '^LANE=1[[:space:]]*$' "$REPO/.git-autosync" || none "a Clavain marker without LANE=1"
  gd=$(git -C "$REPO" rev-parse --absolute-git-dir)
  for p in rebase-merge rebase-apply MERGE_HEAD; do [ ! -e "$gd/$p" ] || none "$p (the sweep skips)"; done
  st=$(git -C "$REPO" status --porcelain | grep -vE '^.. \.git-autosync(-allow-patterns)?$')
  if [ -n "$st" ]; then n=$(printf '%s\n' "$st" | grep -c .)
    out "row 5"; out "log DIRTY $REPO $n file(s)"; out "lane unchanged"
  else
    lane_lib; n=$(asl_ahead "$REPO")
    if [ "$n" -gt 0 ]; then out "row 6"; out "log LANE $REPO pushed $n commit(s) to autosync/$LANE"; out "lane head"
    else out "row 7"; out "lane unchanged"; fi
  fi
  git -C "$REPO" status --porcelain=v1 --untracked-files=all | sed 's/^/after /'
  out "verdict run"; }

verify() {  # PRED LOG : fails closed; every field, file and command is checked
  local k repo rel lane lout head lanetip row verdict want got cs c top
  set -o pipefail
  mismatch() { echo "restart: STOP: the run differs from the prediction: $*" >&2; exit 3; }
  bad() { echo "restart: STOP: no valid prediction or log to verify: $*" >&2; exit 3; }
  [ -f "$PRED" ] && [ -r "$PRED" ] && [ -s "$PRED" ] || bad "PRED [$PRED] is missing, unreadable or empty"
  [ -f "$LOG" ] && [ -r "$LOG" ] && [ -s "$LOG" ] || bad "LOG [$LOG] is missing, unreadable or empty"
  # the schema: only known line kinds; exactly one of each context field; two lane lines (name, then outcome)
  got=$(awk '!/^(kind|repo|rel|lane|head|lanetip|row|log|commit|after|verdict)( |$)/' "$PRED") || bad "cannot read PRED"
  [ -z "$got" ] || bad "unknown line(s) in PRED: $(printf '%s' "$got" | head -n 1)"
  one() { awk -v k="$1" 'index($0, k " ")==1 || $0==k {n++; v=substr($0, length(k)+2)} END {if (n!=1) exit 1; print v}' "$PRED" || bad "PRED has no single \"$1\" line"; }
  k=$(one kind) && repo=$(one repo) && rel=$(one rel) && head=$(one head) && lanetip=$(one lanetip) && row=$(one row) && verdict=$(one verdict) || exit 3
  [ "$(awk 'index($0, "lane ")==1' "$PRED" | wc -l | tr -d ' ')" = 2 ] || bad "PRED needs exactly two lane lines (name, outcome)"
  lane=$(awk 'index($0, "lane ")==1 {print substr($0, 6); exit}' "$PRED") && lout=$(awk 'index($0, "lane ")==1 {v=substr($0, 6)} END {print v}' "$PRED") || bad "cannot read PRED"
  [ "$row" != none ] || mismatch "the prediction has no row"   # a STOP verdict is still compared
  case $k:$row in server:1|server:2|server:2u|server:3|server:4|clavain:5|clavain:6|clavain:7|clavain:8) ;; *) bad "kind [$k] with row [$row] is not a known prediction" ;; esac
  case $k in server) [ -n "$rel" ] || bad "a server prediction without rel" ;; clavain) [ -z "$rel" ] || bad "a clavain prediction with rel" ;; esac
  [[ $lane =~ ^[A-Za-z0-9._/-]+$ ]] || bad "lane name [$lane]"
  case $lout in head|unchanged) ;; *) bad "lane outcome [$lout]" ;; esac
  [[ $head =~ ^[0-9a-f]{40}$ ]] || bad "head [$head]"
  [ -z "$lanetip" ] || [[ $lanetip =~ ^[0-9a-f]{40}$ ]] || bad "lanetip [$lanetip]"
  case $verdict in run|"STOP "?*) ;; *) bad "verdict [$verdict]" ;; esac
  [ "$(tail -n 1 "$PRED")" = "verdict $verdict" ] || bad "the verdict is not the last line"
  case $repo in /*) ;; *) bad "repo [$repo] is not an absolute path" ;; esac
  top=$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null) && [ -n "$top" ] && [ "$top" = "$(cd "$repo" 2>/dev/null && pwd -P)" ] ||
    bad "repo [$repo] is not the top of a git work tree"
  git -C "$repo" cat-file -e "$head^{commit}" 2>/dev/null || bad "head $head is not a commit in $repo"
  if [ "$k" = server ]; then
    grep -q '^[0-9][0-9]* autosync repo(s): ' "$LOG" || mismatch "no summary line: the run did not run"
    got=$(awk -v r="$rel" 'index($0, " " r " -- ") && /^  [A-Z]/ {on=1; print; next} on && /^      / {print; next} {on=0}' "$LOG") || bad "cannot read LOG"
  else   # rows 5-7 have a marker, so the sweep must have run; row 8 has none and the sweep never looks at it
    case $row in 5|6|7) grep -qE '^swept [0-9]+ repos: ' "$LOG" || mismatch "no sweep summary line: the sweep did not run" ;; esac
    got=$(awk -v r="$repo" '$2==r' "$LOG" | sed 's/, newest change .*//') || bad "cannot read LOG"
  fi
  want=$(awk 'index($0, "log ")==1 {print substr($0, 5)}' "$PRED") || bad "cannot read PRED"
  [ "$got" = "$want" ] || mismatch "log lines [$got], predicted [$want]"
  cs=$(git -C "$repo" rev-list "$head..HEAD") || bad "git rev-list $head..HEAD failed"
  got=$(for c in $cs; do git -C "$repo" diff-tree -r --root --no-commit-id --name-only "$c" || exit 1; done | sort -u) || bad "git diff-tree failed"
  want=$(awk 'index($0, "commit ")==1 {print substr($0, 8)}' "$PRED" | sort -u) || bad "cannot read PRED"
  [ "$k" = server ] && [[ $row == [23] ]] || want=
  [ "$got" = "$want" ] || mismatch "committed paths [$got], predicted [$want]"
  if [ -z "$want" ]; then c=$(git -C "$repo" rev-parse --verify HEAD) || bad "no HEAD"; [ "$c" = "$head" ] || mismatch "HEAD moved without a commit"
  else c=$(git -C "$repo" rev-parse --verify 'HEAD^') || mismatch "HEAD has no parent"; [ "$c" = "$head" ] || mismatch "not exactly one commit on the old HEAD"; fi
  got=$(git -C "$repo" status --porcelain=v1 --untracked-files=all | sort) || bad "git status failed"
  want=$(awk 'index($0, "after ")==1 {print substr($0, 7)}' "$PRED" | sort) || bad "cannot read PRED"
  [ "$got" = "$want" ] || mismatch "status after [$got], predicted [$want]"
  got=$(git -C "$repo" ls-remote lane "refs/heads/autosync/$lane" | cut -f1) || bad "git ls-remote lane failed"
  if [ "$lout" = head ]; then want=$(git -C "$repo" rev-parse --verify HEAD) || bad "no HEAD"; else want=$lanetip; fi
  [ "$got" = "$want" ] || mismatch "lane tip $got, predicted $want"
  echo "restart: the run matches the prediction (row $row)"; }

T=$(mktemp -d) || exit 1; CMDLINE="$*"; STEPNAME=${1:-none}
report() {  # EXIT trap
  local rc=$? tell=${RESTART_REPORT_TELL:-} t=${RESTART_REPORT_TITLE:-cutover}
  local d=${RESTART_LOG_DIR:-${GATE0_STATE_DIR:-$(cd "$(dirname "$0")/.." && pwd -P)}/logs} r f me
  r=$([ $rc = 0 ] && echo ok || echo failed); f=$d/restart-predict-$(date -u +%Y%m%dT%H%M%SZ)-$$.report
  me=$(cd "$(dirname "$0")" && pwd -P)/$(basename "$0")
  mkdir -p "$d" 2>/dev/null; echo "restart-predict.sh (sha256 $SELF_SHA) $CMDLINE: exit $rc ($r)" > "$f" 2>/dev/null
  if [ "$(id -u)" = 0 ]; then chmod a+rx "$d" 2>/dev/null; chmod a+r "$f" 2>/dev/null
    runuser -u "${RESTART_OPERATOR:-}" -- "$tell" --title "$t" --message-file "$f" --script "$me" --result "$r" --step "$STEPNAME" --log "$f"
  else "$tell" --title "$t" --message-file "$f" --script "$me" --result "$r" --step "$STEPNAME" --log "$f"
  fi >/dev/null 2>&1 || { echo "restart: report not delivered; it is $f:" >&2; cat "$f" >&2; }
  rm -rf -- "${T:?}"; exit $rc; }
if [ "${RESTART_REPORT:-1}" != 0 ]; then trap report EXIT; else trap 'rm -rf -- "${T:?}"' EXIT; fi
case ${1:-} in
  server) [ $# = 5 ] || [ $# = 6 ] || usage; REPO=$2; REL=$3; LANE=$4; EXIT=$5; P2STATUS=${6:-}
        [ "$EXIT" != r6 ] || [ -r "$P2STATUS" ] || usage; server ;;
  clavain) [ $# = 3 ] || usage; REPO=$2; LANE=$3; clavain ;;
  verify) [ $# = 3 ] || usage; PRED=$2; LOG=$3; verify ;;
  *) usage ;; esac
