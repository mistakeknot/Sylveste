---
artifact_type: flux-drive-synthesis
subject_prd: docs/prds/2026-04-07-fluxbench-closed-loop-model-discovery.md
bead: sylveste-s3z6
reviewed_date: 2026-04-07
agents: [fd-architecture, fd-user-product, fd-correctness, fd-systems, fd-decisions, fd-resilience]
---

# Synthesis: FluxBench Closed-Loop Model Discovery PRD Review

## Verdict Summary

**Verdict: NEEDS_ATTENTION** (2 P0s block implementation)

| Agent | Total | P0 | P1 | P2 | P3 | Status | Risk |
|-------|-------|----|----|----|----|--------|------|
| fd-architecture | 12 | 2 | 4 | 4 | 2 | NEEDS_ATTENTION | Boundary violations, unspecified ownership |
| fd-user-product | 12 | 2 | 4 | 4 | 2 | NEEDS_ATTENTION | Flow gaps, unimplemented dependencies |
| fd-correctness | 12 | 3 | 4 | 3 | 2 | NEEDS_ATTENTION | Concurrency, data integrity, TOCTOU |
| fd-systems | 7 | 0 | 3 | 3 | 1 | NEEDS_ATTENTION | Feedback loops, equilibrium traps, over-adaptation |
| fd-decisions | 7 | 0 | 2 | 3 | 2 | NEEDS_ATTENTION | Ungrounded thresholds, reversibility, interaction |
| fd-resilience | 7 | 0 | 2 | 3 | 2 | NEEDS_ATTENTION | Baseline versioning, containment, decay |

**Summary:** 7 P0 findings block implementation. 19 P1s require resolution before Phase 2. 20 P2s should resolve before Phase 3. The system is well-conceived on the happy path but brittle under correlated failures, missing critical pre-conditions, and has unspecified ownership on key state mutations.

---

## Critical Blocking Issues (P0)

### 1. Scoring Engine Caller Unspecified (ARCH-01, ARCH-02)

**Convergence:** 2 agents (fd-architecture, implicit in fd-user-product UP-02)

**Issue:** `fluxbench-score.sh` is the scoring engine, but no feature specifies which script invokes it during a standard qualification run. F1 says "model-registry.yaml updated with FluxBench scores on qualification" but does not name who triggers the update.

Additionally, `fluxbench-score.sh` "reads qualification run output JSON" but the current qualification pipeline produces peer-findings JSONL and agent markdown files, not a JSON blob. The format contract is undefined.

**Smallest Fix:** 
- F1 acceptance criteria: "Called by `[specific script/hook]` when qualification run completes"
- F1 must define the input JSON schema (field names, types, source)
- F2's calibration script cannot proceed until F1's input schema is stable

**Severity:** P0 — Feature cannot be wired without answering "what calls this?"

---

### 2. Concurrent JSONL Write Corruption (FB-01)

**Agent:** fd-correctness

**Issue:** `fluxbench-results.jsonl` is written by multiple scripts (`fluxbench-score.sh`, `fluxbench-qualify.sh`) without serialization. Concurrent qualification runs can interleave JSON lines, producing invalid output. The existing `findings-helper.sh` uses `flock` for safety; the PRD must require all new writers to do the same.

**Pattern exists:** `findings-helper.sh write` already has the correct implementation.

**Smallest Fix:** Add to F1/F3/F4 acceptance criteria: "All JSONL writes use `findings-helper.sh write` or equivalent `flock`-protected method."

**Severity:** P0 — Data corruption in persistent results store.

---

### 3. Registry TOCTOU Race (FB-02)

**Agent:** fd-correctness

**Issue:** `model-registry.yaml` is read-modified-written by multiple paths (`fluxbench-score.sh`, `fluxbench-drift.sh`, `fluxbench-qualify.sh`, F5 proactive surfacing) without atomic-swap. A concurrent drift detection + weekly qualification can both read the same registry state, compute against stale baselines, and write conflicting mutations.

**Scenario:** Weekly qualification reads registry at T0, starts computing scores. At T1, drift detection reads the same file, demotes a model, writes back. At T2, weekly qualification finishes and overwrites the drift demotion with its earlier snapshot.

**Smallest Fix:** Serialize all registry writes with `flock` on a `model-registry.yaml.lock` file. Pattern: acquire lock → read → modify → write to temp → `mv` temp → original → release lock.

