# fd-syriac-masora-vocalization-intermediary-layer — F5 Brainstorm Findings

**Target:** `docs/brainstorms/2026-04-07-interweave-f5-named-query-templates-brainstorm.md`
**Agent:** fd-syriac-masora-vocalization-intermediary-layer (Syriac Eastern Masora: intermediary layer contract, reconstructibility from documented primitives, protocol standardization, usage metadata)
**Track:** D (Esoteric)
**Decision Lens:** Evaluates whether the template layer transforms without modifying the base (templates depend on primitives; primitives function without templates), whether template join logic is reconstructible from the documented 7 interaction rules and 5 type families, whether the protocol enforces true standardization across implementations, and whether the layer collects usage metadata enabling evidence-based evolution.

---

## Finding S-1: Go MCP adapter requires new subprocess dispatch capability that does not exist and serves no purpose outside the template layer

**Severity: P0**
**File:** `docs/brainstorms/2026-04-07-interweave-f5-named-query-templates-brainstorm.md` — Open Questions #1, "Go ↔ Python bridge: Option (a) Python CLI entrypoint that the Go adapter shells out to"
**Referenced file:** `interverse/interweave/internal/adapter/mcp.go` (entire file)

The brainstorm proposes the Go MCP adapter shells out to Python for template execution. The existing adapter (`mcp.go:1-160`) handles attp session management, intermute bridging, and interlock conflict resolution. It has no subprocess dispatch capability. Adding Python subprocess dispatch to `mcp.go` means the adapter acquires a new dependency — that Python is available in the process environment and that a Python entrypoint exists at a known path — that serves no purpose outside the template layer.

This is the Syriac P0: the intermediary layer (templates) requires the base layer (Go adapter) to grow a capability it does not have and that serves no purpose outside the template layer. The adapter is being modified to accommodate the annotation layer — the vocalization points are altering the consonantal text.

**Failure scenario:** The Go adapter is deployed in a containerized environment where Python is not available (not uncommon for Go binaries distributed as single-file executables). Template dispatch fails at runtime with "python3: not found." The Go adapter's existing capabilities (intermute, interlock, attp) are unaffected — but templates are silently unavailable with no clear error to the agent calling MCP tools. The issue is only discovered when an agent calls `who_touched_file` and receives a tool error.

**Fix:** Implement templates as an independent Python MCP server that operates without modification to the Go adapter. Agents connect to both the Go adapter (for intermute/interlock/attp) and the Python MCP server (for named query templates) as separate MCP servers. The Go adapter is not involved in template dispatch. This preserves the adapter's unidirectional dependency (adapter depends on attp/intermute/interlock; templates depend on crosswalk/connectors/engine; nothing crosses). If the Python MCP server is unavailable, the Go adapter continues operating normally.

---

## Finding S-2: Template join logic is not reconstructible from the documented 7 interaction rules; templates embed undocumented relational semantics

**Severity: P1**
**File:** `docs/brainstorms/2026-04-07-interweave-f5-named-query-templates-brainstorm.md` — query #2 `bead_context`, "Joins: beads connector + crosswalk links + engine relationships"

The 7 interaction rules in `rules.py` define valid relationship *types* between *family pairs* (e.g., ACTOR↔PROCESS yields `executes, dispatches, delegates, monitors`). They do not define which connectors to call, in what order, or how to assemble a cross-system graph for a given query. The join logic in `bead_context` — call beads connector, query crosswalk links, run engine relationships — is not derivable from `rules.py`, `families.py`, or the existing connector interfaces.

Reconstructibility test: if `bead_context.py` were deleted, could a developer reconstruct it from the documented primitives? No. The developer would know that beads entities are of family PROCESS, and that PROCESS has productivity (ACTOR↔PROCESS), transformation (PROCESS↔ARTIFACT), and evidence-production (any↔EVIDENCE) rules. But the specific query — "given bead ID, resolve it via crosswalk, call BeadsConnector for properties, query engine for all entities related to this bead's canonical ID" — is not derivable from these rules. It requires domain knowledge encoded only in the template.

**Failure scenario:** A new developer joins the interweave team. The template codebase is lost (repository corruption, accidental deletion). The developer can reconstruct the engine, connectors, crosswalk, and families from their documentation. They cannot reconstruct the 8 named queries because the join logic is undocumented outside the template code itself. The template layer has become a source of truth rather than a systematic derivation from existing primitives.

