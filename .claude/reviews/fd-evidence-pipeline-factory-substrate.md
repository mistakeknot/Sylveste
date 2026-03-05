# Evidence Pipeline Review: Factory Substrate PRD

**Reviewer:** fd-evidence-pipeline
**PRD:** `docs/prds/2026-03-05-factory-substrate.md`
**Brainstorm:** `docs/brainstorms/2026-03-05-factory-substrate-brainstorm.md`
**Date:** 2026-03-05

---

## 1. Data Contracts Between Plugins and CXDB

**Priority:** P0
**Finding:** The PRD defines 6 CXDB type bundles (`clavain.phase.v1`, `clavain.dispatch.v1`, `clavain.artifact.v1`, `clavain.scenario.v1`, `clavain.satisfaction.v1`, `clavain.evidence.v1`, `clavain.policy_violation.v1`) but provides **zero field-level schemas** for any of them. The brainstorm's mapping table (line 85-94) maps Clavain concepts to CXDB primitives at a conceptual level, but never specifies the JSON envelope contents.

**Failure scenario:** Two implementers work on Phase 2 (scenario bank) and Phase 3 (evidence pipeline) in parallel. The scenario runner writes `clavain.scenario.v1` turns with `{scenario_id, steps_passed, steps_failed}`. The satisfaction scorer expects `{scenario_id, trajectory, rubric_results}`. The fields don't align. This is discovered at integration time, requiring rework of whichever shipped first.

**Evidence:**
- PRD F2 acceptance criteria (line 38): `clavain.phase.v1`, `clavain.dispatch.v1`, `clavain.artifact.v1` — names only, no fields
- PRD F5 acceptance criteria (line 76): `clavain.evidence.v1` — name only
- Brainstorm Go SDK (line 153-161): function signatures like `RecordPhase(ctx, phase, artifacts)` hint at field names but are not binding

**Recommendation:** Add a `Data Contracts` section to the PRD with concrete JSON schema examples for each type bundle. At minimum, specify required fields, types, and one example document. This is the contract between producers (F2, F5) and consumers (F4 scoring, Interspect queries). Example:

```json
// clavain.dispatch.v1
{
  "agent_name": "string",
  "subagent_type": "string",
  "bead_id": "string",
  "phase": "string",
  "model": "string",
  "input_tokens": "int",
  "output_tokens": "int",
  "total_tokens": "int",
  "wall_clock_ms": "int",
  "result_status": "enum(success|failure|timeout)",
  "artifact_refs": ["blake3-hash"]
}
```

---

## 2. Turn DAG Structure Concreteness

**Priority:** P1
**Finding:** The Turn DAG is described via the CXDB concept mapping (brainstorm line 85-94) and the Go SDK surface (brainstorm line 153-161), but several implementation-critical questions are unresolved:

- **Parent references:** CXDB turns form a DAG via parent references. The PRD does not specify the parent-linking strategy. Does a dispatch turn point to the preceding phase turn? Does a phase turn point to the previous phase? Is it linear (each turn points to its predecessor) or structured (dispatch turns fan out from their phase)?
- **Turn vs blob boundary:** The brainstorm says "Artifacts stored as BLAKE3-addressed blobs in CXDB CAS" (PRD line 41) and lists "Artifact (plan, brainstorm, review)" as blobs. But dispatch results also contain large text. The PRD never defines the size/content threshold for when data goes inline in a turn vs. gets stored as a blob reference.
- **Context-per-sprint vs context-per-session:** `SprintContext(beadID)` (brainstorm line 158) implies one context per bead. But a single session can work on multiple beads, and a single bead can span sessions. The PRD does not clarify the context lifecycle or how cross-session continuity works.

**Failure scenario:** Without parent-linking rules, the Turn DAG degrades to an unordered bag of turns per context. `QueryByType` still works, but the DAG's value proposition (trajectory reconstruction, fork-point identification) is lost.

**Evidence:**
- PRD F2 line 43: "Any sprint is reconstructable from its CXDB context" — requires ordered traversal, which requires parent references
- Brainstorm line 91: `ForkContext(baseTurnID)` — the turn ID is the fork point, so parent structure matters for identifying valid fork points

**Recommendation:** Add a subsection to F2 specifying: (a) parent-linking convention (recommend: linear chain within a phase, phase turns point to previous phase turn, creating a spine with dispatch branches), (b) inline-vs-blob threshold (recommend: >4KB or binary content goes to blob CAS, referenced by BLAKE3 hash in the turn body), (c) context lifecycle (one context per bead, context ID stored in bead metadata via `bd set-state`).

---

## 3. Migration Path from Existing Storage

