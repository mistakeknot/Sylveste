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
then sha() { local h; h=$(set -o pipefail; sha256sum | cut -d' ' -f1) && [[ $h =~ ^[0-9a-f]{64}$ ]] && printf '%s\n' "$h" || echo "sha-failed-$RANDOM-$RANDOM"; }
else sha() { local h; h=$(set -o pipefail; shasum -a 256 2>/dev/null | cut -d' ' -f1) && [[ $h =~ ^[0-9a-f]{64}$ ]] && printf '%s\n' "$h" || echo "sha-failed-$RANDOM-$RANDOM"; }; fi   # a hash that fails is a fresh sentinel: two failed observations are never equal
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

for _v in $(compgen -e); do case $_v in GIT_*) unset "$_v" ;; esac; done   # no Git environment override reaches the fixtures (repository, work tree, index, object store, configuration): the settings the fixtures need are set below
export HOME=$B/home GIT_CONFIG_GLOBAL=$B/gitconfig GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
mkdir -p "$HOME" "$B/bin" "$B/stub" "$B/mut" "$B/lib"
git config --global user.email t@example.invalid; git config --global user.name t
git config --global init.defaultBranch main; git config --global advice.detachedHead false
export GIT_AUTHOR_DATE='2026-10-01T00:00:00Z' GIT_COMMITTER_DATE='2026-10-01T00:00:00Z'
W=$B/w; R=$W/root/Sylveste; J=$W/J; ST=$W/st

link_text() { local t; t=$(readlink -- "$1" && printf x) || return 1; t=${t%x}; printf '%s' "${t%?}"; }
dgh() { local h; h=$(set -o pipefail; sha) && [[ $h =~ ^[0-9a-f]{64}$ ]] && printf '%s' "$h"; }   # stdin's digest; a hash that fails prints nothing and fails
dg() {  # an entry's kind and digest; a digest that cannot be made is a fresh sentinel, so two failed observations are never equal
  local h k
  if [ -L "$1" ]; then k=l; h=$(set -o pipefail; link_text "$1" | dgh)
  elif [ -d "$1" ]; then echo d; return 0
  elif [ -f "$1" ]; then if [ -x "$1" ]; then k=x; else k=f; fi; h=$(dgh < "$1")
  else echo -; return 0; fi
  if [ -n "$h" ]; then printf '%s:%s\n' "$k" "$h"; else echo "dg-failed-$RANDOM-$RANDOM"; fi; }
files() { (cd "$1" && set -o pipefail && find . -path ./.git -prune -o \( -type f -o -type l \) -print | sed 's|^\./||' | sort); }
dmap() { local p; while IFS= read -r p; do printf '%s\t%s\n' "$(dg "$1/$p")" "$p"; done < "$2"; }
wr() { mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; }
g() { GIT_OPTIONAL_LOCKS=0 git -C "$R" "$@"; }   # the test observes the checkout without refreshing its index
ckfp() {  # the checkout as the plan sees it, plus the marker's presence and bytes; an observation that cannot be made, or that fails after its output, is never equal to another one
  local bad="ckfp-failed-$RANDOM-$RANDOM" sr
  g rev-parse HEAD > /dev/null 2>&1 || { echo "$bad"; return 0; }
  g symbolic-ref -q HEAD; sr=$?; [ $sr -le 1 ] || echo "$bad"   # 1 is a detached HEAD; anything else is a read that failed
  g rev-parse HEAD || echo "$bad"; { g ls-files -s || echo "$bad"; } | sha; g status --porcelain -uall || echo "$bad"
  files "$R" > "$B/ck.list" || echo "$bad"; dmap "$R" "$B/ck.list"
  g for-each-ref --format='%(refname) %(objectname)' refs/heads refs/tags || echo "$bad"; dg "$R/.git-autosync"; }
jfp() {  # the journal's files and directories with their digests, hashed; a listing that fails anywhere, after its output included, is never equal to another one
  local l; l=$(cd "$J" 2>/dev/null && set -o pipefail && find . -mindepth 1 \( -type f -o -type d \) | sort | while IFS= read -r p; do printf '%s %s\n' "$p" "$(dg "$p")"; done) || { echo "jfp-failed-$RANDOM-$RANDOM"; return 0; }
  printf '%s\n' "$l" | sha || echo "jfp-failed-$RANDOM-$RANDOM"; }
lanerefs() { git --git-dir="$W/lane.git" for-each-ref --format='%(refname) %(objectname)' || echo "lanerefs-failed-$RANDOM-$RANDOM"; }
snap() { rm -rf -- "${B:?}/tpl-${1:?}"; cp -a "$W" "$B/tpl-$1"; }
restore() { rm -rf -- "${W:?}"; cp -a "$B/tpl-$1" "$W"; }

# ---- stubs: the unit controller, journalctl, the lane library, the predictor, the report sender, the tracker
cat > "$B/bin/ctl" <<EOF
#!/bin/bash
# ctl stop|start|active UNIT : unit state is a file; starting the repair service writes the journal unless told not to
S=$ST; act=\$1; shift
for u in "\$@"; do case \$act in
  stop) [ ! -e "\$S/failstop-\$u" ] || exit 1
        [ ! -e "\$S/stop-hang" ] || { echo \$PPID > "\$S/stop-hung"; while [ ! -e "\$S/stop-release" ]; do sleep 0.1; done; }   # a stop that blocks until the test lets it go
        rm -f "\$S/units/\$u" ;;
  active) [ ! -e "\$S/ctl-error" ] || exit 4; [ -e "\$S/units/\$u" ] || exit 3 ;;
  start) [ ! -e "\$S/failstart-\$u" ] || exit 1
         if [ "\$u" = git-autosync-repair.service ]; then echo "start \$(date +%s)" >> "\$S/starts"; [ ! -e "\$S/svc-stays-active" ] || touch "\$S/units/\$u"
           [ -e "\$S/nojournal" ] || echo "1 autosync repo(s): 1 unchanged" >> "\$S/jlog"
           [ ! -e "\$S/start-hang" ] || { echo \$PPID > "\$S/start-hung"; while [ ! -e "\$S/start-release" ]; do sleep 0.1; done; }   # a start that blocks until the test lets it go: the caller is signalled meanwhile
         else [ -e "\$S/lie-\$u" ] || touch "\$S/units/\$u"; [ ! -e "\$S/lockg" ] || chmod a-w "$J/gate0-run"; fi ;;
  esac; done
EOF
# journalctl: an append-only log whose cursor is the number of lines so far (--show-cursor), read back with --after-cursor
cat > "$B/stub/journalctl" <<EOF
#!/bin/bash
f=$ST/jlog; touch "\$f"
for a in "\$@"; do case \$a in
  --show-cursor) [ ! -e "$ST/fail-jcursor" ] || { echo "journalctl: cannot read the journal (stub)" >&2; exit 1; }; echo "-- cursor: \$(wc -l < "\$f" | tr -d ' ')"; exit 0 ;;
  --after-cursor=*) tail -n +\$(( \${a#--after-cursor=} + 1 )) "\$f"; [ ! -e "$ST/fail-jafter" ] || { echo "journalctl: read failed after output (stub)" >&2; exit 1; }; exit 0 ;; esac; done
cat "\$f"
EOF
cat > "$B/lib/autosync-lane.sh" <<EOF
# stub lane library: asl_resolve REPO [REMOTE] validates, asl_tip REPO REF reads the tip
asl_resolve() { ASL_REASON=; ASL_SLUG=fixture/lane; ASL_NAME=\$2; ASL_URL=
  [ ! -e "$ST/refuse-archive" ] || { ASL_REASON="not verified private"; return 1; }
  if [ -e "$ST/asl-url" ]; then ASL_URL=\$(cat "$ST/asl-url"); else ASL_URL=\$(git -C "\$1" remote get-url --push "\$2"); fi; }
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
[ -e "$B/lsof-partial" ] || [ -e "$B/lsof-ok" ] || exit 1
p=\$PPID
while [ -n "\$p" ] && [ "\$p" -gt 1 ]; do printf 'p%s\ncfake\nn/nowhere\n' "\$p"; p=\$($REALPS -o ppid= -p "\$p" | tr -d ' '); done
[ -e "$B/lsof-ok" ] && exit 0
exit 1
EOF
# sync, except that it fails for an argument matching the glob in $ST/failsync (a flush that does not happen); the python fsync fallback too
cat > "$B/stub/sync" <<EOF
#!/bin/bash
if [ -e "$ST/failsync" ]; then for a in "\$@"; do case \$a in \$(cat "$ST/failsync")) exit 1 ;; esac; done; fi
exec /bin/sync "\$@"
EOF
REALPY=$(command -v python3)
cat > "$B/stub/python3" <<EOF
#!/bin/bash
if [ -e "$ST/failsync" ]; then case \${!#} in \$(cat "$ST/failsync")) exit 1 ;; esac; fi
exec $REALPY "\$@"
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
# the lane cannot be read by the wrapper's own git calls (the steps it runs read it through their own, which still work)
if [ -e "$ST/fail-lsremote" ]; then case " \$* " in *" ls-remote "*) case "\$($REALPS -o args= -p \$PPID)" in *cutover-steps*) ;; *) echo "fatal: unable to access the lane (stub)" >&2; exit 128 ;; esac ;; esac; fi
if [ -e "$ST/fail-arch-after" ]; then case " \$* " in *" ls-remote "*archive/gate0*) case "\$($REALPS -o args= -p \$PPID)" in *cutover-steps*) ;; *) n=\$(cat "$ST/arch-n" 2>/dev/null || echo 0); n=\$((n+1)); echo \$n > "$ST/arch-n"; if [ \$n -gt \$(cat "$ST/fail-arch-after") ]; then echo "fatal: unable to access the lane (stub)" >&2; exit 128; fi ;; esac ;; esac; fi
if [ -e "$ST/fail-tip-after" ]; then case " \$* " in *" ls-remote "*refs/heads/autosync/*) case "\$($REALPS -o args= -p \$PPID)" in *cutover-steps*) ;; *) n=\$(cat "$ST/tip-n" 2>/dev/null || echo 0); n=\$((n+1)); echo \$n > "$ST/tip-n"; if [ \$n -gt \$(cat "$ST/fail-tip-after") ]; then echo "fatal: unable to access the lane (stub)" >&2; exit 128; fi ;; esac ;; esac; fi
if [ -e "$ST/gitfail" ]; then case " \$* " in *"\$(cat "$ST/gitfail")"*) case "\$($REALPS -o args= -p \$PPID)" in *cutover-steps*) ;; *) n=\$(cat "$ST/gitfail-n" 2>/dev/null || echo 0); n=\$((n+1)); echo \$n > "$ST/gitfail-n"
  if [ \$n -gt \$(cat "$ST/gitfail-skip" 2>/dev/null || echo 0) ]; then [ ! -e "$ST/gitfail-out" ] || $REALGIT "\$@"; echo "fatal: injected failure (stub)" >&2; exit 128; fi ;; esac ;; esac; fi
# the names of the GIT_* variables each git process starts with (while $ST/gitenv-log exists); at call number N of $ST/gitredir (lines: N, root, work tree) the checkout's core.worktree is pointed elsewhere
# while $ST/gitargs-log exists, the arguments of each of the wrapper's own git calls (the steps it runs are not counted), in the order sw_inj counts them
if [ -e "$ST/gitargs-log" ]; then case "\$($REALPS -o args= -p \$PPID)" in *cutover-steps*) ;; *) echo "\$*" >> "$ST/gitargs-log" ;; esac; fi
if [ -e "$ST/gitenv-log" ]; then env | grep '^GIT_' | sed 's/=.*//' >> "$ST/gitenv-log"; fi
# while $ST/gitdirenv exists, a git that reads the git directory (--git-dir) is started with GIT_DIR set to the file's content, as if the scrub had let it through
if [ -e "$ST/gitdirenv" ]; then case " \$* " in *" --git-dir "*) export GIT_DIR=\$(cat "$ST/gitdirenv") ;; esac; fi
if [ -e "$ST/gitredir" ]; then n=\$(cat "$ST/gitredir-n" 2>/dev/null || echo 0); n=\$((n+1)); echo \$n > "$ST/gitredir-n"; if [ \$n = \$(sed -n 1p "$ST/gitredir") ]; then $REALGIT -C "\$(sed -n 2p "$ST/gitredir")" config core.worktree "\$(sed -n 3p "$ST/gitredir")"; fi; fi
# while $ST/gitredir-marker exists (lines: root, work tree, N), the first git call that finds the marker back in the checkout (a restart past its marker restore) counts; at the Nth the checkout's core.worktree is pointed elsewhere
if [ -e "$ST/gitredir-marker" ] && [ ! -e "$ST/gitredir-marker-done" ] && [ -e "\$(sed -n 1p "$ST/gitredir-marker")/.git-autosync" ]; then c=\$(cat "$ST/gitredir-marker-c" 2>/dev/null || echo 0); echo \$((c+1)) > "$ST/gitredir-marker-c"
  if [ \$c = \$(sed -n 3p "$ST/gitredir-marker") ]; then : > "$ST/gitredir-marker-done"; $REALGIT -C "\$(sed -n 1p "$ST/gitredir-marker")" config core.worktree "\$(sed -n 2p "$ST/gitredir-marker")"; fi; fi
exec $REALGIT "\$@"
EOF
# sha256sum: fails for a stdin that is a file whose path matches the glob in $ST/fail-sha (Linux: /proc names the file behind the redirect)
REALSHA=$(command -v sha256sum)
cat > "$B/stub/sha256sum" <<EOF
#!/bin/bash
if [ -e "$ST/fail-sha" ]; then p=\$(readlink /proc/self/fd/0 2>/dev/null); case "\$p" in \$(cat "$ST/fail-sha")) cat > /dev/null; echo "sha256sum: injected failure (stub)" >&2; exit 1 ;; esac; fi
if [ -e "$ST/fail-sha-out" ]; then p=\$(readlink /proc/self/fd/0 2>/dev/null); case "\$p" in \$(cat "$ST/fail-sha-out")) $REALSHA "\$@"; echo "sha256sum: injected failure after output (stub)" >&2; exit 1 ;; esac; fi
exec $REALSHA "\$@"
EOF
# awk: the lsof listing's filter (the call with -v r=) fails while $ST/fail-awk exists
REALAWK=$(command -v awk)
cat > "$B/stub/awk" <<EOF
#!/bin/bash
if [ -e "$ST/fail-awk" ]; then case "\$*" in *"-v r="*) cat > /dev/null; echo "awk: injected failure (stub)" >&2; exit 2 ;; esac; fi
exec $REALAWK "\$@"
EOF
# grep: a call whose arguments contain the text in $ST/grepfail fails with status 2, printing what it would first while $ST/grepfail-out exists
REALGREP=$(command -v grep)
cat > "$B/stub/grep" <<EOF
#!/bin/bash
if [ -e "$ST/grepfail" ]; then case " \$* " in *"\$(cat "$ST/grepfail")"*) if [ -e "$ST/grepfail-out" ]; then $REALGREP "\$@"; else cat > /dev/null; fi; echo "grep: injected failure (stub)" >&2; exit 2 ;; esac; fi
exec $REALGREP "\$@"
EOF
# sed: a call whose arguments contain the text in $ST/sedfail fails (after $ST/sedfail-skip such calls passed), printing what it would first while $ST/sedfail-out exists
REALSED=$(command -v sed)
cat > "$B/stub/sed" <<EOF
#!/bin/bash
if [ -e "$ST/sedfail" ]; then case " \$* " in *"\$(cat "$ST/sedfail")"*)
  n=\$(cat "$ST/sedfail-n" 2>/dev/null || echo 0); n=\$((n+1)); echo \$n > "$ST/sedfail-n"
  if [ \$n -gt \$(cat "$ST/sedfail-skip" 2>/dev/null || echo 0) ]; then [ ! -e "$ST/sedfail-out" ] || $REALSED "\$@"; echo "sed: injected failure (stub)" >&2; exit 4; fi ;; esac; fi
exec $REALSED "\$@"
EOF
# cut: a call whose arguments contain the text in $ST/cutfail prints what it would, then fails (the status of a pipeline's first stage)
REALCUT=$(command -v cut)
cat > "$B/stub/cut" <<EOF
#!/bin/bash
if [ -e "$ST/cutfail" ]; then case " \$* " in *"\$(cat "$ST/cutfail")"*) $REALCUT "\$@"; echo "cut: injected failure after output (stub)" >&2; exit 1 ;; esac; fi
exec $REALCUT "\$@"
EOF
# id -u : prints nothing and fails (none), prints the id and then fails (after), or prints a word (word), while $ST/idfail holds that mode
REALID=$(command -v id)
cat > "$B/stub/id" <<EOF
#!/bin/bash
if [ -e "$ST/idfail" ] && [ "\$*" = -u ]; then case "\$(cat "$ST/idfail")" in
  after) $REALID -u; exit 1 ;; word) echo root; exit 0 ;; *) exit 1 ;; esac; fi
exec $REALID "\$@"
EOF
# systemctl --user is-active UNIT : prints the word in $ST/sysctl-out and exits $ST/sysctl-rc (stop and start do nothing)
cat > "$B/stub/systemctl" <<EOF
#!/bin/bash
case "\$*" in *is-active*) cat "$ST/sysctl-out" 2>/dev/null; exit \$(cat "$ST/sysctl-rc" 2>/dev/null || echo 4) ;; esac
exit 0
EOF
chmod +x "$B/stub/id" "$B/stub/cut" "$B/stub/grep" "$B/stub/sed" "$B/stub/awk" "$B/stub/systemctl" "$B/stub/sha256sum" "$B/stub/git" "$B/stub/sync" "$B/stub/python3" "$B/bin/sweep" "$B/stub/lsof" "$B/stub/ps" "$B/bin/ctl" "$B/stub/journalctl" "$B/bin/pred" "$B/bin/tell"
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
  # Every account in the passwd database is listed too: a process of one (the sshd privilege-separation child of an inbound connection is one) can appear between this listing and the wrapper's own scan
  { stat -c %u /proc/[0-9]* 2>/dev/null; getent passwd 2>/dev/null | cut -d: -f3; } | sort -u | tr '\n' ' '; }
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
    case $pt in service) pat='/^  units start "\$REPAIR_SVC"/a kill -KILL $$' ;; timer) pat='/^    units start "\$u" || rbail "cannot re-enable/a kill -KILL $$' ;; esac
    sed "$pat" "${WG:-$GW}" > "$crash"; chmod +x "$crash"; cp "$HERE/cutover-steps.sh" "$B/mut/cutover-steps.sh"
    cmp -s "${WG:-$GW}" "$crash" && { echo "  FAIL crash copy for $pt changed nothing"; return 1; }
    restore r0a; rm -f "$ST/units/git-autosync-repair.service"; [ $pt != service ] || touch "$ST/svc-stays-active"; WG=$crash wg restart r0 > "$B/out.rc" 2>&1; rc=$?
    f="$([ -e "$R/.git-autosync" ] && echo marker)/$(timers)/svc-$(active git-autosync-repair.service)"
    rm -f "$ST/svc-stays-active"   # the retry's own start of the service finishes at once, as the real oneshot does
    wg restart r0 >> "$B/out.rc" 2>&1; rc2=$?
    f="$f/$rc2/$([ -e "$R/.git-autosync" ] && echo marker)/$(timers)/svc-$(active git-autosync-repair.service)/$(ls "$J/gate0-run" | grep -c '^restart')"
    wg restart r0 >> "$B/out.rc" 2>&1; rc3=$?
    RCS="$RCS$rc/$f/$rc3/$(timers)/$([ -e "$J/gate0-run/restarted-r0" ] && echo recorded);"
  done
  rm -f "$ST/svc-stays-active"
  [ "$RCS" = "137/marker/no/no/svc-yes/3//no/no/svc-no/0/0/yes/yes/recorded;137/marker/yes/no/svc-no/3//no/no/svc-no/0/0/yes/yes/recorded;" ]; }
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

t_archrecheck() {  # capture validates the archive destination again after the last freeze check, and binds P1a to the push URL it validated
  local c0 rc1 rc2 rc3 d
  restore fx; stepto preflight freeze || return 1; touch "$ST/refuse-archive"; c0=$(ckfp)
  wg capture > "$B/out.ar" 2>&1; rc1=$?
  d="$(grep -c 'archive destination is not acceptable' "$B/out.ar")/$([ -e "$J/cp" ] && echo cp)/$([ "$(ckfp)" = "$c0" ] && echo same)/$(ls "$W/pres" 2>/dev/null | wc -l)"
  rm -f "$ST/refuse-archive"
  restore fx; stepto preflight freeze || return 1; echo "file:///somewhere/else.git" > "$ST/asl-url"; c0=$(ckfp)
  wg capture > "$B/out.ar" 2>&1; rc2=$?
  d="$d/$(grep -c 'push URL of lane is not the one just validated' "$B/out.ar")/$([ -e "$J/cp" ] && echo cp)/$([ "$(ckfp)" = "$c0" ] && echo same)"
  rm -f "$ST/asl-url"
  restore fx; stepto preflight freeze || return 1
  wg capture > "$B/out.ar" 2>&1; rc3=$?
  ARS="$rc1/$rc2/$rc3/$d/$([ -e "$J/cp" ] && echo cp)"
  [ "$ARS" = "3/3/0/1//same/0/1//same/cp" ]; }
t_flushfail() {  # a flush that fails is a STOP at every point of the preservation copy; the capture is not recorded as done
  local pat rc res=; local pats=("*/pres/*/main.bundle.tmp.*" "*/pres/*/wtree.manifest" "*/pres/*/sha256" "*/pres/mA-????????????????????????????????????????")
  for pat in "${pats[@]}"; do
    restore fx; stepto preflight freeze || return 1; printf '%s\n' "$pat" > "$ST/failsync"
    wg capture > "$B/out.ff" 2>&1; rc=$?; rm -f "$ST/failsync"
    res="$res$rc/$(grep -c 'cannot \(copy and \)\?flush' "$B/out.ff")/$([ -e "$J/gate0-run/captured" ] && echo captured);"
  done
  FFS=$res
  [ "$res" = "3/1/;3/1/;3/1/;3/1/;" ]; }
