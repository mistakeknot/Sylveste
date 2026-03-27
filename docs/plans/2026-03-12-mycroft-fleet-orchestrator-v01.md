---
artifact_type: plan
brainstorm: docs/brainstorms/2026-03-12-mycroft-fleet-orchestrator-brainstorm.md
bead: none
stage: plan
scope: v0.1 — fleet monitor + T0/T1 only
---

# Mycroft Fleet Orchestrator — v0.1 Implementation Plan

**Scope:** Fleet monitor + T0 (observe/shadow) + T1 (suggest/approve). No autonomous dispatch (T2/T3), no auto-recovery, Claude Code runtime only.

**Success metric:** User can see unified fleet state and accept/reject Mycroft's dispatch suggestions from a single session, reducing coordination overhead vs. manual tmux tab-hopping.

**Module:** `apps/Autarch/` — 5th app in the Autarch suite.
**Go module:** `github.com/mistakeknot/autarch`

---

## Prerequisites (must complete before Step 1)

### P1. Extract aggregator to pkg/ (Bigend refactor)

**What:** Move `internal/bigend/aggregator/` → `pkg/aggregator/`
**Why:** Mycroft needs to share Bigend's FleetView composition. Currently internal, not importable.
**Files:**
- `apps/Autarch/internal/bigend/aggregator/*.go` → `apps/Autarch/pkg/aggregator/*.go`
- Update all `internal/bigend/` imports
**Tests:** Existing Bigend tests must still pass after the move.
**Size:** ~1hr. Mechanical move + import updates.

### P2. Add registry-backed agent keywords to intermux

**What:** Intermux's `ParseSessionName()` reads agent keywords from `fleet-registry.yaml` instead of hardcoded list.
**Why:** Culture ship names (grey-area, falling-outside) won't match the hardcoded `["admin-claude", "claude", "codex", "dev"]`.
**Files:**
- `interverse/intermux/internal/tmux/session_name.go` — add `LoadKeywordsFromRegistry(path string)` function
- `interverse/intermux/internal/tmux/session_name_test.go` — test with Culture names
- Fallback: if registry not found, use existing hardcoded list (backward compat)
**Size:** ~1hr. Small change with good test coverage.

### P3. Add `mycroft-check` to Clavain SessionStart hook

**What:** Add mycroft-check section to `os/Clavain/hooks/session-start.sh` that checks for Mycroft assignments via bead state.
**Why:** Agents need to auto-detect and start working on Mycroft-assigned beads.
**Files:**
- `os/Clavain/hooks/session-start.sh` — add mycroft-check after `cass index`, before `/route`
- Shell script: extract fleet name from tmux session, query `bd list --json`, set MYCROFT_BEAD/PHASE/CONTEXT env vars, write session_id + interlock_agent_id to bead state
**Size:** ~1hr. Shell script, follows existing hook patterns.

---

## Implementation Steps

### Step 1. Scaffold Mycroft package structure + SQLite schema

**What:** Create the directory structure, Go types, and SQLite schema.
**Files to create:**
```
apps/Autarch/cmd/mycroft/main.go           # Entry point (cobra CLI)
apps/Autarch/internal/mycroft/
  config.go                                 # Config struct + YAML loader
  db.go                                     # SQLite schema init (decisions.db)
  types.go                                  # FleetView, AgentView, BeadView, shared types
```

**SQLite schema** (from brainstorm — dispatch_log, tier_state, tier_transitions, recovery_log tables).

**Config struct** maps `.autarch/mycroft/config.yaml` with tier, dispatch_preferences, demotion_triggers, agent_overrides.

**cmd/mycroft/main.go:** Cobra root command with subcommands: `mycroft run`, `mycroft status`, `mycroft shadows`, `mycroft pause`, `mycroft resume`, `mycroft override`.

**Tests:**
- Config loading from YAML (round-trip)
- SQLite schema creation (open, migrate, close)
- Type serialization

**Verification:** `go build ./cmd/mycroft/` succeeds. `go test ./internal/mycroft/...` passes.
**Size:** ~2hr.

### Step 2. Fleet registry reader + FleetView builder

**What:** Read fleet-registry.yaml and compose FleetView from existing data sources.
**Files to create:**
```
apps/Autarch/internal/mycroft/fleet/
  registry.go        # Parse fleet-registry.yaml → []AgentSpec
  registry_test.go
```
**Files to modify:**
```
apps/Autarch/internal/mycroft/types.go     # Add AgentSpec, FleetView builder
```

