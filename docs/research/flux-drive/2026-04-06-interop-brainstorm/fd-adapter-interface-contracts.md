### Findings Index
- P1 | ADP-1 | "Key Decisions" | Adapter interface specifies type signatures only — no behavioral contracts for Start/Stop/HandleEvent/Emit
- P1 | ADP-2 | "Open Questions" | Identity mapping deferred as open question — display name keys will cause silent identity splits
- P1 | ADP-3 | "Key Decisions" | No error taxonomy for HandleEvent — hub cannot distinguish retry-safe from fatal errors
- P2 | ADP-4 | "Key Decisions" | Interface not designed for extension — adding methods breaks all adapters simultaneously
- P2 | ADP-5 | "Key Decisions" | Beads CLI-only constraint stated by convention, not enforced by interface design
- P2 | ADP-6 | "Key Decisions" | Event type is fixed struct — no extensibility for adapter-specific metadata
Verdict: needs-changes

## Summary

The brainstorm defines the Adapter interface as `Start()`, `Stop()`, `HandleEvent(Event)`, `Emit() <-chan Event` (line 39). This is a clean Go interface design, but it specifies only type signatures — not behavioral contracts. The difference matters because four independent adapters will be implemented against this interface, likely by different developers (or agents) at different times. Without documented behavioral invariants (what does Start() guarantee when it returns? can HandleEvent block? is the Emit channel closed on Stop?), each adapter will make different assumptions, creating subtle incompatibilities that surface only when the hub orchestrates them together. Identity mapping — the cross-cutting concern of mapping GitHub users to Notion users to beads assignees — is listed as Open Question 3, which means it will be retrofitted after adapters are deployed, requiring schema migrations.

## Issues Found

