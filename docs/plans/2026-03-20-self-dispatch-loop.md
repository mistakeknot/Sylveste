---
artifact_type: plan
bead: Demarch-ysxe.3
stage: plan-reviewed
parent_plan: docs/plans/2026-03-20-ai-factory-wave1-foundation.md
---

# Plan: Self-Dispatch Loop (Demarch-ysxe.3)

## Goal

Event-driven self-dispatch: agents autonomously claim and execute beads after completing work. Stop hook trigger with cooldown, multi-factor scoring, atomic claim, dispatch via route.md.

## Prerequisites (both closed)

- Demarch-ysxe.1: Atomic bead claim (provides `bead_claim()`)
- Demarch-ysxe.2: Deterministic quality gates (provides `lib-gates.sh`)

## Files to Create/Modify

| File | Action | Purpose |
|------|--------|---------|
| `os/Clavain/hooks/auto-stop-actions.sh` | Modify | Add dispatch tier (4th tier) triggered by `bead-closed` signal |
| `os/Clavain/hooks/lib-dispatch.sh` | Create | Dispatch logic: scoring, filtering, claim, logging (~100 lines) |
| (no interphase changes) | — | Dispatch-specific scoring stays in lib-dispatch.sh, not shared scorer |

## Architecture Decisions (from flux-drive review)

1. **Merge into auto-stop-actions.sh** — not a separate hook. The existing stop sentinel architecture (`INTERCORE_STOP_DEDUP_SENTINEL`) enforces one blocking action per stop cycle. A second hook either competes for the sentinel or bypasses it, both causing issues. Adding dispatch as a 4th tier follows the precedent of the compound+drift merge (iv-rn81).

2. **Don't modify interphase** — `score_bead()` is a shared scorer used by `/lfg`, session-start, etc. Deps-ready and WIP-balance are dispatch-context signals that would be noise/misguidance in human-facing discovery. Dispatch scoring is a local re-scoring pass in `lib-dispatch.sh`.

3. **Require `bead-closed` signal specifically** — not weight >= 1. Weight >= 1 fires on any commit, which is too broad. `bead-closed` is the precise indicator that a unit of work completed.

4. **Only emit `block` after confirmed claim** — every exit path that does not own a confirmed `bead_claim` return 0 must be a silent `exit 0`. This prevents phantom dispatch where an agent executes a bead it doesn't own.

## Implementation Steps

### Step 1: Create lib-dispatch.sh

```
os/Clavain/hooks/lib-dispatch.sh
```

Sourced library with these functions:

**`dispatch_rescore()`** — local re-scoring pass on `discovery_scan_beads` output:
- Filter: skip `id: null` (orphans), skip already-claimed beads
- deps-ready check: `bd dep list $bead_id --direction=down --json` — if any dep is open/in_progress, skip bead entirely (hard filter, not bonus)
- WIP-avoidance: skip beads in modules with active WIP (extract module from bead labels; if no labels, skip this filter)
- Random perturbation: `$((RANDOM % 6))` added to each score for tie-breaking
- Output: sorted JSON array of eligible beads

**`dispatch_attempt_claim()`** — claim with retry:
- Select top bead from rescored list
- Add jitter: `sleep 0.$(( (RANDOM ^ (BASHPID * 31337)) % 500 + 100 ))`
- `bead_claim "$TOP_BEAD_ID"` — if success (return 0), return bead_id + score
- On race loss (return 1): re-run `discovery_scan_beads` fresh, rescore, try next candidate
- Max 2 attempts total. If both fail, return empty (caller exits silently)
- Only count infrastructure failures toward circuit breaker (bd unavailable, DISCOVERY_ERROR), NOT claim races

**`dispatch_log()`** — append to `$HOME/.clavain/dispatch-log.jsonl`:
- Entry: `{"ts": "<ISO>", "session": "<id>", "bead": "<id>", "score": N, "outcome": "claimed|race_lost|no_candidates|circuit_break|cap_reached"}`

**`dispatch_circuit_check()`** — circuit breaker:
- State: intercore state `dispatch_failures_$SESSION_ID` (durable across shell restarts, not /tmp)
- Threshold: 3 consecutive infrastructure failures
- Reset to 0 on successful dispatch
- Race losses do NOT increment the counter

**`dispatch_cap_check()`** — per-session dispatch cap:
- State: intercore state `dispatch_count_$SESSION_ID`
- Gate: if count >= 5, return 1 (configurable via `CLAVAIN_DISPATCH_CAP`)
- Increment on successful dispatch

### Step 2: Add dispatch tier to auto-stop-actions.sh

Add as 4th tier in the existing tiered decision block (after compound >= 4, drift >= 3):

