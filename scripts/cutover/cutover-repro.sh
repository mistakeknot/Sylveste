#!/bin/bash
# Local reproductions for Sol round-3 findings 1, 4 and 6 (rev 4 fixes) and
# Sol round-4 finding 2 (rev 5: rollback split on P5, unfreeze gate) and Sol
# round-5 finding 2 (rev 6: rollback per machine checkpoint) and Sol round-6
# finding 2 (rev 7: a durable intent before every cutover mutation, and recovery
# from checkpoint + intent + actual HEAD) and Sol round-7 findings 2 and 3
# (reproduced against the rev 7 functions here; the rev 8 generic intent
# mechanism is exercised by out/crash-inject.sh). Synthetic content; local bare remotes only (no network). Writes
# only under a fresh mktemp dir in $T_ROOT. No guarded git form is used.
# Usage: cutover-repro.sh > log ; exit 0 = every expectation held.
set -u
PATH=/usr/local/bin:/usr/bin:/bin
HERE=$(cd "$(dirname "$0")" && pwd) || exit 1
for v in $(compgen -e); do case $v in GIT_*) unset "$v" ;; esac; done   # no Git environment override reaches the fixtures
T=$(mktemp -d "${T_ROOT:-$HERE/../work}/cutrepro.XXXXXX") && T=$(cd "$T" && pwd -P) && [ -n "$T" ] && [ -d "$T" ] ||   # canonical: git reports physical paths
  { echo "cutover-repro: cannot allocate a scratch dir under ${T_ROOT:-$HERE/../work}; nothing changed" >&2; exit 1; }
