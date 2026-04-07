### Findings Index
- P1 | ASY-1 | "Current Architecture / Synthesize" | Synthesis makes no judgment call on inter-model conflicts — presents "model A says X, model B says Y" without hallmarking a verdict
- P1 | ASY-2 | "Cross-model dispatch / Budget system" | All model tiers dispatched simultaneously at full parallelism — no staged cost-ordered approach where cheap models inform whether expensive models are needed
- P2 | ASY-3 | "Model diversity as a signal" | Claude-Claude corroboration treated as equivalent to Claude-DeepSeek corroboration despite the former sharing training family biases
- P2 | ASY-4 | "OpenRouter integration" | No model blind-spot profile proposed — synthesis cannot weight findings by known per-model reliability on specific finding types
- P3 | ASY-5 | "Insight quality / Token efficiency" | Diagnostic value of cheap-model "clean" verdicts unquantified — system cannot distinguish "genuinely clean" from "cheap model missed it"

Verdict: needs-changes

### Summary

The interflux multi-model proposal identifies the right epistemological hypothesis — models from different training families provide more independent verification than same-family models — but the synthesis architecture treats all findings and conflicts as equivalent inputs to a majority-vote deduplication, rather than as outputs of independent analytical methods with known different blind spots. The medieval Wardein's insight is that no single test is definitive, but the value is in *knowing which test measures what* and integrating the results with that knowledge. A Wardein who runs all four tests simultaneously and then averages the results without knowing each test's limitations is not doing assay work — he is doing statistics, and statistics on improperly weighted inputs.

The current synthesis rules in `phases/synthesize.md` (Step 3.3, five dedup rules) treat all conflicts as symmetrical: Rule 4 takes the highest severity from conflicting agents, Rule 5 preserves both recommendations with attribution. Neither rule allows the synthesis to say "Claude flagged this at P1, DeepSeek flagged it at P2 — we know DeepSeek systematically under-rates this class of issue, so we accept Claude's P1 assessment and note the discrepancy as expected." This is the Wardein refusing to stamp the hallmark because he won't interpret the test results. The result is either a synthesis that defers unresolved conflicts to the user (increasing their uncertainty) or a synthesis that defaults to highest-severity without explaining why, hiding the evidential basis for the verdict.

### Issues Found

**[P1-1]** Section: "Current Architecture / Synthesize phase" — Synthesis does not make judgment calls on inter-model conflicts; hallmark is never stamped

The synthesis subagent (Step 3.2, `intersynth:synthesize-review`) executes the five dedup rules. Rule 5 states "Conflicting recommendations → preserve both with attribution." This is correct behavior for two Claude agents that disagree (their disagreement reflects genuine analytical ambiguity, and the user should see both perspectives). But for a Claude-Sonnet vs DeepSeek-V3 conflict on the same finding, "preserve both with attribution" produces a synthesis that says "Claude says fix this, DeepSeek says it's fine" without telling the user which assessment to act on.

The Wardein's hallmark liability means he *must* make a judgment call. He cannot say "the touchstone says pure, the cupellation says debased — decide for yourself." He must interpret which result is more reliable for this metal's provenance and stamp accordingly. A review system that presents unresolved multi-model conflicts delegates the epistemological integration problem back to the user — who has less context than the synthesis agent, and who came to the review system precisely to not have to do this work themselves.

Concrete failure: A review runs fd-correctness on both Claude Sonnet and DeepSeek V3. Claude flags an error handling pattern as P1 (potential unhandled exception path). DeepSeek rates the same pattern as P2 (style concern, not a correctness issue). Synthesis Rule 5 presents: "fd-correctness (claude-sonnet): P1 — unhandled exception path | fd-correctness (deepseek-v3): P2 — style concern." The user sees a conflict and doesn't know which assessment to act on. They either over-react (treat P1 as authoritative) or under-react (treat P2 as authoritative since it's the gentler verdict). Both outcomes are worse than a synthesis that said "Claude Sonnet's P1 is accepted; DeepSeek's P2 classification appears to reflect a systematic pattern where DeepSeek rates exception-handling concerns lower than Claude — this disagreement matches the known pattern."

