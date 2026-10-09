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
g() { GIT_OPTIONAL_LOCKS=0 git -C "$R" "$@"; }   # the test observes the checkout without refreshing its index
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
  stop) [ ! -e "\$S/failstop-\$u" ] || exit 1; rm -f "\$S/units/\$u" ;;
  active) [ ! -e "\$S/ctl-error" ] || exit 4; [ -e "\$S/units/\$u" ] || exit 3 ;;
  start) [ ! -e "\$S/failstart-\$u" ] || exit 1
         if [ "\$u" = git-autosync-repair.service ]; then echo "start \$(date +%s)" >> "\$S/starts"
           [ -e "\$S/nojournal" ] || echo "1 autosync repo(s): 1 unchanged" >> "\$S/jlog"
         else [ -e "\$S/lie-\$u" ] || touch "\$S/units/\$u"; [ ! -e "\$S/lockg" ] || chmod a-w "$J/gate0-run"; fi ;;
  esac; done
EOF
# journalctl: an append-only log whose cursor is the number of lines so far (--show-cursor), read back with --after-cursor
cat > "$B/stub/journalctl" <<EOF
#!/bin/bash
f=$ST/jlog; touch "\$f"
for a in "\$@"; do case \$a in
  --show-cursor) echo "-- cursor: \$(wc -l < "\$f" | tr -d ' ')"; exit 0 ;;
  --after-cursor=*) tail -n +\$(( \${a#--after-cursor=} + 1 )) "\$f"; exit 0 ;; esac; done
cat "\$f"
EOF
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
  server) echo "\$*" >> "\$S/pred-args"; echo "report=\${RESTART_REPORT:-unset}" >> "\$S/pred-env"; echo "row 4"; echo "log fixture"
          # the real predictor writes a delivery failure to stderr when its own report sender is on and empty
          if [ -e "\$S/pred-noise" ]; then echo "restart: report not delivered; it is /x:" >&2; fi
          if [ -e "\$S/pred-stop" ]; then echo "verdict STOP row 5 at \$6"; exit 3; fi; echo "verdict run" ;;
  clavain) echo "\$*" >> "\$S/pred-args"; echo "row 8"; echo "verdict run" ;;
  verify) ! grep -q 'report not delivered' "\$2" || { echo "verify: unknown line in the prediction"; exit 3; }
          [ ! -e "\$S/pred-tag" ] || git -C $R tag gate0/injected HEAD
          [ ! -e "\$S/pred-mismatch" ] || { echo "verify: mismatch"; exit 3; }; echo "verify: match" ;;
  *) exit 1 ;;
esac
EOF
cat > "$B/bin/tell" <<EOF
#!/bin/bash
echo "\$*" >> "$B/tell.log"; exit 0
EOF
# the wrapper refuses while any bd runs on the machine; the test must not depend on what else the host is running,
# so the process list the wrapper sees holds only the bd this test starts (its pid is written to $B/bdpid)
REALPS=$(command -v ps)
cat > "$B/stub/ps" <<EOF
#!/bin/bash
if [ "\$*" = "-A -o pid= -o comm=" ]; then [ ! -e "$B/ps-fail" ] || exit 1; $REALPS "\$@" | awk -v keep="\$(cat "$B/bdpid" 2>/dev/null)" '{ n = \$2; sub(/.*\//, "", n); if (n == "bd" && \$1 != keep) next; print }'
else exec $REALPS "\$@"; fi
EOF
# a listing that fails: used only when the test forces the lsof branch. With $B/lsof-partial it fails after printing the wrapper's own
# ancestors and nothing else, so a caller that ignores the exit status sees itself and no other process
cat > "$B/stub/lsof" <<EOF
#!/bin/bash
[ -e "$B/lsof-partial" ] || exit 1
p=\$PPID
while [ -n "\$p" ] && [ "\$p" -gt 1 ]; do printf 'p%s\ncfake\nn/nowhere\n' "\$p"; p=\$($REALPS -o ppid= -p "\$p" | tr -d ' '); done
exit 1
EOF
cat > "$B/bin/sweep" <<EOF
#!/bin/bash
touch "$ST/sweep-ran"; [ ! -e "$ST/sweep-fail" ] || exit 1; echo "drift fixture" > "$B/drift.txt"
EOF
REALGIT=$(command -v git)
cat > "$B/stub/git" <<EOF
#!/bin/bash
# the real git, except that reading the tracker file from a commit fails while $ST/failshow exists (an unreadable object)
if [ -e "$ST/failshow" ]; then case " \$* " in *" show "*":.beads/issues.jsonl"*) echo "fatal: bad object (stub)" >&2; exit 128 ;; esac; fi
exec $REALGIT "\$@"
EOF
chmod +x "$B/stub/git" "$B/bin/sweep" "$B/stub/lsof" "$B/stub/ps" "$B/bin/ctl" "$B/stub/journalctl" "$B/bin/pred" "$B/bin/tell"
rec() { printf '{"_type":"issue","id":"%s","title":"%s","status":"open","priority":2,"issue_type":"task","created_at":"%s","updated_at":"%s"}\n' "$1" "$2" "$3" "$3"; }
rec fx-one one 2026-10-01T00:00:01Z > "$B/one.jsonl"
{ rec fx-two two 2026-10-01T00:00:02Z; cat "$B/one.jsonl"; } > "$B/trk.jsonl"
mkbd() { printf '#!/bin/bash\npwd -P >> %q\ncase "$1 ${2:-}" in "export -o") cp %q "$3" ;; *) echo "bd stub: unsupported: $*" >&2; exit 2 ;; esac\n' "$B/bd-cwd" "$1" > "$B/bin/bd"; chmod +x "$B/bin/bd"; }
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
hostuids() {  # every account that owns a process on this host: the host may run processes whose working directory this account cannot read
  # (a same-account tailscale ssh child is one), and the fixture must not depend on them. Only unreadable processes are exempted; readable ones are still examined
  stat -c %u /proc/[0-9]* 2>/dev/null | sort -u | tr '\n' ' '; }
