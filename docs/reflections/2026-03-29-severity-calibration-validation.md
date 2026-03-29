---
artifact_type: reflection
bead: sylveste-feu
stage: reflect
---

# Reflection: Severity Calibration Validation (sylveste-feu)

## What happened

Validated that the sylveste-pkx severity calibration changes to flux-gen actually work end-to-end. Generated 5 v5 agents with domain-specific severity examples, ran them against a Go test fixture with 4 planted flaws, and all 4 agents produced P0/P1 findings covering all planted flaws plus 1 bonus finding.

## Key learnings

### 1. severity_examples reliably populate from the LLM prompt
The flux-gen prompt change (injecting canonical severity definitions + requesting structured severity_examples) caused the LLM to produce severity_examples in all 5 specs. This was the highest-risk assumption — LLMs often skip optional-looking fields. The key was making severity_examples part of the schema description (not a separate instruction), and providing the severity reference as fixed context rather than asking the LLM to invent definitions.

### 2. Plan review caught real integration gaps
The 3-agent plan review (fd-quality, fd-correctness, fd-acceptance-criteria-quality) found 2 P0 issues that would have caused false positives in the validation:
- **Name collision:** `--mode=skip-existing` silently skips agents matching existing names. With 250 v4 agents, this was a real risk.
- **Core agent masking:** Core agents (fd-correctness) would have scored 3 on the Go fixture and produced P0/P1 findings regardless of calibration, making it impossible to attribute findings to v5 agents specifically.

Both were fixed in the plan revision with blocking gates (collision gate, dispatch gate, v5-specific finding check).

### 3. The ambiguous-severity flaw is the real discriminator
The 3 obvious flaws (no transaction, goroutine leak, discarded error) would likely be caught by any competent agent regardless of calibration. The 4th flaw (silent connection drop in pool reaper) is genuinely ambiguous — it was flagged as P1 by fd-goroutine-lifecycle, which correctly identified it as a resource leak pattern. This suggests calibration adds value for borderline-severity issues, not just obvious ones.

### 4. Version gating works as designed
All 5 specs had severity_examples → all 5 agents rendered as v5 with structured Severity Calibration sections. The fallback path (v4 with generic calibration) was not triggered. This confirms the version gating logic in `render_agent()` is correct.

## What to do differently

- **For future validation beads:** Include a negative control (v4 agent on same content) to measure the calibration delta, not just the absolute result. This was explicitly deferred as a scope decision, but the plan review flagged it as the main weakness.
- **For flux-gen:** Consider making severity_examples required (not optional) in the spec schema. The current fallback to generic calibration means v4 agents still get calibration text, just not domain-specific — this blurs the v4/v5 distinction.

## Metrics

- 4/4 v5 agents produced P0/P1 findings (100% hit rate)
- 4/4 planted flaws detected (100% coverage)
- 1 bonus finding (missing rows.Err() — not planted)
- 13 total findings across 4 agents (6 P0, 5 P1, 1 P2, 1 P3)
- Plan review: 2 P0 + 5 P1 fixed in revision before execution
