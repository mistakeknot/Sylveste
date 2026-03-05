---
artifact_type: prd
bead: iv-nh3d7
stage: design
---
# PRD: F4 Consumer Wiring — flux-drive and sprint consume Composer dispatch plan

## Problem

The Composer pipeline (C3-C5) generates structured dispatch plans but nothing reads them. Flux-drive still runs its own manual triage scoring, and the sprint executor uses hardcoded defaults. The entire Composer infrastructure sits idle.

## Solution

Wire both consumers to read ComposePlan artifacts: a shell bridge for flux-drive, launch.md integration for agent dispatch, and a hook for sprint env var injection. Composer becomes authoritative when configured (agency-spec exists).

## Features

### F1: lib-compose.sh shell bridge

**What:** Shell helper library at `os/clavain/scripts/lib-compose.sh` that wraps clavain-cli compose commands for Bash consumers.

**Acceptance criteria:**
- [ ] `compose_available()` returns 0 when clavain-cli exists AND agency-spec is found in any config dir
- [ ] `compose_dispatch(bead_id, phase)` reads stored ic artifact first, falls back to `clavain-cli compose --stage=X`
- [ ] `compose_agents_json(plan)` extracts agents array from ComposePlan JSON
- [ ] `compose_has_agents(plan)` returns 0 when plan has non-empty agents array
- [ ] `compose_warn_if_expected(err)` prints error when agency-spec exists, is silent otherwise
- [ ] Unit tests using fixture ComposePlan JSON files (test_compose.bats)

### F2: flux-drive launch.md Composer integration

**What:** Wire Step 2.0.4 in flux-drive launch.md to call lib-compose.sh and, when a ComposePlan is available, replace the entire manual triage (Steps 2.0.5-2.2) with Composer-selected agents.

**Acceptance criteria:**
- [ ] Step 2.0.4 sources lib-compose.sh and calls compose_dispatch() with current bead and phase
- [ ] When ComposePlan has agents: skip Steps 2.0.5-2.2, iterate plan agents directly for dispatch
- [ ] When ComposePlan is empty or unavailable (no agency-spec): fall through to existing triage unchanged
- [ ] When agency-spec exists but compose fails: surface error, do NOT silently fall back
- [ ] ComposePlan warnings are logged (budget_exceeded, unmatched_role, etc.)
- [ ] Agent dispatch uses `subagent_type` and `model` from the plan

### F3: Sprint hook env var injection

**What:** SessionStart hook calls `clavain-cli sprint-env-vars` to export `CLAVAIN_MODEL` and `CLAVAIN_PHASE_BUDGET` when an active sprint bead exists.

**Acceptance criteria:**
- [ ] Hook detects active sprint bead (from `sprint-find-active`)
- [ ] Calls `sprint-env-vars <bead_id> <phase>` and exports the output
- [ ] Sprint skills read `CLAVAIN_MODEL` and `CLAVAIN_PHASE_BUDGET` from env without changes
- [ ] No-op when no active sprint exists
- [ ] No-op when sprint-env-vars returns empty (no stored compose plan)

## Non-goals

- Modifying the Composer algorithm itself (that's C3, already shipped)
- Changing the agency-spec format
- Adding new agent types to the fleet registry
- Runtime re-composition mid-session (env vars are set once at session start)
- Flux-drive knowledge injection (Step 2.1) — orthogonal to agent selection

## Dependencies

- `compose.go` + `selfbuild.go` in clavain-cli (shipped in C3/C5)
- `sprint-compose`, `sprint-plan-phase`, `sprint-env-vars` CLI commands (shipped in C5)
- `ic` CLI for artifact storage (intercore)
- Existing flux-drive launch.md triage logic (Steps 2.0.5-2.2)
- `lib-routing.sh` for fallback model resolution

## Open Questions

1. **Hook timing for env vars:** SessionStart runs once. If the phase advances mid-session, env vars go stale. Acceptable for now (phase transitions are rare within a single session), but may need a PreToolUse hook later.
2. **Budget mapping:** `CLAVAIN_PHASE_BUDGET` and `FLUX_BUDGET_REMAINING` may overlap. For now, if both are set, `FLUX_BUDGET_REMAINING` takes precedence (it's more specific). If only phase budget is set, use it as the flux-drive budget.
