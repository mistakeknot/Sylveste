---
artifact_type: plan
bead: Demarch-uboy.6
stage: planned
---
# Plan: Validate Incremental Expansion (Step 2.2a.6)

**Bead:** Demarch-uboy.6
**Goal:** Confirm that flux-drive's speculative Stage 2 launch logic (Step 2.2a.6 in launch.md) works during a real review run.

## Acceptance Criteria (from bead)

1. Speculative launches fire (at least 1 agent launched speculatively during Stage 1)
2. Speculative launches don't count against the slot ceiling
3. Triage report marks speculative agents correctly: `[speculative -- launched after {agent} completed]`

## Task 1: Add incremental_expansion config to budget.yaml

**File:** `interverse/interflux/config/flux-drive/budget.yaml`
**Change:** Add `incremental_expansion` section:
```yaml
# Incremental expansion — speculative Stage 2 launch (Step 2.2a.6)
incremental_expansion:
  enabled: true
  max_speculative: 2         # max agents launched speculatively during Stage 1
```
**Why:** launch.md's skip condition checks `budget.yaml -> incremental_expansion.enabled is false`. Without this key, the agent has no explicit signal to follow the step.

## Task 2: Run flux-drive on a real 400+ line doc

**Target:** `docs/plans/2026-03-09-interhelm.md` (2111 lines)
**Command:** `/interflux:flux-drive docs/plans/2026-03-09-interhelm.md`
**Expected:** 6+ agents selected -> Stage 1/2 split -> incremental expansion has a chance to fire.

## Task 3: Verify the three acceptance criteria

After the flux-drive run completes:

### 3a: Check for speculative launches
- Search flux-drive output directory for log pattern: `[speculative Stage 2]`
- If not present: check if Stage 1 produced P0/P1 findings (they may not have, which means expansion_score < 3 and speculative launches correctly didn't fire — this is still a valid result if expansion decision logic ran)

### 3b: Verify ceiling independence
- From triage report: count total agents dispatched vs the calculated ceiling
- Speculative agents should be additive (ceiling + speculative <= ceiling + max_speculative)

### 3c: Verify triage report markers
- Check triage-table.md for `[speculative]` marker on any agents
- If no speculative launches occurred: verify the triage report correctly shows only Stage 1 and Stage 2 agents (no false speculative markers)

## Task 4: Document findings

If speculative launches fired: record verification as passing.
If they didn't fire (due to no P0/P1 findings in adjacent domains): document WHY they didn't fire and whether the logic was correctly evaluated. This is still a valid outcome — it means the skip conditions worked. Consider a follow-up bead to construct a scenario that guarantees speculative triggers.

## Build Sequence

Task 1 -> Task 2 -> Task 3 -> Task 4 (strictly sequential)