wg() {  # run the wrapper under test (WG, default $GW) with the fixture's stubs
  env GATE0_UNINSPECTABLE_UIDS="$(hostuids)" GATE0_ROOT="$R" GATE0_STATE_DIR="${T_STATE:-$W/state}" GATE0_JOURNAL="${T_JOURNAL:-$J}" GATE0_PRESERVE_DIR="${T_PRES:-$W/pres}" GATE0_NO_REEXEC=1 \
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

t_dirty() {  # a dirty tracked path is only counted, never run as a command (the wrapper started inside the checkout)
  restore fx; rm -f "$B/dirty-ran"; printf '#!/bin/sh\ntouch %q\n' "$B/dirty-ran" > "$R/.beads/issues.jsonl"; chmod +x "$R/.beads/issues.jsonl"
  ( cd "$R" && wg preflight > "$B/out.dirty" 2>&1 ); [ ! -e "$B/dirty-ran" ]; }
t_hookfetch() {  # the hook refusal comes before the fetch: when origin gained a branch, a refused hook has not run
  restore fx; rm -f "$B/hook-ran"; git -C "$SD" push -q origin main:refs/heads/newbr
  printf '#!/bin/sh\ntouch %q\n' "$B/hook-ran" > "$R/.git/hooks/reference-transaction"; chmod +x "$R/.git/hooks/reference-transaction"
  wg preflight > "$B/out.hf" 2>&1; HFRC=$?; [ "$HFRC" = 3 ] && [ ! -e "$B/hook-ran" ]; }
t_noise() {  # predictor stderr (and its own report sender) must not reach the prediction file the verifier reads
  restore r0a; touch "$ST/pred-noise"; rm -f "$ST/pred-env"
  wg restart r0 > "$B/out.noise" 2>&1; NRC=$?; [ "$NRC" = 0 ] && [ "$(tail -n 1 "$ST/pred-env")" = report=0 ]; }
t_agentre() {  # an agent that resumed after the freeze is caught again before P1a
  restore fx; stepto preflight freeze || return 1
  ( cd "$R" && exec sleep 60 ) & BG=$!; sleep 0.3
  wg capture > "$B/out.ar" 2>&1; ARC=$?; kill $BG 2>/dev/null; wait $BG 2>/dev/null; BG=
  [ "$ARC" = 3 ] && grep -q 'agent process' "$B/out.ar" && [ ! -e "$J/cp" ] && [ ! -d "$J/capture" ]; }
t_unitserr() {  # a unit controller error is not proof that a unit is inactive
  restore fx; stepto preflight freeze || return 1
  touch "$ST/ctl-error"; wg capture > "$B/out.ue" 2>&1; URC=$?; rm -f "$ST/ctl-error"
  [ "$URC" = 3 ] && grep -q 'cannot establish whether' "$B/out.ue" && [ ! -e "$J/cp" ] && [ ! -d "$J/capture" ]; }
t_cleanup() {  # a failed restart leaves the frozen state: marker aside, every timer of the attempt stopped
  restore r0a; touch "$ST/failstart-git-autosync-promote.timer"
  wg restart r0 > "$B/out.cl1" 2>&1; C1=$?; C1S="$([ -e "$R/.git-autosync" ] && echo marker)/$(timers)"
  restore r0a; touch "$ST/pred-tag"
  wg restart r0 > "$B/out.cl2" 2>&1; C2=$?; C2S="$([ -e "$R/.git-autosync" ] && echo marker)/$(timers)"
  [ "$C1/$C1S" = "3//no/no" ] && [ "$C2/$C2S" = "3//no/no" ]; }
t_confine() {  # the state, journal and preservation directories are checked by physical path before anything is created
  restore fx; ln -s "$R" "$B/alias" 2>/dev/null; local r1 r2 r3 r4
  T_STATE="$R/st" wg --check preflight > "$B/out.cf" 2>&1; r1=$?
  T_JOURNAL="$R/.git/jj" wg --check preflight >> "$B/out.cf" 2>&1; r2=$?
  T_JOURNAL="$B/alias/jj" wg --check preflight >> "$B/out.cf" 2>&1; r3=$?
  T_PRES="$B/alias/pp" wg preflight >> "$B/out.cf" 2>&1; r4=$?
  CFR="$r1$r2$r3$r4"; [ "$CFR" = 1111 ] && [ ! -e "$R/st" ] && [ ! -e "$R/.git/jj" ] && [ ! -e "$R/jj" ] && [ ! -e "$R/pp" ] && [ ! -d "$J/p0" ]; }
t_locks() {  # --check never rewrites the index, even when a tracked file's timestamp changed
  restore fx; touch -d 2001-01-01 "$R/README.md"; local i0; i0=$(sha < "$R/.git/index")
  wg --check preflight > "$B/out.lk" 2>&1; wg --check capture >> "$B/out.lk" 2>&1; [ "$(sha < "$R/.git/index")" = "$i0" ]; }
t_self() {  # freeze started from inside the checkout does not report the wrapper's own subshell as an agent
  restore fx; stepto preflight || return 1
  ( cd "$R" && wg freeze > "$B/out.self" 2>&1 ); SRC=$?; [ "$SRC" = 0 ]; }

t_cwd() {  # bd and the steps find the tracker from the working directory: the checkout's, whatever the caller's
  restore fx; stepto preflight freeze || return 1; rm -f "$B/bd-cwd"
  ( cd "$B" && wg capture > "$B/out.cwd" 2>&1 ); local c1=$?
  restore r0a; ( cd "$B" && wg restart r0 >> "$B/out.cwd" 2>&1 ); local c2=$?
  CWR="$c1$c2/$(sort -u "$B/bd-cwd" 2>/dev/null | paste -sd, -)"; [ "$CWR" = "00/$R" ]; }
t_listfail() {  # a process listing that fails is not an empty one: no agent and no bd can be ruled out, so STOP
  restore fx; stepto preflight || return 1
  touch "$B/ps-fail"; wg freeze > "$B/out.lf" 2>&1; LF1=$?; rm -f "$B/ps-fail"
  GATE0_PROCFS="$B/no-procfs" wg freeze >> "$B/out.lf" 2>&1; LF2=$?   # no /proc: the lsof branch, whose stub fails
  [ "$LF1/$LF2/$(timers)" = "3/3/yes/yes" ] && grep -q 'cannot read the process table' "$B/out.lf" && grep -q 'cannot list the processes' "$B/out.lf"; }
t_symlinks() {  # children of the state, journal and preservation directories are checked as well as the directories
  restore fx; local c0 r1 r2 r3 k; c0=$(ckfp)
  mkdir -p "$W/state"; ln -s "$R" "$W/state/logs"
  wg --check preflight > "$B/out.sl" 2>&1; r1=$?
  rm -f "$W/state/logs"; ln -s "$R" "$J/gate0-run"
  wg preflight >> "$B/out.sl" 2>&1; r2=$?
  SLK=$([ "$(ckfp)" = "$c0" ] && echo same); rm -f "$J/gate0-run"
  restore fx; stepto preflight freeze || return 1
  mkdir -p "$W/pres"; ln -s "$R" "$W/pres/mA-$O"; k=$(ckfp)
  wg capture >> "$B/out.sl" 2>&1; r3=$?
  SLR="$r1$r2$r3"; [ "$SLR" = 113 ] && [ "$(ckfp)" = "$k" ] && [ ! -e "$J/cp" ] && [ "$SLK" = same ] && [ ! -e "$R/main.bundle" ]; }
t_restart_idem() {  # a repeated restart runs nothing; a restart or rollback needs a live freeze
  restore r0a; wg restart r0 > "$B/out.ri" 2>&1; RI1=$?
  wg restart r0 >> "$B/out.ri" 2>&1; RI2=$?; RIS=$(nstarts)
  restore r0a; touch "$ST/units/git-autosync-promote.timer"
  wg restart r0 >> "$B/out.ri" 2>&1; RI3=$?; RIN=$(nstarts)
  restore fx; stepto preflight freeze capture || return 1
  touch "$ST/units/git-autosync-promote.timer"
  wg rollback >> "$B/out.ri" 2>&1; RI4=$?; RIC=$(cut -d' ' -f1 "$J/cp")
  [ "$RI1/$RI2/$RIS/$RI3/$RIN/$RI4/$RIC" = "0/0/1/3/0/3/a1" ]; }
t_putfail() {  # the restart succeeded but could not be recorded: the frozen state is restored, not left half-restarted
  restore r0a; touch "$ST/lockg"
  wg restart r0 > "$B/out.pf" 2>&1; PFR=$?; chmod u+w "$J/gate0-run"; rm -f "$ST/lockg"
  PFS="$([ -e "$R/.git-autosync" ] && echo marker)/$(timers)/$([ -e "$J/gate0-run/restarted-r0" ] && echo recorded)"
  [ "$PFR/$PFS" = "3//no/no/" ]; }

t_lsofpartial() {  # an lsof that fails after listing the wrapper itself is not a clean listing: a process in the checkout may be missing
  restore fx; stepto preflight || return 1
  ( cd "$R" && exec sleep 60 ) & BG=$!; sleep 0.3; touch "$B/lsof-partial"
  GATE0_PROCFS="$B/no-procfs" wg freeze > "$B/out.lp" 2>&1; LPR=$?
  kill $BG 2>/dev/null; wait $BG 2>/dev/null; BG=; rm -f "$B/lsof-partial"
  [ "$LPR/$(timers)" = "3/yes/yes" ] && grep -q 'cannot list the processes' "$B/out.lp"; }
t_clavmarker() {  # Clavain restart: the marker put back must be the one the freeze record names, as on the server
  restore r0a; rm -f "$B/drift.txt"
  GATE0_MACHINE=clavain GATE0_SWEEP="$B/bin/sweep" GATE0_DRIFT_REPORT="$B/drift.txt" wg restart r0 > "$B/out.cm" 2>&1; CM0=$?
  CM0S="$([ -e "$ST/sweep-ran" ] && echo swept)/$(timers)"
  restore r0a; rm -f "$B/drift.txt"; printf 'EXTRA=1\n' >> "$J/gate0-run/marker"
  GATE0_MACHINE=clavain GATE0_SWEEP="$B/bin/sweep" GATE0_DRIFT_REPORT="$B/drift.txt" wg restart r0 >> "$B/out.cm" 2>&1; CM1=$?
  CM1S="$([ -e "$R/.git-autosync" ] && echo marker)/$([ -e "$ST/sweep-ran" ] && echo swept)/$(timers)/$([ -e "$J/gate0-run/restarted-r0" ] && echo recorded)"
  [ "$CM0/$CM0S/$CM1/$CM1S" = "0/swept/yes/yes/3///no/no/" ]; }
t_startlie() {  # a unit controller that returns 0 from start while the timer stays inactive is not a restart
  restore r0a; touch "$ST/lie-git-autosync-promote.timer"
  wg restart r0 > "$B/out.sl2" 2>&1; SLIE=$?
  SLIS="$([ -e "$R/.git-autosync" ] && echo marker)/$(timers)/$([ -e "$J/gate0-run/restarted-r0" ] && echo recorded)"
  [ "$SLIE/$SLIS" = "3//no/no/" ] && grep -q 'not active after its start' "$B/out.sl2"; }
t_checkreport() {  # --check preflight and --check capture write nothing even when a report directory is inherited from the environment
  restore fx; stepto preflight freeze || return 1
  local c0 j0; c0=$(ckfp); j0=$(jfp)
  CUTOVER_LOG_DIR="$J/leak" wg --check preflight > "$B/out.cr" 2>&1; CR1=$?
  CUTOVER_LOG_DIR="$R/leak" wg --check preflight >> "$B/out.cr" 2>&1; CR2=$?
  CUTOVER_LOG_DIR="$R/leak" wg --check capture >> "$B/out.cr" 2>&1; CR3=$?
  [ "$CR1/$CR2/$CR3" = 0/0/0 ] && [ ! -e "$J/leak" ] && [ ! -e "$R/leak" ] && [ "$(ckfp)" = "$c0" ] && [ "$(jfp)" = "$j0" ]; }
t_refreeze() {  # a new freeze after a completed restart is a new attempt: timers and marker stopped again, the restart record cleared
  restore r0a; wg restart r0 > "$B/out.rf" 2>&1; RF1=$?
  wg freeze >> "$B/out.rf" 2>&1; RF2=$?
  RFS="$(timers)/$([ -e "$R/.git-autosync" ] && echo marker)/$([ -e "$J/gate0-run/restarted-r0" ] && echo recorded)/$(grep -c '^timer ' "$J/gate0-run/freeze")"
  [ "$RF1/$RF2/$RFS" = "0/0/no/no///2" ]; }

t_unreadable() {  # a live process whose working directory cannot be read is a STOP, unless it is a zombie or its account is declared uninspectable
  local pf=$B/pf h=$B/procfix.sh me o1 o2 o3 o4 r1 r2 r3 r4; me=$(id -u)
  { echo 'ROOT=$1; LOG=$2; mkdir -p "$GATE0_PROCFS/$$"; ln -sfn / "$GATE0_PROCFS/$$/cwd"'   # the harness's own entry: the listing must show it
    sed -n '/^under_self() {/,/^bd_writers() {/{/^bd_writers() {/!p;}' "${WG:-$GW}"; echo 'agents_in_root; echo "rc=$?"'; } > "$h"
  hr() { rm -f -- "$B/unr.log"; env GATE0_PROCFS="$pf" GATE0_UNINSPECTABLE_UIDS="$1" bash "$h" "$R" "$B/unr.log" 2>&1; }
  rm -rf -- "${pf:?}"; mkdir -p "$pf/self" "$pf/424242"; printf 'State:\tS (sleeping)\n' > "$pf/424242/status"   # no cwd entry: unreadable
  o1=$(hr ""); r1=$(printf '%s\n' "$o1" | sed -n 's/^rc=//p')
  o2=$(hr "$me"); r2=$(printf '%s\n' "$o2" | sed -n 's/^rc=//p')
  printf 'State:\tZ (zombie)\n' > "$pf/424242/status"; o3=$(hr ""); r3=$(printf '%s\n' "$o3" | sed -n 's/^rc=//p')
  printf 'State:\tS (sleeping)\n' > "$pf/424242/status"; mkdir -p "$pf/424243"; ln -s "$R" "$pf/424243/cwd"; echo agentx > "$pf/424243/comm"
  o4=$(hr "$me"); r4=$(printf '%s\n' "$o4" | grep -c '^424243 agentx$')
  UNR="$r1/$r2/$r3/$r4"; [ "$UNR" = 2/0/0/1 ] && printf '%s\n' "$o1" | grep -q "pid 424242 (uid $me) is live and its working directory cannot be read"; }
t_failstop() {  # a freeze whose stop fails midway has still stopped some timers: a repeat must keep them in the restart set
  restore fx; stepto preflight || return 1
  touch "$ST/failstop-git-autosync-promote.timer"; wg freeze > "$B/out.fs" 2>&1; FS1=$?; rm -f "$ST/failstop-git-autosync-promote.timer"
  FS1S=$(timers); wg freeze >> "$B/out.fs" 2>&1; FS2=$?
  FSS="$FS1/$FS1S/$FS2/$(timers)/$(grep -c '^timer ' "$J/gate0-run/freeze")/$([ -e "$J/gate0-run/freeze-intent" ] && echo intent)"
  [ "$FSS" = "3/no/yes/0/no/no/2/" ]; }
t_staledrift() {  # Clavain restart: only a drift report this sweep wrote is evidence; an earlier one is set aside and put back as found
  restore r0a; echo "old drift" > "$B/drift.txt"; touch "$ST/sweep-fail"
  GATE0_MACHINE=clavain GATE0_SWEEP="$B/bin/sweep" GATE0_DRIFT_REPORT="$B/drift.txt" wg restart r0 > "$B/out.sd" 2>&1; SD1=$?
  SD1S="$(cat "$B/drift.txt" 2>/dev/null)/$([ -e "$R/.git-autosync" ] && echo marker)/$(timers)"
  restore r0a; echo "old drift" > "$B/drift.txt"
  GATE0_MACHINE=clavain GATE0_SWEEP="$B/bin/sweep" GATE0_DRIFT_REPORT="$B/drift.txt" wg restart r0 >> "$B/out.sd" 2>&1; SD2=$?
  SDS="$SD1/$SD1S/$SD2/$(cat "$B/drift.txt" 2>/dev/null)"
  [ "$SDS" = "3/old drift//no/no/0/drift fixture" ] && grep -q 'the sweep wrote no new drift report' "$B/out.sd"; }
t_unconfirmed() {  # a stop the wrapper cannot confirm in cleanup is said so, with the units named
  restore r0a; touch "$ST/failstart-git-autosync-promote.timer" "$ST/failstop-git-autosync-repair.timer"
  wg restart r0 > "$B/out.uc" 2>&1; UC=$?; rm -f "$ST/failstop-git-autosync-repair.timer"
  UCS="$UC/$(timers)/$([ -e "$R/.git-autosync" ] && echo marker)"
  [ "$UCS" = "3/yes/no/" ] && grep -q 'UNCONFIRMED: these units are not confirmed stopped: git-autosync-repair.timer' "$B/out.uc"; }

t_refreezecrash() {  # a crash while a new freeze clears the earlier attempt's records must not lose the restart set, at either point
  local pt pat crash=$B/mut/crash.sh rc rc2 n left; RZS=
  for pt in restarted intent; do
    case $pt in restarted) pat='^  rm -f -- "\$G"\/restarted-\*' ;; intent) pat='^  rm -f -- "\$G\/freeze-intent"' ;; esac
    sed "/$pat/i exit 9" "${WG:-$GW}" > "$crash"; chmod +x "$crash"; cp "$HERE/cutover-steps.sh" "$B/mut/cutover-steps.sh"
    cmp -s "${WG:-$GW}" "$crash" && { echo "  FAIL crash copy for $pt changed nothing"; return 1; }
    restore r0a; wg restart r0 > "$B/out.rz" 2>&1 || return 1
    WG=$crash wg freeze >> "$B/out.rz" 2>&1; rc=$?
    wg freeze >> "$B/out.rz" 2>&1; rc2=$?
    n=$(grep -c '^timer ' "$J/gate0-run/freeze" 2>/dev/null)
    left=$([ -e "$J/gate0-run/restarted-r0" ] && echo restarted; [ -e "$J/gate0-run/freeze-intent" ] && echo intent)
    RZS="$RZS$rc/$rc2/$n/$left/"
  done
  [ "$RZS" = "9/0/2//9/0/2//" ]; }
