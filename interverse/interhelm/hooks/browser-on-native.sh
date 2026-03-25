#!/usr/bin/env bash
# Hook: Detect browser/screenshot tool usage on native app projects
# Suggests diagnostic CLI instead of visual inspection
set -uo pipefail
trap 'exit 0' ERR

# Q-05: Drain stdin to prevent pipe blockage on large tool responses
cat > /dev/null

# Check if project has a diagnostic server configured
PROJECT_ROOT="${CLAUDE_PROJECT_ROOT:-.}"

# Look for diagnostic server markers in CLAUDE.md
if [[ -f "$PROJECT_ROOT/CLAUDE.md" ]]; then
    if grep -qi "diagnostic server\|/diag/\|diag.*port" "$PROJECT_ROOT/CLAUDE.md" 2>/dev/null; then
        # Check if this is a native app (Tauri, Electron, etc.)
        is_native=false
        [[ -d "$PROJECT_ROOT/src-tauri" ]] && is_native=true
        [[ -f "$PROJECT_ROOT/electron-builder.yml" ]] && is_native=true
        [[ -f "$PROJECT_ROOT/forge.config.js" ]] && is_native=true

        if $is_native; then
            echo "interhelm: This project has a diagnostic server. Consider using the diagnostic CLI instead of screenshots for runtime verification. Run: interhelm:runtime-diagnostics"
        fi
    fi
fi
