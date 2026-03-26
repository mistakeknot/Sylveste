---
artifact_type: plan
bead: Demarch-og7m
stage: plan-reviewed
requirements:
  - F1: Event pipeline nucleation fix (.17)
  - F2: Event schema contract (.21)
  - F3: Closed-loop calibration stage reporting (.23)
review_status: revised after flux-drive (architecture, correctness, quality, user/product)
---
# Monorepo Consolidation Batch 4 — Implementation Plan (Revised)

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Demarch-og7m
**Goal:** Prepare the event pipeline for unification (fix nucleation + enrich generated schema + add source validation) and add observability for PHILOSOPHY.md's closed-loop maturity gap.

**Architecture:** F1 and F2 are Go in L1 Intercore (event package). F3 is YAML in L2 Clavain + bash in /doctor. F1 and F2 share the event package but don't block each other. F3 is fully independent.

**Tech Stack:** Go 1.22 (intercore, modernc.org/sqlite), bash 5.x (Clavain doctor), YAML (calibration stages)

**Honest scope:** F1 is a preventive fix for anticipated scale (5+ agents), not a critical production defect. F2 enriches existing generated schemas and adds source validation — preparatory for .2.1, not standalone consumer protection. F3 delivers a machine-readable maturity artifact and /doctor visibility for sprint planning.

---

## Must-Haves

**Truths** (observable behaviors):
- ListEvents with limit=20 returns events from all active sources, not just the highest-volume one
- `Event.Validate()` rejects unknown Source values
- Generated `event.json` schema includes `source` enum constraint (via `go generate`)
- `/doctor --scope calibration` shows calibration stage for all 6 PHILOSOPHY.md domains

**Artifacts** (files with specific exports):
- [`core/intercore/internal/event/store.go`] ListEvents + ListAllEvents use per-source sub-limits; coordination cursor fixed
- [`core/intercore/internal/event/event.go`] exports `Validate()` method; `Source` has `jsonschema:"enum=..."` struct tag
- [`core/intercore/contracts/events/event.json`] regenerated with source enum constraint
- [`core/intercore/contracts/events/README.md`] Event vocabulary reference
- [`docs/calibration-stages.yaml`] 6-domain stage definitions (not in core/intercore — L2 operational policy)
- [`os/Clavain/commands/doctor.md`] includes calibration stage check section

**Key Links:**
- F1 per-source sub-limits applied inside each SELECT arm; coordination cursor now uses `id > ?` like other sources
- F2 enriches existing generated schemas via struct tags — no hand-authored `.schema.json` files
- F3 calibration-stages.yaml lives in `docs/` (not L1 contracts) — operational policy, not type contract

---

### Task 1: Event Pipeline Nucleation Fix (F1/.17)

**Files:**
- Modify: `core/intercore/internal/event/store.go:95-186`
- Modify: `core/intercore/internal/event/store_test.go`

**Step 1: Add sinceCoordinationID parameter and refactor ListEvents**

The current query has a pre-existing bug: coordination events use `id > 0` (hardcoded, no cursor). With per-source sub-limits, this means perSource old coordination events are re-fetched every poll. Fix by adding `sinceCoordinationID int64` to the signature.

In `store.go`, replace the `ListEvents` method:

```go
// ListEvents returns unified events for a run, merging phase_events,
// dispatch_events, coordination_events, and review_events, ordered by
// timestamp. Uses per-source sub-limits to prevent high-volume sources
// from crowding out low-volume ones. Discovery events are excluded
// (system-level, no run_id column — use ListAllEvents for those).
//
// Note: Per-source sub-limits mean each source gets at most ceil(limit/4)
// rows. Callers debugging a single source should use the source-specific
// query methods instead. Polling callers must loop until fewer than limit
// rows are returned to guarantee all events are drained.
func (s *Store) ListEvents(ctx context.Context, runID string, sincePhaseID, sinceDispatchID, sinceCoordinationID, sinceReviewID int64, limit int) ([]Event, error) {
	if limit <= 0 {
		limit = 1000
	}

	// Per-source sub-limit guarantees each source gets representation.
	// 4 sources in run-scoped query (discovery excluded — no run_id column).
	perSource := perSourceLimit(limit, 4)

	rows, err := s.db.QueryContext(ctx, `
		SELECT id, run_id, source, event_type, from_state, to_state, reason, envelope_json, created_at FROM (
			SELECT id, run_id, 'phase' AS source, event_type, from_phase AS from_state, to_phase AS to_state,
				COALESCE(reason, '') AS reason, COALESCE(envelope_json, '') AS envelope_json, created_at
			FROM phase_events
			WHERE run_id = ? AND id > ?
			ORDER BY created_at ASC, id ASC
			LIMIT ?
		)
		UNION ALL
		SELECT id, run_id, source, event_type, from_state, to_state, reason, envelope_json, created_at FROM (
			SELECT id, COALESCE(run_id, '') AS run_id, 'dispatch' AS source, event_type,
				from_status AS from_state, to_status AS to_state, COALESCE(reason, '') AS reason,
				COALESCE(envelope_json, '') AS envelope_json, created_at
			FROM dispatch_events
			WHERE (run_id = ? OR ? = '') AND id > ?
			ORDER BY created_at ASC, id ASC
			LIMIT ?
		)
		UNION ALL
		SELECT id, run_id, source, event_type, from_state, to_state, reason, envelope_json, created_at FROM (
			SELECT id, COALESCE(run_id, '') AS run_id, 'coordination' AS source, event_type,
				owner AS from_state, pattern AS to_state, COALESCE(reason, '') AS reason,
				COALESCE(envelope_json, '') AS envelope_json, created_at
			FROM coordination_events
			WHERE (run_id = ? OR ? = '') AND id > ?
			ORDER BY created_at ASC, id ASC
			LIMIT ?
		)
		UNION ALL
		SELECT id, run_id, source, event_type, from_state, to_state, reason, envelope_json, created_at FROM (
			SELECT id, COALESCE(run_id, '') AS run_id, 'review' AS source, 'disagreement_resolved' AS event_type,
				finding_id AS from_state, resolution AS to_state, COALESCE(agents_json, '{}') AS reason,
				'' AS envelope_json, created_at
			FROM review_events
			WHERE (run_id = ? OR ? = '') AND id > ?
			ORDER BY created_at ASC, id ASC
			LIMIT ?
		)
		ORDER BY created_at ASC, source ASC, id ASC
		LIMIT ?`,
		runID, sincePhaseID, perSource,
		runID, runID, sinceDispatchID, perSource,
		runID, runID, sinceCoordinationID, perSource,
		runID, runID, sinceReviewID, perSource,
		limit,
	)
	if err != nil {
		return nil, fmt.Errorf("list events: %w", err)
	}
	defer rows.Close()

	return scanEvents(rows)
}
```

Parameter count: 3 + 4 + 4 + 4 + 1 = **16** params, 16 `?` placeholders. Verified.

**Important:** The old signature had `sinceDiscoveryID` as the 4th parameter (unused placeholder). The new signature replaces it with `sinceCoordinationID` (actively used). All callers of `ListEvents` must be updated. Search with: `grep -rn "ListEvents(" core/intercore/`

**Step 2: Refactor ListAllEvents with sinceCoordinationID**

Apply the same pattern to `ListAllEvents`. This one has 5 sources (includes discovery). Add `sinceCoordinationID int64` parameter:

```go
// ListAllEvents returns events across all runs, merging all five event tables.
// Per-source sub-limits ensure each source is represented regardless of volume.
// Polling callers must loop until fewer than limit rows are returned.
func (s *Store) ListAllEvents(ctx context.Context, sincePhaseID, sinceDispatchID, sinceDiscoveryID, sinceCoordinationID, sinceReviewID int64, limit int) ([]Event, error) {
	if limit <= 0 {
		limit = 1000
	}

	perSource := perSourceLimit(limit, 5)

	rows, err := s.db.QueryContext(ctx, `
		SELECT id, run_id, source, event_type, from_state, to_state, reason, envelope_json, created_at FROM (
			SELECT id, run_id, 'phase' AS source, event_type, from_phase AS from_state, to_phase AS to_state,
				COALESCE(reason, '') AS reason, COALESCE(envelope_json, '') AS envelope_json, created_at
			FROM phase_events
			WHERE id > ?
			ORDER BY created_at ASC, id ASC
			LIMIT ?
		)
		UNION ALL
		SELECT id, run_id, source, event_type, from_state, to_state, reason, envelope_json, created_at FROM (
			SELECT id, COALESCE(run_id, '') AS run_id, 'dispatch' AS source, event_type,
				from_status AS from_state, to_status AS to_state, COALESCE(reason, '') AS reason,
				COALESCE(envelope_json, '') AS envelope_json, created_at
			FROM dispatch_events
			WHERE id > ?
			ORDER BY created_at ASC, id ASC
			LIMIT ?
		)
		UNION ALL
		SELECT id, run_id, source, event_type, from_state, to_state, reason, envelope_json, created_at FROM (
			SELECT id, COALESCE(discovery_id, '') AS run_id, 'discovery' AS source, event_type,
				from_status AS from_state, to_status AS to_state, COALESCE(payload, '{}') AS reason,
				'' AS envelope_json, created_at
			FROM discovery_events
			WHERE id > ?
			ORDER BY created_at ASC, id ASC
			LIMIT ?
		)
		UNION ALL
		SELECT id, run_id, source, event_type, from_state, to_state, reason, envelope_json, created_at FROM (
			SELECT id, COALESCE(run_id, '') AS run_id, 'coordination' AS source, event_type,
				owner AS from_state, pattern AS to_state, COALESCE(reason, '') AS reason,
				COALESCE(envelope_json, '') AS envelope_json, created_at
			FROM coordination_events
			WHERE id > ?
			ORDER BY created_at ASC, id ASC
			LIMIT ?
		)
		UNION ALL
		SELECT id, run_id, source, event_type, from_state, to_state, reason, envelope_json, created_at FROM (
			SELECT id, COALESCE(run_id, '') AS run_id, 'review' AS source, 'disagreement_resolved' AS event_type,
				finding_id AS from_state, resolution AS to_state, COALESCE(agents_json, '{}') AS reason,
				'' AS envelope_json, created_at
			FROM review_events
			WHERE id > ?
			ORDER BY created_at ASC, id ASC
			LIMIT ?
		)
		ORDER BY created_at ASC, source ASC, id ASC
		LIMIT ?`,
		sincePhaseID, perSource,
		sinceDispatchID, perSource,
		sinceDiscoveryID, perSource,
		sinceCoordinationID, perSource,
		sinceReviewID, perSource,
		limit,
	)
	if err != nil {
		return nil, fmt.Errorf("list all events: %w", err)
	}
	defer rows.Close()

	return scanEvents(rows)
}
```

Parameter count: 2 + 2 + 2 + 2 + 2 + 1 = **11** params, 11 `?` placeholders. Verified.

**Step 3: Add perSourceLimit helper**

Add at the bottom of store.go, near other unexported helpers (`scanEvents`, `statusRef`, etc.):

```go
// perSourceLimit computes per-source sub-limit for UNION ALL queries.
// Each source gets ceil(total / sourceCount) to guarantee representation.
func perSourceLimit(total, sourceCount int) int {
	if sourceCount <= 0 {
		return total
	}
	return (total + sourceCount - 1) / sourceCount
}
```

**Step 4: Update all callers**

