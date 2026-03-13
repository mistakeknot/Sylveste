---
artifact_type: plan
bead: Demarch-g3a
stage: design
requirements:
  - F1: Fix verdict recording discovery path
  - F2: Calibration schema v2 with source weighting
  - F3: Verdict backfill + sweep mechanism
---
# Interspect Calibration Pipeline Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Demarch-g3a
**Goal:** Make quality-gates agent verdicts flow into interspect's calibration pipeline so future sprints automatically adjust agent model tiers.

**Architecture:** The existing pipeline (`_interspect_record_verdict` → `_interspect_compute_agent_scores` → `_interspect_write_routing_calibration`) is complete but never fires because quality-gates Step 5a relies on agent compliance with SKILL.md text. Fix: add a verdict sweep to the SessionStart hook that catches unrecorded `.clavain/verdicts/*.json` files, then upgrade the calibration schema to v2 with source weighting.

**Tech Stack:** Bash (lib-interspect.sh), SQLite (interspect.db), jq, JSON

## Must-Haves

**Truths** (observable behaviors):
- After any session that ran `/quality-gates`, the next session's SessionStart records any unrecorded verdict events
- `/calibrate` produces `routing-calibration.json` with `schema_version: 2` including `weighted_hit_rate` and `source_weights`
- Bootstrap sessions are weighted 0.5x in hit rate calculations
- Existing `.clavain/verdicts/*.json` files are backfilled on first run

**Artifacts** (files that must exist):
- `interverse/interspect/hooks/lib-interspect.sh` exports `_interspect_sweep_verdicts`, `_interspect_compute_agent_scores` (v2)
- `.clavain/interspect/routing-calibration.json` with schema_version 2

**Key Links:**
- SessionStart hook calls `_interspect_sweep_verdicts` which reads `.clavain/verdicts/*.json` and calls `_interspect_record_verdict`
- `_interspect_compute_agent_scores` reads `verdict_outcome` events and applies source weights from sessions table
- `_interspect_write_routing_calibration` writes v2 schema consumed by `lib-routing.sh`

---

### Task 1: Add verdict sweep function to lib-interspect.sh

**Files:**
- Modify: `interverse/interspect/hooks/lib-interspect.sh`

**Step 1: Read the existing `_interspect_record_verdict` function and understand the evidence schema**

Run: read lines 2684-2712 of lib-interspect.sh (already done during brainstorm).

The function inserts into `evidence` table with: session_id, source (agent name), event="verdict_outcome", override_reason="", context (JSON with status, findings_count, model_used).

**Step 2: Add `_interspect_sweep_verdicts` function**

Add after the existing `_interspect_record_verdict` function (after line 2712). This function:
1. Finds all `.clavain/verdicts/*.json` files
2. For each, checks if already recorded (by querying evidence table for matching source + context hash)
3. If not recorded, calls `_interspect_record_verdict`
4. Writes a marker file `.clavain/verdicts/.recorded-<hash>` to track what's been processed

```bash
# Sweep unrecorded verdict files from quality-gates runs.
# Called by SessionStart hook to catch verdicts the previous session didn't record.
# Idempotent: tracks recorded verdicts via marker files.
_interspect_sweep_verdicts() {
    local verdicts_dir="${1:-.clavain/verdicts}"
    local session_id="${2:-$(cat /tmp/interstat-session-id 2>/dev/null || echo "sweep")}"

    [[ -d "$verdicts_dir" ]] || return 0
    _interspect_ensure_db || return 0

    local recorded=0
    local skipped=0

    for verdict_file in "$verdicts_dir"/*.json; do
        [[ -f "$verdict_file" ]] || continue
        local basename
        basename=$(basename "$verdict_file" .json)

        # Skip non-verdict files (synthesis.md, etc.)
        [[ "$basename" == "synthesis" ]] && continue

        # Check marker file
        local marker="${verdicts_dir}/.recorded-${basename}"
        if [[ -f "$marker" ]]; then
            skipped=$((skipped + 1))
            continue
        fi

        # Extract verdict data
        local status findings model
        status=$(jq -r '.status // "UNKNOWN"' "$verdict_file" 2>/dev/null) || continue
        findings=$(jq -r '.findings_count // 0' "$verdict_file" 2>/dev/null) || findings=0
        model=$(jq -r '.model // "unknown"' "$verdict_file" 2>/dev/null) || model="unknown"

        # Record the verdict
        _interspect_record_verdict "$session_id" "$basename" "$status" "$findings" "$model"
        local rc=$?

        if [[ $rc -eq 0 ]]; then
            # Write marker (content: timestamp + source session for auditability)
            printf '%s\n' "recorded_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$marker"
            recorded=$((recorded + 1))
        fi
    done

    if [[ $recorded -gt 0 ]]; then
        echo "interspect: swept $recorded verdict(s), $skipped already recorded" >&2
    fi
}
```

