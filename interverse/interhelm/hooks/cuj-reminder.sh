#!/usr/bin/env bash
# Hook: Remind agents to run CUJ verification after significant changes
# Triggers after git commit (detected via Bash tool running git commit)
# PostToolUse hooks receive JSON on stdin: {"tool_name", "tool_input", "tool_response"}
set -euo pipefail

# Parse the command from stdin JSON
HOOK_INPUT=$(cat)
COMMAND=$(echo "$HOOK_INPUT" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    inp = d.get('tool_input', {})
    if isinstance(inp, str):
        inp = json.loads(inp)
    print(inp.get('command', ''))
except: pass
" 2>/dev/null) || COMMAND=""

# Only trigger on git commit commands
case "$COMMAND" in
    *"git commit"*)
        ;;
    *)
        exit 0
        ;;
esac

PROJECT_ROOT="${CLAUDE_PROJECT_ROOT:-.}"

# Check if project has CUJs or diagnostic server
if [[ -f "$PROJECT_ROOT/CLAUDE.md" ]]; then
    has_diag=$(grep -qi "diagnostic server\|/diag/" "$PROJECT_ROOT/CLAUDE.md" 2>/dev/null && echo "true" || echo "false")
    if [[ "$has_diag" == "true" ]]; then
        echo "interhelm: Consider running CUJ verification to confirm runtime behavior after this change. Skill: interhelm:cuj-verification"
    fi
fi
