---
module: Clavain
date: 2026-02-12
problem_type: best_practice
component: cli
symptoms:
  - "Shell scripts using pipe-delimited output are vulnerable to field injection"
  - "Titles, descriptions, and file paths commonly contain the | delimiter character"
root_cause: missing_validation
resolution_type: code_fix
severity: high
tags: [shell, injection, pipe-delimited, json, security]
lastConfirmed: 2026-02-12
provenance: independent
review_count: 0
---

# Shell Pipe-Delimited Format Injection

## Problem

Shell scripts using pipe-delimited output (e.g., `title|action|path`) are vulnerable to field injection when any field contains the delimiter character. Titles, user descriptions, and file paths commonly contain `|`.

## Solution

Use JSON output with `jq --arg` for safe field construction instead of pipe/tab-delimited text formats. The `jq -n -c --arg key "$value"` pattern prevents injection from any user-controlled data.

## Evidence

hooks/lib-discovery.sh — originally designed with pipe-delimited output, changed to JSON before implementation after fd-correctness plan review caught the risk.

## Prevention

Grep for `IFS='|'` or `cut -d'|'` in hooks/*.sh and scripts/*.sh.
