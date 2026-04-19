# fd-venetian-avogadori-di-comun-genealogical-registry — F5 Brainstorm Findings

**Target:** `docs/brainstorms/2026-04-07-interweave-f5-named-query-templates-brainstorm.md`
**Agent:** fd-venetian-avogadori-di-comun-genealogical-registry (Venetian Avogadori di Comun: catalog-of-catalogs discipline, dead-reference handling, self-describing registry)
**Track:** D (Esoteric)
**Decision Lens:** Evaluates whether the template registry maintains strict non-ownership of source data (Avogadori never copied parish records into the Libro d'Oro), handles partial source failures with explicit lacuna annotations, enforces join ordering via canonical ID resolution before fan-out, and whether TemplateRegistry.list() is self-describing without requiring Python class imports.

---

## Finding V-1: Shadow caching not prohibited by design; `bead_context` "full context graph" risks implicit materialization

**Severity: P1**
**File:** `docs/brainstorms/2026-04-07-interweave-f5-named-query-templates-brainstorm.md` — Key Decisions section, "`QueryResult` dataclass with entities, relationships, metadata" and `bead_context` description ("returns the full context graph")

The brainstorm states templates "compose existing primitives" and never own entity data. But the design does not prohibit caching. `bead_context` is described as returning "the full context graph: related files, sessions, actors, findings, dependencies" — the phrase signals a complete in-memory assembly of cross-system data. Nothing in the proposed `QueryTemplate` ABC constrains implementations from storing this assembled graph in a module-level or class-level dict between invocations.

**Failure scenario:** A developer adds `_cache: dict[str, QueryResult] = {}` to `bead_context.py` for performance (subprocess JSON round-trips are expensive). When bead `sylveste-5b7` is closed and its status changes in beads, `bead_context("sylveste-5b7")` returns cached "open" status. An agent uses this stale context to plan follow-on work. The catalog-of-catalogs contract is violated: the template layer now holds a shadow copy that disagrees with the authoritative source.

**Fix (one constraint, not a rewrite):** Add to the `QueryTemplate` ABC docstring: "Implementations MUST NOT persist results from `execute()` across invocations. The template layer owns no entity data — it is a composition engine only." Mirror interweave's existing finding-aid test in CLAUDE.md: if this template file is deleted, crosswalk, engine, and connectors still reflect correct state.

---

## Finding V-2: `QueryResult` has no gap/lacuna annotation; partial source failures produce silent omissions

**Severity: P1**
**File:** `docs/brainstorms/2026-04-07-interweave-f5-named-query-templates-brainstorm.md` — Key Decisions section, "`QueryResult` dataclass with entities, relationships, metadata, not raw dicts"

The brainstorm proposes `QueryResult` with `entities`, `relationships`, `metadata` fields. There is no `gaps` or `partial_sources` field. The existing `BeadsConnector._harvest_broad()` (`interverse/interweave/src/interweave/connectors/beads.py:67-115`) already returns `HarvestResult(errors=["bd list --all --json failed"])` when `bd` is unavailable. When `bead_context` calls the beads connector and receives this error, there is no mechanism in `QueryResult` to annotate "bead-specific properties unavailable." The template would return entities from crosswalk only, with no indication that title, status, priority, labels are absent.

**Failure scenario:** `bd` daemon is restarting (this happens; see `beads-troubleshooting.md` in memory). An agent calls `bead_context("sylveste-5b7")`. The template populates entities from crosswalk (the bead entity is indexed) but gets no bead properties. `QueryResult` shows the bead as an entity with empty properties. The agent interprets this as "bead has no properties yet" rather than "bead data is temporarily unavailable." It proceeds with incomplete context.

**Fix:** Add `gaps: list[SourceGap]` to `QueryResult`, where `SourceGap = dataclass(subsystem: str, reason: str, affected_entity_types: list[str])`. Templates populate `gaps` when a connector returns errors rather than silently omitting that subsystem's data. Agents can check `result.gaps` before treating the result as authoritative.

---

## Finding V-3: Join ordering in `who_touched_file` is unspecified; parallel fan-out risks merging on unresolved file paths

**Severity: P1**
**File:** `docs/brainstorms/2026-04-07-interweave-f5-named-query-templates-brainstorm.md` — query #1 `who_touched_file`, "Joins: crosswalk (file entity) + cass (sessions) + beads (work items)"

The brainstorm specifies the three data sources for `who_touched_file` but not their join order. The current crosswalk API (`interverse/interweave/src/interweave/crosswalk.py:59`) provides `resolve(subsystem, subsystem_id)` — there is no `resolve_by_path()` method. The cass connector (`connectors/cass.py:79`) registers sessions under `cass:{session_id}` with `workspace` and `source_path` as string properties, not as indexed crosswalk lookup keys.

If a template queries cass for sessions touching `/src/interweave/engine.py` and crosswalk for the same path in parallel, it must merge on the path string before confirming that `cass:abc123`'s `source_path` corresponds to the same crosswalk entity as `beads:file:src/interweave/engine.py`. Two sessions may reference `/src/foo.py` in different workspaces (different repositories) as canonically distinct files. Merging on path string alone produces false actor-to-file attributions.

**Fix:** Specify in the `QueryTemplate` ABC contract (docstring or type annotation) that `execute()` MUST call `crosswalk.resolve()` on all input identifiers before fanning out to subsystem connectors. The resolved `CanonicalID` must be the join key. For `who_touched_file`: resolve the file path to a canonical ID via crosswalk first; then query cass and beads using the canonical ID as the filter, not the raw path string.

---

## Finding V-4: TemplateRegistry.list() will require Python class imports to extract `parameters_schema()`

**Severity: P2**
**File:** `docs/brainstorms/2026-04-07-interweave-f5-named-query-templates-brainstorm.md` — Key Decisions section, "Registry pattern — `TemplateRegistry` mirrors `ConnectorRegistry`"

The existing `ConnectorRegistry.list()` (`interverse/interweave/src/interweave/connector.py:91-93`) returns `list[Connector]` — live instances. If `TemplateRegistry` follows this pattern, listing available templates requires importing every template class. The Go MCP adapter would need to spawn a Python subprocess just to enumerate tools for MCP tool listing — a cost incurred on every client connection.

At 8 templates this is one subprocess at startup. As the template set grows (the brainstorm notes 8 templates covers "all 5 type families and most of the 7 interaction rules" — implying future expansion), this becomes a multi-second initialization on every tool listing request.

**Fix:** Add a `TemplateManifest` dataclass (`name: str, description: str, parameters_schema: dict`) registered separately from the template class instance. `TemplateRegistry.list_manifests()` returns manifests as pure data (JSON-serializable, no class import). The Go adapter reads manifests at startup via a single subprocess call and caches them; it spawns a fresh subprocess only for `execute()` dispatch.

---

## Finding V-5: `bead_context` traversal depth is unbounded

**Severity: P3**
**File:** `docs/brainstorms/2026-04-07-interweave-f5-named-query-templates-brainstorm.md` — query #2 `bead_context`, "returns the full context graph: related files, sessions, actors, findings, dependencies"

For large epics (e.g., `sylveste-46s` referenced in interweave's CLAUDE.md), `bead_context` could fan out to dozens of child beads, hundreds of sessions, and thousands of file entities. The brainstorm defers pagination to F6 but does not specify a traversal depth limit. An unbounded graph traversal would produce a payload too large for useful agent consumption.

**Recommendation:** Add a `depth: int = 1` parameter to `bead_context.parameters_schema()` to limit relationship traversal depth. Default 1 means direct relationships only; depth 2 includes one hop of transitively related entities. This parameter also serves as a design exemplar for other graph-traversal templates (`entity_relationships`, `related_artifacts`, `entity_timeline`).
