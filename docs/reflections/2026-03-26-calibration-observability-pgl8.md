---
artifact_type: reflection
bead: Sylveste-pgl8
date: 2026-03-26
sprint_outcome: shipped
---
# Reflection: F6 Calibration Observability (Sylveste-pgl8)

## What happened

3-task batch for calibration observability. Plan review discovered Tasks 6.1 (gate provenance output) and 6.2 (skip-gate audit event) were already shipped in commit 8c0d46c alongside F2-F5. Only Task 6.3 (calibration file staleness interspect event) needed implementation.

## Implementation

Added `calibrationStaleDetected` flag + `emitCalibrationStaleEvent()` to `calibration_load.go`. Wired into both callers (`gate.go:cmdGateCheck`, `run.go:cmdRunAdvance`). Routes through `cmdEventsRecord --source=interspect` to land in the interspect event store, not `phase_events` (staleness is an operational signal, not a phase transition).

## Lessons

1. **Same orphan pattern as Sylveste-fi7b.** Commit 8c0d46c shipped Batches 2-6 but only the parent epic's phase advanced — 5 child beads (F2-F6) were left open. The orphan doctor check we added earlier in this session would catch all of them.
2. **PhaseEvent is not a catch-all event store.** The initial implementation attempt tried to emit staleness as a `PhaseEvent` — wrong model. Phase events are for transitions (advance, block, override). Operational signals (staleness, data starvation) go to interspect via `ic events record --source=interspect`.
3. **Plan review ROI compounds across a session.** This is the third sprint where review-before-execute saved a full execute cycle. The pattern: read source to validate plan claims → discover most work is done → scope execution to the actual gap.
