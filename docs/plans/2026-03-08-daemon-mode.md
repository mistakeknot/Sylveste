**Bead:** iv-sym04

# Plan: Continuous Dispatch Daemon Mode for Clavain (Phase 1 — MVP)

## Goal

Add a `clavain-cli daemon` subcommand that continuously polls for eligible beads, claims them, and spawns Claude Code sessions — enabling autonomous overnight/unattended operation.

## Scope

Phase 1 only: poll loop, eligibility filtering, subprocess spawning, concurrency limiting, graceful shutdown, logging. Phase 2 (ic dispatch integration, reconciliation, retry backoff) and Phase 3 (budget enforcement, TUI, systemd) are separate beads.

## Reference Files

- `os/clavain/cmd/clavain-cli/main.go` — command dispatch (add `case "daemon":`)
- `os/clavain/cmd/clavain-cli/exec.go` — `runBD()`, `runCommandExec()` helpers
- `os/clavain/cmd/clavain-cli/claim.go` — `isClaimStale()`, `isBeadClosed()`, claim constants
- `docs/research/assess-symphony.md` — design reference (poll-dispatch-reconcile)

## Steps

### Step 1: Create `daemon.go` with config and types
- [x] Create `os/clavain/cmd/clavain-cli/daemon.go`
- [x] Define `daemonConfig` struct: `PollInterval`, `MaxConcurrent`, `MaxComplexity`, `MinPriority`, `LabelFilter`, `DryRun`, `Once` (one-shot mode)
- [x] Parse flags: `--poll=30s`, `--max-concurrent=3`, `--max-complexity=3`, `--min-priority=3`, `--label=`, `--dry-run`, `--once`, `--project-dir=.`
- [x] Define `daemonState` struct: active dispatches (map of bead ID → agentInfo), shutdown flag, mutex
- [x] Define `bdReadyEntry` struct: ID, title, priority, labels

### Step 2: Implement bead polling and eligibility filtering
- [x] `pollEligible(state, cfg)` — runs `bd ready --json`, parses output
- [x] Filter by priority: bead priority <= `cfg.MinPriority` (P0=highest)
- [x] Filter by complexity: read `bd state <id> complexity` for each candidate, skip if > `cfg.MaxComplexity`
- [x] Filter by label: if `cfg.LabelFilter` non-empty, check bead labels contain it
- [x] Filter by already-active: skip beads already in `state.active` map
- [x] Filter by claim freshness: skip beads with `claimed_at` < 45 min (another agent has it)

### Step 3: Implement agent spawning
- [x] `spawnAgent(state, cfg, bead, logDir)` — claims bead, spawns Claude Code
- [x] Claim bead: `runBD("update", bead.ID, "--claim")`. On failure, skip (another agent got it).
- [x] Write claim identity: `claimed_by=daemon-<pid>` and `claimed_at=<epoch>`
- [x] Sanitize bead title for prompt (strip backticks, dollar signs, newlines)
- [x] Build Claude command: `claude --dangerously-skip-permissions --verbose -p "/clavain:route <bead-id>"`
- [x] Start subprocess with `exec.Command`, set `cmd.Dir` to `cfg.ProjectDir`
- [x] Set `cmd.Stdout` and `cmd.Stderr` to log file (`.clavain/daemon/<bead-id>.log`)
- [x] Start (not Run) — non-blocking. Goroutine waits for completion.
- [x] Add to `state.active` map

### Step 4: Implement the main poll-dispatch loop
- [x] `cmdDaemon(args []string) error` — entry point
- [x] Parse flags into `daemonConfig`
- [x] Validate: `bd` available, project dir has `.beads/` or CLAUDE.md
- [x] Set up signal handler: `SIGTERM`, `SIGINT` → set shutdown flag
- [x] Log startup with config summary
- [x] Main loop: check shutdown, reap completed, check slots, poll, dispatch
- [x] If `--once`: run one cycle, wait for agents, then exit

### Step 5: Implement graceful shutdown
- [x] On signal: set shutdown flag, stop polling
- [x] Send SIGTERM to all active agent processes
- [x] Wait up to 60s for graceful exit
- [x] If still alive after timeout, SIGKILL
- [x] Release all bead claims (`claimed_by=released`, `claimed_at=0`)
- [x] Log final summary

### Step 6: Register command in main.go
- [x] Add `case "daemon":` to main.go command dispatch
- [x] Add to help text

### Step 7: Write tests
- [x] `daemon_test.go`:
  - Test config flag parsing (defaults + custom)
  - Test bead title sanitization
  - Test label matching
  - Test daemon state operations (add/remove/count/shutdown)
  - Test concurrent state access (race detector safe)

### Step 8: Add logging infrastructure
- [x] Create `.clavain/daemon/` directory on startup for per-agent logs
- [x] Main daemon log to stdout via `log.Printf` (timestamp, level, bead_id, action)
- [x] Per-agent logs append (don't overwrite)
