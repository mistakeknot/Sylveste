### Findings Index
- P0 | WHK-1 | "Key Decisions" | Webhook signature verification not mentioned — accepting unauthenticated payloads
- P1 | WHK-2 | "Day-1 Adapters" | No async processing contract — synchronous handler risk for webhook timeout
- P1 | WHK-3 | "Why This Approach" | No delivery ID deduplication specified — at-least-once delivery creates duplicate beads
- P1 | WHK-4 | "Day-1 Adapters" | Notion webhook reliability undocumented — no fallback for missing signatures or dropped deliveries
- P2 | WHK-5 | "Key Decisions" | Caddy reverse proxy header forwarding not specified
- P2 | WHK-6 | "Day-1 Adapters" | No deduplication store retention window — unbounded memory growth risk
- P2 | WHK-7 | "Day-1 Adapters" | No event type allowlisting — unknown Notion event types could crash handlers
Verdict: risky

## Summary

The brainstorm positions webhook-first as a core architectural bet ("Instead of interkasten's 60s polling, interop receives push notifications and reacts immediately") but does not address any of the operational reliability requirements that make webhook ingestion safe. Webhook signature verification — the single most critical security control for an endpoint that can create, close, and modify beads — is entirely absent from the document. Delivery deduplication, async processing, and Caddy header forwarding are also unspecified. This is a risky gap because webhook endpoints are internet-facing attack surfaces, and the brainstorm's day-1 data flows (Beads <-> GitHub Issues) mean a forged webhook can directly manipulate work tracking state.

## Issues Found

1. **[P0] WHK-1: Webhook signature verification entirely absent**
   The brainstorm's Key Decisions (lines 31-38) and Day-1 Adapters table (lines 44-49) mention GitHub webhook support but never mention HMAC signature verification. GitHub sends an `X-Hub-Signature-256` header with every delivery. Notion has its own verification scheme. Neither is referenced.
   
   **Risk**: Without signature verification, anyone who discovers or guesses the webhook URL can POST crafted payloads. An attacker could:
   - Close beads issues by sending fake `issues.closed` events
   - Create spurious issues by sending fake `issues.opened` events
   - Inject malicious comments that propagate to Notion pages
   
   This is a P0 because it affects data integrity of the beads tracking system, which is the "single source of truth for work tracking" per CLAUDE.md.
   
   **Recommendation**: Add to Key Decisions: "All webhook ingestion MUST verify the sender's cryptographic signature before dispatching to the event bus. GitHub: validate X-Hub-Signature-256 against the app's webhook secret. Notion: validate per Notion's webhook verification docs. Signature verification is a middleware layer that cannot be bypassed by configuration."

2. **[P1] WHK-2: No async processing contract for webhook handlers**
   The brainstorm states "interop receives push notifications and reacts immediately" (line 27) but does not specify whether processing is synchronous (in the HTTP handler) or asynchronous (dispatched to the event bus before returning).
   
   **Risk**: If the webhook handler calls the Notion API or runs `bd` CLI commands synchronously before returning the HTTP response, GitHub's 10-second timeout will fire during any external API slowdown. GitHub retries with exponential backoff for 72 hours, but after enough timeouts it marks the endpoint as "failing" and may disable delivery entirely. This would silently break all webhook-driven sync.
   
   **Recommendation**: Add to Architecture Sketch: "Webhook handlers MUST return 202 Accepted within 100ms. The handler validates the signature, parses the payload, enqueues the event to the adapter's input channel, and returns. All processing happens asynchronously in the adapter's goroutine pool."

3. **[P1] WHK-3: No delivery ID deduplication**
   GitHub includes an `X-GitHub-Delivery` header (a UUID) with every webhook delivery. When GitHub retries a delivery (because interop was briefly slow or restarting), it reuses the same delivery ID. The brainstorm does not mention deduplication.
   
   **Risk**: During a deploy or restart, GitHub retries several webhook deliveries. Without deduplication, each retry is processed as a new event. A single GitHub issue creation event processed twice creates two beads — a permanent tracking state split that requires manual reconciliation.
   
   **Recommendation**: Add to Key Decisions: "The event bus checks each incoming event against a recent-deliveries store (keyed by delivery ID) before dispatching. Duplicate deliveries are acknowledged (200 OK) but not processed. The dedup store retains delivery IDs for 7 days (matching GitHub's 72-hour retry window with margin)."

