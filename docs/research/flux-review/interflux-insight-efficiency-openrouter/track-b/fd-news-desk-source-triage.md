---
agent: fd-news-desk-source-triage
tier: project
model: sonnet
input: interflux-insight-efficiency-openrouter/input.md
track: b (operational parallel disciplines)
---

# fd-news-desk-source-triage — Findings

## Findings Index

| Severity | ID | Section | Title |
|----------|-----|---------|-------|
| P0 | NDT-01 | Synthesis | Single-source P0 findings from cheap models accepted without verification |
| P1 | NDT-02 | Convergence Scoring | Cross-source validation treats all providers equally regardless of reliability history |
| P2 | NDT-03 | Editorial Allocation | Claude verification applied uniformly instead of targeted at divergent findings |
| P2 | NDT-04 | Kill-switch | No retraction mechanism: hallucinated findings from cheap models persist in output |
| P3 | NDT-05 | Source Scoring | No provider reliability history: quality history not accumulated across runs |

---

## Detailed Findings

### P0 — NDT-01: Single-Source P0 Findings from Cheap Models Accepted Without Verification

**Newsroom parallel:** The cardinal rule on a wire desk: never run a single-source story on a critical claim. If only one agency is reporting a P0 event (major accident, political crisis), you hold until a second independent source confirms or you reach someone directly. A single-source P0 from an unreliable stringer gets extra scrutiny, not less.

**Interflux parallel:** The proposed design routes agents to cheap models for cost savings. A `fd-security` or `fd-correctness` agent running on DeepSeek might produce a P0 finding: "SQL injection vulnerability in authentication module." If that finding comes from a single cheap-model agent and no other agent raises the same issue, what does synthesis do?

**Current behavior** (from `phases/synthesize.md`): Convergence tracks whether multiple agents flagged the same issue. A finding flagged by 1/4 agents is lower confidence than one flagged by 3/4. But the convergence score doesn't distinguish *which* agent raised the finding. A P0 from a cheap model that no other agent confirmed is treated the same as a P0 from Claude that no other agent confirmed.

**Failure scenario (false positive):** DeepSeek V3 hallucinates a P0 SQL injection vulnerability in correctly-parameterized code. Claude fd-correctness doesn't flag it (it's not real). Synthesis includes the finding because P0s are always included regardless of convergence. The user spends 4 hours investigating a phantom vulnerability. Trust in interflux erodes.

**Failure scenario (false negative complement):** The same design means Claude's single-source P0 finding also passes without verification from another agent. Cheap model integration doesn't create this problem — it makes it visible. The real gap is that P0 findings from any single source should trigger escalation.

**Fix:** In synthesis, flag any P0/P1 finding that is single-source AND comes from a provider below the top quality tier. Add a `verification_recommended: true` field and surface it prominently in the findings report. Optionally: auto-escalate by dispatching the same task to a Claude agent if budget permits (newsroom analog: editor calls the source directly). This is a 10-line addition to synthesis logic.

---

### P1 — NDT-02: Cross-Source Validation Treats All Providers Equally

**Newsroom parallel:** On a wire desk, not all agencies are equal. Reuters and AP carry more weight than a regional stringer. When 3 agencies report the same story, the combination of Reuters + AP + AFP is much stronger confirmation than 3 regional stringers. Cross-source validation that ignores source quality is just counting, not validating.

**Interflux parallel:** The current convergence scoring in synthesis counts how many agents flagged the same finding. If 3 agents flag the same issue, it's high confidence. But the design doesn't distinguish: 3 Claude agents converging vs 1 Claude + 2 OpenRouter cheap-model agents converging.

**Why this matters for insight quality:** The input document correctly identifies that Claude-DeepSeek agreement is a stronger signal than Claude-Claude agreement (different training biases → independent assessment). But this asymmetry should work both ways: cheap-cheap agreement is a *weaker* signal than Claude-Claude agreement, because cheap models may share the same training data biases and hallucination patterns.

**Failure scenario:** Three OpenRouter agents (different models but all trained on similar data) all flag the same architectural issue. Synthesis scores this as high-confidence convergence. But the finding is a shared hallucination pattern across cheap models — Claude would not have flagged it. The high convergence score gives it unwarranted authority.

**Fix:** Weight convergence scores by provider diversity, not just count. Same-family agreement (3 OpenRouter models) scores lower than cross-family agreement (Claude + OpenRouter). The formula: `convergence_score = Σ (agent_weight × agreement_signal)` where `agent_weight` is based on provider tier and historical reliability. This is a modification to the convergence computation in `phases/synthesize.md` — 10-15 lines.

---

### P2 — NDT-03: Editorial Attention (Claude Verification) Applied Uniformly

**Newsroom parallel:** Experienced wire desk editors know that editorial attention is a scarce resource. You don't assign your best editor to verify every story equally — you concentrate editorial attention on high-uncertainty, high-stakes stories. A routine earnings announcement gets a junior editor; a breaking political crisis gets the senior correspondent.

