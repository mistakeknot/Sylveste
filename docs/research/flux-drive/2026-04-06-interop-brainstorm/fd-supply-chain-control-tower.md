---
agent: fd-supply-chain-control-tower
source_doc: docs/brainstorms/2026-04-06-interop-brainstorm.md
generated_at: 2026-04-06
lens: Supply chain control tower — authority hierarchy, golden record, full-sync reconciliation, in-flight state, field-level merge
---

# fd-supply-chain-control-tower — Review Findings

## Decision Lens

Does interop conflict resolution and bidirectional sync model handle concurrent edits across N external systems the way a supply chain control tower handles concurrent inventory updates across warehouses, carriers, and ERPs — with explicit conflict detection, master data authority hierarchy, and reconciliation audit trails rather than last-write-wins overwriting legitimate upstream changes?

---

## P0 Findings

### P0-1: Three-way merge operates on top-level state, not field-level — content overwrite on convergent state transitions

**Finding:** The brainstorm specifies "three-way merge for content (ported concept from interkasten), last-write-wins for metadata." It does not specify that conflict detection operates at the field level within the content tree. Standard three-way merge algorithms (git-style) check whether the same content block was modified by both sides — but the *merge condition* is checked at the state node, not at every leaf field.

**Failure scenario:** A beads bead is closed manually via `bd close` at 12:00:00. The bead's closure notes field is set to "Fixed in deploy 47." At 12:00:01, a GitHub issue is closed via the GitHub API by an automated workflow. The GitHub issue's close comment is "Auto-closed by release pipeline." Both events arrive at the interop hub within the same sync window. The three-way merge sees: base state = `open`, left = `closed` (bead), right = `closed` (GitHub). Both sides agree on `closed` — the merge algorithm classifies this as a non-conflicting convergent edit and applies the merge. The merge writes back GitHub's close comment (`Auto-closed by release pipeline`) to beads, overwriting `Fixed in deploy 47`. It writes beads' closure notes to the GitHub issue comment, which is a nonsensical GitHub API operation. The developer's carefully written closure notes are destroyed silently with no conflict alert.

**Condition:** When the three-way merge algorithm treats same-state convergence as conflict-free and does not check whether associated content fields are also identical, allowing field-level overwrite even when the top-level state merge succeeds.

**Smallest viable fix:** Extend the merge logic to run field-level comparison even on convergent state transitions: if `left.State == right.State` but `left.Fields != right.Fields`, classify as a content conflict and route to the dead-letter queue for operator review rather than applying a silent field overwrite. In Go terms, the merge function must accept a `FieldConflictPolicy` — `OverwriteOnConvergence` (current implicit behavior) vs. `DeadLetterOnFieldDivergence` (safe default). Supply chain control towers call this "same-status, different-attribute conflict" — two warehouses both mark a shipment "delivered" but with different delivery timestamps; the timestamp matters even when the status agrees.

---

## P1 Findings

### P1-1: Cursor-based reconnect misses offline changes — no full-sync reconciliation on adapter recovery

**Finding:** The brainstorm describes "event-driven hub" with "webhook-first" sync. Webhook-based systems maintain a cursor (last received event ID or timestamp) to resume after gaps. The brainstorm does not describe a full-sync reconciliation mode that runs on adapter reconnection to detect changes made during the offline window.

