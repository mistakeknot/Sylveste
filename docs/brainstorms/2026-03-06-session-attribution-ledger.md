---
bead: iv-30zy3
date: 2026-03-06
type: brainstorm
status: draft
---

# Durable Session Attribution Ledger

**Bead:** iv-30zy3
**Question:** How should Demarch replace temp-file session attribution with a durable kernel-backed ledger?

## Problem Statement

Session-to-bead-to-run attribution currently flows through temp files:

| Temp file | Purpose | Failure mode |
|---|---|---|
| `/tmp/interstat-session-id` | Session persistence | Lost on crash; stale across restarts |
| `/tmp/interstat-bead-{session_id}` | Session→Bead mapping | Invisible drift when bead changes |
| `/tmp/interstat-phase-{bead_id}` | Bead→Phase mapping | Stale after crashes |

This was flagged as F2 [P0] in iv-544dn: "Session, bead, and phase attribution still depend on temp files." The Demarch vision says "if it matters, it's in the database." These joins matter for:

- North-star metric (cost per landable change) — needs session→bead→tokens
- Routing eval (iv-godia) — needs session→run→dispatch→outcome
- Interspect canary policy — needs session→bead→override association
- Coverage metrics — needs to detect dark/unattributed sessions

## Constraints

- Must use existing kernel DB (`modernc.org/sqlite`, single-writer, Go)
- Must be queryable via `ic` CLI (bash hooks shell out to `ic`)
- Must not break existing interstat hooks during migration (dual-write period)
- Must support the attribution chain: `session_id → bead_id → run_id → phase → project_dir`
- Must handle multi-project sessions (one session can work across repos)
- Must handle bead changes mid-session (route discovers new work)

## Current Durable Surface

The kernel already has `session_id` fields on 4 tables:
- `interspect_events.session_id` — human corrections
- `review_events.session_id` — disagreement resolution
- `landed_changes.session_id` — landed commit attribution (v25)
- `audit_log.session_id` — tamper-evident trail (v15)

But there is **no `sessions` table** — these are orphan foreign keys with no parent entity. There is no authoritative record of "session X started at time T, worked on bead Y under run Z in phase P in project D."

## Design Space

### What is a session?

A session is a single invocation of an AI agent (Claude Code session, Codex CLI run, etc.) that:
- Has a unique `session_id` (UUID)
- Starts at a known time
- Ends at a known time (or is abandoned)
- Works in one or more `project_dir` contexts
- May claim zero or more beads during its lifetime
- May operate under zero or more runs

### Key design tension: session→bead is N:M

A session can work on multiple beads (route discovers new work mid-session). A bead can be worked on by multiple sessions (handoff, concurrent agents). The temp-file model assumes 1:1 (one bead file per session). The durable model must support M:N.

### Option A: Single `session_ledger` table with current-state columns

```sql
CREATE TABLE session_ledger (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id      TEXT NOT NULL,
    bead_id         TEXT,
    run_id          TEXT,
    phase           TEXT,
    project_dir     TEXT NOT NULL,
    agent_type      TEXT NOT NULL DEFAULT 'claude-code',
    started_at      INTEGER NOT NULL DEFAULT (unixepoch()),
    ended_at        INTEGER,
    metadata        TEXT,  -- JSON: model, plugin versions, etc.
    UNIQUE(session_id, project_dir)
);
```

Pros: Simple, single row per session+project. Direct replacement for temp files.
Cons: Can't track bead changes mid-session. Last-write-wins for bead_id.

### Option B: Session header + attribution events (recommended)

Two tables: a session header (lifecycle) and attribution events (changes):

```sql
-- Session lifecycle (one row per session per project)
CREATE TABLE sessions (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id      TEXT NOT NULL,
    project_dir     TEXT NOT NULL,
    agent_type      TEXT NOT NULL DEFAULT 'claude-code',
    model           TEXT,
    started_at      INTEGER NOT NULL DEFAULT (unixepoch()),
    ended_at        INTEGER,
    metadata        TEXT,  -- JSON: plugin versions, host info
    UNIQUE(session_id, project_dir)
);

-- Attribution changes within a session (append-only)
CREATE TABLE session_attributions (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id      TEXT NOT NULL,
    project_dir     TEXT NOT NULL,
    bead_id         TEXT,
    run_id          TEXT,
    phase           TEXT,
    created_at      INTEGER NOT NULL DEFAULT (unixepoch())
);
```

