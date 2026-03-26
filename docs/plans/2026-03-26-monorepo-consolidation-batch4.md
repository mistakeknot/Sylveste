---
artifact_type: plan
bead: Demarch-og7m
stage: design
requirements:
  - F1: Event pipeline nucleation fix (.17)
  - F2: Event schema contract (.21)
  - F3: Closed-loop calibration stage reporting (.23)
---
# Monorepo Consolidation Batch 4 — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Demarch-og7m
**Goal:** Prepare the event pipeline for unification (fix nucleation + publish schema contract) and add observability for PHILOSOPHY.md's closed-loop maturity gap.

**Architecture:** F1 and F2 are Go in L1 Intercore (event package). F3 is shell/YAML in L2 Clavain + L1 Intercore contracts. F1 and F2 share the event package but don't block each other. F3 is fully independent.

**Tech Stack:** Go 1.22 (intercore, modernc.org/sqlite), bash 5.x (Clavain doctor), YAML (calibration stages), JSON Schema Draft 2020-12

---

## Must-Haves

**Truths** (observable behaviors):
- ListEvents with limit=20 returns events from all active sources, not just the highest-volume one
- `Event.Validate()` rejects unknown Source values
- JSON Schema files validate against Draft 2020-12
- `/doctor` shows calibration stage for all 6 PHILOSOPHY.md domains

**Artifacts** (files with specific exports):
- [`core/intercore/internal/event/store.go`] ListEvents + ListAllEvents use per-source sub-limits
- [`core/intercore/contracts/events/event.schema.json`] JSON Schema for Event type
- [`core/intercore/contracts/events/envelope.schema.json`] JSON Schema for EventEnvelope
- [`core/intercore/contracts/events/README.md`] Event vocabulary reference
- [`core/intercore/internal/event/event.go`] exports `Validate()` method on Event
- [`core/intercore/contracts/calibration-stages.yaml`] 6-domain stage definitions
- [`os/Clavain/commands/doctor.md`] includes calibration stage check section

