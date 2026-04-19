---
artifact_type: plan
bead: sylveste-5b7
prd: docs/prds/2026-04-07-interweave-f5-named-query-templates.md
stage: planned
---

# Implementation Plan: F5 Named Query Templates

## Build Order

F5.5 (resolution primitives) → F5.1 (protocol + registry) → F5.3 (core templates) → F5.4 (multi-connector templates) → F5.2 (Go-Python bridge)

Rationale: Resolution primitives are used by all templates. The protocol must exist before templates. Core (pure) templates are simpler and validate the protocol before composite queries add connector fan-out. The Go bridge is last because it wraps the Python layer — it needs working templates to integrate against.

## Task 1: Shared Resolution Primitives (F5.5: sylveste-j0yv)

**Files to create:**
- `src/interweave/templates/__init__.py` — empty package init
- `src/interweave/templates/_resolve.py` — resolution functions

**Files to modify:**
- None (new package)

**Implementation:**

```python
# src/interweave/templates/_resolve.py

class ResolutionError(Exception):
    """Entity could not be resolved in the crosswalk."""
    def __init__(self, subsystem: str, native_id: str):
        self.subsystem = subsystem
        self.native_id = native_id
        super().__init__(f"Cannot resolve {subsystem}:{native_id}")

class EntityFamilyScopeError(Exception):
    """Entity family does not match template's accepted families."""
    def __init__(self, canonical_id: str, actual_family: str, accepted: list[str]):
        self.canonical_id = canonical_id
        self.actual_family = actual_family
        self.accepted = accepted
        super().__init__(f"{canonical_id} is {actual_family}, expected one of {accepted}")

def resolve_entity(crosswalk, subsystem: str, native_id: str) -> str:
    """Resolve subsystem:native_id to canonical ID. Raises ResolutionError on miss."""
    result = crosswalk.resolve(subsystem, native_id)
    if result is None:
        raise ResolutionError(subsystem, native_id)
    return result

def resolve_file_entity(crosswalk, path: str) -> str:
    """Normalize path then resolve via tldr-code subsystem."""
    from interweave.resolve_file import normalize_path
    normalized = normalize_path(path)
    return resolve_entity(crosswalk, "tldr-code", normalized)

def validate_entity_family(crosswalk, canonical_id: str, accepted_families: list[str]) -> dict:
    """Validate entity exists and is in accepted families. Returns entity dict."""
    entity = crosswalk.get(canonical_id)
    if entity is None:
        raise ResolutionError("crosswalk", canonical_id)
    if entity["family"] not in accepted_families:
        raise EntityFamilyScopeError(canonical_id, entity["family"], accepted_families)
    return entity
```

**Tests:** `tests/test_resolve_primitives.py`
- Test `resolve_entity` success, missing entity
- Test `resolve_file_entity` with various path forms (relative, `./`, `../`, trailing `/`, symlink via `os.path.realpath`)
- Test `validate_entity_family` success, wrong family, missing entity
- Use in-memory CrosswalkDB with seeded entities

**Verification:** `uv run pytest tests/test_resolve_primitives.py -v`

## Task 2: QueryTemplate Protocol + TemplateRegistry (F5.1: sylveste-mf6n)

**Files to create:**
- `src/interweave/templates/protocol.py` — ABC, dataclasses, registry

**Files to modify:**
- `src/interweave/__init__.py` — export new public API

**Implementation:**

