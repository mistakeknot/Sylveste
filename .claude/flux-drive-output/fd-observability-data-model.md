# Flux Drive Review: Observability Data Model

**Reviewer:** fd-observability-data-model
**Date:** 2026-03-14
**Source:** `research/agi-hyperspace/ANALYSIS.md`, `research/agi-hyperspace/README.md`, `research/agi-hyperspace/.github/scripts/build-leaderboard.js`
**Codebase explored:** interlab, interstat, intersearch, Intercom, Autarch, beads backup, cass integration

---

## 1. Per-Agent Experiment Format: Designing Sylveste's Equivalent

### Hyperspace Pattern

```
projects/<project>/agents/<peerId>/
  run-0001.json    # Machine-readable results
  run-0001.md      # Human-readable report
  best.json        # Current personal best
  JOURNAL.md       # Cognitive journal
```

Each `run-NNN.json` is a self-contained record with `result.valLoss`, `hypothesis`, `runNumber`, `gpu`, `timestamp`. The `best.json` is the current winner. The `build-leaderboard.js` script (139 lines, zero external deps) scans all agent branches, reads `best.json` from each, sorts by project-specific metric extractor, and emits markdown.

### What Sylveste Already Has

Interlab's JSONL (`interverse/interlab/internal/experiment/state.go`) stores a **Config header** followed by **Result entries** in a single append-only file:

```go
// Config: type, name, metric_name, direction, benchmark_command, ...
// Result: type, decision, description, metric_value, duration_ms, exit_code, secondary_metrics, commit_hash, timestamp
```

This is a compact, crash-recoverable format that `ReconstructState()` replays from scratch on each call. The multi-campaign layer (`internal/orchestration/synthesize.go`) produces a `SynthesisReport` with per-campaign `CampaignSummary` objects and aggregate insights. Completed campaigns archive to `campaigns/<name>/results.jsonl` + `learnings.md`.

The interstat pipeline (`interverse/interstat/scripts/cost-query.sh`) produces JSON output for 10 query modes (aggregate, by-bead, by-phase, baseline, cost-snapshot, etc.) against a SQLite DB at `~/.claude/interstat/metrics.db`.

### Gap Analysis

Interlab's JSONL is **campaign-scoped** (one file per optimization run), not **work-item-scoped**. There is no equivalent of Hyperspace's `run-NNN.json` as a standalone, self-describing record of a single unit of agent work. Beads (`issues.jsonl`) track work items but contain no execution telemetry (tokens, duration, metrics). Interstat has execution telemetry but is session-scoped, not bead-scoped (the `bead_id` column exists but is sparsely populated).

### Recommendation: P1 — Sylveste Experiment Record Schema

Define a unified "work record" format that bridges beads (what was done) with interstat (what it cost) and interlab (what it measured). This is the Sylveste equivalent of `run-NNN.json`.

**Proposed schema** (`work-record.json`):

```json
{
  "version": 1,
  "bead_id": "Sylveste-05kd",
  "session_id": "2f47757d-c465-4865-af26-0a9911d43f5e",
  "agent": "claude-opus-4-6",
  "timestamp": "2026-03-14T04:18:27Z",
  "duration_s": 342,
  "outcome": "closed",
  "close_reason": "Implemented snapshot validation CI",

  "cost": {
    "total_tokens": 48000,
    "input_tokens": 35000,
    "output_tokens": 13000,
    "usd": 1.42,
    "model_breakdown": {
      "claude-opus-4-6": { "input": 35000, "output": 13000, "usd": 1.42 }
    }
  },

  "artifacts": {
    "commits": ["abc1234", "def5678"],
    "files_changed": 4,
    "lines_added": 120,
    "lines_removed": 15,
    "tests_added": 3
  },

  "experiment": {
    "metric_name": "reconstruct_100_ns",
    "direction": "lower_is_better",
    "baseline": 1540000,
    "result": 68000,
    "improvement_pct": 95.6,
    "run_count": 8,
    "kept_count": 6
  },

  "context": {
    "sprint_id": "sprint-2026w11",
    "parent_bead": "Sylveste-85k",
    "discovered_from": null,
    "complexity": 2,
    "priority": 2,
    "issue_type": "task"
  }
}
```

