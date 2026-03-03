# Tool Selection Failure Instrumentation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** iv-rttr5
**Goal:** Instrument agent sessions to classify tool selection failures into 3 categories (discovery, sequencing, scale degradation), producing queryable data for the composition layer design (iv-3kpfu).

**Architecture:** Extend interstat with a new `tool_selection_events` table and two new hooks: PostToolUse (all tools, not just Task) for tracking all tool calls with context, and PostToolUseFailure for capturing failures. A SessionEnd classifier reads the session's events and assigns failure categories using heuristics.

**Tech Stack:** Bash (hooks), SQLite (storage), Python (classifier script)

## Prior Learnings

- hooks.json must use record format, not array (ZodError prevents plugin loading)
- PostToolUseFailure is a valid hook event but currently has zero consumers
- interstat hooks read bead context from `/tmp/interstat-bead-{session_id}`
- `PRAGMA busy_timeout=5000` + WAL mode for concurrent hook writes
- Secret redaction available via interspect's `_interspect_redact_secrets()`
- All hooks must exit 0 (fail-open) to avoid blocking sessions

---

### Task 1: Add tool_selection_events table to interstat schema

**Files:**
- Edit: `interverse/interstat/scripts/init-db.sh`

**What to do:**
Add schema v3 migration creating the `tool_selection_events` table:

```sql
CREATE TABLE IF NOT EXISTS tool_selection_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,
    session_id TEXT NOT NULL,
    seq INTEGER NOT NULL DEFAULT 0,
    tool_name TEXT NOT NULL,
    tool_input_summary TEXT,
    outcome TEXT NOT NULL DEFAULT 'success',
    error_message TEXT,
    failure_category TEXT,
    failure_signals TEXT,
    preceding_tool TEXT,
    retry_of_seq INTEGER,
    bead_id TEXT DEFAULT '',
    phase TEXT DEFAULT ''
);
CREATE INDEX IF NOT EXISTS idx_tse_session ON tool_selection_events(session_id);
CREATE INDEX IF NOT EXISTS idx_tse_category ON tool_selection_events(failure_category);
CREATE INDEX IF NOT EXISTS idx_tse_tool ON tool_selection_events(tool_name);
CREATE INDEX IF NOT EXISTS idx_tse_outcome ON tool_selection_events(outcome);
```

Bump `PRAGMA user_version` to 3. Keep existing schema v2 migrations unchanged.

**Verification:** Run `bash interverse/interstat/scripts/init-db.sh` and verify table exists with `sqlite3 ~/.claude/interstat/metrics.db ".schema tool_selection_events"`.

---

### Task 2: Add PostToolUse hook for all tool calls

**Files:**
- Create: `interverse/interstat/hooks/post-tool-all.sh`
- Edit: `interverse/interstat/hooks/hooks.json`

**What to do:**

Create `post-tool-all.sh` — a PostToolUse hook that captures ALL tool calls (not just Task). This is the primary data collection hook.

The hook should:
1. Read hook JSON from stdin (same schema as post-task.sh)
2. Extract: `session_id`, `tool_name`, `tool_input` (truncate to 200 chars), `tool_output` (check for error indicators)
3. Determine `outcome`: 'success' or 'error' (check if tool_output contains error markers)
4. Read session sequence counter from `/tmp/interstat-seq-${session_id}` (increment on each call)
5. Read preceding tool from `/tmp/interstat-prev-tool-${session_id}`
6. Write current tool as prev-tool for next call
7. Detect retry pattern: if tool_name matches preceding_tool, check if params differ → set retry_of_seq
8. INSERT into `tool_selection_events`
9. Read bead_id from `/tmp/interstat-bead-${session_id}` (reuse existing protocol)
10. Exit 0 always (fail-open)

Error detection heuristics for `outcome`:
- tool_output starts with `Error:` or `error:` → 'error'
- tool_output contains `"error"` key in JSON → 'error'
- tool_output is empty or null → 'error'
- Otherwise → 'success'

Register in hooks.json as a new PostToolUse entry with `"matcher": "*"` (all tools).

**Important:** The existing `PostToolUse` entry for `"matcher": "Task"` (post-task.sh) must remain unchanged. Add a SECOND PostToolUse entry for `"matcher": "*"`.

**Verification:** Start a new Claude Code session, make a few tool calls, then check `sqlite3 ~/.claude/interstat/metrics.db "SELECT * FROM tool_selection_events ORDER BY id DESC LIMIT 5;"`.

---

### Task 3: Add PostToolUseFailure hook

**Files:**
- Create: `interverse/interstat/hooks/post-tool-failure.sh`
- Edit: `interverse/interstat/hooks/hooks.json`

**What to do:**

Create `post-tool-failure.sh` — captures tool invocations that failed (tool_use returned an error). This is a separate event type from PostToolUse.