4. **[P1] WHK-4: Notion webhook reliability undocumented and no fallback**
   The brainstorm lists Notion as a webhook source (line 46) but Notion's webhook API is newer and less battle-tested than GitHub's. The brainstorm mentions "Polling exists only as fallback for systems without webhook support" (line 27) but does not specify a polling fallback for Notion in case webhooks are unreliable.
   
   **Risk**: Notion webhook delivery has been inconsistent in production (delayed deliveries, dropped events during Notion outages). If interop relies solely on Notion webhooks with no periodic reconciliation, sync will silently lag during Notion infrastructure issues. Unlike GitHub (which retries for 72 hours), Notion's retry behavior is less documented and less aggressive.
   
   **Recommendation**: Add to Day-1 Adapters: "Notion adapter uses webhooks as primary with a periodic reconciliation poll (every 5 minutes) as fallback. The reconciliation poll checks for changes since the last webhook timestamp and processes any missed events. This hybrid approach ensures sync resilience during Notion webhook outages."

5. **[P2] WHK-5: Caddy reverse proxy header forwarding not addressed**
   The brainstorm specifies "Caddy reverse proxy for webhook ingestion" (line 36) but does not mention header forwarding configuration. Caddy's default reverse proxy behavior varies by version and configuration.
   
   **Risk**: If Caddy strips or modifies the `X-Hub-Signature-256` or `X-GitHub-Delivery` headers when forwarding to interop, signature verification silently fails for every webhook. This is a subtle deployment bug that would cause all webhooks to be rejected after signature verification is implemented (or silently bypass verification if the code handles missing signatures by skipping the check).
   
   **Recommendation**: Note in deployment section: "Caddy Caddyfile must include `header_up X-Hub-Signature-256 {header.X-Hub-Signature-256}` and `header_up X-GitHub-Delivery {header.X-GitHub-Delivery}` in the reverse proxy block."

6. **[P2] WHK-6: No dedup store retention window specified**
   Even if deduplication is added (per WHK-3), the brainstorm does not specify whether the store is bounded. An unbounded in-memory map of delivery IDs will grow indefinitely.
   
   **Risk**: At 100 webhooks/day, a delivery ID (~36 bytes UUID) accumulates ~1.3 KB/day. Negligible short-term, but over a year without cleanup, combined with any event metadata stored alongside, this becomes a slow memory leak on a long-running daemon.
   
   **Recommendation**: Specify a TTL-based eviction policy on the dedup store (7-day window maps to GitHub's retry window).

7. **[P2] WHK-7: No event type allowlisting for Notion webhooks**
   The brainstorm does not mention event type filtering. Both GitHub and Notion may add new event types in API updates.
   
   **Risk**: A handler that attempts to process every event type will encounter unknown types when the API provider adds new ones. If the handler panics on an unexpected event structure (e.g., missing field in a new event type), the adapter crashes.
   
   **Recommendation**: Add: "Each adapter maintains an explicit allowlist of handled event types. Unknown types are logged with structured `unhandled_event_type` field and discarded. New types require a code change to handle, never auto-processing."

## Improvements

1. **Add a webhook health dashboard**: Track per-adapter metrics: delivery count, duplicate count, signature failures, processing latency p50/p95. Expose via the MCP server so Claude Code sessions can query webhook health.

2. **Document the Notion webhook setup path**: Open Question 4 asks about Notion webhook configuration but should be elevated to a day-1 requirement. Without the webhook setup, the Notion adapter falls back to polling only, which defeats the webhook-first architecture.

3. **Consider a dead letter queue for failed event processing**: Events that pass signature verification but fail processing (malformed payload, adapter error) should be stored for retry or manual inspection rather than silently dropped.

--- VERDICT ---
STATUS: fail
FILES: 0 changed
FINDINGS: 7 (P0: 1, P1: 3, P2: 3)
SUMMARY: The webhook-first architecture is the right bet but the brainstorm omits all operational reliability controls — most critically, signature verification is absent, making the internet-facing webhook endpoint an unauthenticated attack surface for beads manipulation.
---

<!-- flux-drive:complete -->
