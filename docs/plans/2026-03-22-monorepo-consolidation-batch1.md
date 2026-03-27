# Plan: Monorepo Consolidation Batch 1

**Date:** 2026-03-22 (amended 2026-03-23 after flux-drive review)
**Epic:** Sylveste-og7m
**PRD:** `docs/prds/2026-03-22-monorepo-consolidation-batch1.md`
**Children:** .10 (P0), .11, .13, .14, .15, .16, .25 (P1)
**Review:** 4 agents (architecture, correctness, safety, quality) — 5 P1+ findings, all addressed below.

## Execution Order

Dependencies dictate order. Most items are parallelizable, but some have logical prerequisites:

```
Phase A (foundations — parallel):
  ├── A1: WorkContext type (.16) — new file, no dependencies
  ├── A2: Phase contract export (.14) — move internal/ → pkg/
  └── A3: Superstar cap (.15) — small scoring.go change

Phase B (dedup — after A2 for phase contract):
  └── B1: Skaffen→Alwe/Zaka import (.10) — the P0

Phase C (security — parallel with B):
  ├── C1: X-Agent-ID verification (.11) — intermute middleware + SQLite agents table
  └── C2: Bead state writer verification (.13) — bd set-state

Phase D (calibration — after foundations):
  └── D1: Interspect closed-loop (.25) — canary outcomes → threshold calibration
```

---

## A1: WorkContext Type (.16)

**Create:** `core/intercore/pkg/workctx/workctx.go`

```go
package workctx

// WorkContext is the (bead, run, session) trinity that identifies a unit of work.
type WorkContext struct {
    BeadID    string `json:"bead_id"`
    RunID     string `json:"run_id"`
    SessionID string `json:"session_id"`
}

// IsZero returns true if all fields are empty.
func (wc WorkContext) IsZero() bool {
    return wc.BeadID == "" && wc.RunID == "" && wc.SessionID == ""
}
```

**Why `core/intercore/pkg/workctx/`:** Skaffen→intercore is a sanctioned L2→L1 dependency (documented in architecture.md). The type is fundamental infrastructure. `sdk/interbase/go` is an alternative if we want to avoid adding intercore to Skaffen's go.mod for a single struct, but intercore is the right home for kernel-level types.

**Convert 3+ reconstruction sites:**
1. `os/Clavain/hooks/lib-sprint.sh` — bash reconstruction of bead+run+session. Add `ic workctx` CLI command that outputs JSON; bash reads it.
2. `os/Clavain/hooks/session-end-release.sh` — identical bead-ID reconstruction. Same CLI command.
3. `core/intercore/internal/coordination/types.go` — if Run or similar types already carry these fields, embed WorkContext.

**New CLI command:** `ic workctx --bead <id> --run <id> --session <id>` outputs JSON. Bash hooks call this instead of reconstructing independently.

**Test:** `core/intercore/pkg/workctx/workctx_test.go`:
- JSON round-trip
- IsZero on empty struct → true
- IsZero with partial fields → false
- Unknown JSON fields are ignored (document forward-compat contract)

---

## A2: Phase Contract Export (.14)

**Key design decision (from review):** OODARC (observe/orient/decide/act/reflect/compound) is the agent's behavioral loop — what it *does* within each lifecycle phase. Lifecycle phases (brainstorm/strategized/planned/executing/...) are where the sprint is. These are orthogonal. The phase contract exports only lifecycle phases. Skaffen's OODARC phases and its internal aliases (PhaseBrainstorm=PhaseOrient etc.) remain Skaffen-internal.

**Current state:** `core/intercore/internal/phase/` has 4 files with 9-phase `DefaultPhaseChain`. All `internal/`.

### Step 1: Extract lifecycle phase constants to exportable package

Create `core/intercore/pkg/phase/phase.go` (package name `phase`, matching existing `internal/phase/`):

