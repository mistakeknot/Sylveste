#!/usr/bin/env bash
# Generate a consolidated <10KB JSON snapshot of Sylveste system state.
# Idempotent, safe for cron or SessionStart hook. Each data source fails
# gracefully — partial output is always valid JSON.
#
# Usage: bash .beads/scripts/snapshot.sh [--stdout]
#   --stdout  Print to stdout instead of writing to .beads/snapshots/latest.json
#
# Requires: jq, bd
# Optional: cass, interstat (cost-query.sh)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BEADS_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$(dirname "$BEADS_DIR")"
SNAPSHOT_DIR="$BEADS_DIR/snapshots"
COST_QUERY="$PROJECT_DIR/interverse/interstat/scripts/cost-query.sh"

STDOUT_ONLY=false
for arg in "$@"; do
    [[ "$arg" == "--stdout" ]] && STDOUT_ONLY=true
done

mkdir -p "$SNAPSHOT_DIR"

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
SEVEN_DAYS_AGO=$(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-7d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")
WEEK_AGO_DATE=$(date -u -d '7 days ago' +%Y-%m-%d 2>/dev/null || date -u -v-7d +%Y-%m-%d 2>/dev/null || echo "")
YESTERDAY_DATE=$(date -u -d '1 day ago' +%Y-%m-%d 2>/dev/null || date -u -v-1d +%Y-%m-%d 2>/dev/null || echo "")

# Temp dir for parallel result collection
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ---------- Launch parallel data collection ----------
# Each collector writes its result to a temp file. Errors produce defaults.

# 1a. Counts: single --all query, group by status in jq
(
    all_json=$(bd list --all --json 2>/dev/null) || all_json="[]"
    echo "$all_json" | jq '{
        total: length,
        open: [.[] | select(.status == "open")] | length,
        in_progress: [.[] | select(.status == "in_progress")] | length,
        closed: [.[] | select(.status == "closed")] | length,
        blocked: [.[] | select(.status == "blocked")] | length
    }' 2>/dev/null > "$TMP/counts.json" || echo '{"total":0,"open":0,"in_progress":0,"closed":0,"blocked":0}' > "$TMP/counts.json"
) &

# 1b. Velocity: closed in 7d and 24h (separate filtered queries are faster than --all + jq filter)
(
    closed_7d=0
    closed_24h=0
    if [[ -n "$WEEK_AGO_DATE" ]]; then
        closed_7d=$(bd list --all --status=closed --closed-after="$WEEK_AGO_DATE" --json 2>/dev/null | jq 'length' 2>/dev/null) || closed_7d=0
    fi
    if [[ -n "$YESTERDAY_DATE" ]]; then
        closed_24h=$(bd list --all --status=closed --closed-after="$YESTERDAY_DATE" --json 2>/dev/null | jq 'length' 2>/dev/null) || closed_24h=0
    fi
    echo "${closed_7d}" > "$TMP/closed_7d"
    echo "${closed_24h}" > "$TMP/closed_24h"
) &

