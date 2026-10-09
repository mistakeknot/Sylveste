#!/bin/bash
# crash-inject.sh: crash-point injection for plan revision 8 (Sol round-7
# findings 1-3). Every crash point of the helper (out/git-internal/scripts/
# git-internal) and of the per-machine cutover steps (out/cutover-steps.sh) is
# a numbered kill -KILL: before and after each record write (temp, rename),
# after each file write, removal, move and restore, after the index, after HEAD,
# after the importer, after the intent is retired. For each scenario the
# harness restores the same fixture, kills the run at point N for N = 1, 2, ...
# until a run finishes without reaching N, and after each kill checks:
#   at the crash moment: no data loss (every P2 file, or the local commit and
#     local-only file, is still on disk with its exact digest);
#   after recovery and the continuing step: convergence to the uncrashed result.
# Nested mode kills the recovery run as well, at each of its own points.
# The verbatim rev 7 helper (out/repro-r7/git-internal) reproduces finding 1.
# Revision 8.1 (Sol round 8): the helper sets ORIG_HEAD to the intent's OLD and
# reads it back before the importer (crash point orig-head). After each sync
# crash point a stale ORIG_HEAD.lock and an older ORIG_HEAD are planted: the
# next sync must stop (10) with the intent kept, the lane unpushed and no
# import of a wrong range, then converge once the lock is removed. The
# verbatim rev 8 helper (out/repro-r8/git-internal) reproduces the finding.
# Revision 8.2 (Sol round 9): clear_state fails when deleting the fold ref
# fails. After each resolve crash point the fold ref is corrupted: the next
# command must stop (10 with the intent, 6 without) with nothing imported or
# pushed and the ref left in place, then converge once the owner removes it.
# The verbatim rev 8.1 helper (out/repro-r8.1/git-internal) reproduces it.
# Synthetic content, local bare remotes only, fresh mktemp dir under $T_ROOT.
#   crash-inject.sh [--no-nested]
set -u
PATH=${GIT_INTERNAL_PATH:-/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin}
export LC_ALL=C
HERE=$(cd "$(dirname "$0")" && pwd) || exit 1
for v in $(compgen -e); do case $v in GIT_*) unset "$v" ;; esac; done   # no Git environment override reaches the fixtures
GI_TREE=${GI_TREE:-$HERE/git-internal}   # RH points GI_TREE at PR 1's checkout, as in lane-sync-test.sh
HELPER=$GI_TREE/scripts/git-internal
STEPS=$HERE/cutover-steps.sh
REPRO7=$HERE/repro-r7/git-internal
REPRO8=$HERE/repro-r8/git-internal
REPRO81=$HERE/repro-r8.1/git-internal
NESTED=1; [ "${1:-}" = --no-nested ] && NESTED=0
B=$(mktemp -d "${T_ROOT:-$HERE/../work}/crash.XXXXXX") && B=$(cd "$B" && pwd -P) && [ -n "$B" ] && [ -d "$B" ] ||
  { echo "crash-inject: cannot allocate a scratch dir under ${T_ROOT:-$HERE/../work}; nothing changed" >&2; exit 1; }
W=$B/w                       # the live fixture; every case restores it here, so absolute paths stay valid
CNT=$B/count; CLOG=$B/crash.log
export CUTOVER_REPORT=0 RESTART_REPORT=0 GIT_CONFIG_NOSYSTEM=1 HOME="$B/home"; mkdir -p "$HOME"
git config --global user.email t@example.invalid; git config --global user.name t
git config --global init.defaultBranch main; git config --global advice.detachedHead false
export GIT_AUTHOR_DATE='2026-10-01T00:00:00Z' GIT_COMMITTER_DATE='2026-10-01T00:00:00Z'   # commits identical across runs
fails=0; TOTAL=0; SUMMARY=""
check() { if [ "$2" = "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1: got [$2] want [$3]"; fails=$((fails+1)); fi; }
fail() { echo "  FAIL $*"; fails=$((fails+1)); }
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | cut -d' ' -f1; }
link_text() { local t; t=$(readlink -- "$1" && printf x) || return 1; t=${t%x}; printf '%s' "${t%?}"; }
dg() {  # the digest cutover-steps.sh records
  if [ -L "$1" ]; then printf 'l:%s\n' "$(link_text "$1" | sha)"
  elif [ -d "$1" ]; then echo d
  elif [ -f "$1" ] && [ -x "$1" ]; then printf 'x:%s\n' "$(sha < "$1")"
  elif [ -f "$1" ]; then printf 'f:%s\n' "$(sha < "$1")"
  else echo -; fi
}
snap() { rm -rf -- "${B:?}/tpl-${1:?}"; cp -a "$W" "$B/tpl-$1"; }
restore() { rm -rf -- "${W:?}"; cp -a "$B/tpl-$1" "$W"; rm -f -- "${CNT:?}" "${CLOG:?}"; }
label() { awk -v n="$1" '$1==n{print $2"/"$3}' "$CLOG"; }
echo "helper: $HELPER ($(sha < "$HELPER" | cut -c1-16)); steps: $STEPS ($(sha < "$STEPS" | cut -c1-16)); bash $BASH_VERSION; $(git version)"

