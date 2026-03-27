---
artifact_type: plan
bead: Sylveste-0ztn
stage: planned
---
# Plan: Sprint Flow Improvements (Iteration 1)

**PRD:** docs/prds/2026-03-22-sprint-flow-improvements.md
**Bead:** Sylveste-0ztn
**Scope:** 3 P1 bugs + 2 theme increments (5 features)
**Parallelism:** F1, F2, F3 are independent. F4 depends on F2. F5 is independent.
**Build sequence:** F2 → F3 → F1 → F4 → F5

## Task 1: Fix Step 9 sprint-advance calibration corruption (F2, Sylveste-84sv)

**What:** Step 9's `sprint-advance "shipping"` performs the `shipping → reflect` transition (NOT a duplicate of Step 7's `executing → shipping`). Both pass `"shipping"` as `currentPhase`, causing `recordPhaseTokens` to double-attribute tokens under "shipping". Fix: keep the call but pass the correct phase identifier.

**Context (from plan review):** `cmdSprintAdvance` uses `currentPhase` only for logging and `recordPhaseTokens` — `ic run advance` computes the target independently. Step 7 (line 225) transitions `executing → shipping`; Step 9 (line 245) transitions `shipping → reflect`. Both calls are necessary but should use distinct phase identifiers for calibration.

**Files:**
- `os/Clavain/commands/sprint.md` (line 245)

**Changes:**
1. On line 245, split the compound instruction. Keep the `sprint-advance` call but change arg to `"reflect-entry"` to distinguish from Step 7's call. This gives `recordPhaseTokens` a unique phase key for the shipping→reflect tokens.
2. Update line 245 from:
   `clavain-cli sprint-advance "$CLAVAIN_BEAD_ID" "shipping"` then `/reflect`.
   To:
   ```
   clavain-cli sprint-advance "$CLAVAIN_BEAD_ID" "reflect-entry"
   `/reflect`
   ```
3. Update line 247 to remove "Gate is soft" language (F4 will harden this).

**Verify:** After change, Step 7 records under "shipping", Step 9 records under "reflect-entry" — no double-attribution. `/reflect` Step 1 will see phase=`reflect` (set by ic kernel, not by the string argument).

## Task 2: Mitigate TOCTOU in cmdBeadClaim (F3, Sylveste-r9b5)

**What:** Add best-effort locking to `cmdBeadClaim` to reduce (not eliminate) the race window. The claim system is fundamentally advisory — `bd` CLI calls from shell scripts bypass any Go-side lock, and `bd` has no atomic CAS for labels. Document this limitation explicitly.

**Context (from plan review):** A Go-side lock serializes concurrent `clavain-cli bead-claim` invocations but does NOT cover: (a) direct `bd update` calls from shell scripts, (b) the two-transaction gap in Dolt between read and write. The lock reduces the race window from seconds to milliseconds but cannot eliminate it. Additionally, line 268's `_, _ = runBD(updateArgs...)` discards errors — a failed write is indistinguishable from success.

**Files:**
- `os/Clavain/cmd/clavain-cli/claim.go` (cmdBeadClaim, lines 198-270)
- `os/Clavain/cmd/clavain-cli/claim_test.go` (add tests)

**Changes:**
1. At the start of `cmdBeadClaim`, mirror `cmdSprintClaim`'s two-branch locking pattern: try `runIC("lock", "acquire", "bead-claim", beadID, "--timeout=500ms")` first, fall back to `fallbackLock("bead-claim", beadID)`. Defer the corresponding unlock.
2. Add a comment near `cmdSprintClaim` line 149 noting the nested lock acquisition uses a different namespace (no deadlock risk).
3. Check the error from `runBD(updateArgs...)` on line 268: if it fails, return an error instead of silently succeeding.
4. Add doc comment to `cmdBeadClaim` stating: "Advisory locking — serializes concurrent Go callers but does not cover direct `bd` CLI invocations. The claim system is best-effort; downstream consumers must tolerate stale or contested claims."
5. Fix stale doc comment on line 21: "45-minute threshold" → "10-minute threshold".

**Tests in claim_test.go:**
- `TestBeadClaimLockSerializes`: Acquire fallbackLock, verify second acquisition fails (tests contention, not directory creation).
- `TestBeadClaimLockDifferentNamespace`: Verify `fallbackLock("bead-claim", X)` and `fallbackLock("sprint-claim", X)` don't conflict.

**Lock scope:** Entire `cmdBeadClaim` function body. Nested call from `cmdSprintClaim` (line 149) acquires a separate `"bead-claim"` namespace lock — documented as safe.

## Task 3: Make set-artifact + sprint-advance less fragile (F1, Sylveste-2wzj)

**What:** The "Phase Tracking" section in sprint.md calls `set-artifact` then `sprint-advance` as two separate commands. If advance fails, the artifact is recorded but phase didn't advance. This is actually the correct behavior (artifact should be recorded regardless), but the SKILL.md doesn't explain this and callers may be confused.

