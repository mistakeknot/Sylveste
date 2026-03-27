# fd-rl-training-pipeline: Hermes Agent RL Training Pipeline Review

**Reviewer:** fd-rl-training-pipeline (ML engineer specializing in RL from environment feedback)
**Date:** 2026-03-02
**Target:** `/home/mk/projects/Sylveste/research/hermes_agent/`
**Scope:** Adapting patterns for Sylveste's Autarch (L3 orchestration) and intercom (messaging/gateway)

---

## 1. Two-Phase Design: OpenAI Server (Phase 1) vs. ManagedServer/VLLM (Phase 2)

**Priority: P1**
**Files:** `environments/hermes_base_env.py:180-298`, `environments/agent_loop.py:115-453`

### Finding

`HermesAgentBaseEnv._use_managed_server()` (line 281) implements a clean server-type discriminator: if the first registered server is an `OpenAIServer` instance, Phase 1 direct chat-completion is used; otherwise Phase 2 (VLLM/SGLang via `/generate`) is used. The discriminator is a single `isinstance` check rather than a configuration flag.

Phase 1 uses `server.chat_completion()` directly with native `tool_calls` parsing. Phase 2 wraps the server in `managed_server()` context to capture exact token IDs and logprobs via `SequenceNode` state, enabling GRPO training. The fallback at line 497-513 catches `NotImplementedError` from `DummyManagedServer` and silently degrades to Phase 1 behavior.

`collect_trajectory()` (line 442-602) builds `ScoredDataItem` differently for each phase:
- **Phase 2:** Uses `nodes[-1]` (final `SequenceNode`) for real token/mask/logprob data
- **Phase 1:** Tokenizes the full conversation text with `self.tokenizer.encode()` to create approximate placeholder tokens (lines 585-596), explicitly flagged as not suitable for training but valid for SFT data gen and eval

### Autarch Relevance

Autarch currently uses Go with an L3 orchestration role, but is on a roadmap toward agent training. The two-phase pattern directly addresses the bootstrapping problem: you can run Phase 1 against any OpenAI-compatible provider (OpenRouter, Anthropic direct) to generate SFT data and test reward functions before a VLLM deployment exists. The `ScoredDataItem` placeholder token strategy means the same code path works for evaluation, data gen, and reward engineering without a separate code branch.

**Coupling concern:** The ManagedServer abstraction is fully Atropos-specific (`atroposlib.envs.server_handling`). Any Autarch training pipeline would need to either depend on Atropos or reimplement the `SequenceNode` token capture mechanism.

---

## 2. ToolContext Reward Function Pattern

**Priority: P0**
**Files:** `environments/tool_context.py:1-475`, `environments/hermes_base_env.py:541-549`

### Finding

`ToolContext` is the most directly portable abstraction in the codebase. It provides a per-rollout, session-scoped handle to all hermes-agent tools, keyed by `task_id`. The critical insight is at line 1-24 of `tool_context.py`:

> The same `task_id` means the terminal/browser session is the **same one** the model used during its rollout — all state (files, processes, browser tabs) is preserved.

This makes the reward function a first-class citizen in the environment rather than a post-hoc text scorer. The verifier can run `pytest` in the model's actual sandbox (lines 15-23 in the module docstring example), check filesystem state, navigate the browser to verify a web task, or download artifacts for local inspection.

`_run_tool_in_thread()` (lines 44-64) solves the asyncio nesting problem: when called from an async context (which `compute_reward` always is), it submits `handle_function_call` to a fresh single-thread `ThreadPoolExecutor` and blocks for the result. This is distinct from the agent loop's shared pool — the ToolContext creates a new 1-thread pool per call, which is safe but potentially slow under high verification load.

The `cleanup()` method (lines 440-474) performs ordered teardown: process registry, VM, browser. Each step is individually try-excepted so one failure doesn't prevent the others. The browser cleanup suppresses noisy debug prints via `HERMES_QUIET` env var (lines 464-474).

The base environment's `collect_trajectory()` (line 542-549) always calls `ctx.cleanup()` in a `finally` block, guaranteeing sandbox teardown even if `compute_reward` raises.

### Autarch/Intercom Relevance

For Autarch's training roadmap, the `ToolContext` pattern maps directly to a **VerifierContext** that could scope to an Intermute session or a Coldwine run. The verifier reusing the model's execution environment is a fundamentally better approach than extracting text answers — it gives binary ground truth from actual test execution rather than LLM-judged heuristics.

For intercom: if Autarch eventually trains on messaging tasks, the same sandbox-reuse pattern could verify that an agent's gateway call actually produced a delivered message, not just a plausible tool call.

