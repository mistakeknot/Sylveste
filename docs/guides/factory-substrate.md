# Factory Substrate Guide

The factory substrate adds validation-first quality infrastructure to Clavain's sprint lifecycle. It records execution as an immutable Turn DAG, scores agent output against holdout scenarios, converts failures into regression tests, and enforces capability policies per phase.

## Components

| Component | Purpose | CLI Prefix |
|-----------|---------|------------|
| CXDB (Turn DAG) | Append-only execution recording | `cxdb-*` |
| Scenario Bank | Dev/holdout test scenarios | `scenario-*` |
| Satisfaction Scoring | Quality gate with closed-loop calibration | `scenario-score`, `scenario-calibrate` |
| Evidence Pipeline | Failure-to-scenario conversion | `evidence-*` |
| Agent Policies | Phase-aware capability restrictions | `policy-*` |

All commands are subcommands of `clavain-cli`. Run `clavain-cli help` for the full list.

## CXDB — Turn DAG

CXDB is StrongDM's open-source Context Database. Clavain uses it to record every phase transition, agent dispatch, artifact, and quality score as immutable turns in a directed acyclic graph.

### Setup

```bash
# Download the CXDB server binary (one-time)
clavain-cli cxdb-setup

# Start the server (also auto-starts via SessionStart hook)
clavain-cli cxdb-start

# Check status
clavain-cli cxdb-status
```

The server stores data at `.clavain/cxdb/data/` and listens on port 9009 (binary) / 9010 (HTTP).

### Recording

Phase transitions are recorded automatically when `clavain-cli advance-phase` succeeds. You can also backfill from Intercore events:

```bash
# Backfill CXDB from an existing sprint
clavain-cli cxdb-sync <sprint-id>

# Create a branched execution trajectory (O(1) fork)
clavain-cli cxdb-fork <sprint-id> <turn-id>
```

### Turn Types

Seven typed schemas are registered at startup from `config/cxdb-types.json`:

| Type | Records |
|------|---------|
| `clavain.phase.v1` | Phase transitions (brainstorm, executing, shipping, etc.) |
| `clavain.dispatch.v1` | Agent dispatches with model, tokens, status |
| `clavain.artifact.v1` | Artifact references with BLAKE3 blob hashes |
| `clavain.scenario.v1` | Scenario execution trajectories |
| `clavain.satisfaction.v1` | Quality scores with judge rationale |
| `clavain.evidence.v1` | Evidence from failures, profiler events, regressions |
| `clavain.policy_violation.v1` | Holdout access violations |

## Scenario Bank

Scenarios are YAML files that define reproducible test cases for agent-driven development. They live in `.clavain/scenarios/` with strict separation between dev and holdout sets.

### Directory Structure

```
.clavain/scenarios/
  dev/           # Failure-derived scenarios (agents can see these)
  holdout/       # Spec-derived scenarios (hidden during build phases)
  satisfaction/  # Run results and scores
```

### Creating Scenarios

```bash
# Scaffold a dev scenario
clavain-cli scenario-create checkout-flow

# Scaffold a holdout scenario (from specs, not from failures)
clavain-cli scenario-create checkout-validation --holdout

# List all scenarios
clavain-cli scenario-list
clavain-cli scenario-list --holdout  # holdout only

# Validate all scenarios against the v1 schema
clavain-cli scenario-validate
```

### Scenario YAML Format

```yaml
schema_version: 1
id: checkout-flow-001
intent: "User can complete checkout with a valid credit card"
mode: behavioral        # static | behavioral
setup:
  - "Application running with test database"
  - "User authenticated as test-buyer"
steps:
  - action: "Navigate to cart"
    expect: "Cart shows 2 items"
    type: llm-judge     # llm-judge | exact | regex | shell
  - action: "Submit order"
    expect: "exit_code: 0"
    type: shell
rubric:
  - criterion: "Order persisted in database"
    weight: 0.4
  - criterion: "Confirmation email queued"
    weight: 0.3
  - criterion: "Inventory decremented"
    weight: 0.3
risk_tags: [payment, data-integrity]
holdout: false
```

### Running Scenarios

```bash
# Run all scenarios matching a pattern
clavain-cli scenario-run "checkout*"

# Run with sprint association (records in CXDB)
clavain-cli scenario-run "*" --sprint=iv-abc123
```

