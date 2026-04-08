---
artifact_type: flux-drive-synthesis
plan: docs/plans/2026-04-07-interop.md
bead: sylveste-bcok
date: 2026-04-07
agents:
  - fd-bidirectional-sync-conflicts
  - fd-adapter-interface-contracts
  - fd-dependency-ordering
  - fd-migration-correctness
  - fd-go-concurrency-safety
  - fd-acceptance-criteria-quality
verdict: needs-attention
p0_count: 3
p1_count: 12
---

# Flux-Drive Synthesis: interop Implementation Plan

**Verdict: needs-attention**
**P0 findings: 3** | **P1 findings: 12** | **P2 findings: 12**

The plan is architecturally sound and has addressed the full set of flux-review P0/P1s from the brainstorm and PRD reviews. However, three P0s and twelve P1s surfaced in the implementation plan itself — all fixable with targeted amendments, none requiring architectural changes. The two most urgent P0s are Go data races in the EventBus and CollisionWindow that would be caught immediately by `go test -race`. The third P0 is a task-ordering bug where Task 1.5 has a compile-time dependency on Task 1.8.

---

## P0 Findings

### P0-1: EventBus per-entity channel map — data race
**Agent:** fd-go-concurrency-safety | **Task:** 1.4

`map[EntityKey]chan Event` is described as "created on demand, GC'd after 60s idle" with no synchronization specified. Two adapters emitting events for the same new EntityKey simultaneously will race on the map write, causing a runtime panic. `go test -race` catches this immediately.

**Amendment:** Change Task 1.4 Step 1 to: "`entityChans sync.Map` — not `map[EntityKey]chan Event` — to eliminate concurrent read/write races on channel creation and GC."

---

### P0-2: CollisionWindow pending map — data race
**Agent:** fd-go-concurrency-safety | **Task:** 1.5

Same class of issue: `map[EntityKey]pendingEvent` with TTL has no synchronization specified. Concurrent check-then-write from two goroutines on the same EntityKey is a data race.

**Amendment:** Add to Task 1.5 Step 1: "Protected by `mu sync.Mutex` covering all reads and writes to `pending map[EntityKey]pendingEvent`."

---

### P0-3: Tasks 1.5 and 1.8 are misordered — compile-time dependency
**Agent:** fd-dependency-ordering | **Tasks:** 1.5, 1.8

Task 1.5 (CollisionWindow) Step 3 calls `ConflictResolver.ResolvePair(a, b Event)` — but ConflictResolver is defined in Task 1.8. A developer executing Task 1.5 in task order cannot compile without Task 1.8's types existing first. The plan presents 1.5 before 1.8 in Phase 1.

**Amendment:** Reorder Phase 1: 1.1 → 1.2 → 1.3 → 1.4 → 1.6 → 1.7 → 1.8 → 1.5 → 1.9 → 1.10 → 1.11. (Or split Task 1.8 into an interface-stub sub-task before 1.5.)

---

## P1 Findings

### P1-1: ResolveThreeWay has no unresolvable return path
**Agent:** fd-bidirectional-sync-conflicts | **Task:** 1.8

`ResolveThreeWay` returns `(merged, ConflictRecord)` — always a winning event. The plan claims to fix P0-5 (same close-state, different close-notes → dead-letter), but the signature has no error/unresolvable return. The test verifies "field-level conflict on convergent state detected" but not that the outcome is dead-lettered rather than silently resolved with a wrong winner.

**Amendment:** Change signature to `ResolveThreeWay(base, left, right) (Event, ConflictRecord, error)` where non-nil error = dead-letter. Add to Task 1.8 test: "Assert conflict record's `resolution_type == dead-letter` for the convergent-state, divergent-notes case."

---

### P1-2: No structural enforcement of bd CLI-only access in beads adapter
**Agent:** fd-adapter-interface-contracts | **Task:** 2.1

The plan specifies "bd CLI exclusively — no direct Dolt access" by convention, but no compile-time guard is specified. A future contributor adding a direct Dolt connection to the struct bypasses the constraint invisibly.

**Amendment:** Add to Task 2.1: "`go list -deps ./internal/adapters/beads/...` in CI must not match `dolt` or `modernc.org/sqlite` — enforced by a CI lint step."

---

### P1-3: Unbounded goroutine spawning in HandleEvent
**Agent:** fd-go-concurrency-safety | **Tasks:** 2.1, 2.2, 3.1, 3.2

Each `HandleEvent()` dispatches to a new goroutine. Under bulk-import load (Notion sends 1000 events/s), this creates uncapped goroutines. The PRD's "bounded input channel (1000)" bounds bus ingestion, not per-adapter worker count. At 5s per goroutine × 1000/s = 5000 concurrent goroutines.

