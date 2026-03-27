# Sylveste Work Orchestration & Agent Coordination Learnings

**Compiled:** 2026-03-19
**Purpose:** Institutional learnings from Sylveste's multi-agent orchestration, sprint workflow, and work coordination systems. Reference for flux-drive and future work orchestration design.

---

## Executive Summary

Sylveste has developed a mature orchestration architecture across three layers:

1. **Sprint Kernel** (Intercore) — transactional orchestration, phase gating, event-driven coordination
2. **Work Routing** (Clavain + Mycroft) — dispatch planning, agent claiming, capability-aware assignment
3. **Coordination Fabric** (Interlock + Intermute) — file reservations, session visibility, conflict detection

Key learnings center on **TOCTOU prevention, graceful degradation fallbacks, and receipts-driven loops**.

---

## Architecture Overview

### Three-Layer Coordination Model

```
┌─────────────────────────────────────────┐
│ Clavain (Work Composition)              │
│ ├─ /sprint (session start + dispatch)   │
│ ├─ /work (plan-driven multi-agent)      │
│ └─ C3 Composer (plan generation)        │
└────────────┬────────────────────────────┘
             │ bd create/claim
             ↓
┌─────────────────────────────────────────┐
│ Beads (Work Tracking)                   │
│ ├─ Single source of truth                │
│ ├─ Claiming prevents double-assignment   │
│ └─ State machine (todo→claimed→closed)  │
└────────────┬────────────────────────────┘
             │ bd claim updates
             ↓
┌─────────────────────────────────────────┐
│ Intercore Kernel (Orchestration)        │
│ ├─ Transactional run state               │
│ ├─ Phase gating + events                 │
│ ├─ Portfolio runs (cross-project)        │
│ └─ Dispatch coordination                 │
└────────────┬────────────────────────────┘
             │ reservations
             ↓
┌──────────────────────────────────────────┐
│ Interlock + Intermute (Coordination)     │
│ ├─ File reservations (prevent conflicts) │
│ ├─ Session visibility (status dashboard) │
│ └─ WebSocket notifications               │
└──────────────────────────────────────────┘
```

---

## Key Learnings by Domain

### 1. TOCTOU Prevention & Transactional Coordination

**Location:** `docs/solutions/database-issues/toctou-gate-check-cas-dispatch-intercore-20260221.md`

#### The Problem

Gate evaluation in Intercore reads state across multiple SQL tables (count artifacts, count active agents, check verdicts) and then updates phase—but the check and update are separate SQL statements. Between check and write, another concurrent agent can change state, causing invalid phase transitions (e.g., gate reads "1000 artifacts completed" but 3 more complete while the gate checks, leading to false positives).

#### Solution Pattern: Tx-Scoped Querier Wrappers

Wrap gate checks + phase update in a **single transaction**:

```go
tx, err := store.BeginTx(ctx)
defer tx.Rollback()

// Gate checks run inside the transaction
txRT := &txRuntrackQuerier{q: tx}
gateResult, _ := evaluateGate(ctx, run, ..., txRT)

// Phase update in same transaction
store.UpdatePhaseQ(ctx, tx, runID, from, to)

// Event recorded in same transaction
store.AddEventQ(ctx, tx, &PhaseEvent{...})

tx.Commit()  // atomic unit
```

**Key insight:** `SetMaxOpenConns(1)` at the Go level doesn't prevent TOCTOU because between releasing and re-acquiring the connection, another goroutine interleaves. Only transaction boundaries prevent this.

#### Double-Layer Defense for Status Updates

When a field has terminal states (e.g., dispatch status: completed, failed), use:

1. **Go-level guard** — reject transitions from terminal states before attempting the UPDATE
2. **CAS guard in SQL** — UPDATE WHERE `id = ? AND status = ?` with expected prior status, check `RowsAffected()`

The CAS guard alone is insufficient — a goroutine reading `status=completed` will match `WHERE status='completed'`, so a Go-level terminal-state check is necessary.

#### Prevention

