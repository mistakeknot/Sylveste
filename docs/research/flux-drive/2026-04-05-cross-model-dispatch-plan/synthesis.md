---
artifact_type: flux-drive-synthesis
plan: docs/plans/2026-04-05-cross-model-dispatch.md
date: 2026-04-05
agents: [fd-correctness, fd-safety, fd-architecture, fd-quality, fd-performance]
---
# Flux-Drive Review Synthesis: Cross-Model Dispatch Plan

## Severity Summary

| Severity | Count | Agents |
|----------|-------|--------|
| P0 | 0 | — |
| P1 | 12 | C1-C3, S1-S3, A1-A3, Q1-Q3 |
| P2 | 10 | C5-C6, S4-S5, A4-A6, Q4-Q6, P2-P3 |
| P3 | 6 | C4, C7, S6, A7, Q7, P4-P5 |
| **Total** | **28** | |

No P0 findings. The plan is architecturally sound and the PRD coverage is complete. However, **three structural P1 clusters** must be resolved before implementation begins.

---

## P1 Cluster 1: `_routing_agent_field()` must not duplicate existing infrastructure

**Findings:** F-C1, F-A1, F-A4, F-P1, F-S1

The plan introduces `_routing_agent_field()` as a standalone function that:
1. Re-implements file discovery (`_routing_find_roles_config()` already exists)
2. Spawns python3 per call (`_routing_load_cache()` already parses agent-roles.yaml into bash arrays)
3. Reads `min_model` from disk (`_ROUTING_SF_AGENT_MIN[]` cache already has this)

**Convergence across all 5 agents:** This is the most over-specified finding in the review. The correct implementation extends `_routing_load_cache()` to parse two additional fields into two new arrays:
```bash
declare -gA _ROUTING_SF_AGENT_DOMAIN_CX=()   # new
declare -gA _ROUTING_SF_AGENT_MAX_MODEL=()    # new
```
`_routing_agent_field()` then becomes a 3-line lookup function with no subprocess. This also resolves F-S1 (constitutional floor uses same cache as safety floor), F-P1 (no subprocess overhead), and F-A4 (no parallel parse path inconsistency).

**Additionally:** The constitutional floor step in `routing_adjust_expansion_tier()` (Task 1.5 step 3) is **redundant** — the safety floor step (step 5) already enforces `min_model` from the same cache. Consider removing the constitutional floor step and let safety floor handle it, or document explicitly that constitutional floor runs early (before budget pressure) as an intentional ordering decision.

---

## P1 Cluster 2: Shell injection in python3 string interpolation

**Finding:** F-C3 (fd-correctness), F-S2 reinforces (PyYAML dependency)

Task 1.4's python3 inline script interpolates `$short_name` and `$field` directly into the Python source code. Agent names are normally safe but there is no validation. Beyond injection risk, the PyYAML dependency (F-S2) means a missing `python3-yaml` package silently disables constitutional floors and the feature gate without any warning.

**Recommended resolution:**
- Fix the subprocess approach: pass values via environment variables not string interpolation
- Add a startup check: `python3 -c "import yaml" 2>/dev/null || echo "[routing] WARN: PyYAML unavailable" >&2`
- Better: eliminate the python3 subprocess entirely by using the cache (resolves both issues)

---

## P1 Cluster 3: Missing pieces in the plan that block implementation

**Findings:** F-A2 (broken Step 2.0.5 reference), F-A3 (build order gap), F-Q1 (no test fixture setup), F-Q2 (missing test case), F-Q3 (F2 verification insufficient)

Three "missing pieces" that would block a clean implementation:

1. **F-A2:** Task 3.1 references `model_map[agent] # from Step 2.0.5`. Step 2.0.5 does not exist in expansion.md. This must be added or the reference must be replaced with the actual mechanism (the model resolved by `routing_resolve_agents` before Stage 2 dispatch).

2. **Build/test gaps (F-A3, F-Q1):** No test fixture setup instructions. Integration tests will silently pass with wrong behavior if F4 fields aren't in agent-roles.yaml. The plan should specify `CLAVAIN_ROLES_CONFIG=test-fixture.yaml` for unit tests.

