#!/bin/bash
# cutover-steps.sh: the per-machine steps of plan §1.4 P2 and P6-P8 and of
# Rollback R1, R3-R5 (revision 8), as one journal with one recovery rule.
#
#   cutover-steps.sh ROOT J p2        record the P2 manifest, status and checkpoint c0
#   cutover-steps.sh ROOT J forward [CP]   finish any recorded step, then P6, P7, P8 to c3
#                                     (or stop once checkpoint CP is reached)
#   cutover-steps.sh ROOT J rollback  finish or supersede the recorded step, then R1, R3, R4, R5
#   cutover-steps.sh ROOT J recover   finish the recorded step only
#
# Gate 0 (revision 9.1-9.5; only where J/base exists):
#   cutover-steps.sh ROOT J p0        read-only baseline J/p0/ (RH stands in for P0's report)
#   cutover-steps.sh ROOT J p1-pre    read-only re-check inside the freeze, record J/p1-pre/
#   cutover-steps.sh ROOT J p1a       capture + preserve (checkpoint a0), then the realign to a1
#   cutover-steps.sh ROOT J unfreeze-gate r0|p10|r6
#   cutover-steps.sh ROOT J preserved restart step 1: tag, capture digests, archive branches
#   rollback from a1, or from c0 after P1a before P5, runs R0a and stops at a0r.
# Gate 0 inputs in J: base, host, lane-remote (default lane), dispositions
# ("class<TAB>glob"; internal paths are always class internal), pr1-head, and
# optionally pr1-merge. keep.list lines are "<state>\t<path>", state as dg prints
# it (- = absent). Extra journal ops: tag NAME SHA; realign OLD NEW KEEP.
# CUTOVER_BD names the bd binary (default bd).
#
# J is this machine's journal directory, outside ROOT, on ROOT's filesystem. It
# holds the inputs (delete-list, shared.manifest, local.manifest: one path per
# line; url, host, helper: one value), the quarantine J/Q, the set-aside
# directories J/rollback-p8 and J/rollback-revert, and the journal:
#   J/cp      "<checkpoint> <HEAD>": c0 c1 c2 c3, then r1-done r3-done r4-done r5
#   J/intent  line 1 "<step> <target checkpoint> <target HEAD>", then one op per
#             line (tab-separated), written whole before the step's first write
# Every op is idempotent with a checkable postcondition:
#   mv DIGEST SRC DST [refill]
#                       post: DST holds DIGEST and SRC is gone (refill: a later op
#                       of the same intent writes SRC); pre: SRC holds DIGEST, DST absent
#   ff OLD NEW          post: HEAD is NEW; pre: HEAD OLD, index OLD or NEW, each
#                       changed path holding its OLD or its NEW entry
#   install URL HOST    post: .git-internal/info/installed; pre: always (resumable)
#   w PATH, from CP     records only (P8's planned writes; R3's starting checkpoint)
# The one recovery rule, for every step: if J/cp already equals the intent's
# target, the step finished and only its intent is left; otherwise, per op,
# "postcondition true" skips it, "precondition true" does it, anything else is a
# STOP (exit 3) with the intent kept. Then the step's check, then J/cp, then the
# intent is renamed to J/done-<step> LAST (it stays as the step's ledger). Each
# step starts only at its checkpoint, with HEAD equal to the HEAD recorded
# there; HEAD changes only through an ff op whose OLD and NEW are in the intent.
#
# Exit: 0 ok; 1 usage, or refused before the intent (nothing written); 2 fetch
# failed; 3 STOP, the recorded step cannot finish (intent kept, owner decides).
# Records are written atomically: temp file, fsync, rename, directory fsync.
# CUTOVER_CRASH_AT=N (tests only) kills this script at its Nth crash point,
# counted in the file $CUTOVER_CRASH_COUNT, which it shares with the helper.
# Portable to /bin/bash 3.2. No guarded git form is used.
#
#   cutover-steps.sh --check                syntax and tools only; reads and writes nothing
#   cutover-steps.sh --check ROOT J p1a     P1a's check (plan §1.4): P1-pre and every capture check
#       run against a scratch copy of J in a new directory under $CUTOVER_CHECK_DIR (default: thread
#       storage, $GATE0_STATE_DIR, else $TMPDIR). Nothing else is written: no fetch (origin/main is
#       compared with ls-remote), no ref, no push, no checkout write; the bundle is built in a scratch
#       repository. bd export writes only into the scratch directory.
# Reporting: the EXIT trap writes a report (this script's sha256, the command, the exit status) to
# $CUTOVER_LOG_DIR (default $GATE0_STATE_DIR/logs, else logs/ beside this script's directory) and
# sends it with report-tell --title "$CUTOVER_REPORT_TITLE" (as $CUTOVER_OPERATOR when run as root). CUTOVER_REPORT=0
# turns it off: the RH runs this script thousands of times and tests the trap once with a stub
# CUTOVER_REPORT_TELL.
set -u
PATH=${CUTOVER_PATH:-/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin}
export LC_ALL=C
# the hash tool is chosen by a known answer (the digest of no input), so a present but broken sha256sum falls back
if [ "$(printf '' | sha256sum 2>/dev/null | cut -d' ' -f1)" = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 ]
then sha() { sha256sum | cut -d' ' -f1; }; else sha() { shasum -a 256 2>/dev/null | cut -d' ' -f1; }; fi
SELF_SHA=$(sha < "$0")
[[ $SELF_SHA =~ ^[0-9a-f]{64}$ ]] || { echo "cutover: no sha256 of this script (neither sha256sum nor shasum -a 256 works); refusing" >&2; exit 1; }
TSDIR=${GATE0_STATE_DIR:-$(cd "$(dirname "$0")/.." && pwd -P)}
CHECK=
if [ "${CUTOVER_REPORT:-1}" != 0 ]; then
  RDIR=${CUTOVER_LOG_DIR:-$TSDIR/logs}; RLOG=$RDIR/cutover-$(date -u +%Y%m%dT%H%M%SZ)-$$.report
  report() {  # EXIT trap: the report, then report-tell (as $CUTOVER_OPERATOR when run as root); a failed delivery prints the report
    local rc=$? tell=${CUTOVER_REPORT_TELL:-} t=${CUTOVER_REPORT_TITLE:-cutover} r
    r=$([ $rc = 0 ] && echo ok || echo failed)
    mkdir -p "$RDIR" 2>/dev/null; echo "cutover-steps.sh (sha256 $SELF_SHA) $CMDLINE: step $1, exit $rc ($r)" > "$RLOG" 2>/dev/null
    if [ "$(id -u)" = 0 ]; then chmod a+rx "$RDIR" 2>/dev/null; chmod a+r "$RLOG" 2>/dev/null
      runuser -u "${CUTOVER_OPERATOR:-}" -- "$tell" --title "$t" --message-file "$RLOG" --script "$(cd "$(dirname "$0")" && pwd -P)/$(basename "$0")" --result "$r" --step "$1" --log "$RLOG"
    else "$tell" --title "$t" --message-file "$RLOG" --script "$(cd "$(dirname "$0")" && pwd -P)/$(basename "$0")" --result "$r" --step "$1" --log "$RLOG"
    fi >/dev/null 2>&1 || { echo "cutover: report not delivered; it is $RLOG:" >&2; cat "$RLOG" >&2; }
    exit $rc; }
  trap 'report "$STEPNAME"' EXIT
