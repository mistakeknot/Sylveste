### Findings Index
- P1 | ONG-1 | "OpenRouter integration / Constraints" | No failure isolation design for external provider agents — a DeepSeek API timeout can block the synthesis phase's wait loop
- P1 | ONG-2 | "OpenRouter integration / Constraints" | All models will receive identical prompt templates designed for Claude's patterns — prompt monoculture suppresses the diversity that justifies multi-model dispatch
- P2 | ONG-3 | "Cross-model dispatch / Current Cost Model" | Context volume uniform across all agents regardless of task requirements — no porosity differentiation proposed
- P2 | ONG-4 | "Model diversity as a signal" | No mechanism to accommodate model version evolution — routing assumptions built for DeepSeek V3 will silently degrade when V4 ships
- P3 | ONG-5 | "OpenRouter integration / Constraints" | Output format requirements may suppress diverse model analytical styles — sand grain uniformity producing flat fermentation

Verdict: needs-changes

### Summary

The proposed OpenRouter integration in the document treats infrastructure as a solved problem and focuses primarily on the economic question (which models at what cost). But the onggi master knows that the vessel design is the primary quality lever — the potter cannot direct which microbes flourish, only shape the environmental conditions that allow or suppress diversity. The document's implementation constraints ("go through Bash tool API calls or MCP server") are correctly identified, but the design of those Bash calls — what context to send, how to handle failures, what output format to accept — will determine whether the multi-model fleet produces genuinely diverse collective intelligence or expensive homogeneity.

The two critical infrastructure gaps are failure isolation and prompt environment design. The current flux-drive pipeline (`phases/launch.md` Step 2.3) monitors agent completion via `flux-watch.sh` with a `TIMEOUT` parameter and retries incomplete agents with `run_in_background: false`. For Claude subagents via the Agent tool, this is straightforward — the Agent tool manages the process lifecycle. For OpenRouter agents dispatched via Bash tool API calls, the pipeline enters a fundamentally different failure domain: network timeouts, rate limits, API quota exhaustion, and JSON parse errors in the response are all possible failure modes that the current monitoring infrastructure was not designed for. A vessel with no walls provides no temperature buffering — a DeepSeek API error that takes 30 seconds to timeout during peak load will stall flux-watch.sh and delay every other agent's synthesis.

### Issues Found

**[P1-1]** Section: "OpenRouter integration / Constraints" — No failure isolation architecture for Bash-dispatched OpenRouter agents

The document states "Any non-Claude model integration would need to go through Bash tool (API calls) or MCP server." The current agent monitoring in `phases/launch.md` Step 2.3 uses `flux-watch.sh {OUTPUT_DIR} {N} {TIMEOUT}` which polls for `.md` files or uses inotifywait. For Claude subagents dispatched via Agent tool with `run_in_background: true`, the Agent tool manages process lifecycle independently. For Bash-dispatched OpenRouter agents, the Bash tool call itself must complete before the orchestrator regains control — a 60-second DeepSeek API timeout during Bash execution blocks the orchestrator for 60 seconds.

The failure modes of Bash-dispatched OpenRouter agents that the current pipeline does not handle:
1. **HTTP timeout**: OpenRouter returns a 504 after 30s → Bash call hangs for 30s, then returns an error. The output `.md.partial` file is never written. flux-watch.sh polls indefinitely until TIMEOUT.
2. **Rate limit**: OpenRouter returns 429 → Bash call completes quickly with an error response. The orchestrator must detect this, implement backoff, and retry — none of which the current retry logic (Step 2.3 "retry once with run_in_background: false") handles for API errors.
3. **Malformed JSON response**: The OpenRouter response parses incorrectly → the Bash script to extract the finding text fails. The output file contains raw JSON or an error, causing Step 3.1 validation to classify it as "Malformed."

Concrete failure: A review dispatches 4 agents: fd-architecture (Claude Sonnet), fd-quality (DeepSeek via Bash/OpenRouter), fd-systems (Claude Haiku), fd-correctness (Claude Sonnet). DeepSeek's API is experiencing elevated latency (not a failure, just slow). The Bash call for fd-quality runs for 45 seconds. flux-watch.sh is waiting for 4 `.md` files. The three Claude agents complete in 90 seconds, but flux-watch.sh keeps waiting because fd-quality hasn't written its output yet. The synthesis is delayed 45 seconds, and if the Bash call times out at the 60s Bash tool limit, fd-quality writes an error stub, contributing nothing to the synthesis despite the cost of the delayed wait.

Smallest viable fix: Wrap each OpenRouter Bash dispatch in a per-agent timeout with immediate error file writing:
```bash
# In the dispatch wrapper for OpenRouter agents:
timeout 30 curl -s https://openrouter.ai/api/v1/chat/completions \
  -H "Authorization: Bearer $OPENROUTER_API_KEY" \
  -d "$payload" > /tmp/openrouter-response-${agent}.json 2>&1 || {
    echo "<!-- flux-drive:complete -->" > "${OUTPUT_DIR}/${agent}.md"
    echo "Verdict: error" >> "${OUTPUT_DIR}/${agent}.md"
    echo "OpenRouter timeout or API error for ${agent}" >> "${OUTPUT_DIR}/${agent}.md"
    exit 0  # don't let the error propagate to stall flux-watch
}
```
The `timeout 30` ensures the Bash call completes within a bounded time. The error stub is written immediately in the failure case, keeping flux-watch.sh's file count correct. The 30-second cap is aggressive — adjust based on observed OpenRouter p95 latency — but guarantees bounded wait even under degraded conditions.

**[P1-2]** Section: "OpenRouter integration / Prompt design" — Uniform Claude-designed prompt templates will suppress multi-model analytical diversity