**Severity:** P0 — Registry is the nerve center; stale reads corrupt the entire system state.

---

### 4. Hysteresis Baseline Ratchets Downward (FB-03)

**Agent:** fd-correctness

**Issue:** F4 drift detection uses a "qualified baseline" to detect degradation (>15% drop) and a hysteresis band to clear the flag (within 5% recovery). The PRD does not specify whether the baseline is frozen at qualification time or read from current registry values.

If the baseline drifts (i.e., when `fluxbench-qualify.sh` updates `finding_recall` from 0.82 to 0.78 after new shadow runs), the threshold for demotion silently increases. A model can ratchet down in small steps (0.82 → 0.78 → 0.73 → 0.68) without ever crossing the 15% threshold because the baseline moves with it.

**Smallest Fix:** Freeze the baseline at qualification time in a separate field (`baseline_finding_recall`, `baseline_format_compliance`, etc.). Both demote and clear checks read only from frozen fields.

**Severity:** P0 — Silent integrity failure in the drift detection state machine.

---

### 5. Weekly Auto-Qualification Agent Unspecified (UP-02)

**Agent:** fd-user-product

**Issue:** F5's acceptance criteria require a "weekly scheduled agent" that orchestrates MCP calls and invokes `fluxbench-qualify.sh`. The PRD treats this as a given, but the agent does not exist and is not defined anywhere. There is no agent spec, prompt, tool list, or bead.

`discover-models.sh` outputs query specs; it cannot execute them. The agent that interprets those specs and invokes qualification is out of scope of the PRD.

**Smallest Fix:** Define the weekly agent explicitly in F5 scope: agent type (Claude Code background agent or cron script?), tool access required, orchestration contract with `discover-models.sh`.

**Severity:** P0 — Without this agent, F5 delivers no action path, only passive awareness.

---

### 6. Challenger Slot Depends on Unimplemented Mixed-Mode Dispatch (UP-01)

**Agent:** fd-user-product

**Issue:** The CUJ friction list states directly: "Cross-model dispatch is in shadow mode. Challenger slot needs dispatch in `enforce` mode for the challenger position, while rest stays in `shadow`. Mixed-mode dispatch isn't implemented yet."

F7 (Phase 3) has a hard dependency on mixed-mode dispatch, which is not a FluxBench feature and is not tracked in this epic.

**Smallest Fix:** Add mixed-mode dispatch as an explicit F0 prerequisite in the epic dependency table, or create a separate blocking bead before F7 can start.

**Severity:** P0 — Implementers will reach Phase 3 and discover the platform is not ready.

---

### 7. Drift Demotion Ownership Unspecified (ARCH-05)

**Agent:** fd-architecture

**Issue:** F4 specifies "drift flag: any core metric drops >15% → model demoted to `qualifying`" but does not name the owner of the registry mutation. The drift detection script (`fluxbench-drift.sh`) writes a drift event to JSONL; the registry status write is unattributed.

This is a boundary violation: the detection event and the state mutation belong to the same transition, but the PRD splits them without naming the bridge.

**Smallest Fix:** Assign registry mutation ownership explicitly. E.g., "On drift event in fluxbench-results.jsonl, session-start.sh reads and demotes model in registry" or "fluxbench-drift.sh owns the demotion write."

**Severity:** P0 — Detection without action is observation without consequence. The system detects drift but does not change behavior.

---

## High-Risk Issues (P1) — 19 findings

### Architecture & Ownership

| ID | Agent | Title | Fix |
|----|----|-------|-----|
| ARCH-03 | fd-architecture | Threshold calibration still circular | Make F1 thresholds configurable; F2 output drives final values |
| ARCH-04 | fd-architecture | Cross-repo git write unresolved | Auth, repo access, conflict resolution spec required before F3 ships |
| ARCH-06 | fd-architecture | Scheduled agent bypasses flux-drive protocol | Add `auto-qualified` intermediate status before `qualified` promotion |
| ARCH-09 | fd-architecture | LLM-as-judge cannot run in script | Resolve execution context conflict between F1 (session) and F5 (script) |

### User & Product Flow

