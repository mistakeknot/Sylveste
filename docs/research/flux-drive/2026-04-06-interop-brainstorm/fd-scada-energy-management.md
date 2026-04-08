---
agent: fd-scada-energy-management
source_doc: docs/brainstorms/2026-04-06-interop-brainstorm.md
generated_at: 2026-04-06
lens: SCADA/EMS — goroutine isolation boundaries, alarm management, degraded-mode contracts, circuit breaker calibration, startup sequencing, historian
---

# fd-scada-energy-management — Review Findings

## Decision Lens

Does the daemon fail safe under partial adapter failure the way an EMS fails safe when a metering subsystem goes offline — with automatic isolation, degraded-mode operation on surviving subsystems, and operator-visible alarm management rather than silent full-system impact?

---

## P0 Findings

### P0-1: Panic recovery does not account for in-flight events — adapter restart loses dequeued events

**Finding:** The brainstorm states "panic recovery" as a per-adapter goroutine pool feature. Standard Go panic recovery (`defer func() { if r := recover(); r != nil { ... } }()`) restarts the goroutine but does not restore the state of the goroutine at the point of panic. If the adapter goroutine has already read an event from the bus channel and is mid-processing when it panics, that event is gone — the bus channel has already advanced past it.

**Failure scenario:** The Notion adapter goroutine pool is processing a bulk sync of 500 page events. At event 237, the Notion API returns a malformed response that triggers a nil pointer dereference. The goroutine panics. Panic recovery fires. The hub considers event 237 delivered (it was read from the channel). The Notion adapter restarts with its last committed cursor position. Depending on cursor persistence: (a) if the cursor is flushed only on successful batch completion, the adapter replays events 1–237, creating duplicate writes in beads and Notion; (b) if the cursor is advanced on channel read (not on confirmed write), events 237–300 are lost and the adapter resumes from 301. Both outcomes corrupt state.

**Condition:** Panic recovery restarts the adapter goroutine without atomic in-flight event accounting. The bus considers an event delivered the moment it is read from the channel, not the moment it is durably written to the external system.

**Smallest viable fix:** Use a two-phase commit pattern for each event: (1) adapter reads event from channel, writes it to a per-adapter WAL file (in-flight log), (2) adapter applies the event to the external system, (3) adapter removes the event from the WAL. On restart, the first operation is to replay the WAL (idempotent retry). This guarantees at-least-once delivery with explicit idempotency requirements on the external system write. This is the SCADA EMS checkpoint model — the historian records every telemetry point durably before the application layer processes it.

---

## P1 Findings

### P1-1: Adapters likely share HTTP transport — GitHub rate limiting starves Notion API calls

**Finding:** The brainstorm does not specify how outbound HTTP clients are instantiated per adapter. Go's `net/http.DefaultClient` is a global singleton. If any adapter uses `http.DefaultClient` or shares a `*http.Client` instance across adapters, the connection pool is shared. GitHub's aggressive rate limiting (5,000 requests/hour for authenticated apps, but burst limits apply) can exhaust the connection pool.

**Failure scenario:** The GitHub adapter is processing a large repository sync (1,000 issues). It makes rapid authenticated requests to the GitHub API. GitHub responds with HTTP 429 with a `Retry-After: 60` header. The GitHub adapter's retry logic backs off, but the existing connections to GitHub's API servers are held open in the `http.DefaultClient` connection pool, waiting for the backoff to expire. The Notion adapter attempts an API call to write a page update. Its outbound request is queued behind the GitHub connections in the shared pool. The Notion write times out. The Notion adapter logs an error and retries. Notion write latency spikes from 200ms to 62 seconds for the duration of the GitHub rate limit window.

**Condition:** When adapters share transport-layer resources (`http.Client`, connection pools, TLS sessions) that are not partitioned per adapter, one adapter's traffic pattern starves another's outbound capacity.

**Smallest viable fix:** Each adapter constructor must receive a dedicated `*http.Client` with its own `Transport` (separate `net/http.Transport` with per-adapter `MaxConnsPerHost`, `MaxIdleConns`, and `DialContext` timeout). This is a one-line change in the adapter factory and is the direct equivalent of SCADA's per-subsystem network interface isolation — metering traffic must not share bandwidth with state estimation traffic.

---

## P2 Findings

### P2-1: No structured adapter health alarms — failures invisible to Docker Compose

**Finding:** The brainstorm describes Docker Compose deployment with "Caddy reverse proxy for webhook ingestion." Docker Compose relies on container-level healthchecks (`HEALTHCHECK` instruction). The brainstorm does not specify what the daemon's health endpoint exposes. Standard Go HTTP servers typically expose `/health` returning HTTP 200 if the process is alive. This reflects process liveness, not adapter operational health.

