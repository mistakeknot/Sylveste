---
agent: fd-persistence-integrity
status: NEEDS_ATTENTION
finding_count: 3
---

## Findings

### [P0] Schema DDL and migration state written outside any transaction
**File:** tests/fixtures/severity-test-content.go
**Lines:** 20–41
**Issue:** `MigrateV12` executes three DDL statements (`CREATE TABLE`, `ALTER TABLE`, `CREATE INDEX`) using bare `db.Exec` calls — no transaction wraps them and no migration-state record is written atomically with them. If the process crashes after any DDL commits but before the caller records the migration as applied, the migration will appear unapplied on restart and re-run against a partially-altered schema.
**Failure scenario:** Application starts. `CREATE TABLE audit_events` commits. Process crashes (OOM, SIGKILL, deploy restart). On next startup the migration runner sees schema version < 12, calls `MigrateV12` again, hits `CREATE TABLE audit_events` — which now fails with "already exists" — and either panics or skips silently depending on error handling upstream. The `ALTER TABLE` half of the migration may or may not have committed, leaving `last_audit_at` absent or present unpredictably. Even without a crash, a mid-function error (e.g., `ALTER TABLE` fails because the column already exists from a prior partial run) leaves the first DDL permanently committed with no rollback path.
**Fix:** Wrap all DDL and the migration-state persistence write in a single `db.BeginTx` / `tx.Commit` block. Note that some databases (e.g., MySQL) do not support transactional DDL; for those, use a pre-flight idempotency check (`IF NOT EXISTS`) before each statement and record state atomically with the final DDL step.

---

### [P0] Backfill INSERT errors silently discarded — partial batch committed without detection
**File:** tests/fixtures/severity-test-content.go
**Lines:** 57–65
**Issue:** The backfill loop calls `db.Exec(...)` and discards both the result and the error. If any INSERT fails (constraint violation, connection error, serialization failure), execution continues to the next row. `MigrateV12` returns `nil` after the loop, signalling success to the migration runner even though an arbitrary subset of users received no seed audit event.
**Failure scenario:** Row N fails (e.g., a concurrent delete of the user between the SELECT and the INSERT causes a FK violation). The migration runner marks v12 applied. Post-migration queries that join `users` with `audit_events` on the assumption that every pre-existing user has a seed event will return wrong results. Because no error is surfaced, no alert fires and the inconsistency is discovered only when user-facing features behave incorrectly. The entire backfill also runs outside the outer transaction (which doesn't exist — see P0 above), so there is no mechanism to roll back the partial write.
**Fix:** Capture and return the error from every `db.Exec` call inside the loop. Run the entire backfill inside a transaction so a single failure rolls back all inserts for the batch. If partial-batch tolerance is required by design, log each failure with enough context (user ID, error) to enable a targeted repair query, and surface a final non-nil error to the caller so the migration runner does not mark the migration complete.

---

### [P1] Missing `defer tx.Rollback()` on every early-return path (structural gap)
**File:** tests/fixtures/severity-test-content.go
**Lines:** 14–69
**Issue:** `MigrateV12` does not open a transaction at all (see P0), so there is currently no `tx.Rollback()` to omit. However, the fix for the P0 finding will introduce a `sql.Tx`. The existing code structure — multiple sequential error-return points before `tx.Commit()` — is the exact pattern where `defer tx.Rollback()` must be placed immediately after `tx, err := db.BeginTx(...)`. The in-loop early returns on `rows.Scan` error (line 54) and per-row exec error (once fixed) are additional exit paths that must be covered.
**Failure scenario:** A context cancellation (e.g., from a deployment shutdown signal) arrives mid-migration after the transaction is opened but before `tx.Commit()`. Without `defer tx.Rollback()`, the transaction remains open, holding row locks on `users` and blocking concurrent reads on Postgres's `ShareRowExclusiveLock` until the connection is eventually recycled by the pool. Under a rolling restart this can cause a cascade of blocked queries for tens of seconds.
**Fix:** Immediately after `tx, err := db.BeginTx(ctx, nil)` add `defer tx.Rollback()`. This is safe because `Rollback` on an already-committed transaction is a no-op in `database/sql`.
