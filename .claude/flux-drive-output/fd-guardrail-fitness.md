# Guardrail Fitness Review: CUJ Documents

Reviewed: `docs/cujs/first-install.md`, `docs/cujs/running-a-sprint.md`, `docs/cujs/code-review.md`

Lens: Can an agent use these CUJs as its definition of "working correctly" — knowing what to check, when to block, and when to proceed?

---

## Finding 1 — Most 'measurable' signals lack the setup clause an agent needs to run them

**Severity: blocking for agent use**

Several measurable signals specify a command and threshold but omit what must be true *before* the assertion can run. An agent reading these as guardrails will either skip the check (no precondition to trigger it) or run it at the wrong time.

Examples:

- **first-install / "Install completes without errors"**: `claude install clavain` exits 0, all declared dependencies resolve. An agent can run the exit-code check. But "all declared dependencies resolve" — where is the dependency manifest? What command enumerates them? An agent would need to know that Clavain declares dependencies in its `package.json` or plugin manifest and that `claude plugin check-deps clavain` (or equivalent) is the assertion command. The signal gives the *what* but not the *how*.

- **first-install / "Install and onboard complete within 10 minutes"**: The clock starts at `claude install clavain` and stops when `/clavain:project-onboard` finishes. But what timestamp source does the agent use? Shell `$SECONDS`? A kernel event pair? If the agent is *running* the onboard (not observing a human), this becomes a timeout, not a measurement — and the CUJ doesn't say which. An agent needs: "record `start_time` before `claude install clavain`; assert `$(date +%s) - $start_time < 600` after onboard hook completes."

- **running-a-sprint / "Complexity classification matches actual effort"**: "Estimated complexity (1-5) correlates with actual tokens spent and phases needed." Correlation is a statistical property across many sprints, not something an agent can assert on a single run. This is a calibration metric, not a guardrail. An agent given this as a pass/fail criterion has no single-sprint assertion to execute. It needs to be reframed: either as a per-sprint bounds check ("complexity-3 sprint should cost between X and Y tokens") or explicitly marked as a multi-sprint calibration metric that an agent should *record* but not *gate on*.

- **running-a-sprint / "Cost per landable change trends downward over time"**: Same problem — trend analysis requires historical data. An agent cannot assert this on a single change. This is an Interspect dashboard metric, not an agent guardrail.

**Recommendation:** For each measurable signal, add a `precondition` (what must be true before the check runs), `command` (the exact assertion), and `scope` (single-run vs. multi-sprint). Signals with multi-sprint scope should be explicitly labeled as calibration metrics, not gateable assertions.

---

## Finding 2 — 'Observable' signals don't name hooks, event types, or file paths an agent could instrument

**Severity: blocking for agent use**

Observable signals describe what a human would notice but don't tell an agent where to look.

- **first-install / "First `/route` presents actionable options"**: "Discovery scan completes, user sees 'Start fresh brainstorm' option." An agent can't observe what a user sees. It needs: which hook fires when discovery completes? What is the output format? Is there a structured output (JSON, event) that contains the option list, or only terminal text? If terminal text, what string does the agent grep for?

