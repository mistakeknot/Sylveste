# Ockham Algedonic Signal Design — Repo Research

## Sources

- `/home/mk/projects/Sylveste/os/Ockham/AGENTS.md` — architecture overview, package map, planned CLI
- `/home/mk/projects/Sylveste/os/Ockham/CLAUDE.md` — four subsystems, autonomy ratchet summary
- `/home/mk/projects/Sylveste/os/Ockham/docs/HANDOFF.md` — current scaffold state (all internal packages empty)
- `/home/mk/projects/Sylveste/os/Clavain/hooks/lib-dispatch.sh` — dispatch scoring, circuit breaker, cap, lane pause
- `/home/mk/projects/Sylveste/os/Clavain/hooks/lib-recovery.sh` — quarantine model, failure classification
- `/home/mk/projects/Sylveste/os/Clavain/hooks/lib-intercore.sh` — state read/write API (`ic state get/set`)
- `/home/mk/projects/Sylveste/os/Clavain/hooks/auto-stop-actions.sh` — dispatch trigger, factory-paused check
- `/home/mk/projects/Sylveste/os/Clavain/cmd/clavain-cli/watchdog.go` — factory-pause and agent-pause file writers
- `/home/mk/projects/Sylveste/os/Clavain/cmd/clavain-cli/intent.go` — `clavain-cli intent submit` contract
- `/home/mk/projects/Sylveste/os/Clavain/commands/sprint.md` — `autonomy_tier` bead state field
- `/home/mk/projects/Sylveste/interverse/interphase/hooks/lib-discovery.sh` — `score_bead()` formula
- `/home/mk/projects/Sylveste/interverse/interspect/hooks/lib-interspect.sh` — SQLite schema, routing overrides
- `/home/mk/projects/Sylveste/interverse/interstat/scripts/cost-query.sh` — interstat query interface
- `/home/mk/projects/Sylveste/os/Alwe/internal/observer/cass.go` — CASS query surface
- `/home/mk/projects/Sylveste/os/Alwe/AGENTS.md` — MCP tools exposed by Alwe

---

## Findings

### 1. Input Surface: What Ockham Can Observe

#### 1a. Beads State

The `bd` CLI is the primary query interface. The following queries are directly usable today:

| Query | Algedonic signal type |
|-------|----------------------|
| `bd list --status=blocked --label=quarantine:needs-human` | Pain — beads quarantined by the watchdog after max retries |
| `bd list --status=blocked --label=quarantine:needs-infra` | Pain — env-blocked beads needing SRE fix |
| `bd list --status=in_progress --json` | Observation — WIP count, assignees, stale claims |
| `bd list --status=open --label=needs-review` | Pain — review queue depth (drives backpressure) |
| `bd dep list <id> --direction=down --json` | Structural — unsatisfied dependencies |
| `bd state <id> claimed_at` | Staleness detection — epoch of last claim heartbeat |
| `bd state <id> claimed_by` | Owner identity — `released` sentinel = unclaimed |
| `bd state <id> autonomy_tier` | Per-bead autonomy override (1/2/3) |
| `bd state <id> ic_run_id` | Links bead to intercore run for phase queries |
| `bd stats` | Aggregate counts — open/in_progress/closed |

Stale claim detection: `lib-recovery.sh` uses `RECOVERY_STALE_TTL` (default 600s). Ockham reads staleness the same way: compare `claimed_at` epoch to `$(date +%s)`.

Quarantine labels applied by `recovery_quarantine_bead()`:
- `quarantine:needs-human` (spec-blocked failures)
- `quarantine:needs-infra` (env-blocked failures)

Quarantined bead status is set to `blocked` via `bd update --status=blocked`.

#### 1b. Interspect Evidence

Database: `.clavain/interspect/interspect.db` (SQLite, WAL mode).

Key tables and queryable signals:

**`evidence` table** — agent override events:
```sql
-- Count overrides by agent in last N days
SELECT source, event, override_reason, COUNT(*) as n
FROM evidence
WHERE event IN ('override', 'disagreement_override')
  AND COALESCE(quarantine_until, 0) <= strftime('%s','now')
GROUP BY source, override_reason
ORDER BY n DESC;

-- Agents with high wrong rate (pain: systematic miscalibration)
SELECT source,
  COUNT(*) as total,
  SUM(CASE WHEN override_reason = 'agent_wrong' THEN 1 ELSE 0 END) as wrong,
  ROUND(100.0 * SUM(CASE WHEN override_reason = 'agent_wrong' THEN 1 ELSE 0 END) / COUNT(*), 1) as pct
FROM evidence
WHERE event = 'override'
  AND COALESCE(quarantine_until, 0) <= strftime('%s','now')
GROUP BY source
HAVING total >= 5;
```

**`canary` table** — active routing override monitoring:
```sql
-- Active canaries in alert state (pain: override regression)
SELECT file, status, uses_so_far, window_uses, baseline_override_rate
FROM canary WHERE status = 'alert';

-- Circuit-breaker-tripped targets
SELECT target_file, COUNT(*) as reverts
FROM modifications
WHERE mod_type = 'revert' AND ts > datetime('now', '-30 days')
GROUP BY target_file;
```

**`modifications` table** — applied routing overrides with commit SHA.

**`sentinels` table** — TTL-cached system breaker state (key/value).

Event types in `evidence.event`:
- `override` — human corrected an agent
- `disagreement_override` — disagreement pipeline detected correction
- `review_phase_outcome` — per-phase review result (tier-skip calibration data)

The `_interspect_get_routing_eligible()` and `_interspect_get_overlay_eligible()` shell functions in `lib-interspect.sh` implement the full classification pipeline. Ockham can call these directly or replicate the SQL queries in Go.

#### 1c. Interstat Metrics

Database: `~/.claude/interstat/metrics.db` (SQLite).

Cross-layer interface: `interverse/interstat/scripts/cost-query.sh`. All modes output JSON.

Key queries for Ockham:

| Mode | Signal |
|------|--------|
| `cost-query.sh aggregate` | Total tokens by agent type (pleasure: low = efficient) |
| `cost-query.sh by-bead` | Per-bead token cost (pain: outlier beads) |
| `cost-query.sh baseline` | North star: USD/landable-change (pleasure: decreasing trend) |
| `cost-query.sh effectiveness` | Per-agent avg cost ranked (pleasure: high value agents) |
| `cost-query.sh session-cost --session=<id>` | Real-time cost for a session |

The `agent_runs` table schema: `session_id`, `bead_id`, `phase`, `model`, `agent_name`, `subagent_type`, `input_tokens`, `output_tokens`, `total_tokens`, `timestamp`.

Note from MEMORY.md: `subagent_type` column is empty in production data — `agent_name` is the reliable field.

#### 1d. Clavain Dispatch State

All dispatch state lives in the intercore state store, scoped to `session_id`. Ockham reads it via `ic state get <key> <session_id>`.

| Key | Format | Meaning |
|-----|--------|---------|
| `dispatch_count` | `{"count": N}` | Dispatches used this session |
| `dispatch_failures` | `{"count": N}` | Consecutive infra failures (circuit breaker) |

Circuit breaker trips at `DISPATCH_CIRCUIT_THRESHOLD = 3` consecutive failures.
Dispatch cap default: `CLAVAIN_DISPATCH_CAP=5` per session (env-overridable).

Factory-level pause state (checked by `auto-stop-actions.sh` before dispatching):
- `~/.clavain/factory-paused.json` — global factory pause (written by `pauseFactory()`)
- `~/.clavain/paused-agents/<session_id>.json` — per-agent pause (written by `pauseAgentDispatch()`)

Both files are written by `clavain-cli watchdog` and checked as file existence tests (not intercore state).

Lane pause state: `ic lane status <lane> --json` → `.metadata.paused == "true"`. Lane pauses skip beads with matching `lane:<name>` labels during dispatch rescoring.

