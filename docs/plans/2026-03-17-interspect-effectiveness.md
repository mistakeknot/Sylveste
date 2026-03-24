---
artifact_type: plan
bead: iv-5ztam
stage: design
requirements:
  - F1: Effectiveness report function (Demarch-l6td)
  - F2: /interspect:effectiveness command (Demarch-w6tl)
  - F3: Effectiveness summary in status (Demarch-5pal)
---
# Interspect Effectiveness Dashboard — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** iv-5ztam
**Phase:** planned (as of 2026-03-17T19:43:47Z)
**Goal:** Add an effectiveness measurement dashboard to Interspect showing whether routing changes are making reviews better.

**Architecture:** New function `_interspect_effectiveness_report()` in `lib-interspect.sh` computing metrics from existing evidence/sessions tables. New command `commands/interspect-effectiveness.md`. One-line summary added to existing status command.

**Tech Stack:** Bash (lib-interspect.sh conventions), SQLite3, JSON (jq)

---

## Must-Haves

**Truths** (observable behaviors):
- User can run `/interspect:effectiveness` and see aggregate routing impact
- Override rate trend shows before/after comparison with percentage change
- Per-agent hit rates show directional trend (improving/stable/declining)
- Declining agents are flagged with warning
- `/interspect:status` includes a one-line effectiveness summary

**Artifacts** (files with specific exports):
- [`hooks/lib-interspect.sh`] exports `_interspect_effectiveness_report`, `_interspect_effectiveness_summary`
- [`commands/interspect-effectiveness.md`] — new command file

**Key Links:**
- Effectiveness queries read from existing `evidence` and `sessions` tables — no schema changes
- Status command calls `_interspect_effectiveness_summary()` — function must be fast (<1s)
- Active overrides read from `.claude/routing-overrides.json` — same as existing commands

---

### Task 1: Add Effectiveness Report Function to lib-interspect.sh

**Files:**
- Modify: `interverse/interspect/hooks/lib-interspect.sh` (append new functions at end)

**Step 1: Write test script**
Create `interverse/interspect/tests/test_effectiveness.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

# Setup test DB
TEST_DIR=$(mktemp -d)
export CLAUDE_PROJECT_DIR="$TEST_DIR"
mkdir -p "$TEST_DIR/.clavain/interspect"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/hooks/lib-interspect.sh"
_interspect_ensure_db
DB=$(_interspect_db_path)

# Insert test sessions
sqlite3 "$DB" "INSERT INTO sessions (session_id, start_ts, end_ts, project) VALUES
  ('s1', datetime('now', '-25 days'), datetime('now', '-25 days', '+1 hour'), 'test'),
  ('s2', datetime('now', '-20 days'), datetime('now', '-20 days', '+1 hour'), 'test'),
  ('s3', datetime('now', '-10 days'), datetime('now', '-10 days', '+1 hour'), 'test'),
  ('s4', datetime('now', '-5 days'), datetime('now', '-5 days', '+1 hour'), 'test'),
  ('s5', datetime('now', '-2 days'), datetime('now', '-2 days', '+1 hour'), 'test');"

# Insert evidence: dispatches and overrides for fd-safety
sqlite3 "$DB" "INSERT INTO evidence (ts, session_id, seq, source, event, override_reason, context, project) VALUES
  (datetime('now', '-25 days'), 's1', 1, 'fd-safety', 'agent_dispatch', '', '', 'test'),
  (datetime('now', '-25 days'), 's1', 2, 'fd-safety', 'override', 'agent_wrong', '', 'test'),
  (datetime('now', '-20 days'), 's2', 1, 'fd-safety', 'agent_dispatch', '', '', 'test'),
  (datetime('now', '-20 days'), 's2', 2, 'fd-safety', 'override', 'agent_wrong', '', 'test'),
  (datetime('now', '-10 days'), 's3', 1, 'fd-safety', 'agent_dispatch', '', '', 'test'),
  (datetime('now', '-10 days'), 's3', 2, 'fd-safety', 'agent_dispatch', '', '', 'test'),
  (datetime('now', '-5 days'), 's4', 1, 'fd-safety', 'agent_dispatch', '', '', 'test'),
  (datetime('now', '-2 days'), 's5', 1, 'fd-safety', 'agent_dispatch', '', '', 'test');"

# Test 1: effectiveness report returns JSON
echo "TEST 1: effectiveness report returns valid JSON"
result=$(_interspect_effectiveness_report 30)
echo "$result" | jq . >/dev/null 2>&1 || { echo "FAIL: invalid JSON"; exit 1; }
echo "PASS"

# Test 2: override_rate computed correctly
echo "TEST 2: per-agent data present"
agent_count=$(echo "$result" | jq '.agents | length')
[[ "$agent_count" -ge 1 ]] || { echo "FAIL: expected >=1 agent, got $agent_count"; exit 1; }
echo "PASS"

# Test 3: summary function returns one-line string
echo "TEST 3: summary function returns string"
summary=$(_interspect_effectiveness_summary)
[[ -n "$summary" ]] || { echo "FAIL: empty summary"; exit 1; }
echo "PASS: $summary"

# Test 4: empty DB returns graceful result
echo "TEST 4: empty DB handled gracefully"
sqlite3 "$DB" "DELETE FROM evidence; DELETE FROM sessions;"
empty_result=$(_interspect_effectiveness_report 30)
echo "$empty_result" | jq . >/dev/null 2>&1 || { echo "FAIL: invalid JSON on empty"; exit 1; }
echo "PASS"

# Cleanup
rm -rf "$TEST_DIR"
echo "All tests passed."
```

