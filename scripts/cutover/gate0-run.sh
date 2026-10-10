#!/bin/bash
# gate0-run.sh: the production wrapper around the Gate 0 steps of the cutover plan (bead mk-z9st.22).
# It drives cutover-steps.sh (p0, p1-pre, p1a, preserved, rollback, unfreeze-gate) and restart-predict.sh
# for ONE machine and adds what those scripts leave to the operator: the operator-presence check, the
# freeze (quiesce check, bd-writer check, timers stopped, marker moved aside), the refusal of a writing
# reference-transaction hook, the verified private archive destination, the preservation copy, the bd
# export reconciliation, marker handling and the restart orchestration. It is code in the PR. Merging
# the PR does not run it; the operator runs it, once the cutover is approved, in the order below.
#
#   gate0-run.sh --check                  syntax and tools only; reads and writes nothing
#   gate0-run.sh --check PHASE [EXIT]     the phase's read-only checks and nothing else: no freeze, no unit stop,
#                                         no marker move, no journal record, no ref, no push; writes only the
#                                         diagnostic log and the report (capture's P1a check writes a scratch dir
#                                         under the log directory)
#   gate0-run.sh preflight                P0: readiness, hook refusal, verified archive destination, record J/p0
#   gate0-run.sh freeze                   P1: presence check, quiesce check, timers stopped, marker aside
#   gate0-run.sh capture                  P1-pre, P1a (capture, archive push, realign), the re-check, the
#                                         preservation copy, restart step 1
#   gate0-run.sh run                      preflight, freeze, capture in order; stops at the first failure
#   gate0-run.sh rollback                 R0a (before P5 only): back to the old tip, checkpoint a0r
#   gate0-run.sh restart r0|p10|r6        unfreeze gate, restart steps 1-5 (r0 after R0a gives row 4)
#   Environment (everything is explicit; nothing is read from a private path):
#     GATE0_ROOT          the Sylveste checkout (required; the journal must be outside it)
#     GATE0_STATE_DIR     parent of the journal J (default $GATE0_STATE_DIR/journal), the preservation copy
#                         (GATE0_PRESERVE_DIR, default $GATE0_STATE_DIR/preserve) and the logs; required
#     GATE0_MACHINE       server (default) or clavain
#     GATE0_REL           the checkout's path relative to the repair script's root (default: its basename)
#     GATE0_OPERATOR, GATE0_OPERATOR_HOME   the account that owns the checkout; run as root, the wrapper
#                         re-executes itself as GATE0_OPERATOR, so every git command runs as the owner
#     GATE0_REPORT_TELL, GATE0_REPORT_TITLE report sender and title; the sender is empty by default, so the
#                         delivery fails into the print-the-report fallback
#     GATE0_BD            the bd binary (default bd); GATE0_DOTFILES; AUTOSYNC_LANE_LIB (the lane library)
#     GATE0_UNITS_TIMERS, GATE0_UNITS_SERVICES   the autosync units (defaults: git-autosync-repair.timer
#                         git-autosync-promote.timer; git-autosync-repair.service git-autosync-promote.service)
#     GATE0_TIMER_CTL     a command taking stop|start|active UNIT (required off Linux, where there is no
#                         systemd; on Linux the default is systemctl --user, as GATE0_OPERATOR). `active` exits 0
#                         when the unit is active, 3 when it is confirmed inactive; any other status is an error
#                         and is a STOP, never taken as inactive.
#     GATE0_CONFIRM_FILE  tests only: read the presence phrase from this file instead of the terminal
#     GATE0_QUIESCE_WAIT  seconds to wait for agent processes to leave the checkout (default 0)
#     GATE0_UNINSPECTABLE_UIDS  space-separated uids of accounts whose processes this account cannot inspect and
#                         that run no agent or bd work in the checkout (default none). On Linux a live process whose
#                         working directory cannot be read is a STOP unless its owner's uid is listed here. The lsof
#                         branch (no /proc) sees only the processes lsof may list and cannot make this distinction.
#     GATE0_STATUS_CMD    optional command whose output is recorded at freeze (an autosync status report)
#     GATE0_READONLY_HOOKS  a file of sha256 values of reference-transaction hooks the owner reviewed as
#                         read-only; any other installed hook is refused
# Inputs in J (written by the operator from the approved inventory): base, host, lane-remote, dispositions,
# pr1-head, delete-list. cutover-steps.sh documents their formats.
# Exit: 0 ok; 1 usage, or refused before any write; 3 STOP (a check failed; the state is described).
# Every phase is idempotent: it re-verifies what an earlier run left and continues from the journal.
# Reporting: the EXIT trap writes a report (this script's sha256, the phase, the exit status) to the run's log
# directory $GATE0_STATE_DIR/logs/<phase>-<utc timestamp>-<pid> and sends it with the report sender.
# Portable to /bin/bash 3.2.
set -u
PATH=${GATE0_PATH:-/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin}
export LC_ALL=C
export GIT_OPTIONAL_LOCKS=0   # no git command of this script, nor the steps it runs, rewrites the index to refresh stat data
HERE=$(cd "$(dirname "$0")" && pwd -P); SELF=$HERE/$(basename "$0")
# the hash tool is chosen by a known answer (the digest of no input), so a present but broken sha256sum falls back
if [ "$(printf '' | sha256sum 2>/dev/null | cut -d' ' -f1)" = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 ]
then sha() { local h; h=$(set -o pipefail; sha256sum | cut -d' ' -f1) && [[ $h =~ ^[0-9a-f]{64}$ ]] && printf '%s\n' "$h"; }
else sha() { local h; h=$(set -o pipefail; shasum -a 256 2>/dev/null | cut -d' ' -f1) && [[ $h =~ ^[0-9a-f]{64}$ ]] && printf '%s\n' "$h"; }; fi   # a hash that fails prints nothing and fails: two failed hashes are never "equal"
SELF_SHA=$(sha < "$SELF")
[[ $SELF_SHA =~ ^[0-9a-f]{64}$ ]] || { echo "gate0-run: no sha256 of this script (neither sha256sum nor shasum -a 256 works); refusing" >&2; exit 1; }
CS=${GATE0_CS:-$HERE/cutover-steps.sh}; PRED=${GATE0_PRED:-$HERE/restart-predict.sh}
CMDLINE="$*"; CHECKMODE=0; PHASE=none
if [ "${1:-}" = --check ]; then
  CHECKMODE=1; shift
  if [ $# = 0 ]; then
    bash -n "$SELF" && [ -f "$CS" ] && [ -f "$PRED" ] && bash -n "$CS" && bash -n "$PRED" && command -v git >/dev/null &&
      command -v tar >/dev/null && command -v awk >/dev/null && command -v ps >/dev/null &&
      echo "gate0-run.sh: check ok (sha256 $SELF_SHA; cutover-steps.sh $(sha < "$CS"); restart-predict.sh $(sha < "$PRED"))"
    exit $?
  fi
fi
PHASE=${1:-}; XARG=${2:-}
case $PHASE in
  preflight|freeze|capture|run|rollback) [ $# = 1 ] || PHASE= ;;
  restart) case $XARG in r0|p10|r6) [ $# = 2 ] || PHASE= ;; *) PHASE= ;; esac ;;
  *) PHASE= ;;
esac
[ -n "$PHASE" ] || { echo "usage: gate0-run.sh [--check [PHASE [EXIT]]] preflight|freeze|capture|run|rollback|restart r0|p10|r6" >&2; exit 1; }

ROOT_IN=${GATE0_ROOT:-}; SD=${GATE0_STATE_DIR:-}
[ -n "$ROOT_IN" ] && [ -n "$SD" ] || { echo "gate0-run: set GATE0_ROOT and GATE0_STATE_DIR" >&2; exit 1; }
ROOT=$(cd "$ROOT_IN" 2>/dev/null && pwd -P) && [ -e "$ROOT/.git" ] || { echo "gate0-run: GATE0_ROOT is not a git checkout" >&2; exit 1; }
if [ "$(id -u)" = 0 ] && [ -z "${GATE0_NO_REEXEC:-}" ]; then   # git runs as the checkout's owner, never as root
  OP=${GATE0_OPERATOR:-}; id "$OP" >/dev/null 2>&1 && [ "$OP" != root ] || { echo "gate0-run: run as root, set GATE0_OPERATOR to the checkout's owner" >&2; exit 1; }
  exec runuser -u "$OP" -- env GATE0_NO_REEXEC=1 "$SELF" $( [ $CHECKMODE = 1 ] && echo --check ) $PHASE $XARG