**Priority:** P1
**Finding:** The PRD mentions no migration or dual-write strategy for existing evidence stores. Three stores currently hold evidence data:

1. **Interstat SQLite** (`~/.claude/interstat/metrics.db`): `agent_runs` table with session_id, agent_name, token counts, bead_id, phase, model. Schema v4 includes `tool_selection_events`. This is the richest existing dataset.
2. **Interspect SQLite** (`.clavain/interspect/interspect.db`): `evidence` table with ts, session_id, seq, source, event, override_reason, context JSON, project metadata. Also `sessions`, `canary`, `modifications` tables.
3. **Interject SQLite** (`interject.db`): `discoveries`, `promotions`, `feedback_signals`, `query_log`, `scan_log` tables.

The PRD says "wire existing plugins into a unified evidence pipeline" (F5) but only describes the future state (plugins write to CXDB). It does not address:
- Whether existing SQLite stores continue as primary storage with CXDB as secondary
- Whether there is a dual-write transition period
- Whether historical data is backfilled into CXDB
- What happens to the existing interstat `cost-query.sh` interface that downstream consumers (Intercore, fleet enrichment) depend on

**Failure scenario:** F5 ships and interspect starts writing `clavain.evidence.v1` turns to CXDB. But the existing `_interspect_classify_pattern()` function reads from the local SQLite `evidence` table. Without dual-write, pattern classification stops receiving data. The closed-loop learning pipeline (PHILOSOPHY.md line 58-65) breaks silently.

**Evidence:**
- `interverse/interspect/hooks/lib-interspect.sh` line 120-132: evidence table schema, actively written by 3+ hooks
- `interverse/interstat/scripts/cost-query.sh`: declared cross-layer interface consumed by `ic cost baseline`
- `interverse/interstat/CLAUDE.md`: "Data Flow" section shows 6-step pipeline from hooks to SQLite to reports
- `interverse/interject/src/interject/db.py` line 14-86: full CRUD layer against local SQLite

**Recommendation:** Add a migration subsection to F5 specifying: (a) Phase 3 implements dual-write — plugins continue writing to local SQLite AND write to CXDB via a thin adapter, (b) existing query interfaces (`cost-query.sh`, `_interspect_classify_pattern`) continue reading from SQLite during transition, (c) CXDB becomes the primary read path only after validation that CXDB data matches SQLite data for N sprints, (d) backfill is explicitly deferred (historical data stays in SQLite, CXDB starts fresh from the cutover point).

---

## 4. Query Patterns for Downstream Consumers

**Priority:** P1
**Finding:** The PRD specifies one query function: `QueryByType(ctx, typeID) []Turn` (brainstorm line 161). This is insufficient for the consumers described in the PRD:

- **LLM-as-judge scoring (F4):** Needs the full trajectory of a scenario run — all turns in order within a context. `QueryByType` returns only one type. The judge needs phases + dispatches + artifacts together.
- **Sprint gate (F4 line 67):** Needs "holdout satisfaction >= threshold" — requires querying all `clavain.satisfaction.v1` turns for a sprint context and aggregating scores. No aggregation query is specified.
- **Interspect pattern classification:** Currently classifies patterns from the `evidence` table with counting rules. The CXDB equivalent would need to query across contexts (cross-sprint) to identify recurring patterns. `QueryByType` is per-context.
- **Evidence pack generation (F5 line 80-81):** Needs all evidence for a specific failure case, likely spanning multiple turn types.

**Failure scenario:** The Interspect profiler (the primary cross-sprint consumer) cannot query "all dispatch turns where agent=fd-safety across the last 20 sprints" because `QueryByType` is scoped to a single context. Interspect falls back to its local SQLite, making CXDB a write-only sink.

**Evidence:**
- Brainstorm line 94: "Interspect outcome query | Query turns by type, extract signals" — one line, no detail
- CXDB is a Turn DAG store, not a relational database — cross-context queries may require full scans or secondary indexing

**Recommendation:** Expand the `pkg/cxdb/` API surface to include: (a) `QueryByTypeAcrossContexts(typeID, timeRange) []Turn` for cross-sprint analysis, (b) `QueryTrajectory(ctx) []Turn` returning all turns in DAG order for a context, (c) `QuerySatisfactionSummary(ctx) (score, passCount, failCount)` as a convenience for gate checks. If CXDB does not support cross-context queries efficiently, document that Interspect continues reading from its local SQLite and CXDB serves only per-sprint reconstruction. This is an honest dual-store architecture, not a bug.

---

## 5. Consistency Model / Write Failure Handling