**Logic:**
- `LoadRegistry(path string) ([]AgentSpec, error)` — parse YAML, extract agent names, capabilities, runtime, models
- `AgentSpec` struct: Name, Runtime, Capabilities, CostProfile, Tags
- Freshness map tracking per-source timestamps

**Tests:**
- Parse real fleet-registry.yaml (fixture from `os/Clavain/config/fleet-registry.yaml`)
- Handle missing registry (graceful fallback)
- Handle malformed YAML

**Verification:** Registry loads all 35+ agents with capabilities.
**Size:** ~1.5hr.

### Step 3. Patrol loop — intermux + beads + interlock data sources

**What:** Implement the polling patrol loop that queries intermux, beads, and interlock on intervals.
**Files to create:**
```
apps/Autarch/internal/mycroft/patrol/
  patrol.go           # Main patrol coordinator (30-60s cycle)
  fleet_observer.go   # Query intermux agent_health, classify agent state
  work_scanner.go     # Query bd ready --json, parse available work
  conflict_detector.go # Query interlock check_conflicts
  patrol_test.go
```

**DataSource interface:**
```go
type DataSource interface {
    FleetState() (FleetView, error)
    AgentHealth(name string) (AgentStatus, error)
    BeadQueue() ([]BeadView, error)
}
```

**Two implementations:**
- `PatrolSource` — queries MCP/CLI directly (v0.1 default)
- `AggregatorSource` — reads from pkg/aggregator (Autarch-embedded, stub for v0.1)

**PatrolSource implementation:**
- `FleetState()`: call intermux `list_agents` or `agent_health` MCP tool, merge with fleet-registry.yaml
- `BeadQueue()`: run `bd ready --json`, parse output
- Interlock: call `check_conflicts` MCP tool

**Staleness gating:** Track Freshness per source. If source stale >2x poll interval, defer dispatch decisions but continue health monitoring.

**Heartbeat file:** Write `.autarch/mycroft/heartbeat` with epoch timestamp each cycle.

**Tests:**
- PatrolSource with mock MCP responses
- Staleness gating: stale source defers dispatch
- Heartbeat file written each cycle
- Cycle timing (30s fleet, 60s beads/interlock)

**Verification:** `mycroft run` starts, polls, prints FleetView to stdout.
**Size:** ~3hr.

### Step 4. Failure detection — classify agent state

**What:** Implement failure classification (clean/dirty/degraded/corrupted).
**Files to create:**
```
apps/Autarch/internal/mycroft/patrol/
  detect.go           # State classifier
  detect_test.go
```

**Logic:**
- Input: AgentView (from FleetView) + git status + interlock reservations
- Output: FailureClass enum (Clean, Dirty, Degraded, Corrupted, Healthy)
- Phase-aware stuck thresholds: brainstorm/research = 15min, build/test = 5min
- Corrupted detection: known-bad git patterns with retry for transient errors
- Degraded detection: cross-reference token spend with bead progress (>10min no progress)

