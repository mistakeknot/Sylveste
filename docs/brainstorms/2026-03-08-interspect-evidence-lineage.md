# Preserve raw review semantics and source lineage in evidence ingestion

**Bead:** iv-w3ee6
**Date:** 2026-03-08
**Status:** Brainstorm

## Problem

Interspect's evidence ingestion pipeline loses information in two ways:

1. **Semantic collapse in dismissal mapping** — `_interspect_process_disagreement_event()` maps `not_applicable` → `agent_wrong`, collapsing two distinct signals. "Not applicable to this context" means the agent correctly identified a pattern but it doesn't apply here. "Agent wrong" means the agent's judgment was incorrect. Treating them identically inflates the false positive rate used for routing eligibility calculations.

2. **No structured lineage** — The kernel review event ID is stored in the `context` JSON blob but not as a queryable column. You can't efficiently join evidence rows back to kernel events, trace the provenance chain, or detect stale/duplicate evidence.

## Current State

### Dismissal Mapping (lib-interspect.sh ~line 2240)
```
agent_wrong     → agent_wrong          (correct)
deprioritized   → deprioritized        (correct)
already_fixed   → stale_finding        (correct)
not_applicable  → agent_wrong          ← LOSSY
""              → severity_miscalibrated (conditional, correct)
```

### Evidence Schema (no lineage columns)
```sql
CREATE TABLE evidence (
    id, ts, session_id, seq, source, source_version,
    event, override_reason, context, project, project_lang, project_type
);
```

No `source_event_id`, `source_table`, `derivation_version`, or `raw_dismissal_reason` columns.

### Impact
- Routing eligibility uses `override_reason IN ('agent_wrong', 'severity_miscalibrated')` to compute `agent_wrong_pct`. Inflated by `not_applicable` misclassification.
- Canary baselines include the same bias — FP rate metrics are systematically overstated.
- No way to trace evidence back to kernel events without parsing JSON.

## Proposed Fix

### F1: Preserve raw dismissal reason
- Add `not_applicable` as its own override_reason (don't collapse to `agent_wrong`)
- Update the `case` statement mapping
- **Do NOT change routing queries yet** — add the new category but keep `not_applicable` excluded from routing eligibility to be conservative. It can be added later with data to support it.

### F2: Add lineage columns
- Add `source_event_id TEXT` and `source_table TEXT` to evidence table
- `source_event_id` = kernel event ID (from review_events or generic events)
- `source_table` = `"review_events"` or `"events"` (origin table)
- Populate on insert from `_interspect_process_disagreement_event()` and `_interspect_consume_kernel_events()`
- Use `ALTER TABLE ADD COLUMN` migration (SQLite supports this without downtime)

### F3: Preserve raw values alongside mapped values
- Store the original `dismissal_reason` in context JSON (already done for disagreement events)
- Add `raw_override_reason TEXT` column to evidence table for queryable access
- This is insurance: even if the mapping evolves, the raw signal is always available

## Risks

- **Migration**: SQLite ALTER TABLE ADD COLUMN is safe (nullable columns only). No data loss risk.
- **Query changes**: Routing eligibility queries use `override_reason IN (...)` — adding `not_applicable` as a new value won't break them since it's not in the IN list.
- **Canary baselines**: Existing baselines were computed with inflated FP rates. After the fix, new baselines will be lower. This could trigger canary alerts (expected drift, not real regression). May need to re-baseline active canaries.

## Non-Goals

- Backfilling existing evidence rows (not worth the complexity)
- Changing routing eligibility thresholds (separate concern)
- Adding a full event sourcing / CQRS pattern (overkill for SQLite)

## Open Questions

- Should `not_applicable` count toward routing eligibility at all? Current recommendation: no, exclude it. It signals context mismatch, not agent error.
- Should we add an index on `source_event_id`? Probably yes if we want efficient lineage queries.
