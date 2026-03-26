---
agent: claude-opus-4-6
status: complete
findings: 6
reviewed_files:
  - core/intercore/contracts/generate.go
  - core/intercore/contracts/registry.go
  - core/intercore/contracts/generate_test.go
  - core/intercore/contracts/cmd/gen/main.go
  - core/intercore/contracts/events/event.json
  - core/intercore/contracts/events/event-envelope.json
  - core/intercore/internal/event/envelope.go
  - core/intercore/internal/event/event.go
  - docs/plans/2026-03-26-event-envelope-v2.md
  - vendor: github.com/invopop/jsonschema@v0.13.0 (reflect.go, schema.go, utils.go, fixtures/)
---

# Flux-Drive Review: JSON Schema Generation for EventEnvelope v2

Review of the invopop/jsonschema reflector pipeline and whether the planned v2 struct
tags will produce the intended schema output.

---

## Finding 1: json.RawMessage Payload renders as boolean `true`, not empty object `{}`

**Severity: P1**

The plan assumes `json.RawMessage` generates `{}` ("empty object") in the schema. The
actual behavior in invopop/jsonschema v0.13.0 is different: `json.RawMessage` is
special-cased in `reflectSliceOrArray` (reflect.go:397-399) — the function returns
immediately without setting any type, which causes the field to serialize as the JSON
Schema boolean value `true` (meaning "any value accepted").

Confirmed in library test fixtures (`no_reference.json` line 193, `test_user.json`
line 205): a `json.RawMessage` field produces `"raw": true` in the properties map.

**Impact:** The generated schema will look like:

```json
"payload": true
```

Not:

```json
"payload": {}
```

Both `true` and `{}` are semantically equivalent in JSON Schema 2020-12 (both mean
"accept any value"), so this is functionally correct. However, if downstream consumers
or documentation expect `{}`, it may cause confusion. The `true` form is actually the
canonical way to express "any value" in modern JSON Schema.

**Recommendation:** No code change needed. Document the `true` representation in the
`contracts/events/README.md` update (Task 5) so downstream consumers aren't surprised.

---

## Finding 2: enum values on int field correctly serialize as integers, not strings

**Severity: P3 (informational, no issue)**

The plan uses `jsonschema:"enum=1,enum=2"` on the `Version int` field. The library's
dispatch path is:

1. `int` → schema type `"integer"` (reflect.go:337-339)
2. Type `"integer"` → `numericalKeywords()` called (reflect.go:619-620)
3. `numericalKeywords` parses enum values via `toJSONNumber()` (reflect.go:811-814)
4. `toJSONNumber` wraps the string in `json.Number`, which marshals as bare `1`, `2`

The generated schema will correctly contain:

```json
"v": {
  "type": "integer",
  "enum": [1, 2]
}
```

This is verified by the library's own `no_reference.json` fixture (`"rank"` field at
lines 143-150 shows integer enum values `[1, 2, 3]`).

**No action needed.**

---

## Finding 3: Required/optional field classification is correct — but Version=0 passes enum at marshal time, not schema time

**Severity: P2**

The reflector's `RequiredFromJSONSchemaTags` is NOT set (defaults to `false`), so the
default behavior applies: fields without `omitempty` are required; fields with
`omitempty` are optional (`requiredFromJSONTags`, reflect.go:928-940).

For `EventEnvelopeV2`:

| Field            | json tag                     | Required? | Correct? |
|------------------|------------------------------|-----------|----------|
| `Version`        | `json:"v"`                   | Yes       | Yes      |
| `TraceID`        | `json:"trace_id,omitempty"`  | No        | Yes      |
| `SpanID`         | `json:"span_id,omitempty"`   | No        | Yes      |
| `ParentSpanID`   | `json:"parent_span_id,omitempty"` | No   | Yes      |
| `CallerIdentity` | `json:"caller_identity,omitempty"` | No  | Yes      |
| `Payload`        | `json:"payload,omitempty"`   | No        | Yes      |

The subtlety: `MarshalEnvelopeV2JSON` has `if e.Version == 0 { e.Version = 2 }`,
which mutates the input struct's Version field. This means a caller who constructs
`EventEnvelopeV2{}` (zero value) and calls `MarshalEnvelopeV2JSON` will silently get
Version=2. This is by design. But the mutation is on the input pointer — callers who
inspect the struct after marshaling will see Version=2 where they set Version=0. This
is a side-effect that should be documented.

**Recommendation:** Either document the mutation, or assign to a copy:

```go
out := *e
if out.Version == 0 {
    out.Version = 2
}
b, err := json.Marshal(&out)
```

---

## Finding 4: Payload types have inconsistent required-field patterns

**Severity: P2**

