### Findings Index
- P0 | PQG-1 | "Constraints / Agent tool" | No gradient calibration between prompt complexity and model capability — steep gradient risk (hallucination erosion)
- P1 | PQG-2 | "Current Cost Model" | Mother well (token budget) has no physical weirs between model families — one provider can drain the entire supply
- P1 | PQG-3 | "Current Architecture / Budget system" | No vertical shafts (intermediate quality checkpoints) between OpenRouter dispatch and synthesis
- P2 | PQG-4 | "Question / OpenRouter integration" | Irreversible flow not acknowledged — once a non-Claude agent starts generating, no reclaim path exists
- P2 | PQG-5 | "Question / Chinese models on OpenRouter" | Multi-aquifer sourcing model unspecified — no routing policy for which quality characteristics to source from which model training lineage

Verdict: risky

---

## Agent: fd-persian-qanat-gradient-cascade

**Persona:** A muqanni (qanat engineer) who maintains a 2,700-year-old tradition of underground aqueduct construction, knowing that the gradient must be precisely calibrated — too steep causes erosion and collapse, too shallow causes siltation — and that branch qanats share a mother well with strictly allocated flow.

---

## Summary

The interflux OpenRouter integration question contains a critical unaddressed gradient problem. Qanats have survived millennia because gradient calibration is treated as a first-class engineering concern, not an afterthought. The current interflux design routes tasks to models based on tier labels (haiku/sonnet/opus) but has no mechanism for matching prompt complexity to model capability — the gradient equivalent. Adding OpenRouter models (DeepSeek, Qwen) without gradient calibration is not progressive enhancement; it is boring a new branch qanat from an uncalibrated mother well. The water will flow, but some channels will erode and some will silt.

---

## Findings

### P0 | PQG-1 | No gradient calibration between prompt complexity and model capability

**Location:** `input.md` § "Constraints" — "Agents are dispatched via Claude Code's Agent tool (subagents) which only supports Claude models natively. Any non-Claude model integration would need to go through Bash tool (API calls) or MCP server."

**Qanat diagnosis:** A qanat engineer calculates the slope of the channel against the terrain — too steep, and the water flow erodes the tunnel walls and collapses the qanat; too shallow, and sediment accumulates until flow stops. The "slope" in model dispatch is the ratio of task cognitive complexity to model capability. The current architecture dispatches agents to model tiers using a coarse expansion-score heuristic (P0→+3, P1→+2, domain affinity→+1). This heuristic does not measure the actual complexity gradient of the agent's task against the target model's capability.

**Failure scenario with OpenRouter integration:** An fd-architecture agent reviewing a 400-line multi-service architectural plan is dispatched to DeepSeek V3 (cost-optimized routing). The task complexity (architectural coherence across 5 services, 3 data stores, 2 external APIs) exceeds DeepSeek V3's capability for deep architectural reasoning on this specific structure. The agent produces confident-sounding findings that are architecturally incoherent — the gradient is too steep, the qanat erodes. These findings enter synthesis with the same weight as a Claude Opus finding on the same content. The synthesis cannot detect that the findings are erosion products (hallucinated structural analysis). The verdict is poisoned.

**Smallest viable fix:** Before routing any agent to a non-Claude model, add a gradient check to `skills/flux-drive/phases/launch.md`:
```
gradient_check(agent, model):
  task_complexity = agent.cognitive_operation_type  # gong/saron/gambang (see JGC-5)
  model_capability = model.tier  # structural/reference/coverage
  if task_complexity == "structural" and model.tier != "structural":
    return ROUTE_TO_CLAUDE  # gradient too steep for non-Claude
  if task_complexity == "coverage" and model.tier == "structural":
    return ROUTE_TO_OPENROUTER  # gradient appropriate for cheaper model
```

This is not a capability judgment on DeepSeek — it is a gradient calibration that routes coverage tasks (where the slope is gentle and the model capacity is ample) to cheaper models, and reserves structural tasks (where the slope is steep and model capacity is the constraint) for Claude.

