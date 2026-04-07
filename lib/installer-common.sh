#!/usr/bin/env bash
# installer-common.sh -- Shared color setup and logging functions for install/uninstall scripts
#
# Source from scripts using:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/lib/installer-common.sh"

# --- Colors (TTY-aware) ---
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    DIM='\033[2m'
    RESET='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    BOLD=''
    DIM=''
    RESET=''
fi

# --- Logging ---
log() { printf "%b\n" "$*"; }
success() { printf "${GREEN}  ✓ %s${RESET}\n" "$*"; }
warn() { printf "${YELLOW}  ! %s${RESET}\n" "$*"; }
fail() { printf "${RED}  ✗ %s${RESET}\n" "$*"; }

# --- Command execution (dry-run aware) ---
# Requires DRY_RUN to be set by the sourcing script.
run() {
    if [[ "$DRY_RUN" == true ]]; then
        printf "${DIM}  [DRY RUN] %s${RESET}\n" "$*"
        return 0
    fi
    "$@"
}
