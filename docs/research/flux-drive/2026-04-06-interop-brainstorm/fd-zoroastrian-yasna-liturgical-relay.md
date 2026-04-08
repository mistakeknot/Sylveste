# fd-zoroastrian-yasna-liturgical-relay Review: interop Integration Fabric Brainstorm

**Source:** `docs/brainstorms/2026-04-06-interop-brainstorm.md`
**Reviewed:** 2026-04-06
**Agent:** fd-zoroastrian-yasna-liturgical-relay (Zaotar — goroutine isolation, typed handoff contracts, panic-recovery continuity)
**Track:** D (Esoteric)
**Bead:** sylveste-bcok

---

## Findings Index

- P0 | ZYL-01 | Architecture Sketch / Event Bus | No contamination-isolation boundary: adapters share a single unguarded channel, so a panicking adapter can write to shared state before recover() fires
- P1 | ZYL-02 | Key Decisions #2 / Panic Recovery | Panic recovery described as adapter restart; no replay mechanism for events mid-processing at panic time
- P1 | ZYL-03 | Adapter Interface / HandleEvent(Event) | `Event` type is unspecified — no compile-time typed handoff contracts between adapters
- P2 | ZYL-04 | Key Decisions #6 / Circuit Breaker | Circuit breaker behavior on event queuing during open state is unspecified — events may be dropped or discarded rather than held at the handoff point
- P2 | ZYL-05 | Day-1 Adapters / Beads: event watch | No defined handoff contract for `bd` CLI events — Beads adapter emits via `bd` CLI subprocess, which is an untyped stdout pipe with no structured handoff

---

## ZYL-01 — No Contamination-Isolation Boundary on the Shared Event Bus (P0)

**Location:** `docs/brainstorms/2026-04-06-interop-brainstorm.md`, "Architecture Sketch", diagram showing adapters writing directly to the shared "Event Bus (channels)".

**Severity:** P0 — A panicking adapter can write a partial or malformed event to the shared channel before `recover()` fires. Go's `recover()` only fires on the deferred return — any channel sends initiated by the panicking goroutine before the panic point may complete before `recover()` suppresses further execution. If the event bus uses an unbuffered or buffered `chan Event` (implying `Event` is an interface or concrete struct), a partial write is not possible on the channel operation itself (channel sends are atomic in Go), but a panicking goroutine can emit a structurally valid but semantically malformed event before the panic — one that passes compile-time checks but contains nil fields, zero-valued IDs, or inverted state flags. Because Go channel sends are syntactically complete operations (not multi-step writes), the actual P0 is the *logical contamination* scenario: the Notion adapter, mid-processing a complex webhook, emits an update event with `EntityID: ""` and `NewState: "closed"` before panicking on a nil dereference. The event is not corrupted bytes — it is a valid-typed but semantically invalid event that reaches the beads adapter and triggers a spurious close.

**The Yasna parallel:**
The Vendidad's contamination protocol distinguishes between contamination that spreads through shared implements (implements that passed through the failing station before the station's purification) and contamination that stays within the failing station. The brainstorm's architecture has no equivalent of "contamination does not leave the station before purification is complete." A panicking adapter emits through the shared channel — the channel IS the shared sacred implement. Nothing in the brainstorm prevents a pre-panic emit of a semantically invalid event.

**Concrete failure scenario:** The Notion webhook adapter receives a `page.updated` event for a page that is being deleted concurrently. It begins constructing an `Event{EntityID: page.ID, Type: "update", ...}` and calls `bus.Emit(event)` before a nil dereference on `page.Properties` triggers a panic. The event reaches the beads adapter with `EntityID` set but `Payload` nil. The beads adapter calls `bd update` with a nil payload, producing a malformed `bd` invocation that either silently no-ops or corrupts the bead's state fields. The panic fires, the Notion adapter restarts — but the spurious beads mutation has already been committed.

