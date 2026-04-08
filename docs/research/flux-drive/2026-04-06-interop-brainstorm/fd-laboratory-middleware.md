---
agent: fd-laboratory-middleware
source_doc: docs/brainstorms/2026-04-06-interop-brainstorm.md
generated_at: 2026-04-06
lens: Clinical laboratory middleware — adapter translation fidelity, bidirectional correlation, schema versioning, uncorrelated event handling
---

# fd-laboratory-middleware — Review Findings

## Decision Lens

Does each adapter translate faithfully between the external system native protocol and the hub canonical event schema, the way laboratory middleware translates between instrument-native result formats and HL7 messages — with round-trip fidelity, schema version tracking, and field-level mapping audits?

---

## P0 Findings

### P0-1: Canonical Event type does not specify routing context — silent drops at FS adapter

**Finding:** The brainstorm defines an `Adapter` interface with `HandleEvent(Event)` but does not specify what fields the canonical `Event` type carries. The architecture supports bidirectional Notion ↔ local FS sync (Day-1 data flow #3). For an FS adapter to apply a Notion page update to the correct local file, the canonical event must carry a resolvable local file path (or a stable mapping key that the FS adapter can use to look up the path).

**Failure scenario:** A Notion page is updated. The Notion adapter creates a canonical event containing the Notion page ID and the updated content. The hub routes this event to the FS adapter. The FS adapter's `HandleEvent` implementation attempts to resolve the Notion page ID to a local file path via its mapping table. The Notion page was originally created outside interop (e.g., manually in Notion). No mapping entry exists. The FS adapter logs a warning and returns `nil` (no error — the adapter cannot return an error for an unmappable event without breaking the bus contract). The Notion update succeeds. The local file is not updated. No dead-letter entry is created. The two systems diverge silently.

**Condition:** When the canonical Event type does not carry enough routing context for every downstream adapter to resolve the target entity, and missing context causes silent drops rather than explicit errors routed to a dead-letter queue.

**Smallest viable fix:** The canonical `Event` struct must include a `RoutingHints` map (e.g., `map[string]string`) populated by the originating adapter with all known cross-system IDs for the entity (`notion_page_id`, `github_issue_number`, `local_file_path`, `bead_id`). If a downstream adapter cannot find the target entity *and* no routing hint for its system exists in the event, it must return an explicit `ErrUnresolvableTarget` — which the hub routes to a structured dead-letter queue rather than swallowing. This is the HL7 orphan result model: unresolvable results are held in a review queue, not silently discarded.

---

## P1 Findings

### P1-1: No canonical event schema versioning — silent incompatibility on adapter update

**Finding:** The brainstorm describes a `Adapter` interface with `Start()`, `Stop()`, `HandleEvent(Event)`, and `Emit() <-chan Event`. There is no `SchemaVersion()` method or schema version field in the Event type. The brainstorm mentions replacing interkasten but does not specify a schema migration strategy.

**Failure scenario:** The GitHub webhook payload schema changes (GitHub has changed webhook payload formats before, e.g., the `installation` context changes in GitHub Apps v3). The GitHub adapter is updated to parse the new format and emit a canonical event with renamed fields (`pr_merged` → `pull_request.merged`). The beads adapter, which maps `pr_merged` to a bead state transition, is not updated simultaneously — it is a separate goroutine pool and could be hot-reloaded independently. After the GitHub adapter update, the beads adapter silently ignores the `pull_request.merged` field (Go's JSON unmarshaling ignores unknown fields by default). GitHub PR-to-bead sync stops working. No error is raised. The bead state diverges from GitHub PR state until the beads adapter is also updated.

**Condition:** When canonical event schema changes are not versioned and adapters do not declare which schema version they consume, Go's permissive JSON unmarshaling creates silent incompatibilities between adapters updated at different times.

**Smallest viable fix:** Add `SchemaVersion int` to the canonical `Event` struct. Each adapter's `HandleEvent` implementation should check: if `event.SchemaVersion > adapter.MaxSupportedSchemaVersion`, return `ErrUnsupportedSchema` rather than attempting to parse. The hub routes `ErrUnsupportedSchema` events to the dead-letter queue with the version mismatch logged. This gives operators a visible signal rather than a silent state divergence. Laboratory middleware calls this "interface version mismatch" — it fails loudly so the instrument vendor can push a parser update.

---

## P2 Findings

### P2-1: No adapter translation contracts specified — field-level mapping is implicit

**Finding:** The brainstorm states each adapter implements `HandleEvent(Event)` but does not specify any formal translation contract — no document, struct tag, or test fixture that maps every field in a GitHub Issues webhook payload to a corresponding field in the canonical `Event` type and then to the beads bead schema.

**Risk:** Without a translation contract, fields can be silently dropped during translation (a GitHub issue body with embedded checkboxes, a Notion block with a custom property type, a beads state that has no GitHub label equivalent). Developers discover missing fields through user reports, not through automated round-trip tests. In laboratory middleware this class of bug causes result values to be lost in translation — the instrument reports a critical value, the middleware strips it as "unknown field," and the EMR never receives the critical alert.

**Suggested fix (P3 boundary):** For each adapter, create a `contracts/<adapter>_translation.go` table-driven test that: (a) takes a canonical fixture payload from the external system, (b) runs it through the adapter's parse function, (c) asserts every mapped field survives translation, and (d) round-trips the canonical event back through the adapter's emit function and asserts the re-serialized payload matches the original on all canonical fields. This is a test-time contract, not a runtime check — it does not add operational overhead.

### P2-2: No event debouncing — Notion block-level events flood beads

**Finding:** Notion's webhook API emits block-level events. A user editing a page body in Notion can generate dozens of `block.updated` events for a single keystroke. The brainstorm does not specify event debouncing or logical change aggregation in the Notion adapter.

**Failure scenario:** A developer rewrites a Notion page description (200 words) in a live editing session. The Notion adapter receives 150 `block.updated` events. Each is translated to a canonical `Event` and dispatched to the bus. The beads adapter processes each as an independent update, calling `bd update` 150 times for the same bead. The bead's event history contains 150 entries for one logical user action. `bd list` and `bd search` output is unsearchable for this bead. The beads Dolt DB grows proportionally.

**Smallest viable fix:** Add a per-entity debounce window (e.g., 2 seconds) to the Notion adapter's emit path. Accumulate block-level events for the same Notion page ID within the window, then emit a single `page.updated` canonical event carrying the final page state. This is the laboratory middleware calibration run model — aggregate instrument readings within a run, emit one result record per specimen rather than one per sensor ping.

### P2-3: Orphan events from unknown repositories/pages silently dropped

**Finding:** The brainstorm does not specify handling for events that arrive from external systems that have no configured mapping. A GitHub webhook from a repository not in the interop config, or a Notion page update from a database not in the adapter's mapping table, will arrive at the adapter's `HandleEvent` and have no processing path.

**Risk:** If the adapter returns `nil` for unmapped entities (the path of least resistance in Go), these events disappear silently. Operators have no visibility into what the daemon is ignoring. In laboratory middleware, orphan results (results with no matching order) are held in a dedicated review queue so a lab technician can investigate and correlate manually.

**Smallest viable fix:** When `HandleEvent` receives an event for an entity with no configured mapping, write a structured entry to the per-adapter orphan queue (append-only log file, rotated daily): `{timestamp, adapter, entity_type, external_id, payload_hash}`. Expose an MCP tool `interop_orphan_list(adapter, since)` so Claude Code sessions can inspect what the daemon has been silently ignoring. This is a one-function addition to the adapter error path and a single MCP handler.

---

## Summary

The laboratory middleware lens surfaces three structural gaps in the interop brainstorm that will produce silent data loss in production:

1. **Missing routing context in canonical Event** — the FS adapter (and any future adapter) cannot resolve target entities without cross-system ID hints in the event envelope; unresolvable events must fail explicitly, not silently
2. **No schema versioning** — Go's permissive JSON unmarshaling means an adapter schema change is invisible at runtime; version-mismatch events must dead-letter rather than apply with wrong field mapping
3. **No translation contracts** — without round-trip fidelity tests per adapter, field-level loss is discovered by users, not by CI

The Notion block-level debouncing gap (P2-2) is operationally important for the Notion ↔ beads sync path specifically, given the project's heavy Notion usage documented in memory.
