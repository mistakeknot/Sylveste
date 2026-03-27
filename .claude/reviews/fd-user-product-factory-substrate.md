---
artifact_type: review
reviewer: fd-user-product
prd: docs/prds/2026-03-05-factory-substrate.md
brainstorm: docs/brainstorms/2026-03-05-factory-substrate-brainstorm.md
bead: iv-ho3
date: 2026-03-05
---

# User & Product Review: Factory Substrate (iv-ho3)

## Primary User and Job

Primary user: a developer running Clavain for autonomous sprint execution. Their job is to
ship code changes with minimal manual intervention while maintaining confidence that
autonomous agents are not regressing correctness. They interact through Claude Code slash
commands, the `clavain-cli` binary, and YAML files in `.clavain/`.

Secondary user: the Sylveste platform itself — agents that self-build Sylveste using Clavain
tools. The PRD explicitly calls out "self-building validation" as a target outcome.

---

## Findings

### P0 — CXDB as Required Infrastructure Raises the Barrier to Entry Unacceptably at This Stage

**Finding:** Making CXDB a hard requirement adds a Rust binary dependency that has no
upstream pre-built releases. The PRD's own dependency list states: "StrongDM doesn't
publish GitHub releases yet. Need to build from source (Rust toolchain) and cache the
binary, or request releases from StrongDM." This means every user who runs `clavain setup`
will either encounter a bespoke caching mechanism with unclear provenance, or need to
install a Rust toolchain to build CXDB themselves. The first-stranger experience PRD
(iv-t712t) explicitly specifies "No Go builds, no systemd, no platform-specific package
managers" for the install path. CXDB from source adds a Rust build to that list.

The PRD's rationale for "required not optional" cites the Dolt precedent. But Dolt
distributes official pre-built binaries for all platforms via GitHub releases. The
comparison does not hold until CXDB does the same. The brainstorm acknowledges this but
treats it as a logistics detail. It is a product gate: until upstream releases exist,
"required infrastructure" means "required Rust toolchain" for new users.

**Evidence:** PRD §Dependencies: "StrongDM doesn't publish GitHub releases yet." First-
stranger PRD §F2 acceptance criteria: "No Go builds, no systemd, no platform-specific
package managers." Dolt releases: https://github.com/dolthub/dolt/releases shows 400+
versioned platform binaries.

**Recommendation:** Downgrade CXDB from required to strongly-preferred for this iteration.
Auto-start only if the binary is present; emit a clear warning when absent, explaining what
degrades (sprint execution recording, scenario trajectory storage) but allow sprints to
proceed. Publish a contribution to CXDB upstream for GitHub Actions release artifacts as a
parallel work item. Flip to required once upstream binary distribution exists. This is a
one-flag change in `cxdb-start`: `if binary not found: warn and no-op` instead of `fatal`.

---

### P0 — Satisfaction Threshold of 0.7 Ships Without Closed-Loop Calibration

**Finding:** F4 sets a default gate threshold of 0.7 for holdout satisfaction but the PRD
does not include the calibration machinery that PHILOSOPHY.md mandates for any system that
makes a judgment. Specifically, PHILOSOPHY.md's "Closed-loop by default" section says: any
system that makes a judgment "MUST close the loop: predict, observe the outcome, feed the
outcome back to improve the next prediction. Automatically, not manually." The four
required stages are: hardcoded defaults, collect actuals, calibrate from history, defaults
become fallback. This PRD ships stages 1-2 (default threshold + score recording to CXDB)
but stages 3-4 (calibrate from historical pass/fail rates, adaptive threshold) are
absent — not deferred to a named follow-on, just missing.

The brainstorm's Open Question 5 asks whether this "should follow the closed-loop pattern"
and answers with a trailing question mark. That question has a definitive answer in
PHILOSOPHY.md: yes, it must. A gate that emits scores without ever adjusting its threshold
from those scores is "a constant masquerading as intelligence" by the project's own
definition.