# inject NAME TEMPLATE ACT CONT MOMENT END [LABELS] : one crash per run, at N = 1, 2, ...
# ACT and CONT are functions; ACT reads $AT (0 = no crash) and returns its rc.
# Each recovery (CONT with no crash) must exit 0, the run past the last point
# must exit 0, at least one point must be covered, and every crash-point label
# in LABELS (space-separated, as label prints them) must be among the points.
declare -A NPTS
inject() {
  local name=$1 tpl=$2 act=$3 cont=$4 mom=$5 fin=$6 want=${7:-} n=0 rc crc pts=0 names="" l
  echo "== $name"
  while :; do
    n=$((n+1)); restore "$tpl"; AT=$n $act; rc=$?
    [ $rc = 137 ] || break
    pts=$n; names="$names $(label $n)"
    $mom || fail "$name: data lost at crash point $n ($(label $n))"
    AT=0 $cont; crc=$?
    [ $crc = 0 ] || fail "$name: recovery after crash point $n ($(label $n)) exited $crc"
    $fin || fail "$name: no convergence after crash point $n ($(label $n))"
  done
  check "$name: the run past the last point finishes (rc 0) and passes the end check" "$rc $($fin && echo pass)" "0 pass"
  [ $pts -gt 0 ] || fail "$name: no injection point was reached"
  for l in $want; do case " $names " in *" $l "*) ;; *) fail "$name: expected crash point $l not covered";; esac; done
  echo "  points: $pts:$names"
  NPTS[$tpl:$act]=$pts
  TOTAL=$((TOTAL+pts)); SUMMARY="$SUMMARY
  $name: $pts"
}
# inject2 NAME TEMPLATE ACT CONT MOMENT END : crash ACT at N, then crash CONT at
# each of its own points M, then CONT again; counts the (N, M) pairs. The outer
# point count must equal inject's for the same scenario, each inner run past its
# last point and each recovery must exit 0, and at least one pair is covered.
inject2() {
  local name=$1 tpl=$2 act=$3 cont=$4 mom=$5 fin=$6 n=0 m rc crc pts=0 outer=0
  echo "== $name (nested)"
  while :; do
    n=$((n+1)); restore "$tpl"; AT=$n $act; rc=$?
    [ $rc = 137 ] || break
    outer=$n; snap "$tpl-n"; m=0
    while :; do
      m=$((m+1)); restore "$tpl-n"; AT=$m $cont; rc=$?
      [ $rc = 137 ] || break
      pts=$((pts+1))
      $mom || fail "$name: data lost at crash $n then $m"
      AT=0 $cont; crc=$?
      [ $crc = 0 ] || fail "$name: recovery after crash $n then $m ($(label $m)) exited $crc"
      $fin || fail "$name: no convergence after crash $n then $m ($(label $m))"
    done
    [ $rc = 0 ] && $fin || fail "$name: after crash $n, the uncrashed continuation exited $rc or did not converge"
  done
  [ $rc = 0 ] || fail "$name: the uncrashed run exited $rc"
  check "$name: nested outer points equal the single-crash points" "$outer" "${NPTS[$tpl:$act]:-unset}"
  [ $pts -gt 0 ] || fail "$name: no nested pair was reached"
  echo "  nested pairs: $pts"
  TOTAL=$((TOTAL+pts)); SUMMARY="$SUMMARY
  $name (nested pairs): $pts"
}
crashenv() { if [ "$AT" = 0 ]; then env -u GIT_INTERNAL_CRASH_AT -u CUTOVER_CRASH_AT ${1+"$@"}
  else GIT_INTERNAL_CRASH_AT=$AT GIT_INTERNAL_CRASH_COUNT=$CNT GIT_INTERNAL_CRASH_LOG=$CLOG \
       CUTOVER_CRASH_AT=$AT CUTOVER_CRASH_COUNT=$CNT CUTOVER_CRASH_LOG=$CLOG ${1+"$@"}; fi; }
# rbfwd NAME TEMPLATE ACT PREP RB MOMENT END [nested] : crash ACT at each of its
# points N, run PREP, then RB to the end (nested: crash RB at each of its own
# points M first, then RB again). The ACT run past its last point must exit 0,
# its point count must equal inject's for TEMPLATE/ACT, every RB that is not
# crashed must exit 0 and pass END, and at least one point (pair) is covered.
rbfwd() {
  local name=$1 tpl=$2 act=$3 prep=$4 rb=$5 mom=$6 fin=$7 nest=${8:-} n=0 m rc orc outer=0 pts=0
  echo "== $name${nest:+ (nested)}"
  while :; do
    n=$((n+1)); restore "$tpl"; AT=$n $act; orc=$?
    [ $orc = 137 ] || break
    outer=$n; $mom || fail "$name: data lost at forward crash $n ($(label $n))"; $prep
    if [ -z "$nest" ]; then pts=$n; AT=0 $rb; rc=$?
      [ $rc = 0 ] && $fin || fail "$name: rollback after forward crash $n ($(label $n)) rc $rc"; continue; fi
    snap "$tpl-fx"; m=0
    while :; do
      m=$((m+1)); restore "$tpl-fx"; AT=$m $rb; rc=$?
      [ $rc = 137 ] || break
      pts=$((pts+1)); $mom || fail "$name: data lost: forward crash $n, rollback crash $m"
      AT=0 $rb; rc=$?; [ $rc = 0 ] && $fin || fail "$name: no convergence: forward crash $n, rollback crash $m ($(label $m)) rc $rc"
    done
    [ $rc = 0 ] && $fin || fail "$name: forward crash $n: the uncrashed rollback exited $rc or did not converge"
  done
  check "$name: the forward run past the last point exits 0, its points equal the forward scenario's" "$orc $outer" "0 ${NPTS[$tpl:$act]:-unset}"
  [ $pts -gt 0 ] || fail "$name: no point reached"
  echo "  ${nest:+nested pairs}${nest:-points}: $pts"; TOTAL=$((TOTAL+pts)); SUMMARY="$SUMMARY
  $name${nest:+ (nested pairs)}: $pts"
}

