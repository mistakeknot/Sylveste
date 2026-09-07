---
artifact_type: prd
bead: sylveste-5qv9
stage: design
version: 2
---
# PRD: Factory Substrate — Validation-First Infrastructure for Clavain

## Problem

Clavain can brainstorm, plan, build, review, and ship — but has no way to externalize what "correct" means, score satisfaction over execution trajectories, or record sprint history as a structured DAG. Without validation infrastructure, the autonomy ladder stalls at L2 (React). L3 (Auto-remediate) requires the system to know when something went wrong.

## Solution

Add a validation-first factory substrate to Clavain: adopt CXDB for artifact storage and rich querying, build a scenario bank with satisfaction scoring as the keystone validation primitive, wire existing plugins into an evidence pipeline, and enforce agent capability boundaries during execution. All intelligence lives in Clavain (L2) and Interverse plugins. Autarch (L3) is a pure UI consumer.

### Architectural Decisions (from flux-drive review)

**CXDB hybrid architecture:** Intercore remains the sole system of record for sprint state (phases, gates, dispatches). CXDB owns artifact blobs (scenario trajectories, evidence packs, satisfaction scores) via its Blob CAS with BLAKE3 dedup. The Turn DAG spine is derived from Intercore events, enriched with blob references. This eliminates dual-write consistency problems while giving CXDB its natural role.

**Binary distribution:** Sylveste cross-compiles CXDB for 4 targets (linux-x86_64, linux-aarch64, darwin-x86_64, darwin-aarch64) and hosts binaries in a Sylveste GitHub release. `clavain setup` downloads the right binary for the platform.

**Holdout enforcement:** Defense in depth — (1) SessionStart hook excludes `.clavain/scenarios/holdout/` from agent context during Build phase, (2) post-hoc audit detects holdout access and invalidates satisfaction scores from contaminated sprints.

**Scenario execution:** Full executor model — `scenario-run` spawns an agent that follows scenario steps against the actual codebase/system. Trajectories are recorded in CXDB. `scenario-score` evaluates trajectories via LLM judges.

**Anti-gaming:** Failure-derived scenarios go to `dev/` only. Holdout scenarios are either human-curated or spec-derived via `scenario-generate`. Agents never write to `holdout/`.

**Closed-loop calibration:** All 4 stages ship in F4 per PHILOSOPHY.md mandate: hardcoded default (0.7) -> collect scores -> calibrate from history -> default as fallback.

## Features

### F1: CXDB Adoption + Service Lifecycle

**What:** Adopt StrongDM's open-source CXDB (github.com/strongdm/cxdb) for artifact storage and rich querying. Intercore remains the system of record for sprint state.

**Acceptance criteria:**
- [ ] Cross-compiled `cxdb-server` binaries for 4 platforms hosted in Sylveste GitHub release
- [ ] `clavain setup` downloads correct platform binary to `.clavain/cxdb/cxdb-server`
- [ ] Service lifecycle commands: `clavain-cli cxdb-start`, `cxdb-stop`, `cxdb-status`
- [ ] PID file management at `.clavain/cxdb/cxdb.pid`
- [ ] Data directory at `.clavain/cxdb/data/`
- [ ] Auto-start from SessionStart hook when not running
- [ ] Health check returns server version and context count
- [ ] Type bundles registered during `cxdb-start` before health check passes: `clavain.phase.v1`, `clavain.dispatch.v1`, `clavain.artifact.v1`, `clavain.scenario.v1`, `clavain.satisfaction.v1`, `clavain.evidence.v1`, `clavain.policy_violation.v1`
- [ ] `clavain-types.json` bundle shipped in Clavain plugin with field-level schemas for all 7 types

### F2: Sprint Execution Recording

**What:** Record sprint execution history by deriving a CXDB Turn DAG from Intercore events, enriched with artifact blob references.

**Acceptance criteria:**
- [ ] Go SDK (`github.com/strongdm/ai-cxdb/clients/go`) added to clavain-cli `go.mod`
- [ ] New `pkg/cxdb/` package in clavain-cli with explicit error handling: `Connect() (*Client, error)`, `SprintContext(beadID) (uint64, error)`, `RecordPhase(...)`, `RecordDispatch(...)`, `StoreBlob(data) (hash, error)`, `ForkSprint(ctx, turnID) (uint64, error)`, `QueryByType(ctx, typeID) ([]Turn, error)`
- [ ] DAG spine replay: `cxdb-sync` reads `ic run events` and backfills CXDB Turn DAG for any sprint
- [ ] Large artifacts (review outputs, plans, evidence) stored as BLAKE3-addressed blobs in CXDB CAS
- [ ] Phase transitions and dispatch records remain in Intercore only — CXDB derives them via replay
- [ ] `cxdb-fork <sprint-id> <turn-id>` creates an O(1) branched execution trajectory
- [ ] CXDB write failures logged but do not block sprint progression (Intercore is authoritative)

**Field-level type schemas:**