t_reconcileread() {  # a tracker file that cannot be read from a commit that lists it is a STOP, not an empty file
  restore r0a; touch "$ST/failshow"
  wg restart r0 > "$B/out.rr" 2>&1; RRC=$?; rm -f "$ST/failshow"
  RRS="$([ -e "$R/.git-autosync" ] && echo marker)/$(timers)/$(nstarts)"
  [ "$RRC/$RRS" = "3//no/no/0" ] && grep -q 'cannot read .beads/issues.jsonl at' "$B/out.rr"; }
t_stalejournal() {  # lines of an earlier run in the journal are not this run's evidence
  restore r0a; echo "1 autosync repo(s): 1 unchanged" >> "$ST/jlog"; touch "$ST/nojournal"
  wg restart r0 > "$B/out.sj" 2>&1; SJC=$?
  SJS="$([ -e "$R/.git-autosync" ] && echo marker)/$(timers)"
  [ "$SJC/$SJS" = "3//no/no" ]; }
t_holdsbail() {  # a recorded restart whose state no longer holds is undone like any failed restart: timers stopped, marker aside, record gone
  restore r0a; wg restart r0 > "$B/out.hb" 2>&1 || return 1
  rm -f "$ST/units/git-autosync-promote.timer"
  wg restart r0 >> "$B/out.hb" 2>&1; HBC=$?
  HBS="$([ -e "$R/.git-autosync" ] && echo marker)/$(timers)/$([ -e "$J/gate0-run/restarted-r0" ] && echo recorded)"
  [ "$HBC/$HBS" = "3//no/no/" ]; }

