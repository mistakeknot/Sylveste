---
bead: sylveste-feu
title: "Plan: Validate severity calibration fix end-to-end"
date: 2026-03-29
type: plan
revised: true
revision_reason: "Plan review found 2 P0 and 5 P1 issues — name collision skips generation, core agents mask findings, pass criterion doesn't require v5"
---

# Plan: Validate Severity Calibration Fix End-to-End (Revised)

## Summary

4 tasks, no code changes to production. Create test content, generate v5 agents (with name collision mitigation), run flux-drive, verify P0/P1 output specifically from a **v5 generated** agent. All work is validation — the severity calibration code is already in generate-agents.py (v5).

## Context

- 250 generated agents exist, 0 are v5 (all generated before sylveste-pkx landed)
- `_render_severity_calibration()` in generate-agents.py is ready but untested end-to-end
- flux-gen command includes `severity_examples` in the LLM prompt schema (Step 1 of flux-gen.md)
- Name collision risk: `--mode=skip-existing` silently skips agents matching existing names

## Tasks

### Task 1: Create test content with known P0 conditions
**Bead:** sylveste-w05
**File:** `tests/fixtures/severity-test-content.go` (deleted after validation)
**What:**

Write a realistic Go file (~80-120 lines) containing a database migration handler with these deliberate P0-level flaws:

1. **Migration without transaction safety** — `db.Exec()` calls for schema changes without `BEGIN`/`COMMIT`/`ROLLBACK`, meaning a partial failure leaves the DB in an inconsistent state
2. **Goroutine leak** — spawns a goroutine with `go func()` that reads from a channel but has no context cancellation or timeout, so it hangs forever if the channel is never closed
3. **Missing error handling on DB write** — `db.Exec("INSERT ...")` with the error return value discarded (`_ = err` or just not checked)
4. **Ambiguous-severity flaw** — a connection pool that silently drops connections on timeout instead of returning an error; could be P1 or P2 depending on domain expertise. This tests whether calibrated agents escalate appropriately vs. uncalibrated ones.

Use realistic table names, column types, and function signatures. Must use real stdlib imports (`database/sql`, `context`, `fmt`).

**Verify:** File exists, contains all 4 flaws, uses real Go imports and function signatures.

### Task 2: Generate v5 agents and validate structure
**Bead:** sylveste-cud
**What:**

1. Run `/interflux:flux-gen` targeting the test content. Use `--from-specs` if a spec file with `severity_examples` already exists, otherwise generate fresh:
   ```
   /interflux:flux-gen "Review of Go database migration handler with schema changes, goroutine workers, and data persistence"
   ```

2. **Name collision gate (BLOCKING):** After generation, check the saved spec JSON in `.claude/flux-gen-specs/` for the `generated` vs `skipped` counts. If all agents were skipped (name collision with existing 250), re-run with unique name prefix or use `--mode=regenerate-stale` on one colliding agent.

3. **v5 gate (BLOCKING):** Verify at least 1 generated agent has `flux_gen_version: 5`:
   ```bash
   grep -l "flux_gen_version: 5" .claude/agents/fd-*.md
   ```
   If zero v5 agents: inspect spec JSON for `severity_examples` field. If field is empty/missing, the LLM did not produce it — retry with emphasis. Do NOT proceed to Task 3 with only v4 agents.

4. For each v5 agent, verify:
   - Contains `## Severity Calibration` section
   - Has ≥2 lines matching `- **P0**:` or `- **P1**:` with domain-specific content
   - Content is not a restatement of the generic definition

**Pass:** ≥1 agent with `flux_gen_version: 5` + structured severity calibration section with domain-specific scenarios.

### Task 3: Run flux-drive and verify P0/P1 detection
**Bead:** sylveste-z25
**What:**

1. Run `/interflux:flux-drive tests/fixtures/severity-test-content.go`

2. **Dispatch gate:** Before evaluating findings, confirm the triage table shows at least 1 v5 generated agent in Stage 1 or Stage 2. If the v5 agent was pushed to expansion pool or not dispatched, the test is inconclusive — note this and stop.

3. Check findings specifically from the **v5 generated** agent (not core agents):
   - Agent name does NOT match CORE_AGENTS set
   - Agent frontmatter has `flux_gen_version: 5`
   - Finding has severity P0 or P1
   - Finding references one of the 4 deliberate flaws

**Pass criterion:** ≥1 **v5 generated** (non-core) agent produces a P0 or P1 finding referencing a deliberate flaw in the test content.

**If FAIL:** Structured failure report:
1. List of generated agents dispatched by triage (with version)
2. Severity distribution of their findings (P0/P1/P2/P3 counts)
3. Whether their Severity Calibration section contained scenarios relevant to the test content
4. Whether core agents found the same flaws (to distinguish "calibration broken" from "agent not dispatched")

### Task 4: Cleanup
**What:** Delete `tests/fixtures/severity-test-content.go`. This is a throwaway test fixture, not a regression test. If the validation passes, the result is documented in the bead; if it fails, the fixture needs redesign anyway.

## Execution Order

Task 1 → Task 2 → Task 3 → Task 4 (strictly sequential, each depends on the previous)

Task 2 has two blocking gates (name collision, v5 verification) that may require retry loops.

## Risk

- **flux-gen LLM may not populate severity_examples** — the field is in the prompt schema but LLMs sometimes skip optional-looking fields. Mitigation: v5 gate in Task 2 catches this; retry with emphasis if needed.
- **flux-drive triage may not select generated agents** — single-file slot ceiling is 4-5, core agents fill most slots. Mitigation: dispatch gate in Task 3 checks this before evaluating findings.
- **Name collision with existing agents** — 250 v4 agents exist; LLM may generate names that collide. Mitigation: collision gate in Task 2.

## Scope note

This is a smoke test, not a recall measurement. Passing proves the calibration pipeline is functional end-to-end. It does not prove calibration improves detection rates — that requires A/B comparison (deferred).
