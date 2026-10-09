#!/bin/bash
# rh-gate0.sh: rehearsal RH for the Gate 0 ops of plan §1.4 (revisions 9.1-9.9),
# scratch clones only. It drives out/cutover-steps.sh (p0, p1-pre, p1a, the P1a
# --check, p2, rollback/R0a, unfreeze-gate r0/p10, preserved) on a synthetic
# Sylveste checkout and runs the real git-autosync-repair.sh and
# git-autosync-sweep.sh from dotfiles against restart states, checking each run
# against out/restart-predict.sh. One repair run goes through a transient
# systemd user unit, as the service runs it, with its journal captured.
#
# Isolation: the outer process allocates a fresh mktemp dir B under $T_ROOT
# (default ../work) and runs every case in bubblewrap with / read-only, only B
# writable, no network and a cleared environment. The inner process trusts none
# of that: before any case it probes that /, $T_ROOT, thread storage, this
# directory, ~/.beads and the operator home refuse a write with EROFS and leave no file,
# that B is writable, and that /proc/self/mountinfo shows / read-only and no
# read-write mount outside B, /tmp, /dev, /proc and the root-owned host mounts
# listed in iso(). HOME is inside B; every remote is a file:// bare repository
# inside B. The lane library is a copy of the installed one with exactly three
# edits, checked by diff: asl_slug maps the scratch file:// URLs to rh/Sylveste
# and rh/Sylveste-lane, asl_private answers yes for those two slugs (no gh call),
# asl_build allows the file protocol. One case runs the installed library
# unchanged and must refuse.
# bd: every case uses a stub CUTOVER_BD that logs its calls and answers
# `export -o FILE` with a canned export. bd 1.1.2 ignores $HOME and `-C` for init
# (a first RH run wrote into the real ~/.beads), so the one real-bd case (an
# older export imported over a tracker with newer records) runs in a nested
# bubblewrap after a canary write under ~/.beads fails with EROFS; if that proof
# fails, the case counts as a failure. A guard records ~/.beads (names, sizes,
# mtimes; shared-server/, eventsData/ and last-touched excluded, other bd
# processes on the host write them) before anything runs and fails the run if it changed. The guard is
# an advisory concurrency check, not an integrity proof: under .dolt/noms it
# compares names, types and sizes only (another writer re-stamps those mtimes),
# so a same-size content change there goes unseen. Isolation rests on the
# read-only mounts that iso() and the canary prove, not on this guard.
#
# Logs: $RH_LOG_DIR (default $GATE0_STATE_DIR/logs, else logs/ beside this
# script's directory). The EXIT trap writes a report (this script's sha256, the
# step, the exit status, the log and its sha256) and sends it with report-tell
# --title "$RH_REPORT_TITLE"; RH_REPORT=0 turns that off, RH_REPORT_TELL names
# another sender. Run as root, it re-executes itself as $GATE0_OPERATOR.
#
#   rh-gate0.sh [--no-nested]     run; exit 0 when every check passes
#   rh-gate0.sh --check           syntax and inputs only; runs nothing, writes nothing
set -u
PATH=/usr/local/bin:/usr/bin:/bin
export LC_ALL=C
HERE=$(cd "$(dirname "$0")" && pwd -P); SELF=$HERE/$(basename "$0")
# the hash tool is chosen by a known answer (the digest of no input), so a present but broken sha256sum falls back
if [ "$(printf '' | sha256sum 2>/dev/null | cut -d' ' -f1)" = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 ]
then sha() { sha256sum | cut -d' ' -f1; }; else sha() { shasum -a 256 2>/dev/null | cut -d' ' -f1; }; fi
SELF_SHA=$(sha < "$SELF")
[[ $SELF_SHA =~ ^[0-9a-f]{64}$ ]] || { echo "rh: no sha256 of this script (neither sha256sum nor shasum -a 256 works); refusing" >&2; exit 1; }
CS=$HERE/cutover-steps.sh; PRED=$HERE/restart-predict.sh
OPH=${GATE0_OPERATOR_HOME:-${HOME:-}}; [ -n "$OPH" ] || { echo "rh: set GATE0_OPERATOR_HOME" >&2; exit 1; }
DOT=${GATE0_DOTFILES:-$OPH/projects/dotfiles}
REPAIR=$DOT/server/.local/bin/git-autosync-repair.sh; SWEEP=$DOT/common/.local/bin/git-autosync-sweep.sh
IL=$OPH/.local/lib/autosync-lane.sh; BDBIN=$OPH/.local/bin/bd; BWRAP=/usr/bin/bwrap; RB=$OPH/.beads
SPATH=/usr/local/bin:/usr/bin:/bin
# eventsData is bd's metrics queue, written by any bd run on the host (seen changing with no RH running).
# last-touched records the last bead any bd run on the host touched (seen 2026-10-09 at 01:59:19 holding
# another tracker's bead while RH's only bd ran in the EROFS-proven nested sandbox).
# The embedded Dolt stores' noms files and dirs are re-stamped by another writer every few minutes with
# no RH running (seen 2026-10-09: manifest mtimes moved at 00:45:18 and 00:45:52, sizes unchanged), so
# under .dolt/noms the guard compares names, types and sizes, not mtimes; a write by a bd run (a new
# store, a new table file, a longer journal) still changes a name or a size.
beadsstat() { find "$RB" \( -path "$RB/shared-server" -o -path "$RB/eventsData" -o -path "$RB/last-touched" \) -prune -o -printf '%y %s %T@ %p\n' 2>&1 |
  awk '$4 ~ /\/\.dolt\/noms(\/|$)/ { $3 = "-" } { print }' | sort; }
MODE=outer
case ${1:-} in
  --check)   # syntax and inputs only; writes nothing
    bash -n "$SELF" && bash -n "$CS" && bash -n "$PRED" && [ -r "$REPAIR" ] && [ -r "$SWEEP" ] && [ -r "$IL" ] && [ -x "$BDBIN" ] && [ -x "$BWRAP" ] &&
      command -v systemd-run > /dev/null && command -v journalctl > /dev/null && echo "rh-gate0.sh: check ok (sha256 $SELF_SHA)"
    exit $? ;;
  --inner) MODE=inner ;;
  --svc-verify) MODE=svcv ;;
esac

# ================================================================ outer: allocate, sandbox, service unit, guard, report
if [ $MODE = outer ]; then
  [ "$(id -u)" != 0 ] || { [ -n "${GATE0_OPERATOR:-}" ] || { echo "rh: run as root only with GATE0_OPERATOR set" >&2; exit 1; }
    exec env GATE0_OPERATOR_HOME="${GATE0_OPERATOR_HOME:-$(getent passwd "$GATE0_OPERATOR" | cut -d: -f6)}" runuser -u "$GATE0_OPERATOR" -- "$SELF" "$@"; }
  NA=; [ "${1:-}" = --no-nested ] && NA=--no-nested
  TS=$(cd "${GATE0_STATE_DIR:-$HERE/..}" && pwd -P) || exit 1
  TR=$(cd "${T_ROOT:-$HERE/../work}" && pwd -P) || exit 1
  LOGD=${RH_LOG_DIR:-$TS/logs}; mkdir -p "$LOGD" || exit 1
  LOG=$LOGD/rh-gate0-$(date -u +%Y%m%dT%H%M%SZ)-$$.log; : > "$LOG" || exit 1
  G=$(mktemp -d "$LOGD/rh-guard.XXXXXX") || exit 1
  beadsstat > "$G/beads.before"
  STEP=setup; RC=1
  finish() {
    beadsstat > "$G/beads.after"
    cmp -s "$G/beads.before" "$G/beads.after" ||
      { { echo "GUARD FAIL: $RB changed during the run:"; diff "$G/beads.before" "$G/beads.after" | head -n 40; } >> "$LOG"; RC=4; }
    local r ls rep=$LOG.report t=${RH_REPORT_TITLE:-cutover} tell=${RH_REPORT_TELL:-}
    r=$([ $RC = 0 ] && echo ok || echo failed)
    if [ $RC = 0 ]; then echo "RESULT: PASS" >> "$LOG"; else echo "RESULT: FAIL (exit $RC, step $STEP)" >> "$LOG"; fi
    ls=$(sha < "$LOG")
    echo "rh-gate0.sh (sha256 $SELF_SHA): step $STEP, exit $RC ($r); log $LOG (sha256 $ls); scratch ${B:-none}" > "$rep"
    if [ "${RH_REPORT:-1}" != 0 ]; then
      "$tell" --title "$t" --message-file "$rep" --script "$SELF" --result "$r" --step "$STEP" --log "$LOG" > /dev/null 2>&1 ||
        { echo "rh-gate0.sh: report not delivered; it is $rep:"; cat "$rep"; }
    fi
    grep '^RESULT' "$LOG" | tail -n 1; echo "log: $LOG"; echo "log sha256: $ls"
    exit $RC; }
  trap finish EXIT
  echo "rh-gate0.sh sha256 $SELF_SHA; log $LOG"
  echo "rh-gate0.sh sha256 $SELF_SHA" >> "$LOG"
  B=$(mktemp -d "$TR/rh.XXXXXX") && B=$(cd "$B" && pwd -P) || exit 1
  sbx() { "$BWRAP" --ro-bind / / --bind "$B" "$B" --dev /dev --proc /proc --tmpfs /tmp --unshare-net --die-with-parent --clearenv \
    --setenv PATH "$SPATH" --setenv LC_ALL C --setenv GATE0_OPERATOR_HOME "$OPH" --setenv GATE0_DOTFILES "$DOT" "$@"; }
  STEP=cases; sbx /bin/bash "$SELF" --inner "$B" "$TS" $NA >> "$LOG" 2>&1; irc=$?
  STEP=service; src=0
  if [ -f "$B/svc.ready" ]; then
    U=rh-svc-$(date -u +%Y%m%dT%H%M%SZ)-$$
    echo "== service path: the real repair as the transient user unit $U, in bubblewrap" >> "$LOG"
    XDG_RUNTIME_DIR=/run/user/$(id -u) systemd-run --user --quiet --wait --collect --unit="$U" -p SyslogIdentifier="$U" -- "$BWRAP" --ro-bind / / --bind "$B" "$B" \
      --dev /dev --proc /proc --tmpfs /tmp --unshare-net --die-with-parent --clearenv --setenv PATH "$SPATH" --setenv LC_ALL C \
      --setenv HOME "$B/home" --setenv TMPDIR "$B/tmp" --setenv GIT_CONFIG_NOSYSTEM 1 --setenv RIG_AUTOSYNC_ROOT "$B/x/svc/root" \
      --setenv RIG_HEALTH_DIR "$B/health" --setenv ASL_PAUSE_FILE "$B/absent" --setenv AUTOSYNC_LANE mA \
      --setenv AUTOSYNC_LANE_LIB "$B/lib/autosync-lane.sh" /bin/bash "$REPAIR" >> "$LOG" 2>&1
    echo "$?" > "$B/svc.rc"
    # by identifier: `-u` loses the lines of a writer that exited before journald read them (here the repair's
    # `cat "$DETAIL" >&2`, every NEEDS-HUMAN and PUSH line); the unit's own exit lines come from `-u`
    for i in $(seq 1 40); do
      { XDG_RUNTIME_DIR=/run/user/$(id -u) journalctl --user -t "$U" --no-pager -o cat
        XDG_RUNTIME_DIR=/run/user/$(id -u) journalctl --user -u "$U" --no-pager -o cat | grep "^$U.service: "; } > "$B/svc.journal" 2>&1
      grep -q 'Main process exited' "$B/svc.journal" && grep -q 'need a human' "$B/svc.journal" && break; sleep 0.25; done
    XDG_RUNTIME_DIR=/run/user/$(id -u) journalctl --user -u "$U" --no-pager -o cat > "$B/svc.journal-u" 2>&1
    echo "  unit exit $(cat "$B/svc.rc"); journal:" >> "$LOG"; sed 's/^/    /' "$B/svc.journal" >> "$LOG"
    STEP=svc-verify; sbx /bin/bash "$SELF" --svc-verify "$B" "$TS" >> "$LOG" 2>&1; src=$?
  else echo "  FAIL the inner phase did not prepare the service case" >> "$LOG"; src=1; fi
  echo "scratch kept: $B" >> "$LOG"
  STEP=done; [ $irc = 0 ] && [ $src = 0 ] && RC=0 || RC=1
  exit $RC