**Hermes-specific coupling:** `ToolContext` directly imports from `model_tools`, `tools.terminal_tool`, `tools.browser_tool`, and `tools.process_registry` — all hermes-agent internal packages. The pattern is portable; the implementation is not.

---

## 3. Toolset Distribution Sampling as Implicit Curriculum

**Priority: P1**
**Files:** `toolset_distributions.py:1-365`, `environments/hermes_base_env.py:242-275`

### Finding

`sample_toolsets_from_distribution()` (line 247-288 of `toolset_distributions.py`) implements **independent Bernoulli sampling**: each tool has its own probability of inclusion, rolled independently per call. A rollout group might get `[terminal, file, web]` while another gets `[terminal, file]`. The fallback at lines 282-286 ensures at least one tool is always selected by picking the highest-probability toolset.

The 15 named distributions (lines 29-219) encode domain knowledge about task types. `terminal_tasks` gives terminal+file+web each 97% but image_gen only 10%. `science` gives browser 50% for paper access. `development` gives moa (mixture of agents) 60% for reasoning tools.

The critical architectural decision is **when** sampling occurs: `_resolve_tools_for_group()` is called once in `collect_trajectories()` (line 318) and the result is shared across all `collect_trajectory()` calls within the group (lines 453-458). All rollouts in a group see the same toolset. Different groups sample independently. This creates variance at the group level, not the trajectory level — which is what GRPO needs: within-group samples should be comparable (same toolset, same task), while between-group samples should be diverse.

`batch_runner.py` uses the same sampling per-prompt (line 304): each prompt in a batch gets its own `sample_toolsets_from_distribution()` call, giving trajectory-level diversity for SFT data gen.

### Autarch Relevance

This is a directly portable concept. Autarch currently has no concept of capability distributions for agent runs. A `PluginDistribution` for Autarch could specify per-plugin or per-MCP-tool probabilities that vary per training group, forcing the agent to develop strategies that don't over-rely on any single capability.

The named distribution approach is more legible and tunable than learned curriculum methods — a researcher can directly say "I want the agent to focus on terminal tasks 80% of the time" without understanding the training loop.

**Note:** The current implementation has no entropy tracking. It is impossible to know post-hoc whether a low-scoring rollout failed because the task was hard or because the sampled toolset was insufficient. Autarch should log the sampled distribution name and included tools in trajectory metadata.

---

## 4. HermesAgentEnvConfig: Environment-Agnostic Fields

**Priority: P2**
**File:** `environments/hermes_base_env.py:73-177`

### Finding

`HermesAgentEnvConfig` extends Atropos's `BaseEnvConfig` with 11 additional fields. Categorized by portability:

**Environment-agnostic (directly promotable):**
- `max_agent_turns: int = 30` — max LLM calls per rollout; universal concept
- `system_prompt: Optional[str] = None` — initial system message; universal
- `agent_temperature: float = 1.0` — sampling temperature; universal
- `tool_call_parser: str = "hermes"` — tool call parser name; universal with different registry
- `extra_body: Optional[Dict[str, Any]] = None` — pass-through to provider API; universal
- `tool_pool_size: int = 128` — concurrency setting; universal

**Partially hermes-coupled:**
- `enabled_toolsets / disabled_toolsets / distribution` — concept is universal, but the toolset names (`terminal`, `file`, `web`, `browser`, `vision`, `image_gen`, `moa`) are hermes-specific
- `dataset_name / dataset_split / prompt_field` — HuggingFace-specific; useful convention but not universal

**Terminal-backend-specific (hermes-specific):**
- `terminal_backend: str = "local"` — `local/docker/modal/ssh/singularity` backends are mini-swe-agent concepts
- `terminal_timeout: int = 120` — command timeout; only relevant with terminal tool
- `terminal_lifetime: int = 3600` — sandbox inactivity lifetime; only relevant with cloud sandboxes

### Autarch Relevance

The environment-agnostic fields form a clean minimal schema for an `AutarchTrainingConfig`. A straightforward Pydantic model could be extracted containing: `max_agent_turns`, `system_prompt`, `agent_temperature`, `tool_pool_size`, `max_token_length`, `group_size`, `total_steps`, and a `capability_distribution` field replacing hermes's `distribution`. This would give Autarch a training config baseline without depending on Atropos's `BaseEnvConfig`.

---

## 5. Thread Pool Executor Pattern for Async/Sync Bridging

**Priority: P1**
**Files:** `environments/agent_loop.py:25-43`, `environments/patches.py:1-189`, `environments/tool_context.py:40-64`

### Finding

The deadlock problem: Atropos runs an asyncio event loop. Many hermes tools (Modal, Docker, web_extract) use `asyncio.run()` internally. Nested `asyncio.run()` calls deadlock. Three complementary solutions are used:

