#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: bump-version.sh <version>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"

# Update plugin.json
cd "$ROOT"
python3 -c "
import json, sys
with open('.claude-plugin/plugin.json', 'r+') as f:
    d = json.load(f)
    d['version'] = '$VERSION'
    f.seek(0)
    json.dump(d, f, indent=2)
    f.write('\n')
    f.truncate()
"
echo "Bumped to $VERSION"
