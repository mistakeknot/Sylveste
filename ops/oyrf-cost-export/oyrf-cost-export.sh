#!/usr/bin/env bash
# OYRF longitudinal cost exporter — runs on the machine that holds interstat.
# Bead sylveste-oyrf. Replaces the six-hourly GitHub Actions job: that job ran
# on a checkout without interverse/ (gitignored, so interstat was never there)
# and published 225 rows to oyrf-data between 2026-04-30 and 2026-09-07, every
# one of them `interstat-empty`. The cadence plan called a streak longer than a
# day an instrumentation fault; nothing was positioned to notice a streak of
# 130.
#
# Exit codes follow ops/rig-self-checks.md — 0 wrote and pushed a measured row,
# 1 something is wrong, 3 could not look. A "could not look" never becomes a
# row: a zero that looks like a measurement is the failure this replaces.
# Fail-open on the automation pause file, like every other rig timer.
set -u
[ -f "$HOME/.claude-automations-paused" ] && exit 0
export PATH="$HOME/.local/bin:$HOME/bin:$PATH"

REPO="${OYRF_REPO:-$HOME/projects/Sylveste}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/oyrf-cost-export"
WORKTREE="$STATE_DIR/oyrf-data"
DATA_BRANCH="${OYRF_DATA_BRANCH:-oyrf-data}"
CSV="data/cost-trajectory.csv"
# Same override estimate-costs.sh honours, so a test can stand in for interstat.
COST_QUERY="${OYRF_COST_QUERY_OVERRIDE:-$REPO/interverse/interstat/scripts/cost-query.sh}"
GIT_NAME="${OYRF_GIT_NAME:-oyrf-cost-export}"
GIT_EMAIL="${OYRF_GIT_EMAIL:-oyrf-cost-export@$(hostname -s 2>/dev/null || echo rig)}"

mkdir -p "$STATE_DIR"

# One line per run: when, exit code, what was (or was not) measured. A
# freshness check can read it; the file is not advanced on a path that wrote
# nothing, so staleness means exactly "no measured row lately".
receipt() {
  printf '%s exit=%s source=%s captured_at=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "${2:-}" "${3:-}" > "$STATE_DIR/last-run"
}
could_not_look() { echo "oyrf-cost-export: $1" >&2; receipt 3 "$2"; exit 3; }
wrong()          { echo "oyrf-cost-export: $1" >&2; receipt 1 "$2"; exit 1; }

[ -d "$REPO/.git" ] || [ -f "$REPO/.git" ] || could_not_look "repo not found at $REPO" no-repo
[ -x "$REPO/estimate-costs.sh" ] || wrong "estimate-costs.sh missing or not executable in $REPO" no-exporter
[ -x "$COST_QUERY" ] || could_not_look \
  "interstat cost query not executable at $COST_QUERY — this host does not hold interstat, nothing to measure" no-interstat

# The data branch lives in its own detached worktree under state, never in the
# working checkout, so a run cannot disturb whatever a session is doing there.
git -C "$REPO" fetch -q origin "$DATA_BRANCH" || could_not_look "cannot fetch origin/$DATA_BRANCH (offline?)" offline
if ! git -C "$WORKTREE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  rm -rf "$WORKTREE"
  git -C "$REPO" worktree prune
  git -C "$REPO" worktree add -q --detach "$WORKTREE" "origin/$DATA_BRANCH" \
    || wrong "cannot create worktree at $WORKTREE" no-worktree
fi

# A sample committed by an earlier run that could not push is retried first;
# it is never discarded by the reset below.
if [ -n "$(git -C "$WORKTREE" log --oneline "origin/$DATA_BRANCH..HEAD" 2>/dev/null)" ]; then
  git -C "$WORKTREE" push -q origin "HEAD:$DATA_BRANCH" \
    || could_not_look "an earlier sample is still unpushed and push failed again (offline?); keeping it" push-pending
fi
git -C "$WORKTREE" checkout -q --detach "origin/$DATA_BRANCH" || wrong "cannot check out origin/$DATA_BRANCH" checkout
mkdir -p "$WORKTREE/data"

if ! out="$(cd "$REPO" && bash estimate-costs.sh --output "$WORKTREE/$CSV" 2>&1)"; then
  git -C "$WORKTREE" checkout -q -- "$CSV" 2>/dev/null
  wrong "estimate-costs.sh failed: ${out##*$'\n'}" exporter-failed
fi

# estimate-costs.sh writes CSV rows with CRLF (Python csv default); strip it
# before parsing, or the last field reads "interstat\r" and nothing matches.
row="$(tail -n 1 "$WORKTREE/$CSV" | tr -d '\r')"
source="${row##*,}"
captured_at="${row%%,*}"
if [ "$source" != "interstat" ]; then
  # Undo the append. The exporter's fallback row is exactly what must never be
  # published from here: it is a shape, not a measurement.
  git -C "$WORKTREE" checkout -q -- "$CSV" 2>/dev/null
  could_not_look "interstat returned nothing usable (exporter row source=$source); no row published. exporter said: ${out##*$'\n'}" "$source"
fi

git -C "$WORKTREE" add -- "$CSV"
git -C "$WORKTREE" -c user.name="$GIT_NAME" -c user.email="$GIT_EMAIL" \
  commit -q -m "data: OYRF cost trajectory sample $captured_at" || wrong "commit failed" commit
git -C "$WORKTREE" push -q origin "HEAD:$DATA_BRANCH" \
  || could_not_look "sample $captured_at committed locally but push failed (offline?); retried next run" push
receipt 0 interstat "$captured_at"
echo "oyrf-cost-export: published sample $captured_at to $DATA_BRANCH"
exit 0
