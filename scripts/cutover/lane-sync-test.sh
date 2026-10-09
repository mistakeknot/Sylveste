#!/bin/bash
# Test of the private overlay helper and its sync protocol (plan §1.4 P8, P9,
# "Private sync"), revision 8. Runs the helper and hook templates from
# $GI_TREE (default: the reference tree out/git-internal, which PR 1 adds
# verbatim as scripts/; RH points GI_TREE at PR 1's checkout). Every machine
# root is a public repo whose .gitignore ignores the internal path set, as
# after PR 1. The rev 4 forms are kept as sync_r4/probe_r4 and reproduce Sol
# round-4 findings 1, 3 and 4; each fix is checked against the same state.
# Revision 6 adds Sol round-5 findings 1, 3 and 4: the verbatim rev 5 helper
# (out/repro-r5/git-internal, $REPRO5) reproduces 1 and 3 on machine F, and
# the current helper is checked against the same state on G, H and B.
# Revision 7 adds Sol round-6 findings 1 and 3: the verbatim rev 6 helper
# (out/repro-r6/git-internal, $REPRO6) reproduces symlink corruption on SX and
# SZ (scratch remote sym.git) and the silent importer failure on F; the
# current helper is checked against the same state on SY and B.
# Revision 8 records an unfinished sync or resolve as the intent
# $GIT_DIR/git-internal-intent ("STEP OLD NEW") instead of a pending-import
# record; crash recovery itself is tested by crash-inject.sh.
# Revision 8.2 adds Sol round-9: a corrupted fold ref under an unfinished
# resolve. The verbatim rev 8.1 helper (out/repro-r8.1/git-internal) treats it
# as absent, imports and retires the intent; rev 8.2 stops (10) until the
# owner removes the broken ref.
# Revision 8.1 adds Sol round-8: with a stale ORIG_HEAD.lock and an older
# ORIG_HEAD, the verbatim rev 8 helper (out/repro-r8/git-internal, $REPRO8)
# finishes an unfinished sync by importing the wrong range and pushing (F);
# the current helper stops (10) on B, and re-sets an older ORIG_HEAD on E.
# Portable to macOS /bin/bash 3.2 and BSD tools, for the Clavain run in P0.
# Synthetic content, local bare remotes only, fresh mktemp dir under $T_ROOT.
set -u
PATH=${GIT_INTERNAL_PATH:-/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin}
HERE=$(cd "$(dirname "$0")" && pwd) || exit 1
for v in $(compgen -e); do case $v in GIT_*) unset "$v" ;; esac; done   # no Git environment override reaches the fixtures
GI_TREE=${GI_TREE:-$HERE/git-internal}
HELPER=$GI_TREE/scripts/git-internal
REPRO5=$HERE/repro-r5/git-internal
REPRO6=$HERE/repro-r6/git-internal
REPRO8=$HERE/repro-r8/git-internal
REPRO81=$HERE/repro-r8.1/git-internal
T=$(mktemp -d "${T_ROOT:-$HERE/../work}/lanesync.XXXXXX") && T=$(cd "$T" && pwd -P) && [ -n "$T" ] && [ -d "$T" ] ||   # canonical: git reports physical paths
  { echo "lane-sync-test: cannot allocate a scratch dir under ${T_ROOT:-$HERE/../work}; nothing changed" >&2; exit 1; }