# ---------------------------------------------------------------- negative controls of the accounting
# A fake scenario: ACT crashes (137) at points 1..NC_PTS and then exits NC_RC;
# RB/CONT crashes at 1..NC_IPTS and otherwise exits NC_CRC; END is NC_END.
# Each accounting function must count a fault as a failure and a clean run as none.
nc_act() { [ "$AT" -ge 1 ] && [ "$AT" -le "$NC_PTS" ] && return 137; return "$NC_RC"; }
nc_cont() { [ "$AT" -ge 1 ] && [ "$AT" -le "$NC_IPTS" ] && return 137; return "$NC_CRC"; }
nc_end() { "$NC_END"; }
nc() { (fails=0; NPTS[nc:nc_act]=3; "$@" >/dev/null 2>&1; echo "$fails"); }
nc_all() {  # the fail counts of inject, inject2, rbfwd and nested rbfwd on the fake scenario
  echo "$(nc inject nc nc nc_act nc_cont true nc_end) $(nc inject2 nc nc nc_act nc_cont true nc_end)" \
       "$(nc rbfwd nc nc nc_act true nc_cont true nc_end) $(nc rbfwd nc nc nc_act true nc_cont true nc_end nested)"; }
echo "== negative controls: the crash accounting turns red on a fault"
mkdir -p "$W"; snap nc
export NC_PTS=3 NC_IPTS=2 NC_RC=0 NC_CRC=0 NC_END=true
check "clean fake scenario: no failure in any accounting function" "$(nc_all)" "0 0 0 0"
r=$(NC_CRC=1 nc_all); check "a failing continuation/recovery turns each red [$r]" "$(case "$r" in *" 0"*|"0 "*) echo green;; *) echo red;; esac)" red
r=$(NC_PTS=0 nc_all); check "zero coverage turns each red [$r]" "$(case "$r" in *" 0"*|"0 "*) echo green;; *) echo red;; esac)" red
r=$(NC_RC=2 nc_all); check "a failing terminal run turns each red [$r]" "$(case "$r" in *" 0"*|"0 "*) echo green;; *) echo red;; esac)" red
r=$(NC_END=false nc_all); check "a failing end check turns each red [$r]" "$(case "$r" in *" 0"*|"0 "*) echo green;; *) echo red;; esac)" red
r=$(NC_PTS=2 nc_all); check "an outer count unequal to the single-crash count turns inject2 and rbfwd red [$r]" "$(echo "$r" | awk '{print ($2>0 && $3>0 && $4>0)}')" 1
r=$(NC_IPTS=0 nc_all); check "zero nested coverage turns inject2 and nested rbfwd red [$r]" "$(echo "$r" | awk '{print ($2>0 && $4>0)}')" 1
unset NC_PTS NC_IPTS NC_RC NC_CRC NC_END
rm -rf -- "${W:?}" "${B:?}/tpl-nc" "${B:?}/tpl-nc-n" "${B:?}/tpl-nc-fx"

