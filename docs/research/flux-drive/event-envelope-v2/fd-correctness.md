---
agent: fd-correctness
reviewer: Julik (Flux-drive Correctness Reviewer)
plan: docs/plans/2026-03-26-event-envelope-v2.md
bead: Demarch-og7m.2.1
date: 2026-03-26
status: fail
findings: 7
severity_distribution: "P1: 3, P2: 3, P3: 1"
---

# Correctness Review — EventEnvelope v2 Schema

**Plan:** `docs/plans/2026-03-26-event-envelope-v2.md`
**Bead:** Demarch-og7m.2.1
**Reviewer:** Julik, Flux-drive Correctness Reviewer
**Date:** 2026-03-26

---

## Invariants

These must remain true for the implementation to be correct. They are derived from the plan's stated goals and the existing codebase semantics.

1. **No v1 data loss on fallback.** `ParseEnvelopeV2JSON(v1_json)` must preserve every field that v1 carries: `TraceID`, `SpanID`, `ParentSpanID`, `CallerIdentity`, and also `PolicyVersion`, `CapabilityScope`, `RequestedSandbox`, `EffectiveSandbox`, `InputArtifactRefs`, `OutputArtifactRefs`. Dropping any field without explicit justification breaks causal audit trails for existing rows.

2. **Version probe is unambiguous.** `v=1` present in the JSON must not route to native v2 parsing. The probe condition `probe.V != nil && *probe.V >= 2` is correct for forward compat, but v1 blobs from `phaseEventEnvelope` (which write no `v` field at all) and any future v1 writer that adds `"v":1` explicitly must both land on the v1 path.

3. **Marshal does not mutate its argument.** `MarshalEnvelopeV2JSON` sets `e.Version = 2` when `e.Version == 0`. This modifies the caller's struct in place. If the caller holds a pointer they expect to be unchanged, re-reading `e.Version` after the call returns 2 instead of 0. This is a mutation side-effect on the caller's data.

4. **Round-trip fidelity.** `MarshalEnvelopeV2JSON(e)` → `ParseEnvelopeV2JSON(s)` → field equality must hold for all v2 structs, including those with `nil` payload and those with non-nil `json.RawMessage` payload.

5. **`ParsePayload[T]` nil safety.** `ParsePayload[T](nil)` and `ParsePayload[T](&EventEnvelopeV2{})` must return `(nil, nil)` without panicking.

6. **`scanEvents` backward compatibility.** `store.go`'s `scanEvents` calls `ParseEnvelopeJSON` (v1 parser) on every `envelope_json` column value. After og7m.2.2 starts writing v2 blobs, existing `scanEvents` callers will silently receive `nil` envelopes for new rows because `ParseEnvelopeJSON` returns a zero-check result that discards any JSON it does not understand — specifically, the `v` field is not in `EventEnvelope` and the struct will unmarshal with all zero values, causing `IsZero()` to return `true` and `ParseEnvelopeJSON` to return `nil`.

7. **No cross-package type duplication divergence.** `phase/event_envelope.go` defines `phaseEventEnvelope` with an independent copy of the envelope fields. It writes envelope JSON directly (bypassing `MarshalEnvelopeJSON`). This type is not migrated by the plan. Its JSON output has no `v` field. Readers using `ParseEnvelopeV2JSON` will correctly treat it as v1. But the plan registers the new v2 types in `contracts/registry.go` — not the phase package's private struct. No schema inconsistency today, but the duplicate type remains a correctness risk across the migration.

---

## Findings Index