**Key Links:**
- F1 per-source sub-limits applied inside each SELECT arm, outer query does final ORDER BY + LIMIT
- F2 schema documents current state (not v2 redesign — that's .2.1)
- F3 calibration-stages.yaml is the single source of truth for /doctor

---

### Task 1: Event Pipeline Nucleation Fix (F1/.17)

**Files:**
- Modify: `core/intercore/internal/event/store.go:95-186`
- Modify: `core/intercore/internal/event/store_test.go`

**Step 1: Refactor ListEvents to use per-source sub-limits**

The current query (store.go:99-142) uses a flat `UNION ALL ... LIMIT ?`. Replace with per-source sub-limits inside each SELECT arm.

In `store.go`, replace the `ListEvents` method body. The strategy: wrap each SELECT in a subquery with its own LIMIT, then UNION ALL the subqueries, ORDER BY on the outer query, and apply the total LIMIT.

```go
func (s *Store) ListEvents(ctx context.Context, runID string, sincePhaseID, sinceDispatchID, sinceDiscoveryID, sinceReviewID int64, limit int) ([]Event, error) {
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
			WHERE (run_id = ? OR ? = '') AND id > 0
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
		runID, runID, perSource,
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

**Step 2: Refactor ListAllEvents the same way**

Apply the same pattern to `ListAllEvents` (store.go:144-186). This one has 5 sources (includes discovery_events):

```go
func (s *Store) ListAllEvents(ctx context.Context, sincePhaseID, sinceDispatchID, sinceDiscoveryID, sinceReviewID int64, limit int) ([]Event, error) {
	if limit <= 0 {
		limit = 1000
	}

	perSource := perSourceLimit(limit, 5)

	// Same pattern: per-source sub-limit inside each SELECT, outer ORDER BY + LIMIT.
	// Include discovery_events (5th source) since this is cross-run.
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
			WHERE id > 0
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
		perSource,
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

**Step 3: Add perSourceLimit helper**

Add near the top of store.go, after the struct definition:

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

**Step 4: Add test for per-source representation**

In `store_test.go`, add a test that verifies low-volume sources aren't crowded out:

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

	// Phase should have up to perSourceLimit(20,4)=5 events
	if sources["phase"] > 5 {
		t.Errorf("phase events %d exceeds per-source limit of 5", sources["phase"])
	}

	t.Logf("sources: %v (total: %d)", sources, len(events))
}
```

**Step 5: Build and test**

Run: `cd core/intercore && go build ./... && go test ./... -v -count=1`
Expected: PASS

**Step 6: Commit**

```bash
cd core/intercore && git add internal/event/store.go internal/event/store_test.go
git commit -m "fix(events): per-source sub-limits prevent nucleation crowding

ListEvents and ListAllEvents now apply ceil(limit/sourceCount) inside
each UNION ALL arm, guaranteeing low-volume sources (phase, review)
get representation even when coordination events dominate.

Fixes Demarch-og7m.17"
```

<verify>
- run: `cd core/intercore && go build ./...`
  expect: exit 0
- run: `cd core/intercore && go test ./internal/event/ -v -count=1 -run TestListEvents_PerSourceRepresentation`
  expect: contains "PASS"
- run: `cd core/intercore && go test ./... -count=1`
  expect: exit 0
</verify>

---

### Task 2: Event Schema Contract (F2/.21)

**Files:**
- Create: `core/intercore/contracts/events/event.schema.json`
- Create: `core/intercore/contracts/events/envelope.schema.json`
- Create: `core/intercore/contracts/events/README.md`
- Modify: `core/intercore/internal/event/event.go`

**Step 1: Create contracts directory**

```bash
mkdir -p core/intercore/contracts/events
```

**Step 2: Create event.schema.json**

Document the current Event type (from event.go:46-56) as JSON Schema:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://github.com/mistakeknot/intercore/contracts/events/event.schema.json",
  "title": "Intercore Event",
  "description": "Unified event type for the intercore event bus. All event sources (phase, dispatch, coordination, review, discovery, interspect, intent) are represented by this schema.",
  "type": "object",
  "required": ["id", "source", "type", "timestamp"],
  "properties": {
    "id": {
      "type": "integer",
      "description": "Auto-increment ID, unique within source table (NOT globally unique across sources)"
    },
    "run_id": {
      "type": "string",
      "description": "Run ID for run-scoped events. Empty for system-level events (discovery)"
    },
    "source": {
      "type": "string",
      "enum": ["phase", "dispatch", "interspect", "discovery", "coordination", "review", "intent"],
      "description": "Origin subsystem"
    },
    "type": {
      "type": "string",
      "description": "Event type within source (e.g., 'advance', 'status_change', 'disagreement_resolved')"
    },
    "from_state": {
      "type": "string",
      "description": "Source-dependent: from_phase (phase), from_status (dispatch), owner (coordination), finding_id (review)"
    },
    "to_state": {
      "type": "string",
      "description": "Source-dependent: to_phase (phase), to_status (dispatch), pattern (coordination), resolution (review)"
    },
    "reason": {
      "type": "string",
      "description": "Human-readable reason or JSON payload (agents_json for review, payload for discovery)"
    },
    "envelope": {
      "$ref": "envelope.schema.json",
      "description": "Optional provenance envelope for causal audit and replay"
    },
    "timestamp": {
      "type": "string",
      "format": "date-time",
      "description": "Event creation time (RFC 3339)"
    }
  }
}
```

**Step 3: Create envelope.schema.json**

Document the EventEnvelope type (from envelope.go:8-19):

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://github.com/mistakeknot/intercore/contracts/events/envelope.schema.json",
  "title": "EventEnvelope",
  "description": "Provenance data for causal audit and replay. All fields optional — an empty/nil envelope means no provenance captured.",
  "type": "object",
  "properties": {
    "policy_version": {
      "type": "string",
      "description": "Version of the authorization policy active when the event was produced"
    },
    "caller_identity": {
      "type": "string",
      "description": "Verified identity of the caller (agent ID or system component)"
    },
    "capability_scope": {
      "type": "string",
      "description": "Capability scope granted to the caller"
    },
    "trace_id": {
      "type": "string",
      "description": "Distributed trace ID (propagated across component boundaries)"
    },
    "span_id": {
      "type": "string",
      "description": "Span within the trace"
    },
    "parent_span_id": {
      "type": "string",
      "description": "Parent span for causal chain reconstruction"
    },
    "input_artifact_refs": {
      "type": "array",
      "items": { "type": "string" },
      "description": "References to input artifacts consumed by this event's producer"
    },
    "output_artifact_refs": {
      "type": "array",
      "items": { "type": "string" },
      "description": "References to output artifacts produced alongside this event"
    },
    "requested_sandbox": {
      "type": "string",
      "description": "Sandbox level requested by the caller"
    },
    "effective_sandbox": {
      "type": "string",
      "description": "Sandbox level actually applied (may differ due to policy override)"
    }
  },
  "additionalProperties": false
}
```

**Step 4: Create README.md**

```markdown
# Intercore Event Contracts