**Interflux parallel:** The current architecture applies Claude (highest-judgment, most expensive) uniformly across all agents in a review. The proposed multi-model dispatch would route some agents to cheap models, but Claude's role as orchestrator + synthesizer remains uniform regardless of finding uncertainty.

**The missed opportunity:** Claude should be deployed *reactively* to high-uncertainty findings from cheap models, not pre-assigned to fixed agent slots. Specifically: when synthesis identifies a finding with high provider diversity (Claude and OpenRouter disagree), or a single-source P0 from a cheap model, that's the trigger for deploying additional Claude capacity.

**This is a P2 (not P1) because:** The uniform application still works — it just doesn't optimize Claude's value. The optimization is: save Claude tokens on low-uncertainty findings (cheap model convergence without red flags) and deploy Claude tokens on high-uncertainty findings (divergence, single-source P0).

**Fix (architectural):** Add an "uncertainty escalation" mode to synthesis: findings flagged as high-uncertainty (single-source P0, cross-provider divergence) get routed to a Claude verification agent as a Stage 2 expansion. Budget for this escalation pool should be pre-allocated (e.g., 20% of total budget reserved for escalation dispatch). The expansion mechanism already exists in `phases/launch.md` — this extends the expansion trigger condition.

---

### P2 — NDT-04: No Retraction Mechanism for Hallucinated Findings

**Newsroom parallel:** Every professional newsroom has a kill-switch: when a story that passed triage turns out to be false, it gets retracted. The retraction is not just "remove from the website" — it's a documented correction with attribution. Kill-switch discipline is what separates professional newsrooms from tabloids.

**Interflux parallel:** Once a finding enters the synthesis output (`findings.json` + `summary.md`), there's no mechanism to retract it if subsequent analysis reveals it's incorrect. This is a gap in the current architecture that cheap model integration makes more acute — cheap models have higher hallucination rates, increasing the frequency of findings that should be retracted.

**Concrete scenario:** flux-drive runs on a codebase. DeepSeek V3 fd-quality flags a "missing error handling in database connection" finding as P1. The finding is hallucinated — the error handling exists but uses a pattern the model didn't recognize. Claude fd-correctness doesn't cover this specific area (its scope is race conditions, not error handling patterns). Synthesis includes the P1.

**Current state:** The user can manually review and dismiss findings, but there's no in-system mechanism to mark a finding as `retracted: true` with a correction note. The finding lives in `findings.json` permanently.

**Fix (modest):** Add a `retracted` field to the findings schema in `phases/shared-contracts.md`. Add a CLI command (or note in `fetch-findings.md`) to retract a specific finding ID with a correction reason. This is metadata-only — doesn't change synthesis logic, just gives users a correction mechanism. The retraction history is itself valuable signal for model calibration.

---

### P3 — NDT-05: No Provider Reliability History

**Newsroom parallel:** Wire desk editors maintain informal (and sometimes formal) reliability scores for each agency. Reuters consistently files accurate copy; a particular regional stringer consistently embellishes. This history shapes how much verification effort each source gets.

**Interflux parallel:** The proposed design treats all OpenRouter providers as equal candidates for dispatch. But across runs, interflux could accumulate quality data: `provider X → agent type Y → finding count / quality score`. This history should feed back into future dispatch decisions (the supply chain lens calls this "volume allocation based on quality signals").

**Why P3:** This requires interstat instrumentation and historical data accumulation — it's not a day-one feature. But it's the right long-term architecture. The ground truth for source reliability is in the run history.

**Fix (roadmap):** Note in `agents/measurement.md` that provider reliability tracking is a planned enhancement. Define the data model: `{provider, agent_type, run_id, findings_count, quality_score}`. The quality score can be computed from user feedback (finding accepted/dismissed) or from cross-provider convergence (findings also flagged by high-quality providers).

---

## Verdict

**needs-changes**

The newsroom triage lens surfaces a P0 that the other agents didn't fully articulate: **single-source P0 findings from cheap models need verification escalation**. This is not just a quality concern — it's a trust concern. If a user follows a hallucinated P0 finding and invests significant debugging time on a non-issue, interflux's credibility is damaged. The fix is clear and bounded.

The strongest newsroom lesson for interflux: **editorial attention is the scarcest resource, and it should be concentrated on high-uncertainty stories**. Claude is the editor. Right now Claude is spread uniformly across all findings. The optimization is to concentrate Claude's verification capacity where cheap-model uncertainty is highest — divergent findings and single-source P0s. This is both an efficiency gain (fewer Claude tokens wasted on easy findings) and a quality gain (more Claude attention on genuinely uncertain findings).

The cross-source validation weighting (P1) is the most architecturally important finding from this lens: convergence scoring must distinguish cross-family agreement (strong signal) from same-family agreement (weaker signal). This is a direct translation of newsroom practice — Reuters + AP + AFP is a different level of confirmation than three regional stringers reporting the same story.

<!-- flux-drive:complete -->
