# Hermes Execution Receipts Brainstorm Review

Date: 2026-04-25
Bead: Sylveste-1vq
Target: docs/brainstorms/2026-04-25-hermes-execution-receipts-brainstorm.md

## Verdict

Needs revision before leaving Step 1.

No P0 findings were identified. Multiple P1 findings must be converted into explicit design requirements before planning/implementation, especially around enablement, trace identity, redaction, writer safety, schema evolution, and delegated provenance.

## P1 Findings

1. Plugin enablement/disabled-by-default semantics are unsafe unless explicitly tested.
   - The implementation plan must verify how Hermes actually gates bundled/user/project plugins.
   - If `plugins.enabled` is not a real hook-registration gate in the current target repo, the receipt plugin must self-gate on explicit config.

2. The hook contract must be stable and versioned.
   - Add the chosen hook to Hermes' valid hook set.
   - Prefer a single versioned payload argument, e.g. `receipt={...}`, rather than ad hoc kwargs.

3. Universal coverage is easy to overclaim.
   - Agent-loop execution has registry, direct, concurrent, blocked, invalid, skipped, interrupted, and delegated branches.
   - Use one internal emission helper and tests for each terminal branch.

4. Trace/span identity is missing.
   - Define `trace_id`, `span_id`, and `parent_span_id` now, even if only tool terminal events are emitted first.
   - Include sequence numbers and links for cases without strict parentage.

5. Redaction policy is underspecified.
   - Durable receipts need always-on, receipt-specific sanitization.
   - Default to no raw args/results; store allowlisted metadata, hashes, sizes, and bounded sanitized previews.

6. JSONL writer safety is underspecified.
   - Concurrent tools/subagents require a lock or single-writer queue.
   - Define max encoded receipt size, recovery for partial lines, rotation/retention, and fail-open-but-observable write errors.

7. Delegation provenance cannot be deferred too far.
   - The first slice should propagate parent/root trace context into child agents when feasible.
   - At minimum, parent `delegate_task` receipts must include stable child trace/session references or explicit evidence gaps.

8. Evidence integrity/tamper evidence is missing.
   - For P1 implementation, full signing can defer, but schema should reserve `receipt_id`, `prev_hash`, and `receipt_hash` fields or explicitly mark integrity as a P2 follow-up.

9. Failure terminal states need semantics.
   - Include statuses for `ok`, `error`, `blocked`, `cancelled`, `timeout`, `invalid_tool`, `invalid_json`, and `receipt_write_failed` where applicable.

## P2 Findings

- Add retention/prune/export controls.
- Add a verifier/doctor command in a later slice.
- Record prior-art/provenance paths and inspected repo commit in design artifacts.
- Avoid direct external observability dependencies in P1; keep local JSONL first.

## Gate Resolution

The brainstorm should be revised to include these as explicit design constraints before Step 2 strategy proceeds.
