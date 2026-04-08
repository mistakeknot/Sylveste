---
artifact_type: flux-drive-review
agent: fd-decisions
subject: docs/prds/2026-04-07-fluxbench-closed-loop-model-discovery.md
prior_review: docs/research/flux-drive/fluxbench-brainstorm-review/fd-decisions.md
date: 2026-04-07
---

# FluxBench PRD — Decision Quality Review

## Findings Index

| Sev | ID | Location | One-line finding |
|-----|----|----------|-----------------|
| P1 | DEC-1 | F1 acceptance criteria | Five gate thresholds committed without calibration plan — brainstorm concern carried forward unresolved |
| P1 | DEC-2 | F4, F7 | Two independent stopping rules (>15% drift, 10+ challenger runs) share no stated derivation — orthogonal arbitrary anchors compound each other |
| P2 | DEC-3 | F3 Non-goals | Store-and-forward over git-commit is a low-reversibility infrastructure bet disguised as a non-goal |
| P2 | DEC-4 | F7 acceptance criteria | Challenger slot fixed at exactly 1 without examining the explore/exploit trade-off at the fleet level |
| P2 | DEC-5 | F4 + F5 | Dual surfacing modes (drift + proactive) selected without a signpost defining when each mode dominates — silent interaction risk |
| P2 | DEC-6 | F2 acceptance criteria | Ground-truth fixture quality is load-bearing for all downstream thresholds, but the validation plan relies on a single human annotator with no inter-rater agreement check |
| P3 | DEC-7 | Success Metrics | 85% human-agreement target is a proxy metric — no stated theory of change linking FluxBench score to actual review outcome quality |

---

## Detailed Analysis

### DEC-1 (P1) — Gate Thresholds Committed Without Calibration Plan

**Location:** F1 acceptance criteria — format-compliance (>=95%), finding-recall (>=60%), false-positive-rate (<=20%), severity-accuracy (>=70%), persona-adherence (>=0.6).

**Lens: Cone of Uncertainty / Anchoring Bias**

The prior brainstorm review (DEC-1 in `fluxbench-brainstorm-review/fd-decisions.md`) flagged these values as empirically ungrounded. The PRD carries them forward without resolution. They now appear in acceptance criteria — a more committal context than a brainstorm — without any calibration plan or note that values are provisional.

The problem deepens in the PRD. F2 creates the calibration fixtures, and F2 depends on nothing. F1 (the scoring engine) depends on F2. But F1's thresholds are written into acceptance criteria *before* F2 fixtures exist. The causal direction is inverted: the thresholds should be derived from running the scoring engine against the fixtures, not specified ahead of them.

What happens if the calibration exercise (F2) produces score distributions that make the 60% recall threshold nonsensical? A model that currently qualifies via manual review might score 52% on FluxBench, forcing a choice between adjusting the threshold or demoting a model that has worked well. The PRD has no decision rule for resolving this.

The irreversibility concern from the brainstorm review is amplified here: the PRD's F3 writes FluxBench benchmark definitions to AgMoDB. Once AgMoDB records `>=60%` as the published threshold for `finding-recall`, that value migrates from a provisional acceptance criterion to a published benchmark standard that interrank and other consumers depend on.

**What would make this look wrong in 6 months:** You run F2 calibration, discover existing qualified models cluster at 45-55% recall (because Claude's finding density is higher than alternatives in all categories), and the 60% gate becomes a de-facto Claude-only fence that never passes any alternative model.

**Recommendation:** Mark all five threshold values as `[provisional — to be calibrated from F2 results]` in F1 acceptance criteria. Add an explicit acceptance criterion to F2: "Run all F2 fixtures against 3+ currently-qualified models; publish score distribution; derive gate thresholds at the Nth percentile." F1 implementation should not gate on specific values until F2 calibration runs.

---

### DEC-2 (P1) — Two Orthogonal Stopping Rules Without Shared Derivation

**Location:** F4 (>15% drift threshold, 2N sampling guarantee), F7 (10+ challenger runs before evaluation).

**Lens: Overconfidence / N-ply Thinking**

The PRD introduces three numeric thresholds that interact but were not derived together: (a) 15% drift triggers demotion, (b) hysteresis clears at 5% from baseline, (c) challenger evaluates after 10+ runs. These numbers share no visible derivation methodology. Treating them as independent constants ignores their interaction.

Consider the interaction: a challenger model running in the 1-in-10 sampling slot will, by construction, accumulate 10 real-review runs at the rate of 1 per 10 production reviews. If production volume is 1 review/day, that's 100 days before challenger evaluation — during which the drift detector could flag the same model (via F4's sampling path) and demote it before F7 gets a chance to promote it. The PRD does not address this race condition.

