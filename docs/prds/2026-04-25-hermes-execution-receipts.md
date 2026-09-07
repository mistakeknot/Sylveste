---
artifact_type: prd
bead: Sylveste-1vq
stage: design
---

# PRD: Hermes Execution Receipts P1

## Problem

The Skaffen-on-Hermes spike proved that Hermes can passively observe useful runtime events, but it also showed that current evidence coverage is incomplete and still branded around a stale Sylveste subsystem. Hermes needs a native, passive execution receipt substrate before it can safely support advisory routing, sprint UX, or policy enforcement.

## Solution

Land a small Hermes-native execution receipts slice: a stable `execution_receipt` hook emitted from the agent loop with `receipt_type: tool_complete`, a disabled-by-default receipt plugin using Hermes-native names, a versioned/redacted/span-shaped JSONL schema, and tests/dogfood evidence proving registry tools, direct tools, and delegation boundaries are covered without claiming hard enforcement.

## Features

### F1: Hermes-native receipt plugin identity and enablement

**What:** Rename/reframe the spike from `skaffen-receipts` to `execution-receipts` and make enablement explicitly passive and disabled by default.

**Acceptance criteria:**
- Durable feature names use Hermes-native terminology: plugin `execution-receipts`, command `/receipts`, schema `hermes.execution_receipt.v0`, path `$HERMES_HOME/execution-receipts/receipts.jsonl`.
- Historical Skaffen references remain only in research/history docs, not plugin API names or user-facing command output.
- The plugin is a standalone Hermes plugin gated by `plugins.enabled`; disabled/default mode registers no hooks, exposes no `/receipts` command, creates no new receipt file/directory, and writes no receipts.
- If implementation discovers a plugin-manager path that still registers the plugin in disabled mode, add a secondary self-gate such as `execution_receipts.enabled: true` and test both gates.
- Command output is local-only, applies the same receipt redaction policy, and defaults to the current session/project where that scope is available.

### F2: Stable execution receipt hook contract

**What:** Add a Hermes-native `execution_receipt` hook for tool terminal receipts, emitted from a central agent-loop helper rather than from the registry-only dispatcher.

**Acceptance criteria:**
- `execution_receipt` is added to Hermes' valid hook contract and plugin docs/tests.
- Hook payload is a single versioned `receipt={...}` object with `receipt_type: "tool_complete"` for this P1 slice.
- Legacy `post_tool_call` remains backward-compatible and is not used as the universal substrate.
- Tests prove the new hook emits exactly once per terminal tool-like action for registry and direct agent-loop paths.
- Required exact-once matrix covers registry success, registry error, direct agent-loop success, direct agent-loop error, pre-tool-call blocked, cancelled/interrupted/skipped, invalid tool, invalid JSON, concurrent batch, and `delegate_task` parent receipt. Timeout is covered where Hermes exposes a representable timeout path.
- Invalid tool and invalid JSON behavior is explicit: emit one terminal receipt per failed attempted tool call object, not a turn-level aggregate.

### F3: Versioned, redacted, span-shaped receipt schema and writer

**What:** Define and implement the v0 JSONL receipt envelope, receipt-specific redaction, safe append behavior, and bounded payload policy.

**Acceptance criteria:**
- Receipts include required envelope fields: `schema_version`, `receipt_id`, `receipt_type`, `trace_id`, `span_id`, `parent_span_id`, `sequence_number`, `session_id`, `task_id`, `tool_call_id`, `tool_name`, `status`, `duration_ms`, timestamp, and redaction metadata.
- Trace semantics are defined for P1: `trace_id` is stable per root agent run/session and propagated to child agents when practical; `span_id` is unique per emitted receipt; `parent_span_id` points to the parent tool/delegate span when known; unknown parentage is represented by null/empty `parent_span_id` plus a stable evidence-gap code; `sequence_number` is unique and monotonic within the writer/session scope; `links[]` stores non-tree references such as child session or child trace IDs.
- Terminal statuses include at least `ok`, `error`, `blocked`, `cancelled`, `timeout`, `invalid_tool`, and `invalid_json` where applicable. Receipt sink/write health is tracked separately from tool execution status.
- Raw args/results are not persisted by default; receipts store hashes, sizes, safe allowlisted metadata, and sanitized previews only when preview storage is explicitly enabled for the tool or receipt profile.
- Hashes over sensitive raw values are avoided unless salted/keyed locally; default hashes should cover redacted/canonicalized payloads or opaque result digests that do not enable dictionary attacks on short secrets.
- Receipt-specific redaction remains on even if general debug redaction is disabled. Redaction runs before serialization/write; redactor failure writes a minimal safe receipt with `redaction_status: "failed_minimal"`, never raw fallback content.
- JSONL writes are thread-safe or single-writer queued, bounded by max receipt size, and recover gracefully from partial/corrupt lines.
- Storage is local-only in P1, uses owner-only permissions where the platform supports them (`0700` directory, `0600` file), and has explicit retention/rotation/purge behavior or a documented P1 limit if rotation is deferred.
- Write failures are fail-open for agent execution and observable through logs, in-memory counters, `/receipts status`, or a next-successful diagnostic; they must not recursively attempt infinite `receipt_write_failed` receipts.
- P1 integrity is best-effort, not tamper-evident unless hash chaining is implemented. Even if hash chaining is deferred, receipts/status must report sequence gaps, duplicates, corrupt lines, oversized/dropped receipts, and writer errors.

