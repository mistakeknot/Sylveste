# Symphony (OpenAI) Assessment

**Assessed:** 2026-03-07
**Bead:** iv-sym01
**Source:** github.com/openai/symphony (8.3k stars, Apache-2.0)
**Spec version:** SPEC.md as of 2026-03-05

---

## What It Is

Symphony is a long-running automation daemon that polls an issue tracker (Linear), creates isolated per-issue workspaces, and runs a coding agent (Codex app-server) for each eligible ticket. It is a **scheduler/runner** with no persistent database — all state lives in-memory and recovers from tracker + filesystem on restart.

**Stack:** Elixir/BEAM (reference impl). The spec is language-agnostic and explicitly designed for porting.

**Scope:** Orchestrator only. Symphony does not write to the issue tracker; ticket mutations (state transitions, comments, PR links) are performed by the coding agent via tools in the workflow prompt. The orchestrator's job is concurrency control, retry with backoff, reconciliation, and workspace lifecycle.

---

## Architecture Summary

### Components (7 required, 1 optional)

| Component | Role |
|-----------|------|
| Workflow Loader | Reads `WORKFLOW.md` (YAML front matter + prompt template) |
| Config Layer | Typed getters with env var indirection, dynamic reload |
| Issue Tracker Client | Linear GraphQL adapter; normalized issue model |
| Orchestrator | Poll loop, state machine, concurrency slots, retry queue |
| Workspace Manager | Per-issue dirs, lifecycle hooks (after_create, before_run, after_run, before_remove) |
| Agent Runner | Workspace + prompt + Codex app-server subprocess over stdio |
| Logging | Structured logs with issue/session context |
| Status Surface (opt) | Terminal UI, dashboard, or HTTP API |

### 6-Layer Abstraction

1. Policy (repo-owned `WORKFLOW.md`)
2. Configuration (typed getters from front matter)
3. Coordination (orchestrator state machine)
4. Execution (workspace + agent subprocess)
5. Integration (Linear adapter)
6. Observability (logs + optional status surface)

### Orchestrator State Machine

Issues flow through: `Unclaimed -> Claimed -> Running -> RetryQueued -> Released`

Key behaviors:
- Poll every 30s (configurable), reconcile before dispatch
- Global + per-state concurrency limits (`max_concurrent_agents=10`, `max_concurrent_agents_by_state`)
- `Todo` issues blocked by non-terminal blockers are not dispatched
- Normal exit -> 1s continuation retry (re-check if issue still active)
- Abnormal exit -> exponential backoff: `min(10s * 2^(attempt-1), max_retry_backoff_ms)`
- Stall detection: kill + retry if no agent event within `stall_timeout_ms` (5m default)
- Reconciliation: terminal tracker state -> kill + cleanup; non-active -> kill only

### Agent Runner Protocol (Codex app-server)

1. Launch `bash -lc <codex.command>` in workspace dir
2. JSON-RPC over stdio: `initialize` -> `initialized` -> `thread/start` -> `turn/start`
3. Stream turn events; extract session IDs, token counts, rate limits
4. Multi-turn: up to `max_turns` per worker session, re-checking tracker state between turns
5. Continuation guidance (not full prompt re-render) for turns 2+

### Workspace Lifecycle Hooks

```yaml
hooks:
  after_create: "git clone ..."      # Only on new workspace
  before_run: "git pull && npm ci"   # Every attempt
  after_run: "cleanup..."            # Best-effort
  before_remove: "archive..."        # Best-effort
  timeout_ms: 60000
```

### Dynamic Reload

`WORKFLOW.md` is file-watched; changes to poll interval, concurrency, hooks, prompt, and codex settings apply to future dispatches without restart. Invalid reloads keep last-known-good config.

---

## Demarch Equivalence Map