- **running-a-sprint / "Execution follows existing codebase patterns"**: "New code matches naming conventions, file structure, and idioms of surrounding code." This is a quality judgment, not an observable. An agent cannot instrument this without a linter rule, a pattern-matching tool, or a review agent dispatch. The CUJ should specify: does the quality gate agent check this? Is there a specific lint rule set? Or is this purely human-evaluated (in which case it's qualitative, not observable)?

- **running-a-sprint / "Reflect phase produces reusable learnings"**: "Solution doc or calibration data is written to persistent storage." Where? An agent needs a file glob: `docs/solutions/*.md` or a specific Interspect data path. "Persistent storage" is not instrumentable.

- **running-a-sprint / "Model routing uses the cheapest sufficient model"**: "Haiku/Sonnet dispatches appear for subtasks that don't require Opus." Appear where? In terminal output? In kernel events? In a dispatch log? An agent needs the event type name (e.g., `agent.dispatch` with a `model` field) or the log path.

- **code-review / "Triage selects relevant agents only"**: "No agent is dispatched whose declared capabilities don't match the change type." Where are capability declarations stored? How does an agent cross-reference the dispatch list against capability manifests? This needs: "each dispatched agent's `capabilities` field in `interverse/<plugin>/package.json` includes the detected change type from the triage classifier."

- **code-review / "Verdict confidence correlates with quality"**: "High-confidence 'approve' verdicts don't precede post-merge regressions." This requires tracking regressions back to specific reviews — a multi-week feedback loop. An agent cannot assert this in real time. Like the cost-trend signal in running-a-sprint, this is a calibration metric that needs explicit labeling.

- **code-review / "Interspect adjusts routing based on review outcomes"**: "Agent dispatch patterns change after sustained dismissal or action signals." The CUJ itself notes this is Phase 2 and partially shipped. An agent trying to use this as a guardrail today would be checking for behavior that doesn't exist yet. The signal should have a `status: planned` marker so agents skip it.

**Recommendation:** Each observable signal should name at least one of: (a) a hook ID the agent can subscribe to, (b) a file path or glob the agent can watch, (c) a kernel event type the agent can query, or (d) a command that produces structured output. Signals that are actually calibration metrics (multi-sprint, require historical data) should be separated into their own section.

---

## Finding 3 — No negative-case signals: agents don't know what failure looks like

**Severity: high for agent use**

All three CUJs define success signals but no failure signals. An agent needs to know not just "what does working look like?" but "what must I block on?" and "what constitutes a broken journey?"

Missing negative cases by CUJ:

**first-install.md:**
- What if `claude install clavain` exits non-zero? Is this a retry or a hard fail?
- What if `/clavain:project-onboard` creates CLAUDE.md but not .beads/? Is the journey partially complete or failed?
- What if the first `/route` returns no options (scanner error)? What should the agent report?
- What if the first sprint fails at the Ship phase? Does the first-install journey count as failed?

**running-a-sprint.md:**
- What if `/route` takes >30 seconds? Is this a degraded experience or a hard failure?
- What if a gate fails and the developer has no recovery path? When does "sprint stuck" become "sprint failed"?
- What if a multi-session resume re-executes completed steps? This is listed as a success signal (doesn't re-execute), but there's no signal for the failure case (does re-execute — how does the agent detect and report this?).
- What if the reflect phase is skipped (developer closes session)? Is the sprint considered complete without it?

**code-review.md:**
- What if synthesis produces *more* findings than the sum of individual agents (hallucinated findings)? This is the inverse of the dedup signal but isn't mentioned.
- What if zero findings are produced? Is this a valid "approve" or a suspicious silence?
- What if >80% of findings are dismissed? This should trigger an Interspect recalibration signal, but the CUJ doesn't say so.
- What if agent dispatch takes >5 minutes? Is there a timeout? What does the agent report?

**Recommendation:** Add a "Failure Signals" table (or rename the existing table to "Success and Failure Signals") with the same structure: signal, type, assertion. Each failure signal should specify the agent's required action: block, warn, retry, or escalate to human.

---

## Finding 4 — Known Friction Points are human-readable but not agent-actionable

**Severity: moderate**

The Known Friction Points sections describe real problems but in a form that only a human product manager can act on. An agent reading these sections gets context about what might go wrong, but no instructions for what to do when it does.

Examples:

- **first-install / "Prerequisite sprawl"**: A developer who doesn't have Go installed may bounce. For an agent, the actionable version is: "before running onboard, check `command -v go`; if missing, emit a structured warning with install instructions and do not proceed to sprint." The friction point describes the problem; it doesn't give the agent a guard clause.

- **running-a-sprint / "Complexity misclassification"**: A task may be underestimated, leading to an undersized workflow. For an agent, the actionable version is: "if execution phase discovers >3x the expected file scope, escalate complexity re-classification before continuing." The friction point is diagnostic, not prescriptive.

- **code-review / "Re-review cost"**: Re-running review re-dispatches all agents, not just relevant ones. For an agent, this is a known inefficiency it could work around — but only if told to. "On re-review, if the diff since last review touches <20% of original files, dispatch only agents whose previous findings overlapped with the changed files."

- **code-review / "Dismissal friction"**: The tension between fast dismissal and informative dismissal is unresolved. An agent needs a default: "record dismissal reason in a structured field; if no reason given, default to `not-applicable`."

**Recommendation:** For each friction point, add a one-line "Agent mitigation" that specifies what an agent should do when it encounters the condition. This transforms friction points from "things that might go wrong" into "guard clauses the agent implements."

---

## Finding 5 — running-a-sprint signals are not machine-readable enough for Interspect calibration

**Severity: high for Interspect integration**

The running-a-sprint CUJ is described as the canonical sprint description, and its signals should feed Interspect calibration. But the signals as written cannot be ingested by a pipeline without significant interpretation.

Specific gaps:

- **No event schema.** The signals reference things an agent would record (intervention count, phase transitions, tokens spent, model dispatches), but don't specify the event type names or field schemas that Interspect would consume. Interspect needs `sprint.phase_transition {phase: "brainstorm", timestamp: T}`, `sprint.intervention {type: "gate_failure", phase: "execute"}`, `sprint.dispatch {model: "haiku", subtask: "rename_variable"}`. The CUJ describes the *meaning* of these events but not their *structure*.

- **No aggregation boundaries.** "Sprint completes without unnecessary human intervention" — what counts as one intervention? A single message to the developer? A gate failure that requires action? A clarifying question? The CUJ says "intervention count is 0 for routine work, <=2 for complex work" but doesn't define the unit. Interspect needs a countable event type, not a description.

- **No calibration feedback format.** "Complexity classification matches actual effort" should produce a calibration record: `{estimated: 3, actual_tokens: 45000, actual_phases: ["brainstorm", "plan", "execute", "ship", "reflect"]}`. The CUJ describes the *intent* of this calibration but not the record shape.

- **No threshold for "bead is closed with complete metadata."** What constitutes "complete"? Which fields must be populated? An agent checking `bd show <id>` needs to know the required field list: status, claimed_by, closed_at, complexity, cost, ...? Without this, "all state fields populated" is unverifiable.

**Recommendation:** Add an "Interspect Schema" subsection to running-a-sprint that defines the event types, field names, and aggregation units that map to each signal. This makes the CUJ not just a description of the sprint but a contract for Interspect's data model.

---

## Finding 6 — code-review signals conflate current capabilities with Phase 2 plans, creating false guardrails

**Severity: moderate**

The code-review CUJ mixes currently-working signals with signals that depend on unshipped features, without distinguishing them. An agent using these signals as guardrails today would attempt to verify behavior that doesn't exist.

Specific cases:

- **"Interspect adjusts routing based on review outcomes"** — the CUJ narrative explicitly notes this is "Phase 2" and "partially shipped." But the success signal table doesn't carry this qualification. An agent reading the table gets a guardrail it cannot evaluate.

- **"Verdict confidence correlates with quality"** — requires regression tracking that isn't described as implemented anywhere. An agent can record the confidence score today but cannot evaluate the correlation without post-merge regression detection.

- **"Review cost trends downward per change"** — requires Interspect's optimization loop to be active. If Interspect isn't adjusting routing yet, this metric will be flat or random. An agent tracking it would see no trend and might report a failure.

**Recommendation:** Add a `status` column to the success signals table: `active` (agent can check this now), `recording` (agent should record data but not gate on it), `planned` (agent should skip). This prevents agents from trying to enforce future capabilities as current guardrails.

---

## Finding 7 — first-install CUJ has no signal for the most common failure mode: partial install

**Severity: high**

The first-install CUJ covers "install completes without errors" and "onboarding produces valid structure" but nothing in between. The most likely failure mode for a new user is partial success: Clavain installs but a companion plugin fails, onboarding creates CLAUDE.md but beads init fails because Go isn't installed, the first sprint starts but the discovery scanner can't find beads because the database isn't running.

An agent monitoring this journey needs checkpoint assertions:

1. After `claude install clavain`: plugin is listed in `claude plugins list`
2. After companion installs: each requested companion appears in `claude plugins list`
3. After onboard: each expected artifact exists (`test -f CLAUDE.md && test -f AGENTS.md && test -d .beads && test -d docs`)
4. After beads init: `bd list` exits 0 (database is accessible)
5. After first `/route`: structured output contains at least one option

The current signals jump from "install completes" to "onboard produces valid structure" to "sprint reaches Ship phase" — three large gaps where an agent has no intermediate assertions to detect partial failure.

**Recommendation:** Add checkpoint signals at each transition point in the journey. These don't need to be in the main success signals table — a separate "Checkpoint Assertions" subsection would suffice. Each checkpoint should have a command, expected output, and failure action.

---

## Summary

| # | Finding | Severity | CUJ(s) |
|---|---------|----------|---------|
| 1 | Measurable signals lack setup clauses and scope labels | blocking | all three |
| 2 | Observable signals don't name hooks, events, or file paths | blocking | all three |
| 3 | No failure signals — agents don't know what to block on | high | all three |
| 4 | Known Friction Points lack agent mitigations | moderate | all three |
| 5 | Sprint signals aren't Interspect-ingestible without event schemas | high | running-a-sprint |
| 6 | Phase 2 signals mixed with active signals create false guardrails | moderate | code-review |
| 7 | No checkpoint assertions for partial install failure | high | first-install |

### Cross-cutting recommendation

The CUJs are well-written as human planning documents. To make them agent-usable as guardrail definitions, each signal needs three additions: (1) a concrete assertion an agent can execute (command + expected output), (2) a scope label (single-run, multi-sprint, or planned), and (3) a failure action (block, warn, record, skip). The Known Friction Points need agent mitigations. And running-a-sprint needs an Interspect event schema subsection to serve as the calibration contract.
