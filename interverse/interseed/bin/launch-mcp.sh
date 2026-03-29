#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

export PATH="/usr/bin:$PATH"

if ! command -v uv &>/dev/null; then
    echo "uv not found — install with: curl -LsSf https://astral.sh/uv/install.sh | sh" >&2
    exit 0
fi

exec uv run --directory "$PROJECT_ROOT" interseed-mcp "$@"
