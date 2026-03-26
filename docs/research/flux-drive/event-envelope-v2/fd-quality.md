---
artifact_type: flux-drive-review
reviewer: fd-quality
plan: docs/plans/2026-03-26-event-envelope-v2.md
bead: Demarch-og7m.2.1
status: needs-changes
findings: 6
---

# Quality & Style Review — EventEnvelope v2 Implementation Plan

## Scope

Plan at `docs/plans/2026-03-26-event-envelope-v2.md` — 6 tasks: new `envelope_v2.go` file with
types and helpers, tests in `envelope_v2_test.go`, registry update in `contracts/registry.go`,
and schema regeneration. Language in scope: Go 1.22. Review aligns against prevailing patterns in
`core/intercore/internal/event/` (envelope.go, event.go, store.go, store_test.go) and the
intercore CLAUDE.md/AGENTS.md conventions.

---

## Findings Index

- HIGH | Q-01 | Task 2: MarshalEnvelopeV2JSON | Silent mutation of caller's struct violates the existing marshal convention
- HIGH | Q-02 | Task 2: ParseEnvelopeV2JSON | v1 parse errors lose context compared to existing package style
- MED  | Q-03 | Task 1: EventEnvelopeV2 struct | `json:"v"` key is too terse for a public contract type; diverges from field naming convention in the same package
- MED  | Q-04 | Task 4: Test coverage | v1 fallback test cases use "actual v1 JSON" but no fixture JSON is provided; implementor must guess the shape
- LOW  | Q-05 | Task 2: ParsePayload generic | Idiomatic for Go 1.22 but `nil, nil` on empty payload is an undocumented footgun for callers
- LOW  | Q-06 | Task 3: Registry entry | `EventEnvelopeV2{}` in the registry will generate a schema where `json:"v"` appears as `"v"` — inconsistent with all other generated schemas that use full field names

Verdict: needs-changes

---

## Finding 1 — HIGH: MarshalEnvelopeV2JSON mutates the caller's struct

**Task 2, `MarshalEnvelopeV2JSON`**

```go
func MarshalEnvelopeV2JSON(e *EventEnvelopeV2) (*string, error) {
    if e == nil {
        return nil, nil
    }
    if e.Version == 0 {
        e.Version = 2   // mutates the caller's value
    }
    ...
}
```

The existing `MarshalEnvelopeJSON` in `envelope.go` never writes back to its argument. This new
function does: it sets `e.Version = 2` on the pointer the caller passed in. A caller who
constructs an `EventEnvelopeV2{}` zero value, marshals it, then inspects the struct will see
`Version == 2` — a change they did not make. This breaks the "marshal is a read-only operation"
expectation and can produce subtle ordering bugs if the struct is used again after marshaling.

Fix: copy the value before setting the version field, or require callers to populate `Version`
themselves and reject zero with an error.

```go
func MarshalEnvelopeV2JSON(e *EventEnvelopeV2) (*string, error) {
    if e == nil {
        return nil, nil
    }
    out := *e
    if out.Version == 0 {
        out.Version = 2
    }
    b, err := json.Marshal(out)
    if err != nil {
        return nil, fmt.Errorf("marshal envelope v2: %w", err)
    }
    s := string(b)
    return &s, nil
}
```

---

## Finding 2 — HIGH: ParseEnvelopeV2JSON v1 parse error drops context

**Task 2, `ParseEnvelopeV2JSON` v1 fallback branch**

```go
var v1 EventEnvelope
if err := json.Unmarshal([]byte(raw), &v1); err != nil {
    return nil, fmt.Errorf("parse envelope v1: %w", err)
}
```

The v2 native branch wraps its error as `"parse envelope v2: %w"`. The existing `ParseEnvelopeJSON`
in `envelope.go` returns the raw `json.Unmarshal` error without any wrapping at all. The v1
fallback branch here adds an inconsistent middle ground: it wraps but the prefix `"parse envelope
v1"` is invisible to callers who do not know whether the input was v1 or v2. More importantly,
`ParseEnvelopeJSON` (the v1-only function) is the authoritative v1 parser — if its behavior
changes in a future bead, the v1 fallback inside `ParseEnvelopeV2JSON` will silently diverge.