t_lanefail() {  # Clavain row 8: a lane that cannot be read is not a lane that has not changed, even when the recorded tip is empty
  restore r0a; rm -f "$B/drift.txt"; rm -f "$J/gate0-run/marker" "$R/.git-autosync"
  sed -i 's/^marker .*/marker none/' "$J/gate0-run/freeze"; : > "$J/p0/lane"; echo 1 > "$ST/fail-tip-after"; rm -f "$ST/tip-n"
  GATE0_MACHINE=clavain GATE0_SWEEP="$B/bin/sweep" GATE0_DRIFT_REPORT="$B/drift.txt" wg restart r0 > "$B/out.lf" 2>&1; LFC=$?; rm -f "$ST/fail-tip-after"
  LFS="$(grep -c 'cannot read the Clavain lane tip' "$B/out.lf")/$([ -e "$J/gate0-run/restarted-r0" ] && echo recorded)/$(timers)"
  [ "$LFC/$LFS" = "3/1//no/no" ]; }

t_archfail() {  # a lane read that fails is a STOP, not an empty listing that equals another empty listing (tip before, archive before, archive after)
  local n rc; AFS=
  for n in tip 1 2; do   # the archive listing in the restart's own archive check is the first call; the reads before and after the run are the next two
    restore r0a; rm -f "$ST/arch-n"
    case $n in tip) echo 1 > "$ST/fail-tip-after"; rm -f "$ST/tip-n" ;; *) echo "$n" > "$ST/fail-arch-after" ;; esac
    wg restart r0 > "$B/out.af$n" 2>&1; rc=$?
    AFS="$AFS$rc/$(grep -c 'cannot read the \(lane tip\|archive branches\)' "$B/out.af$n")/$([ -e "$J/gate0-run/restarted-r0" ] && echo recorded)/$(timers)/$([ -e "$R/.git-autosync" ] && echo marker);"
    rm -f "$ST/fail-tip-after" "$ST/fail-arch-after"
  done
  [ "$AFS" = "3/1//no/no/;3/1//no/no/;3/1//no/no/;" ]; }
t_svcoverride() {  # a custom service list still holds the service a restart starts: a cut-off restart's cleanup stops it
  local crash=$B/mut/crash.sh rc rc2
  sed '/^  units start "\$REPAIR_SVC"/a kill -KILL $$' "${WG:-$GW}" > "$crash"; chmod +x "$crash"; cp "$HERE/cutover-steps.sh" "$B/mut/cutover-steps.sh"
  restore r0a; rm -f "$ST/units/git-autosync-repair.service"; touch "$ST/svc-stays-active"
  GATE0_UNITS_SERVICES="other.service" WG=$crash wg restart r0 > "$B/out.so" 2>&1; rc=$?
  rm -f "$ST/svc-stays-active"
  GATE0_UNITS_SERVICES="other.service" wg restart r0 >> "$B/out.so" 2>&1; rc2=$?
  SOS="$rc/$rc2/$(active git-autosync-repair.service)/$(timers)/$([ -e "$R/.git-autosync" ] && echo marker)"
  [ "$SOS" = "137/3/no/no/no/" ]; }
t_hookafter() {  # a writing hook installed after preflight is found before capture's fetch runs it
  restore fx; stepto preflight freeze || return 1
  rm -f "$B/hook-ran"; git -C "$SD" push -q origin main:refs/heads/newbr2
  printf '#!/bin/sh\ntouch %q\n' "$B/hook-ran" > "$R/.git/hooks/reference-transaction"; chmod +x "$R/.git/hooks/reference-transaction"
  wg capture > "$B/out.ha" 2>&1; HAC=$?
  HAS="$(grep -c 'reference-transaction hook' "$B/out.ha")/$([ -e "$B/hook-ran" ] && echo ran)/$([ -d "$J/p1-pre" ] && echo pre)"
  rm -f "$R/.git/hooks/reference-transaction"
  [ "$HAC/$HAS" = "3/1//" ]; }

# ---- class sweep: every read whose status or content a decision rests on is checked where it is used (bead mk-z9st.22)
# swrun LABEL... : the status, the matching message count and the state words of the last run are one string
sw_msg() { grep -c -- "$1" "$B/out.sw"; }
sw_inj() {  # PATTERN [SKIP] : the wrapper's own git calls whose arguments contain PATTERN fail (after SKIP matching calls pass)
  printf '%s' "$1" > "$ST/gitfail"; printf '%s' "${2:-0}" > "$ST/gitfail-skip"; rm -f "$ST/gitfail-n"; }
t_swfreezesha() {  # a marker that cannot be hashed is not recorded as "none" or as an empty value
  restore fx; stepto preflight || return 1; printf '%s' '*/gate0-run/marker' > "$ST/fail-sha"
  wg freeze > "$B/out.sw" 2>&1; SWA="$?/$(sw_msg 'cannot hash the marker set aside')/$([ -e "$J/gate0-run/freeze" ] && echo recorded)"
  [ "$SWA" = "3/1/" ]; }
t_swhooksha() {  # an installed hook that cannot be hashed is a STOP, not an empty digest that matches nothing
  restore fx; printf '#!/bin/sh\nexit 0\n' > "$R/.git/hooks/reference-transaction"; chmod +x "$R/.git/hooks/reference-transaction"
  sha < "$R/.git/hooks/reference-transaction" > "$B/ro-hooks.sw"; printf '%s' '*/hooks/reference-transaction' > "$ST/fail-sha"
  GATE0_READONLY_HOOKS="$B/ro-hooks.sw" wg preflight > "$B/out.sw" 2>&1; SWB="$?/$(sw_msg 'cannot hash the installed reference-transaction hook')/$([ -d "$J/p0" ] && echo p0)"
  [ "$SWB" = "3/1/" ]; }
t_swhookgit() {  # a failed read of core.hooksPath, or of the hooks directory, is a STOP and not "no hook"
  local a b; restore fx; sw_inj ' config core.hooksPath'
  wg preflight > "$B/out.sw" 2>&1; a="$?/$(sw_msg 'cannot read core.hooksPath')/$([ -d "$J/p0" ] && echo p0)"
  restore fx; sw_inj ' --git-path hooks'
  wg preflight > "$B/out.sw" 2>&1; b="$?/$(sw_msg 'cannot locate the hooks directory')/$([ -d "$J/p0" ] && echo p0)"
  SWC="$a;$b"; [ "$SWC" = "3/1/;3/1/" ]; }
t_swready() {  # the git directory, the commit count and the two status reads: a failed read is a STOP, not an empty value, and a read that fails after its output is a failed read
  local p res= k m o; for o in plain out; do for p in ' rev-parse --absolute-git-dir|cannot read the git directory' ' rev-parse --show-toplevel|is not GATE0_ROOT itself|1' ' rev-parse --path-format=absolute --git-dir|has no usable git directory|1' \
      ' rev-parse --git-common-dir|has no usable common git directory|1' ' rev-list --left-right --count|cannot count the commits' \
      ' status --porcelain --untracked-files=no|cannot read the status: the local changes' ' status --porcelain --untracked-files=all|cannot read the status: the untracked files'; do
    m=${p#*|}; k=0; case $m in *"|"*) k=${m#*|}; m=${m%%|*} ;; esac   # the wrapper's own start-up check (the git binding) reads each of its three once
    restore fx; sw_inj "${p%%|*}" $k; [ $o = plain ] || touch "$ST/gitfail-out"; wg preflight > "$B/out.sw" 2>&1; res="$res$?/$(sw_msg "$m")/$([ -d "$J/p0" ] && echo p0);"
  done; done
  SWD=$res; [ "$SWD" = "$(printf "3/1/;%.0s" {1..14})" ]; }
t_swarchlist() {  # an archive listing that fails is not an empty one
  restore fx; echo 0 > "$ST/fail-arch-after"; rm -f "$ST/arch-n"
  wg preflight > "$B/out.sw" 2>&1; SWE="$?/$(sw_msg 'cannot list the archive branches on the lane')/$([ -d "$J/p0" ] && echo p0)"
  [ "$SWE" = "3/1/" ]; }
t_swheadrec() {  # the preflight record never names an empty head
  restore fx; sw_inj ' rev-parse HEAD' 
  wg preflight > "$B/out.sw" 2>&1; SWF="$?/$(sw_msg 'cannot read HEAD')/$([ -e "$J/gate0-run/preflight" ] && echo recorded)"
  [ "$SWF" = "3/1/" ]; }
sw_state() { echo "$([ -e "$J/gate0-run/restarted-r0" ] && echo recorded)/$(nstarts)/$(timers)/$([ -e "$R/.git-autosync" ] && echo marker)"; }
t_swp1pre() {  # a missing, empty or damaged P1-pre head is a STOP in the restart and in a repeated capture, never an empty old tip
  local v res=
  for v in missing empty junk; do
    restore r0a; case $v in missing) rm -f "$J/p1-pre/head" ;; empty) : > "$J/p1-pre/head" ;; junk) echo "not-a-sha" > "$J/p1-pre/head" ;; esac
    wg restart r0 > "$B/out.sw" 2>&1; res="$res$?/$(sw_msg 'the unfreeze gate refused\|P1-pre record')/$(sw_state);"
  done
  restore fx; stepto preflight freeze capture || return 1; rm -f "$J/p1-pre/head"
  wg capture > "$B/out.sw" 2>&1; res="$res$?/$(sw_msg 'P1-pre record')"
  SWG=$res; [ "$SWG" = "3/1//0/no/no/;3/1//0/no/no/;3/1//0/no/no/;3/1" ]; }
t_swtree() {  # the base's tree and the index's tree are both read; a failed read of either is a STOP after P1a, and capture is not recorded
  local a b
  restore fx; stepto preflight freeze || return 1; sw_inj '^{tree}'
  wg capture > "$B/out.sw" 2>&1; a="$?/$(sw_msg "re-check: cannot read the base's tree")/$([ -e "$J/gate0-run/captured" ] && echo captured)"
  restore fx; stepto preflight freeze || return 1; sw_inj ' write-tree'
  wg capture > "$B/out.sw" 2>&1; b="$?/$(sw_msg "re-check: the index is not the base's tree")/$([ -e "$J/gate0-run/captured" ] && echo captured)"
  SWH="$a;$b"; [ "$SWH" = "3/1/;3/1/" ]; }
t_swmarkrec() {  # a marker record that names no hash is not equal to a hash that could not be computed (restore, and a recorded restart)
  local a b
  restore r0a; sed -i '/^marker /d' "$J/gate0-run/freeze"; printf '%s' '*/.git-autosync' > "$ST/fail-sha"
  wg restart r0 > "$B/out.sw" 2>&1; a="$?/$(sw_msg 'the restored marker differs')/$(sw_state)"
  restore r0a; wg restart r0 > "$B/out.sw" 2>&1 || return 1
  sed -i '/^marker /d' "$J/gate0-run/freeze"; printf '%s' '*/.git-autosync' > "$ST/fail-sha"
  wg restart r0 > "$B/out.sw" 2>&1; b="$?/$(sw_msg 'is recorded but the marker in the checkout is not the one set aside')/$(sw_state)"
  SWI="$a;$b"; [ "$SWI" = "3/1//0/no/no/;3/1//1/no/no/" ]; }
t_swrestatus() {  # the status read behind the marker rule: a failed read is a STOP with nothing started
  restore r0a; sw_inj ' status --porcelain=v1'
  wg restart r0 > "$B/out.sw" 2>&1; SWJ="$?/$(sw_msg 'cannot read the status: whether the marker')/$(sw_state)"
  [ "$SWJ" = "3/1//0/no/no/" ]; }
t_swtags() { local t  # the gate0 tags are read before and after the run with the status checked; an empty list after P1a is a failed read in disguise
  local k res= t
  for k in 0 1; do restore r0a; sw_inj 'refs/tags/gate0' $k
    wg restart r0 > "$B/out.sw" 2>&1; res="$res$?/$(sw_msg 'cannot read the gate0 tags')/$(sw_state);"; done
  SWK=$res; [ "$SWK" = "3/1//0/no/no/;3/1//1/no/no/;" ]; }
t_swjcursor() {  # no journal cursor is a STOP before the service starts
  restore r0a; touch "$ST/fail-jcursor"
  wg restart r0 > "$B/out.sw" 2>&1; SWL="$?/$(sw_msg 'cannot take a journal cursor')/$(sw_state)"
  [ "$SWL" = "3/1//0/no/no/" ]; }
t_swp0lane() { local t  # a Clavain restart recorded with no marker needs the P0 lane record: a missing record is not an empty tip
  restore r0a; rm -f "$B/drift.txt" "$J/gate0-run/marker" "$R/.git-autosync" "$J/p0/lane"
  sed -i 's/^marker .*/marker none/' "$J/gate0-run/freeze"
  for t in $(git --git-dir="$W/lane.git" for-each-ref --format='%(refname)' 'refs/heads/autosync'); do git --git-dir="$W/lane.git" update-ref -d "$t"; done
  GATE0_MACHINE=clavain GATE0_SWEEP="$B/bin/sweep" GATE0_DRIFT_REPORT="$B/drift.txt" wg restart r0 > "$B/out.sw" 2>&1; SWM="$?/$(sw_msg 'the P0 lane record')/$(sw_state)"
  [ "$SWM" = "3/1//0/no/no/" ]; }
t_swarchready() {  # a restart validates the archive destination and its push URL itself, on both machines, before any side effect
  local res= m
  for m in server clavain; do
    restore r0a; touch "$ST/refuse-archive"
    GATE0_MACHINE=$m GATE0_SWEEP="$B/bin/sweep" GATE0_DRIFT_REPORT="$B/drift.txt" wg restart r0 > "$B/out.sw" 2>&1; res="$res$?/$(sw_msg 'archive destination is not acceptable')/$(sw_state);"
    restore r0a; echo "file:///somewhere/else.git" > "$ST/asl-url"
    GATE0_MACHINE=$m GATE0_SWEEP="$B/bin/sweep" GATE0_DRIFT_REPORT="$B/drift.txt" wg restart r0 > "$B/out.sw" 2>&1; res="$res$?/$(sw_msg 'push URL of lane is not the one just validated')/$(sw_state);"
  done
  SWN=$res; [ "$SWN" = "3/1//0/no/no/;3/1//0/no/no/;3/1//0/no/no/;3/1//0/no/no/;" ]; }

t_swshaout() {  # a hash that is printed and then fails (the tool exits nonzero after its output) is not a hash
  restore fx; stepto preflight || return 1; printf '%s' '*/gate0-run/marker' > "$ST/fail-sha-out"
  wg freeze > "$B/out.sw" 2>&1; SWO="$?/$(sw_msg 'cannot hash the marker set aside')/$([ -e "$J/gate0-run/freeze" ] && echo recorded)"
  [ "$SWO" = "3/1/" ]; }
t_swunitstate() {  # the production controller branch: the state word and the exit status must agree, and a transitional state is not confirmed
  local fn row res= w r
  fn=$(sed -n '/^unit_state() {/,/^is_active() {/p' "${WG:-$GW}" | sed '$d')
  for row in 'active 0 active' 'inactive 3 inactive' 'failed 3 inactive' 'inactive 0 unknown' 'active 3 unknown' 'failed 0 unknown' \
             'deactivating 3 unknown' 'activating 0 unknown' 'reloading 0 unknown' 'unknown 4 unknown' '- 1 unknown' '- 0 unknown'; do
    set -- $row; w=$1; r=$2; if [ "$w" = - ]; then : > "$ST/sysctl-out"; else printf '%s\n' "$w" > "$ST/sysctl-out"; fi; echo "$r" > "$ST/sysctl-rc"
    res="$res$( unset GATE0_TIMER_CTL; PATH="$PATHS"; XDG_RUNTIME_DIR=/nonexistent; eval "$fn"; unit_state git-autosync.timer )/"
  done
  SWP=$res; [ "$SWP" = "active/inactive/inactive/unknown/unknown/unknown/unknown/unknown/unknown/unknown/unknown/unknown/" ]; }
t_swjournal() {  # journal lines read by a failed read are not evidence: a start whose journal read fails is a STOP with the marker aside
  restore r0a; touch "$ST/fail-jafter"
  GATE0_JOURNAL_TRIES=0 wg restart r0 > "$B/out.sw" 2>&1; SWQ="$?/$(sw_msg 'the journal could not be read after the start')/$(sw_state)"
  [ "$SWQ" = "3/1//1/no/no/" ]; }
t_swlsofawk() {  # the lsof branch: a filter that fails shows no agents, and that is not "no agent"
  restore fx; stepto preflight || return 1; touch "$B/lsof-ok" "$ST/fail-awk"
  GATE0_PROCFS="$B/no-procfs" wg freeze > "$B/out.sw" 2>&1; SWR="$?/$(sw_msg 'cannot list the processes')/$([ -e "$J/gate0-run/freeze" ] && echo recorded)"
  rm -f "$B/lsof-ok"; [ "$SWR" = "3/1/" ]; }
t_swlsremote() {  # --check: origin/main read from the remote and from the tracking ref, both failing, are not "equal"
  restore fx; sw_inj 'main'
  wg --check preflight > "$B/out.sw" 2>&1; SWS="$?/$(sw_msg 'check: cannot read origin/main from the remote')"
  [ "$SWS" = "3/1" ]; }

# ---- class sweep, round 12: the record reads, the push URL read and the status compares (bead mk-z9st.22)
sw_injo() { sw_inj "$@"; touch "$ST/gitfail-out"; }   # as sw_inj, but the real output is shown before the failure
sw_sed() {  # TEXT [SKIP] [out] : the wrapper's sed calls whose arguments contain TEXT fail (after SKIP matching calls pass); "out" prints their output first
  printf '%s' "$1" > "$ST/sedfail"; printf '%s' "${2:-0}" > "$ST/sedfail-skip"; rm -f "$ST/sedfail-n" "$ST/sedfail-out"; [ "${3:-}" != out ] || touch "$ST/sedfail-out"; }
t_swrecrbail() {  # cleanup with an unreadable freeze record still stops every configured timer (the recorded restart's check and its cleanup both fail to read it)
  restore r0a; wg restart r0 > "$B/out.sw" 2>&1 || return 1
  sw_sed 's/^timer //p'
  wg restart r0 > "$B/out.sw" 2>&1; SWT="$?/$(sw_msg 'every configured timer is stopped instead')/$(sw_state)"
  [ "$SWT" = "3/1//1/no/no/" ]; }
t_swrecholds() {  # a recorded restart whose freeze record fails after its output (the timers, then the marker) is undone, not trusted
  local a b
  restore r0a; wg restart r0 > "$B/out.sw" 2>&1 || return 1
  sw_sed 's/^timer //p' 0 out; wg restart r0 > "$B/out.sw" 2>&1; a="$?/$(sw_msg 'the timers it names cannot be checked')/$(sw_state)"
  restore r0a; wg restart r0 > "$B/out.sw" 2>&1 || return 1
  sw_sed 's/^marker //p' 0 out; wg restart r0 > "$B/out.sw" 2>&1; b="$?/$(sw_msg 'its marker cannot be checked')/$(sw_state)"
  SWU="$a;$b"; [ "$SWU" = "3/1//1/no/no/;3/1//1/no/no/" ]; }
t_swstep5() {  # the timers to start are read from the record with its status checked: a read that fails after its output starts no timer
  restore r0a; sw_sed 's/^timer //p' 0 out
  wg restart r0 > "$B/out.sw" 2>&1; SWV="$?/$(sw_msg 'the timers to start are unknown')/$(sw_state)"
  [ "$SWV" = "3/1//1/no/no/" ]; }
t_swfreezerec() {  # a freeze record, or an earlier freeze intent, that fails after its output is not a list to trust
  local a b
  restore fx; stepto preflight freeze || return 1; sw_sed 's/^timer //p' 0 out
  wg freeze > "$B/out.sw" 2>&1; a="$?/$(sw_msg 'whether its timers stay stopped cannot be told')"
  restore fx; stepto preflight || return 1; printf 'timer git-autosync-repair.timer\n' > "$J/gate0-run/freeze-intent"; sw_sed 'freeze-intent' 0 out
  wg freeze > "$B/out.sw" 2>&1; b="$?/$(sw_msg 'the earlier freeze intent cannot be read')/$([ -e "$J/gate0-run/freeze" ] && echo recorded)"
  SWW="$a;$b"; [ "$SWW" = "3/1;3/1/" ]; }
t_swpushurl() {  # the lane's push URL read prints the validated URL and then fails: that is a failed read, not a match
  restore r0a; sw_injo ' remote get-url --push' 1
  wg restart r0 > "$B/out.sw" 2>&1; SWX="$?/$(sw_msg 'cannot read the push URL')/$(sw_state)"
  [ "$SWX" = "3/1//0/no/no/" ]; }
sw_r0prep() { restore fx; stepto preflight freeze || return 1; mkdir -p "$J/p1-pre"; g status --porcelain -uall > "$J/p1-pre/status.all"; }
t_swr0status() {  # R0 without P1a: P1-pre's status record is read, and filtered, with each status checked
  local a b c
  sw_r0prep || return 1; wg restart r0 > "$B/out.sw" 2>&1; a=$(sw_msg 'R0 without P1a')   # control: a readable, equal record passes this check
  sw_r0prep || return 1; chmod 000 "$J/p1-pre/status.all"
  wg restart r0 > "$B/out.sw" 2>&1; b="$?/$(sw_msg 'status record cannot be read')/$(sw_state)"; chmod 644 "$J/p1-pre/status.all"
  sw_r0prep || return 1; printf '%s' 'beads/issues' > "$ST/grepfail"; touch "$ST/grepfail-out"
  wg restart r0 > "$B/out.sw" 2>&1; c="$?/$(sw_msg 'the status cannot be filtered')/$(sw_state)"
  SWY="$a;$b;$c"; [ "$SWY" = "0;3/1//0/no/no/;3/1//0/no/no/" ]; }
