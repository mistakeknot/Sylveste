### Findings Index
- P1 | REG-1 | "Key Decisions" | Exception handlers in execute() will convert connector errors to empty results — no error taxonomy defined
- P1 | REG-2 | "What We're Building" | session_entities crosswalk resolution silently drops unresolved entities — no resolution_status field specified
- P2 | REG-3 | "Key Decisions" | QueryResult.metadata is a free-form dict — inconsistent key naming across templates breaks monitoring consumers
- P2 | REG-4 | "What We're Building" | No audit trail from query invocation to result — connector versions, crosswalk state, inference rules applied are unrecorded
- P2 | REG-5 | "Open Questions" | No declared latency SLAs per template — agents cannot make informed decisions between high-latency and low-latency alternatives
- P3 | REG-6 | "Key Decisions" | execute() determinism not specified — re-runs with same parameters can produce different relationship graphs
Verdict: needs-changes

### Summary
The F5 brainstorm's error handling design is underspecified in ways that will cause silent data loss. The critical gap is the absence of a defined error taxonomy: when a connector fails, the current design will produce empty results that are indistinguishable from genuine absence. This is the regulatory reporting equivalent of submitting a partial report as if it were complete. The metadata field needs to be a typed dataclass with required fields, not a free-form dict. The audit trail requirements — connector versions, crosswalk state at execution time, inference rules applied — are entirely absent from the design.

### Issues Found

REG-1. P1: Exception handlers in execute() will convert connector errors to empty results — no error taxonomy defined

The brainstorm states "templates compose existing primitives" (crosswalk, engine, connectors). It does not specify the error handling protocol for `execute()`. In the absence of a defined error taxonomy, the natural implementation will catch connector exceptions and return a QueryResult with whatever data was retrieved before the failure. The Severity Calibration scenario for this agent: `entity_timeline` template calls crosswalk; crosswalk SQLite is locked by concurrent write; `OperationalError` is raised; execute() catches it and returns an empty events list; the Go adapter serializes the empty result; the agent concludes the entity has no history.

This is the regulatory reporting "silent partial submission" failure — worse than an explicit error because consumers treat the result as authoritative.

Smallest fix: Add an error taxonomy to the Key Decisions section: "execute() raises `TemplateExecutionError(error_code, affected_connector)` for fatal connector failures rather than returning partial results. The Go adapter converts TemplateExecutionError to an MCP tool error response. Partial results are only returned when at least one connector succeeds AND the metadata.source_status records the failure for consumer inspection."

REG-2. P1: session_entities crosswalk resolution silently drops unresolved entities — no resolution_status field specified

The brainstorm defines `session_entities` as joining "cass connector + crosswalk" — cass returns file paths, crosswalk resolves them to canonical entity IDs. The design does not specify what happens when crosswalk cannot resolve a file path (e.g., recently created file not yet indexed). The natural implementation silently drops unresolved paths. The Severity Calibration scenario: session creates 3 new files; crosswalk hasn't indexed them yet; session_entities returns a result omitting those 3 files with no indication of the omission. The consuming agent treats the result as complete and misses 30% of the session's artifacts.

Smallest fix: Add `unresolved_entities: list[UnresolvedEntity]` as a required field in QueryResult — when crosswalk returns None for a resolution, the template includes the entity in `unresolved_entities` with `resolution_status='unresolved'` rather than silently dropping it. This is a one-field addition to the QueryResult spec.

REG-3. P2: QueryResult.metadata is a free-form dict — inconsistent key naming across templates breaks monitoring consumers

The brainstorm calls for a "QueryResult dataclass with entities, relationships, metadata" but specifies metadata only as a generic "not raw dicts" constraint. With 8 templates written by potentially different developers, the metadata dict will accumulate inconsistent key names: `source_connectors` vs `connectors_used` vs `connector_status`. A monitoring script that checks for partial results across all templates must handle all variants. This is the exact failure described in the Severity Calibration scenario for this agent (metadata key inconsistency).

Smallest fix: Define a `QueryResultMetadata` typed dataclass as part of the F5 spec with required fields: `source_status: dict[str, Literal['ok','empty','error','skipped']]`, `execution_timestamp: datetime`, `template_version: str`, `unresolved_entities: list[UnresolvedEntity]`. All templates must populate this dataclass, not a free-form dict.

REG-4. P2: No audit trail from query invocation to result — connector versions, crosswalk state, inference rules applied are unrecorded

The brainstorm does not address result provenance. When an agent acts on a `bead_context` result and makes a wrong decision, a developer cannot diagnose why the template returned what it did without re-running the query and hoping conditions are identical. Regulatory reporting requires an unbroken audit chain from source data to submitted result. For F5, the equivalent is: which connector versions were active, what the crosswalk returned before relationship resolution, and whether the engine applied inference rules that expanded the result beyond direct relationships.

Smallest fix: Add `query_provenance: QueryProvenance` to QueryResultMetadata with fields: `connector_versions: dict[str, str]`, `crosswalk_index_timestamp: datetime`, `inference_rules_applied: list[str]`. This does not require new storage — connectors can report their version, and crosswalk can report its last index timestamp.

REG-5. P2: No declared latency SLAs per template — agents cannot make informed decisions between high-latency and low-latency alternatives

The brainstorm defers caching to F6 and does not address latency. `entity_timeline` (crosswalk history + identity chain + connectors) is structurally much slower than `entity_relationships` (pure engine query). An agent operating under a response latency constraint has no basis for choosing between them. Regulatory submissions have hard deadlines; the F5 analog is agents that need results within a response budget choosing the wrong template and timing out.

Smallest fix: Add `estimated_latency_p50_ms: int` and `estimated_latency_p95_ms: int` as class attributes to the QueryTemplate ABC specification. Initial values can be estimates based on the number of subsystem joins; they become more accurate as the system is profiled.

REG-6. P3: execute() determinism not specified — re-runs with same parameters can produce different relationship graphs

The brainstorm notes that crosswalk is a cache that indexes asynchronously. Two invocations of `entity_timeline` with the same canonical ID at different times will return different results as the crosswalk cache updates. This is expected behavior — but the brainstorm does not specify whether QueryTemplate.execute() is documented as non-deterministic (time-sensitive query against live caches) or pseudo-deterministic (results valid as of execution_timestamp). Without this specification, consumers cannot reason about whether to cache query results or always re-run.

Suggestion: Add to Key Decisions: "QueryTemplate.execute() is documented as time-sensitive — results reflect subsystem state at execution_timestamp, not a stable snapshot. Consumers that need stable results should cache at the application layer."

### Improvements

REG-IMP-1. The Go↔Python subprocess bridge (Open Question 1) needs explicit stderr/stdout separation specified — Python exceptions or logging to stdout will corrupt the JSON protocol and may be silently parsed as malformed JSON rather than raising an error.

REG-IMP-2. Consider adding a QueryResult.is_complete() convenience method that returns False if any source_status is 'error' — this gives consumers a single boolean completeness check without needing to inspect the full metadata dict.
<!-- flux-drive:complete -->
