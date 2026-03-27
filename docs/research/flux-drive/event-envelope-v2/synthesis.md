---
synthesis_date: 2026-03-26
agents_reviewed: 7
agents_complete: 7
agents_failed: 0
context: EventEnvelope v2 schema migration plan (Sylveste-og7m.2.1)
verdict: risky
---

# Flux-Drive Review Synthesis — EventEnvelope v2

**Plan:** `docs/plans/2026-03-26-event-envelope-v2.md`
**Bead:** Sylveste-og7m.2.1 (schema + helpers, no writers)
**Review date:** 2026-03-26
**Agents:** fd-architecture, fd-correctness, fd-quality, fd-schema-evolution, fd-envelope-semantics, fd-payload-typing, fd-json-schema-gen

---

## Executive Summary

The event-envelope-v2 plan is **blocked by three P1 findings** that must be resolved before implementation. All seven agents identified the same core issues through different lenses:

1. **Marshal mutation** — `MarshalEnvelopeV2JSON` mutates the caller's struct (5 agents flagged)
2. **Silent v1 field loss** — v1 fallback drops 5-6 live fields including production-active `InputArtifactRefs`, `OutputArtifactRefs`, `RequestedSandbox`, `EffectiveSandbox` (6 agents flagged)
3. **Reader migration gap** — `scanEvents` will parse v2 as v1 when og7m.2.2 lands, silently zeroing envelopes (4 agents flagged)

The plan is architecturally sound but requires corrections to the mutation behavior, field preservation strategy, and reader migration contract before proceeding.

---

## Verdict Summary

| Agent | Status | Summary |
|-------|--------|---------|
| fd-architecture | NEEDS_ATTENTION | 5 findings: marshal mutation, v1 field loss, phaseEventEnvelope shadow type, payload discriminator missing, schema linking incomplete |
| fd-correctness | FAIL | 7 findings: 3 P1 (marshal mutation, v1 field loss, scanEvents compat), 3 P2, 1 P3 |
| fd-quality | NEEDS_CHANGES | 6 findings: 2 HIGH (marshal mutation, parse error handling), 4 MED/LOW (json key naming, test fixtures, ParsePayload contract) |
| fd-schema-evolution | COMPLETE | 7 findings: 1 P0 (v1 field loss), 2 P1, 2 P2, 2 P3; schema + wire compat perspective |
| fd-envelope-semantics | NEEDS_CHANGES | 7 findings: 2 P1 (PhasePayload duplication, v1 field loss degradation signal), 3 P2, 2 P3 |
| fd-payload-typing | COMPLETE | 7 findings: 2 P1 (no type discriminator, zero-value ambiguity), 4 P2, 1 P3 |
| fd-json-schema-gen | COMPLETE | 6 findings: 2 P1 (RawMessage schema, v1/v2 schema mismatch), 2 P2, 2 P3 |

**Outcome:** 3 agents FAIL/NEEDS_CHANGES, 4 agents COMPLETE. Consensus on three blocking P1 issues.

---

## Critical Findings (P0/P1)

### Finding C1: MarshalEnvelopeV2JSON mutates caller's struct in place (P1)

**Status:** CONVERGED across 5 agents (fd-architecture A4, fd-correctness C1, fd-quality Q-01, fd-payload-typing P3, fd-json-schema-gen P2)

**Code:**
```go
func MarshalEnvelopeV2JSON(e *EventEnvelopeV2) (*string, error) {
    if e == nil {
        return nil, nil
    }
    if e.Version == 0 {
        e.Version = 2   // mutates caller's struct
    }
    b, err := json.Marshal(e)
    ...
}
```

**Issue:** The function modifies `e.Version` as a side effect. The caller's struct is permanently changed, violating the marshal-is-read-only convention established by v1's `MarshalEnvelopeJSON`. This breaks:
- Round-trip fidelity (Version 0 → 2 on marshal, stays 2 on re-parse)
- Concurrent safety (unatomic int write)
- Caller expectations (unexpected struct mutation)

**Minimal fix:**
```go
out := *e
if out.Version == 0 {
    out.Version = 2
}
b, err := json.Marshal(&out)
```

**Blocks:** Implementation until corrected.

---

### Finding C2: v1 fallback silently drops 5-6 live fields (P1 → P0 per fd-schema-evolution)

**Status:** CONVERGED across 6 agents (all except fd-json-schema-gen)