Fix: delegate to the existing `ParseEnvelopeJSON` for the v1 path rather than duplicating the
unmarshal logic, and wrap with a consistent message that includes the input version:

```go
v1, err := ParseEnvelopeJSON(raw)
if err != nil {
    return nil, fmt.Errorf("parse envelope v2 (v1 fallback): %w", err)
}
if v1 == nil || v1.IsZero() {
    return nil, nil
}
return &EventEnvelopeV2{
    Version:        1,
    TraceID:        v1.TraceID,
    ...
}, nil
```

This also eliminates the duplicated `if v1.IsZero()` logic since `ParseEnvelopeJSON` already
returns `nil` for zero envelopes.

---

## Finding 3 — MED: `json:"v"` key diverges from the package's naming convention

**Task 1, `EventEnvelopeV2` struct**

```go
Version int `json:"v" jsonschema:"enum=1,enum=2"`
```

Every field in `EventEnvelope` (v1) uses the full snake_case JSON key that matches or approximates
the field name: `policy_version`, `caller_identity`, `trace_id`, `span_id`. The `Event` struct in
`event.go` follows the same rule (`run_id`, `from_state`, `to_state`). Using `"v"` as the key
for `Version` is a single-character abbreviation that breaks this consistency.

The key is also a public contract: it appears in the generated JSON schema, in the `event-envelope.json`
file checked into the repo, and in any downstream consumers that parse the blob. The plan comment
correctly says this field is the version discriminator, which makes legibility especially important
— a reader of raw JSON should not need to look up what `"v"` means.

Fix: use `json:"version"` to stay consistent with the package convention. If an abbreviated key is
intentional (e.g., to save bytes in high-volume storage), document the rationale in the field
comment so future maintainers do not silently change it.

---

## Finding 4 — MED: Test task references "actual v1 JSON" with no fixture provided

**Task 4, test cases 5 and 6**

```
5. v1 fallback: parse actual v1 JSON (phase-machine format) → verify Version=1 + core fields
6. v1 fallback: parse actual v1 JSON (dispatch-lifecycle format) → verify Version=1
```

The words "actual v1 JSON" imply concrete fixture strings, but none are given in the plan. The
implementor must reverse-engineer what a v1 `phase-machine` envelope looks like from `store.go`'s
`defaultDispatchEnvelope` and `defaultCoordinationEnvelope` functions. This is not hard, but
leaving it implicit means the test may be written against an envelope that lacks the fields the
v1 fallback is supposed to preserve (TraceID, SpanID, etc.), producing a test that passes trivially
while covering nothing meaningful.

Existing tests in `store_test.go` show the project's style: inline literal values are preferred
over fixture files for the event package. The plan should provide the literal JSON strings so the
implementor cannot inadvertently write a test that passes on an empty v1 envelope.

Suggested fixture (phase-machine format, matching `PolicyVersion: "dispatch-lifecycle/v2"` seen in
`store.go`):

```go
const v1PhaseJSON = `{"policy_version":"dispatch-lifecycle/v2","caller_identity":"dispatch.store","trace_id":"run-abc","span_id":"dispatch:d1:1234","parent_span_id":""}`
```

---

## Finding 5 — LOW: ParsePayload nil-nil return is an undocumented footgun

**Task 2, `ParsePayload[T any]`**

```go
func ParsePayload[T any](e *EventEnvelopeV2) (*T, error) {
    if e == nil || len(e.Payload) == 0 {
        return nil, nil
    }
    ...
}
```

Returning `(nil, nil)` when the payload is absent is a common Go pattern, but it is indistinguishable
from "the type T has no fields set". A caller calling `ParsePayload[PhasePayload](e)` where the
envelope has a `DispatchPayload` in it will get back a populated `*PhasePayload` with incorrect
data (silently zero-typed fields), not an error. The function provides no mechanism to detect type
mismatch.

