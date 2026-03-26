---
artifact_type: flux-drive-review
reviewer: fd-payload-typing
plan: docs/plans/2026-03-26-event-envelope-v2.md
bead: Demarch-og7m.2.1
agent: claude-opus-4-6
status: complete
findings: 7
date: 2026-03-26
---

# Payload Typing Review — EventEnvelope v2

**Document:** `docs/plans/2026-03-26-event-envelope-v2.md`
**Existing code:** `core/intercore/internal/event/envelope.go`, `core/intercore/contracts/registry.go`
**Reviewer:** fd-payload-typing (Go type-system specialist)
**Focus:** Type key collisions, json.RawMessage two-phase decode correctness, receiver consistency, unknown-type error handling, zero-value vs missing payload distinguishability.

---

## Finding 1

**Severity: P1 — No type discriminator in payload; all three categories share an untyped json.RawMessage**

The plan defines three typed payload structs (`PhasePayload`, `DispatchPayload`, `CoordinationPayload`) but the `EventEnvelopeV2.Payload` field is a bare `json.RawMessage` with no `type` or `kind` discriminator key. There is no mechanism in the envelope to indicate which payload type the `Payload` field contains. The generic `ParsePayload[T]` function requires the caller to already know the concrete type at the call site.

This means:

1. **No runtime dispatch.** A consumer reading events from the unified `ListEvents` query cannot determine the payload type from the envelope alone. They must inspect `Event.Source` (a separate field on the outer `Event` struct, not on `EventEnvelopeV2`) and then manually select the correct generic instantiation. This coupling is implicit and undocumented in the plan.

2. **Collision by absence.** The three payload types use distinct JSON field names (`from_phase`/`to_phase`, `dispatch_id`/`from_status`/`to_status`, `lock_id`/`pattern`/`scope`), so they are de-facto distinguishable by key inspection. But this is an accident of current field naming, not a contract. A future payload type that reuses `pattern` or `scope` fields would be indistinguishable from `CoordinationPayload` without external context.

3. **Schema generation gap.** The JSON Schema for `event-envelope-v2.json` will emit `Payload` as `{"type": "object"}` (or a raw JSON value) with no `oneOf`/`anyOf` discriminator. Schema consumers (validation, documentation generators) cannot validate payload contents.

**Recommendation:** Add a `payload_type` string field to `EventEnvelopeV2` (values: `"phase"`, `"dispatch"`, `"coordination"`, `""`). This enables runtime dispatch without requiring callers to cross-reference `Event.Source`, makes the schema self-describing, and prevents future collisions. The `ParsePayload[T]` generic can remain for type-safe extraction, but the discriminator provides the routing signal.

---

## Finding 2

**Severity: P1 — ParsePayload returns nil, nil for missing payload; indistinguishable from zero-value struct**

`ParsePayload[T]` (line 168-177 of plan) returns `(nil, nil)` when `e == nil || len(e.Payload) == 0`. This correctly handles the "no payload" case. However, consider this scenario:

```go
payload := PhasePayload{} // zero-value: FromPhase="", ToPhase=""
raw, _ := MarshalPayload(payload) // produces: {"from_phase":"","to_phase":""}
// ...later...
parsed, err := ParsePayload[PhasePayload](envelope)
// parsed != nil, parsed.FromPhase == "", parsed.ToPhase == ""
```

This is technically distinguishable from missing (`nil`). But the more insidious case is:

```go
payload := PhasePayload{} // zero-value
raw, _ := json.Marshal(payload) // {"from_phase":"","to_phase":""}
envelope.Payload = raw
// Now: len(envelope.Payload) > 0, so ParsePayload returns a *PhasePayload
// But semantically this is a zero-value payload — was it intentional or a bug?
```

The plan's `MarshalPayload(nil)` returns `nil, nil`, which means `Payload` will be `null` in JSON (omitted due to `omitempty`). But `MarshalPayload(PhasePayload{})` returns a non-nil `json.RawMessage` containing `{"from_phase":"","to_phase":""}`. There is no way for a consumer to distinguish "caller explicitly set an empty phase transition" from "caller forgot to populate the payload fields."