```python
# src/interweave/templates/protocol.py

from __future__ import annotations
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Any

class ErrorPolicy(Enum):
    FAIL_FAST = "fail_fast"
    BEST_EFFORT = "best_effort"

@dataclass
class QueryContext:
    crosswalk: Any  # Crosswalk
    connector_registry: Any  # ConnectorRegistry
    # engine functions accessed via module import

@dataclass
class QueryResultMetadata:
    template_name: str
    template_version: str
    execution_timestamp: str  # RFC 3339
    subsystem_status: dict[str, str] = field(default_factory=dict)
    data_freshness: dict[str, str] = field(default_factory=dict)
    unresolved_entities: list[str] = field(default_factory=list)
    staleness_warnings: list[str] = field(default_factory=list)
    crosswalk_snapshot_age_seconds: int = 0

@dataclass
class QueryResult:
    entities: list[dict[str, Any]]
    relationships: list[dict[str, Any]]
    metadata: QueryResultMetadata

    def validate(self) -> list[str]:
        """Check consistency. Returns list of issues (empty = valid)."""
        issues = []
        entity_ids = {e.get("canonical_id") for e in self.entities}
        for rel in self.relationships:
            for endpoint in ("source", "target"):
                eid = rel.get(endpoint)
                if eid and eid not in entity_ids:
                    issues.append(f"Relationship {endpoint} '{eid}' not in entities list")
        return issues

    def to_dict(self) -> dict[str, Any]:
        """Serialize to JSON-safe dict. CanonicalIDs as strings, datetimes as RFC 3339."""
        return {
            "entities": self.entities,
            "relationships": self.relationships,
            "metadata": {
                "template_name": self.metadata.template_name,
                "template_version": self.metadata.template_version,
                "execution_timestamp": self.metadata.execution_timestamp,
                "subsystem_status": self.metadata.subsystem_status,
                "data_freshness": self.metadata.data_freshness,
                "unresolved_entities": self.metadata.unresolved_entities,
                "staleness_warnings": self.metadata.staleness_warnings,
                "crosswalk_snapshot_age_seconds": self.metadata.crosswalk_snapshot_age_seconds,
            },
        }

class QueryTemplate(ABC):
    @property
    @abstractmethod
    def name(self) -> str: ...

    @property
    @abstractmethod
    def description(self) -> str: ...

    @property
    @abstractmethod
    def version(self) -> str: ...

    @property
    @abstractmethod
    def accepted_families(self) -> list[str]:
        """Entity families this template accepts. Empty = any."""
        ...

    @property
    @abstractmethod
    def error_policy(self) -> ErrorPolicy: ...

    @abstractmethod
    def parameters_schema(self) -> dict[str, Any]:
        """JSON Schema for this template's parameters."""
        ...

    @abstractmethod
    def execute(self, context: QueryContext, **params: Any) -> QueryResult: ...

class TemplateRegistry:
    def __init__(self) -> None:
        self._templates: dict[str, QueryTemplate] = {}

    def register(self, template: QueryTemplate) -> None:
        if template.name in self._templates:
            raise ValueError(
                f"Template '{template.name}' already registered "
                f"(existing: {self._templates[template.name].__class__.__name__})"
            )
        self._templates[template.name] = template

    def get(self, name: str) -> QueryTemplate | None:
        return self._templates.get(name)

    def list(self) -> list[QueryTemplate]:
        return list(self._templates.values())

    def reset(self) -> None:
        self._templates.clear()
```

**Tests:** `tests/test_template_protocol.py`
- TemplateRegistry: register, get, list, collision raises ValueError, reset clears
- QueryResult.validate(): valid result, missing endpoint, empty result
- QueryResult.to_dict(): round-trip, CanonicalID as string, datetime format

**Verification:** `uv run pytest tests/test_template_protocol.py -v`

## Task 3: Core Query Templates — entity_relationships + evidence_for_entity (F5.3 part 1)

**Files to create:**
- `src/interweave/templates/entity_relationships.py`
- `src/interweave/templates/evidence_for_entity.py`

**Implementation notes:**

`entity_relationships`: Takes `canonical_id` param. Validates via `validate_entity_family()`. Queries crosswalk for linked entities. Uses engine `valid_relationships()` to determine valid relationship types for the entity's family pairs. Returns materialized edges (not just type names). Fail-fast error policy.

`evidence_for_entity`: Takes `canonical_id` param. Queries crosswalk for Evidence-family entities that reference the input. Uses the evidence-production interaction rule. Fail-fast.

Both templates populate `QueryResultMetadata` with `crosswalk_snapshot_age_seconds` from the entity's `updated_at` field.

**Tests:** `tests/test_templates_core.py` (first half)
- Each template: valid query with seeded crosswalk data, missing entity, wrong family
- Integration test with multi-entity crosswalk fixture

**Verification:** `uv run pytest tests/test_templates_core.py -v`

## Task 4: Core Query Templates — related_artifacts + entity_timeline (F5.3 part 2)

**Files to create:**
- `src/interweave/templates/related_artifacts.py`
- `src/interweave/templates/entity_timeline.py`

**Implementation notes:**

`related_artifacts`: Takes `canonical_id` + optional `max_results` (default 20). Validates Artifact-family scope. Queries crosswalk for structurally related artifacts via structure interaction rule (`imports`, `depends-on`, `references`, `blocks`, `parent-child`). Fail-fast.

`entity_timeline`: Takes `canonical_id` + optional `limit` (default 100). Queries crosswalk entity history + identity chains. Each timeline entry has `event_kind` field (`ontology_change` or `infrastructure_sync`). Events sorted chronologically.

**Tests:** `tests/test_templates_core.py` (second half)
- `related_artifacts`: max_results respected, Artifact-family validation
- `entity_timeline`: limit respected, event_kind classification, chronological ordering
- Integration test with identity chain fixture

**Verification:** `uv run pytest tests/test_templates_core.py -v`

## Task 5a: Multi-Connector Template — bead_context (F5.4 part 1a)

