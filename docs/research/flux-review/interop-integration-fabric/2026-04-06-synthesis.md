---
artifact_type: review-synthesis
method: flux-review
target: "docs/brainstorms/2026-04-06-interop-brainstorm.md"
target_description: "interop: unified integration fabric -- Go daemon bridging Notion, GitHub, beads, and local FS"
tracks: 3
track_a_agents: [fd-go-goroutine-isolation, fd-webhook-delivery-semantics, fd-bidirectional-sync-conflicts, fd-adapter-interface-contracts, fd-daemon-operational-reliability]
track_b_agents: [fd-atc-flow-management, fd-laboratory-middleware, fd-scada-energy-management, fd-supply-chain-control-tower]
track_d_agents: [fd-zoroastrian-yasna-liturgical-relay, fd-dogon-hogon-granary-arbitration, fd-song-yizhan-postal-relay-routing]
date: 2026-04-06
---

# Unified Synthesis: interop Integration Fabric Brainstorm

12 agents across 3 tracks reviewed the interop brainstorm. Track A ran 5 domain-expert agents plus 4 orthogonal agents auto-triaged in. Track B's 4 parallel-discipline agents overlap with Track A (same agents, pulled into A's run). Track D ran 3 esoteric-domain agents. Total unique findings: 8 P0, 18 P1, 18 P2. Verdicts: 2 fail (webhook-delivery, bidirectional-sync), 5 risky (daemon-ops, ATC, lab, SCADA, supply-chain), 5 needs-revision/needs-attention.

The brainstorm's architectural bets are correct: Go monolith, goroutine isolation, webhook-first, adapter interface, three-way merge. Every agent validated the direction. The deficits are in behavioral contracts, failure paths, and operational machinery. The brainstorm describes what the system does when everything works. It says nothing about what the system does when things fail concurrently -- which is the nominal operating condition for a bidirectional integration fabric.

---

## Critical Findings (P0/P1)

### P0-1: Webhook signature verification absent
**Agents:** fd-webhook-delivery-semantics (Track A)
**Tracks:** A only

The brainstorm specifies an internet-facing webhook endpoint (Caddy reverse proxy) that can create, close, and modify beads -- the single source of truth for work tracking. No HMAC signature verification is mentioned for GitHub (`X-Hub-Signature-256`) or Notion. An attacker who discovers the webhook URL can forge payloads that manipulate beads state.

**Fix:** Add non-bypassable signature verification middleware. GitHub: validate `X-Hub-Signature-256` against the GitHub App webhook secret. Notion: validate per Notion's webhook verification scheme. The middleware rejects unverified payloads before they reach the event bus. This is a `func(next http.Handler) http.Handler` wrapper in the webhook ingestion path.

---

### P0-2: Common ancestor store persistence not specified
**Agents:** fd-bidirectional-sync-conflicts (Track A), fd-scada-energy-management (Track B)
**Tracks:** A, B (convergent)

Three-way merge requires a common ancestor (version O) for every synced entity. The brainstorm does not specify where ancestors are persisted. If in-memory, a daemon restart loses all sync history. The next sync cycle sees GitHub and Notion with no shared base, producing either hundreds of false conflicts or silent data loss depending on the merge implementation's zero-ancestor fallback.

**Fix:** Persist the ancestor store to disk (SQLite or BoltDB, not flat JSON -- the ancestor store is queried by entity ID and needs indexed lookup). Write on every successful sync completion. Read on daemon startup. Loss of the ancestor store is a critical failure requiring manual reconciliation, not a soft reset. Define the store as a first-class component: `type AncestorStore interface { Get(entityID string) (Ancestor, error); Put(entityID string, a Ancestor) error }`.

---

### P0-3: SIGTERM loses in-flight events permanently
**Agents:** fd-daemon-operational-reliability (Track A), fd-scada-energy-management (Track B), fd-atc-flow-management (Track B)
**Tracks:** A, B (convergent -- 3 agents independently)

