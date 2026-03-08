# Plan: Preserve raw review semantics and source lineage in evidence ingestion

**Bead:** iv-w3ee6
**Date:** 2026-03-08
**Brainstorm:** [docs/brainstorms/2026-03-08-interspect-evidence-lineage.md](../brainstorms/2026-03-08-interspect-evidence-lineage.md)

## Goal

Fix two information-loss bugs in interspect's evidence pipeline: (1) `not_applicable` dismissals incorrectly mapped to `agent_wrong`, inflating routing FP rates; (2) no queryable lineage from evidence rows back to kernel events. All changes in `interverse/interspect/hooks/lib-interspect.sh`.

## Tasks

### T1: Schema migration — add lineage and raw-reason columns
**File:** `lib-interspect.sh` lines 118-142 (DB init block)
**Pattern:** Follow existing `CREATE TABLE IF NOT EXISTS` + add `ALTER TABLE ADD COLUMN` statements after table creation (SQLite silently errors on duplicate column adds — suppress with `2>/dev/null || true`)

- [x] After the `CREATE TABLE IF NOT EXISTS evidence (...)` block (~line 135), add:
  ```sql
  ALTER TABLE evidence ADD COLUMN source_event_id TEXT;
  ALTER TABLE evidence ADD COLUMN source_table TEXT;
  ALTER TABLE evidence ADD COLUMN raw_override_reason TEXT;
  ```
- [x] Add `CREATE INDEX IF NOT EXISTS idx_evidence_source_event_id ON evidence(source_event_id);` for lineage queries

### T2: Fix dismissal mapping — preserve `not_applicable`
**File:** `lib-interspect.sh` line 2244
**Change:** Single line — `not_applicable) override_reason="agent_wrong"` → `not_applicable) override_reason="not_applicable"`

- [x] Change line 2244 case branch:
  ```bash
  not_applicable)     override_reason="not_applicable" ;;
  ```
- [x] Verify: routing eligibility query at line 559 uses `IN ('agent_wrong', 'severity_miscalibrated')` — `not_applicable` is excluded, no query changes needed

### T3: Extend `_interspect_insert_evidence` to accept lineage + raw reason
**File:** `lib-interspect.sh` lines 2454-2498

- [x] Add 3 optional parameters after `hook_id`:
  ```bash
  local source_event_id="${7:-}"
  local source_table="${8:-}"
  local raw_override_reason="${9:-}"
  ```
- [x] Add SQL-escape lines for new parameters:
  ```bash
  local e_source_event_id="${source_event_id//\'/\'\'}"
  local e_source_table="${source_table//\'/\'\'}"
  local e_raw_override_reason="${raw_override_reason//\'/\'\'}"
  ```
- [x] Update INSERT statement to include new columns:
  ```sql
  INSERT INTO evidence (ts, session_id, seq, source, source_version, event,
    override_reason, context, project, project_lang, project_type,
    source_event_id, source_table, raw_override_reason)
  VALUES (...)
  ```
- [x] Existing callers pass 6 args — the 3 new params default to empty string, so backward compatible

### T4: Wire lineage into disagreement event processing
**File:** `lib-interspect.sh` lines 2224-2280 (`_interspect_process_disagreement_event`)

- [x] Extract event ID from the event JSON:
  ```bash
  local event_id
  event_id=$(echo "$event_json" | jq -r '.id // empty') || event_id=""
  ```
- [x] Pass lineage + raw reason to `_interspect_insert_evidence` (line 2275-2278):
  ```bash
  _interspect_insert_evidence \
      "$session_id" "$agent_name" "disagreement_override" \
      "$override_reason" "$context" "interspect-disagreement" \
      "$event_id" "review_events" "$dismissal_reason" \
      2>/dev/null || true
  ```

### T5: Wire lineage into kernel event consumption
**File:** `lib-interspect.sh` lines 2195-2214 (`_interspect_consume_kernel_events` inner loop)

- [x] The `$event_id` variable already exists (line ~2185). Pass it to `_interspect_insert_evidence` (line 2211-2214):
  ```bash
  _interspect_insert_evidence \
      "$session_id" "kernel-${event_source}" "${event_type}" \
      "" "$enriched_context" "interspect-consumer" \
      "$event_id" "events" "" \
      2>/dev/null || true
  ```

### T6: Validate
- [x] `bash -n interverse/interspect/hooks/lib-interspect.sh` — syntax check
- [x] Manual review: no existing callers of `_interspect_insert_evidence` break (all pass ≤6 args, new params default empty)
- [x] Verify `CREATE INDEX` doesn't error on fresh DB or existing DB

## Execution Order

T1 → T2 → T3 → T4 → T5 → T6 (sequential — T3 must exist before T4/T5 can use the new params)

## Risks

- **None for existing data**: New columns are nullable, existing rows get NULL
- **No routing query changes**: `not_applicable` is excluded from eligibility IN-list
- **Canary drift**: After fix, new baselines will be lower (fewer false `agent_wrong` tags). May trigger canary alerts — expected, not a regression