The 5% hysteresis band (clear drift when recovered to within 5% of baseline) is the only number with an implicit rationale (prevents oscillation). The other numbers have no equivalent reasoning.

**What happens if this assumption is wrong:** If normal review-to-review variance for a well-performing model is 8-12% (entirely plausible given the stochastic nature of LLM outputs), then the 15% drift trigger fires on measurement noise roughly once every 7-10 reviews. The model gets demoted, Claude takes its slot, the challenger never accumulates 10 runs, and the system converges to Claude-only operation. This is the Jevons Paradox applied to model diversity: the safety mechanism (drift detection) eliminates the population it was meant to protect (non-Claude models), increasing system fragility rather than reducing it.

**Recommendation:** Before committing these constants, instrument a pilot: run 5-10 qualification trials against the same model on the same fixtures and measure FluxBench score variance. Set the drift threshold at (mean variance + 2 standard deviations). Set the challenger run count at (2 * the minimum sample needed to distinguish signal from variance at 80% confidence). Both derivations are tractable before implementation begins.

---

### DEC-3 (P2) — Git-Commit Write-Back Is a Low-Reversibility Bet Framed as a Non-Goal

**Location:** F3 architecture, Non-goals section ("Real-time write API for AgMoDB: Store-and-forward via git commit is sufficient. REST API is a separate AgMoDB concern.").

**Lens: Reversibility / Dissolving the Problem**

The Non-goals section frames the absence of a REST write API as a deliberate scope boundary. This is correct scoping. What it does not address is the irreversibility cost of the chosen alternative: git-committed JSONL via `fluxbench-sync.sh`.

Once FluxBench data flows into AgMoDB via git commits as the canonical write path, that path becomes load-bearing for interrank's snapshot refresh. The `relevantUseCases`, `benchmarkDefinition`, and `externalBenchmarkScores` entries written by `fluxbench-sync.sh` will be read by other AgMoDB consumers. Changing the schema, renaming fields, or moving to a different write path later requires coordinating with all downstream consumers — including interrank — which is a medium-cost migration.

The Starter Option lens asks: what is the smallest commitment that tests the most uncertainty? Here, the smallest commitment is writing FluxBench scores only to local `model-registry.yaml` (which the PRD already includes as an acceptance criterion in F1). Surfacing them in interrank could be achieved by having interrank read from `model-registry.yaml` directly on local deployments, deferring the AgMoDB write-back entirely to a later feature. The PRD does not evaluate this option — it treats AgMoDB write-back (F3) as co-equal with local scoring (F1) in Phase 1.

The key question is: does interrank need AgMoDB-hosted FluxBench data, or does it need *any* FluxBench data? If the answer is "any", then writing to a local file that interrank reads on startup is sufficient for Phase 1 and defers the irreversible AgMoDB schema commitment to Phase 2 when the data model is more stable.

**Recommendation:** Evaluate whether F3 should move to Phase 2. Phase 1 (MVP) would be: F2 + F1 + local `model-registry.yaml` update. interrank reads FluxBench scores from model-registry.yaml for local use. F3 (AgMoDB write-back) ships only after FluxBench metrics have been validated and the schema is stable.

---

### DEC-4 (P2) — Challenger Slot Fixed at 1 Without Explore/Exploit Analysis

**Location:** F7 acceptance criteria — "Reserve 1 agent slot in flux-drive reviews for the highest-scoring unqualified candidate."

**Lens: Explore vs. Exploit / False Dichotomy**

The challenger slot count of 1 is presented as a design decision ("1 reserved position") but the PRD does not examine why 1 is correct rather than 0 or 2.

