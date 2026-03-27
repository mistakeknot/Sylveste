---
artifact_type: prd
bead: Sylveste-xk68
stage: design
---

# PRD: Khouri Core Domain Model with CLA Layer Provenance

## Problem

Khouri's 10-stage pipeline has no shared type system. Each stage would need to define its own representations for CLA layers, causal claims, ontology mappings, and gaps — leading to incompatible interfaces and lost layer provenance.

## Solution

A single `models.py` with Pydantic v2 models that thread CLA layer identity through the entire type graph. Every downstream stage imports from this module, ensuring layer provenance is preserved from decomposition through gap reporting.

## Features

### F1: CLA Core Types
**What:** CLALayer enum and graph primitives for CLA decomposition.
**Acceptance criteria:**
- [ ] CLALayer str enum with LITANY, SOCIAL_CAUSES, DISCOURSE_WORLDVIEW, MYTH_METAPHOR
- [ ] CLADecomposition model with layer → content mapping
- [ ] CLAEdge with source_layer, target_layer, relationship, weight
- [ ] CLAGraph wrapping networkx DiGraph with typed node/edge access
- [ ] All models validate with Pydantic v2, serialize to/from JSON

### F2: Causal & Forecast Models
**What:** CausalClaim with cross-layer provenance, forecast domain and structured output types.
**Acceptance criteria:**
- [ ] CausalClaim with cause, effect, source_layer, target_layer, confidence, evidence
- [ ] ForecastDomain enum for scenario families
- [ ] DomainForecast with domain, scenarios list, time_horizon
- [ ] StructuredForecast aggregating DomainForecasts with metadata
- [ ] Cross-layer claims (source_layer != target_layer) are valid

### F3: Ontology & Gap Models
**What:** Ontology mapping types with coalition support and CLA-aware gap classification.
**Acceptance criteria:**
- [ ] MappingConfidence with score float + method str
- [ ] OntologyMapping with source_concept, target_entities list, cla_layer, confidence
- [ ] GapType enum including MISSING_DISCOURSE_FRAME, MISSING_NARRATIVE_ARCHETYPE, WORLDVIEW_CONFLICT
- [ ] Gap with gap_type, cla_layer, description, severity
- [ ] GapReport with gaps_by_layer dict (CLALayer → list[Gap]) + resolution_order list
- [ ] GapReport.resolution_order respects CLA depth ordering (myth → litany)

## Non-goals

- Pipeline orchestration (separate bead: Sylveste-hmo7)
- LLM integration or API calls (Stage 1 bead: Sylveste-gbm7)
- Persistence/database layer
- CLI commands (separate bead: Sylveste-n497)

## Dependencies

- pydantic>=2.0 (already in pyproject.toml)
- networkx>=3.0 (already in pyproject.toml)
- No new dependencies required

## Open Questions

None blocking — start simple, iterate.
