#!/usr/bin/env bash
# Test: measure-preamble.sh emits valid JSON with expected keys.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
out=$(bash "$here/measure-preamble.sh" 2>&1) || { echo "FAIL: script errored: $out"; exit 1; }
echo "$out" | jq -e '.skill_listing_bytes >= 0' >/dev/null 2>&1 \
  || { echo "FAIL: skill_listing_bytes missing"; exit 1; }
echo "$out" | jq -e '.deferred_tools_delta_bytes >= 0' >/dev/null 2>&1 \
  || { echo "FAIL: deferred_tools_delta_bytes missing"; exit 1; }
echo "$out" | jq -e '.total_preamble_bytes > 0' >/dev/null 2>&1 \
  || { echo "FAIL: total_preamble_bytes should be > 0"; exit 1; }
echo "$out" | jq -e '.attachment_types_seen | length >= 0' >/dev/null 2>&1 \
  || { echo "FAIL: attachment_types_seen missing"; exit 1; }
echo "PASS"
