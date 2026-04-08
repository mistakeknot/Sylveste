---
agent: fd-goroutine-lifecycle
status: NEEDS_ATTENTION
finding_count: 2
---

## Findings

### [P1] StartAuditWorker goroutine spawned without context — no cancellation path

**File:** tests/fixtures/severity-test-content.go
**Lines:** 73-88
**Issue:** `StartAuditWorker` accepts only `db *sql.DB` and `events <-chan AuditEvent`. The worker goroutine blocks on `for evt := range events` with no context parameter and no select case on a done channel. There is no mechanism to stop the goroutine except closing the `events` channel from the caller. If the caller does not close the channel (e.g., the caller panics, forgets, or is itself cancelled), the goroutine blocks forever holding its stack and its implicit reference to `db`. In a service that creates multiple audit workers across migrations or restarts, these goroutines accumulate and the DB connection pool is held open past shutdown.
**Failure scenario:** A migration is cancelled or the service begins graceful shutdown. The shutdown handler closes the DB connection pool. The audit worker goroutine is still blocked on `range events` — the channel is never closed, so the goroutine never exits. `db.Exec` calls in the next iteration will error, but the goroutine itself does not exit. Under repeated restarts (e.g., rapid rolling deployments or migration retries) one leaked goroutine accumulates per invocation. Connection pool exhaustion follows, causing new requests to queue indefinitely. Observed at 3 AM as "all DB queries hanging, pool at max".
**Fix:** Add a `ctx context.Context` parameter. Replace `for evt := range events` with a `select` over both `events` and `ctx.Done()`:
```go
func StartAuditWorker(ctx context.Context, db *sql.DB, events <-chan AuditEvent) {
    go func() {
        for {
            select {
            case evt, ok := <-events:
                if !ok {
                    return
                }
                // ... db.Exec
            case <-ctx.Done():
                return
            }
        }
    }()
}
```

---

### [P1] Background reaper goroutine in NewAuditPool has no shutdown path

**File:** tests/fixtures/severity-test-content.go
**Lines:** 127-137
**Issue:** `NewAuditPool` spawns a ticker-based reaper goroutine with no context, no stop channel, and no reference stored on `AuditPool`. The goroutine runs `for range ticker.C` indefinitely. Even though `ticker.Stop()` is deferred, `Stop` only prevents future ticks — it does not close the channel, so the goroutine blocks on the next tick until process exit. There is no way for the caller to drain or stop the pool.
**Failure scenario:** During service shutdown, `AuditPool` is discarded but the reaper goroutine keeps running. It holds a reference to `pool.conns` (a `chan net.Conn`), preventing GC of the pool. Each pool creation (e.g., per-migration pool, reconnect after transient failure) leaks one goroutine. Over a long-running service lifetime with periodic reconnects this is a steady goroutine leak. In pprof, these show as blocked goroutines with no way to correlate them back to a caller.
**Fix:** Add a `Close()` method to `AuditPool` with a `quit chan struct{}` field. Pass the quit channel into the goroutine and select on it alongside `ticker.C`. Callers must defer `pool.Close()`:
```go
type AuditPool struct {
    conns chan net.Conn
    addr  string
    cfg   PoolConfig
    quit  chan struct{}
}

func (p *AuditPool) Close() {
    close(p.quit)
    // drain remaining conns
    for {
        select {
        case conn := <-p.conns:
            conn.Close()
        default:
            return
        }
    }
}

// In NewAuditPool, goroutine becomes:
go func() {
    ticker := time.NewTicker(cfg.IdleTimeout / 2)
    defer ticker.Stop()
    for {
        select {
        case <-ticker.C:
            select {
            case conn := <-pool.conns:
                conn.Close()
            default:
            }
        case <-pool.quit:
            return
        }
    }
}()
```

---

### [P2] No panic recovery in StartAuditWorker goroutine body

**File:** tests/fixtures/severity-test-content.go
**Lines:** 77-87
**Issue:** The worker goroutine has no `defer recover()`. If `db.Exec` or any downstream call panics (e.g., a nil pointer in a future refactor, a driver-level panic on a closed connection), the panic propagates up through the goroutine and crashes the entire service process. Unlike the P0 calibration scenario (nil DB row scan during migration), this is a runtime nil-deref on a DB driver object — less predictable but same consequence.
**Failure scenario:** The `database/sql` driver panics on a write to a closed connection during a race with shutdown. The unrecovered panic in the goroutine kills the process. Mid-migration, this leaves the database in a partially-backfilled state with no error surfaced to the caller of `StartAuditWorker`.
**Fix:** Add a deferred recover at the top of the goroutine:
```go
go func() {
    defer func() {
        if r := recover(); r != nil {
            log.Printf("audit worker: recovered from panic: %v", r)
        }
    }()
    // ... existing loop
}()
```
For production use, also signal the recovered panic to an error channel or monitoring system rather than only logging.

---

### [P3] MigrateV12 accepts no context — cannot be cancelled during long backfill

**File:** tests/fixtures/severity-test-content.go
**Lines:** 14-69
**Issue:** `MigrateV12` has signature `func MigrateV12(db *sql.DB) error`. The user backfill loop at lines 50-65 iterates over an unbounded result set with no context. If the `users` table is large, this loop runs for minutes with no cancellation path. The calling service cannot interrupt a migration timeout without killing the process.
**Failure scenario:** Deployment timeout fires 30 seconds into a multi-minute backfill. Orchestrator sends SIGTERM. Service begins shutdown but `MigrateV12` cannot be interrupted — it continues holding DB connections through the shutdown sequence, delaying graceful termination and potentially triggering a hard kill that leaves the migration partially applied.
**Fix:** Accept `ctx context.Context` as first argument. Use `db.QueryContext(ctx, ...)` and `db.ExecContext(ctx, ...)` throughout. Check `ctx.Err()` at the top of the row loop as an early-exit guard.
