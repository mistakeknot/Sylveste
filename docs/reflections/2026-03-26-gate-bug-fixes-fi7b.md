---
artifact_type: reflection
bead: Demarch-fi7b
date: 2026-03-26
sprint_outcome: closed-retroactive
---
# Reflection: F1 Gate Bug Fixes (Demarch-fi7b)

## What happened

This bead tracked 4 pre-existing bugs in the gate evaluation system (scanRuns column mismatch, non-tx-scoped BudgetQuerier, non-atomic Rollback, non-atomic cmdGateOverride) plus a documentation fix for override tier recording. All 5 tasks were implemented as part of the gate calibration plan (Demarch-0rgc) in commit `d27b3fc` on 2026-03-24, but the child bead was never closed.

## Sprint discovered this was already done

The sprint's plan review (Step 4) used a codebase exploration agent to validate plan claims against actual source code, which revealed 5/5 tasks fully implemented. Tests confirmed passing. This saved a full execute cycle.

## Lessons

1. **Close child beads when parent work ships.** Batch 1 was a dependency of the calibration plan (Demarch-0rgc). When Batch 1 shipped in the same session as Batches 2-6, only the parent's phase advanced — the child bead was orphaned as open/P0.
2. **Plan review catches stale beads.** The review-before-execute pattern caught that this P0 was actually resolved. Without it, the sprint would have redundantly re-implemented already-shipped code.
3. **Triage should check git history for open beads with code references.** `git log --grep=Demarch-fi7b` would have immediately surfaced commit `d27b3fc`. A bd doctor check for "open beads referenced in commit messages" would catch this class of orphan.