# ---------------------------------------------------------------- helper fixture
gi() { local r=$1; shift; git -C "$r" --git-dir="$r/.git-internal" "$@"; }
GI() { local r=$1; shift; "$HELPER" -C "$r" "$@"; }
machine() { git init -q "$1"; printf 'docs/plans/\n/.git-internal/\n' > "$1/.gitignore"; git -C "$1" add .gitignore; git -C "$1" commit -qm 'public after PR 1'; }
wr() { mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; }
mkdir -p "$W"
git init -q --bare "$W/int.git"
git clone -q "$W/int.git" "$W/seed" 2>/dev/null
for f in shared mod del; do wr "$W/seed/docs/plans/$f.md" "$f v1"; done
wr "$W/seed/docs/plans/mode.sh" '#!/bin/sh'
git -C "$W/seed" add -A; git -C "$W/seed" commit -qm seed; git -C "$W/seed" push -q origin main
machine "$W/mA"; machine "$W/mB"
GI "$W/mA" install "$W/int.git" mA && GI "$W/mB" install "$W/int.git" mB || { echo "fixture: install failed"; exit 1; }
printf '#!/bin/sh\necho "$(git rev-parse ORIG_HEAD) $(git rev-parse HEAD)" >> "%s"\n' "$W/import.log" > "$W/mA/.git-internal/hooks/post-merge"
chmod +x "$W/mA/.git-internal/hooks/post-merge"
wr "$W/mB/docs/plans/new.md" 'from B'; ln -s shared.md "$W/mB/docs/plans/lnk"
wr "$W/mB/docs/plans/mod.md" 'mod v2'; chmod +x "$W/mB/docs/plans/mode.sh"; rm -- "${W:?}/mB/docs/plans/del.md"
gi "$W/mB" add -f -A docs/plans; gi "$W/mB" commit -qm 'B: add, link, change, mode, delete'
GI "$W/mB" sync || { echo "fixture: B sync failed"; exit 1; }
wr "$W/mA/docs/plans/a-local.md" 'A local commit'; GI "$W/mA" add docs/plans/a-local.md; GI "$W/mA" commit -m a-local >/dev/null
wr "$W/mA/docs/plans/scratch.md" 'A local-only, untracked'
A_OLD=$(gi "$W/mA" rev-parse HEAD); SCRATCH=$(dg "$W/mA/docs/plans/scratch.md"); ALOCAL=$(dg "$W/mA/docs/plans/a-local.md")
snap sync
GI "$W/mA" sync; check "reference sync" "$?" 0
SYNC_REF=$(gi "$W/mA" rev-parse HEAD)
check "reference: the importer ran once for old..new" "$(cat "$W/import.log")" "$A_OLD $SYNC_REF"

sync_act() { crashenv "$HELPER" -C "$W/mA" sync 2>/dev/null; }
sync_mom() { [ "$(dg "$W/mA/docs/plans/scratch.md")" = "$SCRATCH" ] && [ "$(dg "$W/mA/docs/plans/a-local.md")" = "$ALOCAL" ] &&
  gi "$W/mA" merge-base --is-ancestor "$A_OLD" HEAD; }
sync_end() {
  [ "$(gi "$W/mA" rev-parse HEAD)" = "$SYNC_REF" ] && [ -z "$(gi "$W/mA" status --porcelain)" ] &&
  [ ! -e "$W/mA/.git-internal/git-internal-intent" ] && [ "$(git -C "$W/int.git" rev-parse autosync/mA 2>/dev/null)" = "$SYNC_REF" ] &&
  [ "$(tail -n 1 "$W/import.log" 2>/dev/null)" = "$A_OLD $SYNC_REF" ] && sync_mom &&
  [ "$(readlink "$W/mA/docs/plans/lnk")" = shared.md ] && [ -x "$W/mA/docs/plans/mode.sh" ] && [ ! -e "$W/mA/docs/plans/del.md" ]
}
inject "helper sync (add, symlink, change, mode, delete; local commit; importer)" sync sync_act sync_act sync_mom sync_end
[ $NESTED = 0 ] || inject2 "helper sync" sync sync_act sync_act sync_mom sync_end   # before the resolve fixture resets A_OLD

echo "== finding 1 (rev 7): HEAD moves before the import record exists"
restore sync
sed '233a\
kill -KILL $$' "$REPRO7" > "$B/r7-kill"; chmod +x "$B/r7-kill"
"$B/r7-kill" -C "$W/mA" sync 2>/dev/null; rc=$?
check "rev 7 helper killed between update-ref (l.233) and the pending-import write (l.236)" "$rc $(gi "$W/mA" rev-parse HEAD)" "137 $SYNC_REF"
"$REPRO7" -C "$W/mA" sync 2>/dev/null; rc=$?
lane=$(git -C "$W/int.git" rev-parse autosync/mA 2>/dev/null)
[ $rc = 0 ] && [ "$lane" = "$SYNC_REF" ] && [ ! -s "$W/import.log" ] &&
  echo "  reproduced: the next rev 7 sync returns 0 and pushes the lane; the importer never ran"
check "rev 7: next sync rc 0, lane pushed, import log empty" "$rc $lane $([ -s "$W/import.log" ] && echo imported || echo empty)" "0 $SYNC_REF empty"
restore sync; n=$(AT=999 sync_act; awk '$3=="head"{print $1}' "$CLOG")
restore sync; AT=$n sync_act; check "rev 8: killed at the same place (point $n, after update-ref HEAD)" "$? $(gi "$W/mA" rev-parse HEAD) $(cut -d' ' -f1 "$W/mA/.git-internal/git-internal-intent")" "137 $SYNC_REF sync"
AT=0 sync_act; check "rev 8: the next sync finishes the intent: importer ran, lane pushed" "$? $(sync_end && echo converged)" "0 converged"

echo "== Sol round 8: a stale ORIG_HEAD.lock and an older ORIG_HEAD, planted after each sync crash point"
OLDER=$(gi "$W/mA" rev-parse "$A_OLD~1")
plant() { gi "$W/mA" update-ref ORIG_HEAD "$OLDER"; : > "$W/mA/.git-internal/ORIG_HEAD.lock"; }
unlock() { rm -f -- "${W:?}/mA/.git-internal/ORIG_HEAD.lock"; }
wrong_range() { [ -n "$(grep -v -x -- "$A_OLD $SYNC_REF" "$W/import.log" 2>/dev/null)" ]; }
lane_of_a() { git -C "$W/int.git" rev-parse autosync/mA 2>/dev/null; }
restore sync; AT=$n sync_act >/dev/null; plant
"$REPRO8" -C "$W/mA" sync 2>/dev/null; rc=$?
[ $rc = 0 ] && [ "$(cat "$W/import.log")" = "$OLDER $SYNC_REF" ] && [ "$(lane_of_a)" = "$SYNC_REF" ] &&
  echo "  reproduced: after a crash at point $n (head), rev 8 recovery under the stale lock exits 0, imports $OLDER..HEAD, retires the intent and pushes"
