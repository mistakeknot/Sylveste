---
name: interlab
description: "Autonomous experiment loop with mutation provenance tracking — init, run, log experiments with JSONL persistence, git isolation, SQLite mutation store, and ic events bridge."
---
# Gemini Skill: interlab

You have activated the interlab capability.

## Base Instructions
# interlab — Agent Development Guide

## Overview

Autonomous experiment loop for Demarch — an Interverse MCP plugin providing 7 MCP tools: 3 single-campaign tools (`init_experiment`, `run_experiment`, `log_experiment`) and 4 multi-campaign orchestration tools (`plan_campaigns`, `dispatch_campaigns`, `status_campaigns`, `synthesize_campaigns`). JSONL persistence, git branch isolation, circuit breaker guards, beads-backed coordination, and ic events bridge.

## Agent Quickstart

1. Read this file (AGENTS.md) — you're doing it now.
2. Run `bd ready` to see available work.
3. Before editing, check the relevant module's local AGENTS.md if one exists.
4. When done: `bd close <id>`, commit, push.

## Directory Layout

| Directory | Purpose |
|-----------|---------|
| `cmd/interlab-mcp/` | MCP server entry point (stdio) |
| `internal/experiment/` | Single-campaign engine: tools, state model, ic bridge |
| `internal/orchestration/` | Multi-campaign orchestration: plan, dispatch, status, synthesize |
| `bin/` | Auto-build launcher (`launch-mcp.sh`) + compiled binary |
| `.claude-plugin/` | Plugin manifest (`plugin.json`) |
| `skills/autoresearch/` | Single-campaign `/autoresearch` skill |
| `skills/autoresearch-multi/` | Multi-campaign `/autoresearch-multi` skill |
| `hooks/` | SessionStart hook for campaign detection |
| `scripts/` | Build and utility scripts |
| `tests/structural/` | Python structural tests (plugin validation) |
| `docs/` | Brainstorms, plans, research, solutions |

## Build & Test

```bash
# Build binary
go build -o bin/interlab-mcp ./cmd/interlab-mcp/

# Run Go tests
go test ./... -count=1

# Run structural tests
python3 -m pytest tests/structural/ -v

# Lint
go vet ./...

# Validate plugin manifest
python3 -c "import json; json.load(open('.claude-plugin/plugin.json'))"
```

## Coding Conventions

- **Go style:** `gofmt`, `go vet`, error wrapping with `%w`
- **Testing:** Table-driven tests, `t.TempDir()` for filesystem tests, `t.Helper()` in test utilities
- **Error handling:** Best-effort for external tools (ic CLI, git) — degrade gracefully, never crash
- **State model:** All state reconstructed from JSONL on each tool call. No in-memory state between calls.
- **Git safety:** NEVER `git add -A`. Always path-scoped: `git add <explicit files>` from `Config.FilesInScope`
- **JSONL format:** One JSON object per line. `type` field discriminates: `"config"` or `"result"`

## Architecture

### Three-Tool Interface

1. **init_experiment** — Write config header to JSONL, create experiment branch, return segment ID
2. **run_experiment** — Check circuit breaker, execute benchmark, parse METRIC lines, save run details
3. **log_experiment** — Record decision (keep/discard/crash), git commit or revert, write JSONL, emit ic event

### State Reconstruction

```
interlab.jsonl → ReconstructState() → State{Config, RunCount, BestMetric, CrashCount, ...}
```

Each tool call reads the JSONL from scratch. No server-side state machine. Crash recovery is free — a fresh agent picks up exactly where the last one left off.

### Circuit Breaker

Three independent limits (configurable per campaign):
- `max_experiments` (default 50) — total runs in this segment
- `max_crashes` (default 3) — consecutive crashes
- `max_no_improvement` (default 10) — consecutive runs without beating best

### METRIC Protocol

Benchmark scripts output parseable lines:
```
METRIC duration_ms=42.5
METRIC memory_kb=1024
```

`run_experiment` extracts these via regex and matches `metric_name` from config.

## Bead Tracking

All work is tracked using beads (`bd` CLI). The database lives in `.beads/`.

```bash
bd ready                              # Show available work
bd create --title="..." --type=task   # Create new issue
bd update <id> --status=in_progress   # Claim work
bd close <id>                         # Mark complete
```

## Multi-Campaign Orchestration

### Four Orchestration Tools

1. **plan_campaigns** — Agent provides campaign specs + dependency graph → tool creates beads, directories, JSONL configs
2. **dispatch_campaigns** — Reads plan, identifies ready campaigns (deps met), returns dispatch instructions
3. **status_campaigns** — Reads bead state + JSONL per campaign, returns aggregate progress
4. **synthesize_campaigns** — Reads completed results, generates cross-campaign report, closes parent bead

### Beads-Backed Coordination

Multi-campaign orchestration uses beads as the coordination layer:
- **Parent bead** (epic) = the broad optimization goal
- **Child beads** (tasks) = individual campaigns with `bd dep add` for ordering
- State stored via `bd set-state`: `campaign_name`, `campaign_dir`, `campaign_ids`, `plan_timestamp`

### Execution Model

- Same-project campaigns: dispatch via Claude subagents, each running `/autoresearch`
- Cross-project: session-level parallelism via intermux
- Shared files: serial execution enforced by dependency edges
- File conflicts detected at plan time — overlapping `files_in_scope` between parallel campaigns rejected

### Skills

- `/autoresearch` — Single-campaign loop (existing)
- `/autoresearch-multi` — Multi-campaign orchestration: analyze → plan → dispatch → monitor → synthesize

## Key Dependencies

| Dependency | Version | Purpose |
|-----------|---------|---------|
| `github.com/mark3labs/mcp-go` | v0.32.0 | MCP server framework (tool registration, stdio serving) |
| Go stdlib | 1.23+ | JSON, os/exec, regexp, bufio |
| `ic` CLI | optional | Event emission, run creation (best-effort) |
| `bd` CLI | optional | Beads coordination for multi-campaign orchestration |
| `git` | required | Branch creation, commit, revert |