- P1 | C1 | "Task 2: MarshalEnvelopeV2JSON" | Marshal mutates caller's struct — `e.Version` set to 2 in place, permanent side-effect
- P1 | C2 | "Task 2: ParseEnvelopeV2JSON v1 fallback" | v1 fallback silently drops 6 fields present in EventEnvelope but absent from EventEnvelopeV2
- P1 | C3 | "Task 2 + store.go" | `scanEvents` calls v1 parser after v2 writers land — all new rows silently lose their envelope
- P2 | C4 | "Task 2: ParseEnvelopeV2JSON version probe" | `"v":1` written explicitly by a future writer routes to v1 path correctly, but `"v":0` written by a zeroed struct routes incorrectly to v1 path, yielding an envelope that claims Version=0
- P2 | C5 | "Task 1: PhasePayload" | PhasePayload duplicates `from_phase`/`to_phase` fields already present in the Event row — round-trip test will not detect aliased state
- P2 | C6 | "Task 2: MarshalEnvelopeV2JSON + IsZero asymmetry" | MarshalEnvelopeV2JSON marshals even a completely-zero v2 envelope (unlike v1 MarshalEnvelopeJSON which checks IsZero first) — stores unnecessary `{}` blobs
- P3 | C7 | "Task 3: registry.go" | `event.EventEnvelopeV2{}` registered with zero-value `Payload` field typed `json.RawMessage` (nil) — jsonschema reflector generates no `payload` property or marks it as `null`, which misrepresents the schema

---

## Finding 1 (P1): Marshal mutates the caller's struct in place

**Section:** Task 2, `MarshalEnvelopeV2JSON`

**Code at issue:**
```go
func MarshalEnvelopeV2JSON(e *EventEnvelopeV2) (*string, error) {
    if e == nil {
        return nil, nil
    }
    if e.Version == 0 {
        e.Version = 2  // modifies the caller's struct
    }
    b, err := json.Marshal(e)
    ...
}
```

`MarshalEnvelopeV2JSON` receives a `*EventEnvelopeV2` and unconditionally writes to `e.Version` when it is zero. This is a permanent mutation of the caller's data. The caller may be passing a reusable envelope struct that they constructed with `Version: 0` to signal "unset" — after `MarshalEnvelopeV2JSON` returns, their struct now has `Version: 2` and a second call to `MarshalEnvelopeV2JSON` takes the non-mutating branch, but any direct inspection of `e.Version` by the caller before the second call will observe the mutated value.

**Concrete failure scenario:**

```
1. Caller builds: e := &EventEnvelopeV2{TraceID: "t1"}  // Version == 0
2. Caller logs: fmt.Printf("version before marshal: %d", e.Version) → prints 0
3. Caller calls: MarshalEnvelopeV2JSON(e) → sets e.Version = 2 internally
4. Caller later checks: if e.Version == 0 { /* treat as unset */ } → WRONG, version is now 2
5. A concurrent goroutine reading e.Version without synchronization sees a partially-written int
   (int on amd64 is 64-bit aligned, Go does not atomically write int fields)
```

Step 5 is relevant if the caller shares the envelope between the marshal goroutine and a reader goroutine. There is no synchronization in the plan. `json.Marshal` itself does not synchronize access to the input struct.

**Minimal fix:** Do not mutate the argument. Use a local copy or a local `version` variable:

```go
func MarshalEnvelopeV2JSON(e *EventEnvelopeV2) (*string, error) {
    if e == nil {
        return nil, nil
    }
    v := *e                     // shallow copy on the stack
    if v.Version == 0 {
        v.Version = 2
    }
    b, err := json.Marshal(&v)
    ...
}
```

This is O(1) extra stack space (the struct is small — five strings, one `[]byte`). No pointer aliasing issues.

Note: `Payload json.RawMessage` is a `[]byte` slice header (pointer + len + cap). The shallow copy shares the underlying byte array. That is safe for marshal — `json.Marshal` reads but does not write the slice contents.

---

## Finding 2 (P1): v1 fallback silently drops 6 fields

**Section:** Task 2, `ParseEnvelopeV2JSON` v1 fallback

**Code at issue:**
```go
return &EventEnvelopeV2{
    Version:        1,
    TraceID:        v1.TraceID,
    SpanID:         v1.SpanID,
    ParentSpanID:   v1.ParentSpanID,
    CallerIdentity: v1.CallerIdentity,
    // v1 source-specific data is not migrated into Payload —
    // readers of Version=1 envelopes should use the Event's
    // top-level fields for source context.
}, nil
```

`EventEnvelope` (v1) has 10 fields. `EventEnvelopeV2` maps only 4 of them. The fields dropped by the fallback path:

| Dropped v1 field | Risk |
|---|---|
| `PolicyVersion` | Policy audit trail is lost for all v1 rows read through the v2 path |
| `CapabilityScope` | Capability attribution is lost |
| `RequestedSandbox` | Sandbox audit is lost — this is specifically populated by `defaultDispatchEnvelope` from a live DB query |
| `EffectiveSandbox` | Same — populated from `dispatches.sandbox_effective` |
| `InputArtifactRefs` | Causal input chain lost |
| `OutputArtifactRefs` | Causal output chain lost |

The comment "readers of Version=1 envelopes should use the Event's top-level fields for source context" does not apply to these fields: `PolicyVersion`, `CapabilityScope`, `RequestedSandbox`, and `EffectiveSandbox` are not present anywhere in the `Event` struct. They exist only in the stored `envelope_json`. Once the v1 fallback silently drops them, they are gone from any caller using `ParseEnvelopeV2JSON`.

**Why this is P1:** The `RequestedSandbox` and `EffectiveSandbox` fields are populated by a live DB query in `defaultDispatchEnvelope` at write time — this is the only place in the system where sandbox attribution is recorded for dispatch events. After og7m.2.2 shifts readers to `ParseEnvelopeV2JSON`, all v1 rows in the database will report empty sandbox fields through the new parser. This is a silent data regression for all existing dispatch event history.

**Concrete failure:**
```
1. dispatch_events row: envelope_json = '{"policy_version":"dispatch-lifecycle/v2","requested_sandbox":"{\"mode\":\"workspace-write\"}","effective_sandbox":"{\"mode\":\"workspace-read\"}","trace_id":"run-abc",...}'
2. ParseEnvelopeV2JSON(row) → v1 probe.V == nil → falls through to v1 path
3. v1 struct populated: v1.RequestedSandbox = `{"mode":"workspace-write"}`, v1.EffectiveSandbox = `{"mode":"workspace-read"}`
4. Return: &EventEnvelopeV2{Version:1, TraceID:"run-abc", ...} — RequestedSandbox and EffectiveSandbox are empty string
5. Caller checks envelope.RequestedSandbox → "" → reports "no sandbox configured" for a row that clearly had one
```

**Fix options (choose one):**

Option A — Extend `EventEnvelopeV2` to carry the dropped fields as top-level fields:
```go
type EventEnvelopeV2 struct {
    Version          int             `json:"v"`
    TraceID          string          `json:"trace_id,omitempty"`
    SpanID           string          `json:"span_id,omitempty"`
    ParentSpanID     string          `json:"parent_span_id,omitempty"`
    CallerIdentity   string          `json:"caller_identity,omitempty"`
    PolicyVersion    string          `json:"policy_version,omitempty"`    // preserved for v1 compat
    CapabilityScope  string          `json:"capability_scope,omitempty"`  // preserved for v1 compat
    RequestedSandbox string          `json:"requested_sandbox,omitempty"` // lifted from DispatchPayload for v1
    EffectiveSandbox string          `json:"effective_sandbox,omitempty"` // lifted from DispatchPayload for v1
    Payload          json.RawMessage `json:"payload,omitempty"`
}
```

Option B — Populate the v1 fields in the fallback return, mapping them into `Payload` as a `DispatchPayload` when the source-specific fields are non-empty (requires knowing the source type, which is not available at parse time — this makes Option A cleaner).

Option C — Keep `EventEnvelopeV2` lean but document explicitly that callers receiving `Version=1` must fall back to `ParseEnvelopeJSON` for the full field set. This is safe only if v2 readers are written to perform that dual-path lookup, which the plan currently does not describe.

---

## Finding 3 (P1): `scanEvents` calls v1 parser — v2 blobs silently become nil envelopes

**Section:** Task 2 (cross-cutting) and `store.go`

**Code at issue** (`store.go`, `scanEvents`):
```go
if envelopeJSON != "" {
    envelope, err := ParseEnvelopeJSON(envelopeJSON)
    if err == nil {
        e.Envelope = envelope
    }
}
```

