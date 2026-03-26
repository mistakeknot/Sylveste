# Blocked Items (convert to beads when Dolt recovers)

## Epic: Competitive Landscape — Close Clavain routing gaps vs LiteLLM/OpenRouter

- **Type**: feature (epic)
- **Priority**: P1
- **Created**: 2026-03-26
- **Context**: Local LLM optimization brainstorm (`docs/brainstorms/2026-03-26-local-llm-optimization-m5-max-brainstorm.md`)

Clavain's 4-track routing is more intelligent than LiteLLM (task-aware complexity, evidence calibration, safety floors) but lacks operational capabilities that proxy layers provide:

1. **Cost tracking & attribution** — Per-request cost, budget limits, usage attribution per user/tag
2. **Cloud provider fallback with retries** — model_fallbacks with automatic retry on failure
3. **Rate limit management** — Provider rate limit awareness with queuing and backpressure
4. **Unified API gateway** — Single endpoint abstracting all providers (local + cloud)
5. **Usage observability** — Token usage dashboards, cost trends, model utilization
6. **Privacy-aware routing** — Classification of sensitive vs public code for routing decisions

With interfere providing local model serving, Clavain needs these to route between local and cloud without an intermediate proxy.
