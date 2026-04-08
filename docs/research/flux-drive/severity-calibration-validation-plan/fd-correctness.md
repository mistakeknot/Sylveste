---
agent: fd-correctness
status: NEEDS_ATTENTION
finding_count: 6
---

## Invariants This Review Assumes

Before listing findings, here are the invariants the validation plan must satisfy to
prove the severity calibration actually works:

1. **v5 agents are generated** — flux-gen produces at least one agent file with
   `flux_gen_version: 5` in frontmatter (not 4, not missing).
2. **v5 agents contain structured calibration** — the `## Severity Calibration`
   section uses domain-specific P0/P1 scenarios from the LLM, not the generic
   fallback path in `_render_severity_calibration()`.
3. **A generated (non-core) agent is dispatched by flux-drive triage** — the v5
   agent must actually enter the review, not be blocked by triage scoring or slot
   ceilings.
4. **The dispatched agent produces a P0 or P1 finding** — the severity calibration
   section must influence the agent's output, not just appear in the rendered file.
5. **The finding references a deliberate flaw in the test fixture** — this rules out
   accidental P0/P1 hits from unrelated content.

---

## Findings

### [P0] Task 2 uses `skip-existing` but may have name collisions with prior v4 agents, silently skipping generation

**File:** `docs/plans/2026-03-29-severity-calibration-validation-plan.md`
**Lines:** 41-52
**Issue:** The plan invokes flux-gen with a new task prompt and expects at least one
`flux_gen_version: 5` agent to appear. However, flux-gen (and the underlying
`generate-agents.py`) defaults to `--mode=skip-existing`. If any prior run of
flux-gen for this project already generated an agent whose LLM-chosen name collides
with a name the new run would produce, that agent is silently skipped rather than
regenerated. Because the 250 existing agents are all v4, a name collision produces
a skipped v4 agent — and the Task 2 pass check ("at least 1 new agent with
`flux_gen_version: 5`") fails without any error message. The skip is silent: the
JSON report shows the name in `skipped`, not in `errors`, so a casual reader can
mistake "0 generated, N skipped" for success.

The name is assigned by the LLM in Step 1 of flux-gen. The LLM is given only the
task description and its own design heuristics — it has no visibility into the
existing 250 agent files. Name collision probability is non-trivial for generic
domains like "database migration" or "concurrency".

**Fix:** Add an explicit pre-check step to Task 2: before running flux-gen, confirm
that the generated agent names are new. Either run with `--mode=regenerate-stale`
to force v5 regeneration of any stale existing agent, or verify the JSON report
shows `generated` count >= 1 (not just `skipped` count). The plan already
acknowledges the risk of severity_examples being missing from LLM output (line 79),
but this is a different and more likely failure — the generation step is bypassed
entirely before any LLM check is possible. Add it to the Risk section and to the
Task 2 verification steps.

---

### [P0] Task 3 pass criterion is satisfied by core agents, not generated agents — the validation can pass without testing the calibration at all

**File:** `docs/plans/2026-03-29-severity-calibration-validation-plan.md`
**Lines:** 62-66
**Issue:** The Task 3 pass criterion is: "at least 1 finding from a generated (non-core)
agent has severity P0 or P1". This is a necessary condition for validating that v5
calibration influences agent output. However, the flux-drive triage algorithm
(SKILL.md Step 1.2) gives core agents like `fd-correctness` a base_score of 3 for
Go code with database operations, concurrency, and error handling — the exact content
the test fixture contains. Core agents will almost certainly be selected and will
almost certainly flag the deliberate flaws (transaction safety, goroutine leak, error
handling are textbook correctness issues). If the generated v5 agent gets a lower
triage score and is placed in Stage 2 or in the expansion pool but not dispatched,
the test can produce P0/P1 findings from core agents while the generated agent
contributes nothing — and the plan's pass criterion is still unmet.

The false-positive direction is: core agents pass the check via P0/P1 findings, but
the evaluator misreads the criterion. The false-negative direction is: the generated
agent is never dispatched at all (see finding below), so no generated-agent P0/P1
finding ever appears, and the plan correctly fails — but then the failure is
attributed to calibration when it may actually be a triage slot issue.

**Fix:** The pass criterion needs a two-part check that is explicitly tested in order:
(a) confirm the v5 agent was dispatched (appears in the triage table under Stage 1
or Stage 2 and shows findings in the output), then (b) confirm that agent produced
a P0 or P1 finding. If (a) fails, the test is inconclusive about calibration — record
it as "agent not dispatched" not "calibration failed". The current plan conflates
these two failure modes.

---

### [P1] v5 version gating in `generate-agents.py` means LLM omitting `severity_examples` silently produces a v4 agent, and the Task 2 pass check is ambiguous about this

**File:** `interverse/interflux/scripts/generate-agents.py`
**Lines:** 155-158 (version gating), plan lines 46-52
**Issue:** `render_agent()` checks `has_severity = bool(severity_examples and isinstance(severity_examples, list))`.
When the LLM omits `severity_examples` (or returns an empty list), `has_severity` is
False, `effective_version` is set to 4, and the agent is written as v4 with the
generic fallback calibration section. The agent is still generated successfully —
it goes into `report["generated"]`, not `report["errors"]`. The Task 2 pass check
says "at least 1 new agent with `flux_gen_version: 5`". If every agent comes back v4
because the LLM omitted the field, zero v5 agents exist but `report["generated"]`
is non-empty and looks like success.

The plan's mitigation ("inspect the saved spec JSON") is manual and can be missed
under time pressure. Task 2 step 3 also says to check whether `severity_examples`
was populated — but this is listed as a fallback investigation path, not as a
mandatory verification step that gates proceeding to Task 3.

**Fix:** Make the v5 check mechanically enforced in Task 2, not advisory. After
running generate-agents.py, parse the frontmatter of every generated agent and
assert `flux_gen_version == 5` for at least one. If all generated agents are v4,
stop at Task 2 and re-run flux-gen (the risk mitigation already says to do this —
it just needs to be a blocking gate, not an optional investigation).

---

### [P1] The test fixture in Task 1 is a `.go` file — flux-drive's cognitive-agent filter and data filter behavior near the file path may cause the generated agent to be pre-filtered out of triage

**File:** `docs/plans/2026-03-29-severity-calibration-validation-plan.md`
**Lines:** 27-35, 59
**Issue:** The flux-drive pre-filter (SKILL.md Step 1.2a) passes `fd-correctness` for Go
files with database/migration/concurrency content. But generated agents (Project
Agents) are scored with `domain_agent: +1` only when "the detected domain matches
their specialization". A generated agent named, say, `fd-migration-safety` or
`fd-goroutine-lifecycle` gets:
- `base_score`: depends on how well its focus description matches the fixture
- `domain_boost`: +2 only if the project is classified under a domain that has
  injection criteria for that agent — which it will not have (the fixture is in
  `tests/fixtures/`, not in a recognized domain profile)
- `project_bonus`: +1 (CLAUDE.md and AGENTS.md exist)
- `domain_agent`: +1

So the generated agent scores at most 3+0+1+1=5, while `fd-correctness` scores
3+2+1+0=6 for this exact content. Under single-file input, the slot ceiling is 4
(base) + 0 (single file) + 0 or 1 (domain) = 4-5. If the ceiling is 4 and five
agents pass pre-filter, the generated agent may be pushed to Stage 2 or the
expansion pool and never dispatched.

This is not a bug in the validation plan's logic, but it is an unacknowledged
assumption: the plan assumes a generated agent will be dispatched. If it is not,
the failure is ambiguous (triage slot contention vs. calibration failure).

**Fix:** Add a Task 3 pre-step: inspect the triage table to confirm the generated
v5 agent appears in Stage 1 or Stage 2. If it is only in the expansion pool, either
increase the slot ceiling for the test run (by making the fixture a directory rather
than a single file, which raises the ceiling to 4+3=7 slots) or manually force the
generated agent into Stage 1 by editing the triage selection. This should be
explicit in the plan, not left to chance.

---

### [P2] The validation does not distinguish "severity calibration section influenced output" from "agent would have said P0 anyway"

**File:** `docs/plans/2026-03-29-severity-calibration-validation-plan.md`
**Lines:** 62-68
**Issue:** The test fixture contains textbook P0-level Go bugs (no-transaction DB exec,
goroutine with no context cancellation, discarded error on DB write). Any competent
code review agent — with or without a severity calibration section — will rate these
P0 or P1. The pass criterion ("the finding has severity P0 or P1") therefore does
not isolate the causal contribution of the severity calibration section. An agent
running with the generic v4 fallback calibration would produce the same output for
these flaws, because the flaws are obvious enough that no calibration nudge is
needed.

This means a PASS on this test is consistent with two hypotheses:
(a) The calibration is working and correctly uplifts severity.
(b) The calibration is irrelevant and the agent rates the bugs correctly regardless.

To distinguish (a) from (b), the test would need a flaw that is ambiguous enough to
be rated P2 without calibration guidance but P0/P1 with it. The current fixture
contains no such ambiguous-severity flaw.

**Fix:** Add a fourth flaw to the fixture with genuinely ambiguous severity — for
example, a context passed to a goroutine but the cancel function is called after a
potential early return, meaning the goroutine may not be cancelled in one branch.
This is defensible as P2 ("potential leak in one path") or P0 ("context leak under
specific conditions"). If the v5 agent with domain-calibrated examples flags this as
P0 and the v4 agent flags it as P2, that is meaningful evidence. This change does
not require redesigning the other tasks.

---

### [P2] Task 4 cleanup instruction is ambiguous — the plan says "remove or move" with no definitive choice, which means the fixture may silently persist

**File:** `docs/plans/2026-03-29-severity-calibration-validation-plan.md`
**Lines:** 71-73
**Issue:** Task 4 says: "Remove `tests/fixtures/severity-test-content.go` (or move to
`tests/fixtures/` with a comment explaining it's a test fixture)." The destination
for the "move" case is `tests/fixtures/` — which is exactly where Task 1 creates it.
So the "move" option is a no-op (the file is already there). This is a copy-paste
inconsistency: the original instruction in Task 1 (line 27) says the file goes in
`tests/fixtures/severity-test-content.go`, and Task 4 says to remove it or move it
to `tests/fixtures/` — the same directory.

The practical consequence is that whoever executes Task 4 will either delete the
file (correct) or "move" it to its existing location (a no-op), leaving the fixture
permanently in the repo. Since the fixture contains deliberately buggy code, it will
appear in future flux-drive reviews of `tests/fixtures/` and generate spurious P0
findings. Task 1 also says "gitignored or removed after", but Task 4 does not
mention gitignore — so if someone chooses to keep it, it will be committed.

**Fix:** Make the cleanup deterministic: "Delete `tests/fixtures/severity-test-content.go`
and confirm `git status` does not show it as a tracked file." If the fixture is
valuable for future regression testing, the plan should explicitly say so and
describe where it belongs (e.g., `tests/fixtures/known-flaws/severity-test.go` with
a README explaining its purpose). Do not leave the outcome ambiguous.