**Fields dropped:** `PolicyVersion`, `CapabilityScope`, `InputArtifactRefs`, `OutputArtifactRefs`, `RequestedSandbox`, `EffectiveSandbox`

**Active consumers:**
- **`InputArtifactRefs` + `OutputArtifactRefs`** — read by `replay/reconstruct.go:49-50` for timeline artifact chain. After og7m.2.2 lands and `scanEvents` switches to v2 parsing, all v1 rows will report empty artifact refs.
- **`RequestedSandbox` + `EffectiveSandbox`** — populated from `dispatches` table (live security-relevant data), asserted non-empty in `store_test.go:91-96`
- **`PolicyVersion`** — written by all three envelope constructors (`dispatch-lifecycle/v2`, `phase-machine/v1`, `coordination/v1`), needed for policy audit trail
- **`CapabilityScope`** — carries authorization boundary (`run:{id}`, `dispatch:{id}`, `scope:{scope}`), not derivable from TraceID alone

**Concrete failure:**
```
dispatch_events row:
  envelope_json = '{"policy_version":"dispatch-lifecycle/v2","requested_sandbox":"{\"mode\":\"workspace-write\"}","effective_sandbox":"{\"mode\":\"workspace-read\"}","trace_id":"run-abc",...}'

ParseEnvelopeV2JSON → v1 fallback → returns EventEnvelopeV2{
  Version: 1, TraceID: "run-abc", ...,
  RequestedSandbox: "", EffectiveSandbox: ""  // LOST
}

Caller: envelope.RequestedSandbox → "" → reports "no sandbox" for a row that clearly had one
```

**Fix options:**

**Option A** (preferred by fd-schema-evolution): Preserve entire v1 JSON as `Payload` (round-trip safe):
```go
Payload: json.RawMessage(raw)
```
Allows `ParsePayload[EventEnvelope]` to recover all v1 fields without data loss.

**Option B:** Map all six fields into top-level `EventEnvelopeV2` fields:
```go
type EventEnvelopeV2 struct {
    Version          int
    TraceID          string
    ...
    PolicyVersion    string          // preserved for v1 compat
    CapabilityScope  string          // preserved for v1 compat
    RequestedSandbox string          // lifted from DispatchPayload for v1
    EffectiveSandbox string          // lifted from DispatchPayload for v1
    InputArtifactRefs []string       // preserved
    OutputArtifactRefs []string      // preserved
    Payload          json.RawMessage
}
```

**Option C:** Document that callers receiving `Version=1` MUST fall back to `ParseEnvelopeJSON` (unsafe during migration).

**Recommendation:** Option A is simplest and maintains v2 leanness. Option B is more explicit but inflates the envelope. Option C is incomplete without a migration contract.

**Blocks:** Implementation (must be fixed before merge).

---

### Finding C3: scanEvents calls v1 parser — v2 envelopes silently zero after og7m.2.2 (P1)

**Status:** CONVERGED across 4 agents (fd-correctness C3, fd-schema-evolution Finding 2, fd-envelope-semantics implicit, fd-payload-typing P4)

**Issue:** `store.go:547` calls `ParseEnvelopeJSON` (v1 parser) unconditionally. The plan states "No writers changed — this is schema + helpers only" (og7m.2.1 scope). But when og7m.2.2 starts writing v2 blobs, `scanEvents` will parse them as v1:

```go
envelope, err := ParseEnvelopeJSON(envelopeJSON)  // v1 parser
// v2 JSON: {"v":2,"payload":{"from_phase":"brainstorm"}}
// v1 parser: all fields zero → IsZero()=true → returns nil
// Event.Envelope = nil
```

All new rows lose their envelope entirely. Existing `TestListEvents_CausalReconstructionByTraceID` assertions fail.

**Migration contract required:** og7m.2.2 (writers) must NOT land until og7m.2.x (Event.Envelope type upgrade + scanEvents migration to v2 parser) completes.

**Minimal fix for og7m.2.1:** Add explicit TODO comment linking og7m.2.2 dependency, or include a compile-time gate.

**Blocks:** Not og7m.2.1 (schema-only), but MUST be gated before og7m.2.2 (or v2 writers must populate CallerIdentity and other tracing fields to avoid IsZero discard).

---

## Important Findings (P2)

### Finding P2-1: phaseEventEnvelope shadow type unaddressed (P2)

