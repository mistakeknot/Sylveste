# fd-signal-quality: Success Signals Review

**Scope:** Success Signals tables in `docs/cujs/first-install.md`, `docs/cujs/running-a-sprint.md`, `docs/cujs/code-review.md`
**Reviewer lens:** Test engineering — can each signal gate a CI run, be observed in telemetry, or genuinely require a human?

---

## Summary

- **33 signals total** across 3 CUJs (11 + 13 + 9). Counts are healthy (3-15 target met per CUJ).
- **8 signals have type/assertion mismatches** — labeled measurable but missing thresholds, or labeled observable but actually measurable or qualitative.
- **4 signals are unfalsifiable or circular** — they reference trends without baselines, or define success in terms of themselves.
- **3 cross-CUJ duplications** — first-install and running-a-sprint both cover sprint phases, bead closure, and test-passing, without explicit delegation.
- **6 measurable signals lack a concrete pass/fail command** — they state a threshold but no way to collect the measurement.

---

## Per-Signal Findings

### CUJ: first-install.md (11 signals)

| # | Signal | Type | Verdict |
|---|--------|------|---------|
| 1 | README communicates value proposition | qualitative | **PASS.** Genuinely requires human judgment — no automation can assess comprehension. |
| 2 | Install completes without errors | measurable | **PASS.** `claude install clavain; echo $?` is a concrete gate. |
| 3 | Install and onboard < 10 minutes | measurable | **DEFECT: No measurement command.** How is elapsed time captured? There is no instrumentation described. A stopwatch is not a gate. Needs: a kernel event pair (install_start, onboard_complete) with a timestamp delta assertion, or a CI harness that wraps the two commands and checks wall-clock time. |
| 4 | Onboarding produces valid structure | measurable | **DEFECT: Incomplete threshold.** Asserts file creation but not file validity. `CLAUDE.md` could be empty and this passes. Tighten: each file must be non-empty and parseable (YAML frontmatter for AGENTS.md, TOML for .beads/config). Suggest: `test -s CLAUDE.md && test -s AGENTS.md && test -d .beads && test -d docs`. |
| 5 | First `/route` presents actionable options | observable | **DEFECT: Mislabeled.** "User sees 'Start fresh brainstorm' option" is a UI assertion that can be automated (string match on terminal output). This is measurable, not observable. If it stays observable, specify the instrumentation surface: what event or file write proves the option was rendered? |
| 6 | Sprint reaches Ship without manual intervention | measurable | **DEFECT: No pass/fail mechanism.** How is "manual intervention" counted? No event schema is cited. Needs: a kernel event `phase_transition` log with an `intervention_required` boolean, or an intercore event query. Also duplicated in running-a-sprint signal #8 — see cross-CUJ section. |
| 7 | At least one review finding is acted upon | observable | **DEFECT: Missing instrumentation surface.** Which file, event stream, or hook records that a finding was "acted upon"? The code-review CUJ describes flux-drive-output files and kernel events, but this signal doesn't reference them. Specify: `review_events` table with `action=applied`, or a diff between pre-review and post-review commits that touches lines cited in a finding. |
| 8 | Change lands on main with passing tests | measurable | **PASS.** `git log -1` + test exit code is concrete and gateable. Minor: specify which test command (`go test ./...`? `make test`? project-dependent?). |
| 9 | Bead is closed at sprint end | measurable | **PASS.** `bd show <bead-id>` with status check is concrete. Duplicated in running-a-sprint #9. |
| 10 | First sprint time is reasonable | qualitative | **PASS with reservation.** "Feels proportionate" is genuinely qualitative, but dangerously close to unfalsifiable. Consider adding a measurable companion: "First sprint on a <100-line change completes in <30 minutes" to anchor the qualitative judgment. |
| 11 | Developer understands what happened | qualitative | **PASS.** Requires interview or survey — correctly qualitative. |

### CUJ: running-a-sprint.md (13 signals)

