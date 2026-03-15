#!/usr/bin/env bash
# Generate a sprint retrospective markdown report from beads + cost data.
#
# Usage: bash .beads/scripts/sprint-report.sh [--since=YYYY-MM-DD] [--stdout]
#   --since    Start date for the sprint window (default: 7 days ago)
#   --stdout   Print to stdout instead of writing to .beads/reports/
#
# Requires: jq, bd
# Optional: interstat (cost-query.sh)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BEADS_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$(dirname "$BEADS_DIR")"
REPORTS_DIR="$BEADS_DIR/reports"
COST_QUERY="$PROJECT_DIR/interverse/interstat/scripts/cost-query.sh"

STDOUT_ONLY=false
SINCE=""

for arg in "$@"; do
    case "$arg" in
        --stdout) STDOUT_ONLY=true ;;
        --since=*) SINCE="${arg#--since=}" ;;
    esac
done

# Default: 7 days ago
if [[ -z "$SINCE" ]]; then
    SINCE=$(date -u -d '7 days ago' +%Y-%m-%d 2>/dev/null || date -u -v-7d +%Y-%m-%d 2>/dev/null || echo "2026-01-01")
fi

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
WEEK_LABEL=$(date +%Y-W%V 2>/dev/null || echo "unknown")

mkdir -p "$REPORTS_DIR"

# ---------- Collect closed beads in window ----------
closed_json=$(bd list --all --status=closed --closed-after="$SINCE" --json 2>/dev/null) || closed_json="[]"
closed_count=$(echo "$closed_json" | jq 'length' 2>/dev/null) || closed_count=0

if [[ "$closed_count" -eq 0 ]]; then
    report="## Sprint Report: $WEEK_LABEL\n\n**No beads closed since $SINCE.**\n"
    if [[ "$STDOUT_ONLY" == true ]]; then
        echo -e "$report"
    else
        echo -e "$report" > "$REPORTS_DIR/sprint-${WEEK_LABEL}.md"
        echo "Report written to $REPORTS_DIR/sprint-${WEEK_LABEL}.md" >&2
    fi
    exit 0
fi

# ---------- Collect cost data ----------
cost_by_bead=""
total_cost_usd="0"
if [[ -f "$COST_QUERY" ]]; then
    cost_by_bead=$(bash "$COST_QUERY" by-bead 2>/dev/null) || cost_by_bead="[]"
    baseline=$(bash "$COST_QUERY" baseline 2>/dev/null) || baseline=""
    if [[ -n "$baseline" ]]; then
        total_cost_usd=$(echo "$baseline" | jq -r '.cost_usd // 0' 2>/dev/null) || total_cost_usd="0"
    fi
fi

# ---------- Compute stats ----------

# By type breakdown
type_stats=$(echo "$closed_json" | jq -r '
    group_by(.issue_type) |
    map({
        type: .[0].issue_type,
        count: length
    }) |
    sort_by(-.count)' 2>/dev/null) || type_stats="[]"

# Average duration (seconds -> hours)
avg_duration_h=$(echo "$closed_json" | jq '
    [.[] | select(.created_at != null and .closed_at != null) |
        ((.closed_at | fromdateiso8601) - (.created_at | fromdateiso8601))] |
    if length > 0 then (add / length / 3600 * 10 | round / 10) else 0 end
' 2>/dev/null) || avg_duration_h="0"

# Find cost outliers (>2x average cost per bead)
avg_cost=0
outliers="[]"
if [[ -n "$cost_by_bead" && "$cost_by_bead" != "[]" ]]; then
    # Match closed beads to cost data
    closed_ids=$(echo "$closed_json" | jq -r '[.[].id]')
    matched_costs=$(echo "$cost_by_bead" | jq --argjson ids "$closed_ids" '
        [.[] | select(.bead_id as $bid | $ids | index($bid))]
    ' 2>/dev/null) || matched_costs="[]"

    matched_count=$(echo "$matched_costs" | jq 'length' 2>/dev/null) || matched_count=0
    if [[ "$matched_count" -gt 0 ]]; then
        avg_tokens=$(echo "$matched_costs" | jq '[.[].tokens] | add / length' 2>/dev/null) || avg_tokens=0
        if [[ -n "$avg_tokens" && "$avg_tokens" != "0" && "$avg_tokens" != "null" ]]; then
            outliers=$(echo "$matched_costs" | jq --argjson avg "$avg_tokens" '
                [.[] | select(.tokens > ($avg * 2)) | {bead_id, tokens, runs}] | sort_by(-.tokens)
            ' 2>/dev/null) || outliers="[]"
        fi
    fi
fi

# Notable completions (P0 and P1 beads)
notable=$(echo "$closed_json" | jq '[.[] | select(.priority <= 1) | {id, title, priority, close_reason}] | sort_by(.priority)' 2>/dev/null) || notable="[]"

# ---------- Generate markdown ----------
{
    echo "## Sprint Report: $WEEK_LABEL"
    echo ""
    echo "**Closed:** $closed_count beads | **Avg time:** ${avg_duration_h}h | **Since:** $SINCE"
    echo ""

    # By type table
    echo "### By Type"
    echo "| Type | Count |"
    echo "|------|-------|"
    echo "$type_stats" | jq -r '.[] | "| \(.type) | \(.count) |"' 2>/dev/null
    echo ""

    # Notable completions
    notable_count=$(echo "$notable" | jq 'length' 2>/dev/null) || notable_count=0
    if [[ "$notable_count" -gt 0 ]]; then
        echo "### Notable Completions (P0-P1)"
        echo "$notable" | jq -r '.[] | "- **\(.id)**: \(.title)" + (if .close_reason != "" and .close_reason != null then " — \(.close_reason)" else "" end)' 2>/dev/null
        echo ""
    fi

    # Cost outliers
    outlier_count=$(echo "$outliers" | jq 'length' 2>/dev/null) || outlier_count=0
    if [[ "$outlier_count" -gt 0 ]]; then
        echo "### Cost Outliers (>2x avg)"
        echo "$outliers" | jq -r '.[] | "- \(.bead_id): \(.tokens) tokens (\(.runs) runs)"' 2>/dev/null
        echo ""
    fi

    # Recently closed list (last 10)
    echo "### Recent Closures"
    echo "$closed_json" | jq -r '
        sort_by(.closed_at) | reverse | .[:10][] |
        "- \(.id): \(.title) [\(.issue_type), P\(.priority)]"
    ' 2>/dev/null
    echo ""

    echo "_Generated $(date -u +%Y-%m-%dT%H:%M:%SZ) by sprint-report.sh_"
} > /tmp/sprint-report-output.md

if [[ "$STDOUT_ONLY" == true ]]; then
    cat /tmp/sprint-report-output.md
else
    cp /tmp/sprint-report-output.md "$REPORTS_DIR/sprint-${WEEK_LABEL}.md"
    echo "Report written to $REPORTS_DIR/sprint-${WEEK_LABEL}.md ($(wc -c < "$REPORTS_DIR/sprint-${WEEK_LABEL}.md" | tr -d '[:space:]') bytes)" >&2
fi

rm -f /tmp/sprint-report-output.md
