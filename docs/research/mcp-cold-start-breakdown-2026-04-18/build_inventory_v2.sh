#!/usr/bin/env bash
set -euo pipefail
CACHE=~/.claude/plugins/cache
SETTINGS=~/.claude/settings.json
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
> "$TMP/records.jsonl"

# Pick best version per plugin based on plugin.json presence OR .mcp.json presence
# For each marketplace::plugin dir, find highest version with any MCP-declaring file
find "$CACHE" -maxdepth 4 -mindepth 3 -type d | while read -r vdir; do
    version=$(basename "$vdir")
    plugin_name=$(basename "$(dirname "$vdir")")
    marketplace=$(basename "$(dirname "$(dirname "$vdir")")")
    # Look for MCP declarations
    pj="$vdir/.claude-plugin/plugin.json"
    mcp_json="$vdir/.mcp.json"
    has_any=""
    [[ -f "$pj" ]] && jq -e '.mcpServers' "$pj" >/dev/null 2>&1 && has_any="plugin_json"
    if [[ -f "$mcp_json" ]]; then
        has_any="${has_any:+${has_any}+}mcp_json"
    fi
    [[ -z "$has_any" ]] && continue
    echo "$version $marketplace $plugin_name $vdir $has_any"
done | sort -V | awk '{ key=$2"::"$3; best[key]=$0 } END { for (k in best) print best[k] }' > "$TMP/best.txt"

while read -r version marketplace plugin_name vdir has_any; do
    pj="$vdir/.claude-plugin/plugin.json"
    mcp_json="$vdir/.mcp.json"

    # Extract from plugin.json
    if [[ "$has_any" == *plugin_json* ]]; then
        jq --arg mk "$marketplace" --arg pl "$plugin_name" --arg ver "$version" --arg src "$pj" -c '
            (.mcpServers // {}) | to_entries[] | {
                marketplace: $mk, plugin: $pl, version: $ver, source: $src,
                server_name: .key,
                type: (.value.type // "stdio"),
                command: (.value.command // null),
                args: (.value.args // []),
                url: (.value.url // null),
                env: (.value.env // {}),
                headers: (.value.headers // {})
            }
        ' "$pj" 2>/dev/null >> "$TMP/records.jsonl" || true
    fi

    # Extract from .mcp.json (may have flat or nested mcpServers)
    if [[ "$has_any" == *mcp_json* ]]; then
        # Detect whether top level is {mcpServers: ...} or just {<name>: ...}
        has_wrapper=$(jq -r 'if .mcpServers then "yes" else "no" end' "$mcp_json" 2>/dev/null)
        expr='(.mcpServers // .)'
        jq --arg mk "$marketplace" --arg pl "$plugin_name" --arg ver "$version" --arg src "$mcp_json" --argjson dummy null -c "
            $expr | to_entries[] | {
                marketplace: \$mk, plugin: \$pl, version: \$ver, source: \$src,
                server_name: .key,
                type: (.value.type // \"stdio\"),
                command: (.value.command // null),
                args: (.value.args // []),
                url: (.value.url // null),
                env: (.value.env // {}),
                headers: (.value.headers // {})
            }
        " "$mcp_json" 2>/dev/null >> "$TMP/records.jsonl" || true
    fi
done < "$TMP/best.txt"

# User scope from ~/.claude/settings.json (may have .mcpServers)
if [[ -f "$SETTINGS" ]]; then
    jq --arg mk "user-scope" --arg src "$SETTINGS" -c '
        (.mcpServers // {}) | to_entries[] | {
            marketplace: $mk, plugin: "user-settings", version: "n/a", source: $src,
            server_name: .key,
            type: (.value.type // "stdio"),
            command: (.value.command // null),
            args: (.value.args // []),
            url: (.value.url // null),
            env: (.value.env // {}),
            headers: (.value.headers // {})
        }
    ' "$SETTINGS" 2>/dev/null >> "$TMP/records.jsonl" || true
fi

jq -s '{servers: .}' "$TMP/records.jsonl"
