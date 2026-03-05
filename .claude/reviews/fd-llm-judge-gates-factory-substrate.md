# Review: LLM-as-Judge Reliability — Factory Substrate PRD

**Reviewer:** fd-llm-judge-gates (reliability engineering lens)
**PRD:** docs/prds/2026-03-05-factory-substrate.md
**Brainstorm:** docs/brainstorms/2026-03-05-factory-substrate-brainstorm.md
**Date:** 2026-03-05

---

## 1. Non-Determinism

**Priority:** P0 — blocks trustworthy gating

**Finding:** The PRD specifies single-shot LLM-as-judge scoring (`scenario-score <run-id>` invokes judges, produces `satisfaction.json`). There is no mention of retry strategy, majority vote, averaging across N evaluations, or temperature controls. Same trajectory scored twice by the same judge model may produce different scores. For a gate that blocks Ship, this is a reliability hole: a sprint that legitimately passes could be blocked by a noisy low score, or a failing sprint could slip through on a lucky high score.

**Evidence:**
- PRD F4: "invokes LLM judges on scenario trajectories" — no mention of N>1 evaluations
- PRD F4: "overall score (0.0-1.0)" — single scalar, no confidence interval or variance measure
- Brainstorm: "LLM-as-judge + deterministic rubric scoring" — the "deterministic rubric" half is unexplored; it's unclear what's deterministic vs. what's LLM-judged

**Recommendation:** Specify: (a) temperature=0 for judge calls, (b) minimum N=3 evaluations per criterion with median aggregation, (c) variance threshold — if score variance across evaluations exceeds a bound, flag as "inconclusive" rather than pass/fail, (d) the `satisfaction.json` schema must include per-evaluation raw scores, not just the aggregate. Cost implications of N=3 are addressed in section 2.

---

## 2. Cost and Latency

**Priority:** P1 — determines operational viability

**Finding:** The PRD reuses three existing flux-drive agents (`fd-user-product`, `fd-correctness`, `fd-safety`) as judges. There is no mention of which model tier these agents run on, whether there's a tiered judging strategy (cheap model pre-screen, expensive model for borderline cases), or what the expected per-scenario cost is. If these agents run on Opus (the project's primary model), judging a holdout set of 10 scenarios with N=3 evaluations each across 3 judges = 90 LLM calls per Ship gate. At ~$0.10-0.30 per call, that's $9-27 per gate check. With the project's $1.17/landable-change baseline, this could multiply cost by 10x.

**Evidence:**
- PRD F4: "Scoring reuses existing agents: `fd-user-product` (satisfaction), `fd-correctness` (technical), `fd-safety` (risk)"
- No model tier specified for judge agents
- No cost estimate or budget ceiling for scoring
- Brainstorm mentions no cost analysis for the judge pipeline

**Recommendation:** (a) Specify model tier for judges — Sonnet-class is likely sufficient for rubric scoring; reserve Opus for appeals/escalation. (b) Add a cost ceiling per gate check in the acceptance criteria. (c) Consider tiered judging: run `fd-safety` (binary risk gate) first; only run satisfaction judges if safety passes. (d) Add latency SLO — gate check should complete in under 60s to avoid blocking sprint flow.

---

## 3. Judge Unavailability

**Priority:** P1 — determines failure mode of the entire gating system

**Finding:** The PRD does not specify behavior when judge API calls fail (rate limit, timeout, model unavailable). The gate blocks Ship advancement. If the judge is down, does the sprint block indefinitely? Does it timeout and bypass? Does it retry with backoff? The `CLAVAIN_SKIP_GATE` override is mentioned but positioned as a manual escape hatch with "auditable reason," not an automatic fallback.

**Evidence:**
- PRD F4: "sprint cannot advance to Ship unless holdout satisfaction >= configurable threshold (default: 0.7)"
- PRD F4: "Gate respects existing `CLAVAIN_SKIP_GATE` override mechanism with auditable reason"
- No timeout, retry, or degraded-mode specification
- No mention of caching previous scores as fallback

**Recommendation:** Specify: (a) retry policy — 3 retries with exponential backoff per judge call, (b) timeout — if scoring doesn't complete within 120s, record "judge_unavailable" status, (c) degraded mode — if judge is unavailable, allow Ship with a reduced-confidence flag that triggers post-hoc scoring when judges recover, (d) never silently bypass — every unavailability event must produce a CXDB turn (`clavain.judge_failure.v1`) for audit. The `CLAVAIN_SKIP_GATE` mechanism should be reserved for human overrides, not API failures.

