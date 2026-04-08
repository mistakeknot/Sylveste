# Synthesis Report: interop Integration Fabric Brainstorm — Track D (Esoteric)

**Review Date:** 2026-04-06
**Document Under Review:** `docs/brainstorms/2026-04-06-interop-brainstorm.md`
**Track:** D — Esoteric domain structural isomorphisms
**Agents:** 3 launched, 3 completed, 0 failed
**Verdict:** NEEDS-REVISION

---

## Executive Summary

The brainstorm's architectural commitments — Go monolith, goroutine isolation, webhook-first, event bus, per-adapter panic recovery — are individually sound. The three esoteric-domain agents converge on a single structural gap that is invisible from within the integration-fabric domain: **the brainstorm specifies the happy path for every mechanism but specifies no path for partial failure**.

- The goroutine isolation is a crash barrier, not a contamination barrier (Yasna).
- The bidirectional sync has no independent ledger and no rollback (Hogon).
- The event bus has no collision detection and no priority lanes (Yizhan).

Every one of these gaps manifests when two systems interact concurrently — the routine operational case in a bidirectional integration fabric. The brainstorm describes a system that will work correctly when events arrive sequentially. It will behave unpredictably when they arrive simultaneously, which they will, continuously.

The single most important structural addition is the **SyncJournal** — a persistent, adapter-independent log of cross-adapter operations that serves simultaneously as: the hogon's neutral arbitration ledger (DHG-01, DHG-02), the hewen audit record (SYP-05), and the retry queue for partial failures (DHG-01). The SyncJournal is not a new architectural layer — it is the reconciliation substrate that makes the event bus's bidirectional flows trustworthy.

---

## Verdict by Agent

| Agent | Specialty | Status | Highest Severity | Key Finding |
|-------|-----------|--------|-----------------|-------------|
| fd-zoroastrian-yasna-liturgical-relay | Goroutine isolation, typed handoffs, panic recovery continuity | NEEDS-REVISION | P0 | Pre-panic emit of semantically invalid events reaches other adapters; no contamination-isolation boundary |
| fd-dogon-hogon-granary-arbitration | Cross-adapter rollback, neutral arbitration, identity mapping | NEEDS-REVISION | P0 | No bulu (atomic rollback); no independent reconciliation ledger; adapters are party and judge |
| fd-song-yizhan-postal-relay-routing | Event priority, bidirectional collision detection, SLA audit | NEEDS-REVISION | P0 | No bingjuan (collision detection); simultaneous opposing events silently discard one side |

---

## Critical Findings (P0 — Block Implementation)

### 1. No Contamination-Isolation Boundary on the Shared Event Bus
**Source:** fd-zoroastrian-yasna-liturgical-relay (ZYL-01, P0)

The brainstorm's goroutine isolation prevents crashes from spreading — it does not prevent semantically invalid events from spreading. A panicking adapter can emit a valid-typed but semantically malformed event (nil payload, empty EntityID, inverted state) before the panic fires. That event routes to other adapters and triggers mutations against the corrupted payload. Go's channel atomicity prevents corrupted bytes; it does not prevent corrupted semantics.

**Recommendation:** The `EventBus.Emit()` method must validate events before enqueuing. Three-line validation in the bus send path (non-empty EntityID, non-nil Payload, valid Type constant). Adapters call `bus.Emit()` — they never write directly to the channel. Cost: one method + 3-5 validation checks.

---

### 2. No Atomic Rollback for Cross-Adapter Partial Failure
**Source:** fd-dogon-hogon-granary-arbitration (DHG-01, P0)

The brainstorm does not contain a mechanism for partial-failure recovery. When a beads state-change event syncs successfully to beads but the GitHub adapter times out, the system is in split state with no alarm, no retry queue, no rollback, and no user notification. This is the routine case, not an edge case — any network hiccup, rate limit, or transient API error produces it.

