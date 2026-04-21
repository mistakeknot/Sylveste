#!/usr/bin/env bash
# Push per-project beads Dolt DB to the filesystem remote.
# Updated 2026-04-16 for the per-project Dolt layout (migrated 2026-03-15);
# the pre-migration global DB at ~/.local/share/beads-dolt no longer exists.
#
# 2026-04-19 (sylveste-qdqr): delegates to the bd-push-dolt gate wrapper when
# clavain-cli is installed; falls through to the raw dolt push otherwise, so
# environments without the gate layer keep working unchanged.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_DIR="${BEADS_DOLT_DB:-$SCRIPT_DIR/dolt/Sylveste}"
DOLT="${BEADS_DOLT_BIN:-$(command -v dolt || true)}"
GATE_SCRIPT="$SCRIPT_DIR/../os/Clavain/scripts/gates/bd-push-dolt.sh"

if [[ -z "$DOLT" ]]; then
  echo "beads push: failed — dolt binary not found on PATH (set BEADS_DOLT_BIN to override)" >&2
  exit 1
fi

if [[ ! -d "$DB_DIR" ]]; then
  echo "beads push: failed — DB dir not found: $DB_DIR (set BEADS_DOLT_DB to override)" >&2
  exit 1
fi

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
