# fd-song-yizhan-postal-relay-routing Review: interop Integration Fabric Brainstorm

**Source:** `docs/brainstorms/2026-04-06-interop-brainstorm.md`
**Reviewed:** 2026-04-06
**Agent:** fd-song-yizhan-postal-relay-routing (Yicheng — event routing priority, bidirectional collision detection, SLA audit)
**Track:** D (Esoteric)
**Bead:** sylveste-bcok

---

## Findings Index

- P0 | SYP-01 | Architecture Sketch / Event Bus | No bidirectional collision detection (bingjuan): simultaneous opposing events on the same entity are processed independently, silently discarding one side
- P1 | SYP-02 | Architecture Sketch / Event Bus | No event priority classification: FIFO routing makes Notion webhook floods indistinguishable from beads state-change events
- P1 | SYP-03 | Key Decisions #3 / Deployment | No per-stage event timestamp (jianbu): no SLA audit trail for event processing latency across ingestion, routing, and adapter processing
- P2 | SYP-04 | Key Decisions #4 / Caddy Webhook Ingestion | No per-source admission control: single Caddy ingestion path allows one noisy source (Notion bulk update) to starve all other sources
- P2 | SYP-05 | Key Decisions #8 / Conflict Resolution | Last-write-wins conflict decisions produce no auditable hewen: resolution is opaque, cannot be diagnosed retroactively

---

## SYP-01 — No Bidirectional Collision Detection: Simultaneous Opposing Events Silently Discard One Side (P0)

**Location:** `docs/brainstorms/2026-04-06-interop-brainstorm.md`, "Architecture Sketch": single event bus (channels) routing to four adapter goroutine pools. "Key Decisions #3": "webhook-first (GitHub, Notion), fsnotify for local files."

**Severity:** P0 — All four Day-1 flows are bidirectional. This means at any moment, a user editing a Notion page and a collaborator editing the corresponding GitHub file will produce two simultaneous opposing events about the same logical entity: `Event{Type: "notion.page", EntityID: "page-xyz", Direction: outbound-to-github}` and `Event{Type: "github.file", EntityID: "page-xyz", Direction: outbound-to-notion}`. The event bus's single FIFO channel processes these independently. The second event processed overwrites the first event's sync. Neither user's changes are preserved in full. No user is notified.

**The Yizhan parallel:**
The bingjuan protocol arose from a structural problem in Song Dynasty administration that had no other solution: provincial memorials (flowing toward the capital) and imperial edicts (flowing toward the provinces) crossed paths constantly on the trunk routes. Without bingjuan, an edict ordering a governor's dismissal would arrive at his province while his memorial asking for a promotion was still en route to the capital. The relay station that processed them independently would complete both deliveries, producing a contradictory state: the governor receives his dismissal and promotion simultaneously. The bingjuan required the station master to detect the crossing, package both documents together, and forward them as a collision pair — the downstream resolver would see both and make a coherent decision.

**Concrete failure scenario:** A user opens a Notion page for bead `sylveste-bcok` at 14:30:00 and edits the description. Simultaneously (14:30:01), a CI run closes the corresponding GitHub issue. Notion webhook fires at 14:30:03 (Notion page updated). GitHub webhook fires at 14:30:02 (GitHub issue closed). Both events enter the event bus. GitHub event is processed first (arrived 1 second earlier): GitHub adapter closes beads bead `sylveste-bcok` and emits a "closed" state back to Notion adapter. Notion adapter then processes the Notion page-update event: it updates the GitHub issue description — but the issue is now closed. GitHub update on a closed issue may succeed (description updates are allowed on closed issues) or fail depending on GitHub settings. Meanwhile, the Notion adapter's update overwrites the "closed" state field in Notion with the old "in_progress" description. Result: bead is closed in beads but Notion shows "in_progress" description with no "closed" status update.

**Evidence:** The brainstorm does not contain the words "collision," "concurrent," "simultaneous," "opposing," or "bingjuan." The concept of two adapters emitting events about the same entity within the same time window is not addressed.

**Smallest fix:** Add a collision detection window to the event bus. Before dispatching an outbound event, check the event bus's recent-events ring buffer for an opposing event on the same `EntityID` within a configurable window (default: 5 seconds):

