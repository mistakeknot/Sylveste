# Sprint Handoff: Hermes Execution Receipts P1

Date: 2026-04-25
Parent bead: Sylveste-1vq

## Sprint state

The sprint ran through brainstorm, PRD, plan, review, implementation, delegation-provenance completion, and dogfood verification in Hermes.

## Bead artifacts

- Brainstorm: docs/brainstorms/2026-04-25-hermes-execution-receipts-brainstorm.md
- Brainstorm review: docs/research/flux-review/hermes-execution-receipts/brainstorm-review-2026-04-25.md
- PRD: docs/prds/2026-04-25-hermes-execution-receipts.md
- PRD review: docs/research/flux-review/hermes-execution-receipts/prd-review-2026-04-25.md
- Implementation plan: docs/plans/2026-04-25-hermes-execution-receipts-implementation.md
- Plan review: docs/research/flux-review/hermes-execution-receipts/plan-review-2026-04-25.md
- Dogfood evidence: docs/research/flux-review/hermes-execution-receipts/dogfood-evidence-2026-04-25.md

## Hermes implementation completed in working tree

Files changed in `/Users/sma/.hermes/hermes-agent`:

- `hermes_cli/plugins.py`
  - Added `execution_receipt` as a valid plugin hook.
- `run_agent.py`
  - Added per-agent monotonic execution receipt sequence tracking.
  - Added fail-open `_emit_terminal_tool_receipt(...)` helper.
  - Emits `hermes.execution_receipt.v0` / `tool_complete` receipts for sequential, concurrent, blocked, invalid-JSON, error, and `delegate_task`-style agent-loop tool paths.
  - Receipts contain metadata only; raw args/results are not emitted.
- `plugins/execution-receipts/`
  - Replaced spike identity with Hermes-native `execution-receipts` plugin.
  - Registers only `execution_receipt` hook and `/receipts` command.
  - Persists JSONL to `$HERMES_HOME/execution-receipts/receipts.jsonl` or `HERMES_EXECUTION_RECEIPTS_PATH`.
  - Uses local append-only-ish JSONL writer with `0600` file mode and fail-open hook behavior.
- `tests/plugins/test_execution_receipts_plugin.py`
  - Replaces Skaffen-named tests with Hermes-native plugin tests.
- `tests/run_agent/test_run_agent.py`
  - Adds hook-contract and exact-once coverage for terminal tool paths, including delegate receipt links/evidence gaps.
- `tools/delegate_tool.py`
  - Adds bounded child provenance fields to delegate results: `child_session_id`, `child_task_id`, `subagent_id`, and `provenance_evidence_gaps`.
  - Extends `subagent_stop` with child correlation, API call count, bounded tool-trace summary, and explicit evidence gaps.
- `tests/tools/test_delegate.py`
  - Adds coverage that `subagent_stop` exposes opaque child IDs and metadata-only trace summaries without raw child traces.

## Verification

Passed:

```bash
uv run --extra dev pytest -n0 tests/plugins/test_execution_receipts_plugin.py tests/hermes_cli/test_plugins.py tests/tools/test_delegate.py tests/run_agent/test_run_agent.py -q
# 482 passed, 482 warnings in 138.28s

uv run --extra dev python -m py_compile run_agent.py tools/delegate_tool.py plugins/execution-receipts/__init__.py tests/plugins/test_execution_receipts_plugin.py tests/tools/test_delegate.py tests/run_agent/test_run_agent.py
# passed

uv run --extra dev ruff check plugins/execution-receipts tests/plugins/test_execution_receipts_plugin.py
# All checks passed

git diff --check -- hermes_cli/plugins.py run_agent.py tools/delegate_tool.py tests/run_agent/test_run_agent.py tests/tools/test_delegate.py tests/hermes_cli/test_plugins.py tests/plugins/test_execution_receipts_plugin.py plugins/execution-receipts
# passed
```

Observed issue:

- `uv` still warns that `exclude-newer = "7 days"` in `pyproject.toml` cannot be parsed as a date.
- Full-file `ruff check run_agent.py tests/run_agent/test_run_agent.py tools/delegate_tool.py tests/tools/test_delegate.py` reports existing broad-file lint debt; targeted ruff for the new execution-receipts plugin/tests passes.
- `tests/tools/test_delegate.py` had one earlier xdist timing failure in `TestDelegateHeartbeat::test_heartbeat_does_not_trip_idle_stale_while_inside_tool`; the same test passed with `-n0`, and the full focused set passed with `-n0`.

## Completed remaining work

- Delegation provenance now includes child session/task/subagent correlation where available and explicit evidence gaps where unavailable.
- `subagent_stop` now carries bounded child metadata: child IDs, role/status, API call count, duration, and a metadata-only child tool-trace summary.
- Parent `delegate_task` execution receipts now extract delegate child links from the JSON result and include explicit evidence gaps.
- Dogfood evidence was captured in `docs/research/flux-review/hermes-execution-receipts/dogfood-evidence-2026-04-25.md`.

## Follow-up candidates

- Decide whether to keep or remove the duplicate implementation plan at `/Users/sma/.hermes/hermes-agent/docs/plans/2026-04-25-hermes-execution-receipts-implementation.md`.
- Run a live-provider/live-subagent E2E receipt dogfood once credentials/test isolation are ready.
- Decide what to do with existing unrelated Hermes dirty state before any commit.

## Alignment

Supports Sylveste/Hermes by extracting a general execution-evidence substrate from the Skaffen analysis without turning Hermes into Skaffen.

## Conflict/Risk

The Hermes working tree already has unrelated dirty state; do not commit or push this without separating/confirming scope.
