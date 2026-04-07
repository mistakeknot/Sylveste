# Flux Drive Review — Track B: Operational Parallel Disciplines
## interflux insight quality & token efficiency via OpenRouter

**Input:** `docs/research/flux-review/interflux-insight-efficiency-openrouter/input.md`
**Track focus:** Operational patterns from parallel professional disciplines
**Agents:** fd-trading-desk-order-routing, fd-supply-chain-multi-sourcing, fd-broadcast-signal-routing, fd-news-desk-source-triage, fd-systems (Stage 2)
**Verdict:** needs-changes

---

## Summary

Five agents analyzed the interflux OpenRouter integration design from four parallel professional disciplines — smart order routing, supply chain multi-sourcing, broadcast signal engineering, newsroom wire-desk triage — plus a systems dynamics overlay. The disciplines converge on the same root cause from different directions: **the design is a dispatch mechanism without a feedback loop**, and **failure modes are silent by default**.

14 findings: 3 P0, 5 P1, 4 P2, 2 P3.

---

## P0 Findings — Requires Action Before Shipping

### TRACK-B-01 — Silent partial review: provider outage is invisible to the user
*fd-supply-chain-multi-sourcing*

A provider outage causes some agents to silently drop. The review completes with fewer agents but the output looks identical to a full review — no user-visible signal. A user reviewing a security-sensitive codebase may see a "clean" review that was actually missing half the agents.

**Fix:** Explicit fallback routing — if OpenRouter fails for an agent, re-dispatch to Claude haiku and surface a `provider_fallback` warning in the findings report. Never silent.

---

### TRACK-B-02 — No quality monitoring: shallow cheap-model output looks like a thorough review
*fd-broadcast-signal-routing*

A cheap model that is *up* but *shallow* produces 2 findings where Claude would produce 7. Low finding density passes format validation, enters synthesis, and the review looks clean. The user cannot distinguish a shallow review from a deep one.

**Fix:** In synthesis, compute per-agent findings-density against historical interstat baseline. If a cheap-model agent's finding count is >50% below median for that agent type, flag `low_signal_confidence` and downweight in convergence scoring.

---

### TRACK-B-03 — Single-source P0 findings from cheap models enter synthesis without verification
*fd-news-desk-source-triage*

A cheap model may hallucinate a P0 finding (e.g., "SQL injection in authentication") that Claude would not flag. Synthesis includes it — P0s are always included regardless of convergence. The user invests hours investigating a phantom issue. Trust in interflux erodes.

**Fix:** In synthesis, flag any P0/P1 finding that is (a) single-source AND (b) from a provider below top quality tier. Surface `verification_recommended: true` prominently. Optionally auto-escalate to a Claude verification agent as Stage 2 expansion (using the existing expansion mechanism).

---

## P1 Findings — Required Before Calling the Integration Production-Ready

### TRACK-B-04 — No post-routing analysis: efficiency gains are unverifiable
*fd-trading-desk-order-routing + fd-systems (corroborating)*

The claimed "10-50x cost reduction" cannot be proven after shipping because there is no mechanism to compare cost/quality across routing configurations. Without a Transaction Cost Analysis equivalent, the integration cannot be tuned, justified, or improved.

**Fix:** Add a `routing_report` block to synthesis output: per-provider `{model, tokens, cost, findings_count, severity_distribution}`. The data already flows through synthesis — this is one additional output block.

---

### TRACK-B-05 — No model qualification process: cheap models added without quality baseline
*fd-supply-chain-multi-sourcing*

DeepSeek V3, Qwen 2.5, and Yi are listed as candidates. There is no described process for determining which agent tasks each model handles adequately. "Strong reasoning at 10-50x lower cost" is a benchmark claim, not a quality baseline for interflux's specific output format and finding precision requirements.

**Fix:** Define a qualification checklist before adding any model: 3 synthetic review tasks with known ground-truth findings, measure format compliance rate and finding precision/recall vs Claude baseline. Store results in `config/flux-drive/model-registry.yaml`. Requalify on major model updates.

---

### TRACK-B-06 — Convergence scoring treats all providers equally
*fd-news-desk-source-triage*

The current convergence scoring counts how many agents flagged the same finding. It does not distinguish: 3 OpenRouter agents converging (weaker — may share training biases) vs Claude + OpenRouter converging (stronger — genuinely independent). The design's stated goal of "model diversity as signal" requires this distinction.

**Fix:** Add `provider_family` field to findings metadata. Weight convergence scores by provider diversity: cross-family agreement scores 1.5x vs same-family agreement. This is the direct implementation of the "diversity as signal" insight in the design document.

---

### TRACK-B-07 — Provider failover is manual
*fd-broadcast-signal-routing*

If OpenRouter returns 429 or 503, the Bash tool call fails. The agent's `.partial` file is never renamed. Synthesis either times out, proceeds with missing agents, or errors — none of which trigger automatic re-dispatch to Claude. The orchestrator has no circuit breaker.

**Fix:** In the OpenRouter dispatch wrapper: 2 retries with exponential backoff, then re-dispatch to Claude haiku. Log `provider_fallback: true`. This is 15-20 lines of bash — the pattern exists in broadcast engineering as the primary/backup/emergency chain.

---

### TRACK-B-08 — Quality feedback loop absent: routing system cannot learn from outcomes
*fd-systems*

The routing logic assigns model tiers once. There is no mechanism for finding acceptance rates, severity accuracy (hallucinated P0s), or cost-per-finding data to feed back into routing decisions. The system will drift — either toward unnecessary cost or toward undetected quality degradation — with no corrective signal.

