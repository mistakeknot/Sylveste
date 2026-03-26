---
agent: fd-envelope-semantics
status: needs-changes
findings: 7
reviewed: docs/plans/2026-03-26-event-envelope-v2.md
context:
  - docs/brainstorms/2026-03-26-event-envelope-v2.md
  - core/intercore/internal/event/envelope.go
  - core/intercore/internal/event/event.go
  - core/intercore/internal/event/store.go
  - core/intercore/internal/phase/event_envelope.go
  - core/intercore/internal/replay/reconstruct.go
---
# Envelope Semantics Review: EventEnvelope v2 Plan

**Reviewer:** fd-envelope-semantics
**Focus:** Field-level audit of v1-to-v2 migration completeness, event discriminator uniqueness, observability metadata sufficiency, overloaded field decomposition, and envelope size budget.

---

### Findings Index

| SEVERITY | ID | Title |
|----------|----|-------|
| P1 | S1 | PhasePayload duplicates Event.FromState/ToState -- semantic double-write |
| P1 | S2 | v1 fallback drops source-specific data silently -- no degradation signal |
| P2 | S3 | CapabilityScope dropped without replacement -- loses authorization context |
| P2 | S4 | Replay reconstruct reads ArtifactRefs -- migration path unaddressed |
| P2 | S5 | CoordinationPayload lacks owner field -- coordination events lose actor identity |
| P3 | S6 | PolicyVersion dropped but no equivalent version-per-source discriminator in payloads |
| P3 | S7 | Envelope payload has no type discriminator -- readers must correlate with Event.Source |

**Verdict: needs-changes** (2 P1, 3 P2, 2 P3)

---

## Finding S1

**Severity: P1 -- PhasePayload duplicates Event.FromState/ToState**

The v2 `PhasePayload` defines `from_phase` and `to_phase` fields. These carry the same values already stored in the `Event` struct's top-level `FromState` and `ToState` fields (populated from `phase_events.from_phase` and `phase_events.to_phase` by the `ListEvents` UNION ALL query at store.go:116-117).

Similarly, `DispatchPayload.FromStatus`/`ToStatus` duplicate `Event.FromState`/`ToState` (populated from `dispatch_events.from_status`/`to_status` at store.go:126).

This creates a semantic double-write: the same transition data exists in two places with different field names. When og7m.2.2 has writers emit v2 payloads, consumers must decide which source of truth to read. If the two ever diverge (a writer bug populates the payload but the table column holds different values), debugging becomes significantly harder.

**Recommendation:** Either (a) remove `from_phase`/`to_phase` from `PhasePayload` and `from_status`/`to_status` from `DispatchPayload` since `Event.FromState`/`ToState` already carry this data, or (b) document explicitly that the payload fields are the canonical source and `Event.FromState`/`ToState` are denormalized copies for query convenience, with a single writer function that populates both from one input. Option (a) is cleaner -- it keeps payloads for source-specific data that is NOT already on the Event struct.

---

## Finding S2

**Severity: P1 -- v1 fallback drops source-specific data silently**

`ParseEnvelopeV2JSON` maps v1 envelopes to v2 with `Version=1`, preserving only core tracing fields (trace/span/parent/caller). The comment on line 161-163 of the plan says: "v1 source-specific data is not migrated into Payload -- readers of Version=1 envelopes should use the Event's top-level fields for source context."

The problem: v1 envelopes carry `InputArtifactRefs`, `OutputArtifactRefs`, `RequestedSandbox`, `EffectiveSandbox`, `CapabilityScope`, and `PolicyVersion`. After `ParseEnvelopeV2JSON` runs, these fields are silently discarded with no signal to the caller. There is no `Degraded bool` flag, no log, and no metric. A consumer calling `ParsePayload[DispatchPayload](env)` on a Version=1 envelope will get `nil` (no payload), with no way to distinguish "this event had sandbox data in v1 format that was dropped" from "this event never had sandbox data."

During the migration window (og7m.2.1 through og7m.2.6), both v1 and v2 envelopes coexist in the `envelope_json` column. Consumers that switch to v2 parsing early will lose access to v1 source-specific data unless they add their own v1 fallback logic, defeating the purpose of a unified parse function.

