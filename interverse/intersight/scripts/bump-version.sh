#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Delegate to monorepo interbump if available
if [[ -f "$ROOT/../../scripts/interbump.sh" ]]; then
    exec bash "$ROOT/../../scripts/interbump.sh" "$ROOT" "$@"
fi

# Fallback: manual bump
VERSION="${1:?Usage: bump-version.sh <version>}"

# Update plugin.json
PLUGIN_JSON="$ROOT/.claude-plugin/plugin.json"
if command -v jq >/dev/null 2>&1; then
    tmp=$(mktemp)
    jq --arg v "$VERSION" '.version = $v' "$PLUGIN_JSON" > "$tmp" && mv "$tmp" "$PLUGIN_JSON"
else
    sed -i "s/\"version\": \"[^\"]*\"/\"version\": \"$VERSION\"/" "$PLUGIN_JSON"
fi

echo "intersight bumped to $VERSION"