**Implementation path:**
1. Interstat's `cost-snapshot` mode already produces per-bead cost JSON -- this becomes `cost`
2. Interlab's `CampaignSummary` struct already has the fields for `experiment`
3. Beads JSONL already has all `context` fields
4. A 50-line bash script could join these three sources into the work-record on `bd close`

**Where it lives:** `.beads/records/<bead_id>.json` -- one file per closed bead. Machine-readable, queryable, archivable. The `best.json` equivalent is `bd list --status=closed --sort-by=cost --json | head -1`.

---

## 2. Hourly Snapshot Pattern vs. Complex Beads Dashboards

### Hyperspace Pattern

Every hour, a node publishes `snapshots/latest.json` -- the full CRDT leaderboard state. The README says: *"Point any LLM at that URL and ask it to analyze. No narrative, no spin."* This is 47 lines of JSON (summary, per-domain leaderboards, experiment counts, timestamp, disclaimer).

### What Sylveste Already Has

Beads backup (`.beads/backup/`) produces JSONL exports of issues (952 records, 1.1MB), events (2007 records, 512KB), dependencies (514 records), and labels (302 records). The `backup_state.json` records the last Dolt commit hash, event ID, timestamp, and counts.

Interstat's `cost-query.sh baseline` produces a structured JSON snapshot:
```json
{
  "measurement_window": { "first_session": "...", "last_session": "...", "sessions": N },
  "tokens": { "total": N, "input": N, "output": N },
  "cost_usd": N,
  "landed_changes": { "count": N, "source": "ic_landed|git_log_fallback" },
  "north_star": { "tokens_per_landable_change": N, "usd_per_landable_change": N }
}
```

Intercom's `SylvesteAdapter` (`apps/Intercom/rust/intercom-core/src/sylveste.rs`) supports read operations: `RunStatus`, `SprintPhase`, `SearchBeads`, `NextWork`, `RunEvents`, `RunTokens`, `DispatchList`. These are already structured queries that return JSON.

### Assessment

The beads JSONL backup is **close to a snapshot but not quite**. It is a full dump rather than a summary. An LLM pointed at 1.1MB of issues JSONL would burn tokens without proportional insight. What is needed is a **derived summary** -- the equivalent of Hyperspace's 47-line `latest.json`.

### Recommendation: P0 — `bd snapshot --json` Summary Format

**Verdict: This would replace complex beads dashboards.** The snapshot should aggregate, not dump.

**Proposed schema** (`snapshot.json`):

```json
{
  "version": 1,
  "timestamp": "2026-03-14T12:00:00Z",
  "generated_by": "bd snapshot --json",

  "counts": {
    "total": 952,
    "open": 208,
    "in_progress": 12,
    "closed": 732,
    "blocked": 4
  },

  "velocity": {
    "closed_last_7d": 47,
    "closed_last_24h": 8,
    "avg_close_time_hours": 3.2,
    "cost_per_change_usd": 1.17
  },

  "active_agents": [
    { "session_id": "2f47757d", "bead_id": "Sylveste-05kd", "claimed_at": "2026-03-14T04:24:19Z", "title": "Snapshot validation CI" }
  ],

  "blockers": [
    { "bead_id": "Sylveste-0ox", "title": "Discovery evaluation dashboard", "blocked_by": "Sylveste-xyz" }
  ],

  "top_cost_beads_7d": [
    { "bead_id": "Sylveste-0pj", "title": "F4: Model routing", "cost_usd": 4.20, "tokens": 180000 }
  ],

  "experiment_campaigns": {
    "active": 0,
    "completed": 1,
    "best_improvement": { "campaign": "interlab-reconstruct-speed", "improvement_pct": 95.6 }
  }
}
```

