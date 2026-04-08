---
agent: fd-atc-flow-management
source_doc: docs/brainstorms/2026-04-06-interop-brainstorm.md
generated_at: 2026-04-06
lens: Air traffic flow management — event routing, ordering, sector handoff, backpressure
---

# fd-atc-flow-management — Review Findings

## Decision Lens

Does the event bus route, sequence, and arbitrate between adapters the way ATFM routes and sequences aircraft across sector boundaries — with priority, ordering guarantees, and deterministic conflict resolution when two adapters claim the same resource?

---

## P0 Findings

### P0-1: No per-entity event serialization — goroutine scheduling determines concurrent update outcome

**Finding:** The brainstorm specifies "goroutine pools" as the per-adapter isolation unit and a "channels"-based event bus. Go channels provide FIFO ordering within a single channel, but the brainstorm defines no mechanism for serializing concurrent updates to the same logical entity across *different* adapters.

**Failure scenario:** A beads bead is updated simultaneously via a Notion webhook (Notion adapter goroutine A) and a GitHub webhook (GitHub adapter goroutine B). Both events arrive at the hub within the same sync window. Both are dispatched to the beads adapter. The beads adapter processes them in goroutine-scheduled order — whichever goroutine wins the channel read applies its write first. The result is non-deterministic: in run 1 the Notion content overwrites GitHub content; in run 2 the reverse. The final bead state differs between identical input sequences depending on CPU scheduling. No replay can reproduce the result.

**Condition:** The event bus (`Event Bus (channels)` in the architecture sketch) has no per-entity lock, per-entity channel, or logical clock that prevents two cross-adapter updates to the same entity from racing at the consumer side.

