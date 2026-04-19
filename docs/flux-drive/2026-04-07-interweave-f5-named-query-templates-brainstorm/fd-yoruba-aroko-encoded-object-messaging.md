# fd-yoruba-aroko-encoded-object-messaging — F5 Brainstorm Findings

**Target:** `docs/brainstorms/2026-04-07-interweave-f5-named-query-templates-brainstorm.md`
**Agent:** fd-yoruba-aroko-encoded-object-messaging (Yoruba aroko: compositional query semantics, self-containment, typed response contracts, template disambiguation)
**Track:** D (Esoteric)
**Decision Lens:** Evaluates whether named query templates have compositional parameter semantics (different parameter combinations produce distinct query plans, not just post-hoc filters), whether `execute()` is fully self-contained without implicit context injection, whether response types are typed per-template, and whether template names + schemas are unambiguous from MCP tool listing alone.

---

## Finding A-1: All 8 templates share a single generic `QueryResult` type; response shape is opaque to agents at tool selection time

**Severity: P1**
**File:** `docs/brainstorms/2026-04-07-interweave-f5-named-query-templates-brainstorm.md` — Key Decisions section, "`QueryResult` dataclass with entities, relationships, metadata, not raw dicts"

The brainstorm specifies a single `QueryResult` type across all 8 templates: `{entities: [...], relationships: [...], metadata: {...}}`. An agent calling `who_touched_file` and an agent calling `entity_timeline` both receive the same envelope. The agent cannot determine from the MCP tool schema (which describes only input parameters) what the payload will contain.

`who_touched_file` should return actors with session IDs and modification timestamps. `entity_timeline` should return events ordered chronologically with event types. `related_artifacts` should return artifact nodes with structural relationship labels (`imports`, `depends-on`, `parent-child`). If all return the same generic bag, the agent must inspect content and infer schema — which defeats the "one MCP tool per query" discoverability argument explicitly stated in the "Why This Approach" section.

**Failure scenario:** An agent calls `who_touched_file("/src/interweave/engine.py")` expecting to receive a list of actors with timestamps. It receives `{entities: [{canonical_id: "cass:abc123", entity_type: "session", ...}], relationships: [...]}`. The entity is a session, not an actor — the agent must infer that sessions are proxies for actors here. It cannot do this from the MCP tool schema alone. The "individual tools mean agents see `who_touched_file` in their tool list with a typed schema" promise (brainstorm, "One MCP tool per query" section) is broken.

**Fix:** Define template-specific result types that declare their payloads: `WhoTouchedFileResult(actors: list[Actor], sessions: list[SessionRef], files: list[FileRef])`, `EntityTimelineResult(events: list[TimelineEvent])`, etc. Map these to MCP tool `outputSchema` declarations. Agents know the response shape at tool selection time, not after payload inspection.

---

## Finding A-2: `entity_relationships` and `related_artifacts` are not disambiguated from their MCP tool schemas alone

**Severity: P1**
**File:** `docs/brainstorms/2026-04-07-interweave-f5-named-query-templates-brainstorm.md` — queries #4 and #7

`entity_relationships` (#4): "Given a canonical ID, returns all valid relationships and linked entities using the relational calculus engine. Pure engine query over crosswalk data."

`related_artifacts` (#7): "Given an artifact (file, module, function), returns structurally related artifacts via the structure interaction rule: imports, dependencies, references, parent-child."

Both accept a canonical ID (or artifact identifier) and return relationship/entity lists. The distinction — full 7-rule engine vs. ARTIFACT↔ARTIFACT structure rule only — is meaningful to a developer who has read the brainstorm but is opaque in a tool schema description. An agent choosing between these to find code dependencies cannot determine from tool listing alone which to call.

**Failure scenario:** An agent needs to find all artifacts that import `engine.py`. It selects `entity_relationships` (more general-sounding) rather than `related_artifacts` (scoped to structure rule). `entity_relationships` returns relationships including actor stewardship, process transformation, and evidence production — a much larger result set than the agent needed. The agent must post-filter, negating the "typed parameters and structured cross-system context back" value proposition.

**Fix:** The MCP tool descriptions must encode the distinction operationally, not architecturally. `entity_relationships`: "Returns all relationship types applicable to this entity across all 5 type families — use when you need the complete relationship map for an entity." `related_artifacts`: "Returns only code structure relationships (imports, depends-on, references, blocks, parent-child) between artifacts — use for code dependency graphs and impact analysis." The description disambiguates by use-case. Additionally, evaluate whether these two templates justify separate registrations vs. a single `entity_context` template with a `rule_scope` parameter (see Finding S-5 for the complementary analysis).

---

## Finding A-3: `execute()` connector dependency is not declared in the template interface; templates are not self-contained

**Severity: P2**
**File:** `docs/brainstorms/2026-04-07-interweave-f5-named-query-templates-brainstorm.md` — Key Decisions section, "Templates compose existing primitives — they call crosswalk, engine, connectors"

The brainstorm specifies `QueryTemplate` ABC with `execute()` as a method. The existing `Connector` ABC makes its crosswalk dependency explicit: `harvest(self, crosswalk: Crosswalk, mode: HarvestMode)` — the crosswalk is passed as a parameter, not accessed as a module-level global. The proposed `execute(parameters)` signature does not include crosswalk or connector registry as parameters.

If connectors are accessed via module-level globals or process-level imports within `execute()`, templates depend on implicit runtime state not declared in `parameters_schema()`. This means the MCP tool schema shown to agents is incomplete — the template requires state that is not described in its declared interface. In testing, mocking connectors requires patching module-level globals rather than injecting test doubles.

**Failure scenario:** A developer writes `execute()` that calls `ConnectorRegistry.get("beads")` on a module-level registry instance. In a test environment where the beads connector is not registered, `execute()` returns `None` from the connector call and silently returns an empty `QueryResult`. The test passes. In production, the registry is populated. The template behavior differs between test and production contexts because the dependency is invisible in the interface.

**Fix:** Mirror the connector pattern: `QueryTemplate.__init__(self, crosswalk: Crosswalk, connectors: ConnectorRegistry)`. Constructor injection makes all dependencies explicit and testable. `TemplateRegistry` initializes templates with the crosswalk and connector registry instances at registration time.

---

## Finding A-4: `who_touched_file` and `actor_activity` both return actor information; the distinction is not clear from names alone

**Severity: P2**
**File:** `docs/brainstorms/2026-04-07-interweave-f5-named-query-templates-brainstorm.md` — queries #1 and #5

`who_touched_file(path)` (#1): returns actors who modified a file.
`actor_activity(actor_id)` (#5): returns an actor's activity across subsystems including files touched.

These are inverses, which is legitimate. But an agent investigating "what work touched this file and who did it" may call `who_touched_file` and receive only modification actors — or may call `actor_activity` on each returned actor to get full context, not knowing that `who_touched_file` already joins sessions and beads. The overlap is not a collision but it creates selection ambiguity: when does an agent use the file-first query vs. constructing actor queries manually?

This is the aroko disambiguation problem: the same semantic need ("understand activity around this file") can be encoded with different starting objects. The wrapping material (template name + description) must encode the canonical entry point.

**Fix:** Add to `who_touched_file` description: "Use this as the entry point when you have a file and need actor context. Do not call actor_activity separately for each returned actor — the join is already done." Add to `actor_activity` description: "Use this when you have an actor and need their cross-subsystem footprint. If you are starting from a file, use who_touched_file instead."
