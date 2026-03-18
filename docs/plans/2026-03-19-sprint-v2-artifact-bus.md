---
artifact_type: plan
bead: Demarch-lta9
stage: plan
source: docs/prds/2026-03-19-sprint-v2-lifecycle-redesign.md
---

# Plan: Sprint v2 — Artifact Bus + Progress Trackers

## Context

`set-artifact` and `get-artifact` already exist in `clavain-cli` (phase.go:301-369) but depend on `resolveRunID()` → `ic_run_id` in bead state. Without an active Intercore run (common for standalone sprints), both commands silently fail. The fix is a `bd set-state` fallback path so artifacts work with or without interserve.

## Scope

This plan covers F1 (make artifact bus reliable) and F3 (progress tracker rollout). F2 (wiring into commands) is deferred until F1 is proven — we'll start with strategy.md as the pilot command.

## Tasks

### Task 1: Add bd-fallback to set-artifact (phase.go)

**File:** `os/Clavain/cmd/clavain-cli/phase.go` (cmdSetArtifact, lines 301-337)

**Change:** After the ic artifact add call (or if resolveRunID fails), also write artifact to bead state:
```go
// Always store in bd state as fallback (even if ic succeeds)
runBD("set-state", beadID, "artifact_"+artifactType+"="+artifactPath)
```

This ensures artifacts are queryable via `bd state <bead> artifact_<type>` even without interserve.

**Test:** `clavain-cli set-artifact <test-bead> plan test.md` succeeds without ic_run_id set.

### Task 2: Add bd-fallback to get-artifact (phase.go)

**File:** `os/Clavain/cmd/clavain-cli/phase.go` (cmdGetArtifact, lines 341-369)

**Change:** Try ic first (existing path). If ic fails or returns empty, fall back to bd state:
```go
// Fallback: read from bd state
out, err := runBD("state", beadID, "artifact_"+artifactType)
if err == nil && len(bytes.TrimSpace(out)) > 0 {
    fmt.Println(strings.TrimSpace(string(out)))
    return nil
}
```

**Test:** `clavain-cli get-artifact <test-bead> plan` returns path set by Task 1.

### Task 3: Add get-artifact to help text (main.go)

**File:** `os/Clavain/cmd/clavain-cli/main.go` (help section ~line 227)

**Change:** Add `get-artifact` to the Sprint State help section alongside `set-artifact`.

### Task 4: Add type validation to set-artifact

**File:** `os/Clavain/cmd/clavain-cli/phase.go`

**Change:** Add a known-types list and validate before storing:
```go
var knownArtifactTypes = map[string]bool{
    "brainstorm": true, "prd": true, "plan": true,
    "plan-review": true, "implementation": true,
    "quality-verdict": true, "resolution": true,
    "reflection": true, "landed": true, "closed": true,
}
```

Warn (not error) on unknown type — allow future extensibility.

### Task 5: Pilot — wire artifact bus into strategy.md

**File:** `os/Clavain/commands/strategy.md`

**Change at input:** Replace `ls -t docs/brainstorms/*.md | head -1` with:
```bash
brainstorm_doc=$(clavain-cli get-artifact "$CLAVAIN_BEAD_ID" "brainstorm" 2>/dev/null)
if [[ -z "$brainstorm_doc" ]]; then
    brainstorm_doc=$(ls -t docs/brainstorms/*.md 2>/dev/null | head -1)
fi
```

**Change at output:** After writing PRD, add:
```bash
clavain-cli set-artifact "$CLAVAIN_BEAD_ID" "prd" "<prd_path>"
```

### Task 6: Add progress tracker to strategy.md

**File:** `os/Clavain/commands/strategy.md`

**Change:** Add `## Progress Tracking` section with canonical phase checklist matching brainstorm.md pattern. Add behavioral rule capping phase count. Add `(Terminal)` to final phase. Add hard-stop after output summary.

### Task 7: Build and smoke test

```bash
cd os/Clavain/cmd/clavain-cli && go build -o clavain-cli .
# Create test bead, set/get artifact, verify fallback works without ic
```

## Execution Order

Tasks 1-4 are sequential (Go changes, build once). Task 5-6 are independent (command file edits). Task 7 validates everything.

## Risk

- `bd set-state` uses `key=value` format — artifact paths with `=` in them would break. Mitigate: URL-encode or use a different separator. Low risk since our paths don't contain `=`.
- Dual-write (ic + bd) means artifacts are stored in two places. Mitigate: get-artifact tries ic first, bd second. Consistent.
