# Hermes Execution Receipts P1 Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Land a passive Hermes-native execution receipts substrate: `execution_receipt` hook with `receipt_type: tool_complete`, a disabled-by-default `/receipts` plugin, redacted JSONL storage, delegation provenance, and dogfood evidence.

**Architecture:** Keep enforcement out of scope. Add one fail-open core observability seam for terminal tool-like actions, then let an opt-in standalone plugin persist redacted span-shaped receipts. Preserve existing `post_tool_call` behavior and use tests to prevent duplicate or missing terminal events.

**Tech Stack:** Python, Hermes plugin manager, pytest via `uv run --extra dev pytest`, JSONL sidecar storage under `$HERMES_HOME`, existing Hermes delegation/tool execution code.

Alignment: Builds Hermes' evidence layer first, matching the module doctrine of making action observable before adding authority.
Conflict/Risk: Risk is overclaiming safety or leaking sensitive metadata; this plan keeps P1 passive, local-only, redacted, and explicitly non-tamper-evident unless later work adds hash chaining.

---

## Pre-flight

Work in `/Users/sma/.hermes/hermes-agent`.

Run before editing:

```bash
git status --short
```

Known caution: the repo already has unrelated dirty state and `uv.lock` may be modified by `uv run --extra dev ...`; do not clean, revert, commit, or push unrelated changes without explicit user direction.

## Task 1: Add the hook name to the plugin contract

**Objective:** Make `execution_receipt` a recognized plugin hook while preserving existing hooks.

**Files:**
- Modify: `/Users/sma/.hermes/hermes-agent/hermes_cli/plugins.py`
- Test: `/Users/sma/.hermes/hermes-agent/tests/hermes_cli/test_plugins.py`

**Step 1: Write failing test**

Add a test near existing valid-hook/plugin-manager tests:

```python
def test_execution_receipt_is_valid_hook():
    from hermes_cli.plugins import VALID_HOOKS

    assert "execution_receipt" in VALID_HOOKS
```

**Step 2: Verify RED**

Run:

```bash
uv run --extra dev pytest tests/hermes_cli/test_plugins.py::test_execution_receipt_is_valid_hook -q
```

Expected: FAIL because `execution_receipt` is not yet in `VALID_HOOKS`.

**Step 3: Implement minimal code**

Add `execution_receipt` to `VALID_HOOKS` in `hermes_cli/plugins.py`.

**Step 4: Verify GREEN**

Run:

```bash
uv run --extra dev pytest tests/hermes_cli/test_plugins.py::test_execution_receipt_is_valid_hook -q
```

Expected: PASS.

## Task 2: Define the canonical receipt helper and exact-once seam

**Objective:** Create one helper contract that emits fail-open `execution_receipt` hooks with stable envelope fields, then use that helper as the only terminal receipt emission surface.

**Files:**
- Modify: `/Users/sma/.hermes/hermes-agent/run_agent.py`
- Test: `/Users/sma/.hermes/hermes-agent/tests/run_agent/test_run_agent.py`

**Step 1: Write failing test for receipt envelope**

Add a test that monkeypatches `hermes_cli.plugins.invoke_hook`, calls the new helper, and asserts one hook call:

```python
def test_execution_receipt_hook_receives_tool_complete_envelope(monkeypatch):
    seen = []

    def fake_invoke_hook(name, **kwargs):
        seen.append((name, kwargs))
        return []

    monkeypatch.setattr("hermes_cli.plugins.invoke_hook", fake_invoke_hook)

    agent = AIAgent(api_key="test", provider="openai", model="gpt-test")
    agent.session_id = "session-1"
    agent.task_id = "task-1"

    agent._emit_terminal_tool_receipt(
        tool_name="example_tool",
        tool_call_id="call-1",
        status="ok",
        duration_ms=12,
        source="direct",
        evidence_gaps=[],
        links=[],
    )

    assert len(seen) == 1
    hook_name, kwargs = seen[0]
    assert hook_name == "execution_receipt"
    receipt = kwargs["receipt"]
    assert receipt["schema_version"] == "hermes.execution_receipt.v0"
    assert receipt["receipt_type"] == "tool_complete"
    assert receipt["receipt_id"]
    assert receipt["session_id"] == "session-1"
    assert receipt["task_id"] == "task-1"
    assert receipt["tool_name"] == "example_tool"
    assert receipt["tool_call_id"] == "call-1"
    assert receipt["status"] == "ok"
    assert receipt["duration_ms"] == 12
    assert receipt["trace_id"]
    assert receipt["span_id"]
    assert "parent_span_id" in receipt
    assert isinstance(receipt["sequence_number"], int)
    assert receipt["timestamp"]
    assert "redaction_policy_version" in receipt
    assert "redaction_status" in receipt
    assert receipt["evidence_gaps"] == []
    assert receipt["links"] == []
```

