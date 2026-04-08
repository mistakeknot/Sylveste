---
agent: fd-error-propagation
status: NEEDS_ATTENTION
finding_count: 3
---

## Findings

### [P0] INSERT errors silently discarded during backfill loop
**File:** tests/fixtures/severity-test-content.go
**Lines:** 60-64
**Issue:** `db.Exec(...)` is called without capturing the error return. Both the `sql.Result` and `error` values are discarded (`_ , _` implicitly). If any INSERT fails mid-backfill, the loop continues and `MigrateV12` returns `nil`, telling the caller the migration succeeded.
**Failure scenario:** A constraint violation (duplicate `user_id`, FK miss, payload too large) or transient DB error causes one or more INSERT rows to fail. The backfill is partially applied — some users have a seed audit event, others do not. There is no log entry, no error return, and no way for the caller to detect the inconsistency. The schema version is then bumped to v12 and the migration never reruns. The missing seed events may silently corrupt downstream audit queries or reporting at any later point.
**Fix:** Capture the error and return it (wrapped) immediately, or accumulate errors and return a combined error after the loop:
```go
if _, err := db.Exec(...); err != nil {
    return fmt.Errorf("backfill audit event for user %d: %w", userID, err)
}
```

---

### [P0] `rows.Close()` error silently dropped; late-stream DB errors lost
**File:** tests/fixtures/severity-test-content.go
**Lines:** 48, 65 (deferred `rows.Close()`)
**Issue:** `rows.Close()` is called via `defer rows.Close()` and its error return is ignored. PostgreSQL drivers can surface row-iteration errors on `Close()` (e.g., the server aborted the cursor mid-stream). Additionally, `rows.Err()` is never checked after the loop.
**Failure scenario:** The DB server aborts the `SELECT id, email FROM users` cursor midway (e.g., query timeout, server restart). `rows.Next()` returns false, the loop exits normally, and `rows.Err()` — which holds the transport error — is never inspected. `rows.Close()` may also return that error, but it is discarded by the deferred call. `MigrateV12` returns `nil`. The backfill ran for only a subset of users; the rest are silently skipped.
**Fix:** Check `rows.Err()` after the loop and propagate `rows.Close()` errors:
```go
if err := rows.Err(); err != nil {
    return fmt.Errorf("iterate users: %w", err)
}
// For Close, replace defer with explicit call:
if err := rows.Close(); err != nil {
    return fmt.Errorf("close users cursor: %w", err)
}
```

---

### [P1] `StartAuditWorker` swallows worker errors; caller has no signal on persistent write failures
**File:** tests/fixtures/severity-test-content.go
**Lines:** 73-88
**Issue:** The goroutine launched by `StartAuditWorker` logs DB write failures with `log.Printf` but has no mechanism to surface them to the caller. The function returns nothing (`void`). Persistent failures (e.g., table dropped, credentials revoked) are invisible outside the log stream.
**Failure scenario:** The `audit_events` table is dropped or the DB connection is permanently broken. Every event write fails. The `log.Printf` line fires in a background goroutine with no rate limiting — under sustained load this floods logs. The caller (application startup or request handler) receives no signal and cannot decide to circuit-break, alert, or halt ingestion. Audit events are silently lost without any caller-visible error state.
**Fix:** Change the signature to return an error channel (or accept a context and an error callback) so persistent failures propagate:
```go
func StartAuditWorker(ctx context.Context, db *sql.DB, events <-chan AuditEvent) <-chan error {
    errc := make(chan error, 1)
    go func() {
        defer close(errc)
        for evt := range events {
            if _, err := db.Exec(...); err != nil {
                // non-blocking send so worker doesn't stall
                select {
                case errc <- fmt.Errorf("audit worker write: %w", err):
                default:
                }
            }
        }
    }()
    return errc
}
```
