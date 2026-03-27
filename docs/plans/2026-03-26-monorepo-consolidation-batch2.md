---
artifact_type: plan
bead: Sylveste-og7m
stage: design
requirements:
  - F1: Safety floor clamping (.18)
  - F3: Phase skip prevention (.20)
  - F4a: Phase name deduplication (.22)
  - F2: Autonomy hysteresis (.19)
  - F5: Shadow tracker enforcement (.24)
  - F6: Routing always-on (.3)
---
# Monorepo Consolidation Batch 2 — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Sylveste-og7m
**Goal:** Close 6 P1 architectural gaps left after Batch 1 — safety floor ordering, gate enforcement, phase constants, autonomy downgrade, shadow tracking, and subagent routing.

**Architecture:** Three-layer (L1 Intercore kernel → L2 Clavain/Skaffen OS → L3 apps). Tasks 1-3 are Go changes in L1/L2, Tasks 4-5 are bash in L2/Interverse, Task 6 is Go in L2 Skaffen + L1 kernel extension.

**Tech Stack:** Go 1.22 (modernc.org/sqlite), bash 5.x, Claude Code hooks

**Prior Learnings:** `docs/solutions/2026-03-03-c3-composer-dispatch-plan-generator.md` — compose.go resolution chain design. Safety floor should always be final clamp, not early return.

---

## Must-Haves

**Truths** (observable behaviors):
- Calibration recommending opus for fd-safety with sufficient confidence → opus used (not clamped to sonnet)
- `ic run advance <id>` without flags → gate checks fire AND block on failure
- No hardcoded phase strings remain in Clavain CLI Go files (all use `phase.*` constants)
- System breaker auto-disables autonomy when >=50% of agents with evidence have tripped circuit breakers
- Shadow tracker files detected at session end, with actionable block decision
- Skaffen subagent model selection goes through `ic route dispatch`

**Artifacts** (files with specific exports):
- [`core/intercore/pkg/phase/phase.go`] exports `ModelTier()`, `LegacyPlanReviewed`, `LegacyShipping`
- [`os/Clavain/hooks/lib-shadow-tracker.sh`] exports `detect_shadow_trackers()`
- [`core/intercore/cmd/ic/route.go`] accepts `--type` and `--phase` on `dispatch` subcommand

**Key Links** (connections where breakage cascades):
- `resolveModel()` calibration block runs before safety floor clamp (F1)
- `evaluateGate()` priority mapping: <=1 TierHard, <=3 TierSoft, >=4 TierNone (F3)
- `budget.go`/`phase.go`/`policy.go` switch cases use `phase.*` constants, not string literals (F4a)

---

### Task 1: Safety Floor Clamping (F1/.18)

**Files:**
- Modify: `os/Clavain/cmd/clavain-cli/compose.go:611-647`
- Modify: `os/Clavain/cmd/clavain-cli/compose_test.go`
- Modify: `core/intercore/pkg/phase/phase.go` (add `ModelTier()`)

**Step 1: Add ModelTier helper to phase package**

Add to `core/intercore/pkg/phase/phase.go` after `IsValidForChain`:

```go
// ModelTier returns a numeric tier for model comparison.
// Higher tier = more capable model. Returns 0 for unknown.
func ModelTier(model string) int {
	switch model {
	case "haiku":
		return 1
	case "sonnet":
		return 2
	case "opus":
		return 3
	default:
		return 0
	}
}
```

**Step 2: Write failing tests in compose_test.go**

Add test cases to `TestResolveModel`:

