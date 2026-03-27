---
artifact_type: plan
bead: Sylveste-py89
stage: planned
---
# Plan: Auto-run bd doctor on SessionStart, block on corruption

**Bead:** Sylveste-py89
**Roadmap:** v0.7 exit criterion (B:L2 — gates learn)

## Current State

`session-start.sh` already runs `bd doctor --json` with 5-minute TTL (line 134-144). It counts warnings+errors combined and adds a context line. No blocking behavior.

## Gap

1. Doesn't distinguish **errors** (corruption, missing tables) from **warnings** (outdated hooks, uncomitted Dolt changes)
2. Doesn't block sprint execution when errors are found
3. The context line says "run `bd doctor --fix`" but doesn't prevent work on a corrupt database

## Changes

### Task 1: Separate error count from warning count in session-start.sh

**File:** `os/Clavain/hooks/session-start.sh` (line 138)
**Change:** Parse `bd doctor --json` output to extract error count separately:
```bash
_bd_result=$( (bd doctor --json 2>/dev/null || true) )
beads_errors=$(echo "$_bd_result" | jq '[.checks[]? | select(.status == "error")] | length' 2>/dev/null) || beads_errors="0"
beads_warnings=$(echo "$_bd_result" | jq '[.checks[]? | select(.status == "warning")] | length' 2>/dev/null) || beads_warnings="0"
```

Update context message to differentiate:
- Errors → `"beads doctor: N error(s) — DATA CORRUPTION, run bd doctor --fix before starting work"`
- Warnings only → `"beads doctor: N warning(s) — run bd doctor --fix"`

**LOC:** ~10

### Task 2: Write corruption sentinel file

**File:** `os/Clavain/hooks/session-start.sh`
**Change:** When `beads_errors > 0`, write a sentinel file that sprint commands can check:
```bash
if [[ "$beads_errors" -gt 0 ]]; then
    echo "$beads_errors" > /tmp/clavain-bd-corruption-${USER:-mk}
else
    rm -f /tmp/clavain-bd-corruption-${USER:-mk}
fi
```

**LOC:** ~5

### Task 3: Check corruption sentinel in sprint-init

**File:** `os/Clavain/cmd/clavain-cli/main.go` (cmdSprintInit)
**Change:** At the start of `cmdSprintInit`, check for the corruption sentinel:
```go
corruptionFile := fmt.Sprintf("/tmp/clavain-bd-corruption-%s", os.Getenv("USER"))
if data, err := os.ReadFile(corruptionFile); err == nil {
    count := strings.TrimSpace(string(data))
    fmt.Fprintf(os.Stderr, "ERROR: bd doctor found %s error(s) — run 'bd doctor --fix' before sprinting\n", count)
    os.Exit(1)
}
```

**LOC:** ~8

## Checkpoint

Test by creating a corrupt state (rename a Dolt table), verify sprint-init blocks, fix with `bd doctor --fix`, verify sprint-init passes.

## Out of scope

- `bd doctor --deep` (expensive, not for SessionStart)
- Auto-fix (too risky without human review)
- Blocking on warnings (too noisy — outdated hooks, uncommitted Dolt changes are not corruption)
