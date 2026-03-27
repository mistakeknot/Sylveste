# fd-mini-swe-agent: Hermes Agent Code Review

**Reviewer agent:** fd-mini-swe-agent
**Date:** 2026-03-02
**Target:** `research/hermes_agent/` — execution backend interface, trajectory normalization, batch pipeline
**Decision lens:** Execution backend contracts, trajectory format normalization, batch pipeline design
**Out of scope:** Atropos base env internals (fd-rl-training-pipeline), terminal security isolation (fd-security-patterns), platform message delivery (fd-gateway-messaging)

## 1. create_environment() Factory — Backend Unification

**File:** `research/hermes_agent/mini_swe_runner.py:104-137`

### Findings

**[P0] Minimal execute() contract is implicit, not enforced.**
`create_environment()` returns three different concrete types (`LocalEnvironment`, `DockerEnvironment`, `SwerexModalEnvironment`) without a shared base class or protocol. The caller always calls `.execute(command, timeout=...)` and expects `{"output": str, "returncode": int}` back, but this contract exists only in the caller's wrapper at `mini_swe_runner.py:270-281`. There is no ABC or `Protocol` defining it. Adding a fourth backend (e.g., SSH, Kubernetes) requires knowing this implicit contract by reading existing callers, not from the type system.

```python
# mini_swe_runner.py:255-281
def _execute_command(self, command: str, timeout: int = None) -> Dict[str, Any]:
    result = self.env.execute(command, timeout=timeout or self.command_timeout)
    return {
        "output": result.get("output", ""),       # normalized here
        "exit_code": result.get("returncode", 0), # key rename happens here
        "error": None
    }
```

The `returncode` to `exit_code` rename happening silently inside this wrapper is the only place that normalizes the key mismatch between `SwerexModalEnvironment.execute()` (which returns `returncode`) and the rest of the caller code (which uses `exit_code`).

**[P1] Cleanup interface is also implicit and dual-named.**
`_cleanup_env()` at `mini_swe_runner.py:246-253` probes for either `cleanup` or `stop` to handle the fact that different backends use different teardown method names. This duck-typing works but is fragile: a new backend that uses `close()` or `teardown()` would silently skip cleanup.

**[P1] `env_type` string dispatching with no exhaustiveness check.**
The factory raises `ValueError` for unknown types (`mini_swe_runner.py:136-137`), which is correct, but the dispatch is a plain if/elif chain. There is no registry or enum, so refactoring (renaming `"modal"` to `"swerex"`) requires grep-based tracking. The string `"modal"` appears in config fields, CLI flags, system prompt examples, and the factory — all independently.

**[P2] `batch_runner.py` has a parallel and richer version of the same pattern.**
`_process_single_prompt()` at `batch_runner.py:253-298` builds environment overrides through `register_task_env_overrides()` (a task-ID-keyed dict in `terminal_tool.py`). This is the production path; `create_environment()` in `mini_swe_runner.py` is a simpler standalone version. The two patterns are not unified. Autarch should pick one.

### Adaptation opportunities for Sylveste

The backend contract is: `execute(command, timeout) -> {"output": str, "returncode": int}` plus one of `{cleanup, stop}` for teardown. This is the minimal interface Autarch needs if it wants to add its own execution backends. A `Protocol` with `execute()` and `teardown()` is the right shape.

---

## 2. MINI_SWE_AGENT_FINAL_OUTPUT Sentinel — Completion Detection

**Files:** `research/hermes_agent/mini_swe_runner.py:80-82`, `mini_swe_runner.py:513-516`, `mini_swe_runner.py:527-530`; `research/hermes_agent/environments/agent_loop.py:408-431`

### Findings

**[P0] Two competing completion detection strategies coexist in the same codebase, and they behave differently.**

`MiniSWERunner.run_task()` (the standalone CLI runner) uses stdout scanning: it checks whether `"MINI_SWE_AGENT_FINAL_OUTPUT"` appears in the terminal tool's output (`mini_swe_runner.py:514`). When detected, it sets `completed = True` and breaks the iteration loop immediately, without waiting for another API call.