1. **[P1] ADP-1: Adapter interface lacks behavioral contracts**
   Line 39 lists the interface methods but does not specify:
   - `Start()`: Does returning without error mean the adapter is ready to handle events, or that initialization has begun? Can Start() be called twice? What happens if Start() fails — is the adapter in a valid state for Stop()?
   - `Stop()`: Must Stop() drain in-flight events from HandleEvent before returning? Is the Emit channel closed after Stop()? Can HandleEvent be called after Stop()?
   - `HandleEvent(Event)`: Is this allowed to block? For how long? Must it be goroutine-safe (called from the hub's dispatch goroutine)?
   - `Emit() <-chan Event`: Is this a new channel per call or the same channel? When does it close?
   
   **Risk**: The GitHub adapter's HandleEvent() blocks for up to 30 seconds during a GitHub API call. The Notion adapter's HandleEvent() returns immediately after enqueueing. The hub calls HandleEvent() sequentially in a dispatch loop. GitHub API slowness blocks all other adapters. This is a P1 because it is a hub-wide stall caused by one adapter's implementation choice.
   
   **Recommendation**: Add an interface contract document (or detailed GoDoc) specifying:
   - `Start()` MUST return only when the adapter is ready to receive HandleEvent calls. It MUST be idempotent.
   - `HandleEvent(Event)` MUST return within 100ms. Long-running work MUST be dispatched to the adapter's internal goroutine pool. It MUST be goroutine-safe.
   - `Stop()` MUST drain in-flight events (up to a configurable timeout, default 30s) before returning. After Stop() returns, HandleEvent calls are no-ops. The Emit channel is closed.
   - `Emit()` returns the same channel for the adapter's lifetime. It is closed by Stop().

2. **[P1] ADP-2: Identity mapping deferred — will require painful retrofit**
   Open Question 3 (line 74) asks: "GitHub user <-> Notion user <-> beads assignee. Where does the mapping live?" This is listed as an open question, meaning it will not be designed before implementation begins.
   
   **Risk**: Without an identity mapping designed up front, each adapter will implement its own ad-hoc matching. The GitHub adapter might match by display name. The Notion adapter might match by email. When a user changes their GitHub display name, the mapping breaks silently — creating a new "unknown" identity in the sync system. All subsequent assignments to that person are lost.
   
   More critically, retrofitting identity mapping after adapters are deployed requires:
   - A migration for every synced entity that references a user
   - A new config schema that each adapter must read
   - Re-testing all sync flows with the new identity system
   
   **Recommendation**: Elevate from Open Questions to Key Decisions: "Identity mapping is a first-class data structure using stable system-native identifiers: GitHub numeric user ID, Notion user UUID, beads assignee string. A config file maps these stable IDs bidirectionally. Display names and emails are metadata, never keys. The mapping is loaded at daemon startup and shared (read-only) with all adapters."

3. **[P1] ADP-3: No error taxonomy for HandleEvent return values**
   The interface specifies `HandleEvent(Event)` but the brainstorm does not describe what errors mean. In production, HandleEvent can fail in at least four distinct ways:
   - Event is malformed (bad payload) — should be discarded, never retried
   - External API is down (GitHub 503) — should be retried with backoff
   - Event creates a conflict (both sides changed) — should be escalated to conflict resolution
   - Event is valid but adapter is shutting down — should be re-queued
   
   **Risk**: Without explicit error types, the hub interprets errors by string content or treats all errors the same. If all errors trigger retry, a malformed event loops forever. If all errors are discarded, transient API failures cause permanent sync gaps.
   
   **Recommendation**: Define an error taxonomy as typed Go errors: `ErrMalformed` (discard), `ErrTransient` (retry with backoff), `ErrConflict` (escalate to conflict resolution), `ErrShuttingDown` (re-queue). The hub's dispatch logic switches on error type.

4. **[P2] ADP-4: Interface not designed for extension**
   The Adapter interface has four methods. When Google Drive is added as a day-2 adapter, it may need capabilities the current interface doesn't support (e.g., `SyncState()` for resumable sync, `HealthCheck()` for adapter-specific diagnostics). Adding a required method to a Go interface breaks all existing implementations.
   
   **Risk**: Adding `HealthCheck()` to the Adapter interface in v2 requires updating all four day-1 adapters simultaneously, even if only the Google Drive adapter needs it. This creates a coupling that makes incremental adapter development impossible.
   
   **Recommendation**: Use the Go capability pattern: define a core `Adapter` interface with the 4 base methods. Define optional capabilities as separate interfaces (`HealthChecker`, `StateSyncer`). The hub checks for optional capabilities via type assertion: `if hc, ok := adapter.(HealthChecker); ok { ... }`. This allows incremental adoption without breaking existing adapters.

5. **[P2] ADP-5: Beads CLI-only constraint is convention, not enforcement**
   Key Decision 6 (line 38) states "Beads access: via `bd` CLI only — consistent with ecosystem convention, no direct SQLite/Dolt access." However, the Adapter interface does not enforce this. The Beads adapter struct can expose a `*sql.DB` field, and a future contributor will use it for "performance" reasons.
   
   **Risk**: Direct Dolt access bypasses the `bd` CLI's validation, audit logging, and version compatibility checks. When the `bd` CLI interface changes (as it has during the v0.60 migration), the direct access breaks silently.
   
   **Recommendation**: The Beads adapter should have an internal `bdcli` package that wraps `exec.Command("bd", ...)` calls. The adapter struct should not contain any database connection fields. Code review should enforce this, and the interface contract doc should state: "The Beads adapter MUST NOT import database drivers or hold database connections."

6. **[P2] ADP-6: Event type is a fixed struct without extensibility**
   The brainstorm does not describe the Event type's structure. If it's a fixed-field Go struct (`type Event struct { Type string; Payload []byte }`), adapter-specific metadata must be smuggled through untyped fields (e.g., `map[string]interface{}`).
   
   **Risk**: When the Google Drive adapter is added, its events include folder_id, sharing permissions, and revision history — none of which exist in the original Event struct. If these are stored in an untyped metadata map, the hub's routing logic ignores them. Drive-to-local-FS syncs lose folder context, placing all files in the root directory.
   
   **Recommendation**: Design the Event type with an extensible metadata field using a typed approach: `type Event struct { Base EventBase; Metadata interface{} }` where each adapter defines its own metadata type. Alternatively, use protobuf-style `Any` or a `json.RawMessage` extension field with documented per-adapter schemas.

## Improvements

1. **Add an adapter compliance test suite**: A Go `testing.T` helper that validates any Adapter implementation against behavioral contracts: Start() returns in <5s, HandleEvent() returns in <100ms, Stop() closes the Emit channel, etc. Run this suite against every adapter to prevent contract drift.

2. **Document the adapter development guide**: A "How to write an adapter" doc that walks through the interface contract, error types, identity mapping integration, and compliance test. This is critical for day-2 adapter development (Google Drive, etc.).

3. **Version the Adapter interface explicitly**: Use a constant (`const AdapterInterfaceVersion = 1`) and have the hub check it at adapter registration. This enables graceful migration when the interface evolves.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 6 (P0: 0, P1: 3, P2: 3)
SUMMARY: The Adapter interface has the right shape (Start/Stop/HandleEvent/Emit) but lacks behavioral contracts, error taxonomy, and extensibility design. Identity mapping — deferred as an open question — will be expensive to retrofit after adapters ship.
---

<!-- flux-drive:complete -->