**Smallest viable fix:** Add a `EntityKey` field to the canonical `Event` type (e.g., `beads:issue:<id>`). In the hub router, maintain a `map[EntityKey]chan Event` of per-entity dispatch channels (created on demand, GC'd when idle). All events for the same entity are serialized through the same per-entity channel before reaching the consuming adapter's goroutine pool. This is the Go equivalent of ATFM's per-aircraft conflict alert — you cannot have two sector controllers issuing simultaneous instructions for the same aircraft.

---

### P0-2: Conflict detection fires after dual-emission, not before

**Finding:** The brainstorm states "three-way merge for content" as the conflict resolution strategy. The architecture sketch shows adapters on the output side of the event bus. This implies conflict resolution happens at the consuming adapter, *after* both conflicting events have already been emitted into the bus.

**Failure scenario:** GitHub and Notion both update a beads bead title within the same 100ms window. The hub emits both events to the beads adapter channel. The beads adapter applies event 1 (GitHub title update). Before it processes event 2, a monitoring query reads the bead title — it sees the GitHub value. Then event 2 applies (Notion title update), overwriting it. The "conflict" was never detected; the three-way merge ran against stale base state because the base snapshot was taken before event 1 was applied. The merge produces a silently wrong result.

**Condition:** When conflict detection is downstream of event dispatch, the hub has already committed to delivering both events. The only correct detection point is before dispatch: the hub must hold both events, compare them against the same base snapshot, and route to conflict resolution *before* either reaches a consuming adapter.

**Smallest viable fix:** The hub router should check `EntityKey` collision: if two events for the same `EntityKey` are in-flight simultaneously, hold the second event and merge it with the first before dispatching either. This is the ATFM conflict alert model — detect the conflict in the routing layer, not at the sector (adapter) level.

---

## P1 Findings

### P1-1: Webhook ingestion decoupled from adapter readiness — events lost during adapter restart

**Finding:** The brainstorm describes a `Caddy reverse proxy for webhook ingestion` and a single interop daemon. The Caddy layer accepts webhooks independently of adapter goroutine health. The brainstorm mentions "panic recovery" for adapter goroutines but does not specify any durable queue between Caddy and the adapter.

**Failure scenario:** The Notion adapter goroutine crashes during a bulk sync. Panic recovery schedules a restart with backoff (say, 5 seconds). During those 5 seconds, three Notion webhooks arrive at Caddy. Caddy forwards them to the interop HTTP server. The interop HTTP server returns HTTP 200 (the HTTP handler is alive). The events are dispatched to the Notion adapter's input channel. The Notion adapter goroutine has not restarted yet. Depending on channel buffering: (a) if the channel is unbuffered, the HTTP handler blocks, Caddy times out, Notion marks the webhook delivery as failed and may retry; (b) if the channel is buffered, events queue but if the restart takes longer than the buffer drains, subsequent events block the HTTP handler goroutine. Neither path guarantees the 3 events are durably recorded and processed after the adapter restarts.

**Smallest viable fix:** Before dispatching a webhook payload to an adapter's input channel, check adapter health state. If the adapter is in the `restarting` state, write the payload to a durable per-adapter dead-letter queue (append-only file or SQLite WAL) and return HTTP 202 Accepted. On adapter restart, drain the dead-letter queue before processing new events. This is the ATFM ground delay program model — slow the ingest rate to match downstream capacity.

---

### P1-2: No fallback activation path when primary webhook source fails

**Finding:** The brainstorm describes "polling as fallback for systems without webhook support" and "polling as last resort." It does not describe an automatic fallback mechanism when a *supported* webhook source (GitHub, Notion) stops delivering.

**Failure scenario:** GitHub's webhook delivery service has an outage for 45 minutes. No GitHub events arrive at the interop daemon. The beads adapter continues operating but does not detect that GitHub sync has stopped. Developer closes a GitHub issue manually. The bead remains open. The developer creates a new PR referencing the issue. The bead has no PR link. The interop daemon's GitHub adapter is healthy (the goroutine is running, the webhook secret is valid) but it has received no events — the hub cannot distinguish legitimate silence from missed deliveries. After the outage ends, GitHub may or may not replay missed webhooks (GitHub replays up to 3 failed attempts; a 45-minute outage exceeds retry window for many events).

**Smallest viable fix:** Each adapter should maintain a `lastEventAt` timestamp. The hub supervisor goroutine checks: if `time.Since(lastEventAt) > adapter.SilenceThreshold` and `adapter.Type == WebhookDriven`, automatically switch the adapter to polling mode for the configured `FallbackPollInterval`. This is the ATFM contingency routing model — when a sector data feed goes silent beyond the declared timeout, switch to secondary radar source.

---

## P2 Findings

### P2-1: Unbounded event bus channels — no backpressure to webhook ingestion layer

**Finding:** The architecture sketch shows `Event Bus (channels)` as Go channels. The brainstorm does not specify channel buffer sizes or backpressure semantics.

**Failure scenario:** The Notion adapter is processing a bulk sync of 5,000 pages. Its goroutine pool is at capacity. New events continue to be dispatched from the bus to the Notion adapter's input channel. If the channel is buffered with a large buffer (or unbounded via a wrapper), events queue in memory. The interop daemon continues accepting incoming webhooks at full rate. Memory grows proportionally to the backlog. Eventually the process OOMs. No operator signal indicates the growing lag.

**Smallest viable fix:** Use bounded channels (e.g., `make(chan Event, 512)`) for each adapter's input. When the channel is full, the hub's dispatch goroutine should write the event to the per-adapter dead-letter queue rather than blocking, and increment a `adapter_channel_full_total` Prometheus counter. This provides both backpressure and operator visibility.

### P2-2: Hub treats event emission as completion — no consumer acknowledgment

**Finding:** The brainstorm specifies `HandleEvent(Event)` in the adapter interface. There is no `AcknowledgeEvent(eventID)` method. The hub has no way to know whether an event was successfully applied to the external system.

**Failure scenario:** The hub dispatches an event to the beads adapter via channel. The beads adapter goroutine receives it, calls `bd` CLI, and the CLI hangs (Dolt server unresponsive). The goroutine is blocked. The hub has no acknowledgment timeout. From the hub's perspective, the event has been delivered. If the adapter goroutine is later killed (OOM, shutdown), the event is lost. The hub does not retry.

**Smallest viable fix:** Add `AcknowledgeEvent(ctx context.Context, eventID string) error` to the `Adapter` interface. The hub tracks in-flight events per adapter with a timeout. Unacknowledged events after timeout are moved to the dead-letter queue. This is the ATC handoff model — the receiving sector must acknowledge the handoff before the originating sector releases responsibility.

---

## Summary

The interop brainstorm defines a solid goroutine-isolation architecture but leaves three critical routing gaps that ATFM would classify as mandatory before a system goes live:

1. **Per-entity serialization** — without it, concurrent cross-adapter updates to the same entity produce non-deterministic state
2. **Pre-emission conflict detection** — detecting conflicts at the consuming adapter is too late; the hub must hold and compare concurrent updates before dispatching either
3. **Adapter-readiness gate on webhook ingestion** — accepting webhooks when the consuming adapter is not healthy creates a loss window that no amount of panic recovery closes

The webhook-to-adapter acknowledgment gap (P2-2) is technically P2 in current scope but will upgrade to P1 the moment the Dolt/bd CLI path is under any load — Dolt startup latency is documented in project memory as a recurring operational issue.
