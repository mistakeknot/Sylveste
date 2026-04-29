---
artifact_type: epic-dod
bead: sylveste-8r5h
prd: docs/prds/2026-04-29-activation-rate-kpi.md
date: 2026-04-29
---

# Epic Definition of Done — sylveste-8r5h Activation-Rate KPI

These are outcome-based criteria distinct from "all children closed."
The epic succeeds when these are demonstrably met.

| # | Criterion | Verification | Automated |
|---|-----------|--------------|-----------|
| 1 | Phase 0 spike returns a recorded recall number against iv-zsio / iv-godia / iv-2s7k7 with a binary go/no-go decision | `bd state sylveste-xofc passive_spike_recall && bd state sylveste-xofc next_phase` | yes |
| 2 | If explicit-emit chosen: ≥5 reference plugins emit ≥1 activation event in real sessions, each visible via `interspect activation` | `interspect activation --format=json` returns ≥5 `activated` rows | yes |
| 3 | North Star table in `docs/sylveste-vision.md` contains an activation-rate KPI row under **Quality** with the documented 14d / ≥3-distinct-sessions definition | `grep -E 'Activation rate.*distinct sessions' docs/sylveste-vision.md` | yes |
| 4 | Three-week baseline observation methodology documented; v1 = report-only; v2 soft-block guarded behind explicit calibration approval | Manual review of vision doc methodology section | no |
| 5 | If explicit-emit chosen: `subsystem_events` table exists, `ic events emit-subsystem` succeeds, and `cmdEventsEmit` accepts `SourceSubsystem` (meta-recursive failure mode closed) | `ic events emit-subsystem _activation-test --entry-point=test` then `ic events list-subsystem --since=0 --limit=1` returns the test row | yes |

**Phase 0 dominance rule.** If F0 returns `next_phase=passive-v1`, criteria 2 and 5 do not apply (Phase 1 is deferred). Criteria 1, 3, 4 still apply — passive v1 must still update the North Star table and document the methodology.