**Failure scenario:** The interop daemon is stopped for maintenance at 14:00. An operator makes 15 manual Notion page edits during the 14:00–15:30 maintenance window. These edits do not generate webhook deliveries (the webhook receiver is down). The daemon restarts at 15:30. The Notion adapter initializes with its last cursor (the last event ID from before 14:00). Notion's webhook API delivers events starting from the cursor. The 15 manual edits made during the maintenance window were not captured as webhook events — Notion's webhook system does not retroactively deliver events for changes made while the integration was offline (Notion's webhook model is fire-and-forget, not durable). The local FS copies of those 15 pages remain stale. No alert is raised. The operator does not know the sync is broken.

**Condition:** When adapter reconnection restores event streaming from the last cursor without checking whether manual changes were made to external systems during the offline window, and when there is no scheduled reconciliation to catch drift.

**Smallest viable fix:** On adapter startup (and on a configurable periodic schedule, e.g., every 6 hours), run a full-sync reconciliation: enumerate all entities from the external system, compare checksums against the locally cached version, and emit synthetic `entity.reconcile` events for any that have drifted. This is the supply chain full-inventory snapshot model — the event stream is the primary signal, but the periodic snapshot catches everything the event stream misses. For Notion specifically, this means paginating through all configured databases and comparing block checksums. Expensive but necessary.

---

## P2 Findings

### P2-1: No per-entity-type authority hierarchy for conflict resolution fallback

**Finding:** The brainstorm states "configurable per-adapter" conflict resolution. It does not specify whether there is a per-entity-type authority hierarchy for cases where automated merge fails.

**Risk:** When the three-way merge algorithm cannot resolve a conflict (both sides modified the same field with different values), the system needs a tiebreaker. "Configurable per-adapter" suggests the resolution is configured at the adapter level (e.g., "Notion wins over local FS"). But different entity types within the same adapter should have different authority semantics: beads is authoritative for work item status (not Notion), GitHub is authoritative for PR merge state (not beads), Notion is authoritative for page prose content (not GitHub). A single adapter-level authority setting cannot express this correctly.

**Suggested fix:** Define a `ConflictResolutionHierarchy` config section that maps entity type patterns to authority order:
```yaml
conflict_resolution:
  "bead.status": [beads, github, notion]
  "pr.merge_state": [github, beads]
  "page.content": [notion, local_fs]
  "*": [last_write_wins]
```
When automated merge fails, the hub walks the authority list and applies the first adapter's version. This is the ERP/WMS/TMS authority model — each data domain has a system of record.

### P2-2: Parallel adapter writes for new entities do not coordinate cross-system ID registration

**Finding:** The brainstorm describes multiple Day-1 data flows that require cross-system entity creation (beads bead → GitHub issue + Notion page). When a new bead is created, the hub may route the creation event to both the GitHub adapter and the Notion adapter concurrently. Each adapter creates its external entity and receives an external ID back. But the brainstorm does not specify how these external IDs are written back to the golden record atomically.

**Failure scenario:** A new bead is created. The hub dispatches the creation event to GitHub adapter and Notion adapter concurrently. GitHub creates the issue (ID: 4521) after 500ms. Notion creates the page (ID: `abc123`) after 2000ms. Meanwhile, at 800ms, a Notion webhook arrives for page `abc123` (Notion notifies as soon as the page is created). The hub processes this webhook. It tries to correlate `abc123` with a known bead. The bead's golden record was written at time 0 with `github_issue=4521` but `notion_page=nil` (the Notion write hasn't returned yet). Correlation fails. The webhook is dead-lettered. When the Notion write returns at 2000ms, `abc123` is written to the golden record. But the dead-lettered webhook is never replayed — the system has no mechanism to drain the dead-letter queue for events that failed due to timing.

**Smallest viable fix:** Entity creation must use a two-phase write: (1) reserve the entity in the golden record with a pending token (all external IDs null, status=`creating`), (2) dispatch creation events to all relevant adapters and collect all external IDs before setting status=`active`. Incoming events for entities in `creating` status are queued in a per-entity hold buffer (bounded, short TTL). This is the supply chain "shipment booking" model — a shipment is not visible to downstream systems until all party confirmations are collected.

### P2-3: In-flight entity state not surfaced to MCP layer

**Finding:** The brainstorm proposes an MCP server mode for Claude Code sessions. It does not specify whether MCP tools can query the in-flight state of cross-adapter operations.

**Risk:** When a Claude Code session asks "what is the current state of bead sylveste-bcok?", the MCP tool returns the locally cached state. If a GitHub webhook has arrived and is being processed (bead update in-flight, beads write pending), the MCP response reflects stale state. A Claude Code agent acting on this stale state (e.g., marking the bead as unresolved when GitHub already closed it) will create a conflicting write.

**Smallest viable fix:** The MCP `bead_get(id)` tool response should include an `in_flight` boolean and an `in_flight_operations` list describing pending cross-adapter operations. A Claude Code agent that receives `in_flight: true` should wait (poll with backoff) before writing. This requires the hub to maintain an in-flight operation registry keyed by entity ID — the same registry used for the P0-1 fix above.

---

## Summary

The supply chain lens reveals that the interop brainstorm's conflict resolution model has a critical gap at the field level: three-way merge on convergent state transitions silently overwrites content fields that were intentionally different in each system. This is the most operationally dangerous gap in the brainstorm because it is invisible — both systems end up in the same top-level state, so no conflict alert fires, and the lost content is only noticed when a human looks for their notes.

The three key additions the supply chain model demands:

1. **Field-level conflict detection on convergent state transitions** — same-status merges can still have content conflicts
2. **Full-sync reconciliation on adapter reconnect** — cursor-based resume cannot recover changes made during offline windows
3. **Golden record with two-phase entity creation** — parallel adapter writes for new entities must coordinate cross-system ID registration before the entity becomes visible to event routing