t_swmarkfilter() {  # the filter behind the marker rule fails: a filter that fails shows no marker, which is not a clean status
  local a b
  restore r0a; wg restart r0 > "$B/out.sw" 2>&1; a=$(sw_msg 'cannot filter the status for the marker rule')   # control: a working filter passes
  restore r0a; printf '%s' '-x \.git-autosync' > "$ST/grepfail"
  wg restart r0 > "$B/out.sw" 2>&1; b="$?/$(sw_msg 'cannot filter the status for the marker rule')/$(sw_state)"
  SWMF="$a;$b"; [ "$SWMF" = "0;3/1//0/no/no/" ]; }
t_swlsfilesu() {  # the unmerged-entries read fails after its output: an index that cannot be read is not a clean one
  restore fx; sw_injo ' ls-files -u'
  wg preflight > "$B/out.sw" 2>&1; SWAA="$?/$(sw_msg 'cannot read the index')/$([ -d "$J/p0" ] && echo p0)"
  [ "$SWAA" = "3/1/" ]; }
t_swpgs() {  # a read that prints the matching value and then fails is not a match (HEAD's name, origin/main, the tag after P1a)
  local p res=
  for p in ' symbolic-ref -q HEAD|HEAD is not main' ' rev-parse refs/remotes/origin/main|origin/main is not the approved base'; do
    restore fx; sw_injo "${p%%|*}"; wg preflight > "$B/out.sw" 2>&1; res="$res$?/$(sw_msg "${p#*|}")/$([ -d "$J/p0" ] && echo p0);"; done
  restore fx; stepto preflight freeze || return 1; sw_injo '--verify refs/tags/gate0'
  wg capture > "$B/out.sw" 2>&1; res="$res$?/$(sw_msg 're-check: the tag')/$([ -e "$J/gate0-run/captured" ] && echo captured);"
  SWAB="$res"; [ "$SWAB" = "3/1/;3/1/;3/1/;" ]; }
t_swp0laneread() { local t  # a P0 lane record that exists but cannot be read is not an empty tip (the lane has no branch, so its listing is empty too)
  restore r0a; rm -f "$B/drift.txt" "$J/gate0-run/marker" "$R/.git-autosync"
  sed -i 's/^marker .*/marker none/' "$J/gate0-run/freeze"; : > "$J/p0/lane"; chmod 000 "$J/p0/lane"
  for t in $(git --git-dir="$W/lane.git" for-each-ref --format='%(refname)' 'refs/heads/autosync'); do git --git-dir="$W/lane.git" update-ref -d "$t"; done
  GATE0_MACHINE=clavain GATE0_SWEEP="$B/bin/sweep" GATE0_DRIFT_REPORT="$B/drift.txt" wg restart r0 > "$B/out.sw" 2>&1; SWAC="$?/$(sw_msg 'lane record .*cannot be read')/$(sw_state)"; chmod 644 "$J/p0/lane"
  [ "$SWAC" = "3/1//0/no/no/" ]; }
t_swinputs() {  # an approved input that exists but cannot be read is refused before any write, not read as empty
  restore fx; chmod 000 "$J/lane-remote"
  wg preflight > "$B/out.sw" 2>&1; SWAD="$?/$(sw_msg 'an input in J cannot be read')/$([ -d "$J/p0" ] && echo p0)"; chmod 644 "$J/lane-remote"
  [ "$SWAD" = "1/1/" ]; }
t_swsharec() {  # the capture's sha256 record must name exactly the bundle and the W-snapshot: a record that names fewer is not verified file by file
  restore fx; stepto preflight freeze capture || return 1
  grep -v 'wtree.tar' "$J/capture/sha256" > "$B/sha256.new"; cat "$B/sha256.new" > "$J/capture/sha256"
  wg capture > "$B/out.sw" 2>&1; SWAE="$?/$(sw_msg 'does not name exactly main.bundle and wtree.tar')"
  [ "$SWAE" = "3/1" ]; }

t_swrestmark() {  # the restored marker's recorded hash is read with its status: a read that prints the hash and then fails is not a match
  restore r0a; sw_sed 's/^marker //p' 0 out
  wg restart r0 > "$B/out.sw" 2>&1; SWAF="$?/$(sw_msg 'the restored marker differs from the one set aside')/$(sw_state)"
  [ "$SWAF" = "3/1//0/no/no/" ]; }
t_swactlines() {  # the restart set is written from a list built with each stage's status checked: a list that fails after its output is not written, and nothing is stopped
  local a b
  restore fx; stepto preflight || return 1; sw_sed 's/ timer /' 0 out
  wg freeze > "$B/out.sw" 2>&1; a="$?/$(sw_msg 'cannot write the list of timers to restart')/$([ -e "$J/gate0-run/freeze-intent" ] && echo intent)/$(timers)"
  restore fx; stepto preflight || return 1; sw_sed '/^timer /p' 0 out
  wg freeze > "$B/out.sw" 2>&1; b="$?/$(sw_msg 'cannot write the list of timers to restart')/$([ -e "$J/gate0-run/freeze-intent" ] && echo intent)/$(timers)"
  SWAG="$a;$b"; [ "$SWAG" = "3/1//yes/yes;3/1//yes/yes" ]; }
t_swverifyset() {  # the verifier of a sha256 record: two completed digest checks, the last line needing no newline, a wrong digest or a missing file anywhere is a failure
  local fn d res= h1 h2
  fn=$(sed -n '/^verify_set() {/,/^preserve_copy() {/p' "${WG:-$GW}" | sed '$d')
  d=$B/vs; rm -rf "$d"; mkdir -p "$d/capture" "$d/c"; printf a > "$d/c/main.bundle"; printf b > "$d/c/wtree.tar"
  h1=$(sha256sum < "$d/c/main.bundle" | cut -d' ' -f1); h2=$(sha256sum < "$d/c/wtree.tar" | cut -d' ' -f1)
  vs() { ( J=$d; sha() { sha256sum | cut -d' ' -f1; }; eval "$fn"; verify_set "$d/c" ) 2>/dev/null && echo ok || echo no; }
  printf 'main.bundle\t%s\nwtree.tar\t%s\n' "$h1" "$h2" > "$d/capture/sha256"; res="$(vs)/"
  printf 'main.bundle\t%s\nwtree.tar\t%s' "$h1" "$h2" > "$d/capture/sha256"; res="$res$(vs)/"
  printf 'main.bundle\t%s\nwtree.tar\t%s' "$h1" "$h1" > "$d/capture/sha256"; res="$res$(vs)/"
  printf 'main.bundle\t%s\nwtree.tar\t%s\n' "$h2" "$h2" > "$d/capture/sha256"; res="$res$(vs)/"
  printf 'main.bundle\t%s' "$h1" > "$d/capture/sha256"; res="$res$(vs)/"
  printf 'main.bundle\t%s\nwtree.tar\t%s\nwtree.manifest\t%s\n' "$h1" "$h2" "$h2" > "$d/capture/sha256"; res="$res$(vs)/"
  printf 'main.bundle\t%s\nwtree.tar\t%s\n' "$h1" "$h2" > "$d/capture/sha256"; rm -f "$d/c/wtree.tar"; res="$res$(vs)/"
  SWAH=$res; [ "$SWAH" = "ok/ok/no/no/no/no/no/" ]; }
t_swsharecterm() {  # a capture whose sha256 record has no final newline is still verified file by file, the preservation copy it would replace is never overwritten by a bad one, and a good one still passes
  local a b c p0 PD=$W/pres/mA-$O
  restore fx; stepto preflight freeze capture || return 1
  printf '%s' "$(cat "$J/capture/sha256")" > "$J/capture/sha256"; echo x >> "$J/capture/wtree.tar"
  wg capture > "$B/out.sw" 2>&1; a="$?/$(sw_msg 'does not match its sha256 record')"
  restore fx; stepto preflight freeze capture || return 1; p0=$(sha < "$PD/wtree.tar")
  echo x >> "$J/capture/wtree.tar"
  wg capture > "$B/out.sw" 2>&1; b="$?/$(sw_msg 'does not match its sha256 record')/$([ "$(sha < "$PD/wtree.tar")" = "$p0" ] && echo intact)/$(ls "$PD" | grep -c tmp)"
  restore fx; stepto preflight freeze capture || return 1
  printf '%s' "$(cat "$J/capture/sha256")" > "$J/capture/sha256"
  wg capture > "$B/out.sw" 2>&1; c="$?"
  SWAI="$a;$b;$c"; [ "$SWAI" = "3/1;3/1/intact/0;0" ]; }

t_swrestover() {  # restoring the set-aside marker over other bytes in the checkout keeps those bytes first: the restore never replaces a marker it has not kept
  local f1 f2 d res= h
  f1=$(sed -n '/^keep_unexpected_marker() {/,/^move_marker_aside() {/p' "${WG:-$GW}" | sed '$d'); f2=$(sed -n '/^restore_marker() {/,/^lane_refs() {/p' "${WG:-$GW}" | sed '$d')
  d=$B/ro; rm -rf "$d"; mkdir -p "$d/G" "$d/R"; printf 'LANE=1\nmine\n' > "$d/G/marker"; h=$(sha < "$d/G/marker"); printf 'marker %s\n' "$h" > "$d/G/freeze"
  printf 'LANE=1\nother\n' > "$d/R/.git-autosync"; h=$(sha < "$d/R/.git-autosync")
  ( G=$d/G; ROOT=$d/R; sha() { sha256sum | cut -d' ' -f1; }; say() { :; }; stop() { exit 3; }; rec_marker() { sed -n 's/^marker //p' "$G/freeze"; }; eval "$f1"; eval "$f2"; restore_marker ) 2>/dev/null; res="$?"
  res="$res/$(cmp -s "$d/G/marker" "$d/R/.git-autosync" && echo restored)/$(cmp -s "$d/G/marker.unexpected.$h" <(printf 'LANE=1\nother\n') && echo kept)"
  SWAJ=$res; [ "$SWAJ" = "0/restored/kept" ]; }

t_swclavmark() {  # a freeze record that cannot be read is not a record that names a marker: the Clavain restart stops before the marker path is taken
  restore r0a; rm -f "$B/drift.txt"; chmod 000 "$J/gate0-run/freeze"
  GATE0_MACHINE=clavain GATE0_SWEEP="$B/bin/sweep" GATE0_DRIFT_REPORT="$B/drift.txt" wg restart r0 > "$B/out.sw" 2>&1; SWAK="$?/$(sw_msg 'whether a marker was set aside cannot be told')/$(sw_state)"; chmod 644 "$J/gate0-run/freeze"
  [ "$SWAK" = "3/1//0/no/no/" ]; }
t_swobserver() {  # the test's own before/after observers fail closed: two failed observations are never "nothing changed", a listing that fails after its output included
  local a b c d e f g2 h i j k l
  restore fx
  a=$(R=$B/nowhere ckfp 2>/dev/null); b=$(R=$B/nowhere ckfp 2>/dev/null); c=$(J=$B/nowhere jfp 2>/dev/null); d=$(J=$B/nowhere jfp 2>/dev/null); e=$(W=$B/nowhere lanerefs 2>/dev/null); f=$(W=$B/nowhere lanerefs 2>/dev/null)
  g2=$(find() { command find "$@"; return 1; }; jfp 2>/dev/null); h=$(find() { command find "$@"; return 1; }; jfp 2>/dev/null)
  wr "$B/dgfile" content; printf '%s' "$B/dgfile" > "$ST/fail-sha"; i=$(PATH="$B/stub:$PATH" dg "$B/dgfile" 2>/dev/null); j=$(PATH="$B/stub:$PATH" dg "$B/dgfile" 2>/dev/null); rm -f "$ST/fail-sha"   # a digest that fails: a fresh sentinel each time
  printf '%s' 'pipe:*' > "$ST/fail-sha"; k=$(echo x | PATH="$B/stub:$PATH" sha 2>/dev/null); l=$(echo x | PATH="$B/stub:$PATH" sha 2>/dev/null); rm -f "$ST/fail-sha"   # the aggregate hash (stdin a pipe) that fails: the same
  SWAL="$([ "$a" != "$b" ] && echo differ)/$([ "$c" != "$d" ] && echo differ)/$([ "$e" != "$f" ] && echo differ)/$([ "$(ckfp)" = "$(ckfp)" ] && echo same)/$([ "$(jfp)" = "$(jfp)" ] && echo same)/$([ "$g2" != "$h" ] && echo differ)/$([ "$i" != "$j" ] && echo differ)/$([ "$(dg "$B/dgfile")" = "$(dg "$B/dgfile")" ] && echo same)/$([ "$k" != "$l" ] && echo differ)"
  [ "$SWAL" = "differ/differ/differ/same/same/differ/differ/same/differ" ]; }
t_swidfail() {  # a user id that cannot be read is not "not root": the wrapper stops before it makes a journal or runs git
  local m r=""
  for m in none after word; do
    restore fx; printf '%s' "$m" > "$ST/idfail"
    wg preflight > "$B/out.sw" 2>&1; r="$r$?/$(sw_msg 'cannot establish the user id')/$([ -e "$J/gate0-run" ] && echo journal);"
    rm -f "$ST/idfail"
  done
  SWAP=$r; [ "$SWAP" = "1/1/;1/1/;1/1/;" ]; }
t_swprocenum() {  # a /proc directory that can be entered but not listed leaves the glob pattern in the loop: that is not "no agents"
  local pf=$B/pf2 h=$B/procfix2.sh o
  [ "$(id -u)" != 0 ] || return 0   # root lists any directory: the case cannot be built
  { echo 'ROOT=$1; LOG=$2; mkdir -p "$GATE0_PROCFS/$$"; ln -sfn / "$GATE0_PROCFS/$$/cwd"; chmod 111 "$GATE0_PROCFS"'
    sed -n '/^under_self() {/,/^bd_writers() {/{/^bd_writers() {/!p;}' "${WG:-$GW}"; echo 'agents_in_root; echo "rc=$?"; chmod 755 "$GATE0_PROCFS"'; } > "$h"
  chmod 755 "$pf" 2>/dev/null; rm -rf -- "${pf:?}"; mkdir -p "$pf/self"; rm -f -- "$B/unr.log"
  o=$(env GATE0_PROCFS="$pf" GATE0_UNINSPECTABLE_UIDS="" bash "$h" "$R" "$B/unr.log" 2>&1)
  chmod 755 "$pf" 2>/dev/null; SWAQ=$(printf '%s\n' "$o" | sed -n 's/^rc=//p'); [ "$SWAQ" = 2 ]; }
t_swprecommit() {  # the private pre-commit hook reads the staged-path listing with its status: a listing that fails, after an approved path or none, is a refusal
  local hook=${HOOK:-$HERE/../git-internal-hooks/pre-commit} d=$B/pc m p rest rc want got="" exp=""
  rm -rf -- "${d:?}"; mkdir -p "$d/stub" "$d/gd/info"; printf '# approved\nok/a\ndir/\n' > "$d/gd/info/approved-paths"
  cat > "$d/stub/git" <<EOF
#!/bin/bash
case "\$1" in rev-parse) echo "$d/gd" ;; diff) cat "$d/staged" 2>/dev/null; exit \$(cat "$d/rc" 2>/dev/null || echo 0) ;; *) exit 2 ;; esac
EOF
  chmod +x "$d/stub/git"
  for m in "ok/a|0|0" "bad|0|1" "ok/a|128|1" "|128|1" "dir/x|0|0"; do   # path|status of the listing|expected hook status
    p=${m%%|*}; rest=${m#*|}; rc=${rest%%|*}; want=${rest#*|}
    if [ -n "$p" ]; then printf '%s\0' "$p" > "$d/staged"; else : > "$d/staged"; fi; printf '%s' "$rc" > "$d/rc"
    PATH="$d/stub:$PATH" bash "$hook" > /dev/null 2>&1; got="$got$? "; exp="$exp$want "
  done
  SWAR=$got; [ "$got" = "$exp" ] && [ "$exp" = "0 1 1 1 0 " ]; }
t_swnoprocsub() {  # the overlay driver and its hook templates feed no loop through a process substitution, whose status is lost
  SWAS=$(cd "$HERE/.." && grep -c 'done < <(' git-internal git-internal-hooks/pre-commit git-internal-hooks/pre-push | tr '\n' ' ')
  [ "$SWAS" = "git-internal:0 git-internal-hooks/pre-commit:0 git-internal-hooks/pre-push:0 " ]; }
t_swgi() {  # the overlay driver reads the unmerged-entry list and the remote-ref list with their status: a failed read is a refusal, not "none"
  local gi=${GI:-$HERE/../git-internal} d=$B/gif r="" c rc
  rm -rf -- "${d:?}"; mkdir -p "$d/gd"
  for c in pre-ok pre-fail fold-ok fold-fail fold-failout; do   # case names: which read fails, and whether it prints before it fails
    ( GD=$d/gd; FOLDREF=refs/x; STATE=$d/state; rm -f -- "$d/lsfail" "$d/fefail" "$d/feout"
      case $c in pre-fail) : > "$d/lsfail" ;; fold-fail) : > "$d/fefail" ;; fold-failout) : > "$d/fefail"; : > "$d/feout" ;; esac
      gi() { case $1 in ls-files) [ ! -e "$d/lsfail" ] ;; for-each-ref) [ -e "$d/feout" ] && echo refs/remotes/origin/main; [ ! -e "$d/fefail" ] ;; *) true ;; esac; }
      die() { exit "$1"; }; host() { echo h; }; put() { :; }; crash_point() { :; }
      eval "$(sed -n '/^precheck() {/,/^}/p;/^fold() {/,/^}/p' "$gi")" || exit 99
      case $c in pre-*) precheck ;; *) fold h ;; esac; exit 0 ) > /dev/null 2>&1; rc=$?
    r="$r$c=$rc;"
  done
  SWAT=$r; [ "$SWAT" = "pre-ok=0;pre-fail=4;fold-ok=0;fold-fail=6;fold-failout=6;" ]; }
t_swignore() {  # the git dir of an interrupted overlay install (.git-internal.new, a bare clone) is ignored like .git-internal: a public `git add -A` cannot stage it
  local gi=${GITIGNORE:-$HERE/../../.gitignore} d=$B/ign l
  rm -rf -- "${d:?}"; mkdir -p "$d"; git -C "$d" init -q && cp "$gi" "$d/.gitignore" || return 1
  git init -q --bare "$d/.git-internal.new" && git init -q --bare "$d/.git-internal" || return 1
  git -C "$d" add -A > /dev/null 2>&1; l=$(git -C "$d" ls-files) || return 1
  SWAU=$(printf '%s' "$l" | tr '\n' ' '); [ "$SWAU" = ".gitignore" ]; }
t_swfreezerep() {  # a repeated freeze checks the whole invariant before it says the freeze holds: a marker back after a "none" record, or a service active again, is a STOP and keeps the intent
  local r="" c
  for c in same marker svc; do
    restore fx; stepto preflight freeze || return 1
    printf 'timer git-autosync-repair.timer\n' > "$J/gate0-run/freeze-intent"
    case $c in
      marker) rm -f "$J/gate0-run/marker"; sed -i 's/^marker .*/marker none/' "$J/gate0-run/freeze"; printf 'x\n' > "$R/.git-autosync" ;;
      svc) touch "$ST/units/git-autosync-promote.service" ;;
    esac
    wg freeze > "$B/out.sw" 2>&1; r="$r$?/$(sw_msg 'freeze already holds')/$(sw_msg 'freeze no longer holds')/$([ -e "$J/gate0-run/freeze-intent" ] && echo intent);"
  done
  SWAV=$r; [ "$SWAV" = "0/1/0/;3/0/1/intent;3/0/1/intent;" ]; }
t_swpushurls() {  # a lane remote with a second push URL is not the validated destination: a push goes to every push URL
  local res= m
  for m in server clavain; do
    restore r0a; g config --add remote.lane.pushurl "file://$W/lane.git"; g config --add remote.lane.pushurl "file://$W/pub.git"
    GATE0_MACHINE=$m GATE0_SWEEP="$B/bin/sweep" GATE0_DRIFT_REPORT="$B/drift.txt" wg restart r0 > "$B/out.sw" 2>&1; res="$res$?/$(sw_msg 'push URL of lane is not the one just validated')/$(sw_state);"
  done
  SWAW=$res; [ "$SWAW" = "3/1//0/no/no/;3/1//0/no/no/;" ]; }
t_swcheckro() {  # --check never writes: every --check phase, from every state a freeze or restart can leave, changes nothing in the checkout, the journal, the lane or the units (the review's case: a completed restart, the live marker removed, the earlier attempt's copy still in the journal)
  local st ph c j l t rc bad="" ran=0
  for st in start restarted nomarker intent; do
    restore r0a
    case $st in
      start) ;;
      *) wg restart r0 > "$B/out.ro" 2>&1 || { echo "  FAIL t_swcheckro: restart r0 for state $st exited $?"; return 1; } ;;
    esac
    case $st in nomarker|intent) rm -f -- "$R/.git-autosync" ;; esac
    [ $st != intent ] || printf 'timer git-autosync-repair.timer\ntimer git-autosync-promote.timer\n' > "$J/gate0-run/freeze-intent"
    if [ $st = nomarker ]; then [ -e "$J/gate0-run/marker" ] && [ ! -e "$R/.git-autosync" ] && ls "$J/gate0-run" | grep -q '^restarted-' || { echo "  FAIL t_swcheckro: state nomarker is not the state under test"; return 1; }; fi
    for ph in preflight freeze capture run rollback "restart r0" "restart p10" "restart r6"; do
      c=$(ckfp); j=$(jfp); l=$(lanerefs); t=$(timers)
      wg --check $ph > "$B/out.ro" 2>&1; rc=$?; ran=$((ran+1))
      [ "$(ckfp)/$(jfp)/$(lanerefs)/$(timers)" = "$c/$j/$l/$t" ] || bad="$bad $st:$ph"
    done
  done
  for st in "fresh:" "frozen:preflight freeze" "captured:preflight freeze capture"; do   # the states before a rollback, where each phase would really run (a wrapper that ran it in --check would write)
    restore fx; [ -z "${st#*:}" ] || stepto ${st#*:} || return 1
    for ph in preflight freeze capture run rollback "restart r0" "restart p10" "restart r6"; do
      c=$(ckfp); j=$(jfp); l=$(lanerefs); t=$(timers)
      wg --check $ph > "$B/out.ro" 2>&1; rc=$?; ran=$((ran+1))
      [ "$(ckfp)/$(jfp)/$(lanerefs)/$(timers)" = "$c/$j/$l/$t" ] || bad="$bad ${st%%:*}:$ph"
    done
  done
  SWRO="${bad:-none}/$ran"; [ "$SWRO" = "none/56" ]; }
