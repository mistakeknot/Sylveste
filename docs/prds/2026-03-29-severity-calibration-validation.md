---
artifact_type: prd
bead: sylveste-feu
stage: design
---

# PRD: Validate Severity Calibration Fix End-to-End

## Problem

The sylveste-pkx severity calibration changes added `severity_examples` fields and escalation instructions to generated review agents (v5 template). Unit tests pass (31/31), but no integration test confirms that generated agents actually produce P0/P1 findings on content that warrants them.

## Solution

Create controlled test content with known P0 conditions, generate fresh v5 agents via flux-gen, run flux-drive against the test content, and verify at least 1 generated agent produces a P0 or P1 finding.

## Features

### F1: Create test content with known P0 conditions
**What:** Write a synthetic Go file containing deliberate P0-level flaws that any competent reviewer should flag.
**Acceptance criteria:**
- [ ] File contains at least 3 distinct P0-level issues: migration without transaction safety, goroutine leak (no context cancellation), missing error handling on database write
- [ ] File is realistic enough for LLM-based agents to analyze (not obviously synthetic)
- [ ] File is placed in a temporary test location (not committed as production code)

### F2: Generate v5 agents and validate structure
**What:** Run flux-gen to produce fresh agents, verify they contain the severity calibration section.
**Acceptance criteria:**
- [ ] At least 1 generated agent has `## Severity Calibration` section
- [ ] Generated agent frontmatter shows `flux_gen_version: 5`
- [ ] Severity section contains structured P0/P1 scenarios (not generic boilerplate)

### F3: Run flux-drive and verify P0/P1 detection
**What:** Execute flux-drive against the test content and check generated agent findings.
**Acceptance criteria:**
- [ ] At least 1 generated (non-core) agent produces a P0 or P1 finding
- [ ] Finding references a specific flaw in the test content
- [ ] Finding severity is justified (not a false escalation)

## Non-goals

- Validating core agents (they already produce P0/P1)
- Measuring recall (what percentage of P0s are caught)
- Negative controls (content that should NOT produce P0/P1) — useful but out of scope

## Dependencies

- sylveste-pkx code changes must be landed (verified: `FLUX_GEN_VERSION = 5` in generate-agents.py)
- flux-gen and flux-drive commands must be functional

## Open Questions

- None — scope is well-defined from the parent plan's Task 4