export CUTOVER_REPORT=0 GIT_CONFIG_NOSYSTEM=1 HOME="$T/home"; mkdir -p "$HOME"
git config --global user.email t@example.invalid; git config --global user.name t
git config --global init.defaultBranch main; git config --global advice.detachedHead false
fails=0
check() { if [ "$2" = "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1: got [$2] want [$3]"; fails=$((fails+1)); fi; }
manifest() { (cd "$1" && find docs/plans -type f -print0 2>/dev/null | sort -z | xargs -0r sha256sum); }

git init -q --bare "$T/pub.git"
git clone -q "$T/pub.git" "$T/work" 2>/dev/null; cd "$T/work" || exit 1
mkdir -p docs/plans
printf 'base a\n' > docs/plans/a.md
seq 1 200 | sed 's/^/cadence plan line /' > docs/plans/cadence.md
printf 'readme\n' > README.md
git add -A; git commit -qm base; git push -q origin main
BASE=$(git rev-parse HEAD)

for m in mOld mNew mQ mP6a mP6b mP7 mP7x mP7b mP8 mC1 mC2 mR4; do   # machines with the same local state
  git clone -q "$T/pub.git" "$T/$m"
  printf 'LOCAL EDIT a (internal, never pushed)\n' > "$T/$m/docs/plans/a.md"
  printf 'untracked local\n' > "$T/$m/docs/plans/new.md"
  manifest "$T/$m" > "$T/$m.P2.manifest"
  git -C "$T/$m" status --porcelain > "$T/$m.P2.status"
done
for m in mR0 mGate mStay; do                       # two machines with no local edit to tracked files
  git clone -q "$T/pub.git" "$T/$m"
  printf 'untracked local\n' > "$T/$m/docs/plans/new.md"
  manifest "$T/$m" > "$T/$m.P2.manifest"
done
printf '%s\n' docs/plans/ > "$T/delete-list"
# rev 5 unfreeze gate (§1.4 "Unfreeze gate"): the next public pull deletes no
# internal path, and the on-disk internal set equals the state this exit expects
unfreeze_gate() {  # root expected-manifest
  git -C "$1" fetch -q origin || return 2
  local del; del=$(git -C "$1" diff --no-renames --name-only --diff-filter=D HEAD origin/main -- $(cat "$T/delete-list"))
  [ -z "$del" ] || { echo "  gate refuses $(basename "$1"): the next pull deletes $(echo $del)"; return 1; }
  [ "$(manifest "$1" | sha256sum)" = "$(sha256sum < "$2")" ] || { echo "  gate refuses $(basename "$1"): internal set differs from the expected state"; return 1; }
}
r3_ok() {  # root ledger : rev 6 R3 at c1: 0 if the status holds only ledger-accounted deletions
  local line p; git -C "$1" status --porcelain | while IFS= read -r line; do
    p=${line#???}; [ "${line%"$p"}" = " D " ] && grep -q "^P6 quarantine $p " "$2" || { echo "  R3 STOP: $line"; exit 1; }
  done
}
digest() { sha256sum < "$1" | cut -c1-16; }

# rev 7 (round-6 finding 2): a durable intent precedes every cutover mutation.
# $T/<m>.intent names the checkpoint the step is heading for (P7 adds the HEAD
# before the pull and the HEAD it expects); P6's ledger of planned moves and P8's
# ledger of planned writes are complete before the first move or write.
put() { printf '%s\n' "$2" > "$1.tmp" && mv "$1.tmp" "$1" && { sync "$1" 2>/dev/null || sync; }; }   # file text : atomic, durable
p6_intent() {  # m : P6 step 1, before any move
  (cd "$T/$1" && find docs/plans -type f) | sort | while read -r rel; do
    echo "P6 quarantine $rel $(digest "$T/$1/$rel")"; done > "$T/$1.ledger.tmp"
  mv "$T/$1.ledger.tmp" "$T/$1.ledger"; put "$T/$1.intent" c1
}
p6_move() { mkdir -p "$(dirname "$T/$1.Q/$2")" && mv "$T/$1/$2" "$T/$1.Q/$2"; }   # m rel
p6_full() {  # m : P6 to completion, then c1
  p6_intent "$1"; while read -r _ _ rel _; do p6_move "$1" "$rel"; done < "$T/$1.ledger"
  put "$T/$1.checkpoint" c1; rm -f "${T:?}/${1:?}.intent"
}
recover() {  # m : runs before any roll-forward or rollback step. Writes the
             # effective checkpoint to $T/<m>.eff; rc 1 = STOP, nothing moved
  local m=$1 cp it head rel d p q; rm -f "${T:?}/${m:?}.eff"
  cp=$(cat "$T/$m.checkpoint" 2>/dev/null || echo c0); it=$(cat "$T/$m.intent" 2>/dev/null)
  head=$(git -C "$T/$m" rev-parse HEAD)
  case "$cp ${it%% *}" in
    "c0 "|"c1 "|"c2 "|"c3 ") ;;
    "c0 c1")  # P6 part way: each planned file is in place or in quarantine, never both, never neither
      while read -r _ _ rel d; do
        p="$T/$m/$rel"; q="$T/$m.Q/$rel"
        if [ -e "$q" ] && [ ! -e "$p" ] && [ "$(digest "$q")" = "$d" ]; then :
        elif [ -e "$p" ] && [ ! -e "$q" ] && [ "$(digest "$p")" = "$d" ]; then :
        else echo "  recover STOP $m: $rel is not in exactly one place with its ledger digest"; return 1; fi
      done < "$T/$m.ledger"
      while read -r _ _ rel _; do
        [ -e "$T/$m.Q/$rel" ] || continue
        mkdir -p "$(dirname "$T/$m/$rel")" && mv "$T/$m.Q/$rel" "$T/$m/$rel" || return 1
      done < "$T/$m.ledger"
      [ "$(manifest "$T/$m" | sha256sum)" = "$(sha256sum < "$T/$m.P2.manifest")" ] ||
        { echo "  recover STOP $m: restored set differs from P2"; return 1; } ;;
    "c1 c2")  # P7: the pull either did not move HEAD, or moved it to the expected sha
      set -- $it
      if [ "$head" = "$2" ]; then :
      elif [ "$head" = "$3" ]; then put "$T/$m.checkpoint" c2; cp=c2
      else echo "  recover STOP $m: HEAD $head is neither the intent's base nor its target"; return 1; fi ;;
    *) echo "  recover STOP $m: checkpoint $cp with intent '$it'"; return 1 ;;
  esac
  rm -f "${T:?}/${m:?}.intent"; echo "$cp" > "$T/$m.eff"
}
r1_rev7() {  # m : R1 at c3 from P8's planned-write ledger (complete before P8's first write)
  local m=$1 step kind rel d p
  while read -r step kind rel d; do
    p="$T/$m/$rel"; [ -e "$p" ] || continue
    case $kind in
      return) { [ ! -e "$T/$m.Q/$rel" ] && [ "$(digest "$p")" = "$d" ]; } || { echo "  R1 STOP $m: $rel"; return 1; }
              mv "$p" "$T/$m.Q/$rel" ;;
      write)  mkdir -p "$(dirname "$T/$m.rb8/$rel")" && mv "$p" "$T/$m.rb8/$rel" &&
              echo "R1 aside $rel" >> "$T/$m.rb8.ledger" ;;
    esac
  done < "$T/$m.p8ledger"
}
rollback_r3_r4() {  # m checkpoint : R3 and R4 (rev 7); rc 1 = STOP
  local m=$1 cp=$2 p rel st
  git -C "$T/$m" fetch -q origin
  for p in $(git -C "$T/$m" diff --no-renames --name-only --diff-filter=A HEAD origin/main); do
    [ -e "$T/$m/$p" ] && { echo "  R3 STOP $m: incoming $p is present"; return 1; }; done
  git -C "$T/$m" pull -q --ff-only || return 1
  st=$(git -C "$T/$m" status --porcelain)
  case $cp in
    c0) [ "$st" = "$(cat "$T/$m.P2.status")" ] ;;
    c1) r3_ok "$T/$m" "$T/$m.ledger" ;;
    *)  [ -z "$st" ] ;;
  esac || { echo "  R3 STOP $m: status at $cp"; return 1; }
  [ "$cp" = c0 ] && return 0
  while read -r _ _ rel _; do
    if [ -e "$T/$m/$rel" ]; then
      [ "$cp" = c1 ] && { echo "  R4 STOP $m: $rel present at c1"; return 1; }
      mkdir -p "$(dirname "$T/$m.rbrev/$rel")" && mv "$T/$m/$rel" "$T/$m.rbrev/$rel" &&
        echo "R4 aside $rel $(digest "$T/$m.rbrev/$rel")" >> "$T/$m.rbrev.ledger" || return 1
    fi
    mkdir -p "$(dirname "$T/$m/$rel")" && mv "$T/$m.Q/$rel" "$T/$m/$rel" || return 1
  done < "$T/$m.ledger"
}
echo "== finding 2 (pre-merge): before P5 the R0 exit is open"
unfreeze_gate "$T/mGate" "$T/mGate.P2.manifest"; check "gate passes before PR 1 merges (R0)" "$?" 0

