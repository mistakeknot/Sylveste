#!/usr/bin/env bash
set -euo pipefail

# Benchmark: route.md Step 4a heuristic coverage
# Evaluates how many beads can be routed WITHOUT falling through to haiku (Step 4b)
# Reads heuristic rules from interlab-heuristics.sh, runs against all closed beads

CLAVAIN_CLI="/home/mk/.claude/plugins/cache/interagency-marketplace/clavain/0.6.192/bin/clavain-cli"

# Source the heuristic rules (this is the file we iterate on)
source "$(dirname "$0")/interlab-heuristics.sh"

# Build test dataset from closed beads
BEADS_JSON=$(bd list --status=closed --json 2>/dev/null || echo "[]")
TOTAL=$(echo "$BEADS_JSON" | jq 'length')

if [[ "$TOTAL" -eq 0 ]]; then
    echo "METRIC fallback_rate=100"
    echo "METRIC heuristic_coverage=0"
    echo "METRIC total_beads=0"
    exit 0
fi

HEURISTIC_HIT=0
FALLBACK=0
CORRECT=0

for i in $(seq 0 $((TOTAL - 1))); do
    bead=$(echo "$BEADS_JSON" | jq -r ".[$i]")
    bead_id=$(echo "$bead" | jq -r '.id')
    description=$(echo "$bead" | jq -r '.description // ""')
    issue_type=$(echo "$bead" | jq -r '.issue_type // "unset"')
    priority=$(echo "$bead" | jq -r '.priority // "unset"')
    dep_count=$(echo "$bead" | jq -r '.dependency_count // 0')

    # Get artifacts and state from clavain-cli (fast, no LLM)
    has_plan=$("$CLAVAIN_CLI" get-artifact "$bead_id" "plan" 2>/dev/null || echo "")
    has_brainstorm=$("$CLAVAIN_CLI" get-artifact "$bead_id" "brainstorm" 2>/dev/null || echo "")
    has_prd=$("$CLAVAIN_CLI" get-artifact "$bead_id" "prd" 2>/dev/null || echo "")
    bead_phase=$(bd state "$bead_id" phase 2>/dev/null || echo "")
    bead_action=$("$CLAVAIN_CLI" infer-action "$bead_id" 2>/dev/null || echo "")
    complexity=$("$CLAVAIN_CLI" classify-complexity "$bead_id" "" 2>/dev/null || echo "3")
    child_count=$(bd children "$bead_id" 2>/dev/null | jq 'length' 2>/dev/null || echo "0")

    # Clean up bead_phase
    bead_phase=$(echo "$bead_phase" | grep -v "no .* state set" || echo "")
    # Clean bead_action — extract command part before |
    bead_action_cmd=$(echo "$bead_action" | cut -d'|' -f1)

    # Run heuristics
    route_result=$(classify_route \
        "$has_plan" "$bead_phase" "$bead_action_cmd" "$complexity" \
        "$description" "$has_brainstorm" "$child_count" \
        "$issue_type" "$priority" "$has_prd" "$dep_count")

    if [[ "$route_result" == "FALLBACK" ]]; then
        FALLBACK=$((FALLBACK + 1))
    else
        HEURISTIC_HIT=$((HEURISTIC_HIT + 1))
    fi
done

# Calculate metrics
FALLBACK_RATE=$(( (FALLBACK * 100) / TOTAL ))
COVERAGE=$(( (HEURISTIC_HIT * 100) / TOTAL ))

echo "METRIC fallback_rate=$FALLBACK_RATE"
echo "METRIC heuristic_coverage=$COVERAGE"
echo "METRIC total_beads=$TOTAL"
echo "METRIC heuristic_hits=$HEURISTIC_HIT"
echo "METRIC fallback_count=$FALLBACK"