Adjust constructor details to match real fixtures already used in `tests/run_agent/test_run_agent.py`.

**Step 2: Verify RED**

Run:

```bash
uv run --extra dev pytest tests/run_agent/test_run_agent.py::test_execution_receipt_hook_receives_tool_complete_envelope -q
```

Expected: FAIL because `_emit_terminal_tool_receipt` does not exist.

**Step 3: Implement minimal helper**

In `run_agent.py`, add a small fail-open method on `AIAgent` named `_emit_terminal_tool_receipt`:

- assign `trace_id` lazily from existing `session_id` or a UUID fallback;
- assign `sequence_number` with an instance counter and lock if concurrency already uses threads;
- generate unique `receipt_id` and `span_id`;
- include `parent_span_id`, `timestamp`, `evidence_gaps`, `links`, `source`, `schema_version: hermes.execution_receipt.v0`, and `receipt_type: tool_complete`;
- include core redaction metadata fields with conservative values such as `redaction_policy_version: core-envelope-v0` and `redaction_status: envelope_only`; the plugin may strengthen persistence redaction before writing;
- call `invoke_hook("execution_receipt", receipt=receipt)` inside `try/except Exception: pass`.

Do not persist receipts in core.

**Step 4: Verify GREEN**

Run the same test. Expected: PASS.

**Canonical seam rule for later tasks:** every implementation task must route terminal tool-like actions through `_emit_terminal_tool_receipt` or a single wrapper that calls it. Do not add ad hoc `invoke_hook("execution_receipt", ...)` calls in separate code paths unless the test proves the path bypasses the canonical wrapper and still emits exactly once.

## Task 3: Emit receipts for registry tool success and error paths

**Objective:** Prove normal registry-dispatched tools produce exactly one terminal receipt.

**Files:**
- Modify: `/Users/sma/.hermes/hermes-agent/run_agent.py`
- Test: `/Users/sma/.hermes/hermes-agent/tests/run_agent/test_run_agent.py`

**Step 1: Write failing tests**

Add two tests using existing run-agent tool execution fixtures:

```python
def test_registry_tool_success_emits_one_execution_receipt(monkeypatch):
    receipts = []
    monkeypatch.setattr("hermes_cli.plugins.invoke_hook", lambda name, **kw: receipts.append((name, kw)) or [])

    # Arrange a registry tool call through the same path used by the agent loop.
    # Execute it with tool_call_id="call-ok" and tool_name="test_tool".

    tool_receipts = [kw["receipt"] for name, kw in receipts if name == "execution_receipt"]
    assert len(tool_receipts) == 1
    assert tool_receipts[0]["tool_call_id"] == "call-ok"
    assert tool_receipts[0]["status"] == "ok"


def test_registry_tool_error_emits_one_execution_receipt(monkeypatch):
    receipts = []
    monkeypatch.setattr("hermes_cli.plugins.invoke_hook", lambda name, **kw: receipts.append((name, kw)) or [])

    # Arrange a registry tool call whose result is classified by existing failure detection.

    tool_receipts = [kw["receipt"] for name, kw in receipts if name == "execution_receipt"]
    assert len(tool_receipts) == 1
    assert tool_receipts[0]["status"] == "error"
```

Use existing helper patterns in `test_run_agent.py`; do not mock the receipt helper itself.

**Step 2: Verify RED**

Run the two tests. Expected: FAIL because no receipt is emitted by the actual execution path.

**Step 3: Implement minimal emission**

Route the registry/direct tool terminal path through the canonical seam from Task 2 after the terminal result is known. Use existing `_detect_tool_failure` or equivalent status classifier. The receipt should be emitted from one final wrapper such as `_append_tool_result_and_receipt(...)` if that wrapper exists or is introduced.

Keep `model_tools.post_tool_call` unchanged. Do not also emit from `model_tools.py` for the same call.

**Step 4: Verify GREEN**

Run the two tests and existing `tests/run_agent/test_run_agent.py` targeted subset.

## Task 4: Emit receipts for invalid tool and invalid JSON paths

**Objective:** Make malformed tool attempts observable without pretending execution happened.

**Files:**
- Modify: `/Users/sma/.hermes/hermes-agent/run_agent.py`
- Test: `/Users/sma/.hermes/hermes-agent/tests/run_agent/test_run_agent.py`