fi
physpath() {  # PATH : its physical path (symlinks resolved), also when it does not exist yet; nothing is created
  local p=$1 t= d
  case $p in /*) ;; *) p=$PWD/$p ;; esac
  while [ "${p%/}" != "$p" ] && [ "$p" != / ]; do p=${p%/}; done
  while [ ! -e "$p" ] && [ ! -L "$p" ]; do t=/${p##*/}$t; p=${p%/*}; [ -n "$p" ] || p=/; done
  case $t/ in */../*|*/./*) return 1 ;; esac
  d=$(cd "$p" 2>/dev/null && pwd -P) || return 1
  [ "$d" != / ] || d=; printf '%s%s\n' "$d" "$t"; }
GD=$(git -C "$ROOT" rev-parse --absolute-git-dir 2>/dev/null) && GD=$(cd "$GD" 2>/dev/null && pwd -P) || { echo "gate0-run: GATE0_ROOT has no usable git directory" >&2; exit 1; }
SD=$(physpath "$SD") || { echo "gate0-run: cannot use GATE0_STATE_DIR" >&2; exit 1; }
J=$(physpath "${GATE0_JOURNAL:-$SD/journal}") || { echo "gate0-run: cannot use GATE0_JOURNAL" >&2; exit 1; }
PRES=$(physpath "${GATE0_PRESERVE_DIR:-$SD/preserve}") || { echo "gate0-run: cannot use GATE0_PRESERVE_DIR" >&2; exit 1; }
# physical paths, checked before anything is created: nothing this script writes may land in the checkout or its git directory
for d in "state directory:$SD" "journal:$J" "preservation copy:$PRES"; do
  case "${d#*:}/" in "$ROOT"/*|"$GD"/*) echo "gate0-run: the ${d%%:*} must be outside the checkout and its git directory" >&2; exit 1 ;; esac; done
within() {  # PHYSICAL-PATH DIR... : the path is inside one of the directories
  local p=$1 d; shift; for d in "$@"; do case "$p/" in "$d"/*) return 0 ;; esac; done; return 1; }
# the children are checked as well: a symlinked logs/ or gate0-run/ must not turn a write into one inside the checkout or the journal
within "$PRES" "$J" && { echo "gate0-run: the preservation copy must be outside the journal" >&2; exit 1; }
G=$J/gate0-run
GP=$(physpath "$G") && [ "$GP" = "$G" ] || { echo "gate0-run: $G is not a plain child of the journal (a symlink)" >&2; exit 1; }
LOGD=$SD/logs/$PHASE-$(date -u +%Y%m%dT%H%M%SZ)-$$
LP=$(physpath "$LOGD") && ! within "$LP" "$ROOT" "$GD" "$J" "$PRES" || { echo "gate0-run: the log directory must be outside the checkout, its git directory, the journal and the preservation copy" >&2; exit 1; }
[ $CHECKMODE = 1 ] || mkdir -p "$J" || { echo "gate0-run: cannot create the journal" >&2; exit 1; }
mkdir -p "$LOGD" || { echo "gate0-run: cannot create $LOGD" >&2; exit 1; }
LOG=$LOGD/run.log; RLOG=$LOGD/run.report
MACHINE=${GATE0_MACHINE:-server}; case $MACHINE in server|clavain) ;; *) echo "gate0-run: GATE0_MACHINE is server or clavain" >&2; exit 1 ;; esac
OPH=${GATE0_OPERATOR_HOME:-${HOME:-}}; BDBIN=${GATE0_BD:-bd}
DOT=${GATE0_DOTFILES:-$OPH/projects/dotfiles}
SWEEP=${GATE0_SWEEP:-$OPH/.local/bin/git-autosync-sweep.sh}
DRIFT=${GATE0_DRIFT_REPORT:-$OPH/.local/state/autosync-drift/report.txt}
PAUSE=${GATE0_PAUSE_FILE:-$OPH/.claude-automations-paused}
TIMERS=${GATE0_UNITS_TIMERS:-git-autosync-repair.timer git-autosync-promote.timer}
SERVICES=${GATE0_UNITS_SERVICES:-git-autosync-repair.service git-autosync-promote.service}
REPAIR_SVC=git-autosync-repair.service
case " $SERVICES " in *" $REPAIR_SVC "*) ;; *) SERVICES="$SERVICES $REPAIR_SVC" ;; esac   # the service a restart starts is always one the freeze and the cleanup stop and read back
REL=${GATE0_REL:-$(basename "$ROOT")}
export AUTOSYNC_LANE_LIB=${AUTOSYNC_LANE_LIB:-$OPH/.local/lib/autosync-lane.sh}

report() {  # EXIT trap: the report, then the sender; a failed delivery prints the report
  local rc=$? tell=${GATE0_REPORT_TELL:-} t=${GATE0_REPORT_TITLE:-gate0-run} r
  r=$([ $rc = 0 ] && echo ok || echo failed)
  echo "gate0-run.sh (sha256 $SELF_SHA) $CMDLINE: phase $PHASE, exit $rc ($r); log $LOG" > "$RLOG" 2>/dev/null
  "$tell" --title "$t" --message-file "$RLOG" --script "$SELF" --result "$r" --step "$PHASE" --log "$LOG" >/dev/null 2>&1 ||
    { echo "gate0-run: report not delivered; it is $RLOG:" >&2; cat "$RLOG" >&2; }
  exit $rc; }
trap report EXIT
say() { printf '%s\n' "$*"; printf '%s\n' "$*" >> "$LOG"; }
stop() { say "gate0-run: STOP: $*" >&2; exit 3; }
refuse() { say "gate0-run: refused, nothing written: $*" >&2; exit 1; }
runlog() {  # command... : run it, show and log its output, keep its exit status
  local rc; "$@" > "$LOGD/cmd.out" 2>&1; rc=$?; cat "$LOGD/cmd.out"; cat "$LOGD/cmd.out" >> "$LOG"; rm -f "$LOGD/cmd.out"; return $rc; }
pg() { git -C "$ROOT" "$@"; }
pgs() { local o; o=$(pg "$@") || return 1; printf '%s\n' "$o"; }   # pg, but output is shown only when the command succeeded: "output, then failure" is a failure, never a value to compare
rec_timers() { sed -n 's/^timer //p' "${1:-$G/freeze}" 2>/dev/null; }   # the timers of a record; the status is sed's, so an unreadable record is a failure, never an empty list
rec_marker() { sed -n 's/^marker //p' "$G/freeze" 2>/dev/null; }
inroot() { ( cd "$ROOT" && "$@" ); }   # bd and the steps find the tracker from the working directory: always the checkout's, never the caller's
cs() { inroot env CUTOVER_REPORT=0 CUTOVER_PATH="$PATH" CUTOVER_BD="$BDBIN" CUTOVER_CHECK_DIR="$LOGD" "$CS" "$ROOT" "$J" "$@"; }
flush_path() {  # PATH : flush a file or directory to disk; fails when neither sync nor an fsync can do it
  sync "$1" 2>/dev/null && return 0
  python3 -I -c 'import os,sys
fd=os.open(sys.argv[1],os.O_RDONLY)
try: os.fsync(fd)
finally: os.close(fd)' "$1" 2>/dev/null; }
put() {  # file text [handler] : atomic, durable replace (skipped in --check); a failure calls the handler (default stop)
  [ $CHECKMODE = 0 ] || return 0
  local t="$1.tmp.$$"; printf '%s\n' "$2" > "$t" && { sync "$t" 2>/dev/null || sync; } && mv -f -- "$t" "$1" && { sync "$(dirname "$1")" 2>/dev/null || sync; } ||
    { rm -f -- "$t"; ${3:-stop} "cannot record $1"; }; }
need_inputs() {
  local f; for f in base host lane-remote dispositions pr1-head delete-list; do [ -s "$J/$f" ] || refuse "J/$f is missing or empty (the operator writes the approved inputs there)"; done
  BASE=$(cat "$J/base") && HOST=$(cat "$J/host") && LANE=$(cat "$J/lane-remote") && [ -n "$LANE" ] || refuse "an input in J cannot be read"
  [[ $BASE =~ ^[0-9a-f]{40}$ ]] || refuse "J/base is not a commit sha"
  [[ $HOST =~ ^[A-Za-z0-9._-]+$ ]] || refuse "J/host is not a plain host name"; }

# ---- timers and units
units() {  # stop|start UNIT... : the platform's controller
  local act=$1 u rc=0; shift
  if [ -n "${GATE0_TIMER_CTL:-}" ]; then "$GATE0_TIMER_CTL" "$act" "$@"; return $?; fi
  [ "$(uname -s)" = Linux ] || stop "no timer control on this platform (set GATE0_TIMER_CTL)"
  export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
  for u in "$@"; do case $act in
    stop) systemctl --user stop "$u" || rc=1 ;; start) systemctl --user start "$u" || rc=1 ;; esac; done; return $rc; }
unit_state() {  # UNIT : active | inactive | unknown; a controller error is unknown, never inactive
  local u=$1 out rc
  if [ -n "${GATE0_TIMER_CTL:-}" ]; then "$GATE0_TIMER_CTL" active "$u" >/dev/null 2>&1; rc=$?
    case $rc in 0) echo active ;; 3) echo inactive ;; *) echo unknown ;; esac; return 0; fi
  [ "$(uname -s)" = Linux ] || { echo unknown; return 0; }
  export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
  out=$(systemctl --user is-active "$u" 2>/dev/null); rc=$?   # the word and the status must agree: active is 0, inactive and failed are nonzero (3)
  case $out/$rc in active/0) echo active ;; inactive/[1-9]*|failed/[1-9]*) echo inactive ;; *) echo unknown ;; esac; }   # activating, reloading, deactivating and a word that disagrees with its status are not confirmed either way
is_active() {  # UNIT : 0 active, 1 confirmed inactive; any other answer is a STOP
  case $(unit_state "$1") in active) return 0 ;; inactive) return 1 ;; *) stop "cannot establish whether $1 is active: the unit controller gave an error" ;; esac; }

# ---- the freeze
under_self() {  # PID : true when this script is among PID's ancestors (its own subshells and helpers)
  local q=$1 n=0
  while [ -n "$q" ] && [ "$q" -gt 1 ] 2>/dev/null && [ $n -lt 64 ]; do [ "$q" != "$$" ] || return 0; q=$(ps -o ppid= -p "$q" 2>/dev/null | tr -d ' '); n=$((n+1)); done; return 1; }
PROCFS=${GATE0_PROCFS:-/proc}
skippable_proc() {  # DIR PID : a /proc entry whose working directory cannot be read, and that cannot hold an agent: gone, a zombie, or an account declared uninspectable
  local d=$1 p=$2 u m st
  [ -d "$d" ] || return 0   # it exited between the listing and the read
  st=$(sed -n 's/^State:[[:space:]]*\(.\).*/\1/p' "$d/status" 2>/dev/null) || st=   # a failed read is no state: the process still counts as an agent
  case $st in Z|X) return 0 ;; esac
  u=$(stat -c %u "$d" 2>/dev/null) || { [ -d "$d" ] || return 0; u=; }
  if [ -n "$u" ]; then case " ${GATE0_UNINSPECTABLE_UIDS:-} " in *" $u "*) return 0 ;; esac; fi
  m="gate0-run: pid $p (uid ${u:-unknown}) is live and its working directory cannot be read, so it cannot be ruled out as an agent; end it, or list its uid in GATE0_UNINSPECTABLE_UIDS only if no process of that account that you cannot inspect can be an agent or bd work in the checkout"
  printf '%s\n' "$m" >&2; printf '%s\n' "$m" >> "$LOG"; return 1; }
