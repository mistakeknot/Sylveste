#!/usr/bin/env bash
# Generate a unified work-record JSON for a closed bead.
# Bridges beads (what), interstat (cost), and git (artifacts) into one file.
#
# Usage: bash .beads/scripts/work-record.sh <bead_id> [--stdout]
#   --stdout  Print to stdout instead of writing to .beads/records/<bead_id>.json
#
# Requires: jq, bd
# Optional: interstat (cost-query.sh), git
set -euo pipefail

if [[ $# -lt 1 || "$1" == "--help" ]]; then
    echo "Usage: $0 <bead_id> [--stdout]" >&2
    exit 1
fi

BEAD_ID="$1"
shift

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BEADS_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$(dirname "$BEADS_DIR")"
RECORDS_DIR="$BEADS_DIR/records"
COST_QUERY="$PROJECT_DIR/interverse/interstat/scripts/cost-query.sh"

STDOUT_ONLY=false
for arg in "$@"; do
    [[ "$arg" == "--stdout" ]] && STDOUT_ONLY=true
done

mkdir -p "$RECORDS_DIR"

# ---------- Bead metadata ----------
bead_json_raw=$(bd show "$BEAD_ID" --json 2>/dev/null) || bead_json_raw=""
if [[ -z "$bead_json_raw" ]]; then
    echo "Error: bead $BEAD_ID not found" >&2
    exit 1
fi
# bd show --json returns an array; extract first element
bead_json=$(echo "$bead_json_raw" | jq '.[0] // .' 2>/dev/null) || bead_json="$bead_json_raw"

title=$(echo "$bead_json" | jq -r '.title // ""')
status=$(echo "$bead_json" | jq -r '.status // "unknown"')
close_reason=$(echo "$bead_json" | jq -r '.close_reason // ""')
created_at=$(echo "$bead_json" | jq -r '.created_at // ""')
closed_at=$(echo "$bead_json" | jq -r '.closed_at // ""')
issue_type=$(echo "$bead_json" | jq -r '.issue_type // "task"')
priority=$(echo "$bead_json" | jq -r '.priority // 2')

# Compute duration
duration_s=0
if [[ -n "$created_at" && -n "$closed_at" && "$closed_at" != "null" ]]; then
    created_epoch=$(date -d "$created_at" +%s 2>/dev/null) || created_epoch=0
    closed_epoch=$(date -d "$closed_at" +%s 2>/dev/null) || closed_epoch=0
    if [[ "$created_epoch" -gt 0 && "$closed_epoch" -gt 0 ]]; then
        duration_s=$((closed_epoch - created_epoch))
    fi
fi

# Claim info
session_id=$(bd state "$BEAD_ID" claimed_by 2>/dev/null) || session_id=""
[[ "$session_id" == *"no claimed_by"* ]] && session_id=""

# Complexity from state
complexity=$(bd state "$BEAD_ID" complexity 2>/dev/null) || complexity=""
[[ "$complexity" == *"no complexity"* ]] && complexity=""

# Sprint/parent from deps
parent_bead=$(echo "$bead_json" | jq -r '.dependencies[]? | select(.type == "blocks") | .depends_on_id // empty' 2>/dev/null | head -1) || parent_bead=""

# ---------- Cost data from interstat ----------
cost_json='{"total_tokens":0,"input_tokens":0,"output_tokens":0,"usd":0}'
if [[ -f "$COST_QUERY" ]]; then
    by_bead=$(bash "$COST_QUERY" by-bead 2>/dev/null) || by_bead="[]"
    if [[ -n "$by_bead" && "$by_bead" != "[]" ]]; then
        bead_cost=$(echo "$by_bead" | jq --arg id "$BEAD_ID" '[.[] | select(.bead_id == $id)] | .[0] // null' 2>/dev/null) || bead_cost=""
        if [[ -n "$bead_cost" && "$bead_cost" != "null" ]]; then
            tokens=$(echo "$bead_cost" | jq '.tokens // 0')
            input_tokens=$(echo "$bead_cost" | jq '.input_tokens // 0')
            output_tokens=$(echo "$bead_cost" | jq '.output_tokens // 0')
            cost_json=$(jq -n \
                --argjson total "$tokens" \
                --argjson input "$input_tokens" \
                --argjson output "$output_tokens" \
                '{total_tokens: $total, input_tokens: $input, output_tokens: $output, usd: 0}')
        fi
    fi
fi

# ---------- Git artifacts ----------
artifacts='{"commits":[],"files_changed":0,"lines_added":0,"lines_removed":0}'
if command -v git >/dev/null 2>&1; then
    # Find commits referencing this bead ID in message
    commits_json="[]"
    while IFS= read -r sha; do
        [[ -z "$sha" ]] && continue
        commits_json=$(echo "$commits_json" | jq --arg s "$sha" '. + [$s]')
    done < <(git log --all --oneline --grep="$BEAD_ID" --format="%h" 2>/dev/null | head -10)

    commit_count=$(echo "$commits_json" | jq 'length')
    if [[ "$commit_count" -gt 0 ]]; then
        # Get diff stats from first and last commit referencing this bead
        first_sha=$(echo "$commits_json" | jq -r '.[-1]')
        last_sha=$(echo "$commits_json" | jq -r '.[0]')
        diff_stat=$(git diff --shortstat "${first_sha}^..${last_sha}" 2>/dev/null) || diff_stat=""
        files_changed=0; lines_added=0; lines_removed=0
        if [[ -n "$diff_stat" ]]; then
            files_changed=$(echo "$diff_stat" | grep -oP '\d+ file' | grep -oP '\d+' || echo 0)
            lines_added=$(echo "$diff_stat" | grep -oP '\d+ insertion' | grep -oP '\d+' || echo 0)
            lines_removed=$(echo "$diff_stat" | grep -oP '\d+ deletion' | grep -oP '\d+' || echo 0)
        fi
        artifacts=$(jq -n \
            --argjson commits "$commits_json" \
            --argjson fc "${files_changed:-0}" \
            --argjson la "${lines_added:-0}" \
            --argjson lr "${lines_removed:-0}" \
            '{commits: $commits, files_changed: $fc, lines_added: $la, lines_removed: $lr}')
    fi
fi

# ---------- Compose work record ----------
record=$(jq -n \
    --argjson version 1 \
    --arg bead_id "$BEAD_ID" \
    --arg session_id "$session_id" \
    --arg title "$title" \
    --arg timestamp "${closed_at:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}" \
    --argjson duration_s "$duration_s" \
    --arg outcome "$status" \
    --arg close_reason "$close_reason" \
    --arg issue_type "$issue_type" \
    --argjson priority "$priority" \
    --arg parent_bead "$parent_bead" \
    --arg complexity "${complexity:-}" \
    --argjson cost "$cost_json" \
    --argjson artifacts "$artifacts" \
    '{
        version: $version,
        bead_id: $bead_id,
        session_id: $session_id,
        title: $title,
        timestamp: $timestamp,
        duration_s: $duration_s,
        outcome: $outcome,
        close_reason: $close_reason,
        cost: $cost,
        artifacts: $artifacts,
        context: {
            issue_type: $issue_type,
            priority: $priority,
            parent_bead: $parent_bead,
            complexity: (if $complexity == "" then null else ($complexity | tonumber) end)
        }
    }')

if [[ "$STDOUT_ONLY" == true ]]; then
    echo "$record"
else
    echo "$record" > "$RECORDS_DIR/${BEAD_ID}.json"
    size=$(wc -c < "$RECORDS_DIR/${BEAD_ID}.json" | tr -d '[:space:]')
    echo "Work record written to $RECORDS_DIR/${BEAD_ID}.json (${size} bytes)" >&2
fi
