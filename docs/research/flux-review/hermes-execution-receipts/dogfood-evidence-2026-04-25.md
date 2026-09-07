# Hermes Execution Receipts Dogfood Evidence — 2026-04-25

Bead: `Sylveste-1vq`
Child slice: `Sylveste-4m8` / F5

## Goal

Verify the Hermes-native `execution-receipts` plugin and `execution_receipt` hook can capture a reconstructable, metadata-only execution trail for a real agent-loop task before any routing, sprint, or enforcement layer is built on top.

## Dogfood run

Run shape:

- Temporary `HERMES_HOME` with only `execution-receipts` enabled.
- `HERMES_EXECUTION_RECEIPTS_PATH` pointed at the temporary receipt JSONL.
- Real `AIAgent.run_conversation(...)` loop.
- Mocked LLM responses to avoid external network/API dependencies.
- Real tool loop with:
  - one registry `terminal` tool call;
  - one `delegate_task` action through the agent-loop dispatch seam, with child provenance returned by a bounded fake child result.

The first attempt intentionally exposed an important wiring detail: the current agent loop creates a request-local OpenAI client, so setting only `agent.client` is insufficient for a dogfood harness. The successful run used a `MagicMock` client and patched `_create_request_openai_client` to return that same mock, matching the existing test harness pattern and avoiding a live provider call.

## Observed summary

```json
{
  "api_calls": 3,
  "contains_raw_delegate_summary": false,
  "contains_raw_terminal_output": false,
  "delegate_links": [
    {
      "id": "dogfood-child-session-1",
      "type": "delegate_child_session"
    },
    {
      "id": "dogfood-child-task-1",
      "type": "delegate_child_task"
    },
    {
      "id": "dogfood-subagent-1",
      "type": "delegate_subagent"
    },
    {
      "id": "call-delegate-dogfood",
      "type": "tool_call"
    }
  ],
  "evidence_gaps": [
    "child_full_trace_unavailable",
    "parent_span_unavailable"
  ],
  "final_response": "dogfood complete",
  "receipt_count": 2,
  "schema_versions": [
    "hermes.execution_receipt.v0"
  ],
  "statuses": [
    "ok",
    "ok"
  ],
  "tools": [
    "terminal",
    "delegate_task"
  ]
}
```

Full temporary path from the run:

`/var/folders/db/h1yh_d9550qcsd1l30c3nv340000gn/T/hermes-receipts-dogfood-rxu8pvl1/execution-receipts/receipts.jsonl`

## Acceptance check

- Receipt file was created under profile-local receipt path: yes.
- Canonical schema version was used: `hermes.execution_receipt.v0`.
- Terminal action represented: yes, `tool_name: terminal`.
- Delegated action represented: yes, `tool_name: delegate_task`.
- Delegate child correlation represented: yes, links include `delegate_child_session`, `delegate_child_task`, and `delegate_subagent`.
- Evidence gaps explicit: yes, includes `child_full_trace_unavailable` and `parent_span_unavailable`.
- Raw terminal output persisted: no.
- Raw child summary persisted in receipt stream: no.
- Receipts are passive: yes; no gate/enforcement behavior was exercised.

## Interpretation

The current P1 slice is good enough as a passive evidence substrate for tool-complete receipts, including parent-level delegation correlation. It is not yet a complete distributed trace:

- Child internals remain summarized rather than replayed.
- Parent span lineage is still unavailable.
- The dogfood harness uses mocked LLM/delegation to avoid external provider calls, so a later E2E run should verify live subagent behavior once credentials and test isolation are prepared.

This supports the current strategy: keep building passive receipts and observability seams before `/route`, `/sprint`, trust routing, or hard enforcement.
