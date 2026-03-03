# Brainstorm: Tool Selection Failure Instrumentation

**Bead:** iv-rttr5
**Date:** 2026-03-03
**Origin:** Plugin-modularity dialectic Round 3 — hostile auditor's closing verdict: "the composition paradox is an empirical question masquerading as a philosophical one"

## Problem Statement

We have 49 plugins exposing 100+ tools to agents. The dialectic identified three failure modes in tool selection but has zero empirical data on their frequency or distribution:

1. **Discovery failure** — agent didn't surface the right tool candidate (e.g., used Grep when ToolSearch for an MCP tool was needed)
2. **Sequencing failure** — found the right tools but wrong call order or missed preconditions (e.g., called ToolSearch after already having the tool loaded)
3. **Scale degradation** — inherent accuracy loss at 50+ tools regardless of composition quality

Without this data, the downstream composition layer (iv-3kpfu) is designing blind.

## Existing Infrastructure

| System | What it captures | Gap |
|--------|-----------------|-----|
| **interstat** | Token counts per agent, bead/phase correlation | No tool selection reasoning |
| **tool-time** | All tool calls, errors, file paths, skills | Captures `is_error` but no failure taxonomy |
| **interspect** | Agent dispatch events, subagent_type | Only Task tool dispatches, not tool selection |
| **intercheck** | Syntax/format errors on Edit/Write | Wrong scope — code quality, not tool selection |

**Unused hooks:** `PostToolUseFailure` is defined but has zero consumers. This is the direct signal for tool errors.

## Design Space

### What signals exist in session data?

**Direct signals (observable in hook payloads):**
- `PostToolUseFailure` events — tool was called and failed (wrong params, unavailable, timeout)
- `PostToolUse` with error in output — tool succeeded at invocation but returned an error result
- ToolSearch calls — agent needed to discover a tool (discovery gap indicator)
- Repeated calls to same tool with different params — trial-and-error (possible sequencing gap)
- Tool call immediately followed by a different tool doing the same thing — pivot after failure

**Indirect signals (require conversation JSONL analysis):**
- Agent reasoning about tool selection in its output text
- User corrections ("use X instead of Y")
- Tool calls that produce unused results (output never referenced again)

**Scale signals (statistical):**
- Error rate per tool as function of total tool count in session
- Time-to-first-correct-tool as function of available tools
- Session tool diversity vs. outcome quality

### Three approaches

**A: Hook-based real-time capture (PostToolUseFailure + enhanced PostToolUse)**
- Add PostToolUseFailure consumer → direct failure events
- Enhance existing PostToolUse with tool-count-at-time-of-call context
- Store in interstat or new dedicated table
- Pro: Real-time, no post-hoc analysis needed
- Con: Can't capture "would have been better to use tool X" (discovery gaps are invisible at hook time)

**B: JSONL post-hoc analysis (session replay)**
- Parse conversation JSONL after session ends
- Apply heuristics to classify failures: repeated tool calls = sequencing, ToolSearch usage = discovery, error rate regression = scale
- Pro: Can see full conversation context, detect discovery gaps retroactively
- Con: Batch processing, requires session completion, heuristic accuracy uncertain

**C: Hybrid (hooks for direct signals + JSONL for classification)**
- PostToolUseFailure hook captures raw failure events in real-time
- SessionEnd hook triggers classifier that reads failures + conversation context
- Classifier assigns failure category using the 3-bucket taxonomy
- Pro: Best of both — real-time capture + contextual classification
- Con: More complex, two codepaths

### Where to put it?

**Option 1: Extend interstat** — already has SQLite schema, PostToolUse hooks, session correlation
**Option 2: Extend interspect** — already captures agent dispatch evidence, has evidence taxonomy
**Option 3: New plugin (e.g., interprobe)** — clean separation, but adds to the 49-plugin count (ironic given the dialectic)
**Option 4: Extend tool-time** — already parses all tool events, has error capture

## Assessment

**Recommended: Option C (hybrid) + Option 1 (extend interstat)**

Rationale:
- Interstat already has the PostToolUse hook infrastructure, SQLite schema, and session correlation
- Adding PostToolUseFailure is a natural extension
- JSONL analysis for classification can reuse interstat's existing `analyze.py` parser
- Keeps the plugin count at 49 (no new plugins — the dialectic would be embarrassed)

