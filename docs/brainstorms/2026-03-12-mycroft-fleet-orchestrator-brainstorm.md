---
artifact_type: brainstorm
bead: none
stage: discover
---

# Mycroft — Fleet Orchestrator for Demarch

**Date:** 2026-03-12
**Status:** Brainstorming
**Inspiration:** Gas Town (steveyegge/gastown), Goosetown (block/goosetown), Terra Ignota (Ada Palmer)

## What We're Building

**Mycroft** is a fleet coordination agent that serves as a single point of contact between the user and multiple Clavain-rigged AI agent sessions. It observes fleet state, dispatches work, detects failures, and graduates from passive dashboard to autonomous coordinator as it earns trust through proven performance.

Named after **Mycroft Canner** (Ada Palmer's Terra Ignota) — the servicer who coordinates across all seven Hives from a position of earned trust. Also echoes **Mycroft Holmes** — observes and coordinates without doing the fieldwork himself.

### The Problem Today

The user hops between 3-10 tmux tabs to:
- Check what each agent is doing (intermux gives data but no unified view)
- Discover and assign work (manually runs `bd ready`, claims, dispatches)
- Detect failures (stuck agents, stale claims, silent errors)
- Make routing decisions (which agent gets which bead)

This doesn't scale. At 5+ agents, the user becomes the bottleneck.

### What Mycroft Adds

One agent session that:
1. **Observes** fleet state (via intermux, interlock, beads)
2. **Ranks** available work (via beads priority, complexity, dependencies)
3. **Dispatches** work to agents (claims beads, spawns/assigns Clavain sessions)
4. **Detects** anomalies (stuck, idle, failed, conflicting agents)
5. **Recovers** from failures (restart, reassign, escalate)
6. **Reports** to the user (status, decisions, escalations)

## Why This Approach

### Dashboard-first with graduated autonomy

Not fully autonomous (Gas Town's Mayor) — the user retains judgment over work prioritization and irreversible actions. Not fully manual (current tmux tab-hopping) — Mycroft handles routine coordination autonomously once it earns trust.

**Autonomy tiers (earned, not granted):**

| Tier | Name | Authority | Graduation Criteria |
|------|------|-----------|-------------------|
| **T0** | Observe | Aggregate fleet status, emit shadow suggestions, report to user. No actions taken. | Default start state |
| **T1** | Suggest | Propose work assignments + recovery actions. User approves each. | Manual promotion by user |
| **T2** | Auto-dispatch (low-risk) | Auto-assign work matching `tier2_dispatch_allowlist` only. Auto-retry recoverable failures. Escalate everything else. | N accepted suggestions with >90% approval rate AND >70% bead completion rate |
| **T3** | Full dispatch | All work assignment autonomous. Budget-gated (stop at spend limit). User reviews summaries, not decisions. | M successful auto-dispatches with >90% approval AND >70% completion, no regression |

Graduation thresholds (N, M) are configurable. User can demote at any time.

**Promotion privilege separation:** `promotion_requires: manual` by default — all promotions require explicit user action. Auto-promotion (opt-in via config) adds an **Interspect gate**: `tier/evidence.go` queries Interspect's evidence table, and graduation is blocked if Interspect classifies Mycroft's dispatch patterns as `growing` or `emerging` (insufficient evidence). Only `ready` classification allows auto-promotion. This prevents Mycroft from self-promoting in a feedback loop.

**T2 dispatch allowlist** (machine-enforceable gate):
```yaml
tier2_dispatch_allowlist:
  - type: task
    max_priority: 3        # P3 and P4 only
    max_complexity: medium
  - type: bug
    max_priority: 3
    max_complexity: simple
  - type: docs
    max_priority: 2        # any docs up to P2
    max_complexity: any
```
If a bead's `(type, priority, complexity)` tuple doesn't match any allowlist entry, T2 escalates to user. This is enforceable without human judgment — no "low-risk" ambiguity.

**Complexity via labels:** Complexity is expressed using beads labels (`label:complexity/simple`, `label:complexity/medium`, `label:complexity/complex`) rather than a new schema field. Labels are already supported by beads and don't require schema migration. Missing complexity label = unknown = escalate to user (safe default).

**Automatic demotion triggers (symmetric rolling-window circuit breaker):**
- **T3→T2:** >25% failure rate in rolling 24h window
- **T2→T1:** >15% failure rate in rolling 24h window OR any corrupted failure (always escalate-worthy). Symmetric with T3→T2 — the system is at least as rigorous about revoking authority as granting it.
- **Any→T0:** Budget overshoot (>120% of daily limit)
- **Immediate one-tier demotion:** 3 consecutive failures on different beads
- Demotion is instant; re-promotion requires meeting the original graduation criteria again from scratch

**Circuit breaker reconciliation sweep:** The failure rate is computed from `dispatch_log`, but silent failures (agent crashes without Mycroft detecting) would undercount. The patrol loop cross-references `dispatch_log` against intermux presence: any bead that was dispatched but whose agent session disappeared from intermux without a corresponding 'completed' entry is counted as an undetected failure. This ensures the circuit breaker reflects ground truth, not just Mycroft's own records.

**T0 shadow suggestions:** At T0, Mycroft runs the full `select/` pipeline each patrol cycle but writes results as shadow entries in `dispatch_log` (`action='shadow_suggest'`) rather than acting on them. The TUI shows "what Mycroft would have suggested" — bead priority, agent capability match, load reasoning — so the user can evaluate Mycroft's judgment before granting any authority.

**Shadow feedback (hybrid model):** End-of-session digest (`mycroft shadows`) as the default low-friction path — presents shadow suggestions alongside what the user actually did, with `would-approve` / `would-reject` / `skip` ratings. In Autarch TUI mode, a real-time shadow overlay shows suggestions as they arise for immediate thumbs-up/down. Both channels feed into T0→T1 graduation evidence: the user can compare Mycroft's shadow suggestions against their own dispatch decisions.

**T1 inline approval:** At T1, Mycroft presents dispatch suggestions as numbered choices in its session (or TUI panel). User types `approve 1`, `reject 2 — too risky`, or `approve all`. Approved suggestions dispatch immediately. Rejected suggestions are logged with reason to `dispatch_log` (feeds into override pattern analysis). Batch approval supported.

**Graduation minimum sample size:** Tier promotion thresholds (e.g., >90% approval rate) are only evaluated after at least 20 completed dispatches. Below 20, the tier is locked regardless of success rate. This prevents small-sample artifacts (4/5 = 80% at N=5).

**Dual-source graduation verification:** Interspect cross-references `dispatch_log` entries against beads state (was the bead actually closed successfully?) and git history (was a commit produced?). Promotion requires agreement between dispatch_log AND at least one independent signal from systems Mycroft doesn't control. This prevents self-grading — Mycroft cannot inflate its own approval rate.

### 5th Autarch app (not a new pillar)

Mycroft lives in `apps/Autarch/` alongside Bigend, Coldwine, Gurgeh, and Pollard. It shares the `pkg/` layer:
- **pkg/intermute** for real-time events
- **pkg/intercore** for kernel state
- **pkg/tui** for terminal rendering primitives
- **pkg/signals** for cross-component signaling
- **pkg/events** for event bus
- **pkg/db** for SQLite helpers
- **Unified TUI** — new 5th tab (`/myc`)

**Shared logic extraction (v0.1 prerequisite):** Bigend's aggregator pattern and Coldwine's dispatch interfaces currently live in `internal/` (not importable by Mycroft). Before Mycroft implementation, extract:
- `internal/bigend/aggregator/` → `pkg/aggregator/` — multi-source data composition pattern
- `internal/coldwine/agent/detect.go` → `pkg/dispatch/` — bead-to-agent matching interface

This makes the "5th Autarch app" claim architecturally true, not just organizational. The extraction is scoped to interfaces and patterns, not full implementations — Mycroft implements its own fleet-level logic using the shared contracts.

**Dual polling mode:** When running as a tab in Autarch's unified TUI, Mycroft reads from `pkg/aggregator/` (sharing Bigend's already-composed fleet state) rather than polling intermux/interlock independently. This avoids duplicate queries and ensures Mycroft sees the same data Bigend displays. When running standalone (e.g., as a dedicated Claude Code session without Autarch), Mycroft polls independently via its own patrol loop. The `FleetView` builder accepts a `DataSource` interface — either `AggregatorSource` (reads from shared in-process state) or `PatrolSource` (queries MCP/CLI directly).

This avoids rebuilding infrastructure that exists and is tested (358 tests across Autarch).

### Runtime-agnostic agent dispatch

Mycroft coordinates agents running in the **Clavain rig** — currently Claude Code, with Codex and Gemini planned. Future: Skaffen instances via headless/RPC mode.

```
Fleet Agent Interface:

  Agent
    ID()       string
    Runtime()  string  // "claude-code" | "codex" | "skaffen"
    Status()   AgentStatus  // active | idle | stuck | failed
    Dispatch(task) error
    Health()   HealthReport
```

**v0.1 scope: fleet monitor + T0/T1 only.** Mycroft observes fleet state, emits shadow suggestions (T0), and proposes user-approved assignments (T1). No autonomous dispatch, no auto-recovery. This validates the core observation value before automating. Success metric: bead throughput per developer-hour of coordination overhead (measurable via beads timestamps and session activity).

**v0.2:** T2/T3 autonomous dispatch, auto-recovery, multi-runtime support. Architecture abstractions (AgentSpawner interface, select/spawn split) are designed in v0.1 but only implemented when v0.1 usage patterns confirm they're needed.

**Runtime phases:**
- **Phase 1 (v0.1):** Claude Code agents in Clavain rig (tmux sessions, skill injection, intermux monitoring)
- **Phase 2 (v0.2):** Codex/Gemini agents in Clavain rig (same interface, different spawn mechanism)
- **Phase 3 (v0.3):** Skaffen agents (native Go dispatch, evidence pipeline, RPC)

## Key Decisions

### 1. Mycroft is a coordinator, not an executor

Mycroft does not write code, run tests, or modify files. It reads fleet state, makes dispatch decisions, and manages agent lifecycle. This is the Mycroft Holmes pattern: "occasionally he *is* the British government" — but he never leaves his armchair.

Tools Mycroft uses: intermux MCP (read fleet), interlock MCP (read reservations), beads CLI (read/write work state + dispatch metadata via `bd set-state`), tmux (spawn/kill sessions), SQLite (decisions.db). Tools Mycroft does NOT use: write, edit, bash (code execution), grep, glob.

**Bead state safety:** All beads CLI calls use `BD_ACTOR=mycroft` for audit trail. Before any unclaim/reassign action, Mycroft performs a **fresh liveness recheck** (live intermux query, not stale patrol data) to confirm the agent is actually gone. Write operations use a **compare-and-swap guard**: check `assigned_at` matches the expected value before writing, preventing interleaved writes from concurrent Mycroft restarts or race conditions with agents that self-unclaim.

### 2. Patrol loop, not event-driven (Phase 1)

Mycroft polls fleet state on intervals rather than consuming events. Simpler to build, debug, and reason about. Intermux already polls tmux on 10s intervals — Mycroft reads intermux's output rather than duplicating tmux access.

Polling intervals:
- Fleet health: every 30s (via intermux)
- Beads backlog: every 60s (via `bd ready --json`)
- Interlock conflicts: every 60s (via interlock MCP)

Phase 2+: migrate to event-driven via intercore event consumption (Skaffen v0.3 adds native Go intercore client).

### 3. Agent identity via registry-backed detection + Culture ship names

Agents are named after **Culture ships** (Iain M. Banks) — e.g., `grey-area`, `falling-outside`, `mistake-not`. These names go directly in tmux session names (`iterm-Demarch-grey-area-01`) and are the canonical identifiers throughout the system.

**Identity hierarchy (canonical → ephemeral):**
1. **Culture ship name** (durable) — `grey-area`, `falling-outside`, `mistake-not`. Canonical identifier across all systems. Used in `dispatch_log.agent`, `bd set-state claimed_by`, fleet-registry.yaml.
2. **Interlock agent ID** (per-session) — Written by `mycroft-check` hook at SessionStart: `bd set-state <bead> interlock_agent_id=$INTERLOCK_ID`. Maps the durable ship name to the session-specific interlock identity for file reservation correlation.
3. **CLAUDE_SESSION_ID** (ephemeral) — Session-scoped UUID. Linked at SessionStart for crash correlation but never used as a primary key.

**Identity lifecycle:**
1. **Claim time:** Mycroft writes `bd set-state <bead> claimed_by=grey-area` immediately after `bd update <bead> --claim` using `BD_ACTOR=mycroft` for audit trail
2. **Spawn time:** Mycroft creates tmux session with Culture name embedded in the session name (underscore delimiter in tmux: `grey_area`)
3. **SessionStart hook:** `mycroft-check` writes `bd set-state <bead> session_id=$CLAUDE_SESSION_ID` AND `bd set-state <bead> interlock_agent_id=$INTERLOCK_ID` — linking fleet name to session and interlock identities

This eliminates the `claimed_by=unknown` window that exists in the current Clavain claim system.

**Registry-backed detection:** Intermux reads `fleet-registry.yaml` for agent name keywords instead of maintaining a hardcoded list. When intermux sees a tmux session named `iterm-Demarch-grey-area-01`, it matches `grey-area` from the registry.

The fleet registry is a YAML file (existing `fleet-registry.yaml`, extended):
```yaml
agents:
  - name: grey-area
    runtime: claude-code
    capabilities: [go, rust, tests, docs]
  - name: falling-outside
    runtime: claude-code
    capabilities: [python, docs, research]
  - name: mistake-not
    runtime: claude-code
    capabilities: [go, python, refactor]
```

**Fix required:** `bd update --claim` should accept `--claimed-by=<name>` to set the fleet name at claim time (currently writes `claimed_by=unknown`). Until that's implemented, `bd set-state` immediately after `--claim` serves as the workaround.

### 4. User interaction via TUI tab + escalation

Primary: Mycroft tab in Autarch unified TUI — shows fleet status, work queue, pending decisions, recent actions.

Escalation: When Mycroft needs a decision (T0/T1) or encounters an anomaly it can't handle (T2/T3), it sends a notification. Options:
- TUI highlight (tab badge with **severity-aware indicator**: `⚠ 3 pending` when P0/P1 items present, `● 5 pending` for P2+ only, `✓ idle` when nothing pending. Color follows severity: red for P0/P1, yellow for P2, default for P3+)
- Desktop notification (via `notify-send` or macOS `osascript`)
- Terminal bell (fallback)

### 5. Budget gating

Mycroft tracks estimated cost per dispatch (via interstat/fleet registry baselines). At T2/T3, Mycroft stops dispatching when daily spend estimate exceeds a configurable limit. User can override.

### 6. Operational controls (pause/resume/override)

Three commands for runtime control without tier demotion:

- **`myc pause`** — Stops new dispatches. In-flight agents finish their current bead normally, then idle. Logged to `dispatch_log` (`action='pause'`). Essential for responding to upstream breaking changes at T2+.
- **`myc pause --drain`** — Stops new dispatches AND sends a graceful-stop signal to in-flight agents: checkpoint and stop at next safe point. State transitions: `running → paused (no new) → drained (all idle) → running`.
- **`myc resume`** — Re-enables dispatching from current tier. Logged to `dispatch_log` (`action='resume'`).
- **`myc override <bead> <agent>`** — Manually assigns a specific bead to a specific agent, bypassing Mycroft's `select/` pipeline. Logged as `action='manual_override'`. Useful when the user knows the right assignment but doesn't want to leave Mycroft's TUI.

Pause/resume is distinct from tier demotion: pause is temporary (the tier is preserved), demotion is persistent (re-promotion requires meeting graduation criteria). A paused Mycroft at T2 resumes at T2; a demoted Mycroft at T2→T1 must re-earn T2.

### 7. Watchdog (who watches the watcher)

Three-layer monitoring, each covering what the others miss:

**Layer 1 — Heartbeat file + external checker (both runtime modes):** Mycroft writes `.autarch/mycroft/heartbeat` every patrol cycle with epoch timestamp. External shell loop (or cron, every 2min) checks file age. If stale >3min (3x patrol interval), fires `notify-send "Mycroft is down"`. Borrows Gas Town's battle-tested patterns: grace-period logic (distinguish pre-start stale from post-start stale), crash-loop exponential backoff guard (prevent kill-restart loops). The three-tier chain — OS supervisor → shell watchdog → Mycroft patrol loop — mirrors Gas Town's proven `launchd → daemon.go → Deacon` architecture.

**Layer 2 — Internal goroutine watchdog (Autarch-embedded only):** When running as a Go binary inside Autarch, a supervisor goroutine monitors patrol loop health. The pet is **conditional on actual health**: `FleetView` freshness, successful data source queries, and patrol cycle completion must all pass before the watchdog is petted. This catches goroutine-level stalls that heartbeat-only monitoring would miss (process alive but patrol loop stuck on a blocking call).

**Layer 3 — Fleet-aware fallback (already exists):** The `mycroft-check` SessionStart hook checks for Mycroft assignments. If `$MYCROFT_BEAD` is not set (Mycroft down or never assigned), agents fall back to the existing `/route` flow. No new code needed — the fallback path provides graceful degradation.

No auto-restart at v0.1 — alert only. User decides when to relaunch.

## Architecture

```
apps/Autarch/
  cmd/mycroft/main.go           # Entry point
  internal/mycroft/
    patrol/                     # Health checks, failure detection, fleet view
      patrol.go                 # Main patrol coordinator
      detect.go                 # Failure state classifier (clean/dirty/degraded/corrupted)
      fleet_observer.go         # Read intermux, classify agent state
      work_scanner.go           # Read beads, rank available work
      conflict_detector.go      # Read interlock, detect file conflicts
    scheduler/                  # Dispatch queue, selector ranking, timing
      scheduler.go              # Patrol → Decide → Act cycle
      selector.go               # Priority-first ranking with tiebreakers
      dispatch.go               # Dispatch interface + dispatch execution
      conflict.go               # Pre-dispatch interlock conflict check
    fleet/                      # Agent registry + lifecycle
      registry.go               # Fleet YAML + runtime matching
      agent.go                  # Agent interface + implementations
      health.go                 # Health scoring + anomaly detection
    spawn/                      # OS side effects (tmux, hooks)
      spawner.go                # Create new tmux/Skaffen sessions
    briefing/                   # Build task context for agent (avoids stdlib context/ collision)
      briefing.go               # Assemble context document from bead + history
    tier/                       # Autonomy graduation
      tier.go                   # T0-T3 FSM
      evidence.go               # Track suggestion acceptance/rejection + dual-source verification
      graduation.go             # Promotion/demotion logic
      transitions.go            # tier_transitions table: promotion/demotion receipts
    escalate/                   # User notification channel
      escalate.go               # Notification dispatch
      decision.go               # Pending decision queue
```

**DataSource interface sketch:**
```go
type DataSource interface {
    FleetState() FleetView
    AgentHealth(name string) AgentStatus
    BeadQueue() []Bead
}
// AggregatorSource: reads from Bigend's in-process state (Autarch-embedded)
// PatrolSource: queries MCP/CLI directly (standalone Claude Code)
```

## Borrowings from Gas Town / Goosetown

| Concept | Gas Town / Goosetown | Mycroft Adaptation |
|---------|---------------------|-------------------|
| GUPP (work preloading) | Agent finds work on hook, executes immediately | Mycroft pre-assigns beads + writes dispatch metadata to bead state before spawning agent |
| gtwall (agent broadcast) | Flat-file append-only log for inter-agent status | Not needed Phase 1 — Mycroft IS the coordinator. Phase 2: add via intermute |
| Patrol cycles (Deacon) | Daemon polls for stuck/idle/failed agents | Mycroft patrol loop (30-60s intervals) |
| Researcher flock | 3-6 parallel read-only specialists | Mycroft can dispatch parallel research agents for deep-dive tasks |
| Knowledge frontmatter | Mandatory YAML metadata on all docs | Adopt for docs/guides/ (separate initiative, not Mycroft-specific) |
| Stamps / reputation | Peer-attested multi-dimensional trust | Interspect evidence + tier system serves same purpose |
| Wanted board | Shared work marketplace | Beads backlog IS the wanted board (single-org, no federation) |
| Molecules | Durable multi-step workflows | Not needed — Clavain sprint phases + beads serve this role |

## Resolved: Route/Sprint Handoff Protocol

### Push-first, pull-fallback

Mycroft inverts the current pull-based model. Instead of agents discovering their own work via `/route`, Mycroft **pushes assignments** to agents before spawning them.

**Push flow (Mycroft-initiated):**

1. Mycroft selects bead `iv-abc` for agent `grey-area` using **priority-first ranking with tiebreakers**: (1) bead priority (P0 > P1 > P2 > P3 > P4), (2) dependency-readiness (all blockers resolved — beads with unresolved dependencies excluded entirely), (3) age (oldest first within same priority), (4) complexity match (simple beads dispatched to available agents first). User can override via `myc override`.
2. Mycroft checks interlock for file conflicts: if bead's expected file scope overlaps active reservations, skip and pick next-best bead
3. Mycroft claims bead: `bd update iv-abc --claim --claimed-by=grey-area`
4. Mycroft writes dispatch metadata to bead state (all calls use `BD_ACTOR=mycroft`):
   ```bash
   bd set-state iv-abc claimed_by grey-area
   bd set-state iv-abc assigned_agent grey-area
   bd set-state iv-abc assigned_phase build
   bd set-state iv-abc context_file /path/to/context.md
   bd set-state iv-abc assigned_at 2026-03-12T14:30:00Z
   bd set-state iv-abc assigned_by mycroft
   ```
   **Context file path validation:** Context file paths are resolved to absolute and verified to start with the project root. Paths containing `..` after normalization are rejected. Symlinks resolving outside the project root are rejected. This prevents path traversal via corrupted bead state.
5. Mycroft spawns: `tmux new-session -s iterm-Demarch-grey-area-01` with Clavain rig
6. Agent's SessionStart hook chain reads bead state and auto-starts work

**No assignment files.** All dispatch metadata lives in bead state (`bd set-state`), which is durable, queryable, and shared across sessions without filesystem coupling.

**Two-phase claim-expiry TTL:**
- **Phase 1 (dispatch→first heartbeat):** 90 seconds. If the agent doesn't emit its first heartbeat within 90s, it probably failed to start — fast-fail agents are reclaimed quickly.
- **Phase 2 (running):** 45 minutes (aligned with Clavain's `beadClaimStaleSeconds = 2700`). Slow-start agents that successfully boot get the full window.
The patrol loop reads heartbeat age to distinguish phases. Prevents both orphaned claims from failed spawns and premature unclaims on legitimate slow-start agents.

**Pull fallback (user-initiated):**

1. User opens new tmux tab manually
2. No bead state has `assigned_agent` matching this session's fleet name
3. Agent runs `/route` as today (discovery + user picks)
4. Mycroft observes the new session via intermux
5. Mycroft adds it to fleet view as "user-managed"

### Clavain SessionStart hook integration

New `mycroft-check` hook fires BEFORE `/route` in the SessionStart chain:

```
SessionStart hook chain (ordered):
  1. bd prime              # existing: recover beads context
  2. cass index            # existing: index if stale
  3. mycroft-check         # NEW: check for assignment via bead state
     - extract fleet name from tmux session (position 3 of {terminal}-{project}-{agent}-{number})
     - query: bd list --json | find bead where assigned_agent=$FLEET_NAME
     - if found:
         bd set-state $BEAD session_id=$CLAUDE_SESSION_ID
         bd set-state $BEAD interlock_agent_id=$INTERLOCK_ID  # link ship name → interlock identity
         export MYCROFT_BEAD=$BEAD
         export MYCROFT_PHASE=$(bd get-state $BEAD assigned_phase)
         export MYCROFT_CONTEXT=$(bd get-state $BEAD context_file)
  4. existing hooks...     # continue as normal
```

Modified `/route` behavior:
- If `$MYCROFT_BEAD` is set: skip discovery, load context, dispatch to `/work` or `/sprint` directly
- If `$MYCROFT_BEAD` is NOT set: existing `/route` flow (discovery scan + AskUserQuestion)

This preserves backward compatibility: without Mycroft, nothing changes. With Mycroft, agents start working immediately.

### Agent name resolution

The fleet name is extracted from the tmux session name. Mycroft uses the same encoding as intermux: `{terminal}-{project}-{agent}-{number}`. The agent name is extracted from position 3 (e.g., `grey-area` from `iterm-Demarch-grey-area-01`).

## Open Questions

1. **Fleet registry format** — RESOLVED. See "Resolved: Fleet Registry" section below.

2. **Multi-project coordination** — RESOLVED. Start single-project (Demarch), design interfaces for multi-project. Must support physical monorepos (Demarch has subprojects in os/, apps/, interverse/, core/). Multi-project adds a `projects` list to config.yaml with per-project `beads_prefix` and `priority_weight`. The FleetView and patrol loop take `project` as a parameter, not a global assumption.

3. **Skaffen integration timeline** — RESOLVED. Design the `AgentSpawner` interface in v0.1 to support multiple runtimes (claude-code, skaffen). v0.1 implements `ClaudeCodeSpawner` only (tmux + bead state dispatch + intermux monitoring). v0.2 adds `SkaffenSpawner` (headless mode + evidence pipeline + native Go health) when Skaffen is daily driver. No wasted work — the abstraction is ready from day one.

4. **Failure recovery scope** — RESOLVED. See "Resolved: Failure Recovery" section below.

5. **Max OAuth implications** — With Claude Max, persistent sessions are effectively free. Mycroft can run as a persistent Claude Code session or Skaffen instance without cost concerns. This favors the patrol-loop model (always-on, polling) over event-driven (complex, premature). Polling intervals (30-60s) are cheap when the session is free.

## Resolved: Failure Recovery

### Failure classification (state-based)

Mycroft classifies agent failures by inspecting the state they left behind:

**Clean failure** — Agent has no uncommitted changes, no interlock reservations.
- Examples: stuck spinner, idle timeout, session crash before writing anything, completed work already committed
- Detection: `git status` clean + no active interlock reservations
- Safe to auto-recover at T2+

**Dirty failure** — Agent has uncommitted changes or holds file reservations.
- Examples: agent crashed mid-edit, session killed while writing, partial bead work
- Detection: `git status` dirty OR active interlock reservations
- Safe to auto-recover at T2+ (patch + discard scoped files + release locks + reassign)

**Degraded failure** — Agent is running but not making meaningful progress.
- Examples: infinite retry loop (tool called repeatedly with transient errors), token burn without commits or phase transitions, agent stuck in a reasoning loop
- Detection: high token spend (via interstat) without corresponding progress signals (no commits, no phase transitions, no bead state changes) for >10 minutes
- Note: intermux classifies these as `StatusActive` because pane output changes constantly — Mycroft must cross-reference token spend with bead progress independently
- Safe to auto-recover at T2+ (kill session, unclaim, re-dispatch with failure context)

**Corrupted failure** — Git in bad state or multi-agent conflict.
- Examples: merge conflict, detached HEAD, multiple agents wrote same files, bead in inconsistent state
- Detection: `git status` returns error on **known-bad patterns** (merge markers, dangling HEAD, locked index) OR interlock shows conflicting reservations. Mundane `git status` errors (e.g., permission denied, disk full) trigger a single retry after 2s before classifying — transient filesystem issues should not escalate.
- ALWAYS escalate to user, regardless of tier

### Recovery matrix (T2 dirty escalates, T3 auto-discards)

```
             | T0 Observe | T1 Suggest | T2 Auto-low | T3 Full
-------------|------------|------------|-------------|--------
Clean fail   | Report     | Suggest    | Auto-restart| Auto
             |            | restart    | + re-assign | restart
Dirty fail   | Report     | Suggest    | ESCALATE    | Patch +
             |            | options    | (user decides)| reassign
Degraded     | Report     | Suggest    | Kill +      | Kill +
             |            | kill       | re-dispatch | re-dispatch
Corrupted    | Report     | Report     | Report +    | Report +
             |            |            | ESCALATE    | ESCALATE
```

**T2 dirty escalation rationale:** At T2, irreversible discard of uncommitted changes requires user confirmation. Only T3 (full trust) auto-discards. This ensures the system doesn't destroy work at a trust level where the user hasn't fully validated Mycroft's judgment.

### Recovery actions

- **Report:** Log to Mycroft activity feed. No action taken.
- **Suggest restart:** Present "Agent X stuck on bead Y. Restart?" via escalation channel.
- **Auto-restart:** Kill tmux session, unclaim bead (`bd update <id> --unclaim`), clear bead dispatch state (`bd set-state <id> assigned_agent ""`), re-dispatch to same or different agent.
- **Patch + discard (scoped via interlock, WAL-first ordering):** Recovery follows strict WAL-first ordering to prevent data loss:
  1. Write `recovery_log` row (with patch path) in SQLite `BEGIN IMMEDIATE` transaction BEFORE any destructive action
  2. Create patch file with **content-addressed naming**: `recovery-<bead_id>-<sha256(diff)>.patch` — same diff = same filename = idempotent, no duplicate patches
  3. Only then execute `git checkout -- <reserved-files>` (the destructive step)
  4. Release interlock reservations, unclaim bead, re-dispatch

  Interlock reservations scope the recovery to only the files that agent touched — other agents' uncommitted work is untouched.
  - **Key insight:** Interlock already creates per-session `GIT_INDEX_FILE` isolation, so each agent's changes are trackable independently.
  - **v0.2 graduation:** At scale (>5 concurrent agents), graduate to per-agent git worktrees (`--worktree` flag in Claude Code) for full filesystem isolation.
  - **Patch cleanup:** Patches are deleted after the associated bead is successfully closed or after 30 days, whichever comes first. The patrol loop checks for patches whose bead ID is in `closed` status and deletes them.
  - **Durable receipt:** Patch file paths are written to the `recovery_log.context` JSON column (not just TUI display), so patch refs survive Mycroft restarts.
  - **Recovery resumption precondition:** Before resuming an incomplete recovery (from `recovery_log` entries with `status='started'`), validate that the bead is still claimed by the original agent and no new session has started work on it. If a new agent has claimed the bead, skip the stale recovery.
- **Escalate:** Send notification to user (TUI badge + desktop notification). Pause bead (`bd update <id> --status=blocked`). Wait for user input before proceeding.

**Retry limit:** Max 3 recovery attempts per bead, tracked as a **monotonic integer counter** (not time-based — immune to clock skew). After 3 failed dispatch-crash-recover cycles, mark the bead as blocked with reason (`bd update <id> --status=blocked --notes="auto-blocked: 3 recovery failures"`) and escalate to user. Counter resets when the bead transitions to a new state (re-dispatched to a different agent, or manually unblocked). Wall clock timestamps used for logging/display only, not for retry decisions.

### Stuck detection

Mycroft detects stuck agents via intermux's state detection, with **phase-aware thresholds**: brainstorm/research phases get 15 min before stuck classification (legitimate deep thinking), build/test phases keep 5 min (shorter feedback loops expected). The bead's current phase (from `bd get-state <bead> assigned_phase`) determines which threshold applies. Additional heuristics:
- **Spin detection:** Same output pattern repeated >3 times (intermux already does repetition analysis)
- **Tool loop:** Agent calling same tool >5 times with same arguments (detectable from pane capture)
- **Stale claim:** Bead claimed >45 minutes ago with no progress events (aligned with Clavain's `beadClaimStaleSeconds = 2700`)

Stuck agents are classified as clean or dirty failures based on git/interlock state, then routed through the recovery matrix.

## Resolved: Fleet Registry

### Compose from existing sources, don't duplicate

Agent data already lives across 5 systems. Mycroft composes a unified `FleetView` at read time rather than maintaining a redundant registry.

**Data sources (queried each patrol cycle):**

| Source | What it provides | Query method |
|--------|-----------------|--------------|
| `fleet-registry.yaml` | Capabilities, models, cost baselines (35+ agents) | File read (YAML) |
| Intermute `list_agents` | Live status, last_seen, file reservations | MCP tool / HTTP API |
| Intermux `agent_health` | Active/idle/stuck/crashed classification | MCP tool |
| Beads `bd ready --json` | Available work, priorities, dependencies | CLI |
| Interlock `check_conflicts` | File reservation conflicts | MCP tool |
| Interstat (via fleet registry enrichment) | Actual token costs per agent x model | Already merged into fleet-registry.yaml |

**Composed FleetView (in-memory, rebuilt each cycle):**
```go
type FleetView struct {
    Agents       []AgentView
    Work         []BeadView
    Conflicts    []ConflictView
    Freshness    map[string]time.Time // per-source timestamp (keyed by source name)
}

type AgentView struct {
    Name         string
    Runtime      string   // "claude-code" | "skaffen"
    Capabilities []string // from fleet-registry.yaml
    Status       string   // from intermux
    CostProfile  CostProfile // from fleet-registry + interstat
    CurrentBead  string   // from beads claim state
    Health       HealthReport // from intermux
    Reservations []string // from interlock
}
```

**Staleness gating:** The `Freshness` map tracks when each source was last successfully queried. If a source is stale beyond 2x its poll interval (e.g., beads stale >120s), the `select/` package defers dispatch decisions but the patrol loop continues health monitoring. This prevents acting on mixed-freshness data that could cause double-claims.

**Consistency model:** FleetView is eventually consistent within one patrol cycle (30-60s). Sources are queried sequentially, so an agent's state can change between the first and last query within a single cycle. This is accepted by design — the pre-dispatch interlock conflict check (P1 #3) is the safety net against double-claims, not FleetView consistency. No atomic snapshot across sources is attempted.

### Mycroft-owned state (thin)

Two artifacts owned exclusively by Mycroft (no assignment files — dispatch metadata lives in bead state):

**1. Config:** `.autarch/mycroft/config.yaml` (project-local, follows Autarch convention)
```yaml
tier: 0                      # current autonomy tier
dispatch_preferences:
  max_concurrent_agents: 5
  daily_budget: 50.00        # USD, stop dispatching above this
tier2_dispatch_allowlist:
  - { type: task, max_priority: 3, max_complexity: medium }
  - { type: bug, max_priority: 3, max_complexity: simple }
  - { type: docs, max_priority: 2, max_complexity: any }
demotion_triggers:
  failure_rate_window: 24h
  t3_failure_rate_threshold: 0.25    # >25% → T3 demotes to T2
  t2_failure_rate_threshold: 0.15    # >15% → T2 demotes to T1 (symmetric)
  consecutive_failure_limit: 3       # 3 in a row → immediate one-tier demotion
  budget_overshoot_threshold: 1.2    # >120% → demote to T0
  min_sample_size: 20                # don't evaluate thresholds below 20 dispatches
agent_overrides:
  grey-area:
    max_concurrent: 2
    priority_bias: [go, rust]
```

**2. Decision log:** `.autarch/mycroft/decisions.db` (SQLite, project-local)
```sql
CREATE TABLE dispatch_log (
  id INTEGER PRIMARY KEY,
  ts INTEGER,
  project TEXT DEFAULT 'demarch',  -- multi-project ready, hardcoded in v0.1
  agent TEXT,                      -- always Culture ship name (canonical identifier)
  bead TEXT,
  action TEXT,     -- shadow_suggest, suggest, auto_dispatch, restart, patch_reassign, escalate, pause, resume, manual_override
  outcome TEXT,    -- accepted, rejected, success, failure
  reason TEXT,     -- user's reject/override reason (from inline approval, e.g., "too risky")
  context TEXT,    -- JSON: tier_at_time, cost_estimate, selector_reasoning
  cost_actual REAL -- actual token cost from interstat, written after bead close
);

CREATE TABLE tier_state (
  key TEXT,
  project TEXT DEFAULT 'demarch',  -- multi-project ready, hardcoded in v0.1
  value TEXT,
  PRIMARY KEY (key, project)       -- 'current_tier', 'last_promotion', 'last_demotion'
);

CREATE TABLE tier_transitions (
  id INTEGER PRIMARY KEY,
  ts INTEGER,
  project TEXT DEFAULT 'demarch',
  from_tier INTEGER,
  to_tier INTEGER,
  trigger TEXT,            -- 'manual', 'auto_graduate', 'circuit_breaker', 'budget_overshoot'
  evidence TEXT            -- JSON snapshot: approval_rate, completion_rate, sample_size, interspect_class
);

-- Write-ahead log for crash-safe recovery actions
CREATE TABLE recovery_log (
  id INTEGER PRIMARY KEY,
  ts INTEGER,
  agent TEXT,
  bead TEXT,
  action TEXT,      -- patch_save, git_checkout, interlock_release, unclaim, redispatch
  status TEXT,      -- started, completed, failed
  error TEXT,       -- NULL on success, error message on failure
  context TEXT      -- JSON: patch_path, reserved_files, etc.
);
```

**Recovery idempotency (WAL-first):** Before executing any destructive recovery step, Mycroft writes the intent to `recovery_log` in a `BEGIN IMMEDIATE` SQLite transaction. The `recovery_log` row (including patch path) is durable BEFORE `git checkout` executes. On crash and restart, the patrol loop checks for incomplete `recovery_log` entries and resumes from the last completed step — with **precondition validation**: verify the bead is still claimed by the original agent and no new session has started work. Each recovery action is individually idempotent (patching an already-patched file, releasing already-released locks, unclaiming an already-unclaimed bead are all no-ops).

**Dual graduation signal:** Tier promotion requires BOTH user approval rate (>90% of suggestions accepted) AND bead completion rate (>70% of dispatched beads closed successfully within 2x estimated time). Approval alone is insufficient — it measures trust, not outcome quality. Both thresholds are configurable in `config.yaml`. The demotion triggers (circuit breaker) also query dispatch_log for failure rate in the rolling window.

**Override pattern analysis:** `mycroft overrides` summarizes user rejection/override patterns (frequency, common reasons from `dispatch_log.reason`). High override rate is a negative signal for graduation — if the user frequently rejects Mycroft's suggestions, the selector needs recalibration, not promotion.

### Integration seams

**Source priority (when data conflicts):**
- **Intermux** = ground truth for session liveness (is the agent running?)
- **Beads** = ground truth for work assignment (which bead is claimed?)
- **Interlock** = ground truth for file ownership (which files are reserved?)
- **Intermute** heartbeat degrades gracefully (stale heartbeat = unknown, not dead)

**No capabilities in Mycroft config.** Mycroft's config (`.autarch/mycroft/config.yaml`) contains only Mycroft-specific overrides (`max_concurrent`, `priority_bias`). Capabilities come exclusively from `fleet-registry.yaml`. No duplication, no collision.

**Session name format versioning.** Agent name extraction depends on intermux's `{terminal}-{project}-{agent}-{number}` encoding. Add `session_name_format: v1` to fleet-registry.yaml so Mycroft can detect format changes rather than silently mis-parsing.

**Hook ordering guarantee.** `mycroft-check` is implemented as a section within Clavain's `session-start.sh` (not a separate plugin hook), guaranteeing it fires after `bd prime` and before `/route`. Plugin hook ordering across separate plugins is non-deterministic.

### Why compose, not own

- **No data duplication** — fleet-registry.yaml is already maintained by scan-fleet.sh
- **No sync bugs** — Mycroft always reads current state, never stale copy
- **Existing tools keep working** — interlock, intermux, interstat unaware of Mycroft
- **Thin Mycroft state** — only config + decision log (both Mycroft-specific) + dispatch metadata in bead state (shared, queryable)
- **Cost pipeline reuse** — Mycroft consumes calibrated cost estimates from fleet-registry.yaml (scan-fleet.sh's job). `dispatch_log` records the estimate used at dispatch time for audit + records `cost_actual` after bead close from interstat. No separate cost model.