**Step 3: Verify the function compiles (bash syntax check)**

Run: `bash -n interverse/interspect/hooks/lib-interspect.sh`
Expected: exit 0, no errors

<verify>
- run: `bash -n interverse/interspect/hooks/lib-interspect.sh`
  expect: exit 0
- run: `grep -c '_interspect_sweep_verdicts' interverse/interspect/hooks/lib-interspect.sh`
  expect: contains "2"
</verify>

### Task 2: Wire sweep into SessionStart hook

**Files:**
- Modify: `interverse/interspect/hooks/interspect-session.sh`

**Step 1: Read the existing SessionStart hook**

Read `interverse/interspect/hooks/interspect-session.sh` to find where to add the sweep call.

**Step 2: Add verdict sweep call after session recording**

After the session is recorded in the DB (the `_interspect_insert_session` call), add:

```bash
# Sweep unrecorded verdicts from previous sessions
_interspect_sweep_verdicts ".clavain/verdicts" "$_SESSION_ID" 2>/dev/null || true
```

This must be after `source lib-interspect.sh` and after `_interspect_ensure_db`.

**Step 3: Verify hook syntax**

Run: `bash -n interverse/interspect/hooks/interspect-session.sh`
Expected: exit 0

<verify>
- run: `bash -n interverse/interspect/hooks/interspect-session.sh`
  expect: exit 0
- run: `grep -c 'sweep_verdicts' interverse/interspect/hooks/interspect-session.sh`
  expect: contains "1"
</verify>

### Task 3: Add source column to sessions table and classify sessions

**Files:**
- Modify: `interverse/interspect/hooks/lib-interspect.sh`

**Step 1: Find the schema migration / table creation code**

Search for `CREATE TABLE sessions` in lib-interspect.sh.

**Step 2: Add `source` column to sessions table**

Add `source TEXT DEFAULT 'normal'` to the sessions CREATE TABLE statement. Add an ALTER TABLE migration for existing DBs (graceful — if column exists, skip).

**Step 3: Add source classification function**

```bash
# Classify a session's source type for weighting.
# Args: $1=bead_id (optional)
# Output: "bootstrap" | "self-building" | "normal"
_interspect_classify_session_source() {
    local bead_id="${1:-}"

    # Check for bootstrap marker
    if [[ -f "/tmp/interstat-bootstrap" ]] || [[ "${CLAUDE_SESSION_SOURCE:-}" == "bootstrap" ]]; then
        echo "bootstrap"
        return 0
    fi

    # Check if working on interspect itself
    if [[ -n "$bead_id" ]]; then
        local title
        title=$(bd show "$bead_id" 2>/dev/null | head -1)
        if [[ "$title" == *"[interspect]"* ]] || [[ "$title" == *"interspect"* ]]; then
            echo "self-building"
            return 0
        fi
    fi

    # Check git diff for interspect files
    local changed_files
    changed_files=$(git diff --name-only HEAD 2>/dev/null || true)
    if echo "$changed_files" | grep -q 'interverse/interspect/' 2>/dev/null; then
        echo "self-building"
        return 0
    fi

    echo "normal"
}
```

**Step 4: Wire classification into session recording**