**Why this beats dashboards:** A single JSON file that any LLM can analyze produces answers to "what's happening?", "what's blocked?", "where are we spending money?" in one call. Building a dashboard for these questions takes weeks; generating this JSON takes minutes.

**Implementation:** Compose from existing sources:
- `bd list --json` for counts and status
- `bd list --status=in_progress --json` for active agents
- `cost-query.sh baseline` for velocity/cost
- `interlab status_campaigns` for experiment data
- A cron job or SessionStart hook writes `snapshot.json` to `.beads/snapshots/latest.json`

---

## 3. Auto-Generated Leaderboard as Sprint Retrospective Template

### Hyperspace Pattern

`build-leaderboard.js` (at `research/agi-hyperspace/.github/scripts/build-leaderboard.js`) is 139 lines of Node.js with zero dependencies. It:
1. Discovers projects from `projects/` directory
2. Reads `best.json` from each agent branch via `git show`
3. Sorts by project-specific metric extractor (7 project configs)
4. Emits a markdown table per project
5. Runs on a GitHub Actions cron every 6 hours

Key design decisions: metric extractors are configured per-project as `{ field, label, dir, fmt, extract }` objects. The `extract` function handles multiple JSON shapes gracefully (`d.result?.valLoss ?? d.valLoss ?? Infinity`). The output format is deliberately simple -- rank, agent, metric, hypothesis, runs, GPU, last updated.

### What Intercom Could Use

Intercom's `sylveste-query.sh` (`apps/Intercom/container/shared/sylveste-query.sh`) already supports `search_beads`, `run_status`, `sprint_phase`, `run_events`, and `next_work` queries. The vision doc (`apps/Intercom/docs/intercom-vision.md`) explicitly calls out "sprint retro that writes itself" as a goal for Horizon 1.

Intercom's Rust EventConsumer (`apps/Intercom/rust/intercomd/src/events.rs`) already polls kernel events and sends Telegram notifications. Adding a periodic summary message would fit naturally in the same pattern.

### Recommendation: P1 — Beads Report Generator (NOT a Leaderboard)

**Verdict: Do NOT implement a leaderboard generator for Intercom.** Hyperspace's leaderboard works because it tracks a single metric per domain across competing agents. Sylveste's agents do heterogeneous work (features, bugs, refactors, research) that cannot be meaningfully ranked on a single axis.

Instead, implement a **periodic summary generator** that produces a sprint retrospective from beads data:

```markdown
## Sprint Report: 2026-W11

**Closed:** 47 beads | **Cost:** $55.00 | **Avg time:** 3.2h

### By Type
| Type | Count | Avg Cost |
|------|-------|----------|
| feature | 12 | $2.10 |
| bug | 18 | $0.80 |
| task | 15 | $0.60 |
| chore | 2 | $0.30 |

### Notable Completions
- F4: Model routing + budget tracking ($4.20, 3h)
- Audit shadow bet resolution timeline ($0.90, 15m)

### Cost Outliers (>2x avg)
- Sylveste-0pj: F4 Model routing — $4.20 (3.6x avg)

### Experiments
- interlab-reconstruct-speed: -96% (22x faster)
```

**Implementation:** A single script (bash or Go) that:
1. Runs `bd list --status=closed --since=<sprint_start> --json`
2. Runs `cost-query.sh by-bead --since=<sprint_start>`
3. Joins on bead_id
4. Emits markdown
5. Optionally sends via Intercom's `TelegramBridge`

Estimated size: ~100 lines. No new infrastructure needed. Could run as a SessionStart hook, a scheduled task in Intercom, or a standalone script.

---

## 4. Living Research Repository for Autarch's Agent Activity Feed

### Hyperspace Pattern

The README embeds live network data at the top: *"67 agents, 1,369 experiments, 5 domains active"*. The overnight research report shows what agents did while no human was watching. Each agent has a browsable history via git branches.