check "rev 8: rc, imported range, intent, lane" "$rc $(cat "$W/import.log") [$([ -e "$W/mA/.git-internal/git-internal-intent" ] && echo pending)] $(lane_of_a)" "0 $OLDER $SYNC_REF [] $SYNC_REF"
k=0; pts=0; stopped=0; names=""
while :; do
  k=$((k+1)); restore sync; AT=$k sync_act; rc=$?
  [ $rc = 137 ] || break
  pts=$k; names="$names $(label $k)"; plant
  AT=0 sync_act; rc=$?
  if [ $rc = 10 ] && [ -e "$W/mA/.git-internal/git-internal-intent" ] && [ "$(lane_of_a)" != "$SYNC_REF" ] && ! wrong_range; then stopped=$((stopped+1))
  elif [ $rc = 0 ] && sync_end && ! wrong_range; then :            # the importer had finished before the crash
  else fail "stale lock after crash point $k ($(label $k)): rc $rc, intent $([ -e "$W/mA/.git-internal/git-internal-intent" ] && echo kept || echo gone), lane $(lane_of_a), import [$(tr '\n' ' ' < "$W/import.log" 2>/dev/null)]"; fi
  unlock; AT=0 sync_act; rc=$?
  [ $rc = 0 ] && sync_end && ! wrong_range || fail "stale lock after crash point $k ($(label $k)): no convergence once the lock is removed (rc $rc)"
done
check "stale lock: the run past the last point finishes (rc 0), points covered" "$rc $([ $pts -gt 0 ] && echo covered)" "0 covered"
check "every planted stale lock stops the next sync (10) unless the importer had finished" "$stopped" "$((pts-1))"
echo "  points: $pts:$names"
TOTAL=$((TOTAL+pts)); SUMMARY="$SUMMARY
  helper sync, stale ORIG_HEAD.lock planted after the crash: $pts"

# resolve: a conflict on shared.md, the session writes the resolved file
restore sync
wr "$W/mA/docs/plans/shared.md" 'A version'; GI "$W/mA" add docs/plans/shared.md; GI "$W/mA" commit -m 'A shared' >/dev/null
wr "$W/mB/docs/plans/shared.md" 'B version'; GI "$W/mB" add docs/plans/shared.md; GI "$W/mB" commit -m 'B shared' >/dev/null; GI "$W/mB" sync
GI "$W/mA" sync 2>/dev/null; check "resolve fixture: A's sync stops on the conflict (3)" "$?" 3
wr "$W/mA/docs/plans/shared.md" 'resolved'; R_OLD=$(gi "$W/mA" rev-parse HEAD); : > "$W/import.log"
A_OLD=$R_OLD; ALOCAL=$(dg "$W/mA/docs/plans/a-local.md")
snap resolve
GI "$W/mA" resolve origin/autosync/mB 2>/dev/null; check "reference resolve" "$?" 0
RES_REF=$(gi "$W/mA" rev-parse HEAD)
res_act() { crashenv "$HELPER" -C "$W/mA" resolve origin/autosync/mB 2>/dev/null; }
res_cont() { local rc; crashenv "$HELPER" -C "$W/mA" sync 2>/dev/null; rc=$?
  [ $rc = 3 ] && { crashenv "$HELPER" -C "$W/mA" resolve origin/autosync/mB 2>/dev/null; rc=$?; }; return $rc; }
res_mom() { sync_mom && { [ "$(cat "$W/mA/docs/plans/shared.md")" = resolved ] || [ "$(gi "$W/mA" rev-parse HEAD)" = "$RES_REF" ]; }; }
res_end() {
  [ "$(gi "$W/mA" rev-parse HEAD)" = "$RES_REF" ] && [ -z "$(gi "$W/mA" status --porcelain)" ] &&
  [ ! -e "$W/mA/.git-internal/git-internal-intent" ] && [ ! -e "$W/mA/.git-internal/git-internal-conflict" ] &&
  ! gi "$W/mA" rev-parse -q --verify refs/git-internal/fold >/dev/null && [ ! -e "$W/mA/.git-internal/refs/git-internal/fold" ] &&
  [ "$(git -C "$W/int.git" rev-parse autosync/mA)" = "$RES_REF" ] && [ "$(cat "$W/mA/docs/plans/shared.md")" = resolved ] &&
  [ "$(tail -n 1 "$W/import.log")" = "$R_OLD $RES_REF" ] && sync_mom
}
inject "helper resolve (conflict record, fold ref, resolved file)" resolve res_act res_cont res_mom res_end
[ $NESTED = 0 ] || inject2 "helper resolve" resolve res_act res_cont res_mom res_end