**1. Shared thread pool in agent_loop.py (lines 25-43)**
Module-level `_tool_executor = ThreadPoolExecutor(max_workers=128)`. All non-todo, non-memory tool calls in `HermesAgentLoop.run()` are dispatched via `loop.run_in_executor(_tool_executor, lambda: handle_function_call(...))` (line 344). The pool is sized at startup based on `config.tool_pool_size`. `resize_tool_pool()` (line 34) replaces the global executor before any tasks run.

**2. Background event loop thread via `_AsyncWorker` in patches.py (lines 38-83)**
For `SwerexModalEnvironment` specifically, the Modal deployment requires all async operations (init, execute, stop) to run on the **same** event loop that started the gRPC connection. A dedicated background thread with `asyncio.run_forever()` is created per `SwerexModalEnvironment` instance. `run_coroutine_threadsafe()` bridges from any calling context. This is more heavyweight than a simple thread pool submit but necessary because of gRPC's event loop affinity requirement.

**3. Dynamic context detection in tool_context.py (lines 44-64)**
`_run_tool_in_thread()` checks `asyncio.get_running_loop()` at call time: if in an async context, submits to a new 1-worker pool; if not, calls directly. This is a defense-in-depth pattern rather than a primary solution.

The `resize_tool_pool()` function (agent_loop.py line 34) is called from `HermesAgentBaseEnv.__init__()` (line 230). This global mutation is a threading hazard if multiple environments are initialized concurrently — the second `__init__` would replace the pool while the first environment may be using it. In practice, Atropos initializes one environment per process, so this is safe, but the pattern should not be copied without that assumption.

### Autarch Relevance

Autarch is a Go application, which sidesteps Python asyncio issues entirely. However, if Autarch ever integrates with a Python training loop (e.g., via subprocess RPC to an Atropos worker), the `_AsyncWorker` background-thread pattern is the correct way to bridge async/sync boundaries in Python sidecars.

The more relevant lesson for Autarch is the **pool sizing discipline**: `tool_pool_size` must be set to at least the number of concurrent rollouts. The TerminalBench2 comment at line 28-29 of agent_loop.py is explicit: "89 TB2 eval tasks all making tool calls. Too small = thread pool starvation."

---

## 6. AgentResult Metadata as Trajectory Schema

**Priority: P1**
**File:** `environments/agent_loop.py:48-74`

### Finding

`AgentResult` (lines 59-74) is a dataclass with six fields:

```python
@dataclass
class AgentResult:
    messages: List[Dict[str, Any]]          # Full OpenAI-format conversation history
    managed_state: Optional[Dict[str, Any]] # SequenceNodes with tokens/logprobs (Phase 2 only)
    turns_used: int = 0                      # Number of LLM calls made
    finished_naturally: bool = False         # True if model stopped calling tools; False if hit max_turns
    reasoning_per_turn: List[Optional[str]] # Extracted <think>/reasoning_content per turn
    tool_errors: List[ToolError] = field(default_factory=list)  # Tool execution errors
```

`ToolError` (lines 49-57) captures: `turn`, `tool_name`, `arguments` (truncated), `error` (message), `tool_result` (raw response). This enables fine-grained reward shaping — a reward function can penalize trajectories with high `tool_errors` count or that `finished_naturally=False` (hit turn limit without natural completion).

`reasoning_per_turn` is populated by `_extract_reasoning_from_message()` (lines 77-112) which handles three provider formats: `reasoning_content` field (most), `reasoning` field (some), and `reasoning_details[].text` (OpenRouter). This multi-provider normalization is necessary because the field name is not standardized across providers.

`batch_runner.py` extends this schema in its output records (lines 349-364):
```python
{
    "success": bool,
    "trajectory": {...},
    "tool_stats": {tool_name: {count, success, failure}},
    "reasoning_stats": {total_assistant_turns, turns_with_reasoning, ...},
    "completed": bool,
    "partial": bool,
    "api_calls": int,
    "toolsets_used": List[str],
    "metadata": {batch_num, timestamp, model}
}
```

The `batch_runner.py` also discards samples with zero reasoning across all turns (lines 439-444):
```python
if not reasoning.get("has_any_reasoning", True):
    print(f"Prompt {prompt_index} discarded (no reasoning in any turn)")
```
This is an implicit quality filter baked into the data pipeline rather than the reward function.

### Autarch Relevance

`AgentResult`'s fields are the minimal sufficient metadata for a trajectory store. For Autarch's training roadmap, a `RunResult` schema should include at minimum:
- `turns_used` and `finished_naturally` (termination quality signals)
- `tool_errors` per turn (execution health)
- `reasoning_per_turn` normalized across providers (chain-of-thought preservation)
- `toolsets_used` or equivalent capability log (for distribution analysis)

