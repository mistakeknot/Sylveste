---
artifact_type: prd
bead: iv-6ixw
stage: design
---

# PRD: C5 Self-Building Loop

## Problem

Clavain has all the infrastructure to orchestrate its own development (agency specs, fleet registry, Composer, handoff contracts) but nothing wires them together into a self-referential sprint. The Composer produces dispatch plans that are never consumed, and Clavain has no project-specific config to target itself.

## Solution

Wire the Composer's output into the sprint executor so that model selection and budget enforcement are driven by the dispatch plan, not hardcoded. Add a Clavain-specific agency spec override so that when Clavain builds itself, it uses project-aware configuration with mandatory self-modification safety review.

## Features

### F1: Self-Targeting Config

**What:** Create `.clavain/agency-spec.yaml` in the Clavain repo with project-specific overrides.

**Acceptance criteria:**
- [ ] `.clavain/agency-spec.yaml` exists in `os/clavain/` with project metadata (name, language, test_command, lint_command)
- [ ] Ship stage includes `fd-self-modification` as a required agent
- [ ] Composer reads and merges the project override when run from the Clavain directory
- [ ] Existing Composer tests still pass with the new project spec present

### F2: Compose Plan Integration

**What:** Sprint executor reads the ComposePlan to set model tier and budget caps per phase, persisting the plan as an artifact for checkpoint resume.

**Acceptance criteria:**
- [ ] New CLI command `sprint-compose` runs compose for the active sprint and stores the plan as an ic artifact
- [ ] New CLI command `sprint-plan-phase` reads the stored ComposePlan and returns model + budget for a given phase/stage
- [ ] Sprint executor calls `sprint-plan-phase` before each phase dispatch and exports `CLAVAIN_MODEL` and `CLAVAIN_PHASE_BUDGET` env vars
- [ ] ComposePlan survives checkpoint resume (stored as ic artifact, not just in-memory)
- [ ] When no ComposePlan exists (legacy sprints), executor falls back to current behavior silently

### F3: Gate Mode Graduation

**What:** Flip handoff contract validation from shadow to enforce for early-pipeline transitions.

**Acceptance criteria:**
- [ ] Agency spec `gate_mode` changed from `shadow` to `enforce` for discover→design gate
- [ ] Agency spec `gate_mode` changed from `shadow` to `enforce` for design→build gate
- [ ] Ship gates remain `shadow` (lower risk of false-positive blocking)
- [ ] `enforce-gate` correctly blocks phase advancement when artifacts fail validation in enforce mode
- [ ] Existing handoff tests updated to cover enforce mode behavior

### F4: End-to-End Smoke Test

**What:** A smoke test that runs Clavain's sprint infrastructure against itself to validate the full C1→C4 chain.

**Acceptance criteria:**
- [ ] Smoke test script or Go test that: creates a sprint targeting the Clavain project, runs compose (verifying project spec merge), validates a brainstorm artifact against handoff contracts (enforce mode), verifies model/budget env vars are set correctly per phase
- [ ] Test runs in CI (go test) without requiring ic or bd (mock/stub kernel calls)
- [ ] Test validates the self-referential property: Clavain's own agency spec is used

## Non-goals

- Full agent dispatch from ComposePlan (follow-up: iv-71kf3)
- Persistent event reactor for cross-session advancement (follow-up: iv-p0w2s)
- Autonomous sprint initiation from backlog
- Gate graduation for build→ship transitions (too risky for first iteration)

## Dependencies

- C1: Agency spec schema (shipped)
- C2: Fleet registry (shipped)
- C3: Composer (shipped)
- C4: Handoff contracts (shipped)
- A3: Event-driven advancement protocol (shipped — session-scoped auto-advance)

## Open Questions

1. Should `CLAVAIN_MODEL` be consumed by the `/sprint` command template to set subagent model hints, or should individual skills read it themselves?
2. Per-stage budget enforcement: hard-stop or warn-and-continue? Current `budget_exceeded` pause behavior suggests warn.