**Priority:** P1
**Finding:** The PRD does not specify what happens when a CXDB write fails. The evidence pipeline has three write paths:

1. **Sprint recording (F2):** `sprint-advance` and `sprint-track-agent` write phase/dispatch turns. These are called from clavain-cli Go code.
2. **Evidence pipeline (F5):** Interspect hooks write evidence turns. These are bash hooks calling through to clavain-cli or directly to CXDB.
3. **Scenario recording (F3):** `scenario-run` writes trajectory turns.

For path 2, the existing interspect hooks are fail-open by design (`exit 0` on any error, per `interspect-evidence.sh` line 9). If CXDB write fails, the evidence is silently dropped. This violates PHILOSOPHY.md's "every action produces evidence" (line 9) and "if it didn't produce a receipt, it didn't happen" (line 51).

For path 1, a CXDB write failure during `sprint-advance` is more critical — should the phase transition be blocked or should it proceed without recording?

**Failure scenario:** CXDB server is temporarily unavailable (crashed, port conflict, disk full). A sprint runs to completion. All phase transitions and dispatch results are lost. The sprint appears to have never happened. Satisfaction scoring for this sprint is impossible. The evidence gap is not detectable.

**Evidence:**
- `interverse/interspect/hooks/interspect-evidence.sh` line 9: "Exit: 0 always (fail-open)"
- PHILOSOPHY.md line 80: "Every failure produces a receipt, no failure cascades unbounded"
- Brainstorm line 55: "Graceful degradation doubles code paths and the fallback path rots" — argues against fallback, but does not address transient failures

**Recommendation:** Specify a write-ahead log (WAL) strategy for CXDB writes: (a) Sprint recording (F2) writes to a local JSONL append log first, then flushes to CXDB. If CXDB is unavailable, the JSONL persists and is replayed on next `cxdb-start`. (b) Evidence hooks (F5) continue their fail-open behavior for individual events but write to the same JSONL WAL. (c) `cxdb-status` reports the WAL backlog size so operators can detect drift. This is the same pattern as interstat's JSONL-then-SQLite pipeline (interstat CLAUDE.md "Data Flow" step 4).

---

## 6. Blob CAS Garbage Collection

**Priority:** P2
**Finding:** The PRD states "Artifacts stored as BLAKE3-addressed blobs in CXDB CAS" (F2 line 41) and "Interstat token data attached to dispatch turns in CXDB blob CAS" (F5 line 79). The brainstorm lists CXDB's Blob CAS as a feature with "BLAKE3 hashing with Zstd compression" (line 39). Neither document addresses:

- **Garbage collection:** When contexts are deleted (if ever), orphaned blobs remain in CAS. Who collects them?
- **Storage growth:** Each dispatch turn may reference a blob containing full agent output. With 50+ sprints, each with 5-15 dispatches, blob storage grows linearly. No retention policy is specified.
- **Deduplication effectiveness:** BLAKE3 CAS deduplicates identical blobs. But agent outputs are rarely identical — each has unique timestamps, session IDs, etc. Deduplication savings will be minimal for most artifact types.

**Failure scenario:** After 3 months of sprints, `.clavain/cxdb/data/` grows to several GB. No compaction or archival exists. Disk pressure causes CXDB writes to fail, triggering the consistency issues from Finding 5.

**Evidence:**
- PRD open question 3 (line 115): "Retention policy? Per-sprint? Per-project? ... Defer compaction to later."
- PHILOSOPHY.md line 86: "Don't pay too early" — suggests this deferral is intentional

**Recommendation:** The deferral is acceptable for Phase 1, but the PRD should: (a) add an acceptance criterion to F1 for `cxdb-status` to report data directory size, (b) document the explicit deferral in the non-goals section ("Blob CAS garbage collection and retention policies are deferred"), (c) add a P3 note that `cxdb-archive <sprint-id>` should export a context to a portable archive before deletion.

---

## 7. End-to-End Evidence Trace (Missing)

**Priority:** P1
**Finding:** The PRD describes producers (plugins) and a destination (CXDB) but never traces a single evidence item end-to-end from action to storage to query to consumer decision. The brainstorm's evidence pipeline table (line 179-185) lists 5 source-destination pairs but omits the transformation logic, error handling, and consumer query for each.

**Failure scenario:** An implementer builds the interspect-to-CXDB adapter (F5, row 1 of the pipeline table) by copying the `evidence` table fields into a `clavain.evidence.v1` turn. But the satisfaction scorer (F4) expects evidence to include `bead_id` and `phase` (which interspect's evidence table does NOT have — those live in interstat's `agent_runs` table). The evidence arrives in CXDB but is not joinable with dispatch data.