| ID | Agent | Title | Fix |
|----|----|-------|-----|
| UP-03 | fd-user-product | Drift demotion invisible to operator | Specify user-visible signal, channel, actionability |
| UP-04 | fd-user-product | Persona adherence LLM cost undeclared | Bound cost or move persona adherence to extended metrics |
| UP-05 | fd-user-product | Failing challenger has no exit path | Define retry caps, expiry, operator notification |
| UP-06 | fd-user-product | Version-triggered requalification has no deferral | Add `--skip-requalification` or configurable defer window |

### Correctness & Concurrency

| ID | Agent | Title | Fix |
|----|----|-------|-----|
| FB-04 | fd-correctness | Challenger promotion gate raceable | Lock-protect promotion decision; use sentinel flag `challenger_evaluation_in_progress` |
| FB-05 | fd-correctness | SessionStart version-trigger not zero-cost | Decouple F5 awareness (zero-cost) from F4 trigger (async work) |
| FB-06 | fd-correctness | Sync idempotency relies on undefined ID | Generate `qualification_run_id` as UUID v4 at start of each run |
| FB-07 | fd-correctness | Challenger safety-floor bypass | Enforce exclusion at allocation, not dispatch; maintain hardcoded `CHALLENGER_EXCLUDED_ROLES` |

### Systems Dynamics

| ID | Agent | Title | Fix |
|----|----|-------|-----|
| S1 | fd-systems | Demotion storm with no escape valve | Model correlated drift as system-level signal; pause requalification on storm detection |
| S2 | fd-systems | Measuring Claude-similarity, not quality | Introduce human-only (non-Claude) ground-truth fixtures; rotate baseline anchors |
| S3 | fd-systems | Preferential attachment hurts challengers | Account for data density asymmetry in promotion gate thresholds |

### Decision Quality

| ID | Agent | Title | Fix |
|----|----|-------|-----|
| DEC-1 | fd-decisions | Gate thresholds ungrounded | Mark thresholds as `[provisional]`; calibrate from F2 results before F1 ships |
| DEC-2 | fd-decisions | Stopping rules unrelated (15% drift, 10+ runs) | Instrument pilot; derive both from variance analysis and confidence interval theory |

### Resilience

| ID | Agent | Title | Fix |
|----|----|-------|-----|
| RES-1 | fd-resilience | Baseline versioning missing | Add `baseline_model_version` to every FluxBench result; plan transition path on Claude version bump |
| RES-2 | fd-resilience | Challenger containment unspecified | Format-check before inclusion; per-challenger timeout; early-stopping at confidence threshold |

---

## Major Issues (P2) — 20 findings

Grouped by theme:

### Integration Latency & Interaction

- **ARCH-07** (Architecture): AgMoDB snapshot latency (hours to days) invisible to F6
- **S4** (Systems): Bullwhip effect through store-and-forward → sync → snapshot refresh chain
- **DEC-5** (Decisions): Dual surfacing modes (drift + proactive) without interaction signposts
- **RES-5** (Resilience): Weekly auto-qualification budget unbounded (fixture count × candidate count compounds)

### Fixture & Calibration

- **UP-07** (User): Fixture quality criteria absent (annotator count, disagreement resolution, false-positive definition)
- **DEC-6** (Decisions): Ground-truth validated by single annotator with no inter-rater agreement
- **RES-3** (Resilience): Fixture set has no retirement path; becomes ossified baseline

### Observability & Control

- **UP-08** (User): Stuck candidates have no beads (failure tracking missing)
- **UP-09** (User): SessionStart awareness hook has no opt-out (attention tax not acknowledged)
- **UP-10** (User): Challenger tag `[challenger]` has undefined synthesis behavior
- **ARCH-08** (Architecture): Challenger wiring in SKILL.md not listed in key files
- **ARCH-10** (Architecture): Drift depends on cross-model dispatch in shadow mode

### Data Consistency

- **FB-08** (Correctness): Drift sample counter shared across sessions; 2*N guarantee unenforceable
- **FB-09** (Correctness): P0 auto-fail and weighted scoring use potentially inconsistent baselines
- **FB-10** (Correctness): Partial sync run leaves AgMoDB repo in dirty state

### Architecture & Dependencies

- **DEC-3** (Decisions): Git-commit write-back is low-reversibility bet; Phase 1 should defer F3
- **DEC-4** (Decisions): Challenger slot fixed at 1 without explore/exploit analysis
- **S5** (Systems): Time-to-promotion for new entrants grows unbounded as fleet matures

---

## Minor Issues (P3) — 11 findings

