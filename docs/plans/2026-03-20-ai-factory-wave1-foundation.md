---
artifact_type: plan
bead: Sylveste-ysxe
stage: plan
version: 1
---
# Plan: AI Factory Wave 1 — Foundation

**Epic:** Sylveste-ysxe
**PRD:** docs/prds/2026-03-20-ai-factory-orchestration.md
**Brainstorm:** docs/brainstorms/2026-03-19-ai-factory-orchestration-brainstorm.md
**Research:** docs/research/flux-research/phase1-self-dispatch/synthesis.md

## Goal

Ship the minimum viable self-dispatching factory: agents autonomously pull beads, pass deterministic quality gates, recover from failures, and report basic fleet health. Validate with 3+ agents self-dispatching for 48 hours.

## Implementation Sequence

### Batch 1: Atomic Claim (P0, 2-4 hours)

**Why first:** The two-phase claim (bd update --claim + bd set-state) has a crash window that zombies beads. Every other feature depends on reliable claiming.

**Files to modify:**
- `os/Clavain/hooks/lib-sprint.sh` — `bead_claim()` function
- `os/Clavain/go/cmd/clavain-cli/` — `bead-claim` subcommand

**Steps:**
1. Verify `bd update --claim` uses `WHERE status='open'` precondition (read bd source)
2. Create `clavain-cli bead-claim-atomic` that runs a single Dolt SQL transaction:
   ```sql
   UPDATE beads SET status='in_progress', assignee=?, claimed_by=?, claimed_at=?
   WHERE id=? AND status='open'
   ```
3. Add post-claim verification: re-read bead and confirm claimed_by matches own session ID
4. Update `bead_claim()` in lib-sprint.sh to call the new atomic path
5. Add deprecation warning to old two-phase callers
6. Test: parallel claim script (10 concurrent, assert exactly 1 winner)

**Validation:** `bd show <id>` shows consistent claimed_by/assignee after concurrent claims

### Batch 2: Deterministic Quality Gates (P0, 4-6 hours)

**Why second:** Gates are prerequisite for unsupervised execution. Without them, self-dispatch could land broken code.

**Files to create/modify:**
- `os/Clavain/go/cmd/clavain-cli/quality_gates.go` — gate runner
- `os/Clavain/hooks/lib-gates.sh` — shell wrapper for sprint integration

**Steps:**
1. Implement `clavain-cli quality-gate-run` that:
   - Detects project language(s) from file extensions / go.mod / Cargo.toml / pyproject.toml
   - Runs per-language checks: Go (go build, go test, golangci-lint), Rust (cargo check, cargo test, cargo clippy), Python (ruff check, pytest), Shell (shellcheck)
   - Captures structured result: {check, pass/fail, duration_ms, output_snippet}
   - Exits non-zero on any failure
2. Wire into sprint Step 6 (test & verify) — `lib-gates.sh` calls `clavain-cli quality-gate-run`
3. Record gate verdict in beads state: `bd set-state <id> gate_result pass|fail`
4. On failure: sprint blocks, agent must fix before proceeding (existing Step 6 behavior)

**Validation:** Run against 3 known-broken commits, confirm all caught. Run against 3 clean commits, confirm all pass.

### Batch 3: Self-Dispatch Loop (P1, 6-8 hours)

**Why third:** This is the keystone feature. Requires atomic claim (Batch 1) and should use gates (Batch 2) in the dispatch flow.

**Files to create/modify:**
- `os/Clavain/hooks/self-dispatch.sh` — Stop hook handler
- `os/Clavain/go/cmd/clavain-cli/self_dispatch.go` — scoring and selection
- `os/Clavain/hooks/lib-discovery.sh` — bead scoring function (may already have primitives)

**Steps:**
1. **Trigger mechanism:** Add Stop hook that checks for `CLAVAIN_SELF_DISPATCH=true`:
   - On bead close: write `dispatch_signal` marker file
   - On Stop hook: if signal file exists AND idle for 20s, trigger dispatch
   - Circuit breaker: max 3 consecutive dispatch failures before pause
2. **Scoring function** (`clavain-cli dispatch-score`):
   - Input: `bd list --status=open` filtered to ready beads
   - Score: priority (40%) + phase alignment (25%) + recency (15%) + deps-ready (12%) + WIP-balance (8%)
   - Add ±5 random perturbation to break ties
   - Output: top bead ID + score breakdown (for telemetry)
3. **Dispatch flow:**
   - Score → select top bead → add random 0-500ms jitter → atomic claim → dispatch via route.md
   - On claim failure (race): re-score and retry once, then back off 30s
   - WIP limit: check agent holds 0 in-progress beads before dispatch
4. **Capability filter:** Skip beads tagged with languages/modules agent can't handle (read from agent config or infer from recent work)
5. **Telemetry:** Log dispatch events: {timestamp, agent_id, bead_id, score, outcome}

