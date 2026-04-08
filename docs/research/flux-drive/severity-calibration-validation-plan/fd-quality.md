---
agent: fd-quality
status: NEEDS_ATTENTION
finding_count: 6
---

## Findings

### [P1] Pass criterion tests the wrong thing — it validates triage, not calibration

**File:** /home/mk/projects/Sylveste/docs/plans/2026-03-29-severity-calibration-validation-plan.md
**Lines:** 63-66
**Issue:** Task 3's pass criterion is "≥1 generated (non-core) agent produces a P0 or P1 finding referencing a real flaw in the test content." This condition can be satisfied by an agent with no `## Severity Calibration` section at all — the fallback path in `_render_severity_calibration()` also produces agents that can label findings P0/P1. A generated agent using the generic fallback (v4 tag, no structured examples) could satisfy the criterion. If the LLM skips `severity_examples` (the acknowledged risk in the plan), the plan passes anyway as long as the agent finds a flaw at any severity.

The plan is trying to validate that structured `severity_examples` improve calibration, but the pass criterion does not require the finding to come from a v5 agent. The two tasks are linked in prose ("generated agent") but the check at line 66 only tests for `name NOT in CORE_AGENTS`, which is true for both v4 and v5 generated agents.

**Fix:** Split the pass criterion into two conditions:
1. (structural) The finding agent has `flux_gen_version: 5` in its frontmatter — confirming a v5 agent was dispatched.
2. (behavioral) That v5 agent produced a P0 or P1 finding citing one of the three deliberate flaws.

Both conditions must hold for the test to be considered a pass. Add an explicit check step: read the frontmatter of the dispatched agent before declaring success.

---

### [P1] No baseline to distinguish severity calibration signal from default behavior

**File:** /home/mk/projects/Sylveste/docs/plans/2026-03-29-severity-calibration-validation-plan.md
**Lines:** 55-66
**Issue:** The plan runs flux-drive once and checks for a P0/P1 finding. There is no control run — no evidence that the same content reviewed by a v4 agent (or a core agent like `fd-correctness`, which has its own severity section) would produce a different outcome. Without a control, a passing result cannot be attributed to the `severity_examples` calibration. Core agents already understand Go error handling and goroutine leaks. The flaws chosen are canonical, high-confidence P0 patterns that any reasonably prompted agent would flag correctly.

**Fix:** Add a control step: run the same fixture through `fd-correctness` (a core agent with no task-specific calibration) and note its severity labels for the same findings. If the core agent also produces P0/P1 for the identical flaws, the signal is weak. The interesting validation question is whether a v5 generated agent applied to subtler flaws — or correctly escalates something that a v4 agent labels P2 — shows calibration influence. The current test fixture makes the control redundant, but the plan should acknowledge this limitation explicitly.

---

### [P2] Version-gate behavior in `render_agent()` is untested by the plan

**File:** /home/mk/projects/Sylveste/docs/plans/2026-03-29-severity-calibration-validation-plan.md
**Lines:** 38-52
**Issue:** Task 2 verifies the generated agent has `flux_gen_version: 5` and a `## Severity Calibration` section with structured scenarios. This is correct. However, the plan does not test the negative path: if the LLM omits `severity_examples` from its output, `render_agent()` should emit `flux_gen_version: 4` (not 5), and the section should fall back to the generic text. The plan mentions this as a risk but does not include a verification step for it.

From the implementation at line 155-158 of generate-agents.py:
```python
has_severity = bool(severity_examples and isinstance(severity_examples, list))
effective_version = FLUX_GEN_VERSION if has_severity else 4
```
This branch is the critical version-gate. If it silently emits v4 and the plan only checks for presence of a `## Severity Calibration` section (which the fallback also renders), Task 2's pass check would not catch the regression.

**Fix:** Add a step to Task 2: inspect the raw `severity_examples` field in the saved spec JSON to confirm it contains actual structured objects, not just that the rendered section exists. The rendered section exists regardless of version — the spec JSON is the ground truth for whether the LLM populated the field.

---

### [P2] Test fixture flaws are maximally obvious — they may inflate confidence

**File:** /home/mk/projects/Sylveste/docs/plans/2026-03-29-severity-calibration-validation-plan.md
**Lines:** 27-35
**Issue:** The three chosen flaws (missing transaction, goroutine leak, discarded error) are among the most well-known Go anti-patterns. Any LLM-based review agent, regardless of calibration, will flag these. The validation therefore demonstrates "agents can find obvious issues" rather than "severity calibration prevents under-escalation of domain-specific risks."

The harder calibration problem is distinguishing P0 from P1 in ambiguous cases — e.g., an error that is silently swallowed but only in a non-critical path, or a goroutine leak that only manifests under specific load. The current fixture cannot distinguish "agent flagged P0 because calibration trained it to" from "agent flagged P0 because the flaw screams P0 to any LLM."

**Fix:** Include at least one ambiguous flaw alongside the clear P0s — for example, a retried operation that logs but does not return an error on second failure, where a miscalibrated agent might rate P2 (degraded logging) rather than P1 (silent retry masking a real failure). The v5 calibration section should push the agent toward the correct severity. This gives the test discriminatory power.

---

### [P2] Cleanup task has contradictory instructions

**File:** /home/mk/projects/Sylveste/docs/plans/2026-03-29-severity-calibration-validation-plan.md
**Lines:** 70-71
**Issue:** Task 4 says "Remove `tests/fixtures/severity-test-content.go` (or move to `tests/fixtures/` with a comment explaining it's a test fixture)." The file path in Task 1 is already `tests/fixtures/severity-test-content.go` — so the "or move to" option is nonsensical. The fixture is already in `tests/fixtures/`. The instructions also say "temporary, gitignored or removed after" in Task 1, but Task 4 offers keeping it as a permanent fixture with a comment, which contradicts the "temporary" framing.

**Fix:** Decide before execution: is this fixture permanent (useful as a regression canary for future calibration changes) or ephemeral? If permanent, remove the "gitignored or removed after" language from Task 1 and commit the fixture. If ephemeral, remove the ambiguous "or move to" clause from Task 4.

---

### [P3] No coverage of the `--mode=regenerate-stale` upgrade path

**File:** /home/mk/projects/Sylveste/docs/plans/2026-03-29-severity-calibration-validation-plan.md
**Lines:** 19, 38-52
**Issue:** The plan notes "250 generated agents exist, 0 are v5" and validates generating new v5 agents from scratch. It does not validate that running `--mode=regenerate-stale` against an existing v4 agent correctly upgrades it to v5 when a new spec (with `severity_examples`) is available. This is a real user-facing upgrade path that the code explicitly supports (lines 412-416 of generate-agents.py check `existing_version >= FLUX_GEN_VERSION`).

The upgrade path has a subtle edge: a v4 agent regenerated from a spec that now includes `severity_examples` should become v5. A v4 agent regenerated from a spec still missing `severity_examples` should remain v4. Neither case is exercised by the plan.

**Fix:** Add an optional Task 2b: take one of the 250 existing v4 agents, run `--mode=regenerate-stale` with a spec that includes `severity_examples`, and verify the agent file becomes v5. This is lower priority than the primary flow but documents the upgrade behavior and catches any regression in the version-gate logic.