fi

# ================================================================ inner: verify the sandbox, then the cases
B=$(cd "${2:?}" && pwd -P) && TS=${3:?} || exit 1
NESTED=1; [ "${4:-}" = --no-nested ] && NESTED=0
export CUTOVER_REPORT=0 RESTART_REPORT=0 GIT_CONFIG_NOSYSTEM=1 HOME="$B/home" TMPDIR="$B/tmp"
fails=0; TOTAL=0; SUMMARY=""
check() { if [ "$2" = "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1: got [$2] want [$3]"; fails=$((fails+1)); fi; }
fail() { echo "  FAIL $*"; fails=$((fails+1)); }
iso() {  # the sandbox, verified from inside rather than trusted from the environment
  local d f bad=0 m p
  for d in / "$(dirname "$B")" "$TS" "$HERE" "$RB" "$OPH"; do f=$d/.rh-probe-$$
    if touch "$f" 2> "$B/probe.err"; then rm -f -- "$f"; echo "  isolation: $d is writable"; bad=1
    elif ! grep -q 'Read-only file system' "$B/probe.err"; then echo "  isolation: $d: $(head -n 1 "$B/probe.err")"; bad=1
    elif [ -e "$f" ] || [ -L "$f" ]; then echo "  isolation: $f exists"; bad=1; fi; done
  touch "$B/.probe" && rm -f -- "$B/.probe" || { echo "  isolation: $B is not writable"; bad=1; }
  [ "$(awk '$5=="/"{split($6,o,","); print o[1]}' /proc/self/mountinfo | sort -u)" = ro ] || { echo "  isolation: / is not read-only"; bad=1; }
  # root-owned host mounts that bubblewrap's recursive bind leaves read-write; this user cannot write them
  while read -r m p; do [ "$m" = rw ] || continue
    case $p in "$B"|"$B"/*|/tmp|/tmp/*|/dev|/dev/*|/proc|/proc/*|/sys/*|/var/lib/docker/*|/run/docker/*|/run/snapd/*) ;;
      *) echo "  isolation: $p is mounted read-write"; bad=1 ;; esac
  done < <(awk '{split($6,o,","); print o[1], $5}' /proc/self/mountinfo)
  return $bad; }
pres() { git -C "$1" for-each-ref --format='%(refname) %(objectname)' refs/tags; git --git-dir="$(dirname "$(dirname "$1")")/lane.git" for-each-ref refs/heads/archive 2>/dev/null; }
iso || { echo "rh: the sandbox is not proven; no case runs"; exit 1; }
echo "sandbox proven from inside: / and $(dirname "$B"), $TS, $HERE, $RB, $OPH refuse writes (EROFS, no file left); only $B (and /tmp, /dev, /proc) mounted read-write"

if [ $MODE = svcv ]; then   # the service case, after the outer process ran the unit
  echo "== service path: verify"
  r=$B/x/svc/root/Sylveste
  check "service: the unit exited 1 (the planted file is a STOP)" "$(cat "$B/svc.rc")" 1
  check "service: the journal records the unit's failure" "$(grep -c 'status=1/FAILURE' "$B/svc.journal")" 1
  echo "  note: NEEDS-HUMAN lines in the journal read by unit: $(grep -c 'NEEDS-HUMAN' "$B/svc.journal-u"), by identifier: $(grep -c 'NEEDS-HUMAN' "$B/svc.journal")"
  bash "$PRED" verify "$B/rs/svc.pred" "$B/svc.journal" > "$B/out" 2>&1; rc=$?
  check "service: the journal matches the prediction" "$rc" 0; [ $rc = 0 ] || sed 's/^/    /' "$B/out"
  check "service: tag and archive branches unchanged" "$(pres "$r")" "$(cat "$B/svc.pres")"
  if [ $fails = 0 ]; then echo "SERVICE: PASS"; exit 0; else echo "SERVICE: FAIL ($fails)"; exit 1; fi
fi

[ -z "${GIT_CONFIG_COUNT:-}${GIT_CONFIG_PARAMETERS:-}" ] || { echo "rh: GIT_CONFIG_COUNT/PARAMETERS set; the lane library refuses"; exit 1; }
W=$B/w; R=$W/root/Sylveste; J=$W/J; CNT=$B/count; CLOG=$B/crash.log; TL=$B/lib/autosync-lane.sh
mkdir -p "$HOME" "$TMPDIR" "$B/bin" "$B/lib" "$B/rs" "$B/health" "$B/chk" "$B/rep"
git config --global user.email t@example.invalid; git config --global user.name t
git config --global init.defaultBranch main; git config --global advice.detachedHead false
export GIT_AUTHOR_DATE='2026-10-01T00:00:00Z' GIT_COMMITTER_DATE='2026-10-01T00:00:00Z'
link_text() { local t; t=$(readlink -- "$1" && printf x) || return 1; t=${t%x}; printf '%s' "${t%?}"; }
dg() { if [ -L "$1" ]; then printf 'l:%s\n' "$(link_text "$1" | sha)"; elif [ -d "$1" ]; then echo d
  elif [ -f "$1" ] && [ -x "$1" ]; then printf 'x:%s\n' "$(sha < "$1")"; elif [ -f "$1" ]; then printf 'f:%s\n' "$(sha < "$1")"; else echo -; fi; }
files() { (cd "$1" && find . -path ./.git -prune -o \( -type f -o -type l \) -print | sed 's|^\./||' | sort); }
dmap() { local p; while IFS= read -r p; do printf '%s\t%s\n' "$(dg "$1/$p")" "$p"; done < "$2"; }   # dir pathsfile
snap() { rm -rf -- "${B:?}/tpl-${1:?}"; cp -a "$W" "$B/tpl-$1"; }
restore() { rm -rf -- "${W:?}"; cp -a "$B/tpl-$1" "$W"; rm -f -- "${CNT:?}" "${CLOG:?}"; }
label() { awk -v n="$1" '$1==n{print $2"/"$3}' "$CLOG"; }
wr() { mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; }
g() { git -C "$R" "$@"; }
cs() {  # cutover-steps.sh on the fixture; AT>0 crashes it at that point
  if [ "${AT:-0}" = 0 ]; then env -u CUTOVER_CRASH_AT CUTOVER_BD="${BDW:-$B/bin/bd}" bash "$CS" "$R" "$J" "$@"
  else env CUTOVER_CRASH_AT="$AT" CUTOVER_CRASH_COUNT="$CNT" CUTOVER_CRASH_LOG="$CLOG" CUTOVER_BD="${BDW:-$B/bin/bd}" bash "$CS" "$R" "$J" "$@"; fi; }
ckfp() {  # the checkout as the plan sees it: HEAD, index, status, every file's digest, local refs
  g symbolic-ref -q HEAD; g rev-parse HEAD; g ls-files -s | sha; g status --porcelain -uall
  files "$R" > "$B/ck.list"; dmap "$R" "$B/ck.list"
  g for-each-ref --format='%(refname) %(objectname)' refs/heads refs/tags refs/gate0; }
lanerefs() { git --git-dir="$W/lane.git" for-each-ref --format='%(refname) %(objectname)'; }
jtree() { (cd "$J" && find . -type f -print0 | sort -z | xargs -0 sha256sum); }
echo "rh-gate0.sh sha256 $SELF_SHA"
echo "steps: $CS ($(sha < "$CS")); predictor: $PRED ($(sha < "$PRED"))"
echo "repair: $REPAIR ($(sha < "$REPAIR")); sweep: $SWEEP ($(sha < "$SWEEP")); lane lib: $IL ($(sha < "$IL"))"
echo "scratch: $B; bash $BASH_VERSION; $(git version); bd binary $(sha < "$BDBIN")"

# ---------------------------------------------------------------- test lane library
echo "== test lane library: the installed library plus exactly three edits"
awk -v b="$B" '
  /^        https:\/\/github.com\/\*\)/ { print
    print "        file://" b "/*/pub.git) rest=rh/Sylveste ;;   # RH test lib"
    print "        file://" b "/*/lane.git) rest=rh/Sylveste-lane ;;   # RH test lib"; next }
  /^asl_private\(\) \{/ { print; getline; print; print "    case $1 in rh/Sylveste|rh/Sylveste-lane) return 0 ;; esac   # RH test lib"; next }
  /-c protocol.https.allow=always\)$/ { sub(/-c protocol.https.allow=always\)$/, "-c protocol.https.allow=always -c protocol.file.allow=always)   # RH test lib") }
  { print }' "$IL" > "$TL"
diff "$IL" "$TL" > "$B/lib.diff"
check "lib diff: one line replaced, four lines added, all marked" \
  "$(grep -c '^<' "$B/lib.diff") $(grep -c '^>' "$B/lib.diff") $(grep '^>' "$B/lib.diff" | grep -vc 'RH test lib')" "1 4 0"
sed 's/^/    /' "$B/lib.diff"

# ---------------------------------------------------------------- stub trackers (no real bd)
rec() { printf '{"_type":"issue","id":"%s","title":"%s","status":"open","priority":2,"issue_type":"task","created_at":"%s","updated_at":"%s"}\n' "$1" "$2" "$3" "$3"; }
rec rh-one one 2026-10-01T00:00:01Z > "$B/one.jsonl"
{ rec rh-two two 2026-10-01T00:00:02Z; cat "$B/one.jsonl"; } > "$B/trk.jsonl"   # the tracker: one and two
rec rh-oth other 2026-10-01T00:00:03Z > "$B/trk2.jsonl"                         # a second tracker
for t in trk trk2; do
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> %q\ncase "$1 ${2:-}" in "export -o") cp %q "$3" ;; *) echo "bd stub: unsupported: $*" >&2; exit 2 ;; esac\n' \
    "$B/bd-calls" "$B/$t.jsonl" > "$B/bin/bd-$t"; chmod +x "$B/bin/bd-$t"; done