**Smallest fix:** Adapters must not write to the bus directly. Introduce a `bus.Emit(e Event) error` method that validates the event (non-empty EntityID, non-nil Payload, valid Type) before enqueuing. The adapter calls `bus.Emit()` — validation happens in the bus's send path, not in the adapter. If validation fails, the bus returns an error and logs the dropped event. This is a single-method API boundary, not a redesign. Cost: one `Emit()` method with 3-5 validation checks.

```go
func (b *EventBus) Emit(e Event) error {
    if e.EntityID == "" || e.Type == "" || e.Payload == nil {
        b.log.Warn("adapter emitted invalid event, dropping", "event", e)
        return ErrInvalidEvent
    }
    b.ch <- e
    return nil
}
```

---

## ZYL-02 — Panic Recovery Described as Adapter Restart; No Replay for In-Flight Events (P1)

**Location:** `docs/brainstorms/2026-04-06-interop-brainstorm.md`, "Key Decisions #2": "each adapter runs in its own goroutine pool with panic recovery and circuit breakers."

**Severity:** P1 — Required to exit quality gate. The brainstorm describes panic recovery but does not describe what happens to the event that was being processed at panic time. The standard Go `defer recover()` pattern restarts the goroutine (or re-initializes the adapter pool) but does not know about the event that triggered the panic. That event is silently lost.

**The Yasna parallel:**
The Vendidad's station-specific purification protocol restores the priest to valid ritual state — it does not restart the ceremony. The purification explicitly addresses "chapter continuity": which chapter of the 72-chapter Yasna was the station at when contamination occurred? The restored priest resumes from that chapter. Without this, purification is a no-op for ceremony validity — you have a clean priest who doesn't know what verse they're on.

**Concrete failure scenario:** The GitHub adapter is processing an issue-close event (beads bead `sylveste-bcok` has been merged, triggering a GitHub issue close). The adapter is mid-call to the GitHub API when it panics on a rate-limit response it didn't parse correctly. `defer recover()` fires, the goroutine restarts. The issue-close event is gone — it was in a local variable in the stack frame that panicked. The GitHub issue remains open. The bead is closed in beads but the corresponding GitHub issue stays open: persistent split state with no alert. The user discovers it manually when they check GitHub.

**Evidence:** The brainstorm specifies "panic recovery" as a feature but names it only in terms of isolation benefit ("a crashing Notion adapter doesn't take down GitHub sync"). It does not address the recovery continuity question. The word "replay" does not appear in the document.

**Smallest fix:** Each adapter's event-processing goroutine should checkpoint the current event before processing:

```go
func (a *GitHubAdapter) processLoop(ctx context.Context) {
    var currentEvent *Event  // checkpoint slot
    defer func() {
        if r := recover(); r != nil {
            a.log.Error("panic in GitHub adapter", "event", currentEvent, "panic", r)
            if currentEvent != nil {
                a.bus.Requeue(*currentEvent)  // return event to bus for re-delivery
            }
            // restart processing loop
            go a.processLoop(ctx)
        }
    }()
    for event := range a.inbox {
        currentEvent = &event
        a.handle(event)
        currentEvent = nil
    }
}
```

This is a single-variable checkpoint. `bus.Requeue()` returns the event to the front of the adapter's inbox. No event store required. Cost: 1 variable + 1 method on EventBus + 1 line in the defer recovery block.

---

## ZYL-03 — `Event` Type Unspecified — No Compile-Time Typed Handoff Contracts (P1)

**Location:** `docs/brainstorms/2026-04-06-interop-brainstorm.md`, "Key Decisions #7": "each system implements a standard `Adapter` interface: `Start()`, `Stop()`, `HandleEvent(Event)`, `Emit() <-chan Event`."

