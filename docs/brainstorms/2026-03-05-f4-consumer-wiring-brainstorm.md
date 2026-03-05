---
artifact_type: brainstorm
bead: iv-nh3d7
stage: discover
---
# F4: Consumer Wiring — flux-drive and sprint consume Composer dispatch plan

## What We're Building

Wire the two primary consumers (flux-drive and sprint executor) to read and act on Composer dispatch plans. The Composer (C3, shipped as `compose.go`) produces `ComposePlan` JSON artifacts describing which agents to dispatch at each stage, with model tiers and token budgets. Currently, both consumers use hardcoded agent selection — F4 replaces that with Composer-driven dispatch.

Three deliverables:
1. **lib-compose.sh** — shell bridge at `os/clavain/scripts/lib-compose.sh` that reads stored ComposePlan artifacts (from `sprint-compose`) with on-demand `clavain-cli compose` fallback for standalone flux-drive runs.
2. **flux-drive launch.md integration** — Step 2.0.4 calls lib-compose.sh; if a ComposePlan exists, it replaces Steps 2.0.5-2.2 (manual triage) entirely. Composer is authoritative.
3. **Sprint hook injection** — SessionStart hook calls `clavain-cli sprint-env-vars` to export `CLAVAIN_MODEL` and `CLAVAIN_PHASE_BUDGET` into the environment. Sprint skills read these naturally — no skill markdown changes needed.

## Why This Approach

The Composer pipeline (C3 -> C4 -> C5) is shipped but has no consumers. Sprint still uses hardcoded `defaultActions`, and flux-drive still runs its own triage scoring. Without F4, the Composer generates plans nobody reads — the entire C3-C5 arc sits idle.

**Composer replaces triage** rather than layering on top because:
- Agency specs already provide the override mechanism (users edit specs, not triage logic)
- Dual paths (Composer + triage) create ambiguity about which agent list is authoritative
- Simpler code path = fewer bugs in agent selection

**Stored-first, on-demand fallback** for plan retrieval because:
- sprint-create already stores all-stage plans as ic artifacts (cheap to read)
- Standalone flux-drive runs (no sprint context) still need on-demand compose
- Consistent plan across phases within a sprint (no mid-sprint drift)

**Error semantics: fail if expected** because:
- If an agency-spec exists, the user opted into Composer-driven dispatch
- Silent fallback would hide broken configuration (missing fleet registry, broken CLI)
- If no agency-spec exists, silent fallback is correct (Composer not configured)

## Key Decisions

1. **Composer is authoritative when present.** If ComposePlan has agents, flux-drive skips its entire manual triage (Steps 2.0.5-2.2). No hybrid/overlay mode.

2. **lib-compose.sh lives in os/clavain/scripts/.** Co-located with the Go CLI it wraps. Flux-drive sources it via `$CLAVAIN_SOURCE_DIR/scripts/`. This avoids coupling interflux to clavain internals.

3. **Stored artifact first, on-demand fallback.** `compose_dispatch()` reads stored ic artifact via `clavain-cli get-artifact`. If no stored plan (standalone flux-drive, no sprint), falls back to `clavain-cli compose --stage=X`.

4. **Hook injection for sprint env vars.** SessionStart hook calls `sprint-env-vars` when a sprint bead is active. Skills read `CLAVAIN_MODEL` and `CLAVAIN_PHASE_BUDGET` from environment — zero skill markdown changes.

5. **Fail-if-expected error semantics.** If agency-spec exists but compose fails, surface the error (don't silently fall back). If no agency-spec, silent fallback to existing behavior.

## Architecture

### ComposePlan structure (from compose.go)

```json
{
  "stage": "build",
  "sprint": "iv-nh3d7",
  "budget": 100000,
  "estimated_total": 85000,
  "warnings": [],
  "agents": [
    {
      "agent_id": "fd-architecture",
      "subagent_type": "interflux:fd-architecture",
      "model": "sonnet",
      "estimated_tokens": 25000,
      "role": "architecture-review",
      "required": true,
      "model_source": "fleet_preferred"
    }
  ]
}
```

### Data flow

```
agency-spec.yaml + fleet-registry.yaml
        |
        v
  clavain-cli compose  (or sprint-compose for all stages)
        |
        v
  ComposePlan JSON (stored as ic artifact)
        |
        +---> lib-compose.sh ---> flux-drive launch.md (Step 2.0.4)
        |                          - Reads agents from plan
        |                          - Dispatches via Agent() tool
        |                          - Skips manual triage
        |
        +---> sprint-env-vars ---> SessionStart hook
                                   - Exports CLAVAIN_MODEL
                                   - Exports CLAVAIN_PHASE_BUDGET
                                   - Sprint skills read from env
```

### lib-compose.sh API

```bash
compose_available()     # Returns 0 if clavain-cli exists and agency-spec found
compose_dispatch(bead_id, phase)  # Returns ComposePlan JSON on stdout
                                   # Tries stored artifact first, then on-demand
compose_agents_json(plan)         # Extracts agents array from plan
compose_has_agents(plan)          # Returns 0 if plan has non-empty agents
compose_warn_if_expected(err)     # Errors if agency-spec exists, silent otherwise
```

### Error behavior matrix

| agency-spec exists? | compose succeeds? | Behavior |
|---------------------|-------------------|----------|
| No                  | N/A               | Silent fallback to existing triage |
| Yes                 | Yes               | Use ComposePlan, skip triage |
| Yes                 | No                | Surface error, do NOT fall back |

## Open Questions

1. **Hook timing:** Should sprint-env-vars run in SessionStart (once) or at each phase transition? SessionStart is simpler but the model/budget won't update mid-session if the phase advances.
2. **Budget propagation:** How does `CLAVAIN_PHASE_BUDGET` translate to `FLUX_BUDGET_REMAINING`? Are they the same concept or does sprint budget partition differently?
3. **Testing strategy:** How to test the shell bridge without a full sprint? Mock ic artifacts? Fixture ComposePlan JSON files?