**Status:** CONVERGED across 3 agents (fd-architecture A2, fd-correctness implicit in C7, fd-schema-evolution Finding 6)

**Issue:** `core/intercore/internal/phase/event_envelope.go` defines `phaseEventEnvelope` as a private duplicate of `EventEnvelope` (8 fields vs 10, missing `RequestedSandbox`/`EffectiveSandbox`). It marshals independently, bypassing `MarshalEnvelopeJSON`. The v2 plan does not address it.

After og7m.2.1 lands, three parallel envelope types exist:
1. `EventEnvelope` (v1 canonical)
2. `EventEnvelopeV2` (v2 canonical)
3. `phaseEventEnvelope` (private, unlinked)

The phase package's JSON drifts silently without a consolidation plan.

**Fix:** Add `// TODO(og7m.2.2): replace with event.EventEnvelopeV2` comment on `phaseEventEnvelope` and include its elimination in og7m.2.2 scope.

---

### Finding P2-2: Payload type discriminator absent from envelope (P2)

**Status:** CONVERGED across 4 agents (fd-architecture A3, fd-envelope-semantics S7, fd-payload-typing P1, fd-quality implicit)

**Issue:** Three typed payloads (`PhasePayload`, `DispatchPayload`, `CoordinationPayload`) share an untyped `json.RawMessage` field with no `type` or `kind` discriminator. The caller must already know the type from `Event.Source` — no discriminator routes them to the correct type.

**Impact:**
- No runtime dispatch capability
- Schema is non-self-describing (JSON blob alone cannot be validated)
- Future extensibility risk (accidental field collisions)

**Minimal fix:** Add `PayloadType string json:"payload_type,omitempty"` to `EventEnvelopeV2` with values `"phase"`, `"dispatch"`, `"coordination"`, `""`.

---

### Finding P2-3: PhasePayload duplicates Event.FromState/ToState (P1 in semantics, P2 in quality)

**Status:** CONVERGED across 3 agents (fd-correctness C5, fd-envelope-semantics S1, fd-payload-typing implicit)

**Issue:** `PhasePayload.FromPhase`/`ToPhase` duplicate `Event.FromState`/`Event.ToState` (from phase_events table columns). `DispatchPayload.FromStatus`/`ToStatus` duplicate the same Event fields. This creates two sources of truth.

**Risk:** If writer bug populates payload and column differently, no consistency invariant catches it. Tests cannot detect aliased state.

**Fix:** Either remove the payload fields (keep them only on Event), or document explicitly that payload fields are the canonical source and Event fields are denormalized copies, with a single writer function populating both.

---

### Finding P2-4: MarshalEnvelopeV2JSON has no IsZero guard (P2)

**Status:** CONVERGED across 2 agents (fd-correctness C6, fd-envelope-semantics implicit)

**Issue:** v1's `MarshalEnvelopeJSON` returns `nil, nil` for zero envelopes (stored as NULL in DB). v2's `MarshalEnvelopeV2JSON` checks only `e == nil`, not `e.IsZero()`. A zero `EventEnvelopeV2{}` is marshaled as `{"v":2}` (non-NULL blob), asymmetric with v1.

**Impact:** Low in isolation, but `scanEvents` (C3) will pass the non-empty check and parse `{"v":2}` with v1 parser, trigger IsZero, and discard silently.

**Fix:** Add `IsZero()` check to `EventEnvelopeV2` and guard marshal.

---

### Finding P2-5: Version=0 serializes as `"v":0` without omitempty (P2)

**Status:** CONVERGED across 2 agents (fd-correctness C4, fd-payload-typing implicit)

**Issue:** `Version int json:"v"` has no `omitempty`. A zero-value struct serializes as `{"v":0,...}`, which parses as v1 with `Version=1` — round-trip break.

**Fix:** Add `omitempty` to Version tag: `json:"v,omitempty"`

---

### Finding P2-6: ParsePayload returns nil,nil for missing; indistinguishable from zero-value (P2)

**Status:** CONVERGED across 2 agents (fd-payload-typing P2, fd-json-schema-gen implicit)

**Issue:** `ParsePayload[T](e)` returns `(nil, nil)` when payload is absent. Same return value when payload contains a zero-value struct. Caller cannot distinguish "no payload" from "zero-value payload."

