---
artifact_type: flux-drive-finding
agent: fd-user-product
bead: sylveste-s3z6
reviewed: 2026-04-07
---
# FluxBench Closed-Loop Model Discovery — User & Product Review

**Primary user:** An interflux operator — a developer who runs flux-drive reviews and owns `model-registry.yaml`. Their job: ensure multi-agent reviews route to the best-available models without manual monitoring, and that quality doesn't silently degrade between sessions.

---

## Findings Index

| ID | Severity | Area | One-line summary |
|----|----------|------|-----------------|
| UP-01 | P0 | Flow gap | Challenger slot (F7) depends on mixed-mode dispatch that the CUJ explicitly flags as unimplemented — delivery order hides this blocker |
| UP-02 | P0 | Flow gap | discover-models.sh outputs query specs only; the weekly scheduled agent is the sole executor, but that agent is not defined in this PRD |
| UP-03 | P1 | Acceptance criteria | F4 drift demotion: no defined user-visible signal beyond "operator sees a drift event in the session output" — format, channel, and actionability unspecified |
| UP-04 | P1 | Scope | Persona adherence (metric 5 in F1) uses LLM-as-judge (Haiku) on every qualification run — cost per operator never stated; this is a product adoption risk |
| UP-05 | P1 | Edge case | Challenger slot: after 10+ runs the system "auto-evaluates" but no defined behavior when the challenger fails — it stays `qualifying` forever with no expiry, retry cap, or operator notification |
| UP-06 | P1 | Edge case | F4 version-triggered requalification fires on SessionStart — operator has no way to defer or suppress it when working under time pressure |
| UP-07 | P2 | Acceptance criteria | F2 ground-truth fixtures require human annotation, but the PRD contains no acceptance criterion for annotation quality, inter-annotator agreement, or how disputed findings are resolved |
| UP-08 | P2 | Flow gap | F5 auto-qualification creates a bead when a candidate qualifies — but no bead creation is specified for disqualification or repeated failure; operator cannot track candidates that are stuck |
| UP-09 | P2 | UX friction | SessionStart awareness message ("interrank: 2 new model candidates") has no affordance for suppression — operators who don't want to manage models will see this every session |
| UP-10 | P2 | Scope creep | F7 challenger findings tagged `[challenger]` in peer findings — no spec for how synthesis handles or discards this tag; ambiguity will require a synthesis change that is not scoped here |
| UP-11 | P3 | Value proposition | Success metric "FluxBench scoring agrees with human judgment at >=85% accuracy" has no measurement protocol — which fixtures, which annotators, when is this evaluated? |
| UP-12 | P3 | Delivery order | F6 (interrank TASK_DOMAIN_MAP) is Phase 3 but F5 proactive surfacing queries `recommend_model` starting in Phase 2 — F5 will query without FluxBench affinity boost until F6 lands, producing subtly wrong discovery results |

---

## Detailed Analysis

### UP-01 (P0) — Challenger slot blocks on unimplemented mixed-mode dispatch

The CUJ friction list states directly: "Cross-model dispatch is in shadow mode. Challenger slot needs dispatch in `enforce` mode for the challenger position, while rest stays in `shadow`. Mixed-mode dispatch isn't implemented yet."

F7 is slotted as Phase 3 work. The delivery order graph shows F7 depending on F4, which feeds the qualifying pool. But the actual blocker for F7 is not F4 — it is the absence of mixed-mode dispatch, which is not a FluxBench feature. This dependency is not listed in F7's dependency table and is not tracked anywhere in this PRD. An implementer reading the PRD will start F7 in Phase 3 only to discover the cross-model dispatch change is out of scope.

Recommendation: add mixed-mode dispatch as an explicit prerequisite to F7 in the dependency table, and either scope the dispatch change as F0 within this epic or create a blocking bead before F7 can start.

---

### UP-02 (P0) — Weekly auto-qualification agent is unspecified

F5's acceptance criteria say a weekly scheduled agent "runs `discover-models.sh`, auto-qualifies candidates with 3+ synthetic tasks from F2 fixtures." The PRD and CUJ both treat this agent as a given. But discover-models.sh (already implemented, read) outputs MCP query specs to stdout and explicitly states: "The orchestrator reads these and makes the actual MCP calls." The script cannot close the loop on its own.

The weekly agent that orchestrates MCP calls, interprets discover-models.sh output, and invokes fluxbench-qualify.sh does not exist and is not defined here. There is no agent spec, no prompt, no tool list, and no bead for building it. This is not a minor gap — it is the mechanism that converts passive discovery into automated qualification. Without it, F5 delivers only the hook-based awareness path (passive), not the automated discovery path (action), which is the differentiating value of Phase 2.