t_swgitenv() {  # git's repository, work tree, index and configuration can come from the environment, and the work tree from core.worktree: none of them may point a git command of the wrapper, or a step it runs, away from the validated checkout (the review's case: GIT_WORK_TREE at another copy while the freeze and the preservation look at GATE0_ROOT)
  restore fx; local o=$W/other h oh os rc1 rc2 rc3 ph; SWGE=
  cp -a "$R" "$o" && git -C "$o" -c user.email=t@example.invalid -c user.name=t commit -q --allow-empty -m other || { echo "  FAIL t_swgitenv: cannot make another copy"; return 1; }
  h=$(g rev-parse HEAD) && oh=$(git -C "$o" rev-parse HEAD) && [ -n "$h" ] && [ "$h" != "$oh" ] || { echo "  FAIL t_swgitenv: the copy has the checkout's head"; return 1; }
  GIT_DIR=$o/.git GIT_WORK_TREE=$o GIT_INDEX_FILE=$o/.git/index GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.worktree GIT_CONFIG_VALUE_0=$o wg preflight > "$B/out.sw" 2>&1; rc1=$?
  ph=$(sed -n 's/^base .* head \([0-9a-f]*\) host .*/\1/p' "$J/gate0-run/preflight" 2>/dev/null)
  restore fx; cp -a "$R" "$o" && git -C "$o" -c user.email=t@example.invalid -c user.name=t commit -q --allow-empty -m other || { echo "  FAIL t_swgitenv: cannot make another copy"; return 1; }
  oh=$(git -C "$o" rev-parse HEAD); os=$(GIT_OPTIONAL_LOCKS=0 git -C "$o" status --porcelain); git -C "$R" config core.worktree "$o"; wg preflight > "$B/out.sw" 2>&1; rc2=$?
  SWGE="$rc1/$([ "$ph" = "$h" ] && echo head)/$rc2/$(sw_msg 'is not GATE0_ROOT itself')/$([ -e "$J/gate0-run/preflight" ] && echo wrote)/$([ "$(git -C "$o" rev-parse HEAD)" = "$oh" ] && [ "$(GIT_OPTIONAL_LOCKS=0 git -C "$o" status --porcelain)" = "$os" ] && echo other-untouched)"
  restore fx; cp -a "$R" "$o" || { echo "  FAIL t_swgitenv: cannot make another copy"; return 1; }; mkdir -p "$ST"; printf '%s' "$o/.git" > "$ST/gitdirenv"
  wg preflight > "$B/out.sw" 2>&1; rc3=$?
  SWGE="$SWGE/$rc3/$(sw_msg "is not the one GATE0_ROOT/.git names")"
  [ "$SWGE" = "0/head/1/1//other-untouched/1/1" ]; }
t_swgitvars() {  # every variable git reads to find its repository, work tree, index, objects, namespace, configuration or programs is gone before any git process of the wrapper, or of a step it runs, starts; a setting that is not git's own location (identity, credentials, the user-level config file) is left alone
  local kv v bad="" rc n; SWGV=
  for kv in GIT_DIR=x GIT_WORK_TREE=x GIT_INDEX_FILE=x GIT_OBJECT_DIRECTORY=x GIT_ALTERNATE_OBJECT_DIRECTORIES=x GIT_COMMON_DIR=x GIT_NAMESPACE=x GIT_CEILING_DIRECTORIES=x \
            GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.worktree GIT_CONFIG_VALUE_0=x GIT_CONFIG_PARAMETERS=x GIT_CONFIG=x GIT_CONFIG_SYSTEM=x GIT_EXEC_PATH=x GIT_PREFIX=x \
            GIT_LITERAL_PATHSPECS=1 GIT_NO_REPLACE_OBJECTS=1 GIT_REPLACE_REF_BASE=x GIT_SHALLOW_FILE=x GIT_GRAFT_FILE=x GIT_DISCOVERY_ACROSS_FILESYSTEM=1 GIT_ATTR_SOURCE=x \
            GIT_AUTHOR_NAME=kept; do
    v=${kv%%=*}; restore fx; mkdir -p "$ST"; : > "$ST/gitenv-log"
    case $v in
      GIT_DIR|GIT_WORK_TREE|GIT_COMMON_DIR|GIT_CONFIG|GIT_CONFIG_SYSTEM|GIT_CONFIG_VALUE_0) kv=$v=$W/nowhere ;;
      GIT_CONFIG_PARAMETERS) kv="$v='core.worktree=$W/nowhere'" ;;
    esac
    ( export "$kv"; wg preflight > "$B/out.sw" 2>&1 ); rc=$?
    n=$(grep -c . "$ST/gitenv-log")
    if [ $v = GIT_AUTHOR_NAME ]; then   # the control that the filter is not "everything"
      { [ $rc = 0 ] && grep -qx "$v" "$ST/gitenv-log"; } || bad="$bad $v(removed,rc=$rc)"
    else
      { [ $rc = 0 ] && [ "$n" -gt 0 ] && ! grep -qx "$v" "$ST/gitenv-log"; } || bad="$bad $v(rc=$rc,calls=$n)"
    fi
  done
  rm -f -- "$ST/gitenv-log"; SWGV="${bad:-none}"; [ "$SWGV" = none ]; }
t_swgitmid() {  # the checkout can be pointed elsewhere after the first check (core.worktree written between two git calls): the next use of git on it checks again and stops, with nothing further done
  local o=$W/other k rc bad="" tot; SWGM=
  restore fx; mkdir -p "$ST"; : > "$ST/gitenv-log"; wg preflight > "$B/out.sw" 2>&1; rc=$?; tot=$(grep -c '^GIT_OPTIONAL_LOCKS$' "$ST/gitenv-log")
  [ $rc = 0 ] && [ "$tot" -gt 12 ] || { echo "  FAIL t_swgitmid: the plain run (rc=$rc, $tot git processes)"; return 1; }
  for k in 8 $((tot/3)) $((tot/2)) $((tot*2/3)) $((tot-3)); do
    restore fx; mkdir -p "$ST"; cp -a "$R" "$o" 2>/dev/null || { echo "  FAIL t_swgitmid: cannot make another copy"; return 1; }
    printf '%s\n%s\n%s\n' "$k" "$R" "$o" > "$ST/gitredir"
    wg preflight > "$B/out.sw" 2>&1; rc=$?
    { [ $rc != 0 ] && [ "$(sw_msg 'is not GATE0_ROOT itself')" -ge 1 ] && [ ! -e "$J/gate0-run/preflight" ]; } || bad="$bad $k(rc=$rc,msg=$(sw_msg 'is not GATE0_ROOT itself'))"
  done
  SWGM="${bad:-none}"; [ "$SWGM" = none ]; }
t_swgitgi() {  # the overlay driver starts no git with a repository, work tree, index or configuration from the environment; its own settings and identity are kept
  local gi=${GI:-$HERE/../git-internal} d=$B/gigit bad="" kv v n; SWGI=
  rm -rf -- "${d:?}"; mkdir -p "$d/bin"
  printf '#!/bin/sh\nenv | grep "^GIT_" | sed "s/=.*//" >> "%s/log"\nexec %s "$@"\n' "$d" "$REALGIT" > "$d/bin/git"; chmod +x "$d/bin/git"
  for kv in GIT_DIR=$d/x GIT_WORK_TREE=$d/x GIT_INDEX_FILE=$d/x GIT_OBJECT_DIRECTORY=$d/x GIT_ALTERNATE_OBJECT_DIRECTORIES=$d/x GIT_COMMON_DIR=$d/x GIT_NAMESPACE=x \
            GIT_CEILING_DIRECTORIES=$d GIT_CONFIG_COUNT=1 GIT_CONFIG_PARAMETERS=x GIT_CONFIG=x GIT_CONFIG_SYSTEM=x GIT_EXEC_PATH=$d/x GIT_PREFIX=x GIT_AUTHOR_NAME=kept; do
    v=${kv%%=*}; : > "$d/log"
    ( export "$kv" GIT_INTERNAL_PATH="$d/bin:/usr/local/bin:/usr/bin:/bin"; "$gi" doctor > "$d/out" 2>&1 ); n=$(grep -c . "$d/log")
    if [ $v = GIT_AUTHOR_NAME ]; then { [ "$n" -gt 0 ] && grep -qx "$v" "$d/log"; } || bad="$bad $v(removed)"
    else { [ "$n" -gt 0 ] && ! grep -qx "$v" "$d/log"; } || bad="$bad $v(calls=$n)"; fi
  done
  SWGI="${bad:-none}"; [ "$SWGI" = none ]; }
t_swgitrst() {  # a restart past its marker restore, with git then pointed elsewhere at EVERY git call made while the marker is live: the run stops and undoes the restart first (every timer and the repair service stopped, the marker aside, no completion record), wherever the redirect lands
  local o=$W/other k rc bad="" n=0 st fired=0 last
  restore r0a; rm -f "$ST/units/git-autosync-repair.service"; cp -a "$R" "$o" 2>/dev/null || { echo "  FAIL t_swgitrst: cannot make another copy"; return 1; }
  printf '%s\n%s\n%s\n' "$R" "$o" 99999 > "$ST/gitredir-marker"; touch "$ST/svc-stays-active"
  wg restart r0 > "$B/out.sw" 2>&1; rc=$?; n=$(cat "$ST/gitredir-marker-c" 2>/dev/null || echo 0)
  rm -f "$ST/gitredir-marker" "$ST/gitredir-marker-c" "$ST/gitredir-marker-done" "$ST/svc-stays-active"
  { [ $rc = 0 ] && [ "$n" -ge 8 ]; } || { SWGR="count(rc=$rc,n=$n)"; return 1; }
  for ((k=0; k<n; k++)); do
    restore r0a; rm -f "$ST/units/git-autosync-repair.service"; rm -rf "$o"; cp -a "$R" "$o" 2>/dev/null || { echo "  FAIL t_swgitrst: cannot make another copy"; return 1; }
    printf '%s\n%s\n%s\n' "$R" "$o" "$k" > "$ST/gitredir-marker"; touch "$ST/svc-stays-active"
    wg restart r0 > "$B/out.sw" 2>&1; rc=$?
    if [ -e "$ST/gitredir-marker-done" ]; then fired=$((fired+1))
      st="$(timers)/$([ -e "$ST/units/git-autosync-repair.service" ] && echo svc)/$([ -e "$R/.git-autosync" ] && echo marker)/$([ -e "$J/gate0-run/restarted-r0" ] && echo recorded)/$(ls "$J/gate0-run" | grep -c '^restarting-')"
      if [ $rc = 3 ]; then { [ "$st" = "no/no////0" ] && [ "$(sw_msg 'git no longer shows the validated checkout during the restart')" -ge 1 ]; } || bad="$bad $k(rc=$rc,$st)"
      else { [ $rc = 0 ] && [ "$st" = "yes/yes/svc/marker/recorded/0" ]; } || bad="$bad $k(rc=$rc,$st)"; fi   # a git call after the restart is complete comes too late to matter: it is recorded, the marker is back, the timers run
    else bad="$bad $k(not-fired)"; fi
    rm -f "$ST/gitredir-marker" "$ST/gitredir-marker-c" "$ST/gitredir-marker-done" "$ST/svc-stays-active"
  done
  SWGR="${bad:-none}(calls=$n)"; [ "$fired" = "$n" ] && [ -z "$bad" ]; }
t_swgitlink() {  # a linked worktree's git directory is found through its gitdir link and its commondir file: a read of either that prints a path and then fails, or fails outright, is no binding, at the start and at a later use
  restore fx; local R0=$R cm bad="" rc k out
  git -C "$R0" checkout -q --detach && git -C "$R0" worktree add "$W/wt" main > "$B/out.gc" 2>&1 || { echo "  FAIL t_swgitlink: cannot add a linked worktree"; return 1; }
  R=$W/wt; SWGL=
  for k in "gitdir: 0 0" "gitdir: 1 0" "commondir 0 0" "commondir 1 0" "gitdir: 0 4" "commondir 0 4"; do
    set -- $k; : > "$B/out.sw"; rm -f "$ST/sedfail" "$ST/sedfail-n" "$ST/sedfail-out" "$ST/sedfail-skip"
    printf '%s' "$1" > "$ST/sedfail"; [ "$2" = 0 ] || : > "$ST/sedfail-out"; printf '%s' "$3" > "$ST/sedfail-skip"
    wg --check preflight >> "$B/out.sw" 2>&1; rc=$?
    { [ $rc != 0 ] && [ "$(sw_msg 'cannot be read\|readable gitdir link')" -ge 1 ]; } || bad="$bad [$k](rc=$rc,msg=$(sw_msg 'cannot be read\|readable gitdir link'),n=$(cat "$ST/sedfail-n" 2>/dev/null),$(tail -n 2 "$B/out.sw" | tr '\n' '|' | cut -c1-200))"
  done
  rm -f "$ST/sedfail" "$ST/sedfail-n" "$ST/sedfail-out" "$ST/sedfail-skip"
  : > "$B/out.sw"; wg --check preflight >> "$B/out.sw" 2>&1   # the control: with no failure injected the binding itself is not what stops the run
  [ "$(sw_msg 'cannot be read\|readable gitdir link')" = 0 ] || bad="$bad control"
  R=$R0; SWGL="${bad:-none}"; [ "$SWGL" = none ]; }
t_swgitfailall() {  # each git call of a restart in turn fails (the wrapper's own, counted in the order they are made): the run is either undone (every timer and the repair service stopped, the marker aside, no completion record) or complete; a failure the run goes on past is only one of the reads that may fail without a decision resting on it
  local k n rc bad="" st safe="no/no////0" done_="yes/yes/svc/marker/recorded/0" a
  restore r0a; rm -f "$ST/units/git-autosync-repair.service"; touch "$ST/svc-stays-active" "$ST/gitargs-log"; sw_inj ' ' 99999
  wg restart r0 > "$B/out.sw" 2>&1; rc=$?; n=$(cat "$ST/gitfail-n" 2>/dev/null || echo 0); cp "$ST/gitargs-log" "$B/gitargs.txt"
  rm -f "$ST/gitfail" "$ST/gitfail-n" "$ST/gitfail-skip" "$ST/gitargs-log" "$ST/svc-stays-active"
  { [ $rc = 0 ] && [ "$n" -ge 20 ] && [ "$(wc -l < "$B/gitargs.txt")" = "$n" ]; } || { SWGF="count(rc=$rc,n=$n)"; return 1; }
  for ((k=0; k<n; k++)); do
    restore r0a; rm -f "$ST/units/git-autosync-repair.service"; touch "$ST/svc-stays-active"; sw_inj ' ' $k
    wg restart r0 > "$B/out.sw" 2>&1; rc=$?
    st="$(timers)/$([ -e "$ST/units/git-autosync-repair.service" ] && echo svc)/$([ -e "$R/.git-autosync" ] && echo marker)/$([ -e "$J/gate0-run/restarted-r0" ] && echo recorded)/$(ls "$J/gate0-run" | grep -c '^restarting-')"
    a=$(sed -n "$((k+1))p" "$B/gitargs.txt")
    if [ $rc != 0 ]; then { [ "$st" = "$safe" ] || [ "$st" = "$done_" ]; } || bad="$bad $k[$a](rc=$rc,$st)"
    else { [ "$st" = "$done_" ] && case " $a " in *" config core.hooksPath "*|*" --git-path hooks "*) true ;; *) false ;; esac; } || bad="$bad $k[$a](went on, rc=$rc,$st)"; fi
    rm -f "$ST/gitfail" "$ST/gitfail-n" "$ST/gitfail-skip" "$ST/svc-stays-active"
  done
  SWGF="${bad:-none}(calls=$n)"; [ -z "$bad" ]; }
t_swexitclean() {  # a restart cut off by anything but rbail (a stop after the record is written, a signal while the service runs) is undone by the EXIT trap: no record, nothing running, marker aside, a failed exit
  local res= rc i pid rcount='find "$J/gate0-run" -maxdepth 1 -name restarting-\* | wc -l'
  restore r0a; : > "$B/nopause"
  GATE0_MACHINE=clavain GATE0_SWEEP="$B/bin/sweep" GATE0_DRIFT_REPORT="$B/drift.txt" wg restart r0 > "$B/out.sw" 2>&1; rc=$?
  res="$rc/$(sw_msg 'the automations are paused')/$(sw_state)/$(eval "$rcount")"; rm -f "$B/nopause"
  restore r0a; touch "$ST/start-hang" "$ST/svc-stays-active"; : > "$B/tell.log"
  wg restart r0 > "$B/out.sw" 2>&1 &
  for i in $(seq 1 600); do [ -s "$ST/start-hung" ] && break; sleep 0.1; done   # non-empty: the stub creates the file before it writes the pid
  if [ -s "$ST/start-hung" ]; then pid=$(cat "$ST/start-hung"); kill -TERM "$pid"; fi
  touch "$ST/start-release"; wait $!; rc=$?
  res="$res;$rc/$(sw_state)/$(eval "$rcount")/$([ -e "$ST/units/git-autosync-repair.service" ] && echo svc)/$([ -e "$J/gate0-run/marker" ] && echo aside)"
  res="$res/$(tail -n 1 "$B/tell.log" | grep -c -- '--result failed --step restart')"
  restore fx; stepto preflight || return 1; touch "$ST/stop-hang"; : > "$B/tell.log"   # a signal outside a restart: still a failed exit, and the report says so
  wg freeze > "$B/out.sw" 2>&1 &
  for i in $(seq 1 600); do [ -s "$ST/stop-hung" ] && break; sleep 0.1; done
  if [ -s "$ST/stop-hung" ]; then pid=$(cat "$ST/stop-hung"); kill -TERM "$pid"; fi
  touch "$ST/stop-release"; wait $!; rc=$?; rm -f "$ST/stop-hang" "$ST/stop-hung" "$ST/stop-release"
  res="$res;$rc/$(tail -n 1 "$B/tell.log" | grep -c -- '--result failed --step freeze')"
  SWEC=$res; [ "$SWEC" = "3/1//0/no/no//0;143//1/no/no//0//aside/1;143/1" ] || { echo "    t_swexitclean got: $SWEC"; return 1; }; }
t_swrefreezegone() {  # a new freeze after a completed restart is a new attempt: a marker the operator removed meanwhile is not recorded from the earlier attempt's copy, so the next restart does not put it back
  local r="" m
  restore r0a; wg restart r0 > "$B/out.sw" 2>&1; r="$?/$([ -e "$J/gate0-run/marker" ] && echo copy)/$([ -e "$R/.git-autosync" ] && echo live);"
  rm -f -- "$R/.git-autosync"
  wg freeze >> "$B/out.sw" 2>&1; r="$r$?/$(grep -c '^marker none$' "$J/gate0-run/freeze")/$([ -e "$J/gate0-run/marker" ] && echo copy)/$(ls "$J/gate0-run" | grep -c '^marker\.earlier\.');"
  wg restart r0 >> "$B/out.sw" 2>&1; r="$r$?/$([ -e "$R/.git-autosync" ] && echo marker)"
  restore r0a; wg restart r0 >> "$B/out.sw" 2>&1   # an interrupted new freeze (its intent exists, the live marker is already aside) is recovered, not a new attempt: its marker stays the recorded one
  printf 'timer git-autosync-repair.timer\ntimer git-autosync-promote.timer\n' > "$J/gate0-run/freeze-intent"; rm -f -- "$R/.git-autosync"
  wg freeze >> "$B/out.sw" 2>&1; r="$r;$?/$(grep -c '^marker none$' "$J/gate0-run/freeze")/$([ -e "$J/gate0-run/marker" ] && echo copy)/$(ls "$J/gate0-run" | grep -c '^marker\.earlier\.')"
  SWAX=$r; [ "$SWAX" = "0/copy/live;0/1//1;0/;0/0/copy/0" ]; }
t_swgitidx() {  # the overlay driver's finish-the-recorded-step check reads the index tree and both recorded trees with their status: a read that prints a tree and then fails is a STOP, not a match
  local gi=${GI:-$HERE/../git-internal} d=$B/gix r="" c rc m
  rm -rf -- "${d:?}"; mkdir -p "$d"
  for c in ok wt ot nt; do
    ( ROOT=$d; GD=$d/gd; INTENT=$d/intent; WT=T0; [ $c = nt ] && WT=T1
      gi() { case $1 in symbolic-ref) true ;;
        rev-parse) case $* in *"--verify HEAD") echo OLD ;; *"OLD^{tree}") echo T0; [ $c != ot ] ;; *"NEW^{tree}") echo T1; [ $c != nt ] ;; esac ;;
        write-tree) echo "$WT"; [ $c != wt ] ;; *) true ;; esac; }
      changes() { return 1; }
      eval "$(sed -n '/^forward() {/,/^}/p' "$gi")" || exit 99
      forward sync OLD NEW 2> "$d/err"; echo "$?" > "$d/rc" )
    rc=$(cat "$d/rc" 2>/dev/null); m=other; grep -q 'cannot read the index tree' "$d/err" && m=tree; grep -q 'cannot list the changes' "$d/err" && m=changes
    r="$r$c=$rc/$m;"
  done
  SWAY=$r; [ "$SWAY" = "ok=10/changes;wt=10/tree;ot=10/tree;nt=10/tree;" ]; }