---

### P1 | PQG-2 | Mother well has no physical weirs between model families

**Location:** `input.md` § "Current Cost Model" — "Budget system: Per-type token budgets, billing vs total tracking, budget-aware agent selection"

**Qanat diagnosis:** A qanat's mother well serves multiple branch channels. Without physical weirs (carved stone notches that allocate fixed proportions), one greedy branch will draw down the entire mother well, leaving others dry. The current interflux budget system tracks per-type token budgets but does not partition the budget between model families. When OpenRouter integration is added, the same token budget pool will serve both Claude agents and OpenRouter agents. Under budget pressure, the expansion scoring will route more agents to OpenRouter (cheaper per token). This is the greedy branch: cost pressure causes progressive concentration of spend in one channel, eventually depleting the structural-reasoning budget (Claude) even when it is needed.

**Failure scenario:** A review starts with budget=100K tokens (typical). Stage 1 runs 3 Claude agents (40K consumed). Budget pressure triggers. Stage 2 routes 4 agents to OpenRouter (8K tokens total, 90% savings). But 2 of those 4 agents are structural/gong-layer tasks that require Claude. The mother well (Claude allocation) has no physical weir — the routing algorithm drew from it without reservation. The structural analysis for Stage 2 is performed by models that cannot sustain the gradient. Result: synthesis produces a verdict that looks complete (6 agents, low token cost) but has structural analysis from models unsuited to the task.

**Smallest viable fix:** Add family budget partitioning to `config/flux-drive/budget.yaml`:
```yaml
budget:
  total_tokens: 200000
  partitions:
    claude:
      min_reserved: 60000  # physical weir — Claude structural budget cannot go below this
      agents: [gong_layer]
    openrouter:
      max_allocation: 80000  # prevents runaway cheaper-model spend
      agents: [gambang_layer]
```

The weir analogy is direct: `min_reserved` is carved stone — it cannot be overridden by downstream pressure.

---

### P1 | PQG-3 | No vertical shafts between OpenRouter dispatch and synthesis

**Location:** `input.md` § "Current Architecture" — "3-phase pipeline: Triage → Launch → Synthesize"

**Qanat diagnosis:** Long qanats have vertical shafts (kariz) at regular intervals. These serve two functions: inspection (a muqanni can descend to check flow quality and remove debris) and aeration (oxygen prevents anaerobic siltation). Without vertical shafts, debris accumulates silently until the qanat blocks completely. The interflux pipeline has a single quality checkpoint — synthesis — at the end of the flow. There is no intermediate inspection point between agent dispatch and synthesis.

**For OpenRouter specifically:** Non-Claude agents dispatched via Bash/MCP do not use Claude Code's Agent tool subagent completion contract. They produce raw text responses via HTTP. The current synthesis architecture (specs/core/synthesis.md §Step 1) validates the Findings Index format before processing — but this is a terminal inspection, not an intermediate shaft. If a DeepSeek agent produces plausible-looking output in a format that passes Findings Index validation but contains structurally incoherent findings, synthesis cannot detect this. The findings enter the pipeline and contaminate the verdict.

**Failure scenario:** DeepSeek V3 dispatched on a correctness review produces a Findings Index with 3 P1 findings that look syntactically valid but reference the wrong file:line (the model hallucinated line numbers from a similar but different codebase it was trained on). Synthesis accepts the findings as valid (format check passes), deduplication does not merge them (different file:line), convergence counts them as independent findings. The verdict: "needs-changes" with 3 P1s that don't exist.

**Smallest viable fix:** Add an intermediate quality checkpoint (vertical shaft) immediately after non-Claude agent completion, before findings enter the synthesis pipeline. Specifically in `skills/flux-drive/phases/launch.md` after each OpenRouter agent completes:
```
if agent.model_family == "openrouter":
  quick_validate(agent.output):
    - do referenced file:line positions exist in the actual input?
    - are severity labels within valid range (P0/P1/P2/P3)?
    - is finding count reasonable (flag >10 findings from a 50-line doc)?
  if validation_fails: mark as "needs_review" not "valid"
```

