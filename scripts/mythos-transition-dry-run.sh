#!/usr/bin/env bash
# Safe Mythos transition before/after dry-run harness.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BEFORE=""
AFTER=""
WINDOW_DAYS="7"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUTPUT_DIR="${TMPDIR:-/tmp}/oyrf-mythos-transition-dry-run-$STAMP"

usage() {
  cat <<'USAGE'
Usage: scripts/mythos-transition-dry-run.sh --before REF --after REF [--output-dir DIR] [--window-days N]

Run a dry-run Mythos transition comparison. The script compares the before and
after labels with deterministic fixture rows from estimate-costs.sh --dry-run;
it does not checkout refs, read private Interstat data, or call the network.

Required:
  --before REF      Baseline ref/mode/workload label.
  --after REF       Candidate Mythos ref/mode/workload label.

Options:
  --output-dir DIR  Directory for generated CSVs and summary markdown.
  --window-days N   Fixture lookback window. Defaults to 7.
  --help            Show this help.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --before=*)
      BEFORE="${1#--before=}"
      ;;
    --before)
      shift
      BEFORE="${1:?--before requires a value}"
      ;;
    --after=*)
      AFTER="${1#--after=}"
      ;;
    --after)
      shift
      AFTER="${1:?--after requires a value}"
      ;;
    --output-dir=*)
      OUTPUT_DIR="${1#--output-dir=}"
      ;;
    --output-dir)
      shift
      OUTPUT_DIR="${1:?--output-dir requires a path}"
      ;;
    --window-days=*)
      WINDOW_DAYS="${1#--window-days=}"
      ;;
    --window-days)
      shift
      WINDOW_DAYS="${1:?--window-days requires an integer}"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [ -z "$BEFORE" ] || [ -z "$AFTER" ]; then
  echo "error: --before and --after are required" >&2
  usage >&2
  exit 2
fi

case "$WINDOW_DAYS" in
  ''|*[!0-9]*)
    echo "error: --window-days must be a non-negative integer" >&2
    exit 2
    ;;
esac

mkdir -p "$OUTPUT_DIR"
BEFORE_CSV="$OUTPUT_DIR/before-cost-trajectory.csv"
AFTER_CSV="$OUTPUT_DIR/after-cost-trajectory.csv"
SUMMARY="$OUTPUT_DIR/mythos-transition-dry-run.md"

bash "$ROOT/estimate-costs.sh" --dry-run --window-days "$WINDOW_DAYS" --output "$BEFORE_CSV" >/dev/null
bash "$ROOT/estimate-costs.sh" --dry-run --window-days "$WINDOW_DAYS" --output "$AFTER_CSV" >/dev/null

python3 - "$BEFORE" "$AFTER" "$BEFORE_CSV" "$AFTER_CSV" "$SUMMARY" <<'PY'
from __future__ import annotations

import csv
import sys
from pathlib import Path

before_label, after_label, before_csv, after_csv, summary_path = sys.argv[1:]

def last_row(path: str) -> dict[str, str]:
    with open(path, newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    if not rows:
        raise SystemExit(f"no rows written to {path}")
    return rows[-1]

before = last_row(before_csv)
after = last_row(after_csv)

summary = f"""# Mythos transition dry-run

Mode: dry-run fixture; no private Interstat data was read.

| Side | Label | Source | Window days | Sessions | Total tokens | Total cost USD | Cost/session USD |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| before | `{before_label}` | {before['source']} | {before['window_days']} | {before['session_count']} | {before['total_tokens']} | {before['total_cost_usd']} | {before['cost_per_session_usd']} |
| after | `{after_label}` | {after['source']} | {after['window_days']} | {after['session_count']} | {after['total_tokens']} | {after['total_cost_usd']} | {after['cost_per_session_usd']} |

Interpretation: this dry-run validates the harness plumbing only. For a real Mythos transition decision, rerun with identical workloads and live Interstat capture as described in `docs/specs/mythos-transition-harness.md`.
"""
Path(summary_path).write_text(summary, encoding="utf-8")
print(summary)
PY

echo "wrote $SUMMARY" >&2