The brainstorm specifies Docker Compose deployment but no shutdown sequence. Docker sends SIGTERM, then SIGKILL after `stop_grace_period`. A Go daemon that calls `os.Exit(0)` on SIGTERM kills all goroutines. Events already acknowledged to GitHub (HTTP 200 returned) but not yet processed by adapters are lost permanently. GitHub will not retry them. This is invisible sync divergence on every deploy.

**Fix:** Graceful shutdown sequence: (1) stop accepting new webhook connections (close HTTP listener), (2) cancel context to signal adapter goroutine pools, (3) wait for in-flight events to drain (configurable timeout, default 30s), (4) flush recovery checkpoint and SyncJournal to disk, (5) close MCP server, (6) exit. Use `signal.NotifyContext(ctx, syscall.SIGTERM, syscall.SIGINT)` as root context. Set Docker Compose `stop_grace_period` to exceed the drain timeout.

---

### P0-4: No per-entity event serialization
**Agents:** fd-atc-flow-management (Track B)
**Tracks:** B only

Two adapters updating the same entity (same bead modified via Notion and GitHub simultaneously) race at the consumer side. The event bus provides FIFO within a single channel, but when two events for the same `EntityID` arrive from different adapters, goroutine scheduling determines the outcome. Non-deterministic state: run 1 picks Notion, run 2 picks GitHub. No replay can reproduce the result.

**Fix:** Add `EntityKey` to the canonical `Event` type (e.g., `"beads:issue:sylveste-bcok"`). The hub maintains a `map[EntityKey]chan Event` of per-entity dispatch channels, created on demand and GC'd when idle. All events for the same entity are serialized through the same channel before reaching any adapter's goroutine pool.

---

### P0-5: No bidirectional collision detection
**Agents:** fd-song-yizhan-postal-relay-routing (Track D), fd-atc-flow-management (Track B)
**Tracks:** B, D (convergent)

All four Day-1 flows are bidirectional. Simultaneous edits to the same entity from two systems produce opposing events. The FIFO event bus processes them independently -- the second event overwrites the first event's sync. Neither user is notified.

**Fix:** Add a `CollisionWindow` to the event bus -- a `map[string]pendingEvent` with TTL (default 5s). Before dispatching, check if an opposing-source event for the same `EntityID` is already in the window. On collision, route the pair to `ConflictResolver.ResolvePair(a, b Event)` instead of independent dispatch. Write a `ConflictRecord` to the SyncJournal.

---

### P0-6: Pre-panic emit of semantically invalid events
**Agents:** fd-zoroastrian-yasna-liturgical-relay (Track D)
**Tracks:** D only

Goroutine isolation prevents crashes from spreading. It does not prevent semantically invalid events from spreading. A panicking adapter can emit a valid-typed but semantically malformed event (empty EntityID, nil Payload) before `recover()` fires. That event routes to other adapters and triggers mutations against corrupted data.

**Fix:** Adapters must not write to channels directly. The `EventBus.Emit(e Event) error` method validates before enqueuing: non-empty `EntityID`, non-nil `Payload`, valid `EventType`. Invalid events are logged and dropped. Cost: one method with 3-5 validation checks.

---

### P0-7: No atomic rollback for cross-adapter partial failure
**Agents:** fd-dogon-hogon-granary-arbitration (Track D)
**Tracks:** D only

When a sync succeeds at the source adapter but the destination adapter times out (GitHub 503, Dolt unresponsive), the system is in split state. No retry queue, no rollback, no alarm, no user notification. The brainstorm does not contain the words "rollback," "compensating transaction," or "split state."

**Fix:** Introduce `SyncJournal` -- a persistent, adapter-independent log with `Begin(eventID, entityID, src, dst)`, `Complete(eventID)`, `MarkFailed(eventID, err)`. On startup, scan for `MarkFailed` entries and retry or surface via MCP. The SyncJournal serves triple duty: rollback/retry queue, neutral conflict arbiter (independent of both adapters), and audit trail.

---

### P0-8: Adapters are party and judge in conflict resolution
**Agents:** fd-dogon-hogon-granary-arbitration (Track D)
**Tracks:** D only