fi
CMDLINE="$*"; STEPNAME=${3:-none}; [ "${1:-}" != --check ] || STEPNAME=check${4:+-$4}
case ${1:-} in --check)
  bash -n "$0" && command -v git >/dev/null && command -v tar >/dev/null && command -v awk >/dev/null &&
    { command -v sha256sum >/dev/null || command -v shasum >/dev/null; } && echo "cutover-steps.sh: check ok (sha256 $SELF_SHA)" || exit 1
  [ $# = 4 ] && [ "$4" = p1a ] || { [ $# = 1 ] && exit 0; echo "usage: cutover-steps.sh --check [ROOT J p1a]" >&2; exit 1; }
  CHECK=$(mktemp -d "${CUTOVER_CHECK_DIR:-$TSDIR}/cutover-p1a-check.XXXXXX") && [ -d "$3" ] && cp -a "$3/." "$CHECK/J" || exit 1
  echo "cutover: P1a check: scratch $CHECK"
  set -- "$2" "$CHECK/J" p1a-check ;; esac
[ $# = 3 ] || { [ $# = 4 ] && case ${3:-} in forward|unfreeze-gate|preserved) true ;; *) false ;; esac; } ||
  { echo "usage: cutover-steps.sh ROOT J p0|p1-pre|p1a|p2|forward [CP]|rollback|recover|unfreeze-gate r0|p10|r6|preserved" >&2; exit 1; }
ROOT=$(cd "$1" && pwd -P) && J=$(cd "$2" && pwd -P) || exit 1
CMD=$3; UNTIL=${4:-c3}; Q=$J/Q
BD=${CUTOVER_BD:-bd}
export GIT_INTERNAL_CRASH_AT=${CUTOVER_CRASH_AT:-} GIT_INTERNAL_CRASH_COUNT=${CUTOVER_CRASH_COUNT:-} GIT_INTERNAL_CRASH_LOG=${CUTOVER_CRASH_LOG:-}

fetch_origin() {  # a real run fetches; the P1a check compares with ls-remote and writes nothing
  if [ -z "$CHECK" ]; then pg fetch -q origin || exit 2
  else [ "$(pg ls-remote origin refs/heads/main | cut -f1)" = "$(pg rev-parse refs/remotes/origin/main)" ] ||
    refuse "check: origin/main differs from the remote-tracking ref (the real run fetches it); re-run after a fetch"; fi; }
stop() { echo "cutover: STOP: $*" >&2; exit 3; }
refuse() { rm -rf -- "${J:?}"/p1a-check.*; echo "cutover: refused, nothing written: $*" >&2; exit 1; }   # P1a's check dir goes too
crash_point() {  # name : tests only
  [ -n "${CUTOVER_CRASH_AT:-}" ] || return 0
  local n; n=$(cat "${CUTOVER_CRASH_COUNT:?}" 2>/dev/null) || n=0
  n=$((n+1)); echo "$n" > "$CUTOVER_CRASH_COUNT"
  [ -z "${CUTOVER_CRASH_LOG:-}" ] || echo "$n cutover $1" >> "$CUTOVER_CRASH_LOG"
  [ "$n" != "$CUTOVER_CRASH_AT" ] || kill -KILL $$
}
fsync_path() { [ -e "$1" ] || [ -L "$1" ] || return 1; sync "$1" 2>/dev/null || sync; }   # a missing path fails; BSD sync takes no operand
put() {  # file text : atomic, durable replace
  local t="$1.tmp.$$"
  printf '%s\n' "$2" > "$t" && fsync_path "$t" || { rm -f -- "${t:?}"; return 1; }
  crash_point "$(basename "$1")-tmp"
  mv -f "$t" "$1" && fsync_path "$(dirname "$1")" || { rm -f -- "${t:?}"; return 1; }
  crash_point "$(basename "$1")"
}
pg() { git -C "$ROOT" ${1+"$@"}; }
link_text() { local t; t=$(readlink -- "$1" && printf x) || return 1; t=${t%x}; printf '%s' "${t%?}"; }
dg() {  # path : l:<link text sha>, x:/f:<content sha>, d (directory), - (absent)
  if [ -L "$1" ]; then printf 'l:%s\n' "$(link_text "$1" | sha)"
  elif [ -d "$1" ]; then echo d
  elif [ -f "$1" ] && [ -x "$1" ]; then printf 'x:%s\n' "$(sha < "$1")"
  elif [ -f "$1" ]; then printf 'f:%s\n' "$(sha < "$1")"
  else echo -; fi
}
present() { [ -e "$1" ] || [ -L "$1" ]; }
internal() { local pre; while IFS= read -r pre; do [ -n "$pre" ] || continue; case $1 in "$pre"*) return 0 ;; esac; done < "$J/delete-list"; return 1; }
manifest() {  # base : "<digest>\t<path>" for every file and symlink of the internal set under base
  local pre p
  while IFS= read -r pre; do
    [ -n "$pre" ] && present "$1/${pre%/}" || continue
    (cd "$1" && find "${pre%/}" \( -type f -o -type l \) -print)
  done < "$J/delete-list" | sort -u | while IFS= read -r p; do printf '%s\t%s\n' "$(dg "$1/$p")" "$p"; done
}
cp_line() { cat "$J/cp" 2>/dev/null; }
cp_name() { local l; l=$(cp_line); echo "${l%% *}"; }
at() {  # checkpoint... : J/cp names one of them and HEAD is the HEAD recorded there
  local c h; read -r c h < "$J/cp" || refuse "no checkpoint (run p2)"
  case " $* " in *" $c "*) ;; *) return 1 ;; esac
  [ "$(pg rev-parse HEAD)" = "$h" ] || stop "HEAD is $(pg rev-parse HEAD), checkpoint $c recorded $h; no intent explains it"
}
status_within() {  # extra-allowed-lines-file : every public status line is in P2's status or in the file
  local line
  while IFS= read -r line; do grep -qxF -- "$line" "$J/p2.status" "$1" || { echo "cutover: unexplained status: $line" >&2; return 1; }; done < <(pg status --porcelain)
}
ledger_deletions() {  # the P6 ledger as status lines: every quarantined path may show ' D'
  [ ! -e "$J/done-p6" ] || awk -F'\t' -v r="$ROOT/" '$1=="mv" && index($3, r)==1 {print " D " substr($3, length(r)+1)}' "$J/done-p6"; }

# ---- the ff op: the public pull as an idempotent roll forward OLD -> NEW
same_blob() {  # rev path : the path on disk has that entry's blob and mode
  local e mode b m
  { [ -L "$ROOT/$2" ] || [ -f "$ROOT/$2" ]; } || return 1
  e=$(pg ls-tree "$1" -- "$2") && [ -n "$e" ] || return 1
  mode=${e%% *}; b=${e#* }; b=${b#* }; b=${b%%	*}
  if [ -L "$ROOT/$2" ]; then m=120000; elif [ -x "$ROOT/$2" ]; then m=100755; else m=100644; fi
  [ "$m" = "$mode" ] || return 1
  if [ -L "$ROOT/$2" ]; then [ "$(link_text "$ROOT/$2" | pg hash-object --no-filters --stdin)" = "$b" ]
  else [ "$(pg hash-object -- "$ROOT/$2")" = "$b" ]; fi
}
FA=(); FM=(); FD=()
in_keep() { [ -n "${KEEPF:-}" ] && cut -f2 "$KEEPF" | grep -qxF -- "$1"; }
ff_lists() { local st p; FA=(); FM=(); FD=()   # KEEPF set (realign): the KEEP paths are left out
  while IFS= read -r -d '' st && IFS= read -r -d '' p; do
    in_keep "$p" && continue
    case $st in A) FA+=("$p") ;; D) FD+=("$p") ;; *) FM+=("$p") ;; esac
  done < <(pg diff --no-renames --name-status -z "$1" "$2"); }
