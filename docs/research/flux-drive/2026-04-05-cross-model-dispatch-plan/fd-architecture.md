---
agent: fd-architecture
plan: docs/plans/2026-04-05-cross-model-dispatch.md
date: 2026-04-05
---
# fd-architecture Findings: Cross-Model Dispatch Plan

## F-A1 [P1] `_routing_agent_field()` spawns 3 python3 processes per agent — O(n) subprocesses

**Location:** Task 1.4, `_routing_agent_field()`; Task 1.5, `routing_adjust_expansion_tier()`

`routing_adjust_expansion_tier()` calls `_routing_agent_field()` three times:
1. For `max_model` (score=3 upgrade block)
2. For `domain_complexity` (score=1 skip block)
3. For `min_model` (constitutional floor block)

Each call forks a new `python3` process, waits for startup, parses agent-roles.yaml, and exits. For a 10-agent Stage 2 pool: 30 python3 processes sequentially (or in the two-pass case, up to 60). At ~50-100ms each, this adds 1.5-6 seconds of latency before Stage 2 dispatch.

The existing architecture already solved this: `_routing_load_cache()` parses agent-roles.yaml once at startup into bash associative arrays (`_ROUTING_SF_AGENT_MIN[]`). The proposed design ignores this pattern and introduces a new per-call parse path.

**Fix:** Extend `_routing_load_cache()` to also parse `domain_complexity` and `max_model` into new arrays:
```bash
declare -gA _ROUTING_SF_AGENT_DOMAIN_CX=()   # [agent]=low|medium|high
declare -gA _ROUTING_SF_AGENT_MAX_MODEL=()    # [agent]=haiku|sonnet|opus (optional)
```
Then `_routing_agent_field()` becomes a simple array lookup instead of a subprocess. The parser already iterates role-level fields — adding two more is trivial.

---

## F-A2 [P1] Missing reference: Task 3.1 refers to `model_map[agent] # from Step 2.0.5` — Step 2.0.5 does not exist in expansion.md

**Location:** Task 3.1, Step 2.2c dispatch integration

The plan says:
```
original_model = model_map[agent]  # from Step 2.0.5
```

The current expansion.md only contains Steps 2.2a.5, 2.2a.6, 2.2b, and 2.2c. There is no Step 2.0.5 in the existing file or in this plan. This reference is broken.

**Consequence:** Implementers reading the plan won't know where `model_map` comes from or how it's populated. This is a critical gap — without the model map, the "original model" for each agent is undefined.

**Fix:** Either:
(a) Add a Task that creates Step 2.0.5 in expansion.md, specifying that before Stage 2 dispatch the model map is computed using `routing_resolve_agents` or equivalent.
(b) Clarify in Task 3.1 that `model_map` refers to the model resolved during agent-pool initialization (the same model used in existing Step 2.2c dispatch) and add a Task to explicitly define it.

---

## F-A3 [P1] Build order gap: no Task to verify F4 fields exist before F1 integration tests

**Location:** Phase ordering, Task 1.5 integration test

The plan says "F4 and F1 can be done in a single pass since F1's unit tests can stub agent-roles data." But Task 1.5's `routing_adjust_expansion_tier()` reads `domain_complexity` and `min_model` from agent-roles.yaml via `_routing_agent_field()`. Without F4's fields being present:

- `domain_complexity` returns empty → treated as "low" → score=1 downgrades always happen
- `max_model` returns empty → upgrades always allowed for checkers

Integration tests (as opposed to unit tests that stub) will silently pass with wrong behavior if F4 hasn't been applied first.

**Fix:** Add explicit ordering note: "F4 must be committed to agent-roles.yaml before running integration tests for Task 1.5. Unit tests may stub via `CLAVAIN_ROLES_CONFIG=/path/to/test-fixture.yaml`."

---

## F-A4 [P2] `_routing_agent_field()` constitutional floor check inconsistent with safety floor cache

**Location:** Task 1.5, step 3 vs step 5

Step 3 (constitutional floor) calls `_routing_agent_field "$agent" "min_model"` which reads from disk via python3.
Step 5 (safety floor) calls `_routing_apply_safety_floor "$agent" "$model" "expansion"` which reads from `_ROUTING_SF_AGENT_MIN[]` cache (populated at startup).

