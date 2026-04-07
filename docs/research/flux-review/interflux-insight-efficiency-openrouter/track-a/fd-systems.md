### Findings Index
- P1 | SYS-1 | "Question" | Reinforcing cost-quality feedback loop — cheaper models produce lower-quality findings, which reduce trust scores, which route more agents to cheaper models
- P2 | SYS-2 | "Current Architecture" | Pace layer mismatch — model pricing changes monthly while routing policy calibration takes weeks of shadow data
- P2 | SYS-3 | "Question" | Emergent monoculture risk — if cost optimization routes 80% of agents to one cheap provider, training bias homogeneity returns through a different door
- P2 | SYS-4 | "Constraints" | Bullwhip effect in budget-driven routing — small changes in sprint budget pressure cause large swings in provider allocation
Verdict: needs-changes

### Summary

The proposal to add OpenRouter dispatch introduces three feedback loops that the document doesn't analyze. First, a reinforcing degradation loop: cheaper models produce lower-quality findings, which reduce interspect trust scores for those agents, which in turn justifies routing more agents to cheaper models — but now with lower trust multipliers that reduce their weight in synthesis, making the cost savings self-defeating. Second, a pace layer mismatch: model pricing on OpenRouter changes weekly-to-monthly (DeepSeek V3 price dropped 3x in early 2025), while routing policy calibration requires 20+ shadow runs over weeks. The routing policy will always lag the pricing reality. Third, an emergent monoculture: the document motivates model diversity for insight quality, but cost optimization will push most agents toward the single cheapest model — recreating training bias homogeneity through economic pressure rather than technical constraint.

### Issues Found

SYS-1. **P1: Cost-quality degradation loop (Reinforcing).** The system has an existing trust multiplier mechanism (referenced in budget.yaml and the interspect calibration pipeline) that adjusts agent weight based on historical precision. If agents dispatched to cheaper models produce lower-quality findings, their trust scores will decrease. Lower trust scores mean their findings carry less weight in synthesis. This creates a perverse incentive: the system correctly identifies that cheap-model agents are less reliable, but the response (downweighting) doesn't fix the root cause (model quality) — it just makes the cost savings less valuable. Over 50+ reviews, agents routed to cheap models could have trust scores <0.5, effectively becoming decorative — running and costing tokens but contributing nothing to the final synthesis.

**Concrete scenario (T=0 to T=3months):** Initially, cognitive agents routed to DeepSeek V3 produce adequate findings. Over time, interspect detects lower precision (more false positives, fewer confirmed findings). Trust scores drop from 1.0 to 0.6. At 0.6, their findings are significantly downweighted in synthesis. The team sees "we're running 9 agents but synthesis only uses findings from 5" — the cheap agents become zombie participants.

**What the document should address:** A trust score floor for model experimentation periods — during the first 20 reviews with a new provider, hold trust scores at the pre-migration baseline to separate model quality signal from calibration noise.

SYS-2. **P2: Pace layer mismatch (Model pricing vs routing policy).** Model pricing on OpenRouter is a fast-moving layer — prices change with competitive pressure, capacity costs, and promotional periods. DeepSeek V3's price dropped from $0.55/M to $0.27/M input in early 2025. Qwen models have been repriced multiple times. The routing policy (which model to use for which agent) is a slow-moving layer — it requires shadow-mode data collection, recall analysis, and policy update. If the pricing layer changes faster than the policy layer can adapt, the system will either: (a) miss cost savings by routing to a model that's no longer the cheapest, or (b) route to a model whose quality changed with a pricing change (models sometimes degrade when providers cut prices by reducing inference quality).

SYS-3. **P2: Emergent monoculture through cost pressure.** The document frames model diversity as an insight quality lever — different model families have different blind spots, so disagreement is signal. But cost optimization creates pressure toward monoculture: if DeepSeek V3 is 10x cheaper than the next alternative, budget-aware routing will send most agents to DeepSeek V3. With 5/9 agents on DeepSeek V3, the model diversity benefit is reduced — you're back to same-provider agreement dynamics, just with a different provider. The document should define a minimum provider diversity target: e.g., "no single non-Claude provider gets more than 50% of dispatched agents."

SYS-4. **P2: Budget-driven routing bullwhip.** The document mentions "when sprint budget is tight, auto-route more agents to OpenRouter." Budget pressure is a volatile signal — it can change mid-sprint as other tasks consume tokens. If routing decisions are tightly coupled to current budget remaining, small budget fluctuations cause large swings in provider allocation. Review 1 of a sprint: budget is fresh, route to Claude. Review 5: budget is tight, route everything to OpenRouter. Review 6: new sprint starts, back to Claude. This oscillation prevents stable calibration and makes cross-review quality inconsistent.

### Improvements

SYS-I1. Add a provider diversity constraint to the routing policy: `max_provider_share: 0.5` — no single non-Claude provider can receive more than 50% of dispatched agents in a review. This preserves the model diversity signal even under cost pressure.

SYS-I2. Decouple routing decisions from real-time budget pressure. Instead, define routing profiles: `economy` (max OpenRouter), `balanced` (mixed), `quality` (Claude-only). Select profile at review start based on budget-at-start, not budget-at-dispatch. This prevents mid-review oscillation.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 4 (P0: 0, P1: 1, P2: 3)
SUMMARY: Three unanalyzed feedback loops: cost-quality degradation (trust scores penalize cheap-model agents into irrelevance), pace layer mismatch (pricing changes faster than policy calibration), and emergent monoculture (cost pressure defeats diversity goal). Provider diversity constraints and decoupled routing profiles would mitigate.
---
<!-- flux-drive:complete -->
