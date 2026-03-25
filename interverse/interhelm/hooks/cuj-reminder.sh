#!/usr/bin/env bash
# Hook: Remind agents to run CUJ verification after significant changes
# Triggers after git commit (detected via Bash tool running git commit)
# PostToolUse hooks receive JSON on stdin: {"tool_name", "tool_input", "tool_response"}
set -uo pipefail
trap 'exit 0' ERR

# Parse the command from stdin JSON
HOOK_INPUT=$(cat)
PROJECT_ROOT="${CLAUDE_PROJECT_ROOT:-.}"

# UP-03: Check project guard first — skip non-interhelm projects immediately
if [[ ! -f "$PROJECT_ROOT/CLAUDE.md" ]]; then
    exit 0
fi
has_diag=$(grep -qi "diagnostic server\|/diag/" "$PROJECT_ROOT/CLAUDE.md" 2>/dev/null && echo "true" || echo "false")
if [[ "$has_diag" != "true" ]]; then
    exit 0
fi

COMMAND=$(printf '%s' "$HOOK_INPUT" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    inp = d.get('tool_input', {})
    if isinstance(inp, str):
        inp = json.loads(inp)
    print(inp.get('command', ''))
except Exception as e:
    print(str(e), file=sys.stderr)
" 2>/dev/null) || COMMAND=""

# Only trigger on git commit commands
case "$COMMAND" in
    *"git commit"*)
        echo "interhelm: Consider running CUJ verification to confirm runtime behavior after this change. Skill: interhelm:cuj-verification"
        ;;
esac
