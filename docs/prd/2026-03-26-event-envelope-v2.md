---
bead: Sylveste-og7m.2.1
type: prd
parent_epic: Sylveste-og7m.2
---
# PRD: EventEnvelope v2 Schema + JSON Schema Contract

## Problem Statement

The EventEnvelope (v1) blocks pipeline unification (og7m.2) because:
- Phase events use a duplicate local type (`phaseEventEnvelope`) that diverges from `event.EventEnvelope`
- 4 of 10 fields are dead or overloaded across sources (see brainstorm field matrix)
- No version discriminator prevents safe migration
- No extensible payload mechanism for source-specific data

## Target Users

- **Intercore event pipeline** — writes envelope JSON into `envelope_json` columns
- **Clavain sprint** — reads envelopes for causal tracing and audit
- **Skaffen** — will emit v2 envelopes after og7m.2.3
- **og7m.2.2** (unified stream API) — depends on v2 schema being defined

## Requirements

### Must Have
1. `EventEnvelopeV2` struct with `Version` field (v=2), core tracing fields, and `json.RawMessage` payload
2. Source payload types: `PhasePayload`, `DispatchPayload`, `CoordinationPayload`
3. `MarshalEnvelopeV2JSON` + `ParseEnvelopeV2JSON` with v1 read fallback
4. Regenerated `event-envelope.json` schema reflecting v2
5. Round-trip tests for each source payload type
6. v1→v2 backward compatibility: `ParseEnvelopeV2JSON` reads v1 envelopes without error

### Must NOT Have
- Writers emitting v2 (og7m.2.2 scope)
- Reader changes consuming v2 (og7m.2.5 scope)
- Removing v1 code (og7m.2.6 scope)
- Database schema changes (envelope is JSON blob in existing column)

### Nice to Have
- `jsonschema` struct tags on payload types for richer generated schemas
- `EnvelopeVersion()` helper that reads `v` without full parse

## Success Criteria

- `go generate ./contracts/...` produces `event-envelope.json` with `v` field and payload structure
- `ParseEnvelopeV2JSON(v1_json)` returns valid `EventEnvelopeV2` with `Version=1`
- All existing tests pass (no behavioral change — v1 paths unchanged)
- README.md documents v1→v2 migration guidance

## Technical Approach

**Option A selected** from brainstorm: versioned envelope with `json.RawMessage` payload.

Core tracing fields kept top-level (trace_id, span_id, parent_span_id, caller_identity). Source-specific data in typed payload structs marshaled into `Payload json.RawMessage`. Dead fields pruned: `PolicyVersion` (replaced by `Version`), `CapabilityScope` (derivable), `InputArtifactRefs`/`OutputArtifactRefs` (overloaded arrays replaced by source-specific fields in payloads).

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| v1 fallback parsing misses edge cases | Low | Medium | Table-driven tests with all 3 active source envelopes |
| `json.RawMessage` loses type safety | Medium | Low | Payload helper functions enforce types at write time |
| Schema generation doesn't reflect payload inner types | Medium | Low | Use `jsonschema:"oneof_type=..."` or document manually |
