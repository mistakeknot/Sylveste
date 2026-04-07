### Findings Index
- P1 | MUR-1 | "Current Cost Model" | No explicit task criticality taxonomy — all agents default to same tier regardless of judgment requirements
- P1 | MUR-2 | "OpenRouter integration" | Tiered dispatch proposed but routing dimension is technical/cognitive binary, not maestro-vs-lavorante capability analysis
- P2 | MUR-3 | "Cross-model dispatch" | Expansion scoring upgrades model tier but no downgrade protection for safety-adjacent tasks routed to cheap models
- P2 | MUR-4 | "Budget system" | Per-type token budgets exist but no calibration feedback loop to detect when cheap models underperformed on a delegated task
- P3 | MUR-5 | "Model diversity as a signal" | Cheap-model baseline comparison not proposed as explicit calibration mechanism for tier promotion decisions

Verdict: needs-changes

### Summary

The interflux architecture as described treats the tiered dispatch problem as a cost optimization problem rather than a skill delegation problem. The Murano maestro's central discipline — identifying the specific five seconds of a thirty-minute process that require the maestro's hands — is absent from the proposed design. The document proposes routing "certain agent types" to cheaper models and keeping "high-judgment tasks" on Claude, but nowhere is there an explicit taxonomy of which specific review subtasks (ambiguity resolution, inter-finding conflict adjudication, safety implication threading) require Claude's capabilities versus which (pattern matching, checklist verification, deduplication orientation) can be competently handled by cheaper models.

The current cross-model dispatch in `phases/expansion.md` adjusts tiers based on `expansion_score` and `budget_pressure_label` — both of which are signals about the volume and urgency of findings, not about the nature of the cognitive work required by the agent. An agent can score high on expansion because Stage 1 found many P0 issues in adjacent domains, but that says nothing about whether the agent's own review task requires irreplaceable judgment or can be mechanically executed by a cheap model. The maestro who delegates based on workshop throughput pressure rather than task nature will eventually send a garzone to shape the lip.

### Issues Found

**[P1-1]** Section: "Current Cost Model / Tiered dispatch" — No task-criticality taxonomy exists to protect judgment-critical moments from cost-driven delegation

The document proposes tiered dispatch for "certain agent types" but the current architecture (`phases/expansion.md` cross-model dispatch, `phases/launch.md` Step 2.0.5 routing_resolve_agents) routes model tier by `expansion_score` and `pressure_label` — signals about finding volume, not task nature. When implemented, a route like "cognitive agents go to cheaper models because they're non-technical" would send fd-systems (organizational dynamics analysis) and fd-decisions (decision-making pattern analysis) to DeepSeek or Qwen. These agents require strong natural language reasoning and cross-domain judgment that many cheaper models produce shallow or generic findings for.

Concrete failure: A review of an architectural decision document routes fd-decisions to DeepSeek because it's classified as "cognitive/non-technical." DeepSeek produces a finding about the document's decision structure that misses a subtle framing bias invisible to models not trained on organizational design literature. The synthesis phase accepts the finding, the user receives a "clean" verdict on a decision that Claude would have flagged.

Smallest viable fix: Before implementing OpenRouter routing, add an explicit agent capability taxonomy to `config/flux-drive/budget.yaml` or a new `config/flux-drive/agent-tiers.yaml`:
```yaml
judgment_critical:  # never route below sonnet, never to non-Claude
  - fd-safety
  - fd-correctness
  - fd-decisions  # requires nuanced organizational reasoning
standard_analytical:  # sonnet or strong non-Claude equivalent
  - fd-architecture
  - fd-systems
  - fd-resilience
mechanical_procedural:  # haiku or cheap non-Claude acceptable
  - fd-quality  # pattern scanning, style analysis
  - fd-performance  # mostly algorithmic complexity analysis
  - fd-perception  # checklist-style heuristic evaluation
```

The cross-model dispatch in `phases/expansion.md` Step 2.2c should consult `judgment_critical` before applying any tier adjustment, with an unconditional floor that overrides cost optimization.

**[P1-2]** Section: "OpenRouter integration / Constraints" — Routing dimension missing for qualitative capability profiles vs quantitative cost ratio

