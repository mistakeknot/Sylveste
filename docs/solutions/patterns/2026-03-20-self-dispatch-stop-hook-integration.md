---
artifact_type: reflection
bead: Demarch-ysxe.3
stage: reflect
category: patterns
tags: [hooks, dispatch, architecture, concurrency]
---

# Self-Dispatch: Stop Hook Integration Pattern

## What happened

Built the self-dispatch loop (ysxe.3) — agents autonomously claim beads after completing work. The original plan called for a separate `self-dispatch.sh` Stop hook. Four-agent flux-drive review (architecture, correctness, safety, systems) identified that this would conflict with the existing `INTERCORE_STOP_DEDUP_SENTINEL` architecture.

## Key learnings

### 1. Stop hooks are mutually exclusive by design
The shared `stop` sentinel enforces one blocking action per stop cycle. Adding a second Stop hook either competes for the sentinel or bypasses it — both cause problems. The solution was merging dispatch as a tier inside `auto-stop-actions.sh`, following the precedent of the compound+drift merge (iv-rn81).

### 2. `intercore_check_or_die` vs `intercore_sentinel_check_or_legacy`
`check_or_die` exits the entire script on throttle — fine for mutually exclusive `if/elif` tiers, but breaks cascading tiers where one throttled tier should fall through to the next. Changed to `sentinel_check_or_legacy` (returns 1) for proper cascade.

### 3. Dispatch-specific scoring belongs in the dispatch hook, not the shared scorer
`score_bead()` in interphase is used by `/lfg`, session-start, and other consumers. Adding deps-ready and WIP-balance to the shared scorer would add noise to human-facing discovery. Dispatch scoring is a local re-scoring pass in `lib-dispatch.sh`.

### 4. Only emit `block` after confirmed claim
The most dangerous bug identified was phantom dispatch — emitting a `block` decision for a bead the agent doesn't own. Every exit path that doesn't hold a confirmed claim must be silent (`exit 0`).

### 5. Circuit breaker must distinguish race losses from infra failures
Claim races are expected under multi-agent load. Counting them as failures trips the circuit breaker during normal operation. Only infrastructure errors (bd unavailable, discovery scan failure) count.

### 6. Bash integer overflow in jitter calculation
`BASHPID * 31337` overflows 32-bit signed int at high PIDs, producing negative values that make `sleep` fail. Use modulo-clamped arithmetic: `(RANDOM + (BASHPID % 1000)) % 400 + 100`.

## Pattern: Tiered Stop Hook Actions

When adding a new action to the Stop hook:
1. Add as a tier in `auto-stop-actions.sh`, NOT as a separate hook
2. Use `intercore_sentinel_check_or_legacy` for tier-specific cooldown (not `check_or_die`)
3. Check `REASON=""` to determine if a higher-priority tier already claimed the cycle
4. Set `REASON` only on confirmed success; all failure paths fall through silently