`ParseEnvelopeJSON` deserializes into `EventEnvelope` (v1 struct). A v2 blob like:
```json
{"v":2,"trace_id":"run-abc","payload":{"from_phase":"brainstorm","to_phase":"strategized"}}
```
will unmarshal into `EventEnvelope` with all fields zero (the `v` key has no corresponding struct field; `trace_id` maps correctly; `payload` has no corresponding field). After unmarshal, `e.IsZero()` checks `TraceID == ""` — but `trace_id` *does* map to `TraceID`, so if `trace_id` is non-empty, `IsZero()` returns `false` and the v1 envelope is returned with the tracing fields populated but all the v2-specific fields (`payload`, etc.) silently dropped.

However: if a v2 writer emits only `{"v":2,"payload":{...}}` with no tracing fields populated, then `ParseEnvelopeJSON` → `IsZero()` returns `true` → `ParseEnvelopeJSON` returns `nil` → `e.Envelope = nil`. The event row loses its envelope entirely.

**Concrete failure interleaving — mixed deployment (og7m.2.1 plan deployed, og7m.2.2 in progress):**
```
1. og7m.2.2 lands: phase.Store starts writing v2 blobs with only payload data and no trace fields
2. A reader calls store.ListEvents — this calls scanEvents → ParseEnvelopeJSON
3. ParseEnvelopeJSON on '{"v":2,"payload":{"from_phase":"brainstorm"}}' → all v1 fields zero → IsZero()=true → returns nil
4. Event.Envelope = nil
5. Existing test TestListEvents_CausalReconstructionByTraceID asserts e.Envelope != nil — FAIL
6. Production event display shows no envelope on all new phase events
```

**The plan acknowledges this is schema-only (no writers change in og7m.2.1)**, so this failure is latent during og7m.2.1. But the plan does not document that `scanEvents` must be migrated before og7m.2.2 lands, and `Event.Envelope` is typed `*EventEnvelope` (v1) — not `*EventEnvelopeV2`. The migration path for `Event.Envelope` is not described in this plan or the subsequent og7m bead descriptions referenced in the plan header.

**Minimal fix for og7m.2.1:** Document the contract explicitly: og7m.2.2 (writers) must not land until og7m.2.x (Event type migration + scanEvents migration) is complete. Add a compile-time comment or TODO at the `scanEvents` call site naming the dependency bead. Failing to track this dependency is the exact class of issue that causes 3 AM pages when the second bead ships independently.

---

## Finding 4 (P2): `"v":0` stored by zeroed struct routes to v1 path with misleading result

**Section:** Task 2, `ParseEnvelopeV2JSON`

The plan uses `*int` for the probe to distinguish "field absent" from "field present with value 0":

```go
var probe struct {
    V *int `json:"v"`
}
// ...
if probe.V != nil && *probe.V >= 2 {
    // native v2
}
```

This is correct for the distinction between absent `v` and `v=1`. However, `MarshalEnvelopeV2JSON` with a `Version=0` input (after the proposed fix in C1 that avoids mutation) would serialize `"v":0` if the caller explicitly sets `Version` to 0 or forgets to set it. With the current (mutating) implementation, the mutation sets it to 2 before marshal, so `"v":0` is never written. But this is a behavioral coupling: the marshal side-effect prevents `"v":0` from reaching the parser. If the mutation is removed (as recommended in C1), the caller must ensure `Version` is set. A test that marshals a zero-value `EventEnvelopeV2{}` will produce `{"v":0,...}` (or no `v` field at all if `json:",omitempty"` is used — but the struct tag is `json:"v"` with no `omitempty`), and `ParseEnvelopeV2JSON` will route it to the v1 fallback, returning an `EventEnvelopeV2` with `Version=1` when the actual version was 0 (unset).

**The struct tag `json:"v"` without `omitempty` means a zero Version is serialized as `"v":0`.** After the C1 fix, `MarshalEnvelopeV2JSON` no longer sets `Version=2` unconditionally. A caller that passes `&EventEnvelopeV2{TraceID: "t"}` will get `{"v":0,"trace_id":"t"}` serialized, which will re-parse as v1 with Version=1 — a round-trip break.

**Fix:** Add `omitempty` to the Version field tag, or document that callers must set Version before marshaling, or keep the mutation behavior as a documented invariant (and note in C1 that the mutation is intentional, not a bug):

