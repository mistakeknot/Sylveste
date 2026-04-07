---
agent: fd-trading-desk-order-routing
tier: project
model: sonnet
input: interflux-insight-efficiency-openrouter/input.md
track: b (operational parallel disciplines)
---

# fd-trading-desk-order-routing — Findings

## Findings Index

| Severity | ID | Section | Title |
|----------|-----|---------|-------|
| P1 | TCA-01 | Cost Model | No post-trade analysis: impossible to prove routing improves cost/quality ratio |
| P1 | TCA-02 | Dispatch Architecture | Static venue selection: model routing doesn't adapt to current conditions |
| P2 | TCA-03 | OpenRouter Integration | No dark-pool fill quality gate: cheap model output accepted without quality score |
| P2 | TCA-04 | Budget System | Order splitting ignores workload divisibility: not all agent tasks are fungible across model tiers |
| P3 | TCA-05 | Cross-model Dispatch | Best execution obligation unmet: no audit trail proving routing decision rationale |

---

## Detailed Findings

### P1 — TCA-01: No Post-Trade Analysis (TCA equivalent missing)

**Trading desk parallel:** Smart order routers are legally required to demonstrate "best execution" — that routing decisions actually achieved better cost/quality than naive approaches. Without Transaction Cost Analysis, you can't prove routing is better than just sending every order to the lit market.

**Interflux parallel:** The input document describes cross-model dispatch as a cost-efficiency measure, but the current architecture has no mechanism to compare: "What would this run have cost on Claude-only vs the routed configuration?" `config/flux-drive/budget.yaml` tracks budgets and `scripts/estimate-costs.sh` queries interstat, but neither produces a comparative cost/quality report across routing strategies.

**Failure scenario:** Six months after OpenRouter integration ships, a user asks "is this actually cheaper?" The answer requires manually querying interstat, joining on run metadata, and computing per-model findings quality scores — none of which have been instrumented. The team cannot prove routing effectiveness, cannot tune allocation percentages, and cannot detect when a provider's quality/cost ratio shifts.

**Fix:** Add a `routing-report` output to synthesis: for each run, emit `{model: X, tokens: N, cost: $M, findings_count: K, severity_distribution: {...}}` per provider. This is one additional JSON block in `phases/synthesize.md` — the data already flows through synthesis.

---

### P1 — TCA-02: Static Venue Selection — Routing Doesn't Adapt to Current Conditions

**Trading desk parallel:** Smart order routers that use fixed venue percentages regardless of market conditions are called "dumb routers." Real SORs continuously score each venue by current fill rate, fee tier, and queue depth — the same venue gets 80% allocation at 9am and 20% at 3pm based on real-time signals.

**Interflux parallel:** The input document envisions tiered dispatch (cheap models for some agents, Claude for high-judgment tasks), but the proposed routing is static: agent type → model tier, configured once. There's no mechanism for the orchestrator to observe that DeepSeek V3 is returning low-confidence or poorly-structured findings *in this run* and temporarily re-route to Claude.

**Failure scenario:** DeepSeek V3 is having a bad day (model update, API degradation, prompt format regression). The static router keeps sending 40% of agents to it. Finding quality degrades silently. No automatic circuit breaker exists.

**Fix:** The expansion scoring already in `phases/launch.md` (expansion triggered by finding severity) can be extended: if a cheap-model agent's finding count is below threshold OR severity distribution is anomalous, trigger re-routing of that agent's task to a Claude tier as Stage 2 expansion. The circuit breaker is a one-clause addition to the expansion condition.

---

### P2 — TCA-03: No Fill Quality Gate for Cheap Model Output

**Trading desk parallel:** Dark pool execution is cheap but has hidden costs: partial fills, price improvement failure, information leakage. Professional routers always validate fill quality before marking an order complete, even if the venue is cheap.

**Interflux parallel:** The input document correctly identifies that cheap models (DeepSeek, Qwen) will produce findings, but doesn't address output format validation. Claude agents write structured Findings Index output (enforced by agent prompts). OpenRouter-dispatched agents running via Bash tool have no such enforcement — the HTTP response is free-form text that must be parsed into the findings format.

**Failure scenario:** A Qwen 2.5 agent returns a well-reasoned response that doesn't use the `SEVERITY | ID | "Section" | Title` format. Synthesis either (a) silently drops these findings, (b) fails to parse them, or (c) includes them as unstructured text that breaks the convergence scoring. All three outcomes are silent — no error is surfaced to the user.

**Fix:** Add a findings parser/validator step between OpenRouter response receipt and findings index write. This is already partially designed in `phases/shared-contracts.md` (completion signals) — extend it to validate format before writing `.md` file. Findings that fail validation get flagged with `PARSE-FAIL` in the synthesis summary.

---

### P2 — TCA-04: Order Splitting Ignores Workload Divisibility

**Trading desk parallel:** Smart order routers split large orders across venues, but only for fungible instruments. You can't split a block trade in an illiquid stock — the market impact of partial fills exceeds the fee savings.

**Interflux parallel:** The input proposes routing different agent *types* to different models. But not all agent workloads are fungible. `fd-safety` and `fd-correctness` require deep codebase understanding and multi-hop reasoning — qualities where Claude's instruction-following and context management significantly outperform cheap models. `fd-quality` (naming conventions, style) is far more fungible. The proposed tiering (agent_type → model) doesn't capture *why* some tasks are non-fungible.

**Insight:** The split should be along *reasoning depth* and *instruction-following sensitivity*, not just agent category. A fd-architecture review on a complex distributed system is non-fungible; a fd-quality review on a simple Python script is highly fungible. Routing by agent type is a proxy for a better signal.

**Fix (P3 upgrade path):** Add a complexity signal to the triage profile. Current `Estimated complexity: [small|medium|large]` already exists — extend it to gate model tier selection. Small complexity → cheap model eligible. Large complexity + cross-cutting agent → Claude required.

---

### P3 — TCA-05: No Audit Trail for Routing Decisions

**Trading desk parallel:** Every routing decision must be logged: which venue, at what time, what price, why that venue was selected. Post-trade audit requires reconstructing the routing decision for any order.

**Interflux parallel:** When interflux routes an agent to OpenRouter instead of Claude, that decision should be logged: which model was selected, why (tier assignment, budget pressure, expansion score), and what it cost. Currently `findings.json` captures findings but not dispatch metadata.

**Fix:** Add `dispatch_metadata` to `findings.json` output — agent name, model used, tokens consumed, provider. One additional field, available from the HTTP response headers for OpenRouter calls.

---

## Verdict

**needs-changes**

The design direction (multi-model dispatch via OpenRouter) is sound and the parallel to smart order routing is direct. Two P1 gaps — no TCA equivalent and no adaptive routing — must be addressed before the integration is production-ready. Without a cost/quality comparison mechanism, the claimed efficiency gains are unverifiable. Without adaptive routing, provider degradation propagates silently into review quality.

The strongest operational lesson from trading desks: **routing algorithms are only as good as their feedback loops**. Dark pool routing became sophisticated because fill quality data fed back into venue scoring. Interflux needs the same — cheap model findings quality feeding back into the dispatch decision for the next run.

<!-- flux-drive:complete -->
