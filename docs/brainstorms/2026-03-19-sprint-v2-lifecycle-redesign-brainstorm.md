---
artifact_type: brainstorm
bead: Demarch-lta9
stage: discover
---

# Sprint v2 Lifecycle Redesign

## What We're Building

A holistic redesign of the 10-step sprint lifecycle to achieve three goals:

1. **Artifact Bus** — Formal artifact handoff between steps via `clavain-cli set-artifact` / `get-artifact`, replacing brittle file discovery and manual argument passing
2. **Progress Tracker Rollout** — Canonical phase checklists and hard-stop rules in all 9 remaining commands (brainstorm.md already done)
3. **OODARC Alignment** — Each step has a declared OODARC role, reflect compounds learning explicitly, escalation contracts are formalized

**Autonomy target:** All complexities run unattended by default, human opts in via breakpoints. Graduated rollout: C1-C2 first, then C3, then C4-C5. Multi-agent parallel execution designed into the artifact contracts from the start.

**Architecture:** Artifact Bus now, graduating to a formal Go state machine (Approach C) once the sprint shape stabilizes.

## Why This Approach

### Current State (Sprint v1)

Research scored the sprint lifecycle at 6/10 maturity:

- **Progress templates:** 2/9 commands (brainstorm, work via TodoWrite)
- **Artifact handoff:** 3/10 — most steps use `ls -t | head -1`, conversation context, or manual args
- **Checkpoint coverage:** 4/9 commands call `checkpoint-write`
- **OODARC alignment:** Partial — 5 blockers from synthesis doc unresolved

### Six Critical Handoff Gaps

| Gap | Steps | Problem |
|-----|-------|---------|
| 1 | Brainstorm → Strategy | Strategy uses `ls -t docs/brainstorms/ | head -1` instead of reading bead artifact |
| 2 | Strategy → Write-Plan | Write-plan ignores PRD entirely; plan generated from bead title |
| 3 | Write-Plan → Flux-Drive | Plan path passed manually in sprint.md; no artifact registry lookup |
| 4 | Quality-Gates → Resolve | Findings not auto-converted to actionable items; resolve does independent source detection |
| 5 | Resolve → Reflect | Reflect reads conversation history, not resolve's git commits or todo changes |
| 6 | Reflect → Land | Land expects manual argument; reflect artifact not pre-staged |

### Why Artifact Bus

A single mechanism (`set-artifact` / `get-artifact`) solves handoff, tracking, and resume simultaneously. It also enables parallel execution: two agents can write different artifact types to the same bead without conflict. The artifact type registry becomes the contract between steps, which later becomes the state machine's declared I/O.

## Key Decisions

### D1: Artifact Type Registry

Each sprint step declares exactly one output artifact type:

| Step | Artifact Type | Path Pattern | Produced By |
|------|--------------|--------------|-------------|
| 1: Brainstorm | `brainstorm` | `docs/brainstorms/<bead>-*.md` | brainstorm.md Phase 3 |
| 2: Strategy | `prd` | `docs/prds/<bead>-*.md` | strategy.md Phase 2 |
| 3: Write-Plan | `plan` | `docs/plans/<bead>-*.md` | write-plan.md |
| 4: Plan Review | `plan-review` | `.clavain/verdicts/<bead>-plan-review.json` | flux-drive |
| 5: Execute | `implementation` | (git commits — ref is SHA range) | work.md |
| 6: Quality Gates | `quality-verdict` | `.clavain/verdicts/<bead>-quality.json` | quality-gates.md |
| 7: Resolve | `resolution` | (git commits — ref is SHA range) | resolve.md |
| 8: Reflect | `reflection` | `docs/solutions/<bead>-*.md` | reflect.md |
| 9: Land | `landed` | (git tag or commit SHA) | land.md |
| 10: Ship | `closed` | (bead state change) | sprint.md inline |

**CLI contract:**
```bash
# Producer (end of each step):
clavain-cli set-artifact "$BEAD_ID" "<type>" "<path_or_ref>"

# Consumer (start of next step):
artifact_path=$(clavain-cli get-artifact "$BEAD_ID" "<type>")
```

### D2: Progress Tracker Standard

Every command gets the same structure as brainstorm.md:

1. **`## Progress Tracking`** section with exact phase checklist
2. **Behavioral rule** capping phase count: "Exactly N phases (0-M). Do NOT invent, rename, or append phases."
3. **`checkpoint-write`** call at terminal phase
4. **Terminal annotation** `(Terminal)` on final phase heading
5. **Hard stop** after output summary: "Do NOT display additional unchecked phases"

### D3: OODARC Step Mapping

| Step | OODARC Role | Contract |
|------|-------------|----------|
| Brainstorm | **Observe** | Gather signals, understand problem space |
| Strategy | **Orient** | Structure decision space, generate features |
| Write-Plan | **Decide** | Choose implementation approach, decompose |
| Plan Review | **Validate** (gate) | Check decision quality before commitment |
| Execute | **Act** | Implement the decision |
| Quality Gates | **Observe** (quality) | Gather execution quality signals |
| Resolve | **Act** (corrective) | Fix identified issues |
| Reflect | **Reflect + Compound** | Extract learnings, update routing, calibrate |
| Land | **Act** (finalize) | Commit to trunk, close |
| Ship | **Terminal** | Record actuals, sweep children |

### D4: Graduated Autonomy Model

Three tiers, unlocked progressively:

**Tier 1 (C1-C2): Full Auto**
- Skip brainstorm dialogue (Phase 0 detects clear requirements → jump to plan)
- Auto-approve plan review if no P0/P1 findings
- Auto-advance through all steps without AskUserQuestion
- Gate: quality-gates PASS required; FAIL pauses

**Tier 2 (C3): One Checkpoint**
- Auto-advance through brainstorm → plan
- Pause after plan review for user confirmation
- Auto-advance through execute → ship
- Gate: plan review + quality-gates both gate

**Tier 3 (C4-C5): Interactive**
- All current AskUserQuestion checkpoints remain
- But artifact handoff is still explicit (no manual args)
- Multi-agent execution available for independent steps

**Tier selection:** Complexity classification determines tier. User can override with `--autonomy=<tier>` or set breakpoints via `bd set-state <bead> manual_pause true`.

### D5: Multi-Agent Parallel Execution

Two parallelization windows in the sprint:

**Window 1: Execute + Quality Gates Prep**
- While execute runs (Step 5), quality-gates can pre-stage its agent roster based on the plan
- Not full parallelism — quality-gates waits for execute to commit before analyzing

**Window 2: Resolve + Reflect**
- After quality-gates, resolve and reflect can run in parallel if findings are non-blocking
- Resolve writes `resolution` artifact; reflect reads conversation + `quality-verdict` artifact
- Both must complete before land

**Contract:** Parallel agents write to different artifact types. No two agents write the same type for the same bead. Sprint orchestrator waits for all parallel artifacts before advancing.

### D6: State Machine Graduation Path

The artifact bus is designed to be the data layer for a future Go state machine:

```
Current (v2): sprint.md dispatches commands, reads artifacts via CLI
Future (v3): clavain-cli sprint-run <bead> — Go state machine dispatches, gates, advances
```

Migration path:
1. Artifact types become state machine's declared I/O schema
2. Gate checks become state transition guards
3. Progress tracker becomes state machine's current-state display
4. Autonomy tiers become state machine's auto-advance policy

No Go code needed for v2 — the artifact bus CLI commands are sufficient.

## Open Questions

1. **Artifact versioning** — If a step re-runs (e.g., plan rewrite after flux-drive feedback), should `set-artifact` overwrite or version? Overwrite is simpler; versioning enables rollback but adds complexity.

2. **Git commit artifacts** — Steps 5 and 7 produce git commits, not files. Should the artifact reference be a SHA range (`abc123..def456`) or a tag? Tags are more stable but add git overhead.

3. **Parallel execution failure modes** — If resolve fails but reflect succeeds (or vice versa), what's the recovery? Current sprint halts on any failure, but parallel failures need a join-and-report mechanism.

4. **Tier graduation criteria** — What evidence triggers upgrading from Tier 1 to Tier 2? Options: N successful auto-runs, interspect confidence score, user explicit opt-in. User opt-in is safest but slowest.

5. **OODARC inline reflect** — The synthesis doc distinguishes inline reflect (within-cycle, signal_score >= 4) from async reflect (Step 8). Should sprint v2 add inline reflect checkpoints within execute (Step 5), or keep it as a separate step?