Dispatch log (JSONL): `~/.clavain/dispatch-log.jsonl`
- Fields: `ts`, `session`, `bead`, `score`, `outcome`
- Outcome values: `claimed`, `race_lost`, `infra_error`, `no_candidates`, `lane_paused`, `in_the_weeds`, `exhausted`

Recovery log (JSONL): `~/.clavain/recovery-log.jsonl`
- Fields: `ts`, `ts_epoch`, `bead`, `failure_class`, `action`, `reason`

#### 1e. Alwe / CASS

Alwe wraps `cass` CLI and exposes it as either MCP tools or direct CLI commands.

CASS queries available via `alwe` or `cass` directly:

| Query | Signal |
|-------|--------|
| `cass search "<query>" --robot --json --limit N` | Session semantic search |
| `cass context <file_path> --json` | Sessions that touched a file |
| `cass timeline --since 2h --json` | Recent activity across all agents |
| `cass health --json` | CASS availability check |
| `cass analytics tokens/tools/models --json` | Aggregate analytics |

Alwe MCP tools (for programmatic access by Skaffen or Ockham if integrated via MCP):
- `search_sessions` — content search with provider filter
- `context_for_file` — file-centric session history
- `export_session` — session export to markdown
- `timeline` — recent activity
- `health` — availability

Real-time: `TailSession()` polls a JSONL file at 100ms intervals. This enables Ockham to observe a running agent session in near-real-time.

---

### 2. Output Surface: What Ockham Can Influence

#### 2a. Dispatch Weights via `score_bead()` Injection Point

The base scoring formula in `interphase/hooks/lib-discovery.sh::score_bead()`:
```
score = priority_score (0-60) + phase_score (0-30) + recency_score (0-20) - staleness_penalty (10)
```
Max raw score: 110. Range in practice: roughly 5-100.

Ockham's weight multiplier has no defined injection point yet. The dispatch pipeline is:

1. `discovery_scan_beads()` → calls `score_bead()` → JSON array with `score` field
2. `dispatch_rescore()` in `lib-dispatch.sh` → adds perturbation (0-5), subtracts `pressure_penalty`
3. Result sorted by `score DESC` → claim attempted on top candidates

The pressure penalty in `dispatch_rescore()` is additive subtraction: `(review_depth - threshold) * 5`. Ockham's theme-budget weights would slot in at the same layer — a multiplicative modifier on the `score` field before sorting, or an additive term alongside the pressure penalty.

Concrete injection approach (not yet implemented): Ockham writes a per-bead weight multiplier to intercore state:
```bash
ic state set "ockham_weight" "<bead_id>" '{"multiplier": 1.5, "reason": "auth-theme-priority"}'
```
`dispatch_rescore()` reads this and applies it before sorting. The key `ockham_weight` scoped to `bead_id` (rather than `session_id`) would allow cross-session persistence of theme priorities.

Theme-freeze mechanism: setting all beads in a theme's label to multiplier 0 (or 0.01 to preserve ordering signal) would effectively freeze dispatch without removing them from the backlog.

#### 2b. Routing Overrides via Interspect

The routing override file: `.claude/routing-overrides.json` (project-relative, atomic write via temp+rename).

Format (version 1):
```json
{
  "version": 1,
  "overrides": [
    {
      "agent": "fd-safety",
      "action": "exclude",
      "reason": "...",
      "created_by": "interspect",
      "scope": {}
    }
  ]
}
```

Write path: `_interspect_apply_routing_override()` in `lib-interspect.sh` — handles read-modify-write under flock, git commit, and DB record insertion. Ockham can call this function directly (by sourcing `lib-interspect.sh`) or replicate the write pattern in Go.

The `created_by` field accepts any string — Ockham would use `"ockham"`.

Actions: `"exclude"` (remove agent from triage) or `"propose"` (overlay suggestion without exclusion).