The case for 0: if qualified models are performing well, reserving a slot for an unqualified challenger imposes a quality floor reduction on every review that includes one. The PRD correctly excludes challengers from fd-safety and fd-correctness roles, but the safety floor reasoning that justifies those exclusions could equally justify a configurable ramp (start at 0, increase to 1 as challenger confidence grows).

The case for 2: if the goal is accelerating model discovery, one slot accumulates challenger data at the rate of 1-in-10 reviews. With two candidates and two slots, each candidate gets data twice as fast (1-in-20 per candidate). Whether the learning rate justifies the quality risk depends on the fleet's review volume, which the PRD does not state.

The PRD provides a configurable boolean (`challenger_slot: true/false`) but not a configurable count. This is a false dichotomy: "challenger on or off" versus the richer option of "challenger count proportional to fleet confidence." The binary toggle is also irreversible in practice — once teams rely on challenger data to evaluate models, turning it off loses the accumulated run data.

The deeper explore/exploit question is absent: what is the fleet's current exploitation rate? If the model registry already has 8 qualified models and reviews use diverse routing, adding a challenger slot at 1-in-10 is low-value exploration. If the registry has 2 qualified models and all traffic routes to Claude, the explore rate is near zero and a single challenger slot is insufficient to close the loop.

**Recommendation:** State the current qualified model count and routing distribution explicitly. Derive the challenger slot count from the desired exploration rate, not from intuition. Add a configurable integer (`challenger_slots: 1`) rather than a boolean in budget.yaml, with a note that 0 means "exploit only" and N>1 means "accelerated discovery."

---

### DEC-5 (P2) — Dual Surfacing Modes Without Interaction Signposts

**Location:** F4 (drift detection triggers requalification), F5 (proactive discovery triggers qualification of new candidates).

**Lens: Signposts / Sour Spots**

The PRD defines two distinct loops: F4 catches degradation of existing models, F5 discovers new candidates. These are presented as parallel Phase 2 features. The PRD does not define signposts — pre-committed criteria for when each mode becomes the dominant management strategy.

When the fleet is young (2-3 qualified models), F5 (proactive discovery) is the high-value loop. When the fleet is mature (8+ qualified models with stable scores), F4 (drift detection) is the high-value loop. The ratio of effort between the two modes should shift as the fleet matures, but the PRD designs them as co-equal features that run indefinitely.

The sour spot risk: both loops feed the `qualifying` state in model-registry.yaml. F4 demotes qualified models to `qualifying` when drift is detected. F5 promotes candidates to `qualifying` when they appear in interrank. If both loops are active simultaneously at high fleet volume, the `qualifying` pool grows faster than the challenger slot (set to 1) can evaluate models. The PRD does not specify what happens when the qualifying backlog exceeds the challenger slot's throughput.

