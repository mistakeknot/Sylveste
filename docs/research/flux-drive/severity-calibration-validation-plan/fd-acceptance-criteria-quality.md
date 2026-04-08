---
agent: fd-acceptance-criteria-quality
status: NEEDS_ATTENTION
finding_count: 8
---

## Findings

### [P1] "Realistic enough" is subjective and untestable
**File:** /home/mk/projects/Sylveste/docs/prds/2026-03-29-severity-calibration-validation.md
**Lines:** 23
**Issue:** F1 acceptance criterion "File is realistic enough for LLM-based agents to analyze (not obviously synthetic)" has no objective measure. Two reviewers could disagree on whether a file looks "obviously synthetic." There is no oracle for realism.
**Fix:** Replace with a structural criterion: "File uses real stdlib imports, realistic function signatures, and contains at least 80 lines of coherent logic — not isolated bug snippets." Alternatively, drop this criterion entirely since the downstream validation (agents actually produce findings) is the real test of adequacy.

### [P1] "Structured P0/P1 scenarios (not generic boilerplate)" lacks a definition of "generic"
**File:** /home/mk/projects/Sylveste/docs/prds/2026-03-29-severity-calibration-validation.md
**Lines:** 31
**Issue:** F2 criterion "Severity section contains structured P0/P1 scenarios (not generic boilerplate)" requires the verifier to distinguish "structured" from "boilerplate" without a definition. The plan (line 49) gives a concrete regex (`- **P0**:` or `- **P1**:`), but the PRD does not reference it.
**Fix:** Define explicitly: "Severity section contains at least 2 lines matching the pattern `- **P0**: <scenario>` or `- **P1**: <scenario>` with domain-specific content (not just the words 'critical' or 'high severity')."

### [P1] "Finding severity is justified (not a false escalation)" is subjective
**File:** /home/mk/projects/Sylveste/docs/prds/2026-03-29-severity-calibration-validation.md
**Lines:** 38
**Issue:** F3 criterion "Finding severity is justified (not a false escalation)" requires human judgment about whether an escalation is "false." This defeats the purpose of an automated or objective validation. Since the test content has 3 known P0 flaws, the criterion should bind to those.
**Fix:** Replace with: "Finding references one of the 3 deliberately planted flaws (transaction safety, goroutine leak, missing error handling)." The plan already has this criterion at line 64 — the PRD should match.

### [P2] No criterion for minimum number of generated agents
**File:** /home/mk/projects/Sylveste/docs/prds/2026-03-29-severity-calibration-validation.md
**Lines:** 29
**Issue:** F2 says "at least 1 generated agent" but does not specify how many agents flux-gen should produce overall. If flux-gen produces 5 agents and only 1 is v5, that could indicate a regression in the generation pipeline. The plan similarly says >=1 without bounding the expected total.
**Fix:** Add a criterion: "flux-gen produces N agents total, of which >= 1 is v5." Even a soft expectation ("typically 3-5 agents") gives the verifier a sanity check.

### [P2] No criterion for which of the 3 flaws must be detected
**File:** /home/mk/projects/Sylveste/docs/plans/2026-03-29-severity-calibration-validation-plan.md
**Lines:** 63-65
**Issue:** The pass criterion requires only 1 finding referencing "one of the 3 deliberate flaws." This means 2 of 3 P0 flaws can go completely undetected and the validation still passes. For a severity calibration validation, catching only 1 out of 3 known P0s is a weak signal.
**Fix:** Either (a) raise the bar to >= 2 of 3 flaws detected, or (b) explicitly document that recall measurement is out of scope and this is a smoke test only. The PRD non-goals mention "measuring recall" but the plan does not reference this, so the intent is ambiguous.

### [P2] No negative-signal criterion if only core agents fire
**File:** /home/mk/projects/Sylveste/docs/plans/2026-03-29-severity-calibration-validation-plan.md
**Lines:** 62
**Issue:** The pass criterion requires the finding to come from a "generated (non-core) agent." If core agents find all 3 P0s but no generated agent does, the test fails — but the plan's failure documentation (lines 68-69) only asks to "document which agents were triaged." There is no explicit criterion for what constitutes a meaningful failure analysis vs. a shrug.
**Fix:** Add a structured failure criterion: "If FAIL, the failure report must include: (1) list of generated agents dispatched by triage, (2) severity distribution of their findings, (3) whether their Severity Calibration section contained relevant scenarios for the test content."

### [P3] Task 4 cleanup has two contradictory options with no decision rule
**File:** /home/mk/projects/Sylveste/docs/plans/2026-03-29-severity-calibration-validation-plan.md
**Lines:** 71
**Issue:** Task 4 says "Remove tests/fixtures/severity-test-content.go (or move to tests/fixtures/ with a comment)." These are opposite actions with no criterion for choosing between them. The file is already in tests/fixtures/ per Task 1, so "move to tests/fixtures/" is a no-op.
**Fix:** Pick one: either the fixture is valuable for regression and stays (with a comment), or it is throwaway and gets deleted. Tie the decision to whether the validation passed: keep on pass (for future regression), delete on fail (since the fixture may need redesign).

### [P3] Plan and PRD have inconsistent pass criteria for F3
**File:** /home/mk/projects/Sylveste/docs/prds/2026-03-29-severity-calibration-validation.md
**Lines:** 36-38
**Issue:** The PRD F3 has 3 acceptance criteria (non-core agent, references specific flaw, severity is justified). The plan's pass criterion (line 66) only requires 2 of these (non-core agent, references a real flaw) and drops "severity is justified." This inconsistency means a verifier checking the PRD would apply different standards than one checking the plan.
**Fix:** Align the two documents. Recommend dropping "severity is justified" from the PRD (per P1 finding above) and keeping the plan's more concrete formulation as the single source of truth.