The document describes routing agents through Bash API calls. The prompt each model receives determines whether it contributes its distinctive analytical character or mimics Claude's response patterns. The `skills/flux-drive/references/prompt-template.md` prompt template is deeply Claude-specific: it uses Claude's preferred analytical framing, assumes Claude's discursive reasoning style, and includes output format requirements (`### Findings Index`, `Verdict:`, `<!-- flux-drive:complete -->`) that are natural for Claude but may be unusual constraints for models with different natural output structures.

Sending identical prompts to all models creates a prompt monoculture: every model is forced into the same analytical micro-environment, producing outputs that all look like Claude outputs but with varying quality. The diversity that justifies the multi-model fleet — "different model families have different training biases" — is suppressed by instructing all models to analyze identically. A vessel with uniform porosity everywhere produces flat, one-dimensional fermentation.

Concrete failure: DeepSeek V3 is dispatched as fd-correctness with the Claude-designed prompt that asks for structured analytical prose in the Findings Index format. DeepSeek's natural strength is producing precise code-level analysis with concrete references. Constrained to Claude's analytical framing, it produces a more discursive output that matches the format but does not leverage its strength in tracing specific code paths and their implications. The resulting finding is format-compliant but analytically shallower than DeepSeek's unconstrained output would have been — the vessel forces the microbes to behave like a different species.

Smallest viable fix: Create minimal per-family prompt variants that differ only in analytical framing while preserving required output structure:
```markdown
# config/flux-drive/model-prompts/deepseek-variant.md
[After the standard review task and document path:]
Focus on concrete code paths, specific function calls, and traceable execution flows.
For each finding, lead with: the specific code location, what it does, and why that is an issue.
[Output format requirements: identical to Claude template]
```
The required output format (Findings Index, severity labels, sentinel) stays identical across all variants — only the analytical framing guidance changes. This is the minimum-invasive change that allows each model's analytical terroir to shape its contributions without breaking the synthesis pipeline's parsing.

**[P2-3]** Section: "Cross-model dispatch / Context volume" — All agents receive uniform context regardless of task requirements; cheap models with smaller context windows may silently truncate

The document's constraint section mentions that OpenRouter dispatch would go through Bash API calls. Different model families have different context window sizes and performance characteristics at different context lengths. DeepSeek V3 has a large context window but its performance on long-context tasks may differ from Claude's. Qwen 2.5 variants have varying context sizes (7B vs 72B parameter models). The current flux-drive slicing system (`phases/slicing.md`) creates per-agent document slices for large inputs, but the slicing is designed around Claude's context utilization patterns.

A cheap model with a 32K context window receiving a full document plus system prompt plus output format instructions may silently truncate the document mid-way through. The finding output will be syntactically complete (the model continues from the truncation point), but will miss everything after the truncation boundary. There is no truncation detection in the current synthesis validation (Step 3.1 validates format, not content coverage).

Fix: When dispatching to OpenRouter models, add a context budget check before API dispatch:
```bash
estimated_tokens=$(echo "$prompt" | wc -w) * 1.3  # rough estimate
model_context_limit=$(jq -r ".models[\"$model\"].context_limit" config/flux-drive/openrouter-models.yaml)
if [ "$estimated_tokens" -gt "$((model_context_limit * 80 / 100))" ]; then
  # Force slicing to fit within 80% of model's context window
  use_aggressive_slicing=true
fi
```

**[P2-4]** Section: "Model diversity / OpenRouter integration" — Static model capability profiles will drift silently as model versions update

The document proposes routing specific agent types to specific model families based on their known strengths (DeepSeek V3 strong at code, Qwen 2.5 strong at instruction following). OpenRouter serves multiple model versions, and providers update models without always incrementing version numbers. A routing decision based on DeepSeek V3's capability profile may produce incorrect assignments when the underlying model is updated to V3.5 or V4 with a different capability distribution.

More specifically: DeepSeek R1 (reasoning model) and DeepSeek V3 (general chat) have very different capability profiles — one is explicitly designed for chain-of-thought reasoning tasks, the other for general completion. If the OpenRouter model identifier in the routing config refers to `deepseek/deepseek-chat` (which may be updated) rather than a pinned version like `deepseek/deepseek-chat:v3`, the routing assumptions can silently degrade.

Fix: Pin model versions in the routing config (`deepseek/deepseek-chat-v3` not `deepseek/deepseek-chat`) and add a periodic capability probe: monthly, run one standard review task against each configured model and compare output quality to the last known-good baseline. If quality degrades beyond a threshold, alert and revert to the previous pinned version.

### Improvements

1. **P3** — Design the OpenRouter dispatch infrastructure to accept and benefit from varied output formats. Rather than requiring all models to produce exact `### Findings Index` format, use a lightweight normalizer that maps various output formats (JSON findings list, numbered severity list, prose with headers) to the canonical format. This allows each model's natural output style to contribute analytical richness without breaking the synthesis pipeline.

2. **P3** — Add a `provider_health` check at the start of each review that includes OpenRouter agents: a quick probe request (single-sentence response) to each configured provider, with results cached for 5 minutes. If a provider is degraded, route those agent types to Claude equivalents rather than blocking or silently degrading the review.

3. **P3** — Consider MCP server integration as the preferred dispatch mechanism over Bash API calls. An MCP server for OpenRouter would enable the orchestrator to dispatch OpenRouter agents with the same `run_in_background: true` semantics as Claude subagents, avoiding the Bash tool timeout constraints entirely. This is a larger architectural investment but eliminates the failure isolation problem at the infrastructure level.

<!-- flux-drive:complete -->