export GIT_CONFIG_NOSYSTEM=1 HOME="$T/home"; mkdir -p "$HOME"
git config --global user.email t@example.invalid; git config --global user.name t
git config --global init.defaultBranch main
fails=0
check() { if [ "$2" = "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1: got [$2] want [$3]"; fails=$((fails+1)); fi; }
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum ${1+"$@"}; else shasum -a 256 ${1+"$@"}; fi; }
manifest() { (cd "$1" && find docs/plans -type f | LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$(sha < "$f" | cut -c1-64)" "$f"; done) | sha | cut -c1-16; }
idxsum() { gi "$1" ls-files -s | sha | cut -c1-16; }
echo "helper: $HELPER ($(sha < "$HELPER" | cut -c1-16)); bash $BASH_VERSION; $(git version)"

# int.git seeded as P4 leaves it (the seed push is mk's).
git init -q --bare "$T/int.git"
git clone -q "$T/int.git" "$T/seed" 2>/dev/null; mkdir -p "$T/seed/docs/plans"
printf 'shared v1\n' > "$T/seed/docs/plans/shared.md"
git -C "$T/seed" add -A; git -C "$T/seed" commit -qm seed; git -C "$T/seed" push -q origin main
SEED=$(git -C "$T/int.git" rev-parse main)

gi() { local r=$1; shift; git -C "$r" --git-dir="$r/.git-internal" "$@"; }
GI() { local r=$1; shift; "$HELPER" -C "$r" "$@"; }
machine() {  # root : a public checkout after PR 1 (internal set gitignored)
  git init -q "$1"; printf 'docs/plans/\n/.git-internal/\n' > "$1/.gitignore"
  git -C "$1" add .gitignore; git -C "$1" commit -qm 'public after PR 1'
}
put() { mkdir -p "$(dirname "$1/$2")"; printf '%s\n' "$3" > "$1/$2"; }
commit() { put "$1" "$2" "$3"; GI "$1" add "$2" && GI "$1" commit -m "$2"; }
# revision 4 forms, kept only to reproduce the findings (R never pushes)
sync_r4() {
  local r=$1 h ref; h=$(cat "$r/.git-internal/info/host")
  gi "$r" fetch -q origin || return 2
  for ref in $(gi "$r" for-each-ref --format='%(refname:short)' refs/remotes/origin/main 'refs/remotes/origin/autosync/*'); do
    [ "$ref" = "origin/autosync/$h" ] && continue
    gi "$r" merge-base --is-ancestor "$ref" HEAD && continue
    gi "$r" merge-tree --write-tree HEAD "$ref" >/dev/null 2>&1 || return 3
    gi "$r" merge -q --no-edit "$ref" || return 4
  done
}
probe_r4() { (cd "$T" && git --git-dir="$1/.git-internal" push -q --dry-run origin HEAD:refs/heads/main 2>/dev/null); }

A="$T/mA"; B="$T/mB"; E="$T/mE"; R="$T/mR"
for m in A B E R; do r=${!m}; machine "$r"; GI "$r" install "$T/int.git" "m$m"; done
check "overlay installed on A and B" "$(manifest "$A") $(cat "$A/docs/plans/shared.md")" "$(manifest "$B") shared v1"
check "public status clean after install (internal set and .git-internal ignored)" "$(git -C "$A" status --porcelain)" ""

echo "== finding 5: hooks come from the helper's own tree, installed before first use"
check "pre-push is the template" "$(cmp -s "$GI_TREE/scripts/git-internal-hooks/pre-push" "$A/.git-internal/hooks/pre-push"; echo $?)" 0
check "pre-commit is the template" "$(cmp -s "$GI_TREE/scripts/git-internal-hooks/pre-commit" "$A/.git-internal/hooks/pre-commit"; echo $?)" 0
check "approved-paths is the template" "$(cmp -s "$GI_TREE/scripts/git-internal-hooks/approved-paths" "$A/.git-internal/info/approved-paths"; echo $?)" 0
check "hook sha256 record verifies" "$(cd "$A/.git-internal/hooks" && while read -r w f; do [ "$(sha < "$f" | cut -c1-64)" = "$w" ] || echo "$f"; done < ../info/hooks.sha256)" ""

echo "== finding 4: P9 probe right after install, when HEAD equals origin/main"
check "precondition: HEAD == origin/main" "$(gi "$A" rev-parse HEAD)" "$(gi "$A" rev-parse origin/main)"
probe_r4 "$A"; rc=$?
[ $rc = 0 ] && echo "  reproduced: rev 4 probe 'push --dry-run HEAD:main' returns 0 (no update, the hook never runs)"
check "rev 4 probe is vacuous here" "$rc" 0
(cd "$T" && GI "$A" probe >/dev/null); check "rev 5 probe (synthetic commit) passes: main refused, own lane allowed" "$?" 0
mv "$A/.git-internal/hooks/pre-push" "$T/pre-push.aside"
(cd "$T" && GI "$A" probe 2>/dev/null); check "rev 5 probe fails (8) with the pre-push hook missing" "$?" 8
probe_r4 "$A"; check "rev 4 probe still returns 0 with the hook missing" "$?" 0
mv "$T/pre-push.aside" "$A/.git-internal/hooks/pre-push"
printf '#!/bin/sh\nexit 0\n' > "$B/.git-internal/hooks/pre-push"
(cd "$T" && GI "$B" probe 2>/dev/null); check "rev 5 probe fails (8) with a permissive pre-push hook" "$?" 8
GI "$B" install-hooks; (cd "$T" && GI "$B" probe >/dev/null); check "probe passes again after install-hooks" "$?" 0

echo "== install refuses to overwrite an existing file"
C="$T/mC"; machine "$C"; put "$C" docs/plans/shared.md LOCAL
GI "$C" install "$T/int.git" mC 2>/dev/null; check "install exits 5 when a target exists" "$?" 5
check "existing file kept" "$(cat "$C/docs/plans/shared.md")" "LOCAL"
gi "$C" checkout-index -a 2>/dev/null; check "second line (a file that appears after the preflight): checkout-index without -f refuses" "$?" 1
check "existing file still kept" "$(cat "$C/docs/plans/shared.md")" "LOCAL"
GI "$C" sync 2>/dev/null; check "rev 8: a sync on the unfinished install refuses (4)" "$?" 4
mv "$C/docs/plans/shared.md" "$T/C-shared.aside"
GI "$C" install "$T/int.git" mC 2>/dev/null; check "rev 8: after the owner moves it aside, install reruns and finishes" "$? $(cat "$C/docs/plans/shared.md") $(cat "$C/.git-internal/info/installed")" "0 shared v1 $T/int.git mC"
GI "$C" install "$T/int.git" mC 2>/dev/null; check "rev 8: a finished install refuses a rerun (4)" "$?" 4

echo "== finding 1b: staging under the public .gitignore"
put "$A" docs/plans/a1.md 'from A'
gi "$A" add -- docs/plans/a1.md 2>/dev/null; rc=$?
[ $rc = 1 ] && echo "  reproduced: plain 'git add' of a new internal file returns 1 (the public ignore rule applies)"
check "plain add refused by the ignore rule" "$rc" 1
GI "$A" add docs/plans/a1.md; check "helper add (add -f, approved path) succeeds" "$?" 0
put "$A" notes.md 'not internal'
GI "$A" add notes.md 2>/dev/null; check "helper refuses a non-approved path" "$?" 1
GI "$A" add -A 2>/dev/null; check "helper refuses add -A" "$?" 1
GI "$A" add . 2>/dev/null; check "helper refuses add ." "$?" 1
GI "$A" add docs/plans/../notes.md 2>/dev/null; check "helper refuses a path with .." "$?" 1
gi "$A" add -f notes.md
GI "$A" commit -m bad 2>/dev/null; check "pre-commit hook refuses a force-staged non-approved path" "$?" 1
gi "$A" rm -q --cached notes.md; rm "${A:?}/notes.md"
GI "$A" commit -m a1; check "commit of the approved path" "$?" 0

echo "== new files travel both ways through lanes only"
GI "$A" sync
commit "$B" docs/plans/b1.md 'from B'; GI "$B" sync
a0=$(gi "$A" rev-parse HEAD); GI "$A" sync; GI "$B" sync
check "ORIG_HEAD is the pre-sync HEAD (the PR 2 importer reads ORIG_HEAD..HEAD)" "$(gi "$A" rev-parse ORIG_HEAD)" "$a0"
check "A and B converge" "$(manifest "$A")" "$(manifest "$B")"
check "A has b1" "$(cat "$A/docs/plans/b1.md")" "from B"
check "B has a1" "$(cat "$B/docs/plans/a1.md")" "from A"
check "private main untouched by agents" "$(git -C "$T/int.git" rev-parse main)" "$SEED"
check "public status still clean on B" "$(git -C "$B" status --porcelain)" ""

echo "== authority: the private pre-push hook"
gi "$A" push -q origin HEAD:refs/heads/main 2>/dev/null; check "push to main refused" "$?" 1
commit "$A" docs/plans/a2.md 'A unpushed'   # a real push, not an up-to-date no-op
gi "$A" push -q origin HEAD:refs/heads/autosync/mB 2>/dev/null; check "push to the other host's lane refused" "$?" 1
gi "$A" push -q origin :refs/heads/autosync/mA 2>/dev/null; check "deleting the own lane refused" "$?" 1
check "main still the seed" "$(git -C "$T/int.git" rev-parse main)" "$SEED"
GI "$A" sync

echo "== finding 1: an incoming path that exists locally as an ignored file"
commit "$A" docs/plans/n1.md 'from A'; GI "$A" sync
put "$R" docs/plans/n1.md 'LOCAL R'; put "$B" docs/plans/n1.md 'LOCAL B'
check "precondition: n1 is gitignored on B" "$(git -C "$B" check-ignore -q docs/plans/n1.md; echo $?)" 0
sync_r4 "$R"; rc=$?
[ "$rc $(cat "$R/docs/plans/n1.md")" = "0 from A" ] && echo "  reproduced: rev 4 sync (merge) exits 0 and replaces the local ignored file's bytes"
check "rev 4 sync overwrote R's local file" "$rc $(cat "$R/docs/plans/n1.md")" "0 from A"
bhead=$(gi "$B" rev-parse HEAD); bidx=$(idxsum "$B"); bman=$(manifest "$B")
GI "$B" sync 2>"$T/b.err"; check "rev 5 sync exits 5 on the collision" "$?" 5
check "B's local file kept" "$(cat "$B/docs/plans/n1.md")" "LOCAL B"
check "B HEAD unchanged" "$(gi "$B" rev-parse HEAD)" "$bhead"
check "B index unchanged" "$(idxsum "$B")" "$bidx"
check "B worktree unchanged" "$(manifest "$B")" "$bman"
check "collision report names the file as gitignored" "$(grep -c '(gitignored) docs/plans/n1.md' "$T/b.err")" 1
mkdir -p "$T/B.aside"; mv "$B/docs/plans/n1.md" "$T/B.aside/"     # the owner's call
GI "$B" sync; check "after the owner moves it aside, sync succeeds" "$?" 0
check "B has A's n1" "$(cat "$B/docs/plans/n1.md")" "from A"
echo " a tracked file with a local edit that the sync would change"
commit "$A" docs/plans/b1.md 'B text, A edit'; GI "$A" sync
put "$B" docs/plans/b1.md 'uncommitted B edit'; bhead=$(gi "$B" rev-parse HEAD)
GI "$B" sync 2>/dev/null; check "sync exits 4 on a local edit to a changed path" "$?" 4
check "local edit kept" "$(cat "$B/docs/plans/b1.md")" "uncommitted B edit"
check "B HEAD unchanged" "$(gi "$B" rev-parse HEAD)" "$bhead"
commit "$B" docs/plans/b1.md 'B text, A edit'; GI "$B" sync; check "same content committed: sync merges" "$?" 0

echo "== finding 3: several incoming refs, the first clean and the second conflicting"
GI "$A" sync; GI "$E" sync; GI "$B" sync; sync_r4 "$R" >/dev/null 2>&1
commit "$A" docs/plans/a3.md 'A only'; GI "$A" sync                 # autosync/mA: clean for B and R
commit "$E" docs/plans/e1.md 'E only'
commit "$E" docs/plans/shared.md 'E edit'; GI "$E" sync            # autosync/mE: conflicts
commit "$B" docs/plans/shared.md 'B edit'
put "$R" docs/plans/shared.md 'R edit'; gi "$R" add -f docs/plans/shared.md; gi "$R" commit -qm 'R edit'
rhead=$(gi "$R" rev-parse HEAD)
sync_r4 "$R"; rc=$?
[ $rc = 3 ] && [ "$(gi "$R" rev-parse HEAD)" != "$rhead" ] && [ -f "$R/docs/plans/a3.md" ] &&
  echo "  reproduced: rev 4 sync exits 3 after the first merge already moved HEAD and wrote a3.md"
check "rev 4 partial write (rc, HEAD moved, a3 written)" "$rc $([ "$(gi "$R" rev-parse HEAD)" != "$rhead" ] && echo moved) $([ -f "$R/docs/plans/a3.md" ] && echo written)" "3 moved written"
bhead=$(gi "$B" rev-parse HEAD); bidx=$(idxsum "$B"); bman=$(manifest "$B")
GI "$B" sync 2>"$T/b3.err"; check "rev 5 sync exits 3" "$?" 3
check "B HEAD unchanged" "$(gi "$B" rev-parse HEAD)" "$bhead"
check "B index unchanged" "$(idxsum "$B")" "$bidx"
check "B worktree unchanged (no a3.md)" "$(manifest "$B") $([ -e "$B/docs/plans/a3.md" ] && echo a3)" "$bman "
check "B lane on the remote unchanged" "$(git -C "$T/int.git" rev-parse autosync/mB)" "$(gi "$B" rev-parse origin/autosync/mB)"
check "conflict report names shared.md" "$(grep -c '^  docs/plans/shared.md$' "$T/b3.err")" 1
echo " rev 4 resolution (merge -s ours) on R drops the other side's non-conflicting work"
put "$R" docs/plans/shared.md "$(printf 'E edit\nR edit')"; gi "$R" add -f docs/plans/shared.md; gi "$R" commit -qm resolve
gi "$R" merge -q -s ours --no-edit origin/autosync/mE
rc=$(gi "$R" cat-file -e HEAD:docs/plans/e1.md 2>/dev/null; echo $?)
[ "$rc" != 0 ] && echo "  reproduced: after 'merge -s ours' R's tree lacks e1.md, and a fast-forward would delete it elsewhere"
check "rev 4 resolution loses e1.md" "$rc" 128
echo " rev 5 resolution: resolve takes only the conflicted paths from disk"
put "$B" docs/plans/shared.md "$(printf 'E edit\nB edit')"
GI "$B" resolve origin/autosync/mE; check "resolve exits 0" "$?" 0
check "B has E's non-conflicting e1.md" "$(cat "$B/docs/plans/e1.md")" "E only"
GI "$B" sync; check "sync after resolve" "$?" 0
check "B has A's a3.md" "$(cat "$B/docs/plans/a3.md")" "A only"
GI "$A" sync; GI "$E" sync; GI "$B" sync
check "A, B and E converge" "$(manifest "$A") $(manifest "$E")" "$(manifest "$B") $(manifest "$B")"
check "resolved text everywhere" "$(cat "$A/docs/plans/shared.md" | tr '\n' '|')" "E edit|B edit|"
check "public status clean on all" "$(git -C "$A" status --porcelain)$(git -C "$B" status --porcelain)$(git -C "$E" status --porcelain)" ""
check "private status clean on all" "$(GI "$A" status --porcelain)$(GI "$B" status --porcelain)$(GI "$E" status --porcelain)" ""

echo "== round-5 finding 1: resolve merges into the recorded fold, not into HEAD"
F="$T/mF"; G="$T/mG"; H="$T/mH"
for m in F G H; do r=${!m}; machine "$r"; GI "$r" install "$T/int.git" "m$m"; done
for m in A F G H E B A E F G H B; do GI "${!m}" sync || echo "  setup sync on $m failed"; done
check "pruned fold: every lane converges to one commit" "$(git -C "$T/int.git" for-each-ref --format='%(objectname)' refs/heads/autosync | sort -u | wc -l | tr -d ' ')" 1
commit "$A" docs/plans/shared.md 'A3'; gi "$A" push -q origin HEAD:refs/heads/autosync/mA; asha=$(gi "$A" rev-parse HEAD)
commit "$E" docs/plans/shared.md 'E3'; gi "$E" push -q origin HEAD:refs/heads/autosync/mE; esha=$(gi "$E" rev-parse HEAD)
RESOLVED=$(printf 'A3\nE3')
fhead=$(gi "$F" rev-parse HEAD)
"$REPRO5" -C "$F" sync 2>/dev/null; check "rev 5 sync on F (folds mA, conflicts with mE) exits 3" "$?" 3
put "$F" docs/plans/shared.md "$RESOLVED"
"$REPRO5" -C "$F" resolve origin/autosync/mE 2>"$T/f.err"; rc=$?
[ $rc = 1 ] && grep -q 'does not conflict with HEAD' "$T/f.err" &&
  echo "  reproduced: rev 5 resolve merges HEAD (not the fold) with mE, finds no conflict and exits 1"
check "rev 5 resolve is unreachable" "$rc" 1
check "F HEAD unchanged" "$(gi "$F" rev-parse HEAD)" "$fhead"
gi "$F" checkout -q -- docs/plans/shared.md
ghead=$(gi "$G" rev-parse HEAD); gman=$(manifest "$G")
GI "$G" sync 2>/dev/null; check "rev 6 sync on G exits 3" "$?" 3
check "G records the conflict (state file and fold ref)" "$([ -s "$G/.git-internal/git-internal-conflict" ] && echo state) $(gi "$G" rev-parse -q --verify refs/git-internal/fold >/dev/null && echo fold)" "state fold"
check "G HEAD and worktree unchanged" "$(gi "$G" rev-parse HEAD) $(manifest "$G")" "$ghead $gman"
echo " stale state: HEAD moves after the conflict is recorded (H)"
GI "$H" sync 2>/dev/null; check "sync on H exits 3" "$?" 3
commit "$H" docs/plans/h1.md 'from H'; hhead=$(gi "$H" rev-parse HEAD)
put "$H" docs/plans/shared.md "$RESOLVED"
GI "$H" resolve origin/autosync/mE 2>/dev/null; check "resolve refuses (4) when HEAD moved since the conflict" "$?" 4
check "H HEAD unchanged by the refused resolve" "$(gi "$H" rev-parse HEAD)" "$hhead"
gi "$H" checkout -q -- docs/plans/shared.md
GI "$H" sync 2>/dev/null; check "sync on H records the conflict again (3)" "$?" 3
put "$H" docs/plans/shared.md "$RESOLVED"
GI "$H" resolve origin/autosync/mE; check "resolve on H exits 0" "$?" 0
check "H carries A, E and its own h1" "$(gi "$H" merge-base --is-ancestor "$asha" HEAD && echo a) $(gi "$H" merge-base --is-ancestor "$esha" HEAD && echo e) $(gi "$H" merge-base --is-ancestor "$hhead" HEAD && echo h)" "a e h"
check "H lane pushed" "$(git -C "$T/int.git" rev-parse autosync/mH)" "$(gi "$H" rev-parse HEAD)"
echo " the main path (G)"
put "$G" docs/plans/shared.md "$RESOLVED"
GI "$G" resolve origin/autosync/mA 2>/dev/null; check "resolve with a ref other than the recorded one exits 1" "$?" 1
GI "$G" resolve origin/autosync/mE; check "resolve on G exits 0" "$?" 0
check "G carries A's and E's commits" "$(gi "$G" merge-base --is-ancestor "$asha" HEAD && echo a) $(gi "$G" merge-base --is-ancestor "$esha" HEAD && echo e)" "a e"
check "G content is the resolution" "$(gi "$G" show HEAD:docs/plans/shared.md | tr '\n' '|') $(tr '\n' '|' < "$G/docs/plans/shared.md")" "A3|E3| A3|E3|"
check "G public and private status clean" "$(git -C "$G" status --porcelain)$(GI "$G" status --porcelain)" ""
check "G state cleared (no state file, no fold ref)" "$([ -e "$G/.git-internal/git-internal-conflict" ] && echo state)$(gi "$G" rev-parse -q --verify refs/git-internal/fold)" ""
GI "$G" resolve origin/autosync/mE 2>/dev/null; check "a second resolve exits 1 (nothing recorded)" "$?" 1
echo " a machine that stayed at the base meets the resolutions first (pruning)"
GI "$B" sync; check "B syncs without a conflict: mG and mH carry mA and mE" "$?" 0
for m in A E F G H B A E F G H; do GI "${!m}" sync || echo "  sync on $m failed"; done
check "all lanes converge to one commit" "$(git -C "$T/int.git" for-each-ref --format='%(objectname)' refs/heads/autosync | sort -u | wc -l | tr -d ' ')" 1
check "A, F and H hold the resolution and h1" "$(tr '\n' '|' < "$A/docs/plans/shared.md") $(cat "$F/docs/plans/h1.md") $(manifest "$F") $(manifest "$H")" "A3|E3| from H $(manifest "$A") $(manifest "$A")"
check "private status clean on A, B, E, F, G, H" "$(for m in A B E F G H; do GI "${!m}" status --porcelain; done)" ""

echo "== round-5 finding 3: an incoming mode change (overlay-delivered hooks and scripts)"
commit "$A" docs/plans/run.sh 'echo run'; for m in A B F; do GI "${!m}" sync; done
check "precondition: run.sh not executable on B and F" "$([ -x "$B/docs/plans/run.sh" ] && echo B)$([ -x "$F/docs/plans/run.sh" ] && echo F)" ""
chmod +x "$A/docs/plans/run.sh"; GI "$A" add docs/plans/run.sh; GI "$A" commit -m 'run.sh +x'; GI "$A" sync
check "precondition: the incoming change is mode only" "$(gi "$A" diff --raw HEAD~1 HEAD -- docs/plans/run.sh | cut -c1-15)" ":100644 100755 "
"$REPRO5" -C "$F" sync; rc=$?
st=$(GI "$F" status --porcelain)
[ $rc = 0 ] && [ ! -x "$F/docs/plans/run.sh" ] && [ "$st" = " M docs/plans/run.sh" ] &&
  echo "  reproduced: rev 5 sync exits 0, run.sh stays non-executable and private status shows ' M'"
check "rev 5 sync drops the mode change" "$rc $([ -x "$F/docs/plans/run.sh" ] && echo x || echo -) $st" "0 -  M docs/plans/run.sh"
gi "$F" checkout -q -- docs/plans/run.sh   # the repair for a rev 5 machine; P8 installs rev 6 first, so none exist
GI "$B" sync; check "rev 6 sync exits 0" "$?" 0
check "run.sh executable on B" "$([ -x "$B/docs/plans/run.sh" ] && echo x)" x
check "B private status clean" "$(GI "$B" status --porcelain)" ""
chmod -x "$A/docs/plans/run.sh"; GI "$A" add docs/plans/run.sh; GI "$A" commit -m 'run.sh -x'; GI "$A" sync
GI "$B" sync; check "mode removal lands too (not executable, status clean)" "$([ -x "$B/docs/plans/run.sh" ] && echo x)$(GI "$B" status --porcelain)" ""
chmod +x "$B/docs/plans/run.sh"; commit "$A" docs/plans/run.sh 'echo run v2'; GI "$A" sync
GI "$B" sync 2>/dev/null; check "a local mode edit to a path the sync changes is refused (4)" "$?" 4
check "B's local mode and bytes kept" "$([ -x "$B/docs/plans/run.sh" ] && echo x) $(cat "$B/docs/plans/run.sh")" "x echo run"
chmod -x "$B/docs/plans/run.sh"; GI "$B" sync; check "after the owner drops the local mode edit, sync lands v2" "$(cat "$B/docs/plans/run.sh")" "echo run v2"

echo "== round-5 finding 4: platform preflight (Clavain: /bin/bash 3.2, restricted PATH)"
GI "$A" doctor >/dev/null; check "doctor passes here" "$?" 0
mkdir -p "$T/oldgit" "$T/nosha" "$T/shasumonly"
printf '#!/bin/sh\necho "git version 2.37.1"\n' > "$T/oldgit/git"; chmod +x "$T/oldgit/git"
for c in git cat cp chmod dirname basename grep sed cut mkdir rm mv readlink sync; do ln -s "$(command -v $c)" "$T/nosha/$c"; ln -s "$(command -v $c)" "$T/shasumonly/$c"; done
ln -s "$(command -v shasum)" "$T/shasumonly/shasum"
GIT_INTERNAL_PATH=$T/oldgit:/usr/bin:/bin GI "$A" doctor 2>"$T/d1.err"; check "git older than 2.38 fails preflight (9)" "$?" 9
check "the message names the version" "$(grep -c 'older than 2.38' "$T/d1.err")" 1
GIT_INTERNAL_PATH=$T/nosha GI "$A" sync 2>"$T/d2.err"; check "no sha256 tool: every command fails preflight (9) before any write" "$?" 9
check "the message names the missing tool" "$(grep -c 'neither sha256sum nor shasum' "$T/d2.err")" 1
GIT_INTERNAL_PATH=$T/shasumonly GI "$A" install-hooks; check "shasum -a 256 fallback: install-hooks" "$?" 0
(cd / && GIT_INTERNAL_PATH=$T/shasumonly GI "$A" probe >/dev/null); check "shasum -a 256 fallback: probe verifies the record" "$?" 0
echo " static bash 3.2 lint of the helper and hooks"
lint=$(cd "$GI_TREE/scripts" && grep -nE 'mapfile|readarray|declare -A|local -A|\$\{[A-Za-z_]+(,,|\^\^)|\[\[ -v|\|&|&>>|declare -n|local -n' git-internal git-internal-hooks/pre-commit git-internal-hooks/pre-push | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#')
check "no bash 4+ constructs (comments excepted)" "$lint" ""
unguarded=$(cd "$GI_TREE/scripts" && sed -E -e 's/\$\{[A-Za-z_]+\[@\]\+"\$\{[A-Za-z_]+\[@\]\}"\}//g' -e 's/\$\{1\+"\$@"\}//g' git-internal git-internal-hooks/pre-commit git-internal-hooks/pre-push | grep -nE '"\$\{[A-Za-z_]+\[@\]\}"|"\$@"')
check "every array and \"\$@\" expansion guarded for set -u" "$unguarded" ""
lint5=$(cd "$HERE/repro-r5" && grep -cE 'mapfile' pre-commit; sed -E -e 's/\$\{[A-Za-z_]+\[@\]\+"\$\{[A-Za-z_]+\[@\]\}"\}//g' -e 's/\$\{1\+"\$@"\}//g' git-internal | grep -cE '"\$\{[A-Za-z_]+\[@\]\}"|"\$@"')
[ "${lint5%%$'\n'*}" -gt 0 ] && echo "  reproduced: the lint flags the rev 5 pre-commit (mapfile) and rev 5 helper (unguarded expansions)"
check "the lint is live: rev 5 files fail it" "$([ "${lint5%%$'\n'*}" -gt 0 ] && [ "${lint5##*$'\n'}" -gt 0 ] && echo flagged)" flagged

echo "== round-6 finding 1: a symlink (docs/handoffs/latest.md) is recorded as its link text, never its target's bytes"
git init -q --bare "$T/sym.git"
git clone -q "$T/sym.git" "$T/symseed" 2>/dev/null; mkdir -p "$T/symseed/docs/handoffs"
for n in 1 2 3; do printf 'handoff %s\n' "$n" > "$T/symseed/docs/handoffs/h$n.md"; done
ln -s h1.md "$T/symseed/docs/handoffs/latest.md"
git -C "$T/symseed" add -A; git -C "$T/symseed" commit -qm seed; git -C "$T/symseed" push -q origin main
S1="$T/mS1"; S2="$T/mS2"; SX="$T/mSX"; SY="$T/mSY"; SZ="$T/mSZ"
symmachine() { machine "$1"; printf 'docs/handoffs/\n' >> "$1/.gitignore"; git -C "$1" commit -qam 'ignore handoffs'; GI "$1" install "$T/sym.git" "$2"; }
for m in S1 S2 SX SY; do symmachine "${!m}" "m$m"; done
check "install checks the link out as a link" "$(readlink "$SY/docs/handoffs/latest.md") $(cat "$SY/docs/handoffs/latest.md")" "h1.md handoff 1"
relink() { ln -sfn "$3" "$1/$2"; }
lane() { gi "$1" push -q origin "HEAD:refs/heads/autosync/$(cat "$1/.git-internal/info/host")"; }   # push without folding
relink "$S1" docs/handoffs/latest.md h2.md; GI "$S1" add docs/handoffs/latest.md; GI "$S1" commit -m 'latest -> h2'; GI "$S1" sync
relink "$S2" docs/handoffs/latest.md h1.md; relink "$S2" docs/handoffs/latest.md h3.md
GI "$S2" add docs/handoffs/latest.md; GI "$S2" commit -m 'latest -> h3'; lane "$S2"
"$REPRO6" -C "$SX" sync 2>/dev/null; check "rev 6 sync on SX: the two link moves conflict (3)" "$?" 3
GI "$SY" sync 2>/dev/null; check "rev 7 sync on SY: the same conflict (3)" "$?" 3
relink "$SX" docs/handoffs/latest.md h3.md                       # the session chooses mS2's link
"$REPRO6" -C "$SX" resolve origin/autosync/mS2 2>/dev/null; rc=$?
[ $rc = 4 ] && echo "  reproduced: rev 6 cannot resolve to the other side's link: same_blob rejects links, so the chosen link is refused as a local edit (4)"
check "rev 6 resolve refuses another link (4)" "$rc" 4
relink "$SX" docs/handoffs/latest.md h1.md                       # the session keeps the current link
"$REPRO6" -C "$SX" resolve origin/autosync/mS2 2>/dev/null; rc=$?
rec=$(gi "$SX" cat-file -p HEAD:docs/handoffs/latest.md); st=$(gi "$SX" status --porcelain)
[ $rc = 0 ] && [ ! -e "$SX/docs/handoffs/latest.md" ] && [ -z "$st" ] &&
  echo "  reproduced: rev 6 resolve exits 0, records h1.md's bytes as the link text, installs a dangling link, and private status is clean"
check "rev 6 resolve corrupts the current link (rc, disk, recorded text, status)" "$rc $([ -e "$SX/docs/handoffs/latest.md" ] && echo resolves || echo dangling) $rec [$st]" "0 dangling handoff 1 []"
git -C "$T/sym.git" update-ref -d refs/heads/autosync/mSX         # scratch remote: discard the corrupt lane
relink "$SY" docs/handoffs/latest.md h3.md
GI "$SY" resolve origin/autosync/mS2; check "rev 7 resolve exits 0" "$?" 0
check "rev 7 records mode 120000 and the link text" "$(gi "$SY" ls-tree HEAD docs/handoffs/latest.md | cut -c1-6) $(gi "$SY" cat-file -p HEAD:docs/handoffs/latest.md)" "120000 h3.md"
check "the link on disk is intact and resolves" "$(readlink "$SY/docs/handoffs/latest.md") $(cat "$SY/docs/handoffs/latest.md")" "h3.md handoff 3"
check "SY private status clean" "$(GI "$SY" status --porcelain)" ""
symmachine "$SZ" mSZ
for m in S1 S2 SY SZ S1 S2; do GI "${!m}" sync || echo "  sync on $m failed"; done
check "the resolved link reaches S1, S2 and SZ as a link" "$(for m in S1 S2 SZ; do readlink "${!m}/docs/handoffs/latest.md"; done | tr '\n' ' ')" "h3.md h3.md h3.md "
echo " same_blob: an incoming link that already exists on disk"
relink "$S1" docs/handoffs/prev.md h1.md; GI "$S1" add docs/handoffs/prev.md; GI "$S1" commit -m 'prev -> h1'; GI "$S1" sync
for m in SY SZ; do relink "${!m}" docs/handoffs/prev.md h1.md; done      # identical, untracked
relink "$S2" docs/handoffs/prev.md h2.md                                  # different, untracked
"$REPRO6" -C "$SZ" sync 2>/dev/null; rc=$?
[ $rc = 5 ] && echo "  reproduced: rev 6 same_blob rejects every symlink, so an identical link already on disk is a collision (5)"
check "rev 6 sync refuses the identical link" "$rc" 5
GI "$SY" sync; check "rev 7 sync accepts the identical link (0)" "$?" 0
check "SY link kept, status clean" "$(readlink "$SY/docs/handoffs/prev.md") [$(GI "$SY" status --porcelain)]" "h1.md []"
GI "$S2" sync 2>/dev/null; check "rev 7 sync still refuses a different link at the path (5)" "$?" 5
check "S2's own link kept" "$(readlink "$S2/docs/handoffs/prev.md")" h2.md
rm "${S2:?}/docs/handoffs/prev.md"; GI "$S2" sync; check "after the owner removes it, S2 syncs" "$(readlink "$S2/docs/handoffs/prev.md")" h1.md
GI "$SZ" sync; check "SZ under rev 7 accepts the identical link" "$?" 0
echo " a dangling link chosen in a resolution (the target arrives later, or never)"
for m in S1 S2 SY SZ; do GI "${!m}" sync || echo "  sync on $m failed"; done
relink "$S1" docs/handoffs/latest.md h1.md; GI "$S1" add docs/handoffs/latest.md; GI "$S1" commit -m 'latest -> h1'; GI "$S1" sync
relink "$S2" docs/handoffs/latest.md h2.md; GI "$S2" add docs/handoffs/latest.md; GI "$S2" commit -m 'latest -> h2'; lane "$S2"
"$REPRO6" -C "$SZ" sync 2>/dev/null; check "rev 6 sync on SZ conflicts (3)" "$?" 3
GI "$SY" sync 2>/dev/null; check "rev 7 sync on SY conflicts (3)" "$?" 3
relink "$SZ" docs/handoffs/latest.md h4.md; zhead=$(gi "$SZ" rev-parse HEAD)
"$REPRO6" -C "$SZ" resolve origin/autosync/mS2 2>/dev/null; rc=$?
zrec=$(gi "$SZ" ls-tree HEAD docs/handoffs/latest.md | cut -c1-6)
[ $rc != 0 ] && echo "  reproduced: rev 6 resolve takes the dangling link (not -f) for a removal, then refuses it as a local edit ($rc); the chosen link cannot be recorded"
check "rev 6 resolve cannot record a dangling link (rc 4, HEAD unchanged)" "$rc $([ "$(gi "$SZ" rev-parse HEAD)" = "$zhead" ] && echo unchanged)" "4 unchanged"
git -C "$T/sym.git" update-ref -d refs/heads/autosync/mSZ 2>/dev/null
relink "$SY" docs/handoffs/latest.md h4.md
GI "$SY" resolve origin/autosync/mS2; check "rev 7 resolve records the dangling link (0)" "$?" 0
check "recorded as 120000 h4.md; on disk still the dangling link h4.md" "$(gi "$SY" ls-tree HEAD docs/handoffs/latest.md | cut -c1-6) $(gi "$SY" cat-file -p HEAD:docs/handoffs/latest.md) $(readlink "$SY/docs/handoffs/latest.md") $([ -e "$SY/docs/handoffs/latest.md" ] || echo dangling)" "120000 h4.md h4.md dangling"
check "SY private status clean" "$(GI "$SY" status --porcelain)" ""
GI "$S1" sync; check "the dangling link reaches S1 as the same link" "$(readlink "$S1/docs/handoffs/latest.md")" h4.md
echo " the reviewer's case on rev 7: keep the current (resolving) link"
relink "$S1" docs/handoffs/latest.md h1.md; GI "$S1" add docs/handoffs/latest.md; GI "$S1" commit -m 'latest -> h1 again'; GI "$S1" sync
GI "$SY" sync; GI "$S2" sync; check "SY and S2 back on latest -> h1" "$(readlink "$SY/docs/handoffs/latest.md") $(readlink "$S2/docs/handoffs/latest.md")" "h1.md h1.md"
relink "$S1" docs/handoffs/latest.md h2.md; GI "$S1" add docs/handoffs/latest.md; GI "$S1" commit -m 'latest -> h2 again'; lane "$S1"
relink "$S2" docs/handoffs/latest.md h3.md; GI "$S2" add docs/handoffs/latest.md; GI "$S2" commit -m 'latest -> h3 again'; lane "$S2"
GI "$SY" sync 2>/dev/null; check "SY conflicts (3)" "$?" 3
GI "$SY" resolve origin/autosync/mS2; check "rev 7 resolve keeping the current link exits 0" "$?" 0
check "recorded 120000 h1.md; the link resolves; status clean" "$(gi "$SY" ls-tree HEAD docs/handoffs/latest.md | cut -c1-6) $(gi "$SY" cat-file -p HEAD:docs/handoffs/latest.md) $(cat "$SY/docs/handoffs/latest.md") [$(GI "$SY" status --porcelain)]" "120000 h1.md handoff 1 []"

echo "== round-6 finding 3: a failing post-merge importer"
importer() {  # root log rc : a stand-in importer that logs its ORIG_HEAD..HEAD range and exits rc
  printf '#!/bin/sh\necho "$(git rev-parse ORIG_HEAD) $(git rev-parse HEAD)" >> "%s"\nexit %s\n' "$2" "$3" > "$1/.git-internal/hooks/post-merge"
  chmod +x "$1/.git-internal/hooks/post-merge"
}
for m in A B F; do GI "${!m}" sync || echo "  sync on $m failed"; done
importer "$F" "$T/imp.F" 1; : > "$T/imp.F"
commit "$A" docs/plans/imp1.md 'import me'; GI "$A" sync
"$REPRO6" -C "$F" sync 2>/dev/null; rc1=$?
pushed=$([ "$(git -C "$T/int.git" rev-parse autosync/mF)" = "$(gi "$F" rev-parse HEAD)" ] && echo pushed)
"$REPRO6" -C "$F" sync 2>/dev/null; rc2=$?
[ "$rc1 $rc2" = "0 0" ] && [ "$(wc -l < "$T/imp.F" | tr -d ' ')" = 1 ] &&
  echo "  reproduced: rev 6 sync exits 0 and pushes the lane after the importer failed; the next sync exits 0 and never reruns it"
check "rev 6: rc, lane, importer runs, second rc" "$rc1 $pushed $(wc -l < "$T/imp.F" | tr -d ' ') $rc2" "0 pushed 1 0"
rm "${F:?}/.git-internal/hooks/post-merge"
importer "$B" "$T/imp.B" 1; : > "$T/imp.B"
commit "$A" docs/plans/imp2.md 'import me too'; GI "$A" sync
bhead=$(gi "$B" rev-parse HEAD); blane=$(git -C "$T/int.git" rev-parse autosync/mB)
GI "$B" sync 2>"$T/imp.err"; check "rev 7 sync exits 10 when the importer fails" "$?" 10
bnew=$(gi "$B" rev-parse HEAD)
check "HEAD and files moved, lane NOT pushed" "$([ "$bnew" != "$bhead" ] && echo moved) $(cat "$B/docs/plans/imp2.md") $([ "$(git -C "$T/int.git" rev-parse autosync/mB)" = "$blane" ] && echo unpushed)" "moved import me too unpushed"
check "the range is recorded in the intent" "$(cat "$B/.git-internal/git-internal-intent")" "sync $bhead $bnew"
check "the message says the lane was not pushed" "$(grep -c 'lane was NOT pushed' "$T/imp.err")" 1
GI "$B" sync 2>/dev/null; check "the next sync retries first and still exits 10" "$?" 10
check "the importer was rerun over the same range" "$(tail -n 1 "$T/imp.B") $(wc -l < "$T/imp.B" | tr -d ' ')" "$bhead $bnew 2"
check "lane still not pushed" "$(git -C "$T/int.git" rev-parse autosync/mB)" "$blane"
put "$B" docs/plans/b9.md 'later'; GI "$B" add docs/plans/b9.md 2>/dev/null; check "add stops (10) while the import is pending" "$?" 10
rm "${B:?}/docs/plans/b9.md"
GI "$B" commit -m x 2>/dev/null; check "commit stops (10) too" "$?" 10
GI "$B" install-hooks 2>/dev/null; check "install-hooks retries after installing and reports 10" "$?" 10
GI "$B" status --porcelain 2>"$T/imp2.err" >/dev/null; check "status (read-only) runs and warns" "$? $(grep -c 'unfinished sync' "$T/imp2.err")" "0 1"
importer "$B" "$T/imp.B" 0
GI "$B" sync; check "after the importer is fixed, sync exits 0" "$?" 0
check "the retry imported the whole recorded range" "$(tail -n 1 "$T/imp.B")" "$bhead $bnew"
check "intent removed, lane pushed" "$([ -e "$B/.git-internal/git-internal-intent" ] && echo pending) $(git -C "$T/int.git" rev-parse autosync/mB)" " $(gi "$B" rev-parse HEAD)"
rm "${B:?}/.git-internal/hooks/post-merge"
echo " a failing importer after resolve: the recorded conflict is cleared with the move, and the lane is not pushed"
for m in A E G; do GI "${!m}" sync || echo "  sync on $m failed"; done
importer "$G" "$T/imp.G" 1; : > "$T/imp.G"
commit "$A" docs/plans/shared.md 'A4'; lane "$A"; commit "$E" docs/plans/shared.md 'E4'; lane "$E"
GI "$G" sync 2>/dev/null; check "G conflicts (3)" "$?" 3
glane=$(git -C "$T/int.git" rev-parse autosync/mG)
put "$G" docs/plans/shared.md "$(printf 'A4\nE4')"
GI "$G" resolve origin/autosync/mE 2>/dev/null; check "resolve exits 10 when the importer fails" "$?" 10
check "conflict state cleared, resolve intent kept, lane not pushed" "$([ -e "$G/.git-internal/git-internal-conflict" ] && echo state) $(cut -d' ' -f1 "$G/.git-internal/git-internal-intent") $([ "$(git -C "$T/int.git" rev-parse autosync/mG)" = "$glane" ] && echo unpushed)" " resolve unpushed"
rm "${G:?}/.git-internal/hooks/post-merge"
GI "$G" sync; check "with no importer installed, the next sync finishes the resolve and pushes" "$([ -e "$G/.git-internal/git-internal-intent" ] && echo pending) $(git -C "$T/int.git" rev-parse autosync/mG)" " $(gi "$G" rev-parse HEAD)"
echo "== round-8 finding: ORIG_HEAD on the intent path (a stale ORIG_HEAD.lock, an older ORIG_HEAD)"
for m in A B E F; do GI "${!m}" sync || echo "  sync on $m failed"; done
commit "$A" docs/plans/orig.md 'range check'; GI "$A" sync
staleorig() {  # root log lock : an unfinished sync (its importer failed), then an older ORIG_HEAD, and a stale lock if lock=1
  local r=$1
  importer "$r" "$2" 1; GI "$r" sync 2>/dev/null; [ $? = 10 ] || echo "  setup: sync on $r did not stop"
  importer "$r" "$2" 0; : > "$2"
  so_old=$(cut -d' ' -f2 "$r/.git-internal/git-internal-intent"); so_new=$(gi "$r" rev-parse HEAD); so_lane=$(git -C "$T/int.git" rev-parse "autosync/$(cat "$r/.git-internal/info/host")")
  so_older=$(gi "$r" rev-parse "$so_old~1"); gi "$r" update-ref ORIG_HEAD "$so_older"
  [ "$3" = 0 ] || : > "$r/.git-internal/ORIG_HEAD.lock"
}
lanetip() { git -C "$T/int.git" rev-parse "autosync/$(cat "$1/.git-internal/info/host")"; }
staleorig "$F" "$T/orig.F" 1
"$REPRO8" -C "$F" sync 2>/dev/null; rc=$?
[ $rc = 0 ] && [ "$(cat "$T/orig.F")" = "$so_older $so_new" ] && [ "$(lanetip "$F")" = "$so_new" ] &&
  echo "  reproduced: rev 8 recovery exits 0, imports $so_older..HEAD instead of the recorded old, retires the intent and pushes the lane"
check "rev 8: rc, imported range, intent, lane" "$rc $(cat "$T/orig.F") [$([ -e "$F/.git-internal/git-internal-intent" ] && echo pending)] $(lanetip "$F")" "0 $so_older $so_new [] $so_new"
rm -f -- "${F:?}/.git-internal/ORIG_HEAD.lock" "${F:?}/.git-internal/hooks/post-merge"
staleorig "$B" "$T/orig.B" 1
GI "$B" sync 2>"$T/orig.err"; check "rev 8.1: the same state stops (10)" "$?" 10
check "importer not run, intent kept, lane not pushed, ORIG_HEAD untouched" "[$(cat "$T/orig.B")] $(cat "$B/.git-internal/git-internal-intent") $([ "$(lanetip "$B")" = "$so_lane" ] && echo unpushed) $(gi "$B" rev-parse ORIG_HEAD)" "[] sync $so_old $so_new unpushed $so_older"
check "the message names the stale lock" "$(grep -c 'stale .*ORIG_HEAD.lock' "$T/orig.err")" 1
GI "$B" commit -m x 2>/dev/null; check "a writing command stops (10) while the lock stays" "$?" 10
check "still no import, no push" "[$(cat "$T/orig.B")] $([ "$(lanetip "$B")" = "$so_lane" ] && echo unpushed)" "[] unpushed"
rm -f -- "${B:?}/.git-internal/ORIG_HEAD.lock"
GI "$B" sync; check "after the stale lock is removed, sync exits 0" "$?" 0
check "it imported exactly the recorded range, removed the intent and pushed" "$(cat "$T/orig.B") [$([ -e "$B/.git-internal/git-internal-intent" ] && echo pending)] $(lanetip "$B")" "$so_old $so_new [] $(gi "$B" rev-parse HEAD)"
rm -f -- "${B:?}/.git-internal/hooks/post-merge"
staleorig "$E" "$T/orig.E" 0
GI "$E" sync; check "an older ORIG_HEAD without a lock: recovery re-sets it and exits 0" "$?" 0
check "imported the recorded range, intent removed, lane pushed" "$(cat "$T/orig.E") [$([ -e "$E/.git-internal/git-internal-intent" ] && echo pending)] $(lanetip "$E")" "$so_old $so_new [] $(gi "$E" rev-parse HEAD)"
rm -f -- "${E:?}/.git-internal/hooks/post-merge"
echo "== round-9 finding: a corrupted fold ref under an unfinished resolve"
for m in A B F; do GI "${!m}" sync || echo "  sync on $m failed"; done
commit "$A" docs/plans/fold.md 'fold on A'; lane "$A"
foldref() { printf '%s\n' "$1/.git-internal/refs/git-internal/fold"; }
brokenfold() {  # root log : an unfinished resolve (its importer failed), then a corrupted fold ref
  local r=$1
  commit "$r" docs/plans/fold.md "fold on $r"; GI "$r" sync 2>/dev/null; [ $? = 3 ] || echo "  setup: sync on $r did not conflict"
  put "$r" docs/plans/fold.md 'fold resolved'
  importer "$r" "$2" 1; GI "$r" resolve origin/autosync/mA 2>/dev/null; [ $? = 10 ] || echo "  setup: resolve on $r did not stop"
  importer "$r" "$2" 0; : > "$2"
  bf_old=$(cut -d' ' -f2 "$r/.git-internal/git-internal-intent"); bf_new=$(gi "$r" rev-parse HEAD); bf_lane=$(lanetip "$r")
  mkdir -p "$(dirname "$(foldref "$r")")"; printf 'not a ref\n' > "$(foldref "$r")"
}
brokenfold "$F" "$T/fold.F"
"$REPRO81" -C "$F" sync 2>/dev/null; rc=$?
[ -z "$(cat "$T/fold.F")" ] || [ -e "$F/.git-internal/git-internal-intent" ] || [ ! -e "$(foldref "$F")" ] ||
  echo "  reproduced: rev 8.1 recovery treats the broken fold ref as absent: it imports $(cat "$T/fold.F" | cut -c1-12)..., retires the intent while the ref survives, and the sync then exits $rc"
check "rev 8.1: imported range, intent, broken ref present, rc (the fetch stops: 2)" "$(cat "$T/fold.F") [$([ -e "$F/.git-internal/git-internal-intent" ] && echo pending)] $([ -e "$(foldref "$F")" ] && echo ref) $rc" "$bf_old $bf_new [] ref 2"
rm -f -- "$(foldref "${F:?}")" "${F:?}/.git-internal/hooks/post-merge"
brokenfold "$B" "$T/fold.B"
GI "$B" sync 2>"$T/fold.err"; check "rev 8.2: the same state stops (10)" "$?" 10
check "importer not run, intent kept, lane not pushed, the broken ref left in place" "[$(cat "$T/fold.B")] $(cat "$B/.git-internal/git-internal-intent") $([ "$(lanetip "$B")" = "$bf_lane" ] && echo unpushed) $([ -e "$(foldref "$B")" ] && echo ref)" "[] resolve $bf_old $bf_new unpushed ref"
check "git names the broken fold ref" "$(grep -c 'refs/git-internal/fold.*broken' "$T/fold.err")" 1
GI "$B" commit -m x 2>/dev/null; check "a writing command stops (10) while the ref is broken" "$?" 10
check "still no import, no push" "[$(cat "$T/fold.B")] $([ "$(lanetip "$B")" = "$bf_lane" ] && echo unpushed)" "[] unpushed"
rm -f -- "$(foldref "${B:?}")"
GI "$B" sync; check "after the broken ref is removed, sync exits 0" "$?" 0
check "it imported exactly the recorded range, removed the intent and pushed" "$(cat "$T/fold.B") [$([ -e "$B/.git-internal/git-internal-intent" ] && echo pending)] $(lanetip "$B")" "$bf_old $bf_new [] $(gi "$B" rev-parse HEAD)"
rm -f -- "${B:?}/.git-internal/hooks/post-merge"
for m in A B E F G H A B E F G H; do GI "${!m}" sync || echo "  sync on $m failed"; done
check "all lanes converge again" "$(git -C "$T/int.git" for-each-ref --format='%(objectname)' refs/heads/autosync | sort -u | wc -l | tr -d ' ')" 1

echo "== promotion: only mk moves main (stand-in: fast-forward in the scratch bare repo)"
tip=$(git -C "$T/int.git" rev-parse autosync/mB)
git -C "$T/int.git" merge-base --is-ancestor main "$tip" && git -C "$T/int.git" update-ref refs/heads/main "$tip" main
GI "$A" sync; GI "$B" sync
check "A contains promoted main" "$(gi "$A" merge-base --is-ancestor origin/main HEAD; echo $?)" 0
check "B contains promoted main" "$(gi "$B" merge-base --is-ancestor origin/main HEAD; echo $?)" 0

echo "== binding after moving the root (§4.3): probe from an outside cwd"
mv "$A" "$T/mA-moved"; A="$T/mA-moved"
(cd / && GI "$A" probe >/dev/null); check "probe passes at the new root" "$?" 0
check "status clean at the new root" "$(GI "$A" status --porcelain)" ""
commit "$A" docs/plans/a4.md 'after move'; GI "$A" sync; GI "$B" sync
check "sync works after the move" "$(cat "$B/docs/plans/a4.md")" "after move"

echo; echo "expectations failed: $fails"; echo "scratch: $T"
exit $((fails > 0))