| ID | Agent | Title | Mitigation |
|----|----|-------|-----------|
| ARCH-11 | Architecture | Registry write tooling unassigned | Assign script ownership; yq writes straightforward |
| ARCH-12 | Architecture | TASK_DOMAIN_MAP boost systematic advantage | Gate boost on benchmark score, not category membership |
| UP-11 | User | 85% success metric unmeasurable | Define measurement protocol (fixture set, judges, timing) |
| UP-12 | User | F5 discovery uses un-boosted results until F6 | Document interim state; note F6 improves signal |
| FB-11 | Correctness | Weekly re-runs qualified models on stale registry | Check JSONL source-of-truth before re-running |
| FB-12 | Correctness | Version comparison reads stale snapshot | Add max-staleness policy to interrank `load.ts` |
| S6 | Systems | Fixture consensus equilibrium on Claude | Introduce non-Claude reference fixtures; monitor annotation divergence |
| S7 | Systems | Thresholds over-adapted to current conditions | Add stress test scenarios (provider storms, multi-model drift) |
| DEC-7 | Decisions | 85% metric is proxy without theory of change | Acknowledge proxy nature; set invalidation criterion (6-month survival rate) |
| RES-6 | Resilience | Scores flow out, nothing flows back | Defer threshold recalibration to v2 but acknowledge missing feedback loop |
| RES-7 | Resilience | Severity weights from convention, not data | Derive empirically from interflux qualification data before shipping |

---

## Convergent Findings & Deduplication

### Threshold Calibration (5 agents)

**Agents:** fd-architecture, fd-user-product, fd-decisions, fd-resilience (+ S2 fd-systems)

**Convergence:** F1's gate thresholds (95% format, 60% recall, 70% severity, etc.) are hardcoded in acceptance criteria **before** F2 calibration runs. The causal direction is inverted.

**Unified Recommendation:**
1. Mark all thresholds `[provisional — calibrate from F2]`
2. F2 acceptance criteria: "Run all fixtures against 3+ qualified models; publish score distribution; derive thresholds at Nth percentile"
3. F1 implementation gates only on placeholder values until F2 calibration completes

---

### F4 Drift Detection Design (4 agents)

**Agents:** fd-correctness, fd-systems, fd-decisions (+ convergence from architecture)

**Convergence:** The 15% drift threshold, 5% hysteresis, and 2*N sampling guarantee are presented as independent constants. They interact but have no shared derivation methodology.

**Unified Recommendation:**
1. Instrument a calibration run: measure FluxBench score variance on same model + same fixtures over 5-10 trials
2. Drift threshold = (mean variance + 2 std dev)
3. Hysteresis band = (mean variance + 1 std dev)
4. Both prevent oscillation on measurement noise AND prevent slow ratcheting

---

### F7 Challenger Slot (5 agents)

**Agents:** fd-architecture, fd-user-product (2), fd-correctness, fd-resilience

**Convergence:** Multiple unspecified failure modes and edge cases:
- Mixed-mode dispatch not implemented (blocker)
- Safety floor bypass possible via registry state
- No containment for malformed output
- Failing challenger has no exit path
- Promotion gate is binary cliff at 10 runs (no early stopping)

**Unified Recommendation:**
1. Add mixed-mode dispatch (F0 prerequisite)
2. Format-validation gate before findings enter peer pool
3. Hardcoded role exclusion at allocation time
4. Early stopping: if passes all gates at run 7, promote; don't wait for 10
5. Sentinel field `challenger_evaluation_in_progress` prevents double-evaluation

---

### F2 Ground-Truth Fixtures (3 agents)

**Agents:** fd-user-product, fd-decisions, fd-resilience

**Convergence:** Fixture quality is load-bearing but unspecified. No inter-annotator agreement, no dispute resolution, no retirement path.

**Unified Recommendation:**
1. Require 2 independent annotators per fixture
2. Measure Cohen's kappa; minimum 0.7 for core-gate fixtures
3. Retirement policy: fixtures with >=95% recall across all qualified models for 90 days are retired
4. Growth trigger: new domain → new fixtures required before scoring that domain

---

### F3 JSONL Sync (2 agents + context)

**Agents:** fd-correctness (2 findings), context mentions idempotency concerns

**Convergence:** Two separate correctness failures:
1. Concurrent append can corrupt JSONL
2. Idempotency key (`qualification_run_id`) generation undefined; UUID v4 generation method unspecified

