### Findings Index
- P1 | FC-1 | "Question" | Safety floor enforcement missing from the design — fd-safety and fd-correctness must never route to non-Claude models regardless of cost savings
- P1 | FC-2 | "Current Cost Model" | Cost gap analysis is incomplete — the 55x input cost gap (Opus vs DeepSeek V3) narrows to ~8x for output tokens and varies by task type
- P2 | FC-3 | "Question" | Cognitive agents are the best candidates for cheap models, but reaction round quality degrades below sonnet-tier reasoning
- P2 | FC-4 | "Current Architecture" | Stage 1 triage must stay on Claude — routing triage to cheaper models cascades wrong expansion decisions through the entire pipeline
- P2 | FC-5 | "Question" | Budget-aware provider selection needs a cost-quality Pareto frontier, not a binary "cheap or expensive" switch
Verdict: needs-changes

### Summary

The document identifies a real cost optimization opportunity but frames it as a uniform "route some agents to cheaper models" decision when the actual optimization surface is agent-type-specific with sharp quality cliffs. The existing `agent-roles.yaml` already defines a 4-tier role taxonomy (planner/reviewer/editor/checker) with `min_model` safety floors and `domain_complexity` ratings. Extending this to cross-provider routing requires: (a) a per-role provider eligibility matrix, (b) safety floor enforcement that spans providers (not just Claude tiers), (c) cost modeling that accounts for output quality degradation, not just input token price. The ~55x cost gap the document cites is the headline number for input tokens — the real savings after accounting for output quality, retry rates, and format compliance are likely 10-20x, still substantial.

### Issues Found

FC-1. **P1: Safety floor enforcement across providers.** `agent-roles.yaml` (line 32-33) defines `min_model: sonnet` for planner and reviewer roles, and the comment on line 26 states "fd-safety and fd-correctness NEVER route below Sonnet." This floor currently operates within the Claude tier hierarchy. If OpenRouter dispatch is added, the safety floor must extend to a cross-provider quality equivalence: "fd-safety runs on Claude Sonnet or better, never on any non-Claude model regardless of benchmark scores." The document's framing of "which agent types benefit most from Claude's strengths" implicitly assumes all agents are candidates — but `budget.yaml` line 46-48 lists `exempt_agents: [fd-safety, fd-correctness]` which are exempt from budget cuts and AgentDropout. The same exemption logic must extend to provider routing.

**Concrete scenario:** A cost-optimization pass routes fd-safety to DeepSeek V3 (which scores well on general benchmarks). DeepSeek V3 misses a credential exposure in a .env file because its safety training prioritizes different threat models than Claude's. The finding is lost with no indication it was missed — the review completes with fewer findings but no error signal.

**Smallest fix:** Add `provider_floor: claude` to exempt_agents entries in budget.yaml. The routing logic checks `if agent in exempt_agents and resolved_provider != "claude": override to claude`.

FC-2. **P1: Misleading cost gap analysis.** The document cites "10-50x lower cost than Claude Opus" but this conflates input and output pricing. Real numbers (as of early 2026): DeepSeek V3 = $0.27/M input, $1.10/M output. Claude Opus = $15/M input, $75/M output. The input ratio is 55x but the output ratio is 68x. However, for review agents that produce ~2-4K output tokens per ~30-40K input tokens, the total cost ratio is approximately: Claude Opus = ($15 * 35 + $75 * 3) / 1000 = $0.75 per agent. DeepSeek V3 = ($0.27 * 35 + $1.10 * 3) / 1000 = $0.013 per agent. That is a ~58x total cost reduction per agent. But this assumes equal quality — if DeepSeek requires 2x longer prompts for format compliance (few-shot examples, explicit format instructions), the ratio drops. And if retry rates are 20% (format validation failures), effective cost is 1.2x raw cost.

**Smallest fix:** Add a `provider_costs` section to budget.yaml with per-provider per-direction rates, and compute effective cost including estimated retry multiplier.

FC-3. **P2: Cognitive agents are the best routing candidates.** The checker role (fd-perception, fd-resilience, fd-decisions, fd-people) already has `max_model: sonnet` and `domain_complexity: low` in agent-roles.yaml. These agents apply cognitive lenses to text — they don't need deep code understanding or safety reasoning. They are the strongest candidates for OpenRouter dispatch. However, the reaction round (Phase 2.5) requires agents to evaluate peer findings and produce independent critique. If cognitive agents are on cheaper models during the reaction round, the sycophancy detection in `discourse-fixative.yaml` may be less effective because cheaper models have weaker metacognitive capabilities. The reaction round should keep its current model tier even if the initial dispatch used a cheaper model.

FC-4. **P2: Stage 1 triage is the quality bottleneck.** The document mentions "tiered dispatch" but doesn't explicitly protect Stage 1. Stage 1 agents determine the expansion score, which gates Stage 2 dispatch and AgentDropout. If Stage 1 agents produce lower-quality findings on cheaper models, the expansion scoring in `phases/expansion.md` will under-trigger, leading to fewer Stage 2 agents launching. This is a cascade failure — saving $0.50 on Stage 1 could lose $5 of insight from Stage 2 agents never being launched. Stage 1 should always run on Claude.

FC-5. **P2: Binary cost optimization is suboptimal.** The document frames the choice as "Claude for high-judgment, cheap models for the rest." The actual optimization surface has at least 4 dimensions: (a) agent role (planner/reviewer/editor/checker), (b) input complexity (thin document vs large diff), (c) budget pressure (tight sprint budget vs quality-critical review), (d) model availability (OpenRouter model health). A Pareto frontier approach would define quality thresholds per agent type and select the cheapest model meeting that threshold, with real calibration data from shadow runs (already supported by `cross_model_dispatch.mode: shadow` in budget.yaml line 71).

### Improvements

FC-I1. Run shadow-mode cross-provider dispatch on 20+ reviews before enforcing: route Stage 2 checker-role agents to DeepSeek V3 in shadow mode, compare finding recall against Claude Haiku/Sonnet baselines. The existing shadow infrastructure in budget.yaml supports this.

FC-I2. Define a `provider_eligibility` matrix in agent-roles.yaml: `{planner: [claude], reviewer: [claude], editor: [claude, openrouter], checker: [claude, openrouter]}` — makes the routing policy explicit and auditable.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 5 (P0: 0, P1: 2, P2: 3)
SUMMARY: The cost optimization opportunity is real (~58x per agent for checker-role agents) but requires safety floor extension to cross-provider, protection of Stage 1 triage quality, and shadow-mode calibration before enforcing. Cognitive/checker agents are the best candidates; planner/reviewer agents should stay on Claude.
---
<!-- flux-drive:complete -->