The `finished_naturally` boolean is particularly useful as a cheap auxiliary reward signal: trajectories that hit `max_turns` are probably incomplete or stuck in loops. A negative auxiliary reward for `finished_naturally=False` can be added without any environment-specific logic.

The multi-provider reasoning normalization in `_extract_reasoning_from_message()` should be copied verbatim if Autarch ever routes through OpenRouter — the field inconsistency is a real operational problem.

---

## Adaptation Opportunities

The following concrete items are candidates for Autarch beads:

**1. VerifierContext abstraction (from ToolContext)**
Create an Autarch-side concept of a verifier context that reuses the agent's execution environment for reward computation. The interface: `verify(task_id, item) -> float`. Does not depend on hermes tooling — can wrap Intermute session state or Coldwine run state.
Blocked by: defining what "execution environment" means in Autarch's context.

**2. AutarchTrainingConfig schema (from HermesAgentEnvConfig)**
Extract the environment-agnostic config fields into a Pydantic model (or Go struct): `max_agent_turns`, `system_prompt`, `agent_temperature`, `tool_pool_size`, `max_token_length`, `group_size`, `total_steps`, `capability_distribution`. Usable as the base config type for any Autarch environment that wraps the agent loop.
No Hermes coupling. Can be done independently.

**3. CapabilityDistribution system (from toolset_distributions.py)**
Named distributions of MCP tools / Autarch plugins with per-tool inclusion probabilities. Sampled once per training group (not per rollout). Registry of named distributions that can be referenced from config. Include entropy logging: record which distribution was sampled and which tools were included in trajectory metadata.
No Hermes coupling. Directly portable concept.

**4. AgentRunResult trajectory schema (from AgentResult + batch_runner output)**
Standardize a trajectory record schema for Autarch: `turns_used`, `finished_naturally`, `tool_errors[]`, `reasoning_per_turn[]`, `capability_snapshot` (what tools were available), `messages[]`. Add `finished_naturally` as an auxiliary reward signal in training configs.
No Hermes coupling. Can inform intercom's message envelope schema if intercom needs to surface agent run metadata.

**5. Two-phase training path (from HermesAgentBaseEnv Phase 1/2)**
Adopt the same incremental approach for Autarch training: Phase 1 uses OpenAI-compatible providers (Anthropic API) for SFT data gen and reward function development; Phase 2 introduces VLLM for GRPO. The Phase 1 placeholder-token strategy enables reward function iteration without a VLLM cluster. This is a roadmap pattern, not a specific bead, but should be reflected in Autarch's training roadmap doc.

**6. Thread pool sizing doctrine (from agent_loop.py and terminalbench2_env.py)**
Document the rule: thread pool size must equal or exceed max concurrent rollouts. The TB2 environment's explicit 128-worker pool comment is the canonical reference. Any Autarch training environment should expose `tool_pool_size` as a first-class config knob and document the sizing rule.

---

## Hermes-Specific Coupling — Do Not Port Directly

The following patterns are tightly coupled to hermes infrastructure and should not be ported directly:

- `apply_patches()` / `_AsyncWorker` — patches `SwerexModalEnvironment` specifically; Modal + SWE-ReX are hermes dependencies
- `ToolContext.cleanup()` calling `cleanup_vm()` and `cleanup_browser()` — these are hermes-specific process/VM lifecycle methods
- `tool_call_parser` / `get_parser()` registry — the Hermes/Mistral/Llama3 tool call parsing variants are specific to VLLM's raw generation output format; not relevant unless Autarch uses `/generate` directly
- `_extract_base64_tar()` and per-task Docker image registration in TerminalBench2 — TB2-specific task format
- `register_task_env_overrides()` — mini-swe-agent terminal backend concept

---

## Summary Table

| Area | Finding | Priority | Portability |
|------|---------|----------|-------------|
| Two-phase server design | Phase 1 (OpenAI) → Phase 2 (VLLM) incremental path | P1 | Concept portable; Atropos coupling for Phase 2 |
| ToolContext reward pattern | Sandbox reuse for verification; `task_id` scoped verifier | P0 | Concept portable; implementation hermes-specific |
| Distribution sampling | Per-group Bernoulli toolset sampling as curriculum | P1 | Fully portable; no hermes coupling |
| EnvConfig fields | 6 of 11 config fields are environment-agnostic | P2 | Directly portable to AutarchTrainingConfig |
| Thread pool pattern | `run_in_executor` + sized pool for async/sync bridging | P1 | Pattern portable; Python-specific concern |
| AgentResult schema | 6-field trajectory metadata with ToolError records | P1 | Fully portable; schema can be adopted verbatim |