agents_in_root() {  # "pid comm" for each process whose cwd is under the checkout, apart from this script, its ancestors and its descendants
  # status 2 when the processes cannot be listed: a listing that does not show this script itself proves nothing
  local skip=" $$ " p d c out; p=$$
  while [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null; do p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' '); skip="$skip$p "; done
  if [ -d "$PROCFS/self" ]; then
    readlink "$PROCFS/$$/cwd" >/dev/null 2>&1 || return 2
    for d in "$PROCFS"/[0-9]*; do p=${d#"$PROCFS"/}; case $skip in *" $p "*) continue ;; esac
      c=$(readlink "$d/cwd" 2>/dev/null) || { skippable_proc "$d" "$p" && continue; return 2; }
      case $c in "$ROOT"|"$ROOT"/*) under_self "$p" || echo "$p $(tr -d '\0' < "$d/comm" 2>/dev/null)" ;; esac; done
  else
    command -v lsof >/dev/null 2>&1 || return 2
    out=$(lsof -d cwd -Fpcn 2>/dev/null) || return 2   # a failed listing can still show this script and omit others
    case "
$out
" in *"
p$$
"*) ;; *) return 2 ;; esac
    out=$(set -o pipefail; printf '%s\n' "$out" | awk -v r="$ROOT" '/^p/{p=substr($0,2)} /^c/{c=substr($0,2)} /^n/{n=substr($0,2); if (n==r || index(n, r "/")==1) print p, c}') || return 2   # a filter that fails shows no agents; that is not "none"
    while read -r p c; do [ -n "$p" ] || continue; case $skip in *" $p "*) ;; *) under_self "$p" || echo "$p $c" ;; esac; done <<< "$out"
  fi; return 0; }
bd_writers() {  # "pid bd" for each process named bd; status 2 when the process table cannot be read (it must list this script itself)
  local out; out=$(ps -A -o pid= -o comm= 2>/dev/null) || return 2
  printf '%s\n' "$out" | awk -v me="$$" '$1 == me { ok = 1 } { n = $2; sub(/.*\//, "", n); if (n == "bd") print $1, n } END { exit ok ? 0 : 2 }'; }
presence() {
  local want="mk is present for gate 0 on $HOST base ${BASE:0:12}" got=
  if [ -n "${GATE0_CONFIRM_FILE:-}" ]; then got=$(head -n 1 "$GATE0_CONFIRM_FILE" 2>/dev/null)
  elif [ -t 0 ]; then printf 'Gate 0 moves main. Type exactly: %s\n> ' "$want" >&2; IFS= read -r got
  else refuse "no terminal: the presence check needs the operator to type the confirmation"; fi
  [ "$got" = "$want" ] || refuse "presence not confirmed"; }
marker_aside() { [ -e "$G/marker" ] && [ ! -e "$ROOT/.git-autosync" ]; }
keep_unexpected_marker() {  # the bytes now in the checkout are not the recorded marker (or the record says there is none): keep them beside the record, verified, before they are removed
  local m h; h=$(sha < "$ROOT/.git-autosync") || stop "cannot hash the unexpected marker to keep it"; m=$G/marker.unexpected.$h
  if [ ! -e "$m" ]; then
    cp -p "$ROOT/.git-autosync" "$m.tmp.$$" && { sync "$m.tmp.$$" 2>/dev/null || sync; } && mv -f -- "$m.tmp.$$" "$m" || stop "cannot keep the unexpected marker bytes before removing them"; fi
  cmp -s "$m" "$ROOT/.git-autosync" || stop "the kept copy of the unexpected marker does not match it"
  say "gate0-run: the marker in the checkout is not the recorded one; its bytes are kept in $m"; }
move_marker_aside() {  # [force] : the marker is untracked and ignored; keep its bytes in G, verify, then remove it from the checkout
  [ -e "$ROOT/.git-autosync" ] || return 0
  if [ "${1:-}" = force ] && [ ! -e "$G/marker" ] && mk=$(rec_marker) && [ "$mk" = none ]; then   # cleanup: the record says there is no marker, so none may stay
    keep_unexpected_marker; rm -f -- "$ROOT/.git-autosync" && [ ! -e "$ROOT/.git-autosync" ] || stop "cannot move the marker aside"; return 0; fi
  if [ -e "$G/marker" ]; then   # the copy is already there (a restart put the marker back from it): no write to the journal is needed
    if ! cmp -s "$G/marker" "$ROOT/.git-autosync"; then
      [ "${1:-}" = force ] || stop "a different marker is already set aside"
      keep_unexpected_marker; fi   # cleanup after a failure: keep the bytes beside the record, then remove the live file
    rm -f -- "$ROOT/.git-autosync" && [ ! -e "$ROOT/.git-autosync" ] || stop "cannot move the marker aside"; return 0; fi
  cp -p "$ROOT/.git-autosync" "$G/marker.tmp.$$" && { sync "$G/marker.tmp.$$" 2>/dev/null || sync; } &&
    mv -f -- "$G/marker.tmp.$$" "$G/marker" && cmp -s "$G/marker" "$ROOT/.git-autosync" &&
    rm -f -- "$ROOT/.git-autosync" || stop "cannot move the marker aside"; }

# ---- preflight (P0)
ready_checks() {  # the P0 readiness list, read-only
  local gd p b h u st ut rm_ um
  hook_check   # first: the fetch below can run an installed reference-transaction hook
  [ "$(pgs symbolic-ref -q HEAD)" = refs/heads/main ] || stop "HEAD is not main"
  gd=$(pg rev-parse --absolute-git-dir) && [ -n "$gd" ] || stop "cannot read the git directory: the operation-state files cannot be checked"
  for p in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG rebase-merge rebase-apply; do [ ! -e "$gd/$p" ] || stop "operation state $p"; done
  um=$(pg ls-files -u) || stop "cannot read the index: unmerged entries cannot be ruled out"
  [ -z "$um" ] || stop "unmerged entries"
  pg diff --cached --quiet || stop "staged entries"
  if [ $CHECKMODE = 0 ]; then pg fetch -q origin || stop "git fetch origin failed"
  else rm_=$(set -o pipefail; pg ls-remote origin refs/heads/main | cut -f1) && [[ $rm_ =~ ^[0-9a-f]{40}$ ]] || stop "check: cannot read origin/main from the remote"   # two failed reads are not equal
    [ "$rm_" = "$(pgs rev-parse refs/remotes/origin/main)" ] || stop "check: origin/main differs from the remote-tracking ref; fetch first"; fi
  [ "$(pgs rev-parse refs/remotes/origin/main)" = "$BASE" ] || stop "origin/main is not the approved base $BASE (no exception; rebuild PR 1 and re-run the rehearsal)"
  b=$(pg rev-list --left-right --count HEAD...refs/remotes/origin/main) || stop "cannot count the commits between HEAD and origin/main"
  b=$(printf '%s' "$b" | tr '\t' ' '); [[ $b =~ ^[0-9]+\ [0-9]+$ ]] || stop "the commit count between HEAD and origin/main is unreadable [$b]"
  if [ "$b" = "0 0" ]; then say "gate0-run: HEAD equals the base: P1a will not run on this machine"
  else say "gate0-run: local head is $b (ahead behind) against the base: P1a will realign it (the local-head exception, recorded)"; fi
  # a dirty path with no disposition is P1a's STOP (it is the authority); --check capture runs it without writing
  st=$(pg status --porcelain --untracked-files=no) || stop "cannot read the status: the local changes cannot be counted"
  ut=$(pg status --porcelain --untracked-files=all) || stop "cannot read the status: the untracked files cannot be counted"
  say "gate0-run: tracked paths with local changes (P1a decides each one's disposition): $(printf '%s\n' "$st" | grep -c .)"
  say "gate0-run: untracked files outside the internal set (recorded): $(printf '%s\n' "$ut" | grep -c '^??')"
  archive_check; }
hook_check() {  # an installed reference-transaction hook that writes anything is a STOP (design choice)
  local hp h s ok=0 rc
  hp=$(pg config core.hooksPath 2>/dev/null); rc=$?   # 1 is "not set"; any other failure is a read that did not happen
  case $rc in 0|1) ;; *) stop "cannot read core.hooksPath (git config exit $rc): whether a reference-transaction hook is installed cannot be told" ;; esac
  [ $rc = 0 ] || hp=
  if [ -z "$hp" ]; then hp=$(pg rev-parse --git-path hooks) && [ -n "$hp" ] || stop "cannot locate the hooks directory: whether a reference-transaction hook is installed cannot be told"; fi
  case $hp in /*) ;; *) hp=$ROOT/$hp ;; esac
  h=$hp/reference-transaction
  if [ -e "$h" ] || [ -L "$h" ]; then
    s=$(sha < "$h") || stop "cannot hash the installed reference-transaction hook $h"
    [ -f "${GATE0_READONLY_HOOKS:-/nonexistent}" ] && grep -qx "$s" "$GATE0_READONLY_HOOKS" && ok=1
    [ $ok = 1 ] || stop "an installed reference-transaction hook ($h, sha256 $s) is not on the reviewed read-only list; it could write during update-ref"
    say "gate0-run: reference-transaction hook $s is on the reviewed read-only list"
  else say "gate0-run: no reference-transaction hook installed"; fi; }
archive_check() {  # the private archive destination: validated by the lane library the autosync scripts use
  local o r
  # shellcheck disable=SC1090
  source "$AUTOSYNC_LANE_LIB" 2>/dev/null || stop "the lane library does not load ($AUTOSYNC_LANE_LIB)"
  asl_resolve "$ROOT" "$LANE" || stop "the archive destination is not acceptable: ${ASL_REASON:-unknown}"
  asl_tip "$ROOT" "autosync/$HOST" || stop "the archive destination is unreachable: ${ASL_REASON:-unknown}"
  say "gate0-run: archive destination ${ASL_SLUG:-?} accepted (private, validated); lane tip autosync/$HOST: ${ASL_TIP:-absent}"
  for o in "archive/gate0/$HOST"; do
    r=$(pg ls-remote "$LANE" "refs/heads/$o/*") || stop "cannot list the archive branches on the lane: an unreadable lane is not an empty one"
    [ -z "$r" ] || say "gate0-run: note: $o/* branches exist already (a re-run reuses an equal one)"; done; }
archive_ready() {  # the archive destination is acceptable now, and its push URL is the one the lane library just validated
  archive_check
  local pu; pu=$(pg remote get-url --push "$LANE" 2>/dev/null) || stop "cannot read the push URL of $LANE: it cannot be compared with the validated one"
  [ -n "${ASL_URL:-}" ] && [ "$pu" = "$ASL_URL" ] || stop "the push URL of $LANE is not the one just validated; nothing was pushed, realigned or restarted"; }
do_preflight() {
  local hd
  ready_checks
  if [ $CHECKMODE = 1 ]; then env CUTOVER_REPORT=0 "$CS" --check >/dev/null || stop "cutover-steps.sh --check failed"; say "gate0-run: preflight check: would run cutover-steps.sh p0"; return 0; fi
  mkdir -p "$G"
  if [ -d "$J/p0" ] && [ -e "$G/preflight" ]; then say "gate0-run: P0 already recorded ($(cat "$G/preflight"))"; return 0; fi
  runlog cs p0 || stop "P0 (cutover-steps.sh p0) failed"
  hd=$(pg rev-parse HEAD) && [[ $hd =~ ^[0-9a-f]{40}$ ]] || stop "cannot read HEAD: the preflight record would name no head"
  put "$G/preflight" "base $BASE head $hd host $HOST machine $MACHINE at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  say "gate0-run: P0 recorded in $J/p0"; }

# ---- freeze (P1)
in_list() { local x=$1 y; shift; for y in "$@"; do [ "$y" = "$x" ] && return 0; done; return 1; }
act_lines() { ( set -o pipefail; printf '%s\n' "$1" | sed 's/^ *//; s/ timer /\ntimer /g' | sed -n '/^timer /p' ); }   # " timer A timer B" : one "timer UNIT" line each; a failed stage is a failed list, never an empty one
do_freeze() {
  local a w u act="" f prior al
  [ -e "$G/preflight" ] || { [ $CHECKMODE = 1 ] || refuse "no preflight record; run preflight first"; }
  if [ -e "$G/freeze" ] && [ $CHECKMODE = 0 ] && ! restarted_any; then   # after a completed restart a new freeze is a new attempt: it falls through
    a=$(rec_timers) || stop "the freeze record cannot be read: whether its timers stay stopped cannot be told"
    for u in $a; do ! is_active "$u" || stop "the freeze was recorded but $u is active again"; done
    { marker_aside || { mk=$(rec_marker) && [ "$mk" = none ]; }; } || stop "the freeze was recorded but the marker is back in the checkout"
    rm -f -- "$G/freeze-intent"   # a crash after the freeze was recorded can leave the intent behind; the record holds the set
    say "gate0-run: freeze already holds"; return 0
  fi
  if [ $CHECKMODE = 1 ]; then say "gate0-run: freeze check: the presence phrase would be required"; else presence; fi
  a=$(agents_in_root) || stop "cannot list the processes (lsof or /proc): quiescence cannot be established"; w=${GATE0_QUIESCE_WAIT:-0}
  while [ -n "$a" ] && [ "$w" -gt 0 ] 2>/dev/null; do sleep 1; w=$((w-1)); a=$(agents_in_root) || stop "cannot list the processes: quiescence cannot be established"; done
  [ -z "$a" ] || stop "processes still have their working directory in the checkout (tell their threads to quiesce): $(echo "$a" | tr '\n' ';')"
  a=$(bd_writers) || stop "cannot read the process table (ps): no bd process can be ruled out"
  [ -z "$a" ] || stop "a bd process is running: $(echo "$a" | tr '\n' ';')"
  prior=; [ ! -f "$G/freeze-intent" ] || prior=$(rec_timers "$G/freeze-intent") || stop "the earlier freeze intent cannot be read: the timers it stopped would not be restarted"
  for u in $TIMERS; do
    if is_active "$u"; then act="$act timer $u"
    elif in_list "$u" $prior; then act="$act timer $u"; say "gate0-run: $u is inactive but an earlier freeze attempt that did not finish had stopped it: it stays in the restart set"; fi; done
  say "gate0-run: timers to restart after the freeze:${act:- none}"
  if [ $CHECKMODE = 1 ]; then say "gate0-run: freeze check: would stop the timers and services and move the marker aside (marker present: $([ -e "$ROOT/.git-autosync" ] && echo yes || echo no))"; return 0; fi
  al=$(act_lines "$act") || stop "cannot write the list of timers to restart: nothing was stopped"
  mkdir -p "$G"
  put "$G/freeze-intent" "$al"   # before the first stop: a stop that fails midway must not lose the timers already stopped
  for u in $TIMERS; do units stop "$u" || stop "cannot stop $u"; done
  for u in $SERVICES; do units stop "$u" || stop "cannot stop $u"; done
  for u in $TIMERS $SERVICES; do ! is_active "$u" || stop "$u is still active"; done
  move_marker_aside
  [ ! -e "$ROOT/.git-autosync" ] || stop "the marker is still in the checkout"
  if [ -n "${GATE0_STATUS_CMD:-}" ]; then "$GATE0_STATUS_CMD" > "$LOGD/autosync-status.txt" 2>&1; say "gate0-run: autosync status recorded (exit $?)"; fi
  if [ -e "$G/marker" ]; then w=$(sha < "$G/marker") || stop "cannot hash the marker set aside: the freeze record would name no marker"; w="marker $w"; else w="marker none"; fi
  f="${al:+$al$'\n'}$w"$'\n'"at $(date -u +%Y-%m-%dT%H:%M:%SZ)"; put "$G/freeze" "$f"
  rm -f -- "$G"/restarted-* "$G"/restarting-*   # a new freeze starts a new attempt: an earlier attempt's restart records no longer apply (cleared once the new freeze is recorded)
  rm -f -- "$G/freeze-intent"   # last: while a stale restart record exists the intent still names the restart set, so a crash between these two steps loses nothing
  say "gate0-run: freeze holds (timers and services stopped, marker aside)"; }
nobeads() { local rc; grep -v ' \.beads/issues\.jsonl$'; rc=$?; [ $rc -le 1 ]; }   # drop the tracker export line; grep 1 is "no line left", 2 or more is a failed filter
restarting_any() { local f; for f in "$G"/restarting-*; do [ -e "$f" ] && return 0; done; return 1; }
restarted_any() { local f; for f in "$G"/restarted-*; do [ -e "$f" ] && return 0; done; return 1; }
freeze_holds() { local u a
  [ -e "$G/freeze" ] || stop "no freeze record; run freeze first"
  hook_check   # a hook installed after preflight would run on the fetch, the realign or the repair run that follow
  for u in $TIMERS $SERVICES; do ! is_active "$u" || stop "$u is active: the freeze no longer holds"; done
  [ ! -e "$ROOT/.git-autosync" ] || stop "the marker is back in the checkout: the freeze no longer holds"
  a=$(agents_in_root) || stop "cannot list the processes (lsof or /proc): the freeze cannot be confirmed"
  [ -z "$a" ] || stop "an agent process has its working directory in the checkout: the freeze no longer holds: $(echo "$a" | tr '\n' ';')"
  a=$(bd_writers) || stop "cannot read the process table (ps): the freeze cannot be confirmed"
  [ -z "$a" ] || stop "a bd process is running: the freeze no longer holds: $(echo "$a" | tr '\n' ';')"; }

# ---- capture (P1-pre, P1a, the re-check, the preservation copy)
p1pre_head() {  # OLD : the old tip P1-pre recorded; a missing, empty or damaged record is a STOP, never an empty tip
  OLD=$(cat "$J/p1-pre/head" 2>/dev/null) && [[ $OLD =~ ^[0-9a-f]{40}$ ]] || stop "the P1-pre record $J/p1-pre/head is missing or is not a commit sha"; }
recheck_after_p1a() {  # P0's readiness repeated with no local-head exception
  local o h b t w
  b=$BASE; h=$HOST; p1pre_head; o=$OLD
  [ "$(pgs symbolic-ref -q HEAD)" = refs/heads/main ] || stop "re-check: HEAD is not main"
  [ "$(pgs rev-parse HEAD)" = "$b" ] && [ "$(pgs rev-parse refs/remotes/origin/main)" = "$b" ] || stop "re-check: HEAD and origin/main are not both the base"
  cnt=$(pgs rev-list --left-right --count HEAD...refs/remotes/origin/main) && [ "${cnt//$'\t'/ }" = "0 0" ] || stop "re-check: the count is not 0 0"
  [ "$(pgs rev-parse -q --verify "refs/tags/gate0/$h-$o")" = "$o" ] || stop "re-check: the tag gate0/$h-$o does not resolve to the old tip"
  t=$(pg rev-parse "$b^{tree}") && [[ $t =~ ^[0-9a-f]{40}$ ]] || stop "re-check: cannot read the base's tree"
  w=$(pg write-tree 2>/dev/null) && [ "$w" = "$t" ] || stop "re-check: the index is not the base's tree"
  say "gate0-run: re-check after P1a passes"; }
pres_check() {  # PD : this capture's preservation directory, a plain physical child of the preservation copy and outside the checkout and the journal
  local pp; p1pre_head; PD=$PRES/$HOST-$OLD
  pp=$(physpath "$PD") && [ "$pp" = "$PD" ] && ! within "$pp" "$ROOT" "$GD" "$J" || stop "the preservation directory $PD is not a plain directory outside the checkout and the journal (a symlink?)"; }
verify_set() {  # DIR [SUFFIX] : the files the capture's sha256 record names, in DIR (with SUFFIX), have the recorded digests; exactly two entries are checked, and a last line with no newline is still one
  local d=$1 x=${2:-} f s n=0
  while IFS=$(printf '\t') read -r f s || [ -n "$f" ]; do
    [ -n "$s" ] && [ "$(sha < "$d/$f$x")" = "$s" ] || return 1; n=$((n+1)); done < "$J/capture/sha256" || return 1
  [ $n = 2 ]; }
capture_names() {  # the names the capture's sha256 record lists, sorted, on one line; a record that cannot be read is a failure, never a value to compare
  local n; n=$(set -o pipefail; cut -f1 "$J/capture/sha256" | sort | paste -sd' ' -) || return 1; printf '%s\n' "$n"; }
capture_check() {  # the capture in the journal: the record names exactly the bundle and the W-snapshot, and both digests hold (the pinned step 1 drops a last line with no newline)
  local n; n=$(capture_names) && [ "$n" = "main.bundle wtree.tar" ] && verify_set "$J/capture"; }
preserve_copy() {  # the capture, outside the journal, verified file by file; the copies are staged and verified before they replace anything
  local d f g n; pres_check; d=$PD
  [ -f "$J/capture/sha256" ] || stop "no capture to copy"
  mkdir -p "$d" || stop "cannot create $d"
  n=$(capture_names) || stop "the capture's sha256 record cannot be read: the files it names cannot be checked"
  [ "$n" = "main.bundle wtree.tar" ] || stop "the capture's sha256 record does not name exactly main.bundle and wtree.tar"
  for f in main.bundle wtree.tar wtree.manifest sha256; do
    cp -p "$J/capture/$f" "$d/$f.tmp.$$" 2>/dev/null && flush_path "$d/$f.tmp.$$" || { for g in main.bundle wtree.tar wtree.manifest sha256; do rm -f -- "$d/$g.tmp.$$"; done; stop "cannot copy and flush $f"; }; done
  { verify_set "$d" ".tmp.$$" && cmp -s "$d/main.bundle.tmp.$$" "$J/capture/main.bundle" && cmp -s "$d/wtree.tar.tmp.$$" "$J/capture/wtree.tar" && cmp -s "$d/wtree.manifest.tmp.$$" "$J/capture/wtree.manifest" && cmp -s "$d/sha256.tmp.$$" "$J/capture/sha256"; } ||
    { for g in main.bundle wtree.tar wtree.manifest sha256; do rm -f -- "$d/$g.tmp.$$"; done; stop "the capture in the journal does not match its sha256 record or its copy: the preservation copy already there is untouched"; }
  for f in main.bundle wtree.tar wtree.manifest sha256; do mv -f -- "$d/$f.tmp.$$" "$d/$f" || stop "cannot move the staged $f into place"; done
  verify_set "$d" || stop "the preservation copy differs from the capture or its sha256 record"
  cmp -s "$d/wtree.manifest" "$J/capture/wtree.manifest" && cmp -s "$d/sha256" "$J/capture/sha256" || stop "the copied W-snapshot manifest or sha256 record differs"
  for f in main.bundle wtree.tar wtree.manifest sha256; do flush_path "$d/$f" || stop "cannot flush $d/$f"; done
  flush_path "$d" || stop "cannot flush the directory $d: the copy is not known to be on disk"
  say "gate0-run: preservation copy verified in $d (bundle and W-snapshot sha256 in $d/sha256)"; }
do_capture() {
  local o
  if [ $CHECKMODE = 1 ]; then
    [ -d "$J" ] || stop "check: no journal $J (run preflight first)"
    if [ -e "$J/cp" ]; then say "gate0-run: capture check: P1a is already recorded ($(cut -d' ' -f1 "$J/cp")); nothing to check"; return 0; fi
    runlog inroot env CUTOVER_REPORT=0 CUTOVER_PATH="$PATH" CUTOVER_BD="$BDBIN" CUTOVER_CHECK_DIR="$LOGD" "$CS" --check "$ROOT" "$J" p1a ||
      stop "the P1a check failed (it ran P1-pre and every capture check against a scratch copy)"
    say "gate0-run: capture check: P1a would run; it writes the capture, the archive branch, the tag and the realign"; return 0; fi
  [ -e "$G/preflight" ] || refuse "no preflight record"
  freeze_holds
  if [ -e "$G/captured" ]; then
    recheck_after_p1a; preserve_copy; runlog cs preserved || stop "restart step 1 (preservation) failed"
    say "gate0-run: capture already done ($(cat "$G/captured")); re-verified"; return 0; fi
  if [ ! -d "$J/p1-pre" ]; then runlog cs p1-pre || stop "P1-pre failed; re-run preflight and get a fresh approval"; fi
  p1pre_head; o=$OLD
  if [ "$o" != "$BASE" ]; then pres_check; fi   # before anything is realigned
  if [ "$o" = "$BASE" ]; then
    say "gate0-run: main equals the base: P1a does not run; P1-pre's record stands"; put "$G/p1a-skipped" "$o"; return 0; fi
  freeze_holds   # quiescence, once more, immediately before the checkout is realigned
  # the archive destination is validated again now, and its push URL must be the one just validated: P1a pushes the internal commits there
  archive_ready
  runlog cs p1a || stop "P1a failed (see the log; the journal holds the checkpoint and intent; re-run to continue)"
  recheck_after_p1a
  preserve_copy
  runlog cs preserved || stop "restart step 1 (preservation) failed"
  put "$G/captured" "old $o base $BASE at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  say "gate0-run: capture done: checkpoint $(cut -d' ' -f1 "$J/cp")"; }

# ---- rollback (R0a)
do_rollback() {
  if [ $CHECKMODE = 1 ]; then say "gate0-run: rollback check: would run cutover-steps.sh rollback (R0a, before P5 only)"; return 0; fi
  [ -e "$G/freeze" ] || refuse "no freeze record"
  freeze_holds   # rollback: the freeze must hold now, not only have been recorded
  runlog cs rollback || stop "R0a failed"
  say "gate0-run: R0a done: checkpoint $(cut -d' ' -f1 "$J/cp")"; }

# ---- restart (R0, P10, R6)
reconcile() {  # restart step 3: the first bd command is bd export; the base's and the old tip's records must be dominated
  local x o t l def
  [ -e "$J/done-p1a" ] || { say "gate0-run: P1a did not run on this machine: no reconciliation"; return 0; }
  # the same function the P1a check uses; extracted from the script that defines it, so there is one definition
  def=$(sed -n '/^jsonl_dominated() {/,/"\$2" "\$1"; }$/p' "$CS") && [[ $def == "jsonl_dominated() {"*'"$2" "$1"; }' ]] || stop "cannot extract jsonl_dominated from $CS: the extraction failed or did not return the whole function"
  eval "$def" || stop "cannot load jsonl_dominated from $CS"   # the extraction's status is held above: an inherited function never stands in for a definition that did not load
  p1pre_head; o=$OLD; x=$LOGD/export.jsonl
  inroot "$BDBIN" export -o "$x" > "$LOGD/bd-export.out" 2>&1 && [ -f "$x" ] || stop "bd export failed (see $LOGD/bd-export.out)"
  for t in "$o" "$BASE"; do
    l=$(pg ls-tree "$t" -- .beads/issues.jsonl 2>/dev/null) || stop "cannot read the tree of $t: whether it holds tracker records cannot be confirmed"
    if [ -n "$l" ]; then pg show "$t:.beads/issues.jsonl" > "$LOGD/jsonl.$t" 2>/dev/null || stop "cannot read .beads/issues.jsonl at $t (the tree lists it): its records cannot be compared"
    else : > "$LOGD/jsonl.$t"; fi   # confirmed absent from the tree: nothing to dominate
    jsonl_dominated "$LOGD/jsonl.$t" "$x" || stop "the tracker export does not dominate the records at $t"; done
  say "gate0-run: reconciliation holds: the export dominates the base and the old tip"; }
journal_cursor() { local o; o=$(journalctl --user -n 1 --show-cursor -o cat --no-pager 2>/dev/null) || return 1; printf '%s\n' "$o" | sed -n 's/^-- cursor: //p'; }   # the position of the newest entry, taken before the start
journal_since() { journalctl --user -u "$REPAIR_SVC" --after-cursor="$1" --no-pager -o cat 2>/dev/null; }   # only lines written after that position: an earlier invocation's lines are never this run's
predict() { RESTART_REPORT=0 "$PRED" "$@"; }   # the wrapper reports once; the predictor's own report sender stays off
rbail() {  # back to the frozen state: every recorded timer stopped, each timer and service read back, the marker aside; a stop that cannot be confirmed is said so
  local u bad= ts
  ts=$(rec_timers) || { ts=$TIMERS; say "gate0-run: the freeze record cannot be read: every configured timer is stopped instead" >&2; }   # cleanup never skips the timers because its record is unreadable
  for u in $ts $SERVICES; do units stop "$u" >/dev/null 2>&1; done   # a service a cut-off restart left running is stopped too
  for u in $ts $SERVICES; do [ "$(unit_state "$u")" = inactive ] || bad="$bad $u"; done
  [ -z "$bad" ] || say "gate0-run: UNCONFIRMED: these units are not confirmed stopped:$bad; a human must stop them before anything else runs" >&2
  move_marker_aside force; [ -n "$bad" ] || rm -f -- "$G"/restarting-*   # the attempt is closed only when every unit is confirmed stopped and the marker is aside
  stop "$*${bad:+; UNCONFIRMED stop of$bad}"; }
restore_marker() {  # the marker set aside goes back, and must be the one the freeze record names (server and Clavain alike)
  local m
  if [ -f "$G/marker" ] && [ -e "$ROOT/.git-autosync" ] && ! cmp -s "$G/marker" "$ROOT/.git-autosync"; then keep_unexpected_marker; fi   # other bytes in the checkout are kept before the restore replaces them
  [ -f "$G/marker" ] && cp -p "$G/marker" "$ROOT/.git-autosync.tmp.$$" && mv -f -- "$ROOT/.git-autosync.tmp.$$" "$ROOT/.git-autosync" ||
    { [ ! -e "$G/marker" ] && mk=$(rec_marker) && [ "$mk" = none ]; } || stop "cannot restore the marker"
  [ ! -e "$ROOT/.git-autosync" ] || { m=$(rec_marker) && [[ $m =~ ^[0-9a-f]{64}$ ]] && [ "$(sha < "$ROOT/.git-autosync")" = "$m" ]; } || { rm -f -- "$ROOT/.git-autosync"; stop "the restored marker differs from the one set aside"; }; }
lane_refs() {  # PATTERN : the lane's refs matching it, sorted, on one line; a failed read is a failure, never an empty list
  local o; o=$(pg ls-remote "$LANE" "$1") || return 1
  ( set -o pipefail; printf '%s\n' "$o" | sort | paste -sd' ' - ); }
tag_refs() {  # the gate0 tags, sorted, on one line; a failed read is a failure, never an empty list
  local o; o=$(pg for-each-ref --format='%(refname) %(objectname)' refs/tags/gate0) || return 1
  ( set -o pipefail; printf '%s\n' "$o" | sort | paste -sd' ' - ); }
restart_server() {  # exit-name  predict-exit
  local ex=$1 pe=$2 mk_ p2 cur pred rc tries n tip0 tip1 tags0 tags1 arch0 arch1 st h=$HOST
  restore_marker
  st=$(pg status --porcelain=v1 --untracked-files=all) || rbail "cannot read the status: whether the marker would be committed cannot be told; nothing started, marker moved aside again"
  mk_=$(set -o pipefail; printf '%s\n' "$st" | cut -c4- | { grep -x '\.git-autosync'; rc=$?; [ $rc -le 1 ]; }) || rbail "cannot filter the status for the marker rule: a failed filter shows no marker; nothing started, marker moved aside again"   # grep 1 is "no such line", 2 or more is a failed filter
  if [ -n "$mk_" ]; then
    rbail "the marker rule: .git-autosync is in the status; a run would commit it into the checkout and push it to the lane"; fi
  p2=; [ "$ex" != r6 ] || p2=$J/p2.status.all
  pred=$LOGD/prediction.txt
  predict server "$ROOT" "$REL" "$h" "$pe" $p2 > "$pred" 2> "$pred.err"; rc=$?   # stdout only is the prediction
  cat "$pred" "$pred.err" >> "$LOG"; sed -n 's/^\(row\|verdict\) /\1 /p' "$pred" | while read -r l; do say "gate0-run: prediction: $l"; done
  if [ $rc != 0 ] || ! grep -q '^verdict run' "$pred"; then rbail "the prediction says STOP; nothing started, marker moved aside again (see $pred)"; fi
  tip0=$(lane_refs "refs/heads/autosync/$h") || rbail "cannot read the lane tip before the run: an unreadable lane is not an unchanged one; nothing started, marker moved aside again"
  tip0=${tip0%%$'\t'*}   # the first field, with no command whose status could be lost
  tags0=$(tag_refs) || rbail "cannot read the gate0 tags before the run; nothing started, marker moved aside again"
  arch0=$(lane_refs "refs/heads/archive/gate0/$h/*") || rbail "cannot read the archive branches before the run; nothing started, marker moved aside again"
  [ ! -e "$J/done-p1a" ] || { [ -n "$tags0" ] && [ -n "$arch0" ]; } || rbail "P1a ran on this machine but the gate0 tag or the archive branch is not there: nothing started, marker moved aside again"
  cur=$(journal_cursor) && [ -n "$cur" ] || rbail "cannot take a journal cursor: lines of an earlier run could not be told from this run's; nothing started, marker moved aside again"
  units start "$REPAIR_SVC"; say "gate0-run: the service start returned $? (the unit's result is not a row signal; the run is judged by Sylveste's lines and the checkout)"
  tries=${GATE0_JOURNAL_TRIES:-10}; n=0
  jok=0
  while :; do if journal_since "$cur" > "$LOGD/journal.txt"; then jok=1; grep -Eq '^[0-9]+ autosync repo\(s\)' "$LOGD/journal.txt" && break; else jok=0; fi   # lines read by a failed read are not evidence
    n=$((n+1)); [ "$n" -le "$tries" ] || break; sleep 1; done
  cat "$LOGD/journal.txt" >> "$LOG"
  [ "$jok" = 1 ] || rbail "the journal could not be read after the start: its lines cannot be trusted; marker moved aside, timers stay stopped"
  grep -Eq '^[0-9]+ autosync repo\(s\)' "$LOGD/journal.txt" || rbail "the start left no '<n> autosync repo(s)' summary line: the run did not happen; marker moved aside, timers stay stopped"
  if ! predict verify "$pred" "$LOGD/journal.txt" > "$LOGD/verify.out" 2>&1; then
    cat "$LOGD/verify.out" >> "$LOG"; cat "$LOGD/verify.out"; rbail "the run differs from the prediction (log lines, committed paths, status after, or lane tip); marker moved aside, timers stay stopped"; fi
  cat "$LOGD/verify.out" >> "$LOG"
  tags1=$(tag_refs) || rbail "cannot read the gate0 tags after the run: the tag is not known to be preserved; marker moved aside, timers stay stopped"
  arch1=$(lane_refs "refs/heads/archive/gate0/$h/*") || rbail "cannot read the archive branches after the run: the archive is not known to be preserved; marker moved aside, timers stay stopped"
  [ "$tags0" = "$tags1" ] && [ "$arch0" = "$arch1" ] || rbail "the tag or an archive branch changed during the restart run; marker moved aside, timers stay stopped"
  tip1=$(lane_refs "refs/heads/autosync/$h") || rbail "cannot read the lane tip after the run; marker moved aside, timers stay stopped"
  tip1=${tip1%%$'\t'*}; say "gate0-run: lane tip autosync/$h: ${tip0:-absent} -> ${tip1:-absent}"; }
restart_clavain() {  # exit-name
  local pred rc tipn l0 mrec
  [ ! -e "$PAUSE" ] || stop "the automations are paused ($PAUSE exists): the sweep would exit at once; remove it deliberately and re-run"
  mrec=$(rec_marker) || stop "the freeze record cannot be read: whether a marker was set aside cannot be told; nothing was run"   # a failed read is not a record that says something else
  if [ "$mrec" = none ]; then
    say "gate0-run: P0 found no marker: Clavain has no autosync to restart (row 8)"
    tipn=$(pg ls-remote "$LANE" "refs/heads/autosync/$HOST") || stop "cannot read the Clavain lane tip: an unreadable lane is not an unchanged one"
    [ -f "$J/p0/lane" ] || stop "the P0 lane record $J/p0/lane is missing: whether the Clavain lane tip changed cannot be told"
    l0=$(cat "$J/p0/lane") || stop "the P0 lane record $J/p0/lane cannot be read: whether the Clavain lane tip changed cannot be told"   # an empty record is read as empty only after a successful read
    [ "${tipn%%$'\t'*}" = "$l0" ] || stop "the Clavain lane tip changed with no marker"
    return 0; fi
  [ -f "$G/marker" ] && grep -qE '^LANE=1[[:space:]]*$' "$G/marker" || stop "the marker to restore has no LANE=1: a state in no row"
  restore_marker
  pred=$LOGD/prediction.txt
  predict clavain "$ROOT" "$HOST" > "$pred" 2> "$pred.err"; rc=$?; cat "$pred" "$pred.err" >> "$LOG"
  if [ $rc != 0 ] || ! grep -q '^verdict run' "$pred"; then rbail "the prediction says STOP; the sweep was not run, marker moved aside again (see $pred)"; fi
  # an earlier report is not evidence about this sweep: set it aside, so only a report this sweep wrote can be verified
  [ ! -e "$DRIFT" ] || mv -f -- "$DRIFT" "$LOGD/drift.before" || rbail "cannot set the earlier drift report aside ($DRIFT)"
  "$SWEEP" > "$LOGD/sweep.out" 2>&1; say "gate0-run: the sweep returned $? (its exit status is logged, not judged: the verdict is the drift report it wrote)"; cat "$LOGD/sweep.out" >> "$LOG"
  if [ ! -f "$DRIFT" ]; then [ ! -e "$LOGD/drift.before" ] || mv -f -- "$LOGD/drift.before" "$DRIFT"   # put the earlier report back as found
    rbail "the sweep wrote no new drift report ($DRIFT)"; fi
  predict verify "$pred" "$DRIFT" > "$LOGD/verify.out" 2>&1 || { tee -a "$LOG" < "$LOGD/verify.out"; rbail "the sweep differs from the prediction; marker moved aside"; }
  cat "$LOGD/verify.out" >> "$LOG"; }
unrecord_bail() { rm -f -- "$G/restarted-$XARG"; rbail "$@; every timer of this attempt is stopped again and the marker is aside"; }
restarted_holds() {  # a restart that is already recorded: re-verify the state it describes and run nothing
  local u m ts
  ts=$(rec_timers) || unrecord_bail "restart $1 is recorded but the freeze record cannot be read: the timers it names cannot be checked; nothing was run"
  for u in $ts; do   # an unknown state is a failure of this check, so it goes through the cleanup too
    [ "$(unit_state "$u")" = active ] || unrecord_bail "restart $1 is recorded but $u is not confirmed active: the state is not the one the record describes; nothing was run"; done
  m=$(rec_marker) || unrecord_bail "restart $1 is recorded but the freeze record cannot be read: its marker cannot be checked; nothing was run"
  if [ "$m" != none ]; then [[ $m =~ ^[0-9a-f]{64}$ ]] && [ -e "$ROOT/.git-autosync" ] && [ "$(sha < "$ROOT/.git-autosync")" = "$m" ] ||
    unrecord_bail "restart $1 is recorded but the marker in the checkout is not the one set aside; nothing was run"
  else [ ! -e "$ROOT/.git-autosync" ] || unrecord_bail "restart $1 is recorded with no marker, but a marker is in the checkout; nothing was run"; fi
  rm -f -- "$G"/restarting-*   # a leftover from a crash after the record was written
  say "gate0-run: restart $1 already done ($(cat "$G/restarted-$1")); the recorded timers are active and the marker is in place; nothing run"; }
do_restart() {
  local ex=$XARG pe=$XARG sn sr
  if [ $CHECKMODE = 1 ]; then
    [ ! -d "$J/p1-pre" ] || [ ! -e "$J/done-p1a" ] || { capture_check && runlog cs preserved "$( [ "$ex" = r6 ] && echo r6 )"; } || stop "restart step 1 would fail"
    say "gate0-run: restart $ex check: would run the unfreeze gate, preservation, reconciliation, the marker, one autosync run and the timers"; return 0; fi
  [ -e "$G/freeze" ] || refuse "no freeze record"
  if [ -e "$G/restarted-$ex" ]; then restarted_holds "$ex"; return 0; fi   # a repeat runs nothing
  if restarting_any; then rbail "an earlier restart attempt began (marker, service or timers) and left no completion record: its effects are undone now (every timer stopped, marker aside); run the restart again as a new attempt"; fi
  freeze_holds   # restart: the freeze must hold now (units, marker, agents, bd), not only have been recorded
  archive_ready   # the lane this restart reads and the run pushes to is validated now, not trusted from preflight
  if [ "$ex" = r0 ]; then
    if cpv=$(cut -d' ' -f1 "$J/cp" 2>/dev/null) && [ "$cpv" = a0r ]; then pe=a0r
    elif [ ! -e "$J/done-p1a" ]; then pe=p10   # P1a never ran: the machine is at the base, rows 1 or 2 with P1-pre's status
      sn=$(pg status --porcelain -uall) || stop "R0 without P1a: cannot read the status"
      [ -f "$J/p1-pre/status.all" ] || stop "R0 without P1a: P1-pre's status record $J/p1-pre/status.all is missing"
      sr=$(cat "$J/p1-pre/status.all") || stop "R0 without P1a: P1-pre's status record cannot be read"
      sn=$(printf '%s\n' "$sn" | nobeads) && sr=$(printf '%s\n' "$sr" | nobeads) || stop "R0 without P1a: the status cannot be filtered"
      [ "$sn" = "$sr" ] || stop "R0 without P1a: the status differs from P1-pre's record"
    else stop "R0 after P1a needs R0a first (run rollback)"; fi; fi
  runlog cs unfreeze-gate "$ex" || stop "the unfreeze gate refused: the freeze stays"
  if [ -e "$J/done-p1a" ]; then   # the wrapper's own check first: the pinned step reads the record with a loop that drops a last line with no newline
    capture_check || stop "restart step 1: the capture in the journal does not match its sha256 record (both entries are checked, a last line with no newline included); nothing restarted"
    runlog cs preserved "$( [ "$ex" = r6 ] && echo r6 )" || stop "restart step 1 failed before anything restarted"; fi
  reconcile
  put "$G/restarting-$ex" "at $(date -u +%Y-%m-%dT%H:%M:%SZ)"   # before the first side effect: a crash from here to the completion record is found and undone by the next restart
  if [ "$MACHINE" = server ]; then restart_server "$ex" "$pe"; else restart_clavain "$ex"; fi
  # step 5: the timers; the bd writers and the agent sessions resume afterwards, started by their owners
  local u ts; ts=$(rec_timers) || rbail "the freeze record cannot be read: the timers to start are unknown; every timer of this attempt is stopped again and the marker is aside"
  for u in $ts; do
    units start "$u" || rbail "cannot re-enable $u; every timer of this attempt is stopped again and the marker is aside"
    [ "$(unit_state "$u")" = active ] || rbail "$u is not active after its start (a controller that returns 0 proves nothing); every timer of this attempt is stopped again and the marker is aside"; done
  put "$G/restarted-$ex" "at $(date -u +%Y-%m-%dT%H:%M:%SZ)" unrecord_bail
  rm -f -- "$G/restarting-$ex"
  say "gate0-run: restart $ex done: the recorded timers are running again; resume the bd writers and the agent sessions now (they are not started by this script)"; }

need_inputs
say "gate0-run.sh $SELF_SHA: $CMDLINE (machine $MACHINE, host $HOST, base $BASE)"
case $PHASE in
  preflight) do_preflight ;;
  freeze) do_freeze ;;
  capture) do_capture ;;
  run) do_preflight && do_freeze && do_capture ;;
  rollback) do_rollback ;;
  restart) do_restart ;;
esac