printf '#!/bin/bash\ncase "$1 ${2:-}" in "export -o") : > "$3" ;; *) exit 2 ;; esac\n' > "$B/bin/bd-empty"   # an empty export
printf '#!/bin/bash\nexit 0\n' > "$B/bin/bd-nofile"                                                           # exit 0, no file
printf '#!/bin/bash\nprintf "%%s\\n" "$@" > %q\nexit 0\n' "$B/tell.args" > "$B/bin/tell"; printf '#!/bin/bash\nexit 1\n' > "$B/bin/tell-fail"
chmod +x "$B/bin/bd-empty" "$B/bin/bd-nofile" "$B/bin/tell" "$B/bin/tell-fail"
ln -s bd-trk "$B/bin/bd"; ln -s bd-trk2 "$B/bin/bd2"

# ---------------------------------------------------------------- fixture
echo "== fixture"
mkdir -p "$W/root"; git init -q --bare "$W/pub.git"; git init -q --bare "$W/lane.git"
SD=$W/seed; git init -q "$SD"; git -C "$SD" remote add origin "file://$W/pub.git"
wr "$SD/README.md" 'readme v1'
for f in a cu gone up del; do wr "$SD/internal/$f.md" "$f v1"; done
wr "$SD/internal/mode.sh" 'echo mode'
wr "$SD/docs/sylveste-vision.md" 'vision v1'; wr "$SD/docs/research/r.md" 'research'
wr "$SD/ops/run.sh" 'run v1'; wr "$SD/ops/old.sh" 'old v1'; wr "$SD/uv.lock" 'lock v1'
mkdir -p "$SD/.beads"; cp "$B/one.jsonl" "$SD/.beads/issues.jsonl"
git -C "$SD" add -A; git -C "$SD" commit -qm c1
for i in 2 3 4; do wr "$SD/README.md" "readme v$i"; git -C "$SD" commit -qam "c$i"; done
C4=$(git -C "$SD" rev-parse HEAD)
wr "$SD/docs/added.md" 'added in the base'; git -C "$SD" add docs/added.md
for i in 5 6 7 8; do wr "$SD/README.md" "readme v$i"; wr "$SD/internal/up.md" "up v$i"; git -C "$SD" commit -qam "c$i"; done
BASE=$(git -C "$SD" rev-parse HEAD); git -C "$SD" push -q origin main
git -C "$SD" branch -q pr1 "$BASE"; git -C "$SD" checkout -q pr1
wr "$SD/docs/sylveste-vision.md" 'vision v2'; git -C "$SD" rm -rq internal docs/research; git -C "$SD" commit -qam 'PR 1'
PR1=$(git -C "$SD" rev-parse HEAD); git -C "$SD" push -q origin pr1; git -C "$SD" checkout -q main
git clone -q "file://$W/pub.git" "$R"; g checkout -q -B main "$C4"; g branch -q -u origin/main main
g remote add lane "file://$W/lane.git"
printf 'LANE=1\nLANE_REMOTE=lane\n' > "$R/.git-autosync"; printf '.git-autosync\n' >> "$R/.git/info/exclude"
wr "$R/internal/a.md" 'a local'; wr "$R/internal/new.md" 'new local'; g rm -q internal/del.md; g add -A; g commit -qm 'local internal'
wr "$R/docs/sylveste-vision.md" 'vision v2'; g commit -qam 'local vision'
cp "$B/trk.jsonl" "$R/.beads/issues.jsonl"; g commit -qam 'local beads'
wr "$R/ops/run.sh" 'run local'; g commit -qam 'local ops'
wr "$R/ops/new.sh" 'new local'; g add ops/new.sh; g rm -q ops/old.sh; g commit -qm 'local ops add and delete'   # non-KEEP add and delete
wr "$R/internal/cu.md" 'cu committed'; g commit -qam 'local cu'
wr "$R/internal/cu.md" 'cu uncommitted'; rm "$R/internal/gone.md"; chmod +x "$R/internal/mode.sh"; ln -s a.md "$R/internal/ln"
( source "$TL"; asl_resolve "$R" && asl_tip "$R" autosync/mA && asl_push "$R" autosync/mA ) || { echo "fixture: lane push through the test lib failed"; exit 1; }
O=$(g rev-parse HEAD)
check "fixture: the lane holds o, pushed through the test lib" "$(git --git-dir="$W/lane.git" rev-parse refs/heads/autosync/mA)" "$O"
mkdir -p "$J"; echo "$BASE" > "$J/base"; echo mA > "$J/host"; echo lane > "$J/lane-remote"; echo "$PR1" > "$J/pr1-head"
printf 'pr1\tdocs/sylveste-vision.md\nbeads-export\t.beads/issues.jsonl\nops-12a\tops/*\n' > "$J/dispositions"
printf 'internal/\ndocs/research/\n' > "$J/delete-list"
echo "  base $BASE, old $O, pr1 $PR1"
snap fx
cs p0 || fail "p0 on the fixture"; snap p0
cs p1-pre; check "p1-pre on the fixture passes" "$?" 0; snap pre

# ---------------------------------------------------------------- P1-pre STOPs
pstop() {  # name message : p1-pre stops (3), writes no record and no temp dir, leaves the checkout alone
  local before rc; before=$(ckfp); cs p1-pre > "$B/out" 2>&1; rc=$?
  check "P1-pre STOP $1: exit 3, nothing written, checkout unchanged" \
    "$rc $(grep -c -- "$2" "$B/out") $(ls "$J" | grep -c '^p1-pre') $([ "$(ckfp)" = "$before" ] && echo same)" "3 1 0 same"
  grep -q -- "$2" "$B/out" || sed 's/^/    /' "$B/out"; }
echo "== P1-pre STOP cases"
restore fx; wr "$R/misc/x.md" x; g add misc/x.md; g commit -qm 'unmapped'; cs p0; pstop "mA-x (an unmapped path before P0)" "a disposition-set path has no disposition"
restore p0; wr "$R/README.md" 'readme local'; g commit -qam 'public'; pstop "mA-q (a public-path commit after P0)" "touches a path outside the approved classes"
restore p0; echo "$PR1" >> "$J/p0/commits"; pstop "a P0 commit not in main (tampered J/p0/commits)" "is not in main"
restore p0; echo "$PR1" >> "$J/p0/lane-only"; pstop "a lane-only commit not in the approved lane (tampered J/p0/lane-only)" "is not in the approved lane"
restore p0; wr "$W/seed/README.md" 'readme v9'; git -C "$W/seed" commit -qam c9; git -C "$W/seed" push -q origin main
pstop "origin/main moved" "origin/main is not the approved base"
restore p0; g add internal/cu.md; pstop "a staged entry" "staged entries"
restore p0; wr "$R/README.md" 'readme edited'; pstop "an uncommitted README edit after P0 (W-snapshot)" "a W-snapshot entry changed"

echo "== P1-pre PASS: mA-p (an internal commit after P0)"
restore p0; wr "$R/internal/p.md" p; g add internal/p.md; g commit -qm 'internal after P0'; cs p1-pre; rc=$?
check "mA-p: p1-pre passes and the inventory lists the new commit" "$rc $(grep -c "^$(g rev-parse HEAD)	internal	internal/p.md$" "$J/p1-pre/inventory")" "0 1"

echo "== mA-L: the lane holds a commit main does not"
restore fx; git clone -q "$R" "$B/lc"; wr "$B/lc/internal/lane.md" lane; git -C "$B/lc" add -A; git -C "$B/lc" commit -qm 'lane only'
LA=$(git -C "$B/lc" rev-parse HEAD); git -C "$B/lc" push -q "file://$W/lane.git" "$LA:refs/heads/autosync/mA"
cs p0; check "mA-L: P0 records the lane-only commit" "$(cat "$J/p0/lane-only")" "$LA"; snap L0
wr "$B/lc/internal/lane.md" lane2; git -C "$B/lc" commit -qam 'lane again'; git -C "$B/lc" push -q "file://$W/lane.git" "HEAD:refs/heads/autosync/mA"
pstop "mA-L (the lane moved again after P0)" "neither in main nor P0's approved lane"
restore L0; cs p1-pre; rc=$?
check "mA-L: p1-pre passes and records the lane archive" "$rc $(cat "$J/p1-pre/lane-archive")" "0 $LA"
snap Lpre
cs p1a; rc=$?
check "mA-L: p1a archives the lane tip and the old main" "$rc $(git --git-dir="$W/lane.git" rev-parse "refs/heads/archive/gate0/mA/lane-$LA" "refs/heads/archive/gate0/mA/$O" | paste -sd' ' -)" "0 $LA $O"
check "mA-L: the bundle's heads" "$(git bundle list-heads "$J/capture/main.bundle" | awk '{print $2"="$1}' | sort | paste -sd' ' -)" \
  "refs/gate0/base=$BASE refs/gate0/lane=$LA refs/heads/main=$O"

# ---------------------------------------------------------------- P1a refusals
prefuse() {  # name message [bd] : p1a refuses (1), writes nothing (no capture, checkpoint, intent, archive, tag), checkout unchanged
  local before lb rc; before=$(ckfp); lb=$(lanerefs); BDW=${3:-} cs p1a > "$B/out" 2>&1; rc=$?
  check "P1a refuses $1: exit 1, nothing written, checkout and lane unchanged" \
    "$rc $(grep -c -- "$2" "$B/out") $(ls "$J" | grep -cE '^(capture|cp|intent|done-|p1a-check|keep.list)') $([ "$(ckfp)" = "$before" ] && echo same) $([ "$(lanerefs)" = "$lb" ] && echo same)" \
    "1 1 0 same same"
  grep -q -- "$2" "$B/out" || sed 's/^/    /' "$B/out"; }
echo "== P1a refusals"
restore pre; prefuse "with a tracker that lacks the records (a second tracker)" "not dominated by the tracker" "$B/bin/bd2"
restore pre; prefuse "with an empty tracker export while the capture has records" "the tracker export is empty" "$B/bin/bd-empty"
restore pre; prefuse "when bd export exits 0 and writes no file" "bd export wrote no file" "$B/bin/bd-nofile"
restore fx; sed 's/"updated_at":"[^"]*"/"updated_at":"2099-01-01T00:00:00Z"/' "$R/.beads/issues.jsonl" > "$B/n.jsonl"
cp "$B/n.jsonl" "$R/.beads/issues.jsonl"; g commit -qam 'records newer than the tracker'; cs p0; cs p1-pre
prefuse "mA-n (a record newer in the capture than the tracker)" "not dominated by the tracker"
restore pre; echo "$BASE" > "$J/pr1-head"; prefuse "when PR 1 does not carry the change (pr1-head = base)" "PR 1 does not carry the local change"
restore pre; git -C "$W/seed" push -q "file://$W/lane.git" "$BASE:refs/heads/archive/gate0/mA/$O"
prefuse "with the archive branch pre-pushed at another commit" "is at $BASE on the lane, not $O"
restore pre; git clone -q "$R" "$B/lc2"; wr "$B/lc2/internal/l.md" l; git -C "$B/lc2" add -A; git -C "$B/lc2" commit -qm l
git -C "$B/lc2" push -q "file://$W/lane.git" "HEAD:refs/heads/autosync/mA"; rm -rf -- "${B:?}/lc2"
prefuse "when the lane moved after P1-pre" "the lane moved since P1-pre"