```go
// bus.go
type CollisionWindow struct {
    mu      sync.Mutex
    recent  map[string]pendingEvent  // EntityID -> most recent event
    ttl     time.Duration            // default 5s
}

func (b *EventBus) detectCollision(incoming Event) (collision *Event, detected bool) {
    b.window.mu.Lock()
    defer b.window.mu.Unlock()
    if existing, ok := b.window.recent[incoming.EntityID]; ok {
        if existing.SourceAdapter != incoming.SourceAdapter {
            return &existing.Event, true  // opposing source = collision
        }
    }
    b.window.recent[incoming.EntityID] = pendingEvent{Event: incoming, at: time.Now()}
    return nil, false
}
```

On collision detected, route the pair to `ConflictResolver.ResolvePair(a, b Event)` instead of independent dispatch. The resolver logs the hewen (see SYP-05) and dispatches the merged result. Cost: one `CollisionWindow` struct (ring buffer with TTL eviction), one `detectCollision` call in the bus dispatch path, one `ResolvePair` method.

---

## SYP-02 — No Event Priority Classification: FIFO Routing Cannot Distinguish Urgency Classes (P1)

**Location:** `docs/brainstorms/2026-04-06-interop-brainstorm.md`, "Architecture Sketch": single "Event Bus (channels)" — implying a single FIFO channel. "Key Decisions #3": webhooks from GitHub and Notion both feed into this bus.

**Severity:** P1 — The brainstorm's event bus is described as "channels" (plural in the diagram legend) but the architecture sketch shows a single bus that all four adapters share. If the bus is a single `chan Event`, it is FIFO across all sources. A bulk Notion database export (200 page-updated webhooks in 30 seconds) queues ahead of a beads state-change event (bead closed, must sync to GitHub within seconds for CI pipeline purposes). The beads event waits behind 200 Notion events with no priority mechanism.

**The Yizhan parallel:**
The Song yizhan's three-tier urgency system (zuizhong — routine, jiji — urgent, feichuan — express/flying horse) was not an optimization — it was the system's core function. A relay network that could not distinguish an express imperial edict from a routine tax report would have been useless for administration. The entire investment in relay infrastructure (1,600+ stations, dedicated horse strings, station logs) was justified by the ability to guarantee SLA compliance by urgency class. A single FIFO queue destroys the system's primary value proposition.

**Concrete failure scenario:** A Notion workspace is being migrated: 500 pages are exported and re-imported, generating 500 `page.updated` webhook events in 2 minutes. All 500 enter the event bus. A bead is closed simultaneously (`sylveste-bcok`), generating one beads state-change event that should trigger a GitHub issue close within 30 seconds (a CI webhook listening for the GitHub close depends on it). The bead's state-change event is 501st in the FIFO queue. It processes after all 500 Notion events — approximately 3 minutes later, assuming 360ms per Notion event processing. The CI webhook times out at 60 seconds. The downstream CI pipeline stalls.

**Evidence:** The brainstorm specifies a single event bus with four adapter pools. No priority mechanism is mentioned. "Event Bus (channels)" in the architecture sketch uses parenthetical "(channels)" — implying a single Go channel or channel-based abstraction — with no mention of multiple priority lanes.

**Smallest fix:** Replace the single event bus channel with a priority-lane bus — three channels with a select dispatch loop that drains higher-priority lanes first:

```go
type PriorityBus struct {
    express  chan Event  // P0: beads state changes, explicit user actions
    urgent   chan Event  // P1: webhook events from primary sources
    routine  chan Event  // P2: bulk webhook storms, local FS fsnotify
}

func (b *PriorityBus) Dispatch(ctx context.Context, handler func(Event)) {
    for {
        select {
        case e := <-b.express:
            handler(e)
        default:
            select {
            case e := <-b.express:
                handler(e)
            case e := <-b.urgent:
                handler(e)
            default:
                select {
                case e := <-b.express:
                    handler(e)
                case e := <-b.urgent:
                    handler(e)
                case e := <-b.routine:
                    handler(e)
                }
            }
        }
    }
}
```

Each adapter assigns `Priority` to its emitted events at construction time. The webhook ingestion layer assigns incoming webhook events to `urgent` or `routine` based on source and payload size. Cost: three channels instead of one + the nested select dispatch pattern. This is idiomatic Go.