`HermesAgentLoop.run()` (the Atropos RL training path) uses tool_calls cessation: it stops when `assistant_msg.tool_calls` is falsy (`agent_loop.py:408`). The sentinel string is never checked inside the Atropos path. Whether the agent echoed `MINI_SWE_AGENT_FINAL_OUTPUT` is irrelevant there — only the structural absence of tool_calls matters.

```python
# mini_swe_runner.py:513-516 — stdout scanning path
if "MINI_SWE_AGENT_FINAL_OUTPUT" in result["output"]:
    print(f"   Task completion signal detected!")
    completed = True

# agent_loop.py:408-431 — tool_calls cessation path
else:
    # No tool calls -- model is done
    msg_dict = {"role": "assistant", "content": assistant_msg.content or ""}
    ...
    return AgentResult(..., finished_naturally=True, ...)
```

**[P1] The sentinel is embedded in the tool description, not in the reward function.**
`TERMINAL_TOOL_DEFINITION` at `mini_swe_runner.py:80-82` includes `echo "MINI_SWE_AGENT_FINAL_OUTPUT"` in the tool description text. This means the model learns the completion signal through natural language instruction, not through a structured mechanism. If the tool description is changed or truncated, the sentinel disappears from the model's context.

**[P1] Sentinel detection happens on tool result, not on assistant message.**
The check at `mini_swe_runner.py:514` fires after the terminal command runs and returns its output — inside the tool-result processing loop. The model is not given a chance to write a closing summary turn. Compare with tool_calls cessation: the model explicitly produces a final assistant message with no tool_calls, which becomes the summary turn in the trajectory.

**[P2] `AgentResult.finished_naturally` is the clean analogue.**
`agent_loop.py:69-70` marks `finished_naturally=True` only when the model produces a turn with no tool_calls. This boolean is available to `compute_reward()` and is more semantically precise than the sentinel. Downstream reward functions in `hermes_swe_env.py` and `terminalbench2_env.py` do not use it (they run explicit test verification instead), but it is available.

### Adaptation opportunities for Sylveste

For Autarch's batch evaluation pipeline, `finished_naturally` from `AgentResult` is the right completion signal — it does not require cooperation from the model. The stdout sentinel is useful only if running a model that does not natively support tool_calls cessation (e.g., a fine-tuned model that was trained to echo a signal). Autarch should standardize on `finished_naturally` and treat `MINI_SWE_AGENT_FINAL_OUTPUT` as a legacy fallback.

---

## 3. _convert_to_hermes_format() — Trajectory Bridge

**File:** `research/hermes_agent/mini_swe_runner.py:296-403`

### Findings

**[P0] The bridge is not lossless for multi-tool-call turns.**
When an assistant message contains multiple tool_calls (parallel tool use), all corresponding tool responses are collected and written as a single `{"from": "tool", "value": "\n".join(tool_responses)}` entry (`mini_swe_runner.py:387`). The OpenAI format stores each tool response as a separate message with its own `tool_call_id`. Collapsing them into a single joined string discards per-call identity. Replay from ShareGPT format back to OpenAI format would need to parse the XML to re-separate them, which is lossy if tool result content itself contains `</tool_response>` substrings.

```python
# mini_swe_runner.py:385-388
if tool_responses:
    trajectory.append({"from": "tool", "value": "\n".join(tool_responses)})
    i = j - 1
```

**[P0] Tool name assignment for multi-tool turns uses index-based lookup that can go out of bounds silently.**
At `mini_swe_runner.py:377-379`, the name for each tool response is looked up as `msg["tool_calls"][len(tool_responses)]["function"]["name"]`. If the number of tool-response messages collected exceeds the number of tool_calls in the assistant message, the fallback is `"unknown"`. This is a silent data corruption — the trajectory XML will contain `"name": "unknown"` entries.

```python
# mini_swe_runner.py:376-382
tool_response = f"<tool_response>\n"
tool_response += json.dumps({
    "tool_call_id": tool_msg.get("tool_call_id", ""),
    "name": msg["tool_calls"][len(tool_responses)]["function"]["name"] \
        if len(tool_responses) < len(msg["tool_calls"]) else "unknown",
    "content": tool_content
}, ensure_ascii=False)
```