# 2. Active agents (in_progress beads with claim state)
(
    agents="[]"
    if command -v bd >/dev/null 2>&1; then
        ip_json=$(bd list --status=in_progress --json 2>/dev/null) || ip_json="[]"
        ip_count=$(echo "$ip_json" | jq 'length' 2>/dev/null) || ip_count=0
        if [[ "$ip_count" -gt 0 ]]; then
            while IFS= read -r bead_id; do
                title=$(echo "$ip_json" | jq -r --arg id "$bead_id" '.[] | select(.id == $id) | .title // ""' 2>/dev/null)
                session_id=$(bd state "$bead_id" claimed_by 2>/dev/null) || session_id=""
                claimed_at_epoch=$(bd state "$bead_id" claimed_at 2>/dev/null) || claimed_at_epoch=""
                [[ "$session_id" == *"no claimed_by"* ]] && session_id=""
                [[ "$claimed_at_epoch" == *"no claimed_at"* ]] && claimed_at_epoch=""
                claimed_at_iso=""
                if [[ "$claimed_at_epoch" =~ ^[0-9]+$ ]]; then
                    claimed_at_iso=$(date -u -d "@$claimed_at_epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "$claimed_at_epoch")
                fi
                agents=$(echo "$agents" | jq \
                    --arg sid "$session_id" \
                    --arg bid "$bead_id" \
                    --arg cat "$claimed_at_iso" \
                    --arg t "$title" \
                    '. + [{session_id: $sid, bead_id: $bid, claimed_at: $cat, title: $t}]')
            done < <(echo "$ip_json" | jq -r '.[].id' 2>/dev/null)
        fi
    fi
    echo "$agents" > "$TMP/active_agents.json"
) &

# 3. Cost per change + top cost beads (from interstat)
(
    cost_per_change="null"
    top_cost="[]"
    if [[ -f "$COST_QUERY" ]]; then
        baseline_json=$(bash "$COST_QUERY" baseline 2>/dev/null) || baseline_json=""
        if [[ -n "$baseline_json" ]]; then
            cost_per_change=$(echo "$baseline_json" | jq '.north_star.usd_per_landable_change // null' 2>/dev/null) || cost_per_change="null"
        fi
        if [[ -n "$SEVEN_DAYS_AGO" ]]; then
            by_bead_json=$(bash "$COST_QUERY" by-bead --since="$SEVEN_DAYS_AGO" 2>/dev/null) || by_bead_json="[]"
            if [[ -n "$by_bead_json" && "$by_bead_json" != "[]" ]]; then
                top_cost=$(echo "$by_bead_json" | jq '[.[:5] | .[] | {bead_id, tokens, runs}]' 2>/dev/null) || top_cost="[]"
            fi
        fi
    fi
    echo "$cost_per_change" > "$TMP/cost_per_change"
    echo "$top_cost" > "$TMP/top_cost.json"
) &

# 4. Blockers
(
    blockers="[]"
    if command -v bd >/dev/null 2>&1; then
        blocked_json=$(bd list --status=blocked --json 2>/dev/null) || blocked_json="[]"
        blockers=$(echo "$blocked_json" | jq '[.[] | {bead_id: .id, title: .title}]' 2>/dev/null) || blockers="[]"
    fi
    echo "$blockers" > "$TMP/blockers.json"
) &

# 5. Session stats from cass
(
    session_stats="null"
    if command -v cass >/dev/null 2>&1; then
        cass_json=$(cass stats --json 2>/dev/null) || cass_json=""
        if [[ -n "$cass_json" ]]; then
            session_stats=$(echo "$cass_json" | jq '{
                total_conversations: .conversations,
                total_messages: .messages,
                top_agents: [.by_agent[:3][] | {agent, count}]
            }' 2>/dev/null) || session_stats="null"
        fi
    fi
    echo "$session_stats" > "$TMP/session_stats.json"
) &

# ---------- Wait for all collectors ----------
wait

# ---------- Read results ----------
counts=$(cat "$TMP/counts.json" 2>/dev/null) || counts='{"total":0,"open":0,"in_progress":0,"closed":0,"blocked":0}'
closed_7d=$(cat "$TMP/closed_7d" 2>/dev/null | tr -d '[:space:]') || closed_7d=0
closed_24h=$(cat "$TMP/closed_24h" 2>/dev/null | tr -d '[:space:]') || closed_24h=0
cost_per_change=$(cat "$TMP/cost_per_change" 2>/dev/null | tr -d '[:space:]') || cost_per_change="null"
active_agents=$(cat "$TMP/active_agents.json" 2>/dev/null) || active_agents="[]"
blockers=$(cat "$TMP/blockers.json" 2>/dev/null) || blockers="[]"
top_cost=$(cat "$TMP/top_cost.json" 2>/dev/null) || top_cost="[]"
session_stats=$(cat "$TMP/session_stats.json" 2>/dev/null) || session_stats="null"

# Validate numeric values
[[ "$closed_7d" =~ ^[0-9]+$ ]] || closed_7d=0
[[ "$closed_24h" =~ ^[0-9]+$ ]] || closed_24h=0

velocity=$(jq -n \
    --argjson closed_last_7d "$closed_7d" \
    --argjson closed_last_24h "$closed_24h" \
    --argjson cost_per_change_usd "$cost_per_change" \
    '{closed_last_7d: $closed_last_7d, closed_last_24h: $closed_last_24h, cost_per_change_usd: $cost_per_change_usd}')

# ---------- Compose final snapshot ----------
snapshot=$(jq -n \
    --argjson version 1 \
    --arg timestamp "$NOW" \
    --arg generated_by "bd snapshot" \
    --argjson counts "$counts" \
    --argjson velocity "$velocity" \
    --argjson active_agents "$active_agents" \
    --argjson blockers "$blockers" \
    --argjson top_cost_beads_7d "$top_cost" \
    --argjson session_stats "$session_stats" \
    '{
        version: $version,
        timestamp: $timestamp,
        generated_by: $generated_by,
        counts: $counts,
        velocity: $velocity,
        active_agents: $active_agents,
        blockers: $blockers,
        top_cost_beads_7d: $top_cost_beads_7d,
        session_stats: $session_stats
    }')

if [[ "$STDOUT_ONLY" == true ]]; then
    echo "$snapshot"
else
    echo "$snapshot" > "$SNAPSHOT_DIR/latest.json"
    size=$(wc -c < "$SNAPSHOT_DIR/latest.json" | tr -d '[:space:]')
    echo "Snapshot written to $SNAPSHOT_DIR/latest.json (${size} bytes)" >&2
fi