Smallest viable fix: In the synthesis prompt for `intersynth:synthesize-review`, add an explicit judgment mandate for cross-model conflicts:
```
For conflicts between agents from different model families (identified by model_family field):
1. Apply the following resolution order:
   a. If the conflict matches a known systematic disagreement pattern in model-pair-profiles.yaml, resolve per the profile and note: "Expected systematic difference — [profile name]"
   b. If no profile exists, default to the higher-trust model family's assessment but explicitly note: "Cross-model conflict: [model A] P1 vs [model B] P2. Accepting [model A]'s assessment as primary; [model B]'s lower rating may reflect [known weakness or 'unknown systematic difference']. Flag for calibration."
2. Never present an unresolved cross-model conflict as "both perspectives offered" — make a judgment call and explain it.
```
Initially the judgment will often be "accept the more expensive model's assessment" — which is fine. The goal is to stamp the hallmark with stated reasoning, not to get the reasoning perfect on day one.

**[P1-2]** Section: "Cross-model dispatch / Budget system" — All model tiers run simultaneously; cheap touchstone test and expensive cupellation test start at the same time

The current flux-drive pipeline uses staged dispatch (Stage 1: top 2-3 agents → expansion scoring → Stage 2: remaining agents). This is cost-ordered in the sense that it avoids running all agents when Stage 1 finds nothing. But within each stage, all dispatched agents run simultaneously regardless of their model tier. The proposed OpenRouter integration does not add a new staging dimension: cheap models don't run first to inform whether expensive models are needed.

The cost-ordered testing strategy would change this: run cheap-model agents first (30-50 second API calls, $0.01-0.05 per agent), examine their findings, and only dispatch expensive Claude Opus agents to the areas where cheap models found ambiguity or disagreement. A cheap model finding nothing in fd-quality domain reduces the urgency of running Claude Opus fd-quality — not to zero (the cheap model might have missed something), but enough to defer it if budget is constrained. A cheap model finding a P0 in fd-quality increases the urgency of running Claude Opus confirmation.

Concrete failure: A review has a total budget of 200K tokens. Stage 2 expansion fires for 4 agents. All 4 run simultaneously: 2 at Claude Sonnet (expensive), 2 at DeepSeek via OpenRouter (cheap). The 2 DeepSeek agents complete in 60 seconds and find nothing in their domains. The 2 Claude Sonnet agents are already running and complete in 90 seconds, also finding nothing. The review spent the full Stage 2 budget when the cheap-model clean verdicts could have informed a decision to skip or defer the expensive-model agents.

