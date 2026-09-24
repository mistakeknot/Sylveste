#!/usr/bin/env bash
# OYRF cost-trajectory promotion — copy new measured (source=interstat) rows
# from the oyrf-data branch into main via a PR with auto-merge, so the public
# sylvst.com/live view (which reads main's raw CSV per docs/deploy/sylvst-com.md)
# actually sees rows the ops/oyrf-cost-export timer publishes. Bead
# sylveste-oyrf (promotion follow-up — the exporter writes oyrf-data only,
# and nothing bridged it to main before this).
#
# Exit codes follow ops/rig-self-checks.md — 0 nothing to do or a PR is
# open/pending, 1 something is wrong, 3 could not look (offline, missing gh).
# Never force-pushes, never merges via admin override, never touches
# oyrf-data: `gh pr merge --auto` only flips the auto-merge flag, GitHub
# itself gates the actual merge on the required "Generator and parity
# checkers" check. Fail-open on the automation pause file, like every other
# rig timer.
set -u
[ -f "$HOME/.claude-automations-paused" ] && exit 0
export PATH="$HOME/.local/bin:$HOME/bin:$PATH"

REPO="${OYRF_REPO:-$HOME/projects/Sylveste}"
GH_REPO="${OYRF_GH_REPO:-mistakeknot/Sylveste}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/oyrf-cost-promote"
WORKTREE="$STATE_DIR/promote"
CSV="data/cost-trajectory.csv"
GIT_NAME="${OYRF_GIT_NAME:-oyrf-cost-promote}"
GIT_EMAIL="${OYRF_GIT_EMAIL:-oyrf-cost-promote@$(hostname -s 2>/dev/null || echo rig)}"
PR_TITLE_PREFIX="data: promote OYRF cost trajectory"

mkdir -p "$STATE_DIR"

# One line per run, same shape as oyrf-cost-export's receipt, so a freshness
# check can read it without knowing which timer it is.
receipt() {
  printf '%s exit=%s detail=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "${2:-}" > "$STATE_DIR/last-run"
}
could_not_look() { echo "oyrf-cost-promote: $1" >&2; receipt 3 "$2"; exit 3; }
wrong()          { echo "oyrf-cost-promote: $1" >&2; receipt 1 "$2"; exit 1; }

[ -d "$REPO/.git" ] || [ -f "$REPO/.git" ] || could_not_look "repo not found at $REPO" no-repo
command -v gh >/dev/null 2>&1 || could_not_look "gh CLI not on PATH" no-gh

# A prior run's PR may still be waiting on its check (or on a human, if the
# check failed). Don't pile a second promotion PR on top — that would give
# the reviewer two competing sources of truth for the same rows.
existing="$(gh pr list --repo "$GH_REPO" --state open --search "in:title \"$PR_TITLE_PREFIX\"" --json headRefName --jq '.[0].headRefName' 2>/dev/null)"
if [ -n "$existing" ]; then
  echo "oyrf-cost-promote: PR already open on $existing, nothing to do"
  receipt 0 "pr-pending:$existing"
  exit 0
fi

git -C "$REPO" fetch -q origin main oyrf-data || could_not_look "cannot fetch origin main/oyrf-data (offline?)" offline

# Detached worktree under state, same pattern as oyrf-cost-export, so a run
# cannot disturb whatever a session is doing in the working checkout.
if ! git -C "$WORKTREE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  rm -rf "$WORKTREE"
  git -C "$REPO" worktree prune
  git -C "$REPO" worktree add -q --detach "$WORKTREE" origin/main \
    || wrong "cannot create worktree at $WORKTREE" no-worktree
fi
git -C "$WORKTREE" checkout -q --detach origin/main || wrong "cannot check out origin/main" checkout
git -C "$WORKTREE" reset -q --hard origin/main || wrong "cannot reset to origin/main" reset

data_csv="$(git -C "$REPO" show "origin/oyrf-data:$CSV" 2>/dev/null | tr -d '\r')" \
  || wrong "cannot read origin/oyrf-data:$CSV" no-data-csv

# estimate-costs.sh writes CRLF rows (Python csv default) and both branches'
# CSVs carry it; strip it before comparing/filtering or the last field reads
# "interstat\r" and never matches, or two otherwise-identical rows look
# different. Normalize to LF for the merge, then re-add CRLF on write so the
# file's existing line-ending convention doesn't change.
main_header="$(head -n 1 "$WORKTREE/$CSV" | tr -d '\r')"
main_body="$(tail -n +2 "$WORKTREE/$CSV" | tr -d '\r')"