**Recommendation:** Either (a) have the v1 fallback populate `Payload` by detecting `PolicyVersion` and constructing the appropriate typed payload from v1 fields (this is the whole point of a compat shim), or (b) at minimum return a sentinel like `Version=1` and document that consumers MUST fall back to `ParseEnvelopeJSON` for source-specific data when `Version==1 && Payload==nil`. Option (a) is strongly preferred -- it makes the v2 parser a true drop-in replacement.

---

## Finding S3

**Severity: P2 -- CapabilityScope dropped without replacement**

The brainstorm (line 56) notes `CapabilityScope` is "derivable from TraceID." In practice, `CapabilityScope` carries structured authorization context:
- Phase: `"run:{runID}"` (store.go via phase/event_envelope.go:38-39)
- Dispatch: `"run:{runID}"` or `"dispatch:{dispatchID}"` (store.go:574-576)
- Coordination: `"scope:{scope}"` (store.go:638)

`TraceID` carries `runID` (or `lockID` for coordination), but does NOT carry the dispatch-scoped `"dispatch:{dispatchID}"` variant or the `"scope:{scope}"` variant. These are not derivable from TraceID alone. Dropping `CapabilityScope` loses the ability to answer "what authorization boundary was this event written under?" during post-mortem.

**Recommendation:** Either (a) add `CapabilityScope` to the v2 core fields (it is genuinely cross-source, not source-specific), or (b) move it into each payload type where it varies (e.g., `DispatchPayload.CapabilityScope`), or (c) document in the plan that this data is deliberately being dropped with a justification that no current consumer reads it. If (c), verify no consumer reads it -- currently no Go code outside the writers references `CapabilityScope`, so the drop may be safe, but it closes the door on future audit tooling.

---

## Finding S4

**Severity: P2 -- Replay reconstruct reads ArtifactRefs -- migration path unaddressed**

`internal/replay/reconstruct.go:49-50` reads `e.Envelope.InputArtifactRefs` and `e.Envelope.OutputArtifactRefs` to populate `Decision.ArtifactRefs` in the replay timeline. This is the only active consumer of these v1 fields beyond the writers themselves.

The v2 plan drops `InputArtifactRefs`/`OutputArtifactRefs` from the envelope, moving the underlying data into typed payloads (`PhasePayload.FromPhase`, `DispatchPayload.FromStatus`, `CoordinationPayload.LockID`/`Pattern`). But the plan does not address how `reconstruct.go` will get artifact refs after the migration:

1. During the v1/v2 coexistence window: `reconstruct.go` reads `Event.Envelope` (v1 type). If `scanEvents` switches to `ParseEnvelopeV2JSON`, the `Event.Envelope` field is still `*EventEnvelope` (v1) -- so `reconstruct.go` would need updating to read from `EventEnvelopeV2.Payload`.
2. After v1 removal (og7m.2.6): the artifact ref data is in payloads, but `reconstruct.go` does not know which payload type to deserialize.

The brainstorm identifies the overloading problem (artifact refs hold phase names, status strings, lock IDs depending on source) but the plan does not specify when or how `reconstruct.go` will be migrated.

**Recommendation:** Add a note in the plan (or a child bead) specifying that `reconstruct.go` must be updated as part of og7m.2.5 (reader migration) to extract artifact-equivalent data from v2 payloads based on `Event.Source`. This is not blocking for og7m.2.1 (schema-only) but should be tracked.

---

## Finding S5

**Severity: P2 -- CoordinationPayload lacks owner field**

The v2 `CoordinationPayload` has `lock_id`, `pattern`, and `scope`. In v1, the coordination UNION ALL query maps `owner AS from_state` (store.go:136), meaning the lock owner is available via `Event.FromState`. However, `CoordinationPayload` was designed to carry "coordination-specific envelope data" -- and the lock owner is arguably the most important coordination-specific datum.

More critically, for coordination events, the `Event.FromState` mapping (`owner AS from_state`) is a semantic stretch -- `FromState` is documented as "from_phase, from_status, owner, finding_id" depending on source. This is exactly the kind of overloading the v2 design aims to fix. If `CoordinationPayload` is going to exist, it should carry `Owner string` so that consumers reading v2 payloads get the lock owner from a properly named field rather than relying on the overloaded `Event.FromState`.

**Recommendation:** Add `Owner string json:"owner,omitempty"` to `CoordinationPayload`.

---

## Finding S6

**Severity: P3 -- PolicyVersion dropped but no equivalent per-source version in payloads**

