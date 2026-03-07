---
module: Clavain
date: 2026-02-15
problem_type: best_practice
component: cli
symptoms:
  - "Multi-step CLI initialization leaves resource in inconsistent state on partial failure"
  - "|| true error suppression hides individual field write failures"
root_cause: missing_validation
resolution_type: code_fix
severity: high
tags: [cli-init, rollback, partial-failure, error-handling, shell]
lastConfirmed: 2026-02-15
provenance: independent
review_count: 0
---

# Multi-Step CLI Init Rollback

## Problem

When a multi-step CLI initialization (create resource → set field A → set field B → ...) has partial failure, the resource exists but with inconsistent state. Callers assume success, discovery finds the resource, and downstream operations fail on missing fields.

This is especially insidious with `|| true` error suppression — the pattern `bd set-state $id "field=value" 2>/dev/null || true` hides individual failures while the function returns the resource ID as if everything succeeded.

## Solution

1. Check critical field writes and fail early
2. Verify state after writing
3. Cancel/delete the resource on failure

```bash
bd set-state "$id" "phase=brainstorm" 2>/dev/null || {
    bd update "$id" --status=cancelled 2>/dev/null || true
    echo ""; return 0
}
# After all writes, verify critical state
verify=$(bd state "$id" phase 2>/dev/null)
if [[ "$verify" != "brainstorm" ]]; then
    bd update "$id" --status=cancelled 2>/dev/null || true
    echo ""; return 0
fi
```

Reserve `|| true` for non-critical fields only (metadata, history, optional state).

## Evidence

sprint_create() in lib-sprint.sh originally used `|| true` on all 5 set-state calls. Correctness review identified that a mid-sequence failure (FS full, DB locked) leaves a zombie bead with sprint=true but no phase — discoverable but broken.

## Prevention

Grep for `set-state.*|| true` patterns in hooks/*.sh and check if the function returns a resource ID to callers.
