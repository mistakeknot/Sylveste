---
bead: Sylveste-og7m.2.1
type: brainstorm
---
# EventEnvelope v2 — Brainstorm

## Problem

The current `EventEnvelope` (v1) has structural issues that block pipeline unification:

1. **Duplicate type**: `phaseEventEnvelope` in `internal/phase/` duplicates 8/10 fields of `event.EventEnvelope` — missing `RequestedSandbox` and `EffectiveSandbox`. Phase events are marshaled with the local type, meaning they skip the shared `MarshalEnvelopeJSON`/`ParseEnvelopeJSON` path.

2. **Dead fields in some contexts**: `RequestedSandbox`/`EffectiveSandbox` are only populated for dispatch events (looked up from `dispatches` table). For phase, coordination, review, interspect, discovery, and intent events these are always empty strings — wasted schema surface.

3. **No schema version field**: When v2 changes envelope structure, readers have no way to distinguish v1 vs v2 payloads in the `envelope_json` column. This matters for migration.

4. **Semantic overloading**: `InputArtifactRefs`/`OutputArtifactRefs` are used for different purposes per source:
   - Phase: `["phase:brainstorm"]`, `["phase:planned"]` — state refs, not artifacts
   - Dispatch: `["spawned"]`, `["running"]` — status strings, not artifact refs
   - Coordination: `["*.go"]` (pattern), `["lock-123"]` (lock ID) — not artifacts at all

5. **No source-specific payload**: Each source crams its unique data into the generic fields. Coordination has lock_id/pattern/scope in separate columns, but envelope could carry structured payloads.

## Current Field Usage Matrix

| Field | Phase | Dispatch | Coordination | Review | Interspect | Discovery | Intent |
|-------|-------|----------|-------------|--------|------------|-----------|--------|
| PolicyVersion | ✓ "phase-machine/v1" | ✓ "dispatch-lifecycle/v2" | ✓ "coordination/v1" | — | — | — | — |
| CallerIdentity | ✓ "phase.store" | ✓ "dispatch.store" | ✓ "coordination.store" | — | — | — | — |
| CapabilityScope | ✓ "run:{id}" | ✓ "run:{id}" or "dispatch:{id}" | ✓ "scope:{scope}" | — | — | — | — |
| TraceID | ✓ runID | ✓ runID | ✓ runID or lockID | — | — | — | — |
| SpanID | ✓ generated | ✓ generated | ✓ generated | — | — | — | — |
| ParentSpanID | ✓ "phase-state:{from}" | ✓ from env | ✓ from env | — | — | — | — |
| InputArtifactRefs | ✓ phase ref | ✓ status ref | ✓ pattern ref | — | — | — | — |
| OutputArtifactRefs | ✓ phase ref | ✓ status ref | ✓ lock ref | — | — | — | — |
| RequestedSandbox | — | ✓ from dispatches | — | — | — | — | — |
| EffectiveSandbox | — | ✓ from dispatches | — | — | — | — | — |

**Key insight:** Only 3 of 7 sources populate envelopes at all. Review, interspect, discovery, and intent events have no envelope. The v2 design needs to serve the 3 active producers well and be extensible for the 4 inactive ones.

## Design Options

### Option A: Versioned envelope with source-typed payload

```go
type EventEnvelopeV2 struct {
    Version         int               `json:"v"`                          // 2
    TraceID         string            `json:"trace_id,omitempty"`
    SpanID          string            `json:"span_id,omitempty"`
    ParentSpanID    string            `json:"parent_span_id,omitempty"`
    CallerIdentity  string            `json:"caller_identity,omitempty"`
    Payload         json.RawMessage   `json:"payload,omitempty"`          // source-specific
}
```

- Drops: `PolicyVersion` (redundant with `Version`), `CapabilityScope` (derivable from TraceID), `InputArtifactRefs`/`OutputArtifactRefs` (overloaded), `RequestedSandbox`/`EffectiveSandbox` (dispatch-only → move to payload)
- Adds: `Version` field, `Payload` for source-specific data
- **Pro**: Clean, extensible, each source can define its own payload type
- **Con**: Readers need to know the source to interpret payload

### Option B: Minimal core + discriminated union

```go
type EventEnvelopeV2 struct {
    Version        int    `json:"v"`
    TraceID        string `json:"trace_id,omitempty"`
    SpanID         string `json:"span_id,omitempty"`
    ParentSpanID   string `json:"parent_span_id,omitempty"`
    CallerIdentity string `json:"caller_identity,omitempty"`
    // Source-specific (at most one non-nil)
    Phase          *PhaseEnvelopeData        `json:"phase,omitempty"`
    Dispatch       *DispatchEnvelopeData     `json:"dispatch,omitempty"`
    Coordination   *CoordinationEnvelopeData `json:"coordination,omitempty"`
}
```

- **Pro**: Typed per-source data, self-documenting, schema-visible
- **Con**: Envelope type grows with each source; `json.RawMessage` is simpler for rarely-used sources

### Option C: Keep flat, add version, prune dead fields

```go
type EventEnvelopeV2 struct {
    Version            int      `json:"v"`
    TraceID            string   `json:"trace_id,omitempty"`
    SpanID             string   `json:"span_id,omitempty"`
    ParentSpanID       string   `json:"parent_span_id,omitempty"`
    CallerIdentity     string   `json:"caller_identity,omitempty"`
    FromRef            string   `json:"from_ref,omitempty"`   // replaces InputArtifactRefs[0]
    ToRef              string   `json:"to_ref,omitempty"`     // replaces OutputArtifactRefs[0]
    RequestedSandbox   string   `json:"requested_sandbox,omitempty"`
    EffectiveSandbox   string   `json:"effective_sandbox,omitempty"`
}
```

- **Pro**: Simplest migration, flat schema, backward-compat easy
- **Con**: Still overloaded semantics on `FromRef`/`ToRef`, sandbox fields still dispatch-only

## Recommendation

**Option A** — versioned with `json.RawMessage` payload. Rationale:
- Only 3 sources use envelopes today; `Payload` lets each define what it needs
- `Version` field enables gradual migration (readers check `v` before parsing)
- Core tracing fields (trace/span/parent) are universal — keep them top-level
- `CallerIdentity` stays top-level for audit logs
- Dead fields (`PolicyVersion`, `CapabilityScope`, artifact ref arrays) dropped
- Dispatch sandbox data moves into `DispatchPayload` struct
- Phase state transitions move into `PhasePayload` struct
- `json.RawMessage` avoids growing the envelope type with every new source

## Migration Path

1. Add `Version` field to existing `EventEnvelope` (v1 compat: treat missing `v` as 1)
2. Create `EventEnvelopeV2` with new shape
3. Writers emit v2; readers handle both v1 and v2 (check `v` field)
4. After all writers migrated: drop v1 parsing (og7m.2.6 timeline)

## Scope for og7m.2.1

- Define `EventEnvelopeV2` struct in `internal/event/envelope.go`
- Define source payload types (`PhasePayload`, `DispatchPayload`, `CoordinationPayload`)
- Add `jsonschema` struct tags for schema generation
- Regenerate `contracts/events/event-envelope.json` (now reflects v2)
- Add `MarshalEnvelopeV2JSON` / `ParseEnvelopeV2JSON` with v1 fallback read
- Tests: round-trip marshal/parse for each source type, v1→v2 read compat
- Update `contracts/events/README.md` to document v2 shape

**NOT in scope**: changing writers to emit v2 (that's og7m.2.2), changing readers (og7m.2.5), removing v1 (og7m.2.6).
