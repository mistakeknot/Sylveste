### Findings Index
- P1 | GOR-1 | "Architecture Sketch" | No panic recovery contract specified for adapter goroutine pools
- P1 | GOR-2 | "Architecture Sketch" | Event bus channel backpressure semantics unspecified — synchronous send risk
- P1 | GOR-3 | "Key Decisions" | Goroutine pool worker count unbounded — no cap documented
- P2 | GOR-4 | "Key Decisions" | Circuit breaker scoping not explicit — shared vs per-adapter ambiguous
- P2 | GOR-5 | "Architecture Sketch" | No distinction between slow-consumer and dead-consumer on event bus
- P2 | GOR-6 | "Key Decisions" | Context.Context propagation and cancellation chain not specified
Verdict: needs-changes

## Summary

The brainstorm makes the right architectural bet — goroutine isolation per adapter is the correct Go idiom for a multi-backend daemon. However, the document states the conclusion ("a crashing Notion adapter doesn't take down GitHub sync") without specifying the mechanisms that make it true. Panic recovery, channel backpressure, bounded worker pools, and per-adapter circuit breaker scoping are all mentioned at headline level but lack the behavioral contracts needed to implement them correctly. Each of these is a production incident waiting to happen if a developer interprets the brainstorm literally and implements goroutine pools without recover() wrappers or channel capacity limits.

## Issues Found

1. **[P1] GOR-1: No panic recovery contract for adapter goroutine pools**
   The brainstorm states "each adapter runs in its own goroutine pool with panic recovery and circuit breakers" (line 29) but does not specify the recovery contract. In Go, a panic in a goroutine kills the entire process unless explicitly caught with `defer func() { if r := recover(); r != nil { ... } }()`. The document assumes panic recovery exists but does not require:
   - That every goroutine spawned by an adapter wraps its entry function in a recover() block
   - That recovered panics are logged with adapter name, panic value, and stack trace
   - That the goroutine is restarted after recovery (vs silently dying)
   - That recovered panics increment the adapter's circuit breaker failure counter
   
   **Risk**: A nil pointer dereference in the Notion block-to-markdown converter crashes the entire interop daemon, taking all four adapters offline. This is the single most common Go daemon failure mode and the brainstorm's central isolation bet depends on getting this right.
   
   **Recommendation**: Add to Key Decisions: "Each adapter goroutine pool entry function MUST be wrapped in a deferred recover() that logs the panic with structured fields (adapter, panic value, stack trace), increments the circuit breaker failure counter, and restarts the goroutine after a backoff delay."

2. **[P1] GOR-2: Event bus channel backpressure semantics unspecified**
   The architecture sketch shows an "Event Bus (channels)" connecting all four adapters (line 58-60). The brainstorm does not specify:
   - Whether channels are buffered or unbuffered
   - What happens when a channel is full (block the sender? drop the event? apply backpressure?)
   - Whether each adapter has its own input channel or all adapters share one
   
   **Risk**: If the event bus uses a single shared channel with synchronous sends (`ch <- event`), a slow Notion adapter blocks the GitHub webhook handler goroutine from emitting events. Webhook responses back up, GitHub fires delivery timeouts, retries pile up, and GitHub eventually marks the webhook endpoint as unhealthy. The entire webhook-first architecture fails because of one slow consumer.
   
   **Recommendation**: Specify in Architecture Sketch: "Each adapter has a dedicated buffered input channel (capacity: configurable, default 1000). Producers use non-blocking sends (`select { case ch <- event: default: dropCounter++ }`). The hub routes events to per-adapter channels, not a shared bus."

3. **[P1] GOR-3: Goroutine pool worker count unbounded**
   The brainstorm mentions "goroutine pools" (line 29) but does not specify worker count bounds. Go makes it trivially easy to spawn a goroutine per event (`go handleEvent(e)`), and without an explicit worker pool pattern, a burst of 10,000 GitHub webhook events would spawn 10,000 goroutines simultaneously.
   
   **Risk**: Under a webhook burst (repository transfer, mass issue migration), unbounded goroutine spawning exhausts file descriptors and memory. The daemon crashes or becomes unresponsive, affecting all adapters and co-resident services (Auraken) on zklw.
   
   **Recommendation**: Add to Key Decisions: "Each adapter goroutine pool has a configurable worker count (default: 10). Events exceeding pool capacity queue in the adapter's input channel. Pool size is exposed as a runtime metric."

4. **[P2] GOR-4: Circuit breaker scoping ambiguous**
   The brainstorm mentions "circuit breakers" (line 29) alongside "panic recovery" but does not specify whether circuit breaker state is per-adapter or shared. The natural reading is per-adapter, but without explicit specification, a shared implementation is equally plausible.
   
   **Risk**: A shared circuit breaker that opens on Beads failures (common during Dolt server restarts, per project memory) would also reject GitHub webhook events, causing silent sync stoppage across unrelated adapters.
   
   **Recommendation**: Add to Key Decisions: "Circuit breaker state is per-adapter. Each adapter struct contains its own circuit breaker instance. The hub's routing logic checks the destination adapter's circuit breaker before dispatching, not a global breaker."

5. **[P2] GOR-5: No slow-consumer vs dead-consumer distinction on event bus**
   The architecture shows the event bus routing to four adapter goroutine pools, but the brainstorm does not distinguish between an adapter that is slow (healthy but overwhelmed) and one that has exited (goroutine pool died after unrecoverable panic).
   
   **Risk**: Events dispatched to a dead adapter's channel pile up indefinitely. The event bus has no mechanism to detect that the consumer is gone, leading to a memory leak that grows until the daemon is restarted.
   
   **Recommendation**: The hub should monitor adapter goroutine pool liveness (e.g., heartbeat or `select` on a done channel). When a pool exits, the hub should stop routing to it and log a structured error. Consider a "dead letter queue" for events that could not be delivered.

6. **[P2] GOR-6: Context.Context propagation not specified**
   The brainstorm mentions context.Context nowhere. In Go daemons, context is the primary mechanism for cancellation propagation (SIGTERM -> context cancel -> all goroutines notice and drain). Without a specified context chain, each adapter will implement its own shutdown detection, leading to inconsistent drain behavior.
   
   **Recommendation**: Specify that the daemon creates a root context from `signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)`, passes it to each adapter's `Start(ctx)`, and adapters propagate it to all worker goroutines.

## Improvements

1. **Document the goroutine lifecycle state machine**: Each adapter goroutine pool should have documented states: Starting -> Running -> Draining -> Stopped. Transitions should be explicit (context cancel triggers Running -> Draining, last event processed triggers Draining -> Stopped).

2. **Add event bus capacity as a tunable config value**: The channel buffer size should be in config (e.g., `event_bus.per_adapter_capacity: 1000`) with a documented rationale for the default.

3. **Consider a supervisor pattern**: Rather than each adapter managing its own goroutine restart after panic recovery, a central supervisor goroutine could monitor all adapter pools and handle restart logic uniformly, similar to Erlang's supervisor trees.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 6 (P0: 0, P1: 3, P2: 3)
SUMMARY: The goroutine isolation architecture bet is sound but the brainstorm lacks the behavioral contracts (panic recovery, backpressure, bounded pools) that make it work in practice. Three P1 gaps would cause production incidents if implemented as-is.
---

<!-- flux-drive:complete -->