```go
Version int `json:"v,omitempty" jsonschema:"enum=1,enum=2"`
```

With `omitempty`, a zero Version produces no `v` field, which the probe correctly routes to the v1 path. With `Version=2`, it emits `"v":2`. With `Version=1` it emits `"v":1` (non-zero, so not omitted), and the probe correctly routes it to v1 path (condition is `>= 2`).

---

## Finding 5 (P2): PhasePayload duplicates fields already in the Event row — tests will not catch aliased state

**Section:** Task 1, `PhasePayload`

```go
type PhasePayload struct {
    FromPhase string `json:"from_phase"`
    ToPhase   string `json:"to_phase"`
}
```

`Event.FromState` and `Event.ToState` already carry `from_phase` and `to_phase` values for phase events (see `store.go` `ListEvents`, the UNION ALL that maps `from_phase AS from_state` and `to_phase AS to_state`). `PhasePayload` in the envelope stores the same data in a second location.

This creates two sources of truth for phase transition data. If a writer sets `PhasePayload.FromPhase = "brainstorm"` but the row's `from_phase` column contains `"planned"` (e.g., due to a bug in the writer), readers that check `Event.FromState` see one value and readers that check `ParsePayload[PhasePayload](event.Envelope)` see another. No consistency invariant enforces agreement between them.

More concretely: the round-trip test described in the plan ("Round-trip: marshal v2 with PhasePayload → parse → verify all fields") operates entirely on the serialized blob. It never compares `PhasePayload.FromPhase` against the event row's `from_state` column. The test passes even when the two are out of sync.

**This is not a blocker** (the plan explicitly defers writer changes to og7m.2.2), but the design choice to duplicate phase data in the payload should be explicitly justified or the payload type redesigned to carry only data that is NOT already in the Event row (e.g., `RunID`, `ChildPhases`, or future phase-specific metadata).

**Recommendation:** Either remove `PhasePayload` from the plan and defer it to og7m.2.2 when the writer is defined, or rename it to `PhaseEnvelopeExtras` and document that it carries only supplemental data not present in `Event.*` fields.

---

## Finding 6 (P2): `MarshalEnvelopeV2JSON` does not check IsZero — stores unnecessary blobs

**Section:** Task 2, `MarshalEnvelopeV2JSON`

The v1 `MarshalEnvelopeJSON` guards with `if e == nil || e.IsZero() { return nil, nil }`, matching the convention that empty envelopes are stored as NULL in the database. The v2 version checks only `e == nil`:

```go
func MarshalEnvelopeV2JSON(e *EventEnvelopeV2) (*string, error) {
    if e == nil {
        return nil, nil
    }
    if e.Version == 0 {
        e.Version = 2
    }
    b, err := json.Marshal(e)
    ...
}
```

A caller that passes `&EventEnvelopeV2{}` (all zero fields) will get `{"v":2}` marshaled and stored in `envelope_json`. This is a non-NULL blob for a conceptually empty envelope. `ParseEnvelopeV2JSON` on `{"v":2}` will successfully parse a v2 envelope with Version=2 and all other fields zero — so the round-trip is consistent, but the semantics differ from v1: v1 stores NULL for empty envelopes, v2 stores `{"v":2}`.

**Impact:** Low in isolation, but the asymmetry means code that checks `envelope_json IS NOT NULL` to determine whether an envelope exists will return `true` for zero v2 envelopes but `false` for zero v1 envelopes. After the migration, audit queries that count "events with envelopes" will over-count. The `scanEvents` path (C3) will pass the non-empty-string check and attempt to parse `{"v":2}` with `ParseEnvelopeJSON` — which will parse it with all fields zero, trigger `IsZero()`, and return nil, discarding the `{"v":2}` blob silently.

**Fix:** Add an `IsZero` check to `EventEnvelopeV2` and guard in `MarshalEnvelopeV2JSON`:

```go
func (e *EventEnvelopeV2) IsZero() bool {
    return e == nil ||
        (e.TraceID == "" && e.SpanID == "" && e.ParentSpanID == "" &&
         e.CallerIdentity == "" && len(e.Payload) == 0)
}
```