t_holdsunknown() {  # a recorded restart whose timer state cannot be read is undone too, with the unconfirmed readback said
  restore r0a; wg restart r0 > "$B/out.hu" 2>&1 || return 1
  touch "$ST/ctl-error"; wg restart r0 >> "$B/out.hu" 2>&1; HUC=$?; rm -f "$ST/ctl-error"
  HUS="$([ -e "$R/.git-autosync" ] && echo marker)/$(timers)/$([ -e "$J/gate0-run/restarted-r0" ] && echo recorded)"
  [ "$HUC/$HUS" = "3//no/no/" ] && grep -q 'UNCONFIRMED: these units are not confirmed stopped' "$B/out.hu"; }
t_holdsmarker() {  # a recorded restart whose marker bytes changed is undone too: the changed bytes are kept beside the record and removed from the checkout
  local k
  restore r0a; wg restart r0 > "$B/out.hm" 2>&1 || return 1
  echo "LANE=changed-by-someone" >> "$R/.git-autosync"; cp "$R/.git-autosync" "$B/hm.changed"
  wg restart r0 >> "$B/out.hm" 2>&1; HMC=$?
  k=$(ls "$J/gate0-run"/marker.unexpected.* 2>/dev/null | wc -l)
  HMS="$([ -e "$R/.git-autosync" ] && echo marker)/$(timers)/$([ -e "$J/gate0-run/restarted-r0" ] && echo recorded)/$k"
  [ "$HMC/$HMS" = "3//no/no//1" ] && cmp -s "$B/hm.changed" "$J/gate0-run"/marker.unexpected.*; }