**Step 1: Write failing tests**

Add tests for existing invalid-tool-name and invalid-JSON recovery paths. Assert one receipt per failed attempted tool call object:

```python
def test_invalid_tool_name_emits_invalid_tool_receipt(monkeypatch):
    receipts = []
    monkeypatch.setattr("hermes_cli.plugins.invoke_hook", lambda name, **kw: receipts.append((name, kw)) or [])

    # Drive existing invalid tool recovery with tool_call_id="bad-tool".

    receipt = [kw["receipt"] for name, kw in receipts if name == "execution_receipt"][0]
    assert receipt["status"] == "invalid_tool"
    assert receipt["tool_call_id"] == "bad-tool"


def test_invalid_tool_json_emits_invalid_json_receipt(monkeypatch):
    receipts = []
    monkeypatch.setattr("hermes_cli.plugins.invoke_hook", lambda name, **kw: receipts.append((name, kw)) or [])

    # Drive existing invalid JSON recovery with tool_call_id="bad-json".

    receipt = [kw["receipt"] for name, kw in receipts if name == "execution_receipt"][0]
    assert receipt["status"] == "invalid_json"
```

**Step 2: Verify RED**

Run the new tests. Expected: FAIL.

**Step 3: Implement minimal emission**

At the existing invalid-tool and invalid-JSON recovery points, route through `_emit_terminal_tool_receipt(...)` with status `invalid_tool` or `invalid_json`, duration `0` if no timer exists, and evidence gap codes if args/result are unavailable. Emit on each failed attempted tool call object before retry/recovery injection; do not emit a turn-level aggregate.

**Step 4: Verify GREEN**

Run the new tests. Expected: PASS.

## Task 5: Cover blocked/cancelled/concurrent paths without duplicate receipts

**Objective:** Ensure terminal receipts are exact-once even when tools are blocked, skipped, or run concurrently.

**Files:**
- Modify: `/Users/sma/.hermes/hermes-agent/run_agent.py`
- Test: `/Users/sma/.hermes/hermes-agent/tests/run_agent/test_run_agent.py`

**Step 1: Write failing tests**

Add tests for:

- `pre_tool_call` block results in status `blocked`;
- interrupt/skipped path results in status `cancelled` where Hermes has a representable skip path;
- concurrent batch of N tool calls emits exactly N receipts with unique `span_id` and unique `sequence_number`.

**Step 2: Verify RED**

Run each test individually with `uv run --extra dev pytest ... -q`. Expected: FAIL until each behavior exists.

**Step 3: Implement minimal emission**

Use the canonical terminal receipt helper for all paths. Guard against double emission by putting receipt emission in the final agent-loop wrapper, not in both `model_tools.py` and `run_agent.py` for the same call. If a path bypasses the wrapper, add the smallest adapter that forwards into `_emit_terminal_tool_receipt(...)` and add a regression test for exact-once behavior.

**Step 4: Verify GREEN**

Run the new tests. Expected: PASS.

## Task 6: Rename the spike plugin to execution-receipts

**Objective:** Remove durable Skaffen branding from the plugin and command surface.

**Files:**
- Move/Create: `/Users/sma/.hermes/hermes-agent/plugins/execution-receipts/plugin.yaml`
- Move/Create: `/Users/sma/.hermes/hermes-agent/plugins/execution-receipts/__init__.py`
- Move/Create: `/Users/sma/.hermes/hermes-agent/plugins/execution-receipts/README.md`
- Move/Test: `/Users/sma/.hermes/hermes-agent/tests/plugins/test_execution_receipts_plugin.py`
- Remove after migration: `/Users/sma/.hermes/hermes-agent/plugins/skaffen-receipts/` and `/Users/sma/.hermes/hermes-agent/tests/plugins/test_skaffen_receipts_plugin.py`

**Step 1: Write failing rename test**

In `test_execution_receipts_plugin.py`, test the new enablement name:

```python
def test_execution_receipts_is_disabled_by_default(tmp_path, monkeypatch):
    monkeypatch.setenv("HERMES_HOME", str(tmp_path))
    (tmp_path / "config.yaml").write_text("plugins:\n  enabled: []\n", encoding="utf-8")

    manager = PluginManager()
    manager.discover_and_load(force=True)

    loaded = manager._plugins.get("execution-receipts")
    assert loaded is not None
    assert not loaded.enabled
    assert "execution-receipts" not in manager._plugin_commands
    assert not (tmp_path / "execution-receipts" / "receipts.jsonl").exists()
```