Concretely: if F5 surfaces 4 new candidates per month and the challenger slot evaluates 1 candidate per 100 reviews (assuming 10 reviews/day, that's 10 days per candidate), and F4 demotes 2 models per month due to drift, the qualifying pool grows by 5 candidates per month while the evaluation capacity is ~3 per month. The system accumulates a permanent qualifying backlog with no resolution mechanism.

**Recommendation:** Add two signposts to the PRD. Signpost 1: "If qualifying pool exceeds 5 models, pause F5 new-candidate surfacing until challenger evaluation clears the backlog." Signpost 2: "After 12 months of fleet operation with <2 drift events, reduce drift sampling rate from 1-in-10 to 1-in-20 to recover throughput." These are pre-committed criteria, not retrospective policy — they should live in budget.yaml as configurable thresholds.

---

### DEC-6 (P2) — Ground-Truth Fixtures Validated by Single Annotator

**Location:** F2 acceptance criteria — "Ground-truth validated by human annotation (not Claude-generated baseline alone)."

**Lens: Overconfidence / Theory of Change**

The PRD correctly rejects Claude-only ground-truth (avoiding circular validation). The acceptance criterion requires "human annotation" but does not specify the number of annotators, the annotation protocol, or any inter-rater reliability check.

All five FluxBench gate thresholds are derived from how scoring compares against these fixtures. If fixture annotations are inconsistent — one annotator calls a finding P1 while another would call it P2 — the calibration data introduces noise that cannot be separated from model performance. The 85% human-agreement success metric (which measures FluxBench vs. human judgment) would fail not because FluxBench is wrong but because the ground-truth itself is inconsistent.

This is load-bearing: F2 is the calibration anchor for the entire system. A calibration anchor with unknown reliability means all derived thresholds have unknown reliability. The PRD treats fixture quality as a solved problem once "human annotation" occurs, but single-annotator annotation has well-documented reliability issues (inter-rater kappa typically 0.4-0.7 for judgment tasks).

The specific risk for this domain: "analytical" and "judgment" fixtures (security/race-conditions as listed in F2) are the hardest to annotate consistently. A P0 security finding might be P1 to a different reviewer. Since P0 findings auto-fail qualification regardless of aggregate score, fixture-level annotation disagreement on severity directly affects which models can ever qualify.

**Recommendation:** Require 2 independent annotators for each fixture, measure Cohen's kappa before accepting fixtures into the calibration set, and set a minimum kappa of 0.7 for fixtures used in core gate calibration. Fixtures below threshold should be used only for extended metrics (instruction-compliance, latency, etc.) where the stakes are lower.

---

### DEC-7 (P3) — Success Metric Is a Proxy With No Theory of Change

**Location:** Success Metrics — "FluxBench scoring agrees with human judgment on ground-truth fixtures at >=85% accuracy."

**Lens: Theory of Change / Snake Oil Test**

The PRD's four success metrics all measure process outcomes (FluxBench scores appear in interrank, drift detection catches simulated regression, auto-qualification runs end-to-end). The most ambitious metric — 85% human-agreement — measures whether FluxBench correlates with human annotation, not whether FluxBench-qualified models produce better code review outcomes.

The missing link: FluxBench measures whether models produce findings consistent with a human-annotated fixture set. Fixtures are synthetic documents created specifically for calibration. Production reviews operate on real code with unknown ground-truth. The theory of change from "FluxBench score correlates with fixture annotations" to "FluxBench-qualified models improve actual review quality" requires an intermediate step: fixture findings are representative of production findings.

PHILOSOPHY.md's measurement principle states: "Outcomes over proxies. Gate pass rates are gameable. Post-merge defect rates are not." FluxBench is, by construction, a gate pass rate system. The 85% agreement metric measures the gate's consistency, not its predictive validity for production outcomes.

The Non-goals section defers "Finding survival rate tracking: Requires integration with beads/git to detect which findings led to code changes." This is the exact outcome metric that would close the theory of change. Deferring it to v2 is a reasonable scoping decision, but the PRD should acknowledge that the v1 system measures a proxy and state the condition under which the proxy would be invalidated (e.g., "if FluxBench-qualified models produce more acted-on findings than non-qualified models at rate below X%, the fixture set needs revalidation").

**Recommendation:** Add to Non-goals a note: "Survival rate tracking is deferred, but the v1 system is explicitly operating on a proxy metric. If 6-month data shows no correlation between FluxBench qualification status and finding survival rate, the fixture set and threshold calibration should be revisited." This makes the known limitation explicit and sets a signpost for proxy invalidation.

---

## Carry-Forward Assessment

The prior brainstorm review (`fluxbench-brainstorm-review/fd-decisions.md`) raised 6 findings. The PRD resolves 3 partially:

- **DEC-2 (brainstorm) — Over-commitment**: The PRD adopts phased delivery (Phase 1 = F1+F2+F3, Phase 2 = F4+F5, Phase 3 = F6+F7). This addresses the "three capabilities at once" concern but retains F3 (AgMoDB write-back) in Phase 1, which this review's DEC-3 flags as premature.
- **DEC-3 (brainstorm) — Missing alternatives matrix**: The PRD's Non-goals section briefly frames the git-commit choice but does not present an alternatives matrix. The concern stands.
- **DEC-4 (brainstorm) — 60% recall too permissive**: The PRD adds weighted recall (P0=4x, P1=2x, P2=1x, P3=0.5x) and the P0 auto-fail rule. This substantially addresses the concern — severity weighting was the recommended fix.

The two brainstorm P1 findings — threshold values ungrounded (DEC-1) and scope over-commitment (DEC-2) — are carried forward at the same severity in this PRD review, because the PRD commits to specific thresholds in acceptance criteria and retains F3 in Phase 1 before F2 calibration runs.

<!-- flux-drive:complete -->