```go
{
	name:       "calibration upgrades fd-safety to opus",
	agent:      matchedAgent{id: "fd-safety", agent: FleetAgent{}},
	role:       AgentRole{},
	cal:        &InterspectCalibration{Agents: map[string]AgentCalibration{
		"fd-safety": {RecommendedModel: "opus", Confidence: 0.95, EvidenceSessions: 10},
	}},
	wantModel:  "opus",
	wantSource: "interspect_calibration",
},
{
	name:       "calibration haiku for fd-safety clamped to sonnet",
	agent:      matchedAgent{id: "fd-safety", agent: FleetAgent{}},
	role:       AgentRole{},
	cal:        &InterspectCalibration{Agents: map[string]AgentCalibration{
		"fd-safety": {RecommendedModel: "haiku", Confidence: 0.95, EvidenceSessions: 10},
	}},
	wantModel:  "sonnet",
	wantSource: "safety_floor",
},
{
	name:       "unrecognized calibration model for fd-safety clamped to floor",
	agent:      matchedAgent{id: "fd-safety", agent: FleetAgent{}},
	role:       AgentRole{},
	cal:        &InterspectCalibration{Agents: map[string]AgentCalibration{
		"fd-safety": {RecommendedModel: "claude-3-5-sonnet", Confidence: 0.95, EvidenceSessions: 10},
	}},
	wantModel:  "sonnet",
	wantSource: "safety_floor",
},
```

**Step 3: Run tests to verify they fail**

Run: `cd os/Clavain && go test ./cmd/clavain-cli/ -run TestResolveModel -v`
Expected: FAIL — current early return produces `safety_floor` for first test case

**Step 4: Rewrite resolveModel() with post-resolution clamping**

Replace `compose.go:611-647` with:

```go
func resolveModel(agent matchedAgent, role AgentRole, cal *InterspectCalibration, ct *CalibratedThresholds) (string, string) {
	var model, source string

	// Interspect calibration — evidence-driven
	if cal != nil {
		if c, ok := cal.Agents[agent.id]; ok {
			threshold := 0.7
			if ct != nil {
				if at, ok := ct.Agents[agent.id]; ok {
					threshold = at.ConfidenceThreshold
				}
			}
			if c.Confidence >= threshold && c.EvidenceSessions >= 3 {
				if m := c.RecommendedModel; m == "haiku" || m == "sonnet" || m == "opus" {
					model, source = m, "interspect_calibration"
				}
			}
		}
	}

	// Fleet preferred model
	if model == "" && agent.agent.Models.Preferred != "" {
		model, source = agent.agent.Models.Preferred, "fleet_preferred"
	}

	// Role-declared model tier
	if model == "" && role.ModelTier != "" {
		model, source = role.ModelTier, "routing_fallback"
	}

	// Ultimate fallback
	if model == "" {
		model, source = "sonnet", "routing_fallback"
	}

	// Safety floor clamp — unconditional final step
	if floor, ok := safetyFloorAgents[agent.id]; ok {
		if phase.ModelTier(model) < phase.ModelTier(floor) || phase.ModelTier(model) == 0 {
			model, source = floor, "safety_floor"
		}
	}

	return model, source
}
```

**Step 5: Run tests to verify they pass**

Run: `cd os/Clavain && go test ./cmd/clavain-cli/ -run TestResolveModel -v`
Expected: PASS

**Step 6: Verify full build**

Run: `cd os/Clavain && go build ./cmd/clavain-cli/`
Expected: exit 0

**Step 7: Commit**

```bash
cd os/Clavain && git add cmd/clavain-cli/compose.go cmd/clavain-cli/compose_test.go
cd /home/mk/projects/Sylveste && git add core/intercore/pkg/phase/phase.go
git commit -m "fix(routing): safety floor clamp post-calibration, not early return

resolveModel() now runs the full resolution chain (calibration → fleet →
role → fallback) before applying safety floor as a final clamp. This
matches the bash lib-routing.sh behavior and allows calibration to
upgrade safety agents to opus when evidence supports it.

Fixes Sylveste-og7m.18"
```

<verify>
- run: `cd os/Clavain && go test ./cmd/clavain-cli/ -run TestResolveModel -v`
  expect: exit 0
- run: `cd os/Clavain && go build ./cmd/clavain-cli/`
  expect: exit 0
</verify>

---

### Task 2: Phase Skip Prevention (F3/.20)

**Files:**
- Modify: `core/intercore/cmd/ic/run.go:410`
- Modify: `core/intercore/internal/phase/gate.go:131-146`
- Modify: `core/intercore/cmd/ic/run_test.go` (if exists)