**Recommendation:** Introduce `SyncJournal` — a persistent log (SQLite table or JSONL append file) with `Begin(eventID, entityID, src, dst)`, `Complete(eventID)`, and `MarkFailed(eventID, err)` methods. On daemon startup, scan for `MarkFailed` entries and retry or surface. The SyncJournal is the neutral arbiter (hogon's ledger), independent of both adapters. Cost: one table/file + three methods.

---

### 3. No Bidirectional Collision Detection
**Source:** fd-song-yizhan-postal-relay-routing (SYP-01, P0)

All four Day-1 flows are bidirectional. Simultaneous edits to the same entity from two different systems are not an edge case — they are the nominal operational pattern in a multi-user environment. The event bus's FIFO processing of two opposing events about the same entity silently discards one edit. Neither user is notified.

**Recommendation:** The event bus needs a `CollisionWindow` (ring buffer with TTL, default 5s) that detects when two events with the same `EntityID` arrive from different source adapters within the window. On collision, route the pair to `ConflictResolver.ResolvePair()` instead of independent dispatch. The `ConflictResolver` writes a `ConflictRecord` (hewen) to `SyncJournal`. Cost: one `CollisionWindow` struct + one `detectCollision` call in the dispatch path + one `ResolvePair` method.

---

## Important Findings (P1 — Required Before First Milestone)

### 4. Panic Recovery Does Not Replay In-Flight Events
**Source:** fd-zoroastrian-yasna-liturgical-relay (ZYL-02, P1)

The brainstorm describes panic recovery as goroutine restart. The event being processed at panic time is silently lost — it was in a local stack variable in the panicking frame. The goroutine restarts clean with no knowledge of what it was doing. Result: events that triggered panics are never processed, producing permanent partial-completion states.

**Recommendation:** Each adapter's event-processing loop checkpoints the current event (`var currentEvent *Event`) before calling the handler. The defer/recover block calls `bus.Requeue(*currentEvent)` if `currentEvent != nil`. One variable + one method call in the recovery block.

---

### 5. `Event` Type Unspecified — Runtime Type Assertions Replace Compile-Time Contracts
**Source:** fd-zoroastrian-yasna-liturgical-relay (ZYL-03, P1)

The brainstorm's `Adapter` interface specifies `HandleEvent(Event)` but leaves `Event` undefined. If `Event.Payload` is `interface{}`, handoff contracts between adapters are enforced at runtime (type assertion) not compile time. A misspelled type string or nil payload silently no-ops in defensive Go code.

**Recommendation:** Define `Event` with a typed `EventPayload` interface (unexported seal method, preventing external implementation). Adapters use typed channels (`chan GitHubIssueEvent`, not `chan Event`) for their inboxes. The event bus routes by `EventType` constant to per-type channels. No cross-adapter type assertions at runtime.

---

### 6. No Event Priority Classification
**Source:** fd-song-yizhan-postal-relay-routing (SYP-02, P1)

A single FIFO event bus cannot distinguish a beads state-change event (must sync to GitHub within seconds for downstream CI) from a Notion bulk-update webhook (200 events from a database migration). During a Notion migration, critical beads events wait 3+ minutes behind 200 routine Notion events.

**Recommendation:** Replace the single channel with a three-lane priority bus (`express`, `urgent`, `routine`). Each adapter assigns a priority to its emitted events. The dispatch loop uses a nested select that drains `express` before `urgent` before `routine`. This is idiomatic Go — the nested select pattern is a standard Go priority queue. Cost: three channels + one dispatch loop.

---

### 7. No Per-Stage Event Timestamp / SLA Audit Trail
**Source:** fd-song-yizhan-postal-relay-routing (SYP-03, P1)

Events have no timestamp tracking as they move through ingestion → bus queuing → adapter dispatch → adapter processing → external API. When "sync is slow," there is no log that isolates which stage is slow.

**Recommendation:** Add `TracePoints []TracePoint` to the `Event` struct. Each stage appends a trace point (stage name, timestamp, adapter ID). On event completion, write the trace as a structured JSON log line. No separate metrics infrastructure for Day-1 — structured log is sufficient. Forward-compatible with OpenTelemetry span export.

---

### 8. Three-Way Merge Unresolvable Path Undefined
**Source:** fd-dogon-hogon-granary-arbitration (DHG-03, P1)

The brainstorm specifies three-way merge for content conflicts but does not specify what happens when three-way merge produces conflict markers (irresolvable conflict). Without a defined path, the implementation will choose arbitrarily — most likely writing conflict-marked content to local FS, which then propagates back to Notion as a corrupted page.

**Recommendation:** Add to brainstorm: "When three-way merge is irresolvable, the sync is suspended. Both versions are preserved (neither system is mutated). The conflict is surfaced as a `disputed_transfer` entry in SyncJournal with both versions and an MCP tool to surface it to the operator. The operator resolves manually via `interop_resolve_conflict(entityID, winner)`. Day-1 acceptance: this path must exist at launch; manual resolution is acceptable."

---

### 9. Identity Mapping Is Static Config with No Drift Detection
**Source:** fd-dogon-hogon-granary-arbitration (DHG-04, P1)

The brainstorm proposes "config file" for identity mapping (GitHub user ↔ Notion user ↔ beads assignee). A static YAML config cannot detect when a new GitHub user appears in events with no mapping — the system will silently drop the identity attribution.

**Recommendation:** Identity mappings are a `SyncJournal` table, not a static config. Unknown actors (GitHub usernames that appear in events with no mapping) are logged to an `unknown_actors` table. An MCP tool (`interop_unknown_actors()`) surfaces them. The system uses `(unknown)` as a sentinel for unresolved identities rather than dropping attribution. Manual mapping via config update remains the resolution mechanism — the change is in detection, not resolution.

---

## Convergence Across Esoteric Domains

All three esoteric-domain agents converge on the same structural insight expressed through three different 3,000-year-old institutional frameworks:

**The brainstorm specifies isolation mechanisms (goroutine pools, circuit breakers, panic recovery, bidirectional sync) but not integration mechanisms (rollback contracts, collision detection, priority routing, audit trails). An integration fabric without integration mechanisms is a collection of isolated adapters, not a fabric.**

| Finding Pattern | Yasna (Isolation) | Hogon (Rollback) | Yizhan (Routing) |
|-----------------|-------------------|------------------|-----------------|
| Pre-failure contamination | Invalid event emitted before panic | Split state on partial sync | Simultaneous opposing events processed independently |
| Post-failure continuity | In-flight event lost on panic | No retry queue for failed syncs | No priority queue; critical events delayed |
| Audit / accountability | No event validation record | No reconciliation ledger | No per-stage timestamp |
| Resolution path | No replay mechanism | No bulu (atomic rollback) | No hewen (conflict record) |

The SyncJournal addresses the Hogon's ledger requirement, the Yizhan's hewen, and (partially) the Yasna's event checkpoint. It is the single structural addition that addresses the most findings across all three tracks.

---

## Positive Findings Worth Preserving

The following brainstorm elements are validated by the esoteric-domain review:

1. **Goroutine isolation as the right primitive.** The Yasna review confirms goroutine pools are the correct unit of isolation — the critique is about contamination paths, not the isolation mechanism itself.

2. **Webhook-first is correct.** The Yizhan review validates webhook-first as the right ingestion strategy. Push-based event delivery is architecturally superior to polling for a hub routing bidirectional events — the problem is not the strategy but the handling of simultaneous events it produces.

3. **Three-way merge for content is correct.** The Hogon review confirms three-way merge is the right strategy for content conflicts. The critique is about the unresolvable-merge path, not the strategy itself.

4. **`bd` CLI-only for beads is correct.** The Yasna review notes this creates an untyped subprocess interface, but the recommendation is for `bd --json` output (which already exists) bound to a versioned Go struct — not a different access mechanism.

5. **Single binary monolith deployment is correct.** The Yasna review confirms this. Goroutine isolation within a single binary is the Yasna's multi-priest model — each priest operates independently within the shared ceremony.

---

## Recommended Changes Before Implementation

### Must-Have (P0 — Block Implementation)

1. **`EventBus.Emit()` validation method:** Non-empty EntityID, non-nil Payload, valid EventType constant. Adapters never write to channels directly. Cost: one method + 3-5 checks.

2. **`SyncJournal` with Begin/Complete/MarkFailed:** Persistent cross-adapter operation log, independent of both adapters. On startup, scan for MarkFailed and surface. Cost: one SQLite table or JSONL file + three methods.

3. **`CollisionWindow` in event bus dispatch:** Ring buffer with TTL (default 5s). On opposing-source event for same EntityID within window, route pair to `ConflictResolver.ResolvePair()`. Cost: one struct + one detectCollision call + one ResolvePair method.

### Must-Have (P1 — Required Before First Milestone)

4. **In-flight event checkpoint in adapter processing loops:** `var currentEvent *Event` checkpoint; `bus.Requeue(*currentEvent)` in recover block. Cost: one variable + one method.

5. **Typed `Event` and `EventPayload` interface:** `EventType` constants, `EventPayload` with sealed interface, per-adapter typed inbox channels. No cross-adapter runtime type assertions. Cost: one interface + one const block + per-adapter typed channels.

6. **Three-lane priority bus:** `express` / `urgent` / `routine` channels with nested-select dispatch. Adapters assign priority at emit time. Cost: three channels + one dispatch loop.

7. **`TracePoints []TracePoint` on `Event`:** Stage name, timestamp, adapter ID appended at each processing step. Structured JSON log on completion. Cost: one struct + one append per stage.

8. **Define three-way merge unresolvable path:** Add to brainstorm and spec: irresolvable merge → `disputed_transfer` in SyncJournal → MCP surface → manual resolution. Neither system mutated until resolved.

9. **`IdentityMap` with `unknown_actors` detection:** Unknown GitHub/Notion usernames logged, not silently dropped. MCP tool to surface. Cost: one table + one log + one MCP tool.

### Should-Have (P2 — First Iteration)

10. **Per-source admission control in webhook ingestion handler:** `429` response on queue depth threshold per source. GitHub/Notion webhook delivery retries on 429. Cost: queue-depth check + 429 response path.

11. **`ConflictRecord` (hewen) in SyncJournal:** Both winner and loser values preserved with resolution strategy and timestamp. Surfaced via MCP tool. Cost: one struct + one append per conflict resolution.

12. **Circuit breaker open-state queuing specification:** Decide buffer-and-replay vs. fail-fast-with-source-refetch per adapter. Local FS adapter must use buffer-and-replay (no re-fetch path). Add to brainstorm Open Questions.

### Deferred (P3 — Future Iteration)

13. Three-party coordination atomicity (multi-target event groups)
14. `bd --json` schema versioning in Beads adapter
15. OpenTelemetry span export from TracePoints

---

## Files Referenced

- Reviewed document: `docs/brainstorms/2026-04-06-interop-brainstorm.md`
- Agent reports in `docs/research/flux-drive/2026-04-06-interop-brainstorm/`:
  - `fd-zoroastrian-yasna-liturgical-relay.md` — goroutine isolation, typed handoffs, panic-recovery continuity
  - `fd-dogon-hogon-granary-arbitration.md` — cross-adapter rollback, neutral arbitration ledger, identity mapping
  - `fd-song-yizhan-postal-relay-routing.md` — event priority, bidirectional collision detection, SLA audit

---

## Final Verdict

**Status:** NEEDS-REVISION

**Summary:** The brainstorm's architectural commitments are sound. The three esoteric-domain agents expose a single convergent structural gap: the brainstorm describes isolation mechanisms but not integration mechanisms. An integration fabric requires both.

The three P0 findings (invalid-event contamination, no partial-failure rollback, no collision detection) are all variants of the same design deficit: the system has no model for what happens when two concurrent operations interact. Every Day-1 flow is bidirectional, and every bidirectional flow in a multi-user environment produces concurrent operations routinely.

The minimal remediation set is three additions:
1. `EventBus.Emit()` validation (contamination barrier)
2. `SyncJournal` (rollback, neutral ledger, audit trail)
3. `CollisionWindow` in dispatch (collision detection, pairs to ConflictResolver)

These three additions, plus the P1 items (typed `Event`, priority bus, TracePoints, in-flight checkpoint), make the architecture sound for Day-1 implementation. The brainstorm should be updated with these as resolved design decisions — not open questions — before the implementation plan is written.
