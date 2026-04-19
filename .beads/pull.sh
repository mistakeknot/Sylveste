#!/usr/bin/env bash
# Pull per-project beads Dolt DB from the filesystem remote.
# Updated 2026-04-16 for the per-project Dolt layout (migrated 2026-03-15);
# the pre-migration DB path `beads_iv` no longer exists.
set -euo pipefail

DOLT="/home/mk/.local/bin/dolt"
DB_DIR="/home/mk/projects/Sylveste/.beads/dolt/Sylveste"

cd "$DB_DIR"

output=$("$DOLT" pull origin main 2>&1)
status=$?

if [[ "$status" == "0" ]]; then
    echo "beads pull: ok"
    echo "$output" | tail -3
else
    echo "beads pull: failed"
    echo "$output"
    exit 1
fi
