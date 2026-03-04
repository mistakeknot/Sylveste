# Brainstorm: C3 Composer — Match Agency Specs to Fleet Registry Within Budget

**Bead:** iv-240m
**Date:** 2026-03-03
**Epic:** iv-d4wk0 (Consolidate Clavain core logic from shell to Go)

## What We're Building

A `clavain-cli compose` subcommand in Go that takes an agency spec stage definition + fleet registry + Interspect calibration + sprint budget and produces a JSON dispatch plan: which agents, on which models, with what estimated cost, filling which roles.

This is the **join operator** between three existing systems:
- **C1 (agency-spec.yaml):** declares what roles and capabilities each stage needs
- **C2 (fleet-registry.yaml):** declares what agents offer (capabilities, roles, model support, cost)
- **Interspect calibration:** provides evidence-driven model-tier recommendations per agent

Today these systems exist independently. Dispatch is hand-coded in flux-drive (LLM triage scoring) and sprint (hardcoded phase→command maps). Neither reads the spec roster or fleet registry programmatically.

## Why Go (Not Shell)

Clavain has ~4,100 lines of shell libraries (lib-sprint.sh 1,414, lib-routing.sh 1,058, lib-fleet.sh 338, lib-spec.sh 222) containing core operational logic. This accreted organically because Claude Code hooks must be shell, but the logic they call doesn't have to be.

The Go CLI (clavain-cli, 5k lines) already handles budget math, phase tracking, checkpoints, and claims with typed structs and 62 unit tests. The Composer forces fleet+spec reading into Go, establishing the pattern for gradually migrating the rest.

Shell hooks become thin callers: `plan=$(clavain-cli compose --sprint="$id" --stage=build)`.

## Key Decisions

### 1. Runtime: Go subcommand in clavain-cli
- Go reads fleet-registry.yaml + agency-spec.yaml directly (new Go YAML parsing)
- Go calls `ic route batch` for model resolution baseline (existing pattern)
- Go reads Interspect calibration JSON directly for evidence-driven overrides
- Returns JSON array on stdout
- Shell hooks are thin wrappers

### 2. Budget strategy: Warn and emit, don't optimize
- Emit the full plan with all agents at their recommended models
- Calculate total estimated cost vs stage budget
- If over budget: set `warnings: ["budget_exceeded"]` in output
- Never drop or downgrade agents — let the caller decide
- Interspect already runs shadow A/B on model tiers; no need to duplicate comparison infrastructure

### 3. Interspect integration: Read calibration + overrides, don't rebuild
- Read `.clavain/interspect/routing-calibration.json` for per-agent model recommendations
- Read `.claude/routing-overrides.json` for agent exclusion decisions
- Both have `schema_version` fields for forward compatibility
- After agents execute, callers write verdict outcomes back via `_interspect_record_verdict()` (existing shell function, not ported yet)
- The Composer does NOT build its own A/B comparison system

### 4. Output format: JSON stdout
- Standard clavain-cli pattern (every subcommand uses stdout JSON)
- No manifest files — caller captures with `$(clavain-cli compose ...)`
- Schema:
  ```json
  {
    "stage": "build",
    "sprint": "iv-240m",
    "budget": 100000,
    "estimated_total": 85000,
    "warnings": [],
    "agents": [
      {
        "agent_id": "fd-safety",
        "subagent_type": "interflux:fd-safety",
        "model": "sonnet",
        "estimated_tokens": 40000,
        "role": "reviewer",
        "required": true,
        "model_source": "interspect_calibration"
      }
    ]
  }
  ```

### 5. Go consolidation epic (iv-d4wk0)
The Composer is the first concrete step in migrating Clavain core logic from shell to Go. Migration path:
- **Now:** Fleet registry reading + spec loading + compose logic → Go
- **Next:** lib-fleet.sh functions → Go fleet package (replaces yq dependency)
- **Later:** lib-spec.sh → Go spec package (replaces agency-spec-helper.py)
- **Eventually:** lib-routing.sh logic beyond ic-delegation → Go

## Open Questions

1. **Safety floors in Go:** `fd-safety` and `fd-correctness` have hardcoded safety floors in lib-routing.sh (never downgraded below sonnet). Should the Composer enforce this, or trust that Interspect calibration already respects it?
2. **Codex dispatch gap:** The Composer's `model` field (haiku/sonnet/opus) maps to subagent models. Codex dispatch uses `--tier fast|deep` from a separate namespace in routing.yaml. The Composer doesn't yet handle Codex dispatch mode — needs a `dispatch_mode` field or separate path.
3. **Fleet registry staleness:** fleet-registry.yaml is manually maintained. Agents added to plugins but not registered in the fleet are invisible to the Composer. Should `clavain-cli compose` warn about spec roles with no fleet candidates?

## Integration Surface

### Inputs (Go reads directly)
- `os/clavain/config/agency-spec.yaml` (+ project override `.clavain/agency-spec.yaml`)
- `os/clavain/config/fleet-registry.yaml`
- `.clavain/interspect/routing-calibration.json`
- `.claude/routing-overrides.json`
- Sprint budget via `ic run tokens <run_id>` subprocess

### Outputs (JSON stdout)
- Dispatch plan consumed by flux-drive (iterate plan, use agent_id + model for Agent() calls)
- Dispatch plan consumed by sprint pipeline (pass to executing-plans skill)

### Consumers that change
- **flux-drive launch phase:** replaces `routing_resolve_agents` call with Composer plan iteration
- **sprint pipeline:** calls `clavain-cli compose` before dispatching each phase
- **lib-routing.sh:** no longer called directly by consumers for agent batches; still used for single-agent resolution and safety floor enforcement
