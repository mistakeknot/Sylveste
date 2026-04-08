### Findings Index
- P1 | AIC-01 | "Architecture — Adapter interface" | HandleEvent() behavioral contract missing: blocking vs non-blocking not specified
- P1 | AIC-02 | "Open Questions #1 — Identity mapping" | Identity mapping deferred to "config file (YAML)" without stable-ID requirement — display-name keying is a silent data loss vector
- P1 | AIC-03 | "Architecture — Adapter interface" | Emit() channel close-on-Stop semantics not documented — hub cannot safely range over channel
- P2 | AIC-04 | "Architecture — Adapter interface" | Start() behavioral contract ambiguous — "ready to handle events" vs "initialization started" distinction missing
- P2 | AIC-05 | "Architecture — Event type" | Event extensibility story absent — Payload is a sealed interface with no documented extension mechanism for adapter-specific metadata
- P2 | AIC-06 | "F2 — Beads Adapter" | bd CLI encapsulation enforcement strategy not specified — "CLI exclusively" is a convention, not a contract
- P3 | AIC-07 | "Architecture — Adapter interface" | Optional capability interface (HealthChecker, StateSyncer) type-assertion pattern documented in architecture but absent from F1 acceptance criteria
- P3 | AIC-08 | "Architecture — Adapter interface" | ErrShuttingDown typed error listed in architecture section but no acceptance criterion tests that adapters return it during shutdown

Verdict: needs-attention

## Summary

The PRD describes a well-conceived adapter architecture — typed errors, optional capabilities via interface assertion, sealed Event Payload — but leaves the most critical behavioral contracts unspecified. HandleEvent()'s blocking semantics and Emit()'s close-on-Stop contract are the two issues most likely to cause production incidents: a blocking HandleEvent() will stall the entire hub's dispatch goroutine, and an Emit() channel that is not closed on Stop() will leak the goroutine ranging over it. Identity mapping via display names (the "simplest" option in Open Question #1) is a silent corruption vector that cannot be easily retrofitted once synced entities have been created.

## Issues Found

### P1 | AIC-01 — HandleEvent() blocking contract missing

**Location**: PRD § Architecture — "Adapter interface: `HandleEvent(Event) error`"

**Problem**: The interface signature does not specify whether HandleEvent() is permitted to block. If the hub calls HandleEvent() synchronously in a dispatch loop, a slow GitHub API call (up to 30s during rate limiting) will block all other adapters from receiving events for the duration. Per the Architecture section, each adapter has a "bounded input channel (1000)" — but if HandleEvent() blocks, the channel fills and Emit() from other adapters begins to drop events.

**Failure scenario**: GitHub rate-limit kicks in during a busy sync window. GitHub adapter's HandleEvent() blocks for 25 seconds waiting for API response. During this window, the Notion adapter's Emit() channel fills to 1000. New Notion webhook events are silently dropped. The Notion→beads sync pipeline goes silent for 25 seconds with no error surfaced.

**Fix**: Add to F1 acceptance criteria: "HandleEvent() must not block for more than 5s; long-running operations must be dispatched to a goroutine before returning. Hub calls HandleEvent() in a per-adapter goroutine, not in the main dispatch loop."

---

### P1 | AIC-02 — Identity mapping defaults to display names (silent corruption vector)

**Location**: PRD § Open Questions #1: "Config file is simplest for day-1"

**Problem**: The Open Question explicitly acknowledges identity mapping but defers the storage mechanism and — critically — does not specify that keys must be stable system-native identifiers (GitHub numeric user ID, Notion user UUID). If the config file uses GitHub display names as keys (the natural "simplest" choice), a user renaming their GitHub account creates a new unknown identity in beads, and their existing assigned beads stop routing to GitHub Issues. This is a silent data loss vector that scales with team size.

**Concrete scenario**: Developer "alice" changes her GitHub username from `alice` to `alice-dev`. The identity mapping config has `github: "alice"`. Future GitHub issue assignments go to `alice-dev`, which has no mapping — beads assignee field silently becomes empty. All of alice-dev's GitHub issue events route to an anonymous sink in beads.

**Fix**: Add to F2 acceptance criteria: "Identity mapping config uses stable system-native IDs as primary keys (GitHub numeric user ID, Notion user UUID). Display names are stored as aliases only. Config schema must include a `github_user_id` field, not just `github_username`."

---

### P1 | AIC-03 — Emit() close-on-Stop semantics undocumented

**Location**: PRD § Architecture — "Adapter interface: `Emit() <-chan Event`"

**Problem**: The hub must range over the Emit() channel to receive events. If an adapter does NOT close its Emit() channel when Stop() is called, the hub's ranging goroutine leaks indefinitely. If an adapter DOES close the channel before Stop() returns, the hub's goroutine exits cleanly. The contract must be explicit: "Emit() channel is closed by the adapter when Stop() returns."

