---
artifact_type: plan
bead: Sylveste-xk68
stage: planned
---

# Plan: Khouri Core Domain Model with CLA Layer Provenance

**PRD:** docs/prds/2026-03-20-khouri-domain-model.md
**Scope:** `apps/Khouri/src/khouri/models.py` + `apps/Khouri/tests/test_models.py`

## Assessment

- Leaf bead under Sylveste-31g4 (Khouri epic), P0 blocker for all pipeline stages
- Clean Python scaffold exists: pydantic, networkx already in deps, mypy strict, ruff lint
- No existing models.py — greenfield within established project structure
- Risk: low — pure types, no IO, no external deps beyond what's installed

## Tasks

### Task 1: Create models.py with CLA core types
**File:** `apps/Khouri/src/khouri/models.py`
**What:**
- Type aliases: `Confidence = Annotated[float, Field(ge=0.0, le=1.0)]`, `Weight = Annotated[float, Field(ge=0.0)]`
- `CLALayer(str, Enum)` — LITANY, SOCIAL_CAUSES, DISCOURSE_WORLDVIEW, MYTH_METAPHOR
- `CLA_DEPTH_ORDER: Final[list[CLALayer]]` — index 0 = deepest (myth), index -1 = surface (litany)
- `EdgeRelationship(str, Enum)` — CAUSES, REINFORCES, INHIBITS (small closed set)
- `CLADecomposition(BaseModel)` — `layers: dict[CLALayer, str]` (layer → content text)
- `CLAEdge(BaseModel)` — `source_layer: CLALayer`, `target_layer: CLALayer`, `relationship: EdgeRelationship`, `weight: Weight = 1.0`
- `CLAGraph` — wraps `nx.DiGraph` (field annotated as `Any` for mypy strict), typed `add_node`/`add_causal_edge`/`causal_predecessors`/`causal_descendants`/`get_edges_by_layer` methods

**Verify:** `uv run python -c "from khouri.models import CLALayer, CLAGraph"`

### Task 2: Add causal and forecast models
**File:** `apps/Khouri/src/khouri/models.py` (append)
**What:**
- `CausalClaim(BaseModel)` — `cause: str`, `effect: str`, `source_layer: CLALayer`, `target_layer: CLALayer`, `confidence: Confidence`, `evidence: str = ""`
- `DomainForecast(BaseModel)` — `domain: str` (free string, not enum — adapters define taxonomy), `scenarios: list[str]`, `time_horizon: str`
- `StructuredForecast(BaseModel)` — `forecasts: list[DomainForecast]`, `generated_at: datetime` (default: `datetime.now(timezone.utc)`), `source_decomposition: CLADecomposition | None = None`

**Verify:** `uv run python -c "from khouri.models import CausalClaim, StructuredForecast"`

### Task 3: Add ontology and gap models
**File:** `apps/Khouri/src/khouri/models.py` (append)
**What:**
- `MappingConfidence(BaseModel)` — `score: Confidence`, `method: str`
- `OntologyMapping(BaseModel)` — `source_concept: str`, `target_entities: list[str]`, `cla_layer: CLALayer`, `confidence: MappingConfidence`
- `GapType(str, Enum)` — MISSING_DATA, MISSING_CAUSAL_LINK, MISSING_DISCOURSE_FRAME, MISSING_NARRATIVE_ARCHETYPE, WORLDVIEW_CONFLICT, ONTOLOGY_MISMATCH
- `Gap(BaseModel)` — `gap_type: GapType`, `cla_layer: CLALayer`, `description: str`, `severity: Confidence`
- `GapReport(BaseModel)` — `gaps_by_layer: dict[CLALayer, list[Gap]]`, `resolution_order` as `@computed_field` property (sorted by CLA_DEPTH_ORDER, myth-first — not caller-populated)

**Verify:** `uv run python -c "from khouri.models import GapReport, GapType"`

### Task 4: Write comprehensive tests
**File:** `apps/Khouri/tests/test_models.py`
**What:**
- CLALayer enum members and str serialization
- CLADecomposition creation and validation
- CLAEdge with cross-layer (source != target) and same-layer edges
- CLAGraph: add nodes, add edges, get_edges_by_layer filtering
- CausalClaim validation (confidence bounds 0-1, rejection of 1.5/-0.1, cross-layer claims)
- StructuredForecast with optional source_decomposition and UTC default
- OntologyMapping with coalition (multiple target_entities)
- GapType includes all three new discourse/narrative/worldview types
- GapReport.gaps_by_layer grouping and resolution_order depth ordering
- JSON round-trip serialization for all models

**Verify:** `cd apps/Khouri && uv run pytest tests/test_models.py -v`

### Task 5: Pass all quality gates
**What:**
- `cd apps/Khouri && make lint` — ruff check passes
- `cd apps/Khouri && make typecheck` — mypy strict passes
- `cd apps/Khouri && make test` — full test suite green with coverage

**Verify:** All three commands exit 0

### Task 0: Ruff config for CLA naming
**File:** `apps/Khouri/pyproject.toml`
**What:** Add `[tool.ruff.lint.pep8-naming]` with `extend-ignore-names = ["CLA*"]` to suppress N801 on CLA-prefix classes.

## Execution Order

Task 0 first (config). Tasks 1-3 sequential (each appends to models.py). Task 4 after all models. Task 5 last.

## Flux-Drive Review Incorporated

- Bounded floats use `Annotated[float, Field()]` type aliases (quality #2)
- GapReport.resolution_order is `@computed_field` not stored list (quality #3, arch M2)
- CLAGraph field annotated as `Any` with explicit comment for mypy strict (quality #1)
- ForecastDomain enum removed — domain is free `str` for adapter extensibility (arch O1)
- EdgeRelationship small enum replaces free `str` (quality #9)
- CLA_DEPTH_ORDER is `Final` with direction comment (quality #6)
- CLAGraph has thin accessor methods for future graph type changes (arch seam)

## Rollback

Delete `models.py` and `test_models.py`, revert pyproject.toml change — no other files modified.