**Step 2: Verify RED**

Run:

```bash
uv run --extra dev pytest tests/plugins/test_execution_receipts_plugin.py::test_execution_receipts_is_disabled_by_default -q
```

Expected: FAIL because the plugin/test names do not exist yet.

**Step 3: Implement minimal rename**

Copy/rename the spike plugin and tests, replacing:

- `skaffen-receipts` -> `execution-receipts`;
- `SKAFFEN_RECEIPTS_PATH` -> `HERMES_EXECUTION_RECEIPTS_PATH`;
- `skaffen.receipt.v0` -> `hermes.execution_receipt.v0`;
- `/skaffen-receipts` command -> `/receipts`;
- default path `$HERMES_HOME/skaffen-receipts/receipts.jsonl` -> `$HERMES_HOME/execution-receipts/receipts.jsonl`.

**Step 4: Verify GREEN**

Run the renamed plugin tests. Expected: PASS.

## Task 7: Implement redacted receipt schema and safe writer behavior

**Objective:** Make the plugin persist safe JSONL receipts from `execution_receipt` hook calls.

**Files:**
- Modify: `/Users/sma/.hermes/hermes-agent/plugins/execution-receipts/__init__.py`
- Test: `/Users/sma/.hermes/hermes-agent/tests/plugins/test_execution_receipts_plugin.py`

**Step 1: Write failing tests**

Add tests for:

- enabled mode writes one JSON object with `schema_version: hermes.execution_receipt.v0`;
- every persisted terminal receipt includes all PRD F3 envelope fields or an explicit evidence-gap code for unavailable parent/context fields;
- secret canaries in args/results/payload do not appear in the JSONL text;
- previews are absent by default;
- `redaction_policy_version` and `redaction_status` exist;
- `sequence_number`, `receipt_id`, and `span_id` are unique across concurrent writes;
- oversized receipts preserve the envelope and drop/truncate only unsafe optional fields;
- corrupt existing line is skipped/reported by `/receipts status` and does not prevent append;
- duplicate/sequence-gap/corrupt/dropped counters are represented in status;
- writer failure is fail-open and visible in status/counters;
- retention/rotation behavior is implemented or `/receipts status` reports the documented v0 no-rotation limit.

**Step 2: Verify RED**

Run the new tests individually. Expected: FAIL.

**Step 3: Implement minimal code**

Update the plugin to:

- register `@hook("execution_receipt")` and persist terminal `receipt` objects;
- avoid persisting legacy `pre_*`, `post_*`, or `post_tool_call` hook events into the same terminal receipt stream;
- if `subagent_stop` is retained for provenance, persist it as a distinct non-terminal observational event and exclude it from exact-once terminal counts;
- redact before serialization;
- write local JSONL with parent directory/file permissions where possible;
- use an in-process lock or single-writer function;
- keep writer errors in an in-memory diagnostic counter exposed by `/receipts status`.

Do not let a renamed spike plugin keep writing old passive hook receipts as if they were terminal execution receipts.

**Step 4: Verify GREEN**

Run:

```bash
uv run --extra dev pytest tests/plugins/test_execution_receipts_plugin.py -q
```

Expected: PASS.

## Task 8: Enrich delegation provenance

**Objective:** Ensure `delegate_task` parent calls produce a terminal receipt and subagent evidence is not silently lost.

**Files:**
- Modify: `/Users/sma/.hermes/hermes-agent/tools/delegate_tool.py`
- Modify: `/Users/sma/.hermes/hermes-agent/run_agent.py` if parent receipt emission happens there
- Test: `/Users/sma/.hermes/hermes-agent/tests/tools/test_delegate.py`
- Test: `/Users/sma/.hermes/hermes-agent/tests/run_agent/test_run_agent.py`

**Step 1: Write failing tests**

Add tests that assert:

- a parent `delegate_task` action emits one `execution_receipt` with `tool_name: delegate_task` and status from the parent result;
- the parent delegate receipt includes child references in `links[]` or stable provenance fields when the child exposes them;
- `subagent_stop` includes `child_session_id`, child status/exit reason, API call count, and bounded tool-trace digest/summary when available;
- if child references are unavailable, the emitted receipt or subagent event includes stable evidence gap codes;
- delegation error/failure still emits exactly one parent terminal receipt.

**Step 2: Verify RED**

Run targeted delegate tests. Expected: FAIL.

**Step 3: Implement minimal code**

In `tools/delegate_tool.py`, capture bounded child references in the child result/entry when they already exist or are cheaply available:

- child session id;
- child task/subagent id;
- child trace id if propagated;
- child status/exit reason;
- API call count;
- bounded tool-trace digest/summary.

Pass those fields to `subagent_stop` and ensure the parent `delegate_task` receipt includes them through `links[]` or stable provenance fields. Avoid adding raw child prompts, raw task text, raw env, or full paths solely for trace correlation.

If parent `delegate_task` bypasses normal agent-loop receipt emission, add an explicit parent receipt at the one terminal parent seam; otherwise rely on the canonical helper and test for exact-once.

**Step 4: Verify GREEN**

Run:

```bash
uv run --extra dev pytest tests/tools/test_delegate.py tests/run_agent/test_run_agent.py -q
```

Expected: targeted tests pass.

## Task 9: Update documentation and remove stale durable names

**Objective:** Make docs reflect passive Hermes-native execution receipts and avoid product confusion.

**Files:**
- Modify: `/Users/sma/.hermes/hermes-agent/plugins/execution-receipts/README.md`
- Modify: any Hermes plugin hook docs that mention `VALID_HOOKS`
- Modify: `/Users/sma/.hermes/hermes-agent/website/docs/developer-guide/sylveste-adaptation-analysis.md` only if continuing to publish that doc

**Step 1: Write/adjust documentation assertions if existing docs tests cover plugin docs**

If there is no docs test, add a small static test that durable plugin files do not contain `skaffen-receipts` except historical notes.

**Step 2: Verify RED**

Run the static test. Expected: FAIL while stale names remain.

**Step 3: Update docs**

Document:

- `/receipts status`, `/receipts tail [n]`, `/receipts gaps`;
- disabled-by-default enablement via `plugins.enabled: [execution-receipts]`;
- `HERMES_EXECUTION_RECEIPTS_PATH` override;
- passive/advisory only;
- local-only best-effort v0, not tamper-evident;
- future seams for enforcement.

**Step 4: Verify GREEN**

Run docs/static tests if added and the plugin test file.

## Task 10: Dogfood execution receipts on one real Hermes task

**Objective:** Produce evidence that receipts are useful and honest before any `/route` or `/sprint` UX work.

**Files:**
- Create: `/Users/sma/.hermes/hermes-agent/docs/research/execution-receipts/dogfood-2026-04-25.md`

**Step 1: Configure an isolated dogfood profile**

Use a temporary `HERMES_HOME` or existing test profile with:

```yaml
plugins:
  enabled:
    - execution-receipts
```

**Step 2: Run one real Hermes action**

Choose a task that exercises at least one normal registry tool and one direct/delegated path. Keep it small and non-secret.

**Step 3: Inspect receipts**

Run `/receipts status`, `/receipts tail`, and `/receipts gaps` or invoke the command handler in a test/dogfood harness if interactive slash-command execution is awkward.

**Step 4: Write dogfood note**

Include:

- exact config/profile used;
- sanitized receipt summary or excerpt;
- minimum receipt count and event/status counts;
- whether registry and delegated/direct actions appeared;
- evidence gaps;
- explicit statement that P1 is passive/advisory only.

## Task 11: Run verification gates

**Objective:** Prove the implementation is complete without disturbing unrelated dirty state.

Run from `/Users/sma/.hermes/hermes-agent`:

```bash
uv run --extra dev pytest tests/plugins/test_execution_receipts_plugin.py tests/hermes_cli/test_plugins.py tests/tools/test_delegate.py tests/run_agent/test_run_agent.py -q
uv run --extra dev ruff check plugins/execution-receipts/__init__.py tests/plugins/test_execution_receipts_plugin.py
python3 -m compileall plugins/execution-receipts hermes_cli run_agent.py tools/delegate_tool.py
```

Expected:

- pytest target set passes;
- Ruff passes;
- compileall passes;
- `git diff --check` passes for touched files.

Also run:

```bash
git diff --check
```

If `uv.lock` changes only because of `uv` invocation and not intended dependency work, flag it for user review rather than silently reverting unrelated state.

## Suggested bead execution order

1. Sylveste-81r — core `execution_receipt` hook contract, canonical helper, and exact-once matrix.
2. Sylveste-ca5 — plugin identity/enablement rename after the hook name is stable.
3. Sylveste-d27 — schema/writer/redaction/storage.
4. Sylveste-z6b — delegation provenance and parent/child links.
5. Sylveste-4m8 — docs/dogfood.

Do not dogfood before both hook and writer behavior pass targeted tests. If Sylveste-ca5 is started before Sylveste-81r, keep it identity-only and do not land legacy passive hook persistence as terminal receipts.
