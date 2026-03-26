---
artifact_type: plan
bead: Demarch-og7m.2.1
stage: plan-reviewed
review_status: revised after 7-agent flux-drive (architecture, correctness, quality, schema-evolution, envelope-semantics, payload-typing, json-schema-gen)
requirements:
  - EventEnvelopeV2 struct with version field + RawMessage payload
  - Source payload types (Phase, Dispatch, Coordination)
  - Marshal/Parse with v1 fallback
  - Regenerated JSON Schema
  - Round-trip + v1 compat tests
---
# EventEnvelope v2 Schema — Implementation Plan

**Bead:** Demarch-og7m.2.1
**Goal:** Define the v2 envelope schema, payload types, and marshal/parse functions. V1 remains unchanged — this is schema-only, no writer changes.

**Architecture:** All Go in `core/intercore/internal/event/`. Schema generation via `go generate ./contracts/...` (same pipeline used for F2). No DB changes — `envelope_json` column stores JSON blobs, schema change is invisible to SQLite.

**Honest scope:** This defines types and helpers only. No event writers change to emit v2 in this bead — that's og7m.2.2. The v1 fallback in `ParseEnvelopeV2JSON` is the bridge that lets readers handle both during migration.

---

## Must-Haves

**Truths** (observable behaviors):
- `ParseEnvelopeV2JSON(v1_json)` returns `EventEnvelopeV2` with `Version=1` and populated core fields
- `MarshalEnvelopeV2JSON` → `ParseEnvelopeV2JSON` round-trips for each payload type
- `go generate ./contracts/...` produces updated `event-envelope.json` with v2 shape
- All existing tests pass unchanged

**Artifacts:**
- `core/intercore/internal/event/envelope_v2.go` — new file with v2 types + helpers
- `core/intercore/internal/event/envelope_v2_test.go` — new file with tests
- `core/intercore/contracts/events/event-envelope.json` — regenerated
- `core/intercore/contracts/events/README.md` — updated with v2 docs

---

### Task 1: Define EventEnvelopeV2 and payload types

**Files:**
- Create: `core/intercore/internal/event/envelope_v2.go`

**Step 1: Create envelope_v2.go**

```go
package event

import (
	"encoding/json"
	"fmt"
)

// EventEnvelopeV2 is the v2 envelope schema for the unified event stream.
// Core tracing fields are top-level; source-specific data is in Payload.
//
// Version field: 2 for v2 envelopes. ParseEnvelopeV2JSON sets Version=1
// when parsing legacy v1 envelopes that lack the field.
type EventEnvelopeV2 struct {
	Version        int             `json:"v"                          jsonschema:"enum=1,enum=2"`
	TraceID        string          `json:"trace_id,omitempty"`
	SpanID         string          `json:"span_id,omitempty"`
	ParentSpanID   string          `json:"parent_span_id,omitempty"`
	CallerIdentity string          `json:"caller_identity,omitempty"`
	Payload        json.RawMessage `json:"payload,omitempty"`
}

// PhasePayload carries phase-specific envelope data.
type PhasePayload struct {
	FromPhase string `json:"from_phase"`
	ToPhase   string `json:"to_phase"`
}

// DispatchPayload carries dispatch-specific envelope data.
type DispatchPayload struct {
	DispatchID       string `json:"dispatch_id,omitempty"`
	FromStatus       string `json:"from_status,omitempty"`
	ToStatus         string `json:"to_status,omitempty"`
	RequestedSandbox string `json:"requested_sandbox,omitempty"`
	EffectiveSandbox string `json:"effective_sandbox,omitempty"`
}

// CoordinationPayload carries coordination-specific envelope data.
type CoordinationPayload struct {
	LockID  string `json:"lock_id,omitempty"`
	Pattern string `json:"pattern,omitempty"`
	Scope   string `json:"scope,omitempty"`
}
```

### Task 2: Add marshal/parse helpers with v1 fallback

**Step 1: Add to envelope_v2.go (continued)**