**Approach:** Rather than combining into one Go function (which adds complexity for no gain — artifact recording should succeed even if advance fails), improve the SKILL.md documentation and add explicit error reporting.

**Files:**
- `os/Clavain/commands/sprint.md` (Phase Tracking section, lines 115-122)
- `os/Clavain/cmd/clavain-cli/phase.go` (cmdSetArtifact — add stderr logging on success)

**Changes:**
1. Update Phase Tracking section to document that artifact recording is intentionally independent of phase advance. Add: "Artifact is always recorded even if advance fails. This is intentional — artifacts provide audit trail regardless of phase state."
2. Do NOT add success-path stderr logging to `cmdSetArtifact` (plan review: inconsistent with codebase pattern where stderr is for warnings/errors and significant state transitions only, not routine operations). The existing `cxdbRecordArtifact` call provides the audit trail.
3. Update the two-call pattern to handle advance failure gracefully: log warning to stderr but don't halt.

## Task 4: Harden reflect gate (F4, Sylveste-6lpp)

**Depends on:** Task 1 (Step 9 phase fix must land first)

**What:** Change reflect from soft gate to firm gate requiring a minimal artifact, and surface recent reflect learnings at sprint start.

**Files:**
- `os/Clavain/commands/sprint.md` (Step 9, line 247; Environment Bootstrap section)
- `os/Clavain/commands/reflect.md` (add minimum content check)
- `os/Clavain/cmd/clavain-cli/phase.go` (add reflect artifact validation to enforce-gate)

**Changes:**

### 4a: Fix artifact type mismatch + minimum content check in reflect.md
0. **Pre-existing bug fix:** reflect.md Step 4 uses `set-artifact "reflect"` but `knownArtifactTypes` has `"reflection"`. Change Step 4 to use `"reflection"`. Without this fix, the hardened gate will always block (it checks for `"reflection"` in bd state but the artifact was stored as `"artifact_reflect"`).
1. In reflect.md Step 2 (Check existing artifact), add content validation: if existing artifact has < 3 substantive lines, do NOT skip — proceed to Step 3 to capture proper learnings. (Plan review found skip logic would bypass content validation.)
2. In reflect.md Step 3 (Capture learnings), add validation after writing: count non-empty, non-frontmatter lines. Frontmatter boundary: everything between first `---` and second `---` is frontmatter. If body < 3 lines, warn and prompt for more content (advisory, in reflect.md).
3. In reflect.md Step 4 (Register artifact), the `set-artifact` call is the enforcement point. The gate check in sprint.md Step 10 (4b) is the hard enforcement.

### 4b: Harden gate in sprint.md
1. Update Step 9 (line 247) to replace "Gate is soft (warn but allow if no reflect artifact)" with "Gate is firm: Step 10 requires a reflect artifact with >= 3 substantive lines."
2. In Step 10, add a gate check before proceeding:
   ```bash
   reflect_artifact=$(clavain-cli get-artifact "$CLAVAIN_BEAD_ID" "reflection" 2>/dev/null) || reflect_artifact=""
   if [[ -z "$reflect_artifact" ]]; then
       echo "ERROR: Step 10 requires a reflect artifact. Run /reflect first." >&2
       # Stop
   fi
   ```

### 4c: Surface learnings at sprint start
1. In Environment Bootstrap section, after `sprint-init`, add:
   ```bash
   recent_learnings=$(clavain-cli recent-reflect-learnings "$CLAVAIN_BEAD_ID" 3 2>/dev/null) || recent_learnings=""
   if [[ -n "$recent_learnings" ]]; then
       echo "Past learnings that influenced this sprint:"
       echo "$recent_learnings"
   fi
   ```