**Tests:**
- Each failure class with concrete scenarios
- Phase-aware thresholds
- Corrupted retry logic (transient errors don't escalate)
- Stale claim detection (>45min, aligned with beadClaimStaleSeconds)

**Verification:** Unit tests cover all failure matrix cells.
**Size:** ~2hr.

### Step 5. Selector — priority-first bead ranking

**What:** Rank available beads for dispatch using priority-first with tiebreakers.
**Files to create:**
```
apps/Autarch/internal/mycroft/scheduler/
  selector.go         # Priority-first ranking
  selector_test.go
  conflict.go         # Pre-dispatch interlock conflict check
  conflict_test.go
```

**Ranking criteria (ordered):**
1. Bead priority (P0 > P1 > P2 > P3 > P4)
2. Dependency-readiness (all blockers resolved — unresolved excluded)
3. Age (oldest first within same priority)
4. Complexity match (simple beads to available agents first)

**Complexity source:** `label:complexity/simple` etc. from beads labels. Missing = unknown = escalate.

**Pre-dispatch conflict check:** Query interlock for file scope overlap before selecting.

**Tests:**
- Priority ordering
- Dependency filtering
- Age tiebreaking
- Complexity matching
- Conflict pre-check rejection

**Verification:** Given a mock BeadQueue, produces correct ranked order.
**Size:** ~2hr.

### Step 6. Tier FSM — T0/T1 state machine + dispatch_log

**What:** Implement the T0-T3 tier state machine with T0 (shadow) and T1 (suggest) behavior.
**Files to create:**
```
apps/Autarch/internal/mycroft/tier/
  tier.go             # T0-T3 FSM (v0.1: only T0/T1 active)
  tier_test.go
  evidence.go         # Track suggestion acceptance/rejection
  evidence_test.go
  transitions.go      # tier_transitions table writes
  transitions_test.go
  graduation.go       # Promotion/demotion logic (20 sample minimum)
  graduation_test.go
```

**T0 behavior:**
- Run selector each patrol cycle
- Write shadow suggestion to dispatch_log (action='shadow_suggest')
- No action taken

**T1 behavior:**
- Run selector each patrol cycle
- Present numbered suggestions (in stdout / TUI panel)
- Wait for user input: `approve N`, `reject N — reason`, `approve all`
- On approve: execute dispatch (claim bead, write state, spawn agent)
- On reject: log to dispatch_log with reason

**Graduation:**
- Manual promotion only (v0.1)
- Demotion triggers: symmetric circuit breaker (15% T2→T1, 25% T3→T2), corrupted = instant, budget = T0
- Minimum sample size: 20 dispatches before evaluating
- tier_transitions table captures every change with evidence JSON snapshot

**Tests:**
- FSM state transitions
- Shadow suggestion logging
- Approval/rejection flow
- Demotion trigger calculation with rolling window
- 20-sample guard
- tier_transitions recording

**Verification:** At T0, suggestions appear in log. At T1, approve/reject works.
**Size:** ~3hr.

### Step 7. Dispatch execution — claim + spawn + handoff

**What:** Implement the push-first dispatch flow (claim bead → write state → spawn tmux session).
**Files to create:**
```
apps/Autarch/internal/mycroft/scheduler/
  dispatch.go         # Dispatch execution
  dispatch_test.go
apps/Autarch/internal/mycroft/spawn/
  spawner.go          # tmux session creation (ClaudeCodeSpawner)
  spawner_test.go
apps/Autarch/internal/mycroft/briefing/
  briefing.go         # Assemble context document from bead + history
  briefing_test.go
```

**Dispatch flow:**
1. Claim bead: `bd update <bead> --claim` with BD_ACTOR=mycroft
2. Write dispatch metadata: claimed_by, assigned_agent, assigned_phase, context_file, assigned_at, assigned_by
3. Context file path validation: resolve to absolute, reject `..`, reject symlinks outside project root
4. Compare-and-swap guard: check assigned_at before writing
5. Spawn tmux session: `tmux new-session -d -s iterm-Sylveste-{agent}-01`
6. Log to dispatch_log

**Two-phase claim TTL:**
- Phase 1: 90s until first heartbeat
- Phase 2: 45min (aligned with beadClaimStaleSeconds)

**AgentSpawner interface:**
```go
type AgentSpawner interface {
    Spawn(agent AgentSpec, bead BeadView, context string) (SessionID, error)
    Kill(sessionID string) error
}
```
v0.1: `ClaudeCodeSpawner` (tmux only).

**Briefing:**
- Assemble context from bead description, notes, design, dependencies
- Write to `.autarch/mycroft/briefings/{bead_id}.md`

**Tests:**
- Dispatch flow (mock bd, mock tmux)
- Path validation (traversal rejection)
- Compare-and-swap guard
- Two-phase TTL logic
- Briefing generation

**Verification:** `mycroft run` at T1 → approve → bead claimed → tmux session spawned.
**Size:** ~3hr.

### Step 8. Escalation + operational controls

**What:** Implement notification dispatch and pause/resume/override commands.
**Files to create:**
```
apps/Autarch/internal/mycroft/escalate/
  escalate.go         # Notification dispatch (notify-send, terminal bell)
  escalate_test.go
  decision.go         # Pending decision queue
  decision_test.go
```

**Escalation channels:**
- Desktop notification: `notify-send` (Linux) / `osascript` (macOS)
- Terminal bell: `\a`
- Severity-aware badge: `⚠ 3 pending` (P0/P1), `● 5 pending` (P2+), `✓ idle`

**Operational commands (already scaffolded in Step 1):**
- `mycroft pause` — set paused flag, stop new dispatches
- `mycroft pause --drain` — paused + send graceful-stop signal to in-flight agents
- `mycroft resume` — clear paused flag
- `mycroft override <bead> <agent>` — manual assignment bypassing selector
- `mycroft shadows` — show shadow suggestion digest with would-approve/reject/skip feedback

**Override pattern analysis:** `mycroft overrides` summarizes rejection patterns from dispatch_log.reason.

**Tests:**
- Pause/resume state transitions
- Drain mode signal propagation
- Override logging
- Shadow digest generation

**Verification:** `mycroft pause` stops dispatching. `mycroft resume` restarts. `mycroft shadows` shows digest.
**Size:** ~2hr.

### Step 9. Integration testing — end-to-end patrol cycle

**What:** Integration tests that exercise the full patrol → detect → select → suggest/approve → dispatch cycle.
**Files to create:**
```
apps/Autarch/internal/mycroft/
  integration_test.go  # E2E tests with test fixtures
```

**Test scenarios:**
1. **T0 full cycle:** Start at T0 → patrol queries sources → selector ranks beads → shadow suggestion written to dispatch_log → no action taken
2. **T1 approve:** Start at T1 → patrol → selector → suggestion presented → user approves → bead claimed → tmux session spawned → dispatch_log records success
3. **T1 reject:** Suggestion → user rejects with reason → dispatch_log records rejection with reason → bead not claimed
4. **Failure detection:** Agent with dirty git state → classified as dirty → reported at T0/suggested at T1
5. **Staleness gating:** One data source stale → dispatch deferred → health monitoring continues
6. **Heartbeat:** Patrol writes heartbeat file each cycle

**Verification:** All integration tests pass. `go test ./internal/mycroft/... -count=1` clean.
**Size:** ~2hr.

### Step 10. Fleet registry entry + documentation

**What:** Register Mycroft in fleet-registry.yaml and update AGENTS.md.
**Files to modify:**
- `os/Clavain/config/fleet-registry.yaml` — add mycroft agent entry
- `apps/Autarch/CLAUDE.md` — document Mycroft as 5th app
- `apps/Autarch/AGENTS.md` — add Mycroft development guide

**Fleet registry entry:**
```yaml
mycroft:
  source: autarch
  category: orchestration
  description: "Fleet coordination agent — observes, ranks, dispatches"
  capabilities: [multi_agent_coordination, fleet_monitoring, dispatch]
  roles: [coordinator]
  runtime:
    mode: cli
    binary: mycroft
  models:
    preferred: sonnet
    supported: [sonnet, opus]
  tools: [intermux, interlock, beads, tmux]
  tags: [orchestration]
```

**Size:** ~30min.

---

## Deferred to v0.2

- T2/T3 autonomous dispatch + auto-recovery
- Recovery actions (patch + discard, WAL-first ordering)
- Multi-runtime support (Codex, Skaffen spawners)
- Autarch TUI tab (`/myc`) — v0.1 is CLI-only
- Internal goroutine watchdog (Layer 2)
- AggregatorSource implementation (dual polling mode)
- Dispatch log retention policy
- User-defined priority boosts in selector

---

## Dependency Graph

```
P1 (aggregator extraction) ──┐
P2 (intermux keywords)  ─────┤
P3 (mycroft-check hook) ─────┤
                              ↓
Step 1 (scaffold) ────────────┐
                              ↓
Step 2 (registry reader) ─────┤
                              ↓
Step 3 (patrol loop) ─────────┤
                              ↓
Step 4 (failure detection) ───┤ ← can parallel with Step 5
Step 5 (selector) ────────────┤ ← can parallel with Step 4
                              ↓
Step 6 (tier FSM) ────────────┤
                              ↓
Step 7 (dispatch execution) ──┤
                              ↓
Step 8 (escalation/controls) ─┤ ← can parallel with Step 9
Step 9 (integration tests) ───┤ ← can parallel with Step 8
                              ↓
Step 10 (registry + docs) ────┘
```

**Parallelizable pairs:** Steps 4+5, Steps 8+9.

---

## Risk Register

| Risk | Mitigation | Impact if ignored |
|------|-----------|------------------|
| Aggregator extraction breaks Bigend | Run full Bigend test suite after P1 | Bigend (primary dashboard) regresses |
| Intermux keyword change breaks existing session parsing | Fallback to hardcoded list if registry not found | Existing agent detection fails |
| MCP tool calls slow down patrol cycle | Timeout per source (5s), continue with stale data | Patrol loop blocks on unresponsive service |
| bd CLI not available in all environments | Check `command -v bd` before querying, degrade gracefully | Crash on missing dependency |
| tmux session spawn race with SessionStart hooks | Two-phase TTL handles spawn failures | Orphaned bead claims |