- Always wrap check-then-act database patterns in a transaction
- Status columns need both CAS guards AND application-level terminal-state rejection
- When querier interfaces cross package boundaries, use tx-scoped wrappers instead of adding transaction parameters (avoids coupling)
- Fire side-effects/callbacks OUTSIDE the transaction

---

### 2. Multi-Agent File Coordination Without Merging

**Location:** `docs/solutions/patterns/git-autosync-multi-agent-coordination-20260304.md`

#### The Problem

Concurrent Claude Code agents on Mac and server edit the same files. Mutagen syncs bidirectionally with **last-write-wins** conflict resolution — concurrent edits silently discard one side's changes. No error, no warning, work just vanishes.

#### Solution: Git as Coordination Layer

Layer **git on top of Mutagen** — Claude Code hooks commit and push after every edit, pull at session start. Git's three-way merge handles conflicts properly.

#### Key Patterns

**Token-Based Debounce (No External Daemons)**

```bash
TOKEN="$$-$(date +%s%N)"
echo "$TOKEN" > "$TRIGGER"
sleep 3
CURRENT=$(cat "$TRIGGER" 2>/dev/null)
if [[ "$CURRENT" != "$TOKEN" ]]; then
  exit 0  # superseded by newer invocation
fi
```

If another hook wrote a newer token during sleep, this one exits. No flock dependency, works cross-platform.

**mkdir as Atomic Lock**

`flock` is Linux-only. `mkdir` is atomic on POSIX filesystems:

```bash
LOCKDIR="$REPO_ROOT/.git/autosync.lockdir"
while ! mkdir "$LOCKDIR" 2>/dev/null; do
  # stale lock check, wait up to 15s
done
trap 'rmdir "$LOCKDIR"' EXIT
```