---

## 4. Calibration

**Priority:** P0 — the PRD's own open question #5 acknowledges this

**Finding:** The PRD asks "should this follow the closed-loop pattern?" for the 0.7 threshold but leaves it as an open question. Per PHILOSOPHY.md, this is not optional — "closed-loop by default" is a must, and "shipping stages 1-2 without 3-4 is incomplete work." The PRD as written ships stages 1 (hardcoded 0.7 default) and arguably stage 2 (scores recorded in CXDB), but has no plan for stages 3-4 (calibrate threshold from human agreement data, defaults as fallback). More critically, there is no plan to validate that judge scores correlate with human judgment at all. A 0.7 threshold is meaningless if the judge's 0.7 doesn't map to human "acceptable."

**Evidence:**
- PRD Open Question #5: "Should this follow the closed-loop pattern (hardcoded default -> collect actuals -> calibrate from history)?"
- PHILOSOPHY.md: "If you ship stages 1-2 without 3-4, you've built a constant masquerading as intelligence"
- No inter-rater reliability plan (human vs. judge agreement)
- No bootstrapping strategy for the initial threshold
- Brainstorm: no mention of calibration at all

**Recommendation:** Close the open question definitively — yes, closed-loop is mandatory per PHILOSOPHY.md. Concrete plan: (a) Stage 1: ship 0.7 as default. (b) Stage 2: record both judge scores and human override decisions (when `CLAVAIN_SKIP_GATE` is used, record why — this is implicit human scoring). (c) Stage 3: after N=20 scored sprints, compute judge-human agreement rate; adjust threshold to minimize false negatives (blocked sprints humans would have shipped). (d) Stage 4: 0.7 remains fallback when history < 20 samples. Add this as an acceptance criterion in F4, not an open question.

---

## 5. Rubric Concreteness

**Priority:** P1 — vague rubrics produce noisy scores

**Finding:** The scenario YAML schema includes a rubric with criterion/weight pairs, but the criteria are natural-language strings ("Order persisted in database," "Confirmation email queued"). There is no specification for how a judge maps evidence to a criterion score. What does a 0.8 vs 0.5 mean for "Order persisted in database"? Is the judge scoring binary (present/absent) or graded? Without concrete scoring anchors, different judge calls will interpret the same criterion differently, amplifying the non-determinism problem.

**Evidence:**
- Brainstorm scenario schema: `criterion: "Order persisted in database"` with `weight: 0.4` — no scoring anchor
- PRD F4: "per-criterion scores" — no scale definition
- No rubric specification beyond criterion + weight
- The term "deterministic rubric scoring" in the brainstorm is unexplained

**Recommendation:** (a) Define scoring scale per criterion type: binary (0 or 1), ordinal (0, 0.5, 1 with anchors), or continuous (with explicit anchor descriptions for 0.0, 0.5, 1.0). (b) Extend the scenario YAML schema to include scoring anchors per criterion — e.g., `scoring: binary` or `scoring: {0: "not present", 0.5: "partially present", 1: "fully verified"}`. (c) Clarify what "deterministic rubric scoring" means — if some criteria can be checked programmatically (grep for order in DB, check email queue), those should bypass the LLM judge entirely. Deterministic checks are cheaper, faster, and reproducible.

---

## 6. Appeal Mechanism

**Priority:** P2 — important for system health but not launch-blocking

**Finding:** No appeal or feedback mechanism exists when judges produce incorrect scores. If `fd-correctness` scores a technically correct implementation as failing, the only recourse is `CLAVAIN_SKIP_GATE` (which bypasses the entire gate, not just the disputed criterion). There's no way for an agent or human to contest a specific criterion score, provide counter-evidence, and have the score re-evaluated. Without this, incorrect scores poison the calibration data (section 4) and agents learn to work around judge blind spots rather than improve.

**Evidence:**
- PRD F4: only override is `CLAVAIN_SKIP_GATE` — all-or-nothing
- No per-criterion override or re-score mechanism
- No feedback channel from gate results back to judge improvement
- PHILOSOPHY.md "Disagreement" section: "Agents escalate high-confidence disagreements rather than silently comply" — but no mechanism for this in the PRD