---

### P2 | PQG-4 | Irreversible flow not acknowledged in integration design

**Location:** `input.md` § "Question / OpenRouter integration"

**Qanat diagnosis:** Water in a qanat flows one direction. Once it has passed a junction, it cannot be reclaimed. The document discusses OpenRouter integration purely from a cost-optimization perspective but does not acknowledge that token spend on non-Claude models is irreversible in a specific sense: unlike Claude Code Agent tool subagents (which operate within the session context and can be retried, context can be reused), Bash/MCP HTTP calls to OpenRouter produce isolated completions. If a DeepSeek agent produces low-quality output, there is no "retry with better context" — the spend is gone, and the synthesis must proceed with bad findings or discard the entire agent's output.

**Impact:** The integration design needs an explicit policy for handling irreversible OpenRouter spend. Current retry logic (if any) assumes Claude Code agent semantics. OpenRouter HTTP calls need different retry semantics: fail-fast (no retry) or preflight validation (validate prompt before sending to prevent the steep-gradient scenario from PQG-1 reaching the irreversible dispatch point).

**Fix:** Add `retry_policy` to the OpenRouter dispatch configuration:
```yaml
openrouter:
  dispatch:
    retry_policy: none  # token spend is irreversible — no retry
    preflight_validation: gradient_check  # prevent bad dispatches before they happen
```

---

### P2 | PQG-5 | Multi-aquifer sourcing model unspecified

**Location:** `input.md` § "Question / Chinese models on OpenRouter" — "DeepSeek V3/R1, Qwen 2.5/3, Yi, etc."

**Qanat diagnosis:** Advanced qanat systems tap multiple distinct water tables (aquifers) at different depths, each with different water quality — some aquifers are softer (better for irrigation), some harder (better for drinking). A skilled muqanni knows which aquifer to tap for which purpose and does not mix incompatible water qualities without treatment. The document lists multiple Chinese model families (DeepSeek, Qwen, Yi) as interchangeable cost-efficient alternatives, but these models have meaningfully different training characteristics: DeepSeek R1 has explicit chain-of-thought reasoning; Qwen 2.5-Coder is optimized for code understanding; Yi is a general multilingual model. Treating them as equivalent "cheap model" options is mixing aquifers without understanding their distinct quality characteristics.

**Impact:** Agent type to model family matching matters. Dispatching a coverage-check agent (gambang layer) to Qwen-Coder is a better gradient match than dispatching it to Yi-general, because Qwen-Coder's aquifer (training data composition) is richer in the specific quality needed (code pattern recognition). The integration design should specify which model families are tapped for which task types.

**Fix:** Add model-family capability profiles to the OpenRouter routing configuration:
```yaml
openrouter_models:
  deepseek-r1:
    capability: reasoning_heavy  # tap this aquifer for complex analysis tasks
    density_layer: saron
  qwen-2.5-coder:
    capability: coverage_dense  # tap this aquifer for code coverage checks
    density_layer: gambang
  yi:
    capability: general_multilingual
    density_layer: gambang
```

---

## Decision Lens Assessment

Is the throughput gradient between orchestrator and model endpoints calibrated to prevent both overload (erosion) and starvation (siltation)?

**Current state:** No gradient calibration exists. The token budget has no physical weirs. There are no intermediate inspection shafts. The system will function for simple cases but will erode under complex structural analysis dispatched to gradient-mismatched models.

**Required state:** Gradient check before each non-Claude dispatch (PQG-1), family budget partitioning with weirs (PQG-2), post-dispatch quality shafts for OpenRouter output (PQG-3), acknowledgment of irreversible flow in retry policy (PQG-4), and aquifer-specific model routing (PQG-5).

The P0 (PQG-1) is the qanat engineering first principle: calibrate gradient before boring. Everything else is drainage infrastructure.
