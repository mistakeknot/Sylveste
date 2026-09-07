---
artifact_type: reflection
bead: sylveste-fyo3
sprint_steps_completed: 10
autonomy_tier: 3
complexity: 4
---

# Multi-Model Activation Sprint Reflection

**Bead:** sylveste-fyo3
**Sprint:** 2026-04-11 → 2026-04-12

## What worked

- **Parallel batching**: Tasks 1+3+7 ran simultaneously (3 subagents), then 2+4+6, then 5 calibration agents in parallel. This compressed what would be serial 10-task execution into 4 batches.
- **Two-phase script pattern**: The `--emit`/`--score` split cleanly separates "what to do" from "how to call the model", avoiding the deadlock problem of a bash script needing to pause for external async IO. This pattern is reusable for any FluxBench operation that needs model calls.
- **Real calibration run**: 5 sonnet agents produced genuine findings against fixtures. The thresholds are empirical, not hand-tuned.

## What didn't work

- **Scoring system assumes exact location matching**: `fluxbench-score.sh` required exact file:line matches. Real model output uses different line numbering (code-block-relative vs document-relative) and sometimes different filenames (`document.md` vs the code file referenced in the markdown). Required infrastructure fix: fuzzy location matching with ±5 line tolerance and description-only fallback.
- **Budget exhaustion**: Token budget hit 0 before quality gates on a C4 epic. The 5 calibration agents + 8 execution subagents consumed the entire allocation. Need per-phase budgets or complexity-scaled allocations.
- **Calibration thresholds are weak**: p25 of 5 fixtures with fuzzy matching gave severity_accuracy=0.0, fp_rate=0.8333. These thresholds won't meaningfully gate models. Root cause: too few fixtures + scoring system still too strict for cross-file matching. Need more fixtures and/or scoring improvements.

## Key decisions

1. **Fixed score.sh as part of execution** — the fuzzy matching fix was scope creep beyond the plan's 10 tasks, but without it the calibration was meaningless. Made the call to fix infrastructure rather than ship non-functional thresholds.
2. **Raised description-only match threshold from 0.40 to 0.60** — quality gate correctness review caught that 0.40 allowed cross-file false matches (50% desc similarity). Tightened to 0.60 which requires genuine semantic similarity.
3. **Slug validation added to qualify.sh** — safety review caught that model_slug was unsanitized. Added regex gate matching discover-merge.sh's VALID_SLUG pattern.

## Open items for next sprint

- P2-B: Calibrated thresholds near-zero — need minimum floors or more fixtures
- P2-C: calibrate.sh --emit work_dir output not machine-parseable (freeform sentence)
- P1 (safety): OpenRouter MCP spend ceiling has async race condition — need speculative reservation
- The 11 children beads (sylveste-fyo3.1 through .11) track downstream work: real model dispatch, discovery automation, Oracle integration, etc.
