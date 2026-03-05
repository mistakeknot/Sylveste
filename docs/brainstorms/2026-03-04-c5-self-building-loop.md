---
artifact_type: brainstorm
bead: iv-6ixw
stage: discover
---

# C5: Self-Building Loop — Clavain Runs Its Own Development Sprints

**Bead:** iv-6ixw

## What We're Building

A session-scoped self-building loop where Clavain uses its own agency specs, fleet registry, Composer, and handoff contracts to orchestrate its own development sprints. The sprint executor consumes the Composer's dispatch plan to route models and enforce budgets per phase — proving that the C1→C2→C3→C4 chain works end-to-end when Clavain targets itself.

This is the convergence point: all 4 prior deliverables (agency specs, fleet registry, Composer, handoff contracts) feed into a single sprint that builds Clavain using Clavain's own infrastructure.

## Why This Approach

### Session-scoped, not autonomous

The full vision (persistent event reactor, auto-initiated sprints from backlog) is too large for one sprint. Session-scoped proves the loop works with minimal new code and zero new processes. The event reactor becomes a follow-up epic.

### Model routing, not full agent dispatch

The Composer produces a ComposePlan with agents, models, and budgets per stage. Rather than rewriting the sprint executor to spawn fleet agents directly, we inject the Composer's model and budget decisions into the existing skill dispatch. Skills already work — we add model awareness via env vars (`CLAVAIN_MODEL`, `CLAVAIN_PHASE_BUDGET`). Full agent dispatch becomes a follow-up.

### Minimal project overrides

Clavain gets a `.clavain/agency-spec.yaml` that only overrides what's project-specific: test command (go test + bats), lint command (go vet), and mandatory `fd-self-modification` safety agent at the ship stage. Everything else inherits from the default agency spec.

## Key Decisions

1. **Scope: Session-scoped loop** — Human initiates `/sprint`, Composer picks models/budgets, sprint auto-advances within one session. No cross-session reactor.

2. **Dispatch model: Model routing only** — ComposePlan sets model tier and budget caps per phase via env vars. Skill dispatch stays hardcoded. Follow-up bead for full agent dispatch.

3. **Self-targeting config: Minimal overrides** — `.clavain/agency-spec.yaml` with project metadata, Go-specific test/lint commands, and `fd-self-modification` as a required ship-stage agent.

4. **Gate mode: Graduate to enforce** — Flip handoff contracts from shadow to enforce for brainstorm→design and design→build transitions. Keeps ship gates soft for now.

5. **Safety: Mandatory self-modification review** — When the sprint target is the Clavain repo itself, `fd-self-modification` is a required reviewer. This is enforced via the project agency spec, not hardcoded.

## Architecture

### What exists (C1-C4, A1-A2)

- **C1 Agency Spec**: 5-stage declarative config with budget shares, agents, tools, gates
- **C2 Fleet Registry**: 25+ agents with capabilities, roles, cost profiles
- **C3 Composer**: Matches specs to fleet, produces ComposePlan JSON with agents/models/budgets
- **C4 Handoff Contracts**: 5 artifact types validated at phase gates (shadow mode)
- **Sprint infrastructure**: 10-phase pipeline with ic-backed state, auto-advance, checkpoint resume
- **Budget system**: Per-stage allocation, calibration, USD estimation

### What C5 adds

```
sprint-create
  └─ compose (already works)
      └─ ComposePlan JSON
          └─ NEW: sprint executor reads plan
              ├─ sets CLAVAIN_MODEL per phase
              ├─ sets CLAVAIN_PHASE_BUDGET per phase
              └─ existing skill dispatch proceeds with model/budget awareness

.clavain/agency-spec.yaml (Clavain project override)
  └─ Composer reads this when project=clavain
      └─ Adds fd-self-modification to ship stage
      └─ Sets Go-specific test/lint commands
```

### Flow

```
Human: /sprint iv-xyz (Clavain bead)
  │
  ├─ sprint-create → ic run create (with agency spec + compose)
  │   └─ compose produces ComposePlan for this sprint
  │
  ├─ Phase: brainstorm
  │   ├─ Read ComposePlan → model=sonnet, budget=100k
  │   ├─ Set CLAVAIN_MODEL=sonnet, CLAVAIN_PHASE_BUDGET=100000
  │   └─ Dispatch /clavain:brainstorm (existing skill)
  │
  ├─ Phase: design (strategy + plan)
  │   ├─ Read ComposePlan → model=opus, budget=250k
  │   └─ Dispatch /clavain:strategy, /clavain:write-plan
  │
  ├─ Phase: build (execute)
  │   ├─ Read ComposePlan → model=opus, budget=400k
  │   ├─ Handoff contract: enforce (plan must pass validation)
  │   └─ Dispatch /clavain:work
  │
  ├─ Phase: ship (quality-gates)
  │   ├─ Read ComposePlan → model=sonnet, budget=200k
  │   ├─ fd-self-modification required (from project spec)
  │   └─ Dispatch /clavain:quality-gates
  │
  └─ Phase: reflect
      ├─ Read ComposePlan → model=haiku, budget=50k
      └─ Dispatch /clavain:reflect
```

## Open Questions

1. **Env var consumption**: Which skills/commands currently read `CLAVAIN_MODEL`? Need to audit and wire up model routing where it matters (subagent dispatch in `/work`, model selection in `/quality-gates`).

2. **Compose plan persistence**: Should the ComposePlan be stored as an ic artifact so it survives checkpoint resume? Currently `compose` is a one-shot CLI command.

3. **Budget enforcement granularity**: Per-stage budget caps from the plan — should the executor hard-stop when budget is exceeded, or warn and continue (matching current `budget_exceeded` pause behavior)?

4. **Gate graduation scope**: Which gates flip to enforce first? Brainstorm→design and design→build are safest (early in pipeline). Build→ship is riskier (could block shipping on a false positive).

## Follow-Up Beads (to create)

- **C5.1: Full agent dispatch** — Sprint executor spawns fleet agents from ComposePlan instead of hardcoded skills. Needs agent→skill/prompt mapping and parallel dispatch.
- **C5.2: Event reactor (A3 full)** — Persistent event reactor for cross-session sprint advancement. Consumer checkpointing, backoff, managed service lifecycle.