**Evidence:**
- Interspect evidence schema (`lib-interspect.sh` line 120-132): fields are `ts, session_id, seq, source, source_version, event, override_reason, context, project, project_lang, project_type` — no `bead_id`, no `phase`
- Interstat agent_runs schema (`init-db.sh` line 14-33): has `bead_id`, `phase`, `model`, token counts — different schema entirely
- The two stores share `session_id` as a join key, but this cross-store join is not addressed in the CXDB data model

**Recommendation:** Add one concrete end-to-end trace to the PRD. Suggested: "Agent dispatch flows from `sprint-track-agent` (writes `clavain.dispatch.v1` turn with bead_id, phase, agent, tokens) through to `scenario-score` (queries all dispatch turns for the sprint context, passes trajectories to LLM judges) through to Interspect (queries dispatch turns cross-sprint to identify agent accuracy patterns)." This trace will expose the join-key problem and force the schema to include the fields that downstream consumers actually need.

---

## 8. Interject Evidence Pipeline Mismatch

**Priority:** P2
**Finding:** The pipeline table (brainstorm line 179-185, row 2) says "Interject scan findings | Convert to scenario steps | `.clavain/scenarios/dev/`". But interject is an ambient discovery engine that finds external tools, papers, and libraries. Its "findings" are discoveries about the external world (e.g., "new CLI tool for X"), not code quality findings or test failures.

The PRD F5 (line 77) says "Interject scan findings convertible to scenario steps via `clavain-cli evidence-to-scenario <finding-id>`". This implies interject findings map to scenario action/expect pairs, but a discovery like "arxiv paper on improved RAG techniques" does not naturally convert to a testable scenario step.

**Failure scenario:** The `evidence-to-scenario` command is implemented but produces low-quality scenarios because interject findings are research signals, not test specifications. The command ships but is never used, becoming dead code.

**Evidence:**
- `interverse/interject/src/interject/scanner.py` line 38-53: Scanner class orchestrates source adapters for external discovery
- `interverse/interject/src/interject/db.py` line 15-29: discoveries table stores external items (source, source_id, title, summary, url)
- `interverse/interject/CLAUDE.md`: "Ambient discovery and research engine"

**Recommendation:** Clarify the interject pipeline row. If the intent is that interject's capability gap detection (`gaps.py`) can identify missing capabilities that should be tested, say that explicitly and scope `evidence-to-scenario` to gap findings only, not raw discoveries. Alternatively, remove this row from the pipeline table and replace it with a more natural producer: flux-drive review findings (which ARE code quality findings and map directly to regression scenarios).

---

## Summary

| # | Priority | Finding | Status |
|---|----------|---------|--------|
| 1 | P0 | No field-level data contracts for CXDB type bundles | Must fix before implementation |
| 2 | P1 | Turn DAG parent-linking and turn-vs-blob boundary unspecified | Must fix before F2 implementation |
| 3 | P1 | No migration/dual-write strategy for 3 existing SQLite stores | Must fix before F5 implementation |
| 4 | P1 | Query patterns insufficient for cross-sprint consumers (Interspect) | Must fix before F5 implementation |
| 5 | P1 | No consistency model for CXDB write failures | Must fix before F2 implementation |
| 6 | P2 | Blob CAS GC deferred but not documented as non-goal | Document deferral |
| 7 | P1 | No end-to-end evidence trace exposes schema join gaps | Must fix before implementation |
| 8 | P2 | Interject-to-scenario pipeline mismatch with actual interject purpose | Clarify or remove |

---

## Verdict: SHIP_WITH_FIXES

The PRD correctly identifies the right architecture (CXDB adoption, evidence pipeline wiring, scenario bank as keystone) and aligns with PHILOSOPHY.md's "receipts close loops" and "every action produces evidence" principles. The conceptual design is sound.

However, the evidence pipeline — which is this PRD's raison d'etre — lacks the data contracts that make it implementable. Finding 1 (P0: no field-level schemas) is a blocking gap. Findings 2, 3, 4, 5, and 7 (all P1) are implementation-blocking for their respective features but can be addressed incrementally as each phase begins.

**Minimum fixes required before implementation begins:**
1. Add concrete JSON schema examples for all 7 CXDB type bundles (Finding 1)
2. Add one end-to-end evidence trace (Finding 7) — this will naturally surface and resolve Findings 2 and 4
3. Add a "Migration Strategy" section stating dual-write during transition (Finding 3)
4. Add a "Write Failure Handling" paragraph specifying JSONL WAL (Finding 5)

Findings 6 and 8 are P2 and can be addressed post-ship.