**All State in .git/**

Lock, trigger, and log files live in `.git/` (excluded from sync and git tracking) to prevent the coordination metadata from causing its own sync conflicts.

**Push-Retry with Auto-Rebase**

```bash
if ! git push origin "$BRANCH"; then
  git pull --rebase --autostash origin "$BRANCH"
  git push origin "$BRANCH"
fi
```

#### Trade-Offs

- Noisy history: sync commits accumulate. Acceptable — they're automation artifacts
- `git add -A` is aggressive: First commit in dirty repo sweeps up all untracked. Use `--no-verify` to skip pre-commit hooks
- Not a replacement for intentional commits: Session close protocol still applies for milestones

#### Prevention

- Debounce before commit (avoid 1 commit per edit)
- Auto-rebase on push failure (handle concurrent pushes from other agents)
- Fail-silent contract: hooks never surface errors to agents, log to `.git/autosync.log` instead

---

### 3. Last-Mile Activation & Silent Degradation

**Location:** `docs/solutions/patterns/activation-sprint-last-mile-gap-20260307.md`

#### The Pattern

Thorough brainstorms + implementations produce complete infrastructure that's never tested end-to-end. Three instances where "build X" turned out to be config flips or already-built-but-unactivated.

**Example:** Bead estimated "3 sessions to build a 3-layer system" turned out to need only verification + one config line because all 4 layers were already built but modes were `off`/`shadow`.

#### Root Cause

Fail-safe design (every dependency optional, never blocks) is correct for resilience but creates a blind spot: you can't tell the difference between "working correctly" and "not installed" because both produce the same observable behavior — silent degradation to stubs.

#### Detection Signals

- Bead description says "build X" but `infer-action` returns `execute` (plan exists)
- Infrastructure exists in code but mode is `off`/`shadow`
- Plugin or hook exists in source but isn't in installed cache
- Zero events in tracking tables despite recording code existing

#### Resolution Pattern

1. **Verify end-to-end** — don't assume components work just because they exist
2. **Fix pipeline breaks** — DB path resolution, missing allowlist entries, empty caches
3. **Flip the switch** — change mode from `shadow`/`off` to `enforce`/`on`
4. **Smoke test** — run one real transaction through entire pipeline

#### Prevention

- Add "activation verification" as a standard gate after implementation
- Discovery scanner should flag `shadow`/`off` modes as activation candidates
- First-run verification catches setup gaps early
- When brainstorming a bead, check if infrastructure already exists before estimating effort

---

### 4. Multi-Agent Dispatch Architecture

**Location:** `docs/cujs/clavain-parallel-dispatch.md`, `docs/cujs/multi-agent-coordination.md`

#### Parallel Dispatch Model

For a plan with 8 tasks:

1. **Dependency analysis** — identify parallel sets (tasks 1-3 have no deps, can run simultaneously)
2. **Dispatch** — assign independent tasks to agents, wait for blocking tasks to complete
3. **Coordination** — file reservations prevent conflicts, Interlock warns/blocks on conflicts
4. **Re-dispatch** — if task fails, retry up to 2 times with different agent
5. **Aggregate quality gates** — intersynth operates on combined diff, not per-task

**Friction point:** Dependency analysis is task-level, not file-level. Clavain knows task 4 depends on task 1 but not which specific files task 4 needs. Over-conservative file reservation is common.

#### Multi-Agent Coordination Layers

1. **Interlock** — file-level reservation (exclusive/shared modes, TTL with heartbeat)
2. **Intermute** — agent visibility (messaging, WebSocket notifications, registration)
3. **Beads** — bead claiming prevents double-assignment
4. **Intercore** — event bus + shared state store

**Friction point:** File-level granularity only. Two agents editing different functions in same file must negotiate. Fine-grained locking (future) would allow simultaneous edits on non-overlapping sections.

#### Bead Claiming Protocol

- `bd update <id> --claim` sets assignee + status
- Must follow with `bd set-state claimed_by=$SESSION_ID claimed_at=$(epoch)` to complete the claim
- Use `bead_claim()` bash helper (or `clavain-cli bead-claim` in Go) — both steps together
- Stale claims expire via adaptive timeout (default 15 min TTL, auto-renewing on edits)

**Prevention:** Always use wrapper functions, never just `bd update --claim` alone.

---

### 5. Fleet Registry & Cost-Aware Scheduling

**Location:** `docs/plans/2026-02-20-cost-aware-agent-scheduling.md`, project memory

#### Budget Defaults by Complexity Tier

```bash
_sprint_default_budget() {
    local complexity="${1:-3}"
    case "$complexity" in
        1) echo "50000" ;;     # discovery/simple
        2) echo "100000" ;;    # design/moderate
        3) echo "250000" ;;    # build/complex
        4) echo "500000" ;;    # ship/very complex
        5|*) echo "1000000" ;; # multi-session
    esac
}
```

Calibrated from interstat session data (Feb 2026).

#### Cost Estimation Pipeline

1. **Hardcoded defaults** — start with complexity-based budget
2. **Collect actuals** — interstat records per-phase tokens
3. **Calibrate from history** — enrichment pipeline blends baseline + historical delta
4. **Defaults as fallback** — hardcoded values fire when history absent

**Pattern name:** Four-stage calibration. Shipping fewer than all four stages is incomplete work.

#### Enrichment Script

`scan-fleet.sh --enrich-costs` reads historical actuals from interstat and writes per-agent×model stats to fleet-registry.yaml. `estimate-costs.sh` consumes registry baseline + newer interstat delta.

**Gotcha:** Real interstat DB stores hex session IDs as `agent_name`, not fleet-registry names. Enrichment plumbing is correct but needs interstat to write proper agent identifiers.

---

### 6. Sprint Kernel & Phase Gating

**Location:** `docs/plans/2026-02-20-sprint-handover-kernel-driven.md`, `docs/plans/2026-02-21-intercore-e8-portfolio-orchestration.md`

#### From Beads Fallback to Kernel-Driven

Original lib-sprint.sh had ~50% beads fallback code. Migration path:

1. **Add missing intercore wrappers** — `intercore_run_create()`, `intercore_run_list()`, `intercore_run_status()`, `intercore_run_advance()`, etc.
2. **Use associative array for run ID cache** — `_SPRINT_RUN_ID_CACHE[$bead_id]="$run_id"` instead of singleton variable
3. **Make bead creation fatal when bd available** — if bd is available but fails, abort sprint. Only skip bead if bd is not installed
4. **Reorder ic_run_id write** — after phase verification check, not before
5. **Fix JSON field names** — events use `.event_type`, `.to_phase`, `.created_at`; tokens use `.input_tokens`/`.output_tokens`

#### Portfolio Runs (Cross-Project Orchestration)

Schema addition: `parent_run_id` + `max_dispatches` columns on runs table.

**Portfolio model:**
- Parent run with `project_dir = ""` (empty)
- Child runs with `parent_run_id = portfolio.ID`
- Atomic portfolio creation via transaction (BEGIN/INSERT portfolio/INSERT children/COMMIT)
- Cancel cascade: canceling portfolio also cancels all children + their dispatches

**Guard against:** Empty `project_dir` in `Current()` — prevents matching portfolio runs.

#### Gate Mode Graduation

Per-stage `gate_mode` (from agency spec):

- **Enforce** for cheap-to-redo phases (discover, design) — blocks on failures
- **Shadow** for expensive phases (build, ship) — logs but doesn't block

**Rationale:** Gate strictness inversely proportional to cost of re-doing the gated work.

---

### 7. Dispatch Planning & Safety Floors

**Location:** `docs/solutions/2026-03-03-c3-composer-dispatch-plan-generator.md`

#### Safety Floor Invariant vs. Routing Overrides

Routing overrides can exclude agents from active fleet before `matchRole` runs. If a safety-floor agent (fd-safety, fd-correctness) is excluded, the safety invariant is silently violated.

**Solution:** Emit `WARNING:safety_floor_excluded:<agent>:<reason>` at exclusion time. Make the violation visible (can't enforce if agent doesn't exist in plan, but warning makes it detectable).

**Pattern:** When two policies can conflict, the weaker one emits a high-severity warning. Never silently let one defeat another.

#### Shell-to-JSON Variable Injection

**Never interpolate shell variables into inline Python/Ruby code:**

```bash
# WRONG — version string can escape quotes and inject code
python3 -c "import json; v='$VERSION'; print(json.dumps(v))"

# RIGHT — pass via sys.argv
python3 -c "import sys; v=sys.argv[1]; print(json.dumps(v))" "$VERSION"
```

#### Nil Map Panic in Go Struct Merge

YAML unmarshaling leaves maps as `nil` when key is absent:

```go
// Guard before assignment
if base.Stages == nil {
    base.Stages = make(map[string]StageSpec)
}
for stageName, spec := range override.Stages {
    base.Stages[stageName] = spec  // panic if base.Stages is nil
}
```

#### Optional Loaders: Distinguish Missing from Corrupt

```go
// Missing file (expected) → return nil silently
// Corrupt config (bug) → log to stderr, then return nil

if err != nil && !os.IsNotExist(err) {
    log.Fprintf(stderr, "config parse error: %v\n", err)
}
return nil
```

Optional loaders degrade gracefully but shouldn't hide parse failures.

---

### 8. Hook Contracts & PostToolUse Patterns

**Location:** `docs/solutions/patterns/interhelm-plugin-sprint-learnings-20260309.md`

#### PostToolUse Hook Input Contract

PostToolUse hooks receive JSON on stdin (`{"tool_name", "tool_input", "tool_response"}`), not via env var:

```bash
# WRONG
python3 -c "..." "$TOOL_INPUT"

# RIGHT
HOOK_INPUT=$(cat)
printf '%s' "$HOOK_INPUT" | python3 -c "..."
```

**Critical:** Always `cat` or `HOOK_INPUT=$(cat)` to read stdin. Using `$TOOL_INPUT` env var is a silent failure — hook runs but produces no effect.

#### Binary-Safe Piping

`echo` interprets escape sequences and corrupts JSON with `\n` or `\\`:

```bash
# WRONG
echo "$HOOK_INPUT" | python3 -c "..."

# RIGHT
printf '%s' "$HOOK_INPUT" | python3 -c "..."
```

#### Stdin Drain Required Even When Unused

Not reading stdin can block the hook runtime's pipe buffer:

```bash
# Top of any PostToolUse hook that doesn't use stdin
cat > /dev/null
```

#### Hook Guard Ordering Matters

Check the cheapest guard first (file existence) before expensive ones (stdin parsing):

```bash
# WRONG — parse JSON on every project
if [[ "$cmd" == "git commit" ]]; then
    HOOK_INPUT=$(cat)
    # ...
fi

# RIGHT — check project guard first
if ! grep -q "diagnostic:" CLAUDE.md 2>/dev/null; then
    cat > /dev/null  # drain stdin
    exit 0
fi
HOOK_INPUT=$(cat)
# ...
```

---

### 9. Mutex Poisoning in Shared-State HTTP Servers

**Location:** `docs/solutions/patterns/interhelm-plugin-sprint-learnings-20260309.md`

#### The Problem

`state.lock().unwrap()` in all handlers means if any handler panics while holding lock, mutex is poisoned and ALL subsequent requests panic — total server failure.

#### Solution

```go
// Recover from poisoned mutex instead of propagating panic
state.lock().unwrap_or_else(|e| e.into_inner())
```

Recovery allows requests after a handler panic instead of cascading failure.

---

### 10. Wiring > Building, Bridge Functions as Interfaces

**Location:** `docs/solutions/2026-03-04-c5-self-building-loop.md`

#### Complexity Classification Lesson

C5 (self-building loop) was estimated as complexity 5/5 but turned out to be complexity 3/5. All infrastructure existed (C1 specs, C2 fleet, C3 composer, C4 contracts) — the work was wiring them together with thin adapter functions.

**Lesson:** Complexity classification should weight novelty more than scope. Pure wiring should classify lower.

#### Bridge Functions as Critical Interfaces

When wiring subsystems, identify the bridge function early — it's the narrowest interface between domains.

Example: `phaseToStage()` mapping (from sprint phases: brainstorm/executing/shipping → agency spec stages: discover/build/ship) became critical because all three new features depend on it. Identify this early.

#### Fallback Chains for Resilience

Every new command falls back gracefully: compose plans → agency spec → hardcoded defaults.

**Rationale:** Self-building loop works even without ic/bd running — essential for bootstrapping. Fallback chains make autonomous systems resilient to partial infrastructure.

---

### 11. Multi-Agent Review Quality & Convergence

**Location:** `docs/solutions/patterns/interhelm-plugin-sprint-learnings-20260309.md`

#### Flux-Drive Plan Review Benefits

Plan review before execution caught P0 issues that implementation review missed (e.g., stdin contract violations). Different review stages catch different issue classes.

#### Multi-Agent Review Convergence

Multi-agent review (4 agents examining same code) had zero conflicts and consistent conclusions. Independent discovery of the same problems increases confidence.

#### Execution-Time Quality Gates

Execution-time gates (after implementation) caught issues the plan review missed (shell injection, mutex poisoning, echo corruption). Don't skip execution review — different stages are complementary, not redundant.

---

### 12. Mycroft Fleet Dispatch & Trust Tiers

**Location:** `docs/cujs/mycroft-fleet-dispatch.md`

#### Trust Tier Progression

```
T0: Observe only (shadow suggestions)
T1: Suggest (developer approves)
T2: Auto-dispatch (within allowlist)
T3: Autonomous (within daily budget)
```

Each tier requires evidence from lower tier. Shadow suggestions must be >80% correct. T1 must have >90% approval rate before promotion to T2.

#### Promotion / Demotion Criteria

- **Promotion:** Manual only (currently). Developer promotes after consistent correct decisions
- **Demotion:** Automatic on threshold breach (3 consecutive failures or 20% failure rate over last day)

**Future:** `ShouldPromote` nudge during patrol when criteria met.

#### Allowlist Scope (v0.2)

Type/priority/complexity only. Future extension: labels, file paths, agent capabilities.

#### Limitations

- No notification channel (suggestions only visible via `mycroft shadows`)
- Single fleet only (Autarch/Bigend handle multi-project)
- Allowlist can't gate on specific agent capabilities yet

---

## Closed-Loop Calibration Pattern

**Reference:** PHILOSOPHY.md § "Closed-loop by default"

All prediction systems must close the loop: predict → observe outcome → feed back to improve future predictions. Four stages, all mandatory:

| Stage | Example | Implementation |
|-------|---------|-----------------|
| 1. Hardcoded defaults | `_sprint_default_budget(complexity)` | estimates by tier |
| 2. Collect actuals | interstat per-phase tokens | query real outcomes |
| 3. Calibrate from history | `scan-fleet.sh --enrich-costs` | blend baseline + delta |
| 4. Defaults as fallback | `estimate-costs.sh` falls back when history absent | always ship all 4 stages |

Shipping stages 1-2 without 3-4 produces a constant masquerading as intelligence. Shipping stage 3 without 4 breaks when database is empty.

---

## Common Anti-Patterns & Prevention

### 1. Beads Fallback Over Kernel (ANTI-PATTERN)

**Don't:** Duplicate logic in both kernel + beads branches, leave beads as primary.

**Do:** Migrate to kernel-driven exclusively. Keep beads as user-facing identity (`CLAVAIN_BEAD_ID`), resolve run ID once and cache it.

### 2. Optional Loaders Hiding Errors (ANTI-PATTERN)

**Don't:** Return nil for both "file missing" and "file corrupt" cases.

**Do:** Distinguish — return nil silently for missing files, log stderr for parse errors, return nil.

### 3. Concurrent Edits Without Coordination (ANTI-PATTERN)

**Don't:** Rely on Mutagen last-write-wins or optimistic git merges for concurrent agent edits.

**Do:** Layer git autosync on file sync, use file reservations for exclusive access.

### 4. Status Updates Without CAS Guards (ANTI-PATTERN)

**Don't:** `UPDATE dispatches SET status = ? WHERE id = ?` without checking prior status.

**Do:** Add `AND status = ?` to WHERE clause, check `RowsAffected()`, add Go-level terminal-state rejection.

### 5. Check-Then-Act Without Transactions (ANTI-PATTERN)

**Don't:** SELECT to make a decision, then UPDATE as separate statements.

**Do:** Wrap both in BeginTx/Commit.

### 6. Shell Variables Interpolated into Code (ANTI-PATTERN)

**Don't:** `python3 -c "import json; v='$VERSION'; ..."` — version can escape quotes and inject code.

**Do:** Pass via sys.argv: `python3 -c "import sys; v=sys.argv[1]; ..." "$VERSION"`

### 7. Infrastructure Built but Never Activated (ANTI-PATTERN)

**Don't:** Complete implementation with mode=`shadow` or `off`, assume it works.

**Do:** Add activation verification as a gate. Smoke test the entire pipeline end-to-end before closing.

---

## Decision Support Table

| Decision | Guidance | Evidence |
|----------|----------|----------|
| Should we use transactions for this DB pattern? | If check-then-act, YES. Otherwise optional. | TOCTOU doc + prevention section |
| How to prevent concurrent file edits? | File-level reservations + git autosync. | Multi-agent coordination CUJ + git-autosync pattern |
| What's the default token budget by complexity? | 50K (simple) → 250K (complex) → 1M (multi-session) | lib-sprint.sh budget defaults |
| When should we gate strictly vs. shadow? | Enforce for cheap-to-redo (discover/design), shadow for expensive (build/ship) | C5 gate mode graduation |
| How to avoid Mutagen sync conflicts? | Git autosync as coordination layer, not just Mutagen | git-autosync pattern |
| Should we allow shell variables in code strings? | No. Use sys.argv / arg passing | C3 Composer + Interhelm learnings |
| What's the bead claiming protocol? | `bd update --claim`, then `bd set-state claimed_by/claimed_at` | Memory: bead_claim_system_architecture |
| How often should heartbeats renew? | Adaptive (fast on active output, slow on idle) | Multi-agent coordination CUJ § friction |
| What's the cost estimation fallback chain? | Interstat (≥3 runs) → fleet-registry → budget.yaml defaults | fleet-registry-calibration memory |
| Should we implement feature flags? | Yes, for safe rollout of orchestration changes | Hierarchical dispatch plan, activation sprint pattern |

---

## Research Gap Analysis

### Addressed in Sylveste

- ✓ TOCTOU prevention patterns (transactions + CAS)
- ✓ Multi-agent file coordination (git autosync + reservations)
- ✓ Bead claiming lifecycle (heartbeat + adaptive timeout)
- ✓ Cost-aware scheduling (complexity-based budgets)
- ✓ Sprint kernel architecture (Intercore transactional model)
- ✓ Portfolio runs (cross-project coordination)
- ✓ Phase gating + gate modes (enforce vs shadow)
- ✓ Dispatch planning + safety floors (C3 Composer)
- ✓ Multi-agent trust progression (Mycroft tiers)

### Remaining Research Gaps

- [ ] Fine-grained file locking (function/block level vs. whole-file)
- [ ] Automatic conflict resolution (non-overlapping changes)
- [ ] File-level dependency analysis (vs. task-level)
- [ ] Agent capability-aware dispatch (vs. fungible agents)
- [ ] Adaptive heartbeat interval tuning (currently fixed)
- [ ] Cost optimizations for parallelism (3 agents → 3x tokens/min)
- [ ] Multi-framework interoperability routing (beyond Go + Bash)
- [ ] Hierarchical dispatch latency impact measurement

---

## Key Documents by Pillar

### Sprint Kernel & Gating

- `docs/solutions/database-issues/toctou-gate-check-cas-dispatch-intercore-20260221.md` — TOCTOU prevention
- `docs/plans/2026-02-20-sprint-handover-kernel-driven.md` — kernel migration
- `docs/plans/2026-02-21-intercore-e8-portfolio-orchestration.md` — cross-project runs
- `docs/solutions/2026-03-04-c5-self-building-loop.md` — wiring + bridge functions

### Work Routing & Dispatch

- `docs/solutions/2026-03-03-c3-composer-dispatch-plan-generator.md` — plan generation
- `docs/cujs/clavain-parallel-dispatch.md` — parallel execution
- `docs/cujs/mycroft-fleet-dispatch.md` — fleet orchestration
- `docs/plans/2026-02-19-hierarchical-dispatch-meta-agent.md` — hierarchical model

### Coordination & Visibility

- `docs/solutions/patterns/git-autosync-multi-agent-coordination-20260304.md` — file sync
- `docs/cujs/multi-agent-coordination.md` — coordination layers
- `docs/plans/2026-02-15-multi-session-coordination-brainstorm.md` — session isolation

### Quality & Patterns

- `docs/solutions/patterns/interhelm-plugin-sprint-learnings-20260309.md` — hook contracts
- `docs/solutions/patterns/activation-sprint-last-mile-gap-20260307.md` — activation verification
- `docs/plans/2026-02-20-cost-aware-agent-scheduling.md` — budgeting
- PHILOSOPHY.md § "Closed-loop by default" — calibration pattern

### Supporting Infrastructure

- `docs/cujs/` — customer journeys (parallel-dispatch, multi-agent-coordination, fleet-dispatch)
- `docs/plans/2026-02-15-multi-session-coordination-brainstorm.md` — gap analysis
- Project memory entries (bead-claim, beads-workflow, fleet-registry, etc.)

---

## Recommendations for Flux-Drive Integration

1. **Adopt transactional gate evaluation** — don't defer this. Use Tx-scoped querier pattern.

2. **Wire cost estimation into routing** — use fleet-registry enrichment pipeline before dispatch planning.

3. **Activate verification as standard gate** — don't assume infrastructure works if it compiles. Smoke test.

4. **Use bridge functions** — when wiring subsystems (agency spec ↔ fleet registry), identify the narrowest interface and make it explicit.

5. **Implement fallback chains** — self-bootstrapping requires graceful degradation (compose plan → agency spec → defaults).

6. **Phase gates with mode graduation** — enforce for cheap-to-redo phases, shadow for expensive.

7. **Bead claiming with heartbeats** — prevent double-assignment, handle stale claims via adaptive timeout.

8. **Multi-agent review before execution** — flux-drive's plan review stage catches different issues than execution review.

9. **Audit trail for every dispatch decision** — Mycroft's log provides the model. Developer should never wonder "why was that assigned?"

10. **Safety floor warnings, not silent violations** — when routing overrides conflict with safety floors, emit warnings and make conflicts visible.

---

<!-- flux-research:complete -->
