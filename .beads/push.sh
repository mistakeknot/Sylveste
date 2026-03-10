#!/usr/bin/env bash
# Push beads dolt database to filesystem remote.
# Workaround for `bd dolt push` "no store available" error (bd v0.56.1).
# Uses dolt sql with --data-dir to target the global beads database.
set -euo pipefail

DOLT="/home/mk/.local/bin/dolt"
DATA_DIR="/home/mk/.local/share/beads-dolt"

output=$("$DOLT" --data-dir "$DATA_DIR" --use-db beads sql -q "CALL dolt_push('origin', 'main')" 2>&1)
status=$(echo "$output" | grep -oP '(?<=\| )\d+(?= +\|)' | head -1)

if [[ "$status" == "0" ]]; then
    echo "beads push: ok"
else
    echo "beads push: failed"
    echo "$output"
    exit 1
fi