Protected paths enforcement: `.clavain/interspect/protected-paths.json` — `_interspect_validate_target()` gates all writes. Ockham must ensure `.claude/routing-overrides.json` is in the allow-list before writing.

Autonomy gate: `_INTERSPECT_AUTONOMY` in `confidence.json` controls whether interspect self-applies or only proposes. Ockham writing a routing override directly bypasses this gate — it must implement its own equivalent autonomy check.

#### 2c. Factory Pause / Agent Pause Levers

These are the most direct and immediately operable outputs:

**Factory-wide pause** (Ockham tier 4 equivalent):
```bash
# Write: pause all dispatch
echo '{"paused_at":'$(date +%s)',"reason":"ockham-circuit-trip","tier":4}' \
  > ~/.clavain/factory-paused.json

# Clear: resume dispatch
rm ~/.clavain/factory-paused.json
```
Already checked by `auto-stop-actions.sh` before dispatching. No code change required.

**Per-agent pause** (Ockham tier 3 equivalent):
```bash
# Write: pause agent SESSION_ID
mkdir -p ~/.clavain/paused-agents
echo '{"agent":"SESSION_ID","paused_at":'$(date +%s)',"reason":"ockham-anomaly"}' \
  > ~/.clavain/paused-agents/<sanitized_session_id>.json

# Clear: resume
rm ~/.clavain/paused-agents/<sanitized_session_id>.json
```
Also checked in `auto-stop-actions.sh` before dispatch.

These two file-presence checks are Ockham's most direct output path. They require zero changes to existing dispatch code.

#### 2d. Lane Pause (Theme Freeze Mechanism)

A lane is a grouping of beads with strategic intent metadata. `dispatch_rescore()` checks `ic lane status <lane> --json` and skips beads with `lane:<name>` labels when `.metadata.paused == "true"`.

To freeze a theme, Ockham:
1. Reads current lane metadata: `ic lane status <lane_name> --json`
2. Appends pause fields: `jq '.metadata + {paused: "true", pause_reason: "ockham-budget-freeze", pause_ts: <epoch>}'`
3. Writes back: `ic lane update <lane_name> --metadata="<json>"`

To unfreeze: `ic lane update <lane_name> --metadata="<json without pause fields>"` (see the `del(.paused, .pause_reason, .pause_bead, .pause_ts)` pattern in `skills/lane/SKILL.md`).

This is the cleanest "freeze a theme" mechanism. It operates at the lane level rather than per-bead, respects existing dispatch infrastructure, and is reversible.

#### 2e. Autonomy Tier Override

The `autonomy_tier` field is read from bead state during sprint execution:
```bash
autonomy_override=$(bd state "$CLAVAIN_BEAD_ID" autonomy_tier 2>/dev/null)
# Values: 1 (full auto), 2 (two checkpoints), 3 (fully interactive)
```

Ockham writes this via:
```bash
bd set-state <bead_id> "autonomy_tier=3"  # demote to shadow/interactive mode
```

This is the "shadow mode" demotion path. Setting `autonomy_tier=3` on a bead forces full human review at every checkpoint without changing dispatch priority or blocking the bead from being claimed.

For Ockham's own autonomy ratchet (shadow/supervised/autonomous), the current codebase has no persisted Ockham-level autonomy mode. This would need a new state key — e.g., `ic state set "ockham_autonomy" "global" '{"mode":"shadow"}'` — not yet implemented.

#### 2f. Intercore Intent Contract

`clavain-cli intent submit` is a typed RPC interface for authoritative actions:

Supported intent types (from `contract` package):
- `IntentSprintAdvance` — advance a sprint to next phase
- `IntentSprintCreate` — create a sprint
- `IntentSprintClaim` — claim a bead
- `IntentSprintRelease` — release a bead claim
- `IntentGateEnforce` — run gate enforcement
- `IntentBudgetCheck` — check token budget

All intents are logged to `intent_events` in the intercore DB. This is the highest-integrity write path — audit-complete and idempotency-keyed.

