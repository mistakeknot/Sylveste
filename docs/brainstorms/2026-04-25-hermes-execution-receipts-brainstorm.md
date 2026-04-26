---
artifact_type: brainstorm
bead: Sylveste-1vq
stage: discover
---

# Hermes Execution Receipts Brainstorm

## What We're Building

Build a Hermes-native execution receipts capability from the earlier Skaffen-on-Hermes spike, but treat Skaffen as concepts-only prior art rather than a durable product namespace. The feature should record passive, redacted, replay-oriented evidence for meaningful Hermes runtime actions, starting with tool completion events.

The immediate landing slice is P1 observability, not enforcement: rename the spike to `execution-receipts`, replace Skaffen-specific schema/env/path/command names, and add one universal tool-complete hook emitted from Hermes' agent loop so both registry-dispatched tools and direct agent-loop tools are visible. This should cover `delegate_task` as a parent tool call and create a path for child/subagent receipts to carry stable IDs later.

## Why This Approach

The P0 substrate spike showed Hermes can support passive/advisory receipts today, but cannot honestly claim hard phase gates yet. `pre_api_request` is observational, `delegate_task` bypasses normal `post_tool_call`, and `subagent_stop` lacks enough child trace references for full delegated evidence.

So the next step should strengthen the evidence substrate before adding `/route`, `/sprint`, or trust enforcement. A new Hermes-native hook emitted from `run_agent.py` is the least risky way to get complete tool coverage without changing existing `post_tool_call` compatibility semantics in `model_tools.py`.

Prior art considered: existing Sylveste research notes that LangSmith, OpenAI Agents SDK tracing, Langfuse, AgentOps, and Phoenix all model agent observability as structured traces/spans. Hermes should borrow the shape — structured, timestamped, redacted spans — but keep this slice local, profile-scoped, and JSONL-first instead of introducing an external observability dependency.

## Key Decisions

- Use Hermes-native naming: `execution-receipts`, `/receipts`, `hermes.execution_receipt.v0`, and `$HERMES_HOME/execution-receipts/receipts.jsonl`.
- Keep the plugin passive and disabled by default, but do not assume `plugins.enabled` gates hook registration until the current Hermes repo proves it. If plugin-manager enablement is not a real gate, add a receipt-plugin self-gate such as `execution_receipts.enabled: true` and test that disabled mode registers no writer and writes no receipts.
- Add a new hook such as `tool_complete` or `execution_receipt`; prefer a scoped `tool_complete` hook for the first slice unless the implementation naturally supports multiple receipt types. Add the hook to Hermes' valid hook contract and pass a single versioned `receipt={...}` payload rather than ad hoc kwargs.
- Emit the new hook from one internal agent-loop helper in `run_agent.py`, where Hermes has visibility into registry tools, direct agent-loop tools, blocked tools, cancelled tools, invalid/failed calls, concurrent execution, and `delegate_task`.
- Do not reuse `post_tool_call` as the universal substrate yet; it risks duplicate emissions for registry tools and still does not naturally cover all direct paths.
- Model each receipt as a small span-shaped terminal event with `trace_id`, `span_id`, `parent_span_id`, `receipt_id`, `sequence_number`, `session_id`, `task_id`, `tool_call_id`, `tool_name`, `status`, `duration_ms`, and optional `links` when strict parentage is unavailable.
- Define terminal statuses before coding: at least `ok`, `error`, `blocked`, `cancelled`, `timeout`, `invalid_tool`, `invalid_json`, and `receipt_write_failed`.
- Use receipt-specific, always-on redaction. Default to no raw args/results; store allowlisted metadata, hashes, sizes, and bounded sanitized previews. Include `redaction_policy_version` and `redaction_status` in receipts.
- Make the JSONL writer safe under concurrent tools/subagents: lock or single-writer queue, one complete JSON object per append, max encoded receipt size, partial-line recovery, and fail-open-but-observable write failures.
- Include delegated provenance in P1 scope where feasible: parent `delegate_task` receipts should include child trace/session references or explicit evidence gaps, and child agents should receive parent/root trace context when the substrate makes that practical.
- Reserve or implement integrity fields (`receipt_hash`, `prev_hash`) so later verifier/doctor work can detect gaps, duplicates, reordering, and truncation. Full signing/HMAC can be a later slice.
- Dogfood one real Hermes task with receipts enabled before claiming the slice is useful.

## Open Questions

- Should the new core hook be named narrowly (`tool_complete`) or broadly (`execution_receipt` with `receipt_type=tool_complete`)? Recommendation: narrow first, broaden only when session/API receipts need the same dispatch surface.
- Should registry tools continue emitting legacy `post_tool_call` in addition to the new hook? Recommendation: yes for compatibility, with tests proving the new hook emits exactly once per tool-like action.
- How much result data is safe to store? Recommendation: store hashes, sizes, status, error classes, and optional bounded sanitized previews; never store raw unbounded output by default.
- Where should child subagent receipts live long term? Recommendation: every `AIAgent` instance should emit its own receipts; parent-visible `subagent_stop` can carry a trace/session reference rather than the full child trace.
- How strong should P1 integrity be? Recommendation: include hash-chain-ready fields and a simple verifier target if cheap, but defer signing/HMAC and external anchoring.
- Should this bead land in the Hermes repo directly even though it is tracked from Sylveste? Recommendation: yes; the bead records the Sylveste-derived adaptation decision, while code changes land in `/Users/sma/.hermes/hermes-agent`.

## Review Resolution

Step 1 review found no P0 issues, but identified P1 requirements around plugin enablement, hook contract stability, trace identity, redaction, writer safety, delegated provenance, terminal statuses, and integrity. Those requirements are now captured above and should become acceptance criteria in strategy/plan rather than implementation surprises.

## Chosen Approach

Proceed with Approach A: add a new Hermes-native tool-complete/execution-receipt hook from `run_agent.py`, then rename and adapt the passive receipt plugin around that hook. This creates a reusable Hermes capability and avoids baking stale Skaffen assumptions into the product.

Alignment: Evidence first, authority later; every meaningful action should become reconstructable evidence before any routing or enforcement claims are made.

Conflict/Risk: This touches Hermes core while the bead lives in Sylveste; keep the slice small, passive, and compatibility-preserving, and avoid Skaffen-branded durable API names.