**[P1] `json.dumps` serializes the tool call dict inside XML-like tags that are not real XML.**
`mini_swe_runner.py:353-357` dumps the tool call as JSON inside `<tool_call>...</tool_call>`. The JSON uses double-quotes. There is no escaping of characters that would break XML parsing (e.g., if `arguments` contains `<` or `>`). The format is ShareGPT convention, not actual XML, so parsers must treat it as a text format, not parse it with a standard XML library.

**[P1] `reasoning` is preserved but the field name is not standardized across providers.**
At `mini_swe_runner.py:338-340`, reasoning content is wrapped in `<think>...</think>` tags. The source field is `msg.get("reasoning")` — matching only one provider format — while `agent_loop.py:77-112` handles three provider formats (`reasoning_content`, `reasoning`, `reasoning_details[].text`). The conversion function does not benefit from the broader extraction logic.

**[P2] System message is always regenerated from current tool definitions.**
The conversion function regenerates the system message inline (`mini_swe_runner.py:309-325`), which means the stored trajectory's system message always reflects tool definitions at conversion time, not at execution time. If tools change between execution and conversion, the trajectory is internally inconsistent.

**[P2] Two independent conversion functions exist in parallel.**
`batch_runner.py:343-347` calls `agent._convert_to_trajectory_format()` from `run_agent.py` (AIAgent class), while `mini_swe_runner.py` has its own `_convert_to_hermes_format()`. Whether they produce identical output for the same input is not validated anywhere in the codebase.

### Adaptation opportunities for Sylveste

The lossless-ness problem on multi-tool turns is the most important finding for Autarch. Any trajectory compression or replay pipeline that consumes ShareGPT format must handle this. The safest approach: store the original OpenAI-format messages alongside the ShareGPT conversion, use OpenAI format as the source of truth, and treat ShareGPT as a display/training format only.

---

## 4. run_batch() Design — Immediate JSONL Flush

**Files:** `research/hermes_agent/mini_swe_runner.py:564-614`; `research/hermes_agent/batch_runner.py:385-508`

### Findings

**[P1] `MiniSWERunner.run_batch()` flushes immediately but has no checkpoint/resume.**
`mini_swe_runner.py:594-596` opens the output file in `'w'` mode and writes + flushes after each task. If the process crashes mid-batch, completed entries are preserved. However, on resume, the entire file is rewritten from scratch — completed tasks are re-run. There is no tracking of which prompt indices were already completed.

```python
# mini_swe_runner.py:584-596
with open(output_file, 'w', encoding='utf-8') as f:
    for i, prompt in enumerate(prompts, 1):
        try:
            result = self.run_task(prompt)
            results.append(result)
            f.write(json.dumps(result, ensure_ascii=False) + "\n")
            f.flush()
```

**[P0] `BatchRunner` in `batch_runner.py` has the production-grade design: checkpointing, multiprocessing, per-batch JSONL files, resume logic.**
`batch_runner.py:667-693` maintains a `checkpoint.json` file that tracks which `prompt_index` values have been completed. On resume (`--resume` flag), already-completed indices are skipped (`batch_runner.py:403-417`). Each batch writes to its own `batch_N.jsonl` file (`batch_runner.py:401`), merged at the end. This design is crash-safe at the per-task granularity.

**[P1] Error isolation is task-scoped in both implementations.**
`mini_swe_runner.py:600-611` catches all exceptions from `run_task()` and writes an error record with `"completed": False` and `"conversations": []` before continuing. `batch_runner.py:366-382` does the same. Neither lets an individual task failure abort the batch. This is the correct behavior for batch assessment.

**[P1] `batch_runner.py` has a silent discard policy for samples with no reasoning.**
`batch_runner.py:439-444` discards any trajectory where `reasoning_stats["has_any_reasoning"]` is False, printing a message but writing nothing to the output file and not incrementing `completed_prompts`. The discarded sample will be re-attempted on resume (intentional — it might produce reasoning on retry with a different sampled toolset), but this affects throughput measurement.