The brainstorm states conflict resolution is "configurable per-adapter." This means the adapter that is a party to the conflict also determines how it is resolved. The beads adapter resolving a beads-vs-GitHub conflict using beads' timestamp will systematically favor beads.

**Fix:** The SyncJournal (P0-7) doubles as the neutral reconciliation ledger. When a conflict is detected, the resolution decision is written to the SyncJournal with both values, the strategy applied, and the winner. Adapters report to the journal; they do not resolve independently. Add `ResolveConflict(entityID, strategy, value1, value2, winner) ConflictRecord`.

---

### Key P1 findings requiring immediate design decisions

- **Panic recovery loses in-flight events** (fd-go-goroutine-isolation A, fd-scada-energy-management B, fd-zoroastrian-yasna-liturgical-relay D -- 3 tracks convergent). Fix: per-adapter WAL or in-flight event checkpoint with `bus.Requeue()` in the recover block.
- **Event bus backpressure unspecified** (fd-go-goroutine-isolation A, fd-atc-flow-management B). Fix: per-adapter bounded input channels (default 1000), non-blocking sends with dead-letter on overflow.
- **Adapter behavioral contracts missing** (fd-adapter-interface-contracts A, fd-laboratory-middleware B). Fix: GoDoc specifying `HandleEvent` must return within 100ms, `Start` must be idempotent, `Stop` must drain, `Emit` returns the same channel for adapter lifetime.
- **No error taxonomy for HandleEvent** (fd-adapter-interface-contracts A, fd-laboratory-middleware B). Fix: typed Go errors -- `ErrMalformed` (discard), `ErrTransient` (retry), `ErrConflict` (escalate), `ErrShuttingDown` (requeue).
- **Identity mapping deferred** (fd-adapter-interface-contracts A, fd-dogon-hogon-granary-arbitration D). Fix: first-class data structure using stable system-native IDs (GitHub numeric user ID, Notion UUID, beads assignee string). Unknown actors logged, not silently dropped.
- **No webhook delivery deduplication** (fd-webhook-delivery-semantics A). Fix: dedup store keyed by delivery ID (`X-GitHub-Delivery`), 7-day TTL, check before event bus dispatch.
- **Shared HTTP transport across adapters** (fd-scada-energy-management B). Fix: each adapter gets its own `*http.Client` with dedicated `net/http.Transport`. One-line change in the adapter factory.

---

## Cross-Track Convergence

Findings that appeared independently in 2+ tracks carry the highest confidence. They represent structural truths about the design rather than lens-specific observations.

### 1. Event lifecycle has no in-flight tracking (3/3 tracks)

- **Track A:** fd-daemon-operational-reliability found SIGTERM kills in-flight events. fd-go-goroutine-isolation found no panic recovery contract for events mid-processing.
- **Track B:** fd-scada-energy-management found panic recovery does not restore dequeued events; proposed a per-adapter WAL (two-phase commit). fd-atc-flow-management found the hub treats dispatch as delivery with no acknowledgment.
- **Track D:** fd-zoroastrian-yasna-liturgical-relay found in-flight events are lost on panic (stack-local variable destroyed). fd-dogon-hogon-granary-arbitration found no rollback for partially-completed cross-adapter operations.

**Framing differences:** Track A frames it as operational reliability (shutdown/crash data loss). Track B frames it as system engineering (WAL, checkpoint, acknowledgment protocol). Track D frames it as ceremony continuity (the priest restarts but does not know what verse they were on) and transactional integrity (no bulu for partial transfers).

**Convergence score:** 3/3 tracks. This is the highest-confidence finding in the review.

**Unified fix:** The event bus must implement a durable in-flight tracking mechanism. At minimum: (a) per-adapter event checkpoint variable with `bus.Requeue()` in the recover block (Day-1, low cost), (b) SyncJournal with `Begin`/`Complete`/`MarkFailed` for cross-adapter operations (Day-1, medium cost), (c) per-adapter WAL for durability across process restarts (can be deferred to Day-2 if the graceful shutdown drain is implemented first).

---

### 2. Conflict resolution assumes ideal conditions (3/3 tracks)