t_restartcrash() {  # a restart that ends after it restored the marker and started the service or a timer, before its completion record, is found and undone by the next restart
  local pt pat crash=$B/mut/crash.sh rc rc2 rc3 f; RCS=
  for pt in service timer; do
    case $pt in service) pat='/^  units start "\$REPAIR_SVC"/i exit 9' ;; timer) pat='/^    units start "\$u" || rbail "cannot re-enable/a exit 9' ;; esac
    sed "$pat" "${WG:-$GW}" > "$crash"; chmod +x "$crash"; cp "$HERE/cutover-steps.sh" "$B/mut/cutover-steps.sh"
    cmp -s "${WG:-$GW}" "$crash" && { echo "  FAIL crash copy for $pt changed nothing"; return 1; }
    restore r0a; WG=$crash wg restart r0 > "$B/out.rc" 2>&1; rc=$?
    f="$([ -e "$R/.git-autosync" ] && echo marker)/$(timers)"
    wg restart r0 >> "$B/out.rc" 2>&1; rc2=$?
    f="$f/$rc2/$([ -e "$R/.git-autosync" ] && echo marker)/$(timers)/$(ls "$J/gate0-run" | grep -c '^restart')"
    wg restart r0 >> "$B/out.rc" 2>&1; rc3=$?
    RCS="$RCS$rc/$f/$rc3/$(timers)/$([ -e "$J/gate0-run/restarted-r0" ] && echo recorded);"
  done
  [ "$RCS" = "9/marker/no/no/3//no/no/0/0/yes/yes/recorded;9/marker/yes/no/3//no/no/0/0/yes/yes/recorded;" ]; }