```go
package phase

// Lifecycle phase constants — the sprint-level progression.
// OODARC (observe/orient/decide/act/reflect/compound) is the per-turn
// agent behavioral loop and is NOT part of this contract. OODARC happens
// *within* each lifecycle phase. See os/Skaffen/internal/tool/tool.go.
const (
    Brainstorm         = "brainstorm"
    BrainstormReviewed = "brainstorm-reviewed"
    Strategized        = "strategized"
    Planned            = "planned"
    Executing          = "executing"
    Review             = "review"
    Polish             = "polish"
    Reflect            = "reflect"
    Done               = "done"
)

// DefaultChain is the 9-phase Clavain lifecycle.
var DefaultChain = []string{
    Brainstorm, BrainstormReviewed, Strategized, Planned,
    Executing, Review, Polish, Reflect, Done,
}

// Deprecated: use Planned. Alias for lib-sprint.sh phases_json compatibility.
// Will be removed 2026-06-01.
const PlanReviewed = Planned

// Deprecated: use Polish. Alias for lib-sprint.sh phases_json compatibility.
// Will be removed 2026-06-01.
const Shipping = Polish

// IsValid returns true if the phase is in DefaultChain.
func IsValid(p string) bool {
    for _, c := range DefaultChain {
        if c == p {
            return true
        }
    }
    return false
}

// IsValidForChain checks membership in a specific chain.
func IsValidForChain(p string, chain []string) bool {
    for _, c := range chain {
        if c == p {
            return true
        }
    }
    return false
}
```

**No OODARCChain.** Skaffen's OODARC is a different concept (behavioral loop vs lifecycle phase) and already exists at `os/Skaffen/internal/agent/phase.go`.

**Deprecated aliases as constants** (not a map) — `staticcheck` and `godoc` surface these. The old `plan-reviewed` and `shipping` values from live `phases_json` need explicit constants for backward compat.

### Step 2: Update internal/phase to import from pkg/phase

`core/intercore/internal/phase/phase.go` changes its constants to reference `pkg/phase`. Machine logic stays internal.

### Step 3: Fix handler_spawn.go hardcode

Replace literal `"executing"` with `phase.Executing`. **No `run.Config.SpawnPhase` field** — YAGNI (one caller, no second use case).

### Step 4: Add `ic phase list` CLI command

Outputs JSON array of valid phases for the current chain. Clavain's bash reads this instead of maintaining its own phase list. **Fallback:** if `ic` is unavailable, bash degrades to hardcoded chain (not fatal).

### Pre-deploy migration checklist

**CRITICAL (from correctness review):** Before merging A2, audit live runs:
```bash
ic run list --json | jq 'select(.phases == null and (.phase == "plan-reviewed" or .phase == "shipping"))'
```
Any in-flight run at `plan-reviewed` or `shipping` with `phases=NULL` must be migrated before the `DefaultPhaseChain` swap. The deprecated alias constants (`PlanReviewed`, `Shipping`) resolve at CLI input boundaries only — they must **never** be used to normalize stored phase state in `Advance` or `UpdatePhase`.

**Test:** `core/intercore/pkg/phase/phase_test.go`:
- IsValid for all 9 phases → true
- IsValid for "observe", "orient" → false (OODARC, not lifecycle)
- IsValid for "plan-reviewed" → false (deprecated, use PlanReviewed constant)
- IsValidForChain with custom chain
- Deprecated constants equal their canonical values

---

## A3: Superstar Cap (.15)

**File:** `core/intercore/internal/scoring/scoring.go` (line ~409-440)

**Change:** Add maxPerAgent cap and zero-agent guard:

```go
func selectQuality(pairs []scoredPair, ctx *scoringContext, numAgents, numTasks int) []scoredPair {
    if numAgents == 0 {
        return nil
    }
    maxPerAgent := (numTasks + numAgents - 1) / numAgents
    if maxPerAgent < 1 {
        maxPerAgent = 1
    }
    // Quality mode gets +1 over balanced to still prefer best agent
    maxPerAgent += 1

    agentCount := make(map[string]int)
    // ... existing sort-by-score logic ...
    // Skip if agentCount[agent] >= maxPerAgent
}
```

Also add zero-agent guard to `selectBalanced()` for consistency.

**Test:** Add to `scoring_test.go`:
- 10 tasks, 5 agents: no agent gets >3 tasks even with highest score
- Quality mode still prefers higher-scoring agents (not round-robin)
- 0 agents: returns nil, no panic
- Verify total assigned count equals numTasks (no tasks silently dropped)

---

## B1: Skaffen→Alwe/Zaka Import (.10, P0)

**~600-800 LOC of duplication to resolve.**

### Step 1: Export Alwe's observer package

Move: `os/Alwe/internal/observer/` → `os/Alwe/pkg/observer/`

Already well-structured with exported types (`ParseJSONLEvent`, `Event`, `CassObserver`, `SessionResult`). No API changes needed.

### Step 2: Export Zaka's adapter package

Move: `os/Zaka/internal/adapter/` → `os/Zaka/pkg/adapter/`

API stays: `Register()`, `Get()`, `List()`, `Config` struct.

### Step 3: Update Skaffen go.mod

