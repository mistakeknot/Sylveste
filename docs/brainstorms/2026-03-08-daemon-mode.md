**Bead:** iv-sym04

# Brainstorm: Continuous Dispatch Daemon Mode for Clavain

## Problem Statement

Clavain's `/route` command is session-initiated — a human must start each work session. For autonomous operation (overnight runs, CI-triggered builds, batch bead processing), Clavain needs a long-running daemon that:

1. Continuously polls `bd ready` for eligible beads
2. Respects concurrency limits (max simultaneous agents)
3. Dispatches Claude Code sessions via `ic dispatch spawn`
4. Handles graceful shutdown, agent failure, and restart recovery

## Prior Art

Symphony (iv-sym01) provides the reference architecture: poll-dispatch-reconcile loop. Key adaptations for Demarch:
- **Durable state** via intercore SQLite (not in-memory like Symphony)
- **Beads** as tracker (not Linear)
- **Interlock** for file coordination (not worktrees)
- **Trunk-based** development (no merge step)

## Design Decisions

### D1: Where does the daemon live?

**Decision: `clavain-cli daemon` subcommand (Go)**

Clavain owns work discovery and dispatch policy (L2 OS). Intercore provides primitives (`ic dispatch spawn/poll/kill`). The daemon composes them. Rejected alternatives: `ic daemon` (wrong architectural layer — intercore is L1 kernel), shell script (fragile for long-running process), standalone binary (unnecessary when clavain-cli already exists).

### D2: How does it spawn agents?

**Decision: Route through `ic dispatch spawn`**

The daemon calls `ic dispatch spawn --goal="<bead title>" --bead=<id>` which creates a dispatch record, then spawns the Claude Code subprocess. This gives us tracking, cost attribution, and kill capabilities. The subprocess is `claude --dangerously-skip-permissions -p "/clavain:route <bead-id>"`.

### D3: Concurrency model

- **Global limit**: `max_concurrent` (default: 3)
- **Slot accounting**: Count active dispatches via `ic dispatch list --active`
- **Backpressure**: If all slots full, skip this poll cycle
- Per-priority slots deferred to Phase 3

### D4: Dispatch eligibility

A bead is eligible when:
1. `bd ready` returns it (open, unblocked)
2. Not already claimed (`claimed_at` > 45 min or unclaimed)
3. No active `ic dispatch` for this bead
4. Priority meets threshold (configurable, default P0-P3)
5. Complexity within range (configurable, default 1-3 — skip complex/research)

### D5: Reconciliation loop

Every poll cycle, before dispatching new work:
1. **Liveness check**: `ic dispatch list --active` → poll each → kill zombies
2. **Bead state check**: Has a bead been closed externally? → Kill its dispatch
3. **Stale claim cleanup**: `claimed_at` > 45 min with no dispatch → release claim
4. **Retry queue**: Failed dispatches → requeue with exponential backoff

### D6: Configuration

```yaml
# .clavain/daemon.yaml
poll_interval: 30s
max_concurrent: 3
max_complexity: 3
min_priority: 3          # P0-P3 only (lower number = higher priority)
retry_max: 3
retry_backoff_base: 10s  # min(10s * 2^attempt, backoff_cap)
retry_backoff_cap: 5m
stall_timeout: 30m
label_filter: ""         # Optional: mod:clavain, lane:infra, etc.
log_file: .clavain/daemon.log
```

### D7: Graceful shutdown

1. Catch SIGTERM/SIGINT
2. Stop accepting new dispatches (drain mode)
3. Wait for running agents to complete (configurable timeout, default 10m)
4. Release all bead claims (`bd update <id> --unclaim` equivalent)
5. Write final state to log

## Architecture

```
┌─────────────────────────────────────────┐
│            clavain-cli daemon           │
│                                         │
│  ┌───────────┐  ┌──────────────────┐    │
│  │ Poll Loop │→ │ Eligibility Check │   │
│  │  (30s)    │  │ bd ready + filter │   │
│  └───────────┘  └────────┬─────────┘   │
│                          │              │
│                  ┌───────▼────────┐     │
│                  │ Slot Allocator │     │
│                  │ (max N agents) │     │
│                  └───────┬────────┘     │
│                          │              │
│              ┌───────────▼──────────┐   │
│              │   ic dispatch spawn  │   │
│              │   (per eligible bead)│   │
│              └───────────┬──────────┘   │
│                          │              │
│              ┌───────────▼──────────┐   │
│              │  Reconciliation Loop │   │
│              │  - liveness check    │   │
│              │  - bead state sync   │   │
│              │  - stale cleanup     │   │
│              │  - retry backoff     │   │
│              └──────────────────────┘   │
└─────────────────────────────────────────┘
```

## Phased Delivery

### Phase 1 — Minimal viable daemon (this bead)
- [ ] `clavain-cli daemon` command with poll loop
- [ ] `bd ready` polling with priority/complexity filters
- [ ] Bead claiming + Claude Code subprocess spawn
- [ ] Concurrency limiting (global max)
- [ ] Graceful shutdown (SIGTERM/SIGINT)
- [ ] Basic structured logging
- [ ] Configuration via flags (file-based config deferred)

### Phase 2 — Production hardening (future beads)
- [ ] `ic dispatch` integration for full durability + cost attribution
- [ ] Reconciliation loop (kill stale, retry failed)
- [ ] Exponential backoff for retries (iv-sym03)
- [ ] `.clavain/daemon.yaml` configuration file
- [ ] Stall detection (kill agent if no event for N minutes)

### Phase 3 — Advanced features (future beads)
- [ ] Per-priority concurrency slots
- [ ] Lane-filtered dispatch
- [ ] Budget enforcement (stop when spend threshold hit)
- [ ] Status API / TUI dashboard
- [ ] Systemd service file + install script

## Risks

| Risk | Mitigation | Phase |
|------|-----------|-------|
| Runaway agents (infinite loop) | Stall detection + `ic dispatch kill` | Phase 2 |
| Claim races (two daemons) | `bd update --claim` is atomic; fail-fast on conflict | Phase 1 |
| Cost explosion (unattended) | Complexity cap (default 1-3), budget enforcement | Phase 1/3 |
| Zombie processes | SIGCHLD handling, reconciliation loop | Phase 1/2 |
| Agent prompt injection via bead title | Sanitize bead title before passing to Claude | Phase 1 |

## Open Questions

1. Should the daemon run `/clavain:route <bead-id>` or `/clavain:work <plan-path>` directly? Route is safer (does its own classification) but adds overhead.
2. Should we support "dry run" mode that logs what would be dispatched without actually spawning?
3. How does the daemon interact with interlock? If two daemon-spawned agents edit overlapping files, interlock handles it — but should the daemon pre-check for conflicts?
4. Should the daemon have a "one-shot" mode (`--once`) that processes the ready queue once and exits? Useful for cron-triggered runs.