echo "== Sol round 9: a corrupted fold ref, planted after each resolve crash point"
FOLDF=$W/mA/.git-internal/refs/git-internal/fold
breakfold() { mkdir -p "$(dirname "$FOLDF")"; printf 'not a ref\n' > "$FOLDF"; }
pending() { [ -e "$W/mA/.git-internal/git-internal-intent" ]; }
restore resolve; nh=$(AT=999 res_act; awk '$3=="head"{print $1}' "$CLOG")
restore resolve; AT=$nh res_act >/dev/null; breakfold
"$REPRO81" -C "$W/mA" sync 2>/dev/null; rc=$?
[ "$(cat "$W/import.log")" = "$R_OLD $RES_REF" ] && ! pending && [ -e "$FOLDF" ] &&
  echo "  reproduced: after a crash at point $nh (head), rev 8.1 recovery treats the broken fold ref as absent: it imports, retires the intent while the ref survives, and the sync then exits $rc"
check "rev 8.1: imported range, intent, broken ref, rc" "$(cat "$W/import.log") [$(pending && echo pending)] $([ -e "$FOLDF" ] && echo ref) $rc" "$R_OLD $RES_REF [] ref 2"
k=0; pts=0; stopped=0; names=""
while :; do
  k=$((k+1)); restore resolve; AT=$k res_act; rc=$?
  [ $rc = 137 ] || break
  pts=$k; names="$names $(label $k)"
  want=$(pending && echo 10 || echo 6); imp0=$(cat "$W/import.log" 2>/dev/null); lane0=$(lane_of_a); breakfold
  AT=0 res_cont; rc=$?
  if [ $rc = "$want" ] && { [ $want = 6 ] || pending; } && [ "$(cat "$W/import.log" 2>/dev/null)" = "$imp0" ] && [ "$(lane_of_a)" = "$lane0" ] && [ -e "$FOLDF" ]; then stopped=$((stopped+1))
  else fail "broken fold ref after crash point $k ($(label $k)): rc $rc (want $want), intent $(pending && echo kept || echo gone), lane $([ "$(lane_of_a)" = "$lane0" ] && echo unchanged || echo moved), import [$(tr '\n' ' ' < "$W/import.log" 2>/dev/null)]"; fi
  rm -f -- "${FOLDF:?}"; AT=0 res_cont; rc=$?
  [ $rc = 0 ] && res_end || fail "broken fold ref after crash point $k ($(label $k)): no convergence once the ref is removed (rc $rc)"
done
check "broken fold ref: the run past the last point finishes (rc 0), points covered" "$rc $([ $pts -gt 0 ] && echo covered)" "0 covered"
check "every planted broken fold ref stops the next command (10 with the intent, 6 without), nothing imported or pushed" "$stopped" "$pts"
echo "  points: $pts:$names"
TOTAL=$((TOTAL+pts)); SUMMARY="$SUMMARY
  helper resolve, corrupted fold ref planted after the crash: $pts"

# install: a fresh public checkout; the continuing step reruns install unless it finished
restore sync; machine "$W/mI"; snap install
inst_act() { crashenv "$HELPER" -C "$W/mI" install "$W/int.git" mI 2>/dev/null; }
inst_cont() { [ -e "$W/mI/.git-internal/info/installed" ] || inst_act; }
inst_mom() { true; }   # nothing of the machine's own is written by install
inst_end() { [ -e "$W/mI/.git-internal/info/installed" ] && [ ! -e "$W/mI/.git-internal.new" ] &&
  [ -z "$(gi "$W/mI" status --porcelain)" ] && [ -z "$(git -C "$W/mI" status --porcelain)" ] &&
  [ "$(gi "$W/mI" ls-files | wc -l | tr -d ' ')" = 4 ] && (cd / && "$HELPER" -C "$W/mI" probe >/dev/null 2>&1); }
inject "helper install (build .git-internal.new, rename, populate, info/installed)" install inst_act inst_cont inst_mom inst_end
[ $NESTED = 0 ] || inject2 "helper install" install inst_act inst_cont inst_mom inst_end

