---
agent: fd-safety
plan: docs/plans/2026-04-05-cross-model-dispatch.md
date: 2026-04-05
---
# fd-safety Findings: Cross-Model Dispatch Plan

## F-S1 [P1] `_routing_agent_field()` bypasses the existing `_ROUTING_SF_AGENT_MIN[]` cache

**Location:** Task 1.4 and Task 1.5, constitutional floor check

The existing `_routing_load_cache()` (line 427 in lib-routing.sh) already parses `min_model` from agent-roles.yaml into the `_ROUTING_SF_AGENT_MIN[]` associative array during startup. `_routing_apply_safety_floor()` uses this cache exclusively.

Task 1.5 step 3 reads `min_model` again via `_routing_agent_field "$agent" "min_model"` — a fresh `python3` subprocess that re-reads and re-parses agent-roles.yaml. This means:

1. The constitutional floor reads a potentially stale on-disk version of agent-roles.yaml if the file was hot-modified during a run.
2. The safety floor in step 5 uses the cached `_ROUTING_SF_AGENT_MIN[]` which reflects the startup state.
3. If the file changes between startup and tier adjustment, constitutional and safety floors could have different values for the same agent.

**More critically:** If `_routing_load_cache()` has NOT been called (e.g., in unit tests that source lib-routing.sh without loading config), `_routing_apply_safety_floor()` silently skips the floor (no cache entry). But `_routing_agent_field()` would still find the file and apply constitutional floor correctly. This inconsistency makes safety invariants harder to reason about.

**Fix:** The constitutional floor in step 3 should read from the same cache: `${_ROUTING_SF_AGENT_MIN[$agent_short]:-}`. If the cache isn't populated, call `_routing_load_cache` first. This eliminates the parallel parse path and keeps both floors synchronized.

---

## F-S2 [P1] PyYAML (`import yaml`) may not be available in all environments

**Location:** Task 1.4, python3 inline script; Task 3.1, feature gate reading

The plan uses `python3 -c "import yaml"` in two places:
- `_routing_agent_field()` — reads agent-roles.yaml fields
- Task 3.1 feature gate check — reads budget.yaml for `cross_model_dispatch.enabled`

PyYAML is not in the Python standard library. It must be installed separately (`pip install pyyaml` or system package `python3-yaml`). The error behavior is `2>/dev/null` suppression with fallback to empty string, meaning:

- If PyYAML is missing, `_routing_agent_field()` always returns empty
- Constitutional floor is silently skipped (min_model returns empty)
- Feature gate always reads as "false" (disabled)
- Score=3 upgrades always succeed (no max_model ceiling found)
- Score=1 downgrades always happen (no domain_complexity=high protection)

**Consequence:** A missing PyYAML dependency silently degrades correctness without any warning. The safety invariant "constitutional floor enforced" is violated silently.

**Fix:** Either (a) use Python's built-in `re` or line-by-line parsing (no deps) for the simple YAML structures needed, or (b) add an explicit check: `python3 -c "import yaml" 2>/dev/null || { echo "[routing] WARN: PyYAML not available — constitutional floors inactive" >&2; }` at library load time.

---

## F-S3 [P1] Two-pass cap does not guarantee convergence — second pass can destabilize

**Location:** Task 3.1, step 3

"If `revised_pressure_label` differs from `pressure_label`, run a second pass with the revised pressure. Cap at 2 passes to prevent oscillation."

The 2-pass cap prevents infinite loops but does not guarantee the result is better than the 1-pass result. Consider:

- Pass 1 with "low" pressure: 0 downgrades, cost stays high → revised pressure = "high"
- Pass 2 with "high" pressure: many downgrades, cost drops → revised pressure would be "low" again

After 2 passes, we've committed to the "high pressure" result even though a third pass would revert it. This is a ratchet that can drive the pool to over-downgrade.

**More specifically:** The plan applies pass 2 with the pressure computed from pass 1's tentative adjustments. But pass 2 might produce MORE downgrades than warranted by the actual budget situation after pass 1 savings are realized.

**Fix:** After 2 passes, take the result that satisfies the budget constraint (not necessarily the most recent pass). If pass 1 stays within budget, use pass 1 result even if pressure changed. Only use pass 2 if pass 1 results violate the budget.

---

## F-S4 [P2] Downgrade cap "restore lowest-scored" has unclear semantics when scores tie

**Location:** Task 3.1, step 4

"Restore lowest-scored agents to original model until `downgraded_count <= max_downgrades`"

In merit order (sorted by score DESC), the agents processed last have the lowest scores. "Lowest-scored agents" in this context means the last processed. If multiple agents tie at score=1 (all checkers), "lowest scored" is ambiguous — which ones get restored?

**Consequence:** Determinism depends on the stable tiebreaker (name ASC). The current specification implies restoring the alphabetically last agents first. This is consistent with merit order but should be made explicit.

**Recommendation:** Clarify "lowest-scored" as "last processed in merit order (i.e., lowest expansion_score, then highest name alphabetically)."

---

## F-S5 [P2] Pool-level assertion can be violated if all planners/reviewers were dropout-pruned

**Location:** Task 3.1, step 6

"If `planner_reviewer_at_sonnet == 0`, upgrade highest-scored planner/reviewer to sonnet."

But if all planner/reviewer agents were pruned by AgentDropout before reaching Stage 2 dispatch, there are no planners/reviewers in the pool to upgrade. The assertion would set `planner_reviewer_at_sonnet = 0` but the upgrade step would find no candidates.

The `fd-safety` and `fd-correctness` agents are EXEMPT from dropout and both have `min_model: sonnet`. So in practice they always survive to Stage 2. But the plan should explicitly handle the edge case: "If no planner/reviewer agents exist in the pool, skip pool assertion (only editors/checkers present — assertion not applicable)."

---

## F-S6 [P3] Budget pressure "speculative reserve subtracted" double-counts for speculative agents

**Location:** Task 3.1, step 1 (budget pressure) and Task 3.2 (speculative launches)

Task 3.1 computes:
```
speculative_reserve = incremental_expansion.max_speculative × agent_defaults.review
effective_budget = remaining_budget - speculative_reserve
```

If speculative agents have ALREADY been launched (Task 3.2 fired during Stage 1), `remaining_budget` has already been reduced by their actual cost. Subtracting `speculative_reserve` again double-counts.

**Fix:** Only subtract speculative_reserve if speculative launches haven't fired yet. Check: `if speculative_launch_count == 0: effective_budget -= speculative_reserve`.

## Summary

| ID | Severity | Topic |
|----|----------|-------|
| F-S1 | P1 | Constitutional floor bypasses `_ROUTING_SF_AGENT_MIN[]` cache — parallel parse path |
| F-S2 | P1 | PyYAML missing silently disables constitutional floors and feature gate |
| F-S3 | P1 | Two-pass cap can over-downgrade — not stability-guaranteed |
| F-S4 | P2 | Downgrade cap restore semantics ambiguous on score ties |
| F-S5 | P2 | Pool assertion has no candidate if all planners/reviewers dropout-pruned |
| F-S6 | P3 | Speculative reserve double-counted if speculative agents already launched |