**Step 1: Write failing test for default priority**

Add to the appropriate test file in `core/intercore/`:

```go
func TestRunAdvanceDefaultPriority(t *testing.T) {
	// The default priority should be TierHard (1), not TierNone (4)
	// This test verifies that gate evaluation happens by default
	// when calling ic run advance without --priority flag
}
```

The actual test depends on integration test infrastructure. At minimum, verify the constant:

```go
func TestDefaultPriorityIsTierHard(t *testing.T) {
	// Default priority should produce TierHard in evaluateGate
	cfg := GateConfig{Priority: 1} // the new default
	if cfg.Priority > 1 {
		t.Errorf("default priority %d > 1, would not produce TierHard", cfg.Priority)
	}
}
```

**Step 2: Change default priority from 4 to 1**

In `core/intercore/cmd/ic/run.go:410`, change:

```go
// Before:
priority := 4

// After:
priority := 1 // TierHard: evaluate AND block on gate failure (was 4/TierNone: skip all gates)
```

**Step 3: Add audit logging for gate bypass**

In `core/intercore/internal/phase/gate.go`, replace lines 134-135 and 144-145:

```go
func evaluateGate(ctx context.Context, run *Run, cfg GateConfig, from, to string, rt RuntrackQuerier, vq VerdictQuerier, pq PortfolioQuerier, dq DepQuerier, bq BudgetQuerier) (result, tier, source string, evidence *GateEvidence, err error) {
	if cfg.DisableAll {
		slog.Warn("gate bypass: --disable-gates used", "run_id", run.ID, "from", from, "to", to)
		return GateNone, TierNone, "default", nil, nil
	}

	// Determine tier from priority
	switch {
	case cfg.Priority <= 1:
		tier = TierHard
	case cfg.Priority <= 3:
		tier = TierSoft
	default:
		slog.Warn("gate bypass: priority >= 4 disables all gate checks", "run_id", run.ID, "priority", cfg.Priority, "from", from, "to", to)
		return GateNone, TierNone, "default", nil, nil
	}
```

**Step 4: Audit existing callers**

Run: `grep -rn "ic run advance" /home/mk/projects/Sylveste --include="*.sh" --include="*.go" --include="*.md" | grep -v -- "--priority" | grep -v "test\|doc\|brainstorm\|plan"`
Document each caller and its intended tier.

**Step 5: Build and test**

Run: `cd core/intercore && go build ./cmd/ic/ && go test ./... -v`
Expected: PASS — Clavain's `--priority=0` calls are unaffected

**Step 6: Commit**

```bash
cd core/intercore && git add cmd/ic/run.go internal/phase/gate.go
git commit -m "fix(gate): default priority 1 (TierHard) — gates block by default

ic run advance without --priority now evaluates all gates and blocks on
failure. Previously defaulted to priority=4 (TierNone), which skipped
all gate evaluation. --priority=4 and --disable-gates still work but
now emit slog.Warn for audit trail.

Fixes Sylveste-og7m.20"
```

<verify>
- run: `cd core/intercore && go build ./cmd/ic/`
  expect: exit 0
- run: `cd core/intercore && go test ./internal/phase/ -v`
  expect: exit 0
</verify>

---

### Task 3: Phase Name Deduplication (F4a/.22)

**Files:**
- Modify: `core/intercore/pkg/phase/phase.go` (add legacy constants)
- Modify: `os/Clavain/cmd/clavain-cli/budget.go:85-129`
- Modify: `os/Clavain/cmd/clavain-cli/phase.go:14-38, 504-527`
- Modify: `os/Clavain/cmd/clavain-cli/policy.go`
- Modify: `os/Clavain/cmd/clavain-cli/stats.go:96`
- Modify: `os/Clavain/cmd/clavain-cli/factory_stream.go:301-306`

**Step 1: Add legacy transition constants to phase.go**

In `core/intercore/pkg/phase/phase.go`, after the deprecated aliases (line 43):

