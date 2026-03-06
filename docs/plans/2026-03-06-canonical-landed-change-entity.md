---
bead: iv-fo0rx
date: 2026-03-06
type: plan
status: active
brainstorm: docs/brainstorms/2026-03-06-canonical-landed-change-entity.md
---

# Plan: Canonical Landed-Change Entity

## Summary

Add a `landed_changes` table to the Intercore kernel schema and expose it through `ic landed` CLI commands. This creates the single canonical definition of "landed change" that replaces three competing approximations.

## Steps

### 1. Add migration 025_landed_changes.sql

**File:** `core/intercore/internal/db/migrations/025_landed_changes.sql`

Create the `landed_changes` table with full attribution chain:

```sql
CREATE TABLE IF NOT EXISTS landed_changes (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    commit_sha      TEXT NOT NULL,
    project_dir     TEXT NOT NULL,
    branch          TEXT NOT NULL DEFAULT 'main',
    dispatch_id     TEXT,
    run_id          TEXT,
    bead_id         TEXT,
    session_id      TEXT,
    merge_intent_id INTEGER,
    landed_at       INTEGER NOT NULL DEFAULT (unixepoch()),
    reverted_at     INTEGER,
    reverted_by     TEXT,
    files_changed   INTEGER,
    insertions      INTEGER,
    deletions       INTEGER,
    UNIQUE(commit_sha, project_dir)
);
```

Plus indexes on project_dir, bead_id, dispatch_id, run_id, session_id.

**Update** `schema.sql` with the same table definition for fresh installs.

**Update** `PRAGMA user_version` in the migrator to 25.

### 2. Add landed_changes store (internal/landed/)

**File:** `core/intercore/internal/landed/store.go`

LandedStore with methods:
- `Record(ctx, LandedChange) (int64, error)` — insert or ignore (UNIQUE constraint handles idempotency)
- `MarkReverted(ctx, commitSHA, projectDir, revertedBy string) error`
- `List(ctx, ListOpts) ([]LandedChange, error)` — with filters: project_dir, bead_id, run_id, session_id, since/until, include_reverted
- `Summary(ctx, SummaryOpts) (*LandedSummary, error)` — aggregated stats: count, by-bead, by-run

The `LandedChange` struct mirrors the table columns.

### 3. Wire CompleteIntent to auto-record landed changes

**File:** `core/intercore/internal/dispatch/intent.go`

Add an optional callback to `IntentStore` that fires after `CompleteIntent` succeeds. The callback receives the intent (with dispatch_id, run_id, result_commit) and inserts a `landed_changes` row.

The callback is set during store initialization — the CLI layer provides it, connecting IntentStore to LandedStore without introducing a direct dependency.

Update `CompleteIntent` to call the callback after the UPDATE succeeds:
```go
if s.onComplete != nil {
    s.onComplete(ctx, intent)
}
```

### 4. Add `ic landed` CLI commands

**File:** `core/intercore/cmd/ic/landed.go`

Subcommands:
- `ic landed record --commit=<sha> --project=<dir> [--dispatch=<id>] [--run=<id>] [--bead=<id>] [--session=<id>] [--branch=<branch>] [--files=N] [--insertions=N] [--deletions=N]` — manually record a landed change
- `ic landed list [--project=<dir>] [--bead=<id>] [--run=<id>] [--session=<id>] [--since=<iso>] [--include-reverted]` — list landed changes (JSON with --json)
- `ic landed revert --commit=<sha> --project=<dir> --reverted-by=<sha>` — mark a commit as reverted
- `ic landed summary [--project=<dir>] [--bead=<id>] [--since=<iso>] [--days=N]` — aggregated stats

Wire into `main.go` switch statement:
```go
case "landed":
    exitCode = cmdLanded(ctx, subArgs)
```

### 5. Wire IntentStore callback in CLI initialization

**File:** `core/intercore/cmd/ic/dispatch.go` (or wherever IntentStore is constructed)

When the CLI creates an IntentStore, set the `onComplete` callback to insert into `landed_changes`:

```go
intentStore.OnComplete = func(ctx context.Context, intent *dispatch.MergeIntent) {
    // Look up dispatch to get scope/run info
    // Insert landed_changes row
}
```

### 6. Tests

**Files:**
- `core/intercore/internal/landed/store_test.go` — unit tests for Record, List, MarkReverted, Summary, idempotent upsert
- `core/intercore/internal/dispatch/intent_test.go` — add test for CompleteIntent firing callback
- `core/intercore/cmd/ic/landed_test.go` or add to integration test script

### 7. Update schema.sql

**File:** `core/intercore/internal/db/schema.sql`

Add the `landed_changes` table definition alongside other tables. Keep in sync with migration.

## Scope boundary

Steps 1-7 are this bead. Consumer migration (updating cost-query.sh, baseline.go, and Galiana to consume `landed_changes` instead of their current approximations) is out of scope — those are follow-on tasks that depend on this entity existing.

## Files touched

- `core/intercore/internal/db/migrations/025_landed_changes.sql` (new)
- `core/intercore/internal/db/schema.sql` (edit)
- `core/intercore/internal/landed/store.go` (new)
- `core/intercore/internal/landed/store_test.go` (new)
- `core/intercore/internal/dispatch/intent.go` (edit — add callback)
- `core/intercore/internal/dispatch/intent_test.go` (edit — test callback)
- `core/intercore/cmd/ic/landed.go` (new)
- `core/intercore/cmd/ic/main.go` (edit — add case)

## Estimated effort

Moderate. ~2-3 hours. No external dependencies, no cross-module coordination needed.