| Symphony Concept | Demarch Equivalent | Status |
|------------------|--------------------|--------|
| Issue tracker polling | `bd ready` / `bd list` via discovery scanner | Exists (lib-discovery.sh) |
| Linear adapter | Beads (native); no external tracker adapter | **Gap**: iv-sym02 proposes this |
| Orchestrator state machine | `ic dispatch` + `ic run` (SQLite-backed) | Exists but durable, not in-memory |
| Concurrency control | `ic dispatch --max-concurrent` | Exists |
| Per-issue workspace isolation | Single repo, claim-based logical isolation | **Gap**: iv-sym05 proposes worktrees |
| Workspace hooks | Claude Code hooks (SessionStart, PostToolUse, etc.) | Exists (different model) |
| `WORKFLOW.md` (prompt + config) | CLAUDE.md + SKILL.md + AGENTS.md | Exists (distributed, not unified) |
| Retry with backoff | `ic dispatch` has retry logic | Exists but iv-sym03 proposes enhancement |
| Stall detection | Bead claim heartbeat + `claimed_at` freshness | Exists (45-min window) |
| Agent runner (Codex app-server) | Claude Code subprocess (`claude --dangerously-skip-permissions`) | Exists |
| Token accounting | interstat hooks + `ic session` + `ic cost` | Exists (richer) |
| Dynamic config reload | No live reload; session-scoped config | **Gap**: not needed (sessions are ephemeral) |
| Status surface / dashboard | `bd stats`, `/clavain:sprint-status`, `/internext:next-work` | Exists (CLI-only) |
| Prompt template (Liquid) | Skill SKILL.md with argument interpolation | Exists (different mechanism) |

---

## Key Design Differences

### 1. Stateless vs Durable Orchestrator

Symphony intentionally has **no persistent database**. On restart, it re-polls the tracker and re-discovers workspaces. Demarch's intercore uses **durable SQLite** (`dispatches`, `runs`, `sessions`, `phase_events`) to maintain history, cost attribution, and audit trails.

**Assessment:** Symphony's approach is simpler to operate (no migration, no corruption risk) but loses history on restart. Demarch's durable state is essential for cost tracking, landed-change correlation, and the interspect feedback loop. **Skip** — the stateless model is a deliberate simplification that would regress Demarch's observability.

### 2. External Tracker as Source of Truth vs Native Beads

Symphony treats Linear as the authoritative work source. The orchestrator only reads; the agent writes. Demarch owns its tracker (beads) and treats external trackers as optional sync targets.

**Assessment:** Symphony's read-only tracker contract is clean but means the orchestrator has no control over issue lifecycle — it can't close stale beads, create child tasks, or manage dependencies. Demarch needs tracker control for the discovery pipeline, cascade-close, and dependency leverage scoring. **Skip** the read-only model. **Adapt** the external tracker adapter idea (iv-sym02) as an optional beads sync layer.

### 3. Per-Issue Workspace Isolation

Symphony creates a physical directory per ticket (`<root>/<sanitized_identifier>`), persists it across retries, and cleans it when the issue reaches terminal state. This provides true filesystem isolation between concurrent agents.

**Assessment:** Demarch currently runs all agents in the same repo with claim-based coordination (interlock). Physical workspace isolation would eliminate claim conflicts entirely and enable true parallel execution. **Adopt** — iv-sym05 (git worktree per task) is the right vehicle. Symphony's workspace manager patterns (sanitized keys, hook lifecycle, root containment validation) are directly portable.

### 4. WORKFLOW.md Unified Config

Symphony puts prompt template, runtime settings, hooks, and tracker config in a single versioned file. This is elegant for teams that want to version their agent behavior with their code.

**Assessment:** Demarch already distributes this across CLAUDE.md (behavior), SKILL.md (prompts), hooks.json (hooks), and AGENTS.md (architecture). The unified file is simpler but less composable — Demarch's plugin system needs per-plugin config, not a monolithic workflow file. **Skip** the unified file format. **Inspire-from** the dynamic reload pattern if Demarch ever needs live hook reconfiguration.

### 5. Multi-Turn Continuation Within a Worker

Symphony's agent runner supports up to `max_turns` per worker session, re-checking tracker state between turns. Continuation turns send guidance, not the full prompt. This avoids session setup overhead for iterative work.

**Assessment:** Demarch's Clavain sprint workflow already handles multi-phase execution (brainstorm -> strategy -> plan -> execute -> review -> ship) within a single Claude Code session. The explicit `max_turns` cap with inter-turn state refresh is a useful safety pattern. **Adapt** — the cap-and-refresh pattern could be added to `ic dispatch` to prevent runaway agents.

---

## Adopt / Adapt / Skip Verdicts

### Adopt

| Pattern | Target | Why |
|---------|--------|-----|
| **Workspace isolation via git worktree** | iv-sym05 | Eliminates claim conflicts, enables true parallelism. Symphony's sanitized workspace keys, root containment validation, and hook lifecycle are directly portable. |
| **Exponential backoff with capped retry** | iv-sym03 | `min(10s * 2^(attempt-1), max_backoff)` is a clean formula. Demarch's retry logic exists but lacks backoff cap configuration. |
| **Stall detection as reconciliation** | intercore | Kill + retry on inactivity timeout. Demarch's heartbeat model (45-min claimed_at window) is similar but coarser; per-agent event-based stall detection is tighter. |
| **Workspace lifecycle hooks** (after_create, before_run, after_run, before_remove) | iv-sym08 | Clean separation of concerns. Demarch has session-level hooks but no workspace-level hooks. The 4-hook model with failure semantics (fatal vs best-effort) is well-designed. |

