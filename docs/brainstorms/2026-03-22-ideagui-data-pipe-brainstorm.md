---
artifact_type: brainstorm
bead: Demarch-ef08
stage: discover
---

# IdeaGUI Data Pipe for Meadowsyn (F1)

## What We're Building

A Node.js module that exposes two independent data layers for Meadowsyn's visual experiments (F2-F7):

- **Layer 1 — Roster** (`transfer/ideagui/ideagui.json`): 85 agent sessions across 42 projects. Provides session identity, project name, terminal, agent type (claude/codex/gemini), domain, sync topology. Synced from IdeaGUI Notion DB via mutagen. Read once at startup (topology changes hourly, not every 5s).
- **Layer 2 — Live Ops** (`clavain-cli factory-status --json`): Fleet utilization (total/active/idle), work queue by priority, WIP agent→bead mappings with `project` field, recent dispatches, watchdog health. Polled every 5s.

Each experiment declares which layers it consumes. No global merge — per-experiment join only where needed.

## Why This Approach

**Two independent layers over global merge** — 8-agent research review (4 custom agents: identity-resolution, source-emission, parallel-layers, viz-contracts) found:
- 3 of 6 experiments (F3 Hydra, F6 Loopy, F7 Process Replay) need only factory-status aggregates. Roster is irrelevant.
- 2 experiments (F2 Split-Flap, F4 Force Graph) need a project-level join for display names and grouping.
- 1 experiment (F5 Heatmap) works with parallel layers (factory-status grid + roster sidebar).
- **Per-agent matching is impossible**: no foreign key between WIP hex session IDs (CLAUDE_SESSION_ID, ephemeral) and roster session names. The join is inherently project-level, not session-level.

**No hard fail** — a missing roster should not kill experiments that don't use it. Per-experiment source requirements instead.

**Enrich at source** — factory-status.go gets a `project` field on WIP entries (~5 LOC). This moves bead-prefix-to-project logic to the authoritative source. No more `split('-')[0]` parsing downstream.

## Key Decisions

- **Data model**: Two independent layers. Experiments consume what they need. F2/F4 get a project-level join via WIP `project` field → roster `project` field. F3/F6/F7 consume factory-status only.
- **Go prerequisite**: Add `Project string` to `wipEntry` in `factory_status.go` (~5 LOC). Extracts `strings.ToLower(strings.SplitN(b.ID, "-", 2)[0])`. Zero new lookups, additive JSON change.
- **Join granularity**: Project-level only. All sessions in a project share the same `active_beads`. The pipe documents this honestly — `meta.join_coverage` exposes unmatched beads.
- **Delivery**: Dual-mode — ES module export for in-browser consumers, CLI with `--stream` for stdout JSON lines.
- **Roster caching**: Read once at startup, re-read on file mtime change. Not per-snapshot.
- **Unmatched WIP**: Beads whose prefix doesn't match any roster project (e.g., `iv-*`, `projects-*`) are surfaced in `meta.unmatched_wip`, not silently dropped.

## Open Questions (Resolved)

- **Refresh interval**: 5s (matches factory-status polling cadence). ✓
- **History buffer**: F1 is stateless. F8 (DataPipe) adds history. ✓
- **Matching strategy**: Project-level join using factory-status `project` field. Per-agent matching deferred to Phase 2 (SessionStart hook for ID bridge). ✓

## Per-Experiment Source Requirements

| Experiment | Sources Needed | Join? |
|---|---|---|
| F2 Split-Flap | roster + factory-status | Project-level (display names) |
| F3 Hydra Ambient | factory-status only | No |
| F4 Force Graph | roster + factory-status | Project-level (compound nodes) |
| F5 Heatmap | factory-status + roster sidebar | Parallel layers |
| F6 Loopy Signals | factory-status only | No |
| F7 Process Replay | factory-status only | No |

## Module Structure

```
apps/Meadowsyn/experiments/ideagui-pipe/
  index.js          # Core: readRoster(), readFactoryStatus(), generateSnapshot()
  cli.js            # CLI entry: --stream, --interval, --ideagui-path
  package.json      # type: module, bin: cli.js
```