**[P2] `BatchRunner` uses `multiprocessing.Pool` for parallelism; each worker runs prompts sequentially within its batch.**
`batch_runner.py:385` processes prompts serially inside a batch. Parallelism comes from multiple batches running in separate processes (`num_workers` at the pool level). If one prompt hangs, it blocks all subsequent prompts in the same batch.

**[P2] Statistics schema normalization is tied to `TOOL_TO_TOOLSET_MAP`.**
`batch_runner.py:53`, `batch_runner.py:59-86` normalize tool stats to include all tools from the master map, ensuring consistent HuggingFace Arrow schema. Adding a new tool to `model_tools.py` silently changes the schema of output JSONL files, which can break downstream dataset loading if not handled.

### Adaptation opportunities for Sylveste

For Autarch's batch assessment pipeline, the `BatchRunner` design is the production pattern to adopt: per-task JSONL append with `flush()`, checkpoint file tracking completed indices, multiprocessing at the batch level. The `MiniSWERunner.run_batch()` is a simpler reference only. The immediate-flush pattern is the key durability primitive — Autarch's runner should adopt this unconditionally.

---

## 5. patches.py — Async-Safe Workaround for SwerexModalEnvironment

**File:** `research/hermes_agent/environments/patches.py:1-188`

### Findings

**[P0] The root cause being patched around is `asyncio.run()` called inside an already-running event loop.**
Atropos runs everything under a single asyncio event loop. `SwerexModalEnvironment.__init__` and `.execute()` internally call `asyncio.run()`, which raises `RuntimeError: This event loop is already running` when called from inside Atropos's loop. The patch replaces all three methods (`__init__`, `execute`, `stop`) with versions that dispatch to a dedicated background thread with its own `asyncio.new_event_loop()`.

**[P0] The patch is applied unconditionally at import time, even in non-Atropos CLI usage.**
`hermes_base_env.py:47-48` calls `apply_patches()` at import time. `patches.py:174-188` states this is safe for CLI use because the behavior is identical when no event loop is running. This is true today, but only because `_AsyncWorker` uses `asyncio.run_coroutine_threadsafe()` which works in any context. If Modal changes its deployment startup to use event loop local storage or context vars that are not thread-safe, the patch would silently misbehave.

**[P1] `_AsyncWorker` has no backpressure on `run_coroutine()`.**
`patches.py:65-75` calls `future.result(timeout=600)` — a 10-minute timeout is the only safety valve. If Modal deployment startup hangs (cloud provider outage), the calling thread blocks for 10 minutes before raising. In Atropos's context, this blocks a thread pool slot consumed by `loop.run_in_executor()` from `agent_loop.py:344`.

**[P1] The patch applies only to `SwerexModalEnvironment`, not to other potential culprits.**
`patches.py` docstring identifies `web_extract` as another tool with the same problem. `web_extract` is handled differently: `agent_loop.py:340-350` wraps all tool calls (except `todo` and two disabled tools) in `loop.run_in_executor(_tool_executor, ...)`, giving each tool its own clean thread. This is the more general solution. The Modal patch is belt-and-suspenders for the specific case where Modal's gRPC channels must be created on the same thread as the loop they run on.

**[P2] `_patches_applied` is a module-level boolean, not thread-safe.**
`patches.py:35, 174-188` use `global _patches_applied` with a simple check-and-set. In a multithreaded environment where `apply_patches()` could be called simultaneously from multiple threads, there is a race where both threads see `_patches_applied = False` and both apply the patches. In practice this is harmless (both patches are identical), but it is not safe by construction.

### Adaptation opportunities for Sylveste

The `_AsyncWorker` pattern (background thread with dedicated event loop, `run_coroutine_threadsafe` for bridging) is the right primitive for any Autarch component that needs to call async backends from synchronous tool dispatch code. The pattern is clean enough to extract as a standalone utility class, applicable to any Autarch execution module that bridges sync plugin APIs with an async agent loop.

