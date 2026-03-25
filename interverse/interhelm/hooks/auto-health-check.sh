#!/usr/bin/env bash
# Hook: Auto-run health check after Rust/Tauri source file changes
# Advisory only — reports regressions without blocking
# PostToolUse hooks receive JSON on stdin: {"tool_name", "tool_input", "tool_response"}
set -uo pipefail
trap 'exit 0' ERR

# Parse the edited file path from stdin JSON
HOOK_INPUT=$(cat)
FILE_PATH=$(printf '%s' "$HOOK_INPUT" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    inp = d.get('tool_input', {})
    if isinstance(inp, str):
        inp = json.loads(inp)
    print(inp.get('file_path', inp.get('command', '')))
except Exception as e:
    print(str(e), file=sys.stderr)
" 2>/dev/null) || FILE_PATH=""

if [[ -z "$FILE_PATH" ]]; then
    exit 0
fi

# Check if the edited file is a Rust source file
case "$FILE_PATH" in
    *src-tauri/*.rs|*src/*.rs)
        ;;
    *)
        exit 0
        ;;
esac

PROJECT_ROOT="${CLAUDE_PROJECT_ROOT:-.}"

# Check if project has a diagnostic CLI configured
if [[ -f "$PROJECT_ROOT/CLAUDE.md" ]]; then
    diag_cli=$(grep -oP 'CLI:\s*`\K[^`]+' "$PROJECT_ROOT/CLAUDE.md" 2>/dev/null || true)
    # S2: Validate path — must be relative, no traversal, alphanumeric+dash+slash+dot only
    if [[ -n "$diag_cli" && "$diag_cli" != *".."* && "$diag_cli" =~ ^[a-zA-Z0-9_./-]+$ && -x "$PROJECT_ROOT/$diag_cli" ]]; then
        health_output=$("$PROJECT_ROOT/$diag_cli" health 2>/dev/null) || true
        if echo "$health_output" | grep -qi "unhealthy\|degraded\|fail"; then
            echo "interhelm: Health regression detected after editing Rust source. Run '$diag_cli health' for details."
        fi
    fi
fi