# ---------------------------------------------------------------- cutover fixture
# pub.git: c0 = README + docs/plans/{a,b}.md; PR 1 deletes docs/plans and adds
# the .gitignore; the revert of PR 1 is prepared in pubwork, pushed only by a
# rollback case. The machine ROOT = W/m has a local edit to a.md, an untracked
# new.md and an untracked symlink lnk. int.git holds the shared a.md and b.md.
rm -rf -- "${W:?}"; mkdir -p "$W"
git init -q --bare "$W/pub.git"; git clone -q "$W/pub.git" "$W/pubwork" 2>/dev/null
wr "$W/pubwork/README.md" readme; wr "$W/pubwork/docs/plans/a.md" 'base a'; wr "$W/pubwork/docs/plans/b.md" 'base b'
git -C "$W/pubwork" add -A; git -C "$W/pubwork" commit -qm c0; git -C "$W/pubwork" push -q origin main
git init -q --bare "$W/int.git"; git clone -q "$W/int.git" "$W/seed" 2>/dev/null
wr "$W/seed/docs/plans/a.md" 'shared a'; wr "$W/seed/docs/plans/b.md" 'base b'
git -C "$W/seed" add -A; git -C "$W/seed" commit -qm seed; git -C "$W/seed" push -q origin main
git clone -q "$W/pub.git" "$W/m" 2>/dev/null
wr "$W/m/docs/plans/a.md" 'LOCAL EDIT a'; wr "$W/m/docs/plans/new.md" 'local new'; ln -s new.md "$W/m/docs/plans/lnk"
J=$W/j; mkdir -p "$J"
echo docs/plans/ > "$J/delete-list"; printf 'docs/plans/a.md\ndocs/plans/b.md\n' > "$J/shared.manifest"
printf 'docs/plans/lnk\ndocs/plans/new.md\n' > "$J/local.manifest"
echo "$W/int.git" > "$J/url"; echo mA > "$J/host"; echo "$HELPER" > "$J/helper"
"$STEPS" "$W/m" "$J" p2; check "P2 recorded" "$? $(cut -d' ' -f1 "$J/cp")" "0 c0"
git -C "$W/pubwork" rm -q -r docs/plans; printf 'docs/plans/\n/.git-internal/\n' > "$W/pubwork/.gitignore"
git -C "$W/pubwork" add .gitignore; git -C "$W/pubwork" commit -qm 'PR 1'; git -C "$W/pubwork" push -q origin main
PR1=$(git -C "$W/pubwork" rev-parse HEAD)
git -C "$W/pubwork" revert --no-edit HEAD >/dev/null || { echo "fixture: revert failed"; exit 1; }; git -C "$W/pubwork" branch -q revert; git -C "$W/pubwork" reset -q --hard "$PR1"
REV=$(git -C "$W/pubwork" rev-parse revert)
P2M=$(cat "$J/p2.manifest"); P2S=$(cat "$J/p2.status")
echo "  P2 manifest:"; sed 's/^/    /' "$J/p2.manifest"
snap cut0

cut_fwd() { crashenv "$STEPS" "$W/m" "$J" forward 2>/dev/null; }
cut_rb() { crashenv "$STEPS" "$W/m" "$J" rollback 2>/dev/null; }
push_revert() { git -C "$W/pubwork" push -q origin revert:main; }
p2_kept() {  # every P2 file is in ROOT or in the quarantine, with its P2 digest
  local d p; while IFS=$'\t' read -r d p; do
    [ "$(dg "$W/m/$p")" = "$d" ] || [ "$(dg "$J/Q/$p")" = "$d" ] || { echo "    lost: $p" >&2; return 1; }
  done < "$J/p2.manifest"; }
fwd_end() {
  [ "$(cat "$J/cp")" = "c3 $PR1" ] && [ ! -e "$J/intent" ] && [ -e "$W/m/.git-internal/info/installed" ] &&
  [ ! -e "$W/m/.git-internal.new" ] && [ -z "$(git -C "$W/m" status --porcelain)" ] &&
  [ -z "$(gi "$W/m" status --porcelain)" ] && [ "$(cat "$W/m/docs/plans/a.md")" = 'shared a' ] &&
  [ "$(awk -F'\t' '$2 ~ /new.md|lnk/' "$J/p2.manifest")" = "$(for p in lnk new.md; do printf '%s\tdocs/plans/%s\n' "$(dg "$W/m/docs/plans/$p")" "$p"; done)" ] &&
  [ "$(cat "$J/Q/docs/plans/a.md")" = 'LOCAL EDIT a' ] && p2_kept &&
  (cd / && "$HELPER" -C "$W/m" probe >/dev/null 2>&1)
}
rb_end() {
  [ "$(cat "$J/cp")" = "r5 $REV" ] && [ ! -e "$J/intent" ] && [ "$(cat "$J/p2.manifest")" = "$P2M" ] &&
  [ "$(git -C "$W/m" status --porcelain)" = "$P2S" ] &&
  ! [ -e "$W/m/.git-internal" -o -L "$W/m/.git-internal" -o -e "$W/m/.git-internal.new" ] &&
  [ "$(awk -F'\t' '{print $2}' "$J/p2.manifest")" = "$(cd "$W/m" && find docs/plans \( -type f -o -type l \) | sort)" ] &&
  [ "$(while IFS=$'\t' read -r d p; do [ "$(dg "$W/m/$p")" = "$d" ] || echo "$p"; done < "$J/p2.manifest")" = "" ]
}
inject "cutover forward P6-P8 (c0 -> c3)" cut0 cut_fwd cut_fwd p2_kept fwd_end

# rollback after an interrupted forward: each forward crash point, then the revert, then rollback
rbfwd "cutover rollback from every interrupted forward point" cut0 cut_fwd push_revert cut_rb p2_kept rb_end

# rollback with crashes, from each checkpoint
for c in c0 c1 c2 c3; do
  restore cut0; [ $c = c0 ] || AT=0 "$STEPS" "$W/m" "$J" forward $c 2>/dev/null
  check "fixture: forward to $c" "$(cut -d' ' -f1 "$J/cp")" $c
  push_revert; snap "rb-$c"
  inject "cutover rollback R1-R5 from $c" "rb-$c" cut_rb cut_rb p2_kept rb_end
