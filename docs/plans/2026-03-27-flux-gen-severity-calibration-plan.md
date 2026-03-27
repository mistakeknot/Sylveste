---
bead: sylveste-pkx
title: "Plan: Fix flux-gen P0/P1 severity calibration"
date: 2026-03-27
type: plan
revised: true
revision_reason: "Plan review found 3 P0/P1 issues — domain injection doesn't reach generated agents, free-form fields reproduce the problem, version lock-in from stale specs"
---

# Plan: Fix Flux-Gen P0/P1 Severity Calibration (Revised)

## Summary

2 interventions across 2 files + tests. Domain profile backfill (original Task 3) dropped — injection path doesn't reach generated agents.

## Tasks

### Task 1: Add severity calibration to render_agent() template
**File:** `interverse/interflux/scripts/generate-agents.py`
**Changes:**

1. Bump `FLUX_GEN_VERSION` from 4 to 5 — but only emit v5 in frontmatter when spec contains `severity_examples` field. Specs without it render with v4 tag so `--mode=regenerate-stale` will retry them later.

2. Add `## Severity Calibration` section between "Review Approach" and "Success Criteria":
   - Render `severity_examples` as structured list: each item has `severity` (P0/P1), `scenario` (what breaks), `condition` (under what circumstances)
   - If spec lacks `severity_examples`, render domain-generic fallback derived from `focus` field using canonical definitions:
     ```
     P0: {focus}-related issue that causes data loss, corruption, or blocks other work
     P1: {focus}-related issue required to pass the current quality gate
     ```
   - Add explicit escalation instruction to Decision Lens: "If you find an issue matching a P0/P1 scenario above, label it P0 or P1 — do not downgrade to appear less alarming."

3. Replace boilerplate `## Prioritization` section (lines 167-173) with the calibrated version.

4. Move "Provides a concrete failure scenario for each P0/P1 finding" from Success Criteria into Severity Calibration section (where it informs identification, not just reporting).

### Task 2: Enhance LLM prompt in flux-gen command
**File:** `interverse/interflux/commands/flux-gen.md`
**Changes:**

1. Add `severity_examples` to the JSON spec schema:
   ```
   - severity_examples: array of 2-3 objects, each with:
     - severity: "P0" or "P1"
     - scenario: what breaks (1 sentence)
     - condition: under what circumstances (1 sentence)
   ```

2. Inject canonical P0/P1 definitions as fixed context in the design prompt (not asking LLM to invent definitions):
   ```
   Severity reference (use these exact definitions):
   - P0: Blocks other work or causes data loss/corruption. Drop everything.
   - P1: Required to exit the current quality gate. If this doesn't ship, the version doesn't ship.
   - P2: Degrades quality or creates maintenance burden.
   - P3: Improvements and polish.

   For each agent, produce severity_examples: 2-3 concrete scenarios
   specific to that agent's focus area that would warrant P0 or P1.
   ```

3. Add design rule: "severity_examples must be concrete and domain-specific, not restatements of the P0/P1 definition"

4. Drop `review_sequence` (no render target — review_areas already provides ordering)

5. Update line 122 version reference: `flux_gen_version: 5` with severity calibration listed as v5 capability

### Task 3: Add tests for new fields and fallbacks
**File:** `interverse/interflux/tests/structural/test_generate_agents.py`
**Changes:**

1. `test_severity_calibration_rendered`: pass spec with `severity_examples` containing 2 structured objects → assert `## Severity Calibration` heading present, both scenarios rendered, `flux_gen_version: 5` in frontmatter

2. `test_severity_calibration_fallback`: pass spec without `severity_examples` → assert fallback section is non-empty, does not contain literal `"None"`, `flux_gen_version: 4` in frontmatter (not 5)

3. `test_version_gating`: spec with `severity_examples` gets v5, spec without gets v4

### Task 4: Validate end-to-end
**Action:**
1. Delete one existing generated agent, then run `/flux-gen` with a test prompt to generate v5 agent
2. Verify new agent contains `## Severity Calibration` with structured scenarios
3. Verify `flux_gen_version: 5` only when `severity_examples` present
4. Run `/flux-drive` against a document with known issues and confirm generated agent produces at least 1 P0/P1 finding

**Pass criterion:** On a review target containing a known P0 condition (e.g., migration without transaction, goroutine leak), at least 1 generated agent produces a P0 or P1 finding.

## Execution Order

Task 3 (tests first) → Task 1 (template) → Task 2 (LLM prompt) → Task 4 (validate)

TDD: write tests first, then implement to pass them.

## Deferred (separate bead)

- **Domain profile P0/P1 tables**: The injection path (`### fd-{agent-name}`) doesn't reach generated agents. Useful for core agents but doesn't fix the stated problem. Track separately.
- **Domain profile injection for generated agents**: Requires either a `## General Criteria` section injected to all agents regardless of name, or adding `domain:` to generated agent frontmatter for adjacency-based lookup. Follow-on work.
- **`_short_title()` truncation bug**: Produces broken section titles like "No read" and "Json". Separate fix.

## Original Intent

Cut from plan review:
- `review_sequence` field — no render target, duplicates review_areas ordering
- `severity_calibration` as free-form object — replaced with structured `severity_examples` array
- Domain profile backfill (11 files) — injection path doesn't reach generated agents