**Step 2: Run test to verify it fails**
Run: `bash interverse/interspect/tests/test_effectiveness.sh`
Expected: FAIL — `_interspect_effectiveness_report: command not found`

**Step 3: Implement effectiveness functions**
Append to `lib-interspect.sh` (before the final line or at the end):

```bash
# ─── Effectiveness metrics ──────────────────────────────────────────────────

# _interspect_effectiveness_report <window_days>
# Returns JSON with aggregate routing effectiveness metrics.
# Compares current window to prior window of same length.
_interspect_effectiveness_report() {
    local window_days="${1:-30}"
    local db
    db=$(_interspect_db_path) || { echo '{"error":"no_db"}'; return 0; }

    # Per-agent stats for current window
    local agents_json
    agents_json=$(sqlite3 "$db" "
        SELECT json_group_array(json_object(
            'agent', source,
            'dispatches', dispatches,
            'corrections', corrections,
            'override_rate', ROUND(CAST(corrections AS REAL) / MAX(dispatches, 1) * 100, 1),
            'sessions', sessions
        ))
        FROM (
            SELECT
                source,
                SUM(CASE WHEN event = 'agent_dispatch' THEN 1 ELSE 0 END) AS dispatches,
                SUM(CASE WHEN event = 'override' THEN 1 ELSE 0 END) AS corrections,
                COUNT(DISTINCT session_id) AS sessions
            FROM evidence
            WHERE ts > datetime('now', '-${window_days} days')
              AND source LIKE 'fd-%'
            GROUP BY source
            HAVING dispatches > 0
            ORDER BY corrections DESC
        );
    " 2>/dev/null) || agents_json="[]"
    [[ -z "$agents_json" ]] && agents_json="[]"

    # Prior window for trend comparison
    local prior_json
    prior_json=$(sqlite3 "$db" "
        SELECT json_group_array(json_object(
            'agent', source,
            'override_rate', ROUND(CAST(SUM(CASE WHEN event = 'override' THEN 1 ELSE 0 END) AS REAL) /
                MAX(SUM(CASE WHEN event = 'agent_dispatch' THEN 1 ELSE 0 END), 1) * 100, 1)
        ))
        FROM (
            SELECT source, event
            FROM evidence
            WHERE ts > datetime('now', '-$((window_days * 2)) days')
              AND ts <= datetime('now', '-${window_days} days')
              AND source LIKE 'fd-%'
        )
        GROUP BY source
        HAVING SUM(CASE WHEN event = 'agent_dispatch' THEN 1 ELSE 0 END) > 0;
    " 2>/dev/null) || prior_json="[]"
    [[ -z "$prior_json" ]] && prior_json="[]"

    # Aggregate totals
    local agg
    agg=$(sqlite3 -separator '|' "$db" "
        SELECT
            SUM(CASE WHEN event = 'agent_dispatch' THEN 1 ELSE 0 END),
            SUM(CASE WHEN event = 'override' THEN 1 ELSE 0 END),
            COUNT(DISTINCT session_id)
        FROM evidence
        WHERE ts > datetime('now', '-${window_days} days')
          AND source LIKE 'fd-%';
    " 2>/dev/null) || agg="0|0|0"

    local total_dispatches total_corrections total_sessions
    total_dispatches=$(echo "$agg" | cut -d'|' -f1)
    total_corrections=$(echo "$agg" | cut -d'|' -f2)
    total_sessions=$(echo "$agg" | cut -d'|' -f3)
    [[ -z "$total_dispatches" ]] && total_dispatches=0
    [[ -z "$total_corrections" ]] && total_corrections=0
    [[ -z "$total_sessions" ]] && total_sessions=0

    local override_rate=0
    if [[ "$total_dispatches" -gt 0 ]]; then
        override_rate=$(echo "scale=1; $total_corrections * 100 / $total_dispatches" | bc 2>/dev/null || echo "0")
    fi

    # Active overrides from routing-overrides.json
    local overrides_file
    overrides_file=$(_interspect_overrides_path 2>/dev/null || echo "")
    local active_overrides=0
    if [[ -n "$overrides_file" && -f "$overrides_file" ]]; then
        active_overrides=$(jq '[.overrides[] | select(.action == "exclude")] | length' "$overrides_file" 2>/dev/null || echo "0")
    fi

    # Output
    jq -n \
        --argjson agents "$agents_json" \
        --argjson prior "$prior_json" \
        --arg window "$window_days" \
        --arg override_rate "$override_rate" \
        --arg total_dispatches "$total_dispatches" \
        --arg total_corrections "$total_corrections" \
        --arg total_sessions "$total_sessions" \
        --arg active_overrides "$active_overrides" \
        '{
            window_days: ($window | tonumber),
            override_rate: ($override_rate | tonumber),
            total_dispatches: ($total_dispatches | tonumber),
            total_corrections: ($total_corrections | tonumber),
            total_sessions: ($total_sessions | tonumber),
            active_overrides: ($active_overrides | tonumber),
            agents: $agents,
            prior: $prior
        }'
}

# _interspect_effectiveness_summary
# Returns a one-line effectiveness summary for /interspect:status.
_interspect_effectiveness_summary() {
    local db
    db=$(_interspect_db_path) || { echo "Effectiveness: insufficient data"; return 0; }

    # Quick aggregate: current 30d vs prior 30d
    local current prior
    current=$(sqlite3 "$db" "
        SELECT ROUND(CAST(SUM(CASE WHEN event='override' THEN 1 ELSE 0 END) AS REAL) /
            MAX(SUM(CASE WHEN event='agent_dispatch' THEN 1 ELSE 0 END), 1) * 100, 1)
        FROM evidence WHERE ts > datetime('now','-30 days') AND source LIKE 'fd-%';
    " 2>/dev/null) || current=""
    prior=$(sqlite3 "$db" "
        SELECT ROUND(CAST(SUM(CASE WHEN event='override' THEN 1 ELSE 0 END) AS REAL) /
            MAX(SUM(CASE WHEN event='agent_dispatch' THEN 1 ELSE 0 END), 1) * 100, 1)
        FROM evidence WHERE ts > datetime('now','-60 days') AND ts <= datetime('now','-30 days') AND source LIKE 'fd-%';
    " 2>/dev/null) || prior=""

    if [[ -z "$current" || "$current" == "" || -z "$prior" || "$prior" == "" ]]; then
        echo "Effectiveness: insufficient data"
        return 0
    fi

    # Compute change
    local change
    if [[ "$prior" != "0" && "$prior" != "0.0" ]]; then
        change=$(echo "scale=0; ($current - $prior) * 100 / $prior" | bc 2>/dev/null || echo "?")
        if [[ "$change" -lt 0 ]]; then
            echo "Effectiveness: override rate ${prior}% → ${current}% (${change}% — improving)"
        elif [[ "$change" -gt 0 ]]; then
            echo "Effectiveness: override rate ${prior}% → ${current}% (+${change}% — declining)"
        else
            echo "Effectiveness: override rate ${current}% (stable)"
        fi
    else
        echo "Effectiveness: override rate ${current}%"
    fi
}
```