This is acceptable for v2 because the plan explicitly states payload type is not self-describing
(the caller is expected to know the type from `Event.Source`). However, the doc comment should
state this contract explicitly so future callers understand why there is no type discriminator:

```go
// ParsePayload unmarshals the envelope payload into T.
// The caller is responsible for selecting the correct type T based on the
// originating Event.Source value — no type discriminator is stored in the payload.
// Returns (nil, nil) when the envelope or payload is absent.
func ParsePayload[T any](e *EventEnvelopeV2) (*T, error) {
```

The generic itself is idiomatic Go 1.22 — no issue there.

---

## Finding 6 — LOW: Registry schema for EventEnvelopeV2 will emit `"v"` as a top-level key

**Task 3, registry.go addition**

```go
{Name: "event-envelope-v2", Instance: event.EventEnvelopeV2{}},
```

The `invopop/jsonschema` reflector used by `contracts/generate.go` reads the `json` struct tag to
determine the property name in the generated schema. If `Version` keeps `json:"v"`, the generated
`event-envelope-v2.json` will have a top-level property `"v"` alongside `"trace_id"`,
`"span_id"`, etc. This produces a schema that is inconsistent with both the v1 schema
(`event-envelope.json` has no single-letter properties) and every other event schema in
`contracts/events/`. The existing `event.json` schema uses full field names throughout.

This finding is downstream of Finding 3 (the `json:"v"` key choice) and resolves with it. It is
called out separately because the generated JSON schema is a committed artifact checked into the
repo and visible to downstream consumers — the impact is broader than just the Go struct.

---

## Language-Specific Notes (Go)

**Naming — 5-second rule.** `ParsePayload`, `MarshalPayload`, `MarshalEnvelopeV2JSON`, and
`ParseEnvelopeV2JSON` all pass the 5-second rule. `PhasePayload`, `DispatchPayload`,
`CoordinationPayload` are clear. `EventEnvelopeV2` follows the existing `EventEnvelope` + version
suffix pattern.

**Error wrapping.** The plan uses `%w` consistently in all error paths, which matches the
`store.go` pattern (`fmt.Errorf("add dispatch event: marshal envelope: %w", err)`). The one gap
is the v1 fallback discussed in Finding 2.

**Nil pointer safety.** `MarshalEnvelopeV2JSON` checks `e == nil`. `ParsePayload` checks
`e == nil`. `ParseEnvelopeV2JSON` checks `raw == ""`. `EventEnvelope.IsZero()` checks
`e == nil`. These are consistent with the existing package style.

**`json.RawMessage` for Payload.** Using `json.RawMessage` (which is `[]byte`) for `Payload`
is the idiomatic Go approach for an untyped sub-document. The `omitempty` tag on a
`json.RawMessage` field omits it when the slice is nil or empty, which is the correct behavior
here. No issue.

**Table-driven tests.** The plan lists 9 test cases but does not structure them as
`[]struct{name string; ...}` table-driven tests. The existing `handler_log_test.go` and
`notifier_test.go` use both individual and table-driven styles. For 9 cases covering
`ParseEnvelopeV2JSON` + `MarshalEnvelopeV2JSON`, a table-driven approach for the
round-trip cases and the fallback cases would be shorter and more maintainable. This is a
style suggestion, not a defect — the plan does not mandate a structure.

---

## Summary

The plan is well-scoped and the types are sound. Two HIGH findings require changes before
implementation: `MarshalEnvelopeV2JSON` must not mutate the caller's struct, and the v1 fallback
path should delegate to `ParseEnvelopeJSON` rather than duplicating unmarshal logic. The `json:"v"`
key choice (Finding 3) is a MED because it creates an inconsistency that propagates into the
committed JSON schema artifact. The missing fixture strings in the test specification (Finding 4)
are a MED because they make the v1 fallback tests easy to write incorrectly. The remaining two
findings are LOW and can be addressed in the same pass.

<!-- flux-drive:complete -->