# PR 1: delete docs/plans/, relocate the cadence plan, ignore the internal set.
cd "$T/work" || exit 1; mkdir -p docs/specs
git mv docs/plans/cadence.md docs/specs/cadence.md
git rm -q -r docs/plans; printf 'docs/plans/\n' > .gitignore
git add -A; git commit -qm 'PR 1'; git push -q origin main
PR1=$(git rev-parse HEAD)

echo "== finding 2: P5 done (PR 1 merged), machine not yet changed"
echo " rev 4 R0: 'before P6 no worktree has changed', so unfreeze; autosync then pulls"
check "precondition: mR0 manifest still equals P2" "$(manifest "$T/mR0" | sha256sum)" "$(sha256sum < "$T/mR0.P2.manifest")"
git -C "$T/mR0" pull -q --ff-only
if [ ! -e "$T/mR0/docs/plans/a.md" ] && [ ! -e "$T/mR0/docs/plans/cadence.md" ] && [ ! -d "$T/mR0/.git-internal" ]; then
  echo "  reproduced: the pull deleted docs/plans/a.md and cadence.md, and no overlay is installed"; fi
check "rev 4 R0 loses the internal files" "$(manifest "$T/mR0")" "$(grep new.md "$T/mR0.P2.manifest")"
echo " rev 5: after P5 the only exits are roll forward (P6-P9) or revert (R1-R5); the gate holds the freeze in between"
unfreeze_gate "$T/mGate" "$T/mGate.P2.manifest"; check "gate refuses on a merged, unpulled machine" "$?" 1
mkdir -p "$T/mGate.Q"; mv "$T/mGate/docs/plans" "$T/mGate.Q/plans"           # P6
git -C "$T/mGate" pull -q --ff-only                                           # P7
unfreeze_gate "$T/mGate" "$T/mGate.P2.manifest"; check "gate refuses between P7 and P8 (internal set absent)" "$?" 1
mv "$T/mGate.Q/plans" "$T/mGate/docs/plans"                                    # stand-in for P8's absent-only install
unfreeze_gate "$T/mGate" "$T/mGate.P2.manifest"; check "gate passes after the roll forward completes" "$?" 0
check "files survive the next pull" "$(git -C "$T/mGate" pull -q --ff-only; manifest "$T/mGate" | sha256sum)" "$(sha256sum < "$T/mGate.P2.manifest")"