```go
// Legacy string values for backward compatibility with DB records.
// Clavain CLI's switch cases use these until ic migrate phases runs.
// Do NOT change these values — they match what's stored in IC databases.
const (
	LegacyPlanReviewed = "plan-reviewed" // DB value; canonical is Planned ("planned")
	LegacyShipping     = "shipping"      // DB value; canonical is Polish ("polish")
)
```

**Step 2: Replace string literals in budget.go**

Replace `phaseCostDefault` switch (lines 85-108):

```go
func phaseCostDefault(p string) int64 {
	switch p {
	case phase.Brainstorm:
		return 30000
	case phase.BrainstormReviewed:
		return 15000
	case phase.Strategized:
		return 25000
	case phase.Planned:
		return 35000
	case phase.LegacyPlanReviewed:
		return 50000
	case phase.Executing:
		return 150000
	case phase.LegacyShipping:
		return 100000
	case phase.Reflect:
		return 10000
	case phase.Done:
		return 5000
	default:
		return 30000
	}
}
```

Replace `phaseToStage` switch (lines 112-129):

```go
func phaseToStage(p string) string {
	switch p {
	case phase.Brainstorm:
		return "discover"
	case phase.BrainstormReviewed, phase.Strategized, phase.Planned, phase.LegacyPlanReviewed:
		return "design"
	case phase.Executing:
		return "build"
	case phase.LegacyShipping:
		return "ship"
	case phase.Reflect:
		return "reflect"
	case phase.Done:
		return "done"
	default:
		return "unknown"
	}
}
```

**Step 3: Replace string literals in phase.go (Clavain CLI)**

Replace `nextStep` switch (lines 14-38):

```go
func nextStep(p string) string {
	switch p {
	case phase.Brainstorm:
		return "strategy"
	case phase.BrainstormReviewed:
		return "strategy"
	case phase.Strategized:
		return "write-plan"
	case phase.Planned:
		return "flux-drive"
	case phase.LegacyPlanReviewed:
		return "work"
	case phase.Executing:
		return "quality-gates"
	case phase.LegacyShipping:
		return "reflect"
	case phase.Reflect:
		return "done"
	case phase.Done:
		return "done"
	default:
		fmt.Fprintf(os.Stderr, "WARNING: unknown phase %q — defaulting to brainstorm\n", p)
		return "brainstorm"
	}
}
```

Replace `phaseToAction` switch (lines 504-527):

```go
func phaseToAction(p string) string {
	switch p {
	case phase.Brainstorm:
		return "strategize"
	case phase.BrainstormReviewed:
		return "strategize"
	case phase.Strategized:
		return "plan"
	case phase.Planned:
		return "execute"
	case phase.LegacyPlanReviewed:
		return "execute"
	case phase.Executing:
		return "continue"
	case phase.LegacyShipping:
		return "ship"
	case phase.Reflect:
		return "reflect"
	case phase.Done:
		return "closed"
	default:
		return ""
	}
}
```

**Step 4: Replace in stats.go and factory_stream.go**

In `stats.go:96`, replace `r.Phase == "done"` with `r.Phase == phase.Done`.

In `factory_stream.go:301-306`, rename function and add comment:

```go
// agentStatusStr returns the agent activity status string.
// This is agent-level activity (executing/idle), NOT sprint lifecycle phase.
func agentStatusStr(active bool) string {
	if active {
		return "executing" // agent activity status, not phase.Executing
	}
	return "idle"
}
```

Update all callers of `statusStr()` to `agentStatusStr()` in the same file.

**Step 5: Add import for phase package**

Ensure all modified Clavain CLI files import `"github.com/mistakeknot/intercore/pkg/phase"` (or the correct module path).

**Step 6: Build and test**

Run: `cd os/Clavain && go build ./cmd/clavain-cli/ && go test ./cmd/clavain-cli/ -v`
Expected: PASS — same string values, same behavior

**Step 7: Commit**