- **Track A:** fd-bidirectional-sync-conflicts found LWW clock source unspecified (external system timestamps have skew), per-adapter-pair policies missing, ancestor store not persisted, unresolvable conflicts silently tiebroken.
- **Track B:** fd-supply-chain-control-tower found three-way merge on convergent state transitions silently overwrites divergent content fields. fd-atc-flow-management found conflict detection fires after emission, not before.
- **Track D:** fd-dogon-hogon-granary-arbitration found adapters are party and judge (no neutral arbiter), merge unresolvable path undefined. fd-song-yizhan-postal-relay-routing found simultaneous opposing events processed independently with no collision detection, and conflict resolution decisions produce no audit record.

**Framing differences:** Track A focuses on the algorithmic assumptions (clock trust, ancestor persistence). Track B focuses on the merge granularity (top-level vs. field-level) and timing (pre-dispatch vs. post-dispatch detection). Track D focuses on the institutional structure (neutral arbiter, collision detection, audit trail).

**Convergence score:** 3/3 tracks.

**Unified fix:** (a) LWW uses interop's `time.Now()` at ingestion, not external timestamps. (b) Ancestor store persisted as a first-class component. (c) Conflict policies are per-adapter-pair with directional authority (beads authoritative for state, Notion for prose content, GitHub for PR merge state). (d) SyncJournal as neutral arbiter with `ConflictRecord` audit entries. (e) CollisionWindow detects opposing events before dispatch. (f) Field-level conflict check even on convergent state transitions.

---

### 3. Operational contracts are entirely missing (2/3 tracks)

- **Track A:** fd-daemon-operational-reliability found no graceful shutdown, no health/readiness split, no recovery checkpoint, no structured logging, no Docker resource limits. fd-go-goroutine-isolation found no `context.Context` propagation, no goroutine lifecycle state machine.
- **Track B:** fd-scada-energy-management found no structured health alarms (crashed adapters invisible to Docker), no degraded-mode contracts, no startup sequencing. fd-supply-chain-control-tower found no full-sync reconciliation on adapter recovery.
- **Track D:** Did not address operational contracts directly (focused on integration mechanisms instead).

**Framing differences:** Track A frames it as daemon engineering (shutdown, health, logging). Track B frames it as industrial control (alarm management, degraded-mode operation, startup sequencing barriers).

**Convergence score:** 2/3 tracks (A and B).

**Unified fix:** Add Key Decisions covering: graceful shutdown sequence, health/readiness endpoints (`/health` for liveness, `/ready` for adapter operational state), recovery checkpoint (per-adapter last-processed event ID, atomic write-then-rename), structured JSON logging via `slog`, Docker Compose memory limits (512M), startup barrier (`Ready() <-chan struct{}` per adapter, hub does not route until closed).

---

### 4. Event type and routing context underspecified (2/3 tracks)

- **Track A:** fd-adapter-interface-contracts found the `Event` type is a fixed struct with no extensibility, no error taxonomy, no behavioral contracts on `HandleEvent`.
- **Track B:** fd-laboratory-middleware found the canonical Event lacks routing context (cross-system ID hints), no schema versioning, no translation contracts per adapter.
- **Track D:** fd-zoroastrian-yasna-liturgical-relay found `Event` type unspecified -- runtime type assertions replace compile-time contracts. Proposed typed `EventPayload` with sealed interface.

