### Findings Index
- P1 | CDS-1 | "What We're Building" | related_artifacts has no result limit or relevance ranking — high-degree nodes return unbounded result sets that exhaust agent context budgets
- P1 | CDS-2 | "Key Decisions" | QueryResult.metadata has no per-source freshness timestamps — agents act on stale crosswalk data without knowing it
- P2 | CDS-3 | "Open Questions" | No template overlap governance mechanism — registry will accumulate redundant templates as it grows, causing agent confusion
- P2 | CDS-4 | "What We're Building" | Template invocation contexts undocumented — agents cannot determine which templates are appropriate for action-oriented vs. exploratory queries
- P3 | CDS-5 | "Key Decisions" | No usage tracking or feedback loop — TemplateRegistry has no mechanism to detect stale, misused, or noisy templates over time
Verdict: needs-changes

### Summary
The F5 brainstorm's template design omits two result-quality controls that are required for safe agent consumption. First, `related_artifacts` and `entity_relationships` return graph traversals with no result limits — a popular utility module could return hundreds of weakly-related artifacts, exhausting an agent's context budget before useful work begins. Second, `QueryResult.metadata` does not carry data freshness signals, so agents act on crosswalk cache data that may be 45+ minutes stale without any warning. The template invocation context problem — which templates are appropriate for action-oriented vs. exploratory queries — is also unaddressed, creating conditions for agents to invoke the wrong template for their use case.

### Issues Found

CDS-1. P1: related_artifacts has no result limit or relevance ranking — high-degree nodes return unbounded result sets that exhaust agent context budgets

The brainstorm defines `related_artifacts` as returning "structurally related artifacts via the structure interaction rule: imports, dependencies, references, parent-child." This is an unconstrained graph traversal. For a central utility module like crosswalk.py, the structure interaction rule will return every file in the codebase that imports it. The Severity Calibration scenario: 47 artifacts returned, no relevance scoring, agent treats all 47 as equally relevant, exhausts token budget before completing the task.

The same problem applies to `entity_relationships` (relational calculus engine, potentially returning all related entities). Both templates need a maximum result limit and relevance ranking.

Smallest fix: Add to the QueryTemplate ABC specification: "execute() accepts an optional `max_results: int = 20` parameter. Templates that perform graph traversals return results ranked by relationship_strength (a float 0.0-1.0) and truncate at max_results, with metadata.total_results_before_truncation recording the untruncated count."

CDS-2. P1: QueryResult.metadata has no per-source freshness timestamps — agents act on stale crosswalk data without knowing it

The brainstorm lists crosswalk as a cache that is indexed asynchronously. `bead_context`, `entity_timeline`, and most multi-join templates rely on crosswalk. An agent that invokes `bead_context` for an actively worked bead will receive a result based on crosswalk data from the last index run (potentially 45+ minutes ago). The Severity Calibration scenario: agent makes a conflicting edit to a file that an active session is also editing, based on stale bead_context data. The agent has no indication that crosswalk is 45 minutes old.

This is the CDS stale-data-for-live-decision failure — a drug interaction check against a medication list that hasn't been updated since admission.

Smallest fix: Add `data_freshness: dict[str, DataFreshness]` to QueryResultMetadata, where DataFreshness includes `last_indexed: datetime` and `age_seconds: int`. Add a `staleness_warning: list[str]` field populated when any contributor's data exceeds a template-defined `freshness_sla_seconds`. Both fields should be part of the typed QueryResultMetadata dataclass noted in REG-3.

CDS-3. P2: No template overlap governance mechanism — registry will accumulate redundant templates as it grows, causing agent confusion

The brainstorm launches with 8 templates. As interweave evolves, new templates will be added. Without a governance mechanism for detecting overlapping template scope, the registry will accumulate redundant options. The Severity Calibration scenario: a new `actor_files_touched` template covers a subset of `actor_activity` with different parameter names; agents now have two valid options for similar queries and begin invoking the wrong one. CDS rule governance tracks which rules are overridden, ignored, or acted on; template governance needs the equivalent.

Smallest fix: Add to the TemplateRegistry design: "At registration time, the registry checks whether the new template's canonical_question_form overlaps with existing templates using a simple keyword intersection check. Overlapping registrations require a `replaces: str` field naming the template being superseded, or raise TemplateOverlapWarning."

CDS-4. P2: Template invocation contexts undocumented — agents cannot determine which templates are appropriate for action-oriented vs. exploratory queries

The brainstorm lists templates as a flat registry with no invocation context tags. An agent that needs to decide "what should I do next on this bead?" would logically invoke `bead_context` (action-oriented). An agent exploring "what is related to this entity?" might reasonably invoke `entity_relationships`, `related_artifacts`, or `entity_timeline` without a basis for choosing. CDS alerts that fire outside the context where the clinician can act on them are the analog.

`actor_activity` and `bead_context` are action-oriented (the result informs a decision about what to do next). `entity_relationships`, `entity_timeline`, `related_artifacts` are exploratory (the result provides background understanding). These different use cases should be documented as `invocation_context` tags on each template.

Smallest fix: Add `invocation_context: Literal['action-oriented', 'exploratory', 'audit']` as an attribute to the QueryTemplate ABC. Document in the brainstorm which of the 8 templates falls into each category.

CDS-5. P3: No usage tracking or feedback loop — TemplateRegistry has no mechanism to detect stale, misused, or noisy templates over time

The brainstorm states "templates compose existing primitives without adding new storage." This is correct for query execution, but usage metadata is needed for governance. The TemplateRegistry should track invocation_count, empty_result_rate, and median_result_size per template. A high empty_result_rate signals a scope mismatch (agents are invoking the template for entities outside its scope). A high median_result_size signals a noise problem (related_artifacts returning unbounded results). Without this feedback loop, the registry becomes a static artifact that accumulates stale templates.

Suggestion: Add to Key Decisions: "TemplateRegistry records invocation_count, empty_result_rate, and median_result_size per template in a lightweight SQLite log (matching the connector pattern of not adding new storage — reuse the crosswalk SQLite or a separate registry.db). A monitoring endpoint exposes these metrics."

### Improvements

CDS-IMP-1. Document `max_results` and `relationship_strength` as first-class concerns in the Key Decisions section — these are not implementation details but protocol-level constraints that the Go MCP adapter needs to expose in the tool schema so agents can pass them as parameters.

CDS-IMP-2. The brainstorm's "Open Question 4: Pagination" for entity_timeline and actor_activity is correctly identified. Recommend resolving this with cursor-based pagination (a `cursor: str` parameter returning a `next_cursor` in metadata) rather than limit/offset, which is fragile against insertions.
<!-- flux-drive:complete -->