---

## SYP-03 — No Per-Stage Event Timestamp: No SLA Audit Trail (P1)

**Location:** `docs/brainstorms/2026-04-06-interop-brainstorm.md`, "Key Decisions #3": "webhook-first...polling as last resort." "Key Decisions #4": "Docker Compose alongside Auraken. Caddy reverse proxy for webhook ingestion."

**Severity:** P1 — The brainstorm does not specify any timestamp tracking for events as they move through the system. When a user reports "GitHub sync is slow," there is no mechanism to determine whether the delay is in: (1) Caddy webhook ingestion, (2) event bus queuing, (3) adapter goroutine pool processing, or (4) the external API call (GitHub/Notion rate limiting). Without per-stage timestamps, diagnosis is guesswork.

**The Yizhan parallel:**
The jianbu (station log) was the Song government's primary administrative accountability mechanism. Every document's arrival timestamp and departure timestamp at every station were recorded. The Censorate (imperial audit body) reviewed jianbu logs and impeached station masters who delayed documents beyond their urgency class threshold. The station log was not optional record-keeping — it was the mechanism by which the relay network proved it was functioning to specification. A relay network without station logs is a network that cannot be held accountable.

**Concrete failure scenario:** A user reports that a bead state change is not appearing in GitHub Issues for 10 minutes after the bead is closed. Without per-stage timestamps, the engineer investigating cannot determine whether the delay is in: the `bd` CLI subprocess call (beads adapter slow), the event bus queuing (backlog), the GitHub API rate limiting (external), or the Caddy webhook delivery path (irrelevant for beads-to-GitHub direction). They check each component manually in sequence — 30 minutes of investigation for a symptom that a jianbu log would have identified in 30 seconds.

**Evidence:** The brainstorm does not mention timestamps, latency, observability, or metrics anywhere in the document. The operational deployment section mentions "long-running daemon on zklw" but no monitoring strategy.

**Smallest fix:** Each `Event` struct should carry a `TracePoints` slice populated at each processing stage:

```go
type TracePoint struct {
    Stage     string    // "ingested", "bus_queued", "bus_dispatched", "adapter_received", "adapter_processed"
    At        time.Time
    AdapterID string
}

type Event struct {
    // ... existing fields
    TracePoints []TracePoint
}
```

Each component appends a `TracePoint` as the event passes through. On completion (or failure), the trace is written to a structured log (stdout JSON, consumed by the existing log aggregation). No separate metrics infrastructure required for Day-1 — structured log is sufficient for manual SLA audit. Cost: one struct + one append call per stage + one log write on event completion. The trace is forward-compatible with OpenTelemetry span export later.

---

## SYP-04 — No Per-Source Admission Control: Single Ingestion Path Enables Source Starvation (P2)

**Location:** `docs/brainstorms/2026-04-06-interop-brainstorm.md`, "Key Decisions #4": "Caddy reverse proxy for webhook ingestion."

**Severity:** P2 — The brainstorm specifies Caddy as the reverse proxy for webhook ingestion but does not specify per-source rate limiting or admission control. Caddy's default configuration accepts all connections from all sources. A GitHub webhook storm (bulk PR creation, repository events) or a Notion bulk update fills the event bus from one source while other sources (beads state changes, local FS events) cannot get their events processed.

**The Yizhan parallel:**
The Song relay system's physical architecture enforced per-urgency-class horse string separation: express horses were not shared with routine courier horses. A routine tax-report convoy could not commandeer the express horse string even if the express horses were idle. This physical separation guaranteed that express capacity was available for express documents regardless of routine traffic volume. Admission control at the relay station gate (a gatekeeper who checked urgency class before accepting documents into the station's queue) enforced the separation.

**Evidence:** Caddy's default `reverse_proxy` directive queues all requests from all upstream sources into a single connection pool. There is no Caddy module for per-source request rate limiting that would specifically throttle a single webhook source.