done

if [ $NESTED = 1 ]; then
  inject2 "cutover forward" cut0 cut_fwd cut_fwd p2_kept fwd_end
  for c in c0 c1 c2 c3; do inject2 "cutover rollback from $c" "rb-$c" cut_rb cut_rb p2_kept rb_end; done
  # a rollback started from each interrupted forward point, itself interrupted at each of its points
  rbfwd "cutover rollback from every interrupted forward point, rollback interrupted" cut0 cut_fwd push_revert cut_rb p2_kept rb_end nested
fi

echo "== no code path accepts an arbitrary HEAD"
restore cut0; AT=0 "$STEPS" "$W/m" "$J" forward c1 2>/dev/null
git -C "$W/m" commit -q --allow-empty -m 'outside the procedure'
AT=0 cut_fwd; check "forward at c1 with an unexplained HEAD: STOP (3)" "$?" 3
push_revert; AT=0 cut_rb; check "rollback at c1 with an unexplained HEAD: STOP (3)" "$?" 3
restore cut0; n=$(AT=999 cut_fwd; awk '$3=="intent"{c++} $3=="intent" && c==2 {print $1; exit}' "$CLOG")   # P7's intent written, pull not done
restore cut0; AT=$n cut_fwd >/dev/null; check "P7 intent recorded (point $n)" "$(head -n 1 "$J/intent" | cut -d' ' -f1-2)" "p7 c2"
git -C "$W/m" commit -q --allow-empty -m 'outside the procedure'
AT=0 cut_fwd; check "recovery of P7 with HEAD neither OLD nor NEW: STOP (3), intent kept" "$? $(head -n 1 "$J/intent" | cut -d' ' -f1)" "3 p7"

echo "== R3 waits for R2 (mk's revert)"
restore cut0; AT=0 "$STEPS" "$W/m" "$J" forward c2 2>/dev/null
AT=0 cut_rb; check "rollback at c2 before the revert lands: refused (1), still c2, no intent" "$? $(cut -d' ' -f1 "$J/cp") $([ -e "$J/intent" ] && echo intent)" "1 c2 "
restore cut0; AT=0 cut_fwd
AT=0 cut_rb; check "rollback at c3 before the revert lands: R1 done, R3 refused (1)" "$? $(cut -d' ' -f1 "$J/cp") $([ -e "$J/intent" ] && echo intent)" "1 r1-done "
push_revert; AT=0 cut_rb; check "once the revert lands, rollback reaches R5" "$? $(rb_end && echo converged)" "0 converged"

echo "== Sol round-7 findings 2 and 3, rev 8 forms (the rev 7 forms: cutover-repro.sh)"
for s in p6 p7; do
  restore cut0; n=$(AT=999 cut_fwd; awk -v s="$s" '$3=="cp" {c++} $3=="cp" && c==(s=="p6"?1:2) {print $1; exit}' "$CLOG")
  restore cut0; AT=$n cut_fwd
  check "finding 2: $s killed after J/cp records its target, before the intent is retired (point $n)" "$(head -n 1 "$J/intent" | cut -d' ' -f1) $(cut -d' ' -f1 "$J/cp")" "$s $([ $s = p6 ] && echo c1 || echo c2)"
  AT=0 "$STEPS" "$W/m" "$J" recover 2>/dev/null
  check "finding 2: recovery sees cp == target and only retires the intent" "$? $([ -e "$J/intent" ] && echo kept) $(cut -d' ' -f1 "$J/cp") $(head -n 1 "$J/done-$s" | cut -d' ' -f1)" "0  $([ $s = p6 ] && echo c1 || echo c2) $s"
  AT=0 "$STEPS" "$W/m" "$J" recover 2>/dev/null; check "finding 2: a second recovery is a no-op" "$? $(cut -d' ' -f1 "$J/cp")" "0 $([ $s = p6 ] && echo c1 || echo c2)"
done
restore rb-c2; n=$(AT=999 cut_rb; awk '$3=="mv"{c++} $3=="mv" && c==2 {print $1; exit}' "$CLOG")   # R4: the aside of a.md, then its restore
restore rb-c2; AT=$n cut_rb
check "finding 3: rollback killed in R4 after restoring a.md (point $n)" "$(head -n 1 "$J/intent" | cut -d' ' -f1) $(cut -d' ' -f1 "$J/cp") $(cat "$W/m/docs/plans/a.md")" "r4 r3-done LOCAL EDIT a"
check "finding 3: the public status shows the restored local edit" "$(git -C "$W/m" status --porcelain -- docs/plans/a.md)" " M docs/plans/a.md"
AT=0 cut_rb; check "finding 3: rollback resumes R4 from its intent (no R3 rerun, no clean-status check) and reaches R5" "$? $(rb_end && echo converged)" "0 converged"

echo
echo "injection points covered (single crash per run, each followed by recovery and the continuing step):$SUMMARY"
echo "  TOTAL: $TOTAL"
[ "$TOTAL" -gt 0 ] || fail "no injection point was covered at all"
echo "expectations failed: $fails"
echo "scratch: $B"
[ $fails = 0 ]