### What Autarch Already Has

Autarch (`apps/Autarch/`) has five tools:
- **Bigend** -- multi-project mission control (web + TUI), already renders kernel state
- **Coldwine** -- task orchestration with `.coldwine/state.db`
- **Mycroft** -- fleet orchestrator with `.autarch/mycroft/decisions.db`, escalating autonomy tiers

Mycroft specifically tracks dispatch decisions in SQLite and has a `status` command showing fleet state and current tier. This is architecturally similar to the Hyperspace overnight report but scoped to fleet management rather than research output.

### Recommendation: P2 — Autarch Activity Feed from Snapshot + Work Records

**Verdict: Adopt the pattern, but derive from existing data rather than building a new system.**

The "living research repository" pattern maps to Autarch as follows:
- Hyperspace's `snapshots/latest.json` -> `bd snapshot --json` (from recommendation #2)
- Hyperspace's per-agent `run-NNN.json` -> per-bead `work-record.json` (from recommendation #1)
- Hyperspace's `LEADERBOARD.md` -> sprint report (from recommendation #3)
- Hyperspace's per-agent `JOURNAL.md` -> cass session export per-agent (already exists)

Bigend's web dashboard could consume `snapshot.json` directly. Mycroft's `status` command could include the last N closed beads with cost data. No new data pipeline needed -- just aggregation of work-records and snapshots into existing surfaces.

The key insight from Hyperspace is that the README itself is the dashboard. For Autarch, the equivalent is a generated `STATUS.md` or `/autarch status` command that reads from the same `snapshot.json`.

---

## 5. "Point Any LLM at snapshots/latest.json" UX Philosophy

### Hyperspace's Approach

Hyperspace explicitly designs for LLM consumption. The snapshot includes a `disclaimer` field. The README instructs: *"Point any LLM at that URL and ask it to analyze."* The data is raw and uninterpreted.

### Sylveste's Current Approach

Sylveste's observability is tool-specific and fragmented:

| Data Source | Format | Query Interface | LLM-Friendly? |
|-------------|--------|-----------------|----------------|
| Beads (`issues.jsonl`) | JSONL, 1.1MB | `bd list --json`, `bd search` | Too large for raw ingestion |
| Interstat (`metrics.db`) | SQLite | `cost-query.sh` (10 modes, JSON out) | Yes -- each mode outputs focused JSON |
| Interlab (`interlab.jsonl`) | JSONL, per-campaign | `ReconstructState()`, `status_campaigns` | Compact, LLM-friendly |
| Cass | SQLite | `cass search --robot`, `cass timeline --json` | Yes -- `--robot` mode designed for machine parsing |
| Intercom events | Postgres | `SylvesteAdapter::ReadOperation` | Via IPC only, not file-based |
| Mycroft decisions | SQLite | `mycroft status` | CLI output, not JSON |

### Assessment

Sylveste **already produces LLM-friendly JSON** from interstat and cass. The gap is consolidation -- there is no single file a user can point to and say "analyze my dev agency." The beads backup is too large (1.1MB raw JSONL). The interstat output is too narrow (only tokens/cost).

### Recommendation: P0 — Consolidated Snapshot as the Single LLM Entry Point

The `snapshot.json` from recommendation #2 IS this entry point. The additional design requirement: **it must fit in a single LLM context window without truncation.** Target: <10KB.

The Hyperspace `latest.json` works because it is a summary, not a dump. Sylveste's equivalent must similarly summarize:
- 952 beads -> 5 status counts + top-5 active + top-5 blockers
- 200+ sessions -> 3 velocity metrics
- Hundreds of interstat rows -> 1 north-star cost metric + 3 model-level breakdowns
- Multiple campaigns -> 1 aggregate experiment status

