---
agent: fd-migration-correctness
status: NEEDS_ATTENTION
finding_count: 3
---

## Findings

### [P0] Multi-statement DDL not wrapped in a transaction
**File:** tests/fixtures/severity-test-content.go
**Lines:** 20-41
**Issue:** `MigrateV12` executes three separate DDL statements — `CREATE TABLE audit_events`, `ALTER TABLE users ADD COLUMN last_audit_at`, `CREATE INDEX idx_audit_events_user` — outside of any transaction. Each statement is issued via a bare `db.Exec` call with no surrounding `BEGIN`/`COMMIT`. If `ALTER TABLE` succeeds and the `CREATE INDEX` fails (e.g., disk full, statement timeout, lock timeout), the schema is left in a partially-applied state: `audit_events` exists, `last_audit_at` is present on `users`, but the index is missing. No rollback path exists to undo what was already committed. Re-running the migration will fail immediately on `CREATE TABLE audit_events` with a "relation already exists" error, so forward progress is also blocked without manual intervention.
**Failure scenario:** Production database with millions of rows. `CREATE INDEX` times out. Service restarts, tries to run v12 again, and fails on the `CREATE TABLE`. The on-call engineer now must manually inspect which of the three DDL steps landed and apply the remainder by hand, under incident pressure. Any concurrent connection that read the partial schema between the `ALTER TABLE` success and the `CREATE INDEX` failure will observe an inconsistent view.
**Fix:** Wrap all three DDL statements in a single `sql.Tx`. Acquire the transaction with `db.BeginTx(ctx, nil)`, execute all three statements, and only call `tx.Commit()` after all succeed. Defer `tx.Rollback()` as a safety net. PostgreSQL supports transactional DDL, so the rollback will cleanly undo the partial work. Example structure:

```go
tx, err := db.BeginTx(ctx, nil)
if err != nil { return err }
defer tx.Rollback()
// ... all three Exec calls on tx ...
return tx.Commit()
```

---

### [P0] No concurrency guard on migration version insertion
**File:** tests/fixtures/severity-test-content.go
**Lines:** 14-69 (entire `MigrateV12` function)
**Issue:** The function contains no advisory lock, `SELECT ... FOR UPDATE`, or any other serialization mechanism before checking whether v12 has already been applied and before inserting the version record. The code shown does not even contain a version-check query or a version-insert at all — meaning two concurrent startup processes (rolling deploy, pod restart during upgrade) will both enter `MigrateV12`, both execute `CREATE TABLE audit_events`, and one will fail with a duplicate-table error after the other has already committed. Even if a version table check were added inline without a lock, the check-then-act window is a classic TOCTOU race.
**Failure scenario:** Kubernetes rolling deploy: old pod still running, new pod starts. Both call `MigrateV12`. Pod A executes `CREATE TABLE`; pod B, milliseconds later, also executes `CREATE TABLE` and gets an error. Depending on error handling upstream, pod B may crash-loop, leaving the service degraded. If the advisory lock is absent at the framework level and each migration is a standalone function like this one, there is no protection at all.
**Fix:** Acquire a PostgreSQL advisory lock before any schema mutation, and hold it for the duration of the migration. Use `pg_try_advisory_lock` or `pg_advisory_lock` on a stable numeric key derived from the migration version. Alternatively, use an `INSERT INTO schema_migrations ... ON CONFLICT DO NOTHING` with `RETURNING` to atomically claim execution rights before running DDL. Release the advisory lock in a deferred call after `Commit`.

---

### [P1] Backfill INSERT errors silently discarded — partial backfill undetectable
**File:** tests/fixtures/severity-test-content.go
**Lines:** 57-65
**Issue:** The INSERT inside the backfill loop (`db.Exec(...)`) discards both return values. If any insert fails — due to a constraint violation, a full tablespace, a transient connection error, or a conflict on `user_id` — the error is silently swallowed. The loop continues, some users receive their seed `audit_events` row and others do not. `MigrateV12` returns `nil`, signaling success to the caller. The version table (if one existed) would record v12 as complete. There is no way to detect the partial state after the fact without a cross-table count query.
**Failure scenario:** Halfway through a 500k-user backfill, a constraint violation fires (e.g., a duplicate `(user_id, event_type)` unique index added in a later migration that was already partially applied). The loop silently skips the remaining rows. The service deploys, audit queries for the skipped users return no historical events, and the gap looks like a data retention issue rather than a migration bug. Root-causing requires comparing `users` count against `audit_events WHERE event_type = 'account_created'` count — a non-obvious forensic query.
**Fix:** Check the error return from every `db.Exec` call. At minimum, return the error immediately to halt the migration and allow a retry. For large backfills, consider wrapping the entire loop in a transaction (or batching into chunks of N rows per transaction) so that a partial backfill is fully rolled back and the migration is retried cleanly on restart. At minimum:

```go
if _, err := db.Exec(...); err != nil {
    return fmt.Errorf("backfill user %d: %w", userID, err)
}
```
