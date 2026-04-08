---
agent: fd-performance
plan: docs/plans/2026-04-05-cross-model-dispatch.md
date: 2026-04-05
---
# fd-performance Findings: Cross-Model Dispatch Plan

## F-P1 [P1] 30+ python3 subprocess spawns for 10-agent pool — cold-start overhead dominates

**Location:** Task 1.4 (`_routing_agent_field()`), Task 1.5 (`routing_adjust_expansion_tier()`)

For each agent in the expansion pool, `routing_adjust_expansion_tier()` calls `_routing_agent_field()` up to 3 times (max_model, domain_complexity, min_model). Each call:
1. Runs `_routing_find_roles_config()` equivalent (filesystem search)
2. Spawns `python3`
3. Imports PyYAML
4. Parses full agent-roles.yaml
5. Searches for agent name
6. Returns one field

Python 3 cold-start time on a typical system: 40-80ms. YAML parse for the ~80-line file: ~5ms. Total per call: ~50ms minimum.

For a 10-agent pool with 2 passes: 60 calls × 50ms = 3 seconds minimum. This is synchronous (cannot be parallelized within a bash function) and blocks Stage 2 dispatch.

The existing lib-routing.sh architecture solves exactly this problem: `_routing_load_cache()` parses agent-roles.yaml ONCE at startup into bash associative arrays. All subsequent lookups are O(1) array reads with no subprocess overhead.

**Impact:** Stage 2 dispatch latency increases by 1-6 seconds with the proposed implementation. For a pipeline where agents run for 60-120 seconds, this is a 1-5% overhead — noticeable but not catastrophic. However, it's architecturally wrong given the existing pattern.

**Fix:** Extend `_routing_load_cache()` to parse `domain_complexity` and `max_model` into `_ROUTING_SF_AGENT_DOMAIN_CX[]` and `_ROUTING_SF_AGENT_MAX_MODEL[]` arrays. Convert `_routing_agent_field()` to array lookups.

---

## F-P2 [P2] `find` glob fallback in `_routing_agent_field()` traverses entire plugin cache

**Location:** Task 1.4, file discovery fallback

```bash
roles_file=$(find ~/.claude/plugins/cache/*/interflux/*/config/flux-drive/agent-roles.yaml 2>/dev/null | head -1)
```

`~/.claude/plugins/cache/` contains cached versions of all installed plugins (potentially hundreds of directories). The glob `*/interflux/*/config/flux-drive/` requires `find` to stat every subdirectory. If the cache grows large (50+ plugins with nested structures), this glob can take 100-500ms even with SSD.

This fallback is only reached if `_routing_find_roles_config()` fails — which shouldn't happen in production. But if it does trigger, it's now the hot path for every `_routing_agent_field()` call.

**Fix:** If this fallback is needed at all, cache the result in a `declare -g _RAF_ROLES_FILE=""` variable so subsequent calls reuse the path without re-running `find`.

---

## F-P3 [P2] Two-pass budget accounting may undercount savings from first pass

**Location:** Task 3.1, step 3

The two-pass design computes:
```
adjusted_total = sum(cost_estimate(agent, tentative_adjustments[agent]) for agent in candidates)
```

The plan does not specify where `cost_estimate()` is implemented. If it calls into interstat (database query) or spawns a subprocess, the cost of computing the estimate may exceed the savings being computed. For a 10-agent pool, this is 10 cost estimates per pass × up to 2 passes = 20 lookups.

**Recommendation:** Specify that `cost_estimate()` should use the in-memory `agent_defaults` table from budget.yaml (already loaded), not a live interstat query. The budget.yaml `agent_defaults` values are exactly designed for this purpose.

---

## F-P4 [P3] Merit-order sort per run — negligible for pool sizes up to ~20 agents

**Location:** Task 2.2, pre-dispatch sort

Sorting 10-20 agents by 3 keys (score, priority, name) is O(n log n) with n ≤ 20. This is nanoseconds. No concern.

---

## F-P5 [P3] Calibration emit is append-only to log — no structured storage

**Location:** Task 4.2, calibration logging

Emitting one log line per adjusted agent is low volume. `grep cmd-calibration <logs>` on 1000 runs × 10 agents = 10,000 lines is fast. No concern for current scale.

However, if calibration data needs to be queried by multiple dimensions (agent × model × score × severity), a flat log is the right start but may need a parser later. This is V2 scope — acceptable.

## Summary

| ID | Severity | Topic |
|----|----------|-------|
| F-P1 | P1 | 30+ python3 spawns per 10-agent pool — should use existing cache pattern |
| F-P2 | P2 | `find` glob fallback may be slow if triggered; lacks path caching |
| F-P3 | P2 | `cost_estimate()` source unspecified — should use in-memory agent_defaults |
| F-P4 | P3 | Sort is negligible for current pool sizes |
| F-P5 | P3 | Calibration log is appropriate for V1; structured storage is V2 |
