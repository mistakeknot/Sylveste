#!/bin/bash
# gate0-run-test.sh: the production wrapper gate0-run.sh against a synthetic fixture (bead mk-z9st.22).
#
# The wrapper is code in the PR and is never run against production by the PR. This test runs the real
# gate0-run.sh and the real cutover-steps.sh on local bare repositories, with stubs for what only the
# operator's machine has: the systemd controller (GATE0_TIMER_CTL), journalctl, the lane library, the
# restart predictor (GATE0_PRED; restart-predict.sh itself is exercised by rh-gate0.sh against the real
# repair script), the tracker and the report sender. It asserts, per phase:
#   --check: nothing in the checkout, the journal or the lane changes;
#   preflight: records J/p0; refuses a writing reference-transaction hook, an unverified archive
#     destination, a base that is not origin/main;
#   freeze: refuses a wrong presence phrase, an agent in the checkout, a running bd; stops the timers and
#     services, moves the marker aside byte for byte, and holds across a re-run;
#   capture: refuses without the freeze or when the marker is back; runs P1a to a1, re-checks, copies the
#     capture to the preservation directory and verifies it by sha256; is idempotent;
#   rollback and restart r0: R0a, the unfreeze gate, reconciliation (the export must dominate the base's
#     and the old tip's records), the marker restored only after a matching prediction, one repair-service
#     start, and the timers back; every failure leaves the marker aside and the timers stopped;
#   the report: one sender call per run with the title, result and step.
# Controls: mutation copies of the wrapper with one safeguard removed each must be judged NOT fail-closed.
#
#   gate0-run-test.sh            run; exit 0 when every check passes
#   gate0-run-test.sh --check    syntax and tools only; runs nothing, writes nothing
# Env: T_ROOT (scratch parent; default $TMPDIR, else /tmp), GATE0_RUN (script under test). Synthetic content only.
set -u
PATH=${GATE0_RUN_TEST_PATH:-/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin}
export LC_ALL=C
HERE=$(cd "$(dirname "$0")" && pwd -P)
GW=${GATE0_RUN:-$HERE/gate0-run.sh}; CS=$HERE/cutover-steps.sh
if [ "$(printf '' | sha256sum 2>/dev/null | cut -d' ' -f1)" = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 ]
then sha() { sha256sum | cut -d' ' -f1; }; else sha() { shasum -a 256 2>/dev/null | cut -d' ' -f1; }; fi
case ${1:-} in
  --check)
    bash -n "$0" && [ -f "$GW" ] && bash -n "$GW" && [ -f "$CS" ] && command -v git >/dev/null && command -v tar >/dev/null &&
      command -v ps >/dev/null && command -v python3 >/dev/null || { echo "gate0-run-test: check failed" >&2; exit 1; }
    echo "gate0-run-test: check ok (sha256 $(sha < "$0"); script under test $GW $(sha < "$GW"))"; exit 0 ;;
  '') ;;
  *) echo "usage: gate0-run-test.sh [--check]" >&2; exit 1 ;;
esac
B=$(mktemp -d "${T_ROOT:-${TMPDIR:-/tmp}}/gate0-run.XXXXXX") && B=$(cd "$B" && pwd -P) && [ -d "$B" ] ||
  { echo "gate0-run-test: cannot allocate a scratch dir; nothing changed" >&2; exit 1; }
