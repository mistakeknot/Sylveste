---
artifact_type: review-findings-summary
target: docs/prds/2026-04-29-activation-rate-kpi.md
bead: sylveste-8r5h
date: 2026-04-29
agents: [interflux:fd-architecture, interflux:fd-user-product]
status: resolved
---

# Strategy Review — Findings Summary (Resolved)

**Initial counts:** 4 P0 · 6 P1 · 5 P2 · 3 P3
**Status (2026-04-29):** All P0/P1 folded back into the PRD. P2/P3 structurally absorbed.

## P0 (resolved)
1. F1 unified `Event` struct shape mismatch — now uses dedicated `SubsystemEvent` type, parallel to `ReviewEvent`. `validSources` is not modified.
2. F1 AC2 was mechanism, not behavior — now requires `ic events emit-subsystem` to exit 0 without `--source=review`.
3. F2 sentinel TTL=24h was nonsense (session_id unique) — recast as 7d storage GC.
4. F2 race AC was vague — now: 50 parallel calls, exact SQL assertion, CI.

## P1 (resolved)
5. F1→F2 sequencing without enforcement — version check in shim + CI test against pre-F1 binary.
6. F3 cursor-pattern duplication — extract `_consume_event_stream` shared helper; refactor existing review consumer.
7. F3 ACs tested schema not behavior — idempotent re-run, cursor-reset, concurrent-consumer tests.
8. F4 <500ms unverifiable — CI benchmark fixture.
9. F5 "real session" ambiguous — AC now: ≥5 plugins reach `activated` status (≥3 distinct sessions each).
10. `COUNT(DISTINCT session_id)` not enforced — pinned in F3 + F4 ACs.

## P2/P3 (absorbed structurally)
- Activation table split: `activation_events` + `activation_summary`.
- F2 vs F5 overlap removed: F2 ships helper only; F5 owns adoption.
- F4 explicitly includes `not-yet-instrumented` in denominator.
- `low_frequency` deferred to calibration follow-up bead.

## Convergent themes (cross-lens)
- Both lenses independently flagged the F1→F2 sequencing-without-enforcement as P1.
- Both flagged the missing `COUNT(DISTINCT session_id)` test.
- Architecture lens uniquely caught the `Event` struct semantics error (P0 #1).
- AC lens uniquely caught the bd state key-name pinning gap (P2 absorbed).
