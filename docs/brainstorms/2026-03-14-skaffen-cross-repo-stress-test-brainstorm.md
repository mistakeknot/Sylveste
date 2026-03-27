---
artifact_type: brainstorm
bead: Sylveste-ome7
stage: discover
---

# Skaffen Cross-Repo Stress Testing

**Bead:** Sylveste-ome7

## What We're Building

An end-to-end stress testing campaign that runs Skaffen against unfamiliar open-source repos to discover failure modes, validate the intermix evaluation pipeline, and build observability infrastructure for automated failure tracking.

## Priority Stack

1. **Observability first** — logging, intermux integration, debug bead auto-creation
2. **Validate pipeline** — intermix init→run→classify→report works end-to-end
3. **Discover failure modes** — run the matrix, classify breakages, cluster patterns
4. **Fix reliability** — address discovered issues in Skaffen

## Architecture Decisions

### Execution Model: Full Parallel with intermux Supervisor

Launch all 9 cells as parallel tmux sessions (`intermix-<cell_id>`). intermux monitors health across all sessions simultaneously.

**Why parallel over sequential:**
- 9 cells is small enough to run concurrently without coordination complexity
- intermux was built for multi-agent monitoring — `list_agents`, `agent_health`, `who_is_editing` handle this natively
- ~9x faster than sequential (each cell ~5-15 min → total ~15 min vs ~2 hours)

**JSONL isolation:** Per-cell JSONL files (`intermix-<cell_id>.jsonl`) instead of a single append-only file. `report_matrix` merges at report time. Eliminates write races.

**Changes required to intermix:**
- `run_cell` launches Skaffen in a named tmux session instead of raw `exec.CommandContext`
- New per-cell JSONL file naming: `<campaign_dir>/cells/<cell_id>.jsonl`
- `report_matrix` walks `cells/` directory to reconstruct campaign state
- New `supervisor` tool (or adapt existing `run_cell`) for parallel dispatch

### Failure Tracking: Auto-create + Cluster

Two-tier bead creation:

1. **Per-cell debug beads** — each classified failure automatically creates a child bead under Sylveste-ome7 with: cell ID, repo, task, failure taxonomy, Skaffen evidence excerpt, tmux pane capture
2. **Pattern beads** — `report_matrix` clusters failures by taxonomy (e.g., "all Go refactor-extract tasks timeout") and creates pattern beads that reparent the individual cell beads

### Evidence Flow: Dual Path

After each cell completes:
1. **Local:** Copy Skaffen's evidence JSONL (`~/.skaffen/evidence/<session_id>.jsonl`) into the intermix results directory alongside the cell JSONL
2. **Fleet:** Let Skaffen's existing intercore bridge (`ic events record`) fire to interspect for fleet-level pattern aggregation

### intermux Integration: Supervisor Mode

Each Skaffen cell runs in its own tmux session. intermux provides:
- **Health monitoring:** `agent_health` detects stuck (>5 min no change) or crashed cells
- **Live visibility:** `peek_agent` captures pane output for any cell
- **Activity feed:** `activity_feed` shows chronological events across all cells
- **Conflict detection:** `who_is_editing` catches if two cells somehow touch the same files (shouldn't happen with isolated clones, but safety net)

### First Run Scope: Quarter Matrix (9 cells)

| Repo | Language | Complexity | Tasks |
|------|----------|------------|-------|
| chi | Go | small | add-test, refactor-extract, add-feature |
| zod | TypeScript | small | add-test, refactor-extract, add-feature |
| click | Python | medium | add-test, refactor-extract, add-feature |

3 repos × 3 generic tasks = 9 cells. One small repo per language family (Go, TS, Python), skipping Rust for v1. All generic tasks to test breadth.

## Key Decisions

- **Parallel execution** over sequential — 9 cells is small enough, intermux handles supervision
- **Per-cell JSONL isolation** — eliminates write races, merge at report time
- **Tmux-per-cell** — intermux gets automatic visibility without custom monitoring code
- **Auto-create + cluster beads** — per-cell for traceability, pattern beads for actionable fixes
- **Dual evidence path** — local for intermix, intercore bridge for fleet patterns
- **Quarter matrix first** — validate pipeline with 9 cells before committing to 60

## Open Questions

- **API rate limits:** Can we sustain 9 concurrent Anthropic API sessions? May need to check tier limits or use Claude Code provider instead of direct API.
- **Clone isolation:** Each cell clones to a temp dir — need to ensure cleanup after run, especially on crash.
- **Timeout handling:** When intermux detects a stuck cell (>5 min), should it kill the tmux session or just flag it? Kill is aggressive but prevents resource waste.
- **Cost estimation:** 9 parallel cells × ~$1-5 per cell = $9-45 for the first run. Acceptable?
- **Skaffen provider:** Should cells use `anthropic` (direct API, faster) or `claude-code` (OAuth, slower but free with Claude Max)?