echo "== finding 4: P7 deleted-set check with a planned relocation"
for m in mOld mNew; do mkdir -p "$T/$m.Q"; mv "$T/$m/docs/plans" "$T/$m.Q/plans"; done
git -C "$T/mOld" pull -q --ff-only
OLD=$(git -C "$T/mOld" diff --name-only --diff-filter=D ORIG_HEAD HEAD | sort | tr '\n' ' ')
EXP=$(git -C "$T/mOld" ls-tree -r --name-only "$BASE" -- $(cat "$T/delete-list") | sort | tr '\n' ' ')
NEW=$(git -C "$T/mOld" diff --no-renames --name-only --diff-filter=D ORIG_HEAD HEAD | sort | tr '\n' ' ')
echo "  expanded source-removal manifest: $EXP"
echo "  rev 3 check (--diff-filter=D):     $OLD"
[ "$OLD" != "$EXP" ] && echo "  reproduced: the rename source docs/plans/cadence.md is missing from the rev 3 set"
check "rev 4 check (--no-renames) equals the expanded manifest" "$NEW" "$EXP"
git -C "$T/mNew" pull -q --ff-only
# mQ stops at checkpoint c1: P6 done (quarantine and its ledger), P7 not run
mkdir -p "$T/mQ.Q"; : > "$T/mQ.ledger"
(cd "$T/mQ" && find docs/plans -type f) | sort | while read -r rel; do
  echo "P6 quarantine $rel $(sha256sum < "$T/mQ/$rel" | cut -c1-16)" >> "$T/mQ.ledger"; done
mv "$T/mQ/docs/plans" "$T/mQ.Q/plans"; echo c1 > "$T/mQ.checkpoint"

# round-6 finding 2: steps interrupted between a mutation and the checkpoint that records it.
# mP6a: P6 stops part way (a.md moved, the rest not). mP6b: P6 moved everything,
# then its status check STOPs. Both still read c0, with files in quarantine.
p6_intent mP6a; p6_move mP6a docs/plans/a.md
p6_intent mP6b; while read -r _ _ rel _; do p6_move mP6b "$rel"; done < "$T/mP6b.ledger"
# mP7 and mP7x: P6 done (c1); P7 records its intent, the pull moves HEAD to PR 1,
# and the run stops before c2. mP7b: the same intent, but the pull never ran.
for m in mP7 mP7x; do p6_full $m; put "$T/$m.intent" "c2 $BASE $PR1"; git -C "$T/$m" pull -q --ff-only; done
p6_full mP7b; put "$T/mP7b.intent" "c2 $BASE $PR1"
# mP8: P6 and P7 done (c2). P8 writes its planned-write ledger and c3, then
# creates .git-internal, writes a.md, returns the local new.md, and stops. A
# rev 6 ledger, appended after each write, would hold only .git-internal.
p6_full mP8; put "$T/mP8.intent" "c2 $BASE $PR1"; git -C "$T/mP8" pull -q --ff-only
put "$T/mP8.checkpoint" c2; rm -f "${T:?}/mP8.intent"
{ echo "P8 write .git-internal -"; echo "P8 write docs/plans/a.md -"; echo "P8 write docs/plans/cadence.md -"
  echo "P8 return docs/plans/new.md $(digest "$T/mP8.Q/docs/plans/new.md")"; } > "$T/mP8.p8ledger"
put "$T/mP8.checkpoint" c3
mkdir "$T/mP8/.git-internal"; echo "P8 wrote .git-internal" > "$T/mP8.r6ledger"
mkdir -p "$T/mP8/docs/plans"; printf 'shared a\n' > "$T/mP8/docs/plans/a.md"
mv "$T/mP8.Q/docs/plans/new.md" "$T/mP8/docs/plans/new.md"

# round-7 finding 2: mC1 finishes P6 and records c1, then stops before removing
# the intent (c1 + intent c1). mC2 finishes P7's pull and records c2, then stops
# before removing the intent (c2 + intent c2); a rev 7 recover interrupted after
# its own c2 write leaves the same state. round-7 finding 3: mR4 sits at c1.
p6_intent mC1; while read -r _ _ rel _; do p6_move mC1 "$rel"; done < "$T/mC1.ledger"; put "$T/mC1.checkpoint" c1
p6_full mC2; put "$T/mC2.intent" "c2 $BASE $PR1"; git -C "$T/mC2" pull -q --ff-only; put "$T/mC2.checkpoint" c2
p6_full mR4

# mk reverts PR 1 on the remote.
cd "$T/work" || exit 1; git revert --no-edit HEAD >/dev/null; git push -q origin main

echo "== finding 1: rollback order"
echo " rev 3 order: move quarantine back (ignored files), then pull the revert"
mv "$T/mOld.Q/plans" "$T/mOld/docs/plans"
git -C "$T/mOld" pull -q --ff-only 2>&1 | sed 's/^/  git: /'
manifest "$T/mOld" > "$T/mOld.final"
if cmp -s "$T/mOld.P2.manifest" "$T/mOld.final"; then echo "  not reproduced"; else
  echo "  reproduced: pull overwrote the restored internal edit (manifest differs from P2):"
  diff "$T/mOld.P2.manifest" "$T/mOld.final" | sed 's/^/    /'; fi