t_swresolve() {  # resolve reads a resolved file for conflict markers with the status of the read: markers refuse, none go on, and a failed read is a STOP that records nothing
  local gi=${GI:-$HERE/../git-internal} d=$B/gir r="" c rc m
  rm -rf -- "${d:?}"; mkdir -p "$d/root" "$d/gd"; printf 'a\n' > "$d/root/f.txt"; printf 'H F R origin/main\n' > "$d/state"
  for c in marked clean unread mode; do
    ( ROOT=$d/root; GD=$d/gd; STATE=$d/state; FOLDREF=refs/x
      if [ $c = marked ]; then printf '<<<<<<< ours\n' > "$ROOT/f.txt"; else printf 'a\n' > "$ROOT/f.txt"; fi
      gi() { case $1 in rev-parse) case $* in *"-q --verify HEAD") echo H ;; *"--verify refs/x") echo F ;; *"--verify origin/main^{commit}") echo R ;; esac ;;
        merge-tree) printf 'TREE\nf.txt\n'; return 1 ;; *) true ;; esac; }
      die() { echo "$*" > "$d/die"; exit "$1"; }; host() { echo h; }; precheck() { :; }; approved() { return 0; }
      disk_blob() { return 1; }; disk_mode() { echo 100644; [ $c != mode ]; }
      [ $c = unread ] && grep() { return 2; }
      eval "$(sed -n '/^cmd_resolve() {/,/^}/p' "$gi")" || exit 99
      cmd_resolve origin/main ) > /dev/null 2>&1; rc=$?
    m=other; grep -q 'still has conflict markers' "$d/die" 2>/dev/null && m=markers; grep -q 'cannot read f.txt for conflict markers' "$d/die" 2>/dev/null && m=unread; grep -q 'cannot record' "$d/die" 2>/dev/null && m=went-on; grep -q 'cannot read the mode of f.txt' "$d/die" 2>/dev/null && m=mode
    rm -f -- "$d/die"; r="$r$c=$rc/$m;"
  done
  SWAZ=$r; [ "$SWAZ" = "marked=1/markers;clean=6/went-on;unread=6/unread;mode=6/mode;" ]; }
t_swsameblob() {  # a blob that a failed hash printed is not the file's blob: same_blob is a mismatch, not a match
  local gi=${GI:-$HERE/../git-internal} d=$B/gis r="" c rc
  rm -rf -- "${d:?}"; mkdir -p "$d"; printf 'a\n' > "$d/p"
  for c in ok failout; do
    ( ROOT=$d
      gi() { case $1 in ls-tree) printf '100644 blob SHA\tp\n' ;; *) true ;; esac; }
      disk_blob() { echo SHA; [ $c = ok ]; }
      eval "$(sed -n '/^disk_mode() {/,/^}/p;/^same_blob() {/,/^}/p' "$gi")" || exit 99
      same_blob REV p ); rc=$?
    r="$r$c=$rc;"
  done
  SWBA=$r; [ "$SWBA" = "ok=0;failout=1;" ]; }
t_sworighead() {  # ORIG_HEAD is read with its status: an initial read that prints the old commit and fails is "not set" (rewritten), and a read-back that prints it and fails is a STOP
  local gi=${GI:-$HERE/../git-internal} d=$B/gio r="" c rc u
  rm -rf -- "${d:?}"; mkdir -p "$d"
  for c in ok initread readback; do
    rm -f -- "$d/n" "$d/upd"; : > "$d/intent"
    ( ROOT=$d; GD=$d/gd; INTENT=$d/intent
      gi() { case $1 in symbolic-ref) true ;;
        update-ref) : > "$d/upd" ;;
        rev-parse) case $* in
          *"--verify HEAD") echo NEW ;;
          *"--verify ORIG_HEAD") n=$(cat "$d/n" 2>/dev/null || echo 0); echo $((n+1)) > "$d/n"
            case $c/$((n+1)) in
              ok/1) echo OLD ;;
              initread/1) echo OLD; return 1 ;;
              initread/2) echo OLD ;;
              readback/1) return 1 ;;
              readback/2) echo OLD; return 1 ;;
            esac ;;
          esac ;;
        *) true ;; esac; }
      crash_point() { :; }; fsync_path() { :; }
      eval "$(sed -n '/^forward() {/,/^}/p' "$gi")" || exit 99
      forward sync OLD NEW 2> "$d/err"; echo "$?" > "$d/rc" )
    rc=$(cat "$d/rc" 2>/dev/null); u=no-rewrite; [ -e "$d/upd" ] && u=rewrote
    r="$r$c=$rc/$u;"
  done
  SWBB=$r; [ "$SWBB" = "ok=0/no-rewrite;initread=0/rewrote;readback=10/rewrote;" ]; }
t_swhost() {  # the machine-local host name is read with the status of the read, in the driver and in the private pre-push hook: a read that prints a name and then fails is no host
  local gi=${GI:-$HERE/../git-internal} hook=${PPHOOK:-$HERE/../git-internal-hooks/pre-push} d=$B/gh r="" c rc o realcat
  realcat=$(command -v cat)
  rm -rf -- "${d:?}"; mkdir -p "$d/shim" "$d/repo"
  printf '#!/bin/bash\n%s "$@"; [ "${FAILCAT:-}" != 1 ]\n' "$realcat" > "$d/shim/cat"; chmod +x "$d/shim/cat"
  git init -q "$d/repo" && mkdir -p "$d/repo/.git/info" && printf 'h1\n' > "$d/repo/.git/info/host" || return 1
  for c in ok failout; do
    o=$( GD=$d/hostgd; mkdir -p "$GD/info"; printf 'h1' > "$GD/info/host"
         cat() { "$realcat" "$@"; [ $c = ok ]; }; die() { exit 4; }
         eval "$(sed -n '/^host() {/,/^}/p' "$gi")" || exit 99
         host ); rc=$?
    r="$r$c=$rc/$o;"
  done
  for c in ok failout; do
    ( cd "$d/repo" && printf 'refs/heads/main aaa refs/heads/autosync/h1 bbb\n' | { [ $c = failout ] && export FAILCAT=1; PATH=$d/shim:$PATH bash "$hook"; } ) > /dev/null 2>&1; rc=$?
    r="${r}hook-$c=$rc;"
  done
  SWBC=$r; [ "$SWBC" = "ok=0/h1;failout=4/;hook-ok=0;hook-failout=1;" ]; }
t_swcapnames() {  # the names of the capture's sha256 record are read with the status of the read: a read that prints both names and then fails is not a match
  local PD=$W/pres/mA-$O
  restore fx; stepto preflight freeze capture || return 1
  printf '%s' 'capture/sha256' > "$ST/cutfail"
  wg capture > "$B/out.sw" 2>&1; SWAM="$?/$(sw_msg 'sha256 record cannot be read')/$(ls "$PD" | grep -c tmp)"
  [ "$SWAM" = "3/1/0" ]; }
t_swrestcap() {  # restart step 1 checks both entries of the capture's sha256 record itself: the pinned step drops a last line with no newline, so a changed W-snapshot behind such a record is caught here, in --check as well
  local a b c
  restore r0a; printf '%s' "$(cat "$J/capture/sha256")" > "$J/capture/sha256"; echo x >> "$J/capture/wtree.tar"
  wg restart r0 > "$B/out.sw" 2>&1; a="$?/$(sw_msg 'the capture in the journal does not match its sha256 record')/$(sw_state)"
  restore r0a; printf '%s' "$(cat "$J/capture/sha256")" > "$J/capture/sha256"; echo x >> "$J/capture/wtree.tar"
  wg --check restart r0 > "$B/out.sw" 2>&1; c="$?/$(sw_msg 'restart step 1 would fail')"
  restore r0a; printf '%s' "$(cat "$J/capture/sha256")" > "$J/capture/sha256"
  wg restart r0 > "$B/out.sw" 2>&1; b="$?/$(sw_state)"
  SWAN="$a;$c;$b"; [ "$SWAN" = "3/1//0/no/no/;3/1;0/recorded/1/yes/yes/marker" ]; }
t_swreconeval() {  # the jsonl_dominated definition is taken from the steps with the extraction's status held and the whole function checked, and its load is checked: an inherited function never stands in for it
  local a b c
  restore r0a; sw_sed '/^jsonl_dominated() {/' 0 out
  wg restart r0 > "$B/out.sw" 2>&1; a="$?/$(sw_msg 'cannot extract jsonl_dominated')/$(sw_state)"
  restore r0a; sed 's/jsonl_dominated/jsonl_domx/g' "$CS" > "$B/cs-nodom.sh"; chmod +x "$B/cs-nodom.sh"
  ( jsonl_dominated() { return 0; }; export -f jsonl_dominated; CS=$B/cs-nodom.sh; wg restart r0 > "$B/out.sw" 2>&1; echo "$?" > "$B/rc.sw" ); b="$(cat "$B/rc.sw")/$(sw_msg 'cannot extract jsonl_dominated')/$(sw_state)"
  restore r0a
  ( jsonl_dominated() { return 0; }; eval() { case $1 in "jsonl_dominated() {"*) return 1 ;; esac; builtin eval "$@"; }; export -f jsonl_dominated eval; wg restart r0 > "$B/out.sw" 2>&1; echo "$?" > "$B/rc.sw" ); c="$(cat "$B/rc.sw")/$(sw_msg 'cannot load jsonl_dominated')/$(sw_state)"
  SWAO="$a;$b;$c"; [ "$SWAO" = "3/1//0/no/no/;3/1//0/no/no/;3/1//0/no/no/" ]; }

# ---- class sweep, round 18: the shared git directory of a linked worktree, and the cleanup of a cut-off restart before any input is validated (bead mk-z9st.22)
t_swgitcommon() {  # a linked worktree keeps its refs, objects and config in the common git directory: no state, journal, preservation or log directory may be inside it
  restore fx; local R0=$R cm rf0 r1 r2 r3 r4
  git -C "$R0" checkout -q --detach && git -C "$R0" worktree add "$W/wt" main > "$B/out.gc" 2>&1 || { echo "  FAIL cannot add a linked worktree"; return 1; }
  cm=$(cd "$R0/.git" && pwd -P); rf0=$(ls "$cm/refs"); R=$W/wt; : > "$B/out.sw"
  T_STATE="$cm/refs/st" wg --check preflight >> "$B/out.sw" 2>&1; r1=$?
  T_JOURNAL="$cm/jj" wg --check preflight >> "$B/out.sw" 2>&1; r2=$?
  T_PRES="$cm/objects/pp" wg --check preflight >> "$B/out.sw" 2>&1; r3=$?
  mkdir -p "$W/lst"; ln -s "$cm/refs" "$W/lst/logs"   # the state directory is outside; its logs child leads into the common directory
  T_STATE="$W/lst" wg --check preflight >> "$B/out.sw" 2>&1; r4=$?
  R=$R0; SWGC="$r1$r2$r3$r4/$(sw_msg 'git directories')"
  [ "$SWGC" = 1111/4 ] && [ ! -e "$cm/refs/st" ] && [ ! -e "$cm/jj" ] && [ ! -e "$cm/objects/pp" ] && [ "$(ls "$cm/refs")" = "$rf0" ]; }
t_swrestartclean() {  # a restart cut off after its first timer start is undone by the next restart although an input in J is missing or unreadable (the cleanup needs none); the inputs are still required for a new attempt
  local v crash=$B/mut/crash2.sh rc rc2 rc3 f g; SWRC=
  for v in missing unreadable; do
    sed '/^    units start "\$u" || rbail "cannot re-enable/a kill -KILL $$' "${WG:-$GW}" > "$crash"; chmod +x "$crash"; cp "$HERE/cutover-steps.sh" "$B/mut/cutover-steps.sh"
    cmp -s "${WG:-$GW}" "$crash" && { echo "  FAIL crash copy changed nothing"; return 1; }
    restore r0a; rm -f "$ST/units/git-autosync-repair.service"; : > "$B/out.sw"
    WG=$crash wg restart r0 >> "$B/out.sw" 2>&1; rc=$?
    f="$([ -e "$R/.git-autosync" ] && echo marker)/$(timers)"
    case $v in missing) rm -f "$J/lane-remote" ;; unreadable) chmod 000 "$J/lane-remote" ;; esac
    wg restart r0 >> "$B/out.sw" 2>&1; rc2=$?
    g="$([ -e "$R/.git-autosync" ] && echo marker)/$(timers)/$(ls "$J/gate0-run" | grep -c '^restart')/$(sw_msg 'an earlier restart attempt began')"
    wg restart r0 >> "$B/out.sw" 2>&1; rc3=$?
    SWRC="$SWRC$rc/$f/$rc2/$g/$rc3/$(sw_msg 'is missing or empty\|cannot be read');"
    chmod 644 "$J/lane-remote" 2>/dev/null
  done
  restore r0a; : > "$B/out.sw"; wg restart r0 >> "$B/out.sw" 2>&1 || return 1   # a completed restart whose state no longer matches its record is undone, not refused
  rm -f "$J/lane-remote"; rm -f "$ST/units/git-autosync-promote.timer"
  wg restart r0 >> "$B/out.sw" 2>&1; rc=$?
  SWRC="$SWRC$rc/$([ -e "$J/gate0-run/restarted-r0" ] && echo recorded)/$(timers)/$([ -e "$R/.git-autosync" ] && echo marker)/$(sw_msg 'is not confirmed active')"
  [ "$SWRC" = "137/marker/yes/no/3//no/no/0/1/1/1;137/marker/yes/no/3//no/no/0/1/1/1;3//no/no//1" ]; }

# The statements of the start-up that can end the script, in the order they run, are read from the wrapper itself and each has a case below
# (a statement with no entry, or an entry with no statement, fails t_swstartguards). The tables are lexical, so they are an aid and no proof:
# they cannot see an exit inside a helper function. The proof is t_swstartinject, which fails every command the start-up executes (helpers and
# subshells included) and checks the state each time. set -u is no extra class: an unbound variable ends the script through the same EXIT trap,
# and every expansion before the arm is guarded or assigned above it.
SRKEYS=('$ROOT/.git' 'git_bind' 'PRES=$(physpath' 'must be outside the checkout and its git' 'preservation copy must be outside the journal' 'LP=$(physpath' 'cannot create the journal' 'cannot create $LOGD' 'GATE0_MACHINE is server' 'self_sha')
SRCASES=('nogit' 'gitcfg gitroot gitdir gitcommon' 'pres-dangling pres-file' 'state-in-checkout pres-in-checkout' 'pres-in-journal' 'logs-into-checkout' 'journal-mkdir' 'logdir-mkdir' 'machine' 'nosha')
# before the recovery is armed only what names the journal can fail (and nothing is written there)
SPKEYS=('exit $?' 'self_sha' 'usage: gate0-run.sh' 'set GATE0_ROOT and GATE0_STATE_DIR' 'GATE0_ROOT is not a git checkout' 'cannot establish the user id' 'run as root, set GATE0_OPERATOR' 'exec runuser' 'cannot use GATE0_STATE_DIR' 'cannot use GATE0_JOURNAL' 'is not a plain child')
SPCASES=('check' 'check-nosha' 'usage usage-exit-arg' 'noenv' 'root-bad' 'uid-bad' 'operator-bad' 'runuser-bad' 'state-dangling' 'journal-dangling' 'gate-symlink')
sr_post() { awk '/^trap bootexit EXIT$/{on=1;next} /^restart_settled && exit 0$/{on=0} on' "${WG:-$GW}" | grep -v '^ *#' | grep -v '^trap ' | grep -E 'exit [0-9$]|git_bind|self_sha'; }
sr_pre() { awk '
/^trap bootexit EXIT$/{exit}
{ line=$0; o=gsub(/\{/,"{",line); c=gsub(/\}/,"}",line)
  if (depth==0 && $0 ~ /^[A-Za-z_][A-Za-z0-9_]*\(\) *\{/) { depth=o-c; next }
  if (depth>0) { depth+=o-c; next }
  if ($0 ~ /^ *#/) next
  if ($0 ~ /exit [0-9$]|exec runuser|self_sha/) print }' "${WG:-$GW}"; }
sr_table_ok() {  # LINES KEYS... : every line holds a key and every key is held by a line
  local lines=$1 k l miss=; shift
  while IFS= read -r l; do [ -n "$l" ] || continue; for k in "$@"; do case $l in *"$k"*) continue 2 ;; esac; done; miss="$miss [no case for: ${l:0:70}]"; done <<< "$lines"
  for k in "$@"; do case $lines in *"$k"*) ;; *) miss="$miss [no statement for: $k]" ;; esac; done
  [ -z "$miss" ] || { echo "    start-up table: $miss"; return 1; }; }