**Amendment:** Add to Task 1.2 adapter contract: "Each adapter MUST implement HandleEvent using an internal worker pool (semaphore channel, configurable size, default 10) to bound concurrent goroutines."

---

### P1-4: Panic recovery has no retry limit or dead-letter path
**Agent:** fd-go-concurrency-safety | **Task:** 1.4

Task 1.4 mentions `Requeue(e Event)` for panic recovery but specifies neither where `recover()` is called, nor a retry limit. A repeatedly-panicking adapter causes an infinite requeue loop.

**Amendment:** Add to Task 1.4: "Dispatch goroutine wraps HandleEvent in `recover()`. On panic: if `e.RetryCount < maxRetry` (default 3), call `bus.Requeue(e.WithIncrementedRetryCount())`; else call `bus.DeadLetter(e)`. Event struct needs `RetryCount int` field."

---

### P1-5: Task 1.3 compliance criterion not independently testable
**Agent:** fd-acceptance-criteria-quality | **Task:** 1.3

The compliance suite includes "Invalid events (empty EntityID) rejected by bus validation (tested at bus level)" — but EventBus is Task 1.4. `go test ./internal/adapter/...` on Task 1.3 alone cannot verify this criterion without Task 1.4's implementation.

**Amendment:** Move the bus-level validation criterion to Task 1.4's test, or add a stub validator interface in Task 1.3 that the real EventBus satisfies.

---

### P1-6: Task 1.9 drain test criterion doesn't verify drain works
**Agent:** fd-acceptance-criteria-quality | **Task:** 1.9

"SIGTERM triggers orderly shutdown" passes even if the daemon ignores in-flight events and exits immediately. The critical safety property — that in-flight events complete before exit — is unverified.

**Amendment:** Add to Task 1.9 test: "Send SIGTERM while 10 mock events are processing (each sleeps 2s); assert all 10 complete before process exit; process exits within 30s."

---

### P1-7: Task 3.1 Notion merge test requires live systems
**Agent:** fd-acceptance-criteria-quality | **Task:** 3.1

"merge produces correct output in both systems" requires Notion API + filesystem adapter running simultaneously — an e2e integration test that cannot run in CI without live credentials.

**Amendment:** Split into: (a) unit test — "merge produces correct merged content" with mock adapters; (b) unit test — "merge result written to SyncJournal with `resolution_type`"; (c) integration test (separate CI job) — "merge appears in Notion page and local file."

---

### P1-8: Phase 1 gate too high — 11 tasks before any adapter work
**Agent:** fd-dependency-ordering | **Task:** 1.10 (Docker)

11 tasks before Phase 2 adapters can start is an unnecessary long runway. Task 1.10 (Docker) and Task 1.11 (identity mapping) are not runtime dependencies for adapter development — adapters only require Tasks 1.1-1.9. Docker belongs with operational packaging in Phase 5.

**Amendment:** Move Task 1.10 to Phase 5 (alongside MCP plugin). Phase 1 gate becomes Tasks 1.1-1.9 (+ 1.11 optionally). Phase 2 can start after Task 1.9.

---

### P1-9: Migration not guaranteed idempotent on re-run
**Agent:** fd-migration-correctness | **Task:** 6.1

Re-running `interop migrate` after a completed migration hits `entity_id PRIMARY KEY` constraint errors in AncestorStore. The plan doesn't specify UPSERT semantics.

**Amendment:** Add to Task 6.1 Step 2: "Migration uses UPSERT semantics (`INSERT OR REPLACE`) for AncestorStore and SyncJournal entries. Re-running migration is safe and idempotent."

---

### P1-10: No pre-migration backup step
**Agent:** fd-migration-correctness | **Task:** 6.1

If migration fails mid-way (disk full, interkasten data corrupt), AncestorStore is left in a partial state with no rollback path.

**Amendment:** Add Task 6.1 Step 0: "Back up existing interop SQLite files to a timestamped `.bak` directory before any writes. On error, print: 'restore from <backup-path>'."

---

### P1-11: interkasten WAL format undocumented — hidden work in Task 6.1
**Agent:** fd-migration-correctness | **Task:** 6.1

Task 6.1 Step 1 says "Read interkasten's tracked databases, WAL state, conflict history" without specifying the WAL format. The developer must first reverse-engineer interkasten's storage schema — unplanned work not reflected in the task estimate.

**Amendment:** Add Task 6.1 Step 0 (before backup): "Read `interverse/interkasten/` source to document WAL/conflict-history storage format. Add format specification as a comment in `migrations/migrate.go` before implementing conversion."

---

### P1-12: SQLite connection pool unspecified — risk of SQLITE_BUSY errors
**Agent:** fd-go-concurrency-safety | **Tasks:** 1.6, 1.7