echo " rev 4 order: R2 absent check, R3 pull revert, R4 swap via aside, R5 verify P2"
git -C "$T/mNew" fetch -q
INCOMING=$(git -C "$T/mNew" diff --no-renames --name-only --diff-filter=A HEAD origin/main)
present=0; for p in $INCOMING; do [ -e "$T/mNew/$p" ] && present=1; done
check "R2 every incoming path absent before the revert pull" "$present" 0
git -C "$T/mNew" pull -q --ff-only
mkdir -p "$T/mNew.aside"; : > "$T/mNew.ledger"
(cd "$T/mNew.Q" && find plans -type f) | sort | while read -r rel; do
  tgt="$T/mNew/docs/$rel"
  if [ -e "$tgt" ]; then mkdir -p "$(dirname "$T/mNew.aside/$rel")"; mv "$tgt" "$T/mNew.aside/$rel"
    echo "R4 aside $rel $(sha256sum < "$T/mNew.aside/$rel" | cut -c1-16)" >> "$T/mNew.ledger"; fi
  mkdir -p "$(dirname "$tgt")"; mv "$T/mNew.Q/$rel" "$tgt"
done
check "R5 on-disk manifest equals P2" "$(manifest "$T/mNew" | sha256sum)" "$(sha256sum < "$T/mNew.P2.manifest")"
check "R5 git status equals P2 status" "$(git -C "$T/mNew" status --porcelain | sha256sum)" "$(sha256sum < "$T/mNew.P2.status")"
echo "  ledger: $(wc -l < "$T/mNew.ledger") revert-written file(s) set aside"
echo "== finding 2 (post-revert): the revert exit reopens the gate"
unfreeze_gate "$T/mNew" "$T/mNew.P2.manifest"; check "gate passes after R5 on a reverted machine" "$?" 0
unfreeze_gate "$T/mStay" "$T/mStay.P2.manifest"; check "gate passes on a machine untouched since P2 once the revert is on main" "$?" 0

echo "== round-5 finding 2: a revert that lands before the machine pulled PR 1 (checkpoint c1)"
check "precondition: mQ at c1, HEAD still the base" "$(cat "$T/mQ.checkpoint") $(git -C "$T/mQ" rev-parse HEAD)" "c1 $BASE"
git -C "$T/mQ" pull -q --ff-only                                             # R3 pull: base -> revert adds nothing
st=$(git -C "$T/mQ" status --porcelain)
[ -n "$st" ] && [ ! -e "$T/mQ/docs/plans/a.md" ] &&
  echo "  reproduced: after the R3 pull the quarantined files are still missing; rev 5 R3 needs a clean status and stops before R4:" &&
  echo "$st" | sed 's/^/    /'
check "rev 5 R3 (status must be clean) stops" "$([ -z "$st" ] && echo clean || echo STOP)" STOP
echo " rev 6 R3: every status entry must be ' D' for a path in this machine's P6 ledger"
r3_ok "$T/mQ" "$T/mQ.ledger"; check "rev 6 R3 accepts the ledger-accounted deletions" "$?" 0
printf 'stray\n' > "$T/mQ/README.md"
r3_ok "$T/mQ" "$T/mQ.ledger" >/dev/null; check "rev 6 R3 still stops on anything else (a modified tracked file)" "$?" 1
git -C "$T/mQ" checkout -q -- README.md
mv "$T/mQ.Q/plans" "$T/mQ/docs/plans"                                         # R4 (nothing incoming, so no aside)
check "R5 on-disk manifest equals P2" "$(manifest "$T/mQ" | sha256sum)" "$(sha256sum < "$T/mQ.P2.manifest")"
check "R5 git status equals P2 status" "$(git -C "$T/mQ" status --porcelain | sha256sum)" "$(sha256sum < "$T/mQ.P2.status")"
check "R5 every ledger entry restored with its recorded digest" "$(while read -r _ _ rel d; do [ "$(sha256sum < "$T/mQ/$rel" | cut -c1-16)" = "$d" ] || echo "$rel"; done < "$T/mQ.ledger")" ""
unfreeze_gate "$T/mQ" "$T/mQ.P2.manifest"; check "gate passes after R5 at c1" "$?" 0

