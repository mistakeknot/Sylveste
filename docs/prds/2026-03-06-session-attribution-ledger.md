---
artifact_type: prd
bead: iv-30zy3
stage: design
---
# PRD: Durable Session Attribution Ledger

## Problem

Session-to-bead-to-run attribution relies on temp files (`/tmp/interstat-*`) that are lost on crashes, stale across restarts, and invisible when bead context changes mid-session. This blocks trustworthy cost-per-landable-change measurement and routing eval.

## Solution

Add a `sessions` table and `session_attributions` event table to the intercore kernel DB, expose them via `ic session` CLI commands, and dual-write from interstat/clavain hooks alongside existing temp files.

## Features

### F1: Schema — sessions + session_attributions tables (v26 migration)

**What:** Add two new tables to the intercore schema and a v26 migration file.

**Acceptance criteria:**
- [ ] `sessions` table exists with columns: session_id, project_dir, agent_type, model, started_at, ended_at, metadata; UNIQUE(session_id, project_dir)
- [ ] `session_attributions` table exists with columns: session_id, project_dir, bead_id, run_id, phase, created_at
- [ ] Indexes on session_attributions(session_id), sessions(project_dir, started_at)
- [ ] v26 migration applies cleanly on existing DBs (`go test ./...` passes)
- [ ] schema.sql updated with new tables

### F2: CLI — `ic session` command group

**What:** Add `ic session start`, `ic session attribute`, `ic session end`, `ic session current`, and `ic session list` subcommands.

**Acceptance criteria:**
- [ ] `ic session start --session=X --project=Y --agent-type=Z` creates a sessions row (idempotent via UPSERT)
- [ ] `ic session attribute --session=X --bead=B --run=R --phase=P` inserts a session_attributions row
- [ ] `ic session end --session=X` sets ended_at on the sessions row
- [ ] `ic session current --session=X --json` returns latest attribution (bead, run, phase) as JSON
- [ ] `ic session list --project=Y --since=24h --json` returns recent sessions as JSON array
- [ ] All commands respect `--db` global flag
- [ ] Integration tests pass

### F3: Hook — interstat session-start dual-write

**What:** Update interstat's `session-start.sh` hook to call `ic session start` alongside the existing temp-file write.

**Acceptance criteria:**
- [ ] Hook calls `ic session start` with session_id, project_dir, and agent_type
- [ ] Existing temp-file write (`/tmp/interstat-session-id`) is preserved (dual-write)
- [ ] `ic` failure is non-blocking (hook continues on error)
- [ ] Existing bead context from `bd list --status=in_progress` is written via `ic session attribute`

### F4: Hook — clavain route/sprint attribution dual-write

**What:** Update clavain route.md and sprint.md bead-context writes to also call `ic session attribute`.

**Acceptance criteria:**
- [ ] When route/sprint sets `CLAVAIN_BEAD_ID`, it also calls `ic session attribute --bead=X`
- [ ] When sprint advances phase, it calls `ic session attribute --phase=P`
- [ ] When sprint creates a run, it calls `ic session attribute --run=R`
- [ ] Existing temp-file writes are preserved (dual-write)
- [ ] `ic` failure is non-blocking

### F5: Hook — interstat session-end recording

**What:** Update interstat's `session-end.sh` hook to call `ic session end`.

**Acceptance criteria:**
- [ ] Hook calls `ic session end --session=X` to set ended_at
- [ ] Existing session-end behavior preserved
- [ ] `ic` failure is non-blocking

## Non-goals

- Migrating consumers (post-task.sh, cost-query.sh, Galiana) to read from the ledger — separate beads
- Removing temp-file writes — only after all consumers migrate
- Adding session_id to phase_events or dispatch_events — separate work (iv-544dn F5)
- Coverage metrics (detecting dark sessions) — uses the ledger but is separate work

## Dependencies

- intercore Go codebase (`core/intercore/`)
- interstat plugin hooks (`interverse/interstat/hooks/`)
- clavain route/sprint commands (`os/clavain/commands/`)
- `ic` binary must be on PATH (already required by existing hooks)

## Open Questions

None — all questions from brainstorm are resolved:
1. Sessions table goes in intercore DB (kernel concern)
2. session_attributions is append-only events (matches kernel pattern)
3. Multi-project sessions: one row per (session_id, project_dir) pair
4. Metadata: start with agent_type + model, add more later