## Satisfaction Scoring

Satisfaction scoring determines whether a sprint meets quality standards before shipping.

### Scoring a Run

```bash
# Score a completed scenario run
clavain-cli scenario-score run-1709654400

# Get pass/fail summary
clavain-cli scenario-score run-1709654400 --summary
# Output: Satisfaction: 0.85 (threshold: 0.70, source: default)
#         Pass: 8, Fail: 2, Total: 10
#         PASS
```

### Threshold Calibration

The system uses a 4-stage calibration pattern:

1. **Stage 1:** Default threshold 0.7
2. **Stage 2:** Scores + sprint outcomes collected in CXDB
3. **Stage 3:** `clavain-cli scenario-calibrate` computes optimal threshold (needs 20+ sprints)
4. **Stage 4:** Calibrated threshold used, 0.7 as fallback

Override the threshold in `.clavain/budget.yml`:
```yaml
satisfaction_threshold: 0.75
```

### Gate Integration

The satisfaction gate blocks shipping when holdout scores are below threshold. It runs automatically during `clavain-cli enforce-gate <bead-id> shipping`.

- Score below threshold: gate fails (in enforce mode) or warns (in shadow mode)
- No holdout scenarios: gate passes (no data = no block)
- `CLAVAIN_SKIP_GATE=<reason>`: bypasses with auditable reason

## Evidence Pipeline

The evidence pipeline converts failures into regression scenarios, building a growing test suite from real incidents.

### Converting Findings to Scenarios

```bash
# Convert a scan finding to a dev scenario
clavain-cli evidence-to-scenario finding-abc123

# Create an evidence pack from a failed sprint
clavain-cli evidence-pack iv-xyz789

# List evidence packs
clavain-cli evidence-list
clavain-cli evidence-list iv-xyz789  # filter by bead
```

Evidence-to-scenario **always** writes to `dev/`, never `holdout/`. This is enforced by hardcoded path checks.

### Automatic Scenario Generation

When flux-drive detects a regression with severity `error` or `critical`, a dev scenario is auto-generated at `.clavain/scenarios/dev/fd-<hash>.yaml`. This is idempotent — the same finding won't create duplicate scenarios.

## Agent Capability Policies

Policies restrict what agents can access during different sprint phases. The primary use case is preventing holdout contamination — agents building code must never see holdout scenarios.

### How It Works

```bash
# Check if an action is allowed
clavain-cli policy-check build-agent read --path=.clavain/scenarios/holdout/test.yaml
# {"allowed":false,"reason":"path denied by pattern in phase executing"}

# Same check during shipping phase (quality gates)
CLAVAIN_PHASE=shipping clavain-cli policy-check validator read --path=.clavain/scenarios/holdout/test.yaml
# {"allowed":true,"reason":"allowed by policy"}

# Display current policy table
clavain-cli policy-show
```

### Default Policy

| Phase | Holdout Access | Notes |
|-------|---------------|-------|
| brainstorm | Denied | Building phase |
| strategized | Denied | Building phase |
| planned | Denied | Building phase |
| executing | Denied | Building phase |
| shipping | Allowed | Quality gates need holdout to validate |
| reflect | Denied | Post-ship phase |

### Custom Policies

Override the default by creating `.clavain/policy.yml`:

```yaml
schema_version: 1
phases:
  executing:
    deny_paths:
      - ".clavain/scenarios/holdout/**"
      - "secrets/**"
    deny_tools:
      - "rm"
  shipping:
    allow_paths: ["**"]
    allow_tools: ["**"]
```

### Violation Tracking

Policy violations (holdout access during build) are recorded as CXDB turns (`clavain.policy_violation.v1`). The satisfaction gate queries for violations and invalidates contaminated scores.

## Defense in Depth

The factory substrate implements three layers of holdout protection:

1. **Preventive:** SessionStart hook excludes holdout from agent context during build phases
2. **Detective:** `policy-check` records violations as CXDB turns
3. **Corrective:** Satisfaction gate invalidates scores from contaminated sprints

This means a single failure (e.g., preventive exclusion bypassed) doesn't compromise quality assurance — the detective and corrective layers catch it.