r5() {  # m label : R5 and the unfreeze gate
  check "$2: R5 on-disk manifest equals P2" "$(manifest "$T/$1" | sha256sum)" "$(sha256sum < "$T/$1.P2.manifest")"
  check "$2: R5 git status equals P2 status" "$(git -C "$T/$1" status --porcelain | sha256sum)" "$(sha256sum < "$T/$1.P2.status")"
  unfreeze_gate "$T/$1" "$T/$1.P2.manifest"; check "$2: unfreeze gate passes" "$?" 0
}
echo "== round-6 finding 2: a step interrupted before its checkpoint (rev 7: intent first, then recovery)"
echo " P6 stopped part way (mP6a: 1 of 3 files moved) or at its status check (mP6b: all moved)"
check "precondition: both read c0 with files in quarantine" \
  "$(for m in mP6a mP6b; do printf '%s %s ' "$(cat "$T/$m.checkpoint" 2>/dev/null || echo c0)" "$(find "$T/$m.Q" -type f | wc -l)"; done)" "c0 1 c0 3 "
for m in mP6a mP6b; do
  git -C "$T/$m" pull -q --ff-only     # rev 6 R3 at c0 (the revert's tree equals the base, so this writes nothing)
  st6=$([ "$(git -C "$T/$m" status --porcelain)" = "$(cat "$T/$m.P2.status")" ] && echo pass || echo STOP)
  unfreeze_gate "$T/$m" "$T/$m.P2.manifest" >/dev/null; g6=$?
  [ "$st6 $g6" = "STOP 1" ] && echo "  reproduced: rev 6 on $m reads c0, so R3 expects P2's status and stops on the quarantined paths; c0 has no restore step, and the gate refuses"
  check "rev 6 at c0 strands $m's quarantined files (R3 STOP, gate 1)" "$st6 $g6" "STOP 1"
done
printf 'external write\n' > "$T/mP6b/docs/plans/a.md"                  # a file at a quarantined path: unexplained
recover mP6b; check "rev 7 recover refuses a path that is both on disk and in quarantine" "$?" 1
check "nothing moved by the refused recover" "$(find "$T/mP6b.Q" -type f | wc -l)" 3
rm "${T:?}/mP6b/docs/plans/a.md"              # stand-in for the owner's decision
for m in mP6a mP6b; do
  recover $m; check "rev 7 recover on $m (c0 + intent c1) restores from quarantine" "$? $(cat "$T/$m.eff")" "0 c0"
  rollback_r3_r4 $m c0; check "$m R3-R4 at c0" "$?" 0
  r5 $m "$m"
done

echo " P7 moved HEAD to PR 1 and stopped before recording c2 (mP7, mP7x); the checkpoint still reads c1"
check "precondition: c1 with HEAD at PR 1" "$(cat "$T/mP7.checkpoint") $(git -C "$T/mP7" rev-parse HEAD)" "c1 $PR1"
git -C "$T/mP7" fetch -q origin
inc=$(git -C "$T/mP7" diff --no-renames --name-only --diff-filter=A HEAD origin/main | wc -l)
git -C "$T/mP7" pull -q --ff-only                                    # rev 6 R3 at c1
r3_ok "$T/mP7" "$T/mP7.ledger" >/dev/null; r3=$?
blocked=$(while read -r _ _ rel _; do [ -e "$T/mP7/$rel" ] && echo "$rel"; done < "$T/mP7.ledger" | wc -l)
[ "$inc $r3 $blocked" = "2 0 2" ] && echo "  reproduced: rev 6 treats mP7 as c1 (HEAD at the base), but the revert writes 2 files; R3 at c1 passes on a clean status, and R4 at c1 (no set-aside) meets the revert's copies at 2 quarantine targets"
check "rev 6 at c1 with HEAD at PR 1: R3 list not empty, R4 blocked at 2 targets" "$inc $r3 $blocked" "2 0 2"
recover mP7 >/dev/null; check "rev 7 recover refuses a HEAD that is neither side of the intent (mP7 after the rev 6 pull)" "$?" 1
recover mP7x; check "rev 7 recover on mP7x (c1 + intent c2, HEAD = target) yields c2" "$? $(cat "$T/mP7x.eff") $(cat "$T/mP7x.checkpoint")" "0 c2 c2"
rollback_r3_r4 mP7x c2; check "mP7x R3-R4 at c2" "$?" 0
check "the revert's 2 copies set aside, ledgered" "$(wc -l < "$T/mP7x.rbrev.ledger")" 2
r5 mP7x mP7x
recover mP7b; check "rev 7 recover on mP7b (c1 + intent c2, HEAD = base) yields c1" "$? $(cat "$T/mP7b.eff")" "0 c1"
rollback_r3_r4 mP7b c1; check "mP7b R3-R4 at c1" "$?" 0
r5 mP7b mP7b