ff_pre() {  # old new : HEAD old, index old or new, each changed path old or new
  local p d t bad=0
  pg symbolic-ref -q HEAD >/dev/null && [ "$(pg rev-parse HEAD)" = "$1" ] || return 1
  t=$(pg write-tree 2>/dev/null); [ "$t" = "$(pg rev-parse "$1^{tree}")" ] || [ "$t" = "$(pg rev-parse "$2^{tree}")" ] || return 1
  ff_lists "$1" "$2"
  for p in ${FA[@]+"${FA[@]}"}; do
    same_blob "$2" "$p" && continue
    present "$ROOT/$p" && { echo "cutover: incoming $p exists on disk" >&2; bad=1; continue; }
    d=$(dirname "$p"); while [ "$d" != . ]; do
      { [ -L "$ROOT/$d" ] || { [ -e "$ROOT/$d" ] && [ ! -d "$ROOT/$d" ]; }; } && { echo "cutover: $d blocks $p" >&2; bad=1; break; }
      d=$(dirname "$d"); done
  done
  for p in ${FD[@]+"${FD[@]}"}; do present "$ROOT/$p" && ! same_blob "$1" "$p" && { echo "cutover: $p has a local edit" >&2; bad=1; }; done
  for p in ${FM[@]+"${FM[@]}"}; do same_blob "$1" "$p" || same_blob "$2" "$p" || { echo "cutover: $p holds neither entry" >&2; bad=1; }; done
  return $bad
}
ff_act() {  # old new [op] : after ff_pre; writes what is still old, then index, then HEAD (realign: main)
  local p idx="$J/ff-index.$$" k=${3:-ff} ref=HEAD
  [ "$k" = ff ] || ref=refs/heads/main
  GIT_INDEX_FILE=$idx pg read-tree "$2" || stop "read-tree $2"
  for p in ${FA[@]+"${FA[@]}"}; do same_blob "$2" "$p" && continue
    GIT_INDEX_FILE=$idx pg checkout-index -- "$p" || stop "$p appeared"; crash_point $k-write; done
  for p in ${FM[@]+"${FM[@]}"}; do same_blob "$2" "$p" && continue
    GIT_INDEX_FILE=$idx pg checkout-index -f -- "$p" || stop "write $p"; crash_point $k-write; done
  for p in ${FD[@]+"${FD[@]}"}; do present "$ROOT/$p" || continue
    rm -f -- "${ROOT:?}/${p:?}" || stop "remove $p"; crash_point $k-remove; done
  rm -f -- "${idx:?}"
  pg read-tree "$2" || stop "read-tree $2"; pg update-index -q --refresh >/dev/null; crash_point $k-index
  pg update-ref -m "cutover $k" $ref "$2" "$1" || stop "HEAD moved"; crash_point $k-head
}

# ---- Gate 0 (revision 9.1-9.5): the tag and realign ops and their records
TGD=''
tdg() {  # rev path : the tree entry in dg form (- absent, d tree, g:<sha> gitlink); TGD names another repo
  local e mode b t d g="${TGD:-$ROOT}"
  e=$(git -C "$g" ls-tree --full-tree "$1" -- "$2") || return 1; [ -n "$e" ] || { echo -; return 0; }
  mode=${e%% *}; b=${e#* }; b=${b#* }; b=${b%%	*}
  case $mode in 120000) t=l ;; 100755) t=x ;; 100644) t=f ;; 040000) echo d; return 0 ;; *) printf 'g:%s\n' "$b"; return 0 ;; esac
  # a failed blob read must not become the digest of no input
  d=$(set -o pipefail; git -C "$g" cat-file blob "$b" | sha) && [[ $d =~ ^[0-9a-f]{64}$ ]] ||
    { echo "cutover: cannot read blob $b ($2 at $1)" >&2; return 1; }
  printf '%s:%s\n' "$t" "$d"; }
cls() {  # path : internal, or the class of the first dispositions glob it matches, else unmapped
  local c g; internal "$1" && { echo internal; return; }
  while IFS=$'\t' read -r c g; do [ -n "$c" ] || continue
    case $1 in $g) [ "$c" = internal ] && c=unmapped; echo "$c"; return ;; esac
  done < "$J/dispositions"; echo unmapped; }
wpaths() {  # rev : the W-snapshot domain: the internal set on disk and in rev, and every tracked change
  { manifest "$ROOT" | cut -f2; pg ls-tree -r --name-only "$1" -- $(cat "$J/delete-list"); pg diff --no-renames --name-only "$1"; } | sort -u; }
wstate() { local p; while IFS= read -r p; do printf '%s\t%s\n' "$(dg "$ROOT/$p")" "$p"; done; }   # paths on stdin
wman() { wpaths "$1" | wstate; }
ds() {  # old mb : the disposition set: the local commits' paths and every path whose disk differs from old
  { pg diff --no-renames --name-only "$2" "$1"
    wman "$1" | while IFS=$'\t' read -r d p; do [ "$d" = "$(tdg "$1" "$p")" ] || echo "$p"; done; } | sort -u; }
keep_ok() { local s p; while IFS=$'\t' read -r s p; do [ "$(dg "$ROOT/$p")" = "$s" ] || return 1; done < "$1"; }
holds() { if [ "$(tdg "$1" "$2")" = - ]; then ! present "$ROOT/$2"; else same_blob "$1" "$2"; fi; }   # rev path
jsonl_dominated() {  # x export : every record of x is in export, equal or with a later updated_at (export must exist)
  [ -f "$2" ] || { echo "cutover: no export file $2" >&2; return 1; }
  awk 'function id(l) { return match(l, /"id":"[^"]*"/) ? substr(l, RSTART+6, RLENGTH-7) : "" }
       function up(l) { return match(l, /"updated_at":"[^"]*"/) ? substr(l, RSTART+14, RLENGTH-15) : "" }
       FILENAME == ARGV[1] { k = id($0); if (k != "") { E[k] = $0; U[k] = up($0) }; next }
       /^[[:space:]]*$/ { next }
       { k = id($0); if (k == "" || !(k in E)) { print "cutover: record " k " is not in the export" > "/dev/stderr"; bad = 1 }
         else if (E[k] != $0 && !(U[k] > up($0))) { print "cutover: record " k " is newer than the export" > "/dev/stderr"; bad = 1 } }
       END { exit bad }' "$2" "$1"; }
realign_pre() {  # old new keep : only in the p1a and r0a intents ($step of run_intent)
  case ${step:-} in p1a|r0a) ;; *) echo "cutover: realign outside p1a/r0a" >&2; return 1 ;; esac
  [ "$(pg symbolic-ref -q HEAD)" = refs/heads/main ] && keep_ok "$3" || return 1
  KEEPF=$3 ff_pre "$1" "$2"
}
lane_tip() { pg ls-remote "$LANE" "refs/heads/$1" | cut -f1; }
LANE=lane; [ ! -e "$J/lane-remote" ] || LANE=$(cat "$J/lane-remote")

# ---- the generic step runner
op_post() { case $1 in
  mv) [ "$(dg "$4")" = "$2" ] && { [ "${5:-}" = refill ] || ! present "$3"; } ;;
  ff) [ "$(pg rev-parse HEAD)" = "$3" ] ;;
  install) [ -e "$ROOT/.git-internal/info/installed" ] ;;
  tag) [ "$(pg rev-parse -q --verify "refs/tags/$2")" = "$3" ] ;;
  realign) [ "$(pg rev-parse HEAD)" = "$3" ] && [ "$(pg symbolic-ref -q HEAD)" = refs/heads/main ] && keep_ok "$4" ;;
  w|from) true ;;
  *) stop "unknown op $1" ;; esac; }
op_pre() { case $1 in
  mv) [ "$(dg "$3")" = "$2" ] && ! present "$4" ;;
  ff) ff_pre "$2" "$3" ;;
  tag) ! pg rev-parse -q --verify "refs/tags/$2" >/dev/null ;;
  realign) realign_pre "$2" "$3" "$4" ;;
  install) true ;; esac; }
op_act() { local rc; case $1 in
  mv) mkdir -p "$(dirname "$4")" && mv "$3" "$4" && fsync_path "$(dirname "$4")" && fsync_path "$(dirname "$3")" || stop "mv $3"
      crash_point mv ;;
  ff) ff_act "$2" "$3" ;;
  tag) pg update-ref "refs/tags/$2" "$3" "" || stop "tag $2"; crash_point tag ;;
  realign) ff_act "$2" "$3" realign ;;
  install) "$(cat "$J/helper")" -C "$ROOT" install "$2" "$3"; rc=$?
           [ $rc = 137 ] && kill -KILL $$       # the helper hit the shared crash point
           [ $rc = 0 ] || stop "git-internal install exited $rc" ;; esac; }
