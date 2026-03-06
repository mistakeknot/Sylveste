---
bead: iv-fo0rx
date: 2026-03-06
type: brainstorm
status: draft
---

# Canonical Landed-Change Entity

**Bead:** iv-fo0rx
**Question:** What is a "landed change" in Demarch, and how should it be represented as a first-class kernel entity?

## Problem Statement

iv-544dn found three competing definitions of "landed change" across the repo:

1. **Session-window commits** (`cost-query.sh baseline`): Count git commits whose timestamp falls within a session's start/end window. Simple but noisy — includes merge commits, reverts, and commits from other agents in the same repo.

2. **Closed beads joined to interstat** (`baseline.go`): Use closed beads as the denominator, correlate each bead's token spend via interstat. Semantically better (a bead represents intentional work) but conflates "closed" with "landed" — a bead can be closed without shipping code, and shipped code can land without a bead closing.

3. **Galiana phase-based inference** (`galiana/analyze.py`): Infer landed work from telemetry expectations around phase transitions. Most sophisticated but least transparent — the mapping from phases to outcomes is implicit.

None of these consume the strongest existing signal: `merge_intents.result_commit`, which durably records the exact commit SHA that a dispatch's code produced.

## Constraints

- Must work with the existing kernel schema (SQLite, `modernc.org/sqlite`, single-writer)
- Must be queryable from `ic` CLI and from interstat/cost-query.sh
- Must not require temp files for attribution (the whole point of iv-30zy3)
- Must support the north-star metric: **cost per landable change** (tokens spent / landed outcomes)
- Must support future needs: revert tracking, defect attribution, routing eval counterfactuals

## Design Space

### What constitutes a "landed change"?

A landed change is a **commit that reaches the trunk branch and stays there**. More precisely:

- A commit SHA on `main` (or the project's trunk branch)
- That was produced by an agent session or manual work
- That is attributable to a run, dispatch, bead, and/or session
- That has not been reverted

This is subtly different from all three current definitions:
- Not "any commit in a time window" (too broad)
- Not "a closed bead" (wrong abstraction level — beads are work items, not outcomes)
- Not "a phase transition" (an internal signal, not a durable fact)

### Granularity question: commit-level or bead-level?

**Option A: Commit-level entity (recommended)**

Each row in `landed_changes` represents one commit SHA that reached trunk. Multiple commits can map to one bead. This is the most granular and least lossy representation.

Pros:
- Directly observable (git log can verify)
- Supports partial landings (3 of 5 planned commits landed)
- Supports revert detection (commit X reverts commit Y)
- Natural join to `merge_intents.result_commit`

Cons:
- One bead may produce many commits — the "cost per landed change" denominator inflates
- Squash-merge workflows produce one commit per dispatch, but non-squash produces many

**Option B: Bead-level outcome entity**

Each row represents a bead's shipped outcome. The denominator is "beads that shipped code."

Pros:
- Stable denominator regardless of commit strategy
- Natural join to bead-level cost data

Cons:
- Loses commit-level granularity
- Can't track partial landings or reverts at fine grain
- A bead that touches 3 repos creates attribution ambiguity

**Option C: Dispatch-level outcome entity**

Each row represents one dispatch's outcome — the code it produced that landed.

Pros:
- Natural 1:1 with `merge_intents` (which is already dispatch-scoped)
- Supports multi-dispatch beads cleanly
- Cost attribution is straightforward (dispatch already has token counters)

Cons:
- Not all dispatches produce code that lands
- Manual work (non-dispatched) has no dispatch record

### Recommendation: Commit-level with aggregation views

Use commits as the atomic entity, but provide SQL views that aggregate to dispatch-level and bead-level for different consumers:

- `landed_changes` table: one row per landed commit
- `v_landed_by_dispatch`: aggregates commits to dispatch_id
- `v_landed_by_bead`: aggregates commits to bead_id (via dispatch -> run -> scope_id)
- `v_cost_per_landed_change`: joins landed_changes with token spend

The north-star metric (`cost_per_landable_change`) uses the **bead-level view** as its denominator — "how many tokens did we spend per bead that shipped code?" — while revert tracking and routing eval use the commit-level table.

## Proposed Schema

```sql
-- Canonical landed-change entity
CREATE TABLE IF NOT EXISTS landed_changes (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    commit_sha      TEXT NOT NULL,
    project_dir     TEXT NOT NULL,
    branch          TEXT NOT NULL DEFAULT 'main',

    -- Attribution chain (all nullable — not all landings have full lineage)
    dispatch_id     TEXT,           -- which dispatch produced this
    run_id          TEXT,           -- which run owned the dispatch
    bead_id         TEXT,           -- which bead scoped the run
    session_id      TEXT,           -- which session was active
    merge_intent_id INTEGER,        -- link to merge_intents row

    -- Lifecycle
    landed_at       INTEGER NOT NULL DEFAULT (unixepoch()),
    reverted_at     INTEGER,        -- set when a revert is detected
    reverted_by     TEXT,           -- commit SHA of the reverting commit

    -- Metadata
    files_changed   INTEGER,        -- stat from git diff
    insertions      INTEGER,
    deletions       INTEGER,

    UNIQUE(commit_sha, project_dir)
);
CREATE INDEX IF NOT EXISTS idx_landed_changes_project ON landed_changes(project_dir, landed_at);
CREATE INDEX IF NOT EXISTS idx_landed_changes_bead ON landed_changes(bead_id) WHERE bead_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_landed_changes_dispatch ON landed_changes(dispatch_id) WHERE dispatch_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_landed_changes_run ON landed_changes(run_id) WHERE run_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_landed_changes_session ON landed_changes(session_id) WHERE session_id IS NOT NULL;
```

### Recording mechanism

Two paths for populating `landed_changes`:

1. **Dispatch path (primary):** When `merge_intents` completes successfully, insert a `landed_changes` row with full attribution (dispatch_id, run_id from merge_intent, bead_id from run.scope_id, session_id from active session). This is the high-fidelity path.

2. **Manual/session path (fallback):** When a session ends with new commits on trunk that don't have merge_intent records, insert rows with partial attribution (session_id, maybe bead_id from session ledger, no dispatch_id). This catches manual work and non-dispatched agent work.

### Consuming the entity

The north-star metric becomes a simple query:

```sql
-- Cost per landed bead (the north-star denominator)
SELECT
    lc.bead_id,
    COUNT(DISTINCT lc.commit_sha) as commits,
    SUM(d.input_tokens + d.output_tokens) as total_tokens
FROM landed_changes lc
JOIN dispatches d ON d.scope_id = lc.run_id
WHERE lc.reverted_at IS NULL
  AND lc.bead_id IS NOT NULL
GROUP BY lc.bead_id;
```

### Revert detection

When a commit is detected as a revert (via `git log --format` parsing for "Revert" prefix or `revert:` trailer), update the original `landed_changes` row:

```sql
UPDATE landed_changes
SET reverted_at = ?, reverted_by = ?
WHERE commit_sha = ? AND project_dir = ?;
```

Reverted changes are excluded from the north-star denominator but included in defect-attribution analysis.

## Integration Points

### With iv-30zy3 (session attribution ledger)

The session ledger provides the `session_id -> bead_id -> run_id` join that `landed_changes` needs for the manual/session path. These two beads are complementary — iv-30zy3 provides the attribution chain, iv-fo0rx provides the outcome entity.

### With merge_intents (existing)

`merge_intents` already records `dispatch_id`, `run_id`, `base_commit`, and `result_commit`. The dispatch path for `landed_changes` is essentially: "when a merge_intent completes, also insert a landed_change."

### With interstat/cost-query.sh

`cost-query.sh baseline` currently counts session-window commits. It should switch to querying `landed_changes` via `ic` CLI. This eliminates the git-log-in-session-window approximation.

### With Galiana

`galiana/analyze.py` currently infers landed work from phase transitions. It should consume `landed_changes` (via `ic` CLI JSON output) instead of deriving its own estimate. This collapses all three definitions into one.

### With routing eval (iv-godia)

Routing eval needs to build historical counterfactual rows. With `landed_changes`, a counterfactual query becomes: "for this routing decision, what landed changes resulted?" — a direct join from routing decisions to outcomes.

## Open Questions

1. **Should `landed_changes` be populated eagerly (on merge_intent completion) or lazily (on query)?** Eager is simpler and ensures the record exists even if the query tooling changes. Recommend eager.

2. **How to handle squash merges vs. non-squash?** In a squash-merge workflow, one dispatch = one commit = one landed_change row. In a non-squash workflow, one dispatch may produce multiple commits. The schema handles both (multiple rows with same dispatch_id). The bead-level view aggregates correctly either way.

3. **Should the `ic` CLI expose `ic landed record` and `ic landed list`?** Yes — this makes the entity first-class and queryable from bash hooks, cost-query.sh, and Galiana.

4. **What about cross-repo landed changes?** A bead may produce commits in multiple repos. The `project_dir` column handles this — each repo gets its own rows. The bead-level view aggregates across repos naturally.

## Migration Path

1. Add `landed_changes` table to intercore schema (new migration)
2. Add `ic landed record` and `ic landed list` CLI commands
3. Wire merge_intent completion to auto-insert landed_changes (dispatch path)
4. Wire session-end hooks to insert landed_changes for unattributed commits (fallback path)
5. Update `cost-query.sh baseline` to query `ic landed list --json` instead of session-window git log
6. Update `baseline.go` to query landed_changes instead of correlating closed beads
7. Update Galiana to consume landed_changes instead of inferring from phases

Steps 1-4 are this bead (iv-fo0rx). Steps 5-7 are consumer migration (can be separate beads or part of this one depending on scope).
