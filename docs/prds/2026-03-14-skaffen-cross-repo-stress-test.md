---
artifact_type: prd
bead: Demarch-ome7
stage: design
---

# PRD: Skaffen Cross-Repo Stress Testing

## Problem

Skaffen has 355+ hermetic tests but zero end-to-end validation against real repos it hasn't seen before. We don't know what breaks when Skaffen encounters unfamiliar codebases, and we have no infrastructure to automatically track and cluster failure patterns across a test campaign.

## Solution

Build a parallel stress test pipeline using intermix (execution) + intermux (supervision) + beads (failure tracking), then run a 9-cell campaign across 3 repos × 3 tasks to discover failure modes.

## Features

### F1: Parallel Tmux Executor

**What:** Modify intermix's `run_cell` to launch Skaffen in named tmux sessions instead of raw subprocesses, enabling parallel execution with per-cell JSONL isolation.

**Acceptance criteria:**
- [ ] `run_cell` creates a tmux session named `intermix-<cell_id>` and runs Skaffen inside it
- [ ] Each cell writes to its own JSONL file at `<campaign_dir>/cells/<cell_id>.jsonl`
- [ ] A new `run_batch` tool launches N cells in parallel, returning immediately with session names
- [ ] Cleanup kills tmux sessions and removes temp clone dirs on completion or crash
- [ ] Existing `run_cell` tests pass with the tmux execution path

### F2: intermux Supervisor Integration

**What:** Wire intermux's monitoring tools into the stress test workflow so a supervisor agent can track health, detect stuck cells, and capture output across all parallel sessions.

**Acceptance criteria:**
- [ ] Each Skaffen tmux session is detectable by `intermux list_agents` (session name matches pattern)
- [ ] `agent_health` correctly reports active/idle/stuck/crashed for stress test sessions
- [ ] A new `poll_campaign` tool (or script) calls `agent_health` periodically and returns when all cells finish or timeout
- [ ] `peek_agent` captures meaningful pane output from Skaffen print-mode sessions
- [ ] Session mapping files (`/tmp/intermux-mapping-*.json`) are written for each cell session

### F3: Auto-Create Debug Beads on Failure

**What:** When `classify_result` determines a cell failed, automatically create a child bead under the campaign epic with failure context attached.

**Acceptance criteria:**
- [ ] `classify_result` calls `bd create` for non-success outcomes (timeout, crash, context_limit, tool_failure, no_progress, setup_failure)
- [ ] Debug bead includes: cell ID, repo name, task ID, failure taxonomy, Skaffen evidence excerpt (last 20 lines), tmux pane capture (last 50 lines)
- [ ] Debug bead is linked as child of Demarch-ome7 via `bd dep add`
- [ ] Partial success creates a bead with `partial` label (not skipped)
- [ ] Success cells do NOT create beads (only failures)

### F4: Evidence Harvesting (Dual Path)

**What:** After each cell completes, copy Skaffen's evidence JSONL into the intermix results directory and let the intercore bridge fire for fleet-level aggregation.

**Acceptance criteria:**
- [ ] Skaffen evidence file (`~/.skaffen/evidence/<session_id>.jsonl`) is copied to `<campaign_dir>/evidence/<cell_id>.jsonl`
- [ ] Evidence session ID is recorded in the cell JSONL for cross-reference
- [ ] If `ic` binary is available, intercore bridge events are verified in interspect (best-effort, non-blocking)
- [ ] Missing evidence files (Skaffen crashed before writing) are handled gracefully with a warning, not a crash

### F5: Pattern Clustering in report_matrix

**What:** Extend `report_matrix` to walk per-cell JSONL files, aggregate results, cluster failures by taxonomy, and create pattern beads that reparent individual debug beads.

**Acceptance criteria:**
- [ ] `report_matrix` reads from `<campaign_dir>/cells/*.jsonl` (not a single file)
- [ ] Failures are clustered by taxonomy (e.g., "timeout" across repos) and by repo (e.g., "all click tasks fail")
- [ ] Each cluster with ≥2 failures creates a pattern bead: "Pattern: <taxonomy> across <repos>"
- [ ] Pattern beads reparent individual debug beads via `bd dep add`
- [ ] Report includes a pass/fail heatmap (repo × task matrix) and per-taxonomy counts
- [ ] Delta comparison against prior campaign segment (if exists) highlights regressions

### F6: Run the 9-Cell Campaign

**What:** Execute the quarter-matrix stress test: chi (Go) × zod (TS) × click (Python) × 3 generic tasks.

**Acceptance criteria:**
- [ ] All 9 cells run to completion (success or classified failure)
- [ ] Campaign report is generated with heatmap and failure clusters
- [ ] Debug beads exist for all failures with evidence attached
- [ ] Pattern beads exist for any cross-cell failure patterns
- [ ] Total campaign duration is logged
- [ ] No orphaned tmux sessions or temp dirs after completion

## Non-goals

- **Full 60-cell matrix** — this iteration validates the pipeline with 9 cells only
- **Rust repos** — skipped for v1 (clap, axum require longer build times)
- **Parallel cell interaction** — cells are isolated; no shared state or cross-cell communication
- **Skaffen fixes** — this iteration discovers failures; fixes are tracked as separate beads
- **CI integration** — manual triggering only; automated scheduling is future work

## Dependencies

- **Skaffen binary** — must be built and on PATH (`skaffen --mode print`)
- **intermix MCP server** — must be built (`go build -o bin/intermix-mcp ./cmd/intermix-mcp/`)
- **intermux MCP server** — already built at `interverse/intermux/bin/intermux-mcp`
- **tmux** — required for parallel execution and intermux monitoring
- **beads (bd)** — required for failure tracking
- **Anthropic API key or Claude Code** — Skaffen needs an LLM provider

## Open Questions

- **Provider choice:** Direct Anthropic API (faster, costs money) vs Claude Code provider (free with Max, slower). Decision: start with direct API for speed, fall back to CC if rate-limited.
- **Stuck timeout:** Kill stuck tmux sessions after 5 min of no output change, or flag and continue? Decision: kill after timeout (configurable), log the kill in the cell JSONL.
- **Cost budget:** 9 cells × ~$1-5 = $9-45. Acceptable for first run.
