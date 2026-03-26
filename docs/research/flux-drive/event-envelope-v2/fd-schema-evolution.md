---
artifact_type: flux-drive-review
agent: fd-schema-evolution
plan: docs/plans/2026-03-26-event-envelope-v2.md
bead: Demarch-og7m.2.1
status: complete
findings: 7
---

# Schema Evolution & Wire Compatibility Review — EventEnvelope v2

**Plan:** `docs/plans/2026-03-26-event-envelope-v2.md`
**v1 source of truth:** `core/intercore/internal/event/envelope.go`
**Duplicate:** `core/intercore/internal/phase/event_envelope.go`
**Storage layer:** `core/intercore/internal/event/store.go` (scanEvents, AddDispatchEvent, AddCoordinationEvent)
**Downstream consumer:** `core/intercore/internal/replay/reconstruct.go` (BuildTimeline reads ArtifactRefs)
**Review date:** 2026-03-26
**Reviewer:** fd-schema-evolution (distributed systems / wire compat)

---

## Finding 1: v1 fallback silently drops 5 of 10 live fields

**Severity: P0**

The v1 `EventEnvelope` has 10 fields:

| # | Field | JSON key | v2 top-level? | v2 Payload? | Dropped? |
|---|---|---|---|---|---|
| 1 | PolicyVersion | `policy_version` | No | No | **YES** |
| 2 | CallerIdentity | `caller_identity` | Yes | -- | No |
| 3 | CapabilityScope | `capability_scope` | No | No | **YES** |
| 4 | TraceID | `trace_id` | Yes | -- | No |
| 5 | SpanID | `span_id` | Yes | -- | No |
| 6 | ParentSpanID | `parent_span_id` | Yes | -- | No |
| 7 | InputArtifactRefs | `input_artifact_refs` | No | No | **YES** |
| 8 | OutputArtifactRefs | `output_artifact_refs` | No | No | **YES** |
| 9 | RequestedSandbox | `requested_sandbox` | No | DispatchPayload only | **YES (partial)** |
| 10 | EffectiveSandbox | `effective_sandbox` | No | DispatchPayload only | **YES (partial)** |

`ParseEnvelopeV2JSON` for v1 input (lines 155-164 of plan) maps only 4 fields (`TraceID`, `SpanID`, `ParentSpanID`, `CallerIdentity`) and explicitly comments "v1 source-specific data is not migrated into Payload." The remaining fields are silently lost.

**Of the 5 dropped fields, 3 are actively consumed in production:**

1. **`InputArtifactRefs` + `OutputArtifactRefs`** — Read by `replay/reconstruct.go:49-50` (`BuildTimeline`) to populate `Decision.ArtifactRefs`. Dropping these breaks replay timeline reconstruction for all existing v1 events.

2. **`RequestedSandbox` + `EffectiveSandbox`** — Asserted non-empty in `store_test.go:91-96`. These are populated from the `dispatches` table and represent real security-relevant sandbox provenance. While they appear in `DispatchPayload`, the v1 fallback path does not construct a `DispatchPayload` from the v1 data, so they are lost.

3. **`PolicyVersion`** — Written as `"phase-machine/v1"`, `"dispatch-lifecycle/v2"`, `"coordination/v1"` by all three envelope constructors. This is the schema self-description field. While no code reads it programmatically today, dropping it from the v2 representation eliminates the ability to audit which policy version governed an event.

4. **`CapabilityScope`** — Written as `"run:<id>"`, `"dispatch:<id>"`, `"scope:<scope>"` by all constructors. No current reader, but this is a live field in every stored envelope.

**Remediation:** The v1 fallback must either:
(a) Preserve all v1 fields as a `json.RawMessage` payload (round-trip safe), or
(b) Map `InputArtifactRefs`, `OutputArtifactRefs`, `RequestedSandbox`, `EffectiveSandbox`, `PolicyVersion`, `CapabilityScope` into structured payload or additional v2 top-level fields.

Option (a) is simplest: `Payload: json.RawMessage(raw)` preserves all v1 data and lets `ParsePayload[EventEnvelope]` recover it.

---

## Finding 2: scanEvents still calls ParseEnvelopeJSON (v1), not ParseEnvelopeV2JSON

**Severity: P1**

