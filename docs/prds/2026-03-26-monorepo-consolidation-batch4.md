---
artifact_type: prd
bead: Demarch-og7m
stage: design
batch: 4
---
# PRD: Monorepo Consolidation Batch 4

## Problem

Batches 1-3 hardened safety, governance, and multi-agent coordination. But the event pipeline — Intercore's central nervous system — has two operational defects and no contract: (1) `ListEvents` uses a shared `LIMIT` across 4-5 tables, so high-frequency coordination events (60/min at 10 agents) crowd out low-volume phase and review events; (2) 7 event types and 7 source values evolved across 30 commits with no JSON Schema — any schema change requires coordinated 5-file updates across 6+ consumers with no validation. Meanwhile, PHILOSOPHY.md's 4-stage closed-loop pattern is only complete in 2/6 domains (fleet budgets, review triage), with cost estimation, complexity scoring, gate thresholds, and agent routing stuck at stages 1-2.

This batch prepares the ground for the .2 sub-epic (event pipeline unification) by fixing nucleation and establishing a typed contract, while advancing the closed-loop calibration that PHILOSOPHY.md calls "incomplete work."

## Solution

Three targeted fixes: per-source sub-limits in ListEvents, a JSON Schema contract for event types, and /doctor reporting of calibration stage maturity.

## Features

### F1: Event Pipeline Nucleation Fix (.17)

**What:** Replace shared `LIMIT 1000` in `ListEvents` and `ListAllEvents` with per-source sub-limits that guarantee each event source gets representation regardless of volume.

**Root cause:** `store.go:99-186` uses `UNION ALL ... ORDER BY ... LIMIT ?` with a single limit across all sources. At 10 agents, coordination events (~60/min) fill the limit before slower sources (phase, review, discovery) contribute meaningfully. Result: consumers see a coordination-heavy stream with sparse phase/review events.

**Files:**
- `core/intercore/internal/event/store.go` — per-source sub-limits in ListEvents + ListAllEvents
- `core/intercore/internal/event/store_test.go` — test coverage for sub-limit behavior

**Acceptance criteria:**
- [ ] Each source (phase, dispatch, coordination, review, discovery) gets `ceil(limit / source_count)` rows in the UNION, with remainder allocated to the final merge
- [ ] Per-source `LIMIT` applied inside each `SELECT` arm of the UNION ALL, final `ORDER BY + LIMIT` on the outer query preserves timestamp ordering
- [ ] Existing cursor semantics unchanged — per-table `id > ?` filters still work
- [ ] Test: insert 100 coordination events + 5 phase events + 5 review events, list with limit=20 → all 3 sources represented
- [ ] `go build ./...` and `go test ./...` pass

### F2: Event Schema Contract (.21)

**What:** Publish JSON Schema contracts for the event types and EventEnvelope, create a validation helper, and document the event vocabulary.

**Root cause:** Event vocabulary grew organically across `event.go` (7 source constants), `envelope.go` (10 fields, 6 dead per .17 analysis), and 5 table schemas. No single document defines what a valid event looks like. 6+ consumers (interspect, intertrace, Clavain gate_calibration, Skaffen evidence emitter, interlab, intermix) parse events with ad-hoc assumptions.

**Files:**
- Create: `core/intercore/contracts/events/event.schema.json` — JSON Schema for unified Event type
- Create: `core/intercore/contracts/events/envelope.schema.json` — JSON Schema for EventEnvelope
- Create: `core/intercore/contracts/events/README.md` — event vocabulary reference
- `core/intercore/internal/event/event.go` — add Source/EventType validation method

**Acceptance criteria:**
- [ ] JSON Schema covers all 7 source values: phase, dispatch, interspect, discovery, coordination, review, intent
- [ ] JSON Schema covers EventEnvelope's 10 fields with types and constraints
- [ ] README documents each event type, which table it comes from, and which consumers read it
- [ ] `Event.Validate()` method checks Source against allowed values (returns error for unknown source)
- [ ] Schema files are valid JSON Schema Draft 2020-12
- [ ] `go build ./...` and `go test ./...` pass

### F3: Closed-Loop Calibration Stage Reporting (.23)

**What:** Add a `/doctor` check that reports calibration stage maturity for each of the 6 PHILOSOPHY.md domains, and promote the gate threshold calibration (B3) from shadow to active.

**Root cause:** PHILOSOPHY.md defines a 4-stage pattern (defaults → collect → calibrate → fallback) and lists 6 domains. Only fleet budgets (stage 4) and review triage (stage 3-4) are complete. Cost estimation, complexity scoring, gate thresholds, and agent routing are stuck at stages 1-2 — but nothing reports this gap, so it's invisible to sprint planning.

**Files:**
- `os/Clavain/commands/doctor.md` — add calibration stage check
- `os/Clavain/hooks/lib-doctor.sh` (or equivalent) — implement stage detection logic
- Create: `core/intercore/contracts/calibration-stages.yaml` — machine-readable stage definitions per domain

**Acceptance criteria:**
- [ ] `/doctor` outputs a table: Domain | Current Stage | Target Stage | Evidence
- [ ] All 6 domains from PHILOSOPHY.md are represented
- [ ] Stage detection is evidence-based: checks for actual files/functions, not hardcoded claims
- [ ] Gate threshold calibration (Demarch-0rgc) status accurately reflected
- [ ] Calibration stages YAML is the single source of truth — /doctor reads it, not hardcoded
- [ ] `bash -n` syntax check passes on all modified shell files

## Execution Order

```
F1 and F2 have mild affinity (both touch event package) but no blocking dependency:
  ├── F1: Nucleation fix (.17) — Go, store.go query rewrite
  ├── F2: Schema contract (.21) — JSON Schema + Go validation + docs
  └── F3: Closed-loop reporting (.23) — bash/YAML, independent

Recommended: F1 first (smallest, highest signal), then F2 (references F1's source list), then F3.
```

## Non-goals

- Event pipeline unification (.2) — separate sub-epic, depends on F1 + F2 landing first
- Phase FSM lift (.1) — separate sub-epic
- Promoting all 6 domains to stage 4 — F3 only adds visibility, actual calibration is per-domain work
- Backward-incompatible EventEnvelope changes — F2 documents current schema, v2 redesign is in .2.1

## Dependencies

- F1 (.17): None
- F2 (.21): Mild affinity with F1 (references same source constants), but no blocking dependency
- F3 (.23): None — reads PHILOSOPHY.md domains, no event pipeline dependency
- F1 blocks: Demarch-og7m.2.2 (unified stream API inherits per-source sub-limits)
- F2 blocks: Demarch-og7m.2.1 (unified envelope v2 builds on documented current schema)