Ockham would submit intents via:
```bash
echo '{"type":"sprint.release","bead_id":"<id>","session_id":"<sid>","idempotency_key":"<uuid>"}' \
  | clavain-cli intent submit
```

---

### Confidence

**High confidence** (directly observed in source code):
- Beads query surface: `bd list`, `bd show`, `bd state`, `bd dep list` — all in active use
- Dispatch state keys in intercore: `dispatch_count`, `dispatch_failures` — literal strings in `lib-dispatch.sh`
- Quarantine mechanism: labels `quarantine:needs-human` / `quarantine:needs-infra`, status `blocked`
- Factory pause / agent pause: file paths `~/.clavain/factory-paused.json` and `~/.clavain/paused-agents/` checked by `auto-stop-actions.sh`
- Lane pause mechanism: `ic lane update --metadata` pattern, checked in `dispatch_rescore()`
- `autonomy_tier` bead state field: consumed by `sprint.md` and multiple sprint transcripts
- Interspect SQLite schema: `evidence`, `canary`, `modifications`, `sentinels` tables
- Routing override file format: `{"version":1,"overrides":[...]}` at `.claude/routing-overrides.json`
- CASS query surface: `cass search/context/timeline/health` — all implemented in `alwe/internal/observer/cass.go`

**Medium confidence** (design intent clear, no implementation yet):
- Ockham weight multiplier injection into `dispatch_rescore()` — the slot exists (pressure penalty pattern), but no `ockham_weight` key or read-side code exists
- Ockham-level autonomy mode persistence (`ockham_autonomy` state key) — mentioned in AGENTS.md design, no implementation
- Ockham writing routing overrides directly — the write path exists in `lib-interspect.sh`, but Ockham has no Go implementation of it yet

**Low confidence** (architecture mentioned, no code):
- All four Ockham internal packages (`internal/intent`, `internal/authority`, `internal/anomaly`, `internal/dispatch`) are **empty directories** — the scaffold exists but zero Go files are present
- The `ockham intent` CLI planned in AGENTS.md does not exist yet

---

### Gaps

1. **Dispatch weight injection is unimplemented.** `dispatch_rescore()` has no `ockham_weight` read. Ockham has no way to influence bead scoring today without modifying `lib-dispatch.sh`. The most natural insertion point is after the lane-pause check and before the perturbation addition, applying a multiplier from `ic state get "ockham_weight" <bead_id>`.

2. **No Ockham-to-interspect write bridge in Go.** Routing override writes are implemented entirely in bash (`lib-interspect.sh`). Ockham (Go) would need to either shell out to a helper script or reimplement the write+flock+git+DB pattern in Go. The bash path is the path of least resistance for a prototype.

3. **No Ockham autonomy mode persisted.** The shadow/supervised/autonomous ratchet described in AGENTS.md has no storage layer. Intercore state is the natural home (`ic state set "ockham_autonomy" "global" '{"mode":"shadow"}'`), but nothing reads it yet.

4. **CASS timeline data has no bead correlation.** `cass timeline --json` shows agent activity but does not include `bead_id`. Correlating session history to beads requires a join against interstat (`session_id` → `bead_id` via `agent_runs.bead_id`) or reading `bd state <id> claimed_by` against known session IDs.

5. **Dispatch log is not queryable by Ockham at design time.** `~/.clavain/dispatch-log.jsonl` accumulates dispatch outcomes but has no index or query interface. Ockham needs to parse JSONL directly. A `jq -c 'select(.outcome == "infra_error")'` scan on this file is the immediate path.

6. **`subagent_type` column in interstat is empty in production.** Cost attribution to specific flux-drive agents requires using `agent_name` (which uses interflux prefix format: `interflux:fd-safety`) not `subagent_type`.

7. **Lane velocity data.** `ic lane velocity --json` is referenced in the lane skill but its output schema is undocumented in the sources reviewed. This would provide throughput-per-lane data useful for pleasure signals (improving cycle time per theme).