**Failure scenario**: Beads adapter implements Stop() to cancel its polling goroutine but does not close the Emit() channel. The hub's dispatch goroutine ranges over the beads Emit() channel forever, blocking graceful shutdown past the 30s drain timeout. SIGTERM during a busy sync window causes interop to hang and be SIGKILL'd by Docker's stop_grace_period, losing the in-flight SyncJournal flush.

**Fix**: Add to F1 acceptance criteria: "Each adapter's Stop() closes its Emit() channel before returning. Hub ranging goroutines exit cleanly without timeout when all adapters have stopped."

---

### P2 | AIC-04 — Start() behavioral contract ambiguous

**Location**: PRD § Architecture — "Adapter interface: `Start(ctx)`"

**Problem**: Start() returning without error could mean "initialization complete, ready to handle events" or "initialization started in background, may not be ready yet." The hub cannot safely call HandleEvent() on an adapter whose Start() has returned if "ready" is not guaranteed. F3 (GitHub adapter) has webhook receiver setup, which involves HTTP server binding — if Start() returns before the bind completes, early webhook deliveries are silently lost.

**Fix**: Add to F1 acceptance criteria: "Start(ctx) must not return until the adapter is fully initialized and ready to accept HandleEvent() calls and emit events. HTTP server binding, initial state sync, and credential validation must complete before Start() returns."

---

### P2 | AIC-05 — Event Payload extensibility undocumented

**Location**: PRD § Architecture — "Event type: `Payload` (sealed interface)"

**Problem**: The PRD notes Payload is a "sealed interface" but does not describe the extension mechanism for adapter-specific metadata. When a future Google Drive adapter is added, its events need folder_id and MIME type context that the existing Payload types don't carry. If there is no documented extension pattern, adapter authors will add string maps to RoutingHints (which is documented as cross-system IDs) or create untyped metadata blobs.

**Fix**: Add to F1 acceptance criteria or Architecture section: "The Event type includes an `Extensions map[string]json.RawMessage` field for adapter-specific metadata. Core routing logic ignores unknown extension keys. Adapter-specific logic accesses extensions by key with type assertion."

---

### P2 | AIC-06 — Beads adapter "CLI exclusively" is a convention, not a contract

**Location**: PRD § F2: "Uses `bd` CLI exclusively — no direct Dolt access"

**Problem**: The criterion states a convention but not how it is enforced. If the Beads adapter struct is exported and embeds a Dolt connection, a future contributor will use it. The constraint should be enforced architecturally: the adapter package should have no import of any Dolt library, enforced by go build tags or package-level import restrictions.

**Fix**: Add to F2 acceptance criteria: "The beads adapter package has no import of `github.com/dolthub/dolt` or any Dolt library — verified by `go mod graph | grep dolt` showing no path through the beads adapter package."

---

### P3 | AIC-07 — Optional capability interfaces not in F1 acceptance criteria

**Location**: PRD § Architecture: "Optional capabilities via Go interface assertion (HealthChecker, StateSyncer)"

**Problem**: The Architecture section documents HealthChecker and StateSyncer as optional interfaces, but F1's acceptance criteria do not include a test that the hub correctly type-asserts for these interfaces and uses them when available. Without a criterion, implementations may skip these interfaces and the /ready endpoint will report "operational" for adapters that have no health check.

**Fix**: Add to F1 acceptance criteria: "Hub type-asserts each registered adapter for HealthChecker; if asserted successfully, `/ready` uses HealthChecker.Check() for that adapter's status. Adapters without HealthChecker are reported as 'assumed healthy'."

---

### P3 | AIC-08 — ErrShuttingDown not tested

**Location**: PRD § Architecture: "Typed errors: ErrMalformed, ErrTransient, ErrConflict, ErrShuttingDown"

**Problem**: ErrShuttingDown is listed in the architecture but no acceptance criterion tests that an adapter returns it when HandleEvent() is called after Stop() has been initiated. Without this criterion, the hub's dispatch loop may continue sending events to a shutting-down adapter, which could block the drain.

**Fix**: Add to F1 acceptance criteria: "HandleEvent() called after Stop() is initiated returns ErrShuttingDown; hub drops the event and does not retry."

## Improvements

1. **Write an interface contract document** — before F1 implementation begins, write a `docs/interfaces/adapter.md` that specifies behavioral invariants for all four Adapter methods in prose. This is a one-day investment that prevents N adapter implementations from diverging in incompatible ways.

2. **Add an adapter compliance test suite** — a Go `testing` package test that any adapter can run against, verifying: Start() readiness guarantee, HandleEvent() non-blocking, Emit() closes on Stop(), typed error taxonomy. New adapters (Google Drive, Auraken) run the suite before merge.

3. **Resolve Open Question #1 before F2 begins** — identity mapping storage format is a schema decision that affects F2 (beads), F3 (GitHub), and F4 (Notion). Deferring it means all three adapters will need schema migrations when the decision is made.

<!-- flux-drive:complete -->