fails=0; BG=
cleanup() { [ -z "$BG" ] || kill $BG 2>/dev/null; if [ $fails = 0 ]; then rm -rf -- "${B:?}"; else echo "scratch kept: $B"; fi; }
trap cleanup EXIT
check() { if [ "$2" = "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1: got [$2] want [$3]"; fails=$((fails+1)); fi; }

export HOME=$B/home GIT_CONFIG_GLOBAL=$B/gitconfig GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS GIT_DIR GIT_WORK_TREE
mkdir -p "$HOME" "$B/bin" "$B/stub" "$B/mut" "$B/lib"
git config --global user.email t@example.invalid; git config --global user.name t
git config --global init.defaultBranch main; git config --global advice.detachedHead false
export GIT_AUTHOR_DATE='2026-10-01T00:00:00Z' GIT_COMMITTER_DATE='2026-10-01T00:00:00Z'
W=$B/w; R=$W/root/Sylveste; J=$W/J; ST=$W/st

link_text() { local t; t=$(readlink -- "$1" && printf x) || return 1; t=${t%x}; printf '%s' "${t%?}"; }
dg() { if [ -L "$1" ]; then printf 'l:%s\n' "$(link_text "$1" | sha)"; elif [ -d "$1" ]; then echo d
  elif [ -f "$1" ] && [ -x "$1" ]; then printf 'x:%s\n' "$(sha < "$1")"; elif [ -f "$1" ]; then printf 'f:%s\n' "$(sha < "$1")"; else echo -; fi; }
files() { (cd "$1" && find . -path ./.git -prune -o \( -type f -o -type l \) -print | sed 's|^\./||' | sort); }
dmap() { local p; while IFS= read -r p; do printf '%s\t%s\n' "$(dg "$1/$p")" "$p"; done < "$2"; }
wr() { mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; }
g() { git -C "$R" "$@"; }
ckfp() {  # the checkout as the plan sees it, plus the marker's presence and bytes
  g symbolic-ref -q HEAD; g rev-parse HEAD; g ls-files -s | sha; g status --porcelain -uall
  files "$R" > "$B/ck.list"; dmap "$R" "$B/ck.list"
  g for-each-ref --format='%(refname) %(objectname)' refs/heads refs/tags; dg "$R/.git-autosync"; }
jfp() { (cd "$J" 2>/dev/null && find . -mindepth 1 \( -type f -o -type d \) | sort | while IFS= read -r p; do printf '%s %s\n' "$p" "$(dg "$p")"; done) | sha; }
lanerefs() { git --git-dir="$W/lane.git" for-each-ref --format='%(refname) %(objectname)'; }
snap() { rm -rf -- "${B:?}/tpl-${1:?}"; cp -a "$W" "$B/tpl-$1"; }
restore() { rm -rf -- "${W:?}"; cp -a "$B/tpl-$1" "$W"; }

# ---- stubs: the unit controller, journalctl, the lane library, the predictor, the report sender, the tracker
cat > "$B/bin/ctl" <<EOF
#!/bin/bash
# ctl stop|start|active UNIT : unit state is a file; starting the repair service writes the journal unless told not to
S=$ST; act=\$1; shift
for u in "\$@"; do case \$act in
  stop) rm -f "\$S/units/\$u" ;;
  active) [ -e "\$S/units/\$u" ] || exit 1 ;;
  start) if [ "\$u" = git-autosync-repair.service ]; then echo "start \$(date +%s)" >> "\$S/starts"
           [ -e "\$S/nojournal" ] || echo "1 autosync repo(s): 1 unchanged" > "\$S/journal.txt"
         else touch "\$S/units/\$u"; fi ;;
  esac; done
EOF
printf '#!/bin/bash\ncat %q 2>/dev/null; true\n' "$ST/journal.txt" > "$B/stub/journalctl"
cat > "$B/lib/autosync-lane.sh" <<EOF
# stub lane library: asl_resolve REPO [REMOTE] validates, asl_tip REPO REF reads the tip
asl_resolve() { ASL_REASON=; ASL_SLUG=fixture/lane; ASL_NAME=\$2
  [ ! -e "$ST/refuse-archive" ] || { ASL_REASON="not verified private"; return 1; }; }
asl_tip() { ASL_TIP=\$(git -C "\$1" ls-remote "\$ASL_NAME" "refs/heads/\$2" | cut -f1); }
EOF
cat > "$B/bin/pred" <<EOF
#!/bin/bash
S=$ST
case \$1 in
  server) echo "\$*" >> "\$S/pred-args"; echo "row 4"; echo "log fixture"
          if [ -e "\$S/pred-stop" ]; then echo "verdict STOP row 5 at \$6"; exit 3; fi; echo "verdict run" ;;
  verify) [ ! -e "\$S/pred-mismatch" ] || { echo "verify: mismatch"; exit 3; }; echo "verify: match" ;;
  *) exit 1 ;;