```
require (
    github.com/mistakeknot/Alwe v0.0.0
    github.com/mistakeknot/Zaka v0.0.0
)
replace (
    github.com/mistakeknot/Alwe => ../../os/Alwe
    github.com/mistakeknot/Zaka => ../../os/Zaka
)
```

**Pre-step:** Verify module casing in Alwe/Zaka `go.mod` matches these paths exactly (Go module paths are case-sensitive).

### Step 4: Replace Skaffen copy-forks

1. **Delete** `os/Skaffen/internal/observer/cass.go` and `cass_test.go`
2. **Replace** with import of `github.com/mistakeknot/Alwe/pkg/observer`
3. **Delete** `os/Skaffen/internal/provider/tmuxagent/adapter.go`, `claude.go`, and tests
4. **Replace** with imports from `github.com/mistakeknot/Zaka/pkg/adapter`

**Name divergence resolution:** Update Skaffen call sites to use Zaka's names (`adapter.Config`, `adapter.Register`, `adapter.Get`, `adapter.List`). No type alias layer.

**Pre-step:** Verify no Skaffen-only methods exist on the copy-forked types before deleting.

### Step 5: Verify

- `cd os/Alwe && go test ./...`
- `cd os/Zaka && go test ./...`
- `cd os/Skaffen && go test ./...`

---

## C1: X-Agent-ID Verification (.11)

**File:** `core/intermute/internal/auth/middleware.go`

**Critical fix (from safety review):** The current middleware has a localhost bypass that returns early before `authorize()`. With `AllowLocalhostWithoutAuth: true` (the default), the proposed API-key-path check would never fire. The fix must work in the localhost branch too.

### Approach: Registration-time token in SQLite

1. **At registration time** (`handleRegisterAgent` → `s.store.RegisterAgent()`), generate a short-lived random token and return it to the agent. Store `token → agentID` in the SQLite `agents` table alongside SessionID.

2. **New header:** `X-Agent-Token` — agents include this on every request alongside `X-Agent-ID`.

3. **Middleware check in BOTH code paths:**

```go
// Before the localhost bypass and after agentID extraction:
agentToken := strings.TrimSpace(r.Header.Get("X-Agent-Token"))

// In the localhost bypass branch:
if ring.AllowLocalhostWithoutAuth && isLocalRequest(r) {
    if agentID != "" && agentToken != "" {
        registered, err := store.AgentForToken(agentToken)
        if err == nil && registered != "" && registered != agentID {
            http.Error(w, "agent identity mismatch", http.StatusForbidden)
            return
        }
    }
    // ... continue with existing bypass logic
}

// In the API-key branch (same check):
if agentID != "" {
    registered, err := store.AgentForToken(agentToken)
    if err == nil && registered != "" && registered != agentID {
        http.Error(w, "agent identity mismatch", http.StatusForbidden)
        return
    }
}
```

4. **Bound token enforcement:** If a token has a binding, the `X-Agent-ID` must match. If `X-Agent-ID` is omitted but token is bound, reject (prevents header-omission bypass).

5. **Backward compat:** If no `X-Agent-Token` header is sent, no check fires. Agents provisioned before this change continue to work. **Graduation trigger:** after all active agents have been observed sending `X-Agent-Token` for 7 days, graduate to enforce-all (logged warning → hard reject).

**Why SQLite not Keyring:** The Keyring is immutable at runtime (loaded once from YAML at startup). Agent registration happens at runtime via `handleRegisterAgent`. The SQLite `agents` table is the natural home for runtime bindings.

**Test:** `middleware_test.go`:
- Agent A registers, gets token T1. Agent B sends T1 with X-Agent-ID: "B" → 403
- Agent omits X-Agent-Token header → passes (backward compat)
- Agent sends bound token with no X-Agent-ID header → 403
- Localhost request with valid token + matching ID → passes

---

## C2: Bead State Writer Verification (.13)

**Scope:** `bd` CLI change.

**Critical fix (from safety review):** Protected dimensions must be hard-coded in the binary, not in config. Config can only ADD dimensions.

### Implementation

1. **Hard-coded canonical dimensions** in beads binary:
   ```go
   var canonicalProtectedDimensions = []string{
       "ic_run_id", "dispatch_count", "autonomy_tier", "phase",
   }
   ```

2. **Config extends** (never reduces) the canonical list:
   ```yaml
   state:
     additional-protected-dimensions:
       - custom_field
   ```

3. **Check logic** in `set-state` handler:
   - If dimension is in canonical + additional list AND bead has `claimed_by` set:
   - Require `--actor` flag, verify actor matches `claimed_by`
   - If no `claimed_by` set (unclaimed), allow write (progressive enforcement)