**Validation:** Start 3 agents with CLAVAIN_SELF_DISPATCH=true, seed 10 open beads, observe autonomous claim+execute+close cycle for 2+ beads per agent.

### Batch 4: Failure Recovery (P1, 4-6 hours)

**Why fourth:** Self-dispatch needs a safety net. Without recovery, a single failure can zombie an agent.

**Files to create/modify:**
- `os/Clavain/go/cmd/clavain-cli/watchdog.go` — sweep daemon
- `os/Clavain/hooks/lib-recovery.sh` — failure classification + escalation

**Steps:**
1. **Failure classification** in lib-recovery.sh:
   - `retriable`: transient errors, flaky test output, agent crash (intermux StatusCrashed)
   - `spec_blocked`: 2+ failed attempts with no commits, error contains "ambiguous"/"unclear"
   - `env_blocked`: error matches /auth|Dolt|ENOSPC/, 2+ failures within 120s
2. **Watchdog sweep** (`clavain-cli watchdog`):
   - Runs every 60s (invoked from SessionStart hook or standalone)
   - For each in-progress bead: check heartbeat age against 600s TTL
   - If stale: check intermux pane status
   - If pane alive + output: refresh heartbeat (false positive)
   - If pane dead: unclaim + re-queue + increment attempt_count
3. **Escalation tiers:**
   - Tier 1: Auto-retry (attempt_count < 3, retriable) — unclaim, re-queue
   - Tier 2: Quarantine (attempt_count >= 3 OR spec_blocked) — set status=blocked
   - Tier 3: Circuit breaker (3+ quarantines in 30min from same agent) — pause agent dispatch
   - Tier 4: Factory pause (circuit breakers on 2+ agents in 15min) — pause all dispatch, notify
4. **Disruption budget:** Max 2 simultaneous unclaims per sweep cycle, min 1 agent always working

**Validation:** Kill an agent mid-execution, confirm bead recovers to backlog within 10 minutes. Trigger 3 consecutive failures, confirm circuit breaker pauses dispatch.

### Batch 5: Fleet Feedback Dashboard (P2, 2-3 hours)

**Why last:** Observability over the running factory. Nice-to-have but not blocking.

**Files to create/modify:**
- `os/Clavain/go/cmd/clavain-cli/factory_status.go` — dashboard command

**Steps:**
1. `clavain-cli factory-status` queries:
   - Fleet utilization: count tmux sessions with active dispatches / total sessions
   - Queue depth: `bd list --status=open` grouped by priority
   - WIP balance: `bd list --status=in_progress` grouped by assignee
   - Recent dispatches: last 10 dispatch events from telemetry log
2. Format as compact terminal table
3. Optional: `--json` output for integration with other tools

**Validation:** Run with 3 active agents, confirm output shows correct counts.

## Dependency Graph

```
Batch 1 (Atomic Claim) ← Batch 3 (Self-Dispatch) ← Batch 4 (Failure Recovery)
                                                   ← Batch 5 (Fleet Dashboard)
Batch 2 (Quality Gates) ← Batch 3 (uses gates in dispatch flow)
```

Batches 1 and 2 are independent and can be parallelized. Batch 3 depends on both. Batches 4 and 5 depend on Batch 3.

## Estimated Effort

| Batch | Effort | Sessions |
|-------|--------|----------|
| 1. Atomic Claim | 2-4 hours | 1 |
| 2. Quality Gates | 4-6 hours | 1-2 |
| 3. Self-Dispatch | 6-8 hours | 2-3 |
| 4. Failure Recovery | 4-6 hours | 1-2 |
| 5. Fleet Dashboard | 2-3 hours | 1 |
| **Total** | **18-27 hours** | **6-9 sessions** |

## Risks

1. **Dolt transaction semantics:** Need to verify Dolt supports the atomic UPDATE...WHERE pattern. If not, fallback to Dolt's merge conflict detection (looser but still safe).
2. **Stop hook reliability:** If Stop hook fires inconsistently, dispatch trigger is unreliable. Mitigation: intermux watcher as fallback trigger.
3. **Score perturbation tuning:** ±5 jitter may not be enough to prevent herding at scale. Will need empirical tuning during 48-hour validation.

## Validation Protocol (48-hour test)

1. Create 20+ open beads across 3 priority tiers
2. Start 3 agents with `CLAVAIN_SELF_DISPATCH=true`
3. Monitor via `clavain-cli factory-status` every 4 hours
4. Success criteria:
   - All 3 agents dispatch autonomously (no human per-task commands)
   - Deterministic gates catch at least 1 real issue
   - Stale-claim recovery triggers <=2 false positives
   - No bead zombied for >15 minutes
