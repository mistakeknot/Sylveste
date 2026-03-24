#!/usr/bin/env bash
# Route heuristics — the file autoresearch iterates on
# Returns: "/sprint confidence" or "/work confidence" or "FALLBACK"
#
# These mirror route.md Step 4a. The goal is to expand coverage
# so fewer beads fall through to the haiku fallback in Step 4b.

classify_route() {
    local has_plan="$1"
    local bead_phase="$2"
    local bead_action="$3"
    local complexity="$4"
    local description="$5"
    local has_brainstorm="$6"
    local child_count="$7"
    local issue_type="${8:-unset}"
    local priority="${9:-unset}"
    local has_prd="${10:-}"
    local dep_count="${11:-0}"

    # Guard: ensure numeric fields have defaults
    [[ "$complexity" =~ ^[0-9]+$ ]] || complexity=3
    [[ "$child_count" =~ ^[0-9]+$ ]] || child_count=0
    [[ "$dep_count" =~ ^[0-9]+$ ]] || dep_count=0

    # --- Current 7 heuristics from route.md Step 4a ---

    # 1. Bead has plan artifact
    if [[ -n "$has_plan" ]]; then
        echo "/work 1.0"
        return
    fi

    # 2. Phase is planned or plan-reviewed
    if [[ "$bead_phase" == "planned" || "$bead_phase" == "plan-reviewed" ]]; then
        echo "/work 1.0"
        return
    fi

    # 3. Action is execute or continue
    if [[ "$bead_action" == "execute" || "$bead_action" == "continue" ]]; then
        echo "/work 1.0"
        return
    fi

    # 4. Complexity = 1 (trivial)
    if [[ "$complexity" == "1" ]]; then
        echo "/work 0.9"
        return
    fi

    # 5. No description AND no brainstorm
    if [[ -z "$description" && -z "$has_brainstorm" ]]; then
        echo "/sprint 0.9"
        return
    fi

    # 6. Complexity = 5 (research)
    if [[ "$complexity" == "5" ]]; then
        echo "/sprint 0.85"
        return
    fi

    # 7. Epic with children
    if [[ "$child_count" -gt 0 ]]; then
        echo "/sprint 0.85"
        return
    fi

    # --- NEW: Type-based heuristics ---

    # 8. Bug type → /work (bugs have clear scope: fix the thing)
    if [[ "$issue_type" == "bug" ]]; then
        echo "/work 0.9"
        return
    fi

    # 9. Type=task + complexity <= 3 → /work (scoped, moderate work)
    if [[ "$issue_type" == "task" && "$complexity" -le 3 ]]; then
        echo "/work 0.85"
        return
    fi

    # 10. Type=decision → /sprint (needs brainstorm/exploration)
    if [[ "$issue_type" == "decision" ]]; then
        echo "/sprint 0.85"
        return
    fi

    # 11. Type=epic without children → /sprint (needs decomposition)
    if [[ "$issue_type" == "epic" && "$child_count" -eq 0 ]]; then
        echo "/sprint 0.85"
        return
    fi

    # --- NEW: Description keyword heuristics ---

    # 12. Description/title contains research indicators → /sprint
    if echo "$description" | grep -qiE '\[research\]|investigate|explore|assess|evaluate'; then
        echo "/sprint 0.85"
        return
    fi

    # 13. Complexity 2 → /work (simple enough for direct execution)
    if [[ "$complexity" == "2" ]]; then
        echo "/work 0.85"
        return
    fi

    # 14. Complexity 4 → /sprint (complex enough to need full lifecycle)
    if [[ "$complexity" == "4" ]]; then
        echo "/sprint 0.85"
        return
    fi

    # 15. Has brainstorm but no plan → /sprint (needs planning)
    if [[ -n "$has_brainstorm" && -z "$has_plan" ]]; then
        echo "/sprint 0.85"
        return
    fi

    # 16. Feature type + complexity 3 → /sprint (moderate features need brainstorm)
    if [[ "$issue_type" == "feature" && "$complexity" == "3" ]]; then
        echo "/sprint 0.85"
        return
    fi

    # --- No heuristic matched ---
    echo "FALLBACK"
}