These two sources can diverge if agent-roles.yaml is modified between `_routing_load_cache()` running (startup) and `routing_adjust_expansion_tier()` running (during Stage 2 dispatch). This is unlikely in practice but architecturally unsound: the same field (`min_model`) is read twice via different mechanisms.

Furthermore: the existing safety floor in step 5 already enforces `min_model`. Step 3's constitutional floor check for `min_model` is therefore REDUNDANT — the safety floor in step 5 will catch any constitutional floor violation that step 3 missed (or that step 3 wrongly applied). The constitutional floor step adds complexity without adding safety.

**Recommendation:** Remove step 3 (constitutional floor check) from `routing_adjust_expansion_tier()`. Let the safety floor in step 5 handle `min_model` enforcement (it already does). The constitutional floor concept is valid but is already implemented by the safety floor mechanism. If the intent is to apply `min_model` BEFORE budget pressure (not after), then the constitutional floor should be applied after score adjustment but before the budget pressure step — and it should use the cache, not python3.

---

## F-A5 [P2] Expansion scoring algorithm change (Task 2.1) may change expansion DECISION threshold

**Location:** Task 2.1, deduplication semantics

Current algorithm: `expansion_score` can exceed 3 (P0=3 + P1=2 + disagree=2 = 7 for one agent).
New algorithm: deduplication + `min(sum, 3)` caps at 3.

For the expansion DECISION table (Step 2.2b), this matters:
- A case that previously scored 5 (→ RECOMMEND) now scores 3 (→ RECOMMEND). Same outcome.
- A case that previously scored 2 (→ OFFER) — e.g., P1 from adjacent + disagree — now after deduplication might score max 3. But if deduplication reduces it (same source for both contributions), it could score 1 (→ RECOMMEND STOP).

The concern: deduplication could REDUCE scores that previously triggered OFFER or RECOMMEND. An implementer needs to verify the new algorithm produces correct decisions for edge cases.

**Fix:** Add a table of example scenarios to Task 2.1 showing how the new algorithm handles cases that were previously borderline (score = 2 or 3).

---

## F-A6 [P2] F3 speculative score discount semantic: `max(score-1, 1)` always yields "keep model"

**Location:** Task 3.2, speculative launches

Step 2.2a.6 only launches speculatively when `expansion_score >= 3`. So effective_score = max(3-1, 1) = 2. Score=2 maps to "keep model" in `routing_adjust_expansion_tier()`. This means the tier adjustment function is called but always returns the original model for speculative launches.

This may be intentional ("speculative launches use safe conservative tiers"), but the code path (calling `routing_adjust_expansion_tier()` to get back the same model) adds complexity with no effect when score starts at exactly 3. Only a score=4+ source (impossible with the new capped algorithm) would produce a discount that triggers an upgrade at 3.

**Fix:** Either document explicitly that "speculative launches always dispatch at original model (discount ensures score=2=no-adjust)" or reconsider the discount. If score=3 speculative launches should still get an upgrade, the discount should not reduce to 2.

---

## F-A7 [P3] `_routing_agent_field()` has no caching for repeated calls

Even if the subprocess overhead is acceptable, calling `_routing_find_roles_config()` (or its inline equivalent) on each call to `_routing_agent_field()` re-searches the filesystem. A simple `declare -g _RAF_ROLES_FILE=""` cached path variable would prevent redundant filesystem searches across calls within the same shell process.

## Summary

| ID | Severity | Topic |
|----|----------|-------|
| F-A1 | P1 | 30 python3 subprocesses per 10-agent pool — should extend existing cache |
| F-A2 | P1 | Broken reference to non-existent Step 2.0.5 in expansion.md |
| F-A3 | P1 | Build order gap: integration tests silently wrong if F4 not applied first |
| F-A4 | P2 | Constitutional floor redundant with safety floor; uses inconsistent data source |
| F-A5 | P2 | Deduplication can reduce borderline scores — edge cases not validated |
| F-A6 | P2 | Speculative score discount always yields "keep model" — call may be no-op |
| F-A7 | P3 | `_routing_agent_field()` lacks path caching for repeated calls |
