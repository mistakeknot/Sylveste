---
artifact_type: cuj
journey: multi-agent-coordination
actor: regular user (developer running multiple agents simultaneously)
criticality: p1
bead: Demarch-2c7
---

# Multi-Agent Coordination

## Why This Journey Matters

Running multiple AI agents on the same codebase without coordination produces merge conflicts, duplicated work, and race conditions. Two agents editing the same file simultaneously corrupt each other's changes. Two agents claiming the same bead waste tokens on redundant work. An agent that doesn't know what other agents are doing makes decisions in a vacuum.

Multi-agent coordination is the infrastructure that makes fleet development possible. Without it, the developer is limited to one agent at a time — which defeats the purpose of Demarch. With it, five agents can work in parallel on different beads, aware of each other's file reservations, sharing status through the coordination bus, and avoiding conflicts.

This journey spans multiple plugins: **Interlock** (file reservations), **Intermux** (agent visibility), **Intercore** (state + coordination bus), and **Beads** (work tracking). The developer rarely interacts with these directly — they're the plumbing that Clavain and Mycroft use — but when something goes wrong, the developer needs to diagnose and fix it.

## The Journey

The developer starts three agent sessions via Mycroft or manually. When agents are dispatched by Clavain or Mycroft, they auto-join Interlock on startup — no manual step required. For ad-hoc sessions the developer starts themselves, `/interlock:join` registers the agent explicitly. Either way, Interlock creates a coordination identity. When an agent starts editing `selector.go`, it reserves the file: `reserve_files(["internal/mycroft/scheduler/selector.go"])`. Other agents querying that file see it's held and work on something else.

The developer can see who's editing what: `/interlock:status` shows active agents and their reservations. If two agents need the same file, Interlock's negotiation protocol kicks in — one agent can request release, the other can grant it or refuse. For non-conflicting sections of large files, fine-grained locking (future) allows simultaneous edits.

Intermux provides the visibility layer. `/intermux:agents` shows a dashboard of all tmux agent sessions — their status, recent output, and activity timeline. The developer can peek at any agent's output without switching tabs: `peek_agent("grey-area")` returns the last N lines from that agent's session.

Intercore is the coordination infrastructure underneath, providing both an event bus and a shared state store. Agents emit events (started, progress, completed, error) across 5 source types (phase, dispatch, interspect, discovery, coordination), which other agents and tools can subscribe to via async handlers. Shared state — claimed beads, sprint phase, budget remaining — is accessible through Intercore's key-value store, giving every agent a consistent view of the fleet's status.

Beads ties it together — each agent claims a bead before starting work, preventing double-assignment. Claims have heartbeats — if an agent stalls, the claim goes stale and Mycroft can reassign.

When coordination fails — a conflict, a stale lock, a hung agent — the developer intervenes:
- `/interlock:conflict-recovery` — resolve file conflicts
- `intermux:agents` — find the stuck agent
- `bd update <id> --unclaim` — release a stale bead claim

## Success Signals

| Signal | Type | Assertion |
|--------|------|-----------|
| No merge conflicts when 3+ agents work in parallel | measurable | Zero git conflicts during coordinated multi-agent session |
| File reservations prevent concurrent edits to same file | measurable | Second agent's edit blocked when file is reserved |
| Agent status visible within 5 seconds of change | measurable | Intermux dashboard reflects state change ≤ 5s |
| Stale reservations auto-expire | measurable | Reservations from dead agents expire within timeout |
| Bead claims prevent double-assignment | measurable | `bd update --claim` fails if already claimed |
| Coordination works across separate tmux sessions | measurable | Agents in different tmux windows see each other |
| Developer can diagnose conflicts from `/interlock:status` alone | qualitative | Status output shows who holds what and for how long |

## Known Friction Points

- **File-level granularity only** — Interlock reserves entire files, not functions or line ranges. Two agents editing different functions in the same file must negotiate.
- **No automatic conflict resolution** — when conflicts arise, the developer must intervene. Future: merge assistant that combines non-overlapping changes.
- **Coordination requires Intercore** — Intercore is a hard dependency for multi-agent work. If the Intercore bus isn't running, multi-agent dispatch refuses to start rather than allowing uncoordinated parallel execution.
- **Intermux depends on tmux** — agents not in tmux sessions aren't visible to Intermux. Non-tmux agents (Docker, remote) need a different adapter.
- **Heartbeat interval is a tradeoff** — too short = noisy, too long = stale claims linger. Heartbeats should be adaptive: fast when the agent is actively producing output, slow when idle.