echo "== jsonl_dominated (cutover-steps.sh's function, extracted)"
sed -n '/^jsonl_dominated() {/,/"\$2" "\$1"; }$/p' "$CS" > "$B/jd.sh"
jd() { bash -c 'source "$1"; jsonl_dominated "$2" "$3"' _ "$B/jd.sh" "$1" "$2" 2> /dev/null; }
: > "$B/jd-empty"; rec rh-one one-newer 2026-10-01T00:00:09Z > "$B/jd-newer"; rec rh-two two 2026-10-01T00:00:02Z >> "$B/jd-newer"
jd "$B/one.jsonl" "$B/jd-empty"; check "an empty export does not dominate a base with records" "$?" 1
jd "$B/jd-empty" "$B/jd-empty"; check "an empty export dominates an empty base" "$?" 0
jd "$B/one.jsonl" "$B/jd-missing"; check "a missing export dominates nothing" "$?" 1
jd "$B/one.jsonl" "$B/jd-newer"; check "an export with the record newer and an extra record dominates" "$?" 0
jd "$B/jd-newer" "$B/trk.jsonl"; check "a base record newer than the export is not dominated" "$?" 1

echo "== tag op"
restore pre; g update-ref "refs/tags/gate0/mA-$O" "$O"; cs p1a; rc=$?
check "a tag already at the old tip is skipped; p1a finishes at a1" "$rc $(cut -d' ' -f1 "$J/cp") $(g rev-parse "refs/tags/gate0/mA-$O")" "0 a1 $O"
restore pre; g update-ref "refs/tags/gate0/mA-$O" "$BASE"; cs p1a > "$B/out" 2>&1; rc=$?
check "a tag at the base: STOP 3, intent kept, at a0, HEAD still the old tip" \
  "$rc $([ -e "$J/intent" ] && echo intent) $(cat "$J/cp") $(g rev-parse HEAD) $(grep -c "is in neither its old nor its new state" "$B/out")" "3 intent a0 $O $O 1"

# ---------------------------------------------------------------- the P1a --check (preflight on a scratch copy)
echo "== P1a --check"
restore pre; ck0=$(ckfp); ix0=$(sha < "$R/.git/index"); jt0=$(jtree); lr0=$(lanerefs)
CUTOVER_BD=$B/bin/bd CUTOVER_CHECK_DIR=$B/chk bash "$CS" --check "$R" "$J" p1a > "$B/out" 2>&1; rc=$?
check "the P1a check passes before P1a" "$rc $(grep -c 'P1a check: pass' "$B/out")" "0 1"; [ $rc = 0 ] || sed 's/^/    /' "$B/out"
check "the check leaves the checkout, its index, the journal and the lane unchanged" \
  "$([ "$(ckfp)" = "$ck0" ] && echo same) $([ "$(sha < "$R/.git/index")" = "$ix0" ] && echo same) $([ "$(jtree)" = "$jt0" ] && echo same) $([ "$(lanerefs)" = "$lr0" ] && echo same)" \
  "same same same same"
ckd=$(sed -n 's/^cutover: P1a check: scratch //p' "$B/out")
check "the check built the capture in its scratch dir (bundle, sha256 manifest, W-snapshot)" \
  "$(cd "$ckd/J/capture.tmp" 2>/dev/null && ls main.bundle sha256 wtree.tar 2>/dev/null | paste -sd' ' -) $(cut -f1 "$ckd/J/capture.tmp/sha256" 2>/dev/null | paste -sd' ' -)" \
  "main.bundle sha256 wtree.tar main.bundle wtree.tar"
check "the check's scratch dir is under CUTOVER_CHECK_DIR" "$(dirname "$ckd")" "$B/chk"
restore pre; cs p1a > /dev/null 2>&1
CUTOVER_BD=$B/bin/bd CUTOVER_CHECK_DIR=$B/chk bash "$CS" --check "$R" "$J" p1a > "$B/out" 2>&1
check "the P1a check refuses after P1a (a checkpoint exists)" "$? $(grep -c 'runs only before P1a' "$B/out")" "1 1"
restore pre; wr "$W/seed/README.md" 'readme v9'; git -C "$W/seed" commit -qam c9; git -C "$W/seed" push -q origin main
CUTOVER_BD=$B/bin/bd CUTOVER_CHECK_DIR=$B/chk bash "$CS" --check "$R" "$J" p1a > "$B/out" 2>&1
check "the P1a check refuses when origin/main moved and was not fetched" "$? $(grep -c 'differs from the remote-tracking ref' "$B/out")" "1 1"
restore pre   # the seed and pub.git live in W; restore drops c9

# ---------------------------------------------------------------- P1a and R0a, uncrashed
echo "== P1a"
restore pre; cs p1a; check "p1a exits 0 at a1" "$? $(cat "$J/cp")" "0 a1 $BASE"
check "HEAD is the base, level with origin/main" "$(g rev-parse HEAD) $(g rev-list --left-right --count HEAD...refs/remotes/origin/main)" "$BASE 0	0"
check "status against the base" "$(g status --porcelain -uall | sort | paste -sd'|' -)" \
  " D internal/del.md| D internal/gone.md| M internal/a.md| M internal/cu.md| M internal/mode.sh| M internal/up.md|?? internal/ln|?? internal/new.md"
check "cu.md holds the uncommitted bytes, up.md the old bytes, gone.md absent" \
  "$(cat "$R/internal/cu.md") $(cat "$R/internal/up.md") $([ -e "$R/internal/gone.md" ] || echo absent)" "cu uncommitted up v1 absent"
check "public paths hold the base" "$(g diff --name-only HEAD -- README.md docs ops uv.lock .beads | wc -l)" 0
check "non-KEEP realign: the local add removed, the local delete and the base's add written" \
  "$([ -e "$R/ops/new.sh" ] || echo absent) $(cat "$R/ops/old.sh") $(cat "$R/docs/added.md")" "absent old v1 added in the base"
check "tag, archive branch, lane unchanged" \
  "$(g rev-parse "refs/tags/gate0/mA-$O") $(git --git-dir="$W/lane.git" rev-parse "refs/heads/archive/gate0/mA/$O" refs/heads/autosync/mA | paste -sd' ' -)" "$O $O $O"
g bundle verify -q "$J/capture/main.bundle" > /dev/null 2>&1; check "bundle verify" "$?" 0
check "bundle heads" "$(git bundle list-heads "$J/capture/main.bundle" | awk '{print $2"="$1}' | sort | paste -sd' ' -)" "refs/gate0/base=$BASE refs/heads/main=$O"
check "capture digests" "$(while IFS=$'\t' read -r f s; do [ "$(sha < "$J/capture/$f")" = "$s" ] && echo ok; done < "$J/capture/sha256" | paste -sd' ' -)" "ok ok"
mkdir "$B/tar"; tar -C "$B/tar" -xpf "$J/capture/wtree.tar"
check "the W-snapshot tar restores wtree.manifest" "$(cut -f2 "$J/capture/wtree.manifest" | while IFS= read -r p; do printf '%s\t%s\n' "$(dg "$B/tar/$p")" "$p"; done)" "$(cat "$J/capture/wtree.manifest")"
check "the KEEP paths" "$(cut -f2 "$J/keep.list" | paste -sd' ' -)" "internal/a.md internal/cu.md internal/del.md internal/gone.md internal/ln internal/mode.sh internal/new.md internal/up.md"
cs forward > "$B/out" 2>&1; check "forward at a1 refuses (P1a is done; run p2)" "$? $(grep -c 'run p2' "$B/out")" "1 1"
snap a1; ckfp > "$B/ck-a1"
echo "== R0a from a1"
cs rollback; check "rollback from a1 runs R0a and stops at a0r" "$? $(cat "$J/cp")" "0 a0r $O"
check "the checkout is the P1-pre checkout again" "$(g status --porcelain -uall) $(g rev-parse HEAD)" "$(cat "$J/p1-pre/status.all") $O"
check "non-KEEP realign undone: the local add back, the local delete and the base's add gone" \
  "$(cat "$R/ops/new.sh") $([ -e "$R/ops/old.sh" ] || echo absent) $([ -e "$R/docs/added.md" ] || echo absent)" "new local absent absent"
check "the tag is kept" "$(g rev-parse "refs/tags/gate0/mA-$O")" "$O"
cs unfreeze-gate r0 > "$B/out" 2>&1; check "unfreeze-gate r0 passes" "$? $(cat "$B/out")" "0 cutover: unfreeze gate r0: pass"
cs preserved > "$B/out" 2>&1; check "restart step 1: preservation intact" "$? $(cat "$B/out")" "0 cutover: preservation intact"
ckfp > "$B/ck-a0r"; snap a0r
cs rollback; check "a second rollback is a no-op" "$? $([ "$(ckfp)" = "$(cat "$B/ck-a0r")" ] && echo same) $(cat "$J/cp")" "0 same a0r $O"
echo "== R0a from c0 (P2 ran, PR 1 not merged)"
restore a1; cs p2; check "p2 at a1 records c0" "$? $(cat "$J/cp")" "0 c0 $BASE"; snap c0
check "p2 records the status in the repair script's mode" "$(cat "$J/p2.status.all")" "$(g status --porcelain=v1 --untracked-files=all)"
cs rollback; check "rollback from c0 before P5 runs R0a to a0r" "$? $(cat "$J/cp")" "0 a0r $O"
check "the same checkout as R0a from a1" "$(ckfp)" "$(cat "$B/ck-a0r")"
cs unfreeze-gate r0 > /dev/null 2>&1; check "unfreeze-gate r0 passes" "$?" 0

# ---------------------------------------------------------------- restart step 1: the preservation check fails closed
echo "== preserved: a damaged capture STOPs"
ppre() {  # name message edit... : from a0r, edit the capture, preserved stops (3) with the message
  local n=$1 m=$2; shift 2; restore a0r; "$@"; cs preserved > "$B/out" 2>&1
  check "preserved STOPs: $n" "$? $(grep -c -- "$m" "$B/out")" "3 1"; }
ppre "the sha256 manifest removed" "sha256 manifest is missing" rm -f -- "$J/capture/sha256"
ppre "a manifest line dropped" "does not list exactly" sed -i '/^wtree.tar/d' "$J/capture/sha256"
ppre "an extra manifest line" "does not list exactly" sh -c "printf 'extra\tx\n' >> '$J/capture/sha256'"
ppre "a blank digest" "main.bundle changed or is missing" sed -i 's/^main.bundle\t.*/main.bundle\t/' "$J/capture/sha256"
ppre "wtree.tar corrupted" "wtree.tar changed or is missing" sh -c "printf x >> '$J/capture/wtree.tar'"
ppre "main.bundle removed" "main.bundle changed or is missing" rm -f -- "$J/capture/main.bundle"

# ---------------------------------------------------------------- rollback routing around P5
echo "== rollback routing: PR 1 merged by squash, recorded and unrecorded merge sha"
sq() { git -C "$W/seed" commit-tree "$PR1^{tree}" -p "$BASE" -m 'PR 1 (squash)'; }   # fixed dates: the same sha after each restore
restore a1; SQ=$(sq); git -C "$W/seed" push -q origin "$SQ:refs/heads/main"; echo "$SQ" > "$J/pr1-merge"; before=$(ckfp)
cs rollback > "$B/out" 2>&1
check "a squash merge in main, recorded: rollback at a1 STOPs (after P5), nothing undone" \
  "$? $(grep -c 'PR 1 is merged (after P5)' "$B/out") $([ "$(ckfp)" = "$before" ] && echo same) $(cut -d' ' -f1 "$J/cp")" "3 1 same a1"