### F4: Delegation and subagent provenance coverage

**What:** Ensure `delegate_task` and child/subagent execution can be correlated through receipts or explicit evidence-gap markers.

**Acceptance criteria:**
- Parent `delegate_task` terminal receipts include parent trace/span context and child trace/session references when available.
- Child agents receive or derive opaque, non-secret trace context where practical without broad core churn. Trace propagation must not copy raw parent prompt text, task text, environment values, or workspace paths solely for correlation.
- The implementation extends `subagent_stop` or an equivalent delegation evidence seam when feasible with `child_session_id`, `child_task_id`/`subagent_id`, `child_trace_id`, child status/exit reason, API call count, and a bounded tool-trace digest/summary.
- If a child trace/session reference is unavailable, the receipt explicitly records stable evidence-gap codes rather than silently omitting provenance.
- Tests cover parent delegate receipt, successful child reference/correlation when the substrate exposes it, fallback evidence-gap behavior when it does not, and delegation failure/error behavior.

### F5: Dogfood and documentation

**What:** Run one real Hermes task with receipts enabled and document what the receipts prove and what gaps remain.

**Acceptance criteria:**
- A dogfood run records receipts for a real task involving at least one registry tool and one agent-loop/direct or delegated action.
- Dogfood evidence is written to a durable note under `docs/research/` or `docs/dogfood/` and includes the exact config/profile used, sanitized receipt summary or excerpt, minimum receipt count observed, event/status counts, and evidence-gap summary.
- `/receipts status`, `/receipts tail`, and `/receipts gaps` or equivalent commands summarize recorded events and evidence gaps. These commands default to the current session/project where available, skip/report corrupt lines, and do not reveal previews unless previews are explicitly enabled.
- Documentation states the feature is passive/advisory only and lists remaining enforcement seams: pre-model tool schema filtering, richer subagent trace references, and future policy enforcement.
- Tests and dogfood notes show no hard `/route`, `/sprint`, or phase-gating claims are made by this P1 slice.

## Non-goals

- No hard phase gates or tool-schema filtering.
- No automatic model/tool routing decisions.
- No `/route` or `/sprint` workflow UX inside Hermes.
- No external tracing dependency such as Langfuse, LangSmith, Phoenix, or OpenTelemetry exporter in P1.
- No signing/HMAC/external anchoring requirement in P1. If hash chaining is deferred, v0 must say explicitly that receipts are best-effort and not tamper-evident.
- No new allow/deny/block behavior introduced by execution receipts. Receipt code may mirror existing Hermes outcomes, including `blocked`, but must not become an enforcement surface in P1.

## Dependencies

- Target implementation repo: `/Users/sma/.hermes/hermes-agent`.
- Existing spike artifacts in that repo: `plugins/skaffen-receipts/`, `tests/plugins/test_skaffen_receipts_plugin.py`, and P0 characterization tests/docs.
- Hermes plugin manager and hook system in `hermes_cli/plugins.py`.
- Hermes agent-loop tool execution paths in `run_agent.py`.
- Registry-dispatched tool path in `model_tools.py`.
- Delegation implementation in `tools/delegate_tool.py`.

## Open Questions

- Can Hermes propagate trace context to child agents with a small parameter/env seam, or should P1 record only child session references and stable evidence-gap codes?
- Which retention/rotation default is least surprising for a local JSONL sidecar: size-based rotation, count-based rotation, or explicit no-rotation-with-warning for v0?
- Which exact existing Hermes interruption paths can be mapped to `cancelled` and `timeout` without inventing behavior?

## Chosen Defaults for P1

- Hook: `execution_receipt`.
- Receipt type for this slice: `tool_complete`.
- Storage: `$HERMES_HOME/execution-receipts/receipts.jsonl`, local-only, owner-only permissions where supported.
- Preview behavior: off by default; allowlisted/configured only.
- Integrity: best-effort v0 with sequence/corrupt/dropped reporting; hash chaining can be reserved but is not required.
- Enforcement: none. Receipts observe existing outcomes only.

## Success Metrics

- Existing P0 tests continue to pass after rename/reframe.
- New tests prove `execution_receipt` exact-once hook emission across registry, direct agent-loop, invalid-tool, invalid-JSON, blocked/error, concurrent, and delegation parent paths.
- Receipt plugin remains fail-open: plugin errors never alter agent execution results.
- Receipt plugin tests prove disabled/default mode, enabled mode, redaction canaries, corrupt-line recovery, writer failure/fail-open status reporting, sequence-number uniqueness, and command summaries.
- Dogfood receipts are sufficient to reconstruct the high-level action timeline without reading the original transcript or exposing raw secrets.

Alignment: This directly supports “every action produces evidence” while keeping authority passive until evidence quality is proven.

Conflict/Risk: The work touches Hermes core from a Sylveste-tracked bead; keep changes small, test-first, compatibility-preserving, and explicitly advisory.