echo " P8 stopped after writing a.md and returning new.md, before ledgering either (mP8 at c3)"
git -C "$T/mP8" fetch -q origin
left=$(for p in docs/plans/a.md docs/plans/cadence.md docs/plans/new.md; do [ -e "$T/mP8/$p" ] && ! grep -q " $p\$" "$T/mP8.r6ledger" && echo "$p"; done | tr '\n' ' ')
hit=$(for p in $(git -C "$T/mP8" diff --no-renames --name-only --diff-filter=A HEAD origin/main); do [ -e "$T/mP8/$p" ] && echo "$p"; done | tr '\n' ' ')
[ -n "$hit" ] && echo "  reproduced: rev 6 R1 sets aside only ledgered writes, leaving ${left}on disk; R3 then stops on $hit"
check "rev 6 R1 leaves P8's unledgered writes in the revert's way" "$left/$hit" "docs/plans/a.md docs/plans/new.md /docs/plans/a.md "
recover mP8; check "rev 7 recover on mP8 yields c3" "$? $(cat "$T/mP8.eff")" "0 c3"
r1_rev7 mP8; check "rev 7 R1 from the planned-write ledger" "$?" 0
check "R1 set aside a.md and .git-internal, and returned new.md to quarantine" \
  "$(cat "$T/mP8.rb8.ledger" | tr '\n' ' ')$([ -e "$T/mP8.Q/docs/plans/new.md" ] && echo returned)" "R1 aside .git-internal R1 aside docs/plans/a.md returned"
rollback_r3_r4 mP8 c3; check "mP8 R3-R4 at c3" "$?" 0
r5 mP8 mP8

echo "== round-7 finding 2: a step (or recover) interrupted after its checkpoint, before removing its intent"
check "precondition: mC1 reads c1 + intent c1, mC2 reads c2 + intent c2" \
  "$(cat "$T/mC1.checkpoint") $(cat "$T/mC1.intent") $(cat "$T/mC2.checkpoint") $(cut -d' ' -f1 "$T/mC2.intent")" "c1 c1 c2 c2"
recover mC1 >/dev/null; r1=$?; recover mC2 >/dev/null; r2=$?
[ "$r1 $r2" = "1 1" ] && echo "  reproduced: rev 7 recover has no 'c1 c1' or 'c2 c2' row, so a completed step whose intent survived STOPs"
check "rev 7 recover STOPs on c1+c1 and c2+c2" "$r1 $r2" "1 1"
echo "  rev 8: the intent's postcondition (checkpoint = target) is already true, so recovery only retires the intent; see crash-inject.sh (p6 'cp', p7 'cp')"

echo "== round-7 finding 3: rollback interrupted inside R4"
git -C "$T/mR4" fetch -q origin; git -C "$T/mR4" pull -q --ff-only                       # R3 done: HEAD = revert
REV=$(git -C "$T/mR4" rev-parse HEAD)
mkdir -p "$T/mR4/docs/plans"; mv "$T/mR4.Q/docs/plans/a.md" "$T/mR4/docs/plans/a.md"    # R4 restored a.md, then stopped
recover mR4 >/dev/null; rr=$?
[ "$rr $(cat "$T/mR4.eff" 2>/dev/null)" = "0 c1" ] && [ "$REV" != "$BASE" ] &&
  echo "  reproduced: rev 7 recover has no intent here, so it accepts HEAD at the revert (neither c1's base nor any recorded sha) and reports c1"
check "rev 7 recover accepts an unrecorded HEAD when no intent exists" "$rr $(cat "$T/mR4.eff" 2>/dev/null)" "0 c1"
st=$(git -C "$T/mR4" status --porcelain | tr '\n' ' ')
rollback_r3_r4 mR4 c1 >/dev/null; rb=$?
[ "$rb" = 1 ] && echo "  reproduced: restarting rev 7 R3 at c1 STOPs on the restored file (status: $st)"
check "rev 7 rollback cannot resume after a partial R4" "$rb" 1
echo "  rev 8: R3 and R4 each run under an intent (r3: ff OLD REV; r4: one mv per ledger file); R4 resumes after a verified R3 and skips files already restored; see crash-inject.sh (rb-c1, rb-c2 'R4 killed after restoring a.md')"

