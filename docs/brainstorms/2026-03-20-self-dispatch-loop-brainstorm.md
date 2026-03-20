---
artifact_type: brainstorm
bead: Demarch-ysxe.3
stage: discover
---

# Self-Dispatch Loop — Brainstorm

## What We're Building

An event-driven self-dispatch system that lets agents autonomously pick up the next bead after completing work. When an agent finishes (Stop hook fires), the system scores available beads, claims the best candidate atomically, and dispatches execution via route.md. Opt-in via `CLAVAIN_SELF_DISPATCH=true`.

## Why This Approach

The current workflow requires human dispatch: user runs `/route` or `/clavain:sprint` to assign work. With 3+ agents running, this becomes a bottleneck. Self-dispatch closes the loop — agents become autonomous work consumers.

Key design constraints from the wave1 plan:
- **Event-driven, not polling:** Stop hook trigger (not a cron/interval)
- **Atomic claim:** Uses ysxe.1's `bead_claim()` to prevent race conditions
- **Opt-in:** No behavior change unless explicitly enabled
- **Safety:** Circuit breaker, WIP limit, cooldown

## Key Decisions

### 1. Trigger: Separate Stop hook with own sentinel
- New `self-dispatch.sh` registered in hooks.json as a second Stop hook
- Uses its own intercore sentinel (`dispatch_sentinel`) — independent of auto-stop-actions.sh
- Only fires when `CLAVAIN_SELF_DISPATCH=true` env var is set
- 20s cooldown via intercore sentinel TTL

### 2. Scoring: Extend existing `score_bead()` in interphase
- Existing factors (priority 60%, phase 30%, recency 20%) already weight correctly
- Add two new factors to interphase's `score_bead()`:
  - **deps-ready bonus (+15):** All dependency beads are closed
  - **WIP-balance bonus (+10):** Bead is in a module with fewer active agents
- Add random perturbation (0-5) for tie-breaking
- Total scale: 0-125 (vs current 0-110)

### 3. Dispatch flow
- Stop hook fires → check `CLAVAIN_SELF_DISPATCH=true` → check cooldown
- Run `discovery_scan_beads()` → filter to ready beads (deps satisfied, not claimed)
- Score top candidate → add 0-500ms jitter → `bead_claim()`
- On claim success: write dispatch signal, output JSON to trigger `/clavain:route`
- On claim failure: re-score once, then back off 30s

### 4. Safety mechanisms
- **WIP limit:** Agent must hold 0 in-progress beads (check before scoring)
- **Circuit breaker:** 3 consecutive dispatch failures → pause self-dispatch for this session
- **Cooldown:** 20s minimum between dispatch attempts (intercore sentinel)
- **Opt-out files:** `.claude/clavain.no-selfdispatch` per-repo

### 5. Architecture: Shell hook + scoring enhancement
- `self-dispatch.sh` — Stop hook handler (Bash, ~80 lines)
- Enhance `score_bead()` in interphase/hooks/lib-discovery.sh with deps-ready + WIP-balance
- No Go code needed — existing Bash primitives cover all requirements
- Telemetry: log to `.clavain/dispatch-log.jsonl`

## Open Questions

- Should dispatch respect `DISCOVERY_LANE` filtering (existing lane system)?
  - Probably yes — if agent has a lane restriction, respect it
- Should dispatch skip beads with complexity > agent's max?
  - Defer to ysxe.4 (capability filter is listed as a step but not blocking)
- Multi-project dispatch via `DISCOVERY_ROOTS`?
  - Already supported by lib-discovery.sh wrapper — should work automatically
