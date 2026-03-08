#!/usr/bin/env bash
# Close beads and immediately sync to prevent data loss on Dolt crashes.
# Usage: bash .beads/close-and-sync.sh <bead-id> [<bead-id> ...] [--reason="..."]
#
# Replaces the pattern: bd close <id> && bash .beads/push.sh
# Adds bd backup between close and push so recovery always has fresh state.
set -euo pipefail

if [[ $# -eq 0 ]]; then
    echo "Usage: bash .beads/close-and-sync.sh <bead-id> [<bead-id> ...] [--reason=\"...\"]"
    exit 1
fi

# Close all specified beads (bd close handles multiple IDs and --reason)
bd close "$@"

# Backup to JSONL immediately — this is what recover.sh reads
bd backup 2>/dev/null && echo "beads backup: ok" || echo "beads backup: skipped"

# Push to Dolt remote
bash "$(dirname "$0")/push.sh"
