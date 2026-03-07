---
module: Clavain
date: 2026-02-12
problem_type: best_practice
component: cli
symptoms:
  - "Shell stat calls with || echo 0 fallback convert errors into epoch 0"
  - "Deleted files appear maximally stale instead of unknown"
root_cause: logic_error
resolution_type: code_fix
severity: medium
tags: [shell, stat, fallback, timestamp, false-positive]
lastConfirmed: 2026-02-12
provenance: independent
review_count: 0
---

# Shell stat Fallback Epoch Zero

## Problem

Shell `stat` calls with `|| echo 0` fallback silently convert errors into epoch 0, which compares as "very old" in any timestamp check. This creates false positives: a file that was deleted between discovery and stat appears maximally stale instead of unknown.

## Solution

Use `|| echo ""` and check for empty string before numeric comparison. Empty = "unknown" (default to safe assumption), 0 = "epoch zero" (false signal).

## Evidence

hooks/lib-discovery.sh staleness check — `stat -c %Y "$plan_path" || echo 0` made deleted files appear stale. Changed to `|| echo ""` with `-n` guard.

## Prevention

Grep for `stat.*|| echo 0` in hooks/*.sh and scripts/*.sh.