**Recommendation:** Either (a) add an `IsZero()` method to each payload type (mirroring v1's `EventEnvelope.IsZero()`) and have `MarshalPayload` check it, or (b) document that zero-value payloads are semantically valid and callers must use `nil` to signal absence. Option (b) is simpler and consistent with Go conventions, but it must be explicitly stated in the contract since v1 uses `IsZero()` as the authoritative emptiness check.

---

## Finding 3

**Severity: P2 — MarshalEnvelopeV2JSON silently upgrades Version 0 to 2; breaks round-trip for default-constructed envelopes**

Lines 110-112 of the plan:

```go
if e.Version == 0 {
    e.Version = 2
}
```

This mutates the input struct in place (receiver is `*EventEnvelopeV2`, not a copy). A caller who constructs `EventEnvelopeV2{}` and later inspects it will find `Version` changed to 2 as a side effect of marshaling. This is surprising because `MarshalEnvelopeJSON` (v1) does not mutate its input — it returns `nil, nil` for zero envelopes.

More critically, this means `Version == 0` is impossible to serialize. If a future version needs a sentinel for "version not yet determined," the zero value is consumed. And `ParseEnvelopeV2JSON` never produces `Version == 0` (it yields 1 or 2), so a round-trip of a default-constructed envelope changes `Version` from 0 to 2.

**Recommendation:** Either (a) make `MarshalEnvelopeV2JSON` take a value receiver (copy) to avoid mutating the caller's struct, or (b) create a local copy inside the function: `out := *e; if out.Version == 0 { out.Version = 2 }; json.Marshal(&out)`. Option (b) is the minimal fix.

---

## Finding 4

**Severity: P2 — json.RawMessage two-phase decode swallows malformed payload silently in scanEvents**

The existing `scanEvents` function (store.go lines 536-556) parses envelope JSON and silently discards errors:

```go
if envelopeJSON != "" {
    envelope, err := ParseEnvelopeJSON(envelopeJSON)
    if err == nil {
        e.Envelope = envelope
    }
}
```

When v2 envelopes start appearing in the `envelope_json` column, this code path will call `ParseEnvelopeJSON` (v1 parser) on v2 JSON. The v1 parser will succeed because v2 is a superset of v1 field-wise (both have `trace_id`, `span_id`, etc.), but it will silently drop the `Payload` field (not present in `EventEnvelope` v1 struct) and the `v` field. The result is a degraded v1 `EventEnvelope` with no indication that payload data was lost.

The plan's `ParseEnvelopeV2JSON` correctly handles both v1 and v2, but `scanEvents` still calls the v1 parser. The plan explicitly states "No writers changed — this is schema + helpers only" and acknowledges that readers migrate in og7m.2.2. However, if any test or consumer creates v2 envelopes using the new marshaler and then reads them back via `ListEvents`, the payload will be silently dropped. The plan should document this as a known limitation or include a TODO marker in `scanEvents`.

Additionally, within the v2 parser itself: the two-phase decode (probe version, then full unmarshal) correctly propagates errors from both phases via `fmt.Errorf` wrapping. This is sound. But the `ParsePayload[T]` generic function does not distinguish between "payload is valid JSON but wrong shape for T" and "payload is invalid JSON." Both produce the same wrapped error string. A typed error would allow callers to handle schema evolution gracefully.

**Recommendation:** (a) Add a `// TODO(og7m.2.2): migrate scanEvents to ParseEnvelopeV2JSON` comment in the plan or code. (b) Consider introducing a `PayloadDecodeError` type that carries the raw bytes alongside the error, so callers can log the problematic payload for debugging.

---

## Finding 5

**Severity: P2 — Payload structs use no pointer receivers; inconsistent with EventEnvelope v1**

The v1 `EventEnvelope` has `IsZero()` defined on a pointer receiver (`func (e *EventEnvelope) IsZero() bool`). The v2 payload structs (`PhasePayload`, `DispatchPayload`, `CoordinationPayload`) define no methods at all. `EventEnvelopeV2` also defines no methods.

This is not a bug per se, but it creates an inconsistency in the API surface:

1. v1 has `IsZero()` for emptiness checking; v2 has nothing.
2. The contract registry uses zero-value instances (`event.PhasePayload{}`) for schema generation, which is correct for value types. But if methods are later added to payload structs (e.g., `Validate()`), they should use pointer receivers for consistency with the rest of the codebase and to avoid copying large structs.
3. `MarshalPayload` takes `any`, so it works with both value and pointer arguments. But `ParsePayload[T]` always returns `*T`, meaning callers always get a pointer. If someone later adds a method on `PhasePayload` (value receiver), it would be callable on `*PhasePayload` (Go's auto-deref), so there is no functional breakage. But the absence of any methods means there is no compile-time contract for what a "payload" is — it is just `any`.

**Recommendation:** Define a `Payload` interface with at least `PayloadType() string` that each struct implements. This provides the discriminator for Finding 1 and a compile-time contract. If that is too much for this bead's scope, at minimum document the convention that payload structs should use pointer receivers if methods are added later.

---

## Finding 6

**Severity: P2 — ParsePayload with unknown type returns nil, nil instead of a typed error**

When `ParsePayload[T]` is called with a `T` whose fields do not match the payload JSON (e.g., calling `ParsePayload[CoordinationPayload]` on a `PhasePayload` blob), `json.Unmarshal` will succeed silently — it will simply leave the non-matching fields at their zero values. Go's `encoding/json` does not error on extra or missing fields by default.

This means there is no "unknown type key" error path at all. The current design has no type key, so there is no lookup that can fail. The failure mode is worse than `nil+nil` — it is a successfully parsed struct with all zero-value fields, which is indistinguishable from a legitimately empty payload (see Finding 2).

```go
// This succeeds silently with all zero-value fields:
envelope.Payload = []byte(`{"from_phase":"brainstorm","to_phase":"plan"}`)
coord, err := ParsePayload[CoordinationPayload](envelope)
// err == nil, coord.LockID == "", coord.Pattern == "", coord.Scope == ""
```

**Recommendation:** This reinforces the need for a type discriminator (Finding 1). Without one, mismatched `ParsePayload` calls are undetectable. If a discriminator is added, `ParsePayload` should validate it: accept a `payloadType string` parameter and return a typed `ErrPayloadTypeMismatch` when the envelope's `payload_type` does not match the expected type for `T`.

---

## Finding 7

**Severity: P3 — Contract registry names for payload types could collide with future CLI contract names**

The plan adds four new entries to `EventContracts`:

```go
{Name: "event-envelope-v2", Instance: event.EventEnvelopeV2{}},
{Name: "phase-payload", Instance: event.PhasePayload{}},
{Name: "dispatch-payload", Instance: event.DispatchPayload{}},
{Name: "coordination-payload", Instance: event.CoordinationPayload{}},
```

The `CLIContracts` list already has names like `"dispatch"`, `"run"`, `"coordination-lock"`. The payload names use a `-payload` suffix, which avoids collision today. But the naming scheme is ad-hoc — there is no namespace separator between the two registries (`CLIContracts` vs `EventContracts`). If `go generate` produces schemas into the same directory, `dispatch-payload.json` and `dispatch.json` coexist, which is fine. But if the registries are ever merged (or a validation tool loads both), there is no prefix to distinguish event-bus types from CLI-output types.

This is informational. The current separation into two slices (`CLIContracts`, `EventContracts`) provides the namespace implicitly. No action needed unless registries are consolidated.

---

## Summary

| ID | Severity | Title |
|----|----------|-------|
| 1 | P1 | No type discriminator in payload — all three categories share untyped json.RawMessage |
| 2 | P1 | ParsePayload returns nil,nil for missing; indistinguishable from zero-value struct |
| 3 | P2 | MarshalEnvelopeV2JSON mutates input struct — breaks round-trip for Version 0 |
| 4 | P2 | Two-phase decode: scanEvents will silently drop v2 payloads via v1 parser |
| 5 | P2 | Payload structs define no methods — inconsistent with v1 and no compile-time contract |
| 6 | P2 | ParsePayload on wrong type silently succeeds with zero values instead of typed error |
| 7 | P3 | Contract registry names lack namespace prefix between CLI and event-bus types |

**Verdict: needs-changes** — The P1 findings (no discriminator, zero-value ambiguity) create type-safety holes that will surface as silent data loss when multiple payload types flow through the same consumer code path. The P2 findings are correctness and API hygiene issues that should be addressed before writers start emitting v2 in og7m.2.2.

<!-- flux-drive:complete -->