t_holdsnone() {  # Clavain row 8 (no marker) is recorded; a marker that appears afterwards is undone like any state the record does not describe, its bytes kept
  local k; restore r0a; rm -f "$B/drift.txt"; rm -f "$J/gate0-run/marker"; rm -f "$R/.git-autosync"
  sed -i 's/^marker .*/marker none/' "$J/gate0-run/freeze"
  GATE0_MACHINE=clavain GATE0_SWEEP="$B/bin/sweep" GATE0_DRIFT_REPORT="$B/drift.txt" wg restart r0 > "$B/out.hn" 2>&1; HN0=$?
  HN0S="$([ -e "$J/gate0-run/restarted-r0" ] && echo recorded)/$(timers)"
  printf 'LANE=1\n' > "$R/.git-autosync"
  GATE0_MACHINE=clavain GATE0_SWEEP="$B/bin/sweep" GATE0_DRIFT_REPORT="$B/drift.txt" wg restart r0 >> "$B/out.hn" 2>&1; HN1=$?
  k=$(ls "$J/gate0-run"/marker.unexpected.* 2>/dev/null | wc -l)
  HN1S="$([ -e "$R/.git-autosync" ] && echo marker)/$(timers)/$([ -e "$J/gate0-run/restarted-r0" ] && echo recorded)/$k/$([ -e "$J/gate0-run/marker" ] && echo marker-record)"
  [ "$HN0/$HN0S/$HN1/$HN1S" = "0/recorded/yes/yes/3//no/no//1/" ]; }

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
"$B/x/bd" 60 & BG=$!; echo $BG > "$B/bdpid"; sleep 0.3
wg freeze > "$B/out" 2>&1; rc=$?
check "a running bd is a STOP; timers and marker untouched" "$rc/$(timers)/$([ -e "$R/.git-autosync" ] && echo marker)" "3/yes/yes/marker"
kill $BG; wait $BG 2>/dev/null; BG=; rm -f "$B/bdpid"
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

echo "== review fixes"
t_dirty; check "a dirty tracked executable is counted, never run (wrapper started inside the checkout)" "$?" 0
t_hookfetch; check "a refused hook has not run on the fetch: exit 3, hook untouched" "$HFRC/$?" "3/0"
t_noise; check "predictor stderr and its own report sender stay out of the prediction: restart exit 0, report off" "$NRC/$?" "0/0"
t_agentre; check "an agent that resumed after the freeze is a STOP at capture: P1a did not run" "$ARC/$?" "3/0"
t_unitserr; check "a unit controller error is a STOP, not 'inactive': P1a did not run" "$URC/$?" "3/0"
t_cleanup; check "a failed restart (timer start, or a differing run) leaves marker aside and timers stopped" "$C1,$C2/$?" "3,3/0"
t_confine; check "state, journal and preservation inside the checkout (also through a symlink) are refused, nothing created" "$CFR/$?" "1111/0"
t_locks; check "--check leaves the index bytes alone when a tracked file's timestamp changed" "$?" 0
t_self; check "freeze from inside the checkout does not count the wrapper's own processes as agents" "$SRC/$?" "0/0"
t_cwd; check "bd and the steps run in the checkout whatever the caller's directory: capture and restart exit 0" "$CWR/$?" "00/$R/0"
t_listfail; check "a failing ps or lsof is a STOP at freeze (exit 3), timers untouched" "$LF1/$LF2/$?" "3/3/0"
t_symlinks; check "a symlinked logs/, gate0-run/ or preservation child is refused (1, 1, STOP 3); nothing written into the checkout" "$SLR/$?" "113/0"
t_restart_idem; check "restart twice runs once; restart or rollback without a live freeze is a STOP" "$RI1/$RI2/$RIS/$RI3/$RIN/$RI4/$RIC/$?" "0/0/1/3/0/3/a1/0"
t_putfail; check "a restart that cannot be recorded: exit 3, marker aside, timers stopped, no record" "$PFR/$PFS/$?" "3//no/no//0"
t_lsofpartial; check "an lsof that fails after listing the wrapper is a STOP at freeze (exit 3), timers untouched" "$LPR/$?" "3/0"
t_clavmarker; check "Clavain restart: the unchanged marker restarts and sweeps; a changed one is a STOP before any sweep, marker aside, timers stopped" "$CM0/$CM0S/$CM1/$CM1S/$?" "0/swept/yes/yes/3///no/no//0"
t_startlie; check "a start that returns 0 with the timer still inactive is a STOP: marker aside, timers stopped, no record" "$SLIE/$SLIS/$?" "3//no/no//0"
t_checkreport; check "--check preflight and capture with an inherited report directory write nothing" "$CR1/$CR2/$CR3/$?" "0/0/0/0"
t_refreeze; check "freeze after a completed restart re-freezes: timers and marker out, restart record cleared, both timers recorded" "$RF1/$RF2/$RFS/$?" "0/0/no/no///2/0"