### Adapt

| Pattern | Target | How to adapt |
|---------|--------|--------------|
| **External issue tracker adapter** | iv-sym02 | Don't replace beads with Linear; add an optional sync layer that imports from Linear/GitHub Issues into beads. The adapter interface (fetch_candidates, fetch_states_by_ids) is clean. |
| **Dispatch-level retry with backoff** | iv-sym03 | Add `max_retry_backoff_ms` to `ic dispatch` config. Use Symphony's formula but integrate with intercore's durable retry tracking (not in-memory). |
| **Continuous dispatch daemon mode** | iv-sym04 | Symphony's poll-dispatch-reconcile loop is the right shape. Adapt to a long-running `ic daemon` that watches beads instead of Linear. Must be durable (intercore SQLite), not in-memory. |
| **Turn cap with inter-turn state refresh** | iv-sym06 | Add `max_turns` to Clavain sprint config. Between turns, refresh bead state and check for cancellation/priority changes. Adapt the continuation guidance pattern (don't re-render full prompt). |
| **Harness engineering audit** | iv-sym07 | Symphony's Section 15.5 harness hardening guidance is a good checklist. Adapt into a pre-dispatch health check: verify repo state, check for uncommitted changes, validate CLAUDE.md exists, ensure hooks are registered. |

### Skip

| Pattern | Why skip |
|---------|----------|
| **Stateless in-memory orchestrator** | Demarch needs durable state for cost attribution, landed-change correlation, and interspect feedback loops. Symphony's restart-from-tracker model would lose this. |
| **Unified WORKFLOW.md config file** | Demarch's distributed config (CLAUDE.md + SKILL.md + hooks.json + AGENTS.md) is more composable for a plugin ecosystem. Monolithic config doesn't scale to 49 plugins. |
| **Linear as sole tracker** | Beads is the native tracker; Linear/GitHub are optional sync targets, not primary sources. |
| **Read-only tracker contract** | Demarch needs tracker writes for discovery pipeline (bd create, bd close), cascade-close, and dependency management. |
| **Codex app-server protocol** | Demarch uses Claude Code's native subprocess model, which is simpler (no JSON-RPC handshake). The app-server protocol is Codex-specific. |
| **Dynamic config file watching** | Claude Code sessions are ephemeral (minutes to hours). Live reload within a session adds complexity for minimal benefit. |

---

## Dependency Unblocking

This assessment enables concrete scoping for the 7 downstream beads:

| Bead | Verdict | Scope from spec |
|------|---------|-----------------|
| iv-sym02 | Adapt | Adapter interface: `fetch_candidates()`, `fetch_states_by_ids()`, `fetch_by_states()`. Normalize to beads issue model. |
| iv-sym03 | Adopt | `min(10s * 2^(attempt-1), config.max_retry_backoff_ms)` in `ic dispatch`. Continuation retry = 1s fixed. |
| iv-sym04 | Adapt | Poll-dispatch-reconcile loop as `ic daemon`. Durable state, not in-memory. Watch beads, not Linear. |
| iv-sym05 | Adopt | `git worktree add` per bead. Sanitize workspace key from bead ID. Root containment validation. 4 hooks. |
| iv-sym06 | Adapt | `max_turns` cap + inter-turn bead state refresh. Budget enforcement from interstat. |
| iv-sym07 | Adapt | Pre-dispatch health gate: repo clean, CLAUDE.md exists, hooks registered, no zombie processes. |
| iv-sym08 | Adopt | Hook lifecycle: after_create (fatal), before_run (fatal), after_run (best-effort), before_remove (best-effort). Timeout per hook. |

---

## Verdict: `adapt-selectively`

**Rationale:** Symphony's spec is well-engineered and covers orchestration concerns comprehensively. However, Demarch already has most of the equivalent infrastructure across intercore + Clavain + interstat, and three of Symphony's core design bets (stateless orchestrator, external tracker as truth, unified config file) conflict with Demarch's architecture. The valuable patterns to adopt are workspace isolation (worktrees), exponential retry backoff, workspace lifecycle hooks, and stall detection — all of which map cleanly to existing Demarch beads (iv-sym03, iv-sym05, iv-sym08). The adapter interface for external trackers (iv-sym02) is worth building as an optional sync layer, not a primary work source.
