### Findings Index
- P1 | DEC-1 | "Question" | Premature commitment to OpenRouter as the multi-model gateway — alternative integration paths (LiteLLM, local inference) not evaluated
- P2 | DEC-2 | "Question" | Anchoring on input token cost obscures the real optimization target — finding quality per dollar, not tokens per dollar
- P2 | DEC-3 | "Constraints" | Irreversibility of prompt template changes — once prompts are adapted for non-Claude models, the complexity tax is permanent even if OpenRouter is abandoned
- P2 | DEC-4 | "Question" | Missing signposts — no pre-committed criteria for when to expand, contract, or abandon OpenRouter integration
- P3 | DEC-5 | "Question" | Explore/exploit imbalance — the proposal is all exploitation (cost savings now) with insufficient exploration (what novel insights does model diversity actually produce?)
Verdict: needs-changes

### Summary

The document exhibits anchoring bias on OpenRouter specifically when the real question is "should interflux dispatch to non-Claude models, and if so, through what mechanism?" OpenRouter is one gateway; LiteLLM (self-hosted proxy), direct API calls to providers, and local inference (Ollama/vLLM) are alternatives not evaluated. The cost framing anchors on input token pricing ($15/M vs $0.27/M) when the optimization target should be finding quality per dollar — a metric that requires empirical measurement, not price comparison. The proposal also lacks signposts: specific, pre-committed criteria for deciding whether the integration is working. Without signposts, the team risks continuing to invest in a degraded integration because "we've already built it" (sunk cost).

### Issues Found

DEC-1. **P1: Gateway lock-in without alternatives analysis.** The document frames the integration as "OpenRouter integration" throughout, treating gateway selection as decided. But the actual decision is: "How should interflux dispatch to non-Claude models?" At least four options exist:

(a) **OpenRouter** — managed multi-model gateway, handles provider failover, adds markup (~10-30% over direct API pricing), single API key.
(b) **LiteLLM** — self-hosted proxy with OpenAI-compatible API, no markup, requires hosting, supports 100+ providers.
(c) **Direct provider APIs** — call DeepSeek/Qwen APIs directly, lowest cost, requires per-provider integration, more code to maintain.
(d) **Local inference** — Ollama/vLLM with open-weight models, zero API cost, requires GPU, latency depends on hardware.

Each has different cost structures, failure modes, and operational requirements. The document should evaluate these as alternatives before committing to OpenRouter. The "starter option" (smallest commitment to learn most) would be direct DeepSeek API calls for 2 agents, not a full OpenRouter integration.

DEC-2. **P2: Wrong optimization metric.** The document frames the opportunity as "10-50x lower cost" based on per-token pricing. But the metric that matters is **finding quality per dollar**: how many P0/P1/P2 findings of confirmed accuracy does each dollar of model cost produce? A $0.75 Claude agent that produces 3 confirmed findings = $0.25/finding. A $0.013 DeepSeek agent that produces 1 confirmed finding = $0.013/finding. But if that DeepSeek agent also produces 2 false positives that waste human review time (valued at $50/hr, 5 minutes each = $8.33), the effective cost is $8.35/finding — 33x worse than Claude. The cost analysis must include downstream human review cost of false positives.

DEC-3. **P2: Complexity tax is permanent.** Adapting the prompt template for non-Claude models (per fd-prompt-portability findings) adds permanent complexity: prompt variants per model family, response format validation, reasoning trace stripping, XML-to-markdown conversion. This complexity persists in the codebase even if OpenRouter integration is later disabled or abandoned. The document should quantify this maintenance burden: how many additional code paths, how many conditional branches, how much testing surface area? If the answer is "small" (a prompt format flag and a response validator), it's acceptable. If it's "large" (per-model prompt templates, per-model parsers, per-model retry logic), the complexity tax may exceed the cost savings.

DEC-4. **P2: No pre-committed decision criteria.** The document should define signposts — specific, measurable criteria that trigger strategy changes:

- **Expand signal:** After 20 shadow reviews, if cheap-model agents achieve >80% finding recall vs Claude baseline on checker-role tasks, expand to editor-role agents.
- **Contract signal:** If false positive rate on cheap-model agents is >2x Claude baseline, restrict to checker-role only.
- **Abandon signal:** If total integration maintenance cost (developer time for prompt variants, debugging, monitoring) exceeds the token cost savings over a 3-month period, disable OpenRouter dispatch.

Without signposts, the team will evaluate the integration based on feelings ("it seems to work") rather than evidence.

DEC-5. **P3: Explore/exploit imbalance.** The proposal focuses on exploitation — achieving the same insights at lower cost. But the exploration question is more interesting: "What novel insights does model diversity produce that a Claude-only fleet cannot?" The document mentions this ("disagreements might be more meaningful") but doesn't propose experiments to test it. A small exploration budget (10% of reviews run with forced model diversity, regardless of cost, specifically to measure insight novelty) would answer the exploration question while the exploitation path is being built.

### Improvements

DEC-I1. Before building anything, run a 5-review manual experiment: copy 5 recent flux-drive agent prompts, call DeepSeek V3 directly via curl, compare finding quality to Claude output. Total cost: ~$0.10. This answers "do non-Claude models produce useful findings with current prompts?" before any engineering investment.

DEC-I2. Define the signposts document (expand/contract/abandon criteria) before starting implementation. Pin it to the bead for this work. Review it at 20 and 50 mixed-provider reviews.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 5 (P0: 0, P1: 1, P2: 3, P3: 1)
SUMMARY: The proposal anchors on OpenRouter without evaluating alternatives, uses input token pricing as the optimization metric when finding quality per dollar is what matters, and lacks pre-committed signposts for expand/contract/abandon decisions. A $0.10 manual experiment should precede any engineering investment.
---
<!-- flux-drive:complete -->