Recommendation: define the weekly agent explicitly in F5 scope. Specify: agent type (Claude Code background agent or cron-triggered script), tool access required (interrank MCP, file write to model-registry.yaml), and the orchestration contract with discover-models.sh.

---

### UP-03 (P1) — Drift demotion is invisible to the operator

F4 specifies that a demoted model triggers a "drift event written to fluxbench-results.jsonl." The CUJ says "the operator sees a drift event in the session output." These are incompatible: JSONL append is not surfaced in session output without a read path. Neither the PRD nor the CUJ specifies how the operator learns about the demotion in the moment it happens.

The real-world scenario is: the operator runs a flux-drive review, drift fires during sampling, the model is demoted, Claude silently takes over. The operator sees the review complete normally. The JSONL has a record, but the operator had no indication anything changed. This inverts the expected behavior — demotions are meaningful quality events that warrant operator attention, not silent background substitutions.

Acceptance criteria for F4 should include: what the operator sees when drift fires, through which channel (session output, hook message, bead creation), and what action the operator can take (acknowledge, suppress, trigger manual requalification).

---

### UP-04 (P1) — Persona adherence LLM cost is an adoption risk without a stated ceiling

Persona adherence (F1 core gate 5) uses Haiku-as-judge per qualification run. The PRD lists this as an open question ("Haiku per-run cost for persona scoring — acceptable at qualification volume?") but makes no attempt to bound it.

For a typical qualification run: 5 fixtures × 1 Haiku call each = 5 Haiku calls. At scale with challenger runs and drift re-qualifications, this compounds. The operator who sets `challenger_slot: true` has no cost transparency into how many Haiku calls that generates. If a weekly auto-qualification cycle runs on 5 candidates × 5 fixtures, that is 25 Haiku calls per week as a background tax, invisible until the invoice arrives.

This is a product decision that should be made explicit before F1 ships: either accept the LLM judge cost and document it as a known per-qualification expense, or defer persona adherence to the extended metrics group (where it arguably belongs) and exclude it from the 5 core gates that trigger pass/fail. The current design makes it both a core gate and a recurring background cost without a budget ceiling.

---

### UP-05 (P1) — Failing challenger has no exit path

F7 specifies: "After 10+ challenger runs: auto-evaluate qualification gate — promote or reject." The PRD says candidates failing mark to `candidate` with failure reason, "retried on next weekly cycle." But once a model is in the challenger slot and fails the 10-run evaluation, the PRD does not specify:

- Does it go back to `qualifying` or back to `candidate`?
- How many retry cycles before it is retired?
- Does the operator receive notification that the challenger evaluation failed?
- Is the challenger slot then filled by the next candidate, or does it stay empty until the weekly cycle runs again?

Without these states, the challenger mechanism can produce a permanent `qualifying` population that occupies the slot indefinitely, silently cycling through failing candidates while the operator has no visibility. The "creates bead if any candidate qualifies" criterion in F5 has no parallel for disqualification — failures are write-only events with no operator-visible outcome.

---

### UP-06 (P1) — Version-triggered requalification has no deferral mechanism

F4 specifies: "on SessionStart, compare active models' `qualified_date` against interrank snapshot `releaseDate` — version bump → trigger full requalification." Full requalification runs all F2 fixtures against the model. This is not instantaneous.

The operator starting a session to land a time-sensitive fix has no mechanism to say "I see the requalification trigger, skip it this session." There is no `--skip-requalification` flag or configurable deferral window. The PRD's zero-cost guarantee only applies to the awareness query in F5 — the version-triggered path in F4 is a different code path that may block or delay session startup.

The acceptance criteria for F4 should specify: synchronous vs. asynchronous execution, timeout behavior, and whether the operator can defer or override the trigger without editing config.

---

### UP-07 (P2) — F2 fixture quality criteria are absent

F2 acceptance criteria require "Ground-truth validated by human annotation (not Claude-generated baseline alone)" and a README. But there is no criterion for:

- How many annotators per fixture?
- What resolution process applies when annotators disagree on severity (e.g., one annotator calls a finding P1, another P2)?
- What happens when Claude's calibration run produces findings not in the ground-truth set — are they false positives by definition?

The calibration script (`fluxbench-calibrate.sh`) "computes threshold baselines" from the fixture set. If the ground-truth is thin or inconsistent, the thresholds are wrong from day one, and every subsequent FluxBench score is calibrated against a flawed anchor. This is the most upstream quality risk in the entire system.

---