t_unreadable; check "a live process with an unreadable working directory is a STOP; a zombie, or an account declared uninspectable, is not; a readable agent is still found" "$UNR/$?" "2/0/0/1/0"
t_failstop; check "a freeze whose stop failed midway: the repeat keeps the timer already stopped in the restart set, then holds" "$FSS/$?" "3/no/yes/0/no/no/2//0"
t_staledrift; check "Clavain: a sweep that writes no new drift report is a STOP (the earlier report is put back); a fresh one is accepted" "$SDS/$?" "3/old drift//no/no/0/drift fixture/0"
t_unconfirmed; check "a cleanup stop that cannot be confirmed is reported with the unit named; the marker is still aside" "$UCS/$?" "3/yes/no//0"
t_refreezecrash; check "a crash while a new freeze clears the earlier records loses nothing at either point: the repeat holds both timers" "$RZS/$?" "9/0/2//9/0/2///0"
t_reconcileread; check "a tracker file that cannot be read from a commit that lists it is a STOP: marker aside, timers stopped, nothing started" "$RRC/$RRS/$?" "3//no/no/0/0"
t_stalejournal; check "a journal that holds only an earlier run's summary line is not this run's evidence: STOP, marker aside, timers stopped" "$SJC/$SJS/$?" "3//no/no/0"
t_holdsbail; check "a recorded restart whose timer is no longer active is undone: timers stopped, marker aside, record removed" "$HBC/$HBS/$?" "3//no/no//0"
t_holdsunknown; check "a recorded restart whose timer state cannot be read is undone: timers stopped, marker aside, record removed, UNCONFIRMED said" "$HUC/$HUS/$?" "3//no/no//0"
t_holdsmarker; check "a recorded restart whose marker bytes changed is undone: the changed bytes kept beside the record, none left in the checkout" "$HMC/$HMS/$?" "3//no/no//1/0"
t_restartcrash; check "a restart cut off after the marker/service/first timer, before its record: the next restart undoes it (timers stopped, marker aside, attempt closed), the one after runs" "$RCS/$?" "9/marker/no/no/3//no/no/0/0/yes/yes/recorded;9/marker/yes/no/3//no/no/0/0/yes/yes/recorded;/0"
t_holdsnone; check "a recorded no-marker restart: a marker that appears afterwards is undone, its bytes kept, no marker record made" "$HN0/$HN0S/$HN1/$HN1S/$?" "0/recorded/yes/yes/3//no/no//1//0"

echo "== mutation controls (each must be judged NOT fail-closed)"
mutate() {  # NAME SEDEXPR : a copy of the wrapper with one safeguard removed; WG names it
  sed "$2" "$GW" > "$B/mut/$1.sh"; chmod +x "$B/mut/$1.sh"
  cmp -s "$GW" "$B/mut/$1.sh" && { echo "  FAIL mutation $1 changed nothing"; fails=$((fails+1)); return 1; }
  cp "$HERE/cutover-steps.sh" "$B/mut/cutover-steps.sh"; return 0; }