```bash
# Tier: self-dispatch (requires bead-closed signal + opt-in)
if [[ "$CLAVAIN_SELF_DISPATCH" == "true" ]]; then
    # Check bead-closed signal specifically
    if [[ "$SIGNALS" == *"bead-closed"* ]]; then
        # Check per-repo opt-out
        if [[ ! -f ".claude/clavain.no-selfdispatch" ]]; then
            # Check dispatch-specific cooldown (20s)
            if intercore_check_or_die "dispatch_cooldown" "$SESSION_ID" 20 2>/dev/null; then
                source "${SCRIPT_DIR}/lib-dispatch.sh"
                # Guards: WIP check, circuit breaker, session cap
                if dispatch_cap_check "$SESSION_ID" && dispatch_circuit_check "$SESSION_ID"; then
                    # WIP check (advisory — claim is the real guard)
                    local wip_count
                    wip_count=$(bd list --status=in_progress --json 2>/dev/null | jq "[.[] | select(.assignee == \"$SESSION_ID\")] | length" 2>/dev/null) || wip_count=0
                    if [[ "$wip_count" -eq 0 ]]; then
                        local dispatch_result
                        dispatch_result=$(dispatch_attempt_claim "$SESSION_ID")
                        if [[ -n "$dispatch_result" ]]; then
                            local d_bead d_score
                            d_bead=$(echo "$dispatch_result" | cut -d'|' -f1)
                            d_score=$(echo "$dispatch_result" | cut -d'|' -f2)
                            dispatch_log "$SESSION_ID" "$d_bead" "$d_score" "claimed"
                            REASON="Self-dispatch: claimed $d_bead (score $d_score). Run /clavain:route $d_bead"
                            # REASON is set — falls through to the block output at end of script
                        fi
                    fi
                fi
            fi
        fi
    fi
fi
```

**Key: dispatch only emits REASON (and thus `block`) after confirmed successful claim.** All failure paths fall through silently, allowing lower-priority tiers (drift check) to fire if applicable.

**Tier ordering:** compound (>= 4) > dispatch (bead-closed + opt-in) > drift (>= 3). Dispatch takes priority over drift because completing the next bead is more valuable than checking doc staleness.

### Step 3: No hooks.json changes needed

Since dispatch is merged into auto-stop-actions.sh, no new hook registration is required.

### Step 4: Integration test

Manual validation:
1. Set `CLAVAIN_SELF_DISPATCH=true`
2. Create 3 open beads with different priorities (P0, P1, P2)
3. Close current bead → Stop hook fires → verify dispatch selects highest-scored ready bead
4. Verify `$HOME/.clavain/dispatch-log.jsonl` entry written with outcome=claimed
5. Verify WIP limit: if agent has in-progress bead, dispatch should not fire
6. Verify per-session cap: dispatch 5 beads → 6th dispatch should be blocked
7. Verify circuit breaker: stop Dolt → attempt dispatch → 3 failures → dispatch pauses → restart Dolt → next session dispatch works
8. Verify race handling: two agents close beads simultaneously → one claims top bead, other claims second bead (or silently exits)

## Estimated Scope

- lib-dispatch.sh: ~100 lines
- auto-stop-actions.sh changes: ~30 lines (dispatch tier)
- Total: ~130 lines of new code

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Stop hook timeout (10s) | Discovery scan is O(beads). Acceptable for <50 beads. Scale concern deferred to v2 |
| Stale discovery cache between scan and claim | Atomic claim is the real guard. Fresh re-scan on race loss |
| Priority starvation (P3/P4 beads never selected) | Known v1 limitation. Aging mechanism deferred to v2 |
| WIP check TOCTOU (two agents both see 0 WIP) | Advisory check only. Atomic claim prevents duplicate execution |
| Env var inherited by subagents | Document: set `CLAVAIN_SELF_DISPATCH` at top-level only |
| No factory-level circuit breaker without Batch 4 | Per-session cap (5 dispatches) + per-session circuit breaker provide local safety |

## Validation Criteria

Start 3 agents with `CLAVAIN_SELF_DISPATCH=true`, seed 10 open beads, observe autonomous claim+execute+close cycle for 2+ beads per agent. Verify no phantom dispatches (bead claimed_by matches executing agent).

## Review History

- 2026-03-20: flux-drive review (4 agents: architecture, correctness, safety, systems)
- P0 fixes applied: merged into auto-stop-actions.sh, no interphase modification, require bead-closed signal, block only after confirmed claim
- P1 fixes applied: circuit breaker counts only infra failures, per-session dispatch cap, fresh re-scan on race loss, home-rooted log path
- Deferred to v2: priority aging, cross-agent cooldown, O(n) scan optimization