Machine-readable contracts for the Intercore event bus.

## Event Sources

| Source | Table | Description | Key consumers |
|---|---|---|---|
| `phase` | `phase_events` | Phase FSM transitions (advance, skip, block) | Clavain gate_calibration, interspect |
| `dispatch` | `dispatch_events` | Dispatch lifecycle (spawned → running → completed) | Clavain sprint, Skaffen |
| `discovery` | `discovery_events` | System-level discovery lifecycle (no run_id) | interphase |
| `coordination` | `coordination_events` | Lock acquire/release/conflict | interlock, Clavain |
| `review` | `review_events` | Disagreement resolution, execution defects | interspect evidence pipeline |
| `interspect` | `interspect_events` | Agent corrections, routing signals | interspect, Skaffen evidence emitter |
| `intent` | (planned) | Intent declarations from Ockham | Ockham (future) |

## Schemas

- [`event.schema.json`](event.schema.json) — Unified Event type
- [`envelope.schema.json`](envelope.schema.json) — EventEnvelope provenance data

## Versioning

These schemas document the **current** event format. Breaking changes require:
1. Bump schema `$id` version
2. Update all consumers listed above
3. Dual-write during migration period

The planned EventEnvelope v2 (Demarch-og7m.2.1) will be published here as a new schema version.
```

**Step 5: Add Validate() method to Event**

In `event.go`, add after the Event struct:

```go
// ValidSources lists all recognized event source values.
var ValidSources = map[string]bool{
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
	if !ValidSources[e.Source] {
		return fmt.Errorf("unknown event source %q", e.Source)
	}
	return nil
}
```

Add `"fmt"` to the import block in event.go.

**Step 6: Add test for Validate**

In `store_test.go`, add:

```go
func TestEvent_Validate(t *testing.T) {
	tests := []struct {
		source  string
		wantErr bool
	}{
		{"phase", false},
		{"dispatch", false},
		{"interspect", false},
		{"discovery", false},
		{"coordination", false},
		{"review", false},
		{"intent", false},
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
```

**Step 7: Build and test**

Run: `cd core/intercore && go build ./... && go test ./... -v -count=1`
Expected: PASS

**Step 8: Commit**

```bash
cd core/intercore && git add contracts/events/ internal/event/event.go internal/event/store_test.go
git commit -m "feat(events): publish JSON Schema contract + Event.Validate()

Adds contracts/events/ with JSON Schema Draft 2020-12 for Event and
EventEnvelope types. Documents all 7 source values, 5 backing tables,
and key consumers. Event.Validate() rejects unknown sources.

Fixes Demarch-og7m.21"
```

<verify>
- run: `cd core/intercore && go build ./...`
  expect: exit 0
- run: `cd core/intercore && go test ./internal/event/ -v -count=1 -run TestEvent_Validate`
  expect: contains "PASS"
- run: `python3 -c "import json; json.load(open('core/intercore/contracts/events/event.schema.json'))"`
  expect: exit 0
- run: `python3 -c "import json; json.load(open('core/intercore/contracts/events/envelope.schema.json'))"`
  expect: exit 0
</verify>

---

### Task 3: Closed-Loop Calibration Stage Reporting (F3/.23)

**Files:**
- Create: `core/intercore/contracts/calibration-stages.yaml`
- Modify: `os/Clavain/commands/doctor.md`

**Step 1: Create calibration-stages.yaml**

This is the single source of truth for /doctor's calibration stage check. Each domain maps to its current stage and evidence pointers.

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
    current_stage: 4
    evidence:
      stage_1: "interflux default relevance weights"
      stage_2: "interspect evidence tracks which findings got acted on"
      stage_3: "interspect evidence → routing overrides (calibration active)"
      stage_4: "hardcoded weights used as fallback when no evidence exists"
    next_step: "complete — monitor for regression"
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

**Step 2: Add calibration stage check to doctor.md**

Insert a new section after "### 3a. Shadow Tracker Detection" and before "### 3b. Zombie Bead Detection":

```markdown
### 3a2. Calibration Stage Maturity

```bash
_stages_file="core/intercore/contracts/calibration-stages.yaml"
if [ -f "$_stages_file" ]; then
  echo "Calibration Stages (PHILOSOPHY.md closed-loop):"
  # Parse YAML with python3 for reliability
  python3 -c "
import yaml, sys
with open('$_stages_file') as f:
    data = yaml.safe_load(f)
domains = data.get('domains', {})
complete = 0
for name, info in domains.items():
    stage = info.get('current_stage', 0)
    desc = info.get('description', '')
    marker = 'PASS' if stage >= 4 else ('WARN' if stage >= 3 else 'GAP')
    print(f'  {name:20s} stage {stage}/4  {marker}  {desc}')
    if stage >= 4: complete += 1
print(f'  Summary: {complete}/{len(domains)} domains at stage 4')
if complete < len(domains):
    gaps = [n for n, i in domains.items() if i.get('current_stage', 0) < 3]
    if gaps:
        print(f'  Action: advance {", ".join(gaps)} beyond stage 2')
" 2>/dev/null || echo "  calibration stages: SKIP (requires python3+pyyaml)"
else
  echo "calibration stages: SKIP (no contracts/calibration-stages.yaml)"
fi
```

Note: Place this section at `### 3a2` to preserve existing section numbering.

**Step 3: Commit**

```bash
cd core/intercore && git add contracts/calibration-stages.yaml
cd /home/mk/projects/Demarch && cd os/Clavain && git add commands/doctor.md
```

Commit intercore first:
```bash
cd core/intercore
git commit -m "feat(contracts): calibration-stages.yaml — closed-loop maturity definitions

Machine-readable stage definitions for PHILOSOPHY.md's 6 calibration
domains. Reports: 2/6 at stage 4, 4/6 stuck at stages 1-2.
Single source of truth for /doctor calibration check.

Part of Demarch-og7m.23"
```

Then commit Clavain:
```bash
cd os/Clavain
git commit -m "feat(doctor): add calibration stage maturity check

Reads calibration-stages.yaml and reports per-domain stage with
PASS/WARN/GAP markers. Surfaces the PHILOSOPHY.md closed-loop
gap that was previously invisible to sprint planning.

Fixes Demarch-og7m.23"
```

<verify>
- run: `python3 -c "import yaml; yaml.safe_load(open('core/intercore/contracts/calibration-stages.yaml'))"`
  expect: exit 0
- run: `bash -n os/Clavain/commands/doctor.md 2>&1 || true`
  expect: no fatal errors (doctor.md is markdown with embedded bash, not a standalone script)
- run: `python3 -c "
import yaml
with open('core/intercore/contracts/calibration-stages.yaml') as f:
    data = yaml.safe_load(f)
domains = data['domains']
assert len(domains) == 6, f'expected 6 domains, got {len(domains)}'
complete = sum(1 for d in domains.values() if d['current_stage'] >= 4)
assert complete == 2, f'expected 2 complete, got {complete}'
print('calibration-stages.yaml: valid')
"`
  expect: contains "valid"
</verify>

---

## Post-Implementation

After all 3 tasks land:
1. Close beads: `bd close Demarch-og7m.17`, `bd close Demarch-og7m.21`, `bd close Demarch-og7m.23`
2. Push subproject repos: `cd core/intercore && git push`, `cd os/Clavain && git push`
3. Export beads: `bd backup export && git add -f .beads/backup/ && git commit -m "chore(beads): close Batch 4" && git push`
4. Update dependencies: .17 closes → unblocks og7m.2.2; .21 closes → unblocks og7m.2.1
