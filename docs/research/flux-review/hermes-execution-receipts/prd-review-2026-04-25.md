# Hermes Execution Receipts PRD Review

Date: 2026-04-25
Bead: Sylveste-1vq
Target: docs/prds/2026-04-25-hermes-execution-receipts.md
Related brainstorm: docs/brainstorms/2026-04-25-hermes-execution-receipts-brainstorm.md

## Verdict

Needs revision before Step 3 planning.

No P0 findings were identified. P1 issues are mostly specificity problems: hook name, trace identity, exact-once matrix, delegation provenance, redaction, writer safety, privacy controls, and fail-open semantics must be resolved enough to drive TDD.

## Required P1 Revisions

1. Resolve the hook name and payload scope.
   - Use `execution_receipt` with `receipt_type: tool_complete` for P1, because the schema is already span-shaped and likely to grow beyond terminal tool events.
   - Payload should be one kwarg: `receipt={...}`.

2. Define minimal trace/span context.
   - `trace_id`: stable per root agent run/session; propagated into child agents when practical.
   - `span_id`: unique per emitted receipt.
   - `parent_span_id`: parent tool/delegate span when known, otherwise empty/null plus explicit evidence gap.
   - `sequence_number`: monotonic per writer/session/trace scope, assigned at emission/write time.
   - `links[]`: optional references for tool_call_id, child_session_id, child_trace_id, or other non-tree relationships.

3. Define exact-once terminal event matrix.
   - Required paths: registry success/error, direct agent-loop success/error, blocked, cancelled/interrupted, invalid tool, invalid JSON, timeout when representable, concurrent batch, and delegate_task parent receipt.
   - Define invalid tool/JSON as one terminal receipt per attempted tool call or per failed call object, not ambiguous retry-level behavior.

4. Tighten delegation requirements.
   - Extend subagent/delegate evidence when feasible with child_session_id, child_task_id/subagent_id, child_trace_id, child status, api_calls, and tool_trace digest/summary.
   - If unavailable, use stable evidence-gap codes and test the gap path.

5. Tighten privacy/redaction and storage controls.
   - Default previews off or allowlisted only.
   - No raw args/results by default.
   - Redaction before serialization/write.
   - Redactor failure writes a minimal safe receipt, never raw fallback.
   - File/dir permissions 0600/0700, local-only P1 persistence, rotation/retention/purge behavior.

6. Clarify fail-open and write-failure semantics.
   - Receipt failures must never alter tool results/status.
   - Tool execution status and receipt sink status are separate.
   - Writer failures are observable through counters/logs/status without recursive receipt_write_failed loops.

7. Clarify integrity stance.
   - P1 may be best-effort/not tamper-evident, but must explicitly say so if hash chaining is deferred.
   - Still require sequence numbers, duplicate/gap/corrupt-line reporting, dropped/oversize counters.

8. Tighten dogfood artifact requirements.
   - Dogfood note path, exact config, sanitized summary/excerpt, minimum receipt count, at least one registry receipt, at least one direct/delegated receipt, and evidence-gap summary.

## Gate Resolution

Patch the PRD to incorporate these requirements, then proceed to Step 3 planning if no new P0/P1 issues remain.
