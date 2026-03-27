---
agent: fd-architecture
status: NEEDS_ATTENTION
findings: 5
---

# EventEnvelope v2 — Architecture Review

**Plan:** `/home/mk/projects/Sylveste/docs/plans/2026-03-26-event-envelope-v2.md`
**Bead:** Sylveste-og7m.2.1
**Reviewer:** flux-drive

---

## Finding 1: v1 fallback silently drops seven fields with no reader contract

**Severity:** P1

The v1-to-v2 mapping in `ParseEnvelopeV2JSON` projects only four fields onto `EventEnvelopeV2` (TraceID, SpanID, ParentSpanID, CallerIdentity). The existing `EventEnvelope` in `/home/mk/projects/Sylveste/core/intercore/internal/event/envelope.go` carries seven additional fields that are live in production data:

- `PolicyVersion` — written by all three default envelope constructors (`dispatch-lifecycle/v2`, `phase-machine/v1`, `coordination/v1`)
- `CapabilityScope` — written for every run-scoped and dispatch-scoped event
- `InputArtifactRefs` / `OutputArtifactRefs` — written for every phase advance and coordination lock
- `RequestedSandbox` / `EffectiveSandbox` — written by `defaultDispatchEnvelope` from a live SQLite query

The plan acknowledges this with a comment ("v1 source-specific data is not migrated into Payload") but offers no reader contract: what should code reading `Version=1` do when it needs `PolicyVersion` or `CapabilityScope`? The plan's guidance is "use the Event's top-level fields for source context," but those top-level fields (`from_state`, `to_state`) contain phase names and status strings, not `CapabilityScope` or `PolicyVersion`.

Concretely, `RequestedSandbox` and `EffectiveSandbox` are already modeled in `DispatchPayload` in v2 — meaning v2 carries them in the typed payload, but a v1 envelope parsed through the fallback loses them entirely with no way for the caller to recover them without re-querying SQLite. This is a silent data loss path, not an acknowledged migration gap.

**Smallest fix:** Either map all seven fields onto `EventEnvelopeV2` top-level fields (making `PolicyVersion`, `CapabilityScope`, `InputArtifactRefs`, `OutputArtifactRefs`, `RequestedSandbox`, `EffectiveSandbox` first-class fields of the v2 struct) or document explicitly in the plan — as a requirement, not a comment — which fields are intentionally dropped and which downstream consumers are already confirmed to not need them. If `RequestedSandbox`/`EffectiveSandbox` are needed from v1 envelopes, they must be surfaced somewhere callers can reach without re-querying.

---

## Finding 2: `phaseEventEnvelope` is a private shadow type that will diverge from both v1 and v2

**Severity:** P2

`/home/mk/projects/Sylveste/core/intercore/internal/phase/event_envelope.go` contains `phaseEventEnvelope`, a private struct that duplicates all fields of `EventEnvelope` except `RequestedSandbox` and `EffectiveSandbox`. It is serialized independently and stored in `phase_events.envelope_json`. The v2 plan does not mention this type.

After og7m.2.1 lands, the codebase will have three separate envelope representations in the `internal/event/` package boundary:

1. `EventEnvelope` (v1 canonical, `envelope.go`)
2. `EventEnvelopeV2` (v2 canonical, `envelope_v2.go`)
3. `phaseEventEnvelope` (private, `phase/event_envelope.go`)

`phaseEventEnvelope` does not use `MarshalEnvelopeJSON` — it marshals itself directly. This means phase events written to SQLite emit a structurally compatible but code-unlinked blob. `ParseEnvelopeV2JSON`'s v1 fallback will parse these correctly today only because the JSON field names happen to overlap. If `phaseEventEnvelope` is not eliminated and replaced by `EventEnvelope` (or eventually `EventEnvelopeV2`) as part of the migration, it becomes a third independent schema that can drift silently.

The plan for og7m.2.2 (writer changes) should address this, but og7m.2.1 should at minimum document `phaseEventEnvelope` as a known divergence requiring consolidation, so it does not persist past the migration window.

**Smallest fix:** Add a `// TODO(og7m.2.2): replace with event.EventEnvelope` comment on `phaseEventEnvelope` in the plan, and include elimination of `phaseEventEnvelope` in og7m.2.2's scope. No code change required in this bead.

---

## Finding 3: Payload types duplicate fields already present in `Event` top-level; discriminator is absent

**Severity:** P2

The plan's typed payload structs replicate information the `Event` struct already carries at the top level:

- `PhasePayload.FromPhase` / `ToPhase` mirrors `Event.FromState` / `Event.ToState` for `Source == "phase"`
- `DispatchPayload.FromStatus` / `ToStatus` mirrors `Event.FromState` / `Event.ToState` for `Source == "dispatch"`
- `CoordinationPayload.LockID` mirrors the `from_state` / `to_state` pattern already used by coordination events in the `scanEvents` SQL in `store.go`

