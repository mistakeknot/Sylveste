### Findings Index
- P1 | OD-1 | "Constraints" | Agent tool sandbox prevents direct HTTP dispatch — Bash-based curl is the only viable path, but stdout capture has token and timeout limits
- P1 | OD-2 | "Current Architecture" | Token accounting contract assumes single provider — budget.yaml cost_basis field has no provider dimension
- P2 | OD-3 | "Constraints" | Response format normalization gap — OpenRouter returns OpenAI-compatible JSON, not the Findings Index markdown contract
- P2 | OD-4 | "Current Cost Model" | Context window mismatch — prompt construction in launch.md calibrates slicing thresholds to Claude's 200K, DeepSeek V3/Qwen 2.5 are 128K
- P1 | OD-5 | "Constraints" | Progressive enhancement gate missing — no fallback path when OPENROUTER_API_KEY is unset or OpenRouter returns 5xx
Verdict: needs-changes

### Summary

The document correctly identifies the core constraint — Claude Code's Agent tool only dispatches Claude subagents natively — but underestimates the integration complexity of the Bash-tool dispatch path. The actual implementation requires solving five interdependent problems: HTTP dispatch lifecycle management (streaming vs blocking), response format normalization (OpenAI JSON to Findings Index markdown), token accounting across providers, context window-aware prompt construction, and graceful degradation. The MCP server path (mentioned but not explored) is architecturally cleaner than raw curl because it gets tool-level retry, timeout, and error propagation from Claude Code's MCP client.

### Issues Found

OD-1. **P1: Bash-tool HTTP dispatch has structural limitations.** The document proposes "Bash tool (API calls)" as the dispatch mechanism for OpenRouter, but doesn't address that Bash tool output is captured as a string and returned to the orchestrator's context. For a typical agent response (~8-15K tokens of generated text), this means the full OpenRouter response body lands in the orchestrator's context window — defeating the token efficiency goal. The Agent tool avoids this because subagent output goes to a file, not the host context. A Bash-tool dispatch would need to: (a) write response to a temp file, (b) return only a status line, (c) have the orchestrator read findings from the file. This exactly mirrors the `.md.partial` → `.md` contract in shared-contracts.md but requires building the write-to-file wrapper around curl.

**Concrete scenario:** Dispatching 4 agents via Bash curl with average 12K token responses = ~48K tokens dumped into orchestrator context. With a 200K context window and 9 agents total, this consumes 24% of context on raw response bodies that should never enter the host.

**Smallest fix:** An MCP server wrapper around OpenRouter's API that accepts a prompt and output path, writes the response to the path using the `.md.partial` → `.md` protocol, and returns only `{status: "complete", tokens: N}`. This preserves the existing monitoring contract from shared-contracts.md.

OD-2. **P1: Token accounting has no provider dimension.** `budget.yaml` tracks `cost_basis: billing` and `agent_defaults` in raw token counts, but nowhere distinguishes provider. When OpenRouter returns `usage.prompt_tokens` and `usage.completion_tokens`, these need to map to a cost model where DeepSeek V3 input = $0.27/M vs Claude Opus input = $15/M. The current `token-count.py` script (referenced in shared-contracts.md § Token Counting Contract) parses Claude subagent JSONL — it has no codepath for OpenRouter response JSON. Adding a provider field to the token tracking would require changes to: budget.yaml (per-provider rates), token-count.py (OpenRouter JSON parser), and the synthesis cost report (Step 3.4c).

OD-3. **P2: Response format normalization.** OpenRouter returns OpenAI-compatible chat completion JSON. Interflux agents produce markdown with a specific structure: `### Findings Index` → `### Summary` → `### Issues Found` → `### Improvements` → `<!-- flux-drive:complete -->`. When dispatching to OpenRouter, the orchestrator must: (a) construct the prompt to request this exact format, (b) extract the `content` field from the JSON response, (c) write it as `.md.partial`, (d) validate the Findings Index structure before renaming to `.md`. The synthesis phase (Step 3.1) already has validation for malformed output — the question is whether DeepSeek/Qwen reliably produce the Findings Index format (see fd-prompt-portability findings).

OD-4. **P2: Context window calibration.** The slicing thresholds in `phases/slicing.md` are implicitly calibrated for Claude's 200K context. DeepSeek V3 and Qwen 2.5 have 128K context windows. If an agent prompt (system prompt + document + review instructions) exceeds 128K, the model will either truncate or error. The current pipeline has no per-model context budget — `REVIEW_TOKENS` in Step 2.0.5 measures input size but doesn't compare against per-model limits. A per-model context ceiling check between prompt construction and dispatch would prevent silent truncation.

OD-5. **P1: No progressive enhancement gate.** The document states "OpenRouter integration should be a progressive enhancement, not a requirement" but doesn't describe the gate mechanism. Interflux already has this pattern — Exa MCP is optional (CLAUDE.md: "if `EXA_API_KEY` not set, agents fall back to Context7 + WebSearch"). The same pattern applies: check `OPENROUTER_API_KEY`, try dispatch, on failure fall back to Claude-only. But the failure modes are richer than Exa: OpenRouter can return partial responses, rate limit mid-batch, or have model-specific outages (DeepSeek available but Qwen down). The gate needs per-model health checking, not just per-provider.

### Improvements

OD-I1. Consider an `openrouter-dispatch` MCP server as the integration surface rather than raw Bash curl — it gets Claude Code's MCP client error handling, timeout management, and tool-level retry for free.

OD-I2. The existing `interserve` codex dispatch path (phases/launch-codex.md) is a closer architectural analogy than Bash curl — it dispatches to a different runtime (Codex CLI) with its own output format and reconciles results. Study that integration for patterns.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 5 (P0: 0, P1: 3, P2: 2)
SUMMARY: OpenRouter integration is feasible but requires an MCP server wrapper (not raw Bash curl), provider-aware token accounting in budget.yaml and token-count.py, per-model context window checks, and a multi-level progressive enhancement gate.
---
<!-- flux-drive:complete -->
