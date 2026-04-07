---
agent: fd-supply-chain-multi-sourcing
tier: project
model: sonnet
input: interflux-insight-efficiency-openrouter/input.md
track: b (operational parallel disciplines)
---

# fd-supply-chain-multi-sourcing — Findings

## Findings Index

| Severity | ID | Section | Title |
|----------|-----|---------|-------|
| P0 | SCM-01 | OpenRouter Integration | Single-source critical agents with no fallback path |
| P1 | SCM-02 | Model Roster | No supplier qualification: new models added without calibration baseline |
| P1 | SCM-03 | Cost Model | Total cost of ownership omits hidden costs: retry overhead, synthesis rework, validation cost |
| P2 | SCM-04 | Budget System | Static volume allocation: routing percentages never updated from quality signals |
| P3 | SCM-05 | Architecture | Dual sourcing not enforced for cross-cutting agents |

---

## Detailed Findings

### P0 — SCM-01: Single-Source Critical Agents with No Fallback

**Supply chain parallel:** The first principle of supply chain risk management is never single-source critical components. When your sole supplier for a key part goes offline, production stops. Mature procurement teams maintain at least two qualified suppliers for any safety-critical input.

**Interflux parallel:** The input document explicitly states `fd-safety` and `fd-correctness` are exempt from budget cuts and AgentDropout. This is correct for Claude-native dispatch. But the proposed architecture introduces OpenRouter as an additional dispatch backend. If OpenRouter is down, rate-limited, or returning degraded output, and the design routes *any* portion of non-exempt agents through it exclusively, those agents have no fallback path.

**Critical failure scenario:** A user triggers flux-drive on a security-sensitive codebase. Budget pressure or tier assignment routes `fd-quality` and `fd-architecture` to OpenRouter. OpenRouter experiences an API outage (documented incidents: 2025-Q3 multi-hour outage affecting all providers). The review completes with only 2 agents (fd-safety + fd-correctness on Claude), missing architectural findings. User ships a change believing it passed review. The OpenRouter outage was silent — no error surfaced to user.

**Why P0:** This is not a quality degradation — it's a silent partial review that looks like a complete review. A user cannot distinguish "4 agents reviewed" from "2 agents reviewed, 2 silently dropped" without reading the findings metadata carefully.

**Fix:** Add explicit fallback routing to the dispatch logic: if OpenRouter backend fails for an agent, re-route to Claude tier (haiku minimum) and log `provider_fallback: true` in dispatch metadata. One additional try/catch branch in the HTTP dispatch path. The budget impact of fallback should be surfaced as a warning, not a silent cost increase.

---

### P1 — SCM-02: No Supplier Qualification — Models Added Without Calibration Baseline

**Supply chain parallel:** Professional procurement teams run supplier qualification before adding a vendor to the approved roster: sample testing, quality audits, capacity verification. A supplier that passes qualification gets a quality score and volume allocation. One that fails qualification never touches production.

**Interflux parallel:** The input document lists DeepSeek V3/R1, Qwen 2.5/3, Yi as candidate cheap models. These are candidates, not qualified suppliers. There is no described process for determining which agent types each model handles adequately. "Strong reasoning at 10-50x lower cost" is a marketing claim, not a quality baseline.

**Concrete gaps:**
1. No benchmark process: which agent prompts does each model handle adequately? (Format compliance, finding precision, severity calibration)
2. No minimum bar: what is the minimum acceptable findings quality score to qualify a model for production dispatch?
3. No re-qualification trigger: if a model's quality degrades after an API update, what triggers re-evaluation?

**Failure scenario:** Qwen 2.5 is added to the OpenRouter roster after a brief manual test. A subsequent model update (Qwen releases updates frequently) degrades its instruction-following. The findings format is corrupted subtly — severity labels shift. Synthesis absorbs the degraded output. Quality degrades across all reviews using Qwen until someone manually notices.

**Fix:** Define a qualification checklist before adding any model to the dispatch roster: (1) run 3 synthetic review tasks with known ground-truth findings, (2) measure format compliance rate, (3) measure finding precision/recall against Claude baseline, (4) set minimum thresholds. Store results in `config/flux-drive/model-registry.yaml` (new file, 20 lines). Requalify on major model updates.