| # | Signal | Type | Verdict |
|---|--------|------|---------|
| 1 | `/route` presents work within 5 seconds | measurable | **DEFECT: No measurement command.** What instruments the latency? Needs: a timer wrapper (`time clavain route 2>&1`), a kernel event with timestamp, or a performance test harness. Without specifying the measurement surface, this is aspirational, not gateable. |
| 2 | Complexity classification matches actual effort | measurable | **DEFECT: Unfalsifiable as written.** "Correlates with actual tokens spent and phases needed" — what correlation coefficient? What threshold? r>0.5? Complexity 3 maps to 50K-200K tokens? Without concrete bins or a statistical threshold, this cannot pass or fail. Also: who computes the correlation? At what cadence? This is a post-mortem metric dressed as a measurable signal. Reclassify as observable with a specified data pipeline, or add concrete bins (e.g., "complexity-1 tasks use <20K tokens, complexity-5 tasks use >100K tokens"). |
| 3 | Brainstorm surfaces non-obvious insight | qualitative | **PASS.** Genuinely requires human evaluation. |
| 4 | Plan is executable without ambiguity | qualitative | **PASS.** Requires human reading — correctly typed. |
| 5 | Execution follows codebase patterns | observable | **DEFECT: Missing instrumentation surface.** What detects pattern conformance? Lint rules? AST comparison? Human spot-check? If lint, it's measurable. If human, it's qualitative. "Observable" implies there's a sensor — name it. Candidate: `golangci-lint` output, or a custom pattern-matching rule in flux-drive. |
| 6 | Tests pass after each incremental commit | measurable | **PASS.** Gateable via CI or a post-commit hook that runs the test suite. Concrete command: `git log --oneline <sprint-range> | while read sha _; do git checkout $sha && make test; done`. |
| 7 | Model routing uses cheapest sufficient model | observable | **DEFECT: Missing instrumentation surface.** Where are dispatch records? Kernel events? intercore logs? Interspect telemetry? Specify: "dispatch events in `intercore events` include `model_selected` and `model_tier`, queryable with `ic events list --type=dispatch`" or similar. Without naming the data source, this is a hope, not an observable. |
| 8 | Sprint completes without unnecessary intervention | measurable | **DEFECT: Threshold is soft.** "0 for routine, <=2 for complex" — who classifies routine vs. complex? The complexity classifier (signal #2) is itself unfalsifiable. This creates a circular dependency: signal #8 depends on signal #2, which has no concrete threshold. Fix: define intervention count thresholds independent of the complexity classifier, or anchor to concrete scenarios ("a sprint that only modifies <5 files in 1 package requires 0 interventions"). |
| 9 | Bead closed with complete metadata | measurable | **DEFECT: "All state fields populated" is vague.** Which fields? List them: status, claimed_by, claimed_at, closed_at, complexity, phase. A concrete check: `bd show <id> --json | jq '.status, .complexity, .closed_at' | grep -v null`. Duplicated from first-install #9 (see cross-CUJ section). |
| 10 | Reflect phase produces reusable learnings | observable | **DEFECT: Missing instrumentation surface.** "Solution doc or calibration data is written to persistent storage" — which path? `docs/solutions/`? `.interspect/calibration/`? Specify the file glob or database table. A concrete check: `ls docs/solutions/*<bead-id>*` or `ic state get reflect_complete <bead-id>`. |
| 11 | Cost per landable change trends downward | measurable | **DEFECT: Unfalsifiable — no baseline, no timeframe, no magnitude.** "Trends downward" over what period? Compared to what starting value? A 0.1% decrease over 6 months technically satisfies this. Needs: "Cost per landable change decreases by >=10% over 30 sprints, measured from $BASELINE" or similar. Also requires specifying the measurement: `interstat` query? `cass analytics tokens`? The MEMORY.md mentions a cost baseline of $1.17/landable change and a query script at `interverse/interstat/scripts/cost-query.sh` — reference these. |
| 12 | Multi-session resume preserves progress | measurable | **DEFECT: No pass/fail command.** "Does not re-execute completed steps" — how is this detected? Needs: completed step IDs in checkpoint state, assertion that execution log in session 2 starts at step N+1, not step 1. Specify the checkpoint format and the verification command. |
| 13 | Failed sprints surface the problem clearly | observable | **DEFECT: Missing instrumentation surface and partially qualitative.** "Identifies the root cause, not just the symptom" requires judgment — is the error message clear? That's qualitative. If observable, specify: "gate failure events include `error_category` and `suggested_action` fields" and assert those fields are non-empty. |

### CUJ: code-review.md (9 signals)

| # | Signal | Type | Verdict |
|---|--------|------|---------|
| 1 | Triage selects relevant agents only | observable | **DEFECT: Missing instrumentation surface.** How is "relevant" evaluated post-hoc? Needs: a log of dispatched agents with their declared capabilities, cross-referenced against the detected change type. Specify: "dispatch manifest at `.claude/flux-drive-output/dispatch.json` includes `agent`, `capabilities`, and `change_type`." Without this, relevance is evaluated by a human reading agent names — that's qualitative. |
| 2 | Agent dispatch < 2 minutes | measurable | **DEFECT: No measurement command.** Wall-clock time of what? The `flux-drive` invocation? A kernel event pair? Specify: `time clavain quality-gates` or "elapsed_ms in `dispatch_complete` event < 120000". Also: "typical changes" is undefined — what's the size/complexity bound? |
| 3 | Synthesis deduplicates overlap | measurable | **PASS.** "Finding count in synthesis < sum of individual agent findings" is concrete and verifiable from the output files. Check: count findings in each `fd-*.md`, sum them, compare to `synthesis.md` finding count. |
| 4 | At least one finding is genuinely actionable | qualitative | **PASS.** Requires human judgment on whether the finding matters — correctly typed. |
| 5 | Majority of findings acted upon | measurable | **DEFECT: No measurement surface.** How are "acted upon" vs. "dismissed" recorded? The CUJ narrative describes act/dismiss/discuss as developer actions, but no event schema or file format is specified for recording these responses. Needs: a review_events record with `response` field, queryable with a concrete command. Without this, the >50% threshold is uncheckable. |
| 6 | Verdict confidence correlates with quality | observable | **DEFECT: Unfalsifiable as written.** "Don't precede post-merge regressions" requires (a) tracking regressions, (b) linking them to specific review verdicts, (c) statistical analysis over a meaningful sample. This is a research question, not an observable signal. It cannot be checked in any single sprint or review cycle. Reclassify as a long-term metric with explicit data pipeline requirements, or remove and replace with a per-review signal like "verdict confidence is >0.8 for approve verdicts." |
| 7 | Developer reads the full report | qualitative | **PASS.** "Concise enough to read" is genuinely about human experience. Consider: this is very hard to verify even qualitatively — it's closer to a design goal than a signal. But it's correctly typed. |
| 8 | Review cost trends downward | measurable | **DEFECT: Same unfalsifiable pattern as running-a-sprint #11.** No baseline, no timeframe, no magnitude. "Token spend decreases" — from what starting point? Over how many reviews? Measured how? Duplicated problem from running-a-sprint. Fix identically: concrete baseline, timeframe, magnitude, measurement command. |
| 9 | Interspect adjusts routing based on outcomes | observable | **DEFECT: Missing instrumentation surface.** "Agent dispatch patterns change" — change detected how? Diff of dispatch manifests across sprints? An Interspect configuration changelog? Specify the observable artifact. Also partially contradicted by the CUJ narrative itself, which notes this is "Phase 2" — making it a signal for unshipped functionality. |

---

## Cross-CUJ Signal Duplication

Three signal clusters appear in multiple CUJs without explicit delegation:

### 1. Bead closure
- **first-install #9:** "Bead is closed at sprint end" — `bd show` reports CLOSED
- **running-a-sprint #9:** "Bead is closed with complete metadata" — `bd show` reports CLOSED + all fields populated

The running-a-sprint version is strictly stronger. First-install should either defer to running-a-sprint ("see running-a-sprint signal #9") or weaken to "bead exists" (since for first-install, the existence of the bead is the novel thing, not its metadata completeness).

### 2. Sprint completion / intervention count
- **first-install #6:** "Sprint reaches Ship without manual intervention"
- **running-a-sprint #8:** "Sprint completes without unnecessary human intervention" (with thresholds)

First-install uses this as a first-run smoke test; running-a-sprint uses it as an ongoing quality metric. Neither references the other. First-install should cross-reference and note it's testing the zero-intervention case specifically.

### 3. Cost trending
- **running-a-sprint #11:** "Cost per landable change trends downward"
- **code-review #8:** "Review cost trends downward per change"

Both are unfalsifiable (see individual findings). They also overlap: review cost is a component of sprint cost. The running-a-sprint signal should be the canonical cost signal, and code-review should measure review-specific cost as a component (e.g., "review token spend is <15% of total sprint token spend").

---

## Structural Findings

### S1: No signals cover the Brainstorm-to-Strategy handoff (running-a-sprint)
The journey narrative describes brainstorm, strategy, plan, execute, ship, reflect — six phases. Signals cover brainstorm (#3), plan (#4), execute (#5, #6, #7), ship (implicit in #6), and reflect (#10). **Strategy has zero signals.** The strategy is described as "the contract between the human and the agency" — whether that contract is clear and complete is a testable property. Add: a qualitative signal ("Strategy has explicit scope, success criteria, and non-goals") or a measurable one ("Strategy document contains sections: scope, success-criteria, non-goals, each non-empty").

### S2: No signals cover error recovery (first-install)
The Known Friction Points section explicitly calls out "Error recovery on first run" as a risk: "If a gate fails... the developer has no mental model for debugging." Yet no signal tests whether error recovery works. Add: an observable signal for first-run error messages ("Gate failure during first sprint produces an error message that names the failing gate, the phase, and a suggested next action") with instrumentation surface (error event schema).

### S3: "Observable" is used for two different things
Some "observable" signals describe automated telemetry that could be queried (model routing dispatches, agent selection logs) — these should be measurable once the instrumentation exists. Others describe emergent system behavior that requires human pattern-matching (execution follows codebase patterns, failed sprints surface problems clearly). The type label "observable" conflates "we have sensors but no threshold" with "a human has to look at this." Consider splitting into:
- **observable-instrumented**: data is collected, no pass/fail threshold defined yet
- **observable-human**: requires human inspection of system behavior

### S4: Qualitative signals are well-chosen
All 6 qualitative signals (across all 3 CUJs) genuinely require human judgment. None are catch-alls for things that could be automated. This is a strength — the temptation to dump hard-to-measure things into "qualitative" was resisted.

---

## Severity Summary

| Severity | Count | Description |
|----------|-------|-------------|
| **Unfalsifiable** | 4 | Signals that cannot pass or fail as written (complexity correlation, cost trends x2, verdict-quality correlation) |
| **Missing measurement command** | 6 | Measurable signals with thresholds but no specified way to collect the measurement |
| **Missing instrumentation surface** | 7 | Observable signals that don't name the sensor, event, file, or API |
| **Type mislabel** | 2 | Signal typed as observable but actually measurable or qualitative |
| **Cross-CUJ duplication** | 3 | Same signal in multiple CUJs without explicit delegation |
| **Missing phase coverage** | 2 | Journey phases with no corresponding signal (strategy, error recovery) |
| **Pass** | 12 | Signals that are concrete, correctly typed, and gateable or evaluable |

---

## Recommended Fixes (Priority Order)

1. **Fix the 4 unfalsifiable signals** — add baselines, timeframes, and magnitude thresholds. Reference `interverse/interstat/scripts/cost-query.sh` and the $1.17 baseline for cost signals. Define complexity bins for the correlation signal. Replace verdict-confidence correlation with a per-review check.

2. **Add measurement commands to the 6 measurable signals missing them** — each needs a concrete shell command, API call, or event query that returns pass/fail.

3. **Name instrumentation surfaces for the 7 observable signals** — file paths, event types, database tables, or hook IDs. If the instrumentation doesn't exist yet, note it as a dependency and mark the signal as "blocked on: [component]".

4. **Resolve the 3 cross-CUJ duplications** — make running-a-sprint the canonical owner of sprint-phase signals, and have first-install cross-reference with first-run-specific narrowing.

5. **Add signals for uncovered phases** — strategy (running-a-sprint) and error recovery (first-install).

6. **Consider splitting "observable" into instrumented vs. human subtypes** — optional but would clarify the contract each signal makes.
