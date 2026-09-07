---
artifact_type: prd
bead: sylveste-5b7
stage: design
---

# PRD: F5 Named Query Templates (MCP Tools)

## Problem

Agents operating in the Sylveste ecosystem cannot access cross-system context without manually querying multiple subsystems (beads, cass, tldr-code) and joining the results. The interweave ontology layer has the domain primitives (engine, crosswalk, connectors) but no agent-facing query surface.

## Solution

A template layer that exposes interweave's cross-system ontology as 8 individual MCP tools. Each named query is a Python `QueryTemplate` protocol class registered into a `TemplateRegistry`, invocable by agents as standard MCP tools with typed parameters and structured `QueryResult` responses.

## Features

### F1: QueryTemplate Protocol + TemplateRegistry

**What:** Define the `QueryTemplate` ABC, `QueryContext`, `QueryResult`, `QueryResultMetadata` dataclasses, and `TemplateRegistry` with collision detection.

**Acceptance criteria:**
- [ ] `QueryTemplate` ABC has `name`, `description`, `version`, `accepted_families`, `parameters_schema()`, `error_policy` (fail-fast/best-effort), and `execute(context: QueryContext) -> QueryResult`
- [ ] `QueryContext` bundles `Crosswalk`, `ConnectorRegistry`, and engine references
- [ ] `QueryResult` has typed `entities`, `relationships`, `metadata` fields — flat parallel lists
- [ ] `QueryResultMetadata` has `subsystem_status`, `data_freshness`, `unresolved_entities`, `staleness_warnings`, `crosswalk_snapshot_age_seconds`, `template_version`, `execution_timestamp`
- [ ] `TemplateRegistry.register()` raises `ValueError` on name collision
- [ ] `TemplateRegistry.reset()` clears all templates (test isolation)
- [ ] `QueryResult.validate()` checks relationship endpoints exist in entities list
- [ ] `QueryResult.to_dict()` serializes all fields to JSON-safe types (CanonicalID as string, datetimes as RFC 3339)
- [ ] Unit tests cover: registration, collision, reset, validate, to_dict round-trip

### F2: Go-Python Persistent Worker Bridge

**What:** A persistent Python subprocess that the Go MCP adapter communicates with via JSON-RPC over stdin/stdout, supporting dynamic template discovery.

**Acceptance criteria:**
- [ ] Python worker entrypoint (`python -m interweave.worker`) starts and stays alive
- [ ] JSON-RPC protocol: `list_templates` returns all registered template names + schemas
- [ ] JSON-RPC protocol: `execute_template` dispatches to named template with parameters
- [ ] Newline-delimited JSON framing — no pipe buffer deadlock on large responses
- [ ] Stderr captured separately for error logging, never mixed into stdout JSON
- [ ] Concurrent invocations handled (requests include an `id` field for correlation)
- [ ] Graceful shutdown on SIGTERM
- [ ] Go adapter calls `list_templates` at startup and registers MCP tools dynamically
- [ ] Integration test: Go spawns worker, lists templates, executes a template, verifies result

### F3: Core Query Templates (4 pure queries)

**What:** Four templates that compose engine + crosswalk without live connector calls: `entity_relationships`, `evidence_for_entity`, `related_artifacts`, `entity_timeline`.

**Acceptance criteria:**
- [ ] `entity_relationships`: Given canonical ID, returns materialized relationships from crosswalk (not just type names). Validates entity-family scope. Fail-fast error policy.
- [ ] `evidence_for_entity`: Given canonical ID, returns Evidence-family entities via evidence-production rule. Validates input exists in crosswalk.
- [ ] `related_artifacts`: Given artifact canonical ID, returns structurally related artifacts via structure rule. `max_results=20` default. Validates Artifact-family scope.
- [ ] `entity_timeline`: Given canonical ID, returns chronological events with `event_kind` field (`ontology_change` vs `infrastructure_sync`). Default `limit=100`.
- [ ] All templates use `resolve_entity()` from shared primitives (F5)
- [ ] All templates return typed `QueryResult` with populated `QueryResultMetadata`
- [ ] Each template has unit tests + one integration test with multi-subsystem crosswalk fixture

### F4: Multi-Connector Query Templates (4 composite queries)

**What:** Four templates requiring cross-connector fan-out with partial result handling: `session_actors_for_file`, `bead_context`, `session_entities`, `actor_activity`.

**Acceptance criteria:**
- [ ] `session_actors_for_file`: Given file path, resolves via `normalize_path()` + `Crosswalk.resolve('tldr-code', ...)`, returns actors from cass sessions. Tool description explicitly states "session-tracked actors only." Failed resolution returns typed error, not empty result.
- [ ] `bead_context`: Given bead ID, returns full context graph. Best-effort error policy. `subsystem_status` populated per connector.
- [ ] `session_entities`: Given session ID, returns all entities. `unresolved_entities` populated for crosswalk misses.
- [ ] `actor_activity`: Given actor identifier, returns recent activity. `data_freshness` populated per connector.
- [ ] All multi-connector templates fan out in parallel via `concurrent.futures.ThreadPoolExecutor`
- [ ] Partial results always marked in `subsystem_status` — agents can distinguish "no data" from "connector unavailable"
- [ ] `data_freshness` dict shows last-harvest timestamp per contributing connector
- [ ] Each template has unit tests + one integration test with multi-connector fixture (including a simulated connector failure)

### F5: Shared Resolution Primitives

**What:** A `templates/_resolve.py` module with `resolve_entity()`, path normalization, and entity-family scope validation used by all templates.

**Acceptance criteria:**
- [ ] `resolve_entity(crosswalk, subsystem, native_id)` returns canonical ID or raises `ResolutionError` (never returns None silently)
- [ ] `resolve_file_entity(crosswalk, path)` normalizes via `resolve_file.normalize_path()` then resolves
- [ ] `validate_entity_family(crosswalk, canonical_id, accepted_families)` raises `EntityFamilyScopeError` on mismatch
- [ ] All resolution functions are used by F3 and F4 templates — no inline resolution logic
- [ ] Unit tests cover: successful resolution, missing entity, wrong family, path normalization edge cases (relative, absolute, trailing slash, symlink)

## Non-goals

- Query result caching (catalog-of-catalogs principle — deferred to F6 salience layer)
- Reverse-direction queries (entities_by_relationship — deferred to F6)
- Query composition / chaining (F6 territory)
- New connector development (existing beads, cass, tldr-code connectors are sufficient)
- MCP tool authentication or rate limiting

## Dependencies

- F3 (connector protocol) — **done** (sylveste-qo8, closed)
- F2 (identity crosswalk) — crosswalk.py, storage.py, resolve_*.py exist
- F1 (type families) — families.py, rules.py, engine.py exist
- Go MCP adapter exists at `internal/adapter/mcp.go`
- attp dependency (`github.com/mistakeknot/attp`)

## Open Questions

1. **Template versioning migration path** — When a template's output schema evolves, how do agents on the old schema handle it? Version field exists but no migration protocol defined. Defer to F7.
2. **Cursor-based pagination** — Default limit=100 is set, but cursor implementation for timeline queries needs design. Defer details to F6.
