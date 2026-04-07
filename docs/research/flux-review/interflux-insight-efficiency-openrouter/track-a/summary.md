# Flux-Drive Review: Interflux Insight Quality & Token Efficiency via OpenRouter

**Input:** `docs/research/flux-review/interflux-insight-efficiency-openrouter/input.md`
**Review type:** Design exploration document
**Agents:** 9 (5 project specialists + 2 cognitive Stage 1 + 2 cognitive Stage 2)
**Overall verdict:** needs-changes (8 agents) / risky (1 agent: fd-prompt-portability)

---

## Findings Summary

**Total findings:** 42 across 9 agents
- **P0:** 1 (prompt portability — DeepSeek R1 reasoning trace breaks Findings Index parsing)
- **P1:** 14 (integration plumbing, safety floors, cost modeling, signal theory, decision quality)
- **P2:** 21 (operational concerns, feedback loops, calibration gaps, sensemaking biases)
- **P3:** 6 (improvements and polish)

---

## Deduplicated Top Findings (Cross-Agent Convergence)

### P0 — Drop Everything

**1. DeepSeek R1 reasoning trace breaks synthesis parsing** (PP-1)
DeepSeek R1 produces `<think>...</think>` preamble before structured output. The Findings Index parser in Step 3.1 checks "first non-empty line starts with `### Findings Index`" — this will fail, classifying valid output as malformed. OpenRouter may substitute R1 for V3 during capacity constraints.
- **Fix:** Strip `<think>` blocks from OpenRouter responses before `.md.partial` write. Pin exact model IDs in provider config.
- **Cross-agent convergence:** PP-1 (primary), OD-3 (format normalization), AR-4 (partial failure)

### P1 — Must Address Before Implementation

**2. Safety floor enforcement must extend across providers** (FC-1, convergence: 3 agents)
`agent-roles.yaml` defines `min_model: sonnet` and `budget.yaml` lists `exempt_agents: [fd-safety, fd-correctness]` — but these floors only operate within Claude tiers. If OpenRouter dispatch is added, exempt agents must be restricted to Claude regardless of cost savings. DeepSeek's safety training covers different threat models than Claude's.
- **Fix:** Add `provider_floor: claude` to exempt_agents. Check in routing logic.
- **Supporting agents:** FC-1, OD-5 (progressive enhancement), SYS-1 (degradation loop)

**3. Bash-tool dispatch is architecturally wrong — use an MCP server** (OD-1)
Bash tool returns response content into the orchestrator's context window. Dispatching 4 agents via curl dumps ~48K tokens of raw response into the host context, defeating the token efficiency goal. The Agent tool avoids this because subagent output goes to files.
- **Fix:** Build an `openrouter-dispatch` MCP server that accepts prompt + output path, writes response using the `.md.partial` protocol, returns only status.
- **Supporting agents:** OD-1 (primary), AR-1 (rate limits), AR-2 (timeouts)

**4. Token accounting has no provider dimension** (OD-2, convergence: 3 agents)
`budget.yaml` cost_basis, `token-count.py`, and interstat recording all assume Claude JSONL format. OpenRouter returns OpenAI-compatible usage JSON with different fields and fundamentally different cost-per-token rates.
- **Fix:** Add `provider_costs` section to budget.yaml. Extend token-count.py to parse OpenRouter response JSON.
- **Supporting agents:** OD-2, AR-3, FC-2

**5. Parallel dispatch will hit OpenRouter rate limits** (AR-1)
Free tier: 20 req/min. Paid tiers: 200-500/min. Dispatching 6 agents simultaneously risks 429 batch failures, with later agents silently producing no findings.
- **Fix:** Concurrency limiter (max 3 concurrent OpenRouter requests) + exponential backoff retry.
- **Supporting agents:** AR-1 (primary), AR-2 (timeout), RES-1 (SPOF)

**6. Prompt template breaks on non-Claude models in 3 ways** (PP-2, PP-3)
XML tags lose semantic meaning (treated as literal text), system prompt messages get deprioritized or ignored, and persona instructions degrade to flavor text. These are well-documented behaviors of DeepSeek/Qwen model families.
- **Fix:** Create prompt variants per model family — XML to markdown, system+user flattened, explicit format examples.
- **Supporting agents:** PP-2, PP-3, PP-5

**7. Gateway lock-in — OpenRouter not evaluated against alternatives** (DEC-1)
Four alternatives exist: OpenRouter (managed gateway, markup), LiteLLM (self-hosted proxy, no markup), direct provider APIs (lowest cost, more code), local inference (zero API cost, requires GPU). The document treats gateway selection as decided.
- **Fix:** Evaluate at least 2 alternatives. The starter option is direct DeepSeek API calls for 2 agents, not full OpenRouter integration.
- **Supporting agents:** DEC-1, DEC-3 (complexity tax), RES-2 (staging)

**8. Benchmarks don't predict review quality** (PER-1)
The implicit logic "DeepSeek scores well on benchmarks, therefore it will produce good review findings" is map/territory confusion. No benchmark measures structured analytical output with severity calibration from a domain-specific cognitive lens.
- **Fix:** Empirical A/B testing with actual interflux agent prompts is the only valid evidence.
- **Supporting agents:** PER-1, DEC-2 (wrong metric), PER-3 (streetlight effect)