esac
EOF
cat > "$B/bin/tell" <<EOF
#!/bin/bash
echo "\$*" >> "$B/tell.log"; exit 0
EOF
chmod +x "$B/bin/ctl" "$B/stub/journalctl" "$B/bin/pred" "$B/bin/tell"
rec() { printf '{"_type":"issue","id":"%s","title":"%s","status":"open","priority":2,"issue_type":"task","created_at":"%s","updated_at":"%s"}\n' "$1" "$2" "$3" "$3"; }
rec fx-one one 2026-10-01T00:00:01Z > "$B/one.jsonl"
{ rec fx-two two 2026-10-01T00:00:02Z; cat "$B/one.jsonl"; } > "$B/trk.jsonl"
mkbd() { printf '#!/bin/bash\ncase "$1 ${2:-}" in "export -o") cp %q "$3" ;; *) echo "bd stub: unsupported: $*" >&2; exit 2 ;; esac\n' "$1" > "$B/bin/bd"; chmod +x "$B/bin/bd"; }
mkbd "$B/trk.jsonl"
mkdir -p "$B/x"; cp "$(command -v sleep)" "$B/x/bd"

# ---- fixture (the same shape as p1a-flush-test.sh): a clone at an old commit with local internal work, a lane holding the old tip
echo "== fixture"
mkdir -p "$W/root" "$ST/units"; git init -q --bare "$W/pub.git"; git init -q --bare "$W/lane.git"
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
wr "$R/internal/cu.md" 'cu uncommitted'; rm "$R/internal/gone.md"; chmod +x "$R/internal/mode.sh"; ln -s a.md "$R/internal/ln"
O=$(g rev-parse HEAD)
g push -q lane "$O:refs/heads/autosync/mA" || { echo "fixture: the lane push failed"; exit 1; }
mkdir -p "$J"; echo "$BASE" > "$J/base"; echo mA > "$J/host"; echo lane > "$J/lane-remote"; echo "$PR1" > "$J/pr1-head"
printf 'pr1\tdocs/sylveste-vision.md\nbeads-export\t.beads/issues.jsonl\nops-12a\tops/*\n' > "$J/dispositions"
printf 'internal/\ndocs/research/\n' > "$J/delete-list"
echo "mk is present for gate 0 on mA base ${BASE:0:12}" > "$B/confirm"
for u in git-autosync-repair.timer git-autosync-promote.timer; do touch "$ST/units/$u"; done
echo "  base $BASE, old $O; script under test $GW ($(sha < "$GW"))"
snap fx

PATHS="$B/stub:/usr/local/bin:/usr/bin:/bin"
wg() {  # run the wrapper under test (WG, default $GW) with the fixture's stubs
  env GATE0_ROOT="$R" GATE0_STATE_DIR="$W/state" GATE0_JOURNAL="$J" GATE0_PRESERVE_DIR="$W/pres" GATE0_NO_REEXEC=1 \
    GATE0_PATH="$PATHS" GATE0_BD="$B/bin/bd" GATE0_OPERATOR_HOME="$HOME" AUTOSYNC_LANE_LIB="$B/lib/autosync-lane.sh" \
    GATE0_TIMER_CTL="$B/bin/ctl" GATE0_CONFIRM_FILE="${GATE0_CONFIRM_FILE:-$B/confirm}" GATE0_PRED="$B/bin/pred" GATE0_CS="$CS" \
    GATE0_REPORT_TELL="$B/bin/tell" GATE0_REPORT_TITLE="fixture title" GATE0_JOURNAL_TRIES=0 GATE0_QUIESCE_WAIT=0 \
    GATE0_PAUSE_FILE="$B/nopause" "${WG:-$GW}" "$@"; }
nstarts() { [ -f "$ST/starts" ] && wc -l < "$ST/starts" || echo 0; }
active() { [ -e "$ST/units/$1" ] && echo yes || echo no; }
timers() { echo "$(active git-autosync-repair.timer)/$(active git-autosync-promote.timer)"; }
stepto() {  # PHASE... : bring a restored fixture to the state after the named phases
  local p; for p in "$@"; do WG= wg $p >> "$B/step.out" 2>&1 || { echo "  FAIL stepto $p"; tail -n 8 "$B/step.out"; fails=$((fails+1)); return 1; }; done; }

