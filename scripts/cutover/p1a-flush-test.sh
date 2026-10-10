#!/bin/bash
# p1a-flush-test.sh: a flush failure injected through the whole of P1a (bead mk-z9st.22).
#
# The P1a helper tests exercise put/fsync_path in isolation. They would stay green if
# P1a's own caller-side STOP checks were deleted: the flush loop over the capture files
# and the chain that publishes the capture (fsync the directory, mv, fsync the journal).
# This test runs the real `cutover-steps.sh ROOT J p1a` on a synthetic fixture with a
# `sync` first in CUTOVER_PATH that fails once, on one named path (and on the bare `sync`
# fallback that fsync_path then tries), then works again. Because the stub recovers, a
# deleted caller check would let P1a run on to a1; the later syncs cannot mask it.
#
# Per injected failure, with the real script, it asserts fail-closed:
#   exit 3 and a "cutover: STOP:" line naming the failed flush or publish;
#   the checkout unchanged (HEAD, index, status, every file's digest, refs/heads, refs/tags);
#   the lane unchanged (autosync/<host> and every other ref as before; the only new ref is
#   the preservation branch archive/gate0/<host>/<old>, which P1a pushes before the flush);
#   no J/cp, J/keep.list, J/intent, J/done-p1a; no published J/capture (except after the
#   directory flush, where the mv already happened and the capture is not adopted);
#   a re-run without the fault finishes P1a (checkpoint a1).
# Controls: a stub that never fires (P1a reaches a1), and mutation copies of
# cutover-steps.sh with the caller-side checks removed, which must be judged NOT
# fail-closed on the cases built to reach them (the test goes red).
#
#   p1a-flush-test.sh            run; exit 0 when every check passes
#   p1a-flush-test.sh --check    syntax and tools only; runs nothing, writes nothing
#
# Env: T_ROOT (scratch parent; default $TMPDIR, else /tmp), P1A_CS (script under test;
# default cutover-steps.sh beside this one). Synthetic content, local bare repositories only.
set -u
PATH=${P1A_FLUSH_PATH:-/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin}
export LC_ALL=C
HERE=$(cd "$(dirname "$0")" && pwd -P)
CS=${P1A_CS:-$HERE/cutover-steps.sh}
if [ "$(printf '' | sha256sum 2>/dev/null | cut -d' ' -f1)" = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 ]
then sha() { sha256sum | cut -d' ' -f1; }; else sha() { shasum -a 256 2>/dev/null | cut -d' ' -f1; }; fi
case ${1:-} in
  --check)
    bash -n "$0" && [ -f "$CS" ] && bash -n "$CS" && command -v git >/dev/null && command -v tar >/dev/null &&
      command -v sync >/dev/null && command -v awk >/dev/null || { echo "p1a-flush-test: check failed" >&2; exit 1; }
    echo "p1a-flush-test: check ok (sha256 $(sha < "$0"); script under test $CS $(sha < "$CS"))"; exit 0 ;;
  '') ;;
  *) echo "usage: p1a-flush-test.sh [--check]" >&2; exit 1 ;;
esac
REALSYNC=$(command -v sync) || { echo "p1a-flush-test: no sync binary" >&2; exit 1; }
B=$(mktemp -d "${T_ROOT:-${TMPDIR:-/tmp}}/p1a-flush.XXXXXX") && B=$(cd "$B" && pwd -P) && [ -d "$B" ] ||
  { echo "p1a-flush-test: cannot allocate a scratch dir; nothing changed" >&2; exit 1; }
