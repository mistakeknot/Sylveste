### Findings Index
- P1 | TLM-01 | "MVP milestone + Open Questions: Measurement" | No primary metric committed; three candidates listed, pick-after-seeing invites motivated reasoning
- P1 | TLM-02 | "MVP milestone + D5 flux-drive triage view" | Baseline ("current filename-glob + tier heuristics") is not frozen; baseline will drift during the 7-week epic, invalidating A/B
- P1 | TLM-03 | "Open Questions: Measurement" | Held-out diff corpus is undefined — size, sampling method, ground-truth labeling process all missing
- P2 | TLM-04 | "D5 + MVP milestone" | Cost confound: ontology triage may pick more or more expensive agents; "more P0/P1 findings" then conflates quality with spend
- P2 | TLM-05 | "MVP milestone" | No pre-registered stopping rule or required sample size; "measurable lift" has no threshold
- P2 | TLM-06 | "D5 triage view" | User-accepted-verdict rate is listed as a candidate metric but has no labeling pipeline; introducing it late will reshape the whole MVP
Verdict: needs-changes

## Summary

The MVP's entire credibility rests on "measurable triage lift" being, in fact, measurable. The brainstorm lists three candidate metrics without committing to one, does not freeze the baseline, does not define the held-out corpus, and does not address the cost confound that will dominate the naive P0/P1-count comparison. All of these are pre-registration failures — choices that have to be made before the experiment runs, not after. The fix is cheap (a one-page measurement plan in strategy step) but cannot be skipped.

## Issues Found

### 1. [P1] No primary metric committed — TLM-01

**File:** `docs/brainstorms/2026-04-21-persona-lens-ontology-brainstorm.md`, Open Questions §"Measurement" lines 101-102, MVP milestone line 26.

Three candidates listed:
(a) P0+P1 count per /flux-drive run vs. baseline
(b) review-coverage-per-diff (did we select agents that touched every changed subsystem?)
(c) user-accepted-verdict rate

No commitment to a primary. The line "Strategy step picks and calibrates a baseline before we start swapping selection logic" defers the decision to a future step — fine, *if* the strategy step actually pre-registers. This is the review's job to enforce: before any graph-query-based triage code is written, one of (a)/(b)/(c) must be named the primary, with the others as secondary diagnostics.

Each metric has different failure modes:
- (a) is easiest to compute but confounded by agent count and cost (see TLM-04)
- (b) requires a "changed subsystem" ground truth — someone has to label which subsystems each diff touches
- (c) requires user disposition after review — labor-intensive and slow

**Failure scenario:** The A/B runs. Whichever of (a)/(b)/(c) looks best for the ontology view gets written up as "the metric we used." The other two get explained away. This is textbook result-driven metric selection — common, corrosive, often unconscious. Even a favorable genuine lift gets treated as sus by reviewers because the analysis plan wasn't pre-registered.

**Smallest fix:** Before Epic shape #4 begins, write a 1-page measurement plan that names:
- Primary metric (recommended: review-coverage-per-diff — it most directly answers "did we pick the right reviewers?")
- Lift threshold (e.g., "+15% coverage at p < 0.05 over 30 paired diffs")
- Secondary metrics (the other two) as diagnostics, not as alternative primaries
- What happens if primary is flat but secondary is positive: "ontology view does not replace baseline this epic; iterate"

### 2. [P1] Baseline will drift — TLM-02

**File:** same brainstorm, MVP milestone line 26, Epic shape lines 86-98.

The baseline is "current filename-glob + tier heuristics." This logic lives in flux-drive's triage code and is under active evolution (tier_bonus, routing-overrides, the domain boost from Step 1.0.1). Over the 7-week epic, the baseline will change — and if it changes in ways that improve it, the A/B loses signal. If it changes in ways that degrade it, the ontology view looks better than it is.