`PolicyVersion` served as a source-specific schema version (`"phase-machine/v1"`, `"dispatch-lifecycle/v2"`, `"coordination/v1"`). The v2 envelope's `Version` field is an envelope-level version (always 2 for v2), not a source-specific schema version. If the `PhasePayload` schema changes in the future, there is no field to distinguish `PhasePayload` v1 from v2.

Today this is not a problem because v2 defines the first version of each payload type. It becomes a problem if any payload type needs a breaking change -- the envelope `Version` cannot be bumped for a single source without affecting all sources.

**Recommendation:** This is informational for now. If payload types are expected to evolve independently, add an optional `SchemaVersion int` field to each payload type. If payloads will only change in lockstep with the envelope version, document that assumption.

---

## Finding S7

**Severity: P3 -- Envelope payload has no type discriminator**

`EventEnvelopeV2.Payload` is `json.RawMessage` with no `type` field. Readers must know the `Event.Source` to determine whether to deserialize as `PhasePayload`, `DispatchPayload`, or `CoordinationPayload`. This coupling is acceptable when the envelope is always read alongside its parent `Event`, but it means the envelope JSON blob is not self-describing.

This matters for:
1. **Schema validation:** The generated JSON Schema for `event-envelope-v2.json` cannot express "payload is one of these three types depending on source." It will describe payload as `json.RawMessage` (any JSON), which weakens contract enforcement.
2. **Debug tooling:** A human examining raw `envelope_json` in SQLite cannot determine the payload type without joining to the parent events table.
3. **Future decoupling:** If envelopes are ever serialized or transmitted independently of their parent Event (e.g., to an external audit system), the payload becomes uninterpretable.

The brainstorm's Option B (discriminated union with `Phase *PhaseEnvelopeData`, `Dispatch *DispatchEnvelopeData`) would have solved this but was rejected for extensibility reasons. A lighter fix: add a `payload_type` string field to the envelope (`"phase"`, `"dispatch"`, `"coordination"`) that matches `Event.Source` when populated.

**Recommendation:** Consider adding `PayloadType string json:"payload_type,omitempty"` to `EventEnvelopeV2`. It costs one small field but makes the blob self-describing. If rejected, document that envelope JSON is intentionally not self-describing and must always be read with its Event context.

---

### Field Disposition Audit

Complete v1-to-v2 field tracking:

| v1 Field | v2 Disposition | Status |
|----------|---------------|--------|
| PolicyVersion | Dropped (brainstorm says "redundant with Version") | **Lossy** -- see S6. Source-specific versioning lost. |
| CallerIdentity | Retained as top-level `caller_identity` | Clean |
| CapabilityScope | Dropped ("derivable from TraceID") | **Lossy** -- see S3. Not fully derivable. |
| TraceID | Retained as top-level `trace_id` | Clean |
| SpanID | Retained as top-level `span_id` | Clean |
| ParentSpanID | Retained as top-level `parent_span_id` | Clean |
| InputArtifactRefs | Dropped; data split into payload FromPhase/FromStatus/Pattern | **Lossy during migration** -- see S2, S4. |
| OutputArtifactRefs | Dropped; data split into payload ToPhase/ToStatus/LockID | **Lossy during migration** -- see S2, S4. |
| RequestedSandbox | Moved to DispatchPayload | Clean |
| EffectiveSandbox | Moved to DispatchPayload | Clean |

### Discriminator Analysis

Event routing uses `Event.Source` (7 values) + `Event.Type` (per-source: "advance", "skip", "block", "status_change", "lock_acquired", "disagreement_resolved", etc.). This combination is sufficient for unambiguous routing -- each `(Source, Type)` pair identifies a unique event kind. The v2 envelope does not add or remove discriminators; routing remains on the Event struct, not the envelope. This is correct -- the envelope is metadata, not a routing key.

### Observability Assessment

The v2 core fields (trace_id, span_id, parent_span_id, caller_identity) are sufficient for distributed tracing and post-mortem correlation. The `CallerIdentity` field preserves audit attribution. The gap is `CapabilityScope` (S3) which provides authorization boundary context useful for security post-mortems.

### Envelope Size Budget

The v2 design correctly moves source-specific data into `Payload`, keeping the top-level envelope lean (5 fields: v, trace_id, span_id, parent_span_id, caller_identity + payload blob). This is a good structural improvement over v1's 10 flat fields. The only concern is payload duplication with Event.FromState/ToState (S1) which inflates envelope size without adding information.

<!-- flux-drive:complete -->