2. In `stats.go` (NOT phase.go — plan review: phase.go's responsibility is phase transitions, not sibling-bead aggregation), add `cmdRecentReflectLearnings` function:
   - Register in `main.go` dispatch: `case "recent-reflect-learnings": return cmdRecentReflectLearnings(args)`
   - Get parent bead ID: use `bd dep list <bead_id> --json` and find the parent-child dependency. Guard for `(no ... state set)` sentinel from bd state calls using `strings.HasPrefix(out, "(no ")`.
   - List siblings: `bd list --parent=<parent_id> --status=closed`
   - For each sibling (up to N), check `bd state <sibling> artifact_reflection` (note: type is "reflection", stored as bd key "artifact_reflection")
   - Read the reflection file, extract first 3 substantive lines (skip frontmatter block between `---` markers)
   - Output formatted learnings using `printf '%s\n'` pattern in SKILL.md (not bare `echo`) to avoid shell metacharacter issues

## Task 5: Degraded mode definitions (F5, Sylveste-qlnk)

**What:** Define a capability reduction table and update Error Recovery to use degradation instead of halt.

**Files:**
- `os/Clavain/commands/degraded-modes.yaml` (new — in commands/, NOT config/. Plan review: config/ files are Go-loaded via configDirs(); this file is Claude-read reference. Placing in commands/ next to sprint.md signals the correct consumption model.)
- `os/Clavain/commands/sprint.md` (Error Recovery section, lines 284-290)

**Changes:**

### 5a: Create commands/degraded-modes.yaml
```yaml
# Degraded Mode Definitions
# When a subsystem fails, sprint continues at reduced capability instead of halting.
# Each mode defines: trigger, reduced capability, downstream impact.

subsystems:
  review-fleet:
    trigger: "flux-drive agents return errors or timeout"
    degraded: "Sprint continues with self-review only (no multi-agent analysis)"
    flag: "review_degraded"
    impact: "Quality gates run with reduced confidence; sprint summary notes unreviewed status"

  test-suite:
    trigger: "Test command fails with infrastructure error (not test failure)"
    degraded: "Sprint continues; test step marked as skipped with reason"
    flag: "tests_degraded"
    impact: "Quality gates cannot verify correctness; manual testing recommended before ship"

  intercore:
    trigger: "ic commands fail (ECONNREFUSED, timeout, not installed)"
    degraded: "Sprint uses bd-only tracking (no ic runs, budgets, or gates)"
    flag: "intercore_degraded"
    impact: "No budget enforcement, no kernel-level phase tracking"

  routing:
    trigger: "clavain-cli routing commands fail or routing.yaml missing"
    degraded: "Sprint uses default model routing (no agent-specific optimization)"
    flag: "routing_degraded"
    impact: "May use more expensive models than necessary"

  budget:
    trigger: "Token budget exceeded or budget tracking unavailable"
    degraded: "Sprint continues with soft budget warning per step"
    flag: "budget_degraded"
    impact: "No automatic pause on budget exceed; manual cost awareness required"

ladder:
  - level: full
    description: "All subsystems operational"
  - level: reduced
    description: "1-2 non-critical subsystems degraded (routing, budget)"
  - level: critical-only
    description: "Review fleet or test suite degraded; proceed with caution"
  - level: skeleton
    description: "Intercore degraded; bd-only tracking"
  - level: checkpoint-only
    description: "Multiple critical subsystems down; save work and stop"
```

### 5b: Update Error Recovery in sprint.md
Replace lines 284-290 with:
```markdown
## Error Recovery

When a subsystem fails, consult `commands/degraded-modes.yaml` for the appropriate degradation:

1. Identify which subsystem failed (review-fleet, test-suite, intercore, routing, budget)
2. Apply the degraded mode: set the flag, log to stderr, continue at reduced capability
3. If multiple critical subsystems fail (level: checkpoint-only): save all work, commit clean changes, report diagnostic
4. Record degradation events for sprint summary: `clavain-cli set-artifact "$CLAVAIN_BEAD_ID" "degradation" "<subsystem>:<level>"`

To resume: `/clavain:route` (auto-detects active sprint) or `/clavain:sprint --from-step <step>`.
```

## Build Sequence

1. **Task 1** (F2 — Step 9 fix): Edit sprint.md only. No Go changes. ~5 min.
2. **Task 2** (F3 — TOCTOU fix): Edit claim.go + claim_test.go. Compile + test. ~15 min.
3. **Task 3** (F1 — artifact/advance docs): Edit sprint.md + phase.go. Compile. ~10 min.
4. **Task 4** (F4 — reflect hardening): Edit sprint.md + reflect.md + phase.go. Compile + test. ~20 min.
5. **Task 5** (F5 — degraded modes): Create YAML + edit sprint.md. No Go changes. ~10 min.

**Test command:** `cd os/Clavain && go build ./cmd/clavain-cli/ && go test -race ./cmd/clavain-cli/ -count=1`

## Verification

After all tasks:
- [ ] `go build ./cmd/clavain-cli/` succeeds
- [ ] `go test -race ./cmd/clavain-cli/ -count=1` passes (includes race detector)
- [ ] sprint.md Step 9 uses `"reflect-entry"` phase arg (not `"shipping"`)
- [ ] sprint.md Error Recovery references degraded modes
- [ ] sprint.md Phase Tracking documents artifact independence
- [ ] claim.go cmdBeadClaim acquires ic-first lock before read-check-write, with advisory doc comment
- [ ] claim.go line 268 checks bd write error instead of discarding
- [ ] claim.go line 21 doc comment fixed ("10-minute" not "45-minute")
- [ ] commands/degraded-modes.yaml exists with 5 subsystems (NOT in config/)
- [ ] reflect.md uses artifact type `"reflection"` (not `"reflect"`)
- [ ] reflect.md Step 2 validates content on existing artifacts
- [ ] reflect.md has minimum content validation in Step 3
- [ ] stats.go contains cmdRecentReflectLearnings (not phase.go)
- [ ] main.go dispatches `"recent-reflect-learnings"` command
- [ ] `phaseToAction` includes `"reflect"` case (pre-existing gap fix)
