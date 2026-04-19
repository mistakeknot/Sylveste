---
artifact_type: prd
bead: sylveste-s3z6
stage: design
---
# PRD: FluxBench Closed-Loop Model Discovery

## Problem

interflux qualifies models through manual observation with no structured measurement, no feedback to the model catalog, and no automated detection of model degradation or new candidates. Shadow run metrics exist in the registry schema (format_compliance, finding_recall, severity_accuracy) but no scoring engine, qualification loop, or write-back mechanism is implemented.

## Solution

FluxBench — a custom benchmark suite measuring whether models produce useful structured review findings from domain-specific agent prompts. Scores flow back to AgMoDB via store-and-forward, interrank natively surfaces FluxBench-scored models, and drift detection + proactive discovery close the loop autonomously.

## Architecture

```
interflux qualification run
        │
        ▼
  FluxBench scorer (local)
        │
        ▼
  results.jsonl (store-and-forward)
        │
        ├──▶ model-registry.yaml (local cache, immediate)
        │
        └──▶ AgMoDB repo commit (periodic, via fluxbench-sync.sh)
                    │
                    ▼
              interrank snapshot refresh
                    │
                    ▼
              recommend_model includes FluxBench scores
```

## Features

### F1: FluxBench Metric Definitions + Local Scoring Engine

**What:** Implement the 9-metric FluxBench scoring engine that evaluates qualification run outputs against baseline/ground-truth findings, producing structured JSON results.

**Input contract:** `fluxbench-score.sh` reads a structured JSON file (`qualification-output.json`) containing: model_slug, findings array (each with severity, location, description, category), run metadata (agent_type, baseline_model, timestamp). This format is produced by `fluxbench-qualify.sh` (F5) and `fluxbench-drift.sh` (F4), which extract and normalize findings from the standard peer-findings JSONL + markdown output.

**Acceptance criteria:**
- [ ] 9 metrics defined in `interverse/interflux/config/flux-drive/fluxbench-metrics.yaml` (5 core gates + 4 extended)
- [ ] Core gate **default** thresholds: format-compliance (binary, >=95%), finding-recall (severity-weighted, >=60%), false-positive-rate (<=20%), severity-accuracy (>=70%), persona-adherence (>=0.6). These are configurable defaults — F2's `fluxbench-calibrate.sh` overrides them with empirically derived values written to `fluxbench-thresholds.yaml`
- [ ] Extended: instruction-compliance, cross-family-disagreement-rate, latency-p50, token-efficiency
- [ ] Scoring script `interverse/interflux/scripts/fluxbench-score.sh` reads `qualification-output.json` (see input contract above), compares against baseline, outputs FluxBench result JSON
- [ ] **Caller contract:** `fluxbench-score.sh` is invoked by: (a) `fluxbench-qualify.sh` during qualification runs, (b) `fluxbench-drift.sh` during drift shadow runs, (c) `fluxbench-calibrate.sh` during threshold calibration. No other callers.
- [ ] Weighted recall uses P0=4x, P1=2x, P2=1x, P3=0.5x — missing any P0 auto-fails regardless of aggregate. Severity weights are configurable in `fluxbench-metrics.yaml` (empirical derivation from production data is a Phase 2 refinement)
- [ ] Format-compliance is binary gate (>=95% pass, <95% fail), not included in weighted scoring
- [ ] Results written to `interverse/interflux/data/fluxbench-results.jsonl` — **all writes use flock** (`flock -x results.lock`) to prevent interleaved lines from concurrent runs
- [ ] `model-registry.yaml` updates use **atomic write** pattern: write to `.tmp`, validate YAML, `mv` to replace. All writers (`fluxbench-score.sh`, `fluxbench-drift.sh`, `fluxbench-qualify.sh`) acquire `flock -x registry.lock` before read-modify-write
- [ ] `model-registry.yaml` updated with FluxBench scores on qualification (extends existing `format_compliance`, `finding_recall`, `severity_accuracy` fields + adds 6 new fields)

**Dependencies:** F2 (needs fixtures for calibration baseline)