# ---- tests as functions of the wrapper under test, so the mutation controls run the same ones
t_hook() {  # an installed reference-transaction hook that is not on the reviewed list is a STOP, with nothing written
  restore fx; printf '#!/bin/sh\ntouch "$GIT_DIR/x"\n' > "$R/.git/hooks/reference-transaction"; chmod +x "$R/.git/hooks/reference-transaction"
  local c0 j0; c0=$(ckfp); j0=$(jfp)
  wg preflight > "$B/out.hook" 2>&1; HRC=$?
  [ "$HRC" = 3 ] && grep -q 'reference-transaction hook' "$B/out.hook" && [ ! -e "$J/p0" ] && [ "$(ckfp)" = "$c0" ] && [ "$(jfp)" = "$j0" ]; }
t_markerback() {  # capture refuses when the marker is back in the checkout: P1a does not run
  restore fx; stepto preflight freeze || return 1
  cp -p "$W/J/gate0-run/marker" "$R/.git-autosync"; local c0; c0=$(ckfp)
  wg capture > "$B/out.mb" 2>&1; MRC=$?
  [ "$MRC" = 3 ] && grep -q 'freeze no longer holds' "$B/out.mb" && [ ! -e "$J/cp" ] && [ ! -d "$J/capture" ] && [ "$(ckfp)" = "$c0" ]; }
t_verify() {  # a run that differs from the prediction leaves the marker aside and the timers stopped
  restore fx; stepto preflight freeze capture rollback || return 1
  touch "$ST/pred-mismatch"
  wg restart r0 > "$B/out.vf" 2>&1; VRC=$?
  [ "$VRC" = 3 ] && grep -q 'differs from the prediction' "$B/out.vf" && [ ! -e "$R/.git-autosync" ] && [ "$(timers)" = no/no ]; }

echo "== --check forms change nothing"
restore fx; c0=$(ckfp); j0=$(jfp); l0=$(lanerefs)
WG= wg --check > "$B/out" 2>&1; check "--check" "$?" 0
for ph in preflight freeze capture "restart r0"; do
  wg --check $ph > "$B/out.chk" 2>&1; rc=$?
  # before the journal has p0/p1-pre the later checks stop; they must still write nothing
  check "--check $ph: no write (exit $rc is 0 or 3)" "$([ $rc = 0 ] || [ $rc = 3 ] && echo ok)" ok
  check "--check $ph: checkout, journal, lane and units unchanged" "$(ckfp | sha)/$(jfp)/$(lanerefs | sha)/$(timers)" "$(echo "$c0" | sha)/$j0/$(echo "$l0" | sha)/yes/yes"; done
stepto preflight; c1=$(ckfp); j1=$(jfp)
wg --check freeze > "$B/out.chk" 2>&1; check "--check freeze after preflight" "$?" 0
check "--check freeze: nothing changed" "$(ckfp | sha)/$(jfp)/$(timers)" "$(echo "$c1" | sha)/$j1/yes/yes"
stepto freeze; c2=$(ckfp); j2=$(jfp); l2=$(lanerefs)
wg --check capture > "$B/out.chk" 2>&1; check "--check capture after freeze" "$?" 0
check "--check capture: checkout, journal and lane unchanged" "$(ckfp | sha)/$(jfp)/$(lanerefs | sha)" "$(echo "$c2" | sha)/$j2/$(echo "$l2" | sha)"

echo "== preflight"
restore fx; c0=$(ckfp); : > "$B/tell.log"
wg preflight > "$B/out" 2>&1; check "preflight exit" "$?" 0
check "preflight records J/p0 and the wrapper's record" "$([ -d "$J/p0" ] && [ -e "$J/gate0-run/preflight" ] && echo yes)" yes
check "preflight leaves the checkout alone" "$(ckfp | sha)" "$(echo "$c0" | sha)"
wg preflight > "$B/out" 2>&1; check "preflight is idempotent" "$?" 0
check "the sender was called with the title, result and step" "$(grep -c -- '--title fixture title .*--result ok --step preflight' "$B/tell.log")" 2
t_hook; check "hook refused: exit 3, no J/p0, nothing changed" "$HRC/$?" "3/0"
restore fx; printf '#!/bin/sh\ntrue\n' > "$R/.git/hooks/reference-transaction"; chmod +x "$R/.git/hooks/reference-transaction"
sha < "$R/.git/hooks/reference-transaction" > "$B/readonly-hooks"
GATE0_READONLY_HOOKS="$B/readonly-hooks" wg preflight > "$B/out" 2>&1; check "a reviewed read-only hook is accepted" "$?" 0
restore fx; touch "$ST/refuse-archive"; wg preflight > "$B/out" 2>&1; rc=$?
check "an unverified archive destination is refused (exit 3, no J/p0)" "$rc/$([ -d "$J/p0" ] && echo p0)" "3/"
restore fx; echo "$(printf '%040d' 1)" > "$J/base"; wg preflight > "$B/out" 2>&1; rc=$?
check "a base that is not origin/main is refused (exit 3, no J/p0)" "$rc/$([ -d "$J/p0" ] && echo p0)" "3/"
restore fx; rm "$J/dispositions"; wg preflight > "$B/out" 2>&1; check "a missing input is refused before any write (exit 1)" "$?" 1

