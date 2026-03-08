# Define canonical measurement read model and typed review event contract

**Bead:** iv-057uu
**Date:** 2026-03-08
**Status:** Brainstorm
**Discovered from:** iv-544dn (Research: Interspect event validity and outcome attribution)
**Builds on:** iv-w3ee6 (evidence lineage columns — just shipped)

## Problem

The intercore event surface has two gaps that prevent measurement consumers from getting a complete, typed view of review outcomes:

1. **No typed review event contract.** `contracts/events/` has `event.json` (generic bus shape) and `interspect-event.json` (correction events), but no `review-event.json`. The `ReviewEvent` Go struct exists in `internal/event/event.go` and is served by `ic events list-review`, but it's not registered in `contracts/registry.go` → `EventContracts`. Consumers have no schema to validate against.

2. **The "measurement read model" is implicit.** iv-544dn found that the unified event stream (`ListAllEvents`) includes review events but flattens them — `finding_id` → `from_state`, `resolution` → `to_state`, `agents_json` → `reason`, while `dismissal_reason`, `chosen_severity`, `impact`, `session_id`, `project_dir` are dropped. The actual measurement read model is "use `ListReviewEvents` for full fidelity" — but this is convention, not contract.

## Current State

### What exists

- **`ReviewEvent` Go struct** (`internal/event/event.go`) — full fidelity: id, run_id, finding_id, agents_json, resolution, dismissal_reason, chosen_severity, impact, session_id, project_dir, timestamp
- **`review_events` SQL table** (`migrations/024_review_events.sql`) — matching schema with indexes on finding_id and created_at
- **`ListReviewEvents()` store method** — cursor-paginated, returns `[]ReviewEvent`
- **`ic events list-review` CLI command** — exposes `ListReviewEvents` with `--since` and `--limit` flags
- **`ic events emit --source=review`** CLI command — writes review events with context JSON validation

### What's missing

- `review-event.json` contract in `contracts/events/`
- `ReviewEvent` registration in `EventContracts` array in `registry.go`
- Documentation of the canonical measurement read model (which streams to consume for what purpose)

### Consumers today

| Consumer | How it reads review events | Fidelity |
|---|---|---|
| Interspect (`_interspect_consume_review_events`) | `ic events list-review --since=N --limit=100` | Full (direct ReviewEvent JSON) |
| Generic `ic events tail` | UNION ALL bus | Lossy (fields dropped) |
| Autarch `EventsTail()` | Shells out to `ic events tail` | Lossy |

## Proposed Fix

### F1: Register ReviewEvent in contracts

Add `ReviewEvent` to `EventContracts` in `registry.go`:
```go
var EventContracts = []ContractType{
    {Name: "event", Instance: event.Event{}},
    {Name: "interspect-event", Instance: event.InterspectEvent{}},
    {Name: "event-envelope", Instance: event.EventEnvelope{}},
    {Name: "review-event", Instance: event.ReviewEvent{}},  // NEW
}
```

Then `go generate` produces `contracts/events/review-event.json` — the first-class typed contract.

### F2: Document the canonical measurement read model

Create `docs/contracts/measurement-read-model.md` (or a section in an existing doc) that explicitly states:

1. **Generic stream** (`ic events tail`, `ListAllEvents`): For lifecycle awareness (phases, dispatches, discoveries). Review events appear but are flattened — sufficient for "something happened" but not for scoring.

2. **Review events** (`ic events list-review`, `ListReviewEvents`): The canonical source for disagreement resolution analysis, agent scoring, and routing decisions. Full fidelity. Cursor-paginated via `--since`.

3. **Interspect events** (`ListInterspectEvents`): Manual corrections and override evidence. Currently NOT in the unified stream (separate query). Full fidelity.

4. **Measurement read model = generic stream + review events + interspect events.** Consumers that need correctness guarantees MUST use the typed APIs, not the lossy bus.

### F3: Run contract generation

After registering `ReviewEvent`, run `go generate ./contracts/...` (or the equivalent `go run contracts/cmd/gen/main.go`) to produce the JSON schema file. Verify it matches the ReviewEvent struct fields.

## What iv-w3ee6 already fixed

The evidence lineage work (just shipped) addressed the consumer side:
- Interspect now preserves `source_event_id` and `source_table` when ingesting review events
- `not_applicable` is no longer collapsed to `agent_wrong`
- `raw_override_reason` preserves the original dismissal signal

iv-057uu completes the producer side: making the source contract explicit.

## Scope boundary

**In scope:**
- Register ReviewEvent contract
- Generate JSON schema
- Document measurement read model
- Run tests (`go test ./...`)

**Out of scope (separate beads):**
- Adding interspect_events to the unified stream (separate design decision)
- Changing the UNION ALL projection to include more review fields (separate, and the typed API is the preferred path)
- Session ledger (iv-30zy3, already shipped)
- Landed change entity (iv-fo0rx, already shipped)

## Risks

- **None for existing consumers.** Adding a contract doesn't change behavior. The ReviewEvent struct is already public within the module.
- **Contract generation dependency.** Need `go generate` tooling to work. If the reflector can't handle ReviewEvent (unlikely — it's simpler than Dispatch), fall back to hand-writing the JSON schema.
- **Doc maintenance.** The measurement read model doc needs a home that people actually read. Recommend `core/intercore/docs/contracts/` alongside the JSON schemas.