3. **F-Q3:** F2 verification is "manual." For a scoring algorithm change that affects dispatch decisions, this is insufficient. A deterministic input-output table or Python unit test should be specified.

---

## Notable P2 Findings

**F-S3 (Two-pass oscillation):** The 2-pass cap does not guarantee the second pass result is better than the first. If pass 1 computes "low pressure" → no downgrades → revised pressure = "high", pass 2 applies high pressure downgrades. This is a ratchet toward over-downgrading. Fix: only apply pass 2 if pass 1 result exceeds the budget; otherwise use pass 1 result.

**F-A5 (Deduplication changes expansion decision threshold):** The new deduplication algorithm can reduce scores that previously triggered expansion. Edge cases where the old algorithm scored 2 (OFFER) might now score 1 (RECOMMEND STOP) if contributions share a source_id. Add a validation table for edge cases.

**F-A6 (Speculative discount is always a no-op):** `max(score - 1, 1)` applied to score=3 (the only trigger) always yields 2 = "keep model." The discount effectively means speculative launches never get tier-adjusted. Either document this as intentional or change the discount to `max(score - 1, 0)` and let score=2 trigger a conditional downgrade based on domain complexity.

**F-Q6 (F4 YAML sketch omits experiments section):** The plan's YAML sketch for agent-roles.yaml could be misread as a complete replacement. Make clear it's an edit to the `roles:` block only.

---

## PRD Acceptance Criteria Coverage

| Feature | Plan Coverage | Gaps |
|---------|---------------|------|
| F1 | Full | PRD AC "local unchanged" vs plan's local downgrade (F-C2) |
| F2 | Full | Deduplication edge cases not validated (F-A5) |
| F3 | Full | Step 2.0.5 reference broken (F-A2); speculative discount no-op (F-A6) |
| F4 | Full | max_model per-role vs per-agent wording mismatch (F-Q5) |
| F5 | Full | Constitutional floor status missing from dispatch log (F-C6) |

No features are unimplemented. All PRD ACs have corresponding plan tasks. The gaps are in correctness of implementation details, not coverage.

---

## Backward Compatibility of expansion.md Changes

The expansion.md modifications (Tasks 2.1-2.3, Task 3.1) replace the expansion scoring algorithm and Step 2.2c. Key backward compatibility analysis:

- **Scoring change (Task 2.1):** Old scores ≥ 3 map to new score = 3 (capped). Old scores of 2 may reduce to 1 after deduplication — this could change OFFER → RECOMMEND STOP. Backward incompatible in edge cases. Requires validation.

- **Step 2.2c replacement (Task 3.1):** The shadow mode ensures no behavioral change until `mode: enforce`. The disabled path (`cmd_enabled == "false"`) preserves existing dispatch behavior exactly. Backward compatible behind the gate.

- **Merit-order sort (Task 2.2):** Only affects dispatch order within a pool, not which agents dispatch. Backward compatible.

- **Domain intersection check (Task 2.3):** New check can cap an agent's tier at haiku that previously had no cap. Can reduce quality when it fires. Needs validation that "no overlap" detection is correct before enabling enforce mode.

---

## Recommended Pre-Implementation Actions

1. **Resolve F-C2:** Align PRD AC "local models" behavior with plan's downgrade implementation (one sentence fix).
2. **Redesign `_routing_agent_field()`:** Extend `_routing_load_cache()` instead of a new subprocess function. This closes F-C1, F-C3, F-S1, F-S2, F-A1, F-A4, F-P1, F-P2 in one architectural change.
3. **Add Step 2.0.5 to expansion.md** or clarify the model_map source (F-A2).
4. **Add test fixture setup instructions** to the verification strategy (F-Q1).
5. **Add deterministic F2 scoring unit test** to replace "manual" verification (F-Q3).
6. **Add missing test case** for score=3 + max_model=haiku (F-Q2).
7. **Fix two-pass logic** to prefer pass 1 result when pass 1 stays within budget (F-S3).
