---
agent: fd-quality
plan: docs/plans/2026-04-05-cross-model-dispatch.md
date: 2026-04-05
---
# fd-quality Findings: Cross-Model Dispatch Plan

## F-Q1 [P1] F1 verification lacks test fixture setup instructions

**Location:** Verification Strategy, F1 row

The plan says "Bash unit test: source lib-routing.sh, call `routing_adjust_expansion_tier` with known inputs." But:

1. `lib-routing.sh` sources a routing.yaml config at load time via `_routing_load_cache()`. Without a test fixture, the unit test will fail to find a config or load a production config.
2. `_routing_agent_field()` calls python3 to read agent-roles.yaml. Without `CLAVAIN_INTERFLUX_CONFIG` set to a test fixture, it will search the filesystem and either find the production file or return empty values.
3. Safety floors from `_routing_apply_safety_floor()` depend on `_ROUTING_SF_AGENT_MIN[]` which is populated by `_routing_load_cache()`.

**Missing from the plan:**
- How to set up test fixtures (minimal routing.yaml + agent-roles.yaml with test data)
- How to set env vars to isolate the test from production configs (`CLAVAIN_ROUTING_CONFIG`, `CLAVAIN_INTERFLUX_CONFIG` or `CLAVAIN_ROLES_CONFIG`)
- Whether to call `_routing_load_cache` before tests or stub the cache arrays directly

**Fix:** Add a "Test setup" subsection to F1 verification:
```bash
# Test fixture setup
export CLAVAIN_ROUTING_CONFIG=/tmp/test-routing.yaml
export CLAVAIN_ROLES_CONFIG=/tmp/test-agent-roles.yaml
# Create minimal fixtures with known domain_complexity and min_model values
# Then source lib-routing.sh and call _routing_load_cache
```

---

## F-Q2 [P1] F1 test matrix missing: score=3 with `max_model=haiku` ceiling

**Location:** Verification Strategy, F1 row; PRD F1 AC

PRD F1 AC: "Score=3 upgrades haiku→sonnet for agents **without** max_model=haiku ceiling"

The plan's F1 verification lists "score=3 upgrade" but does not list "score=3 + max_model=haiku → no upgrade." This is an explicit AC from the PRD that is missing from the test matrix.

The logic to test:
- A checker with `max_model: haiku` at model=haiku and score=3 → should stay at haiku
- A checker without `max_model` at model=haiku and score=3 → should upgrade to sonnet
- A checker with `max_model: sonnet` at model=haiku and score=3 → should upgrade to sonnet

All three cases exercise different branches of the ceiling check in Task 1.5.

---

## F-Q3 [P1] F2 verification "manual" is insufficient for a scoring algorithm change

**Location:** Verification Strategy, F2 row

"Manual: run flux-drive on a test document, verify logs show deduplicated scores, sorted candidates, domain intersection checks."

This is the weakest verification in the plan. The expansion scoring change (deduplication + source IDs) affects which agents get dispatched and at what tier. A manual test:
- Cannot guarantee all edge cases are covered
- Cannot verify deduplication is correct without knowing exactly which findings the test document produces
- Is not reproducible (different test documents produce different findings)

**Fix:** Add a deterministic unit test for the expansion scoring algorithm:
```python
# Given: mock Stage 1 findings with known domains and severities
# Assert: expansion_scores are as expected with and without deduplication
# Assert: the same source_id does not contribute twice
# Assert: final score is capped at 3
```
This could be a Python script that imports the scoring logic, or a documented table of expected scores for known input patterns.

---

## F-Q4 [P2] Upgrade pass semantics undefined when highest-scored score=2 agent is already at opus

**Location:** Task 3.1, step 5

"Find highest-scored score=2 agent that was NOT upgraded. Upgrade one tier: haiku→sonnet or sonnet→opus."

If the eligible agent is already at opus (score=2, original_model=opus), there is no tier above opus to upgrade to. The plan does not specify whether to:
(a) Skip the upgrade pass silently
(b) Try the next highest-scored agent
(c) Return "savings" to budget without recycling

**Fix:** Add a clause: "If the candidate is already at opus (or max_model ceiling prevents upgrade), try the next highest-scored score=2 agent. If no upgradeable candidate exists, skip the upgrade pass and retain savings in budget."

---

## F-Q5 [P2] F4 AC says `max_model` added "per agent" — plan adds it per role (checker role only)

**Location:** Task 1.1, agent-roles.yaml YAML sketch; PRD F4 AC

PRD F4 AC: "`max_model: haiku|sonnet|opus|null` added per agent (optional ceiling)"

The plan adds `max_model: sonnet` only to the checker role. Planner, reviewer, and editor roles have no `max_model` field (implicitly null/no ceiling).

This is CORRECT behavior (planners/reviewers/editors should not have ceilings). But:
1. The AC says "per agent" which implies it should be explicitly set for all agents (even if null).
2. The header comment says "If absent, no ceiling is enforced" — which is correct — but the PRD AC implies all agents should have the field.

**Recommendation:** Either update the PRD AC to say "per role (optional)" or add explicit `max_model: null` comments for planner/reviewer/editor roles to make the intent unambiguous.

---

## F-Q6 [P2] F4 edit doesn't preserve existing file structure

**Location:** Task 1.1, agent-roles.yaml modification

The plan shows a YAML sketch for the modified agent-roles.yaml. The current file has an `experiments:` section (lines 54-74 in the actual file) that the plan's sketch omits. If an implementer overwrites the file using the plan's sketch as a template, the experiments section would be lost.

The plan says "Add two new fields per agent in the existing roles structure" (not replace), but the YAML sketch could be misread as a complete file replacement.

**Fix:** Make the task description explicit: "Edit existing `roles:` block only. Do not modify the `experiments:` section. The YAML snippet above shows only the changed section."

---

## F-Q7 [P3] F3 integration test doesn't specify what a "different model" means for success

**Location:** Verification Strategy, integration test item 1

"Stage 2 agents receive different models based on expansion score"

This is ambiguous. "Different" from what? From each other? From Stage 1? From the original pre-adjustment model? The test needs to specify: "At least one agent receives a different model than it would have received without cross-model dispatch active."

## Summary

| ID | Severity | Topic |
|----|----------|-------|
| F-Q1 | P1 | F1 verification missing test fixture setup instructions |
| F-Q2 | P1 | F1 test matrix missing score=3 + max_model=haiku ceiling case |
| F-Q3 | P1 | F2 verification "manual" insufficient for scoring algorithm change |
| F-Q4 | P2 | Upgrade pass undefined when eligible agent already at opus |
| F-Q5 | P2 | F4 AC "per agent" vs plan's "per role" — add explicit null for planner/reviewer |
| F-Q6 | P2 | agent-roles.yaml YAML sketch omits experiments section — edit scope unclear |
| F-Q7 | P3 | Integration test success criterion for "different models" is ambiguous |