The design intent appears to be that `Payload` carries the fields that do not fit in the flat `Event` structure (e.g., `DispatchID`, `RequestedSandbox`, `EffectiveSandbox`, `LockID`, `Scope`). But as specified, a caller reading a v2 envelope cannot determine which payload type to use without consulting `Event.Source`, which is outside the envelope. `ParsePayload[T]` is a generic that requires the caller to already know the right `T` — there is no discriminator field inside the payload or the envelope itself that routes to the correct type.

This is not inherently wrong (the caller always has `Event.Source`), but the plan does not state this contract, and the schema generated for `event-envelope-v2.json` will describe `payload` as `json.RawMessage` with no subtype linkage. External consumers (Interspect, Interverse plugins) parsing the contract schema will have no machine-readable way to know which payload type applies per source.

**Smallest fix:** Add a `source` field to `EventEnvelopeV2` (mirroring `Event.Source`) or document in `contracts/events/README.md` that payload type selection requires reading `Event.Source`. The schema should reference the three payload schemas from the envelope schema using a `oneOf` annotation so contract consumers have a complete picture.

---

## Finding 4: `MarshalEnvelopeV2JSON` mutates the caller's struct via pointer side-effect

**Severity:** P2

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

The function modifies the `Version` field of the caller's struct as a side effect of serialization. This breaks the principle that marshal functions are pure: a caller passing `e` with `Version == 0` will find `e.Version == 2` after the call, which is surprising and makes behavior in concurrent or test contexts unpredictable. The existing v1 `MarshalEnvelopeJSON` in `envelope.go` does not mutate its argument.

This also creates a state dependency: calling `MarshalEnvelopeV2JSON` twice on the same struct the second time applies `Version = 2` redundantly but not harmfully — the subtle risk is that code inspecting `e.Version` before and after a marshal call will see different values.

**Smallest fix:** Replace the mutation with a local copy:

```go
out := *e
if out.Version == 0 {
    out.Version = 2
}
b, err := json.Marshal(out)
```

This is a one-line change with no API surface impact.

---

## Finding 5: Contract registry adds four new entries but the generation pipeline produces a single file per entry with no v2 envelope linking payload schemas

**Severity:** P3

The plan adds four entries to `EventContracts` in `registry.go`:

```go
{Name: "event-envelope-v2", Instance: event.EventEnvelopeV2{}},
{Name: "phase-payload", Instance: event.PhasePayload{}},
{Name: "dispatch-payload", Instance: event.DispatchPayload{}},
{Name: "coordination-payload", Instance: event.CoordinationPayload{}},
```

The `GenerateSchemas` function in `generate.go` calls `r.Reflect(ct.Instance)` with `DoNotReference: true` for each entry independently. This means `event-envelope-v2.json` will describe `payload` as `{"type": "string", "contentEncoding": "base64"}` (the default `json.RawMessage` schema) — it will not reference `phase-payload.json`, `dispatch-payload.json`, or `coordination-payload.json`. The four schemas are generated as independent files with no structural link.

This is a limitation of the reflector, not a bug in the plan, but it becomes a problem when the schema is consumed by external systems (Interspect's `review_events` schema validator, any Interverse plugin reading the event bus). The generated schema will be technically valid but structurally incomplete.

The plan's verify step only checks `grep '"v"' contracts/events/event-envelope-v2.json` — it does not verify that the payload type schemas are reachable from the envelope schema.

**Smallest fix:** Either (a) use a `jsonschema` schema override in `contracts/overrides/` (if that directory follows the existing pattern) to inject a `oneOf` referencing the three payload schemas, or (b) add an explicit note in `contracts/events/README.md` that the four schemas form a group and must be read together. If override injection is not yet supported by the pipeline, document it as a known gap in the README and add a verify step that confirms the three payload schemas exist and parse correctly.

---

## Summary

| # | Title | Severity | Required for this bead |
|---|-------|----------|------------------------|
| 1 | v1 fallback silently drops seven live fields | P1 | Yes — needs explicit contract or full field mapping |
| 2 | `phaseEventEnvelope` shadow type unaddressed | P2 | Plan note + og7m.2.2 scope addition |
| 3 | Payload type discriminator absent from envelope | P2 | README contract or `source` field |
| 4 | `MarshalEnvelopeV2JSON` mutates caller's struct | P2 | One-line fix before implementation |
| 5 | Generated schemas are structurally unlinked | P3 | README gap note + verify step |

Findings 1, 3, and 4 are blocking implementation correctness. Finding 2 is a scope documentation issue that prevents technical debt from becoming invisible. Finding 5 is cleanup that should land before og7m.2.6.

<!-- flux-drive:complete -->
