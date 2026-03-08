# Plan: Canonical measurement read model and typed review event contract

**Bead:** iv-057uu
**Date:** 2026-03-08
**Brainstorm:** [docs/brainstorms/2026-03-08-canonical-measurement-read-model.md](../brainstorms/2026-03-08-canonical-measurement-read-model.md)

## Goal

Publish a first-class JSON Schema contract for ReviewEvent and document the canonical measurement read model. All changes in `core/intercore/`.

## Tasks

### T1: Register ReviewEvent in EventContracts
**File:** `core/intercore/contracts/registry.go`

- [x] Add to `EventContracts` array:
  ```go
  {Name: "review-event", Instance: event.ReviewEvent{}},
  ```

### T2: Generate JSON schema
**Dir:** `core/intercore/`

- [x] Run `go generate ./contracts/...` to produce `contracts/events/review-event.json`
- [x] Verify generated schema has all ReviewEvent fields: id, run_id, finding_id, agents_json, resolution, dismissal_reason, chosen_severity, impact, session_id, project_dir, timestamp

### T3: Document the measurement read model
**File:** `core/intercore/docs/measurement-read-model.md` (new)

- [x] Document the three event streams and when to use each:
  1. Generic stream (`ic events tail`) — lifecycle awareness, lossy for review fields
  2. Review events (`ic events list-review`) — canonical source for scoring/routing
  3. Interspect events (`ListInterspectEvents`) — manual corrections, not in unified stream
- [x] State explicitly: measurement read model = generic + review + interspect
- [x] List the fields dropped in generic projection vs full ReviewEvent
- [x] Reference the new `review-event.json` contract

### T4: Run tests
- [x] `go test ./...` in `core/intercore/` — verify contract generation passes
- [x] `go test ./contracts/...` — verify generate_test.go includes the new contract

## Execution Order

T1 → T2 → T3 → T4 (sequential — T2 depends on T1, T3 references T2 output)

## Risks

- **None for existing consumers.** Additive only — new contract file + doc.
- **Contract generation.** If the reflector chokes on ReviewEvent, hand-write the JSON schema (unlikely — struct is simpler than Dispatch).