**9. Synthesis has no provider attribution — model diversity signal is lost** (MD-1)
The deduplication algorithm treats all findings as equivalent regardless of which model produced them. Cross-provider agreement on the same finding is stronger evidence than same-provider agreement, but this signal is invisible without a `provider` field in the findings contract.
- **Fix:** Add `provider:` metadata to Findings Index. Compute cross-provider convergence score in synthesis.
- **Supporting agents:** MD-1 (primary), MD-3 (disagreement taxonomy), SYS-3 (monoculture)

**10. Cost-quality degradation feedback loop** (SYS-1)
Cheaper models produce lower-quality findings, reducing interspect trust scores, which downweight those agents in synthesis, making cheap dispatch self-defeating. Over 50+ reviews, cheap-model agents could become zombie participants.
- **Fix:** Trust score floor during model experimentation periods. Evaluate model quality independently of trust calibration.
- **Supporting agents:** SYS-1, FC-3 (reaction quality), SYS-2 (pace mismatch)

### P2 — Address in Design

**11. No staged rollout plan** (RES-2, DEC-4, convergence: 4 agents)
The proposal goes from "no OpenRouter" to "full integration" with no intermediate steps and no pre-committed expand/contract/abandon criteria. Four agents independently recommend a staged approach with signposts.

**12. Stage 1 triage must stay on Claude** (FC-4)
Stage 1 determines expansion score. Lower-quality Stage 1 findings cause under-triggering of Stage 2 dispatch — saving $0.50 on triage could lose $5 of insight from agents never launched.

**13. Context window mismatch** (OD-4)
Slicing thresholds calibrated for Claude's 200K. DeepSeek V3 and Qwen 2.5 have 128K windows. No per-model context budget check exists.

**14. Reaction round sycophancy detection needs cross-model recalibration** (MD-2, FC-3)
Sycophancy patterns differ across model families. Hearsay detection heuristics are calibrated for Claude-Claude dynamics.

**15. Emergent monoculture through cost pressure** (SYS-3)
Cost optimization will push most agents to the single cheapest model, defeating the model diversity goal. Need `max_provider_share: 0.5` constraint.

**16. Budget-driven routing oscillation** (SYS-4)
Real-time budget coupling causes provider allocation swings across reviews. Define routing profiles (economy/balanced/quality) selected at review start.

---

## Cross-Agent Agreement Matrix

| Finding Theme | Agents Converging | Confidence |
|---|---|---|
| "Test empirically before building" | DEC-1, PER-1, RES-2, DEC-2, RES-I1 | Very High (5 agents) |
| "Safety-critical agents stay on Claude" | FC-1, OD-5, SYS-1 | High (3 agents) |
| "MCP server, not Bash curl" | OD-1, AR-1, AR-2 | High (3 agents) |
| "Provider-aware token accounting" | OD-2, AR-3, FC-2 | High (3 agents) |
| "Staged rollout with signposts" | RES-2, DEC-4, RES-3, DEC-5 | High (4 agents) |
| "Prompt template needs per-model variants" | PP-1, PP-2, PP-3, PP-5 | High (4 agents) |
| "Model diversity is the real value, not cost" | MD-1, PER-3, SYS-3, DEC-5 | High (4 agents) |

---

## Recommended Action Sequence

1. **$0.10 manual experiment** (30 minutes): Copy 3 recent flux-drive agent prompts, call DeepSeek V3 via curl, compare output quality and format compliance against Claude baseline. This answers "do non-Claude models produce usable findings?" before any engineering.

2. **Define signposts** (1 hour): Write expand/contract/abandon criteria. Pin to the bead. Review at 20 and 50 mixed-provider reviews.

3. **Build MCP server wrapper** (1-2 days): `openrouter-dispatch` MCP server that accepts prompt + output path, writes to `.md.partial` protocol, handles retry/backoff/timeout, returns status only.

4. **Prompt variants** (1 day): Per-model-family prompt format (XML to markdown, flattened messages, explicit format instructions, reasoning trace stripping).

5. **Shadow mode for checker-role agents** (1 week): Route fd-perception, fd-resilience, fd-decisions, fd-people to DeepSeek V3 in shadow mode. Compare finding recall and format compliance.

6. **Provider attribution in findings** (2 hours): Add `provider:` field to Findings Index contract. No synthesis changes yet — collect data first.

7. **Canary rollout** (2 weeks): If shadow metrics pass, route 2 checker-role agents to OpenRouter in 10% of reviews. Measure finding recall, false positive rate, and format compliance.

---

## What This Review Did NOT Cover

- Specific OpenRouter API documentation or current pricing (would need web search)
- Actual format compliance testing of DeepSeek V3/Qwen 2.5 with interflux prompts
- Comparison of OpenRouter vs LiteLLM vs direct API operational characteristics
- Legal/compliance implications of routing code to Chinese model providers
- Impact on the interserve (Codex) dispatch path

---

**Review completed by 9 agents: fd-openrouter-dispatch-integration, fd-heterogeneous-fleet-cost-routing, fd-model-divergence-signal-extraction, fd-prompt-portability-across-families, fd-api-resilience-and-observability, fd-systems, fd-decisions, fd-resilience, fd-perception.**