**Unified Recommendation:**
1. All writers use `findings-helper.sh write` (flock-protected)
2. `fluxbench-score.sh` generates UUID v4 at start; written as first field
3. `fluxbench-sync.sh` queries AgMoDB manifest for already-committed IDs before processing

---

## Delivery Order Assessment

**Phase 1 (F2 → F1 → F3):** Correctly sequenced IF:
- F1's input schema is defined before F2 can be written
- F2 calibration runs and drives F1 thresholds (not vice versa)
- Registry write tooling is ready

**Phase 2 (F4 + F5 parallel):** Risks:
- F4 depends on cross-model dispatch exiting shadow mode (currently not scoped)
- F5's weekly agent is unspecified (no agent exists yet)
- Both compete for JSONL write path and registry lock

**Phase 3 (F6 + F7):** Risks:
- F6's value gated on AgMoDB snapshot latency (up to 48 hours)
- F7 blocks on mixed-mode dispatch infrastructure

**Recommendation:** Reorder to:
1. **F0 (Prerequisite):** Mixed-mode dispatch, weekly agent definition
2. **Phase 1:** F2 → F1 (with schema defined first) → local `model-registry.yaml` update only (defer F3 to Phase 2)
3. **Phase 2:** F4 + F5 after Phase 1 ships and F2 calibration validates baselines
4. **Phase 3:** F3 (AgMoDB sync) + F6 (interrank integration) + F7 (challenger)

Moving F3 to Phase 2 defers the irreversible AgMoDB schema commitment until FluxBench metrics are validated and stable.

---

## Overall Gate Assessment

**Validity:** 6/6 agents produced valid, well-structured reviews. All findings are substantive and cross-referenced.

**Severity Distribution:**
- P0: 7 findings (2 architecture, 2 user, 3 correctness)
- P1: 19 findings (distributed across all agents)
- P2: 20 findings (distributed across all agents)
- P3: 11 findings (lower-risk, mostly observability and measurement)

**Blocker Status:** The 7 P0 findings must be resolved before Phase 1 implementation:
1. Scoring engine caller unspecified
2. JSONL write race
3. Registry TOCTOU race
4. Hysteresis baseline ratcheting
5. Weekly agent unspecified
6. Challenger depends on unimplemented dispatch
7. Drift demotion ownership unspecified

**Gate Verdict:**
- **FAIL** on delivery as-written (P0 blockers)
- **CONDITIONAL PASS** if P0s are resolved and Phase 1 reordered to F2→F1→local registry before F3

---

## Files & Configuration Affected

**PRD:** docs/prds/2026-04-07-fluxbench-closed-loop-model-discovery.md

**Implementation Key Files (per PRD):**
- F1: `fluxbench-score.sh`, `fluxbench-metrics.yaml`
- F2: `data/fluxbench-fixtures/`, `fluxbench-calibrate.sh`
- F3: `fluxbench-sync.sh`, AgMoDB integration
- F4: `fluxbench-drift.sh`, `data/fluxbench-results.jsonl`
- F5: Weekly scheduled agent (unspecified), `discover-models.sh`
- F6: `interverse/interrank/src/TASK_DOMAIN_MAP` update
- F7: Triage step in `interflux/SKILL.md`, `agent-roles.yaml`, `budget.yaml`

**Configuration:**
- `model-registry.yaml` (new schema with 9 metrics)
- `budget.yaml` (new fields: `challenger_slot`, `requalify_on_version_bump`, etc.)
- `.beads/` (tracking)

---

## Next Steps

1. **Resolve P0s:** Assign ownership for ARCH-05 (demotion), define ARCH-01 caller, specify UP-02 agent, resolve conflicting execution contexts (ARCH-09)
2. **Calibration-first approach:** Run F2 calibration manually with 3 hand-annotated fixtures against production Claude baseline before building automation
3. **Reorder Phase 1:** Move F3 to Phase 2; Phase 1 should stop at local `model-registry.yaml` update
4. **Prerequisite work:** Start mixed-mode dispatch infrastructure; define weekly agent in parallel with F4/F5
5. **Measurement plan:** Define success metric protocol; commit 6-month evaluation gate for fixture finding-survival correlation

---

Synthesis completed: 2026-04-07
Review cycle: 6 agents, 57 findings (7 P0, 19 P1, 20 P2, 11 P3)