The immediate user impact is false positives blocking Ship. Without calibration, the 0.7
threshold is an arbitrary number. Too high and autonomous sprints stall before shipping.
Too low and the gate is meaningless. Users have no feedback on why their threshold is wrong
or how to tune it beyond guessing.

**Evidence:** PHILOSOPHY.md §Receipts Close Loops: "Closed-loop by default. Any system
that makes a judgment [...] MUST close the loop." The four-stage pattern table lists "Gate
thresholds" explicitly. PRD F4 acceptance criteria: no calibration step. Open Question 5
deferred without resolution.

**Recommendation:** Add a calibration stage as an acceptance criterion for F4. Minimum
viable: `clavain-cli scenario-threshold-calibrate` reads historical `satisfaction.json`
run files, computes false-positive rate (threshold passed but merge caused regression) and
false-negative rate (threshold blocked a clean change), and writes a calibrated threshold
back to `.clavain/policy.yml`. Ship the default (0.7), collect actuals (already done via
CXDB), add calibration (one command reading satisfaction history), and fall back to 0.7
when history is absent. This is a small addition — roughly the same complexity as
`scenario-score --summary` — but it closes the loop.

---

### P1 — Scenario Authoring UX Has No Entry Point for New Projects

**Finding:** The PRD defines the scenario YAML schema and the `scenario-create` scaffold
command, but leaves Open Question 4 ("who writes scenarios — human, agent, or both?")
entirely unresolved. For a developer adopting Clavain on a new project, the scenario bank
starts empty. The holdout gate cannot block Ship if there are no holdout scenarios. This
means the gate is silently a no-op for the first N sprints until someone authors scenarios.
Users will not know the gate is inactive, and will not understand what they need to do to
activate it.

The brainstorm mentions a hypothetical `/scenario:generate` command but defers it. F5 wires
flux-drive review findings to auto-create holdout scenarios from regressions — but that
requires a regression to have already occurred, which means the gate was already open when
the regression shipped. The bootstrapping sequence is: no scenarios → gate is no-op → first
regression ships → auto-generate scenario → gate activates. This is backwards for the
stated goal of preventing regressions.

There is no progressive disclosure path from "I just installed Clavain" to "I have a
functioning holdout gate." The PRD assumes users know to run `scenario-create` and write
YAML rubrics before their first sprint. That is not a reasonable assumption.

**Evidence:** PRD §F3 lists `scenario-create` and `scenario-list` but no seeding flow.
PRD §F4 gate criteria do not address what happens when holdout/ is empty. Brainstorm Open
Question 4 deferred. F5 evidence pipeline creates scenarios reactively from failures, not
proactively from project structure.