`store.go:547` reads envelope JSON from the database via `ParseEnvelopeJSON`, which returns `*EventEnvelope` (v1 type). The `Event.Envelope` field (event.go:57) is typed `*EventEnvelope`, not `*EventEnvelopeV2`.

The plan creates v2 types and helpers but does not update:
- `scanEvents` to use `ParseEnvelopeV2JSON`
- `Event.Envelope` field type from `*EventEnvelope` to `*EventEnvelopeV2`
- `replay/reconstruct.go` to read from the v2 structure

This is acknowledged in the plan scope ("No writers changed — this is schema + helpers only"), but the plan also claims test case 5-6 will "parse actual v1 JSON (phase-machine format) -> verify Version=1 + core fields." The tests only verify `ParseEnvelopeV2JSON` in isolation. No integration test verifies that `scanEvents` -> `ParseEnvelopeV2JSON` -> `BuildTimeline` preserves artifact refs. When `scanEvents` is eventually switched to v2 parsing (og7m.2.2), the artifact ref loss from Finding 1 will become a live regression.

**Remediation:** Either:
(a) Add a "migration readiness" test that calls `ParseEnvelopeV2JSON` on real v1 JSON and asserts all 10 fields are recoverable (forcing Finding 1 to be fixed before merge), or
(b) Document in the plan that og7m.2.2 (writer migration) MUST fix the v1 fallback field mapping before switching `scanEvents` to v2 parsing.

---

## Finding 3: v2 marshal output with `"v":2` is safe for v1 parser but payload is silently dropped

**Severity: P2**

When v2-marshaled JSON is stored and later read by the current `ParseEnvelopeJSON` (v1 parser), Go's `encoding/json` ignores unknown fields by default. The v1 parser will:
- Ignore `"v": 2` (no matching struct field) -- safe
- Ignore `"payload": {...}` (no matching struct field) -- data loss but no error
- Read `"trace_id"`, `"span_id"`, `"parent_span_id"`, `"caller_identity"` -- correct
- Find all other v1 fields empty (v2 moves them to payload) -- `IsZero()` may return true

The critical issue: if a v2 envelope has only tracing fields + payload (the common case), and `CallerIdentity` is omitted, then `IsZero()` returns true and `ParseEnvelopeJSON` returns `nil`. The event's `Envelope` field becomes nil, and `BuildTimeline` produces no artifact refs. This is a data-loss path during mixed-version operation.

Concretely, if og7m.2.2 starts writing v2 envelopes while `scanEvents` still uses `ParseEnvelopeJSON`, any v2 envelope where `CallerIdentity` is empty will be parsed as "zero" and discarded.