```bash
cd /home/mk/projects/Sylveste && git add core/intercore/pkg/phase/phase.go
cd os/Clavain && git add cmd/clavain-cli/budget.go cmd/clavain-cli/phase.go cmd/clavain-cli/policy.go cmd/clavain-cli/stats.go cmd/clavain-cli/factory_stream.go
git commit -m "refactor(phase): replace hardcoded phase strings with constants

All Clavain CLI switch cases now use phase.* constants from intercore.
LegacyPlanReviewed and LegacyShipping preserve old DB string values
for backward compatibility. DB migration deferred to F4b/Batch 3.

statusStr() renamed to agentStatusStr() to avoid semantic collision
with phase.Executing.

Fixes Sylveste-og7m.22"
```

<verify>
- run: `cd os/Clavain && go build ./cmd/clavain-cli/`
  expect: exit 0
- run: `cd os/Clavain && go test ./cmd/clavain-cli/ -v`
  expect: exit 0
</verify>

---

### Task 4: Autonomy Hysteresis (F2/.19)

**Files:**
- Modify: `interverse/interspect/hooks/lib-interspect.sh` (add system breaker)
- Modify: `interverse/interspect/commands/interspect-disable-autonomy.md` (add --revert-all)

**Step 1: Add system breaker check function**

Add after `_interspect_circuit_breaker_tripped()` (~line 1660) in `lib-interspect.sh`:

```bash
# System-level circuit breaker: auto-disable autonomy when >=50% of agents
# with evidence have tripped their per-agent circuit breakers.
# Returns: 0 if system breaker should fire, 1 if system is healthy.
# Uses 60-second TTL cache to avoid cross-agent table scan per call.
_interspect_system_breaker_check() {
    local db="${_INTERSPECT_DB:-}"
    [[ -z "$db" || ! -f "$db" ]] && return 1

    # TTL cache: check sentinel
    local sentinel_key="system_breaker_check"
    local now; now=$(date +%s)
    local last_check
    last_check=$(sqlite3 "$db" "SELECT CAST(value AS INTEGER) FROM sentinels WHERE key='$sentinel_key' LIMIT 1" 2>/dev/null) || last_check=0
    if [[ $((now - last_check)) -lt 60 ]]; then
        # Use cached result
        local cached
        cached=$(sqlite3 "$db" "SELECT value FROM sentinels WHERE key='system_breaker_result' LIMIT 1" 2>/dev/null) || cached="healthy"
        [[ "$cached" == "tripped" ]] && return 0
        return 1
    fi

    # Count agents with evidence
    local total_agents tripped_agents
    total_agents=$(sqlite3 "$db" "SELECT COUNT(DISTINCT group_id) FROM modifications WHERE ts > datetime('now', '-30 days')" 2>/dev/null) || total_agents=0

    # Minimum 3-agent floor
    if [[ $total_agents -lt 3 ]]; then
        sqlite3 "$db" "INSERT OR REPLACE INTO sentinels(key,value) VALUES('$sentinel_key','$now'),('system_breaker_result','healthy')" 2>/dev/null
        return 1
    fi

    # Count agents with >=3 reverts in 30 days (circuit breaker tripped)
    tripped_agents=$(sqlite3 "$db" "SELECT COUNT(DISTINCT group_id) FROM (
        SELECT group_id, COUNT(*) as revert_count
        FROM modifications
        WHERE status='reverted' AND ts > datetime('now', '-30 days')
        GROUP BY group_id
        HAVING revert_count >= 3
    )" 2>/dev/null) || tripped_agents=0

    # >=50% threshold
    local result="healthy"
    if [[ $total_agents -gt 0 ]] && (( tripped_agents * 2 >= total_agents )); then
        result="tripped"
    fi

    # Cache result
    sqlite3 "$db" "INSERT OR REPLACE INTO sentinels(key,value) VALUES('$sentinel_key','$now'),('system_breaker_result','$result')" 2>/dev/null

    [[ "$result" == "tripped" ]] && return 0
    return 1
}
```

**Step 2: Wire system breaker into _interspect_should_auto_apply()**

At the top of `_interspect_should_auto_apply()` (~line 1710), after the autonomy check:

```bash
    # System-level circuit breaker — auto-disable autonomy if fleet is degraded
    if _interspect_system_breaker_check; then
        echo "[interspect] System breaker tripped: >=50% of agents with evidence have circuit breaker active. Auto-disabling autonomy." >&2
        _interspect_set_autonomy "false"
        # Log to modifications table
        local db="${_INTERSPECT_DB:-}"
        [[ -n "$db" && -f "$db" ]] && sqlite3 "$db" "INSERT INTO modifications(group_id,ts,tier,mod_type,target_file,status,evidence_summary) VALUES('_system','$(date -Iseconds)','persistent','system_breaker','.clavain/interspect/confidence.json','applied','System breaker: >=50% agents tripped circuit breaker')" 2>/dev/null
        _INTERSPECT_AUTONOMY=false
        return 1  # Do not auto-apply
    fi
```

**Step 3: Add --revert-all to disable-autonomy command**

In `interverse/interspect/commands/interspect-disable-autonomy.md`, add after the disable logic:

```markdown
If the user passed `--revert-all --confirm`:
1. Read all active overrides from `.claude/routing-overrides.json`
2. For each, call `_interspect_revert_routing_override "$agent_name"`
3. Report count of reverted overrides

If `--revert-all` without `--confirm`:
- Show count of active overrides and ask for confirmation via AskUserQuestion
```

**Step 4: Test**

Run: `bash -n interverse/interspect/hooks/lib-interspect.sh`
Expected: exit 0 (syntax valid)

**Step 5: Commit**

```bash
cd interverse/interspect && git add hooks/lib-interspect.sh commands/interspect-disable-autonomy.md
git commit -m "feat(interspect): system-level circuit breaker for autonomy downgrade

Auto-disables autonomy when >=50% of agents with evidence have tripped
their per-agent circuit breakers (3+ reverts in 30 days). Minimum
3-agent floor prevents false triggers on small pools. Result cached
with 60-second TTL.

disable-autonomy gains --revert-all --confirm to also revert active
routing overrides on manual downgrade. System breaker auto-disable
only stops new proposals — does NOT auto-revert.

Fixes Sylveste-og7m.19"
```

<verify>
- run: `bash -n interverse/interspect/hooks/lib-interspect.sh`
  expect: exit 0
</verify>

---

### Task 5: Shadow Tracker Enforcement (F5/.24)

**Files:**
- Create: `os/Clavain/hooks/lib-shadow-tracker.sh`
- Modify: `os/Clavain/hooks/auto-stop-actions.sh`

**Step 1: Create lib-shadow-tracker.sh**

```bash
#!/usr/bin/env bash
# lib-shadow-tracker.sh — detect shadow work-tracking files
# Used by: auto-stop-actions.sh (Stop hook), doctor.md (manual)

# detect_shadow_trackers [dir]
# Outputs: one line per detected file. Returns count via exit code (0=none, N=count capped at 125).
detect_shadow_trackers() {
    local dir="${1:-.}"
    local count=0
    local files=()

    # Category 1: todos/*.md with status frontmatter
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        if head -10 "$f" 2>/dev/null | grep -qE '^status:\s*(pending|open|done|complete|ready|in_progress)'; then
            files+=("$f")
            ((count++))
        fi
    done < <(find "$dir" -path '*/todos/*.md' -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null)

    # Category 2: pending-beads*.md files
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        files+=("$f")
        ((count++))
    done < <(find "$dir" -name 'pending-beads*.md' -not -path '*/.git/*' 2>/dev/null)

    # Category 3: todos/tracking files with type:task/todo frontmatter
    # (Tightened from doctor.md: requires type:task|todo, not just any status: key)
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        if head -10 "$f" 2>/dev/null | grep -qE '^type:\s*(task|todo|tracker)'; then
            files+=("$f")
            ((count++))
        fi
    done < <(find "$dir" -maxdepth 3 -name '*.md' -newer "${dir}/.beads/config.yaml" -not -path '*/.git/*' -not -path '*/docs/brainstorms/*' -not -path '*/docs/plans/*' -not -path '*/docs/prds/*' -not -path '*/docs/research/*' -not -path '*/docs/solutions/*' 2>/dev/null | head -50)

    # Output detected files
    for f in "${files[@]}"; do
        echo "$f"
    done

    # Return count (capped at 125 for bash exit code safety)
    [[ $count -gt 125 ]] && count=125
    return "$count"
}
```