---

## 6. TerminalBench2EvalEnv and HermesSweEnv — Concrete Subclass Interface

**Files:** `research/hermes_agent/environments/benchmarks/terminalbench_2/terminalbench2_env.py`; `research/hermes_agent/environments/hermes_swe_env/hermes_swe_env.py`; `research/hermes_agent/environments/terminal_test_env/terminal_test_env.py`

### Findings

**[P0] The minimal interface for a new SWE environment is five methods, but one is never called in assessment-only mode.**
`HermesAgentBaseEnv` declares five abstract methods: `setup()`, `get_next_item()`, `format_prompt()`, `compute_reward()`, `evaluate()`. `TerminalBench2EvalEnv` stubs three of them (`get_next_item`, `format_prompt`, `compute_reward`) because the assessment subcommand calls `setup()` and `evaluate()` directly, bypassing the Atropos training pipeline entirely (`terminalbench2_env.py:318-336`). This means a purely assessment-oriented environment must still implement the training-pipeline methods as stubs. This is a leaky abstraction.

**[P1] `TerminalBench2EvalEnv` reimplements streaming JSONL flush inside `setup()`.**
`terminalbench2_env.py:293-297` opens a timestamped JSONL file and stores `_streaming_file` and `_streaming_lock` on `self`. The flush at `_save_result()` (`terminalbench2_env.py:303-309`) is structurally identical to `MiniSWERunner.run_batch()`. This is a third independent implementation of the same "write and flush after each task" pattern.

**[P1] Per-task image override uses `register_task_env_overrides()` — a process-global mutable dict keyed by task_id.**
`terminalbench2_env.py:433` calls `register_task_env_overrides(task_id, {"modal_image": modal_image})`. At teardown, `clear_task_env_overrides(task_id)` removes the entry (`terminalbench2_env.py:523`). This works correctly for concurrent tasks (each has a unique task_id UUID) but is fragile: if `rollout_and_score_eval()` raises before reaching `clear_task_env_overrides()`, the entry leaks in the global dict. The `finally` block at `terminalbench2_env.py:521-529` mitigates this, but there is still a window during `asyncio.wait_for()` timeout where the `finally` may not run if the coroutine is cancelled before reaching it.

**[P2] `HermesSweEnv` is the cleanest reference implementation for a training-capable subclass.**
`hermes_swe_env.py:62-229` implements all five abstract methods in approximately 170 lines (excluding config). It is the recommended starting point for a new training environment. The key pattern: `compute_reward()` receives a `ToolContext` scoped to the rollout's `task_id` and can call any tool against the model's sandbox. The sandbox state (files, processes) from the agent's tool calls is preserved until `ctx.cleanup()` runs in the base class `finally` block.

**[P2] `TerminalTestEnv` is the integration smoke test — it has no external dependencies.**
`terminal_test_env.py:58-82` defines three training tasks inline (no HuggingFace dataset). This makes it the fastest way to validate that the full stack (agent loop to tool execution to reward computation to Atropos pipeline) is wired correctly. A Sylveste equivalent would be valuable as a smoke test for Autarch's harness.

---

## Cross-Cutting Observations

**[P1] `task_id` UUID is the key architectural primitive for session isolation.**
Across all components (`agent_loop.py:160`, `terminalbench2_env.py:414`, `batch_runner.py:250`, `tool_context.py:76`), `task_id = str(uuid.uuid4())` is generated per task and passed through the entire stack. Terminal backends use it to route commands to the correct sandbox. Browsers use it to select the correct browser session. This is the correct design for concurrent execution and the pattern Autarch should adopt for task isolation.

**[P1] Tool error tracking is split between agent-level and environment-level.**
`AgentResult.tool_errors` (`agent_loop.py:74`) records structured tool errors per turn during the agent loop. `HermesAgentBaseEnv._tool_error_buffer` (`hermes_base_env.py:233, 551-560`) copies these into a separate buffer for wandb logging. Two consumers, two representations. Any Autarch dashboard should decide on one canonical location.