```json
{
  "clavain.phase.v1": {
    "bead_id": "string",
    "phase": "string",
    "previous_phase": "string",
    "artifact_path": "string",
    "artifact_blob_hash": "bytes32",
    "timestamp": "uint64"
  },
  "clavain.dispatch.v1": {
    "bead_id": "string",
    "agent_name": "string",
    "agent_type": "string",
    "model": "string",
    "status": "string",
    "input_tokens": "uint64",
    "output_tokens": "uint64",
    "result_blob_hash": "bytes32",
    "timestamp": "uint64"
  },
  "clavain.artifact.v1": {
    "bead_id": "string",
    "artifact_type": "string",
    "path": "string",
    "blob_hash": "bytes32",
    "size_bytes": "uint64",
    "timestamp": "uint64"
  }
}
```

### F3: Scenario Bank + Full Executor

**What:** Filesystem-based scenario bank with dev/holdout separation, YAML schema, full executor that spawns agents to follow scenario steps, and CLI lifecycle commands.

**Acceptance criteria:**
- [ ] Directory convention: `.clavain/scenarios/{dev,holdout,satisfaction}/`
- [ ] Scenario YAML schema with fields: id, intent, mode (`static`|`behavioral`), setup, steps (action/expect pairs with type discriminator: `llm-judge`|`exact`|`regex`|`shell`), rubric (criterion/weight), risk_tags, holdout flag, schema_version
- [ ] `clavain-cli scenario-create <name> [--holdout]` scaffolds scenario YAML
- [ ] `clavain-cli scenario-list [--holdout] [--dev]` lists scenarios with metadata
- [ ] `clavain-cli scenario-run <pattern> [--sprint=<id>]` spawns an executor agent that follows scenario steps against the actual codebase, recording trajectories as CXDB turns (`clavain.scenario.v1`)
- [ ] `clavain-cli scenario-generate --from-prd <path>` generates holdout scenarios from PRD/spec files (spec-derived, not failure-derived)
- [ ] `clavain-cli scenario-validate` checks all scenarios against schema
- [ ] Scenario run results written to `.clavain/scenarios/satisfaction/run-<id>.json`
- [ ] Agents never write to `holdout/` — enforced by policy-check