restore a1; SQ=$(sq); git -C "$W/seed" push -q origin "$SQ:refs/heads/main"; cs rollback > "$B/out" 2>&1
check "a squash merge in main, no merge sha recorded: STOP, the PR 1 head is no stand-in" \
  "$? $(grep -c 'no PR 1 merge sha is recorded' "$B/out") $(cut -d' ' -f1 "$J/cp")" "3 1 a1"
restore a1; SQ=$(sq); git -C "$W/seed" push -q origin "$SQ:refs/heads/sq"; echo "$SQ" > "$J/pr1-merge"
wr "$W/seed/README.md" 'readme v9'; git -C "$W/seed" commit -qam c9; git -C "$W/seed" push -q origin main
cs rollback > "$B/out" 2>&1
check "the recorded merge not in main (main moved by an unrelated commit): R0a runs to a0r" "$? $(cut -d' ' -f1 "$J/cp")" "0 a0r"
[ "$(cut -d' ' -f1 "$J/cp")" = a0r ] || sed 's/^/    /' "$B/out"
echo "== rollback routing: c0 without P1a (R0 exit)"
restore pre; cs p2; check "p2 before P1a records c0" "$? $(cut -d' ' -f1 "$J/cp")" "0 c0"; before=$(ckfp)
cs rollback > "$B/out" 2>&1
check "rollback at c0 without done-p1a before P5: the R0 exit, nothing undone" \
  "$? $(grep -c 'R0, nothing to undo' "$B/out") $([ "$(ckfp)" = "$before" ] && echo same) $(cut -d' ' -f1 "$J/cp")" "0 1 same c0"
cs unfreeze-gate r0 > "$B/out" 2>&1; check "unfreeze-gate r0 passes at c0 without P1a" "$? $(cat "$B/out")" "0 cutover: unfreeze gate r0: pass"

# ---------------------------------------------------------------- the R0 gate refuses unfinished intents
echo "== unfreeze-gate r0 and unfinished intents"
gi=0; n=0
while :; do n=$((n+1)); restore a1; AT=$n cs rollback > /dev/null 2>&1; rc=$?; [ $rc = 137 ] || break
  [ -e "$J/intent" ] || continue; gi=$((gi+1))
  cs unfreeze-gate r0 > "$B/out" 2>&1; rc=$?; check "R0a crashed at point $n ($(label $n)) with an intent: the gate STOPs" "$rc $(grep -c 'an unfinished intent' "$B/out")" "3 1"
  cs rollback > /dev/null 2>&1; check "then rollback finishes at a0r and the gate passes" "$? $(cut -d' ' -f1 "$J/cp") $(cs unfreeze-gate r0 2>&1)" "0 a0r cutover: unfreeze gate r0: pass"
done
[ $gi -gt 0 ] || fail "no R0a crash point left an intent"
ga=0; gb=0; gc=0; n=0
while :; do n=$((n+1)); restore pre; AT=$n cs p1a > /dev/null 2>&1; rc=$?; [ $rc = 137 ] || break
  cs unfreeze-gate r0 > "$B/out" 2>&1; rc=$?
  if [ -e "$J/intent" ]; then ga=$((ga+1)); check "P1a crashed at point $n ($(label $n)), intent unfinished: the gate STOPs" "$rc $(grep -c 'an unfinished intent' "$B/out")" "3 1"
  elif [ "$(cut -d' ' -f1 "$J/cp" 2>/dev/null)" = a1 ]; then gc=$((gc+1))
    check "P1a crashed at point $n ($(label $n)), at a1, no intent: the gate STOPs (rollback first)" "$rc $(grep -c 'P1a ran; run rollback' "$B/out")" "3 1"
  else gb=$((gb+1)); check "P1a crashed at point $n ($(label $n)), checkpoint '$(cut -d' ' -f1 "$J/cp" 2>/dev/null)', no intent: the gate passes" "$rc" 0; fi
done
check "P1a crash points with an intent, without one before a1, and at a1 were all covered" "$([ $ga -gt 0 ] && echo y) $([ $gb -gt 0 ] && echo y) $([ $gc -gt 0 ] && echo y)" "y y y"

# ---------------------------------------------------------------- the P10 gate compares content with the expected end state
echo "== unfreeze-gate p10"
P=$B/p10g; PRT=$P/root/Sylveste; JP=$P/J
git init -q --bare "$P/pub.git"; git clone -q "file://$P/pub.git" "$P/seed" 2> /dev/null; wr "$P/seed/README.md" r
git -C "$P/seed" add -A; git -C "$P/seed" commit -qm r; git -C "$P/seed" push -q origin main
git clone -q "file://$P/pub.git" "$PRT"; git init -q --bare "$PRT/.git-internal"
git clone -q "$PRT/.git-internal" "$P/gi" 2> /dev/null; wr "$P/gi/internal/s.md" 's v1'; git -C "$P/gi" add -A; git -C "$P/gi" commit -qm s; git -C "$P/gi" push -q origin main
wr "$PRT/internal/s.md" 's v1'; wr "$PRT/internal/l.md" 'l local'
mkdir -p "$JP"; printf 'internal/\n' > "$JP/delete-list"; echo internal/s.md > "$JP/shared.manifest"; echo internal/l.md > "$JP/local.manifest"
printf 'f:%s\tinternal/l.md\n' "$(printf 'l local\n' | sha)" > "$JP/p2.manifest"
printf 'f:%s\tinternal/l.md\nf:%s\tinternal/s.md\n' "$(printf 'l local\n' | sha)" "$(printf 's v1\n' | sha)" > "$JP/p9"
rm -rf -- "${B:?}/p10g-tpl"; cp -a "$P" "$B/p10g-tpl"
pg10() {  # name rc message edit... : from the template, edit, run the p10 gate
  local n=$1 want=$2 m=$3; shift 3; rm -rf -- "${P:?}"; cp -a "$B/p10g-tpl" "$P"; "$@"
  bash "$CS" "$PRT" "$JP" unfreeze-gate p10 > "$B/out" 2>&1
  check "p10 gate: $n" "$? $(grep -c -- "$m" "$B/out")" "$want 1"; }
pg10 "the expected end state passes" 0 "unfreeze gate p10: pass" true
pg10 "a shared file's content changed" 3 "content is not its expected end state" wr "$PRT/internal/s.md" 's changed'
pg10 "a local file's content changed" 3 "content is not its expected end state" wr "$PRT/internal/l.md" 'l changed'
pg10 "the private HEAD moved the shared file" 3 "content is not its expected end state" \
  sh -c "printf 's v2\n' > '$P/gi/internal/s.md' && git -C '$P/gi' commit -qam s2 && git -C '$P/gi' push -q origin main"
pg10 "an extra internal file" 3 "not shared+local" wr "$PRT/internal/x.md" x
pg10 "local.manifest is missing" 3 "cannot build the P10 expected set" rm -f -- "$JP/local.manifest"
pg10 "shared.manifest is missing" 3 "cannot build the P10 expected set" rm -f -- "$JP/shared.manifest"
nob() {  # the shared blob cannot be read, and disk and P9 both hold the digest of no input (the fail-open shape)
  local o; o=$(git -C "$PRT/.git-internal" rev-parse HEAD:internal/s.md) && [ -f "$PRT/.git-internal/objects/${o:0:2}/${o:2}" ] &&
    rm -f -- "$PRT/.git-internal/objects/${o:0:2}/${o:2}" || fail "p10 gate fixture: the shared blob is not a loose object"
  : > "$PRT/internal/s.md"
  printf 'f:%s\tinternal/l.md\nf:%s\tinternal/s.md\n' "$(printf 'l local\n' | sha)" "$(printf '' | sha)" > "$JP/p9"; }
pg10 "the shared blob cannot be read (disk and P9 empty)" 3 "cannot build the P10 expected set" nob
echo "== fsync_path (cutover-steps.sh's function, extracted)"
sed -n '/^fsync_path() {/p' "$CS" > "$B/fs.sh"
fsp() { bash -c 'source "$1"; [ "$2" = ok ] || sync() { return 1; }; fsync_path "$3"' _ "$B/fs.sh" "$1" "$2" 2> /dev/null; }
fsp ok "$B/fs.sh"; check "fsync_path: an existing file flushes" "$?" 0
fsp ok "$B/no-such-file"; check "fsync_path: a missing path fails" "$?" 1
fsp fail "$B/fs.sh"; check "fsync_path: a failing sync fails" "$?" 1
pg10 "no P9 record" 3 "no record" rm -f -- "$JP/p9"
pg10 "P9's record differs" 3 "P9's record is not the expected end state" sed -i 's/^f:[0-9a-f]*\tinternal\/s.md/f:0\tinternal\/s.md/' "$JP/p9"

# ---------------------------------------------------------------- the EXIT-trap reports
echo "== reports (EXIT trap, stub sender)"
targ() { awk -v k="$1" 'p{print; exit} $0==k{p=1}' "$B/tell.args"; }
restore a0r; rm -f -- "$B/tell.args"
CUTOVER_REPORT=1 CUTOVER_REPORT_TELL=$B/bin/tell CUTOVER_LOG_DIR=$B/rep cs unfreeze-gate r0 > "$B/out" 2>&1; rc=$?
check "cutover-steps: the step's exit is kept and the report is sent (title, script, result, step)" \
  "$rc|$(targ --title)|$(targ --script)|$(targ --result)|$(targ --step)" "0|cutover|$CS|ok|unfreeze-gate"
check "cutover-steps: the report names the script's sha256 and the exit" \
  "$(grep -c "sha256 $(sha < "$CS").*step unfreeze-gate, exit 0 (ok)" "$(targ --message-file)" 2>/dev/null)" 1
restore a1; rm -f -- "$B/tell.args"
CUTOVER_REPORT=1 CUTOVER_REPORT_TELL=$B/bin/tell CUTOVER_LOG_DIR=$B/rep cs unfreeze-gate r0 > "$B/out" 2>&1; rc=$?
check "cutover-steps: a failing step reports failed and keeps its exit" "$rc $(targ --result)" "3 failed"
restore a0r
CUTOVER_REPORT=1 CUTOVER_REPORT_TELL=$B/bin/tell-fail CUTOVER_LOG_DIR=$B/rep cs unfreeze-gate r0 > "$B/out" 2>&1; rc=$?
check "cutover-steps: an undelivered report is printed and the exit kept" "$rc $(grep -c 'report not delivered' "$B/out") $(grep -c 'exit 0 (ok)' "$B/out")" "0 1 1"

# ---------------------------------------------------------------- crash injection
files "$B/tpl-pre/root/Sylveste" > "$B/d1"; files "$B/tpl-a1/root/Sylveste" > "$B/d2"; sort -u "$B/d1" "$B/d2" > "$B/D"
dmap "$B/tpl-pre/root/Sylveste" "$B/D" > "$B/map-pre"; dmap "$B/tpl-a1/root/Sylveste" "$B/D" > "$B/map-a1"
dmap "$B/tpl-a0r/root/Sylveste" "$B/D" > "$B/map-a0r"
fp() {  # convergence fingerprint: the checkout, its refs, the lane, the journal (bundle and tar bytes excluded)
  ckfp; git --git-dir="$W/lane.git" for-each-ref --format='%(refname) %(objectname)'
  (cd "$J" && find . -type f | sort) | while IFS= read -r f; do case $f in
    ./capture/main.bundle|./capture/wtree.tar) echo "$f" ;; *) echo "$f $(sha < "$J/$f")" ;; esac; done; }
