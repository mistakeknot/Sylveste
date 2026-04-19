#!/usr/bin/env bash
# Push per-project beads Dolt DB to the filesystem remote.
# Updated 2026-04-16 for the per-project Dolt layout (migrated 2026-03-15);
# the pre-migration global DB at ~/.local/share/beads-dolt no longer exists.
set -euo pipefail

DOLT="/home/mk/.local/bin/dolt"
DB_DIR="/home/mk/projects/Sylveste/.beads/dolt/Sylveste"

cd "$DB_DIR"

output=$("$DOLT" push origin main 2>&1)
status=$?

if [[ "$status" == "0" ]]; then
    echo "beads push: ok"
else
    echo "beads push: failed"
    echo "$output"
    exit 1
fi