**Severity:** P1 — The brainstorm specifies `HandleEvent(Event)` and `Emit() <-chan Event` but leaves `Event` unspecified. If `Event` is `interface{}` or a thin struct with an untyped `Payload interface{}` field, handoff contracts between adapters are enforced at runtime (type assertion) rather than compile time. A GitHub adapter emitting `GitHubIssueEvent` wrapped in a generic `Event.Payload` — and a beads adapter calling `payload.(BeadsIssueEvent)` — is a handoff contract enforced by string/type assertion, not by Go's type system.

**The Yasna parallel:**
The Yasna's handoff gestures are physically prescribed — the baresman bundle is passed with both hands at shoulder height, never underhand, never single-handed. There is no ambiguity about whether the correct implement was transferred correctly because the gesture is distinctive and physically constrained. A system where handoff is "pass an object and call it a baresman" with runtime checking is exactly the scenario the prescribed gesture prevents: a plausible-looking handoff that fails on type inspection.

**Concrete failure scenario:** The Notion adapter emits an event for a Notion property change that affects a database field. It wraps the payload as `NotionPropertyEvent{DatabaseID: ..., PropertyName: "Status", NewValue: "Done"}`. The beads adapter receives `HandleEvent(Event)`, type-asserts the payload as `BeadsStateEvent`, and the assertion fails. In the current brainstorm, the failure mode is unspecified — does `HandleEvent` return an error? Panic? Silently no-op? If it silently no-ops (common defensive Go pattern: `if payload, ok := e.Payload.(BeadsStateEvent); !ok { return }`), the Notion status change is silently dropped with no user-visible error. A "Done" in Notion does not close the bead.

**Evidence:** The `Adapter` interface in the brainstorm specifies `HandleEvent(Event)` but not the `Event` type structure. The brainstorm's architecture sketch shows all four adapters connected to the same event bus, implying they all consume from the same event stream — but with different capabilities for different event types. The routing mechanism (who delivers which events to which adapters) is not specified in the brainstorm.

**Smallest fix:** Define `Event` as a concrete typed struct with a typed `Payload` discriminated union, not `interface{}`:

```go
type EventType string

const (
    EventGitHubIssue    EventType = "github.issue"
    EventNotionPage     EventType = "notion.page"
    EventBeadsState     EventType = "beads.state"
    EventLocalFSChange  EventType = "localfs.change"
)

type Event struct {
    ID        string
    EntityID  string
    Type      EventType
    SourceAdapter AdapterID
    Timestamp time.Time
    Payload   EventPayload  // interface with typed implementations
}

type EventPayload interface {
    eventPayloadSeal()  // unexported method, prevents external implementation
}
```

Each adapter declares which `EventType`s it handles. The bus routes by `EventType` to specific adapter inboxes — typed channels `chan GitHubIssueEvent`, `chan NotionPageEvent`, etc. No cross-adapter type assertions at runtime. Cost: one `EventPayload` interface, one `EventType` const block, per-adapter typed inbox channels.

---

## ZYL-04 — Circuit Breaker Queuing Behavior Unspecified; Events May Be Dropped (P2)

**Location:** `docs/brainstorms/2026-04-06-interop-brainstorm.md`, "Key Decisions #2": "circuit breakers."

**Severity:** P2 — The brainstorm mentions circuit breakers as a fault-isolation mechanism but does not specify what happens to events that arrive while a circuit is open (adapter down). Standard circuit breaker implementations reject calls while open — which for an integration adapter means dropping events during the breaker's open window. Dropped events mean split state between systems during any adapter outage, however brief.

**The Yasna parallel:**
When the circuit breaker pattern is applied to the Yasna, it must distinguish between: (a) pausing the handoff queue at the failing station's input point (events accumulate at the handoff boundary, preserving order for when the station recovers) versus (b) skipping the station entirely and continuing the ceremony without it (events are dropped or rerouted, breaking sequential integrity). The Vendidad permits (a) — pause at the boundary — but prohibits (b) for implements that cannot be re-consecrated elsewhere.