moment() {  # pre-map post-map : every path holds its pre or its post state, KEEP paths hold pre, o reachable
  dmap "$R" "$B/D" > "$B/map-now"
  awk -F'\t' 'FILENAME==ARGV[1] {a[$2]=$1; next} FILENAME==ARGV[2] {b[$2]=$1; next}
    $1 != a[$2] && $1 != b[$2] { print "    moment: " $2 " is " $1; bad=1 } END { exit bad }' "$1" "$2" "$B/map-now" || return 1
  while IFS=$'\t' read -r s p; do [ "$(dg "$R/$p")" = "$s" ] || { echo "    moment: KEEP $p"; return 1; }; done < "$B/tpl-a1/J/keep.list"
  [ -n "$(g for-each-ref --contains "$O" --format=x)" ]; }
converged() { fp > "$B/fp-now"; cmp -s "$B/fp-now" "$1" || { diff "$1" "$B/fp-now" | head -n 6 | sed 's/^/    /'; return 1; }; }
# inject NAME TEMPLATE ACT CONT MOMENT END [LABELS] : one crash per run, at N = 1, 2, ...
# Each recovery (CONT with no crash) must exit 0, the run past the last point
# must exit 0, at least one point must be covered, and every crash-point label
# in LABELS (as label prints them) must be among the points.
declare -A NPTS
inject() {
  local name=$1 tpl=$2 act=$3 cont=$4 mom=$5 fin=$6 want=${7:-} n=0 rc crc pts=0 names="" l
  echo "== crash: $name"
  while :; do n=$((n+1)); restore "$tpl"; AT=$n $act > /dev/null 2>&1; rc=$?
    [ $rc = 137 ] || break
    pts=$n; names="$names $(label $n)"
    $mom || fail "$name: data lost at crash point $n ($(label $n))"
    AT=0 $cont > /dev/null 2>&1; crc=$?
    [ $crc = 0 ] || fail "$name: recovery after crash point $n ($(label $n)) exited $crc"
    $fin || fail "$name: no convergence after crash point $n ($(label $n))"
  done
  check "$name: the run past the last point finishes (rc 0) and converges" "$rc $($fin && echo pass)" "0 pass"
  [ $pts -gt 0 ] || fail "$name: no injection point was reached"
  for l in $want; do case " $names " in *" $l "*) ;; *) fail "$name: expected crash point $l not covered" ;; esac; done
  echo "  points: $pts:$names"; NPTS[$tpl:$act]=$pts; TOTAL=$((TOTAL+pts)); SUMMARY="$SUMMARY
  $name: $pts"; }