fails=0
cleanup() { if [ $fails = 0 ]; then rm -rf -- "${B:?}"; else echo "scratch kept: $B"; fi; }
trap cleanup EXIT
check() { if [ "$2" = "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1: got [$2] want [$3]"; fails=$((fails+1)); fi; }

export HOME=$B/home GIT_CONFIG_GLOBAL=$B/gitconfig GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS GIT_DIR GIT_WORK_TREE
mkdir -p "$HOME" "$B/bin" "$B/stub" "$B/mut"
git config --global user.email t@example.invalid; git config --global user.name t
git config --global init.defaultBranch main; git config --global advice.detachedHead false
export GIT_AUTHOR_DATE='2026-10-01T00:00:00Z' GIT_COMMITTER_DATE='2026-10-01T00:00:00Z'
W=$B/w; R=$W/root/Sylveste; J=$W/J; SS=$B/stub-state

link_text() { local t; t=$(readlink -- "$1" && printf x) || return 1; t=${t%x}; printf '%s' "${t%?}"; }
dgh() { local h; h=$(set -o pipefail; sha) && [[ $h =~ ^[0-9a-f]{64}$ ]] && printf '%s' "$h"; }   # stdin's digest; a hash that fails prints nothing and fails
dg() {  # an entry's kind and digest; a digest that cannot be made is a fresh sentinel, so two failed observations are never equal
  local h k
  if [ -L "$1" ]; then k=l; h=$(set -o pipefail; link_text "$1" | dgh)
  elif [ -d "$1" ]; then echo d; return 0
  elif [ -f "$1" ]; then if [ -x "$1" ]; then k=x; else k=f; fi; h=$(dgh < "$1")
  else echo -; return 0; fi
  if [ -n "$h" ]; then printf '%s:%s\n' "$k" "$h"; else echo "dg-failed-$RANDOM-$RANDOM"; fi; }
files() { (cd "$1" && find . -path ./.git -prune -o \( -type f -o -type l \) -print | sed 's|^\./||' | sort); }
dmap() { local p; while IFS= read -r p; do printf '%s\t%s\n' "$(dg "$1/$p")" "$p"; done < "$2"; }
wr() { mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; }
g() { git -C "$R" "$@"; }
ckfp() {  # the checkout as the plan sees it: HEAD, index, status, every file's digest, local branches and tags
  g symbolic-ref -q HEAD; g rev-parse HEAD; g ls-files -s | sha; g status --porcelain -uall
  files "$R" > "$B/ck.list"; dmap "$R" "$B/ck.list"
  g for-each-ref --format='%(refname) %(objectname)' refs/heads refs/tags; }
gate0refs() { g for-each-ref --format='%(refname)' refs/gate0 | sort | tr '\n' ' '; }
lanerefs() { git --git-dir="$W/lane.git" for-each-ref --format='%(refname) %(objectname)'; }
snap() { rm -rf -- "${B:?}/tpl-${1:?}"; cp -a "$W" "$B/tpl-$1"; }
restore() { rm -rf -- "${W:?}"; cp -a "$B/tpl-$1" "$W"; }
cs() {  # the script under test (CSX), the stub sync first on its PATH, no report
  env CUTOVER_REPORT=0 CUTOVER_PATH="$B/stub:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin" CUTOVER_BD="$B/bin/bd" bash "${CSX:-$CS}" "$R" "$J" "$@"; }

# ---- the stub sync: fails once on the operand named in $SS/target (when $SS/needs, if present, exists),
# then fails the one bare `sync` that fsync_path tries next; every other call, and every later call, is the real sync
cat > "$B/stub/sync" <<EOF
#!/bin/bash
S=$SS; REAL=$REALSYNC
if [ \$# -ge 1 ]; then
  if [ -e "\$S/target" ] && [ ! -e "\$S/fired" ] && [ "\$1" = "\$(cat "\$S/target")" ] && { [ ! -e "\$S/needs" ] || [ -e "\$(cat "\$S/needs")" ]; }; then
    touch "\$S/fired" "\$S/fallback"; echo "injected failure on \$1" >> "\$S/log"; exit 1; fi
  exec "\$REAL" "\$@"
fi
if [ -e "\$S/fallback" ]; then rm -f "\$S/fallback"; echo "injected failure on the bare sync" >> "\$S/log"; exit 1; fi
exec "\$REAL"
EOF
chmod +x "$B/stub/sync"

# ---- stub tracker: `bd export -o FILE` copies the canned tracker
rec() { printf '{"_type":"issue","id":"%s","title":"%s","status":"open","priority":2,"issue_type":"task","created_at":"%s","updated_at":"%s"}\n' "$1" "$2" "$3" "$3"; }
rec fx-one one 2026-10-01T00:00:01Z > "$B/one.jsonl"
{ rec fx-two two 2026-10-01T00:00:02Z; cat "$B/one.jsonl"; } > "$B/trk.jsonl"
printf '#!/bin/bash\ncase "$1 ${2:-}" in "export -o") cp %q "$3" ;; *) echo "bd stub: unsupported: $*" >&2; exit 2 ;; esac\n' "$B/trk.jsonl" > "$B/bin/bd"
chmod +x "$B/bin/bd"

# ---- fixture: a public clone on main at an old commit with local internal work, a lane holding the old tip,
# and PR 1's head carrying the local change to the one kept public file
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
wr "$R/ops/new.sh" 'new local'; g add ops/new.sh; g rm -q ops/old.sh; g commit -qm 'local ops add and delete'
wr "$R/internal/cu.md" 'cu committed'; g commit -qam 'local cu'
wr "$R/internal/cu.md" 'cu uncommitted'; rm "$R/internal/gone.md"; chmod +x "$R/internal/mode.sh"; ln -s a.md "$R/internal/ln"
O=$(g rev-parse HEAD)
g push -q lane "$O:refs/heads/autosync/mA" || { echo "fixture: the lane push failed"; exit 1; }
check "fixture: the lane holds the old tip" "$(git --git-dir="$W/lane.git" rev-parse refs/heads/autosync/mA)" "$O"
mkdir -p "$J"; echo "$BASE" > "$J/base"; echo mA > "$J/host"; echo lane > "$J/lane-remote"; echo "$PR1" > "$J/pr1-head"
printf 'pr1\tdocs/sylveste-vision.md\nbeads-export\t.beads/issues.jsonl\nops-12a\tops/*\n' > "$J/dispositions"
printf 'internal/\ndocs/research/\n' > "$J/delete-list"
echo "  base $BASE, old $O, pr1 $PR1; script under test $CS ($(sha < "$CS"))"
CSX=$CS
cs p0 > "$B/out" 2>&1; check "fixture: p0" "$?" 0
cs p1-pre > "$B/out" 2>&1; check "fixture: p1-pre" "$?" 0
snap pre
LANE0=$(lanerefs); ARCH="refs/heads/archive/gate0/mA/$O"

# ---- one injected failure: run p1a, then observe
# runcase NAME CSFILE TARGET [NEEDS]  : sets RC, and the property variables
runcase() {
  restore pre; rm -rf -- "$SS"; mkdir -p "$SS"
  [ -z "${3:-}" ] || printf '%s\n' "$3" > "$SS/target"
  [ -z "${4:-}" ] || [ "$4" = - ] || printf '%s\n' "$4" > "$SS/needs"
  CK0=$(ckfp); CSX=$2; RUN=$1
  cs p1a > "$B/out.$1" 2>&1; RC=$?
  CSX=$CS
  FIRED=no; [ ! -e "$SS/fired" ] || FIRED=yes
  P_EXIT=$RC
  P_CK=same; [ "$(ckfp)" = "$CK0" ] || P_CK=changed
  P_G0=$(gate0refs)
  P_LANE=ok; [ "$(lanerefs | grep -vF "$ARCH")" = "$LANE0" ] && [ "$(lanerefs | grep -cF "$ARCH")" -le 1 ] || P_LANE=changed
  P_J=ok; for f in cp keep.list intent done-p1a; do [ ! -e "$J/$f" ] || P_J="$f exists"; done
  P_CAP=absent; [ ! -e "$J/capture" ] || P_CAP=published
}
failclosed() {  # CAPOK(yes/no) MSGPAT : 0 when every fail-closed property holds
  [ $FIRED = yes ] && [ "$P_EXIT" = 3 ] && [ "$P_CK" = same ] && [ "$P_LANE" = ok ] && [ "$P_J" = ok ] &&
    { [ "$1" = yes ] || [ "$P_CAP" = absent ]; } && grep -q "cutover: STOP: .*$2" "$B/out.$RUN"
}

# case table: name, injected operand, precondition path, message, capture-may-be-published
CJ=$J
cases() {
  printf '%s\t%s\t%s\t%s\t%s\n' \
    flush-first   "$CJ/capture.tmp/digests"    -              'cannot flush'            no \
    flush-last    "$CJ/capture.tmp/wtree.tar"  -              'cannot flush'            no \
    flush-dir     "$CJ/capture.tmp"            -              'cannot keep the capture' no \
    publish-sync  "$CJ"                        "$CJ/capture"  'cannot keep the capture' yes
}
# printf cycles its format over the arguments: one row per five

echo "== the script under test: a flush or publish failure stops P1a, fail-closed"
while IFS=$'\t' read -r CASE TGT NEED MSG CAPOK; do
  runcase "$CASE" "$CS" "$TGT" "$NEED"
  echo "  case $CASE: inject on ${TGT#"$J"/}: exit $RC; checkout $P_CK; lane $P_LANE; journal $P_J; capture $P_CAP; refs/gate0 ${P_G0:-none}"
  check "$CASE: the stub fired" "$FIRED" yes
  check "$CASE: P1a exits 3 (STOP)" "$P_EXIT" 3
  check "$CASE: the STOP names the failure ($MSG)" "$(grep -c "cutover: STOP: .*$MSG" "$B/out.$CASE")" 1
  check "$CASE: the checkout is unchanged" "$P_CK" same
  check "$CASE: the lane is unchanged (only the preservation branch is new)" "$P_LANE" ok
  check "$CASE: no cp, keep.list, intent or done-p1a" "$P_J" ok
  [ "$CAPOK" = yes ] || check "$CASE: no capture is published" "$P_CAP" absent
  check "$CASE: refs/gate0 holds only lane and base" "$P_G0" "refs/gate0/base refs/gate0/lane "
  # recovery: the same journal, no fault, finishes P1a
  rm -rf -- "$SS"; mkdir -p "$SS"
  cs p1a > "$B/out.$CASE.retry" 2>&1; rrc=$?
  check "$CASE: a re-run without the fault exits 0" "$rrc" 0
  check "$CASE: ... and reaches checkpoint a1" "$(cut -d' ' -f1 "$J/cp" 2>/dev/null)" a1
done < <(cases)

echo "== control: a stub that never fires lets P1a reach a1"
runcase none "$CS" ""
check "no injection: exit 0" "$P_EXIT" 0
check "no injection: checkpoint a1" "$(cut -d' ' -f1 "$J/cp" 2>/dev/null)" a1
check "no injection: the capture is published" "$P_CAP" published

echo "== mutation controls: without the caller-side checks the same injection is NOT fail-closed (the test goes red)"
mutate() {  # SRC DST PATTERN REPLACEMENT : the pattern occurs exactly once
  local c rest; c=$(cat "$1"; printf x); c=${c%x}
  case $c in *"$3"*) ;; *) return 1 ;; esac
  rest=${c#*"$3"}; case $rest in *"$3"*) return 1 ;; esac
  printf '%s' "${c/"$3"/$4}" > "$2"
}
mutate "$CS" "$B/mut/M1.sh" '|| stop "P1a: cannot flush $p"' '|| true' || { echo "  FAIL cannot build M1 (the flush check is not where the test expects it)"; fails=$((fails+1)); }
mutate "$CS" "$B/mut/M2.sh" '|| stop "P1a: cannot keep the capture"' '|| true' || { echo "  FAIL cannot build M2 (the publish check is not where the test expects it)"; fails=$((fails+1)); }
for m in M1 M2; do [ ! -f "$B/mut/$m.sh" ] || check "$m differs from the script under test in exactly one line" "$(diff "$CS" "$B/mut/$m.sh" | grep -c '^>')" 1; done
echo "  (cells: red = judged not fail-closed; green = still stopped, caught by a later check)"
while IFS=$'\t' read -r CASE TGT NEED MSG CAPOK; do
  for m in M1 M2; do
    [ -f "$B/mut/$m.sh" ] || continue
    runcase "$CASE.$m" "$B/mut/$m.sh" "$TGT" "$NEED"
    if failclosed "$CAPOK" "$MSG"; then cell=green; else cell=red; fi
    echo "  $m x $CASE: exit $P_EXIT, checkpoint $(cut -d' ' -f1 "$J/cp" 2>/dev/null || echo none): $cell"
    case "$m $CASE" in
      "M1 flush-first"|"M1 flush-last"|"M2 publish-sync") check "$m x $CASE: the test goes red" "$cell" red ;;
    esac
  done
done < <(cases)

if [ $fails = 0 ]; then echo "P1A-FLUSH: PASS"; exit 0; else echo "P1A-FLUSH: FAIL ($fails)"; exit 1; fi