**Files to create:**
- `src/interweave/templates/bead_context.py`

**Implementation notes:**

`bead_context`: Takes `bead_id` param. Fans out to beads + cass + crosswalk. Returns full context graph: related files, sessions, actors, findings, dependencies. Best-effort with `subsystem_status` per connector. Uses `ThreadPoolExecutor` for parallel fan-out. `data_freshness` populated per connector.

**Key pattern:** Uses `concurrent.futures.ThreadPoolExecutor(max_workers=3)` for parallel connector calls. Each connector call wrapped in try/except, failures recorded in `subsystem_status` as `"unavailable"` or `"timeout"`.

**Tests:** `tests/test_template_bead_context.py`
- Valid bead with multi-connector data
- One connector fails (partial result with `subsystem_status` marking)
- All connectors fail (empty result, all statuses marked)
- Verify `data_freshness` populated per connector
- Mock connectors that return controlled HarvestResult or raise

**Verification:** `uv run pytest tests/test_template_bead_context.py -v`

## Task 5b: Multi-Connector Template — session_actors_for_file (F5.4 part 1b)

**Files to create:**
- `src/interweave/templates/session_actors_for_file.py`

**Implementation notes:**

`session_actors_for_file`: Takes `file_path` param. Resolves via `resolve_file_entity()`. Fans out to cass connector for sessions that touched the file, then resolves actors from those sessions. Tool description: "Given a file path, returns session-tracked actors that modified it. Does not cover non-session modifications." Best-effort. `subsystem_status` populated.

**Tests:** `tests/test_templates_composite.py` (first half)
- `session_actors_for_file`: valid file, missing file (ResolutionError), cass unavailable (partial result with status), verify `data_freshness` populated
- Mock connectors that return controlled HarvestResult or raise

**Verification:** `uv run pytest tests/test_templates_composite.py -v`

## Task 6: Multi-Connector Templates — session_entities + actor_activity (F5.4 part 2)

**Files to create:**
- `src/interweave/templates/session_entities.py`
- `src/interweave/templates/actor_activity.py`

**Implementation notes:**

`session_entities`: Takes `session_id` param. Resolves session via cass subsystem. Returns all entities touched: files, beads, findings. `unresolved_entities` populated for crosswalk misses. Best-effort.

`actor_activity`: Takes `actor_id` param (agent name or human username). Resolves via actor resolution. Returns recent activity across subsystems. `data_freshness` populated per connector. Default `limit=100`. Best-effort.

**Tests:** `tests/test_templates_composite.py` (second half)
- `session_entities`: valid session, unresolved entities reported, cass down
- `actor_activity`: valid actor, data_freshness populated, limit respected

**Verification:** `uv run pytest tests/test_templates_composite.py -v`

## Task 7: Template Registration + Package Wiring

**Files to modify:**
- `src/interweave/templates/__init__.py` — register all 8 templates into a default registry
- `src/interweave/__init__.py` — export `TemplateRegistry`, `QueryTemplate`, `QueryResult`, `QueryContext`

**Implementation:**

```python
# src/interweave/templates/__init__.py
"""Named query templates for the interweave ontology layer."""

from interweave.templates.protocol import (
    QueryContext,
    QueryResult,
    QueryResultMetadata,
    QueryTemplate,
    TemplateRegistry,
    ErrorPolicy,
)

_registry = TemplateRegistry()

def get_default_registry() -> TemplateRegistry:
    return _registry

def _register_builtins() -> None:
    from interweave.templates.entity_relationships import EntityRelationshipsTemplate
    from interweave.templates.evidence_for_entity import EvidenceForEntityTemplate
    from interweave.templates.related_artifacts import RelatedArtifactsTemplate
    from interweave.templates.entity_timeline import EntityTimelineTemplate
    from interweave.templates.session_actors_for_file import SessionActorsForFileTemplate
    from interweave.templates.bead_context import BeadContextTemplate
    from interweave.templates.session_entities import SessionEntitiesTemplate
    from interweave.templates.actor_activity import ActorActivityTemplate

    for cls in [
        EntityRelationshipsTemplate,
        EvidenceForEntityTemplate,
        RelatedArtifactsTemplate,
        EntityTimelineTemplate,
        SessionActorsForFileTemplate,
        BeadContextTemplate,
        SessionEntitiesTemplate,
        ActorActivityTemplate,
    ]:
        _registry.register(cls())

_register_builtins()
```

**Tests:** `tests/test_template_registration.py`
- Default registry has 8 templates
- All names unique
- `get_default_registry()` returns populated registry

**Verification:** `uv run pytest tests/test_template_registration.py -v`

## Task 8: Python Worker Process (F5.2: sylveste-34r2, Python side)