step_check() { case $1 in
  p6) [ "$(manifest "$Q")" = "$(cat "$J/p2.manifest")" ] && [ -z "$(manifest "$ROOT")" ] &&
      { grep -v '^$' "$J/p2.status" | while IFS= read -r l; do internal "${l#???}" || echo "$l"; done
        pg ls-files -- $(cat "$J/delete-list") | sed 's/^/ D /'; } | sort > "$J/p6.status" &&
      [ "$(pg status --porcelain | sort)" = "$(cat "$J/p6.status")" ] ;;
  p7) [ -z "$(pg status --porcelain)" ] &&
      [ "$(pg diff --no-renames --name-only --diff-filter=D "$(awk -F'\t' '$1=="ff"{print $2}' "$J/intent")" HEAD | sort)" = "$(cat "$J/removed.manifest")" ] ;;
  p8) local p; [ -e "$ROOT/.git-internal/info/installed" ] &&
      [ "$(manifest "$ROOT" | cut -f2)" = "$(sort -u "$J/shared.manifest" "$J/local.manifest")" ] &&
      [ -z "$(git -C "$ROOT" --git-dir="$ROOT/.git-internal" status --porcelain)" ] && [ -z "$(pg status --porcelain)" ] &&
      while IFS= read -r p; do [ "$(dg "$ROOT/$p")" = "$(awk -F'\t' -v p="$p" '$2==p{print $1}' "$J/p2.manifest")" ] || return 1; done < "$J/local.manifest" ;;
  r1) local p; ! present "$ROOT/.git-internal" && ! present "$ROOT/.git-internal.new" &&
      while IFS= read -r p; do ! present "$ROOT/$p" || return 1; done < "$J/shared.manifest" &&
      while IFS= read -r p; do present "$Q/$p" || return 1; done < "$J/local.manifest" ;;
  r3) case $(awk -F'\t' '$1=="from"{print $2}' "$J/intent") in
        c0) [ "$(pg status --porcelain)" = "$(cat "$J/p2.status")" ] ;;
        c1) ledger_deletions > "$J/r3.allowed"; status_within "$J/r3.allowed" ;;
        *)  [ -z "$(pg status --porcelain)" ] ;; esac ;;
  r4) [ "$(manifest "$ROOT")" = "$(cat "$J/p2.manifest")" ] ;;
  p1a) local b o p KEEPF=$J/keep.list; b=$(cat "$J/base"); o=$(cat "$J/p1-pre/head")
      [ "$(pg rev-parse HEAD)" = "$b" ] && [ "$(pg rev-parse refs/remotes/origin/main)" = "$b" ] &&
      [ "$(pg rev-list --left-right --count HEAD...refs/remotes/origin/main)" = "0	0" ] &&
      [ "$(pg reflog show -n 1 --format=%gs refs/heads/main)" = "cutover realign" ] &&
      [ "$(pg rev-parse -q --verify "refs/tags/gate0/$(cat "$J/host")-$o")" = "$o" ] &&
      [ "$(pg write-tree)" = "$(pg rev-parse "$b^{tree}")" ] && keep_ok "$J/keep.list" || return 1
      while IFS= read -r p; do in_keep "$p" || holds "$b" "$p" || { echo "cutover: P1a: $p does not hold the base entry" >&2; return 1; }
      done < <(pg diff --no-renames --name-only "$o" "$b")
      p1a_status "$o" "$b" > "$J/p1a.status" && [ "$(pg status --porcelain -uall | sort)" = "$(cat "$J/p1a.status")" ] ;;
  r0a) local o; o=$(cat "$J/p1-pre/head")
      [ "$(pg rev-parse HEAD)" = "$o" ] && [ "$(pg rev-parse -q --verify "refs/tags/gate0/$(cat "$J/host")-$o")" = "$o" ] &&
      [ "$(pg write-tree)" = "$(pg rev-parse "$o^{tree}")" ] &&
      [ "$(pg status --porcelain -uall)" = "$(cat "$J/p1-pre/status.all")" ] &&
      [ "$(manifest "$ROOT")" = "$(cat "$J/p1-pre/pre.manifest")" ] &&
      [ "$(cut -f2 "$J/capture/wtree.manifest" | wstate)" = "$(cat "$J/capture/wtree.manifest")" ] ;;
  *) false ;; esac; }
p1a_status() {  # old base : the expected status against the base: P1-pre's lines off the write set, plus each KEEP path's
  local l p t w
  pg diff --no-renames --name-only "$1" "$2" > "$J/p1a.ws"
  { while IFS= read -r l; do grep -qxF -- "${l#???}" "$J/p1a.ws" || echo "$l"; done < "$J/p1-pre/status.all"
    while IFS=$'\t' read -r w p; do grep -qxF -- "$p" "$J/p1a.ws" || continue; t=$(tdg "$2" "$p")
      if [ "$t" = - ]; then [ "$w" = - ] || pg check-ignore -q --no-index -- "$p" || echo "?? $p"
      elif [ "$w" = - ]; then echo " D $p"
      elif [ "$w" = "$t" ]; then :
      elif [ "$([ "${w%%:*}" = l ] && echo l)" != "$([ "${t%%:*}" = l ] && echo l)" ]; then echo " T $p"
      else echo " M $p"; fi
    done < "$J/keep.list"; } | sort; }