Smallest viable fix: Add a `cheap_first` expansion mode to `budget.yaml`:
```yaml
cross_model_dispatch:
  cheap_first:
    enabled: true
    cheap_threshold_cost: 5000  # tokens — models below this cost run first
    wait_window: 60  # seconds — wait for cheap models before expensive dispatch
    escalation_trigger: P1  # only dispatch expensive models if cheap found >= P1
```
When `cheap_first.enabled`: in Stage 2, dispatch all cheap-model agents first with a 60-second wait. If they return clean verdicts with no P0/P1 findings, skip expensive-model dispatch for those domains (or reduce to haiku-tier rather than sonnet). If they return P0/P1, dispatch the expensive-model agents immediately for confirmation. This is not the full staged testing strategy (it doesn't eliminate expensive dispatch on clean cheap verdicts) but it uses cheap findings as a gate for expensive dispatch.

**[P2-3]** Section: "Model diversity as a signal / Synthesize" — Within-family corroboration weighted equally to cross-family corroboration

The synthesis convergence tracking counts the number of agents that found the same issue (`"convergence": N` in findings.json). Claude Haiku + Claude Sonnet finding the same P1 produces `convergence: 2`. Claude Sonnet + DeepSeek V3 finding the same P1 also produces `convergence: 2`. These are not epistemologically equivalent.

The touchstone test done twice is not equivalent to a touchstone test plus a cupellation: the second touchstone measures the same surface property as the first. Claude Haiku and Claude Sonnet share RLHF training data and Constitutional AI fine-tuning — their agreement is corroborating evidence that Claude's analytical tradition is internally consistent, not that an independent analytical tradition reached the same conclusion. Cross-family agreement (Claude + DeepSeek) is stronger evidence because the two families were trained by different organizations on different data distributions with different optimization objectives. Their agreement is evidence that the finding is observable from fundamentally different analytical perspectives.

Fix: Add `cross_family_weight` to `budget.yaml` and apply in synthesis:
```yaml
synthesis:
  corroboration:
    within_family_weight: 1.0  # baseline
    cross_family_weight: 1.5   # cross-family agreement = 1.5x within-family
```
In findings.json, convergence score for a finding with 1 cross-family pair would be displayed as `convergence: 2 (cross-family: 1.5x weight)` or equivalently stored as `weighted_convergence: 2.5`. This affects the Section Heat Map (Step 3.5) and the Key Findings priority ordering.

**[P2-4]** Section: "OpenRouter integration / Insight quality" — No model blind-spot profile; synthesis cannot weight findings by known per-model reliability

The Wardein knows the touchstone cannot detect interior debasement and the hydrostatic test is fooled by compensating alloys. Without equivalent documentation of each model family's known blind spots, the synthesis cannot weight findings appropriately. A finding that DeepSeek consistently produces (e.g., flagging certain error-handling patterns as P0 that Claude rates P1) should be weighted differently than a finding DeepSeek rarely produces but produced here — the latter is more surprising and potentially more significant.

The document proposes that model diversity itself is valuable without addressing the blind-spot profiling problem. If DeepSeek has a known systematic tendency to over-flag performance issues in interpreted languages, every fd-performance finding from DeepSeek carries a prior that some fraction of DeepSeek's P1 performance findings are Claude P2s. Without this prior, the synthesis treats DeepSeek's findings as equally reliable to Claude's findings for every finding type — which is the Wardein trusting the touchstone as much as the cupellation for detecting interior debasement.

Fix: Design the model blind-spot profile as a first-class data structure accumulated from calibration runs:
```yaml
# config/flux-drive/model-blind-spots.yaml
deepseek-v3:
  tends_to_over_flag:
    - domain: performance
      pattern: "interpreted_language_overhead"
      observed_rate: 0.23  # 23% of DeepSeek P1 performance findings are Claude P2
  tends_to_under_flag:
    - domain: security
      pattern: "subtle_authorization_bypass"
      observed_rate: 0.31  # 31% of Claude P1 security findings missed by DeepSeek
```
The synthesis subagent consults this profile when evaluating findings from profiled models: a DeepSeek P1 performance finding in an interpreted language is automatically noted as "in DeepSeek's known over-flag range (23% base rate) — confirm with Claude equivalent."

### Improvements

1. **P3** — Add a "minimum independent methods" requirement for P0 verdicts: a finding can only be elevated to P0 in the final verdict if it was flagged by at least 2 agents from different model families (or by 1 agent with a trust score above a high threshold). This is the Wardein's rule: high-stakes hallmarks require multiple independent tests. A P0 from a single cheap model should be treated as "candidate P0 — requires confirmation."

2. **P3** — The diagnostic value of "cheap model found nothing" should be quantified in the cost report. Rather than just reporting that a cheap model ran and produced N findings, also report: "Based on this model's known recall rate for this domain and finding type, the probability that it missed a P0/P1 finding is estimated at X%." This gives the user a calibrated sense of how much the clean verdict is worth.

3. **P3** — Design an explicit "assay confirmation" mode: for any finding where a cheap model and an expensive model disagree on severity by 2+ levels (cheap says P2, expensive says P0), automatically dispatch a third agent (different family if possible) as a tiebreaker. The Wardein orders additional testing when the disagreement pattern doesn't match any known explanation. Cap at 1 tiebreaker per review to limit cost.

<!-- flux-drive:complete -->