**Recommendation:** Add an explicit "no scenarios" state with user-visible guidance. When
`enforce-gate` checks holdout satisfaction and finds zero holdout scenarios, emit a named
warning: "No holdout scenarios configured. Gate is inactive. Run `clavain-cli scenario-
generate` to create scenarios from existing tests, or `scenario-create` to author
manually." Define `scenario-generate` (the deferred `/scenario:generate`) as an F3
acceptance criterion for this PRD, not a follow-on. It can be thin: read the project's
test files and existing specs, infer three to five scenario stubs, write them to
`.clavain/scenarios/dev/` as starting points for human curation. This turns the empty-bank
problem into a one-command activation.

---

### P1 — Holdout Separation Relies on Policy-Check Soft Enforcement with No Audit Trail for Bypasses

**Finding:** F6 defines the policy framework but the enforcement mechanism is "clavain-cli
`policy-check` command that gates tool dispatch" — a soft check, not a filesystem-level
constraint. The brainstorm explicitly notes: "enforcement via clavain-cli policy (not
filesystem permissions — agents can read anything)." This means an implementation agent
that ignores or fails to call `policy-check` before a tool dispatch will silently bypass
holdout separation. The holdout bank's integrity depends entirely on every code path
calling `policy-check` before every file read.

The PRD records policy violations as CXDB turns (`clavain.policy_violation.v1`), which is
good for post-hoc audit. But post-hoc audit of holdout contamination does not repair the
contamination: if a Build-phase agent read the holdout scenarios, the separation is already
broken for that sprint. The user impact is that the holdout gate can generate inflated
satisfaction scores (the agent optimized for what it was not supposed to see) without any
runtime signal that contamination occurred.

**Evidence:** Brainstorm §Holdout separation: "enforcement via clavain-cli policy (not
filesystem permissions — agents can read anything)." F6 acceptance criteria: "Policy
violations recorded as CXDB turns." No acceptance criterion for "sprint is quarantined or
re-run when contamination is detected."

**Recommendation:** Add one acceptance criterion to F6: "If a policy violation of type
`holdout_read` is recorded for a sprint, the satisfaction gate for that sprint is
automatically invalidated and the sprint cannot advance to Ship without human override with
auditable reason." This converts the audit trail from a historical record into an active
control. The mechanism is simple: `enforce-gate` queries CXDB for `clavain.policy_
violation.v1` turns in the current sprint context before accepting satisfaction scores.

---

### P1 — Six Features in One PRD Is Too Much for a Single Iteration

**Finding:** The PRD bundles F1 (CXDB service lifecycle), F2 (sprint recording), F3
(scenario bank + CLI), F4 (satisfaction scoring + gate), F5 (evidence pipeline wiring),
and F6 (agent capability policies) into one unit of work. The brainstorm's implementation
priority already implicitly acknowledges this by phasing F1-F2 before F3-F4 before F5
before F6. But those phases are not bead boundaries — they are all under bead iv-ho3.

The brainstorm table re-scopes nine child beads (iv-c2r, iv-296, iv-wbh, iv-2li, iv-3ov,
iv-b46, iv-1hu, iv-d32, iv-txw) but maps all the active work into this single PRD rather
than distributing it across those children. The result is a PRD with 42 acceptance criteria
across six features. A single sprint run against a 42-AC scope will either time out,
partially complete with unclear state, or require multiple sessions with hand-off
complexity.

The stated MVP signal is: "holdout satisfaction gates Ship." That requires F1 (CXDB up),
F3 (scenarios exist), and F4 (scoring + gate). F2 (full recording), F5 (evidence
pipeline), and F6 (policies) are the "while we're here" additions. They each add value but
none of them are necessary for the first satisfaction gate to block a Ship.

**Evidence:** PRD contains 42 acceptance criteria across 6 features. Brainstorm §Implementation
Priority explicitly sequences four phases. Child beads iv-c2r, iv-296, iv-3ov, iv-b46
already exist as separate bead IDs. The stated keystone (scenario bank + satisfaction
scoring) is F3+F4, not all six.

**Recommendation:** Keep the PRD as the design document but map features to their existing
child beads for execution: F1+F2 to iv-296 (CXDB adoption), F3+F4 to iv-c2r (scenario
bank), F5 to iv-3ov (evidence pipeline), F6 to iv-b46 (capability policies). Define
iv-c2r as the first sprint — it can start once iv-296 has a CXDB binary present, even if
CXDB is in graceful-degradation mode. This gives each sprint a clear done-state and a
measurable exit condition.

---

### P2 — CXDB Type Registry Bootstrapping Is Undefined but Blocks All Recording

**Finding:** Open Question 2 asks whether to ship `clavain-types.json` or register lazily.
The PRD leaves it open. But this is not an aesthetic choice — it is a blocking dependency.
All of F2, F3, F4, F5 record typed turns (`clavain.phase.v1`, `clavain.scenario.v1`,
etc.). If type bundles are not registered before the first turn, the write either fails or
falls back to untyped data that cannot support the `QueryByType` queries that F4 and
Interspect depend on.

Lazy registration is the simpler implementation path but creates a race condition: if two
sprint phases register the same type bundle concurrently (possible with parallel dispatch),
CXDB's behavior on duplicate registration is not documented in the PRD. The user-visible
failure mode is silent data loss: phase turns written as untyped blobs, satisfaction scores
that cannot be queried, Interspect that sees no evidence.

**Evidence:** PRD §Open Questions: "Type registry bootstrapping: [...] Ship [...] in setup?
Or register lazily on first sprint?" F2 acceptance criteria require `clavain.phase.v1`,
`clavain.dispatch.v1`, `clavain.artifact.v1` bundles. No acceptance criterion specifies
what happens if registration fails or is skipped.

**Recommendation:** Resolve this before implementation begins. The safe default is: ship
`clavain-types.json` alongside the CXDB binary in the setup flow, register all Clavain
type bundles during `cxdb-start` before the service accepts connections, and treat
registration failure as a fatal start error. Add one AC to F1: "`cxdb-start` registers all
Clavain type bundles from `clavain-types.json` before returning healthy." This eliminates
the race condition and makes type availability a precondition, not a runtime assumption.

---

### P2 — "Scenario Run" Execution Model Is Underspecified for the CLI Interface

**Finding:** `scenario-run <pattern> [--sprint=<id>]` is listed as an acceptance criterion
for F3, but the execution model is not specified. A scenario in the YAML schema has
`setup`, `steps`, and `rubric` — but how does the CLI execute a step like "Navigate to
cart" or "Submit order"? For software development scenarios (the primary use case), actions
are typically shell commands or file operations. For behavioral scenarios (testing
autonomous agent outputs), actions are prompts or intent descriptions that an LLM judges.
The schema as written supports both interpretations, but the CLI command must pick one or
the CLI's implementation scope explodes.

Without a defined execution model, scenario-run is not implementable. The acceptance
criterion ("executes matching scenarios and records trajectories") cannot be verified
because "executes" is undefined. This is the most implementation-blocking gap in the PRD.

**Evidence:** PRD §F3 AC: "`scenario-run <pattern> [--sprint=<id>]` executes matching
scenarios and records trajectories." Scenario YAML schema: steps are `action: "Navigate to
cart"` with `expect: "Cart shows 2 items"` — these are English prose, not shell commands.
No execution model section exists in the PRD or brainstorm.

