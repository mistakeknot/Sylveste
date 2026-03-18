---
artifact_type: prd
bead: Demarch-lta9
stage: strategize
source: docs/brainstorms/2026-03-19-sprint-v2-lifecycle-redesign-brainstorm.md
---

# PRD: Sprint v2 Lifecycle Redesign

## Problem Statement

The 10-step sprint lifecycle has brittle inter-step handoffs (scored 3/10), inconsistent progress tracking (2/9 commands have templates), and no formal autonomy model. Steps discover inputs via `ls -t | head -1` or manual argument passing, causing misrouted artifacts, phantom phases, and inability to run unattended.

## Success Criteria

- All 10 steps read inputs via `clavain-cli get-artifact`, not file discovery
- All commands have canonical progress trackers with hard-stop rules
- C1-C2 sprints complete start-to-finish without AskUserQuestion (except quality-gate failures)
- Parallel execution windows (execute+QG, resolve+reflect) are supported by artifact contracts

## Features

### F1: Artifact Bus CLI Commands

**What:** Add `set-artifact` and `get-artifact` subcommands to `clavain-cli`. Each stores/retrieves a typed artifact path for a bead ID.

**Scope:**
- `clavain-cli set-artifact <bead> <type> <path>` — writes to bead state (Dolt)
- `clavain-cli get-artifact <bead> <type>` — reads from bead state, prints path to stdout
- Types: brainstorm, prd, plan, plan-review, implementation, quality-verdict, resolution, reflection, landed, closed
- Overwrite semantics (no versioning for v2)

**Acceptance criteria:**
- Both commands work with per-project Dolt
- `get-artifact` returns empty string + exit 1 if artifact not set
- `set-artifact` validates type against known list

### F2: Wire Artifact Bus Into All 10 Commands

**What:** Update each sprint command to produce its artifact via `set-artifact` and consume its input via `get-artifact`.

**Scope (per command):**
- brainstorm.md: already calls `set-artifact` (via advance-phase); add explicit `set-artifact brainstorm`
- strategy.md: replace `ls -t docs/brainstorms/ | head -1` with `get-artifact $BEAD brainstorm`; produce `set-artifact $BEAD prd`
- write-plan.md: read PRD via `get-artifact $BEAD prd`; produce `set-artifact $BEAD plan`
- sprint.md Step 4: read plan via `get-artifact $BEAD plan` instead of manual path; produce `set-artifact $BEAD plan-review`
- work.md: read plan via `get-artifact $BEAD plan`; produce `set-artifact $BEAD implementation` (SHA range)
- quality-gates.md: read implementation via `get-artifact $BEAD implementation`; produce `set-artifact $BEAD quality-verdict`
- resolve.md: read quality-verdict via `get-artifact $BEAD quality-verdict`; produce `set-artifact $BEAD resolution`
- reflect.md: read quality-verdict + resolution; produce `set-artifact $BEAD reflection`
- land.md: read implementation; produce `set-artifact $BEAD landed`
- sprint.md Step 10: produce `set-artifact $BEAD closed`

**Acceptance criteria:**
- No command uses `ls -t` or manual path passing for sprint inputs
- Sprint.md no longer needs "remember path for Step 4" — artifact bus handles it

### F3: Progress Tracker Rollout

**What:** Add canonical phase checklists and hard-stop rules to all commands that lack them.

**Scope:** strategy.md, write-plan.md, quality-gates.md, resolve.md, reflect.md, land.md (6 commands). Brainstorm.md already done. Work.md uses TodoWrite (different pattern, acceptable).

**Per command:**
1. `## Progress Tracking` section with exact phase checklist
2. Behavioral rule: "Exactly N phases. Do NOT invent, rename, or append phases."
3. `checkpoint-write` call at terminal phase
4. `(Terminal)` annotation on final phase heading
5. Hard stop after output summary

**Acceptance criteria:**
- All 6 commands pass manual inspection for progress template, hard-stop, checkpoint-write
- sprint.md itself gets a 10-step progress template

### F4: Autonomy Tier System

**What:** Add graduated autonomy that determines which AskUserQuestion checkpoints are active based on complexity.

**Scope:**
- Tier 1 (C1-C2): All AskUserQuestion calls in brainstorm/strategy/plan-review are suppressed; quality-gate FAIL is the only pause
- Tier 2 (C3): Plan-review checkpoint active; all others suppressed
- Tier 3 (C4-C5): All checkpoints active (current behavior)
- Override: `--autonomy=<1|2|3>` or `bd set-state <bead> manual_pause true`

**Implementation:** Each command checks `autonomy_tier` (from complexity or override) before calling AskUserQuestion. If tier allows auto-advance, use the recommended option.

**Acceptance criteria:**
- C1 bead completes sprint without any AskUserQuestion calls (except gate failure)
- User can force interactive mode via `--autonomy=3` regardless of complexity

### F5: Sprint Progress Display

**What:** Sprint.md gets its own 10-step progress template that updates after each step.

**Scope:**
```
Sprint Progress (Demarch-xxxx):
- [x] Step 1: Brainstorm ✓ docs/brainstorms/...
- [x] Step 2: Strategy ✓ docs/prds/...
- [ ] Step 3: Write Plan
- [ ] Step 4: Plan Review
- [ ] Step 5: Execute
- [ ] Step 6: Test
- [ ] Step 7: Quality Gates
- [ ] Step 8: Resolve
- [ ] Step 9: Reflect
- [ ] Step 10: Ship
```

**Acceptance criteria:**
- Progress display updates after each step completion
- Artifact path shown next to completed steps
- Display is in sprint.md, not in sub-commands

### F6: Multi-Agent Parallel Windows

**What:** Design artifact contracts to support two parallel execution windows.

**Scope:**
- Window 1: Execute (Step 5) + Quality Gates prep — QG pre-stages agent roster from plan while execute runs
- Window 2: Resolve (Step 7) + Reflect (Step 8) — both write different artifact types, sprint waits for both
- Contract: no two agents write same artifact type for same bead

**Acceptance criteria:**
- Artifact types for parallel steps are distinct (implementation vs quality-verdict, resolution vs reflection)
- Sprint.md documents parallel dispatch pattern using Task tool
- Join point: sprint.md checks both artifacts exist before advancing past parallel window

## Non-Goals

- Go state machine (v3 — deferred until sprint shape stabilizes)
- Artifact versioning (overwrite is fine for v2)
- Per-turn OODARC (L0/L1 — out of sprint scope)
- OODARC escalation contracts (separate design work needed)

## Dependencies

- `clavain-cli` Go codebase for F1 (artifact bus commands)
- All 9 command files in os/Clavain/commands/ for F2-F3
- Complexity classification (already exists) for F4

## Rollout Plan

1. **F1** first — CLI commands are the foundation
2. **F3** second — progress trackers are independent of artifact bus, can parallelize
3. **F2** third — wire artifact bus into commands (depends on F1)
4. **F5** fourth — sprint display (depends on F2 for artifact paths)
5. **F4** fifth — autonomy tiers (depends on F2 for reliable auto-advance)
6. **F6** sixth — parallel windows (depends on F2 + F4 for safe parallel dispatch)
