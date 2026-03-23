---
artifact_type: plan
bead: Demarch-enxv
stage: plan
---

# Plan: Publish v1.0 Roadmap Artifact

**Brainstorm:** `docs/brainstorms/2026-03-23-v1-roadmap-parallel-tracks-brainstorm.md`
**PRD:** `docs/prds/2026-03-23-v1-roadmap-milestone-path.md`
**Focus:** F9 (Demarch-c44z) — Write `docs/roadmap-v1.md` with parallel track model

## Context

This plan covers the first deliverable of the Demarch-enxv epic: a canonical roadmap document. The other children (F1-F8) are separate sprints. This session produces the artifact that guides all future v0.7→v1.0 work.

## Steps

### Step 1: Write roadmap document structure
**File:** `docs/roadmap-v1.md`
**Content:**
- Title and version (living document, tracks current state)
- Three track definitions (Autonomy, Safety, Adoption) with 4 levels each
- Version gate table (v0.7 through v1.0)
- Current state assessment with evidence links

### Step 2: Populate current state assessment
For each track×level cell, assess:
- What code exists (link to files/functions from research)
- Whether it's wired into runtime
- Whether it's autonomous
- Gap to next level

Evidence sources:
- Routing: `interverse/interspect/hooks/lib-interspect.sh` (verdict recording, calibration)
- Gates: `core/intercore/cmd/ic/gate.go` (gate evaluation, hardcoded thresholds)
- Phase-cost: `os/Clavain/cmd/clavain-cli/budget.go` (calibration pipeline)
- Self-building: 800+ sessions, $2.93/landable-change

### Step 3: Define exit criteria per milestone
Each version gate gets:
- Concrete, measurable criteria (not aspirational)
- The specific track×level combination required
- A validation method (how do we know the criterion is met?)

### Step 4: Add child bead mapping
Map each child bead to its track×level target:
- Demarch-enxv.2 → A:L1.5→L3 (routing, phase-cost wiring)
- Demarch-0rgc → A:L3 + B:L2 (gate threshold calibration)
- Demarch-py89 → B:L2 (bd doctor auto-run)
- Demarch-enxv.3 → Cross-track validation (deletion-recovery)
- Demarch-c44z → Meta (this deliverable)

### Step 5: Link from AGENTS.md or docs index
Add a reference to the roadmap from the appropriate navigation point.

### Step 6: Commit and close F9 bead
Stage changes, commit with descriptive message, close Demarch-c44z.

## Non-goals
- Writing plans for F1-F8 (separate sprints)
- Implementing any calibration code
- External project selection for C:L2