**Key files:**
- New: `config/flux-drive/fluxbench-metrics.yaml`, `config/flux-drive/fluxbench-thresholds.yaml`, `scripts/fluxbench-score.sh`, `data/fluxbench-results.jsonl`
- Modified: `config/flux-drive/model-registry.yaml` (schema extension)

### F2: Qualification Test Fixtures

**What:** Create 5-10 standardized test documents with human-annotated ground-truth findings that serve as the model-independent calibration anchor for FluxBench scoring.

**Acceptance criteria:**
- [ ] 5+ test fixtures in `interverse/interflux/tests/fixtures/qualification/` with known ground-truth findings
- [ ] Each fixture: source document + `ground-truth.json` (findings with severity, location, description)
- [ ] Fixtures cover multiple agent types: checker (style/naming), analytical (architecture/design), judgment (security/race-conditions)
- [ ] At least 2 fixtures with P0 findings, 3 with mixed P1-P3
- [ ] Ground-truth validated by human annotation (not Claude-generated baseline alone)
- [ ] README documenting fixture format and how to add new fixtures
- [ ] Calibration script `scripts/fluxbench-calibrate.sh` runs all fixtures against Claude baseline, computes threshold baselines, and writes derived thresholds to `config/flux-drive/fluxbench-thresholds.yaml` (overrides F1 defaults)
- [ ] Minimum inter-rater reliability: fixtures used in core gate calibration require kappa >= 0.7 or dual-annotator agreement on severity

**Dependencies:** None (can start independently)

### F3: AgMoDB Write-Back (Store-and-Forward)

**What:** Persist FluxBench results locally and periodically commit them to the AgMoDB repo as `externalBenchmarkScores` entries, making FluxBench data available in interrank snapshots.

**Acceptance criteria:**
- [ ] Local persistence: `data/fluxbench-results.jsonl` with schema matching AgMoDB `externalBenchmarkScores` format
- [ ] 9 `benchmarkDefinition` entries added to AgMoDB with `category: "fluxbench"`, `source: "interflux-qualification"`, `freshnessType: "continuous"`
- [ ] Sync script `scripts/fluxbench-sync.sh` reads unsent results from JSONL, writes to AgMoDB repo format, commits
- [ ] Sync script idempotent — re-running doesn't duplicate entries (keyed on `qualification_run_id`)
- [ ] Store-and-forward pattern: scoring works when AgMoDB unreachable; sync catches up later
- [ ] `relevantUseCases: ["code review", "multi-agent review", "structured output", "agent"]` on all FluxBench benchmarks

**Dependencies:** F1 (needs result format), AgMoDB repo access

**Key constraint:** AgMoDB has no REST write API. Current ingest path is git-committed JSONL from scrapers. FluxBench uses the same path — interflux writes JSONL, `fluxbench-sync.sh` commits to AgMoDB repo.

### F4: Drift Detection (Sample + Trigger)

**What:** Continuous requalification via sample-based monitoring (1-in-N reviews) plus version-triggered requalification on model updates. Detects both silent provider updates and explicit version bumps.

**Acceptance criteria:**
- [ ] Sample-based: every Nth review (N=10, configurable in budget.yaml), shadow-run 1 active non-Claude agent against Claude baseline
- [ ] Sampling guarantee: force shadow if model unsampled in 2*N reviews (max gap = 20 for N=10)
- [ ] Shadow run outputs compared against model's qualified FluxBench baseline via `fluxbench-score.sh`
- [ ] **Frozen baseline:** On qualification, snapshot the model's FluxBench scores as `qualified_baseline` in `model-registry.yaml`. This baseline is immutable — drift is always measured against the original qualification scores, not running averages. Prevents silent ratcheting.
- [ ] Drift flag: any core metric drops >15% from `qualified_baseline` → model demoted to `qualifying`
- [ ] Drift hysteresis: clear only when recovered to within 5% of `qualified_baseline` (prevents oscillation)
- [ ] **Correlated drift detection:** If >=50% of active models flag drift in the same sampling window, treat as baseline shift (not model degradation). Log alert, do NOT mass-demote. Operator must re-run `fluxbench-calibrate.sh` to re-anchor.
- [ ] All registry writes in drift.sh use atomic write + flock pattern (same as F1)
- [ ] Trigger-based: on SessionStart, compare active models' `qualified_date` against interrank snapshot `releaseDate` — version bump → trigger full requalification
- [ ] Drift event written to `fluxbench-results.jsonl` with `metadata.trigger: "drift-sample"` or `"drift-version"`
- [ ] Demoted model replaced by Claude for that agent tier until requalification passes