Search for `ListEvents(` and `ListAllEvents(` across the codebase. Update call sites to pass the new `sinceCoordinationID` parameter (pass `0` for callers that don't track coordination cursors yet). The signature change from `sinceDiscoveryID` → `sinceCoordinationID` in `ListEvents` must be reflected at each call site.

**Step 5: Add tests**

In `store_test.go`, add tests for per-source representation and edge cases:

```go
func TestListEvents_PerSourceRepresentation(t *testing.T) {
	store, d := setupTestStore(t)
	ctx := context.Background()
	insertTestRun(t, d, "run-nucleation")

	// Insert 100 coordination events (high volume)
	for i := 0; i < 100; i++ {
		err := store.AddCoordinationEvent(ctx, "lock_acquired", fmt.Sprintf("lock-%d", i),
			"agent-a", "*.go", "project", "", "run-nucleation", nil)
		if err != nil {
			t.Fatalf("AddCoordinationEvent %d: %v", i, err)
		}
	}

	// Insert 5 phase events (low volume)
	for i := 0; i < 5; i++ {
		_, err := d.SqlDB().ExecContext(ctx, `
			INSERT INTO phase_events (run_id, from_phase, to_phase, event_type)
			VALUES (?, ?, ?, ?)`, "run-nucleation", "brainstorm", "planned", "advance")
		if err != nil {
			t.Fatalf("insert phase event %d: %v", i, err)
		}
	}

	// List with limit=20 — both sources should be represented
	events, err := store.ListEvents(ctx, "run-nucleation", 0, 0, 0, 0, 20)
	if err != nil {
		t.Fatalf("ListEvents: %v", err)
	}

	if len(events) == 0 {
		t.Fatal("expected events, got none")
	}

	sources := map[string]int{}
	for _, e := range events {
		sources[e.Source]++
	}

	if sources["phase"] == 0 {
		t.Errorf("phase events crowded out: got %d phase, %d coordination", sources["phase"], sources["coordination"])
	}
	if sources["coordination"] == 0 {
		t.Error("expected coordination events")
	}

	// Phase should have exactly 5 (perSourceLimit(20,4)=5, and we inserted 5)
	if sources["phase"] != 5 {
		t.Errorf("phase events = %d, want 5", sources["phase"])
	}

	// Coordination capped at perSource=5 (out of 100 available)
	if sources["coordination"] > 5 {
		t.Errorf("coordination events %d exceeds per-source limit of 5", sources["coordination"])
	}

	t.Logf("sources: %v (total: %d)", sources, len(events))
}

func TestListEvents_EdgeCases(t *testing.T) {
	store, d := setupTestStore(t)
	ctx := context.Background()
	insertTestRun(t, d, "run-edge")

	// Insert 2 phase events only
	for i := 0; i < 2; i++ {
		_, err := d.SqlDB().ExecContext(ctx, `
			INSERT INTO phase_events (run_id, from_phase, to_phase, event_type)
			VALUES (?, ?, ?, ?)`, "run-edge", "brainstorm", "planned", "advance")
		if err != nil {
			t.Fatalf("insert: %v", err)
		}
	}

	// limit=1: perSourceLimit(1,4)=1, outer limit=1
	events, err := store.ListEvents(ctx, "run-edge", 0, 0, 0, 0, 1)
	if err != nil {
		t.Fatalf("ListEvents limit=1: %v", err)
	}
	if len(events) != 1 {
		t.Errorf("limit=1: got %d events, want 1", len(events))
	}

	// limit > total: should return all 2
	events, err = store.ListEvents(ctx, "run-edge", 0, 0, 0, 0, 200)
	if err != nil {
		t.Fatalf("ListEvents limit=200: %v", err)
	}
	if len(events) != 2 {
		t.Errorf("limit=200: got %d events, want 2", len(events))
	}
}
```

**Step 6: Build and test**

Run: `cd core/intercore && go build ./... && go test ./... -v -count=1`
Expected: PASS

**Step 7: Commit**

```bash
cd core/intercore && git add internal/event/store.go internal/event/store_test.go
git commit -m "fix(events): per-source sub-limits + coordination cursor fix

ListEvents and ListAllEvents now apply ceil(limit/sourceCount) inside
each UNION ALL arm, guaranteeing low-volume sources (phase, review) get
representation even when coordination events dominate.

Also fixes pre-existing bug: coordination_events used hardcoded id > 0
(no cursor). Now uses sinceCoordinationID parameter like other sources.

Behavior change: --limit N now means 'up to N events, balanced across
sources' — each source gets at most ceil(N/sourceCount) rows. Callers
debugging a single source should use source-specific query methods.

Fixes Demarch-og7m.17"
```

<verify>
- run: `cd core/intercore && go build ./...`
  expect: exit 0
- run: `cd core/intercore && go test ./internal/event/ -v -count=1 -run TestListEvents`
  expect: contains "PASS"
- run: `cd core/intercore && go test ./... -count=1`
  expect: exit 0
</verify>

---

### Task 2: Event Schema Contract (F2/.21)

**IMPORTANT:** `contracts/events/` already contains generated schemas from `registry.go` → `generate.go` → `invopop/jsonschema` (pipeline: `//go:generate go run ./cmd/gen` in `contracts/doc.go`). Do NOT create hand-authored `.schema.json` files. Enrich the generated schemas via struct tags instead.

**Files:**
- Modify: `core/intercore/internal/event/event.go` — struct tags + Validate()
- Modify: `core/intercore/internal/event/store_test.go` — Validate test
- Create: `core/intercore/contracts/events/README.md` — event vocabulary reference
- Regenerate: `core/intercore/contracts/events/event.json` — via `go generate`

**Step 1: Add jsonschema struct tag and fix stale comment**

In `event.go`, update the `Event` struct's `Source` field to include a `jsonschema` enum tag and fix the stale comment (lists 3 of 7 sources):

```go
// Event is the unified event type for the intercore event bus.
type Event struct {
	ID        int64          `json:"id"`
	RunID     string         `json:"run_id"`
	Source    string         `json:"source" jsonschema:"enum=phase,enum=dispatch,enum=interspect,enum=discovery,enum=coordination,enum=review,enum=intent"` // origin subsystem — see contracts/events/README.md
	Type      string         `json:"type"`       // "advance", "skip", "block", "status_change", etc.
	FromState string         `json:"from_state"` // source-dependent: from_phase, from_status, owner, finding_id
	ToState   string         `json:"to_state"`   // source-dependent: to_phase, to_status, pattern, resolution
	Reason    string         `json:"reason,omitempty"`
	Envelope  *EventEnvelope `json:"envelope,omitempty"`
	Timestamp time.Time      `json:"timestamp"`
}
```

**Step 2: Add Validate() method with unexported map**

In `event.go`, add after the Event struct. Use unexported `validSources` to prevent external mutation:

```go
// validSources is the set of recognized event source values.
// Unexported to prevent external mutation — use Event.Validate() instead.
// NOTE: When adding a new Source* constant, add it here too.
var validSources = map[string]bool{
	SourcePhase:        true,
	SourceDispatch:     true,
	SourceInterspect:   true,
	SourceDiscovery:    true,
	SourceCoordination: true,
	SourceReview:       true,
	SourceIntent:       true,
}

// Validate checks that the event has a recognized Source value.
func (e *Event) Validate() error {
	if !validSources[e.Source] {
		return fmt.Errorf("unknown event source %q", e.Source)
	}
	return nil
}
```

Add `"fmt"` to the import block in event.go.

**Step 3: Add test for Validate with source count guard**

In `store_test.go`, add a table-driven test plus a count guard that catches sync drift:

```go
func TestEvent_Validate(t *testing.T) {
	tests := []struct {
		source  string
		wantErr bool
	}{
		{event.SourcePhase, false},
		{event.SourceDispatch, false},
		{event.SourceInterspect, false},
		{event.SourceDiscovery, false},
		{event.SourceCoordination, false},
		{event.SourceReview, false},
		{event.SourceIntent, false},
		{"unknown", true},
		{"", true},
	}
	for _, tt := range tests {
		e := Event{Source: tt.source}
		err := e.Validate()
		if (err != nil) != tt.wantErr {
			t.Errorf("Validate(%q) error = %v, wantErr %v", tt.source, err, tt.wantErr)
		}
	}
}

func TestValidSources_CountMatchesConstants(t *testing.T) {
	// Guard against adding a Source* constant without updating validSources.
	// If this fails, add the new constant to validSources in event.go.
	const expectedSources = 7
	valid := 0
	for _, src := range []string{
		event.SourcePhase, event.SourceDispatch, event.SourceInterspect,
		event.SourceDiscovery, event.SourceCoordination, event.SourceReview, event.SourceIntent,
	} {
		e := Event{Source: src}
		if err := e.Validate(); err == nil {
			valid++
		}
	}
	if valid != expectedSources {
		t.Errorf("validSources has %d entries, expected %d — update validSources when adding Source* constants", valid, expectedSources)
	}
}
```

**Step 4: Regenerate schemas**

```bash
cd core/intercore && go generate ./contracts/...
```

This re-runs `contracts/cmd/gen/main.go`, which reflects the updated `Event` struct (now with `jsonschema:"enum=..."` tag) and writes the enriched schema to `contracts/events/event.json`. Verify the generated file now includes the enum:

```bash
grep -A1 '"source"' contracts/events/event.json | grep enum
```

Expected: `"enum": ["phase", "dispatch", "interspect", "discovery", "coordination", "review", "intent"]`

**Step 5: Create README.md**

Create `core/intercore/contracts/events/README.md`:

```markdown
# Intercore Event Contracts

Machine-readable contracts for the Intercore event bus. Schemas in this
directory are **generated** by `go generate ./contracts/...` — do not
hand-edit the `.json` files. To add constraints, use `jsonschema` struct
tags on the Go types in `internal/event/`.

## Event Sources

| Source | Table | In unified stream? | Key consumers |
|---|---|---|---|
| `phase` | `phase_events` | Yes (ListEvents, ListAllEvents) | Clavain gate_calibration, interspect |
| `dispatch` | `dispatch_events` | Yes (ListEvents, ListAllEvents) | Clavain sprint, Skaffen |
| `discovery` | `discovery_events` | ListAllEvents only (no run_id) | interphase |
| `coordination` | `coordination_events` | Yes (ListEvents, ListAllEvents) | interlock, Clavain |
| `review` | `review_events` | Yes (ListEvents, ListAllEvents) | interspect evidence pipeline |
| `interspect` | `interspect_events` | **No** — use `ListInterspectEvents` | interspect, Skaffen evidence emitter |
| `intent` | `intent_events` | **No** — planned for future unification | Ockham (future) |

Note: `interspect` and `intent` are valid Source values (accepted by `Event.Validate()`)
but are NOT included in the `ListEvents`/`ListAllEvents` UNION ALL queries. They have
dedicated query methods. The `.2` sub-epic (Demarch-og7m.2) will unify all sources.

## Schemas

- [`event.json`](event.json) — Unified Event type (generated)
- [`event-envelope.json`](event-envelope.json) — EventEnvelope provenance data (generated)
- [`review-event.json`](review-event.json) — ReviewEvent type (generated)
- [`interspect-event.json`](interspect-event.json) — InterspectEvent type (generated)

## Versioning

Breaking changes require:
1. Update the Go struct (the source of truth)
2. Re-run `go generate ./contracts/...`
3. Update all consumers listed above
4. Dual-write during migration period

The planned EventEnvelope v2 (Demarch-og7m.2.1) will update the struct and regenerate.
```

**Step 6: Build, test, and verify schemas**

```bash
cd core/intercore && go build ./... && go test ./... -v -count=1
```

**Step 7: Commit**

```bash
cd core/intercore && git add internal/event/event.go internal/event/store_test.go contracts/events/
git commit -m "feat(events): source enum in schema + Event.Validate() + vocabulary README

Adds jsonschema enum tag to Event.Source, regenerating event.json with
the 7-value constraint. Event.Validate() rejects unknown sources via
unexported validSources map. README documents which sources appear in
the unified stream vs dedicated query methods.

Fixes Demarch-og7m.21"
```

<verify>
- run: `cd core/intercore && go build ./...`
  expect: exit 0
- run: `cd core/intercore && go test ./internal/event/ -v -count=1 -run TestEvent_Validate`
  expect: contains "PASS"
- run: `cd core/intercore && go test ./contracts/ -v -count=1`
  expect: contains "PASS"
- run: `grep '"enum"' core/intercore/contracts/events/event.json`
  expect: contains "phase"
- run: `python3 -c "import json; json.load(open('core/intercore/contracts/events/event.json'))"`
  expect: exit 0
</verify>

---

### Task 3: Closed-Loop Calibration Stage Reporting (F3/.23)

**Scope: Reporting only.** This task adds visibility into calibration stage maturity. It does NOT promote any domain from shadow to active — that is separate per-domain work. The PRD feature description should be read as "reporting only" despite the original phrasing.

**Files:**
- Create: `docs/calibration-stages.yaml` (not in core/intercore/contracts — this is operational policy, not a type contract)
- Modify: `os/Clavain/commands/doctor.md`

**Step 1: Create calibration-stages.yaml**

Place in `docs/` (project-level operational policy, consumed by L2 Clavain). Not in `core/intercore/contracts/` — that directory holds Go-generated type schemas.

```yaml
# Calibration stages per PHILOSOPHY.md's 4-stage closed-loop pattern:
# 1: Hardcoded defaults
# 2: Collect actuals
# 3: Calibrate from history
# 4: Defaults become fallback
#
# Source of truth for /clavain:doctor calibration check.
# Update this file when a domain advances stages.

domains:
  cost_estimation:
    description: "Sprint/phase cost prediction"
    prediction: "phaseCostEstimate()"
    current_stage: 2
    evidence:
      stage_1: "os/Clavain/config/budget.yaml (hardcoded defaults)"
      stage_2: "interverse/interstat — per-phase token actuals collected"
      stage_3: null
      stage_4: null
    next_step: "calibrate-phase-costs reads interstat history to adjust estimates"
    related_bead: null

  agent_routing:
    description: "Model tier selection for agent dispatch"
    prediction: "selectQuality() model tier"
    current_stage: 2
    evidence:
      stage_1: "os/Clavain/config/routing.yaml (tier defaults)"
      stage_2: "interspect canary monitoring collects post-dispatch outcomes"
      stage_3: null
      stage_4: null
    next_step: "interspect evidence → automatic routing override adjustments"
    related_bead: null

  complexity_scoring:
    description: "Task complexity classification"
    prediction: "classifyComplexity()"
    current_stage: 1
    evidence:
      stage_1: "core/intercore complexity classifier (hardcoded thresholds)"
      stage_2: null
      stage_3: null
      stage_4: null
    next_step: "instrument actual sprint duration/tokens alongside predictions"
    related_bead: null

  review_triage:
    description: "Agent relevance scoring for review findings"
    prediction: "agent relevance scores"
    current_stage: 3
    evidence:
      stage_1: "interflux default relevance weights"
      stage_2: "interspect evidence tracks which findings got acted on"
      stage_3: "interspect evidence → routing override proposals (calibration active, human-approved)"
      stage_4: null
    next_step: "automate override promotion (currently requires human approval via _interspect_apply_propose)"
    related_bead: null

  gate_thresholds:
    description: "Phase gate pass/fail thresholds"
    prediction: "gate hardness levels"
    current_stage: 2
    evidence:
      stage_1: "interphase hardcoded gate thresholds (TierHard/TierSoft)"
      stage_2: "Demarch-0rgc: outcome recording schema + shadow mode active"
      stage_3: null
      stage_4: null
    next_step: "promote B3 calibration from shadow — threshold tuning from outcomes"
    related_bead: "Demarch-0rgc"

  fleet_budgets:
    description: "Agent token budget estimation"
    prediction: "agent token estimates"
    current_stage: 4
    evidence:
      stage_1: "os/Clavain/config/budget.yaml defaults"
      stage_2: "interstat per-agent token actuals"
      stage_3: "scan-fleet.sh --enrich-costs calibrates from history"
      stage_4: "estimate-costs.sh falls back to budget.yaml when no history"
    next_step: "complete — monitor for regression"
    related_bead: null
```

**Key change from v1:** `review_triage` downgraded from stage 4 → stage 3. Routing overrides are proposed but require human approval — not yet automatic. Summary: 1/6 at stage 4, 1/6 at stage 3, 4/6 at stages 1-2.

**Step 2: Add calibration stage check to doctor.md**

Insert as section `### 3c. Calibration Stage Maturity` (following existing numbering convention: 3, 3a, 3b, 3c, 3f...).

Use awk-based parsing (matching the existing `2e. Routing Activation Status` pattern) with python3 as optional enhancement, to avoid silent skip when pyyaml is absent:

```markdown
### 3c. Calibration Stage Maturity

```bash
_stages_file="docs/calibration-stages.yaml"
if [ -f "$_stages_file" ]; then
  echo "Calibration Stages (PHILOSOPHY.md closed-loop):"
  # Parse with awk (no external deps). Extracts domain name + current_stage.
  awk '
    /^  [a-z_]+:$/ { domain = $1; sub(/:$/, "", domain) }
    /current_stage:/ && domain != "" {
      stage = $NF
      marker = (stage >= 4) ? "PASS" : (stage >= 3) ? "WARN" : "GAP"
      printf "  %-20s stage %s/4  %s\n", domain, stage, marker
      if (stage >= 4) complete++
      total++
      domain = ""
    }
    END {
      printf "  Summary: %d/%d domains at stage 4\n", complete, total
    }
  ' "$_stages_file"
else
  echo "calibration stages: WARN (docs/calibration-stages.yaml not found)"
fi
```
```

**Step 3: Commit**

Commit from monorepo root (YAML is in docs/, not a subproject):
```bash
git add docs/calibration-stages.yaml
git commit -m "feat: calibration-stages.yaml — closed-loop maturity definitions

Machine-readable stage definitions for PHILOSOPHY.md's 6 calibration
domains. Reports: 1/6 at stage 4, 1/6 at stage 3, 4/6 at stages 1-2.
review_triage at stage 3 (not 4): overrides are proposed, not automatic.

Part of Demarch-og7m.23"
```

Then commit Clavain:
```bash
cd os/Clavain && git add commands/doctor.md
git commit -m "feat(doctor): add calibration stage maturity check (section 3c)

Reads docs/calibration-stages.yaml and reports per-domain stage with
PASS/WARN/GAP markers. Uses awk (no pyyaml dependency). Surfaces the
PHILOSOPHY.md closed-loop gap for sprint planning.

Fixes Demarch-og7m.23"
```

<verify>
- run: `python3 -c "import yaml; d=yaml.safe_load(open('docs/calibration-stages.yaml')); assert len(d['domains'])==6; s4=sum(1 for v in d['domains'].values() if v['current_stage']>=4); print(f'{s4}/6 at stage 4')"`
  expect: contains "1/6 at stage 4"
- run: `awk '/^  [a-z_]+:$/{d=$1;sub(/:$/,"",d)} /current_stage:/ && d!=""{printf "%-20s stage %s/4\n",d,$NF;d=""}' docs/calibration-stages.yaml`
  expect: 6 lines with stage numbers
</verify>

---

## Post-Implementation

After all 3 tasks land:
1. Close beads: `bd close Demarch-og7m.17`, `bd close Demarch-og7m.21`, `bd close Demarch-og7m.23`
2. Push subproject repos: `cd core/intercore && git push`, `cd os/Clavain && git push`
3. Export beads: `bd backup export && git add -f .beads/backup/ && git commit -m "chore(beads): close Batch 4" && git push`
4. Update dependencies: .17 closes → unblocks og7m.2.2; .21 closes → unblocks og7m.2.1

## Review Findings Incorporated

This plan was revised after flux-drive review (architecture, correctness, quality, user/product). Key changes from v1:

| Finding | Change |
|---------|--------|
| Blocker: contracts/events/ has generated schemas | F2 uses struct tags + `go generate`, no hand-authored files |
| coordination_events `id > 0` hardcoded cursor | F1 adds `sinceCoordinationID` parameter, fixes `id > ?` |
| `ValidSources` exported mutable map | F2 uses unexported `validSources` |
| `review_triage` incorrectly at stage 4 | F3 downgrades to stage 3 (overrides are proposals, not automatic) |
| calibration-stages.yaml in L1 contracts | F3 moves to `docs/` (operational policy, not type contract) |
| pyyaml silent skip | F3 uses awk (matching section 2e pattern), no external deps |
| Section numbering `3a2` inconsistent | F3 uses `3c` (following existing convention) |
| Stale Event.Source comment | F2 fixes in same commit |
| Test assertion vacuous | F1 uses `!= 5` and adds edge case tests (limit=1, limit > total) |
| Behavior change undocumented | F1 commit message and function comment document the per-source semantics |
| F2 "6+ consumers" overstated | README documents which sources are in unified stream vs dedicated methods |
| PRD says "promote B3" but AC doesn't | F3 scope clarified: reporting only |
