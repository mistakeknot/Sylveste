### Findings Index
- P1 | AR-1 | "Constraints" | Parallel dispatch to OpenRouter will hit per-key rate limits — 6+ concurrent requests exceed typical free/mid-tier limits causing batch 429 failures
- P1 | AR-2 | "Current Architecture" | Timeout mismatch — OpenRouter latency variance is 3-10x higher than Claude Agent tool, flux-watch.sh 300s timeout may be insufficient
- P2 | AR-3 | "Current Cost Model" | Cost audit trail gap — interstat token recording assumes Claude JSONL format, OpenRouter usage data is in a different schema
- P2 | AR-4 | "Constraints" | Partial failure mode undefined — if 2/6 OpenRouter agents fail, does synthesis produce partial results or abort?
- P2 | AR-5 | "Question" | No circuit breaker — repeated OpenRouter failures should trigger automatic fallback to Claude-only, not retry indefinitely
Verdict: needs-changes

### Summary

Interflux currently operates in a single-failure-domain world: all agents run inside Claude Code's sandbox, and failures manifest as subagent timeouts or error stubs — both handled by existing retry logic. OpenRouter adds a second failure domain with fundamentally different characteristics: network-dependent latency, per-key rate limits, model-specific availability (DeepSeek may be up while Qwen is down), and provider-level outages. The document acknowledges "must be backward-compatible" but doesn't design the failure modes. The critical gap is that interflux's current monitoring contract (`flux-watch.sh` checking for `.md` files) doesn't distinguish between "agent still running" and "agent failed silently" — OpenRouter failures need explicit error signaling.

### Issues Found

AR-1. **P1: Rate limit batch failure.** OpenRouter's per-key rate limits vary by tier: free tier allows 20 requests/minute, paid tiers allow 200-500/minute. Interflux dispatches agents in parallel — if 6 agents are dispatched simultaneously to OpenRouter, the first few may succeed but later requests may get 429 responses. Unlike Claude's Agent tool (which has no user-facing rate limits in normal operation), OpenRouter 429s are expected during burst dispatch.

**Concrete scenario:** flux-drive launches 4 OpenRouter agents in parallel at T=0. OpenRouter's rate limiter allows 3, rejects the 4th with 429. If the dispatch wrapper doesn't retry with backoff, one agent produces no findings. flux-watch.sh waits for 4 `.md` files but only 3 appear. After 300s timeout, synthesis runs with 3/4 agents — silently missing one perspective.

**Smallest fix:** Implement request-level retry with exponential backoff (1s, 2s, 4s, max 3 retries) in the OpenRouter dispatch wrapper. Add a concurrency limiter: dispatch at most N=3 concurrent OpenRouter requests, queue the rest. This stays within typical rate limits while preserving parallelism.

AR-2. **P1: Timeout calibration.** `flux-watch.sh` uses a 300s (5 minute) timeout for Task-dispatched agents and 600s for Codex agents (shared-contracts.md line 112). OpenRouter's time-to-first-token for DeepSeek V3 varies from 2-30s depending on queue depth, and total generation for ~4K output tokens takes 15-60s. But during peak load, OpenRouter queues requests — a single agent dispatch can take 120-180s. If flux-drive dispatches 6 agents and OpenRouter queues them sequentially (due to rate limits), the last agent may not complete until 6 * 120s = 720s — exceeding the 300s timeout.

**Smallest fix:** Use a per-provider timeout config: `timeouts: {claude: 300, openrouter: 600}`. Alternatively, dispatch OpenRouter agents with staggered starts (0s, 5s, 10s) to reduce queue contention.

AR-3. **P2: Cost recording schema mismatch.** `token-count.py` (referenced in shared-contracts.md § Token Counting Contract) parses Claude subagent JSONL files to extract `input_tokens`, `output_tokens`, `cache_creation`, and `cache_read`. OpenRouter returns usage data in OpenAI format: `usage.prompt_tokens`, `usage.completion_tokens`, `usage.total_tokens` — no cache breakdown. The fields don't map 1:1, and the per-token cost is different. If OpenRouter usage isn't recorded, `interstat` cost estimates become progressively wrong as more agents route through OpenRouter — budget.yaml enforcement drifts from reality.

AR-4. **P2: Partial failure synthesis.** The synthesis phase (Step 3.0) verifies "N files (one per launched agent)." If an OpenRouter agent fails after retry exhaustion, the dispatch wrapper must write an error stub (shared-contracts.md § Error Stub Format) so synthesis can proceed with N-1 valid agents + 1 error. The current error stub format handles this — the gap is in the dispatch wrapper, which must guarantee that every dispatched agent produces either a findings file or an error stub, never nothing.

AR-5. **P2: No circuit breaker.** If OpenRouter experiences a sustained outage (>5 minutes), every OpenRouter-dispatched agent will fail and retry, consuming time without producing findings. A circuit breaker pattern would: (a) track failure count per provider in the current session, (b) after 3 consecutive failures, mark the provider as "down" for the remainder of the review, (c) fall back to Claude dispatch for remaining agents. This aligns with the progressive enhancement contract — OpenRouter is never required.

### Improvements

AR-I1. Add an `openrouter_health_check()` function that pings OpenRouter's `/api/v1/models` endpoint before dispatch. If it returns an error, skip OpenRouter dispatch entirely for this review — zero cost, zero risk.

AR-I2. Record OpenRouter dispatch outcomes (success/429/timeout/error) in a session-level log. After the review, report provider reliability alongside the cost report in Step 3.4b. This builds the operational data needed to calibrate timeouts and rate limits.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 5 (P0: 0, P1: 2, P2: 3)
SUMMARY: OpenRouter adds a network-dependent failure domain requiring request-level retry with backoff, per-provider timeout configuration, error stub guarantees, and a circuit breaker for sustained outages. The existing monitoring contract (flux-watch.sh) works if the dispatch wrapper guarantees one file per agent.
---
<!-- flux-drive:complete -->