The three payload types have different required-field behavior based on their `omitempty`
tags:

**PhasePayload** — both fields required:
```go
FromPhase string `json:"from_phase"`
ToPhase   string `json:"to_phase"`
```
Schema: `"required": ["from_phase", "to_phase"]`

**DispatchPayload** — no fields required (all `omitempty`):
```go
DispatchID       string `json:"dispatch_id,omitempty"`
FromStatus       string `json:"from_status,omitempty"`
ToStatus         string `json:"to_status,omitempty"`
RequestedSandbox string `json:"requested_sandbox,omitempty"`
EffectiveSandbox string `json:"effective_sandbox,omitempty"`
```
Schema: no `required` array.

**CoordinationPayload** — no fields required (all `omitempty`):
```go
LockID  string `json:"lock_id,omitempty"`
Pattern string `json:"pattern,omitempty"`
Scope   string `json:"scope,omitempty"`
```
Schema: no `required` array.

This inconsistency may be intentional (phase transitions always have from/to, dispatch
may not), but it should be verified against the event writers in og7m.2.2 that will
populate these payloads. If dispatch events always have `from_status`/`to_status`, those
fields should drop `omitempty`.

**Recommendation:** Audit whether `DispatchPayload.FromStatus` and
`DispatchPayload.ToStatus` should be required (matching the v1 `Event.FromState`/
`Event.ToState` which are required in the existing `event.json` schema).

---

## Finding 5: Schema output is deterministic — no ordering issue

**Severity: P3 (informational, no issue)**

The invopop/jsonschema library uses `github.com/wk8/go-ordered-map/v2` for the
`Properties` field (schema.go:38). Properties are inserted in struct field declaration
order via `st.Properties.Set(name, property)` (reflect.go:543). The `required` array
is built by `appendUniqueString` in the same field iteration order (reflect.go:544-546).

Both `EventContracts` and `CLIContracts` are Go slice literals (registry.go), so
iteration order is stable. `json.MarshalIndent` preserves ordered-map key order.

The generated schemas will have deterministic field ordering matching struct declaration
order. Repeated `go generate` runs will produce identical output (no diff noise).

**No action needed.**

---

## Finding 6: v2 schema is structurally distinguishable from v1 but additionalProperties: false blocks cross-validation

**Severity: P1**

The generated v2 schema will have:
- `$id: "https://intercore.dev/contracts/events/event-envelope-v2.json"` (distinct from
  v1's `event-envelope.json`)
- A `"v"` property with `"enum": [1, 2]` (v1 has no version field)
- `"additionalProperties": false` (default behavior, `AllowAdditionalProperties` not set)

The `additionalProperties: false` constraint means a v1 JSON document (containing fields
like `policy_version`, `capability_scope`, `input_artifact_refs`, `output_artifact_refs`)
will **fail validation** against the v2 schema. This is correct behavior — the v2 schema
describes v2 documents only.

However, the plan's `ParseEnvelopeV2JSON` function accepts both v1 and v2 JSON, which
means Go code will handle documents that the v2 JSON Schema would reject. This creates a
mismatch between schema-level validation and runtime behavior:

- **Schema says:** v2 envelope only, with exactly these fields
- **Runtime says:** v1 or v2, fallback parsing for v1

If any downstream system uses the v2 JSON Schema for pre-validation (e.g., a webhook
gateway or event ingestion pipeline), v1 documents will be rejected before they reach
the Go parser's fallback path.

**Recommendation:** Either:
1. Keep the schema strict (v2 only) and document that schema validation should be
   skipped during the v1→v2 migration window (until og7m.2.6 removes v1). This is the
   simpler approach.
2. Or add a `oneOf` composition schema (e.g., `event-envelope-any.json`) that accepts
   either v1 or v2, for use by external validators during migration.

Option 1 is likely sufficient since the plan says "schema change is invisible to SQLite"
and the envelope JSON is stored as an opaque blob.

---

## Summary

| # | Finding | Severity | Action Required |
|---|---------|----------|-----------------|
| 1 | RawMessage renders as `true` not `{}` | P1 | Document in README |
| 2 | int enum serializes correctly as integers | P3 | None |
| 3 | Required fields correct; marshal mutates input | P2 | Copy before mutation |
| 4 | Payload types have inconsistent required fields | P2 | Audit dispatch payload |
| 5 | Output ordering is deterministic | P3 | None |
| 6 | additionalProperties: false blocks v1 cross-validation | P1 | Document migration gap |

Two P1 findings require documentation changes. Two P2 findings require minor code or
design decisions. No blockers — the plan's core approach is sound, and the invopop/jsonschema
library handles the v2 struct tags correctly for the intended semantics.

<!-- flux-drive:complete -->
