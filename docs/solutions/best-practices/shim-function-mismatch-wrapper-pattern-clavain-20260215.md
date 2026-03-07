---
module: Clavain
date: 2026-02-15
problem_type: best_practice
component: tooling
symptoms:
  - "Command references function that exists in upstream library but is NOT re-exported by shim layer"
  - "Calls to shimmed functions silently fail when upstream adds new functions"
root_cause: missing_workflow_step
resolution_type: code_fix
severity: high
tags: [shim, wrapper, function-delegation, library-abstraction]
lastConfirmed: 2026-02-15
provenance: independent
review_count: 0
---

# Shim Function Mismatch Wrapper Pattern

## Problem

When a command references a function (`enforce_gate`) that exists in the upstream library (interphase lib-gates.sh) but is NOT re-exported by the shim layer (Clavain lib-gates.sh), calls silently fail. The shim only stubs functions it knows about — new upstream functions are invisible.

## Solution

Add a wrapper function in the consuming library that delegates to the upstream function if available, otherwise passes through:

```bash
enforce_gate() {
    if type check_phase_gate &>/dev/null; then
        check_phase_gate "$@"
    else
        return 0  # No gate library — pass through
    fi
}
```

This is preferable to modifying the shim (which would need version sync) or requiring the upstream library directly (which breaks the shim abstraction).

## Evidence

sprint.md referenced `enforce_gate()` which existed in interphase lib-gates.sh (line 214) but was not in Clavain's lib-gates.sh shim (only 7 of ~15 functions re-exported). Architecture review caught this — pre-existing bug propagated into new plan.

## Prevention

For any shim pattern, compare exported function lists between shim and upstream: `grep -oP '^\w+\(\)' shim.sh` vs `grep -oP '^\w+\(\)' upstream.sh`.