echo "== finding 6: overlay bindings after relocating the root"
R1="$T/root1"; mkdir -p "$R1/docs/plans"; printf 'x\n' > "$R1/docs/plans/x.md"
git init -q --bare "$R1/.git-internal"
git --git-dir="$R1/.git-internal" config core.bare false
git --git-dir="$R1/.git-internal" config core.worktree "$R1"
git --git-dir="$R1/.git-internal" config status.showUntrackedFiles no
git --git-dir="$R1/.git-internal" config core.hooksPath "$R1/.git-internal/hooks"
mkdir -p "$R1/.git-internal/hooks"
printf '#!/bin/sh\necho "$PWD" > "$(git rev-parse --git-dir)/hook-ran"\n' > "$R1/.git-internal/hooks/pre-commit"
chmod +x "$R1/.git-internal/hooks/pre-commit"
git --git-dir="$R1/.git-internal" add docs/plans/x.md
git --git-dir="$R1/.git-internal" commit -qm x
R2="$T/root2"; mv "$R1" "$R2"
top=$(git --git-dir="$R2/.git-internal" rev-parse --show-toplevel 2>&1); rc=$?
echo "  after the move, unbound: rc $rc, toplevel/err: ${top##*/}"
[ "$top" != "$R2" ] && echo "  reproduced: private git does not resolve to the new root"
git --git-dir="$R2/.git-internal" config core.worktree "$R2"
git --git-dir="$R2/.git-internal" config core.hooksPath "$R2/.git-internal/hooks"
check "rebound toplevel is the new root" "$(git --git-dir="$R2/.git-internal" rev-parse --show-toplevel)" "$R2"
check "rebound hooksPath is under the new root" "$(git --git-dir="$R2/.git-internal" config core.hooksPath)" "$R2/.git-internal/hooks"
check "rebound status clean" "$(git --git-dir="$R2/.git-internal" status --porcelain)" ""
printf 'y\n' >> "$R2/docs/plans/x.md"; git --git-dir="$R2/.git-internal" add docs/plans/x.md
git --git-dir="$R2/.git-internal" commit -qm y
check "pre-commit hook ran from the new root" "$(cat "$R2/.git-internal/hook-ran" 2>/dev/null)" "$R2"
check "no config value names the old root" "$(git --git-dir="$R2/.git-internal" config --list | grep -c "$R1")" 0

echo " rev 3 hazard variant: a relative core.hooksPath skips pre-push when git runs from outside the root"
R5="$T/root5"; mkdir -p "$R5"; git init -q --bare "$T/r5remote.git"
git init -q --bare "$R5/.git-internal"
git --git-dir="$R5/.git-internal" config core.bare false
git --git-dir="$R5/.git-internal" config core.worktree ..
git --git-dir="$R5/.git-internal" config status.showUntrackedFiles no
git --git-dir="$R5/.git-internal" remote add origin "$T/r5remote.git"
mkdir -p "$R5/.git-internal/hooks" "$R5/docs"; printf 'z\n' > "$R5/docs/z.md"
printf '#!/bin/sh\nwhile read -r l ls r rs; do [ "$r" = refs/heads/main ] && exit 1; done; exit 0\n' > "$R5/.git-internal/hooks/pre-push"
chmod +x "$R5/.git-internal/hooks/pre-push"
git --git-dir="$R5/.git-internal" add "$R5/docs/z.md"; git --git-dir="$R5/.git-internal" commit -qm z
cd "$T" || exit 1
git --git-dir="$R5/.git-internal" config core.hooksPath .git-internal/hooks
git --git-dir="$R5/.git-internal" push -q --dry-run origin HEAD:refs/heads/main 2>/dev/null
rc=$?; [ $rc = 0 ] && echo "  reproduced: relative hooksPath, run from outside the root: push to main NOT refused (rc 0)"
echo " rev 4 binding: core.worktree=.. and no core.hooksPath (hooks = \$GIT_DIR/hooks), then move the root"
git --git-dir="$R5/.git-internal" config --unset core.hooksPath
R6="$T/root6"; mv "$R5" "$R6"; cd "$T" || exit 1
check "toplevel is the new root" "$(git --git-dir="$R6/.git-internal" rev-parse --show-toplevel)" "$R6"
check "hooks path is inside the moved git dir" "$(git --git-dir="$R6/.git-internal" rev-parse --git-path hooks)" "$R6/.git-internal/hooks"
check "status clean" "$(git --git-dir="$R6/.git-internal" status --porcelain)" ""
git --git-dir="$R6/.git-internal" push -q --dry-run origin HEAD:refs/heads/main 2>/dev/null
check "pre-push probe refuses main after the move" "$?" 1
check "no config value names the old root" "$(git --git-dir="$R6/.git-internal" config --list | grep -c "$R5")" 0

echo; echo "expectations failed: $fails"; echo "scratch: $T"
exit $((fails > 0))