**Dependencies:** F1 (scoring), F2 (baseline), existing cross-model dispatch infrastructure

**Key files:**
- New: `scripts/fluxbench-drift.sh` (drift check logic)
- Modified: `hooks/session-start.sh` (version comparison), `config/flux-drive/budget.yaml` (drift config)

### F5: Proactive Model Surfacing

**What:** Two-mode discovery: SessionStart hook polls interrank for new candidates above FluxBench-relevant thresholds (awareness), weekly scheduled agent runs full auto-qualification pipeline (action).

**Acceptance criteria:**
- [ ] SessionStart hook: query interrank `recommend_model` for code-review task, compare against `model-registry.yaml` — surface new models not in registry
- [ ] Hook output: one-line awareness message (e.g., "interrank: 2 new model candidates (deepseek-v4, qwen-3.1)")
- [ ] Hook is zero-cost: single MCP query, no qualification work in session startup
- [ ] **Weekly qualification agent spec:** `agents/fluxbench-discover.md` defines the agent prompt, tools required (interrank MCP), and autonomy level. Agent is dispatched via `clavain-cli schedule` or `/clavain:schedule`. The agent: (a) calls `discover-models.sh` to generate interrank queries, (b) executes the MCP calls, (c) runs `fluxbench-qualify.sh` for each candidate, (d) updates registry, (e) creates beads for qualified candidates.
- [ ] `scripts/fluxbench-qualify.sh`: runs a candidate model against all F2 fixtures, normalizes output to `qualification-output.json` (F1 input contract), invokes `fluxbench-score.sh`, writes results to JSONL
- [ ] Auto-qualification: candidates passing all 5 core gates → promoted to `auto-qualified` (not `qualified`) in model-registry.yaml. `auto-qualified` models are eligible for challenger slot but require operator confirmation for `qualified` status. One-field promotion: `bd set-state` or operator edits registry.
- [ ] Candidates failing → marked `candidate` with failure reason and timestamp, retried on next weekly cycle
- [ ] Creates bead if any candidate auto-qualifies (for human awareness)
- [ ] **Weekly budget ceiling:** max N candidates per weekly cycle (N=5 default, configurable in `budget.yaml`). If qualifying pool > N, score-rank and qualify top N only. Prevents unbounded weekly cost as candidate pool grows.
- [ ] Version-triggered requalification on SessionStart is **deferred** (queued, not synchronous) — writes a `requalification_needed` flag to registry, weekly agent picks it up. Preserves zero-cost SessionStart guarantee.

**Dependencies:** F1 (scoring), F2 (fixtures), F6 (interrank integration for discovery queries)

**Key files:**
- Modified: `hooks/session-start.sh` (awareness query + deferred requalification flag), `scripts/discover-models.sh` (qualification integration)
- New: `scripts/fluxbench-qualify.sh` (auto-qualification runner), `agents/fluxbench-discover.md` (weekly agent spec)

### F6: interrank TASK_DOMAIN_MAP Integration

**What:** Add FluxBench category affinity to interrank's recommendation engine so `recommend_model` natively includes FluxBench scores for code-review-flavored queries.

**Acceptance criteria:**
- [ ] `TASK_DOMAIN_MAP` in `interverse/interrank/src/recommend.ts` updated: add `"fluxbench"` to affinity list for `"code review"`, `"agent"`, `"automation"` archetypes
- [ ] FluxBench benchmarks (with `category: "fluxbench"`) receive domain affinity boost (weight 2) for matching queries
- [ ] `recommend_model` response includes FluxBench-scored models when query matches code review / agent use case
- [ ] `recommend_benchmarks` returns FluxBench entries for relevant task descriptions
- [ ] Backwards-compatible: queries without FluxBench data continue to work (graceful absence)

