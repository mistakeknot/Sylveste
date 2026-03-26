# Flux Drive Research Synthesis

## Research Question
"Opportunities for improvements and closing gaps in the new routing architecture"

## Sources
- `docs/research/research-current-model-routing.md` (Internal, High Authority)
- `docs/research/heterogeneous-routing-results.md` (Internal, High Authority)

## Key Answer
The key opportunities for improving the new routing architecture involve addressing the lack of quality floors for safety-critical agents, transitioning from static to complexity-aware and adaptive routing, and unifying disconnected routing systems. 

## Findings

### 1. Missing Quality Floors for Safety-Critical Agents (P1 Priority)
Recent heterogeneous routing experiments revealed a critical quality risk: safety-critical agents are frequently running on weaker, cheaper models (e.g., `fd-safety` on Haiku 47% of the time, `fd-correctness` 26% of the time). 
**Improvement Opportunity:** Implement mandatory "safety floors" (e.g., `min_model: sonnet` or `min_model: opus`) in the routing configuration to ensure token-cost optimization does not degrade security and code correctness.

### 2. Lack of Complexity-Aware Routing (Track B2)
Currently, all tasks within a given phase use the same model tier, regardless of the task's actual difficulty. 
**Improvement Opportunity:** Develop "complexity-aware routing" that analyzes inputs like token count, reasoning requirements, and cross-file scope to dynamically select the appropriate model tier for each specific task. This should be implemented with a zero-cost abstraction and tested via shadow mode.

### 3. Interspect Outcome Data Not Driving Adaptive Routing (Track B3)
While the `interspect` system successfully collects evidence and outcome data (user corrections, quality signals, token spend), these insights are not yet automatically acting on the routing behavior.
**Improvement Opportunity:** Evolve the system to "Adaptive Routing" where this historical outcome data actively drives agent and model selection over time, creating a self-improving routing loop.

### 4. Fragmented Routing Systems
Clavain's model routing currently relies on three independent, static systems: Dispatch tiers for Codex, Agent frontmatter for Claude subagents, and Interspect overrides.
**Improvement Opportunity:** Unify dispatch tiers and subagent routing into a single declarative configuration (as envisioned in the B1 `config/routing.yaml` plan) that applies uniformly across all execution environments.

## Confidence
- **High confidence**: These findings are supported by quantitative data from 34 analyzed sessions and formalized roadmap tracks (Track B1, B2, B3).

## Gaps
- **Cognitive Agents Haiku Candidates**: While data suggests cognitive agents (like `fd-decisions`) could safely run on Haiku, there is currently insufficient data (e.g., only 1 run of `fd-decisions`) to confidently set this as a default. More data from checker-only reviews is needed.