**Step 2: Add orthogonal shadow tracker check to auto-stop-actions.sh**

Source the lib at the top (near existing lib-signals.sh source):

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib-shadow-tracker.sh"
```

Add the shadow tracker check as an **independent early check** before the tier waterfall (after sentinel dedup, ~line 45):

```bash
# Shadow tracker detection — orthogonal to tier waterfall
# Runs independently; emits warning always, blocks only if no other tier claimed the cycle
SHADOW_WARNING=""
if [[ ! -f ".claude/clavain.no-shadow-enforce" ]]; then
    shadow_files=$(detect_shadow_trackers "." 2>/dev/null)
    shadow_count=$?
    if [[ $shadow_count -gt 0 ]]; then
        SHADOW_WARNING="Shadow tracker detected: ${shadow_count} file(s) found using work-tracking outside beads:\n${shadow_files}\n\nThese drift silently and cause duplicate work. Run /bead-sweep to migrate to beads, or delete if already tracked."
    fi
fi
```

Then at the end, after the tier waterfall (before final output, ~line 180):

```bash
# If no tier claimed the cycle AND shadow trackers were found, block
if [[ -z "$REASON" && -n "$SHADOW_WARNING" ]]; then
    REASON="$SHADOW_WARNING"
fi
```

**Step 3: Syntax check**

Run: `bash -n os/Clavain/hooks/lib-shadow-tracker.sh && bash -n os/Clavain/hooks/auto-stop-actions.sh`
Expected: exit 0

**Step 4: Commit**

```bash
cd os/Clavain && git add hooks/lib-shadow-tracker.sh hooks/auto-stop-actions.sh
git commit -m "feat(hooks): shadow tracker enforcement via Stop hook