---

## Finding 7 (P3): `json.RawMessage` nil payload generates misleading JSON schema

**Section:** Task 3, registry.go

```go
{Name: "event-envelope-v2", Instance: event.EventEnvelopeV2{}},
```

`EventEnvelopeV2{}` has `Payload json.RawMessage` with a nil value (zero-value `[]byte`). `github.com/invopop/jsonschema` reflects the `json.RawMessage` type (`[]byte` underlying) as:
```json
{"type": "string", "contentEncoding": "base64"}
```
(or similar, depending on reflector version) rather than `{"type": "object"}` or an anyOf of the payload union types. This means the generated schema for `event-envelope-v2.json` will not accurately describe the actual payload shape. Downstream schema validators using the generated contract will either reject valid payloads or accept invalid ones.

**Fix:** Override the schema for `Payload` using a `JSONSchema` method or use `jsonschema_extras` tag to specify `type: object` or a `oneOf` covering the known payload types. Alternatively, add a note in `contracts/events/README.md` documenting that the `payload` field schema is intentionally loose (raw JSON object, validated per source type) so schema consumers are not misled.

---

## Summary

The plan is structurally sound. The version probe approach (`*int` pointer) is the correct Go idiom for distinguishing absent-vs-zero. The generic `ParsePayload[T]` design is clean and safe. The test coverage list is appropriate.

Three issues require changes before the plan can be considered correct:

**C1 (P1) — Marshal mutation:** `MarshalEnvelopeV2JSON` must not modify its argument. Shallow-copy the struct before setting Version.

**C2 (P1) — v1 fallback field loss:** `PolicyVersion`, `CapabilityScope`, `RequestedSandbox`, `EffectiveSandbox`, `InputArtifactRefs`, and `OutputArtifactRefs` are silently dropped from v1 rows when read through `ParseEnvelopeV2JSON`. For `RequestedSandbox` and `EffectiveSandbox` this is a silent audit regression affecting all existing dispatch event history. Either extend `EventEnvelopeV2` to carry the missing fields, or require dual-path readers.

**C3 (P1) — scanEvents compatibility gap:** `store.go`'s `scanEvents` uses the v1 parser unconditionally. This is safe while og7m.2.1 is schema-only, but og7m.2.2 (writers) must not merge until the `Event.Envelope` type and `scanEvents` are updated. The plan does not capture this dependency. Without a hard gate, og7m.2.2 shipping before the reader migration will silently zero out envelopes on all new rows in production.

The three P2 issues (C4 tag serialization, C5 PhasePayload duplication, C6 IsZero asymmetry) should be addressed before writers change in og7m.2.2 to prevent the asymmetry from becoming load-bearing.

---

### Findings Index

- P1 | C1 | "Task 2: MarshalEnvelopeV2JSON" | Marshal mutates caller's struct — `e.Version` set to 2 in place, permanent side-effect
- P1 | C2 | "Task 2: ParseEnvelopeV2JSON v1 fallback" | v1 fallback silently drops PolicyVersion, CapabilityScope, RequestedSandbox, EffectiveSandbox, InputArtifactRefs, OutputArtifactRefs
- P1 | C3 | "Task 2 + store.go scanEvents" | scanEvents calls v1 parser — all v2 blobs silently lose envelope when og7m.2.2 lands without reader migration gate
- P2 | C4 | "Task 1 + Task 2" | Version=0 struct serializes as `"v":0` (no omitempty), routes to v1 path on re-parse — round-trip break for zero-value envelopes
- P2 | C5 | "Task 1: PhasePayload" | PhasePayload duplicates from_phase/to_phase already in Event row — no consistency invariant, tests cannot catch aliased state
- P2 | C6 | "Task 2: MarshalEnvelopeV2JSON" | No IsZero guard — zero v2 envelopes stored as `{"v":2}` rather than NULL, asymmetric with v1 behavior
- P3 | C7 | "Task 3: contracts/registry.go" | json.RawMessage payload reflects as base64 string in generated schema, not object — misleads schema consumers

<!-- flux-drive:complete -->
