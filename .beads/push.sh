#!/usr/bin/env bash
# Push per-project beads Dolt DB to the filesystem remote.
# Updated 2026-04-16 for the per-project Dolt layout (migrated 2026-03-15);
# the pre-migration global DB at ~/.local/share/beads-dolt no longer exists.
#
# 2026-04-19 (sylveste-qdqr): delegates to the bd-push-dolt gate wrapper when
# clavain-cli is installed; falls through to the raw dolt push otherwise, so
# environments without the gate layer keep working unchanged.
set -euo pipefail

DOLT="/home/mk/.local/bin/dolt"
DB_DIR="/home/mk/projects/Sylveste/.beads/dolt/Sylveste"
GATE_SCRIPT="$(dirname "$0")/../os/Clavain/scripts/gates/bd-push-dolt.sh"

if command -v clavain-cli >/dev/null 2>&1 && [[ -x "$GATE_SCRIPT" ]]; then
  exec bash "$GATE_SCRIPT" "$DB_DIR"
fi

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