echo "== freeze"
restore fx; wg freeze > "$B/out" 2>&1; check "freeze without preflight is refused (exit 1)" "$?" 1
stepto preflight
echo "wrong phrase" > "$B/confirm.bad"; GATE0_CONFIRM_FILE="$B/confirm.bad" wg freeze > "$B/out" 2>&1; rc=$?
check "a wrong presence phrase is refused (exit 1); timers untouched" "$rc/$(timers)" "1/yes/yes"
( cd "$R" && exec sleep 60 ) & BG=$!; sleep 0.3
wg freeze > "$B/out" 2>&1; rc=$?
check "an agent process in the checkout is a STOP; timers and marker untouched" "$rc/$(timers)/$([ -e "$R/.git-autosync" ] && echo marker)" "3/yes/yes/marker"
kill $BG; wait $BG 2>/dev/null; BG=
"$B/x/bd" 60 & BG=$!; sleep 0.3
wg freeze > "$B/out" 2>&1; rc=$?
check "a running bd is a STOP; timers and marker untouched" "$rc/$(timers)/$([ -e "$R/.git-autosync" ] && echo marker)" "3/yes/yes/marker"
kill $BG; wait $BG 2>/dev/null; BG=
M0=$(sha < "$R/.git-autosync")
wg freeze > "$B/out" 2>&1; check "freeze exit" "$?" 0
check "timers stopped, marker out of the checkout and kept byte for byte" "$(timers)/$([ -e "$R/.git-autosync" ] && echo marker)/$(sha < "$J/gate0-run/marker")" "no/no//$M0"
wg freeze > "$B/out" 2>&1; check "freeze holds across a re-run" "$?" 0
touch "$ST/units/git-autosync-promote.timer"; wg freeze > "$B/out" 2>&1; check "a re-enabled timer breaks the recorded freeze (exit 3)" "$?" 3

echo "== capture"
restore fx; stepto preflight
wg capture > "$B/out" 2>&1; check "capture without the freeze is a STOP (exit 3)" "$?" 3
check "the P1a journal is untouched" "$([ -e "$J/cp" ] && echo cp)" ""
stepto freeze
wg capture > "$B/out" 2>&1; check "capture exit" "$?" 0
check "P1a reached a1 and HEAD is the base" "$(cut -d' ' -f1 "$J/cp")/$(g rev-parse HEAD)" "a1/$BASE"
check "the tag resolves to the old tip" "$(g rev-parse "refs/tags/gate0/mA-$O")" "$O"
check "the archive branch is on the lane" "$(git --git-dir="$W/lane.git" rev-parse "refs/heads/archive/gate0/mA/$O")" "$O"
PD=$W/pres/mA-$O
check "the preservation copy holds the capture, byte for byte" "$(cd "$PD" && sha < main.bundle)/$(cd "$PD" && sha < wtree.tar)" "$(sha < "$J/capture/main.bundle")/$(sha < "$J/capture/wtree.tar")"
check "the marker stays out of the checkout" "$([ -e "$R/.git-autosync" ] && echo marker)" ""
ck=$(ckfp); wg capture > "$B/out" 2>&1; check "capture is idempotent" "$?" 0
check "...and changes nothing" "$(ckfp | sha)" "$(echo "$ck" | sha)"
echo x >> "$PD/main.bundle"; wg capture > "$B/out" 2>&1; rc=$?
check "...but rewrites a damaged preservation copy from the verified capture" "$rc/$(cd "$PD" && sha < main.bundle)" "0/$(sha < "$J/capture/main.bundle")"
t_markerback; check "marker back in the checkout: exit 3, P1a did not run, nothing changed" "$MRC/$?" "3/0"