**Recommendation:** Add an execution model specification to F3 before implementation. The
simplest viable model for this iteration: steps are evaluated by the LLM judge (`scenario-
score`) rather than mechanically executed. The CLI's `scenario-run` records the sprint
context and the scenario definition as a CXDB turn, then `scenario-score` invokes the
judge to evaluate whether the sprint's actual artifacts satisfy each step's `expect` field.
This avoids building a test executor and reuses the existing flux-drive judge agents. Add
an AC: "scenario-run records the scenario definition and current sprint artifact references
as a `clavain.scenario.v1` CXDB turn; no mechanical execution of steps." The rubric
scoring then becomes the operational definition of "execution."

---

### P3 — Measurable Success Signal Is Missing

**Finding:** The PRD has no post-release measurement criteria. There is no stated metric
for whether the factory substrate is working. The brainstorm's "What This Enables" section
lists capabilities (L3 autonomy, Interspect learning, sprint forking, self-building
validation) but no measurable outcomes to verify after shipping.

By PHILOSOPHY.md's own standard, the system must "instrument first, optimize later" and
must have "outcomes over proxies." The proxy is easy to define (scenarios created, scores
above threshold). The outcome is harder but essential: does shipping this substrate reduce
the rate at which autonomous sprints produce regressions? Is the holdout gate actually
catching bad changes?

Without a stated success signal, there is no way to know at T+30 days whether the factory
substrate is working, misconfigured, or silently producing meaningless scores.

**Evidence:** PRD has no §Success Metrics or §Measurement section. PHILOSOPHY.md:
"Instrument first, optimize later. Most agent systems have zero outcome feedback."

**Recommendation:** Add a measurement section with two signals. Leading indicator:
"holdout scenario coverage" — ratio of sprint Ship events where at least one holdout
scenario was evaluated. Target 80% within 30 days of shipping. Lagging indicator:
"satisfaction gate catch rate" — ratio of satisfaction gate blocks that were confirmed as
real regressions by post-merge review. Target: gate is not purely theatrical (>0% catch
rate within 90 days). These are small additions that make the post-release conversation
concrete.