Multiple adapters may call `SyncJournal.Begin()` simultaneously. `modernc.org/sqlite` with WAL mode and default connection pool settings can return `SQLITE_BUSY`. Neither Task 1.6 nor Task 1.7 specifies connection pool configuration.

**Amendment:** Add to Tasks 1.6 and 1.7: "Open SQLite with `_busy_timeout=5000` pragma and a pool of 1 write connection to serialize writes and prevent SQLITE_BUSY."

---

## P2 Findings (summary)

| # | Agent | Task | Issue |
|---|-------|------|-------|
| P2-1 | fd-adapter-interface-contracts | 1.2 | No `Adapter` interface versioning story for future v2 methods |
| P2-2 | fd-acceptance-criteria-quality | 1.2 | `errors.go` typed error tests missing from Task 1.2 criteria |
| P2-3 | fd-acceptance-criteria-quality | 1.4 | "Serialized (not interleaved)" test criterion needs precise definition |
| P2-4 | fd-acceptance-criteria-quality | 1.5 | CollisionWindow TTL-boundary race edge case not tested |
| P2-5 | fd-acceptance-criteria-quality | 1.6 | "ListPending after crash" test criterion ambiguous — how crash is simulated unspecified |
| P2-6 | fd-go-concurrency-safety | 2.1 | Polling goroutine cancellation on Stop() not specified in task or compliance suite |
| P2-7 | fd-migration-correctness | 1.6/1.7 | No SQLite `user_version` schema versioning for interop's own DB schema |
| P2-8 | fd-migration-correctness | 6.1 | Migration tool development unnecessarily blocked on Phase 5; dry-run testable in Phase 3 |
| P2-9 | fd-dependency-ordering | 3.1/2.2 | Notion↔filesystem implicit runtime coupling not captured in integration test sequencing |
| P2-10 | fd-acceptance-criteria-quality | 4.1 | 120s time bound specified in task steps but omitted from test criterion |

---

## Findings vs. Flux-Review Prior Work

The plan's "Original Intent" section documents 9 flux-review structural additions and 5 PRD review P1s addressed. Spot-checking:

| Prior Finding | Plan Address | Status |
|---|---|---|
| AncestorStore restart persistence (P0-1) | Task 1.7 explicit restart test | PASS |
| LWW receive-time clock (P1-BSC-02) | Task 1.2 Event.Timestamp; Task 1.8 | PASS |
| Per-adapter-pair conflict policies (P1-BSC-04) | Task 1.8 ConflictPolicy | PASS |
| WAL → AncestorStore migration (P1-BSC-03) | Task 6.1 Step 2 | PASS |
| HandleEvent non-blocking (P1-AIC-01) | Task 1.2 contract; adapter tasks | PASS |
| Emit() close-on-Stop (P1-AIC-03) | Task 1.2, compliance suite | PASS |
| Observable CollisionWindow via /conflicts (P1-ACQ-01) | Task 1.5 → SyncJournal | PASS |
| GitHub HMAC verification (P0-1 brainstorm) | Task 3.2 Step 2 | PASS |
| EventBus.Emit contamination barrier (P0-6) | Task 1.4 Step 2 | PASS |

All 9 prior structural findings are correctly addressed in the plan. The new P0/P1 findings are implementation-level gaps (map synchronization, task ordering, test specificity) not covered by the earlier reviews.

---

## Recommended Plan Amendments (ordered by severity)

1. **[P0] Task ordering fix:** Move Task 1.8 (or ConflictResolver stub) before Task 1.5 in Phase 1 sequence
2. **[P0] Task 1.4:** Specify `sync.Map` for `entityChans` and document synchronization
3. **[P0] Task 1.5:** Add `mu sync.Mutex` protecting `pending map[EntityKey]pendingEvent`
4. **[P1] Task 1.8:** Change `ResolveThreeWay` return to `(Event, ConflictRecord, error)`; add dead-letter test
5. **[P1] Task 1.4:** Add panic recovery with `RetryCount`-bounded requeue and dead-letter path
6. **[P1] Task 1.2:** Add worker pool requirement to adapter contract
7. **[P1] Task 1.9:** Add drain verification to SIGTERM test (10 in-flight events, all complete)
8. **[P1] Task 3.1:** Split merge test into unit + integration components
9. **[P1] Task 6.1:** Add Step 0 (document interkasten WAL format + backup), UPSERT semantics
10. **[P1] Phase structure:** Move Task 1.10 (Docker) to Phase 5; reduce Phase 1 gate to 9 tasks
11. **[P1] Task 2.1:** Add CI lint step enforcing no Dolt/SQLite imports in beads adapter
12. **[P1] Tasks 1.6/1.7:** Specify SQLite connection pool + `_busy_timeout=5000`