```go
// MarshalPayload marshals a typed payload into json.RawMessage.
func MarshalPayload(v any) (json.RawMessage, error) {
	if v == nil {
		return nil, nil
	}
	return json.Marshal(v)
}

// MarshalEnvelopeV2JSON serializes a v2 envelope for database storage.
// Returns nil when the envelope is nil/empty.
func MarshalEnvelopeV2JSON(e *EventEnvelopeV2) (*string, error) {
	if e == nil {
		return nil, nil
	}
	if e.Version == 0 {
		e.Version = 2
	}
	b, err := json.Marshal(e)
	if err != nil {
		return nil, err
	}
	s := string(b)
	return &s, nil
}

// ParseEnvelopeV2JSON decodes envelope JSON, handling both v1 and v2 formats.
// For v1 envelopes (no "v" field), maps v1 fields to v2 structure with Version=1.
// Returns nil for empty input.
func ParseEnvelopeV2JSON(raw string) (*EventEnvelopeV2, error) {
	if raw == "" {
		return nil, nil
	}

	// Probe version field first
	var probe struct {
		V *int `json:"v"`
	}
	if err := json.Unmarshal([]byte(raw), &probe); err != nil {
		return nil, fmt.Errorf("parse envelope version: %w", err)
	}

	if probe.V != nil && *probe.V >= 2 {
		// Native v2
		var e EventEnvelopeV2
		if err := json.Unmarshal([]byte(raw), &e); err != nil {
			return nil, fmt.Errorf("parse envelope v2: %w", err)
		}
		return &e, nil
	}

	// v1 fallback: parse as v1, map to v2
	var v1 EventEnvelope
	if err := json.Unmarshal([]byte(raw), &v1); err != nil {
		return nil, fmt.Errorf("parse envelope v1: %w", err)
	}
	if v1.IsZero() {
		return nil, nil
	}

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
}

// ParsePayload unmarshals the envelope payload into a typed struct.
func ParsePayload[T any](e *EventEnvelopeV2) (*T, error) {
	if e == nil || len(e.Payload) == 0 {
		return nil, nil
	}
	var v T
	if err := json.Unmarshal(e.Payload, &v); err != nil {
		return nil, fmt.Errorf("parse payload: %w", err)
	}
	return &v, nil
}
```

### Task 3: Register v2 types in contract registry

**Files:**
- Modify: `core/intercore/contracts/registry.go`

Add to `EventContracts`:
```go
{Name: "event-envelope-v2", Instance: event.EventEnvelopeV2{}},
{Name: "phase-payload", Instance: event.PhasePayload{}},
{Name: "dispatch-payload", Instance: event.DispatchPayload{}},
{Name: "coordination-payload", Instance: event.CoordinationPayload{}},
```

Keep `event-envelope` (v1) in registry for backward compat until og7m.2.6.

### Task 4: Add tests

**Files:**
- Create: `core/intercore/internal/event/envelope_v2_test.go`

Test cases:
1. **Round-trip**: marshal v2 with PhasePayload → parse → verify all fields
2. **Round-trip**: marshal v2 with DispatchPayload → parse → verify sandbox fields
3. **Round-trip**: marshal v2 with CoordinationPayload → parse → verify
4. **Round-trip**: marshal v2 with nil payload → parse → verify core fields only
5. **v1 fallback**: parse actual v1 JSON (phase-machine format) → verify Version=1 + core fields
6. **v1 fallback**: parse actual v1 JSON (dispatch-lifecycle format) → verify Version=1
7. **Empty input**: parse "" → nil, nil
8. **MarshalPayload nil**: returns nil
9. **ParsePayload generic**: round-trip typed payload extraction

### Task 5: Regenerate schemas and update README

```bash
cd core/intercore && go generate ./contracts/...
```

Update `contracts/events/README.md`:
- Add v2 envelope schema to the Schemas list
- Add payload type schemas
- Document v1→v2 migration under Versioning section

### Task 6: Build, test, commit

```bash
cd core/intercore && go build ./... && go test ./internal/event/ -v -count=1
```

Commit from intercore subproject:
```
feat(events): EventEnvelope v2 schema with typed payloads

Defines EventEnvelopeV2 with version discriminator, core tracing fields,
and json.RawMessage payload for source-specific data. Includes typed
payload structs (Phase, Dispatch, Coordination) and marshal/parse helpers
with v1 read fallback.

No writers changed — this is schema + helpers only. Writers migrate to v2
in og7m.2.2; v1 removal in og7m.2.6.

Fixes Demarch-og7m.2.1
```

<verify>
- run: `cd core/intercore && go build ./...`
  expect: exit 0
- run: `cd core/intercore && go test ./internal/event/ -v -count=1 -run TestEnvelopeV2`
  expect: contains "PASS"
- run: `grep '"v"' contracts/events/event-envelope-v2.json`
  expect: contains version field
- run: `cd core/intercore && go test ./contracts/ -v -count=1`
  expect: contains "PASS"
</verify>