Pros: Full history of bead changes. Supports M:N. Append-only events are auditable.
Cons: Two tables, slightly more complex queries.

### Option C: Use existing `state` table (key-value)

```bash
ic state set "session.bead_id" "$session_id" <<< "$bead_id"
ic state set "session.run_id" "$session_id" <<< "$run_id"
ic state set "session.phase" "$session_id" <<< "$phase"
```

Pros: Zero schema changes. Already works.
Cons: No lifecycle tracking. No history. No joins with other tables. Awkward for aggregation queries.

### Recommendation: Option B (session header + attribution events)

Option B is the right balance. It provides:
- A proper parent entity for the orphan `session_id` foreign keys across the schema
- Full history of bead/run/phase changes for debugging and replay
- Simple current-state queries via `ORDER BY created_at DESC LIMIT 1`
- Clean integration with existing `ic` CLI patterns

## Proposed CLI Interface

Following the existing `ic <command> <subcommand>` pattern:

```bash
# Register session start (called from session-start hooks)
ic session start --session="$CLAUDE_SESSION_ID" --project="$(pwd)" --agent-type=claude-code

# Update attribution (replaces temp-file writes)
ic session attribute --session="$CLAUDE_SESSION_ID" --bead="$BEAD_ID" --run="$RUN_ID" --phase="$PHASE"

# Record session end
ic session end --session="$CLAUDE_SESSION_ID"

# Query current attribution for a session (replaces temp-file reads)
ic session current --session="$CLAUDE_SESSION_ID" --json

# List sessions (debugging, metrics)
ic session list --project="$(pwd)" --since=24h --json
```

## Migration Strategy

### Phase 1: Dual-write (this bead)

1. Add `sessions` + `session_attributions` tables (v26 migration)
2. Add `ic session` CLI commands
3. Update interstat `session-start.sh` to call `ic session start` AND write temp file
4. Update clavain route/sprint to call `ic session attribute` AND write temp file
5. Update interstat `session-end.sh` to call `ic session end`

### Phase 2: Consumer migration (separate beads)

6. Update interstat `post-task.sh` to read from `ic session current` instead of temp files
7. Update `cost-query.sh` to join through `sessions` table
8. Update Galiana to consume `sessions` + `landed_changes`

### Phase 3: Temp-file removal (cleanup bead)

9. Remove temp-file writes (once all consumers migrated)
10. Remove temp-file reads

This bead covers Phase 1 only. Phase 2-3 are separate follow-on work.

## Integration Points

### With landed_changes (v25, iv-fo0rx)

`landed_changes.session_id` is already a column. Once `sessions` exists, it becomes a joinable FK:
```sql
SELECT s.bead_id, lc.commit_sha, lc.landed_at
FROM sessions s
JOIN session_attributions sa ON sa.session_id = s.session_id
JOIN landed_changes lc ON lc.session_id = s.session_id
WHERE sa.bead_id IS NOT NULL;
```

### With runs (v3)

`runs.scope_id` holds the bead_id by convention. `session_attributions.run_id` provides the explicit join that `runs` doesn't have for sessions.

### With interstat

Interstat's `agent_runs` table in its own SQLite DB currently uses temp files for bead/phase. After migration, it can read from `ic session current` instead.

## Open Questions

1. **Should `sessions` be in the intercore DB or a separate interstat DB?** Recommendation: intercore DB — this is a kernel concern (attribution chain), not a measurement concern.

2. **Should `session_attributions` be an event table or a mutable current-state table?** Recommendation: append-only events — cheaper writes, full history, matches the kernel's event-sourced pattern.

3. **How to handle sessions that span multiple projects?** One `sessions` row per (session_id, project_dir) pair. A session working in both Demarch and Clavain gets two rows.

4. **What metadata to capture?** Minimum: agent_type, model. Nice to have: plugin versions, host identity, Claude session ID format. Start minimal, add columns via future migrations.