**Files to create:**
- `src/interweave/worker.py` — JSON-RPC worker entrypoint

**Implementation:**

Worker reads newline-delimited JSON requests from stdin, dispatches to template registry, writes newline-delimited JSON responses to stdout. Stderr used for logging only.

Protocol:
```json
// Request
{"jsonrpc": "2.0", "method": "list_templates", "id": 1}
{"jsonrpc": "2.0", "method": "execute_template", "params": {"name": "bead_context", "params": {"bead_id": "sylveste-5b7"}}, "id": 2}

// Response
{"jsonrpc": "2.0", "result": [...], "id": 1}
{"jsonrpc": "2.0", "result": {...}, "id": 2}
{"jsonrpc": "2.0", "error": {"code": -1, "message": "..."}, "id": 3}
```

Worker initializes: CrosswalkDB (path from env or default), ConnectorRegistry with all connectors, TemplateRegistry via `get_default_registry()`, QueryContext from these.

Handles SIGTERM for graceful shutdown. Each request processed synchronously (concurrent invocations handled by separate Go goroutines spawning separate requests with unique IDs).

**Tests:** `tests/test_worker.py`
- Spawn worker subprocess, send `list_templates`, verify 8 templates returned
- Send `execute_template` with mock crosswalk data, verify QueryResult structure
- Send invalid method, verify error response
- Send malformed JSON, verify error response (not crash)

**Verification:** `uv run pytest tests/test_worker.py -v`

## Task 9: Go MCP Adapter Integration (F5.2: sylveste-34r2, Go side)

**Files to modify:**
- `internal/adapter/mcp.go` — add worker lifecycle + tool registration
- `internal/adapter/mcp_test.go` — add integration test

**Implementation notes:**

Add to Adapter:
- `workerCmd *exec.Cmd` — persistent Python worker process
- `workerStdin io.Writer`, `workerStdout *bufio.Scanner` — JSON-RPC communication
- `StartWorker(ctx context.Context) error` — spawns `python -m interweave.worker`, calls `list_templates`, registers MCP tools
- `StopWorker() error` — sends SIGTERM, waits
- `callWorker(method string, params map[string]any) (json.RawMessage, error)` — JSON-RPC call with timeout

On `StartWorker()`:
1. Spawn Python worker
2. Call `list_templates` — get template names + schemas
3. For each template, register an MCP tool on the attp server with the template's name, description, and parameter schema
4. Tool handler calls `execute_template` via `callWorker()`

**Tests:** `internal/adapter/mcp_test.go` additions
- `TestWorkerStartStop` — verify worker starts and responds to list_templates
- `TestWorkerExecuteTemplate` — verify end-to-end MCP tool call → worker → result

**Verification:** `cd interverse/interweave && go test ./internal/adapter/ -v -run TestWorker`

## Task 10: Wiring, Integration Test + Cleanup

**Files to create:**
- `tests/test_integration_templates.py` — end-to-end integration tests

**Files to modify:**
- `src/interweave/templates/__init__.py` — register all 8 templates into default registry (Task 7 merged here)
- `src/interweave/__init__.py` — export `TemplateRegistry`, `QueryTemplate`, `QueryResult`, `QueryContext`

**Implementation:**

Register all 8 templates in `templates/__init__.py` (see Task 7 code in plan above).

Fixture seeds a CrosswalkDB with entities from multiple subsystems (beads, cass, tldr-code), creates connectors, and exercises all 8 templates through the full stack:
1. Seed crosswalk with 5+ entities across 3 subsystems
2. Call each template via the registry
3. Verify QueryResult structure, metadata completeness, relationship consistency
4. Test partial failure (mock one connector unavailable)
5. Verify `subsystem_status` and `data_freshness` populated correctly

**Resolve enforcement check:** Grep all template files (`src/interweave/templates/*.py`, excluding `_resolve.py` and `protocol.py`) and assert no direct `crosswalk.resolve()` or `crosswalk.get()` calls — all resolution must go through `_resolve.py` functions. Add as test in `test_integration_templates.py`.

Also:
- Run `uv run ruff check src/` — fix any lint issues
- Run full test suite: `uv run pytest tests/ -v`

**Verification:** `uv run pytest tests/ -v && uv run ruff check src/`

## Execution Notes

- Tasks 1-2 are foundation — must complete before 3-6
- Tasks 3-4 (core templates) and 5a-5b-6 (composite templates) can run in parallel after Tasks 1-2
- Task 5a (bead_context) is the most complex single template — split out for focused implementation
- Task 8 (Python worker) depends on all templates (3-6)
- Task 9 (Go integration) depends on Task 8
- Task 10 (wiring + integration tests) depends on everything

**Estimated files:** 12 new Python files, 1 modified Go file, 8 test files