**Step 4: Run tests to verify they pass**
Run: `bash interverse/interspect/tests/test_effectiveness.sh`
Expected: All tests PASS

**Step 5: Syntax check**
Run: `bash -n interverse/interspect/hooks/lib-interspect.sh`
Expected: No errors

**Step 6: Commit**
```bash
cd interverse/interspect && git add hooks/lib-interspect.sh tests/test_effectiveness.sh
git commit -m "feat: add effectiveness report and summary functions"
```

<verify>
- run: `bash -n interverse/interspect/hooks/lib-interspect.sh`
  expect: exit 0
- run: `bash interverse/interspect/tests/test_effectiveness.sh`
  expect: contains "All tests passed"
</verify>

---

### Task 2: Create /interspect:effectiveness Command

**Files:**
- Create: `interverse/interspect/commands/interspect-effectiveness.md`

**Step 1: Write the command file**
```markdown
---
name: interspect-effectiveness
description: Show routing effectiveness metrics — override rate trends, per-agent impact, and actionable recommendations
argument-hint: "[--window=30]"
---

# Interspect Effectiveness

Show the impact of routing changes on review quality.

<effectiveness_args> #$ARGUMENTS </effectiveness_args>

## Locate Library

` ` `bash
INTERSPECT_LIB="${CLAUDE_PLUGIN_ROOT}/hooks/lib-interspect.sh"
if [[ ! -f "$INTERSPECT_LIB" ]]; then
    INTERSPECT_LIB=$(find ~/.claude/plugins/cache -path '*/interspect/*/hooks/lib-interspect.sh' -o -path '*/clavain/*/hooks/lib-interspect.sh' 2>/dev/null | head -1)