**Dependencies:** F3 (FluxBench data must exist in snapshot)

**Key file:** `interverse/interrank/src/recommend.ts` (lines 12-28, TASK_DOMAIN_MAP)

### F7: Challenger Slot Mechanism

**What:** Reserve 1 agent slot in flux-drive reviews for the highest-scoring unqualified candidate, preventing preferential attachment to incumbents.

**Acceptance criteria:**
- [ ] Triage allocates 1 slot to highest-FluxBench-scoring `qualifying` or `auto-qualified` model (if any exist in registry)
- [ ] **Prerequisite: cross-model dispatch must support mixed-mode** — challenger slot runs in `enforce` mode while other slots remain in current mode. This is an infrastructure dependency, not just config.
- [ ] Challenger runs alongside qualified agents in actual reviews (not synthetic)
- [ ] Challenger findings included in peer findings but flagged with `[challenger]` tag
- [ ] **Pre-inclusion filter:** Before first real dispatch, challenger must pass format-compliance gate (>=95%) on 2 synthetic fixture runs. Prevents malformed output from contaminating peer findings.
- [ ] Challenger FluxBench metrics updated from each real review (accumulates shadow data)
- [ ] After 10+ challenger runs: auto-evaluate qualification gate — promote to `qualified` or reject to `candidate` with failure reason. **Early exit:** If challenger passes all 5 gates after run 5 with >20% margin, fast-track promotion (don't wait for 10).
- [ ] **Stale challenger cleanup:** If a challenger accumulates 20+ runs without passing, demote to `rejected` and remove from challenger rotation. Operator notification via bead.
- [ ] Challenger slot configurable in `budget.yaml` (`challenger_slots: 1`, integer — allows 0 to disable or 2+ for higher exploration)
- [ ] Safety: challenger never assigned to `fd-safety` or `fd-correctness` roles — **enforced in triage at role-assignment time** (check exclusion list before assignment, not after)
- [ ] If no qualifying candidates exist, slot used by next-best qualified model (no waste)

**Dependencies:** F1 (scoring), F4 (drift detection feeds the qualifying pool), cross-model dispatch in mixed mode (`agent-roles.yaml`), **mixed-mode dispatch infrastructure** (new dependency)

**Key files:**
- Modified: `config/flux-drive/agent-roles.yaml` (challenger tier), `config/flux-drive/budget.yaml` (challenger config)
- Modified: triage logic (wherever agent dispatch decisions happen)

## Delivery Order

```
F2 (fixtures) ──────────────────────┐
                                    ▼
F1 (scoring engine) ◄──────── F2 calibration
        │
        ├──▶ F3 (AgMoDB write-back)
        │         │
        │         └──▶ F6 (interrank integration)
        │
        ├──▶ F4 (drift detection)
        │
        └──▶ F5 (proactive surfacing)
                  │
                  └──▶ F7 (challenger slot)
```

**Phase 1 (MVP):** F2 → F1 → local registry update only (measurement validated)
**Phase 2 (feedback):** F3 (AgMoDB write-back, after metrics proven stable) + F4 (drift detection)
**Phase 3 (automation):** F5 (proactive surfacing) + F6 (interrank integration)
**Phase 4 (optimization):** F7 (challenger slot, requires mixed-mode dispatch)

## Non-goals

- **Real-time write API for AgMoDB**: Store-and-forward via git commit is sufficient. REST API is a separate AgMoDB concern.
- **Cross-project FluxBench**: Only interflux reports FluxBench results. Other tools can consume via interrank but don't produce.
- **Finding survival rate tracking**: Requires integration with beads/git to detect which findings led to code changes. Deferred to v2.
- **Persona adherence heuristic proxy**: LLM-as-judge (Haiku) is the scoring method. No cheaper heuristic for v1.

## Dependencies

| Dependency | Owner | Status |
|-----------|-------|--------|
| `model-registry.yaml` schema | interflux | Exists (needs extension) |
| `externalBenchmarkScores` format | AgMoDB | Exists (34+ scrapers use it) |
| interrank `recommend_model` | interrank | Implemented |
| `TASK_DOMAIN_MAP` | interrank | Implemented (needs `fluxbench` addition) |
| Cross-model dispatch | interflux | Shadow mode implemented |
| **Mixed-mode dispatch** | interflux | **Not implemented** — needed for F7 challenger slot |
| `discover-models.sh` | interflux | Exists (outputs queries, no execution) |
| AgMoDB repo write access | AgMoDB | Needed for F3 sync |

## Open Questions

1. **AgMoDB repo auth for fluxbench-sync.sh**: SSH key or token? Who owns the AgMoDB repo pipeline?
2. **Persona adherence LLM-judge cost**: Haiku per-run cost for persona scoring — acceptable at qualification volume?
3. **Challenger slot finding weight**: Should challenger findings count toward convergence scores, or be informational only?
4. **Calibration frequency**: How often should FluxBench thresholds be re-derived from the growing ground-truth set?
5. **Multi-provider latency measurement**: `fluxbench-latency-p50` varies by provider infrastructure — is this a fair comparison metric?

## Review-Incorporated Changes (from flux-drive review 2026-04-07)

### P0 resolutions

1. **ARCH-01/ARCH-02 (scoring caller + input format):** Added input contract and caller contract to F1. Defined `qualification-output.json` schema. Named all callers: `fluxbench-qualify.sh`, `fluxbench-drift.sh`, `fluxbench-calibrate.sh`.
2. **FB-01 (concurrent JSONL writes):** Added flock requirement to F1 AC for all JSONL writes.
3. **FB-02 (registry TOCTOU):** Added atomic write pattern (write .tmp, validate, mv) with flock for all registry writers.
4. **FB-03 (hysteresis baseline ratchet):** Added frozen `qualified_baseline` concept — immutable snapshot at qualification time, drift always measured against it.
5. **UP-01 (challenger dispatch):** Added mixed-mode dispatch as explicit F7 dependency. Noted as "Not implemented" in dependencies table.
6. **UP-02 (weekly agent unspecified):** Added `agents/fluxbench-discover.md` agent spec to F5. Defined the full agent workflow.

### Key P1 resolutions

- **Threshold calibration inversion (5-agent convergence):** F1 thresholds are now configurable defaults. F2's calibrate script writes `fluxbench-thresholds.yaml` that overrides them. Causal direction: F2 → F1 (not F1 → F2).
- **Auto-qualification autonomy (ARCH-06):** Added `auto-qualified` intermediate status between `candidate` and `qualified`. Requires operator confirmation for full promotion.
- **Challenger containment (RES-2):** Added pre-inclusion filter (2 synthetic fixture runs) and stale challenger cleanup (20-run cap). Added early exit for clearly passing challengers.
- **Correlated drift (S1, RES-4):** Added correlated drift detector — >=50% simultaneous drift flags trigger baseline-shift alert, not mass-demotion.
- **Version-trigger SessionStart (FB-05):** Deferred version-triggered requalification to async flag, preserving zero-cost SessionStart.
- **Weekly budget ceiling (RES-5):** Added max N candidates per cycle to prevent unbounded cost.
- **Delivery reordering (DEC-3):** Moved F3 (AgMoDB write-back) from Phase 1 to Phase 2 — validate metrics locally before publishing externally. Added Phase 4 for F7 (blocked on mixed-mode dispatch).
- **Inter-rater reliability (DEC-6):** Added kappa >= 0.7 requirement for fixture annotations used in core gate calibration.

## Success Metrics

- Models with FluxBench scores appear in `recommend_model` results for code-review queries within 1 snapshot cycle
- Drift detection catches a simulated 20% regression within 2*N reviews
- Auto-qualification pipeline promotes a valid candidate end-to-end without human intervention
- FluxBench scoring agrees with human judgment on ground-truth fixtures at >=85% accuracy