### Schema additions to interstat

```sql
-- New table for tool selection events
CREATE TABLE IF NOT EXISTS tool_selection_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,
    session_id TEXT NOT NULL,
    tool_name TEXT NOT NULL,
    tool_input_summary TEXT,          -- truncated first 200 chars of input
    outcome TEXT NOT NULL,            -- 'success', 'error', 'failure'
    error_message TEXT,               -- from PostToolUseFailure or error output
    failure_category TEXT,            -- 'discovery', 'sequencing', 'scale', 'uncategorized'
    failure_signals TEXT,             -- JSON: which heuristics fired
    tools_available_count INTEGER,    -- how many tools loaded at time of call
    tool_search_preceding BOOLEAN,   -- was a ToolSearch call in the last 3 events?
    retry_count INTEGER DEFAULT 0,   -- times this tool was called with different params
    bead_id TEXT,
    phase TEXT
);

CREATE INDEX IF NOT EXISTS idx_tse_session ON tool_selection_events(session_id);
CREATE INDEX IF NOT EXISTS idx_tse_category ON tool_selection_events(failure_category);
CREATE INDEX IF NOT EXISTS idx_tse_tool ON tool_selection_events(tool_name);
```

### Classification heuristics

| Signal Pattern | Category | Confidence |
|---------------|----------|------------|
| PostToolUseFailure with "unknown tool" | Discovery | High |
| ToolSearch immediately before tool call | Discovery | Medium (could be normal) |
| Tool A fails → Tool B called (different tool, same intent) | Discovery | High |
| Same tool called 3+ times with different params | Sequencing | High |
| Tool called before its precondition tool | Sequencing | Medium |
| Error rate increases when session has 40+ tools loaded | Scale | Medium |
| PostToolUseFailure with "not loaded" for deferred tool | Discovery | High |

### Data collection targets

- **Minimum viable:** 50 sessions with PostToolUseFailure data
- **Meaningful analysis:** 200+ sessions across different agent types (subagents, main session)
- **Timeline to data:** ~1 week of normal usage after instrumentation ships

## Output Contract

The instrumentation should produce data queryable as:

```sql
-- Distribution of failure categories
SELECT failure_category, COUNT(*) as count
FROM tool_selection_events
WHERE outcome != 'success'
GROUP BY failure_category;

-- Failure rate by tool count (scale degradation signal)
SELECT
    CASE WHEN tools_available_count < 20 THEN '<20'
         WHEN tools_available_count < 40 THEN '20-39'
         ELSE '40+' END as tool_range,
    COUNT(*) as total,
    SUM(CASE WHEN outcome != 'success' THEN 1 ELSE 0 END) as failures,
    ROUND(100.0 * SUM(CASE WHEN outcome != 'success' THEN 1 ELSE 0 END) / COUNT(*), 1) as failure_pct
FROM tool_selection_events
GROUP BY tool_range;

-- Discovery vs sequencing by agent type
SELECT failure_category, bead_id, COUNT(*) as count
FROM tool_selection_events
WHERE failure_category IS NOT NULL
GROUP BY failure_category, bead_id;
```

## Open Questions

1. **How do we count "tools available"?** Claude Code doesn't expose this directly in hook payloads. Could count registered MCP tools + built-in tools from a static scan, or infer from ToolSearch calls.
2. **Can we detect discovery failures at hook time?** An agent that uses Grep when ToolSearch+MCP tool would have been better — this is only visible in retrospect. May need user-feedback annotation.
3. **Sample bias:** Heavy sessions (sprints with many agents) will dominate. Weight by session or by event?
4. **Privacy:** Tool inputs may contain sensitive data. Reuse interspect's `_interspect_redact_secrets()`.

## Next Steps

1. Write plan with concrete tasks
2. Implement PostToolUseFailure hook in interstat
3. Enhance PostToolUse to capture tool context (available count, preceding ToolSearch)
4. Build JSONL classifier for post-hoc failure categorization
5. Create query scripts for the output contract
6. Ship, collect data for ~1 week, then feed into iv-3kpfu composition layer design