The document correctly identifies that "different model families have different training biases" but the only proposed routing signal is cost performance ratio ("10-50x lower cost"). There is no mechanism proposed to match model family strengths to agent task types. DeepSeek V3's strength in code reasoning makes it suitable for fd-correctness code analysis subtasks but weak for fd-people organizational dynamics. Qwen 2.5's strength in instruction following makes it suitable for checklist-style fd-quality reviews but potentially weaker for open-ended architectural analysis.

Concrete failure: OpenRouter integration routes all non-safety agents to the cheapest available model based on cost/performance ratio. fd-architecture (structural analysis requiring understanding of architectural tradeoffs) goes to a model strong at code but weak at systems reasoning. The finding output is technically correct but architecturally shallow — the model detects specific anti-patterns but misses the higher-order structural issue. The synthesis phase can't distinguish shallow-but-correct from deep-correct at the finding level.

Smallest viable fix: Add a `model_family_strengths` profile to the OpenRouter routing config:
```yaml
model_assignments:
  deepseek-v3:
    strong_agents: [fd-correctness, fd-performance]  # code reasoning strength
    weak_agents: [fd-people, fd-decisions]  # natural language nuance weakness
  qwen-2.5:
    strong_agents: [fd-quality, fd-user-product]  # instruction following
    weak_agents: [fd-architecture, fd-systems]  # open-ended reasoning
```

**[P2-3]** Section: "Cross-model dispatch / Budget system" — No feedback mechanism to detect cheap-model underperformance on delegated tasks

The `phases/expansion.md` logs `[tier-escalation] {agent} was downgraded but returned {severity} finding` — this is calibration data that a downgraded agent found something important. But there is no inverse: detecting when a cheap model was assigned a task and *failed* to find something that a higher-tier model would have caught. Without a baseline comparison mechanism (run the same agent at both tiers occasionally and compare finding sets), the calibration is asymmetric — it catches false downgrades but not false "the cheap model was fine" assumptions.

The garzone's learning trajectory (agent MUR-5 improvement) is the constructive framing of this gap: running cheap models on tasks and comparing against expensive-model baselines would build an empirical skill map. But even before that, the system needs to track when a cheap-model agent produced zero findings in a domain where Stage 1 found P0 issues — a signal that the cheap model may have missed something rather than genuinely found nothing.

Fix: In the cost report (Step 3.4b), add a `zero_finding_in_hot_domain` flag per cheap-model agent:
```json
{
  "name": "fd-quality",
  "model": "deepseek-v3",
  "findings": 0,
  "zero_in_hot_domain": true,  // Stage 1 found P1 in adjacent domain but this agent found nothing
  "escalation_candidate": true
}
```

**[P2-4]** Section: "Tiered dispatch / Budget system" — Per-type token budgets calibrated for Claude tiers only; cheap-model agents may underspend budget allocation while under-reviewing

The current `budget.yaml` has `agent_defaults` calibrated for Claude model behavior (response length, reasoning verbosity). A cheap model dispatched to the same agent type may produce much shorter outputs (fewer tokens) while also producing shallower findings. The budget system would record this as efficiency (under-budget), masking that the cheap model simply did less work rather than did equivalent work more efficiently.

Fix: Track `finding_density = findings_count / output_tokens` per agent per model tier. In the cost report, flag agents where `finding_density` is significantly below the baseline for that agent type — it may indicate the cheap model produced low-density output rather than genuinely clean code.

### Improvements

1. **P3** — Add an explicit agent tier taxonomy document (`config/flux-drive/agent-tiers.yaml`) that categorizes each agent by the reasoning capability it requires (judgment-critical, standard-analytical, mechanical-procedural) before implementing OpenRouter routing. This taxonomy should be the primary routing dimension, with cost optimization as a secondary signal within each tier's eligible model set.

2. **P3** — Design the calibration mechanism proposed in the document ("comparing cheap-model findings against expensive-model baselines") as a first-class feature: on every N-th review, shadow-run 1-2 cheap-model agents at their Claude equivalent tier and compare finding sets. The delta reveals whether the delegation is working or whether the garzone is producing pieces that crack under use.

3. **P3** — The trust multiplier (Step 2.1e) currently operates on agent identity. Extend it to operate on `(agent, model_tier)` pairs — so fd-quality at haiku and fd-quality at deepseek-v3 can accumulate separate trust histories, enabling the system to detect that a specific model-agent combination is systematically under-performing.

<!-- flux-drive:complete -->