**Fix:** Add a "Template specification" section to the brainstorm (and eventually to each template's docstring) that documents for each query: (1) which type families are traversed and in what order, (2) which interaction rules govern each join step, (3) which connectors supply data for which family. `bead_context` spec: "Resolves bead canonical ID via crosswalk. Applies transformation rule (PROCESS↔ARTIFACT) to find files modified. Applies productivity rule (ACTOR↔PROCESS) to find actors. Applies evidence-production rule to find findings. BeadsConnector provides PROCESS properties; CassConnector provides session context." This makes templates reconstructible from their specification.

---

## Finding S-3: `QueryTemplate` ABC enforces method presence but not behavioral contracts; implementations will diverge in error handling

**Severity: P1**
**File:** `docs/brainstorms/2026-04-07-interweave-f5-named-query-templates-brainstorm.md` — Key Decisions section, "Python protocol class — consistent with connector.py, families.py, rules.py patterns"

The brainstorm models `QueryTemplate` on the existing `Connector` ABC (`connector.py:50-73`). The `Connector` ABC enforces method presence (`name`, `get_observation_contract`, `harvest`) but not behavioral contracts. The existing connectors diverge: `BeadsConnector._harvest_broad()` logs warnings and returns `HarvestResult(errors=[...])` on failure; `CassConnector.harvest()` catches `CalledProcessError`, `FileNotFoundError`, `TimeoutExpired` together and returns `None` (line 30), which the caller must handle. This divergence is tolerable for connectors because each connector wraps a different subsystem with different failure modes. It is not tolerable for templates, which are the unified public interface.

An agent calling any named query template should receive consistent behavior: if parameter validation fails, the response is the same type with an error field, not sometimes a `ValueError` and sometimes an empty `QueryResult`. If a source connector is unavailable, the response indicates which source failed, not sometimes a `gaps` list and sometimes an exception.

**Failure scenario:** Template A (implemented by developer X) raises `ValidationError` when `who_touched_file` receives a non-existent file path. Template B (implemented by developer Y) returns `QueryResult(entities=[], relationships=[], metadata={"warning": "path not found"})`. The Go MCP adapter must handle both exception propagation and empty-result interpretation. It cannot apply a uniform "did this query succeed" check without inspecting each template's behavior individually. The Syriac equivalent: masoretic manuscripts where each scribe uses different symbols for the same vocalization — the reader must learn each scribe's notation separately.

**Fix:** Add two abstract methods to `QueryTemplate` ABC: `validate_parameters(params: dict) -> list[ValidationError]` (called before `execute()`, returns typed errors rather than raising); and specify that `execute()` MUST return `QueryResult` (never raise on recoverable failures). Add `error: str | None` and `gaps: list[SourceGap]` to `QueryResult` as standard fields that all templates populate consistently.

---

## Finding S-4: No template usage metadata; the template layer cannot evolve from call patterns

**Severity: P2**
**File:** `docs/brainstorms/2026-04-07-interweave-f5-named-query-templates-brainstorm.md` — entire document (absence)

The brainstorm does not specify instrumentation for the template layer. The existing connectors record no usage metrics either — but connectors are internal harvest tools, not public MCP interfaces. Named query templates ARE the public interface: agents call them directly. Without usage metadata, there is no signal for which templates are frequently called, which are never called (candidates for removal), which are slow (candidates for optimization), or which consistently return empty results (indicating coverage gaps in the connectors).

The Syriac marginal frequency counts — tracking how many times a rare word form appears across the corpus — are metadata about the metadata. The template layer needs the equivalent: call frequency, query latency, result size, and empty-result rate per template.

**Fix:** Add `TemplateRegistry.record_invocation(template_name: str, duration_ms: int, result_entity_count: int, gap_count: int, success: bool)`. Store to a simple SQLite table mirroring the crosswalk's storage pattern (`storage.py`). Expose a `template_stats` query in a future F6 or as a special registry query. This mirrors the Masora's marginal frequency apparatus: standardized metadata in a separate layer that enables corpus-level understanding without modifying the primary text.

---

## Finding S-5: `entity_relationships` may add a layer without adding meaning — raw engine call is already directly accessible

**Severity: P3**
**File:** `docs/brainstorms/2026-04-07-interweave-f5-named-query-templates-brainstorm.md` — query #4 `entity_relationships`

The Syriac test for whether an intermediary layer adds value: does it disambiguate something that is already ambiguous in the base text? For `entity_relationships`: given a canonical ID, it calls `crosswalk.get()` to find the entity type, then calls `engine.valid_relationships(type_a, type_b)`. The engine's `valid_relationships()` function (`engine.py:13-39`) is already directly callable. The template adds only the crosswalk lookup (one extra step).

Compare with `who_touched_file`: this genuinely disambiguates by composing actor resolution, session data, and modification history — none of which is directly accessible from a single primitive call. `entity_relationships` does not analogously disambiguate; it wraps a two-step operation that a developer could inline.

**Recommendation:** Evaluate whether `entity_relationships` should be merged into a richer `entity_context` template that returns the full entity record from crosswalk plus valid relationships in one call. Alternatively, if `entity_relationships` is retained as a standalone template, its description should explicitly state "use this when you have a canonical ID and need to know what relationship types are valid before querying — it does not return linked entities, only valid relationship types." The current description ("returns all valid relationships AND linked entities") suggests it returns populated relationship data, which would require additional crosswalk queries — clarify scope.