**Convergence score:** 3/3 tracks (though Track A's framing is narrower).

**Unified fix:** Define `Event` as a concrete struct with: `ID string`, `EntityID string`, `Type EventType` (typed constants), `SourceAdapter AdapterID`, `Timestamp time.Time`, `SchemaVersion int`, `RoutingHints map[string]string` (cross-system IDs), `TracePoints []TracePoint`, `Payload EventPayload` (sealed interface with unexported method). Each adapter declares handled `EventType`s. The bus routes by type to per-adapter typed channels. `HandleEvent` returns typed errors (`ErrMalformed`, `ErrTransient`, `ErrConflict`, `ErrShuttingDown`).

---

## Domain-Expert Insights (Track A)

### Security

fd-webhook-delivery-semantics produced the only security finding: unauthenticated webhook ingestion is a P0. The agent also identified the Caddy header forwarding gap -- `X-Hub-Signature-256` must be explicitly forwarded in the Caddyfile reverse proxy block, or signature verification silently fails. This is a subtle deployment bug that would be caught late.

### Sync correctness

fd-bidirectional-sync-conflicts produced the most architecturally consequential finding: the ancestor store is the foundation of three-way merge and must be a first-class persisted component, not an implementation detail. The agent also identified that the four-system bidirectional topology creates 6 adapter pairs (4 choose 2) and needs per-pair directional authority, not a global policy. The cycle detection recommendation (tag events with originating adapter and hop count, discard events that return to origin) is a concrete, low-cost addition.

### Interface design

fd-adapter-interface-contracts identified the Go capability pattern as the extensibility mechanism: a core `Adapter` interface with 4 base methods, optional capabilities (`HealthChecker`, `StateSyncer`) as separate interfaces, hub checks via type assertion. This prevents the interface-version-breaks-all-adapters problem when Google Drive arrives as a day-2 adapter. The agent also recommended an adapter compliance test suite -- a `testing.T` helper that validates any `Adapter` implementation against behavioral contracts.

### Daemon engineering

fd-daemon-operational-reliability's most valuable finding is the MCP/webhook lifecycle coupling. Two listeners in one process with independent failure modes: if the webhook server crashes but MCP stays up, Claude Code sessions query stale state and act on it, creating conflicting writes. The fix is shared lifecycle -- either server's listener failure triggers graceful shutdown of both.

---

## Parallel-Discipline Insights (Track B)

### ATC flow management: per-entity serialization and pre-dispatch conflict detection

**Source discipline:** Air traffic control flow management.
**Specific practice:** ATFM's per-aircraft conflict alert -- two sector controllers cannot issue simultaneous instructions for the same aircraft. Conflict alerts fire in the routing layer (flow control), not at the sector (adapter) level.
**Mapping:** The event bus needs per-entity dispatch channels (`map[EntityKey]chan Event`) to serialize concurrent updates. Conflict detection must happen in the hub router before dispatch, not at the consuming adapter after both events are already delivered. The ATC agent's framing that "conflict detection after emission is too late" is the most concise formulation of the pre-dispatch collision detection requirement that Track D's Song yizhan agent also surfaced.

### Laboratory middleware: canonical event routing context and schema versioning

**Source discipline:** Clinical laboratory middleware (HL7, instrument interfacing).
**Specific practice:** HL7 orphan result handling -- unresolvable results are held in a review queue, not silently discarded. Interface version mismatch fails loudly so the instrument vendor can push a parser update.
**Mapping:** The canonical `Event` struct needs `RoutingHints map[string]string` populated by the originating adapter with all known cross-system IDs. When a downstream adapter cannot resolve the target and no routing hint exists, it returns `ErrUnresolvableTarget` (explicit dead-letter, not silent drop). Schema versioning (`SchemaVersion int` on Event, `MaxSupportedSchemaVersion` on adapter) prevents silent incompatibilities when adapters are updated independently.

The lab middleware agent also identified Notion block-level event debouncing as a practical gap: Notion emits per-block webhooks, so a 200-word page edit generates 150 events. Without a per-entity debounce window (2s) in the Notion adapter's emit path, the beads adapter calls `bd update` 150 times for one logical change.

### SCADA/EMS: in-flight event WAL and per-adapter HTTP transport isolation

**Source discipline:** SCADA energy management systems.
**Specific practice:** The SCADA historian records every telemetry point durably before the application layer processes it. Per-subsystem network interface isolation -- metering traffic never shares bandwidth with state estimation traffic.
**Mapping:** The per-adapter WAL (write event to append-only log before processing, remove after confirmed write, replay WAL on restart) is the most robust fix for the in-flight event loss problem. It guarantees at-least-once delivery with explicit idempotency requirements on external writes. The per-adapter `*http.Client` with dedicated `net/http.Transport` prevents GitHub rate limiting from starving Notion API calls through the shared `http.DefaultClient` connection pool. This is a one-line-per-adapter change in the factory constructor.

### Supply chain control tower: field-level merge and full-sync reconciliation

**Source discipline:** Supply chain control tower (ERP/WMS/TMS multi-system coordination).
**Specific practice:** "Same-status, different-attribute conflict" -- two warehouses mark a shipment "delivered" but with different timestamps. The golden record with two-phase entity creation coordinates cross-system ID registration atomically.
**Mapping:** Three-way merge on convergent state transitions can silently overwrite content fields. Both sides close a bead, but with different closure notes. The merge sees agreement on `closed` and applies one side's notes, destroying the other's. Fix: field-level comparison even on convergent states; if `left.Fields != right.Fields`, route to dead-letter for operator review. The `FieldConflictPolicy` config controls this per entity type.

Full-sync reconciliation on adapter reconnect is also critical: webhook-based resume from cursor cannot recover changes made during offline windows (Notion's webhook model is fire-and-forget). A periodic reconciliation (every 6 hours) enumerates all entities, compares checksums, and emits synthetic `entity.reconcile` events for drift.

---

## Frontier Patterns (Track D)

### Zoroastrian Yasna: contamination-isolation vs. crash-isolation

**Source domain:** The Vendidad's contamination protocols distinguish contamination that spreads through shared ritual implements from contamination that stays within the failing station. Purification explicitly addresses "chapter continuity" -- which chapter was the priest at when contamination occurred?

**Why unexpected:** The distinction between crash-isolation (goroutine panics are contained) and contamination-isolation (semantically invalid events can escape before the panic) is invisible from within the Go concurrency domain. Go's `recover()` is universally discussed as crash isolation. The Yasna lens reframes it as: what leaves the station through shared implements before purification fires?

**Mechanism:** A panicking adapter can call `bus.Emit(event)` with an event that has nil Payload or empty EntityID before the nil dereference that triggers the panic. The channel send completes (channel sends are atomic in Go). The panic fires after. The invalid event is now in another adapter's inbox. This is not a corrupted-bytes problem (channels are byte-safe). It is a corrupted-semantics problem.

**Mapping:** `EventBus.Emit()` validation method -- the bus, not the adapter, checks event validity before enqueueing. This is the Vendidad's "contamination does not leave the station before purification is complete." One method with 3-5 checks.

**Design direction:** Refines existing. The validation layer does not change the architecture; it adds a single gate function. But the conceptual reframe -- goroutine isolation is a crash barrier, not a contamination barrier -- should be stated explicitly in the brainstorm's Key Decisions to prevent implementers from assuming `recover()` is sufficient.

### Dogon Hogon granary arbitration: the neutral ledger and the bulu

**Source domain:** The hogon (Dogon elder/arbiter) maintains a master reconciliation ledger independent of both granaries. The bulu (reversal ceremony) exists because partial transfers -- grain left source but never arrived at destination -- are the most dangerous state. The hogon is structurally prohibited from being a party to the transfer.

**Why unexpected:** The insight that "adapters should not resolve their own conflicts" seems obvious when stated, but the brainstorm's "configurable per-adapter" phrasing makes it sound reasonable. The hogon lens exposes the structural flaw: a party that is also the judge will systematically favor its own timestamp. The real insight is that the reconciliation layer must be architecturally independent -- not just logically separate, but structurally unable to be the same code that writes to the adapter.

**Mechanism:** `SyncJournal` -- a persistent log independent of all adapters, with `Begin`/`Complete`/`MarkFailed`/`ResolveConflict`. Adapters report to the journal. The journal makes resolution decisions using configured policies. No adapter directly calls another adapter's conflict resolution. The journal is the hogon.

**Mapping:** The SyncJournal is the single most impactful structural addition identified by any track. It addresses: partial-failure rollback (DHG-01), neutral conflict arbitration (DHG-02), conflict audit records (SYP-05 hewen), unknown actor detection (DHG-04), and three-party coordination tracking (DHG-05). One component, five findings resolved.

**Design direction:** Opens a new direction. The brainstorm has no reconciliation layer. The SyncJournal is not an optimization of the event bus -- it is a new architectural component that sits alongside the event bus. The event bus routes events. The SyncJournal tracks cross-adapter operations across time. Both are needed.

### Song Dynasty yizhan postal relay: collision detection and priority routing

**Source domain:** The Song Dynasty postal relay system's bingjuan protocol detected when opposing documents (provincial memorials flowing to the capital, imperial edicts flowing to the provinces) crossed paths at a relay station. The three-tier urgency system (routine, urgent, express/flying horse) guaranteed SLA compliance by urgency class. The jianbu (station log) recorded per-station arrival/departure timestamps for audit.

**Why unexpected:** Priority queuing and collision detection are well-known patterns in distributed systems. What the yizhan lens adds is the SLA audit trail -- the jianbu -- as a structural requirement, not an operational nice-to-have. The Song government impeached station masters who delayed documents beyond their urgency class threshold. The audit trail enforced the priority system. Without it, priority routing is unverifiable.

**Mechanism:** Three-lane priority bus (`express`, `urgent`, `routine`) with nested-select dispatch. `CollisionWindow` with TTL for opposing-source events on the same entity. `TracePoints []TracePoint` on every event, with stage name, timestamp, and adapter ID appended at each processing step.

**Mapping:** The priority bus prevents a Notion bulk migration (200 routine events) from starving a beads state-change event (express) that CI depends on. The collision window catches the most common bidirectional failure: simultaneous edits from two systems. The trace points make latency diagnosis a structured log query rather than manual component-by-component investigation.

**Design direction:** Refines existing (priority bus, collision detection are known patterns). But the jianbu-as-accountability-mechanism framing argues that `TracePoints` should be a Day-1 requirement, not a Day-2 improvement. Without per-stage timestamps, the priority bus cannot be verified to be working.

---

## Synthesis Assessment

**Overall quality of the brainstorm:** The architectural direction is sound -- every agent across all three tracks validated the core bets (Go monolith, goroutine isolation, webhook-first, adapter interface, three-way merge, single-binary deployment). The deficit is systematic: the brainstorm specifies mechanisms for the happy path but omits failure contracts, operational machinery, and integration mechanisms (collision detection, rollback, audit) that make the happy-path mechanisms safe under concurrent load.

**Highest-leverage improvement:** Introduce the `SyncJournal` -- a persistent, adapter-independent log of cross-adapter operations with `Begin`/`Complete`/`MarkFailed`/`ResolveConflict` methods. This single component addresses 5 P0 findings across Tracks B and D (partial-failure rollback, neutral conflict arbitration, collision resolution audit, unknown actor detection, three-party coordination tracking). It is not a redesign; it is one SQLite table with four methods that sits alongside the event bus. The event bus routes events in real time. The SyncJournal tracks operations across time. Both are needed for a bidirectional integration fabric.

**Surprising finding:** The convergent insight from Track D that the brainstorm "specifies isolation mechanisms but not integration mechanisms" is something no single inner-track agent articulated at that level of abstraction. Track A agents found specific missing contracts (panic recovery, shutdown drain, signature verification). Track B agents found specific missing patterns (per-entity serialization, schema versioning, field-level merge). Track D agents, working from 3,000-year-old institutional frameworks that have solved multi-party coordination problems at scale, converged on the structural observation: an integration fabric without integration mechanisms is a collection of isolated adapters, not a fabric. The specific integration mechanisms -- contamination barriers, neutral ledgers, collision detection -- map precisely to the gaps the inner tracks found piecemeal.

**Semantic distance value:** Track D contributed qualitatively different insights from Tracks A/B. The inner tracks found *what* is missing (specific contracts, patterns, configurations). Track D found *why* it is missing (the brainstorm's design frame is isolation-centric, not integration-centric) and proposed structural additions (SyncJournal, CollisionWindow, EventBus.Emit validation) that unify multiple inner-track findings under single components. The Yasna's crash-vs-contamination distinction, the hogon's party-vs-judge prohibition, and the yizhan's jianbu-as-accountability-mechanism each reframed an inner-track finding in a way that changed the recommended fix from "add a check" to "add an architectural component." The outer tracks justified their cost.