run_intent() {
  local step tcp th op a b c e first=1
  read -r step tcp th < "$J/intent" || stop "unreadable $J/intent"
  if [ "$(cp_line)" != "$tcp $th" ]; then
    while IFS=$'\t' read -r op a b c e <&9; do
      [ $first = 1 ] && { first=0; continue; }
      [ -n "$op" ] || continue     # a step with no ops (R1 or R4 with nothing to move)
      op_post "$op" "$a" "$b" "$c" "$e" && continue
      op_pre "$op" "$a" "$b" "$c" || stop "$step: '$op $a $b $c' is in neither its old nor its new state"
      op_act "$op" "$a" "$b" "$c"
      op_post "$op" "$a" "$b" "$c" "$e" || stop "$step: '$op $a $b $c' did not reach its new state"
    done 9< "$J/intent"
    step_check "$step" || stop "$step: its check failed; the intent is kept"
    put "$J/cp" "$tcp $th" || stop "cannot write $J/cp"
  fi
  mv -f "$J/intent" "$J/done-$step" && fsync_path "$J" || stop "cannot retire $J/intent"
  crash_point intent-done
}
begin() {  # ops-file step target-cp target-head : the intent, durable before the first write
  put "$J/intent" "$2 $3 $4
$(cat "$1")" || refuse "cannot write $J/intent"
  rm -f -- "${1:?}"; run_intent
}
cleanup() { rm -rf -- "${J:?}"/*.tmp.* "${J:?}"/ff-index.* "${J:?}"/ops.*; }   # this script's own temporaries
recover() { cleanup; [ ! -e "$J/intent" ] || run_intent; }

# ---- steps; each first checks, writing nothing on refusal
p6() {
  local d p h ops="$J/ops.$$"; at c0 || return 0; h=$(pg rev-parse HEAD)
  [ "$(manifest "$ROOT")" = "$(cat "$J/p2.manifest")" ] || stop "P6: the internal set differs from P2 (external write)"
  while IFS=$'\t' read -r d p; do printf 'mv\t%s\t%s\t%s\n' "$d" "$ROOT/$p" "$Q/$p"; done < "$J/p2.manifest" > "$ops"
  begin "$ops" p6 c1 "$h"
}
p7() {
  local h t ops="$J/ops.$$"; at c1 || return 0; h=$(pg rev-parse HEAD)
  pg fetch -q origin || exit 2; t=$(pg rev-parse origin/main)
  pg merge-base --is-ancestor "$h" "$t" || refuse "P7: origin/main is not a fast-forward"
  [ "$(pg diff --no-renames --name-only --diff-filter=D "$h" "$t" | sort)" = "$(cat "$J/removed.manifest")" ] || refuse "P7: the pull's removed set differs from removed.manifest"
  ff_pre "$h" "$t" || refuse "P7: the checkout is not ready for the pull"
  printf 'ff\t%s\t%s\n' "$h" "$t" > "$ops"; begin "$ops" p7 c2 "$t"
}
p8() {
  local h p ops="$J/ops.$$"; at c2 || return 0; h=$(pg rev-parse HEAD)
  ! present "$ROOT/.git-internal" && ! present "$ROOT/.git-internal.new" || refuse "P8: .git-internal exists"
  while IFS= read -r p; do ! present "$ROOT/$p" || refuse "P8: $p exists (external write)"; done < <(cat "$J/shared.manifest" "$J/local.manifest")
  { printf 'install\t%s\t%s\n' "$(cat "$J/url")" "$(cat "$J/host")"
    sed 's/^/w\t/' "$J/shared.manifest"
    while IFS= read -r p; do printf 'mv\t%s\t%s\t%s\n' "$(awk -F'\t' -v p="$p" '$2==p{print $1}' "$J/p2.manifest")" "$Q/$p" "$ROOT/$p"; done < "$J/local.manifest"
  } > "$ops"
  begin "$ops" p8 c3 "$h"
}
r1() {  # from c3, or superseding an unfinished P8: set aside what P8 wrote, return the local files
  local h src op a b c ops="$J/ops.$$"
  if [ -e "$J/intent" ]; then src="$J/intent"; put "$J/done-p8" "$(cat "$J/intent")" || stop "cannot keep the P8 ledger"
  else src="$J/done-p8"; fi
  at c2 c3 || stop "R1 needs c2 or c3"; h=$(pg rev-parse HEAD)
  { for a in .git-internal .git-internal.new; do present "$ROOT/$a" && printf 'mv\t%s\t%s\t%s\n' "$(dg "$ROOT/$a")" "$ROOT/$a" "$J/rollback-p8/$a"; done
    while IFS=$'\t' read -r op a b c; do case $op in
      w)  present "$ROOT/$a" && printf 'mv\t%s\t%s\t%s\n' "$(dg "$ROOT/$a")" "$ROOT/$a" "$J/rollback-p8/$a" ;;
      mv) present "$c" && printf 'mv\t%s\t%s\t%s\n' "$a" "$c" "$b" ;;
    esac; done < <(tail -n +2 "$src")
  } > "$ops"
  begin "$ops" r1 r1-done "$h"
}
r3() {  # pull the revert of PR 1
  local c h t ops="$J/ops.$$"; c=$(cp_name); at c0 c1 c2 r1-done || return 0; h=$(pg rev-parse HEAD)
  pg fetch -q origin || exit 2; t=$(pg rev-parse origin/main)
  pg merge-base --is-ancestor "$h" "$t" || refuse "R3: origin/main is not a fast-forward"
  [ "$(pg ls-tree -r --name-only "$t" -- $(cat "$J/delete-list") | sort)" = "$(cat "$J/removed.manifest")" ] ||
    refuse "R3: origin/main does not hold every removed.manifest path; R2 (mk's revert of PR 1) has not landed"
  case $c in
    c0) [ "$(pg status --porcelain)" = "$(cat "$J/p2.status")" ] ;;
    c1) ledger_deletions > "$J/r3.allowed"; status_within "$J/r3.allowed" ;;
    *)  [ -z "$(pg status --porcelain)" ] ;; esac || refuse "R3: status at $c"
  ff_pre "$h" "$t" || refuse "R3: the checkout is not ready for the revert"
  printf 'ff\t%s\t%s\nfrom\t%s\n' "$h" "$t" "$c" > "$ops"; begin "$ops" r3 r3-done "$t"
}
r4() {  # restore the quarantine, setting aside what the revert wrote at those paths
  local h d s p ops="$J/ops.$$"; at r3-done || return 0; h=$(pg rev-parse HEAD)
  ledger_deletions > "$J/r4.allowed"; status_within "$J/r4.allowed" || refuse "R4: status"
  [ ! -e "$J/done-p6" ] || while IFS=$'\t' read -r _ d s p; do   # done-p6: mv DIGEST ROOT/p Q/p
    present "$s" && printf 'mv\t%s\t%s\t%s\trefill\n' "$(dg "$s")" "$s" "$J/rollback-revert/${s#"$ROOT"/}"
    printf 'mv\t%s\t%s\t%s\n' "$d" "$p" "$s"
  done < <(tail -n +2 "$J/done-p6") > "$ops"
  [ -e "$ops" ] || : > "$ops"
  begin "$ops" r4 r4-done "$h"
}
r5() {
  local h; at r4-done || return 0; h=$(pg rev-parse HEAD)
  [ "$(manifest "$ROOT")" = "$(cat "$J/p2.manifest")" ] && [ "$(pg status --porcelain)" = "$(cat "$J/p2.status")" ] || stop "R5: not the P2 state"
  put "$J/cp" "r5 $h" || stop "cannot write $J/cp"
}

# ---- Gate 0 steps
gate0() { [ -e "$J/base" ] && [ -e "$J/host" ] && [ -e "$J/dispositions" ] || refuse "Gate 0 needs J/base, J/host and J/dispositions"; }
classes() {  # allowed... : each path on stdin is in one of these classes
  local p c; while IFS= read -r p; do c=$(cls "$p")
    case " $* " in *" $c "*) ;; *) echo "cutover: $p is class $c" >&2; return 1 ;; esac; done; }
p0() {  # RH stand-in for P0's report: read-only in the checkout except the local ref refs/gate0/lane
  local o b l t="$J/p0.tmp.$$" c p; gate0; b=$(cat "$J/base"); o=$(pg rev-parse HEAD)
  rm -rf -- "${J:?}/p0"; mkdir "$t" || refuse "cannot write $t"
  echo "$o" > "$t/old"; pg rev-list "$b..$o" > "$t/commits"; l=$(lane_tip "autosync/$(cat "$J/host")"); echo "$l" > "$t/lane"
  : > "$t/lane-only"
  [ -z "$l" ] || { pg fetch -q "$LANE" "+refs/heads/autosync/$(cat "$J/host"):refs/gate0/lane" || exit 2; pg rev-list "$o..$l" > "$t/lane-only"; }
  for c in $(cat "$t/commits" "$t/lane-only"); do
    pg diff-tree -r -m --root --no-renames --name-only --no-commit-id "$c" | sort -u | while IFS= read -r p; do printf '%s\t%s\t%s\n' "$c" "$(cls "$p")" "$p"; done
  done > "$t/inventory"
  wman "$o" > "$t/wtree.manifest"; mv "$t" "$J/p0"
}
p1pre() {  # read-only in the checkout; writes only J/p1-pre
  local b o o0 l l0 c p gd rc t="$J/p1-pre.tmp.$$"; gate0; [ -d "$J/p0" ] || refuse "no P0 record"
  [ ! -e "$J/cp" ] || refuse "P1-pre runs before P1a only (checkpoint $(cp_name))"
  b=$(cat "$J/base"); o0=$(cat "$J/p0/old"); l0=$(cat "$J/p0/lane")
  fail() { rm -rf -- "${t:?}"; stop "P1-pre: $*; re-run P0 and get a fresh approval"; }
  rm -rf -- "${J:?}"/p1-pre.tmp.*; mkdir "$t" || refuse "cannot write $t"
  [ "$(pg symbolic-ref -q HEAD)" = refs/heads/main ] || fail "HEAD is not main"
  gd=$(pg rev-parse --absolute-git-dir)
  for p in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG rebase-merge rebase-apply; do ! present "$gd/$p" || fail "operation state $p"; done
  [ -z "$(pg ls-files -u)" ] || fail "unmerged entries"
  pg diff --cached --quiet || fail "staged entries"
  ( fetch_origin ) || { rc=$?; rm -rf -- "${t:?}"; exit $rc; }
  [ "$(pg rev-parse refs/remotes/origin/main)" = "$b" ] || fail "origin/main is not the approved base"
  o=$(pg rev-parse HEAD)
  for c in $(cat "$J/p0/commits"); do pg merge-base --is-ancestor "$c" "$o" || fail "P0 commit $c is not in main"; done
  for c in $(cat "$J/p0/lane-only"); do pg merge-base --is-ancestor "$c" "$l0" || fail "P0 lane commit $c is not in the approved lane"; done
  pg merge-base --is-ancestor "$o0" "$o" || fail "P0's main is not an ancestor of main"
  cp "$J/p0/inventory" "$t/inventory"
  for c in $(pg rev-list "$o0..$o"); do
    pg diff-tree -r -m --root --no-renames --name-only --no-commit-id "$c" | sort -u > "$t/c"
    classes internal beads-export < "$t/c" || fail "new commit $c touches a path outside the approved classes"
    while IFS= read -r p; do printf '%s\t%s\t%s\n' "$c" "$(cls "$p")" "$p"; done < "$t/c" >> "$t/inventory"
  done; rm -f -- "$t/c"
  wman "$o" > "$t/wtree.manifest"
  awk -F'\t' 'NR==FNR {a[$2]=$1; next} {if (a[$2] != $1) print $2; delete a[$2]} END {for (p in a) print p}' \
    "$J/p0/wtree.manifest" "$t/wtree.manifest" | sort -u | classes internal beads-export || fail "a W-snapshot entry changed on a path outside the approved classes"
  ds "$o" "$(pg merge-base "$o" "$b")" | classes internal pr1 ops-12a beads-export drop || fail "a disposition-set path has no disposition"
  l=$(lane_tip "autosync/$(cat "$J/host")"); : > "$t/lane-archive"
  if [ -z "$l" ]; then [ -z "$l0" ] || fail "the lane was deleted since P0"
  elif [ "$l" = "$o" ] || { pg cat-file -e "$l^{commit}" 2>/dev/null && pg merge-base --is-ancestor "$l" "$o"; }; then :
  elif [ "$l" = "$l0" ]; then echo "$l" > "$t/lane-archive"
  else fail "the lane tip $l is neither in main nor P0's approved lane"; fi
  pg status --porcelain --untracked-files=no | while IFS= read -r p; do internal "${p#???}" || { echo "cutover: $p" >&2; exit 1; }; done ||
    fail "a tracked change outside the internal set"
  echo "$o" > "$t/head"; echo "$l" > "$t/lane"
  pg status --porcelain > "$t/status"; pg status --porcelain -uall > "$t/status.all"
  grep '^?? ' "$t/status.all" | while IFS= read -r p; do internal "${p#???}" || echo "${p#???}"; done > "$t/untracked"
  manifest "$ROOT" > "$t/pre.manifest"
  rm -rf -- "${J:?}/p1-pre"; mv "$t" "$J/p1-pre" && fsync_path "$J"
}
archive() {  # branch sha [check] : absent or equal on the lane (check: only verify), then pushed and read back
  local r; r=$(lane_tip "$1")
  [ -z "$r" ] || [ "$r" = "$2" ] || refuse "P1a: $1 is at $r on the lane, not $2"
  [ -z "${3:-}" ] || return 0
  [ -n "$r" ] || pg push -q --no-follow-tags "$LANE" "$2:refs/heads/$1" || stop "P1a: push $1"
  crash_point archive
  [ "$(lane_tip "$1")" = "$2" ] || stop "P1a: $1 does not read back as $2"
}
p1a() {  # capture and preserve (a0), then the realign intent to a1
  local b o mb h l la p c t m BR C="$J/capture.tmp" X="$J/p1a-check.$$"; gate0; recover
  if [ -e "$J/cp" ]; then case $(cp_name) in a0) p1a_realign; return ;; a1) return 0 ;; *) refuse "P1a after checkpoint $(cp_name)" ;; esac; fi
  [ -d "$J/p1-pre" ] || refuse "no P1-pre record"
  b=$(cat "$J/base"); o=$(cat "$J/p1-pre/head"); h=$(cat "$J/host"); l=$(cat "$J/p1-pre/lane"); la=$(cat "$J/p1-pre/lane-archive")
  [ "$o" != "$b" ] || refuse "main equals the base; P1a does not run"
  [ "$(pg rev-parse HEAD)" = "$o" ] || refuse "HEAD moved since P1-pre"
  fetch_origin
  [ "$(pg rev-parse refs/remotes/origin/main)" = "$b" ] || refuse "origin/main moved since P1-pre"
  [ "$(pg status --porcelain -uall)" = "$(cat "$J/p1-pre/status.all")" ] && [ "$(wman "$o")" = "$(cat "$J/p1-pre/wtree.manifest")" ] ||
    refuse "the checkout changed since P1-pre"
  [ "$(lane_tip "autosync/$h")" = "$l" ] || refuse "the lane moved since P1-pre"
  mb=$(pg merge-base "$o" "$b") || refuse "no merge base"
  rm -rf -- "${J:?}"/p1a-check.*; mkdir "$X" || refuse "cannot write $X"
  ds "$o" "$mb" > "$X/ds"; pg diff --no-renames --name-only "$o" "$b" > "$X/ws"
  while IFS= read -r p; do c=$(cls "$p"); case $c in
    internal|ops-12a|drop) ;;
    pr1) m=$(cat "$J/pr1-head"); pg cat-file -e "$m^{commit}" 2>/dev/null || refuse "P1a: PR 1's head $m is not here"
         for t in mb o m; do pg show "${!t}:$p" > "$X/$t" 2>/dev/null || : > "$X/$t"; done   # an absent side is empty
         git merge-file -p "$X/o" "$X/mb" "$X/m" > "$X/merged" && cmp -s "$X/merged" "$X/m" ||
           refuse "P1a: PR 1 does not carry the local change to $p" ;;
    beads-export) [ -e "$X/export.done" ] || { "$BD" export -o "$X/export.jsonl" >/dev/null 2>"$X/bd.err" && : > "$X/export.done"; } ||
           refuse "P1a: bd export failed"
         [ -f "$X/export.jsonl" ] || refuse "P1a: bd export wrote no file"
         for t in "$o" "$b"; do pg show "$t:$p" > "$X/jsonl" 2>/dev/null || : > "$X/jsonl"
           grep -q '"id":"' "$X/jsonl" && ! grep -q '"id":"' "$X/export.jsonl" && refuse "P1a: the tracker export is empty but the $p at $t has records"
           jsonl_dominated "$X/jsonl" "$X/export.jsonl" || refuse "P1a: the $p records at $t are not dominated by the tracker"; done ;;
    *) refuse "P1a: $p has no disposition ($c)" ;; esac; done < "$X/ds"
  [ -z "$la" ] || archive "archive/gate0/$h/lane-$la" "$la" check
  archive "archive/gate0/$h/$o" "$o" check
  { cat "$X/ws" "$X/ds"; } | sort -u | while IFS= read -r p; do internal "$p" && echo "$p"; done > "$X/keep"
  sort -u "$X/keep" "$X/ds" > "$X/w"
  wstate < "$X/keep" > "$X/keep.list"
  KEEPF=$X/keep.list ff_pre "$o" "$b" || refuse "P1a: the checkout is not ready for the realign"
  # nothing is written to the checkout before this point except fetched remote-tracking refs
  rm -rf -- "${C:?}" "${J:?}/capture"; mkdir "$C" || refuse "cannot write $C"
  BR=$ROOT
  if [ -n "$CHECK" ]; then BR=$CHECK/repo   # the check bundles from a scratch repository; the checkout gets no ref
    git init -q --bare "$BR" && git -C "$BR" fetch -q "$ROOT" refs/heads/main:refs/heads/main refs/remotes/origin/main:refs/gate0/base || stop "P1a check: scratch repo"
  else pg update-ref refs/gate0/base "$b" || stop "P1a: refs/gate0/base"; fi
  crash_point gate0-base
  set -- main refs/gate0/base
  [ -z "$la" ] || { git -C "$BR" fetch -q "$(pg remote get-url "$LANE" 2>/dev/null || echo "$LANE")" "+refs/heads/autosync/$h:refs/gate0/lane" || exit 2
    crash_point lane-fetch
    [ "$(git -C "$BR" rev-parse refs/gate0/lane)" = "$la" ] || stop "P1a: the lane moved during capture"; set -- "$@" refs/gate0/lane; }
  git -C "$BR" bundle create -q "$C/main.bundle" "$@" 2>/dev/null || stop "P1a: bundle"; crash_point capture-bundle
  while IFS= read -r p; do printf '%s\t%s\t%s\t%s\n' "$(tdg "$o" "$p")" "$(tdg "$mb" "$p")" "$(tdg "$b" "$p")" "$p"; done < "$X/ds" > "$C/digests"
  crash_point capture-digests
  wstate < "$X/w" > "$C/wtree.manifest"
  ! grep -q '^d	' "$C/wtree.manifest" || stop "P1a: a directory where git expects a file: $(grep '^d	' "$C/wtree.manifest" | cut -f2 | head -n 1)"
  crash_point capture-wtree
  wstate < "$X/keep" > "$C/keep.list"; crash_point capture-keep
  grep -v '^-	' "$C/wtree.manifest" | cut -f2 > "$X/present"
  tar -C "$ROOT" --no-recursion -cf "$C/wtree.tar" -T "$X/present" || stop "P1a: tar"; crash_point capture-tar
  p1a_verify "$C" "$o" "$b" "$la"
  printf 'main.bundle\t%s\nwtree.tar\t%s\n' "$(sha < "$C/main.bundle")" "$(sha < "$C/wtree.tar")" > "$C/sha256"; crash_point capture-sha256
  if [ -n "$CHECK" ]; then
    [ "$(lane_tip "autosync/$h")" = "$l" ] || refuse "P1a check: the lane moved since P1-pre"
    rm -rf -- "${X:?}"; echo "cutover: P1a check: pass (capture checks in $C; nothing pushed or written outside $CHECK)"; exit 0; fi
  [ -z "$la" ] || archive "archive/gate0/$h/lane-$la" "$la"
  archive "archive/gate0/$h/$o" "$o"
  [ "$(lane_tip "autosync/$h")" = "$l" ] || stop "P1a: the lane moved during capture"
  for p in "$C"/*; do fsync_path "$p" || stop "P1a: cannot flush $p"; done   # each capture file is durable before the capture is published
  fsync_path "$C" && mv "$C" "$J/capture" && fsync_path "$J" || stop "P1a: cannot keep the capture"; crash_point capture
  rm -rf -- "${X:?}"
  cp "$J/capture/keep.list" "$J/keep.list.tmp.$$" && fsync_path "$J/keep.list.tmp.$$" && mv -f "$J/keep.list.tmp.$$" "$J/keep.list" && fsync_path "$J" ||
    stop "cannot write $J/keep.list"
  crash_point keep-publish
  put "$J/cp" "a0 $o" || stop "cannot write $J/cp"
  p1a_realign
}
p1a_verify() {  # capture old base lane-archive : test-restore the bundle and the W-snapshot from the capture alone
  local V="$1/verify" a m b p r
  rm -rf -- "${V:?}"; mkdir -p "$V/w" && git init -q --bare "$V/repo" || stop "P1a: verify dir"
  pg bundle verify -q "$1/main.bundle" >/dev/null 2>&1 || stop "P1a: bundle verify"
  git -C "$V/repo" fetch -q "$1/main.bundle" 'refs/*:refs/*' || stop "P1a: fetch from the bundle"
  [ "$(git -C "$V/repo" rev-parse refs/heads/main)" = "$2" ] && [ "$(git -C "$V/repo" rev-parse refs/gate0/base)" = "$3" ] &&
    { [ -z "$4" ] || [ "$(git -C "$V/repo" rev-parse refs/gate0/lane)" = "$4" ]; } || stop "P1a: the bundle's refs"
  r=$(git -C "$V/repo" merge-base "$2" "$3")
  while IFS=$'\t' read -r a m b p; do
    [ "$(TGD=$V/repo tdg "$2" "$p")" = "$a" ] && [ "$(TGD=$V/repo tdg "$r" "$p")" = "$m" ] && [ "$(TGD=$V/repo tdg "$3" "$p")" = "$b" ] ||
      stop "P1a: the bundle does not restore $p"; done < "$1/digests"
  tar -C "$V/w" -xpf "$1/wtree.tar" || stop "P1a: tar extract"
  [ "$(cut -f2 "$1/wtree.manifest" | while IFS= read -r p; do printf '%s\t%s\n' "$(dg "$V/w/$p")" "$p"; done)" = "$(cat "$1/wtree.manifest")" ] &&
    [ "$(cd "$V/w" && find . \( -type f -o -type l \) | wc -l | tr -d ' ')" = "$(grep -vc '^-	' "$1/wtree.manifest")" ] || stop "P1a: the W-snapshot does not restore"
  rm -rf -- "${V:?}"
}
p1a_realign() {
  local o b ops="$J/ops.$$"; at a0 || refuse "P1a realign needs a0"; o=$(pg rev-parse HEAD); b=$(cat "$J/base")
  printf 'tag\tgate0/%s-%s\t%s\nrealign\t%s\t%s\t%s\n' "$(cat "$J/host")" "$o" "$o" "$o" "$b" "$J/keep.list" > "$ops"
  begin "$ops" p1a a1 "$b"
}
r0a() {
  local h o c ops="$J/ops.$$"; [ -e "$J/done-p1a" ] || refuse "R0a: P1a did not run"
  c=$(cp_name); at a1 c0 || refuse "R0a needs a1 or c0"; h=$(pg rev-parse HEAD); o=$(cat "$J/p1-pre/head")
  printf 'realign\t%s\t%s\t%s\nfrom\t%s\n' "$h" "$o" "$J/keep.list" "$c" > "$ops"; begin "$ops" r0a a0r "$o"
}
before_p5() {  # true when PR 1's merge commit is not in origin/main. PR 1's head is no stand-in: a squash or
  # rebase merge leaves it out of main. Without a recorded merge sha, only origin/main still at the base proves
  # "before P5"; anything else is a STOP until the merge sha is recorded in J/pr1-merge.
  local m; pg fetch -q origin || exit 2
  if [ -e "$J/pr1-merge" ]; then m=$(cat "$J/pr1-merge")
    pg cat-file -e "$m^{commit}" 2>/dev/null || stop "rollback: the recorded PR 1 merge $m is not here"
    ! pg merge-base --is-ancestor "$m" refs/remotes/origin/main
  elif [ -e "$J/base" ] && [ "$(pg rev-parse refs/remotes/origin/main)" = "$(cat "$J/base")" ]; then true
  else stop "rollback: origin/main moved and no PR 1 merge sha is recorded (J/pr1-merge); before or after P5 is unknown"; fi; }
unfreeze_gate() {  # r0|p10|r6
  local mb want rec o t
  [ ! -e "$J/intent" ] || stop "gate: an unfinished intent ($(head -n 1 "$J/intent" | cut -d' ' -f1)); run recover or rollback first"
  pg fetch -q origin || exit 2
  mb=$(pg merge-base HEAD refs/remotes/origin/main) || stop "gate: no merge base"
  [ -z "$(pg diff --no-renames --name-only --diff-filter=D "$mb" refs/remotes/origin/main -- $(cat "$J/delete-list"))" ] ||
    stop "gate: the next pull deletes internal paths"
  case $1 in
    r0) case $(cp_name) in
          a0r) want=$J/p1-pre/pre.manifest; rec=$J/done-r0a ;;
          a1) stop "gate: P1a ran; run rollback (R0a) first" ;;
          c0) [ ! -e "$J/done-p1a" ] || stop "gate: P1a ran; run rollback (R0a) first"; want=$J/p2.manifest; rec=$J/p2.manifest ;;
          a0|'') want=$J/p1-pre/pre.manifest; rec=$J/p1-pre/pre.manifest ;;
          *) stop "gate: R0 from checkpoint $(cp_name)" ;; esac
        [ "$(manifest "$ROOT")" = "$(cat "$want")" ] || stop "gate: the internal set is not the expected set" ;;
    p10) rec=$J/p9; p10_want > "$J/p10.want" || stop "gate: cannot build the P10 expected set"
         [ "$(manifest "$ROOT" | cut -f2)" = "$(sort -u "$J/shared.manifest" "$J/local.manifest")" ] || stop "gate: the internal set is not shared+local"
         [ "$(manifest "$ROOT")" = "$(cat "$J/p10.want")" ] || stop "gate: an internal file's content is not its expected end state"
         [ ! -e "$rec" ] || [ "$(cat "$rec")" = "$(cat "$J/p10.want")" ] || stop "gate: P9's record is not the expected end state" ;;
    r6) rec=$J/cp; [ "$(cp_name)" = r5 ] && [ "$(manifest "$ROOT")" = "$(cat "$J/p2.manifest")" ] || stop "gate: not the R5 state" ;;
    *) refuse "unfreeze-gate r0|p10|r6" ;; esac
  [ -e "$rec" ] || stop "gate: no record $rec"
  if [ "$(cp_name)" = a0r ]; then o=$(cat "$J/p1-pre/head")
    [ "$(pg rev-parse HEAD)" = "$o" ] && [ "$(pg rev-parse -q --verify "refs/tags/gate0/$(cat "$J/host")-$o")" = "$o" ] &&
      [ "$(pg status --porcelain -uall)" = "$(cat "$J/p1-pre/status.all")" ] && [ "$(wman "$o")" = "$(cat "$J/p1-pre/wtree.manifest")" ] &&
      [ "$(pg rev-parse refs/remotes/origin/main)" = "$(cat "$J/base")" ] || stop "gate: not the P1-pre state"
  fi
  echo "cutover: unfreeze gate $1: pass"
}
p10_want() (  # P10's expected end state: local paths at their P2 digests, shared paths at the private HEAD's entries
  set -o pipefail   # a missing digest inside the group fails the function, not only the group
  local p d f; for f in local.manifest shared.manifest p2.manifest; do   # a manifest that cannot be read fails, not reads as empty
    [ -f "$J/$f" ] && [ -r "$J/$f" ] || { echo "cutover: P10 needs $J/$f" >&2; return 1; }; done
  { while IFS= read -r p; do d=$(awk -F'\t' -v p="$p" '$2==p{print $1}' "$J/p2.manifest") && [ -n "$d" ] || return 1
      printf '%s\t%s\n' "$d" "$p"; done < "$J/local.manifest" || return 1
    while IFS= read -r p; do d=$(TGD=$ROOT/.git-internal tdg HEAD "$p") && [ "$d" != - ] || return 1
      printf '%s\t%s\n' "$d" "$p"; done < "$J/shared.manifest" || return 1; } | sort -t "$(printf '\t')" -k2,2; )
preserved() {  # [r6] : restart step 1
  local o h f s la; o=$(cat "$J/p1-pre/head"); h=$(cat "$J/host"); la=$(cat "$J/p1-pre/lane-archive")
  [ "$(pg rev-parse -q --verify "refs/tags/gate0/$h-$o")" = "$o" ] || stop "restart: the tag"
  [ -f "$J/capture/sha256" ] && [ "$(cut -f1 "$J/capture/sha256" | sort | paste -sd' ' -)" = "main.bundle wtree.tar" ] ||
    stop "restart: the capture's sha256 manifest is missing or does not list exactly main.bundle and wtree.tar"
  while IFS=$'\t' read -r f s; do [ -n "$s" ] && [ -f "$J/capture/$f" ] && [ "$(sha < "$J/capture/$f")" = "$s" ] || stop "restart: $f changed or is missing"; done < "$J/capture/sha256"
  [ "$(lane_tip "archive/gate0/$h/$o")" = "$o" ] || stop "restart: the archive branch"
  [ -z "$la" ] || [ "$(lane_tip "archive/gate0/$h/lane-$la")" = "$la" ] || stop "restart: the lane archive branch"
  [ "${1:-}" != r6 ] || { [ "$(cp_line)" = "r5 $(pg rev-parse HEAD)" ] && [ "$(pg status --porcelain)" = "$(cat "$J/p2.status")" ]; } ||
    stop "restart: not R5's restoration"
  echo "cutover: preservation intact"
}

case $CMD in
  p0) p0 ;;
  p1-pre) p1pre ;;
  p1a) p1a ;;
  p1a-check) [ -n "$CHECK" ] || refuse "p1a-check runs only as --check ROOT J p1a"
    [ ! -e "$J/cp" ] && [ ! -e "$J/intent" ] || refuse "the P1a check runs only before P1a (the journal has a checkpoint or an intent)"
    export GIT_OPTIONAL_LOCKS=0   # git status refreshes no index stat data in the checkout
    p1pre; p1a ;;
  unfreeze-gate) unfreeze_gate "${4:-}" ;;
  preserved) preserved "${4:-}" ;;
  p2) recover; [ ! -e "$J/cp" ] || at a1 || refuse "P2 is already recorded"
      manifest "$ROOT" > "$J/p2.manifest"; pg status --porcelain > "$J/p2.status"
      pg status --porcelain=v1 --untracked-files=all > "$J/p2.status.all"   # the repair script's mode, for the R6 restart prediction
      [ -e "$J/removed.manifest" ] || pg ls-tree -r --name-only HEAD -- $(cat "$J/delete-list") | sort > "$J/removed.manifest"
      put "$J/cp" "c0 $(pg rev-parse HEAD)" ;;
  recover) recover ;;
  forward) recover
    while :; do [ "$(cp_name)" != "$UNTIL" ] || exit 0; case $(cp_name) in
      c0) p6 ;; c1) p7 ;; c2) p8 ;; c3) exit 0 ;;
      a0) p1a_realign ;; a1) refuse "P1a is done; run p2" ;; a0r) refuse "R0a ran; the machine is back at the old tip" ;;
      *) refuse "checkpoint $(cp_name) is a rollback state" ;; esac; done ;;
  rollback)
    cleanup
    if [ -e "$J/intent" ]; then case $(head -n 1 "$J/intent" | cut -d' ' -f1) in p8) r1 ;; *) run_intent ;; esac; fi
    if [ -e "$J/done-p1a" ]; then case $(cp_name) in
      a1) before_p5 || stop "rollback: P1a ran and P2 did not, but PR 1 is merged (after P5); the owner decides"
          r0a; exit 0 ;;
      a0r) exit 0 ;;
      c0) if before_p5; then r0a; exit 0; fi ;; esac
    elif [ "$(cp_name)" = c0 ] && [ -e "$J/base" ] && before_p5; then
      echo "cutover: rollback at c0 before P5, P1a did not run: R0, nothing to undo; run unfreeze-gate r0"; exit 0; fi
    [ "$(cp_name)" != a0 ] || exit 0
    while :; do case $(cp_name) in
      c3) r1 ;; c0|c1|c2|r1-done) r3 ;; r3-done) r4 ;; r4-done) r5 ;; r5) exit 0 ;;
      *) stop "unknown checkpoint" ;; esac; done ;;
  *) refuse "unknown command $CMD" ;;
esac