**Evidence:** The brainstorm does not specify circuit breaker semantics. Go circuit breaker libraries (sony/gobreaker, afex/hystrix-go) default to fail-fast with no queuing when the circuit is open. Without explicit queue-on-open semantics, the default behavior drops events during the open window.

**Question (not assertion):** Does the circuit breaker implementation use queue-on-open semantics (events buffered at the adapter's inbox when the circuit is open, re-delivered when it closes)? Or does it use fail-fast semantics (events rejected during open state)? If fail-fast, what is the recovery mechanism for events rejected during an outage — are they re-fetched from the source system on circuit close?

**Smallest fix:** Add to the brainstorm's Open Questions: "Circuit breaker open-state queuing: buffer-and-replay vs. fail-fast with source re-fetch. Which adapters support re-fetch (GitHub, Notion — yes via API; beads — yes via `bd list`; local FS — no)? For local FS, queue-on-open is mandatory since there is no re-fetch path."

---

## ZYL-05 — Beads Adapter Handoff Contract Is Untyped Subprocess Stdout (P2)

**Location:** `docs/brainstorms/2026-04-06-interop-brainstorm.md`, "Key Decisions #6": "Beads access: via `bd` CLI only — consistent with ecosystem convention."

**Severity:** P2 — The Beads adapter's handoff contract is subprocess stdout from `bd` CLI invocations. This is not a typed Go interface — it is a text pipe whose schema is defined by `bd`'s output format, which can change across `bd` versions without a Go compile-time error. All other adapters have typed API responses (GitHub REST API, Notion REST API, fsnotify events) that can be marshaled into Go structs. The beads adapter has an untyped text interface.

**The Yasna parallel:**
The Yasna requires that ritual implements be physically identifiable — the baresman bundle must have a specific number of twigs bound in a specific direction. A "bundle that looks like a baresman" passed at the handoff point by verbal description (like untyped stdout parsing) creates a verification gap. The raspi at the receiving station cannot inspect whether the bundle meets the canonical specification at compile time — only at runtime, when the ceremony may already be in progress.

**Evidence:** The brainstorm explicitly states "Beads access: via `bd` CLI only." This is the ecosystem convention for agents and plugin scripts, but it creates a coupling to `bd`'s text output format that no other adapter has. If `bd` output changes (new field ordering, added fields, changed status strings), the Beads adapter fails at runtime, not at compile time.

**Question (not assertion):** Does the Beads adapter parse `bd` output with a versioned schema (e.g., `bd --json` output bound to a Go struct matching the current `bd` version)? Or does it use text scanning that is brittle to `bd` output changes? If the former, the risk is low; if the latter, this becomes a hidden coupling that will fail on `bd` upgrades.

**Smallest fix:** Specify that the Beads adapter uses `bd --json` output format exclusively (not plain text), and that the JSON schema is pinned to a versioned struct in `interop/adapters/beads/schema.go` updated on each `bd` version bump. One `BdJsonOutput` struct + JSON unmarshal call replaces all text parsing.

---

## Summary

| ID | Severity | Domain | Status |
|----|----------|--------|--------|
| ZYL-01 | P0 | Event bus contamination isolation | BLOCKING — pre-panic emits of semantically invalid events reach other adapters |
| ZYL-02 | P1 | Panic recovery continuity | BLOCKING — in-flight events at panic time are silently dropped with no replay |
| ZYL-03 | P1 | Typed handoff contracts | BLOCKING — `Event` type unspecified; runtime type assertion replaces compile-time contracts |
| ZYL-04 | P2 | Circuit breaker queuing | Important — open-state behavior unspecified; standard default drops events |
| ZYL-05 | P2 | Beads adapter handoff contract | Important — text pipe substrate vs. typed Go interface; brittle to `bd` output changes |

**Verdict: needs-revision** — two P1 structural gaps and one P0: the brainstorm's goroutine isolation provides crash isolation but not contamination isolation. The `Event` type must be defined with typed handoff contracts before the architecture is sound, and panic recovery must include in-flight event replay, not just goroutine restart.