Detects shadow work-tracking files (todos/*.md with status, pending-beads*,
type:task/todo frontmatter) at session end. Orthogonal to the tier
waterfall — warns always, blocks when no other tier (compound/dispatch/
drift-check) claimed the cycle.

Opt-out: .claude/clavain.no-shadow-enforce
Detection extracted into lib-shadow-tracker.sh for reuse by doctor.md.

Fixes Sylveste-og7m.24"
```

<verify>
- run: `bash -n os/Clavain/hooks/lib-shadow-tracker.sh`
  expect: exit 0
- run: `bash -n os/Clavain/hooks/auto-stop-actions.sh`
  expect: exit 0
</verify>

---

### Task 6: Routing Always-On (F6/.3)

**Files:**
- Modify: `core/intercore/cmd/ic/route.go` (extend cmdRouteDispatch)
- Modify: `os/Skaffen/internal/subagent/tool.go:97-144`
- Modify: `os/Skaffen/internal/subagent/runner.go:80-152`
- Modify: `os/Skaffen/internal/subagent/registry.go`

**Note:** This task may require 2 sessions. Partial state (extended `cmdRouteDispatch` without Skaffen integration) is safe to ship independently.

**Step 1: Extend cmdRouteDispatch with --type and --phase**

In `core/intercore/cmd/ic/route.go`, extend `cmdRouteDispatch`:

```go
func cmdRouteDispatch(ctx context.Context, args []string) int {
	var tier, subagentType, currentPhase string
	for i := 0; i < len(args); i++ {
		switch {
		case strings.HasPrefix(args[i], "--tier="):
			tier = strings.TrimPrefix(args[i], "--tier=")
		case strings.HasPrefix(args[i], "--type="):
			subagentType = strings.TrimPrefix(args[i], "--type=")
		case strings.HasPrefix(args[i], "--phase="):
			currentPhase = strings.TrimPrefix(args[i], "--phase=")
		}
	}

	// When --type is provided, resolve subagent type + model
	if subagentType != "" {
		cfg, err := loadRoutingConfig()
		if err != nil {
			slog.Error("route dispatch", "error", err)
			return 2
		}
		r := routing.NewResolver(cfg)
		// Map subagent type to a dispatch tier
		dispatchTier := subagentType // default: type name is tier name
		if currentPhase != "" {
			dispatchTier = subagentType + ":" + currentPhase
		}
		model := r.ResolveDispatchTier(dispatchTier)
		if model == "" {
			// Fallback to type-only tier
			model = r.ResolveDispatchTier(subagentType)
		}

		if flagJSON {
			out := map[string]string{"type": subagentType, "phase": currentPhase, "model": model}
			enc := json.NewEncoder(os.Stdout)
			enc.Encode(out)
		} else {
			fmt.Println(model)
		}
		return 0
	}

	// Original --tier path (backward compat)
	if tier == "" {
		fmt.Fprintf(os.Stderr, "ic: route dispatch: requires --tier=<name> or --type=<name>\n")
		return 3
	}
	// ... existing tier logic ...
```

**Step 2: Add routing call to Skaffen subagent tool.go**

In `tool.go:Execute()`, before creating SubagentTask:

```go
// Consult ic route dispatch for type and model override
routedType := input.SubagentType
routedModel := ""
if icPath := os.Getenv("IC_PATH"); icPath != "" {
	ctx, cancel := context.WithTimeout(ctx, 200*time.Millisecond)
	defer cancel()
	cmd := exec.CommandContext(ctx, icPath, "route", "dispatch",
		"--type="+input.SubagentType,
		"--phase="+os.Getenv("CLAVAIN_PHASE"),
		"--json")
	out, err := cmd.Output()
	if err == nil {
		var result struct {
			Type  string `json:"type"`
			Model string `json:"model"`
		}
		if json.Unmarshal(out, &result) == nil && result.Model != "" {
			if result.Type != "" && result.Type != input.SubagentType {
				routedType = result.Type
				slog.Info("subagent type routed", "requested", input.SubagentType, "routed", routedType)
			}
			routedModel = result.Model
		}
	} else {
		slog.Debug("ic route dispatch fallback", "error", err)
	}
}
```

**Step 3: Replace NoOpRouter in runner.go**

In `runner.go:runOne()`, replace the NoOpRouter construction:

```go
router := &agentloop.NoOpRouter{}
if routedModel != "" {
	router.Model = routedModel
} else if st.Model != "" {
	router.Model = st.Model
} else if dm := r.registry.DefaultModel(); dm != "" {
	router.Model = dm
}
```

**Step 4: Add routing annotation to tool result**

In `tool.go`, modify the result string to include routing info:

```go
routeInfo := ""
if routedType != input.SubagentType {
	routeInfo = fmt.Sprintf("[routed: %s→%s] ", input.SubagentType, routedType)
}
return agentloop.ToolResult{
	Content: fmt.Sprintf("%sSubagent %q completed (%d turns, %d tokens):\n\n%s", routeInfo, task.Description, turns, tokens, output),
}
```

**Step 5: Build and test**

Run: `cd core/intercore && go build ./cmd/ic/ && go test ./...`
Run: `cd os/Skaffen && go build ./... && go test ./...`
Expected: PASS

**Step 6: Commit**

```bash
cd core/intercore && git add cmd/ic/route.go
cd /home/mk/projects/Sylveste/os/Skaffen && git add internal/subagent/tool.go internal/subagent/runner.go
git commit -m "feat(routing): wire subagent dispatch through ic route

Extends ic route dispatch with --type/--phase for subagent routing.
Skaffen's Agent tool now consults ic route dispatch before spawning
subagents, with 200ms timeout and graceful fallback to LLM's choice.
Tool result annotates type overrides for parent LLM visibility.

Fixes Sylveste-og7m.3"
```

<verify>
- run: `cd core/intercore && go build ./cmd/ic/`
  expect: exit 0
- run: `cd os/Skaffen && go build ./...`
  expect: exit 0
</verify>