Update `_interspect_insert_session` (or wherever sessions are INSERT'd) to call `_interspect_classify_session_source` and store the result.

**Step 5: Verify syntax**

Run: `bash -n interverse/interspect/hooks/lib-interspect.sh`
Expected: exit 0

<verify>
- run: `bash -n interverse/interspect/hooks/lib-interspect.sh`
  expect: exit 0
- run: `grep -c '_interspect_classify_session_source' interverse/interspect/hooks/lib-interspect.sh`
  expect: contains "2"
</verify>

### Task 4: Upgrade agent scoring to v2 with source weighting

**Files:**
- Modify: `interverse/interspect/hooks/lib-interspect.sh`

**Step 1: Read the existing `_interspect_compute_agent_scores` function (lines 2728-2810)**

Already done during brainstorm.

**Step 2: Update the SQL query to join sessions table for source weights**

The query needs to join evidence with sessions to get the session's source, then apply weight multipliers:
- `bootstrap` → 0.5
- `self-building` → 0.7
- `normal` → 1.0

Update the jq processing to compute `weighted_hit_rate` alongside the raw `hit_rate`.

```bash
# In the SQL query, add a LEFT JOIN to sessions:
raw=$(sqlite3 -json "$db" "
    SELECT
        CASE
            WHEN e.source LIKE 'interflux:review:%' THEN SUBSTR(e.source, INSTR(e.source, ':') + INSTR(SUBSTR(e.source, INSTR(e.source, ':') + 1), ':') + 1)
            WHEN e.source LIKE 'interflux:%' THEN SUBSTR(e.source, 11)
            ELSE e.source
        END as agent,
        e.event,
        json_extract(e.context, '$.status') as verdict_status,
        json_extract(e.context, '$.findings_count') as findings_count,
        json_extract(e.context, '$.model_used') as model_used,
        e.session_id,
        COALESCE(s.source, 'normal') as session_source
    FROM evidence e
    LEFT JOIN sessions s ON e.session_id = s.session_id
    WHERE e.event IN ('agent_dispatch', 'verdict_outcome', 'override', 'disagreement_override')
    ORDER BY agent, e.ts
" 2>/dev/null) || raw="[]"
```

**Step 3: Update jq scoring to apply source weights and compute weighted_hit_rate**

Add source weight mapping and weighted hit rate computation to the jq pipeline. Add `min_non_bootstrap_sessions` threshold check (20).

**Step 4: Update `_interspect_write_routing_calibration` for v2 schema**

Change `schema_version` to 2, add `source_weights` field, add `weighted_hit_rate` and `min_non_bootstrap_sessions` to the output JSON.

**Step 5: Verify syntax**

Run: `bash -n interverse/interspect/hooks/lib-interspect.sh`
Expected: exit 0

<verify>
- run: `bash -n interverse/interspect/hooks/lib-interspect.sh`
  expect: exit 0
- run: `grep -c 'schema_version.*2' interverse/interspect/hooks/lib-interspect.sh`
  expect: contains "1"
- run: `grep -c 'weighted_hit_rate' interverse/interspect/hooks/lib-interspect.sh`
  expect: contains "2"
</verify>

### Task 5: Backfill existing verdicts and test end-to-end

**Files:**
- Modify: `interverse/interspect/hooks/lib-interspect.sh` (minor: test invocation)

**Step 1: Run the verdict sweep manually to backfill existing data**

```bash
cd /home/mk/projects/Demarch
source interverse/interspect/hooks/lib-interspect.sh
_interspect_ensure_db
_interspect_sweep_verdicts ".clavain/verdicts" "backfill-$(date +%s)"
```

Expected: records 5 verdict events (matching the 5 .json files in .clavain/verdicts/).

**Step 2: Verify evidence count increased**

```bash
sqlite3 .clavain/interspect/interspect.db "SELECT event, COUNT(*) FROM evidence GROUP BY event;"
```

Expected: `verdict_outcome` row with count >= 5.

**Step 3: Run calibration to test v2 output**

```bash
source interverse/interspect/hooks/lib-interspect.sh
_interspect_ensure_db
_interspect_write_routing_calibration
cat .clavain/interspect/routing-calibration.json | jq '.schema_version, .source_weights'
```

Expected: `schema_version` = 2, `source_weights` shows bootstrap/self-building/normal values.

**Step 4: Commit**

```bash
git add interverse/interspect/hooks/lib-interspect.sh interverse/interspect/hooks/interspect-session.sh
git commit -m "feat(interspect): close calibration flywheel — verdict sweep + v2 schema

Add _interspect_sweep_verdicts to catch unrecorded quality-gates verdicts
at SessionStart. Upgrade calibration schema to v2 with source weighting
(bootstrap 0.5x, self-building 0.7x) and weighted_hit_rate. Add session
source classification and backfill existing verdict data."
```

<verify>
- run: `sqlite3 .clavain/interspect/interspect.db "SELECT COUNT(*) FROM evidence WHERE event='verdict_outcome';"`
  expect: contains "5"
- run: `cat .clavain/interspect/routing-calibration.json 2>/dev/null | jq -r '.schema_version'`
  expect: contains "2"
- run: `bash -n interverse/interspect/hooks/lib-interspect.sh`
  expect: exit 0
</verify>