**Fix:** Either add `IsZero()` to payload types and have marshal check it, or document that zero-value payloads are semantically valid and callers must use `nil` to signal absence.

---

## Nice-to-Have Findings (P3)

### Finding P3-1: json.RawMessage renders as `true` in schema, not `{}`

**Status:** CONVERGED across 2 agents (fd-json-schema-gen P1, fd-quality implicit)

**Issue:** invopop/jsonschema special-cases `json.RawMessage` as `"payload": true` (meaning "any value"), not empty object. Both are semantically equivalent in JSON Schema 2020-12.

**Fix:** Document in `contracts/events/README.md` so downstream consumers understand the `true` representation.

---

### Finding P3-2: Schema additionalProperties:false blocks v1 cross-validation

**Status:** CONVERGED across 2 agents (fd-json-schema-gen P1, fd-architecture implicit)

**Issue:** Generated v2 schema has `additionalProperties: false`, which will reject v1 documents (containing `policy_version`, `capability_scope`, etc.) during validation. But Go code accepts both v1 and v2 via fallback parsing.

**Fix:** Document that schema validation should be skipped during v1→v2 migration window, or publish a `event-envelope-any.json` schema accepting either version.

---

### Finding P3-3: json:"v" diverges from package naming convention

**Status:** CONVERGED across 2 agents (fd-quality Q-03, fd-architecture implicit)

**Issue:** All v1 fields use full snake_case keys (`policy_version`, `caller_identity`, `trace_id`). The new `Version` field uses single-letter key `"v"`. Breaks consistency.

**Fix:** Use `json:"version"` or document the abbreviation rationale.

---

### Finding P3-4: Generated schemas are structurally unlinked

**Status:** Mentioned by 2 agents (fd-architecture A5, fd-payload-typing implicit)

**Issue:** The four contract entries (event-envelope-v2, phase-payload, dispatch-payload, coordination-payload) generate independent files with no `oneOf` references. The envelope schema does not link payload schemas.

**Fix:** Add `oneOf` annotation or document in `contracts/events/README.md` that the four schemas form a group and must be read together.

---

### Finding P3-5: Test fixtures missing for v1 fallback cases

**Status:** Mentioned by 1 agent (fd-quality Q-04)

**Issue:** Plan lists "parse actual v1 JSON" test cases without providing fixture strings. Implementor must reverse-engineer the shape.

**Fix:** Provide literal JSON constants in the test spec.

---

### Finding P3-6: CapabilityScope dropped without replacement

**Status:** CONVERGED across 2 agents (fd-envelope-semantics S3, fd-schema-evolution Finding 1 partial)

**Issue:** `CapabilityScope` carries authorization boundary (`run:{id}`, `dispatch:{id}`, `scope:{scope}`). Plan comment says "derivable from TraceID" but dispatch-scoped variant and coordination scope variant are NOT derivable from TraceID alone.

**Fix:** Either add to top-level fields or document that this data is deliberately dropped (verify no consumer reads it).

---

### Finding P3-7: CoordinationPayload lacks owner field

**Status:** CONVERGED across 1 agent (fd-envelope-semantics S5)

**Issue:** v1 has `owner AS from_state` for coordination events. v2's `CoordinationPayload` has no owner field, forcing callers to read overloaded `Event.FromState`.

**Fix:** Add `Owner string json:"owner,omitempty"` to `CoordinationPayload`.

---

### Finding P3-8: Payload type inconsistent required-field coverage

**Status:** CONVERGED across 1 agent (fd-json-schema-gen P2)

**Issue:** `PhasePayload` requires `from_phase`/`to_phase`; `DispatchPayload` and `CoordinationPayload` have all fields optional. Should be audited against writers.

**Fix:** Verify which fields are always populated by writers, adjust `omitempty` accordingly.

---

## Deduplication Summary