The hook should:
1. Read hook JSON from stdin
2. Extract: `session_id`, `tool_name`, `tool_input` (truncated), `error` message
3. Read session sequence from `/tmp/interstat-seq-${session_id}`
4. INSERT into `tool_selection_events` with `outcome='failure'`, `error_message` populated
5. Apply preliminary failure_category:
   - If error contains "unknown tool" or "not loaded" or "not found" → 'discovery'
   - If error contains "missing parameter" or "invalid" → 'sequencing'
   - Otherwise → NULL (deferred to classifier)
6. Exit 0 always

Register in hooks.json as `PostToolUseFailure` with no matcher (catches all failures).

**Verification:** Intentionally trigger a tool failure (e.g., Read a non-existent file), check that `tool_selection_events` has a row with `outcome='failure'`.

---

### Task 4: Build SessionEnd failure classifier

**Files:**
- Create: `interverse/interstat/scripts/classify-failures.py`

**What to do:**

Python script invoked during SessionEnd that reads tool_selection_events for the current session and classifies uncategorized failures. Can also be run standalone for batch classification.

Usage: `python3 classify-failures.py [--session-id=<id>] [--all-unclassified]`

Classification heuristics (applied in order):

1. **Discovery signals:**
   - ToolSearch call immediately precedes the failed tool → discovery (agent was searching for tools)
   - Tool A fails → different Tool B called with similar input → discovery (agent pivoted tools)
   - PostToolUseFailure with "unknown tool" / "not loaded" → discovery (already set by hook)

2. **Sequencing signals:**
   - Same tool called 3+ times with different inputs in sequence → sequencing (trial-and-error)
   - Tool called that typically follows another tool, but precursor was skipped → sequencing
   - Error message contains "precondition" or "must call X first" → sequencing

3. **Scale signals:**
   - Statistical: session has >40 unique tool calls AND error rate > session average → scale
   - Note: this is a weak signal, needs larger dataset to validate

4. **Uncategorized:** Anything not matching above patterns stays NULL

The script should:
- Query `tool_selection_events WHERE session_id=? AND failure_category IS NULL AND outcome != 'success'`
- Apply heuristics, UPDATE the `failure_category` and `failure_signals` (JSON describing which heuristics fired)
- Print summary: `Classified X/Y failures: N discovery, M sequencing, K scale, J uncategorized`

**Verification:** Create test data with known failure patterns, run classifier, verify correct categories.

---

### Task 5: Wire classifier into SessionEnd hook

**Files:**
- Edit: `interverse/interstat/hooks/session-end.sh`

**What to do:**

Add a call to the classifier at the end of session-end.sh:

```bash
# Classify tool selection failures for this session
python3 "${SCRIPT_DIR}/../scripts/classify-failures.py" --session-id="$session_id" 2>/dev/null || true
```

This runs after the existing JSONL analysis (analyze.py), so token data is already backfilled.

**Verification:** Complete a session with some tool failures, check that `failure_category` is populated in `tool_selection_events`.

---

### Task 6: Add query script for failure analysis

**Files:**
- Create: `interverse/interstat/scripts/failure-query.sh`

**What to do:**

Query interface for tool selection failure data. Modeled after cost-query.sh.

Modes:
- `summary` — Count by failure_category (discovery/sequencing/scale/uncategorized)
- `by-tool` — Failure count and category breakdown per tool_name
- `by-session` — Failure rate per session with tool count context
- `scale-correlation` — Failure rate bucketed by unique-tools-in-session (the key scale degradation signal)
- `recent` — Last 20 failure events with full detail

All modes output JSON.

Example:
```bash
bash scripts/failure-query.sh summary
bash scripts/failure-query.sh scale-correlation
bash scripts/failure-query.sh by-tool --limit=10
```

**Verification:** Run each mode with test data and verify JSON output.

---

### Task 7: Smoke test — end-to-end validation

**Files:** None (runtime verification)

**What to do:**

1. Run `bash interverse/interstat/scripts/init-db.sh` to apply schema migration
2. Verify hooks.json is valid: `jq . interverse/interstat/hooks/hooks.json`
3. Verify all new scripts are executable
4. Manually INSERT test data:
   ```sql
   INSERT INTO tool_selection_events (timestamp, session_id, seq, tool_name, outcome, error_message)
   VALUES ('2026-03-03T12:00:00Z', 'test-session', 1, 'Read', 'success', NULL);
   INSERT INTO tool_selection_events (timestamp, session_id, seq, tool_name, outcome, error_message)
   VALUES ('2026-03-03T12:00:01Z', 'test-session', 2, 'ToolSearch', 'success', NULL);
   INSERT INTO tool_selection_events (timestamp, session_id, seq, tool_name, outcome, error_message, failure_category)
   VALUES ('2026-03-03T12:00:02Z', 'test-session', 3, 'mcp__unknown__tool', 'failure', 'unknown tool', 'discovery');
   ```
5. Run `bash scripts/failure-query.sh summary` and verify output
6. Run classifier on test session: `python3 scripts/classify-failures.py --session-id=test-session`
7. Clean up test data
