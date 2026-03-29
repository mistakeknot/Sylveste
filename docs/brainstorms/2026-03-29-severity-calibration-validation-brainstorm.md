---
artifact_type: brainstorm
bead: sylveste-feu
stage: discover
---

# Brainstorm: Validate Severity Calibration Fix End-to-End

## What We're Building

An end-to-end validation that the sylveste-pkx severity calibration changes to flux-gen actually produce P0/P1 findings from generated agents. This is Task 4 from the implementation plan — the code is already landed, we need to prove it works.

## Why This Approach

The code changes (v5 template with `severity_examples`, LLM prompt with canonical severity definitions, escalation instructions) are in `generate-agents.py`. Unit tests pass (31/31). But the real question is: do generated agents actually produce high-severity findings on content that warrants them? Only an integration test answers that.

## Key Decisions

- **Test content:** Create a synthetic document with known P0 conditions (migration without transaction safety, goroutine leak, missing error handling on DB write). This gives a controlled baseline where we *know* what severity to expect.
- **Validation flow:** Run `/flux-gen` to generate fresh v5 agents, then `/flux-drive` against the test document. Check if any generated (non-core) agent produces P0/P1.
- **Success metric:** At least 1 generated agent produces a P0 or P1 finding on the test content. This matches the original plan's pass criterion.

## Open Questions

- Should we also check that the severity *reasoning* is domain-specific (not just generic restatements)?
- Do we need a negative control (content that should NOT produce P0/P1)?