### UP-08 (P2) — Stuck candidates have no beads

F5's bead creation criterion fires only on success: "Creates bead if any candidate qualifies." No bead is created when a candidate fails qualification on the weekly cycle, accumulates failures, or stalls in `candidate` status for months.

An operator looking at `model-registry.yaml` six weeks after initial deployment will find candidates with no associated work items, no failure log summary accessible through normal beads tools, and no indication whether they are actively being retried or silently abandoned. The model-registry YAML is readable, but beads is the single source of truth for work tracking per project convention. A candidate that has failed three weekly cycles warrants a bead for triage, not silent JSONL accumulation.

---

### UP-09 (P2) — SessionStart awareness message has no opt-out

The CUJ describes the hook message as: `interrank: 1 new model candidate (deepseek-v4) — run /flux-drive discover to qualify`. This fires every session start when there are registry gaps. For operators who are not in a model-management workflow — the majority of sessions — this is noise that cannot be dismissed without editing config.

The PRD does not specify a `model_discovery.awareness: false` toggle in budget.yaml, a suppression threshold (e.g., only surface if candidate score exceeds X), or a "don't show this again for N days" pattern. Compare this to the zero-cost guarantee stated in F5: the MCP query is zero-cost, but the attention tax on the operator is not.

---

### UP-10 (P2) — Challenger tag `[challenger]` has undefined synthesis behavior

F7 specifies challenger findings are "included in peer findings but flagged with `[challenger]` tag." The flux-drive synthesis phase reads peer findings for convergence scoring and cross-agent validation. The synthesis logic (wherever it lives) will encounter `[challenger]`-tagged findings and has no specified handling:

- Should challenger findings count toward finding-density convergence scores?
- Should they appear in the final Findings Index with or without the tag?
- If a challenger and a qualified agent both report the same P0 finding, does the challenger's report count as confirmation or noise?

This is a synthesis behavior change that is not scoped in F7 and not referenced in the dependency table. It will surface when F7 is integrated into real reviews.

---

### UP-11 (P3) — 85% accuracy success metric is unmeasurable as written

The success metric "FluxBench scoring agrees with human judgment on ground-truth fixtures at >=85% accuracy" is the key validation signal for the entire system, but the measurement protocol is absent:

- Which fixtures are used for this check (all F2 fixtures, a held-out validation set, a new set)?
- Who are the human judges (the original fixture annotators, independent reviewers)?
- Is accuracy measured per-finding or per-fixture?
- When is this evaluated — after F1 ships, after calibration, once per quarter?

Without a protocol, this metric cannot be used to declare the system healthy or unhealthy. It reads as a confidence-level statement rather than a testable criterion.

---

### UP-12 (P3) — F5 discovery uses un-boosted interrank results until F6 lands

F5 (Phase 2) queries `recommend_model` for new candidates. F6 (Phase 3) adds FluxBench affinity boost to interrank's TASK_DOMAIN_MAP so that FluxBench-scored models rank higher for code-review queries.

Between Phase 2 go-live and Phase 3 go-live, F5's auto-qualification will discover and qualify candidates based on interrank scores that do not yet reflect FluxBench data. This means the first cohort of auto-qualified models is selected by general benchmark rankings, not by FluxBench-relevant signal. This is not a blocking problem, but the delivery order implies F6 is optional polish when it is actually the signal-quality upgrade for F5. The PRD should note this interim state explicitly so operators understand discovery results improve after F6.

---

## Scope Assessment

The epic is appropriately sized for a C4 (complex feature). Seven features with clear dependency order and a phased delivery plan is coherent. The scope becomes strained at F7 (challenger slot) which carries a hidden dependency on mixed-mode dispatch infrastructure that crosses the epic boundary. If the mixed-mode dispatch work is not in-flight as a parallel bead, F7 will arrive at Phase 3 and find the platform not ready for it.

The non-goals are well-chosen. Finding survival rate tracking and cross-project FluxBench are correctly deferred. The store-and-forward AgMoDB approach (no REST write API) is the right call given AgMoDB's current ingest model.

## Smallest Change That Improves Confidence Before Full Build

Run fluxbench-calibrate.sh manually with 3 hand-annotated fixtures on the production Claude baseline and verify that the scoring engine's output matches operator judgment before building the automation layers. This validates the ground-truth quality assumption (UP-07), surfaces the LLM-judge cost concretely (UP-04), and confirms the metric definitions are coherent before F3-F7 depend on them. The entire closed loop rests on the calibration anchor — if that anchor is wrong, everything downstream is calibrated incorrectly.

<!-- flux-drive:complete -->