**Failure scenario:** The GitHub adapter enters a crash loop due to a bad webhook secret (HMAC validation fails for every incoming webhook). The adapter goroutine restarts every 5 seconds. The main goroutine remains alive. The `/health` endpoint returns HTTP 200. Docker Compose marks the service as healthy. The Docker health dashboard shows green. GitHub webhooks are silently discarded for hours. A developer notices that bead states haven't updated for GitHub activity and investigates manually.

**Smallest viable fix:** The `/health` endpoint should return an HTTP 200 only if all configured adapters are in `healthy` or `degraded` (not `failed` or `crash_loop`) state. Add `/metrics` for Prometheus with per-adapter gauges: `interop_adapter_state{adapter="github"}` (0=failed, 1=degraded, 2=healthy), `interop_adapter_last_event_seconds{adapter="github"}`. This is the SCADA alarm management model — structured alarms consumable by a monitoring system, not raw log lines requiring manual inspection.

### P2-2: No explicit degraded-mode contracts per adapter pair

**Finding:** The brainstorm states goroutine isolation means "a crashing Notion adapter doesn't take down GitHub sync." This is true at the goroutine scheduling level, but the question is whether the hub has explicit contracts for what happens to events that *would have been* routed to the failed adapter.

**Failure scenario:** The Notion adapter is down. A beads bead is updated. The beads adapter emits a canonical event. The hub's router looks up the routing table: this event type should be delivered to both the GitHub adapter and the Notion adapter. The GitHub adapter receives it and creates a GitHub issue. The Notion adapter is down; the event is dispatched to its channel. If the channel is buffered, the event queues. If it queues for longer than the configured buffer depth, the event is dropped. If the hub does not track that the Notion adapter was supposed to receive this event, the Notion page is never created when the Notion adapter recovers.

**Smallest viable fix:** Each routing decision must be durable: when the hub decides "this event routes to adapters {GitHub, Notion}," it writes a `routing_record{event_id, [adapter_ids], acked_by=[]}` entry to the event WAL before dispatching to any adapter. When an adapter acknowledges processing, its ID is added to `acked_by`. On adapter recovery, the WAL is scanned for routing records with missing acknowledgments from the recovered adapter. Undelivered events are replayed. This is the SCADA degraded-mode state estimation model — surviving subsystems operate with full data; when the failed subsystem recovers, it gets the missing measurements.

### P2-3: No startup sequencing — adapters race during daemon initialization

**Finding:** The brainstorm describes a long-running daemon but does not specify an explicit startup sequence. Go `main()` with multiple goroutines started in a `for range adapters { go adapter.Start() }` loop means all adapters start concurrently.

**Failure scenario:** The beads adapter starts first and immediately emits a synthetic "full sync requested" event for all known beads. The GitHub adapter is still initializing (fetching the GitHub App installation token). The hub dispatches the beads sync events to the GitHub adapter's input channel before the GitHub adapter has a valid auth token. The GitHub adapter's `HandleEvent` calls the GitHub API with an empty token. GitHub returns HTTP 401. The GitHub adapter treats this as a transient error and queues the events for retry. The retry delay is 30 seconds. 30 seconds into daemon operation, the GitHub adapter retries with a valid token. This works — but the race is non-deterministic. In some environments (cold Docker start, slow network), the initialization takes longer and the retry window fills with spurious errors.

**Smallest viable fix:** Implement a startup barrier in the hub: each adapter exposes a `Ready() <-chan struct{}` channel that closes when the adapter has successfully initialized (auth token acquired, webhook registration confirmed). The hub's event dispatch loop does not route to an adapter until its `Ready()` channel is closed. This is the EMS cold-start model — AGC does not activate until state estimation has converged, state estimation does not run until metering is healthy.

---

## Summary

The SCADA lens reveals that the interop brainstorm's goroutine isolation claim is weaker than it appears:

1. **Panic recovery without in-flight accounting** creates event loss at exactly the wrong moment (mid-write during bulk sync) — the P0 failure that wakes someone at 3 AM
2. **Shared HTTP transport** is the hidden coupling that makes isolation claims false — a single GitHub rate-limit event degrades all adapter outbound capacity simultaneously
3. **No degraded-mode contracts** means the hub does not know what it owes to a recovering adapter — events are silently lost rather than durably queued for replay

The SCADA historian pattern (P0-1 fix) is particularly valuable here: the project already uses `bd` CLI for beads writes (per AGENTS.md convention), which means adapter writes are inherently stateful shell invocations that can fail mid-flight without returning a Go error. A per-adapter WAL is not optional — it is the only way to make the beads adapter reliable under the `bd` CLI execution model.