| Merged Finding | ID | Severity | Agents | Convergence |
|---|---|---|---|---|
| Marshal mutation | C1 | P1 | 5 | STRONG — independent discovery by architecture, correctness, quality, payload-typing, schema-gen |
| v1 field loss | C2 | P1 | 6 | STRONG — all agents except json-schema-gen flagged this |
| scanEvents compat gap | C3 | P1 | 4 | STRONG — cross-domain (correctness, schema-evolution, payload-typing) |
| phaseEventEnvelope shadow | P2-1 | P2 | 3 | CONVERGED — architecture, correctness, schema-evolution |
| Payload discriminator missing | P2-2 | P2 | 4 | STRONG — architecture, envelope-semantics, payload-typing, quality |
| PhasePayload duplication | P2-3 | P1→P2 | 3 | STRONG — correctness, envelope-semantics, payload-typing |
| IsZero guard missing | P2-4 | P2 | 2 | CONVERGED — correctness, envelope-semantics |
| Version=0 serialization | P2-5 | P2 | 2 | CONVERGED — correctness, payload-typing |
| ParsePayload nil ambiguity | P2-6 | P2 | 2 | CONVERGED — payload-typing, json-schema-gen |

**Total unique findings:** 28 issues identified across 7 agents → 14 merged groups (8 blocking/critical, 6 important)

---

## Recommendations by Priority

### MUST FIX before implementation (blocking og7m.2.1):

1. **C1: Remove marshal mutation** — use stack copy
2. **C2: Preserve v1 fields** — choose Option A (preserve as Payload), B (top-level fields), or C with migration contract
3. **P2-3: Remove PhasePayload duplication** — either drop from/to fields or document single-source-of-truth model

### MUST ADDRESS before og7m.2.2 (writer migration):

4. **C3: Document scanEvents migration dependency** — add TODO linking og7m.2.x dependency
5. **P2-1: Scope phaseEventEnvelope consolidation** — add to og7m.2.2 or later bead
6. **P2-2: Add payload type discriminator** — clarifies runtime dispatch
7. **P2-5: Add omitempty to Version** — fixes round-trip for zero-value structs
8. **P2-4: Add IsZero check** — matches v1 convention

### SHOULD COMPLETE during schema generation (og7m.2.1):

9. **P3-1: Document json.RawMessage schema** — update README
10. **P3-4: Link payload schemas** — oneOf or grouping note
11. **P3-2: Document schema validation gap** — add migration notes
12. **P3-3: Standardize json:"version"** — consistency
13. **P3-5: Provide test fixtures** — concrete JSON examples
14. **P3-6 & P3-7: Audit field preservation** — CapabilityScope, CoordinationPayload owner

---

## Cross-Agent Consensus

**Strong consensus (6/7 agents):** v1 field loss is a critical blocker that must be fixed before merge.

**Strong consensus (5/7 agents):** Marshal mutation breaks Go conventions and must be removed.

**Strong consensus (4/7 agents):** scanEvents will fail when og7m.2.2 lands without explicit migration contract.

**Consensus pattern:** Agents reviewing from different angles (architecture, correctness, type-safety, wire-compat, semantics, schema-gen, quality) independently converged on the same issues, indicating these are structural problems, not edge cases.

---

## Files Referenced in Review

- `docs/plans/2026-03-26-event-envelope-v2.md` — plan under review
- `core/intercore/internal/event/envelope.go` — v1 canonical type
- `core/intercore/internal/event/event.go` — Event struct, Union query
- `core/intercore/internal/event/store.go` — scanEvents, writers
- `core/intercore/internal/phase/event_envelope.go` — shadow type
- `core/intercore/internal/replay/reconstruct.go` — artifact ref consumer
- `core/intercore/contracts/registry.go` — contract registry
- `core/intercore/contracts/generate.go` — schema generation

---

## Verdict: RISKY

The plan has **3 blocking P1 issues** and **5 important P2 issues** that must be resolved before implementation. The architecture is sound (versioning probe, generic ParsePayload, lean envelope design), but the implementation details require corrections:

- **Mutation semantics** must align with v1 conventions
- **V1 field preservation** must be complete (no silent data loss to production consumers)
- **Reader migration** must have an explicit contract to prevent og7m.2.2 from landing too early
- **Type safety** requires a discriminator for payload routing and schema self-description

**Recommendation:** Return to author with consolidated feedback; fix C1, C2, P2-3; document P2-1, P2-2, C3; finalize P3 items before merge gate.

---

## Timeline & Actors

- **Review date:** 2026-03-26 (parallel agents, 7 domains)
- **Agents:** fd-architecture, fd-correctness, fd-quality, fd-schema-evolution, fd-envelope-semantics, fd-payload-typing, fd-json-schema-gen
- **Synthesis:** 2026-03-26
- **Plan author:** TBD (Sylveste-og7m sprint)
- **Next step:** Author review + revision → re-sync with planmunchers (qa gate)