**Fix:** Design the feedback loop architecture before shipping, even if only as a manual reporting cycle. `scripts/estimate-costs.sh --routing-report` mode emitting per-provider quality/cost metrics from interstat closes the calibration loop manually. Automatic rebalancing is iteration 2. The data model must be instrumented from day one.

---

## P2 Findings — Quality and Maintainability

| ID | Title | Agent | Fix |
|----|-------|-------|-----|
| TRACK-B-09 | TCO ignores hidden costs (retry, validation, rework) | fd-supply-chain-multi-sourcing | Add TCO fields to budget.yaml: retry_cost_multiplier, validation_overhead_tokens, quality_discount |
| TRACK-B-10 | Format conversion artifacts: severity label variants across model families | fd-broadcast-signal-routing | Findings format normalizer before synthesis ingestion (CRITICAL→P0, HIGH→P1, etc.) |
| TRACK-B-11 | Claude verification applied uniformly instead of concentrated on uncertain findings | fd-news-desk-source-triage | Uncertainty escalation: pre-allocate 20% of budget for escalation pool; deploy Claude at divergent/single-source-P0 findings |
| TRACK-B-12 | Cost-quality coupling unacknowledged: no break-even threshold for routing eligibility | fd-systems | Define explicit eligibility threshold: agent type X routes to cheap model only if finding density within N% of Claude baseline |

---

## P3 Findings — Improvements

| ID | Title | Agent |
|----|-------|-------|
| TRACK-B-13 | Order splitting ignores workload divisibility: routing by agent type is a proxy for complexity | fd-trading-desk-order-routing |
| TRACK-B-14 | Cross-provider convergence is emergent: independence conditions not designed for | fd-systems |

---

## Cross-Agent Convergences

Three thematic convergences across multiple agents — the strongest signals in this review:

**1. Silent failure by default (P0 cluster)**
Both SCM-01 (outage → partial review) and BSR-01 (degradation → shallow review) are expressions of the same gap: the absence of monitoring means failure is invisible to the user. The two P0 findings are complementary — one covers provider absence, one covers provider degradation. Both need the same fix: explicit quality gates between provider response and synthesis ingestion.

**2. Feedback loop absence (P1 cluster)**
TCA-01 (no post-routing analysis) and SYS-01 (no quality feedback loop) converge on the same root cause. The trading desk lens frames it as "no TCA." The systems lens frames it as "no feedback loop." The fix is the same: instrument the routing decision and its outcome from day one, even if analysis is initially manual.

**3. Cross-family convergence as the core insight quality mechanism (P1 + P3)**
NDT-02 (convergence weighting) and SYS-03 (independence conditions) converge on the key implementation requirement for "model diversity as signal": it only works if (a) models are genuinely independent on the finding type, and (b) convergence scoring reflects provider diversity. Without TRACK-B-06's fix, the diversity benefit is hypothesized but not realized.

---

## Disciplinary Synthesis: What the Four Disciplines Agree On

The four disciplines — trading desk, supply chain, broadcast engineering, newsroom — have each independently solved the multi-source quality triage problem. Their convergent lessons for interflux:

1. **Monitoring before optimization.** All four disciplines monitor source/venue/signal quality continuously before optimizing allocation. Interflux is proposing to optimize allocation before building monitoring. The order should be reversed: instrument first, optimize second.

2. **Fallback as a design requirement, not an afterthought.** In all four disciplines, fallback paths are designed in from the start. The cheap source always has an expensive fallback. The fallback is what makes the cheap source safe to use — without it, the cheap source is a liability, not an asset.

3. **Source reliability history accumulates over time.** Wire desks have agency reliability scores. Supply chains have supplier scorecards. Trading desks have venue fill quality databases. Broadcast engineers have signal quality logs. All four disciplines recognize that source reliability is not known a priori — it is learned from history. Interflux needs to design for this accumulation from the first run.

4. **Cheap-source agreement is weaker than cross-source agreement.** All four disciplines distinguish independent confirmation from corroborated confirmation. Three regional stringers reporting the same story is not as strong as Reuters + AP. Interflux's convergence scoring currently does not make this distinction.

---

## Implementation Priority

Recommended sequencing for shipping:

**Phase 1 (before any OpenRouter traffic):**
- TRACK-B-05: Model qualification baseline (know what you're deploying)
- TRACK-B-10: Findings format normalizer (correctness prerequisite)
- TRACK-B-04: Routing report in synthesis output (observability prerequisite)

**Phase 2 (gate for production traffic):**
- TRACK-B-07: Automatic provider failover (never manual)
- TRACK-B-01: Silent partial review prevention (explicit fallback signal)
- TRACK-B-02: Findings density monitoring in synthesis

**Phase 3 (before calling integration stable):**
- TRACK-B-03: Single-source P0 verification escalation
- TRACK-B-06: Cross-family convergence weighting
- TRACK-B-08: Feedback loop instrumentation (even if manual reporting only)

**Phase 4 (quality improvement, after stable operation):**
- TRACK-B-11: Targeted Claude verification (uncertainty escalation)
- TRACK-B-12: Break-even threshold definition
- TRACK-B-09: TCO documentation

---

*Track B complete. 5 agents, 14 findings, verdict: needs-changes.*
*See track-b/findings.json for structured findings data.*
*See individual agent files for full finding detail and fix specifics.*