mutate M1 's/|| stop "the marker is back in the checkout: the freeze no longer holds"/|| true/' &&
  { WG=$B/mut/M1.sh; t_markerback; r=$?; WG=; check "M1 (no marker check before capture) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M2 's/^  hook_check   # first:.*/  :/' &&
  { WG=$B/mut/M2.sh; t_hook; r=$?; WG=; check "M2 (no hook check) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M3 's/rbail "the run differs/stop "the run differs/' &&
  { WG=$B/mut/M3.sh; t_verify; r=$?; WG=; check "M3 (marker left in place after a mismatch) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }

mutate M4 's/^  hook_check   # first:.*/  :/; s/^  archive_check; }$/  hook_check; archive_check; }/' &&
  { WG=$B/mut/M4.sh; t_hookfetch; r=$?; WG=; check "M4 (hook check after the fetch) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M5 's/\*) stop "cannot establish whether \$1 is active: the unit controller gave an error" ;; esac; }/*) return 1 ;; esac; }/' &&
  { WG=$B/mut/M5.sh; t_unitserr; r=$?; WG=; check "M5 (controller error read as inactive) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M6 's/^  move_marker_aside force; \[ -n /  [ -n /' &&
  { WG=$B/mut/M6.sh; t_cleanup; r=$?; WG=; check "M6 (failed restart leaves the marker in place) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M7 's/under_self "\$p" || //g' &&
  { WG=$B/mut/M7.sh; t_self; r=$?; WG=; check "M7 (own processes counted as agents) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M8 's/2> "\$pred.err"/2>\&1/' &&
  { WG=$B/mut/M8.sh; t_noise; r=$?; WG=; check "M8 (predictor stderr in the prediction) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M9 's/^  a=\$(agents_in_root) || stop "cannot list the processes (lsof or \/proc): the freeze cannot be confirmed"/  a=/' &&
  { WG=$B/mut/M9.sh; t_agentre; r=$?; WG=; check "M9 (no agent re-check at capture) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M10 's/^  if \[ -e "\$G\/restarted-\$ex" \]; then restarted_holds.*$/  :/' &&
  { WG=$B/mut/M10.sh; t_restart_idem; r=$?; WG=; check "M10 (a repeated restart runs again) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M11 's/^  freeze_holds   # restart:.*$/  :/' &&
  { WG=$B/mut/M11.sh; t_restart_idem; r=$?; WG=; check "M11 (no freeze check before restart) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M12 's/^  freeze_holds   # rollback:.*$/  :/' &&
  { WG=$B/mut/M12.sh; t_restart_idem; r=$?; WG=; check "M12 (no freeze check before rollback) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M13 's/stop "cannot read the process table (ps): no bd process can be ruled out"/true/' &&
  { WG=$B/mut/M13.sh; t_listfail; r=$?; WG=; check "M13 (a failing ps read as no bd) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M14 's/command -v lsof >\/dev\/null 2>&1 || return 2/:/; s/ \*) return 2 ;; esac/ *) ;; esac/; s/ || return 2   # a failed listing can still show this script and omit others//' &&
  { WG=$B/mut/M14.sh; t_listfail; r=$?; WG=; check "M14 (a failing lsof read as no agents) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M15 's/^LP=.*$/LP=x/' &&
  { WG=$B/mut/M15.sh; t_symlinks; r=$?; WG=; check "M15 (no check of the log directory's physical path) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M16 's/^  if \[ "\$o" != "\$BASE" \]; then pres_check; fi.*$/  :/; s/pres_check; d=\$PD/PD=\$PRES\/\$HOST-\$o; d=\$PD/' &&
  { WG=$B/mut/M16.sh; t_symlinks; r=$?; WG=; check "M16 (no check of the preservation directory) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M17 's/ unrecord_bail$//' &&
  { WG=$B/mut/M17.sh; t_putfail; r=$?; WG=; check "M17 (a failed record leaves the restart half done) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M18 's/^inroot() {.*$/inroot() { "$@"; }/' &&
  { WG=$B/mut/M18.sh; t_cwd; r=$?; WG=; check "M18 (bd run from the caller's directory) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M19 's/ || return 2   # a failed listing can still show this script and omit others//' &&
  { WG=$B/mut/M19.sh; t_lsofpartial; r=$?; WG=; check "M19 (lsof's exit status ignored) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M20 '/^restart_clavain()/,/^unrecord_bail/ s/^  restore_marker$/  cp -p "$G\/marker" "$ROOT\/.git-autosync" || stop "cannot restore the marker"/' &&
  { WG=$B/mut/M20.sh; t_clavmarker; r=$?; WG=; check "M20 (Clavain marker not checked against the freeze record) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M21 's/^    \[ "\$(unit_state "\$u")" = active \] || rbail .*; done$/    :; done/' &&
  { WG=$B/mut/M21.sh; t_startlie; r=$?; WG=; check "M21 (a started timer not checked live) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M22 's/env CUTOVER_REPORT=0 "\$CS" --check/"$CS" --check/' &&
  { WG=$B/mut/M22.sh; t_checkreport; r=$?; WG=; check "M22 (preflight check lets the step script report) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M23 's/ && ! restarted_any; then/; then/' &&
  { WG=$B/mut/M23.sh; t_refreeze; r=$?; WG=; check "M23 (freeze after a completed restart stops) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }

mutate M24 's/|| { skippable_proc "\$d" "\$p" && continue; return 2; }/|| continue/' &&
  { WG=$B/mut/M24.sh; t_unreadable; r=$?; WG=; check "M24 (an unreadable process skipped) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M25 's/^  prior=; .*$/  prior=/' &&
  { WG=$B/mut/M25.sh; t_failstop; r=$?; WG=; check "M25 (no memory of a partly stopped freeze) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M26 's/^  \[ ! -e "\$DRIFT" \] || mv -f -- "\$DRIFT" "\$LOGD\/drift.before".*$/  :/' &&
  { WG=$B/mut/M26.sh; t_staledrift; r=$?; WG=; check "M26 (an earlier drift report accepted) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M27 's/^  \[ -z "\$bad" \] || say .*$/  :/; s/\${bad:+; UNCONFIRMED stop of\$bad}//' &&
  { WG=$B/mut/M27.sh; t_unconfirmed; r=$?; WG=; check "M27 (an unconfirmed stop not reported) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M28 's/^  rm -f -- "\$G"\/restarted-\*/  rm -f -- "$G\/freeze-intent"\n&/; /^  rm -f -- "\$G\/freeze-intent"   # last/d' &&
  { WG=$B/mut/M28.sh; t_refreezecrash; r=$?; WG=; check "M28 (the restart set dropped before the earlier restart records) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M29 's/2>\/dev\/null || stop "cannot read .beads\/issues.jsonl at \$t (the tree lists it): its records cannot be compared"/2>\/dev\/null || : > "$LOGD\/jsonl.$t"/' &&
  { WG=$B/mut/M29.sh; t_reconcileread; r=$?; WG=; check "M29 (an unreadable tracker file read as empty) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M30 's/ --after-cursor="\$1"//' &&
  { WG=$B/mut/M30.sh; t_stalejournal; r=$?; WG=; check "M30 (journal lines not tied to this start) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M31 '/^restarted_holds()/,/^do_restart/ s/unrecord_bail/stop/' &&
  { WG=$B/mut/M31.sh; t_holdsbail; r=$?; WG=; check "M31 (a failed recorded-restart check left as a plain STOP) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M32 '/^restarted_holds()/,/^do_restart/ s/\[ "\$(unit_state "\$u")" = active \] || unrecord_bail/is_active "$u" || unrecord_bail/' &&
  { WG=$B/mut/M32.sh; t_holdsunknown; r=$?; WG=; check "M32 (an unknown timer state in a recorded restart skips the cleanup) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M33 's/^  move_marker_aside force; \[ -n /  move_marker_aside; [ -n /' &&
  { WG=$B/mut/M33.sh; t_holdsmarker; r=$?; WG=; check "M33 (a changed marker left in the checkout by the cleanup) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }

mutate M34 's/^  if restarting_any; then rbail /  if false; then rbail /' &&
  { WG=$B/mut/M34.sh; t_restartcrash; r=$?; WG=; check "M34 (an earlier restart attempt that left no record is not looked for) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M35 's/\[ ! -e "\$ROOT\/.git-autosync" \] || unrecord_bail "restart \$1 is recorded with no marker[^"]*"/:/' &&
  { WG=$B/mut/M35.sh; t_holdsnone; r=$?; WG=; check "M35 (a recorded no-marker restart does not check the marker stays absent) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M36 's/^  if \[ "\${1:-}" = force \] \&\& \[ ! -e "\$G\/marker" \]/  if false \&\& [ ! -e "$G\/marker" ]/' &&
  { WG=$B/mut/M36.sh; t_holdsnone; r=$?; WG=; check "M36 (cleanup of a no-marker record makes a marker record instead of keeping the bytes) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
if [ $fails = 0 ]; then echo "GATE0-RUN: PASS"; exit 0; else echo "GATE0-RUN: FAIL ($fails)"; exit 1; fi