t_swstartguards() {  # the case tables cover every statement that can end the start-up, before and after the arm
  local n; n=$(sr_post | wc -l); [ "$n" -ge 8 ] || { echo "    start-up table: only $n statements found after the arm"; return 1; }
  n=$(sr_pre | wc -l); [ "$n" -ge 8 ] || { echo "    start-up table: only $n statements found before the arm"; return 1; }
  sr_table_ok "$(sr_post)" "${SRKEYS[@]}" && sr_table_ok "$(sr_pre)" "${SPKEYS[@]}" && [ ${#SRKEYS[@]} = ${#SRCASES[@]} ] && [ ${#SPKEYS[@]} = ${#SPCASES[@]} ]; }
sr_cut() {  # a restart cut off after its first timer start; SRRC is its status, SRF the marker and timers it left
  local crash=$B/mut/crash3.sh
  sed '/^    units start "\$u" || rbail "cannot re-enable/a kill -KILL $$' "${WG:-$GW}" > "$crash"; chmod +x "$crash"; cp "$HERE/cutover-steps.sh" "$B/mut/cutover-steps.sh"
  cmp -s "${WG:-$GW}" "$crash" && { echo "  FAIL crash copy changed nothing"; return 1; }
  restore r0a; rm -f "$ST/units/git-autosync-repair.service"; : > "$B/out.sw"; rm -rf "$B/shabad" "$B/badcfg" "$B/mkbad" "$B/idstub" "$B/rustub"
  [ -z "${SRSVC:-}" ] || touch "$ST/svc-stays-active"   # SRSVC=1: the repair service the cut-off attempt started is still running when it is cut off
  WG=$crash wg restart r0 >> "$B/out.sw" 2>&1; SRRC=$?; rm -f "$ST/svc-stays-active"
  SRF="$([ -e "$R/.git-autosync" ] && echo marker)/$(timers)"; }
sr_state() { echo "$([ -e "$R/.git-autosync" ] && echo marker)/$(timers)/$(ls "$J/gate0-run" | grep -c '^restart')"; }
sr_full() { echo "$(sr_state)/$([ -e "$ST/units/git-autosync-repair.service" ] && echo svc)/$([ -f "$J/gate0-run/marker" ] && sha < "$J/gate0-run/marker")"; }   # what the injector observes: the marker, the timers, the restart records, the repair service, and the preserved marker's bytes
sr_stubs() {  # stub commands that fail on request, ahead of the wrapper's own PATH
  mkdir -p "$B/mkbad" "$B/shabad" "$B/idstub" "$B/rustub"
  printf '#!/bin/sh\nfor a in "$@"; do [ "$a" != "$STUB_FAIL" ] || exit 1; done\nexec %s "$@"\n' "$(command -v mkdir)" > "$B/mkbad/mkdir"
  printf '#!/bin/sh\necho x\nexit 1\n' > "$B/shabad/sha256sum"; cp "$B/shabad/sha256sum" "$B/shabad/shasum"
  printf '#!/bin/sh\ncase "$1" in -u) [ "$ID_MODE" = bad ] && exit 1; echo 0 ;; "") exit 1 ;; *) exit 0 ;; esac\n' > "$B/idstub/id"
  printf '#!/bin/sh\nexit 1\n' > "$B/rustub/runuser"
  chmod +x "$B"/mkbad/mkdir "$B"/shabad/* "$B"/idstub/id "$B"/rustub/runuser; }
t_swstartrecover() {  # a restart cut off after its first timer start is undone by a retry that fails at any step of its start after the arm, before restart_settled can run (one case for each statement t_swstartguards lists), with no PRES, log directory or other input resolved
  local c rc2 g want='137/marker/yes/no/1//no/no/0' bad= ran=0 total=0 cs; SWSR=
  for cs in "${SRCASES[@]}"; do for c in $cs; do total=$((total+1)); done; done
  for cs in "${SRCASES[@]}"; do for c in $cs; do
    sr_cut || return 1; sr_stubs; ran=$((ran+1)); rc2=0
    case $c in
      nogit) mv "$R/.git" "$R/.git.off"; wg restart r0 >> "$B/out.sw" 2>&1; rc2=$?; mv "$R/.git.off" "$R/.git" ;;
      gitcfg) printf '[\n' > "$B/badcfg"; GIT_CONFIG_GLOBAL=$B/badcfg wg restart r0 >> "$B/out.sw" 2>&1; rc2=$? ;;
      gitroot) sw_inj ' --show-toplevel'; wg restart r0 >> "$B/out.sw" 2>&1; rc2=$? ;;
      gitdir) sw_inj ' --git-dir'; wg restart r0 >> "$B/out.sw" 2>&1; rc2=$? ;;
      gitcommon) sw_inj ' --git-common-dir'; wg restart r0 >> "$B/out.sw" 2>&1; rc2=$? ;;
      pres-dangling) ln -s "$W/nowhere" "$W/pdang"; T_PRES=$W/pdang wg restart r0 >> "$B/out.sw" 2>&1; rc2=$? ;;   # the round-25 case: the preservation path cannot be resolved
      pres-file) : > "$W/pfile"; T_PRES=$W/pfile/x wg restart r0 >> "$B/out.sw" 2>&1; rc2=$? ;;
      state-in-checkout) T_STATE=$R/st wg restart r0 >> "$B/out.sw" 2>&1; rc2=$? ;;
      pres-in-checkout) T_PRES=$R/pres wg restart r0 >> "$B/out.sw" 2>&1; rc2=$? ;;
      pres-in-journal) T_PRES=$J/pres wg restart r0 >> "$B/out.sw" 2>&1; rc2=$? ;;
      logs-into-checkout) mkdir -p "$W/lst"; ln -s "$R" "$W/lst/logs"; T_STATE=$W/lst wg restart r0 >> "$B/out.sw" 2>&1; rc2=$? ;;
      journal-mkdir) STUB_FAIL=$J PATHS=$B/mkbad:$PATHS wg restart r0 >> "$B/out.sw" 2>&1; rc2=$?   # the journal exists (it holds the record), so only an injected failure reaches the statement
        [ "$(sw_msg 'cannot create the journal')" = 1 ] || { echo "    $c: the statement was not reached"; bad="$bad $c"; } ;;
      logdir-mkdir) mkdir -p "$W/state2"; : > "$W/state2/logs"; T_STATE=$W/state2 wg restart r0 >> "$B/out.sw" 2>&1; rc2=$? ;;
      machine) GATE0_MACHINE=bogus wg restart r0 >> "$B/out.sw" 2>&1; rc2=$? ;;
      nosha) PATHS=$B/shabad:$PATHS wg restart r0 >> "$B/out.sw" 2>&1; rc2=$? ;;   # neither digest tool works
      *) echo "    no such start-up case: $c"; return 1 ;;
    esac
    g=$(sr_state); [ "$SRRC/$SRF/$rc2/$g" = "$want" ] || { echo "    start case $c: got $SRRC/$SRF/$rc2/$g want $want"; bad="$bad $c"; }
    SWSR="$SWSR$c:$rc2;"
  done; done
  [ "$ran" = "$total" ] || { echo "    start cases run: $ran"; return 1; }
  restore r0a; : > "$B/out.sw"; wg restart r0 >> "$B/out.sw" 2>&1 || return 1   # a completed restart is not undone by a later start that fails
  GATE0_MACHINE=bogus wg restart r0 >> "$B/out.sw" 2>&1; rc2=$?
  SWSR="$SWSR$rc2/$([ -e "$R/.git-autosync" ] && echo marker)/$(timers)/$(ls "$J/gate0-run" | grep -c '^restarted-')"
  [ -z "$bad" ] && [ "$rc2/$([ -e "$R/.git-autosync" ] && echo marker)/$(timers)/$(ls "$J/gate0-run" | grep -c '^restarted-')" = 1/marker/yes/yes/1 ]; }
t_swprearm() {  # a retry that fails before the recovery is armed (usage, the environment, the checkout path, the user, the state and journal paths, the script's own digest under --check) writes and undoes nothing: the cut-off attempt is unchanged, and the next ordinary retry undoes it
  local c rc2 pre post bad= ran=0 total=0 cs op; SWPA=
  op=$(id -un)
  for cs in "${SPCASES[@]}"; do for c in $cs; do total=$((total+1)); done; done
  for cs in "${SPCASES[@]}"; do for c in $cs; do
    sr_cut || return 1; sr_stubs; ran=$((ran+1)); rc2=0; pre=$(sr_state)
    case $c in
      check) wg --check >> "$B/out.sw" 2>&1; rc2=$? ;;
      check-nosha) PATHS=$B/shabad:$PATHS wg --check >> "$B/out.sw" 2>&1; rc2=$? ;;
      usage) wg restart >> "$B/out.sw" 2>&1; rc2=$? ;;
      usage-exit-arg) wg restart zz >> "$B/out.sw" 2>&1; rc2=$? ;;
      noenv) env GATE0_ROOT= GATE0_STATE_DIR= GATE0_PATH="$PATHS" "${WG:-$GW}" restart r0 >> "$B/out.sw" 2>&1; rc2=$? ;;
      root-bad) R=$W/nowhere wg restart r0 >> "$B/out.sw" 2>&1; rc2=$? ;;
      uid-bad) ID_MODE=bad PATHS=$B/idstub:$PATHS wg restart r0 >> "$B/out.sw" 2>&1; rc2=$? ;;
      operator-bad) env GATE0_ROOT="$R" GATE0_STATE_DIR="$W/state" GATE0_JOURNAL="$J" GATE0_PATH="$B/idstub:$PATHS" GATE0_OPERATOR= "${WG:-$GW}" restart r0 >> "$B/out.sw" 2>&1; rc2=$? ;;
      runuser-bad) env GATE0_ROOT="$R" GATE0_STATE_DIR="$W/state" GATE0_JOURNAL="$J" GATE0_PATH="$B/rustub:$B/idstub:$PATHS" GATE0_OPERATOR=$op "${WG:-$GW}" restart r0 >> "$B/out.sw" 2>&1; rc2=$? ;;
      state-dangling) ln -s "$W/nowhere" "$W/sdang"; T_STATE=$W/sdang wg restart r0 >> "$B/out.sw" 2>&1; rc2=$? ;;
      journal-dangling) ln -s "$W/nowhere" "$W/jdang"; T_JOURNAL=$W/jdang wg restart r0 >> "$B/out.sw" 2>&1; rc2=$? ;;
      gate-symlink) mv "$J/gate0-run" "$J/gate0-real"; ln -s gate0-real "$J/gate0-run"; wg restart r0 >> "$B/out.sw" 2>&1; rc2=$?; rm -f "$J/gate0-run"; mv "$J/gate0-real" "$J/gate0-run" ;;
      *) echo "    no such pre-arm case: $c"; return 1 ;;
    esac
    post=$(sr_state)
    case $c in check) [ $rc2 = 0 ] || { echo "    pre-arm $c: exit $rc2 want 0"; bad="$bad $c"; } ;; *) [ $rc2 != 0 ] || { echo "    pre-arm $c: exit 0"; bad="$bad $c"; } ;; esac
    [ "$SRRC/$SRF" = 137/marker/yes/no ] && [ "$pre" = "$post" ] || { echo "    pre-arm $c: state $pre -> $post"; bad="$bad $c"; }
    wg restart r0 >> "$B/out.sw" 2>&1; post=$(sr_state)
    [ "$post" = "/no/no/0" ] || { echo "    pre-arm $c: the next retry left $post"; bad="$bad $c"; }
    SWPA="$SWPA$c:$rc2;"
  done; done
  [ "$ran" = "$total" ] || { echo "    pre-arm cases run: $ran"; return 1; }
  [ -z "$bad" ]; }

t_swunconfined() {  # a retry whose journal is not confined (inside the checkout, inside a git directory it names, or confinement that cannot be read) is refused and touches nothing: no write into that journal, nothing stopped, the marker where it was; the state stays for a run with the right journal, which then undoes it
  local c rc2 jj Rx R0=$R bad= jpre jpost rpre rpost spre spost g; SWUC=
  for c in jin jgit wtgit wtcommon wtroot brokenlink; do
    sr_cut || return 1; sr_stubs; : > "$B/out.sw"; Rx=$R0; jj=$J
    case $c in
      jin) jj=$R0/jin ;;
      jgit) jj=$R0/.git/jin ;;
      wtgit|wtcommon|wtroot)
        git -C "$R0" checkout -q --detach && git -C "$R0" worktree add "$W/wt" main >> "$B/out.sw" 2>&1 || { echo "    $c: cannot add a linked worktree"; return 1; }
        Rx=$W/wt
        case $c in wtgit) jj=$R0/.git/worktrees/wt/jin ;; wtcommon) jj=$R0/.git/jc ;; wtroot) jj=$W/wt/jin ;; esac ;;
      brokenlink) Rx=$W/brk; mkdir -p "$Rx"; printf 'gitdir: %s\n' "$W/nowhere/x" > "$Rx/.git"; jj=$W/jout ;;
    esac
    mkdir -p "$(dirname "$jj")" && cp -a "$J" "$jj" || { echo "    $c: cannot copy the journal"; return 1; }
    jpre=$(J=$jj jfp); rpre=$(ls -A "$Rx" | sha); spre="$([ -e "$R0/.git-autosync" ] && echo marker)/$(timers)"
    R=$Rx T_JOURNAL=$jj wg restart r0 >> "$B/out.sw" 2>&1; rc2=$?
    jpost=$(J=$jj jfp); rpost=$(ls -A "$Rx" | sha); spost="$([ -e "$R0/.git-autosync" ] && echo marker)/$(timers)"
    [ "$rc2" = 1 ] || { echo "    $c: exit $rc2 want 1"; bad="$bad $c"; }
    { [ "$jpre" = "$jpost" ] && [ "$rpre" = "$rpost" ] && [ "$spre" = "$spost" ] && [ "$spost" = marker/yes/no ]; } || { echo "    $c: the refused start changed something (journal ${jpre:0:8}->${jpost:0:8}, checkout ${rpre:0:8}->${rpost:0:8}, $spre -> $spost)"; bad="$bad $c"; }
    [ "$(sw_msg 'are undone now')" = 0 ] || { echo "    $c: a recovery ran in the refused start"; bad="$bad $c"; }
    case $c in brokenlink) ;; *) [ "$(sw_msg 'must be outside the checkout and its git')" = 1 ] || { echo "    $c: not refused by the confinement check"; bad="$bad $c"; } ;; esac
    wg restart r0 >> "$B/out.sw" 2>&1; g=$(sr_state)   # the run with the right journal undoes the earlier attempt
    [ "$g" = "/no/no/0" ] || { echo "    $c: the right journal left $g"; bad="$bad $c"; }
    SWUC="$SWUC$c:$rc2;"
  done
  [ -z "$bad" ]; }
t_swlayouts() {  # the journal's confinement is one decision, taken from the git directories .git names: for every layout of .git (a directory, a link to a directory, a link to a linked worktree's git directory, a gitdir file with a commondir file, a gitdir file with none) and every place the journal can be (the shared git directory, the worktree's own git directory, the work tree, outside), git itself says whether the journal is inside the checkout or a git directory; the start-up refuses exactly then (and then touches nothing, recovery included), and otherwise goes on and undoes the cut-off attempt
  local R0=$R lay loc Rx gd gc jj og oc exp rc2 g jpre jpost spre spost rows=0 refused=0 acted=0 bad= c1 c2; SWLAY=
  for lay in dir dirlink wtlink gitfile sepfile; do
    for loc in shared gitdir root outside; do
      sr_cut || return 1; sr_stubs; : > "$B/out.sw"
      case $lay in
        dir) Rx=$R0; gd=$R0/.git; gc=$gd ;;
        dirlink) git clone -q --no-checkout "$R0" "$W/lr" >> "$B/out.sw" 2>&1 && mkdir -p "$W/lnk" && ln -s "$W/lr/.git" "$W/lnk/.git" || { echo "    $lay: cannot make the layout"; return 1; }
          Rx=$W/lnk; gd=$W/lr/.git; gc=$gd ;;
        wtlink|gitfile) git -C "$R0" checkout -q --detach && git -C "$R0" worktree add "$W/wt" main >> "$B/out.sw" 2>&1 || { echo "    $lay: cannot add a linked worktree"; return 1; }
          Rx=$W/wt; gd=$R0/.git/worktrees/wt; gc=$R0/.git
          [ $lay != wtlink ] || { rm -f "$Rx/.git" && ln -s "$gd" "$Rx/.git"; } || { echo "    $lay: cannot link .git"; return 1; } ;;
        sepfile) git init -q --separate-git-dir="$W/sep.git" "$W/sepco" >> "$B/out.sw" 2>&1 || { echo "    $lay: cannot make the layout"; return 1; }
          Rx=$W/sepco; gd=$W/sep.git; gc=$gd ;;
      esac
      case $loc in shared) jj=$gc/jx ;; gitdir) jj=$gd/jx ;; root) jj=$Rx/jx ;; outside) jj=$W/jout ;; esac
      [ "$loc" != gitdir ] || [ "$gd" != "$gc" ] || continue   # the same place as the shared git directory
      og=$(git -C "$Rx" rev-parse --path-format=absolute --git-dir 2>/dev/null) && oc=$(git -C "$Rx" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || { echo "    $lay: git does not accept the layout"; bad="$bad $lay"; continue; }
      og=$(cd "$og" && pwd -P); oc=$(cd "$oc" && pwd -P); c1=$(cd "$Rx" && pwd -P)
      [ "$og" = "$gd" ] && [ "$oc" = "$gc" ] || { echo "    $lay: git names $og and $oc, the table $gd and $gc"; bad="$bad $lay"; continue; }
      case "$jj/" in "$c1"/*|"$og"/*|"$oc"/*) exp=refuse ;; *) exp=run ;; esac   # git's answer, not the wrapper's
      mkdir -p "$(dirname "$jj")" && cp -a "$J" "$jj" || { echo "    $lay/$loc: cannot copy the journal"; return 1; }
      jpre=$(J=$jj jfp); spre="$(timers)/$(ls "$jj/gate0-run" | grep -c '^restart')"
      R=$Rx T_JOURNAL=$jj wg restart r0 >> "$B/out.sw" 2>&1; rc2=$?
      jpost=$(J=$jj jfp); spost="$(timers)/$(ls "$jj/gate0-run" | grep -c '^restart')"; rows=$((rows+1))
      c2=$(sw_msg 'must be outside the checkout and its git')
      if [ $exp = refuse ]; then refused=$((refused+1))
        { [ "$rc2" = 1 ] && [ "$c2" = 1 ] && [ "$jpre" = "$jpost" ] && [ "$spre" = "$spost" ] && [ "$spost" = yes/no/1 ] && [ "$(sw_msg 'are undone now')" = 0 ]; } || { echo "    $lay/$loc: git puts the journal inside, the start-up got rc=$rc2 refusals=$c2 journal $([ "$jpre" = "$jpost" ] && echo same || echo changed) state $spre -> $spost"; bad="$bad $lay/$loc"; }
      else
        { [ "$c2" = 0 ] && [ "$spost" = no/no/0 ] && [ "$jpre" != "$jpost" ]; } && acted=$((acted+1)) || { echo "    $lay/$loc: git puts the journal outside, the start-up got rc=$rc2 refusals=$c2 state $spre -> $spost"; bad="$bad $lay/$loc"; }
      fi
      wg restart r0 >> "$B/out.sw" 2>&1; g=$(sr_state)   # the run with the right journal ends in the undone state in every layout
      [ "$g" = "/no/no/0" ] || { echo "    $lay/$loc: the right journal left $g"; bad="$bad $lay/$loc(retry)"; }
    done
  done
  SWLAY="rows=$rows refused=$refused acted=$acted"; echo "    layouts: $SWLAY"
  [ -z "$bad" ] && [ "$rows" -ge 15 ] && [ "$refused" -ge 8 ] && [ "$acted" -ge 3 ]; }
t_swtransient() {  # a confinement result is the last one computed: a transient failure of the first read of the git directories (the recovery is armed with nothing known) does not stay: the start-up goes on on the later, good result, and a signal after the restart still undoes it; an early "safe" is revoked the same way: a later "unsafe" refuses and the recovery then touches nothing
  local m=$B/mut/gn1.sh m2=$B/mut/gn2.sh res rc i pid rcount='find "$J/gate0-run" -maxdepth 1 -name restarting-\* | wc -l' R0=$R jj g jpre jpost spre spost
  sed $'/^  local f= x=; NE=; NEC=; NERR=$/a\\\n  if [ -n "${GN_ONCE:-}" ] \\&\\& [ ! -e "$GN_ONCE" ]; then : > "$GN_ONCE"; NERR=transient; return 1; fi' "${WG:-$GW}" > "$m"
  sed $'/^  local f= x=; NE=; NEC=; NERR=$/a\\\n  if [ -n "${GN_FAKE:-}" ] \\&\\& [ ! -e "$GN_FAKE" ]; then : > "$GN_FAKE"; NE=/nonexistent-git-dir; NEC=$NE; return 0; fi' "${WG:-$GW}" > "$m2"
  chmod +x "$m" "$m2"; cp "$HERE/cutover-steps.sh" "$B/mut/cutover-steps.sh"
  { bash -n "$m" && bash -n "$m2" && ! cmp -s "$m" "${WG:-$GW}" && ! cmp -s "$m2" "${WG:-$GW}"; } 2>/dev/null || { echo "    transient copies are not usable"; return 1; }
  rm -f "$B/gnonce" "$B/gnfake"; restore r0a; touch "$ST/start-hang" "$ST/svc-stays-active"; : > "$B/tell.log"
  GN_ONCE=$B/gnonce WG=$m wg restart r0 > "$B/out.sw" 2>&1 &
  for i in $(seq 1 600); do [ -s "$ST/start-hung" ] && break; sleep 0.1; done
  if [ -s "$ST/start-hung" ]; then pid=$(cat "$ST/start-hung"); kill -TERM "$pid"; fi
  touch "$ST/start-release"; wait $!; rc=$?
  res="$rc/$(sw_state)/$(eval "$rcount")/$([ -e "$ST/units/git-autosync-repair.service" ] && echo svc)/$([ -e "$J/gate0-run/marker" ] && echo aside)/$(tail -n 1 "$B/tell.log" | grep -c -- '--result failed --step restart')/$([ -e "$B/gnonce" ] && echo transient)"
  rm -f "$ST/start-hang" "$ST/start-hung" "$ST/start-release" "$ST/svc-stays-active"
  [ "$res" = "143//1/no/no//0//aside/1/transient" ] || { echo "    transient failure, then a signal after the restart: got $res"; return 1; }
  sr_cut || return 1; sr_stubs; : > "$B/out.sw"; jj=$R0/.git/jc   # the journal is inside the shared git directory of the worktree; the first read of the names says otherwise
  git -C "$R0" worktree add --detach "$W/wt" >> "$B/out.sw" 2>&1 || { echo "    cannot add a linked worktree"; return 1; }
  cp -a "$J" "$jj" || return 1; jpre=$(J=$jj jfp); spre="$(R=$R0 sr_state)"
  R=$W/wt T_JOURNAL=$jj GN_FAKE=$B/gnfake WG=$m2 wg restart r0 >> "$B/out.sw" 2>&1; rc=$?
  jpost=$(J=$jj jfp); spost="$(R=$R0 sr_state)"
  { [ "$rc" = 1 ] && [ -e "$B/gnfake" ] && [ "$jpre" = "$jpost" ] && [ "$spre" = "$spost" ] && [ "$spost" = marker/yes/no/1 ] && [ "$(sw_msg 'must be outside the checkout and its git')" = 1 ] && [ "$(sw_msg 'are undone now')" = 0 ]; } || { echo "    an early safe, then unsafe: rc=$rc fake=$([ -e "$B/gnfake" ] && echo used) journal $([ "$jpre" = "$jpost" ] && echo same || echo changed) state $spre -> $spost"; return 1; }
  true; }
t_swstartinject() {  # every command the start-up executes, in a counted run, is failed in turn (a DEBUG trap with a counter in a file, so helpers and subshells count too) with a cut-off restart in the journal: a failure after the recovery is armed always leaves it undone, except that the final confinement read failing makes the start-up refuse an unknown journal and touch nothing; one before the arm leaves everything as it was, or undone; and the next retry undoes it
  local inj=$B/inj mut=$B/mut/inj.sh wsave clean n tot arm rc2 pre jpre post jpost kept=0 rec=0 bad= g; SWSI=
  rm -rf "$inj"; mkdir -p "$inj"
  cat > "$inj/head.txt" <<'EOS'
set -T
injtrap() {  # test only
  [ -e "$INJF.fired" ] && return 0
  local n; read -r n < "$INJF.n"; n=$((n+1)); echo "$n" > "$INJF.n"
  echo "$n ${BASH_COMMAND%%$'\n'*}" >> "$INJF.log"
  if [ "$n" = "$INJN" ]; then : > "$INJF.fired"; exit 1; fi
  return 0; }
trap injtrap DEBUG
EOS
  sed -e '/^set -u$/r '"$inj/head.txt" -e 's/^restart_settled && exit 0$/trap - DEBUG\n&/' "${WG:-$GW}" > "$mut"; chmod +x "$mut"
  bash -n "$mut" 2>/dev/null && ! cmp -s "$mut" "${WG:-$GW}" || { echo "    injector copy is not usable"; return 1; }
  wsave=${WG:-}; WG=; SRSVC=1 sr_cut || { WG=$wsave; return 1; }; WG=$wsave   # the cut-off state comes from the unmutated wrapper, so a mutation of the start-up is not already in the baseline
  sr_stubs; clean="/no/no/0//$(sha < "$J/gate0-run/marker")"; snap rcut   # undone: no marker in the checkout, no timer, no restart record, the repair service stopped, the preserved marker byte for byte
  echo 0 > "$inj/c.n"; : > "$inj/c.log"
  INJF=$inj/c INJN=0 WG=$mut wg restart r0 >> "$B/out.sw" 2>&1
  arm=$(awk '$2=="trap" && $3=="bootexit" && $4=="EXIT" {print $1; exit}' "$inj/c.log"); tot=$(awk '$2=="trap" && $3=="-" && $4=="DEBUG" {print $1; exit}' "$inj/c.log")
  { [ -n "$arm" ] && [ -n "$tot" ] && [ "$arm" -ge 8 ] && [ $((tot-arm)) -ge 15 ]; } || { echo "    injector: arm=$arm end=$tot (too few steps counted)"; return 1; }
  for ((n=1; n<=tot; n++)); do
    restore rcut; : > "$B/out.sw"; echo 0 > "$inj/k.n"; : > "$inj/k.log"; rm -f "$inj/k.fired"
    pre=$(sr_full); jpre=$(jfp)
    INJF=$inj/k INJN=$n WG=$mut wg restart r0 >> "$B/out.sw" 2>&1; rc2=$?
    [ -e "$inj/k.fired" ] || { echo "    step $n: not reached"; bad="$bad $n(not reached)"; continue; }
    post=$(sr_full); jpost=$(jfp)
    [ "$rc2" != 0 ] || { echo "    step $n: exit 0"; bad="$bad $n(exit 0)"; }
    if [ "$post" = "$clean" ]; then rec=$((rec+1))
    elif { [ "$n" -le "$arm" ] || grep -q 'its git directories (it is unknown)' "$B/out.sw"; } && [ "$post" = "$pre" ] && [ "$jpost" = "$jpre" ]; then   # after the arm only a refusal for a confinement the final read could not establish may leave the state as it was: the recovery then reads "unknown" and touches nothing
      kept=$((kept+1)); wg restart r0 >> "$B/out.sw" 2>&1; g=$(sr_full)
      [ "$g" = "$clean" ] || { echo "    step $n: the next retry left $g"; bad="$bad $n(retry)"; }
    else echo "    step $n ($(sed -n "s/^$n //p" "$inj/k.log" | head -n 1 | cut -c1-70)): left $post (journal $([ "$jpost" = "$jpre" ] && echo same || echo changed)), arm at $arm"; bad="$bad $n"; fi
  done
  SWSI="steps=$tot arm=$arm kept=$kept recovered=$rec"; echo "    injector: $SWSI"
  [ -z "$bad" ] && [ "$kept" -ge 1 ] && [ $((kept+rec)) = "$tot" ]; }

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
t_restartcrash; check "a restart cut off after the marker/service/first timer, before its record: the next restart undoes it (timers stopped, marker aside, attempt closed), the one after runs" "$RCS/$?" "137/marker/no/no/svc-yes/3//no/no/svc-no/0/0/yes/yes/recorded;137/marker/yes/no/svc-no/3//no/no/svc-no/0/0/yes/yes/recorded;/0"
t_holdsnone; check "a recorded no-marker restart: a marker that appears afterwards is undone, its bytes kept, no marker record made" "$HN0/$HN0S/$HN1/$HN1S/$?" "0/recorded/yes/yes/3//no/no//1//0"
t_archrecheck; check "capture validates the archive destination again after the last freeze check: a refused destination or a push URL that is not the validated one stops it before P1a, checkout unchanged; the validated one proceeds" "$ARS/$?" "3/3/0/1//same/0/1//same/cp/0"
t_flushfail; check "a flush that fails (the copied file before it is moved, a verified file, the sha256 file, the directory) is a STOP and the capture is not recorded" "$FFS/$?" "3/1/;3/1/;3/1/;3/1/;/0"
t_lanefail; check "a Clavain no-marker restart whose lane cannot be read is a STOP (not an unchanged lane), nothing recorded, timers stay stopped" "$LFC/$LFS/$?" "3/1//no/no/0"
t_archfail; check "a failed read of the lane tip or of the archive branches (before or after the run) is a STOP, never an equal empty listing; nothing recorded, timers stopped, marker aside" "$AFS/$?" "3/1//no/no/;3/1//no/no/;3/1//no/no/;/0"
t_svcoverride; check "with a custom service list the repair service is still stopped by the cleanup of a cut-off restart" "$SOS/$?" "137/3/no/no/no//0"
t_hookafter; check "a writing hook installed after preflight stops capture before its fetch: exit 3, hook not run, P1-pre not run" "$HAC/$HAS/$?" "3/1///0"

echo "== class sweep: a read whose status or content a decision rests on is checked where it is used"
HAVE_PROC=$([ -r /proc/self/fd/0 ] && echo 1)
sc() { local lbl=$1 fn=$2; shift 2; "$fn"; check "$lbl" "$([ $? = 0 ] && echo fail-closed || echo open)" fail-closed; }
[ -n "$HAVE_PROC" ] && {
sc "a marker that cannot be hashed is not recorded at the freeze: exit 3, no freeze record" t_swfreezesha
sc "an installed hook that cannot be hashed is a STOP at preflight" t_swhooksha
sc "a restored marker is not compared with a missing record (restore, and a recorded restart)" t_swmarkrec; }
sc "a failed read of core.hooksPath or of the hooks directory is a STOP, not no hook" t_swhookgit
sc "a failed git-directory, count or status read is a STOP at preflight" t_swready
sc "an archive listing that fails is not an empty one" t_swarchlist
sc "the preflight record never names an empty head" t_swheadrec
sc "a missing, empty or damaged P1-pre head is a STOP (restart and a repeated capture)" t_swp1pre
sc "an unreadable tree or index after P1a is a STOP and capture is not recorded" t_swtree
sc "a failed status read behind the marker rule starts nothing" t_swrestatus
sc "a failed filter behind the marker rule starts nothing" t_swmarkfilter
sc "a failed gate0 tag read, before or after the run, is a STOP with the marker aside" t_swtags
sc "no journal cursor is a STOP before the service starts" t_swjcursor
sc "a Clavain restart with no P0 lane record is a STOP" t_swp0lane
sc "a restart validates the archive destination and push URL itself, on both machines" t_swarchready
[ -n "$HAVE_PROC" ] && sc "a hash that prints and then fails is not a hash" t_swshaout
sc "the production unit controller branch: the word and the status must agree, a transitional state is unconfirmed" t_swunitstate
sc "a journal read that fails after its output is a STOP with the marker aside" t_swjournal
sc "an lsof listing whose filter fails is a STOP, not no agent" t_swlsofawk
sc "--check: a failed read of origin/main is a STOP, not an empty value equal to another" t_swlsremote
sc "cleanup with an unreadable freeze record still stops every configured timer" t_swrecrbail
sc "a recorded restart whose freeze record fails after its output is undone, not trusted" t_swrecholds
sc "the timers to start are not taken from a record read that failed" t_swstep5
sc "a freeze record or freeze intent that fails after its output is not a list to trust" t_swfreezerec
sc "a push URL read that prints the validated URL and then fails is a STOP before anything runs" t_swpushurl
sc "R0 without P1a: an unreadable or unfilterable status record is a STOP" t_swr0status
sc "an unmerged-entries read that fails after its output is a STOP" t_swlsfilesu
sc "a HEAD, origin/main or tag read that prints a match and then fails is not a match" t_swpgs
sc "an unreadable P0 lane record is not an empty tip" t_swp0laneread
sc "an approved input that cannot be read is refused" t_swinputs
sc "a capture sha256 record that names the wrong files is a STOP" t_swsharec
sc "a restored marker whose recorded hash is read with a failing status is a STOP" t_swrestmark
sc "a restart-set list that fails after its output is not written and nothing is stopped" t_swactlines
sc "the sha256 record verifier needs two completed checks and accepts an unterminated last line" t_swverifyset
sc "restoring the set-aside marker keeps the bytes it replaces" t_swrestover
sc "a sha256 record with no final newline is verified in full and a bad capture never replaces the preservation copy" t_swsharecterm
sc "a freeze record that cannot be read does not take the no-marker path of a Clavain restart" t_swclavmark
sc "the test's before and after observers fail closed" t_swobserver
sc "the capture's sha256 names read with a failing status are a STOP" t_swcapnames
sc "a user id that cannot be read stops the wrapper before it does anything" t_swidfail
sc "a /proc listing that cannot be read is not an empty process table" t_swprocenum
sc "the private pre-commit hook refuses when the staged-path listing fails" t_swprecommit
sc "the overlay driver refuses when the unmerged-entry list or the remote-ref list cannot be read" t_swgi
sc "the overlay driver's finish-the-step check refuses an index tree or recorded tree that is printed and then fails to read" t_swgitidx
sc "resolve refuses a resolved file whose conflict-marker read fails" t_swresolve
sc "same_blob does not match a blob that a failed hash printed" t_swsameblob
sc "forward reads ORIG_HEAD with its status and reads it back with its status" t_sworighead
sc "the host name is read with its status in the driver and in the private pre-push hook" t_swhost
sc "an interrupted overlay install's git dir is ignored by the public .gitignore" t_swignore
sc "a repeated freeze checks the whole invariant" t_swfreezerep
sc "a restart cut off by a stop or a signal after its record is written is undone by the EXIT trap: no record, nothing running, marker aside, a failed exit" t_swexitclean
sc "a new freeze does not record the earlier attempt's marker copy when the checkout has no marker" t_swrefreezegone
sc "--check never writes, from every freeze and restart state" t_swcheckro
sc "no git variable and no core.worktree points the wrapper away from the validated checkout" t_swgitenv
sc "every git location and configuration variable is gone before any git of the wrapper or its steps starts" t_swgitvars
sc "a checkout pointed elsewhere after the first check is refused at the next use of git" t_swgitmid
sc "the overlay driver starts no git with an inherited location or configuration" t_swgitgi
sc "a restart whose git stops showing the checkout is undone before the run ends" t_swgitrst
sc "each git call of a restart failing in turn leaves the restart undone or complete, never half done" t_swgitfailall
sc "a git directory link or common directory link that is read with a failing status is no binding" t_swgitlink
sc "a lane remote with a second push URL is refused" t_swpushurls
sc "no process substitution feeds a loop in the overlay driver or its hooks" t_swnoprocsub
sc "restart step 1 checks both entries of the capture's sha256 record, a last line with no newline included" t_swrestcap
sc "the jsonl_dominated extraction and load are status-checked and an inherited function is not accepted" t_swreconeval
sc "no state, journal, preservation or log directory may be inside the common git directory of a linked worktree" t_swgitcommon
sc "a cut-off restart is undone before any input is validated, and a new attempt still needs the inputs" t_swrestartclean
sc "the start-up case tables list every statement that can end the start, before and after the recovery is armed" t_swstartguards
sc "a cut-off restart is undone by a retry whose start fails at any step after the arm, one case for each statement of the start-up" t_swstartrecover
sc "a retry that fails before the recovery is armed changes nothing, and the next retry undoes the cut-off restart" t_swprearm
sc "a retry whose journal is not confined is refused and touches nothing: no write, nothing stopped" t_swunconfined
sc "every layout of .git and every place of the journal: refuse or run and recover as git's own answer says" t_swlayouts
sc "a transient failure of the first confinement read does not stay, and an early safe is revoked by the final decision" t_swtransient
sc "every command of the start-up failed in turn: after the arm the cut-off restart is undone, before it nothing changed" t_swstartinject

echo "== mutation controls (each must be judged NOT fail-closed)"
mutate() {  # NAME SEDEXPR : a copy of the wrapper with one safeguard removed; WG names it
  sed "$2" "$GW" > "$B/mut/$1.sh" || { echo "  FAIL mutation $1: the sed expression failed"; fails=$((fails+1)); return 1; }
  chmod +x "$B/mut/$1.sh"
  cmp -s "$GW" "$B/mut/$1.sh" && { echo "  FAIL mutation $1 changed nothing"; fails=$((fails+1)); return 1; }
  bash -n "$B/mut/$1.sh" 2>/dev/null || { echo "  FAIL mutation $1 left a wrapper that does not parse (a control against a broken file proves nothing)"; fails=$((fails+1)); return 1; }
  cp "$HERE/cutover-steps.sh" "$B/mut/cutover-steps.sh"; return 0; }
mutate M1 's/|| stop "the marker is back in the checkout: the freeze no longer holds"/|| true/' &&
  { WG=$B/mut/M1.sh; t_markerback; r=$?; WG=; check "M1 (no marker check before capture) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M2 's/^  hook_check   # first:.*/  :/' &&
  { WG=$B/mut/M2.sh; t_hook; r=$?; WG=; check "M2 (no hook check) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M3 's/rbail "the run differs/stop "the run differs/; s/INCLEAN=1; ( rcleanup ) >\/dev\/null || :   #/:   #/' &&   # the caller's recovery and the EXIT-trap net both gone
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
mutate M10 's/^  if \[ -e "\$G\/restarted-\$XARG" \]; then restarted_holds.*$/  :/' &&
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
mutate M17 's/ unrecord_bail$//; s/INCLEAN=1; ( rcleanup ) >\/dev\/null || :   #/:   #/' &&   # the handler and the EXIT-trap net both gone
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
mutate M27 's/^  \[ -z "\$RBAD" \] || say .*$/  :/; s/\${RBAD:+; UNCONFIRMED stop of\$RBAD}//' &&
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

mutate M34 's/^  if restarting_any; then rbail /  if false; then rbail /; s/\&\& restarting_any; }$/\&\& false; }/' &&   # the settled check and the start-up/EXIT-trap net both stop looking for an earlier attempt
  { WG=$B/mut/M34.sh; t_restartcrash; r=$?; WG=; check "M34 (an earlier restart attempt that left no record is not looked for) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M35 's/\[ ! -e "\$ROOT\/.git-autosync" \] || unrecord_bail "restart \$1 is recorded with no marker[^"]*"/:/' &&
  { WG=$B/mut/M35.sh; t_holdsnone; r=$?; WG=; check "M35 (a recorded no-marker restart does not check the marker stays absent) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M36 's/^  if \[ "\${1:-}" = force \] \&\& \[ ! -e "\$G\/marker" \]/  if false \&\& [ ! -e "$G\/marker" ]/' &&
  { WG=$B/mut/M36.sh; t_holdsnone; r=$?; WG=; check "M36 (cleanup of a no-marker record makes a marker record instead of keeping the bytes) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M37 's/^  archive_check$/  :/' &&
  { WG=$B/mut/M37.sh; t_archrecheck; r=$?; WG=; check "M37 (no archive destination re-validation before P1a) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M38 's/^  \[ -n "\${ASL_URL:-}" \] && \[ "\$pu" = "\$ASL_URL" \] || stop .*/  :; }/' &&
  { WG=$B/mut/M38.sh; t_archrecheck; r=$?; WG=; check "M38 (P1a not bound to the validated push URL) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M39 's/ \&\& flush_path "\$d\/\$f.tmp.\$\$"//' &&
  { WG=$B/mut/M39.sh; t_flushfail; r=$?; WG=; check "M39 (the copied file is not flushed before it is moved) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M40 '/^  for f in main.bundle wtree.tar wtree.manifest sha256; do flush_path/d' &&
  { WG=$B/mut/M40.sh; t_flushfail; r=$?; WG=; check "M40 (the verified files are not flushed) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M41 's/^  flush_path "\$d" || stop .*/  flush_path "$d" || true/' &&
  { WG=$B/mut/M41.sh; t_flushfail; r=$?; WG=; check "M41 (a failed directory flush is ignored) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M42 's/^    tipn=\$(pg ls-remote "\$LANE" "refs\/heads\/autosync\/\$HOST") || stop .*/    tipn=$(pg ls-remote "$LANE" "refs\/heads\/autosync\/$HOST")/' &&
  { WG=$B/mut/M42.sh; t_lanefail; r=$?; WG=; check "M42 (a failed lane read is taken for an unchanged lane) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M43 '/# a service a cut-off restart left running is stopped too/ s/ \$SERVICES;/;/' &&
  { WG=$B/mut/M43.sh; t_restartcrash; r=$?; WG=; check "M43 (a cleanup does not stop the services) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M44 's/o=\$(pg ls-remote "\$LANE" "\$1") || return 1/o=$(pg ls-remote "$LANE" "$1")/' &&
  { WG=$B/mut/M44.sh; t_archfail; r=$?; WG=; check "M44 (a failed lane read is an empty listing) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M45 '/^case " \$SERVICES " in/d' &&
  { WG=$B/mut/M45.sh; t_svcoverride; r=$?; WG=; check "M45 (the repair service is not bound to the configured list) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M46 '/^  hook_check   # a hook installed after preflight/d' &&
  { WG=$B/mut/M46.sh; t_hookafter; r=$?; WG=; check "M46 (no hook check after preflight) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
[ -n "$HAVE_PROC" ] && mutate M47 's/w=\$(sha < "\$G\/marker") || stop "cannot hash the marker set aside[^"]*"/w=$(sha < "$G\/marker")/' &&
  { WG=$B/mut/M47.sh; t_swfreezesha; r=$?; WG=; check "M47 (a marker that cannot be hashed is recorded as empty) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
[ -n "$HAVE_PROC" ] && mutate M48 's/s=\$(sha < "\$h") || stop "cannot hash the installed[^"]*"/s=$(sha < "$h")/' &&
  { WG=$B/mut/M48.sh; t_swhooksha; r=$?; WG=; check "M48 (a hook that cannot be hashed is compared as empty) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M49 's/\*) stop "cannot read core.hooksPath[^"]*" ;;/*) ;;/' &&
  { WG=$B/mut/M49.sh; t_swhookgit; r=$?; WG=; check "M49 (a failed core.hooksPath read is no hook) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M50 's/ \&\& \[ -n "\$hp" \] || stop "cannot locate the hooks directory[^"]*"//' &&
  { WG=$B/mut/M50.sh; t_swhookgit; r=$?; WG=; check "M50 (a failed hooks-directory read is no hook) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M51 's/ \&\& \[ -n "\$gd" \] || stop "cannot read the git directory[^"]*"//' &&
  { WG=$B/mut/M51.sh; t_swready; r=$?; WG=; check "M51 (a failed git-directory read is accepted) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M52 's/b=\$(pg rev-list --left-right --count HEAD...refs\/remotes\/origin\/main) || stop "[^"]*"/b=$(pg rev-list --left-right --count HEAD...refs\/remotes\/origin\/main)/' &&
  { WG=$B/mut/M52.sh; t_swready; r=$?; WG=; check "M52 (a failed commit count is accepted) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M53 's/st=\$(pg status --porcelain --untracked-files=no) || stop "[^"]*"/st=$(pg status --porcelain --untracked-files=no)/' &&
  { WG=$B/mut/M53.sh; t_swready; r=$?; WG=; check "M53 (a failed local-changes status is accepted) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M54 's/ut=\$(pg status --porcelain --untracked-files=all) || stop "[^"]*"/ut=$(pg status --porcelain --untracked-files=all)/' &&
  { WG=$B/mut/M54.sh; t_swready; r=$?; WG=; check "M54 (a failed untracked status is accepted) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M55 's/r=\$(pg ls-remote "\$LANE" "refs\/heads\/\$o\/\*") || stop "[^"]*"/r=$(pg ls-remote "$LANE" "refs\/heads\/$o\/*")/' &&
  { WG=$B/mut/M55.sh; t_swarchlist; r=$?; WG=; check "M55 (a failed archive listing is an empty one) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M56 's/ \&\& \[\[ \$hd =~ \^\[0-9a-f\]{40}\$ \]\] || stop "cannot read HEAD[^"]*"//' &&
  { WG=$B/mut/M56.sh; t_swheadrec; r=$?; WG=; check "M56 (the preflight record accepts an empty head) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M57 's/ \&\& \[\[ \$OLD =~ \^\[0-9a-f\]{40}\$ \]\] || stop "the P1-pre record[^"]*"//' &&
  { WG=$B/mut/M57.sh; t_swp1pre; r=$?; WG=; check "M57 (a damaged P1-pre head is accepted) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M58 's/ \&\& \[\[ \$t =~ \^\[0-9a-f\]{40}\$ \]\] || stop "re-check: cannot read[^"]*"//' &&
  { WG=$B/mut/M58.sh; t_swtree; r=$?; WG=; check "M58 (an unreadable base tree is accepted) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M59 's/ \&\& \[ "\$w" = "\$t" \] || stop "re-check: the index[^"]*"//' &&
  { WG=$B/mut/M59.sh; t_swtree; r=$?; WG=; check "M59 (an unreadable index tree is accepted) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
[ -n "$HAVE_PROC" ] && mutate M60 's/\[\[ \$m =~ \^\[0-9a-f\]{64}\$ \]\] \&\& \(\[ "\$(sha < "\$ROOT\/.git-autosync")" = "\$m" \]\); }/\1; }/' &&
  { WG=$B/mut/M60.sh; t_swmarkrec; r=$?; WG=; check "M60 (the restored marker is compared without checking the record) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M61 's/st=\$(pg status --porcelain=v1 --untracked-files=all) || rbail "[^"]*"/st=$(pg status --porcelain=v1 --untracked-files=all)/' &&
  { WG=$B/mut/M61.sh; t_swrestatus; r=$?; WG=; check "M61 (a failed status read behind the marker rule is accepted) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M62 's/tags0=\$(tag_refs) || rbail "[^"]*"/tags0=$(tag_refs)/' &&
  { WG=$B/mut/M62.sh; t_swtags; r=$?; WG=; check "M62 (a failed tag read before the run is accepted) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M63 's/tags1=\$(tag_refs) || rbail "[^"]*"/tags1=$(tag_refs)/' &&
  { WG=$B/mut/M63.sh; t_swtags; r=$?; WG=; check "M63 (a failed tag read after the run is accepted) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M64 's/cur=\$(journal_cursor) \&\& \[ -n "\$cur" \] || rbail "[^"]*"/cur=$(journal_cursor)/' &&
  { WG=$B/mut/M64.sh; t_swjcursor; r=$?; WG=; check "M64 (no journal cursor is accepted) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M65 's/\[ -f "\$J\/p0\/lane" \] || stop "the P0 lane record[^"]*"/true/; s/l0=\$(cat "\$J\/p0\/lane") || stop "[^"]*"/l0=$(cat "$J\/p0\/lane" 2>\/dev\/null)/' &&
  { WG=$B/mut/M65.sh; t_swp0lane; r=$?; WG=; check "M65 (a missing P0 lane record is accepted) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M66 '/^  archive_ready   # the lane this restart/d' &&
  { WG=$B/mut/M66.sh; t_swarchready; r=$?; WG=; check "M66 (the restart does not validate the archive destination itself) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
[ -n "$HAVE_PROC" ] && mutate M67 '/^then sha() {/s/set -o pipefail; //' &&
  { WG=$B/mut/M67.sh; t_swshaout; r=$?; WG=; check "M67 (a hash that fails after its output is used) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M68 's/^  case \$out\/\$rc in .*/  case $out in active|activating|reloading|deactivating) echo active ;; inactive|failed) echo inactive ;; *) echo unknown ;; esac; }/' &&
  { WG=$B/mut/M68.sh; t_swunitstate; r=$?; WG=; check "M68 (the controller's word is trusted without its status) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M69 's/^  while :; do if journal_since "\$cur" > "\$LOGD\/journal.txt"; then jok=1; /  while :; do if journal_since "$cur" > "$LOGD\/journal.txt" || true; then jok=1; /' &&
  { WG=$B/mut/M69.sh; t_swjournal; r=$?; WG=; check "M69 (a failed journal read is accepted) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M70 's/ || return 2   # a filter that fails shows no agents; that is not "none"//' &&
  { WG=$B/mut/M70.sh; t_swlsofawk; r=$?; WG=; check "M70 (a failed lsof filter shows no agents) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mutate M71 's/^  else rm_=.*/  else rm_=$(pg ls-remote origin refs\/heads\/main | cut -f1)/' &&
  { WG=$B/mut/M71.sh; t_swlsremote; r=$?; WG=; check "M71 (the remote read behind --check is not checked) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mm() {  # NAME TEST DESC SEDEXPR : one more mutation control
  local n=$1 t=$2 d=$3; mutate "$n" "$4" && { WG=$B/mut/$n.sh; $t; r=$?; WG=; check "$n ($d) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }; }
mm M72 t_swrecrbail "cleanup without a readable freeze record stops no timer" 's/^  ts=\$(rec_timers) || { ts=\$TIMERS; say [^}]*}/  ts=$(rec_timers)/'
mm M73 t_swrecholds "the recorded timers are trusted after a failed read" 's/^  ts=\$(rec_timers) || unrecord_bail "[^"]*"/  ts=$(rec_timers)/'
mm M74 t_swrecholds "the recorded marker is trusted after a failed read" 's/^  m=\$(rec_marker) || unrecord_bail "[^"]*"/  m=$(rec_marker)/'
mm M75 t_swstep5 "timers are started from a failed read" 's/ts=\$(rec_timers) || rbail "the freeze record cannot be read: the timers to start[^"]*"/ts=$(rec_timers)/'
mm M76 t_swfreezerec "a recorded freeze is trusted after a failed read" 's/^    a=\$(rec_timers) || stop "[^"]*"/    a=$(rec_timers)/'
mm M77 t_swfreezerec "an earlier freeze intent is trusted after a failed read" 's/ || prior=\$(rec_timers "\$G\/freeze-intent") || stop "[^"]*"/ || prior=$(rec_timers "$G\/freeze-intent")/'
mm M78 t_swpushurl "the push URL is compared after a failed read" 's/2>\/dev\/null) || stop "cannot read the push URL[^"]*"/2>\/dev\/null)/'
mm M79 t_swr0status "an unreadable status record is read as empty" 's/sr=\$(cat "\$J\/p1-pre\/status.all") || stop "[^"]*"/sr=$(cat "$J\/p1-pre\/status.all" 2>\/dev\/null)/'
mm M80 t_swr0status "a failed status filter is accepted" 's/^nobeads() { local rc; grep -v .*$/nobeads() { grep -v " \\.beads\/issues\\.jsonl$"; true; }/'
mm M81 t_swlsfilesu "a failed unmerged-entries read is accepted" 's/ || stop "cannot read the index: unmerged entries cannot be ruled out"//'
mm M82 t_swpgs "output-then-failure reads are compared" 's/\$(pgs /$(pg /g'
mm M83 t_swp0laneread "an unreadable P0 lane record is read as empty" 's/l0=\$(cat "\$J\/p0\/lane") || stop "[^"]*"/l0=$(cat "$J\/p0\/lane" 2>\/dev\/null)/'
mm M84 t_swinputs "an unreadable input is read as empty" 's/ \&\& LANE=\$(cat "\$J\/lane-remote") \&\& \[ -n "\$LANE" \] || refuse "an input in J cannot be read"/; LANE=$(cat "$J\/lane-remote" 2>\/dev\/null)/'
mm M85 t_swsharec "a sha256 record naming fewer files is accepted" '/^  \[ "\$n" = "main.bundle wtree.tar" \] || stop /d'
mm M86 t_swmarkfilter "a failed marker-rule filter is read as a clean status" 's/ || rbail "cannot filter the status for the marker rule[^"]*"/ || true/'
mm M87 t_swrestmark "a restored marker is compared after a failed read" 's/{ m=\$(rec_marker) \&\& \[\[/{ m=$(rec_marker); [[/'
mm M88 t_swactlines "the restart-set list is built without pipefail" 's/^act_lines() { ( set -o pipefail; /act_lines() { ( /'
mm M89 t_swactlines "a failed restart-set list is written" 's/^  al=\$(act_lines "\$act") || stop "[^"]*"/  al=$(act_lines "$act")/'
mm M90 t_swverifyset "an unterminated last record line is dropped" 's/ || \[ -n "\$f" \]; do/; do/'
mm M91 t_swverifyset "the number of completed checks is not required" 's/^  \[ \$n = 2 \]; }$/  true; }/'
mm M92 t_swsharecterm "the preservation copy is replaced before the capture is verified" 's/^  { verify_set "\$d" ".tmp.\$\$" \&\& .*$/  true ||/'
mm M93 t_swrestover "the restore replaces other marker bytes without keeping them" 's/^  if \[ -f "\$G\/marker" \] \&\& \[ -e "\$ROOT\/.git-autosync" \].*$/  :/'
mm M94 t_swclavmark "the freeze record's marker line is read with its status ignored" 's/^  mrec=\$(rec_marker) || stop "[^"]*"[^\n]*$/  mrec=$(rec_marker)/'
mm M95 t_swcapnames "the names read loses its pipefail" 's/n=\$(set -o pipefail; cut -f1/n=$(cut -f1/'
mm M96 t_swcapnames "the status check on the names read is removed; the name comparison after it still refuses, so this pins the dedicated diagnostic (defense in depth)" 's/^  n=\$(capture_names) || stop "[^"]*"/  n=$(capture_names)/'
mm M97 t_swrestcap "restart does not check the capture itself" 's/^    capture_check || stop "restart step 1: [^"]*"/    :/'
mm M98 t_swrestcap "the capture check ignores the digests" 's/ \&\& verify_set "\$J\/capture"; }$/; }/'
mm M99 t_swreconeval "the extraction status and whole-function check are removed" 's/^  def=\$(sed -n \(.*\) "\$CS") \&\& \[\[ .* \]\] || stop "[^"]*"/  def=$(sed -n \1 "$CS")/'
mm M100 t_swreconeval "the load status is ignored" 's/^  eval "\$def" || stop "[^"]*"/  eval "$def"/'
mm M101 t_swidfail "a user id that cannot be read is taken as not root" 's/^MYUID=\$(id -u 2>\/dev\/null) .*$/MYUID=$(id -u 2>\/dev\/null)/'
mm M102 t_swprocenum "the /proc listing is not required to show this script" 's/^    \[ -n "\$me" \] || return 2 .*$/    :/'
mgi_prep() {  # NAME SED : the mutated copy of the overlay driver; fails when sed fails, when nothing changed, or when the result does not parse (a control against a file that is not the driver with one fix removed proves nothing)
  sed "$2" "$HERE/../git-internal" > "$B/mut/$1-gi" 2>/dev/null && ! cmp -s "$HERE/../git-internal" "$B/mut/$1-gi" && bash -n "$B/mut/$1-gi" 2>/dev/null; }
mgi() {  # NAME TEST DESC SED : the same test against the overlay driver with the fix taken out must fail
  local n=$1 t=$2 d=$3 e=$4 r
  if ! mgi_prep "$n" "$e"; then echo "  FAIL mutation $n: the sed failed, changed nothing, or left a driver that does not parse"; fails=$((fails+1))
  else GI=$B/mut/$n-gi; $t; r=$?; GI=; check "$n ($d) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; fi
}
mgi M104 t_swgi "a failed driver read of the unmerged paths is taken as an empty one" 's/^  u=\$(gi ls-files -u) || die 4 "[^"]*".*$/  u=$(gi ls-files -u)/'
mgi M105 t_swgi "a failed driver read of the remote refs is taken as an empty one" 's/ || die 6 "cannot list the remote refs".*$//'
mgi M111 t_swgitidx "a write-tree that prints and fails is taken as the index tree" 's/t=\$(gi write-tree 2>\/dev\/null) \&\& ot=/t=$(gi write-tree 2>\/dev\/null); ot=/'
mgi M112 t_swgitidx "the recorded trees are read without their status" 's/ \&\& ot=\$(gi rev-parse/; ot=$(gi rev-parse/;s/ \&\& nt=\$(gi rev-parse/; nt=$(gi rev-parse/'
mgi M113 t_swresolve "a failed conflict-marker read is taken as no markers" 's/^      \[ \$rc = 1 \] || { rm -f -- "\${idx:?}"; die 6 "resolve: cannot read.*$/      :/'
mgi M114 t_swsameblob "the hash status is not held" 's/dm=\$(disk_mode "\$2") \&\& db=\$(disk_blob "\$2") || return 1/dm=$(disk_mode "$2"); db=$(disk_blob "$2")/'
mgi M115 t_sworighead "an initial ORIG_HEAD read that prints and fails is taken as set" 's/ORIG_HEAD) || og=   #.*$/ORIG_HEAD)/'
mgi M116 t_sworighead "the ORIG_HEAD read-back status is not held" 's/ \&\& og=\$(gi rev-parse -q --verify ORIG_HEAD) \&\& \[ "\$og"/; og=$(gi rev-parse -q --verify ORIG_HEAD); [ "$og"/'
mgi M117 t_swhost "the driver's host read status is not held" 's/h=\$(cat "\$GD\/info\/host" 2>\/dev\/null) \&\& \[ -n "\$h" \] || die 4/h=$(cat "$GD\/info\/host" 2>\/dev\/null); [ -n "$h" ] || die 4/'
if sed 's/host=\$(cat "\$gd\/info\/host" 2>\/dev\/null) || host=$/host=$(cat "$gd\/info\/host" 2>\/dev\/null)/' "$HERE/../git-internal-hooks/pre-push" > "$B/mut/M118-hook" && ! cmp -s "$HERE/../git-internal-hooks/pre-push" "$B/mut/M118-hook"; then
  PPHOOK=$B/mut/M118-hook; t_swhost; r=$?; PPHOOK=; check "M118 (the pre-push hook keeps a host name that a failed read printed) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught
else echo "  FAIL mutation M118 changed nothing"; fails=$((fails+1)); fi
mgi M119 t_swresolve "a mode that a failed read printed is recorded" 's/mode=\$(disk_mode "\$p") || { rm -f -- "\${idx:?}"; die 6 "resolve: cannot read the mode of \$p"; }/mode=$(disk_mode "$p")/'
mgi_prep M124 's/(/' ; a=$?; mgi_prep M124 's/zzzqq-not-present/x/'; b=$?; mgi_prep M124 's/^#!.*/if/'; c=$?; mgi_prep M124 's/^host() {/host() {/' ; e=$?
check "M124 (a mutation of the driver whose sed fails, changes nothing or leaves a script that does not parse is rejected, a real one accepted)" "$([ $a != 0 ] && [ $b != 0 ] && [ $c != 0 ] && [ $e != 0 ] && mgi_prep M124 's/^host() {/host() { :;/' && echo rejected)" rejected
mm M120 t_swgitcommon "the common git directory is not checked for the state, journal and preservation directories" 's/! within "\${d#\*:}" "\$ROOT" "\$GD" "\$GC" ||/! within "${d#*:}" "$ROOT" "$GD" ||/'
mm M121 t_swgitcommon "the log directory may be inside the common git directory" 's/"\$GD" "\$GC" "\$J" "\$PRES" ||/"$GD" "$J" "$PRES" ||/'
mutate M122 '/^restart_settled \&\& exit 0$/d; s/^need_inputs$/need_inputs\nrestart_settled \&\& exit 0/' &&
  { WG=$B/mut/M122.sh; t_swrestartclean; r=$?; WG=; check "M122 (diagnostic only: a restart cleanup placed after the input validation changes the exit status and the message of a blocked input; M145 to M148 are the controls that lose the recovery, M149 to M152 guard the case tables, M153 to M161 the single confinement decision and the start-up injector) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; }
mm M123 t_swrestartclean "a recorded restart is no longer re-verified before the input validation" 's/^  if \[ -e "\$G\/restarted-\$XARG" \]; then restarted_holds "\$XARG"; return 0; fi.*$/  :/'
mm M109 t_swrefreezegone "a new freeze records the earlier attempt's marker copy although the checkout has no marker" 's/^    else mv -f -- "\$G\/marker" "\$G\/marker.earlier.\$w" \&\& \[ ! -e "\$G\/marker" \] || stop "cannot set the earlier attempt.s marker copy aside"$/    else :/'
mm M125 t_swcheckro "--check freeze sets the earlier attempt's marker copy aside" 's/^    if \[ \$CHECKMODE = 1 \]; then say "gate0-run: freeze check: the checkout has no marker.*$/    if false; then :/'
mm M126 t_swcheckro "--check freeze stops the timers" 's/^  if \[ \$CHECKMODE = 1 \]; then say "gate0-run: freeze check: would stop/  if false; then say "gate0-run: freeze check: would stop/'
mm M127 t_swcheckro "--check preflight records P0" 's/^  if \[ \$CHECKMODE = 1 \]; then env CUTOVER_REPORT=0 "\$CS" --check/  if false; then env CUTOVER_REPORT=0 "$CS" --check/'
mm M128 t_swcheckro "--check rollback rolls back" 's/^  if \[ \$CHECKMODE = 1 \]; then say "gate0-run: rollback check/  if false; then say "gate0-run: rollback check/'
mm M129 t_swcheckro "--check restart restarts" '/^do_restart() {/,/^  \[ -e "\$G\/freeze" \]/ s/^  if \[ \$CHECKMODE = 1 \]; then$/  if false; then/'
mm M130 t_swcheckro "--check capture captures" '/^do_capture() {/,/P1a is already recorded/ s/^  if \[ \$CHECKMODE = 1 \]; then$/  if false; then/'
mm M131 t_swgitvars "git's location and configuration variables are inherited" 's/^    GIT_\*) unset "\$_v" ;; esac; done$/    GIT_*) : ;; esac; done/'
mm M132 t_swgitenv "a work tree other than GATE0_ROOT is accepted" 's/\[ "\$t" = "\$ROOT" \] ||/true ||/'
mm M133 t_swgitmid "the checkout is not checked again before each git on it" 's/^pg() { git_bind; /pg() { /; s/^inroot() { git_bind; /inroot() { /'
mm M134 t_swgitvars "the scrub keeps the variables of a config file selected by name" 's/GIT_CONFIG_GLOBAL|GIT_CONFIG_NOSYSTEM|GIT_TERMINAL_PROMPT/GIT_CONFIG_*|GIT_TERMINAL_PROMPT/'
mm M135 t_swgitenv "the git directory is not compared with the one the checkout names" 's/ \&\& \[ "\$d" = "\$e" \] \&\& \[ "\$c" = "\$ec" \] || bindfail/ || bindfail/'
mm M136 t_swgitrst "diagnostic only: the bind-failure trap no longer says why; the EXIT-trap cleanup still undoes the restart (M141 and M143 are the controls that lose the recovery)" 's/^  if \[ -n "\$RSTART" \] \&\& \[ -z "\${INCLEAN:-}" \]; then.*; fi$/  :/'
mm M137 t_swgitlink "a failing gitdir link read is accepted" 's/ \&\& \[ -n "\$f" \] || { NERR="GATE0_ROOT\/.git is neither[^"]*"; return 1; }/ || :/'
mm M138 t_swgitlink "a failing commondir read is accepted" 's/ \&\& \[ -n "\$x" \] || { NERR="the common directory link of the git directory cannot be read"; return 1; }/ || :/'
mm M139 t_swgitfailall "the cleanup of a failed restart leaves the marker in the checkout" 's/^  move_marker_aside force; \[ -n "\$RBAD" \]/  [ -n "$RBAD" ]/'
mm M140 t_swgitfailall "the cleanup of a failed restart leaves the repair service running" 's/^  for u in \$ts \$SERVICES; do units stop "\$u" >\/dev\/null 2>&1; done/  for u in $ts; do units stop "$u" >\/dev\/null 2>\&1; done/'
mm M141 t_swexitclean "the EXIT trap does not undo an open restart attempt" 's/INCLEAN=1; ( rcleanup ) >\/dev\/null || :   #/:   #/'
mm M142 t_swexitclean "a signal is not turned into a failed exit" "s/^trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP.*\$/:/"
mm M143 t_swstartrecover "a start that fails before the log directory exists leaves a cut-off restart live" 's/^trap bootexit EXIT$/:/'
mm M144 t_swstartrecover "the start-up exit trap does not undo a cut-off restart" '/^bootexit()/,/^  exit \$rc; }/ s/if undo_open_restart; then/if false; then/'
mm M145 t_swstartrecover "the preservation path is resolved before the recovery is armed" '/^PRES=/d; s/^trap bootexit EXIT$/PRES=$(physpath "${GATE0_PRESERVE_DIR:-$SD\/preserve}") || { echo "gate0-run: cannot use GATE0_PRESERVE_DIR" >\&2; exit 1; }\ntrap bootexit EXIT/'
mm M146 t_swstartrecover "the checkout's .git is asked for before the recovery is armed" '/^\[ -e "\$ROOT\/.git" \] ||/d; s/^trap bootexit EXIT$/[ -e "$ROOT\/.git" ] || { echo "gate0-run: GATE0_ROOT is not a git checkout" >\&2; exit 1; }\ntrap bootexit EXIT/'
mm M147 t_swstartrecover "git's view of the checkout is bound before the recovery is armed" '/^BINDRC=1; git_bind$/d; s/^trap bootexit EXIT$/BINDRC=1; git_bind\ntrap bootexit EXIT/'
mm M148 t_swstartrecover "the machine name is checked before the recovery is armed" '/^MACHINE=/d; s/^trap bootexit EXIT$/MACHINE=${GATE0_MACHINE:-server}; case $MACHINE in server|clavain) ;; *) echo "gate0-run: GATE0_MACHINE is server or clavain" >\&2; exit 1 ;; esac\ntrap bootexit EXIT/'
mm M149 t_swstartguards "a new statement that can end the start-up has no case" 's/^BINDRC=1; git_bind$/&\n[ -d \/ ] || exit 1/'
mm M150 t_swstartguards "a case names a statement that is gone" '/^self_sha$/d'
mm M151 t_swstartguards "a new statement before the recovery is armed has no case" 's/^PHASE=\${1:-}; XARG=\${2:-}$/&\n[ -d \/ ] || exit 1/'
mm M152 t_swprearm "a retry that fails before the arm clears the open restart's records" 's/^\[ -n "\$PHASE" \] || { echo "usage/[ -n "$PHASE" ] || { rm -f -- "${GATE0_JOURNAL:-\/nonexistent}"\/gate0-run\/restarting-*; echo "usage/'
mm M153 t_swunconfined "the recovery ignores whether the journal passed confinement" 's/^  \[ "\${JSAFE:-unknown}" = safe \] || return 1$/  :/'
mm M154 t_swunconfined "the git directories the checkout names are left out of the journal confinement" 's/within "\$J" "\$ROOT" \${NE:+"\$NE"} \${NEC:+"\$NEC"}/within "$J" "$ROOT"/'
mm M155 t_swunconfined "git directories that cannot be read count as confined" 's/gitnames \&\& r=read; else/gitnames; r=read; else/'
mm M156 t_swstartinject "a write into the journal before the recovery is armed (no lexical table sees it)" 's/^confine   # before the arm.*$/: > "$J\/early-write"\n&/'
mm M157 t_swtransient "no final confinement after the checkout is bound: the result of the first, possibly failed, read stays" '/^confine   # the final decision/d'
mm M158 t_swlayouts "the start-up does not refuse a journal that is not confined" '/^\[ "\$JSAFE" = safe \] || {/d'
mm M159 t_swtransient "the early result is kept when it is not unknown: an early safe is never revoked" 's/^confine   # the final decision.*$/[ "$JSAFE" != unknown ] || confine/'
mm M160 t_swunconfined "the recovery accepts a confinement that is unknown" 's/^  \[ "\${JSAFE:-unknown}" = safe \] || return 1$/  [ "${JSAFE:-unknown}" != unsafe ] || return 1/'
mm M161 t_swlayouts "the common git directory is not read from commondir" 's/^  if \[ -f "\$NE\/commondir" \]; then$/  if false; then/'
mm M110 t_swrefreezegone "an interrupted new freeze is taken for a new attempt: its recorded marker is set aside" 's/^  if restarted_any \&\& \[ ! -e "\$G\/freeze-intent" \] \&\& /  if restarted_any \&\& /'
mm M106 t_swfreezerep "a repeated freeze does not check the whole invariant" 's/^    freeze_holds   # the whole invariant.*$/    :/'
mm M107 t_swpushurls "only the first push URL is compared" 's/remote get-url --push --all "\$LANE"/remote get-url --push "$LANE"/'
sed '/^\/\.git-internal\.new\/$/d' "$HERE/../../.gitignore" > "$B/mut/M108-ign" 2>/dev/null
if cmp -s "$HERE/../../.gitignore" "$B/mut/M108-ign"; then echo "  FAIL mutation M108 changed nothing"; fails=$((fails+1))
else GITIGNORE=$B/mut/M108-ign; t_swignore; r=$?; GITIGNORE=; check "M108 (the interrupted install's git dir is not ignored) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught; fi
if sed 's/ || { echo "private pre-commit: cannot list the staged paths" >&2; exit 1; }//' "$HERE/../git-internal-hooks/pre-commit" > "$B/mut/M103-hook" && ! cmp -s "$HERE/../git-internal-hooks/pre-commit" "$B/mut/M103-hook"; then
  HOOK=$B/mut/M103-hook; t_swprecommit; r=$?; HOOK=; check "M103 (the hook ignores the status of the staged-path listing) is caught" "$([ $r = 0 ] && echo fail-closed || echo caught)" caught
else echo "  FAIL mutation M103 changed nothing"; fails=$((fails+1)); fi
if [ $fails = 0 ]; then echo "GATE0-RUN: PASS"; exit 0; else echo "GATE0-RUN: FAIL ($fails)"; exit 1; fi