fi
if [[ -z "$INTERSPECT_LIB" || ! -f "$INTERSPECT_LIB" ]]; then
    echo "Error: Could not locate hooks/lib-interspect.sh" >&2
    exit 1
fi
source "$INTERSPECT_LIB"
_interspect_ensure_db
` ` `

## Parse Arguments

Extract `--window=N` from arguments (default 30).

## Generate Report

` ` `bash
WINDOW=${window:-30}
REPORT=$(_interspect_effectiveness_report "$WINDOW")
` ` `

## Display

Present the report as a formatted dashboard:

1. **Header:** `Routing Effectiveness — Last ${WINDOW} days`

2. **Active Overrides:** Read from routing-overrides.json, show each with:
   - Agent name
   - Action (exclude/propose)
   - Age (how long ago applied)
   - Canary status (from canary table)

3. **Aggregate Metrics:**
   - Override rate: X% (show trend vs prior window if available)
   - Total dispatches: N across M sessions
   - Total corrections: N

4. **Per-Agent Table:** From report.agents array:
   | Agent | Dispatches | Corrections | Override Rate | Trend |
   Compare with report.prior to compute trend direction:
   - Rate decreased → "↓ improving"
   - Rate increased → "↑ declining ⚠"
   - Rate unchanged (±2%) → "→ stable"
   - No prior data → "— new"

5. **Recommendations:**
   - Any agent with override_rate > 50%: "Consider /interspect:propose to evaluate excluding <agent>"
   - Any agent with declining trend (rate increased >10%): "⚠ <agent> declining — run /interspect:evidence <agent>"
   - All agents stable/improving: "Routing is healthy — no action needed"
```

**Step 2: Verify command loads**
Run: `ls interverse/interspect/commands/interspect-effectiveness.md && echo "OK"`
Expected: OK

**Step 3: Commit**
```bash
cd interverse/interspect && git add commands/interspect-effectiveness.md
git commit -m "feat: add /interspect:effectiveness command"
```

<verify>
- run: `ls interverse/interspect/commands/interspect-effectiveness.md`
  expect: exit 0
</verify>

---

### Task 3: Add Effectiveness Summary to Status Command

**Files:**
- Modify: `interverse/interspect/commands/interspect-status.md` (add effectiveness line)

**Step 1: Read the current status command**
Read `commands/interspect-status.md` to find where to insert the effectiveness summary.

**Step 2: Add effectiveness summary call**
After the canary summary section and before the final output, add:
```bash
# Effectiveness one-liner
EFFECTIVENESS=$(_interspect_effectiveness_summary 2>/dev/null || echo "")
```

**Step 3: Include in output**
In the display section, add after the canary stats:
```
${EFFECTIVENESS}
```
Only show if non-empty and not "insufficient data".

**Step 4: Commit**
```bash
cd interverse/interspect && git add commands/interspect-status.md
git commit -m "feat: add effectiveness summary to /interspect:status"
```

<verify>
- run: `bash -n interverse/interspect/hooks/lib-interspect.sh`
  expect: exit 0
</verify>

---

### Task 4: Bump Version and Final Verification

**Files:**
- Modify: `interverse/interspect/.claude-plugin/plugin.json` (bump version)

**Step 1: Bump version to 0.1.16**
Update version field in plugin.json.

**Step 2: Run full syntax check**
Run: `bash -n interverse/interspect/hooks/lib-interspect.sh`
Expected: No errors

**Step 3: Run effectiveness tests**
Run: `bash interverse/interspect/tests/test_effectiveness.sh`
Expected: All tests pass

**Step 4: Verify hooks.json is valid**
Run: `python3 -c "import json; json.load(open('interverse/interspect/hooks/hooks.json'))"`
Expected: No errors

**Step 5: Commit and push**
```bash
cd interverse/interspect && git add .claude-plugin/plugin.json
git commit -m "chore: bump interspect to v0.1.16 (effectiveness dashboard)"
git push
```

<verify>
- run: `bash -n interverse/interspect/hooks/lib-interspect.sh`
  expect: exit 0
- run: `bash interverse/interspect/tests/test_effectiveness.sh`
  expect: contains "All tests passed"
- run: `python3 -c "import json; json.load(open('interverse/interspect/.claude-plugin/plugin.json'))"`
  expect: exit 0
</verify>
