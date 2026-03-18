#!/usr/bin/env bash
set -euo pipefail
# masaq/interlab.sh — wraps masaq Go benchmarks for interlab consumption.
# Primary metric: priompt_render_ns (BenchmarkRender100)
# Secondary: diff_lcs_ns, compact_format_ns, allocs, bytes

HARNESS="${INTERLAB_HARNESS:-$(git rev-parse --show-toplevel)/interverse/interlab/scripts/go-bench-harness.sh}"
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "--- priompt ---" >&2
bash "$HARNESS" --pkg ./priompt/ --bench 'BenchmarkRender100$' --metric priompt_render_ns --dir "$DIR"

echo "--- diff ---" >&2
bash "$HARNESS" --pkg ./diff/ --bench 'BenchmarkLCS500Lines5Pct$' --metric diff_lcs_ns --dir "$DIR"

echo "--- compact ---" >&2
bash "$HARNESS" --pkg ./compact/ --bench 'BenchmarkFormatToolCallCompact$' --metric compact_format_ns --dir "$DIR"