# inject2: crash ACT at N, then CONT at each of its own points M, then CONT again.
# The outer count must equal inject's, each inner run past its last point and
# each recovery must exit 0, and at least one pair must be covered.
inject2() {
  local name=$1 tpl=$2 act=$3 cont=$4 mom=$5 fin=$6 n=0 m rc crc pts=0 outer=0
  echo "== crash: $name (nested)"
  while :; do n=$((n+1)); restore "$tpl"; AT=$n $act > /dev/null 2>&1; rc=$?
    [ $rc = 137 ] || break
    outer=$n; snap "$tpl-n"; m=0
    while :; do m=$((m+1)); restore "$tpl-n"; AT=$m $cont > /dev/null 2>&1; rc=$?
      [ $rc = 137 ] || break
      pts=$((pts+1)); $mom || fail "$name: data lost at crash $n then $m"
      AT=0 $cont > /dev/null 2>&1; crc=$?
      [ $crc = 0 ] || fail "$name: recovery after crash $n then $m ($(label $m)) exited $crc"
      $fin || fail "$name: no convergence after crash $n then $m ($(label $m))"
    done
    [ $rc = 0 ] && $fin || fail "$name: after crash $n, the uncrashed continuation exited $rc or did not converge"
  done
  [ $rc = 0 ] || fail "$name: the uncrashed run exited $rc"
  check "$name: nested outer points equal the single-crash points" "$outer" "${NPTS[$tpl:$act]:-unset}"
  [ $pts -gt 0 ] || fail "$name: no nested pair was reached"
  echo "  nested pairs: $pts"; TOTAL=$((TOTAL+pts)); SUMMARY="$SUMMARY
  $name (nested pairs): $pts"; }
# negative controls of the accounting: a fake scenario whose ACT crashes (137) at
# points 1..NC_PTS and then exits NC_RC, whose CONT crashes at 1..NC_IPTS and
# otherwise exits NC_CRC, and whose END is NC_END. Each fault must count as a failure.
nc_act() { [ "$AT" -ge 1 ] && [ "$AT" -le "$NC_PTS" ] && return 137; return "$NC_RC"; }
nc_cont() { [ "$AT" -ge 1 ] && [ "$AT" -le "$NC_IPTS" ] && return 137; return "$NC_CRC"; }
nc_end() { "$NC_END"; }
nc() { (fails=0; NPTS[nc:nc_act]=3; "$@" >/dev/null 2>&1; echo "$fails"); }
nc_all() { echo "$(nc inject nc nc nc_act nc_cont true nc_end) $(nc inject2 nc nc nc_act nc_cont true nc_end)"; }
echo "== negative controls: the crash accounting turns red on a fault"
mkdir -p "$B/tpl-nc"; export NC_PTS=3 NC_IPTS=2 NC_RC=0 NC_CRC=0 NC_END=true
check "clean fake scenario: inject and inject2 count no failure" "$(nc_all)" "0 0"
for f in NC_CRC=1 NC_PTS=0 NC_RC=2 NC_END=false NC_IPTS=0; do
  r=$(export "${f?}"; nc_all)
  check "fault $f: inject and inject2 turn red [$r]" "$(echo "$r" | awk -v f="$f" '{print ($2>0 && (f=="NC_IPTS=0" || $1>0))}')" 1
done
r=$(NC_PTS=2 nc_all); check "an outer count unequal to the single-crash count turns inject2 red [$r]" "$(echo "$r" | awk '{print ($2>0)}')" 1
unset NC_PTS NC_IPTS NC_RC NC_CRC NC_END; rm -rf -- "${B:?}/tpl-nc" "${B:?}/tpl-nc-n"
restore pre; cs p1a > /dev/null 2>&1; fp > "$B/fp-a1"
restore Lpre; cs p1a > /dev/null 2>&1; fp > "$B/fp-La1"
restore a1; cs rollback > /dev/null 2>&1; fp > "$B/fp-a0r"
restore c0; cs rollback > /dev/null 2>&1; fp > "$B/fp-a0r-c0"
act_p1a() { cs p1a; }; act_rb() { cs rollback; }
mom_p1a() { moment "$B/map-pre" "$B/map-a1"; }; mom_r0a() { moment "$B/map-a1" "$B/map-a0r"; }
fin_p1a() { converged "$B/fp-a1"; }; fin_pL() { converged "$B/fp-La1"; }; fin_r0a() { converged "$B/fp-a0r"; }; fin_r0c() { converged "$B/fp-a0r-c0"; }
P1A_PTS="cutover/gate0-base cutover/capture-bundle cutover/capture-digests cutover/capture-wtree cutover/capture-keep cutover/capture-tar cutover/capture-sha256 cutover/archive cutover/capture cutover/keep-publish cutover/tag cutover/realign-write cutover/realign-remove cutover/realign-index cutover/realign-head"
inject "P1a" pre act_p1a act_p1a mom_p1a fin_p1a "$P1A_PTS"
inject "P1a with a lane-only commit" Lpre act_p1a act_p1a mom_p1a fin_pL "cutover/lane-fetch $P1A_PTS"
inject "R0a from a1" a1 act_rb act_rb mom_r0a fin_r0a "cutover/realign-write cutover/realign-remove cutover/realign-head"
inject "R0a from c0" c0 act_rb act_rb mom_r0a fin_r0c
if [ $NESTED = 1 ]; then
  inject2 "P1a" pre act_p1a act_p1a mom_p1a fin_p1a
  inject2 "R0a from a1" a1 act_rb act_rb mom_r0a fin_r0a
fi

# ---------------------------------------------------------------- restart
echo "== restart: synthetic P10 and R6 origins, the real a0r checkout"
restore a1; git clone -q "file://$W/pub.git" "$B/pubs/seed"
git -C "$B/pubs/seed" merge -q --no-ff -m 'Merge PR 1' origin/pr1
for s in p10 r6; do git init -q --bare "$B/pubs/$s/pub.git"; done
git -C "$B/pubs/seed" push -q "file://$B/pubs/p10/pub.git" main
git -C "$B/pubs/seed" revert -m 1 --no-edit HEAD > /dev/null; git -C "$B/pubs/seed" push -q "file://$B/pubs/r6/pub.git" main
cp -a "$W/lane.git" "$B/pubs/lane.git"   # the frozen lane: autosync/mA = o, the archive branches
repair() {  # root [lib] : the real repair script, isolated
  env HOME="$B/home" RIG_AUTOSYNC_ROOT="$1" RIG_HEALTH_DIR="$B/health" ASL_PAUSE_FILE="$B/absent" TMPDIR="$B/tmp" \
    AUTOSYNC_LANE=mA AUTOSYNC_LANE_LIB="${2:-$TL}" bash "$REPAIR"; }
mkcase() {  # name state [tag] : a checkout of that origin with the frozen lane; prints its path
  local d=$B/x/$1; mkdir -p "$d/root"; cp -a "$B/pubs/lane.git" "$d/lane.git"
  git clone -q "file://$B/pubs/$2/pub.git" "$d/root/Sylveste"; git -C "$d/root/Sylveste" remote add lane "file://$d/lane.git"
  printf 'LANE=1\nLANE_REMOTE=lane\n' > "$d/root/Sylveste/.git-autosync"; printf '.git-autosync\n' >> "$d/root/Sylveste/.git/info/exclude"
  [ -z "${3:-}" ] || git -C "$d/root/Sylveste" fetch -q "$B/tpl-a1/root/Sylveste" "refs/tags/gate0/mA-$O:refs/tags/gate0/mA-$O"
  echo "$d/root/Sylveste"; }
rz() {  # name repo exit verdict row repair-exit [p2status] : predict, run the repair, verify
  local n=$1 repo=$2 pr=$B/rs/$1.pred lg=$B/rs/$1.log rc vc pb
  pb=$(pres "$repo")
  AUTOSYNC_LANE_LIB=$TL bash "$PRED" server "$repo" Sylveste mA "$3" ${7:+"$7"} > "$pr"; rc=$?
  vc=0; [ "$4" = run ] || vc=3
  check "restart $n: predicted $(grep '^row ' "$pr"), $(tail -n 1 "$pr")" "$(grep '^row ' "$pr") $(sed -n 's/^verdict \([A-Za-z]*\).*/\1/p' "$pr") $rc" "row $5 $4 $vc"
  repair "$(dirname "$repo")" > "$lg" 2>&1; rc=$?
  check "restart $n: the repair exits $6" "$rc" "$6"
  bash "$PRED" verify "$pr" "$lg" > "$B/out" 2>&1; rc=$?
  check "restart $n: the run matches the prediction" "$rc" 0; [ $rc = 0 ] || { sed 's/^/    /' "$B/out"; sed 's/^/    log: /' "$lg"; }
  check "restart $n: tag and archive branches unchanged" "$(pres "$repo")" "$pb"; }
jl() { printf '%s\n' '{"_type":"issue","id":"rh-zz","title":"z","updated_at":"2026-10-08T00:00:00Z"}' >> "$1/.beads/issues.jsonl"; }
ST='--porcelain=v1 --untracked-files=all'   # the repair script's status mode, as P2 records it

r=$(mkcase p10-1 p10 tag); rz p10-row1 "$r" p10 run 1 0
rm -f -- "$B/tell.args"
RESTART_REPORT=1 RESTART_REPORT_TELL=$B/bin/tell RESTART_LOG_DIR=$B/rep bash "$PRED" verify "$B/rs/p10-row1.pred" "$B/rs/p10-row1.log" > "$B/out" 2>&1; rc=$?
check "restart-predict: the exit is kept and the report is sent (title, script, result, step)" \
  "$rc|$(targ --title)|$(targ --script)|$(targ --result)|$(targ --step)" "0|cutover|$PRED|ok|verify"
wr "$r/README.md" 'planted'; git -C "$r" commit -qam planted; rz p10-planted-commit "$r" p10 run 2 0
r=$(mkcase p10-2 p10 tag); jl "$r"; cp -a "$B/x/p10-2" "$B/x/p10-neg"; rz p10-row2-jsonl "$r" p10 run 2 0
r=$B/x/p10-neg/root/Sylveste; git -C "$r" remote set-url lane "file://$B/x/p10-neg/lane.git"; h=$(git -C "$r" rev-parse HEAD)
repair "$B/x/p10-neg/root" "$IL" > "$B/rs/neg.log" 2>&1; rc=$?
check "installed lib: the repair refuses, commits nothing, pushes nothing" \
  "$rc $(grep -c "REFUSE  Sylveste -- lane destination not acceptable: origin is not a GitHub ssh/https URL; nothing committed" "$B/rs/neg.log") $(git -C "$r" rev-parse HEAD) $(git --git-dir="$B/x/p10-neg/lane.git" rev-parse refs/heads/autosync/mA)" \
  "1 1 $h $O"
r=$(mkcase p10-3 p10 tag); wr "$r/notes.md" n; rz p10-row3-planted-file "$r" p10 STOP 3 1
r=$(mkcase p10-m p10 tag); sed -i '/^\.git-autosync$/d' "$r/.git/info/exclude"; rz p10-marker-untracked "$r" p10 STOP 2 0
check "the marker rule: the run committed the marker" "$(git -C "$r" show --name-only --format= HEAD)" ".git-autosync"
r=$(mkcase p10-u p10 tag); wr "$r/README.md" local; git -C "$r" commit -qam local
( source "$TL"; asl_resolve "$r" && asl_tip "$r" autosync/mA && asl_push "$r" autosync/mA ) || fail "2u: setting the lane to HEAD"
rz p10-2u "$r" p10 STOP 2u 1
r=$(mkcase r6-1 r6 tag); wr "$r/README.md" edited; git -C "$r" status $ST > "$B/p2-1"; rz r6-one-M "$r" r6 run 3 1 "$B/p2-1"
r=$(mkcase r6-8 r6 tag); wr "$r/README.md" edited; for i in 1 2 3 4 5 6 7; do wr "$r/x$i.md" "$i"; done
git -C "$r" status $ST > "$B/p2-8"; rz r6-eight "$r" r6 run 3 1 "$B/p2-8"
check "r6-eight: six listed and '... and 2 more'" "$(grep -c '^      ' "$B/rs/r6-eight.log") $(grep -c '^      \.\.\. and 2 more$' "$B/rs/r6-eight.log")" "7 1"
r=$(mkcase r6-j r6 tag); wr "$r/README.md" edited; git -C "$r" status $ST > "$B/p2-j"; jl "$r"; rz r6-jsonl "$r" r6 run 3 1 "$B/p2-j"
r=$(mkcase r6-0 r6 tag); : > "$B/p2-0"; rz r6-row1-ignored-marker "$r" r6 run 1 0 "$B/p2-0"
r=$(mkcase r6-c r6 tag); rm "$r/uv.lock"; ln -s README.md "$r/uv.lock"; wr "$r/a b.md" q
git -C "$r" status $ST > "$B/p2-c"; rz r6-classification "$r" r6 run 3 1 "$B/p2-c"
check "classification: type change and quoted path" "$(grep -c '^      uv.lock (type change)$' "$B/rs/r6-classification.log") $(grep -c '^      "a b.md" (quoted path)$' "$B/rs/r6-classification.log")" "1 1"
# the real P2 capture: the c0 checkout's internal set, restored at R5 over the reverted origin
r=$(mkcase r6-p2 r6 tag); rm -rf -- "${r:?}/internal"; cp -a "$B/tpl-c0/root/Sylveste/internal" "$r/internal"
check "r6-real-p2: R5's checkout shows P2's recorded status" "$(git -C "$r" status $ST)" "$(cat "$B/tpl-c0/J/p2.status.all")"
rz r6-real-p2 "$r" r6 run 3 1 "$B/tpl-c0/J/p2.status.all"
# the same with an entirely untracked directory of several files: the default mode collapses it to one
# entry, the repair script's -uall lists every file, so P2 must record each file
restore a1; for f in one two three; do wr "$R/internal/nd/$f.md" "$f"; done
check "r6-real-p2-dir: the default status mode collapses the new directory (the fixture distinguishes)" \
  "$(g status --porcelain | grep -c '^?? internal/nd/$')" 1
cs p2; check "r6-real-p2-dir: p2 at a1 with an untracked directory records c0" "$? $(cut -d' ' -f1 "$J/cp")" "0 c0"
check "r6-real-p2-dir: P2's status lists each file of the untracked directory, not the directory" \
  "$(grep -c '^?? internal/nd/\(one\|two\|three\)\.md$' "$J/p2.status.all") $(grep -c '^?? internal/nd/$' "$J/p2.status.all")" "3 0"
snap c0u
r=$(mkcase r6-p2d r6 tag); rm -rf -- "${r:?}/internal"; cp -a "$B/tpl-c0u/root/Sylveste/internal" "$r/internal"
check "r6-real-p2-dir: R5's checkout shows P2's recorded status" "$(git -C "$r" status $ST)" "$(cat "$B/tpl-c0u/J/p2.status.all")"
rz r6-real-p2-dir "$r" r6 run 3 1 "$B/tpl-c0u/J/p2.status.all"
restore a0r; rz a0r-row4 "$R" a0r run 4 1
restore a0r; jl "$R"; rz a0r-row4-jsonl "$R" a0r run 4 1
check "a0r: tag, archive branches and lane unchanged after the runs" \
  "$(g rev-parse "refs/tags/gate0/mA-$O") $(git --git-dir="$W/lane.git" rev-parse "refs/heads/archive/gate0/mA/$O" refs/heads/autosync/mA | paste -sd' ' -)" "$O $O $O"
cp "$B/rs/p10-row2-jsonl.pred" "$B/rs/tampered.pred"; sed -i 's/^log   COMMIT /log   COMMIT x/' "$B/rs/tampered.pred"
bash "$PRED" verify "$B/rs/tampered.pred" "$B/rs/p10-row2-jsonl.log" > "$B/out" 2>&1
check "a tampered prediction: verify STOPs" "$? $(grep -c 'restart: STOP' "$B/out")" "3 1"
RESTART_REPORT=1 RESTART_REPORT_TELL=$B/bin/tell-fail RESTART_LOG_DIR=$B/rep bash "$PRED" verify "$B/rs/tampered.pred" "$B/rs/p10-row2-jsonl.log" > "$B/out" 2>&1; rc=$?
check "restart-predict: an undelivered report is printed and the exit kept" "$rc $(grep -c 'not delivered' "$B/out")" "3 1"
# verify fails closed: no evidence, an unknown kind, a missing or doubled field, a bad repo or head
vneg() {  # name pred log [cwd] : verify must STOP (3) with a diagnostic and never claim a match
  ( cd "${4:-$B}" && bash "$PRED" verify "$2" "$3" ) > "$B/out" 2>&1; local rc=$?
  check "verify fails closed: $1" "$rc $(grep -c 'restart: STOP' "$B/out") $(grep -c 'matches the prediction' "$B/out")" "3 1 0"; }
mkdir -p /tmp/rh-nonrepo; : > /tmp/rh-nonrepo/empty.pred; : > /tmp/rh-nonrepo/empty.log
check "verify fails closed: the cwd for the empty case is not a git repository" "$(git -C /tmp/rh-nonrepo rev-parse --git-dir > /dev/null 2>&1; echo $?)" 128
vneg "empty PRED and LOG from a non-repository cwd" empty.pred empty.log /tmp/rh-nonrepo
vneg "missing PRED and LOG" /tmp/rh-nonrepo/absent.pred /tmp/rh-nonrepo/absent.log /tmp/rh-nonrepo
vp=$B/rs/p10-row2-jsonl.pred; vl=$B/rs/p10-row2-jsonl.log   # its checkout is not touched again
vneg "an empty LOG" "$vp" /tmp/rh-nonrepo/empty.log
sed 's/^kind server$/kind bogus/' "$vp" > "$B/rs/nk.pred"; vneg "an unknown kind" "$B/rs/nk.pred" "$vl"
sed 's/^kind server$/kind clavain/' "$vp" > "$B/rs/nk2.pred"; vneg "a server row under the clavain kind" "$B/rs/nk2.pred" "$vl"
sed 's/^row .*/row 9/' "$vp" > "$B/rs/nr.pred"; vneg "an unknown row" "$B/rs/nr.pred" "$vl"
for fld in kind repo rel lane head lanetip row verdict; do
  awk -v k="$fld" 'index($0, k " ")!=1 && $0!=k' "$vp" > "$B/rs/nf-$fld.pred"; vneg "a missing $fld line" "$B/rs/nf-$fld.pred" "$vl"; done
awk '{print} /^head /{print}' "$vp" > "$B/rs/dup.pred"; vneg "a doubled head line" "$B/rs/dup.pred" "$vl"
printf 'bogus line\n' | cat - "$vp" > "$B/rs/unk.pred"; vneg "an unknown line" "$B/rs/unk.pred" "$vl"
sed "s|^repo .*|repo /tmp/rh-nonrepo|" "$vp" > "$B/rs/nrepo.pred"; vneg "a repo that is not a git work tree" "$B/rs/nrepo.pred" "$vl"
sed "s|^repo .*|repo rel/Sylveste|" "$vp" > "$B/rs/rrepo.pred"; vneg "a relative repo" "$B/rs/rrepo.pred" "$vl"
sed "s|^head .*|head $(printf '0%.0s' $(seq 40))|" "$vp" > "$B/rs/nh.pred"; vneg "a head that is not a commit in the repo" "$B/rs/nh.pred" "$vl"
sed "s|^head .*|head HEAD|" "$vp" > "$B/rs/sh.pred"; vneg "a head that is not 40 hex" "$B/rs/sh.pred" "$vl"
bash "$PRED" verify "$vp" "$vl" > "$B/out" 2>&1; check "verify fails closed: the untouched prediction still matches (control)" "$?" 0

echo "== restart: the service case, prepared here, run by the outer process as a systemd user unit"
r=$(mkcase svc p10 tag); wr "$r/notes.md" n
AUTOSYNC_LANE_LIB=$TL bash "$PRED" server "$r" Sylveste mA p10 > "$B/rs/svc.pred"; rc=$?
check "service: predicted row 3 STOP" "$(grep '^row ' "$B/rs/svc.pred" | cut -d' ' -f2) $rc" "3 3"
pres "$r" > "$B/svc.pres"; : > "$B/svc.ready"

echo "== restart: Clavain sweep (rows 5-8, marker files only)"
V=$B/x/clv; mkdir -p "$V"
cv() { local d=$V/$1; mkdir -p "$d"; cp -a "$B/pubs/lane.git" "$d/lane.git"; git clone -q "file://$B/pubs/p10/pub.git" "$d/Sylveste"
  git -C "$d/Sylveste" remote add lane "file://$d/lane.git"; [ "$2" = nomarker ] && return
  printf 'LANE=1\nLANE_REMOTE=lane\n' > "$d/Sylveste/.git-autosync"
  [ "$2" = files ] && printf 'x\n' > "$d/Sylveste/.git-autosync-allow-patterns" || printf '.git-autosync\n' >> "$d/Sylveste/.git/info/exclude"; }
cv r5 marker; wr "$V/r5/Sylveste/README.md" dirty
cv r6 marker
cv r7 marker; cv rm files
for x in r7 rm; do ( source "$TL"; asl_resolve "$V/$x/Sylveste" && asl_tip "$V/$x/Sylveste" autosync/mA && asl_push "$V/$x/Sylveste" autosync/mA ) || fail "clavain $x: lane to HEAD"; done
cv r8 nomarker
cv r8d nomarker; wr "$V/r8d/Sylveste/README.md" dirty   # a dirty checkout without a marker: no sweep, the status kept
CV="r5 r6 r7 rm r8 r8d"
for x in $CV; do AUTOSYNC_LANE_LIB=$TL bash "$PRED" clavain "$V/$x/Sylveste" mA > "$B/rs/clv-$x.pred"; done
check "clavain: predicted rows" "$(for x in $CV; do grep '^row ' "$B/rs/clv-$x.pred" | cut -d' ' -f2; done | paste -sd' ' -)" "5 6 7 7 8 8"
check "clavain r8d: the prediction records the dirty status" "$(grep -c '^after .*README.md' "$B/rs/clv-r8d.pred")" 1
env HOME="$B/home" SWEEP_ROOT="$V" AUTOSYNC_LANE=mA AUTOSYNC_LANE_LIB="$TL" ASL_PAUSE_FILE="$B/absent" bash "$SWEEP" > "$B/rs/sweep.out" 2>&1
check "clavain: the sweep exits 0 and writes its report" "$? $(grep -c '^swept 4 repos: 1 pushed, 1 dirty, 0 push-fail$' "$HOME/.local/state/autosync-drift/report.txt")" "0 1"
for x in $CV; do bash "$PRED" verify "$B/rs/clv-$x.pred" "$HOME/.local/state/autosync-drift/report.txt" > "$B/out" 2>&1; rc=$?
  check "clavain $x: the sweep matches the prediction" "$rc" 0; [ $rc = 0 ] || sed 's/^/    /' "$B/out"; done
printf 'fatal: sweep failed\n' > "$B/rs/unrelated.log"   # nonempty, but no sweep ran
for x in r7 rm; do bash "$PRED" verify "$B/rs/clv-$x.pred" "$B/rs/unrelated.log" > "$B/out" 2>&1
  check "clavain $x (row 7): a log with no sweep summary does not verify" "$? $(grep -c 'no sweep summary line' "$B/out")" "3 1"; done
bash "$PRED" verify "$B/rs/clv-r8.pred" "$B/rs/unrelated.log" > "$B/out" 2>&1
check "clavain r8 (row 8, no marker): the sweep never looks at it, so any log verifies" "$?" 0
sed 's/^/    /' "$HOME/.local/state/autosync-drift/report.txt"

echo "== standalone harnesses: a scratch dir that cannot be allocated stops them before any change"
SN=$B/sentinel; mkdir -p "$SN/w"; printf 'keep\n' > "$SN/w/f"; snt() { (cd "$SN" && find . -printf '%y %s %p\n' | sort; cat w/f); }; sn0=$(snt)
for h in crash-inject.sh cutover-repro.sh lane-sync-test.sh; do
  for tr in "$B/no-such-dir" "$HERE"; do   # missing; read-only in the sandbox
    ( cd "$SN" && env T_ROOT="$tr" bash "$HERE/$h" ) > "$B/out" 2>&1; rc=$?
    check "$h with T_ROOT=$tr: exits 1, says nothing changed, the caller's dir is untouched" \
      "$rc $(grep -c 'cannot allocate a scratch dir.*nothing changed' "$B/out") $([ "$(snt)" = "$sn0" ] && echo same)" "1 1 same"; done; done

echo "== hash tools: the scripts fall back to shasum -a 256 and refuse a blank identity hash (nested bubblewrap)"
hb() { "$BWRAP" --ro-bind / / --bind "$B" "$B" --dev /dev --proc /proc --tmpfs /tmp --unshare-net --die-with-parent --clearenv \
  --setenv PATH "$SPATH" --setenv LC_ALL C --setenv HOME "$B/home" --setenv TMPDIR "$B/tmp" --setenv CUTOVER_REPORT 0 \
  --setenv RESTART_REPORT 0 --setenv RH_REPORT 0 "$@"; }
M1=(--ro-bind /dev/null /usr/bin/sha256sum); M2=("${M1[@]}" --ro-bind /dev/null /usr/bin/shasum)
check "the masks break the tools (sha256sum fails; then shasum fails too)" \
  "$(hb "${M1[@]}" /bin/bash -c 'printf "" | sha256sum > /dev/null 2>&1; echo $?') $(hb "${M2[@]}" /bin/bash -c 'printf "" | shasum -a 256 > /dev/null 2>&1; echo $?')" "126 126"
for sc in restart-predict.sh cutover-steps.sh rh-gate0.sh; do
  want=$(sha < "$HERE/$sc")
  hb "${M1[@]}" /bin/bash "$HERE/$sc" --check > "$B/out" 2>&1; rc=$?
  check "$sc without sha256sum: shasum gives the same identity hash" "$rc $(grep -c "check ok (sha256 $want)" "$B/out")" "0 1"
  hb "${M2[@]}" /bin/bash "$HERE/$sc" --check > "$B/out" 2>&1; rc=$?
  check "$sc without either tool: refuses, no check ok" \
    "$([ $rc != 0 ] && echo refused) $(grep -c 'refusing' "$B/out") $(grep -c 'check ok' "$B/out")" "refused 1 0"; done

echo "== real bd 1.1.2: an older export imported over newer records, in a nested bubblewrap only"
bw() { "$BWRAP" --ro-bind / / --bind "$B" "$B" --dev /dev --proc /proc --tmpfs /tmp --unshare-net --die-with-parent --clearenv \
  --setenv PATH "$SPATH" --setenv LC_ALL C --setenv HOME "$B/home" --setenv TMPDIR "$B/tmp" --setenv BD_NON_INTERACTIVE 1 "$@"; }
CN=$RB/.rh-canary-$$
bw /bin/bash -c "touch '$CN'" > "$B/canary.out" 2>&1; rc=$?
if [ $rc != 0 ] && grep -q 'Read-only file system' "$B/canary.out" && [ ! -e "$CN" ] && bw /bin/bash -c "touch '$B/canary-ok'" && [ -e "$B/canary-ok" ]; then
  echo "  ok   isolation proven: a write under $RB fails with EROFS and leaves no file; the scratch dir is writable"
  mkdir -p "$B/bdr/trk"; git init -q "$B/bdr/trk"
  bw --chdir "$B/bdr/trk" /bin/bash -c "set -e; '$BDBIN' version; '$BDBIN' init --prefix rh -q; '$BDBIN' create one -q; '$BDBIN' create two -q; '$BDBIN' export -o ../e0.jsonl" > "$B/bdr/bd.log" 2>&1; rc=$?
  check "real bd: init, two records, export (the older base)" "$rc" 0
  id=$(sed -n 's/.*"id":"\([^"]*\)","title":"one".*/\1/p' "$B/bdr/e0.jsonl")
  sleep 1.1   # bd stamps updated_at from the real clock
  bw --chdir "$B/bdr/trk" /bin/bash -c "set -e; '$BDBIN' update '$id' --title one-newer; '$BDBIN' create three -q; '$BDBIN' import ../e0.jsonl; '$BDBIN' export -o ../e1.jsonl" >> "$B/bdr/bd.log" 2>&1; rc=$?
  check "real bd: update, a third record, import of the older export, export" "$rc" 0; [ $rc = 0 ] || tail -n 15 "$B/bdr/bd.log" | sed 's/^/    /'
  grep -m1 'bd version' "$B/bdr/bd.log" | sed 's/^/    /'
  grep -i 'stale' "$B/bdr/bd.log" | sed 's/^/    /'
  up() { sed -n "s/.*\"id\":\"$1\".*\"updated_at\":\"\([^\"]*\)\".*/\1/p" "$2"; }
  check "real bd: the newer records survive the older import (3 records, one-newer, three)" \
    "$(grep -c '"id":"' "$B/bdr/e1.jsonl") $(grep -c "\"id\":\"$id\",\"title\":\"one-newer\"" "$B/bdr/e1.jsonl") $(grep -c '"title":"three"' "$B/bdr/e1.jsonl")" "3 1 1"
  check "real bd: the updated record's updated_at is later than in the base" "$([ -n "$id" ] && [ "$(up "$id" "$B/bdr/e1.jsonl")" \> "$(up "$id" "$B/bdr/e0.jsonl")" ] && echo later)" later
  check "the real export has the shape the stub mimics (id, title, updated_at per record)" \
    "$(grep -c '^{"_type":"issue","id":"rh-[^"]*","title":"[^"]*",.*"updated_at":"' "$B/bdr/e0.jsonl")" 2
  jd "$B/bdr/e0.jsonl" "$B/bdr/e1.jsonl"; check "the older base is dominated by the tracker's export (cutover-steps jsonl_dominated)" "$?" 0
  jd "$B/bdr/e1.jsonl" "$B/bdr/e0.jsonl"; check "the newer export is not dominated by the older base" "$?" 1
else
  fail "real bd: bwrap did not prove isolation (rc $rc: $(head -n 1 "$B/canary.out")); the import case did not run"
  [ ! -e "$CN" ] || fail "the canary file exists under $RB"
fi
check "the stub bd saw only exports" "$(grep -vc '^export -o ' "$B/bd-calls")" 0

echo "== crash points per scenario:$SUMMARY"
echo "   total crash points exercised: $TOTAL"
echo "scratch kept: $B"
if [ $fails = 0 ]; then echo "CASES: PASS"; exit 0; else echo "CASES: FAIL ($fails)"; exit 1; fi