echo "== rollback and restart r0"
restore fx; stepto preflight freeze capture
WG= wg restart r0 > "$B/out" 2>&1; check "restart r0 after P1a without R0a is a STOP (exit 3)" "$?" 3
check "...timers stopped, marker aside" "$(timers)/$([ -e "$R/.git-autosync" ] && echo marker)" "no/no/"
wg restart p10 > "$B/out" 2>&1; check "restart p10 is refused by the unfreeze gate (exit 3); the freeze stays" "$?/$(timers)" "3/no/no"
wg rollback > "$B/out" 2>&1; check "rollback (R0a) exit" "$?" 0
check "R0a restored the old tip at checkpoint a0r" "$(cut -d' ' -f1 "$J/cp")/$(g rev-parse HEAD)" "a0r/$O"
snap r0a
t_verify; check "a run that differs from the prediction: exit 3, marker aside, timers stopped" "$VRC/$?" "3/0"
restore r0a; touch "$ST/pred-stop"; wg restart r0 > "$B/out" 2>&1; rc=$?
check "a prediction of STOP starts nothing (exit 3)" "$rc/$(nstarts)/$([ -e "$R/.git-autosync" ] && echo marker)/$(timers)" "3/0//no/no"
restore r0a; touch "$ST/nojournal"; wg restart r0 > "$B/out" 2>&1; rc=$?
check "no '<n> autosync repo(s)' line is a STOP: marker aside, timers stopped" "$rc/$([ -e "$R/.git-autosync" ] && echo marker)/$(timers)" "3//no/no"
restore r0a; mkbd "$B/one.jsonl"; wg restart r0 > "$B/out" 2>&1; rc=$?
check "an export that does not dominate the old tip's records is a STOP before anything restarts" "$rc/$(nstarts)/$([ -e "$R/.git-autosync" ] && echo marker)/$(timers)" "3/0//no/no"
mkbd "$B/trk.jsonl"
restore r0a; M0=$(sha < "$J/gate0-run/marker"); wg restart r0 > "$B/out" 2>&1; check "restart r0 after R0a exit" "$?" 0
check "the predictor was asked for the a0r exit with the checkout and the host" "$(tail -n 1 "$ST/pred-args")" "server $R Sylveste mA a0r"
check "marker restored byte for byte, repair service started once, timers back" "$(sha < "$R/.git-autosync")/$(wc -l < "$ST/starts")/$(timers)" "$M0/1/yes/yes"
check "the restart is recorded" "$([ -e "$J/gate0-run/restarted-r0" ] && echo yes)" yes

echo "== mutation controls (each must be judged NOT fail-closed)"
mutate() {  # NAME SEDEXPR : a copy of the wrapper with one safeguard removed; WG names it
  sed "$2" "$GW" > "$B/mut/$1.sh"; chmod +x "$B/mut/$1.sh"
  cmp -s "$GW" "$B/mut/$1.sh" && { echo "  FAIL mutation $1 changed nothing"; fails=$((fails+1)); return 1; }
  cp "$HERE/cutover-steps.sh" "$B/mut/cutover-steps.sh"; return 0; }
mutate M1 's/|| stop "the marker is back in the checkout: the freeze no longer holds"/|| true/' &&
  { WG=$B/mut/M1.sh; t_markerback; r=$?; WG=; check "M1 (no marker check before capture) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M2 's/^  hook_check; archive_check; }/  archive_check; }/' &&
  { WG=$B/mut/M2.sh; t_hook; r=$?; WG=; check "M2 (no hook check) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M3 's/cat "\$LOGD\/verify.out"; move_marker_aside; stop "the run differs/cat "$LOGD\/verify.out"; stop "the run differs/' &&
  { WG=$B/mut/M3.sh; t_verify; r=$?; WG=; check "M3 (marker left in place after a mismatch) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }

if [ $fails = 0 ]; then echo "GATE0-RUN: PASS"; exit 0; else echo "GATE0-RUN: FAIL ($fails)"; exit 1; fi
