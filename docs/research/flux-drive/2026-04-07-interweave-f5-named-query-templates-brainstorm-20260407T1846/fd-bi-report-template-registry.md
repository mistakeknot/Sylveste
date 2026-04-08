### Findings Index
- P1 | BI-1 | "What We're Building" | QueryResult lacks connector status enumeration — empty result indistinguishable from error-absent
- P1 | BI-2 | "Key Decisions" | No versioning mechanism for QueryTemplate result schema — MCP tool schema changes break agent consumers silently
- P1 | BI-3 | "Key Decisions" | Result entity identifiers unspecified — subsystem-native IDs in QueryResult will break cross-template query chaining
- P2 | BI-4 | "What We're Building" | TemplateRegistry population not auto-discovered — manual __init__.py imports create silent registration gaps
- P2 | BI-5 | "Open Questions" | Execution timeout allocation across subsystem calls not addressed — slow cass connector can time out entire multi-join template
- P3 | BI-6 | "What We're Building" | 8-template initial set derived from ontology coverage, not observed agent query patterns — risk of gaps causing ad-hoc cross-system queries outside template layer
Verdict: needs-changes

### Summary
The F5 brainstorm presents a coherent template registry design that mirrors existing connector patterns well. Three structural gaps require resolution before implementation: (1) QueryResult's metadata field must distinguish connector error states from empty results, (2) result entity identifiers must be canonical crosswalk IDs not subsystem-native IDs, and (3) the TemplateRegistry needs auto-discovery rather than manual imports. Template versioning is absent from the design — an omission that will cause MCP tool schema breakage as templates evolve. The execution timeout model is deferred with no protocol proposed, creating latency-budget risk for multi-join templates like entity_timeline.

### Issues Found

BI-1. P1: QueryResult lacks connector status enumeration — empty result indistinguishable from error-absent

The brainstorm defines `QueryResult` as "a dataclass with entities, relationships, metadata" (Key Decisions, bullet 5) but does not specify what `metadata` carries. The Severity Calibration scenario in this agent's spec calls out the exact failure: `bead_context` joins beads + crosswalk + cass; if cass returns an error, the template can only return a QueryResult with the sessions field empty. An agent consuming this result has no way to distinguish "no sessions worked on this bead" from "cass was unreachable." The brainstorm's "Structured result type — QueryResult dataclass with entities, relationships, metadata, not raw dicts" is the right direction but metadata must be typed, not a free-form dict.

Smallest fix: Add a `source_status: dict[str, Literal['ok','empty','error','skipped']]` required field to QueryResult's metadata specification in the brainstorm's Key Decisions section. This is a one-line addition to the protocol spec before implementation begins.

BI-2. P1: No versioning mechanism for QueryTemplate result schema — MCP tool schema changes break agent consumers silently

The Key Decisions section lists the TemplateRegistry pattern as mirroring ConnectorRegistry (register, get, list) but neither the registry nor the template protocol includes a version attribute. When a QueryTemplate's result schema evolves (new relationship types, renamed entity fields, removed connectors), the Go MCP adapter exposes the new schema to all calling agents simultaneously with no migration path. Agents that cached query results or built logic around prior schema shapes will receive unexpected data. BI report template registries that omit versioning create exactly this problem at scale.

Smallest fix: Add `version: str` to the `QueryTemplate` ABC specification and a `schema_version: str` field to `QueryResult`. The registry can expose both as part of the MCP tool schema so agents can detect schema changes. This is a one-field addition to the protocol spec.

BI-3. P1: Result entity identifiers unspecified — subsystem-native IDs in QueryResult will break cross-template query chaining

The brainstorm lists `who_touched_file` as returning "all actors (agents, humans) that modified it, with session context and timestamps. Joins: crosswalk (file entity) + cass (sessions) + beads (work items)." It does not specify what ID format the returned actor entities carry. If the implementation uses cass's native session UUID as the actor identifier in the result, an agent that passes this ID as input to `actor_activity` will receive format-mismatch errors when cass changes its ID format (see Severity Calibration scenario BI-1 in this agent's spec). The crosswalk exists precisely to provide canonical IDs — the template layer must use them in results, not the underlying connector IDs.

Smallest fix: Add a one-line decision to the Key Decisions section: "QueryResult entity identifiers use canonical crosswalk IDs — no subsystem-native IDs (cass UUIDs, beads hex IDs) appear in the result schema."

BI-4. P2: TemplateRegistry population not auto-discovered — manual __init__.py imports create silent registration gaps

The brainstorm says "each template lives in its own file under `src/interweave/templates/`, mirroring the `connectors/` package structure." If ConnectorRegistry uses the same manual-import pattern, the same gap exists there. But for templates that are exposed as MCP tools, a missing registration is invisible until an agent attempts to call a tool by name and receives "tool not found" — there is no startup validation that expected templates are present. Python's `__init_subclass__` hook or `ABCMeta` registry pattern would auto-register any QueryTemplate subclass defined in the package, eliminating the dependency on manual imports.

Smallest fix: Note in the Key Decisions section: "TemplateRegistry uses `__init_subclass__` auto-registration rather than manual imports — any QueryTemplate subclass in the templates/ package is automatically registered."

BI-5. P2: Execution timeout allocation across subsystem calls not addressed — slow cass connector can time out entire multi-join template

Open Question 1 defers the Go↔Python bridge decision. Open Question 2 defers caching to F6. Neither addresses timeout budgets for the constituent subsystem calls inside `execute()`. Templates like `entity_timeline` join crosswalk history + identity chain + multiple connectors. If cass is slow (indexing, high load), the entire `entity_timeline` call blocks with no partial-result option. BI reporting platforms that join live operational data always define per-source timeout budgets and return partial results with a timeout flag rather than blocking on the slowest source.

Smallest fix: Add to Open Questions: "Timeout budget: should execute() allocate per-connector timeouts (e.g., 2s cass, 1s beads, 500ms crosswalk) and return partial results with a timeout flag in metadata.source_status?"

BI-6. P3: 8-template initial set derived from ontology coverage, not observed agent query patterns — risk of coverage gaps causing ad-hoc queries

The brainstorm justifies the 8 templates as covering "all 5 type families and most of the 7 interaction rules." This is schema-driven coverage, not usage-driven coverage. BI template registries that are designed to cover the schema end up with templates that no one uses, while real query patterns get answered by ad-hoc joins outside the layer. The brainstorm does not cite any observed agent query patterns (e.g., from cass session logs showing what cross-system lookups agents currently perform manually) as the basis for the initial template set.

Suggestion: Before finalizing the 8 templates, run a quick query against cass session logs to identify the top 5-10 cross-system lookup patterns agents currently perform without template support. Use those as the ground truth for the initial template set.

### Improvements

BI-IMP-1. Add a `QueryResult.metadata` typed dataclass spec to Key Decisions — free-form dict metadata fields lead to inconsistent key naming across templates and breaks monitoring consumers.

BI-IMP-2. Document the ConnectorRegistry pattern in the brainstorm for comparison — if ConnectorRegistry already uses auto-discovery, note it; if it uses manual imports, note that F5 should improve on that pattern.

BI-IMP-3. The Go↔Python subprocess bridge (Open Question 1) should note that stderr vs stdout must be separated clearly — Python exceptions printed to stdout will corrupt the JSON protocol.
<!-- flux-drive:complete -->