**[P2] Phase 1 / Phase 2 duality adds branching to `collect_trajectory()`.**
`hermes_base_env.py:468-526` has three branches: Phase 2 (ManagedServer), Phase 2 fallback to Phase 1 (NotImplementedError on DummyManagedServer), and Phase 1 direct. In production Autarch usage, only one phase will be active — the branching adds dead code surface.

---

## Assumptions That Would Break With New Backends

1. **The `execute()` return dict uses `"returncode"` as the key for exit status (swerex/mini-swe-agent convention), but the rest of Hermes uses `"exit_code"`.** Any new backend that follows the Hermes convention directly, without going through `_execute_command()`'s normalization layer, will send `"returncode"` upstream and cause silent bugs.

2. **All completion detection in `HermesAgentLoop` assumes the OpenAI spec: `response.choices[0].message.tool_calls` is either a non-empty list or falsy.** A backend that returns tool calls as a string (raw XML without structured parsing) would always appear as "model finished naturally" even if it was calling tools.

3. **`register_task_env_overrides()` uses a process-global dict.** Any backend deployment that spawns isolated worker processes per task (e.g., Kubernetes pods) would break this — the override dict would not be visible in the pod running the terminal tool.

4. **`_AsyncWorker` pins Modal's async gRPC channels to a specific background thread's event loop.** If Modal changes to an architecture where gRPC channels are bound to a specific asyncio loop by context var rather than by thread identity, the patch would stop working silently.

---

## Adaptation Opportunities for Autarch Beads

The following are concrete items representing transferable patterns. Each is scoped to a single well-defined deliverable.

| Priority | Item | Description | Source Reference |
|---|---|---|---|
| P0 | Define `ExecutionBackend` Protocol | A `Protocol` (or ABC) with `execute(command, timeout) -> dict`, `teardown()`, and optional `is_available() -> bool`. Enforce this contract for all Autarch execution backends. | `mini_swe_runner.py:104-137` |
| P0 | Standardize trajectory serialization | Pick one canonical format (OpenAI messages or ShareGPT) as source of truth. Fix the multi-tool-call collapse bug before adopting for Autarch training data. Validate round-trip fidelity. | `mini_swe_runner.py:296-403` |
| P1 | Port `_AsyncWorker` as a shared utility | Extract `_AsyncWorker` from `patches.py:38-82` into a standalone `async_worker.py` in Autarch's runtime utilities. Required for any Autarch component that bridges sync plugin dispatch with async agent loops. | `environments/patches.py:38-82` |
| P1 | Adopt `finished_naturally` as completion signal | Remove dependency on `MINI_SWE_AGENT_FINAL_OUTPUT` stdout scanning in any Autarch batch runner. Use `AgentResult.finished_naturally` instead. | `agent_loop.py:68-70`, `mini_swe_runner.py:513-516` |
| P1 | Adopt immediate-flush JSONL pattern for batch runs | Every Autarch runner that processes multiple tasks must write and flush after each task, not batch-commit at the end. Model the checkpoint design from `BatchRunner` in `batch_runner.py`. | `batch_runner.py:385-508`, `mini_swe_runner.py:584-596` |
| P2 | Smoke-test environment with no external deps | Port `TerminalTestEnv`'s inline task pattern for Autarch harness validation. Three inline tasks, no external dataset, validates the full loop in approximately 5 minutes. | `terminal_test_env.py:58-82` |
| P2 | Decouple assessment-only from training-capable base | `HermesAgentBaseEnv` forces assessment-only environments to stub training methods. Autarch should split the base into `AssessEnv` (3 methods: `setup`, `evaluate`, `format_prompt`) and `TrainingEnv` (extends with `get_next_item`, `compute_reward`). | `hermes_base_env.py:608-672`, `terminalbench2_env.py:318-336` |
| P2 | Centralize tool error aggregation | Merge `AgentResult.tool_errors` and `_tool_error_buffer` into a single stream. Autarch's dashboard should consume one canonical error record per task, not two parallel representations. | `agent_loop.py:49-57`, `hermes_base_env.py:551-560` |