The key architectural decision: **snapshot generation is a write-time operation, not a read-time query.** Generate on cron (hourly or on session-start), write to `.beads/snapshots/latest.json`, commit to git. Any LLM -- Intercom's container agents, Autarch's TUI, external analysis -- reads the same file.

**Existing tools that already produce snapshot-friendly JSON:**
1. `cost-query.sh baseline` -- north star metrics (tokens, cost, velocity)
2. `cost-query.sh cost-usd` -- per-model cost breakdown
3. `cass analytics tokens --json` -- cross-agent token analytics
4. `cass stats --json` -- session statistics
5. `bd list --status=in_progress --json` -- active work

A composer script joining these five outputs produces the snapshot. Estimated: 40 lines of bash.

---

## 6. Per-Agent Git Branch Archive for Skaffen Instances

### Hyperspace Pattern

Each agent gets its own git branch: `agents/<peerId>/<project>`. Never merged to main. Creates browsable history per agent, with experiment files as commits.

### What Sylveste Already Has

Interlab already creates experiment branches (`interlab/<name>`) as a documented exception to trunk-based development (per `interverse/interlab/CLAUDE.md`). Clavain worktrees provide per-agent filesystem isolation. Beads tracks `created_by` (session ID prefix) and `assignee` per issue, plus `claimed_by` via `bd set-state`.

### Recommendation: P3 — Do NOT Adopt Per-Agent Branches

**Verdict: This pattern does not fit Sylveste's architecture.** Here is why:

1. **Sylveste uses trunk-based development.** Per-agent branches contradict this fundamental decision. Interlab's exception is narrow (experiment isolation only) and already causes friction.

2. **Agents modify the same files.** Hyperspace agents work on independent experiment configs. Sylveste agents work on shared codebases where branch isolation would create merge conflicts.

3. **The browsable history need is already met.** `cass context <path> --json` shows which sessions touched a file. `bd list --assignee=<session_prefix> --json` shows what each agent worked on. `git log --author=<email>` provides per-agent commit history on trunk.

4. **The archival need is better served by work-records.** Per-bead `work-record.json` files (recommendation #1) provide the same browsable, machine-readable history that Hyperspace's per-agent branches provide, without the git complexity.

The one valuable sub-pattern: **agent identity in commit metadata.** Interlab already includes `Bead-ID` in git trailers. Adding `Agent-Session: <session_id>` as a trailer would make `git log` queries by agent trivial without requiring branches.

---

## Summary Table

| # | Recommendation | Priority | Effort | Existing Foundation |
|---|---------------|----------|--------|-------------------|
| 1 | Per-bead work-record JSON schema | P1 | ~50 lines bash | interstat `cost-snapshot`, interlab `CampaignSummary`, beads JSONL |
| 2 | `bd snapshot --json` summary format | P0 | ~40 lines bash | `cost-query.sh baseline`, `bd list --json`, beads backup |
| 3 | Sprint report generator (NOT leaderboard) | P1 | ~100 lines bash | `cost-query.sh by-bead`, `bd list --json` |
| 4 | Autarch activity feed from snapshots | P2 | Integration work | Bigend web, Mycroft status, snapshot.json |
| 5 | Consolidated snapshot as LLM entry point | P0 | Same as #2 | 5 existing JSON-producing tools |
| 6 | Per-agent git branches | P3 (reject) | N/A | cass context, bd list by assignee |

## Key Finding

Sylveste's observability infrastructure is **more capable than it appears** -- interstat, cass, interlab, and beads all produce structured JSON. The missing piece is not data collection but **data consolidation.** A single snapshot composer script (40-50 lines) that joins existing tool outputs would deliver 80% of the Hyperspace observability UX with near-zero new infrastructure.

The Hyperspace insight worth internalizing: **structured data + LLM analysis beats hand-built dashboards.** Sylveste should resist building Bigend dashboard widgets for sprint velocity, cost trends, and agent activity. Instead, generate `snapshot.json` and let LLMs (including Intercom's agents) interpret it on demand.
