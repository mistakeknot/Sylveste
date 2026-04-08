### Findings Index
- P0 | OPS-1 | "Key Decisions" | No graceful shutdown specification — SIGTERM event loss risk
- P1 | OPS-2 | "Key Decisions" | No health vs readiness endpoint distinction — crashed adapters invisible to Docker
- P1 | OPS-3 | "Key Decisions" | No recovery checkpoint — crash during sync causes full re-processing
- P1 | OPS-4 | "Key Decisions" | MCP server and webhook server lifecycle coupling not specified
- P2 | OPS-5 | "Key Decisions" | No structured logging specification — operational debugging impossible
- P2 | OPS-6 | "Key Decisions" | Docker Compose resource limits not mentioned
- P2 | OPS-7 | "Open Questions" | No crash recovery strategy beyond "restart the daemon"
Verdict: risky

## Summary

The brainstorm describes interop as a "long-running daemon on zklw" deployed via "Docker Compose alongside Auraken" with "Caddy reverse proxy for webhook ingestion" and "MCP server mode for Claude Code sessions" (line 36). This is four multiplexed services in a single process: HTTP webhook server, MCP server, event bus, and four adapter goroutine pools. The brainstorm does not address any operational reliability requirement for this complex daemon: no shutdown sequencing, no health check specification, no recovery checkpoint, no structured logging contract, and no Docker resource limits. For a daemon whose failure mode is invisible sync divergence discovered days later, operational reliability is as important as functional correctness — and the brainstorm addresses none of it.

## Issues Found