**Recommendation:** (a) Add per-criterion override: `clavain-cli scenario-override <run-id> <criterion> <score> --reason "..."`. (b) Record overrides as CXDB turns (`clavain.judge_override.v1`) — these are the highest-value calibration data. (c) Phase 2 or 3: when override rate for a criterion exceeds threshold, flag the rubric for revision. (d) Consider PHILOSOPHY.md's disagreement protocol: if the implementing agent's self-assessment diverges significantly from the judge score, auto-escalate to human review rather than auto-fail.

---

## 7. Closed-Loop Compliance (PHILOSOPHY.md)

**Priority:** P0 — architectural alignment

**Finding:** The PRD partially follows the closed-loop pattern but leaves the critical stages incomplete. Mapping to the 4-stage pattern:

| Stage | Status | Evidence |
|---|---|---|
| 1. Hardcoded defaults | Present | Default threshold 0.7, three named judge agents |
| 2. Collect actuals | Partial | Scores recorded in CXDB, but no human ground-truth collection |
| 3. Calibrate from history | Missing | Open question #5, no acceptance criteria |
| 4. Defaults as fallback | Missing | No specification for cold-start or missing-history behavior |

Additionally, the Goodhart caveat from PHILOSOPHY.md ("Agents will optimize for any stable target. Rotate metrics, cap optimization rate, randomize audits") is directly relevant to LLM-as-judge scoring but is not addressed. If implementation agents learn which criteria the judges check, they will optimize for those criteria at the expense of unchecked dimensions. The holdout separation helps (agents can't see holdout scenarios) but doesn't address criterion gaming within visible dev scenarios.

**Evidence:**
- PHILOSOPHY.md: "Rotate and diversify. No single metric stays dominant."
- PHILOSOPHY.md: "Anti-gaming by design. Rotate metrics, cap optimization rate, randomize audits."
- PRD: static rubric criteria with fixed weights — no rotation or randomization
- PRD: dev scenarios visible to implementation agents — criteria are gameable

**Recommendation:** (a) Close open question #5: mandatory closed-loop, not optional. (b) Add Goodhart mitigation: periodic rotation of holdout scenarios, random sampling of criteria subsets per gate check rather than scoring all criteria every time. (c) Track criterion-level score drift over time — if a criterion's average score monotonically increases without corresponding human-validated quality improvement, flag it as potentially gamed.

---

## Summary

| # | Area | Priority | Status |
|---|---|---|---|
| 1 | Non-determinism | P0 | No multi-evaluation strategy, no variance handling |
| 2 | Cost/latency | P1 | No model tier, no cost ceiling, no latency SLO |
| 3 | Judge unavailability | P1 | No timeout, retry, or degraded mode |
| 4 | Calibration | P0 | Closed-loop left as open question despite PHILOSOPHY.md mandate |
| 5 | Rubric concreteness | P1 | Criteria are natural-language strings without scoring anchors |
| 6 | Appeal mechanism | P2 | All-or-nothing gate bypass, no per-criterion feedback |
| 7 | Closed-loop compliance | P0 | Stages 3-4 missing, Goodhart mitigations absent |

---

## Verdict: SHIP_WITH_FIXES

The PRD's architecture is sound — reusing flux-drive agents as judges, recording scores in CXDB, and gating Ship on holdout satisfaction is the right shape. But the judge reliability layer is underspecified to the point where the gate could be worse than no gate (noisy scores blocking valid work, or passing invalid work, with no calibration to converge on correctness).

**Required fixes before implementation begins:**

1. **Close open question #5:** Threshold calibration follows the closed-loop pattern. This is not optional per PHILOSOPHY.md. Add stages 3-4 as acceptance criteria in F4.
2. **Specify evaluation protocol:** temperature=0, N>=3 evaluations, median aggregation, variance threshold for inconclusive results.
3. **Add judge failure handling:** Retry policy, timeout, degraded-mode behavior. Never silently block or silently bypass.
4. **Define scoring anchors:** Extend scenario YAML schema with criterion scoring types and anchor descriptions. Separate deterministic checks from LLM-judged criteria.
5. **Add cost/latency bounds:** Model tier for judges, cost ceiling per gate, latency SLO.

Items 6 (appeal mechanism) and Goodhart mitigations can ship in Phase 2/3 but should be documented as planned work, not left unmentioned.