**Scenario YAML v1 schema:**
```yaml
schema_version: 1
id: scenario-001
intent: "User can complete checkout with a valid credit card"
mode: behavioral  # static | behavioral
setup:
  - "Application running with test database"
  - "User authenticated as test-buyer"
steps:
  - action: "Navigate to cart"
    expect: "Cart shows 2 items"
    type: llm-judge  # llm-judge | exact | regex | shell
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

### F4: Satisfaction Scoring + Closed-Loop Calibration

**What:** LLM-as-judge satisfaction scoring with full closed-loop calibration and sprint gate integration.

**Acceptance criteria:**
- [ ] `clavain-cli scenario-score <run-id>` invokes LLM judges on scenario trajectories
- [ ] Multi-evaluation: each scenario scored by 3 judges (fd-user-product, fd-correctness, fd-safety), median score used to reduce non-determinism
- [ ] Output: `satisfaction.json` with per-criterion scores, overall score (0.0-1.0), judge_model_version, trajectory CXDB reference, judge rationale
- [ ] Satisfaction scores recorded as CXDB turns (`clavain.satisfaction.v1`) with sprint outcome field (merged/reverted/abandoned) for calibration
- [ ] **Stage 1:** Default threshold 0.7, configurable in `.clavain/budget.yml`
- [ ] **Stage 2:** All scores + sprint outcomes collected in CXDB
- [ ] **Stage 3:** `clavain-cli scenario-calibrate` reads historical scores + outcomes, computes project-specific optimal threshold (same pattern as `calibrate-phase-costs`)
- [ ] **Stage 4:** Calibrated threshold used when available, 0.7 as fallback when history is insufficient (< 20 sprints)
- [ ] Gate: sprint cannot advance to Ship unless holdout satisfaction >= threshold
- [ ] Gate checks for holdout access violations — invalidates scores from contaminated sprints
- [ ] Gate respects `CLAVAIN_SKIP_GATE` with auditable reason
- [ ] Judge failure handling: timeout after 60s per scenario, bypass with warning after 3 consecutive failures (sprint not blocked on judge unavailability)
- [ ] `scenario-score --summary` outputs pass/fail counts and aggregate satisfaction

**Satisfaction score schema:**
```json
{
  "clavain.satisfaction.v1": {
    "bead_id": "string",
    "scenario_id": "string",
    "overall_score": "float64",
    "per_criterion_scores": "map<string, float64>",
    "judge_model_version": "string",
    "judge_agent": "string",
    "trajectory_context_id": "uint64",
    "sprint_outcome": "string",
    "holdout": "bool",
    "timestamp": "uint64"
  }
}
```

### F5: Evidence Pipeline Wiring

**What:** Wire existing Interverse plugins into a unified evidence pipeline that feeds CXDB. Auto-generated scenarios from failures go to dev only; spec-derived scenarios go to holdout.

**Acceptance criteria:**
- [ ] Interspect profiler events recorded as CXDB turns (`clavain.evidence.v1`) via hook integration
- [ ] Interject scan findings convertible to dev scenario steps via `clavain-cli evidence-to-scenario <finding-id>` (writes to `dev/` only, never `holdout/`)
- [ ] Flux-drive review findings that indicate regressions auto-create dev scenarios (not holdout)
- [ ] Interstat token data attached to dispatch turns in CXDB blob CAS
- [ ] Sprint failure trajectories auto-generate evidence packs at `.clavain/evidence/<case>/`
- [ ] Evidence pack manifest: `manifest.yml` with provenance, type, replay instructions
- [ ] `scenario-generate --from-prd` creates holdout scenarios from specifications (spec-derived, independent of agent failure history)

**Evidence type schema:**
```json
{
  "clavain.evidence.v1": {
    "bead_id": "string",
    "source_plugin": "string",
    "evidence_type": "string",
    "session_id": "string",
    "phase": "string",
    "blob_hash": "bytes32",
    "timestamp": "uint64"
  }
}
```

### F6: Agent Capability Policies + Holdout Enforcement

**What:** Policy framework with defense-in-depth holdout enforcement: context exclusion (preventive) + audit trail (detective).

**Acceptance criteria:**
- [ ] `.clavain/policy.yml` schema defining per-phase tool permissions and file path denylists
- [ ] `clavain-cli scenario-policy-check <agent> <action>` returns allow/deny with reason (renamed from `policy-check` post sylveste-qdqr to free `policy` namespace for authz)
- [ ] `clavain-cli scenario-policy-show` displays current policy in human-readable format
- [ ] **Preventive:** SessionStart hook excludes `.clavain/scenarios/holdout/` from agent context during Build phase (implementation agents don't see holdout files)
- [ ] **Detective:** All holdout file access during Build phase recorded as CXDB turns (`clavain.policy_violation.v1`)
- [ ] **Consequence:** `enforce-gate` queries for holdout access violations and invalidates satisfaction scores from contaminated sprints
- [ ] Validation agents granted full access during quality-gates phase
- [ ] Policy uses Intercore phase state (not agent self-report) for phase determination
- [ ] Minimum hardcoded holdout denial ships with F3 (before full policy framework in F6)

**Policy violation schema:**
```json
{
  "clavain.policy_violation.v1": {
    "bead_id": "string",
    "agent_name": "string",
    "phase": "string",
    "action": "string",
    "target": "string",
    "policy_rule": "string",
    "timestamp": "uint64"
  }
}
```

## Non-goals

- **Autarch UI integration:** Autarch consuming CXDB/scenario data is future work. This PRD covers the substrate only.
- **Graph pipeline orchestration:** Linear sprint with CXDB forking is sufficient. Attractor-mode graph pipelines (iv-wbh) are deferred.
- **DTU-lite behavioral mocks:** API mock generation (iv-2li) is a separate skill, not part of the substrate.
- **Semantic porting:** Entirely separate domain (iv-d32), deferred.
- **CXDB React frontend deployment:** The CXDB server + Go SDK are required; the React UI is optional tooling for debugging.
- **Behavioral scenario test harness:** v1 executor spawns an LLM agent; a deterministic test harness (containerized execution, fixture management) is future work.

## Dependencies

- **CXDB cross-compilation CI:** GitHub Actions workflow that builds CXDB for 4 targets from Rust source. Must be set up before F1 can ship.
- **clavain-cli Go module:** CXDB Go SDK adds 3 new dependencies (uuid, msgpack, blake3). Must verify no conflicts with existing `go.mod`.
- **Flux-drive agents:** F4 (satisfaction scoring) reuses `fd-user-product`, `fd-correctness`, `fd-safety`. These already exist in interflux.
- **Intercore gate rules:** F4 adds a new gate rule (satisfaction threshold). Must coordinate with existing gate infrastructure in `cmdEnforceGate`.

## Resolved Questions (from flux-drive review)

1. **CXDB binary distribution:** Sylveste cross-compiles and hosts binaries. No upstream PR dependency.
2. **Type registry bootstrapping:** Ship `clavain-types.json` in plugin. Register all bundles during `cxdb-start` before health check passes. No lazy registration.
3. **CXDB data lifecycle:** Defer retention policy. Blob CAS deduplicates naturally. Add compaction when storage becomes a measured problem.
4. **Scenario authoring:** Failure-derived → dev (auto). Spec-derived → holdout (`scenario-generate --from-prd`). Human-curated → holdout (manual). Agents never write holdout.
5. **Satisfaction calibration:** Yes — all 4 stages of closed-loop pattern ship in F4. `scenario-calibrate` command reads history and adjusts threshold.
6. **CXDB architecture:** Hybrid — Intercore owns state, CXDB owns blobs, DAG spine derived from ic events.
7. **Holdout enforcement:** Context exclusion (preventive) + post-hoc audit (detective). Score invalidation on contamination.

## Success Metrics

- **Holdout scenario coverage:** >= 1 holdout scenario per active project within 30 days of adoption
- **Satisfaction gate catch rate:** Regressions caught by holdout gate / total post-merge regressions, measured at T+90 days