# Idempotent merge: every row already in main's CSV stays; any source=interstat
# row from oyrf-data whose exact line isn't already present in main is new.
# Exact-line comparison (not just captured_at) so a schema difference shows up
# as "new" instead of being silently treated as a duplicate.
new_rows="$(comm -13 \
  <(printf '%s\n' "$main_body" | sort) \
  <(printf '%s\n' "$data_csv" | tail -n +2 | awk -F',' '$NF == "interstat"' | sort))"

if [ -z "$new_rows" ]; then
  echo "oyrf-cost-promote: no new interstat rows in oyrf-data, nothing to promote"
  receipt 0 no-new-rows
  exit 0
fi

{ printf '%s\n' "$main_body"; printf '%s\n' "$new_rows"; } | sort -t, -k1,1 | sed 's/$/\r/' > "$STATE_DIR/body.csv"
{ printf '%s\r\n' "$main_header"; cat "$STATE_DIR/body.csv"; } > "$WORKTREE/$CSV.new"
mv "$WORKTREE/$CSV.new" "$WORKTREE/$CSV"
rm -f "$STATE_DIR/body.csv"

row_count="$(printf '%s\n' "$new_rows" | grep -c .)"
newest_captured_at="$(printf '%s\n' "$new_rows" | cut -d, -f1 | sort | tail -n1)"
branch="oyrf-promote-$(date -u +%Y%m%d-%H%M%S)"

git -C "$WORKTREE" checkout -q -b "$branch"
git -C "$WORKTREE" add -- "$CSV"
# --no-verify: the repo's pre-commit hook (bd hooks run pre-commit) exports
# and stages .beads/issues.jsonl on every commit, including this one, which
# would drag an unrelated (and sometimes conflicted) beads diff into a PR
# that's meant to be a single CSV row. This commit touches nothing but the
# CSV, so skipping pre-commit here is a scope fix, not a quality bypass.
git -C "$WORKTREE" -c user.name="$GIT_NAME" -c user.email="$GIT_EMAIL" \
  commit -q --no-verify -m "$PR_TITLE_PREFIX: $row_count row(s) through $newest_captured_at" \
  || wrong "commit failed" commit
head_sha="$(git -C "$WORKTREE" rev-parse HEAD)"
git -C "$WORKTREE" push -q origin "HEAD:$branch" || could_not_look "push of $branch failed (offline?)" push

pr_url="$(gh pr create --repo "$GH_REPO" \
  --base main --head "$branch" \
  --title "$PR_TITLE_PREFIX: $row_count row(s) through $newest_captured_at" \
  --body "Automated promotion from \`oyrf-data\` by ops/oyrf-cost-promote. Copies $row_count \`source=interstat\` row(s) (through $newest_captured_at) into main's \`$CSV\` so sylvst.com/live sees them. Auto-merge is enabled; this lands only if \`Generator and parity checkers\` passes. See docs/live/closed-loop.md." \
)" || wrong "gh pr create failed" pr-create

gh pr merge --repo "$GH_REPO" --auto --squash "$pr_url" \
  || wrong "gh pr merge --auto failed for $pr_url (PR is open; no bypass attempted)" auto-merge

# zklw-ci owns the required "Generator and parity checkers" status for this
# repo and only reports on a commit it was asked to run — request it here so
# a daily promotion PR doesn't sit forever waiting for a status nobody
# triggered. Fully-qualified path + 40-hex SHA matches this host's NOPASSWD
# sudoers rule for zklw-ci; anything else would prompt and hang the timer.
ci_job_id=""
if command -v zklw-ci >/dev/null 2>&1; then
  ci_out="$(zklw-ci request --repo "$GH_REPO" --sha "$head_sha" --json 2>&1)"
  ci_rc=$?
  if [ "$ci_rc" -eq 0 ]; then
    ci_job_id="$(printf '%s' "$ci_out" | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
    print(d.get("job_id") or d.get("id") or "")
except Exception:
    print("")' 2>/dev/null)"
    echo "oyrf-cost-promote: requested zklw-ci job ${ci_job_id:-unknown} for $head_sha"
  else
    echo "oyrf-cost-promote: zklw-ci request failed for $head_sha (PR stays open, no bypass): $ci_out" >&2
  fi
else
  echo "oyrf-cost-promote: zklw-ci not on PATH, could not request a run for $head_sha" >&2
fi

echo "oyrf-cost-promote: opened $pr_url with auto-merge enabled ($row_count row(s) through $newest_captured_at)"
receipt 0 "$pr_url ci_job=${ci_job_id:-none} sha=$head_sha"
exit 0
