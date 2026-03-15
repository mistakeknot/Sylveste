# Plan: Skaffen Quality Signals

**Bead:** Demarch-khlh
**PRD:** docs/prds/2026-03-14-skaffen-quality-signals.md
**Date:** 2026-03-14

## Step 1: Define QualitySignal types

**File:** `os/Skaffen/internal/mutations/signal.go` (NEW)

Create the `mutations` package with the QualitySignal type hierarchy:

```go
package mutations

import "github.com/mistakeknot/Skaffen/internal/tool"

type QualitySignal struct {
    SessionID string     `json:"session_id"`
    Timestamp string     `json:"timestamp"`
    Phase     tool.Phase `json:"phase"`
    Hard      HardSignals  `json:"hard"`
    Soft      SoftSignals  `json:"soft"`
    Human     HumanSignals `json:"human"`
}

type HardSignals struct {
    TestsPassed     *bool   `json:"tests_passed,omitempty"`
    BuildSuccess    *bool   `json:"build_success,omitempty"`
    TokenEfficiency float64 `json:"token_efficiency"`
    TurnCount       int     `json:"turn_count"`
}

type SoftSignals struct {
    ComplexityTier  int     `json:"complexity_tier"`
    ToolErrorRate   float64 `json:"tool_error_rate"`
    ToolDenialRate  float64 `json:"tool_denial_rate"`
}

type HumanSignals struct {
    ApprovalRate float64 `json:"approval_rate"`
    Outcome      string  `json:"outcome"`
}
```

**Test:** `os/Skaffen/internal/mutations/signal_test.go` — JSON round-trip, zero-value handling.

**Acceptance:** Types compile, JSON marshaling preserves all fields.

## Step 2: Implement mutations Store

**File:** `os/Skaffen/internal/mutations/store.go` (NEW)

JSONL-backed store with:
- `New(dir string) *Store` — constructor, dir = `~/.skaffen/mutations/`
- `Write(sig QualitySignal) error` — append to `quality-signals.jsonl`, thread-safe (sync.Mutex), auto-create dir
- `ReadRecent(n int) ([]QualitySignal, error)` — read last N entries. Implementation: read full file, return last N (simple; optimize to tail-read in v0.2 if file grows large)

**Test:** `os/Skaffen/internal/mutations/store_test.go` — write 3 signals, read recent 2, verify FIFO order. Test with empty file. Test with missing dir (auto-create).

**Acceptance:** `go test ./internal/mutations/ -count=1` passes.

## Step 3: Implement evidence aggregation

**File:** `os/Skaffen/internal/mutations/aggregate.go` (NEW)

```go
func Aggregate(evidenceDir, sessionID string) (QualitySignal, error)
```

Reads `evidenceDir/<sessionID>.jsonl`, computes:
- **Hard:** TokenEfficiency = total_out / total_in, TurnCount = number of evidence entries. TestsPassed/BuildSuccess = nil (no heuristic for now).
- **Soft:** ComplexityTier = max complexity_tier across turns. ToolErrorRate = turns with non-empty outcome=="error" / total turns. ToolDenialRate = 0 (no denial tracking in evidence yet — placeholder).
- **Human:** ApprovalRate = 0 (no approval tracking yet — placeholder). Outcome = last turn's outcome field.

Uses `agent.Evidence` type for deserialization (import from agent package).

**Test:** `os/Skaffen/internal/mutations/aggregate_test.go` — create temp evidence JSONL with 3 turns, verify aggregated signal values.

**Acceptance:** Aggregation produces correct signal from test evidence.

## Step 4: Wire Compound phase to write signals

**File:** `os/Skaffen/internal/agent/agent.go` (MODIFY)

Changes:
1. Add `signalStore mutations.Store` field to Agent struct (or via interface)
2. Add `WithSignalStore(s *mutations.Store) Option`
3. After `Run()` completes for Compound phase, call aggregation and write:
   - Read evidence for current session
   - `Aggregate(evidenceDir, sessionID)` → QualitySignal
   - `signalStore.Write(signal)`

**File:** `os/Skaffen/internal/agent/deps.go` (MODIFY)

Add interface:
```go
type SignalStore interface {
    Write(sig mutations.QualitySignal) error
    ReadRecent(n int) ([]mutations.QualitySignal, error)
}
```

Add NoOp:
```go
type NoOpSignalStore struct{}
func (s *NoOpSignalStore) Write(_ mutations.QualitySignal) error { return nil }
func (s *NoOpSignalStore) ReadRecent(_ int) ([]mutations.QualitySignal, error) { return nil, nil }
```

**File:** `cmd/skaffen/main.go` (MODIFY)

Wire: create `mutations.New(skaffenDir + "/mutations")`, pass to agent via `WithSignalStore()`.

**Acceptance:** After running a Skaffen session, `~/.skaffen/mutations/quality-signals.jsonl` contains a new entry.

## Step 5: Orient system prompt injection

**File:** `os/Skaffen/internal/session/session.go` (MODIFY)

Changes:
1. Add `signalStore` field to JSONLSession (passed via constructor or setter)
2. In `SystemPrompt()`, when phase == `tool.PhaseOrient`:
   - Call `signalStore.ReadRecent(5)`
   - Format compact summary: `"## Quality History\n<summary>"`
   - Append to prompt if budget allows (check budget param)

Format example:
```
## Quality History (last 5 sessions)
- Avg turns: 14, Token efficiency: 0.52
- Tool errors: 2/5 sessions, Complexity: C3-C4
- Outcome: 4/5 success
```

**Test:** `os/Skaffen/internal/session/session_test.go` — mock signal store, verify prompt includes quality history when phase=Orient, excludes it for other phases.

**Acceptance:** Orient system prompt contains quality summary.

## Step 6: Quality history tool

**File:** `os/Skaffen/internal/tool/quality_history.go` (NEW)

Tool implementation:
- Name: `quality_history`
- Description: "View quality signals from recent sessions"
- Schema: `{"type":"object","properties":{"count":{"type":"integer","description":"Number of recent sessions to show (default 5, max 20)"}}}`
- Execute: reads from signal store, formats as JSON array

**File:** `os/Skaffen/internal/tool/register.go` (MODIFY)

Register `quality_history` in `RegisterBuiltins()`.

**File:** `os/Skaffen/internal/agent/gated_registry.go` (MODIFY)

Gate to Orient phase:
```go
string(tool.PhaseOrient): {"quality_history": true, "read": true, "glob": true, ...}
```

**Test:** `os/Skaffen/internal/tool/quality_history_test.go` — mock store, verify tool returns formatted signals.

**Acceptance:** Tool callable during Orient, returns quality data.

## Step 7: Integration test + verify

Run full test suite:
```bash
cd os/Skaffen && go test ./... -count=1
cd os/Skaffen && go vet ./...
```

Verify no import cycles (mutations imports tool.Phase, agent imports mutations — ensure no circular deps).

**Acceptance:** All tests pass, no vet warnings, `go build ./cmd/skaffen` succeeds.

## Dependency Graph

```
Step 1 (types)
  ↓
Step 2 (store) ← Step 3 (aggregate)
  ↓                ↓
Step 4 (wire compound) ← depends on 1,2,3
  ↓
Step 5 (orient prompt) ← depends on 2
  ↓
Step 6 (orient tool) ← depends on 2
  ↓
Step 7 (integration) ← depends on all
```

Steps 5 and 6 are independent of each other and can be done in parallel.