**Failure scenario:** In week 4 of the epic, someone merges an unrelated improvement to tier_bonus scoring that makes baseline triage pick 5% more P1 findings on average. The week-6 A/B attributes that improvement to the ontology view (since that's what changed in the "treatment" arm). We ship a false positive.

**Smallest fix:** Freeze the baseline at a specific git SHA on day 1 of Epic shape #4. Run A/B comparisons using that frozen baseline, not live /flux-drive. The comparison arm invokes `/interflux:flux-drive` at the frozen SHA (e.g., `git worktree add /tmp/flux-baseline <SHA>`) with the held-out diffs. This is annoying infrastructure but essential — otherwise the experiment is uninterpretable.

### 3. [P1] Held-out diff corpus is not defined — TLM-03

**File:** same brainstorm, MVP milestone line 26, Open Questions §"Measurement" lines 101-102.

"A/B test P0/P1 detection vs. current selection on a held-out corpus." Questions unanswered:
- How many diffs? 10? 30? 100? At 10, no statistical power; at 100, weeks of labeling work.
- Sampled how? Random from recent commits? Stratified by diff size? Curated to include known P0/P1 cases?
- Ground truth for (a) and (b): who decides the "true" set of agents that should have been selected, or the true P0/P1 count? Self-labeling (the diff's author) biases toward what they expected; adversarial labeling (another reviewer) is expensive.
- Ground truth for (c) user-accepted-verdict: requires running the full review, seeing verdicts, and having a user mark each finding accept/reject — days of work per A/B round.

**Failure scenario:** Epic shape #4 starts. Someone realizes the held-out corpus doesn't exist. A 10-diff corpus gets hastily assembled. The A/B shows +2 P0 findings on ontology view (3 total vs. 1 total across 10 diffs). Claim: "100% lift!" Reality: n=10 is too noisy to conclude anything.

**Smallest fix:** In strategy step or early Epic #4, build the corpus before triage code is written:
- Recommended: 30 recent diffs, stratified by size (10 small <50 LOC, 10 medium 50-500, 10 large >500).
- Ground truth by a combination: (i) self-label each diff with the subsystems it touched (coverage metric), (ii) for P0/P1-count metric, use the union of findings across baseline AND ontology triage as the "upper bound" and measure each arm's coverage of it.
- Freeze the corpus. Do not add diffs during the experiment.

### 4. [P2] Cost confound — TLM-04

**File:** same brainstorm, D5 line 64, MVP milestone line 26.

The ontology query in D5 selects agents by "domain match × discipline coverage × effectiveness × community neighborhood." Nothing in that formula constrains the *count* of selected agents. A richer community neighborhood means more agents. If ontology triage picks on average 7 agents per diff and baseline picks 4, it will mechanically find more P0/P1s — simply because more agents = more findings. That's not lift from better selection; that's lift from more spend.

**Failure scenario:** The A/B shows +40% P0/P1 findings on ontology triage. Writeup celebrates. Buried in the numbers: ontology triage cost 2.3x the baseline per run. Per-finding cost is flat or worse. The epic claims success on a metric that doesn't control for what actually matters (cost-adjusted quality).

**Smallest fix:** Primary metric should be normalized — either fix agent count (cap both arms at same N, measure which agents each picks), OR report cost-per-P0/P1-finding as a required secondary. The brainstorm's interstat infrastructure already tracks per-run cost (per memory note on cost-query.sh v0.2.27). Piping cost into the A/B report is cheap.

### 5. [P2] No pre-registered stopping rule or sample size — TLM-05

**File:** same brainstorm, MVP milestone line 26, Open Questions line 101.

"A/B test" without specifying: how many paired runs? What significance threshold? What effect size counts as shipping? Without these, the stopping rule is implicit: stop when the numbers look good (or when frustration sets in).

**Failure scenario:** Runs accumulate. At run 12, a slight edge appears. Is that shipping? At run 30, it's still slight. Is that ship-or-abandon? Nobody knows because the rule wasn't set. Decision gets made by whoever cares most at the time.

**Smallest fix:** In the measurement plan, state:
- N: 30 paired diffs (or justify different N)
- Analysis: paired t-test or Wilcoxon signed-rank on primary metric
- Ship threshold: p < 0.05 AND effect size >= 15% relative improvement
- Abandon threshold: p < 0.05 AND effect size <= 0%, OR sample=N and p > 0.2

### 6. [P2] User-accepted-verdict rate introduces late will reshape the MVP — TLM-06

**File:** same brainstorm, Open Questions line 102.

(c) is listed as a candidate without acknowledging its infrastructure cost: a verdict-capture pipeline, user labeling time, a labeling UI or at minimum a labeling convention. If the MVP decides (c) is primary mid-epic, all of that becomes blocking.

**Smallest fix:** Either drop (c) from consideration for MVP (revisit in V2 with Hermes conversational view), or commit to it now with a plan for the verdict-capture infrastructure. Do not leave it as a fallback option — it isn't one.

## Improvements

### 1. Report as paired data not independent arms

Run baseline and ontology triage on the *same* diffs (paired). This controls for diff difficulty (some diffs have more P0s regardless of triage). Statistical power is much higher than unpaired comparison. Frame all analysis as paired from day 1.

### 2. Pre-register the analysis plan in a markdown file

A one-page `docs/plans/triage-lift-preregistration-v1.md` committed before Epic #4 starts is worth 10x its length in credibility. Future-you reading the results will know past-you didn't cherry-pick.

### 3. Include a null-result report template

Draft the report template assuming the ontology view shows no lift. What does the epic claim then? (Probably: "ingestion and schema value stand independently; triage query needs redesign.") If the null-result story is coherent, you're doing science; if null-results feel unthinkable, you're doing advocacy.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 6 (P0: 0, P1: 3, P2: 3, P3: 0)
SUMMARY: Commit the primary metric, freeze the baseline at a git SHA, define a 30-diff paired held-out corpus, and require cost-per-finding as a secondary metric — all before Epic #4 begins. Pre-register the analysis plan; without it, "measurable triage lift" isn't measurable.
---
<!-- flux-drive:complete -->