---

## Flow Analysis

### Happy Path: Developer Runs First Autonomous Sprint with Holdout Gate Active

1. Developer runs `clavain setup` — CXDB binary downloaded and started, type bundles
   registered. (Undefined: what happens if CXDB binary is absent.)
2. Developer runs `scenario-generate` or `scenario-create` to populate holdout bank.
   (Undefined: this step is not prompted by any existing flow.)
3. Developer initiates sprint via `/clavain:route`.
4. Sprint phases execute; phase turns recorded in CXDB.
5. Sprint reaches quality-gates; `scenario-run` executes holdout scenarios.
6. `scenario-score` invokes flux-drive judges; writes `satisfaction.json`.
7. `enforce-gate` reads satisfaction score; blocks or allows Ship.
8. Developer sees result and either ships or investigates.

Missing states identified: Step 2 has no trigger. Step 5 has no defined execution model.
Step 7 has no contamination check. Step 8 has no explanation of why a specific scenario
failed (judge rationale is recorded but not surfaced in the gate output).

### Error Path: CXDB Service Crashes Mid-Sprint

No defined behavior in the PRD. The phase recording turns begin failing silently. The
sprint continues because `enforce-gate` is not yet reached. At Ship time, `scenario-run`
attempts to write to CXDB and fails. User sees an error at the final gate with no
explanation of the mid-sprint data gap.

Recommendation: `sprint-advance` should check CXDB health before writing each phase turn.
On failure, emit a warning and record the gap in the local sprint state file (already
used for checkpoint resume). At Ship time, if CXDB data is incomplete, surface the gap
rather than running satisfaction scoring against partial data.

### Error Path: Holdout Satisfaction Below Threshold

Gate blocks Ship. User sees a score (e.g., 0.58) and a threshold (0.70). The PRD does not
specify what the user sees next. The acceptance criterion for F4 includes "judge rationale"
in `satisfaction.json`, but there is no AC requiring that rationale to be surfaced in the
gate output. The user must know to run `cat .clavain/scenarios/satisfaction/run-<id>.json`
to understand what failed, which is a discovery barrier.

Recommendation: `enforce-gate` output when satisfaction fails should include the top-
failing criterion and the judge's reason inline. One line: "Gate blocked: criterion
'Inventory decremented' scored 0.2 (weight 0.3). Judge: 'No inventory update found in
artifacts.'" This converts a numeric rejection into an actionable finding.

---

## Verdict

The problem statement is sound and internally consistent with the platform philosophy. The
pain point (no externalized correctness definition, no outcome data for L3 autonomy) is
real and well-evidenced by the Oracle gap analysis. The adoption of CXDB over a build-your-
own implementation is the correct call and aligned with PHILOSOPHY.md.

The PRD is not ready to implement as written. Three issues require resolution before the
first sprint begins:

1. CXDB binary distribution must be resolved or the "required" designation must be
   downgraded to "strongly-preferred with graceful degradation" until upstream releases
   exist. (P0)

2. The scenario execution model must be specified so that `scenario-run` has a defined
   implementation target. Without this, F3's core acceptance criterion cannot be verified.
   (P2, but implementation-blocking)

3. The empty-scenario-bank bootstrapping path must be explicit — including a `scenario-
   generate` command or equivalent — so the holdout gate is not silently inactive for new
   adopters. (P1)

The remaining findings (closed-loop calibration, contamination invalidation, scope
distribution across child beads, success metrics) are important but do not block the first
sprint. They should be filed as acceptance criteria additions before iv-c2r begins, not
after.

Recommended pre-implementation actions:
- Resolve Open Question 1 (CXDB binary) with a concrete decision and document it.
- Resolve Open Question 2 (type registry) with the ship-in-setup approach.
- Add `scenario-generate` as an F3 AC.
- Add execution model definition to F3.
- Add calibration AC to F4.
- Add contamination invalidation AC to F6.
- Add success metrics section.
- Map features to child beads for execution scope control.