**Question (not assertion):** Does the brainstorm intend for Caddy to handle per-source admission control, or does the interop daemon itself handle it (after Caddy passes the request)? If interop handles it, the priority bus in SYP-02 provides the admission control at the event level. If Caddy handles it, the Caddy configuration must include per-source rate limits (Caddy's `rate_limit` module supports this).

**Smallest fix:** Specify that per-source admission control is handled at the interop daemon level, not at Caddy. The webhook ingestion handler (the HTTP handler that receives Caddy-forwarded webhooks) assigns events to the priority bus based on source and current queue depth:

```go
func (h *WebhookHandler) handleGitHub(w http.ResponseWriter, r *http.Request) {
    event := parseGitHubWebhook(r)
    priority := h.priorityFor(event)  // assigns routine vs urgent based on event type and current queue depth
    if err := h.bus.Enqueue(priority, event); err == ErrQueueFull {
        w.WriteHeader(http.StatusTooManyRequests)
        // GitHub will retry with exponential backoff
        return
    }
    w.WriteHeader(http.StatusOK)
}
```

Returning `429 Too Many Requests` to GitHub/Notion webhook delivery causes the source to retry later — this is the correct admission control mechanism for webhook sources, which are designed to handle retries. Cost: queue-depth check in the ingestion handler + `429` response path.

---

## SYP-05 — Last-Write-Wins Decisions Produce No Auditable Hewen (P2)

**Location:** `docs/brainstorms/2026-04-06-interop-brainstorm.md`, "Key Decisions #8": "last-write-wins for metadata, configurable per-adapter."

**Severity:** P2 — The brainstorm specifies last-write-wins as the metadata conflict resolution strategy. When last-write-wins fires, one side's value is discarded. There is no specification of an audit record (hewen) capturing what was discarded, when, by which adapter, and what the resolution produced. Without a hewen, there is no way to diagnose retroactively why an entity ended up in a particular state after a conflict.

**The Yizhan parallel:**
The hewen (reconciliation annotation) was the station master's record of what the collision contained and how it was resolved. When a bingjuan collision was packaged and forwarded, the hewen traveled with it: "Document A from Hangzhou (dated X) and Document B from Kaifeng (dated Y) arrived simultaneously at this station on date Z, addressed to the same administrative matter. Forwarded together per bingjuan protocol. Station master: [name]." Downstream stations and final recipients could audit the collision history. Without the hewen, the contradiction would arrive at the destination with no context for why two contradictory documents existed.

**Evidence:** The brainstorm specifies last-write-wins as a strategy but does not specify any audit record of conflict resolution decisions. The word "audit" does not appear in the document.

**Smallest fix:** When any conflict resolution decision fires (last-write-wins, three-way merge win), write a `ConflictRecord` to the `SyncJournal` (DHG-02):

```go
type ConflictRecord struct {
    EntityID      string
    ResolvedAt    time.Time
    Strategy      string     // "last-write-wins" | "three-way-merge" | "manual"
    WinnerSource  string     // adapter name
    LoserSource   string
    WinnerValue   string     // JSON-encoded
    LoserValue    string     // JSON-encoded — PRESERVED for audit, not discarded
    Reason        string     // "winner timestamp newer by 3s", etc.
}
```

The `LoserValue` is preserved in the audit log even though it is not applied. This is the hewen: a complete record of what was discarded and why. Cost: one struct + one append to `SyncJournal` per conflict resolution. The `SyncJournal` doubles as the reconciliation log from DHG-01/DHG-02.

---

## Summary

| ID | Severity | Domain | Status |
|----|----------|--------|--------|
| SYP-01 | P0 | Bidirectional collision detection | BLOCKING — simultaneous opposing events on same entity silently discard one side |
| SYP-02 | P1 | Event priority classification | BLOCKING — single FIFO bus; webhook storms starve state-change events |
| SYP-03 | P1 | Per-stage event timestamp / SLA audit | BLOCKING — no jianbu; latency diagnosis is guesswork; no observability path |
| SYP-04 | P2 | Per-source admission control | Important — Caddy with no source rate limiting; single noisy source starves others |
| SYP-05 | P2 | Conflict resolution audit record | Important — last-write-wins with no hewen; retroactive diagnosis impossible |

**Verdict: needs-revision** — one P0 and two P1 gaps in the event routing architecture. The brainstorm correctly identifies webhook-first as the right ingestion strategy but does not address what happens when bidirectional webhooks about the same entity arrive simultaneously — the most common scenario in an integration fabric. The collision window (SYP-01) and priority bus (SYP-02) are the two structural additions required before the routing architecture is sound.
