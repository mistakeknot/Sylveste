---
artifact_type: reflection
bead: sylveste-bcok
sprint_step: reflect
session: 5e8c849d-11f7-4152-b47b-47ba578f047b
---

# Reflection: interop Plan Review + P0/P1 Fixes

## What went well

1. **4-agent parallel review caught structural wiring gaps that unit tests couldn't.** The bus dispatch pipeline was structurally disconnected — events went into entity channels but nothing read them out. Tests passed because they tested components in isolation (CollisionWindow, DispatchToAdapters). Only the integration-level review caught that these components weren't connected.

2. **Deduplication across agents was clean.** 3 of 4 agents independently found the CollisionWindow-unwired P0. This convergence gave high confidence the finding was real and critical. The dedup step reduced 14 raw P0s to 5 unique ones.

3. **Fixing the code after the review was fast** because the review agents provided specific file references and concrete fix patterns. The bus.go rewrite took one pass because the two-stage dispatch design was already specified.

## What to improve

1. **Phase 1 was committed before plan review.** The existing commits (`feat(interop): complete Phase 1`) shipped code that had 4 P0 bugs. The sprint should have caught this — plan review (Step 4) should run before any execution commit, not after. For future epics: don't mark Phase 1 "complete" until the plan review gate passes.

2. **No end-to-end integration test exists.** All tests pass, but there's no test that verifies: adapter emits event → bus routes to entity channel → collision window checks → flusher releases → target adapter receives. The current bus_test.go tests CollisionWindow in isolation. A daemon-level integration test that wires mock adapters through the full pipeline would catch the class of bug found by this review.

3. **Entity channel GC was removed entirely** rather than fixed. For Phase 1 scale (hundreds of entities) this is fine, but Phase 2+ will need a proper lifecycle model where GC coordinates with consumer goroutines. Track this as tech debt.

## Key learnings

- **Integration seams are where bugs hide.** Components designed in isolation and tested in isolation pass their tests. The bugs emerge at the boundaries — where CollisionWindow.Check should be called, where dispatchToAdapters should be invoked, where shutdown should wait.

- **The `atomic.Int64` pattern for timestamps** is the right Go approach for concurrent access to time values. Storing `UnixNano()` avoids the data race that `time.Time` struct assignment causes.

- **SQLite `SetMaxOpenConns(1)` is non-optional** for `modernc.org/sqlite`. The default unlimited pool creates multiple file descriptors to the same WAL database, making shutdown behavior unpredictable.