4. **Atomicity note:** The check-and-write is not fully atomic (TOCTOU between reading `claimed_by` and writing state). Full fix requires Dolt transactions — tracked as follow-up. Current design is a meaningful improvement over zero protection.

**Test:**
- `claimed_by=agent-A`, `bd set-state <id> phase=done --actor=agent-B` → rejected
- `claimed_by=agent-A`, `bd set-state <id> phase=done --actor=agent-A` → succeeds
- No `claimed_by` set → write succeeds regardless of actor
- Custom dimension in config → also protected

---

## D1: Interspect Confidence Calibration (.25)

**Current state:** Hardcoded thresholds in shell scripts (≥3 events + ≥0.7 confidence).

### Step 1: Canary outcome schema

Add to interspect.db (SQLite):
```sql
CREATE TABLE canary_outcomes (
    id INTEGER PRIMARY KEY,
    agent_name TEXT NOT NULL,
    override_id TEXT NOT NULL,
    applied_at INTEGER NOT NULL,   -- Unix epoch seconds (matches project convention)
    measured_at INTEGER NOT NULL,  -- Unix epoch seconds
    metric TEXT NOT NULL,
    baseline_value REAL,
    override_value REAL,
    outcome TEXT NOT NULL           -- 'improved', 'degraded', 'neutral'
);
```

**Note:** `INTEGER NOT NULL` for timestamps, matching the project convention (`time.Now().Unix()`, not TEXT).

### Step 2: Record canary outcomes

New CLI: `clavain-cli interspect-record-canary --agent <name> --override <id> --metric <metric> --baseline <val> --measured <val> --outcome <improved|degraded|neutral>`

**SQLite concurrency fix (from correctness review):** Set `_busy_timeout=5000` in DSN when opening interspect.db. If insert still fails, write to `.clavain/interspect/canary-pending.jsonl` as sidecar. The calibration command drains the sidecar on each run.

### Step 3: Calibrate thresholds

New CLI: `clavain-cli interspect-calibrate-thresholds`

Logic:
1. Drain any pending records from `canary-pending.jsonl` into the DB
2. Read canary_outcomes from last 30 days (not 7 — need sufficient sample)
3. For each agent: compute improvement rate (improved_count / total)
4. If improvement rate > 0.6: lower confidence threshold (min floor: 0.3)
5. If improvement rate < 0.3: raise confidence threshold (max ceiling: 0.95)
6. Write adjusted thresholds to `.clavain/interspect/calibrated-thresholds.json`

### Step 4: Wire into existing flow — both manual and automated

**Manual:** `/interspect:calibrate` calls `clavain-cli interspect-calibrate-thresholds` after computing per-agent scores.

**Automated (from architecture review — PHILOSOPHY compliance):** Add a post-sprint hook (in Clavain's `reflect` phase) that calls `clavain-cli interspect-calibrate-thresholds` automatically. This closes the OODARC Compound step: evidence from the sprint feeds back into routing for the next sprint without human intervention.

The compose step in `compose.go` reads calibrated thresholds and falls back to hardcoded defaults if file missing.

### Test
- Feed 10 mock outcomes (7 improved, 3 degraded) → threshold adjusts downward for >60% rate
- All degraded → threshold raises but does not exceed 0.95
- Mixed agents: agent-A improves, agent-B degrades → per-agent, not global
- Concurrent writes: 5 goroutines writing simultaneously → all 5 rows present (busy_timeout test)

---

## Verification Sequence

After all changes:
1. `cd core/intercore && go test ./...` — phase, scoring, workctx
2. `cd core/intermute && go test ./...` — auth middleware
3. `cd os/Alwe && go test ./...` — exported observer
4. `cd os/Zaka && go test ./...` — exported adapter
5. `cd os/Skaffen && go test ./...` — imports working, no copy-forks
6. `cd os/Clavain && go test ./...` — interspect calibration
7. `bd set-state` protected dimension test (manual)

## Build Sequence

```
A1 → commit "feat(intercore): add WorkContext type in pkg/workctx"
A2 → commit "feat(intercore): export lifecycle phase contract to pkg/phase"
A3 → commit "fix(intercore): add maxPerAgent cap and zero-guard to selectQuality"
B1 → commit "fix(skaffen): replace copy-forks with Alwe/Zaka imports (P0)"
C1 + C2 → commit "fix(security): registration-token identity binding, protected bead dimensions"
D1 → commit "feat(interspect): canary outcome tracking and threshold calibration"
```

6 commits (split A into 3 for clean bisection). Each independently testable.
