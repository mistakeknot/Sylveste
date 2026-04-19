---
artifact_type: brainstorm
bead: sylveste-5b7
stage: discover
---

# F5: Named Query Templates (MCP Tools)

## What We're Building

A template layer that exposes interweave's cross-system ontology as individual MCP tools. Each named query is a Python class implementing a `QueryTemplate` protocol, registered into a `TemplateRegistry`. Agents invoke these as standard MCP tools with typed parameters and get structured cross-system context back.

The template layer sits between the existing domain primitives (engine, crosswalk, connectors) and the Go MCP adapter. It answers questions like "who touched this file?", "what evidence exists for this bead?", and "show me all actors in this session" — queries that require joining data across subsystems.

### Initial Query Set (6-8 templates)

1. **who_touched_file** — Given a file path, returns all actors (agents, humans) that modified it, with session context and timestamps. Joins: crosswalk (file entity) + cass (sessions) + beads (work items).

2. **bead_context** — Given a bead ID, returns the full context graph: related files, sessions, actors, findings, dependencies. Joins: beads connector + crosswalk links + engine relationships.

3. **session_entities** — Given a session ID, returns all entities touched during that session: files modified, beads worked, findings produced. Joins: cass connector + crosswalk.

4. **entity_relationships** — Given a canonical ID, returns all valid relationships and linked entities using the relational calculus engine. Pure engine query over crosswalk data.

5. **actor_activity** — Given an actor identifier (agent name, human username), returns their recent activity across subsystems: sessions run, beads worked, files touched. Joins: actor resolution + crosswalk + connectors.

6. **evidence_for_entity** — Given any entity's canonical ID, returns all Evidence-family entities that reference it: findings, verdicts, metrics, discoveries. Uses the evidence-production interaction rule.

7. **related_artifacts** — Given an artifact (file, module, function), returns structurally related artifacts via the structure interaction rule: imports, dependencies, references, parent-child.

8. **entity_timeline** — Given a canonical ID, returns a chronological timeline of events: creation, modifications, relationship changes, lifecycle transitions. Aggregates crosswalk history + identity chain data.

## Why This Approach

### One MCP tool per query

Agents discover tools via MCP tool listing. Individual tools mean agents see `who_touched_file` in their tool list with a typed schema — they don't need to know template names or consult docs. This maximizes discoverability, which is the primary value prop for an ontology layer.

### Python protocol classes (not YAML, not decorators)

The existing codebase uses protocol/ABC patterns consistently: `Connector` ABC in connector.py, `EntityType` dataclass in families.py, `InteractionRule` dataclass in rules.py. A `QueryTemplate` ABC with `name`, `description`, `parameters_schema()`, and `execute()` fits naturally. Each template lives in its own file under `src/interweave/templates/`, mirroring the `connectors/` package structure.

### Registry pattern (like ConnectorRegistry)

`TemplateRegistry` mirrors `ConnectorRegistry` — register, get, list. This gives the MCP adapter a single entry point to enumerate available queries and dispatch execution. The Go adapter calls into Python (via subprocess stdin/stdout JSON protocol, matching how connectors already shell out to CLI tools).

## Key Decisions

- **One tool per query** over polymorphic — discoverability wins for an ontology layer
- **Python protocol class** — consistent with connector.py, families.py, rules.py patterns
- **Registry pattern** — `TemplateRegistry` raises `ValueError` on name collision (unlike `ConnectorRegistry` which silently overwrites — acceptable for 3 hardcoded connectors but not for an open template namespace). Includes `reset()` for test isolation.
- **Full ontology surface** (8 queries) — covers all 5 type families and most of the 7 interaction rules
- **Templates are stateless** — dependencies injected via `QueryContext` parameter to `execute()`, not stored as instance state. Matches `harvest(crosswalk, mode)` pattern.
- **Persistent Python worker process** for Go → Python bridge — JSON-RPC over stdin/stdout with newline framing. Per-call subprocess spawn is inappropriate for latency-sensitive MCP tools (400ms overhead per call) and deadlocks on responses >64KB. The Go adapter does NOT embed template dispatch — it proxies to the Python worker, preserving the intermediary-layer boundary.
- **Templates compose existing primitives** — they call crosswalk, engine, connectors. No new storage, no caching (catalog-of-catalogs principle).
- **All cross-subsystem joins must resolve through `Crosswalk.resolve()`** — direct ID string comparison across subsystems is prohibited. Templates receive a `Crosswalk` reference via `QueryContext`.
- **CanonicalID serializes as string** (`subsystem:native_id`) in JSON responses. Go-side deserializes via string split on first colon.
- **All datetimes use RFC 3339** (`2006-01-02T15:04:05.000000Z`). Python templates format with `datetime.isoformat() + 'Z'`.
- **Default `limit=100`** for all templates returning lists, overridable per-call. Prevents unbounded responses.
- **Entity-family scope validation** — templates declare accepted entity families; `execute()` raises on out-of-scope input.
- **Tool descriptions state primary-key entity type explicitly** — agents must be able to distinguish overlapping queries from the MCP tool listing alone.

## Typed Result Contract

```python
@dataclass
class QueryContext:
    crosswalk: Crosswalk
    connector_registry: ConnectorRegistry
    engine: ...  # relational calculus functions

@dataclass
class QueryResultMetadata:
    template_name: str
    template_version: str
    execution_timestamp: str                    # RFC 3339
    subsystem_status: dict[str, str]           # connector_name -> ok/unavailable/partial/timeout
    data_freshness: dict[str, str]             # connector_name -> last_harvest RFC 3339
    unresolved_entities: list[str]             # IDs that couldn't be resolved
    staleness_warnings: list[str]              # human-readable
    crosswalk_snapshot_age_seconds: int

@dataclass
class QueryResult:
    entities: list[dict]           # flat list, canonical IDs as strings
    relationships: list[dict]      # flat list, source/target as canonical ID strings
    metadata: QueryResultMetadata  # typed, not dict[str, Any]
```

Templates return flat, parallel lists — never nested. Template-specific extensions go in `metadata`.

## Open Questions

1. ~~**Go ↔ Python bridge**~~ — **Resolved: persistent Python worker process** with JSON-RPC over stdin/stdout. Go adapter discovers templates dynamically via `list_templates` call at startup.
2. **Caching**: Templates must not cache — catalog-of-catalogs principle. Defer any result caching to F6 (salience layer).
3. **Parameter validation**: Use JSON Schema for parameter definitions (matches MCP tool schema format). `canonical_id` parameters include pattern hint: `"^[a-z-]+:.+"`.
4. **Pagination**: Default `limit=100`. Cursor-based pagination for timeline queries (limit/offset is fragile against insertions). Full pagination design deferred to F6.
5. **Reverse-direction queries**: All 8 initial templates are forward lookups (entity → context). Add `entities_by_relationship` to the F6 roadmap for inverse queries.
6. **Event kind discrimination**: `entity_timeline` must distinguish `"ontology_change"` from `"infrastructure_sync"` events to avoid re-harvest noise.
7. **Error policy per template**: Templates declare fail-fast vs best-effort. Pure engine queries (entity_relationships) fail-fast; multi-connector queries (bead_context) use best-effort with `subsystem_status` marking.
8. **Template versioning**: Add `version: str` to `QueryTemplate` ABC and `schema_version` to `QueryResult` for safe evolution.