---

### P1 — SCM-03: Total Cost of Ownership Ignores Hidden Costs

**Supply chain parallel:** Unit price is never total cost. Procurement teams calculate Total Cost of Ownership: unit price + incoming inspection + rework rate + logistics + supplier management overhead. A supplier with 30% lower unit price but 15% higher defect rate may have higher TCO.

**Interflux parallel:** The input document frames cost reduction as "10-50x lower cost than Claude Opus." This is the unit price (tokens/dollar). The hidden costs are not mentioned:

1. **Retry cost:** If a cheap model returns malformed output, the orchestrator retries. How many retries before fallback? Each retry burns tokens and latency.
2. **Validation cost:** Adding output format validation (necessary — see TCA-03) adds orchestrator compute.
3. **Synthesis overhead:** Heterogeneous output from different model families may require additional deduplication passes if findings use different terminology for the same issue.
4. **Integration cost:** Building and maintaining the OpenRouter dispatch path (HTTP client, error handling, token accounting, model registry) is engineering cost amortized over runs.
5. **Quality rework:** If a cheap model misses a P0 finding that Claude would have caught, the cost is not token savings — it's the cost of the bug that shipped.

**Failure scenario:** Interflux ships with DeepSeek V3 on fd-quality and fd-architecture. Token cost drops 40%. But retry rate is 8% (format compliance failure), synthesis runs 1.3x longer (heterogeneous deduplication), and 2 P1 bugs ship in the first month that Claude would have caught. True TCO is break-even vs full-Claude at this quality level.

**Fix:** Add TCO framing to `config/flux-drive/budget.yaml` documentation: explicit fields for `retry_cost_multiplier`, `validation_overhead_tokens`, `expected_quality_discount`. These can start as estimates and be updated from actual run data via interstat.

---

### P2 — SCM-04: Static Volume Allocation — Routing Percentages Never Updated

**Supply chain parallel:** Professional procurement teams run quarterly supplier reviews: volume allocation percentages are adjusted based on quality scorecards, delivery performance, and price negotiations. A supplier that improved quality gets more volume. One that degraded gets less.

**Interflux parallel:** The proposed tiering (agent_type → model tier) is static configuration. Once `fd-quality → OpenRouter` is configured, it stays that way until a human changes it. There's no mechanism to observe that `fd-quality` on Qwen 2.5 is producing 30% fewer findings than Claude baseline and automatically adjust allocation.

**This is a P2 (not P1) because:** Static allocation still produces value — it's just not learning. The risk is quality drift over months, not immediate failure.

**Fix (evolutionary path):** The interstat database already tracks per-agent token costs and run metadata. Extend it to track `findings_count`, `severity_distribution`, and `provider` per run. `scripts/estimate-costs.sh` could include a `model-quality-report` mode that surfaces per-provider finding quality trends. Start with reporting; adaptive rebalancing is a later iteration.

---

### P3 — SCM-05: Dual Sourcing Not Enforced for Cross-Cutting Agents

**Supply chain parallel:** Cross-cutting components (those that appear in multiple product lines) require dual sourcing by policy — a single supplier failure cascades across all products.

**Interflux parallel:** `fd-architecture` and `fd-quality` are cross-cutting — they run in almost every review. If both are routed exclusively to OpenRouter, a provider outage takes down the most commonly-dispatched agents simultaneously.

**Fix:** Policy constraint: cross-cutting agents (fd-architecture, fd-quality) must always have a Claude fallback tier configured, even if OpenRouter is the primary. This is a one-line rule in routing configuration — but it needs to be explicit, not implicit.

---

## Verdict

**needs-changes**

The supply chain lens surfaces one P0 the trading desk lens missed: **silent partial review** from provider outage looks like a complete review to the user. This is the most dangerous failure mode in the design. The P1 qualification gap (models added without calibration baseline) is the second highest priority — it's the difference between a controlled quality/cost tradeoff and an uncontrolled quality drift.

The strongest supply chain lesson for interflux: **dual sourcing is not about redundancy, it's about visibility**. When you have a fallback, you notice when the primary fails. When you're single-sourced, you find out from your customers.

<!-- flux-drive:complete -->
