# Sprint Completion Rate Tracking

**Bead:** iv-a0mv
**Date:** 2026-03-15
**Complexity:** 3/5 (moderate)

## Goal

Track sprint completion rate (% reaching `done` phase without abandonment). Expose via `clavain-cli sprint-stats` subcommand. Target from clavain-vision.md: >70% for complexity ≤3.

## Data Source

All data lives in intercore's `runs` table (`ic run list`). Key columns:
- `status`: active | completed | cancelled
- `phase`: brainstorm | ... | done (9-step sequence)
- `complexity`: integer 1-5
- `created_at`, `completed_at`: timestamps
- `project_dir`: for per-project filtering

Current data: 16 runs (1 completed/done, 14 cancelled, 1 active).

## Definition of Completion

- **Completed** = `status='completed'` AND `phase='done'`
- **Abandoned** = `status='cancelled'` (any phase)
- **Active** = `status='active'` (excluded from rate calculation — still in progress)
- **Completion rate** = `completed / (completed + abandoned) * 100`

## Steps

### Step 1: Add `sprint-stats` subcommand to clavain-cli

**File:** `os/clavain/cmd/clavain-cli/sprint.go`

Add `cmdSprintStats()` function that:
1. Calls `ic run list` and parses output (or queries via `ic` SQL interface)
2. Groups runs by status (completed, cancelled, active)
3. Computes completion rate overall and per-complexity tier
4. Outputs structured JSON (for programmatic use) or formatted table (for human use)

**Register in main.go:** Add `case "sprint-stats":` dispatching to `cmdSprintStats(args)`.

### Step 2: Add `--complexity` and `--since` flags

- `--complexity=N` — filter to runs with complexity ≤ N (default: all)
- `--since=DURATION` — filter to runs created within duration (e.g., `7d`, `30d`; default: all time)
- `--json` — output as JSON instead of table
- `--project` — filter by project_dir (default: current directory)

### Step 3: Implementation detail

Query `ic` database directly via the same DB path used by other clavain-cli commands:

```sql
SELECT
  complexity,
  COUNT(*) as total,
  COUNT(CASE WHEN status = 'completed' AND phase = 'done' THEN 1 END) as completed,
  COUNT(CASE WHEN status = 'cancelled' THEN 1 END) as abandoned,
  COUNT(CASE WHEN status = 'active' THEN 1 END) as active
FROM runs
WHERE (? = 0 OR complexity <= ?)        -- complexity filter
  AND (? = 0 OR created_at >= ?)        -- since filter
  AND (? = '' OR project_dir = ?)       -- project filter
GROUP BY complexity
ORDER BY complexity;
```

Plus an aggregate row for totals.

### Step 4: Human-readable output format

```
Sprint Completion Rate
──────────────────────
                 Completed  Abandoned  Active  Rate
  Complexity 1         2          0       0   100.0%
  Complexity 2         3          1       1    75.0%
  Complexity 3         5          3       0    62.5%  ← below target (70%)
  Complexity 4         1          2       0    33.3%
  Complexity 5         0          1       0     0.0%
  ─────────────────────────────────────────────────
  Total               11          7       1    61.1%

Target: >70% for complexity ≤3 → Current: 71.4% (10/14) ✓
```

### Step 5: Add to sprint.md command documentation

Add a note in the Ship step that `sprint-stats` can be run to see completion metrics.

### Step 6: Wire into `/clavain:sprint-status` command

The existing `sprint-status.md` command shows sprint state. Add completion rate summary to its output by calling `clavain-cli sprint-stats --json`.

## Test Plan

- [ ] `clavain-cli sprint-stats` with current data (16 runs)
- [ ] `clavain-cli sprint-stats --complexity=3` filters correctly
- [ ] `clavain-cli sprint-stats --json` outputs valid JSON
- [ ] `clavain-cli sprint-stats --since=7d` time filtering works
- [ ] Rate calculation handles edge cases: 0 runs, all active, all cancelled

## Non-Goals

- No streaming/continuous monitoring (can be added later)
- No dashboard (CLI output is sufficient for now)
- No schema changes (query existing tables only)