1. **[P0] OPS-1: No graceful shutdown specification**
   The brainstorm mentions Docker Compose deployment (line 36) but does not describe what happens on SIGTERM (Docker Compose's default stop signal). A Go daemon that calls `os.Exit(0)` on SIGTERM immediately kills all goroutines.
   
   **Risk**: interop receives SIGTERM during a Docker Compose deploy. At that moment, 40 GitHub webhook events are sitting in the event bus channel, dispatched but not yet processed by adapters. The goroutines are killed. The 40 events are lost permanently — GitHub already received 200 OK for each webhook delivery and will not retry them (delivery was "successful" from GitHub's perspective). The corresponding beads issues and Notion pages are never updated. The sync divergence is invisible until a human notices the discrepancy days or weeks later.
   
   This is a P0 because it causes permanent, invisible data loss on every deploy or restart.
   
   **Recommendation**: Add to Key Decisions: "Graceful shutdown sequence: (1) Stop accepting new webhook connections (close HTTP listener). (2) Signal all adapter goroutine pools to stop accepting new events (cancel context). (3) Wait for in-flight events to drain (configurable timeout, default 30s). (4) Flush recovery checkpoint to disk. (5) Close MCP server. (6) Exit. Docker Compose `stop_grace_period` must exceed the drain timeout."

2. **[P1] OPS-2: No health vs readiness endpoint distinction**
   The brainstorm does not mention health checks at all. A Docker Compose service without a health check is assumed healthy as long as the process is running.
   
   **Risk**: All four adapters crash due to unrecoverable errors (e.g., invalid API credentials after a rotation). The HTTP server continues to listen. Docker Compose sees the service as healthy. GitHub webhooks arrive, pass the HTTP server, are dispatched to the event bus, and routed to dead adapter goroutines. Events are silently dropped because no consumer reads the channels. Sync stops entirely with no alert, no restart, and no operator notification.
   
   **Recommendation**: Add to Key Decisions: "Two health endpoints: `/health` (process liveness — HTTP server responding) and `/ready` (operational readiness — at least one adapter goroutine pool is running). Docker Compose healthcheck calls `/ready`. `/ready` returns 503 until all adapters have completed Start() successfully. `/ready` returns 503 if all adapters have crashed. The distinction enables Docker to restart the service when adapters are dead, not just when the process exits."

3. **[P1] OPS-3: No recovery checkpoint specification**
   The brainstorm does not describe what state is preserved across daemon restarts. If the daemon crashes during a Notion sync run, what happens on restart?
   
   **Risk**: Without a persisted recovery checkpoint (last-processed event ID per adapter, adapter connection state), a crash restarts the daemon with no memory of what was already processed. The daemon re-fetches all changes since an undefined timestamp (which may default to "last 24 hours" or "all time"). It re-applies hundreds of already-applied syncs, creating:
   - Duplicate local file writes (benign but noisy)
   - Duplicate beads update events (floods beads event history with noise)
   - Potential re-triggering of webhooks if the sync creates GitHub events (infinite re-sync loop)
   
   **Recommendation**: Add to Key Decisions: "The daemon writes a recovery checkpoint to disk on a periodic flush interval (every 30s) and on shutdown. The checkpoint records: per-adapter last-processed event ID, adapter connection state, event bus drain position. On startup, the daemon reads the checkpoint and resumes from the last-processed position. The checkpoint file uses atomic write-then-rename to prevent corruption during a crash mid-write."

4. **[P1] OPS-4: MCP server and webhook server lifecycle coupling not specified**
   The brainstorm lists both MCP server mode and webhook ingestion (line 36) but does not describe their lifecycle relationship. These are two independent listeners in the same process.
   
   **Risk**: If the webhook server crashes but the MCP server remains healthy, Claude Code sessions query interop's state and get stale data (no new webhook events are being processed). The user sees a functioning MCP interface but sync is silently broken. Conversely, if the MCP server crashes, webhooks continue processing but Claude Code cannot query or control interop.
   
   **Recommendation**: Add: "The MCP server and webhook ingestion server share a lifecycle. If either server's listener fails, the daemon triggers a graceful shutdown of both. The `/ready` endpoint reports both servers' status. A crash in either server is equivalent to a full daemon failure."

5. **[P2] OPS-5: No structured logging specification**
   The brainstorm does not mention logging. A Go daemon without a structured logging contract makes production debugging nearly impossible.
   
   **Risk**: When a user reports "my GitHub issue change didn't sync to Notion," the operator needs to find the specific webhook event and trace its processing path. Without structured log fields (adapter name, event type, delivery ID, processing duration, outcome), the operator has to grep through unstructured log lines with no reliable way to correlate a user report with a specific event.
   
   **Recommendation**: Add to Key Decisions: "All log lines use structured JSON logging (e.g., `slog` in Go 1.21+). Required fields on every log line: `adapter` (string), `event_type` (string), `delivery_id` (string, if webhook), `duration_ms` (int, for processing), `outcome` (success/error/conflict/dropped). The logging middleware enforces these fields — raw `fmt.Println` is prohibited."

6. **[P2] OPS-6: Docker Compose resource limits not mentioned**
   The brainstorm specifies Docker Compose deployment (line 36) but does not mention resource limits.
   
   **Risk**: A goroutine leak or unbounded channel growth (both identified by the fd-go-goroutine-isolation agent) causes interop to consume all available memory on zklw. This affects Auraken and other co-resident services. Without a memory limit, the Linux OOM killer eventually kills a random process — which may be Auraken rather than interop.
   
   **Recommendation**: Add to deployment section: "Docker Compose service includes `deploy.resources.limits.memory: 512M` and `deploy.resources.limits.cpus: '1.0'`. The memory limit is based on expected steady-state usage (4 adapters, ~1000 events/day) with 2x headroom. A goroutine leak that exceeds the limit causes Docker to restart the service (with the OOM kill restart policy) rather than affecting co-resident services."

7. **[P2] OPS-7: No crash recovery strategy beyond implicit restart**
   The brainstorm's deployment model (Docker Compose) provides automatic restart on exit, but does not describe how the daemon recovers after an unclean crash. Beyond the recovery checkpoint (OPS-3), there are additional crash recovery concerns:
   - Partial writes to the ancestor store (from fd-bidirectional-sync-conflicts)
   - Stale lock files preventing adapter startup
   - Orphaned webhook subscriptions (if Notion webhook registration is part of Start())
   
   **Risk**: An unclean crash leaves the daemon in an inconsistent state. Docker Compose restarts it, but the restart fails because of stale state (lock files, partial writes). The service enters a crash loop with no operator visibility beyond Docker logs.
   
   **Recommendation**: Add: "The daemon startup sequence includes a recovery phase that checks for and resolves stale state: remove lock files, validate ancestor store integrity (atomic write-then-rename prevents partial writes), and re-register webhook subscriptions. If recovery fails, the daemon starts in degraded mode (polling only, no webhooks) and logs a structured `recovery_failed` event."

## Improvements

1. **Add an operational runbook section to the brainstorm**: A brief section listing the expected operator actions for common scenarios: how to check sync status, how to force a full re-sync, how to drain and restart without losing events, how to check adapter health individually.

2. **Consider a metrics endpoint**: Expose Prometheus-compatible metrics at `/metrics`: goroutine count, event bus queue depth per adapter, webhook processing latency histogram, adapter circuit breaker state. This enables alerting on sync degradation before users notice.

3. **Plan for log rotation and retention**: A long-running daemon on zklw will produce substantial log volume. Specify log rotation (e.g., `logrotate` or Docker's `max-size/max-file` logging options) and retention period.

--- VERDICT ---
STATUS: fail
FILES: 0 changed
FINDINGS: 7 (P0: 1, P1: 3, P2: 3)
SUMMARY: The brainstorm describes a complex multiplexed daemon (webhook server + MCP server + event bus + 4 adapters) but addresses none of the operational reliability requirements: no shutdown sequencing, no health checks, no recovery checkpoints, no structured logging, and no resource limits. A deploy or crash will cause silent, permanent sync divergence.
---

<!-- flux-drive:complete -->
