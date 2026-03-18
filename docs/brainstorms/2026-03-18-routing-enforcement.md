# Routing Enforcement — Shadow→Enforce Promotion

**Beads:** Demarch-k2xf.5 (infrastructure) + Demarch-1x9l.2 (campaign)
**Date:** 2026-03-18

## Current State

B2 complexity routing is **fully implemented and wired**:
- `lib-routing.sh` classifies complexity from signals (prompt-tokens, file-count, reasoning-depth)
- `routing_resolve_agents` passes classified tier to `routing_resolve_model_complex`
- flux-drive launch.md measures signals and passes them to `routing_resolve_agents`
- Safety floors clamp fd-safety/fd-correctness to never drop below Sonnet
- routing.yaml has thresholds (C1-C5) and per-tier model overrides

**The only remaining step is flipping `mode: shadow` → `mode: enforce`.**

### What shadow mode does vs enforce
- **Shadow:** Classifies tier, logs `[B2-shadow] would change model: sonnet → haiku`, but applies B1 result
- **Enforce:** Classifies tier, applies complexity override (C1/C2→haiku, C4/C5→opus), clamps with safety floors

### Expected cost impact
- Baseline: $1.17/landable change (Opus is 95% of cost)
- C1/C2 tasks (simple/trivial) → Haiku instead of Sonnet: ~$0.003 per call vs ~$0.015
- C4/C5 tasks already get Opus via phase routing, so no change
- Net savings: depends on C1/C2 task proportion in flux-drive reviews

## What needs to happen

### 1. Shadow log aggregation (validate before enforce)
- Script that parses shadow logs from recent sessions
- Shows: tier distribution (how many C1, C2, C3, C4, C5)
- Shows: would-have-changed count and direction (upgrades vs downgrades)
- Purpose: sanity check before flipping to enforce

### 2. Flip mode to enforce
- Single line change in routing.yaml: `mode: shadow` → `mode: enforce`
- Add the shadow→enforce toggle as a routing.yaml config option (already exists, just change value)

### 3. Cost baseline (for campaign 1x9l.2)
- Capture pre-enforce cost via `cost-query.sh`
- After enforce: run same query, compute delta
- Metric: cost_per_landable_change (USD, lower_is_better)

## Risk

- **Low:** Safety floors protect critical agents (fd-safety, fd-correctness never below Sonnet)
- **Low:** C3 tier inherits B1 (no change for moderate tasks)
- **Reversible:** Flip back to `mode: shadow` instantly
- **Only downgrades affected:** C1/C2 → Haiku (trivial/simple tasks). If quality drops, shadow logs already tell us which agents were downgraded.

## Decision

Skip extended shadow log analysis — the infrastructure has been in shadow mode since March 14. The code paths are battle-tested through the test suite. Flip to enforce, monitor via interstat cost data, revert if quality metrics drop.
