#!/usr/bin/env bash
# Beads recovery script: kills zombies, stops orphan monitors, re-inits from JSONL
# Usage: bash .beads/recover.sh
#
# Prefers backup/issues.jsonl over issues.jsonl when it's newer, since
# auto-flush to the main JSONL can stall while bd backup stays current.
set -euo pipefail

echo "=== Beads Recovery ==="

# 1. Kill all idle-monitors across all projects
echo "Killing idle-monitors..."
ps aux | grep "bd dolt idle-monitor" | grep -v grep | awk '{print $2}' | xargs -r kill 2>/dev/null || true

# 2. Kill all dolt sql-servers
echo "Killing dolt servers..."
ps aux | grep "dolt sql-server" | grep -v grep | awk '{print $2}' | xargs -r kill 2>/dev/null || true

# 3. Use bd's built-in killall (v0.58+)
sleep 2
bd dolt killall 2>/dev/null || true

# 4. Try to flush latest state before killing the database
# If the server was still alive enough, this captures recent mutations
bd backup 2>/dev/null && echo "Pre-recovery backup captured" || echo "Pre-recovery backup skipped (server already dead)"

# 5. Pick the freshest JSONL source
MAIN_JSONL=".beads/issues.jsonl"
BACKUP_JSONL=".beads/backup/issues.jsonl"
JSONL=""

if [[ -f "$BACKUP_JSONL" ]] && [[ -f "$MAIN_JSONL" ]]; then
    main_mtime=$(stat -c %Y "$MAIN_JSONL" 2>/dev/null) || main_mtime=0
    backup_mtime=$(stat -c %Y "$BACKUP_JSONL" 2>/dev/null) || backup_mtime=0
    if [[ "$backup_mtime" -gt "$main_mtime" ]]; then
        echo "Using backup/issues.jsonl (newer: $(date -d @$backup_mtime '+%Y-%m-%d %H:%M') vs $(date -d @$main_mtime '+%Y-%m-%d %H:%M'))"
        cp "$BACKUP_JSONL" "$MAIN_JSONL"
        JSONL="$MAIN_JSONL"
    else
        echo "Using issues.jsonl (up to date)"
        JSONL="$MAIN_JSONL"
    fi
elif [[ -f "$BACKUP_JSONL" ]]; then
    echo "Main JSONL missing — using backup/issues.jsonl"
    cp "$BACKUP_JSONL" "$MAIN_JSONL"
    JSONL="$MAIN_JSONL"
elif [[ -f "$MAIN_JSONL" ]]; then
    echo "No backup JSONL — using issues.jsonl"
    JSONL="$MAIN_JSONL"
else
    echo "ERROR: No JSONL found. Cannot recover."
    exit 1
fi

LINES=$(wc -l < "$JSONL")
echo "JSONL has $LINES issues"

# 6. Re-init from JSONL
echo "Re-initializing from JSONL..."
bd dolt stop 2>/dev/null || true
sleep 2
bd init --from-jsonl --force --prefix iv

# 7. Verify
echo ""
echo "=== Verification ==="
bd list 2>&1 | wc -l
echo "issues loaded"
bd dolt status 2>&1
echo ""
echo "Recovery complete."