**Remediation:** The v2 struct should always populate `CallerIdentity` (it's in every v1 envelope today), and the plan should document this as a v2 writer invariant. Alternatively, fix this at the reader side by switching `scanEvents` to `ParseEnvelopeV2JSON` in the same bead as the writer migration.

---

## Finding 4: Version discriminator `"v"` is detectable before typed decode -- PASS with caveat

**Severity: P3**

The plan's version probe (lines 130-137) uses a minimal struct to read `"v"` before full decode. This is the correct pattern: it avoids allocating the full v2 struct for v1 input. The probe handles:
- `"v": 2` -- v2 path
- `"v": 1` -- v2 path (technically; `*probe.V >= 2` is false, falls to v1)
- `"v"` absent -- v1 path (probe.V is nil)
- `"v": null` -- v1 path (json.Unmarshal sets pointer to nil for JSON null)

**Caveat:** The discriminator field name `"v"` is short and collision-prone. If any future payload type includes a top-level `"v"` key (e.g., a "version" field in a nested payload), it won't collide because `Payload` is `json.RawMessage` and only the outer object is probed. But if the envelope JSON is ever embedded inside another JSON object (envelope-in-envelope), the probe would need to be path-aware. This is a theoretical concern only; the current architecture stores envelopes as top-level column values.

No remediation needed for current scope.

---

## Finding 5: `omitempty` coverage on v2-only fields is correct

**Severity: P3**

All v2-only fields have `omitempty`:
- `TraceID` -- `omitempty`
- `SpanID` -- `omitempty`
- `ParentSpanID` -- `omitempty`
- `CallerIdentity` -- `omitempty`
- `Payload` -- `omitempty` (json.RawMessage nil/empty omitted)

The `Version` field (`"v"`) does NOT have `omitempty`, which is correct: it should always be present in v2 output. A v1 reader encountering `"v": 2` will ignore it (unknown field).

One subtlety: `json.RawMessage` with value `null` is NOT empty for `omitempty` -- `json.Marshal` will emit `"payload":null`. This would be harmless to v1 readers (unknown field ignored) but is aesthetically noisy. The plan's `MarshalPayload` returns `nil, nil` for nil input, and `MarshalEnvelopeV2JSON` doesn't set Payload for nil, so in practice `Payload` will be either nil (omitted) or valid JSON. This is correct.

No remediation needed.

---

## Finding 6: phaseEventEnvelope duplicate lacks RequestedSandbox/EffectiveSandbox -- pre-existing divergence

**Severity: P2**

`phase/event_envelope.go` defines `phaseEventEnvelope` as a copy of `EventEnvelope` but is missing the `RequestedSandbox` and `EffectiveSandbox` fields (only 8 fields vs 10). This is a pre-existing bug, not introduced by the v2 plan, but it becomes load-bearing during migration:

- The phase package writes its own envelope JSON via `defaultPhaseEnvelopeJSON`, bypassing `event.MarshalEnvelopeJSON`
- When `scanEvents` reads phase events and parses them as `EventEnvelope`, the sandbox fields are absent (always empty)
- The v2 plan does not address this divergence -- it will persist into v2

The v2 plan's Task 1 creates `PhasePayload` with `FromPhase`/`ToPhase` but does not consolidate the duplicate `phaseEventEnvelope`. The phase package will continue writing v1-shaped JSON via its own struct while the event package defines the canonical v2 types. This creates two parallel serialization paths that must both be migrated in og7m.2.2.

**Remediation:** The plan (or og7m.2.2) should explicitly call out that `phase/event_envelope.go` must be replaced by the canonical v2 marshal path. Add a TODO or deprecation comment in the current bead.

---

## Finding 7: MarshalEnvelopeV2JSON auto-promotes Version=0 to Version=2 -- correct but fragile

**Severity: P3**

Lines 110-112 of the plan: `if e.Version == 0 { e.Version = 2 }`. This means a caller constructing `EventEnvelopeV2{}` without setting Version gets v2 automatically. This is a reasonable default, but it mutates the input struct (pointer receiver semantics via the `*EventEnvelopeV2` parameter). If a caller reuses the struct after marshaling, it will have `Version=2` set as a side effect.

The v1 fallback sets `Version=1` on the returned struct (correct), but if someone constructs an `EventEnvelopeV2{Version: 1}` and calls `MarshalEnvelopeV2JSON`, it will serialize as `"v":1` -- which is then parseable by the v2 parser's v1 fallback path. This creates a loop: v2 marshal with Version=1 -> v2 parse -> v1 fallback -> loses payload fields (per Finding 1). This is unlikely in practice but the API permits it.

**Remediation:** Consider returning an error if `Version == 1` is passed to `MarshalEnvelopeV2JSON`, or document that callers must never set Version=1 explicitly.

---

## Summary

| # | Finding | Severity | Blocks merge? |
|---|---|---|---|
| 1 | v1 fallback drops 5/10 fields including live ArtifactRefs | P0 | Yes |
| 2 | scanEvents not updated; no integration test for field preservation | P1 | No (acknowledged scope) but needs og7m.2.2 gate |
| 3 | v2 output parsed by v1 reader may trigger IsZero discard | P2 | No (future risk, needs writer invariant) |
| 4 | Version discriminator design is correct | P3 | No |
| 5 | omitempty coverage is correct | P3 | No |
| 6 | phaseEventEnvelope duplicate diverges from canonical type | P2 | No (pre-existing, needs migration note) |
| 7 | MarshalEnvelopeV2JSON mutates input + permits Version=1 | P3 | No (minor API hygiene) |

**Verdict:** The plan has one P0 blocking issue: the v1 fallback path in `ParseEnvelopeV2JSON` silently discards `InputArtifactRefs`, `OutputArtifactRefs`, `RequestedSandbox`, `EffectiveSandbox`, `PolicyVersion`, and `CapabilityScope`. The first two are actively consumed by `replay/reconstruct.go` for timeline reconstruction. The simplest fix is to store the entire v1 JSON blob as the `Payload` field when parsing v1 input, allowing `ParsePayload[EventEnvelope]` to recover all original fields.

<!-- flux-drive:complete -->
